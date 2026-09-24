# IC-7300MK2 Control

**English** | [Español](README.es.md)

![Platform](https://img.shields.io/badge/platform-Linux-1793D1)
![Qt](https://img.shields.io/badge/Qt-6.4%2B-41CD52)
![C++](https://img.shields.io/badge/C%2B%2B-20-00599C)
![Version](https://img.shields.io/badge/version-1.2.13-blue)
![Status](https://img.shields.io/badge/status-in%20development-orange)

Desktop application for **Linux** designed to control the **Icom IC-7300MK2** transceiver via **CI-V**, developed with **C++20, Qt 6 and QML**.

The goal of the project is to provide a single, compact and readable control panel for the radio's most commonly used functions, keep the software synchronized with changes made directly on the radio, and provide additional tools such as spectrum/waterfall, memories, CI-V diagnostics and an integrated Morse trainer.

> [!NOTE]
> This project is developed specifically around the **IC-7300MK2**. At present, it is not intended to be a generic CI-V controller for all Icom models.

---

### v1.2.13 — Quansheng dual-radio controls and band shortcuts

- The main window can show the Icom panel and Quansheng LAN panel side by side.
- Quansheng direct band buttons now include VHF 144-146 MHz and UHF 430-440 MHz shortcuts.
- Quansheng bands remember the last frequency and observed profile per VFO, including mode, power, step and tones.
- CTCSS/DCS read/write support is exposed through the Quansheng tone editor when the server enables keyboard control.
- Quansheng controls remain inhibited until a fresh display state arrives after a command, with a timeout fallback.

### v1.2.12 — Grouped interface and analog S-Meter

- The top bar and side panels group controls by function family, using distinct colors and titles.
- New analog S-Meter with an animated needle, smoother CI-V readings and an additional digital readout.
- Rearranged display, VFO, meters and lower panels for improved visibility.
- The main window uses a fixed height of 880 px while keeping the width adjustable.
- The Internet control window remains linked to the main window and is explicitly closed when the application exits.

### v1.2.11 — Improved contrast for remote auto-start

- The **ENABLE INTERNET AT PROGRAM START** option uses bold white text so it remains readable against the dark background.

### v1.2.10 — Band memory in remote control

- Band buttons in the web interface remember the last frequency used on each band.
- The memory is independent for VFO A and VFO B and is stored in the remote server configuration.
- Each button displays the stored frequency and the band in meters.



### v1.2.10 — 8-character remote token

Web access now uses an **8-character** alphanumeric token designed to be easy to type from a phone or another computer. Visually ambiguous characters (`0`, `1`, `I`, `L`, `O`) are omitted. The token remains an additional layer of protection intended for use inside a **LAN or private VPN** such as Tailscale/WireGuard; the HTTP server must not be exposed directly to the Internet.

### v1.2.10 — Owner-defined remote key

The access key for the web panel can be set manually from the **INTERNET** window. It must contain exactly 8 alphanumeric characters and is preserved across restarts, allowing the owner to memorize it and connect without first checking the station PC. Random key generation remains available.

## Remote control v1.2.11

- Frequency input supports `14.074.000`, `14.074`, `14074` and `14074000`.
- Frequency changes can be applied with `Enter`, step buttons and clicks on the Spectrum/Waterfall.
- Waterfall includes a grid and real frequency markers.
- Retains all remote controls introduced in v1.2.1 and the Spectrum/Waterfall introduced in v1.2.2.

## Project status

Current version: **1.2.13**

The application is under active development. The main CI-V control, VFO, level, memory, spectrum/waterfall and Morse trainer functions are implemented and continue to be refined.

The repository also includes an independent subsystem for the **Quansheng UV-K5**. Its protocol, serial transport, state model and transmission authorization remain separate from the Icom CI-V controller.

Main development and test platform:

- Linux Mint / Ubuntu.
- Qt 6.4 or later.
- USB connection to the IC-7300MK2.
- CI-V at **115200 baud**.
- Recommended CI-V address for the IC-7300MK2: **0x94**.

---

## Main features

### CI-V connection

- Detection and connection to the radio's serial port.
- Generic detection of USB (B) / `if02` without hard-coded serial numbers in the source code.
- On Linux, the persistent `/dev/serial/by-id/` link is preferred, with `bInterfaceNumber=02` identification through sysfs used as a fallback.
- Manual configuration of port, baud rate and CI-V address.
- Reconnection.
- Periodic status polling.
- CI-V command acknowledgment.
- Explicit port closing on exit to prevent it from remaining locked.
- CI-V TX/RX traffic diagnostics.
- Synchronization with changes made from the radio's front panel.

### VFO and frequency

- VFO A and VFO B.
- Direct VFO selection.
- `A=B`.
- `A/B` swap.
- SPLIT.
- RIT.
- ΔTX.
- Direct frequency entry.
- Frequency adjustment by steps.
- Configurable tuning steps.
- Band buttons.
- Persistent memory of the last frequency used on each band, independent for VFO A and VFO B.
- Graphical tuning dial.

### Modes and filters

Modes available from the panel:

- LSB
- USB
- CW
- CW-R
- RTTY
- RTTY-R
- AM
- FM

Additionally:

- DATA ON/OFF.
- Mode selection preserves the current DATA state, both over USB and LAN.

- FIL1 / FIL2 / FIL3.
- Filter curve and shape.
- Mode and filter synchronization with the radio.

### Levels and reception

- AF Gain.
- RF Gain.
- Squelch.
- RF Power.
- Preamplifier.
- Attenuator.
- AGC.
- Noise Blanker.
- NB level.
- Noise Reduction.
- NR level.
- Auto Notch.
- Manual Notch.
- Notch position and width.
- Twin PBT.
- IP+.

### Reception controls over LAN

The existing P.AMP, ATT, AGC, NB, NR, Auto Notch, Manual Notch and IP+ buttons,
as well as the AF, RF, SQL, NB level, NR level and notch position controls, also use
the LAN connection. The interface is updated from the radio responses, with one query
after each command and a polling cycle of about seven seconds to collect changes made
from the front panel.

Isolated tests for this path can be run with:

```bash
cmake -S . -B build -DICOM_BUILD_TESTS=ON
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

### Transmission

- Software PTT.
- RF Power.
- Mic Gain.
- Compressor.
- Compression level.
- Monitor.
- Monitor level.
- VOX.
- VOX Gain.
- Anti-VOX.
- TX filter.
- Tuner.
- TX status reading.

> [!WARNING]
> Transmission functions can cause the radio to emit RF. Always check the antenna, load, power level and operating conditions before enabling TX, TUNE, BK-IN or other transmission-related functions.

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
- Keyer memories.
- Direct CW message.

### FM and RTTY

- Repeater Tone.
- Tone Squelch.
- Tone frequencies.
- Twin Peak Filter.
- Mark Frequency.
- Shift Width.
- Keying Reverse.

### Meters

Graphical display of several measurements provided by the radio:

- S-Meter.
- Power.
- SWR.
- ALC.
- COMP.
- Voltage.
- Current.
- Overflow status when available.

### Spectrum Scope and Waterfall

Since version 1.2.10, the remote web interface includes a **real-time Spectrum Scope and Waterfall**. The browser receives all 475 levels from each CI-V frame and draws them locally, avoiding the need to transmit screenshots.

From the web interface you can:

- start and stop the scope stream;
- select CENTER/FIXED/SCROLL mode;
- select span;
- switch between FAST/MID/SLOW;
- enable HOLD and VBW WIDE;
- clear the local waterfall;
- click on the spectrum or waterfall to tune to the indicated frequency.

The vertical spectrum scale is relative, from **0 to −80 dB**.

- Spectrum scope.
- Waterfall.
- Configurable span.
- Hold.
- Sweep speed.
- VBW.
- Graphical scale.
- Waterfall clearing.

### Memories

- Memory reading.
- Combined channel reading.
- Display of occupied and free channels.
- Memory selection.
- Copy to VFO.
- Write and overwrite.
- Band register management.

### Scanner

- Start and stop scan.
- Scan type selection.
- Scanner status.

### CI-V diagnostics

Includes a dedicated window for checking:

- Last frame sent.
- Last frame received.
- TX history.
- RX history.
- Connection status.
- Active port.
- CI-V parameters.

It is especially useful when developing new functions or checking the radio's actual behavior.

---


## Web remote control

Since version **1.2.0**, the application includes an integrated web server for controlling the radio from a browser without opening a second CI-V port.

In **v1.2.10**, the desktop remote interface was compacted to fit a 1366×768 screen without vertical scrolling, and A=B, VFO swap, RIT/ΔTX, NB/NR, notch, IP+, Twin PBT and filter shape were added. On mobile devices, the adaptive layout is retained with scrolling where necessary.

The server runs within the same process and uses the same `RadioController` as the local QML interface. This allows changes made from the browser, the local panel or the radio itself to converge on the same CI-V state.

### First remote version

Includes:

- integrated HTTP server;
- default port `7300`, configurable;
- mandatory authentication using a random token;
- responsive interface for desktop, tablet and mobile;
- VFO A/B, frequency, mode, filter, DATA, SPLIT and S-meter status;
- frequency changes;
- VFO A/B selection;
- LSB, USB, CW, RTTY, AM, FM, CW-R and RTTY-R modes;
- FIL1/FIL2/FIL3;
- DATA and SPLIT;
- AF Gain, RF Gain, SQL and RF Power;
- P.AMP, ATT, AGC and TUNER ON/OFF;
- remote changes blocked while the radio is transmitting.

For safety reasons, this first version **does not expose PTT or TUNE over the Internet**.

### Access from the local network

In the main application, open **INTERNET**, start the server and use one of the displayed addresses, for example:

```text
http://192.168.1.50:7300/
```

The browser will request the access token shown in the same configuration window.

### Access from the Internet

A private VPN such as **Tailscale** or **WireGuard** is recommended. The server listens on the computer's IPv4 interfaces, so an address from the VPN will appear among the available addresses when the VPN is active.

> [!WARNING]
> Directly forwarding port `7300` from the router to the Internet is not recommended. Version 1.2.0 uses HTTP and is designed to operate within a LAN or private VPN.

The token can be regenerated at any time. When it is regenerated, browsers using the previous token lose access.

# Morse Trainer

The application includes a Morse trainer with two different operating modes.

## 1. Keying practice

Designed for practice using the **real key or paddle connected to the IC-7300MK2 KEY jack**.

The application detects the radio's sidetone through USB audio and reconstructs dots, dashes and characters.

Features:

- Audio input device selection.
- Input level detection.
- CW tone detection.
- Automatic or manual threshold.
- `KEY DOWN` display.
- Current Morse pattern.
- Decoded text.
- Koch exercises.
- Character speed.
- Farnsworth effective speed.
- Scoring.
- Statistics by session and lesson.

### Prepare radio

The **PREPARE RADIO** option saves the relevant radio parameters before the exercise and configures the radio for practice.

When the trainer is closed, it attempts to restore the previous state of:

- mode;
- DATA;
- filter;
- RF power;
- Break-in;
- CW Pitch;
- keyer speed.

The recommended mode for practice is **BK-IN OFF**, so the key or paddle generates sidetone without transmitting RF.

## 2. Receiving and copying

Generates Morse exercises from the computer for practicing copy by ear.

Includes:

- Koch method.
- Farnsworth on/off.
- Character speed.
- Effective speed.
- Number of groups.
- Characters per group.
- Configurable countdown before starting.
- Exercise replay.
- Field for typing copied text.
- Playback of individual symbols.
- Morse letters, numbers and punctuation.
- Automatic scoring.
- Visual comparison between sent and copied text.

### Error comparison

At the end, two aligned lines are shown:

- **SENT**
- **COPIED**

Correct characters are visually differentiated and errors are highlighted in red.

The score distinguishes between:

- correct characters;
- substitutions;
- omissions;
- extra characters.

Spaces used only to separate groups do not affect the score.

The comparison strictly respects the number of transmitted symbols: in a 25-symbol exercise, no new correct match can appear after position 25.

## Koch lessons

Lesson progression is manual.

A lesson is considered **PASSED** when its best score reaches **90 or higher**.

Each lesson can be reset independently without deleting statistics from the other lessons.

---

## Quansheng UV-K5 subsystem

The [`quansheng/`](quansheng/) directory contains the native Linux development for the **Quansheng UV-K5**. It originates from the independent QuanshengDock-Linux project and retains its own code, protocol, documentation and tests.

The integration keeps the following components separate:

- the Icom CI-V protocol;
- the QuanshengDock/UV-K5 protocol;
- serial transport;
- LAN transport;
- the observable state model;
- TX/PTT authorization.

The Icom `RadioController` is not reused as the Quansheng controller, and the integration does not alter the stable operation of the IC-7300MK2.

### Current architecture

The IC-7300MK2 is connected locally to the main HP computer. The Quansheng UV-K5 remains connected via USB/serial to the HP Pavilion dv6, where the PL2303 adapter operates reliably.

```text
Main HP computer
├── IC-7300MK2 local via CI-V
└── Quansheng client
       │
       └── LAN ──► qdock-server on HP Pavilion dv6
                         │
                         └── USB/serial ──► Quansheng UV-K5
```

Physical access to the `/dev/ttyUSB0` port resides on the Pavilion. The main application receives state through an independent TCP/JSON client and does not assume that this serial device exists on the main HP computer.

### Implemented features

- Incremental parser for the Quansheng protocol.
- Support for `AB CD` frames and `B5` interface events.
- Qt `QSerialPort` serial transport and `qdock-server` LAN server.
- LAN client integrated into the main interface.
- Passive reconstruction of the display state.
- Observation of VFO A/B, active selector, frequency, mode, memory, name and displayed power.
- RX state, battery, step, tone, DTMF and observable indicators.
- Experimental RSSI query.
- Experimental reading of BK4819 registers.
- Reserved table for all 128 BK4819 addresses `0x00–0x7F`.
- Interpretation of block, AGC, AFC, audio, RF, filter, squelch, PA, CTCSS/CDCSS, tone, scanner and DTMF registers.
- Slow polling of up to 50 registers every 30 seconds.
- Internal frequency query through registers `0x38/0x39` every two seconds.
- Full EEPROM read under explicit server authorization.
- Interpretation of 200 channels, including empty channels.
- View of settings, user options and calibrations.
- Complete 8192-byte hexadecimal dump.
- EEPROM user values from `0x0E70` through `0x0F47`.
- Highlighted display of call channel `0x0E70`, squelch `0x0E71`, channel display `0x0E79` and cross-band `0x0E7A`.
- Clipboard copy of the register table and EEPROM dump.
- Optional raw capture and session replay for reproducible testing.

Display-derived data that has not yet been fully validated is identified as candidate observations. Calibration values without a confirmed unit are retained as raw values, and secrets are not displayed in clear text.

### EEPROM reading

EEPROM reading is experimental and must be explicitly enabled when starting the server with:

```text
--allow-eeprom-query
```

The client requests 8192 bytes in 64 blocks of 128 bytes. The session uses only `Hello 0x0514` and `ReadEeprom 0x051B`; the application contains no EEPROM write path.

The `Hello` command may temporarily turn off the UV-K5 display backlight. Reading should be performed while the radio is being observed and stopped if any abnormal behavior appears.

### Safety limits

The following functions are currently blocked or not implemented:

- EEPROM writing;
- BK4819 register writing;
- GPIO writing;
- changing the Quansheng frequency or mode;
- remote key presses;
- TX/PTT;
- firmware flashing;
- execution of `k5prog -F`;
- modification of Pavilion services from the application.

EEPROM fields identified as user values are currently displayed in read-only mode. Their presence in the interface prepares future controls, but does not yet authorize or implement modification.

### Build and test the subsystem

From the repository root:

```bash
cmake -S quansheng -B build-quansheng -DQDOCK_SERIAL=ON
cmake --build build-quansheng -j2
ctest --test-dir build-quansheng --output-on-failure
```

On a system without Qt SerialPort, the core and replay components can be built with limited functionality:

```bash
cmake -S quansheng -B build-quansheng -DQDOCK_SERIAL=OFF
cmake --build build-quansheng -j2
ctest --test-dir build-quansheng --output-on-failure
```

The `QDOCK_SERIAL=OFF` configuration does not allow use of the real serial port.

### Start the Pavilion server

The telemetry launcher starts the server with RSSI, register access and on-demand EEPROM reading:

```bash
cd ~/qdock-readonly
./tools/start-qdock-pavilion-telemetry.sh
```

The script keeps TX/PTT, keys, EEPROM writing and register writing blocked.

### Quansheng documentation

- [Subsystem README](quansheng/README.md).
- [Context and confirmed status](quansheng/PROJECT_CONTEXT.md).
- [Serial protocol](quansheng/docs/PROTOCOL.md).
- [LAN protocol](quansheng/docs/LAN_PROTOCOL.md).
- [Development-specific rules](quansheng/AGENTS.md).

---

## Requirements

### Hardware

- Icom IC-7300MK2.
- USB cable between the radio and the computer.
- For Morse keying practice:
  - key or paddle connected to the IC-7300MK2;
  - radio USB audio available in Linux.

### Software

- Linux.
- CMake 3.16 or later.
- Compiler with C++20 support.
- Qt 6.4 or later with:
  - Qt Quick
  - Qt Quick Controls 2
  - Qt Serial Port
  - Qt Multimedia
  - Qt Network

On Ubuntu/Linux Mint-based distributions, the development dependencies can be installed with:

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

Exact package names may vary between distributions.

---

## Serial port permissions

On Linux, the user must have permission to access `/dev/ttyACM*`.

Check the available ports:

```bash
ls -l /dev/ttyACM*
ls -l /dev/serial/by-id/
```

If necessary, add your user to the `dialout` group:

```bash
sudo usermod -aG dialout "$USER"
```

Then **log out completely and log back in** for the new group membership to take effect.

You can verify it with:

```bash
groups
```

---


## Recommended IC-7300MK2 configuration

Values commonly used with the project:

| Parameter | Value |
|---|---:|
| CI-V baud rate | 115200 baud |
| CI-V address | 94h / 0x94 |
| Connection | USB |
| Interface | CI-V port corresponding to the IC-7300MK2 |

The application allows these parameters to be changed from the connection settings if your installation uses different values.

For the Morse trainer using USB sidetone, also make sure the radio sends the required audio/beep through USB so the CW tone can be heard by the application.

---

## Building from the terminal

Clone the repository:

```bash
git clone <REPOSITORY-URL>
cd Icom7300Mk2Control
```

Configure the project:

```bash
cmake -S . -B build -G Ninja
```

Build:

```bash
cmake --build build -j
```

Run:

```bash
./build/Icom7300Mk2Control
```

---


## Building with Qt Creator

1. Open Qt Creator.
2. Select **Open Project**.
3. Open `CMakeLists.txt`.
4. Select a Qt 6.4 or later kit.
5. Configure the project.
6. Build it.
7. Run `Icom7300Mk2Control`.

---

## Installable DEB packages

For Linux Mint 22 / Ubuntu 24.04 (amd64), see the [installation and packaging guide](packaging/INSTALAR.md).
Run `python3 packaging/build-deb.py` to build separate packages for the main application and the Quansheng server.

## Local installation on Linux

The `CMakeLists.txt` includes installation rules for Linux.

After building:

```bash
cmake --install build --prefix "$HOME/.local"
```

This installs:

- the executable in `~/.local/bin`;
- the `.desktop` file;
- icons in different sizes.

Make sure `~/.local/bin` is included in your `PATH`.

The following script is also included:

```text
install-linux-user.sh
```

This script installs the launcher and icons for the current user when the executable is already accessible from the `PATH`.

Usage:

```bash
chmod +x install-linux-user.sh
./install-linux-user.sh
```

---


## Project structure

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
├── org.icom.Icom7300Mk2Control.desktop
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

### Main files

**`radiocontroller.cpp/.h`**  
Serial communication, CI-V protocol, synchronization, radio control, memories, scope and meters.

**`Main.qml`**  
Main interface.

**`morsetrainer.cpp/.h`**  
Morse generation and analysis, audio, Koch/Farnsworth, scoring and statistics.

**`MorseTrainerWindow.qml`**  
Morse trainer interface.

---


## Basic usage

1. Connect the IC-7300MK2 via USB.
2. Turn on the radio.
3. Run the application.
4. Check the connection indicator.
5. If it does not connect automatically, open the CI-V settings and select:
   - port;
   - 115200 baud;
   - address `0x94`.
6. Change the frequency from the application or from the radio's tuning dial and verify that both remain synchronized.

---


## Troubleshooting

### The radio does not connect

Check:

```bash
ls -l /dev/ttyACM*
ls -l /dev/serial/by-id/
```

Also check:

- that the USB cable is connected;
- that no other process has the same port open;
- that the user belongs to `dialout`;
- that CI-V is configured at the correct baud rate;
- that the radio address is `0x94` when using the recommended values.

To find a process that has a port open:

```bash
lsof /dev/ttyACM0
lsof /dev/ttyACM1
```

### A second instance does not connect

Current versions explicitly close the CI-V port on exit.

If the problem continues, check whether a previous process is still running:

```bash
pgrep -a Icom7300Mk2Control
```

### Morse sidetone is not detected

Check:

- selected USB audio input device;
- USB audio output configured on the radio;
- audio level;
- CW Pitch;
- detection threshold;
- that the trainer's input level meter is moving.

On Linux, you can also inspect audio devices through PipeWire/PulseAudio.

### The first symbols of a Morse exercise are clipped

Playback includes an initial silence period to allow PipeWire/PulseAudio/ALSA to stabilize the output before the first symbol.

If the problem persists, check that the audio device is not being aggressively suspended by the system.

---


## Simultaneous use with other applications

The project is designed to coexist with digital-mode applications when the port and USB interface configuration allows it.

Do not try to make two processes open the **same serial device** exclusively at the same time. If another application needs CI-V control, use the appropriate interface and port configuration to avoid conflicts.

---


## Safety

This software can modify parameters of a real transceiver and activate transmission-related functions.

Before using it:

- check the power level;
- check the load or antenna;
- check the frequency;
- comply with applicable regulations;
- do not rely solely on the graphical interface to prevent accidental transmission.

The developer and contributors cannot guarantee the behavior of equipment, drivers, firmware or installations external to the application.

---


## Roadmap

Possible development directions:

- Progressive expansion of web remote control (scope/waterfall and remote audio).
- Remote audio.
- Full Windows adaptation.
- Optional separation of the Morse trainer as an independent application.
- Additional scope/waterfall improvements.
- New CI-V functions available on the IC-7300MK2.
- More statistics and Morse learning tools.

---


## Contributions

Contributions, testing and bug reports are welcome.

When reporting an issue, it is useful to include:

- application version;
- Linux distribution;
- Qt version;
- radio firmware version;
- port used;
- CI-V baud rate;
- steps to reproduce the problem;
- relevant CI-V diagnostic output.

Avoid publishing serial numbers, keys, passwords or other private identifiers in reports.

---


## Memories in remote control

Since version **1.2.10**, the web interface includes a manager for the IC-7300MK2's 99 memories without increasing the size of the main panel.

Available functions:

- individual memory reading;
- sequential reading of all 99 memories;
- summary of read, occupied and free channels;
- filters: all, occupied, free and unread;
- search by channel, name, frequency, mode or status;
- memory selection (`IR`);
- copy a memory to the VFO;
- return to the previous VFO;
- rename;
- save the current state to a memory;
- erase memory.

Write or erase operations require confirmation in the browser.

## Releases

For published versions, **GitHub Releases** are recommended instead of storing a ZIP file for each version inside the repository.

Example:

```text
v1.2.13
└── Icom7300Mk2Control_v1.2.13.zip
```

The main repository should contain the source code for the current version.

---


## License

Before publishing the repository, add a `LICENSE` file containing the chosen license.

If you want a permissive open-source license, **MIT** is a common option.

---


## Trademark notice

**Icom** and **IC-7300MK2** are trademarks or names belonging to their respective owners.

This project is independent and is not affiliated with, sponsored by or officially endorsed by Icom Inc.

> **v1.2.10:** fixed the authentication screen: periodic updates no longer erase the key while it is being typed, and `Enter` can be used to validate it.
