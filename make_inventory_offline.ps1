# ============================
# make_inventory_offline.ps1
# Genera inventario interactivo en local y opcionalmente publica en docs/.
# ============================

[CmdletBinding()]
param(
  [string[]]$Drives = @('H','I','J'),
  [string]$Output = 'inventario_interactivo_offline.html',
  [string]$DocsTarget,
  [switch]$Push,
  [string]$CommitMessage = 'chore(docs): actualizar inventario offline'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function HtmlEnc {
  param([string]$Value)
  if (-not $Value) { return '' }
  return ($Value -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;')
}

$repoRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
Push-Location $repoRoot
try {
  $outputPath = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $repoRoot $Output }
  $docsTargetPath = $null
  if ($DocsTarget) {
    $docsTargetPath = if ([System.IO.Path]::IsPathRooted($DocsTarget)) { $DocsTarget } else { Join-Path $repoRoot $DocsTarget }
    $docsDir = Split-Path -Parent $docsTargetPath
    if ($docsDir -and -not (Test-Path $docsDir)) {
      New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
    }
  }

  $excludeRx = '\\(System Volume Information|\$Recycle\.Bin|FOUND\.\d{3}|_quarantine(_from_[A-Z]+|_quarantine)?|_quarantine)($|\\)'
  $files = [System.Collections.Generic.List[object]]::new()

  foreach ($drive in $Drives) {
    $root = '{0}:\' -f $drive
    if (-not (Test-Path $root)) {
      Write-Verbose "Unidad $drive no encontrada, se omite."
      continue
    }
    Write-Verbose "Explorando $drive ..."
    Get-ChildItem $root -Recurse -Force -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch $excludeRx } |
      ForEach-Object {
        $files.Add([pscustomobject]@{
          Drive     = $drive
          Folder    = $_.DirectoryName
          Name      = $_.Name
          Extension = ($_.Extension -replace '^$','(sin)')
          Size      = [int64]$_.Length
          MB        = [math]::Round($_.Length/1MB, 2)
          LastWrite = $_.LastWriteTime
          FullPath  = $_.FullName
        }) | Out-Null
      }
  }

  if (-not $files.Count) {
    Write-Warning 'No se encontraron archivos con el filtro actual.'
  }

  $summary = $files | Group-Object Drive | ForEach-Object {
    $sumBytes = ($_.Group | Measure-Object Size -Sum).Sum
    [pscustomobject]@{
      Drive = $_.Name
      Count = $_.Count
      GB    = [math]::Round($sumBytes / 1GB, 2)
    }
  } | Sort-Object Drive
  if (-not $summary) {
    $summary = @()
  }

  $fecha = Get-Date -Format 'yyyy-MM-dd HH:mm'
  $totalCount = ($summary | Measure-Object Count -Sum).Sum
  if (-not $totalCount) { $totalCount = 0 }
  $totalGB    = ($summary | Measure-Object GB -Sum).Sum
  if (-not $totalGB) { $totalGB = 0 }

  
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
    $sumBytes = ($_.Group | Measure-Object Size -Sum).Sum
    [pscustomobject]@{
      Drive = $driveId
      Folder = $folderId
      Count = $_.Count
      GB    = [math]::Round($sumBytes/1GB, 2)
    }
  }

  $topExtensions = $files | Group-Object Extension | ForEach-Object {
    $sumBytes = ($_.Group | Measure-Object Size -Sum).Sum
    [pscustomobject]@{
      Ext   = $_.Name
      Count = $_.Count
      GB    = [math]::Round($sumBytes/1GB, 2)
    }
  } | Sort-Object GB -Descending | Select-Object -First 8

  $dataset = $files | ForEach-Object {
    [pscustomobject]@{
      Drive        = $_.Drive
      Folder       = $_.Folder
      Name         = $_.Name
      Ext          = $_.Extension
      MB           = $_.MB
      LastWrite    = ($_.LastWrite.ToString('yyyy-MM-ddTHH:mm:ss'))
      FullPath     = $_.FullPath
      FullPathLower= $_.FullPath.ToLower()
    }
  }

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
    const guard = Math.max(1, Math.ceil(filtered.length / PAGE));
    info.textContent = 'Pagina '+ (guard === 0 ? 0 : page + 1) +' de '+ guard;
    stats.textContent = filtered.length.toLocaleString() +' de '+ data.length.toLocaleString() +' archivos visibles';
    prev.disabled = page <= 0;
    next.disabled = page >= guard - 1;
  }

  function apply(){
    const raw = (input?.value || '').trim().toLowerCase();
    const selected = column ? column.value : 'all';
    if (!raw) {
      filtered = data.slice();
      page = 0;
      render();
      return;
    }

    if (selected === 'all') {
      const terms = raw.split(/\s+/).filter(Boolean);
      filtered = data.filter(row => {
        const hay = [row.FullPathLower || '', row.Ext || '', row.Name || '', row.Folder || '', row.Drive || ''].join(' ');
        return terms.every(term => hay.includes(term));
      });
    } else {
      const getter = getters[selected] || (() => '');
      filtered = data.filter(row => getter(row).toLowerCase().includes(raw));
    }
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
    const csv = [header.join(','), ...lines].join('
');
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
    apply();
  });
  column?.addEventListener('change', apply);
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

  $sb = [System.Text.StringBuilder]::new()
  $null = $sb.AppendLine('<!doctype html>')
  $null = $sb.AppendLine('<html lang="es"><head><meta charset="utf-8">')
  $null = $sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
  $null = $sb.AppendLine('<title>Inventario Offline H/I/J</title>')
  $null = $sb.AppendLine($css)
  $null = $sb.AppendLine('</head><body><div class="wrap">')
  $null = $sb.AppendLine('<h1>Inventario H / I / J (offline)</h1>')
  $chips = ($summary | ForEach-Object { "<span class='pill nowrap'><b>$($_.Drive):</b> $([string]::Format('{0:n0}', $_.Count)) archivos - $([string]::Format('{0:n2}', $_.GB)) GB</span>" }) -join " "
  $chips += " <span class='pill nowrap'><b>TOTAL</b>: $([string]::Format('{0:n0}', $totalCount)) archivos - $([string]::Format('{0:n2}', $totalGB)) GB</span>"
  $null = $sb.AppendLine("<div class='bar'>$chips</div>")
  $analysisIntro = "Inventario generado el $fecha. Se excluyen carpetas de sistema, reciclaje y cuarentenas para evitar contar duplicados ya tratados."
  $null = $sb.AppendLine("<section class='panel intro'>")
  $null = $sb.AppendLine("<h2>Resumen rapido</h2>")
  $null = $sb.AppendLine("<p>$(HtmlEnc $analysisIntro)</p>")
  $null = $sb.AppendLine("<p class='muted small'>Los enlaces <code>file://</code> solo se abren de forma local.</p>")
  $null = $sb.AppendLine("<p class='muted small'>Las carpetas <code>_quarantine*</code> se omiten porque contienen copias que ya cuentan con respaldo o están en revisión.</p>")
  $null = $sb.AppendLine('</section>')

  $null = $sb.AppendLine("<section class='panel'>")
  $null = $sb.AppendLine("<h2>Carpetas destacadas por unidad</h2>")
  $null = $sb.AppendLine("<p>Ayuda a decidir que zonas respaldar o depurar primero.</p>")
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
    $null = $sb.AppendLine("<p class='muted'>No hay carpetas destacadas disponible.</p>")
  }
  $null = $sb.AppendLine('</section>')

  if ($topExtensions) {
    $null = $sb.AppendLine("<section class='panel'>")
    $null = $sb.AppendLine("<h2>Tipos de archivo predominantes</h2>")
    $null = $sb.AppendLine("<p>Formatos pesados sirven como referencia para planes de copia o limpieza.</p>")
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
  $null = $sb.AppendLine("  </div>")
  $null = $sb.AppendLine('</div>')
  $null = $sb.AppendLine("<div class='pager'>")
  $null = $sb.AppendLine("  <button id='prev' class='btn'>&larr; Prev</button>")
  $null = $sb.AppendLine("  <span id='info' class='muted small'></span>")
  $null = $sb.AppendLine("  <button id='next' class='btn'>Next &rarr;</button>")
  $null = $sb.AppendLine('</div>')
  $null = $sb.AppendLine('<table id="tbl"><thead><tr><th>Drive</th><th>Folder</th><th>Name</th><th>Ext</th><th>MB</th><th>LastWrite</th><th>Path</th></tr></thead><tbody></tbody></table>')
  $null = $sb.AppendLine('</section>')

  $json = $dataset | ConvertTo-Json -Depth 3 -Compress
  $json = $json -replace '</script','<\/script'
  $null = $sb.AppendLine('<script>window.__DATA__ = ')
  $null = $sb.AppendLine($json)
  $null = $sb.AppendLine(';</script>')
  $null = $sb.AppendLine($js)
  $null = $sb.AppendLine('</div></body></html>')

  $sb.ToString() | Set-Content -Path $outputPath -Encoding UTF8
  Write-Host "Inventario generado en: $outputPath"


  if ($docsTargetPath) {
    Copy-Item -LiteralPath $outputPath -Destination $docsTargetPath -Force
    Write-Host "Copiado a: $docsTargetPath"
  }

  if ($Push) {
    $git = Get-Command git -ErrorAction Stop
    $targets = @($outputPath)
    if ($docsTargetPath) { $targets += $docsTargetPath }
    $relative = @()
    foreach ($target in ($targets | Sort-Object -Unique)) {
      if (Test-Path $target) {
        $relative += (Resolve-Path -LiteralPath $target -Relative)
      }
    }
    foreach ($item in $relative) {
      & $git.Source add -- $item
    }
    $status = (& $git.Source status --short)
    if (-not $status) {
      Write-Host 'No hay cambios para commitear.'
    } else {
      & $git.Source commit -m $CommitMessage | Out-Null
      & $git.Source push
      Write-Host 'Cambios enviados a remoto.'
    }
  }
}
finally {
  Pop-Location
}

