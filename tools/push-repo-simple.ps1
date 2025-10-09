# tools\push-repo-simple.ps1
param(
  [string]$Remote = "",    # ej: https://github.com/TUUSER/TU-REPO.git  (o git@github.com:TUUSER/TU-REPO.git)
  [string]$Branch = "main",
  [string]$Message = ("update: inventario {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")),
  [switch]$SkipPull,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Say($t,$c="White"){ Write-Host $t -ForegroundColor $c }

# 1) Raíz del repo (carpeta padre de \tools) y cd
$repo = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
Set-Location $repo
Say ("→ Repo: " + $repo) "Cyan"

# 2) Git disponible
try { $v = (& git --version) -join ' '; Say ("✔ " + $v) "Green" }
catch { throw "git no está en PATH" }

# 3) .gitignore básico (si no existe)
$gi = [System.IO.Path]::Combine($repo, ".gitignore")
if (-not (Test-Path $gi)) {
  @"
# Backups y temporales
*.bak
*.tmp
*.log
Thumbs.db
.DS_Store

# Backups del visor
docs/inventario_pro_offline.html.bak_*

# Índice recreable
docs/inventory/hash_index.csv
"@ | Set-Content -Encoding UTF8 -Path $gi
  Say "✔ .gitignore creado" "Green"
}

# 4) init si hace falta
if (-not (Test-Path (Join-Path $repo ".git"))) {
  Say "→ git init" "Cyan"
  git init | Out-Null
  git checkout -B $Branch | Out-Null
  Say "✔ repo inicializado" "Green"
} else {
  # asegura estar en la rama deseada
  $cur = (git rev-parse --abbrev-ref HEAD) 2>$null
  if (-not $cur -or $cur -eq "HEAD" -or $cur -ne $Branch) {
    Say ("→ checkout -B " + $Branch) "Cyan"
    git checkout -B $Branch | Out-Null
  }
}

# 5) remoto origin
$haveOrigin = ((git remote) -split "\r?\n") -contains "origin"
if ($Remote) {
  if ($haveOrigin) {
    Say "→ set-url origin" "Cyan"
    git remote set-url origin $Remote
  } else {
    Say "→ add origin" "Cyan"
    git remote add origin $Remote
    $haveOrigin = $true
  }
} elseif (-not $haveOrigin) {
  Say "⚠ Sin remoto 'origin' (no haré push). Pasa -Remote ..." "Yellow"
}

# 6) add + commit (si hay cambios)
Say "→ git add -A" "Cyan"
git add -A

$changes = git status --porcelain
if ([string]::IsNullOrWhiteSpace($changes)) {
  Say "No hay cambios nuevos" "Yellow"
} else {
  Say "→ git commit" "Cyan"
  git commit -m $Message | Out-Null
  Say "✔ commit creado" "Green"
}

# 7) pull opcional
if ($haveOrigin -and -not $SkipPull) {
  Say "→ git pull --rebase origin $Branch" "Cyan"
  git pull --rebase origin $Branch 2>$null | Out-Null
}

# 8) push
if ($haveOrigin) {
  $args = @("push","-u","origin",$Branch)
  if ($Force) { $args = @("push","--force-with-lease","-u","origin",$Branch) }
  Say ("→ git " + ($args -join " ")) "Cyan"
  git @args
  Say "✔ push hecho" "Green"
}

# 9) status final
Say "`n→ git status -sb" "Cyan"
git status -sb