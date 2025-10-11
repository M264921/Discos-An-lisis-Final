# MingoMedia · Multimedia Mingorance

Inventario multimedia autoservicio con visores universales, soporte DLNA/Chromecast/AirPlay y publicación directa en GitHub Pages.

---

## Panorama general

| Recurso | Descripción |
| --- | --- |
| `docs/` | Sitio estático servido por Pages (HTML, CSS, JS y datos). |
| `tools/` | Scripts PowerShell para escaneo, generación de datos y empaquetado. |
| `tools/dlna-helper/` | Helper opcional (Node.js) para descubrir renderers DLNA y exponer `/play`. |
| `inventory.config.sample.json` | Plantilla de configuración para `inventory-fileserver.ps1`. |

---

## Flujo habitual

1. **Escaneo interactivo**
   ```pwsh
   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1
   ```
   - Detecta unidades y permite elegirlas.
   - Opcionalmente calcula SHA256 por lote.
   - Genera `docs/hash_data.csv` y actualiza el HTML.
   - Puede lanzar `tools/sync-to-github.ps1` para publicar en Pages.

2. **Sincronizar sin escanear**
   ```pwsh
   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync-to-github.ps1
   ```
   Reinyecta los datos existentes y realiza commit + push.

3. **Servir archivos en LAN** (opcional)
   ```pwsh
   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\inventory-fileserver.ps1
   ```
   - Configura `inventory.config.json` con `publicBaseUrl`, `driveMappings` y `listenerPrefixes`.
   - Los enlaces de la columna **Nombre** pasan a usar `http://host/files/<unidad>/...` cuando el servidor responde.

4. **Helper DLNA** (opcional)
   ```bash
   cd tools/dlna-helper
   npm install
   node server.js
   ```
   Publica `/devices` y `/play` (HTTP + WS) para poblar el selector DLNA del UI.

---

## Inventario interactivo (Pages)

- **Identidad**: el sitio se muestra como **MingoMedia** tanto en Pages como offline.
- **Visor universal** (modal "Abrir con"):
  - Navegador local, Chromecast/AirPlay, DLNA, nueva pestaña y descarga directa.
  - Preferencia global guardada en `localStorage`.
- **Acceso configurable**:
  - `docs/assets/js/mingomedia-config.js` permite exigir correo y PIN antes de cargar el inventario.
  - Sesiones opcionales en `localStorage` para no repetir el formulario.
- **Visores integrados**:
  - Imagen / PDF / HTML → pestaña nueva u overlay según tipo.
  - Texto → overlay con `<pre>` + botón de descarga.
  - Audio / vídeo → overlay ligero con `<audio>/<video>`.
- **Cast**:
  - Chromecast/AirPlay usa Remote Playback API; se oculta en navegadores sin soporte.
  - Botón AirPlay visible sólo en Safari cuando hay destinos.
- **DLNA**:
  - Actívalo pasando `?dlnaHelper=ws://host:8787&dlnaApi=http://host:8787` o definiendo defaults en el UI.
  - La acción DLNA dispara `POST /play` contra el helper opcional.
- **Tabla**:
  - Columnas arrastrables con ancho ajustable y filtros por columna.
  - Descarga CSV del resultado filtrado y paginación configurable.
  - Selección con casillas por fila (persistente por usuario) y contador en la barra.
  - `Ctrl/Cmd + clic` y botón medio mantienen el comportamiento nativo (sin modal).

### Configuración de acceso y preferencias

`docs/assets/js/mingomedia-config.js` expone dos secciones:

```js
window.MingoMediaConfig = {
  access: {
    enabled: true,
    requireEmail: true,
    requirePin: true,
    pin: "1234",             // PIN global opcional
    allowedEmails: ["admin@mingomedia.local"],
    allowedDomains: ["familia.local"],
    users: [{ email: "ana@familia.local", pin: "7777" }],
    rememberSession: true,
    version: "2025-10-10"
  },
  view: {
    storagePrefix: "mingomedia.inventory.view",
    defaultUser: "public"
  }
};
```

- **`access`** controla la puerta de entrada (correo obligatorio, PIN global o por usuario y lista blanca de dominios/correos).
- **`view`** define la clave base usada en `localStorage` para guardar el orden de columnas, anchos, filas ocultas, alturas y selección.
- Los datos de vista se aíslan por usuario: el correo validado se normaliza y se usa como sufijo (`<prefijo>:<usuario>`).
- El formulario respeta `rememberSession`; si es `false` se solicitarán credenciales en cada visita.

El estado de la tabla y los filtros se exponen vía `window.mingoInventory`, un store con métodos como `getState()`, `on(evento, handler)` o `setFilter(columna, valor)`, útil para integraciones futuras.

---

## Scripts principales

| Script | Propósito |
| --- | --- |
| `tools/scan-drives-interactive.ps1` | Orquestador: escaneo, hash opcional, merge y regeneración de HTML. |
| `tools/build-hash-data.ps1` | Reprocesa `index_by_hash.csv` a `docs/hash_data.csv`. |
| `tools/inventory-fileserver.ps1` | Servidor HTTP para exponer archivos en LAN. |
| `tools/make-inventory-package.ps1` | Construye paquete distribuible + `InventoryCleaner.exe`. |
| `tools/dlna-helper/server.js` | Mini servicio DLNA (Node.js + HTTP/WS). |

---

## Tips operativos

1. Tras tocar la tubería, ejecuta el cleaner y revisa los logs de PowerShell.
2. Usa `tools/normalize-inventory-html.ps1` como smoke test del HTML.
3. Revisa `docs/hash_data.csv` cuando modifiques hashing o duplicados.
4. Antes de publicar un release, genera el paquete (`tools/make-inventory-package.ps1`) y prueba `InventoryCleaner.exe -SweepMode DryRun`.
5. Mantén `docs/` sólo a través de scripts; evita ediciones manuales en Pages.

---

## Licencia y contacto

Proyecto mantenido por **Antonio Durán Mingorance**. Preguntas y sugerencias vía issues o contacto directo.
