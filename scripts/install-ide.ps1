#Requires -Version 5.1
<#
.SYNOPSIS
  Install agentic-quality-gate for Cursor / VS Code on Windows (no admin).
#>
$ErrorActionPreference = "Stop"

$RepoUrl = if ($env:AGENTIC_QUALITY_GATE_REPO) { $env:AGENTIC_QUALITY_GATE_REPO } else { "https://github.com/pulumamidi-harsha/agentic-quality-gate.git" }
$RepoRef = if ($env:AGENTIC_QUALITY_GATE_REF) { $env:AGENTIC_QUALITY_GATE_REF } else { "main" }
$Dest = if ($env:AGENTIC_QUALITY_GATE_HOME) { $env:AGENTIC_QUALITY_GATE_HOME } else { (Join-Path $env:USERPROFILE ".cursor\agentic-quality-gate") }
$AppRoot = $env:AGENTIC_APP_ROOT
$CursorMcp = Join-Path $env:USERPROFILE ".cursor\mcp.json"
$BinDir = Join-Path $env:USERPROFILE ".local\bin"
$CacheDir = Join-Path $env:USERPROFILE ".cache\agentic-quality-gate"

function Find-GitBash {
  foreach ($c in @(
      (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
      (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe")
    )) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  $cmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Find-PythonCmd {
  $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
  if ($pyLauncher) {
    try {
      $exe = & py -3 -c "import sys; print(sys.executable)" 2>$null
      if ($exe) { return @{ Exe = "py"; PrefixArgs = @("-3") } }
    } catch { }
  }
  foreach ($name in @("python", "python3")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return @{ Exe = $cmd.Source; PrefixArgs = @() } }
  }
  return $null
}

function Find-Uvx {
  $cmd = Get-Command uvx -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in @(
      (Join-Path $env:USERPROFILE ".local\bin\uvx.exe"),
      (Join-Path $env:USERPROFILE ".cargo\bin\uvx.exe")
    )) {
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

Write-Host "=== agentic-quality-gate -> IDE (Windows) ==="
Write-Host "  Dest: $Dest"
Write-Host "  Ref:  $RepoRef"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git required — install Git for Windows from https://git-scm.com/download/win"
}
if (-not (Find-GitBash)) {
  throw "Git Bash not found — install Git for Windows (includes bash), then reopen the terminal"
}
$Python = Find-PythonCmd
if (-not $Python) {
  throw "Python 3 required — install from https://www.python.org/downloads/ (check 'Add to PATH')"
}

New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent), (Join-Path $env:USERPROFILE ".cursor"), $CacheDir, $BinDir | Out-Null

$LocalSrc = $null
if ($PSCommandPath) {
  $here = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
  if (Test-Path (Join-Path $here "scripts\local-gate.sh")) { $LocalSrc = $here }
}

if (Test-Path (Join-Path $Dest ".git")) {
  Write-Host "  Updating existing install..."
  git -C $Dest fetch --depth=1 origin $RepoRef 2>$null | Out-Null
  git -C $Dest checkout -q FETCH_HEAD 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    git -C $Dest pull --ff-only origin $RepoRef 2>$null | Out-Null
  }
} elseif ($LocalSrc -and ($LocalSrc -ne $Dest)) {
  Write-Host "  Installing from local clone -> $Dest"
  if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  & robocopy $LocalSrc $Dest /MIR /NFL /NDL /NJH /NJS /XD .git "mcp\.venv" .agentic-quality-gate | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit $LASTEXITCODE" }
  if (-not (Test-Path (Join-Path $Dest ".git"))) {
    git -C $Dest init -q
    git -C $Dest remote add origin $RepoUrl 2>$null | Out-Null
  }
} else {
  Write-Host "  Cloning $RepoUrl ($RepoRef)..."
  if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
  git clone --depth=1 --branch $RepoRef $RepoUrl $Dest
}

if (-not (Test-Path (Join-Path $Dest "scripts\local-gate.sh"))) {
  throw "install incomplete — missing scripts\local-gate.sh under $Dest"
}

$Uvx = Find-Uvx
if (-not $Uvx) {
  Write-Host "  Installing uv (user-space) for MCP runner..."
  try { irm https://astral.sh/uv/install.ps1 | iex } catch {
    Write-Host "  warn: uv install failed; will fall back to python"
  }
  $Uvx = Find-Uvx
}

$hubSlash = ($Dest -replace '\\', '/')
if ($Uvx) {
  $command = $Uvx
  $argsList = @("--from", "$hubSlash/mcp", "aqg-mcp")
  Write-Host "  Runner: uvx"
} else {
  $command = $Python.Exe
  $argsList = @($Python.PrefixArgs) + @("$hubSlash/mcp/aqg_mcp/server.py")
  Write-Host "  Runner: python"
  try {
    $pipArgs = @($Python.PrefixArgs) + @("-m", "pip", "install", "--user", "-q", "mcp>=1.2.0,<2")
    & $Python.Exe @pipArgs 2>$null | Out-Null
  } catch { }
}

