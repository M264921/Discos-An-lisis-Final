#!/usr/bin/env python3
"""Generate the interactive duplicates explorer from dupes_confirmed.csv."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Tuple
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "dupes_confirmed.csv"
DEFAULT_TARGET = ROOT / "Listado_Duplicados_interactivo.html"

VIDEO_EXT = {
    ".mp4",
    ".m2ts",
    ".avi",
    ".mov",
    ".mpg",
    ".mpeg",
    ".mts",
    ".wmv",
    ".m4v",
    ".mkv",
    ".flv",
    ".ts",
    ".webm",
}
PHOTO_EXT = {
    ".jpg",
    ".jpeg",
    ".png",
    ".gif",
    ".heic",
    ".tif",
    ".tiff",
    ".bmp",
    ".raw",
    ".nef",
    ".cr2",
    ".cr3",
    ".arw",
    ".psd",
    ".svg",
    ".webp",
    ".ai",
}
AUDIO_EXT = {
    ".mp3",
    ".wav",
    ".flac",
    ".aac",
    ".m4a",
    ".ogg",
    ".wma",
    ".aiff",
    ".aif",
    ".mid",
    ".midi",
}
DOC_EXT = {
    ".pdf",
    ".doc",
    ".docx",
    ".xls",
    ".xlsx",
    ".ppt",
    ".pptx",
    ".txt",
    ".csv",
    ".rtf",
    ".odt",
    ".ods",
    ".odp",
    ".md",
    ".html",
}
ICON_MAP = {
    "video": "🎬",
    "foto": "🖼️",
    "audio": "🎧",
    "documento": "📄",
    "otro": "📦",
}


class DuplicateExplorerError(RuntimeError):
    """Custom error for controlled failures."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help="CSV con las columnas Hash, Path, Bytes, LastWrite (por defecto dupes_confirmed.csv)",
    )
    parser.add_argument(
        "--target",
        type=Path,
        default=DEFAULT_TARGET,
        help="HTML de salida (por defecto Listado_Duplicados_interactivo.html)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="No imprimir resumen al terminar",
    )
    return parser.parse_args()


def classify(ext: str) -> Tuple[str, str]:
    ext = ext.lower()
    if ext in VIDEO_EXT:
        return "video", ICON_MAP["video"]
    if ext in PHOTO_EXT:
        return "foto", ICON_MAP["foto"]
    if ext in AUDIO_EXT:
        return "audio", ICON_MAP["audio"]
    if ext in DOC_EXT:
        return "documento", ICON_MAP["documento"]
    return "otro", ICON_MAP["otro"]


def human_size(value: int) -> str:
    amount = float(value)
    suffixes = ["B", "KB", "MB", "GB", "TB", "PB"]
    for idx, unit in enumerate(suffixes):
        is_last = idx == len(suffixes) - 1
        if amount < 1024 or is_last:
            if unit == "B":
                return f"{int(amount)} {unit}"
            return f"{spanish_decimal(amount, 1)} {unit}"
        amount /= 1024
    return f"{spanish_decimal(amount, 1)} PB"


def spanish_decimal(value: float, ndigits: int = 1) -> str:
    formatted = f"{value:,.{ndigits}f}"
    formatted = formatted.replace(",", "@").replace(".", ",").replace("@", ".")
    if formatted.endswith(",0"):
        formatted = formatted[:-2]
    return formatted


def clean_int(raw: str) -> int:
    raw = (raw or "").strip().replace("\"", "").replace(",", "")
    try:
        return int(float(raw))
    except ValueError:
        return 0


def file_uri(path: str) -> str:
    if ":" not in path:
        return ""
    drive, remainder = path.split(":", 1)
    remainder = remainder.replace("\\", "/")
    return f"file:///{drive}:{quote(remainder)}"


