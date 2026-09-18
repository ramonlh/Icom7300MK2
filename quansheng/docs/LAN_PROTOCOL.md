# qdock-lan/1 — observación y controles opcionales

Implementación inicial del 11 de septiembre de 2026. Es un contrato diagnóstico,
no un controlador completo de radio. El servidor es C++/Qt Core/Network y utiliza
el parser existente. El cliente de consola es Python 3, sin dependencias externas.

## Arquitectura y alcance

- HP principal: aplicación Icom existente y, por ahora, cliente de prueba separado.
- Pavilion: ubicación prevista del lector serie; validado ahora únicamente con PTY local.
- Alternativa futura: ambas radios en el HP principal y servidor Quansheng local,
  accesible mediante 127.0.0.1. No cambiarán las observaciones ni su consumidor.
- La operación simultánea de ambas radios es requisito de arquitectura, incluyendo
  las combinaciones RX/RX, RX/TX, TX/RX y TX/TX cuando estén implementadas y autorizadas.
  PTT Quansheng es opcional; no hay una exclusión global entre radios.
- Protocolos, estado, conexión y futura autorización PTT permanecen independientes.

`qdock-server` admite --serial al compilar con QDOCK_SERIAL=ON, y --replay
en ambas variantes. Los modos son excluyentes; los controles requieren permisos explícitos.
`--replay` exige un archivo regular legible. Se conserva `qdock-probe`.

En esta herramienta diagnóstica cada conexión autenticada puede reproducir el
archivo una vez, desde el principio y con sesión propia. Esto permite comparar
clientes y repetir pruebas. El servicio serie tiene **un único lector y parser
compartidos**, distribuyendo observaciones entre suscriptores. No abre un puerto
por cliente. La implementación está probada con pseudoterminal; físico PENDIENTE.

## Transporte

TCP persistente; un objeto JSON UTF-8 compacto por línea, terminada en LF.
Se aceptan fragmentación TCP y varios mensajes en una lectura. Los saltos dentro
de cadenas deben escaparse mediante JSON. No es HTTP ni el protocolo UDP Icom.

Dirección predeterminada: 127.0.0.1. Puerto predeterminado: 8765; configurable,
con 0 para seleccionar uno libre en pruebas. Para LAN debe indicarse explícitamente
la dirección local del servidor mediante `--listen`.

Token independiente en `QDOCK_LAN_TOKEN`, 16–256 bytes UTF-8; no se imprime ni se
incluye en argumentos CLI. TCP no cifra: esta versión es para loopback/LAN privada.
No se modifican firewall, servicios ni configuración de ninguno de los PCs.
Los lanzadores no proporcionan un valor predeterminado: solicitan el token de
forma oculta cuando la variable no existe. Un token incluido alguna vez en un
repositorio o paquete debe considerarse público y sustituirse en servidor y cliente.

Límites: 8 clientes; 4096 bytes por línea recibida sin LF; autenticación en 5 s;
cola de salida máxima de 1 MiB por cliente, superada la cual se aborta su conexión.
El cliente diagnóstico limita cada línea recibida a 256 KiB y espera hasta 10 s
por actividad de red. No tiene reconexión automática: una desconexión es un error.

## Mensajes

Cliente inicia con:

```json
{"message":"hello","protocol":"qdock-lan/1","token":"TOKEN_CONFIGURADO"}
```

Servidor responde `welcome` con `protocol`, `source: "replay"` y capacidades
`serialAvailable`, `txControlAvailable`, `radioControlAvailable` y
`normalizedStateAvailable`, `eepromReadAvailable` y `frequencyControlAvailable`.
Las dos últimas solo son true con fuente serie iniciada mediante sus opciones
explícitas. El cambio de frecuencia requiere `--allow-frequency-control`, actúa
solo sobre el VFO normal y simula las teclas numéricas; el firmware puede marcar
el canal para guardarlo en EEPROM. `txControlAvailable` solo es true con
`--allow-ptt` y fuente serie escuchando. No se habilita escritura de registros.

La misma autorización permite `set_dual_watch` (`enabled` booleano) y
`set_squelch` (`level` entero 0–9). Ambos simulan exclusivamente el menú normal
del firmware Dock 0.32.21q (`RxMode` 59 y `Sql` 61); no escriben registros ni
EEPROM directamente, aunque el propio firmware puede guardar el ajuste igual que
cuando se realiza desde el teclado de la radio.

