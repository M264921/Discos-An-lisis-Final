# Visor privado de archivos

El nombre de un archivo del inventario abre una vista previa dentro de MingoMedia.
Admite imágenes, PDF, texto (hasta 2 MiB), audio y vídeo compatibles con el navegador.
HTML se muestra como código, sin ejecutar scripts. Otros formatos permiten descargar.
Si un archivo ha cambiado de ruta o la unidad está desconectada, se muestra un aviso.

## Acceso desde el móvil

Desde la raíz del repositorio:

```powershell
python tools/inventory_remote.py
```

Introduce una contraseña de al menos 8 caracteres. El servicio escucha únicamente
en `127.0.0.1:8766`. Consulta los metadatos de unidades montadas de Windows cada
15 segundos; no busca letras ausentes ni recorre carpetas para descubrir archivos.
El inventario existente determina los nombres que aparecen en la tabla.

Para acceder desde otra red, ejecuta el cliente oficial de Cloudflare en otra terminal:

```powershell
cloudflared tunnel --url http://127.0.0.1:8766 --no-autoupdate
```

Abre la URL HTTPS que indique el cliente. Todo el visor, el inventario y los archivos
requieren contraseña; la sesión dura ocho horas y usa una cookie HttpOnly y SameSite.
Hay un límite de intentos de acceso y protección del formulario. Los archivos se
sirven en modo de lectura, con soporte de rangos para reproducción y búsqueda.
No se suben archivos a GitHub. El servidor no registra nombres ni contraseñas.

Este servicio da acceso a los archivos de **todas las unidades disponibles** a quien
tenga la contraseña. Mantén el PC encendido y conectado. Detén ambos procesos con
Ctrl+C para cerrar el acceso. Un Quick Tunnel es temporal y cambia de URL al reiniciarlo.
Consulta la [documentación oficial](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

Para automatizar el arranque, `--password-env NOMBRE` consume y elimina del entorno
del proceso una variable con una contraseña generada. No escribas contraseñas en
archivos del repositorio ni las incluyas en enlaces o argumentos de línea de comandos.

## Desarrollo

La plantilla del visor está en `tools/templates/inventory-preview.js`.
Regenera su bloque en el picker y las versiones de caché con:

```powershell
python tools/sync-file-preview.py
python -m unittest discover -s tests -p test_inventory_remote.py -v
```

Las pruebas usan carpetas y archivos sintéticos, sin explorar discos reales.
