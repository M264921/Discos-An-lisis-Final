# Flujos anteriores que se conservan

La aplicación recomendada es [MingoMedia para Windows](MINGOMEDIA-WINDOWS.md).
Las siguientes herramientas siguen en el repositorio por sus consumidores,
formatos de datos o funciones específicas; no forman un segundo instalador actual.

## Inventarios y páginas históricas

- `index_by_hash.csv`, `docs/hash_data.csv`, `docs/inventory/` y las variantes
  JSON/gzip conservan conjuntos de inventario. No deben fusionarse por su fecha.
- `dupes_confirmed.csv`, los CSV de borrados/movimientos y los índices de carpetas
  conservan trazabilidad. Una ruta registrada no demuestra que el archivo exista
  actualmente ni que su unidad esté conectada.
- Los HTML sin sufijo `.bak` se conservan como visores y salidas de generadores.
  `docs/index.html` es la entrada de Pages; los archivos HTML antiguos pueden
  contener sus propios datos embebidos.
- Las variantes `data/` y `docs/data/` no se sustituyen entre sí automáticamente.
  Comprime solo el JSON elegido con `tools/sync-inventory-data.ps1 -JsonPath ...`.

## Escaneo y generación PowerShell

`tools/scan-drives-interactive.ps1`, `tools/test-drive.ps1` y los asistentes
`run-inventory-wizard*.ps1` conservan selección e inventarios anteriores. Requieren
las herramientas indicadas en sus parámetros y producen archivos en el repositorio.
No los ejecutes como comprobación rutinaria.

```powershell
# Ejecución voluntaria: elegir unidades y generar resultados sin publicar.
pwsh -NoProfile -File tools/scan-drives-interactive.ps1 -SkipPublish
```

El escáner anterior puede publicar mediante commit y push si no se utiliza
`-SkipPublish`. `tools/sync-to-github.ps1` y su variante de la raíz mantienen ese
flujo; para cambios de código usa una rama, revisa el diff y publica por PR.

`tools/agents/inventory-cleaner.ps1` sigue regenerando informes. Su modo por
defecto `None` no retira duplicados; `DryRun` simula la retirada anterior de
auxiliares y `Apply` activa el borrado permanente de ese flujo. Consulta
[CLEANUP.md](CLEANUP.md) antes de utilizarlo.

Los nombres `Reindex-HIJ`, `Rebuild-HIJ-Inventory`, `Generate-HIJ-Report` y
`Move-I-Duplicates` corresponden a datos de equipos anteriores. Sus letras
históricas no identifican volúmenes en otro ordenador. No se usan como entrada
del asistente actual; para un trabajo nuevo utiliza selección de unidades o
[media-dedup](tools/media-dedup/STORAGE.md), con identidad de volumen.

## Otras interfaces y servicios

- `tools/MingoMedia_inventory_gui.py`: GUI anterior con PySimpleGUI opcional y
  formato `data/gui/`. Tiene pruebas de almacenamiento; no se incluye en el
  instalador actual ni es necesaria para usarlo.
- [CLI Python](README.md#desarrollo-y-comprobaciones): paquete
  `discos_analisis` y comando `discos-enrich`. El enriquecimiento con un proveedor
  externo es opcional y requiere configurar el entorno fuera del repositorio.
- [Visor privado](tools/README-inventory-remote.md): puede arrancarse por separado
  para un inventario existente. El asistente actual lo gestiona automáticamente.
- `tools/inventory-fileserver.ps1`: servicio anterior para archivos en LAN;
  no equivale al enlace privado HTTPS del asistente.
- `tools/dlna-helper/`: servicio Node.js opcional para dispositivos DLNA de la LAN.
  Conserva `package.json` y su lockfile; no es una dependencia del instalador.
- `tools/build-dist.ps1` y `tools/make-inventory-package.ps1`: generación anterior
  de paquetes de scripts. Pueden requerir PS2EXE y copiar inventarios al paquete;
  no deben utilizarse para distribuir la aplicación privada actual.

## Retiradas

Las migraciones puntuales, publicadores duplicados, paquetes antiguos, notas de
conversaciones y backups retirados figuran en
[REPOSITORY-MAINTENANCE.md](REPOSITORY-MAINTENANCE.md). Pueden consultarse en el
historial de Git si hacen falta para una investigación.
