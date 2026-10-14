$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\MediaStorage.psm1') -Force
function Assert-Storage($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Assert-StorageThrows($Action, $Message) { $failed = $false; try { & $Action } catch { $failed = $true }; Assert-Storage $failed $Message }
$fake = @(
  [pscustomobject]@{ Root='J:\'; MountPaths=@('J:\'); VolumeSerial='A1B2C3D4'; PartitionGuid='guid-a'; Label='Photos'; Ready=$true; IsSystem=$false },
  [pscustomobject]@{ Root='C:\'; MountPaths=@('C:\'); VolumeSerial='FFFFFFFF'; PartitionGuid='guid-b'; Label='Photos'; Ready=$true; IsSystem=$true }
)
$selector = @{ VolumeSerial = 'A1B2C3D4' }
Assert-Storage ((Resolve-MediaVolume $selector -Volumes $fake).Root -eq 'J:\') 'Identity not resolved after drive change.'
$record = [pscustomobject]@{ VolumeSerial='A1B2C3D4'; RelativePath='photos\image.jpg' }
Assert-Storage ((Resolve-MediaSourcePath 'H:\photos\image.jpg' $record @{} $fake) -eq 'J:\photos\image.jpg') 'Catalog uses historical letter.'
Assert-Storage ((Resolve-MediaSourcePath 'H:\photos\image.jpg' $null @{ LegacyDriveMap=@{ H=$selector } } $fake) -eq 'J:\photos\image.jpg') 'Legacy mapping not applied.'
Assert-Storage (@(Get-MediaSourceVolume @{ SourceVolumes=@(); IncludeSystemDrive=$false } -Volumes $fake).Count -eq 1) 'System drive not excluded.'
Assert-StorageThrows { Resolve-MediaVolume @{ VolumeSerial='ABSENT' } -Volumes $fake } 'Missing volume accepted.'
Assert-StorageThrows { Resolve-MediaVolume $selector -Volumes @($fake[0], $fake[0]) } 'Ambiguous volume accepted.'
Assert-StorageThrows { Resolve-MediaVolume @{ Label='Photos' } -Volumes $fake } 'Label used as identity.'
$locked = [pscustomobject]@{ VolumeSerial='A1B2C3D4'; Ready=$false }
Assert-StorageThrows { Resolve-MediaVolume $selector -Volumes @($locked) } 'Locked volume accepted.'
Assert-StorageThrows { Join-MediaRelativePath 'J:\' '..\outside.txt' } 'Traversal accepted.'
Assert-StorageThrows { Join-MediaRelativePath 'J:\' 'C:\outside.txt' } 'Absolute relative path accepted.'
Assert-StorageThrows { Get-MediaDestination '' @{ DestinationVolume=@{} } $fake } 'Implicit destination accepted.'
$mounted = [pscustomobject]@{ Root='C:\mount\photos\'; MountPaths=@('C:\mount\photos\'); VolumeSerial='00000001'; Ready=$true }
Assert-Storage ((Get-MediaVolumeForPath 'C:\mount\photos\one.jpg' -Volumes @($fake[1],$mounted)).Volume.VolumeSerial -eq '00000001') 'Folder mount matched to its parent drive.'
Write-Host 'Storage regression: 12 checks passed.'
