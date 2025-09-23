# ====================== INFORME INVENTARIO BUENO (H/I/J) =======================
# Solo indexa archivos "buenos" (excluye quarantine, sistema, FOUND.###)
# Salidas:
#   - HTML: C:\Users\anton\media-dedup\04_logs\_snapshots\inventario_bueno.html
#   - CSV : C:\Users\anton\media-dedup\04_logs\_snapshots\inventario_bueno.csv
# ------------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

# Ajustes fijos (no cambiar)
$Drives  = @('H','I','J')
$Base    = 'C:\Users\anton\media-dedup'
$OutDir  = Join-Path $Base '04_logs\_snapshots'
$OutHtml = Join-Path $OutDir 'inventario_bueno.html'
$OutCsv  = Join-Path $OutDir 'inventario_bueno.csv'

# Exclusiones: sistema + cualquier variante de quarantine
$ExcludeRx = '\\(System Volume Information|\$Recycle\.Bin|FOUND\.\d{3}|_quarantine(_from_[A-Z]+|_from_HIJ)?|_quarantine)($|\\)'

# Prep carpeta de salida
$null = New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Helpers
function HtmlEscape([string]$s) {
  if ($null -eq $s) { return '' }
  return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function Format-Bytes([long]$b) {
  if($b -ge 1TB){ '{0:n2} TB' -f ($b/1TB) }
  elseif($b -ge 1GB){ '{0:n2} GB' -f ($b/1GB) }
  elseif($b -ge 1MB){ '{0:n2} MB' -f ($b/1MB) }
  else{ '{0:n0} B' -f $b }
}

# Recolecta archivos BUENOS por disco
$inventory = @()
$summary   = @()
$topByDrive = @{}
$quarAudit = @()

foreach($d in $Drives){
  $root = "$($d):\"
  if(-not (Test-Path $root)){ continue }

  Write-Host " > $($d): escaneando archivos buenos..."
  $files = Get-ChildItem $root -Recurse -Force -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch $ExcludeRx }

  # Inventario (normalizado para CSV y HTML)
  $block = $files | ForEach-Object {
    [pscustomobject]@{
      Drive     = $d
      Folder    = $_.DirectoryName
      Name      = $_.Name
      Extension = ($_.Extension.ToLower() -replace '^$','(sin)')
      Length    = [int64]$_.Length
      MB        = [math]::Round($_.Length/1MB,2)
      LastWrite = $_.LastWriteTime
      FullPath  = $_.FullName
    }
  }
  $inventory += $block

  # Resumen por disco
  $sumBytes = ($block | Measure-Object Length -Sum).Sum
  $summary += [pscustomobject]@{
    Drive    = $d
    Archivos = $block.Count
    Bytes    = [int64]$sumBytes
    GB       = [math]::Round($sumBytes/1GB,2)
  }

  # Top 15 carpetas por tamaño (buenas)
  $byFolder = $block | Group-Object Folder | ForEach-Object {
    [pscustomobject]@{
      Folder  = $_.Name
      Archivos= $_.Count
      Bytes   = [int64](($_.Group | Measure-Object Length -Sum).Sum)
      GB      = [math]::Round( (($_.Group | Measure-Object Length -Sum).Sum/1GB), 2)
    }
  } | Sort-Object Bytes -Descending | Select-Object -First 15
  $topByDrive[$d] = $byFolder

  # Auditoría de quarantine (solo info, no entra en inventario)
  $qDirs = Get-ChildItem $root -Recurse -Force -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '\\_quarantine(_from_[A-Z]+|_from_HIJ)?($|\\)' }
  foreach($q in $qDirs){
    $qFiles = Get-ChildItem $q.FullName -Recurse -Force -File -ErrorAction SilentlyContinue
    $qBytes = ($qFiles | Measure-Object Length -Sum).Sum
    $quarAudit += [pscustomobject]@{
      Drive   = $d
      Dir     = $q.FullName
      Archivos= $qFiles.Count
      Bytes   = [int64]$qBytes
      GB      = [math]::Round($qBytes/1GB,2)
      Updated = $q.LastWriteTime
    }
  }
}

