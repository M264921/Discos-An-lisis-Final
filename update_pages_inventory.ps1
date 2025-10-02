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
foreach ($d in $Drives) {
  $root = "$($d):\"
  if (-not (Test-Path $root)) {
    Write-Host " - $($d): no existe, se omite."
    continue
  }

  Write-Host " - $($d): leyendo..."
  $items = Get-ChildItem $root -Recurse -Force -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch $ExcludeRx }

  foreach ($f in $items) {
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


$formattedTotalCount = [string]::Format('{0:n0}', $totalCount)
$formattedTotalGB = [string]::Format('{0:n2}', $totalGB)

$topFolderGroups = $files | Group-Object {
  $relative = ($_.FullPath -replace '^[A-Za-z]:\\', '')
  if (-not $relative) { return "{0}|(raiz)" -f $_.Drive }
  $segment = $relative.Split('\')[0]
  if (-not $segment) { return "{0}|(raiz)" -f $_.Drive }
  return "{0}|{1}" -f $_.Drive, $segment
}

$topFolders = $topFolderGroups | ForEach-Object {
  $parts = $_.Name.Split('|', 2)
  $driveId = $parts[0]
  $folderId = if ($parts.Count -gt 1) { $parts[1] } else { '(raiz)' }
  $sumBytes = ($_.Group | Measure-Object Bytes -Sum).Sum
  [pscustomobject]@{
    Drive = $driveId
    Folder = $folderId
    Count = $_.Count
    GB    = [math]::Round($sumBytes/1GB, 2)
  }
}

$topExtensions = $files | Group-Object Ext | ForEach-Object {
  $sumBytes = ($_.Group | Measure-Object Bytes -Sum).Sum
  [pscustomobject]@{
    Ext   = $_.Name
    Count = $_.Count
    GB    = [math]::Round($sumBytes/1GB, 2)
  }
} | Sort-Object GB -Descending | Select-Object -First 8

# ============================== HTML OFFLINE ===============================
# Todo inline (CSS/JS) para funcionar sin Internet.
$fecha = Get-Date -Format 'yyyy-MM-dd HH:mm'

# CSS y JS (puros, sin & ni caracteres exÃ³ticos)
$css = @"
<style>
  :root { --bg:#0f172a; --panel:#111827; --text:#e5e7eb; --muted:#9ca3af; --chip:#1f2937; --accent:#22d3ee; }
  *{box-sizing:border-box}
  body{margin:16px;background:var(--bg);color:var(--text);font:14px/1.5 system-ui,Segoe UI,Roboto,Arial}
  h1{margin:0 0 10px;font-size:22px}
  h2{margin:0 0 12px;font-size:18px;color:#e2e8f0}
  .muted{color:var(--muted)}
  .wrap{max-width:1200px;margin:0 auto}
  .bar{display:flex;flex-wrap:wrap;gap:12px;margin:12px 0}
  .pill{background:var(--chip);padding:6px 12px;border-radius:999px;border:1px solid #1f2937}
  .pill b{color:#fff}
  .panel{background:rgba(15,23,42,0.35);border:1px solid #1f2937;border-radius:16px;padding:18px;margin:18px 0}
  .panel p{margin:0 0 12px}
  .cards{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(220px,1fr))}
  .card{background:#0f172a;border:1px solid #1f2937;border-radius:14px;padding:14px}
  .card h3{margin:0 0 6px;font-size:16px;color:#e2e8f0}
  .insights{list-style:none;margin:8px 0 0;padding:0;font-size:13px;color:#cbd5e1}
  .insights li{margin:4px 0;line-height:1.4}
  .tag{display:inline-flex;align-items:center;gap:6px;background:#1f2937;border:1px solid #334155;border-radius:999px;padding:3px 10px;font-size:12px;color:#e2e8f0}
  .toolbar{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-start;justify-content:space-between;margin:12px 0}
  .filter{display:flex;flex-direction:column;gap:6px;min-width:260px}
  .filter-controls{display:flex;gap:8px;align-items:center}
  .filter-controls input{flex:1 1 260px;background:#0b1220;color:#e5e7eb;border:1px solid #1f2937;border-radius:8px;padding:8px 10px}
  .actions{display:flex;flex-wrap:wrap;gap:8px}
  .selector{background:#0b1220;border:1px solid #1f2937;color:#e5e7eb;padding:8px 10px;border-radius:8px}
  .table-wrap{overflow:auto;margin-top:12px}
  thead tr.filters th{background:#0b1220;padding:6px;color:#94a3b8;font-weight:500}
  .column-filter{width:100%;background:#0b1220;color:#e5e7eb;border:1px solid #1f2937;border-radius:6px;padding:6px 8px;font-size:12px}
  .column-filter::placeholder{color:#64748b}
  .file-link{color:#38bdf8;text-decoration:none}
  .file-link:hover{text-decoration:underline}
  .btn{background:#0b1220;border:1px solid #1f2937;color:#e5e7eb;padding:8px 12px;border-radius:8px;cursor:pointer;transition:background .2s}
  .btn:hover{background:#1d283a}
  .btn.secondary{background:#13213a;border-color:#233554}
  .btn.secondary:hover{background:#1f2f4c}
  .btn.ghost{background:transparent;border-color:#334155}
  .btn.ghost:hover{background:#1d283a}
  .pager{display:flex;gap:10px;align-items:center;margin:12px 0 18px}
  table{width:100%;border-collapse:separate;border-spacing:0 8px;font-size:13px}
  thead th{color:#cbd5e1;text-align:left;padding:8px;background:#0f172a;border:1px solid #1f2937;border-bottom:0}
  tbody tr{background:#111f37;border:1px solid #1f2937}
  tbody td{padding:8px;vertical-align:top}
  tbody tr:hover{outline:1px solid var(--accent)}
  td.path{font-family:Consolas,Monaco,monospace}
  .small{font-size:12px}
  .nowrap{white-space:nowrap}
  .summary-table{width:100%;border-collapse:collapse;margin-top:10px;font-size:13px}
  .summary-table thead th{background:#0b1220;color:#e2e8f0;text-align:left;padding:8px;border-bottom:1px solid #1f2937}
  .summary-table tbody td{padding:6px 8px;border-bottom:1px solid #1f2937;color:#cbd5e1}
  .summary-table tbody tr:hover{background:#17233b}
</style>
"@
$js = @"
<script>
(function(){
  const data = window.__DATA__ || [];
  const PAGE = 200;
  let page = 0;
  let filtered = data.slice();

  const tbody = document.querySelector('#tbl tbody');
  const input = document.getElementById('q');
  const clear = document.getElementById('clr');
  const stats = document.getElementById('count');
  const info = document.getElementById('info');
  const prev = document.getElementById('prev');
  const next = document.getElementById('next');
  const download = document.getElementById('download');
  const downloadAll = document.getElementById('download-all');
  const column = document.getElementById('column');
  const columnInputs = Array.from(document.querySelectorAll('.column-filter'));

  const getters = {
    Drive: row => (row.Drive || ''),
    Folder: row => (row.Folder || ''),
    Name: row => (row.Name || ''),
    Ext: row => (row.Ext || ''),
    MB: row => String(row.MB ?? ''),
    LastWrite: row => (row.LastWrite || ''),
    FullPath: row => (row.FullPath || '')
  };

  function fmtDate(value){
    return (value || '').replace('T',' ').slice(0,19);
  }

  function escapeHtml(value){
    return String(value ?? '').replace(/[&<>"']/g, ch => ({
      '&':'&amp;',
      '<':'&lt;',
      '>':'&gt;',
      '"':'&quot;',
      "'":'&#39;'
    })[ch] ?? ch);
  }

  function buildRow(row){
    const rawPath = row.FullPath || '';
    const href = 'file:///' + rawPath.split('\').join('/');
    const size = Number(row.MB ?? 0);
    const sizeCell = Number.isFinite(size) ? size.toFixed(2) : '0.00';
    const safeDrive = escapeHtml(row.Drive || '');
    const safeFolder = escapeHtml(row.Folder || '');
    const safeName = escapeHtml(row.Name || '');
    const safeExt = escapeHtml(row.Ext || '');
    const safePath = escapeHtml(rawPath);
    const safeHref = escapeHtml(href);
    const nameLabel = safeName || '(sin nombre)';
    const pathLabel = safePath || '(sin ruta)';
    return '<td>'+ safeDrive +'</td>'+
           '<td>'+ safeFolder +'</td>'+
           '<td><a class="file-link" href="'+ safeHref +'" target="_blank" rel="noopener">'+ nameLabel +'</a></td>'+
           '<td>'+ safeExt +'</td>'+
           '<td>'+ sizeCell +'</td>'+
           '<td>'+ fmtDate(row.LastWrite) +'</td>'+
           '<td class="path"><a class="file-link" href="'+ safeHref +'" target="_blank" rel="noopener">'+ pathLabel +'</a></td>';
  }

  function render(){
    tbody.innerHTML = '';
    const start = page * PAGE;
    const slice = filtered.slice(start, start + PAGE);
    for (const row of slice) {
      const tr = document.createElement('tr');
      tr.innerHTML = buildRow(row);
      tbody.appendChild(tr);
    }
    const totalRows = filtered.length;
    const totalPages = totalRows === 0 ? 0 : Math.ceil(totalRows / PAGE);
    if (totalPages === 0) {
      info.textContent = 'Sin resultados';
      page = 0;
      prev.disabled = true;
      next.disabled = true;
    } else {
      info.textContent = 'Pagina '+ (page + 1) +' de '+ totalPages;
      prev.disabled = page <= 0;
      next.disabled = page >= totalPages - 1;
    }
    stats.textContent = totalRows.toLocaleString() +' de '+ data.length.toLocaleString() +' archivos visibles';
  }

  function apply(){
    const raw = (input?.value || '').trim().toLowerCase();
    const selected = column ? column.value : 'all';
    const activeColumns = columnInputs
      .map(el => ({ field: el.dataset.field, value: (el.value || '').trim().toLowerCase() }))
      .filter(entry => entry.field && entry.value);

    filtered = data.filter(row => {
      if (raw) {
        if (selected === 'all') {
          const terms = raw.split(/\s+/).filter(Boolean);
          const hay = [row.FullPathLower || '', row.Ext || '', row.Name || '', row.Folder || '', row.Drive || ''].join(' ');
          if (!terms.every(term => hay.includes(term))) {
            return false;
          }
        } else {
          const getter = getters[selected] || (() => '');
          if (!getter(row).toLowerCase().includes(raw)) {
            return false;
          }
        }
      }

      for (const filter of activeColumns) {
        const getter = getters[filter.field] || (() => '');
        if (!getter(row).toLowerCase().includes(filter.value)) {
          return false;
        }
      }

      return true;
    });

    page = 0;
    render();
  }

  function downloadRows(rows, filename){
    if (!rows.length) {
      alert('No hay filas para descargar con el filtro actual.');
      return;
    }
    const header = ['Drive','Folder','Name','Ext','MB','LastWrite','Path'];
    const lines = rows.map(row => {
      const size = Number(row.MB ?? 0);
      const sizeCell = Number.isFinite(size) ? size.toFixed(2) : '0.00';
      return [
        row.Drive,
        row.Folder,
        row.Name,
        row.Ext,
        sizeCell,
        fmtDate(row.LastWrite),
        row.FullPath
      ].map(value => '"'+ String(value ?? '').replace(/"/g,'""') +'"').join(',');
    });
    const csv = [header.join(','), ...lines].join('\n');
    const blob = new Blob([csv], { type:'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  input?.addEventListener('input', () => window.requestAnimationFrame(apply));
  clear?.addEventListener('click', () => {
    input.value = '';
    columnInputs.forEach(el => { el.value = ''; });
    apply();
  });
  column?.addEventListener('change', apply);
  columnInputs.forEach(el => {
    el.addEventListener('input', () => window.requestAnimationFrame(apply));
  });
  prev?.addEventListener('click', () => { if (page > 0) { page--; render(); } });
  next?.addEventListener('click', () => {
    const guard = Math.ceil(filtered.length / PAGE);
    if (page < guard - 1) { page++; render(); }
  });

  download?.addEventListener('click', () => downloadRows(filtered, 'inventario_filtrado.csv'));
  downloadAll?.addEventListener('click', () => downloadRows(data, 'inventario_completo.csv'));

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
  $null = $sb.AppendLine("<section class='panel dataset'>")
  $null = $sb.AppendLine("<h2>Explorador interactivo</h2>")
  $null = $sb.AppendLine("<p>Filtra por cualquier fragmento y exporta la vista actual o el inventario completo en CSV.</p>")
  $null = $sb.AppendLine("<div class='toolbar'>")
  $null = $sb.AppendLine("  <div class='filter'>")
  $null = $sb.AppendLine("    <div class='filter-controls'>")
  $null = $sb.AppendLine("      <select id='column' class='selector'>")
  $null = $sb.AppendLine("        <option value='all'>Todos los campos</option>")
  $null = $sb.AppendLine("        <option value='Drive'>Unidad</option>")
  $null = $sb.AppendLine("        <option value='Folder'>Carpeta</option>")
  $null = $sb.AppendLine("        <option value='Name'>Nombre</option>")
  $null = $sb.AppendLine("        <option value='Ext'>Extensión</option>")
  $null = $sb.AppendLine("        <option value='MB'>Tamaño (MB)</option>")
  $null = $sb.AppendLine("        <option value='LastWrite'>Fecha</option>")
  $null = $sb.AppendLine("        <option value='FullPath'>Ruta completa</option>")
  $null = $sb.AppendLine("      </select>")
  $null = $sb.AppendLine("      <input id='q' type='text' placeholder='Filtrar por carpeta, nombre o extension...'>")
  $null = $sb.AppendLine("      <button id='clr' class='btn ghost'>Limpiar</button>")
  $null = $sb.AppendLine("    </div>")
  $null = $sb.AppendLine("    <span id='count' class='muted small'></span>")
  $null = $sb.AppendLine("  </div>")
  $null = $sb.AppendLine("  <div class='actions'>")
  $null = $sb.AppendLine("    <button id='download' class='btn secondary'>Descargar vista (CSV)</button>")
  $null = $sb.AppendLine("    <button id='download-all' class='btn secondary ghost'>Descargar todo (CSV)</button>")
  $null = $sb.AppendLine("    <a id='popout' class='btn ghost' href='inventario_interactivo_offline.html' target='_blank' rel='noopener'>Abrir solo la tabla</a>")
  $null = $sb.AppendLine("  </div>")
  $null = $sb.AppendLine('</div>')
  $null = $sb.AppendLine("<div class='pager'>")
  $null = $sb.AppendLine("  <button id='prev' class='btn'>&larr; Prev</button>")
  $null = $sb.AppendLine("  <span id='info' class='muted small'></span>")
  $null = $sb.AppendLine("  <button id='next' class='btn'>Next &rarr;</button>")
  $null = $sb.AppendLine('</div>')
  $null = $sb.AppendLine("<div class='table-wrap'>")
  $null = $sb.AppendLine("  <table id='tbl'><thead>")
  $null = $sb.AppendLine("    <tr><th>Drive</th><th>Folder</th><th>Name</th><th>Ext</th><th>MB</th><th>LastWrite</th><th>Path</th></tr>")
  $null = $sb.AppendLine("    <tr class='filters'><th><input class='column-filter' data-field='Drive' placeholder='Filtrar unidad'></th><th><input class='column-filter' data-field='Folder' placeholder='Filtrar carpeta'></th><th><input class='column-filter' data-field='Name' placeholder='Filtrar nombre'></th><th><input class='column-filter' data-field='Ext' placeholder='Filtrar extensión'></th><th><input class='column-filter' data-field='MB' placeholder='Filtrar MB'></th><th><input class='column-filter' data-field='LastWrite' placeholder='Filtrar fecha'></th><th><input class='column-filter' data-field='FullPath' placeholder='Filtrar ruta'></th></tr>")
  $null = $sb.AppendLine("  </thead><tbody></tbody></table>")
  $null = $sb.AppendLine('</div>')
  $null = $sb.AppendLine('</section>')
$analysisIntro = "Se han catalogado $formattedTotalCount archivos (~$formattedTotalGB GB). Usa el resumen para priorizar limpieza y evita contar las cuarentenas que ya tienen duplicados controlados."
$null = $sb.AppendLine("<section class='panel intro'>")
$null = $sb.AppendLine("<h2>Resumen rapido</h2>")
$null = $sb.AppendLine("<p>$(HtmlEnc $analysisIntro)</p>")
$null = $sb.AppendLine("<p class='muted small'>Se excluyen <code>_quarantine*</code>, <code>System Volume Information</code>, <code>$Recycle.Bin</code> y <code>FOUND.###</code> para evitar contar archivos ya duplicados o en cuarentena.</p>")
$null = $sb.AppendLine('</section>')
$null = $sb.AppendLine("<section class='panel'>")
$null = $sb.AppendLine("<h2>Carpetas destacadas por unidad</h2>")
$null = $sb.AppendLine("<p>Los conjuntos que concentran mas espacio ayudan a priorizar el ordenado.</p>")
if ($topFolders) {
  $driveCardsBuilder = [System.Text.StringBuilder]::new()
  foreach ($driveInfo in $summary) {
    $driveId = $driveInfo.Drive
    $driveCountFmt = [string]::Format('{0:n0}', $driveInfo.Count)
    $driveGBFmt = [string]::Format('{0:n2}', $driveInfo.GB)
    $null = $driveCardsBuilder.AppendLine("<article class='card'>")
    $null = $driveCardsBuilder.AppendLine("<h3>Unidad $driveId</h3>")
    $null = $driveCardsBuilder.AppendLine("<p>$driveCountFmt archivos &middot; $driveGBFmt GB</p>")
    $null = $driveCardsBuilder.AppendLine("<ul class='insights'>")
    $driveTop = $topFolders | Where-Object { $_.Drive -eq $driveId } | Sort-Object GB -Descending | Select-Object -First 3
    if (-not $driveTop) {
      $null = $driveCardsBuilder.AppendLine("<li>Sin carpetas destacadas</li>")
    } else {
      foreach ($entry in $driveTop) {
        $folderLabel = if ($entry.Folder -eq '(raiz)') { '{0}:\ (raiz)' -f $driveId } else { '{0}:\{1}' -f $driveId, $entry.Folder }
        $safeLabel = HtmlEnc($folderLabel)
        $countFmt = [string]::Format('{0:n0}', $entry.Count)
        $gbFmt = [string]::Format('{0:n2}', $entry.GB)
        $null = $driveCardsBuilder.AppendLine("<li><span class='tag'>$safeLabel</span> $countFmt archivos &middot; $gbFmt GB</li>")
      }
    }
    $null = $driveCardsBuilder.AppendLine('</ul>')
    $null = $driveCardsBuilder.AppendLine('</article>')
  }
  $driveCardsHtml = $driveCardsBuilder.ToString().Trim()
  if ($driveCardsHtml) {
    $null = $sb.AppendLine("<div class='cards'>")
    $null = $sb.AppendLine($driveCardsHtml)
    $null = $sb.AppendLine('</div>')
  }
} else {
  $null = $sb.AppendLine("<p class='muted'>No hay carpetas con datos suficientes.</p>")
}
$null = $sb.AppendLine('</section>')
if ($topExtensions) {
  $null = $sb.AppendLine("<section class='panel'>")
  $null = $sb.AppendLine("<h2>Tipos de archivo predominantes</h2>")
  $null = $sb.AppendLine("<p>Los formatos con mayor peso acumulado pueden indicar oportunidades de depuracion o migracion.</p>")
  $null = $sb.AppendLine("<ul class='insights'>")
  foreach ($extStat in $topExtensions) {
    $label = if ($extStat.Ext -eq '(sin)') { 'Sin extension' } else { ($extStat.Ext).ToUpper() }
    $safeLabel = HtmlEnc($label)
    $countFmt = [string]::Format('{0:n0}', $extStat.Count)
    $gbFmt = [string]::Format('{0:n2}', $extStat.GB)
    $null = $sb.AppendLine("<li><span class='tag'>$safeLabel</span> $countFmt archivos &middot; $gbFmt GB</li>")
  }
  $null = $sb.AppendLine('</ul>')
  $null = $sb.AppendLine('</section>')
}

$folderRanking = @()
if ($topFolders) {
  $folderRanking = @($topFolders | Where-Object { $_.GB -gt 0.05 } | Sort-Object GB -Descending)
  if (-not $folderRanking.Count) {
    $folderRanking = @($topFolders | Sort-Object GB -Descending | Select-Object -First 12)
  } else {
    $folderRanking = @($folderRanking | Select-Object -First 12)
  }
}

if ($folderRanking.Count) {
  $null = $sb.AppendLine("<section class='panel'>")
  $null = $sb.AppendLine("<h2>Resumen por carpeta principal</h2>")
  $null = $sb.AppendLine("<p>Ranking de carpetas superiores ordenadas por espacio ocupado (hasta 12 entradas).</p>")
  $null = $sb.AppendLine("<table class='summary-table'>")
  $null = $sb.AppendLine("<thead><tr><th>Unidad</th><th>Carpeta</th><th>Archivos</th><th>GB</th></tr></thead><tbody>")
  foreach ($entry in $folderRanking) {
    $folderLabel = if ($entry.Folder -eq '(raiz)') { '{0}:\\ (raíz)' -f $entry.Drive } else { '{0}:\\{1}' -f $entry.Drive, $entry.Folder }
    $safeLabel = HtmlEnc($folderLabel)
    $countFmt = [string]::Format('{0:n0}', $entry.Count)
    $gbFmt = [string]::Format('{0:n2}', $entry.GB)
    $null = $sb.AppendLine("<tr><td>$($entry.Drive)</td><td>$safeLabel</td><td class='nowrap'>$countFmt</td><td class='nowrap'>$gbFmt GB</td></tr>")
  }
  $null = $sb.AppendLine('</tbody></table>')
  $null = $sb.AppendLine('</section>')
}

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




