<#
.SYNOPSIS
  Bring up the services in docker-compose.yaml with `podman compose`, then run each
  service's post-startup actions.

.DESCRIPTION
  1. `podman compose up -d` for everything in docker-compose.yaml.
  2. Runs one post-startup function per service (see the "Post-startup" section).
     Currently:
       - Nexus: decides which admin password to use: -NexusAdminPassword if given, else
         nexus_admin_password from nexus-tf/terraform.auto.tfvars.json, else (file not
         found) it stops before starting anything; the VS Code task "Compose: first-time
         setup (set Nexus admin password)" asks for the password via its input prompt and
         passes it as -NexusAdminPassword. It waits for
         the REST API, then checks whether admin's password is already that password.
         If not, Nexus is assumed to still be on its initial (first-run generated)
         password: it is read from /nexus-data/admin.password inside the container, used
         to log in, and then changed to the chosen password via the REST API. It then
         accepts the Nexus license
         agreement (EULA) if that has not been done yet, and disables anonymous access
         (the first-login wizard's anonymous-access question). All of nexus-tf's variable
         values (URL, admin user, password) are written to
         nexus-tf/terraform.auto.tfvars.json (gitignored) so `terraform apply` in
         nexus-tf picks them up automatically.
       - Jenkins: before compose starts, generates the admin and agent-connector
         passwords into jenkins/secrets/ (gitignored) if they do not exist yet, since
         JCasC reads them at startup. After startup it waits for the controller and
         checks that the JCasC-defined node "agent" is connected.

  3. Finally runs scripts/Apply-Terraform.ps1, which applies every "<system>-tf" module
     (currently nexus-tf) so the systems' internal resources match the code.

  To add a service: add it to docker-compose.yaml, write an Initialize-<Service>
  function below, and call it from the bottom of the script (before the Terraform step).

  Everything is idempotent: re-running just re-verifies each service.

.EXAMPLE
  ./scripts/Start-Services.ps1
  ./scripts/Start-Services.ps1 -NexusAdminPassword 'something-else' -NexusTimeoutSeconds 600

.NOTES
  Kept ASCII-only and Windows PowerShell 5.1 compatible on purpose (no BOM-less
  encoding switches, no non-ASCII characters).
#>
[CmdletBinding()]
param(
  [string]$NexusUrl            = 'http://localhost:8081',
  # URL as seen from the Terraform container (localhost there is the container itself).
  [string]$NexusTerraformUrl   = 'http://host.containers.internal:8081',
  # Optional. When omitted: read from nexus-tf/terraform.auto.tfvars.json. If that file does
  # not exist either, the script stops (it never prompts itself: password entry belongs to the
  # VS Code task input, see .vscode/tasks.json).
  [string]$NexusAdminPassword,
  [int]$NexusTimeoutSeconds    = 300,
  [string]$JenkinsUrl          = 'http://localhost:8080',
  [int]$JenkinsTimeoutSeconds  = 300
)

$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repoRoot 'docker-compose.yaml'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Get-HttpStatus([scriptblock]$Request) {
  # Returns the HTTP status code of a request instead of throwing on non-2xx.
  # Returns 0 when no HTTP response was received at all (connection refused, reset...).
  try {
    $null = & $Request
    return 200
  } catch {
    if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
    return 0
  }
}

function New-BasicAuthHeader([string]$User, [string]$Password) {
  $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${User}:${Password}"))
  return @{ Authorization = "Basic $token" }
}

# --- Compose ------------------------------------------------------------------
function Start-ComposeServices {
  # podman compose prints a provider banner on stderr. Under Windows PowerShell 5.1 a
  # native command's stderr becomes a terminating error when $ErrorActionPreference is
  # 'Stop' (redirecting it makes that certain), so relax it here and rely on exit codes.
  # The assignment is scoped to this function.
  $ErrorActionPreference = 'Continue'
  podman compose version *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "'podman compose' is not usable. It needs a compose provider (docker-compose or podman-compose) on PATH, and a running podman machine (podman machine start)."
  }

  # Bind-mount source of the helm-cicd service. Terraform (helm-access.tf) fills it later, but
  # compose needs the directory to exist now, on a fresh checkout before the first apply.
  New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot 'nexus-tf\helm-registry') | Out-Null

  New-JenkinsSecrets

  Write-Step "podman compose -f docker-compose.yaml up -d"
  podman compose -f $composeFile up -d
  if ($LASTEXITCODE -ne 0) { throw "podman compose up failed (exit $LASTEXITCODE)" }
}

