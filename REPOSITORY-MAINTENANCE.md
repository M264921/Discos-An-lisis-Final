# Revisión del repositorio · 15 de octubre de 2026

Se retiran 53 archivos (10.97 MB) del árbol actual.
Se conservan en el historial de Git. No se reescribe el historial ni se eliminan archivos de las unidades analizadas.

La edad no determina la retirada: se revisaron referencias, sustitutos actuales y efectos de las herramientas.

## Archivos retirados

### Copias de seguridad ya cubiertas por Git

- `docs/assets/inventario.css.bak`
- `docs/assets/inventario.js.bak`
- `docs/assets/inventario.js.bak_20251005145649`
- `docs/assets/inventario.js.bak_20251005150324`
- `docs/assets/inventario.js.bak_20251008191514`
- `docs/assets/inventario.js.bak_20251008191529`
- `docs/inventario_pro_offline.html.bak_20251013-201018`
- `tools/_backup_20251007_001837/inventory-inject-from-csv.ps1`
- `tools/_backup_20251007_001837/scan-drives-interactive.ps1`
- `tools/inventory-inject-from-csv.ps1.bak`
- `tools/normalize-inventory-html.ps1.bak.20251008-204212`
- `tools/scan-drives-interactive.backup.ps1`

### Publicadores duplicados, sustituidos por Git y sync-to-github

- `tools/push-repo.ps1`
- `tools/push-repo-simple.ps1`
- `tools/push-repo-safe.ps1`
- `tools/push-repo-Branch-main-simple.ps1`
- `tools/toolspush-repo.ps1`

### Migraciones puntuales de 2025, sin consumidores activos

- `tools/fix-and-run.ps1`
- `tools/fix-and-reskin.ps1`
- `tools/fix-and-push-large-files.ps1`
- `tools/fix-inventory-json.ps1`

### Escaneos y traslados antiguos con letras fijas, sustituidos por el asistente y media-dedup

- `hybrid_dedup.ps1`
- `identify-duplicates.ps1`
- `move-duplicates.ps1`
- `move_duplicates.ps1`
- `test-drive-j.ps1`
- `test-inventario.ps1`
- `tools/quick-scan.ps1`
- `tools/inventory.ps1`

### Utilidades retiradas por efectos inesperados o destinos inexistentes

- `tools/agents/repo-sweep.ps1`
- `tools/repo-clean-core.ps1`
- `tools/rebuild-inventory.ps1`
- `tools/self-test.ps1`

### Generadores placeholder y automatizacion que vaciaban el inventario

- `tools/regen_inventory_json_gz.py`
- `data/python crear_gzip.py`
- `.github/workflows/update-inventory-gz.yml`

### Paquetes generados antiguos; las descargas actuales estan en Releases

- `releases/InventoryCleaner.exe`
- `releases/InventoryCleaner-package.zip`
- `releases/InventoryCleaner.ps1`

### Notas, catalogos MCP inactivos y configuraciones de ejemplo sin consumidores

- `tools/Sin título.txt`
- `Cómo usarlo.txt`
- `docs/Codex/codex resume I.txt`
- `docs/Codex/codex resume J.txt`
- `docs/Codex/codex resune H.txt`
- `docs/mcp/agents.json`
- `docs/mcp/resources.json`
- `docs/mcp/tools.json`
- `sample_keys.json`
- `.safety.patch`

### Reglas y entorno redundantes, centralizados en la raiz y CI Python

- `tools/.gitattributes`
- `tools/.gitignore`
- `.github/workflows/python-package-conda.yml`
- `environment.yml`

## Archivos conservados

- Inventarios CSV, JSON y gzip, índices de carpetas y visores sin sufijo de backup: contienen datos históricos o siguen siendo entradas y salidas de las herramientas.
- Registros de retiradas y movimientos: documentan operaciones anteriores; no se confunden con archivos temporales.
- Generadores PowerShell, GUI Python anterior, CLI, helper DLNA y media-dedup: mantienen funciones propias o compatibilidad. Consulta [LEGACY.md](LEGACY.md) y [tools/README.md](tools/README.md).
- Los archivos de Git LFS conservan sus reglas y contenido. Esta revisión no regenera inventarios ni unifica conjuntos históricos.

## Mantenimiento actualizado

- README y guía de agentes centrados en MingoMedia para Windows, visor privado, contraseña mínima de ocho caracteres y revisión de duplicados con Papelera.
- Reglas de texto y binarios centralizadas en `.gitattributes`; ignores para resultados locales, backups, entornos y configuraciones privadas.
- Comprobaciones de Python, JavaScript, enlaces de documentación y sintaxis PowerShell. No se considera un éxito la ausencia de pruebas.
- El empaquetado de Windows puede validar cambios de mantenimiento sin reemplazar una versión ya publicada. Los cambios de código o recursos empaquetados requieren incrementar VERSION.
- El cleaner anterior ya no llama al barrido que movía archivos en DryRun. Se mantiene su simulación de duplicados no multimedia y el modo Apply explícito.
