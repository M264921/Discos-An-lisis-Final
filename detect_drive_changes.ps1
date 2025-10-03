# =============================== DETECT DRIVE CHANGES ===============================
# Escanea las unidades especificadas con reindex_hij.py y compara contra index_by_hash.csv.
# Genera un resumen por unidad con archivos nuevos, eliminados y modificados, junto con
# CSVs de detalle en la carpeta de _snapshots.
# ====================================================================================

[CmdletBinding()]
param(
  [string[]]$Drives = @('H','I','J'),
  [string]$RepoRoot,
  [string]$Python = 'python',
  [string]$Baseline = 'index_by_hash.csv',
  [string]$SnapshotRoot,
  [switch]$SkipScan,
  [string]$CurrentIndex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
  param([string]$Base, [string]$Relative)
  if ([System.IO.Path]::IsPathRooted($Relative)) { return $Relative }
  return Join-Path $Base $Relative
}

$scriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
if (-not $RepoRoot) {
  $RepoRoot = Split-Path -Parent $scriptRoot
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$baselinePath = Resolve-RepoPath -Base $RepoRoot -Relative $Baseline
if (-not (Test-Path -LiteralPath $baselinePath)) {
  throw "No se encontró el inventario base en $baselinePath. Ejecuta primero tools\\Reindex-HIJ.ps1."
}

$pythonExe = (Get-Command $Python -ErrorAction Stop).Source
$reindexScript = Join-Path $RepoRoot 'tools\reindex_hij.py'
if (-not (Test-Path -LiteralPath $reindexScript)) {
  throw "No se localizó tools\\reindex_hij.py en $RepoRoot"
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ($SnapshotRoot) {
  $snapshotParent = if ([System.IO.Path]::IsPathRooted($SnapshotRoot)) {
    $SnapshotRoot
  } else {
    Join-Path $RepoRoot $SnapshotRoot
  }
} else {
  $snapshotParent = Join-Path $RepoRoot '_snapshots'
}

$latestSnapshotDir = $null
$currentIndexPath  = $null

if ($SkipScan) {
  if (-not $CurrentIndex) {
    throw 'Cuando usas -SkipScan debes indicar -CurrentIndex con el CSV actual a comparar.'
  }
  $currentIndexPath = Resolve-RepoPath -Base $RepoRoot -Relative $CurrentIndex
  if (-not (Test-Path -LiteralPath $currentIndexPath)) {
    throw "No se encontró el CSV actual en $currentIndexPath"
  }
  $latestSnapshotDir = Split-Path -Parent $currentIndexPath
  if (-not $latestSnapshotDir) {
    $latestSnapshotDir = $snapshotParent
  }
} else {
  $latestSnapshotDir = Join-Path $snapshotParent $timestamp
  New-Item -ItemType Directory -Force -Path $latestSnapshotDir | Out-Null

  $arguments = @($reindexScript, '--output-root', $RepoRoot, '--skip-copy', '--snapshot-dir', $latestSnapshotDir)
  if ($Drives -and $Drives.Count) {
    $arguments += '--drives'
    $arguments += $Drives
  }

  Write-Host "Escaneando unidades con reindex_hij.py ..."
  $process = & $pythonExe @arguments 2>&1
  if ($process) { $process | ForEach-Object { Write-Host $_ } }
  if ($LASTEXITCODE -ne 0) {
    throw "La ejecución de reindex_hij.py terminó con código $LASTEXITCODE"
  }
  $currentIndexPath = Join-Path $latestSnapshotDir 'index_by_hash.csv'
  if (-not (Test-Path -LiteralPath $currentIndexPath)) {
    throw "No se generó index_by_hash.csv en $latestSnapshotDir"
  }
}

function Normalize-PathKey {
  param([string]$Path)
  if (-not $Path) { return '' }
  $normalized = $Path.Trim()
  $normalized = $normalized -replace '/', '\\'
  return $normalized.ToLowerInvariant()
}

$culture = [System.Globalization.CultureInfo]::GetCultureInfo('es-ES')

function Convert-IndexRow {
  param([pscustomobject]$Row, [string]$Origin)
  $rawLength = $Row.Length
  if (-not $rawLength) { $rawLength = '0' }
  $length = 0L
  [long]::TryParse($rawLength, [ref]$length) | Out-Null
  $drive = if ($Row.Drive) { $Row.Drive.Trim().ToUpper() } else {
    if ($Row.Path -match '^[A-Za-z]:') { $Row.Path.Substring(0,1).ToUpper() } else { '' }
  }
  $lastWrite = $null
  if ($Row.LastWrite) {
    [datetime]::TryParseExact($Row.LastWrite, 'dd/MM/yyyy HH:mm:ss', $culture, [System.Globalization.DateTimeStyles]::None, [ref]$lastWrite) | Out-Null
  }
  if (-not $lastWrite) {
    $lastWrite = [datetime]::MinValue
  }
  $hashValue = $Row.Hash
  if (-not $hashValue) { $hashValue = '' }
  return [pscustomobject]@{
    Origin     = $Origin
    Key        = Normalize-PathKey $Row.Path
    Path       = $Row.Path
    Drive      = $drive
    Hash       = $hashValue.ToUpper()
    Length     = $length
    LastWrite  = $lastWrite
  }
}

$baselineRows = Import-Csv -LiteralPath $baselinePath
$currentRows  = Import-Csv -LiteralPath $currentIndexPath

$baselineMap = @{}
foreach ($row in $baselineRows) {
  $item = Convert-IndexRow -Row $row -Origin 'baseline'
  if ($item.Key) { $baselineMap[$item.Key] = $item }
}

$currentMap = @{}
foreach ($row in $currentRows) {
  $item = Convert-IndexRow -Row $row -Origin 'current'
  if ($item.Key) { $currentMap[$item.Key] = $item }
}

$added    = New-Object System.Collections.Generic.List[object]
$removed  = New-Object System.Collections.Generic.List[object]
$changed  = New-Object System.Collections.Generic.List[object]

foreach ($key in $currentMap.Keys) {
  if (-not $baselineMap.ContainsKey($key)) {
    $added.Add($currentMap[$key]) | Out-Null
  } else {
    $currentItem = $currentMap[$key]
    $baseItem    = $baselineMap[$key]
    if ($currentItem.Hash -ne $baseItem.Hash -or $currentItem.Length -ne $baseItem.Length) {
      $changed.Add([pscustomobject]@{
        Key            = $key
        Drive          = $currentItem.Drive
        Path           = $currentItem.Path
        OldHash        = $baseItem.Hash
        NewHash        = $currentItem.Hash
        OldLength      = $baseItem.Length
        NewLength      = $currentItem.Length
        OldLastWrite   = $baseItem.LastWrite
        NewLastWrite   = $currentItem.LastWrite
      }) | Out-Null
    }
  }
}

foreach ($key in $baselineMap.Keys) {
  if (-not $currentMap.ContainsKey($key)) {
    $removed.Add($baselineMap[$key]) | Out-Null
  }
}

function Summarize {
  param([System.Collections.Generic.IEnumerable[object]]$Rows, [string]$DriveProperty = 'Drive')
  $totals = @{}
  foreach ($row in $Rows) {
    $driveRaw = $row.$DriveProperty
    if (-not $driveRaw) { $driveRaw = '' }
    $drive = $driveRaw.ToString().ToUpper()
    if (-not $drive) { $drive = '(sin drive)' }
    if (-not $totals.ContainsKey($drive)) {
      $totals[$drive] = [pscustomobject]@{ Drive = $drive; Count = 0; Bytes = 0L }
    }
    $entry = $totals[$drive]
    $entry.Count++
    $lengthValue = $row.Length
    if (-not $lengthValue -and $row.NewLength) { $lengthValue = $row.NewLength }
    if (-not $lengthValue) { $lengthValue = 0L }
    $entry.Bytes += [long]$lengthValue
  }
  return $totals.Values | Sort-Object Drive
}

$addedSummary   = Summarize -Rows $added
$removedSummary = Summarize -Rows $removed
$changedSummary = Summarize -Rows $changed

function Format-Bytes {
  param([long]$Bytes)
  if ($Bytes -eq 0) { return '0 MB' }
  $mb = [math]::Round($Bytes / 1MB, 2)
  if ($mb -ge 1024) {
    $gb = [math]::Round($Bytes / 1GB, 2)
    return "$gb GB"
  }
  return "$mb MB"
}

$allDrives = @([System.Collections.Generic.HashSet[string]]::new())
foreach ($entry in $addedSummary) { $null = $allDrives.Add($entry.Drive) }
foreach ($entry in $removedSummary) { $null = $allDrives.Add($entry.Drive) }
foreach ($entry in $changedSummary) { $null = $allDrives.Add($entry.Drive) }
$driveList = @($allDrives) | Sort-Object

Write-Host ""
Write-Host '===== Resumen de cambios por unidad ====='
if (-not $driveList.Count) {
  Write-Host 'No se detectaron diferencias entre el inventario base y el actual.'
} else {
  foreach ($drive in $driveList) {
    $addedEntry   = $addedSummary   | Where-Object { $_.Drive -eq $drive }
    $removedEntry = $removedSummary | Where-Object { $_.Drive -eq $drive }
    $changedEntry = $changedSummary | Where-Object { $_.Drive -eq $drive }
    $addedCount   = if ($addedEntry) { $addedEntry.Count } else { 0 }
    $removedCount = if ($removedEntry) { $removedEntry.Count } else { 0 }
    $changedCount = if ($changedEntry) { $changedEntry.Count } else { 0 }
    $addedBytes   = if ($addedEntry) { Format-Bytes $addedEntry.Bytes } else { '0 MB' }
    $removedBytes = if ($removedEntry) { Format-Bytes $removedEntry.Bytes } else { '0 MB' }
    $changedBytes = if ($changedEntry) { Format-Bytes $changedEntry.Bytes } else { '0 MB' }
    Write-Host ("{0}: +{1} ({2})  -{3} ({4})  ~{5} ({6})" -f $drive, $addedCount, $addedBytes, $removedCount, $removedBytes, $changedCount, $changedBytes)
  }
}

$totalAddedBytes   = ($added | Measure-Object Length -Sum).Sum
$totalRemovedBytes = ($removed | Measure-Object Length -Sum).Sum
$totalChangedCount = $changed.Count
Write-Host ""
Write-Host "Totales:"
Write-Host ("  Nuevos:      {0:n0} archivos ({1})" -f $added.Count, (Format-Bytes $totalAddedBytes))
Write-Host ("  Eliminados:  {0:n0} archivos ({1})" -f $removed.Count, (Format-Bytes $totalRemovedBytes))
Write-Host ("  Modificados: {0:n0} archivos" -f $totalChangedCount)
Write-Host ""

$reports = @{}
if ($added.Count) {
  $path = Join-Path $latestSnapshotDir 'changes_added.csv'
  $added | Select-Object Drive, Path, Hash, Length, @{n='LastWrite';e={ $_.LastWrite.ToString('yyyy-MM-dd HH:mm:ss') }} | Export-Csv -LiteralPath $path -Encoding UTF8 -NoTypeInformation
  $reports['added'] = $path
}
if ($removed.Count) {
  $path = Join-Path $latestSnapshotDir 'changes_removed.csv'
  $removed | Select-Object Drive, Path, Hash, Length, @{n='LastWrite';e={ $_.LastWrite.ToString('yyyy-MM-dd HH:mm:ss') }} | Export-Csv -LiteralPath $path -Encoding UTF8 -NoTypeInformation
  $reports['removed'] = $path
}
if ($changed.Count) {
  $path = Join-Path $latestSnapshotDir 'changes_modified.csv'
  $changed | Select-Object Drive, Path, OldHash, NewHash, OldLength, NewLength, @{n='OldLastWrite';e={ $_.OldLastWrite.ToString('yyyy-MM-dd HH:mm:ss') }}, @{n='NewLastWrite';e={ $_.NewLastWrite.ToString('yyyy-MM-dd HH:mm:ss') }} | Export-Csv -LiteralPath $path -Encoding UTF8 -NoTypeInformation
  $reports['modified'] = $path
}

Write-Host "Reportes generados en: $latestSnapshotDir"
foreach ($key in $reports.Keys) {
  Write-Host ("  - {0}: {1}" -f $key, $reports[$key])
}
Write-Host ""
Write-Host "Para actualizar la tabla interactiva ejecuta luego update_pages_inventory.ps1"
