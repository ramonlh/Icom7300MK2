# QuanshengDock-Linux

Port nativo para Linux de las funciones de QuanshengDock, inicialmente centrado en
comunicación serie robusta con firmware Dock 0.32.21q.

Contexto y reglas:
- `PROJECT_CONTEXT.md`
- `AGENTS.md`

Primera versión: `qdock-probe` de consola, sin GUI, con parser independiente de Qt.
No envía bytes: no handshake, teclas, PTT, escrituras EEPROM ni firmware.

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

## Prueba serie, pendiente de autorización

Antes de abrir `/dev/ttyUSB0`, explicar la prueba y obtener autorización explícita.
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
- Sin GUI ni control de radio. TX observado en un paquete es información recibida;
  no existe función para activarlo.
- Decisiones y límites de sincronización: [docs/PROTOCOL.md](docs/PROTOCOL.md).

Licencia GPL v2: [LICENSE](LICENSE). Protocolo adaptado de QuanshengDock de
**nicsure**, versión 0.32.22q; véase [NOTICE](NOTICE).
