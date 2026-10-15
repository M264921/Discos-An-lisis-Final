# MingoMedia para Windows

## Descargar e instalar

En [Releases](https://github.com/M264921/Discos-An-lisis-Final/releases), descarga
**MingoMedia-Setup-1.1.0-win64.exe**. Ábrelo con doble clic y sigue el instalador.
Después abre **MingoMedia** desde el menú Inicio. Opcionalmente puedes crear un
acceso directo en el Escritorio durante la instalación.

Es para Windows 10/11 de 64 bits. Incluye Python, la interfaz y el componente de
conexión: el ordenador de destino no necesita Git, Python ni PowerShell 7.
Se instala para tu usuario y se desinstala desde Configuración → Aplicaciones.
La versión ZIP portable permite descomprimir la carpeta completa y abrir
`MingoMedia.exe` sin instalar. No extraigas solo el EXE de esa carpeta.

El ejecutable todavía no tiene una firma comercial de código. Windows puede
mostrar un aviso de editor desconocido; verifica el origen y el SHA-256 publicado.

## Usar el asistente

1. **Unidades.** Aparecen solo unidades disponibles. Se muestran su letra, etiqueta,
   capacidad, espacio libre y tipo: fijo, externo/USB, extraíble, red u óptico.
   Marca una, varias o usa Seleccionar todas. Actualizar detecta cambios.
2. **Archivos.** Elige todos los tipos o combina imágenes, vídeos, audio,
   documentos y otros. Por defecto se omiten Windows, programas y cachés.
   Puedes activar la comprobación SHA-256 para identificar duplicados; tarda más.
3. **Contraseña.** Elige y confirma una contraseña de al menos 8 caracteres.
   No se guarda en archivos ni se publica en GitHub.
4. **Analizar y compartir.** Primero se descubren y cuentan los archivos. Después
   se muestra un porcentaje sobre ese conjunto. Se omiten archivos inaccesibles,
   modificados durante el análisis y elementos de nube no disponibles localmente.
   Puedes cancelar. Los originales no se modifican.
5. **Abrir desde el móvil.** Copia el enlace HTTPS y entra con tu contraseña.
   Los nombres abren las vistas previas admitidas por el navegador; los demás
   formatos permiten descargar. Solo se sirven archivos incluidos en el análisis.

**Preparar correo** abre un borrador en tu aplicación de correo predeterminada.
Escribe el destinatario; puedes incluir la contraseña o compartirla por separado.
El programa no envía correos automáticamente y no necesita credenciales de correo.
Si no hay una aplicación configurada, usa Copiar enlace y tu correo habitual.

Mantén **el PC y MingoMedia encendidos y conectados**. La suspensión, el cierre del
programa o Cerrar acceso interrumpen el enlace. Cada conexión nueva tiene otra URL.
No se abren puertos del router; se usa un túnel HTTPS temporal de Cloudflare que
requiere Internet. Si falla, el inventario sigue disponible en el PC y puedes
reintentar el enlace sin repetir el análisis. Los Quick Tunnels no garantizan
disponibilidad permanente: [documentación oficial](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

Los resultados se guardan en `%LOCALAPPDATA%\MingoMedia\analisis`.
No se incorporan al repositorio ni a GitHub Pages. La conexión protege todo el
visor con contraseña, cookie de sesión, límite de intentos y acceso de solo lectura.
Las carpetas habituales de credenciales y certificados privados se omiten.

## Revisar duplicados

Después del análisis, pulsa **Revisar duplicados…**. Se vuelve a comprobar el
contenido de los archivos del análisis mediante SHA-256. Los nombres parecidos
no bastan y los enlaces al mismo archivo no se cuentan como copias independientes.
Los archivos vacíos, rutas de sistema, programas, cachés y credenciales se excluyen.
No se buscan unidades ni carpetas ajenas al análisis seleccionado.

La propuesta conserva **una copia por grupo**, aunque haya dos, tres o más.
Prioriza la unidad que indiques; en automático prefiere un disco fijo y rutas
fuera de Descargas, Escritorio y temporales. No supone que una copia idéntica
tenga más calidad. Puedes seleccionar otra copia a conservar en cada grupo;
esas elecciones manuales se respetan aunque cambies la unidad preferida.

Ningún grupo está marcado inicialmente. Marca los que quieras y pulsa
**Revisar retirada…**. El resumen muestra todas las rutas y unidades donde se
conservan archivos y desde donde se enviarán copias a la Papelera. Puedes volver
y modificar la elección antes de confirmar.

Antes de cada retirada se comprueba de nuevo el contenido. La copia conservada
queda abierta con protección frente a escritura, renombrado y borrado mientras
se procesa su grupo. Si falta o ha cambiado, se bloquea ese grupo. Los cambios,
cancelaciones y errores quedan registrados en un informe local junto al análisis.
Se actualiza el inventario; recarga el navegador del móvil para ver los cambios.

La retirada usa la operación **RecycleItem** de Windows, sin alternativa de
borrado permanente. Si la unidad (por ejemplo una red o algunos USB) no admite
Papelera, se omite el archivo y se informa. El espacio se libera cuando vacíes la
Papelera por tu cuenta. La limpieza solo se controla desde el programa de Windows.

## Compilar desde el repositorio (desarrollo)

```powershell
python -m venv .venv-build
.venv-build\Scripts\python -m pip install -r tools/windows/requirements-build.txt
.venv-build\Scripts\python tools/build-mingomedia-windows.py --prepare-only
.venv-build\Scripts\python tools/mingomedia_desktop.py
.venv-build\Scripts\python tools/build-mingomedia-windows.py --installer
```

El instalador requiere el compilador Inno Setup 6; el flujo **MingoMedia Windows**
lo construye en GitHub Actions y prueba el EXE portable, la instalación y la
desinstalación antes de publicar la descarga desde `main`. Los cambios se prueban
en una rama antes de publicar. Incrementa `VERSION` antes de la siguiente release.
La compilación no incluye inventarios, contraseñas o configuraciones de tu PC.

```powershell
python -m unittest discover -s tests -p test_mingomedia_desktop.py -v
```