Tras `{"message":"subscribe"}`, el servidor envía:

1. `source_status`: `source: "replay"`, identificador UUID `session`, estado `replaying`.
2. Cero o más `event`, en orden.
3. `stats`: bytes, eventos, descartados y pendientes del parser.
4. `source_status` con la misma sesión y estado `ended`.

Entre los eventos puede emitir `display_state`, siempre con `source` y la misma
`session`. Contiene `activeVfo` (`A`, `B` o vacío) y objetos `vfoA`/`vfoB` con
`frequencyText`, `memory`, `name`, `mode`, `power` y `selected`. Es un modelo
observable de la pantalla, no una consulta interna a la radio. Reconstruye los
fragmentos de frecuencia conocidos y descarta textos no imprimibles. El objeto
`indicators` añade señal cruda, porcentaje de batería derivado, paso, tono
observado, último DTMF y banderas de estado. Ningún campo habilita control.

La conexión permanece abierta después de `ended`; otra suscripción en la misma
conexión se rechaza. Una conexión nueva obtiene nueva sesión y replay desde cero.
El archivo se lee en bloques de 256 bytes cada 10 ms: **no reproduce el tiempo de
la captura original**, que los fixtures no conservan.

Un `event` contiene:

- `source: "replay"`, `session`, `sequence` desde 1.
- `observedAt`: hora UTC del procesamiento de replay, no de la captura física.
- `quality: "candidate"`: ninguna muestra se promueve a estado fiable.
- `decoder: "qdock-probe/0.1.0"`: identifica la interpretación actual.
- `event`: objeto con exactamente los campos JSON emitidos por el probe existente.

Secuencia y contadores se codifican como cadenas decimales para evitar pérdida
de precisión en consumidores JSON. `stats` incluye `bytes`, `events`, `discarded`
y `pending`. Un final con pendientes no es un replay completo de todas las tramas.

Después de autenticarse puede enviarse `{"message":"ping"}` para recibir
`{"message":"pong"}`. Ese intercambio prueba el servicio LAN, no una radio.

Con `eepromReadAvailable: true`, un cliente ya suscrito puede enviar
`{"message":"read_eeprom"}`. El servidor inicia `Hello 0x0514` y encadena
lecturas `0x051B` de 128 bytes hasta completar `0x0000-0x1FFF`. Publica
`eeprom_status` con progreso y finalmente `eeprom_dump`, cuyo `dataBase64`
contiene exactamente 8192 bytes. La lectura puede apagar temporalmente la
iluminación de la radio. No existe mensaje ni constructor de escritura EEPROM.
El mensaje incluye además `channels`, una tabla de 200 filas interpretada a partir
de los registros de canal `channel*16`, nombres en `0x0F50` y atributos en
`0x0D60`. `settings` agrupa VFO, FM, ajustes, mensajes, DTMF, escaneo,
contactos y calibraciones. Contraseña, clave AES y códigos kill/revive no se
transportan en claro; solo se indica si existen. Los valores no reconocidos se
etiquetan como pendientes y las calibraciones sin unidad confirmada permanecen brutas.

Al arrancar con la lectura EEPROM habilitada, el servidor realiza además una
lectura mínima de 128 bytes en `0x0E00`, extrae el nivel de squelch de `0x0E71`
y publica `radio_settings.squelchLevel` (0–9). El último nivel conocido también
se incluye en `display_state` para inicializar clientes que se conecten después.
Esta operación no escribe EEPROM ni recorre el volcado completo.

Errores: `{"message":"error","code":"..."}`, seguido de cierre. Códigos:
`invalid_json`, `message_too_large`, `protocol_mismatch`, `unauthorized`,
`authentication_timeout`, `unsupported_message`, `replay_open_failed`,
`replay_read_failed`. Un cliente lento puede recibir directamente cierre TCP.

Con `frequencyControlAvailable: true`, un cliente suscrito puede enviar
`{"message":"set_frequency","frequencyHz":145675000}`. El servidor valida
VFO activo normal, bloqueo/escaneo, TX y rango EGZUMER 18–1300 MHz. Se excluye
la zona BK4819 aproximadamente 630–840 MHz, y publica
`frequency_status` (`starting`, `sent`, `complete` o `error`). No se acepta ningún
mensaje de teclas arbitrarias ni escritura cruda; se rechazan como
`unsupported_message`. PTT utiliza el contrato independiente descrito abajo. La lectura EEPROM conserva su permiso
independiente `--allow-eeprom-query`. `hello` es
autenticación LAN, nunca el comando de radio 0x0514.

