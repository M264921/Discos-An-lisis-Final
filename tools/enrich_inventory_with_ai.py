#!/usr/bin/env python3
"""Annotate inventory entries with OpenAI-powered labels and summaries."""

import argparse
import datetime as _dt
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request
from typing import Dict, Iterable, List, Optional, Tuple

DEFAULT_EXTENSIONS = {
    ".txt",
    ".md",
    ".rst",
    ".log",
    ".ini",
    ".cfg",
    ".conf",
    ".csv",
    ".tsv",
    ".json",
    ".yaml",
    ".yml",
    ".xml",
    ".html",
    ".htm",
    ".css",
    ".js",
    ".ts",
    ".py",
    ".ps1",
    ".psm1",
    ".bat",
    ".cmd",
    ".sh",
    ".bash",
    ".zsh",
    ".sql",
    ".java",
    ".cs",
    ".cpp",
    ".c",
    ".h",
    ".hpp",
    ".rb",
    ".php",
    ".go",
    ".rs",
}

DEFAULT_CATEGORIES = [
    "documento",
    "codigo",
    "backup",
    "informe",
    "multimedia",
    "personal",
    "otro",
]


class ApiError(RuntimeError):
    """Simple error wrapper for HTTP failures."""

    def __init__(self, message: str, status: Optional[int] = None) -> None:
        super().__init__(message)
        self.status = status


def parse_args() -> argparse.Namespace:
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
    return parser.parse_args()


def load_inventory(path: pathlib.Path) -> List[Dict[str, object]]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            return data
    raise ValueError(f"El inventario {path} no contiene una lista JSON válida")


def load_annotations(path: pathlib.Path) -> Tuple[Dict[str, object], Dict[str, Dict[str, object]]]:
    if not path.exists():
        return {"items": []}, {}
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if isinstance(payload, dict):
        items = payload.get("items")
        if not isinstance(items, list):
            items = []
            payload["items"] = items
    elif isinstance(payload, list):
        items = payload
        payload = {"items": items}
    else:
        raise ValueError(f"Anotaciones inválidas en {path}")
    index: Dict[str, Dict[str, object]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        key = annotation_key(item)
        if key:
            index[key] = item
    return payload, index


def save_annotations(path: pathlib.Path, payload: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def normalize_extensions(raw: Optional[str]) -> Iterable[str]:
    if not raw:
        return DEFAULT_EXTENSIONS
    values = []
    for part in raw.split(","):
        token = part.strip()
        if not token:
            continue
        if not token.startswith("."):
            token = "." + token
        values.append(token.lower())
    return values or DEFAULT_EXTENSIONS


def annotation_key(item: Dict[str, object]) -> Optional[str]:
    sha = str(item.get("sha") or item.get("hash") or "").strip()
    if sha:
        return f"sha:{sha}"
    identifier = str(item.get("id") or "").strip()
    if identifier:
        return identifier
    ruta = str(item.get("ruta") or item.get("path") or "").strip()
    nombre = str(item.get("nombre") or item.get("name") or "").strip()
    full = combine_path(ruta, nombre)
    if full:
        return f"path:{full.lower()}"
    if ruta:
        return f"ruta:{ruta.lower()}"
    if nombre:
        return f"nombre:{nombre.lower()}"
    return None


def combine_path(directory: str, name: str) -> str:
    directory = (directory or "").strip()
    name = (name or "").strip()
    if not directory:
        return name
    if not name:
        return directory
    if directory.endswith(":"):
        directory = directory + "\\"
    if directory.startswith("\\\\") or ":" in directory[:3]:
        return str(pathlib.PureWindowsPath(directory) / name)
    return str(pathlib.PurePath(directory) / name)


def detect_extension(row: Dict[str, object]) -> str:
    raw = row.get("extension") or row.get("ext")
    if isinstance(raw, str) and raw.strip():
        return "." + raw.strip().lstrip(".").lower()
    name = row.get("nombre") or row.get("name")
    if isinstance(name, str) and "." in name:
        return pathlib.Path(name).suffix.lower()
    return ""


def build_full_path(row: Dict[str, object]) -> pathlib.Path:
    ruta = str(row.get("ruta") or row.get("dir") or row.get("path") or "").strip()
    nombre = str(row.get("nombre") or row.get("name") or "").strip()
    full = combine_path(ruta, nombre)
    if not full:
        return pathlib.Path(nombre)
    return pathlib.Path(full)


def read_text_preview(path: pathlib.Path, max_bytes: int) -> str:
    with path.open("rb") as handle:
        chunk = handle.read(max_bytes)
    if not chunk:
        return ""
    try:
        return chunk.decode("utf-8")
    except UnicodeDecodeError:
        return chunk.decode("utf-8", errors="ignore")


def truncate_text(text: str, limit: int) -> str:
    if limit <= 0 or len(text) <= limit:
        return text
    return text[:limit]


def format_prompt(
    metadata: Dict[str, str],
    preview: str,
    categories: List[str],
    include_summary: bool,
) -> str:
    options = ", ".join(categories)
    lines = [
        "Eres un asistente que clasifica archivos de un inventario.",
        "Analiza los metadatos del archivo y, si existe, el fragmento de contenido.",
        "Debes responder únicamente en JSON con las claves 'category' y 'summary'.",
        "La clave 'category' debe ser una de: [" + options + "].",
    ]
    if include_summary:
        lines.append("La clave 'summary' debe contener una frase breve (máx. 2) en español.")
    else:
        lines.append("Si no hay que resumir, deja 'summary' como cadena vacía.")
    lines.append("")
    lines.append("Metadatos:")
    for key, value in metadata.items():
        if value:
            lines.append(f"- {key}: {value}")
    if preview:
        lines.append("")
        lines.append("Contenido:")
        lines.append(preview)
    return "\n".join(lines)


class OpenAIClient:
    def __init__(self, api_key: str, model: str, api_base: str, max_tokens: int) -> None:
        base = api_base.rstrip("/")
        if base.endswith("/v1"):
            endpoint = f"{base}/chat/completions"
        else:
            endpoint = f"{base}/v1/chat/completions"
        self.endpoint = endpoint
        self.model = model
        self.api_key = api_key
        self.max_tokens = max_tokens

    def classify(
        self,
        metadata: Dict[str, str],
        preview: str,
        categories: List[str],
        include_summary: bool,
        temperature: float,
    ) -> Dict[str, str]:
        prompt = format_prompt(metadata, preview, categories, include_summary)
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Eres un asistente experto en gestión documental. "
                        "Responde siempre en JSON válido."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            "temperature": temperature,
            "max_tokens": self.max_tokens,
            "response_format": {"type": "json_object"},
        }
        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.endpoint,
            data=data,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request) as response:
                body = response.read().decode("utf-8")
        except urllib.error.HTTPError as err:
            message = err.read().decode("utf-8", errors="ignore")
            raise ApiError(message or str(err), status=err.code) from err
        except urllib.error.URLError as err:
            raise ApiError(str(err)) from err
        payload = json.loads(body)
        choices = payload.get("choices")
        if not choices:
            raise ApiError("Respuesta sin 'choices' desde el API de OpenAI")
        message = choices[0].get("message", {})
        content = message.get("content", "{}").strip()
        data = json.loads(content)
        category = str(data.get("category") or "").strip()
        summary = str(data.get("summary") or "").strip()
        return {"category": category, "summary": summary}


