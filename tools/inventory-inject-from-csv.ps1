Param(
  [string]$CsvPath = "",
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"
if (!(Test-Path -LiteralPath $HtmlPath)) { throw "No existe: $HtmlPath" }

if (-not $CsvPath) {
  $cands = @(
    "docs\hash_data.csv",
    "docs\inventory_all.csv"
  ) + (Get-ChildItem -Recurse -File -Filter "inventory*.csv" | ForEach-Object { $_.FullName })
  $CsvPath = ($cands | Where-Object { Test-Path $_ } | Select-Object -First 1)
  if (-not $CsvPath) { throw "No se encontro CSV de inventario. Pasa -CsvPath explicito." }
}

Write-Host "Usando CSV: $CsvPath"

function PickCol {
  param(
    $Row,
    [string[]]$Names
  )
  if (-not $Row) { return $null }
  foreach ($n in $Names) {
    $prop = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $n } | Select-Object -First 1
    if ($prop -and $null -ne $prop.Value) {
      $value = ("{0}" -f $prop.Value).Trim()
      if ($value) { return $prop.Value }
    }
  }
  return $null
}

$tildeN = [char]0xF1
$accentO = [char]0xF3
$sizeColumnNames = @('Length','Size','Bytes','Tamano',"Tama${tildeN}o")
$extColumnNames = @('Extension',"Extensi${accentO}n",'Ext')

$rowsRaw = Import-Csv -LiteralPath $CsvPath
$rowsOut = New-Object System.Collections.Generic.List[object]

