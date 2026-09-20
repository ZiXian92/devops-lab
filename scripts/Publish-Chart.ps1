<#
.SYNOPSIS
  Test, package and publish one Helm chart to the local Nexus OCI registry at a given version.

.DESCRIPTION
  First sets `version:` in the chart's Chart.yaml to -Version, so a release needs no separate
  edit or PR. Then runs `tasks publish <chart>` in the helm-cicd container: helm lint,
  helm-unittest and kubeconform, then `helm package` and `helm push` to
  oci://localhost:8081/oci-internal/helm/deployment-templates (Nexus is plain HTTP, so helm is
  run with --plain-http).

  Chart.yaml is left with the published version so it stays in step with what is in Nexus
  (commit it when convenient). If the tests or the push fail, the previous Chart.yaml is
  restored. Only `version:` is touched, not `appVersion:`.

  Credentials are the helm-publisher auth file nexus-tf/helm-registry/publisher.json (written
  by Terraform, see Apply-Terraform.ps1). Inside the compose network Nexus is reached as
  nexus:8081 (localhost there is the container itself); it is the same server as
  localhost:8081 on the host, and tasks.sh re-keys the credentials to that host name.

  Starts the helm-cicd service if it is not running. Pass -Rebuild after changing anything in
  images/helm-cicd (the Dockerfile or tasks.sh). The charts are bind-mounted, so the edited
  Chart.yaml is visible in the container immediately.

.EXAMPLE
  ./scripts/Publish-Chart.ps1 -Chart web-app -Version 1.2.0
  ./scripts/Publish-Chart.ps1 -Chart web-app -Version 1.3.0-rc.1 -Rebuild

.NOTES
  Kept ASCII-only and Windows PowerShell 5.1 compatible on purpose (see Start-Services.ps1).
#>
[CmdletBinding()]
param(
  # A chart directory name under app-deployment-template-charts/.
  [Parameter(Mandatory)][string]$Chart,
  # Semantic version (semver.org) to publish the chart as, e.g. 1.2.0 or 1.3.0-rc.1.
  [Parameter(Mandatory)][string]$Version,
  # Rebuild the helm-cicd image first (podman compose up -d --build helm-cicd).
  [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repoRoot 'docker-compose.yaml'
$chartsRoot  = Join-Path $repoRoot 'app-deployment-template-charts'
$service     = 'helm-cicd'   # service and container_name in docker-compose.yaml

# The official semver.org regular expression. A leading "v" is not semver, and helm would
# publish it as-is, so it is rejected here.
$semver = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Start-HelmCicd {
  # podman compose prints a provider banner on stderr, which Windows PowerShell 5.1 turns
  # into a terminating error under 'Stop'. Relax it (scoped to this function) and rely on
  # exit codes instead, as Start-Services.ps1 does.
  $ErrorActionPreference = 'Continue'

  $running = podman inspect --format '{{.State.Running}}' $service 2>$null
  if (-not $Rebuild -and $LASTEXITCODE -eq 0 -and "$running".Trim() -eq 'true') { return }

  $composeArgs = @('-f', $composeFile, 'up', '-d')
  if ($Rebuild) { $composeArgs += '--build' }
  Write-Step "podman compose $($composeArgs -join ' ') $service"
  podman compose @composeArgs $service
  if ($LASTEXITCODE -ne 0) { throw "Could not start the '$service' service (exit $LASTEXITCODE)." }
}

# --- Main ---------------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $chartsRoot $Chart) 'Chart.yaml'))) {
  throw "Unknown chart '$Chart': no Chart.yaml in $chartsRoot\$Chart."
}
if ($Version -cnotmatch $semver) {
  throw "'$Version' is not a semantic version (expected MAJOR.MINOR.PATCH[-prerelease][+build], e.g. 1.2.0)."
}

Start-HelmCicd

# Set the version in Chart.yaml (exactly one top-level `version:` line; `appVersion:` does not
# match). Read and written as raw text, so comments and line endings survive; no BOM.
$chartFile = Join-Path (Join-Path $chartsRoot $Chart) 'Chart.yaml'
$utf8      = New-Object System.Text.UTF8Encoding($false)
$original  = [System.IO.File]::ReadAllText($chartFile, $utf8)
$pattern   = '(?m)^(version:[ \t]*)\S+'
if ([regex]::Matches($original, $pattern).Count -ne 1) {
  throw "Expected exactly one top-level 'version:' line in $chartFile."
}
Write-Step "Setting version: $Version in $Chart/Chart.yaml"
[System.IO.File]::WriteAllText($chartFile, [regex]::Replace($original, $pattern, "`${1}$Version"), $utf8)

$ErrorActionPreference = 'Continue'   # see Start-HelmCicd
Write-Step "Publishing chart: $Chart $Version"
# -T: no TTY, so this also works from a task terminal.
podman compose -f $composeFile exec -T $service tasks publish $Chart
if ($LASTEXITCODE -ne 0) {
  [System.IO.File]::WriteAllText($chartFile, $original, $utf8)
  throw "Publishing $Chart $Version failed (exit $LASTEXITCODE); Chart.yaml restored to its previous version."
}

Write-Step "Published $Chart $Version to oci://localhost:8081/oci-internal/helm/deployment-templates/$Chart"