## Evidencia y límites

**CONFIRMADO mediante pruebas locales:** compilación, cinco suites con SerialPort, fidelidad
de los 286 eventos candidatos de radio-screen.hex frente al probe, dos clientes
simultáneos, nuevas sesiones, fragmentación/agrupación TCP, autenticación,
rechazo de mensajes inválidos y de control. Las suites previas siguen pasando.

**PARCIALMENTE CONFIRMADO:** recepción física y significado de observaciones B5,
sin nueva evidencia física aportada por esta entrega. Mantener las distinciones
de PROJECT_CONTEXT.md.

**CONFIRMADO por salida aportada por el usuario:** replay desde Pavilion
192.168.1.78 al HP principal, sesión 04b248e8-a289-4133-b658-ae09a8e16840;
16968 bytes, 286 candidatos, 14713 descartados, 0 pendientes y ended.

**CONFIRMADO por el usuario el 13 de septiembre de 2026:** recepción física por
LAN de frecuencia, estado RX, batería, modos y otras observaciones desde el
Pavilion. **PENDIENTE:** sesiones prolongadas y saturación de clientes,
reconexión automática, reconstrucción LCD y estado normalizado fiable. El
control de frecuencia y VFO mediante teclas virtuales es experimental, requiere
`--allow-frequency-control` y todavía está pendiente de validación física.

El falso positivo de texto de 181 bytes continúa presente y se transporta como
candidato; la regresión exige conservarlo sin presentarlo como estado validado.
No se ha resuelto la falsa sincronización. `data_hex` conserva datos del evento,
no sustituye la captura cruda. No deducir frecuencia/canal del texto, ni TX de la
cadena "TX", ni validez de respuesta de `crc_matches_command_algorithm`.


## Fuente serie (segunda fase, validada con pseudoterminal)

Compilar con QDOCK_SERIAL=ON. `--serial DISPOSITIVO` selecciona exclusivamente
ese puerto; `--seconds N` limita la escucha a 1–86400 s (predeterminado 15).
Se abre después de que el socket TCP haya podido escuchar. La duración cuenta
desde la apertura, **no desde la conexión del primer cliente**. Un error de bind
no abre el puerto. No existe una orden LAN para abrir, reabrir o cambiar puerto.
La apertura física sigue requiriendo autorización explícita.

Configuración y comprobación termios compartidas con el probe: 38400 8N1 raw,
sin flujo. Sin opciones de control/consulta la apertura es QIODevice::ReadOnly.
Las opciones explícitas abren ReadWrite para las operaciones habilitadas.
READ-ONLY no garantiza ausencia de efectos eléctricos sobre líneas de control.

`welcome` anuncia `source: "serial"` y `serialAvailable: true` cuando ese modo
está seleccionado; esto indica capacidad, no apertura correcta. Las otras tres
capacidades reflejan las opciones habilitadas. La suscripción devuelve un `source_status` con:

- `session`: UUID de adquisición compartido, independiente del cliente.
- `status`: listening, ended o error. listening significa puerto abierto, no radio validada.
- `portOpen`: apertura efectiva del puerto.
- `error`: detalle del fallo, vacío si no hay error.
- `nextSequence`: siguiente evento global; el cliente tardío comienza en ese número.

Eventos y calidad mantienen el formato del replay con `source: "serial"`.
`observedAt` es hora de recepción/procesamiento en el servidor, no reloj de radio.
Cada segundo se emiten estadísticas acumuladas, incluso sin bytes de entrada;
esto mantiene visible la diferencia entre servicio activo y radio silenciosa.
Al vencer la duración o fallar el puerto se cierra la adquisición y se publican
estadísticas finales y estado. El servidor sigue vivo y responde ping/suscripciones.

La reconexión TCP no reinicia el parser ni repite datos antiguos: devuelve el
estado actual y eventos futuros de la misma sesión. Un cliente que se desconectó
puede haber perdido eventos. Reiniciar el proceso crea nueva sesión. No hay
reapertura automática. La CLI muestra el error de fuente y termina con código 1;
termina normalmente al recibir ended, incluso si se conecta después de finalizar.

