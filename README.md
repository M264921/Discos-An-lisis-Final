# 🧠 Discos-Análisis-Final

Sistema de inventario interactivo y análisis multimedia multiunidad con hash, duplicados y publicación automática en GitHub Pages.

---

## 🚀 Quickstart

**Escanear, hashear y actualizar inventario automáticamente**

```pwsh
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1
```

Esto lanzará una ventana gráfica para seleccionar las unidades que quieras analizar (ejemplo: `C:`, `D:`, `J:`) y opcionalmente marcar el cálculo de hash SHA256.

### ⚙️ Flujo automático

El proceso completo está totalmente automatizado:

| Etapa | Descripción |
| --- | --- |
| 🗂️ Selección de unidades | Popup interactivo que detecta discos y permite elegir cuáles analizar |
| 🔍 Escaneo de archivos | Busca fotos, vídeos, audios y documentos en cada unidad seleccionada |
| 🔢 Cálculo de hash (opcional) | SHA256 para identificar duplicados y cambios |
| 📊 Generación de inventario | Exporta resultados a `docs/hash_data.csv` (en bloques de 400 archivos) |
| 🧩 Inyección HTML | Actualiza automáticamente `docs/inventario_interactivo_offline.html` |
| ☁️ Sincronización | Ejecuta `tools/sync-to-github.ps1` → commit, push y rebuild de Pages |
| 🌐 Publicación | Se abre automáticamente el inventario actualizado en tu navegador |

### 🧭 Ejemplos prácticos

- **Escaneo rápido sin hash**
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "D,E" -OpenAfter
  ```
- **Escaneo completo con hash**
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\scan-drives-interactive.ps1 -Drives "C,F" -ComputeHash -OpenAfter -VerboseLog
  ```
- **Solo actualizar la página (sin reescanear)**
  ```pwsh
  pwsh -NoProfile -ExecutionPolicy Bypass -File tools\sync-to-github.ps1
  ```

---

## 📂 Estructura del repositorio

```
Discos-An-lisis-Final/
├─ docs/
│  ├─ inventario_interactivo_offline.html   # Inventario visual (GitHub Pages)
│  ├─ hash_data.csv                         # Datos de archivos escaneados
│  └─ assets/                               # CSS/JS del inventario
├─ tools/
│  ├─ scan-drives-interactive.ps1           # Script autónomo principal
│  ├─ inventory-inject-from-csv.ps1         # Inyector CSV → HTML
│  ├─ sync-to-github.ps1                    # Commit + push + rebuild Pages
│  └─ agents/                               # Herramientas auxiliares
└─ AGENTS.md                                # Guía avanzada y ejemplos
```

### 🧩 Archivos clave

| Archivo | Rol principal |
| --- | --- |
| `tools/scan-drives-interactive.ps1` | Escaneo y flujo completo |
| `tools/inventory-inject-from-csv.ps1` | Inserta datos CSV en HTML |
| `tools/sync-to-github.ps1` | Sube los cambios y fuerza rebuild |
| `docs/hash_data.csv` | Base de datos de resultados |
| `docs/inventario_interactivo_offline.html` | Vista interactiva final |
| `AGENTS.md` | Documentación técnica extendida |

---

## 🧠 Concepto

El sistema combina automatización PowerShell + GitHub Pages para crear una vista web interactiva de los archivos multimedia de tus discos, detectando duplicados, rutas, tamaños y tipos en tiempo real.

## 🧰 Autor

Desarrollado por **Antonio Durán Mingorance**.

💡 Inspirado en la idea de un inventario multimedia universal multiplataforma y autosincronizado.
