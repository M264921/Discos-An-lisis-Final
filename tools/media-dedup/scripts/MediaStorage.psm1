# Storage metadata only: importing this module never scans or modifies a disk.
function Get-MediaVolume {
  [CmdletBinding()]
  param()
  $partitions = @()
  $disks = @()
  try {
    $partitions = @(Get-Partition -ErrorAction Stop)
    $disks = @(Get-Disk -ErrorAction Stop)
  } catch { Write-Verbose "Physical disk metadata unavailable: $_" }
  try {
    $volumes = @(Get-CimInstance Win32_Volume -ErrorAction Stop)
    foreach ($v in $volumes) {
      if ($v.DriveType -notin 2, 3) { continue }
      $partition = $partitions | Where-Object { $_.AccessPaths -contains $v.DeviceID } | Select-Object -First 1
      $disk = $disks | Where-Object { $partition -and $_.Number -eq $partition.DiskNumber } | Select-Object -First 1
      $mounts = @($partition.AccessPaths | Where-Object { $_ -and $_ -notlike '\\?\Volume*' })
      $root = if ($v.DriveLetter) { "$($v.DriveLetter)\" } elseif ($mounts.Count) { $mounts[0] } else { $v.DeviceID }
      $serial = if ($null -ne $v.SerialNumber) { '{0:X8}' -f [uint32]$v.SerialNumber } else { '' }
      [pscustomobject]@{
        Root = $root
        MountPaths = @($mounts + $v.DeviceID | Select-Object -Unique)
        VolumeSerial = $serial
        VolumeId = $v.DeviceID
        PartitionGuid = [string]$partition.Guid
        DiskUniqueId = [string]$disk.UniqueId
        DiskSerial = [string]$disk.SerialNumber
        Label = [string]$v.Label
        DriveType = if ($v.DriveType -eq 2) { 'Removable' } else { 'Fixed' }
        BusType = [string]$disk.BusType
        SizeBytes = [long]$v.Capacity
        FreeBytes = [long]$v.FreeSpace
        FileSystem = [string]$v.FileSystem
        IsSystem = [bool]($v.BootVolume -or $v.SystemVolume -or $partition.IsSystem -or $partition.IsBoot -or $partition.IsHidden -or $root -eq "$env:SystemDrive\")
        Ready = [bool]($v.FileSystem -and ($v.DriveLetter -or $mounts.Count) -and (Test-Path -LiteralPath $root -PathType Container))
      }
    }
  } catch {
    Write-Warning "Volume identities unavailable. Listing mounted drives only; identity binding is disabled. $_"
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
      if ($d.DriveType -notin 'Fixed', 'Removable') { continue }
      [pscustomobject]@{
        Root = $d.Name; MountPaths = @($d.Name); VolumeSerial = ''; VolumeId = ''
        PartitionGuid = ''; DiskUniqueId = ''; DiskSerial = ''; BusType = ''
        Label = if ($d.IsReady) { $d.VolumeLabel } else { '' }
        DriveType = [string]$d.DriveType
        SizeBytes = if ($d.IsReady) { $d.TotalSize } else { 0 }
        FreeBytes = if ($d.IsReady) { $d.AvailableFreeSpace } else { 0 }
        FileSystem = if ($d.IsReady) { $d.DriveFormat } else { '' }
        IsSystem = ($d.Name -eq "$env:SystemDrive\"); Ready = $d.IsReady
      }
    }
  }
}

function Resolve-MediaVolume {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Selector, [object[]]$Volumes = @(Get-MediaVolume))
  if (-not $Selector.VolumeSerial -and -not $Selector.PartitionGuid) {
    throw 'A VolumeSerial or PartitionGuid is required; drive letters and labels are not identities.'
  }
  $matches = @($Volumes | Where-Object {
    (-not $Selector.VolumeSerial -or $_.VolumeSerial -eq $Selector.VolumeSerial) -and
    (-not $Selector.PartitionGuid -or $_.PartitionGuid -eq $Selector.PartitionGuid)
  })
  if ($matches.Count -ne 1) { throw "Volume absent or ambiguous ($($matches.Count) matches): $($Selector | ConvertTo-Json -Compress)" }
  if (-not $matches[0].Ready) { throw 'Selected volume is unmounted, locked or unreadable.' }
  return $matches[0]
}

function Get-MediaSettings {
  param([Parameter(Mandatory)][string]$ConfigPath)
  $settings = Import-PowerShellDataFile -LiteralPath $ConfigPath
  $local = Join-Path (Split-Path -Parent $ConfigPath) 'storage-bindings.json'
  if (Test-Path -LiteralPath $local) {
    $bindings = Get-Content -LiteralPath $local -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $bindings.Keys) { $settings[$key] = $bindings[$key] }
  }
  return $settings
}

