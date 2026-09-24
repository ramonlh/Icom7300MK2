# QuanshengDock-Linux

Port nativo para Linux de las funciones de QuanshengDock, inicialmente centrado en
comunicación serie robusta con firmware Dock 0.32.21q.

Contexto y reglas:
- `PROJECT_CONTEXT.md`
- `AGENTS.md`

Primera versión: `qdock-probe` de consola, sin GUI, con parser independiente de Qt.
`qdock-probe` no envía bytes a la radio. `qdock-server` mantiene ese comportamiento
sin opciones adicionales; sus consultas, controles de teclado y PTT son
experimentales y requieren habilitación explícita. No escribe EEPROM directamente
ni flashea firmware.

## CTCSS y DCS RX/TX

En el panel Quansheng, **CTCSS / DCS…** abre el editor del VFO seleccionado.
**Leer RX / TX** consulta los cuatro menús de tonos; **Escribir RX/TX** aplica
OFF, uno de los 50 CTCSS o uno de los 104 DCS normales/invertidos, y vuelve a
leer la pantalla para comprobarlo. OFF desactiva ambas familias. Los índices
EEPROM se muestran también como frecuencias Hz o códigos DCS de tres cifras.

Requiere actualizar tanto el cliente como `qdock-server` del Pavilion y activar
el permiso existente `--allow-frequency-control` (controles de teclado en el
servidor gráfico). La lectura recorre los menús mediante teclas: no es escucha
pasiva. Desactivar recepción dual, escaneo, FM broadcast y bloqueo; seleccionar
primero A o B y no utilizar el teclado físico durante la operación. Se exige
estado RX/TX reciente y se bloquean operaciones simultáneas y PTT.

Se usan exclusivamente teclas del menú del firmware Dock 0.32.21q, sin escritura
directa de registros ni comandos WriteEeprom. Al aceptar, el propio firmware
guarda el ajuste en VFO; en MR modifica el canal en uso sin sobrescribir la
memoria almacenada. No se implementa guardar/reescribir memorias con esta opción.
La petición del usuario autoriza este ajuste de tonos; no autoriza flasheo ni
pruebas físicas automáticas. **Validación física pendiente**. La suite `lan-tones`
simula la radio mediante PTY y comprueba lectura, escritura y errores.

## PTT momentáneo

En el servidor gráfico del Pavilion, marcar **Permitir PTT** antes de iniciar.
Por consola, añadir `--allow-ptt` al comando del servidor serie. Después conectar
el cliente y mantener pulsado **PTT** en el panel Quansheng; soltar para liberar.
El servidor necesita haber recibido un estado reciente de radio.

Libera al perder conexión/mantenimiento (1500 ms), al cerrar y al alcanzar
60 s por pulsación. El máximo puede configurarse con `--ptt-max-seconds N`
(1–180). PTT permanece desactivado por defecto y el lanzador de telemetría no
lo activa automáticamente. El botón distingue PTT solicitado del estado TX
observado. Pruebas offline disponibles en `lan-ptt`. El usuario confirmó el
18 de septiembre de 2026 la activación rápida de TX al pulsar y su desactivación
rápida al soltar, con el servidor actualizado en el Pavilion. Los casos de
caducidad y desconexión siguen validados únicamente offline.
Los fallos de cable/USB o la terminación forzada del servidor pueden impedir
entregar la orden de liberación. Véase `docs/LAN_PROTOCOL.md`.

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

Los lanzadores del Pavilion no contienen ningún token predeterminado. Si
`QDOCK_LAN_TOKEN` no está definido, solicitan uno de forma oculta al arrancar.
Debe introducirse el mismo valor en la configuración del cliente principal.
No reutilices tokens publicados anteriormente en scripts o paquetes de prueba.

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

El servidor publica además un modelo pasivo `display_state` derivado de la
pantalla: VFO A/B, selector activo y frecuencia reconstruida. En el fixture real
se verifican `145.67500` y la frecuencia fragmentada `110.937` + `50` →
`110.93750`. Una captura física posterior confirma también el formato de VFO
libre `435.900` + `00` → `435.90000`. Estos valores siguen siendo observaciones,
nunca controles.

El panel muestra también señal cruda, porcentaje aproximado de batería, paso,
tono/último DTMF e indicadores observados como scan, DWR, cross-band, VOX,
bloqueo, función y carga. La señal no se presenta en dBm y el tono no se
clasifica como CTCSS/DCS hasta disponer de evidencia suficiente.

La utilidad experimental `qdock-register-query` lee los 128 registros BK4819
(`0x00-0x7F`) en tres lotes, sin escribir registros ni acceder a EEPROM o GPIO.
Debe utilizarse con el servidor detenido, pues el puerto serie es exclusivo.

La utilidad experimental `qdock-eeprom-query` realiza una sola lectura EEPROM
de 1 a 128 bytes dentro de `0x0000-0x1FFF`. Inicia una sesión con `Hello 0x0514`,
espera `0x0515` y envía exclusivamente `ReadEeprom 0x051B`; no implementa
`WriteEeprom 0x051D`. `Hello` puede apagar la iluminación de la pantalla. Debe
ejecutarse con cualquier servidor serie detenido. Primera prueba propuesta:

```sh
sg dialout -c './build/qdock-eeprom-query /dev/ttyUSB0 0x0000 16'
```

El servidor admite además `--allow-eeprom-query`. Con esa autorización explícita,
el botón **Leer EEPROM…** del cliente solicita los 8192 bytes en bloques de 128 y
los presenta como tabla interpretada de 200 canales (nombre, frecuencias RX/TX,
desplazamiento, modo, ancho, potencia, tonos, paso, listas y opciones), conservando
una vista hexadecimal secundaria. Una segunda tabla interpreta VFO/bandas, radio
FM, ajustes generales, pantalla, teclas, escaneo, DTMF, contactos y calibraciones.
Los secretos se ocultan y las magnitudes de calibración no confirmadas se conservan
en bruto. La ruta solo contiene `Hello 0x0514` y
`ReadEeprom 0x051B`; no existe escritura EEPROM. El lanzador experimental
`tools/start-qdock-pavilion-telemetry.sh` activa esta capacidad.

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
