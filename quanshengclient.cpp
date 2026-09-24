#include "quanshengclient.h"
#include "quansheng/src/core/tones.h"

#include <QAbstractSocket>
#include <QDateTime>
#include <QJsonDocument>
#include <QLocale>
#include <QtMath>
#include <QJsonArray>
#include <QJsonObject>
#include <QDebug>
#include <QSettings>
#include <QGuiApplication>
#include <QUuid>
#include <QTcpSocket>

namespace {

QVariantList emptyHardwareRegisterRows()
{
    QVariantList rows;
    rows.reserve(0x80);
    for (int address = 0; address <= 0x7f; ++address) {
        rows.append(QVariantMap{
            {QStringLiteral("register"),
             QStringLiteral("0x%1").arg(QString::number(address, 16)
                                             .rightJustified(2, QLatin1Char('0')).toUpper())},
            {QStringLiteral("value"), QStringLiteral("—")},
            {QStringLiteral("interpretation"),
             QStringLiteral("No leído · interpretación pendiente")}});
    }
    return rows;
}

} // namespace

QuanshengClient::QuanshengClient(QObject *parent)
    : QObject(parent), m_socket(new QTcpSocket(this))
{
    m_pttTimer.setInterval(250);
    connect(&m_pttTimer, &QTimer::timeout, this, [this] {
        if (m_pttPressed && connected() && m_socket->bytesToWrite() == 0)
            sendJson({{"message", "ptt"}, {"action", "keepalive"}, {"id", m_pttId}});
    });
    if (auto* app = qobject_cast<QGuiApplication*>(QCoreApplication::instance()))
        connect(app, &QGuiApplication::applicationStateChanged, this,
                [this](Qt::ApplicationState state) {
            if (state != Qt::ApplicationActive) releasePtt();
        });
    m_hardwareRegisterRows = emptyHardwareRegisterRows();

    QSettings settings;
    m_host = settings.value(QStringLiteral("quansheng/host"), m_host).toString();
    const int savedPort = settings.value(QStringLiteral("quansheng/port"), m_port).toInt();
    if (savedPort >= 1 && savedPort <= 65535)
        m_port = savedPort;
    m_token = settings.value(QStringLiteral("quansheng/token"), m_token).toString();
    m_autoReconnect = settings.value(QStringLiteral("quansheng/autoReconnect"), true).toBool();
    m_autoConnectOnStartup = settings.value(QStringLiteral("quansheng/autoConnectOnStartup"), false).toBool();

    m_reconnectTimer.setInterval(5000);
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, &QTimer::timeout,
            this, &QuanshengClient::connectToServer);

    m_observationTimer.setInterval(1000);
    connect(&m_observationTimer, &QTimer::timeout, this, [this]() {
        bool changed = false;
        const QDateTime now = QDateTime::currentDateTimeUtc();
        if (!m_lastObservationAt.isEmpty()) {
            const QDateTime observed = QDateTime::fromString(
                m_lastObservationAt, Qt::ISODateWithMs);
            if (observed.isValid()) {
                const int age = qMax(0, observed.secsTo(now));
                const bool fresh = age <= 5 && connected();
                if (age != m_observationAgeSeconds || fresh != m_observationFresh) {
                    m_observationAgeSeconds = age;
                    m_observationFresh = fresh;
                    changed = true;
                }
            }
        }
        const int silence = connected() && m_lastEventReceivedAt.isValid()
            ? qMax(0, m_lastEventReceivedAt.secsTo(now)) : -1;
        const bool stalled = connected() && m_serialAvailable && silence >= 10;
        if (silence != m_eventSilenceSeconds || stalled != m_eventStreamStalled) {
            m_eventSilenceSeconds = silence;
            m_eventStreamStalled = stalled;
            changed = true;
        }
        if (changed)
            emit stateChanged();
    });
    m_observationTimer.start();

    m_notifyTimer.setInterval(100);
    m_notifyTimer.setSingleShot(true);
    connect(&m_notifyTimer, &QTimer::timeout, this, [this]() {
        if (!m_notificationPending)
            return;
        m_notificationPending = false;
        emit stateChanged();
        emit countersChanged();
    });

    m_controlSettleTimer.setInterval(6000);
    m_controlSettleTimer.setSingleShot(true);
    connect(&m_controlSettleTimer, &QTimer::timeout, this, [this]() {
        if (!m_waitingControlDisplayState)
            return;
        m_waitingControlDisplayState = false;
        m_controlBusy = false;
        m_frequencyControlStatus = QStringLiteral("%1 · sin nueva confirmación de pantalla; controles liberados")
            .arg(m_controlOperation.isEmpty() ? QStringLiteral("Operación") : m_controlOperation);
        m_controlOperation.clear();
        emit stateChanged();
    });

    connect(m_socket, &QTcpSocket::connected,
            this, &QuanshengClient::onConnected);
    connect(m_socket, &QTcpSocket::readyRead,
            this, &QuanshengClient::onReadyRead);
    connect(m_socket, &QTcpSocket::disconnected,
            this, &QuanshengClient::onDisconnected);
    connect(m_socket, &QTcpSocket::errorOccurred,
            this, &QuanshengClient::onSocketError);
}

QuanshengClient::~QuanshengClient()
{
    shutdown();
}

void QuanshengClient::appendToneLog(const QString &message)
{
    m_toneLog.append(QStringLiteral("%1 %2")
                     .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")), message));
    constexpr int maxEntries = 120;
    while (m_toneLog.size() > maxEntries)
        m_toneLog.removeFirst();
    emit stateChanged();
}

void QuanshengClient::clearToneLog()
{
    m_toneLog.clear();
    emit stateChanged();
}

void QuanshengClient::finishRadioControlWait()
{
    if (!m_waitingControlDisplayState)
        return;
    m_waitingControlDisplayState = false;
    m_controlSettleTimer.stop();
    if (!m_toneBusy)
        m_controlBusy = false;
    m_frequencyControlStatus = (m_controlOperation.isEmpty()
        ? QStringLiteral("Operación") : m_controlOperation)
        + QStringLiteral(" · confirmado por pantalla");
    m_controlOperation.clear();
}

void QuanshengClient::setHost(const QString &host)
{
    const QString value = host.trimmed();
    if (value.isEmpty() || value == m_host)
        return;
    m_host = value;
    QSettings().setValue(QStringLiteral("quansheng/host"), m_host);
    emit connectionSettingsChanged();
}

void QuanshengClient::setPort(int port)
{
    if (port < 1 || port > 65535 || port == m_port)
        return;
    m_port = port;
    QSettings().setValue(QStringLiteral("quansheng/port"), m_port);
    emit connectionSettingsChanged();
}

void QuanshengClient::setToken(const QString &token)
{
    if (token == m_token)
        return;
    m_token = token;
    QSettings().setValue(QStringLiteral("quansheng/token"), m_token);
    emit connectionSettingsChanged();
}

void QuanshengClient::setAutoReconnect(bool enabled)
{
    if (enabled == m_autoReconnect)
        return;
    m_autoReconnect = enabled;
    QSettings().setValue(QStringLiteral("quansheng/autoReconnect"), m_autoReconnect);
    if (!m_autoReconnect)
        m_reconnectTimer.stop();
    emit connectionSettingsChanged();
}

void QuanshengClient::setAutoConnectOnStartup(bool enabled)
{
    if (enabled == m_autoConnectOnStartup)
        return;
    m_autoConnectOnStartup = enabled;
    QSettings().setValue(QStringLiteral("quansheng/autoConnectOnStartup"), m_autoConnectOnStartup);
    emit connectionSettingsChanged();
}

void QuanshengClient::connectToServer()
{
    if (m_shuttingDown)
        return;
    releasePtt();
    m_toneControlAvailable = false;
    m_toneBusy = false;
    m_toneRequestPending = false;
    m_toneState.clear();
    m_toneStates.clear();
    m_toneStatus = QStringLiteral("Tonos sin leer");
    m_txControlAvailable = false;
    m_reconnectRequested = true;
    setError(QString());
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->abort();
    m_buffer.clear();
    m_sourceStatus = QStringLiteral("conectando");
    m_serialAvailable = false;
    m_eepromReadAvailable = false;
    m_frequencyControlAvailable = false;
    m_frequencyControlStatus = QStringLiteral("No disponible");
    m_controlBusy = false;
    m_waitingControlDisplayState = false;
    m_controlSettleTimer.stop();
    m_controlOperation.clear();
    m_pendingVfoModeTarget.clear();
    m_pendingVfoModePreviousMemory.clear();
    m_pendingRadioControl.clear();
    m_dualWatchKnown = false;
    m_squelchLevel = -1;
    m_eepromBusy = false;
    m_lastEventReceivedAt = {};
    m_eventSilenceSeconds = -1;
    m_eventStreamStalled = false;
    m_frequencyText.clear();
    m_activeVfo.clear();
    m_batteryPercent = -1;
    m_signalLevel = -1;
    m_signalOver = 0;
    m_rssiRaw = -1;
    m_rssiNoise = -1;
    m_rssiGlitch = -1;
    m_hardwareFrequencyText.clear();
    m_hardwareRegisterCount = 0;
    m_hardwareBlocksText.clear();
    m_hardwareAgcText.clear();
    m_hardwareAfcText.clear();
    m_hardwareRegistersRawText.clear();
    m_hardwareRegisterRows = emptyHardwareRegisterRows();
    m_hardwareFunctionsText.clear();
    m_hardwareGpioText.clear();
    m_hardwareAudioText.clear();
    m_hardwareRfAgcText.clear();
    m_hardwareFilterText.clear();
    m_hardwareSquelchText.clear();
    m_hardwarePaText.clear();
    m_hardwareCssText.clear();
    m_hardwareTonesText.clear();
    m_hardwareScanText.clear();
    m_hardwareDtmfText.clear();
    m_stepText.clear();
    m_toneIndicator.clear();
    m_indicatorsText.clear();
    m_lastDtmf.clear();
    m_vfoAFrequencyText.clear();
    m_vfoBFrequencyText.clear();
    m_vfoAMemory.clear();
    m_vfoBMemory.clear();
    m_vfoAName.clear();
    m_vfoBName.clear();
    m_vfoAMode.clear();
    m_vfoBMode.clear();
    m_vfoAPower.clear();
    m_vfoBPower.clear();
    emit stateChanged();
    m_socket->connectToHost(m_host, static_cast<quint16>(m_port));
}

void QuanshengClient::shutdown()
{
    if (m_shuttingDown)
        return;
    releasePtt();
    m_socket->flush();
    m_shuttingDown = true;
    m_reconnectRequested = false;
    m_reconnectTimer.stop();
    m_observationTimer.stop();
    m_notifyTimer.stop();
    m_controlSettleTimer.stop();
    m_notificationPending = false;
    if (m_socket) {
        m_socket->disconnect(this);
        m_socket->abort();
    }
}

void QuanshengClient::disconnectFromServer()
{
    releasePtt();
    m_txControlAvailable = false;
    m_reconnectRequested = false;
    m_reconnectTimer.stop();
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->disconnectFromHost();
    m_sourceStatus = QStringLiteral("desconectado");
    m_serialAvailable = false;
    m_frequencyControlAvailable = false;
    m_frequencyControlStatus = QStringLiteral("No disponible");
    m_controlBusy = false;
    m_waitingControlDisplayState = false;
    m_controlSettleTimer.stop();
    m_controlOperation.clear();
    m_pendingVfoModeTarget.clear();
    m_pendingVfoModePreviousMemory.clear();
    m_pendingRadioControl.clear();
    m_dualWatchKnown = false;
    m_squelchLevel = -1;
    m_eepromReadAvailable = false;
    m_eepromBusy = false;
    m_observationFresh = false;
    m_lastEventReceivedAt = {};
    m_eventSilenceSeconds = -1;
    m_eventStreamStalled = false;
    emit stateChanged();
}

void QuanshengClient::resetCounters()
{
    m_eventCount = 0;
    m_bytesReceived = 0;
    m_discardedBytes = 0;
    m_pendingBytes = 0;
    emit countersChanged();
}

void QuanshengClient::readEeprom()
{
    if (!connected() || !m_eepromReadAvailable || m_eepromBusy)
        return;
    m_eepromBusy = true;
    m_eepromStatus = QStringLiteral("Iniciando lectura…");
    m_eepromHexDump.clear();
    m_eepromChannelRows.clear();
    m_eepromSettingRows.clear();
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("read_eeprom")}});
}

