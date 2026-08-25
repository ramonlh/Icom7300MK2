# Cliente Android y Android Auto

Este módulo consume la API HTTP de la aplicación Linux. No accede al USB de la
radio y no incluye órdenes PTT ni TUNE.

1. Abra `android/` con Android Studio e instale el SDK 36 si se solicita.
2. Ejecute `app` en un teléfono o emulador Android 9 o posterior.
3. Introduzca la URL mostrada en **INTERNET** y la clave de ocho caracteres.
4. Pulse **Guardar y probar conexión** antes de abrir Android Auto.
5. Para desarrollo, pruebe la proyección mediante Desktop Head Unit.

HTTP sin cifrar se admite para el servidor actual, exclusivamente dentro de una
LAN o una VPN como Tailscale/WireGuard. No publique el puerto 7300 en Internet.

La primera versión muestra conexión, frecuencia, modo, filtro, banda y S-meter,
permite refrescar y sintonizar ±1 kHz, y bloquea controles durante TX o CI-V
ocupado. El servicio declara la categoría Android Auto `IOT`.
