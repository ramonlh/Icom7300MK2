import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Window {
    id: trainerWindow

    width: 1240
    height: 790
    minimumWidth: 1000
    minimumHeight: 680
    color: "#101315"
    title: "Entrenador Morse · IC-7300MK2"
    flags: Qt.Tool

    property bool safePractice: true
    property bool dummyLoadConfirmed: false

    // Control común para las modalidades de manipulación y recepción.
    // Al desactivarlo, la velocidad efectiva coincide con la de carácter.
    // Al activarlo de nuevo, se recupera el último valor Farnsworth usado.
    property bool farnsworthEnabled:
        morseTrainer.effectiveWpm < morseTrainer.characterWpm
    property int savedFarnsworthWpm:
        Math.max(5, Math.min(morseTrainer.effectiveWpm,
                             morseTrainer.characterWpm - 1))

    // Tabla completa admitida por el entrenador. El panel lateral usa la
    // velocidad de carácter y el tono configurados en ese momento.
    property var morseReferenceSymbols: [
        { "symbol": "A", "code": "·−" },
        { "symbol": "B", "code": "−···" },
        { "symbol": "C", "code": "−·−·" },
        { "symbol": "D", "code": "−··" },
        { "symbol": "E", "code": "·" },
        { "symbol": "F", "code": "··−·" },
        { "symbol": "G", "code": "−−·" },
        { "symbol": "H", "code": "····" },
        { "symbol": "I", "code": "··" },
        { "symbol": "J", "code": "·−−−" },
        { "symbol": "K", "code": "−·−" },
        { "symbol": "L", "code": "·−··" },
        { "symbol": "M", "code": "−−" },
        { "symbol": "N", "code": "−·" },
        { "symbol": "O", "code": "−−−" },
        { "symbol": "P", "code": "·−−·" },
        { "symbol": "Q", "code": "−−·−" },
        { "symbol": "R", "code": "·−·" },
        { "symbol": "S", "code": "···" },
        { "symbol": "T", "code": "−" },
        { "symbol": "U", "code": "··−" },
        { "symbol": "V", "code": "···−" },
        { "symbol": "W", "code": "·−−" },
        { "symbol": "X", "code": "−··−" },
        { "symbol": "Y", "code": "−·−−" },
        { "symbol": "Z", "code": "−−··" },
        { "symbol": "0", "code": "−−−−−" },
        { "symbol": "1", "code": "·−−−−" },
        { "symbol": "2", "code": "··−−−" },
        { "symbol": "3", "code": "···−−" },
        { "symbol": "4", "code": "····−" },
        { "symbol": "5", "code": "·····" },
        { "symbol": "6", "code": "−····" },
        { "symbol": "7", "code": "−−···" },
        { "symbol": "8", "code": "−−−··" },
        { "symbol": "9", "code": "−−−−·" },
        { "symbol": ".", "code": "·−·−·−" },
        { "symbol": ",", "code": "−−··−−" },
        { "symbol": "?", "code": "··−−··" },
        { "symbol": "/", "code": "−··−·" },
        { "symbol": "=", "code": "−···−" },
        { "symbol": "Á", "code": "·−−·−" },
        { "symbol": "É", "code": "··−··" },
        { "symbol": "Ñ", "code": "−−·−−" }
    ]

    function setFarnsworthEnabled(enabled) {
        if (enabled) {
            farnsworthEnabled = true
            const restoredWpm = Math.max(
                        5,
                        Math.min(savedFarnsworthWpm,
                                 morseTrainer.characterWpm - 1))
            morseTrainer.effectiveWpm = restoredWpm
        } else {
            if (morseTrainer.effectiveWpm < morseTrainer.characterWpm)
                savedFarnsworthWpm = morseTrainer.effectiveWpm

            farnsworthEnabled = false
            morseTrainer.effectiveWpm = morseTrainer.characterWpm
        }
    }

    function setCharacterSpeed(wpm) {
        morseTrainer.characterWpm = wpm

        if (!farnsworthEnabled) {
            morseTrainer.effectiveWpm = wpm
        } else if (morseTrainer.effectiveWpm >= wpm) {
            const adjustedWpm = Math.max(
                        5,
                        Math.min(savedFarnsworthWpm, wpm - 1))
            morseTrainer.effectiveWpm = adjustedWpm
            savedFarnsworthWpm = adjustedWpm
        }
    }

    function setEffectiveSpeed(wpm) {
        morseTrainer.effectiveWpm = wpm
        if (wpm < morseTrainer.characterWpm) {
            savedFarnsworthWpm = wpm
            farnsworthEnabled = true
        } else {
            farnsworthEnabled = false
        }
    }

    // Instantánea del estado real de la radio antes de preparar el entrenador.
    property bool radioSettingsSaved: false
    property string savedModeText: "USB"
    property bool savedDataMode: false
    property int savedFilterNumber: 1
    property int savedRfPower: 0
    property int savedBreakInMode: 0
    property int savedCwPitchHz: 600
    property int savedCwSpeedWpm: 20

    // Cola secuencial: RadioController solo admite una escritura CI-V protegida
    // cada vez. De este modo ninguna orden de preparar/restaurar se pierde.
    property var radioOperationQueue: []
    property int radioOperationIndex: 0
    property string radioOperationName: ""
    property bool restoreRequested: false
    property string radioPreparationStatus:
        "Pulse PREPARAR RADIO para guardar el estado actual y configurar la práctica."

    function filterNumberFromText(filterText) {
        const match = String(filterText).match(/[123]/)
        return match ? Number(match[0]) : 1
    }

    function saveRadioSettingsOnce() {
        if (radioSettingsSaved || !radioController.connected)
            return

        savedModeText = radioController.modeText
        savedDataMode = radioController.dataMode
        savedFilterNumber = filterNumberFromText(radioController.filterText)
        savedRfPower = radioController.rfPower
        savedBreakInMode = radioController.breakInMode
        savedCwPitchHz = radioController.cwPitchHz
        savedCwSpeedWpm = radioController.cwKeySpeedWpm
        radioSettingsSaved = true
    }

    function executeRadioOperation(operation) {
        switch (operation.action) {
        case "mode":
            radioController.setOperatingMode(operation.value)
            break
        case "modeState":
            radioController.setOperatingModeState(
                        operation.mode,
                        operation.data,
                        operation.filter)
            break
        case "data":
            radioController.setDataEnabled(operation.value)
            break
        case "filter":
            radioController.setFilter(operation.value)
            break
        case "rfPower":
            radioController.setRfPower(operation.value)
            break
        case "breakIn":
            radioController.setBreakInMode(operation.value)
            break
        case "cwPitch":
            radioController.setCwPitchHz(operation.value)
            break
        case "cwSpeed":
            radioController.setCwKeySpeedWpm(operation.value)
            break
        }
    }

    function finishRadioOperation() {
        const completedOperation = radioOperationName
        radioOperationName = ""
        radioOperationQueue = []
        radioOperationIndex = 0

        if (completedOperation === "prepare") {
            radioPreparationStatus = safePractice
                    ? "RADIO PREPARADA: CW, BK-IN OFF; el estado anterior se restaurará al cerrar."
                    : "RADIO PREPARADA: BK-IN SEMI y RF POWER 1 %; el estado anterior se restaurará al cerrar."
        } else if (completedOperation === "restore") {
            radioSettingsSaved = false
            restoreRequested = false
            radioPreparationStatus =
                    "Estado anterior de la radio restaurado correctamente."
        }
    }

    function runNextRadioOperation() {
        if (radioOperationName.length === 0)
            return

        if (!radioController.connected) {
            radioPreparationStatus = radioOperationName === "restore"
                    ? "Restauración pendiente: la radio está desconectada."
                    : "Preparación detenida: la radio está desconectada."
            return
        }

        if (radioController.busy)
            return

        // No se modifican ajustes mientras la radio está transmitiendo.
        if (radioController.transmitting) {
            radioPreparationStatus =
                    "Esperando a que la radio vuelva a RX para continuar."
            return
        }

        if (radioOperationIndex >= radioOperationQueue.length) {
            finishRadioOperation()
            return
        }

        const operation = radioOperationQueue[radioOperationIndex]
        radioOperationIndex += 1
        executeRadioOperation(operation)

        // Si una orden no necesitó activar BUSY, continúa sin bloquear la cola.
        Qt.callLater(runNextRadioOperation)
    }

    function beginRadioOperation(name, operations) {
        radioOperationName = name
        radioOperationQueue = operations
        radioOperationIndex = 0
        Qt.callLater(runNextRadioOperation)
    }

    function prepareRadio() {
        if (!radioController.connected) {
            radioPreparationStatus =
                    "Conecte primero la radio mediante CI-V."
            return
        }

        if (radioOperationName === "restore") {
            radioPreparationStatus =
                    "Espere a que termine la restauración de la radio."
            return
        }

        saveRadioSettingsOnce()
        restoreRequested = false

        const operations = [
            { "action": "mode", "value": "CW" },
            { "action": "cwPitch", "value": morseTrainer.toneFrequencyHz },
            { "action": "cwSpeed", "value": morseTrainer.characterWpm }
        ]

        if (safePractice) {
            operations.push({ "action": "breakIn", "value": 0 })
            radioPreparationStatus =
                    "Preparando práctica segura y guardando el estado anterior…"
        } else {
            operations.push({ "action": "rfPower", "value": 1 })
            operations.push({ "action": "breakIn", "value": 1 })
            radioPreparationStatus =
                    "Preparando RF mínima y guardando el estado anterior…"
        }

        beginRadioOperation("prepare", operations)
    }

    function restoreRadioState() {
        morseTrainer.stopReceptionPlayback()
        morseTrainer.stopCapture()

        if (!radioSettingsSaved || restoreRequested)
            return

        restoreRequested = true
        radioPreparationStatus = "Restaurando el estado anterior de la radio…"

        const operations = [
            { "action": "rfPower", "value": savedRfPower },
            { "action": "cwPitch", "value": savedCwPitchHz },
            { "action": "cwSpeed", "value": savedCwSpeedWpm },
            { "action": "breakIn", "value": savedBreakInMode },
            {
                "action": "modeState",
                "mode": savedModeText,
                "data": savedDataMode,
                "filter": savedFilterNumber
            }
        ]

        // Si se cierra durante PREPARAR RADIO, se descartan las órdenes que aún
        // no se habían enviado y se restaura desde la instantánea original.
        beginRadioOperation("restore", operations)
    }

    onVisibleChanged: {
        if (visible) {
            morseTrainer.refreshAudioInputs()
            if (!radioSettingsSaved) {
                radioPreparationStatus =
                        "Pulse PREPARAR RADIO para guardar el estado actual y configurar la práctica."
            }
        } else {
            restoreRadioState()
        }
    }

    onClosing: function(close) {
        close.accepted = false
        restoreRadioState()
        visible = false
    }

    Connections {
        target: radioController

        function onBusyChanged() {
            if (!radioController.busy)
                Qt.callLater(trainerWindow.runNextRadioOperation)
        }

        function onTransmittingChanged() {
            if (trainerWindow.visible
                    && trainerWindow.safePractice
                    && radioController.transmitting) {
                radioController.setTransmit(false)
                trainerWindow.radioPreparationStatus =
                        "TX detectado. Esperando que la radio vuelva a RX."
            } else if (!radioController.transmitting) {
                Qt.callLater(trainerWindow.runNextRadioOperation)
            }
        }

        function onConnectedChanged() {
            if (!radioController.connected) {
                trainerWindow.radioPreparationStatus =
                        trainerWindow.radioSettingsSaved
                        ? "Radio desconectada; la restauración queda pendiente."
                        : "Radio desconectada."
            } else {
                Qt.callLater(trainerWindow.runNextRadioOperation)
            }
        }
    }

    Connections {
        target: morseTrainer

        function onTrainingSettingsChanged() {
            if (trainerWindow.visible
                    && trainerWindow.radioSettingsSaved
                    && trainerWindow.radioOperationName.length === 0
                    && radioController.connected
                    && !radioController.busy) {
                radioController.setCwKeySpeedWpm(
                            morseTrainer.characterWpm)
            }
        }

        function onSettingsChanged() {
            if (trainerWindow.visible
                    && trainerWindow.radioSettingsSaved
                    && trainerWindow.radioOperationName.length === 0
                    && radioController.connected
                    && !radioController.busy) {
                radioController.setCwPitchHz(
                            morseTrainer.toneFrequencyHz)
            }
        }
    }

    component Panel: Rectangle {
        radius: 5
        color: "#1b2023"
        border.color: "#4b5961"
        border.width: 1
    }

    component SectionTitle: Text {
        color: "#eaf1f4"
        font.pixelSize: 14
        font.bold: true
    }

    component SmallLabel: Text {
        color: "#b9c4ca"
        font.pixelSize: 11
    }

    component ActionButton: Button {
        id: actionButton
        implicitHeight: 34
        implicitWidth: 100
        font.pixelSize: 11
        font.bold: true

        background: Rectangle {
            radius: 4
            color: actionButton.down
                   ? "#263d49"
                   : actionButton.checked
                     ? "#245f78"
                     : actionButton.hovered
                       ? "#304d5c"
                       : "#27343b"
            border.color: actionButton.enabled
                          ? actionButton.checked
                            ? "#72d8ff"
                            : "#63879a"
                          : "#4a5053"
        }

        contentItem: Text {
            text: actionButton.text
            color: actionButton.enabled ? "#f4f8fa" : "#777f83"
            font: actionButton.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component MorseReferencePanel: Panel {
        // Tres columnas y más anchura útil: los botones son claramente más
        // anchos sin modificar las dimensiones generales de la ventana.
        Layout.preferredWidth: 335
        Layout.minimumWidth: 325
        Layout.maximumWidth: 345
        Layout.fillHeight: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            SectionTitle {
                text: "SONIDOS MORSE"
            }

            Text {
                Layout.fillWidth: true
                text: "Pulse un símbolo · "
                      + morseTrainer.characterWpm
                      + " WPM · "
                      + morseTrainer.toneFrequencyHz
                      + " Hz"
                color: "#8edcf8"
                font.pixelSize: 9
                font.bold: true
                wrapMode: Text.WordWrap
            }

            GridLayout {
                id: referenceGrid

                // No se calcula el ancho de la celda a partir del propio
                // GridLayout: esa dependencia circular hacía que Qt usara
                // el ancho mínimo del texto. Las tres columnas comparten
                // ahora el espacio disponible de forma uniforme.
                property int cellHeight: 35

                Layout.fillWidth: true
                Layout.preferredHeight:
                    Math.ceil(trainerWindow.morseReferenceSymbols.length
                              / columns) * cellHeight
                    + (Math.ceil(trainerWindow.morseReferenceSymbols.length
                                 / columns) - 1) * rowSpacing
                Layout.minimumHeight: Layout.preferredHeight
                Layout.maximumHeight: Layout.preferredHeight
                Layout.alignment: Qt.AlignTop
                columns: 3
                rowSpacing: 2
                columnSpacing: 6

                Repeater {
                    model: trainerWindow.morseReferenceSymbols

                    Button {
                        id: referenceButton

                        Layout.fillWidth: true
                        Layout.preferredWidth: 100
                        Layout.minimumWidth: 92
                        Layout.maximumWidth: 1000
                        Layout.preferredHeight: referenceGrid.cellHeight
                        Layout.minimumHeight: referenceGrid.cellHeight
                        Layout.maximumHeight: referenceGrid.cellHeight
                        enabled: !morseTrainer.receptionPlaying
                        hoverEnabled: true

                        background: Rectangle {
                            radius: 4
                            color:
                                morseTrainer.referencePlaying
                                && morseTrainer.referenceSymbol
                                   === modelData.symbol
                                ? "#286b87"
                                : referenceButton.down
                                  ? "#304f5e"
                                  : referenceButton.hovered
                                    ? "#2b424d"
                                    : "#202b31"
                            border.color:
                                morseTrainer.referencePlaying
                                && morseTrainer.referenceSymbol
                                   === modelData.symbol
                                ? "#8ce1ff"
                                : "#526a76"
                            border.width:
                                morseTrainer.referencePlaying
                                && morseTrainer.referenceSymbol
                                   === modelData.symbol
                                ? 2 : 1
                        }

                        contentItem: Column {
                            spacing: 0

                            Text {
                                width: parent.width
                                text: modelData.symbol
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                width: parent.width
                                text: modelData.code
                                color: "#f2cd65"
                                font.family: "monospace"
                                font.pixelSize: 8
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        ToolTip.visible: hovered
                        ToolTip.delay: 350
                        ToolTip.text:
                            "Reproducir " + modelData.symbol
                            + "  " + modelData.code
                            + " a " + morseTrainer.characterWpm
                            + " WPM"

                        onClicked:
                            morseTrainer.playReferenceSymbol(
                                modelData.symbol)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Text {
                    Layout.fillWidth: true
                    text: morseTrainer.receptionPlaying
                          ? "Detenga primero el ejercicio de recepción."
                          : morseTrainer.referencePlaying
                            ? "Reproduciendo: "
                              + morseTrainer.referenceSymbol
                            : "Letras, números y signos admitidos."
                    color: morseTrainer.referencePlaying
                           ? "#7fe2a7" : "#aebbc1"
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                }

                ActionButton {
                    visible: morseTrainer.referencePlaying
                    text: "PARAR"
                    implicitWidth: 60
                    implicitHeight: 28
                    onClicked: morseTrainer.stopReferencePlayback()
                }
            }
        }
    }

    // Controles Qt con paleta oscura explícita. Evita que Fusion herede
    // texto negro o gris muy oscuro sobre los paneles negros.
    component DarkTabButton: TabButton {
        id: darkTab
        implicitHeight: 34
        font.pixelSize: 11
        font.bold: true
        palette.buttonText: "#eaf1f4"
        palette.text: "#eaf1f4"
        palette.windowText: "#eaf1f4"
        palette.highlightedText: "#ffffff"
        palette.button: "#232b2f"
        palette.highlight: "#3f7188"

        contentItem: Text {
            text: darkTab.text
            color: darkTab.checked ? "#ffffff" : "#c8d3d8"
            font: darkTab.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 4
            color: darkTab.checked
                   ? "#315365"
                   : darkTab.hovered ? "#2b3940" : "#20272b"
            border.color: darkTab.checked ? "#79bddb" : "#4b5961"
            border.width: darkTab.checked ? 2 : 1
        }
    }

    component DarkSpinBox: SpinBox {
        implicitHeight: 34
        palette.text: "#f3f7f8"
        palette.buttonText: "#f3f7f8"
        palette.windowText: "#f3f7f8"
        palette.highlightedText: "#ffffff"
        palette.base: "#111619"
        palette.alternateBase: "#1a2226"
        palette.button: "#2a363c"
        palette.highlight: "#3f7188"
        palette.mid: "#55656d"
    }

    component DarkComboBox: ComboBox {
        id: darkCombo

        implicitHeight: 36
        leftPadding: 11
        rightPadding: 34
        hoverEnabled: true

        palette.text: "#f3f7f8"
        palette.buttonText: "#f3f7f8"
        palette.windowText: "#f3f7f8"
        palette.highlightedText: "#ffffff"
        palette.base: "#111619"
        palette.alternateBase: "#1a2226"
        palette.button: "#202a2f"
        palette.highlight: "#3f7188"
        palette.mid: "#55656d"

        contentItem: Text {
            leftPadding: 0
            rightPadding: 0
            text: darkCombo.displayText
            color: darkCombo.enabled ? "#f3f7f8" : "#7f8a90"
            font: darkCombo.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        indicator: Text {
            x: darkCombo.width - width - 11
            y: (darkCombo.height - height) / 2 - 1
            text: "▼"
            color: darkCombo.enabled ? "#dce8ed" : "#758087"
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: 4
            color: darkCombo.pressed
                   ? "#30434c"
                   : darkCombo.hovered ? "#29363c" : "#202a2f"
            border.color: darkCombo.activeFocus ? "#79bddb" : "#596970"
            border.width: darkCombo.activeFocus ? 2 : 1
        }

        delegate: ItemDelegate {
            id: comboDelegate
            width: darkCombo.width
            implicitHeight: 36
            highlighted: darkCombo.highlightedIndex === index

            contentItem: Text {
                text: darkCombo.textAt(index)
                leftPadding: 9
                rightPadding: 9
                color: comboDelegate.highlighted ? "#ffffff" : "#eaf1f4"
                font: darkCombo.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            background: Rectangle {
                color: comboDelegate.highlighted
                       ? "#3f7188"
                       : comboDelegate.hovered ? "#293a42" : "#151c20"
            }
        }

        popup: Popup {
            y: darkCombo.height + 2
            width: darkCombo.width
            implicitHeight: Math.min(contentItem.implicitHeight + topPadding
                                     + bottomPadding, 280)
            padding: 1

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: darkCombo.popup.visible ? darkCombo.delegateModel : null
                currentIndex: darkCombo.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator { }
            }

            background: Rectangle {
                color: "#151c20"
                border.color: "#65777f"
                border.width: 1
                radius: 4
            }
        }
    }

    component DarkRadioButton: RadioButton {
        id: darkRadio
        palette.windowText: enabled ? "#eaf1f4" : "#7b858a"
        palette.text: enabled ? "#eaf1f4" : "#7b858a"
        palette.buttonText: enabled ? "#eaf1f4" : "#7b858a"
        palette.highlight: "#62b9dc"

        contentItem: Text {
            text: darkRadio.text
            color: darkRadio.enabled ? "#eaf1f4" : "#7b858a"
            font: darkRadio.font
            leftPadding: darkRadio.indicator.width + darkRadio.spacing
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }

    component DarkCheckBox: CheckBox {
        id: darkCheck
        palette.windowText: enabled ? "#eaf1f4" : "#7b858a"
        palette.text: enabled ? "#eaf1f4" : "#7b858a"
        palette.buttonText: enabled ? "#eaf1f4" : "#7b858a"
        palette.highlight: "#62b9dc"

        contentItem: Text {
            text: darkCheck.text
            color: darkCheck.enabled ? "#eaf1f4" : "#7b858a"
            font: darkCheck.font
            leftPadding: darkCheck.indicator.width + darkCheck.spacing
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }

    component DarkSwitch: Switch {
        id: darkSwitch
        palette.windowText: enabled ? "#eaf1f4" : "#7b858a"
        palette.text: enabled ? "#eaf1f4" : "#7b858a"
        palette.buttonText: enabled ? "#eaf1f4" : "#7b858a"
        palette.highlight: "#62b9dc"

        contentItem: Text {
            text: darkSwitch.text
            color: darkSwitch.enabled ? "#eaf1f4" : "#7b858a"
            font: darkSwitch.font
            leftPadding: darkSwitch.indicator.width + darkSwitch.spacing
            verticalAlignment: Text.AlignVCenter
        }
    }

    component MetricCard: Rectangle {
        property string caption: ""
        property string valueText: "—"
        property color accent: "#65c8ee"

        implicitHeight: 68
        radius: 5
        color: "#151a1d"
        border.color: accent
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 3

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: caption
                color: "#aebbc1"
                font.pixelSize: 10
                font.bold: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: valueText
                color: accent
                font.pixelSize: 23
                font.bold: true
            }
        }
    }

    component LevelMeter: Item {
        id: meter
        property string caption: ""
        property real levelDb: -90
        property color barColor: "#54c5ef"

        implicitHeight: 38

        ColumnLayout {
            anchors.fill: parent
            spacing: 3

            RowLayout {
                Layout.fillWidth: true

                SmallLabel {
                    text: meter.caption
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Number(meter.levelDb).toFixed(1) + " dB"
                    color: meter.barColor
                    font.family: "monospace"
                    font.pixelSize: 11
                    font.bold: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 12
                radius: 3
                color: "#080a0b"
                border.color: "#465158"

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 2
                    width: Math.max(
                               0,
                               Math.min(
                                   parent.width - 4,
                                   (parent.width - 4)
                                   * (meter.levelDb + 90.0) / 90.0
                               )
                           )
                    radius: 2
                    color: meter.barColor
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#101315"
        border.color: "#657a85"
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: 10

                Text {
                    text: "ENTRENADOR MORSE"
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.bold: true
                }

                Rectangle {
                    implicitWidth: 104
                    implicitHeight: 28
                    radius: 4
                    color: radioController.connected
                           ? "#24563d" : "#56302d"
                    border.color: radioController.connected
                                  ? "#65d49a" : "#e47b72"

                    Text {
                        anchors.centerIn: parent
                        text: radioController.connected
                              ? "RADIO ONLINE" : "SIN RADIO"
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                Rectangle {
                    implicitWidth: 88
                    implicitHeight: 28
                    radius: 4
                    color: radioController.transmitting
                           ? "#8f2828" : "#263239"
                    border.color: radioController.transmitting
                                  ? "#ff8c83" : "#63757e"

                    Text {
                        anchors.centerIn: parent
                        text: radioController.transmitting ? "TX" : "RX"
                        color: radioController.transmitting
                               ? "#ffffff" : "#a9d7e9"
                        font.pixelSize: 13
                        font.bold: true
                    }
                }

                Rectangle {
                    implicitWidth: 130
                    implicitHeight: 28
                    radius: 4
                    color: trainerWindow.safePractice
                           ? "#204d3a" : "#6c3e22"
                    border.color: trainerWindow.safePractice
                                  ? "#69d39c" : "#f0a15e"

                    Text {
                        anchors.centerIn: parent
                        text: trainerWindow.safePractice
                              ? "SIN TRANSMISIÓN" : "RF MÍNIMA 1 %"
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: "PREPARAR RADIO"
                    implicitWidth: 132
                    enabled: trainerTabs.currentIndex !== 1
                             && radioController.connected
                             && trainerWindow.radioOperationName.length === 0
                    onClicked: trainerWindow.prepareRadio()
                }

                ActionButton {
                    text: "CERRAR"
                    implicitWidth: 78
                    onClicked: trainerWindow.visible = false
                }
            }

            TabBar {
                id: trainerTabs
                Layout.fillWidth: true
                Layout.preferredHeight: 34

                DarkTabButton { text: "MANIPULACIÓN" }
                DarkTabButton { text: "RECEPCIÓN Y COPIA" }
                DarkTabButton { text: "PROGRESO Y ESTADÍSTICAS" }
                DarkTabButton { text: "CONFIGURACIÓN Y SEGURIDAD" }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: trainerTabs.currentIndex

                Item {
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        ColumnLayout {
                            Layout.preferredWidth: 300
                            Layout.minimumWidth: 280
                            Layout.maximumWidth: 325
                            Layout.fillHeight: true
                            spacing: 8

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 235

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    SectionTitle { text: "MÉTODO KOCH / FARNSWORTH" }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        rowSpacing: 6
                                        columnSpacing: 8

                                        SmallLabel { text: "Lección Koch" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 1
                                            to: morseTrainer.maximumLesson
                                            value: morseTrainer.lesson
                                            editable: true
                                            onValueModified:
                                                morseTrainer.lesson = value
                                        }

                                        SmallLabel { text: "Velocidad carácter" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 6
                                            to: 48
                                            value: morseTrainer.characterWpm
                                            editable: true
                                            textFromValue: function(value) {
                                                return value + " WPM"
                                            }
                                            valueFromText: function(text) {
                                                return parseInt(text)
                                            }
                                            onValueModified:
                                                trainerWindow.setCharacterSpeed(value)
                                        }

                                        SmallLabel { text: "Velocidad efectiva" }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            DarkSpinBox {
                                                Layout.fillWidth: true
                                                from: 5
                                                to: morseTrainer.characterWpm
                                                value: morseTrainer.effectiveWpm
                                                editable: true
                                                enabled: trainerWindow.farnsworthEnabled
                                                textFromValue: function(value) {
                                                    return value + " WPM"
                                                }
                                                valueFromText: function(text) {
                                                    return parseInt(text)
                                                }
                                                onValueModified:
                                                    trainerWindow.setEffectiveSpeed(value)
                                            }

                                            ActionButton {
                                                Layout.preferredWidth: 84
                                                implicitWidth: 84
                                                implicitHeight: 30
                                                checked: trainerWindow.farnsworthEnabled
                                                text: checked ? "FARN. ON" : "FARN. OFF"
                                                onClicked:
                                                    trainerWindow.setFarnsworthEnabled(
                                                        !trainerWindow.farnsworthEnabled)
                                            }
                                        }

                                        SmallLabel { text: "Caracteres por grupo" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 1
                                            to: 10
                                            value: morseTrainer.groupSize
                                            onValueModified:
                                                morseTrainer.groupSize = value
                                        }

                                        SmallLabel { text: "Número de grupos" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 1
                                            to: 20
                                            value: morseTrainer.exerciseGroups
                                            onValueModified:
                                                morseTrainer.exerciseGroups = value
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: trainerWindow.farnsworthEnabled
                                              ? "Farnsworth activo: caracteres rápidos con espacios ampliados."
                                              : "Espaciado normal, sin reducción Farnsworth."
                                        color: "#75d5f4"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 130

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        SectionTitle {
                                            Layout.fillWidth: true
                                            text: morseTrainer.currentLessonPassed
                                                  ? "LECCIÓN SUPERADA"
                                                  : "CARACTERES DE LA LECCIÓN"
                                            color: morseTrainer.currentLessonPassed
                                                   ? "#75e69b" : "#eaf1f4"
                                        }

                                        ActionButton {
                                            text: "RESETEAR"
                                            implicitWidth: 82
                                            implicitHeight: 27
                                            font.pixelSize: 9
                                            onClicked:
                                                resetCurrentLessonDialog.open()
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: morseTrainer.lessonCharacters
                                        color: "#f2f5f6"
                                        font.family: "monospace"
                                        font.pixelSize: 17
                                        font.bold: true
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Nuevos/refuerzo: "
                                              + morseTrainer.newestLessonCharacters
                                        color: "#f1c76a"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    SectionTitle { text: "ENTRADA DE AUDIO USB" }

                                    DarkComboBox {
                                        Layout.fillWidth: true
                                        model: morseTrainer.audioInputNames
                                        currentIndex: morseTrainer.audioInputIndex
                                        onActivated:
                                            morseTrainer.audioInputIndex = currentIndex
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ActionButton {
                                            text: "ACTUALIZAR"
                                            Layout.fillWidth: true
                                            onClicked:
                                                morseTrainer.refreshAudioInputs()
                                        }

                                        ActionButton {
                                            text: morseTrainer.capturing
                                                  ? "DETENER" : "ESCUCHAR"
                                            Layout.fillWidth: true
                                            onClicked: {
                                                if (morseTrainer.capturing)
                                                    morseTrainer.stopCapture()
                                                else
                                                    morseTrainer.startCapture()
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: morseTrainer.statusText
                                        color: morseTrainer.capturing
                                               ? "#7fe2a7" : "#b9c4ca"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }

                                    LevelMeter {
                                        Layout.fillWidth: true
                                        caption: "Nivel total"
                                        levelDb: morseTrainer.inputLevelDb
                                        barColor: "#65c8ee"
                                    }

                                    LevelMeter {
                                        Layout.fillWidth: true
                                        caption: "Tono CW detectado"
                                        levelDb: morseTrainer.toneLevelDb
                                        barColor: morseTrainer.keyDown
                                                  ? "#75e69b" : "#f0c75a"
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 620
                            Layout.preferredWidth: 850
                            Layout.fillHeight: true
                            spacing: 8

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 118

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true

                                        SectionTitle { text: "TEXTO DEL EJERCICIO" }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "Lección " + morseTrainer.lesson
                                            color: "#72d2f2"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: morseTrainer.targetText
                                        color: "#ffffff"
                                        font.family: "monospace"
                                        font.pixelSize: 25
                                        font.bold: true
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true

                                        SectionTitle { text: "MANIPULACIÓN REAL" }
                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            implicitWidth: 126
                                            implicitHeight: 30
                                            radius: 15
                                            color: morseTrainer.keyDown
                                                   ? "#287e4c" : "#252c30"
                                            border.color: morseTrainer.keyDown
                                                          ? "#87f2ae" : "#5c686e"
                                            border.width: 2

                                            Text {
                                                anchors.centerIn: parent
                                                text: morseTrainer.keyDown
                                                      ? "LLAVE CERRADA" : "LLAVE ABIERTA"
                                                color: "#ffffff"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 66
                                        radius: 5
                                        color: "#080b0d"
                                        border.color: morseTrainer.keyDown
                                                      ? "#7be3a1" : "#43515a"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8

                                            Text {
                                                text: "Código actual"
                                                color: "#9eabb1"
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: morseTrainer.currentPattern.length > 0
                                                      ? morseTrainer.currentPattern
                                                      : "· · ·"
                                                color: "#f2cd65"
                                                font.family: "monospace"
                                                font.pixelSize: 34
                                                font.bold: true
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }

                                    SmallLabel { text: "Texto decodificado" }

                                    TextArea {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        text: morseTrainer.decodedText
                                        color: "#eaf7fb"
                                        font.family: "monospace"
                                        font.pixelSize: 24
                                        font.bold: true
                                        background: Rectangle {
                                            radius: 5
                                            color: "#090d0f"
                                            border.color: "#46606c"
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ActionButton {
                                            text: "NUEVO EJERCICIO"
                                            implicitWidth: 140
                                            onClicked:
                                                morseTrainer.createExercise()
                                        }

                                        ActionButton {
                                            text: "LIMPIAR"
                                            onClicked:
                                                morseTrainer.clearAttempt()
                                        }

                                        ActionButton {
                                            text: "ESPACIO"
                                            onClicked:
                                                morseTrainer.appendWordSpace()
                                        }

                                        ActionButton {
                                            text: "BORRAR"
                                            onClicked:
                                                morseTrainer.removeLastDecodedCharacter()
                                        }

                                        Item { Layout.fillWidth: true }

                                        ActionButton {
                                            text: "FINALIZAR Y PUNTUAR"
                                            implicitWidth: 166
                                            enabled: morseTrainer.exerciseActive
                                            onClicked:
                                                morseTrainer.finishExercise()
                                        }
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 72
                                columns: 5
                                columnSpacing: 7

                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "PRECISIÓN"
                                    valueText: Number(morseTrainer.accuracy).toFixed(1) + "%"
                                    accent: "#72d2f2"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "RITMO"
                                    valueText: Number(morseTrainer.timingScore).toFixed(1) + "%"
                                    accent: "#d5b86a"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "NOTA"
                                    valueText: Number(morseTrainer.totalScore).toFixed(1)
                                    accent: morseTrainer.totalScore >= 90
                                            ? "#75e69b" : "#f0c75a"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "ACIERTOS"
                                    valueText:
                                        String(morseTrainer.correctCharacters)
                                        + " / "
                                        + String(morseTrainer.targetCharacterCount)
                                    accent: "#75e69b"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "ERRORES"
                                    valueText: String(morseTrainer.errorCount)
                                    accent: "#f08c7f"
                                }
                            }
                        }

                        MorseReferencePanel {
                            Layout.fillHeight: true
                        }
                    }
                }

                Item {
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        ColumnLayout {
                            Layout.preferredWidth: 310
                            Layout.minimumWidth: 285
                            Layout.maximumWidth: 335
                            Layout.fillHeight: true
                            spacing: 8

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 250

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    SectionTitle {
                                        text: "RECEPCIÓN KOCH / FARNSWORTH"
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        rowSpacing: 6
                                        columnSpacing: 8

                                        SmallLabel { text: "Lección Koch" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 1
                                            to: morseTrainer.maximumLesson
                                            value: morseTrainer.lesson
                                            editable: true
                                            onValueModified:
                                                morseTrainer.lesson = value
                                        }

                                        SmallLabel { text: "Velocidad carácter" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 6
                                            to: 48
                                            value: morseTrainer.characterWpm
                                            editable: true
                                            textFromValue: function(value) {
                                                return value + " WPM"
                                            }
                                            valueFromText: function(text) {
                                                return parseInt(text)
                                            }
                                            onValueModified:
                                                trainerWindow.setCharacterSpeed(value)
                                        }

                                        SmallLabel { text: "Velocidad efectiva" }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 5

                                            DarkSpinBox {
                                                Layout.fillWidth: true
                                                from: 5
                                                to: morseTrainer.characterWpm
                                                value: morseTrainer.effectiveWpm
                                                editable: true
                                                enabled: trainerWindow.farnsworthEnabled
                                                textFromValue: function(value) {
                                                    return value + " WPM"
                                                }
                                                valueFromText: function(text) {
                                                    return parseInt(text)
                                                }
                                                onValueModified:
                                                    trainerWindow.setEffectiveSpeed(value)
                                            }

                                            ActionButton {
                                                Layout.preferredWidth: 84
                                                implicitWidth: 84
                                                implicitHeight: 30
                                                checked: trainerWindow.farnsworthEnabled
                                                text: checked ? "FARN. ON" : "FARN. OFF"
                                                onClicked:
                                                    trainerWindow.setFarnsworthEnabled(
                                                        !trainerWindow.farnsworthEnabled)
                                            }
                                        }

                                        SmallLabel { text: "Caracteres por grupo" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 1
                                            to: 10
                                            value: morseTrainer.groupSize
                                            onValueModified:
                                                morseTrainer.groupSize = value
                                        }

                                        SmallLabel { text: "Número de grupos" }
                                        DarkSpinBox {
                                            Layout.fillWidth: true
                                            from: 1
                                            to: 20
                                            value: morseTrainer.exerciseGroups
                                            onValueModified:
                                                morseTrainer.exerciseGroups = value
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: trainerWindow.farnsworthEnabled
                                              ? "Farnsworth activo: caracteres rápidos y separaciones más largas."
                                              : "Espaciado Morse normal."
                                        color: "#75d5f4"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 145

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        SectionTitle {
                                            Layout.fillWidth: true
                                            text: morseTrainer.currentLessonPassed
                                                  ? "LECCIÓN SUPERADA"
                                                  : "CARACTERES ACTIVOS"
                                            color: morseTrainer.currentLessonPassed
                                                   ? "#75e69b" : "#eaf1f4"
                                        }

                                        ActionButton {
                                            text: "RESETEAR"
                                            implicitWidth: 82
                                            implicitHeight: 27
                                            font.pixelSize: 9
                                            onClicked:
                                                resetCurrentLessonDialog.open()
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: morseTrainer.lessonCharacters
                                        color: "#f2f5f6"
                                        font.family: "monospace"
                                        font.pixelSize: 17
                                        font.bold: true
                                        wrapMode: Text.Wrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Refuerzo: "
                                              + morseTrainer.newestLessonCharacters
                                        color: "#f1c76a"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    SectionTitle { text: "CÓMO SE USA" }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: "1. Pulse NUEVO Y REPRODUCIR.\n"
                                              + "2. Durante la cuenta atrás, suelte el ratón y prepare el lápiz o el teclado.\n"
                                              + "3. Escuche el Morse por los altavoces o auriculares del ordenador.\n"
                                              + "4. Escriba lo oído en el cuadro de copia.\n"
                                              + "5. Puede usar REPETIR las veces que necesite.\n"
                                              + "6. Pulse FINALIZAR Y PUNTUAR para ver el texto enviado y los errores.\n\n"
                                              + "Esta modalidad no transmite ni necesita preparar la radio."
                                        color: "#cdd7db"
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 118

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true

                                        SectionTitle { text: "ESCUCHA" }
                                        Item { Layout.fillWidth: true }

                                        SmallLabel { text: "ESPERA" }

                                        DarkSpinBox {
                                            Layout.preferredWidth: 76
                                            implicitHeight: 30
                                            from: 0
                                            to: 10
                                            value: morseTrainer.receptionLeadInSeconds
                                            editable: true
                                            enabled: !morseTrainer.receptionPlaying
                                            textFromValue: function(value) {
                                                return value + " s"
                                            }
                                            valueFromText: function(text) {
                                                return parseInt(text)
                                            }
                                            onValueModified:
                                                morseTrainer.receptionLeadInSeconds = value
                                        }

                                        Rectangle {
                                            implicitWidth: 150
                                            implicitHeight: 30
                                            radius: 15
                                            color: morseTrainer.receptionCountdownActive
                                                   ? "#6b4d18"
                                                   : morseTrainer.receptionPlaying
                                                     ? "#236243" : "#252c30"
                                            border.color:
                                                morseTrainer.receptionCountdownActive
                                                ? "#f1c76a"
                                                : morseTrainer.receptionPlaying
                                                  ? "#79e4a4" : "#5c686e"
                                            border.width: 2

                                            Text {
                                                anchors.centerIn: parent
                                                text: morseTrainer.receptionCountdownActive
                                                      ? "EMPIEZA EN "
                                                        + morseTrainer.receptionCountdownRemaining
                                                      : morseTrainer.receptionPlaying
                                                        ? "REPRODUCIENDO" : "EN ESPERA"
                                                color: "#ffffff"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: morseTrainer.receptionStatusText
                                        color: morseTrainer.receptionCountdownActive
                                               ? "#f1c76a"
                                               : morseTrainer.receptionPlaying
                                                 ? "#86efad" : "#c8d3d8"
                                        font.pixelSize: 11
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ActionButton {
                                            text: "NUEVO Y REPRODUCIR"
                                            implicitWidth: 170
                                            enabled: !morseTrainer.receptionPlaying
                                            onClicked: {
                                                morseTrainer.startReceptionExercise()
                                                receptionCopyArea.forceActiveFocus()
                                            }
                                        }

                                        ActionButton {
                                            text: "REPETIR"
                                            enabled:
                                                !morseTrainer.receptionPlaying
                                                && morseTrainer.receptionExerciseActive
                                                && morseTrainer.receptionTargetText.length > 0
                                            onClicked: {
                                                morseTrainer.replayReceptionExercise()
                                                receptionCopyArea.forceActiveFocus()
                                            }
                                        }

                                        ActionButton {
                                            text: "DETENER"
                                            enabled: morseTrainer.receptionPlaying
                                            onClicked:
                                                morseTrainer.stopReceptionPlayback()
                                        }

                                        Item { Layout.fillWidth: true }

                                        SmallLabel {
                                            text: morseTrainer.characterWpm
                                                  + "/"
                                                  + morseTrainer.effectiveWpm
                                                  + " WPM · "
                                                  + morseTrainer.toneFrequencyHz
                                                  + " Hz"
                                        }
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    RowLayout {
                                        Layout.fillWidth: true
                                        SectionTitle {
                                            text: "COPIA LO QUE ESCUCHAS"
                                        }
                                        Item { Layout.fillWidth: true }
                                        SmallLabel {
                                            text: morseTrainer.receptionExerciseActive
                                                  ? "EJERCICIO ACTIVO"
                                                  : "EJERCICIO FINALIZADO"
                                        }
                                    }

                                    TextArea {
                                        id: receptionCopyArea

                                        property bool synchronizingFromModel: false

                                        function synchronizeCopyText() {
                                            const modelText =
                                                morseTrainer.receptionCopyText
                                            if (text === modelText) {
                                                return
                                            }

                                            // El modelo convierte la copia a
                                            // mayúsculas. Conservamos la posición
                                            // del cursor para impedir que cada
                                            // actualización lo devuelva al inicio.
                                            const savedCursor = cursorPosition
                                            synchronizingFromModel = true
                                            text = modelText
                                            cursorPosition = Math.min(
                                                savedCursor,
                                                text.length
                                            )
                                            synchronizingFromModel = false
                                        }

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        enabled:
                                            morseTrainer.receptionExerciseActive
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        horizontalAlignment: TextEdit.AlignLeft
                                        inputMethodHints:
                                            Qt.ImhPreferUppercase
                                            | Qt.ImhNoPredictiveText
                                        placeholderText:
                                            "Escriba aquí los caracteres que escucha…"
                                        color: "#ffffff"
                                        selectionColor: "#3f7188"
                                        selectedTextColor: "#ffffff"
                                        font.family: "monospace"
                                        font.pixelSize: 26
                                        font.bold: true
                                        background: Rectangle {
                                            radius: 5
                                            color: "#090d0f"
                                            border.color:
                                                receptionCopyArea.activeFocus
                                                ? "#72d2f2" : "#46606c"
                                            border.width:
                                                receptionCopyArea.activeFocus ? 2 : 1
                                        }

                                        Component.onCompleted:
                                            synchronizeCopyText()

                                        onTextChanged: {
                                            if (!synchronizingFromModel
                                                    && morseTrainer
                                                       .receptionCopyText
                                                       !== text) {
                                                morseTrainer.receptionCopyText = text
                                            }
                                        }
                                    }

                                    Connections {
                                        target: morseTrainer

                                        function onReceptionChanged() {
                                            receptionCopyArea
                                            .synchronizeCopyText()
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ActionButton {
                                            text: "LIMPIAR COPIA"
                                            implicitWidth: 125
                                            enabled:
                                                morseTrainer.receptionCopyText.length > 0
                                            onClicked: {
                                                morseTrainer.clearReceptionCopy()
                                                receptionCopyArea.forceActiveFocus()
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        ActionButton {
                                            text: "FINALIZAR Y PUNTUAR"
                                            implicitWidth: 178
                                            enabled:
                                                morseTrainer.receptionExerciseActive
                                                && !morseTrainer.receptionPlaying
                                            onClicked:
                                                morseTrainer.finishReceptionExercise()
                                        }
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 106

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true

                                        SectionTitle { text: "COMPARACIÓN" }
                                        Item { Layout.fillWidth: true }

                                        Text {
                                            visible:
                                                morseTrainer
                                                .receptionTargetRevealed
                                            text: "CORRECTO"
                                            color: "#75e69b"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }

                                        Text {
                                            visible:
                                                morseTrainer
                                                .receptionTargetRevealed
                                            text: "  ERROR"
                                            color: "#ff5f5f"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        visible:
                                            !morseTrainer
                                             .receptionTargetRevealed
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text:
                                            "Los dos textos aparecerán aquí al finalizar y puntuar."
                                        color: "#839198"
                                        font.pixelSize: 12
                                        horizontalAlignment:
                                            Text.AlignHCenter
                                        verticalAlignment:
                                            Text.AlignVCenter
                                        wrapMode: Text.Wrap
                                    }

                                    RowLayout {
                                        visible:
                                            morseTrainer
                                            .receptionTargetRevealed
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        spacing: 7

                                        Text {
                                            Layout.preferredWidth: 70
                                            text: "ENVIADO"
                                            color: "#f7df86"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                morseTrainer
                                                .receptionTargetComparisonHtml
                                            textFormat: Text.RichText
                                            color: "#f7df86"
                                            font.family: "monospace"
                                            font.pixelSize: 21
                                            font.bold: true
                                            wrapMode: Text.NoWrap
                                            clip: true
                                        }
                                    }

                                    RowLayout {
                                        visible:
                                            morseTrainer
                                            .receptionTargetRevealed
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        spacing: 7

                                        Text {
                                            Layout.preferredWidth: 70
                                            text: "COPIADO"
                                            color: "#72d2f2"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text:
                                                morseTrainer
                                                .receptionCopyComparisonHtml
                                            textFormat: Text.RichText
                                            color: "#75e69b"
                                            font.family: "monospace"
                                            font.pixelSize: 21
                                            font.bold: true
                                            wrapMode: Text.NoWrap
                                            clip: true
                                        }
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 72
                                columns: 4
                                columnSpacing: 7

                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "PRECISIÓN"
                                    valueText:
                                        Number(morseTrainer.receptionAccuracy)
                                        .toFixed(1) + "%"
                                    accent: "#72d2f2"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "NOTA"
                                    valueText:
                                        Number(morseTrainer.receptionScore)
                                        .toFixed(1)
                                    accent: morseTrainer.receptionScore >= 90
                                            ? "#75e69b" : "#f0c75a"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "ACIERTOS"
                                    valueText:
                                        String(morseTrainer
                                               .receptionCorrectCharacters)
                                        + " / "
                                        + String(morseTrainer
                                                 .receptionTargetCharacterCount)
                                    accent: "#75e69b"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "ERRORES"
                                    valueText:
                                        String(morseTrainer
                                               .receptionErrorCount)
                                    accent: "#f08c7f"
                                }
                            }
                        }

                        MorseReferencePanel {
                            Layout.fillHeight: true
                        }
                    }
                }

                Item {
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        ColumnLayout {
                            Layout.preferredWidth: 340
                            Layout.fillHeight: true
                            spacing: 8

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 8
                                columnSpacing: 8

                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "SESIONES"
                                    valueText: String(morseTrainer.totalSessions)
                                    accent: "#72d2f2"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "MEDIA GLOBAL"
                                    valueText: Number(morseTrainer.averageScore).toFixed(1)
                                    accent: "#d5b86a"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "MEJOR NOTA"
                                    valueText: Number(morseTrainer.bestScore).toFixed(1)
                                    accent: "#75e69b"
                                }
                                MetricCard {
                                    Layout.fillWidth: true
                                    caption: "LECCIÓN ACTUAL"
                                    valueText: morseTrainer.currentLessonPassed
                                               ? "SUPERADA" : "EN CURSO"
                                    accent: morseTrainer.currentLessonPassed
                                            ? "#75e69b" : "#f0c75a"
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 158

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    SectionTitle {
                                        text: "LECCIÓN " + morseTrainer.lesson
                                    }
                                    SmallLabel {
                                        text: "Sesiones: "
                                              + morseTrainer.currentLessonSessions
                                    }
                                    SmallLabel {
                                        text: "Media: "
                                              + Number(morseTrainer.currentLessonAverage).toFixed(1)
                                    }
                                    SmallLabel {
                                        text: "Mejor: "
                                              + Number(morseTrainer.currentLessonBest).toFixed(1)
                                    }
                                    Text {
                                        text: morseTrainer.currentLessonPassed
                                              ? "Objetivo Koch alcanzado (≥ 90)."
                                              : "Objetivo recomendado: alcanzar 90 puntos."
                                        color: morseTrainer.currentLessonPassed
                                               ? "#75e69b" : "#f0c75a"
                                        font.pixelSize: 11
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            Panel {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 7

                                    SectionTitle { text: "ÚLTIMAS SESIONES" }

                                    ListView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: 4
                                        model: morseTrainer.recentSessions

                                        delegate: Rectangle {
                                            width: ListView.view.width
                                            height: 58
                                            radius: 4
                                            color: index % 2 === 0
                                                   ? "#171c1f" : "#121719"
                                            border.color: "#3b474d"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 7
                                                spacing: 7

                                                Text {
                                                    text: "L" + modelData.lesson
                                                    color: "#72d2f2"
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.timestamp
                                                        color: "#aeb8bd"
                                                        font.pixelSize: 9
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.modeText
                                                              + " · "
                                                              + modelData.characterWpm
                                                              + "/"
                                                              + modelData.effectiveWpm
                                                              + " WPM · "
                                                              + modelData.correct
                                                              + " aciertos"
                                                        color: "#dce4e7"
                                                        font.pixelSize: 10
                                                    }
                                                }
                                                Text {
                                                    text: Number(modelData.total).toFixed(1)
                                                    color: modelData.total >= 90
                                                           ? "#75e69b" : "#f0c75a"
                                                    font.pixelSize: 18
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Panel {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7

                                RowLayout {
                                    Layout.fillWidth: true
                                    SectionTitle { text: "PROGRESO POR LECCIÓN KOCH" }
                                    Item { Layout.fillWidth: true }
                                    SmallLabel { text: "Superada con mejor nota ≥ 90" }
                                    ActionButton {
                                        text: "RESETEAR LECCIÓN"
                                        implicitWidth: 132
                                        onClicked:
                                            resetCurrentLessonDialog.open()
                                    }
                                    ActionButton {
                                        text: "BORRAR HISTORIAL"
                                        implicitWidth: 126
                                        onClicked: resetStatisticsDialog.open()
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    color: "#273036"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        Text { Layout.preferredWidth: 55; text: "LECCIÓN"; color: "#dce4e7"; font.pixelSize: 10; font.bold: true }
                                        Text { Layout.fillWidth: true; text: "CARACTERES"; color: "#dce4e7"; font.pixelSize: 10; font.bold: true }
                                        Text { Layout.preferredWidth: 65; text: "SESIONES"; color: "#dce4e7"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                        Text { Layout.preferredWidth: 60; text: "MEDIA"; color: "#dce4e7"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight }
                                        Text { Layout.preferredWidth: 60; text: "MEJOR"; color: "#dce4e7"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight }
                                        Text { Layout.preferredWidth: 75; text: "ESTADO"; color: "#dce4e7"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                    }
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 2
                                    model: morseTrainer.lessonStatistics
                                    currentIndex: morseTrainer.lesson - 1

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 34
                                        color: modelData.lesson === morseTrainer.lesson
                                               ? "#203945"
                                               : index % 2 === 0
                                                 ? "#171c1f" : "#121719"
                                        border.color: modelData.lesson === morseTrainer.lesson
                                                      ? "#5da8c7" : "#303a3f"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8

                                            Text { Layout.preferredWidth: 55; text: modelData.lesson; color: "#dce4e7"; font.pixelSize: 11; font.bold: modelData.lesson === morseTrainer.lesson }
                                            Text { Layout.fillWidth: true; text: modelData.characters; color: "#bfc9ce"; font.family: "monospace"; font.pixelSize: 10; elide: Text.ElideRight }
                                            Text { Layout.preferredWidth: 65; text: modelData.sessions; color: "#cbd5da"; font.pixelSize: 10; horizontalAlignment: Text.AlignHCenter }
                                            Text { Layout.preferredWidth: 60; text: Number(modelData.average).toFixed(1); color: "#cbd5da"; font.pixelSize: 10; horizontalAlignment: Text.AlignRight }
                                            Text { Layout.preferredWidth: 60; text: Number(modelData.best).toFixed(1); color: modelData.passed ? "#75e69b" : "#f0c75a"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignRight }
                                            Text { Layout.preferredWidth: 75; text: modelData.passed ? "SUPERADA" : "EN CURSO"; color: modelData.passed ? "#75e69b" : "#aeb8bd"; font.pixelSize: 9; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked:
                                                morseTrainer.lesson = modelData.lesson
                                        }
                                    }
                                    ScrollBar.vertical: ScrollBar { }
                                }
                            }
                        }
                    }
                }

                Item {
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        Panel {
                            Layout.preferredWidth: 405
                            Layout.minimumWidth: 370
                            Layout.maximumWidth: 445
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                SectionTitle { text: "RADIO Y SEGURIDAD" }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 102
                                    radius: 5
                                    color: "#173527"
                                    border.color: "#61c991"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        Text {
                                            Layout.fillWidth: true
                                            text: "MODO RECOMENDADO · SIN RF"
                                            color: "#8aebb2"
                                            font.pixelSize: 13
                                            font.bold: true
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "El entrenador ordena CW y BREAK-IN OFF. El manipulador genera el tono lateral de práctica sin conmutar el transmisor."
                                            color: "#e5f1e9"
                                            font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                DarkRadioButton {
                                    id: safeModeRadio
                                    Layout.fillWidth: true
                                    text: "Práctica segura, BK-IN OFF (recomendada)"
                                    checked: trainerWindow.safePractice
                                    onClicked: {
                                        trainerWindow.safePractice = true
                                        trainerWindow.prepareRadio()
                                    }
                                }

                                DarkCheckBox {
                                    id: dummyLoadCheck
                                    Layout.fillWidth: true
                                    text: "Confirmo que hay una carga ficticia adecuada y que acepto una transmisión real."
                                    checked: trainerWindow.dummyLoadConfirmed
                                    onToggled: {
                                        trainerWindow.dummyLoadConfirmed = checked
                                        if (!checked && !trainerWindow.safePractice) {
                                            trainerWindow.safePractice = true
                                            safeModeRadio.checked = true
                                            trainerWindow.prepareRadio()
                                        }
                                    }
                                }

                                DarkRadioButton {
                                    id: rfModeRadio
                                    Layout.fillWidth: true
                                    text: "Prueba RF mínima: RF POWER 1 % y BK-IN SEMI"
                                    enabled: trainerWindow.dummyLoadConfirmed
                                    checked: !trainerWindow.safePractice
                                    onClicked: {
                                        if (!trainerWindow.dummyLoadConfirmed)
                                            return
                                        trainerWindow.safePractice = false
                                        trainerWindow.prepareRadio()
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 94
                                    radius: 5
                                    color: "#4b281d"
                                    border.color: "#e69359"

                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        text: "ATENCIÓN: el modo RF mínima sí transmite cuando se acciona el manipulador. El 1 % es el mínimo del control software, no una garantía de potencia exacta. No lo use sin carga ficticia o una instalación de antena segura."
                                        color: "#ffe3cf"
                                        font.pixelSize: 11
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                ActionButton {
                                    Layout.fillWidth: true
                                    text: "APLICAR CONFIGURACIÓN A LA RADIO"
                                    enabled: radioController.connected
                                    onClicked: trainerWindow.prepareRadio()
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: trainerWindow.radioPreparationStatus
                                    color: trainerWindow.safePractice
                                           ? "#7fe2a7" : "#f0a15e"
                                    font.pixelSize: 11
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        Panel {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 520
                            Layout.preferredWidth: 720
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 9

                                SectionTitle { text: "DETECTOR DEL TONO CW" }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    rowSpacing: 8
                                    columnSpacing: 12

                                    SmallLabel { text: "Pitch de detección" }
                                    DarkSpinBox {
                                        Layout.fillWidth: true
                                        from: 300
                                        to: 900
                                        stepSize: 5
                                        value: morseTrainer.toneFrequencyHz
                                        editable: true
                                        textFromValue: function(value) {
                                            return value + " Hz"
                                        }
                                        valueFromText: function(text) {
                                            return parseInt(text)
                                        }
                                        onValueModified:
                                            morseTrainer.toneFrequencyHz = value
                                    }

                                    SmallLabel { text: "Umbral automático" }
                                    DarkSwitch {
                                        checked: morseTrainer.automaticThreshold
                                        text: checked ? "ACTIVO" : "MANUAL"
                                        onToggled:
                                            morseTrainer.automaticThreshold = checked
                                    }
                                }

                                SmallLabel {
                                    text: "Umbral manual: "
                                          + Number(morseTrainer.thresholdDb).toFixed(1)
                                          + " dB"
                                }
                                Slider {
                                    Layout.fillWidth: true
                                    from: -80
                                    to: -8
                                    value: morseTrainer.thresholdDb
                                    enabled: !morseTrainer.automaticThreshold
                                    onMoved:
                                        morseTrainer.thresholdDb = value
                                }

                                LevelMeter {
                                    Layout.fillWidth: true
                                    caption: "Ruido estimado"
                                    levelDb: morseTrainer.noiseFloorDb
                                    barColor: "#8f9da4"
                                }
                                LevelMeter {
                                    Layout.fillWidth: true
                                    caption: "Nivel de entrada"
                                    levelDb: morseTrainer.inputLevelDb
                                    barColor: "#65c8ee"
                                }
                                LevelMeter {
                                    Layout.fillWidth: true
                                    caption: "Energía en "
                                             + morseTrainer.toneFrequencyHz
                                             + " Hz"
                                    levelDb: morseTrainer.toneLevelDb
                                    barColor: morseTrainer.keyDown
                                              ? "#75e69b" : "#f0c75a"
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 132
                                    radius: 5
                                    color: "#151a1d"
                                    border.color: "#46545b"

                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        text: "CONEXIÓN\n1. Conecte el manipulador al jack KEY de la radio.\n2. Seleccione la entrada de audio USB correspondiente al IC-7300MK2.\n3. Pulse PREPARAR RADIO y después ESCUCHAR.\n4. Ajuste el pitch solo si no coincide con el tono CW de la radio.\n\nSi el medidor no se mueve, revise en la radio la ruta/nivel de salida AF por USB y el dispositivo elegido en Linux."
                                        color: "#cbd5da"
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Historial: " + morseTrainer.statisticsFilePath
                                    color: "#86959c"
                                    font.pixelSize: 9
                                    wrapMode: Text.WrapAnywhere
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: resetCurrentLessonDialog

        anchors.centerIn: parent
        modal: true
        title: "Resetear lección " + morseTrainer.lesson
        standardButtons: Dialog.Ok | Dialog.Cancel
        palette.text: "#e7edf0"
        palette.buttonText: "#f4f8fa"
        palette.windowText: "#e7edf0"
        palette.button: "#2a363c"
        palette.highlight: "#3f7188"

        contentItem: Text {
            text: "Se eliminarán únicamente las sesiones y estadísticas de la lección "
                  + morseTrainer.lesson
                  + ". Las demás lecciones conservarán su progreso."
            color: "#e7edf0"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: 390
            padding: 12
        }

        background: Rectangle {
            color: "#23292d"
            border.color: "#c79045"
            radius: 5
        }

        onAccepted:
            morseTrainer.resetCurrentLessonStatistics()
    }

    Dialog {
        id: resetStatisticsDialog

        anchors.centerIn: parent
        modal: true
        title: "Borrar historial Morse"
        standardButtons: Dialog.Ok | Dialog.Cancel
        palette.text: "#e7edf0"
        palette.buttonText: "#f4f8fa"
        palette.windowText: "#e7edf0"
        palette.button: "#2a363c"
        palette.highlight: "#3f7188"

        contentItem: Text {
            text: "Se eliminarán todas las sesiones y estadísticas del entrenador Morse. Esta operación no se puede deshacer."
            color: "#e7edf0"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: 380
            padding: 12
        }

        background: Rectangle {
            color: "#23292d"
            border.color: "#8d5b55"
            radius: 5
        }

        onAccepted: morseTrainer.resetStatistics()
    }

}