void QuanshengClient::setFrequency(const QString &frequencyMHz)
{
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy)
        return;
    bool ok = false;
    const double mhz = QLocale::c().toDouble(frequencyMHz.trimmed(), &ok);
    if (!ok || !qIsFinite(mhz) || mhz < 18.0 || mhz > 1300.0
            || (mhz > 630.0 && mhz < 840.0)) {
        m_frequencyControlStatus = QStringLiteral("Frecuencia no utilizable (18–1300 MHz; 630–840 MHz excluidos)");
        emit stateChanged();
        return;
    }
    const qint64 hz = qRound64(mhz * 1000000.0);
    m_controlOperation = QStringLiteral("Frecuencia VFO %1 a %2 MHz")
        .arg(m_activeVfo.isEmpty() ? QStringLiteral("—") : m_activeVfo,
             frequencyMHz.trimmed());
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("set_frequency")},
                         {QStringLiteral("frequencyHz"), hz}});
}

void QuanshengClient::switchVfo()
{
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy)
        return;
    const QString destination = m_activeVfo == QStringLiteral("A")
        ? QStringLiteral("B") : m_activeVfo == QStringLiteral("B")
        ? QStringLiteral("A") : QStringLiteral("—");
    if (destination == QStringLiteral("A") || destination == QStringLiteral("B")) {
        m_memoryStepPending = true;
        m_memoryToneReadAttempts = 0;
        m_memoryStepVfo = destination;
        m_toneStates.remove(destination);
        m_toneState.clear();
    }
    m_controlOperation = QStringLiteral("Cambiar VFO %1 → %2")
        .arg(m_activeVfo.isEmpty() ? QStringLiteral("—") : m_activeVfo, destination);
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("switch_vfo")} });
}

void QuanshengClient::toggleVfoMode(const QString &vfo)
{
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy || (vfo != "A" && vfo != "B")) return;
    QString &memory = vfo == QStringLiteral("A") ? m_vfoAMemory : m_vfoBMemory;
    m_pendingVfoModeTarget = vfo;
    m_pendingVfoModePreviousMemory = memory;
    const bool wasMemory = memory == QStringLiteral("Memoria")
        || memory.startsWith(QLatin1Char('M'));
    m_memoryStepPending = true;
    m_memoryToneReadAttempts = 0;
    m_memoryStepVfo = vfo;
    m_toneStates.remove(vfo);
    m_toneState.clear();
    // La tecla actúa inmediatamente en la radio, pero el firmware puede tardar
    // varios segundos en volver a dibujar Mxxx/Fxxx. Reflejar provisionalmente
    // el destino y sustituirlo cuando llegue la confirmación de pantalla.
    memory = wasMemory ? QStringLiteral("VFO") : QStringLiteral("Memoria");
    const QString destination = wasMemory ? QStringLiteral("VFO") : QStringLiteral("Memoria");
    m_controlOperation = m_activeVfo == vfo
        ? QStringLiteral("Cambiar VFO %1 a %2").arg(vfo, destination)
        : QStringLiteral("Seleccionar VFO %1 y cambiar a %2").arg(vfo, destination);
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("toggle_vfo_mode")},
                         {QStringLiteral("vfo"), vfo}});
}

void QuanshengClient::stepMemory(const QString &vfo, bool up)
{
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy || (vfo != "A" && vfo != "B")) return;
    m_memoryStepPending = true;
    m_memoryToneReadAttempts = 0;
    m_memoryStepVfo = vfo;
    const QString direction = up ? QStringLiteral("subir memoria")
                                 : QStringLiteral("bajar memoria");
    m_controlOperation = m_activeVfo == vfo
        ? QStringLiteral("VFO %1: %2").arg(vfo, direction)
        : QStringLiteral("Seleccionar VFO %1 y %2").arg(vfo, direction);
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("memory_step")},
                         {QStringLiteral("vfo"), vfo},
                         {QStringLiteral("direction"), up ? QStringLiteral("up") : QStringLiteral("down")} });
}

void QuanshengClient::setMode(const QString &vfo, const QString &mode)
{
    static const QStringList modes{QStringLiteral("FM"), QStringLiteral("AM"),
        QStringLiteral("USB"), QStringLiteral("BYP"), QStringLiteral("RAW")};
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy
        || (vfo != QStringLiteral("A") && vfo != QStringLiteral("B"))
        || !modes.contains(mode))
        return;
    m_controlOperation = m_activeVfo == vfo
        ? QStringLiteral("Modo %1 en VFO %2").arg(mode, vfo)
        : QStringLiteral("Seleccionar VFO %1 y aplicar modo %2").arg(vfo, mode);
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("set_mode")},
                         {QStringLiteral("vfo"), vfo}, {QStringLiteral("mode"), mode}});
}

void QuanshengClient::setDualWatch(bool enabled)
{
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy
        || (m_dualWatchKnown && m_dualWatch == enabled))
        return;
    m_pendingRadioControl = QStringLiteral("dual_watch");
    m_pendingDualWatchPrevious = m_dualWatch;
    m_dualWatch = enabled;
    m_dualWatchKnown = true;
    m_controlOperation = enabled ? QStringLiteral("Activar Dual Watch")
                                 : QStringLiteral("Desactivar Dual Watch");
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("set_dual_watch")},
                         {QStringLiteral("enabled"), enabled}});
}

void QuanshengClient::setSquelch(int level)
{
    if (!connected() || !m_frequencyControlAvailable || m_controlBusy
        || level < 0 || level > 9 || m_squelchLevel == level)
        return;
    m_pendingRadioControl = QStringLiteral("squelch");
    m_pendingSquelchPrevious = m_squelchLevel;
    m_squelchLevel = level;
    m_controlOperation = QStringLiteral("Ajustar squelch a %1").arg(level);
    m_frequencyControlStatus = m_controlOperation + QStringLiteral("…");
    m_controlBusy = true;
    emit stateChanged();
    sendJson(QJsonObject{{QStringLiteral("message"), QStringLiteral("set_squelch")},
                         {QStringLiteral("level"), level}});
}

void QuanshengClient::onConnected()
{
    qInfo().noquote() << "Quansheng LAN conectado a" << m_host << m_port;
    m_reconnectTimer.stop();
    emit connectedChanged();
    QJsonObject hello;
    hello.insert(QStringLiteral("message"), QStringLiteral("hello"));
    hello.insert(QStringLiteral("protocol"), QStringLiteral("qdock-lan/1"));
    hello.insert(QStringLiteral("token"), m_token);
    sendJson(hello);
}

