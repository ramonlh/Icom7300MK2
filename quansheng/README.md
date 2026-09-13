# QuanshengDock-Linux

Port nativo para Linux de las funciones de QuanshengDock, inicialmente centrado en
comunicación serie robusta con firmware Dock 0.32.21q.

Contexto y reglas:
- `PROJECT_CONTEXT.md`
- `AGENTS.md`

Primera versión: `qdock-probe` de consola, sin GUI, con parser independiente de Qt.
`qdock-probe` y `qdock-server` no envían bytes a la radio: no implementan
handshake, cambio de frecuencia, teclas, PTT, escritura EEPROM ni firmware.

## Compilar y probar sin radio

Dependencias en Linux Mint 22: compilador C++17, CMake, Qt 6 Core, Qt 6
SerialPort y Python 3 para tests de integración. Si falta SerialPort, el paquete
es `qt6-serialport-dev`; su instalación requiere permiso del usuario.

```sh
cmake -S . -B build -DQDOCK_SERIAL=ON
cmake --build build -j2
ctest --test-dir build --output-on-failure
./build/qdock-probe --help
```

Para compilar únicamente reproducción de capturas, sin Qt SerialPort:

```sh
cmake -S . -B build -DQDOCK_SERIAL=OFF
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

Prueba inmediata con datos sintéticos, sin radio:

```sh
python3 -c "from pathlib import Path; Path('/tmp/qdock-demo.raw').write_bytes(bytes.fromhex('b5 06 02 00 00 c8 b5 00 00 01 00 03 31 34 35'))"
./build/qdock-probe --replay /tmp/qdock-demo.raw
```

Cada evento se imprime como JSON en stdout; el resumen y errores van a stderr.
La muestra representa RX, batería de 8 V y texto `145`; no es una captura real.

## Primera integración LAN: replay sin radio

Se añade `qdock-server` (Qt Core/Network) y `tools/lan_client.py` (Python 3).
La compilación anterior genera también el servidor y ejecuta cinco suites con
SerialPort habilitado. Qt Network es ahora una dependencia de compilación.

Desde el directorio `quansheng/`, preparar una captura de prueba:

```sh
python3 -c "from pathlib import Path; Path('/tmp/qdock-lan-screen.raw').write_bytes(bytes.fromhex(Path('tests/fixtures/radio-screen.hex').read_text()))"
```

En una terminal, definir un token propio y arrancar el servidor:

```sh
read -rs -p 'Token LAN (al menos 16 caracteres): ' QDOCK_LAN_TOKEN
export QDOCK_LAN_TOKEN
./build/qdock-server --replay /tmp/qdock-lan-screen.raw
```

En otra terminal, definir/exportar el mismo token y ejecutar:

```sh
python3 tools/lan_client.py --host 127.0.0.1 --port 8765
```

El cliente termina al finalizar el replay; el servidor sigue disponible hasta
Ctrl+C. Para probar entre PCs, ejecutar el servidor con `--listen IP_DEL_PAVILION`
y el cliente con `--host IP_DEL_PAVILION`. Las direcciones son marcadores que se
deben sustituir. El usuario confirmó el replay entre Pavilion (192.168.1.78) y HP principal.

En modo replay el servidor solo lee archivos regulares: no abre `/dev/ttyUSB0`,
no transmite comandos y no inicia servicios. Todos los eventos se etiquetan como candidatos,
incluido el falso positivo conocido. Esta fase no modifica la GUI Icom.

Contrato, límites y arquitectura local/remota: [docs/LAN_PROTOCOL.md](docs/LAN_PROTOCOL.md).

## Escucha serie física

Antes de abrir `/dev/ttyUSB0` en una sesión nueva, comprobar que ninguna otra
aplicación posee el puerto y mantener la radio bajo observación.
Cerrar QuanshengDock/Wine y cualquier otro programa que use el puerto. No usar
sudo para acceder al puerto ni cambiar servicios automáticamente.

Tras autorización y compilación con SerialPort:

```sh
./build/qdock-probe --list-ports
./build/qdock-probe --port /dev/ttyUSB0 --seconds 15 --capture /tmp/qdock-first.raw
./build/qdock-probe --replay /tmp/qdock-first.raw
```

La captura debe ser un archivo nuevo: se rechaza sobrescribir archivos existentes.
La escucha acaba automáticamente y no envía el byte de prueba ni las teclas que
upstream usa al conectar. La radio puede permanecer silenciosa sin ese inicio de
sesión: cero bytes no demuestra un fallo de cable o parser. Abrir/configurar un
puerto puede afectar líneas de control según el driver; READ-ONLY significa que
el programa no transmite datos ni comandos.

## Estado y límites

- Parser AB CD y B5, XOR, CRC de diagnóstico y eventos UI básicos implementados.
- Tests de parser y CLI disponibles; con SerialPort se añade un test sobre un
  pseudoterminal que comprueba captura y ausencia de bytes transmitidos.
- Validación parcial con radio real: 506 eventos UI de limpieza/estado recibidos
  pasivamente, batería 7.88 V y ahorro de energía. Otra captura de redibujado
  contiene texto de frecuencia, canal y menús, y se reproduce en tests.
  Falta reconstruir el LCD y un estado estructurado fiable: se ha observado
  también un evento de texto espurio por falsa sincronización.
- El probe verifica la configuración efectiva de Linux antes de escuchar.
  Se observaron bytes adicionales y una primera captura ilegible; véase el
  diagnóstico en `docs/PROTOCOL.md`. Aún no se considera recepción plenamente estable.
- La aplicación principal incorpora un panel LAN de observación. La frecuencia,
  modos y TX observados son únicamente información recibida; no existe función
  para modificarlos o activarlos.
- Decisiones y límites de sincronización: [docs/PROTOCOL.md](docs/PROTOCOL.md).

Licencia GPL v2: [LICENSE](LICENSE). Protocolo adaptado de QuanshengDock de
**nicsure**, versión 0.32.22q; véase [NOTICE](NOTICE).


## Servidor serie: validación offline de la segunda fase

Con QDOCK_SERIAL=ON el servidor admite --serial y --seconds. Hay un solo lector
ReadOnly para todos los clientes; errores y fin de escucha cierran el puerto sin
cerrar el servidor LAN. La CLI admite tanto replay como observaciones serie.
El tiempo de escucha empieza al arrancar el servidor, no al conectar el cliente.

Prueba reproducible **sin radio** desde quansheng/:

```sh
cmake -S . -B build -DQDOCK_SERIAL=ON
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

Deben pasar cinco suites; lan-serial-read-only crea su propio pseudoterminal.
Con QDOCK_SERIAL=OFF permanecen tres suites y --serial se rechaza.
La lectura física en Pavilion quedó confirmada el 13 de septiembre de 2026 con
frecuencia, RX, batería y modos visibles. No hay reapertura automática.

La opción `--capture ARCHIVO_NUEVO` junto a `--serial` conserva en el servidor
todos los bytes recibidos, antes del parser y aunque el cliente se conecte tarde.
No sobrescribe archivos. Un fallo de captura cierra la adquisición con error;
stats incluye capturedBytes. La captura es binaria y admite replay con el probe.
Las pruebas PTY comprueban contenido exacto, protección contra sobrescritura y
fallos de creación/escritura. Su prueba con radio física sigue pendiente.

Análisis y copia preservada del primer registro físico LAN:
[docs/LIVE_SESSION_2026-09-11.md](docs/LIVE_SESSION_2026-09-11.md).
