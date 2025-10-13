#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from collections.abc import Callable
from importlib import import_module
from pathlib import Path
from types import ModuleType


_ENTRYPOINT = "discos_analisis.cli.enrich"


_MainCallable = Callable[[], int | None]


def _ensure_src_on_path() -> Path | None:
    """Ensure the development ``src`` tree is importable.

    Returns the path that was added so callers can include it in error
    diagnostics when the import still fails (for example if the package was
    renamed).
    """

    src_root = Path(__file__).resolve().parents[1] / "src"
    if not src_root.exists():
        return None

    src_path = str(src_root)
    if src_path not in sys.path:
        sys.path.insert(0, src_path)

    return src_root


def _load_main() -> _MainCallable:
    """Load ``discos_analisis.cli.enrich.main`` supporting editable checkouts."""

    # Ensure the development ``src`` tree is discoverable before attempting the
    # import. This keeps the legacy entrypoint runnable from a fresh checkout
    # without requiring ``pip install -e .`` or manual ``PYTHONPATH`` tweaks.
    src_root = _ensure_src_on_path()

    try:
        module: ModuleType = import_module(_ENTRYPOINT)
    except ModuleNotFoundError as exc:  # pragma: no cover - defensive path
        hint = (
            " Instala el paquete o ejecuta el script desde la raíz del repositorio."
            if src_root is None
            else f" Asegúrate de que {src_root} contenga el paquete 'discos_analisis'."
        )
        raise ModuleNotFoundError(
            "No se pudo importar 'discos_analisis'." + hint
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