void QuanshengClient::onReadyRead()
{
    m_buffer += m_socket->readAll();
    while (true) {
        const qsizetype newline = m_buffer.indexOf('\n');
        if (newline < 0)
            break;
        const QByteArray line = m_buffer.left(newline).trimmed();
        m_buffer.remove(0, newline + 1);
        if (!line.isEmpty())
            processLine(line);
    }
}

void QuanshengClient::onSocketError(QAbstractSocket::SocketError)
{
    if (m_shuttingDown)
        return;
    qWarning().noquote() << "Quansheng LAN error:" << m_socket->errorString();
    // El servidor envía primero un mensaje JSON con el motivo preciso y cierra
    // después el socket. No ocultar ese diagnóstico con RemoteHostClosedError.
    if (m_error.isEmpty())
        setError(m_socket->errorString());
    m_sourceStatus = QStringLiteral("error");
    emit stateChanged();
}

void QuanshengClient::onDisconnected()
{
    if (m_shuttingDown)
        return;
    m_pttTimer.stop();
    m_toneControlAvailable = false;
    m_toneBusy = false;
    m_toneRequestPending = false;
    m_toneState.clear();
    m_toneStates.clear();
    m_toneStatus = QStringLiteral("Desconectado; tonos sin confirmar");
    m_pttPressed = false;
    m_pttId.clear();
    m_txControlAvailable = false;
    m_pttStatus = QStringLiteral("PTT desconectado");
    qInfo() << "Quansheng LAN desconectado";
    emit connectedChanged();
    m_sourceStatus = QStringLiteral("desconectado");
    m_serialAvailable = false;
    m_controlBusy = false;
    m_waitingControlDisplayState = false;
    m_controlSettleTimer.stop();
    m_controlOperation.clear();
    m_pendingVfoModeTarget.clear();
    m_pendingVfoModePreviousMemory.clear();
    m_pendingRadioControl.clear();
    m_dualWatchKnown = false;
    m_squelchLevel = -1;
    m_observationFresh = false;
    m_lastEventReceivedAt = {};
    m_eventSilenceSeconds = -1;
    m_eventStreamStalled = false;
    emit stateChanged();
    if (m_reconnectRequested && m_autoReconnect && !m_reconnectTimer.isActive())
        m_reconnectTimer.start();
}

QVariantList QuanshengClient::toneOptions(int type) const
{
    QVariantList values;
    const int count = type == 0 ? 1 : type == 1 ? 50 : (type == 2 || type == 3) ? 104 : 0;
    for (int i = 0; i < count; ++i)
        values.append(QString::fromStdString(qdock::toneLabel(type, i)));
    return values;
}

void QuanshengClient::readTones(const QString& vfo)
{
    if (!connected() || !m_toneControlAvailable || m_controlBusy || m_eepromBusy
        || m_pttPressed || m_sourceStatus != "listening" || (vfo != "A" && vfo != "B")) return;
    m_toneRequestPending = true;
    m_controlBusy = true;
    m_toneState.clear();
    m_toneStates.remove(vfo);
    m_toneStatus = QStringLiteral("Solicitando lectura de tonos…");
    appendToneLog(QStringLiteral("TX read_tones vfo=%1").arg(vfo));
    sendJson({{"message", "read_tones"}, {"vfo", vfo}});
    emit stateChanged();
}

void QuanshengClient::readMemoryTonesIfNeeded(const QString &requestedVfo)
{
    const QString requested = requestedVfo.isEmpty() ? QStringLiteral("active") : requestedVfo;
    if (!connected() || !m_toneControlAvailable || m_controlBusy || m_eepromBusy
        || m_toneBusy || m_toneRequestPending || m_pttPressed
        || m_sourceStatus != QStringLiteral("listening"))
        return;
    if (m_skipMemoryToneReadAfterPttRelease) {
        return;
    }

    const QString vfo = requestedVfo == QStringLiteral("A") || requestedVfo == QStringLiteral("B")
        ? requestedVfo
        : (m_activeVfo == QStringLiteral("B") ? QStringLiteral("B") : QStringLiteral("A"));
    const QString memory = vfo == QStringLiteral("B") ? m_vfoBMemory : m_vfoAMemory;
    const QString frequency = vfo == QStringLiteral("B")
        ? m_vfoBFrequencyText : m_vfoAFrequencyText;
    if (memory.isEmpty() || (!memory.startsWith(QLatin1Char('M'))
                             && memory != QStringLiteral("Memoria"))
        || frequency.isEmpty())
        return;

    const QVariantMap cached = m_toneStates.value(vfo).toMap();
    if (!cached.isEmpty() && cached.value(QStringLiteral("frequency")).toString() == frequency
        && cached.value(QStringLiteral("memory")).toString() == memory)
        return;

    qInfo().noquote() << "Quansheng: lectura automática de tonos"
                      << "solicitado=" + requested
                      << "vfo=" + vfo
                      << "activo=" + m_activeVfo
                      << "memoria=" + memory
                      << "frecuencia=" + frequency;
    appendToneLog(QStringLiteral("AUTO vfo=%1 activo=%2 memoria=%3 frecuencia=%4")
                  .arg(vfo, m_activeVfo, memory, frequency));
    readTones(vfo);
}

void QuanshengClient::retryPendingMemoryToneRead()
{
    if (!m_memoryStepPending)
        return;
    if (++m_memoryToneReadAttempts > 12) {
        m_memoryStepPending = false;
        m_memoryStepVfo.clear();
        return;
    }
    const QString targetVfo = m_memoryStepVfo;
    readMemoryTonesIfNeeded(targetVfo);
    if (m_toneRequestPending || m_toneBusy) {
        m_memoryStepPending = false;
        m_memoryStepVfo.clear();
        return;
    }
    QTimer::singleShot(400, this, &QuanshengClient::retryPendingMemoryToneRead);
}

void QuanshengClient::setTone(const QString& vfo, const QString& direction, int type, int index)
{
    if (!connected() || !m_toneControlAvailable || m_controlBusy || m_eepromBusy
        || m_pttPressed || m_sourceStatus != "listening" || (vfo != "A" && vfo != "B")
        || (direction != "RX" && direction != "TX") || !qdock::validTone(type, index)) return;
    m_toneRequestPending = true;
    m_controlBusy = true;
    m_toneState.clear();
    m_toneStates.remove(vfo);
    m_toneStatus = QStringLiteral("Escribiendo tono %1; pendiente de verificación…").arg(direction);
    sendJson({{"message", "set_tone"}, {"vfo", vfo}, {"direction", direction},
              {"type", type}, {"index", index}});
    emit stateChanged();
}

void QuanshengClient::sendJson(const QJsonObject &object)
{
    if (m_socket->state() == QAbstractSocket::ConnectedState) {
        const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Compact);
        QJsonObject loggedObject = object;
        if (loggedObject.value(QStringLiteral("message")).toString()
            == QStringLiteral("hello"))
            loggedObject.insert(QStringLiteral("token"), QStringLiteral("<oculto>"));
        if (object.value("action") != "keepalive") {
            qInfo().noquote() << "Quansheng LAN TX:"
                              << QJsonDocument(loggedObject).toJson(QJsonDocument::Compact);
        }
        m_socket->write(payload);
        m_socket->write("\n");
    }
}

