"""CLI para enriquecer el inventario con anotaciones generadas por IA."""

from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import sys
import time
from typing import Dict, Iterable, Sequence

from .. import constants
from ..ai import OpenAIClient, call_with_retries
from ..annotations import (
    AnnotationIndex,
    annotation_key,
    load_annotations,
    normalize_category,
    save_annotations,
)
from ..inventory import (
    build_full_path,
    detect_extension,
    load_inventory,
    normalize_extensions,
    read_text_preview,
    truncate_text,
)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parsea los argumentos de línea de comandos del enriquecedor."""
    parser = argparse.ArgumentParser(
        description=(
            "Clasifica archivos legibles usando OpenAI y genera anotaciones "
            "para el inventario HTML."
        )
    )
    parser.add_argument(
        "--inventory",
        default="docs/data/inventory.json",
        help="Ruta al inventario base en JSON.",
    )
    parser.add_argument(
        "--output",
        default=None,
        help=(
            "Archivo de salida para las anotaciones. Por defecto usa "
            "docs/data/inventory_ai_annotations.json en el mismo directorio que"
            " el inventario."
        ),
    )
    parser.add_argument(
        "--model",
        default=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
        help="Modelo a utilizar (OPENAI_MODEL tiene precedencia si está definido).",
    )
    parser.add_argument(
        "--api-key",
        default=None,
        help="Clave API (por defecto se usa OPENAI_API_KEY).",
    )
    parser.add_argument(
        "--api-base",
        default=os.getenv("OPENAI_API_BASE", "https://api.openai.com"),
        help="Base URL del API de OpenAI (OPENAI_API_BASE si está presente).",
    )
    parser.add_argument(
        "--categories",
        default=None,
        help=(
            "Lista de categorías separadas por coma. Si se omite se usan las "
            "categorías por defecto."
        ),
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Solicitar también un resumen corto del archivo.",
    )
    parser.add_argument(
        "--max-chars",
        type=int,
        default=1800,
        help="Número máximo de caracteres enviados al modelo por archivo.",
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=8192,
        help="Número máximo de bytes que se leerán del archivo fuente.",
    )
    parser.add_argument(
        "--extensions",
        default=None,
        help=(
            "Extensiones legibles separadas por coma (incluye el punto). Si se "
            "proporciona, reemplaza al conjunto por defecto."
        ),
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Límite de nuevos archivos a procesar en esta ejecución.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Forzar reclasificación incluso si ya existe una anotación.",
    )
    parser.add_argument(
        "--retries",
        type=int,
        default=2,
        help="Número de reintentos automáticos ante errores del API.",
    )
    parser.add_argument(
        "--retry-wait",
        type=float,
        default=5.0,
        help="Segundos a esperar entre reintentos.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.0,
        help="Pausa opcional (en segundos) entre llamadas exitosas para controlar el ritmo.",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=320,
        help="Límite aproximado de tokens de salida para el modelo.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="No escribe archivo ni llama al API; solo muestra qué se procesaría.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Muestra información adicional durante el procesamiento.",
    )
    return parser.parse_args(argv)


def _resolve_categories(raw: str | None) -> list[str]:
    if raw:
        tokens = [token.strip().lower() for token in raw.split(",") if token.strip()]
        if tokens:
            return tokens
    return list(constants.DEFAULT_CATEGORIES)


def _load_extensions(raw: str | None) -> set[str]:
    normalized: Iterable[str] = normalize_extensions(raw)
    return {token.lower() for token in normalized}


def _ensure_client(args: argparse.Namespace, api_key: str | None) -> OpenAIClient | None:
    if args.dry_run:
        return None
    assert api_key is not None  # se valida antes de llamar
    return OpenAIClient(api_key, args.model, args.api_base, args.max_tokens)


def _should_skip_existing(
    key: str | None,
    annotations: AnnotationIndex,
    force: bool,
    require_summary: bool,
    verbose: bool,
) -> bool:
    if not key:
        return False
    existing = annotations.get(key)
    if not existing:
        return False
    if force:
        return False
    summary = str(existing.get("resumen") or existing.get("summary") or "").strip()
    if require_summary and not summary:
        if verbose:
            print(
                f"[actualización] Re-generando resumen para {existing.get('nombre', 'sin nombre')}",
                file=sys.stderr,
            )
        return False
    return True


def _record_metadata(row: Dict[str, object]) -> Dict[str, str]:
    return {
        "nombre": str(row.get("nombre") or row.get("name") or ""),
        "ruta": str(row.get("ruta") or row.get("dir") or row.get("path") or ""),
        "extension": str(row.get("extension") or row.get("ext") or ""),
        "tamano": str(row.get("tamano") or row.get("size") or row.get("length") or ""),
    }


def main(argv: Sequence[str] | None = None) -> int:
    """Punto de entrada del comando `enrich`."""
    args = parse_args(argv)
    inventory_path = pathlib.Path(args.inventory)
    if not inventory_path.exists():
        raise SystemExit(f"No se encontró el inventario: {inventory_path}")
    output_path = (
        pathlib.Path(args.output)
        if args.output
        else inventory_path.parent / "inventory_ai_annotations.json"
    )
    annotations_payload, annotations_index = load_annotations(output_path)
    extensions = _load_extensions(args.extensions)
    categories = _resolve_categories(args.categories)
    if not categories:
        raise SystemExit("Debes definir al menos una categoría")
    api_key = args.api_key or os.getenv("OPENAI_API_KEY")
    if not api_key and not args.dry_run:
        raise SystemExit("OPENAI_API_KEY no está definido y no es un dry-run")
    inventory = load_inventory(inventory_path)
    client = _ensure_client(args, api_key)
    updated = 0
    skipped = 0
    start_time = time.time()
    for row in inventory:
        extension = detect_extension(row)
        if extension and extension.lower() not in extensions:
            skipped += 1
            continue
        full_path = build_full_path(row)
        if not args.dry_run and not full_path.exists():
            if args.verbose:
                print(f"[omitido] No existe {full_path}", file=sys.stderr)
            skipped += 1
            continue
        metadata = _record_metadata(row)
        metadata["extension"] = extension or metadata.get("extension", "")
        preview = ""
        if extension:
            try:
                preview = read_text_preview(full_path, args.max_bytes)
            except FileNotFoundError:
                if args.verbose:
                    print(f"[omitido] No se pudo abrir {full_path}", file=sys.stderr)
                skipped += 1
                continue
            except PermissionError:
                if args.verbose:
                    print(f"[omitido] Sin permisos para {full_path}", file=sys.stderr)
                skipped += 1
                continue
        preview = truncate_text(preview, args.max_chars)
        lookup = annotation_key(
            {
                "sha": row.get("sha"),
                "ruta": metadata["ruta"],
                "nombre": metadata["nombre"],
            }
        )
        if _should_skip_existing(lookup, annotations_index, args.force, args.summary, args.verbose):
            skipped += 1
            continue
        if args.limit is not None and updated >= args.limit:
            if args.verbose:
                print("Límite alcanzado, deteniendo procesamiento", file=sys.stderr)
            break
        if args.dry_run:
            print(f"[dry-run] Clasificaría {metadata['nombre']} ({full_path})")
            updated += 1
            continue
        assert client is not None
        result = call_with_retries(
            client,
            metadata,
            preview,
            categories,
            args.summary,
            args.retries,
            args.retry_wait,
            args.verbose,
            args.delay,
        )
        category = normalize_category(result.get("category", ""), categories)
        summary = result.get("summary", "").strip()
        record = {
            "id": lookup or None,
            "sha": str(row.get("sha") or ""),
            "ruta": metadata["ruta"],
            "nombre": metadata["nombre"],
            "categoria": category,
            "resumen": summary if args.summary else "",
            "model": args.model,
            "generated_at": dt.datetime.utcnow().isoformat() + "Z",
        }
        annotations_payload.setdefault("items", [])
        store_key = lookup or annotation_key(record)
        if not store_key:
            fallback = f"row:{metadata['ruta']}::{metadata['nombre']}"
            store_key = fallback.lower()
        record["id"] = store_key
        annotations_index[store_key] = record
        updated += 1
        display = metadata["nombre"] or metadata["ruta"] or record["sha"] or "(sin nombre)"
        if args.summary and summary:
            print(f"[IA] {display} → {category} :: {summary}")
        else:
            print(f"[IA] {display} → {category}")
    if args.dry_run:
        return 0
    annotations_payload["generated_at"] = dt.datetime.utcnow().isoformat() + "Z"
    annotations_payload["model"] = args.model
    annotations_payload["items"] = sorted(
        annotations_index.values(),
        key=lambda item: (
            str(item.get("sha") or ""),
            str(item.get("ruta") or ""),
            str(item.get("nombre") or ""),
        ),
    )
    save_annotations(output_path, annotations_payload)
    elapsed = time.time() - start_time
    print(
        f"Listo. Actualizados {updated} registros, omitidos {skipped}. "
        f"Duración: {elapsed:.1f}s",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":  # pragma: no cover
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