def load_groups(csv_path: Path) -> List[Dict[str, object]]:
    if not csv_path.exists():
        raise DuplicateExplorerError(f"No se encuentra el CSV: {csv_path}")

    with csv_path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        if not reader.fieldnames:
            return []

        lookup = {name.lstrip("\ufeff").lower(): name for name in reader.fieldnames}
        hash_key = lookup.get("hash")
        path_key = lookup.get("path")
        bytes_key = next((lookup[name] for name in lookup if "bytes" in name), None)
        last_key = next((lookup[name] for name in lookup if "last" in name), None)
        if not hash_key or not path_key:
            raise DuplicateExplorerError("El CSV debe incluir las columnas Hash y Path")

        grouped: Dict[str, List[Dict[str, object]]] = defaultdict(list)
        for row in reader:
            sha = (row.get(hash_key) or "").strip()
            raw_path = (row.get(path_key) or "").strip()
            if not sha or not raw_path:
                continue
            path = raw_path.replace("\\\\", "\\")
            drive = path.split(":", 1)[0] if ":" in path else "-"
            name = path.split("\\")[-1]
            ext = f".{name.split('.')[-1]}" if "." in name else ""
            size = clean_int(row.get(bytes_key) or "0") if bytes_key else 0
            last = (row.get(last_key) or "").strip() if last_key else ""
            category, icon = classify(ext)
            entry = {
                "sha": sha,
                "path": path,
                "name": name,
                "drive": drive,
                "bytes": size,
                "sizeLabel": human_size(size),
                "lastWrite": last,
                "category": category,
                "icon": icon,
                "openUri": file_uri(path),
            }
            grouped[sha].append(entry)

    priority = {"H": 0, "I": 1, "J": 2}
    groups: List[Dict[str, object]] = []
    for sha, entries in grouped.items():
        entries.sort(key=lambda item: (priority.get(item["drive"], 9), item["path"].lower()))
        for idx, entry in enumerate(entries):
            entry["role"] = "Principal" if idx == 0 else "Duplicado"
        drives = sorted({entry["drive"] for entry in entries})
        total = sum(entry["bytes"] for entry in entries)
        groups.append(
            {
                "group": 0,
                "sha": sha,
                "count": len(entries),
                "drives": drives,
                "multiDrive": len(drives) > 1,
                "totalBytes": total,
                "totalLabel": human_size(total),
                "entries": entries,
            }
        )

    groups.sort(key=lambda item: (-item["count"], -item["totalBytes"], item["sha"]))
    for idx, group in enumerate(groups, start=1):
        group["group"] = idx
    return groups


def build_payload(groups: List[Dict[str, object]]) -> Dict[str, object]:
    items = sum(len(group["entries"]) for group in groups)
    total_bytes = sum(group["totalBytes"] for group in groups)
    summary = {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "groups": len(groups),
        "items": items,
        "bytes": total_bytes,
        "bytesLabel": human_size(total_bytes),
    }
    return {"summary": summary, "groups": groups}


