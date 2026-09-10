# QuanshengDock-Linux — documento de traspaso

Actualizado el 10 de septiembre de 2026 a partir de la conversación, código,
referencias locales, capturas y resultados de pruebas. Destino previsto: otro
repositorio que integrará este trabajo con un programa de control del Icom
IC-7300MK2, denominación proporcionada por el usuario.

Este documento permite retomar el trabajo sin acceder a la conversación original.
No confundir el port nativo con QuanshengDock Windows bajo Wine.

## 1. Cómo interpretar el estado

- **CONFIRMADO**: comprobado en el código, herramientas o pruebas indicadas.
  Cuando procede del contexto inicial del usuario, se identifica expresamente
  como antecedente y no como una medición nueva de esta sesión.
- **PARCIALMENTE CONFIRMADO**: hay evidencia real, pero cobertura incompleta o una
  explicación plausible aún no demostrada como causa del comportamiento observado.
- **PENDIENTE**: no implementado, no probado o sin información suficiente.

Una definición de comando confirmada en upstream no implica que se haya enviado
ni validado contra la radio. Un evento que emite el parser no es necesariamente
válido: hay al menos un falso positivo documentado.

## 2. Objetivo real y alcance de la integración

**CONFIRMADO — objetivo acordado:** desarrollar un port Linux nativo de las
funciones de QuanshengDock, con Qt 6/C++/CMake y compatible con el firmware ya
instalado. Reutilizar conocimiento del protocolo y comportamiento upstream;
no traducir WPF línea por línea ni depender de Wine para el programa nuevo.
Preservar la radio funcional durante todo el desarrollo.

El primer entregable es `qdock-probe`, una herramienta de consola READ-ONLY con
tests reproducibles. Existe y funciona parcialmente con la radio. No hay todavía
GUI, emisor de comandos ni controlador completo.

**PENDIENTE — integración Icom:** el usuario quiere trasladar este conocimiento a
otro repositorio de control del Icom IC-7300MK2. Esta descripción corresponde al
estado y conocimiento de este repositorio fuente en el Pavilion al preparar el
traspaso; no describe el conocimiento del repositorio Icom después del traspaso.
En el repositorio de destino, `~/Icom7300MK2`, este proyecto será incorporado
bajo el prefijo `quansheng/`.

En el repositorio fuente se facilitó este enlace:
`https://chatgpt.com/g/g-p-6a6851b2c13c8191841cb4cab60d615c/project`.
No se pudo obtener su contenido. En ese contexto no se conocían su código,
lenguaje, arquitectura, protocolo implementado, dependencias ni licencia.
Tampoco se ha verificado aquí
el modelo Icom ni se ha probado comunicación con ese equipo.

Se propuso una aplicación común con controladores separados para Quansheng e
Icom, y una interfaz común de capacidades/estado. Es una propuesta, no una
integración existente ni una garantía de compatibilidad. El parser Quansheng
no se puede presentar como un controlador Icom. Mantener separados protocolos,
funciones específicas y autorización de TX de cada radio. La separación actual
del núcleo y transporte facilita estudiar esa integración; no existe aún una
API común de radio ni un esquema estable de estado para consumo externo.

## 3. Equipo y referencia funcional

### Antecedentes aportados al inicio

**CONFIRMADO como contexto previo del usuario; no reidentificado por consulta
nativa en esta sesión:**

- PC: HP Pavilion dv6, Linux Mint 22 x86_64, usuario `ramon`.
- Radio: **Quansheng UV-K5 original/V1**. No asumir UV-K5(8), UV-K6 u otra revisión.
- Bootloader probado previamente: `2.00.06`.
- Firmware instalado y funcional: **`EGZUMER0_32_21q`**.
- Referencia funcional Windows: **QuanshengDock 0.32.22q**, mediante Wine.
- Ejecutable: `/home/ramon/QuanshengDock/QuanshengDock.exe`.
- Prefijo Wine: `/home/ramon/.wine-quanshengdock`.
- COM1 mapeado a `/dev/ttyUSB0`.
- Bajo Wine ya funcionaban clonado de pantalla, frecuencia/canal/batería,
  botones, desbloqueo TX y PTT press/release. Es evidencia previa del conjunto
  radio/cable/firmware, NO de esas funciones en el port nativo.

