# ============================
# make_inventory_offline.ps1
# Genera inventario interactivo (offline, sin CDN)
# ============================

$ErrorActionPreference = 'Stop'

# --- Config
$Drives  = 'H','I','J'
$Base    = (Get-Location).Path
$OutHtml = Join-Path $Base 'inventario_interactivo_offline.html'
$fecha   = Get-Date -Format 'yyyy-MM-dd HH:mm'

# --- Exclusiones (sistema + cualquier "quarantine")
$ExcludeRx = '\\(System Volume Information|\$Recycle\.Bin|FOUND\.\d{3}|_quarantine(_from_[A-Z]+|_from_HIJ)?|_quarantine)($|\\)'

# --- HtmlEncode (por si hiciera falta)
try { Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue } catch {}
function HtmlEnc([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  return [System.Web.HttpUtility]::HtmlEncode($s)
}

# --- Recolección de archivos
$index = foreach ($d in $Drives) {
  $root = "$($d):\"
  if (Test-Path $root) {
    Get-ChildItem $root -Recurse -Force -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch $ExcludeRx } |
      ForEach-Object {
        [pscustomobject]@{
          Drive     = $d
          Folder    = $_.DirectoryName
          Name      = $_.Name
          Extension = ($_.Extension -replace '^$','(sin)')
          Size      = [int64]$_.Length
          MB        = [math]::Round($_.Length/1MB, 2)
          LastWrite = $_.LastWriteTime
          FullPath  = $_.FullName
        }
      }
  }
}

# --- Resumen por disco
$resumen = $index | Group-Object Drive | ForEach-Object {
  [pscustomobject]@{
    Drive = $_.Name
    Count = $_.Count
    GB    = [math]::Round( ($_.Group | Measure-Object Size -Sum).Sum / 1GB, 2 )
  }
} | Sort-Object Drive

