#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

import sys
from pathlib import Path


_SRC_ROOT = Path(__file__).resolve().parents[1] / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))


from discos_analisis.cli.enrich import main


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
