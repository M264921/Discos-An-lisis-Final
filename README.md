# MingoMedia

Analiza las unidades de tu ordenador, consulta los archivos desde el móvil y
revisa los duplicados antes de enviar las copias sobrantes a la Papelera.

**[Descargar para Windows](https://github.com/M264921/Discos-An-lisis-Final/releases/latest)**

## Instalar y empezar

Descarga el archivo **MingoMedia-Setup-…-win64.exe** de Releases, instálalo y abre
MingoMedia desde Inicio. Es para Windows 10/11 de 64 bits e incluye su propio
Python: el equipo de destino no necesita Git, Python ni PowerShell 7.

También hay un **Portable-…-win64.zip**: descomprime la carpeta completa y abre
`MingoMedia.exe`. Conserva todos los archivos de esa carpeta.

1. Selecciona una, varias o todas las unidades disponibles. El programa distingue
   discos fijos, externos/USB, extraíbles, red y ópticos; no busca letras ausentes.
2. Elige todos los archivos o combina imágenes, vídeos, audio y documentos.
3. Elige y confirma una contraseña de **al menos ocho caracteres**.
4. Espera al análisis y abre o copia el enlace privado HTTPS. El PC y MingoMedia
   deben permanecer encendidos y conectados para acceder desde fuera de casa.
5. Usa **Revisar duplicados…** para marcar grupos de contenido idéntico. Se propone
   una copia a conservar y puedes cambiarla. El resumen muestra todas las rutas
   y unidades antes de confirmar el envío de las demás copias a la Papelera.

El análisis inicial solo lee archivos. La revisión comprueba SHA-256 e identidad
de los archivos, protege la copia conservada y omite archivos cambiados o unidades
sin Papelera compatible. No hay borrado permanente alternativo en la aplicación.

Los resultados privados se guardan en `%LOCALAPPDATA%\MingoMedia\analisis`, fuera
del repositorio. **Preparar correo** abre un borrador para que lo envíes tú.

Consulta [instalación, uso y compilación](MINGOMEDIA-WINDOWS.md) para los detalles.

## Qué contiene este repositorio

| Zona | Función |
| --- | --- |
| `tools/mingomedia_*.py` | Aplicación de Windows, análisis, revisión y Papelera. |
| `tools/inventory_remote.py` | Visor privado con autenticación y acceso a los archivos del análisis. |
| `tools/windows/` y `tools/build-mingomedia-windows.py` | Construcción del EXE portable y el instalador. |
| `docs/` | Visor estático de GitHub Pages, recursos web e inventarios históricos. |
| `src/discos_analisis/` | CLI Python para inventarios y enriquecimiento opcional. |
| `tools/media-dedup/` | Catálogos y consolidación por identidad del volumen. |
| `tools/dlna-helper/` | Servicio DLNA opcional para la red local. |
| `tests/` | Pruebas con archivos ficticios y comprobaciones del visor. |

Los inventarios históricos conservados no representan necesariamente las unidades
conectadas hoy. Las letras antiguas H:, I: o J: no se asignan automáticamente a
otros discos. Algunos archivos grandes usan Git LFS; para trabajar con esos datos
históricos hace falta descargar sus objetos con Git LFS.

El [sitio estático de Pages](https://m264921.github.io/Discos-An-lisis-Final/)
permite consultar lo que se haya publicado allí. Su formulario de correo/PIN
en JavaScript no protege los archivos públicos del sitio. Para compartir archivos
personales con contraseña utiliza el enlace privado del programa de Windows.

## Desarrollo y comprobaciones

Python 3.10 o posterior para la CLI y las herramientas; la compilación de Windows
se valida con Python 3.13. PowerShell 7 y Node.js son necesarios para comprobar
las herramientas PowerShell y los recursos JavaScript, respectivamente.

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -e ".[test]"
.venv/Scripts/python -m discos_analisis --help
.venv/Scripts/discos-enrich --help
.venv/Scripts/python tools/check-repository.py
.venv/Scripts/python -m pytest
node --test tests/drive-links.test.cjs tests/inventory-loader.test.cjs
pwsh -NoProfile -File tools/check-powershell-syntax.ps1
```

En Linux/macOS, usa `.venv/bin/python` y `.venv/bin/discos-enrich`.
Las pruebas usan datos ficticios; no requieren escanear discos personales.
La prueba que utiliza la Papelera real de Windows se activa expresamente en CI
con `MINGOMEDIA_RECYCLE_TEST=1` y solo procesa su propio archivo de prueba.

- **Repository checks** valida Python 3.10 y 3.13, JavaScript y sintaxis PowerShell.
- **MingoMedia Windows** prueba la aplicación, la Papelera, el EXE, la instalación
  y la desinstalación. Publica nuevas versiones desde `main`. Un cambio de
  mantenimiento no reemplaza una descarga ya publicada.
- Sigue [AGENTS.md](AGENTS.md) para cambiar código o publicar una versión.

## Herramientas anteriores y mantenimiento

[tools/README.md](tools/README.md) identifica las herramientas actuales y sus
generadores. [LEGACY.md](LEGACY.md) explica los flujos anteriores que se conservan.
No ejecutes un escaneo o un cleaner como comprobación rutinaria del repositorio.

[CLEANUP.md](CLEANUP.md) distingue la revisión con Papelera de los comandos
anteriores con opciones explícitas de borrado.
[REPOSITORY-MAINTENANCE.md](REPOSITORY-MAINTENANCE.md) registra qué archivos
obsoletos se retiraron y por qué. Su historial sigue disponible en Git.

Mantenido por Antonio Durán Mingorance. Incidencias y propuestas en
[GitHub Issues](https://github.com/M264921/Discos-An-lisis-Final/issues).
