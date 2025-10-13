#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from collections.abc import Callable
from importlib import import_module
from pathlib import Path
from types import ModuleType


_MainCallable = Callable[[], int | None]


def _iter_candidate_src_dirs() -> list[Path]:
    """Return ``src`` directories discovered while walking up from this file."""

    resolved = Path(__file__).resolve()
    candidates: list[Path] = []
    for parent in resolved.parents:
        candidate = parent / "src"
        if candidate.exists() and candidate.is_dir():
            candidates.append(candidate)
    return candidates


def _ensure_src_on_path() -> None:
    """Add the repository ``src`` directory to ``sys.path`` when available."""

    for candidate in _iter_candidate_src_dirs():
        src_path = str(candidate)
        if src_path not in sys.path:
            sys.path.insert(0, src_path)
        # Once we've added the first matching ``src`` directory we can stop.
        break


def _load_main() -> _MainCallable:
    """Load ``discos_analisis.cli.enrich.main`` supporting editable checkouts."""

    module_name = "discos_analisis.cli.enrich"

    # Ensure the development ``src`` tree is discoverable before attempting the
    # import. This keeps the legacy entrypoint runnable from a fresh checkout
    # without requiring ``pip install -e .`` or manual ``PYTHONPATH`` tweaks.
    _ensure_src_on_path()

    try:
        module: ModuleType = import_module(module_name)
    except ModuleNotFoundError as exc:  # pragma: no cover - defensive path
        raise ModuleNotFoundError(
            "No se pudo importar 'discos_analisis'. Instala el paquete o ejecuta el script "
            "desde la raíz del repositorio."
        ) from exc

    main_attr = getattr(module, "main", None)
    if not isinstance(main_attr, Callable):
        raise AttributeError(
            "El módulo 'discos_analisis.cli.enrich' no expone un callable 'main'."
        )

    if not callable(main_attr):
        raise TypeError(
            "El atributo 'main' de 'discos_analisis.cli.enrich' no es invocable."
        )

    return main_attr


main = _load_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
