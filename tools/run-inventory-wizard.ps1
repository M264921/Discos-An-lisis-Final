# tools\run-inventory-wizard-lite.ps1  (ASCII-safe)
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Paths base
$scriptPath = $PSCommandPath
if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
$here = [System.IO.Path]::GetDirectoryName($scriptPath)
$repo = [System.IO.Directory]::GetParent($here).FullName

$tools = Join-Path $repo "tools"
$test  = Join-Path $tools "test-drive.ps1"
$html  = Join-Path $repo "docs\inventario_pro_offline.html"

if (-not (Test-Path -LiteralPath $test)) { throw "No encuentro: $test" }

Write-Host "=== INVENTORY WIZARD (lite clean) ==="
Write-Host ("repo:   " + $repo)
Write-Host ("tools:  " + $tools)
Write-Host ("html:   " + $html)
Write-Host ""

# Modo
Write-Host "Modo de escaneo:"
Write-Host "  1) Auto   (incremental: usa indice; hashea solo si falta)"
Write-Host "  2) Hash   (completo: recalcula hash)"
Write-Host "  3) Quick  (rapido: sin hash)"
$modeChoice = Read-Host "Elige 1/2/3"
switch ($modeChoice) {
  '2' { $mode = 'Hash' }
  '3' { $mode = 'Quick' }
  default { $mode = 'Auto' }
}
Write-Host ""

# Unidades fijas con .NET
$drives = [System.IO.DriveInfo]::GetDrives() |
  Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
  Sort-Object Name

[int]$i = 0
$map = @{}
Write-Host "Unidades detectadas:"
foreach ($d in $drives) {
  $i++
  $root = $d.Name.TrimEnd('\')  # "C:" , "D:"
  $free = [math]::Round($d.TotalFreeSpace/1GB,1)
  $size = [math]::Round($d.TotalSize/1GB,1)
  Write-Host ("  {0}) {1}  {2} GB libres / {3} GB" -f $i, $root, $free, $size)
  $map[$i] = ($root + '\')       # "C:\"
}
Write-Host "  F) Carpeta concreta (p.ej. D:\Fotos\2024)"
$sel = Read-Host "Selecciona (p.ej. 1,3) o F"

$targets = @()
if ($sel -match '^[Ff]$') {
  $p = Read-Host "Ruta de carpeta o unidad (p.ej. D:\ o D:\Fotos)"
  if (-not $p) { throw "No diste ruta" }
  if ($p -match '^[A-Za-z]:\\?$') { $p = $p.Substring(0,2) + "\" }
  $targets += $p
} else {
  $nums = $sel -split '[,; ]+' | Where-Object { $_ -match '^\d+$' }
  foreach ($n in $nums) {
    if ($map.ContainsKey([int]$n)) { $targets += $map[[int]$n] }
  }
  if (-not $targets.Count) { throw "Seleccion vacia" }
}

# Ejecuta test-drive (mismo proceso)
foreach ($t in $targets) {
  Write-Host ("-> Escaneando {0} (modo {1})" -f $t, $mode)
  & $test -Path $t -Mode $mode -NoOpen
  if ($LASTEXITCODE -ne 0) { Write-Warning ("Fallo escaneo en " + $t) }
}

# Abre visor
if (Test-Path -LiteralPath $html) {
  Write-Host "[OK] Terminado. Abriendo visor..."
  Start-Process $html
} else {
  Write-Warning ("No se encontro el HTML en " + $html)
}
