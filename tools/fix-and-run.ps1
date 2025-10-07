# fix-and-run.ps1
# Parchea scripts .ps1 del proyecto y opcionalmente ejecuta el pipeline completo.
[CmdletBinding()]
param(
  [switch]$Run,               # Si lo pasas, al final ejecuta: escaneo -> inyección -> HTML
  [string[]]$Roots            # Opcional: unidades a escanear, ej. -Roots 'C:\','F:\'
)

function Write-Ok($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Step($msg){ Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg){ Write-Host $msg -ForegroundColor Red }
function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Path $p | Out-Null } }

# --- Ubicaciones ---
$repo = Get-Location
$tools = Join-Path $repo "tools"
$docs  = Join-Path $repo "docs"
$inv   = Join-Path $docs "inventory"

Ensure-Dir $tools
Ensure-Dir $docs
Ensure-Dir $inv
$backupDir = Join-Path $tools "_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Ensure-Dir $backupDir

# --- Helper: backup simple ---
function Backup([string]$path){
  if(Test-Path -LiteralPath $path){
    Copy-Item -LiteralPath $path -Destination (Join-Path $backupDir ([IO.Path]::GetFileName($path))) -Force
  }
}

# --- 1) Parchear inventory-inject-from-csv.ps1 ---
$injectPath = Join-Path $tools "inventory-inject-from-csv.ps1"
if(Test-Path $injectPath){
  Write-Step "Parchando $injectPath"
  Backup $injectPath
  $txt = Get-Content -LiteralPath $injectPath -Raw

  # Reparar '-match ... -i' -> '-imatch ...' (soporta comillas simples o dobles y espacios)
  $txt = $txt -replace "(-match\s+)(['""])(.+?)\2\s+-i\b",' -imatch $2$3$2'

  # (Opcional) si existen más '-i' sueltos tras operadores, los neutralizamos con -imatch
  # p.ej.  if($x -match '...' -i ) -> -imatch
  $txt = $txt -replace "(-match\s+)(['""])(.+?)\2\s+-i(\s*[\)\}])",' -imatch $2$3$2$4'

  # Garantizar que al final intente regenerar HTML si existe el script
  if($txt -notmatch 'make_inventory_offline\.ps1'){
    $txt += @"

# --- Auto: regenerar HTML si está disponible ---
try {
  \$off = Join-Path \$PSScriptRoot 'make_inventory_offline.ps1'
  if(Test-Path \$off){ & \$off }
} catch { Write-Warning ("No se pudo generar HTML: {0}" -f \$_.Exception.Message) }
"@
  }

  Set-Content -LiteralPath $injectPath -Encoding UTF8 -NoNewline -Value $txt
  Write-Ok "OK: $injectPath parcheado"
} else {
  Write-Err "No existe $injectPath (lo necesito para fusionar CSV y actualizar JSON/HTML)."
}

