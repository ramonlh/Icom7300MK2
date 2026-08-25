CONTROL IC-7300MK2 - VERSIÓN 1.2.11


CAMBIOS 1.2.11 - MEJORA DE CONTRASTE EN OPCIÓN DE ARRANQUE REMOTO
- El texto del CheckBox de arranque automático del servidor remoto se muestra ahora en blanco y negrita.
- Texto aclarado a: "ACTIVAR INTERNET AL INICIAR EL PROGRAMA".

CAMBIOS 1.2.10 - CORRECCIÓN DE ESCRITURA DE CLAVE REMOTA
- La actualización periódica no consulta el servidor hasta que existe una clave candidata válida.
- Un error 401 ya no reescribe el campo mientras el usuario está escribiendo.
- Una credencial incorrecta se elimina del navegador y se solicita de nuevo.
- La tecla Enter valida la clave igual que el botón ENTRAR.

CAMBIOS 1.2.9 - CLAVE REMOTA FIJADA POR EL PROPIETARIO
- Eliminadas del código las rutas /dev/serial/by-id que contenían el número de serie de la radio de desarrollo.
- La interfaz USB (B) / if02 se localiza dinámicamente buscando IC-7300MK2 en /dev/serial/by-id.
- Si no existe /dev/serial/by-id, Linux intenta identificar bInterfaceNumber=02 mediante sysfs.
- Se mantiene un fallback genérico con QSerialPortInfo y selección manual desde Configuración.
- No quedan rutas /home/... ni identificadores particulares del equipo de desarrollo en los fuentes.

- La salida de audio se activa al comenzar la cuenta atrás, no al terminarla.
- El silencio de la cuenta atrás sirve como precalentamiento para PipeWire/PulseAudio/ALSA.
- El primer símbolo comienza cuando el dispositivo ya está estable.
- Los botones de sonidos Morse incorporan también un preámbulo de seguridad de 900 ms.
- Se conserva un silencio final corto para evitar cortes secos al cerrar la salida.

- La lección seleccionada muestra LECCIÓN SUPERADA al alcanzar una mejor nota de 90 o más.
- RESETEAR elimina únicamente las sesiones de la lección seleccionada.
- El resto de lecciones y su historial permanecen intactos.

- Al finalizar un ejercicio de recepción se muestran el texto enviado y el texto copiado, uno debajo del otro.
- Los caracteres correctos del texto copiado aparecen en verde.
- Las sustituciones, omisiones y caracteres añadidos aparecen en rojo.
- Las omisiones y los añadidos se representan con un punto centrado para conservar la alineación de ambas líneas.
- La comparación ocupa el panel existente y no aumenta el tamaño de la ventana Morse.

CAMBIOS ANTERIORES CONSERVADOS EN EL HISTORIAL DEL PROYECTO.

- La comparación ya no puede desplazar una coincidencia posterior al final del ejercicio.
- En un ejercicio de 25 símbolos, cualquier carácter escrito a partir de la posición 26 se cuenta siempre como añadido/error.
- La comparación visual marca esos caracteres posteriores en rojo.

CONTROL REMOTO WEB 1.2.0
- Servidor HTTP integrado en el mismo proceso que RadioController: no duplica el puerto CI-V.
- Puerto predeterminado 7300, configurable.
- Autenticación obligatoria mediante token aleatorio persistente.
- Interfaz web responsive para navegador de PC, tablet o móvil.
- Estado remoto: conexión, RX/TX, VFO A/B, frecuencia, modo, filtro, DATA, SPLIT, niveles y S-meter.
- Control remoto: frecuencia, VFO, modo, filtros, DATA, SPLIT, AF/RF/SQL/RF Power, P.AMP, ATT, AGC y TUNER ON/OFF.
- PTT y TUNE NO se exponen en esta primera versión.
- Todas las modificaciones remotas se bloquean mientras la radio está transmitiendo.
- Diseñado para acceso por LAN o VPN privada (Tailscale/WireGuard). No se recomienda redirigir el puerto 7300 directamente desde Internet.
CONTROL REMOTO WEB 1.2.9
-------------------------
- Interfaz de escritorio compactada para caber en una pantalla de 1366x768 sin scroll vertical.
- VFO A/B, A=B, intercambio A/B, RIT, Delta-TX y offset RIT.
- Bandas directas, modos, filtros, DATA y SPLIT en franjas compactas.
- NB/NR, niveles NB/NR, Auto Notch, Manual Notch, ancho/posición de notch, IP+ y Twin PBT.
- Forma de filtro SHARP/SOFT y controles rápidos de frecuencia.
- El servidor rechaza nuevas órdenes mientras CI-V está ocupado.
- PTT y TUNE de transmisión continúan sin estar expuestos por Internet.
- En pantallas pequeñas/móvil se permite scroll para conservar legibilidad.


CAMBIOS 1.2.9 - MEMORIAS WEB MÁS COMPACTAS
- El panel superpuesto de memorias reduce su ancho máximo de 1180 a 860 px sin eliminar funciones.

CONTROL REMOTO 1.2.9
- Token de acceso de 8 caracteres alfanuméricos.
- Se evitan 0, 1, I, L y O para facilitar la introducción manual.
- Los tokens largos de versiones anteriores se regeneran automáticamente al primer arranque.
- Recomendado únicamente detrás de una LAN/VPN privada; no exponer el puerto HTTP directamente a Internet.

CONTROL REMOTO 1.2.9
--------------------
- La clave de acceso remoto puede ser fijada manualmente por el propietario.
- Debe contener exactamente 8 letras o números.
- La clave queda guardada entre reinicios y no es necesario consultar el PC principal cada vez.
- Se conserva la opción ALEATORIA para generar una clave nueva automáticamente.
- Al cambiar la clave, los navegadores deberán autenticarse de nuevo.
