# Resumen de archivos del proyecto Icom IC-7300MK2

Fecha del inventario: 22 de octubre de 2026.

Ubicación principal: `/home/ramon/Icom7300MK2`.

Este documento recoge los archivos de desarrollo visibles en el inventario local. Las carpetas de compilación, los metadatos Git y las carpetas locales de herramientas se describen por separado; no se enumeran sus archivos internos. Las descripciones son un mapa de ubicación y responsabilidad, no una certificación de funcionamiento ni de validación física.

## Organización general

- La aplicación principal utiliza C++20, Qt 6, QML y CMake. Sus fuentes están directamente en la raíz.
- El subsistema UV-K5 está en `quansheng/`, con protocolo y transporte propios.
- Arquitectura prevista: Icom conectado al HP principal; Quansheng conectado por USB al Pavilion y accesible desde el HP principal por LAN.
- El código actual incluye ampliaciones posteriores al contexto inicial: cliente y servidor LAN Quansheng, GUI de servidor y módulos experimentales. Consultar `quansheng/PROJECT_CONTEXT.md` para sus estados de confirmación y límites.
- La presencia de un módulo de control o una prueba no autoriza a ejecutarlo contra la radio. Se mantienen las instrucciones de seguridad de los archivos `AGENTS.md`.

## Cómo leer los nombres

- `.cpp`: implementación C++; `.h`: declaraciones e interfaces.
- `.qml`: interfaz gráfica Qt; `.html`: interfaz web.
- `.py` y `.sh`: herramientas, automatización o pruebas.
- `.md` y `.txt`: documentación; `.hex`, `.jsonl` y `.gz`: fixtures, registros o capturas.
- `.desktop`: lanzador del escritorio Linux; `.1`: página de manual.

## Aplicación principal

Archivos de la raíz que implementan la aplicación Qt/QML y sus controladores.

- `Main.qml` — Interfaz principal de control de las radios.
- `MorseTrainerWindow.qml` — Ventana del entrenador de Morse.
- `SelectableLabel.qml` — Componente de texto seleccionable.
- `applicationlauncher.cpp` — Lanzamiento e integración de aplicaciones externas.
- `applicationlauncher.h` — Lanzamiento e integración de aplicaciones externas.
- `main.cpp` — Inicio de la aplicación y registro de componentes para QML.
- `morsetrainer.cpp` — Lógica del entrenador de Morse.
- `morsetrainer.h` — Lógica del entrenador de Morse.
- `qrzlogbookcontroller.cpp` — Integración con el libro de guardia de QRZ.
- `qrzlogbookcontroller.h` — Integración con el libro de guardia de QRZ.
- `quanshengclient.cpp` — Cliente de comunicación LAN con el servidor Quansheng.
- `quanshengclient.h` — Cliente de comunicación LAN con el servidor Quansheng.
- `radiocontroller.cpp` — Control del Icom y comunicaciones con la radio.
- `radiocontroller.h` — Control del Icom y comunicaciones con la radio.
- `remoteserver.cpp` — Servidor de acceso remoto de la aplicación.
- `remoteserver.h` — Servidor de acceso remoto de la aplicación.
- `videocapturecontroller.cpp` — Gestión de captura de vídeo.
- `videocapturecontroller.h` — Gestión de captura de vídeo.

## Documentación y configuración general

Instrucciones, documentación, configuración de compilación e instalación.