# ----- Export CSV (inventario bueno)
'Drive,Folder,Name,Extension,Length,MB,LastWrite,FullPath' | Out-File -LiteralPath $OutCsv -Encoding UTF8
$inventory | Sort-Object Drive,Folder,Name | ForEach-Object {
  $line = '{0},"{1}","{2}",{3},{4},{5},"{6}","{7}"' -f `
    $_.Drive,
    ($_.Folder -replace '"','""'),
    ($_.Name -replace '"','""'),
    $_.Extension,
    $_.Length,
    $_.MB,
    ($_.LastWrite.ToString('yyyy-MM-dd HH:mm:ss')),
    ($_.FullPath -replace '"','""')
  Add-Content -LiteralPath $OutCsv -Value $line -Encoding UTF8
}

# ----- Construcción del HTML (plegable)
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("<!doctype html><meta charset='utf-8'><title>Inventario BUENO (H/I/J)</title>")
$null = $sb.AppendLine(@"
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#202124}
h1{margin:0 0 4px 0}
.muted{color:#5f6368;margin:6px 0 18px}
table{border-collapse:collapse;width:100%;margin:8px 0}
th,td{border:1px solid #e5e7eb;padding:6px 8px;text-align:left;font-size:13px}
th{background:#f6f8fa}
details{border:1px solid #e5e7eb;border-radius:10px;padding:10px 12px;margin:10px 0;background:#fafbfc}
summary{font-weight:700;cursor:pointer}
.small{font-size:12px;color:#5f6368}
code{background:#f1f3f4;border:1px solid #e0e0e0;border-radius:6px;padding:1px 4px}
.btns{margin:6px 0 12px}
button{padding:6px 10px;border:1px solid #d0d7de;border-radius:8px;background:#fff;cursor:pointer}
button+button{margin-left:8px}
ul{margin:6px 0 0 18px}
.file{font-family:Consolas,monospace;white-space:pre-wrap}
</style>
<script>
function toggleAll(open){
  document.querySelectorAll('details').forEach(d=>d.open=open);
}
</script>
"@)

$fecha = Get-Date -Format 'dd/MM/yyyy HH:mm'
$null = $sb.AppendLine("<h1>Inventario por carpeta — SOLO BUENOS</h1>")
$null = $sb.AppendLine("<div class='muted'>Generado: $fecha. Se excluyen <code>_quarantine*</code>, <code>System Volume Information</code>, <code>$Recycle.Bin</code> y <code>FOUND.###</code>.</div>")
$null = $sb.AppendLine("<div class='btns'><button onclick='toggleAll(true)'>Abrir todo</button><button onclick='toggleAll(false)'>Cerrar todo</button></div>")

# Resumen por disco
$null = $sb.AppendLine("<h2>Resumen por disco</h2>")
$null = $sb.AppendLine("<table><tr><th>Disco</th><th>Archivos buenos</th><th>Datos buenos</th></tr>")
foreach($row in ($summary | Sort-Object Drive)){
  $null = $sb.AppendLine("<tr><td>$($row.Drive:HtmlEscape())</td><td>$([string]::Format('{0:n0}',$row.Archivos))</td><td>$(Format-Bytes $row.Bytes)</td></tr>")
}
$null = $sb.AppendLine("</table>")

# Top carpetas por disco
foreach($d in ($summary | Sort-Object Drive | Select-Object -ExpandProperty Drive)){
  $null = $sb.AppendLine("<details open><summary>Top carpetas por tamaño — $d:</summary>")
  $null = $sb.AppendLine("<table><tr><th>Carpeta</th><th>Archivos</th><th>Tamaño</th></tr>")
  foreach($f in $topByDrive[$d]){
    $null = $sb.AppendLine("<tr><td><code>"+(HtmlEscape $f.Folder)+"</code></td><td>$([string]::Format('{0:n0}',$f.Archivos))</td><td>$(Format-Bytes $f.Bytes)</td></tr>")
  }
  $null = $sb.AppendLine("</table></details>")
}

# Árbol por disco → carpeta → archivos
foreach($d in ($summary | Sort-Object Drive | Select-Object -ExpandProperty Drive)){
  $null = $sb.AppendLine("<details><summary>Árbol completo — $d:</summary>")
  $block = $inventory | Where-Object { $_.Drive -eq $d }
  $folders = $block | Group-Object Folder | Sort-Object Name
  foreach($g in $folders){
    $bytes = ($g.Group | Measure-Object Length -Sum).Sum
    $null = $sb.AppendLine("<details><summary><code>"+(HtmlEscape $g.Name)+"</code> — $([string]::Format('{0:n0}',$g.Count)) archivos, $(Format-Bytes $bytes)</summary>")
    $null = $sb.AppendLine("<table><tr><th>Fecha</th><th>Tamaño</th><th>Nombre</th><th>Ruta</th></tr>")
    foreach($it in ($g.Group | Sort-Object LastWrite -Descending)){
      $null = $sb.AppendLine("<tr><td>$($it.LastWrite.ToString('yyyy-MM-dd HH:mm'))</td><td>$(Format-Bytes $it.Length)</td><td>"+(HtmlEscape $it.Name)+"</td><td class='file'>"+(HtmlEscape $it.FullPath)+"</td></tr>")
    }
    $null = $sb.AppendLine("</table></details>")
  }
  $null = $sb.AppendLine("</details>")
}

# Auditoría quarantine (para dejar constancia, NO incluido en inventario)
$null = $sb.AppendLine("<h2>Auditoría de carpetas quarantine (excluidas del inventario)</h2>")
if($quarAudit.Count -gt 0){
  $totQ = ($quarAudit | Measure-Object Bytes -Sum).Sum
  $null = $sb.AppendLine("<div class='small'>Total archivos en quarantine: $([string]::Format('{0:n0}',($quarAudit | Measure-Object Archivos -Sum).Sum)) — $(Format-Bytes $totQ)</div>")
  $null = $sb.AppendLine("<table><tr><th>Disco</th><th>Carpeta</th><th>Archivos</th><th>Tamaño</th><th>Última escritura</th></tr>")
  foreach($qr in ($quarAudit | Sort-Object Drive, Dir)){
    $null = $sb.AppendLine("<tr><td>$($qr.Drive)</td><td class='file'>"+(HtmlEscape $qr.Dir)+"</td><td>$([string]::Format('{0:n0}',$qr.Archivos))</td><td>$(Format-Bytes $qr.Bytes)</td><td>$($qr.Updated.ToString('yyyy-MM-dd HH:mm'))</td></tr>")
  }
  $null = $sb.AppendLine("</table>")
} else {
  $null = $sb.AppendLine("<div class='small'>No se encontraron carpetas quarantine en H:, I:, J:.</div>")
}

# Guardar HTML
[IO.File]::WriteAllText($OutHtml, $sb.ToString(), [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "================= LISTO ================="
Write-Host ("Inventario BUENO (CSV): {0}" -f $OutCsv)
Write-Host ("Inventario BUENO (HTML): {0}" -f $OutHtml)
Write-Host "Ábrelo con:  start $OutHtml"
# ==============================================================================
