Param(
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $HtmlPath)) { throw "No se genero $HtmlPath" }

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

$html = [regex]::Replace($html, 'windiw', 'window', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$scriptPattern = '<script[\s\S]*?window\.__DATA__\s*=\s*(\[[\s\S]*?\]);[\s\S]*?</script>'
$rx = [System.Text.RegularExpressions.Regex]::new($scriptPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$m = $rx.Match($html)
if (!$m.Success) {
  Write-Host "No se encontro __DATA__/_DATA_; sin cambios"
  return
}

$json = $m.Groups[1].Value
$metaText = $null

$metaMatch = [System.Text.RegularExpressions.Regex]::Match($m.Value, 'window\.__META__\s*=\s*(.+?);', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if ($metaMatch.Success) {
  $rawMeta = $metaMatch.Groups[1].Value.Trim()
  try {
    $metaText = ($rawMeta | ConvertFrom-Json)
  } catch {
    $metaText = $rawMeta.Trim('"')
  }
}

try {
  $rows = $json | ConvertFrom-Json
  if ($rows) {
    if ($rows -isnot [System.Collections.IEnumerable]) { $rows = @($rows) }
    $rowsArray = @($rows)
    $metaSegments = @("Total: {0}" -f $rowsArray.Count)
    $driveCounts = @{}
    foreach ($row in $rowsArray) {
      $driveRaw = $null
      if ($row -and $row.PSObject.Properties['Drive']) {
        $driveRaw = ("{0}" -f $row.Drive).Trim()
      }
      if ($driveRaw) {
        $driveKey = $driveRaw.ToUpperInvariant()
        if (-not $driveCounts.ContainsKey($driveKey)) {
          $driveCounts[$driveKey] = 0
        }
        $driveCounts[$driveKey]++
      }
    }
    if ($driveCounts.Count -gt 0) {
      $driveSummary = $driveCounts.Keys | Sort-Object | ForEach-Object { "{0}: {1} files" -f $_, $driveCounts[$_] }
      $metaSegments += $driveSummary
    }
    $computedMeta = ($metaSegments -join ' | ').Trim()
    if ([string]::IsNullOrWhiteSpace($metaText)) {
      $metaText = $computedMeta
    }
  }
} catch {
  if (-not $metaText) { $metaText = 'Normalizado desde __DATA__' }
}

if (-not $metaText) { $metaText = 'Normalizado desde __DATA__' }
$metaLiteral = ($metaText | ConvertTo-Json -Compress)
$replacement = "`n<script>window.__INVENTARIO__.setData($json, $metaLiteral);</script>`n"

$html = $rx.Replace($html, $replacement, 1)
[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: normalizado a __INVENTARIO__.setData(...)"
