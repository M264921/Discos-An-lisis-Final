Param(
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $HtmlPath)) { throw "No se genero $HtmlPath" }

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

$html = [regex]::Replace($html, 'windiw', 'window', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$rx = [System.Text.RegularExpressions.Regex]::new('window\.(?:__DATA__|_DATA_)\s*=\s*(\[[\s\S]*?\]);', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$m = $rx.Match($html)
if ($m.Success) {
  $json = $m.Groups[1].Value
  $metaText = 'Normalizado desde __DATA__'
  try {
    $rows = $json | ConvertFrom-Json
    if ($rows) {
      if ($rows -isnot [System.Collections.IEnumerable]) {
        $rows = @($rows)
      }
      $rowsArray = @($rows)
      $metaSegments = @("Total: {0}" -f $rowsArray.Count)
      $driveCounts = @{}
      foreach ($row in $rowsArray) {
        $drive = $null
        if ($row -and $row.PSObject.Properties['Drive']) {
          $drive = ("{0}" -f $row.Drive).Trim()
        }
        if ($drive) {
          $driveUpper = $drive.ToUpperInvariant()
          if (-not $driveCounts.ContainsKey($driveUpper)) {
            $driveCounts[$driveUpper] = 0
          }
          $driveCounts[$driveUpper]++
        }
      }
      if ($driveCounts.Count -gt 0) {
        $driveSummary = $driveCounts.Keys | Sort-Object | ForEach-Object { "{0}: {1} files" -f $_, $driveCounts[$_] }
        $metaSegments += $driveSummary
      }
      $metaText = ($metaSegments -join ' | ').Trim()
    }
  } catch {
    $metaText = 'Normalizado desde __DATA__'
  }
  $metaLiteral = ($metaText | ConvertTo-Json -Compress)
  $inject = "`n<script>window.__INVENTARIO__.setData($json, $metaLiteral);</script>`n"
  $html = $rx.Replace($html, '')
  $html = [regex]::Replace($html, '</body>\s*</html>\s*$', $inject + '</body></html>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  [IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
  Write-Host "OK: normalizado a __INVENTARIO__.setData(...)"
} else {
  Write-Host "No se encontro __DATA__/_DATA_; sin cambios"
}

