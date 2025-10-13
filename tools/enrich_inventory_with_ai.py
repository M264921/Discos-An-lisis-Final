#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from typing import Callable, Optional


def _ensure_src_on_path() -> None:
    """Add the repository ``src`` directory to ``sys.path`` when available."""

    src_root = Path(__file__).resolve().parents[1] / "src"
    if not src_root.exists():
        return

    src_path = str(src_root)
    if src_path not in sys.path:
        sys.path.insert(0, src_path)


MainCallable = Callable[[], Optional[int]]


def _load_main() -> MainCallable:
    """Load `discos_analisis.cli.enrich.main` with fallback for src layout."""

    module_name = "discos_analisis.cli.enrich"

    # Ensure the development "src" tree is discoverable before attempting the import.
    # This keeps the legacy entrypoint runnable from a fresh checkout without
    # requiring `pip install -e .` or manual `PYTHONPATH` tweaks.
    _ensure_src_on_path()

    module = importlib.import_module(module_name)

    return module.main


# Resolve the CLI entry point at import time using the loader helper.
main: MainCallable = _load_main()


# Keep a compatibility helper for callers that previously imported `_resolve_main`.
def _resolve_main() -> MainCallable:
    """Compatibility shim for legacy callers expecting the old helper name."""

    return _load_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
