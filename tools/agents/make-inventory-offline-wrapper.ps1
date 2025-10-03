Param(
    [string]$RepoRoot = "$PSScriptRoot/../..",
    [string]$CsvPath = "docs/hash_data.csv",
    [string]$OutputHtml = "docs/inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"
$resolvedRepo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Resolve-InRepo {
    param([string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $resolvedRepo $Path)
}

$csvFull   = Resolve-InRepo $CsvPath
$htmlFull  = Resolve-InRepo $OutputHtml
$makeLocal = Join-Path $resolvedRepo "tools/make_inventory_offline.ps1"
if (-not (Test-Path -LiteralPath $makeLocal)) {
    $makeLocal = Join-Path $resolvedRepo "make_inventory_offline.ps1"
}
if (-not (Test-Path -LiteralPath $makeLocal)) {
    throw "No se encontro make_inventory_offline.ps1 en $resolvedRepo"
}

$buildHash = Join-Path $resolvedRepo "tools/build-hash-data.ps1"
$injectScript = Join-Path $resolvedRepo "tools/inventory-inject-from-csv.ps1"
$normalizeScript = Join-Path $resolvedRepo "tools/normalize-inventory-html.ps1"
$sanitizeScript = Join-Path $resolvedRepo "tools/sanitize-inventory-html.ps1"
if (-not (Test-Path -LiteralPath $injectScript)) {
    throw "No se encontro tools/inventory-inject-from-csv.ps1"
}
if (-not (Test-Path -LiteralPath $sanitizeScript)) {
    throw "No se encontro tools/sanitize-inventory-html.ps1"
}

function Get-InventoryRowCount {
    param([string]$HtmlPath)
    if (-not (Test-Path -LiteralPath $HtmlPath)) { return 0 }
    $html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

    $json = $null
    $dataMatch = [System.Text.RegularExpressions.Regex]::Match($html, 'window\.__DATA__\s*=\s*(\[[\s\S]*?\]);', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($dataMatch.Success) {
        $json = $dataMatch.Groups[1].Value
    } else {
        $setDataMatch = [System.Text.RegularExpressions.Regex]::Match($html, 'window\.__INVENTARIO__\.setData\((\[[\s\S]*?\]),', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($setDataMatch.Success) {
            $json = $setDataMatch.Groups[1].Value
        }
    }

    if (-not $json) { return 0 }

    try {
        $rows = $json | ConvertFrom-Json
    } catch {
        return 0
    }
    if ($null -eq $rows) { return 0 }
    if ($rows -is [array]) { return $rows.Count }
    return 1
}

Push-Location $resolvedRepo
try {
    if (Test-Path -LiteralPath $buildHash) {
        Write-Host "[wrapper] Actualizando docs\\hash_data.csv ..."
        & $buildHash -RepoRoot $resolvedRepo -IndexPath 'index_by_hash.csv' -OutputCsv $csvFull
    }

    Write-Host "[wrapper] Generando HTML base ..."
    & $makeLocal -Output $htmlFull

    $rowCount = Get-InventoryRowCount -HtmlPath $htmlFull
    Write-Host "[wrapper] Filas tras make_inventory_offline: $rowCount"

    if ($rowCount -le 0) {
        Write-Host "[wrapper] HTML vacio. Inyectando datos desde $csvFull ..."
        & $injectScript -CsvPath $csvFull -HtmlPath $htmlFull
        $rowCount = Get-InventoryRowCount -HtmlPath $htmlFull
        Write-Host "[wrapper] Filas tras inyeccion CSV: $rowCount"
    }

    if (Test-Path -LiteralPath $normalizeScript) {
        Write-Host "[wrapper] Normalizando inyeccion de datos ..." -ForegroundColor Cyan
        pwsh -NoProfile -ExecutionPolicy Bypass -File $normalizeScript -HtmlPath $htmlFull
    }

    Write-Host "[wrapper] Sanitizando HTML ..."
    & $sanitizeScript -HtmlPath $htmlFull

    $rowCount = Get-InventoryRowCount -HtmlPath $htmlFull
    Write-Host "[wrapper] Filas finales en HTML: $rowCount"

    $rootHtml = Join-Path $resolvedRepo 'inventario_interactivo_offline.html'
    if (-not [string]::Equals($rootHtml, $htmlFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $rootHtml)) {
        Write-Host "[wrapper] Eliminando copia redundante en $rootHtml ..."
        Remove-Item -LiteralPath $rootHtml -Force
    }
} finally {
    Pop-Location
}

