#include "quanshengclient.h"

#include <QAbstractSocket>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QSettings>
#include <QTcpSocket>

QuanshengClient::QuanshengClient(QObject *parent)
    : QObject(parent), m_socket(new QTcpSocket(this))
{
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
        if (m_lastObservationAt.isEmpty())
            return;
        const QDateTime observed = QDateTime::fromString(
            m_lastObservationAt, Qt::ISODateWithMs);
        if (!observed.isValid())
            return;
        const int age = qMax(0, observed.secsTo(QDateTime::currentDateTimeUtc()));
        const bool fresh = age <= 5 && connected();
        if (age != m_observationAgeSeconds || fresh != m_observationFresh) {
            m_observationAgeSeconds = age;
            m_observationFresh = fresh;
            emit stateChanged();
        }
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
    m_reconnectRequested = true;
    setError(QString());
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->abort();
    m_buffer.clear();
    m_sourceStatus = QStringLiteral("conectando");
    m_serialAvailable = false;
    m_frequencyText.clear();
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
    m_shuttingDown = true;
    m_reconnectRequested = false;
    m_reconnectTimer.stop();
    m_observationTimer.stop();
    m_notifyTimer.stop();
    m_notificationPending = false;
    if (m_socket) {
        m_socket->disconnect(this);
        m_socket->abort();
    }
}

void QuanshengClient::disconnectFromServer()
{
    m_reconnectRequested = false;
    m_reconnectTimer.stop();
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->disconnectFromHost();
    m_sourceStatus = QStringLiteral("desconectado");
    m_serialAvailable = false;
    m_observationFresh = false;
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
    setError(m_socket->errorString());
    m_sourceStatus = QStringLiteral("error");
    emit stateChanged();
}

void QuanshengClient::onDisconnected()
{
    if (m_shuttingDown)
        return;
    qInfo() << "Quansheng LAN desconectado";
    emit connectedChanged();
    m_sourceStatus = QStringLiteral("desconectado");
    m_serialAvailable = false;
    m_observationFresh = false;
    emit stateChanged();
    if (m_reconnectRequested && m_autoReconnect && !m_reconnectTimer.isActive())
        m_reconnectTimer.start();
}

void QuanshengClient::sendJson(const QJsonObject &object)
{
    if (m_socket->state() == QAbstractSocket::ConnectedState) {
        const QByteArray payload = QJsonDocument(object).toJson(QJsonDocument::Compact);
        qInfo().noquote() << "Quansheng LAN TX:" << payload;
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
    if (message == QStringLiteral("welcome")) {
        qInfo() << "Quansheng LAN welcome recibido";
        m_serialAvailable = object.value(QStringLiteral("serialAvailable")).toBool();
        m_txControlAvailable = object.value(QStringLiteral("txControlAvailable")).toBool();
        m_sourceStatus = object.value(QStringLiteral("source")).toString();
        emit stateChanged();
        QJsonObject subscribe;
        subscribe.insert(QStringLiteral("message"), QStringLiteral("subscribe"));
        sendJson(subscribe);
    } else if (message == QStringLiteral("source_status")) {
        m_sourceStatus = object.value(QStringLiteral("status")).toString();
        if (object.contains(QStringLiteral("error")))
            setError(object.value(QStringLiteral("error")).toString());
        emit stateChanged();
    } else if (message == QStringLiteral("event")) {
        const QJsonObject event = object.value(QStringLiteral("event")).toObject();
        ++m_eventCount;
        if (event.contains(QStringLiteral("state")))
            m_candidateState = event.value(QStringLiteral("state")).toString();
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
        if (frequencyOk && text.contains(QLatin1Char('.'))
            && frequency >= 20.0 && frequency <= 1000.0) {
            // A frequency is identified by its numeric LCD text and row. The
            // firmware uses different UI packet types/fields for memory and
            // VFO screens, so the row is the stable discriminator here.
            if (vfoA) {
                m_vfoAFrequencyText = text;
                if (type == 1 && field == 9)
                    m_vfoAMemory = QStringLiteral("Memoria");
                else if (type == 3 && field == 7)
                    m_vfoAMemory = QStringLiteral("VFO");
            } else if (vfoB) {
                m_vfoBFrequencyText = text;
                if (type == 1 && field == 9)
                    m_vfoBMemory = QStringLiteral("Memoria");
                else if (type == 3 && field == 7)
                    m_vfoBMemory = QStringLiteral("VFO");
            }
            m_frequencyText = text;
        }
        if (field == 2 && (text == QStringLiteral("AM")
                           || text == QStringLiteral("FM")
                           || text == QStringLiteral("NFM")
                           || text == QStringLiteral("WFM")
                           || text == QStringLiteral("USB")
                           || text == QStringLiteral("LSB")
                           || text == QStringLiteral("CW"))) {
            if (vfoA)
                m_vfoAMode = text;
            else if (vfoB)
                m_vfoBMode = text;
        }
        if (field == 2 && (text.startsWith(QLatin1Char('M'))
                           || text.startsWith(QLatin1Char('F')))) {
            if (vfoA)
                m_vfoAMemory = text;
            else if (vfoB)
                m_vfoBMemory = text;
        }
        else if (field == 7 && !text.isEmpty() && !frequencyOk) {
            if (vfoA)
                m_vfoAName = text;
            else if (vfoB)
                m_vfoBName = text;
        }
        if (field == 1 && (text == QStringLiteral("H")
                           || text == QStringLiteral("M")
                           || text == QStringLiteral("L"))) {
            if (vfoA)
                m_vfoAPower = text;
            else if (vfoB)
                m_vfoBPower = text;
        }
        m_lastObservationAt = object.value(QStringLiteral("observedAt")).toString();
        m_observationAgeSeconds = 0;
        m_observationFresh = connected();
        m_notificationPending = true;
        if (!m_notifyTimer.isActive())
            m_notifyTimer.start();
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
