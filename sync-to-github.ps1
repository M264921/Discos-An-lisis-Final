# === Añade esto al principio de tools/sync-to-github.ps1 (justo tras setear $RepoRoot si existe) ===
Write-Host "== Sync: pull previo =="
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if (-not $branch) { throw "No se pudo detectar la rama actual." }

# Si hay cambios sin commitear, los guardamos temporalmente
$dirty = (git status --porcelain).Trim()
$stashed = $false
if ($dirty) {
  Write-Host "Hay cambios locales; creando stash temporal..."
  git stash push -k -u -m "sync-autostash $(Get-Date -Format s)" | Out-Null
  $stashed = $true
}

# Traer y rebasar sobre remoto
git fetch origin
git pull --rebase --autostash origin $branch
if ($LASTEXITCODE -ne 0) {
  throw "Fallo al hacer pull --rebase. Resuelve conflictos y reintenta."
}

# Restaurar stash si lo creamos y quedó algo pendiente
if ($stashed) {
  Write-Host "Restaurando cambios locales..."
  git stash pop | Out-Null
}
Write-Host "== Pull OK =="
# === Fin bloque pull ===


# sync-to-github.ps1
$ErrorActionPreference = 'Stop'
$repoDir = "$HOME\Documents\GitHub\Discos-An-lisis-Final"
$pagesUrlBase = "https://m264921.github.io/Discos-An-lisis-Final/inventario_interactivo_offline.html"

Set-Location $repoDir

# 0) Mostrar rama actual
$current = (git rev-parse --abbrev-ref HEAD).Trim()
Write-Host "Rama actual: $current" -ForegroundColor Cyan

# 1) Añadir y commit (solo si hay cambios)
git add -A
$gitStatus = git status --porcelain | Out-String
if ($gitStatus.Trim()) {
  $msg = 'chore: sync UI + scanner + injector (force pages rebuild)'
  git commit -m $msg
  Write-Host "Commit hecho: $msg" -ForegroundColor Green
} else {
  Write-Host "No hay cambios para commitear." -ForegroundColor Yellow
}

# 2) Push a la rama actual
git push -u origin $current

# 3) Si NO estamos en main, crear PR y hacer merge automático (requiere gh logueado)
if ($current -ne "main") {
  try {
    gh pr create --fill --base main --head $current --title "Sync $current -> main" --body "Auto-PR desde script" | Out-Null
  } catch { 
    Write-Host "PR ya existía o no se pudo crear; continuo..." -ForegroundColor Yellow
  }
  try {
    gh pr merge --squash --delete-branch --auto | Out-Null
  } catch {
    Write-Host "Intento de auto-merge fallido o aún en checks; lo haré manualmente." -ForegroundColor Yellow
  }
}

# 4) Actualizar main local y subir
git checkout main
git pull --rebase origin main
git push origin main

# 5) Forzar rebuild de GitHub Pages (gh CLI)
try {
  $origin = (git remote get-url origin)
  if ($origin -match 'github\.com[:/](.+?)/(.+?)\.git$') {
    $owner = $Matches[1]; $repo = $Matches[2]
    gh api -X POST "repos/$owner/$repo/pages/builds" | Out-Null
    Write-Host "✅ Rebuild de GitHub Pages solicitado." -ForegroundColor Green
  } else {
    Write-Host "No pude detectar owner/repo para API Pages." -ForegroundColor Yellow
  }
} catch {
  Write-Host "No se pudo llamar a gh api; continuo sin forzar rebuild." -ForegroundColor Yellow
}

# 6) Abrir página con cache-buster
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$final = "https://m264921.github.io/Discos-An-lisis-Final/inventario_interactivo_offline.html?v=$ts"

try { Start-Process $final }
catch {
  try { Start-Process "explorer.exe" $final }           # fallback 1
  catch { Start-Process "cmd.exe" "/c start $final" }   # fallback 2
}
"$final"
