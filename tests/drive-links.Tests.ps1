$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/common/mounted-drives.ps1')
$fakeDrives = @(
  [pscustomobject]@{ Name = 'C:\'; DriveType = 'Fixed'; IsReady = $true },
  [pscustomobject]@{ Name = 'K:\'; DriveType = 'Removable'; IsReady = $true },
  [pscustomobject]@{ Name = 'H:\'; DriveType = 'Removable'; IsReady = $false },
  [pscustomobject]@{ Name = 'I:\'; DriveType = 'Network'; IsReady = $false },
  [pscustomobject]@{ Name = 'J:\'; DriveType = 'CDRom'; IsReady = $false },
  [pscustomobject]@{ Name = 'Temp'; DriveType = 'Fixed'; IsReady = $true }
)
$mounted = @(Get-InventoryMountedDrive -Drives $fakeDrives)
if (($mounted.Key -join ',') -ne 'C,K') { throw 'Included an unavailable drive or an alias.' }
$script:probes = @()
function Test-Path {
  param([string]$LiteralPath, [string]$PathType)
  $script:probes += $LiteralPath
  throw "Unexpected path probe: $LiteralPath"
}
$roots = Get-InventoryDriveRoots -Mappings @{ H = 'H:\'; I = 'I:\folder'; J = 'J:\' } -MountedDrives $mounted
if ($roots.Count -ne 0 -or $probes.Count -ne 0) { throw 'Probed an absent drive.' }
$none = Get-InventoryDriveRoots -MountedDrives @()
if ($none.Count -ne 0) { throw 'Invented a fallback drive.' }
$roots = Get-InventoryDriveRoots -MountedDrives $mounted
if (($roots.Keys | Sort-Object) -join ',' -ne 'C,K') { throw 'Automatic detection has fixed letters.' }
function Get-CimInstance {
  param([string]$ClassName, [string]$ErrorAction)
  @(
    [pscustomobject]@{ DeviceID = 'C:'; DriveType = 3; FileSystem = 'NTFS'; Size = 1000 },
    [pscustomobject]@{ DeviceID = 'L:'; DriveType = 2; FileSystem = 'exFAT'; Size = 2000 },
    [pscustomobject]@{ DeviceID = 'I:'; DriveType = 4; FileSystem = $null; Size = $null },
    [pscustomobject]@{ DeviceID = 'J:'; DriveType = 4; FileSystem = $null; Size = $null }
  )
}
$metadata = @(Get-InventoryMountedDrive)
if (($metadata.Key -join ',') -ne 'C,L' -or $probes.Count -ne 0) { throw 'Metadata detection accessed an offline network mapping.' }
Write-Output 'PASS: readiness filtering, absent-drive zero probes, empty detection, automatic mounted roots, offline-network metadata.'
