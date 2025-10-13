#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from importlib import import_module
from pathlib import Path


def _ensure_src_on_path() -> None:
    """Add the repository ``src`` directory to ``sys.path`` when available."""

    src_root = Path(__file__).resolve().parents[1] / "src"
    if not src_root.exists():
        return

    src_path = str(src_root)
    if src_path not in sys.path:
        sys.path.insert(0, src_path)


def _load_main() -> "object":
    """Load `discos_analisis.cli.enrich.main` supporting editable checkouts."""

    _ensure_src_on_path()

    try:
        return import_module("discos_analisis.cli.enrich").main
    except ModuleNotFoundError as exc:  # pragma: no cover - defensive fallback
        if exc.name != "discos_analisis" and not exc.name.startswith("discos_analisis."):
            raise

        raise ModuleNotFoundError(
            "No se pudo importar 'discos_analisis'. Instala el paquete o ejecuta el script "
            "desde la raíz del repositorio."
        ) from exc


main = _load_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
