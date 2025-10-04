Param(
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $HtmlPath)) {
  throw "No se encontro $HtmlPath"
}

function Escape-ScriptJson {
  param([string]$Json)
  if ($null -eq $Json) { return '' }
  return ($Json -replace '</', '<\/')
}

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$dataMatch = [regex]::Match($html, '<script\s+id="inventory-data"[^>]*>([\s\S]*?)</script>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if (-not $dataMatch.Success) {
  Write-Host 'No se encontro <script id="inventory-data">. Sin cambios.'
  return
}

$metaMatch = [regex]::Match($html, '<script\s+id="inventory-meta"[^>]*>([\s\S]*?)</script>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$dataJson = $dataMatch.Groups[1].Value.Trim()
$rows = @()
if ($dataJson) {
  try {
    $parsed = $dataJson | ConvertFrom-Json
    if ($parsed) {
      if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
        $rows = @($parsed)
      } else {
        $rows = @($parsed)
      }
    }
  } catch {
    Write-Warning "No se pudo leer inventory-data como JSON."
  }
}

if (-not $rows) {
  Write-Host 'Bloque inventory-data sin filas. Nada que normalizar.'
  return
}

$driveCounts = @{}
$driveBytes = @{}
$typeCounts = @{}
$totalBytes = 0L

foreach ($row in $rows) {
  $drive = if ($row.PSObject.Properties['drive']) { ("{0}" -f $row.drive).Trim().ToUpperInvariant() } else { '' }
  $type = if ($row.PSObject.Properties['type']) { ("{0}" -f $row.type).Trim().ToLowerInvariant() } else { 'otro' }
  $size = 0L
  if ($row.PSObject.Properties['size']) {
    [long]::TryParse(("{0}" -f $row.size), [ref]$size) | Out-Null
  }
  if ($drive) {
    if (-not $driveCounts.ContainsKey($drive)) { $driveCounts[$drive] = 0 }
    if (-not $driveBytes.ContainsKey($drive)) { $driveBytes[$drive] = 0L }
    $driveCounts[$drive]++
    $driveBytes[$drive] += $size
  }
  if (-not $typeCounts.ContainsKey($type)) { $typeCounts[$type] = 0 }
  $typeCounts[$type]++
  $totalBytes += $size
}

$metaObject = [ordered]@{
  total = $rows.Count
  totalBytes = $totalBytes
  driveCounts = [ordered]@{}
  driveBytes = [ordered]@{}
  typeCounts = [ordered]@{}
  generatedAt = (Get-Date).ToUniversalTime().ToString('s')
}
foreach ($driveKey in ($driveCounts.Keys | Sort-Object)) {
  $metaObject.driveCounts[$driveKey] = $driveCounts[$driveKey]
  $metaObject.driveBytes[$driveKey] = $driveBytes[$driveKey]
}
foreach ($typeKey in ($typeCounts.Keys | Sort-Object)) {
  $metaObject.typeCounts[$typeKey] = $typeCounts[$typeKey]
}

$metaJson = $metaObject | ConvertTo-Json -Depth 6 -Compress
$newDataJson = $rows | ConvertTo-Json -Depth 4 -Compress

$metaPayload = Escape-ScriptJson -Json $metaJson
$dataPayload = Escape-ScriptJson -Json $newDataJson

$html = [regex]::Replace($html, '<script\s+id="inventory-meta"[^>]*>[\s\S]*?</script>', "<script id=\"inventory-meta\" type=\"application/json\">$metaPayload</script>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$html = [regex]::Replace($html, '<script\s+id="inventory-data"[^>]*>[\s\S]*?</script>', "<script id=\"inventory-data\" type=\"application/json\">$dataPayload</script>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: normalizado inventory-data/meta en $HtmlPath"