void QuanshengClient::processLine(const QByteArray &line)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning() << "Quansheng LAN JSON inválido:" << parseError.errorString();
        setError(QStringLiteral("JSON LAN inválido"));
        return;
    }

    const QJsonObject object = document.object();
    const QString message = object.value(QStringLiteral("message")).toString();
    if (message == QStringLiteral("display_state")
        && object.value(QStringLiteral("squelchLevel")).isDouble()) {
        const int level = object.value(QStringLiteral("squelchLevel")).toInt(-1);
        if (level >= 0 && level <= 9)
            m_squelchLevel = level;
    }
    if (message == QStringLiteral("display_state"))
        finishRadioControlWait();
    if (message == QStringLiteral("welcome")) {
        m_toneControlAvailable = object.value("toneControlAvailable").toBool();
        qInfo() << "Quansheng LAN welcome recibido";
        m_serialAvailable = object.value(QStringLiteral("serialAvailable")).toBool();
        m_txControlAvailable = object.value(QStringLiteral("txControlAvailable")).toBool();
        m_pttStatus = m_txControlAvailable ? QStringLiteral("PTT disponible")
                                         : QStringLiteral("PTT no habilitado en servidor");
        m_eepromReadAvailable = object.value(QStringLiteral("eepromReadAvailable")).toBool();
        m_frequencyControlAvailable = object.value(QStringLiteral("frequencyControlAvailable")).toBool();
        m_frequencyControlStatus = m_frequencyControlAvailable ? QStringLiteral("Disponible") : QStringLiteral("No disponible");
        m_sourceStatus = object.value(QStringLiteral("source")).toString();
        m_lastEventReceivedAt = QDateTime::currentDateTimeUtc();
        m_eventSilenceSeconds = 0;
        m_eventStreamStalled = false;
        emit stateChanged();
        QJsonObject subscribe;
        subscribe.insert(QStringLiteral("message"), QStringLiteral("subscribe"));
        sendJson(subscribe);
    } else if (message == QStringLiteral("ptt_state") || message == QStringLiteral("ptt_status")) {
        if (object.value("id").toString() != m_pttId || m_pttId.isEmpty()) return;
        const bool active = message == "ptt_state" && object.value("active").toBool();
        if (!active) {
            m_pttTimer.stop();
            m_pttPressed = false;
            m_pttId.clear();
        }
        const QString error = object.value("error").toString();
        const QString reason = object.value("reason").toString();
        if (!error.isEmpty()) m_pttStatus = QStringLiteral("Error PTT: %1").arg(error);
        else if (active) m_pttStatus = QStringLiteral("PTT enviado · TX según radio");
        else if (reason == "released") m_pttStatus = QStringLiteral("PTT liberado");
        else m_pttStatus = QStringLiteral("PTT detenido: %1").arg(reason);
        emit stateChanged();
    } else if (message == QStringLiteral("source_status")) {
        m_sourceStatus = object.value(QStringLiteral("status")).toString();
        if (m_sourceStatus != "listening") {
            releasePtt();
            m_txControlAvailable = false;
            m_toneControlAvailable = false;
            m_toneBusy = m_toneRequestPending = false;
            m_toneState.clear();
            m_toneStates.clear();
            m_toneStatus = QStringLiteral("Fuente serie detenida; tonos sin confirmar");
            m_controlBusy = false;
            m_waitingControlDisplayState = false;
            m_controlSettleTimer.stop();
        }
        if (object.contains(QStringLiteral("error")))
            setError(object.value(QStringLiteral("error")).toString());
        emit stateChanged();
    } else if (message == QStringLiteral("eeprom_status")) {
        const QString status = object.value(QStringLiteral("status")).toString();
        const int bytesRead = object.value(QStringLiteral("bytesRead")).toInt();
        const int totalBytes = object.value(QStringLiteral("totalBytes")).toInt(0x2000);
        m_eepromBusy = status == QStringLiteral("starting") || status == QStringLiteral("reading");
        if (status == QStringLiteral("reading"))
            m_eepromStatus = QStringLiteral("Leyendo: %1 / %2 bytes").arg(bytesRead).arg(totalBytes);
        else if (status == QStringLiteral("complete"))
            m_eepromStatus = QStringLiteral("Lectura completa: %1 bytes").arg(bytesRead);
        else if (status == QStringLiteral("error"))
            m_eepromStatus = QStringLiteral("Error: %1").arg(object.value(QStringLiteral("error")).toString());
        else
            m_eepromStatus = QStringLiteral("Iniciando sesión EEPROM…");
        emit stateChanged();
    } else if (message == QStringLiteral("tone_status")) {
        const QString status = object.value("status").toString();
        if (status == "starting") {
            m_toneRequestPending = false;
            m_toneBusy = true;
            m_controlBusy = true;
            m_toneState.clear();
            m_toneStatus = QStringLiteral("Leyendo/verificando menús de tonos…");
        } else if (status == "complete" || status == "error") {
            m_toneBusy = m_toneRequestPending = false;
            m_controlBusy = false;
            m_toneStatus = status == "complete"
                ? QStringLiteral("Tonos confirmados por lectura de pantalla")
                : object.value("error").toString();
            if (status == "error") m_toneState.clear();
            qInfo().noquote() << "Quansheng: lectura de tonos"
                              << (status == "complete" ? "completada" : "fallida")
                              << "vfo=" << object.value("vfo").toString()
                              << (status == "error" ? object.value("error").toString() : QString());
            appendToneLog(QStringLiteral("RX tone_status %1 vfo=%2%3")
                          .arg(status, object.value("vfo").toString(),
                               status == QStringLiteral("error")
                               ? QStringLiteral(" error=%1").arg(object.value("error").toString())
                               : QString()));
        } else if (status == "rejected") {
            if (m_toneRequestPending && !m_toneBusy) m_controlBusy = false;
            m_toneRequestPending = false;
            m_toneStatus = object.value("error").toString();
            qWarning().noquote() << "Quansheng: lectura de tonos rechazada por el servidor:"
                                 << m_toneStatus << "vfo=" << object.value("vfo").toString();
            appendToneLog(QStringLiteral("RX tone_status rejected vfo=%1 error=%2")
                          .arg(object.value("vfo").toString(), m_toneStatus));
        }
        emit stateChanged();
    } else if (message == QStringLiteral("tone_state")) {
        const auto rx = object.value("rx").toObject(), tx = object.value("tx").toObject();
        const QString vfo = object.value("vfo").toString();
        if ((vfo == "A" || vfo == "B")
            && qdock::validTone(rx.value("type").toInt(-1), rx.value("index").toInt(-1))
            && qdock::validTone(tx.value("type").toInt(-1), tx.value("index").toInt(-1))) {
            // A memory tone read can complete before the server has emitted
            // the normalized frequency. Use the client's current display
            // value for cache identity so the automatic reader stops retrying.
            QJsonObject normalized = object;
            if (normalized.value(QStringLiteral("frequency")).toString().isEmpty()) {
                normalized.insert(QStringLiteral("frequency"),
                                  vfo == QStringLiteral("B")
                                      ? m_vfoBFrequencyText : m_vfoAFrequencyText);
            }
            if (normalized.value(QStringLiteral("memory")).toString().isEmpty()) {
                normalized.insert(QStringLiteral("memory"),
                                  vfo == QStringLiteral("B")
                                      ? m_vfoBMemory : m_vfoAMemory);
            }
            m_toneState = normalized.toVariantMap();
            m_toneStates.insert(vfo, m_toneState);
            appendToneLog(QStringLiteral("RX tone_state vfo=%1 memoria=%2 frecuencia=%3 RX=%4 TX=%5")
                          .arg(vfo, normalized.value("memory").toString(), normalized.value("frequency").toString(),
                               rx.value("text").toString(), tx.value("text").toString()));
        }
        emit stateChanged();
    } else if (message == QStringLiteral("frequency_status") || message == QStringLiteral("vfo_status")) {
        const QString status = object.value(QStringLiteral("status")).toString();
        const bool vfo = message == QStringLiteral("vfo_status");
        if (status == QStringLiteral("starting")) {
            const QString targetVfo = object.value(QStringLiteral("targetVfo")).toString();
            const QString invalidatedVfo = targetVfo == QStringLiteral("A") || targetVfo == QStringLiteral("B")
                ? targetVfo : m_activeVfo;
            m_toneStates.remove(invalidatedVfo);
            m_toneState.clear();
            m_toneStatus = QStringLiteral("Radio modificada; vuelve a leer los tonos");
        }
        if (status == QStringLiteral("starting") || status == QStringLiteral("sent")) {
            m_controlBusy = true;
            m_waitingControlDisplayState = false;
            m_controlSettleTimer.stop();
        } else if (status == QStringLiteral("complete")) {
            m_waitingControlDisplayState = true;
            m_controlBusy = true;
            m_controlSettleTimer.start();
        } else if (status == QStringLiteral("error") && !m_toneBusy) {
            m_controlBusy = false;
            m_waitingControlDisplayState = false;
            m_controlSettleTimer.stop();
        }
        if (status == QStringLiteral("starting"))
            m_frequencyControlStatus = (m_controlOperation.isEmpty()
                ? (vfo ? QStringLiteral("Operación de VFO") : QStringLiteral("Cambio de frecuencia"))
                : m_controlOperation) + QStringLiteral("…");
        else if (status == QStringLiteral("sent"))
            m_frequencyControlStatus = QStringLiteral("%1 · enviando (%2 tramas restantes)…")
                .arg(m_controlOperation.isEmpty() ? QStringLiteral("Operación") : m_controlOperation)
                .arg(object.value(QStringLiteral("framesRemaining")).toInt());
        else if (status == QStringLiteral("complete"))
            m_frequencyControlStatus = QStringLiteral("%1 · completado; esperando radio")
                .arg(m_controlOperation.isEmpty() ? QStringLiteral("Operación") : m_controlOperation);
        else if (status == QStringLiteral("error"))
            m_frequencyControlStatus = QStringLiteral("%1 · error: %2")
                .arg(m_controlOperation.isEmpty() ? QStringLiteral("Operación") : m_controlOperation,
                     object.value(QStringLiteral("error")).toString());
        if (status == QStringLiteral("error")) {
            m_memoryStepPending = false;
            m_memoryStepVfo.clear();
        }
        if (status == QStringLiteral("complete") && m_memoryStepPending) {
            QTimer::singleShot(300, this, &QuanshengClient::retryPendingMemoryToneRead);
        }
        if (status == QStringLiteral("error") && !m_pendingVfoModeTarget.isEmpty()) {
            QString &memory = m_pendingVfoModeTarget == QStringLiteral("A")
                ? m_vfoAMemory : m_vfoBMemory;
            memory = m_pendingVfoModePreviousMemory;
            m_pendingVfoModeTarget.clear();
            m_pendingVfoModePreviousMemory.clear();
        }
        if (status == QStringLiteral("error") && m_pendingRadioControl == QStringLiteral("dual_watch")) {
            m_dualWatch = m_pendingDualWatchPrevious;
            m_pendingRadioControl.clear();
        } else if (status == QStringLiteral("error") && m_pendingRadioControl == QStringLiteral("squelch")) {
            m_squelchLevel = m_pendingSquelchPrevious;
            m_pendingRadioControl.clear();
        }
        emit stateChanged();
    } else if (message == QStringLiteral("eeprom_dump")) {
        m_eepromChannelRows = object.value(QStringLiteral("channels")).toArray().toVariantList();
        m_eepromSettingRows = object.value(QStringLiteral("settings")).toArray().toVariantList();
        const QByteArray data = QByteArray::fromBase64(
            object.value(QStringLiteral("dataBase64")).toString().toLatin1());
        if (data.size() > 0x0e71) {
            const int level = static_cast<uchar>(data.at(0x0e71));
            if (level >= 0 && level <= 9)
                m_squelchLevel = level;
        }
        QStringList lines;
        for (int offset = 0; offset < data.size(); offset += 16) {
            const QByteArray block = data.mid(offset, 16);
            QStringList bytes;
            QString ascii;
            for (char byte : block) {
                const uchar value = static_cast<uchar>(byte);
                bytes.append(QStringLiteral("%1").arg(value, 2, 16, QLatin1Char('0')).toUpper());
                ascii.append(value >= 32 && value <= 126 ? QChar(value) : QChar('.'));
            }
            lines.append(QStringLiteral("%1  %2  |%3|")
                         .arg(offset, 4, 16, QLatin1Char('0')).toUpper()
                         .arg(bytes.join(QLatin1Char(' ')), -47)
                         .arg(ascii));
        }
        m_eepromHexDump = lines.join(QLatin1Char('\n'));
        emit stateChanged();
    } else if (message == QStringLiteral("radio_settings")) {
        if (object.value(QStringLiteral("squelchLevel")).isDouble()) {
            const int level = object.value(QStringLiteral("squelchLevel")).toInt(-1);
            if (level >= 0 && level <= 9)
                m_squelchLevel = level;
        }
        emit stateChanged();
    } else if (message == QStringLiteral("event")) {
        const QJsonObject event = object.value(QStringLiteral("event")).toObject();
        m_lastEventReceivedAt = QDateTime::currentDateTimeUtc();
        m_eventSilenceSeconds = 0;
        m_eventStreamStalled = false;
        ++m_eventCount;
        if (event.contains(QStringLiteral("state"))) {
            m_candidateState = event.value(QStringLiteral("state")).toString();
            if (m_candidateState != QStringLiteral("RX")) {
                m_signalLevel = -1;
                m_signalOver = 0;
            }
        }
        if (event.contains(QStringLiteral("battery_volts")))
            m_batteryVolts = event.value(QStringLiteral("battery_volts")).toDouble();
        const QString text = event.value(QStringLiteral("text")).toString();
        bool printableText = !text.isEmpty() && text.size() <= 32;
        for (const QChar character : text) {
            if (character.unicode() < 0x20 || character.unicode() > 0x7e) {
                printableText = false;
                break;
            }
        }
        if (printableText && (event.value(QStringLiteral("type")).toInt() >= 1
                              && event.value(QStringLiteral("type")).toInt() <= 3))
            m_lastObservationText = text;
        // Compatibility fallback for physical firmware layouts not yet covered
        // by display_state. Normalized updates overwrite these candidates when
        // the server can reconstruct the complete screen.
        bool frequencyOk = false;
        const double frequency = text.toDouble(&frequencyOk);
        const int type = event.value(QStringLiteral("type")).toInt(-1);
        const int field = event.value(QStringLiteral("field")).toInt(-1);
        int lcdX = event.value(QStringLiteral("val1")).toInt(-1);
        int lcdRow = event.value(QStringLiteral("val2")).toInt(-1) + 1;
        while (lcdX > 128) {
            ++lcdRow;
            lcdX -= 128;
        }
        const bool vfoA = lcdRow >= 1 && lcdRow <= 3;
        const bool vfoB = lcdRow >= 4;
        if (printableText && frequencyOk && text.contains(QLatin1Char('.'))
            && frequency >= 18.0 && frequency <= 1300.0) {
            if (vfoA)
                m_vfoAFrequencyText = text;
            else if (vfoB)
                m_vfoBFrequencyText = text;
            m_frequencyText = text;
        }
        static const QStringList modes = {
            QStringLiteral("AM"), QStringLiteral("FM"), QStringLiteral("NFM"),
            QStringLiteral("WFM"), QStringLiteral("USB"), QStringLiteral("LSB"),
            QStringLiteral("CW")};
        if (printableText && field == 2 && modes.contains(text)) {
            if (vfoA) m_vfoAMode = text;
            else if (vfoB) m_vfoBMode = text;
        }
        if (printableText && field == 2
            && (text.startsWith(QLatin1Char('M')) || text.startsWith(QLatin1Char('F')))) {
            if (vfoA) m_vfoAMemory = text;
            else if (vfoB) m_vfoBMemory = text;
        } else if (printableText && field == 7 && !frequencyOk) {
            if (vfoA) m_vfoAName = text;
            else if (vfoB) m_vfoBName = text;
        }
        if (printableText && field == 1
            && (text == QStringLiteral("H") || text == QStringLiteral("M")
                || text == QStringLiteral("L"))) {
            if (vfoA) m_vfoAPower = text;
            else if (vfoB) m_vfoBPower = text;
        }
        m_lastObservationAt = object.value(QStringLiteral("observedAt")).toString();
        m_observationAgeSeconds = 0;
        m_observationFresh = connected();
        m_notificationPending = true;
        if (!m_notifyTimer.isActive())
            m_notifyTimer.start();
    } else if (message == QStringLiteral("rssi_state")) {
        m_rssiRaw = object.value(QStringLiteral("raw")).toInt(-1);
        m_rssiDbmUncorrected = object.value(QStringLiteral("dbmUncorrected")).toInt();
        m_rssiNoise = object.value(QStringLiteral("noise")).toInt(-1);
        m_rssiGlitch = object.value(QStringLiteral("glitch")).toInt(-1);
        emit stateChanged();
    } else if (message == QStringLiteral("register_frequency_state")) {
        const qulonglong frequencyHz = object.value(QStringLiteral("frequencyHz")).toString().toULongLong();
        if (frequencyHz > 0) {
            m_hardwareFrequencyText = QStringLiteral("%1.%2 MHz")
                    .arg(frequencyHz / 1000000)
                    .arg(frequencyHz % 1000000, 6, 10, QLatin1Char('0'));
        }
        emit stateChanged();
    } else if (message == QStringLiteral("register_state")) {
        const qulonglong frequencyHz = object.value(QStringLiteral("frequencyHz")).toString().toULongLong();
        if (frequencyHz > 0) {
            const qulonglong mhz = frequencyHz / 1000000;
            const qulonglong remainder = frequencyHz % 1000000;
            m_hardwareFrequencyText = QStringLiteral("%1.%2 MHz")
                    .arg(mhz).arg(remainder, 6, 10, QLatin1Char('0'));
        }
        m_hardwareRegisterCount = object.value(QStringLiteral("values")).toObject().size();
        const QJsonObject values = object.value(QStringLiteral("values")).toObject();
        const QStringList registerNames{
            QStringLiteral("07"), QStringLiteral("0B"), QStringLiteral("0C"),
            QStringLiteral("10"), QStringLiteral("11"),
            QStringLiteral("12"), QStringLiteral("13"), QStringLiteral("14"),
            QStringLiteral("19"), QStringLiteral("21"), QStringLiteral("24"), QStringLiteral("28"),
            QStringLiteral("29"), QStringLiteral("30"), QStringLiteral("31"),
            QStringLiteral("32"), QStringLiteral("33"),
            QStringLiteral("36"), QStringLiteral("37"), QStringLiteral("38"), QStringLiteral("39"),
            QStringLiteral("43"), QStringLiteral("47"), QStringLiteral("48"), QStringLiteral("49"),
            QStringLiteral("4D"), QStringLiteral("4E"), QStringLiteral("4F"), QStringLiteral("50"),
            QStringLiteral("51"), QStringLiteral("52"), QStringLiteral("65"), QStringLiteral("67"),
            QStringLiteral("68"), QStringLiteral("69"), QStringLiteral("6A"),
            QStringLiteral("63"), QStringLiteral("64"), QStringLiteral("6F"),
            QStringLiteral("70"), QStringLiteral("71"), QStringLiteral("72"),
            QStringLiteral("73"), QStringLiteral("78"), QStringLiteral("7B"),
            QStringLiteral("7C"), QStringLiteral("7D"), QStringLiteral("7E")};
        QStringList rawRegisters;
        for (const QString &name : registerNames) {
            const QString value = QString::number(values.value(name).toInt(), 16)
                    .rightJustified(4, QLatin1Char('0')).toUpper();
            rawRegisters << name + QLatin1Char('=') + value;
        }
        m_hardwareRegistersRawText = rawRegisters.join(QStringLiteral("   "));
        const QJsonObject functions = object.value(QStringLiteral("functions")).toObject();
        QStringList enabledFunctions;
        if (functions.value(QStringLiteral("vox")).toBool()) enabledFunctions << QStringLiteral("VOX");
        if (functions.value(QStringLiteral("scrambler")).toBool()) enabledFunctions << QStringLiteral("scrambler");
        if (functions.value(QStringLiteral("compander")).toBool()) enabledFunctions << QStringLiteral("compander");
        m_hardwareFunctionsText = enabledFunctions.isEmpty() ? QStringLiteral("ninguna activa")
                                                              : enabledFunctions.join(QStringLiteral(" · "));
        const QJsonObject gpio = object.value(QStringLiteral("gpio")).toObject();
        QStringList enabledGpio;
        if (gpio.value(QStringLiteral("rxEnable")).toBool()) enabledGpio << QStringLiteral("RX");
        if (gpio.value(QStringLiteral("paEnable")).toBool()) enabledGpio << QStringLiteral("PA");
        if (gpio.value(QStringLiteral("uhfLna")).toBool()) enabledGpio << QStringLiteral("LNA UHF");
        if (gpio.value(QStringLiteral("vhfLna")).toBool()) enabledGpio << QStringLiteral("LNA VHF");
        if (gpio.value(QStringLiteral("redLed")).toBool()) enabledGpio << QStringLiteral("LED rojo");
        if (gpio.value(QStringLiteral("greenLed")).toBool()) enabledGpio << QStringLiteral("LED verde");
        m_hardwareGpioText = enabledGpio.isEmpty() ? QStringLiteral("ninguna línea activa")
                                                   : enabledGpio.join(QStringLiteral(" · "));
        const QJsonObject audio = object.value(QStringLiteral("audio")).toObject();
        const QStringList audioOutputs{QStringLiteral("mute"), QStringLiteral("FM"), QStringLiteral("alarma"),
            QStringLiteral("beep"), QStringLiteral("RAW"), QStringLiteral("USB"), QStringLiteral("CTCSS"),
            QStringLiteral("AM"), QStringLiteral("FSK"), QStringLiteral("BYP")};
        const int output = audio.value(QStringLiteral("output")).toInt();
        const QString outputName = output >= 0 && output < audioOutputs.size()
                ? audioOutputs.at(output) : QStringLiteral("ruta %1").arg(output);
        m_hardwareAudioText = QStringLiteral("%1 · G1 %2 · G2 %3 · DAC %4")
                .arg(outputName).arg(audio.value(QStringLiteral("gain1")).toInt())
                .arg(audio.value(QStringLiteral("gain2")).toInt())
                .arg(audio.value(QStringLiteral("dacGain")).toInt());
        const QJsonObject rfAgc = object.value(QStringLiteral("rfAgc")).toObject();
        const int loMode = rfAgc.value(QStringLiteral("loMode")).toInt();
        m_hardwareRfAgcText = QStringLiteral("LO %1 · umbral alto %2 · bajo %3")
                .arg(loMode < 2 ? QStringLiteral("auto") : loMode == 2 ? QStringLiteral("bajo") : QStringLiteral("alto"))
                .arg(rfAgc.value(QStringLiteral("highThreshold")).toInt())
                .arg(rfAgc.value(QStringLiteral("lowThreshold")).toInt());
        const QJsonObject filter = object.value(QStringLiteral("filter")).toObject();
        const QStringList rfWidths{QStringLiteral("1.70"), QStringLiteral("2.00"),
            QStringLiteral("2.50"), QStringLiteral("3.00"), QStringLiteral("3.75"),
            QStringLiteral("4.00"), QStringLiteral("4.25"), QStringLiteral("4.50")};
        const int bandwidthMode = filter.value(QStringLiteral("bandwidthMode")).toInt();
        const QString channelWidth = bandwidthMode == 0 ? QStringLiteral("12.5 kHz")
                : bandwidthMode == 1 ? QStringLiteral("6.25 kHz")
                : bandwidthMode == 2 ? QStringLiteral("25/20 kHz") : QStringLiteral("modo %1").arg(bandwidthMode);
        const int rfIndex = filter.value(QStringLiteral("rf")).toInt();
        const int weakIndex = filter.value(QStringLiteral("weakRf")).toInt();
        const QString multiplier = filter.value(QStringLiteral("doubleRf")).toBool() ? QStringLiteral(" ×2") : QString();
        m_hardwareFilterText = QStringLiteral("%1 · RF %2%3 kHz · débil %4%3 kHz")
                .arg(channelWidth).arg(rfWidths.value(rfIndex)).arg(multiplier).arg(rfWidths.value(weakIndex));
        const QJsonObject squelch = object.value(QStringLiteral("squelch")).toObject();
        m_hardwareSquelchText = QStringLiteral("RSSI %1/%2 · ruido %3/%4 · glitch %5/%6 · retardo %7/%8")
                .arg(squelch.value(QStringLiteral("openRssi")).toInt())
                .arg(squelch.value(QStringLiteral("closeRssi")).toInt())
                .arg(squelch.value(QStringLiteral("openNoise")).toInt())
                .arg(squelch.value(QStringLiteral("closeNoise")).toInt())
                .arg(squelch.value(QStringLiteral("openGlitch")).toInt())
                .arg(squelch.value(QStringLiteral("closeGlitch")).toInt())
                .arg(squelch.value(QStringLiteral("openDelay")).toInt())
                .arg(squelch.value(QStringLiteral("closeDelay")).toInt());
        const QJsonObject pa = object.value(QStringLiteral("pa")).toObject();
        m_hardwarePaText = QStringLiteral("%1 · bias %2 · G1 %3 · G2 %4")
                .arg(pa.value(QStringLiteral("enabled")).toBool() ? QStringLiteral("activo") : QStringLiteral("inactivo"))
                .arg(pa.value(QStringLiteral("bias")).toInt())
                .arg(pa.value(QStringLiteral("gain1")).toInt())
                .arg(pa.value(QStringLiteral("gain2")).toInt());
        const QJsonObject css = object.value(QStringLiteral("css")).toObject();
        m_hardwareCssText = QStringLiteral("%1 · %2 · ganancia TX %3 · umbral %4/%5 · cola %6")
                .arg(css.value(QStringLiteral("enabled")).toBool() ? QStringLiteral("activo") : QStringLiteral("inactivo"))
                .arg(css.value(QStringLiteral("mode")).toString())
                .arg(css.value(QStringLiteral("txGain")).toInt())
                .arg(css.value(QStringLiteral("foundThreshold")).toInt())
                .arg(css.value(QStringLiteral("lostThreshold")).toInt())
                .arg(css.value(QStringLiteral("tailEnabled")).toBool() ? QString::number(css.value(QStringLiteral("tailMode")).toInt()) : QStringLiteral("no"));
        const QJsonObject tones = object.value(QStringLiteral("tones")).toObject();
        m_hardwareTonesText = QStringLiteral("Tone1 %1/%2 · Tone2 %3/%4")
                .arg(tones.value(QStringLiteral("tone1Enabled")).toBool() ? QStringLiteral("activo") : QStringLiteral("off"))
                .arg(tones.value(QStringLiteral("tone1Gain")).toInt())
                .arg(tones.value(QStringLiteral("tone2Enabled")).toBool() ? QStringLiteral("activo") : QStringLiteral("off"))
                .arg(tones.value(QStringLiteral("tone2Gain")).toInt());
        const QJsonObject advanced = object.value(QStringLiteral("advanced")).toObject();
        const QJsonObject blocks = object.value(QStringLiteral("blocks")).toObject();
        QStringList activeBlocks;
        if (blocks.value(QStringLiteral("rxDsp")).toBool()) activeBlocks << QStringLiteral("RX DSP");
        if (blocks.value(QStringLiteral("txDsp")).toBool()) activeBlocks << QStringLiteral("TX DSP");
        if (blocks.value(QStringLiteral("afDac")).toBool()) activeBlocks << QStringLiteral("AF");
        if (blocks.value(QStringLiteral("discriminator")).toBool()) activeBlocks << QStringLiteral("DISC");
        if (blocks.value(QStringLiteral("paGain")).toBool()) activeBlocks << QStringLiteral("PA");
        if (blocks.value(QStringLiteral("micAdc")).toBool()) activeBlocks << QStringLiteral("MIC");
        if (blocks.value(QStringLiteral("vcoCalibration")).toBool()) activeBlocks << QStringLiteral("VCO cal");
        activeBlocks << QStringLiteral("RX link %1").arg(blocks.value(QStringLiteral("rxLink")).toInt());
        activeBlocks << QStringLiteral("PLL %1").arg(blocks.value(QStringLiteral("pllVco")).toInt());
        m_hardwareBlocksText = activeBlocks.join(QStringLiteral(" · "))
                + QStringLiteral(" (0x%1)").arg(QString::number(values.value(QStringLiteral("30")).toInt(), 16).rightJustified(4, QLatin1Char('0')).toUpper());
        const QJsonObject agc = object.value(QStringLiteral("agc")).toObject();
        m_hardwareAgcText = QStringLiteral("%1 · índice %2 · nivel %3 · DC RX %4 / TX %5 (0x%6)")
                .arg(agc.value(QStringLiteral("mode")).toString())
                .arg(agc.value(QStringLiteral("gainIndex")).toInt())
                .arg(agc.value(QStringLiteral("signalStrength")).toInt())
                .arg(agc.value(QStringLiteral("rxDcFilter")).toInt())
                .arg(agc.value(QStringLiteral("txDcFilter")).toInt())
                .arg(QString::number(values.value(QStringLiteral("7E")).toInt(), 16).rightJustified(4, QLatin1Char('0')).toUpper());
        m_hardwareAfcText = QStringLiteral("%1 (0x%2)")
                .arg(object.value(QStringLiteral("afcEnabled")).toBool() ? QStringLiteral("activa") : QStringLiteral("desactivada"))
                .arg(QString::number(values.value(QStringLiteral("73")).toInt(), 16).rightJustified(4, QLatin1Char('0')).toUpper());
        const QStringList ratios{QStringLiteral("off"), QStringLiteral("1.333:1"),
                                 QStringLiteral("2:1"), QStringLiteral("4:1")};
        const QStringList expandRatios{QStringLiteral("off"), QStringLiteral("1:2"),
                                       QStringLiteral("1:3"), QStringLiteral("1:4")};
        m_hardwareRegisterRows = emptyHardwareRegisterRows();
        const auto addRegister = [&](const QString &name, const QString &interpretation) {
            bool addressOk = false;
            const int address = name.toInt(&addressOk, 16);
            if (!addressOk || address < 0 || address >= m_hardwareRegisterRows.size()
                || !values.contains(name)) {
                return;
            }
            m_hardwareRegisterRows[address] = QVariantMap{
                {QStringLiteral("register"), QStringLiteral("0x") + name},
                {QStringLiteral("value"), QStringLiteral("0x") + QString::number(values.value(name).toInt(), 16).rightJustified(4, QLatin1Char('0')).toUpper()},
                {QStringLiteral("interpretation"), interpretation}};
        };
        const auto registerValue = [&](const QString &name) {
            return values.value(name).toInt();
        };
        const int toneControl = registerValue(QStringLiteral("07"));
        const int toneMode = (toneControl >> 13) & 0x07;
        const QStringList toneModes{QStringLiteral("CTCSS 1"), QStringLiteral("CTCSS 2"),
                                    QStringLiteral("CDCSS"), QStringLiteral("reservado"),
                                    QStringLiteral("reservado"), QStringLiteral("reservado"),
                                    QStringLiteral("reservado"), QStringLiteral("reservado")};
        addRegister(QStringLiteral("07"), QStringLiteral("%1 · palabra de tono %2")
                    .arg(toneModes.value(toneMode)).arg(toneControl & 0x1fff));
        const int detectedDtmf = registerValue(QStringLiteral("0B"));
        addRegister(QStringLiteral("0B"), QStringLiteral("Código DTMF/5-tone detectado: %1")
                    .arg((detectedDtmf >> 8) & 0x0f));
        const int detectedCss = registerValue(QStringLiteral("0C"));
        const QStringList cssCodeTypes{QStringLiteral("positivo"), QStringLiteral("negativo"),
                                       QStringLiteral("reservado 2"), QStringLiteral("reservado 3")};
        addRegister(QStringLiteral("0C"), QStringLiteral("CDCSS %1 · desplazamiento %2 · tipo CTCSS %3")
                    .arg(cssCodeTypes.value((detectedCss >> 14) & 0x03))
                    .arg((detectedCss >> 12) & 0x03).arg((detectedCss >> 10) & 0x03));
        addRegister(QStringLiteral("10"), QStringLiteral("Tabla de ganancia AGC · índice 0"));
        addRegister(QStringLiteral("11"), QStringLiteral("Tabla de ganancia AGC · índice 1"));
        addRegister(QStringLiteral("12"), QStringLiteral("Tabla de ganancia AGC · índice 2"));
        addRegister(QStringLiteral("13"), QStringLiteral("Tabla de ganancia AGC · índice 3 (máximo)"));
        addRegister(QStringLiteral("14"), QStringLiteral("Tabla de ganancia AGC · índice -1 (mínimo)"));
        addRegister(QStringLiteral("19"), advanced.value(QStringLiteral("micAgc")).toBool() ? QStringLiteral("AGC micrófono activo") : QStringLiteral("AGC micrófono desactivado"));
        addRegister(QStringLiteral("21"), QStringLiteral("Configuración base detector DTMF · desglose pendiente"));
        const int dtmf = registerValue(QStringLiteral("24"));
        m_hardwareDtmfText = QStringLiteral("%1 · %2 · umbral %3 · código %4")
                .arg(dtmf & 0x0010 ? QStringLiteral("DTMF") : QStringLiteral("SelCall"))
                .arg(dtmf & 0x0020 ? QStringLiteral("activo") : QStringLiteral("inactivo"))
                .arg((dtmf >> 7) & 0xff).arg((detectedDtmf >> 8) & 0x0f);
        addRegister(QStringLiteral("24"), QStringLiteral("Detector %1 · %2 · umbral %3 · máx. %4 símbolos")
                    .arg(dtmf & 0x0010 ? QStringLiteral("DTMF") : QStringLiteral("SelCall"))
                    .arg(dtmf & 0x0020 ? QStringLiteral("activo") : QStringLiteral("inactivo"))
                    .arg((dtmf >> 7) & 0xff).arg(dtmf & 0x0f));
        addRegister(QStringLiteral("28"), QStringLiteral("Expansor RX %1; punto %2, ruido %3")
                    .arg(expandRatios.value(advanced.value(QStringLiteral("rxExpandRatio")).toInt()))
                    .arg(advanced.value(QStringLiteral("rxExpandPoint")).toInt()).arg(advanced.value(QStringLiteral("rxExpandNoise")).toInt()));
        addRegister(QStringLiteral("29"), QStringLiteral("Compresor TX %1; punto %2, ruido %3")
                    .arg(ratios.value(advanced.value(QStringLiteral("txCompressRatio")).toInt()))
                    .arg(advanced.value(QStringLiteral("txCompressPoint")).toInt()).arg(advanced.value(QStringLiteral("txCompressNoise")).toInt()));
        addRegister(QStringLiteral("30"), m_hardwareBlocksText);
        addRegister(QStringLiteral("31"), m_hardwareFunctionsText);
        const int scan = registerValue(QStringLiteral("32"));
        m_hardwareScanText = QStringLiteral("%1 · tiempo %2")
                .arg(scan & 0x0001 ? QStringLiteral("activo") : QStringLiteral("inactivo"))
                .arg((scan >> 14) & 0x03);
        addRegister(QStringLiteral("32"), QStringLiteral("Escáner de frecuencia %1 · tiempo %2")
                    .arg(scan & 0x0001 ? QStringLiteral("activo") : QStringLiteral("inactivo"))
                    .arg((scan >> 14) & 0x03));
        addRegister(QStringLiteral("33"), m_hardwareGpioText);
        addRegister(QStringLiteral("36"), m_hardwarePaText);
        addRegister(QStringLiteral("37"), QStringLiteral("Configuración interna sin desglose confirmado"));
        addRegister(QStringLiteral("38"), QStringLiteral("Frecuencia: palabra baja"));
        addRegister(QStringLiteral("39"), QStringLiteral("Frecuencia: palabra alta"));
        addRegister(QStringLiteral("3D"), advanced.value(QStringLiteral("ifValue")).toInt() == 0 ? QStringLiteral("IF USB") : QStringLiteral("IF/configuración de modulación"));
        addRegister(QStringLiteral("43"), m_hardwareFilterText);
        addRegister(QStringLiteral("46"), QStringLiteral("Umbral apertura VOX %1").arg(advanced.value(QStringLiteral("voxOpen")).toInt()));
        addRegister(QStringLiteral("47"), QStringLiteral("Ruta de audio: %1").arg(outputName));
        addRegister(QStringLiteral("48"), m_hardwareAudioText);
        addRegister(QStringLiteral("49"), m_hardwareRfAgcText);
        addRegister(QStringLiteral("4D"), QStringLiteral("Squelch: glitch de cierre %1").arg(squelch.value(QStringLiteral("closeGlitch")).toInt()));
        addRegister(QStringLiteral("4E"), QStringLiteral("Squelch: glitch apertura %1; retardos %2/%3").arg(squelch.value(QStringLiteral("openGlitch")).toInt()).arg(squelch.value(QStringLiteral("openDelay")).toInt()).arg(squelch.value(QStringLiteral("closeDelay")).toInt()));
        addRegister(QStringLiteral("4F"), QStringLiteral("Squelch: ruido apertura/cierre %1/%2").arg(squelch.value(QStringLiteral("openNoise")).toInt()).arg(squelch.value(QStringLiteral("closeNoise")).toInt()));
        addRegister(QStringLiteral("50"), registerValue(QStringLiteral("50")) & 0x8000
                    ? QStringLiteral("Audio TX silenciado") : QStringLiteral("Audio TX no silenciado"));
        addRegister(QStringLiteral("51"), m_hardwareCssText);
        addRegister(QStringLiteral("52"), QStringLiteral("CTCSS: cola y umbrales %1/%2").arg(css.value(QStringLiteral("foundThreshold")).toInt()).arg(css.value(QStringLiteral("lostThreshold")).toInt()));
        addRegister(QStringLiteral("63"), QStringLiteral("Indicador glitch %1").arg(registerValue(QStringLiteral("63")) & 0xff));
        addRegister(QStringLiteral("64"), QStringLiteral("Amplitud voz/VOX %1").arg(registerValue(QStringLiteral("64")) & 0x7fff));
        addRegister(QStringLiteral("65"), QStringLiteral("Indicador de ruido; pendiente de validar"));
        addRegister(QStringLiteral("67"), QStringLiteral("RSSI de registro; pendiente de validar"));
        addRegister(QStringLiteral("68"), QStringLiteral("Medición interna; pendiente"));
        addRegister(QStringLiteral("69"), QStringLiteral("Medición interna; pendiente"));
        addRegister(QStringLiteral("6A"), QStringLiteral("Medición interna; pendiente"));
        addRegister(QStringLiteral("6F"), QStringLiteral("Nivel AF TX/RX %1").arg(registerValue(QStringLiteral("6F")) & 0x3f));
        addRegister(QStringLiteral("70"), m_hardwareTonesText);
        addRegister(QStringLiteral("71"), QStringLiteral("Tone1 · palabra %1 · aprox. %2 Hz")
                    .arg(registerValue(QStringLiteral("71")))
                    .arg(registerValue(QStringLiteral("71")) / 10.3244, 0, 'f', 1));
        addRegister(QStringLiteral("72"), QStringLiteral("Tone2 · palabra %1 · aprox. %2 Hz")
                    .arg(registerValue(QStringLiteral("72")))
                    .arg(registerValue(QStringLiteral("72")) / 10.3244, 0, 'f', 1));
        addRegister(QStringLiteral("73"), m_hardwareAfcText);
        addRegister(QStringLiteral("78"), QStringLiteral("Squelch: RSSI apertura/cierre %1/%2").arg(squelch.value(QStringLiteral("openRssi")).toInt()).arg(squelch.value(QStringLiteral("closeRssi")).toInt()));
        addRegister(QStringLiteral("79"), QStringLiteral("Umbral cierre VOX %1").arg(advanced.value(QStringLiteral("voxClose")).toInt()));
        addRegister(QStringLiteral("7A"), QStringLiteral("Código de retardo VOX %1").arg(advanced.value(QStringLiteral("voxDelayCode")).toInt()));
        addRegister(QStringLiteral("7B"), QStringLiteral("Tabla/configuración RSSI 0"));
        addRegister(QStringLiteral("7C"), QStringLiteral("Tabla/configuración RSSI 1"));
        addRegister(QStringLiteral("7D"), QStringLiteral("Configuración AGC/RSSI; desglose pendiente"));
        addRegister(QStringLiteral("7E"), m_hardwareAgcText);
        emit stateChanged();
    } else if (message == QStringLiteral("display_state")) {
        const QJsonObject a = object.value(QStringLiteral("vfoA")).toObject();
        const QJsonObject b = object.value(QStringLiteral("vfoB")).toObject();
        const QJsonObject indicators = object.value(QStringLiteral("indicators")).toObject();
        m_charging = indicators.value(QStringLiteral("charging")).toBool();
        if (indicators.contains(QStringLiteral("dualWatch"))) {
            const bool observedDualWatch = indicators.value(QStringLiteral("dualWatch")).toBool();
            if (m_pendingRadioControl != QStringLiteral("dual_watch")
                || observedDualWatch != m_pendingDualWatchPrevious) {
                m_dualWatch = observedDualWatch;
                m_dualWatchKnown = true;
                if (m_pendingRadioControl == QStringLiteral("dual_watch"))
                    m_pendingRadioControl.clear();
            }
        }
        const auto updateIfPresent = [](QString &target, const QJsonObject &source,
                                        const QString &key) {
            const QString value = source.value(key).toString();
            if (!value.isEmpty())
                target = value;
        };
        const QString active = object.value(QStringLiteral("activeVfo")).toString();
        if (!active.isEmpty())
            m_activeVfo = active;
        updateIfPresent(m_vfoAFrequencyText, a, QStringLiteral("frequencyText"));
        updateIfPresent(m_vfoBFrequencyText, b, QStringLiteral("frequencyText"));
        const auto updateMemory = [this](QString &target, const QJsonObject &source,
                                         const QString &vfo) {
            const QString value = source.value(QStringLiteral("memory")).toString();
            if (value.isEmpty())
                return;
            // Durante el redibujado pueden llegar restos del modo anterior.
            // Mantener el estado provisional hasta observar un valor distinto.
            if (m_pendingVfoModeTarget == vfo
                && value == m_pendingVfoModePreviousMemory)
                return;
            target = value;
            if (m_pendingVfoModeTarget == vfo) {
                m_pendingVfoModeTarget.clear();
                m_pendingVfoModePreviousMemory.clear();
            }
        };
        updateMemory(m_vfoAMemory, a, QStringLiteral("A"));
        updateMemory(m_vfoBMemory, b, QStringLiteral("B"));
        if (!m_toneBusy) {
            bool invalidated = false;
            const auto invalidateIfChanged = [this, &invalidated](const QString &vfo, const QString &frequency,
                                                     const QString &) {
                const QVariantMap state = m_toneStates.value(vfo).toMap();
                if (state.isEmpty() || frequency.isEmpty()
                    || state.value("frequency").toString().isEmpty())
                    return;
                // La etiqueta de memoria puede llegar en un display_state
                // distinto durante la navegación de los menús de tonos.
                if (state.value("frequency").toString() != frequency) {
                    m_toneStates.remove(vfo);
                    invalidated = true;
                }
            };
            invalidateIfChanged(QStringLiteral("A"), m_vfoAFrequencyText, m_vfoAMemory);
            invalidateIfChanged(QStringLiteral("B"), m_vfoBFrequencyText, m_vfoBMemory);
            m_toneState = m_toneStates.value(m_activeVfo).toMap();
            if (m_toneState.isEmpty() && invalidated)
                m_toneStatus = QStringLiteral("VFO/canal cambiado; vuelve a leer los tonos");
        }
        updateIfPresent(m_vfoAName, a, QStringLiteral("name"));
        updateIfPresent(m_vfoBName, b, QStringLiteral("name"));
        updateIfPresent(m_vfoAMode, a, QStringLiteral("mode"));
        updateIfPresent(m_vfoBMode, b, QStringLiteral("mode"));
        updateIfPresent(m_vfoAPower, a, QStringLiteral("power"));
        updateIfPresent(m_vfoBPower, b, QStringLiteral("power"));
        updateIfPresent(m_vfoAStep, a, QStringLiteral("step"));
        updateIfPresent(m_vfoBStep, b, QStringLiteral("step"));
        const int batteryPercent = indicators.value(QStringLiteral("batteryPercent")).toInt(-1);
        if (batteryPercent >= 0) m_batteryPercent = batteryPercent;
        if (indicators.contains(QStringLiteral("signalLevel"))) {
            m_signalLevel = indicators.value(QStringLiteral("signalLevel")).toInt(-1);
            m_signalOver = indicators.value(QStringLiteral("signalOver")).toInt();
        }
        const auto updateIndicator = [&](QString &target, const QString &key) {
            const QString value = indicators.value(key).toString();
            if (!value.isEmpty()) target = value;
        };
        updateIndicator(m_stepText, QStringLiteral("step"));
        updateIndicator(m_toneIndicator, QStringLiteral("tone"));
        updateIndicator(m_lastDtmf, QStringLiteral("lastDtmf"));
        QStringList activeIndicators;
        const auto addFlag = [&](const char *key, const QString &label) {
            if (indicators.value(QLatin1String(key)).toBool()) activeIndicators.append(label);
        };
        addFlag("noa", QStringLiteral("NOA"));
        addFlag("dtmf", QStringLiteral("DTMF"));
        addFlag("broadcastFm", QStringLiteral("FM"));
        addFlag("scan", QStringLiteral("SCAN"));
        addFlag("dualWatch", QStringLiteral("DWR"));
        addFlag("crossBand", QStringLiteral("><"));
        addFlag("xb", QStringLiteral("XB"));
        addFlag("vox", QStringLiteral("VOX"));
        addFlag("locked", QStringLiteral("LOCK"));
        addFlag("function", QStringLiteral("F"));
        const QString statusCode = indicators.value(QStringLiteral("statusCode")).toString();
        if (!statusCode.isEmpty()) activeIndicators.append(statusCode);
        m_indicatorsText = activeIndicators.join(QStringLiteral(" · "));
        m_frequencyText = m_activeVfo == QStringLiteral("B")
            ? m_vfoBFrequencyText : m_vfoAFrequencyText;
        emit stateChanged();
        // Memory changes are reported as display_state events. Read the live
        // menu values once the new channel is visible, including on entry to
        // memory mode and after every channel step.
        readMemoryTonesIfNeeded();
        if (m_memoryStepPending) {
            QTimer::singleShot(400, this, &QuanshengClient::retryPendingMemoryToneRead);
        }
    } else if (message == QStringLiteral("stats")) {
        m_bytesReceived = object.value(QStringLiteral("bytes")).toString().toULongLong();
        m_discardedBytes = object.value(QStringLiteral("discarded")).toString().toULongLong();
        m_pendingBytes = object.value(QStringLiteral("pending")).toString().toInt();
        emit countersChanged();
    } else if (message == QStringLiteral("error")) {
        setError(object.value(QStringLiteral("code")).toString());
        qWarning() << "Quansheng LAN servidor rechazó:" << m_error;
    } else if (object.contains(QStringLiteral("error"))) {
        setError(object.value(QStringLiteral("error")).toString());
    }
}

