# Discos-Analisis-Final

Sistema de inventario interactivo y analisis multimedia multiunidad con deteccion de duplicados, hashes opcionales y publicacion en GitHub Pages.

---

## Inicio rapido

Escanea, calcula hashes (opcional) y actualiza el inventario con un unico comando:

```pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1
```

Se abrira un dialogo para elegir las unidades (por ejemplo `C:`, `D:`, `J:`) y, si lo deseas, activar el calculo de hash SHA256.

### Flujo automatizado

| Etapa                   | Descripcion                                                                 |
| ----------------------- | --------------------------------------------------------------------------- |
| Seleccion de unidades   | Popup que detecta discos y permite elegir cuales procesar                   |
| Escaneo de archivos     | Recorre fotos, videos, audios y documentos en las unidades elegidas         |
| Calculo de hash         | (Opcional) SHA256 para identificar duplicados y cambios                     |
| Generacion de inventario| Exporta resultados a `docs/hash_data.csv` en lotes de 400 archivos          |
| Inyeccion HTML          | Actualiza `docs/inventario_interactivo_offline.html` con los datos nuevos   |
| Sincronizacion          | Ejecuta `tools/sync-to-github.ps1` -> pull con rebase seguro, commit y push |
| Publicacion             | Abre el inventario actualizado en el navegador y refresca GitHub Pages      |

### Casos de uso

- Escaneo rapido sin hash:
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "D,E" -OpenAfter
  ```
- Escaneo completo con hash:
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "C,F" -ComputeHash -OpenAfter -VerboseLog
  ```
- Solo regenerar la pagina (sin escanear de nuevo):
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync-to-github.ps1
  ```

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

## Concepto

El sistema combina automatizacion PowerShell con GitHub Pages para ofrecer una vista web interactiva de los archivos multimedia de multiples unidades, identificando duplicados, rutas, tamanos y tipos en tiempo real.

## Autor

Desarrollado por **Antonio Duran Mingorance**. Inspirado en la idea de un inventario multimedia universal, multiplataforma y autosincronizado.
