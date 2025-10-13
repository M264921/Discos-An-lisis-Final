"""Gestión de anotaciones generadas por modelos de lenguaje."""

from __future__ import annotations

import json
import pathlib
from typing import Dict, Optional, Tuple

from .inventory import combine_path


AnnotationIndex = Dict[str, Dict[str, object]]


def annotation_key(item: Dict[str, object]) -> Optional[str]:
    """Genera una clave estable para identificar una anotación."""
    sha = str(item.get("sha") or item.get("hash") or "").strip()
    if sha:
        return f"sha:{sha}"
    identifier = str(item.get("id") or "").strip()
    if identifier:
        return identifier
    ruta = str(item.get("ruta") or item.get("path") or "").strip()
    nombre = str(item.get("nombre") or item.get("name") or "").strip()
    full = combine_path(ruta, nombre)
    if full:
        return f"path:{full.lower()}"
    if ruta:
        return f"ruta:{ruta.lower()}"
    if nombre:
        return f"nombre:{nombre.lower()}"
    return None


def load_annotations(path: pathlib.Path) -> Tuple[Dict[str, object], AnnotationIndex]:
    """Carga anotaciones existentes y construye un índice rápido por clave."""
    if not path.exists():
        return {"items": []}, {}
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if isinstance(payload, dict):
        items = payload.get("items")
        if not isinstance(items, list):
            items = []
            payload["items"] = items
    elif isinstance(payload, list):
        items = payload
        payload = {"items": items}
    else:
        raise ValueError(f"Anotaciones inválidas en {path}")
    index: AnnotationIndex = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        key = annotation_key(item)
        if key:
            index[key] = item
    return payload, index


def save_annotations(path: pathlib.Path, payload: Dict[str, object]) -> None:
    """Guarda las anotaciones generadas en disco con indentación legible."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def normalize_category(value: str, categories: list[str]) -> str:
    """Normaliza la categoría devuelta por el modelo al conjunto esperado."""
    normalized = value.strip().lower()
    if normalized in categories:
        return normalized
    for candidate in categories:
        if candidate.lower() == normalized:
            return candidate.lower()
    return "otro" if "otro" in categories else categories[0]


__all__ = [
    "AnnotationIndex",
    "annotation_key",
    "load_annotations",
    "save_annotations",
    "normalize_category",
]
