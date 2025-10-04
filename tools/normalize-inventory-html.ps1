Param(
  [string]$HtmlPath = 'docs/inventario_interactivo_offline.html',
  [int]$PreviewRows = 50
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $HtmlPath)) {
  throw "No existe el HTML de inventario: $HtmlPath"
}

[string]$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$originalHtml = $html

$ignoreCase = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$singleLine = [System.Text.RegularExpressions.RegexOptions]::Singleline
$multiLine = [System.Text.RegularExpressions.RegexOptions]::Multiline

$html = [regex]::Replace($html, 'windiw', 'window', $ignoreCase)

function Resolve-DataBlock {
  param([string]$Content)
  $options = $ignoreCase -bor $singleLine
  $result = [ordered]@{ Json = $null; Meta = $null; Source = 'none'; Match = $null }

  $setDataRegex = [System.Text.RegularExpressions.Regex]::new('window\.__INVENTARIO__\.setData\(\s*(\[[\s\S]*?\])\s*,\s*([^)]+?)\);', $options)
  $match = $setDataRegex.Match($Content)
  if ($match.Success) {
    $result.Json = $match.Groups[1].Value
    $result.Meta = $match.Groups[2].Value
    $result.Source = 'setData'
    $result.Match = $match
    return $result
  }

  $dataRegex = [System.Text.RegularExpressions.Regex]::new('window\.(?:__DATA__|_DATA_)\s*=\s*(\[[\s\S]*?\]);', $options)
  $match = $dataRegex.Match($Content)
  if ($match.Success) {
    $result.Json = $match.Groups[1].Value
    $result.Source = 'window.__DATA__'
  }

  $metaRegex = [System.Text.RegularExpressions.Regex]::new('window\.(?:__META__|_META_)\s*=\s*(.+?);', $options)
  $metaMatch = $metaRegex.Match($Content)
  if ($metaMatch.Success) {
    $result.Meta = $metaMatch.Groups[1].Value
  }

  return $result
}

$block = Resolve-DataBlock -Content $html
if (-not $block.Json) {
  Write-Host 'WARN: No se encontro bloque de datos en el HTML.'
  return
}

function Parse-JsonArray {
  param([string]$Json)
  if (-not $Json) { return @() }
  $trimmed = $Json.Trim()
  if ($trimmed.EndsWith(';')) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) }
  try {
    $parsed = $trimmed | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Write-Warning "No se pudo convertir JSON del inventario: $($_.Exception.Message)"
    return @()
  }
  if ($null -eq $parsed) { return @() }
  if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
    return @($parsed)
  }
  return @($parsed)
}

$rows = Parse-JsonArray -Json $block.Json

function Get-PropertyValue {
  param(
    [psobject]$Row,
    [string[]]$Names
  )
  foreach ($name in $Names) {
    $prop = $Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
    if ($prop -and $null -ne $prop.Value) {
      $value = ("{0}" -f $prop.Value).Trim()
      if ($value) { return $prop.Value }
    }
  }
  return $null
}

function Build-DriveMap {
  param([object[]]$InputRows)
  $map = [ordered]@{}
  foreach ($row in $InputRows) {
    if (-not $row) { continue }
    $drive = $null
    if ($row.PSObject.Properties['Drive']) { $drive = $row.Drive }
    if (-not $drive) { $drive = Get-PropertyValue -Row $row -Names @('Unidad') }
    if (-not $drive) {
      $path = Get-PropertyValue -Row $row -Names @('Path', 'FullPath', 'FullName', 'Location')
      if (-not $path) { $path = Get-PropertyValue -Row $row -Names @('Ruta', 'RutaCompleta') }
      if ($path -and $path -match '^[A-Za-z]:') { $drive = $path.Substring(0, 1) }
    }
    if (-not $drive) { continue }
    $key = ("{0}" -f $drive).Substring(0, 1).ToUpperInvariant()
    if (-not $map.Contains($key)) { $map[$key] = 0 }
    $map[$key]++
  }
  foreach ($letter in @('H', 'I', 'J')) {
    if (-not $map.Contains($letter)) { $map[$letter] = 0 }
  }
  return $map
}

$driveMap = Build-DriveMap -InputRows $rows