- `.gitignore` — Exclusiones de archivos para Git.
- `AGENTS.md` — Reglas de trabajo y seguridad del repositorio.
- `CMakeLists.txt` — Configuración de compilación; versión principal declarada: 1.2.14.
- `COMANDOS_LAN_CONFIRMADOS.md` — Registro de comandos LAN confirmados del Icom.
- `GITHUB_RELEASES.md` — Documentación de publicación de versiones.
- `LAN_RETRANSMIT_TEST.log`
- `LAN_SESSION_2026-09-03.md` — Notas de la sesión de desarrollo LAN del 3 de septiembre de 2026.
- `LAN_SESSION_2026-09-03_FIXED.log`
- `LAN_SESSION_2026-09-03_REPEAT.log`
- `README.es.md` — Documentación general en español.
- `README.md` — Presentación e instrucciones generales del proyecto.
- `README.txt` — Documentación general en formato de texto.
- `install-linux-user.sh` — Instalación de la aplicación para el usuario de Linux.
- `org.icom.Icom7300Mk2Control.desktop` — Entrada de la aplicación en el menú del escritorio Linux.
- `qdock-pavilion-actualizado-20260914.tar.gz`
- `qdock-pavilion-eeprom-20260914.tar.gz`
- `qdock-pavilion-eeprom-completo-20260914.tar.gz`
- `qdock-pavilion-eeprom-table-20260914.tar.gz`

## Copias de seguridad de archivos

Copias anteriores al cambio de disposición de doble radio del 20 de septiembre de 2026. No son los fuentes activos enumerados en CMakeLists.txt.

- `Main.qml.before-dual-radio-layout-2026-09-20` — Interfaz principal de control de las radios.
- `applicationlauncher.cpp.before-dual-radio-layout-2026-09-20`
- `applicationlauncher.h.before-dual-radio-layout-2026-09-20`
- `quanshengclient.cpp.before-dual-radio-layout-2026-09-20`
- `quanshengclient.h.before-dual-radio-layout-2026-09-20`

## Interfaz web remota

Páginas de control remoto servidas por la aplicación.

- `remote/index.html`
- `remote/quansheng.html`

## Iconos

Recursos gráficos en PNG de distintos tamaños, SVG e ICO.

- `icons/icom7300mk2_control.ico`
- `icons/icom7300mk2_control.svg`
- `icons/icom7300mk2_control_128.png`
- `icons/icom7300mk2_control_256.png`
- `icons/icom7300mk2_control_32.png`
- `icons/icom7300mk2_control_48.png`
- `icons/icom7300mk2_control_512.png`
- `icons/icom7300mk2_control_64.png`

## Pruebas de la aplicación principal

Pruebas del receptor LAN y del cliente PTT Quansheng.

- `tests/lan_receiver_test.cpp`
- `tests/quansheng_ptt_client_test.cpp`

## Scripts y publicación

Automatización de compilación, publicación y flujos de GitHub.

- `.github/workflows/publicar-instaladores.yml`
- `.github/workflows/publicar-version.yml`
- `scripts/build-timestamp.cmake`
- `scripts/publicar-version.sh`
- `scripts/sincronizar-quansheng.sh` — Publica `quansheng/` en el repositorio QuanshengDock-Linux.

## Empaquetado y manuales

Generación de paquetes Debian, instrucciones de instalación y páginas de manual.

- `packaging/INSTALAR.md`
- `packaging/build-deb.py`
- `packaging/man/Icom7300Mk2Control.1`
- `packaging/man/qdock-probe.1`
- `packaging/man/qdock-server-gui.1`
- `packaging/man/qdock-server.1`

## Quansheng: documentación y configuración

Contexto, reglas, licencia, configuración CMake y documentación de protocolo.

- `quansheng/.gitignore`
- `quansheng/AGENTS.md`
- `quansheng/CMakeLists.txt`
- `quansheng/LICENSE`
- `quansheng/NOTICE`
- `quansheng/PROJECT_CONTEXT.md`
- `quansheng/README.md`
- `quansheng/cmake/build-timestamp.cmake`
- `quansheng/docs/LAN_PROTOCOL.md`
- `quansheng/docs/LIVE_SESSION_2026-09-11.md`
- `quansheng/docs/PROTOCOL.md`
- `quansheng/qdock-pavilion-diagnostico-20260913-220243-875074.raw`

## Quansheng: código fuente

