Param(
    [string]$RepoRoot = "$PSScriptRoot/../..",
    [string]$CsvPath = "docs/hash_data.csv",
    [string]$OutputHtml = "docs/inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"

$resolvedRepo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Resolve-InRepo {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $resolvedRepo }
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return [IO.Path]::Combine($resolvedRepo, $Path)
}

$csvFull   = Resolve-InRepo $CsvPath
$htmlFull  = Resolve-InRepo $OutputHtml
$makeLocal = Resolve-InRepo "tools/make_inventory_offline.ps1"
if (-not (Test-Path -LiteralPath $makeLocal)) {
    $makeLocal = Resolve-InRepo "make_inventory_offline.ps1"
}
if (-not (Test-Path -LiteralPath $makeLocal)) {
    throw "No se encontro make_inventory_offline.ps1 en $resolvedRepo"
}

$buildHash = Resolve-InRepo "tools/build-hash-data.ps1"
$injectScript = Resolve-InRepo "tools/inventory-inject-from-csv.ps1"
$normalizeScript = Resolve-InRepo "tools/normalize-inventory-html.ps1"
$sanitizeScript = Resolve-InRepo "tools/sanitize-inventory-html.ps1"
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
    $setDataMatch = [regex]::Match($html, 'window\.__INVENTARIO__\.setData\((\[[\s\S]*?\])\s*,', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($setDataMatch.Success) {
        $json = $setDataMatch.Groups[1].Value
    } else {
        $dataMatch = [regex]::Match($html, 'window\.__DATA__\s*=\s*(\[[\s\S]*?\]);', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($dataMatch.Success) {
            $json = $dataMatch.Groups[1].Value
        }
    }

    if (-not $json) { return 0 }

    try {
        $rows = $json | ConvertFrom-Json
    } catch {
        return 0
    }

    if ($null -eq $rows) { return 0 }
    if ($rows -is [System.Collections.IEnumerable] -and -not ($rows -is [string])) {
        return @($rows).Count
    }
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

    if (-not (Test-Path -LiteralPath $htmlFull)) {
        throw "No se genero $htmlFull"
    }

    if (Test-Path -LiteralPath $normalizeScript) {
        Write-Host "[wrapper] Normalizando data/meta ..." -ForegroundColor Cyan
        & $normalizeScript -HtmlPath $htmlFull
    }

    $rowCount = Get-InventoryRowCount -HtmlPath $htmlFull
    Write-Host "[wrapper] Filas tras make_inventory_offline: $rowCount"

    if ($rowCount -le 0) {
        Write-Host "[wrapper] HTML sin filas. Inyectando datos desde $csvFull ..." -ForegroundColor Yellow
        & $injectScript -CsvPath $csvFull -HtmlPath $htmlFull
        if (Test-Path -LiteralPath $normalizeScript) {
            Write-Host "[wrapper] Normalizando post-inyeccion ..." -ForegroundColor Cyan
            & $normalizeScript -HtmlPath $htmlFull
        }
        $rowCount = Get-InventoryRowCount -HtmlPath $htmlFull
        Write-Host "[wrapper] Filas tras inyeccion: $rowCount"
    }

    Write-Host "[wrapper] Sanitizando HTML final ..."
    & $sanitizeScript -HtmlPath $htmlFull

    $rowCount = Get-InventoryRowCount -HtmlPath $htmlFull
    Write-Host "[wrapper] Filas finales en HTML: $rowCount"

    $rootHtml = Resolve-InRepo 'inventario_interactivo_offline.html'
    if (-not [string]::Equals($rootHtml, $htmlFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $rootHtml)) {
        Write-Host "[wrapper] Eliminando copia redundante en $rootHtml ..."
        Remove-Item -LiteralPath $rootHtml -Force
    }
} finally {
    Pop-Location
}