function Build-MetaSummary {
  param(
    [object[]]$InputRows,
    [ordered]$DriveCounts
  )
  $metaParts = New-Object System.Collections.Generic.List[string]
  $metaParts.Add("Total: {0}" -f $InputRows.Count) | Out-Null
  foreach ($letter in @('H', 'I', 'J')) {
    if ($DriveCounts.Contains($letter)) {
      $metaParts.Add("{0}: {1} files" -f $letter, $DriveCounts[$letter]) | Out-Null
    }
  }
  $others = $DriveCounts.Keys | Where-Object { $_ -notin @('H', 'I', 'J') } | Sort-Object
  foreach ($drive in $others) {
    $metaParts.Add("{0}: {1} files" -f $drive, $DriveCounts[$drive]) | Out-Null
  }
  return ($metaParts -join ' | ')
}

$summary = Build-MetaSummary -InputRows $rows -DriveCounts $driveMap

$metaObject = [ordered]@{
  summary = $summary
  total = $rows.Count
  drives = $driveMap
}

function Parse-MetaCandidate {
  param([string]$MetaText)
  if (-not $MetaText) { return $null }
  $trimmed = $MetaText.Trim()
  if ($trimmed.EndsWith(';')) { $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) }
  try {
    $parsed = $trimmed | ConvertFrom-Json -ErrorAction Stop
    return $parsed
  } catch {}
  if ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
    try { return ($trimmed | ConvertFrom-Json -ErrorAction Stop) } catch {}
  }
  return $trimmed
}

$existingMeta = Parse-MetaCandidate -MetaText $block.Meta
if ($existingMeta -is [string] -and [string]::IsNullOrWhiteSpace($existingMeta)) {
  $existingMeta = $null
}
if ($existingMeta -is [psobject]) {
  if ($existingMeta.PSObject.Properties['summary'] -and $existingMeta.summary) {
    $metaObject.summary = ("{0}" -f $existingMeta.summary).Trim()
  }
  if ($existingMeta.PSObject.Properties['total'] -and $existingMeta.total -is [int]) {
    $metaObject.total = [int]$existingMeta.total
  }
  if ($existingMeta.PSObject.Properties['drives']) {
    foreach ($prop in $existingMeta.drives.PSObject.Properties) {
      $key = ("{0}" -f $prop.Name).Trim().ToUpperInvariant()
      if (-not $metaObject.drives.Contains($key)) { $metaObject.drives[$key] = 0 }
      $metaObject.drives[$key] = [int]$prop.Value
    }
  }
}
if ($existingMeta -is [string] -and $existingMeta.Trim()) {
  $metaObject.summary = $existingMeta.Trim()
}
if (-not $metaObject.summary) {
  $metaObject.summary = $summary
}
if (-not $metaObject.total -or $metaObject.total -lt 0) {
  $metaObject.total = $rows.Count
}

$dataJson = ($rows | ConvertTo-Json -Depth 8 -Compress)
$metaJson = ($metaObject | ConvertTo-Json -Depth 6 -Compress)

$scriptCleanupPatterns = @(
  '<script[^>]*>\s*window\.__INVENTARIO__\.setData\([\s\S]*?</script>',
  '<script[^>]*>\s*window\.(?:__DATA__|_DATA_)\s*=\s*[\s\S]*?</script>'
)
foreach ($pattern in $scriptCleanupPatterns) {
  $regex = [System.Text.RegularExpressions.Regex]::new($pattern, $ignoreCase -bor $singleLine)
  $html = $regex.Replace($html, '')
}
$html = [regex]::Replace($html, 'window\.(?:__DATA__|_DATA_)\s*=\s*\[[\s\S]*?\];', '', $ignoreCase -bor $singleLine)
$html = [regex]::Replace($html, 'window\.(?:__META__|_META_)\s*=\s*.+?;', '', $ignoreCase -bor $singleLine)
$html = [regex]::Replace($html, '<style[^>]*id="inventory-preview-shim-style"[^>]*>[\s\S]*?</style>', '', $ignoreCase -bor $singleLine)
$html = [regex]::Replace($html, '<script[^>]*id="inventory-preview-shim-script"[^>]*>[\s\S]*?</script>', '', $ignoreCase -bor $singleLine)
$html = [regex]::Replace($html, '<script[^>]*id="inventory-preview-data"[^>]*>[\s\S]*?</script>', '', $ignoreCase -bor $singleLine)

