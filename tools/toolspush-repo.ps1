# tools\push-repo.ps1
[CmdletBinding()]
param(
  [string]$Remote = "",                     # p.ej. https://github.com/tuuser/tu-repo.git  (o git@github.com:tuuser/tu-repo.git)
  [string]$Branch = "main",
  [string]$Message = $( "update: inventario ({0:yyyy-MM-dd HH:mm:ss})" -f (Get-Date) ),
  [switch]$SkipPull,                        # útil en el primer push cuando aún no hay rama remota
  [switch]$Force,                           # fuerza push con --force-with-lease si es necesario
  [switch]$NoStatus                         # no mostrar git status al final
)

$ErrorActionPreference = "Stop"

function Ok($t){ Write-Host $t -ForegroundColor Green }
function Info($t){ Write-Host $t -ForegroundColor Cyan }
function Warn($t){ Write-Warning $t }
function Fail($t){ Write-Host $t -ForegroundColor Red; exit 1 }

# --- Localiza la raíz del repo (carpeta padre de /tools) ---
$here = Split-Path -LiteralPath $PSCommandPath -Parent
$repo = Split-Path -LiteralPath $here -Parent
Set-Location $repo

Info "→ Repo: $repo"

# --- Comprueba git ---
try {
  $v = (& git --version) -join ' '
  Ok "✔ $v"
} catch {
  Fail "git no está disponible en PATH. Instala Git para Windows."
}

# --- .gitignore básico (si no existe) ---
$gi = Join-Path $repo ".gitignore"
if(-not (Test-Path $gi)){
  @"
# Backups y temporales
*.bak
*.tmp
*.log
Thumbs.db
.DS_Store

# Backups del visor
docs/inventario_pro_offline.html.bak_*

# Índice incremental (recreable)
docs/inventory/hash_index.csv
"@ | Set-Content -Encoding UTF8 $gi
  Ok "✔ Creado .gitignore"
}

# --- Inicializa repo si hace falta ---
if(-not (Test-Path (Join-Path $repo ".git"))){
  Info "→ git init"
  git init | Out-Null
  # asegura rama por defecto
  try { git symbolic-ref HEAD "refs/heads/$Branch" | Out-Null } catch {}
  Ok "✔ Repo inicializado"
}

# --- Config de usuario (solo si no existe) ---
$haveName  = (git config user.name 2>$null)
$haveEmail = (git config user.email 2>$null)
if(-not $haveName -or -not $haveEmail){
  Warn "No hay user.name / user.email configurados para este repo."
  Write-Host " Configúralos (ejemplo):" -ForegroundColor Yellow
  Write-Host "   git config user.name  ""Tu Nombre""" -ForegroundColor Yellow
  Write-Host "   git config user.email ""tu@email""" -ForegroundColor Yellow
}

# --- Comprueba remoto existente ---
$remotes = (git remote 2>$null) -split '\r?\n' | Where-Object { $_ }
$haveOrigin = $remotes -contains 'origin'

if($Remote){
  if($haveOrigin){
    Info "→ Actualizando URL de origin"
    git remote set-url origin $Remote
  } else {
    Info "→ Añadiendo origin"
    git remote add origin $Remote
  }
} else {
  if(-not $haveOrigin){
    Warn "No se ha proporcionado -Remote y no existe 'origin'. Saltaré pull/push."
  }
}

# --- Asegura rama actual ---
try {
  $cur = (git rev-parse --abbrev-ref HEAD).Trim()
} catch { $cur = "" }

if(-not $cur -or $cur -eq "HEAD" -or $cur -ne $Branch){
  # crea/usa la rama deseada si no estamos ya en ella
  Info "→ Cambiando/creando rama '$Branch'"
  git checkout -B $Branch | Out-Null
}

# --- Añade y commit ---
Info "→ git add -A"
git add -A

# Evita commit vacío si no hay cambios
$changes = (git status --porcelain)
if([string]::IsNullOrWhiteSpace($changes)){
  Warn "No hay cambios que commitear."
} else {
  Info "→ git commit"
  git commit -m $Message | Out-Null
  Ok "✔ Commit creado"
}

# --- Pull (rebase) si hay remoto y no pediste SkipPull ---
if($haveOrigin -and -not $SkipPull){
  try {
    Info "→ git pull --rebase origin $Branch"
    git pull --rebase origin $Branch
  } catch {
    Warn "Pull con rebase falló. Intento sin rebase…"
    try { git pull origin $Branch } catch { Warn "Pull simple también falló: $($_.Exception.Message)" }
  }
}

# --- Push ---
if($haveOrigin){
  $pushArgs = @('push','-u','origin',$Branch)
  if($Force){ $pushArgs = @('push','--force-with-lease','-u','origin',$Branch) }
  Info ("→ git " + ($pushArgs -join ' '))
  git @pushArgs
  Ok "✔ Push subido a 'origin/$Branch'"
} else {
  Warn "Sin remoto 'origin': no se ha hecho push."
}

if(-not $NoStatus){
  Write-Host ""
  Info "→ git status"
  git status -sb
}