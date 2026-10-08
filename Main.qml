import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQml.Models 2.15
import Icom.Video 1.0

ApplicationWindow {
    id: window

    readonly property int radioPanelsPreferredWidth:
        (applicationLauncher.icomPanelVisible ? 900 : 0)
        + (applicationLauncher.quanshengPanelVisible ? 550 : 0)
        + (applicationLauncher.icomPanelVisible && applicationLauncher.quanshengPanelVisible ? 8 : 0)
        + 24
    readonly property int toolbarGroupCount:
        3 + (applicationLauncher.icomPanelVisible ? 1 : 0)
    readonly property int topToolbarPreferredWidth:
        applicationLauncher.icomPanelVisible ? Math.ceil(
            connectionToolbarGroup.implicitWidth
            + toolsToolbarGroup.implicitWidth
            + memoriesToolbarGroup.implicitWidth
            + generalToolbarGroup.implicitWidth
            + (toolbarGroupCount - 1) * 4
            + (applicationLauncher.icomPanelVisible
               && applicationLauncher.quanshengPanelVisible ? 400 : 0)
            + 34
        ) : 0
    readonly property int preferredMainWindowWidth:
        Math.max(radioPanelsPreferredWidth, topToolbarPreferredWidth)
    width: preferredMainWindowWidth
    height: 880
    minimumWidth: preferredMainWindowWidth
    minimumHeight: 880
    maximumHeight: 880

    visible: !compactVisible && !superCompactVisible
    title: "Control IC-7300MK2 / Quansheng UV-K5 · Versión 1.2.14 · Compilado " + buildTimestamp
    color: "#454545"

    property bool diagnosticsVisible: false
    property bool remoteServerVisible: false
    property bool settingsVisible: false
    property bool compactVisible:
        applicationLauncher.startupViewMode === "compact"
    property bool superCompactVisible:
        applicationLauncher.startupViewMode === "frequency"
    property bool superCompactReturnToCompact: false
    property bool txSettingsVisible: false
    property bool cwSettingsVisible: false
    property bool toneRttySettingsVisible: false
    property bool scopeVisible: false
    property bool videoDetached: false
    property bool morseTrainerVisible: false
    property bool morseWorkspaceActive: false
    property bool applicationClosing: false
    property bool startupComplete: false
    property int mainVisibilityBeforeMorse: Window.Windowed
    property bool scannerVisible: false
    property bool memoryQuickPanelVisible: false
    property string lanLogText: ""
    property string generalLogText: ""
    property string generalLogFilter: "TODOS"
    property string lastQuanshengToneLog: ""
    property string lastQuanshengEepromStatus: ""
    property int memoryQuickSelectedChannel: 1
    property int pendingMemoryStoreChannel: 1
    property int pendingMemoryClearChannel: 1
    property int memoryQuickLoadedCount: 0
    property int memoryQuickOccupiedCount: 0
    readonly property int memoryQuickPanelWidth: 382
    property int nextAuxiliaryWindowZ: 100
    property int stepIndex: 3
    property real tuningAngle: 0
    property int selectedRadioTab: applicationLauncher.lastRadioTab
    property var quanshengMenuDefinitions: buildQuanshengMenuDefinitions()
    property var quanshengMenuReadSelection: ({})
    property var quanshengMenuPendingValues: ({})
    property var quanshengMenuReadTimestamps: ({})
    property string quanshengMenuStepVfo: ""
    property string quanshengMenuWidthVfo: ""
    property string quanshengMenuRxModeVfo: ""
    property string quanshengRepeaterReadVfo: ""
    property int quanshengRepeaterPendingDirection: -1
    property int quanshengRepeaterOffsetUnits: 76000
    property var quanshengWidthByVfo: ({})
    property var quanshengRxModeByVfo: ({})


    onSelectedRadioTabChanged: {
        applicationLauncher.lastRadioTab = selectedRadioTab
    }

    function qMenuOption(value, label) {
        return {"value": value, "label": label}
    }

    function qTwoDigits(value) {
        return value < 10 ? "0" + value : "" + value
    }

    function quanshengRxModeForVfo(vfo) {
        if (quanshengMenuRxModeVfo === vfo
                && quanshengMenuPendingValues["59"] !== undefined) {
            var pendingValue = quanshengMenuPendingValues["59"]
            var options = quanshengMenuDefinitions[58].options
            for (var i = 0; i < options.length; ++i)
                if (options[i].value === pendingValue)
                    return options[i].label
        }
        return String(quanshengRxModeByVfo[vfo] || "")
    }

    function applyQuanshengMainMenuValue(menuNumber, value, vfo) {
        if (vfo !== quanshengClient.activeVfo)
            return
        var menu = quanshengMenuDefinitions[menuNumber - 1]
        if (!menu || !menu.settable)
            return
        var option = null
        for (var i = 0; i < menu.options.length; ++i)
            if (menu.options[i].value === value) {
                option = menu.options[i]
                break
            }
        if (!option)
            return
        if (menuNumber === 1) {
            quanshengMenuStepVfo = vfo
            setQMenuPendingValue(menu, option.value)
        } else if (menuNumber === 59) {
            quanshengMenuRxModeVfo = vfo
            setQMenuPendingValue(menu, option.value)
        }
        quanshengClient.setMenuOption(menuNumber, option.value,
                                      qTwoDigits(menuNumber) + " " + menu.name + " " + option.label)
    }

    function quanshengWidthForVfo(vfo) {
        return String(quanshengWidthByVfo[vfo] || "—")
    }

    function rememberConfirmedQuanshengMenuStep() {
        var width = quanshengClient.menuValues["9"]
        if (width && width.confirmed && width.displayValue
                && (quanshengMenuWidthVfo === "A" || quanshengMenuWidthVfo === "B")
                && quanshengWidthByVfo[quanshengMenuWidthVfo] !== String(width.displayValue)) {
            var widths = Object.assign({}, quanshengWidthByVfo)
            widths[quanshengMenuWidthVfo] = String(width.displayValue)
            quanshengWidthByVfo = widths
        }
        var rxMode = quanshengClient.menuValues["59"]
        if (rxMode && rxMode.confirmed && rxMode.displayValue
                && (quanshengMenuRxModeVfo === "A" || quanshengMenuRxModeVfo === "B")
                && quanshengRxModeByVfo[quanshengMenuRxModeVfo] !== String(rxMode.displayValue)) {
            var rxModes = Object.assign({}, quanshengRxModeByVfo)
            rxModes[quanshengMenuRxModeVfo] = String(rxMode.displayValue)
            quanshengRxModeByVfo = rxModes
        }
    }

    function qMenuConfirmedIndex(menu) {
        var reading = quanshengClient.menuValues[String(menu.number)]
        if (!reading || !reading.confirmed)
            return -1
        var observed = String(reading.displayValue).toLowerCase().replace(/[^a-z0-9.]+/g, "")
        for (var i = 0; i < menu.options.length; ++i) {
            var candidate = String(menu.options[i].label).toLowerCase().replace(/[^a-z0-9.]+/g, "")
            if (candidate === observed)
                return i
        }
        return -1
    }

    function qMenuReadState(menu) {
        var reading = quanshengClient.menuValues[String(menu.number)]
        return reading ? reading.readState || (reading.confirmed ? "confirmed" : "unconfirmed") : "unread"
    }

    function qMenuSelectedIndex(menu) {
        var pending = quanshengMenuPendingValues[String(menu.number)]
        if (pending !== undefined) {
            for (var i = 0; i < menu.options.length; ++i)
                if (menu.options[i].value === pending)
                    return i
        }
        return qMenuConfirmedIndex(menu)
    }

    function setQMenuPendingValue(menu, value) {
        var pending = Object.assign({}, quanshengMenuPendingValues)
        pending[String(menu.number)] = value
        quanshengMenuPendingValues = pending
    }

    function clearConfirmedQuanshengMenuPendingValues() {
        var timestamps = Object.assign({}, quanshengMenuReadTimestamps)
        var pending = Object.assign({}, quanshengMenuPendingValues)
        var timestampsChanged = false
        var pendingChanged = false
        var readings = quanshengClient.menuValues
        for (var number in readings) {
            var reading = readings[number]
            if (!reading || !reading.confirmed || !reading.observedAt)
                continue
            var observedAt = String(reading.observedAt)
            if (timestamps[number] === observedAt)
                continue
            timestamps[number] = observedAt
            timestampsChanged = true
            if (pending[number] !== undefined) {
                delete pending[number]
                pendingChanged = true
            }
        }
        if (timestampsChanged)
            quanshengMenuReadTimestamps = timestamps
        if (pendingChanged)
            quanshengMenuPendingValues = pending
        if (!quanshengClient.controlBusy
                && quanshengClient.frequencyControlStatus.indexOf("error:") >= 0) {
            var failedPending = Object.assign({}, quanshengMenuPendingValues)
            var failedChanged = false
            if (quanshengMenuStepVfo && failedPending["1"] !== undefined) {
                delete failedPending["1"]
                failedChanged = true
            }
            if (quanshengMenuRxModeVfo && failedPending["59"] !== undefined) {
                delete failedPending["59"]
                failedChanged = true
            }
            if (failedChanged)
                quanshengMenuPendingValues = failedPending
        }
    }

    function qMenuReadIsIncluded(menu) {
        return quanshengMenuReadSelection[String(menu.number)] !== false
    }

    function qMenuReadSelectionCount() {
        var count = 0
        for (var i = 0; i < quanshengMenuDefinitions.length; ++i) {
            var menu = quanshengMenuDefinitions[i]
            if ((menu.settable || menu.readable) && qMenuReadIsIncluded(menu))
                ++count
        }
        return count
    }

    function setQMenuReadIncluded(menu, included) {
        var selection = Object.assign({}, quanshengMenuReadSelection)
        selection[String(menu.number)] = included
        quanshengMenuReadSelection = selection
        applicationLauncher.quanshengMenuReadSelectionJson = JSON.stringify(selection)
    }

    function readQuanshengMenuValues() {
        var menus = []
        for (var i = 0; i < quanshengMenuDefinitions.length; ++i)
            if ((quanshengMenuDefinitions[i].settable || quanshengMenuDefinitions[i].readable)
                    && qMenuReadIsIncluded(quanshengMenuDefinitions[i]))
                menus.push(quanshengMenuDefinitions[i].number)
        if (menus.indexOf(1) >= 0)
            quanshengMenuStepVfo = quanshengClient.activeVfo
        if (menus.indexOf(9) >= 0)
            quanshengMenuWidthVfo = quanshengClient.activeVfo
        if (menus.indexOf(59) >= 0)
            quanshengMenuRxModeVfo = quanshengClient.activeVfo
        if (menus.indexOf(7) >= 0 || menus.indexOf(8) >= 0)
            quanshengRepeaterReadVfo = quanshengClient.activeVfo
        quanshengClient.readMenuValues(menus)
    }

    function readAllQuanshengMenuValues() {
        var menus = []
        for (var i = 1; i <= 61; ++i)
            menus.push(i)
        quanshengMenuStepVfo = quanshengClient.activeVfo
        quanshengMenuWidthVfo = quanshengClient.activeVfo
        quanshengMenuRxModeVfo = quanshengClient.activeVfo
        quanshengRepeaterReadVfo = quanshengClient.activeVfo
        quanshengClient.readMenuValues(menus)
    }

    function readQuanshengMenuValue(menu) {
        if (menu.number === 1)
            quanshengMenuStepVfo = quanshengClient.activeVfo
        if (menu.number === 9)
            quanshengMenuWidthVfo = quanshengClient.activeVfo
        if (menu.number === 59)
            quanshengMenuRxModeVfo = quanshengClient.activeVfo
        if (menu.number === 7 || menu.number === 8)
            quanshengRepeaterReadVfo = quanshengClient.activeVfo
        quanshengClient.readMenuValues([menu.number], true)
    }

    function readQuanshengRepeater() {
        if (quanshengClient.activeVfo !== "A" && quanshengClient.activeVfo !== "B")
            return
        quanshengRepeaterReadVfo = quanshengClient.activeVfo
        quanshengClient.readMenuValues([7, 8], true)
    }

    function quanshengRepeaterPreset() {
        var frequency = quanshengPopup.activeFrequencyMHz()
        if (!isFinite(frequency))
            return { "supported": false, "label": "—", "offsets": [] }
        if (frequency >= 144 && frequency <= 146)
            return { "supported": true, "label": "2 m", "offsets": [
                    { "units": 6000, "label": "0,600 MHz" }
                ] }
        if (frequency >= 430 && frequency <= 440)
            return { "supported": true, "label": "70 cm", "offsets": [
                    { "units": 16000, "label": "1,600 MHz" },
                    { "units": 76000, "label": "7,600 MHz" }
                ] }
        return { "supported": false, "label": "—", "offsets": [] }
    }

    function quanshengRepeaterOffsetIndex(offsets) {
        for (var i = 0; i < offsets.length; ++i)
            if (offsets[i].units === quanshengRepeaterOffsetUnits)
                return i
        return offsets.length > 0 ? offsets.length - 1 : -1
    }

    function applyQuanshengRepeaterDirection(direction) {
        if (quanshengClient.activeVfo !== "A" && quanshengClient.activeVfo !== "B")
            return
        if (direction !== 0 && !quanshengRepeaterPreset().supported)
            return
        quanshengRepeaterReadVfo = quanshengClient.activeVfo
        quanshengRepeaterPendingDirection = direction
        quanshengClient.setMenuOption(7, direction,
                                      "07 TxODir " + ["OFF", "+", "-"][direction])
    }

    function quanshengRepeaterConfirmedDirection() {
        if (quanshengRepeaterPendingDirection >= 0)
            return quanshengRepeaterPendingDirection
        if (quanshengRepeaterReadVfo !== quanshengClient.activeVfo)
            return -1
        var reading = quanshengClient.menuValues["7"]
        if (!reading || !reading.confirmed)
            return -1
        var value = String(reading.displayValue).trim().toUpperCase()
        if (value === "OFF") return 0
        if (value.indexOf("+") >= 0) return 1
        if (value.indexOf("-") >= 0 || value.indexOf("−") >= 0) return 2
        return -1
    }

    function quanshengOffsetUnitsFromReading() {
        if (quanshengRepeaterReadVfo !== quanshengClient.activeVfo)
            return 0
        var reading = quanshengClient.menuValues["8"]
        if (!reading || !reading.confirmed)
            return 0
        var match = String(reading.displayValue).match(/[0-9]+(?:\.[0-9]+)?/)
        return match ? Math.max(0, Math.min(999999, Math.round(Number(match[0]) * 10000))) : 0
    }

    function quanshengRepeaterOffsetMatchesPreset() {
        var preset = quanshengRepeaterPreset()
        if (!preset.supported || quanshengRepeaterReadVfo !== quanshengClient.activeVfo
                || !quanshengClient.menuValues["8"]
                || !quanshengClient.menuValues["8"].confirmed)
            return false
        var selectedUnits = quanshengRepeaterOffsetCombo.currentValue
        return preset.offsets.some(function(option) { return option.units === selectedUnits })
                && quanshengOffsetUnitsFromReading() === selectedUnits
    }

    function applyQuanshengRepeaterOffset(units) {
        if (quanshengClient.activeVfo !== "A" && quanshengClient.activeVfo !== "B")
            return
        var preset = quanshengRepeaterPreset()
        if (!preset.supported
                || !preset.offsets.some(function(option) { return option.units === units }))
            return
        quanshengRepeaterReadVfo = quanshengClient.activeVfo
        quanshengClient.setMenuOption(8, units * 10,
                                      "08 TxOffs " + (units / 10000).toFixed(5) + " MHz")
    }

    function applyQuanshengMenuOption(menu, option) {
        if (menu.number === 1)
            quanshengMenuStepVfo = quanshengClient.activeVfo
        if (menu.number === 9)
            quanshengMenuWidthVfo = quanshengClient.activeVfo
        if (menu.number === 59)
            quanshengMenuRxModeVfo = quanshengClient.activeVfo
        quanshengClient.setMenuOption(menu.number, option.value,
                                      qTwoDigits(menu.number) + " " + menu.name + " " + option.label)
    }

    function qMenuOptions(labels, firstValue) {
        var start = firstValue === undefined ? 0 : firstValue
        var options = []
        for (var i = 0; i < labels.length; ++i)
            options.push(qMenuOption(start + i, labels[i]))
        return options
    }

    function qMenuRange(minimum, maximum, prefix, suffix) {
        var options = []
        for (var value = minimum; value <= maximum; ++value)
            options.push(qMenuOption(value, (prefix || "") + value + (suffix || "")))
        return options
    }

    function qMenuCtcssOptions() {
        var tones = [67.0, 69.3, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5,
                     94.8, 97.4, 100.0, 103.5, 107.2, 110.9, 114.8, 118.8, 123.0, 127.3,
                     131.8, 136.5, 141.3, 146.2, 151.4, 156.7, 159.8, 162.2, 165.5, 167.9,
                     171.3, 173.8, 177.3, 179.9, 183.5, 186.2, 189.9, 192.8, 196.6, 199.5,
                     203.5, 206.5, 210.7, 218.1, 225.7, 229.1, 233.6, 241.8, 250.3, 254.1]
        var options = [qMenuOption(0, "OFF")]
        for (var i = 0; i < tones.length; ++i)
            options.push(qMenuOption(i + 1, tones[i].toFixed(1) + " Hz"))
        return options
    }

    function qMenuDcsLabel(code, inverted) {
        var text = Number(code).toString(8)
        while (text.length < 3)
            text = "0" + text
        return "D" + text + (inverted ? "I" : "N")
    }

    function qMenuDcsOptions() {
        var codes = [0x0013, 0x0015, 0x0016, 0x0019, 0x001a, 0x001e, 0x0023, 0x0027,
                     0x0029, 0x002b, 0x002c, 0x0035, 0x0039, 0x003a, 0x003b, 0x003c,
                     0x004c, 0x004d, 0x004e, 0x0052, 0x0055, 0x0059, 0x005a, 0x005c,
                     0x0063, 0x0065, 0x006a, 0x006d, 0x006e, 0x0072, 0x0075, 0x007a,
                     0x007c, 0x0085, 0x008a, 0x0093, 0x0095, 0x0096, 0x00a3, 0x00a4,
                     0x00a5, 0x00a6, 0x00a9, 0x00aa, 0x00ad, 0x00b1, 0x00b3, 0x00b5,
                     0x00b6, 0x00b9, 0x00bc, 0x00c6, 0x00c9, 0x00cd, 0x00d5, 0x00d9,
                     0x00da, 0x00e3, 0x00e6, 0x00e9, 0x00ee, 0x00f4, 0x00f5, 0x00f9,
                     0x0109, 0x010a, 0x010b, 0x0113, 0x0119, 0x011a, 0x0125, 0x0126,
                     0x012a, 0x012c, 0x012d, 0x0132, 0x0134, 0x0135, 0x0136, 0x0143,
                     0x0146, 0x014e, 0x0153, 0x0156, 0x015a, 0x0166, 0x0175, 0x0186,
                     0x018a, 0x0194, 0x0197, 0x0199, 0x019a, 0x01ac, 0x01b2, 0x01b4,
                     0x01c3, 0x01ca, 0x01d3, 0x01d9, 0x01da, 0x01dc, 0x01e3, 0x01ec]
        var options = [qMenuOption(0, "OFF")]
        for (var i = 0; i < codes.length; ++i)
            options.push(qMenuOption(i + 1, qMenuDcsLabel(codes[i], false)))
        for (var j = 0; j < codes.length; ++j)
            options.push(qMenuOption(j + 105, qMenuDcsLabel(codes[j], true)))
        return options
    }

    function buildQuanshengMenuDefinitions() {
        var onOff = qMenuOptions(["OFF", "ON"])
        var sideFunctions = qMenuOptions(["NONE", "FLASH LIGHT", "POWER", "MONITOR", "SCAN", "VOX",
                                          "FM RADIO", "LOCK KEYPAD", "SWITCH VFO", "VFO/MR",
                                          "SWITCH DEMODUL"])
        var disabled = function(text) { return [qMenuOption(0, text)] }
        return [
            {"number": 1, "name": "Step", "description": "Paso de sintonia del VFO", "settable": true, "options": qMenuOptions(["0.01 kHz", "0.05 kHz", "0.1 kHz", "0.25 kHz", "0.5 kHz", "1 kHz", "1.25 kHz", "2.5 kHz", "5 kHz", "6.25 kHz", "8.33 kHz", "9 kHz", "10 kHz", "12.5 kHz", "15 kHz", "20 kHz", "25 kHz", "30 kHz", "50 kHz", "100 kHz", "125 kHz", "200 kHz", "250 kHz", "500 kHz"])},
            {"number": 2, "name": "TxPwr", "description": "Nivel de potencia transmitida", "settable": true, "options": qMenuOptions(["LOW", "MID", "HIGH"])},
            {"number": 3, "name": "RxDCS", "description": "Codigo DCS para abrir recepcion", "settable": true, "options": qMenuDcsOptions()},
            {"number": 4, "name": "RxCTCS", "description": "Tono CTCSS para abrir recepcion", "settable": true, "options": qMenuCtcssOptions()},
            {"number": 5, "name": "TxDCS", "description": "Codigo DCS transmitido", "settable": true, "options": qMenuDcsOptions()},
            {"number": 6, "name": "TxCTCS", "description": "Tono CTCSS transmitido", "settable": true, "options": qMenuCtcssOptions()},
            {"number": 7, "name": "TxODir", "description": "Desplazamiento español: configúralo desde el control de repetidor principal", "settable": false, "readable": true, "options": disabled("Usa el control de repetidor principal, limitado al segmento y salto españoles")},
            {"number": 8, "name": "TxOffs", "description": "Frecuencia de desplazamiento del repetidor", "settable": false, "readable": true, "options": disabled("Frecuencia introducida desde el control principal")},
            {"number": 9, "name": "W/N", "description": "Ancho de banda de canal", "settable": true, "options": qMenuOptions(["WIDE", "NARROW"])},
            {"number": 10, "name": "Scramb", "description": "Frecuencia del codificador de voz", "settable": true, "options": qMenuOptions(["OFF", "2600 Hz", "2700 Hz", "2800 Hz", "2900 Hz", "3000 Hz", "3100 Hz", "3200 Hz", "3300 Hz", "3400 Hz", "3500 Hz"])},
            {"number": 11, "name": "BusyCL", "description": "Bloquea TX si el canal esta ocupado", "settable": true, "options": onOff},
            {"number": 12, "name": "Compnd", "description": "Compansor de audio TX/RX", "settable": true, "options": qMenuOptions(["OFF", "TX", "RX", "TX/RX"])},
            {"number": 13, "name": "Demodu", "description": "Modo de demodulacion", "settable": true, "options": qMenuOptions(["FM", "AM", "USB", "BYP", "RAW"])},
            {"number": 14, "name": "ScAdd1", "description": "Incluye el canal en la lista de escaneo 1", "settable": true, "options": onOff},
            {"number": 15, "name": "ScAdd2", "description": "Incluye el canal en la lista de escaneo 2", "settable": true, "options": onOff},
            {"number": 16, "name": "ChSave", "description": "Guarda los ajustes actuales en una memoria", "settable": false, "options": disabled("Guarda memoria; no habilitado desde esta ventana")},
            {"number": 17, "name": "ChDele", "description": "Borra una memoria de canal", "settable": false, "options": disabled("Borra memoria; no habilitado desde esta ventana")},
            {"number": 18, "name": "ChName", "description": "Edita el nombre de una memoria", "settable": false, "options": disabled("Texto de canal; pendiente de editor dedicado")},
            {"number": 19, "name": "SList", "description": "Selecciona la lista usada al escanear", "settable": true, "options": qMenuOptions(["LIST1", "LIST2", "ALL"])},
            {"number": 20, "name": "SList1", "description": "Canal inicial de la lista de escaneo 1", "settable": false, "options": disabled("Rango -1..199; pendiente de editor de canal")},
            {"number": 21, "name": "SList2", "description": "Canal inicial de la lista de escaneo 2", "settable": false, "options": disabled("Rango -1..199; pendiente de editor de canal")},
            {"number": 22, "name": "ScnRev", "description": "Comportamiento al reanudar el escaneo", "settable": true, "options": qMenuOptions(["TIMEOUT", "CARRIER", "STOP"])},
            {"number": 23, "name": "F1Shrt", "description": "Accion de pulsacion corta de F1", "settable": true, "options": sideFunctions},
            {"number": 24, "name": "F1Long", "description": "Accion de pulsacion larga de F1", "settable": true, "options": sideFunctions},
            {"number": 25, "name": "F2Shrt", "description": "Accion de pulsacion corta de F2", "settable": true, "options": sideFunctions},
            {"number": 26, "name": "F2Long", "description": "Accion de pulsacion larga de F2", "settable": true, "options": sideFunctions},
            {"number": 27, "name": "M Long", "description": "Accion de pulsacion larga de MENU", "settable": true, "options": sideFunctions},
            {"number": 28, "name": "KeyLck", "description": "Bloqueo automatico del teclado", "settable": true, "options": qMenuOptions(["OFF", "AUTO"])},
            {"number": 29, "name": "TxTOut", "description": "Tiempo maximo continuo de transmision", "settable": true, "options": qMenuOptions(["30 sec", "1 min", "2 min", "3 min", "4 min", "5 min", "6 min", "7 min", "8 min", "9 min", "15 min"])},
            {"number": 30, "name": "BatSav", "description": "Ciclo de ahorro de bateria", "settable": true, "options": qMenuOptions(["OFF", "1:1", "1:2", "1:3", "1:4"])},
            {"number": 31, "name": "Mic", "description": "Nivel de ganancia del microfono", "settable": true, "editorType": "spin", "minimum": 0, "maximum": 4, "options": qMenuOptions(["0", "1", "2", "3", "4"])},
            {"number": 32, "name": "MicBar", "description": "Muestra la barra de nivel de microfono", "settable": true, "options": onOff},
            {"number": 33, "name": "ChDisp", "description": "Formato mostrado para el canal", "settable": true, "options": qMenuOptions(["FREQ", "CHANNEL NUMBER", "NAME", "NAME + FREQ"])},
            {"number": 34, "name": "POnMsg", "description": "Pantalla de bienvenida al encender", "settable": true, "options": qMenuOptions(["FULL", "MESSAGE", "VOLTAGE", "NONE"])},
            {"number": 35, "name": "BatTxt", "description": "Informacion de bateria en pantalla", "settable": true, "options": qMenuOptions(["NONE", "VOLTAGE", "PERCENT"])},
            {"number": 36, "name": "BackLt", "description": "Tiempo de iluminacion de pantalla", "settable": true, "options": qMenuOptions(["OFF", "5 sec", "10 sec", "20 sec", "1 min", "2 min", "4 min", "ON"])},
            {"number": 37, "name": "BLMin", "description": "Brillo minimo de la pantalla", "settable": true, "editorType": "spin", "minimum": 0, "maximum": 9, "options": qMenuRange(0, 9)},
            {"number": 38, "name": "BLMax", "description": "Brillo maximo de la pantalla", "settable": true, "editorType": "spin", "minimum": 1, "maximum": 10, "options": qMenuRange(1, 10)},
            {"number": 39, "name": "BltTRX", "description": "Iluminacion asociada a TX y RX", "settable": true, "options": qMenuOptions(["OFF", "TX", "RX", "TX/RX"])},
            {"number": 40, "name": "Beep", "description": "Sonidos de confirmacion del teclado", "settable": true, "options": onOff},
            {"number": 41, "name": "Roger", "description": "Tono de fin de transmision", "settable": true, "options": qMenuOptions(["OFF", "ROGER", "MDC"])},
            {"number": 42, "name": "STE", "description": "Elimina el tono de cola de silenciador", "settable": true, "options": onOff},
            {"number": 43, "name": "RP STE", "description": "Retardo STE para repetidor", "settable": true, "options": qMenuOptions(["OFF", "1*100ms", "2*100ms", "3*100ms", "4*100ms", "5*100ms", "6*100ms", "7*100ms", "8*100ms", "9*100ms", "10*100ms"])},
            {"number": 44, "name": "1 Call", "description": "Canal de llamada rapida", "settable": true, "editorType": "spin", "minimum": 0, "maximum": 199, "options": qMenuRange(0, 199, "Canal ")},
            {"number": 45, "name": "ANI ID", "description": "Identificador personal enviado por DTMF", "settable": false, "options": disabled("Texto DTMF; pendiente de editor dedicado")},
            {"number": 46, "name": "UPCode", "description": "Codigo DTMF enviado al pulsar PTT", "settable": false, "options": disabled("Codigo DTMF; pendiente de editor dedicado")},
            {"number": 47, "name": "DWCode", "description": "Codigo DTMF enviado al soltar PTT", "settable": false, "options": disabled("Codigo DTMF; pendiente de editor dedicado")},
            {"number": 48, "name": "PTT ID", "description": "Momento de envio del identificador DTMF", "settable": true, "options": qMenuOptions(["OFF", "UP CODE", "DOWN CODE", "UP+DOWN CODE", "APOLLO QUINDAR"])},
            {"number": 49, "name": "D ST", "description": "Audicion local de tonos DTMF", "settable": true, "options": onOff},
            {"number": 50, "name": "D Resp", "description": "Respuesta a una llamada DTMF", "settable": true, "options": qMenuOptions(["DO NOTHING", "RING", "REPLY", "BOTH"])},
            {"number": 51, "name": "D Hold", "description": "Duracion de deteccion de codigo DTMF", "settable": true, "editorType": "spin", "minimum": 5, "maximum": 60, "options": qMenuRange(5, 60, "", " s")},
            {"number": 52, "name": "D Prel", "description": "Duracion previa al envio DTMF", "settable": true, "editorType": "spin", "minimum": 3, "maximum": 99, "options": qMenuRange(3, 99, "", "*10ms")},
            {"number": 53, "name": "D Decd", "description": "Decodificacion de tonos DTMF", "settable": true, "options": onOff},
            {"number": 54, "name": "D List", "description": "Lista de contactos DTMF permitidos", "settable": false, "options": disabled("Lista de contactos; pendiente de editor dedicado")},
            {"number": 55, "name": "D Live", "description": "Muestra en directo los tonos DTMF", "settable": true, "options": onOff},
            {"number": 56, "name": "AM Fix", "description": "Correccion de recepcion en modo AM", "settable": true, "options": onOff},
            {"number": 57, "name": "VOX", "description": "Sensibilidad de activacion por voz", "settable": true, "editorType": "spin", "minimum": 0, "maximum": 9, "options": qMenuOptions(["OFF", "1", "2", "3", "4", "5", "6", "7", "8", "9"])},
            {"number": 58, "name": "BatVol", "description": "Voltaje medido de la bateria", "settable": false, "options": disabled("Solo lectura en la radio")},
            {"number": 59, "name": "RxMode", "description": "Modo de recepcion dual y transmision", "settable": true, "options": qMenuOptions(["MAIN ONLY", "DUAL RX RESPOND", "CROSS BAND", "MAIN TX DUAL RX"])},
            {"number": 60, "name": "Remote", "description": "Control remoto desde la interfaz Dock", "settable": true, "options": onOff},
            {"number": 61, "name": "Sql", "description": "Nivel de silenciador", "settable": true, "editorType": "spin", "minimum": 0, "maximum": 9, "options": qMenuRange(0, 9)}
        ]
    }

    function appendGeneralLog(scope, text) {
        if (!text || String(text).trim() === "")
            return
        var now = new Date()
        var stamp = Qt.formatTime(now, "HH:mm:ss")
        var line = stamp + " · " + scope + " · " + String(text).replace(/\n/g, " ")
        generalLogText = (generalLogText ? generalLogText + "\n" : "") + line
        var lines = generalLogText.split("\n")
        if (lines.length > 400)
            generalLogText = lines.slice(lines.length - 400).join("\n")
    }

    function visibleGeneralLog() {
        if (generalLogFilter === "TODOS")
            return generalLogText || "Sin actividad registrada"
        var lines = generalLogText.split("\n")
        var result = []
        for (var i = 0; i < lines.length; ++i) {
            if (lines[i].indexOf(" · " + generalLogFilter + " · ") >= 0)
                result.push(lines[i])
        }
        return result.length ? result.join("\n") : "Sin entradas para este ámbito"
    }

    Connections {
        target: radioController

        function onTrafficChanged() {
            appendGeneralLog("ICOM", "TX " + radioController.lastTx + " | RX " + radioController.lastRx)
        }
        function onStatusChanged() {
            appendGeneralLog("ICOM", radioController.status)
        }
        function onActionStatusChanged() {
            var status = radioController.actionStatus
            var scope = status.toLowerCase().indexOf("registro") >= 0
                    || status.toLowerCase().indexOf("memoria") >= 0
                    ? "REGISTROS" : "ICOM"
            appendGeneralLog(scope, status)
        }
    }

    Connections {
        target: quanshengClient

        function onStateChanged() {
            window.rememberConfirmedQuanshengMenuStep()
            window.clearConfirmedQuanshengMenuPendingValues()
            if (window.quanshengRepeaterPendingDirection >= 0) {
                var repeaterDirection = quanshengClient.menuValues["7"]
                if (repeaterDirection && repeaterDirection.confirmed)
                    window.quanshengRepeaterPendingDirection = -1
            }
            var toneLog = quanshengClient.toneLog
            if (toneLog !== lastQuanshengToneLog) {
                var toneLines = toneLog.split("\n")
                if (toneLines.length && toneLines[toneLines.length - 1] !== "")
                    appendGeneralLog("TONOS", toneLines[toneLines.length - 1])
                lastQuanshengToneLog = toneLog
            }
            var eepromStatus = quanshengClient.eepromStatus
            if (eepromStatus !== lastQuanshengEepromStatus) {
                if (eepromStatus)
                    appendGeneralLog("EEPROM", eepromStatus)
                lastQuanshengEepromStatus = eepromStatus
            }
        }
        function onConnectedChanged() {
            if (!quanshengClient.connected) {
                window.quanshengWidthByVfo = ({})
                window.quanshengRxModeByVfo = ({})
                window.quanshengMenuStepVfo = ""
                window.quanshengMenuWidthVfo = ""
                window.quanshengMenuRxModeVfo = ""
            }
            appendGeneralLog("QUANSHENG", quanshengClient.connected ? "Conectado" : "Desconectado")
        }
        function onErrorChanged() {
            appendGeneralLog("QUANSHENG", quanshengClient.error)
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            applicationLauncher.startIcomVideo()
        })
        try {
            quanshengMenuReadSelection = JSON.parse(applicationLauncher.quanshengMenuReadSelectionJson)
        } catch (error) {
            quanshengMenuReadSelection = ({})
        }
        if (applicationLauncher.startupViewMode !== "normal") {
            Qt.callLater(function() {
                if (applicationLauncher.startupViewMode === "compact")
                    setCompactMode(true)
                else
                    setSuperCompactMode(true)
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
        if (startupComplete && visible && !compactVisible)
            applicationLauncher.mainWindowX = Math.round(x)
    }

    onYChanged: {
        if (startupComplete && visible && !compactVisible)
            applicationLauncher.mainWindowY = Math.round(y)
    }

    function fitMainWindowWidth() {
        const targetWidth = preferredMainWindowWidth
        if (window.minimumWidth !== targetWidth)
            window.minimumWidth = targetWidth
        if (window.width !== targetWidth)
            window.width = targetWidth
    }

    function detachVideoWindow() {
        const videoWindowWidth = detachedVideoWindow.width
        const videoWindowHeight = detachedVideoWindow.height
        detachedVideoWindow.x = Math.max(
            Screen.virtualX,
            Math.min(window.x + (window.width - videoWindowWidth) / 2,
                     Screen.virtualX + Screen.desktopAvailableWidth - videoWindowWidth))
        detachedVideoWindow.y = Math.max(
            Screen.virtualY,
            Math.min(window.y + 46,
                     Screen.virtualY + Screen.desktopAvailableHeight - videoWindowHeight))
        videoDetached = true
        Qt.callLater(function() {
            detachedVideoWindow.raise()
            detachedVideoWindow.requestActivate()
        })
    }

    Connections {
        target: applicationLauncher
        function onIcomVideoRunningChanged() {
            if (applicationLauncher.icomVideoRunning)
                videoCapture.startCapture()
            else
                videoCapture.stopCapture()
        }
    }

    Connections {
        target: applicationLauncher
        function onRadioPanelsVisibilityChanged() {
            panelResizeTimer.restart()
        }
    }

    Timer {
        id: panelResizeTimer
        interval: 150
        repeat: false
        onTriggered: window.fitMainWindowWidth()
    }

    Timer {
        id: memoryQuickWindowPositionSaveTimer
        interval: 250
        repeat: false
        onTriggered: window.saveMemoryQuickWindowPosition()
    }

    Timer {
        interval: 2200
        running: qrzLogbook.configured
        repeat: false
        onTriggered: qrzLogbook.refresh()
    }

    Timer {
        id: applicationShutdownTimer
        interval: 200
        repeat: false
        onTriggered: Qt.quit()
    }

    function beginApplicationShutdown() {
        if (applicationClosing)
            return
        // Keep the main window alive briefly while Qt removes Popup content
        // from Overlay.overlay. Destroying an open popup together with its
        // QQuickWindow can crash inside QQuickItem teardown on Qt 6.4.
        applicationClosing = true
        // La pestaña activa ya se guarda al cambiar; no permitir que el
        // cierre visual del panel la restablezca a Icom.
        quanshengPopup.close()
        bandStackingConfirmDialog.close()
        storeMemoryConfirmDialog.close()
        clearMemoryConfirmDialog.close()
        toneRttySettingsPopup.close()
        cwSettingsPopup.close()
        txSettingsPopup.close()
        digitalFrequencyPopup.close()
        quanshengBandMemorySaveTimer.stop()
        applicationLauncher.quanshengBandMemoriesJson = JSON.stringify(quanshengBandMemories)
        diagnosticsPopup.close()
        settingsPopup.close()
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
        if (memoryQuickWindow.visible)
            saveMemoryQuickWindowPosition()
        memoryQuickPanelVisible = false
        if (memoryQuickWindow.visible)
            memoryQuickWindow.close()
        scannerVisible = false
        scopeVisible = false
        videoDetached = false
        morseTrainerVisible = false
        morseTrainerWindow.visible = false
        morseTrainer.stopReceptionPlayback()
        morseTrainer.stopCapture()
        remoteServer.stop()
        applicationLauncher.stopIcomVideo()
        inlineVideoFrameItem.controller = null
        inlineVideoFrameItem.visible = false
        settingsVisible = false
        radioController.stopSpectrumScope()
        radioController.shutdown()
        // Give close transitions and Overlay reparenting one event-loop turn
        // before destroying QQmlApplicationEngine.
        applicationShutdownTimer.start()
    }

    onClosing: function(close) {
        if (applicationClosing)
            return
        close.accepted = false
        beginApplicationShutdown()
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
        if (enabled)
            superCompactReturnToCompact = compactVisible || compactWindow.visible
        else
            superCompactReturnToCompact = false
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

    function returnFromSuperCompact() {
        const returnToCompact = superCompactReturnToCompact
        superCompactReturnToCompact = false
        if (returnToCompact)
            setCompactMode(true)
        else
            setSuperCompactMode(false)
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

        function onLanConnectionChanged() {
            if (applicationLauncher.lanConnected
                    && !radioController.busy
                    && memoryQuickLoadedCount < 99) {
                // El escritor CI-V LAN se instala al recibir esta señal.
                Qt.callLater(function() {
                    if (applicationLauncher.lanConnected
                            && !radioController.busy
                            && memoryQuickLoadedCount < 99)
                        radioController.readMemoryRange(1, 99)
                })
            }
        }

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

    // Bandas de recepción que corresponden al rango del UV-K5.
    property var quanshengBandDefinitions: [
        { name: "F1", label: "50–76 MHz", minimum: 50, maximum: 76, frequency: 50.000 },
        { name: "F2", label: "108–137 MHz", minimum: 108, maximum: 137, frequency: 108.000 },
        { name: "F3", label: "137–174 MHz", minimum: 137, maximum: 174, frequency: 145.000 },
        { name: "VHF", label: "144–146 MHz", minimum: 144, maximum: 146, frequency: 145.000 },
        { name: "F4", label: "174–350 MHz", minimum: 174, maximum: 350, frequency: 174.000 },
        { name: "F5", label: "350–400 MHz", minimum: 350, maximum: 400, frequency: 350.000 },
        { name: "F6", label: "400–470 MHz", minimum: 400, maximum: 470, frequency: 433.000 },
        { name: "UHF", label: "430–440 MHz", minimum: 430, maximum: 440, frequency: 433.000 },
        { name: "F7", label: "470–1300 MHz", minimum: 470, maximum: 1300, frequency: 470.000 }
    ]

    property var bandMemories: JSON.parse(applicationLauncher.bandMemoriesJson)
    property var quanshengBandMemories: JSON.parse(applicationLauncher.quanshengBandMemoriesJson)
    property string activeQuanshengBandName: ""
    property var pendingQuanshengBandRestore: null
    property string currentBandName:
        bandNameForFrequency(activeVfoFrequencyHz())

    onBandMemoriesChanged: {
        applicationLauncher.bandMemoriesJson = JSON.stringify(bandMemories)
    }

    onQuanshengBandMemoriesChanged: {
        quanshengBandMemorySaveTimer.restart()
    }

    Timer {
        id: quanshengBandMemorySaveTimer
        interval: 400
        repeat: false
        onTriggered: applicationLauncher.quanshengBandMemoriesJson = JSON.stringify(quanshengBandMemories)
    }

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
        memoryQuickWindow.width =
            memoryQuickPanelWidth
        memoryQuickWindow.height =
            Math.min(window.height, Screen.desktopAvailableHeight)

        const screenLeft = Screen.virtualX
        const screenTop = Screen.virtualY
        const screenRight = screenLeft + Screen.desktopAvailableWidth
        const screenBottom = screenTop + Screen.desktopAvailableHeight
        const maxX = Math.max(screenLeft,
                              screenRight - memoryQuickWindow.width)
        const maxY = Math.max(screenTop,
                              screenBottom - memoryQuickWindow.height)
        const savedX = applicationLauncher.memoryQuickWindowX
        const savedY = applicationLauncher.memoryQuickWindowY
        const hasSavedPosition = savedX !== -1 && savedY !== -1
        const desiredX = hasSavedPosition
                         ? savedX
                         : window.x + 24
        const desiredY = hasSavedPosition
                         ? savedY
                         : window.y + 40

        memoryQuickWindow.x = Math.max(screenLeft,
                                       Math.min(desiredX, maxX))
        memoryQuickWindow.y = Math.max(screenTop,
                                       Math.min(desiredY, maxY))
    }

    function saveMemoryQuickWindowPosition() {
        applicationLauncher.memoryQuickWindowX = Math.round(memoryQuickWindow.x)
        applicationLauncher.memoryQuickWindowY = Math.round(memoryQuickWindow.y)
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

            if ((radioController.connected || applicationLauncher.lanConnected)
                    && !radioController.busy
                    && memoryQuickLoadedCount < 99) {
                radioController.readMemoryRange(1, 99)
            }

            return
        }

        saveMemoryQuickWindowPosition()
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

        if (applicationLauncher.lanConnected) {
            // The LAN CI-V frequency write addresses the selected VFO.
            // Keep the same band-memory behavior as the USB path.
            if (vfoNumber !== radioController.selectedVfo)
                return
            if (applicationLauncher.setLanFrequency(targetFrequency))
                radioController.setExternalFrequency(targetFrequency)
        } else {
            radioController.setVfoFrequency(
                vfoNumber,
                String(targetFrequency)
            )
        }
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

    function quanshengBandByName(name) {
        for (let index = 0; index < quanshengBandDefinitions.length; ++index) {
            const band = quanshengBandDefinitions[index]
            if (band.name === name)
                return band
        }
        return null
    }

    function quanshengBandNameForFrequency(mhz) {
        const frequency = Number(mhz)
        if (!isFinite(frequency))
            return ""
        if (frequency >= 144 && frequency <= 146)
            return "VHF"
        if (frequency >= 430 && frequency <= 440)
            return "UHF"
        if (frequency >= 50 && frequency <= 76)
            return "F1"
        if (frequency >= 108 && frequency <= 137)
            return "F2"
        if (frequency >= 137 && frequency <= 174)
            return "F3"
        if (frequency >= 174 && frequency <= 350)
            return "F4"
        if (frequency >= 350 && frequency <= 400)
            return "F5"
        if (frequency >= 400 && frequency <= 470)
            return "F6"
        if (frequency >= 470 && frequency <= 1300)
            return "F7"
        return ""
    }

    function quanshengBandMemoryKey(vfo, bandName) {
        return String(vfo || "A") + ":" + bandName
    }

    function currentQuanshengVfoState(vfo) {
        const isB = vfo === "B"
        const frequency = Number(String(isB ? quanshengClient.vfoBFrequencyText
                                            : quanshengClient.vfoAFrequencyText).replace(",", "."))
        return {
            frequency: frequency,
            mode: isB ? quanshengClient.vfoBMode : quanshengClient.vfoAMode,
            power: isB ? quanshengClient.vfoBPower : quanshengClient.vfoAPower,
            step: isB ? quanshengClient.vfoBStep : quanshengClient.vfoAStep,
            memory: isB ? quanshengClient.vfoBMemory : quanshengClient.vfoAMemory,
            name: isB ? quanshengClient.vfoBName : quanshengClient.vfoAName,
            tones: quanshengClient.toneStates[vfo] || null
        }
    }

    function rememberQuanshengBandState(vfo) {
        if (vfo !== "A" && vfo !== "B")
            return
        const state = currentQuanshengVfoState(vfo)
        if (!quanshengPopup.frequencyAllowed(state.frequency))
            return
        let bandName = activeQuanshengBandName
        if (!bandName && quanshengBandByName(state.memory))
            bandName = state.memory
        const activeBand = quanshengBandByName(bandName)
        if (!activeBand || state.frequency < activeBand.minimum
                || state.frequency > activeBand.maximum) {
            bandName = quanshengBandNameForFrequency(state.frequency)
        }
        if (!bandName)
            return
        const key = quanshengBandMemoryKey(vfo, bandName)
        const nextState = {
            frequency: state.frequency,
            mode: state.mode || "",
            power: state.power || "",
            step: state.step || "",
            memory: state.memory || "",
            name: state.name || "",
            tones: state.tones || null
        }
        const previousState = quanshengBandMemories[key]
        if (previousState && JSON.stringify(previousState) === JSON.stringify(nextState))
            return
        const updated = ({})
        for (const storedKey in quanshengBandMemories)
            updated[storedKey] = quanshengBandMemories[storedKey]
        updated[key] = nextState
        quanshengBandMemories = updated
    }

    function selectQuanshengBand(band) {
        if (!quanshengClient.connected || !quanshengClient.frequencyControlAvailable
                || quanshengClient.controlBusy)
            return
        if (!band)
            return
        const vfo = quanshengClient.activeVfo === "B" ? "B" : "A"
        const key = quanshengBandMemoryKey(vfo, band.name)
        const remembered = quanshengBandMemories[key]
        const targetFrequency = remembered && remembered.frequency !== undefined
            ? Number(remembered.frequency)
            : Number(band.frequency)
        activeQuanshengBandName = band.name
        pendingQuanshengBandRestore = {
            vfo: vfo,
            frequency: targetFrequency,
            mode: remembered ? remembered.mode || "" : "",
            tones: remembered ? remembered.tones || null : null,
            stage: "frequency"
        }
        if (quanshengPopup.vfoInMemoryMode(vfo)) {
            pendingQuanshengBandRestore.stage = "vfoMode"
            quanshengClient.toggleVfoMode(vfo)
            return
        }
        quanshengClient.setFrequency(targetFrequency.toFixed(6))
    }

    function advanceQuanshengBandRestore() {
        const restore = pendingQuanshengBandRestore
        if (!restore || quanshengClient.controlBusy || !quanshengClient.connected
                || !quanshengClient.frequencyControlAvailable)
            return
        if (restore.vfo !== quanshengClient.activeVfo)
            return
        if (restore.stage === "vfoMode") {
            if (quanshengPopup.vfoInMemoryMode(restore.vfo))
                return
            restore.stage = "frequency"
            quanshengClient.setFrequency(Number(restore.frequency).toFixed(6))
            return
        }
        const current = Number(String(restore.vfo === "B"
                                     ? quanshengClient.vfoBFrequencyText
                                     : quanshengClient.vfoAFrequencyText).replace(",", "."))
        if (!isFinite(current) || Math.abs(current - Number(restore.frequency)) > 0.0005)
            return
        if (restore.stage === "frequency") {
            restore.stage = "mode"
            const currentMode = restore.vfo === "B" ? quanshengClient.vfoBMode : quanshengClient.vfoAMode
            if (restore.mode && currentMode !== restore.mode) {
                quanshengClient.setMode(restore.vfo, restore.mode)
                return
            }
        }
        if (restore.stage === "mode") {
            restore.stage = "toneRx"
            const rx = restore.tones && restore.tones.rx
            if (rx && quanshengClient.toneControlAvailable) {
                quanshengClient.setTone(restore.vfo, "RX", Number(rx.type), Number(rx.index))
                return
            }
        }
        if (restore.stage === "toneRx") {
            restore.stage = "toneTx"
            const tx = restore.tones && restore.tones.tx
            if (tx && quanshengClient.toneControlAvailable) {
                quanshengClient.setTone(restore.vfo, "TX", Number(tx.type), Number(tx.index))
                return
            }
        }
        pendingQuanshengBandRestore = null
    }

    function quanshengBandButtonHelp(modelData) {
        const vfo = quanshengClient.activeVfo === "B" ? "B" : "A"
        const remembered = quanshengBandMemories[quanshengBandMemoryKey(vfo, modelData.name)]
        if (!remembered)
            return modelData.label + " · primera vez " + Number(modelData.frequency).toFixed(3) + " MHz"
        const parts = [modelData.label, Number(remembered.frequency).toFixed(6) + " MHz"]
        if (remembered.mode)
            parts.push(remembered.mode)
        if (remembered.power)
            parts.push("Pwr " + remembered.power)
        if (remembered.tones && remembered.tones.rx && remembered.tones.tx)
            parts.push("RX " + remembered.tones.rx.text + " / TX " + remembered.tones.tx.text)
        return parts.join(" · ")
    }

    function controlsEnabled() {
        return (radioController.connected || applicationLauncher.lanConnected)
               && !radioController.transmitting
               // El estado busy pertenece a la cola CI-V por USB. No debe
               // bloquear los controles cuando la sesión activa es LAN.
               // Durante el ajuste de frecuencia se mantiene estable la
               // apariencia del panel; el controlador sigue rechazando
               // otras órdenes hasta terminar la verificación CI-V.
               && (applicationLauncher.lanConnected
                   || !radioController.busy
                   || radioController.frequencyWritePending)
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

        if (adjustTuningFrequency(
            radioController.selectedVfo,
            stepCount * selectedStep()
        ))
            tuningAngle += stepCount * 8
    }

    function adjustTuningFrequency(vfoNumber, deltaHz) {
        if (applicationLauncher.lanConnected) {
            // The LAN frequency command addresses the selected VFO only.
            if (vfoNumber !== radioController.selectedVfo)
                return false
            const current = Number(radioController.frequencyHz)
            if (current <= 0)
                return false
            const target = current + deltaHz
            if (!applicationLauncher.setLanFrequency(target))
                return false
            // Accumulate fast wheel steps immediately. Incoming radio
            // frequency reports subsequently reconcile the displayed value.
            radioController.setExternalFrequency(target)
            return true
        }
        radioController.adjustVfoFrequency(vfoNumber, deltaHz)
        return true
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

    function formatQuanshengFrequency(text) {
        if (!text)
            return "—"
        var parts = String(text).split(".")
        if (parts.length !== 2)
            return text
        var fraction = parts[1]
        while (fraction.length < 6)
            fraction += "0"
        fraction = fraction.substring(0, 6)
        return parts[0] + "." + fraction.substring(0, 3)
               + "." + fraction.substring(3, 6)
    }

    function quanshengFrequencyMain(text) {
        var formatted = formatQuanshengFrequency(text)
        return formatted.substring(0, formatted.length - 3)
    }

    function quanshengFrequencyHz(text) {
        var formatted = formatQuanshengFrequency(text)
        return formatted.substring(formatted.length - 3)
    }

    function quanshengSignalPercent() {
        if (quanshengClient.candidateState !== "RX"
                || quanshengClient.signalLevel < 0)
            return 0
        return Math.min(100, (quanshengClient.signalLevel * 8)
                        + (quanshengClient.signalOver * 4))
    }

    function quanshengPowerPercent() {
        var power = quanshengClient.activeVfo === "B"
                    ? quanshengClient.vfoBPower : quanshengClient.vfoAPower
        if (power === "H" || power === "High")
            return 100
        if (power === "M" || power === "Med" || power === "Medium")
            return 66
        if (power === "L" || power === "Low")
            return 33
        return 0
    }

    function quanshengPowerText() {
        var power = quanshengClient.activeVfo === "B"
                    ? quanshengClient.vfoBPower : quanshengClient.vfoAPower
        return power === "H" ? "High" : power === "M" ? "Med" : power === "L" ? "Low" : (power || "—")
    }

    function quanshengToneValue(vfo, family, direction) {
        var state = quanshengClient.toneStates[vfo]
        var values = state ? state[family] : null
        var tone = values ? values[direction] : null
        return tone && tone.text ? tone.text : "—"
    }

    function quanshengBatteryColor() {
        var p = quanshengClient.batteryPercent
        return p < 0 ? "#65747b" : p <= 20 ? "#e74c3c" : p <= 45 ? "#e67e22" : p <= 70 ? "#f1c40f" : "#2ecc71"
    }

    function quanshengRegistersClipboardText() {
        var lines = ["Registro\tValor\tInterpretación"]
        for (var i = 0; i < quanshengClient.hardwareRegisterRows.length; ++i) {
            var row = quanshengClient.hardwareRegisterRows[i]
            lines.push((row.register || "—") + "\t"
                       + (row.value || "—") + "\t"
                       + (row.interpretation || "—"))
        }
        return lines.join("\n")
    }

    function quanshengUserSettingRows() {
        var rows = []
        for (var i = 0; i < quanshengClient.eepromSettingRows.length; ++i) {
            var row = quanshengClient.eepromSettingRows[i]
            var address = parseInt(String(row.address).substring(2), 16)
            if (address >= 0x0e70 && address <= 0x0f47)
                rows.push(row)
        }
        return rows
    }

    function quanshengUserSettingValue(address) {
        var wanted = String(address).toUpperCase()
        for (var i = 0; i < quanshengClient.eepromSettingRows.length; ++i) {
            var row = quanshengClient.eepromSettingRows[i]
            if (String(row.address).toUpperCase() === wanted)
                return row.value || "—"
        }
        return "—"
    }

    component QuanshengActionButton: Button {
        id: quanshengActionButton
        implicitHeight: 27
        padding: 5
        font.pixelSize: 10
        font.bold: true
        palette.buttonText: enabled ? "#edf3f6" : "#788287"
        background: Rectangle {
            radius: 2
            color: quanshengActionButton.down
                   ? "#315f7a"
                   : quanshengActionButton.hovered ? "#35434a" : "#202629"
            border.color: quanshengActionButton.hovered ? "#72ceff" : "#5c6b72"
            border.width: 1
        }
    }

    component QuanshengSectionHeader: Rectangle {
        property string text: ""
        Layout.fillWidth: true
        Layout.preferredHeight: 19
        radius: 2
        color: "#20272b"
        border.color: "#4d9fc1"
        border.width: 1

        Text {
            anchors.fill: parent
            anchors.leftMargin: 7
            text: parent.text
            color: "#9edcf4"
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 0.5
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Segunda página de radio. Se mantiene separada del controlador CI-V y
    // comparte únicamente la barra superior de la aplicación.
    Rectangle {
        id: quanshengPopup
        parent: radioPageHost
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 0
        visible: applicationLauncher.quanshengPanelVisible
        color: "#414141"
        border.color: "#5886ad"
        border.width: 1
        radius: 4
        property int leftPadding: 12
        property int rightPadding: 12
        property real candidateFrequencyMHz: 145.675
        property bool candidateFrequencyTouched: false
        property real editedFrequencyAMHz: 145.675
        property real editedFrequencyBMHz: 145.675
        property bool editedFrequencyATouched: false
        property bool editedFrequencyBTouched: false
        readonly property bool quanshengTxActive:
            quanshengClient.connected
            && (quanshengClient.candidateState === "TX" || quanshengClient.pttPressed)
        readonly property string controlUnavailableMessage:
            !quanshengClient.connected ? "SERVIDOR DESCONECTADO"
            : quanshengClient.sourceStatus !== "listening"
              ? "SERVIDOR " + quanshengClient.sourceStatus.toUpperCase()
            : quanshengClient.serialPortState !== "open"
              ? quanshengClient.serialPortState === "busy" ? "PUERTO SERIE OCUPADO"
                : quanshengClient.serialPortState === "error" ? "ERROR EN PUERTO SERIE"
                  : "PUERTO SERIE NO DISPONIBLE"
            : !quanshengClient.frequencyControlAvailable
              ? "CONTROL REMOTO NO HABILITADO"
            : quanshengClient.eepromBusy ? "LECTURA EEPROM EN CURSO"
            : quanshengClient.controlBusy ? "ORDEN DE RADIO EN CURSO"
            : quanshengPopup.quanshengTxActive ? "RADIO EN TX"
            : ""
        readonly property bool commandControlsUnavailable:
            controlUnavailableMessage !== ""

        function open() { applicationLauncher.quanshengPanelVisible = true }
        function close() {
            if (!applicationClosing)
                applicationLauncher.quanshengPanelVisible = false
        }

        function syncCandidateFrequency() {
            syncEditedFrequency("A")
            syncEditedFrequency("B")
            if (candidateFrequencyTouched)
                return
            var text = quanshengClient.activeVfo === "B"
                       ? quanshengClient.vfoBFrequencyText
                       : quanshengClient.vfoAFrequencyText
            var value = Number(String(text).replace(",", "."))
            if (frequencyAllowed(value))
                candidateFrequencyMHz = value
        }

        function editedFrequency(vfo) {
            return vfo === "B" ? editedFrequencyBMHz : editedFrequencyAMHz
        }

        function editedFrequencyTouched(vfo) {
            return vfo === "B" ? editedFrequencyBTouched : editedFrequencyATouched
        }

        function setEditedFrequency(vfo, value) {
            if (vfo === "B") {
                editedFrequencyBMHz = value
                editedFrequencyBTouched = true
            } else {
                editedFrequencyAMHz = value
                editedFrequencyATouched = true
            }
        }

        function syncEditedFrequency(vfo) {
            var text = vfo === "B"
                       ? quanshengClient.vfoBFrequencyText
                       : quanshengClient.vfoAFrequencyText
            var value = Number(String(text).replace(",", "."))
            if (!frequencyAllowed(value))
                return
            var current = editedFrequency(vfo)
            if (!editedFrequencyTouched(vfo) || Math.abs(current - value) < 0.0000005) {
                if (vfo === "B") {
                    editedFrequencyBMHz = value
                    editedFrequencyBTouched = false
                } else {
                    editedFrequencyAMHz = value
                    editedFrequencyATouched = false
                }
            }
        }

        function editedFrequencyDisplay(vfo) {
            return formatQuanshengFrequency(editedFrequency(vfo).toFixed(6))
        }

        function adjustEditedFrequencyAt(vfo, x, width, direction) {
            var shown = editedFrequencyDisplay(vfo)
            var position = Math.max(0, Math.min(shown.length - 1,
                Math.floor(x / Math.max(1, width) * shown.length)))
            while (position < shown.length && shown.charAt(position) === ".")
                ++position
            if (position >= shown.length)
                return
            var digitsRight = 0
            for (var index = position + 1; index < shown.length; ++index)
                if (shown.charAt(index) !== ".")
                    ++digitsRight
            if (digitsRight < 1)
                return
            var currentHz = Math.round(editedFrequency(vfo) * 1000000)
            var incrementHz = Math.pow(10, digitsRight)
            setEditedFrequency(vfo, (currentHz + direction * incrementHz) / 1000000)
        }

        function zeroEditedFrequencyRight(vfo, digitsRight) {
            if (digitsRight < 1 || vfo !== quanshengClient.activeVfo
                    || activeVfoInMemoryMode())
                return
            var currentHz = Math.round(editedFrequency(vfo) * 1000000)
            var scaleHz = Math.pow(10, digitsRight)
            var targetHz = Math.floor(currentHz / scaleHz) * scaleHz
            setEditedFrequency(vfo, targetHz / 1000000)
        }

        function validateEditedFrequency(vfo) {
            if (vfo !== quanshengClient.activeVfo
                    || activeVfoInMemoryMode()
                    || !frequencyAllowed(editedFrequency(vfo)))
                return
            quanshengClient.setFrequency(editedFrequency(vfo).toFixed(6))
        }

        function activeFrequencyMHz() {
            var text = quanshengClient.activeVfo === "B"
                       ? quanshengClient.vfoBFrequencyText
                       : quanshengClient.vfoAFrequencyText
            return Number(String(text).replace(",", "."))
        }

        function frequencyAllowed(value) {
            var mhz = Number(value)
            return isFinite(mhz) && mhz >= 18 && mhz <= 1300
                   && !(mhz > 630 && mhz < 840)
        }

        function activeVfoInMemoryMode() {
            var memory = quanshengClient.activeVfo === "B"
                         ? quanshengClient.vfoBMemory
                         : quanshengClient.vfoAMemory
            return memory === "Memoria" || String(memory).startsWith("M")
        }

        function vfoInMemoryMode(vfo) {
            var memory = vfo === "B"
                         ? quanshengClient.vfoBMemory
                         : quanshengClient.vfoAMemory
            return memory === "Memoria" || String(memory).startsWith("M")
        }

        function stepFrequencyFromDisplay(vfo, up) {
            if (vfo === "B")
                editedFrequencyBTouched = false
            else
                editedFrequencyATouched = false
            syncEditedFrequency(vfo)
            quanshengClient.stepFrequency(vfo, up)
        }

        function frequencyStepMHz(vfo) {
            return 0.00001
        }

        function snapCandidate(value, vfo) {
            var step = frequencyStepMHz(vfo)
            return Math.max(18, Math.min(1300, Math.round(value / step) * step))
        }

        function candidateDisplayText() {
            var text = candidateFrequencyMHz.toFixed(6)
            var parts = text.split(".")
            var integerPart = parts[0].padStart(4, "0")
            var fraction = (parts[1] || "000000").padEnd(6, "0")
            return integerPart + "." + fraction.substring(0, 3)
                   + "." + fraction.substring(3)
        }

        function candidateDigitIncrementAtPosition(position, vfo) {
            var shown = candidateDisplayText()
            var digitsRight = 0
            for (var i = position + 1; i < shown.length; ++i) {
                if (shown.charAt(i) !== ".")
                    ++digitsRight
            }
            if (digitsRight <= 4)
                return frequencyStepMHz(vfo)
            return Math.pow(10, digitsRight - 6)
        }

        function adjustCandidateAt(x, width, direction, visualWidth) {
            var shown = candidateDisplayText()
            visualWidth = Math.min(width, visualWidth || width)
            var left = width - visualWidth
            var position = Math.max(0, Math.min(shown.length - 1,
                Math.floor((x - left) / Math.max(1, visualWidth) * shown.length)))
            while (position < shown.length && shown.charAt(position) === ".")
                ++position
            if (position >= shown.length)
                return
            var vfo = quanshengClient.activeVfo
            candidateFrequencyTouched = true
            candidateFrequencyMHz = snapCandidate(candidateFrequencyMHz
                + direction * candidateDigitIncrementAtPosition(position, vfo), vfo)
        }

        onVisibleChanged: {
            if (!visible) quanshengClient.releasePtt()
            if (visible) {
                candidateFrequencyTouched = false
                syncCandidateFrequency()
            }
        }
        Connections {
            target: quanshengClient
            function onStateChanged() {
                quanshengPopup.syncCandidateFrequency()
                window.rememberQuanshengBandState("A")
                window.rememberQuanshengBandState("B")
                window.advanceQuanshengBandRestore()
            }
        }

        Item {
            anchors.fill: parent
            z: 100
            visible: quanshengPopup.quanshengTxActive

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.64, 360)
                height: 104
                color: "#300306"
                border.color: "#70201b"
                border.width: 3
                radius: height / 2
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.88; duration: 1300 }
                    NumberAnimation { from: 0.88; to: 1.0; duration: 1300 }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -7
                    color: "transparent"
                    border.color: "#45ff2522"
                    border.width: 7
                    radius: height / 2
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    border.color: "#b93124"
                    border.width: 1
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#650609" }
                        GradientStop { position: 0.22; color: "#c20b10" }
                        GradientStop { position: 0.5; color: "#ec1719" }
                        GradientStop { position: 0.78; color: "#c20b10" }
                        GradientStop { position: 1.0; color: "#650609" }
                    }
                }

                Text {
                    anchors.fill: parent
                    text: "ON AIR"
                    color: "#ff321d"
                    opacity: 0.72
                    scale: 1.045
                    font.family: "DejaVu Sans"
                    font.pixelSize: 47
                    font.bold: true
                    font.letterSpacing: 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    anchors.fill: parent
                    text: "ON AIR"
                    color: "#ffe8c3"
                    font.family: "DejaVu Sans"
                    font.pixelSize: 44
                    font.bold: true
                    font.letterSpacing: 2
                    style: Text.Outline
                    styleColor: "#ff751f"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Item {
            anchors.fill: parent
            z: 90
            visible: quanshengPopup.commandControlsUnavailable
                     && !quanshengPopup.quanshengTxActive

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 10
                width: Math.min(parent.width - 32, 370)
                height: 34
                color: "#e51c2226"
                border.color: "#c8a65d"
                border.width: 1
                radius: 3

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    text: quanshengPopup.controlUnavailableMessage
                    color: "#efd69a"
                    font.pixelSize: 11
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 12
            opacity: quanshengPopup.commandControlsUnavailable ? 0.68 : 1.0

            FrameBox {
                visible: false
                // The old side band column is hidden; it must not reserve
                // horizontal space in the two-radio layout.
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                Layout.maximumWidth: 0
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
                            id: quanshengPttButton
                            Layout.fillWidth: true
                            implicitHeight: 31
                            enabled: quanshengClient.connected && quanshengClient.txControlAvailable
                                     && (quanshengClient.pttPressed
                                         || (!quanshengClient.controlBusy && !quanshengClient.eepromBusy))
                            autoRepeat: false
                            onPressed: quanshengClient.pressPtt()
                            onReleased: quanshengClient.releasePtt()
                            onCanceled: quanshengClient.releasePtt()
                            onEnabledChanged: if (!enabled) quanshengClient.releasePtt()
                            background: Rectangle {
                                radius: 2
                                color: quanshengClient.pttPressed ? "#a92b2b" : "#2b0d0d"
                                border.color: quanshengPttButton.enabled ? "#d97878" : "#744545"
                            }
                            contentItem: Text {
                                text: quanshengClient.pttPressed ? "SOLTAR PTT" : "PTT"
                                color: quanshengPttButton.enabled ? "#ffffff" : "#8c7777"
                                font.pixelSize: 12
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: "Mantén pulsado para transmitir. " + quanshengClient.pttStatus
                        }
                        SelectableLabel {
                            Layout.fillWidth: true
                            text: quanshengClient.pttStatus
                            wrapMode: Text.Wrap
                            font.pixelSize: 9
                            color: "#d9b7b7"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    SidePanelGroup {
                        caption: "NIVELES RF"
                        accentColor: "#b99956"

                        KnobControl {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 94
                            Layout.maximumHeight: 94
                            compact: true
                            caption: "RF POWER"
                            currentValue: (quanshengClient.activeVfo === "B"
                                           ? quanshengClient.vfoBPower
                                           : quanshengClient.vfoAPower) === "H" ? 100
                                          : (quanshengClient.activeVfo === "B"
                                             ? quanshengClient.vfoBPower
                                             : quanshengClient.vfoAPower) === "M" ? 50 : 15
                            accentColor: "#f2c94c"
                            enabled: false
                            applyFunction: function(value) {}
                            ToolTip.visible: hovered
                            ToolTip.text: "Potencia observada; el ajuste aún no está habilitado."
                        }
                    }
                }
            }

            ScrollView {
                anchors.fill: parent
                clip: true
                contentWidth: Math.max(0, quanshengPopup.width - 24)
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    width: Math.max(0, quanshengPopup.width - 24)
                    spacing: 7

            RowLayout {
                Layout.fillWidth: true
                visible: false
                Layout.preferredHeight: 0
                Layout.minimumHeight: 0
                Layout.maximumHeight: 0
                Item { Layout.fillWidth: true }
                QuanshengActionButton {
                    text: quanshengClient.connected ? "Desconectar" : "Conectar"
                    onClicked: quanshengClient.connected
                              ? quanshengClient.disconnectFromServer()
                              : quanshengClient.connectToServer()
                }
                QuanshengActionButton {
                    text: "Reiniciar servidor"
                    enabled: quanshengClient.connected
                    onClicked: quanshengClient.restartServer()
                    ToolTip.visible: hovered && !enabled
                    ToolTip.text: "Conecta primero con el servidor Quansheng"
                }
                SelectableLabel {
                    text: quanshengClient.eventStreamStalled
                          ? "SIN EVENTOS · " + quanshengClient.eventSilenceSeconds + " s"
                          : quanshengClient.sourceStatus
                    color: quanshengClient.eventStreamStalled
                           ? "#ff6b6b"
                           : (quanshengClient.connected ? "#8fdb9b" : "#e5c07b")
                    font.bold: quanshengClient.eventStreamStalled
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 27
                spacing: 3
                Repeater {
                    model: quanshengBandDefinitions
                    PanelButton {
                        id: compactQuanshengBandButton
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: 26
                        text: modelData.name
                        textPixelSize: 9
                        readonly property bool quickSubBand:
                            modelData.name === "VHF" || modelData.name === "UHF"
                        contentItem: RowLayout {
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: !compactQuanshengBandButton.enabled ? "#818181"
                                      : compactQuanshengBandButton.quickSubBand
                                        ? (compactQuanshengBandButton.selected ? "#fff4bf" : "#ffd36a")
                                        : "#f1f1f1"
                                font.pixelSize: 9
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                Layout.preferredWidth: 38
                                text: modelData.label.replace(" MHz", "")
                                color: !compactQuanshengBandButton.enabled ? "#6f777b"
                                      : compactQuanshengBandButton.quickSubBand
                                        ? (compactQuanshengBandButton.selected ? "#fff0a0" : "#d6a23a")
                                        : "#69d6ff"
                                font.pixelSize: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                        selected: quanshengClient.activeVfo === "A"
                                  ? activeQuanshengBandName === modelData.name
                                    || (activeQuanshengBandName === ""
                                        && String(quanshengClient.vfoAMemory).startsWith(modelData.name))
                                  : activeQuanshengBandName === modelData.name
                                    || (activeQuanshengBandName === ""
                                        && String(quanshengClient.vfoBMemory).startsWith(modelData.name))
                        activeColor: quickSubBand ? "#8b5f12" : "#4a4a4a"
                        groupAccentColor: quickSubBand ? "#d49a24" : "#5f8799"
                        enabled: quanshengClient.connected
                                 && quanshengClient.frequencyControlAvailable
                                 && !quanshengClient.controlBusy
                        ToolTip.visible: hovered
                        ToolTip.text: quanshengBandButtonHelp(modelData)
                        onClicked: selectQuanshengBand(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                spacing: 6
                QuanshengActionButton {
                    text: quanshengClient.pttPressed ? "SOLTAR PTT" : "PTT"
                    Layout.preferredWidth: 96
                    enabled: quanshengClient.connected && quanshengClient.txControlAvailable
                             && (quanshengClient.pttPressed
                                 || (!quanshengClient.controlBusy && !quanshengClient.eepromBusy))
                    onPressed: quanshengClient.pressPtt()
                    onReleased: quanshengClient.releasePtt()
                    onCanceled: quanshengClient.releasePtt()
                    background: Rectangle {
                        radius: 2
                        color: quanshengClient.pttPressed ? "#a92b2b" : "#2b0d0d"
                        border.color: parent.enabled ? "#d97878" : "#744545"
                    }
                }
                SelectableLabel {
                    text: quanshengClient.pttStatus
                    color: "#d9b7b7"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 3
                    SelectableLabel {
                        visible: quanshengClient.connected && quanshengClient.activeVfo === ""
                        text: "VFO ?"
                        color: "#e5c07b"
                        font.pixelSize: 9
                        font.bold: true
                        ToolTip.visible: hovered
                        ToolTip.text: "Esperando a que la radio confirme el VFO activo"
                    }
                    Button {
                        readonly property bool activeVfo: quanshengClient.activeVfo === "A"
                        text: "A"
                        Layout.preferredWidth: 29
                        Layout.minimumWidth: 29
                        Layout.maximumWidth: 29
                        implicitHeight: 27
                        enabled: quanshengClient.connected
                                 && quanshengClient.frequencyControlAvailable
                                 && !quanshengClient.controlBusy
                        palette.buttonText: activeVfo ? "#102018" : "#c9d8ce"
                        background: Rectangle {
                            color: parent.activeVfo ? "#69c98b" : "#26372d"
                            border.color: parent.activeVfo ? "#b9f6ca" : "#526b5a"
                            border.width: parent.activeVfo ? 2 : 1
                            radius: 2
                        }
                        onClicked: if (!activeVfo) quanshengClient.switchVfo()
                        ToolTip.visible: hovered
                        ToolTip.text: "Seleccionar VFO A"
                    }
                    Button {
                        readonly property bool activeVfo: quanshengClient.activeVfo === "B"
                        text: "B"
                        Layout.preferredWidth: 29
                        Layout.minimumWidth: 29
                        Layout.maximumWidth: 29
                        implicitHeight: 27
                        enabled: quanshengClient.connected
                                 && quanshengClient.frequencyControlAvailable
                                 && !quanshengClient.controlBusy
                        palette.buttonText: activeVfo ? "#201508" : "#e1d4c0"
                        background: Rectangle {
                            color: parent.activeVfo ? "#e0a24d" : "#403321"
                            border.color: parent.activeVfo ? "#ffd08a" : "#806640"
                            border.width: parent.activeVfo ? 2 : 1
                            radius: 2
                        }
                        onClicked: if (!activeVfo) quanshengClient.switchVfo()
                        ToolTip.visible: hovered
                        ToolTip.text: "Seleccionar VFO B"
                    }
                }
                Button {
                    id: quanshengDwrButton
                    readonly property string selectedMode:
                        window.quanshengRxModeForVfo(quanshengClient.activeVfo)
                    readonly property bool dwrActive: selectedMode === "DUAL RX RESPOND"
                        || (selectedMode === "" && quanshengClient.dualWatchKnown
                            && quanshengClient.dualWatch)
                    text: selectedMode === "MAIN ONLY" ? "RX MAIN"
                          : selectedMode === "DUAL RX RESPOND" ? "RX DWR"
                          : selectedMode === "CROSS BAND" ? "RX X-BAND"
                          : selectedMode === "MAIN TX DUAL RX" ? "RX MAIN+DUAL"
                          : "RX MODE"
                    Layout.preferredWidth: 92
                    Layout.minimumWidth: 92
                    Layout.maximumWidth: 92
                    implicitHeight: 27
                    enabled: quanshengClient.connected
                             && quanshengClient.frequencyControlAvailable
                             && !quanshengClient.controlBusy
                    palette.buttonText: dwrActive ? "#102018" : "#d6e2e7"
                    background: Rectangle {
                        color: quanshengDwrButton.dwrActive ? "#69c98b" : "#303a3f"
                        border.color: quanshengDwrButton.dwrActive ? "#b9f6ca" : "#65747b"
                        border.width: quanshengDwrButton.dwrActive ? 2 : 1
                        radius: 2
                    }
                    onClicked: quanshengRxModeMenu.popup()
                    ToolTip.visible: hovered
                    ToolTip.text: selectedMode || "Seleccionar modo de recepción"
                    Menu {
                        id: quanshengRxModeMenu
                        MenuItem {
                            text: "MAIN ONLY"
                            onTriggered: window.applyQuanshengMainMenuValue(59, 0, quanshengClient.activeVfo)
                        }
                        MenuItem {
                            text: "DUAL RX RESPOND"
                            onTriggered: window.applyQuanshengMainMenuValue(59, 1, quanshengClient.activeVfo)
                        }
                        MenuItem {
                            text: "CROSS BAND"
                            onTriggered: window.applyQuanshengMainMenuValue(59, 2, quanshengClient.activeVfo)
                        }
                        MenuItem {
                            text: "MAIN TX DUAL RX"
                            onTriggered: window.applyQuanshengMainMenuValue(59, 3, quanshengClient.activeVfo)
                        }
                    }
                }
                Button {
                    id: quanshengVoxButton
                    readonly property bool active: quanshengClient.voxKnown
                                                  && quanshengClient.vox
                    text: "VOX"
                    Layout.preferredWidth: 44
                    Layout.minimumWidth: 44
                    Layout.maximumWidth: 44
                    implicitHeight: 27
                    enabled: quanshengClient.connected
                             && quanshengClient.frequencyControlAvailable
                             && !quanshengClient.controlBusy
                    palette.buttonText: active ? "#102018" : "#d6e2e7"
                    background: Rectangle {
                        color: quanshengVoxButton.active ? "#69c98b" : "#303a3f"
                        border.color: quanshengVoxButton.active ? "#b9f6ca" : "#65747b"
                        border.width: quanshengVoxButton.active ? 2 : 1
                        radius: 2
                    }
                    onClicked: quanshengClient.setVox(!quanshengClient.vox)
                    ToolTip.visible: hovered
                    ToolTip.text: quanshengClient.vox
                                  ? "Desactivar VOX" : "Activar VOX"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 3

                SelectableLabel {
                    text: "REP " + (quanshengClient.activeVfo || "?")
                    color: "#d0d0d0"
                    font.pixelSize: 10
                    font.bold: true
                    Layout.preferredWidth: 54
                }
                Repeater {
                    model: ["OFF", "+", "−"]
                    delegate: Button {
                        required property int index
                        required property string modelData
                        readonly property int confirmedDirection: quanshengRepeaterConfirmedDirection()
                        text: modelData
                        Layout.preferredWidth: 32
                        Layout.minimumWidth: 32
                        Layout.maximumWidth: 32
                        Layout.preferredHeight: 25
                        enabled: quanshengClient.connected
                                 && quanshengClient.frequencyControlAvailable
                                 && !quanshengClient.controlBusy
                                 && (quanshengClient.activeVfo === "A" || quanshengClient.activeVfo === "B")
                                 && (index === 0 || quanshengRepeaterPreset().supported)
                        palette.buttonText: confirmedDirection === index ? "#182019" : "#e1e1e1"
                        background: Rectangle {
                            color: parent.confirmedDirection === index ? "#75c98d" : "#343a38"
                            border.color: parent.confirmedDirection === index ? "#b9f6ca" : "#68736c"
                            radius: 2
                        }
                        onClicked: applyQuanshengRepeaterDirection(index)
                        ToolTip.visible: hovered
                        ToolTip.text: "Sentido de desplazamiento TX"
                    }
                }
                ComboBox {
                    id: quanshengRepeaterOffsetCombo
                    model: quanshengRepeaterPreset().offsets
                    textRole: "label"
                    valueRole: "units"
                    currentIndex: window.quanshengRepeaterOffsetIndex(model)
                    onActivated: function(index) {
                        window.quanshengRepeaterOffsetUnits = currentValue
                    }
                    Layout.preferredWidth: 94
                    Layout.minimumWidth: 94
                    Layout.maximumWidth: 94
                    Layout.preferredHeight: 25
                    enabled: quanshengClient.connected
                             && quanshengClient.frequencyControlAvailable
                             && !quanshengClient.controlBusy
                             && (quanshengClient.activeVfo === "A" || quanshengClient.activeVfo === "B")
                             && quanshengRepeaterPreset().supported
                    palette.text: "#eeeeee"
                    palette.buttonText: "#eeeeee"
                    contentItem: Text {
                        leftPadding: 7
                        rightPadding: quanshengRepeaterOffsetCombo.indicator.width + 6
                        text: quanshengRepeaterOffsetCombo.displayText
                        color: "#f0f0f0"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: quanshengRepeaterOffsetMatchesPreset() ? "#294735" : "#424242"
                        border.color: "#668d73"
                        radius: 2
                    }
                    delegate: ItemDelegate {
                        required property int index
                        width: quanshengRepeaterOffsetCombo.width
                        text: quanshengRepeaterOffsetCombo.textAt(index)
                        highlighted: quanshengRepeaterOffsetCombo.highlightedIndex === index
                        contentItem: Text {
                            text: parent.text
                            color: "#f0f0f0"
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 7
                        }
                        background: Rectangle {
                            color: parent.highlighted ? "#496350" : "#303436"
                        }
                    }
                    popup: Popup {
                        y: quanshengRepeaterOffsetCombo.height
                        width: quanshengRepeaterOffsetCombo.width
                        implicitHeight: Math.min(contentItem.implicitHeight, 140)
                        padding: 1
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: quanshengRepeaterOffsetCombo.popup.visible
                                   ? quanshengRepeaterOffsetCombo.delegateModel : null
                            currentIndex: quanshengRepeaterOffsetCombo.highlightedIndex
                            ScrollIndicator.vertical: ScrollIndicator { }
                        }
                        background: Rectangle {
                            color: "#303436"
                            border.color: "#718078"
                            radius: 2
                        }
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: "Saltos permitidos en España para la banda activa"
                }
                QuanshengActionButton {
                    text: "Aplicar"
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 25
                    enabled: quanshengRepeaterOffsetCombo.enabled
                    onClicked: applyQuanshengRepeaterOffset(quanshengRepeaterOffsetCombo.currentValue)
                }
                QuanshengActionButton {
                    text: "Leer"
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 25
                    enabled: quanshengClient.connected && quanshengClient.menuReadAvailable
                             && !quanshengClient.controlBusy
                             && (quanshengClient.activeVfo === "A" || quanshengClient.activeVfo === "B")
                    background: Rectangle {
                        radius: 2
                        color: parent.down ? "#263c40" : parent.hovered ? "#405c61" : "#344c50"
                        border.color: "#587579"
                    }
                    onClicked: readQuanshengRepeater()
                    ToolTip.visible: hovered
                    ToolTip.text: "Leer TxODir y TxOffs del VFO activo"
                }
                Item { Layout.fillWidth: true }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: 10000
                    Layout.preferredHeight: 100
                    Layout.minimumHeight: 100
                    Layout.maximumHeight: 100
                    color: "#000000"
                    border.color: "#000000"
                    border.width: 0
                    radius: 0
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            SelectableLabel { visible: false; text: "VFO A"; color: quanshengClient.activeVfo === "A" ? "#49bfff" : "#9aa7ad"; font.bold: true; font.pixelSize: quanshengClient.activeVfo === "A" ? 12 : 10 }
                            RowLayout {
                                spacing: 2
                                Button {
                                    id: vfoAModeButton
                                    readonly property bool modeSelected: quanshengClient.vfoAMemory !== "Memoria"
                                                                         && !quanshengClient.vfoAMemory.startsWith("M")
                                    text: "VFO"
                                    enabled: modelData !== "BYP" && modelData !== "RAW"
                                             && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                    implicitWidth: 38; implicitHeight: 24; padding: 2; font.pixelSize: 9
                                    palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                    background: Rectangle { color: vfoAModeButton.modeSelected ? "#69c98b" : "#303a3f"; border.color: vfoAModeButton.modeSelected ? "#b9f6ca" : "#65747b"; border.width: vfoAModeButton.modeSelected ? 2 : 1; radius: 3 }
                                    onClicked: if (!modeSelected) quanshengClient.toggleVfoMode("A")
                                }
                                Button {
                                    id: memoryAModeButton
                                    readonly property bool modeSelected: quanshengClient.vfoAMemory === "Memoria"
                                                                         || quanshengClient.vfoAMemory.startsWith("M")
                                    text: "Mem"
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                    implicitWidth: 38; implicitHeight: 24; padding: 2; font.pixelSize: 9
                                    palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                    background: Rectangle { color: memoryAModeButton.modeSelected ? "#69c98b" : "#303a3f"; border.color: memoryAModeButton.modeSelected ? "#b9f6ca" : "#65747b"; border.width: memoryAModeButton.modeSelected ? 2 : 1; radius: 3 }
                                    onClicked: if (!modeSelected) quanshengClient.toggleVfoMode("A")
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.preferredWidth: 146
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "DCS RX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("A", "dcs", "rx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                        SelectableLabel { text: "TX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("A", "dcs", "tx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                    }
                                    RowLayout {
                                        Layout.preferredWidth: 76
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "W/N:"; color: "#b8c2d0"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengWidthForVfo("A"); color: "#b8c2d0"; font.pixelSize: 9; font.bold: true;  }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.preferredWidth: 146
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "CTCSS RX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("A", "ctcss", "rx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                        SelectableLabel { text: "TX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("A", "ctcss", "tx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                    }
                                    RowLayout {
                                        Layout.preferredWidth: 76
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "TX Power:"; color: "#d9b35f"; font.pixelSize: 9 }
                                        SelectableLabel { text: quanshengClient.vfoAPower === "H" ? "HIGH" : quanshengClient.vfoAPower === "M" ? "MID" : quanshengClient.vfoAPower === "L" ? "LOW" : (quanshengClient.vfoAPower || "—"); color: "#d9b35f"; font.pixelSize: 9; font.bold: true;  }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                            SelectableLabel {
                                visible: quanshengClient.vfoAMemory === "Memoria"
                                         || quanshengClient.vfoAMemory.startsWith("M")
                                text: (quanshengClient.vfoAMemory || "—") + " · " + (quanshengClient.vfoAName || "")
                                color: "#f4fbff"
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 125
                                Layout.minimumWidth: 0
                                Layout.maximumWidth: 150
                            }
                            Button {
                                visible: quanshengClient.vfoAMemory === "Memoria"
                                         || quanshengClient.vfoAMemory.startsWith("M")
                                text: "▲"
                                enabled: quanshengClient.activeVfo === "A" && (quanshengClient.vfoAMemory === "Memoria" || quanshengClient.vfoAMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                implicitWidth: 25; implicitHeight: 24; padding: 1; font.pixelSize: 9
                                onClicked: quanshengClient.stepMemory("A", true)
                            }
                            Button {
                                visible: quanshengClient.vfoAMemory === "Memoria"
                                         || quanshengClient.vfoAMemory.startsWith("M")
                                text: "▼"
                                enabled: quanshengClient.activeVfo === "A" && (quanshengClient.vfoAMemory === "Memoria" || quanshengClient.vfoAMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                implicitWidth: 25; implicitHeight: 24; padding: 1; font.pixelSize: 9
                                onClicked: quanshengClient.stepMemory("A", false)
                            }
                            Repeater {
                                model: ["FM", "AM", "USB"]
                                PanelButton {
                                    required property string modelData
                                    selected: quanshengClient.vfoAMode === modelData
                                    text: modelData
                                    Layout.preferredWidth: 36
                                    Layout.minimumWidth: Layout.preferredWidth
                                    Layout.maximumWidth: Layout.preferredWidth
                                    textPixelSize: 10
                                    activeColor: "#2f72b9"
                                    groupAccentColor: "#5f8799"
                                    enabled: modelData !== "BYP" && modelData !== "RAW"
                                             && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                             && quanshengClient.activeVfo !== ""
                                    tip: quanshengClient.activeVfo === ""
                                         ? "Esperando a identificar el VFO activo"
                                         : "Aplicar modo al VFO A"
                                    onClicked: if (!selected) quanshengClient.setMode("A", modelData)
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 60
                            Layout.minimumHeight: 60
                            Layout.maximumHeight: 60
                            color: quanshengClient.activeVfo === "A" ? "#06202b" : "#090909"
                            border.color: quanshengClient.activeVfo === "A" ? "#42bfff" : "#4b4b4b"
                            border.width: 1
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Button {
                                    text: "▲"
                                    implicitWidth: 25; implicitHeight: 23; padding: 0; font.pixelSize: 10
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                             && quanshengClient.activeVfo === "A" && !quanshengClient.controlBusy
                                             && !quanshengPopup.vfoInMemoryMode("A")
                                    onClicked: quanshengPopup.stepFrequencyFromDisplay("A", true)
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Subir 10 Hz"
                                }
                                Button {
                                    text: "▼"
                                    implicitWidth: 25; implicitHeight: 23; padding: 0; font.pixelSize: 10
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                             && quanshengClient.activeVfo === "A" && !quanshengClient.controlBusy
                                             && !quanshengPopup.vfoInMemoryMode("A")
                                    onClicked: quanshengPopup.stepFrequencyFromDisplay("A", false)
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Bajar 10 Hz"
                                }
                            }
                            FrequencyDigits {
                                anchors.left: parent.left
                                anchors.leftMargin: 38
                                anchors.right: parent.right
                                anchors.rightMargin: 68
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                vfoNumber: 0
                                frequencyValue: quanshengPopup.editedFrequencyDisplay("A")
                                large: true
                                active: quanshengClient.activeVfo === "A"
                                wheelEnabled: quanshengClient.connected
                                              && quanshengClient.frequencyControlAvailable
                                              && !quanshengClient.controlBusy
                                wheelFunction: function(x, width, direction) {
                                    quanshengPopup.adjustEditedFrequencyAt("A", x, width, direction)
                                }
                                doubleClickFunction: function(digitsRight) {
                                    quanshengPopup.zeroEditedFrequencyRight("A", digitsRight)
                                }
                            }
                            QuanshengActionButton {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 3
                                text: "Validar"
                                Layout.preferredWidth: 60
                                enabled: quanshengClient.connected
                                         && quanshengClient.activeVfo === "A"
                                         && quanshengClient.frequencyControlAvailable
                                         && !quanshengClient.controlBusy
                                         && !quanshengPopup.activeVfoInMemoryMode()
                                         && quanshengPopup.frequencyAllowed(quanshengPopup.editedFrequencyAMHz)
                                onClicked: quanshengPopup.validateEditedFrequency("A")
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "Seleccione VFO A y cambie a modo VFO para validar la frecuencia."
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 4
                                color: quanshengClient.activeVfo === "A" ? "#42bfff" : "#4b4b4b"
                            }
                            Text {
                                id: candidateTextA
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                                text: "VFO-A"
                                color: quanshengClient.activeVfo === "A" ? "#36c8ff" : "#9f9f9f"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                        RowLayout {
                            visible: false
                            Layout.fillWidth: true
                            spacing: 5
                            transform: Translate { y: -12 }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.preferredWidth: 300
                                Layout.minimumWidth: 260
                                Layout.maximumWidth: 300
                                text: quanshengPopup.candidateDisplayText()
                                color: quanshengPopup.candidateFrequencyMHz > 630
                                       && quanshengPopup.candidateFrequencyMHz < 840
                                       ? "#f2a65a" : "#8fd3ed"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 30
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                property real cursorX: width / 2
                                HoverHandler {
                                    id: candidateHoverA
                                    onPointChanged: candidateTextA.cursorX = point.position.x
                                }
                                ToolTip.visible: candidateHoverA.hovered
                                ToolTip.text: "Rueda sobre este dígito para ajustarlo; pulse Validar / enviar para transmitir la frecuencia."
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: false
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    onPositionChanged: candidateTextA.cursorX = mouse.x
                                    onWheel: function(wheel) {
                                        const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y
                                        if (delta !== 0) {
                                            quanshengPopup.adjustCandidateAt(mouse.x, candidateTextA.width, delta > 0 ? 1 : -1)
                                            wheel.accepted = true
                                        }
                                    }
                                }
                                WheelHandler {
                                    enabled: true
                                    onWheel: {
                                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                                        if (delta !== 0) {
                                            quanshengPopup.adjustCandidateAt(point.position.x, parent.width, delta > 0 ? 1 : -1, parent.implicitWidth)
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                            SelectableLabel { text: "Paso " + (quanshengClient.vfoAStep || "—"); color: "#9da8ad"; font.pixelSize: 11; font.bold: true }
                            QuanshengActionButton {
                                text: "Validar\nenviar"
                                Layout.preferredWidth: 82
                                Layout.minimumWidth: 82
                                Layout.maximumWidth: 82
                                enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy && !quanshengPopup.activeVfoInMemoryMode() && quanshengPopup.frequencyAllowed(quanshengPopup.activeFrequencyMHz()) && quanshengPopup.frequencyAllowed(quanshengPopup.candidateFrequencyMHz) && Math.abs(quanshengPopup.candidateFrequencyMHz - quanshengPopup.activeFrequencyMHz()) > 0.0000005
                                onClicked: quanshengClient.setFrequency(quanshengPopup.candidateFrequencyMHz.toFixed(6))
                            }
                        }
                        SelectableLabel { visible: false; text: "Canal / nombre"; color: "#83949d"; font.pixelSize: 9 }
                        RowLayout {
                            visible: false
                            opacity: 1
                            enabled: true
                            Layout.fillWidth: true
                            spacing: 3
                            SelectableLabel { text: (quanshengClient.vfoAMemory || "—") + " · " + (quanshengClient.vfoAName || "sin nombre"); opacity: quanshengClient.vfoAMemory === "Memoria" || quanshengClient.vfoAMemory.startsWith("M") ? 1 : 0.55; color: "#ffffff"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Button { text: "▲"; enabled: (quanshengClient.vfoAMemory === "Memoria" || quanshengClient.vfoAMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy; implicitWidth: 28; implicitHeight: 24; padding: 2; font.pixelSize: 9; onClicked: quanshengClient.stepMemory("A", true) }
                            Button { text: "▼"; enabled: (quanshengClient.vfoAMemory === "Memoria" || quanshengClient.vfoAMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy; implicitWidth: 28; implicitHeight: 24; padding: 2; font.pixelSize: 9; onClicked: quanshengClient.stepMemory("A", false) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20
                            visible: false
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                SelectableLabel { text: "Modo"; color: "#83949d"; font.pixelSize: 9 }
                                RowLayout {
                                    spacing: 2
                                    Repeater {
                                        model: ["FM", "AM", "USB", "BYP", "RAW"]
                                        Button {
                                            id: modeAButton
                                            required property string modelData
                                            readonly property bool modeSelected: quanshengClient.vfoAMode === modelData
                                            text: modelData
                                            enabled: modelData !== "BYP" && modelData !== "RAW"
                                                     && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                            implicitWidth: modelData.length > 2 ? 34 : 29
                                            implicitHeight: 23
                                            padding: 2
                                            font.pixelSize: 9
                                            palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                            background: Rectangle {
                                                color: modeAButton.modeSelected ? "#69c98b" : "#303a3f"
                                                border.color: modeAButton.modeSelected ? "#b9f6ca" : "#65747b"
                                                border.width: modeAButton.modeSelected ? 2 : 1
                                                radius: 3
                                            }
                                            onClicked: if (!modeSelected) quanshengClient.setMode("A", modelData)
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                SelectableLabel { text: "Potencia TX"; color: "#83949d"; font.pixelSize: 9 }
                                SelectableLabel { text: quanshengClient.vfoAPower === "H" ? "High" : quanshengClient.vfoAPower === "M" ? "Med" : quanshengClient.vfoAPower === "L" ? "Low" : (quanshengClient.vfoAPower || "pendiente"); color: "#aeb9be"; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: 10000
                    Layout.preferredHeight: 100
                    Layout.minimumHeight: 100
                    Layout.maximumHeight: 100
                    color: "#000000"
                    border.color: "#000000"
                    border.width: 0
                    radius: 0
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 0
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            SelectableLabel { visible: false; text: "VFO B"; color: quanshengClient.activeVfo === "B" ? "#ffb347" : "#9aa7ad"; font.bold: true; font.pixelSize: quanshengClient.activeVfo === "B" ? 12 : 10 }
                            RowLayout {
                                spacing: 2
                                Button {
                                    id: vfoBModeButton
                                    readonly property bool modeSelected: quanshengClient.vfoBMemory !== "Memoria"
                                                                         && !quanshengClient.vfoBMemory.startsWith("M")
                                    text: "VFO"
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                    implicitWidth: 38; implicitHeight: 24; padding: 2; font.pixelSize: 9
                                    palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                    background: Rectangle { color: vfoBModeButton.modeSelected ? "#69c98b" : "#303a3f"; border.color: vfoBModeButton.modeSelected ? "#b9f6ca" : "#65747b"; border.width: vfoBModeButton.modeSelected ? 2 : 1; radius: 3 }
                                    onClicked: if (!modeSelected) quanshengClient.toggleVfoMode("B")
                                }
                                Button {
                                    id: memoryBModeButton
                                    readonly property bool modeSelected: quanshengClient.vfoBMemory === "Memoria"
                                                                         || quanshengClient.vfoBMemory.startsWith("M")
                                    text: "Mem"
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                    implicitWidth: 38; implicitHeight: 24; padding: 2; font.pixelSize: 9
                                    palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                    background: Rectangle { color: memoryBModeButton.modeSelected ? "#69c98b" : "#303a3f"; border.color: memoryBModeButton.modeSelected ? "#b9f6ca" : "#65747b"; border.width: memoryBModeButton.modeSelected ? 2 : 1; radius: 3 }
                                    onClicked: if (!modeSelected) quanshengClient.toggleVfoMode("B")
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.preferredWidth: 146
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "DCS RX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("B", "dcs", "rx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                        SelectableLabel { text: "TX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("B", "dcs", "tx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                    }
                                    RowLayout {
                                        Layout.preferredWidth: 76
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "W/N:"; color: "#b8c2d0"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengWidthForVfo("B"); color: "#b8c2d0"; font.pixelSize: 9; font.bold: true;  }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        Layout.preferredWidth: 146
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "CTCSS RX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("B", "ctcss", "rx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                        SelectableLabel { text: "TX:"; color: "#9fbcc6"; font.pixelSize: 9 }
                                        SelectableLabel { text: window.quanshengToneValue("B", "ctcss", "tx"); color: "#9fbcc6"; font.pixelSize: 9; font.bold: true; elide: Text.ElideRight;  }
                                    }
                                    RowLayout {
                                        Layout.preferredWidth: 76
                                        Layout.minimumWidth: 0
                                        spacing: 3
                                        SelectableLabel { text: "TX Power:"; color: "#d9b35f"; font.pixelSize: 9 }
                                        SelectableLabel { text: quanshengClient.vfoBPower === "H" ? "HIGH" : quanshengClient.vfoBPower === "M" ? "MID" : quanshengClient.vfoBPower === "L" ? "LOW" : (quanshengClient.vfoBPower || "—"); color: "#d9b35f"; font.pixelSize: 9; font.bold: true;  }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                            SelectableLabel {
                                visible: quanshengClient.vfoBMemory === "Memoria"
                                         || quanshengClient.vfoBMemory.startsWith("M")
                                text: (quanshengClient.vfoBMemory || "—") + " · " + (quanshengClient.vfoBName || "")
                                color: "#f4fbff"
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 125
                                Layout.minimumWidth: 0
                                Layout.maximumWidth: 150
                            }
                            Button {
                                visible: quanshengClient.vfoBMemory === "Memoria"
                                         || quanshengClient.vfoBMemory.startsWith("M")
                                text: "▲"
                                enabled: quanshengClient.activeVfo === "B" && (quanshengClient.vfoBMemory === "Memoria" || quanshengClient.vfoBMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                implicitWidth: 25; implicitHeight: 24; padding: 1; font.pixelSize: 9
                                onClicked: quanshengClient.stepMemory("B", true)
                            }
                            Button {
                                visible: quanshengClient.vfoBMemory === "Memoria"
                                         || quanshengClient.vfoBMemory.startsWith("M")
                                text: "▼"
                                enabled: quanshengClient.activeVfo === "B" && (quanshengClient.vfoBMemory === "Memoria" || quanshengClient.vfoBMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                implicitWidth: 25; implicitHeight: 24; padding: 1; font.pixelSize: 9
                                onClicked: quanshengClient.stepMemory("B", false)
                            }
                            Repeater {
                                model: ["FM", "AM", "USB"]
                                PanelButton {
                                    required property string modelData
                                    selected: quanshengClient.vfoBMode === modelData
                                    text: modelData
                                    Layout.preferredWidth: 36
                                    Layout.minimumWidth: Layout.preferredWidth
                                    Layout.maximumWidth: Layout.preferredWidth
                                    textPixelSize: 10
                                    activeColor: "#2f72b9"
                                    groupAccentColor: "#5f8799"
                                    enabled: modelData !== "BYP" && modelData !== "RAW"
                                             && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                             && quanshengClient.activeVfo !== ""
                                    tip: quanshengClient.activeVfo === ""
                                         ? "Esperando a identificar el VFO activo"
                                         : "Aplicar modo al VFO B"
                                    onClicked: if (!selected) quanshengClient.setMode("B", modelData)
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 60
                            Layout.minimumHeight: 60
                            Layout.maximumHeight: 60
                            color: quanshengClient.activeVfo === "B" ? "#211708" : "#090909"
                            border.color: quanshengClient.activeVfo === "B" ? "#ffad4d" : "#4b4b4b"
                            border.width: 1
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Button {
                                    text: "▲"
                                    implicitWidth: 25; implicitHeight: 23; padding: 0; font.pixelSize: 10
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                             && quanshengClient.activeVfo === "B" && !quanshengClient.controlBusy
                                             && !quanshengPopup.vfoInMemoryMode("B")
                                    onClicked: quanshengPopup.stepFrequencyFromDisplay("B", true)
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Subir 10 Hz"
                                }
                                Button {
                                    text: "▼"
                                    implicitWidth: 25; implicitHeight: 23; padding: 0; font.pixelSize: 10
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                             && quanshengClient.activeVfo === "B" && !quanshengClient.controlBusy
                                             && !quanshengPopup.vfoInMemoryMode("B")
                                    onClicked: quanshengPopup.stepFrequencyFromDisplay("B", false)
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Bajar 10 Hz"
                                }
                            }
                            FrequencyDigits {
                                anchors.left: parent.left
                                anchors.leftMargin: 38
                                anchors.right: parent.right
                                anchors.rightMargin: 68
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                vfoNumber: 1
                                frequencyValue: quanshengPopup.editedFrequencyDisplay("B")
                                large: true
                                active: quanshengClient.activeVfo === "B"
                                wheelEnabled: quanshengClient.connected
                                              && quanshengClient.frequencyControlAvailable
                                              && !quanshengClient.controlBusy
                                wheelFunction: function(x, width, direction) {
                                    quanshengPopup.adjustEditedFrequencyAt("B", x, width, direction)
                                }
                                doubleClickFunction: function(digitsRight) {
                                    quanshengPopup.zeroEditedFrequencyRight("B", digitsRight)
                                }
                            }
                            QuanshengActionButton {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 3
                                text: "Validar"
                                Layout.preferredWidth: 60
                                enabled: quanshengClient.connected
                                         && quanshengClient.activeVfo === "B"
                                         && quanshengClient.frequencyControlAvailable
                                         && !quanshengClient.controlBusy
                                         && !quanshengPopup.activeVfoInMemoryMode()
                                         && quanshengPopup.frequencyAllowed(quanshengPopup.editedFrequencyBMHz)
                                onClicked: quanshengPopup.validateEditedFrequency("B")
                                ToolTip.visible: hovered && !enabled
                                ToolTip.text: "Seleccione VFO B y cambie a modo VFO para validar la frecuencia."
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 4
                                color: quanshengClient.activeVfo === "B" ? "#ffad4d" : "#4b4b4b"
                            }
                            Text {
                                id: candidateTextB
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 5
                                text: "VFO-B"
                                color: quanshengClient.activeVfo === "B" ? "#ffb347" : "#9f9f9f"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                        RowLayout {
                            visible: false
                            Layout.fillWidth: true
                            spacing: 5
                            transform: Translate { y: -12 }
                            Item { Layout.fillWidth: true }
                            Text {
                                Layout.preferredWidth: 260
                                Layout.minimumWidth: 230
                                Layout.maximumWidth: 260
                                text: quanshengPopup.candidateDisplayText()
                                color: quanshengPopup.candidateFrequencyMHz > 630
                                       && quanshengPopup.candidateFrequencyMHz < 840
                                       ? "#f2a65a" : "#8fd3ed"
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 30
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                property real cursorX: width / 2
                                HoverHandler {
                                    id: candidateHoverB
                                    onPointChanged: candidateTextB.cursorX = point.position.x
                                }
                                ToolTip.visible: candidateHoverB.hovered
                                ToolTip.text: "Rueda sobre este dígito para ajustarlo; pulse Validar / enviar para transmitir la frecuencia."
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: false
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    onPositionChanged: candidateTextB.cursorX = mouse.x
                                    onWheel: function(wheel) {
                                        const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y
                                        if (delta !== 0) {
                                            quanshengPopup.adjustCandidateAt(mouse.x, candidateTextB.width, delta > 0 ? 1 : -1)
                                            wheel.accepted = true
                                        }
                                    }
                                }
                                WheelHandler {
                                    enabled: true
                                    onWheel: {
                                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                                        if (delta !== 0) {
                                            quanshengPopup.adjustCandidateAt(point.position.x, parent.width, delta > 0 ? 1 : -1, parent.implicitWidth)
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                            SelectableLabel { text: "Paso " + (quanshengClient.vfoBStep || "—"); color: "#9da8ad"; font.pixelSize: 11; font.bold: true }
                            QuanshengActionButton {
                                text: "Validar\nenviar"
                                Layout.preferredWidth: 82
                                Layout.minimumWidth: 82
                                Layout.maximumWidth: 82
                                enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy && !quanshengPopup.activeVfoInMemoryMode() && quanshengPopup.frequencyAllowed(quanshengPopup.activeFrequencyMHz()) && quanshengPopup.frequencyAllowed(quanshengPopup.candidateFrequencyMHz) && Math.abs(quanshengPopup.candidateFrequencyMHz - quanshengPopup.activeFrequencyMHz()) > 0.0000005
                                onClicked: quanshengClient.setFrequency(quanshengPopup.candidateFrequencyMHz.toFixed(6))
                            }
                        }
                        SelectableLabel { visible: false; text: "Canal / función"; color: "#83949d"; font.pixelSize: 9 }
                        RowLayout {
                            visible: false
                            opacity: 1
                            enabled: true
                            Layout.fillWidth: true
                            spacing: 3
                            SelectableLabel { text: (quanshengClient.vfoBMemory || "—") + " · " + (quanshengClient.vfoBName || "sin nombre"); opacity: quanshengClient.vfoBMemory === "Memoria" || quanshengClient.vfoBMemory.startsWith("M") ? 1 : 0.55; color: "#ffffff"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Button { text: "▲"; enabled: (quanshengClient.vfoBMemory === "Memoria" || quanshengClient.vfoBMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy; implicitWidth: 28; implicitHeight: 24; padding: 2; font.pixelSize: 9; onClicked: quanshengClient.stepMemory("B", true) }
                            Button { text: "▼"; enabled: (quanshengClient.vfoBMemory === "Memoria" || quanshengClient.vfoBMemory.startsWith("M")) && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy; implicitWidth: 28; implicitHeight: 24; padding: 2; font.pixelSize: 9; onClicked: quanshengClient.stepMemory("B", false) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20
                            visible: false
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                SelectableLabel { text: "Modo"; color: "#83949d"; font.pixelSize: 9 }
                                RowLayout {
                                    spacing: 2
                                    Repeater {
                                        model: ["FM", "AM", "USB", "BYP", "RAW"]
                                        Button {
                                            id: modeBButton
                                            required property string modelData
                                            readonly property bool modeSelected: quanshengClient.vfoBMode === modelData
                                            text: modelData
                                            enabled: modelData !== "BYP" && modelData !== "RAW"
                                                     && quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                            implicitWidth: modelData.length > 2 ? 34 : 29
                                            implicitHeight: 23
                                            padding: 2
                                            font.pixelSize: 9
                                            palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                            background: Rectangle {
                                                color: modeBButton.modeSelected ? "#69c98b" : "#303a3f"
                                                border.color: modeBButton.modeSelected ? "#b9f6ca" : "#65747b"
                                                border.width: modeBButton.modeSelected ? 2 : 1
                                                radius: 3
                                            }
                                            onClicked: if (!modeSelected) quanshengClient.setMode("B", modelData)
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                SelectableLabel { text: "Potencia TX"; color: "#83949d"; font.pixelSize: 9 }
                                SelectableLabel { text: quanshengClient.vfoBPower === "H" ? "High" : quanshengClient.vfoBPower === "M" ? "Med" : quanshengClient.vfoBPower === "L" ? "Low" : (quanshengClient.vfoBPower || "pendiente"); color: "#aeb9be"; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 150
                Layout.preferredHeight: 150
                Layout.maximumHeight: 150
                spacing: 8
                FrameBox {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: 150
                    Layout.preferredHeight: 150
                    Layout.maximumHeight: 150
                    Layout.fillHeight: false
                    color: "#000000"
                    border.color: "transparent"
                    border.width: 0
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 1
                        Text { text: "1    3    5    7    9    +20    +40    +60 dB"; color: "#9fa7ad"; font.pixelSize: 8; font.family: "DejaVu Sans Mono"; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                        MeterLine {
                            Layout.fillWidth: true
                            caption: "S"
                            valueText: quanshengClient.signalLevel >= 0 ? "S" + quanshengClient.signalLevel : "—"
                            percent: window.quanshengSignalPercent()
                            multicolor: true
                            compact: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "SQL"; color: "#f0f0f0"; font.pixelSize: 11; font.bold: true; Layout.preferredWidth: 34 }
                            Repeater {
                                model: 10
                                Button {
                                    required property int index
                                    readonly property bool modeSelected: quanshengClient.squelchLevel === index
                                    text: String(index)
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                    implicitWidth: 23; implicitHeight: 20; padding: 1; font.pixelSize: 9
                                    palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                                    background: Rectangle { color: modeSelected ? "#69c98b" : "#303a3f"; border.color: modeSelected ? "#b9f6ca" : "#65747b"; border.width: modeSelected ? 2 : 1; radius: 3 }
                                    onClicked: if (!modeSelected) quanshengClient.setSquelch(index)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "VOX"; color: "#f0f0f0"; font.pixelSize: 11; font.bold: true; Layout.preferredWidth: 34 }
                            Repeater {
                                model: 10
                                Button {
                                    required property int index
                                    readonly property bool modeSelected: quanshengClient.voxKnown
                                                                         && quanshengClient.voxLevel === index
                                    text: String(index)
                                    enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable && !quanshengClient.controlBusy
                                    implicitWidth: 23; implicitHeight: 20; padding: 1; font.pixelSize: 9
                                    palette.buttonText: modeSelected ? "#201508" : "#e4ddd0"
                                    background: Rectangle { color: modeSelected ? "#d99a3a" : "#3d3630"; border.color: modeSelected ? "#ffd08a" : "#7c7165"; border.width: modeSelected ? 2 : 1; radius: 3 }
                                    onClicked: if (!modeSelected) quanshengClient.setVoxLevel(index)
                                }
                            }
                        }
                        MeterLine {
                            Layout.fillWidth: true
                            caption: "BAT"
                            valueText: quanshengClient.batteryPercent >= 0
                                       ? quanshengClient.batteryPercent + "% · " + Number(quanshengClient.batteryVolts).toFixed(2) + " V"
                                       : "—"
                            percent: Math.max(0, quanshengClient.batteryPercent)
                            barColor: window.quanshengBatteryColor()
                            compact: true
                        }
                    }
                }
                AnalogSMeter {
                    Layout.preferredWidth: 145
                    Layout.minimumWidth: 135
                    Layout.maximumWidth: 150
                    Layout.minimumHeight: 132
                    Layout.preferredHeight: 132
                    Layout.maximumHeight: 132
                    Layout.alignment: Qt.AlignVCenter
                    meterPercent: window.quanshengSignalPercent()
                    valueText: quanshengClient.signalLevel >= 0 ? "S" + quanshengClient.signalLevel : "S0"
                }
            }

            RowLayout {
                visible: false
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                            color: "transparent"
                            border.color: "transparent"
                            border.width: 0
                            radius: 0
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 14
                        ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2
                        SelectableLabel { visible: false; text: "FRECUENCIA CANDIDATA · VFO " + (quanshengClient.activeVfo || "—"); color: "#83949d"; font.pixelSize: 9 }
                        Row {
                            spacing: 0
                            enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                     && !quanshengClient.controlBusy
                            Repeater {
                                model: quanshengPopup.candidateDisplayText().length
                                delegate: Item {
                                    required property int index
                                    readonly property string digitText: quanshengPopup.candidateDisplayText().charAt(index)
                                    readonly property bool lowDigits: index >= quanshengPopup.candidateDisplayText().length - 3
                                    width: digitText === "." ? 8 : 15
                                    height: 31
                                    Text {
                                        anchors.fill: parent
                                        text: digitText
                                        color: digitText === "." ? "#ffffff" : (lowDigits ? "#9fb4be" : "#8fd3ed")
                                        font.pixelSize: lowDigits ? 19 : 28
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    WheelHandler {
                                        enabled: digitText !== "."
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                        onWheel: function(event) {
                                            var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
                                            if (delta === 0) return
                                            var digitIndex = 0
                                            for (var i = 0; i < index; ++i)
                                                if (quanshengPopup.candidateDisplayText().charAt(i) !== ".") ++digitIndex
                                            var increment = Math.pow(10, 2 - digitIndex)
                                            quanshengPopup.candidateFrequencyTouched = true
                                            quanshengPopup.candidateFrequencyMHz = Math.max(18, Math.min(1300,
                                            quanshengPopup.snapCandidate(quanshengPopup.candidateFrequencyMHz
                                                                          + (delta > 0 ? increment : -increment))))
                                            event.accepted = true
                                        }
                                    }
                                }
                            }
                        }
                        SelectableLabel { visible: false; text: "Rueda sobre cada cifra · paso " + (quanshengClient.stepText || "1 kHz"); color: "#9da8ad"; font.pixelSize: 10 }
                        SelectableLabel {
                            visible: false
                            Layout.fillWidth: true
                            text: quanshengClient.frequencyControlStatus
                            color: quanshengClient.frequencyControlStatus.indexOf("error:") >= 0
                                   || quanshengClient.frequencyControlStatus.startsWith("Error")
                                   ? "#e06c75" : "#d2b36f"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                        SelectableLabel {
                            text: "Paso " + (quanshengClient.stepText || "1 kHz")
                            color: "#9da8ad"
                            font.pixelSize: 10
                            Layout.alignment: Qt.AlignVCenter
                        }
                        QuanshengActionButton {
                        Layout.preferredWidth: 80
                        Layout.minimumWidth: 80
                        Layout.maximumWidth: 80
                        Layout.alignment: Qt.AlignVCenter
                        text: "Enviar\nfrecuencia"
                        enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                 && !quanshengClient.controlBusy
                                 && !quanshengPopup.activeVfoInMemoryMode()
                                 && quanshengPopup.frequencyAllowed(quanshengPopup.activeFrequencyMHz())
                                 && quanshengPopup.frequencyAllowed(quanshengPopup.candidateFrequencyMHz)
                                 && Math.abs(quanshengPopup.candidateFrequencyMHz
                                             - quanshengPopup.activeFrequencyMHz()) > 0.0000005
                        onClicked: quanshengClient.setFrequency(quanshengPopup.candidateFrequencyMHz.toFixed(6))
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: quanshengPopup.activeVfoInMemoryMode()
                                      ? "No disponible mientras el VFO activo está en memoria"
                                      : "Requiere --allow-frequency-control o una frecuencia diferente"
                        }
                    }
                }

                FrameBox {
                    Layout.preferredWidth: 250
                    Layout.minimumWidth: 250
                    Layout.maximumWidth: 250
                    Layout.fillHeight: true
                    color: "#111719"
                    border.color: "#53616a"

                    AnalogSMeter {
                        anchors.fill: parent
                        anchors.margins: 5
                        meterPercent: window.quanshengSignalPercent()
                        valueText: quanshengClient.candidateState === "RX"
                                   && quanshengClient.signalLevel >= 0
                                   ? "S" + quanshengClient.signalLevel
                                     + (quanshengClient.signalOver > 0
                                        ? "+" + (quanshengClient.signalOver * 10) : "")
                                   : "S0"
                    }
                }
            }

            QuanshengSectionHeader {
                text: "ESTADO Y RECEPCIÓN"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SelectableLabel { text: "Estado"; color: "#aeb9be" }
                SelectableLabel {
                    text: quanshengClient.candidateState || "—"
                    color: "#ffffff"
                    elide: Text.ElideRight
                }
                SelectableLabel { text: "Eventos"; color: "#aeb9be" }
                SelectableLabel { text: String(quanshengClient.eventCount); color: "#ffffff" }
                SelectableLabel {
                    visible: quanshengClient.charging
                    text: "⚡"
                    color: "#ffd866"
                    font.pixelSize: 15
                    font.bold: true
                    ToolTip.visible: chargingMouse.containsMouse
                    ToolTip.text: "Batería cargando"
                    MouseArea { id: chargingMouse; anchors.fill: parent; hoverEnabled: true }
                }
                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SelectableLabel { text: "RSSI"; color: "#aeb9be" }
                SelectableLabel {
                    text: quanshengClient.rssiRaw >= 0
                          ? quanshengClient.rssiDbmUncorrected + " dBm (raw " + quanshengClient.rssiRaw + ")"
                          : "—"
                    color: "#ffffff"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SelectableLabel { text: "Puerto serie"; color: "#aeb9be" }
                SelectableLabel {
                    text: "Cortes: " + quanshengClient.serialDisconnectCount
                          + "    Recuperaciones: " + quanshengClient.serialRecoveryCount
                          + "    " + quanshengClient.serialDiagnostic
                    color: "#d7e0e4"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    ToolTip.visible: serialDiagnosticMouse.containsMouse
                    ToolTip.text: text
                    MouseArea { id: serialDiagnosticMouse; anchors.fill: parent; hoverEnabled: true }
                }
            }

            RowLayout {
                visible: false
                spacing: 2
                Repeater {
                    model: [{"label": "OFF", "value": false}, {"label": "ON", "value": true}]
                    Button {
                        id: dualWatchButton
                        required property var modelData
                        readonly property bool modeSelected: quanshengClient.dualWatchKnown
                                                                     && quanshengClient.dualWatch === modelData.value
                        text: modelData.label
                        enabled: quanshengClient.connected && quanshengClient.frequencyControlAvailable
                                 && !quanshengClient.controlBusy
                        implicitWidth: 38; implicitHeight: 23; padding: 2; font.pixelSize: 9
                        palette.buttonText: modeSelected ? "#102018" : "#d6e2e7"
                        background: Rectangle { color: dualWatchButton.modeSelected ? "#69c98b" : "#303a3f"; border.color: dualWatchButton.modeSelected ? "#b9f6ca" : "#65747b"; border.width: dualWatchButton.modeSelected ? 2 : 1; radius: 3 }
                        onClicked: if (!modeSelected) quanshengClient.setDualWatch(modelData.value)
                    }
                }
            }

            QuanshengSectionHeader {
                visible: false
                text: "CONFIGURACIÓN OBSERVADA"
            }

            GridLayout {
                visible: false
                columns: 4
                Layout.fillWidth: true
                columnSpacing: 8
                rowSpacing: 3
                SelectableLabel { text: "Funciones"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareFunctionsText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                SelectableLabel { text: "Escáner"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareScanText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                SelectableLabel { text: "Filtro RX"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareFilterText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                SelectableLabel { text: "Squelch"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareSquelchText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                SelectableLabel { text: "CTCSS/CDCSS"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareCssText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                SelectableLabel { text: "DTMF/SelCall"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareDtmfText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                SelectableLabel { text: "Generadores tono"; color: "#aeb9be" }
                SelectableLabel { text: quanshengClient.hardwareTonesText || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
            }

            QuanshengSectionHeader {
                text: "CONTROL DEL SERVIDOR Y LECTURAS"
            }

            ColumnLayout {
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    QuanshengActionButton {
                        text: registerPopup.visible ? "Cerrar reg." : "Registros"
                        onClicked: registerPopup.visible ? registerPopup.close() : registerPopup.open()
                    }
                    QuanshengActionButton {
                        text: "EEPROM"
                        enabled: quanshengClient.connected && quanshengClient.eepromReadAvailable
                        onClicked: eepromPopup.open()
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: "Arranca qdock-server con --allow-eeprom-query"
                    }
                    QuanshengActionButton {
                        text: "Contadores"
                        onClicked: quanshengClient.resetCounters()
                    }
                    QuanshengActionButton {
                        text: "Menús radio"
                        enabled: !quanshengClient.controlBusy
                        onClicked: quanshengMenuPopup.open()
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: "Requiere control de frecuencia habilitado y radio libre"
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    QuanshengActionButton {
                        text: "Arrancar servidor"
                        enabled: !quanshengClient.connected
                        onClicked: quanshengClient.startServerGuiBySsh()
                        ToolTip.visible: hovered
                        ToolTip.text: quanshengClient.serverLocation === "local"
                                      ? "Abrir la ventana del servidor en este PC"
                                      : "Arrancar el servidor con su ventana remota por SSH"
                    }
                    QuanshengActionButton {
                        text: "Parar servidor"
                        onClicked: quanshengClient.stopServerGuiBySsh()
                        ToolTip.visible: hovered
                        ToolTip.text: quanshengClient.serverLocation === "local"
                                      ? "Detener el servidor y cerrar su ventana local"
                                      : "Cerrar el servidor y su ventana remota por SSH"
                    }
                    QuanshengActionButton {
                        text: quanshengClient.connected ? "Desconectar" : "Conectar"
                        onClicked: quanshengClient.connected
                                  ? quanshengClient.disconnectFromServer()
                                  : quanshengClient.connectToServer()
                    }
                    QuanshengActionButton {
                        text: "Reiniciar"
                        enabled: quanshengClient.connected
                        onClicked: quanshengClient.restartServer()
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: "Conecta primero con el servidor Quansheng"
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            QuanshengSectionHeader {
                visible: false
                text: "VALORES DE USUARIO EEPROM · SOLO LECTURA"
            }

            GridLayout {
                visible: false
                columns: 4
                Layout.fillWidth: true
                columnSpacing: 8
                rowSpacing: 3
                SelectableLabel { text: "Canal llamada 0x0E70"; color: "#aeb9be" }
                SelectableLabel { text: quanshengUserSettingValue("0x0E70"); color: "#ffffff" }
                SelectableLabel { text: "Squelch 0x0E71"; color: "#aeb9be" }
                SelectableLabel { text: quanshengUserSettingValue("0x0E71"); color: "#ffffff" }
                SelectableLabel { text: "Visualización 0x0E79"; color: "#aeb9be" }
                SelectableLabel { text: quanshengUserSettingValue("0x0E79"); color: "#ffffff" }
                SelectableLabel { text: "Cross-band 0x0E7A"; color: "#aeb9be" }
                SelectableLabel { text: quanshengUserSettingValue("0x0E7A"); color: "#ffffff" }
            }

            RowLayout {
                visible: false
                Layout.fillWidth: true
                SelectableLabel {
                    text: quanshengClient.eepromSettingRows.length
                          ? quanshengUserSettingRows().length + " opciones de usuario leídas"
                          : "Lee primero la EEPROM para cargar los valores"
                    color: "#9da8ad"
                    Layout.fillWidth: true
                }
                QuanshengActionButton {
                    text: "Todas las opciones…"
                    enabled: quanshengClient.eepromSettingRows.length > 0
                    onClicked: quanshengUserSettingsPopup.open()
                }
            }

            }

            }

        }
    }

    Popup {
        id: quanshengMenuPopup
        width: Math.min(740, window.width - 32)
        height: Math.min(660, window.height - 32)
        x: Math.max(8, (window.width - width) / 2)
        y: Math.max(8, (window.height - height) / 2)
        modal: false
        focus: true
        padding: 12
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: "#050505"; border.color: "#444444"; radius: 4 }
        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                SelectableLabel {
                    id: quanshengMenuDragTitle
                    text: "MENÚS OPERATIVOS QUANSHENG"
                    color: "#f2f2f2"
                    font.bold: true
                    Layout.fillWidth: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        property real pressWindowX: 0
                        property real pressWindowY: 0
                        property real popupStartX: 0
                        property real popupStartY: 0
                        onPressed: function(mouse) {
                            var point = quanshengMenuDragTitle.mapToItem(quanshengMenuPopup.parent, mouse.x, mouse.y)
                            pressWindowX = point.x
                            pressWindowY = point.y
                            popupStartX = quanshengMenuPopup.x
                            popupStartY = quanshengMenuPopup.y
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var point = quanshengMenuDragTitle.mapToItem(quanshengMenuPopup.parent, mouse.x, mouse.y)
                            quanshengMenuPopup.x = Math.max(0, Math.min(window.width - quanshengMenuPopup.width,
                                                                         popupStartX + point.x - pressWindowX))
                            quanshengMenuPopup.y = Math.max(0, Math.min(window.height - quanshengMenuPopup.height,
                                                                         popupStartY + point.y - pressWindowY))
                        }
                    }
                }
                SelectableLabel {
                    text: quanshengClient.menuReadStatus
                    color: "#aeb9b2"
                    elide: Text.ElideRight
                    Layout.maximumWidth: 270
                }
                Button {
                    text: "Leer valores (" + qMenuReadSelectionCount() + ")"
                    enabled: quanshengClient.connected && quanshengClient.menuReadAvailable
                             && !quanshengClient.controlBusy
                    ToolTip.visible: hovered && !enabled
                    ToolTip.text: !quanshengClient.connected ? "Conecta con el servidor Quansheng"
                                    : !quanshengClient.menuReadAvailable
                                      ? "Actualiza el servidor del Pavilion para habilitar la lectura"
                                      : "La radio mostrará cada valor sin modificarlo"
                    palette.buttonText: "#eeeeee"
                    background: Rectangle { color: parent.enabled ? "#303b34" : "#303030"; border.color: "#596b60"; radius: 2 }
                    onClicked: readQuanshengMenuValues()
                }
                Button {
                    text: "Leer todas"
                    enabled: quanshengClient.connected && quanshengClient.menuReadAvailable
                             && !quanshengClient.controlBusy
                    ToolTip.visible: hovered
                    ToolTip.text: "Leer los menús 1–61. Si alguno no responde, la tanda puede tardar varios minutos."
                    palette.buttonText: "#eeeeee"
                    background: Rectangle { color: parent.enabled ? "#343c49" : "#303030"; border.color: "#5b687b"; radius: 2 }
                    onClicked: readAllQuanshengMenuValues()
                }
                Button {
                    text: "Cerrar"
                    palette.buttonText: "#eeeeee"
                    background: Rectangle { color: "#303030"; border.color: "#555555"; radius: 2 }
                    onClicked: quanshengMenuPopup.close()
                }
            }
            SelectableLabel {
                Layout.fillWidth: true
                text: "Catalogo 1-61 del firmware Dock. Los ajustes de texto y memoria no se pueden editar desde esta ventana."
                color: "#c5c5c5"
                wrapMode: Text.WordWrap
            }
            ListView {
                id: quanshengMenuList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                pixelAligned: false
                cacheBuffer: 440
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                maximumFlickVelocity: 2500
                flickDeceleration: 3000
                spacing: 0
                model: quanshengMenuDefinitions
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                delegate: Item {
                    required property var modelData
                    width: quanshengMenuList.width - 14
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        z: 0
                        color: qMenuReadState(modelData) === "unconfirmed" ? "#302923"
                              : qMenuReadState(modelData) === "pending" ? "#383222" : "#101010"
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: "#333333"
                        }
                    }
                    RowLayout {
                        z: 1
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        anchors.topMargin: 2
                        anchors.bottomMargin: 2
                        spacing: 7
                        CheckBox {
                            checked: (modelData.settable || modelData.readable) && qMenuReadIsIncluded(modelData)
                            enabled: modelData.settable || modelData.readable
                            Layout.preferredWidth: 22
                            Layout.minimumWidth: 22
                            Layout.maximumWidth: 22
                            Layout.alignment: Qt.AlignVCenter
                            padding: 0
                            indicator: Rectangle {
                                implicitWidth: 18
                                implicitHeight: 18
                                x: 1
                                y: (parent.height - height) / 2
                                radius: 3
                                color: parent.checked ? "#287a55" : "#111719"
                                border.width: 1
                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.bold: true
                                    visible: parent.parent.checked
                                }
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.settable || modelData.readable
                                          ? (checked ? "Incluir en lectura global" : "Excluir de lectura global")
                                          : "Este menú no se puede leer desde aquí"
                            onToggled: setQMenuReadIncluded(modelData, checked)
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.preferredWidth: 180
                            Layout.minimumWidth: 180
                            Layout.fillHeight: true
                            SelectableLabel {
                                text: qTwoDigits(modelData.number) + "  " + modelData.name + "  "
                                      + (modelData.settable ? "(" + modelData.options.length + ")"
                                         : modelData.readable ? "(control principal)" : "(pendiente)")
                                color: "#d6d6d6"
                                font.bold: true
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                Layout.fillWidth: true
                                Layout.preferredHeight: 17
                            }
                            SelectableLabel {
                                text: modelData.description
                                color: "#b8b8b8"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                Layout.fillWidth: true
                                Layout.preferredHeight: 16
                            }
                        }
                        SpinBox {
                            id: menuOptionSpin
                            visible: modelData.settable && modelData.options.length > 5
                                     && modelData.editorType === "spin"
                            enabled: visible && !quanshengClient.controlBusy
                            from: modelData.editorType === "spin" ? modelData.minimum : 0
                            to: modelData.editorType === "spin" ? modelData.maximum : 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            editable: false
                            value: {
                                var confirmed = qMenuConfirmedIndex(modelData)
                                confirmed >= 0 ? modelData.options[confirmed].value : from
                            }
                            palette.text: "#f2f2f2"
                            palette.buttonText: "#f2f2f2"
                            background: Rectangle {
                                color: qMenuConfirmedIndex(modelData) >= 0 ? "#294735"
                                      : qMenuReadState(modelData) === "unconfirmed" ? "#514238"
                                      : qMenuReadState(modelData) === "pending" ? "#554a31" : "#424242"
                                border.color: qMenuConfirmedIndex(modelData) >= 0 ? "#668d73"
                                              : qMenuReadState(modelData) === "unconfirmed" ? "#9b765b"
                                              : qMenuReadState(modelData) === "pending" ? "#a18b58" : "#666666"
                                radius: 2
                            }
                        }
                        ComboBox {
                            id: menuOptionCombo
                            visible: modelData.settable && modelData.options.length > 5
                                     && modelData.editorType !== "spin"
                            enabled: visible && !quanshengClient.controlBusy
                            model: modelData.options.map(function(option) { return option.label })
                            currentIndex: qMenuSelectedIndex(modelData)
                            onActivated: function(index) {
                                setQMenuPendingValue(modelData, modelData.options[index].value)
                            }
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            palette.text: "#f2f2f2"
                            palette.buttonText: "#f2f2f2"
                            contentItem: Text {
                                leftPadding: 8
                                rightPadding: menuOptionCombo.indicator.width + 8
                                text: menuOptionCombo.displayText
                                color: "#f2f2f2"
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            delegate: ItemDelegate {
                                required property var modelData
                                width: menuOptionCombo.width
                                text: modelData
                                highlighted: menuOptionCombo.highlightedIndex === index
                                contentItem: Text {
                                    text: modelData
                                    color: "#f2f2f2"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle {
                                    color: parent.highlighted ? "#5b5b5b" : "#363636"
                                }
                            }
                            popup: Popup {
                                y: menuOptionCombo.height
                                width: menuOptionCombo.width
                                implicitHeight: Math.min(contentItem.implicitHeight, 320)
                                padding: 1
                                contentItem: ListView {
                                    clip: true
                                    implicitHeight: contentHeight
                                    model: menuOptionCombo.popup.visible ? menuOptionCombo.delegateModel : null
                                    currentIndex: menuOptionCombo.highlightedIndex
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                background: Rectangle {
                                    color: "#363636"
                                    border.color: "#666666"
                                    radius: 2
                                }
                            }
                            background: Rectangle {
                                color: qMenuConfirmedIndex(modelData) >= 0 ? "#294735"
                                      : qMenuReadState(modelData) === "unconfirmed" ? "#514238"
                                      : qMenuReadState(modelData) === "pending" ? "#554a31" : "#424242"
                                border.color: qMenuConfirmedIndex(modelData) >= 0 ? "#668d73"
                                              : qMenuReadState(modelData) === "unconfirmed" ? "#9b765b"
                                              : qMenuReadState(modelData) === "pending" ? "#a18b58" : "#666666"
                                radius: 2
                            }
                        }
                        SelectableLabel {
                            visible: !modelData.settable
                            text: modelData.options.length ? modelData.options[0].label : "No disponible"
                            color: "#bdbdbd"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            id: menuOptionButtons
                            property var menuDefinition: modelData
                            visible: modelData.settable && modelData.options.length <= 5
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: modelData.options
                                delegate: Button {
                                    required property var modelData
                                    required property int index
                                    text: modelData.label
                                    readonly property bool confirmedSelection: qMenuConfirmedIndex(menuOptionButtons.menuDefinition) === index
                                    readonly property string menuReadState: qMenuReadState(menuOptionButtons.menuDefinition)
                                    enabled: !quanshengClient.controlBusy
                                    readonly property int directWidth: text.length > 10 ? 92 : text.length > 5 ? 68 : 46
                                    Layout.minimumWidth: directWidth
                                    Layout.preferredWidth: directWidth
                                    Layout.maximumWidth: directWidth
                                    Layout.preferredHeight: 30
                                    padding: 3
                                    font.pixelSize: 10
                                    palette.buttonText: "#dedede"
                                    background: Rectangle {
                                        radius: 2
                                        color: parent.confirmedSelection ? (parent.down ? "#315641" : "#294735")
                                              : parent.menuReadState === "unconfirmed" ? (parent.down ? "#594538" : "#514238")
                                              : parent.menuReadState === "pending" ? (parent.down ? "#5c5033" : "#554a31")
                                              : parent.down ? "#353535" : parent.hovered ? "#505050" : "#424242"
                                        border.color: parent.confirmedSelection ? "#668d73"
                                                      : parent.menuReadState === "unconfirmed" ? "#9b765b"
                                                      : parent.menuReadState === "pending" ? "#a18b58" : "#666666"
                                    }
                                    onClicked: applyQuanshengMenuOption(menuOptionButtons.menuDefinition, modelData)
                                }
                            }
                        }
                        QuanshengActionButton {
                            text: "Aplicar"
                            enabled: modelData.settable && !quanshengClient.controlBusy
                            visible: modelData.settable && modelData.options.length > 5
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 30
                            palette.buttonText: enabled ? "#dedede" : "#999999"
                            background: Rectangle {
                                radius: 2
                                color: parent.down ? "#353535" : parent.hovered ? "#505050" : "#424242"
                                border.color: "#666666"
                            }
                            onClicked: {
                                var selected = null
                                if (modelData.editorType === "spin") {
                                    var value = menuOptionSpin.value
                                    selected = modelData.options[value - modelData.minimum]
                                } else if (qMenuSelectedIndex(modelData) >= 0) {
                                    selected = modelData.options[qMenuSelectedIndex(modelData)]
                                }
                                if (selected) {
                                    applyQuanshengMenuOption(modelData, selected)
                                }
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.settable
                                          ? "Menu " + qTwoDigits(modelData.number) + " " + modelData.name
                                          : (modelData.options.length ? modelData.options[0].label : "Pendiente")
                        }
                        QuanshengActionButton {
                            text: "Leer"
                            enabled: quanshengClient.connected
                                     && quanshengClient.menuReadAvailable
                                     && !quanshengClient.controlBusy
                            Layout.preferredWidth: 54
                            Layout.preferredHeight: 30
                            palette.buttonText: enabled ? "#dedede" : "#999999"
                            background: Rectangle {
                                radius: 2
                                color: parent.down ? "#263c40" : parent.hovered ? "#405c61" : "#344c50"
                                border.color: "#587579"
                            }
                            onClicked: readQuanshengMenuValue(modelData)
                            ToolTip.visible: hovered
                            ToolTip.text: "Leer el valor actual de " + qTwoDigits(modelData.number)
                                          + " " + modelData.name
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: quanshengUserSettingsPopup
        width: Math.min(760, window.width - 32)
        height: Math.min(620, window.height - 32)
        x: Math.max(8, (window.width - width) / 2)
        y: Math.max(8, (window.height - height) / 2)
        modal: false
        focus: true
        padding: 12
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: "#292d30"; border.color: "#7f8a91"; radius: 4 }
        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                SelectableLabel { text: "VALORES DE USUARIO EEPROM 0x0E70–0x0F47"; color: "#ffffff"; font.bold: true; Layout.fillWidth: true }
                Button { text: "Cerrar"; onClicked: quanshengUserSettingsPopup.close() }
            }
            SelectableLabel { text: "Lectura actual; preparados para futuros controles de edición. La escritura EEPROM continúa deshabilitada."; color: "#d2b36f"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 1
                model: quanshengUserSettingRows()
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 29
                    color: index % 2 ? "#252b2e" : "#22272a"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        SelectableLabel { text: modelData.address; color: "#a9c3ce"; font.family: "monospace"; Layout.preferredWidth: 75 }
                        SelectableLabel { text: modelData.field; color: "#d8e0e4"; elide: Text.ElideRight; Layout.preferredWidth: 250 }
                        SelectableLabel { text: modelData.value || "—"; color: "#ffffff"; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    Popup {
        id: eepromPopup
        property int page: 0 // 0 canales, 1 otros datos, 2 hexadecimal
        width: Math.min(860, window.width - 32)
        height: Math.min(620, window.height - 32)
        x: Math.max(8, (window.width - width) / 2)
        y: Math.max(8, (window.height - height) / 2)
        modal: false
        focus: true
        padding: 12
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: "#292d30"; border.color: "#7f8a91"; radius: 4 }
        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                SelectableLabel { text: "EEPROM QUANSHENG UV-K5 · SOLO LECTURA"; color: "#ffffff"; font.bold: true; font.pixelSize: 14; Layout.fillWidth: true }
                Button { text: quanshengClient.eepromBusy ? "Leyendo…" : "Leer EEPROM"; enabled: quanshengClient.eepromReadAvailable && !quanshengClient.eepromBusy; onClicked: quanshengClient.readEeprom() }
                Button {
                    text: "Copiar EEPROM"
                    enabled: quanshengClient.eepromHexDump.length > 0
                    onClicked: radioController.copyTextToClipboard(
                                   quanshengClient.eepromHexDump,
                                   "EEPROM Quansheng")
                }
                Button { text: "Cerrar"; onClicked: eepromPopup.close() }
            }
            SelectableLabel { text: quanshengClient.eepromStatus; color: quanshengClient.eepromStatus.startsWith("Error") ? "#e06c75" : "#8fd3ed"; Layout.fillWidth: true }
            SelectableLabel { text: "La lectura inicia una sesión con la radio y puede apagar temporalmente su iluminación. No se escribe ningún byte en EEPROM."; color: "#d2b36f"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout {
                Button { text: "Canales"; checkable: true; checked: eepromPopup.page === 0; onClicked: eepromPopup.page = 0 }
                Button { text: "Ajustes y calibración"; checkable: true; checked: eepromPopup.page === 1; onClicked: eepromPopup.page = 1 }
                Button { text: "Hexadecimal"; checkable: true; checked: eepromPopup.page === 2; onClicked: eepromPopup.page = 2 }
                SelectableLabel { text: quanshengClient.eepromChannelRows.length ? (eepromPopup.page === 0 ? "200 canales · vacíos incluidos" : eepromPopup.page === 1 ? quanshengClient.eepromSettingRows.length + " datos interpretados" : "8192 bytes") : ""; color: "#9da8ad"; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
            }
            Rectangle {
                visible: eepromPopup.page === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#202629"
                border.color: "#465157"
                radius: 3
                Flickable {
                    id: eepromTableFlick
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    contentWidth: 1450
                    contentHeight: eepromTableColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }
                    Column {
                        id: eepromTableColumn
                        width: 1450
                        spacing: 1
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["Canal", "Nombre", "RX MHz", "TX MHz", "Desplazamiento", "Modo", "Ancho", "Potencia", "Tono RX", "Tono TX", "Paso", "Escaneo", "Opciones"]
                                SelectableLabel {
                                    required property var modelData
                                    required property int index
                                    width: [55,110,95,95,125,70,75,75,145,145,85,100,130][index]
                                    text: modelData
                                    color: "#91a6af"
                                    font.bold: true
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Repeater {
                            model: quanshengClient.eepromChannelRows
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: 1450
                                height: 24
                                color: index % 2 ? "#252b2e" : "#22272a"
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    property var values: modelData.empty
                                        ? [String(modelData.channel).padStart(3, "0"), modelData.name || "—", "VACÍO", "—", "—", "—", "—", "—", "—", "—", "—", modelData.scan || "—", "—"]
                                        : [String(modelData.channel).padStart(3, "0"), modelData.name || "—", modelData.rx, modelData.tx, modelData.offset, modelData.mode, modelData.bandwidth, modelData.power, modelData.rxTone, modelData.txTone, modelData.step, modelData.scan || "—", modelData.flags || "—"]
                                    Repeater {
                                        model: parent.values
                                        SelectableLabel {
                                            required property var modelData
                                            required property int index
                                            width: [55,110,95,95,125,70,75,75,145,145,85,100,130][index]
                                            text: modelData
                                            color: index === 2 && modelData === "VACÍO" ? "#758087" : "#d8e0e4"
                                            elide: Text.ElideRight
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                visible: eepromPopup.page === 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#202629"
                border.color: "#465157"
                radius: 3
                Flickable {
                    id: eepromSettingsFlick
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    contentWidth: 1150
                    contentHeight: eepromSettingsColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }
                    Column {
                        id: eepromSettingsColumn
                        width: 1150
                        spacing: 1
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["Sección", "Dirección", "Dato", "Valor interpretado", "Observación"]
                                SelectableLabel {
                                    required property var modelData
                                    required property int index
                                    width: [170,80,220,300,310][index]
                                    text: modelData
                                    color: "#91a6af"
                                    font.bold: true
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Repeater {
                            model: quanshengClient.eepromSettingRows
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: 1150
                                height: 25
                                color: index % 2 ? "#252b2e" : "#22272a"
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    property var values: [modelData.section, modelData.address, modelData.field, modelData.value || "—", modelData.detail || ""]
                                    Repeater {
                                        model: parent.values
                                        SelectableLabel {
                                            required property var modelData
                                            required property int index
                                            width: [170,80,220,300,310][index]
                                            text: modelData
                                            color: index === 0 ? "#8fd3ed" : index === 1 ? "#a9c3ce" : "#d8e0e4"
                                            font.family: index === 1 ? "monospace" : Qt.application.font.family
                                            elide: Text.ElideRight
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            TextArea {
                visible: eepromPopup.page === 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.NoWrap
                font.family: "monospace"
                font.pixelSize: 12
                color: "#d8e0e4"
                text: quanshengClient.eepromHexDump || "Pulsa «Leer EEPROM» para obtener el volcado completo (0x0000–0x1FFF)."
                background: Rectangle { color: "#202629"; border.color: "#465157"; radius: 3 }
            }
        }
    }

    Popup {
        id: registerPopup
        width: Math.min(900, window.width - 32)
        height: Math.min(620, window.height - 32)
        x: Math.max(8, (window.width - width) / 2)
        y: Math.max(8, (window.height - height) / 2)
        modal: false
        focus: true
        padding: 12
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            color: "#292d30"
            border.color: "#7f8a91"
            border.width: 1
            radius: 4
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                SelectableLabel {
                    text: "REGISTROS BK4819 · LECTURA Y DIAGNÓSTICO"
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 14
                    Layout.fillWidth: true
                }
                SelectableLabel {
                    text: quanshengClient.hardwareRegisterCount > 0
                          ? quanshengClient.hardwareRegisterCount + " valores recibidos"
                          : "Esperando primera lectura…"
                    color: "#8fd3ed"
                }
                Button {
                    text: "Copiar tabla"
                    enabled: quanshengClient.hardwareRegisterRows.length > 0
                    onClicked: radioController.copyTextToClipboard(
                                   quanshengRegistersClipboardText(),
                                   "Registros BK4819")
                }
                Button { text: "Cerrar"; onClicked: registerPopup.close() }
            }
            SelectableLabel {
                text: "Datos técnicos de sólo lectura · — indica que el registro todavía no se consulta"
                color: "#9da8ad"
                Layout.fillWidth: true
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#22272a"
                border.color: "#465157"
                radius: 3
                Flickable {
                    id: registerFlick
                    anchors.fill: parent
                    anchors.margins: 7
                    clip: true
                    contentWidth: width
                    contentHeight: registerColumns.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOn }
                    RowLayout {
                        id: registerColumns
                        width: registerFlick.width - 14
                        spacing: 18
                        Repeater {
                            model: 2
                            ColumnLayout {
                                id: registerHalf
                                required property int index
                                property int firstRow: registerHalf.index * Math.ceil(quanshengClient.hardwareRegisterRows.length / 2)
                                property int rowsHere: Math.min(Math.ceil(quanshengClient.hardwareRegisterRows.length / 2), quanshengClient.hardwareRegisterRows.length - registerHalf.firstRow)
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    SelectableLabel { text: "Registro"; color: "#91a6af"; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 65 }
                                    SelectableLabel { text: "Valor"; color: "#91a6af"; font.bold: true; font.pixelSize: 12; Layout.preferredWidth: 72 }
                                    SelectableLabel { text: "Interpretación"; color: "#91a6af"; font.bold: true; font.pixelSize: 12; Layout.fillWidth: true }
                                }
                                Repeater {
                                    model: registerHalf.rowsHere
                                    RowLayout {
                                        required property int index
                                        property var rowData: quanshengClient.hardwareRegisterRows[registerHalf.firstRow + index]
                                        Layout.fillWidth: true
                                        SelectableLabel { text: rowData ? rowData.register : "—"; color: "#a9c3ce"; font.family: "monospace"; font.pixelSize: 12; Layout.preferredWidth: 65 }
                                        SelectableLabel { text: rowData ? rowData.value : "—"; color: "#e0e5e7"; font.family: "monospace"; font.pixelSize: 12; Layout.preferredWidth: 72 }
                                        SelectableLabel { text: rowData ? rowData.interpretation : "—"; color: "#c8d0d4"; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
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
                        } else if (toolbarButton.iconName === "video") {
                            ctx.strokeRect(4, 8, 18, 16)
                            line(22, 12, 29, 8)
                            line(29, 8, 29, 24)
                            line(29, 24, 22, 20)
                            line(8, 5, 18, 5)
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
        property bool compact: false
        property color barColor: "#43bafd"
        property int valueRightMargin: 0

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
            spacing: meter.compact ? 1 : 4

            Text {
                Layout.preferredWidth: 34
                text: meter.caption
                color: "#f0f0f0"
                font.pixelSize: meter.compact ? 11 : 9
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
                Layout.preferredWidth: meter.compact ? 48 : 52
                Layout.rightMargin: meter.valueRightMargin
                text: meter.valueText
                color: "#f0f0f0"
                font.pixelSize: meter.compact ? 10 : 9
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

                ctx.font = "bold 8px sans-serif"
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
                ctx.font = "bold 9px sans-serif"
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

                ctx.font = "bold 8px 'DejaVu Sans'"
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
                ctx.font = "bold 9px 'DejaVu Sans'"
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
                ctx.font = "bold 8px 'DejaVu Sans'"

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
            compact ? 170 : 178
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
                    Layout.fillWidth: false
                    Layout.minimumWidth: 80
                    Layout.preferredWidth: 80
                    Layout.maximumWidth: 80
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
                    Layout.fillWidth: false
                    Layout.minimumWidth: 80
                    Layout.preferredWidth: 80
                    Layout.maximumWidth: 80
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
        property bool wheelEnabled: true
        property var wheelFunction: null
        property var doubleClickFunction: null

        property color displayColor:
            active
            ? (vfoNumber === 0
               ? "#36c8ff"
               : "#ffb347")
            : (radioController.splitEnabled
               ? "#ffc276"
               : "#9bd7aa")

        property color outlineColor:
            active
            ? (vfoNumber === 0
               ? "#0b3c56"
               : "#5a2e08")
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
                return 0
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
                    return 0
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

            return digitsOnRight === 0
                    ? 0
                    : Math.pow(10, Math.max(1, digitsOnRight))
        }

        function digitCountRightAt(pointerX) {
            const step = digitStepAt(pointerX)
            return step > 0 ? Math.round(Math.log(step) / Math.LN10) : 0
        }

        function stepText(step) {
            if (step <= 0)
                return "no ajustable"
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
                frequencyDigits.doubleClickFunction ? Qt.LeftButton : Qt.NoButton
            hoverEnabled: true
            enabled:
                frequencyDigits.wheelEnabled
                && (frequencyDigits.wheelFunction
                    || controlsEnabled())

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

            WheelHandler {
                acceptedDevices:
                    PointerDevice.Mouse
                    | PointerDevice.TouchPad
                enabled:
                    frequencyDigits.wheelEnabled
                    && (frequencyDigits.wheelFunction
                        || controlsEnabled())

                onWheel: function(event) {
                    const delta = event.angleDelta.y !== 0
                                  ? event.angleDelta.y
                                  : event.pixelDelta.y
                    if (delta === 0) {
                        event.accepted = false
                        return
                    }

                    const direction = delta > 0 ? 1 : -1
                    const x = point.position.x
                    if (frequencyDigits.wheelFunction) {
                        frequencyDigits.wheelFunction(
                            x, frequencyDigits.width, direction)
                    } else {
                        const step = frequencyDigits.digitStepAt(x)
                        if (step > 0
                                && adjustTuningFrequency(
                                    frequencyDigits.vfoNumber,
                                    direction * step))
                            tuningAngle += direction * 8
                    }
                    event.accepted = true
                }
            }

            onDoubleClicked: {
                if (frequencyDigits.doubleClickFunction)
                    frequencyDigits.doubleClickFunction(
                        frequencyDigits.digitCountRightAt(mouse.x))
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
                    Layout.preferredWidth: 86
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
                    Layout.preferredWidth: 68
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
                        id: qrzRecentText
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
                    Layout.preferredWidth: 86
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
                    Layout.preferredWidth: 86
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
                    Layout.preferredWidth: 86
                    text: "Actualizar"
                    tip: "Vuelve a leer los ajustes TX/AUDIO de la radio."
                    enabled: radioController.connected
                    onClicked: radioController.refreshTxAudioSettings()
                }

                PanelButton {
                    Layout.preferredWidth: 68
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
        id: detachedVideoWindow

        visible: window.videoDetached
        width: 920
        height: 560
        minimumWidth: 420
        minimumHeight: 280
        flags: Qt.Window
        color: "#090a0b"
        title: "Vídeo IC-7300MK2"

        onClosing: function(close) {
            close.accepted = false
            window.videoDetached = false
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 7
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                PanelButton {
                    Layout.preferredWidth: 112
                    Layout.minimumWidth: 100
                    Layout.preferredHeight: 28
                    text: "SOLO SCOPE"
                    selected: videoCapture.scopeOnly
                    activeColor: "#3f6e82"
                    onClicked: videoCapture.scopeOnly = true
                }

                PanelButton {
                    Layout.preferredWidth: 178
                    Layout.minimumWidth: 160
                    Layout.preferredHeight: 28
                    text: "PANTALLA COMPLETA"
                    selected: !videoCapture.scopeOnly
                    activeColor: "#3f6e82"
                    onClicked: videoCapture.scopeOnly = false
                }

                Item { Layout.fillWidth: true }

                PanelButton {
                    Layout.preferredWidth: 106
                    Layout.minimumWidth: 96
                    Layout.preferredHeight: 28
                    text: "ACOPLAR"
                    activeColor: "#347e98"
                    tip: "Devuelve el vídeo al panel Icom."
                    onClicked: window.videoDetached = false
                }
            }

            FrameBox {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"
                border.color: "#555b60"
                clip: true

                VideoFrameItem {
                    anchors.fill: parent
                    anchors.margins: 3
                    controller: videoCapture
                    scopeOnly: videoCapture.scopeOnly
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: videoCapture.scopeOnly = !videoCapture.scopeOnly
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    visible: videoCapture.frameRevision === 0
                    text: videoCapture.status
                    color: "#aab2b8"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Window {
        id: superCompactWindow

        property bool returningToCompact: false
        readonly property int preferredWidth:
            (applicationLauncher.icomPanelVisible ? 320 : 0)
            + (applicationLauncher.quanshengPanelVisible ? 320 : 0)
            + (applicationLauncher.icomPanelVisible
               && applicationLauncher.quanshengPanelVisible ? 9 : 0)
            + 10

        visible: superCompactVisible
        width: preferredWidth
        height: 64
        minimumWidth: preferredWidth
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
            border.color:
                applicationLauncher.icomPanelVisible
                ? (radioController.selectedVfo === 0 ? "#347e98" : "#9a6630")
                : (quanshengClient.activeVfo === "B" ? "#9a6630" : "#347e98")
            radius: 4

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 8

                RowLayout {
                    visible: applicationLauncher.icomPanelVisible
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6
                    Text {
                        text: "IC"
                        color: "#75c6e2"
                        font.pixelSize: 13
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: radioController.frequencyMhzText
                        color: radioController.selectedVfo === 0 ? "#36c8ff" : "#ffb347"
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 25
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideLeft
                    }
                    Text {
                        text: radioController.modeText
                              + (radioController.dataMode ? "-D" : "")
                        color: "#ffd27a"
                        font.pixelSize: 20
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    visible: applicationLauncher.icomPanelVisible
                             && applicationLauncher.quanshengPanelVisible
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: "#53616a"
                }

                RowLayout {
                    visible: applicationLauncher.quanshengPanelVisible
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6
                    Text {
                        text: "QS"
                        color: "#8fdb9b"
                        font.pixelSize: 13
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: quanshengClient.activeVfo === "B"
                              ? quanshengClient.vfoBFrequencyText
                              : quanshengClient.vfoAFrequencyText
                        color: quanshengClient.activeVfo === "B" ? "#ffb347" : "#36c8ff"
                        font.family: "DejaVu Sans Mono"
                        font.pixelSize: 25
                        font.bold: true
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideLeft
                    }
                    Text {
                        text: quanshengClient.activeVfo === "B"
                              ? quanshengClient.vfoBMode
                              : quanshengClient.vfoAMode
                        color: "#ffd27a"
                        font.pixelSize: 20
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: returnFromSuperCompact()
            }
        }
    }

    Window {
        id: compactWindow

        property bool returningToFullView: false
        property bool adjustingSize: false
        readonly property real baseWidth: 700
        readonly property real baseHeight:
            applicationLauncher.icomPanelVisible
            ? (applicationLauncher.quanshengPanelVisible ? 194 : 116)
            : 130
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
        title: "IC-7300MK2 · Control compacto · Compilado " + buildTimestamp

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
        onBaseHeightChanged: {
            adjustingSize = true
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

            GridLayout {
                anchors.fill: parent
                anchors.margins: 7
                columns: 1
                rowSpacing: 5
                columnSpacing: 0

                RowLayout {
                    Layout.row: 0
                    Layout.column: 0
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
                        visible: applicationLauncher.icomPanelVisible
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
                        visible: applicationLauncher.icomPanelVisible
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
                        visible: applicationLauncher.icomPanelVisible
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
                        visible: applicationLauncher.icomPanelVisible
                        text: "TUNE"
                        activeColor: "#8a6330"
                        Layout.preferredWidth: 54
                        enabled: radioController.connected
                        tip: "Inicia el ciclo de ajuste del acoplador."
                        onClicked: radioController.startTuner()
                    }
                    Rectangle {
                        visible: applicationLauncher.icomPanelVisible
                        Layout.fillWidth: true
                        Layout.minimumWidth: 75
                        Layout.preferredHeight: 28
                        color: "#071014"
                        border.color:
                            radioController.selectedVfo === 0
                            ? "#347e98"
                            : "#9a6630"
                        radius: 3
                        clip: true
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 6
                            text: radioController.frequencyMhzText
                                  + "  " + radioController.modeText
                                  + (radioController.dataMode ? "-D" : "")
                            color:
                                radioController.selectedVfo === 0
                                ? "#36c8ff"
                                : "#ffb347"
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
                            tip: "Vista de frecuencia y modo"
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
                            onClicked: window.beginApplicationShutdown()
                        }
                    }
                }

                Rectangle {
                    visible: applicationLauncher.quanshengPanelVisible
                    Layout.row: applicationLauncher.icomPanelVisible ? 2 : 1
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 69
                    color: "#1c2a22"
                    border.color: "#4b795c"
                    radius: 3

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            spacing: 4

                            PanelButton {
                                text: "AS"
                                Layout.preferredWidth: 34
                                textPixelSize: 9
                                activeColor: "#397a52"
                                enabled: !quanshengClient.connected
                                tip: quanshengClient.serverLocation === "local"
                                     ? "Arrancar servidor Quansheng en este PC"
                                     : "Arrancar servidor Quansheng remoto por SSH"
                                onClicked: quanshengClient.startServerGuiBySsh()
                            }

                            PanelButton {
                                text: "PS"
                                Layout.preferredWidth: 34
                                textPixelSize: 9
                                activeColor: "#8b3535"
                                tip: quanshengClient.serverLocation === "local"
                                     ? "Parar servidor Quansheng en este PC"
                                     : "Parar servidor Quansheng remoto por SSH"
                                onClicked: quanshengClient.stopServerGuiBySsh()
                            }

                            PanelButton {
                                text: quanshengClient.connected ? "QS ON" : "QS OFF"
                                selected: quanshengClient.connected
                                activeColor: "#397a52"
                                Layout.preferredWidth: 58
                                textPixelSize: 9
                                tip: quanshengClient.connected
                                      ? "Desconectar del servidor Quansheng"
                                      : "Conectar con el servidor Quansheng"
                                onClicked: quanshengClient.connected
                                           ? quanshengClient.disconnectFromServer()
                                           : quanshengClient.connectToServer()
                            }

                            Text {
                                Layout.preferredWidth: 74
                                text: quanshengClient.connected
                                      ? (quanshengClient.eventStreamStalled ? "Sin eventos"
                                         : quanshengClient.sourceStatus)
                                      : "Desconectado"
                                color: quanshengClient.eventStreamStalled ? "#ff8585"
                                       : quanshengClient.connected ? "#8fdb9b" : "#d8bd82"
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }

                            Repeater {
                                model: ["A", "B"]
                                PanelButton {
                                    required property string modelData
                                    readonly property bool selectedVfo:
                                        quanshengClient.activeVfo === modelData
                                    text: "VFO " + modelData
                                    Layout.preferredWidth: 48
                                    Layout.minimumWidth: 48
                                    Layout.maximumWidth: 48
                                    textPixelSize: 9
                                    selected: selectedVfo
                                    activeColor: modelData === "A" ? "#397a52" : "#8a6330"
                                    enabled: quanshengClient.connected
                                             && quanshengClient.frequencyControlAvailable
                                             && !quanshengClient.controlBusy
                                    onClicked: if (!selectedVfo) quanshengClient.switchVfo()
                                }
                            }

                            TextField {
                                id: compactQuanshengFrequencyField
                                Layout.fillWidth: true
                                Layout.minimumWidth: 100
                                Layout.preferredHeight: 30
                                horizontalAlignment: TextInput.AlignHCenter
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 16
                                font.bold: true
                                color: quanshengClient.activeVfo === "B"
                                       ? "#ffb347" : "#36c8ff"
                                selectByMouse: true
                                placeholderText: "Frecuencia MHz"
                                enabled: quanshengClient.connected
                                         && quanshengClient.frequencyControlAvailable
                                         && !quanshengClient.controlBusy
                                Component.onCompleted: text = quanshengClient.activeVfo === "B"
                                    ? quanshengClient.vfoBFrequencyText
                                    : quanshengClient.vfoAFrequencyText
                                onAccepted: quanshengClient.setFrequency(text.trim())
                                background: Rectangle {
                                    color: quanshengClient.activeVfo === "B"
                                           ? "#211708" : "#06202b"
                                    border.color: quanshengClient.activeVfo === "B"
                                                  ? "#ffad4d" : "#42bfff"
                                    border.width: 1
                                    radius: 3
                                }
                                Connections {
                                    target: quanshengClient
                                    function onStateChanged() {
                                        if (compactQuanshengFrequencyField.activeFocus)
                                            return
                                        compactQuanshengFrequencyField.text =
                                            quanshengClient.activeVfo === "B"
                                            ? quanshengClient.vfoBFrequencyText
                                            : quanshengClient.vfoAFrequencyText
                                    }
                                }
                            }

                            PanelButton {
                                text: "Validar"
                                Layout.preferredWidth: 52
                                textPixelSize: 9
                                enabled: compactQuanshengFrequencyField.enabled
                                onClicked: quanshengClient.setFrequency(
                                               compactQuanshengFrequencyField.text.trim())
                            }

                            PanelButton {
                                text: quanshengClient.pttPressed ? "RX" : "PTT"
                                Layout.preferredWidth: 48
                                textPixelSize: 9
                                selected: quanshengClient.pttPressed
                                activeColor: "#a33d3d"
                                enabled: quanshengClient.connected
                                         && quanshengClient.txControlAvailable
                                         && (quanshengClient.pttPressed
                                             || (!quanshengClient.controlBusy
                                                 && !quanshengClient.eepromBusy))
                                tip: "Mantén pulsado para transmitir"
                                onPressed: quanshengClient.pressPtt()
                                onReleased: quanshengClient.releasePtt()
                                onCanceled: quanshengClient.releasePtt()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 25
                            spacing: 3

                            Repeater {
                                model: ["FM", "AM", "USB"]
                                PanelButton {
                                    required property string modelData
                                    readonly property string activeMode:
                                        quanshengClient.activeVfo === "B"
                                        ? quanshengClient.vfoBMode
                                        : quanshengClient.activeVfo === "A"
                                          ? quanshengClient.vfoAMode : ""
                                    text: modelData
                                    Layout.preferredWidth: 38
                                    Layout.minimumWidth: 38
                                    Layout.maximumWidth: 38
                                    textPixelSize: 9
                                    selected: activeMode === modelData
                                    activeColor: "#2f72b9"
                                    enabled: quanshengClient.connected
                                             && quanshengClient.frequencyControlAvailable
                                             && !quanshengClient.controlBusy
                                             && quanshengClient.activeVfo !== ""
                                    tip: quanshengClient.activeVfo === ""
                                         ? "Esperando a identificar el VFO activo"
                                         : "Aplicar modo al VFO activo"
                                    onClicked: if (activeMode !== modelData)
                                                   quanshengClient.setMode(
                                                       quanshengClient.activeVfo, modelData)
                                }
                            }

                            Repeater {
                                model: quanshengBandDefinitions
                                PanelButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredHeight: 25
                                    text: modelData.name
                                    textPixelSize: 9
                                    selected: activeQuanshengBandName === modelData.name
                                              || (activeQuanshengBandName === ""
                                                  && (quanshengClient.activeVfo === "B"
                                                      ? String(quanshengClient.vfoBMemory).startsWith(modelData.name)
                                                      : String(quanshengClient.vfoAMemory).startsWith(modelData.name)))
                                    activeColor: modelData.name === "VHF"
                                                 || modelData.name === "UHF"
                                                 ? "#8b5f12" : "#4a4a4a"
                                    enabled: quanshengClient.connected
                                             && quanshengClient.frequencyControlAvailable
                                             && !quanshengClient.controlBusy
                                    tip: modelData.label
                                    onClicked: window.selectQuanshengBand(modelData)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: applicationLauncher.icomPanelVisible
                    Layout.row: 1
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    color: "#17262d"
                    border.color: "#3d7186"
                    radius: 3

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 1
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
                            required property int index
                            required property var modelData
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

        property int sectionIndex: 5

        transientParent: window
        visible: settingsVisible
        width: 940
        height: 760
        minimumWidth: 820
        minimumHeight: 640
        flags: Qt.Tool
        color: "#202326"
        title: "Configuración avanzada · Radios"

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
                if (quanshengClient.serverLocation === "local")
                    quanshengClient.refreshLocalSerialPorts()
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
                        text: "CONFIGURACIÓN"
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
                                text: "GENERAL"
                                selected: settingsPopup.sectionIndex === 5
                                activeColor: "#69734c"
                                onClicked: settingsPopup.sectionIndex = 5
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "VÍDEO HDMI"
                                selected: settingsPopup.sectionIndex === 6
                                activeColor: "#3f6e82"
                                onClicked: settingsPopup.sectionIndex = 6
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "CONEXIÓN ICOM"
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

                            PanelButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: "QUANSHENG LAN"
                                selected:
                                    settingsPopup
                                    .sectionIndex === 4
                                activeColor: "#557b69"
                                onClicked:
                                    settingsPopup
                                    .sectionIndex = 4
                            }

                            Item {
                                Layout.fillHeight: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text:
                                    "Las preferencias se guardan en la "
                                    + "configuración del usuario."
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
                                            CheckBox {
                                                id: lanPasswordVisible
                                                text: "Mostrar"
                                                enabled: connectionTypeBox.currentIndex === 1
                                                font.pixelSize: 10
                                                palette.text: "#d9e0e4"
                                                indicator: Rectangle {
                                                    implicitWidth: 18
                                                    implicitHeight: 18
                                                    x: 0
                                                    y: (parent.height - height) / 2
                                                    radius: 3
                                                    color: parent.checked ? "#287a55" : "#111719"
                                                    border.width: 1
                                                    border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✓"
                                                        color: "#ffffff"
                                                        font.pixelSize: 14
                                                        font.bold: true
                                                        visible: lanPasswordVisible.checked
                                                    }
                                                }
                                            }

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
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    visible: connectionAutoCheck.checked
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
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
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    visible: connectionReconnectCheck.checked
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
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

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width: parent.width
                                spacing: 8

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 410
                                    color: "#171a1c"

                                    GridLayout {
                                        anchors.fill: parent
                                        anchors.margins: 9
                                        columns: 3
                                        rowSpacing: 8
                                        columnSpacing: 8

                                        Text { text: "Servidor"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true }
                                        RowLayout {
                                            Layout.columnSpan: 2
                                            Layout.fillWidth: true
                                            spacing: 4
                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "Este PC"
                                                selected: quanshengClient.serverLocation === "local"
                                                onClicked: quanshengClient.serverLocation = "local"
                                            }
                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "Remoto (SSH)"
                                                selected: quanshengClient.serverLocation === "remote"
                                                onClicked: quanshengClient.serverLocation = "remote"
                                            }
                                        }
                                        Text {
                                            visible: quanshengClient.serverLocation === "remote"
                                            text: "Host"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true
                                        }
                                        TextField {
                                            id: quanshengSettingsHost
                                            visible: quanshengClient.serverLocation === "remote"
                                            Layout.columnSpan: 2
                                            Layout.fillWidth: true
                                            text: quanshengClient.host
                                            placeholderText: "ramon@192.168.1.78"
                                            onEditingFinished: quanshengClient.host = text
                                        }
                                        Text {
                                            visible: quanshengClient.serverLocation === "local"
                                            text: "Host"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true
                                        }
                                        SelectableLabel {
                                            visible: quanshengClient.serverLocation === "local"
                                            Layout.columnSpan: 2
                                            text: "Este PC · 127.0.0.1"
                                            color: "#aeb9be"
                                            font.pixelSize: 10
                                        }
                                        Text {
                                            visible: quanshengClient.serverLocation === "local"
                                            text: "Puerto serie"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true
                                        }
                                        RowLayout {
                                            visible: quanshengClient.serverLocation === "local"
                                            Layout.columnSpan: 2
                                            Layout.fillWidth: true
                                            spacing: 5
                                            ComboBox {
                                                id: quanshengLocalSerialPort
                                                Layout.fillWidth: true
                                                enabled: !quanshengClient.connected
                                                model: quanshengClient.localSerialPorts
                                                textRole: "label"
                                                valueRole: "device"
                                                currentIndex: {
                                                    for (var i = 0; i < quanshengClient.localSerialPorts.length; ++i)
                                                        if (quanshengClient.localSerialPorts[i].device
                                                                === quanshengClient.localSerialDevice)
                                                            return i
                                                    return -1
                                                }
                                                displayText: currentIndex < 0
                                                             ? "Selecciona un puerto serie" : currentText
                                                onActivated: quanshengClient.localSerialDevice = currentValue
                                            }
                                            Button {
                                                text: "Actualizar"
                                                enabled: !quanshengClient.connected
                                                implicitWidth: 84
                                                onClicked: quanshengClient.refreshLocalSerialPorts()
                                                ToolTip.visible: hovered
                                                ToolTip.text: "Volver a detectar los puertos serie de este PC"
                                            }
                                        }
                                        Text { text: "Puerto LAN"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true }
                                        SpinBox {
                                            id: quanshengSettingsPort
                                            Layout.columnSpan: 2
                                            from: 1; to: 65535
                                            value: quanshengClient.port
                                            editable: true
                                            onValueModified: quanshengClient.port = value
                                        }
                                        Text {
                                            visible: quanshengClient.serverLocation === "remote"
                                            text: "Token"; color: "#d9e0e4"; font.pixelSize: 10; font.bold: true
                                        }
                                        TextField {
                                            id: quanshengSettingsToken
                                            visible: quanshengClient.serverLocation === "remote"
                                            Layout.columnSpan: 2
                                            Layout.fillWidth: true
                                            text: quanshengClient.token
                                            echoMode: TextInput.Password
                                            onEditingFinished: quanshengClient.token = text
                                        }
                                        Item { visible: quanshengClient.serverLocation === "local"; Layout.columnSpan: 3; Layout.preferredHeight: 1 }
                                        SelectableLabel {
                                            visible: quanshengClient.serverLocation === "local"
                                            Layout.columnSpan: 3
                                            text: "El token local se crea y protege automáticamente."
                                            color: "#aeb9be"
                                            font.pixelSize: 9
                                        }
                                        CheckBox {
                                            id: quanshengAutoReconnectCheck
                                            Layout.columnSpan: 3
                                            text: "Reconectar automáticamente si el servidor vuelve a estar disponible"
                                            checked: quanshengClient.autoReconnect
                                            onToggled: quanshengClient.autoReconnect = checked
                                            palette.text: "#d9e0e4"
                                            indicator: Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    visible: quanshengAutoReconnectCheck.checked
                                                }
                                            }
                                            contentItem: Text {
                                                text: quanshengAutoReconnectCheck.text
                                                color: "#d9e0e4"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 28
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        CheckBox {
                                            id: quanshengAutoConnectCheck
                                            Layout.columnSpan: 3
                                            text: "Conectar automáticamente al iniciar la aplicación"
                                            checked: quanshengClient.autoConnectOnStartup
                                            onToggled: quanshengClient.autoConnectOnStartup = checked
                                            palette.text: "#d9e0e4"
                                            indicator: Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    visible: quanshengAutoConnectCheck.checked
                                                }
                                            }
                                            contentItem: Text {
                                                text: quanshengAutoConnectCheck.text
                                                color: "#d9e0e4"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 28
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        CheckBox {
                                            id: quanshengAutoStartLocalCheck
                                            visible: quanshengClient.serverLocation === "local"
                                            Layout.columnSpan: 3
                                            text: "Arrancar y conectar al servidor local al iniciar el cliente"
                                            checked: quanshengClient.autoStartLocalServer
                                            onToggled: quanshengClient.autoStartLocalServer = checked
                                            palette.text: "#d9e0e4"
                                            indicator: Rectangle {
                                                implicitWidth: 18; implicitHeight: 18
                                                x: 0; y: (parent.height - height) / 2; radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent; text: "✓"; color: "#ffffff"
                                                    font.pixelSize: 14; font.bold: true
                                                    visible: quanshengAutoStartLocalCheck.checked
                                                }
                                            }
                                            contentItem: Text {
                                                text: quanshengAutoStartLocalCheck.text
                                                color: "#d9e0e4"; font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.left: parent.left; anchors.leftMargin: 28
                                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Item { Layout.columnSpan: 3; Layout.preferredHeight: 2 }

                                        PanelButton {
                                            Layout.columnSpan: 1
                                            Layout.preferredWidth: 140
                                            text: quanshengClient.connected ? "DESCONECTAR" : "CONECTAR"
                                            selected: quanshengClient.connected
                                            activeColor: "#3d7650"
                                            onClicked: {
                                                if (quanshengClient.connected) {
                                                    quanshengClient.disconnectFromServer()
                                                } else {
                                                    quanshengClient.port = quanshengSettingsPort.value
                                                    if (quanshengClient.serverLocation === "remote") {
                                                        quanshengClient.host = quanshengSettingsHost.text
                                                        quanshengClient.token = quanshengSettingsToken.text
                                                    }
                                                    quanshengClient.connectToServer()
                                                }
                                            }
                                        }
                                        PanelButton {
                                            Layout.columnSpan: 1
                                            Layout.preferredWidth: 170
                                            text: "REINICIAR SERVIDOR"
                                            enabled: quanshengClient.connected
                                            activeColor: "#8b5f12"
                                            groupAccentColor: "#d49a24"
                                            onClicked: quanshengClient.restartServer()
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width: parent.width
                                spacing: 10

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 142
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: "PANELES EN LA VENTANA PRINCIPAL"
                                            color: "#e5e9ec"
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        CheckBox {
                                            id: icomPanelVisibleCheck
                                            Layout.fillWidth: true
                                            text: "Mostrar panel Icom"
                                            checked: applicationLauncher.icomPanelVisible
                                            onToggled: applicationLauncher.icomPanelVisible = checked
                                            palette.text: "#e3e8eb"
                                            indicator: Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    visible: icomPanelVisibleCheck.checked
                                                }
                                            }
                                            contentItem: Text {
                                                text: icomPanelVisibleCheck.text
                                                color: "#e3e8eb"
                                                font.pixelSize: 12
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 28
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        CheckBox {
                                            id: quanshengPanelVisibleCheck
                                            Layout.fillWidth: true
                                            text: "Mostrar panel Quansheng"
                                            checked: applicationLauncher.quanshengPanelVisible
                                            onToggled: applicationLauncher.quanshengPanelVisible = checked
                                            palette.text: "#e3e8eb"
                                            indicator: Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    visible: quanshengPanelVisibleCheck.checked
                                                }
                                            }
                                            contentItem: Text {
                                                text: quanshengPanelVisibleCheck.text
                                                color: "#e3e8eb"
                                                font.pixelSize: 12
                                                verticalAlignment: Text.AlignVCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 28
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 128
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        Text {
                                            Layout.fillWidth: true
                                            text: "MODO DE INICIO"
                                            color: "#e5e9ec"
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                text: "NORMAL"
                                                selected: applicationLauncher.startupViewMode === "normal"
                                                activeColor: "#386d84"
                                                onClicked: applicationLauncher.startupViewMode = "normal"
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                text: "COMPACTO"
                                                selected: applicationLauncher.startupViewMode === "compact"
                                                activeColor: "#4f795d"
                                                onClicked: applicationLauncher.startupViewMode = "compact"
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                text: "FRECUENCIA Y MODO"
                                                selected: applicationLauncher.startupViewMode === "frequency"
                                                activeColor: "#7b6538"
                                                onClicked: applicationLauncher.startupViewMode = "frequency"
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "La vista Frecuencia y modo muestra solo esos dos datos. Se aplicará al próximo arranque."
                                            color: "#aab4b9"
                                            font.pixelSize: 10
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 150
                                    color: "#171a1c"

                                    ColumnLayout {
                                        id: qrzSettingsLayout
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8
                                        property bool qrzShowApiKey: false

                                        Text {
                                            Layout.fillWidth: true
                                            text: "QRZ LOGBOOK"
                                            color: "#e5e9ec"
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            TextField {
                                                id: qrzApiKeyField
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 34
                                                placeholderText: "Clave API del logbook QRZ"
                                                echoMode: qrzSettingsLayout.qrzShowApiKey
                                                          ? TextInput.Normal
                                                          : TextInput.Password
                                                selectByMouse: true
                                                text: qrzLogbook.apiKey
                                                onAccepted: qrzLogbook.saveApiKey(text.trim())
                                            }

                                            PanelButton {
                                                Layout.preferredWidth: 90
                                                Layout.preferredHeight: 34
                                                text: qrzSettingsLayout.qrzShowApiKey ? "OCULTAR" : "VER"
                                                textPixelSize: 11
                                                activeColor: "#46565e"
                                                tip: qrzSettingsLayout.qrzShowApiKey
                                                     ? "Ocultar clave API"
                                                     : "Mostrar clave API"
                                                onClicked: qrzSettingsLayout.qrzShowApiKey = !qrzSettingsLayout.qrzShowApiKey
                                            }

                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            PanelButton {
                                                Layout.preferredWidth: 170
                                                Layout.preferredHeight: 32
                                                text: "GUARDAR Y ACTUALIZAR"
                                                activeColor: "#3d7650"
                                                onClicked: {
                                                    if (qrzLogbook.saveApiKey(qrzApiKeyField.text.trim()))
                                                        qrzLogbook.refresh()
                                                }
                                            }

                                            PanelButton {
                                                Layout.preferredWidth: 110
                                                Layout.preferredHeight: 32
                                                text: "BORRAR CLAVE"
                                                activeColor: "#8c463e"
                                                enabled: qrzLogbook.configured
                                                onClicked: {
                                                    qrzLogbook.clearApiKey()
                                                    qrzApiKeyField.clear()
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: qrzLogbook.status
                                                color: qrzLogbook.configured ? "#9edcf4" : "#aab4b9"
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "La clave QRZ concede acceso de escritura. El cliente solo consulta STATUS y FETCH; se guarda en la configuración local del usuario."
                                            color: "#d1b77d"
                                            font.pixelSize: 9
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth

                            ColumnLayout {
                                width: parent.width
                                spacing: 10

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 176
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: "FUENTE DE VÍDEO"
                                            color: "#e5e9ec"
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        ComboBox {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            model: videoCapture.devices
                                            currentIndex: Math.max(0, model.indexOf(videoCapture.selectedDevice))
                                            onActivated: videoCapture.selectedDevice = currentText
                                            enabled: model.length > 0
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: videoCapture.status
                                            color: "#aab4b9"
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                FrameBox {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 132
                                    color: "#171a1c"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: "MODO DE VISUALIZACIÓN"
                                            color: "#e5e9ec"
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                text: "SOLO SCOPE"
                                                selected: videoCapture.scopeOnly
                                                activeColor: "#3f6e82"
                                                onClicked: videoCapture.scopeOnly = true
                                            }
                                            PanelButton {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                text: "PANTALLA COMPLETA"
                                                selected: !videoCapture.scopeOnly
                                                activeColor: "#3f6e82"
                                                onClicked: videoCapture.scopeOnly = false
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "La selección se guarda para el próximo inicio."
                                            color: "#aab4b9"
                                            font.pixelSize: 10
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

    Popup {
        id: generalLogPopup
        parent: Overlay.overlay
        modal: false
        focus: true
        width: Math.min(980, window.width - 40)
        height: Math.min(540, window.height - 100)
        x: 20
        y: 74
        closePolicy: Popup.CloseOnEscape
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
                    popupTarget: generalLogPopup
                    title: "REGISTRO GENERAL"
                    textColor: "#e3f6ff"
                    pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: ["TODOS", "ICOM", "QUANSHENG", "TONOS", "REGISTROS", "EEPROM"]
                    PanelButton {
                        required property string modelData
                        Layout.preferredWidth:
                            modelData === "QUANSHENG"
                            ? 92
                            : modelData === "REGISTROS"
                              ? 84
                              : modelData === "TODOS"
                                ? 64
                                : 70
                        text: modelData
                        selected: generalLogFilter === modelData
                        onClicked: generalLogFilter = modelData
                    }
                }
                PanelButton {
                    Layout.preferredWidth: 68
                    text: "Copiar"
                    tip: "Copia el registro visible al portapapeles."
                    onClicked: radioController.copyTextToClipboard(visibleGeneralLog(), "Registro general")
                }
                PanelButton {
                    Layout.preferredWidth: 68
                    text: "Borrar"
                    tip: "Borra el registro general."
                    onClicked: generalLogText = ""
                }
                PanelButton {
                    Layout.preferredWidth: 68
                    text: "Cerrar"
                    onClicked: generalLogPopup.close()
                }
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                TextArea {
                    id: generalLogArea
                    width: Math.max(parent.availableWidth, implicitWidth)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.NoWrap
                    text: visibleGeneralLog()
                    padding: 6
                    color: "#d9f0ff"
                    selectionColor: "#315d72"
                    selectedTextColor: "#ffffff"
                    font.family: "DejaVu Sans Mono"
                    font.pixelSize: 9
                    background: Rectangle { color: "#050707" }
                    onTextChanged: {
                        cursorPosition = length
                        Qt.callLater(function() {
                            var flick = generalLogArea.parent
                            if (flick && flick.contentItem)
                                flick.contentItem.contentY = Math.max(0, flick.contentItem.contentHeight - flick.height)
                        })
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
                    Layout.preferredWidth: 68
                    text: "Cerrar"
                    tip:
                        "Cierra la ventana de diagnóstico."
                    onClicked:
                        diagnosticsPopup.close()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                PanelButton {
                    Layout.preferredWidth: 92
                    text: "Log general"
                    tip: "Abre el registro general filtrable de la aplicación."
                    onClicked: generalLogPopup.open()
                }

                PanelButton {
                    Layout.preferredWidth: 78
                    text: diagnosticsPopup.trafficPaused ? "Continuar" : "Pausa"
                    selected: diagnosticsPopup.trafficPaused
                    activeColor: "#9a672e"
                    tip: diagnosticsPopup.trafficPaused
                          ? "Reanuda la actualización del historial."
                          : "Congela las tramas visibles para poder seleccionarlas y copiarlas."
                    onClicked: diagnosticsPopup.setTrafficPaused(!diagnosticsPopup.trafficPaused)
                }

                PanelButton {
                    Layout.preferredWidth: 82
                    text: diagnosticsPopup.memoryTrafficOnly ? "Solo MEM: ON" : "Solo MEM"
                    selected: diagnosticsPopup.memoryTrafficOnly
                    activeColor: "#6a4b88"
                    tip: "Muestra únicamente las tramas CI-V de memorias."
                    onClicked: diagnosticsPopup.memoryTrafficOnly = !diagnosticsPopup.memoryTrafficOnly
                }

                PanelButton {
                    Layout.preferredWidth: 76
                    text: "Copiar TX"
                    tip: "Copia las tramas TX visibles."
                    onClicked: radioController.copyTextToClipboard(diagnosticsTxArea.text, "Historial TX")
                }
                PanelButton {
                    Layout.preferredWidth: 76
                    text: "Copiar RX"
                    tip: "Copia las tramas RX visibles."
                    onClicked: radioController.copyTextToClipboard(diagnosticsRxArea.text, "Historial RX")
                }
                PanelButton {
                    Layout.preferredWidth: 84
                    text: "Copiar todo"
                    tip: "Copia conjuntamente TX y RX."
                    onClicked: radioController.copyTextToClipboard(
                        "TX:\n" + diagnosticsTxArea.text + "\n\nRX:\n" + diagnosticsRxArea.text,
                        "Diagnóstico CI-V")
                }
                PanelButton {
                    Layout.preferredWidth: 64
                    text: "Limpiar"
                    tip: "Borra el historial TX y RX."
                    onClicked: {
                        diagnosticsPopup.setTrafficPaused(false)
                        diagnosticsPopup.pausedTxHistory = ""
                        diagnosticsPopup.pausedRxHistory = ""
                        radioController.clearTrafficHistory()
                    }
                }
                Item { Layout.fillWidth: true }
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
                        id: connectionToolbarGroup
                        caption: "CONEXIÓN"
                        accentColor: "#3d9fc4"

                    ToolbarButton {
                        text: "RADIO"
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 56 : 0
                        Layout.maximumWidth: visible ? 56 : 0
                        iconName: "connect"
                        iconColor:
                            (radioController.connected || applicationLauncher.lanConnected)
                            ? "#39d871"
                            : "#49bfff"

                        onClicked: {
                            if (applicationLauncher.lanConnectionEnabled) {
                                applicationLauncher.lanConnected
                                ? applicationLauncher.disconnectLanConnection()
                                : applicationLauncher.testLanConnection()
                            } else {
                                radioController.connected
                                ? radioController.disconnectRadio()
                                : radioController.connectRadio()
                            }
                        }
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
                        text: "DIAGNÓST."
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 56 : 0
                        Layout.maximumWidth: visible ? 56 : 0
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
                        id: toolsToolbarGroup
                        caption: "HERRAMIENTAS"
                        accentColor: "#b68b45"

                    ToolbarButton {
                        text: "SCOPE"
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 45 : 0
                        Layout.maximumWidth: visible ? 45 : 0
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
                        text: "VÍDEO"
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 45 : 0
                        Layout.maximumWidth: visible ? 45 : 0
                        iconName: "video"
                        iconColor: applicationLauncher.icomVideoRunning
                                    ? "#ffd27a" : "#8f8f8f"
                        tip: applicationLauncher.icomVideoRunning
                             ? "Detener el vídeo HDMI del IC-7300MK2"
                             : "Mostrar u ocultar el vídeo HDMI dentro del panel Icom"
                        onClicked: applicationLauncher.icomVideoRunning
                                   ? applicationLauncher.stopIcomVideo()
                                   : applicationLauncher.startIcomVideo()
                    }

                    ToolbarButton {
                        text: "TX"
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 45 : 0
                        Layout.maximumWidth: visible ? 45 : 0
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
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 45 : 0
                        Layout.maximumWidth: visible ? 45 : 0
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
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: visible ? 45 : 0
                        Layout.maximumWidth: visible ? 45 : 0
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
                        id: memoriesToolbarGroup
                        caption: "MEMORIAS"
                        visible: applicationLauncher.icomPanelVisible
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: visible ? 10000 : 0
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

                    FrameBox {
                        id: qrzToolbarPanel
                        visible: applicationLauncher.icomPanelVisible
                                 && applicationLauncher.quanshengPanelVisible
                        Layout.fillWidth: true
                        Layout.minimumWidth: visible ? 360 : 0
                        Layout.preferredWidth: visible ? 400 : 0
                        Layout.maximumWidth: visible ? 10000 : 0
                        Layout.fillHeight: true
                        color: "#202629"
                        border.color: "#52636b"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7

                                Text {
                                    text: "QRZ"
                                    color: "#f0c181"
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Text {
                                    text: "QSO " + (qrzLogbook.qsoCount >= 0 ? qrzLogbook.qsoCount : "—")
                                    color: "#dce3e7"
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: "Conf. " + (qrzLogbook.confirmedCount >= 0 ? qrzLogbook.confirmedCount : "—")
                                    color: "#8fd49b"
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: "Países " + (qrzLogbook.dxccCount >= 0 ? qrzLogbook.dxccCount : "—")
                                    color: "#9edcf4"
                                    font.pixelSize: 14
                                }

                                Item { Layout.fillWidth: true }

                                PanelButton {
                                    Layout.preferredWidth: 25
                                    Layout.minimumWidth: 25
                                    Layout.preferredHeight: 21
                                    text: "↻"
                                    textPixelSize: 14
                                    activeColor: "#3f6e82"
                                    enabled: qrzLogbook.configured && !qrzLogbook.loading
                                    tip: qrzLogbook.status
                                         + " · Actualizar estadísticas y últimos QSOs."
                                    onClicked: qrzLogbook.refresh()
                                }
                            }

                            RowLayout {
                                id: qrzToolbarRecentRow
                                Layout.fillWidth: true
                                spacing: 7
                                visible: qrzLogbook.recentQsos.length > 0

                                Repeater {
                                    model: qrzLogbook.recentQsos

                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 4

                                        Text {
                                            text: modelData.call || "—"
                                            color: "#ffffff"
                                            font.pixelSize: 12
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: [modelData.band, modelData.mode, modelData.time]
                                                  .filter(function(part) { return !!part })
                                                  .join(" ")
                                            color: "#aebbc1"
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                HoverHandler { id: qrzToolbarRecentHover }
                                ToolTip.text: qrzLogbook.recentSummary
                                              + " · " + qrzLogbook.status
                                ToolTip.visible: qrzToolbarRecentHover.hovered
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                visible: qrzLogbook.recentQsos.length === 0
                                text: qrzLogbook.configured
                                      ? qrzLogbook.status
                                      : "Configura la clave QRZ en Configuración"
                                color: qrzLogbook.status.startsWith("QRZ:") ? "#ef9a9a" : "#d4dade"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    ToolbarGroup {
                        id: generalToolbarGroup
                        caption: "GENERAL"
                        accentColor: "#8a8e62"

                    ToolbarButton {
                        text: "CONFIG"
                        Layout.preferredWidth: 55
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
                        text: "COMPACTO"
                        iconName: "settings"
                        iconColor: compactVisible ? "#ffd36b" : "#8f8f8f"
                        tip: "Abre la vista compacta para mantener los controles esenciales accesibles."
                        onClicked: setCompactMode(true)
                    }

                    ToolbarButton {
                        text: "FREC."
                        iconName: "settings"
                        iconColor: superCompactVisible ? "#ffd36b" : "#8f8f8f"
                        tip: "Muestra solo frecuencia y modo."
                        onClicked: setSuperCompactMode(true)
                    }

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

                }
            }

            RowLayout {
                id: radioPanelsHost
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
            }

            Item {
                id: radioPageHost
                parent: radioPanelsHost
                visible: applicationLauncher.quanshengPanelVisible
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: visible ? 550 : 0
                Layout.minimumWidth: visible ? 520 : 0
                Layout.maximumWidth: visible ? 590 : 0
            }

            Item {
                id: icomPageHost
                parent: radioPanelsHost
                visible: applicationLauncher.icomPanelVisible
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: visible ? 900 : 0
                Layout.minimumWidth: visible ? 760 : 0
                Layout.maximumWidth: visible ? 980 : 0

                Item {
                    anchors.fill: parent
                    z: 100
                    visible: radioController.connected && radioController.transmitting

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width * 0.58, 390)
                        height: 112
                        color: "#300306"
                        border.color: "#70201b"
                        border.width: 3
                        radius: height / 2
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.88; duration: 1300 }
                            NumberAnimation { from: 0.88; to: 1.0; duration: 1300 }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -7
                            color: "transparent"
                            border.color: "#45ff2522"
                            border.width: 7
                            radius: height / 2
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            border.color: "#b93124"
                            border.width: 1
                            radius: height / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#650609" }
                                GradientStop { position: 0.22; color: "#c20b10" }
                                GradientStop { position: 0.5; color: "#ec1719" }
                                GradientStop { position: 0.78; color: "#c20b10" }
                                GradientStop { position: 1.0; color: "#650609" }
                            }
                        }

                        Text {
                            anchors.fill: parent
                            text: "ON AIR"
                            color: "#ff321d"
                            opacity: 0.72
                            scale: 1.045
                            font.family: "DejaVu Sans"
                            font.pixelSize: 50
                            font.bold: true
                            font.letterSpacing: 2
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            anchors.fill: parent
                            text: "ON AIR"
                            color: "#ffe8c3"
                            font.family: "DejaVu Sans"
                            font.pixelSize: 47
                            font.bold: true
                            font.letterSpacing: 2
                            style: Text.Outline
                            styleColor: "#ff751f"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                RowLayout {
                    id: icomBandRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 28
                    spacing: 3

                    Repeater {
                        model: bandDefinitions
                        PanelButton {
                            id: compactIcomBandButton
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitHeight: 26
                            text: modelData.name
                            textPixelSize: 10
                            tip: bandButtonHelp(index) + " · " + modelData.label
                            selected: currentBandName === modelData.name
                            activeColor: "#4a4a4a"
                            enabled: controlsEnabled()
                            contentItem: RowLayout {
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: compactIcomBandButton.enabled ? "#f1f1f1" : "#818181"
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Text {
                                    Layout.preferredWidth: 34
                                    text: modelData.label
                                    color: !compactIcomBandButton.enabled ? "#6f777b"
                                          : compactIcomBandButton.selected ? "#ffd27a" : "#69d6ff"
                                    font.pixelSize: 8
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }
                            onClicked: selectBand(index)
                        }
                    }
                }
            }

            RowLayout {
                parent: icomPageHost
                visible: applicationLauncher.icomPanelVisible
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: icomBandRow.bottom
                anchors.bottom: parent.bottom
                spacing: 6

                FrameBox {
                    id: leftOperatingPanel

                    Layout.preferredWidth: 106
                    Layout.minimumWidth: 106
                    Layout.maximumWidth: 106
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
                                && (!radioController.transmitting
                                    || radioController.pttOwned)

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

                            onPressed: radioController.setTransmit(true)

                            onReleased: radioController.setTransmit(false)

                            onCanceled: radioController.setTransmit(false)

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
                                radioController.connected

                            onClicked: radioController.startTuner()
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            text: radioController.bandText
                            color: "#f0a35b"
                            font.pixelSize: 10
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
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
                                Layout.minimumHeight: 356
                                Layout.preferredHeight: 356
                                Layout.maximumHeight: 356
                                Layout.alignment: Qt.AlignTop

                                color: "#020202"
                                border.color: "#4d4d4d"
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

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
                                        Layout.preferredHeight: 160
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
                                                        // Ancho reservado para los estados; evita que un texto largo
                                                        // desplace la rejilla de botones de modo.
                                                        Layout.preferredWidth: 145
                                                        Layout.minimumWidth: 145
                                                        Layout.maximumWidth: 145
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

                                                ColumnLayout {
                                                    anchors.top: parent.top
                                                    x: mainRadioDisplay.width
                                                       - parent.mapToItem(mainRadioDisplay, 0, 0).x
                                                       - width - 8
                                                    width: 52
                                                    height: 52
                                                    spacing: 4

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 24
                                                        Layout.minimumHeight: 24
                                                        Layout.maximumHeight: 24
                                                        text: "VFO A"
                                                        textPixelSize: 9
                                                        enabled: !radioController.vfoASelected
                                                        selected: radioController.vfoASelected
                                                        activeColor: "#36c8ff"
                                                        tip: "Selecciona el VFO A."
                                                        onClicked: {
                                                            if (applicationLauncher.lanConnected) {
                                                                applicationLauncher.selectLanVfo(0)
                                                                radioController.setSelectedVfoForLan(0)
                                                            } else {
                                                                radioController.selectVfoA()
                                                            }
                                                        }
                                                    }

                                                    PanelButton {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 24
                                                        Layout.minimumHeight: 24
                                                        Layout.maximumHeight: 24
                                                        text: "VFO B"
                                                        textPixelSize: 9
                                                        enabled: !radioController.vfoBSelected
                                                        selected: radioController.vfoBSelected
                                                        activeColor: "#ffb347"
                                                        tip: "Selecciona el VFO B."
                                                        onClicked: {
                                                            if (applicationLauncher.lanConnected) {
                                                                applicationLauncher.selectLanVfo(1)
                                                                radioController.setSelectedVfoForLan(1)
                                                            } else {
                                                                radioController.selectVfoB()
                                                            }
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
                                                    : "#9a6630"

                                                MouseArea {
                                                    anchors.fill: parent
                                                    enabled: controlsEnabled()
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var targetVfo = otherVfoNumber()
                                                        if (applicationLauncher.lanConnected) {
                                                            applicationLauncher.selectLanVfo(targetVfo)
                                                            radioController.setSelectedVfoForLan(targetVfo)
                                                        } else if (targetVfo === 0) {
                                                            radioController.selectVfoA()
                                                        } else {
                                                            radioController.selectVfoB()
                                                        }
                                                    }
                                                }

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

                                                Text {
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 8
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: 5
                                                    text:
                                                        radioController.selectedVfo === 0
                                                        ? "VFO-A"
                                                        : "VFO-B"
                                                    color:
                                                        radioController.selectedVfo === 0
                                                        ? "#36c8ff"
                                                        : "#ffb347"
                                                    font.family: "DejaVu Sans Mono"
                                                    font.pixelSize: 12
                                                    font.bold: true
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
                                                        : "#ffad4d"
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
                                                    color:
                                                        radioController.selectedVfo === 0
                                                        ? "#36c8ff"
                                                        : "#ffb347"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                }

                                            }
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: 320
                                            Layout.minimumWidth: 300
                                            Layout.maximumWidth: 340
                                            Layout.fillHeight: true
                                            spacing: 0

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 8
                                                Layout.minimumHeight: 8
                                                Layout.maximumHeight: 8
                                            }

                                            FrameBox {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 76
                                                Layout.minimumHeight: 76
                                                Layout.maximumHeight: 76
                                                color: "#070707"
                                                raised: true
                                                border.color: radioController.splitEnabled
                                                             ? "#b34f38" : "#4b4b4b"

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    enabled: controlsEnabled()
                                                    onClicked: {
                                                        if (otherVfoNumber() === 0)
                                                            applicationLauncher.lanConnected
                                                            ? (applicationLauncher.selectLanVfo(0), radioController.setSelectedVfoForLan(0))
                                                            : radioController.selectVfoA()
                                                        else
                                                            applicationLauncher.lanConnected
                                                            ? (applicationLauncher.selectLanVfo(1), radioController.setSelectedVfoForLan(1))
                                                            : radioController.selectVfoB()
                                                    }
                                                    cursorShape: Qt.PointingHandCursor
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: 450
                                                    ToolTip.timeout: 8000
                                                    ToolTip.text: "Selecciona el VFO alternativo."
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    spacing: 0

                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 12
                                                        text: "VFO "
                                                              + (otherVfoNumber() === 0 ? "A" : "B")
                                                              + (radioController.splitEnabled ? " · SPLIT" : " · SUB")
                                                              + " · " + otherVfoModeText()
                                                              + " " + otherVfoFilterText()
                                                              + " " + otherVfoDataText()
                                                        color: radioController.splitEnabled ? "#e5a278" : "#c9d1d5"
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        elide: Text.ElideRight
                                                    }

                                                    FrequencyDigits {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 43
                                                        vfoNumber: otherVfoNumber()
                                                        frequencyValue: otherVfoFrequencyText()
                                                        large: false
                                                        active: false
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 10
                                                        text: "TX real " + radioController.txFrequencyText
                                                        color: radioController.transmitting ? "#e5a278" : "#777777"
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        horizontalAlignment: Text.AlignRight
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.minimumHeight: 116
                                        Layout.preferredHeight: 140
                                        spacing: 8

                                        AnalogSMeter {
                                            Layout.preferredWidth: 155
                                            Layout.minimumWidth: 145
                                            Layout.maximumWidth: 160
                                            Layout.minimumHeight: 104
                                            Layout.preferredHeight: 104
                                            Layout.maximumHeight: 104
                                            Layout.alignment: Qt.AlignVCenter
                                            meterPercent: radioController.sMeterPercent
                                            valueText: radioController.sMeterText
                                        }

                                        ColumnLayout {
                                            Layout.preferredWidth: 235
                                            Layout.minimumWidth: 215
                                            Layout.maximumWidth: 250
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Item { Layout.preferredWidth: 34 }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "1  3  5  7  9  +20  +40  +60 dB"
                                                    color: "#9fa7ad"
                                                    font.pixelSize: 8
                                                    font.family: "DejaVu Sans Mono"
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                                Item { Layout.preferredWidth: 52 }
                                            }

                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "S"
                                                valueText: radioController.sMeterText
                                                percent: radioController.sMeterPercent
                                                multicolor: true
                                                valueRightMargin: 30
                                            }
                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "PO"
                                                valueText: radioController.powerMeterText
                                                percent: radioController.powerMeterPercent
                                                barColor: "#42b7ff"
                                                valueRightMargin: 30
                                            }
                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "ALC"
                                                valueText: radioController.alcMeterText
                                                percent: radioController.alcMeterPercent
                                                barColor: "#aaaaaa"
                                                valueRightMargin: 30
                                            }
                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "COMP"
                                                valueText: radioController.compMeterText
                                                percent: radioController.compMeterPercent
                                                barColor: "#aaaaaa"
                                                valueRightMargin: 30
                                            }
                                            MeterLine {
                                                Layout.fillWidth: true
                                                caption: "SWR"
                                                valueText: radioController.swrMeterText
                                                percent: radioController.swrMeterPercent
                                                barColor: "#aaaaaa"
                                                valueRightMargin: 30
                                            }

                                            Text {
                                                Layout.topMargin: 2
                                                text: "NOTCH: "
                                                      + (radioController.manualNotchEnabled
                                                         ? "MANUAL"
                                                         : radioController.autoNotchEnabled
                                                           ? "AUTO" : "OFF")
                                                      + "    Vd / Id: "
                                                      + radioController.voltageMeterText
                                                      + " / "
                                                      + radioController.currentMeterText
                                                color: "#c5c5c5"
                                                font.pixelSize: 9
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                        }

                                        Item {
                                            Layout.preferredWidth: 350
                                            Layout.minimumWidth: 330
                                            Layout.maximumWidth: 370
                                            Layout.fillHeight: true
                                            Layout.minimumHeight: 126
                                            Layout.alignment: Qt.AlignVCenter
                                            clip: false

                                            FrameBox {
                                                anchors.left: parent.left
                                                anchors.leftMargin: -35
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.topMargin: -43
                                                anchors.bottom: parent.bottom
                                                anchors.bottomMargin: 0
                                                color: "#090a0b"
                                                border.color: "#555b60"
                                                clip: true

                                                Item {
                                                    anchors.fill: parent
                                                    anchors.margins: 3
                                                    clip: true

                                                    VideoFrameItem {
                                                        id: inlineVideoFrameItem
                                                        anchors.fill: parent
                                                        controller: videoCapture
                                                        scopeOnly: videoCapture.scopeOnly
                                                        visible: !window.videoDetached
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        visible: !window.videoDetached
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: videoCapture.scopeOnly = !videoCapture.scopeOnly
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        width: parent.width - 8
                                                        visible: !window.videoDetached
                                                                 && videoCapture.frameRevision === 0
                                                        text: videoCapture.status
                                                        color: "#aab2b8"
                                                        font.pixelSize: 9
                                                        horizontalAlignment: Text.AlignHCenter
                                                        wrapMode: Text.Wrap
                                                    }
                                                }

                                                PanelButton {
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 5
                                                    anchors.topMargin: 20
                                                    width: 74
                                                    height: 22
                                                    text: "ABRIR ↗"
                                                    textPixelSize: 9
                                                    activeColor: "#347e98"
                                                    tip: "Desacopla el vídeo en una ventana independiente."
                                                    visible: !window.videoDetached
                                                    onClicked: window.detachVideoWindow()
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    anchors.margins: 3
                                                    visible: window.videoDetached
                                                    color: "#d5090a0b"

                                                    Column {
                                                        anchors.centerIn: parent
                                                        spacing: 6

                                                        Text {
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            text: "VÍDEO EN VENTANA INDEPENDIENTE"
                                                            color: "#c8d0d4"
                                                            font.pixelSize: 10
                                                            font.bold: true
                                                        }

                                                        PanelButton {
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            width: 92
                                                            height: 25
                                                            text: "ACOPLAR"
                                                            textPixelSize: 9
                                                            activeColor: "#347e98"
                                                            tip: "Devuelve el vídeo al panel Icom."
                                                            onClicked: window.videoDetached = false
                                                        }
                                                    }
                                                }
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
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.setLanSplitEnabled(
                                                        !radioController.splitEnabled)
                                                    : radioController.setSplitEnabled(
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
                                                    {
                                                        if (applicationLauncher.lanConnected)
                                                            applicationLauncher.exchangeLanVfos()
                                                        else
                                                            radioController.exchangeVfos()
                                                        radioController.setSelectedVfoForLan(
                                                            radioController.selectedVfo === 0 ? 1 : 0)
                                                    }
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "A=B"
                                                enabled:
                                                    controlsEnabled()

                                                onClicked:
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.equalizeLanVfos()
                                                    : radioController.equalizeVfos()
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
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.setLanRitEnabled(
                                                        !radioController.ritEnabled)
                                                    : radioController.setRitEnabled(
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
                                                    applicationLauncher.lanConnected
                                                    ? applicationLauncher.setLanDeltaTxEnabled(
                                                        !radioController.deltaTxEnabled)
                                                    : radioController.setDeltaTxEnabled(
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
                                            Layout.minimumWidth: 160
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

                            Layout.preferredWidth: 780
                            Layout.minimumWidth: 760
                            Layout.maximumWidth: 800
                            Layout.minimumHeight: 138
                            Layout.preferredHeight: 138
                            Layout.maximumHeight: 138
                            color: "#25282a"
                            border.color: "#53616a"
                            raised: true

                            GridLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                columns: 4
                                columnSpacing: 6
                                rowSpacing: 6

                                FrameBox {
                                    Layout.column: 3
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
                                                onClicked: applicationLauncher.lanConnected
                                                           ? applicationLauncher.setLanFilter(1)
                                                           : radioController.setFilter(1)
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "FIL2"
                                                selected: radioController.filterText === "FIL2"
                                                enabled: controlsEnabled()
                                                onClicked: applicationLauncher.lanConnected
                                                           ? applicationLauncher.setLanFilter(2)
                                                           : radioController.setFilter(2)
                                            }

                                            PanelButton {
                                                Layout.fillWidth: true
                                                text: "FIL3"
                                                selected: radioController.filterText === "FIL3"
                                                enabled: controlsEnabled()
                                                onClicked: applicationLauncher.lanConnected
                                                           ? applicationLauncher.setLanFilter(3)
                                                           : radioController.setFilter(3)
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
                                    Layout.column: 1
                                    Layout.preferredWidth: 240
                                    Layout.minimumWidth: 240
                                    Layout.maximumWidth: 240
                                    Layout.fillHeight: true
                                    color: "#191c1e"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 4

                                        TwinPbtControl {
                                            Layout.fillWidth: false
                                            Layout.minimumWidth: 170
                                            Layout.preferredWidth: 170
                                            Layout.maximumWidth: 170
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
                                    Layout.column: 2
                                    Layout.preferredWidth: 176
                                    Layout.minimumWidth: 176
                                    Layout.maximumWidth: 176
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
                                                Layout.minimumWidth: 80
                                                Layout.preferredWidth: 80
                                                Layout.maximumWidth: 80
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
                                                Layout.preferredWidth: 80
                                                Layout.minimumWidth: 80
                                                Layout.maximumWidth: 80
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
                                FrameBox {
                                    Layout.column: 0
                                    Layout.preferredWidth: 170
                                    Layout.minimumWidth: 160
                                    Layout.maximumWidth: 180
                                    Layout.fillHeight: true
                                    color: "#191c1e"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: "AUDIO / SQL"
                                            color: "#ededed"
                                            font.pixelSize: 9
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 3

                                            KnobControl {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                compact: true
                                                caption: "AF"
                                                currentValue: radioController.afGain
                                                accentColor: "#69d0ff"
                                                applyFunction: function(value) {
                                                    radioController.setAfGain(value)
                                                }
                                            }
                                            KnobControl {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                compact: true
                                                caption: "SQL"
                                                currentValue: radioController.squelch
                                                accentColor: "#80d8c8"
                                                applyFunction: function(value) {
                                                    radioController.setSquelch(value)
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

                            visible: false
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
                                            required property int index
                                            required property var modelData

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

                visible: applicationLauncher.icomPanelVisible
                         || applicationLauncher.quanshengPanelVisible
                Layout.fillWidth: true
                Layout.minimumHeight: 32
                Layout.preferredHeight: 32
                Layout.maximumHeight: 32
                color: "#171a1c"
                border.color: "#50595e"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    RowLayout {
                        visible: applicationLauncher.icomPanelVisible
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 6

                        Text {
                            text: radioController.connected ? "ICOM OK" : "ICOM OFF"
                            color: radioController.connected ? "#8fd49b" : "#ef9a9a"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Text {
                            text: radioController.txRxText
                            color: radioController.transmitting ? "#ff8d8d" : "#8ff09d"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Text {
                            text: radioController.memoryModeActive
                                  ? radioController.selectedMemoryChannelText
                                  : radioController.vfoText
                            color: "#9edcf4"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: radioController.actionStatus || radioController.status
                            color: "#d4dade"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "STEP " + stepNames[stepIndex]
                            color: "#72d1ff"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Text {
                            text: radioController.overflow ? "OVF OVER" : "OVF OK"
                            color: radioController.overflow ? "#ff8585" : "#8fd49b"
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    Rectangle {
                        visible: applicationLauncher.icomPanelVisible
                                 && applicationLauncher.quanshengPanelVisible
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 7
                        Layout.bottomMargin: 7
                        color: "#4e575c"
                    }

                    RowLayout {
                        visible: applicationLauncher.quanshengPanelVisible
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 6

                        Text {
                            text: quanshengClient.connected ? "QUANSHENG OK" : "QUANSHENG OFF"
                            color: quanshengClient.connected ? "#8fd49b" : "#ef9a9a"
                            font.pixelSize: 10
                            font.bold: true
                        }

                        Text {
                            readonly property string portState: quanshengClient.serialPortState
                            readonly property string stateLabel:
                                portState === "open" ? "SERIE OK"
                                : portState === "busy" ? "SERIE OCUPADA"
                                : portState === "reconnecting" ? "SERIE RECONECTANDO"
                                : portState === "error" ? "SERIE ERROR"
                                : portState === "closed" ? "SERIE CERRADA"
                                : portState === "not_applicable" ? "SIN SERIE"
                                : "SERIE ?"
                            text: stateLabel
                                  + (quanshengClient.serialPortDevice
                                     ? " · " + quanshengClient.serialPortDevice : "")
                                  + (quanshengClient.serialPortUpdatedAt
                                     ? " · " + quanshengClient.serialPortUpdatedAt : "")
                                  + (quanshengClient.serialPortError
                                     ? " · " + quanshengClient.serialPortError : "")
                            color: portState === "open" ? "#8fd49b"
                                   : portState === "reconnecting" ? "#e5c07b"
                                   : portState === "busy" || portState === "error" ? "#ef9a9a"
                                   : "#c5cdd1"
                            font.pixelSize: 10
                            font.bold: portState === "busy" || portState === "error"
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 205
                        }

                        Text {
                            Layout.fillWidth: true
                            text: quanshengClient.eventStreamStalled
                                  ? "SIN EVENTOS · " + quanshengClient.eventSilenceSeconds + " s"
                                  : ((quanshengClient.frequencyControlStatus
                                      && quanshengClient.frequencyControlStatus !== "No disponible")
                                     ? quanshengClient.frequencyControlStatus
                                     : quanshengClient.sourceStatus)
                            color: quanshengClient.eventStreamStalled
                                   ? "#ff6b6b"
                                   : (quanshengClient.connected ? "#d4dade" : "#e5c07b")
                            font.pixelSize: 10
                            font.bold: quanshengClient.eventStreamStalled
                            elide: Text.ElideRight
                        }
                    }

                    CheckBox {
                        id: statusIcomPanelToggle
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 24
                        text: "IC"
                        checked: applicationLauncher.icomPanelVisible
                        enabled: applicationLauncher.quanshengPanelVisible
                        onToggled: applicationLauncher.icomPanelVisible = checked
                        palette.text: "#d5dde0"
                        indicator: Rectangle {
                            implicitWidth: 16
                            implicitHeight: 16
                            x: 0
                            y: (parent.height - height) / 2
                            radius: 3
                            color: parent.checked ? "#287a55" : "#111719"
                            border.width: 1
                            border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.bold: true
                                visible: statusIcomPanelToggle.checked
                            }
                        }
                        contentItem: Text {
                            text: statusIcomPanelToggle.text
                            color: statusIcomPanelToggle.enabled ? "#d5dde0" : "#778186"
                            font.pixelSize: 10
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 21
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Mostrar u ocultar el panel Icom"
                    }

                    CheckBox {
                        id: statusQuanshengPanelToggle
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 24
                        text: "QS"
                        checked: applicationLauncher.quanshengPanelVisible
                        enabled: applicationLauncher.icomPanelVisible
                        onToggled: applicationLauncher.quanshengPanelVisible = checked
                        palette.text: "#d5dde0"
                        indicator: Rectangle {
                            implicitWidth: 16
                            implicitHeight: 16
                            x: 0
                            y: (parent.height - height) / 2
                            radius: 3
                            color: parent.checked ? "#287a55" : "#111719"
                            border.width: 1
                            border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                color: "#ffffff"
                                font.pixelSize: 12
                                font.bold: true
                                visible: statusQuanshengPanelToggle.checked
                            }
                        }
                        contentItem: Text {
                            text: statusQuanshengPanelToggle.text
                            color: statusQuanshengPanelToggle.enabled ? "#d5dde0" : "#778186"
                            font.pixelSize: 10
                            font.bold: true
                            verticalAlignment: Text.AlignVCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 21
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "Mostrar u ocultar el panel Quansheng"
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
                            palette.text: "#f5f7f8"
                            onToggled:
                                remoteServer.setAutoStart(
                                    checked
                                )
                            indicator: Rectangle {
                                implicitWidth: 18
                                implicitHeight: 18
                                x: 0
                                y: (parent.height - height) / 2
                                radius: 3
                                color: parent.checked ? "#287a55" : "#111719"
                                border.width: 1
                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    font.bold: true
                                    visible: remoteAutoStartCheck.checked
                                }
                            }

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
                                    "bold 11px 'DejaVu Sans'"
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
                                        "bold 18px 'DejaVu Sans'"
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
                                        "bold 15px 'DejaVu Sans'"
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
                                        "bold 15px 'DejaVu Sans'"
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
                                    "bold 13px 'DejaVu Sans'"
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
            Math.min(window.height, Screen.desktopAvailableHeight)
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

        onXChanged: {
            if (visible)
                memoryQuickWindowPositionSaveTimer.restart()
        }
        onYChanged: {
            if (visible)
                memoryQuickWindowPositionSaveTimer.restart()
        }

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
                memoryQuickWindow.selectedRecord

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
            if (window.applicationClosing) {
                close.accepted = true
                return
            }
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

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.SizeAllCursor
                        onPressed: memoryQuickWindow.startSystemMove()
                    }

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
                                            memoryQuickWindow.selectedRecord.loaded
                                            ? memoryQuickWindow.selectedRecord.blank
                                              ? "CANAL VACÍO"
                                              : memoryQuickWindow.selectedRecord.name.length > 0
                                                ? memoryQuickWindow.selectedRecord.name
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
                                    !memoryQuickWindow.selectedRecord.loaded
                                    || memoryQuickWindow.selectedRecord.blank
                                Layout.fillWidth: true
                                text:
                                    memoryQuickWindow.selectedRecord.loaded
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
                                            indicator: Rectangle {
                                                implicitWidth: 18
                                                implicitHeight: 18
                                                x: 0
                                                y: (parent.height - height) / 2
                                                radius: 3
                                                color: parent.checked ? "#287a55" : "#111719"
                                                border.width: 1
                                                border.color: parent.checked ? "#7bd9a5" : "#a1b0b5"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    visible: quickMemorySplitCheck.checked
                                                }
                                            }

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
                                        && memoryQuickWindow.selectedRecord.loaded
                                        && !memoryQuickWindow.selectedRecord.blank
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
                                        && memoryQuickWindow.selectedRecord.loaded
                                        && !memoryQuickWindow.selectedRecord.blank

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
                                        && memoryQuickWindow.selectedRecord.loaded
                                        && !memoryQuickWindow.selectedRecord.blank

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
                    Layout.preferredHeight: 208
                    Layout.minimumHeight: 208
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
                                selected: true
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
                    Layout.preferredHeight: 140
                    Layout.minimumHeight: 140
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
                    Layout.preferredHeight: 112
                    Layout.minimumHeight: 112
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
