<# Legacy preview only. Moves now use tools/media-dedup and stable volumes. #>
[CmdletBinding()]
param(
  [string]$CsvPath,
  [ValidatePattern('^[A-Za-z]$')][string]$DriveLetter,
  [string]$DestinationRoot,
  [switch]$WhatIf,
  [switch]$Apply,
  [string]$LogPath
)
$ErrorActionPreference = 'Stop'
if ($Apply) {
  throw 'Movimiento antiguo retirado. Use tools/media-dedup/STORAGE.md: identifique volumenes y genere un plan nuevo antes de aplicar.'
}
if (-not $CsvPath) { $CsvPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'dupes_confirmed.csv' }
if (-not $DriveLetter) { throw 'Indique -DriveLetter para previsualizar. No se presupone I:.' }
if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "CSV no encontrado: $CsvPath" }
Write-Warning 'Solo previsualizacion historica: no se crean directorios ni se mueven archivos.'
Import-Csv -LiteralPath $CsvPath |
  Where-Object { $_.Path -like ('{0}:\*' -f $DriveLetter) } |
  Sort-Object Path -Unique |
  Select-Object Path, Hash, Bytes, @{Name='Action';Expression={'PreviewOnly'}}