function Get-MediaSourceVolume {
  param([hashtable]$Settings, [object[]]$Volumes = @(Get-MediaVolume))
  if ($Settings.SourceVolumes.Count) {
    foreach ($selector in $Settings.SourceVolumes) { Resolve-MediaVolume -Selector $selector -Volumes $Volumes }
  } else {
    $Volumes | Where-Object { $_.Ready -and ($Settings.IncludeSystemDrive -or -not $_.IsSystem) }
  }
}

function Get-MediaVolumeForPath {
  param([Parameter(Mandatory)][string]$Path, [object[]]$Volumes = @(Get-MediaVolume))
  $full = [IO.Path]::GetFullPath($Path)
  $candidates = foreach ($v in $Volumes) {
    foreach ($mount in @($v.Root) + @($v.MountPaths)) {
      if (-not $mount) { continue }
      $prefix = $mount.TrimEnd('\') + '\'
      if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $full.TrimEnd('\') -eq $mount.TrimEnd('\')) {
        [pscustomobject]@{ Volume = $v; Mount = $prefix; Length = $prefix.Length }
      }
    }
  }
  $match = $candidates | Sort-Object Length -Descending | Select-Object -First 1
  if (-not $match) { throw "No local storage volume contains: $Path" }
  return $match
}

function Join-MediaRelativePath {
  param([string]$Root, [string]$RelativePath)
  if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
    throw 'Relative path escapes the selected volume.'
  }
  return [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $RelativePath))
}

function Resolve-MediaSourcePath {
  param([string]$Path, $Record, [hashtable]$Settings, [object[]]$Volumes)
  if ($Record.VolumeSerial) {
    $v = Resolve-MediaVolume -Selector @{ VolumeSerial = $Record.VolumeSerial } -Volumes $Volumes
    if ([string]::IsNullOrWhiteSpace($Record.RelativePath)) { throw 'Catalog row has identity but no relative path.' }
    return Join-MediaRelativePath $v.Root $Record.RelativePath
  }
  if ($Path -match '^([A-Za-z]):[\\/]') {
    $alias = $Matches[1].ToUpperInvariant()
    if ($Settings.LegacyDriveMap -and $Settings.LegacyDriveMap.ContainsKey($alias)) {
      $v = Resolve-MediaVolume -Selector $Settings.LegacyDriveMap[$alias] -Volumes $Volumes
      return Join-MediaRelativePath $v.Root $Path.Substring(3)
    }
  }
  return $Path
}

function Get-MediaDestination {
  param([string]$DestRoot, [hashtable]$Settings, [object[]]$Volumes)
  if ($DestRoot) { return [IO.Path]::GetFullPath($DestRoot) }
  if (-not $Settings.DestinationVolume.Count) {
    throw 'Select a destination with -DestRoot or Register-MediaStorage.ps1 -DestinationRoot. No drive is assumed.'
  }
  $v = Resolve-MediaVolume -Selector $Settings.DestinationVolume -Volumes $Volumes
  return Join-MediaRelativePath $v.Root $Settings.DestinationFolder
}

function Read-MediaCsv {
  param([Parameter(Mandatory)][string]$Path)
  $reader = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($Path)
  $reader.SetDelimiters(',')
  $reader.HasFieldsEnclosedInQuotes = $true
  $reader.TrimWhiteSpace = $false
  try {
    if ($reader.EndOfData) { return }
    $header = $reader.ReadFields()
    while (-not $reader.EndOfData) {
      $values = $reader.ReadFields()
      if ($values.Count -ne $header.Count) { throw "Invalid CSV row at line $($reader.LineNumber): $Path" }
      $row = [ordered]@{}
      for ($i = 0; $i -lt $header.Count; $i++) { $row[$header[$i]] = $values[$i] }
      [pscustomobject]$row
    }
  } finally { $reader.Close() }
}

Export-ModuleMember -Function Get-MediaVolume, Resolve-MediaVolume, Get-MediaSettings, Get-MediaSourceVolume, Get-MediaVolumeForPath, Join-MediaRelativePath, Resolve-MediaSourcePath, Get-MediaDestination, Read-MediaCsv
