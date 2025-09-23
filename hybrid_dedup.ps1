# ========================= HYBRID DEDUP (H/I/J) =========================
# 1) Inventario por carpetas (sin hash), ordenado por fecha
# 2) Precandidatos por (tamaño + nombre) para reducir hashing
# 3) Duplicados confirmados por HASH (SHA256)
# Salidas: C:\Users\anton\media-dedup\04_logs\_snapshots
# =======================================================================

$ErrorActionPreference = 'Stop'

# --- Ajustes fijos
$Drives  = @('H','I','J')
$Base    = 'C:\Users\anton\media-dedup'
$SnapDir = Join-Path $Base '04_logs\_snapshots'

$CsvInv  = Join-Path $SnapDir 'inventory_by_folder.csv'
$CsvPre  = Join-Path $SnapDir 'prededup_size_name.csv'
$CsvDup  = Join-Path $SnapDir 'dupes_confirmed.csv'
$TxtIdx  = Join-Path $SnapDir 'inventory_folder_index.txt'

$Algorithm = 'SHA256'
$ExcludeRx = '\\(System Volume Information|\$Recycle\.Bin|_quarantine_from_HIJ|_quarantine\\|FOUND\.\d{3})($|\\)'

# --- Prep carpeta
$null = New-Item -ItemType Directory -Force -Path $SnapDir | Out-Null

