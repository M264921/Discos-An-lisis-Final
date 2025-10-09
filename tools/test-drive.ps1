# tools\test-drive.ps1  -- version estable (PS 5/7, ASCII-only)
param(
  [string]$Path,                                  # C:\  o D:\Carpeta
  [ValidateSet('Auto','Hash','Quick')][string]$Mode = 'Auto',
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

# --- Rutas base del repo (robusto) ---
$scriptPath = $PSCommandPath
if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
$here  = [System.IO.Path]::GetDirectoryName($scriptPath)
$repo  = [System.IO.Directory]::GetParent($here).FullName

$scans  = Join-Path $repo 'docs\inventory'
$dataJs = Join-Path $repo 'docs\data\inventory.json'
$html   = Join-Path $repo 'docs\inventario_pro_offline.html'
$idxCsv = Join-Path $scans 'hash_index.csv'

if (-not $Path) { throw 'Falta -Path' }

New-Item -ItemType Directory -Force -Path (Split-Path $dataJs -Parent) | Out-Null
New-Item -ItemType Directory -Force -Path $scans | Out-Null

# --- Normaliza destino y metadatos ---
$target = (Resolve-Path -LiteralPath $Path).Path
if ($target -match '^[A-Za-z]:\\?$') { $target = $target.Substring(0,2) + '\' }  # D:\ si venia D:
$driveLetter = ([IO.Path]::GetPathRoot($target)).Substring(0,1).ToUpper()
$slug = ($target -replace '[:\\\/]+','_').Trim('_')
$scanCsv = Join-Path $scans ("scan_{0}.csv" -f $slug)

Write-Host ("-> Escaneando {0}  (modo: {1})" -f $target,$Mode)

# --- Carga indice incremental ---
$idx = @{}
if (Test-Path -LiteralPath $idxCsv) {
  foreach ($r in Import-Csv -LiteralPath $idxCsv) {
    $idx["$($r.path)|$($r.size)|$($r.mtime)"] = $r.sha
  }
}

# --- Recolecta archivos (tolerante) ---
$files = @()
try {
  $files = Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction Stop
} catch {
  $files = Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ("-> Archivos candidatos: {0}" -f $files.Count)

# --- Recorre archivos sin Split-Path (usa .NET) ---
$rows = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
  try {
    $p     = $f.FullName
    $size  = [int64]$f.Length
    $mtime = $f.LastWriteTimeUtc.ToString('s')
    $key   = "$p|$size|$mtime"

    $sha = ''
    switch ($Mode) {
      'Hash'  { try { $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $p -ErrorAction Stop).Hash } catch { $sha='' } }
      'Auto'  {
        if ($idx.ContainsKey($key)) { $sha = $idx[$key] }
        else { try { $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $p -ErrorAction Stop).Hash } catch { $sha='' } }
      }
      'Quick' { $sha = '' }
    }
    if ($sha) { $idx[$key] = $sha }

    $rows.Add([pscustomobject]@{
      sha     = $sha
      tipo    = ''
      nombre  = $f.Name
      ruta    = [System.IO.Path]::GetDirectoryName($p)   # <- sin Split-Path
      unidad  = ($driveLetter + ':')
      tamano  = $size
      fecha   = $mtime
    }) | Out-Null
  } catch {
    Write-Host "(saltado) $($_.Exception.Message)"
  }
}
Write-Host ("-> Filas construidas: {0}" -f $rows.Count)

# --- Guarda CSV del escaneo ---
$rows | Export-Csv -NoTypeInformation -LiteralPath $scanCsv -Encoding UTF8
Write-Host ("OK CSV: {0} ({1} filas)" -f $scanCsv, $rows.Count)

# --- Actualiza indice incremental ---
$idx.GetEnumerator() | ForEach-Object {
  $parts = $_.Key -split '\|', 3
  [pscustomobject]@{ path=$parts[0]; size=$parts[1]; mtime=$parts[2]; sha=$_.Value }
} | Export-Csv -NoTypeInformation -LiteralPath $idxCsv -Encoding UTF8

# --- Merge de TODOS los scan_*.csv a docs\data\inventory.json ---
$all = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath $scans -Filter 'scan_*.csv' | Sort-Object Name | ForEach-Object {
  try { (Import-Csv -LiteralPath $_.FullName) | ForEach-Object { $all.Add($_) | Out-Null } } catch {}
}

# Dedup por ruta|tamano|fecha (conserva el ultimo visto)
$seen   = New-Object 'System.Collections.Generic.HashSet[string]'
$merged = New-Object System.Collections.Generic.List[object]
foreach ($r in $all) {
  $key = '{0}|{1}|{2}' -f $r.ruta, $r.tamano, $r.fecha
  if ($seen.Add($key)) { $merged.Add($r) | Out-Null }
}

# Guarda JSON
$merged | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $dataJs -Encoding UTF8
Write-Host ("OK Merge: {0} ({1} filas)" -f $dataJs, $merged.Count)

# --- Incrusta en el HTML ---
if (-not (Test-Path -LiteralPath $html)) { throw ("No encuentro visor HTML en " + $html) }
$doc     = Get-Content -LiteralPath $html -Raw
$jsonTxt = Get-Content -LiteralPath $dataJs -Raw

$pat = '<script id="inventory-data"[^>]*>[\s\S]*?</script>'
$new = '<script id="inventory-data" type="application/json">' + $jsonTxt + '</script>'

if ($doc -match $pat) {
  $doc = [regex]::Replace($doc, $pat, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $new }, 1)
} else {
  $doc += "`r`n" + $new
}
# backup y escribe
$bak = "$html.bak_{0:yyyyMMdd-HHmmss}" -f (Get-Date)
Copy-Item -LiteralPath $html -Destination $bak -Force
Set-Content -LiteralPath $html -Value $doc -Encoding UTF8
Write-Host ("OK Backup: {0}" -f $bak)
Write-Host ("OK HTML embebido: {0}" -f $html)

if (-not $NoOpen) { Start-Process $html }
exit 0