function Write-CursorMcp([string]$Path) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  $serverObj = @{
    command = $command
    args    = @($argsList)
    env     = @{
      AGENTIC_QUALITY_GATE_HOME  = $Dest
      AGENTIC_QUALITY_GATE_CACHE = $CacheDir
    }
  }
  $servers = [ordered]@{ "agentic-quality-gate" = $serverObj }
  if (Test-Path $Path) {
    try {
      $raw = Get-Content -Raw -Path $Path | ConvertFrom-Json
      if ($raw.mcpServers) {
        $raw.mcpServers.PSObject.Properties | ForEach-Object {
          if ($_.Name -ne "agentic-quality-gate") { $servers[$_.Name] = $_.Value }
        }
      }
    } catch { }
  }
  $out = [ordered]@{ mcpServers = $servers }
  Write-Utf8NoBom $Path (($out | ConvertTo-Json -Depth 8) + "`n")
  Write-Host "  Cursor MCP -> $Path"
}

function Write-VscodeMcp([string]$Path) {
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
  $out = [ordered]@{
    servers = [ordered]@{
      "agentic-quality-gate" = [ordered]@{
        type    = "stdio"
        command = $command
        args    = @($argsList)
        env     = [ordered]@{
          AGENTIC_QUALITY_GATE_HOME  = $Dest
          AGENTIC_QUALITY_GATE_CACHE = $CacheDir
        }
      }
    }
  }
  Write-Utf8NoBom $Path (($out | ConvertTo-Json -Depth 8) + "`n")
  Write-Host "  VS Code MCP -> $Path"
}

Write-CursorMcp $CursorMcp
New-Item -ItemType Directory -Force -Path (Join-Path $Dest "examples") | Out-Null
Write-VscodeMcp (Join-Path $Dest "examples\vscode-mcp.json")

Copy-Item -Force (Join-Path $Dest "scripts\run-qg.cmd") (Join-Path $BinDir "run-qg.cmd")
Write-Utf8NoBom (Join-Path $BinDir "run-qg.ps1") @"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Rest)
& (Join-Path `$env:USERPROFILE '.local\bin\run-qg.cmd') @Rest
exit `$LASTEXITCODE
"@
Write-Host "  CLI -> $(Join-Path $BinDir 'run-qg.cmd')"

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if ($userPath -notlike "*$BinDir*") {
  $newPath = if ($userPath.Trim()) { "$BinDir;$userPath" } else { $BinDir }
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  Write-Host "  PATH -> added $BinDir to user PATH"
}
$env:Path = "$BinDir;$env:Path"

if ($AppRoot -and (Test-Path (Join-Path $AppRoot ".git"))) {
  Write-Host "  Wiring app repo: $AppRoot"
  Write-VscodeMcp (Join-Path $AppRoot ".vscode\mcp.json")

  $skillSrc = Join-Path $Dest "examples\cursor-skill\SKILL.md"
  if (Test-Path $skillSrc) {
    $skillDir = Join-Path $AppRoot ".cursor\skills\quality-gate"
    New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
    Copy-Item -Force $skillSrc (Join-Path $skillDir "SKILL.md")
    Write-Host "  Cursor skill -> $skillDir\SKILL.md"
  }

  $tasksSrc = Join-Path $Dest "examples\vscode-tasks.json"
  if (Test-Path $tasksSrc) {
    $vs = Join-Path $AppRoot ".vscode"
    New-Item -ItemType Directory -Force -Path $vs | Out-Null
    Copy-Item -Force $tasksSrc (Join-Path $vs "tasks.json")
    Write-Host "  VS Code task -> $vs\tasks.json"
  }

  $hookDir = Join-Path $AppRoot ".git\hooks"
  $hook = Join-Path $hookDir "pre-push"
  New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
  if ((Test-Path $hook) -and -not (Select-String -Path $hook -Pattern "agentic-quality-gate" -Quiet)) {
    Copy-Item $hook "$hook.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
  }
  $hookText = @'
#!/usr/bin/env bash
# agentic-quality-gate — block push when the local quality gate fails
set -euo pipefail
HUB="${AGENTIC_QUALITY_GATE_HOME:-__HUB__}"
RUN_QG="${HUB}/scripts/run-qg.sh"
echo "=== agentic-quality-gate (pre-push) ==="
exec bash "$RUN_QG" --base "${AGENTIC_GATE_BASE:-main}" --strict
'@
  $hookText = $hookText.Replace("__HUB__", $hubSlash) -replace "`r`n", "`n"
  Write-Utf8NoBom $hook $hookText
  Write-Host "  git pre-push hook -> $hook"

  $wf = Join-Path $AppRoot ".github\workflows\quality-gate.yml"
  $wfSrc = Join-Path $Dest "examples\caller-workflow.yml"
  if (-not (Test-Path $wf) -and (Test-Path $wfSrc)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $wf -Parent) | Out-Null
    Copy-Item -Force $wfSrc $wf
    Write-Host "  PR workflow -> $wf"
  }
}

Write-Host ""
Write-Host "Done."
if ($AppRoot) {
  Write-Host "This app is ready: $AppRoot"
  Write-Host "  Type: run-qg"
} else {
  Write-Host "Laptop hub installed. Wire an app with:"
  Write-Host '  cd C:\path\to\your-app; & ..\agentic-quality-gate\scripts\install-app.ps1'
}
