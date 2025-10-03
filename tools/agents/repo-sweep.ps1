Param(
  [string]$RepoRoot = "$PSScriptRoot/../..",
  [ValidateSet("DryRun","Apply")] [string]$Mode = "DryRun",
  [string[]]$Patterns = @('Thumbs.db','.DS_Store','desktop.ini','*.tmp','*.bak','*.old','*.crdownload','*.part','~$*'),
  [string[]]$ExcludeDirs = @('\.git\','\logs\','\docs\'),
  [string]$DryRunBase = "Dry run",
  [string]$HashAlgo = "SHA256",
  [string]$FromCsv = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path $RepoRoot).Path
Set-Location $RepoRoot

# Helpers
function New-Log {
  param([string]$name)
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $path = Join-Path "logs" ("$name-$ts.log")
  New-Item -ItemType Directory -Force -Path "logs" | Out-Null
  $script:LOG = $path
  $path
}
function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "u"), $msg
  $line | Tee-Object -FilePath $script:LOG -Append
}
function Get-KnownHashes {
  # Busca CSVs con columna "hash" (insensible) en la raíz y subcarpetas típicas
  $candidates = Get-ChildItem -Recurse -File -Filter *.csv -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\logs\\' -and $_.FullName -notmatch '\\Dry run\\' }
  $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($csv in $candidates) {
    try {
      $first = (Get-Content -TotalCount 1 -Path $csv.FullName)
      if (-not $first) { continue }
      $hdr = $first -split ',' | ForEach-Object { $_.Trim('" ') }
      $col = $hdr | Where-Object { $_ -match '^(hash|sha256)$' -or $_ -match '(?i)hash' }
      if (-not $col) { continue }
      $data = Import-Csv -Path $csv.FullName
      foreach ($row in $data) {
        foreach ($key in $row.PSObject.Properties.Name) {
          if ($key -match '(?i)hash|sha256') {
            $val = [string]$row.$key
            if ($val) { $null = $set.Add(($val.Trim())) }
          }
        }
      }
    } catch { }
  }
  return ,$set
}
function Get-RelPath([string]$abs) {
  $uri1 = New-Object System.Uri($RepoRoot + [IO.Path]::DirectorySeparatorChar)
  $uri2 = New-Object System.Uri($abs)
  return [System.Uri]::UnescapeDataString($uri1.MakeRelativeUri($uri2).ToString().Replace('/','\'))
}

$logPath = New-Log "repo-sweep-$Mode"
Log "== repo-sweep $Mode START =="
Log "RepoRoot: $RepoRoot"

if ($Mode -eq "DryRun") {
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $dryDir = Join-Path $RepoRoot (Join-Path $DryRunBase $ts)
  New-Item -ItemType Directory -Force -Path $dryDir | Out-Null

  # 1) Encontrar candidatos
  $cands = Get-ChildItem -Recurse -File -Include $Patterns -ErrorAction SilentlyContinue
  $cands = $cands | Where-Object {
    $p = $_.FullName
    foreach ($ex in $ExcludeDirs) { if ($p -match $ex) { return $false } }
    return $true
  }
  Log ("Candidatos: {0}" -f ($cands.Count))

  # 2) MOVER (no copiar) a Dry run/<ts>/ manteniendo estructura
  $rows = @()
  foreach ($f in $cands) {
    $rel = Get-RelPath $f.FullName
    $target = Join-Path $dryDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    try {
      Move-Item -LiteralPath $f.FullName -Destination $target -Force
    } catch {
      # Si hay colisión, añade sufijo
      $base = [IO.Path]::GetFileNameWithoutExtension($target)
      $ext  = [IO.Path]::GetExtension($target)
      $dir  = [IO.Path]::GetDirectoryName($target)
      $target = Join-Path $dir ("{0}__{1}{2}" -f $base, (Get-Random), $ext)
      Move-Item -LiteralPath $f.FullName -Destination $target -Force
    }
    # 3) Hash del MOVIDO
    $h = Get-FileHash -Algorithm $HashAlgo -LiteralPath $target | Select-Object -ExpandProperty Hash
    $rows += [pscustomobject]@{
      OriginalPath = $rel
      DryRunPath   = (Get-RelPath $target)
      SizeBytes    = $([int64](Get-Item -LiteralPath $target).Length)
      HashAlgo     = $HashAlgo
      Hash         = $h
      KnownBefore  = $false
      SafeToDelete = $false
    }
  }

  # 4) Cargar hashes históricos y decidir "SafeToDelete"
  $known = Get-KnownHashes
  foreach ($r in $rows) {
    if ($known.Contains($r.Hash)) {
      $r.KnownBefore = $true
      # Regla conservadora: si ya estaba hasheado antes y es patrón de basura, se puede borrar
      $r.SafeToDelete = $true
    }
  }

  # 5) Exportar CSV inventario del Dry-run
  $csvPath = Join-Path "logs" ("repo-sweep-dryrun-{0}.csv" -f $ts)
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath

  Log "Dry-run dir: $((Get-RelPath $dryDir))"
  Log "Inventario:  $csvPath"
  $sum = ($rows | Measure-Object SizeBytes -Sum)
  Log ("Moved files: {0}  |  Total MB: {1:N2}" -f $rows.Count, ($sum.Sum/1MB))
  $safe = ($rows | Where-Object {$_.SafeToDelete}).Count
  Log ("Marcados SafeToDelete: {0}" -f $safe)
  Log "== repo-sweep DryRun DONE =="
  exit 0
}

if ($Mode -eq "Apply") {
  # Lee CSV (si no se pasa -FromCsv, toma el último repo-sweep-dryrun-*.csv)
  if (-not $FromCsv) {
    $last = Get-ChildItem -Path "logs" -Filter "repo-sweep-dryrun-*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $last) { throw "No se encontró CSV de dry-run previo. Pasa -FromCsv." }
    $FromCsv = $last.FullName
  }
  Log ("Apply desde: {0}" -f $FromCsv)

  $rows = Import-Csv -Path $FromCsv
  $delCount = 0
  foreach ($r in $rows) {
    if ($r.SafeToDelete -eq "True") {
      $abs = Join-Path $RepoRoot $r.DryRunPath
      if (Test-Path -LiteralPath $abs) {
        Remove-Item -LiteralPath $abs -Force -ErrorAction SilentlyContinue
        $delCount++
        Log ("BORRADO: {0}" -f $r.DryRunPath)
      } else {
        Log ("SKIP no existe: {0}" -f $r.DryRunPath)
      }
    }
  }
  Log ("Total borrados: {0}" -f $delCount)
  Log "== repo-sweep Apply DONE =="
}