def main() -> int:
    args = parse_args()
    inventory_path = pathlib.Path(args.inventory)
    if not inventory_path.exists():
        raise SystemExit(f"No se encontró el inventario: {inventory_path}")
    output_path = (
        pathlib.Path(args.output)
        if args.output
        else inventory_path.parent / "inventory_ai_annotations.json"
    )
    annotations_payload, annotations_index = load_annotations(output_path)
    extensions = set(normalize_extensions(args.extensions))
    categories = (
        [token.strip().lower() for token in args.categories.split(",") if token.strip()]
        if args.categories
        else DEFAULT_CATEGORIES
    )
    if not categories:
        raise SystemExit("Debes definir al menos una categoría")
    api_key = args.api_key or os.getenv("OPENAI_API_KEY")
    if not api_key and not args.dry_run:
        raise SystemExit("OPENAI_API_KEY no está definido y no es un dry-run")
    inventory = load_inventory(inventory_path)
    client = None
    if not args.dry_run:
        client = OpenAIClient(api_key, args.model, args.api_base, args.max_tokens)
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
        metadata = {
            "nombre": str(row.get("nombre") or row.get("name") or ""),
            "ruta": str(row.get("ruta") or row.get("dir") or row.get("path") or ""),
            "extension": extension or "",
            "tamano": str(row.get("tamano") or row.get("size") or row.get("length") or ""),
        }
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
        key = annotation_key(
            {
                "sha": row.get("sha"),
                "ruta": metadata["ruta"],
                "nombre": metadata["nombre"],
            }
        )
        existing = annotations_index.get(key) if key else None
        if existing and not args.force:
            if args.summary and not str(existing.get("resumen") or existing.get("summary") or "").strip():
                if args.verbose:
                    print(
                        f"[actualización] Re-generando resumen para {metadata['nombre']}",
                        file=sys.stderr,
                    )
            else:
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
        assert client is not None  # para mypy/linters
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
            "id": key or None,
            "sha": str(row.get("sha") or ""),
            "ruta": metadata["ruta"],
            "nombre": metadata["nombre"],
            "categoria": category,
            "resumen": summary if args.summary else "",
            "model": args.model,
            "generated_at": _dt.datetime.utcnow().isoformat() + "Z",
        }
        annotations_payload.setdefault("items", [])
        store_key = key or annotation_key(record)
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
    annotations_payload["generated_at"] = _dt.datetime.utcnow().isoformat() + "Z"
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


def normalize_category(value: str, categories: List[str]) -> str:
    normalized = value.strip().lower()
    if normalized in categories:
        return normalized
    for candidate in categories:
        if candidate.lower() == normalized:
            return candidate.lower()
    return "otro" if "otro" in categories else categories[0]


def call_with_retries(
    client: OpenAIClient,
    metadata: Dict[str, str],
    preview: str,
    categories: List[str],
    include_summary: bool,
    retries: int,
    wait_seconds: float,
    verbose: bool,
    delay: float,
) -> Dict[str, str]:
    attempts = retries + 1
    for attempt in range(1, attempts + 1):
        try:
            result = client.classify(
                metadata,
                preview,
                categories,
                include_summary,
                temperature=0.0,
            )
            if delay > 0:
                time.sleep(delay)
            return result
        except ApiError as error:
            if verbose:
                print(
                    f"Intento {attempt} falló ({error.status or 'sin código'}): {error}",
                    file=sys.stderr,
                )
            if attempt >= attempts:
                raise
            time.sleep(wait_seconds)
    raise ApiError("Reintentos agotados")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