No se releyó la versión de firmware/bootloader durante estas capturas pasivas.
No se flasheó ni se abrió/modificó la instalación de referencia para desarrollar
el probe. El usuario indicó que Wine estaba cerrado y la radio encendida en
las pruebas de conexión.

### Cable, USB y permisos observados

**CONFIRMADO en esta conversación:**

- Cable/programador USB-serie **Prolific PL2303**, VID:PID **`067b:2303`**, visto
  en `lsusb` al reconectarlo. Driver `pl2303` según contexto inicial.
  No se ha documentado marca comercial ni revisión interna exacta del cable.
- Puerto utilizado: **`/dev/ttyUSB0`**, propietario `root:dialout`, modo `0660`.
- Inicialmente no existía `/dev/ttyUSB0`, tampoco `/dev/serial/by-id`, y el PL2303
  no aparecía en `lsusb`. Se comprobó también fuera del sandbox. Enumerar puertos
  solo mostraba `ttyS*`; no se abrió ninguno de ellos como alternativa.
- La radio encendida no bastaba para que apareciese el adaptador USB. Después de
  pedir desconectar/reconectar el extremo USB, apareció el PL2303 y el puerto.
  No se ha demostrado si la causa era contacto, hub, alimentación u otra.
- `fuser` no mostró usuario del puerto cuando finalmente apareció. Una consulta
  inicial dentro del sandbox dio además `Cannot open a network socket`; las
  comprobaciones posteriores se hicieron fuera del sandbox.
- `id ramon` y `getent group dialout` incluían a ramon, pero `id` de la sesión del
  agente NO tenía dialout en sus grupos efectivos. El probe falló con
  `Permission denied`, incluso fuera del sandbox.
- Se solucionó ejecutando `sg dialout -c '...qdock-probe...'`, sin sudo para el
  puerto ni cambios de propietario/permisos. No dar por hecho que otra sesión
  necesite ese mismo recurso: comprobar sus grupos efectivos.
- La apertura de Qt fue exclusiva: intentar una segunda apertura para consultar
  termios dio `Device or resource busy`. Se abortó esa prueba diagnóstica y se
  movió la comprobación al descriptor ya abierto por el probe.

**PARCIALMENTE CONFIRMADO — ModemManager:** el contexto previo advertía que puede
interferir y que anteriormente se había usado `sudo systemctl stop ModemManager`.
En este desarrollo no se modificaron servicios ni se demostró que ModemManager
causara los errores observados. No pararlo automáticamente.

## 4. Referencias exactas y licencia

**CONFIRMADO por clones e inspección local:**

| Referencia | Versión | Commit | Carpeta local |
| --- | --- | --- | --- |
| https://github.com/nicsure/QuanshengDock | `0.32.22q` | `832e2fc9473de5035a8140cf17289c8d1ca2a1bc` | `reference/QuanshengDock/` |
| https://github.com/nicsure/quansheng-dock-fw | `0.32.21q` | `4375c3e9604ee4c14ec4bdae67af077879a96f34` | `reference/quansheng-dock-fw/` |

Clones de referencia de solo lectura, excluidos por `.gitignore`; no son
necesarios para compilar. No incluirlos como si fueran fuentes modificadas.

Fuentes principales de la aplicación: `QuanshengDock/Serial/Comms.cs`,
`QuanshengDock/Serial/Packet.cs`. Del firmware: `app/uart.c`, `driver/uart.c`,
`driver/keyboard.h`, `driver/keyboard.c`, `ui/status.c`, `misc.c` y las rutas de menú.

El port está identificado como **GPL-2.0-only**; `LICENSE` contiene GPL v2 copiada
de `LICENSE.txt` de QuanshengDock y `NOTICE` atribuye el protocolo a nicsure
(código upstream de 2024), con versión y commit. Conservar licencia y avisos al
trasladarlo. No se ha evaluado la compatibilidad con la licencia del repositorio
Icom. No asumir que todos los archivos del firmware tienen la misma licencia:
por ejemplo, `driver/keyboard.h` conserva avisos Apache 2.0 de sus autores.

## 5. Puerto y protocolo descubierto

### Transporte

**CONFIRMADO en código y pruebas:** `38400` baudios, `8N1`, sin control de flujo
hardware ni software; `QSerialPort` abierto con `QIODevice::ReadOnly`.
No existe llamada de escritura serie en el probe.

