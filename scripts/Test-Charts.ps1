<#
.SYNOPSIS
  Test one Helm chart, or every chart in turn, in the helm-cicd container.

.DESCRIPTION
  Charts are discovered from app-deployment-template-charts/ (every directory with a
  Chart.yaml), so a new chart shows up here without editing anything.

  Without -Chart you get a menu: pick one chart by number or name, or press Enter for all.
  Each chart is tested with `tasks all <chart>` inside the helm-cicd service (helm lint,
  helm-unittest suites, kubeconform on the rendered manifests).

  With "all", the charts run in sequence and a failure does not stop the run: every chart is
  tested, then a summary is printed and the script exits 1 if any of them failed.

  Starts the helm-cicd service if it is not running. Pass -Rebuild after changing anything in
  images/helm-cicd (the Dockerfile or tasks.sh).

.EXAMPLE
  ./scripts/Test-Charts.ps1                    # menu
  ./scripts/Test-Charts.ps1 -Chart web-app
  ./scripts/Test-Charts.ps1 -Chart all -Rebuild

.NOTES
  Kept ASCII-only and Windows PowerShell 5.1 compatible on purpose (see Start-Services.ps1).
#>
[CmdletBinding()]
param(
  # A chart directory name, or 'all'. Omit to choose from a menu.
  [string]$Chart,
  # Rebuild the helm-cicd image first (podman compose up -d --build helm-cicd).
  [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $repoRoot 'docker-compose.yaml'
$chartsRoot  = Join-Path $repoRoot 'app-deployment-template-charts'
$service     = 'helm-cicd'   # service and container_name in docker-compose.yaml

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Get-ChartNames {
  @(
    Get-ChildItem -Path $chartsRoot -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Chart.yaml') } |
      Sort-Object Name |
      ForEach-Object { $_.Name }
  )
}

function Select-Chart([string[]]$Names) {
  Write-Host "Charts in ${chartsRoot}:"
  Write-Host "  [0] all (in sequence)"
  for ($i = 0; $i -lt $Names.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $Names[$i]) }

  $answer = (Read-Host "Choose a number or name (Enter = all)").Trim()
  if (-not $answer -or $answer -eq '0' -or $answer -eq 'all') { return 'all' }

  $number = 0
  if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Names.Count) {
    return $Names[$number - 1]
  }
  if ($Names -contains $answer) { return $answer }
  throw "'$answer' is not one of the choices above."
}

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

function Invoke-ChartTests([string]$Name) {
  $ErrorActionPreference = 'Continue'   # see Start-HelmCicd
  # -T: no TTY, so this also works from a task terminal and when output is piped.
  # Out-Host: a function's output is its return value, and this one must return only the
  # exit code, so the test output is sent to the console instead.
  podman compose -f $composeFile exec -T $service tasks all $Name | Out-Host
  return $LASTEXITCODE
}

# --- Main ---------------------------------------------------------------------
$names = Get-ChartNames
if (-not $names) { throw "No charts (directories with a Chart.yaml) found in $chartsRoot." }

if (-not $Chart) { $Chart = Select-Chart $names }
if ($Chart -ne 'all' -and $names -notcontains $Chart) {
  throw "Unknown chart '$Chart'. Available: $($names -join ', '), or 'all'."
}
$selected = if ($Chart -eq 'all') { $names } else { @($Chart) }

Start-HelmCicd

$results = [ordered]@{}
foreach ($name in $selected) {
  Write-Step "Testing chart: $name"
  $results[$name] = Invoke-ChartTests $name
}

Write-Host ""
Write-Step "Summary"
foreach ($name in $results.Keys) {
  if ($results[$name] -eq 0) {
    Write-Host ("  PASS  {0}" -f $name) -ForegroundColor Green
  } else {
    Write-Host ("  FAIL  {0} (exit {1})" -f $name, $results[$name]) -ForegroundColor Red
  }
}

$failed = @($results.Keys | Where-Object { $results[$_] -ne 0 })
if ($failed.Count -gt 0) { exit 1 }
