# Discos-Analisis-Final

Sistema de inventario interactivo y analisis multimedia multiunidad con deteccion de duplicados, hashes opcionales y publicacion en GitHub Pages.

---

## Inicio rapido

Escanea, calcula hashes (opcional) y actualiza el inventario con un unico comando:

```pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1
```

El asistente detecta las unidades disponibles, permite elegirlas y pregunta el filtro de contenido (`Media`, `Otros`, `Todo`) antes de iniciar el escaneo.

Se abrira un dialogo para elegir las unidades (por ejemplo `C:`, `D:`, `J:`) y, si lo deseas, activar el calculo de hash SHA256.

### Flujo automatizado

| Etapa                   | Descripcion                                                                 |
| ----------------------- | --------------------------------------------------------------------------- |
| Seleccion de unidades   | Popup que detecta discos y permite elegir cuales procesar                   |
| Filtro de contenido     | Selector `Media` / `Otros` / `Todo` para limitar los tipos de archivo        |
| Escaneo de archivos     | Recorre las carpetas aplicando el filtro y captura extension/tipo           |
| Calculo de hash         | (Opcional) SHA256 para identificar duplicados y cambios                     |
| Generacion de inventario| Exporta resultados a `docs/hash_data.csv` en lotes de 400 archivos          |
| Inyeccion HTML          | Actualiza `docs/inventario_interactivo_offline.html` con los datos nuevos   |
| Sincronizacion          | Ejecuta `tools/sync-to-github.ps1` -> pull con rebase seguro, commit y push |
| Publicacion             | Abre el inventario actualizado en el navegador y refresca GitHub Pages      |

### Casos de uso

- Escaneo rapido sin hash:
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "D,E" -ContentFilter Todo -OpenAfter
  ```
- Escaneo completo con hash:
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "C,F" -ComputeHash -ContentFilter Media -OpenAfter -VerboseLog
  ```
- Solo regenerar la pagina (sin escanear de nuevo):
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync-to-github.ps1
  ```

### Inventario interactivo

- Columnas arrastrables y con ancho ajustable; usa `Reiniciar columnas` para volver a la configuracion por defecto.
- Iconos de tipo (`📷`, `🎬`, `🎧`, `📄`) segun la categoria detectada o la extension.
- Selector de paginacion (25, 50, 100, 250, Todo) y contador de rango visible.
- Boton `Descargar CSV` exporta los resultados filtrados respetando el orden de columnas.
- Clic en `Nombre` abre el archivo local (`file:///...`) y clic en `Ruta` abre la carpeta de Windows Explorer.

---

## Estructura del repositorio

- `docs/`
  - `inventario_interactivo_offline.html` (inventario visual)
  - `hash_data.csv` (datos de archivos escaneados)
  - `assets/` (CSS y JS del inventario)
- `tools/`
  - `scan-drives-interactive.ps1` (script principal)
  - `inventory-inject-from-csv.ps1` (inyector CSV -> HTML)
  - `sync-to-github.ps1` (commit + push + rebuild Pages)
  - `agents/` (herramientas auxiliares)
- `AGENTS.md` (guia operativa extendida)

### Archivos clave

| Archivo                               | Rol principal                       |
| ------------------------------------- | ----------------------------------- |
| `tools/scan-drives-interactive.ps1`   | Escaneo y orquestacion completa    |
| `tools/inventory-inject-from-csv.ps1` | Inserta datos CSV en el HTML       |
| `tools/sync-to-github.ps1`            | Sube los cambios y fuerza rebuild  |
| `docs/hash_data.csv`                  | Datos de inventario                 |
| `docs/inventario_interactivo_offline.html` | Vista interactiva final          |
| `AGENTS.md`                           | Documentacion tecnica avanzada      |

---

## Distribucion

1. **Paquete base (`dist/`)**  
   ```pwsh
   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\build-dist.ps1
   ```  
   Genera `dist\latest\` con `tools\`, `docs\` y `logs\` minimos (o `dist\yyyyMMdd-HHmmss\` con `-Timestamp`).

2. **Ejecutable Windows listo para compartir**  
   ```pwsh
   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\make-inventory-package.ps1
   ```  
   Este script orquesta `build-dist`, crea un lanzador `InventoryCleaner.ps1` y lo compila a `InventoryCleaner.exe` con PS2EXE.  
   Los artefactos resultantes se copian a:
   - `dist\latest\InventoryCleaner.exe` (ejecutable standalone, requiere PowerShell 7 instalado en el equipo destino).  
   - `releases\InventoryCleaner.exe` y `releases\InventoryCleaner-package.zip` (lista para adjuntar en GitHub Releases).

3. **Uso en otro equipo**  
   - Descomprime `InventoryCleaner-package.zip` o copia la carpeta `dist\latest`.  
   - Ejecuta `InventoryCleaner.exe` (opcional: `InventoryCleaner.exe -SweepMode DryRun` para validar sin aplicar).  
   - El ejecutable invoca internamente `tools\agents\inventory-cleaner.ps1` manteniendo la estructura del paquete.

> **Notas**: PS2EXE se instala automáticamente la primera vez. Si prefieres producir un instalador MSI/MSIX, reutiliza la carpeta `dist\latest` como payload.

---

## Concepto

El sistema combina automatizacion PowerShell con GitHub Pages para ofrecer una vista web interactiva de los archivos multimedia de multiples unidades, identificando duplicados, rutas, tamanos y tipos en tiempo real.

## Autor

Desarrollado por **Antonio Duran Mingorance**. Inspirado en la idea de un inventario multimedia universal, multiplataforma y autosincronizado.
