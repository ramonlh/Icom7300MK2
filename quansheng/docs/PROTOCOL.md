# Protocolo del probe 0.1

Referencia inspeccionada: QuanshengDock 0.32.22q, commit
`832e2fc9473de5035a8140cf17289c8d1ca2a1bc`, `Serial/Comms.cs` y `Serial/Packet.cs`.
El clon bajo `reference/` es de solo lectura y no se necesita para compilar.
La compatibilidad efectiva con firmware 0.32.21q queda pendiente de captura real.

## Tramas de comandos/respuestas

`AB CD | longitud LE16 | payload XOR | 2 bytes CRC | DC BA`.
La longitud excluye cabecera, CRC y terminador. El payload empieza por comando
LE16 y longitud de parámetros LE16. El probe exige al menos esos cuatro bytes,
pero conserva el payload sin interpretar estructuras de respuestas todavía.

XOR periódico: `16 6c 14 e6 2e 91 0d 40 21 35 d5 40 13 03 e9 80`.
El envío upstream usa CRC-16 polinomio 0x1021, inicial 0, sin reflexión ni XOR
final, sobre payload claro; los bytes CRC little-endian continúan el índice XOR.
Vector independiente `123456789` → `0x31c3`.

**La recepción upstream ignora ambos bytes CRC.** Por ello el probe informa
`crc_matches_command_algorithm`, pero no rechaza una respuesta por discrepancia.
La inspección posterior del firmware 0.32.21q confirma que `SendReply` utiliza
relleno `FF FF`, ofuscado con los índices XOR correspondientes, en esos dos bytes;
no calcula un CRC de respuesta. El campo de diagnóstico compara únicamente con
el algoritmo de comandos y no determina la validez de una respuesta.
Se valida el terminador. La revisión estable READ-ONLY no incluye constructor ni
emisor de comandos. Las identificaciones históricas de `0x0870`, `0x0851`,
`0x052f`, `0x0850` y `0x0871` se conservan únicamente como conocimiento del
protocolo upstream; ninguna de esas tramas se envía. La trama Hello de tests fue
inicialmente un vector sintético y nunca se envía.

## UI

`B5 | tipo | val1 | val2 | val3 | campo | datos`.
Para todos los tipos excepto 6, campo indica número de bytes de datos.
Para tipo 6 no hay datos: campo es batería, voltios = min(campo × 0.04, 8.4).
Los tres bits bajos de val1 indican 1=TX, 2=RX, 4=ahorro y otro=inactivo.
Tipos 0–3 contienen texto. Se conservan todos los tipos y campos sin inventar
semántica; aún no se reconstruye el LCD ni se extraen frecuencia/canal del texto.
UI no tiene checksum, por lo que ruido con B5 puede parecer un evento válido.

## Fragmentación y límites

Se soportan entradas byte a byte y múltiples tramas por lectura, cabeceras
solapadas y recuperación tras longitud menor que 4 o terminador incorrecto.
Se conserva una trama incompleta hasta recibir más bytes; al terminar se informa
el número pendiente. No se busca una cabecera dentro de un payload válido.
Una longitud corrupta pero legal puede retrasar sincronización hasta 65543 bytes;
no se introduce un timeout arbitrario que descartaría capturas fragmentadas.
El buffer pendiente está acotado por el máximo de longitud del protocolo.

## Transporte y próximos pasos

QSerialPort: 38400, 8N1, sin control de flujo, apertura ReadOnly. No se reproduce
el byte `00` ni KeyPress 13/19 usados en OpenPortLoop upstream. Sin actividad
espontánea podría no recibirse nada; handshake requerirá una fase posterior.

Primero ejecutar tests offline y sobre pseudoterminal; después, con autorización,
capturar 15 segundos de puerto real y reproducirlos. No confundir fixtures
sintéticos con evidencia de compatibilidad física.

## Consulta RSSI experimental

**CONFIRMADO en el firmware 0.32.21q y en pruebas offline; PENDIENTE de prueba
física:** `0x0527` no lleva parámetros. La respuesta `0x0528` contiene cuatro
bytes: RSSI LE16 limitado a 9 bits, indicador de ruido limitado a 7 bits e
indicador de glitch de 8 bits. `qdock-rssi-query` es un ejecutable separado que
envía exactamente una consulta y rechaza otras respuestas. No está integrado en
`qdock-server` ni en el lanzador READ-ONLY.
El firmware convierte primero el valor mediante `raw / 2 - 160`; la pantalla
añade después una corrección dependiente de la banda y calcula S0–S9 y el exceso
sobre S9 con los niveles configurados en EEPROM. La utilidad etiqueta ese primer
resultado como `dbm_uncorrected` y no inventa la corrección de banda.

## Lectura experimental de registros BK4819

