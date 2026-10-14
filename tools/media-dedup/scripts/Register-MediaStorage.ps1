[CmdletBinding()]
param(
  [string[]]$SourceRoots,
  [string]$DestinationRoot,
  [hashtable]$LegacyDriveMap,
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
if (-not $SourceRoots -and -not $DestinationRoot -and -not $LegacyDriveMap) { throw 'Supply source roots, a destination or a legacy drive mapping.' }
$volumes = @(Get-MediaVolume)
function Get-Selector($Path) {
  $match = Get-MediaVolumeForPath -Path $Path -Volumes $volumes
  $selector = @{ VolumeSerial = $match.Volume.VolumeSerial }
  $null = Resolve-MediaVolume -Selector $selector -Volumes $volumes
  return $selector
}
$out = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($ConfigPath))) 'storage-bindings.json'
$bindings = if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
if ($SourceRoots) { $bindings.SourceVolumes = @($SourceRoots | ForEach-Object { Get-Selector $_ }) }
if ($DestinationRoot) {
  $match = Get-MediaVolumeForPath $DestinationRoot -Volumes $volumes
  $bindings.DestinationVolume = Get-Selector $DestinationRoot
  $full = [IO.Path]::GetFullPath($DestinationRoot)
  $bindings.DestinationFolder = $full.Substring([Math]::Min($full.Length, $match.Mount.Length))
  if (-not $bindings.DestinationFolder) { throw 'Destination must be a subfolder, not an entire volume.' }
}
if ($LegacyDriveMap) {
  if (-not $bindings.LegacyDriveMap) { $bindings.LegacyDriveMap = @{} }
  foreach ($key in $LegacyDriveMap.Keys) {
    $alias = $key.TrimEnd(':','\').ToUpperInvariant()
    if ($alias -notmatch '^[A-Z]$') { throw "Invalid historical drive alias: $key" }
    $bindings.LegacyDriveMap[$alias] = Get-Selector $LegacyDriveMap[$key]
  }
}
# Writes settings only, never creates the selected destination folder.
$bindings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding utf8
Write-Host "Saved volume identities to $out"