# --- 2) Parchear scan-drives-interactive.ps1 ---
$scanPath = Join-Path $tools "scan-drives-interactive.ps1"
if(Test-Path $scanPath){
  Write-Step "Parchando $scanPath"
  Backup $scanPath
  $txt = Get-Content -LiteralPath $scanPath -Raw

  # Quitar/neutralizar $PSStyle.OutputRendering
  $txt = $txt -replace '^\s*\$PSStyle\.OutputRendering\s*=\s*.+?$','#$0' -replace '(\r?\n){2,}$',"`r`n"

  # Arreglar el espacio colado: ($_ .Root) -> ($_.Root)
  $txt = $txt -replace '\(\$_\s+\.Root\)','($_.Root)'

  # Arreglar interpolación con $_ dentro de comillas en Write-Warning
  # "Error ... $($_.Exception.Message)" -> Write-Warning ("Error ... {0}: {1}" -f $root, $_.Exception.Message)
  if($txt -match 'Write-Warning\s+"Error durante el escaneo'){
    $txt = $txt -replace 'Write-Warning\s+"Error durante el escaneo de\s*\$root:\s*\$\(\$_\.Exception\.Message\)"',
      'Write-Warning ("Error durante el escaneo de {0}: {1}" -f $root, $_.Exception.Message)'
  }

  # Asegurar param de raíces y progreso/heartbeat mínimo (si no existe ya)
  if($txt -notmatch '\[string\[\]\]\s*\$Roots'){
    $prepend = @"
[CmdletBinding()]
param([string[]]\$Roots)

"@
    $txt = $prepend + $txt
  }

  # Inyectar bloque de progreso/heartbeat si no está
  if($txt -notmatch 'HeartbeatEvery'){
    $progressBlock = @"

# --- Progreso / Heartbeat ---
if(-not \$script:HeartbeatEvery){ \$script:HeartbeatEvery = 500 }
if(-not \$script:ProgressEvery){  \$script:ProgressEvery  = 100 }

function Show-ProgressBlock([string]\$activity, [int]\$count, [ref]\$spinIdx){
  \$spinner = @('|','/','-','\'); \$i = \$spinIdx.Value
  \$i = (\$i + 1) % \$spinner.Count; \$spinIdx.Value = \$i
  Write-Progress -Activity $activity -Status ("{0} Procesados: {1}" -f $spinner[$i], $count) -PercentComplete 0

}
"@
    $txt = $txt -replace 'Get-ChildItem[^\r\n]*-Recurse[^\r\n]*\|','`$spin = 0; $&'  # solo para tener \$spin inicializado
    $txt += "`r`n$progressBlock"
  }

  # Asegurar que al final de todo llama a inyección/HTML (por si tu versión no lo hacía)
  if($txt -notmatch 'inventory-inject-from-csv\.ps1'){
    $txt += @"

# --- Auto: fusionar CSV y actualizar HTML ---
try {
  \$inj = Join-Path \$PSScriptRoot 'inventory-inject-from-csv.ps1'
  if(Test-Path \$inj){ & \$inj }
  else { Write-Warning "No encontré inventory-inject-from-csv.ps1 para fusionar CSV" }
} catch { Write-Warning ("Fallo al inyectar CSV: {0}" -f \$_.Exception.Message) }

try {
  # Abre HTML si existe
  \$html1 = Join-Path (Split-Path \$PSScriptRoot -Parent) 'docs\inventario_interactivo_offline.html'
  \$html2 = Join-Path (Split-Path \$PSScriptRoot -Parent) 'docs\index.html'
  if(Test-Path \$html1){ Start-Process \$html1 }
  elseif(Test-Path \$html2){ Start-Process \$html2 }
} catch { Write-Warning ("No pude abrir la página: {0}" -f \$_.Exception.Message) }
"@
  }

  Set-Content -LiteralPath $scanPath -Encoding UTF8 -NoNewline -Value $txt
  Write-Ok "OK: $scanPath parcheado"
} else {
  Write-Err "No existe $scanPath (lo necesito para el escaneo interactivo)."
}

# --- 3) (Opcional) asegurar make_inventory_offline.ps1 existe ---
$offlinePath = Join-Path $tools "make_inventory_offline.ps1"
if(-not (Test-Path $offlinePath)){
  Write-Step "No encontré make_inventory_offline.ps1. Creo un stub mínimo que rehace el HTML si tienes generador JS."
  Backup $offlinePath
  @"
# make_inventory_offline.ps1 (stub)
param()
try {
  \$docs = Join-Path (Split-Path \$PSScriptRoot -Parent) 'docs'
  \$html = Join-Path \$docs 'inventario_interactivo_offline.html'
  \$index = Join-Path \$docs 'index.html'
  if(Test-Path \$index){ Copy-Item \$index \$html -Force }
  Write-Host "HTML regenerado (stub) -> \$html"
} catch { Write-Warning ("Stub make_inventory_offline falló: {0}" -f \$_.Exception.Message) }
"@ | Set-Content -LiteralPath $offlinePath -Encoding UTF8
}

# --- 4) Ejecutar pipeline (opcional) ---
if($Run){
  Write-Step "Ejecutando pipeline completo…"

  # Unidades por defecto si no pasaste -Roots: solo letras (evito PSDrives raros tipo Temp:)
  if(-not $Roots -or $Roots.Count -eq 0){
    $Roots = (Get-PSDrive -PSProvider FileSystem |
      Where-Object { $_.Root -match '^[A-Z]:\\$' } |
      Select-Object -ExpandProperty Root |
      ForEach-Object { $_ }) # ya con barra final
  }

  Write-Ok ("Raíces a escanear: {0}" -f ($Roots -join ', '))

  # Lanza escaneo con pwsh 7 si está disponible
  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
  $exe  = $(if($pwsh) { "pwsh" } else { "powershell" })
  & $exe -NoProfile -ExecutionPolicy Bypass -File $scanPath -Roots $Roots

  # Por si tu scan no llama a la inyección, la forzamos
  if(Test-Path $injectPath){ & $injectPath }

  # Y abrimos HTML final si existe
  $html1 = Join-Path $docs "inventario_interactivo_offline.html"
  $html2 = Join-Path $docs "index.html"
  if(Test-Path $html1){ Start-Process $html1 }
  elseif(Test-Path $html2){ Start-Process $html2 }
}
Write-Ok "Listo. Backups en: $backupDir"
