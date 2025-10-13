#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from importlib import import_module
from pathlib import Path
from typing import Callable


def _ensure_src_on_path() -> None:
    """Add the repository ``src`` directory to ``sys.path`` when available."""

    src_root = Path(__file__).resolve().parents[1] / "src"
    if not src_root.exists():
        return

    src_path = str(src_root)
    if src_path not in sys.path:
        sys.path.insert(0, src_path)


_ensure_src_on_path()


def _load_main() -> Callable[..., int]:
    """Load `discos_analisis.cli.enrich.main` supporting editable checkouts."""

    module_name = "discos_analisis.cli.enrich"

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
