[CmdletBinding()]
param(
  [string]$CatalogCsv = (Join-Path $PSScriptRoot '..\artifacts\media_catalog.csv'),
  [string]$OutCsv = (Join-Path $PSScriptRoot '..\artifacts\duplicates_flat.csv')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
if (Test-Path -LiteralPath $OutCsv) { throw "Output already exists: $OutCsv" }
$keepers = @{}
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutCsv)))
Read-MediaCsv $CatalogCsv | ForEach-Object {
  $row = $_
  if ($row.SHA256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "Invalid catalog hash: $($row.SHA256)" }
  $key = $row.SHA256.ToUpperInvariant()
  $identity = if ($row.VolumeSerial) { "$($row.VolumeSerial):$($row.RelativePath)" } else { $row.Path }
  if (-not $seen.Add($identity)) { return }
  if (-not $keepers.ContainsKey($key)) { $keepers[$key] = $row; return }
  $keep = $keepers[$key]
  if ([long]$keep.SizeBytes -ne [long]$row.SizeBytes) { throw 'Same hash with different sizes; inspect catalog.' }
  [pscustomobject][ordered]@{
    SHA256 = $key; KeepPath = $keep.Path; KeepSizeMB = ([long]$keep.SizeBytes / 1MB)
    DupePath = $row.Path; DupeDir = $row.Dir; DupeExt = $row.Ext
    DupeSizeMB = ([long]$row.SizeBytes / 1MB); DupeLastWrite = $row.LastWriteTime
    KeepVolumeSerial = $keep.VolumeSerial; KeepRelativePath = $keep.RelativePath
    DupeVolumeSerial = $row.VolumeSerial; DupeRelativePath = $row.RelativePath
  }
} | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding utf8
Write-Host "Duplicate plan created: $OutCsv"
