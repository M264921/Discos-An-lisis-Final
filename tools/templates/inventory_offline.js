(function(){
  'use strict';

  function safeJson(node, fallback) {
    if (!node) { return fallback; }
    try {
      var text = node.textContent || node.innerText || '';
      if (!text) { return fallback; }
      var parsed = JSON.parse(text);
      return parsed === null ? fallback : parsed;
    } catch (error) {
      return fallback;
    }
  }

  function normalizeText(value) {
    if (!value) { return ''; }
    return String(value).toLowerCase();
  }

  function normalizeDrive(value) {
    if (!value) { return ''; }
    return String(value).trim().substring(0, 1).toUpperCase();
  }

  function formatDate(value) {
    if (!value) { return ''; }
    var date = new Date(value);
    if (isNaN(date.getTime())) { return ''; }
    return date.toLocaleString('es-ES', { dateStyle: 'short', timeStyle: 'short' });
  }

  function parseDate(value) {
    if (!value) { return -1; }
    var time = Date.parse(value);
    return isNaN(time) ? -1 : time;
  }

  function formatBytes(bytes) {
    var units = ['B','KB','MB','GB','TB','PB'];
    if (!isFinite(bytes)) { return '0 B'; }
    var size = bytes;
    var unit = units[0];
    for (var i = 0; i < units.length; i++) {
      unit = units[i];
      if (Math.abs(size) < 1024 || i === units.length - 1) { break; }
      size = size / 1024;
    }
    var display = Math.abs(size) >= 10 ? Math.round(size) : sizeFormatter.format(size);
    return display + ' ' + unit;
  }

  function capitalize(text) {
    if (!text) { return ''; }
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  function escapeHtml(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function encodeAttr(value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;');
  }

  function csvEscape(value) {
    var text = value == null ? '' : String(value);
    if (/[",\r\n]/.test(text)) {
      return '"' + text.replace(/"/g, '""') + '"';
    }
    return text;
  }

  var metaNode = document.getElementById('inventory-meta');
  var dataNode = document.getElementById('inventory-data');
  var dataset = safeJson(dataNode, []);
  var meta = safeJson(metaNode, {});
  if (!Array.isArray(dataset)) { dataset = []; }
  if (typeof meta !== 'object' || meta === null) { meta = {}; }

  var numberFormatter = new Intl.NumberFormat('es-ES');
  var sizeFormatter = new Intl.NumberFormat('es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  function prepareRow(row) {
    var safe = {
      sha: row && row.sha ? String(row.sha) : '',
      type: row && row.type ? String(row.type) : 'otro',
      name: row && row.name ? String(row.name) : '',
      path: row && row.path ? String(row.path) : '',
      drive: row && row.drive ? String(row.drive) : '',
      size: Number(row && row.size ? row.size : 0),
      last: row && row.last ? String(row.last) : ''
    };
    var driveUpper = normalizeDrive(safe.drive);
    var typeLower = normalizeText(safe.type);
    var lastLabel = formatDate(safe.last);
    return {
      sha: safe.sha,
      type: typeLower || 'otro',
      name: safe.name,
      path: safe.path,
      drive: driveUpper,
      size: safe.size,
      last: safe.last,
      _drive: driveUpper,
      _driveLower: driveUpper.toLowerCase(),
      _type: typeLower || 'otro',
      _nameLower: normalizeText(safe.name),
      _pathLower: normalizeText(safe.path),
      _shaLower: normalizeText(safe.sha),
      _search: normalizeText(safe.name + ' ' + safe.path + ' ' + safe.sha),
      _size: isFinite(safe.size) ? safe.size : 0,
      _lastLabel: lastLabel,
      _lastLower: normalizeText(lastLabel),
      _lastStamp: parseDate(safe.last)
    };
  }

  var state = {
    rows: dataset.map(prepareRow),
    search: '',
    columnFilters: {},
    activeDrives: new Set(),
    activeTypes: new Set(),
    sort: { key: 'name', direction: 'asc' },
    filtered: []
  };

  var refs = {
    generated: document.getElementById('generated-at'),
    driveChips: document.getElementById('drive-chips'),
    typeChips: document.getElementById('type-chips'),
    search: document.getElementById('global-search'),
    reset: document.getElementById('reset-filters'),
    exportBtn: document.getElementById('export-csv'),
    statCount: document.getElementById('stat-count'),
    statTotal: document.getElementById('stat-total'),
    statSize: document.getElementById('stat-size'),
    statSizeTotal: document.getElementById('stat-size-total'),
    statDriveList: document.getElementById('stat-drive'),
    tableBody: document.querySelector('#inventory-table tbody'),
    headers: Array.from(document.querySelectorAll('#inventory-table thead th.sortable')),
    emptyState: document.getElementById('empty-state')
  };

  var filterInputs = Array.from(document.querySelectorAll('[data-filter]'));
  filterInputs.forEach(function(input){
    state.columnFilters[input.dataset.filter] = '';
  });

  if (refs.generated && meta.generatedAt) {
    refs.generated.textContent = 'Generado: ' + formatDate(meta.generatedAt);
  }

  buildChipGroup(refs.driveChips, collectUnique(state.rows, '_drive'), state.activeDrives, meta.driveCounts || {});
  buildChipGroup(refs.typeChips, collectUnique(state.rows, '_type'), state.activeTypes, meta.typeCounts || {});

  if (refs.search) {
    refs.search.addEventListener('input', function(){
      state.search = normalizeText(refs.search.value);
      scheduleRender(false);
    });
  }

  filterInputs.forEach(function(input){
    input.addEventListener('input', function(){
      var key = input.dataset.filter;
      if (key === 'size') {
        state.columnFilters.size = input.value.trim();
      } else {
        state.columnFilters[key] = normalizeText(input.value);
      }
      scheduleRender(false);
    });
  });

  refs.headers.forEach(function(header){
    header.addEventListener('click', function(){
      var key = header.getAttribute('data-sort');
      if (!key) { return; }
      if (state.sort.key === key) {
        state.sort.direction = state.sort.direction === 'asc' ? 'desc' : 'asc';
      } else {
        state.sort.key = key;
        state.sort.direction = (key === 'size' || key === 'last') ? 'desc' : 'asc';
      }
      scheduleRender(true);
    });
  });

  if (refs.reset) {
    refs.reset.addEventListener('click', function(){
      state.search = '';
      if (refs.search) { refs.search.value = ''; }
      state.activeDrives.clear();
      state.activeTypes.clear();
      Object.keys(state.columnFilters).forEach(function(key){ state.columnFilters[key] = ''; });
      filterInputs.forEach(function(input){ input.value = ''; });
      state.sort = { key: 'name', direction: 'asc' };
      syncChipSelection(refs.driveChips, state.activeDrives);
      syncChipSelection(refs.typeChips, state.activeTypes);
      scheduleRender(true);
    });
  }

  if (refs.exportBtn) {
    refs.exportBtn.addEventListener('click', function(){
      if (!state.filtered.length) { return; }
      exportCsv(state.filtered);
    });
  }

  if (refs.tableBody) {
    refs.tableBody.addEventListener('click', function(event){
      var target = event.target.closest('button[data-action]');
      if (!target) { return; }
      var action = target.dataset.action;
      var path = target.dataset.path;
      if (!path) { return; }
      if (action === 'open') {
        openInExplorer(path);
      } else if (action === 'copy') {
        copyToClipboard(path);
      }
    });
  }

  var renderPending = false;
  function scheduleRender(forceSort) {
    if (forceSort) {
      updateSortIndicators();
    }
    if (renderPending) { return; }
    renderPending = true;
    requestAnimationFrame(function(){
      renderPending = false;
      applyFilters();
    });
  }

  function collectUnique(rows, key) {
    var seen = new Set();
    rows.forEach(function(row){
      var value = row[key];
      if (value) { seen.add(value); }
    });
    return Array.from(seen).sort();
  }

  function buildChipGroup(container, values, targetSet, counts) {
    if (!container) { return; }
    container.innerHTML = '';
    var fragment = document.createDocumentFragment();
    var allChip = createChip('Todos', '__all__', true);
    allChip.addEventListener('click', function(){
      targetSet.clear();
      syncChipSelection(container, targetSet);
      scheduleRender(false);
    });
    fragment.appendChild(allChip);
    var mode = container.dataset.chip || '';
    values.forEach(function(value){
      var label = mode === 'type' ? capitalize(value) : value;
      var countKey = mode === 'type' ? value : value;
      var labelCount = counts && counts[countKey] ? numberFormatter.format(counts[countKey]) : '';
      var text = labelCount ? label + ' (' + labelCount + ')' : label;
      var chip = createChip(text, value, false);
      chip.addEventListener('click', function(){
        if (targetSet.has(value)) {
          targetSet.delete(value);
        } else {
          targetSet.add(value);
        }
        syncChipSelection(container, targetSet);
        scheduleRender(false);
      });
      fragment.appendChild(chip);
    });
    container.appendChild(fragment);
    syncChipSelection(container, targetSet);
  }

  function createChip(label, value, isAll) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'chip';
    button.dataset.value = value;
    if (isAll) {
      button.dataset.role = 'all';
    }
    button.textContent = label;
    return button;
  }

  function syncChipSelection(container, targetSet) {
    if (!container) { return; }
    var chips = container.querySelectorAll('.chip');
    var hasSelection = targetSet.size > 0;
    chips.forEach(function(chip){
      var isAll = chip.dataset.role === 'all';
      if (isAll) {
        chip.classList.toggle('is-active', !hasSelection);
      } else {
        chip.classList.toggle('is-active', targetSet.has(chip.dataset.value));
      }
    });
  }

  
function parseSizeFilter(value) {
  if (!value) { return null; }
  var text = value.trim().toLowerCase();
  if (!text) { return null; }
  var match = text.match(/^(>=|<=|>|<)?\s*([0-9]+(?:[.,][0-9]+)?)\s*(b|kb|mb|gb|tb|pb)?$/);
  if (!match) { return text; }
  var op = match[1] || '>=';
  var rawNumber = match[2].replace(',', '.');
  var amount = parseFloat(rawNumber);
  if (!isFinite(amount)) { return text; }
  var unit = match[3] || 'b';
  var scaleMap = { b:1, kb:1024, mb:1024*1024, gb:Math.pow(1024,3), tb:Math.pow(1024,4), pb:Math.pow(1024,5) };
  var multiplier = scaleMap[unit] || 1;
  return { operator: op, target: amount * multiplier };
}

function evaluateSizeFilter(size, filter) {
  if (typeof filter === 'string') {
    return formatBytes(size).toLowerCase().indexOf(filter) !== -1;
  }
  switch (filter.operator) {
    case '>': return size > filter.target;
    case '>=': return size >= filter.target;
    case '<': return size < filter.target;
    case '<=': return size <= filter.target;
    default: return size >= filter.target;
  }
}

function applyFilters() {
  var searchTokens = state.search ? state.search.split(/\s+/).filter(Boolean) : [];
  var sizeFilter = parseSizeFilter(state.columnFilters.size || '');
  var results = [];
  state.rows.forEach(function(row){
    if (state.activeDrives.size && !state.activeDrives.has(row._drive)) { return; }
    if (state.activeTypes.size && !state.activeTypes.has(row._type)) { return; }
    var matches = true;
    for (var i = 0; i < searchTokens.length; i++) {
      if (row._search.indexOf(searchTokens[i]) === -1) {
        matches = false;
        break;
      }
    }
    if (!matches) { return; }
    if (state.columnFilters.name && row._nameLower.indexOf(state.columnFilters.name) === -1) { return; }
    if (state.columnFilters.drive && row._driveLower.indexOf(state.columnFilters.drive) === -1) { return; }
    if (state.columnFilters.type && row._type.indexOf(state.columnFilters.type) === -1) { return; }
    if (state.columnFilters.path && row._pathLower.indexOf(state.columnFilters.path) === -1) { return; }
    if (state.columnFilters.sha && row._shaLower.indexOf(state.columnFilters.sha) === -1) { return; }
    if (state.columnFilters.last && row._lastLower.indexOf(state.columnFilters.last) === -1) { return; }
    if (sizeFilter && !evaluateSizeFilter(row._size, sizeFilter)) { return; }
    results.push(row);
  });
  var comparator = buildComparator(state.sort.key, state.sort.direction);
  results.sort(comparator);
  state.filtered = results;
  renderTable(results);
  updateStats(results);
  updateSortIndicators();
  if (refs.exportBtn) {
    refs.exportBtn.disabled = results.length === 0;
  }
  if (refs.emptyState) {
    refs.emptyState.hidden = results.length > 0;
  }
}

function buildComparator(key, direction) {
  var factor = direction === 'desc' ? -1 : 1;
  return function(a, b){
    var result = 0;
    switch (key) {
      case 'drive':
        result = a._drive.localeCompare(b._drive);
        break;
      case 'type':
        result = a._type.localeCompare(b._type);
        break;
      case 'size':
        result = a._size - b._size;
        break;
      case 'last':
        result = a._lastStamp - b._lastStamp;
        break;
      case 'sha':
        result = a._shaLower.localeCompare(b._shaLower);
        break;
      case 'path':
        result = a._pathLower.localeCompare(b._pathLower);
        break;
      default:
        result = a._nameLower.localeCompare(b._nameLower);
        break;
    }
    if (result === 0 && key !== 'path') {
      result = a._pathLower.localeCompare(b._pathLower);
    }
    return result * factor;
  };
}

function renderTable(rows) {
  if (!refs.tableBody) { return; }
  refs.tableBody.textContent = '';
  var fragment = document.createDocumentFragment();
  rows.forEach(function(row){
    var tr = document.createElement('tr');
    var sizeText = formatBytes(row._size);
    tr.innerHTML = [
      '<td><div class="cell-primary"><span class="file-name">' + escapeHtml(row.name) + '</span></div></td>',
      '<td><span class="pill">' + escapeHtml(row._drive || '-') + '</span></td>',
      '<td><span class="pill pill-muted">' + escapeHtml(capitalize(row.type)) + '</span></td>',
      '<td class="numeric">' + escapeHtml(sizeText) + '</td>',
      '<td>' + escapeHtml(row._lastLabel || '') + '</td>',
      '<td class="mono">' + escapeHtml(row.sha) + '</td>',
      '<td class="mono truncate" title="' + escapeHtml(row.path) + '">' + escapeHtml(row.path) + '</td>',
      '<td class="actions"><button type="button" class="btn-icon" data-action="open" data-path="' + encodeAttr(row.path) + '" title="Abrir en el explorador">Abrir</button><button type="button" class="btn-icon" data-action="copy" data-path="' + encodeAttr(row.path) + '" title="Copiar ruta">Copiar</button></td>'
    ].join('');
    fragment.appendChild(tr);
  });
  refs.tableBody.appendChild(fragment);
}

function updateStats(rows) {
  var visibleCount = rows.length;
  var visibleBytes = rows.reduce(function(sum, row){ return sum + row._size; }, 0);
  if (refs.statCount) {
    refs.statCount.textContent = numberFormatter.format(visibleCount);
  }
  if (refs.statTotal) {
    refs.statTotal.textContent = 'de ' + numberFormatter.format(state.rows.length) + ' archivos';
  }
  if (refs.statSize) {
    refs.statSize.textContent = formatBytes(visibleBytes);
  }
  if (refs.statSizeTotal) {
    var totalBytes = typeof meta.totalBytes === 'number'
      ? meta.totalBytes
      : state.rows.reduce(function(sum, row){ return sum + row._size; }, 0);
    refs.statSizeTotal.textContent = 'total ' + formatBytes(totalBytes);
  }
  if (refs.statDriveList) {
    var list = document.createDocumentFragment();
    if (!rows.length) {
      var emptyItem = document.createElement('li');
      emptyItem.textContent = 'Sin coincidencias';
      list.appendChild(emptyItem);
    } else {
      var stats = {};
      rows.forEach(function(row){
        var key = row._drive || 'N/A';
        if (!stats[key]) {
          stats[key] = { count: 0, bytes: 0 };
        }
        stats[key].count += 1;
        stats[key].bytes += row._size;
      });
      Object.keys(stats).sort().forEach(function(key){
        var entry = document.createElement('li');
        entry.innerHTML = '<span class="pill">' + escapeHtml(key) + '</span><span>' + numberFormatter.format(stats[key].count) + ' archivos</span><span>' + formatBytes(stats[key].bytes) + '</span>';
        list.appendChild(entry);
      });
    }
    refs.statDriveList.innerHTML = '';
    refs.statDriveList.appendChild(list);
  }
}

function updateSortIndicators() {
  refs.headers.forEach(function(header){
    var key = header.getAttribute('data-sort');
    var active = state.sort.key === key;
    header.classList.toggle('is-sorted', active);
    if (active) {
      header.setAttribute('data-sort-state', state.sort.direction);
    } else {
      header.removeAttribute('data-sort-state');
    }
  });
}

function openInExplorer(path) {
  var normalized = path.replace(/\\/g, '/');
  var url = 'file:///' + normalized.replace(/^([A-Za-z]):/, '$1:');
  window.open(url, '_blank');
}

function copyToClipboard(text) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).catch(function(){ fallbackCopy(text); });
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  var area = document.createElement('textarea');
  area.value = text;
  document.body.appendChild(area);
  area.select();
  try {
    document.execCommand('copy');
  } catch (error) {
    window.prompt('Copiar ruta', text);
  }
  document.body.removeChild(area);
}

function exportCsv(rows) {
  var headers = ['name','path','drive','type','size','last','sha'];
  var lines = [headers.join(',')];
  rows.forEach(function(row){
    lines.push([
      csvEscape(row.name),
      csvEscape(row.path),
      csvEscape(row._drive),
      csvEscape(row.type),
      csvEscape(String(row._size)),
      csvEscape(row.last || ''),
      csvEscape(row.sha)
    ].join(','));
  });
  var blob = new Blob([lines.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
  var url = URL.createObjectURL(blob);
  var stamp = new Date().toISOString().replace(/[-:]/g, '').slice(0, 15);
  var link = document.createElement('a');
  link.href = url;
  link.download = 'inventario_filtrado_' + stamp + '.csv';
  document.body.appendChild(link);
  link.click();
  setTimeout(function(){
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }, 0);
}

scheduleRender(true);
})();