Pruebas añadidas: configuración PTY efectiva, entrada fragmentada, dos clientes
con eventos idénticos, cliente tardío, rechazo PTT sin detener otro cliente,
desconexión del PTY, consulta posterior de error, límite temporal, pendientes
finales, puerto inexistente y ausencia de bytes transmitidos. No prueban RF.

## Captura cruda opcional

`--capture ARCHIVO` requiere --serial y crea un archivo **nuevo en el servidor**
con QIODevice::NewOnly. Si falla su creación no se abre el puerto serie. Si después
falla la apertura serie puede quedar un archivo vacío; no demuestra silencio RF.
Cada bloque recibido se escribe y vacía con flush antes de alimentar el parser,
incluyendo bytes que luego se descartan. El cierre vuelve a comprobar flush.
Un fallo de escritura/finalización publica source_status error y cierra la fuente.
Flush no garantiza supervivencia a un fallo eléctrico del disco o equipo.

source_status añade captureRequested y captureOpen; stats añade capturedBytes,
cadena decimal. Sin --capture, capturedBytes es 0. Ante escritura parcial puede
diferir de bytes y el estado final es error. No se transmiten rutas locales por LAN.
El archivo no lleva tiempos ni límites de lectura: es el flujo binario recibido,
apto para qdock-probe --replay. Persiste aunque no haya clientes o lleguen tarde.
No incluye bytes anteriores a abrir el puerto; su tamaño no valida recepción RF.

La escucha física anterior sin captura se analiza en LIVE_SESSION_2026-09-11.md.

## PTT momentáneo opcional (17 de septiembre de 2026)

Solo fuente serie con `--allow-ptt`, cliente autenticado y suscrito.
`--ptt-max-seconds N` limita cada pulsación a 1–180 segundos, 60 por defecto;
no se admite esta opción sin `--allow-ptt`. El modo replay nunca habilita PTT.
El servidor gráfico ofrece la casilla **Permitir PTT**, desmarcada inicialmente.

```json
{"message":"ptt","action":"press","id":"UUID-NUEVO-POR-PULSACION"}
{"message":"ptt","action":"keepalive","id":"UUID-NUEVO-POR-PULSACION"}
{"message":"ptt","action":"release","id":"UUID-NUEVO-POR-PULSACION"}
```

ID: cadena de 1–64 caracteres. El cliente genera un UUID nuevo por pulsación.
Solo la misma conexión e ID pueden renovar/liberar. La renovación, enviada cada
250 ms, no puede crear un PTT nuevo. Al faltar renovaciones durante 1500 ms, se
envía liberación; también al superar la duración máxima, perder conexión,
recibir un error de protocolo o detener la fuente/servidor. El límite se mide con
reloj monótono y no se amplía con renovaciones. No hay reactivación automática.

Para iniciar se exige fuente escuchando, estado UI tipo 6 recibido en los últimos
5 s, sin TX observado, sin otra pulsación y sin teclas/EEPROM/salida serie pendiente.
La señal UI sigue siendo candidata, no una comprobación RF. Durante la pulsación
se pausan consultas RSSI/registros y se rechazan controles/lectura EEPROM.

El servidor publica a los suscriptores:

```json
{"message":"ptt_state","active":true,"id":"...","reason":"pressed"}
{"message":"ptt_state","active":false,"id":"...","reason":"released"}
```

`active` describe la tecla solicitada, no TX RF confirmado. Otros motivos:
`lease_expired`, `max_duration`, `client_disconnected`, `source_stopped` y
`release_write_failed`. La GUI conserva separado el estado recibido de radio.
El cliente solicitante recibe errores como
`{"message":"ptt_status","id":"...","error":"ptt_busy"}` sin cerrar TCP.
Otros errores: `ptt_not_enabled`, `ptt_unavailable`, `invalid_ptt_id`,
`invalid_ptt_action`, `ptt_not_owner`, `ptt_expired`, `radio_control_busy`,
`radio_already_transmitting`, `radio_state_stale`, `ptt_serial_write_failed`.
Un mensaje PTT sin campos `action`/`id` mantiene el rechazo `unsupported_message`.

Validado con TCP local y PTY. El usuario confirmó el 18 de septiembre de 2026
que, con el servidor actualizado en el Pavilion, TX se activa rápidamente al
pulsar y se desactiva rápidamente al soltar. No hay medición de latencia ni
confirmación física de los casos de caducidad/desconexión.
Una interrupción USB, SIGKILL
o pérdida de alimentación impide garantizar que la radio reciba la liberación.
