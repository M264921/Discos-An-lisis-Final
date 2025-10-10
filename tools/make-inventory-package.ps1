[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot\..",
  [string]$Label = "latest",
  [switch]$SkipBuildDist
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$distRoot = Join-Path $resolvedRoot 'dist'
$packageDir = Join-Path $distRoot $Label

if (-not $SkipBuildDist) {
  $buildDist = Join-Path $resolvedRoot 'tools\build-dist.ps1'
  if (-not (Test-Path -LiteralPath $buildDist)) {
    throw "No se encuentra tools\build-dist.ps1 en $resolvedRoot"
  }
  Write-Host ">> Regenerando dist\$Label mediante build-dist.ps1" -ForegroundColor Cyan
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $buildDist -RepoRoot $resolvedRoot -OutputRoot 'dist'
}

if (-not (Test-Path -LiteralPath $packageDir)) {
  throw "No existe el directorio de paquete en $packageDir"
}

$launcherPath = Join-Path $packageDir 'InventoryCleaner.ps1'
$exePath = Join-Path $packageDir 'InventoryCleaner.exe'

$launcher = @'
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
'@

Set-Content -LiteralPath $launcherPath -Encoding UTF8 -Value $launcher

if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
  Write-Host ">> Instalando modulo PS2EXE (solo una vez)..." -ForegroundColor DarkGray
  if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host ">> Instalando proveedor NuGet..." -ForegroundColor DarkGray
    Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -ErrorAction Stop
  }
  Install-Module -Name PS2EXE -Scope CurrentUser -Force -ErrorAction Stop
}

Import-Module PS2EXE -ErrorAction Stop

Write-Host ">> Generando InventoryCleaner.exe..." -ForegroundColor Cyan
Invoke-PS2EXE -InputFile $launcherPath -OutputFile $exePath -RequireAdmin:$false -NoConsole:$false -Title 'Inventory Cleaner' -Description 'Automatiza el pipeline inventory-cleaner.ps1'

Write-Host ""
Write-Host "Paquete listo:" -ForegroundColor Green
Write-Host "  $packageDir"
Write-Host "  - InventoryCleaner.ps1"
Write-Host "  - InventoryCleaner.exe"