void QuanshengClient::setError(const QString &error)
{
    if (error == m_error)
        return;
    m_error = error;
    emit errorChanged();
}

void QuanshengClient::pressPtt()
{
    if (m_shuttingDown || m_pttPressed || !connected() || !m_txControlAvailable
        || m_sourceStatus != "listening" || m_controlBusy || m_eepromBusy) return;
    m_pttId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_pttPressed = true;
    m_pttStatus = QStringLiteral("Solicitando PTT…");
    sendJson({{"message", "ptt"}, {"action", "press"}, {"id", m_pttId}});
    m_pttTimer.start();
    emit stateChanged();
}

void QuanshengClient::releasePtt()
{
    m_pttTimer.stop();
    if (!m_pttPressed) return;
    m_pttPressed = false;
    const QString memory = m_activeVfo == QStringLiteral("B") ? m_vfoBMemory : m_vfoAMemory;
    if (memory == QStringLiteral("Memoria") || memory.startsWith(QLatin1Char('M'))) {
        m_skipMemoryToneReadAfterPttRelease = true;
        QTimer::singleShot(1000, this, [this] {
            m_skipMemoryToneReadAfterPttRelease = false;
        });
    }
    sendJson({{"message", "ptt"}, {"action", "release"}, {"id", m_pttId}});
    m_pttStatus = QStringLiteral("Solicitando liberar PTT…");
    emit stateChanged();
}