El firmware de referencia configura `UART1->BAUD = Frequency / 39053U` en
`driver/uart.c:UART_Init`; la aplicación Windows abre a 38400. No se cambió el
baudrate del probe a 39053 ni se midió físicamente la velocidad UART.

El probe verifica mediante `tcgetattr(port.handle())`: velocidad de entrada y
salida `B38400`, `CS8`, ausencia de `PARENB`, `CSTOPB`, `CRTSCTS`, `IXON`, `IXOFF`,
`ISTRIP`, `INLCR`, `IGNCR`, `ICRNL`, `ICANON`, `ECHO` e `ISIG`. Si no coincide,
termina con error. Esta comprobación consulta la configuración; NO es una
corrección de velocidad ni demuestra la causa de la primera captura ilegible.

READ-ONLY significa ausencia de datos/comandos enviados por el programa. Abrir y
configurar un puerto puede afectar líneas de control según el driver; no equivale
a instrumentación eléctrica pasiva. Los tests verifican ausencia de bytes de
salida en un pseudoterminal, no una medición física de todas las líneas del cable.

### Tramas AB CD

**CONFIRMADO en upstream y fixtures sintéticos; PENDIENTE validación física de
respuestas AB CD con este probe.**

```text
AB CD | longitud LE16 | payload ofuscado | 2 bytes de cola | DC BA
```

- Longitud: número de bytes de payload; excluye cabecera, cola y terminador.
- Payload: identificador de comando LE16, longitud de parámetros LE16, parámetros.
- XOR periódico, empezando en índice 0 para el payload:
  `16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80`.
- Comandos enviados por upstream: CRC-16, polinomio `0x1021`, inicial 0, sin
  reflexión ni XOR final, sobre payload claro. CRC little-endian, ofuscado
  continuando el índice XOR. Vector `123456789` da `0x31c3`.
- **Respuestas del firmware:** `SendReply` usa relleno `FF FF`, ofuscado si la
  sesión está ofuscada, NO un CRC calculado. El receptor Windows ignora ambos
  bytes. Corrige la descripción inicial que llamaba CRC a toda cola.
- El probe calcula `crc_matches_command_algorithm` como diagnóstico, pero no
  rechaza una respuesta por discrepancia. No usar ese campo como validez de RX.
- El parser actual siempre desofusca AB CD; no implementa selección de sesión
  sin ofuscación, aunque el firmware contempla esa posibilidad.
- Verifica longitud mínima 4 y terminador. Conserva payload y comando sin validar
  estructuras internas de cada respuesta ni la longitud interna de parámetros.

Vector Hello de tests, exclusivamente offline, nunca enviado:
`ab cd 08 00 02 69 10 e6 56 c7 39 52 04 a8 dc ba`.
Payload claro: `14 05 04 00 78 56 34 12`; CRC claro `0x9d25`.

### Paquetes UI B5

**CONFIRMADO en código; PARCIALMENTE CONFIRMADO con capturas reales:**

```text
B5 | tipo | val1 | val2 | val3 | campo | datos
```

Campos de un byte. No tienen XOR ni checksum/terminador propio. El parser usa
`campo` como longitud de datos, salvo tipo 6: consume únicamente los seis bytes
de cabecera y trata `campo` como batería, imitando al receptor Windows.

| Tipo | Interpretación upstream | Estado del port / evidencia |
| --- | --- | --- |
| 0–3 | Texto y variantes de tamaño/estilo del LCD | Texto y campos decodificados; tipos observados físicamente; sin renderizador |
| 5 | Borrar líneas, con val1/val2 | Evento conservado; observado físicamente |
| 6 | Estado e indicadores, batería | Decodificación básica; observado físicamente |
| 7 | Indicador/flecha de selección | Evento conservado; observado físicamente |
| 8 | Señal mediante `LCD.DrawSignal(val1,val2)` | Identificado en código, sin validación física |
| 9 | Datos de mensajería | Identificado en código, sin implementación funcional |
| 10 | DTMF | Identificado en código, sin implementación funcional |

No se asignó semántica al tipo 4. El parser admite tipos desconocidos, conserva
campos y bytes, y no valida todavía su plausibilidad.

