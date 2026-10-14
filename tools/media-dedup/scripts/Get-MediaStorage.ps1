[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1'),
  [switch]$SelectedOnly,
  [switch]$AsJson
)
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
$volumes = @(Get-MediaVolume)
if ($SelectedOnly) { $volumes = @(Get-MediaSourceVolume -Settings (Get-MediaSettings $ConfigPath) -Volumes $volumes) }
if ($AsJson) { ConvertTo-Json -InputObject $volumes -Depth 5 } else { $volumes }
