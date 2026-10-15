# Guía de agentes de MingoMedia

El primo codex mantiene este repositorio junto con su usuario. Trabaja en una rama
de `main`, conserva los cambios ajenos y entrega un resultado probado y revisable.

## Arquitectura actual

| Zona | Responsabilidad |
| --- | --- |
| `tools/mingomedia_desktop.py` | Asistente Tk de Windows: unidades, tipos, contraseña, progreso y enlace privado. |
| `tools/mingomedia_core.py` | Detección de unidades montadas, catálogo SQLite, inventario y sesión del visor. |
| `tools/mingomedia_duplicates*.py` | Grupos SHA-256, propuesta editable y confirmación local. |
| `tools/mingomedia_recycle.py` | Lectura protegida y operación RecycleItem de Windows. |
| `tools/inventory_remote.py` | Autenticación del visor y acceso de solo lectura a archivos autorizados. |
| `tools/build-mingomedia-windows.py`, `tools/windows/` | Empaquetado, recursos explícitos e instalador por usuario. |
| `src/discos_analisis/` | CLI instalable y enriquecimiento opcional. |
| `tools/templates/`, scripts de sincronización | Fuentes y generación de los visores web. |
| `docs/` | Sitio estático generado, recursos publicados y datos históricos. |

Consulta [tools/README.md](tools/README.md) y [LEGACY.md](LEGACY.md) antes de cambiar
una herramienta anterior. Los archivos antiguos con consumidores o datos únicos
siguen teniendo función; no se borran por su fecha.

## Límites operativos

- Las revisiones y pruebas no deben escanear unidades personales, limpiar archivos
  reales, instalar programas ni publicar inventarios sin autorización del usuario.
- Detecta solo unidades montadas y disponibles. Nunca presupongas H:, I:, J: ni un
  destino por su letra; los flujos de consolidación usan identidad del volumen.
- No leas claves, certificados ni credenciales. No incluyas inventarios privados,
  contraseñas o configuraciones personales en commits, logs públicos o paquetes.
- Los datos privados del asistente viven en la carpeta de datos del usuario,
  fuera del repositorio. Los CSV/JSON/HTML históricos existentes son conjuntos
  separados: no los regeneres o fusiones para una limpieza de código.
- `docs/` es salida generada: actualiza los recursos mediante sus scripts o
  modifica las fuentes correspondientes. No edites manualmente los inventarios
  o HTML generados. Una retirada de artefactos debe usar un manifiesto explícito.
- No ejecutes los cleaners ni los publicadores para verificar documentación.
  Algunos comandos anteriores modifican archivos o hacen commit y push.

## Contratos que hay que conservar

- Contraseña mínima de **8 caracteres**, validada tanto por la interfaz como por el
  servidor. Protege datos, recursos y archivos mediante autenticación del servidor;
  un formulario JavaScript en Pages no sustituye esa protección.
- El visor solo sirve archivos publicados en el catálogo del análisis y unidades
  seleccionadas disponibles. Mantén las guardas de rutas, CSRF, intentos y sesiones.
- Los duplicados se comparan por contenido, tamaño e identidad. Cada grupo marcado
  conserva una copia elegida y admite cambio manual antes de confirmar las rutas.
- Antes de retirar, revalida el contenido y protege la copia conservada frente a
  escritura, renombrado y borrado. Un cambio o una ausencia bloquea el grupo.
- La aplicación usa exclusivamente Papelera. Nunca añadas una alternativa de
  borrado permanente si RecycleItem falla. Informa de omisiones y actualiza el
  catálogo, el inventario y el informe local de las operaciones realizadas.
- Preparar correo abre un borrador; no envía mensajes automáticamente.
- El empaquetado incluye recursos permitidos de forma explícita, sin arrastrar
  datos históricos, archivos de acceso o configuraciones del equipo de desarrollo.

## Estilo y dependencias

- Python: PEP 8, cuatro espacios. El runtime de la aplicación usa la biblioteca
  estándar; las dependencias de compilación viven en `tools/windows/`.
- La GUI anterior con PySimpleGUI es opcional y no forma parte del instalador.
- JavaScript: sin nuevas dependencias para los visores; maneja APIs no disponibles.
- PowerShell: conserva compatibilidad declarada y evita rutas absolutas personales.
  Usa ASCII en scripts nuevos y rutas literales para operaciones de archivos.
- Los scripts deben ser idempotentes y contener sus salidas dentro del destino
  explícito. La simulación debe simular, sin mover ni borrar originales.
- `.gitattributes` centraliza texto/binarios y conserva los patrones LFS. No hagas
  una renormalización masiva de datos para una modificación de documentación.

## Comprobaciones

```powershell
python tools/check-repository.py
python -m pytest
node --test tests/drive-links.test.cjs tests/inventory-loader.test.cjs
pwsh -NoProfile -File tools/check-powershell-syntax.ps1
```

Prepara el entorno con `python -m pip install -e ".[test]"` dentro de un entorno
virtual. Usa comprobaciones adecuadas al cambio; no instales dependencias en el
Python global. Las pruebas trabajan con fixtures, sin archivos personales.

Para cambios de la aplicación, Windows CI prueba también la interfaz, la Papelera
real con un archivo ficticio y el instalador. Comprueba carga gzip, enlaces y
vistas previas cuando cambies el visor. No presentes una comprobación interna de
widgets como si fuese una prueba manual completa.

## Publicar

1. Actualiza los documentos afectados y revisa el diff, sin añadir resultados de
   escaneos. Las copias de seguridad y los paquetes generados no se versionan.
2. Para una nueva versión de la aplicación o sus recursos empaquetados, incrementa
   `VERSION` en `tools/mingomedia_core.py`, el valor por defecto del instalador y
   los nombres de descarga de [MINGOMEDIA-WINDOWS.md](MINGOMEDIA-WINDOWS.md).
3. Abre el PR y espera a las comprobaciones aplicables antes de integrar. El flujo
   de Windows valida ramas `feat/mingomedia-windows-*` y `main`.
4. La release de `main` publica EXE, ZIP portable y SHA256SUMS. Si la versión ya
   existe y el runtime/recursos son idénticos, no reemplaza sus descargas. Si han
   cambiado, exige una nueva versión.
5. Verifica las descargas nuevas y su SHA-256. Deja el repositorio sincronizado y
   comunica qué cambió, qué se comprobó y cualquier limitación pendiente.
