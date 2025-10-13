#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

from pathlib import Path
import sys


def _ensure_src_on_path() -> None:
    """Añade `src/` al `sys.path` cuando se ejecuta desde el checkout."""

    repo_root = Path(__file__).resolve().parent.parent
    src_dir = repo_root / "src"
    if src_dir.is_dir():
        src_path = str(src_dir)
        if src_path not in sys.path:
            sys.path.insert(0, src_path)


_ensure_src_on_path()

from discos_analisis.cli.enrich import main


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