$styleBlock = @"
<style id="inventory-preview-shim-style">
  #inventory-preview-shim {
    font-family: 'Segoe UI', Arial, sans-serif;
    border: 1px solid #ccc;
    border-radius: 8px;
    padding: 16px;
    margin: 24px auto;
    background: #fff;
    box-shadow: 0 2px 6px rgba(0,0,0,0.1);
    max-width: 1200px;
  }
  #inventory-preview-shim h2 {
    margin: 0 0 8px 0;
    font-size: 1.4rem;
  }
  .inventory-preview-meta {
    font-size: 0.95rem;
    margin-bottom: 12px;
    color: #333;
    word-break: break-word;
  }
  .inventory-preview-actions {
    display: flex;
    gap: 8px;
    margin-bottom: 12px;
    flex-wrap: wrap;
  }
  .inventory-preview-actions button {
    background-color: #2563eb;
    color: #fff;
    border: none;
    border-radius: 4px;
    padding: 6px 12px;
    cursor: pointer;
  }
  .inventory-preview-actions button[disabled] {
    background-color: #94a3b8;
    cursor: not-allowed;
  }
  .inventory-preview-filters {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 8px;
    margin-bottom: 12px;
  }
  .inventory-preview-filters label {
    display: flex;
    flex-direction: column;
    font-size: 0.85rem;
    color: #1f2937;
  }
  .inventory-preview-filters input {
    margin-top: 4px;
    padding: 4px 6px;
    border-radius: 4px;
    border: 1px solid #cbd5f5;
  }
  .inventory-preview-table-wrapper {
    overflow-x: auto;
  }
  #inventory-preview-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.9rem;
  }
  #inventory-preview-table th,
  #inventory-preview-table td {
    border: 1px solid #d1d5db;
    padding: 6px 8px;
    text-align: left;
  }
  #inventory-preview-table th {
    background: #f3f4f6;
    cursor: pointer;
    position: relative;
    user-select: none;
  }
  #inventory-preview-table th.sort-asc::after {
    content: '▲';
    position: absolute;
    right: 8px;
    font-size: 0.7rem;
  }
  #inventory-preview-table th.sort-desc::after {
    content: '▼';
    position: absolute;
    right: 8px;
    font-size: 0.7rem;
  }
  .inventory-preview-empty {
    margin-top: 12px;
    color: #6b7280;
    font-style: italic;
  }
  .inventory-preview-more {
    margin-top: 8px;
    font-size: 0.85rem;
    color: #334155;
  }
</style>
"@

