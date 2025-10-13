"""Funciones utilitarias para cargar inventarios y manipular rutas."""

from __future__ import annotations

import json
import pathlib
from typing import Dict, Iterable, List, Optional

from .constants import DEFAULT_EXTENSIONS


def load_inventory(path: pathlib.Path) -> List[Dict[str, object]]:
    """Carga un inventario en forma de lista de diccionarios."""
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            return data
    raise ValueError(f"El inventario {path} no contiene una lista JSON válida")


def normalize_extensions(raw: Optional[str]) -> Iterable[str]:
    """Normaliza una lista separada por comas de extensiones legibles."""
    if not raw:
        return DEFAULT_EXTENSIONS
    values = []
    for part in raw.split(","):
        token = part.strip()
        if not token:
            continue
        if not token.startswith("."):
            token = "." + token
        values.append(token.lower())
    return values or DEFAULT_EXTENSIONS


def combine_path(directory: str, name: str) -> str:
    """Compone una ruta combinando directorio y nombre de archivo."""
    directory = (directory or "").strip()
    name = (name or "").strip()
    if not directory:
        return name
    if not name:
        return directory
    if directory.endswith(":"):
        directory = directory + "\\"
    if directory.startswith("\\\\") or ":" in directory[:3]:
        return str(pathlib.PureWindowsPath(directory) / name)
    return str(pathlib.PurePath(directory) / name)


def detect_extension(row: Dict[str, object]) -> str:
    """Intenta deducir la extensión del archivo a partir del inventario."""
    raw = row.get("extension") or row.get("ext")
    if isinstance(raw, str) and raw.strip():
        return "." + raw.strip().lstrip(".").lower()
    name = row.get("nombre") or row.get("name")
    if isinstance(name, str) and "." in name:
        return pathlib.Path(name).suffix.lower()
    return ""


def build_full_path(row: Dict[str, object]) -> pathlib.Path:
    """Devuelve la ruta absoluta del archivo combinando carpeta y nombre."""
    ruta = str(row.get("ruta") or row.get("dir") or row.get("path") or "").strip()
    nombre = str(row.get("nombre") or row.get("name") or "").strip()
    full = combine_path(ruta, nombre)
    if not full:
        return pathlib.Path(nombre)
    return pathlib.Path(full)


def read_text_preview(path: pathlib.Path, max_bytes: int) -> str:
    """Lee un fragmento del archivo para mostrar un avance legible."""
    with path.open("rb") as handle:
        chunk = handle.read(max_bytes)
    if not chunk:
        return ""
    try:
        return chunk.decode("utf-8")
    except UnicodeDecodeError:
        return chunk.decode("utf-8", errors="ignore")


def truncate_text(text: str, limit: int) -> str:
    """Recorta el texto respetando el límite máximo de caracteres."""
    if limit <= 0 or len(text) <= limit:
        return text
    return text[:limit]


__all__ = [
    "load_inventory",
    "normalize_extensions",
    "combine_path",
    "detect_extension",
    "build_full_path",
    "read_text_preview",
    "truncate_text",
]