Estado del tipo 6: `val1 & 7`: 1=TX, 2=RX, 4=power_save, otro=idle.
Batería mostrada: `min(campo * 0.04, 8.4)` voltios. La fórmula proviene de upstream;
no es una medición independiente ni valida precisión/calibración de la batería.
Otros bits de indicadores quedan conservados como campos, sin modelo completo.

Upstream interpreta el texto como ASCII. El probe usa Latin-1 para exponer bytes
en JSON y también entrega `data_hex`. Esta diferencia no es una validación de
texto arbitrario. Coordenadas y estilos no se aplican todavía; algunas cifras
se dibujan en elementos separados (`110.937` y `50` en la captura real).

### Particularidad del firmware y falsa sincronización

**CONFIRMADO en código:** `ui/status.c` pasa batería como longitud y `NULL` como
datos a `UART_SendUiElement(6, ...)`; esta función llama incondicionalmente a
`UART_Send(data, Length)`. Por tanto intenta leer/transmitir desde dirección cero
con esa longitud, pese a que el receptor trata tipo 6 como paquete sin payload.

**PARCIALMENTE CONFIRMADO:** esto sustenta una explicación de bytes adicionales
tras estado. Se observaron separaciones de 6, 56 y 203 bytes entre cabeceras en
la captura de estado. No demuestra que todos los bytes descartados, pérdidas o
la primera captura ilegible tengan esa causa. No se parcheó ni flasheó firmware.

**CONFIRMADO en captura:** el parser puede tomar un B5 entre datos adicionales
como una cabecera. En la captura de pantalla emitió un texto espurio tipo 0,
longitud 181, con datos binarios. Problema pendiente, documentado y no ocultado.

### Comandos y respuestas identificados

**CONFIRMADO en código de referencia; ninguno transmitido por el port.**

| ID | Nombre/función de referencia | Alcance comprobado |
| --- | --- | --- |
| `0x0514` | Hello / inicializar sesión | Firmware envía versión; timestamp `0x12345678` habilita Remote UI; también apaga luz y establece contador de configuración de 6 s |
| `0x0801` | KeyPress | `Key & 0x1f` selecciona tecla; bit 32 indica click; manipula tecla simulada/retención |
| `0x0803` | GetScreen | Dump de depuración: byte `EF` seguido de 1024 bytes desde gStatusLine; no es el clonado UI usado por Dock ni está soportado por el parser |
| `0x0515` | ImHere | Identificador en Packet.cs; no equivale aquí a un handshake validado |
| `0x0527` / `0x0528` | GetRssi / RssiInfo | Identificadores; sin interpretación funcional nativa |
| `0x051B` / `0x051C` | ReadEeprom / respuesta | Identificadores; no se ha leído EEPROM mediante el probe |
| `0x051D` / `0x051E` | WriteEeprom / respuesta | Identificadores; escritura no implementada y prohibida en esta fase |
| `0x0808` / `0x0809` / `0x0908` | Scan / ScanAdjust / ScanReply | Identificados; sin spectrum nativo |
| `0x0850` / `0x0851` / `0x0951` | WriteRegisters / ReadRegisters / RegisterInfo | Identificados; sin control de registros nativo |
| `0x0860` / `0x0861` / `0x0961` / `0x0862` | WriteGPIO / ReadGPIO / GPIOInfo / GPIOPulse | Identificadores, sin implementación funcional |
| `0x0870` / `0x0871` / `0x0872` | EnterHardwareMode / ExitHardwareMode / SetReportReg | Identificadores, sin implementación funcional |

`OpenPortLoop` Windows envía byte de prueba `00`, KeyPress 13, espera 50 ms y
KeyPress 19 antes de escuchar. Hello está comentado. `keyboard.h` identifica
13=EXIT, 19=KEY_INVALID (liberación de retención), 16=PTT. No son comandos
explícitos para habilitar UI. `misc.c` inicializa Remote UI a true; también existe
opción Remote en menú. No asumir que el ajuste actual siempre coincida con ese
valor inicial. Las capturas válidas pasivas demuestran que no fue necesario
enviar esta secuencia para recibir UI durante esas pruebas.

## 6. Programa actual y archivos importantes

