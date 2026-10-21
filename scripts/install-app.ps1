#Requires -Version 5.1
<#
.SYNOPSIS
  One-command Windows setup from your APPLICATION repo.

.EXAMPLE
  # From app repo (recommended — local hub next to the app):
  cd C:\work\dso-os-frontend
  & ..\agentic-quality-gate\scripts\install-app.ps1

  # Or from GitHub (needs network):
  irm https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main/scripts/install-app.ps1 | iex
#>
$ErrorActionPreference = "Stop"

function Get-GitRoot {
  $top = & git rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $top) { return $null }
  return $top.Trim()
}

$AppRoot = Get-GitRoot
if (-not $AppRoot) {
  Write-Error @"
Run this from inside your application git repo, e.g.:
  cd C:\work\dso-os-frontend
  & ..\agentic-quality-gate\scripts\install-app.ps1
"@
}

$env:AGENTIC_APP_ROOT = $AppRoot
Write-Host "=== agentic-quality-gate -> this app (Windows) ==="
Write-Host "  App: $AppRoot"

$RawBase = if ($env:AGENTIC_QUALITY_GATE_RAW) {
  $env:AGENTIC_QUALITY_GATE_RAW
} else {
  "https://raw.githubusercontent.com/pulumamidi-harsha/agentic-quality-gate/main"
}
$Dest = if ($env:AGENTIC_QUALITY_GATE_HOME) {
  $env:AGENTIC_QUALITY_GATE_HOME
} else {
  Join-Path $env:USERPROFILE ".cursor\agentic-quality-gate"
}

# 1) Script lives in a hub checkout
$localIde = $null
if ($PSCommandPath) {
  $candidate = Join-Path (Split-Path $PSCommandPath -Parent) "install-ide.ps1"
  if (Test-Path $candidate) { $localIde = $candidate }
}

# 2) Already-installed hub
$destIde = Join-Path $Dest "scripts\install-ide.ps1"

# 3) Sibling hub next to the app (../agentic-quality-gate)
$siblingIde = Join-Path (Split-Path $AppRoot -Parent) "agentic-quality-gate\scripts\install-ide.ps1"

if ($localIde) {
  & $localIde
} elseif (Test-Path $destIde) {
  Write-Host "  Using existing hub at $Dest"
  & $destIde
} elseif (Test-Path $siblingIde) {
  Write-Host "  Using sibling hub: $siblingIde"
  & $siblingIde
} else {
  Write-Host "  Downloading install-ide.ps1 from GitHub..."
  try {
    $ideScript = Join-Path $env:TEMP "aqg-install-ide.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "$RawBase/scripts/install-ide.ps1" -OutFile $ideScript
    & $ideScript
  } catch {
    throw @"
Could not download install-ide.ps1 ($($_.Exception.Message)).

Clone the hub once next to your app, then run:
  cd $AppRoot
  & ..\agentic-quality-gate\scripts\install-app.ps1
"@
  }
}

# Ensure run-qg works in THIS PowerShell session
$bin = Join-Path $env:USERPROFILE ".local\bin"
$env:Path = "$bin;$env:Path"

Write-Host ""
Write-Host "Done for this app: $AppRoot"
Write-Host "  Type:  run-qg"
Write-Host "  VS Code: Terminal -> Run Task -> run-qg"
Write-Host "  Agent chat: run-qg"
