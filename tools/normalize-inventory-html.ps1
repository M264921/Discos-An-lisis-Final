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
if (-not $m.Success) {
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

if ($html -notmatch 'global.__INVENTARIO__') {
  $shimScript = @"
<script>
(function(){
  const global = window;
  const inventory = global.__INVENTARIO__ = global.__INVENTARIO__ || {};
  function computeMeta(rows, meta) {
    if (typeof meta === "string" && meta.trim().length > 0) {
      return meta;
    }
    const safeRows = Array.isArray(rows) ? rows : [];
    const drives = {};
    for (let index = 0; index < safeRows.length; index++) {
      const entry = safeRows[index];
      if (!entry || !entry.Drive) { continue; }
      const key = String(entry.Drive).trim().toUpperCase();
      if (!key) { continue; }
      drives[key] = (drives[key] || 0) + 1;
    }
    const parts = Object.keys(drives).sort().map(function(key) {
      return key + ": " + drives[key] + " files";
    });
    const total = "Total: " + safeRows.length;
    return parts.length ? total + " | " + parts.join(" | ") : total;
  }
  if (typeof inventory.setData !== "function") {
    inventory.setData = function(rows, meta) {
      const safeRows = Array.isArray(rows) ? rows : [];
      const summary = computeMeta(safeRows, meta);
      global.__DATA__ = safeRows;
      global.__META__ = summary;
      inventory._lastRows = safeRows;
      inventory._lastMeta = summary;
      return safeRows;
    };
  }
  if (!inventory._shimSeeded) {
    inventory._shimSeeded = true;
    const legacyRows = Array.isArray(global.__DATA__) ? global.__DATA__ : (Array.isArray(global._DATA_) ? global._DATA_ : null);
    const legacyMeta = typeof global.__META__ !== "undefined" ? global.__META__ : global._META_;
    if (legacyRows) {
      const compatMeta = computeMeta(legacyRows, legacyMeta);
      inventory.setData(legacyRows, compatMeta);
    }
  }
})();
</script>
"@

  $insertIndex = $html.IndexOf('window.__INVENTARIO__.setData(')
  if ($insertIndex -gt -1) {
    $html = $html.Insert($insertIndex, $shimScript)
  } else {
    $html = $shimScript + $html
  }
}

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: normalizado a __INVENTARIO__.setData(...)"
