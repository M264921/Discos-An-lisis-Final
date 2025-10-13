#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path


def _load_main() -> "object":
    """Load `discos_analisis.cli.enrich.main` with fallback for src layout."""

    try:
        module = importlib.import_module("discos_analisis.cli.enrich")
    except ModuleNotFoundError as first_error:
        if first_error.name not in {"discos_analisis", "discos_analisis.cli", "discos_analisis.cli.enrich"}:
            raise

        repo_root = Path(__file__).resolve().parents[1]
        src_dir = repo_root / "src"

        if src_dir.is_dir() and str(src_dir) not in sys.path:
            sys.path.insert(0, str(src_dir))

        module = importlib.import_module("discos_analisis.cli.enrich")

    return module.main


main = _load_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