# --- Helpers CSV (cabecera una vez)
function Init-Csv([string]$Path,[string[]]$Header){
  if (Test-Path $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
  ($Header -join ',') | Out-File -LiteralPath $Path -Encoding UTF8
}
function Append-CsvRow([string]$Path,[object]$Obj,[string[]]$Header){
  $line = ($Obj | Select-Object $Header | ConvertTo-Csv -NoTypeInformation)[1]
  Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

# --- Rutas largas locales \\?\
function Add-LongPrefix([string]$p){
  if ($p -match '^[A-Za-z]:' -and -not ($p.StartsWith('\\?\'))) { return '\\?\'+$p }
  return $p
}

# --- Hash robusto
function Get-HashSafe([string]$Path,[string]$Algorithm='SHA256'){
  try {
    return (Get-FileHash -Algorithm $Algorithm -LiteralPath $Path -ErrorAction Stop).Hash
  } catch {
    try{
      $lp = Add-LongPrefix $Path
      $ha = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
      $fs = [System.IO.File]::Open($lp,'Open','Read','ReadWrite')
      try {
        $buf = New-Object byte[] (4MB)
        while (($read = $fs.Read($buf,0,$buf.Length)) -gt 0) { $null = $ha.TransformBlock($buf,0,$read,$buf,0) }
        $null = $ha.TransformFinalBlock($buf,0,0)
        (-join ($ha.Hash | ForEach-Object { $_.ToString('x2') })).ToUpperInvariant()
      } finally { $fs.Dispose() }
    } catch { return $null }
  }
}

Write-Host ""
Write-Host ("HYBRID DEDUP  Inicio {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host "  1/3 Inventario  2/3 Precandidatos  3/3 Duplicados HASH"
Write-Host ("  Carpeta: {0}" -f $SnapDir)
Write-Host ""

# ========================= 1/3 INVENTARIO ===============================
Write-Host "1/3 Inventario: escaneando H:, I:, J: (sin hash) ..."
$invHeader = @('Drive','Folder','Name','Extension','Length','MB','LastWrite','FullPath')
Init-Csv -Path $CsvInv -Header $invHeader

# Indice TXT legible por carpeta
if (Test-Path $TxtIdx) { Remove-Item -LiteralPath $TxtIdx -Force -ErrorAction SilentlyContinue }
("INDICE POR CARPETA  generado {0}`r`n" -f (Get-Date -Format 'dd/MM/yyyy HH:mm')) | Out-File -LiteralPath $TxtIdx -Encoding UTF8

$totalFiles = 0
foreach($d in $Drives){
  $root = "$($d):\"
  if(-not(Test-Path $root)){ continue }
  Write-Host (" > {0}: recolectando archivos ..." -f $d)

  $items = Get-ChildItem $root -Recurse -Force -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch $ExcludeRx }

  # Indice TXT por carpeta
  $byFolder = $items | Group-Object DirectoryName | Sort-Object Name
  foreach($g in $byFolder){
    ("### {0}" -f $g.Name) | Add-Content -LiteralPath $TxtIdx -Encoding UTF8
    $g.Group | Sort-Object LastWriteTime -Descending | ForEach-Object {
      ("{0:yyyy-MM-dd HH:mm}  {1,10:n0}  {2}" -f $_.LastWriteTime,$_.Length,$_.Name)
    } | Add-Content -LiteralPath $TxtIdx -Encoding UTF8
    "" | Add-Content -LiteralPath $TxtIdx -Encoding UTF8
  }

  # CSV streaming
  $i = 0
  foreach($f in $items){
    $obj = [pscustomobject]@{
      Drive     = $d
      Folder    = $f.DirectoryName
      Name      = $f.Name
      Extension = ($f.Extension.ToLower() -replace '^$','(sin)')
      Length    = [int64]$f.Length
      MB        = [math]::Round($f.Length/1MB,2)
      LastWrite = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
      FullPath  = $f.FullName
    }
    Append-CsvRow -Path $CsvInv -Obj $obj -Header $invHeader
    $i++; $totalFiles++
    if(($i % 1000) -eq 0){ Write-Progress -Activity ("1/3 Inventario {0}:" -f $d) -Status ("{0} archivos" -f $i) -PercentComplete 0 }
  }
  Write-Host ("   + {0:n0} archivos en {1}" -f $i, $d)
}
Write-Host ("Inventario completado: {0:n0} archivos" -f $totalFiles)
Write-Host ("CSV: {0}" -f $CsvInv)
Write-Host ("TXT: {0}" -f $TxtIdx)
Write-Host ""

# ================= 2/3 PRECANDIDATOS (tamaño+nombre) ===================
Write-Host "2/3 Precandidatos: agrupando por (tamaño + nombre) ..."
$preHeader = @('Name','Length','Count','AnyExt','AnyDate','SamplePath')
Init-Csv -Path $CsvPre -Header $preHeader

$inv = Import-Csv -LiteralPath $CsvInv
$groups = $inv | Group-Object -Property { ($_.Name).ToLowerInvariant() + '|' + [string]$_.Length }

$preCount = 0
foreach($g in $groups){
  if($g.Count -le 1){ continue }
  $sample = $g.Group | Select-Object -First 1
  $obj = [pscustomobject]@{
    Name       = $sample.Name
    Length     = [int64]$sample.Length
    Count      = $g.Count
    AnyExt     = $sample.Extension
    AnyDate    = $sample.LastWrite
    SamplePath = $sample.FullPath
  }
  Append-CsvRow -Path $CsvPre -Obj $obj -Header $preHeader
  $preCount++
  if(($preCount % 500) -eq 0){ Write-Progress -Activity "2/3 Precandidatos" -Status ("{0} grupos" -f $preCount) -PercentComplete 0 }
}
Write-Host ("Precandidatos: {0:n0} grupos (Count>1)" -f $preCount)
Write-Host ("CSV: {0}" -f $CsvPre)
Write-Host ""

# ============ 3/3 DUPLICADOS CONFIRMADOS POR HASH (SHA256) =============
Write-Host ("3/3 Duplicados HASH: confirmando por {0} solo en precandidatos ..." -f $Algorithm)
$dupHeader = @('Hash',$Algorithm,'Bytes','LastWrite','Path')
Init-Csv -Path $CsvDup -Header $dupHeader

$hashGroupsConfirmados = 0
$hashedFiles = 0

foreach($g in $groups){
  if($g.Count -le 1){ continue }

  $hashed = @()
  foreach($row in $g.Group){
    $p = $row.FullPath
    $h = Get-HashSafe -Path $p -Algorithm $Algorithm
    if(-not $h){ continue }
    $hashed += [pscustomobject]@{
      Hash      = $h
      Bytes     = [int64]$row.Length
      LastWrite = $row.LastWrite
      Path      = $p
    }
    $hashedFiles++
    if(($hashedFiles % 200) -eq 0){
      Write-Progress -Activity "3/3 Hashing" -Status ("{0} archivos hasheados" -f $hashedFiles) -PercentComplete 0
    }
  }
  if($hashed.Count -eq 0){ continue }

  $hGroups = $hashed | Group-Object Hash | Where-Object { $_.Count -gt 1 }
  foreach($hg in $hGroups){
    $hashGroupsConfirmados++
    $hg.Group | Sort-Object LastWrite | ForEach-Object {
      Append-CsvRow -Path $CsvDup -Obj $_ -Header $dupHeader
    }
  }
}

Write-Host ("HASH listo. Grupos confirmados: {0:n0} | Archivos hasheados: {1:n0}" -f $hashGroupsConfirmados,$hashedFiles)
Write-Host ("CSV: {0}" -f $CsvDup)
Write-Host ""
Write-Host ("Consejo (otra ventana): Get-Content '{0}' -Tail 20 -Wait" -f $CsvDup)
# =======================================================================
