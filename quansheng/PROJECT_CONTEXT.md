# QuanshengDock-Linux — documento de traspaso

Actualizado el 10 de septiembre de 2026 a partir de la conversación, código,
referencias locales, capturas y resultados de pruebas. Destino previsto: otro
repositorio que integrará este trabajo con un programa de control del Icom
IC-7300MK2, denominación proporcionada por el usuario.

Este documento permite retomar el trabajo sin acceder a la conversación original.
No confundir el port nativo con QuanshengDock Windows bajo Wine.

## PTT experimental autorizado — 17 de septiembre de 2026

El usuario solicita expresamente implementar PTT. Esta actualización prevalece
sobre los límites históricos de TX/PTT de este documento; no autoriza flasheo,
escritura EEPROM ni pruebas físicas automáticas.

Implementado PTT momentáneo independiente del Icom: botón del panel Quansheng,
cliente TCP y servidor serie, habilitado solo con `--allow-ptt` o con la casilla
**Permitir PTT** del servidor gráfico antes de iniciarlo. El lanzador de telemetría
existente no habilita PTT automáticamente.

Se reutiliza `KeyPress 0x0801`: tecla 16 para pulsar y 19 para liberar. Referencia
inspeccionada para esta ampliación: clone local de QuanshengDock en
`/tmp/QuanshengDock-original`, commit `103acd3f83ae0d920abfd38e0cd1ef242a9b8451`,
`UI/MouseActions.cs` y `Serial/PTT.cs`. No se entra en hardware mode ni se
escriben registros/GPIO. La referencia usa repetición de tecla 16 cada 50 ms
para su PTT externo; se conserva ese intervalo mientras la concesión LAN vive.

El servidor admite un único propietario por pulsación, con ID de operación.
Exige una observación de estado de menos de 5 s, radio no observada en TX y
ninguna operación de teclas/EEPROM en curso. Durante PTT suspende consultas y
rechaza cambios de controles/EEPROM. El cliente mantiene la pulsación cada
250 ms; el servidor libera si faltan renovaciones durante 1500 ms, al desconectar
el propietario, al cerrar la fuente/proceso normalmente o al cumplir el límite
predeterminado de 60 s (`--ptt-max-seconds`, rango 1–180). Un keepalive caducado
no inicia una nueva transmisión. La GUI libera al soltar/cancelar, cambiar de
panel, perder actividad de la aplicación, desconectar o cerrar.

**CONFIRMADO offline:** pruebas de tramas/CRC, permisos, autenticación,
propietario único, conflictos con otros controles, mantenimiento, caducidad,
límite máximo, desconexión, mensaje inválido y cierre del servidor; prueba del
cliente con servidor simulado. Compilaciones de aplicación y servidor correctas;
11/11 suites Quansheng y 2/2 de aplicación aprobadas. Carga QML offscreen con
panel Quansheng y autoconexiones desactivadas correcta (avisos de PulseAudio por
restricciones del entorno).

**CONFIRMADO por prueba física del usuario — 18 de septiembre de 2026:** tras
actualizar y compilar el servidor en `/home/ramon/qdock-readonly` del Pavilion
(11/11 suites aprobadas allí), TX se activa rápidamente al pulsar PTT y se
desactiva rápidamente al soltar el botón. Es una confirmación cualitativa del
usuario, sin medición de latencia. **PENDIENTE de prueba física:** caducidad de
mantenimiento, límite máximo y liberación ante desconexiones; estas rutas están
probadas offline.

 `ptt_state.active` significa pulsación enviada, no
confirmación RF: se conserva por separado el estado candidato observado de radio.
Un fallo de USB, SIGKILL o pérdida de alimentación puede impedir enviar liberación;
no se afirma que exista un watchdog físico validado en el firmware.

## Punto estable READ-ONLY — 13 de septiembre de 2026

**Seguridad de credenciales — 14 de septiembre de 2026:** los lanzadores del
Pavilion ya no contienen un token LAN predeterminado. Si la variable
`QDOCK_LAN_TOKEN` no existe, solicitan un valor de forma oculta y rechazan menos
de 16 caracteres. Cualquier valor publicado anteriormente debe considerarse
público y rotarse tanto en servidor como en cliente.

**CONFIRMADO por prueba física del usuario en el Pavilion:** `qdock-server`,
abriendo `/dev/ttyUSB0` con `QIODevice::ReadOnly`, recibe por LAN frecuencia,
estado RX, batería, modos y otras observaciones de la radio. La aplicación
principal las presenta sin compartir el controlador CI-V del Icom.

En la primera apertura los contadores permanecieron a cero y apareció
temporalmente `Timeout` en la pantalla del UV-K5; al desconectar y reiniciar la
radio recuperó su funcionamiento normal. Una repetición posterior funcionó y
recibió datos. Mantener este antecedente visible y detener la prueba si reaparece.