foreach ($r in $rowsRaw) {
  $errorCol = PickCol $r @('Error','ErrorMessage','MensajeError')
  if ($errorCol -and $errorCol.ToString().Trim()) { continue }

  $full = PickCol $r @('FullName','FullPath','Path','Ruta','File','Archivo','Location')
  if (-not $full) {
    $dir = PickCol $r @('Directory','Folder','RutaCarpeta','Parent','Carpeta')
    $name = PickCol $r @('Name','FileName','Nombre')
    if ($dir -and $name) { $full = [IO.Path]::Combine($dir,$name) }
  }
  if (-not $full) { continue }

  $full = ("{0}" -f $full).Trim()
  if (-not $full) { continue }
  $full = $full -replace '/', '\\'
  $full = ($full -replace '\\\\+', '\\')

  if ($full -notmatch '^[HhIiJj]:\\') { continue }

  $drive = PickCol $r @('Drive','Unidad')
  if (-not $drive -and $full -match '^[A-Za-z]:') { $drive = $full.Substring(0,1) }
  if (-not $drive) { $drive = 'H' }
  $drive = ("{0}" -f $drive).Substring(0,1).ToUpperInvariant()

  $name = PickCol $r @('Name','FileName','Nombre')
  if (-not $name) { $name = [IO.Path]::GetFileName($full) }

  $ext = PickCol $r $extColumnNames
  if (-not $ext) { $ext = [IO.Path]::GetExtension($full) }
  if (-not $ext) { $ext = '' }
  if ($ext -and $ext[0] -ne '.') { $ext = '.' + $ext }

  $folder = [IO.Path]::GetDirectoryName($full)

  $sizeRaw = PickCol $r $sizeColumnNames
  [int64]$bytes = 0
  $bytesValid = $false
  if ($sizeRaw) {
    if ([int64]::TryParse("{0}" -f $sizeRaw, [ref]$bytes)) {
      $bytesValid = $true
    } else {
      foreach ($cultureName in @('es-ES','en-US','en-GB')) {
        try {
          $culture = [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
          if ([int64]::TryParse("{0}" -f $sizeRaw, [System.Globalization.NumberStyles]::Integer, $culture, [ref]$bytes)) {
            $bytesValid = $true
            break
          }
        } catch {}
      }
    }
  }
  if (-not $bytesValid) {
    try {
      $bytes = ([IO.FileInfo]$full).Length
      $bytesValid = $true
    } catch {}
  }
  $mb = if ($bytesValid) { [Math]::Round($bytes / 1MB, 2) } else { $null }

  $date = PickCol $r @('LastWriteTime','LastWrite','Modified','Fecha','Date')
  if ($date) {
    $date = ("{0}" -f $date).Trim()
    if ($date) {
      $parsed = $false
      foreach ($format in @('yyyy-MM-ddTHH:mm:ss','yyyy-MM-ddTHH:mm:ss.fff','dd/MM/yyyy HH:mm:ss','yyyy-MM-dd HH:mm:ss')) {
        try {
          $tmp = [datetime]::ParseExact($date, $format, [System.Globalization.CultureInfo]::InvariantCulture)
          $date = $tmp.ToString('s')
          $parsed = $true
          break
        } catch {}
      }
      if (-not $parsed) {
        try {
          $tmp = [datetime]::Parse($date, [System.Globalization.CultureInfo]::GetCultureInfo('es-ES'))
          $date = $tmp.ToString('s')
        } catch {}
      }
    }
  }

  $hash = PickCol $r @('Hash','SHA256','Sha256','sha256','checksum','Checksum')
  if ($hash) { $hash = ("{0}" -f $hash).Trim().ToUpperInvariant() }

  $rowsOut.Add([pscustomobject]@{
    Drive          = $drive
    Folder         = $folder
    Name           = $name
    Ext            = $ext
    MB             = $mb
    LastWrite      = $date
    Hash           = $hash
    FullPath       = $full
    FullPathLower  = ([string]$full).ToLowerInvariant()
    Duplicate      = ''
    DuplicateCount = 0
  }) | Out-Null
}

if (-not $rowsOut.Count) {
  Write-Warning "CSV sin filas validas tras el filtrado."
}

$hashGroups = $rowsOut | Where-Object { $_.Hash } | Group-Object Hash
$dupMap = @{}
foreach ($g in $hashGroups) { $dupMap[$g.Name] = $g.Count }

foreach ($row in $rowsOut) {
  if (-not $row.Hash) {
    $row.Duplicate = 'Sin hash'
    $row.DuplicateCount = 0
  } elseif ($dupMap.ContainsKey($row.Hash) -and $dupMap[$row.Hash] -gt 1) {
    $row.Duplicate = 'Duplicado'
    $row.DuplicateCount = $dupMap[$row.Hash]
  } else {
    $row.Duplicate = 'Unico'
    $row.DuplicateCount = 1
  }
}

$rowsOrdered = $rowsOut | Sort-Object FullPath
$byDrive = $rowsOrdered | Group-Object Drive | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
$meta = "Total: {0} | {1}" -f $rowsOrdered.Count, ($byDrive -join " | ")
$metaJson = ($meta | ConvertTo-Json -Compress)
$setDataCall = "if (window.__INVENTARIO__ && typeof window.__INVENTARIO__.setData === 'function') { window.__INVENTARIO__.setData(window.__DATA__ || [], typeof window.__META__ !== 'undefined' ? window.__META__ : 'Cargado por compatibilidad'); }"

$shimScript = @"
<script>
(function(){
  const global = window;
  const inventory = global.__INVENTARIO__ = global.__INVENTARIO__ || {};
  if (typeof inventory.setData !== 'function') {
    inventory.setData = function(rows, meta) {
      const safeRows = Array.isArray(rows) ? rows : [];
      global.__DATA__ = safeRows;
      if (typeof meta !== 'undefined') {
        global.__META__ = meta;
      }
      inventory._lastRows = safeRows;
      inventory._lastMeta = meta;
      return safeRows;
    };
  }
  if (!inventory._shimSeeded) {
    inventory._shimSeeded = true;
    const legacyRows = Array.isArray(global.__DATA__) ? global.__DATA__ : (Array.isArray(global._DATA_) ? global._DATA_ : null);
    const legacyMeta = typeof global.__META__ !== 'undefined' ? global.__META__ : global._META_;
    const compatMeta = typeof legacyMeta !== 'undefined' && legacyMeta !== null ? legacyMeta : 'Cargado por compatibilidad';
    if (legacyRows) {
      inventory.setData(legacyRows, compatMeta);
    }
  }
})();
</script>
"@

$html = Get-Content -Raw -Encoding UTF8 -LiteralPath $HtmlPath
$jsonRows  = ($rowsOrdered | ConvertTo-Json -Depth 4 -Compress)

$pattern = 'window\.__DATA__\s*=\s*\[[\s\S]*?\];'
if ([regex]::IsMatch($html, $pattern)) {
  $replacement = "window.__META__ = $metaJson; window.__DATA__ = $jsonRows; $setDataCall"
  $html = [regex]::Replace($html, $pattern, $replacement, 1)
} else {
  $inject = "<script>window.__META__ = $metaJson; window.__DATA__ = $jsonRows; $setDataCall</script>"
  $html = $html -replace '</body>\s*</html>\s*$', ($inject + '</body></html>')
}

$html = [regex]::Replace($html, '(?s)\s*<script>window\.__INVENTARIO__\.setData\([\s\S]*?\);</script>', '')

if ($html -notmatch 'global.__INVENTARIO__\s*=\s*global.__INVENTARIO__') {
  $shimTrim = $shimScript.TrimEnd()
  $markers = @(
    '<script>(function(){',
    "<script>`r`n(function(){",
    "<script>`n(function(){"
  )
  foreach ($marker in $markers) {
    $pos = $html.IndexOf($marker)
    if ($pos -ge 0) {
      $html = $html.Insert($pos, $shimTrim + "`n")
      break
    }
  }
}


if ($html -match 'Total:\s*0\s*\|') {
  $html = $html -replace 'Total:\s*0\s*\|[^<]*', ($meta -replace '([\\\^\$\*\+\?\{\}\|\(\)\[\]])', '\\$1')
}

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: Inyectadas $($rowsOrdered.Count) filas en $HtmlPath"
Write-Host $meta
