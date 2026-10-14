[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1'),
  [string]$OutCsv = (Join-Path $PSScriptRoot '..\artifacts\media_catalog.csv'),
  [string[]]$SourceRoots,
  [long]$MinSizeBytes = -1,
  [int]$MaxItems = 0
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
$settings = Get-MediaSettings $ConfigPath
$volumes = @(Get-MediaVolume)
if ($MinSizeBytes -lt 0) { $MinSizeBytes = $settings.MinSizeBytes }
$targets = if ($SourceRoots) {
  foreach ($root in $SourceRoots) {
    $match = Get-MediaVolumeForPath $root -Volumes $volumes
    $null = Resolve-MediaVolume -Selector @{ VolumeSerial = $match.Volume.VolumeSerial } -Volumes $volumes
    [pscustomobject]@{ Path = [IO.Path]::GetFullPath($root); Volume = $match.Volume; Mount = $match.Mount }
  }
} else {
  foreach ($v in Get-MediaSourceVolume -Settings $settings -Volumes $volumes) {
    [pscustomobject]@{ Path = $v.Root; Volume = $v; Mount = $v.Root }
  }
}
if (-not $targets) { throw 'No readable source volumes selected.' }
foreach ($t in $targets) {
  if (-not (Test-Path -LiteralPath $t.Path -PathType Container)) { throw "Source folder absent: $($t.Path)" }
  if (-not $t.Volume.VolumeSerial) { throw 'Cannot create a portable catalog without volume identity.' }
}
if (Test-Path -LiteralPath $OutCsv) { throw "Catalog exists; choose a new -OutCsv: $OutCsv" }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutCsv)))
$excluded = @($settings.ExcludeDirs | ForEach-Object { $_.Trim('\') })
$excluded += @($settings.DestinationFolder, 'media_final', 'quarantine')
$count = 0
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
& {
  foreach ($t in $targets) {
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($t.Path)
    while ($stack.Count -and ($MaxItems -le 0 -or $count -lt $MaxItems)) {
      $folder = $stack.Pop()
      $children = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Continue)
      foreach ($item in $children) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.PSIsContainer) {
          if ($item.Name -notin $excluded) { $stack.Push($item.FullName) }
          continue
        }
        if ($item.Length -lt $MinSizeBytes -or $item.FullName -eq [IO.Path]::GetFullPath($OutCsv)) { continue }
        if ($MaxItems -gt 0 -and $count -ge $MaxItems) { break }
        if (-not $seen.Add($item.FullName)) { continue }
        try { $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } catch { Write-Warning "Cannot hash $($item.FullName): $_"; continue }
        [pscustomobject][ordered]@{
          Path = $item.FullName; Name = $item.Name; Dir = $item.DirectoryName
          Ext = $item.Extension; SizeBytes = $item.Length; LastWriteTime = $item.LastWriteTime.ToString('o')
          QuickHash = ''; SHA256 = $hash; VolumeSerial = $t.Volume.VolumeSerial
          RelativePath = $item.FullName.Substring($t.Mount.Length)
        }
        $count++
      }
    }
  }
} | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding utf8
Write-Host "Catalog created: $OutCsv."
