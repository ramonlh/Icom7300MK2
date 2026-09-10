# AGENTS.md — QuanshengDock-Linux

Lee `PROJECT_CONTEXT.md` completo antes de modificar nada.

## Misión
Desarrollar un port Linux nativo de QuanshengDock usando Qt 6/C++/CMake, reutilizando
el protocolo y comportamiento del upstream GPL v2 sin depender de Wine/WPF.

## Reglas críticas
- No flashees firmware.
- No ejecutes `k5prog -F`.
- No escribas EEPROM en las primeras fases.
- Mantén TX/PTT bloqueado hasta aprobación explícita.
- Mantén `~/QuanshengDock` y `~/.wine-quanshengdock` intactos como referencia.
- Trata repositorios upstream clonados como referencia de solo lectura.
- El primer entregable debe ser un probe serie READ-ONLY con tests.
- Antes de usar `/dev/ttyUSB0` real, explica la prueba y pide autorización.
- No uses sudo para acceder al puerto serie; el usuario pertenece a `dialout`.
- Si falta una dependencia del sistema, explica el paquete y pide permiso antes de
  instalarlo con sudo.

## Forma de trabajo
1. Inspecciona antes de editar.
2. Haz cambios pequeños y verificables.
3. Compila y ejecuta tests después de cada bloque lógico.
4. No ocultes errores desactivando comprobaciones.
5. Documenta las decisiones de protocolo.
6. Mantén el protocolo independiente de la GUI.

## Inicio de cada sesión
Revisa:
- `PROJECT_CONTEXT.md`
- `README.md`
- `git status`
- el trabajo existente

Después resume brevemente el estado y continúa desde el último punto, sin recrear
el proyecto desde cero.
