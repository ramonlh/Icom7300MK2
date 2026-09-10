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

## Subsistema Quansheng UV-K5

Este repositorio contiene también, bajo:

    quansheng/

el desarrollo nativo Linux para el Quansheng UV-K5.

Este subsistema procede del proyecto independiente QuanshengDock-Linux y conserva
su propio contexto, documentación, código y pruebas.

Antes de trabajar en cualquier archivo bajo quansheng/ leer obligatoriamente:

- quansheng/AGENTS.md
- quansheng/PROJECT_CONTEXT.md
- quansheng/README.md
- quansheng/docs/PROTOCOL.md

No asumir que el protocolo Quansheng es CI-V ni reutilizar directamente
RadioController del Icom para el UV-K5.

Mantener inicialmente separados:

- protocolo Icom CI-V;
- protocolo QuanshengDock/UV-K5;
- transporte serie;
- modelo de estado;
- autorización TX/PTT.

### Arquitectura física prevista

El IC-7300MK2 está conectado al HP principal.

El Quansheng UV-K5 permanece conectado físicamente por USB al HP Pavilion dv6,
porque allí el adaptador USB-serie PL2303 ha demostrado funcionar correctamente.

Arquitectura prevista:

    HP principal
    ~/Icom7300MK2
        |
        +-- IC-7300MK2 local
        |
        +-- cliente/control Quansheng
                 |
                LAN
                 |
                 v
          HP Pavilion dv6
                 |
            USB / serie
                 |
                 v
          Quansheng UV-K5

Por tanto, no asumir que /dev/ttyUSB0 del Quansheng existe en el HP principal.

El acceso físico al UV-K5 deberá residir inicialmente en el Pavilion y el
control desde la aplicación principal deberá diseñarse mediante comunicación LAN.

### Estado actual del Quansheng

Actualmente existe:

- parser de protocolo incremental;
- soporte de tramas AB CD;
- decodificación parcial de paquetes UI B5;
- transporte Qt QSerialPort de solo lectura;
- qdock-probe;
- capturas reales reproducibles;
- tests de parser, CLI y puerto serie.

Todavía NO existe:

- GUI Quansheng terminada;
- controlador completo de radio;
- protocolo LAN Pavilion <-> HP principal;
- modelo normalizado fiable de frecuencia/canal;
- emisor de comandos habilitado;
- TX/PTT habilitado.

Consultar quansheng/PROJECT_CONTEXT.md para distinguir siempre entre:

- CONFIRMADO;
- PARCIALMENTE CONFIRMADO;
- PENDIENTE.

### Seguridad Quansheng

Hasta nueva instrucción expresa:

- NO flashear firmware.
- NO ejecutar k5prog -F.
- NO escribir EEPROM.
- NO habilitar TX/PTT.
- NO enviar comandos al UV-K5 solo para probar una hipótesis.
- Priorizar replay y fixtures antes de pruebas físicas.
- No modificar servicios del Pavilion sin necesidad explícita.

La integración del Quansheng no debe deteriorar ni reestructurar las funciones
ya estables del IC-7300MK2.

### Integración

Primero diseñar y probar el subsistema Quansheng de forma independiente.

Después definir una interfaz entre el HP principal y el Pavilion.

Solo posteriormente estudiar una interfaz común de radio para la GUI.

No fusionar prematuramente RadioController del Icom con el controlador Quansheng.

## Subsistema Quansheng UV-K5

Este repositorio contiene también, bajo:

    quansheng/

el desarrollo nativo Linux para el Quansheng UV-K5.

Este subsistema procede del proyecto independiente QuanshengDock-Linux y conserva
su propio contexto, documentación, código y pruebas.

Antes de trabajar en cualquier archivo bajo quansheng/ leer obligatoriamente:

- quansheng/AGENTS.md
- quansheng/PROJECT_CONTEXT.md
- quansheng/README.md
- quansheng/docs/PROTOCOL.md

No asumir que el protocolo Quansheng es CI-V ni reutilizar directamente
RadioController del Icom para el UV-K5.

Mantener inicialmente separados:

- protocolo Icom CI-V;
- protocolo QuanshengDock/UV-K5;
- transporte serie;
- modelo de estado;
- autorización TX/PTT.

### Arquitectura física prevista

El IC-7300MK2 está conectado al HP principal.

El Quansheng UV-K5 permanece conectado físicamente por USB al HP Pavilion dv6,
porque allí el adaptador USB-serie PL2303 ha demostrado funcionar correctamente.

Arquitectura prevista:

    HP principal
    ~/Icom7300MK2
        |
        +-- IC-7300MK2 local
        |
        +-- cliente/control Quansheng
                 |
                LAN
                 |
                 v
          HP Pavilion dv6
                 |
            USB / serie
                 |
                 v
          Quansheng UV-K5

Por tanto, no asumir que /dev/ttyUSB0 del Quansheng existe en el HP principal.

El acceso físico al UV-K5 deberá residir inicialmente en el Pavilion y el
control desde la aplicación principal deberá diseñarse mediante comunicación LAN.

### Estado actual del Quansheng

Actualmente existe:

- parser de protocolo incremental;
- soporte de tramas AB CD;
- decodificación parcial de paquetes UI B5;
- transporte Qt QSerialPort de solo lectura;
- qdock-probe;
- capturas reales reproducibles;
- tests de parser, CLI y puerto serie.

Todavía NO existe:

- GUI Quansheng terminada;
- controlador completo de radio;
- protocolo LAN Pavilion <-> HP principal;
- modelo normalizado fiable de frecuencia/canal;
- emisor de comandos habilitado;
- TX/PTT habilitado.

Consultar quansheng/PROJECT_CONTEXT.md para distinguir siempre entre:

- CONFIRMADO;
- PARCIALMENTE CONFIRMADO;
- PENDIENTE.

### Seguridad Quansheng

Hasta nueva instrucción expresa:

- NO flashear firmware.
- NO ejecutar k5prog -F.
- NO escribir EEPROM.
- NO habilitar TX/PTT.
- NO enviar comandos al UV-K5 solo para probar una hipótesis.
- Priorizar replay y fixtures antes de pruebas físicas.
- No modificar servicios del Pavilion sin necesidad explícita.

La integración del Quansheng no debe deteriorar ni reestructurar las funciones
ya estables del IC-7300MK2.

### Integración

Primero diseñar y probar el subsistema Quansheng de forma independiente.

Después definir una interfaz entre el HP principal y el Pavilion.

Solo posteriormente estudiar una interfaz común de radio para la GUI.

No fusionar prematuramente RadioController del Icom con el controlador Quansheng.
