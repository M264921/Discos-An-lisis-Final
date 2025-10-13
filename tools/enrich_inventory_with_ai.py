#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import importlib
import importlib.util
import sys
from importlib import import_module
from importlib.util import find_spec
from pathlib import Path


def _ensure_src_on_path() -> None:
    """Add the repository ``src`` directory to ``sys.path`` when available."""

    src_root = Path(__file__).resolve().parents[1] / "src"
    if not src_root.exists():
        return

    src_path = str(src_root)
    if src_path not in sys.path:
        sys.path.insert(0, src_path)


def _resolve_main():
    """Import the CLI entry point, adding ``src`` to ``sys.path`` as needed."""

    spec = find_spec("discos_analisis")
    if spec is None:
        _ensure_src_on_path()
        spec = find_spec("discos_analisis")
        if spec is None:
            raise ModuleNotFoundError(
                "No se pudo importar 'discos_analisis'. Instala el paquete (p. ej. `pip install -e .`) "
                "o ejecuta este script desde el repositorio que contiene el directorio `src/`."
            )

    return import_module("discos_analisis.cli.enrich").main


main = _resolve_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
