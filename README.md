﻿# ðŸ§  Discos-AnÃ¡lisis-Final

Sistema de inventario interactivo y anÃ¡lisis multimedia multiunidad con hash, duplicados y publicaciÃ³n automÃ¡tica en GitHub Pages.

---

## ðŸš€ Quickstart

**Escanear, hashear y actualizar inventario automÃ¡ticamente**

```pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1
```

Esto lanzarÃ¡ una ventana grÃ¡fica para seleccionar las unidades que quieras analizar (ejemplo: `C:`, `D:`, `J:`) y opcionalmente marcar el cÃ¡lculo de hash SHA256.

### âš™ï¸ Flujo automÃ¡tico

El proceso completo estÃ¡ totalmente automatizado:

| Etapa | DescripciÃ³n |
| --- | --- |
| ðŸ—‚ï¸ SelecciÃ³n de unidades | Popup interactivo que detecta discos y permite elegir cuÃ¡les analizar |
| ðŸ” Escaneo de archivos | Busca fotos, vÃ­deos, audios y documentos en cada unidad seleccionada |
| ðŸ”¢ CÃ¡lculo de hash (opcional) | SHA256 para identificar duplicados y cambios |
| ðŸ“Š GeneraciÃ³n de inventario | Exporta resultados a `docs/hash_data.csv` (en bloques de 400 archivos) |
| ðŸ§© InyecciÃ³n HTML | Actualiza automÃ¡ticamente `docs/inventario_interactivo_offline.html` |
| â˜ï¸ SincronizaciÃ³n | Ejecuta `tools/sync-to-github.ps1` â†’ pull (rebase seguro) + commit + push + rebuild de Pages |
| ðŸŒ PublicaciÃ³n | Se abre automÃ¡ticamente el inventario actualizado en tu navegador |

### ðŸ§­ Ejemplos prÃ¡cticos

- **Escaneo rÃ¡pido sin hash**
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "D,E" -OpenAfter
  ```
- **Escaneo completo con hash**
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "C,F" -ComputeHash -OpenAfter -VerboseLog
  ```
- **Solo actualizar la pÃ¡gina (sin reescanear)**
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync-to-github.ps1
  ```

---

## ðŸ“‚ Estructura del repositorio

```
Discos-An-lisis-Final/
â”œâ”€ docs/
â”‚  â”œâ”€ inventario_interactivo_offline.html   # Inventario visual (GitHub Pages)
â”‚  â”œâ”€ hash_data.csv                         # Datos de archivos escaneados
â”‚  â””â”€ assets/                               # CSS/JS del inventario
â”œâ”€ tools/
â”‚  â”œâ”€ scan-drives-interactive.ps1           # Script autÃ³nomo principal
â”‚  â”œâ”€ inventory-inject-from-csv.ps1         # Inyector CSV â†’ HTML
â”‚  â”œâ”€ sync-to-github.ps1                    # Commit + push + rebuild Pages
â”‚  â””â”€ agents/                               # Herramientas auxiliares
â””â”€ AGENTS.md                                # GuÃ­a avanzada y ejemplos
```

### ðŸ§© Archivos clave

| Archivo | Rol principal |
| --- | --- |
| `tools/scan-drives-interactive.ps1` | Escaneo y flujo completo |
| `tools/inventory-inject-from-csv.ps1` | Inserta datos CSV en HTML |
| `tools/sync-to-github.ps1` | Sube los cambios y fuerza rebuild |
| `docs/hash_data.csv` | Base de datos de resultados |
| `docs/inventario_interactivo_offline.html` | Vista interactiva final |
| `AGENTS.md` | DocumentaciÃ³n tÃ©cnica extendida |

---

## ðŸ§  Concepto

El sistema combina automatizaciÃ³n PowerShell + GitHub Pages para crear una vista web interactiva de los archivos multimedia de tus discos, detectando duplicados, rutas, tamaÃ±os y tipos en tiempo real.

## ðŸ§° Autor

Desarrollado por **Antonio DurÃ¡n Mingorance**.

ðŸ’¡ Inspirado en la idea de un inventario multimedia universal multiplataforma y autosincronizado.