Parser, modelo de pantalla, transporte serie, servidor LAN, GUI del servidor y módulos experimentales.

- `quansheng/src/core/displaymodel.cpp`
- `quansheng/src/core/displaymodel.h`
- `quansheng/src/core/parser.cpp`
- `quansheng/src/core/parser.h`
- `quansheng/src/core/tones.h`
- `quansheng/src/eventjson.cpp`
- `quansheng/src/eventjson.h`
- `quansheng/src/experimental/eeprom_main.cpp`
- `quansheng/src/experimental/eepromquery.cpp`
- `quansheng/src/experimental/eepromquery.h`
- `quansheng/src/experimental/keycontrol.cpp`
- `quansheng/src/experimental/keycontrol.h`
- `quansheng/src/experimental/register_main.cpp`
- `quansheng/src/experimental/registerquery.cpp`
- `quansheng/src/experimental/registerquery.h`
- `quansheng/src/experimental/rssi_main.cpp`
- `quansheng/src/experimental/rssiquery.cpp`
- `quansheng/src/experimental/rssiquery.h`
- `quansheng/src/gui/serverwindow.cpp`
- `quansheng/src/lan/serialsource.cpp`
- `quansheng/src/lan/serialsource.h`
- `quansheng/src/lan/server.cpp`
- `quansheng/src/main.cpp`
- `quansheng/src/serial/reader.cpp`
- `quansheng/src/serial/reader.h`

## Quansheng: pruebas y capturas

Pruebas C++ y Python, fixtures de reproducción y evidencia de sesiones físicas.

- `quansheng/docs/evidence/uvk5-live-2026-09-11.jsonl.gz`
- `quansheng/tests/displaymodel_tests.cpp`
- `quansheng/tests/eepromquery_tests.cpp`
- `quansheng/tests/fixtures/qdock-pavilion-diagnostico-20260913-212842-870613.raw`
- `quansheng/tests/fixtures/qdock-pavilion-diagnostico-20260913-213323-871451.raw`
- `quansheng/tests/fixtures/qdock-pavilion-diagnostico-20260913-213857-872067.raw`
- `quansheng/tests/fixtures/qdock-pavilion-diagnostico-20260913-220243-875074.raw`
- `quansheng/tests/fixtures/qdock-registers-435900.jsonl`
- `quansheng/tests/fixtures/radio-screen.hex`
- `quansheng/tests/fixtures/radio-status.hex`
- `quansheng/tests/keycontrol_tests.cpp`
- `quansheng/tests/lan_serial_test.py`
- `quansheng/tests/lan_test.py`
- `quansheng/tests/menu_read_test.py`
- `quansheng/tests/parser_tests.cpp`
- `quansheng/tests/probe_test.py`
- `quansheng/tests/ptt_test.py`
- `quansheng/tests/registerquery_tests.cpp`
- `quansheng/tests/rssiquery_tests.cpp`
- `quansheng/tests/serial_test.py`
- `quansheng/tests/tones_test.py`

## Quansheng: herramientas

Cliente LAN y scripts y lanzadores destinados al Pavilion.

- `quansheng/tools/diagnose-qdock-pavilion.sh`
- `quansheng/tools/lan_client.py`
- `quansheng/tools/qdock-diagnostico-pavilion.desktop`
- `quansheng/tools/qdock-server-gui.desktop`
- `quansheng/tools/qdock-server-pavilion.desktop`
- `quansheng/tools/qdock-server-telemetry.desktop`
- `quansheng/tools/start-qdock-pavilion-registers.sh`
- `quansheng/tools/start-qdock-pavilion-rssi.sh`
- `quansheng/tools/start-qdock-pavilion-telemetry.sh`
- `quansheng/tools/start-qdock-pavilion.sh`
- `quansheng/tools/update-qdock-pavilion.sh`

## Responsabilidades dentro de Quansheng

