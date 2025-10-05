# ðŸ§­ Agent Playbook

GuÃ­a operativa para mantener el flujo autÃ³nomo de inventario multimedia.

---

## ðŸ§± Arquitectura del repositorio

| Zona | Contenido | Notas |
| --- | --- | --- |
| RaÃ­z | CSV y reportes generados (`index_by_hash.csv`, `inventory_by_folder.csv`) mÃ¡s orquestadores como `make_inventory_offline.ps1`. | Los artefactos se regeneran desde scripts, no se editan manualmente. |
| `tools/` | Automatizaciones reutilizables. | Los *entry-points* viven en `tools/agents/`; los mÃ³dulos auxiliares (`build-hash-data.ps1`, `inventory-inject-from-csv.ps1`, `normalize-inventory-html.ps1`) implementan pasos individuales. |
| `docs/` | Salida pÃºblica (`docs/hash_data.csv`, `docs/inventario_interactivo_offline.html`, tableros de duplicados). | TrÃ¡talos como read-only; usa los scripts para actualizarlos. |

---

## ðŸ› ï¸ Comandos esenciales

| Objetivo | Comando |
| --- | --- |
| Pipeline completo (hash â†’ HTML â†’ sanitizado) | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None` |
| Refrescar solo `docs/hash_data.csv` | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build-hash-data.ps1 -RepoRoot . -IndexPath index_by_hash.csv` |
| Regenerar analÃ­tica de duplicados | `python tools/generate_duplicates_table.py --input docs/hash_data.csv --output docs/duplicate_summary.json` |

MantÃ©n los scripts idempotentes y sin rutas absolutas codificadas.

---

## ðŸ§© Estilo y convenciones

- **PowerShell**: SangrÃ­a de 2 espacios, comandos `Verbo-Nombre`, usa comillas simples para literales, ASCII puro.
- **Python**: SangrÃ­a de 4 espacios, `snake_case`, sin dependencias externas.
- **HTML/CSV generados**: nunca los edites a mano; actualÃ­zalos mediante los scripts correspondientes.

---

## âœ… Verificaciones recomendadas

1. DespuÃ©s de modificar la tuberÃ­a, ejecuta el *cleaner* y revisa el log para confirmar los recuentos y el resumen H/I/J en el HTML generado.
2. Cambios de normalizaciÃ³n â†’ `pwsh -File tools/normalize-inventory-html.ps1 -HtmlPath docs/inventario_interactivo_offline.html` como *smoke test*.
3. Ajustes de hash o duplicados â†’ inspecciona `docs/hash_data.csv` y verifica las columnas `FullName`, `Hash`, `Length`, `Extension`, `Error`.

---

## ðŸ“¬ Commits y PRs

- Usa prefijos convencionales (`feat`, `fix`, `chore`, `docs`) con un alcance opcional (`fix(inventory): ...`).
- Los PRs deben resumir cambios, enlazar Trello/issues cuando aplique y adjuntar evidencias antes/despuÃ©s si se modifican HTML o CSV.

---

## ðŸ” Notas operativas

`docs/hash_data.csv` contiene rutas absolutas y tamaÃ±os. Solo compÃ¡rtelo con colaboradores de confianza. Los sanitizadores bloquean protocolos externos (acestream, http); extiende la blocklist si aparecen nuevos protocolos, en vez de deshabilitarla.