**CONFIRMADO:** repositorio fuente en el Pavilion:
`/home/ramon/QuanshengDock-Linux`, versión de CMake y
CLI `0.1.0`. Al iniciar este traspaso, `git status` estaba limpio y el historial
contenía `955107b` — `Estado funcional inicial del control Quansheng UV-K5`.
Esto sustituye el estado inicial de la conversación, cuando aún no había commits.
El título del commit no implica control activo: el programa sigue siendo pasivo.

```text
CMakeLists.txt                 C++17, biblioteca qdock-core y ejecutable qdock-probe
src/core/parser.h, parser.cpp  Parser y Event; C++ estándar, sin Qt/GUI
src/serial/reader.h, reader.cpp QSerialPort, enumeración, temporizador y termios
src/main.cpp                  CLI, captura/replay, JSON y resumen
 tests/parser_tests.cpp       Pruebas C++ del núcleo
 tests/probe_test.py          CLI, fixtures sintéticos y reales
 tests/serial_test.py         Pseudoterminal: recepción, configuración y no envío
 tests/fixtures/radio-status.hex Fragmento real de estado (124 bytes decodificados)
 tests/fixtures/radio-screen.hex Captura real completa (16968 bytes decodificados)
README.md                     Uso y compilación
 docs/PROTOCOL.md              Notas de protocolo y diagnóstico histórico
AGENTS.md                     Reglas de trabajo y seguridad
LICENSE, NOTICE               Licencia y atribuciones
PROJECT_CONTEXT.md            Este documento autosuficiente de traspaso
```

No existen aún `src/model/` ni `src/ui/`. Son arquitectura prevista, no trabajo
implementado. `build/` contiene artefactos regenerables; no trasladar esos binarios
como sustituto del código y los tests. `.gitignore` excluye build, referencias y
extensiones de capturas binarias; los fixtures `.hex` sí se conservan en Git.

### Funciones implementadas

- Parser incremental por bytes, con múltiples eventos por lectura, XOR, cola
  diagnóstica, descarte de ruido y contadores de descartados/pendientes.
- AB CD: rechaza longitud menor que 4 y terminador incorrecto; recupera buscando
  cabecera, conserva tramas incompletas. Buffer pendiente máximo 65543 bytes.
- UI: extracción de campos y datos; texto tipos 0–3 y estado/batería tipo 6.
- Biblioteca `qdock-core`: `Parser::feed`, `pending`, `discarded`, `crc16` y
  `Event` (`Packet`/`Ui`, datos, campos y `crcMatches`).
- `--list-ports` enumera sin abrir puertos; `--port` abre únicamente el elegido.
- `--seconds`: 1–86400, predeterminado 15; termina con temporizador.
- `--capture`: bytes crudos en archivo nuevo; rechaza sobrescribir mediante
  `QIODevice::NewOnly`; informa errores de escritura/flush.
- `--replay`: entrada binaria en bloques de 4096, sin radio.
- JSON por línea en stdout; resumen/errores en stderr. Conserva `data_hex`;
  paquetes AB CD exponen `command` y `crc_matches_command_algorithm`; UI expone
  `type`, `val1`, `val2`, `val3`, `field`, y texto/estado según tipo.
- Modos mutuamente excluyentes, validación de opciones y errores de acceso.

Limitaciones de implementación: no reconexión automática ni modelo persistente,
no checksum UI, no validación semántica de payloads, no timeout para tramas
incompletas. Una longitud corrupta pero legal puede bloquear sincronización hasta
completar el máximo del protocolo. No buscar cabeceras dentro de un payload se
eligió para no romper datos válidos. El emisor de eventos puede incluir falsos
positivos. El texto no se debe tratar como estado fiable de frecuencia/canal.
El transporte incorpora termios Linux; su portabilidad fuera de Linux no está
validada. La captura se crea antes de abrir puerto: un fallo puede dejar archivo
vacío. El mensaje de cero tráfico después de un error de apertura no es evidencia
de silencio de la radio.

## 7. Pruebas realizadas y resultados

### Herramientas y compilación

**CONFIRMADO:** GCC 13.3.0 en la primera configuración; Qt Core y SerialPort
`6.4.2`; Python 3.12.3 observado al configurar; CMake con generador Unix Makefiles.
Ninja no apareció en la inspección inicial, no fue necesario instalarlo.
`QDOCK_SERIAL=ON` en el build actual; tipo de build no especificado.

