# QuanshengDock-Linux — contexto técnico inicial

## Objetivo

Crear una aplicación NATIVA para Linux que sustituya progresivamente a QuanshengDock
sin depender de Wine ni WPF, manteniendo compatibilidad con el firmware actual de la
radio.

Nombre de trabajo del proyecto:

    QuanshengDock-Linux

Directorio previsto:

    ~/QuanshengDock-Linux

Tecnología preferida:

    Qt 6 + C++ + CMake

La estrategia NO es traducir WPF línea por línea. Hay que reutilizar el conocimiento
del protocolo de QuanshengDock y construir primero un núcleo de comunicaciones fiable,
después una GUI Linux nativa.

## Estado actual que YA funciona

Equipo:
- Linux Mint 22 x86_64.
- HP Pavilion dv6.
- Usuario Linux: ramon.
- El usuario pertenece a `dialout`.
- Puerto actual: `/dev/ttyUSB0`.
- Cable Prolific PL2303, VID:PID `067b:2303`, driver `pl2303`.
- ModemManager puede interferir. Durante pruebas se ha usado:
      sudo systemctl stop ModemManager

Radio:
- Quansheng UV-K5 original/V1.
- Bootloader probado: `2.00.06`.
- Firmware instalado y funcionando:
      EGZUMER0_32_21q
- Firmware de referencia: `nicsure/quansheng-dock-fw`, release `0.32.21q`.
- NO volver a flashear para desarrollar el port Linux.
- NO ejecutar `k5prog -F`.
- NO modificar EEPROM ni firmware salvo aprobación explícita.

Referencia funcional:
- QuanshengDock Windows 0.32.22q funciona mediante Wine.
- Ejecutable:
      ~/QuanshengDock/QuanshengDock.exe
- Prefijo:
      ~/.wine-quanshengdock
- COM1 está mapeado a:
      /dev/ttyUSB0
- Ya funciona:
  - clonado de pantalla;
  - frecuencia/canal/batería;
  - botones;
  - desbloqueo TX;
  - PTT press/release.

Por tanto RADIO + CABLE + FIRMWARE están validados. Wine sirve como referencia de
comportamiento mientras se crea la versión nativa.

## Upstream de referencia

Aplicación:
    https://github.com/nicsure/QuanshengDock
    tag/release: 0.32.22q

Firmware:
    https://github.com/nicsure/quansheng-dock-fw
    firmware: 0.32.21q

QuanshengDock es GPL v2. El port/fork debe respetar la licencia y conservar avisos y
atribuciones aplicables.

Si se clonan repositorios upstream, ponerlos en `reference/` o `vendor/` y tratarlos
como solo lectura.

## Datos confirmados del protocolo

Referencia principal:
    QuanshengDock/Serial/Comms.cs

Puerto serie:
- 38400 baudios
- 8 bits
- sin paridad
- 1 bit de parada
- equivalente: 38400 8N1

El programa original:
1. abre el puerto;
2. escribe un byte de prueba `0x00`;
3. envía comandos de tecla;
4. entra en recepción.

### Tramas AB CD

Cabecera:
    AB CD

Longitud de payload: 2 bytes little-endian.

Payload ofuscado con XOR periódico de 16 bytes:
    16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80

Después aparecen CRC y terminación:
    DC BA

Portar la lógica real de upstream; no inventar el protocolo.

### Tramas UI

El firmware Dock también puede emitir paquetes UI empezando por:
    B5

El upstream los usa para reconstruir pantalla/estado remoto.

## Arquitectura deseada

Separar al menos:

    src/core/
        protocolo, framing, CRC, ofuscación, tipos y estado

    src/serial/
        transporte Qt

    src/model/
        estado observable de radio

    src/ui/
        interfaz Qt

    tests/
        pruebas del parser con tramas conocidas

No acoplar parsing y GUI.

Preferencias:
- `QSerialPort` / Qt SerialPort.
- señales/slots.
- Qt Widgets inicialmente salvo razón técnica clara para QML.
- CMake moderno.
- Ninja si está disponible.

## Plan por fases

### Fase 0 — Inspección y diseño

- Comprobar `cmake`, `ninja`, compilador, Qt 6 y Qt SerialPort.
- Inspeccionar upstream 0.32.22q.
- Localizar protocolo, Packet enums, parser, estado, LCD/UI, XVFO, Spectrum,
  canales, audio y rigctld/CAT.
- Documentar C# -> C++/Qt.
- No tocar la radio.

### Fase 1 — Núcleo serie READ-ONLY

Crear:
    qdock-probe

Objetivo:
- abrir `/dev/ttyUSB0` a 38400 8N1;
- recibir;
- sincronizar framing;
- decodificar;
- imprimir eventos;
- opcionalmente guardar capturas para tests.

IMPORTANTE:
- empezar solo leyendo;
- no PTT;
- no EEPROM;
- no flash.

Criterio de éxito:
- tráfico estable de 0.32.21q;
- tests reproducibles del parser.

### Fase 2 — Handshake/control básico

Después de Fase 1:
- reproducir handshake mínimo;
- frecuencia;
- canal;
- batería;
- RX/TX;
- RSSI si está disponible;
- teclas no destructivas.

PTT sólo tras validar y con confirmación explícita.

### Fase 3 — GUI mínima Qt

- conectar/desconectar;
- selector `/dev/ttyUSB*`;
- estado;
- frecuencia;
- canal;
- batería;
- RX/TX;
- botones básicos;
- log opcional.

### Fase 4 — LCD y controles

- pantalla virtual;
- teclas;
- TX lock;
- PTT;
- VFO/MR;
- squelch;
- potencia.

TX bloqueado por defecto.

### Fase 5 — Avanzado

Prioridad:
1. XVFO
2. editor de canales
3. spectrum
4. waterfall
5. CAT / rigctld / Gpredict
6. audio
7. presets y extras

## Reglas críticas

1. NO flashear la radio.
2. NO ejecutar `k5prog -F`.
3. NO escribir EEPROM en las primeras fases.
4. TX/PTT bloqueado por defecto.
5. Pedir confirmación antes de acciones potencialmente destructivas sobre la radio.
6. Mantener `~/QuanshengDock` y `~/.wine-quanshengdock` intactos.
7. No cambiar servicios del sistema sin explicar antes.
8. No usar sudo para abrir el puerto serie.
9. Si falta una dependencia, explicar el paquete y pedir permiso antes de instalar
   con sudo.
10. Hacer cambios pequeños, compilables y comprobables.

## Primer objetivo concreto para Codex

No empezar por toda la GUI.

Primero:
1. inspeccionar sistema y proyecto;
2. analizar protocolo upstream 0.32.22q;
3. proponer estructura Qt/CMake;
4. implementar `qdock-probe` READ-ONLY;
5. compilar;
6. ejecutar tests sin radio;
7. sólo después pedir permiso para probar `/dev/ttyUSB0`.

Antes de escribir código sustancial, mostrar un resumen breve del plan y de los
archivos que se crearán.

## Resultado final deseado

Una aplicación QuanshengDock-Linux mantenible y nativa que:
- funcione en Linux Mint sin Wine;
- use directamente `/dev/ttyUSB0`;
- mantenga compatibilidad con firmware 0.32.21q;
- replique primero las funciones esenciales;
- evolucione hacia spectrum, XVFO, canales, CAT/rigctld y audio;
- tenga UI clara y legible;
- preserve la radio funcional durante todo el desarrollo.
