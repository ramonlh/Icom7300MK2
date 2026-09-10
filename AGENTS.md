# Icom IC-7300MK2 Control

## Objetivo

Este repositorio contiene una aplicación de control para el Icom IC-7300MK2.
La aplicación existente es funcional y debe conservarse estable mientras se
añaden nuevas funciones.

## Entorno

- Linux Mint
- Qt 6 / QML / C++
- CMake
- Ninja
- Hamlib disponible
- Radio: Icom IC-7300MK2
- CI-V confirmado: dirección 0x94
- Puerto habitual: /dev/ttyACM1
- Velocidad serie: 115200 baudios

## Regla principal

NO reestructurar, reemplazar ni reescribir componentes que ya funcionan sin
una necesidad concreta.

Antes de modificar código:

1. Inspeccionar el código existente.
2. Entender qué componente realiza actualmente la función.
3. Mantener compatibilidad con las funciones existentes.
4. Hacer cambios incrementales.
5. Compilar después de cambios significativos.
6. Ejecutar las pruebas disponibles cuando sean relevantes.
7. Mostrar claramente cualquier error encontrado.

## Funciones existentes importantes

La aplicación ya dispone, entre otras funciones, de:

- Lectura y escritura de frecuencia.
- Modos.
- DATA.
- Filtros.
- Estado RX/TX.
- VFO A/B.
- A=B.
- intercambio de VFO.
- Split.
- RIT / Delta TX.
- pasos de sintonía.
- AF.
- RF.
- SQL.
- potencia.
- preamplificador.
- atenuador.
- AGC.
- tuner.
- comunicaciones LAN desarrolladas y probadas.
- integración con programas externos como DECODIUM.

## Interfaz

Mantener como criterio general:

- Una ventana principal compacta.
- Evitar pestañas innecesarias.
- Evitar listas desplegables cuando pueden utilizarse botones directos.
- Controles asociados situados cerca de su indicador/display.
- Dos filas de botones de modos cuando proceda.
- VFO A/B claramente identificables.
- Mantener la estética actual salvo petición expresa.

## Seguridad del desarrollo

La rama de referencia funcional previa a esta integración es:

    backup-pre-codex-2026-09-10

Commit de referencia:

    995f65c

No modificar esa rama.

El desarrollo nuevo se realiza en:

    codex-integracion

## Archivos importantes

Antes de hacer cambios importantes revisar al menos:

- README.md
- CMakeLists.txt
- main.cpp
- Main.qml
- radiocontroller.cpp
- radiocontroller.h
- applicationlauncher.cpp
- applicationlauncher.h
- remoteserver.cpp
- remoteserver.h
- COMANDOS_LAN_CONFIRMADOS.md
- LAN_SESSION_2026-09-03.md

## Forma de trabajo con Codex

Cuando se solicite una nueva función:

1. Analizar primero el repositorio.
2. Explicar brevemente dónde se debe implementar.
3. Evitar duplicar funcionalidad existente.
4. Modificar únicamente los archivos necesarios.
5. Compilar.
6. Corregir errores de compilación antes de dar el trabajo por terminado.
7. Indicar los archivos modificados.
8. No realizar commits automáticamente salvo petición expresa.