Al principio faltaba `qt6-serialport-dev`. El intento autorizado de instalarlo
con sudo falló por requerir contraseña/terminal. Se habilitó compilación offline
con `QDOCK_SERIAL=OFF` y pasaron 2/2 suites. El usuario instaló la dependencia desde
su terminal y ejecutó build/tests; se volvió a verificar con SerialPort: 3/3.
No se desactivaron tests para ocultar fallos.

Último resultado conservado en `build/Testing/Temporary/LastTest.log`, 10 de
septiembre, 22:07 CEST: **3/3 suites aprobadas** en 1.52 s. Son suites, no tres
aserciones. Este traspaso documental consulta ese resultado; no realiza nuevas
pruebas físicas ni altera código.

- `parser`: CRC conocido, fixture Hello fragmentado en todos los puntos de corte,
  XOR, UI byte a byte, tipo 6 sin datos, ruido, CRC discrepante retenido, recuperación
  tras cola incorrecta, longitud cero, truncación y un millón de bytes de ruido.
- `probe-cli`: muestra sintética RX/8 V/texto 145, opciones inválidas, truncación,
  fragmento real de estado y recuperación de texto en captura real completa.
- `serial-read-only`: pseudoterminal Linux, 38400 8N1 efectivo, seis bytes UI
  recibidos/capturados y ausencia de bytes transmitidos. No usa la radio real.

Error de test resuelto: el fixture Hello tenía una cola CRC sintética incorrecta.
Se contrastó con `binascii.crc_hqx` de Python y se corrigió la cola a `04 a8`
(ofuscada; CRC claro `9d25`), sin quitar la comprobación del parser.

### Capturas físicas (15 segundos salvo intentos fallidos)

**CONFIRMADO — resultados observados, sin comandos enviados:**

| Captura | Bytes | Eventos del parser | Descartados | Pendientes | Resultado |
| --- | ---: | ---: | ---: | ---: | --- |
| `qdock-first-20260910-dialout.raw` | 61987 | 0 | 61987 | 0 | Ninguna cabecera AB CD/B5; 12 valores de byte distintos |
| `qdock-verified-20260910.raw` | 40179 | 506 | 37143 | 0 | 253 tipo 5 + 253 tipo 6; 7.88 V y power_save |
| `qdock-screen-20260910.raw` | 16968 | 286 candidatos | 14713 | 0 | Texto de pantalla/menús y estado, con un texto espurio conocido |

Los tres originales estaban presentes bajo `/tmp/` al redactar el traspaso.
`qdock-first-20260910.raw` quedó vacío por Permission denied y
`qdock-diagnostic-20260910.raw` vacío por el intento de segunda apertura; no son
capturas válidas ni pruebas de ausencia de tráfico.

Primera captura ilegible: patrones repetitivos, prefijo `0c 68`, intervalos
observados de 46/49 bytes entre ese prefijo. **PENDIENTE causa exacta.**
No se demostró fallo de parser, baudrate, cable, firmware o ModemManager como
causa. Tras reaperturas y comprobación termios aparecieron eventos válidos;
no atribuir causalidad a esa comprobación de solo consulta.

Captura de estado: primeros 16555 bytes sin B5. Fragmento conservado de 124 bytes
a partir del primer B5: dos pares 5/6 y 100 bytes adicionales descartados.
Ejemplo real de par: `b5 05 00 00 00 00 b5 06 84 00 00 c5`.

Captura de pantalla: se pidió al usuario pulsar brevemente MENU y EXIT, sin
cambiar ajustes ni pulsar PTT; no hay registro independiente de teclas físicas.
Distribución de candidatos: tipo 0=5, 1=87, 2=10, 3=9, 5=84, 6=73, 7=18.
Texto observado: `M1`, `VA.LEON`, `145.67500`, `145.07500`, `F2`, `110.937`, `50`,
`AM`, `H`, `CT`, `-`, `Sql`, `Step`, `TxPwr`, `6.25kHz` y otros fragmentos.
Los estados tipo 6 fueron power_save (7.88 V) e idle (7.88, 7.84 o 7.80 V).
Apareció texto `TX`, pero no estado tipo 6 TX: **no demuestra transmisión RF**.
No combinar `110.937` y `50` como frecuencia validada sin reconstruir el LCD.

