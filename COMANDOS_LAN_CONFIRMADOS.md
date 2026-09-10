# Comandos LAN confirmados — IC-7300MK2

Documento de trabajo. Solo se incluye como **confirmado** aquello que se ha
observado funcionar en la radio y en el programa. Los comandos que todavía
fallan o no se han probado de forma concluyente aparecen al final.

## Convenciones

- Transporte: UDP.
- Puerto de control de la radio: `50001`.
- Puerto CI-V de la radio: `50002`.
- Puerto de audio de la radio: `50003`.
- Los identificadores de sesión son valores de 32 bits en little-endian.
- En las tramas CI-V, la radio es `94` y el destino usado por WFView es `E1`.
- El cliente actual envía órdenes como `FE FE 94 E0 … FD` y recibe
  respuestas como `FE FE E0 94 … FD`, además de notificaciones a `00`.

## Comandos confirmados

### Autenticación LAN

Secuencia confirmada en el log del programa:

1. Descubrimiento de la radio.
2. Solicitud de autorización de login.
3. Login con usuario y contraseña.
4. Recepción de respuesta de sesión de 96 bytes.
5. Obtención y envío del token.
6. Sesión autenticada.

Resultado observado:

```text
LAN: respuesta de sesión recibida (96 bytes)
LAN: confirmación recibida; token obtenido
LAN: token enviado; sesión autenticada
```

### Negociación del canal CI-V

La radio confirma los puertos remotos y acepta la apertura del canal CI-V.

Resultado observado:

```text
LAN: estado recibido; puertos remotos CI-V 50002, audio 50003
LAN: respuesta conninfo recibida (144 bytes); CI-V negociado
LAN: canal CI-V solicitado; esperando confirmación
LAN: apertura CI-V confirmada
LAN: flujo CI-V activo (paquetes de datos recibidos)
```

### Lectura de frecuencia

Consulta CI-V enviada por el canal CI-V:

```text
FE FE 94 E0 25 00 FD
```

Características:

- `25 00`: lectura de frecuencia del VFO seleccionado.
- Se encapsula en una trama LAN CI-V de tipo `C1`.
- La consulta periódica funciona durante la sesión LAN.
- La respuesta explícita a `25 00` se ha recibido en paquetes LAN de 33 bytes.
- El valor se codifica en BCD little-endian dentro de la trama CI-V.

Ejemplo confirmado:

```text
LAN: frecuencia CI-V recibida: 24915000 Hz
LAN: frecuencia CI-V recibida: 24916000 Hz
LAN: frecuencia CI-V recibida: 24917000 Hz
```

### Cambio de modo y DATA ON/OFF

Confirmado en la radio mediante los comandos CI-V usados por la implementación
de referencia: `06 <modo> <filtro>` para el modo seleccionado y
`1A 06 <estado> <filtro-data>` para DATA. Los botones de cambio de modo y el
control DATA de la interfaz funcionan correctamente durante la sesión LAN.

La recepción y actualización de frecuencia también permanece activa de forma
continua mientras se utilizan estos controles.

La implementación actual utiliza `26 00 <modo> <DATA> <filtro>` al cambiar
el modo para conservar el estado DATA. Esta modificación del 7 de septiembre
no tiene todavía una confirmación específica de todas las transiciones de modo;
la confirmación histórica anterior corresponde al comando `06`.

### Escritura de frecuencia y rueda de sintonía

Confirmadas por el usuario el **2026-09-07**: la rueda modifica el dial del
programa y la frecuencia de la radio mediante `25 00 <frecuencia BCD de 5 bytes>`.
El registro muestra órdenes de escritura y respuestas posteriores con la
frecuencia modificada.

La rueda, los botones de paso y la rueda del ratón sobre las cifras del VFO
seleccionado comparten la ruta LAN. La confirmación funcional del usuario
corresponde a la rueda de sintonía.

### Controles de recepción

El usuario confirmó el **2026-09-07** el funcionamiento de este grupo de
controles existentes. La interfaz se actualiza con las respuestas de la radio,
con consultas posteriores a las órdenes y lectura periódica.

| Control | Comando CI-V (sin cabecera ni terminador) |
|---|---|
| P.AMP OFF / 1 / 2 | `16 02 <valor>` |
| ATT OFF / ON | `11 00` / `11 20` |
| AGC FAST / MID / SLOW | `16 12 <01/02/03>` |
| NB | `16 22 <00/01>` |
| NR | `16 40 <00/01>` |
| Auto Notch | `16 41 <00/01>` |
| Manual Notch | `16 48 <00/01>` |
| IP+ | `16 65 <00/01>` |
| AF | `14 01 <nivel>` |
| RF Gain | `14 02 <nivel>` |
| SQL | `14 03 <nivel>` |
| Nivel NB | `14 12 <nivel>` |
| Nivel NR | `14 06 <nivel>` |
| Posición del notch | `14 0D <nivel>` |

