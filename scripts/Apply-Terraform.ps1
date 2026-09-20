<#
.SYNOPSIS
  Run `terraform init` + `terraform apply` for each "<system>-tf" module in the repo, to
  keep the systems' internal resources (e.g. Nexus repositories, roles, users) up to date.

.DESCRIPTION
  Terraform runs in its official container (house rule -- see docs/architecture.md), with
  the module directory mounted at /work, exactly as described in nexus-tf/README.md.

  Modules are auto-discovered: every top-level directory named "*-tf" that contains .tf
  files, in alphabetical order. To manage a new system, create "<system>-tf" and it is
  picked up here. Use -Modules to run a subset.

  Applies without confirmation (-auto-approve); this is a local lab. Each module reads its
  variable values from its own terraform.auto.tfvars.json, which the service's post-startup
  step in Start-Services.ps1 writes, so the service must have been started first. Start-Services.ps1
  calls this script as its last step.

  Idempotent: with nothing to change, apply is a no-op.

.EXAMPLE
  ./scripts/Apply-Terraform.ps1
  ./scripts/Apply-Terraform.ps1 -Modules nexus-tf

.NOTES
  Kept ASCII-only and Windows PowerShell 5.1 compatible on purpose (see Start-Services.ps1).
#>
[CmdletBinding()]
param(
  # Keep in step with the tag used in the module READMEs and the required_version in versions.tf.
  [string]$TerraformImage = 'docker.io/hashicorp/terraform:1.16',
  # Module directory names under the repo root. Default: every "*-tf" directory with .tf files.
  [string[]]$Modules
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Invoke-Terraform([string]$ModuleDir, [string[]]$TerraformArgs) {
  # podman writes pull progress to stderr, which Windows PowerShell 5.1 turns into a
  # terminating error under 'Stop' (see Start-Services.ps1). Relax it here (scoped to this
  # function) and rely on the exit code instead.
  $ErrorActionPreference = 'Continue'
  podman run --rm -v "${ModuleDir}:/work" -w /work $TerraformImage @TerraformArgs
  if ($LASTEXITCODE -ne 0) {
    throw "terraform $($TerraformArgs -join ' ') failed in $ModuleDir (exit $LASTEXITCODE)"
  }
}

if (-not $Modules) {
  $Modules = @(
    Get-ChildItem -Path $repoRoot -Directory -Filter '*-tf' |
      Where-Object { Get-ChildItem -Path $_.FullName -Filter '*.tf' -File } |
      Sort-Object Name |
      ForEach-Object { $_.Name }
  )
}

if (-not $Modules) {
  Write-Host "No '*-tf' Terraform modules found under $repoRoot; nothing to apply."
  return
}

foreach ($module in $Modules) {
  $moduleDir = Join-Path $repoRoot $module
  if (-not (Test-Path -LiteralPath $moduleDir -PathType Container)) {
    throw "Terraform module directory not found: $moduleDir"
  }

  Write-Step "Terraform: init $module"
  Invoke-Terraform $moduleDir @('init', '-input=false')

  Write-Step "Terraform: apply $module"
  Invoke-Terraform $moduleDir @('apply', '-input=false', '-auto-approve')

  Write-Host "    $module is up to date." -ForegroundColor Green
}
