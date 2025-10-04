Param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,
  [string]$HtmlPath = 'docs/inventario_interactivo_offline.html'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "No existe el CSV de respaldo: $CsvPath"
}

if (-not (Test-Path -LiteralPath $HtmlPath)) {
  throw "No existe el HTML de inventario: $HtmlPath"
}

function Get-ColumnValue {
  param(
    [psobject]$Row,
    [string[]]$Names
  )
  foreach ($name in $Names) {
    $match = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if ($match -and $null -ne $match.Value) {
      $value = ("{0}" -f $match.Value).Trim()
      if ($value) { return $match.Value }
    }
  }
  return $null
}

$rowsRaw = Import-Csv -LiteralPath $CsvPath
$rowsOut = New-Object System.Collections.Generic.List[object]

$accentO = [char]0xF3
$extColumnNames = @('Ext', 'Extension', "Extensi${accentO}n")

foreach ($row in $rowsRaw) {
  $path = Get-ColumnValue -Row $row -Names @('Path', 'FullPath', 'FullName', 'Location')
  if (-not $path) { continue }
  $path = ("{0}" -f $path).Trim()
  if (-not $path) { continue }
  $path = $path -replace '/', '\\'
  $path = ($path -replace '\\\\+', '\\')

  $drive = Get-ColumnValue -Row $row -Names @('Drive', 'Unidad')
  if (-not $drive -and $path -match '^[A-Za-z]:') { $drive = $path.Substring(0, 1) }
  $drive = ("{0}" -f $drive).Trim()
  if (-not $drive) { $drive = 'H' }
  $drive = $drive.Substring(0, 1).ToUpperInvariant()

  $folder = Get-ColumnValue -Row $row -Names @('Folder', 'Directory', 'Parent', 'Carpeta')
  if (-not $folder) { $folder = [IO.Path]::GetDirectoryName($path) }

  $name = Get-ColumnValue -Row $row -Names @('Name', 'FileName', 'Nombre')
  if (-not $name) { $name = [IO.Path]::GetFileName($path) }

  $ext = Get-ColumnValue -Row $row -Names $extColumnNames
  if (-not $ext) { $ext = [IO.Path]::GetExtension($path) }
  if ($ext -and $ext[0] -ne '.') { $ext = '.' + $ext }

  $hash = Get-ColumnValue -Row $row -Names @('Hash', 'SHA256', 'Checksum')
  if ($hash) { $hash = ("{0}" -f $hash).Trim().ToUpperInvariant() }

  $mbValue = Get-ColumnValue -Row $row -Names @('MB', 'SizeMB', 'Megabytes', 'Megas')
  [double]$mb = 0
  $mbParsed = $false
  if ($mbValue) {
    if ([double]::TryParse("{0}" -f $mbValue, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$mb)) {
      $mbParsed = $true
    } else {
      foreach ($culture in @('es-ES', 'en-US', 'en-GB')) {
        try {
          $ci = [System.Globalization.CultureInfo]::GetCultureInfo($culture)
          if ([double]::TryParse("{0}" -f $mbValue, [System.Globalization.NumberStyles]::Float, $ci, [ref]$mb)) {
            $mbParsed = $true
            break
          }
        } catch {}
      }
    }
  }
  if (-not $mbParsed) {
    try {
      $info = [IO.FileInfo]::new($path)
      $mb = [Math]::Round($info.Length / 1MB, 2)
      $mbParsed = $true
    } catch {}
  }

  $normalized = [ordered]@{
    Drive = $drive
    Folder = $folder
    Name = $name
    Ext = $ext
    MB = if ($mbParsed) { [Math]::Round($mb, 2) } else { $null }
    Hash = $hash
    Path = $path
  }
  $rowsOut.Add([pscustomobject]$normalized) | Out-Null
}

$rows = @($rowsOut)
$driveCounts = @{}
foreach ($r in $rows) {
  if ($r.Drive) {
    $key = ("{0}" -f $r.Drive).Substring(0, 1).ToUpperInvariant()
    if (-not $driveCounts.ContainsKey($key)) { $driveCounts[$key] = 0 }
    $driveCounts[$key]++
  }
}
foreach ($letter in @('H', 'I', 'J')) {
  if (-not $driveCounts.ContainsKey($letter)) { $driveCounts[$letter] = 0 }
}

$metaParts = @("Total: {0}" -f $rows.Count)
foreach ($letter in @('H', 'I', 'J')) {
  $metaParts += ("{0}: {1} files" -f $letter, $driveCounts[$letter])
}
$otherDrives = $driveCounts.Keys | Where-Object { $_ -notin @('H', 'I', 'J') } | Sort-Object
foreach ($drive in $otherDrives) {
  $metaParts += ("{0}: {1} files" -f $drive, $driveCounts[$drive])
}
$summary = ($metaParts -join ' | ')

$metaPayload = [ordered]@{
  summary = $summary
  total = $rows.Count
  drives = $driveCounts
}

$dataJson = ($rows | ConvertTo-Json -Depth 6 -Compress)
$metaJson = ($metaPayload | ConvertTo-Json -Depth 4 -Compress)

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$setDataRegex = [System.Text.RegularExpressions.Regex]::new('window\.__INVENTARIO__\.setData\(\s*(\[[\s\S]*?\])\s*,\s*([^)]+?)\);', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($setDataRegex.IsMatch($html)) {
  $html = $setDataRegex.Replace($html, "window.__INVENTARIO__.setData($dataJson,$metaJson);", 1)
} else {
  $inject = "<script>window.__INVENTARIO__ = window.__INVENTARIO__ || {}; if (typeof window.__INVENTARIO__.setData === 'function') { window.__INVENTARIO__.setData($dataJson,$metaJson); } else { window.__DATA__ = $dataJson; window.__META__ = $metaJson; }</script>"
  $html = [regex]::Replace($html, '</body>\s*</html>\s*$', $inject + '</body></html>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: Inyectadas $($rows.Count) filas desde $CsvPath"
Write-Host $summary
