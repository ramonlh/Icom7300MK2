# Escucha UV-K5 por LAN — 11 de septiembre de 2026

Prueba realizada por el usuario, autorizada para 60 s de escucha ReadOnly.
Servidor en Pavilion, cliente en HP principal. No se enviaron comandos de radio.
Análisis de `/tmp/qdock-live-on.jsonl`, conservado comprimido en
`evidence/uvk5-live-2026-09-11.jsonl.gz` (JSON recibido, no bytes serie crudos).

SHA256 del JSON sin comprimir:
`c2b8d7d92e6c90dc1a6299a085bcf47062249a22659543b62ce0df6e1b9fc13c`.

## CONFIRMADO en el registro

- Sesión: `e1c8f4e4-dc89-484f-857e-5ba0563c8f19`.
- Servidor: 73777 bytes, 456 candidatos, 71041 descartados, 0 pendientes.
- Cliente: **376 eventos**, secuencias 81–456 contiguas.
- La suscripción anunció nextSequence 81; los 80 primeros eventos ocurrieron
  antes de suscribirse. No es evidencia de pérdida durante la conexión LAN.
- 188 candidatos tipo 5 y 188 tipo 6. Todos los tipo 6 recibidos indican
  power_save y batería derivada de 7.84 V. No hay eventos de texto en este archivo.
- Primer evento recibido: 11:48:55.143 UTC; último: 11:49:44.409 UTC.
- Final ended, error vacío y portOpen false.
- 456 × 6 = 2736 bytes de elementos UI; 73777 − 71041 = 2736.
  Esta coherencia contable no demuestra validez semántica de todos los candidatos.

No se conocen por este JSON los tipos/valores de los 80 eventos previos al cliente.
No presentar los 456 eventos globales como si estuviesen todos guardados en él.

## PARCIALMENTE CONFIRMADO

Recepción física de observaciones UI/estado y transporte al HP principal.
La indicación de batería deriva de upstream, sin calibración independiente.
La ausencia de texto impide inferir frecuencia/canal o reconstrucción de LCD.

## PENDIENTE

Origen y contenido de 71041 bytes descartados: esta sesión no tenía captura cruda.
No atribuirlos a pérdidas LAN, cable, baudrate o firmware como causa demostrada.
La nueva opción --capture permitirá investigar una escucha posterior autorizada
mediante replay offline, conservando ruido y tramas incompletas.

Una primera prueba comunicada tuvo 208 bytes, todos descartados, y 0 eventos.
El usuario aclaró después que la radio estaba apagada. Esa prueba no valida
comunicación del UV-K5; el origen de esos bytes permanece indeterminado.
