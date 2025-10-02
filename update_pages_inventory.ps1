# ============================ INVENTARIO + GH PAGES ============================
# Recorre H:, I:, J:, genera inventario offline (1 solo HTML, sin CDN) y lo
# publica en docs\index.html. Opcionalmente hace git add/commit/push.
# Probado en Windows PowerShell y PowerShell 7.
# ==============================================================================

$ErrorActionPreference = 'Stop'

# --- AJUSTES ---------------------------------------------------------------
# Ruta del repo local (ajustada a lo que dijiste)
$RepoRoot   = 'C:\Users\Antonio\Documents\GitHub\Discos-An-lisis-Final'
$Drives     = @('H','I','J')
$DoGitPush  = $true      # pon $false si no quieres hacer push automÃ¡tico
$PageTitle  = 'Inventario H/I/J (offline)'
$OutName    = 'inventario_interactivo_offline.html'  # copia de seguridad
$DocsIndex  = 'docs\index.html'                      # destino para Pages

# Exclusiones (sÃ³lo archivos "buenos")
$ExcludeRx  = '\\(System Volume Information|\$Recycle\.Bin|FOUND\.\d{3}|_quarantine(_from_[A-Z]+|_from_HIJ)?|_quarantine)($|\\)'

# -----------------------------------------------------------------------------