def build_html(payload: Dict[str, object]) -> str:
    summary = payload["summary"]
    json_blob = json.dumps(payload, ensure_ascii=False)
    safe_blob = json_blob.replace("</", "<\\/")
    html = HTML_TEMPLATE
    replacements = {
        "__GENERATED__": summary["generated"],
        "__GROUP_COUNT__": f"{summary['groups']}",
        "__ITEM_COUNT__": f"{summary['items']}",
        "__BYTES_LABEL__": summary["bytesLabel"],
        "__PAYLOAD__": safe_blob,
    }
    for key, value in replacements.items():
        html = html.replace(key, value)
    # The HTML template keeps double braces so that Python's formatter does not
    # treat them as placeholders. Once the real values have been injected we
    # normalise them back to single braces for valid CSS/JS output.
    html = html.replace("{{", "{").replace("}}", "}")
    return html


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8" />
<title>Duplicados interactivos HIJ</title>
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
:root {{
  color-scheme: light;
}}
* {{
  box-sizing: border-box;
}}
body {{
  margin: 18px;
  font-family: 'Segoe UI', Roboto, Arial, sans-serif;
  background: #f7f9fc;
  color: #0f172a;
}}
h1 {{
  margin: 0;
  font-size: 26px;
  color: #0b2545;
}}
p.summary {{
  margin: 6px 0 20px;
  color: #4b5563;
}}
.stats {{
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  margin-bottom: 18px;
}}
.stat-card {{
  background: #fff;
  border: 1px solid #dce3f8;
  border-radius: 12px;
  padding: 14px 16px;
  min-width: 180px;
  box-shadow: 0 12px 30px -24px rgba(15, 23, 42, 0.45);
}}
.stat-card .label {{
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .04em;
  color: #64748b;
}}
.stat-card .value {{
  font-size: 20px;
  font-weight: 700;
  color: #0b2545;
}}
.stat-card .meta {{
  font-size: 12px;
  color: #475569;
  margin-top: 4px;
}}
.toolbar {{
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  align-items: center;
  margin-bottom: 14px;
}}
.toolbar input[type=search] {{
  padding: 8px 10px;
  border: 1px solid #d1d9f5;
  border-radius: 8px;
  min-width: 260px;
}}
.filter-chip {{
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid #cbd5f5;
  background: #fff;
  cursor: pointer;
  font-size: 13px;
}}
.filter-chip[data-active=true] {{
  background: #1d4ed8;
  border-color: #1d4ed8;
  color: #fff;
}}
.toggle {{
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
}}
.legend {{
  background: #fff;
  border: 1px solid #dce3f8;
  border-radius: 12px;
  padding: 14px 16px;
  margin-bottom: 18px;
  box-shadow: 0 18px 36px -30px rgba(15, 23, 42, 0.4);
}}
.legend h2 {{
  margin: 0 0 10px;
  font-size: 16px;
  color: #0b2545;
}}
.legend ul {{
  margin: 0;
  padding-left: 18px;
  color: #475569;
  font-size: 13px;
}}
.legend li {{
  margin-bottom: 6px;
}}
.table-wrap {{
  border: 1px solid #dbe3ff;
  border-radius: 14px;
  background: #fff;
  overflow: hidden;
  box-shadow: 0 20px 44px -32px rgba(15, 23, 42, 0.4);
}}
table {{
  width: 100%;
  border-collapse: collapse;
  min-width: 960px;
}}
th, td {{
  padding: 10px 12px;
  border-bottom: 1px solid #e2e8f0;
  text-align: left;
  font-size: 13px;
}}
th {{
  background: #eef2ff;
  color: #1e3a8a;
  font-weight: 600;
}}
th.sortable {{
  cursor: pointer;
  position: relative;
}}
th.sortable::after {{
  content: '';
  position: absolute;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 10px;
  color: #64748b;
}}
th.sortable[data-direction="asc"]::after {{
  content: '▲';
}}
th.sortable[data-direction="desc"]::after {{
  content: '▼';
}}
tr.group-row {{
  background: #f8faff;
  font-weight: 600;
  cursor: pointer;
}}
tr.group-row:hover {{
  background: #eef4ff;
}}
tr.entry-row:nth-child(odd) {{
  background: #fbfdff;
}}
td.icon {{
  width: 32px;
  text-align: center;
  font-size: 18px;
}}
td.path {{
  font-family: 'Cascadia Code', 'Fira Code', Consolas, monospace;
  font-size: 12px;
}}
td.actions {{
  white-space: nowrap;
  display: flex;
  gap: 6px;
}}
td.actions a,
td.actions button {{
  padding: 6px 10px;
  border-radius: 8px;
  border: 1px solid #cbd5f5;
  background: #f8fafc;
  color: #1d4ed8;
  text-decoration: none;
  cursor: pointer;
  font-size: 12px;
}}
td.actions a:hover,
td.actions button:hover {{
  background: #eef4ff;
}}
tr.column-filters input {{
  width: 100%;
  padding: 6px;
  border: 1px solid #dbe3ff;
  border-radius: 6px;
  font-size: 12px;
}}
tr.column-filters input:focus {{
  outline: none;
  border-color: #1d4ed8;
}}
.badge {{
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  background: #edf2ff;
  color: #1d4ed8;
}}
.badge.multi {{
  background: #fef3c7;
  color: #b45309;
}}
footer {{
  margin: 16px 0 0;
  font-size: 12px;
  color: #64748b;
}}
@media (max-width: 720px) {{
  body {{ margin: 12px; }}
  .toolbar {{ gap: 6px; }}
  .toolbar input[type=search] {{ min-width: 200px; }}
  .table-wrap {{ overflow-x: auto; }}
}}
</style>
</head>
<body>
<h1>Duplicados de los discos H · I · J</h1>
<p class="summary">Generado: __GENERATED__ · __GROUP_COUNT__ grupos · __ITEM_COUNT__ entradas · __BYTES_LABEL__ totales.</p>
<div class="stats">
  <div class="stat-card"><div class="label">Grupos</div><div class="value" id="stat-groups">__GROUP_COUNT__</div><div class="meta">Hashes con más de una copia</div></div>
  <div class="stat-card"><div class="label">Entradas visibles</div><div class="value" id="stat-visible">-</div><div class="meta">Se actualiza con los filtros</div></div>
  <div class="stat-card"><div class="label">Tamaño visible</div><div class="value" id="stat-size">-</div><div class="meta">Suma de duplicados filtrados</div></div>
