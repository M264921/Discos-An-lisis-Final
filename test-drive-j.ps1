# test-drive-j.ps1
[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z]:$')]
  [string]$Drive = 'J:',
  [string]$ScanOut = '.\docs\inventory\scan_J.csv',
  [string]$JsonOut = '.\docs\data\inventory.json',
  [ValidateSet('Media','Otros','Todo')][string]$ContentFilter = 'Media',
  [switch]$SkipOpen
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$here = Split-Path -Parent $PSCommandPath
Set-Location $here

$combinedCsv = '.\docs\hash_data.csv'

Write-Host ("[*] Hashing {0} (filtro {1}) ..." -f $Drive, $ContentFilter) -ForegroundColor Cyan
pwsh -NoLogo -ExecutionPolicy Bypass -File .\tools\hash-drive-to-csv.ps1 -Drive $Drive -OutCsv $ScanOut -ContentFilter $ContentFilter

# Recolecta todos los scans disponibles
$scans = Get-ChildItem .\docs\inventory\scan_*.csv -ErrorAction SilentlyContinue | Select-Object -Expand FullName
if (-not $scans) {
  throw "No hay scans en .\docs\inventory."
}

Write-Host "[*] Merging scans -> $combinedCsv" -ForegroundColor Cyan
pwsh -NoLogo -ExecutionPolicy Bypass -File .\tools\merge-scans.ps1 -InventoryDir .\docs\inventory -OutCsv $combinedCsv

Write-Host "[*] Generating JSON -> $JsonOut" -ForegroundColor Cyan
pwsh -NoLogo -ExecutionPolicy Bypass -File .\tools\csv-to-inventory-json.ps1 -CsvPath $combinedCsv -JsonPath $JsonOut

Write-Host "[*] Refresh HTML (normalize + embed) ..." -ForegroundColor Cyan
$refreshArgs = @(
  '-NoLogo',
  '-ExecutionPolicy','Bypass',
  '-File','.\tools\refresh-inventory.ps1',
  '-Json',$JsonOut
)
if ($SkipOpen) { $refreshArgs += '-NoOpen' }
pwsh @refreshArgs

# Quick checks
$rows = Get-Content -LiteralPath $JsonOut -Raw | ConvertFrom-Json
if ($null -eq $rows) { $rows = @() }
if ($rows -isnot [System.Collections.IEnumerable]) { $rows = @($rows) }
$jRows = $rows | Where-Object { $_.unidad -eq $Drive }

Write-Host ("[+] Total filas: {0} | En {1} = {2}" -f $rows.Count, $Drive, $jRows.Count) -ForegroundColor Green

$nullHashes = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.sha) })
if ($nullHashes.Count -gt 0) {
  Write-Warning ("Hay {0} filas sin hash." -f $nullHashes.Count)
} else {
  Write-Host "[+] Sin hashes vacios" -ForegroundColor Green
}

if ($SkipOpen) {
  Write-Host "[i] SkipOpen activado: visor no abierto." -ForegroundColor Yellow
}
