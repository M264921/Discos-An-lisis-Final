[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot/..",
  [string]$OutputRoot = "dist",
  [switch]$Timestamp
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path $RepoRoot).Path
Push-Location $resolvedRoot
try {
  $distRoot = Join-Path $resolvedRoot $OutputRoot
  New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

  $label = if ($Timestamp) { Get-Date -Format 'yyyyMMdd-HHmmss' } else { 'latest' }
  $packageDir = Join-Path $distRoot $label

  if (Test-Path $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
  }

  Write-Host "Creando paquete en $packageDir" -ForegroundColor Cyan

  $toolsDir = Join-Path $packageDir 'tools'
  $docsDir  = Join-Path $packageDir 'docs'
  $inventoryDir = Join-Path $docsDir 'inventory'
  $dataDir  = Join-Path $docsDir 'data'
  $logsDir  = Join-Path $packageDir 'logs'

  New-Item -ItemType Directory -Force -Path $toolsDir,$docsDir,$inventoryDir,$dataDir,$logsDir | Out-Null

  Write-Host "Copiando herramientas..." -ForegroundColor DarkGray
  Copy-Item -Path (Join-Path $resolvedRoot 'tools\*') -Destination $toolsDir -Recurse -Force

  Write-Host "Copiando artefactos de docs..." -ForegroundColor DarkGray
  $docAssets = @(
    'inventario_interactivo_offline.html',
    'index.html',
    'Listado_Duplicados_interactivo.html'
  )
  foreach ($asset in $docAssets) {
    $source = Join-Path $resolvedRoot "docs\$asset"
    if (Test-Path $source) {
      Copy-Item -LiteralPath $source -Destination $docsDir -Force
    }
  }

  $dataSource = Join-Path $resolvedRoot 'docs\data\inventory.json'
  if (Test-Path $dataSource) {
    Copy-Item -LiteralPath $dataSource -Destination $dataDir -Force
  }

  $readme = @'
Este paquete contiene la tubería «inventory-cleaner» preparada para ejecutarse fuera del repositorio.

Estructura:
  tools\    Scripts necesarios para generar inventario y duplicados
  docs\     Artefactos HTML/JSON generados (pueden regenerarse con inventory-cleaner)
  logs\     Directorio vacío para salidas de ejecución

Uso sugerido:
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None

Requisitos:
  - PowerShell 7+
  - Python instalado (para remove_nonmedia_duplicates / generate_duplicates_table)
'@
  Set-Content -LiteralPath (Join-Path $packageDir 'README.txt') -Encoding UTF8 -Value $readme

  Write-Host "Paquete listo en $packageDir" -ForegroundColor Green
} finally {
  Pop-Location
}
