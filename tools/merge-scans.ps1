[CmdletBinding()]
param(
  [string]$InventoryDir = "docs\inventory",
  [string]$OutCsv = "docs\hash_data.csv",
  [switch]$KeepDuplicates
)

$ErrorActionPreference = 'Stop'

function Get-Field {
  param(
    [object]$Row,
    [string[]]$Names
  )
  foreach ($name in $Names) {
    if ($Row.PSObject.Properties[$name]) {
      $value = $Row.$name
      if ($null -ne $value -and ("$value").ToString().Trim()) {
        return ("$value").ToString().Trim()
      }
    }
  }
  return ""
}

function Try-ParseDate {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  [datetime]$parsed = [datetime]::MinValue
  if ([datetime]::TryParse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
    return $parsed.ToUniversalTime()
  }
  $parsed = [datetime]::MinValue
  if ([datetime]::TryParse($Value, [ref]$parsed)) {
    return $parsed.ToUniversalTime()
  }
  return $null
}

function New-Key {
  param($Row)
  $sha = Get-Field $Row @('sha','Sha','hash','Hash','checksum','Checksum')
  if ($sha) {
    return "SHA::{0}" -f $sha.ToUpperInvariant()
  }
  $size   = Get-Field $Row @('tamano','size','length','Length','bytes')
  $ruta   = Get-Field $Row @('ruta','path','dir','directory')
  $nombre = Get-Field $Row @('nombre','name','filename')
  return "PATH::{0}|{1}|{2}" -f $ruta,$nombre,$size
}

$scans = Get-ChildItem -LiteralPath $InventoryDir -Filter "scan_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
if (-not $scans) {
  Write-Host "No hay scans. (esperado: scan_C.csv, scan_F.csv.)" -ForegroundColor Yellow
  exit 1
}

$totalRows = 0

if ($KeepDuplicates) {
  $buffer = New-Object System.Collections.Generic.List[object]
  foreach ($scan in $scans) {
    $rows = Import-Csv -LiteralPath $scan.FullName
    foreach ($row in $rows) {
      $buffer.Add($row)
      $totalRows++
    }
  }
  $buffer | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
  Write-Host ("Combinado (sin depuración) -> {0} ({1} filas)" -f $OutCsv, $totalRows) -ForegroundColor Cyan
  exit 0
}

$map = @{}
$sequence = 0

foreach ($scan in $scans) {
  $rows = Import-Csv -LiteralPath $scan.FullName
  foreach ($row in $rows) {
    $totalRows++
    $key = New-Key $row
    if (-not $key) { continue }

    $sequence++
    $candidate = [pscustomobject]@{
      Row      = $row
      FileTime = $scan.LastWriteTimeUtc
      RowTime  = Try-ParseDate (Get-Field $row @('fecha','date','last','LastWriteTime','modified','mtime'))
      Sequence = $sequence
    }

    if (-not $map.ContainsKey($key)) {
      $map[$key] = $candidate
      continue
    }

    $current = $map[$key]
    $replace = $false

    if ($candidate.RowTime -and $current.RowTime) {
      if ($candidate.RowTime -gt $current.RowTime) {
        $replace = $true
      } elseif ($candidate.RowTime -lt $current.RowTime) {
        $replace = $false
      }
    } elseif ($candidate.RowTime -and -not $current.RowTime) {
      $replace = $true
    }

    if (-not $replace) {
      if ($candidate.FileTime -gt $current.FileTime) {
        $replace = $true
      } elseif ($candidate.FileTime -eq $current.FileTime -and $candidate.Sequence -gt $current.Sequence) {
        $replace = $true
      }
    }

    if ($replace) {
      $map[$key] = $candidate
    }
  }
}

$uniqueRows = $map.Values | ForEach-Object { $_.Row }
$uniqueRows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
$duplicates = $totalRows - $map.Count
Write-Host ("Combinado -> {0} (original: {1} filas, finales únicas: {2}, duplicados descartados: {3})" -f $OutCsv, $totalRows, $map.Count, $duplicates) -ForegroundColor Cyan
