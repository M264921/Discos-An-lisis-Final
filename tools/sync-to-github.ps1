[CmdletBinding()]
param(
  [string]$Message,
  [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

if (-not $Message) {
  $Message = "Auto update inventory ({0})" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')
}

Write-Host "== Sync: pull previo ==" -ForegroundColor Cyan
$branch = git rev-parse --abbrev-ref HEAD | Select-Object -First 1
if (-not $branch) {
  throw "No se pudo detectar la rama actual."
}
$branch = $branch.Trim()

$dirty = git status --porcelain
$stashed = $false
if ($dirty) {
  git stash push -k -u -m ("sync-autostash {0}" -f (Get-Date -Format s)) | Out-Null
  $stashed = $true
}

git fetch origin
git pull --rebase --autostash origin $branch
if ($LASTEXITCODE -ne 0) {
  throw "Fallo al hacer pull --rebase. Resuelve conflictos y reintenta."
}

if ($stashed) {
  git stash pop | Out-Null
}
Write-Host "== Pull OK ==" -ForegroundColor Green

git add -A
$pending = git diff --cached --name-only
if (-not $pending) {
  Write-Host "== No hay cambios para publicar (working tree limpio) ==" -ForegroundColor Yellow
  return
}

Write-Host ("== Commit: {0} ==" -f $Message) -ForegroundColor Cyan
git commit -m $Message
if ($LASTEXITCODE -ne 0) {
  throw "Fallo al hacer commit. Revisa el estado y reintenta."
}

if ($NoPush) {
  Write-Host "== Push omitido (NoPush) ==" -ForegroundColor Yellow
  return
}

Write-Host ("== Push a origin/{0} ==" -f $branch) -ForegroundColor Cyan
git push origin $branch
if ($LASTEXITCODE -ne 0) {
  throw "Fallo al hacer push. Revisa credenciales y vuelve a intentar."
}

Write-Host "== Publicacion completada (GitHub Pages se actualizara automaticamente) ==" -ForegroundColor Green
