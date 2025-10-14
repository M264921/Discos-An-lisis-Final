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

# git status outputs nothing (null) when tree is clean; skip trim to avoid null method calls
$dirty = git status --porcelain
$unmergedStatuses = @('DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU')
$unmerged = @()
if ($dirty) {
  $unmerged = $dirty | Where-Object { $_.Length -ge 2 -and $unmergedStatuses -contains $_.Substring(0, 2) }
}
if ($unmerged.Count -gt 0) {
  $conflictList = $unmerged | ForEach-Object { $_.Substring(3) }
  $hint = @('Se detectaron archivos con conflictos sin resolver:')
  $hint += $conflictList | ForEach-Object { "  - $_" }
  $hint += "Ejecuta 'git status' y resuelve cada conflicto. Luego marca los archivos solucionados con 'git add' antes de reintentar."
  throw ($hint -join "`n")
}
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
# git diff --cached also yields null when nothing is staged; guard before checking
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
