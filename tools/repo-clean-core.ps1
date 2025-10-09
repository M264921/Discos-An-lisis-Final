[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path,
  [int]$KeepLatestBackups = 1  # cuántos .bak más recientes conservar (0 = ninguno)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Remove-OldBackups {
  param(
    [Parameter(Mandatory)][string]$Folder,
    [Parameter(Mandatory)][string]$Filter,
    [int]$Keep = 1
  )
  if(!(Test-Path $Folder)){ return }

  $files = Get-ChildItem -Path $Folder -Filter $Filter -File -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending
  if($Keep -lt 0){ $Keep = 0 }
  $toDel = $files | Select-Object -Skip $Keep
  foreach($f in $toDel){
    if($PSCmdlet.ShouldProcess($f.FullName,"Remove-Item")){
      Remove-Item -Force $f.FullName
    }
  }
}

Write-Host "→ Repo: $RepoRoot" -ForegroundColor Cyan

# 1) Archivos opcionales a eliminar (una ruta por elemento, sin Join-Path con arrays)
$maybeDelete = @(
  "$RepoRoot\docs\inventario_min_offline.html",
  "$RepoRoot\docs\inventario_standalone.html",
  "$RepoRoot\docs\inventario_interactivo_offline.html" # elimina si ya no lo usas
)

foreach($p in $maybeDelete){
  if(Test-Path $p){
    if($PSCmdlet.ShouldProcess($p,"Remove-Item")){
      Remove-Item -Force $p
    }
  }
}

# 2) Purga .bak y versiones viejas gigantes, dejando los N más recientes
Remove-OldBackups -Folder "$RepoRoot\docs"       -Filter 'inventario_*bak*.html'   -Keep $KeepLatestBackups
Remove-OldBackups -Folder "$RepoRoot\docs\data"  -Filter 'inventory.json.bak_*'    -Keep $KeepLatestBackups

# 3) Borra logs (opcionales para el commit)
$logs = "$RepoRoot\logs"
if(Test-Path $logs){
  $allLogs = Get-ChildItem -Path $logs -File -Recurse -ErrorAction SilentlyContinue
  foreach($f in $allLogs){
    if($PSCmdlet.ShouldProcess($f.FullName,"Remove-Item")){
      Remove-Item -Force $f.FullName
    }
  }
}

# 4) Sanea .gitignore (añade reglas si no existen)
$gitIgnore = "$RepoRoot\.gitignore"
$needed = @"
# === inventory cleanup ===
*.bak
*.bak_*
docs/inventario_*bak*.html
docs/data/inventory.json.bak_*
logs/
"@.Trim()

if(Test-Path $gitIgnore){
  $current = Get-Content $gitIgnore -Raw
  if($current -notmatch 'inventory cleanup'){
    if($PSCmdlet.ShouldProcess($gitIgnore,"Append .gitignore rules")){
      Add-Content -Path $gitIgnore -Value "`r`n$needed`r`n"
    }
  }
}else{
  if($PSCmdlet.ShouldProcess($gitIgnore,"Create .gitignore")){
    Set-Content -Path $gitIgnore -Encoding UTF8 -Value $needed
  }
}

# 5) Recordatorio de núcleo esperado
$mustKeep = @(
  'docs\inventario_pro_offline.html',
  'docs\assets\inventario.css',
  'docs\assets\inventario.js',
  'docs\assets\bridge-inventory-offline.js',
  'docs\data\inventory.json',
  'tools\update-inventory-embed.ps1',
  'tools\normalize-inventory-html.ps1'
)
Write-Host "`n✔ Núcleo esperado:" -ForegroundColor Green
$mustKeep | ForEach-Object { Write-Host "  - $_" }

Write-Host "`nListo. Usa -WhatIf para ver sin borrar." -ForegroundColor Yellow
