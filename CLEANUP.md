# Limpieza y duplicados

## Aplicación de Windows

El flujo recomendado está en [MingoMedia para Windows](MINGOMEDIA-WINDOWS.md).
Después del análisis, **Revisar duplicados…** compara el contenido, permite marcar
grupos y cambiar la copia conservada. El resumen identifica todas las rutas y
unidades antes de confirmar.

Las copias sobrantes se envían a la Papelera con RecycleItem. La copia conservada
se protege durante el proceso; cambios, errores y unidades incompatibles producen
omisiones documentadas. No hay alternativa de borrado permanente. La Papelera no
se vacía automáticamente.

## Herramientas anteriores

`tools/agents/inventory-cleaner.ps1 -SweepMode None` regenera informes a partir de
los datos existentes, sin retirar duplicados. No es una comprobación del repositorio:
modifica sus salidas generadas. `DryRun` simula la retirada de duplicados no
multimedia y `Apply` activa expresamente ese flujo anterior.

`python tools/remove_nonmedia_duplicates.py --csv ruta.csv` simula por defecto.
`--apply` **borra permanentemente** extensiones auxiliares admitidas; exige hashes
actuales coincidentes y otra copia verificada. No es el mecanismo de la aplicación
de Windows. No lo ejecutes sobre datos reales para probar código.

El cleaner ya no llama al barrido antiguo que movía archivos en DryRun.
`tools/Move-I-Duplicates.ps1` queda para previsualizar un CSV histórico con una
letra explícita. Para catálogos, movimientos y restauraciones nuevos consulta la
[guía de almacenamiento](tools/media-dedup/STORAGE.md), que identifica volúmenes.

## Limpieza del código

Las retiradas se documentan en [REPOSITORY-MAINTENANCE.md](REPOSITORY-MAINTENANCE.md).
No se eliminan inventarios ni registros de operaciones por ser antiguos. Git
conserva los archivos retirados en su historial; los backups y paquetes nuevos
se mantienen fuera del control de versiones.

Comprueba cambios con pruebas de archivos ficticios:

```powershell
python -m unittest discover -s tests -p test_mingomedia_duplicates.py -v
python -m unittest discover -s tests -p test_nonmedia_cleanup.py -v
```