**PARCIALMENTE CONFIRMADO — funcionalidad física alcanzada:** apertura, captura,
replay, recepción de UI, interpretación de batería/idle/ahorro y textos legibles.
No se ha validado lectura nativa de versión, RX activo/TX activo con tipo 6,
RSSI, pantalla completa ni frecuencia/canal como estado estructurado. RX/8 V de
la muestra inicial es sintético. No confundirlo con una captura física.

### Conservación de evidencia

Los archivos `/tmp` son temporales; no confiar en que sobrevivan al traslado.
Los dos fixtures de Git son la evidencia reproducible que debe acompañar al
código. El fixture de pantalla conserva TODOS los bytes, incluidos ruido y falso
positivo. El de estado conserva solo el fragmento descrito.

SHA256 sobre bytes binarios (para `.hex`, decodificar primero):

- Captura completa de estado:
  `a00ed65b856d3a52704acfbff48c241414cc429f61fbd5027613932411d6afd4`.
- `tests/fixtures/radio-status.hex`, 124 bytes:
  `5dc7dbb0f18e13fee40ae630630e96a7991f5eefdc663cb66840ae416948ec7d`.
- Captura completa de pantalla / `tests/fixtures/radio-screen.hex`, 16968 bytes:
  `9533b65dffadbde04a542896531d4ceba5eec0a0e31bdfa2525cc08204e2c564`.

El JSON original de pantalla está en `/tmp/qdock-screen-20260910.jsonl`; puede
regenerarse con `--replay` a partir del fixture. La primera captura ilegible no
está incluida como fixture en Git: preservarla aparte si se continúa su diagnóstico.

## 8. Reproducir en el repositorio de destino

**CONFIRMADO — comandos utilizados o equivalentes al flujo existente.**
Dependencias: compilador C++17, CMake >=3.16, Qt 6 Core, Qt 6 SerialPort y Python 3
para tests. Instalar dependencias del sistema solo con permiso. No hace falta
Wine, firmware nuevo ni los clones upstream para compilar.

Si el proyecto está integrado como subtree en `~/Icom7300MK2/quansheng`,
ejecutar los siguientes comandos desde ese directorio:

```sh
cmake -S . -B build -DQDOCK_SERIAL=ON
cmake --build build -j2
ctest --test-dir build --output-on-failure
./build/qdock-probe --help
```

Como alternativa, desde `~/Icom7300MK2`:

```sh
cmake -S quansheng -B build-quansheng -DQDOCK_SERIAL=ON
cmake --build build-quansheng -j2
ctest --test-dir build-quansheng --output-on-failure
./build-quansheng/qdock-probe --help
```

Los ejemplos posteriores usan el directorio del proyecto Quansheng
(`~/Icom7300MK2/quansheng` en el subtree) y su compilación local en `build/`.

Si falta SerialPort, se puede configurar explícitamente `-DQDOCK_SERIAL=OFF`:
compila núcleo/replay y dos suites, sin funcionalidad serie. Es un modo limitado
explícito, no un fallback silencioso. En Mint se instaló `qt6-serialport-dev`.

Reproducir la captura de pantalla sin radio, desde el directorio del proyecto
Quansheng:

```sh
python3 -c "from pathlib import Path; Path('/tmp/qdock-screen-replay.raw').write_bytes(bytes.fromhex(Path('tests/fixtures/radio-screen.hex').read_text()))"
./build/qdock-probe --replay /tmp/qdock-screen-replay.raw
```

Solo después de explicar y autorizar la prueba física, con puerto libre:

```sh
./build/qdock-probe --list-ports
./build/qdock-probe --port /dev/ttyUSB0 --seconds 15 --capture /tmp/qdock-new-session.raw
```

Si la sesión no tiene efectivo dialout pero el usuario ya pertenece a él, el
recurso utilizado fue `sg dialout -c '...comando del probe...'`. No ejecutar con
sudo ni cambiar permisos para evitar el diagnóstico. Elegir un archivo nuevo
para cada captura. La autorización previa de esta conversación fue para escucha
pasiva; no convertirla en permiso general de control, TX o modificación de radio.

## 9. Decisiones técnicas y reglas que deben trasladarse

**CONFIRMADO — decisiones y restricciones acordadas:**

