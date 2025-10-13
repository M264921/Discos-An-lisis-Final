#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import importlib
import sys
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
    """Load `discos_analisis.cli.enrich.main` with fallback for src layout."""

    module_name = "discos_analisis.cli.enrich"

    # Ensure the development "src" tree is discoverable before attempting the import.
    # This keeps the legacy entrypoint runnable from a fresh checkout without
    # requiring `pip install -e .` or manual `PYTHONPATH` tweaks.
    _ensure_src_on_path()

    module = importlib.import_module(module_name)

    return module.main


# Resolve the CLI entry point at import time using the loader helper.
main = _load_main()

# Backwards compatibility for callers that imported the previous helper name.
_resolve_main = _load_main


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
