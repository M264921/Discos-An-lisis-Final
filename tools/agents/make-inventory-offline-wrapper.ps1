Param(
  [string]$OutDir = "docs",
  [string]$CsvFallback = "docs\hash_data.csv"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$MakeInv = Join-Path $RepoRoot 'tools\make_inventory_offline.ps1'
if (!(Test-Path -LiteralPath $MakeInv)) {
  $MakeInv = Join-Path $RepoRoot 'make_inventory_offline.ps1'
}
if (!(Test-Path -LiteralPath $MakeInv)) {
  throw "No se encontró make_inventory_offline.ps1"
}

$psExe = $null
foreach ($candidate in @('pwsh','powershell')) {
  try {
    $cmd = Get-Command $candidate -ErrorAction Stop
    if ($cmd) { $psExe = $cmd.Source; break }
  } catch {}
}
if (-not $psExe) {
  throw "No se encontró un intérprete de PowerShell (pwsh/powershell)"
}

$OutDirFull = if ([IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $RepoRoot $OutDir }
if (!(Test-Path -LiteralPath $OutDirFull)) {
  New-Item -ItemType Directory -Force -Path $OutDirFull | Out-Null
}
$HtmlPath = Join-Path $OutDirFull 'inventario_interactivo_offline.html'

$Normalize = Join-Path $RepoRoot 'tools\normalize-inventory-html.ps1'
$Sanitize = Join-Path $RepoRoot 'tools\sanitize-inventory-html.ps1'
$Injector = Join-Path $RepoRoot 'tools\inventory-inject-from-csv.ps1'
$CsvPath = if ([IO.Path]::IsPathRooted($CsvFallback)) { $CsvFallback } else { Join-Path $RepoRoot $CsvFallback }

function Get-RowCountFromHtml {
  param([string]$HtmlContent)
  if (-not $HtmlContent) { return 0 }
  $rx = [regex]'window\.__INVENTARIO__\.setData\((\[[\s\S]*?\])\s*,'
  $m = $rx.Match($HtmlContent)
  if (-not $m.Success) { return 0 }
  try {
    $rows = $m.Groups[1].Value | ConvertFrom-Json
    if ($null -eq $rows) { return 0 }
    if ($rows -is [System.Collections.IEnumerable] -and -not ($rows -is [string])) {
      return @($rows).Count
    }
    return 1
  } catch {
    return 0
  }
}

Write-Host "[wrapper] Generando inventario offline…" -ForegroundColor Cyan
& $psExe -NoProfile -ExecutionPolicy Bypass -File $MakeInv -Output $HtmlPath

if (!(Test-Path -LiteralPath $HtmlPath)) {
  throw "No se generó $HtmlPath"
}

if (Test-Path -LiteralPath $Normalize) {
  Write-Host "[wrapper] Normalizando inyección y meta…" -ForegroundColor Cyan
  & $psExe -NoProfile -ExecutionPolicy Bypass -File $Normalize -HtmlPath $HtmlPath
}

$raw = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$rowsCount = Get-RowCountFromHtml -HtmlContent $raw

if ($rowsCount -le 0 -and (Test-Path -LiteralPath $Injector) -and (Test-Path -LiteralPath $CsvPath)) {
  Write-Host "[wrapper] Tabla vacía. Inyectando desde CSV ($CsvPath)…" -ForegroundColor Yellow
  & $psExe -NoProfile -ExecutionPolicy Bypass -File $Injector -CsvPath $CsvPath -HtmlPath $HtmlPath
  if (Test-Path -LiteralPath $Normalize) {
    Write-Host "[wrapper] Normalizando post-inyección…" -ForegroundColor Cyan
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $Normalize -HtmlPath $HtmlPath
  }
  $raw = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
  $rowsCount = Get-RowCountFromHtml -HtmlContent $raw
}

if (Test-Path -LiteralPath $Sanitize) {
  Write-Host "[wrapper] Sanitizando HTML…" -ForegroundColor Cyan
  & $psExe -NoProfile -ExecutionPolicy Bypass -File $Sanitize -HtmlPath $HtmlPath
} else {
  Write-Warning "[wrapper] No se encontró sanitizer; saltando."
}

Write-Host "[wrapper] Filas finales: $rowsCount"
Write-Host "[wrapper] Listo: $HtmlPath" -ForegroundColor Green
