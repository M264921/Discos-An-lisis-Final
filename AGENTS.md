# 🧭 Agent Playbook

Guía operativa para mantener el flujo autónomo de inventario multimedia.

---

## 🧱 Arquitectura del repositorio

| Zona | Contenido | Notas |
| --- | --- | --- |
| Raíz | CSV y reportes generados (`index_by_hash.csv`, `inventory_by_folder.csv`) más orquestadores como `make_inventory_offline.ps1`. | Los artefactos se regeneran desde scripts, no se editan manualmente. |
| `tools/` | Automatizaciones reutilizables. | Los *entry-points* viven en `tools/agents/`; los módulos auxiliares (`build-hash-data.ps1`, `inventory-inject-from-csv.ps1`, `normalize-inventory-html.ps1`) implementan pasos individuales. |
| `docs/` | Salida pública (`docs/hash_data.csv`, `docs/inventario_interactivo_offline.html`, tableros de duplicados). | Trátalos como read-only; usa los scripts para actualizarlos. |

---

## 🛠️ Comandos esenciales

| Objetivo | Comando |
| --- | --- |
| Pipeline completo (hash → HTML → sanitizado) | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None` |
| Refrescar solo `docs/hash_data.csv` | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build-hash-data.ps1 -RepoRoot . -IndexPath index_by_hash.csv` |
| Regenerar analítica de duplicados | `python tools/generate_duplicates_table.py --input docs/hash_data.csv --output docs/duplicate_summary.json` |

Mantén los scripts idempotentes y sin rutas absolutas codificadas.

---

## 🧩 Estilo y convenciones

- **PowerShell**: Sangría de 2 espacios, comandos `Verbo-Nombre`, usa comillas simples para literales, ASCII puro.
- **Python**: Sangría de 4 espacios, `snake_case`, sin dependencias externas.
- **HTML/CSV generados**: nunca los edites a mano; actualízalos mediante los scripts correspondientes.

---

## ✅ Verificaciones recomendadas

1. Después de modificar la tubería, ejecuta el *cleaner* y revisa el log para confirmar los recuentos y el resumen H/I/J en el HTML generado.
2. Cambios de normalización → `pwsh -File tools/normalize-inventory-html.ps1 -HtmlPath docs/inventario_interactivo_offline.html` como *smoke test*.
3. Ajustes de hash o duplicados → inspecciona `docs/hash_data.csv` y verifica las columnas `FullName`, `Hash`, `Length`, `Extension`, `Error`.

---

## 📬 Commits y PRs

- Usa prefijos convencionales (`feat`, `fix`, `chore`, `docs`) con un alcance opcional (`fix(inventory): ...`).
- Los PRs deben resumir cambios, enlazar Trello/issues cuando aplique y adjuntar evidencias antes/después si se modifican HTML o CSV.

---

## 🔐 Notas operativas

`docs/hash_data.csv` contiene rutas absolutas y tamaños. Solo compártelo con colaboradores de confianza. Los sanitizadores bloquean protocolos externos (acestream, http); extiende la blocklist si aparecen nuevos protocolos, en vez de deshabilitarla.
