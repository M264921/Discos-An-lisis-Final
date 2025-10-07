Write-Host "== Sync: pull previo =="
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if (-not $branch) { throw "No se pudo detectar la rama actual." }
$dirty = (git status --porcelain).Trim()
$stashed = $false
if ($dirty) { git stash push -k -u -m "sync-autostash $(Get-Date -Format s)" | Out-Null; $stashed = $true }
git fetch origin
git pull --rebase --autostash origin $branch
if ($LASTEXITCODE -ne 0) { throw "Fallo al hacer pull --rebase. Resuelve conflictos y reintenta." }
if ($stashed) { git stash pop | Out-Null }
Write-Host "== Pull OK =="

