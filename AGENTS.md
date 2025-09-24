# Repository Guidelines

## Project Structure & Module Organization
- `docs/` aloja la versión publicada en GitHub Pages (`index.html` como portal y los anexos interactivos `Listado_*.html`).
- `tools/` guarda la automatización; `generate_duplicates_table.py` produce la tabla de duplicados y `Generate-HIJ-Report.ps1` orquesta el empaquetado.
- Ficheros de datos (`index_by_hash.*`, `dupes_confirmed.csv`) y registros históricos (`logs_*`) viven en la raíz; mantén derivados bajo `docs/` o `logs_*/` para no mezclar fuentes.

## Build, Test, and Development Commands
- `pwsh ./tools/Generate-HIJ-Report.ps1` regenera la web localmente sin tocar Git.
- `pwsh ./tools/Generate-HIJ-Report.ps1 -Push` añade commit + push tras reconstruir todo (pide confirmación en consola).
- `python tools/generate_duplicates_table.py` refresca el explorador de duplicados; acepta `--source` y `--target` para rutas alternativas.

## Coding Style & Naming Conventions
- Python: sangría de 4 espacios, funciones en `snake_case`, usa type hints y f-strings como en `generate_duplicates_table.py`.
- PowerShell: funciones en PascalCase, `Set-StrictMode -Version Latest`, módulos con comment-based help y `Write-Verbose` para logs opcionales.
- HTML/CSS: textos en castellano claro, emojis coherentes con los árboles interactivos y assets embebidos para no depender de rutas externas.

## Testing Guidelines
- Tras generar duplicados, abre `docs/Listado_Duplicados_interactivo.html` y prueba filtros, ordenación y enlaces `Abrir`/`Copiar`.
- Ejecuta `pwsh ./tools/Generate-HIJ-Report.ps1 -Preview` (flag que genera sin push) y sirve `docs/` con `python -m http.server 8000` para validar rutas.
- Revisa `logs_*/report-build-status` tras cada ejecución; conserva los TXT relevantes en el árbol de logs.

## Commit & Pull Request Guidelines
- Procura seguir Conventional Commits (`chore(docs): publicar informe y anexos` es la referencia más reciente) y resume cambios en castellano.
- Describe la procedencia de los datos actualizados, adjunta captura o GIF cuando cambie la UI e incluye la URL de Pages verificada.
- Relaciona issues al abrir PR y señala si se tocaron inventarios H/I/J o cuarentenas para mantener trazabilidad.

## Seguridad & Deployment Tips
- GitHub Pages publica desde `docs/` en la rama `main`; evita subir rutas UNC o credenciales y añade `.gitignore` a dumps temporales.
- Antes de hacer público un volcado, comprueba que los enlaces `file:///` se limitan a unidades locales sin información sensible.
