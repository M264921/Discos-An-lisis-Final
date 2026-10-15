# Mapa de herramientas

## Aplicación actual de Windows

| Archivo | Función |
| --- | --- |
| `mingomedia_desktop.py` | Asistente Tk y entrada del EXE. |
| `mingomedia_core.py` | Unidades disponibles, escaneo, catálogo y enlace privado. |
| `mingomedia_duplicates.py` | Grupos por contenido, elección de copia y ejecución del plan confirmado. |
| `mingomedia_duplicates_ui.py` | Marcado de grupos, elección manual y resumen de rutas. |
| `mingomedia_recycle.py` | Protección de archivos y API de Papelera, sin borrado permanente alternativo. |
| `inventory_remote.py` | Servidor privado con contraseña y acceso a archivos del análisis. |
| `build-mingomedia-windows.py`, `windows/` | EXE, ZIP portable e instalador. |

Consulta la [guía del programa](../MINGOMEDIA-WINDOWS.md) para ejecutar o compilar.
El programa empaquetado no necesita instalar estas dependencias en el equipo final.

## Visor web y generadores

| Fuentes o scripts | Salidas / función |
| --- | --- |
| `templates/inventory-drive-links.js`, `sync-drive-links.ps1` | Enlaces según unidades disponibles, sincronizados con las páginas existentes. |
| `templates/inventory-preview.js`, `sync-file-preview.py` | Vistas previas y apertura de archivos en los visores. |
| `inventory-loader.template.js`, `repair-inventory-loader.ps1` | Cargador publicado en `docs/assets/inventory-loader.js`. |
| `sync-inventory-data.ps1` | Valida un JSON elegido y actualiza su `.gz` sin sustituir el contenido por un ejemplo. |
| `build-inventory-html.ps1`, `templates/inventory_*` | Generación de HTML offline. |
| `build-hash-data.ps1`, `csv-to-inventory-json.ps1`, `merge-scans.ps1` | Transformación de inventarios anteriores. |
| `make_inventory_offline.ps1`, `agents/make-inventory-offline-wrapper.ps1` | Orquestación y posprocesado de HTML histórico. |

Los recursos dentro de `docs/` son salidas publicadas. Revisa el script antes de
sincronizar: algunos actualizan varias páginas o datos históricos. No los ejecutes
para una modificación de README o reglas Git.

## Comprobaciones sin escaneo

```powershell
python tools/check-repository.py
pwsh -NoProfile -File tools/check-powershell-syntax.ps1
python -m pytest
node --test tests/drive-links.test.cjs tests/inventory-loader.test.cjs
```

Ejecuta estos comandos desde la raíz del repositorio. Comprueban estructura,
documentación, sintaxis y fixtures; no limpian discos ni publican inventarios.

## Compatibilidad y servicios opcionales

[LEGACY.md](../LEGACY.md) explica las herramientas PowerShell anteriores, la GUI
con PySimpleGUI, los paquetes InventoryCleaner y las salidas históricas.
[media-dedup/STORAGE.md](media-dedup/STORAGE.md) describe catálogos, movimientos y
restauraciones por identidad de volumen. El helper `dlna-helper/` es opcional y
tiene sus propias dependencias Node.js.
