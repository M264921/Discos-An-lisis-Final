param(
  [ValidateSet("None","DryRun","Apply")][string]$SweepMode = "None"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue

function Fail {
  param([string]$Message)
  Write-Host "ERROR: $Message" -ForegroundColor Red
  exit 1
}

if (-not $pwsh) {
  Fail "No se encontro pwsh (PowerShell 7). Instala https://aka.ms/powershell y reintenta."
}

$pwshPath = $pwsh.Source
$agent = Join-Path $here "tools\agents\inventory-cleaner.ps1"
if (-not (Test-Path -LiteralPath $agent)) {
  Fail "No se encuentra $agent"
}

New-Item -ItemType Directory -Force -Path (Join-Path $here "logs") | Out-Null

Write-Host "Inventario Cleaner -> $here" -ForegroundColor Cyan
$args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$agent,"-RepoRoot",$here,"-SweepMode",$SweepMode)

& $pwshPath @args
exit $LASTEXITCODE
