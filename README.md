<img src="docs/icon.png" width="112" height="112" alt="Icono de Puertos: conector Ethernet con contactos azules">

# Puertos

Tus servicios locales, a mano. Un dashboard nativo para macOS que muestra qué puertos TCP están en escucha, qué proceso los usa y desde cuándo está activo. Abre el servicio o detén el proceso desde su tarjeta.

**[Descargar Puertos para macOS](https://github.com/angelmaciasr/puertos/releases/latest/download/Puertos-macos-universal.zip)** · [Todas las versiones](https://github.com/angelmaciasr/puertos/releases)

macOS **13 Ventura o posterior** · **Apple Silicon e Intel** · Sin Node, Python ni servidores para usarla.

## Instalar

1. Descarga el ZIP y descomprímelo.
2. Arrastra **Puertos.app** a **Aplicaciones**.
3. Ábrela con doble clic o desde Spotlight. Su icono aparece en la barra de menú; púlsalo para abrir el dashboard.

### Primera apertura

Esta versión tiene firma local *ad hoc*, pero **no está firmada con Developer ID ni notarizada por Apple**. macOS puede bloquear la primera apertura al descargarla de Internet.

Si confías en el código y en esta descarga, intenta abrir la app y después ve a **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**. Confirma la apertura. Apple explica este procedimiento en su [guía para abrir apps de forma segura](https://support.apple.com/es-es/102445). No hace falta desactivar las protecciones del sistema.

## Qué puedes hacer

- Ver aparecer y desaparecer tus servicios automáticamente mientras el dashboard está abierto.
- Buscar por puerto, proceso, PID, dirección o carpeta; filtrar por **Todos**, **Proyectos** o **Apps**.
- Consultar el puerto, las direcciones, el PID, la carpeta de trabajo y la fecha y duración del proceso en cada tarjeta.
- Abrir una dirección con HTTP o HTTPS, copiar su URL y mostrar la carpeta en Finder.
- Detener un proceso con confirmación; si no responde, forzar su cierre con una segunda confirmación.
- Elegir un intervalo de actualización de **1, 2, 5 o 10 segundos** y activar **Abrir al iniciar sesión** desde el engranaje. El inicio automático está desactivado de fábrica.

**⌘W** minimiza la ventana. El botón de cierre la oculta. En ambos casos, las comprobaciones se pausan. Clic derecho en el icono de la barra de menú → **Salir** cierra la app por completo.

## Ligera y local

Puertos está hecha con **Swift, AppKit y C**. Consulta los procesos y sockets directamente con `libproc`, sin lanzar `lsof`, escanear puertos ni hacer peticiones a tus servicios. Al ocultar o minimizar el dashboard, deja de consultar. No tiene un servidor propio, telemetría, cuentas ni historial de procesos.

En una medición de desarrollo, el detector necesitó unos **2,3 ms de CPU por consulta**; el consumo depende del número de procesos y del intervalo elegido. Las animaciones de hover usan eventos nativos de ratón, sin temporizadores adicionales.

## Cómo interpreta los servicios

- Muestra **TCP en escucha**, tanto IPv4 como IPv6. Agrupa las direcciones del mismo proceso y puerto. No muestra UDP ni conexiones TCP salientes.
- **Desde** es la fecha de inicio del **proceso**, que puede ser anterior al momento en que abrió ese puerto.
- Un puerto puede pertenecer a una base de datos u otro servicio que no tenga página web. **Abrir** funciona cuando el servicio habla HTTP o HTTPS.
- **Detener** envía `SIGTERM` al proceso completo y afecta a todos sus puertos. Si continúa vivo después de cuatro segundos, **Forzar…** permite enviar `SIGKILL`. Un supervisor o Docker puede volver a levantarlo.
- Antes de detener nada, se revalidan el propietario, el PID, el instante de inicio y el puerto, para evitar actuar sobre un PID reutilizado.
- Solo permite detener procesos de tu usuario y protege los procesos del sistema. Estos están ocultos inicialmente. macOS puede impedir consultar algunos procesos de otros usuarios.
- Detectar un puerto en escucha no implica que esté expuesto a Internet; eso depende de la dirección, el firewall y la red.

## Compilar desde el código

Necesitas macOS y las **Command Line Tools de Apple**. La aplicación compilada no necesita herramientas de desarrollo.

```sh
xcode-select --install
git clone https://github.com/angelmaciasr/puertos.git
cd puertos
./build.sh
```

El resultado es `build/Puertos.app`, un binario universal para Apple Silicon e Intel. Puedes arrastrarlo a Aplicaciones o ejecutar:

```sh
./install.sh
```

El instalador de desarrollo usa `~/Applications/Puertos.app` y crea un enlace en el escritorio. Borrar ese enlace no borra la app. No activa el inicio automático.

Para generar el ZIP y su checksum:

```sh
./package.sh
```

## Pruebas

Después de compilar, con Python 3 disponible:

```sh
python3 -m unittest discover -s tests -v
```

Las pruebas crean procesos desechables y verifican detección, desaparición, carpetas con espacios y acentos, agrupación IPv4/IPv6, exclusión de UDP, cierre normal y forzado, y rechazo de identidades antiguas. No detienen tus servicios existentes.

Para medir el detector:

```sh
xcrun clang -O2 tests/benchmark.c build/PortScanner.o -o build/benchmark
./build/benchmark
```

La app también expone `--list` para producir JSON y `--stop PID START_SEC START_USEC PORT [--force]` para las pruebas. La parada no ejecuta órdenes en una shell.

## Licencia

[MIT](LICENSE). Puedes usarla, modificarla y distribuirla.
