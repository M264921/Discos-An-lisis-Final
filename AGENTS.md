# Agent Playbook

Guia operativa para mantener el flujo autonomo de inventario multimedia.

---

## Arquitectura del repositorio

| Zona   | Contenido                                                                                         | Notas                                                                                       |
| ------ | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Raiz   | CSV y reportes generados (`index_by_hash.csv`, `inventory_by_folder.csv`) y orquestadores clave.  | Los artefactos se regeneran desde scripts; evita edits manuales.                            |
| `tools/` | Automatizaciones reutilizables. Los entry points viven en `tools/agents/`; los modulos auxiliares (`build-hash-data.ps1`, `inventory-inject-from-csv.ps1`, `normalize-inventory-html.ps1`) implementan pasos individuales. |                                                                                             |
| `docs/`  | Salida publica (`docs/hash_data.csv`, `docs/inventario_interactivo_offline.html`, tableros de duplicados). | Tratalos como read-only y usa scripts para actualizarlos.                                   |

---

## Comandos esenciales

| Objetivo                                | Comando                                                                                           |
| --------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Pipeline completo (hash -> HTML -> sanitizado) | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None` |
| Refrescar solo `docs/hash_data.csv`     | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build-hash-data.ps1 -RepoRoot . -IndexPath index_by_hash.csv` |
| Regenerar analitica de duplicados       | `python tools/generate_duplicates_table.py --input docs/hash_data.csv --output docs/duplicate_summary.json` |
| Escaneo guiado (con filtro)             | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/scan-drives-interactive.ps1 -ContentFilter Media` |

Manten los scripts idempotentes y sin rutas absolutas codificadas.

---

## Estilo y convenciones

- **PowerShell**: Sangria de 2 espacios, comandos `Verbo-Nombre`, comillas simples para literales, ASCII puro.
- **Python**: Sangria de 4 espacios, `snake_case`, sin dependencias externas.
- **HTML/CSV generados**: nunca se editan a mano; actualiza usando los scripts correspondientes.

---

## Verificaciones recomendadas

1. Tras modificar la tuberia, ejecuta el cleaner y revisa el log para confirmar recuentos y el resumen H/I/J en el HTML generado.
2. Cambios de normalizacion -> `pwsh -File tools/normalize-inventory-html.ps1 -HtmlPath docs/inventario_interactivo_offline.html` como smoke test.
3. Ajustes de hash o duplicados -> inspecciona `docs/hash_data.csv` y verifica columnas `FullName`, `Hash`, `Length`, `Extension`, `Tipo`.
4. Diferencias de visualizacion -> abre el HTML regenerado y valida iconos de tipo, enlaces locales, selector de pagina y exportacion CSV.

---

## Notas operativas

- `docs/hash_data.csv` contiene rutas absolutas y tamanos: compartelo solo con colaboradores de confianza.
- Los sanitizadores bloquean protocolos externos (acestream, http); amplia la blocklist si aparecen nuevos protocolos en lugar de deshabilitarla.
- El merge de scans conserva por defecto la ultima ruta vista por SHA/tamano; revisa `tools/merge-scans.ps1 -KeepDuplicates` si necesitas diagnosticar historicos.
- Manten bajo control el repositorio: sin rutas absolutas, sin side-effects fuera de `RepoRoot`, y logs siempre en `logs/`.