**LÍMITE ESTABLE:** no existe ruta de cambio de frecuencia o modo, teclas,
TX/PTT, escritura EEPROM ni firmware. Como ampliación experimental autorizada,
el servidor puede habilitar explícitamente `--allow-eeprom-query`: el cliente
solicita entonces un volcado completo mediante Hello y ReadEeprom, sin implementar
WriteEeprom. El resto de mensajes de control continúa rechazado.

**Actualización de telemetría experimental:** la consulta lenta BK4819 abarca
50 registros cada 30 segundos, sin alterar GetRssi (1 s) ni la frecuencia interna
`0x38/0x39` (2 s). Se excluyen los registros de banderas de interrupción `0x02`
y `0x3F`. La primera lectura lenta se solicita a los 3,5 segundos del arranque;
las siguientes mantienen los 30 segundos. La tabla del cliente reserva siempre
las 128 direcciones `0x00-0x7F`.

**EEPROM:** existe constructor validado de `ReadEeprom 0x051B` y
decodificador de `0x051C`, con bloques de 1-128 bytes y rango `0x0000-0x1FFF`.
La utilidad independiente inicia explícitamente sesión con `Hello 0x0514`, que
puede apagar la iluminación, y realiza una sola lectura; no usa `0x052F`. No
existe ruta de escritura. El flujo completo cliente–LAN–PTY, con 64 bloques de
128 bytes y volcado hexadecimal en ventana propia, está probado offline. La
prueba física permanece pendiente.

La ventana EEPROM incluye tres vistas: 200 canales interpretados, ajustes y
calibraciones agrupados, y volcado hexadecimal. También interpreta VFO/bandas,
radio FM, pantalla, operación, teclas, mensajes, DTMF, escaneo y los campos de
calibración confirmados por el firmware de referencia. Los secretos no se muestran
en claro y los contactos/calibraciones cuya estructura o unidad no está confirmada
se etiquetan como datos brutos o pendientes.

### Modelo observable de pantalla — desarrollo posterior al punto estable

**CONFIRMADO en código y pruebas offline:** se añade un `DisplayModel` pasivo y
compartido por replay y fuente serie. Interpreta los borrados de líneas, rechaza
texto no imprimible, separa las zonas A (líneas 1–3) y B (5–7), identifica el
selector lleno del evento tipo 7 y reconstruye la frecuencia B dividida entre
dos elementos de pantalla. El fixture real confirma A activo, `145.67500` en A
y `110.93750` en B. El cliente deja de deducir estos datos directamente de cada
texto y consume mensajes normalizados `display_state` ligados a la sesión.

La GUI resalta el VFO observado como activo. Se mantienen las etiquetas de dato
candidato: todavía se necesitan nuevas capturas físicas para validar otras
pantallas, VFO libre, memorias y cambios de selección. Seis suites aprobadas,
incluidas replay real y ausencia de salida serie.

**CONFIRMADO por captura física posterior:** en pantalla VFO libre, A transmite
la parte principal en tipo 3, x=32, línea 1 (`435.900`) y dos cifras finales en
x=113, línea 2 (`00`); B utiliza la disposición equivalente en líneas 5/6
(`111.137` + `50`). El modelo admite ahora tanto esta forma fragmentada como la
frecuencia completa observada anteriormente en memoria. La regresión reconstruye
`435.90000`, conserva `F6` y potencia `L`; 6/6 suites continúan aprobadas.

El modelo expone además, según la semántica upstream, señal cruda tipo 8,
porcentaje aproximado de batería, paso visible, último DTMF y los indicadores
NOA, DTMF, FM broadcast, scan, DWR, cross-band, XB, VOX, bloqueo, función y
carga. No convierte la señal a S-units o dBm. El carácter de tono visible se
conserva sin afirmar todavía si representa CTCSS o DCS. SQL permanece como
etiqueta de menú mientras no aparezca un valor inequívoco.

## Segunda fase — servidor serie y prueba LAN entre PCs

### Actualización: escucha física y captura cruda

**CONFIRMADO por resultado del usuario:** 5/5 suites aprobadas en el Pavilion
con SerialPort habilitado. Después, escucha física autorizada con radio encendida:
73777 bytes, 456 candidatos globales, 71041 descartados, 0 pendientes y cierre
sin error. El JSON del cliente contiene 376 eventos (81–456), pues se suscribió
después de los primeros 80. Son 188 pares 5/6; todos los estados recibidos son
power_save/7.84 V, sin texto. Registro preservado y análisis en
`docs/LIVE_SESSION_2026-09-11.md`. Recepción física PARCIALMENTE CONFIRMADA.
La prueba previa de 208 bytes/0 eventos fue con la radio apagada, según aclaró
el usuario; no valida comunicación ni determina el origen de esos bytes.

