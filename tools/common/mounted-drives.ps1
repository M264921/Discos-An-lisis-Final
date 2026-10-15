# Enumerate only drive letters reported by Windows; never probe absent letters.
function Get-InventoryMountedDrive {
  [CmdletBinding()]
  param([object[]]$Drives)
  if (-not $PSBoundParameters.ContainsKey('Drives')) {
    try {
      # Logical-disk metadata omits media for disconnected mappings. No path probes
      # are needed, and offline network letters do not delay each viewer refresh.
      foreach ($disk in @(Get-CimInstance Win32_LogicalDisk -ErrorAction Stop)) {
        if ($disk.DriveType -notin 2, 3, 4, 5) { continue }
        if (-not $disk.FileSystem -or $null -eq $disk.Size -or $disk.Size -le 0) { continue }
        if ($disk.DeviceID -notmatch '^([A-Za-z]):$') { continue }
        [pscustomobject]@{ Key = $Matches[1].ToUpperInvariant(); Root = $disk.DeviceID + '\' }
      }
      return
    } catch {
      Write-Verbose 'Logical-disk metadata unavailable; checking local mounted media only.'
      $Drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -in 'Fixed', 'Removable', 'CDRom' })
    }
  }
  foreach ($drive in $Drives) {
    if ($drive.Name -notmatch '^([A-Za-z]):[\\/]$') { continue }
    $key = $Matches[1].ToUpperInvariant()
    try {
      if ($drive.DriveType -notin 'Fixed', 'Removable', 'Network', 'CDRom') { continue }
      if (-not $drive.IsReady) { continue }
      [pscustomobject]@{ Key = $key; Root = $drive.Name }
    } catch { continue }
  }
}

function Get-InventoryDriveRoots {
  [CmdletBinding()]
  param(
    [hashtable]$Mappings,
    [AllowEmptyCollection()][object[]]$MountedDrives = @(Get-InventoryMountedDrive)
  )
  $mounted = @{}
  foreach ($drive in $MountedDrives) { $mounted[$drive.Key] = $drive.Root }
  if ($null -eq $Mappings) { return $mounted }
  $roots = @{}
  foreach ($entry in $Mappings.GetEnumerator()) {
    $path = [string]$entry.Value
    if ($path -notmatch '^([A-Za-z]):[\\/]') { continue }
    $physicalKey = $Matches[1].ToUpperInvariant()
    # Do not call Test-Path or Resolve-Path on a letter Windows did not report.
    if (-not $mounted.ContainsKey($physicalKey)) { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
    $full = (Resolve-Path -LiteralPath $path).ProviderPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $key = ([string]$entry.Key).TrimEnd(':').ToUpperInvariant()
    if ($key -match '^[A-Z]$') { $roots[$key] = $full }
  }
  return $roots
}