Los niveles se codifican en dos bytes BCD, de `00 00` a `02 55`.
Las consultas omiten el valor final. Se observaron respuestas de la radio a
las consultas de los 14 controles. Las pruebas automatizadas de la ruta LAN
y la decodificación de respuestas también pasan.

### FIL1, FIL2 y FIL3: selección e indicador activo

Confirmados por el usuario el **2026-09-07**, incluida la actualización del
color del botón activo, en la compilación **07/09/2026 21:37:10**.

- Escritura: `26 00 <modo actual> <DATA actual> <01/02/03>`.
- Lectura del filtro seleccionado: `26 00`.
- Consulta unos 450 ms después de la orden y también durante el ciclo periódico.
- La respuesta actualiza `radioController.filterText`, que determina el color
  de los tres botones.

Ejemplo observado tras pulsar FIL2:

```text
TX: FE FE 94 E0 26 00 01 01 02 FD
Consulta: FE FE 94 E0 26 00 FD
RX: FE FE E0 94 26 00 01 01 02 FD
```

### Botones de banda

Los botones de banda de la interfaz ya utilizan la escritura de frecuencia
LAN cuando la sesión remota está activa. Mantienen la memoria independiente
de cada banda y VFO: al pulsar una banda recuperan la última frecuencia usada;
si aún no existe, emplean la frecuencia inicial definida para esa banda.

La selección se realiza mediante `25 00 <frecuencia BCD de 5 bytes>` sobre el
VFO seleccionado. La actualización de la frecuencia mostrada y la confirmación
final dependen de la respuesta CI-V de la radio. Los botones de banda fueron
confirmados por el usuario el **2026-09-07**.

### S-Meter por LAN

El S-Meter recibe las respuestas CI-V `15 02 <lectura>` por el canal LAN y las
convierte a porcentaje y texto (`S0` a `S9+… dB`) con la misma escala usada por
la conexión USB. La consulta `15 02` se incluye en el ciclo periódico de
medidores y se envía además cada 250 ms, sin retransmisiones individuales: si
se pierde una lectura, la siguiente llega inmediatamente. Así se obtiene una
respuesta rápida sin saturar la sesión UDP. Confirmado por el usuario el
**2026-09-07**.

### Corrección del acceso al canal UDP

La prueba local del **2026-09-07** mostró un socket enlazado con
`BoundState` e `isOpen() == false`. La búsqueda del canal y los reintentos
comprueban ahora `QAbstractSocket::BoundState`. Esto corrigió el mensaje
«no hay canal CI-V activo» al girar la rueda pese a estar recibiendo frecuencia.

### Bloque VFO, SPLIT, RIT y ΔTX

La implementación LAN incluye ahora selección de VFO A/B (`07 00` / `07 01`),
SPLIT (`0F <estado>`), RIT (`21 01 <estado>`) y ΔTX (`21 02 <estado>`).
Los controles USB siguen usando la cola CI-V protegida habitual. Este bloque
queda pendiente de confirmación manual con la radio.

## Pendientes de confirmación

### Selección, copia e intercambio de VFO

La copia A=B (`07 A0`) y el intercambio A/B (`07 B0`) tienen ruta LAN
implementada, pero no consta confirmación explícita del usuario. La selección
directa de VFO A/B sigue pendiente de completar por LAN.

### Cierre limpio de la sesión LAN

Implementado siguiendo la secuencia observada en WFView, pendiente de nueva
confirmación visual en la pantalla de la radio.

## Historial de confirmaciones

| Fecha | Comando/función | Resultado |
|---|---|---|
| 2026-09-03 | Autenticación LAN | Confirmada |
| 2026-09-03 | Negociación CI-V | Confirmada |
| 2026-09-03 | Lectura y actualización de frecuencia | Confirmada |
| 2026-09-04 | Botones de cambio de modo por LAN | Confirmados |
| 2026-09-04 | DATA ON/OFF por LAN | Confirmado |
| 2026-09-04 | Recepción continua de frecuencia | Confirmada durante cambios de modo y DATA |
| 2026-09-07 | Escritura de frecuencia con la rueda | Confirmada en el programa y la radio |
| 2026-09-07 | 14 controles de recepción LAN | Confirmados por el usuario |
| 2026-09-07 | FIL1 / FIL2 / FIL3 | Cambio en la radio confirmado |
| 2026-09-07 | Color del botón FIL activo | Confirmado tras añadir lectura del filtro |
| 2026-09-07 | Botones de banda | Confirmados por el usuario |
| 2026-09-07 | S-Meter por LAN | Confirmado por el usuario |
