param(
  [Parameter(Mandatory=$true)][string]$CsvPath,
  [Parameter(Mandatory=$true)][string]$Quarantine,
  [string]$LogPath,
  [switch]$DryRun = $true,
  [switch]$Resume,
  [string[]]$IncludeDrives,
  [int]$MaxItems = 0,
  [switch]$VerifyHash,
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
$settings = Get-MediaSettings $ConfigPath
$volumes = @(Get-MediaVolume)
$Quarantine = Resolve-MediaSourcePath -Path $Quarantine -Record $null -Settings $settings -Volumes $volumes
$CsvPath = (Resolve-Path $CsvPath).Path
if (-not (Test-Path $Quarantine)) { New-Item -ItemType Directory -Force -Path $Quarantine | Out-Null }
$Quarantine = (Resolve-Path $Quarantine).Path

if (-not $LogPath) { $LogPath = Join-Path $Quarantine 'moves_log.csv' }
$logHeader = 'SHA256,KeepPath,SourcePath,DestPath,Timestamp,Result,Message,SourceVolumeSerial,SourceRelativePath,DestinationVolumeSerial,DestinationRelativePath'
if (-not (Test-Path $LogPath)) { $logHeader | Out-File -FilePath $LogPath -Encoding UTF8 }
$logColumns = (Get-Content -LiteralPath $LogPath -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"') }

function Write-Log([string]$sha,[string]$keep,[string]$src,[string]$dst,[string]$result,[string]$msg='') {
  $ts = Get-Date -Format s
  $sourceMount = $null; $destMount = $null
  try { $sourceMount = Get-MediaVolumeForPath $src -Volumes $volumes } catch {}
  try { if ($dst) { $destMount = Get-MediaVolumeForPath $dst -Volumes $volumes } } catch {}
  [pscustomobject][ordered]@{
    SHA256=$sha; KeepPath=$keep; SourcePath=$src; DestPath=$dst; Timestamp=$ts; Result=$result; Message=$msg
    SourceVolumeSerial=$sourceMount.Volume.VolumeSerial
    SourceRelativePath=if ($sourceMount) { $src.Substring($sourceMount.Mount.Length) } else { '' }
    DestinationVolumeSerial=$destMount.Volume.VolumeSerial
    DestinationRelativePath=if ($destMount) { $dst.Substring($destMount.Mount.Length) } else { '' }
  } | Select-Object -Property $logColumns | Export-Csv -LiteralPath $LogPath -Append -NoTypeInformation -Encoding utf8
}

function Get-DestPath([string]$src, [string]$qRoot) {
  $qual = Split-Path -Qualifier $src
  if ([string]::IsNullOrEmpty($qual)) { return $null }
  $drive = $qual.TrimEnd('\').TrimEnd(':')
  $rel   = $src.Substring($qual.Length)
  $relDir = Split-Path -Parent $rel
  $leaf   = Split-Path -Leaf $src
  $destDir = if ([string]::IsNullOrEmpty($relDir)) { Join-Path $qRoot $drive } else { Join-Path (Join-Path $qRoot $drive) $relDir }
  $destPath = Join-Path $destDir $leaf
  return @{ Dir=$destDir; Path=$destPath }
}

function Get-UniquePath([string]$path) {
  if (-not (Test-Path $path)) { return $path }
  $dir  = Split-Path -Parent $path
  $name = Split-Path -Leaf $path
  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
  $ext  = [System.IO.Path]::GetExtension($name)
  $i = 1
  do {
    $candidate = Join-Path $dir ("{0} (dupe-{1}){2}" -f $base,$i,$ext)
    $i++
  } while (Test-Path $candidate)
  return $candidate
}

$rows = Import-Csv -Path $CsvPath

$already = @{}
if ($Resume -and (Test-Path $LogPath)) {
  Import-Csv -Path $LogPath | ForEach-Object {
    if ($_.Result -eq 'Moved' -or $_.Result -eq 'ExistsRenamed') {
      $already[$_.SourcePath] = $true
    }
  }
}

$filter = $null
if ($IncludeDrives -and $IncludeDrives.Count -gt 0) {
  $set = [System.Collections.Generic.HashSet[string]]::new([string[]]($IncludeDrives | ForEach-Object { $_.TrimEnd(':') }))
  $filter = { param($p) $set.Contains( (Split-Path -Qualifier $p).TrimEnd('\\').TrimEnd(':') ) }
}

$processed = 0     # filas con acción real (move/dryrun)
$skipped = 0
$errors = 0
$considered = 0    # filas leídas

foreach ($row in $rows) {
  $considered++
  $sha  = $row.SHA256
  $keep = $row.KeepPath
  $src  = $row.DupePath
  $keep = Resolve-MediaSourcePath -Path $keep -Record ([pscustomobject]@{ VolumeSerial=$row.KeepVolumeSerial; RelativePath=$row.KeepRelativePath }) -Settings $settings -Volumes $volumes
  $src = Resolve-MediaSourcePath -Path $src -Record ([pscustomobject]@{ VolumeSerial=$row.DupeVolumeSerial; RelativePath=$row.DupeRelativePath }) -Settings $settings -Volumes $volumes

  if ([string]::IsNullOrWhiteSpace($src)) { continue }

  if ($filter -and -not (& $filter $src)) {
    $skipped++
    continue
  }

  if ($Resume -and $already.ContainsKey($src)) {
    Write-Log $sha $keep $src '' 'SkippedResume' 'Already processed'
    $skipped++
    continue
  }

  if (-not (Test-Path -LiteralPath $src)) {
    Write-Log $sha $keep $src '' 'SkippedMissing' 'Source not found'
    $skipped++
    continue
  }

  if ($MaxItems -gt 0 -and $processed -ge $MaxItems) {
    break
  }

  if (-not $keep -or -not (Test-Path -LiteralPath $keep -PathType Leaf) -or $src -eq $keep) {
    Write-Log $sha $keep $src '' 'SkippedNoKeeper' 'Keeper missing or identical to duplicate'
    $skipped++
    continue
  }
  if ($VerifyHash -or -not $DryRun) {
    try {
      $h = Get-FileHash -Algorithm SHA256 -LiteralPath $src
      $keeperHash = Get-FileHash -Algorithm SHA256 -LiteralPath $keep
      if ($h.Hash -ne $sha -or $keeperHash.Hash -ne $sha) {
        Write-Log $sha $keep $src '' 'HashMismatch' ('Expected ' + $sha + ', got ' + $h.Hash)
        $skipped++
        continue
      }
    } catch {
      Write-Log $sha $keep $src '' 'Error' ('Hash calc failed: ' + $_.Exception.Message)
      $errors++
      continue
    }
  }

  $dstInfo = Get-DestPath -src $src -qRoot $Quarantine
  if ($null -eq $dstInfo) {
    Write-Log $sha $keep $src '' 'Error' 'Cannot compute destination'
    $errors++
    continue
  }

  $destDir  = $dstInfo.Dir
  $destPath = $dstInfo.Path

  try {
    if (-not $DryRun -and -not (Test-Path -LiteralPath $destDir)) {
      New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    $finalDest = Get-UniquePath -path $destPath

    if ($DryRun) {
      Write-Log $sha $keep $src $finalDest 'DryRun' 'Simulated move'
    } else {
      Move-Item -LiteralPath $src -Destination $finalDest
      $result = if ($finalDest -eq $destPath) { 'Moved' } else { 'ExistsRenamed' }
      Write-Log $sha $keep $src $finalDest $result ''
    }
    $processed++
  }
  catch {
    Write-Log $sha $keep $src $destPath 'Error' ($_.Exception.Message)
    $errors++
  }
}

Write-Host ('Done. Considered={0} Processed={1} Skipped={2} Errors={3}' -f $considered,$processed,$skipped,$errors)
if ($errors) { throw "Duplicate processing had $errors errors; inspect $LogPath" }
