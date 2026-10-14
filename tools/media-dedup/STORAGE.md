# Unidades portables

Este modulo vive en `tools/media-dedup/` dentro del repositorio
Discos-An-lisis-Final. Los puntos de entrada mantenidos estan en `scripts/`.
El repositorio independiente media-dedup ya no existe; se conserva aqui
el flujo portable, sin copiar inventarios, logs ni planes historicos.

## Identificar las unidades de este equipo

Desde `tools/media-dedup/`, con PowerShell 7:

```powershell
./scripts/Get-MediaStorage.ps1 | Format-Table Root,Label,DriveType,BusType,VolumeSerial,Ready,IsSystem
```

Solo consulta metadatos. Enumera discos fijos y extraibles y sus puntos de
montaje; no incluye unidades opticas ni redes. Las particiones sin montar
aparecen como no disponibles. El escaneo automatico excluye las particiones
de sistema/arranque/ocultas. Si Windows deniega la consulta, muestra las
unidades montadas con una advertencia y bloquea la creacion de catalogos
portables hasta que pueda consultar su identidad.

## Seleccionar los discos que contienen los medios

La configuracion predeterminada descubre los discos disponibles en cada
equipo. Se puede limitar a determinados volumenes registrando sus rutas
actuales. Ejemplo (sustituir las rutas por las mostradas en ese equipo):

```powershell
./scripts/Register-MediaStorage.ps1 -SourceRoots 'K:\','L:\' -DestinationRoot 'L:\media_final'
```

Guarda `storage-bindings.json` junto a `config.psd1`. Solo escribe esa
configuracion: no crea la carpeta destino ni escanea. Los enlaces guardan
el numero de serie del volumen, no su letra ni su etiqueta; pueden copiarse
al otro equipo. Si el disco pasa de H: a J:, se resuelve su ruta actual.
Un volumen reformateado cambia de identidad y debe registrarse de nuevo.
Un disco ausente, bloqueado o con identidad duplicada provoca un error:
no se sustituye por otra unidad que tenga la misma etiqueta o letra.

El destino debe existir antes de consolidar. Tambien se puede indicar una
ruta concreta con `-DestRoot`; al omitirla no se presupone I: ni se elige
automaticamente otro disco.

## Inventarios antiguos con H:/I:/J:

Una letra antigua no permite averiguar a que disco correspondia. Asociarla
una vez con el volumen correcto, mientras esta conectado:

```powershell
./scripts/Register-MediaStorage.ps1 -LegacyDriveMap @{ H='K:\'; I='L:\' }
```

Las rutas con esas letras se resuelven por la identidad registrada, aunque
la letra antigua exista ahora y corresponda a otro disco. Los catalogos
nuevos guardan `VolumeSerial` y `RelativePath` en cada registro y no
necesitan estas asociaciones. Para datos sin identidad ni asociacion, las
rutas explicitas se conservan; se verifica SHA256 antes de copiar o mover.

## Flujo de analisis y ensayo

Crear nombres de salida nuevos para conservar los inventarios anteriores:

```powershell
# Este comando SI escanea los origenes seleccionados y calcula SHA256.
./scripts/New-MediaCatalog.ps1 -OutCsv ./artifacts/catalog-new.csv
./scripts/Find-MediaDuplicates.ps1 -CatalogCsv ./artifacts/catalog-new.csv -OutCsv ./artifacts/duplicates-new.csv
./scripts/Consolidate-MediaFinal.ps1 -CatalogCsv ./artifacts/catalog-new.csv -DuplicatesCsv ./artifacts/duplicates-new.csv -PlanOnly -LogCsv ./logs/plan-new.csv
```

`New-MediaCatalog.ps1` tambien admite carpetas especificas con
`-SourceRoots`, ademas de `-MaxItems` y `-MinSizeBytes`. Omite enlaces y
directorios de sistema/cuarentena. El plan de duplicados conserva la
primera ruta encontrada por SHA256 y mantiene las demas como duplicadas;
no mueve archivos.

La consolidacion y `Move-Duplicates.ps1` usan simulacion por defecto.
Una ejecucion real exige `-DryRun:$false`; mover exige tambien `-Move`
en la consolidacion. No ejecutar movimientos reales sin revisar el plan
y disponer de una copia de seguridad. `Move-Duplicates.ps1` exige que el
archivo conservado exista y verifica ambos hashes antes de un movimiento
real. `Undo-Duplicates.ps1` tambien simula por defecto.

Las copias nunca sobrescriben otro archivo. Las colisiones reciben nombres
distintos; se verifica el hash antes y despues de copiar. `-SkipLogged`
solo omite operaciones Success cuyo destino conserva el hash esperado:
las entradas Plan y DryRun no cuentan como realizadas. Para registros
nuevos de consolidacion se guardan tambien las identidades de origen y
destino. Se respeta la cabecera de los logs antiguos; usar un log nuevo
para conservar todas las columnas de identidad.

```powershell
./scripts/Verify-Consolidation.ps1 -Mode Full -ConsolidateLog ./logs/consolidate-new.csv
./scripts/Generate-FinalReport.ps1 -ConsolidateLog ./logs/consolidate-new.csv -CatalogCsv ./artifacts/catalog-new.csv
```

Full compara SHA256. Quick compara tamanos cuando dispone de la fuente;
si no puede confirmar una entrada, lo indica y devuelve error. Las entradas
Missing, Mismatch, Errors y Unconfirmed impiden finalizar con exito.
`Start-FullVerifyAndFinalize.ps1` verifica y genera informes; solo publica
si se indica explicitamente `-Publish`.

## Comprobaciones

```powershell
./scripts/Tests/StorageRegression.ps1
# Si Pester esta instalado:
Invoke-Pester ./scripts/Tests/MediaStorage.Tests.ps1
```

La regresion cubre cambios de letra, montajes en carpetas, discos ausentes,
identidades ambiguas, volumenes bloqueados y rutas relativas invalidas.
La deteccion real debe comprobarse en cada ordenador: este cambio se ha
validado en W11-ANTO y con fixtures que simulan otros montajes.
