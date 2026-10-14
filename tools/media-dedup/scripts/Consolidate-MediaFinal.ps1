[CmdletBinding()]
param(
  [string]$CatalogCsv = (Join-Path $PSScriptRoot '..\artifacts\media_catalog.csv'),
  [string]$DuplicatesCsv = (Join-Path $PSScriptRoot '..\artifacts\duplicates_flat.csv'),
  [string]$DestRoot,
  [switch]$Move,
  [switch]$DryRun = $true,
  [string]$LogCsv = (Join-Path $PSScriptRoot '..\logs\consolidate_log.csv'),
  [switch]$PlanOnly,
  [int]$MaxItems = 0,
  [int]$ProgressInterval = 30,
  [string[]]$IncludeCategory,
  [int[]]$IncludeYear,
  [switch]$SkipLogged,
  [int]$BeepEveryItems = 0,
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
$settings = Get-MediaSettings $ConfigPath
$volumes = @(Get-MediaVolume)
$DestRoot = Get-MediaDestination -DestRoot $DestRoot -Settings $settings -Volumes $volumes
if (-not (Test-Path -LiteralPath $DestRoot -PathType Container)) { throw "DestRoot does not exist: $DestRoot" }
$logColumns = if (Test-Path -LiteralPath $LogCsv) { (Get-Content -LiteralPath $LogCsv -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"') } } else { @() }

function Write-Log($Sha, $Src, $Dst, $Result, $Message = '') {
  $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($LogCsv)))
  $sourceMount = $null; $destMount = $null
  try { $sourceMount = Get-MediaVolumeForPath $Src -Volumes $volumes } catch {}
  try { $destMount = Get-MediaVolumeForPath $Dst -Volumes $volumes } catch {}
  [pscustomobject][ordered]@{
    SHA256 = $Sha; SourcePath = $Src; DestPath = $Dst; Timestamp = (Get-Date).ToString('s')
    Mode = if ($Move) { 'Move' } else { 'Copy' }; Result = $Result; Message = $Message
    SourceVolumeSerial = $sourceMount.Volume.VolumeSerial
    SourceRelativePath = if ($sourceMount) { $Src.Substring($sourceMount.Mount.Length) } else { '' }
    DestinationVolumeSerial = $destMount.Volume.VolumeSerial
    DestinationRelativePath = if ($destMount) { $Dst.Substring($destMount.Mount.Length) } else { '' }
  } | Select-Object -Property $(if ($logColumns.Count) { $logColumns } else { '*' }) |
    Export-Csv -LiteralPath $LogCsv -Append -NoTypeInformation -Encoding utf8
}
function Get-Category([string]$Ext) {
  if ($Ext -in '.mp4','.m2ts','.avi','.mkv','.mov','.mpg','.mpeg','.mts','.wmv','.m4v') { return 'Video' }
  if ($Ext -in '.jpg','.jpeg','.png','.gif','.heic','.tif','.tiff','.bmp','.raw','.nef','.cr2') { return 'Foto' }
  if ($Ext -in '.mp3','.wav','.flac','.aac','.m4a','.ogg','.wma') { return 'Audio' }
  return 'Docs'
}
function Copy-VerifiedFile($Src, $Dst, $Sha) {
  $inputStream = [IO.File]::Open($Src, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $actual = [Convert]::ToHexString($hasher.ComputeHash($inputStream)) } finally { $hasher.Dispose() }
    if ($actual -ne $Sha) { throw 'Source SHA256 differs from catalog; regenerate the catalog.' }
    $inputStream.Position = 0
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dst)
    $outputStream = [IO.File]::Open($Dst, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    if ((Get-FileHash -LiteralPath $Dst -Algorithm SHA256).Hash -ne $Sha) { throw 'Destination SHA256 mismatch; source retained.' }
  } finally { $inputStream.Dispose() }
  if ($Move) {
    if ((Get-FileHash -LiteralPath $Src -Algorithm SHA256).Hash -ne $Sha) { throw 'Source changed after copying; source retained.' }
    Remove-Item -LiteralPath $Src -ErrorAction Stop
  }
}