</div>
<div class="toolbar">
  <input id="search" type="search" placeholder="Filtrar por nombre, carpeta o hash..." />
  <div class="controls">
    <span class="filter-chip" data-drive="H" data-active="true">H:</span>
    <span class="filter-chip" data-drive="I" data-active="true">I:</span>
    <span class="filter-chip" data-drive="J" data-active="true">J:</span>
  </div>
  <div class="controls">
    <label>Tipo:</label>
    <span class="filter-chip" data-type="all" data-active="true">Todos</span>
    <span class="filter-chip" data-type="video">Vídeo</span>
    <span class="filter-chip" data-type="foto">Foto</span>
    <span class="filter-chip" data-type="audio">Audio</span>
    <span class="filter-chip" data-type="documento">Docs</span>
    <span class="filter-chip" data-type="otro">Otros</span>
  </div>
  <label class="toggle"><input type="checkbox" id="multi" /> Solo multi-unidad</label>
  <button id="reset" class="filter-chip">Limpiar filtros</button>
</div>
<div class="legend">
  <h2>Cómo leer las rutas</h2>
  <ul>
    <li><strong>H:\\_quarantine_from_HIJ\\*</strong> — cuarentena común antes de decidir el destino final.</li>
    <li><strong>H:\\offload\\...</strong> — volcados rápidos para liberar espacio sin perder respaldo.</li>
    <li><strong>_quarantine_from_H / _quarantine_from_I</strong> — indican la unidad de origen del fichero.</li>
    <li><code>\\migrated</code> — lotes ya revisados listos para archivar o compartir.</li>
    <li><code>media_final</code> — biblioteca curada; toca moverla sólo tras validarlo con la familia.</li>
  </ul>
</div>
<div class="table-wrap">
  <table>
    <thead>
      <tr>
        <th>#</th>
        <th class="sortable" data-sort="sha">SHA256</th>
        <th class="sortable" data-sort="role">Rol</th>
        <th class="sortable" data-sort="type">Tipo</th>
        <th class="sortable" data-sort="name">Nombre</th>
        <th class="sortable" data-sort="path">Ubicación</th>
        <th class="sortable" data-sort="drive">Unidad</th>
        <th class="sortable" data-sort="size">Tamaño</th>
        <th class="sortable" data-sort="last">Modificado</th>
        <th>Acciones</th>
      </tr>
      <tr class="column-filters">
        <td></td>
        <td><input data-filter="sha" placeholder="Hash..." /></td>
        <td><input data-filter="role" placeholder="Rol..." /></td>
        <td><input data-filter="type" placeholder="Tipo..." /></td>
        <td><input data-filter="name" placeholder="Nombre..." /></td>
        <td><input data-filter="path" placeholder="Carpeta..." /></td>
        <td><input data-filter="drive" placeholder="Unidad..." /></td>
        <td><input data-filter="size" placeholder="Tamaño..." /></td>
        <td><input data-filter="last" placeholder="Fecha..." /></td>
        <td></td>
      </tr>
    </thead>
    <tbody id="results"></tbody>
  </table>
