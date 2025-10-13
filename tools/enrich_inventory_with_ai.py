#!/usr/bin/env python3
"""Compatibilidad para el script legacy `tools/enrich_inventory_with_ai.py`."""

from __future__ import annotations

from discos_analisis.cli.enrich import main


if __name__ == "__main__":  # pragma: no cover
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