1. Inspeccionar antes de editar; continuar lo existente, no recrear desde cero.
2. Núcleo de protocolo C++ independiente de Qt/GUI; transporte Qt separado.
   Qt Widgets era la preferencia para la futura GUI, aún no implementada.
3. Cambios pequeños, compilar y ejecutar tests después de cada bloque lógico de
   código. No desactivar comprobaciones para esconder errores.
4. Primero probe READ-ONLY; no introducir handshake por suposición. Las capturas
   pasivas válidas ya permiten mejorar el parser sin tocar la radio.
5. Capturar bytes originales y distinguir sintéticos, datos reales y posibles
   falsos positivos. Conservar `data_hex` para diagnóstico.
6. Mantener interpretación de tipo 6 y cola de respuestas compatible con upstream;
   no rechazar respuestas por un CRC de comandos que el firmware no envía.
7. **No flashear firmware; no ejecutar `k5prog -F`.** No reprogramar la radio como
   solución de desarrollo. Cualquier cambio de alcance requiere nueva instrucción
   explícita; no interpretar permiso de prueba serie como permiso de flasheo.
8. **No escribir EEPROM en las primeras fases.** Tampoco hay lectura EEPROM
   implementada o autorizada mediante comandos en el probe actual.
9. **TX/PTT bloqueado hasta aprobación explícita.** Hoy no existe emisor ni PTT
   en el port; no es un bloqueo físico de la radio. Que PTT funcionara previamente
   bajo Wine no autoriza implementarlo/activarlo en este port o en la integración.
10. Antes de usar `/dev/ttyUSB0` real, explicar prueba y obtener autorización.
    Ya se autorizaron las capturas pasivas descritas, no envío de teclas/Hello.
11. No usar sudo para el puerto. Si falta dependencia del sistema, explicar
    paquete y pedir permiso antes de instalar con sudo. No cambiar servicios
    sin explicar antes.
12. Mantener intactos `/home/ramon/QuanshengDock` y
    `/home/ramon/.wine-quanshengdock`; tratar clones upstream como solo lectura.
13. Conservar licencia, atribuciones, pruebas y límites de validación al integrar.

## 10. Trabajo incompleto y siguiente punto de continuación

**PENDIENTE inmediato:** mejorar la recuperación/validación de UI para evitar el
texto espurio conocido. Trabajar primero offline con `radio-screen.hex`; añadir
una prueba que demuestre eliminar el falso positivo sin perder texto válido.
Los tests actuales verifican recuperación de textos, pero NO exigen ausencia del
falso positivo. No filtrar a ciegas bytes o tipos sin contrastar el firmware.

**PENDIENTE después:**

1. Repetir capturas controladas cuando sea necesario y ampliar evidencia de
   estabilidad. Investigar primera captura ilegible sin afirmar causas no probadas.
2. Construir modelo observable y reconstrucción del LCD: limpieza, coordenadas,
   estilos, selección y fragmentos; separar texto mostrado de frecuencia/canal
   normalizados. No ofrecer aún valores de radio fiables a la integración Icom.
3. Inspeccionar código y licencia del proyecto Icom real; definir interfaz común
   de capacidades, estado, errores y transporte, con controladores separados.
   Decidir integración en proceso o mediante otro mecanismo después de esa revisión.
4. GUI mínima Qt: conectar/desconectar, selector de puerto, estado, batería,
   frecuencia/canal cuando estén validados, pantalla y log opcional.
5. Handshake/control básico solo si hace falta: revisar efectos, preparar tests
   y pedir autorización para cada ampliación de alcance antes de enviar comandos.
   No usar GetScreen como sustituto supuesto de la UI; su dump es distinto.
6. Controles, VFO/MR, squelch y potencia; TX lock/PTT solo con aprobación explícita
   y validación posterior, nunca como efecto implícito de integrar radios.
7. Fases avanzadas originalmente previstas: XVFO, editor de canales, spectrum,
   waterfall, CAT/rigctld/Gpredict, audio, presets/extras. Todas pendientes en el
   port nativo; no se han trasladado módulos upstream de esas funciones.

La fase de probe tiene entregable y evidencia física parcial, pero el criterio
original de tráfico estable/fiable no está completado. El traspaso entrega una
base compilable y comprobable, no un sustituto terminado de QuanshengDock ni un
controlador Icom compatible ya implementado.
