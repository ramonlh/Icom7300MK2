# Control IC-7300MK2

![Platform](https://img.shields.io/badge/platform-Linux-1793D1)
![Qt](https://img.shields.io/badge/Qt-6.4%2B-41CD52)
![C++](https://img.shields.io/badge/C%2B%2B-20-00599C)
![Version](https://img.shields.io/badge/version-1.2.12-blue)
![Status](https://img.shields.io/badge/status-en%20desarrollo-orange)

Aplicación de escritorio para **Linux** destinada al control del transceptor **Icom IC-7300MK2** mediante **CI-V**, desarrollada en **C++20, Qt 6 y QML**.

El objetivo del proyecto es disponer de un panel único, compacto y legible desde el que manejar las funciones habituales de la radio, mantener la sincronización con los cambios realizados desde el propio equipo y disponer de herramientas adicionales como spectrum/waterfall, memorias, diagnóstico CI-V y un entrenador Morse integrado.

> [!NOTE]
> Este proyecto está desarrollado específicamente alrededor del **IC-7300MK2**. No pretende ser, por el momento, un controlador CI-V genérico para todos los modelos Icom.

---

### v1.2.12 — Interfaz agrupada y S-Meter analógico

- La barra superior y los paneles laterales agrupan los controles por familias con colores y títulos diferenciados.
- Nuevo S-Meter analógico con aguja animada, lectura CI-V más regular y lectura digital complementaria.
- Redistribución del display, VFO, medidores y paneles inferiores para mejorar la visibilidad.
- La ventana principal usa una altura fija de 880 px y conserva el ancho ajustable.
- La ventana de control por Internet queda vinculada a la principal y se cierra explícitamente al salir.
- El cliente Android Auto incorpora actualización automática del S-Meter y pantallas de modo, filtro, banda y sintonía.

### v1.2.11 — Contraste del arranque automático remoto

- La opción **ACTIVAR INTERNET AL INICIAR EL PROGRAMA** usa texto blanco en negrita para que sea legible sobre el fondo oscuro.

### v1.2.10 — Memoria de bandas en control remoto

- Los botones de banda de la interfaz web recuerdan la última frecuencia utilizada por banda.
- La memoria es independiente para VFO A y VFO B y se guarda en la configuración del servidor remoto.
- Cada botón muestra la frecuencia memorizada y la banda en metros.



### v1.2.10 — Token remoto de 8 caracteres

El acceso web utiliza ahora un token alfanumérico de **8 caracteres**, pensado para ser fácil de teclear desde un teléfono u otro ordenador. Se omiten caracteres visualmente ambiguos (`0`, `1`, `I`, `L`, `O`). El token sigue siendo una protección adicional para uso dentro de una **LAN o VPN privada** como Tailscale/WireGuard; el servidor HTTP no debe publicarse directamente en Internet.

### v1.2.10 — Clave remota definida por el propietario

La clave de acceso al panel web puede fijarse manualmente desde la ventana **INTERNET**. Debe tener exactamente 8 caracteres alfanuméricos y se conserva entre reinicios, por lo que el propietario puede memorizarla y acceder sin consultar previamente el PC de la estación. La opción de generación aleatoria continúa disponible.

## Control remoto v1.2.11

- Entrada de frecuencia compatible con `14.074.000`, `14.074`, `14074` y `14074000`.
- Cambio de frecuencia con `Enter`, botones de paso y clic sobre Spectrum/Waterfall.
- Waterfall con rejilla y marcas de frecuencia reales.
- Conserva todos los controles remotos introducidos en v1.2.1 y el Spectrum/Waterfall de v1.2.2.

## Estado del proyecto

Versión actual: **1.2.12**

El programa se encuentra en desarrollo activo. Las funciones principales de control CI-V, VFO, niveles, memorias, spectrum/waterfall y entrenador Morse están implementadas y se siguen refinando.

Plataforma principal de desarrollo y pruebas:

- Linux Mint / Ubuntu.
- Qt 6.4 o posterior.
- Conexión USB con el IC-7300MK2.
- CI-V a **115200 baud**.
- Dirección CI-V recomendada para el IC-7300MK2: **0x94**.

---

## Funciones principales

### Conexión CI-V

- Detección y conexión al puerto serie de la radio.
- Detección genérica de USB (B) / `if02` sin números de serie codificados en los fuentes.
- En Linux se prioriza el enlace persistente de `/dev/serial/by-id/` y, como respaldo, la identificación de `bInterfaceNumber=02` mediante sysfs.
- Configuración manual del puerto, velocidad y dirección CI-V.
- Reconexión.
- Polling periódico del estado.
- Confirmación de órdenes CI-V.
- Cierre explícito del puerto al salir para evitar que quede bloqueado.
- Diagnóstico de tráfico CI-V TX/RX.
- Sincronización con cambios efectuados desde el frontal de la radio.

### VFO y frecuencia

- VFO A y VFO B.
- Selección directa del VFO.
- `A=B`.
- Intercambio `A/B`.
- SPLIT.
- RIT.
- ΔTX.
- Introducción directa de frecuencia.
- Ajustes de frecuencia por pasos.
- Pasos de sintonía configurables.
- Botones de banda.
- Mando de sintonía gráfico.

### Modos y filtros

Modos disponibles desde el panel:

- LSB
- USB
- CW
- CW-R
- RTTY
- RTTY-R
- AM
- FM

Además:

- DATA ON/OFF.
- FIL1 / FIL2 / FIL3.
- Curva y forma de filtro.
- Sincronización del modo y filtro con la radio.

### Niveles y recepción

- AF Gain.
- RF Gain.
- Squelch.
- RF Power.
- Preamplificador.
- Atenuador.
- AGC.
- Noise Blanker.
- Nivel de NB.
- Noise Reduction.
- Nivel de NR.
- Auto Notch.
- Manual Notch.
- Posición y anchura del notch.
- Twin PBT.
- IP+.

### Transmisión

- PTT desde software.
- RF Power.
- Mic Gain.
- Compresor.
- Nivel de compresión.
- Monitor.
- Nivel de monitor.
- VOX.
- VOX Gain.
- Anti-VOX.
- Filtro TX.
- Tuner.
- Lectura de estado TX.

> [!WARNING]
> Las funciones de transmisión pueden hacer que la radio emita RF. Comprueba siempre la antena, carga, potencia y condiciones de operación antes de activar TX, TUNE, BK-IN u otras funciones de transmisión.

### CW

- CW Pitch.
- Key Speed.
- Break-in.
- Break-in Delay.
- APF.
- Side Tone Level.
- Dot/Dash Ratio.
- Rise Time.
- Paddle Reverse.
- Key Type.
- Memorias del keyer.
- Mensaje CW directo.

### FM y RTTY

- Repeater Tone.
- Tone Squelch.
- Frecuencias de tono.
- Twin Peak Filter.
- Mark Frequency.
- Shift Width.
- Keying Reverse.

### Medidores

Lectura gráfica de diferentes medidas proporcionadas por la radio:

- S-Meter.
- Potencia.
- SWR.
- ALC.
- COMP.
- Tensión.
- Corriente.
- Estado de overflow cuando está disponible.

### Spectrum Scope y Waterfall

La interfaz remota web incluye desde la versión 1.2.10 un **Spectrum Scope y Waterfall en tiempo real**. El navegador recibe los 475 niveles de cada trama CI-V y los dibuja localmente, evitando transmitir capturas de pantalla.

Desde la web se puede:

- iniciar y detener el stream del scope;
- seleccionar modo CENTER/FIXED/SCROLL;
- seleccionar span;
- cambiar FAST/MID/SLOW;
- activar HOLD y VBW WIDE;
- limpiar el waterfall local;
- pulsar sobre spectrum o waterfall para sintonizar la frecuencia indicada.

La escala vertical del spectrum es relativa, de **0 a −80 dB**.

- Spectrum scope.
- Waterfall.
- Span configurable.
- Hold.
- Velocidad de barrido.
- VBW.
- Escala gráfica.
- Limpieza del waterfall.

### Memorias

- Lectura de memorias.
- Lectura conjunta de canales.
- Visualización de canales ocupados y libres.
- Selección de memoria.
- Copia a VFO.
- Escritura y sobrescritura.
- Gestión de registros de banda.

### Scanner

- Inicio y parada de scan.
- Selección de tipo de escaneo.
- Estado del escáner.

### Diagnóstico CI-V

Incluye una ventana específica para comprobar:

- Última trama enviada.
- Última trama recibida.
- Historial TX.
- Historial RX.
- Estado de conexión.
- Puerto activo.
- Parámetros CI-V.

Es especialmente útil para desarrollar nuevas funciones o comprobar el comportamiento real de la radio.

---


## Control remoto web

Desde la versión **1.2.0** el programa incorpora un servidor web integrado para controlar la radio desde un navegador sin abrir un segundo puerto CI-V.

En **v1.2.10** la interfaz remota de escritorio se compacta para caber en una pantalla de 1366×768 sin scroll vertical y añade A=B, intercambio de VFO, RIT/ΔTX, NB/NR, notch, IP+, Twin PBT y forma de filtro. En móvil se conserva el diseño adaptable con desplazamiento cuando sea necesario.

El servidor forma parte del mismo proceso y utiliza el mismo `RadioController` que la interfaz QML local. De esta forma, los cambios realizados desde el navegador, el panel local o la propia radio convergen en el mismo estado CI-V.

### Primera versión remota

Incluye:

- servidor HTTP integrado;
- puerto predeterminado `7300`, configurable;
- autenticación obligatoria mediante token aleatorio;
- interfaz adaptable a ordenador, tablet y móvil;
- estado de VFO A/B, frecuencia, modo, filtro, DATA, SPLIT y S-meter;
- cambio de frecuencia;
- selección VFO A/B;
- modos LSB, USB, CW, RTTY, AM, FM, CW-R y RTTY-R;
- FIL1/FIL2/FIL3;
- DATA y SPLIT;
- AF Gain, RF Gain, SQL y RF Power;
- P.AMP, ATT, AGC y TUNER ON/OFF;
- bloqueo de modificaciones remotas mientras la radio está transmitiendo.

Por seguridad, esta primera versión **no expone PTT ni TUNE por Internet**.

### Acceso desde la red

En el programa principal abre **INTERNET**, inicia el servidor y utiliza una de las direcciones mostradas, por ejemplo:

```text
http://192.168.1.50:7300/
```

El navegador solicitará el token de acceso que aparece en la misma ventana de configuración.

### Acceso desde Internet

Se recomienda utilizar una VPN privada como **Tailscale** o **WireGuard**. El servidor escucha en las interfaces IPv4 del equipo, por lo que una dirección de la VPN aparecerá entre las direcciones disponibles cuando la VPN esté activa.

> [!WARNING]
> No se recomienda redirigir directamente el puerto `7300` desde el router a Internet. La versión 1.2.0 utiliza HTTP y está diseñada para operar dentro de una LAN o de una VPN privada.

El token puede regenerarse en cualquier momento. Al hacerlo, los navegadores que utilizaban el token anterior pierden el acceso.

# Entrenador Morse

El programa incluye un entrenador Morse con dos modalidades diferentes.

## 1. Manipulación

Pensado para practicar con el **manipulador real conectado al jack KEY del IC-7300MK2**.

El programa detecta el sidetone de la radio mediante el audio USB y reconstruye los puntos, rayas y caracteres.

Funciones:

- Selección de dispositivo de entrada de audio.
- Detección del nivel de entrada.
- Detección del tono CW.
- Umbral automático o manual.
- Visualización de `KEY DOWN`.
- Patrón Morse actual.
- Texto decodificado.
- Ejercicios Koch.
- Velocidad de carácter.
- Velocidad efectiva Farnsworth.
- Puntuación.
- Estadísticas por sesión y lección.

### Preparar radio

La opción **PREPARAR RADIO** guarda los parámetros relevantes de la radio antes del ejercicio y configura el equipo para la práctica.

Al cerrar el entrenador se intenta restaurar el estado anterior de:

- modo;
- DATA;
- filtro;
- potencia RF;
- Break-in;
- CW Pitch;
- velocidad del manipulador.

El modo recomendado para practicar es **BK-IN OFF**, de forma que el manipulador genere sidetone sin transmitir RF.

## 2. Recepción y copia

Genera ejercicios Morse desde el ordenador para practicar recepción de oído.

Incluye:

- Método Koch.
- Farnsworth activable/desactivable.
- Velocidad de carácter.
- Velocidad efectiva.
- Número de grupos.
- Caracteres por grupo.
- Cuenta atrás configurable antes de comenzar.
- Repetición del ejercicio.
- Campo para escribir lo copiado.
- Reproducción de símbolos individuales.
- Letras, números y signos Morse.
- Puntuación automática.
- Comparación visual entre enviado y copiado.

### Comparación de errores

Al finalizar se muestran dos líneas alineadas:

- **ENVIADO**
- **COPIADO**

Los caracteres correctos aparecen diferenciados y los errores se resaltan en rojo.

La puntuación distingue:

- aciertos;
- sustituciones;
- omisiones;
- caracteres añadidos.

Los espacios usados únicamente para separar grupos no intervienen en la puntuación.

La comparación respeta estrictamente el número de símbolos transmitidos: en un ejercicio de 25 símbolos no puede aparecer un nuevo acierto después de la posición 25.

## Lecciones Koch

El avance de lección es manual.

Una lección se considera **SUPERADA** cuando alcanza una mejor nota de **90 o más**.

Cada lección puede resetearse de forma independiente sin eliminar las estadísticas del resto.

---

## Requisitos

### Hardware

- Icom IC-7300MK2.
- Cable USB entre la radio y el ordenador.
- Para la modalidad de manipulación Morse:
  - manipulador conectado al IC-7300MK2;
  - audio USB de la radio disponible en Linux.

### Software

- Linux.
- CMake 3.16 o posterior.
- Compilador con soporte C++20.
- Qt 6.4 o posterior con:
  - Qt Quick
  - Qt Quick Controls 2
  - Qt Serial Port
  - Qt Multimedia
  - Qt Network

En distribuciones basadas en Ubuntu/Linux Mint pueden instalarse las dependencias de desarrollo con:

```bash
sudo apt update
sudo apt install \
    build-essential \
    cmake \
    ninja-build \
    qt6-base-dev \
    qt6-declarative-dev \
    qt6-serialport-dev \
    qt6-multimedia-dev
```

Los nombres exactos de los paquetes pueden variar entre distribuciones.

---

## Permisos del puerto serie

En Linux, el usuario debe tener permiso para acceder a `/dev/ttyACM*`.

Comprueba los puertos disponibles:

```bash
ls -l /dev/ttyACM*
ls -l /dev/serial/by-id/
```

Si es necesario, añade tu usuario al grupo `dialout`:

```bash
sudo usermod -aG dialout "$USER"
```

Después **cierra completamente la sesión de usuario y vuelve a entrar** para que el nuevo grupo tenga efecto.

Puedes comprobarlo con:

```bash
groups
```

---

## Configuración recomendada del IC-7300MK2

Valores utilizados habitualmente con el proyecto:

| Parámetro | Valor |
|---|---:|
| Velocidad CI-V | 115200 baud |
| Dirección CI-V | 94h / 0x94 |
| Conexión | USB |
| Interfaz | Puerto CI-V correspondiente al IC-7300MK2 |

El programa permite modificar estos parámetros desde la configuración de conexión si tu instalación utiliza otros valores.

Para el entrenador Morse mediante sidetone USB, asegúrate además de que la radio envía por USB el audio/beep necesario para escuchar el tono CW.

---

## Compilación desde terminal

Clona el repositorio:

```bash
git clone <URL-DEL-REPOSITORIO>
cd Icom7300Mk2Control
```

Configura el proyecto:

```bash
cmake -S . -B build -G Ninja
```

Compila:

```bash
cmake --build build -j
```

Ejecuta:

```bash
./build/Icom7300Mk2Control
```

---

## Compilación con Qt Creator

1. Abre Qt Creator.
2. Selecciona **Open Project**.
3. Abre `CMakeLists.txt`.
4. Selecciona un kit Qt 6.4 o superior.
5. Configura el proyecto.
6. Compila.
7. Ejecuta `Icom7300Mk2Control`.

---

## Instalación local en Linux

El `CMakeLists.txt` incluye reglas de instalación para Linux.

Después de compilar:

```bash
cmake --install build --prefix "$HOME/.local"
```

Esto instala:

- ejecutable en `~/.local/bin`;
- archivo `.desktop`;
- iconos de diferentes tamaños.

Comprueba que `~/.local/bin` forma parte de tu `PATH`.

También se incluye:

```text
install-linux-user.sh
```

Este script instala el lanzador y los iconos para el usuario actual cuando el ejecutable ya se encuentra accesible desde el `PATH`.

Uso:

```bash
chmod +x install-linux-user.sh
./install-linux-user.sh
```

---

## Estructura del proyecto

```text
Icom7300Mk2Control/
├── CMakeLists.txt
├── main.cpp
├── Main.qml
├── radiocontroller.cpp
├── radiocontroller.h
├── morsetrainer.cpp
├── morsetrainer.h
├── MorseTrainerWindow.qml
├── install-linux-user.sh
├── es.ramonlorenzo.Icom7300Mk2Control.desktop
├── icons/
│   ├── icom7300mk2_control.svg
│   ├── icom7300mk2_control_32.png
│   ├── icom7300mk2_control_48.png
│   ├── icom7300mk2_control_64.png
│   ├── icom7300mk2_control_128.png
│   ├── icom7300mk2_control_256.png
│   ├── icom7300mk2_control_512.png
│   └── icom7300mk2_control.ico
└── .gitignore
```

### Archivos principales

**`radiocontroller.cpp/.h`**  
Comunicación serie, protocolo CI-V, sincronización, control de la radio, memorias, scope y medidores.

**`Main.qml`**  
Interfaz principal.

**`morsetrainer.cpp/.h`**  
Generación y análisis Morse, audio, Koch/Farnsworth, puntuación y estadísticas.

**`MorseTrainerWindow.qml`**  
Interfaz del entrenador Morse.

---

## Uso básico

1. Conecta el IC-7300MK2 por USB.
2. Enciende la radio.
3. Ejecuta el programa.
4. Comprueba el indicador de conexión.
5. Si no conecta automáticamente, abre la configuración CI-V y selecciona:
   - puerto;
   - 115200 baud;
   - dirección `0x94`.
6. Cambia la frecuencia desde el programa o desde el dial de la radio y comprueba que ambos permanecen sincronizados.

---

## Solución de problemas

### La radio no conecta

Comprueba:

```bash
ls -l /dev/ttyACM*
ls -l /dev/serial/by-id/
```

Comprueba también:

- que el cable USB esté conectado;
- que ningún otro proceso tenga abierto el mismo puerto;
- que el usuario pertenezca a `dialout`;
- que CI-V esté configurado a la velocidad correcta;
- que la dirección de radio sea `0x94` si utilizas los valores recomendados.

Para localizar un proceso que tenga abierto un puerto:

```bash
lsof /dev/ttyACM0
lsof /dev/ttyACM1
```

### La segunda ejecución no conecta

Las versiones actuales realizan un cierre explícito del puerto CI-V al salir.

Si sigue ocurriendo, comprueba que no haya quedado un proceso anterior:

```bash
pgrep -a Icom7300Mk2Control
```

### No se detecta el sidetone Morse

Comprueba:

- dispositivo de audio USB seleccionado;
- salida de audio USB configurada en la radio;
- nivel de audio;
- CW Pitch;
- umbral de detección;
- que el medidor de entrada del entrenador se mueva.

En Linux también puedes revisar los dispositivos de audio desde PipeWire/PulseAudio.

### Los primeros símbolos de un ejercicio Morse se cortan

La reproducción incorpora un periodo de silencio previo para permitir que PipeWire/PulseAudio/ALSA estabilice la salida antes del primer símbolo.

Si el problema persiste, revisa que el dispositivo de audio no esté siendo suspendido agresivamente por el sistema.

---

## Uso simultáneo con otros programas

El proyecto está pensado para poder convivir con aplicaciones de modos digitales cuando la configuración de puertos e interfaces USB lo permite.

No intentes que dos procesos abran de forma exclusiva el **mismo dispositivo serie** al mismo tiempo. Si otro programa necesita control CI-V, utiliza la configuración de interfaces y puertos adecuada para evitar conflictos.

---

## Seguridad

Este software puede modificar parámetros de un transceptor real y activar funciones relacionadas con transmisión.

Antes de utilizarlo:

- comprueba la potencia;
- comprueba la carga o antena;
- comprueba la frecuencia;
- respeta la normativa aplicable;
- no dependas únicamente de la interfaz gráfica para evitar una transmisión accidental.

El desarrollador y los colaboradores no pueden garantizar el comportamiento de equipos, drivers, firmware o instalaciones externas al programa.

---

## Roadmap

Posibles líneas de desarrollo:

- Ampliación progresiva del control remoto web (scope/waterfall y audio remoto).
- Audio remoto.
- Adaptación completa a Windows.
- Separación opcional del entrenador Morse como aplicación independiente.
- Mejoras adicionales de scope/waterfall.
- Nuevas funciones CI-V disponibles en el IC-7300MK2.
- Más estadísticas y herramientas de aprendizaje Morse.

---

## Contribuciones

Las contribuciones, pruebas y reportes de errores son bienvenidos.

Al informar de un problema, resulta útil incluir:

- versión del programa;
- distribución Linux;
- versión de Qt;
- firmware de la radio;
- puerto utilizado;
- velocidad CI-V;
- pasos para reproducir el problema;
- salida relevante del diagnóstico CI-V.

Evita publicar números de serie, claves, contraseñas u otros identificadores privados en los informes.

---

## Memorias en el control remoto

Desde la versión **1.2.10**, la interfaz web incluye un gestor de las 99 memorias del IC-7300MK2 sin aumentar el tamaño del panel principal.

Funciones disponibles:

- lectura individual;
- lectura secuencial de las 99 memorias;
- resumen de canales leídos, ocupados y libres;
- filtros: todas, ocupadas, libres y sin leer;
- búsqueda por canal, nombre, frecuencia, modo o estado;
- selección de memoria (`IR`);
- copia de una memoria al VFO;
- vuelta al VFO anterior;
- cambio de nombre;
- guardado del estado actual en una memoria;
- borrado de memoria.

Las operaciones de escritura o borrado requieren confirmación en el navegador.

## Releases

Para versiones publicadas se recomienda utilizar **GitHub Releases** en lugar de almacenar ZIP de cada versión dentro del repositorio.

Ejemplo:

```text
v1.2.12
└── Icom7300Mk2Control_v1.2.12.zip
```

El repositorio principal debería contener el código fuente de la versión actual.

---

## Licencia

Antes de publicar el repositorio, añade un archivo `LICENSE` con la licencia elegida.

Si deseas una licencia permisiva para software abierto, **MIT** es una opción habitual.

---

## Aviso sobre marcas

**Icom** e **IC-7300MK2** son marcas o denominaciones pertenecientes a sus respectivos propietarios.

Este proyecto es independiente y no está afiliado, patrocinado ni respaldado oficialmente por Icom Inc.

> **v1.2.10:** corregida la pantalla de autenticación: la actualización periódica ya no borra la clave mientras se está escribiendo y `Enter` permite validarla.