$scriptBlock = @"
<script id="inventory-preview-shim-script">
(function(){
  const MAX_PREVIEW_ROWS = $PreviewRows;
  const global = window;
  const inventory = global.__INVENTARIO__ = global.__INVENTARIO__ || {};
  const previousSetData = typeof inventory.setData === 'function' ? inventory.setData.bind(inventory) : null;
  const state = {
    rows: [],
    meta: null,
    sortKey: null,
    sortDir: 1,
    filters: {}
  };
  const columns = [
    { key: 'Drive', label: 'Drive', sources: ['Drive', 'Unidad'] },
    { key: 'Folder', label: 'Folder', sources: ['Folder', 'Directory', 'Carpeta'] },
    { key: 'Name', label: 'Name', sources: ['Name', 'FileName', 'Nombre'] },
    { key: 'Ext', label: 'Ext', sources: ['Ext', 'Extension'] },
    { key: 'MB', label: 'MB', sources: ['MB', 'SizeMB', 'Megabytes'] },
    { key: 'Hash', label: 'Hash', sources: ['Hash', 'SHA256', 'Checksum'] },
    { key: 'Path', label: 'Path', sources: ['Path', 'FullPath', 'FullName', 'Location'] }
  ];
  let elements = null;

  function create(tag, className, text) {
    const el = document.createElement(tag);
    if (className) { el.className = className; }
    if (typeof text === 'string') { el.textContent = text; }
    return el;
  }

  function ensureElements() {
    if (elements) { return elements; }
    const existing = document.getElementById('inventory-preview-shim');
    let root = existing;
    if (!root) {
      root = create('section', 'inventory-preview', '');
      root.id = 'inventory-preview-shim';
      const title = create('h2', null, 'Vista previa interactiva');
      const meta = create('div', 'inventory-preview-meta', '');
      meta.id = 'inventory-preview-meta';
      const actions = create('div', 'inventory-preview-actions', '');
      const exportBtn = create('button', null, 'Exportar CSV (filtro)');
      exportBtn.type = 'button';
      exportBtn.id = 'inventory-preview-export';
      actions.appendChild(exportBtn);
      const header = create('div', 'inventory-preview-header', '');
      header.appendChild(title);
      header.appendChild(actions);
      root.appendChild(header);
      root.appendChild(meta);
      const filters = create('div', 'inventory-preview-filters', '');
      filters.id = 'inventory-preview-filters';
      root.appendChild(filters);
      const tableWrapper = create('div', 'inventory-preview-table-wrapper', '');
      const table = document.createElement('table');
      table.id = 'inventory-preview-table';
      const thead = document.createElement('thead');
      const tbody = document.createElement('tbody');
      table.appendChild(thead);
      table.appendChild(tbody);
      tableWrapper.appendChild(table);
      root.appendChild(tableWrapper);
      const empty = create('p', 'inventory-preview-empty', 'Sin resultados');
      empty.id = 'inventory-preview-empty';
      const more = create('p', 'inventory-preview-more', '');
      more.id = 'inventory-preview-more';
      root.appendChild(empty);
      root.appendChild(more);
      document.body.appendChild(root);
    }
    const metaEl = document.getElementById('inventory-preview-meta');
    const filtersEl = document.getElementById('inventory-preview-filters');
    const tableEl = document.getElementById('inventory-preview-table');
    const exportBtnEl = document.getElementById('inventory-preview-export');
    elements = {
      root,
      metaEl,
      filtersEl,
      tableEl,
      thead: tableEl ? tableEl.querySelector('thead') : null,
      tbody: tableEl ? tableEl.querySelector('tbody') : null,
      empty: document.getElementById('inventory-preview-empty'),
      more: document.getElementById('inventory-preview-more'),
      exportBtn: exportBtnEl
    };
    return elements;
  }

  function normalizeValue(value) {
    if (value === null || typeof value === 'undefined') { return ''; }
    if (typeof value === 'number') { return value; }
    return String(value);
  }

  function getValue(row, sources, fallbackKey) {
    if (!row || typeof row !== 'object') { return ''; }
    for (let index = 0; index < sources.length; index++) {
      const key = sources[index];
      if (Object.prototype.hasOwnProperty.call(row, key)) {
        const value = row[key];
        if (value !== null && typeof value !== 'undefined') { return value; }
      }
    }
    if (fallbackKey && Object.prototype.hasOwnProperty.call(row, fallbackKey)) {
      const value = row[fallbackKey];
      if (value !== null && typeof value !== 'undefined') { return value; }
    }
    return '';
  }

  function cloneRow(row) {
    if (!row || typeof row !== 'object') { return {}; }
    const copy = {};
    Object.keys(row).forEach(function(key) { copy[key] = row[key]; });
    return copy;
  }

  function buildDriveMap(rows) {
    const map = {};
    rows.forEach(function(row) {
      let drive = '';
      if (row && row.Drive) {
        drive = String(row.Drive).trim();
      }
      if (!drive && row && row.Path && /^[A-Za-z]:/.test(row.Path)) {
        drive = row.Path.substring(0, 1);
      }
      if (!drive && row && row.FullPath && /^[A-Za-z]:/.test(row.FullPath)) {
        drive = row.FullPath.substring(0, 1);
      }
      if (!drive) { return; }
      const key = drive.substring(0, 1).toUpperCase();
      if (!map[key]) { map[key] = 0; }
      map[key]++;
    });
    ['H', 'I', 'J'].forEach(function(letter) {
      if (!map[letter]) { map[letter] = 0; }
    });
    return map;
  }

  function buildSummary(rows, driveCounts) {
    const parts = [];
    parts.push('Total: ' + rows.length);
    ['H', 'I', 'J'].forEach(function(letter) {
      if (Object.prototype.hasOwnProperty.call(driveCounts, letter)) {
        parts.push(letter + ': ' + driveCounts[letter] + ' files');
      }
    });
    Object.keys(driveCounts).filter(function(key) {
      return ['H', 'I', 'J'].indexOf(key) === -1;
    }).sort().forEach(function(key) {
      parts.push(key + ': ' + driveCounts[key] + ' files');
    });
    return parts.join(' | ');
  }

  function normalizeMeta(meta, rows) {
    const drives = buildDriveMap(rows);
    const payload = { summary: '', total: rows.length, drives: {} };
    Object.keys(drives).forEach(function(key) { payload.drives[key] = drives[key]; });
    if (meta && typeof meta === 'object') {
      if (typeof meta.summary === 'string' && meta.summary.trim()) {
        payload.summary = meta.summary.trim();
      }
      if (typeof meta.total === 'number' && !Number.isNaN(meta.total)) {
        payload.total = meta.total;
      }
      if (meta.drives && typeof meta.drives === 'object') {
        Object.keys(meta.drives).forEach(function(key) {
          payload.drives[String(key).toUpperCase()] = Number(meta.drives[key]) || 0;
        });
      }
    } else if (typeof meta === 'string' && meta.trim()) {
      payload.summary = meta.trim();
    }
    if (!payload.summary) {
      payload.summary = buildSummary(rows, payload.drives);
    }
    return payload;
  }

  function normalizeRows(rows) {
    const normalized = [];
    rows.forEach(function(row) {
      if (!row || typeof row !== 'object') { return; }
      const copy = cloneRow(row);
      columns.forEach(function(column) {
        const value = getValue(copy, column.sources, column.key);
        if (value !== '') {
          copy[column.key] = value;
        }
      });
      if (!copy.Path && copy.FullPath) { copy.Path = copy.FullPath; }
      normalized.push(copy);
    });
    return normalized;
  }

  function applyFilters(rows) {
    const filters = state.filters;
    const keys = Object.keys(filters).filter(function(key) {
      return filters[key];
    });
    if (!keys.length) { return rows.slice(); }
    return rows.filter(function(row) {
      return keys.every(function(key) {
        const value = row && row[key] !== undefined ? row[key] : row && row[key.toLowerCase()];
        const text = normalizeValue(value).toString().toLowerCase();
        return text.indexOf(filters[key]) !== -1;
      });
    });
  }

  function sortRows(rows) {
    if (!state.sortKey) { return rows.slice(); }
    const dir = state.sortDir;
    const key = state.sortKey;
    return rows.slice().sort(function(a, b) {
      const left = normalizeValue(a ? a[key] : '');
      const right = normalizeValue(b ? b[key] : '');
      if (typeof left === 'number' && typeof right === 'number') {
        return (left - right) * dir;
      }
      return left.toString().localeCompare(right.toString(), undefined, { numeric: true }) * dir;
    });
  }

  function renderTable() {
    const refs = ensureElements();
    if (!refs.thead || !refs.tbody) { return; }
    if (!refs.thead.hasChildNodes()) {
      const headerRow = document.createElement('tr');
      columns.forEach(function(column) {
        const th = document.createElement('th');
        th.textContent = column.label;
        th.dataset.key = column.key;
        th.addEventListener('click', function() {
          if (state.sortKey === column.key) {
            state.sortDir = state.sortDir * -1;
          } else {
            state.sortKey = column.key;
            state.sortDir = 1;
          }
          render();
        });
        headerRow.appendChild(th);
      });
      refs.thead.appendChild(headerRow);
    }
    Array.from(refs.thead.querySelectorAll('th')).forEach(function(th) {
      th.classList.remove('sort-asc', 'sort-desc');
      if (th.dataset.key === state.sortKey) {
        th.classList.add(state.sortDir === 1 ? 'sort-asc' : 'sort-desc');
      }
    });
  }

  function renderFilters() {
    const refs = ensureElements();
    if (!refs.filtersEl) { return; }
    if (refs.filtersEl.dataset.initialized === '1') { return; }
    refs.filtersEl.innerHTML = '';
    columns.forEach(function(column) {
      const label = create('label', null, column.label);
      const input = document.createElement('input');
      input.type = 'search';
      input.placeholder = 'Contiene...';
      input.dataset.key = column.key;
      input.addEventListener('input', function(event) {
        const value = event.target.value.trim().toLowerCase();
        if (value) {
          state.filters[column.key] = value;
        } else {
          delete state.filters[column.key];
        }
        render();
      });
      label.appendChild(input);
      refs.filtersEl.appendChild(label);
    });
    refs.filtersEl.dataset.initialized = '1';
  }

  function exportCsv(rows) {
    if (!rows.length) { return; }
    const header = columns.map(function(column) { return '"' + column.label.replace('"', '""') + '"'; }).join(',');
    const body = rows.map(function(row) {
      return columns.map(function(column) {
        const value = normalizeValue(row[column.key]);
        return '"' + value.toString().replace(/"/g, '""') + '"';
      }).join(',');
    });
    const csv = [header].concat(body).join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'inventario_preview.csv';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  function render() {
    const refs = ensureElements();
    renderTable();
    renderFilters();
    const filtered = applyFilters(state.rows);
    const sorted = sortRows(filtered);
    const visible = sorted.slice(0, MAX_PREVIEW_ROWS);
    if (refs.tbody) {
      refs.tbody.innerHTML = '';
      visible.forEach(function(row) {
        const tr = document.createElement('tr');
        columns.forEach(function(column) {
          const td = document.createElement('td');
          const value = normalizeValue(row[column.key]);
          if (column.key === 'MB' && typeof value === 'number') {
            td.textContent = value.toFixed(2);
          } else {
            td.textContent = value;
          }
          tr.appendChild(td);
        });
        refs.tbody.appendChild(tr);
      });
    }
    if (refs.metaEl) {
      if (state.meta && state.meta.summary) {
        refs.metaEl.textContent = state.meta.summary;
      } else {
        const drives = buildDriveMap(state.rows);
        refs.metaEl.textContent = buildSummary(state.rows, drives);
      }
    }
    if (refs.empty) {
      refs.empty.style.display = sorted.length ? 'none' : 'block';
    }
    if (refs.more) {
      if (sorted.length > visible.length) {
        refs.more.textContent = 'Mostrando ' + visible.length + ' de ' + sorted.length + ' filas filtradas.';
      } else {
        refs.more.textContent = sorted.length ? 'Filas mostradas: ' + visible.length : '';
      }
    }
    if (refs.exportBtn) {
      refs.exportBtn.disabled = !sorted.length;
      refs.exportBtn.onclick = function() { exportCsv(sorted); };
    }
  }

  inventory.setData = function(rows, meta) {
    const baseRows = previousSetData ? previousSetData(rows, meta) : rows;
    const safeRows = Array.isArray(baseRows) ? baseRows : (Array.isArray(rows) ? rows : []);
    const normalized = normalizeRows(safeRows);
    state.rows = normalized;
    state.meta = normalizeMeta(meta, normalized);
    global.__DATA__ = normalized;
    global.__META__ = state.meta;
    render();
    return baseRows;
  };

  inventory.getPreviewState = function() {
    return {
      rows: state.rows.slice(),
      meta: state.meta,
      sortKey: state.sortKey,
      sortDir: state.sortDir,
      filters: Object.assign({}, state.filters)
    };
  };

  ensureElements();
  renderTable();
  renderFilters();
  render();
})();
</script>
<script id="inventory-preview-data">
window.__INVENTARIO__ = window.__INVENTARIO__ || {};
if (typeof window.__INVENTARIO__.setData === 'function') {
  window.__INVENTARIO__.setData($dataJson,$metaJson);
} else {
  window.__DATA__ = $dataJson;
  window.__META__ = $metaJson;
}
</script>
"@

$injection = $styleBlock + $scriptBlock
if ($html -match '</body>\s*</html>') {
  $html = [regex]::Replace($html, '</body>\s*</html>\s*$', $injection + '</body></html>', $ignoreCase -bor $singleLine)
} else {
  $html += "`n" + $injection
}

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: Normalizado inventario ($($rows.Count) filas)"
