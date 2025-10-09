# test-drive-j.ps1
[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z]:$')]
  [string]$Drive = 'J:',
  [string]$ScanOut   = ".\docs\inventory\scan_J.csv",
  [string]$JsonOut   = ".\docs\data\inventory.json",
  [switch]$SkipOpen
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
Set-Location $here

Write-Host "→ Hashing $Drive ..." -ForegroundColor Cyan
pwsh -NoLogo -ExecutionPolicy Bypass -File .\tools\hash-drive-to-csv.ps1 -Drive $Drive -Out $ScanOut

# Recolecta todos los scans
$scans = Get-ChildItem .\docs\inventory\scan_*.csv -ErrorAction SilentlyContinue | Select-Object -Expand FullName
if(-not $scans){ throw "No hay scans en .\docs\inventory." }

Write-Host "→ Merging scans → $JsonOut" -ForegroundColor Cyan
pwsh -NoLogo -File .\tools\merge-scans.ps1 -Input $scans -Out $JsonOut

Write-Host "→ Fix JSON ..." -ForegroundColor Cyan
pwsh -NoLogo -File .\tools\fix-inventory-json.ps1 -Path $JsonOut

Write-Host "→ Refresh HTML (normalize + embed) ..." -ForegroundColor Cyan
pwsh -NoLogo -File .\tools\refresh-inventory.ps1

# Verificaciones rápidas
$rows  = Get-Content $JsonOut -Raw | ConvertFrom-Json
$jRows = $rows | Where-Object { ($_.unidad -eq $Drive) }

Write-Host ("✔ Total filas: {0} | En {1} = {2}" -f $rows.Count, $Drive, $jRows.Count) -ForegroundColor Green

$nullHashes = $rows | Where-Object { [string]::IsNullOrWhiteSpace($_.sha) }
if($nullHashes.Count -gt 0){
  Write-Warning ("Hay {0} filas sin hash." -f $nullHashes.Count)
}else{
  Write-Host "✔ Sin hashes vacíos" -ForegroundColor Green
}

if(-not $SkipOpen){
  Start-Process ".\docs\inventario_pro_offline.html"
}