# --- Post-startup: Nexus ------------------------------------------------------
function Test-NexusAdminLogin([string]$Url, [string]$Password) {
  $headers = New-BasicAuthHeader 'admin' $Password
  $status = Get-HttpStatus {
    Invoke-WebRequest -UseBasicParsing -Uri "$Url/service/rest/v1/security/users?userId=admin" -Headers $headers
  }
  if ($status -eq 200) { return $true }
  if ($status -eq 401) { return $false }
  throw "Unexpected HTTP status $status while checking admin credentials against $Url"
}

function Confirm-NexusEula([string]$Url, [hashtable]$Headers) {
  # Nexus 3.77+ (Community Edition) blocks most of the API until the EULA is accepted.
  # GET returns { accepted, disclaimer }; accepting means POSTing that same disclaimer
  # text back with accepted = true. Older Nexus versions have no such endpoint (404).
  $eulaUri = "$Url/service/rest/v1/system/eula"
  try {
    $eula = Invoke-RestMethod -UseBasicParsing -Uri $eulaUri -Headers $Headers
  } catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
      Write-Host "    this Nexus version has no EULA endpoint; nothing to accept."
      return
    }
    throw
  }

  if ($eula.accepted) {
    Write-Host "    license agreement already accepted."
    return
  }

  Write-Step "Nexus: accepting license agreement"
  $body = @{ accepted = $true; disclaimer = $eula.disclaimer } | ConvertTo-Json
  Invoke-RestMethod -UseBasicParsing -Method Post -Uri $eulaUri -Headers $Headers `
    -ContentType 'application/json' -Body $body | Out-Null

  if (-not (Invoke-RestMethod -UseBasicParsing -Uri $eulaUri -Headers $Headers).accepted) {
    throw "Posted the Nexus EULA acceptance but Nexus still reports it as not accepted."
  }
  Write-Host "    license agreement accepted."
}

function Disable-NexusAnonymousAccess([string]$Url, [hashtable]$Headers) {
  # This is the "Configure Anonymous Access" step of the first-login setup wizard.
  # GET returns { enabled, userId, realmName }; PUT the same shape back with enabled = false.
  $anonUri = "$Url/service/rest/v1/security/anonymous"
  $anon = Invoke-RestMethod -UseBasicParsing -Uri $anonUri -Headers $Headers

  if (-not $anon.enabled) {
    Write-Host "    anonymous access is already disabled."
    return
  }

  Write-Step "Nexus: disabling anonymous access"
  $body = @{ enabled = $false; userId = $anon.userId; realmName = $anon.realmName } | ConvertTo-Json
  Invoke-RestMethod -UseBasicParsing -Method Put -Uri $anonUri -Headers $Headers `
    -ContentType 'application/json' -Body $body | Out-Null

  if ((Invoke-RestMethod -UseBasicParsing -Uri $anonUri -Headers $Headers).enabled) {
    throw "Sent the request to disable Nexus anonymous access but Nexus still reports it as enabled."
  }
  Write-Host "    anonymous access disabled."
}

function Get-NexusTfvarsFile { Join-Path $repoRoot 'nexus-tf\terraform.auto.tfvars.json' }

