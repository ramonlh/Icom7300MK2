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
Se valida el terminador. No hay constructor ni emisor de comandos en producción.
La trama Hello de tests es exclusivamente un vector sintético, nunca se envía.

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
