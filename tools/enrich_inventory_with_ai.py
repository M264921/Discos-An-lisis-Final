#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from importlib import import_module
from pathlib import Path
from typing import Callable, Final, Optional


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

    try:
        module = import_module(module_name)
    except ModuleNotFoundError as exc:  # pragma: no cover - defensive path
        raise ModuleNotFoundError(
            "No se pudo importar 'discos_analisis'. Instala el paquete o ejecuta el script "
            "desde la raíz del repositorio."
        ) from exc

    main_attr = getattr(module, "main", None)
    if main_attr is None:
        raise AttributeError(
            "El módulo 'discos_analisis.cli.enrich' no expone un callable 'main'."
        )

    return main_attr


# Resolve the CLI entry point at import time using the new `_load_main` helper.
main: Final[MainCallable]
main = _load_main()


# Keep a compatibility helper for callers that previously imported `_resolve_main`.
def _resolve_main() -> MainCallable:
    """Compatibility shim for legacy callers expecting the old helper name."""

    return _load_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
