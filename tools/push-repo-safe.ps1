# tools\push-repo-safe.ps1
[CmdletBinding()]
param(
  [string]$Remote = "origin",
  [string]$Branch = "main",
  [int]$WarnMB = 90,       # avisa si algo >= 90MB
  [int]$BlockMB = 100      # bloquea push si algo >= 100MB sin LFS
)

$ErrorActionPreference = 'Stop'
function Say($m,$c="Yellow"){ Write-Host $m -ForegroundColor $c }

# 0) Asegura ignores básicos (no versionar HTML offline gigantes)
$gi = ".gitignore"
$lines = @(
  "docs/inventario_pro.html",
  "docs/inventario_pro_offline.html.bak_*",
  "docs/inventario_pro_offline.html.bak_*",
  "docs/inventario_pro_offline.html"
)
if (Test-Path $gi) {
  $cur = Get-Content $gi -Raw
  $append = $lines | Where-Object { $cur -notmatch [regex]::Escape($_) }
  if ($append) { Add-Content $gi ($append -join [Environment]::NewLine) }
} else {
  Set-Content $gi ($lines -join [Environment]::NewLine)
}
git add .gitignore | Out-Null

# 1) Add + Commit (si hay cambios)
git add -A
$hasStaged = (git diff --cached --name-only) -ne $null
if ($hasStaged) {
  git commit -m "update" | Out-Null
  Say "✔ commit creado" "Green"
} else {
  Say "↪ no había cambios para commit" "DarkGray"
}

# 2) Escanea LO STAGEADO por tamaño
$staged = git diff --cached --name-only | Where-Object { $_ -and (Test-Path $_) }
if ($staged) {
  $warns = @()
  $blocks = @()
  foreach ($f in $staged) {
    try {
      $size = (Get-Item -LiteralPath $f).Length
      $mb = [math]::Round($size/1MB,1)
      # ¿Está bajo LFS?
      $attr = git check-attr -a -- "$f" 2>$null
      $isLfs = ($attr -match 'filter:\s*lfs') -or ($attr -match 'diff:\s*lfs') -or ($attr -match 'merge:\s*lfs')

      if ($size -ge ($BlockMB*1MB) -and -not $isLfs) {
        $blocks += "{0}  ({1} MB)  **NO LFS**" -f $f,$mb
      } elseif ($size -ge ($WarnMB*1MB) -and -not $isLfs) {
        $warns  += "{0}  ({1} MB)  (sin LFS)" -f $f,$mb
      }
    } catch {}
  }

  if ($warns.Count) {
    Say "Aviso (>=${WarnMB}MB sin LFS):" "Yellow"
    $warns | ForEach-Object { Say "  - $_" "Yellow" }
  }
  if ($blocks.Count) {
    Say "Bloqueado: archivos >= ${BlockMB}MB sin LFS:" "Red"
    $blocks | ForEach-Object { Say "  - $_" "Red" }
    throw "Aborto push: agrega esos patrones a LFS o ignóralos."
  }
}

# 3) Rebase y push
git pull --rebase $Remote $Branch
git push -u $Remote $Branch
Say "✔ push hecho" "Green"