Param(
  [string]$HtmlPath = "docs/inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $HtmlPath)) {
  throw "No existe $HtmlPath"
}

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

# Corrige typos comunes
$html = [regex]::Replace($html, '\bwindiw\b', 'window', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# Captura array JSON de __DATA__/_DATA_
$rx = [regex]'window\.(?:__DATA__|_DATA_)\s*=\s*(\[[\s\S]*?\])\s*;'
$m = $rx.Match($html)

function Get-MetaSummary {
  param([object[]]$Rows)
  if (-not $Rows) { return "Total: 0" }
  $drives = @{}
  foreach ($row in $Rows) {
    if ($null -eq $row) { continue }
    $drive = $null
    if ($row.PSObject.Properties['Drive']) {
      $drive = [string]$row.Drive
    } elseif ($row.PSObject.Properties['_Drive']) {
      $drive = [string]$row._Drive
    }
    if ([string]::IsNullOrWhiteSpace($drive)) { continue }
    $key = $drive.Trim().ToUpperInvariant()
    if (-not $key) { continue }
    if ($drives.ContainsKey($key)) {
      $drives[$key] += 1
    } else {
      $drives[$key] = 1
    }
  }
  $parts = @()
  foreach ($key in ($drives.Keys | Sort-Object)) {
    $parts += "{0}: {1} ficheros" -f $key, $drives[$key]
  }
  $meta = "Total: {0}" -f $Rows.Count
  if ($parts.Count) {
    $meta += " | " + ($parts -join " · ")
  }
  return $meta
}

if ($m.Success) {
  $json = $m.Groups[1].Value
  $rowsObj = @()
  try {
    $parsed = $json | ConvertFrom-Json
    if ($null -ne $parsed) {
      if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
        $rowsObj = @($parsed)
      } else {
        $rowsObj = @($parsed)
      }
    }
  } catch {
    $rowsObj = @()
  }
  $meta = Get-MetaSummary -Rows $rowsObj
  $metaJson = $meta | ConvertTo-Json -Compress
  $inject = "`n<script>window.__INVENTARIO__.setData($json,$metaJson);</script>`n"
  $html = $rx.Replace($html, '')
  $html = [regex]::Replace($html, '</body>\s*</html>\s*$', $inject + '</body></html>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  [IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
  Write-Host "OK: normalizado a __INVENTARIO__.setData con meta: $meta"
} else {
  Write-Host "No se encontró __DATA__/_DATA_; no hay cambios de normalización."
}