| Ubicación | Responsabilidad |
|---|---|
| `src/main.cpp` | Entrada del probe de protocolo. |
| `src/core/parser.*` | Parser incremental de tramas y eventos UI. |
| `src/core/displaymodel.*` | Reconstrucción del estado observable de pantalla. |
| `src/core/tones.h` | Definiciones relacionadas con CTCSS/DCS. |
| `src/eventjson.*` | Conversión de eventos a JSON. |
| `src/serial/reader.*` | Adquisición de datos mediante puerto serie. |
| `src/lan/server.cpp` | Servidor LAN Quansheng. |
| `src/lan/serialsource.*` | Fuente serie utilizada por el servidor LAN. |
| `src/gui/serverwindow.cpp` | Interfaz gráfica de configuración y ejecución del servidor. |
| `src/experimental/rssi*` | Consultas y decodificación experimental de RSSI. |
| `src/experimental/register*` | Consultas experimentales de registros. |
| `src/experimental/eeprom*` | Consulta y lectura experimental de EEPROM; no implica escritura. |
| `src/experimental/keycontrol.*` | Construcción y gestión de controles mediante teclas. |
| `tests/fixtures/` | Datos conservados para reproducir casos sin radio. |
| `docs/LAN_PROTOCOL.md` | Contrato de comunicación entre cliente y servidor. |
| `docs/PROTOCOL.md` | Estructura y observaciones del protocolo serie. |
| `PROJECT_CONTEXT.md` | Historial, confirmaciones, cuestiones pendientes y límites de cada ampliación. |

## Carpetas generadas y auxiliares

| Carpeta | Contenido |
|---|---|
| `build/` | Compilación de la aplicación principal: ejecutables, objetos, recursos Qt, configuración CMake y resultados de pruebas. |
| `quansheng/build/` | Única compilación del subsistema Quansheng; la aplicación principal busca aquí `qdock-server-gui`. |
| `build-packages/` | Directorios de preparación y resultados de empaquetado: `check/`, `dist/`, `icom/` y `quansheng/`. |
| `quansheng/reference/` | Ubicación de referencias externas; tratar como referencia de solo lectura. No se enumera su contenido en este inventario. |
| `.git/` | Historial, ramas y metadatos de Git. |
| `.github/workflows/` | Automatizaciones de publicación de GitHub. |
| `.agents/`, `.codex/`, `.aws/` | Carpetas locales auxiliares; su contenido no se inspecciona ni reproduce en este resumen. |

Los archivos generados por CMake, Ninja y Qt no son los fuentes que se deben editar para introducir cambios.

## Archivos recomendados para orientarse

1. `README.md`, `README.es.md` y `AGENTS.md`: descripción y reglas generales.
2. `CMakeLists.txt` y `main.cpp`: componentes compilados y arranque.
3. `Main.qml`: organización visual.
4. `radiocontroller.h` y `radiocontroller.cpp`: control del Icom.
5. `remoteserver.*` y `remote/`: acceso remoto.
6. `quanshengclient.*`: integración LAN del Quansheng en la aplicación principal.
7. `quansheng/AGENTS.md`, `quansheng/PROJECT_CONTEXT.md`, `quansheng/README.md` y `quansheng/docs/PROTOCOL.md`: contexto obligatorio antes de modificar el subsistema.

## Conservación y desarrollo

- Rama de desarrollo: `main`; versiones publicadas con etiquetas `vX.Y.Z`. La rama `codex-integracion` es histórica.
- Referencia estable indicada: rama `backup-pre-codex-2026-09-10`, commit `995f65c`; no modificarla.
- Mantener separados los protocolos Icom CI-V y Quansheng.
- Hacer cambios incrementales, compilar y ejecutar las pruebas relevantes cuando se modifique código.
- No realizar commits automáticamente.

Inventario: 132 archivos enumerados, sin contar este resumen ni los directorios excluidos descritos anteriormente.
