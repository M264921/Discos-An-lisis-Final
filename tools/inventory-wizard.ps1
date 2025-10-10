[CmdletBinding()]
param(
  [switch]$HashNow,
  [string[]]$Drives,
  [ValidateSet('Media','Otros','Todo')][string]$ContentFilter = 'Media'
)

function Normalize-Root {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $trimmed = $Value.Trim().Trim('"').Trim("'")
  if ($trimmed.Length -eq 2 -and $trimmed[1] -eq ':') { return "$trimmed\" }
  if ($trimmed.Length -ge 2 -and $trimmed[1] -eq ':' -and $trimmed[-1] -ne '\') { return "$trimmed\" }
  return $trimmed
}

$defaults = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -eq $null -and $_.Free -ne $null }).Root |
  ForEach-Object { $_.TrimEnd('\') }
if (-not $Drives -or $Drives.Count -eq 0) { $Drives = $defaults }
$Drives = $Drives | ForEach-Object { Normalize-Root $_ } | Where-Object { $_ }

Write-Host ("Unidades detectadas: {0}" -f ($defaults -join ', ')) -ForegroundColor DarkCyan

if ($HashNow) {
  foreach ($drive in $Drives) {
    if (-not (Test-Path -LiteralPath $drive)) {
      Write-Warning ("No existe {0}" -f $drive)
      continue
    }
    $letter = if ($drive.Length -ge 1) { $drive[0] } else { 'X' }
    $scanName = "scan_{0}.csv" -f ([char]::ToUpper($letter))
    $outPath = "docs\inventory\{0}" -f $scanName
    Write-Host ("Hashing ({0}) en {1} -> {2}" -f $ContentFilter, $drive, $outPath) -ForegroundColor Cyan
    pwsh -NoProfile -ExecutionPolicy Bypass -File tools\hash-drive-to-csv.ps1 -Drive $drive -OutCsv $outPath -ContentFilter $ContentFilter
  }
} else {
  Write-Host "Saltando hash (HashNow no indicado). Continuamos con merge + JSON + HTML..." -ForegroundColor Yellow
}

pwsh -NoProfile -ExecutionPolicy Bypass -File tools\merge-scans.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\csv-to-inventory-json.ps1

# asegura que los visores HTML se regeneren
& tools\ensure-viewers.ps1

Write-Host ("`nHTML principal: {0}" -f (Resolve-Path "docs\view.html")) -ForegroundColor Green
Write-Host ("HTML offline: {0}" -f (Resolve-Path "docs\inventario_interactivo_offline.html")) -ForegroundColor Green
