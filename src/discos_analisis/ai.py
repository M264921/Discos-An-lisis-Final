"""Cliente minimalista para consumir el API de OpenAI via urllib."""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from typing import Dict, List


class ApiError(RuntimeError):
    """Simple envoltorio para representar fallos HTTP."""

    def __init__(self, message: str, status: int | None = None) -> None:
        super().__init__(message)
        self.status = status


def format_prompt(
    metadata: Dict[str, str],
    preview: str,
    categories: List[str],
    include_summary: bool,
) -> str:
    """Construye el prompt enviado al modelo de lenguaje."""
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
    """Cliente HTTP mínimo para consumir chat.completions sin SDK externo."""

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
    """Invoca el modelo con reintentos automáticos ante fallos recuperables."""
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


__all__ = ["ApiError", "OpenAIClient", "call_with_retries", "format_prompt"]
