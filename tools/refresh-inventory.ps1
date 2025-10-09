<# 
.SYNOPSIS
  Normaliza el HTML, inyecta el JSON y abre el visor PRO.

.EXAMPLE
  pwsh -NoLogo -ExecutionPolicy Bypass -File .\tools\refresh-inventory.ps1
  pwsh -NoLogo -ExecutionPolicy Bypass -File .\tools\refresh-inventory.ps1 -Html .\docs\inventario_pro_offline.html -Json .\docs\data\inventory.json -NoOpen
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path,
  [string]$Html = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'docs\inventario_pro_offline.html'),
  [string]$Json = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'docs\data\inventory.json'),
  [switch]$NoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-File([string]$path){
  if(!(Test-Path $path)){ throw "No existe: $path" }
}

Assert-File $Html
Assert-File $Json

# 1) Normaliza HTML (quita duplicados del script inventory-data, arregla estructura)
$normalizer = Join-Path $RepoRoot 'tools\normalize-inventory-html.ps1'
Assert-File $normalizer
Write-Host "→ Normalizando: $Html" -ForegroundColor Cyan
pwsh -NoLogo -ExecutionPolicy Bypass -File $normalizer -Path $Html

# 2) Inyecta JSON (deja UNA sola etiqueta <script id="inventory-data" type="application/json"> … </script>)
$injector = Join-Path $RepoRoot 'tools\update-inventory-embed.ps1'
Assert-File $injector
Write-Host "→ Inyectando JSON: $Json → $Html" -ForegroundColor Cyan
pwsh -NoLogo -ExecutionPolicy Bypass -File $injector -Html $Html -Json $Json -Backup

# 3) Abrir visor
if(-not $NoOpen){
  Write-Host "→ Abriendo visor..." -ForegroundColor Green
  Start-Process $Html
}

Write-Host "`n✔ Hecho: HTML normalizado + JSON embebido." -ForegroundColor Green
