# Limpieza revisable

`tools/agents/inventory-cleaner.ps1 -SweepMode None` genera informes sin borrar
duplicados. `DryRun` previsualiza; `Apply` habilita expresamente la limpieza del
repositorio y de duplicados no multimedia. No se mueve automaticamente ninguna
unidad por su letra.

`python tools/remove_nonmedia_duplicates.py --csv ruta.csv` simula por defecto.
`--apply` elimina solo extensiones auxiliares admitidas con hashes actuales
coincidentes y conserva otra copia verificada. Rechaza grupos sin otra copia,
hashes obsoletos, rutas relativas y enlaces simbolicos. El CSV de log distingue
`Plan`, `Deleted` y errores; simular no acredita un borrado.

El traslado antiguo `Move-I-Duplicates.ps1` queda solo para previsualizar un CSV
historico con `-DriveLetter` explicita. Para movimientos nuevos sigue
`tools/media-dedup/STORAGE.md` e identifica los volumenes presentes antes de
generar el plan. H:, I: y J: historicas no identifican discos en otro ordenador.

Regresion con archivos ficticios:

```powershell
python -m unittest discover -s tests -p test_nonmedia_cleanup.py -v
```

Los inventarios de 42.320 y 38.116 registros se conservan por separado. Este
cambio no los fusiona ni borra o mueve archivos multimedia reales.