function Resolve-NexusAdminPassword {
  # Order: -NexusAdminPassword (the VS Code "first-time setup" task passes the value typed
  # into its input prompt), else nexus_admin_password from the tfvars file written by a
  # previous run. VS Code task inputs cannot be conditional, so with neither this stops
  # instead of prompting, before anything is started.
  if ($NexusAdminPassword) { return $NexusAdminPassword }

  $tfvarsFile = Get-NexusTfvarsFile
  if (Test-Path -LiteralPath $tfvarsFile -PathType Leaf) {
    $saved = $null
    try { $saved = (Get-Content -LiteralPath $tfvarsFile -Raw | ConvertFrom-Json).nexus_admin_password } catch { }
    if ($saved) {
      Write-Host "    using the Nexus admin password from $tfvarsFile."
      return $saved
    }
  }
  throw "No Nexus admin password: $tfvarsFile is missing or has no nexus_admin_password. Run the VS Code task 'Compose: first-time setup (set Nexus admin password)' once, which asks for the password."
}

function Initialize-Nexus([string]$adminPassword) {
  $containerName = 'nexus'   # container_name in docker-compose.yaml
  $url           = $NexusUrl.TrimEnd('/')
  $tfvarsFile    = Get-NexusTfvarsFile

  Write-Step "Nexus: waiting for $url (timeout ${NexusTimeoutSeconds}s)"
  $deadline = (Get-Date).AddSeconds($NexusTimeoutSeconds)
  while ($true) {
    $status = Get-HttpStatus { Invoke-WebRequest -UseBasicParsing -Uri "$url/service/rest/v1/status" -TimeoutSec 5 }
    if ($status -eq 200) { break }
    if ((Get-Date) -gt $deadline) {
      throw "Nexus did not become ready within ${NexusTimeoutSeconds}s (last HTTP status: $status). Check: podman logs $containerName"
    }
    Start-Sleep -Seconds 5
  }
  Write-Host "    Nexus is up."

  Write-Step "Nexus: checking admin password"
  if (Test-NexusAdminLogin $url $adminPassword) {
    Write-Host "    admin password is already the configured one."
  } else {
    Write-Host "    admin is not using the configured password; looking for the initial (generated) one."
    $ErrorActionPreference = 'Continue'   # native stderr must not be terminating (see Start-ComposeServices)
    $generated = (podman exec $containerName cat /nexus-data/admin.password 2>$null)
    $execExit  = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($execExit -ne 0 -or -not $generated) {
      throw "Login with the configured password failed and /nexus-data/admin.password does not exist in '$containerName'. The admin password was changed to something unknown; reset it (or remove the nexus-data volume for a fresh Nexus) and re-run."
    }
    $generated = ($generated | Out-String).Trim()

    if (-not (Test-NexusAdminLogin $url $generated)) {
      throw "The password in /nexus-data/admin.password was rejected by Nexus."
    }

    Write-Step "Nexus: changing admin password"
    Invoke-WebRequest -UseBasicParsing -Method Put `
      -Uri "$url/service/rest/v1/security/users/admin/change-password" `
      -Headers (New-BasicAuthHeader 'admin' $generated) `
      -ContentType 'text/plain' -Body $adminPassword | Out-Null

    if (-not (Test-NexusAdminLogin $url $adminPassword)) {
      throw "Password change was accepted but login with the new password fails."
    }
    Write-Host "    admin password changed."
  }

  Write-Step "Nexus: checking license agreement (EULA)"
  Confirm-NexusEula $url (New-BasicAuthHeader 'admin' $adminPassword)

  Write-Step "Nexus: checking anonymous access"
  Disable-NexusAnonymousAccess $url (New-BasicAuthHeader 'admin' $adminPassword)

  Write-Step "Nexus: writing $tfvarsFile"
  $json = [ordered]@{
    nexus_url            = $NexusTerraformUrl
    nexus_admin_username = 'admin'
    nexus_admin_password = $adminPassword
  } | ConvertTo-Json
  # .NET call so the file has no BOM on Windows PowerShell 5.1 (Terraform rejects a BOM).
  [IO.File]::WriteAllText($tfvarsFile, $json, (New-Object Text.UTF8Encoding($false)))

  Write-Host "    Nexus ready at $url (user admin; password saved in $tfvarsFile). Next: apply nexus-tf (see nexus-tf/README.md)." -ForegroundColor Green
}

# --- Post-startup: Jenkins ----------------------------------------------------
function Get-JenkinsSecretsDir { Join-Path $repoRoot 'jenkins\secrets' }

function New-JenkinsSecrets {
  # Called before compose up: JCasC (jenkins/casc/jenkins.yaml) reads these files while
  # Jenkins starts, and both jenkins and jenkins-agent bind-mount the directory. Existing
  # files are never overwritten, so the passwords stay stable across runs.
  $dir = Get-JenkinsSecretsDir
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $alphabet = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  foreach ($name in 'admin-password', 'agent-connector-password') {
    $file = Join-Path $dir $name
    if (Test-Path -LiteralPath $file -PathType Leaf) { continue }
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    # No trailing newline and no BOM: JCasC's ${readFile:} and the agent use the content as is.
    [IO.File]::WriteAllText($file, $password, (New-Object Text.UTF8Encoding($false)))
    Write-Host "    generated $file"
  }
}

function Initialize-Jenkins {
  $containerName = 'jenkins'   # container_name in docker-compose.yaml
  $url           = $JenkinsUrl.TrimEnd('/')
  $adminFile     = Join-Path (Get-JenkinsSecretsDir) 'admin-password'

  Write-Step "Jenkins: waiting for $url (timeout ${JenkinsTimeoutSeconds}s)"
  $deadline = (Get-Date).AddSeconds($JenkinsTimeoutSeconds)
  while ($true) {
    $status = Get-HttpStatus { Invoke-WebRequest -UseBasicParsing -Uri "$url/login" -TimeoutSec 5 }
    if ($status -eq 200) { break }
    if ((Get-Date) -gt $deadline) {
      throw "Jenkins did not become ready within ${JenkinsTimeoutSeconds}s (last HTTP status: $status). Check: podman logs $containerName"
    }
    Start-Sleep -Seconds 5
  }
  Write-Host "    Jenkins is up."

  # The node comes from JCasC; the jenkins-agent container looks up its secret and connects.
  Write-Step "Jenkins: waiting for the agent to connect"
  $headers = New-BasicAuthHeader 'admin' ((Get-Content -LiteralPath $adminFile -Raw).Trim())
  while ($true) {
    $offline = $null
    try {
      $offline = (Invoke-RestMethod -UseBasicParsing -Uri "$url/computer/agent/api/json?tree=offline" -Headers $headers).offline
    } catch { }
    if ($offline -eq $false) { break }
    if ((Get-Date) -gt $deadline) {
      throw "The Jenkins node 'agent' is not connected within ${JenkinsTimeoutSeconds}s. Check: podman logs jenkins-agent"
    }
    Start-Sleep -Seconds 5
  }
  Write-Host "    Jenkins ready at $url (user admin; password in $adminFile); node 'agent' is online." -ForegroundColor Green
}
# --- Main ---------------------------------------------------------------------
Write-Step "Nexus: resolving the admin password to use"
$resolvedNexusPassword = Resolve-NexusAdminPassword   # first, so a missing password fails before anything starts
Start-ComposeServices
Initialize-Nexus $resolvedNexusPassword
Initialize-Jenkins

# Last: bring each system's internal resources (Nexus repositories, roles, users, ...) up to
# date. Needs the services above to be ready and the tfvars files their post-startup wrote.
Write-Step "Terraform: applying the *-tf modules (scripts/Apply-Terraform.ps1)"
& (Join-Path $PSScriptRoot 'Apply-Terraform.ps1')