$map = @{}
$meta = @{}
if (Test-Path -LiteralPath $CatalogCsv) {
  Read-MediaCsv $CatalogCsv | ForEach-Object {
    $row = $_
    $sha = $row.SHA256.ToUpperInvariant()
    if (-not $sha) { return }
    $path = Resolve-MediaSourcePath -Path $row.Path -Record $row -Settings $settings -Volumes $volumes
    if (-not $map.ContainsKey($sha) -and ($PlanOnly -or (Test-Path -LiteralPath $path))) { $map[$sha] = $path }
    $meta[$sha] = $row
  }
}
if (Test-Path -LiteralPath $DuplicatesCsv) {
  Read-MediaCsv $DuplicatesCsv | ForEach-Object {
    $row = $_
    $sha = $row.SHA256.ToUpperInvariant()
    if (-not $sha -or $map.ContainsKey($sha)) { return }
    foreach ($candidate in @($row.KeepPath, $row.DupePath)) {
      if (-not $candidate) { continue }
      $path = Resolve-MediaSourcePath -Path $candidate -Record $null -Settings $settings -Volumes $volumes
      if ($PlanOnly -or (Test-Path -LiteralPath $path)) { $map[$sha] = $path; break }
    }
  }
}
if (-not $map.Count) { throw 'No usable sources in catalog or duplicate list.' }

$already = @{}
if ($SkipLogged -and (Test-Path -LiteralPath $LogCsv)) {
  Read-MediaCsv $LogCsv | ForEach-Object {
    if ($_.Result -eq 'Success' -and (Test-Path -LiteralPath $_.DestPath) -and
      (Get-FileHash -LiteralPath $_.DestPath -Algorithm SHA256).Hash -eq $_.SHA256) { $already[$_.SHA256] = $true }
  }
}
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$processed = 0; $ok = 0; $skipped = 0; $errors = 0
foreach ($sha in ($map.Keys | Sort-Object)) {
  if ($MaxItems -gt 0 -and $processed -ge $MaxItems) { break }
  if ($already.ContainsKey($sha)) { $skipped++; continue }
  $src = $map[$sha]
  $row = $meta[$sha]
  $category = Get-Category ([IO.Path]::GetExtension($src))
  if ($IncludeCategory -and $category -notin $IncludeCategory) { continue }
  $year = 2000
  try {
    if ($row.LastWriteTime) { $year = ([datetime]$row.LastWriteTime).Year }
    elseif (Test-Path -LiteralPath $src) { $year = (Get-Item -LiteralPath $src).LastWriteTime.Year }
    elseif ($src -match '(19|20)\d{2}') { $year = [int]$Matches[0] }
  } catch { $year = 2000 }
  if ($IncludeYear -and $year -notin $IncludeYear) { continue }
  if ($sha -notmatch '^[A-F0-9]{64}$') { throw "Invalid SHA256: $sha" }
  $base = Join-Path (Join-Path $DestRoot $category) ([string]$year)
  $name = [IO.Path]::GetFileName($src)
  $dst = Join-Path $base $name
  $sameFile = $false
  $suffix = 0
  while ((Test-Path -LiteralPath $dst) -or $reserved.Contains($dst)) {
    if ((Test-Path -LiteralPath $dst -PathType Leaf) -and (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -eq $sha) { $sameFile = $true; break }
    $suffix++
    $dst = Join-Path $base ('{0}_{1}_{2}{3}' -f [IO.Path]::GetFileNameWithoutExtension($name), $sha.Substring(0,8), $suffix, [IO.Path]::GetExtension($name))
  }
  if ($sameFile) { Write-Log $sha $src $dst 'SkippedExists' 'Destination hash verified'; $skipped++; continue }
  $null = $reserved.Add($dst)
  $processed++
  if (-not $PlanOnly -and -not (Test-Path -LiteralPath $src -PathType Leaf)) { Write-Log $sha $src $dst 'SkippedMissing' 'Source not found'; $skipped++; continue }
  try {
    if ($PlanOnly) { $result = 'Plan' }
    elseif ($DryRun) { $result = 'DryRun' }
    else { Copy-VerifiedFile $src $dst $sha; $result = 'Success' }
    Write-Log $sha $src $dst $result
    $ok++
  } catch { Write-Log $sha $src $dst 'Error' $_.Exception.Message; $errors++ }
  if ($ProgressInterval -gt 0 -and $processed % $ProgressInterval -eq 0) { Write-Host "Processed: $processed | OK: $ok | Skip: $skipped | Errors: $errors" }
  if ($BeepEveryItems -gt 0 -and $processed % $BeepEveryItems -eq 0) { try { [Console]::Beep(760,100) } catch {} }
}
Write-Host "Processed: $processed | OK: $ok | Skip: $skipped | Errors: $errors | DryRun: $DryRun | PlanOnly: $PlanOnly"
if ($errors) { throw "Consolidation failed for $errors files; inspect $LogCsv" }
