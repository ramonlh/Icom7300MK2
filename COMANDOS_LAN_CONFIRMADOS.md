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
FE FE 94 E1 25 00 FD
```

Características:

- `25 00`: lectura de frecuencia del VFO seleccionado.
- Se encapsula en una trama LAN CI-V de tipo `C1`.
- La consulta periódica funciona durante la sesión LAN.
- La frecuencia se recibe en tramas CI-V LAN de 32 bytes.
- El valor se codifica en BCD little-endian dentro de la trama CI-V.

Ejemplo confirmado:

```text
LAN: frecuencia CI-V recibida: 24915000 Hz
LAN: frecuencia CI-V recibida: 24916000 Hz
LAN: frecuencia CI-V recibida: 24917000 Hz
```

## Pendientes de confirmación

### Cambio de modo

Trama observada en WFView:

```text
FE FE 94 E1 26 <modo> FD
```

Todavía no está marcada como confirmada en nuestro programa.

### DATA ON/OFF

Se está probando mediante la trama de estado de modo CI-V (`26 00` con modo,
DATA y filtro). **Confirmado por el usuario:** el interruptor DATA cambia el
estado de la radio por LAN.

### Escritura de frecuencia

Implementada en el cliente, pero pendiente de confirmación explícita en la
radio.

### Cierre limpio de la sesión LAN

Implementado siguiendo la secuencia observada en WFView, pendiente de nueva
confirmación visual en la pantalla de la radio.

## Historial de confirmaciones

| Fecha | Comando/función | Resultado |
|---|---|---|
| 2026-09-03 | Autenticación LAN | Confirmada |
| 2026-09-03 | Negociación CI-V | Confirmada |
| 2026-09-03 | Lectura y actualización de frecuencia | Confirmada |
| 2026-09-03 | DATA ON/OFF por LAN | Confirmada |
