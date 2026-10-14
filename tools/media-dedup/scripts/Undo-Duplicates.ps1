param(
  [Parameter(Mandatory=$true)][string]$LogPath,
  [switch]$DryRun = $true,
  [int]$MaxItems = 0,
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
$settings = Get-MediaSettings $ConfigPath
$volumes = @(Get-MediaVolume)
$LogPath = (Resolve-Path $LogPath).Path

function Get-UniquePath([string]$path) {
  if (-not (Test-Path $path)) { return $path }
  $dir  = Split-Path -Parent $path
  $name = Split-Path -Leaf $path
  $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
  $ext  = [System.IO.Path]::GetExtension($name)
  $i = 1
  do {
    $candidate = Join-Path $dir ("{0} (restore-{1}){2}" -f $base,$i,$ext)
    $i++
  } while (Test-Path $candidate)
  return $candidate
}

$rows = Import-Csv -Path $LogPath | Where-Object { $_.Result -in @('Moved','ExistsRenamed') }
if (-not $rows) { Write-Host 'Nothing to undo.'; return }

$undone = 0; $skipped = 0; $errors = 0; $considered = 0

foreach ($row in $rows) {
  $considered++
  if ($MaxItems -gt 0 -and $undone -ge $MaxItems) { break }

  $src  = $row.SourcePath
  $dst  = $row.DestPath
  $src = Resolve-MediaSourcePath -Path $src -Record ([pscustomobject]@{ VolumeSerial=$row.SourceVolumeSerial; RelativePath=$row.SourceRelativePath }) -Settings $settings -Volumes $volumes
  $dst = Resolve-MediaSourcePath -Path $dst -Record ([pscustomobject]@{ VolumeSerial=$row.DestinationVolumeSerial; RelativePath=$row.DestinationRelativePath }) -Settings $settings -Volumes $volumes
  if ([string]::IsNullOrWhiteSpace($dst)) { $skipped++; continue }

  if (-not (Test-Path -LiteralPath $dst)) {
    Write-Host ('Skip: dest missing -> ' + $dst)
    $skipped++
    continue
  }

  $restorePath = if (-not (Test-Path -LiteralPath (Split-Path -Parent $src))) {
    # crea carpeta origen si no existe
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $src) | Out-Null }
    $src
  } else {
    if (Test-Path -LiteralPath $src) { Get-UniquePath -path $src } else { $src }
  }

  try {
    if ($DryRun) {
      Write-Host ('DryRun: would move back ' + $dst + ' -> ' + $restorePath)
    } else {
      if ((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ne $row.SHA256) { throw 'Quarantined file differs from logged hash.' }
      Move-Item -LiteralPath $dst -Destination $restorePath
    }
    $undone++
  }
  catch {
    Write-Host ('Error: ' + $_.Exception.Message)
    $errors++
  }
}

Write-Host ('Undo finished. Considered={0} Restored={1} Skipped={2} Errors={3}' -f $considered,$undone,$skipped,$errors)