`0x0851` recibe un contador LE16 seguido de hasta 50 direcciones LE16. El
firmware responde con un paquete `0x0951` independiente por dirección, formado
por dirección LE16 y valor LE16. `qdock-register-query` recorre el rango completo
del BK4819, `0x00-0x7F`, en tres lotes de 50, 50 y 28 registros. La herramienta
no contiene ni invoca `WriteRegisters 0x0850`, EEPROM, GPIO, teclas, frecuencia,
TX o PTT. Es una herramienta experimental separada del servidor.

La telemetría experimental decodifica además `0x30` como habilitación de bloques
BK4819 (RX/TX DSP, enlaces RX/PLL, AF, discriminador, PA, micrófono y calibración
VCO), y `0x7E` como modo/índice AGC, intensidad interna y filtros DC. En `0x73`
solo está confirmado el bit 4, que desactiva AFC cuando vale uno. No se presenta
`0x73` como registro de interrupciones. Las banderas de interrupción están en
`0x02`; no se consultan periódicamente para evitar posibles efectos al leerlas.

El conjunto periódico se amplía a 16 registros. Se interpretan `0x31` (VOX,
scrambler y compander), `0x33` (RX, PA, LNA VHF/UHF y LED), `0x47` (selección de
ruta de audio), `0x48` (índices de las dos etapas de ganancia y DAC) y `0x49`
(selección LO y umbrales alto/bajo del RF AGC). `0x37` se transporta únicamente
en bruto porque su desglose no está suficientemente confirmado.

Para no saturar el enlace serie, `0x38/0x39` se consultan cada dos segundos y se
publican como `register_frequency_state`; GetRssi conserva su intervalo de un
segundo. Los otros 14 registros se consultan y publican conjuntamente cada treinta
segundos. Los valores recientes de `0x38/0x39` se incorporan a la lista bruta sin
volver a leerlos en la consulta lenta.

La consulta lenta incorpora también `0x43`, `0x4D`, `0x4E`, `0x4F` y `0x78`.
Se exponen el modo/ancho de filtro receptor y los umbrales brutos de apertura y
cierre del squelch para RSSI, ruido y glitch, además de sus índices de retardo.
Los umbrales se mantienen en unidades del registro; no se convierten a dBm ni a
tiempo hasta disponer de una equivalencia confirmada.

Se incorporan al mismo lote lento `0x36`, `0x51`, `0x52` y `0x70`. Se publican
el estado y los índices de bias/ganancia del PA, la habilitación y modo
CTCSS/CDCSS, sus umbrales y cola, y los estados/ganancias de Tone1 y Tone2. Son
observaciones técnicas; no habilitan transmisión ni modifican ningún registro.

La consulta lenta se amplía a 30 registros con `0x19`, `0x28`, `0x29`, `0x3D`,
`0x46`, `0x79` y `0x7A`: AGC de micrófono, parámetros del expansor RX y compresor
TX, valor IF/modulación, umbrales VOX y código de retardo. Permanecen en el ciclo
de 30 segundos. El cliente los presenta junto con los anteriores en orden, con
dirección, valor hexadecimal e interpretación; los campos no confirmados se
identifican expresamente como pendientes.

El lote lento se amplía posteriormente a 47 registros, todavía dentro del
máximo de 50 direcciones de una consulta. Se incorporan `0x07`, `0x10-0x14`,
`0x24`, `0x32`, `0x50`, `0x63`, `0x64`, `0x6F`, `0x71`, `0x72` y `0x7B-0x7D`:
control de tono, tabla AGC, detector DTMF/SelCall, estado del escáner, mute TX,
glitch, amplitud VOX/voz, nivel AF, palabras de Tone1/Tone2 y configuración
RSSI/AGC. `0x02` y `0x3F` continúan excluidos porque contienen banderas de
interrupción y no se presupone que su lectura carezca de efectos laterales.
La primera consulta del lote se lanza 3,5 segundos después de abrir la sesión,
desfasada de RSSI y frecuencia; una vez realizada, el temporizador continúa con
el periodo normal de 30 segundos. Así el cliente no comienza con la tabla vacía
durante medio minuto.
El cliente duplica en la zona de usuario sólo un resumen de funciones, escáner,
filtro RX, squelch, CTCSS/CDCSS, DTMF/SelCall y generadores de tono. La tabla
completa permanece en diagnóstico y ninguna de estas observaciones habilita
escritura de registros.

## Lectura experimental de EEPROM

El núcleo implementa y prueba offline exclusivamente la construcción de
`ReadEeprom 0x051B` y la decodificación de `ReadEepromReply 0x051C`. Cada lectura
admite de 1 a 128 bytes y queda limitada al rango físico `0x0000-0x1FFF`. La
petición contiene offset LE16, tamaño, padding y un identificador de sesión LE32.
No se ha implementado constructor para `WriteEeprom 0x051D`.

La radio sólo responde si el identificador coincide con el `Timestamp` de la
sesión previamente establecida. La utilidad independiente `qdock-eeprom-query`
establece explícitamente la sesión `0x12345678` mediante `Hello 0x0514`, espera
la respuesta `0x0515` y solicita un único bloque. Advierte que `Hello` puede
apagar la iluminación. No usa `0x052F`, que reinicializa otros estados, ni se
integra en la telemetría periódica. Su validación con radio física está pendiente.

