# Agent Playbook

Guía operativa para mantener el flujo autónomo del inventario **MingoMedia**.

---

## Arquitectura del repositorio

| Zona | Contenido | Notas |
| --- | --- | --- |
| Raíz | CSV y reportes (`index_by_hash.csv`, `inventory_by_folder.csv`) + scripts maestros. | Los artefactos se regeneran; evita ediciones manuales. |
| `tools/` | Automatizaciones reutilizables: escaneo, inyección HTML, empaquetado, helper DLNA. | Los entry points viven en `tools/agents/`. |
| `docs/` | Sitio público (HTML/JS/CSS, datos de hash y duplicados). | Trátalo como read-only; actualiza vía scripts. |

---

## Comandos esenciales

| Objetivo | Comando |
| --- | --- |
| Pipeline completo (hash → HTML → sanitize) | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/agents/inventory-cleaner.ps1 -RepoRoot . -SweepMode None` |
| Refrescar sólo `docs/hash_data.csv` | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/build-hash-data.ps1 -RepoRoot . -IndexPath index_by_hash.csv` |
| Regenerar analítica de duplicados | `python tools/generate_duplicates_table.py --input docs/hash_data.csv --output docs/duplicate_summary.json` |
| Escaneo guiado (con filtro) | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/scan-drives-interactive.ps1 -ContentFilter Media` |
| Escaneo sin publicar | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/scan-drives-interactive.ps1 -SkipPublish` |
| Servir archivos vía HTTP (LAN) | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/inventory-fileserver.ps1` |
| Helper DLNA opcional | `cd tools/dlna-helper && npm install && node server.js` |
| Generar paquete + `.exe` | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/make-inventory-package.ps1` |

Mantén los scripts idempotentes y sin rutas absolutas codificadas.

---

## Inventario MingoMedia

- El HTML publica el modal **Abrir con** con soporte para navegador local, Chromecast/AirPlay, DLNA, nueva pestaña y descarga.
- Preferencias de reproducción guardadas en `localStorage` (`auto`, `local`, `browser-picker`, `dlna:*`).
- Botón AirPlay en la cabecera sólo aparece en Safari cuando detecta destinos (`WebKitPlaybackTargetAvailabilityEvent`).
- Selector global incluye opciones DLNA que llegan por `/devices` (HTTP o WebSocket) desde `tools/dlna-helper`.
- El helper DLNA expone `/play` (HTTP) y espera `controlURL`, `mediaUrl`, `position` en el payload.
- `docs/assets/js/mingomedia-config.js` controla la puerta de acceso (`access.*`) y el almacenamiento de vistas por usuario (`view.*`).
- El store global `window.mingoInventory` expone `getState()`, `on(evento, handler)`, `setFilter()` y helpers similares; úsalo para integraciones o automatizaciones.
- El orden y ancho de columnas, filas ocultas, alturas personalizadas y la selección se persisten en `localStorage` con prefijo `view.storagePrefix` + usuario normalizado.
- Los overlays (`texto`, `audio`, `video`) pueden cerrarse con botón o clic fuera.
- `data-no-intercept` en cualquier contenedor evita que el listener global abra el modal.
- La barra superior incluye botón **Vista…** para ocultar/mostrar columnas, listar filas ocultas y resetear la vista completa.
- El banner bajo la tabla avisa de filas ocultas; desde ahí pueden restaurarse todas.
- Las filas tienen tirador vertical en la primera columna (drag) y doble clic para resetear altura; se puede trazar un recuadro para seleccionar (Ctrl/Cmd suma, Alt resta).

---

## Estilo y convenciones

- **PowerShell**: sangría 2 espacios, comandos `Verbo-Nombre`, ASCII puro.
- **Python**: PE8, 4 espacios, sin dependencias externas.
- **HTML/CSV generados**: nunca se editan a mano; usa los scripts.
- **JS del picker**: evita dependencias externas; mantener funciones puras y proteger contra falta de APIs (`Remote Playback`, `fetch`).

---

## Verificaciones recomendadas

1. Tras modificar la tubería, ejecuta el cleaner y revisa logs + resumen H/I/J del HTML.
2. Cambios de normalización → `pwsh -File tools/normalize-inventory-html.ps1 -HtmlPath docs/inventario_interactivo_offline.html`.
3. Ajustes de hash o duplicados → inspecciona `docs/hash_data.csv` (`FullName`, `Hash`, `Length`, `Extension`, `Tipo`).
4. Diferencias de visualización → abre el HTML generado, revisa el modal, overlays y la botonera de cast.
5. Releases → `tools/make-inventory-package.ps1`, prueba `InventoryCleaner.exe -SweepMode DryRun`, valida `releases/InventoryCleaner-package.zip`.
6. Servidor HTTP → con `inventory-fileserver.ps1` arriba, prueba `http://<host>:<puerto>/healthz` y descarga de archivos desde otra máquina.

---

## Notas operativas

- `docs/hash_data.csv` contiene rutas absolutas y tamaños: compártelo sólo con colaboradores de confianza.
- Los sanitizadores del HTML bloquean protocolos externos; amplía la blocklist en lugar de deshabilitarla.
- El merge de scans conserva la última ruta por hash/tamaño; usa `tools/merge-scans.ps1 -KeepDuplicates` para auditorías.
- `tools/scan-drives-interactive.ps1` publica automáticamente (commit + push). Usa `-SkipPublish` para revisar el diff antes.
- Duplica `inventory.config.sample.json` a `inventory.config.json` para ajustar `publicBaseUrl`, `listenerPrefixes` y `driveMappings`.
- El helper DLNA es opcional: si no se pasa `dlnaHelper/dlnaApi`, el UI oculta la acción.
- Mantén el repo limpio: nada de rutas absolutas, sin efectos fuera de `RepoRoot`, logs en `logs/`.
- Para cambiar el formulario de acceso o las listas permitidas edita `docs/assets/js/mingomedia-config.js`; no hardcodees credenciales en otros archivos.

---

## Roadmap sugerido

1. Autenticación básica + preferencias de vista (PIN/código y `localStorage`).
2. Controles tipo spreadsheet (selección múltiple, ocultar/mostrar columnas/filas, almacenamiento de orden).
3. Lista de reproducción para múltiples archivos seleccionados.

Trabaja cada fase en ramas separadas a partir de `main`.
