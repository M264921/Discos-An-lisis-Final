# ?? DEPRECATED: usa tools/inventory.ps1 en modo correspondiente (interactive, uto, etc.)
[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot\..",
  [string]$Output = "docs\inventario_interactivo_offline.html"
)

$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Push-Location $resolvedRoot
try {
  $docsDir = Join-Path $resolvedRoot 'docs'
  $inventoryDir = Join-Path $docsDir 'inventory'
  $dataDir = Join-Path $docsDir 'data'
  New-Item -ItemType Directory -Force -Path $inventoryDir, $dataDir | Out-Null

  $hashCsv = Join-Path $docsDir 'hash_data.csv'
  $jsonPath = Join-Path $dataDir 'inventory.json'
  $htmlPath = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $resolvedRoot $Output }

  $merge = Join-Path $resolvedRoot 'tools\merge-scans.ps1'
  $csvToJson = Join-Path $resolvedRoot 'tools\csv-to-inventory-json.ps1'
  $buildHtml = Join-Path $resolvedRoot 'tools\build-inventory-html.ps1'

  foreach ($script in @($merge, $csvToJson, $buildHtml)) {
    if (-not (Test-Path -LiteralPath $script)) {
      throw "No se encuentra $script"
    }
  }

  Write-Host "Fusionando scans..." -ForegroundColor Cyan
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $merge -InventoryDir $inventoryDir -OutCsv $hashCsv
  if ($LASTEXITCODE -ne 0) {
    throw "merge-scans.ps1 devolvio codigo $LASTEXITCODE"
  }

  Write-Host "Generando JSON de inventario..." -ForegroundColor Cyan
  & $csvToJson -CsvPath $hashCsv -JsonPath $jsonPath | Out-Null

  Write-Host "Construyendo HTML offline..." -ForegroundColor Cyan
  & $buildHtml -JsonPath $jsonPath -HtmlPath $htmlPath | Out-Null

  if (Test-Path -LiteralPath $htmlPath) {
    Write-Host ("HTML regenerado -> {0}" -f $htmlPath) -ForegroundColor Green
  } else {
    Write-Warning ("No se genero el HTML esperado ({0})" -f $htmlPath)
  }
} finally {
  Pop-Location
}

