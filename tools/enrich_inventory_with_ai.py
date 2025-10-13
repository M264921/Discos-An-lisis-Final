#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from collections.abc import Callable
from functools import lru_cache
from importlib import import_module
from pathlib import Path
from types import ModuleType
from typing import Final


_ENTRYPOINT: Final[str] = "discos_analisis.cli.enrich"


_MainCallable = Callable[[], int | None]
# Exported for compatibility with legacy callers that imported ``MainCallable``.
MainCallable = _MainCallable


def _safe_resolve(entry: str) -> Path | None:
    """Resolve a ``sys.path`` entry defensively."""

    try:
        return Path(entry).resolve()
    except (OSError, RuntimeError):  # pragma: no cover - defensive
        return None


@lru_cache(maxsize=1)
def _ensure_src_on_path() -> Path | None:
    """Ensure the development ``src`` tree is importable."""

    script_path = Path(__file__).resolve()
    tools_dir = script_path.parent

    candidate_roots: list[Path] = []
    # Consider the expected repo layout first (``tools/`` sibling of ``src/``).
    candidate_roots.append(tools_dir.parent / "src")
    # Include every ancestor of ``tools/`` in case the repo is symlinked.
    candidate_roots.extend(parent / "src" for parent in tools_dir.parents)

    normalized_sys_path = {
        resolved
        for entry in sys.path
        if (resolved := _safe_resolve(entry)) is not None
    }

    for src_root in candidate_roots:
        if not src_root.exists():
            continue

        if src_root not in normalized_sys_path:
            sys.path.insert(0, str(src_root))
            normalized_sys_path.add(src_root)

        return src_root

    return None


_SRC_ROOT = _ensure_src_on_path()


def _load_main() -> _MainCallable:
    """Load ``discos_analisis.cli.enrich.main`` supporting editable checkouts."""

    src_root = _ensure_src_on_path() or _SRC_ROOT

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

    if not callable(main_attr):  # pragma: no cover - defensive
        raise TypeError(
            "El atributo 'main' de 'discos_analisis.cli.enrich' no es invocable."
        )

    return main_attr


main: Final[_MainCallable] = _load_main()


# Keep a compatibility helper for callers that previously imported `_resolve_main`.
def _resolve_main() -> _MainCallable:
    """Compatibility shim for legacy callers expecting the old helper name."""

    return _load_main()


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:  # pragma: no cover - user abort
        raise SystemExit(130)
