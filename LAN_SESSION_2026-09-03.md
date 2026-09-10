# Diagnóstico LAN — sesión de 5 minutos

Fecha: 2026-09-03 22:49:45–22:54:45 (Europe/Madrid)

## Condiciones

- Ejecutable: `build/Icom7300Mk2Control --lan-diagnostic`
- Plataforma gráfica: Qt `offscreen`
- Radio: IC-7300MK2 en `192.168.1.143`
- Pruebas automáticas: LSB a los 30 s, USB a los 45 s, DATA ON a los 60 s y DATA OFF a los 75 s.

## Cronología observada

- 22:49:45: se abre el socket de control UDP y se completa correctamente el descubrimiento, login y autenticación.
- Se negocian los sockets secundarios de CI-V y audio. El identificador remoto del flujo CI-V es `2368017568` (`a0 14 25 8d` en el datagrama).
- El flujo CI-V comienza con paquetes de espectro de 518 bytes. Las tramas internas empiezan por `FE FE E1 94 27 ...`, es decir, radio `94` hacia controlador `E1`.
- La radio envía latidos tipo 7 de 21 bytes aproximadamente cada 100 ms. Continúan durante los cinco minutos completos.
- 22:50:15 aprox.: se envía LSB: `FE FE 94 E1 06 00 01 FD`. No llega ACK (`FB`), NAK (`FA`) ni respuesta de estado.
- Las órdenes posteriores USB, DATA ON y DATA OFF tampoco producen respuesta de aceptación ni cambio observable.
- 22:50:21.499: al mover el dial, llega una trama espontánea `FE FE 00 94 00 00 60 13 10 00 FD`, interpretada correctamente como `10 136 000 Hz`.
- 22:51:37.069: llega `FE FE 94 E1 25 00 FD`, idéntica a nuestra consulta de frecuencia. Es un eco de la consulta, no una respuesta de la radio.
- Después cesan los paquetes CI-V de datos/espectro. Los latidos tipo 7 siguen llegando hasta finalizar la prueba; por tanto, el socket UDP y la radio siguen accesibles.
- 22:54:45: final programado de la sesión, sin caída del proceso ni error de red.

## Análisis

### 1. No existe una desconexión de red real

El flujo de latidos radio→aplicación no se interrumpe. Lo que caduca o queda fuera de secuencia es el flujo de datos CI-V. La interfaz muestra una desconexión funcional, pero la asociación UDP secundaria permanece viva.

### 2. Las órdenes llegan al flujo, pero la radio no las ejecuta

El eco de `FE FE 94 E1 25 00 FD` demuestra que la consulta entra en el canal serie virtual. La ausencia total de ACK/NAK y de respuestas apunta a una dirección CI-V de controlador incorrecta (`E1` frente a `E0`) o a que el transporte considera inválida la secuencia del paquete.

### 3. Hay un error confirmado en la secuencia exterior de control

Los paquetes de login, autenticación, solicitud de flujos, renovación e inactividad pertenecen a una única secuencia de transporte. En la implementación actual:

- login usa secuencia exterior 1;
- el paquete inicial de token deja la secuencia en 0;
- CONNINFO fuerza la secuencia 2;
- los paquetes idle arrancan otra vez en 0;
- cada renovación de token vuelve a usar 0.

Esto introduce secuencias duplicadas y fuera de orden. La implementación de referencia envía todos esos paquetes mediante el mismo contador de paquetes rastreados. Es la causa más sólida del cese del flujo tras uno o dos minutos y debe corregirse antes de interpretar otras pruebas.

### 4. El flujo CI-V también se está sobrealimentando

Cada segundo se envían tanto un paquete idle como una consulta de frecuencia. El paquete idle solo debe enviarse cuando no se ha enviado otro paquete rastreado durante ese intervalo. Además, el watchdog reabre el canal repetidamente y suma más números de secuencia. Esto no explica por sí solo la falta total de respuesta, pero hace menos estable la sesión y dificulta el diagnóstico.

### 5. Próxima prueba controlada

La siguiente compilación debería:

1. usar un único contador de secuencia exterior para todo el canal de control;
2. usar idle únicamente después de un segundo sin tráfico rastreado;
3. retirar reaperturas y reintentos agresivos mientras se valida el transporte;
4. probar las órdenes CI-V con controlador `E0`, registrando por separado eco, ACK, NAK y respuesta;
5. mantener el contador interior CI-V en big-endian, como indica el formato del flujo serie.

## Conclusión

La prueba reproduce ambos fallos. La frecuencia recibida al mover el dial prueba que el decodificador funciona. El problema está antes: las consultas y escrituras no reciben respuesta y el flujo de datos queda fuera de servicio aunque el heartbeat siga activo. El primer defecto verificable que hay que corregir es la secuencia exterior compartida del canal de control; después se debe aislar la dirección CI-V `E0`/`E1` con una prueba mínima.

## Repetición después de las correcciones (22:59:18–23:04:18)

Se repitió la misma prueba durante cinco minutos después de unificar la secuencia exterior del canal de control y cambiar las órdenes CI-V de `E1` a `E0`. La captura íntegra está en `LAN_SESSION_2026-09-03_FIXED.log`.

- El flujo CI-V permaneció activo durante los cinco minutos completos, superando ampliamente el punto de fallo anterior.
- La consulta `FE FE 94 E0 25 00 FD` recibió repetidamente respuestas `FE FE E0 94 25 00 [frecuencia] FD`, incluso sin depender de la notificación broadcast dirigida a `00`.
- DATA ON recibió ACK positivo `FE FE E0 94 FB FD` a las 23:00:18.092.
- DATA OFF recibió ACK positivo `FE FE E0 94 FB FD` a las 23:00:33.080.
- Las pruebas de LSB y USB, ejecutadas antes de la primera renovación de autenticación, no recibieron ACK ni NAK. Deben repetirse aisladamente después de estabilizar la retransmisión de paquetes solicitados por la radio.
- La radio pidió reiteradamente retransmitir los paquetes exteriores 1 y 3 mediante paquetes tipo 1 (`01 00 03 00`). La implementación todavía registra pero no atiende esta solicitud.

Resultado: quedan resueltos el corte del flujo y la ruta CI-V de DATA. También se confirmó la respuesta activa de frecuencia; se añadió su decodificación a la aplicación. El cambio de modo sigue pendiente de aislar junto con la retransmisión solicitada por el protocolo.

## Segunda repetición (23:09:52–23:14:52)

Captura: `LAN_SESSION_2026-09-03_REPEAT.log` (9689 líneas, 1.3 MiB).

- El flujo CI-V volvió a mantenerse activo durante los cinco minutos completos.
- Se recibieron 245 respuestas explícitas de frecuencia. La primera fue a las 23:10:47 y la última a las 23:14:51, un segundo antes del cierre programado.
- DATA ON recibió ACK positivo a las 23:10:52.070.
- DATA OFF recibió ACK positivo a las 23:11:07.078.
- LSB y USB no recibieron ACK ni NAK.
- Se registraron 126 solicitudes tipo 1 de retransmisión. La radio sigue reclamando paquetes que la aplicación no conserva ni reenvía.

Esta repetición confirma que la estabilidad y la lectura activa de frecuencia están corregidas, y que DATA funciona de manera reproducible. El fallo restante queda limitado al cambio de modo y al manejo incompleto de retransmisiones.