# --- HTML (sin caracteres especiales y sin dependencias externas)
$head = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Inventario Offline H/I/J</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  :root{ --fg:#1f2937; --muted:#6b7280; --line:#e5e7eb; --bg:#fff; --chip:#f3f4f6; }
  body{ font-family: Segoe UI, Arial, sans-serif; color:var(--fg); background:var(--bg); margin:20px; }
  h1,h2{ margin:0 0 8px 0; }
  .muted{ color:var(--muted); font-size:12px; margin:6px 0 16px; }
  .chips{ display:flex; flex-wrap:wrap; gap:8px; margin:10px 0 16px; }
  .pill{ background:var(--chip); border:1px solid var(--line); border-radius:999px; padding:4px 10px; }
  .nowrap{ white-space:nowrap; }
  table{ width:100%; border-collapse:collapse; font-size:13px; }
  th,td{ border:1px solid var(--line); padding:6px 8px; vertical-align:top; }
  th{ background:#f9fafb; cursor:pointer; user-select:none; }
  code{ font-family: Consolas, Monaco, monospace; background:#f9fafb; padding:1px 3px; border-radius:4px; }
  .right{ text-align:right; }
  .path{ max-width: 520px; }
  .sticky{ position:sticky; top:0; background:#f9fafb; z-index:1; }
  .controls{ display:flex; gap:8px; align-items:center; margin:12px 0; }
  input[type="text"]{ width:340px; padding:6px 8px; border:1px solid var(--line); border-radius:6px; }
  .btn{ padding:6px 10px; border:1px solid var(--line); background:#fff; border-radius:6px; cursor:pointer; }
  .btn:hover{ background:#f3f4f6; }
  .small{ font-size:12px; }
</style>
</head>
<body>
"@

$intro = @"
<h1>Inventario H / I / J (offline)</h1>
<div class="muted">
Generado: $fecha. Sin dependencias externas (funciona con o sin Internet).<br>
Nota: el enlace a archivo real solo abre en local (file://), no desde GitHub Pages.
</div>
"@

# chips de resumen (Count y GB por drive + total)
$totalCount = ($resumen | Measure-Object Count -Sum).Sum
$totalGB    = ($resumen | Measure-Object GB -Sum).Sum
$chips = '<div class="chips">' +
  ($resumen | ForEach-Object {
    '<span class="pill nowrap"><b>'+ $_.Drive + ':</b> ' +
    ([string]::Format('{0:n0}', $_.Count)) + ' archivos - ' +
    ([string]::Format('{0:n2}', $_.GB)) + ' GB</span>'
  } | Out-String).Trim() +
  ' <span class="pill nowrap"><b>TOTAL:</b> ' +
  ([string]::Format('{0:n0}', $totalCount)) + ' archivos - ' +
  ([string]::Format('{0:n2}', $totalGB)) + ' GB</span></div>'

# Controles
$controls = @"
<div class="controls">
  <input id="q" type="text" placeholder="Filtrar por nombre o carpeta...">
  <button id="clr" class="btn">Limpiar</button>
  <span id="count" class="small muted"></span>
</div>
"@

# cabecera tabla
$tableHead = @"
<table id="tbl">
  <thead>
    <tr>
      <th class="sticky">Drive</th>
      <th class="sticky">Folder</th>
      <th class="sticky">Name</th>
      <th class="sticky">Ext</th>
      <th class="sticky right">MB</th>
      <th class="sticky">LastWrite</th>
      <th class="sticky path">Path</th>
    </tr>
  </thead>
  <tbody>
"@

# filas (usamos StringBuilder para rendimiento)
$sbRows = New-Object System.Text.StringBuilder
foreach ($row in $index) {
  $drive  = HtmlEnc($row.Drive)
  $folder = HtmlEnc($row.Folder)
  $name   = HtmlEnc($row.Name)
  $ext    = HtmlEnc($row.Extension)
  $mb     = [string]::Format('{0:n2}', $row.MB)
  # ISO para poder ordenar por texto sin librerías
  $dtISO  = Get-Date $row.LastWrite -Format 'yyyy-MM-dd HH:mm:ss'
  $path   = HtmlEnc($row.FullPath)
  $href   = 'file:///' + ($row.FullPath -replace '\\','/')

  $null = $sbRows.AppendLine( ('<tr>'+
    '<td>'+ $drive +'</td>'+
    '<td>'+ $folder +'</td>'+
    '<td>'+ $name +'</td>'+
    '<td>'+ $ext +'</td>'+
    '<td class="right">'+ $mb +'</td>'+
    '<td>'+ $dtISO +'</td>'+
    '<td class="path"><code>'+ $path +'</code> &nbsp; <a href="'+ $href +'" target="_blank" rel="noopener">Abrir</a></td>'+
  '</tr>') )
}

# cierre tabla y JS
$tableTail = @"
  </tbody>
</table>
<script>
// Ordenacion simple por columna (texto con numeric: true)
(function(){
  const tbody = document.querySelector('#tbl tbody');
  const heads = document.querySelectorAll('#tbl thead th');
  heads.forEach((th, idx) => {
    th.addEventListener('click', () => {
      const asc = !(th.dataset.asc === 'true');
      heads.forEach(h=>{ if(h!==th) h.removeAttribute('data-asc'); });
      th.dataset.asc = asc ? 'true' : 'false';
      const rows = Array.from(tbody.rows);
      rows.sort((a,b)=>{
        const A = a.cells[idx].innerText.trim();
        const B = b.cells[idx].innerText.trim();
        return A.localeCompare(B, undefined, {numeric:true}) * (asc?1:-1);
      });
      rows.forEach(r => tbody.appendChild(r));
    });
  });

  // Filtro simple por nombre o carpeta
  const q = document.getElementById('q');
  const clr = document.getElementById('clr');
  const count = document.getElementById('count');
  const allRows = Array.from(tbody.rows);
  function apply(){
    const val = (q.value||'').toLowerCase();
    let visible = 0;
    allRows.forEach(r=>{
      const folder = r.cells[1].innerText.toLowerCase();
      const name   = r.cells[2].innerText.toLowerCase();
      const ok = (!val) || folder.includes(val) || name.includes(val);
      r.style.display = ok ? '' : 'none';
      if(ok) visible++;
    });
    count.textContent = visible + ' / ' + allRows.length + ' filas';
  }
  q.addEventListener('input', apply);
  clr.addEventListener('click', ()=>{ q.value=''; apply(); });
  apply();
})();
</script>
"@

$end = @"
</body>
</html>
"@

# --- Escribir archivo
$fullHtml = $head + $intro + $chips + $controls + $tableHead + $sbRows.ToString() + $tableTail + $end
$fullHtml | Set-Content -Path $OutHtml -Encoding UTF8

Write-Host "Inventario generado en: $OutHtml"
