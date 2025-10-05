param(
  [string[]]$Drives,                             # opcional: salta el popup si lo pasas
  [string]$OutDir   = "docs\inventory",
  [string]$Merged   = "docs\hash_data.csv",
  [switch]$UseAllStored                         # fusiona TODOS los CSV ya guardados en OutDir (sin re-escanear)
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest
$PSStyle.OutputRendering = 'PlainText'

# --- 1) Descubrir unidades ---
function Get-DriveTable {
  $vols = @()
  try {
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter
  } catch { }
  if(-not $vols){
    # Fallback
    $vols = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
      [pscustomobject]@{
        DriveLetter = $_.Name
        FileSystem  = $null
        FileSystemLabel = $null
        Size        = $null
        SizeRemaining = $null
      }
    }
  }
  $vols | ForEach-Object {
    [pscustomobject]@{
      Letter   = "$($_.DriveLetter)".ToUpper()
      Label    = $_.FileSystemLabel
      FS       = $_.FileSystem
      SizeGB   = if($_.Size){ [math]::Round($_.Size/1GB,1) } else { $null }
      FreeGB   = if($_.SizeRemaining){ [math]::Round($_.SizeRemaining/1GB,1) } else { $null }
      Root     = if($_.DriveLetter){ "$($_.DriveLetter):\" } else { "$($_.Name):\" }
    }
  } | Sort-Object Letter
}

# --- 2) UI selección (o parámetro) ---
$pick = @()
if($UseAllStored){
  # no seleccionamos, fusionamos lo guardado
} elseif($Drives -and $Drives.Count){
  $pick = ($Drives | ForEach-Object { $_.Substring(0,1).ToUpper() }) | Select-Object -Unique
} else {
  $table = Get-DriveTable
  if(Get-Command Out-GridView -ErrorAction SilentlyContinue){
    $sel = $table | Out-GridView -PassThru -Title "Selecciona unidades a escanear (Ctrl+Click múltiple)"
    if($sel){ $pick = $sel.Letter } else { Write-Warning "No se seleccionó nada."; return }
  } else {
    Write-Host "Unidades detectadas:" -ForegroundColor Cyan
    $i=0; $table | ForEach-Object { $script:i++; Write-Host ("[{0}] {1}: {2}  {3}GB ({4}GB libres)" -f $i,$_.Letter,$_.Label,$_.SizeGB,$_.FreeGB) }
    $ans = Read-Host "Escribe índices separados por coma (ej: 1,3)"
    $idx = $ans -split '\s*,\s*' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    $pick = $idx | ForEach-Object { $table[$_-1].Letter } | Where-Object { $_ } | Select-Object -Unique
    if(-not $pick){ Write-Warning "No se seleccionó nada."; return }
  }
}

# --- 3) Extensiones multimedia ---
$media = @(
  '.mp4','.mkv','.avi','.mov','.wmv','.flv','.m4v',
  '.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.webp','.heic',
  '.mp3','.wav','.flac','.aac','.ogg','.m4a',
  '.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.rtf'
)

# --- 4) Función de escaneo por unidad ---
function Scan-Drive([string]$letter,[string]$outDir){
  $root = "$letter`:\"
  if(-not (Test-Path $root)){ Write-Warning "Unidad $letter: no existe, salto."; return $null }
  Write-Host ">>> Escaneando $root ..." -ForegroundColor Green
  $rows = Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $media -contains $_.Extension.ToLowerInvariant() } |
    ForEach-Object {
      $hash=$null; $err=$null
      try   { $hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
      catch { $err=$_.Exception.Message }
      [pscustomobject]@{
        FullName  = $_.FullName
        Hash      = $hash
        Length    = $_.Length
        Extension = $_.Extension
        Error     = $err
      }
    }
  if(-not (Test-Path $outDir)){ New-Item -ItemType Directory -Path $outDir | Out-Null }
  $outCsv = Join-Path $outDir ("scan_{0}.csv" -f $letter)
  $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $outCsv
  Write-Host ("OK {0}: {1} ficheros -> {2}" -f $letter,$rows.Count,$outCsv)
  return $outCsv
}

# --- 5) Escanear o cargar guardados ---
$perDriveCsv = New-Object System.Collections.Generic.List[string]
if($UseAllStored){
  if(Test-Path $OutDir){
    Get-ChildItem -LiteralPath $OutDir -Filter 'scan_*.csv' | ForEach-Object { $perDriveCsv.Add($_.FullName) }
    if(-not $perDriveCsv.Count){ Write-Warning "No hay scans guardados en $OutDir"; return }
  } else {
    Write-Warning "No existe $OutDir"; return
  }
} else {
  foreach($d in $pick){ $p = Scan-Drive -letter $d -outDir $OutDir; if($p){ $perDriveCsv.Add($p) } }
  if(-not $perDriveCsv.Count){ Write-Warning "Nada que fusionar."; return }
}

# --- 6) Fusionar a docs\hash_data.csv ---
$all = foreach($csv in $perDriveCsv){ Import-Csv -LiteralPath $csv }
$all | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath $Merged
Write-Host ("Fusionado -> {0} filas en {1}" -f ($all.Count), $Merged) -ForegroundColor Yellow

# --- 7) Meta JSON por unidad y global ---
$meta = [ordered]@{
  generatedAt = (Get-Date).ToString('s')
  drives = @{}
  total  = $all.Count
}
$all | Group-Object { ($_.'FullName' -split '^[A-Za-z]:')[0]; (($_.FullName)[0]) } | Out-Null # no se usa, pero dejamos nota

$byDrive = $all | ForEach-Object {
  # intenta letra desde FullName
  if($_.FullName -match '^([A-Za-z]):'){ $Matches[1].ToUpper() } else { 'OTROS' }
} | Group-Object

foreach($g in $byDrive){
  $meta.drives[$g.Name] = @{ count = $g.Count }
}

$metaPath = Join-Path $OutDir 'meta.json'
($meta | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 -LiteralPath $metaPath
Write-Host ("Meta -> {0}" -f $metaPath)

# --- 8) Reinyectar a la página ---
$html = "docs\inventario_interactivo_offline.html"
if(Test-Path $html){
  pwsh -NoProfile -ExecutionPolicy Bypass `
    -File .\tools\inventory-inject-from-csv.ps1 `
    -CsvPath $Merged -HtmlPath $html
}
Write-Host "Listo. Abriendo página..."
Start-Process $html