</div>
<footer>Pulsa cada cabecera de grupo para plegar o expandir duplicados. Usa los filtros para decidir qué copia conservar.</footer>
<script id="duplicates-data" type="application/json">__PAYLOAD__</script>
<script>
(() => {{
  const raw = JSON.parse(document.getElementById('duplicates-data').textContent);
  const groups = raw.groups;
  const drives = new Set(['H','I','J']);
  let typeFilter = 'all';
  let searchTerm = '';
  let multiOnly = false;
  const columnFilters = {{ sha:'', role:'', type:'', name:'', path:'', drive:'', size:'', last:'' }};
  const sortConfig = {{ field: null, direction: 'asc' }};

  const searchInput = document.getElementById('search');
  const chips = document.querySelectorAll('.filter-chip[data-drive], .filter-chip[data-type]');
  const multiToggle = document.getElementById('multi');
  const resetBtn = document.getElementById('reset');
  const tbody = document.getElementById('results');
  const statVisible = document.getElementById('stat-visible');
  const statSize = document.getElementById('stat-size');
  const headers = document.querySelectorAll('th[data-sort]');
  const columnInputs = document.querySelectorAll('tr.column-filters input[data-filter]');

  document.getElementById('stat-groups').textContent = groups.length.toLocaleString('es-ES');

  function escapeHtml(value) {{
    return value.replace(/[&<>"']/g, (char) => {{
      switch(char) {{
        case '&': return '&amp;';
        case '<': return '&lt;';
        case '>': return '&gt;';
        case '"': return '&quot;';
        case "'": return '&#39;';
        default: return char;
      }}
    }});
  }}

  function formatBytes(value) {{
    if(!value) return '0 B';
    const units = ['B','KB','MB','GB','TB','PB'];
    let amount = value;
    for(const unit of units) {{
      if(amount < 1024 || unit === units[units.length - 1]) {{
        if(unit === 'B') return `${Math.round(amount)} ${unit}`;
        return new Intl.NumberFormat('es-ES', {{ maximumFractionDigits: 1 }}).format(amount) + ` ${unit}`;
      }}
      amount /= 1024;
    }}
  }}

  function normalise(value) {{
    return (value || '').toString().toLowerCase();
  }}

  function getEntryField(entry, field) {{
    switch(field) {{
      case 'sha': return entry.sha;
      case 'role': return entry.role;
      case 'type': return entry.category;
      case 'name': return entry.name;
      case 'path': return entry.path;
      case 'drive': return entry.drive;
      case 'size': return entry.bytes;
      case 'last': return entry.lastWrite;
      default: return '';
    }}
  }}

  function compareEntries(a, b, field) {{
    if(field === 'size') {{
      return (a.bytes || 0) - (b.bytes || 0);
    }}
    if(field === 'last') {{
      return Date.parse(a.lastWrite || '') - Date.parse(b.lastWrite || '');
    }}
    return normalise(getEntryField(a, field)).localeCompare(normalise(getEntryField(b, field)), 'es');
  }}

  function compareGroups(a, b) {{
    const field = sortConfig.field;
    if(!field) {{
      return a.groupInfo.group - b.groupInfo.group;
    }}
    if(field === 'sha') {{
      return a.groupInfo.sha.localeCompare(b.groupInfo.sha, 'es');
    }}
    const entryA = a.entries[0] || {{}};
    const entryB = b.entries[0] || {{}};
    if(field === 'size') {{
      return (entryA.bytes || 0) - (entryB.bytes || 0);
    }}
    if(field === 'last') {{
      return Date.parse(entryA.lastWrite || '') - Date.parse(entryB.lastWrite || '');
    }}
    return normalise(getEntryField(entryA, field)).localeCompare(normalise(getEntryField(entryB, field)), 'es');
  }}

  function matchesEntry(entry) {{
    if(!drives.has(entry.drive)) return false;
    if(typeFilter !== 'all' && entry.category !== typeFilter) return false;
    if(columnFilters.role && !normalise(entry.role).includes(columnFilters.role)) return false;
    if(columnFilters.type && !normalise(entry.category).includes(columnFilters.type)) return false;
    if(columnFilters.name && !normalise(entry.name).includes(columnFilters.name)) return false;
    if(columnFilters.path && !normalise(entry.path).includes(columnFilters.path)) return false;
    if(columnFilters.drive && !normalise(entry.drive).includes(columnFilters.drive)) return false;
    if(columnFilters.size && !normalise(entry.sizeLabel).includes(columnFilters.size)) return false;
    if(columnFilters.last && !normalise(entry.lastWrite).includes(columnFilters.last)) return false;
    if(searchTerm) {{
      const blob = `${entry.name} ${entry.path} ${entry.sha}`.toLowerCase();
      return blob.includes(searchTerm);
    }}
    return true;
  }}

  function render() {{
    const rendered = [];
    let visibleEntries = 0;
    let visibleBytes = 0;

    const filteredGroups = groups.map((group) => {{
      const entries = group.entries.filter(matchesEntry);
      return {{ groupInfo: group, entries }};
    }}).filter((item) => item.entries.length > 0 && (!multiOnly || item.groupInfo.multiDrive));

    filteredGroups.sort(compareGroups);

    filteredGroups.forEach((groupWrapper) => {{
      const info = groupWrapper.groupInfo;
      rendered.push(`
        <tr class="group-row" data-group="${info.group}" data-open="true">
          <td>${info.group}</td>
          <td colspan="9">
            <span class="badge${info.multiDrive ? ' multi' : ''}">${info.count} copia(s) · ${escapeHtml(info.totalLabel)}</span>
            <span class="badge">Unidades: ${info.drives.join(', ')}</span>
            <span class="badge">SHA: ${escapeHtml(info.sha)}</span>
          </td>
        </tr>`);
      const sortedEntries = [...groupWrapper.entries];
      if(sortConfig.field && sortConfig.field !== 'sha') {{
        const factor = sortConfig.direction === 'desc' ? -1 : 1;
        sortedEntries.sort((a, b) => compareEntries(a, b, sortConfig.field) * factor);
      }}
      sortedEntries.forEach((entry) => {{
        visibleEntries += 1;
        visibleBytes += entry.bytes || 0;
        const disabled = entry.openUri ? '' : ' aria-disabled="true"';
        rendered.push(`
          <tr class="entry-row" data-group="${info.group}">
            <td>${info.group}</td>
            <td>${escapeHtml(entry.sha)}</td>
            <td>${entry.role}</td>
            <td><span class="icon">${entry.icon}</span> ${entry.category}</td>
            <td>${escapeHtml(entry.name)}</td>
            <td class="path">${escapeHtml(entry.path)}</td>
            <td>${entry.drive}</td>
            <td>${escapeHtml(entry.sizeLabel)}</td>
            <td>${escapeHtml(entry.lastWrite || '')}</td>
            <td class="actions">
              ${entry.openUri ? `<a href="${entry.openUri}" target="_blank" rel="noopener">Abrir</a>` : '<span style="opacity:.5">Sin acceso</span>'}
              <button type="button" data-copy="${escapeHtml(entry.path)}">Copiar ruta</button>
            </td>
          </tr>`);
      }});
    }});

    tbody.innerHTML = rendered.join('');
    statVisible.textContent = visibleEntries.toLocaleString('es-ES');
    statSize.textContent = formatBytes(visibleBytes);
  }}

  tbody.addEventListener('click', (event) => {{
    const button = event.target.closest('button[data-copy]');
    if(button) {{
      navigator.clipboard?.writeText(button.dataset.copy).then(() => {{
        button.textContent = 'Copiado ✔';
        setTimeout(() => button.textContent = 'Copiar ruta', 1500);
      }}).catch(() => {{
        button.textContent = 'Error';
        setTimeout(() => button.textContent = 'Copiar ruta', 1500);
      }});
      event.stopPropagation();
      return;
    }}
    const groupRow = event.target.closest('tr.group-row');
    if(groupRow) {{
      const isOpen = groupRow.dataset.open === 'true';
      groupRow.dataset.open = (!isOpen).toString();
      tbody.querySelectorAll(`tr.entry-row[data-group="${groupRow.dataset.group}"]`).forEach((row) => {{
        row.style.display = isOpen ? 'none' : '';
      }});
    }}
  }});

  searchInput.addEventListener('input', (event) => {{
    searchTerm = event.target.value.trim().toLowerCase();
    render();
  }});

  chips.forEach((chip) => {{
    chip.addEventListener('click', () => {{
      if(chip.dataset.drive) {{
        const drive = chip.dataset.drive;
        if(drives.has(drive)) {{
          drives.delete(drive);
          chip.dataset.active = 'false';
        }} else {{
          drives.add(drive);
          chip.dataset.active = 'true';
        }}
      }} else if(chip.dataset.type) {{
        typeFilter = chip.dataset.type;
        document.querySelectorAll('.filter-chip[data-type]').forEach((item) => item.dataset.active = 'false');
        chip.dataset.active = 'true';
      }}
      render();
    }});
  }});

  multiToggle.addEventListener('change', (event) => {{
    multiOnly = event.target.checked;
    render();
  }});

  resetBtn.addEventListener('click', () => {{
    drives.clear();
    ['H','I','J'].forEach((drive) => drives.add(drive));
    document.querySelectorAll('.filter-chip[data-drive]').forEach((chip) => chip.dataset.active = 'true');
    document.querySelector('.filter-chip[data-type="all"]').dataset.active = 'true';
    document.querySelectorAll('.filter-chip[data-type]').forEach((chip) => {{
      if(chip.dataset.type !== 'all') chip.dataset.active = 'false';
    }});
    typeFilter = 'all';
    searchInput.value = '';
    searchTerm = '';
    multiToggle.checked = false;
    multiOnly = false;
    Object.keys(columnFilters).forEach((key) => columnFilters[key] = '');
    columnInputs.forEach((input) => input.value = '');
    render();
  }});

  headers.forEach((header) => {{
    header.addEventListener('click', () => {{
      const field = header.dataset.sort;
      if(sortConfig.field === field) {{
        sortConfig.direction = sortConfig.direction === 'asc' ? 'desc' : 'asc';
      }} else {{
        sortConfig.field = field;
        sortConfig.direction = 'asc';
      }}
      headers.forEach((item) => item.removeAttribute('data-direction'));
      header.dataset.direction = sortConfig.direction;
      render();
    }});
  }});

  columnInputs.forEach((input) => {{
    input.addEventListener('input', (event) => {{
      const key = event.target.dataset.filter;
      columnFilters[key] = event.target.value.trim().toLowerCase();
      render();
    }});
  }});

  render();
}})();
</script>
</body>
</html>
"""


def main() -> int:
    try:
        args = parse_args()
        groups = load_groups(args.source)
        payload = build_payload(groups)
        html = build_html(payload)
        args.target.parent.mkdir(parents=True, exist_ok=True)
        args.target.write_text(html, encoding="utf-8")
        if not args.quiet:
            summary = payload["summary"]
            print(
                f"Generado {args.target} · {summary['groups']} grupos · {summary['items']} entradas · {summary['bytesLabel']}"
            )
        return 0
    except DuplicateExplorerError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - catch-all for logging
        print(f"Error inesperado: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())


