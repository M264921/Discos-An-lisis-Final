# tools\fix-and-push-large-files.ps1
[CmdletBinding()]
param(
  [ValidateSet('lfs','zip')]
  [string]$Mode = 'lfs',
  [int]$ThresholdMB = 90
)

$ErrorActionPreference = 'Stop'

function Format-GitArgs {
  param([string[]]$Args)
  return ($Args | ForEach-Object {
    if ($_ -match '\s') {
      '"' + ($_ -replace '"','\"') + '"'
    } else {
      $_
    }
  }) -join ' '
}

function Run-Git {
  param([string[]]$CmdArgs)
  $output = & git @CmdArgs 2>&1
  $exit = $LASTEXITCODE
  if ($output) {
    $output | ForEach-Object { Write-Host $_ }
  }
  if ($exit -ne 0) {
    throw ("git " + (Format-GitArgs $CmdArgs) + " fallo (Exit " + $exit + ")")
  }
  return $output
}

# --- Base del repo (directorio actual) ---
$repo = (Resolve-Path '.').Path
$gitRoot = Join-Path $repo '.git'

# --- Escanea ficheros grandes ---
$limit = $ThresholdMB * 1MB
$big = Get-ChildItem -Recurse -File -Force |
  Where-Object {
    $_.Length -ge $limit -and
    $_.FullName -notlike '*.bak_*' -and
    -not $_.FullName.StartsWith($gitRoot)
  } |
  Sort-Object Length -Descending

if (-not $big) {
  Write-Host ("OK No hay ficheros >= " + $ThresholdMB + " MB") -ForegroundColor Green
  exit 0
}

Write-Host ("Archivos grandes detectados (>= " + $ThresholdMB + " MB):") -ForegroundColor Cyan
foreach ($f in $big) {
  $sizeMB = [math]::Round($f.Length / 1MB, 1)
  Write-Host ("  " + $sizeMB + " MB  " + $f.FullName)
}

if ($Mode -eq 'lfs') {
  Write-Host "Preparando Git LFS..." -ForegroundColor Cyan
  Run-Git @('--version') | Out-Null
  & git lfs version | Out-Null
  Run-Git @('lfs','install')

  # Helper para ruta relativa
  function Get-Rel {
    param([string]$full)
    try {
      return [System.IO.Path]::GetRelativePath($repo, $full)
    } catch {
      if ($full.StartsWith($repo)) {
        return $full.Substring($repo.Length).TrimStart('\','/')
      } else {
        return $full
      }
    }
  }

  foreach ($f in $big) {
    $rel = Get-Rel $f.FullName
    Run-Git @('lfs','track',$rel)
  }

  $attrs = Join-Path $repo '.gitattributes'
  if (Test-Path $attrs) {
    $existing = Get-Content -LiteralPath $attrs
    $seen = @{}
    $dedup = foreach ($line in $existing) {
      if (-not $seen.ContainsKey($line)) {
        $seen[$line] = $true
        $line
      }
    }
    if ($dedup.Count -ne $existing.Count) {
      Set-Content -LiteralPath $attrs -Value $dedup -Encoding UTF8
    }
  }

  Run-Git @('add','.gitattributes')

  foreach ($f in $big) {
    $rel = Get-Rel $f.FullName
    $ignored = $false
    try {
      & git check-ignore -q -- "$rel"
      if ($LASTEXITCODE -eq 0) { $ignored = $true }
    } catch {}

    if ($ignored) {
      Run-Git @('add','-f','--',$rel)
    } else {
      Run-Git @('add','--',$rel)
    }
  }

  try { Run-Git @('commit','-m','Track large files with Git LFS') } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
  try { Run-Git @('pull','--rebase','origin','main') } catch { Write-Host ("Aviso: " + $_.Exception.Message) -ForegroundColor Yellow }
  Run-Git @('push','-u','origin','main')

  Write-Host "[OK] Push con LFS completado." -ForegroundColor Green
  exit 0
}

# Modo 'zip' (opcional, por si algun dia lo usas)
if ($Mode -eq 'zip') {
  $zip = Join-Path $repo ('large-files_' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path $zip) { Remove-Item $zip -Force }
  [System.IO.Compression.ZipFile]::CreateFromDirectory($repo, $zip)
  Write-Host ("[OK] ZIP creado: " + $zip) -ForegroundColor Green
  exit 0
}

throw ("Modo no soportado: " + $Mode)