Se añade captura cruda opcional --capture al servidor: archivo nuevo, bytes antes
del parser, errores de creación/escritura/finalización visibles, sin sobrescribir.
Se guarda en el PC servidor y no depende de clientes LAN. Los tests PTY cubren
contenido exacto (ruido y truncación), cliente tardío, protección de archivo
existente, directorio inexistente y fallo de escritura mediante límite de archivo.
La validación física de esta nueva captura está PENDIENTE y requerirá nueva prueba.
Esta actualización prevalece sobre los pendientes históricos siguientes.

**CONFIRMADO por salida aportada por el usuario el 11 de septiembre de 2026:**
compilación del servidor en ~/qdock-lan-test del Pavilion con SerialPort OFF;
replay TCP desde 192.168.1.78 al HP principal con 16968 bytes, 286 candidatos,
14713 descartados, 0 pendientes y ended, sesión
04b248e8-a289-4133-b658-ae09a8e16840. No se ha aportado la salida de CTest del
Pavilion; no inferir que se ejecutó o aprobó a partir del replay.
El usuario habilitó SSH en el Pavilion para esta preparación. El agente sigue
sin autenticación SSH automática; las transferencias las realizó el usuario.

**CONFIRMADO en código y pruebas locales:** segunda fase con fuente serie única
compartida por clientes, --serial/--seconds, configuración ReadOnly reutilizada
del probe, errores y fin de adquisición publicados sin terminar el servidor.
Cinco suites aprobadas con QDOCK_SERIAL=ON, incluida lan-serial-read-only sobre
PTY: dos clientes, entrada fragmentada, ausencia de salida serie, cliente tardío,
rechazo PTT, desconexión y límite temporal. Sin modificar el parser ni el Icom.

**PENDIENTE:** prueba física de este servidor con UV-K5, captura cruda del servidor,
reconexión automática, saturación/estabilidad prolongada, GUI/modelo normalizado,
resolución del falso positivo. No se ha abierto ningún puerto físico ni habilitado
TX/PTT. La recepción física histórica sigue PARCIALMENTE CONFIRMADA.

Esta sección prevalece sobre los pendientes históricos de las secciones siguientes.

## Actualización en el repositorio integrado — 11 de septiembre de 2026

Esta sección actualiza el alcance LAN; los apartados históricos posteriores
conservan la evidencia original del traspaso y sus límites físicos.

**CONFIRMADO en compilación y pruebas locales:** añadido `qdock-server` con
TCP/JSON autenticado y fuente exclusivamente replay, cliente diagnóstico Python
`tools/lan_client.py` y suite `lan-replay`. Serialización JSON extraída del probe
a `src/eventjson.*`, sin modificar el parser ni su interpretación. Compilación
Ninja con QDOCK_SERIAL=ON y 4/4 suites aprobadas (parser, probe-cli, lan-replay,
serial-read-only). La prueba TCP requirió ejecución fuera del sandbox: dentro,
QTcpServer falló al escuchar con "Unknown error". No se desactivaron pruebas.

La suite LAN compara los 286 eventos del fixture de pantalla con el probe,
comprueba dos clientes simultáneos, fragmentación TCP, autenticación y rechazo
de control. El texto espurio de 181 bytes sigue presente como candidato.
**PENDIENTE:** resolver la falsa sincronización; no se ha validado estado de radio.

**CONFIRMADO como requisito del usuario:** el UV-K5 permanece actualmente en el
Pavilion por problemas USB cuya causa no está determinada. En el futuro ambas
radios pueden estar en el HP principal; el servidor Quansheng podrá ser local
(127.0.0.1). La GUI deberá contemplar operación simultánea e independiente de
ambas radios, incluyendo RX/TX y TX/TX cuando dichas capacidades estén autorizadas
e implementadas. Este requisito no habilita TX/PTT Quansheng en la fase actual.

**PENDIENTE:** validación LAN entre PCs, lector serie del servidor, reconexión,
modelo observable/GUI, LCD y frecuencia/canal fiables. No se modificó código
Icom, no se abrió radio, ni se cambiaron servicios del Pavilion. La autorización
para comenzar la integración no se interpreta como permiso para comandos físicos.

Consultar `docs/LAN_PROTOCOL.md` para el contrato exacto y `README.md` para uso.
La recepción física continúa **PARCIALMENTE CONFIRMADA**, sin nuevas capturas.

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

**PARCIALMENTE CONFIRMADO — integración inicial en la GUI Icom:** la aplicación
principal incorpora un cliente TCP independiente (`QuanshengClient`) y un panel
compacto de observación para conectar al servidor `qdock-lan/1`. El panel muestra
conexión, estado de fuente, batería candidata, contadores y errores, y mantiene
TX/PTT deshabilitado. No convierte textos de UI en frecuencia/canal ni comparte
`RadioController`; ambos protocolos siguen separados. La prueba de compilación
del ejecutable Icom se realizó en `/tmp/icom-gui-build`.

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
