import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQml.Models 2.15

ApplicationWindow {
    id: window

    width: 1120
    height: 880
    minimumWidth: 1050
    minimumHeight: 880
    maximumHeight: 880

    visible: true
    title: "Control IC-7300MK2 · Versión 1.2.12"
    color: "#454545"

    property bool diagnosticsVisible: false
    property bool remoteServerVisible: false
    property bool settingsVisible: false
    property bool compactVisible: false
    property bool superCompactVisible: false
    property bool txSettingsVisible: false
    property bool cwSettingsVisible: false
    property bool toneRttySettingsVisible: false
    property bool scopeVisible: false
    property bool morseTrainerVisible: false
    property bool morseWorkspaceActive: false
    property bool applicationClosing: false
    property bool startupComplete: false
    property int mainVisibilityBeforeMorse: Window.Windowed
    property bool scannerVisible: false
    property bool memoryQuickPanelVisible: false
    property string lanLogText: ""
    property int memoryQuickSelectedChannel: 1
    property int pendingMemoryStoreChannel: 1
    property int pendingMemoryClearChannel: 1
    property int memoryQuickLoadedCount: 0
    property int memoryQuickOccupiedCount: 0
    readonly property int memoryQuickPanelWidth: 382
    readonly property int memoryQuickPanelSpacing: 6
    property real memoryQuickWindowX: 0
    property real memoryQuickWindowY: 0
    property int nextAuxiliaryWindowZ: 100
    property int stepIndex: 3
    property real tuningAngle: 0

    Component.onCompleted: {
        if (applicationLauncher.compactModePreferred) {
            Qt.callLater(function() {
                setCompactMode(true)
                startupComplete = true
            })
        } else {
            const savedMainX = applicationLauncher.mainWindowX
            const savedMainY = applicationLauncher.mainWindowY
            if (savedMainX !== -1)
                window.x = Math.max(
                    Screen.virtualX,
                    Math.min(savedMainX,
                             Screen.virtualX
                             + Screen.desktopAvailableWidth
                             - window.width))
            if (savedMainY !== -1)
                window.y = Math.max(
                    Screen.virtualY,
                    Math.min(savedMainY,
                             Screen.virtualY
                             + Screen.desktopAvailableHeight
                             - window.height))
            startupComplete = true
        }
    }

    onXChanged: {
        if (memoryQuickPanelVisible)
            Qt.callLater(positionMemoryQuickWindow)
        if (startupComplete && visible && !compactVisible)
            applicationLauncher.mainWindowX = Math.round(x)
    }

    onYChanged: {
        if (memoryQuickPanelVisible)
            Qt.callLater(positionMemoryQuickWindow)
        if (startupComplete && visible && !compactVisible)
            applicationLauncher.mainWindowY = Math.round(y)
    }

    onWidthChanged: {
        if (memoryQuickPanelVisible)
            Qt.callLater(positionMemoryQuickWindow)
    }

    onHeightChanged: {
        if (memoryQuickPanelVisible)
            Qt.callLater(positionMemoryQuickWindow)
    }

    onClosing: {
        applicationClosing = true
        // Notify the IC-7300 before Qt tears down the event loop.
        applicationLauncher.shutdownLanConnection()
        if (compactWindow.visible)
            compactWindow.close()
        if (superCompactWindow.visible)
            superCompactWindow.close()
        // Es una Window nativa independiente: cambiar solo la bandera de
        // estado no procesa su evento de cierre. Ciérrala expresamente antes
        // de abandonar el bucle de eventos para que no quede huérfana.
        if (remoteServerWindow.visible)
            remoteServerWindow.close()
        remoteServerVisible = false
        memoryQuickPanelVisible = false
        scannerVisible = false
        scopeVisible = false
        morseTrainerVisible = false
        morseTrainerWindow.visible = false
        morseTrainer.stopReceptionPlayback()
        morseTrainer.stopCapture()
        remoteServer.stop()
        settingsVisible = false
        radioController.stopSpectrumScope()
        radioController.shutdown()
        // Fuerza la terminación aunque alguna Window auxiliar siga creada
        // pero oculta. El puerto CI-V ya está cerrado en este punto.
        Qt.quit()
    }

    property var modeNames: [
        "LSB", "AM", "CW", "RTTY", "SSTV",
        "USB", "FM", "CW-R", "RTTY-R", "FT8/FT4"
    ]
    property string externalDigitalMode: ""
    property var externalRadioState: null

    function saveExternalRadioState() {
        if (externalRadioState !== null)
            return

        const parsedFilter = Number(String(radioController.filterText)
                                    .replace(/[^0-9]/g, ""))
        externalRadioState = {
            frequency: radioController.frequencyHz,
            mode: radioController.modeText,
            data: radioController.dataMode,
            filter: parsedFilter >= 1 && parsedFilter <= 3
                    ? parsedFilter : 1,
            vfo: radioController.selectedVfo
        }
    }

    function restoreExternalRadioState() {
        if (externalRadioState === null)
            return

        const state = externalRadioState
        externalRadioState = null
        externalDigitalMode = ""
        radioController.setVfoFrequency(state.vfo,
                                        String(state.frequency))
        radioController.setOperatingModeState(state.mode,
                                              state.data,
                                              state.filter)
    }

    function saveCurrentDigitalFrequency() {
        const frequency = radioController.frequencyHz
        if (frequency < 100000 || frequency > 60000000)
            return

        if (externalDigitalMode === "RTTY"
                || externalDigitalMode === "RTTY-R")
            applicationLauncher.rttyFrequencyHz = frequency
        else if (externalDigitalMode === "CW"
                 || externalDigitalMode === "CW-R")
            applicationLauncher.cwFrequencyHz = frequency
        else if (externalDigitalMode === "FT8/FT4")
            applicationLauncher.ftFrequencyHz = frequency
        else if (externalDigitalMode === "SSTV")
            applicationLauncher.sstvFrequencyHz = frequency
        else if (externalDigitalMode === "PSK")
            applicationLauncher.pskFrequencyHz = frequency
        else if (externalDigitalMode === "OLIVIA")
            applicationLauncher.oliviaFrequencyHz = frequency
        else if (externalDigitalMode === "JS8")
            applicationLauncher.js8FrequencyHz = frequency
        else if (externalDigitalMode === "WEFAX")
            applicationLauncher.wefaxFrequencyHz = frequency
    }

    function stopExternalProgramsAndRestore() {
        saveCurrentDigitalFrequency()
        applicationLauncher.stopDecodium()
        applicationLauncher.stopFldigi()
        applicationLauncher.stopQsstv()
        applicationLauncher.stopJs8call()
        extraDigitalModeBox.currentIndex = 0
        compactExtraDigitalModeBox.currentIndex = 0
        restoreExternalRadioState()
    }

    function prepareExternalProgram(programName) {
        if (applicationLauncher.decodiumRunning
                || applicationLauncher.fldigiRunning
                || applicationLauncher.qsstvRunning
                || applicationLauncher.js8callRunning)
            saveCurrentDigitalFrequency()
        saveExternalRadioState()
        if (programName !== "decodium")
            applicationLauncher.stopDecodium()
        if (programName !== "fldigi")
            applicationLauncher.stopFldigi()
        if (programName !== "qsstv")
            applicationLauncher.stopQsstv()
        if (programName !== "js8call")
            applicationLauncher.stopJs8call()
    }

    function setCompactMode(enabled) {
        if (enabled && superCompactWindow.visible) {
            superCompactWindow.returningToCompact = true
            superCompactWindow.close()
            superCompactVisible = false
        }
        if (!enabled && superCompactWindow.visible) {
            superCompactWindow.returningToCompact = true
            superCompactWindow.close()
            superCompactVisible = false
        }
        compactVisible = enabled
        if (!applicationClosing)
            applicationLauncher.compactModePreferred = enabled
        if (enabled) {
            const savedX = applicationLauncher.compactWindowX
            const savedY = applicationLauncher.compactWindowY
            const savedWidth = Math.max(compactWindow.baseWidth,
                                        applicationLauncher.compactWindowWidth)
            compactWindow.adjustingSize = true
            compactWindow.width = savedWidth
            compactWindow.height = Math.round(savedWidth
                                              / compactWindow.baseAspect)
            compactWindow.adjustingSize = false
            compactWindow.visible = true
            const defaultX = window.x + (window.width - compactWindow.width) / 2
            const defaultY = window.y
            compactWindow.x = Math.max(
                Screen.virtualX,
                Math.min(savedX !== -1 ? savedX : defaultX,
                         Screen.virtualX + Screen.desktopAvailableWidth
                         - compactWindow.width))
            compactWindow.y = Math.max(
                Screen.virtualY,
                Math.min(savedY !== -1 ? savedY : defaultY,
                         Screen.virtualY + Screen.desktopAvailableHeight
                         - compactWindow.height))
            window.hide()
            Qt.callLater(function() {
                // El cierre de SUPER puede procesarse después de esta
                // función; volver a mostrar explícitamente la compacta
                // garantiza que nunca queden ambas ventanas ocultas.
                compactWindow.visible = true
                compactWindow.show()
                compactWindow.raise()
                compactWindow.requestActivate()
            })
        } else {
            if (compactWindow.visible) {
                compactWindow.returningToFullView = true
                compactWindow.close()
                // Window.close() puede completar de forma asíncrona en el
                // primer arranque compacto; fuerza además su visibilidad a
                // false antes de mostrar la principal.
                compactWindow.visible = false
            }
            if (!applicationClosing) {
                const savedMainX = applicationLauncher.mainWindowX
                const savedMainY = applicationLauncher.mainWindowY
                if (savedMainX !== -1)
                    window.x = Math.max(
                        Screen.virtualX,
                        Math.min(savedMainX,
                                 Screen.virtualX
                                 + Screen.desktopAvailableWidth
                                 - window.width))
                if (savedMainY !== -1)
                    window.y = Math.max(
                        Screen.virtualY,
                        Math.min(savedMainY,
                                 Screen.virtualY
                                 + Screen.desktopAvailableHeight
                                 - window.height))
                Qt.callLater(function() {
                    window.showNormal()
                    window.raise()
                    window.requestActivate()
                })
            }
        }
    }

    function setSuperCompactMode(enabled) {
        superCompactVisible = enabled
        if (enabled) {
            if (compactWindow.visible) {
                compactWindow.returningToFullView = true
                compactWindow.close()
            }
            compactVisible = false
            window.hide()
            // Sitúa SUPER en el área libre inmediatamente encima de la barra
            // de tareas; desde ahí se puede arrastrar a cualquier otro hueco.
            const savedSuperX = applicationLauncher.superWindowX
            const savedSuperY = applicationLauncher.superWindowY
            superCompactWindow.x = savedSuperX >= Screen.virtualX
                                  ? savedSuperX
                                  : Screen.virtualX + Screen.desktopAvailableWidth
                                    - superCompactWindow.width - 12
            superCompactWindow.y = savedSuperY >= Screen.virtualY
                                  ? savedSuperY
                                  : Screen.virtualY + Screen.desktopAvailableHeight
                                    - superCompactWindow.height - 6
            superCompactWindow.show()
            superCompactWindow.raise()
            superCompactWindow.requestActivate()
        } else if (!applicationClosing) {
            superCompactWindow.hide()
            window.showNormal()
            window.raise()
            window.requestActivate()
        }
    }

    function selectUsbDataMode() {
        if (applicationLauncher.lanConnected) {
            applicationLauncher.testLanModeName("USB")
            applicationLauncher.setLanDataEnabled(true, "USB")
        } else {
            radioController.setOperatingModeState("USB", true, 1)
        }
    }

    function activateCompactMode(modeName) {
        if (modeName === "SSTV") {
            if (applicationLauncher.qsstvRunning) {
                stopExternalProgramsAndRestore()
                return
            }
            prepareExternalProgram("qsstv")
            externalDigitalMode = "SSTV"
            radioController.setFrequency(String(applicationLauncher.sstvFrequencyHz))
            selectUsbDataMode()
            applicationLauncher.launchQsstv()
        } else if (modeName === "FT8/FT4") {
            if (applicationLauncher.decodiumRunning) {
                stopExternalProgramsAndRestore()
                return
            }
            prepareExternalProgram("decodium")
            externalDigitalMode = "FT8/FT4"
            radioController.setFrequency(String(applicationLauncher.ftFrequencyHz))
            selectUsbDataMode()
            applicationLauncher.launchDecodium()
        } else if (modeName === "RTTY" || modeName === "RTTY-R") {
            if (applicationLauncher.fldigiRunning
                    && externalDigitalMode === modeName) {
                stopExternalProgramsAndRestore()
                return
            }
            prepareExternalProgram("fldigi")
            externalDigitalMode = modeName
            radioController.setFrequency(String(applicationLauncher.rttyFrequencyHz))
            selectUsbDataMode()
            applicationLauncher.launchFldigi()
            applicationLauncher.setFldigiMode("RTTY")
            applicationLauncher.setFldigiReverse(modeName === "RTTY-R")
        } else {
            if ((modeName === "CW" || modeName === "CW-R")
                    && applicationLauncher.fldigiRunning
                    && radioController.modeText === modeName) {
                stopExternalProgramsAndRestore()
                return
            }
            if (applicationLauncher.decodiumRunning
                    || applicationLauncher.qsstvRunning
                    || applicationLauncher.js8callRunning
                    || (applicationLauncher.fldigiRunning
                        && modeName !== "CW" && modeName !== "CW-R"))
                stopExternalProgramsAndRestore()
            externalDigitalMode = ""
            if (modeName === "CW" || modeName === "CW-R") {
                radioController.setFrequency(String(applicationLauncher.cwFrequencyHz))
                if (applicationLauncher.fldigiRunning)
                    externalDigitalMode = modeName
            }
            if (applicationLauncher.lanConnected
                    && ["LSB","USB","AM","CW","RTTY","FM","CW-R","RTTY-R"].indexOf(modeName) >= 0)
                applicationLauncher.testLanModeName(modeName)
            else
                radioController.setOperatingMode(modeName)
        }
    }

    Timer {
        id: decodiumModeGuard
        interval: 1200
        repeat: false
        onTriggered: {
            if (applicationLauncher.decodiumRunning
                    && !(radioController.modeText === "USB"
                         && radioController.dataMode)) {
                applicationLauncher.stopDecodium()
                restoreExternalRadioState()
            }
            if (applicationLauncher.qsstvRunning
                    && !(radioController.modeText === "USB"
                         && radioController.dataMode)) {
                applicationLauncher.stopQsstv()
                restoreExternalRadioState()
            }
            if (applicationLauncher.fldigiRunning
                    && !((radioController.modeText === "USB"
                          && radioController.dataMode)
                         || radioController.modeText === "CW"
                         || radioController.modeText === "CW-R")) {
                externalDigitalMode = ""
                applicationLauncher.stopFldigi()
                restoreExternalRadioState()
            }
            if (applicationLauncher.js8callRunning
                    && !(radioController.modeText === "USB"
                         && radioController.dataMode)) {
                applicationLauncher.stopJs8call()
                restoreExternalRadioState()
            }
        }
    }

    Connections {
        target: radioController

        function onModeChanged() {
            decodiumModeGuard.restart()
            if (radioController.modeText === "RTTY"
                    || radioController.modeText === "RTTY-R") {
                externalDigitalMode = radioController.modeText
                radioController.setOperatingModeState(
                    "USB", true, 1
                )
                applicationLauncher.launchFldigi()
                applicationLauncher.setFldigiMode("RTTY")
                applicationLauncher.setFldigiReverse(
                    radioController.modeText === "RTTY-R")
            } else if (radioController.modeText === "CW"
                       || radioController.modeText === "CW-R") {
                externalDigitalMode = applicationLauncher.fldigiRunning
                                      ? radioController.modeText : ""
            }
        }

        function onDataModeChanged() {
            decodiumModeGuard.restart()
        }
    }

    Connections {
        target: applicationLauncher

        function onFldigiRunningChanged() {
            if (!applicationLauncher.fldigiRunning)
                externalDigitalMode = ""
        }

        function onStatusChanged() {
            const line = applicationLauncher.status
            if (!line) return
            lanLogText = (lanLogText ? lanLogText + "\n" : "") + line
            if (lanLogText.length > 4000)
                lanLogText = lanLogText.slice(-4000)
        }
    }

    property var stepNames: [
        "1 Hz", "10 Hz", "100 Hz",
        "1 kHz", "5 kHz", "10 kHz", "100 kHz"
    ]

    property var stepValues: [
        1, 10, 100, 1000, 5000, 10000, 100000
    ]

    property var ctcssToneValues: [
        670, 693, 719, 744, 770, 797, 825, 854, 885, 915,
        948, 974, 1000, 1035, 1072, 1109, 1148, 1188, 1230,
        1273, 1318, 1365, 1413, 1462, 1514, 1567, 1598, 1622,
        1655, 1679, 1713, 1738, 1773, 1799, 1835, 1862, 1899,
        1928, 1966, 1995, 2035, 2065, 2107, 2181, 2257, 2291,
        2336, 2418, 2503, 2541
    ]

    property var bandDefinitions: [
        { name: "1.8", minimum: 1800000, maximum: 2000000,
          defaultHz: 1850000, label: "160 m" },
        { name: "3.5", minimum: 3500000, maximum: 4000000,
          defaultHz: 3700000, label: "80 m" },
        { name: "5", minimum: 5250000, maximum: 5450000,
          defaultHz: 5357000, label: "60 m" },
        { name: "7", minimum: 7000000, maximum: 7300000,
          defaultHz: 7100000, label: "40 m" },
        { name: "10", minimum: 10100000, maximum: 10150000,
          defaultHz: 10120000, label: "30 m" },
        { name: "14", minimum: 14000000, maximum: 14350000,
          defaultHz: 14200000, label: "20 m" },
        { name: "18", minimum: 18068000, maximum: 18168000,
          defaultHz: 18130000, label: "17 m" },
        { name: "21", minimum: 21000000, maximum: 21450000,
          defaultHz: 21200000, label: "15 m" },
        { name: "24", minimum: 24890000, maximum: 24990000,
          defaultHz: 24950000, label: "12 m" },
        { name: "28", minimum: 28000000, maximum: 29700000,
          defaultHz: 28500000, label: "10 m" },
        { name: "50", minimum: 50000000, maximum: 54000000,
          defaultHz: 50150000, label: "6 m" },
        { name: "70", minimum: 69900000, maximum: 70500000,
          defaultHz: 70200000, label: "4 m" }
    ]

    property var bandMemories: ({})
    property string currentBandName:
        bandNameForFrequency(activeVfoFrequencyHz())

    ListModel {
        id: memoryQuickModel
    }

    function rebuildMemoryQuickModel() {
        memoryQuickModel.clear()

        let loaded = 0
        let occupied = 0

        for (let channel = 1;
             channel <= 99;
             ++channel) {
            const row =
                radioController.memoryRow(channel)
            const valid =
                row
                && row.channel !== undefined
            const rowLoaded =
                valid
                ? Boolean(row.loaded)
                : false
            const rowBlank =
                valid
                ? Boolean(row.blank)
                : true

            if (rowLoaded)
                loaded += 1

            if (rowLoaded && !rowBlank)
                occupied += 1

            memoryQuickModel.append({
                "channel": channel,
                "loaded": rowLoaded,
                "blank": rowBlank,
                "memoryName":
                    rowLoaded && !rowBlank
                    && row.name !== undefined
                    && String(row.name).length > 0
                    ? String(row.name)
                    : rowLoaded && rowBlank
                      ? "Canal vacío"
                      : "Sin leer",
                "frequencyText":
                    rowLoaded && !rowBlank
                    && row.frequencyText !== undefined
                    ? String(row.frequencyText)
                    : "—",
                "modeText":
                    rowLoaded && !rowBlank
                    && row.modeText !== undefined
                    ? String(row.modeText)
                    : "—",
                "filterText":
                    rowLoaded && !rowBlank
                    && row.filterText !== undefined
                    ? String(row.filterText)
                    : "—",
                "dataMode":
                    rowLoaded && !rowBlank
                    && row.dataMode !== undefined
                    ? Boolean(row.dataMode)
                    : false,
                "duplexText":
                    rowLoaded && !rowBlank
                    && row.duplexText !== undefined
                    ? String(row.duplexText)
                    : "—",
                "toneText":
                    rowLoaded && !rowBlank
                    && row.toneTypeText !== undefined
                    ? String(row.toneTypeText)
                    : "OFF",
                "selectText":
                    rowLoaded && !rowBlank
                    && row.selectText !== undefined
                    ? String(row.selectText)
                    : "—"
            })
        }

        memoryQuickLoadedCount = loaded
        memoryQuickOccupiedCount = occupied

        memoryQuickSelectedChannel =
            Math.max(
                1,
                Math.min(
                    99,
                    memoryQuickSelectedChannel
                )
            )
    }

    function positionMemoryQuickWindow() {
        const screenLeft =
            Screen.virtualX
        const screenRight =
            Screen.virtualX
            + Screen.desktopAvailableWidth
        const rightPosition =
            window.x
            + window.width
            + memoryQuickPanelSpacing
        const leftPosition =
            window.x
            - memoryQuickPanelWidth
            - memoryQuickPanelSpacing

        if (rightPosition + memoryQuickPanelWidth
                <= screenRight) {
            memoryQuickWindowX =
                rightPosition
        } else if (leftPosition >= screenLeft) {
            memoryQuickWindowX =
                leftPosition
        } else {
            memoryQuickWindowX =
                Math.max(
                    screenLeft,
                    screenRight
                    - memoryQuickPanelWidth
                )
        }

        memoryQuickWindowY =
            window.y
        memoryQuickWindow.x =
            memoryQuickWindowX
        memoryQuickWindow.y =
            memoryQuickWindowY
        memoryQuickWindow.width =
            memoryQuickPanelWidth
        memoryQuickWindow.height =
            window.height
    }

    function setMemoryQuickPanelVisible(showPanel) {
        if (showPanel === memoryQuickPanelVisible)
            return

        if (showPanel) {
            rebuildMemoryQuickModel()
            positionMemoryQuickWindow()
            memoryQuickPanelVisible = true

            Qt.callLater(function() {
                positionMemoryQuickWindow()
                memoryQuickWindow.raise()
                memoryQuickWindow.requestActivate()
            })

            if (radioController.connected
                    && !radioController.busy
                    && memoryQuickLoadedCount < 99) {
                radioController.readMemoryRange(1, 99)
            }

            return
        }

        memoryQuickPanelVisible = false
    }

    function toggleMemoryQuickPanel() {
        setMemoryQuickPanelVisible(
            !memoryQuickPanelVisible
        )
    }

    function activeVfoFrequencyHz() {
        return radioController.selectedVfo === 0
               ? Number(radioController.vfoAFrequencyHz)
               : Number(radioController.vfoBFrequencyHz)
    }

    function otherVfoNumber() {
        return radioController.selectedVfo === 0 ? 1 : 0
    }

    function otherVfoFrequencyText() {
        return radioController.selectedVfo === 0
               ? radioController.vfoBFrequencyText
               : radioController.vfoAFrequencyText
    }

    function otherVfoModeText() {
        return radioController.selectedVfo === 0
               ? radioController.vfoBModeText
               : radioController.vfoAModeText
    }

    function otherVfoFilterText() {
        return radioController.selectedVfo === 0
               ? radioController.vfoBFilterText
               : radioController.vfoAFilterText
    }

    function otherVfoDataText() {
        return radioController.selectedVfo === 0
               ? radioController.vfoBDataText
               : radioController.vfoADataText
    }

    function bandNameForFrequency(frequencyHz) {
        const frequency = Number(frequencyHz)

        for (let index = 0;
             index < bandDefinitions.length;
             ++index) {
            const band = bandDefinitions[index]

            if (frequency >= band.minimum
                    && frequency <= band.maximum) {
                return band.name
            }
        }

        return ""
    }

    function rememberBandFrequency(vfoNumber, frequencyHz) {
        const frequency = Number(frequencyHz)
        const bandName = bandNameForFrequency(frequency)

        if (bandName.length === 0 || frequency <= 0)
            return

        const key = String(vfoNumber) + ":" + bandName
        const updated = ({})

        for (const storedKey in bandMemories)
            updated[storedKey] = bandMemories[storedKey]

        updated[key] = frequency
        bandMemories = updated
    }

    function selectBand(bandIndex) {
        if (!controlsEnabled())
            return

        const band = bandDefinitions[bandIndex]
        const vfoNumber = radioController.selectedVfo
        const key = String(vfoNumber) + ":" + band.name

        const targetFrequency =
            bandMemories[key] !== undefined
            ? Number(bandMemories[key])
            : Number(band.defaultHz)

        radioController.setVfoFrequency(
            vfoNumber,
            String(targetFrequency)
        )
    }

    function formatBandFrequency(frequencyHz) {
        return (Number(frequencyHz) / 1000000)
               .toLocaleString(Qt.locale(), "f", 3)
               + " MHz"
    }

    function bandButtonHelp(index) {
        const band = bandDefinitions[index]
        const key =
            String(radioController.selectedVfo)
            + ":"
            + band.name
        const remembered =
            bandMemories[key] !== undefined

        return "Banda directa "
               + band.label
               + ". "
               + (remembered
                  ? "Recupera la última frecuencia usada en esta banda."
                  : "La primera vez usa "
                    + formatBandFrequency(band.defaultHz)
                    + ".")
    }

    function controlsEnabled() {
        return (radioController.connected || applicationLauncher.lanConnected)
               && !radioController.transmitting
               // El estado busy pertenece a la cola CI-V por USB. No debe
               // bloquear los controles cuando la sesión activa es LAN.
               && (applicationLauncher.lanConnected || !radioController.busy)
    }

    function raiseAuxiliaryWindow(popup) {
        if (popup === null || popup === undefined)
            return

        nextAuxiliaryWindowZ += 1
        popup.z = nextAuxiliaryWindowZ
    }

    function clampAuxiliaryWindow(popup) {
        if (popup === null || popup === undefined)
            return

        const maximumX =
            Math.max(0, Overlay.overlay.width - popup.width)
        const maximumY =
            Math.max(0, Overlay.overlay.height - popup.height)

        popup.x = Math.max(
            0,
            Math.min(maximumX, popup.x)
        )
        popup.y = Math.max(
            0,
            Math.min(maximumY, popup.y)
        )
    }

    function closeAuxiliaryWindowsForMorse() {
        // El entrenador ocupa el espacio de trabajo completo. Las ventanas
        // auxiliares se cierran para no dejar controles ocultos ni procesos
        // innecesarios activos detrás de él.
        if (diagnosticsPopup.visible)
            diagnosticsPopup.close()
        if (txSettingsPopup.visible)
            txSettingsPopup.close()
        if (cwSettingsPopup.visible)
            cwSettingsPopup.close()
        if (toneRttySettingsPopup.visible)
            toneRttySettingsPopup.close()

        diagnosticsVisible = false
        remoteServerVisible = false
        remoteServerWindow.visible = false
        txSettingsVisible = false
        cwSettingsVisible = false
        toneRttySettingsVisible = false
        settingsVisible = false
        scopeVisible = false
        scannerVisible = false
        setMemoryQuickPanelVisible(false)
        radioController.stopSpectrumScope()
    }

    function enterMorseWorkspace() {
        if (morseWorkspaceActive || applicationClosing)
            return

        morseWorkspaceActive = true
        mainVisibilityBeforeMorse = window.visibility
        closeAuxiliaryWindowsForMorse()

        // MorseTrainerWindow es independiente de la ventana principal para
        // que esta pueda minimizarse sin arrastrar al entrenador consigo.
        Qt.callLater(function() {
            if (!morseTrainerWindow.visible || applicationClosing)
                return

            window.showMinimized()
            morseTrainerWindow.raise()
            morseTrainerWindow.requestActivate()
        })
    }

    function leaveMorseWorkspace() {
        if (!morseWorkspaceActive)
            return

        morseWorkspaceActive = false
        if (applicationClosing)
            return

        if (mainVisibilityBeforeMorse === Window.Maximized)
            window.showMaximized()
        else if (mainVisibilityBeforeMorse === Window.FullScreen)
            window.showFullScreen()
        else
            window.showNormal()

        Qt.callLater(function() {
            if (applicationClosing)
                return
            window.raise()
            window.requestActivate()
        })
    }

    function toggleAuxiliaryWindow(windowName) {
        let popup = null

        if (windowName === "remoteServer") {
            remoteServerVisible = !remoteServerVisible
            remoteServerWindow.visible = remoteServerVisible

            if (remoteServerVisible) {
                remoteServer.refreshNetworkInfo()
                remoteServerWindow.x =
                    Math.max(
                        Screen.virtualX,
                        Math.min(
                            window.x
                            + (window.width - remoteServerWindow.width) / 2,
                            Screen.virtualX
                            + Screen.desktopAvailableWidth
                            - remoteServerWindow.width
                        )
                    )
                remoteServerWindow.y =
                    Math.max(
                        Screen.virtualY,
                        Math.min(
                            window.y + 44,
                            Screen.virtualY
                            + Screen.desktopAvailableHeight
                            - remoteServerWindow.height
                        )
                    )
                Qt.callLater(function() {
                    remoteServerWindow.raise()
                    remoteServerWindow.requestActivate()
                })
            }
            return
        }
        else if (windowName === "diagnostics")
            popup = diagnosticsPopup
        else if (windowName === "civ") {
            settingsVisible =
                !settingsVisible

            if (settingsVisible) {
                settingsPopup.x =
                    Math.max(
                        Screen.virtualX,
                        Math.min(
                            window.x
                            + (window.width
                               - settingsPopup.width) / 2,
                            Screen.virtualX
                            + Screen.desktopAvailableWidth
                            - settingsPopup.width
                        )
                    )
                settingsPopup.y =
                    Math.max(
                        Screen.virtualY,
                        Math.min(
                            window.y + 44,
                            Screen.virtualY
                            + Screen.desktopAvailableHeight
                            - settingsPopup.height
                        )
                    )

                Qt.callLater(function() {
                    settingsPopup.raise()
                    settingsPopup.requestActivate()
                })
            }
            return
        }
        else if (windowName === "tx")
            popup = txSettingsPopup
        else if (windowName === "cw")
            popup = cwSettingsPopup
        else if (windowName === "toneRtty")
            popup = toneRttySettingsPopup
        else if (windowName === "morse") {
            morseTrainerVisible =
                !morseTrainerVisible
            morseTrainerWindow.visible =
                morseTrainerVisible

            if (morseTrainerVisible) {
                morseTrainerWindow.x =
                    Math.max(
                        Screen.virtualX,
                        Math.min(
                            window.x
                            + (window.width
                               - morseTrainerWindow.width) / 2,
                            Screen.virtualX
                            + Screen.desktopAvailableWidth
                            - morseTrainerWindow.width
                        )
                    )
                morseTrainerWindow.y =
                    Math.max(
                        Screen.virtualY,
                        Math.min(
                            window.y + 42,
                            Screen.virtualY
                            + Screen.desktopAvailableHeight
                            - morseTrainerWindow.height
                        )
                    )

                Qt.callLater(function() {
                    morseTrainerWindow.raise()
                    morseTrainerWindow.requestActivate()
                })
            }
            return
        }
        else if (windowName === "scope") {
            scopeVisible =
                !scopeVisible

            if (scopeVisible) {
                scopeWindow.x =
                    Math.max(
                        Screen.virtualX,
                        Math.min(
                            window.x
                            + (window.width
                               - scopeWindow.width) / 2,
                            Screen.virtualX
                            + Screen.desktopAvailableWidth
                            - scopeWindow.width
                        )
                    )
                scopeWindow.y =
                    Math.max(
                        Screen.virtualY,
                        Math.min(
                            window.y + 46,
                            Screen.virtualY
                            + Screen.desktopAvailableHeight
                            - scopeWindow.height
                        )
                    )

                Qt.callLater(function() {
                    scopeWindow.raise()
                    scopeWindow.requestActivate()
                })
            }
            return
        }
        else if (windowName === "scanner") {
            scannerVisible =
                !scannerVisible

            if (scannerVisible) {
                scannerWindow.x =
                    Math.max(
                        Screen.virtualX,
                        Math.min(
                            window.x
                            + (window.width
                               - scannerWindow.width) / 2,
                            Screen.virtualX
                            + Screen.desktopAvailableWidth
                            - scannerWindow.width
                        )
                    )
                scannerWindow.y =
                    Math.max(
                        Screen.virtualY,
                        Math.min(
                            window.y + 48,
                            Screen.virtualY
                            + Screen.desktopAvailableHeight
                            - scannerWindow.height
                        )
                    )

                Qt.callLater(function() {
                    scannerWindow.raise()
                    scannerWindow.requestActivate()
                })
            }
            return
        }

        if (popup === null)
            return

        const wasOpen =
            popup.opened
            || popup.visible

        if (wasOpen) {
            popup.close()
            return
        }

        raiseAuxiliaryWindow(popup)
        popup.open()

        Qt.callLater(
            function() {
                window.clampAuxiliaryWindow(popup)
            }
        )
    }

    function selectedStep() {
        return stepValues[stepIndex]
    }

    function tuneSelectedVfo(stepCount) {
        if (!controlsEnabled() || stepCount === 0)
            return

        radioController.adjustVfoFrequency(
            radioController.selectedVfo,
            stepCount * selectedStep()
        )

        tuningAngle += stepCount * 8
    }

    function controlHelp(label) {
        const key = String(label).trim().toUpperCase()

        if (key === "CONNECT")
            return "Conecta o desconecta el puerto CI-V."
        if (key === "INTERNET")
            return "Configura el servidor web remoto para control desde navegador por LAN o VPN privada."
        if (key === "REMOTE")
            return "Abre o cierra el diagnóstico CI-V."
        if (key === "ADV SET"
                || key === "CI-V SET")
            return "Abre la configuración avanzada de conexión, conectores y capacidades."
        if (key === "TX SET")
            return "Abre la configuración de transmisión, micrófono, compresor, monitor y VOX."
        if (key === "CW SET")
            return "Abre pitch, velocidad, APF, break-in, mensajes y memorias del keyer."
        if (key === "MORSE")
            return "Abre el entrenador Morse para practicar manipulación, recepción y copia con Koch/Farnsworth."
        if (key === "TONE/RTTY")
            return "Abre subtonos de repetidor, tone squelch y ajustes internos de RTTY."
        if (key === "SCOPE")
            return "Abre el Spectrum Scope y Waterfall con datos CI-V reales."
        if (key === "SCANNER")
            return "Abre una ventana independiente con todos los controles de escaneo."
        if (key === "MEMORY")
            return "Abre la única ventana de memorias: lista, guardado y edición."
        if (key === "VFO A")
            return "Selecciona el VFO A."
        if (key === "VFO B")
            return "Selecciona el VFO B."
        if (key === "EXIT")
            return "Cierra la aplicación."
        if (key === "TUNER")
            return "Activa o desactiva el acoplador interno."
        if (key === "TUNE")
            return "Inicia un ciclo de sintonización del acoplador."
        if (key === "P.AMP")
            return "Cambia el preamplificador: OFF, P.AMP1 y P.AMP2."
        if (key === "ATT")
            return "Activa o desactiva el atenuador."
        if (key === "AGC")
            return "Cambia la velocidad AGC entre FAST, MID y SLOW."
        if (key === "NB")
            return "Noise Blanker: elimina ruido impulsivo."
        if (key === "NR")
            return "Noise Reduction: reduce ruido continuo."
        if (key === "AN")
            return "Auto Notch: elimina automáticamente una portadora."
        if (key === "MN")
            return "Manual Notch: activa el notch manual."
        if (key === "IP+")
            return "Mejora el comportamiento ante señales fuertes cercanas."
        if (key === "FIL1"
                || key === "FIL2"
                || key === "FIL3")
            return "Selecciona "
                   + key
                   + " para el VFO activo."
        if (key === "DATA")
            return "Activa o desactiva DATA."
        if (key === "SPLIT")
            return "Activa o desactiva SPLIT."
        if (key === "XFC")
            return "Permite escuchar temporalmente la frecuencia de transmisión."
        if (key === "A/B")
            return "Intercambia VFO A y VFO B."
        if (key === "A=B")
            return "Copia VFO A en VFO B."
        if (key === "RIT")
            return "Activa o desactiva RIT."
        if (key === "ΔTX")
            return "Activa o desactiva ΔTX."
        if (key === "CLEAR")
            return "Pone a cero el desplazamiento RIT/ΔTX."
        if (key === "PBT-CLR")
            return "Centra PBT1 y PBT2."
        if (key === "NOTCH-CLR")
            return "Centra el notch manual."
        if (key === "W"
                || key === "M"
                || key === "N")
            return "Selecciona el ancho del notch manual."
        if (key === "SHARP"
                || key === "SOFT")
            return "Alterna la forma del filtro."
        if (key === "SET")
            return "Aplica la frecuencia introducida."
        if (key === "−"
                || key === "-"
                || key === "+")
            return "Aumenta o reduce la frecuencia con el paso seleccionado."
        if (key === "LSB"
                || key === "USB"
                || key === "CW"
                || key === "CW-R"
                || key === "RTTY"
                || key === "RTTY-R"
                || key === "AM"
                || key === "FM")
            return "Selecciona el modo "
                   + key
                   + "."
        if (key === "1"
                || key === "10"
                || key === "100"
                || key === "1K"
                || key === "5K"
                || key === "10K"
                || key === "100K")
            return "Selecciona este paso de sintonía."

        return "Control del IC-7300MK2."
    }

    function meterHelp(label) {
        const key = String(label).trim().toUpperCase()

        if (key === "S")
            return "S-meter: intensidad de la señal recibida."
        if (key === "PO")
            return "Potencia relativa durante transmisión."
        if (key === "ALC")
            return "Control automático del nivel de transmisión."
        if (key === "COMP")
            return "Nivel de compresión."
        if (key === "SWR")
            return "Relación de ondas estacionarias."
        if (key === "VD")
            return "Tensión de alimentación."
        if (key === "ID")
            return "Corriente consumida."
        if (key === "OVF")
            return "Aviso de saturación de entrada."

        return ""
    }

    component FrameBox: Rectangle {
        property bool raised: false

        radius: 3
        color: raised ? "#353535" : "#2d2d2d"
        border.color: raised ? "#7c7c7c" : "#5f5f5f"
        border.width: 1

        Rectangle {
            visible: parent.raised
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 1
            color: "#9a9a9a"
            opacity: 0.55
        }
    }


    component PopupDragTitle: Item {
        id: popupDragTitle

        property var popupTarget
        property string title: ""
        property color textColor: "#ffffff"
        property int pixelSize: 13

        implicitWidth: titleRow.implicitWidth
        implicitHeight: 30

        Row {
            id: titleRow

            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Text {
                text: "⋮⋮"
                color:
                    dragArea.containsMouse
                    ? popupDragTitle.textColor
                    : "#899197"
                font.pixelSize:
                    popupDragTitle.pixelSize + 2
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: popupDragTitle.title
                color: popupDragTitle.textColor
                font.pixelSize: popupDragTitle.pixelSize
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            id: dragArea

            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeAllCursor

            property real startPopupX: 0
            property real startPopupY: 0
            property real startPointerX: 0
            property real startPointerY: 0

            onPressed:
                function(mouse) {
                    if (!popupDragTitle.popupTarget)
                        return

                    window.raiseAuxiliaryWindow(
                        popupDragTitle.popupTarget
                    )

                    const point =
                        dragArea.mapToItem(
                            Overlay.overlay,
                            mouse.x,
                            mouse.y
                        )

                    startPopupX =
                        popupDragTitle.popupTarget.x
                    startPopupY =
                        popupDragTitle.popupTarget.y
                    startPointerX = point.x
                    startPointerY = point.y
                }

            onPositionChanged:
                function(mouse) {
                    if (!pressed
                            || !popupDragTitle.popupTarget)
                        return

                    const point =
                        dragArea.mapToItem(
                            Overlay.overlay,
                            mouse.x,
                            mouse.y
                        )

                    const target =
                        popupDragTitle.popupTarget
                    const maximumX =
                        Math.max(
                            0,
                            Overlay.overlay.width
                            - target.width
                        )
                    const maximumY =
                        Math.max(
                            0,
                            Overlay.overlay.height
                            - target.height
                        )

                    target.x =
                        Math.max(
                            0,
                            Math.min(
                                maximumX,
                                startPopupX
                                + point.x
                                - startPointerX
                            )
                        )

                    target.y =
                        Math.max(
                            0,
                            Math.min(
                                maximumY,
                                startPopupY
                                + point.y
                                - startPointerY
                            )
                        )
                }
        }

        ToolTip.visible:
            dragArea.containsMouse
            && !dragArea.pressed
        ToolTip.delay: 450
        ToolTip.timeout: 5000
        ToolTip.text:
            "Arrastre este título para mover la ventana."
    }

    component ToolbarButton: Button {
        id: toolbarButton

        property color iconColor: "#48bffd"
        property color groupAccentColor: "#5f8799"
        property string iconName: "generic"
        property string tip:
            controlHelp(text)

        implicitWidth: 56
        implicitHeight: 48

        onIconColorChanged:
            iconCanvas.requestPaint()
        onIconNameChanged:
            iconCanvas.requestPaint()
        onHoveredChanged:
            iconCanvas.requestPaint()
        onDownChanged:
            iconCanvas.requestPaint()

        background: Rectangle {
            radius: 4
            color:
                toolbarButton.down
                ? Qt.tint(
                      "#30383d",
                      Qt.rgba(
                          toolbarButton.groupAccentColor.r,
                          toolbarButton.groupAccentColor.g,
                          toolbarButton.groupAccentColor.b,
                          0.48
                      )
                  )
                : toolbarButton.hovered
                  ? Qt.tint(
                        "#30383d",
                        Qt.rgba(
                            toolbarButton.groupAccentColor.r,
                            toolbarButton.groupAccentColor.g,
                            toolbarButton.groupAccentColor.b,
                            0.38
                        )
                    )
                  : Qt.tint(
                        "#252e34",
                        Qt.rgba(
                            toolbarButton.groupAccentColor.r,
                            toolbarButton.groupAccentColor.g,
                            toolbarButton.groupAccentColor.b,
                            0.24
                        )
                    )
            border.color:
                toolbarButton.hovered
                ? Qt.lighter(
                      toolbarButton.groupAccentColor,
                      1.35
                  )
                : Qt.lighter(
                      toolbarButton.groupAccentColor,
                      1.10
                  )
            border.width: 1

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color:
                        toolbarButton.hovered
                        ? Qt.lighter(
                              toolbarButton.groupAccentColor,
                              1.05
                          )
                        : Qt.darker(
                              toolbarButton.groupAccentColor,
                              1.18
                          )
                }

                GradientStop {
                    position: 0.48
                    color: Qt.tint(
                               "#293136",
                               Qt.rgba(
                                   toolbarButton.groupAccentColor.r,
                                   toolbarButton.groupAccentColor.g,
                                   toolbarButton.groupAccentColor.b,
                                   0.25
                               )
                           )
                }

                GradientStop {
                    position: 1
                    color: Qt.tint(
                               "#20262a",
                               Qt.rgba(
                                   toolbarButton.groupAccentColor.r,
                                   toolbarButton.groupAccentColor.g,
                                   toolbarButton.groupAccentColor.b,
                                   0.18
                               )
                           )
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                height: 2
                radius: 1
                color: toolbarButton.iconColor
                opacity:
                    toolbarButton.hovered
                    || toolbarButton.down
                    ? 0.95
                    : 0.38
            }
        }

        ToolTip.visible:
            hovered
            && tip.length > 0
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text: tip

        contentItem: Column {
            anchors.centerIn: parent
            spacing: 1

            Item {
                width: 32
                height: 32
                anchors.horizontalCenter:
                    parent.horizontalCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: 29
                    height: 29
                    radius: 7
                    color: "#171b1e"
                    border.color:
                        Qt.darker(
                            toolbarButton.iconColor,
                            1.35
                        )
                    border.width: 1

                    Rectangle {
                        anchors.centerIn: parent
                        width: 23
                        height: 23
                        radius: 6
                        color:
                            toolbarButton.iconColor
                        opacity:
                            toolbarButton.hovered
                            ? 0.18
                            : 0.10
                    }
                }

                Canvas {
                    id: iconCanvas

                    anchors.fill: parent
                    antialiasing: true

                    Component.onCompleted:
                        requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        const w = width
                        const h = height
                        const cx = w / 2
                        const cy = h / 2
                        const color =
                            toolbarButton.iconColor

                        ctx.reset()
                        ctx.clearRect(0, 0, w, h)
                        ctx.strokeStyle = color
                        ctx.fillStyle = color
                        ctx.lineWidth =
                            toolbarButton.hovered
                            ? 2.35
                            : 2.0
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        function line(x1, y1, x2, y2) {
                            ctx.beginPath()
                            ctx.moveTo(x1, y1)
                            ctx.lineTo(x2, y2)
                            ctx.stroke()
                        }

                        if (toolbarButton.iconName === "connect") {
                            ctx.beginPath()
                            ctx.arc(11, 16, 5, -1.1, 1.1)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(21, 16, 5, 2.04, 4.24)
                            ctx.stroke()

                            line(13.5, 13.5, 18.5, 18.5)
                            line(13.5, 18.5, 18.5, 13.5)

                            ctx.beginPath()
                            ctx.arc(25.5, 7.5, 2.1, 0, Math.PI * 2)
                            ctx.fill()
                        } else if (toolbarButton.iconName === "browser") {
                            ctx.strokeRect(5.5, 7, 21, 18)
                            line(5.5, 11.5, 26.5, 11.5)

                            ctx.beginPath()
                            ctx.arc(8.5, 9.3, 0.9, 0, Math.PI * 2)
                            ctx.fill()
                            ctx.beginPath()
                            ctx.arc(11.5, 9.3, 0.9, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(16, 18.2, 5.1, 0, Math.PI * 2)
                            ctx.stroke()
                            line(10.9, 18.2, 21.1, 18.2)

                            ctx.beginPath()
                            ctx.ellipse(13.5, 13.1, 5, 10.2)
                            ctx.stroke()
                        } else if (toolbarButton.iconName === "remote") {
                            ctx.strokeRect(6.5, 7.5, 19, 14)
                            line(12, 25, 20, 25)
                            line(16, 21.5, 16, 25)

                            ctx.beginPath()
                            ctx.arc(16, 14.5, 2.0, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(16, 14.5, 5.2, -0.65, 0.65)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(16, 14.5, 8.0, -0.55, 0.55)
                            ctx.stroke()
                        } else if (toolbarButton.iconName === "settings") {
                            ctx.beginPath()
                            ctx.arc(cx, cy, 6.3, 0, Math.PI * 2)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(cx, cy, 2.3, 0, Math.PI * 2)
                            ctx.fill()

                            for (let index = 0; index < 8; ++index) {
                                const angle =
                                    index * Math.PI / 4
                                line(
                                    cx + Math.cos(angle) * 7.5,
                                    cy + Math.sin(angle) * 7.5,
                                    cx + Math.cos(angle) * 11.0,
                                    cy + Math.sin(angle) * 11.0
                                )
                            }
                        } else if (toolbarButton.iconName === "tx") {
                            ctx.beginPath()
                            ctx.roundedRect(12, 6, 8, 13, 4, 4)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(16, 15, 8, 0.22, 2.92)
                            ctx.stroke()

                            line(16, 23, 16, 27)
                            line(12, 27, 20, 27)

                            ctx.beginPath()
                            ctx.arc(24, 9, 3.4, -0.8, 0.8)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(24, 9, 6.1, -0.65, 0.65)
                            ctx.stroke()
                        } else if (toolbarButton.iconName === "memory") {
                            ctx.strokeRect(7, 6, 18, 20)
                            line(11, 11, 21, 11)
                            line(11, 16, 21, 16)
                            line(11, 21, 17, 21)

                            ctx.beginPath()
                            ctx.arc(23, 22, 4, 0, Math.PI * 2)
                            ctx.stroke()
                            line(23, 18, 23, 22)
                            line(23, 22, 26, 24)
                        } else if (toolbarButton.iconName === "toneRtty") {
                            ctx.beginPath()
                            ctx.moveTo(5, 12)
                            ctx.bezierCurveTo(9, 5, 13, 19, 17, 12)
                            ctx.bezierCurveTo(21, 5, 24, 19, 28, 12)
                            ctx.stroke()

                            line(7, 22, 11, 22)
                            line(14, 22, 18, 22)
                            line(21, 22, 25, 22)

                            ctx.beginPath()
                            ctx.arc(16, 22, 7, Math.PI, 0)
                            ctx.stroke()
                        } else if (toolbarButton.iconName === "scope") {
                            line(5, 25, 27, 25)
                            line(5, 8, 5, 25)

                            ctx.beginPath()
                            ctx.moveTo(6, 22)
                            ctx.lineTo(9, 20)
                            ctx.lineTo(12, 21)
                            ctx.lineTo(15, 12)
                            ctx.lineTo(18, 18)
                            ctx.lineTo(21, 10)
                            ctx.lineTo(24, 16)
                            ctx.lineTo(27, 13)
                            ctx.stroke()

                            for (let index = 0;
                                 index < 5;
                                 ++index) {
                                ctx.fillStyle =
                                    Qt.rgba(
                                        0.20,
                                        0.72 - index * 0.08,
                                        0.95,
                                        0.70
                                    )
                                ctx.fillRect(
                                    7 + index * 4,
                                    27,
                                    3,
                                    2
                                )
                            }
                        } else if (toolbarButton.iconName === "morse") {
                            line(5, 25, 27, 25)
                            line(8, 21, 19, 12)
                            line(19, 12, 25, 12)

                            ctx.beginPath()
                            ctx.arc(8, 25, 2.4, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(21, 11.5, 2.5, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(24.5, 25, 2.1, 0, Math.PI * 2)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(7, 7, 1.7, 0, Math.PI * 2)
                            ctx.fill()
                            line(12, 7, 18, 7)
                            ctx.beginPath()
                            ctx.arc(24, 7, 1.7, 0, Math.PI * 2)
                            ctx.fill()
                        } else if (toolbarButton.iconName === "cw") {
                            line(6, 24, 26, 24)
                            line(10, 20, 20, 11)
                            line(20, 11, 25, 11)

                            ctx.beginPath()
                            ctx.arc(9, 24, 2.5, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(21, 10.5, 2.7, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(25, 24, 2.2, 0, Math.PI * 2)
                            ctx.stroke()
                        } else if (toolbarButton.iconName === "vfoA"
                                   || toolbarButton.iconName === "vfoB") {
                            ctx.beginPath()
                            ctx.arc(cx, cy, 10, 0, Math.PI * 2)
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.arc(cx, cy, 7.2, 0, Math.PI * 2)
                            ctx.stroke()

                            line(cx, 5.5, cx, 8.5)

                            ctx.font =
                                "bold 11px sans-serif"
                            ctx.textAlign = "center"
                            ctx.textBaseline = "middle"
                            ctx.fillText(
                                toolbarButton.iconName === "vfoA"
                                ? "A"
                                : "B",
                                cx,
                                cy + 0.5
                            )
                        } else if (toolbarButton.iconName === "advanced") {
                            line(7, 9, 25, 9)
                            line(7, 16, 25, 16)
                            line(7, 23, 25, 23)

                            ctx.beginPath()
                            ctx.arc(12, 9, 2.8, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(21, 16, 2.8, 0, Math.PI * 2)
                            ctx.fill()

                            ctx.beginPath()
                            ctx.arc(15, 23, 2.8, 0, Math.PI * 2)
                            ctx.fill()
                        } else if (toolbarButton.iconName === "exit") {
                            ctx.strokeRect(7, 6.5, 12, 20)
                            line(15, 16, 27, 16)
                            line(23, 12, 27, 16)
                            line(23, 20, 27, 16)

                            ctx.beginPath()
                            ctx.arc(11.5, 16, 1.2, 0, Math.PI * 2)
                            ctx.fill()
                        } else {
                            ctx.beginPath()
                            ctx.arc(cx, cy, 8, 0, Math.PI * 2)
                            ctx.stroke()
                        }
                    }
                }
            }

            Text {
                width:
                    toolbarButton.width - 4
                text:
                    toolbarButton.text
                color:
                    toolbarButton.hovered
                    ? "#ffffff"
                    : "#e7edf1"
                font.pixelSize:
                    toolbarButton.text.length > 8 ? 7 : 9
                font.bold: true
                horizontalAlignment:
                    Text.AlignHCenter
                elide: Text.ElideRight
                clip: true
            }
        }
    }

    component ToolbarGroup: Rectangle {
        id: toolbarGroup

        default property alias buttons: toolbarGroupButtons.data
        property string caption: "GRUPO"
        property color accentColor: "#5f8799"

        function applyAccent(item) {
            if (!item)
                return
            if (typeof item.groupAccentColor !== "undefined")
                item.groupAccentColor = accentColor
            if (typeof item.children === "undefined")
                return
            for (let index = 0; index < item.children.length; ++index)
                applyAccent(item.children[index])
        }

        Component.onCompleted:
            Qt.callLater(function() {
                toolbarGroup.applyAccent(toolbarGroupButtons)
            })

        onAccentColorChanged:
            Qt.callLater(function() {
                toolbarGroup.applyAccent(toolbarGroupButtons)
            })

        implicitWidth: toolbarGroupContent.implicitWidth + 10
        implicitHeight: 66
        radius: 5
        color: "#30363a"
        border.color: Qt.darker(toolbarGroup.accentColor, 1.12)
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 14
            radius: 4
            color: toolbarGroup.accentColor
            opacity: 0.34
        }

        ColumnLayout {
            id: toolbarGroupContent
            anchors.fill: parent
            anchors.margins: 4
            spacing: 1

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 11
                text: toolbarGroup.caption
                color: Qt.lighter(toolbarGroup.accentColor, 1.55)
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 0.6
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            RowLayout {
                id: toolbarGroupButtons
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3
            }
        }
    }

    component PanelButton: Button {
        id: panelButton

        property bool selected: false
        property color activeColor: "#2f72b9"
        property color groupAccentColor: "#5f8799"
        property int textPixelSize: 10
        // Icono vectorial opcional para los botones compactos.
        property string iconName: ""
        property string tip:
            controlHelp(text)

        implicitHeight: 27

        background: Rectangle {
            radius: 2
            color:
                panelButton.selected
                ? panelButton.activeColor
                : panelButton.down
                  ? Qt.tint(
                        "#252b2f",
                        Qt.rgba(
                            panelButton.groupAccentColor.r,
                            panelButton.groupAccentColor.g,
                            panelButton.groupAccentColor.b,
                            0.48
                        )
                    )
                  : panelButton.hovered
                    ? Qt.tint(
                          "#252b2f",
                          Qt.rgba(
                              panelButton.groupAccentColor.r,
                              panelButton.groupAccentColor.g,
                              panelButton.groupAccentColor.b,
                              0.38
                          )
                      )
                    : Qt.tint(
                          "#171b1e",
                          Qt.rgba(
                              panelButton.groupAccentColor.r,
                              panelButton.groupAccentColor.g,
                              panelButton.groupAccentColor.b,
                              0.24
                          )
                      )
            border.color:
                panelButton.selected
                ? "#d1e9ff"
                : panelButton.hovered
                  ? Qt.lighter(
                        panelButton.groupAccentColor,
                        1.38
                    )
                  : Qt.lighter(
                        panelButton.groupAccentColor,
                        1.08
                    )
            border.width: 1

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color:
                        panelButton.selected
                        ? Qt.lighter(
                              panelButton.activeColor,
                              1.16
                          )
                        : Qt.darker(
                              panelButton.groupAccentColor,
                              1.12
                          )
                }

                GradientStop {
                    position: 1
                    color:
                        panelButton.selected
                        ? Qt.darker(
                              panelButton.activeColor,
                              1.22
                          )
                        : Qt.tint(
                              "#111518",
                              Qt.rgba(
                                  panelButton.groupAccentColor.r,
                                  panelButton.groupAccentColor.g,
                                  panelButton.groupAccentColor.b,
                                  0.16
                              )
                          )
                }
            }
        }

        ToolTip.visible:
            hovered
            && tip.length > 0
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text: tip

        contentItem: Item {
            anchors.fill: parent

            Text {
                anchors.fill: parent
                visible: panelButton.iconName.length === 0
                text: panelButton.text
                color: panelButton.enabled ? "#f1f1f1" : "#818181"
                font.pixelSize: panelButton.textPixelSize
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Canvas {
                anchors.centerIn: parent
                width: 23
                height: 23
                visible: panelButton.iconName === "browser"
                antialiasing: true
                property color iconColor:
                    panelButton.enabled ? "#f1f1f1" : "#818181"
                onIconColorChanged: requestPaint()
                onVisibleChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    const color = iconColor
                    ctx.reset()
                    ctx.strokeStyle = color
                    ctx.lineWidth = 1.8
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.arc(11.5, 11.5, 9.2, 0, Math.PI * 2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.ellipse(11.5, 11.5, 4.1, 9.2, 0, 0, Math.PI * 2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(2.8, 11.5)
                    ctx.lineTo(20.2, 11.5)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
            }
        }
    }

    component SidePanelGroup: Rectangle {
        id: sidePanelGroup

        default property alias controls: sidePanelControls.data
        property string caption: "GRUPO"
        property color accentColor: "#5f8799"

        function applyAccent(item) {
            if (!item)
                return
            if (typeof item.groupAccentColor !== "undefined")
                item.groupAccentColor = accentColor
            if (typeof item.children === "undefined")
                return
            for (let index = 0; index < item.children.length; ++index)
                applyAccent(item.children[index])
        }

        Component.onCompleted:
            Qt.callLater(function() {
                sidePanelGroup.applyAccent(sidePanelControls)
            })

        onAccentColorChanged:
            Qt.callLater(function() {
                sidePanelGroup.applyAccent(sidePanelControls)
            })

        Layout.fillWidth: true
        implicitHeight: sidePanelContent.implicitHeight + 6
        radius: 5
        color: "#22272a"
        border.color: Qt.darker(sidePanelGroup.accentColor, 1.08)
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 3
            radius: 2
            color: sidePanelGroup.accentColor
            opacity: 0.85
        }

        ColumnLayout {
            id: sidePanelContent
            anchors.fill: parent
            anchors.margins: 3
            spacing: 3

            PanelGroupHeader {
                Layout.fillWidth: true
                caption: sidePanelGroup.caption
                accentColor: sidePanelGroup.accentColor
            }

            ColumnLayout {
                id: sidePanelControls
                Layout.fillWidth: true
                spacing: 3
            }
        }
    }

    component PanelGroupHeader: Rectangle {
        id: panelGroupHeader

        property string caption: ""
        property color accentColor: "#5f8799"

        implicitHeight: 18
        radius: 2
        color: "#171d20"
        border.color:
            panelGroupHeader.accentColor
        border.width: 1

        Text {
            anchors.fill: parent
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            text:
                panelGroupHeader.caption
            color:
                Qt.lighter(
                    panelGroupHeader.accentColor,
                    1.45
                )
            font.pixelSize: 8
            font.bold: true
            horizontalAlignment:
                Text.AlignHCenter
            verticalAlignment:
                Text.AlignVCenter
            elide:
                Text.ElideRight
        }
    }

    component StatusTag: Rectangle {
        property string caption: ""
        property color tagColor: "#315f9b"

        implicitWidth:
            statusText.implicitWidth + 12
        implicitHeight: 21
        radius: 2
        color: tagColor
        border.color: "#9bb3d3"

        Text {
            id: statusText
            anchors.centerIn: parent
            text: parent.caption
            color: "#f1f6ff"
            font.pixelSize: 9
            font.bold: true
        }
    }

    component MeterLine: Item {
        id: meter

        property string caption: ""
        property string valueText: ""
        property int percent: 0
        property bool multicolor: false
        property color barColor: "#43bafd"

        implicitHeight: 18

        HoverHandler {
            id: meterHover
        }

        ToolTip.visible:
            meterHover.hovered
            && meterHelp(caption).length > 0
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text:
            meterHelp(caption)

        RowLayout {
            anchors.fill: parent
            spacing: 4

            Text {
                Layout.preferredWidth: 34
                text: meter.caption
                color: "#f0f0f0"
                font.pixelSize: 9
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 10
                color: "#070707"
                border.color: "#5e5e5e"

                Rectangle {
                    visible:
                        !meter.multicolor
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom:
                        parent.bottom
                    width:
                        parent.width
                        * Math.max(
                            0,
                            Math.min(
                                100,
                                meter.percent
                            )
                        )
                        / 100
                    color:
                        meter.barColor
                }

                Row {
                    visible:
                        meter.multicolor
                    anchors.fill: parent
                    anchors.margins: 1
                    spacing: 1

                    Repeater {
                        model: 24

                        Rectangle {
                            width:
                                (parent.width - 23)
                                / 24
                            height:
                                parent.height
                            color:
                                index < 12
                                ? "#2ecc71"
                                : index < 17
                                  ? "#f1c40f"
                                  : index < 20
                                    ? "#e67e22"
                                    : "#e74c3c"
                            opacity:
                                index
                                < Math.ceil(
                                    Math.max(
                                        0,
                                        Math.min(
                                            100,
                                            meter.percent
                                        )
                                    )
                                    * 24
                                    / 100
                                )
                                ? 1.0
                                : 0.16
                        }
                    }
                }
            }

            Text {
                Layout.preferredWidth: 52
                text: meter.valueText
                color: "#f0f0f0"
                font.pixelSize: 9
                font.bold: true
                horizontalAlignment:
                    Text.AlignRight
            }
        }
    }

    component AnalogSMeter: Rectangle {
        id: analogMeter

        property real meterPercent: 0
        property string valueText: "S0"
        property real displayedPercent:
            Math.max(0, Math.min(100, meterPercent))

        implicitWidth: 190
        implicitHeight: 104
        radius: 5
        color: "#e5dfcc"
        border.color: "#7d7562"
        border.width: 2

        Behavior on displayedPercent {
            NumberAnimation {
                duration: 70
                easing.type: Easing.OutQuad
            }
        }

        onDisplayedPercentChanged: meterCanvas.requestPaint()

        Canvas {
            id: meterCanvas
            anchors.fill: parent
            anchors.margins: 4
            antialiasing: true

            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                const w = width
                const h = height
                const cx = w / 2
                const cy = h * 0.92
                const radius = Math.min(w * 0.45, h * 0.82)
                const start = -Math.PI * 0.84
                const end = -Math.PI * 0.16
                const marks = [
                    { p: 0.00, t: "1" },
                    { p: 0.16, t: "3" },
                    { p: 0.32, t: "5" },
                    { p: 0.48, t: "7" },
                    { p: 0.62, t: "9" },
                    { p: 0.75, t: "+20" },
                    { p: 0.88, t: "+40" },
                    { p: 1.00, t: "+60" }
                ]

                ctx.reset()
                ctx.clearRect(0, 0, w, h)
                ctx.lineCap = "round"
                ctx.strokeStyle = "#292b29"
                ctx.lineWidth = 1.3
                ctx.beginPath()
                ctx.arc(cx, cy, radius, start, end)
                ctx.stroke()

                ctx.strokeStyle = "#b52925"
                ctx.lineWidth = 2.2
                ctx.beginPath()
                ctx.arc(cx, cy, radius,
                        start + (end - start) * 0.62, end)
                ctx.stroke()

                ctx.font = "bold 8px DejaVu Sans"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                for (let index = 0; index < marks.length; ++index) {
                    const mark = marks[index]
                    const angle = start + (end - start) * mark.p
                    const inner = radius - (mark.p >= 0.62 ? 9 : 7)
                    const labelRadius = radius - 18
                    ctx.strokeStyle = mark.p >= 0.62
                                      ? "#a32121" : "#252725"
                    ctx.lineWidth = mark.p >= 0.62 ? 1.5 : 1.0
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(angle) * inner,
                               cy + Math.sin(angle) * inner)
                    ctx.lineTo(cx + Math.cos(angle) * radius,
                               cy + Math.sin(angle) * radius)
                    ctx.stroke()
                    ctx.fillStyle = ctx.strokeStyle
                    ctx.fillText(mark.t,
                                 cx + Math.cos(angle) * labelRadius,
                                 cy + Math.sin(angle) * labelRadius)
                }

                ctx.fillStyle = "#252725"
                ctx.font = "bold 9px DejaVu Sans"
                ctx.fillText("S", cx - 10, 14)
                ctx.fillStyle = "#a32121"
                ctx.fillText("dB", cx + 10, 14)

                const needleAngle = start + (end - start)
                    * analogMeter.displayedPercent / 100
                ctx.strokeStyle = "#d32020"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(
                    cx + Math.cos(needleAngle) * (radius - 4),
                    cy + Math.sin(needleAngle) * (radius - 4)
                )
                ctx.stroke()
                ctx.fillStyle = "#202020"
                ctx.beginPath()
                ctx.arc(cx, cy, 5, 0, Math.PI * 2)
                ctx.fill()
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            width: analogValue.implicitWidth + 12
            height: 17
            radius: 3
            color: "#252a28"

            Text {
                id: analogValue
                anchors.centerIn: parent
                text: analogMeter.valueText
                color: "#f2d16b"
                font.pixelSize: 10
                font.bold: true
            }
        }

        ToolTip.visible: analogHover.hovered
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text:
            "S-meter analógico con la lectura CI-V de señal recibida."

        HoverHandler {
            id: analogHover
        }
    }

    component KnobControl: FrameBox {
        id: knob

        property string caption: ""
        property int currentValue: 0
        property real wheelValue: 0
        property color accentColor: "#52c6ff"
        property var applyFunction
        property bool compact: false
        property bool showCaption: true
        property string tip:
            controlHelp(caption)
            + " · Rueda arriba: aumentar. "
            + "Rueda abajo: disminuir."

        function boundedCurrentValue() {
            const value =
                Number(knob.currentValue)

            return Math.max(
                0,
                Math.min(
                    100,
                    isFinite(value)
                    ? value
                    : 0
                )
            )
        }

        function synchronizeFromRadio() {
            wheelValue =
                boundedCurrentValue()

            if (!dial.pressed
                    && !knobWheelSync.running) {
                dial.value =
                    wheelValue
            }
        }

        Component.onCompleted:
            synchronizeFromRadio()

        onCurrentValueChanged: {
            if (!dial.pressed
                    && !knobWheelSync.running) {
                synchronizeFromRadio()
            } else if (dial.pressed
                       && !knobWheelSync.running) {
                knob.wheelValue =
                    boundedCurrentValue()
                dial.value =
                    knob.wheelValue
            }
        }

        implicitWidth:
            compact ? 78 : 102
        implicitHeight:
            compact ? 96 : 108

        HoverHandler {
            id: knobHover
        }

        ToolTip.visible:
            knobHover.hovered
            && tip.length > 0
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text: tip

        ColumnLayout {
            anchors.fill: parent
            anchors.margins:
                knob.compact ? 3 : 5
            spacing:
                knob.compact ? 1 : 3

            Text {
                visible:
                    knob.showCaption
                Layout.alignment:
                    Qt.AlignHCenter
                Layout.preferredHeight:
                    visible ? implicitHeight : 0
                text: knob.caption
                color: "#ededed"
                font.pixelSize:
                    knob.compact ? 8 : 9
                font.bold: true
            }

            Dial {
                id: dial

                Layout.alignment:
                    Qt.AlignHCenter
                Layout.preferredWidth:
                    knob.compact ? 52 : 64
                Layout.preferredHeight:
                    knob.compact ? 52 : 64

                from: 0
                to: 100
                stepSize: 1
                enabled:
                    controlsEnabled()

                background: Rectangle {
                    x: dial.width / 2 - width / 2
                    y: dial.height / 2 - height / 2
                    width: Math.min(
                        dial.width,
                        dial.height
                    ) - 8
                    height: width
                    radius: width / 2
                    color: "#080808"
                    border.color: "#8b8b8b"
                    border.width: 2

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        height: width
                        radius: width / 2
                        color: "#242424"
                        border.color: "#464646"
                        border.width: 1

                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "#3a3a3a"
                            }

                            GradientStop {
                                position: 1
                                color: "#111111"
                            }
                        }
                    }
                }

                handle: Rectangle {
                    x:
                        dial.background.x
                        + dial.background.width / 2
                        - width / 2
                    y:
                        dial.background.y
                        + dial.background.height / 2
                        - height / 2
                    width: 5
                    height:
                        dial.background.height / 2
                        - 6
                    radius: 2
                    color: knob.accentColor
                    antialiasing: true
                    transform: [
                        Translate {
                            y:
                                -dial.background.height / 4
                                + 4
                        },
                        Rotation {
                            angle:
                                dial.angle
                            origin.x:
                                2.5
                            origin.y:
                                dial.background.height / 4
                                - 4
                        }
                    ]
                }

                onPressedChanged: {
                    if (pressed) {
                        knob.wheelValue =
                            knob.boundedCurrentValue()
                        dial.value =
                            knob.wheelValue
                    } else if (enabled
                               && knob.applyFunction) {
                        knob.wheelValue =
                            Math.round(value)
                        knob.applyFunction(
                            Math.round(value)
                        )
                    }
                }

                WheelHandler {
                    id: knobWheelHandler

                    acceptedDevices:
                        PointerDevice.Mouse
                        | PointerDevice.TouchPad

                    onWheel: function(event) {
                        if (!dial.enabled
                                || !knob.applyFunction) {
                            event.accepted = false
                            return
                        }

                        const delta =
                            event.angleDelta.y !== 0
                            ? event.angleDelta.y
                            : event.pixelDelta.y

                        if (delta === 0) {
                            event.accepted = false
                            return
                        }

                        const direction =
                            delta > 0 ? 1 : -1

                        if (!knobWheelSync.running) {
                            knob.wheelValue =
                                knob.boundedCurrentValue()
                        }

                        const baseValue =
                            knob.wheelValue
                        const nextValue =
                            Math.max(
                                dial.from,
                                Math.min(
                                    dial.to,
                                    baseValue
                                    + direction
                                      * dial.stepSize
                                )
                            )

                        // Se detiene primero el Binding del valor leído.
                        // Así el primer toque parte siempre del valor leído.
                        knobWheelSync.restart()
                        dial.value =
                            baseValue

                        if (nextValue !== baseValue) {
                            knob.wheelValue =
                                nextValue
                            dial.value =
                                nextValue
                            knob.applyFunction(
                                Math.round(nextValue)
                            )
                        }

                        event.accepted = true
                    }
                }

                Timer {
                    id: knobWheelSync
                    interval: 350
                    repeat: false

                    onTriggered:
                        knob.synchronizeFromRadio()
                }
            }

            Binding {
                target: dial
                property: "value"
                value:
                    knob.currentValue
                when:
                    !dial.pressed
                    && !knobWheelSync.running
            }

            Text {
                Layout.alignment:
                    Qt.AlignHCenter
                text:
                    Math.round(dial.value)
                    + " %"
                color:
                    knob.accentColor
                font.pixelSize:
                    knob.compact ? 8 : 9
                font.bold: true
            }
        }
    }

    component FilterCurveDisplay: FrameBox {
        id: filterCurve

        property string filterText: "FIL2"
        property int filterShape: 0
        property string modeText: "USB"
        property int pbt1: 50
        property int pbt2: 50
        property bool manualNotchEnabled: false
        property int manualNotchPosition: 50
        property int manualNotchWidth: 1

        implicitWidth: 126
        implicitHeight: 56
        color: "#0e1316"
        border.color: "#49707a"
        raised: true
        radius: 3
        clip: true

        function clamp(value, minimum, maximum) {
            return Math.max(
                minimum,
                Math.min(maximum, value)
            )
        }

        function modeFamily() {
            const mode =
                String(modeText).toUpperCase()

            if (mode.indexOf("CW") >= 0) {
                return "CW"
            }

            if (mode.indexOf("RTTY") >= 0) {
                return "RTTY"
            }

            if (mode === "AM") {
                return "AM"
            }

            if (mode === "FM") {
                return "FM"
            }

            return "SSB"
        }

        function hasVariableShape() {
            return filterText !== "FIL3"
        }

        function shapeLabel() {
            if (!hasVariableShape()) {
                return "FIXED"
            }

            return filterShape === 0
                   ? "SHARP"
                   : "SOFT"
        }

        function shapeColor() {
            if (!hasVariableShape()) {
                return "#c5cbd1"
            }

            return filterShape === 0
                   ? "#9fe6ff"
                   : "#ffd492"
        }

        function filterWidthNorm() {
            if (filterText === "FIL1") {
                return 0.76
            }

            if (filterText === "FIL3") {
                return 0.36
            }

            return 0.58
        }

        function bandwidthText() {
            const family =
                modeFamily()

            if (family === "CW") {
                if (filterText === "FIL1") {
                    return "BW 500 Hz"
                }

                if (filterText === "FIL2") {
                    return "BW 250 Hz"
                }

                return "BW 50 Hz"
            }

            if (family === "RTTY") {
                if (filterText === "FIL1") {
                    return "BW 500 Hz"
                }

                if (filterText === "FIL2") {
                    return "BW 350 Hz"
                }

                return "BW 250 Hz"
            }

            if (family === "AM") {
                if (filterText === "FIL1") {
                    return "BW 9.0 kHz"
                }

                if (filterText === "FIL2") {
                    return "BW 6.0 kHz"
                }

                return "BW 3.0 kHz"
            }

            if (family === "FM") {
                if (filterText === "FIL1") {
                    return "BW 15 kHz"
                }

                if (filterText === "FIL2") {
                    return "BW 10 kHz"
                }

                return "BW 7.0 kHz"
            }

            if (filterText === "FIL1") {
                return "BW 3.6 kHz"
            }

            if (filterText === "FIL2") {
                return "BW 2.4 kHz"
            }

            return "BW 1.2 kHz"
        }

        function scaleLabels() {
            const family =
                modeFamily()

            if (family === "CW"
                    || family === "RTTY") {
                return [
                    "-600",
                    "-300",
                    "0",
                    "+300",
                    "+600"
                ]
            }

            if (family === "AM") {
                return [
                    "-6k",
                    "-3k",
                    "0",
                    "+3k",
                    "+6k"
                ]
            }

            if (family === "FM") {
                return [
                    "-8k",
                    "-4k",
                    "0",
                    "+4k",
                    "+8k"
                ]
            }

            return [
                "-3k",
                "-1.5k",
                "0",
                "+1.5k",
                "+3k"
            ]
        }

        function pbtText(value) {
            const delta =
                Math.round(
                    Number(value) - 50
                )

            return (delta >= 0 ? "+" : "")
                   + delta
        }

        function leftEdgeNorm() {
            const baseHalf =
                filterWidthNorm() / 2.0
            const shift =
                (pbt1 - 50) / 50.0 * 0.18

            return clamp(
                0.5 - baseHalf + shift,
                0.05,
                0.85
            )
        }

        function rightEdgeNorm() {
            const baseHalf =
                filterWidthNorm() / 2.0
            const shift =
                (pbt2 - 50) / 50.0 * 0.18

            return clamp(
                0.5 + baseHalf + shift,
                0.15,
                0.95
            )
        }

        function notchCenterNorm(leftEdge, rightEdge) {
            const insideWidth =
                Math.max(
                    0.12,
                    rightEdge - leftEdge
                )

            return clamp(
                leftEdge
                + manualNotchPosition / 100.0
                  * insideWidth,
                leftEdge + 0.04,
                rightEdge - 0.04
            )
        }

        function notchWidthNorm() {
            if (manualNotchWidth <= 0) {
                return 0.018
            }

            if (manualNotchWidth === 1) {
                return 0.030
            }

            return 0.048
        }

        function requestRepaint() {
            curveCanvas.requestPaint()
        }

        onFilterTextChanged:
            requestRepaint()
        onFilterShapeChanged:
            requestRepaint()
        onModeTextChanged:
            requestRepaint()
        onPbt1Changed:
            requestRepaint()
        onPbt2Changed:
            requestRepaint()
        onManualNotchEnabledChanged:
            requestRepaint()
        onManualNotchPositionChanged:
            requestRepaint()
        onManualNotchWidthChanged:
            requestRepaint()
        onWidthChanged:
            requestRepaint()
        onHeightChanged:
            requestRepaint()

        Canvas {
            id: curveCanvas

            anchors.fill: parent
            anchors.margins: 3
            antialiasing: true

            onPaint: {
                const ctx =
                    getContext("2d")
                const w = width
                const h = height

                ctx.reset()
                ctx.clearRect(0, 0, w, h)

                const leftNorm =
                    filterCurve.leftEdgeNorm()
                const rightNormRaw =
                    filterCurve.rightEdgeNorm()
                const rightNorm =
                    Math.max(
                        leftNorm + 0.10,
                        rightNormRaw
                    )

                const chartLeft = 10
                const chartRight = w - 10
                const chartWidth =
                    Math.max(
                        20,
                        chartRight - chartLeft
                    )
                const left =
                    chartLeft
                    + leftNorm * chartWidth
                const right =
                    chartLeft
                    + rightNorm * chartWidth
                const baseline =
                    h - 16
                const top =
                    18
                const midY =
                    baseline - (baseline - top) * 0.55
                const centerX =
                    (left + right) / 2
                const hardShape =
                    !filterCurve.hasVariableShape()
                    || filterCurve.filterShape === 0

                const slopeSpan =
                    !filterCurve.hasVariableShape()
                    ? Math.max(
                        10,
                        (right - left) * 0.20
                    )
                    : filterCurve.filterShape === 0
                      ? Math.max(
                          12,
                          (right - left) * 0.17
                      )
                      : Math.max(
                          19,
                          (right - left) * 0.30
                      )

                const domeRise =
                    !filterCurve.hasVariableShape()
                    ? 4.6
                    : filterCurve.filterShape === 0
                      ? 2.6
                      : 1.3

                const crestY =
                    !filterCurve.hasVariableShape()
                    ? top + 4
                    : filterCurve.filterShape === 0
                      ? top + 5
                      : top + 8

                const entryStart =
                    Math.max(
                        chartLeft,
                        left - slopeSpan
                    )
                const exitEnd =
                    Math.min(
                        chartRight,
                        right + slopeSpan
                    )

                // Fondo tipo pantalla retroiluminada
                const gradient =
                    ctx.createLinearGradient(
                        0, top - 3,
                        0, baseline
                    )
                gradient.addColorStop(
                    0.0,
                    "rgba(15, 26, 30, 0.98)"
                )
                gradient.addColorStop(
                    0.50,
                    "rgba(22, 38, 42, 0.92)"
                )
                gradient.addColorStop(
                    1.0,
                    "rgba(8, 14, 16, 0.98)"
                )
                ctx.fillStyle = gradient
                ctx.fillRect(
                    chartLeft,
                    top - 3,
                    chartWidth,
                    baseline - top + 4
                )

                // Halo suave superior
                const halo =
                    ctx.createLinearGradient(
                        0, top - 3,
                        0, top + 12
                    )
                halo.addColorStop(
                    0.0,
                    "rgba(110, 220, 255, 0.20)"
                )
                halo.addColorStop(
                    1.0,
                    "rgba(110, 220, 255, 0.00)"
                )
                ctx.fillStyle = halo
                ctx.fillRect(
                    chartLeft + 1,
                    top - 2,
                    chartWidth - 2,
                    16
                )

                // Borde interior de la zona
                ctx.strokeStyle = "#2b4a55"
                ctx.lineWidth = 1
                ctx.strokeRect(
                    chartLeft + 0.5,
                    top - 2.5,
                    chartWidth - 1,
                    baseline - top + 3
                )

                // Rejilla horizontal
                ctx.strokeStyle = "#233239"
                ctx.lineWidth = 1

                ctx.beginPath()
                ctx.moveTo(chartLeft, baseline)
                ctx.lineTo(chartRight, baseline)
                ctx.stroke()

                ctx.beginPath()
                ctx.moveTo(chartLeft, midY)
                ctx.lineTo(chartRight, midY)
                ctx.stroke()

                ctx.beginPath()
                ctx.moveTo(chartLeft, top + 1)
                ctx.lineTo(chartRight, top + 1)
                ctx.stroke()

                // Línea central destacada
                ctx.strokeStyle = "#4a707e"
                ctx.beginPath()
                ctx.moveTo(chartLeft + chartWidth / 2, top - 2)
                ctx.lineTo(chartLeft + chartWidth / 2, baseline + 1)
                ctx.stroke()

                const scaleLabels =
                    filterCurve.scaleLabels()

                ctx.font = "bold 8px Sans"
                ctx.textAlign = "center"
                ctx.fillStyle = "#81949d"

                for (let i = 0; i < scaleLabels.length; ++i) {
                    const x =
                        chartLeft
                        + chartWidth * (0.1 + i * 0.2)

                    ctx.strokeStyle =
                        i === 2
                        ? "#6f98a7"
                        : "#2f3d43"
                    ctx.beginPath()
                    ctx.moveTo(x, baseline)
                    ctx.lineTo(
                        x,
                        i === 2
                        ? baseline - 6
                        : baseline - 4
                    )
                    ctx.stroke()

                    ctx.fillText(
                        scaleLabels[i],
                        x,
                        h - 3
                    )
                }

                // Banda pasante con iluminación
                const passbandGradient =
                    ctx.createLinearGradient(
                        0, top,
                        0, baseline
                    )
                passbandGradient.addColorStop(
                    0.0,
                    "rgba(132, 232, 255, 0.34)"
                )
                passbandGradient.addColorStop(
                    0.45,
                    "rgba(88, 198, 255, 0.24)"
                )
                passbandGradient.addColorStop(
                    1.0,
                    "rgba(72, 170, 220, 0.10)"
                )

                // Resplandor exterior
                ctx.strokeStyle = "rgba(96, 214, 255, 0.22)"
                ctx.lineWidth = 5.0
                ctx.beginPath()
                ctx.moveTo(entryStart, baseline)
                ctx.bezierCurveTo(
                    entryStart + slopeSpan * 0.20,
                    baseline,
                    left - slopeSpan * 0.30,
                    crestY + 8,
                    left + slopeSpan * 0.22,
                    crestY + 1
                )
                ctx.bezierCurveTo(
                    centerX - (right - left) * 0.20,
                    crestY - domeRise,
                    centerX + (right - left) * 0.20,
                    crestY - domeRise,
                    right - slopeSpan * 0.22,
                    crestY + 1
                )
                ctx.bezierCurveTo(
                    right + slopeSpan * 0.30,
                    crestY + 8,
                    exitEnd - slopeSpan * 0.20,
                    baseline,
                    exitEnd,
                    baseline
                )
                ctx.stroke()

                ctx.fillStyle = passbandGradient
                ctx.strokeStyle = "#75d5ff"
                ctx.lineWidth = 2.0

                ctx.beginPath()
                ctx.moveTo(chartLeft, baseline)
                ctx.lineTo(entryStart, baseline)

                ctx.bezierCurveTo(
                    entryStart + slopeSpan * 0.20,
                    baseline,
                    left - slopeSpan * 0.30,
                    crestY + 8,
                    left + slopeSpan * 0.22,
                    crestY + 1
                )

                ctx.bezierCurveTo(
                    centerX - (right - left) * 0.20,
                    crestY - domeRise,
                    centerX + (right - left) * 0.20,
                    crestY - domeRise,
                    right - slopeSpan * 0.22,
                    crestY + 1
                )

                ctx.bezierCurveTo(
                    right + slopeSpan * 0.30,
                    crestY + 8,
                    exitEnd - slopeSpan * 0.20,
                    baseline,
                    exitEnd,
                    baseline
                )

                ctx.lineTo(chartRight, baseline)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()

                // Refuerzo del borde superior
                ctx.strokeStyle =
                    hardShape
                    ? "#ccf6ff"
                    : "#ffe1b6"
                ctx.lineWidth = 1.30
                ctx.beginPath()
                ctx.moveTo(entryStart, baseline)
                ctx.bezierCurveTo(
                    entryStart + slopeSpan * 0.20,
                    baseline,
                    left - slopeSpan * 0.30,
                    crestY + 8,
                    left + slopeSpan * 0.22,
                    crestY + 1
                )
                ctx.bezierCurveTo(
                    centerX - (right - left) * 0.20,
                    crestY - domeRise,
                    centerX + (right - left) * 0.20,
                    crestY - domeRise,
                    right - slopeSpan * 0.22,
                    crestY + 1
                )
                ctx.bezierCurveTo(
                    right + slopeSpan * 0.30,
                    crestY + 8,
                    exitEnd - slopeSpan * 0.20,
                    baseline,
                    exitEnd,
                    baseline
                )
                ctx.stroke()

                // Marcas laterales de desplazamiento / anchura
                const markerY =
                    baseline - 8

                ctx.strokeStyle = "#7ddcff"
                ctx.fillStyle = "#7ddcff"
                ctx.lineWidth = 1.2

                ctx.beginPath()
                ctx.moveTo(chartLeft + 2, markerY)
                ctx.lineTo(left - 4, markerY)
                ctx.stroke()

                ctx.beginPath()
                ctx.moveTo(left - 4, markerY)
                ctx.lineTo(left - 10, markerY - 3)
                ctx.lineTo(left - 10, markerY + 3)
                ctx.closePath()
                ctx.fill()

                ctx.strokeStyle = "#c7eeff"
                ctx.fillStyle = "#c7eeff"

                ctx.beginPath()
                ctx.moveTo(right + 4, markerY)
                ctx.lineTo(chartRight - 2, markerY)
                ctx.stroke()

                ctx.beginPath()
                ctx.moveTo(right + 4, markerY)
                ctx.lineTo(right + 10, markerY - 3)
                ctx.lineTo(right + 10, markerY + 3)
                ctx.closePath()
                ctx.fill()

                // Notch manual opcional
                if (filterCurve.manualNotchEnabled) {
                    const notchCenter =
                        filterCurve
                        .notchCenterNorm(
                            leftNorm,
                            rightNorm
                        ) * chartWidth
                        + chartLeft
                    const notchHalf =
                        filterCurve
                        .notchWidthNorm()
                        * chartWidth

                    const notchLeft =
                        Math.max(
                            left + 3,
                            notchCenter - notchHalf
                        )
                    const notchRight =
                        Math.min(
                            right - 3,
                            notchCenter + notchHalf
                        )
                    const notchBottom =
                        baseline - 4
                    const notchDepth =
                        crestY + 10

                    ctx.fillStyle =
                        "rgba(14, 18, 20, 0.94)"
                    ctx.strokeStyle =
                        "#d6a5ff"
                    ctx.lineWidth = 1.4

                    ctx.beginPath()
                    ctx.moveTo(notchLeft, crestY + 2)
                    ctx.lineTo(notchLeft, notchDepth)
                    ctx.quadraticCurveTo(
                        notchCenter,
                        notchBottom,
                        notchRight,
                        notchDepth
                    )
                    ctx.lineTo(notchRight, crestY + 2)
                    ctx.closePath()
                    ctx.fill()
                    ctx.stroke()
                }

                // Etiquetas superiores estilo equipo
                ctx.font = "bold 9px Sans"
                ctx.textAlign = "left"
                ctx.fillStyle = "#d5dee2"
                ctx.fillText(
                    filterCurve.filterText,
                    chartLeft,
                    10
                )

                ctx.textAlign = "center"
                ctx.fillStyle = "#b7e9ff"
                ctx.fillText(
                    filterCurve.bandwidthText(),
                    chartLeft + chartWidth / 2,
                    10
                )

                ctx.textAlign = "right"
                ctx.fillStyle =
                    filterCurve.shapeColor()
                ctx.fillText(
                    filterCurve.shapeLabel(),
                    chartRight,
                    10
                )

                // Indicaciones PBT dentro de la gráfica
                ctx.font = "bold 8px Sans"

                ctx.textAlign = "left"
                ctx.fillStyle = "#8fdcff"
                ctx.fillText(
                    "PBT1 "
                    + filterCurve.pbtText(
                        filterCurve.pbt1
                    ),
                    chartLeft + 4,
                    top + 10
                )

                ctx.textAlign = "right"
                ctx.fillStyle = "#c5edff"
                ctx.fillText(
                    "PBT2 "
                    + filterCurve.pbtText(
                        filterCurve.pbt2
                    ),
                    chartRight - 4,
                    top + 10
                )

                if (filterCurve.manualNotchEnabled) {
                    ctx.textAlign = "center"
                    ctx.fillStyle = "#d9b5ff"
                    ctx.fillText(
                        "NOTCH "
                        + filterCurve.manualNotchWidth,
                        chartLeft + chartWidth / 2,
                        top + 10
                    )
                }
            }
        }
    }

    component TwinPbtControl: FrameBox {
        id: twin

        property bool compact: false

        implicitWidth:
            compact ? 202 : 210
        implicitHeight:
            compact ? 122 : 150
        color: "#202020"
        clip: true

        HoverHandler {
            id: twinHover
        }

        ToolTip.visible:
            twinHover.hovered
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text:
            "Twin PBT: PBT1 y PBT2 desplazan o estrechan conjuntamente la banda pasante."

        ColumnLayout {
            anchors.fill: parent
            anchors.margins:
                twin.compact ? 3 : 6
            spacing:
                twin.compact ? 2 : 4

            Text {
                Layout.alignment:
                    Qt.AlignHCenter
                text: "TWIN-PBT"
                color: "#ededed"
                font.pixelSize:
                    twin.compact ? 9 : 10
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 5

                KnobControl {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 82
                    Layout.preferredWidth: 92
                    Layout.fillHeight: true
                    compact: twin.compact
                    caption: "PBT1"
                    currentValue:
                        radioController.pbt1
                    accentColor: "#6bb8ff"
                    applyFunction:
                        function(value) {
                            radioController
                            .setPbt1(value)
                        }
                }

                KnobControl {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 82
                    Layout.preferredWidth: 92
                    Layout.fillHeight: true
                    compact: twin.compact
                    caption: "PBT2"
                    currentValue:
                        radioController.pbt2
                    accentColor: "#9dd2ff"
                    applyFunction:
                        function(value) {
                            radioController
                            .setPbt2(value)
                        }
                }
            }
        }
    }

    component FrequencyDigits: Text {
        id: frequencyDigits

        required property int vfoNumber
        required property string frequencyValue
        property bool large: false
        property bool active: false

        property color displayColor:
            active
            ? (vfoNumber === 0
               ? "#79e6ff"
               : "#8cf0ad")
            : (radioController.splitEnabled
               ? "#ffc276"
               : "#9bd7aa")

        property color outlineColor:
            active
            ? (vfoNumber === 0
               ? "#123b4c"
               : "#163f27")
            : (radioController.splitEnabled
               ? "#4d2d12"
               : "#17331f")

        text: frequencyValue
        color: displayColor
        style: Text.Outline
        styleColor: outlineColor
        opacity: active ? 1.0 : 0.92
        font.family:
            "DejaVu Sans Mono"
        font.pixelSize:
            large ? 56 : 36
        font.bold: true
        font.letterSpacing:
            large ? 1.2 : 0.6

        function digitStepAt(pointerX) {
            const shown =
                String(frequencyValue)
            const count =
                shown.length

            if (count === 0
                    || contentWidth <= 0) {
                return selectedStep()
            }

            const characterWidth =
                contentWidth / count
            let position =
                Math.floor(
                    pointerX
                    / characterWidth
                )

            position =
                Math.max(
                    0,
                    Math.min(
                        count - 1,
                        position
                    )
                )

            if (shown.charAt(position) < "0"
                    || shown.charAt(position) > "9") {
                const inside =
                    pointerX
                    - position
                    * characterWidth
                let candidate =
                    inside
                    < characterWidth / 2
                    ? position - 1
                    : position + 1

                candidate =
                    Math.max(
                        0,
                        Math.min(
                            count - 1,
                            candidate
                        )
                    )

                while (candidate >= 0
                       && candidate < count
                       && (shown.charAt(candidate) < "0"
                           || shown.charAt(candidate) > "9")) {
                    candidate +=
                        candidate < position
                        ? -1
                        : 1
                }

                if (candidate < 0
                        || candidate >= count) {
                    return selectedStep()
                }

                position =
                    candidate
            }

            let digitsOnRight = 0

            for (let index =
                     position + 1;
                 index < count;
                 ++index) {
                const character =
                    shown.charAt(index)

                if (character >= "0"
                        && character <= "9") {
                    ++digitsOnRight
                }
            }

            return Math.pow(
                10,
                digitsOnRight
            )
        }

        function stepText(step) {
            if (step >= 1000000)
                return (step / 1000000)
                       + " MHz"

            if (step >= 1000)
                return (step / 1000)
                       + " kHz"

            return step + " Hz"
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons:
                Qt.NoButton
            hoverEnabled: true
            enabled:
                controlsEnabled()

            property int pointedStep:
                frequencyDigits
                .digitStepAt(mouseX)

            ToolTip.visible:
                containsMouse
            ToolTip.delay: 350
            ToolTip.timeout: 8000
            ToolTip.text:
                "Rueda sobre esta cifra: ±"
                + frequencyDigits
                  .stepText(pointedStep)

            onWheel: {
                const direction =
                    wheel.angleDelta.y >= 0
                    ? 1
                    : -1
                const step =
                    frequencyDigits
                    .digitStepAt(wheel.x)

                radioController
                .adjustVfoFrequency(
                    frequencyDigits
                    .vfoNumber,
                    direction * step
                )

                tuningAngle +=
                    direction * 8
                wheel.accepted = true
            }
        }
    }


    component ConfigSlider: FrameBox {
        id: configSlider

        property string caption: ""
        property int currentValue: 0
        property int minimumValue: 0
        property int maximumValue: 100
        property int stepValue: 1
        property string suffix: " %"
        property var applyFunction
        property var displayFunction
        property string helpText: ""

        implicitHeight: 82
        color: "#17191b"
        raised: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 4

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: configSlider.caption
                    color: "#e8edf1"
                    font.pixelSize: 10
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text:
                        configSlider.displayFunction
                        ? configSlider.displayFunction(
                              Math.round(levelSlider.value)
                          )
                        : Math.round(levelSlider.value)
                          + configSlider.suffix
                    color: "#72d1ff"
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Slider {
                id: levelSlider

                Layout.fillWidth: true
                from: configSlider.minimumValue
                to: configSlider.maximumValue
                stepSize: configSlider.stepValue
                enabled: controlsEnabled()

                ToolTip.visible:
                    hovered && configSlider.helpText.length > 0
                ToolTip.delay: 450
                ToolTip.timeout: 8000
                ToolTip.text: configSlider.helpText

                onPressedChanged: {
                    if (!pressed
                            && enabled
                            && configSlider.applyFunction) {
                        configSlider.applyFunction(Math.round(value))
                    }
                }
            }

            Binding {
                target: levelSlider
                property: "value"
                value: configSlider.currentValue
                when: !levelSlider.pressed
            }
        }
    }


    component ToneSelector: FrameBox {
        id: toneSelector

        property string caption: ""
        property int currentTenthsHz: 885
        property var applyFunction
        property string helpText: ""

        implicitHeight: 92
        color: "#17191b"
        raised: true

        function closestIndex() {
            let bestIndex = 0
            let bestDistance = Number.MAX_VALUE

            for (let index = 0;
                 index < ctcssToneValues.length;
                 ++index) {
                const distance =
                    Math.abs(
                        ctcssToneValues[index]
                        - currentTenthsHz
                    )

                if (distance < bestDistance) {
                    bestDistance = distance
                    bestIndex = index
                }
            }

            return bestIndex
        }

        function selectRelative(delta) {
            if (!applyFunction
                    || ctcssToneValues.length === 0)
                return

            const currentIndex = closestIndex()
            const nextIndex =
                Math.max(
                    0,
                    Math.min(
                        ctcssToneValues.length - 1,
                        currentIndex + delta
                    )
                )

            applyFunction(
                ctcssToneValues[nextIndex]
            )
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 5

            Text {
                text: toneSelector.caption
                color: "#e8edf1"
                font.pixelSize: 10
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                PanelButton {
                    Layout.preferredWidth: 48
                    text: "−"
                    enabled:
                        controlsEnabled()
                        && toneSelector.closestIndex() > 0
                    tip:
                        "Selecciona el subtono anterior."

                    onClicked:
                        toneSelector.selectRelative(-1)
                }

                FrameBox {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    color: "#08100e"
                    border.color: "#47715f"

                    Text {
                        anchors.centerIn: parent
                        text:
                            (toneSelector.currentTenthsHz / 10)
                            .toFixed(1)
                            .replace(".", ",")
                            + " Hz"
                        color: "#8de2b3"
                        font.family:
                            "DejaVu Sans Mono"
                        font.pixelSize: 16
                        font.bold: true
                    }

                    ToolTip.visible:
                        toneHover.hovered
                        && toneSelector.helpText.length > 0
                    ToolTip.delay: 450
                    ToolTip.timeout: 8000
                    ToolTip.text:
                        toneSelector.helpText

                    HoverHandler {
                        id: toneHover
                    }
                }

                PanelButton {
                    Layout.preferredWidth: 48
                    text: "+"
                    enabled:
                        controlsEnabled()
                        && toneSelector.closestIndex()
                           < ctcssToneValues.length - 1
                    tip:
                        "Selecciona el subtono siguiente."

                    onClicked:
                        toneSelector.selectRelative(1)
                }
            }
        }
    }

    component TuningWheel: Item {
        id: tuning

        implicitWidth: 152
        implicitHeight: 152

        // Ángulo visual suavizado. Las texturas radiales permanecen fijas para
        // evitar el efecto estroboscópico o "rueda de carro" al sintonizar.
        property real visualAngle: window.tuningAngle

        Behavior on visualAngle {
            NumberAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: tuningHover
        }

        ToolTip.visible:
            tuningHover.hovered
        ToolTip.delay: 450
        ToolTip.timeout: 8000
        ToolTip.text:
            "Mando principal de sintonía. Arrastra horizontalmente o utiliza la rueda del ratón."

        // Sombra exterior del mando sobre el panel.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.96
            height: width
            radius: width / 2
            color: "#020202"
            border.color: "#343434"
            border.width: 1
        }

        onVisualAngleChanged:
            wheelCanvas.requestPaint()

        Canvas {
            id: wheelCanvas

            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d")
                const cx = width / 2
                const cy = height / 2
                const r = Math.min(width, height) / 2 - 2

                ctx.reset()
                ctx.clearRect(0, 0, width, height)

                // Borde moleteado negro, como el mando físico del IC-7300MK2.
                ctx.fillStyle = "#070707"
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.fill()

                for (let i = 0; i < 84; ++i) {
                    const a = i * Math.PI * 2 / 84
                    const inner = r - 10
                    const outer = r - (i % 2 === 0 ? 1.5 : 3.0)

                    ctx.beginPath()
                    ctx.moveTo(
                        cx + Math.cos(a) * inner,
                        cy + Math.sin(a) * inner
                    )
                    ctx.lineTo(
                        cx + Math.cos(a) * outer,
                        cy + Math.sin(a) * outer
                    )
                    ctx.strokeStyle =
                        i % 2 === 0 ? "#555555" : "#242424"
                    ctx.lineWidth = 1.35
                    ctx.stroke()
                }

                // Aro interior negro que separa el moleteado del aro metálico.
                ctx.fillStyle = "#0a0a0a"
                ctx.beginPath()
                ctx.arc(cx, cy, r - 10, 0, Math.PI * 2)
                ctx.fill()

                // Aro plateado característico del mando principal.
                const silver = ctx.createLinearGradient(
                    cx - r, cy - r, cx + r, cy + r
                )
                silver.addColorStop(0.00, "#4b4f52")
                silver.addColorStop(0.18, "#e3e5e6")
                silver.addColorStop(0.38, "#777c80")
                silver.addColorStop(0.60, "#f0f1f1")
                silver.addColorStop(0.82, "#686c70")
                silver.addColorStop(1.00, "#d7d9da")

                ctx.fillStyle = silver
                ctx.beginPath()
                ctx.arc(cx, cy, r - 11, 0, Math.PI * 2)
                ctx.fill()

                ctx.fillStyle = "#111214"
                ctx.beginPath()
                ctx.arc(cx, cy, r - 16, 0, Math.PI * 2)
                ctx.fill()

                // Cara frontal metálica oscura.
                const face = ctx.createRadialGradient(
                    cx - r * 0.23,
                    cy - r * 0.30,
                    r * 0.05,
                    cx,
                    cy,
                    r * 0.78
                )
                face.addColorStop(0.00, "#4a4b4d")
                face.addColorStop(0.20, "#303133")
                face.addColorStop(0.58, "#191a1c")
                face.addColorStop(1.00, "#08090a")

                ctx.fillStyle = face
                ctx.beginPath()
                ctx.arc(cx, cy, r - 18, 0, Math.PI * 2)
                ctx.fill()

                // Cepillado radial muy fino para dar aspecto de aluminio oscuro.
                for (let i = 0; i < 180; ++i) {
                    const a = i * Math.PI * 2 / 180
                    const startR = r * 0.18
                    const endR = r - 20
                    ctx.beginPath()
                    ctx.moveTo(
                        cx + Math.cos(a) * startR,
                        cy + Math.sin(a) * startR
                    )
                    ctx.lineTo(
                        cx + Math.cos(a) * endR,
                        cy + Math.sin(a) * endR
                    )
                    ctx.strokeStyle =
                        i % 3 === 0
                        ? "rgba(255,255,255,0.060)"
                        : "rgba(255,255,255,0.022)"
                    ctx.lineWidth = 0.65
                    ctx.stroke()
                }

                // Anillos concéntricos sutiles visibles en el mando real.
                ctx.strokeStyle = "rgba(230,230,230,0.13)"
                ctx.lineWidth = 0.8
                for (let ring = 0; ring < 5; ++ring) {
                    ctx.beginPath()
                    ctx.arc(
                        cx,
                        cy,
                        r * (0.30 + ring * 0.095),
                        0,
                        Math.PI * 2
                    )
                    ctx.stroke()
                }

                // Cubo central elevado.
                const hub = ctx.createRadialGradient(
                    cx - r * 0.05,
                    cy - r * 0.07,
                    1,
                    cx,
                    cy,
                    r * 0.18
                )
                hub.addColorStop(0.00, "#55585a")
                hub.addColorStop(0.35, "#252729")
                hub.addColorStop(1.00, "#090a0b")
                ctx.fillStyle = hub
                ctx.beginPath()
                ctx.arc(cx, cy, r * 0.18, 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "#5d6062"
                ctx.lineWidth = 1.2
                ctx.stroke()

                ctx.fillStyle = "#070808"
                ctx.beginPath()
                ctx.arc(cx, cy, r * 0.080, 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "#333638"
                ctx.lineWidth = 1
                ctx.stroke()

                // Hueco para el dedo. Es el elemento que muestra el giro real
                // mientras las estrías finas permanecen fijas para no producir
                // aliasing visual ni aparente rotación inversa.
                const fingerAngle =
                    -Math.PI * 0.28
                    + tuning.visualAngle * Math.PI / 180
                const fingerRadius = r * 0.43
                const fx = cx + Math.cos(fingerAngle) * fingerRadius
                const fy = cy + Math.sin(fingerAngle) * fingerRadius
                const fr = r * 0.112

                ctx.fillStyle = "rgba(0,0,0,0.58)"
                ctx.beginPath()
                ctx.arc(fx + 1.5, fy + 2.0, fr * 1.18, 0, Math.PI * 2)
                ctx.fill()

                const finger = ctx.createRadialGradient(
                    fx - fr * 0.30,
                    fy - fr * 0.35,
                    fr * 0.08,
                    fx,
                    fy,
                    fr
                )
                finger.addColorStop(0.00, "#5a5c5e")
                finger.addColorStop(0.30, "#242628")
                finger.addColorStop(0.78, "#090a0b")
                finger.addColorStop(1.00, "#020202")
                ctx.fillStyle = finger
                ctx.beginPath()
                ctx.arc(fx, fy, fr, 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "#707376"
                ctx.lineWidth = 1.1
                ctx.stroke()

                ctx.strokeStyle = "rgba(255,255,255,0.18)"
                ctx.lineWidth = 0.8
                ctx.beginPath()
                ctx.arc(
                    fx - fr * 0.08,
                    fy - fr * 0.10,
                    fr * 0.62,
                    Math.PI * 1.08,
                    Math.PI * 1.72
                )
                ctx.stroke()
            }
        }

        // Cristal de luz fijo: no gira y refuerza el volumen del mando.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.70
            height: width
            radius: width / 2
            color: "transparent"
            border.color: "#202224"
            border.width: 1
            opacity: 0.75
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled:
                controlsEnabled()

            property real lastX: 0

            onPressed:
                lastX = mouse.x

            onPositionChanged: {
                if (!pressed)
                    return

                const distance =
                    mouse.x - lastX
                let count = 0

                if (distance >= 7)
                    count =
                        Math.floor(
                            distance / 7
                        )
                else if (distance <= -7)
                    count =
                        Math.ceil(
                            distance / 7
                        )

                if (count !== 0) {
                    tuneSelectedVfo(count)
                    lastX += count * 7
                }
            }

            onWheel: {
                const direction =
                    wheel.angleDelta.y >= 0
                    ? 1
                    : -1

                tuneSelectedVfo(direction)
                wheel.accepted = true
            }
        }
    }




    Dialog {
        id: bandStackingConfirmDialog

        parent: Overlay.overlay
        modal: true
        focus: true
        title: "Sobrescribir registro de banda"
        standardButtons: Dialog.Yes | Dialog.No

        contentItem: Text {
            text:
                "Se guardará el estado actual del VFO en "
                + memoryScanSettingsPopup.bandText(
                      memoryScanSettingsPopup.stackBandCode
                  )
                + ", registro "
                + memoryScanSettingsPopup.pendingStackRegister
                + ".\n\nEl registro anterior será sustituido."
            color: "#e8edf1"
            wrapMode: Text.Wrap
            padding: 12
        }

        background: Rectangle {
            color: "#25292c"
            border.color: "#8e72b0"
            border.width: 2
            radius: 5
        }

        onAccepted:
            radioController.storeCurrentToBandStacking(
                memoryScanSettingsPopup.stackBandCode,
                memoryScanSettingsPopup.pendingStackRegister
            )
    }

    Dialog {
        id: storeMemoryConfirmDialog

        parent: Overlay.overlay
        modal: true
        focus: true
        title: "Sobrescribir memoria"
        standardButtons: Dialog.Yes | Dialog.No

        contentItem: Text {
            text:
                "Se guardará el contenido actualmente mostrado por la radio en "
                + "M"
                + (window.pendingMemoryStoreChannel < 10 ? "0" : "")
                + window.pendingMemoryStoreChannel
                + ".\n\nEl contenido anterior de ese canal será sustituido."
            color: "#e8edf1"
            wrapMode: Text.Wrap
            padding: 12
        }

        background: Rectangle {
            color: "#25292c"
            border.color: "#d6a35d"
            border.width: 2
            radius: 5
        }

        onAccepted:
            radioController.storeDisplayedToMemory(
                window.pendingMemoryStoreChannel
            )
    }

    Dialog {
        id: clearMemoryConfirmDialog

        parent: Overlay.overlay
        modal: true
        focus: true
        title: "Borrar memoria"
        standardButtons: Dialog.Yes | Dialog.No

        contentItem: Text {
            text:
                "Se borrará definitivamente "
                + "M"
                + (window.pendingMemoryClearChannel < 10 ? "0" : "")
                + window.pendingMemoryClearChannel
                + ".\n\nEsta operación deja el canal vacío."
            color: "#ffd7d2"
            wrapMode: Text.Wrap
            padding: 12
        }

        background: Rectangle {
            color: "#2c2222"
            border.color: "#d56860"
            border.width: 2
            radius: 5
        }

        onAccepted:
            radioController.clearMemoryChannel(
                window.pendingMemoryClearChannel
            )
    }

    Popup {
        id: toneRttySettingsPopup

        parent: Overlay.overlay
        modal: false
        focus: true

        width: Math.min(790, window.width - 40)
        height: Math.min(590, window.height - 80)
        x: Math.max(20, window.width - width - 24)
        y: 72

        closePolicy:
            Popup.CloseOnEscape

        onOpened: {
            toneRttySettingsVisible = true
            radioController.refreshToneRttySettings()
        }

        onClosed:
            toneRttySettingsVisible = false

        background: Rectangle {
            radius: 5
            color: "#202326"
            border.color: "#e4a65f"
            border.width: 2
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                PopupDragTitle {
                    popupTarget:
                        toneRttySettingsPopup
                    title: "TONE / RTTY SET"
                    textColor: "#fff0db"
                    pixelSize: 13
                }

                StatusTag {
                    caption:
                        radioController.fmModeActive
                        ? "FM"
                        : "TONE CFG"
                    tagColor:
                        radioController.fmModeActive
                        ? "#477b55"
                        : "#55595c"
                }

                StatusTag {
                    caption:
                        radioController.rttyModeActive
                        ? radioController.modeText
                        : "RTTY CFG"
                    tagColor:
                        radioController.rttyModeActive
                        ? "#8a5930"
                        : "#55595c"
                }

                Item {
                    Layout.fillWidth: true
                }

                PanelButton {
                    text: "Actualizar"
                    enabled:
                        radioController.connected
                        && !radioController.busy
                    tip:
                        "Vuelve a leer los tonos y ajustes RTTY."

                    onClicked:
                        radioController
                        .refreshToneRttySettings()
                }

                PanelButton {
                    text: "Cerrar"
                    tip:
                        "Cierra TONE / RTTY SET."

                    onClicked:
                        toneRttySettingsPopup.close()
                }
            }

            Flickable {
                id: toneRttyScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight:
                    toneRttyColumn.implicitHeight
                flickableDirection:
                    Flickable.VerticalFlick
                boundsBehavior:
                    Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy:
                        toneRttyScroll.contentHeight
                        > toneRttyScroll.height
                        ? ScrollBar.AsNeeded
                        : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: toneRttyColumn

                    width:
                        toneRttyScroll.width
                        - (toneRttyScroll.contentHeight
                           > toneRttyScroll.height
                           ? 12
                           : 0)
                    spacing: 8

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 250
                        color: "#17191b"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text:
                                        "FM · REPETIDOR Y TONE SQUELCH"
                                    color: "#e8edf1"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text:
                                        radioController
                                        .repeaterToneText
                                        + " / "
                                        + radioController
                                          .toneSquelchText
                                    color: "#8de2b3"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .repeaterToneEnabled
                                        ? "TONE: ON"
                                        : "TONE: OFF"
                                    selected:
                                        radioController
                                        .repeaterToneEnabled
                                    activeColor: "#3f7658"
                                    enabled: controlsEnabled()
                                    tip:
                                        "Activa el tono de repetidor · CI-V 16 42."

                                    onClicked:
                                        radioController
                                        .setRepeaterToneEnabled(
                                            !radioController
                                             .repeaterToneEnabled
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .toneSquelchEnabled
                                        ? "TSQL: ON"
                                        : "TSQL: OFF"
                                    selected:
                                        radioController
                                        .toneSquelchEnabled
                                    activeColor: "#4f668b"
                                    enabled: controlsEnabled()
                                    tip:
                                        "Activa el tone squelch · CI-V 16 43."

                                    onClicked:
                                        radioController
                                        .setToneSquelchEnabled(
                                            !radioController
                                             .toneSquelchEnabled
                                        )
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ToneSelector {
                                    Layout.fillWidth: true
                                    caption:
                                        "TONO DE REPETIDOR"
                                    currentTenthsHz:
                                        radioController
                                        .repeaterToneTenthsHz
                                    helpText:
                                        "Frecuencia CTCSS transmitida al repetidor · CI-V 1B 00."
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setRepeaterToneTenthsHz(
                                                value
                                            )
                                        }
                                }

                                ToneSelector {
                                    Layout.fillWidth: true
                                    caption:
                                        "FRECUENCIA TSQL"
                                    currentTenthsHz:
                                        radioController
                                        .toneSquelchTenthsHz
                                    helpText:
                                        "Frecuencia CTCSS que abre el squelch · CI-V 1B 01."
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setToneSquelchTenthsHz(
                                                value
                                            )
                                        }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    radioController.fmModeActive
                                    ? "Los controles corresponden al modo FM actual."
                                    : "Los valores pueden configurarse ahora, pero TONE y TSQL se utilizan en FM."
                                color:
                                    radioController.fmModeActive
                                    ? "#aebbb4"
                                    : "#d7ae78"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 292
                        color: "#17191b"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text:
                                        "RTTY · MARK, SHIFT Y POLARIDAD"
                                    color: "#e8edf1"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text:
                                        radioController
                                        .rttyMarkFrequencyText
                                        + " · "
                                        + radioController
                                          .rttyShiftWidthText
                                    color: "#efb77e"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.preferredWidth: 72
                                    text: "MARK"
                                    color: "#cfd8dd"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: [
                                        { code: 0, name: "1275 Hz" },
                                        { code: 1, name: "1615 Hz" },
                                        { code: 2, name: "2125 Hz" }
                                    ]

                                    PanelButton {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        selected:
                                            radioController
                                            .rttyMarkFrequencyCode
                                            === modelData.code
                                        activeColor: "#8a5b2e"
                                        enabled:
                                            controlsEnabled()
                                            && (!radioController
                                                 .twinPeakEnabled
                                                || modelData.code
                                                   === 2)
                                        tip:
                                            "Frecuencia MARK de RTTY · SET > Function."

                                        onClicked:
                                            radioController
                                            .setRttyMarkFrequencyCode(
                                                modelData.code
                                            )
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.preferredWidth: 72
                                    text: "SHIFT"
                                    color: "#cfd8dd"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: [
                                        { code: 0, name: "170 Hz" },
                                        { code: 1, name: "200 Hz" },
                                        { code: 2, name: "425 Hz" }
                                    ]

                                    PanelButton {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        selected:
                                            radioController
                                            .rttyShiftWidthCode
                                            === modelData.code
                                        activeColor: "#755083"
                                        enabled:
                                            controlsEnabled()
                                            && (!radioController
                                                 .twinPeakEnabled
                                                || modelData.code
                                                   === 0)
                                        tip:
                                            "Anchura SHIFT de RTTY · SET > Function."

                                        onClicked:
                                            radioController
                                            .setRttyShiftWidthCode(
                                                modelData.code
                                            )
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .rttyKeyingReverse
                                        ? "KEYING: REVERSE"
                                        : "KEYING: NORMAL"
                                    selected:
                                        radioController
                                        .rttyKeyingReverse
                                    activeColor: "#566b8f"
                                    enabled: controlsEnabled()
                                    tip:
                                        "Polaridad de manipulación RTTY · SET > Function."

                                    onClicked:
                                        radioController
                                        .setRttyKeyingReverse(
                                            !radioController
                                             .rttyKeyingReverse
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .twinPeakEnabled
                                        ? "TWIN PEAK: ON"
                                        : "TWIN PEAK: OFF"
                                    selected:
                                        radioController
                                        .twinPeakEnabled
                                    activeColor: "#a0632d"
                                    enabled:
                                        controlsEnabled()
                                        && (radioController
                                            .twinPeakEnabled
                                            || radioController
                                               .twinPeakAvailable)
                                    tip:
                                        radioController
                                        .twinPeakAvailable
                                        ? "Activa el filtro Twin Peak · CI-V 16 4F."
                                        : "Twin Peak solo puede activarse con MARK 2125 Hz y SHIFT 170 Hz."

                                    onClicked:
                                        radioController
                                        .setTwinPeakEnabled(
                                            !radioController
                                             .twinPeakEnabled
                                        )
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    radioController
                                    .twinPeakAvailable
                                    ? "Twin Peak está disponible con la combinación actual."
                                    : "Para Twin Peak seleccione MARK 2125 Hz y SHIFT 170 Hz."
                                color:
                                    radioController
                                    .twinPeakAvailable
                                    ? "#9bdcae"
                                    : "#e3a06e"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    radioController.rttyModeActive
                                    ? "La radio está actualmente en modo RTTY."
                                    : "Estos parámetros son persistentes y se aplicarán al usar RTTY o RTTY-R."
                                color: "#aeb7bc"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text:
                            "Las frecuencias de tono se guardan por separado para TONE y TSQL. "
                            + "Los cambios solo se envían al pulsar un botón."
                        color: "#9fa8ae"
                        font.pixelSize: 9
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    Popup {
        id: cwSettingsPopup

        parent: Overlay.overlay
        modal: false
        focus: true

        width: Math.min(880, window.width - 40)
        height: Math.min(680, window.height - 80)
        x: Math.max(20, window.width - width - 24)
        y: 72

        closePolicy:
            Popup.CloseOnEscape

        onOpened: {
            cwSettingsVisible = true
            radioController.refreshCwSettings()
        }

        onClosed:
            cwSettingsVisible = false

        background: Rectangle {
            radius: 5
            color: "#202326"
            border.color: "#7ee0b4"
            border.width: 2
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                PopupDragTitle {
                    popupTarget:
                        cwSettingsPopup
                    title: "CW SET · KEYER"
                    textColor: "#dfffee"
                    pixelSize: 13
                }

                StatusTag {
                    caption:
                        radioController.cwModeActive
                        ? radioController.modeText
                        : "NO CW"
                    tagColor:
                        radioController.cwModeActive
                        ? "#2e7650"
                        : "#8a3c36"
                }

                Item {
                    Layout.fillWidth: true
                }

                PanelButton {
                    text: "Actualizar"
                    tip:
                        "Lee todos los ajustes CW y las memorias M1–M8."
                    enabled:
                        radioController.connected
                        && !radioController.busy

                    onClicked:
                        radioController.refreshCwSettings()
                }

                PanelButton {
                    text: "Cerrar"
                    tip: "Cierra CW SET."
                    onClicked:
                        cwSettingsPopup.close()
                }
            }

            Flickable {
                id: cwSettingsScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: cwSettingsColumn.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy:
                        cwSettingsScroll.contentHeight
                        > cwSettingsScroll.height
                        ? ScrollBar.AsNeeded
                        : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: cwSettingsColumn

                    width:
                        cwSettingsScroll.width
                        - (cwSettingsScroll.contentHeight
                           > cwSettingsScroll.height
                           ? 12
                           : 0)
                    spacing: 8

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 146
                        color: "#17191b"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "APF Y BREAK-IN"
                                    color: "#e8edf1"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text:
                                        "APF "
                                        + radioController.apfModeText
                                        + " · BK-IN "
                                        + radioController.breakInModeText
                                    color: "#7ee0b4"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.preferredWidth: 76
                                    text: "APF"
                                    color: "#cfd8dd"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: [
                                        { code: 0, name: "OFF" },
                                        { code: 1, name: "WIDE" },
                                        { code: 2, name: "MID" },
                                        { code: 3, name: "NAR" }
                                    ]

                                    PanelButton {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        selected:
                                            radioController.apfMode
                                            === modelData.code
                                        activeColor: "#2e8062"
                                        enabled: controlsEnabled()

                                        tip:
                                            "Audio Peak Filter "
                                            + modelData.name
                                            + " · CI-V 16 32."

                                        onClicked:
                                            radioController.setApfMode(
                                                modelData.code
                                            )
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.preferredWidth: 76
                                    text: "BREAK-IN"
                                    color: "#cfd8dd"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: [
                                        { code: 0, name: "OFF" },
                                        { code: 1, name: "SEMI" },
                                        { code: 2, name: "FULL" }
                                    ]

                                    PanelButton {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        selected:
                                            radioController.breakInMode
                                            === modelData.code
                                        activeColor:
                                            modelData.code === 0
                                            ? "#555d62"
                                            : "#8a6130"
                                        enabled: controlsEnabled()

                                        tip:
                                            "Modo Break-in CW "
                                            + modelData.name
                                            + " · CI-V 16 47."

                                        onClicked:
                                            radioController.setBreakInMode(
                                                modelData.code
                                            )
                                    }
                                }
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "APF PEAK"
                            currentValue:
                                radioController.cwApfPeakOffsetHz
                            minimumValue: -550
                            maximumValue: 550
                            stepValue: 10
                            displayFunction:
                                function(value) {
                                    return (value >= 0 ? "+" : "")
                                           + value
                                           + " Hz"
                                }
                            helpText:
                                "Desplazamiento del pico APF respecto al pitch CW · CI-V 14 05."
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setCwApfPeakOffsetHz(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "CW PITCH"
                            currentValue:
                                radioController.cwPitchHz
                            minimumValue: 300
                            maximumValue: 900
                            stepValue: 5
                            suffix: " Hz"
                            helpText:
                                "Tono CW entre 300 y 900 Hz · CI-V 14 09."
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setCwPitchHz(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "KEY SPEED"
                            currentValue:
                                radioController.cwKeySpeedWpm
                            minimumValue: 6
                            maximumValue: 48
                            stepValue: 1
                            suffix: " WPM"
                            helpText:
                                "Velocidad del manipulador, 6–48 WPM · CI-V 14 0C."
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setCwKeySpeedWpm(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "BREAK-IN DELAY"
                            currentValue:
                                radioController
                                .cwBreakInDelayTenths
                            minimumValue: 20
                            maximumValue: 130
                            stepValue: 1
                            displayFunction:
                                function(value) {
                                    return (value / 10)
                                           .toFixed(1)
                                           + " d"
                                }
                            helpText:
                                "Retardo de Semi Break-in, 2,0–13,0 d · CI-V 14 0F."
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setCwBreakInDelayTenths(value)
                                }
                        }
                    }

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 122
                        color:
                            radioController.cwModeActive
                            ? "#131d19"
                            : "#241918"
                        border.color:
                            radioController.cwModeActive
                            ? "#3d7f62"
                            : "#8a4c45"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "MENSAJE CW DIRECTO · MÁXIMO 30 CARACTERES"
                                    color: "#e8edf1"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text:
                                        directCwText.text.length + " / 30"
                                    color:
                                        directCwText.text.length <= 30
                                        ? "#8de2b3"
                                        : "#ff9b91"
                                    font.pixelSize: 9
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                TextField {
                                    id: directCwText

                                    Layout.fillWidth: true
                                    maximumLength: 30
                                    selectByMouse: true
                                    placeholderText:
                                        "CQ CQ DE EA..."
                                    color: "#e9f6f0"
                                    font.family:
                                        "DejaVu Sans Mono"
                                    font.pixelSize: 11

                                    background: Rectangle {
                                        color: "#080b0a"
                                        border.color: "#4c7561"
                                        radius: 3
                                    }
                                }

                                PanelButton {
                                    Layout.preferredWidth: 92
                                    text: "Enviar"
                                    activeColor: "#2d7a50"
                                    enabled:
                                        radioController.connected
                                        && !radioController.busy
                                        && radioController.cwModeActive
                                        && directCwText.text.length > 0

                                    tip:
                                        "Envía el texto mediante CI-V 17. Requiere CW/CW-R y Break-in activo o la radio ya en TX."

                                    onClicked:
                                        radioController.sendCwMessage(
                                            directCwText.text
                                        )
                                }

                                PanelButton {
                                    Layout.preferredWidth: 82
                                    text: "STOP"
                                    activeColor: "#a33e38"
                                    enabled:
                                        radioController.connected
                                        && !radioController.busy

                                    tip:
                                        "Detiene el mensaje CW mediante 17 FF."

                                    onClicked:
                                        radioController.stopCwMessage()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    radioController.cwModeActive
                                    ? "Use ^ para unir caracteres sin espacio. TX INHIBIT sigue teniendo prioridad."
                                    : "Seleccione el modo CW o CW-R antes de enviar."
                                color:
                                    radioController.cwModeActive
                                    ? "#aebdb5"
                                    : "#ffb4ac"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 430
                        color: "#17191b"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "MEMORIAS DEL KEYER · M1–M8"
                                    color: "#e8edf1"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                PanelButton {
                                    text: "Leer todas"
                                    enabled:
                                        radioController.connected
                                        && !radioController.busy
                                    tip:
                                        "Lee las ocho memorias mediante CI-V 1A 02."

                                    onClicked:
                                        radioController
                                        .readAllKeyerMemories()
                                }
                            }

                            Repeater {
                                model:
                                    radioController.keyerMemories

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Text {
                                        Layout.preferredWidth: 26
                                        text: modelData.name
                                        color: "#7ee0b4"
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    TextField {
                                        id: keyerMemoryEditor

                                        Layout.fillWidth: true
                                        text: modelData.text
                                        maximumLength: 70
                                        selectByMouse: true
                                        color: "#e7efeb"
                                        font.family:
                                            "DejaVu Sans Mono"
                                        font.pixelSize: 10
                                        placeholderText:
                                            "Memoria vacía"

                                        background: Rectangle {
                                            color: "#090b0a"
                                            border.color: "#485c52"
                                            radius: 2
                                        }
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 58
                                        text: "Leer"
                                        enabled:
                                            radioController.connected
                                            && !radioController.busy

                                        onClicked:
                                            radioController
                                            .readKeyerMemory(
                                                modelData.channel
                                            )
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 68
                                        text: "Guardar"
                                        activeColor: "#795d28"
                                        enabled: controlsEnabled()
                                        tip:
                                            "Sobrescribe de forma persistente "
                                            + modelData.name
                                            + ". Un campo vacío borra la memoria."

                                        onClicked:
                                            radioController
                                            .writeKeyerMemory(
                                                modelData.channel,
                                                keyerMemoryEditor.text
                                            )
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 62
                                        text: "Enviar"
                                        activeColor: "#2d7a50"
                                        enabled:
                                            radioController.connected
                                            && !radioController.busy
                                            && radioController.cwModeActive
                                            && keyerMemoryEditor.text.length > 0
                                        tip:
                                            "Envía los primeros 30 caracteres de "
                                            + modelData.name
                                            + " mediante CI-V 17."

                                        onClicked:
                                            radioController.sendCwMessage(
                                                keyerMemoryEditor.text
                                                .substring(0, 30)
                                            )
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    "Caracteres de memoria: A–Z, 0–9, espacio, / ? , . @ ^ y *. "
                                    + "* inserta el número de concurso. Guardar es una escritura persistente."
                                color: "#9fa8a3"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 346
                        color: "#17191b"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 7

                            Text {
                                text: "SET > CW-KEY SET"
                                color: "#e8edf1"
                                font.pixelSize: 11
                                font.bold: true
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 8
                                columnSpacing: 8

                                ConfigSlider {
                                    Layout.fillWidth: true
                                    caption: "SIDE TONE LEVEL"
                                    currentValue:
                                        radioController.sideToneLevel
                                    helpText:
                                        "Nivel del tono lateral · 1A 05 02 18."
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setSideToneLevel(value)
                                        }
                                }

                                ConfigSlider {
                                    Layout.fillWidth: true
                                    caption: "KEYER REPEAT"
                                    currentValue:
                                        radioController
                                        .keyerRepeatSeconds
                                    minimumValue: 1
                                    maximumValue: 60
                                    stepValue: 1
                                    suffix: " s"
                                    helpText:
                                        "Intervalo de repetición del keyer · 1A 05 02 20."
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setKeyerRepeatSeconds(value)
                                        }
                                }

                                ConfigSlider {
                                    Layout.fillWidth: true
                                    caption: "DOT / DASH RATIO"
                                    currentValue:
                                        radioController
                                        .dotDashRatioTenths
                                    minimumValue: 28
                                    maximumValue: 45
                                    stepValue: 1
                                    displayFunction:
                                        function(value) {
                                            return "1:1:"
                                                   + (value / 10)
                                                     .toFixed(1)
                                        }
                                    helpText:
                                        "Relación punto/raya de 2,8 a 4,5 · 1A 05 02 21."
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setDotDashRatioTenths(value)
                                        }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 82
                                    color: "#17191b"
                                    raised: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        spacing: 5

                                        Text {
                                            text: "RISE TIME"
                                            color: "#e8edf1"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            Repeater {
                                                model: [2, 4, 6, 8]

                                                PanelButton {
                                                    Layout.fillWidth: true
                                                    text: modelData + " ms"
                                                    selected:
                                                        radioController
                                                        .riseTimeMs
                                                        === modelData
                                                    activeColor: "#486b87"
                                                    enabled: controlsEnabled()

                                                    onClicked:
                                                        radioController
                                                        .setRiseTimeMs(
                                                            modelData
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .sideToneLimitEnabled
                                        ? "SIDE TONE LIMIT: ON"
                                        : "SIDE TONE LIMIT: OFF"
                                    selected:
                                        radioController
                                        .sideToneLimitEnabled
                                    activeColor: "#6b5b2b"
                                    enabled: controlsEnabled()

                                    onClicked:
                                        radioController
                                        .setSideToneLimitEnabled(
                                            !radioController
                                             .sideToneLimitEnabled
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController.paddleReversed
                                        ? "PADDLE: REVERSE"
                                        : "PADDLE: NORMAL"
                                    selected:
                                        radioController.paddleReversed
                                    activeColor: "#6a4f85"
                                    enabled: controlsEnabled()

                                    onClicked:
                                        radioController
                                        .setPaddleReversed(
                                            !radioController
                                             .paddleReversed
                                        )
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.preferredWidth: 76
                                    text: "KEY TYPE"
                                    color: "#cfd8dd"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: [
                                        { code: 0, name: "STRAIGHT" },
                                        { code: 1, name: "BUG" },
                                        { code: 2, name: "PADDLE" }
                                    ]

                                    PanelButton {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        selected:
                                            radioController.keyType
                                            === modelData.code
                                        activeColor: "#486b87"
                                        enabled: controlsEnabled()

                                        onClicked:
                                            radioController.setKeyType(
                                                modelData.code
                                            )
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .micUpDownKeyerEnabled
                                        ? "MIC UP/DOWN KEYER: ON"
                                        : "MIC UP/DOWN KEYER: OFF"
                                    selected:
                                        radioController
                                        .micUpDownKeyerEnabled
                                    activeColor: "#3f7658"
                                    enabled: controlsEnabled()

                                    onClicked:
                                        radioController
                                        .setMicUpDownKeyerEnabled(
                                            !radioController
                                             .micUpDownKeyerEnabled
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .cwDecodeDisplayEnabled
                                        ? "CW DECODE DISPLAY: ON"
                                        : "CW DECODE DISPLAY: OFF"
                                    selected:
                                        radioController
                                        .cwDecodeDisplayEnabled
                                    activeColor: "#356f82"
                                    enabled: controlsEnabled()

                                    onClicked:
                                        radioController
                                        .setCwDecodeDisplayEnabled(
                                            !radioController
                                             .cwDecodeDisplayEnabled
                                        )
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text:
                            "Los valores se leen al abrir CW SET. "
                            + "Los cambios solo se envían cuando se pulsa un botón o se libera un deslizador."
                        color: "#9fa8ae"
                        font.pixelSize: 9
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    Popup {
        id: txSettingsPopup

        parent: Overlay.overlay
        modal: false
        focus: true

        width: Math.min(760, window.width - 40)
        height: Math.min(590, window.height - 80)
        x: Math.max(20, window.width - width - 24)
        y: 72

        closePolicy:
            Popup.CloseOnEscape

        onOpened: {
            txSettingsVisible = true
            radioController.refreshTxAudioSettings()
        }

        onClosed:
            txSettingsVisible = false

        background: Rectangle {
            radius: 5
            color: "#202326"
            border.color: "#6ecdf5"
            border.width: 2
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                PopupDragTitle {
                    popupTarget:
                        txSettingsPopup
                    title: "CONFIGURACIÓN TX / AUDIO"
                    textColor: "#dff5ff"
                    pixelSize: 13
                }

                Item { Layout.fillWidth: true }

                PanelButton {
                    text: "Actualizar"
                    tip: "Vuelve a leer los ajustes TX/AUDIO de la radio."
                    enabled: radioController.connected
                    onClicked: radioController.refreshTxAudioSettings()
                }

                PanelButton {
                    text: "Cerrar"
                    tip: "Cierra la configuración TX/AUDIO."
                    onClicked:
                        txSettingsPopup.close()
                }
            }

            Flickable {
                id: txSettingsScroll

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: txSettingsColumn.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy:
                        txSettingsScroll.contentHeight
                        > txSettingsScroll.height
                        ? ScrollBar.AsNeeded
                        : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: txSettingsColumn

                    width:
                        txSettingsScroll.width
                        - (txSettingsScroll.contentHeight
                           > txSettingsScroll.height
                           ? 12 : 0)
                    spacing: 8

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 72
                        color: "#20191a"
                        raised: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 10
                            ColumnLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "PROTECCIÓN TX DEL PROGRAMA"
                                    color: "#ffc2b8"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Corta TX si SWR > 2,5 o al vencer el tiempo máximo. Solo afecta al PTT iniciado desde este programa."
                                    color: "#b9c1c5"
                                    font.pixelSize: 9
                                    wrapMode: Text.Wrap
                                }
                            }
                            Text { text: "Tiempo máximo"; color: "#d9e0e4"; font.pixelSize: 10 }
                            SpinBox {
                                from: 5
                                to: 3600
                                stepSize: 5
                                editable: true
                                value: radioController.txSafetyTimeoutSeconds
                                Layout.preferredWidth: 110
                                onValueModified: radioController.txSafetyTimeoutSeconds = value
                            }
                            Text { text: "s"; color: "#d9e0e4" }
                        }
                    }

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 92
                        color: "#17191b"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Text {
                                text: "FUNCIONES DE TRANSMISIÓN"
                                color: "#e8edf1"
                                font.pixelSize: 11
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController
                                        .speechCompressorEnabled
                                        ? "COMP: ON" : "COMP: OFF"
                                    selected:
                                        radioController
                                        .speechCompressorEnabled
                                    activeColor: "#8c5b20"
                                    enabled: controlsEnabled()
                                    onClicked:
                                        radioController
                                        .setSpeechCompressorEnabled(
                                            !radioController
                                             .speechCompressorEnabled
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController.monitorEnabled
                                        ? "MONITOR: ON" : "MONITOR: OFF"
                                    selected: radioController.monitorEnabled
                                    activeColor: "#316b8f"
                                    enabled: controlsEnabled()
                                    onClicked:
                                        radioController.setMonitorEnabled(
                                            !radioController.monitorEnabled
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    text:
                                        radioController.voxEnabled
                                        ? "VOX: ON" : "VOX: OFF"
                                    selected: radioController.voxEnabled
                                    activeColor: "#3e7b4d"
                                    enabled: controlsEnabled()
                                    onClicked:
                                        radioController.setVoxEnabled(
                                            !radioController.voxEnabled
                                        )
                                }
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "MIC GAIN"
                            currentValue: radioController.microphoneGain
                            helpText: "Ganancia de micrófono · CI-V 14 0B."
                            applyFunction:
                                function(value) {
                                    radioController.setMicrophoneGain(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "COMP LEVEL"
                            currentValue:
                                radioController.speechCompressorLevel
                            maximumValue: 10
                            suffix: " / 10"
                            helpText:
                                "Nivel del compresor de voz · CI-V 14 0E."
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setSpeechCompressorLevel(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "MONITOR LEVEL"
                            currentValue: radioController.monitorLevel
                            helpText:
                                "Nivel del audio monitorizado · CI-V 14 15."
                            applyFunction:
                                function(value) {
                                    radioController.setMonitorLevel(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "VOX GAIN"
                            currentValue: radioController.voxGain
                            helpText: "Sensibilidad VOX · CI-V 14 16."
                            applyFunction:
                                function(value) {
                                    radioController.setVoxGain(value)
                                }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            caption: "ANTI-VOX"
                            currentValue: radioController.antiVoxGain
                            helpText:
                                "Anti-VOX: valores altos reducen la sensibilidad al audio recibido · CI-V 14 17."
                            applyFunction:
                                function(value) {
                                    radioController.setAntiVoxGain(value)
                                }
                        }

                        FrameBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 82
                            color: "#17191b"
                            raised: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 7
                                spacing: 5

                                Text {
                                    text: "SSB TX FILTER"
                                    color: "#e8edf1"
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5

                                    Repeater {
                                        model: [
                                            { width: 0, name: "WIDE" },
                                            { width: 1, name: "MID" },
                                            { width: 2, name: "NAR" }
                                        ]

                                        PanelButton {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            selected:
                                                radioController.txFilterWidth
                                                === modelData.width
                                            activeColor: "#2f72b9"
                                            enabled: controlsEnabled()
                                            onClicked:
                                                radioController
                                                .setTxFilterWidth(
                                                    modelData.width
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    }

                    FrameBox {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 118
                        color:
                            radioController.txInhibitEnabled
                            ? "#32191a" : "#17191b"
                        border.color:
                            radioController.txInhibitEnabled
                            ? "#e36d6d" : "#5f5f5f"
                        raised: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "SEGURIDAD DE TRANSMISIÓN"
                                    color: "#e8edf1"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                PanelButton {
                                    Layout.preferredWidth: 170
                                    text:
                                        radioController.txInhibitEnabled
                                        ? "TX INHIBIT: ON"
                                        : "TX INHIBIT: OFF"
                                    selected:
                                        radioController.txInhibitEnabled
                                    activeColor: "#a12f2f"
                                    enabled: controlsEnabled()
                                    onClicked:
                                        radioController
                                        .setTxInhibitEnabled(
                                            !radioController
                                             .txInhibitEnabled
                                        )
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    radioController.txInhibitEnabled
                                    ? "La radio tiene bloqueada la transmisión. El PTT del programa también queda bloqueado."
                                    : "La transmisión está permitida. Active TX INHIBIT para impedir cualquier TX accidental."
                                color:
                                    radioController.txInhibitEnabled
                                    ? "#ffb3b3" : "#bfc8ce"
                                font.pixelSize: 10
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text:
                            "Estos controles modifican valores reales de la radio. "
                            + "No se aplican cambios automáticamente al abrir la ventana."
                        color: "#9fa8ae"
                        font.pixelSize: 9
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    Window {
        id: superCompactWindow

        property bool returningToCompact: false

        visible: superCompactVisible
        width: 330
        height: 64
        minimumWidth: 240
        minimumHeight: 52
        // Qt.Window hace que SUPER tenga su propia entrada en la barra de
        // tareas; Qt.Tool la ocultaba del selector de ventanas.
        flags: Qt.Window | Qt.FramelessWindowHint
               | (applicationLauncher.compactAlwaysOnTop
                  ? Qt.WindowStaysOnTopHint : 0)
        color: "#071014"
        title: "IC-7300MK2"

        onXChanged: {
            if (visible)
                applicationLauncher.superWindowX = Math.round(x)
        }
        onYChanged: {
            if (visible)
                applicationLauncher.superWindowY = Math.round(y)
        }

        onClosing: function(close) {
            if (returningToCompact) {
                returningToCompact = false
                return
            }
            if (!applicationClosing && !returningToCompact) {
                close.accepted = false
                setSuperCompactMode(false)
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "#071014"
            border.color: "#347e98"
            radius: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: radioController.frequencyMhzText
                    color: "#77dcff"
                    font.family: "DejaVu Sans Mono"
                    font.pixelSize: 25
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    text: radioController.modeText
                          + (radioController.dataMode ? "-D" : "")
                    color: "#ffd27a"
                    font.pixelSize: 20
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: setCompactMode(true)
            }
        }
    }

    Window {
        id: compactWindow

        property bool returningToFullView: false
        property bool adjustingSize: false
        readonly property real baseWidth: 700
        readonly property real baseHeight: 112
        readonly property real baseAspect: baseWidth / baseHeight

        visible: compactVisible
        width: baseWidth
        height: baseHeight
        minimumWidth: baseWidth
        minimumHeight: baseHeight
        flags: Qt.Tool | Qt.FramelessWindowHint
               | (applicationLauncher.compactAlwaysOnTop
                  ? Qt.WindowStaysOnTopHint : 0)
        color: "#292d30"
        title: "IC-7300MK2 · Control compacto"

        onXChanged: {
            if (visible)
                applicationLauncher.compactWindowX = Math.round(x)
        }
        onYChanged: {
            if (visible)
                applicationLauncher.compactWindowY = Math.round(y)
        }
        onWidthChanged: {
            if (adjustingSize) return
            adjustingSize = true
            if (width < baseWidth) width = baseWidth
            height = Math.round(width / baseAspect)
            adjustingSize = false
            if (visible)
                applicationLauncher.compactWindowWidth = Math.round(width)
        }
        onHeightChanged: {
            if (adjustingSize) return
            adjustingSize = true
            // El alto nunca gobierna el tamaño: se deriva siempre del ancho.
            // Esto impide cualquier escalado vertical independiente.
            height = Math.round(width / baseAspect)
            adjustingSize = false
        }

        onClosing: function(close) {
            if (returningToFullView) {
                returningToFullView = false
                return
            }
            if (!applicationClosing && !returningToFullView) {
                compactVisible = false
                applicationLauncher.compactModePreferred = false
                Qt.callLater(function() {
                    window.showNormal()
                    window.raise()
                    window.requestActivate()
                })
            }
        }

        Rectangle {
            width: compactWindow.baseWidth - 8
            height: compactWindow.baseHeight - 8
            anchors.centerIn: parent
            scale: compactWindow.width / compactWindow.baseWidth
            transformOrigin: Item.Center
            color: "#303438"
            border.color: "#5886ad"
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 7
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    spacing: 6

                    Text {
                        text: "⠿"
                        color: "#8fa7b5"
                        font.pixelSize: 18
                        ToolTip.visible: compactDragArea.containsMouse
                        ToolTip.text: "Arrastra para mover"
                        MouseArea {
                            id: compactDragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onPressed: compactWindow.startSystemMove()
                        }
                    }

                    PanelButton {
                        text: "⚑"
                        selected: applicationLauncher.compactAlwaysOnTop
                        activeColor: "#75612e"
                        Layout.preferredWidth: 42
                        textPixelSize: 16
                        tip: "Activa o desactiva que la ventana permanezca siempre visible."
                        onClicked: {
                            applicationLauncher.compactAlwaysOnTop =
                                !applicationLauncher.compactAlwaysOnTop
                            Qt.callLater(function() {
                                compactWindow.show()
                                compactWindow.raise()
                                compactWindow.requestActivate()
                            })
                        }
                    }

                    PanelButton {
                        text: "⏻"
                        selected: radioController.connected || applicationLauncher.lanConnected
                        activeColor: "#397a52"
                        Layout.preferredWidth: 38
                        textPixelSize: 17
                        contentItem: Text {
                            anchors.fill: parent
                            text: "⏻"
                            color: "#f1f1f1"
                            font.pixelSize: 17
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        tip: (radioController.connected || applicationLauncher.lanConnected)
                             ? "Desconectar de la radio"
                             : "Conectar con la radio"
                        onClicked: (radioController.connected || applicationLauncher.lanConnected)
                                   ? (radioController.connected ? radioController.disconnectRadio() : applicationLauncher.disconnectLanConnection())
                                   : (applicationLauncher.lanConnectionEnabled
                                      ? applicationLauncher.testLanConnection()
                                      : radioController.connectRadio())
                    }
                    PanelButton {
                        text: ""
                        iconName: "browser"
                        Layout.preferredWidth: 38
                        tip: "Abrir el panel remoto en el navegador"
                        onClicked: {
                            if ((!remoteServer.running && !remoteServer.start())) return
                            Qt.openUrlExternally(remoteServer.localTestUrl)
                        }
                    }
                    PanelButton {
                        text: radioController.transmitting ? "RX" : "PTT"
                        selected: radioController.transmitting
                        activeColor: "#a33d3d"
                        enabled: radioController.connected
                                 && (!radioController.transmitting
                                     || radioController.pttOwned)
                        Layout.preferredWidth: 54
                        tip: "PTT momentáneo. Mantén pulsado para transmitir."
                        onPressed: radioController.setTransmit(true)
                        onReleased: radioController.setTransmit(false)
                        onCanceled: radioController.setTransmit(false)
                    }
                    PanelButton {
                        text: "TUNE"
                        activeColor: "#8a6330"
                        Layout.preferredWidth: 54
                        enabled: controlsEnabled()
                        tip: "Inicia el ciclo de ajuste del acoplador."
                        onClicked: radioController.startTuner()
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 75
                        Layout.preferredHeight: 28
                        color: "#071014"
                        border.color: "#347e98"
                        radius: 3
                        clip: true
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 6
                            text: radioController.frequencyMhzText
                                  + "  " + radioController.modeText
                                  + (radioController.dataMode ? "-D" : "")
                            color: "#77dcff"
                            font.family: "DejaVu Sans Mono"
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideLeft
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    RowLayout {
                        spacing: 3
                        PanelButton {
                            text: "◈"
                            selected: superCompactVisible
                            activeColor: "#61517d"
                            Layout.preferredWidth: 48
                            textPixelSize: 13
                            onClicked: setSuperCompactMode(true)
                            tip: "Vista SUPER compacta"
                        }
                        PanelButton {
                            text: "□"
                            Layout.preferredWidth: 70
                            textPixelSize: 15
                            activeColor: "#61517d"
                            onClicked: setCompactMode(false)
                            tip: "Vista completa"
                        }
                        PanelButton {
                            text: "×"
                            Layout.preferredWidth: 50
                            textPixelSize: 17
                            activeColor: "#8b3535"
                            tip: "Cierra completamente el programa."
                            onClicked: window.close()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    spacing: 8

                GridLayout {
                    // Los modos ocupan menos ancho para dejar más espacio
                    // a las bandas, cuyos nombres necesitan más aire.
                    Layout.preferredWidth: 225
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: 225
                    Layout.fillHeight: true
                    columns: 5
                    rowSpacing: 3
                    columnSpacing: 4

                    Repeater {
                        model: modeNames
                        PanelButton {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 24
                            text: modelData
                            textPixelSize: 9
                            selected: modelData === "SSTV"
                                      ? applicationLauncher.qsstvRunning
                                      : modelData === "FT8/FT4"
                                      ? applicationLauncher.decodiumRunning
                                      : (modelData === "RTTY" || modelData === "RTTY-R")
                                      ? (applicationLauncher.fldigiRunning
                                         && externalDigitalMode === modelData)
                                      : (applicationLauncher.lanConnected
                                         ? applicationLauncher.lanMode === modelData
                                         : radioController.modeText === modelData)
                            activeColor: modelData === "SSTV" ? "#86652f"
                                         : modelData === "FT8/FT4" ? "#28789a"
                                         : "#2f72b9"
                            enabled: controlsEnabled()
                            onClicked: activateCompactMode(modelData)
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 68
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    spacing: 3

                ComboBox {
                    id: compactExtraDigitalModeBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    font.pixelSize: 9
                    model: ["OTROS…", "PSK", "OLIVIA", "WEFAX", "JS8"]

                    onActivated: function(index) {
                        if (index === 0) return
                        if (index === 1 || index === 2 || index === 3) {
                            const targetMode = index === 1 ? "PSK" : index === 2 ? "OLIVIA" : "WEFAX"
                            if (applicationLauncher.fldigiRunning
                                    && externalDigitalMode === targetMode) {
                                stopExternalProgramsAndRestore()
                                return
                            }
                            prepareExternalProgram("fldigi")
                            externalDigitalMode = targetMode
                            radioController.setFrequency(String(index === 1
                                ? applicationLauncher.pskFrequencyHz
                                : index === 2 ? applicationLauncher.oliviaFrequencyHz
                                : applicationLauncher.wefaxFrequencyHz))
                            radioController.setOperatingModeState("USB", true, 1)
                            applicationLauncher.launchFldigi()
                            applicationLauncher.setFldigiMode(
                                index === 1 ? "BPSK31" : index === 2 ? "OLIVIA-8/250" : "WEFAX576")
                            applicationLauncher.setFldigiReverse(false)
                        } else {
                            if (applicationLauncher.js8callRunning) {
                                stopExternalProgramsAndRestore()
                                return
                            }
                            prepareExternalProgram("js8call")
                            externalDigitalMode = "JS8"
                            radioController.setFrequency(
                                String(applicationLauncher.js8FrequencyHz))
                            radioController.setOperatingModeState("USB", true, 1)
                            applicationLauncher.launchJs8call()
                        }
                    }
                }

                PanelButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    text: "DATA"
                    selected: applicationLauncher.lanConnected
                              ? applicationLauncher.lanDataEnabled
                              : radioController.dataMode
                    activeColor: "#2d7894"
                    textPixelSize: 9
                    enabled: controlsEnabled()
                    tip: "Activa o desactiva DATA en el modo actual."
                    onClicked: applicationLauncher.lanConnected
                               ? applicationLauncher.setLanDataEnabled(
                                     !applicationLauncher.lanDataEnabled,
                                     radioController.modeText)
                               : radioController.setDataEnabled(
                                     !radioController.dataMode)
                }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    columns: 6
                    rowSpacing: 3
                    columnSpacing: 3
                    Repeater {
                        model: bandDefinitions
                        PanelButton {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 24
                            text: modelData.name
                            textPixelSize: 10
                            selected: currentBandName === modelData.name
                            activeColor: "#386d84"
                            enabled: controlsEnabled()
                            tip: modelData.label
                            onClicked: selectBand(index)
                        }
                    }
                }
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 18
            height: 18
            color: resizeMouse.containsMouse ? "#52768a" : "#344750"
            opacity: 0.9

            Text {
                anchors.centerIn: parent
                text: "◢"
                color: "#d6e7ef"
                font.pixelSize: 12
            }

            MouseArea {
                id: resizeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeFDiagCursor
                onPressed: compactWindow.startSystemResize(
                               Qt.RightEdge | Qt.BottomEdge)
            }
        }
    }

    Popup {
        id: digitalFrequencyPopup

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 430
        height: 430
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
                     | Popup.CloseOnPressOutside

        property string errorText: ""

        function mhzText(frequencyHz) {
            return (Number(frequencyHz) / 1000000).toFixed(6)
        }

        function frequencyHz(field) {
            return Math.round(Number(field.text.replace(",", "."))
                              * 1000000)
        }

        function syncFields() {
            rttyFrequencyField.text = mhzText(applicationLauncher.rttyFrequencyHz)
            cwFrequencyField.text = mhzText(applicationLauncher.cwFrequencyHz)
            ftFrequencyField.text = mhzText(applicationLauncher.ftFrequencyHz)
            sstvFrequencyField.text = mhzText(applicationLauncher.sstvFrequencyHz)
            pskFrequencyField.text = mhzText(applicationLauncher.pskFrequencyHz)
            oliviaFrequencyField.text = mhzText(applicationLauncher.oliviaFrequencyHz)
            js8FrequencyField.text = mhzText(applicationLauncher.js8FrequencyHz)
            wefaxFrequencyField.text = mhzText(applicationLauncher.wefaxFrequencyHz)
            errorText = ""
        }

        function applyFields() {
            const rtty = frequencyHz(rttyFrequencyField)
            const cw = frequencyHz(cwFrequencyField)
            const ft = frequencyHz(ftFrequencyField)
            const sstv = frequencyHz(sstvFrequencyField)
            const psk = frequencyHz(pskFrequencyField)
            const olivia = frequencyHz(oliviaFrequencyField)
            const js8 = frequencyHz(js8FrequencyField)
            const wefax = frequencyHz(wefaxFrequencyField)
            if (![rtty, cw, ft, sstv, psk, olivia, js8, wefax].every(function(value) {
                    return isFinite(value) && value >= 100000
                           && value <= 60000000
                })) {
                errorText = "Introduce frecuencias entre 0,100 y 60,000 MHz."
                return
            }
            applicationLauncher.rttyFrequencyHz = rtty
            applicationLauncher.cwFrequencyHz = cw
            applicationLauncher.ftFrequencyHz = ft
            applicationLauncher.sstvFrequencyHz = sstv
            applicationLauncher.pskFrequencyHz = psk
            applicationLauncher.oliviaFrequencyHz = olivia
            applicationLauncher.js8FrequencyHz = js8
            applicationLauncher.wefaxFrequencyHz = wefax
            close()
        }

        onOpened: syncFields()

        background: Rectangle {
            color: "#202326"
            border.color: "#e5bb52"
            border.width: 1
            radius: 4
        }

        contentItem: ColumnLayout {
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "FRECUENCIAS DE MODOS DIGITALES"
                color: "#fff0bd"
                font.pixelSize: 14
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8

                Text { text: "RTTY / RTTY-R"; color: "#d9e0e4" }
                TextField { id: rttyFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "CW / CW-R"; color: "#d9e0e4" }
                TextField { id: cwFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "FT8 / FT4"; color: "#d9e0e4" }
                TextField { id: ftFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "SSTV"; color: "#d9e0e4" }
                TextField { id: sstvFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "PSK"; color: "#d9e0e4" }
                TextField { id: pskFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "Olivia"; color: "#d9e0e4" }
                TextField { id: oliviaFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "JS8"; color: "#d9e0e4" }
                TextField { id: js8FrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
                Text { text: "WEFAX"; color: "#d9e0e4" }
                TextField { id: wefaxFrequencyField; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                Text { text: "MHz"; color: "#aeb8bd" }
            }

            Text {
                Layout.fillWidth: true
                text: digitalFrequencyPopup.errorText
                color: "#f0a0a0"
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                PanelButton { text: "CANCELAR"; Layout.preferredWidth: 110; onClicked: digitalFrequencyPopup.close() }
                PanelButton { text: "GUARDAR"; Layout.preferredWidth: 110; activeColor: "#3d7650"; onClicked: digitalFrequencyPopup.applyFields() }
            }
        }
    }

    Window {
        id: settingsPopup

        property int sectionIndex: 0

        transientParent: window
        visible: settingsVisible
        width: 940
        height: 760
        minimumWidth: 820
        minimumHeight: 640
        flags: Qt.Tool
        color: "#202326"
        title: "Configuración avanzada · IC-7300MK2"

        function modelIndex(model, value) {
            for (let index = 0;
                 index < model.length;
                 ++index) {
                if (String(model[index])
                        === String(value)) {
                    return index
                }
            }

            return -1
        }

        function hexByte(value) {
            let text =
                Number(value)
                .toString(16)
                .toUpperCase()

            return text.length < 2
                   ? "0" + text
                   : text
        }

        function syncConnectionForm() {
            const configured =
                radioController.configuredPort.length > 0
                ? radioController.configuredPort
                : "AUTO"

            let portIndex =
                modelIndex(
                    radioController.serialPortChoices,
                    configured
                )
            connectionPortBox.currentIndex =
                portIndex >= 0 ? portIndex : 0

            lanHostField.text = applicationLauncher.lanHost
            lanUserField.text = applicationLauncher.lanUser
            lanPasswordField.text = applicationLauncher.lanPassword

            let baudIndex =
                modelIndex(
                    connectionBaudBox.model,
                    String(
                        radioController
                        .configuredBaudRate
                    )
                )
            connectionBaudBox.currentIndex =
                baudIndex >= 0 ? baudIndex : 4

            radioAddressField.text =
                hexByte(
                    radioController.civRadioAddress
                )
            controllerAddressField.text =
                hexByte(
                    radioController
                    .civControllerAddress
                )
            connectionAutoCheck.checked =
                radioController.autoConnectEnabled
            connectionReconnectCheck.checked =
                radioController.autoReconnectEnabled
            connectionPollSpin.value =
                radioController.pollIntervalMs
            connectionTimeoutSpin.value =
                radioController.responseTimeoutMs
        }

        function applyConnectionForm() {
            applicationLauncher.lanHost = lanHostField.text
            applicationLauncher.lanUser = lanUserField.text
            applicationLauncher.lanPassword = lanPasswordField.text
            applicationLauncher.lanConnectionEnabled = connectionTypeBox.currentIndex === 1
            const radioAddress =
                parseInt(
                    radioAddressField.text,
                    16
                )
            const controllerAddress =
                parseInt(
                    controllerAddressField.text,
                    16
                )

            radioController.applyConnectionSettings({
                "port":
                    connectionPortBox.currentText,
                "baudRate":
                    Number(
                        connectionBaudBox.currentText
                    ),
                "radioAddress":
                    radioAddress,
                "controllerAddress":
                    controllerAddress,
                "autoConnect":
                    connectionAutoCheck.checked,
                "autoReconnect":
                    connectionReconnectCheck.checked,
                "pollIntervalMs":
                    connectionPollSpin.value,
                "responseTimeoutMs":
                    connectionTimeoutSpin.value,
                "reconnectNow": true
            })
        }

        onVisibleChanged: {
            if (visible) {
                settingsVisible = true
                radioController
                .refreshConnectionDevices()
                radioController
                .refreshCapabilities()
                syncConnectionForm()
            } else {
                settingsVisible = false
            }
        }

        onClosing:
            settingsVisible = false

        Connections {
            target: radioController

            function onConnectionSettingsChanged() {
                if (settingsPopup.visible) {
                    settingsPopup
                    .syncConnectionForm()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#202326"
            border.color: "#e5bb52"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34

                    Text {
                        text: "CONFIGURACIÓN AVANZADA"
                        color: "#fff0bd"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text:
                            radioController.connected
                            ? "CONECTADO · "
                              + radioController.portName
                            : "DESCONECTADO"
                        color:
                            radioController.connected
                            ? "#8de29a"
                            : "#e6a0a0"
                        font.pixelSize: 10
                        font.bold: true
                        horizontalAlignment:
                            Text.AlignRight
                        elide:
                            Text.ElideMiddle
                    }

                    PanelButton {
                        Layout.preferredWidth: 74
                        text: "CERRAR"
                        onClicked:
                            settingsPopup.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#5c6062"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    FrameBox {
                        Layout.preferredWidth: 176
                        Layout.minimumWidth: 176
                        Layout.maximumWidth: 176
                        Layout.fillHeight: true
                        color: "#171a1c"
                        border.color: "#50595e"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: "SECCIONES"
                                color: "#d5dde1"
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment:
                                    Text.AlignHCenter
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "CONEXIÓN CI-V"
                                selected:
                                    settingsPopup
                                    .sectionIndex === 0
                                activeColor: "#386d84"
                                onClicked:
                                    settingsPopup
                                    .sectionIndex = 0
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "CONECTORES"
                                selected:
                                    settingsPopup
                                    .sectionIndex === 1
                                activeColor: "#4f795d"
                                onClicked:
                                    settingsPopup
                                    .sectionIndex = 1
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "RADIO / CAP."
                                selected:
                                    settingsPopup
                                    .sectionIndex === 2
                                activeColor: "#7b6538"
                                onClicked:
                                    settingsPopup
                                    .sectionIndex = 2
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "DIAGNÓSTICO"
                                selected:
                                    settingsPopup
                                    .sectionIndex === 3
                                activeColor: "#66527e"
                                onClicked:
                                    settingsPopup
                                    .sectionIndex = 3
                            }

                            Item {
                                Layout.fillHeight: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    "Los cambios de conexión se guardan "
                                    + "en la configuración del usuario."
                                color: "#909ba0"
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                                horizontalAlignment:
                                    Text.AlignHCenter
                            }
                        }
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex:
                            settingsPopup.sectionIndex

                        ScrollView {
                            id: connectionScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width:
                                    connectionScroll.availableWidth
                                spacing: 8

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 78
                                    color: "#171a1c"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 12

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                text: "ESTADO DE CONEXIÓN"
                                                color: "#dce3e7"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text:
                                                    applicationLauncher.lanConnected
                                                    ? "Conectado - Recepción (LAN)"
                                                    : radioController.status
                                                color:
                                                    (radioController.connected || applicationLauncher.lanConnected)
                                                    ? "#8de29a"
                                                    : "#e6a0a0"
                                                font.pixelSize: 12
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text:
                                                    ((applicationLauncher.lanConnected
                                                      ? "LAN conectado"
                                                      : (applicationLauncher.lanConnectionEnabled
                                                         ? "LAN IC-7300MK2"
                                                         : "USB / CI-V")))
                                                    + " · " + radioController.connectionSettingsSummary
                                                color: (radioController.connected || applicationLauncher.lanConnected)
                                                       ? "#8de29a" : "#e6a0a0"
                                                font.pixelSize: 9
                                                elide: Text.ElideMiddle
                                            }
                                        }

                                        PanelButton {
                                            Layout.preferredWidth: 116
                                            text:
                                                (radioController.connected || applicationLauncher.lanConnected)
                                                ? "DESCONECTAR"
                                                : "CONECTAR"
                                            selected:
                                                (radioController.connected || applicationLauncher.lanConnected)
                                            activeColor: "#3d7650"

                                            onClicked:
                                                (radioController.connected || applicationLauncher.lanConnected)
                                                ? (radioController.connected ? radioController.disconnectRadio() : applicationLauncher.disconnectLanConnection())
                                                : (applicationLauncher.lanConnectionEnabled
                                                   ? applicationLauncher.testLanConnection()
                                                   : radioController.connectRadio())
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 390
                                    color: "#171a1c"

                                    GridLayout {
                                        anchors.fill: parent
                                        anchors.margins: 9
                                        columns: 4
                                        rowSpacing: 7
                                        columnSpacing: 8

                                        Text {
                                            text: "Conexión"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                        ComboBox {
                                            id: connectionTypeBox
                                            Layout.columnSpan: 3
                                            Layout.fillWidth: true
                                            model: ["USB / CI-V", "LAN IC-7300MK2"]
                                            currentIndex: applicationLauncher.lanConnectionEnabled ? 1 : 0
                                            onCurrentIndexChanged: {
                                                const useLan = currentIndex === 1
                                                applicationLauncher.lanConnectionEnabled = useLan
                                                if (useLan && radioController.connected)
                                                    radioController.disconnectRadio()
                                            }
                                            onActivated: {
                                                applicationLauncher.lanConnectionEnabled = currentIndex === 1
                                            }
                                            onCurrentTextChanged: {
                                                if (currentText.length > 0)
                                                    applicationLauncher.lanConnectionEnabled = currentIndex === 1
                                            }
                                            ToolTip.visible: hovered
                                            ToolTip.text: "Selecciona el transporte de comunicación. LAN quedará activo al completar el controlador LAN."
                                        }

                                        Text {
                                            text: "Puerto"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        ComboBox {
                                            id: connectionPortBox
                                            Layout.columnSpan: 3
                                            Layout.fillWidth: true
                                            enabled: connectionTypeBox.currentIndex === 0
                                            model:
                                                radioController
                                                .serialPortChoices

                                            ToolTip.visible: hovered
                                            ToolTip.text:
                                                currentText === "AUTO"
                                                ? "AUTO prioriza USB (B) / if02."
                                                : "Puerto serie seleccionado manualmente."
                                        }

                                        Text { text: "LAN IP / host"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true }
                                        TextField { id: lanHostField; Layout.columnSpan: 3; Layout.fillWidth: true; enabled: connectionTypeBox.currentIndex === 1; placeholderText: "192.168.1.154 o nombre DHCP" }
                                        Text { text: "Usuario LAN"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true }
                                        TextField { id: lanUserField; Layout.columnSpan: 3; Layout.fillWidth: true; enabled: connectionTypeBox.currentIndex === 1 }
                                        Text { text: "Contraseña LAN"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true }
                                        RowLayout {
                                            Layout.columnSpan: 3
                                            Layout.fillWidth: true
                                            spacing: 6
                                            TextField { id: lanPasswordField; Layout.fillWidth: true; enabled: connectionTypeBox.currentIndex === 1; echoMode: lanPasswordVisible.checked ? TextInput.Normal : TextInput.Password }
                                            CheckBox { id: lanPasswordVisible; text: "Mostrar"; enabled: connectionTypeBox.currentIndex === 1; font.pixelSize: 10; palette.text: "#d9e0e4" }
                                        }
                                        Text {
                                            text: "Velocidad"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        ComboBox {
                                            id: connectionBaudBox
                                            Layout.preferredWidth: 130
                                            enabled: connectionTypeBox.currentIndex === 0
                                            model: [
                                                "9600",
                                                "19200",
                                                "38400",
                                                "57600",
                                                "115200"
                                            ]
                                        }

                                        Text {
                                            text: "Radio CI-V"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        TextField {
                                            id: radioAddressField
                                            enabled: connectionTypeBox.currentIndex === 0
                                            Layout.preferredWidth: 84
                                            horizontalAlignment:
                                                Text.AlignHCenter
                                            maximumLength: 2
                                            placeholderText: "94"
                                            font.family:
                                                "DejaVu Sans Mono"
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Controlador"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        TextField {
                                            id: controllerAddressField
                                            enabled: connectionTypeBox.currentIndex === 0
                                            Layout.preferredWidth: 84
                                            horizontalAlignment:
                                                Text.AlignHCenter
                                            maximumLength: 2
                                            placeholderText: "E0"
                                            font.family:
                                                "DejaVu Sans Mono"
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Polling"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        SpinBox {
                                            id: connectionPollSpin
                                            Layout.preferredWidth: 130
                                            from: 40
                                            to: 500
                                            stepSize: 10
                                            editable: true
                                        }

                                        Text {
                                            text: "Timeout"
                                            color: "#d9e0e4"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        SpinBox {
                                            id: connectionTimeoutSpin
                                            Layout.preferredWidth: 130
                                            from: 250
                                            to: 3000
                                            stepSize: 50
                                            editable: true
                                        }

                                        CheckBox {
                                            id: connectionAutoCheck
                                            Layout.columnSpan: 2
                                            Layout.fillWidth: true
                                            text: "Auto-conectar al iniciar"
                                            font.pixelSize: 10
                                            palette.text: "#d9e0e4"
                                            indicator: Rectangle {
                                                implicitWidth: 16; implicitHeight: 16
                                                x: 0; y: (parent.height - height) / 2
                                                color: "#050505"; border.color: "#8aa0aa"; radius: 2
                                                Text { anchors.centerIn: parent; text: "✓"; visible: connectionAutoCheck.checked; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
                                            }
                                            contentItem: Text {
                                                text: connectionAutoCheck.text
                                                color: "#d9e0e4"
                                                font.pixelSize: 12
                                                anchors.left: parent.left
                                                anchors.leftMargin: 30
                                                leftPadding: 0
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            onToggled: radioController.setAutoConnectPreference(checked)
                                        }

                                        CheckBox {
                                            id: connectionReconnectCheck
                                            Layout.columnSpan: 2
                                            Layout.fillWidth: true
                                            text: "Reconectar tras error"
                                            font.pixelSize: 10
                                            palette.text: "#d9e0e4"
                                            indicator: Rectangle {
                                                implicitWidth: 16; implicitHeight: 16
                                                x: 0; y: (parent.height - height) / 2
                                                color: "#050505"; border.color: "#8aa0aa"; radius: 2
                                                Text { anchors.centerIn: parent; text: "✓"; visible: connectionReconnectCheck.checked; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
                                            }
                                            contentItem: Text {
                                                text: connectionReconnectCheck.text
                                                color: "#d9e0e4"
                                                font.pixelSize: 12
                                                anchors.left: parent.left
                                                anchors.leftMargin: 30
                                                leftPadding: 0
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            onToggled: radioController.setAutoReconnectPreference(checked)
                                        }

                                        Text {
                                            Layout.columnSpan: 4
                                            Layout.fillWidth: true
                                            text:
                                                "Valores recomendados para esta instalación: "
                                                + "AUTO, 115200, radio 94h, controlador E0h, "
                                                + "polling 90 ms y timeout 850 ms."
                                            color: "#9da8ad"
                                            font.pixelSize: 9
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 7

                                    PanelButton {
                                        Layout.preferredWidth: 130
                                        text: "ACTUALIZAR"
                                        tip:
                                            "Vuelve a detectar los puertos serie."
                                        onClicked:
                                            radioController
                                            .refreshConnectionDevices()
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 130
                                        text: "RECOMENDADOS"
                                        tip:
                                            "Restaura los valores conocidos de esta instalación."

                                        onClicked: {
                                            radioController
                                            .restoreRecommendedConnectionSettings()
                                            settingsPopup
                                            .syncConnectionForm()
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 184
                                        text: "APLICAR Y RECONECTAR"
                                        selected: true
                                        activeColor: "#3c6f85"
                                        tip:
                                            "Guarda los parámetros y vuelve a abrir el puerto."

                                        onClicked:
                                            settingsPopup
                                            .applyConnectionForm()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:
                                        radioController.actionStatus
                                    color: "#d6dde1"
                                    font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "LAN: " + applicationLauncher.status
                                    color: "#8fd3ed"
                                    font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                    visible: applicationLauncher.status.length > 0
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    TextArea {
                                        id: lanLogArea
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 130
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        text: lanLogText
                                        onTextChanged: Qt.callLater(function() { cursorPosition = text.length })
                                        font.pixelSize: 11
                                        color: "#b9e9f7"
                                        background: Rectangle { color: "#0d1519"; border.color: "#345563"; radius: 2 }
                                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                                    }
                                    PanelButton {
                                        Layout.preferredWidth: 82
                                        text: "COPIAR LOG"
                                        onClicked: { lanLogArea.selectAll(); lanLogArea.copy(); lanLogArea.deselect() }
                                    }
                                    PanelButton {
                                        Layout.preferredWidth: 82
                                        text: "BORRAR LOG"
                                        tip: "Borra el registro LAN mostrado en esta ventana."
                                        onClicked: {
                                            lanLogText = ""
                                            lanLogArea.clear()
                                        }
                                    }
                                }
                            }
                        }

                        ScrollView {
                            id: connectorsScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width:
                                    connectorsScroll.availableWidth
                                spacing: 8

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 230
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text:
                                                    "INTERFACES USB DETECTADAS"
                                                color: "#dce3e7"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            PanelButton {
                                                Layout.preferredWidth: 100
                                                text: "ACTUALIZAR"
                                                onClicked:
                                                    radioController
                                                    .refreshConnectionDevices()
                                            }
                                        }

                                        TextArea {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: Text.Wrap
                                            text:
                                                radioController
                                                .usbInterfacesText
                                            color: "#cbd8de"
                                            font.family:
                                                "DejaVu Sans Mono"
                                            font.pixelSize: 9

                                            background: Rectangle {
                                                color: "#0b0e10"
                                                border.color: "#465158"
                                            }
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 180
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 7

                                        Text {
                                            text:
                                                "SEÑALES Y FUNCIONES ACTIVAS"
                                            color: "#dce3e7"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 7

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text:
                                                    radioController
                                                    .civOutputEnabled
                                                    ? "CI-V OUTPUT ON"
                                                    : "CI-V OUTPUT OFF"
                                                selected:
                                                    radioController
                                                    .civOutputEnabled
                                                activeColor: "#8a6627"
                                                enabled:
                                                    controlsEnabled()
                                                tip:
                                                    "Configuración real SET > CONNECTORS > CI-V Output."

                                                onClicked:
                                                    radioController
                                                    .setCivOutputEnabled(
                                                        !radioController
                                                        .civOutputEnabled
                                                    )
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text:
                                                    applicationLauncher.lanConnected
                                                    ? (applicationLauncher.lanDataEnabled
                                                       ? "DATA ON" : "DATA OFF")
                                                    : (radioController.dataMode
                                                       ? "DATA ON" : "DATA OFF")
                                                selected:
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.lanDataEnabled
                                                    : radioController.dataMode
                                                activeColor: "#347a50"
                                                enabled:
                                                    controlsEnabled()
                                                tip:
                                                    "Activa o desactiva DATA en el VFO actual."

                                                onClicked:
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.setLanDataEnabled(!applicationLauncher.lanDataEnabled, radioController.modeText)
                                                    : radioController.setDataEnabled(!radioController.dataMode)
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text:
                                                    radioController
                                                    .txInhibitEnabled
                                                    ? "TX INHIBIT ON"
                                                    : "TX INHIBIT OFF"
                                                selected:
                                                    radioController
                                                    .txInhibitEnabled
                                                activeColor: "#963b3b"
                                                enabled:
                                                    controlsEnabled()
                                                tip:
                                                    "Bloqueo real de transmisión de la radio."

                                                onClicked:
                                                    radioController
                                                    .setTxInhibitEnabled(
                                                        !radioController
                                                        .txInhibitEnabled
                                                    )
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 2
                                            rowSpacing: 4
                                            columnSpacing: 8

                                            Text {
                                                text: "Puerto activo"
                                                color: "#aeb9be"
                                                font.pixelSize: 9
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text:
                                                    radioController.portName
                                                color: "#8fd9f5"
                                                font.family:
                                                    "DejaVu Sans Mono"
                                                font.pixelSize: 9
                                                elide: Text.ElideMiddle
                                            }

                                            Text {
                                                text: "PTT"
                                                color: "#aeb9be"
                                                font.pixelSize: 9
                                            }

                                            Text {
                                                text:
                                                    radioController.transmitting
                                                    ? (radioController.pttOwned
                                                       ? "TX controlado por la aplicación"
                                                       : "TX externo")
                                                    : "RX"
                                                color:
                                                    radioController.transmitting
                                                    ? "#ff9c9c"
                                                    : "#8de29a"
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                "Esta sección reúne únicamente señales "
                                                + "que ya están implementadas mediante CI-V."
                                            color: "#909ba0"
                                            font.pixelSize: 9
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }

                        ScrollView {
                            id: capabilitiesScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width:
                                    capabilitiesScroll.availableWidth
                                spacing: 8

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 150
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text:
                                                    "PASO REAL DE LA RADIO · COMANDO 10"
                                                color: "#e8edf1"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text:
                                                    radioController
                                                    .radioTuningStepText
                                                color: "#77d3ff"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 5
                                            rowSpacing: 5
                                            columnSpacing: 5

                                            Repeater {
                                                model: [
                                                    { code: 0, text: "OFF" },
                                                    { code: 1, text: "0,1k" },
                                                    { code: 2, text: "1k" },
                                                    { code: 3, text: "5k" },
                                                    { code: 4, text: "9k" },
                                                    { code: 5, text: "10k" },
                                                    { code: 6, text: "12,5k" },
                                                    { code: 7, text: "20k" },
                                                    { code: 8, text: "25k" }
                                                ]

                                                PanelButton {
                                                    Layout.fillWidth: true
                                                    text: modelData.text
                                                    selected:
                                                        radioController
                                                        .radioTuningStepCode
                                                        === modelData.code
                                                    activeColor: "#2d7cb3"
                                                    enabled:
                                                        controlsEnabled()

                                                    onClicked:
                                                        radioController
                                                        .setRadioTuningStep(
                                                            modelData.code
                                                        )
                                                }
                                            }
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 92
                                    color: "#171a1c"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 9

                                        PanelButton {
                                            Layout.preferredWidth: 180
                                            text:
                                                radioController
                                                .civOutputEnabled
                                                ? "CI-V OUTPUT: ON"
                                                : "CI-V OUTPUT: OFF"
                                            selected:
                                                radioController
                                                .civOutputEnabled
                                            activeColor: "#8a5e20"
                                            enabled:
                                                controlsEnabled()

                                            onClicked:
                                                radioController
                                                .setCivOutputEnabled(
                                                    !radioController
                                                    .civOutputEnabled
                                                )
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                "Configuración permanente de "
                                                + "SET > CONNECTORS > CI-V. "
                                                + "El polling permanece como respaldo."
                                            color: "#c7cfd3"
                                            font.pixelSize: 9
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 270
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text:
                                                    "LÍMITES TX REGIONALES · COMANDO 1E"
                                                color: "#e8edf1"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            PanelButton {
                                                Layout.preferredWidth: 96
                                                text: "ACTUALIZAR"
                                                enabled:
                                                    radioController.connected
                                                onClicked:
                                                    radioController
                                                    .refreshCapabilities()
                                            }
                                        }

                                        TextArea {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: Text.NoWrap
                                            text:
                                                radioController.txBandEdgesText
                                            color: "#dce6ed"
                                            font.family:
                                                "DejaVu Sans Mono"
                                            font.pixelSize: 9

                                            background: Rectangle {
                                                color: "#080a0b"
                                                border.color: "#4d555b"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ScrollView {
                            id: diagnosticSectionScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width:
                                    diagnosticSectionScroll.availableWidth
                                spacing: 8

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 130
                                    color: "#171a1c"

                                    GridLayout {
                                        anchors.fill: parent
                                        anchors.margins: 9
                                        columns: 2
                                        rowSpacing: 6
                                        columnSpacing: 9

                                        Text {
                                            text: "Estado"
                                            color: "#aeb9be"
                                            font.pixelSize: 9
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                radioController.status
                                            color: "#dce4e8"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            text: "Acción"
                                            color: "#aeb9be"
                                            font.pixelSize: 9
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                radioController.actionStatus
                                            color: "#dce4e8"
                                            font.pixelSize: 10
                                            wrapMode: Text.Wrap
                                        }

                                        Text {
                                            text: "Última TX"
                                            color: "#aeb9be"
                                            font.pixelSize: 9
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                radioController.lastTx
                                            color: "#efb6b6"
                                            font.family:
                                                "DejaVu Sans Mono"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: "Última RX"
                                            color: "#aeb9be"
                                            font.pixelSize: 9
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                radioController.lastRx
                                            color: "#a9d9f0"
                                            font.family:
                                                "DejaVu Sans Mono"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 7

                                    PanelButton {
                                        Layout.preferredWidth: 150
                                        text: "RECONECTAR"
                                        onClicked:
                                            radioController.reconnectRadio()
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 170
                                        text: "DIAGNÓSTICO COMPLETO"

                                        onClicked: {
                                            settingsPopup.close()
                                            window
                                            .toggleAuxiliaryWindow(
                                                "diagnostics"
                                            )
                                        }
                                    }

                                    PanelButton {
                                        Layout.preferredWidth: 140
                                        text: "LIMPIAR TRÁFICO"
                                        onClicked:
                                            radioController
                                            .clearTrafficHistory()
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:
                                        "El diagnóstico completo mantiene "
                                        + "el historial de tramas CI-V y "
                                        + "los filtros de tráfico de memorias."
                                    color: "#909ba0"
                                    font.pixelSize: 9
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: diagnosticsPopup

        parent: Overlay.overlay
        modal: false
        focus: true

        property bool trafficPaused: false
        property bool memoryTrafficOnly: false
        property string pausedTxHistory: ""
        property string pausedRxHistory: ""

        function filterTraffic(history) {
            if (!memoryTrafficOnly)
                return history

            const lines = history.split("\n")
            let filtered = []

            for (let index = 0;
                 index < lines.length;
                 ++index) {
                const line = lines[index]

                if (line.indexOf("1A 00") >= 0
                        || line.indexOf(" FA ") >= 0
                        || line.endsWith(" FA FD")) {
                    filtered.push(line)
                }
            }

            return filtered.join("\n")
        }

        function visibleTxHistory() {
            const source =
                trafficPaused
                ? pausedTxHistory
                : radioController.txTrafficHistory
            const filtered = filterTraffic(source)
            return filtered.length > 0 ? filtered : "—"
        }

        function visibleRxHistory() {
            const source =
                trafficPaused
                ? pausedRxHistory
                : radioController.rxTrafficHistory
            const filtered = filterTraffic(source)
            return filtered.length > 0 ? filtered : "—"
        }

        function setTrafficPaused(paused) {
            if (paused) {
                pausedTxHistory =
                    radioController.txTrafficHistory
                pausedRxHistory =
                    radioController.rxTrafficHistory
            }

            trafficPaused = paused
        }

        width:
            Math.min(
                900,
                window.width - 40
            )
        height:
            Math.min(
                320,
                window.height - 100
            )
        x: 20
        y: 74

        closePolicy:
            Popup.CloseOnEscape

        onOpened: {
            diagnosticsVisible = true
            setTrafficPaused(false)
        }

        onClosed:
            diagnosticsVisible = false

        background: Rectangle {
            radius: 4
            color: "#1e2225"
            border.color: "#72ceff"
            border.width: 2
        }

        contentItem: ColumnLayout {
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                PopupDragTitle {
                    popupTarget:
                        diagnosticsPopup
                    title: "DIAGNÓSTICO CI-V"
                    textColor: "#e3f6ff"
                    pixelSize: 12
                }

                Item {
                    Layout.fillWidth: true
                }

                PanelButton {
                    text:
                        diagnosticsPopup.trafficPaused
                        ? "Continuar"
                        : "Pausa"
                    selected:
                        diagnosticsPopup.trafficPaused
                    activeColor: "#9a672e"
                    tip:
                        diagnosticsPopup.trafficPaused
                        ? "Reanuda la actualización del historial."
                        : "Congela las tramas visibles para poder seleccionarlas y copiarlas."

                    onClicked:
                        diagnosticsPopup.setTrafficPaused(
                            !diagnosticsPopup.trafficPaused
                        )
                }

                PanelButton {
                    text:
                        diagnosticsPopup.memoryTrafficOnly
                        ? "Solo MEM: ON"
                        : "Solo MEM"
                    selected:
                        diagnosticsPopup.memoryTrafficOnly
                    activeColor: "#6a4b88"
                    tip:
                        "Muestra únicamente las tramas CI-V 1A 00 de lectura o escritura de memorias."

                    onClicked:
                        diagnosticsPopup.memoryTrafficOnly =
                            !diagnosticsPopup.memoryTrafficOnly
                }

                PanelButton {
                    text: "Copiar TX"
                    tip:
                        "Copia al portapapeles las tramas TX que están visibles."

                    onClicked:
                        radioController.copyTextToClipboard(
                            diagnosticsTxArea.text,
                            "Historial TX"
                        )
                }

                PanelButton {
                    text: "Copiar RX"
                    tip:
                        "Copia al portapapeles las tramas RX que están visibles."

                    onClicked:
                        radioController.copyTextToClipboard(
                            diagnosticsRxArea.text,
                            "Historial RX"
                        )
                }

                PanelButton {
                    text: "Copiar todo"
                    tip:
                        "Copia conjuntamente los historiales TX y RX visibles."

                    onClicked:
                        radioController.copyTextToClipboard(
                            "TX:\n"
                            + diagnosticsTxArea.text
                            + "\n\nRX:\n"
                            + diagnosticsRxArea.text,
                            "Diagnóstico CI-V"
                        )
                }

                PanelButton {
                    text: "Limpiar"
                    tip:
                        "Borra el historial TX y RX mostrado."

                    onClicked: {
                        diagnosticsPopup.setTrafficPaused(false)
                        diagnosticsPopup.pausedTxHistory = ""
                        diagnosticsPopup.pausedRxHistory = ""
                        radioController.clearTrafficHistory()
                    }
                }

                PanelButton {
                    text: "Cerrar"
                    tip:
                        "Cierra la ventana de diagnóstico."
                    onClicked:
                        diagnosticsPopup.close()
                }
            }

            Item {
                id: diagnosticsTrafficArea

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                readonly property int dividerGap: 6
                readonly property int columnWidth:
                    Math.floor(
                        (width - dividerGap) / 2
                    )

                FrameBox {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width:
                        diagnosticsTrafficArea
                        .columnWidth
                    color: "#080909"
                    border.color: "#456f83"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text:
                                    diagnosticsPopup.trafficPaused
                                    ? "TX · PAUSA"
                                    : "TX · HISTORIAL"
                                color:
                                    diagnosticsPopup.trafficPaused
                                    ? "#ffc071"
                                    : "#85d7ff"
                                font.pixelSize: 10
                                font.bold: true
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Text {
                                text:
                                    radioController.lastTx === "—"
                                    ? "0 tramas"
                                    : "máx. 300"
                                color: "#7f8b92"
                                font.pixelSize: 8
                            }
                        }

                        ScrollView {
                            id: diagnosticsTxScroll

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ScrollBar.horizontal.policy:
                                ScrollBar.AsNeeded
                            ScrollBar.vertical.policy:
                                ScrollBar.AsNeeded

                            TextArea {
                                id: diagnosticsTxArea

                                width:
                                    Math.max(
                                        diagnosticsTxScroll
                                        .availableWidth,
                                        implicitWidth
                                    )
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.NoWrap
                                padding: 5

                                text:
                                    diagnosticsPopup
                                    .visibleTxHistory()

                                color: "#d9f0ff"
                                selectionColor: "#315d72"
                                selectedTextColor: "#ffffff"
                                font.family:
                                    "DejaVu Sans Mono"
                                font.pixelSize: 9

                                background: Rectangle {
                                    color: "#050707"
                                }

                                onTextChanged: {
                                    if (diagnosticsPopup
                                            .trafficPaused)
                                        return

                                    cursorPosition = length

                                    Qt.callLater(
                                        function() {
                                            const flick =
                                                diagnosticsTxScroll
                                                .contentItem

                                            if (flick) {
                                                flick.contentY =
                                                    Math.max(
                                                        0,
                                                        flick.contentHeight
                                                        - flick.height
                                                    )
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: diagnosticsDivider

                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter:
                        parent.horizontalCenter

                    width: 1
                    color: "#4e6976"
                    opacity: 0.85
                }

                FrameBox {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width:
                        diagnosticsTrafficArea
                        .columnWidth
                    color: "#080909"
                    border.color: "#49755a"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text:
                                    diagnosticsPopup.trafficPaused
                                    ? "RX · PAUSA"
                                    : "RX · HISTORIAL"
                                color:
                                    diagnosticsPopup.trafficPaused
                                    ? "#ffc071"
                                    : "#8de2a7"
                                font.pixelSize: 10
                                font.bold: true
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Text {
                                text:
                                    radioController.lastRx === "—"
                                    ? "0 tramas"
                                    : "máx. 300"
                                color: "#7f8b92"
                                font.pixelSize: 8
                            }
                        }

                        ScrollView {
                            id: diagnosticsRxScroll

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ScrollBar.horizontal.policy:
                                ScrollBar.AsNeeded
                            ScrollBar.vertical.policy:
                                ScrollBar.AsNeeded

                            TextArea {
                                id: diagnosticsRxArea

                                width:
                                    Math.max(
                                        diagnosticsRxScroll
                                        .availableWidth,
                                        implicitWidth
                                    )
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.NoWrap
                                padding: 5

                                text:
                                    diagnosticsPopup
                                    .visibleRxHistory()

                                color: "#d8ffe1"
                                selectionColor: "#315f41"
                                selectedTextColor: "#ffffff"
                                font.family:
                                    "DejaVu Sans Mono"
                                font.pixelSize: 9

                                background: Rectangle {
                                    color: "#050707"
                                }

                                onTextChanged: {
                                    if (diagnosticsPopup
                                            .trafficPaused)
                                        return

                                    cursorPosition = length

                                    Qt.callLater(
                                        function() {
                                            const flick =
                                                diagnosticsRxScroll
                                                .contentItem

                                            if (flick) {
                                                flick.contentY =
                                                    Math.max(
                                                        0,
                                                        flick.contentHeight
                                                        - flick.height
                                                    )
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    FrameBox {
        anchors.fill: parent
        anchors.margins: 6
        color: "#414141"
        border.color: "#5886ad"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 5

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 72
                color: "#4b4b4b"
                border.color: "#707070"

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "#595959"
                    }

                    GradientStop {
                        position: 1
                        color: "#3d3d3d"
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    ToolbarGroup {
                        caption: "CONEXIÓN"
                        accentColor: "#3d9fc4"

                    ToolbarButton {
                        text: "RADIO"
                        iconName: "connect"
                        iconColor:
                            radioController.connected
                            ? "#39d871"
                            : "#49bfff"

                        onClicked:
                            radioController.connected
                            ? radioController
                              .disconnectRadio()
                            : radioController
                              .connectRadio()
                    }

                    ToolbarButton {
                        text: "INTERNET"
                        iconName: "remote"
                        iconColor:
                            remoteServer.running
                            ? "#57d47c"
                            : remoteServerVisible
                              ? "#49bfff"
                              : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "remoteServer"
                            )
                    }

                    ToolbarButton {
                        text: "NAVEGADOR"
                        iconName: "browser"
                        iconColor:
                            remoteServer.running
                            ? "#67d8ff"
                            : "#8f8f8f"
                        tip:
                            "Abre el panel remoto en el navegador de este equipo. "
                            + "Si el servidor está detenido, lo inicia primero."

                        onClicked: {
                            if (!remoteServer.running
                                    && !remoteServer.start())
                                return
                            Qt.openUrlExternally(
                                remoteServer.localTestUrl
                            )
                        }
                    }

                    ToolbarButton {
                        text: "COMPACTO"
                        iconName: "settings"
                        iconColor: compactVisible ? "#ffd36b" : "#8f8f8f"
                        tip: "Abre la vista compacta para mantener los controles esenciales accesibles."
                        onClicked: setCompactMode(true)
                    }

                    ToolbarButton {
                        text: "SUPER"
                        iconName: "settings"
                        iconColor: superCompactVisible ? "#ffd36b" : "#8f8f8f"
                        tip: "Muestra solo frecuencia y modo. Pulse esa ventana para volver al modo compacto."
                        onClicked: setSuperCompactMode(true)
                    }

                    ToolbarButton {
                        text: "DIAGNÓST."
                        iconName: "remote"
                        iconColor:
                            diagnosticsVisible
                            ? "#49bfff"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "diagnostics"
                            )
                    }

                    }

                    ToolbarGroup {
                        Layout.fillWidth: true
                        caption: "HERRAMIENTAS Y AJUSTES"
                        accentColor: "#b68b45"

                    ToolbarButton {
                        text: "CI-V"
                        Layout.preferredWidth: 45
                        Layout.minimumWidth: 40
                        iconName: "settings"
                        iconColor:
                            settingsVisible
                            ? "#f2c94c"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "civ"
                            )
                    }

                    ToolbarButton {
                        text: "SCOPE"
                        Layout.preferredWidth: 45
                        Layout.minimumWidth: 40
                        iconName: "scope"
                        iconColor:
                            scopeVisible
                            ? "#62d5ff"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "scope"
                            )
                    }

                    ToolbarButton {
                        text: "TX"
                        Layout.preferredWidth: 45
                        Layout.minimumWidth: 40
                        iconName: "tx"
                        iconColor:
                            txSettingsVisible
                            ? "#6ecdf5"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "tx"
                            )
                    }

                    ToolbarButton {
                        text: "CW"
                        Layout.preferredWidth: 45
                        Layout.minimumWidth: 40
                        iconName: "cw"
                        iconColor:
                            cwSettingsVisible
                            ? "#7ee0b4"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "cw"
                            )
                    }

                    ToolbarButton {
                        text: "MORSE"
                        Layout.preferredWidth: 45
                        Layout.minimumWidth: 40
                        iconName: "morse"
                        iconColor:
                            morseTrainerVisible
                            ? "#7fe2a7"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "morse"
                            )
                    }

                    ToolbarButton {
                        text: "TONO/RTTY"
                        Layout.preferredWidth: 45
                        Layout.minimumWidth: 40
                        iconName: "toneRtty"
                        iconColor:
                            toneRttySettingsVisible
                            ? "#e4a65f"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "toneRtty"
                            )
                    }

                    }

                    ToolbarGroup {
                        caption: "MEMORIAS"
                        accentColor: "#8e68b5"

                    ToolbarButton {
                        text: "ESCÁNER"
                        iconName: "memory"
                        iconColor:
                            scannerVisible
                            ? "#c99cff"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleAuxiliaryWindow(
                                "scanner"
                            )
                    }

                    ToolbarButton {
                        text: "MEMORIA"
                        iconName: "memory"
                        iconColor:
                            memoryQuickPanelVisible
                            ? "#67cfff"
                            : "#8f8f8f"

                        onClicked:
                            window.toggleMemoryQuickPanel()
                    }

                    }

                    ToolbarGroup {
                        caption: "VFO"
                        accentColor: "#559467"

                    ToolbarButton {
                        text: "VFO A"
                        iconName: "vfoA"
                        iconColor:
                            radioController.vfoASelected
                            ? "#49bfff"
                            : "#878787"

                        onClicked:
                            radioController.selectVfoA()
                    }

                    ToolbarButton {
                        text: "VFO B"
                        iconName: "vfoB"
                        iconColor:
                            radioController.vfoBSelected
                            ? "#6edb79"
                            : "#878787"

                        onClicked:
                            radioController.selectVfoB()
                    }

                    }

                    ToolbarGroup {
                        caption: "SISTEMA"
                        accentColor: "#a65757"

                    ToolbarButton {
                        text: "SALIR"
                        iconName: "exit"
                        iconColor: "#ff7d78"

                        onClicked:
                            Qt.quit()
                    }

                    }

                    Item {
                        Layout.preferredWidth: 2
                    }

                    Text {
                        Layout.maximumWidth: 70
                        text:
                            radioController.portName
                        color: "#e6e6e6"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                FrameBox {
                    id: leftOperatingPanel

                    Layout.preferredWidth: 118
                    Layout.minimumWidth: 118
                    Layout.maximumWidth: 118
                    Layout.fillHeight: true
                    color: "#2c2c2c"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 3

                        SidePanelGroup {
                            caption: "TX / TUNER"
                            accentColor: "#b86d64"

                        Button {
                            id: ptt

                            Layout.fillWidth: true
                            implicitHeight: 31

                            enabled:
                                radioController.connected
                                && (!radioController
                                    .transmitting
                                    || radioController
                                       .pttOwned)

                            background: Rectangle {
                                radius: 2
                                color:
                                    radioController.txInhibitEnabled
                                    ? "#342a16"
                                    : radioController
                                      .transmitting
                                      ? "#b51f1f"
                                      : ptt.down
                                        ? "#8b1717"
                                        : "#2b0d0d"
                                border.color:
                                    radioController
                                    .transmitting
                                    ? "#ffd2d2"
                                    : "#c86464"
                            }

                            ToolTip.visible:
                                hovered
                            ToolTip.delay: 450
                            ToolTip.timeout: 8000
                            ToolTip.text:
                                "PTT momentáneo. Mantén pulsado para transmitir."

                            onPressed:
                                radioController
                                .setTransmit(true)

                            onReleased:
                                radioController
                                .setTransmit(false)

                            onCanceled:
                                radioController
                                .setTransmit(false)

                            contentItem: Text {
                                text:
                                    radioController.txInhibitEnabled
                                    ? "TX LOCK"
                                    : radioController
                                      .transmitting
                                      ? (radioController
                                         .pttOwned
                                         ? "TRANSMIT"
                                         : "TX EXT")
                                      : "TRANSMIT"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.bold: true
                                horizontalAlignment:
                                    Text.AlignHCenter
                                verticalAlignment:
                                    Text.AlignVCenter
                            }
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "TUNER"
                            selected:
                                radioController
                                .tunerEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .setTunerEnabled(
                                    !radioController
                                    .tunerEnabled
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "TUNE"
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .startTuner()
                        }

                        }

                        SidePanelGroup {
                            caption: "FRONTAL RF"
                            accentColor: "#6da184"

                        PanelButton {
                            Layout.fillWidth: true
                            textPixelSize: 12
                            text:
                                "P.AMP "
                                + (radioController.preamp === 0
                                   ? "OFF"
                                   : radioController.preamp)
                            selected:
                                radioController.preamp > 0
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController.setPreamp(
                                    radioController.preamp === 2
                                    ? 0
                                    : radioController.preamp + 1
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            textPixelSize: 12
                            text:
                                radioController.attenuatorEnabled
                                ? "ATT ON"
                                : "ATT OFF"
                            selected:
                                radioController.attenuatorEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController.setAttenuatorEnabled(
                                    !radioController.attenuatorEnabled
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            textPixelSize: 12
                            text:
                                "AGC "
                                + (radioController.agc === 1
                                   ? "F"
                                   : radioController.agc === 2
                                     ? "M"
                                     : "S")
                            selected: true
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController.setAgc(
                                    radioController.agc === 3
                                    ? 1
                                    : radioController.agc + 1
                                )
                        }

                        }

                        SidePanelGroup {
                            caption: "DSP / RUIDO"
                            accentColor: "#6f8fb5"

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "NB"
                            selected:
                                radioController
                                .noiseBlankerEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .setNoiseBlankerEnabled(
                                    !radioController
                                    .noiseBlankerEnabled
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "NR"
                            selected:
                                radioController
                                .noiseReductionEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .setNoiseReductionEnabled(
                                    !radioController
                                    .noiseReductionEnabled
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "AN"
                            selected:
                                radioController
                                .autoNotchEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .setAutoNotchEnabled(
                                    !radioController
                                    .autoNotchEnabled
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "MN"
                            selected:
                                radioController
                                .manualNotchEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .setManualNotchEnabled(
                                    !radioController
                                    .manualNotchEnabled
                                )
                        }

                        PanelButton {
                            Layout.fillWidth: true
                            
                            textPixelSize: 12
text: "IP+"
                            selected:
                                radioController
                                .ipPlusEnabled
                            enabled:
                                controlsEnabled()

                            onClicked:
                                radioController
                                .setIpPlusEnabled(
                                    !radioController
                                    .ipPlusEnabled
                                )
                        }

                        }

                        SidePanelGroup {
                            caption: "NIVELES RF"
                            accentColor: "#b99956"

                        KnobControl {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 94
                            Layout.maximumHeight: 94
                            compact: true
                            caption: "RF GAIN"
                            currentValue:
                                radioController.rfGain
                            accentColor: "#70e0b3"
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setRfGain(value)
                                }
                        }

                        KnobControl {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 94
                            Layout.maximumHeight: 94
                            compact: true
                            caption: "RF POWER"
                            currentValue:
                                radioController.rfPower
                            accentColor: "#f2c94c"
                            applyFunction:
                                function(value) {
                                    radioController
                                    .setRfPower(value)
                                }
                        }

                        }

                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#292929"
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 6
                            clip: true

                            FrameBox {
                                id: mainRadioDisplay

                                Layout.fillWidth: true
                                Layout.minimumHeight: 340
                                Layout.preferredHeight: 340
                                Layout.maximumHeight: 340
                                Layout.alignment: Qt.AlignTop

                                color: "#020202"
                                border.color: "#4d4d4d"
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: "ICOM"
                                            color: "#dedede"
                                            font.pixelSize: 10
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text:
                                                "REMOTE CONTROL SOFTWARE"
                                            color: "#eeeeee"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            text: "IC-7300MK2"
                                            color: "#86d8ff"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        Text {
                                            text: "CONTROL"
                                            color: "#ffffff"
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                    }

                                    RowLayout {
                                        visible: false
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 0
                                        Layout.minimumHeight: 0
                                        Layout.maximumHeight: 0
                                        spacing: 12

                                        // Esta zona tiene exactamente el mismo
                                        // ancho que el panel del VFO principal.
                                        // Los modos quedan sobre su mitad derecha
                                        // y nunca invaden el subpanel del VFO B.
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4

                                            StatusTag {
                                                caption:
                                                    "FIL "
                                                    + radioController
                                                      .filterText
                                                tagColor: "#3d3d3d"
                                            }

                                            StatusTag {
                                                caption:
                                                    radioController
                                                    .agcText
                                                tagColor: "#3d3d3d"
                                            }

                                            StatusTag {
                                                caption:
                                                    radioController
                                                    .preampText
                                                tagColor:
                                                    radioController
                                                    .preamp > 0
                                                    ? "#315f9b"
                                                    : "#3d3d3d"
                                            }

                                            StatusTag {
                                                caption:
                                                    radioController
                                                    .attenuatorText
                                                tagColor:
                                                    radioController
                                                    .attenuatorEnabled
                                                    ? "#8a5630"
                                                    : "#3d3d3d"
                                            }

                                            StatusTag {
                                                caption:
                                                    radioController
                                                    .filterShapeText
                                                tagColor: "#3d3d3d"
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }
                                        }

                                        // Reserva idéntica al ancho del VFO B.
                                        // Aquí solo queda la indicación de potencia.
                                        Item {
                                            Layout.preferredWidth: 235
                                            Layout.minimumWidth: 235
                                            Layout.maximumWidth: 235
                                            Layout.fillHeight: true

                                            Text {
                                                anchors.right: parent.right
                                                anchors.verticalCenter:
                                                    parent.verticalCenter
                                                text:
                                                    "RF PWR "
                                                    + radioController
                                                      .rfPower
                                                    + "%"
                                                color: "#dddddd"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 190
                                        spacing: 12

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            // Banda compacta inmediatamente encima
                                            // del display principal: dos filas de
                                            // estados útiles a la izquierda y dos filas de
                                            // modos a la derecha. No añade altura.
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 52
                                                Layout.minimumHeight: 52
                                                Layout.maximumHeight: 52

                                                RowLayout {
                                                    anchors.fill: parent
                                                    spacing: 8

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        spacing: 0

                                                        Item {
                                                            Layout.fillHeight: true
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 24
                                                            spacing: 5

                                                            StatusTag {
                                                                caption:
                                                                    radioController
                                                                    .squelchStateText
                                                                tagColor:
                                                                    radioController
                                                                    .squelchOpen
                                                                    ? "#2f8f54"
                                                                    : "#444444"

                                                                ToolTip.visible:
                                                                    busyHover.hovered
                                                                ToolTip.delay: 450
                                                                ToolTip.timeout: 8000
                                                                ToolTip.text:
                                                                    "Estado real del squelch leído con CI-V 15 05."

                                                                HoverHandler {
                                                                    id: busyHover
                                                                }
                                                            }

                                                            StatusTag {
                                                                visible:
                                                                    radioController
                                                                    .repeaterToneEnabled
                                                                caption: "TONE"
                                                                tagColor: "#3f7658"
                                                            }

                                                            StatusTag {
                                                                visible:
                                                                    radioController
                                                                    .toneSquelchEnabled
                                                                caption: "TSQL"
                                                                tagColor: "#4f668b"
                                                            }

                                                            StatusTag {
                                                                visible:
                                                                    radioController
                                                                    .twinPeakEnabled
                                                                caption: "TPF"
                                                                tagColor: "#9b5f2d"
                                                            }

                                                            StatusTag {
                                                                visible:
                                                                    radioController
                                                                    .memoryModeActive
                                                                caption:
                                                                    radioController
                                                                    .selectedMemoryChannelText
                                                                tagColor: "#76539a"
                                                            }

                                                            StatusTag {
                                                                visible:
                                                                    radioController
                                                                    .scanActive
                                                                caption: "SCAN"
                                                                tagColor: "#8e3e7f"
                                                            }

                                                            Text {
                                                                text:
                                                                    radioController
                                                                    .bandText
                                                                color: "#e8e8e8"
                                                                font.pixelSize: 10
                                                                font.bold: true
                                                            }

                                                            Item {
                                                                Layout.fillWidth: true
                                                            }

                                                            Text {
                                                                text:
                                                                    "RF PWR "
                                                                    + radioController
                                                                      .rfPower
                                                                    + "%"
                                                                color: "#dddddd"
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                            }
                                                        }

                                                        Item {
                                                            Layout.fillHeight: true
                                                        }
                                                    }

                                                    GridLayout {
                                                        Layout.preferredWidth: 300
                                                        Layout.minimumWidth: 280
                                                        Layout.maximumWidth: 310
                                                        Layout.fillHeight: true
                                                        columns: 5
                                                        rowSpacing: 4
                                                        columnSpacing: 6

                                                        Repeater {
                                                            model: modeNames

                                                            PanelButton {
                                                                Layout.fillWidth: true
                                                                Layout.preferredHeight: 24
                                                                Layout.minimumHeight: 24
                                                                Layout.maximumHeight: 24
                                                                text: modelData
                                                                textPixelSize: 11
                                                                selected:
                                                                    modelData === "SSTV"
                                                                    ? applicationLauncher.qsstvRunning
                                                                    : modelData === "FT8/FT4"
                                                                    ? applicationLauncher.decodiumRunning
                                                                    : (modelData === "RTTY"
                                                                     || modelData === "RTTY-R")
                                                                    ? (applicationLauncher
                                                                       .fldigiRunning
                                                                       && externalDigitalMode
                                                                          === modelData)
                                                                    : (applicationLauncher.lanConnected
                                                                       ? applicationLauncher.lanMode === modelData
                                                                       : radioController.modeText === modelData)
                                                                activeColor:
                                                                    modelData === "SSTV" ? "#86652f"
                                                                    : modelData === "FT8/FT4" ? "#28789a"
                                                                    : "#2f72b9"
                                                                enabled:
                                                                    controlsEnabled()
                                                                tip:
                                                                    "Selecciona el modo "
                                                                    + modelData
                                                                    + "."

                                                                onClicked: {
                                                                    if (modelData === "SSTV") {
                                                                        if (applicationLauncher.qsstvRunning) {
                                                                            stopExternalProgramsAndRestore()
                                                                            return
                                                                        }
                                                                        prepareExternalProgram("qsstv")
                                                                        externalDigitalMode = "SSTV"
                                                                        radioController.setFrequency(
                                                                            String(applicationLauncher.sstvFrequencyHz))
                                                                        selectUsbDataMode()
                                                                        applicationLauncher.launchQsstv()
                                                                    } else if (modelData === "FT8/FT4") {
                                                                        if (applicationLauncher.decodiumRunning) {
                                                                            stopExternalProgramsAndRestore()
                                                                            return
                                                                        }
                                                                        prepareExternalProgram("decodium")
                                                                        externalDigitalMode = "FT8/FT4"
                                                                        radioController.setFrequency(
                                                                            String(applicationLauncher.ftFrequencyHz))
                                                                        selectUsbDataMode()
                                                                        applicationLauncher.launchDecodium()
                                                                    } else if (modelData === "RTTY"
                                                                            || modelData === "RTTY-R") {
                                                                        if (applicationLauncher.fldigiRunning
                                                                                && externalDigitalMode === modelData) {
                                                                            stopExternalProgramsAndRestore()
                                                                            return
                                                                        }
                                                                        prepareExternalProgram("fldigi")
                                                                        externalDigitalMode = modelData
                                                                        radioController.setFrequency(
                                                                            String(applicationLauncher.rttyFrequencyHz)
                                                                        )
                                                                        selectUsbDataMode()
                                                                        applicationLauncher
                                                                        .launchFldigi()
                                                                        applicationLauncher
                                                                        .setFldigiMode("RTTY")
                                                                        applicationLauncher
                                                                        .setFldigiReverse(
                                                                            modelData === "RTTY-R")
                                                                    } else {
                                                                        if ((modelData === "CW"
                                                                             || modelData === "CW-R")
                                                                                && applicationLauncher.fldigiRunning
                                                                                && radioController.modeText === modelData) {
                                                                            stopExternalProgramsAndRestore()
                                                                            return
                                                                        }
                                                                        if (applicationLauncher.decodiumRunning
                                                                                || applicationLauncher.qsstvRunning
                                                                                || applicationLauncher.js8callRunning)
                                                                            stopExternalProgramsAndRestore()
                                                                        if (modelData !== "CW"
                                                                                && modelData !== "CW-R") {
                                                                            stopExternalProgramsAndRestore()
                                                                        }
                                                                        externalDigitalMode = ""
                                                                        if (modelData === "CW"
                                                                                || modelData === "CW-R") {
                                                                            radioController.setFrequency(
                                                                                String(applicationLauncher.cwFrequencyHz)
                                                                            )
                                                                            if (applicationLauncher.fldigiRunning)
                                                                                externalDigitalMode = modelData
                                                                        }
                                                                        if (applicationLauncher.lanConnected
                                                                                && ["LSB","USB","AM","CW","RTTY","FM","CW-R","RTTY-R"].indexOf(modelData) >= 0)
                                                                            applicationLauncher.testLanModeName(modelData)
                                                                        else
                                                                            radioController.setOperatingMode(modelData)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.preferredWidth: 132
                                                        Layout.minimumWidth: 126
                                                        Layout.maximumWidth: 140
                                                        Layout.fillHeight: true
                                                        spacing: 4

                                                        ComboBox {
                                                            id: extraDigitalModeBox
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 24
                                                            font.pixelSize: 10
                                                            model: ["OTROS…", "PSK", "OLIVIA", "WEFAX", "JS8"]

                                                            onActivated: function(index) {
                                                                if (index === 0)
                                                                    return
                                                                if (index === 1 || index === 2 || index === 3) {
                                                                    const targetMode = index === 1 ? "PSK" : index === 2 ? "OLIVIA" : "WEFAX"
                                                                    if (applicationLauncher.fldigiRunning
                                                                            && externalDigitalMode === targetMode) {
                                                                        stopExternalProgramsAndRestore()
                                                                        return
                                                                    }
                                                                    prepareExternalProgram("fldigi")
                                                                    externalDigitalMode = targetMode
                                                                    radioController.setFrequency(
                                                                        String(index === 1
                                                                               ? applicationLauncher.pskFrequencyHz
                                                                               : index === 2 ? applicationLauncher.oliviaFrequencyHz
                                                                               : applicationLauncher.wefaxFrequencyHz))
                                                                    radioController.setOperatingModeState("USB", true, 1)
                                                                    applicationLauncher.launchFldigi()
                                                                    applicationLauncher.setFldigiMode(
                                                                        index === 1 ? "BPSK31" : index === 2 ? "OLIVIA-8/250" : "WEFAX576")
                                                                    applicationLauncher.setFldigiReverse(false)
                                                                } else if (index === 4) {
                                                                    if (applicationLauncher.js8callRunning) {
                                                                        stopExternalProgramsAndRestore()
                                                                        return
                                                                    }
                                                                    prepareExternalProgram("js8call")
                                                                    externalDigitalMode = "JS8"
                                                                    radioController.setFrequency(
                                                                        String(applicationLauncher.js8FrequencyHz))
                                                                    radioController.setOperatingModeState("USB", true, 1)
                                                                    applicationLauncher.launchJs8call()
                                                                }
                                                            }
                                                        }

                                                        PanelButton {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 24
                                                            text: "FRECUENCIAS…"
                                                            textPixelSize: 9
                                                            activeColor: "#61517d"
                                                            onClicked: digitalFrequencyPopup.open()
                                                        }
                                                    }
                                                }
                                            }

                                            FrameBox {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 76
                                                raised: true
                                                color:
                                                    radioController
                                                    .selectedVfo === 0
                                                    ? "#041014"
                                                    : "#061109"
                                                border.color:
                                                    radioController
                                                    .selectedVfo === 0
                                                    ? "#347e98"
                                                    : "#387a48"

                                                FrequencyDigits {
                                                    anchors.centerIn: parent

                                                    vfoNumber:
                                                        radioController
                                                        .selectedVfo
                                                    frequencyValue:
                                                        radioController
                                                        .frequencyText
                                                    large: true
                                                    active: true
                                                }

                                                Rectangle {
                                                    anchors.left:
                                                        parent.left
                                                    anchors.top:
                                                        parent.top
                                                    anchors.bottom:
                                                        parent.bottom
                                                    width: 4
                                                    color:
                                                        radioController
                                                        .selectedVfo === 0
                                                        ? "#42bfff"
                                                        : "#65d779"
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 5

                                                TextField {
                                                    id: mainFrequencyInput

                                                    // Mantener una caja compacta y dejar
                                                    // al botón SET un tamaño cómodo.
                                                    Layout.fillWidth: false
                                                    Layout.preferredWidth: 190
                                                    Layout.minimumWidth: 150
                                                    Layout.preferredHeight: 27
                                                    placeholderText:
                                                        "Frecuencia directa"
                                                    selectByMouse: true
                                                    enabled:
                                                        controlsEnabled()

                                                    ToolTip.visible:
                                                        hovered
                                                    ToolTip.delay: 450
                                                    ToolTip.timeout: 8000
                                                    ToolTip.text:
                                                        "Introduce la frecuencia del VFO activo y pulsa SET o Enter."

                                                    onAccepted:
                                                        radioController
                                                        .setFrequency(text)
                                                }

                                                PanelButton {
                                                    text: "SET"
                                                    Layout.preferredWidth: 62
                                                    Layout.minimumWidth: 58
                                                    tip:
                                                        "Aplica la frecuencia escrita al VFO activo."
                                                    enabled:
                                                        controlsEnabled()

                                                    onClicked:
                                                        radioController
                                                        .setFrequency(
                                                            mainFrequencyInput
                                                            .text
                                                        )
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true

                                                Text {
                                                    text:
                                                        radioController
                                                        .vfoText
                                                        + " · "
                                                        + radioController
                                                          .dataText
                                                    color: "#69c8ff"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                }

                                                Text {
                                                    text:
                                                        radioController
                                                        .splitEnabled
                                                        ? "SPLIT ON"
                                                        : "SPLIT OFF"
                                                    color:
                                                        radioController
                                                        .splitEnabled
                                                        ? "#ff9d72"
                                                        : "#8c8c8c"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        FrameBox {
                                            Layout.preferredWidth: 235
                                            Layout.fillHeight: true
                                            color: "#070707"
                                            raised: true
                                            border.color:
                                                radioController
                                                .splitEnabled
                                                ? "#b34f38"
                                                : "#4b4b4b"

                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled:
                                                    controlsEnabled()

                                                onClicked: {
                                                    if (otherVfoNumber() === 0)
                                                        radioController.selectVfoA()
                                                    else
                                                        radioController.selectVfoB()
                                                }

                                                cursorShape:
                                                    Qt.PointingHandCursor

                                                ToolTip.visible:
                                                    containsMouse
                                                ToolTip.delay: 450
                                                ToolTip.timeout: 8000
                                                ToolTip.text:
                                                    "Selecciona el VFO alternativo."
                                            }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                spacing: 5

                                                RowLayout {
                                                    spacing: 4

                                                    StatusTag {
                                                        caption:
                                                            radioController
                                                            .splitEnabled
                                                            ? "TX"
                                                            : "SUB"
                                                        tagColor:
                                                            radioController
                                                            .splitEnabled
                                                            ? "#a82f2f"
                                                            : "#505050"
                                                    }

                                                    StatusTag {
                                                        caption:
                                                            radioController
                                                            .splitEnabled
                                                            ? "SPLIT"
                                                            : "STBY"
                                                        tagColor:
                                                            radioController
                                                            .splitEnabled
                                                            ? "#6f2424"
                                                            : "#464646"
                                                    }
                                                }

                                                Text {
                                                    text:
                                                        otherVfoModeText()
                                                        + "  "
                                                        + otherVfoFilterText()
                                                        + "  "
                                                        + otherVfoDataText()
                                                    color: "#d8d8d8"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }

                                                FrequencyDigits {
                                                    Layout.alignment:
                                                        Qt.AlignHCenter

                                                    vfoNumber:
                                                        otherVfoNumber()
                                                    frequencyValue:
                                                        otherVfoFrequencyText()
                                                    large: false
                                                    active: false
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true

                                                    Text {
                                                        text:
                                                            "VFO "
                                                            + (otherVfoNumber() === 0
                                                               ? "A"
                                                               : "B")
                                                        color: "#9f9f9f"
                                                        font.pixelSize: 9
                                                    }

                                                    Item {
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        text:
                                                            "TX real "
                                                            + radioController
                                                              .txFrequencyText
                                                        color:
                                                            radioController
                                                            .splitEnabled
                                                            || radioController
                                                               .transmitting
                                                            ? "#e5a278"
                                                            : "#777777"
                                                        font.pixelSize: 9
                                                        font.bold: true

                                                        ToolTip.visible:
                                                            txFrequencyHover
                                                            .hovered
                                                        ToolTip.delay: 450
                                                        ToolTip.timeout: 8000
                                                        ToolTip.text:
                                                            "Frecuencia TX real leída con CI-V 1C 03."

                                                        HoverHandler {
                                                            id: txFrequencyHover
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 15

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 250
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Text {
                                                    Layout.preferredWidth: 34
                                                    text: ""
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text:
                                                        "1    3    5    7    9    +20    +40    +60 dB"
                                                    color: "#9fa7ad"
                                                    font.pixelSize: 8
                                                    font.family:
                                                        "DejaVu Sans Mono"
                                                    horizontalAlignment:
                                                        Text.AlignHCenter
                                                }

                                                Item {
                                                    Layout.preferredWidth: 52
                                                }
                                            }

                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "S"
                                                valueText:
                                                    radioController
                                                    .sMeterText
                                                percent:
                                                    radioController
                                                    .sMeterPercent
                                                multicolor: true
                                            }

                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "PO"
                                                valueText:
                                                    radioController
                                                    .powerMeterText
                                                percent:
                                                    radioController
                                                    .powerMeterPercent
                                                barColor: "#42b7ff"
                                            }

                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "ALC"
                                                valueText:
                                                    radioController
                                                    .alcMeterText
                                                percent:
                                                    radioController
                                                    .alcMeterPercent
                                                barColor: "#aaaaaa"
                                            }

                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "COMP"
                                                valueText:
                                                    radioController
                                                    .compMeterText
                                                percent:
                                                    radioController
                                                    .compMeterPercent
                                                barColor: "#aaaaaa"
                                            }

                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "SWR"
                                                valueText:
                                                    radioController
                                                    .swrMeterText
                                                percent:
                                                    radioController
                                                    .swrMeterPercent
                                                barColor: "#aaaaaa"
                                            }
                                        }

                                        AnalogSMeter {
                                            Layout.preferredWidth: 190
                                            Layout.minimumWidth: 180
                                            Layout.maximumWidth: 195
                                            Layout.minimumHeight: 104
                                            Layout.preferredHeight: 104
                                            Layout.maximumHeight: 104
                                            Layout.alignment:
                                                Qt.AlignVCenter
                                            meterPercent:
                                                radioController
                                                .sMeterPercent
                                            valueText:
                                                radioController
                                                .sMeterText
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: 120
                                            Layout.minimumWidth: 110
                                            spacing: 3

                                            

                                            

                                            

                                            Text {
                                                text:
                                                    "NOTCH  : "
                                                    + (radioController
                                                       .manualNotchEnabled
                                                       ? "MANUAL"
                                                       : radioController
                                                         .autoNotchEnabled
                                                         ? "AUTO"
                                                         : "OFF")
                                                color: "#e2e2e2"
                                                font.pixelSize: 10
                                            }

                                            Text {
                                                text:
                                                    "Vd / Id: "
                                                    + radioController
                                                      .voltageMeterText
                                                    + " / "
                                                    + radioController
                                                      .currentMeterText
                                                color: "#e2e2e2"
                                                font.pixelSize: 10
                                            }
                                        }
                                    }

                                }
                            }

                            FrameBox {
                                id: operatingModeStrip

                                visible: false
                                Layout.fillWidth: true
                                Layout.preferredHeight: 0
                                Layout.minimumHeight: 0
                                Layout.maximumHeight: 0

                                color: "#202020"
                                border.color: "#585858"
                                raised: true

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.preferredWidth: 62
                                        Layout.fillHeight: true
                                        spacing: 1

                                        Item {
                                            Layout.fillHeight: true
                                        }

                                        Text {
                                            Layout.alignment:
                                                Qt.AlignHCenter
                                            text: "MODO"
                                            color: "#aeb7bd"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            Layout.alignment:
                                                Qt.AlignHCenter
                                            text:
                                                radioController
                                                .modeText
                                            color: "#86d8ff"
                                            font.pixelSize: 13
                                            font.bold: true
                                        }

                                        Item {
                                            Layout.fillHeight: true
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillHeight: true
                                        Layout.preferredWidth: 1
                                        color: "#505050"
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        columns: 4
                                        rowSpacing: 4
                                        columnSpacing: 6

                                        Repeater {
                                            model: modeNames

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                text: modelData
                                                textPixelSize: 12
                                                selected:
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.lanMode === modelData
                                                    : radioController.modeText === modelData
                                                activeColor: "#2f72b9"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    if (["RTTY","RTTY-R","SSTV","FT8/FT4"].indexOf(modelData) >= 0)
                                                        selectUsbDataMode()
                                                    else if (applicationLauncher.lanConnected
                                                            && ["LSB","USB","AM","CW","RTTY","FM","CW-R","RTTY-R"].indexOf(modelData) >= 0)
                                                        applicationLauncher.testLanModeName(modelData)
                                                    else
                                                        radioController.setOperatingMode(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            Flickable {
                                id: lowerPanelsViewport

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 120
                                Layout.alignment: Qt.AlignTop

                                clip: true
                                interactive:
                                    contentHeight > height
                                boundsBehavior:
                                    Flickable.StopAtBounds
                                flickableDirection:
                                    Flickable.VerticalFlick

                                contentWidth: width
                                contentHeight:
                                    lowerPanelsRow.height

                                ScrollBar.vertical: ScrollBar {
                                    policy:
                                        lowerPanelsViewport
                                        .contentHeight
                                        > lowerPanelsViewport.height
                                        ? ScrollBar.AsNeeded
                                        : ScrollBar.AlwaysOff
                                }

                                WheelHandler {
                                    acceptedDevices:
                                        PointerDevice.Mouse
                                        | PointerDevice.TouchPad

                                    onWheel: function(event) {
                                        if (lowerPanelsViewport
                                                .contentHeight
                                                <= lowerPanelsViewport
                                                   .height) {
                                            event.accepted = false
                                            return
                                        }

                                        const delta =
                                            event.angleDelta.y !== 0
                                            ? event.angleDelta.y
                                            : event.pixelDelta.y

                                        lowerPanelsViewport.contentY =
                                            Math.max(
                                                0,
                                                Math.min(
                                                    lowerPanelsViewport
                                                    .contentHeight
                                                    - lowerPanelsViewport
                                                      .height,
                                                    lowerPanelsViewport
                                                    .contentY
                                                    - delta
                                                )
                                            )

                                        event.accepted = true
                                    }
                                }

                                RowLayout {
                                    id: lowerPanelsRow

                                    x: 0
                                    y: 0
                                    width:
                                        lowerPanelsViewport.width
                                        - (lowerPanelsViewport
                                           .contentHeight
                                           > lowerPanelsViewport.height
                                           ? 12
                                           : 0)
                                    height: 216
                                    spacing: 6
                                    Layout.alignment: Qt.AlignTop



                                FrameBox {
                                    Layout.preferredWidth: 235
                                    Layout.preferredHeight: 216
                                    Layout.maximumHeight: 216
                                    color: "#1d1d1d"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 6

                                        Text {
                                            text: "VFO / SPLIT"
                                            color: "#ececec"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "SPLIT"
                                                selected:
                                                    radioController
                                                    .splitEnabled
                                                activeColor: "#98501f"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .setSplitEnabled(
                                                        !radioController
                                                        .splitEnabled
                                                    )
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "DATA"
                                                selected:
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.lanDataEnabled
                                                    : radioController.dataMode
                                                activeColor: "#2d7a47"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.setLanDataEnabled(!applicationLauncher.lanDataEnabled, radioController.modeText)
                                                    : radioController.setDataEnabled(!radioController.dataMode)
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "XFC"
                                                selected:
                                                    radioController
                                                    .xfcEnabled
                                                activeColor: "#6e4d8f"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .setXfcEnabled(
                                                        !radioController
                                                        .xfcEnabled
                                                    )
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "A/B"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .exchangeVfos()
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "A=B"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .equalizeVfos()
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "RIT"
                                                selected:
                                                    radioController
                                                    .ritEnabled
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .setRitEnabled(
                                                        !radioController
                                                        .ritEnabled
                                                    )
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "ΔTX"
                                                selected:
                                                    radioController
                                                    .deltaTxEnabled
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .setDeltaTxEnabled(
                                                        !radioController
                                                        .deltaTxEnabled
                                                    )
                                            }
                                        }

                                        SpinBox {
                                            id: ritSpin

                                            Layout.fillWidth: true
                                            from: -9999
                                            to: 9999
                                            stepSize: 10
                                            editable: true
                                            value:
                                                radioController
                                                .ritOffsetHz
                                            enabled:
                                                controlsEnabled()

                                            ToolTip.visible:
                                                hovered
                                            ToolTip.delay: 450
                                            ToolTip.timeout: 8000
                                            ToolTip.text:
                                                "Desplazamiento RIT/ΔTX en Hz."
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "SET"
                                                tip:
                                                    "Aplica el desplazamiento indicado."
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .setRitOffset(
                                                        ritSpin.value
                                                    )
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "CLEAR"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .setRitOffset(0)
                                            }
                                        }

                                        Item {
                                            Layout.fillHeight: true
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                radioController.ritText
                                                + " · "
                                                + radioController
                                                  .deltaTxText
                                            color: "#cdd6dd"
                                            font.pixelSize: 9
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 216
                                    Layout.maximumHeight: 216
                                    spacing: 8

                                    FrameBox {
                                        id: verticalTuningStepPanel

                                        Layout.preferredWidth: 92
                                        Layout.minimumWidth: 92
                                        Layout.maximumWidth: 92
                                        Layout.fillHeight: true
                                        color: "#1d1d1d"

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 5
                                            spacing: 3

                                            Text {
                                                Layout.fillWidth: true
                                                text: "TUNING STEP"
                                                color: "#ececec"
                                                font.pixelSize: 9
                                                font.bold: true
                                                horizontalAlignment:
                                                    Text.AlignHCenter
                                            }



                                            Repeater {
                                                model: stepNames

                                                PanelButton {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 22
                                                    text: modelData
                                                    selected:
                                                        stepIndex
                                                        === index
                                                    activeColor:
                                                        "#2d7cb3"
                                                    enabled:
                                                        controlsEnabled()

                                                    onClicked:
                                                        stepIndex =
                                                            index
                                                }
                                            }

                                            Item {
                                                Layout.fillHeight: true
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        id: tuningWheelColumn

                                        Layout.preferredWidth: 148
                                        Layout.minimumWidth: 148
                                        Layout.maximumWidth: 148
                                        Layout.fillHeight: true
                                        spacing: 6

                                        TuningWheel {
                                            Layout.preferredWidth: 140
                                            Layout.preferredHeight: 140
                                            Layout.alignment:
                                                Qt.AlignTop
                                                | Qt.AlignHCenter
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            spacing: 6

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 32
                                                text: "−"
                                                font.pixelSize: 18
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    tuneSelectedVfo(-1)
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 32
                                                text: "+"
                                                font.pixelSize: 18
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    tuneSelectedVfo(1)
                                            }
                                        }

                                        Item {
                                            Layout.fillHeight: true
                                        }
                                    }

                                    RowLayout {
                                        id: receiverProcessingPanel

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 6

                                        

                                        FrameBox {
                                            id: noiseLevelsPanel

                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 190
                                            Layout.fillHeight: true
                                            color: "#191c1e"

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 5
                                                spacing: 4

                                                FrameBox {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 52
                                                    Layout.minimumHeight: 52
                                                    color: "#14181a"
                                                    border.color: "#43525a"

                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 5
                                                        spacing: 4

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: "NB / NR LEVEL"
                                                            color: "#f2f4f5"
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                            horizontalAlignment:
                                                                Text.AlignHCenter
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 14
                                                            spacing: 5

                                                            Text {
                                                                Layout.preferredWidth: 20
                                                                text: "NB"
                                                                color: "#dce2e5"
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                            }

                                                            Slider {
                                                                id: horizontalNbLevelSlider

                                                                Layout.fillWidth: true
                                                                from: 0
                                                                to: 100
                                                                stepSize: 1
                                                                value:
                                                                    radioController
                                                                    .noiseBlankerLevel
                                                                enabled:
                                                                    controlsEnabled()

                                                                onMoved:
                                                                    radioController
                                                                    .setNoiseBlankerLevel(
                                                                        value
                                                                    )
                                                            }

                                                            Text {
                                                                Layout.preferredWidth: 28
                                                                text:
                                                                    Math.round(
                                                                        radioController
                                                                        .noiseBlankerLevel
                                                                    )
                                                                color: "#9edcf4"
                                                                font.family:
                                                                    "DejaVu Sans Mono"
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                                horizontalAlignment:
                                                                    Text.AlignRight
                                                            }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 14
                                                            spacing: 5

                                                            Text {
                                                                Layout.preferredWidth: 20
                                                                text: "NR"
                                                                color: "#dce2e5"
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                            }

                                                            Slider {
                                                                id: horizontalNrLevelSlider

                                                                Layout.fillWidth: true
                                                                from: 0
                                                                to: 100
                                                                stepSize: 1
                                                                value:
                                                                    radioController
                                                                    .noiseReductionLevel
                                                                enabled:
                                                                    controlsEnabled()

                                                                onMoved:
                                                                    radioController
                                                                    .setNoiseReductionLevel(
                                                                        value
                                                                    )
                                                            }

                                                            Text {
                                                                Layout.preferredWidth: 28
                                                                text:
                                                                    Math.round(
                                                                        radioController
                                                                        .noiseReductionLevel
                                                                    )
                                                                color: "#a8e0b9"
                                                                font.family:
                                                                    "DejaVu Sans Mono"
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                                horizontalAlignment:
                                                                    Text.AlignRight
                                                            }
                                                        }
                                                    }
                                                }

                                                FrameBox {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    color: "#14181a"
                                                    border.color: "#43525a"

                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 4
                                                        spacing: 3

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: "FILTER CURVE"
                                                            color: "#f2f4f5"
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                            horizontalAlignment:
                                                                Text.AlignHCenter
                                                        }

                                                        FilterCurveDisplay {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                                            Layout.minimumHeight: 62
                                                            Layout.preferredHeight: 70
                                                            filterText:
                                                                radioController.filterText
                                                            filterShape:
                                                                radioController.filterShape
                                                            modeText:
                                                                radioController.modeText
                                                            pbt1:
                                                                radioController.pbt1
                                                            pbt2:
                                                                radioController.pbt2
                                                            manualNotchEnabled:
                                                                radioController.manualNotchEnabled
                                                            manualNotchPosition:
                                                                radioController.manualNotchPosition
                                                            manualNotchWidth:
                                                                radioController.manualNotchWidth
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 6

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text:
                                                                    "P1 "
                                                                    + Math.round(
                                                                        radioController.pbt1
                                                                    )
                                                                color: "#8fd4ff"
                                                                font.pixelSize: 8
                                                                font.bold: true
                                                                horizontalAlignment:
                                                                    Text.AlignLeft
                                                            }

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text:
                                                                    "P2 "
                                                                    + Math.round(
                                                                        radioController.pbt2
                                                                    )
                                                                color: "#b4e4ff"
                                                                font.pixelSize: 8
                                                                font.bold: true
                                                                horizontalAlignment:
                                                                    Text.AlignHCenter
                                                            }

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text:
                                                                    radioController
                                                                    .manualNotchEnabled
                                                                    ? "NOTCH "
                                                                      + radioController.manualNotchWidthText
                                                                    : "NOTCH OFF"
                                                                color:
                                                                    radioController
                                                                    .manualNotchEnabled
                                                                    ? "#d7b1ff"
                                                                    : "#8b979c"
                                                                font.pixelSize: 8
                                                                font.bold: true
                                                                horizontalAlignment:
                                                                    Text.AlignRight
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                                            }
                            }
                        }






                        }

                        FrameBox {
                            id: horizontalRxPanel

                            Layout.fillWidth: true
                            Layout.minimumHeight: 138
                            Layout.preferredHeight: 138
                            Layout.maximumHeight: 138
                            color: "#25282a"
                            border.color: "#53616a"
                            raised: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                FrameBox {
                                    Layout.preferredWidth: 140
                                    Layout.fillHeight: true
                                    color: "#191c1e"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 5

                                        Text {
                                            Layout.fillWidth: true
                                            text: "FILTER"
                                            color: "#f2f4f5"
                                            font.pixelSize: 11
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "FIL1"
                                                selected: radioController.filterText === "FIL1"
                                                enabled: controlsEnabled()
                                                onClicked: radioController.setFilter(1)
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "FIL2"
                                                selected: radioController.filterText === "FIL2"
                                                enabled: controlsEnabled()
                                                onClicked: radioController.setFilter(2)
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "FIL3"
                                                selected: radioController.filterText === "FIL3"
                                                enabled: controlsEnabled()
                                                onClicked: radioController.setFilter(3)
                                            }
                                        }

                                        PanelButton {
                                            Layout.fillWidth: true
                                            text:
                                                radioController.filterText === "FIL3"
                                                ? "FIXED"
                                                : radioController.filterShapeText
                                            selected:
                                                radioController.filterText !== "FIL3"
                                            activeColor:
                                                radioController.filterText === "FIL3"
                                                ? "#4f575c"
                                                : "#476a7b"
                                            tip:
                                                radioController.filterText === "FIL3"
                                                ? "En FIL3 la forma del filtro es fija y no se puede cambiar."
                                                : "Alterna la forma del filtro entre SHARP y SOFT."
                                            enabled:
                                                controlsEnabled()
                                                && radioController.filterText !== "FIL3"

                                            onClicked:
                                                radioController.setFilterShape(
                                                    radioController.filterShape === 0
                                                    ? 1
                                                    : 0
                                                )
                                        }

                                    }
                                }

                                FrameBox {
                                    Layout.preferredWidth: 274
                                    Layout.minimumWidth: 274
                                    Layout.maximumWidth: 274
                                    Layout.fillHeight: true
                                    color: "#191c1e"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 4

                                        TwinPbtControl {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 204
                                            Layout.fillHeight: true
                                            compact: true
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: 52
                                            Layout.minimumWidth: 52
                                            Layout.maximumWidth: 52
                                            Layout.fillHeight: true
                                            spacing: 5

                                            Text {
                                                Layout.fillWidth: true
                                                text: "PBT"
                                                color: "#d9dee1"
                                                font.pixelSize: 9
                                                font.bold: true
                                                horizontalAlignment: Text.AlignHCenter
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.minimumHeight: 86
                                                Layout.fillHeight: true
                                                text: "CLR"
                                                tip: "Centra simultáneamente PBT1 y PBT2."
                                                enabled: controlsEnabled()

                                                onClicked:
                                                    radioController
                                                    .clearTwinPbt()
                                            }
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 226
                                    Layout.fillHeight: true
                                    color: "#191c1e"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: "NOTCH"
                                            color: "#ededed"
                                            font.pixelSize: 9
                                            font.bold: true
                                            horizontalAlignment:
                                                Text.AlignHCenter
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 5

                                            KnobControl {
                                                Layout.minimumWidth: 82
                                                Layout.preferredWidth: 92
                                                Layout.maximumWidth: 92
                                                Layout.fillHeight: true
                                                compact: true
                                                caption: "POS"
                                                currentValue:
                                                    radioController
                                                    .manualNotchPosition
                                                accentColor: "#c8a4ff"
                                                applyFunction:
                                                    function(value) {
                                                        radioController
                                                        .setManualNotchPosition(
                                                            value
                                                        )
                                                    }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 4

                                                PanelButton {
                                                    Layout.fillWidth: true
                                                    text: "CLR"
                                                    enabled:
                                                        controlsEnabled()

                                                    onClicked:
                                                        radioController
                                                        .setManualNotchPosition(
                                                            50
                                                        )
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        text: "W"
                                                        selected:
                                                            radioController
                                                            .manualNotchWidth
                                                            === 0
                                                        enabled:
                                                            controlsEnabled()

                                                        onClicked:
                                                            radioController
                                                            .setManualNotchWidth(
                                                                0
                                                            )
                                                    }

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        text: "M"
                                                        selected:
                                                            radioController
                                                            .manualNotchWidth
                                                            === 1
                                                        enabled:
                                                            controlsEnabled()

                                                        onClicked:
                                                            radioController
                                                            .setManualNotchWidth(
                                                                1
                                                            )
                                                    }

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        text: "N"
                                                        selected:
                                                            radioController
                                                            .manualNotchWidth
                                                            === 2
                                                        enabled:
                                                            controlsEnabled()

                                                        onClicked:
                                                            radioController
                                                            .setManualNotchWidth(
                                                                2
                                                            )
                                                    }
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        text: "AN"
                                                        selected:
                                                            radioController
                                                            .autoNotchEnabled
                                                        enabled:
                                                            controlsEnabled()

                                                        onClicked:
                                                            radioController
                                                            .setAutoNotchEnabled(
                                                                !radioController
                                                                .autoNotchEnabled
                                                            )
                                                    }

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        text: "MN"
                                                        selected:
                                                            radioController
                                                            .manualNotchEnabled
                                                        enabled:
                                                            controlsEnabled()

                                                        onClicked:
                                                            radioController
                                                            .setManualNotchEnabled(
                                                                !radioController
                                                                .manualNotchEnabled
                                                            )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }




                            }
                        }

                    }
                }

                        FrameBox {
                            id: bandAudioPanel

                            Layout.preferredWidth: 118
                            Layout.minimumWidth: 118
                            Layout.maximumWidth: 118
                            Layout.fillHeight: true
                            color: "#2c2c2c"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 4

                                SidePanelGroup {
                                    caption: "BANDAS"
                                    accentColor: "#4d9fc1"

                                    ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Repeater {
                                        model: bandDefinitions

                                        PanelButton {
                                            id: directBandButton

                                            Layout.fillWidth: true
                                            textPixelSize: 12
                                            text: modelData.name
                                            tip:
                                                bandButtonHelp(index)
                                                + " · "
                                                + modelData.label
                                            selected:
                                                currentBandName
                                                === modelData.name
                                            activeColor: "#4a4a4a"
                                            enabled:
                                                controlsEnabled()

                                            contentItem: RowLayout {
                                                spacing: 4

                                                Text {
                                                    Layout.fillWidth: true
                                                    text:
                                                        modelData.name
                                                    color:
                                                        directBandButton.enabled
                                                        ? "#f1f1f1"
                                                        : "#818181"
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    horizontalAlignment:
                                                        Text.AlignHCenter
                                                    verticalAlignment:
                                                        Text.AlignVCenter
                                                    elide:
                                                        Text.ElideRight
                                                }

                                                Text {
                                                    Layout.preferredWidth: 40
                                                    text:
                                                        modelData.label
                                                    color:
                                                        !directBandButton.enabled
                                                        ? "#6f777b"
                                                        : directBandButton.selected
                                                          ? "#ffd27a"
                                                          : "#69d6ff"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    horizontalAlignment:
                                                        Text.AlignHCenter
                                                    verticalAlignment:
                                                        Text.AlignVCenter
                                                }
                                            }

                                            onClicked:
                                                selectBand(index)
                                        }
                                    }
                                }

                                }

                                Item {
                                    Layout.fillHeight: true
                                }

                                SidePanelGroup {
                                    caption: "AUDIO / SQL"
                                    accentColor: "#55a996"

                                KnobControl {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 94
                                    Layout.maximumHeight: 94
                                    compact: true
                                    caption: "AF"
                                    currentValue:
                                        radioController.afGain
                                    accentColor: "#69d0ff"
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setAfGain(value)
                                        }
                                }

                                KnobControl {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 94
                                    Layout.maximumHeight: 94
                                    compact: true
                                    caption: "SQL"
                                    currentValue:
                                        radioController.squelch
                                    accentColor: "#80d8c8"
                                    applyFunction:
                                        function(value) {
                                            radioController
                                            .setSquelch(value)
                                        }
                                }

                                }
                            }
                        }


            }

            FrameBox {
                id: applicationStatusBar

                Layout.fillWidth: true
                Layout.minimumHeight: 26
                Layout.preferredHeight: 26
                Layout.maximumHeight: 26
                color: "#171a1c"
                border.color: "#50595e"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    Text {
                        text:
                            radioController.connected
                            ? "CI-V CONECTADO"
                            : "CI-V DESCONECTADO"
                        color:
                            radioController.connected
                            ? "#8fd49b"
                            : "#ef9a9a"
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 5
                        Layout.bottomMargin: 5
                        color: "#4e575c"
                    }

                    Text {
                        text:
                            radioController.txRxText
                        color:
                            radioController.transmitting
                            ? "#ff8d8d"
                            : "#8ff09d"
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text:
                            radioController.actionStatus
                        color: "#d4dade"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }

                    Text {
                        text:
                            radioController.memoryModeActive
                            ? radioController
                              .selectedMemoryChannelText
                            : radioController.vfoText
                        color: "#9edcf4"
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Text {
                        text:
                            "STEP "
                            + stepNames[stepIndex]
                        color: "#72d1ff"
                        font.pixelSize: 9
                        font.bold: true
                    }

                    Text {
                        text:
                            radioController.overflow
                            ? "OVF OVER"
                            : "OVF OK"
                        color:
                            radioController.overflow
                            ? "#ff8585"
                            : "#8fd49b"
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
            }
        }
    }


    Window {
        id: remoteServerWindow

        width: 620
        height: 600
        minimumWidth: 590
        minimumHeight: 560
        visible: false
        title: "Control remoto por Internet / VPN"
        color: "#30363b"
        flags: Qt.Window
        transientParent: window

        onClosing: function(close) {
            remoteServerVisible = false
            close.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            color: "#30363b"

            ScrollView {
                anchors.fill: parent
                anchors.margins: 14
                clip: true

                ColumnLayout {
                    width: Math.max(540, remoteServerWindow.width - 44)
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true

                        Rectangle {
                            width: 13
                            height: 13
                            radius: 7
                            color:
                                remoteServer.running
                                ? "#57d47c"
                                : "#777777"
                        }

                        Text {
                            text:
                                remoteServer.running
                                ? "SERVIDOR REMOTO ACTIVO"
                                : "SERVIDOR REMOTO DETENIDO"
                            color: "#f2f4f5"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: remoteServer.activeClients + " cliente(s)"
                            color: "#b9c8d0"
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        radius: 5
                        color: "#20272c"
                        border.color: "#56656e"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            Text {
                                text: "Primera versión remota: control RX y ajustes principales"
                                color: "#82d8ff"
                                font.bold: true
                                font.pixelSize: 12
                            }

                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "PTT y TUNE no están disponibles por Internet. Se recomienda acceder mediante Tailscale/WireGuard; no abras directamente el puerto 7300 en el router."
                                color: "#d6dde1"
                                font.pixelSize: 10
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text:
                                remoteServer.running
                                ? "DETENER SERVIDOR"
                                : "INICIAR SERVIDOR"
                            Layout.preferredHeight: 36
                            onClicked:
                                remoteServer.running
                                ? remoteServer.stop()
                                : remoteServer.start()
                        }

                        Button {
                            text: "ABRIR EN ESTE PC"
                            enabled: remoteServer.running
                            Layout.preferredHeight: 36
                            onClicked:
                                Qt.openUrlExternally(
                                    remoteServer.localTestUrl
                                )
                        }

                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Puerto"
                            color: "#e8ecee"
                            font.pixelSize: 11
                        }

                        SpinBox {
                            id: remotePortSpin
                            from: 1024
                            to: 65535
                            value: remoteServer.port
                            editable: true
                            Layout.preferredWidth: 120
                        }

                        Button {
                            text: "APLICAR"
                            onClicked:
                                remoteServer.setPort(
                                    remotePortSpin.value
                                )
                        }

                        CheckBox {
                            id: remoteAutoStartCheck
                            text: "ACTIVAR INTERNET AL INICIAR EL PROGRAMA"
                            checked: remoteServer.autoStart
                            onToggled:
                                remoteServer.setAutoStart(
                                    checked
                                )

                            contentItem: Text {
                                text: remoteAutoStartCheck.text
                                color: "#f5f7f8"
                                font.pixelSize: 11
                                font.bold: true
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: remoteAutoStartCheck.indicator.width
                                             + remoteAutoStartCheck.spacing
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Text {
                        text: "Direcciones disponibles"
                        color: "#f0f2f4"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 105
                        radius: 4
                        color: "#151a1e"
                        border.color: "#56656e"

                        TextArea {
                            anchors.fill: parent
                            anchors.margins: 6
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            text: remoteServer.accessUrls.join("\n")
                            color: "#d9f3ff"
                            font.family: "monospace"
                            font.pixelSize: 11
                            background: null
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Clave remota del propietario"
                            color: "#f0f2f4"
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: "COPIAR"
                            onClicked:
                                radioController.copyTextToClipboard(
                                    remoteServer.accessToken
                                )
                        }

                        Button {
                            text: "ALEATORIA"
                            onClicked: {
                                remoteServer.regenerateToken()
                                ownerRemoteKey.text = remoteServer.accessToken
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextField {
                            id: ownerRemoteKey
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            text: remoteServer.accessToken
                            placeholderText: "8 letras o números"
                            maximumLength: 8
                            selectByMouse: true
                            horizontalAlignment: TextInput.AlignHCenter
                            color: "#f6d977"
                            font.family: "monospace"
                            font.pixelSize: 22
                            font.bold: true
                            font.letterSpacing: 3
                            inputMethodHints:
                                Qt.ImhUppercaseOnly
                                | Qt.ImhNoPredictiveText

                            onTextEdited: {
                                const clean = text.toUpperCase()
                                    .replace(/[^A-Z0-9]/g, "")
                                    .slice(0, 8)
                                if (clean !== text)
                                    text = clean
                            }

                            onAccepted: {
                                if (remoteServer.setAccessToken(text))
                                    text = remoteServer.accessToken
                            }
                        }

                        Button {
                            Layout.preferredHeight: 52
                            text: "FIJAR CLAVE"
                            enabled: ownerRemoteKey.text.length === 8
                            onClicked: {
                                if (remoteServer.setAccessToken(
                                        ownerRemoteKey.text))
                                    ownerRemoteKey.text =
                                        remoteServer.accessToken
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "La clave queda guardada y será la misma tras reiniciar el programa. Así puedes memorizarla y entrar desde fuera sin consultar antes el PC principal. Debe tener exactamente 8 letras o números. Úsala como protección adicional dentro de una LAN/VPN privada (Tailscale/WireGuard); no expongas directamente el puerto HTTP a Internet."
                        color: "#b9c8d0"
                        font.pixelSize: 10
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        radius: 4
                        color: "#20272c"
                        border.color: "#485862"

                        Text {
                            anchors.fill: parent
                            anchors.margins: 9
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                            text: remoteServer.status
                            color: remoteServer.running ? "#8fe5a9" : "#d5dde1"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

    }

    MorseTrainerWindow {
        id: morseTrainerWindow

        // Ventana independiente: permite minimizar la principal sin ocultar
        // también el entrenador Morse.
        transientParent: null
        flags: Qt.Window
        visible: false

        onVisibleChanged: {
            if (window.morseTrainerVisible !== visible)
                window.morseTrainerVisible = visible

            if (visible)
                window.enterMorseWorkspace()
            else
                window.leaveMorseWorkspace()
        }
    }

    Window {
        id: scopeWindow

        property var waterfallLines: []
        property int maximumWaterfallLines: 118
        property int spectrumAxisWidth: 62
        property var spanOptions: [
            { label: "2,5 kHz", value: 2500 },
            { label: "5 kHz", value: 5000 },
            { label: "10 kHz", value: 10000 },
            { label: "25 kHz", value: 25000 },
            { label: "50 kHz", value: 50000 },
            { label: "100 kHz", value: 100000 },
            { label: "250 kHz", value: 250000 },
            { label: "500 kHz", value: 500000 }
        ]
        property var waterfallPalette: [
            "#05070b",
            "#07121d",
            "#08243a",
            "#073e58",
            "#075e72",
            "#07858c",
            "#13a89a",
            "#42c582",
            "#8bd360",
            "#c8dc48",
            "#f4d742",
            "#f5a63b",
            "#ed6a35",
            "#df3938",
            "#ef6eb3",
            "#fff4ff"
        ]

        transientParent: window
        visible: scopeVisible
        width: 930
        height: 650
        minimumWidth: 720
        minimumHeight: 500
        flags: Qt.Tool
        color: "#0c1114"
        title: "Spectrum Scope y Waterfall · IC-7300MK2"

        function frequencyText(frequencyHz) {
            const value =
                Number(frequencyHz)

            if (!isFinite(value)
                    || value <= 0) {
                return "—"
            }

            return (value / 1000000.0)
                   .toLocaleString(
                       Qt.locale(),
                       "f",
                       6
                   )
                   + " MHz"
        }

        function lowerFrequency() {
            const lower =
                Number(
                    radioController
                    .scopeLowerFrequencyHz
                )

            if (lower > 0)
                return lower

            const center =
                Number(
                    radioController
                    .frequencyHz
                )
            const half =
                Number(
                    radioController
                    .scopeSpanHz
                ) / 2

            return Math.max(
                0,
                center - half
            )
        }

        function higherFrequency() {
            const higher =
                Number(
                    radioController
                    .scopeHigherFrequencyHz
                )

            if (higher > lowerFrequency())
                return higher

            return lowerFrequency()
                   + Math.max(
                       2500,
                       Number(
                           radioController
                           .scopeSpanHz
                       )
                   )
        }

        function currentFrequencyRatio() {
            const lower =
                lowerFrequency()
            const higher =
                higherFrequency()
            const frequency =
                Number(
                    radioController
                    .frequencyHz
                )

            if (higher <= lower)
                return 0.5

            return Math.max(
                0,
                Math.min(
                    1,
                    (frequency - lower)
                    / (higher - lower)
                )
            )
        }

        function spanIndex() {
            const span =
                Number(
                    radioController
                    .scopeSpanHz
                )

            let bestIndex = 0
            let bestDistance =
                Number.MAX_VALUE

            for (let index = 0;
                 index < spanOptions.length;
                 ++index) {
                const distance =
                    Math.abs(
                        Number(
                            spanOptions[index]
                            .value
                        ) - span
                    )

                if (distance < bestDistance) {
                    bestDistance = distance
                    bestIndex = index
                }
            }

            return bestIndex
        }

        function appendWaterfallLine(values) {
            if (!values
                    || values.length < 2) {
                return
            }

            let copiedLine = []

            for (let index = 0;
                 index < values.length;
                 ++index) {
                copiedLine.push(
                    Number(values[index])
                )
            }

            let updated =
                waterfallLines.slice(0)
            updated.unshift(copiedLine)

            if (updated.length
                    > maximumWaterfallLines) {
                updated.length =
                    maximumWaterfallLines
            }

            waterfallLines = updated
        }

        function clearWaterfall() {
            waterfallLines = []
            waterfallCanvas.requestPaint()
        }

        function tuneAtPosition(
            pointerX,
            availableWidth
        ) {
            if (!radioController.connected
                    || availableWidth <= 0) {
                return
            }

            const ratio =
                Math.max(
                    0,
                    Math.min(
                        1,
                        pointerX
                        / availableWidth
                    )
                )
            const frequency =
                lowerFrequency()
                + ratio
                  * (higherFrequency()
                     - lowerFrequency())

            radioController.setVfoFrequency(
                radioController.selectedVfo,
                String(
                    Math.round(frequency)
                )
            )
        }

        function colorForLevel(level) {
            const bounded =
                Math.max(
                    0,
                    Math.min(
                        160,
                        Number(level)
                    )
                )
            const index =
                Math.max(
                    0,
                    Math.min(
                        waterfallPalette.length - 1,
                        Math.floor(
                            bounded
                            / 160
                            * waterfallPalette.length
                        )
                    )
                )

            return waterfallPalette[index]
        }

        onVisibleChanged: {
            if (visible) {
                scopeSpanBox.currentIndex =
                    spanIndex()

                if (radioController.connected) {
                    radioController
                    .startSpectrumScope()
                }
            } else {
                radioController
                .stopSpectrumScope()
            }
        }

        onClosing: function(close) {
            close.accepted = false
            scopeVisible = false
            radioController
            .stopSpectrumScope()
        }

        Connections {
            target: radioController

            function onScopeWaveformChanged() {
                scopeWindow.appendWaterfallLine(
                    radioController
                    .scopeSpectrumData
                )
                spectrumCanvas.requestPaint()

                if (radioController
                        .scopeFrameCounter % 2 === 0) {
                    waterfallCanvas.requestPaint()
                }
            }

            function onScopeStateChanged() {
                scopeSpanBox.currentIndex =
                    scopeWindow.spanIndex()
                spectrumCanvas.requestPaint()
                waterfallCanvas.requestPaint()
            }

            function onFrequencyChanged() {
                spectrumCanvas.requestPaint()
                waterfallCanvas.requestPaint()
            }

            function onConnectedChanged() {
                if (scopeVisible
                        && radioController.connected) {
                    radioController
                    .startSpectrumScope()
                } else if (!radioController.connected) {
                    spectrumCanvas.requestPaint()
                    waterfallCanvas.requestPaint()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#0c1114"
            border.color: "#527382"
            border.width: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    spacing: 7

                    Text {
                        text: "SPECTRUM SCOPE"
                        color: "#e9f7fb"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    StatusTag {
                        caption:
                            !radioController.connected
                            ? "DESCONECTADO"
                            : radioController
                              .scopeRunning
                              ? "STREAM · "
                                + radioController
                                  .scopeFrameCounter
                              : "DETENIDO"
                        tagColor:
                            !radioController.connected
                            ? "#684349"
                            : radioController
                              .scopeRunning
                              ? "#256f63"
                              : "#49545a"
                    }

                    StatusTag {
                        caption:
                            radioController
                            .scopeModeText
                            + " · "
                            + radioController
                              .scopeSpanText
                        tagColor: "#315d74"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PanelButton {
                        Layout.preferredWidth: 92
                        Layout.preferredHeight: 32
                        text:
                            radioController
                            .scopeRunning
                            ? "STOP"
                            : "START"
                        selected:
                            radioController
                            .scopeRunning
                        activeColor: "#2e7b69"
                        enabled:
                            radioController.connected

                        onClicked:
                            radioController
                            .scopeRunning
                            ? radioController
                              .stopSpectrumScope()
                            : radioController
                              .startSpectrumScope()
                    }

                    PanelButton {
                        Layout.preferredWidth: 82
                        Layout.preferredHeight: 32
                        text: "CERRAR"

                        onClicked:
                            scopeVisible = false
                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    color: "#161d21"
                    border.color: "#3f5863"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        Text {
                            text: "MODE"
                            color: "#b9c8cf"
                            font.pixelSize: 9
                            font.bold: true
                        }

                        ComboBox {
                            id: scopeModeBox

                            Layout.preferredWidth: 114
                            model: [
                                "CENTER",
                                "FIXED",
                                "SCROLL-C",
                                "SCROLL-F"
                            ]
                            currentIndex:
                                radioController
                                .scopeMode
                            enabled:
                                radioController.connected

                            onActivated:
                                radioController
                                .setSpectrumScopeMode(
                                    currentIndex
                                )
                        }

                        Text {
                            text: "SPAN"
                            color: "#b9c8cf"
                            font.pixelSize: 9
                            font.bold: true
                        }

                        ComboBox {
                            id: scopeSpanBox

                            Layout.preferredWidth: 116
                            model:
                                scopeWindow.spanOptions
                            textRole: "label"
                            enabled:
                                radioController.connected
                                && (radioController
                                    .scopeMode === 0
                                    || radioController
                                       .scopeMode === 2)

                            onActivated: {
                                scopeWindow.clearWaterfall()
                                radioController
                                .setSpectrumScopeSpan(
                                    Number(
                                        scopeWindow
                                        .spanOptions[
                                            currentIndex
                                        ].value
                                    )
                                )
                            }
                        }

                        Text {
                            text: "SPEED"
                            color: "#b9c8cf"
                            font.pixelSize: 9
                            font.bold: true
                        }

                        Repeater {
                            model: [
                                "FAST",
                                "MID",
                                "SLOW"
                            ]

                            PanelButton {
                                required property int index
                                required property string modelData

                                Layout.preferredWidth: 58
                                Layout.preferredHeight: 30
                                text: modelData
                                selected:
                                    radioController
                                    .scopeSweepSpeed
                                    === index
                                enabled:
                                    radioController.connected

                                onClicked:
                                    radioController
                                    .setSpectrumScopeSweepSpeed(
                                        index
                                    )
                            }
                        }

                        PanelButton {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 30
                            text:
                                radioController
                                .scopeVbwWide
                                ? "VBW W"
                                : "VBW N"
                            selected:
                                radioController
                                .scopeVbwWide
                            activeColor: "#4d6f88"
                            enabled:
                                radioController.connected

                            onClicked:
                                radioController
                                .setSpectrumScopeVbwWide(
                                    !radioController
                                     .scopeVbwWide
                                )
                        }

                        PanelButton {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 30
                            text: "HOLD"
                            selected:
                                radioController
                                .scopeHold
                            activeColor: "#7d6235"
                            enabled:
                                radioController.connected

                            onClicked:
                                radioController
                                .setSpectrumScopeHold(
                                    !radioController
                                     .scopeHold
                                )
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        PanelButton {
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 30
                            text: "CLEAR WF"

                            onClicked:
                                scopeWindow
                                .clearWaterfall()
                        }
                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 235
                    Layout.minimumHeight: 170
                    color: "#071015"
                    border.color: "#315565"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 3

                        Canvas {
                            id: spectrumCanvas

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            antialiasing: true

                            onWidthChanged:
                                requestPaint()
                            onHeightChanged:
                                requestPaint()

                            onPaint: {
                                const ctx =
                                    getContext("2d")
                                const w = width
                                const h = height
                                const data =
                                    radioController
                                    .scopeSpectrumData
                                const axisWidth =
                                    Math.min(
                                        scopeWindow
                                        .spectrumAxisWidth,
                                        Math.max(
                                            48,
                                            w * 0.14
                                        )
                                    )
                                const plotLeft =
                                    axisWidth
                                const plotRight =
                                    Math.max(
                                        plotLeft + 1,
                                        w - 3
                                    )
                                const plotWidth =
                                    plotRight - plotLeft
                                const plotTop = 8
                                const plotBottom =
                                    Math.max(
                                        plotTop + 1,
                                        h - 8
                                    )
                                const plotHeight =
                                    plotBottom - plotTop

                                ctx.reset()
                                ctx.clearRect(
                                    0,
                                    0,
                                    w,
                                    h
                                )

                                const background =
                                    ctx.createLinearGradient(
                                        0,
                                        0,
                                        0,
                                        h
                                    )
                                background.addColorStop(
                                    0,
                                    "#0d2029"
                                )
                                background.addColorStop(
                                    1,
                                    "#03080b"
                                )
                                ctx.fillStyle =
                                    background
                                ctx.fillRect(
                                    0,
                                    0,
                                    w,
                                    h
                                )

                                ctx.fillStyle =
                                    "rgba(3,8,11,0.78)"
                                ctx.fillRect(
                                    0,
                                    0,
                                    plotLeft,
                                    h
                                )

                                ctx.lineWidth = 1
                                ctx.strokeStyle =
                                    "#183945"

                                for (let column = 0;
                                     column <= 10;
                                     ++column) {
                                    const x =
                                        plotLeft
                                        + column
                                          * plotWidth / 10

                                    ctx.beginPath()
                                    ctx.moveTo(
                                        x,
                                        plotTop
                                    )
                                    ctx.lineTo(
                                        x,
                                        plotBottom
                                    )
                                    ctx.stroke()
                                }

                                for (let row = 0;
                                     row <= 4;
                                     ++row) {
                                    const y =
                                        plotTop
                                        + row
                                          * plotHeight / 4

                                    ctx.beginPath()
                                    ctx.moveTo(
                                        plotLeft,
                                        y
                                    )
                                    ctx.lineTo(
                                        plotRight,
                                        y
                                    )
                                    ctx.stroke()
                                }

                                ctx.strokeStyle =
                                    "#527586"
                                ctx.lineWidth = 1.2
                                ctx.beginPath()
                                ctx.moveTo(
                                    plotLeft,
                                    plotTop
                                )
                                ctx.lineTo(
                                    plotLeft,
                                    plotBottom
                                )
                                ctx.stroke()

                                ctx.fillStyle =
                                    "#d7edf5"
                                ctx.font =
                                    "bold 13px 'DejaVu Sans Mono'"
                                ctx.textAlign =
                                    "right"
                                ctx.textBaseline =
                                    "middle"

                                for (let labelRow = 0;
                                     labelRow <= 4;
                                     ++labelRow) {
                                    const labelY =
                                        plotTop
                                        + labelRow
                                          * plotHeight / 4
                                    const decibels =
                                        -labelRow * 20

                                    ctx.fillText(
                                        String(decibels),
                                        plotLeft - 7,
                                        labelY
                                    )
                                }

                                ctx.save()
                                ctx.translate(
                                    11,
                                    h / 2
                                )
                                ctx.rotate(
                                    -Math.PI / 2
                                )
                                ctx.fillStyle =
                                    "#91b8c6"
                                ctx.font =
                                    "bold 11px Sans"
                                ctx.textAlign =
                                    "center"
                                ctx.textBaseline =
                                    "middle"
                                ctx.fillText(
                                    "dB REL.",
                                    0,
                                    0
                                )
                                ctx.restore()

                                if (data
                                        && data.length > 1) {
                                    const fill =
                                        ctx.createLinearGradient(
                                            0,
                                            plotTop,
                                            0,
                                            plotBottom
                                        )
                                    fill.addColorStop(
                                        0,
                                        "rgba(102,225,255,0.56)"
                                    )
                                    fill.addColorStop(
                                        1,
                                        "rgba(29,111,146,0.06)"
                                    )

                                    ctx.beginPath()

                                    for (let index = 0;
                                         index < data.length;
                                         ++index) {
                                        const x =
                                            plotLeft
                                            + index
                                              * plotWidth
                                              / (data.length - 1)
                                        const value =
                                            Math.max(
                                                0,
                                                Math.min(
                                                    160,
                                                    Number(
                                                        data[index]
                                                    )
                                                )
                                            )
                                        const y =
                                            plotBottom
                                            - value
                                              / 160
                                              * plotHeight

                                        if (index === 0) {
                                            ctx.moveTo(
                                                x,
                                                y
                                            )
                                        } else {
                                            ctx.lineTo(
                                                x,
                                                y
                                            )
                                        }
                                    }

                                    ctx.lineTo(
                                        plotRight,
                                        plotBottom
                                    )
                                    ctx.lineTo(
                                        plotLeft,
                                        plotBottom
                                    )
                                    ctx.closePath()
                                    ctx.fillStyle = fill
                                    ctx.fill()

                                    ctx.beginPath()

                                    for (let point = 0;
                                         point < data.length;
                                         ++point) {
                                        const x =
                                            plotLeft
                                            + point
                                              * plotWidth
                                              / (data.length - 1)
                                        const value =
                                            Math.max(
                                                0,
                                                Math.min(
                                                    160,
                                                    Number(
                                                        data[point]
                                                    )
                                                )
                                            )
                                        const y =
                                            plotBottom
                                            - value
                                              / 160
                                              * plotHeight

                                        if (point === 0) {
                                            ctx.moveTo(
                                                x,
                                                y
                                            )
                                        } else {
                                            ctx.lineTo(
                                                x,
                                                y
                                            )
                                        }
                                    }

                                    ctx.strokeStyle =
                                        "#80e8ff"
                                    ctx.lineWidth = 1.5
                                    ctx.stroke()
                                }

                                const markerX =
                                    plotLeft
                                    + scopeWindow
                                      .currentFrequencyRatio()
                                      * plotWidth

                                ctx.strokeStyle =
                                    "#ffd45f"
                                ctx.lineWidth = 1.2
                                ctx.beginPath()
                                ctx.moveTo(
                                    markerX,
                                    plotTop
                                )
                                ctx.lineTo(
                                    markerX,
                                    plotBottom
                                )
                                ctx.stroke()

                                ctx.fillStyle =
                                    "#ffd45f"
                                ctx.beginPath()
                                ctx.moveTo(
                                    markerX - 5,
                                    plotTop
                                )
                                ctx.lineTo(
                                    markerX + 5,
                                    plotTop
                                )
                                ctx.lineTo(
                                    markerX,
                                    plotTop + 7
                                )
                                ctx.closePath()
                                ctx.fill()

                                const messageCenterX =
                                    plotLeft
                                    + plotWidth / 2

                                if (radioController
                                        .scopeOutOfRange) {
                                    ctx.fillStyle =
                                        "rgba(120,20,25,0.70)"
                                    ctx.fillRect(
                                        plotLeft,
                                        plotTop,
                                        plotWidth,
                                        plotHeight
                                    )
                                    ctx.fillStyle =
                                        "#ffffff"
                                    ctx.font =
                                        "bold 18px Sans"
                                    ctx.textAlign =
                                        "center"
                                    ctx.textBaseline =
                                        "alphabetic"
                                    ctx.fillText(
                                        "OUT OF RANGE",
                                        messageCenterX,
                                        h / 2
                                    )
                                } else if (!radioController
                                            .connected) {
                                    ctx.fillStyle =
                                        "#aab4b9"
                                    ctx.font =
                                        "bold 15px Sans"
                                    ctx.textAlign =
                                        "center"
                                    ctx.textBaseline =
                                        "alphabetic"
                                    ctx.fillText(
                                        "RADIO DESCONECTADA",
                                        messageCenterX,
                                        h / 2
                                    )
                                } else if (!radioController
                                            .scopeRunning) {
                                    ctx.fillStyle =
                                        "#aab4b9"
                                    ctx.font =
                                        "bold 15px Sans"
                                    ctx.textAlign =
                                        "center"
                                    ctx.textBaseline =
                                        "alphabetic"
                                    ctx.fillText(
                                        "SCOPE DETENIDO",
                                        messageCenterX,
                                        h / 2
                                    )
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                readonly property real plotLeft:
                                    Math.min(
                                        scopeWindow
                                        .spectrumAxisWidth,
                                        Math.max(
                                            48,
                                            width * 0.14
                                        )
                                    )
                                readonly property real plotWidth:
                                    Math.max(
                                        1,
                                        width - plotLeft - 3
                                    )
                                readonly property real frequencyRatio:
                                    Math.max(
                                        0,
                                        Math.min(
                                            1,
                                            (mouseX - plotLeft)
                                            / plotWidth
                                        )
                                    )

                                ToolTip.visible:
                                    containsMouse
                                    && mouseX >= plotLeft
                                ToolTip.delay: 350
                                ToolTip.timeout: 6000
                                ToolTip.text:
                                    "Pulse para sintonizar "
                                    + scopeWindow
                                      .frequencyText(
                                          scopeWindow
                                          .lowerFrequency()
                                          + frequencyRatio
                                            * (scopeWindow
                                               .higherFrequency()
                                               - scopeWindow
                                                 .lowerFrequency())
                                      )

                                onClicked: {
                                    if (mouse.x < plotLeft)
                                        return

                                    scopeWindow
                                    .tuneAtPosition(
                                        mouse.x - plotLeft,
                                        plotWidth
                                    )
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30

                            Text {
                                text:
                                    scopeWindow
                                    .frequencyText(
                                        scopeWindow
                                        .lowerFrequency()
                                    )
                                color: "#b9dce8"
                                style: Text.Outline
                                styleColor: "#081015"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 15
                                font.bold: true
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Text {
                                text:
                                    scopeWindow
                                    .frequencyText(
                                        radioController
                                        .frequencyHz
                                    )
                                color: "#ffe274"
                                style: Text.Outline
                                styleColor: "#171000"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 17
                                font.bold: true
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            Text {
                                text:
                                    scopeWindow
                                    .frequencyText(
                                        scopeWindow
                                        .higherFrequency()
                                    )
                                color: "#b9dce8"
                                style: Text.Outline
                                styleColor: "#081015"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }
                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 170
                    color: "#030609"
                    border.color: "#315565"

                    Canvas {
                        id: waterfallCanvas

                        anchors.fill: parent
                        anchors.margins: 4
                        antialiasing: false

                        onWidthChanged:
                            requestPaint()
                        onHeightChanged:
                            requestPaint()

                        onPaint: {
                            const ctx =
                                getContext("2d")
                            const w = width
                            const h = height
                            const lines =
                                scopeWindow
                                .waterfallLines

                            ctx.reset()
                            ctx.clearRect(
                                0,
                                0,
                                w,
                                h
                            )
                            ctx.fillStyle =
                                "#030609"
                            ctx.fillRect(
                                0,
                                0,
                                w,
                                h
                            )

                            if (lines.length > 0) {
                                const rowHeight =
                                    Math.max(
                                        1,
                                        h
                                        / scopeWindow
                                          .maximumWaterfallLines
                                    )

                                for (let row = 0;
                                     row < lines.length;
                                     ++row) {
                                    const values =
                                        lines[row]

                                    if (!values
                                            || values.length < 1) {
                                        continue
                                    }

                                    let runStart = 0
                                    let runColor =
                                        scopeWindow
                                        .colorForLevel(
                                            values[0]
                                        )

                                    for (let sample = 1;
                                         sample <= values.length;
                                         ++sample) {
                                        const nextColor =
                                            sample
                                            < values.length
                                            ? scopeWindow
                                              .colorForLevel(
                                                  values[sample]
                                              )
                                            : ""

                                        if (nextColor
                                                !== runColor) {
                                            const x1 =
                                                runStart
                                                * w
                                                / values.length
                                            const x2 =
                                                sample
                                                * w
                                                / values.length

                                            ctx.fillStyle =
                                                runColor
                                            ctx.fillRect(
                                                x1,
                                                row
                                                * rowHeight,
                                                Math.max(
                                                    1,
                                                    x2 - x1
                                                ),
                                                rowHeight + 0.7
                                            )

                                            runStart =
                                                sample
                                            runColor =
                                                nextColor
                                        }
                                    }
                                }
                            }

                            const markerX =
                                scopeWindow
                                .currentFrequencyRatio()
                                * w

                            ctx.strokeStyle =
                                "rgba(255,212,95,0.75)"
                            ctx.lineWidth = 1
                            ctx.beginPath()
                            ctx.moveTo(
                                markerX,
                                0
                            )
                            ctx.lineTo(
                                markerX,
                                h
                            )
                            ctx.stroke()

                            if (lines.length === 0) {
                                ctx.fillStyle =
                                    "#6f7d83"
                                ctx.font =
                                    "bold 13px Sans"
                                ctx.textAlign =
                                    "center"
                                ctx.fillText(
                                    radioController
                                    .scopeRunning
                                    ? "ESPERANDO PRIMER BARRIDO…"
                                    : "WATERFALL",
                                    w / 2,
                                    h / 2
                                )
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true

                            ToolTip.visible:
                                containsMouse
                            ToolTip.delay: 350
                            ToolTip.timeout: 6000
                            ToolTip.text:
                                "Pulse para sintonizar "
                                + scopeWindow
                                  .frequencyText(
                                      scopeWindow
                                      .lowerFrequency()
                                      + mouseX
                                        / Math.max(
                                            1,
                                            width
                                        )
                                        * (scopeWindow
                                           .higherFrequency()
                                           - scopeWindow
                                             .lowerFrequency())
                                  )

                            onClicked:
                                scopeWindow
                                .tuneAtPosition(
                                    mouse.x,
                                    width
                                )
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    Layout.leftMargin: 5
                    Layout.rightMargin: 5

                    Text {
                        text:
                            scopeWindow
                            .frequencyText(
                                scopeWindow
                                .lowerFrequency()
                            )
                        color: "#b9dce8"
                        style: Text.Outline
                        styleColor: "#081015"
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text:
                            scopeWindow
                            .frequencyText(
                                radioController
                                .frequencyHz
                            )
                        color: "#ffe274"
                        style: Text.Outline
                        styleColor: "#171000"
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text:
                            scopeWindow
                            .frequencyText(
                                scopeWindow
                                .higherFrequency()
                            )
                        color: "#b9dce8"
                        style: Text.Outline
                        styleColor: "#081015"
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 15
                        font.bold: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22

                    Text {
                        text:
                            "475 puntos · CI-V 27 00 · "
                            + radioController
                              .scopeModeText
                            + " · "
                            + radioController
                              .scopeSweepSpeedText
                            + " · VBW "
                            + (radioController
                               .scopeVbwWide
                               ? "WIDE"
                               : "NAR")
                        color: "#82969f"
                        font.pixelSize: 9
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text:
                            "Pulse en el espectro o waterfall para sintonizar"
                        color: "#91b8c6"
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
            }
        }
    }

    Window {
        id: memoryQuickWindow

        property bool editMode: false
        property bool editorDirty: false
        property bool rereadPending: false
        property bool storeConfirmationVisible: false

        readonly property string applyDisabledReason:
            !radioController.connected
            ? "Radio desconectada"
            : radioController.transmitting
              ? "La radio está transmitiendo"
              : radioController.scanActive
                ? "Detenga el escáner"
                : ""
        readonly property int memoryRevision:
            radioController.memoriesRevision

        property var selectedRecord: {
            const ignoredRevision =
                memoryRevision
            const row =
                radioController.memoryRow(
                    memoryQuickSelectedChannel
                )

            return row
                   && row.channel !== undefined
                   ? row
                   : ({
                          "channel":
                              memoryQuickSelectedChannel,
                          "loaded": false,
                          "blank": true,
                          "name": "",
                          "frequencyText": "—",
                          "transmitFrequencyText": "—",
                          "modeText": "USB",
                          "filterCode": 1,
                          "dataMode": false,
                          "toneType": 0,
                          "transmitModeText": "USB",
                          "transmitFilterCode": 1,
                          "transmitDataMode": false,
                          "transmitToneType": 0,
                          "repeaterToneTenthsHz": 885,
                          "toneSquelchTenthsHz": 885,
                          "split": false,
                          "selectGroup": 0
                      })
        }

        transientParent: window
        visible:
            memoryQuickPanelVisible
        width:
            memoryQuickPanelWidth
        height:
            window.height
        minimumWidth:
            memoryQuickPanelWidth
        maximumWidth:
            memoryQuickPanelWidth
        minimumHeight: 520
        color: "transparent"
        title: "Memorias"
        flags:
            Qt.Tool
            | Qt.FramelessWindowHint

        function channelText(channel) {
            return "M"
                   + (channel < 10 ? "0" : "")
                   + channel
        }

        function modeIndex(modeText) {
            const index =
                modeNames.indexOf(
                    String(modeText)
                )
            return index >= 0 ? index : 1
        }

        function toneText(tenthsHz) {
            return (
                Number(tenthsHz || 885) / 10.0
            ).toFixed(1).replace(".", ",")
        }

        function parseTone(text, fallbackValue) {
            const normalized =
                String(text).trim().replace(",", ".")
            const value =
                Number(normalized)

            return isFinite(value)
                   ? Math.round(value * 10)
                   : fallbackValue
        }

        function loadEditor() {
            const row =
                selectedRecord

            quickMemoryNameField.text =
                row.name || ""
            quickMemoryRxFrequencyField.text =
                row.loaded && !row.blank
                ? row.frequencyText
                : ""
            quickMemoryTxFrequencyField.text =
                row.loaded && !row.blank
                ? row.transmitFrequencyText
                : ""

            quickMemoryRxModeBox.currentIndex =
                modeIndex(row.modeText)
            quickMemoryTxModeBox.currentIndex =
                modeIndex(row.transmitModeText)

            quickMemoryRxFilterBox.currentIndex =
                Math.max(
                    0,
                    Math.min(
                        2,
                        Number(row.filterCode || 1) - 1
                    )
                )
            quickMemoryTxFilterBox.currentIndex =
                Math.max(
                    0,
                    Math.min(
                        2,
                        Number(
                            row.transmitFilterCode || 1
                        ) - 1
                    )
                )

            quickMemoryRxDataCheck.checked =
                Boolean(row.dataMode)
            quickMemoryTxDataCheck.checked =
                Boolean(row.transmitDataMode)

            quickMemoryRxToneBox.currentIndex =
                Math.max(
                    0,
                    Math.min(
                        2,
                        Number(row.toneType || 0)
                    )
                )
            quickMemoryTxToneBox.currentIndex =
                Math.max(
                    0,
                    Math.min(
                        2,
                        Number(
                            row.transmitToneType || 0
                        )
                    )
                )

            quickMemoryToneField.text =
                toneText(
                    row.repeaterToneTenthsHz
                )
            quickMemoryTsqlField.text =
                toneText(
                    row.toneSquelchTenthsHz
                )

            quickMemorySplitCheck.checked =
                Boolean(row.split)
            quickMemoryGroupBox.currentIndex =
                Math.max(
                    0,
                    Math.min(
                        3,
                        Number(row.selectGroup || 0)
                    )
                )

            editorDirty = false
        }

        function selectWithoutActivating(channel) {
            memoryQuickSelectedChannel =
                Math.max(
                    1,
                    Math.min(99, channel)
                )
            storeConfirmationVisible = false
        }

        function openEditor(channel) {
            selectWithoutActivating(channel)
            editMode = true
            loadEditor()
        }

        function closeEditor() {
            editorDirty = false
            storeConfirmationVisible = false
            editMode = false
        }

        function requestStoreCurrentState() {
            storeConfirmationVisible = true
        }

        function confirmStoreCurrentState() {
            storeConfirmationVisible = false
            radioController.storeDisplayedToMemory(
                memoryQuickSelectedChannel
            )
        }

        function rereadSelectedMemory() {
            rereadPending = true
            editorDirty = false

            radioController.readMemoryChannel(
                memoryQuickSelectedChannel
            )
        }

        function saveEditor() {
            const accepted =
                radioController.updateMemoryChannel(
                memoryQuickSelectedChannel,
                {
                    "name":
                        quickMemoryNameField.text,
                    "receiveFrequency":
                        quickMemoryRxFrequencyField.text,
                    "transmitFrequency":
                        quickMemoryTxFrequencyField.text,
                    "receiveMode":
                        quickMemoryRxModeBox.currentText,
                    "receiveFilter":
                        quickMemoryRxFilterBox.currentIndex + 1,
                    "receiveData":
                        quickMemoryRxDataCheck.checked,
                    "receiveToneType":
                        quickMemoryRxToneBox.currentIndex,
                    "transmitMode":
                        quickMemoryTxModeBox.currentText,
                    "transmitFilter":
                        quickMemoryTxFilterBox.currentIndex + 1,
                    "transmitData":
                        quickMemoryTxDataCheck.checked,
                    "transmitToneType":
                        quickMemoryTxToneBox.currentIndex,
                    "repeaterToneTenthsHz":
                        parseTone(
                            quickMemoryToneField.text,
                            885
                        ),
                    "toneSquelchTenthsHz":
                        parseTone(
                            quickMemoryTsqlField.text,
                            885
                        ),
                    "split":
                        quickMemorySplitCheck.checked,
                    "selectGroup":
                        quickMemoryGroupBox.currentIndex
                }
            )

            if (accepted) {
                editorDirty = false
            }
        }

        onVisibleChanged: {
            if (visible) {
                Qt.callLater(
                    window.positionMemoryQuickWindow
                )

                if (memoryQuickModel.count !== 99)
                    window.rebuildMemoryQuickModel()
            } else {
                editMode = false
                editorDirty = false
                rereadPending = false
                storeConfirmationVisible = false
            }
        }

        onClosing: function(close) {
            close.accepted = false
            window.setMemoryQuickPanelVisible(false)
        }

        Connections {
            target: radioController

            function onMemoriesChanged() {
                if (!memoryQuickWindow.visible
                        || !memoryQuickWindow.editMode) {
                    return
                }

                if (memoryQuickWindow.rereadPending) {
                    memoryQuickWindow.rereadPending = false
                    memoryQuickWindow.loadEditor()
                    return
                }

                if (!memoryQuickWindow.editorDirty) {
                    memoryQuickWindow.loadEditor()
                }
            }
        }

        FrameBox {
            anchors.fill: parent
            color: "#202427"
            border.color: "#54788b"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 7
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    spacing: 5

                    PanelButton {
                        visible:
                            memoryQuickWindow.editMode
                        Layout.preferredWidth: 68
                        Layout.preferredHeight: 26
                        text: "VOLVER"

                        onClicked:
                            memoryQuickWindow.closeEditor()
                    }

                    Text {
                        text:
                            memoryQuickWindow.editMode
                            ? "EDITAR "
                              + memoryQuickWindow
                                .channelText(
                                    memoryQuickSelectedChannel
                                )
                            : "MEMORIAS"
                        color: "#f4f7f8"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Text {
                        visible:
                            !memoryQuickWindow.editMode
                        text:
                            memoryQuickOccupiedCount
                            + " ocupadas"
                        color: "#9edcf4"
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Button {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 26
                        text: "×"
                        font.pixelSize: 15
                        font.bold: true

                        onClicked:
                            window
                            .setMemoryQuickPanelVisible(
                                false
                            )

                        background: Rectangle {
                            radius: 3
                            color:
                                parent.down
                                ? "#683c3c"
                                : "#3a4145"
                            border.color: "#6c777d"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font: parent.font
                            horizontalAlignment:
                                Text.AlignHCenter
                            verticalAlignment:
                                Text.AlignVCenter
                        }
                    }
                }

                Rectangle {
                    visible:
                        memoryQuickWindow
                        .storeConfirmationVisible
                    Layout.fillWidth: true
                    Layout.preferredHeight:
                        visible ? 86 : 0
                    radius: 5
                    color: "#332618"
                    border.color: "#d89a50"
                    border.width: 2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 5

                        Text {
                            Layout.fillWidth: true
                            text:
                                "¿Guardar el estado actual de la radio en "
                                + memoryQuickWindow
                                  .channelText(
                                      memoryQuickSelectedChannel
                                  )
                                + "?"
                            color: "#ffe1b7"
                            font.pixelSize: 11
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                text: "CANCELAR"

                                onClicked:
                                    memoryQuickWindow
                                    .storeConfirmationVisible =
                                        false
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                text: "CONFIRMAR GUARDADO"
                                activeColor: "#946531"
                                enabled:
                                    controlsEnabled()

                                onClicked:
                                    memoryQuickWindow
                                    .confirmStoreCurrentState()
                            }
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex:
                        memoryQuickWindow.editMode
                        ? 1
                        : 0

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 5

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                text:
                                    "SOBRESCRIBIR "
                                    + memoryQuickWindow
                                      .channelText(
                                          memoryQuickSelectedChannel
                                      )
                                    + " CON ESTADO DE RADIO"
                                font.pixelSize: 10
                                font.bold: true
                                activeColor: "#8a6031"
                                enabled:
                                    controlsEnabled()

                                onClicked:
                                    memoryQuickWindow
                                    .requestStoreCurrentState()
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                spacing: 5

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    text:
                                        memoryQuickLoadedCount
                                        + "/99 LEÍDAS"
                                    activeColor: "#37677d"
                                    enabled:
                                        radioController.connected
                                        && !radioController.busy

                                    onClicked:
                                        radioController
                                        .readMemoryRange(1, 99)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:
                                        "Fila: seleccionar · Doble clic/EDITAR: modificar · Mxx: activar"
                                    color: "#b8c2c7"
                                    font.pixelSize: 9
                                    horizontalAlignment:
                                        Text.AlignRight
                                    elide:
                                        Text.ElideRight
                                }
                            }

                            ListView {
                                id: memoryQuickList

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 3
                                model: memoryQuickModel
                                boundsBehavior:
                                    Flickable.StopAtBounds
                                reuseItems: true

                                ScrollBar.vertical: ScrollBar {
                                    policy:
                                        ScrollBar.AlwaysOn
                                    width: 11
                                }

                                delegate: Rectangle {
                                    id: memoryQuickRow

                                    required property int index
                                    required property int channel
                                    required property bool loaded
                                    required property bool blank
                                    required property string memoryName
                                    required property string frequencyText
                                    required property string modeText
                                    required property string filterText
                                    required property bool dataMode
                                    required property string duplexText
                                    required property string toneText
                                    required property string selectText

                                    readonly property bool activeOnRadio:
                                        radioController
                                        .memoryModeActive
                                        && radioController
                                           .selectedMemoryChannel
                                           === channel

                                    readonly property bool selectedInPanel:
                                        memoryQuickSelectedChannel
                                        === channel

                                    width:
                                        memoryQuickList.width
                                        - 13
                                    height: 52
                                    radius: 4

                                    color:
                                        activeOnRadio
                                        ? "#12536f"
                                        : selectedInPanel
                                          ? "#283c47"
                                          : channel % 2 === 0
                                            ? "#191d20"
                                            : "#1d2225"

                                    border.color:
                                        activeOnRadio
                                        ? "#f0d37b"
                                        : selectedInPanel
                                          ? "#70b7d7"
                                          : "#394247"
                                    border.width:
                                        activeOnRadio
                                        || selectedInPanel
                                        ? 2
                                        : 1

                                    TapHandler {
                                        acceptedButtons:
                                            Qt.LeftButton

                                        onTapped:
                                            memoryQuickWindow
                                            .selectWithoutActivating(
                                                memoryQuickRow.channel
                                            )

                                        onDoubleTapped:
                                            memoryQuickWindow
                                            .openEditor(
                                                memoryQuickRow.channel
                                            )
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 5

                                        Button {
                                            Layout.preferredWidth: 48
                                            Layout.fillHeight: true
                                            text:
                                                memoryQuickWindow
                                                .channelText(
                                                    memoryQuickRow.channel
                                                )
                                            enabled:
                                                radioController.connected
                                                && memoryQuickRow.loaded
                                                && !memoryQuickRow.blank
                                                && !radioController.scanActive

                                            onClicked: {
                                                memoryQuickWindow
                                                .selectWithoutActivating(
                                                    memoryQuickRow.channel
                                                )
                                                radioController
                                                .toggleMemoryChannel(
                                                    memoryQuickRow.channel
                                                )
                                            }

                                            background: Rectangle {
                                                radius: 3
                                                color:
                                                    memoryQuickRow
                                                    .activeOnRadio
                                                    ? "#8a6a24"
                                                    : memoryQuickRow
                                                      .selectedInPanel
                                                      ? "#397895"
                                                      : "#333a3f"
                                                border.color:
                                                    parent.enabled
                                                    ? "#8ca5b0"
                                                    : "#50585d"
                                            }

                                            contentItem: Text {
                                                text: parent.text
                                                color:
                                                    parent.enabled
                                                    ? "#ffffff"
                                                    : "#80888c"
                                                font.pixelSize: 10
                                                font.bold: true
                                                horizontalAlignment:
                                                    Text.AlignHCenter
                                                verticalAlignment:
                                                    Text.AlignVCenter
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                Layout.fillWidth: true
                                                text:
                                                    memoryQuickRow
                                                    .memoryName
                                                color:
                                                    memoryQuickRow.loaded
                                                    && !memoryQuickRow.blank
                                                    ? "#ffffff"
                                                    : "#949da2"
                                                font.pixelSize: 14
                                                font.bold:
                                                    memoryQuickRow.loaded
                                                    && !memoryQuickRow.blank
                                                elide:
                                                    Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text:
                                                    memoryQuickRow.loaded
                                                    && !memoryQuickRow.blank
                                                    ? memoryQuickRow
                                                      .frequencyText
                                                      + " · "
                                                      + memoryQuickRow
                                                        .modeText
                                                      + "/"
                                                      + memoryQuickRow
                                                        .filterText
                                                    : "—"
                                                color: "#aeb8bd"
                                                font.pixelSize: 8
                                                elide:
                                                    Text.ElideRight
                                            }
                                        }

                                        PanelButton {
                                            Layout.preferredWidth: 58
                                            Layout.fillHeight: true
                                            text: "EDITAR"
                                            activeColor: "#66517e"

                                            onClicked:
                                                memoryQuickWindow
                                                .openEditor(
                                                    memoryQuickRow.channel
                                                )
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 3
                                color: "#171a1c"
                                border.color: "#3d474c"

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 7
                                    anchors.rightMargin: 7
                                    text:
                                        radioController
                                        .memoryModeActive
                                        ? "RADIO EN "
                                          + radioController
                                            .selectedMemoryChannelText
                                          + " · repita Mxx para volver a "
                                          + radioController
                                            .memoryReturnVfoText
                                        : "RADIO EN VFO "
                                          + radioController.vfoText
                                    color:
                                        radioController
                                        .memoryModeActive
                                        ? "#f0d37b"
                                        : "#9edcf4"
                                    font.pixelSize: 9
                                    font.bold: true
                                    verticalAlignment:
                                        Text.AlignVCenter
                                    elide:
                                        Text.ElideRight
                                }
                            }
                        }
                    }

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 62
                                radius: 4
                                color: "#2a2117"
                                border.color: "#a87a42"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text:
                                            selectedRecord.loaded
                                            ? selectedRecord.blank
                                              ? "CANAL VACÍO"
                                              : selectedRecord.name.length > 0
                                                ? selectedRecord.name
                                                : "SIN NOMBRE"
                                            : "MEMORIA SIN LEER"
                                        color: "#ffd39b"
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide:
                                            Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text:
                                            "Edite los campos y pulse «APLICAR CAMBIOS»."
                                        color: "#e4d4c0"
                                        font.pixelSize: 9
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            Text {
                                visible:
                                    !selectedRecord.loaded
                                    || selectedRecord.blank
                                Layout.fillWidth: true
                                text:
                                    selectedRecord.loaded
                                    ? "El canal está vacío. Guarde primero el estado actual."
                                    : "Pulse LEER para cargar esta memoria."
                                color: "#e8be78"
                                font.pixelSize: 9
                                wrapMode:
                                    Text.WordWrap
                            }

                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentWidth: width
                                contentHeight:
                                    quickEditorForm
                                    .implicitHeight
                                clip: true
                                boundsBehavior:
                                    Flickable.StopAtBounds

                                ScrollBar.vertical: ScrollBar {
                                    policy:
                                        ScrollBar.AsNeeded
                                }

                                ColumnLayout {
                                    id: quickEditorForm

                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        text: "NOMBRE"
                                        color: "#cbd3d7"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    TextField {
                                        id: quickMemoryNameField

                                        Layout.fillWidth: true
                                        maximumLength: 16
                                        placeholderText:
                                            "Máximo 16 caracteres"
                                        selectByMouse: true

                                        onTextEdited:
                                            memoryQuickWindow
                                            .editorDirty = true
                                    }

                                    Text {
                                        text: "RECEPCIÓN"
                                        color: "#9edcf4"
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    TextField {
                                        id: quickMemoryRxFrequencyField

                                        Layout.fillWidth: true
                                        placeholderText:
                                            "Frecuencia RX"
                                        selectByMouse: true

                                        onTextEdited:
                                            memoryQuickWindow
                                            .editorDirty = true
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        ComboBox {
                                            id: quickMemoryRxModeBox

                                            Layout.fillWidth: true
                                            model: modeNames

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }

                                        ComboBox {
                                            id: quickMemoryRxFilterBox

                                            Layout.fillWidth: true
                                            model: [
                                                "FIL1",
                                                "FIL2",
                                                "FIL3"
                                            ]

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }

                                        PanelButton {
                                            id: quickMemoryRxDataCheck

                                            Layout.preferredWidth: 88
                                            checkable: true
                                            selected: checked
                                            activeColor: "#347a50"
                                            text:
                                                checked
                                                ? "DATA ON"
                                                : "DATA OFF"
                                            textPixelSize: 10
                                            tip:
                                                "Modo DATA de recepción: "
                                                + (checked ? "ON" : "OFF")

                                            onToggled:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Text {
                                            Layout.preferredWidth: 62
                                            text: "TONE RX"
                                            color: "#cbd3d7"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        ComboBox {
                                            id: quickMemoryRxToneBox

                                            Layout.fillWidth: true
                                            model: [
                                                "OFF",
                                                "TONE",
                                                "TSQL"
                                            ]

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }
                                    }

                                    Text {
                                        text: "TRANSMISIÓN"
                                        color: "#f0c88d"
                                        font.pixelSize: 10
                                        font.bold: true
                                    }

                                    TextField {
                                        id: quickMemoryTxFrequencyField

                                        Layout.fillWidth: true
                                        placeholderText:
                                            "Frecuencia TX"
                                        selectByMouse: true

                                        onTextEdited:
                                            memoryQuickWindow
                                            .editorDirty = true
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        ComboBox {
                                            id: quickMemoryTxModeBox

                                            Layout.fillWidth: true
                                            model: modeNames

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }

                                        ComboBox {
                                            id: quickMemoryTxFilterBox

                                            Layout.fillWidth: true
                                            model: [
                                                "FIL1",
                                                "FIL2",
                                                "FIL3"
                                            ]

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }

                                        PanelButton {
                                            id: quickMemoryTxDataCheck

                                            Layout.preferredWidth: 88
                                            checkable: true
                                            selected: checked
                                            activeColor: "#347a50"
                                            text:
                                                checked
                                                ? "DATA ON"
                                                : "DATA OFF"
                                            textPixelSize: 10
                                            tip:
                                                "Modo DATA de transmisión: "
                                                + (checked ? "ON" : "OFF")

                                            onToggled:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        Text {
                                            Layout.preferredWidth: 62
                                            text: "TONE TX"
                                            color: "#cbd3d7"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        ComboBox {
                                            id: quickMemoryTxToneBox

                                            Layout.fillWidth: true
                                            model: [
                                                "OFF",
                                                "TONE",
                                                "TSQL"
                                            ]

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: "TONE"
                                                color: "#cbd3d7"
                                                font.pixelSize: 9
                                                font.bold: true
                                            }

                                            TextField {
                                                id: quickMemoryToneField

                                                Layout.fillWidth: true
                                                placeholderText: "88,5"

                                                onTextEdited:
                                                    memoryQuickWindow
                                                    .editorDirty = true
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: "TSQL"
                                                color: "#cbd3d7"
                                                font.pixelSize: 9
                                                font.bold: true
                                            }

                                            TextField {
                                                id: quickMemoryTsqlField

                                                Layout.fillWidth: true
                                                placeholderText: "88,5"

                                                onTextEdited:
                                                    memoryQuickWindow
                                                    .editorDirty = true
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        CheckBox {
                                            id: quickMemorySplitCheck

                                            text: "SPLIT"

                                            onToggled:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }

                                        ComboBox {
                                            id: quickMemoryGroupBox

                                            Layout.fillWidth: true
                                            model: [
                                                "Sin grupo",
                                                "SEL1",
                                                "SEL2",
                                                "SEL3"
                                            ]

                                            onActivated:
                                                memoryQuickWindow
                                                .editorDirty = true
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    "Los botones DATA ON/OFF guardan el modo DATA por separado para RX y TX. "
                                    + "RELEER actualiza todos los campos desde la radio."
                                color: "#9edcf4"
                                font.pixelSize: 9
                                font.bold: true
                                wrapMode: Text.WordWrap
                                horizontalAlignment:
                                    Text.AlignHCenter
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                PanelButton {
                                    Layout.preferredWidth: 72
                                    Layout.preferredHeight: 34
                                    text:
                                        memoryQuickWindow.rereadPending
                                        ? "RELEYENDO…"
                                        : "RELEER"
                                    activeColor: "#37677d"
                                    enabled:
                                        radioController.connected
                                        && !radioController.busy
                                        && !memoryQuickWindow.rereadPending

                                    onClicked:
                                        memoryQuickWindow
                                        .rereadSelectedMemory()
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    text:
                                        "APLICAR CAMBIOS A "
                                        + memoryQuickWindow
                                          .channelText(
                                              memoryQuickSelectedChannel
                                          )
                                        + (memoryQuickWindow.editorDirty
                                           ? " *"
                                           : "")
                                    activeColor: "#3b7654"
                                    enabled:
                                        radioController.connected
                                        && !radioController.transmitting
                                        && !radioController.scanActive

                                    onClicked:
                                        memoryQuickWindow.saveEditor()
                                }

                                PanelButton {
                                    Layout.preferredWidth: 112
                                    Layout.preferredHeight: 34
                                    text: "DESHACER CAMBIOS"

                                    onClicked:
                                        memoryQuickWindow.loadEditor()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    memoryQuickWindow
                                    .applyDisabledReason.length > 0
                                    ? "APLICAR deshabilitado: "
                                      + memoryQuickWindow
                                        .applyDisabledReason
                                    : radioController.actionStatus
                                color:
                                    memoryQuickWindow
                                    .applyDisabledReason.length > 0
                                    ? "#ef9a9a"
                                    : radioController.memoryReadActive
                                      ? "#e8be78"
                                      : "#aeb8bd"
                                font.pixelSize: 9
                                font.bold:
                                    memoryQuickWindow
                                    .applyDisabledReason.length > 0
                                    || radioController.memoryReadActive
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    text: "IR"
                                    activeColor: "#326f8d"
                                    enabled:
                                        radioController.connected
                                        && selectedRecord.loaded
                                        && !selectedRecord.blank
                                        && !radioController.scanActive

                                    onClicked:
                                        radioController
                                        .selectMemoryChannel(
                                            memoryQuickSelectedChannel
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    text: "COPIAR A VFO"
                                    activeColor: "#456a7c"
                                    enabled:
                                        controlsEnabled()
                                        && selectedRecord.loaded
                                        && !selectedRecord.blank

                                    onClicked:
                                        radioController
                                        .copyMemoryToVfo(
                                            memoryQuickSelectedChannel
                                        )
                                }

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    text: "BORRAR"
                                    activeColor: "#85453f"
                                    enabled:
                                        controlsEnabled()
                                        && selectedRecord.loaded
                                        && !selectedRecord.blank

                                    onClicked: {
                                        window
                                        .pendingMemoryClearChannel =
                                            memoryQuickSelectedChannel
                                        clearMemoryConfirmDialog.open()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Window {
        id: scannerWindow

        transientParent: window
        visible:
            scannerVisible
        width: 500
        height: 590
        minimumWidth: 460
        minimumHeight: 520
        color: "#111315"
        title: "Escáner"

        onClosing: function(close) {
            close.accepted = false
            scannerVisible = false
        }

        Rectangle {
            anchors.fill: parent
            color: "#111315"
            border.color: "#6f8794"
            border.width: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    Text {
                        text: "SCANNER"
                        color: "#ffffff"
                        font.pixelSize: 18
                        font.bold: true
                    }

                    StatusTag {
                        caption:
                            radioController.scanActive
                            ? "ACTIVO · "
                              + radioController.scanTypeText
                            : "DETENIDO"
                        tagColor:
                            radioController.scanActive
                            ? "#8b4d3f"
                            : "#485158"
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PanelButton {
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 34
                        text: "CERRAR"

                        onClicked:
                            scannerVisible = false
                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    color: "#191d20"
                    border.color: "#4a565d"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Text {
                            text: "TIPO DE ESCANEO"
                            color: "#dce3e6"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 6
                            columnSpacing: 6

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "AUTO"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startContextScan()
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "PROGRAMADO"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startProgrammedScan(false)
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "PROGR. FINO"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startProgrammedScan(true)
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "MEMORIAS"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startMemoryScan()
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "MEM. SELECT"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startSelectMemoryScan()
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "ΔF"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startDeltaScan(false)
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "ΔF FINO"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .startDeltaScan(true)
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                text: "STOP"
                                activeColor: "#8c463e"
                                enabled:
                                    radioController.connected

                                onClicked:
                                    radioController.stopScan()
                            }
                        }
                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    color: "#191d20"
                    border.color: "#4a565d"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Text {
                            text: "COMPORTAMIENTO"
                            color: "#dce3e6"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                text:
                                    radioController.scanSpeedFast
                                    ? "VELOCIDAD: RÁPIDA"
                                    : "VELOCIDAD: LENTA"
                                selected:
                                    radioController.scanSpeedFast
                                activeColor: "#416c82"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .setScanSpeedFast(
                                        !radioController
                                         .scanSpeedFast
                                    )
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 36
                                text:
                                    radioController
                                    .scanResumeEnabled
                                    ? "REANUDAR: ON"
                                    : "REANUDAR: OFF"
                                selected:
                                    radioController
                                    .scanResumeEnabled
                                activeColor: "#4e7357"
                                enabled: controlsEnabled()

                                onClicked:
                                    radioController
                                    .setScanResumeEnabled(
                                        !radioController
                                         .scanResumeEnabled
                                    )
                            }
                        }

                        Text {
                            text: "GRUPO DE MEMORIAS"
                            color: "#cbd2d6"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Repeater {
                                model: [0, 1, 2, 3]

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    text:
                                        modelData === 0
                                        ? "TODAS"
                                        : "SEL" + modelData
                                    selected:
                                        radioController
                                        .scanSelectGroup
                                        === modelData
                                    activeColor: "#526f80"
                                    enabled: controlsEnabled()

                                    onClicked:
                                        radioController
                                        .setScanSelectGroup(
                                            modelData
                                        )
                                }
                            }
                        }
                    }
                }

                FrameBox {
                    Layout.fillWidth: true
                    color: "#191d20"
                    border.color: "#4a565d"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 9
                        spacing: 7

                        Text {
                            text: "AMPLITUD ΔF"
                            color: "#dce3e6"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: 5
                            columnSpacing: 5

                            Repeater {
                                model: [
                                    { code: 1, text: "±5 kHz" },
                                    { code: 2, text: "±10 kHz" },
                                    { code: 3, text: "±20 kHz" },
                                    { code: 4, text: "±50 kHz" },
                                    { code: 5, text: "±100 kHz" },
                                    { code: 6, text: "±500 kHz" },
                                    { code: 7, text: "±1 MHz" }
                                ]

                                PanelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    text: modelData.text
                                    selected:
                                        radioController
                                        .deltaScanSpanCode
                                        === modelData.code
                                    activeColor: "#526f80"
                                    enabled: controlsEnabled()

                                    onClicked:
                                        radioController
                                        .setDeltaScanSpanCode(
                                            modelData.code
                                        )
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                Text {
                    Layout.fillWidth: true
                    text:
                        radioController.scanActive
                        ? "Escaneo en curso: "
                          + radioController.scanTypeText
                        : "Seleccione un tipo de escaneo."
                    color:
                        radioController.scanActive
                        ? "#f0c181"
                        : "#aeb8bd"
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment:
                        Text.AlignHCenter
                }
            }
        }
    }



    Connections {
        target: radioController

        function onRitChanged() {
            if (!ritSpin.activeFocus) {
                ritSpin.value =
                    radioController
                    .ritOffsetHz
            }
        }

        function onVfoAStateChanged() {
            window.rememberBandFrequency(
                0,
                radioController.vfoAFrequencyHz
            )
        }

        function onVfoBStateChanged() {
            window.rememberBandFrequency(
                1,
                radioController.vfoBFrequencyHz
            )
        }

        function onMemoriesChanged() {
            window.rebuildMemoryQuickModel()
        }

        function onMemoryModeChanged() {
            if (radioController.memoryModeActive) {
                memoryQuickSelectedChannel =
                    radioController
                    .selectedMemoryChannel
            }
        }
    }
}