# Utilidad: prefijo para rutas largas
function Add-LongPrefix([string]$p){
  if ($p -match '^[A-Za-z]:' -and -not ($p.StartsWith('\\?\'))) { return '\\?\'+$p }
  return $p
}

# Utilidad HTML: escapar
function HtmlEnc([string]$s){
  if ($null -eq $s) { return '' }
  return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

# Comprueba repo
if (-not (Test-Path $RepoRoot)) {
  Write-Error "No existe la carpeta de repo: $RepoRoot"
}

Set-Location $RepoRoot

# Prepara carpetas destino
$DocsPath = Join-Path $RepoRoot 'docs'
if (-not (Test-Path $DocsPath)) { New-Item -ItemType Directory -Force -Path $DocsPath | Out-Null }

# Escaneo (inventario "bueno")
Write-Host "Escaneando discos (archivos BUENOS, excluyendo quarantine/reciclaje/sistema) ..."
$files = @()
foreach($d in $Drives){
  $root = "$($d):\"
  if (-not (Test-Path $root)) { Write-Host " - $($d): no existe, se omite."; continue }
  Write-Host " - $($d): leyendo..."
  $items = Get-ChildItem $root -Recurse -Force -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch $ExcludeRx }

  foreach($f in $items){
    $files += [pscustomobject]@{
      Drive     = $d
      Folder    = $f.DirectoryName
      Name      = $f.Name
      Ext       = ($f.Extension.ToLower() -replace '^$','(sin)')
      Bytes     = [int64]$f.Length
      MB        = [math]::Round($f.Length/1MB, 2)
      LastWrite = $f.LastWriteTime
      FullPath  = $f.FullName
    }
  }
  "{0}: {1:n0} archivos buenos" -f $d, $items.Count | Write-Host
}

if ($files.Count -eq 0) {
  Write-Warning "No se localizaron archivos vÃ¡lidos en H/I/J con el filtro actual."
}

# Resumen por disco
$summary = $files | Group-Object Drive | ForEach-Object {
  $sumBytes = ($_.Group | Measure-Object Bytes -Sum).Sum
  [pscustomobject]@{
    Drive = $_.Name
    Count = $_.Count
    GB    = [math]::Round($sumBytes/1GB, 2)
  }
} | Sort-Object Drive

# Totales
$totalCount = $files.Count
$totalGB    = [math]::Round((($files | Measure-Object Bytes -Sum).Sum)/1GB, 2)

# ============================== HTML OFFLINE ===============================
# Todo inline (CSS/JS) para funcionar sin Internet.
$fecha = Get-Date -Format 'yyyy-MM-dd HH:mm'

# CSS y JS (puros, sin & ni caracteres exÃ³ticos)
$css = @"
<style>
  :root { --bg:#0f172a; --panel:#111827; --text:#e5e7eb; --muted:#9ca3af; --chip:#1f2937; --accent:#22d3ee; }
  *{box-sizing:border-box}
  body{margin:16px;background:var(--bg);color:var(--text);font:14px/1.45 system-ui,Segoe UI,Roboto,Arial}
  h1{margin:0 0 6px 0;font-size:20px}
  .muted{color:var(--muted)}
  .wrap{max-width:1200px;margin:0 auto}
  .bar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:12px 0}
  .pill{background:var(--chip);padding:6px 10px;border-radius:999px;border:1px solid #374151}
  .pill b{color:#fff}
  .kbd{font-family:Consolas,monospace;background:#0b1220;border:1px solid #1f2937;padding:2px 6px;border-radius:6px}
  input[type="text"]{background:#0b1220;border:1px solid #1f2937;color:#e5e7eb;padding:8px 10px;border-radius:8px;min-width:260px}
  table{width:100%;border-collapse:separate;border-spacing:0 6px}
  thead th{font-weight:600;color:#cbd5e1;text-align:left;padding:8px}
  tbody tr{background:var(--panel);border:1px solid #1f2937}
  tbody td{padding:8px;vertical-align:top}
  tbody tr:hover{outline:1px solid var(--accent)}
  .path{font-family:Consolas,monospace}
  .btn{background:#0b1220;border:1px solid #1f2937;color:#e5e7eb;padding:8px 10px;border-radius:8px;cursor:pointer}
  .btn:disabled{opacity:.5;cursor:default}
  .pager{display:flex;gap:8px;align-items:center;justify-content:flex-end;margin-top:10px}
  .nowrap{white-space:nowrap}
  .grid-2{display:grid;grid-template-columns:1fr auto;gap:12px;align-items:center}
  .narrow{max-width:300px}
  a{color:#93c5fd;text-decoration:none}
  a:hover{text-decoration:underline}
  .copyok{color:#22c55e;margin-left:8px}
</style>
"@

$js = @"
<script>
// ==== tabla simple sin dependencias ====
(function(){
  const rows = [];
  // dataset llega desde window.__DATA__ inyectado abajo

  let data = window.__DATA__ || [];
  const PAGE=200;
  let page=0, filtered=data;

  const elTbl = document.getElementById('tbl-body');
  const elInfo= document.getElementById('info');
  const q     = document.getElementById('q');
  const prev  = document.getElementById('prev');
  const next  = document.getElementById('next');

  function fmtDate(s){
    return s.replace('T',' ').slice(0,19);
  }
  function render(){
    elTbl.innerHTML = '';
    const start = page*PAGE;
    const pageRows = filtered.slice(start, start+PAGE);
    for(const r of pageRows){
      const tr = document.createElement('tr');
      const link = 'file:///'+ r.FullPath.replaceAll('\\','/');
      tr.innerHTML = '<td>'+r.Drive+'</td>'+
                     '<td>'+r.Folder+'</td>'+
                     '<td>'+r.Name+'</td>'+
                     '<td>'+r.Ext+'</td>'+
                     '<td class="nowrap">'+r.MB.toFixed(2)+'</td>'+
                     '<td class="nowrap">'+fmtDate(r.LastWrite)+'</td>'+
                     '<td class="path"><a href="'+link+'">Abrir</a></td>';
      elTbl.appendChild(tr);
    }
    const pages = Math.max(1, Math.ceil(filtered.length/PAGE));
    elInfo.textContent = (filtered.length.toLocaleString())+' archivos â€” pÃ¡gina '+(page+1)+' / '+pages;
    prev.disabled = (page<=0);
    next.disabled = (page>=pages-1);
  }

  function doFilter(){
    const t = q.value.trim().toLowerCase();
    if(!t){ filtered = data; page=0; render(); return; }
    const parts = t.split(/\s+/).filter(Boolean);
    filtered = data.filter(r=>{
      const hay = (r.FullPathLower||'')+' '+(r.Ext||'')+' '+(r.Name||'');
      return parts.every(p=> hay.includes(p));
    });
    page=0; render();
  }

  q.addEventListener('input', function(){ window.requestAnimationFrame(doFilter); });
  prev.addEventListener('click', ()=>{ if(page>0){ page--; render(); }});
  next.addEventListener('click', ()=>{ const pages = Math.ceil(filtered.length/PAGE); if(page<pages-1){ page++; render(); }});

  render();
})();
</script>
"@

# Datos en JSON (segmentados si hace falta por tamaÃ±o)
# Compactamos campos y aÃ±adimos derivados para filtro rÃ¡pido
$dataset = $files | ForEach-Object {
  [pscustomobject]@{
    Drive        = $_.Drive
    Folder       = $_.Folder
    Name         = $_.Name
    Ext          = $_.Ext
    MB           = $_.MB
    LastWrite    = ($_.LastWrite.ToString('yyyy-MM-ddTHH:mm:ss'))
    FullPath     = $_.FullPath
    FullPathLower= $_.FullPath.ToLower()
  }
}

# Genera el HTML
$OutHtml = Join-Path $RepoRoot $OutName

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine('<!doctype html>')
$null = $sb.AppendLine('<html lang="es"><head><meta charset="utf-8">')
$null = $sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
$null = $sb.AppendLine("<title>$PageTitle</title>")
$null = $sb.AppendLine($css)
$null = $sb.AppendLine('</head><body><div class="wrap">')
$null = $sb.AppendLine("<h1>$PageTitle</h1>")
$chips = ($summary | ForEach-Object { "<span class='pill nowrap'><b>$($_.Drive):</b> $([string]::Format('{0:n0}', $_.Count)) archivos - $([string]::Format('{0:n2}', $_.GB)) GB</span>" }) -join " "
$chips += " <span class='pill nowrap'><b>TOTAL</b>: $([string]::Format('{0:n0}', $totalCount)) archivos - $([string]::Format('{0:n2}', $totalGB)) GB</span>"
$null = $sb.AppendLine("<div class='bar'>$chips</div>")
$null = $sb.AppendLine("<div class='muted'>Generado: $(HtmlEnc $fecha). Se excluyen <code>_quarantine*</code>, <code>System Volume Information</code>, <code>$Recycle.Bin</code> y <code>FOUND.###</code>.</div>")
$null = $sb.AppendLine('<div class="grid-2">')
$null = $sb.AppendLine('<input id="q" type="text" placeholder="Filtrar (FullPath, nombre, extensiÃ³n)...">')
$null = $sb.AppendLine('<div class="pager"><button id="prev" class="btn">&larr; Prev</button><span id="info" class="small muted"></span><button id="next" class="btn">Next &rarr;</button></div>')
$null = $sb.AppendLine('</div>')
$null = $sb.AppendLine('<table><thead><tr><th>Drive</th><th>Folder</th><th>Name</th><th>Ext</th><th>MB</th><th>LastWrite</th><th>Path</th></tr></thead><tbody id="tbl-body">')

# Cierra tabla; dataset y JS
$null = $sb.AppendLine('</tbody></table>')

# Inyecta DATA como JSON
# Nota: ConvertTo-Json por defecto limita profundidad; aquÃ­ no hay anidaciÃ³n compleja.
$json = $dataset | ConvertTo-Json -Depth 3 -Compress
# Escapa </script para evitar breaking del tag
$json = $json -replace '</script','<\/script'
$null = $sb.AppendLine('<script>window.__DATA__ = ')
$null = $sb.AppendLine($json)
$null = $sb.AppendLine(';</script>')

$null = $sb.AppendLine($js)
$null = $sb.AppendLine('</div></body></html>')

$sb.ToString() | Set-Content -LiteralPath $OutHtml -Encoding UTF8
Write-Host "Inventario generado: $OutHtml"

# Copia a docs\index.html (Pages)
$DocsIndexPath = Join-Path $RepoRoot $DocsIndex
Copy-Item -LiteralPath $OutHtml -Destination $DocsIndexPath -Force
Write-Host "Copiado a: $DocsIndexPath (para GitHub Pages)"

# ============================== GIT (opcional) ===============================
if ($DoGitPush) {
  # Verifica que git estÃ© disponible
  $gitOk = $false
  try {
    $v = git --version 2>$null
    if ($LASTEXITCODE -eq 0) { $gitOk = $true }
  } catch { $gitOk = $false }

  if ($gitOk) {
    try {
      git add --all
      $msg = "Inventario H/I/J actualizado - $fecha"
      git commit -m "$msg" 2>$null | Out-Null
      git push
      Write-Host "Cambios enviados a remoto (git push)."
      Write-Host "Recuerda: GitHub Pages tardarÃ¡ un poco en refrescar."
    } catch {
      Write-Warning "No se pudo hacer commit/push automÃ¡tico. Puedes hacerlo a mano."
    }
  } else {
    Write-Warning "git no estÃ¡ disponible en PATH; omito commit/push."
  }
}

Write-Host "OK. Abre docs\index.html localmente o espera a que Pages lo publique."
# =============================================================================