El lote alcanza finalmente el máximo de 50 direcciones con `0x0B`, `0x0C` y
`0x21`. Los dos primeros exponen el código DTMF/5-tone detectado y los campos de
tipo/desplazamiento CTCSS/CDCSS que el propio firmware consulta. `0x21` se
identifica como configuración base del detector DTMF, pero su desglose permanece
pendiente y se muestra como tal. No se añaden `0x02` ni `0x3F`.

## Diagnóstico físico del 10 de septiembre de 2026

Firmware de referencia inspeccionado: tag `0.32.21q`, commit
`4375c3e9604ee4c14ec4bdae67af077879a96f34`.

- `driver/uart.c:UART_Init` usa divisor `Frequency / 39053U`; la aplicación
  upstream abre a 38400 8N1. No se ha cambiado esa velocidad ni el firmware.
- `misc.c` inicializa Remote UI a true. `CMD_0514` permite activarlo con el
  identificador 0x12345678, pero también apaga la luz y activa un contador de
  configuración; no se ha enviado.
- KeyPress 13 y 19 en upstream son EXIT y KEY_INVALID/liberación, según
  `driver/keyboard.h` y `CMD_0801`. No son un comando explícito de habilitación UI.
- `ui/status.c` llama a `UART_SendUiElement(6, ..., batería, NULL)` y
  `app/uart.c:UART_SendUiElement` llama incondicionalmente a `UART_Send(data, Length)`.
  En este microcontrolador eso intenta leer desde dirección cero. Es una
  explicación sustentada en código para bytes adicionales tras el estado;
  no garantiza que toda pérdida o basura observada tenga esa causa.

Primera captura: 61987 bytes, cero cabeceras AB CD o B5, solo 12 valores de byte.
La causa de esa captura ilegible **no está determinada**.

Nueva captura pasiva, tras reaperturas del puerto y comprobación de termios:
40179 bytes, 506 eventos (253 de tipo 5 y 253 de tipo 6), 37143 bytes descartados,
sin bytes pendientes. Estado power_save, batería 7.88 V. No se enviaron comandos.
La comprobación añadida consulta termios; no corrige ni cambia la configuración.
Por tanto no se atribuye la mejora a una corrección demostrada de velocidad.

Captura completa temporal: `/tmp/qdock-verified-20260910.raw`, SHA256
`a00ed65b856d3a52704acfbff48c241414cc429f61fbd5027613932411d6afd4`.
`tests/fixtures/radio-status.hex` conserva 124 bytes a partir del primer B5:
dos pares de eventos, con 100 bytes adicionales que el parser descarta.
El test de CLI verifica esos eventos y su recuperación entre datos adicionales.
Los bytes previos al primer B5 (16555) no se incluyen en el fragmento.

Qt abre el puerto de forma exclusiva. La sesión del agente no tenía dialout en
sus grupos efectivos aunque ramon ya era miembro; `sg dialout` permitió abrirlo
sin sudo ni alterar permisos. La comprobación de configuración se hace sobre
el descriptor ya abierto, sin una segunda apertura.

Resultado: recepción de estado real validada parcialmente, no LCD completo ni
frecuencia/canal. Próxima prueba propuesta: captura pasiva mientras el usuario
provoca un redibujado no transmisor, para obtener texto de pantalla.

### Captura de redibujado

Segunda prueba de 15 segundos solicitando MENU y EXIT al usuario, sin enviar
comandos desde el PC: 16968 bytes, 286 eventos candidatos, 14713 bytes descartados,
sin pendientes. Se recibieron tipos 0, 1, 2, 3, 5, 6 y 7, con texto `M1`,
`VA.LEON`, `145.67500`, `110.937`, `AM`, `Sql`, `Step`, `TxPwr` y `6.25kHz`.
También aparece `145.07500` y un texto `TX`; los eventos de estado tipo 6
observados solo indican idle o power_save. No se deduce transmisión RF del
texto TX, ni se afirma qué teclas físicas fueron pulsadas realmente.

La captura completa se conserva como hexadecimal en
`tests/fixtures/radio-screen.hex` y se reproduce en el test de CLI. Incluye un
evento espurio tipo 0 de 181 bytes que contiene datos binarios: confirma el
riesgo de falsa sincronización de UI sin checksum. No se ha ocultado ni
filtrado este problema. Antes de construir un modelo fiable de frecuencia/canal,
se debe validar la estructura de elementos UI y mejorar la recuperación usando
esta captura como regresión, sin eliminar caracteres o tramas válidas.

Archivos temporales originales: `/tmp/qdock-screen-20260910.raw` y
`/tmp/qdock-screen-20260910.jsonl`. La frecuencia `110.937` y el fragmento `50`
son elementos separados de pantalla; aún no se reconstruye su valor combinado.
