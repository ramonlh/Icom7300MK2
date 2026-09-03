#include "remoteserver.h"

#include "radiocontroller.h"

#include <QAbstractSocket>
#include <QAudioDevice>
#include <QAudioSource>
#include <QCryptographicHash>
#include <QDateTime>
#include <QFile>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkInterface>
#include <QMediaDevices>
#include <QRegularExpression>
#include <QRandomGenerator>
#include <QSettings>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QVariant>

#include <algorithm>
#include <cmath>

namespace {
constexpr qsizetype kMaximumRequestBytes = 64 * 1024;
constexpr qint64 kClientActiveWindowMs = 10000;
constexpr qsizetype kRemoteTokenLength = 8;

int remoteAudioDeviceScore(const QAudioDevice &device)
{
    const QString name = device.description().trimmed().toLower();
    int score = 0;
    if (name.contains(QStringLiteral("icom"))) score += 100;
    if (name.contains(QStringLiteral("7300"))) score += 100;
    if (name.contains(QStringLiteral("usb audio codec"))) score += 80;
    if (name.contains(QStringLiteral("usb audio device"))) score += 70;
    if (name.contains(QStringLiteral("c-media"))
        || name.contains(QStringLiteral("cmedia"))) score += 60;
    if (name.contains(QStringLiteral("usb"))) score += 20;
    if (name.contains(QStringLiteral("internal"))
        || name.contains(QStringLiteral("integrado"))
        || name.contains(QStringLiteral("dmic"))
        || name.contains(QStringLiteral("sof-hda"))) score -= 40;
    return score;
}

QString generateRemoteToken()
{
    // Alfabeto deliberadamente sin 0, 1, I, L ni O para que el token
    // sea cómodo de copiar a mano desde otro dispositivo.
    static constexpr char alphabet[] = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
    constexpr int alphabetSize = int(sizeof(alphabet) - 1);

    QString token;
    token.reserve(kRemoteTokenLength);
    auto *rng = QRandomGenerator::system();
    for (qsizetype i = 0; i < kRemoteTokenLength; ++i) {
        token.append(QLatin1Char(alphabet[rng->bounded(alphabetSize)]));
    }
    return token;
}

QString normalizedOwnerToken(const QString &token)
{
    const QString normalized = token.trimmed().toUpper();
    static const QRegularExpression allowed(QStringLiteral("^[A-Z0-9]{8}$"));
    if (!allowed.match(normalized).hasMatch()) {
        return {};
    }
    return normalized;
}

QByteArray statusReason(int statusCode)
{
    switch (statusCode) {
    case 200: return QByteArrayLiteral("OK");
    case 204: return QByteArrayLiteral("No Content");
    case 400: return QByteArrayLiteral("Bad Request");
    case 401: return QByteArrayLiteral("Unauthorized");
    case 404: return QByteArrayLiteral("Not Found");
    case 405: return QByteArrayLiteral("Method Not Allowed");
    case 409: return QByteArrayLiteral("Conflict");
    case 413: return QByteArrayLiteral("Payload Too Large");
    case 500: return QByteArrayLiteral("Internal Server Error");
    case 503: return QByteArrayLiteral("Service Unavailable");
    default: return QByteArrayLiteral("Error");
    }
}

QByteArray jsonMessage(const QString &message, bool ok)
{
    QJsonObject object;
    object.insert(QStringLiteral("ok"), ok);
    object.insert(QStringLiteral("message"), message);
    return QJsonDocument(object).toJson(QJsonDocument::Compact);
}

bool jsonBool(const QJsonValue &value, bool *ok)
{
    if (value.isBool()) {
        *ok = true;
        return value.toBool();
    }
    if (value.isDouble()) {
        *ok = true;
        return value.toInt() != 0;
    }
    *ok = false;
    return false;
}


bool parseRemoteFrequency(const QJsonValue &value,
                          qint64 *frequencyHz)
{
    if (frequencyHz == nullptr) {
        return false;
    }

    // Acepta los formatos habituales de radioafición:
    // 14.074.000, 14.074, 14074, 14074000, 14 074 000, etc.
    QString cleaned;
    if (value.isString()) {
        cleaned = value.toString().trimmed().toLower();
    } else if (value.isDouble()) {
        const double numeric = value.toDouble(-1.0);
        if (!std::isfinite(numeric) || numeric < 0.0) {
            return false;
        }
        cleaned = QString::number(numeric, 'f', 6);
        while (cleaned.contains(QLatin1Char('.'))
               && cleaned.endsWith(QLatin1Char('0'))) {
            cleaned.chop(1);
        }
        if (cleaned.endsWith(QLatin1Char('.'))) {
            cleaned.chop(1);
        }
    } else {
        return false;
    }

    cleaned.remove(QStringLiteral("mhz"));
    cleaned.remove(QStringLiteral("khz"));
    cleaned.remove(QStringLiteral("hz"));
    cleaned.remove(QRegularExpression(QStringLiteral("\\s+")));
    if (cleaned.isEmpty()) {
        return false;
    }

    const int separators = cleaned.count(QLatin1Char('.'))
                           + cleaned.count(QLatin1Char(','));
    bool ok = false;
    double hzValue = 0.0;

    if (separators >= 2) {
        cleaned.remove(QLatin1Char('.'));
        cleaned.remove(QLatin1Char(','));
        hzValue = double(cleaned.toULongLong(&ok));
    } else if (separators == 1) {
        cleaned.replace(QLatin1Char(','), QLatin1Char('.'));
        const double numeric = cleaned.toDouble(&ok);
        if (ok) {
            if (numeric < 1000.0) hzValue = numeric * 1'000'000.0;
            else if (numeric < 100000.0) hzValue = numeric * 1000.0;
            else hzValue = numeric;
        }
    } else {
        const qulonglong numeric = cleaned.toULongLong(&ok);
        if (ok) {
            if (numeric < 1000ULL) hzValue = double(numeric) * 1'000'000.0;
            else if (numeric < 100000ULL) hzValue = double(numeric) * 1000.0;
            else hzValue = double(numeric);
        }
    }

    if (!ok || !std::isfinite(hzValue)) {
        return false;
    }

    const qint64 rounded = qint64(std::llround(hzValue));
    if (rounded < 30000 || rounded > 74800000) {
        return false;
    }

    *frequencyHz = rounded;
    return true;
}

struct RemoteBandDefinition {
    const char *name;
    const char *label;
    qint64 minimumHz;
    qint64 maximumHz;
    qint64 defaultHz;
};

constexpr RemoteBandDefinition kRemoteBands[] = {
    {"1.8", "160 m", 1800000, 2000000, 1850000},
    {"3.5", "80 m", 3500000, 4000000, 3700000},
    {"5",   "60 m", 5250000, 5450000, 5357000},
    {"7",   "40 m", 7000000, 7300000, 7100000},
    {"10",  "30 m", 10100000, 10150000, 10120000},
    {"14",  "20 m", 14000000, 14350000, 14200000},
    {"18",  "17 m", 18068000, 18168000, 18130000},
    {"21",  "15 m", 21000000, 21450000, 21200000},
    {"24",  "12 m", 24890000, 24990000, 24950000},
    {"28",  "10 m", 28000000, 29700000, 28500000},
    {"50",  "6 m",  50000000, 54000000, 50150000},
    {"70",  "4 m",  69900000, 70500000, 70200000}
};

const RemoteBandDefinition *remoteBandForName(const QString &name)
{
    for (const auto &band : kRemoteBands) {
        if (name == QString::fromLatin1(band.name)) {
            return &band;
        }
    }
    return nullptr;
}

const RemoteBandDefinition *remoteBandForFrequency(qint64 frequencyHz)
{
    for (const auto &band : kRemoteBands) {
        if (frequencyHz >= band.minimumHz && frequencyHz <= band.maximumHz) {
            return &band;
        }
    }
    return nullptr;
}
}

RemoteServer::RemoteServer(RadioController *radioController, QObject *parent)
    : QObject(parent),
      m_radio(radioController),
      m_server(new QTcpServer(this)),
      m_clientTimer(new QTimer(this))
{
    loadSettings();
    updateAccessUrls();

    connect(m_server, &QTcpServer::newConnection,
            this, &RemoteServer::onNewConnection);

    if (m_radio) {
        connect(m_radio, &RadioController::vfoAStateChanged,
                this, &RemoteServer::rememberCurrentBandFrequencies);
        connect(m_radio, &RadioController::vfoBStateChanged,
                this, &RemoteServer::rememberCurrentBandFrequencies);
        connect(m_radio, &RadioController::frequencyChanged,
                this, &RemoteServer::rememberCurrentBandFrequencies);
        connect(m_radio, &RadioController::connectedChanged,
                this, &RemoteServer::rememberCurrentBandFrequencies);
    }

    m_clientTimer->setInterval(3000);
    connect(m_clientTimer, &QTimer::timeout,
            this, &RemoteServer::pruneClients);
    m_clientTimer->start();

    if (m_autoStart) {
        QTimer::singleShot(0, this, [this]() {
            start();
        });
    }
}

RemoteServer::~RemoteServer()
{
    shutdown();
}

bool RemoteServer::running() const
{
    return m_server && m_server->isListening();
}

int RemoteServer::port() const
{
    return m_port;
}

QString RemoteServer::accessToken() const
{
    return m_accessToken;
}

QStringList RemoteServer::accessUrls() const
{
    return m_accessUrls;
}

QString RemoteServer::primaryUrl() const
{
    return m_primaryUrl;
}

QString RemoteServer::localTestUrl() const
{
    return QStringLiteral("http://127.0.0.1:%1/#token=%2")
        .arg(m_port)
        .arg(m_accessToken);
}

QString RemoteServer::status() const
{
    return m_status;
}

int RemoteServer::activeClients() const
{
    return m_clients.size();
}

bool RemoteServer::autoStart() const
{
    return m_autoStart;
}

void RemoteServer::loadSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("RemoteServer"));
    m_port = std::clamp(settings.value(QStringLiteral("port"), 7300).toInt(),
                        1024, 65535);
    m_accessToken = settings.value(QStringLiteral("token")).toString().trimmed();
    // Desde esta versión el servidor de Internet queda activo por defecto.
    // La marca de migración permite habilitarlo una sola vez también en
    // instalaciones existentes, sin impedir que el usuario lo desactive
    // posteriormente desde la ventana de control remoto.
    const bool autoStartDefaultApplied =
        settings.value(QStringLiteral("autoStartDefaultApplied"), false).toBool();
    if (!autoStartDefaultApplied) {
        m_autoStart = true;
        settings.setValue(QStringLiteral("autoStart"), true);
        settings.setValue(QStringLiteral("autoStartDefaultApplied"), true);
    } else {
        m_autoStart = settings.value(QStringLiteral("autoStart"), true).toBool();
    }

    settings.beginGroup(QStringLiteral("BandMemories"));
    for (int vfo = 0; vfo < 2; ++vfo) {
        for (const auto &band : kRemoteBands) {
            const QString key = QStringLiteral("%1_%2")
                                    .arg(vfo == 0 ? QStringLiteral("A") : QStringLiteral("B"),
                                         QString::fromLatin1(band.name));
            const qint64 hz = settings.value(key, 0).toLongLong();
            if (hz >= band.minimumHz && hz <= band.maximumHz) {
                m_bandMemories.insert(QStringLiteral("%1:%2")
                                          .arg(vfo)
                                          .arg(QString::fromLatin1(band.name)), hz);
            }
        }
    }
    settings.endGroup();
    settings.endGroup();

    // Desde v1.2.9 la clave remota puede fijarla el propietario. Al cargarla
    // se normaliza a mayúsculas y se valida para evitar valores antiguos o
    // corruptos. Si no es válida, se crea una clave aleatoria inicial.
    const QString normalizedToken = normalizedOwnerToken(m_accessToken);
    if (normalizedToken.isEmpty()) {
        m_accessToken = generateRemoteToken();
        saveSettings();
    } else {
        m_accessToken = normalizedToken;
    }
}

void RemoteServer::saveSettings() const
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("RemoteServer"));
    settings.setValue(QStringLiteral("port"), m_port);
    settings.setValue(QStringLiteral("token"), m_accessToken);
    settings.setValue(QStringLiteral("autoStart"), m_autoStart);
    settings.endGroup();
}

void RemoteServer::setStatus(const QString &status)
{
    if (m_status == status) {
        return;
    }
    m_status = status;
    emit statusChanged();
}

void RemoteServer::rememberBandFrequency(int vfoNumber, qint64 frequencyHz)
{
    if (vfoNumber < 0 || vfoNumber > 1 || frequencyHz <= 0) {
        return;
    }

    const auto *band = remoteBandForFrequency(frequencyHz);
    if (!band) {
        return;
    }

    const QString bandName = QString::fromLatin1(band->name);
    const QString memoryKey = QStringLiteral("%1:%2").arg(vfoNumber).arg(bandName);
    if (m_bandMemories.value(memoryKey, 0) == frequencyHz) {
        return;
    }

    m_bandMemories.insert(memoryKey, frequencyHz);

    QSettings settings;
    settings.beginGroup(QStringLiteral("RemoteServer"));
    settings.beginGroup(QStringLiteral("BandMemories"));
    settings.setValue(QStringLiteral("%1_%2")
                          .arg(vfoNumber == 0 ? QStringLiteral("A") : QStringLiteral("B"),
                               bandName),
                      frequencyHz);
    settings.endGroup();
    settings.endGroup();
}

void RemoteServer::rememberCurrentBandFrequencies()
{
    if (!m_radio || !m_radio->connected()) {
        return;
    }
    rememberBandFrequency(0, qint64(m_radio->vfoAFrequencyHz()));
    rememberBandFrequency(1, qint64(m_radio->vfoBFrequencyHz()));
}

qint64 RemoteServer::rememberedBandFrequency(int vfoNumber, const QString &bandName) const
{
    const auto *band = remoteBandForName(bandName);
    if (!band || vfoNumber < 0 || vfoNumber > 1) {
        return 0;
    }

    const QString memoryKey = QStringLiteral("%1:%2").arg(vfoNumber).arg(bandName);
    const qint64 remembered = m_bandMemories.value(memoryKey, 0);
    if (remembered >= band->minimumHz && remembered <= band->maximumHz) {
        return remembered;
    }
    return band->defaultHz;
}

QByteArray RemoteServer::bandStateJson() const
{
    QJsonArray rows;
    const int selectedVfo = m_radio ? m_radio->selectedVfo() : 0;
    for (const auto &band : kRemoteBands) {
        const QString name = QString::fromLatin1(band.name);
        QJsonObject row;
        row.insert(QStringLiteral("name"), name);
        row.insert(QStringLiteral("label"), QString::fromLatin1(band.label));
        row.insert(QStringLiteral("defaultHz"), double(band.defaultHz));
        row.insert(QStringLiteral("vfoAHz"), double(rememberedBandFrequency(0, name)));
        row.insert(QStringLiteral("vfoBHz"), double(rememberedBandFrequency(1, name)));
        row.insert(QStringLiteral("frequencyHz"),
                   double(rememberedBandFrequency(selectedVfo, name)));
        rows.append(row);
    }
    return QJsonDocument(rows).toJson(QJsonDocument::Compact);
}

bool RemoteServer::start()
{
    if (running()) {
        return true;
    }

    if (!m_server->listen(QHostAddress::AnyIPv4, quint16(m_port))) {
        setStatus(
            QStringLiteral("No se puede abrir el puerto %1: %2")
                .arg(m_port)
                .arg(m_server->errorString())
        );
        emit runningChanged();
        return false;
    }

    updateAccessUrls();
    setStatus(
        QStringLiteral("Servidor remoto activo · puerto %1 · TX remoto deshabilitado")
            .arg(m_port)
    );
    emit runningChanged();
    return true;
}

void RemoteServer::stop()
{
    if (m_server->isListening()) {
        m_server->close();
    }

    const auto sockets = m_buffers.keys();
    for (QTcpSocket *socket : sockets) {
        if (socket) {
            socket->disconnectFromHost();
        }
    }
    m_buffers.clear();

    const auto audioSockets = m_audioClients;
    m_audioClients.clear();
    for (QTcpSocket *socket : audioSockets) {
        if (socket) {
            socket->disconnectFromHost();
        }
    }
    stopAudioCaptureIfIdle();

    if (!m_clients.isEmpty()) {
        m_clients.clear();
        emit activeClientsChanged();
    }

    setStatus(QStringLiteral("Servidor remoto detenido"));
    emit runningChanged();
}

void RemoteServer::shutdown()
{
    stop();
}

bool RemoteServer::setPort(int portValue)
{
    const int validated = std::clamp(portValue, 1024, 65535);
    if (m_port == validated) {
        return true;
    }

    const bool wasRunning = running();
    if (wasRunning) {
        stop();
    }

    m_port = validated;
    saveSettings();
    updateAccessUrls();
    emit settingsChanged();

    if (wasRunning) {
        return start();
    }
    return true;
}

void RemoteServer::setAutoStart(bool enabled)
{
    if (m_autoStart == enabled) {
        return;
    }
    m_autoStart = enabled;
    saveSettings();
    emit settingsChanged();
}

bool RemoteServer::setAccessToken(const QString &token)
{
    const QString normalized = normalizedOwnerToken(token);
    if (normalized.isEmpty()) {
        setStatus(QStringLiteral("La clave remota debe contener exactamente 8 letras o números"));
        return false;
    }

    if (m_accessToken == normalized) {
        setStatus(QStringLiteral("La clave remota ya tiene ese valor"));
        return true;
    }

    m_accessToken = normalized;
    saveSettings();
    emit settingsChanged();
    emit networkInfoChanged();
    setStatus(QStringLiteral("Clave remota fijada por el propietario; los navegadores deben usar la nueva clave"));
    return true;
}

void RemoteServer::regenerateToken()
{
    m_accessToken = generateRemoteToken();
    saveSettings();
    emit settingsChanged();
    emit networkInfoChanged();
    setStatus(QStringLiteral("Clave remota aleatoria renovada; los navegadores anteriores deben autenticarse de nuevo"));
}

void RemoteServer::refreshNetworkInfo()
{
    updateAccessUrls();
}

void RemoteServer::updateAccessUrls()
{
    QStringList urls;
    const QString localhost = QStringLiteral("http://127.0.0.1:%1/").arg(m_port);
    urls << localhost;

    const auto addresses = QNetworkInterface::allAddresses();
    QString firstRemote;
    for (const QHostAddress &address : addresses) {
        if (address.protocol() != QAbstractSocket::IPv4Protocol
            || address.isLoopback()
            || address.isNull()) {
            continue;
        }

        const QString url = QStringLiteral("http://%1:%2/")
                                .arg(address.toString())
                                .arg(m_port);
        if (!urls.contains(url)) {
            urls << url;
            if (firstRemote.isEmpty()) {
                firstRemote = url;
            }
        }
    }

    if (firstRemote.isEmpty()) {
        firstRemote = localhost;
    }

    if (m_accessUrls != urls || m_primaryUrl != firstRemote) {
        m_accessUrls = urls;
        m_primaryUrl = firstRemote;
        emit networkInfoChanged();
    }
}

void RemoteServer::pruneClients()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    bool changed = false;
    for (auto it = m_clients.begin(); it != m_clients.end();) {
        if (now - it.value() > kClientActiveWindowMs) {
            it = m_clients.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }
    if (changed) {
        emit activeClientsChanged();
    }
}

void RemoteServer::noteClient(QTcpSocket *socket)
{
    if (!socket) {
        return;
    }
    const QString address = socket->peerAddress().toString();
    const bool isNew = !m_clients.contains(address);
    m_clients.insert(address, QDateTime::currentMSecsSinceEpoch());
    if (isNew) {
        emit activeClientsChanged();
    }
}

void RemoteServer::onNewConnection()
{
    while (m_server->hasPendingConnections()) {
        QTcpSocket *socket = m_server->nextPendingConnection();
        if (!socket) {
            continue;
        }

        m_buffers.insert(socket, QByteArray());
        connect(socket, &QTcpSocket::readyRead,
                this, [this, socket]() { onReadyRead(socket); });
        connect(socket, &QTcpSocket::disconnected,
                this, [this, socket]() {
                    m_buffers.remove(socket);
                    m_audioClients.removeAll(socket);
                    stopAudioCaptureIfIdle();
                    socket->deleteLater();
                });
    }
}

void RemoteServer::onReadyRead(QTcpSocket *socket)
{
    if (!socket) {
        return;
    }

    if (m_audioClients.contains(socket)) {
        const QByteArray frame = socket->readAll();
        if (!frame.isEmpty()
            && (quint8(frame.at(0)) & 0x0F) == 0x08) {
            // El navegador solicita cerrar el WebSocket: no es necesario
            // conservar la captura mientras espera el cierre TCP.
            socket->disconnectFromHost();
        }
        return;
    }

    if (!m_buffers.contains(socket)) {
        return;
    }

    QByteArray &buffer = m_buffers[socket];
    buffer += socket->readAll();

    if (buffer.size() > kMaximumRequestBytes) {
        sendResponse(socket, 413, QByteArrayLiteral("application/json; charset=utf-8"),
                     jsonMessage(QStringLiteral("Solicitud demasiado grande"), false));
        return;
    }

    const qsizetype headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0) {
        return;
    }

    qsizetype contentLength = 0;
    const QList<QByteArray> headerLines = buffer.left(headerEnd).split('\n');
    for (const QByteArray &rawLine : headerLines) {
        const QByteArray line = rawLine.trimmed();
        if (line.toLower().startsWith("content-length:")) {
            bool ok = false;
            contentLength = line.mid(15).trimmed().toLongLong(&ok);
            if (!ok || contentLength < 0 || contentLength > kMaximumRequestBytes) {
                sendResponse(socket, 400,
                             QByteArrayLiteral("application/json; charset=utf-8"),
                             jsonMessage(QStringLiteral("Content-Length no válido"), false));
                return;
            }
        }
    }

    const qsizetype totalLength = headerEnd + 4 + contentLength;
    if (buffer.size() < totalLength) {
        return;
    }

    const QByteArray request = buffer.left(totalLength);
    m_buffers.remove(socket);
    processRequest(socket, request);
}

bool RemoteServer::authorized(const QHash<QByteArray, QByteArray> &headers) const
{
    const QByteArray authorization = headers.value(QByteArrayLiteral("authorization"));
    if (!authorization.startsWith("Bearer ")) {
        return false;
    }
    const QByteArray supplied = authorization.mid(7).trimmed();
    return supplied == m_accessToken.toUtf8();
}

void RemoteServer::processRequest(QTcpSocket *socket, const QByteArray &request)
{
    const qsizetype headerEnd = request.indexOf("\r\n\r\n");
    if (headerEnd < 0) {
        sendResponse(socket, 400, QByteArrayLiteral("text/plain; charset=utf-8"),
                     QByteArrayLiteral("Solicitud HTTP no válida"));
        return;
    }

    const QByteArray headerBytes = request.left(headerEnd);
    const QByteArray body = request.mid(headerEnd + 4);
    const QList<QByteArray> lines = headerBytes.split('\n');
    if (lines.isEmpty()) {
        sendResponse(socket, 400, QByteArrayLiteral("text/plain; charset=utf-8"),
                     QByteArrayLiteral("Solicitud HTTP vacía"));
        return;
    }

    const QList<QByteArray> requestParts = lines.first().trimmed().split(' ');
    if (requestParts.size() < 2) {
        sendResponse(socket, 400, QByteArrayLiteral("text/plain; charset=utf-8"),
                     QByteArrayLiteral("Línea HTTP no válida"));
        return;
    }

    const QByteArray method = requestParts.at(0).toUpper();
    const QByteArray requestTarget = requestParts.at(1);
    QByteArray path = requestTarget;
    const qsizetype queryPos = path.indexOf('?');
    if (queryPos >= 0) {
        path = path.left(queryPos);
    }

    QHash<QByteArray, QByteArray> headers;
    for (qsizetype index = 1; index < lines.size(); ++index) {
        const QByteArray line = lines.at(index).trimmed();
        const qsizetype colon = line.indexOf(':');
        if (colon <= 0) {
            continue;
        }
        headers.insert(line.left(colon).trimmed().toLower(),
                       line.mid(colon + 1).trimmed());
    }

    if (method == "GET" && path == "/ws/audio") {
        if (!upgradeAudioWebSocket(socket, requestTarget, headers)) {
            sendResponse(socket, 401,
                         QByteArrayLiteral("text/plain; charset=utf-8"),
                         QByteArrayLiteral("Audio remoto no autorizado"));
        }
        return;
    }

    if (method == "GET" && (path == "/" || path == "/index.html")) {
        sendResponse(socket, 200, QByteArrayLiteral("text/html; charset=utf-8"),
                     loadWebPage());
        return;
    }

    if (method == "GET" && path == "/api/info") {
        QJsonObject info;
        info.insert(QStringLiteral("application"), QStringLiteral("Control IC-7300MK2"));
        info.insert(QStringLiteral("version"), QStringLiteral("1.2.7"));
        info.insert(QStringLiteral("authenticationRequired"), true);
        info.insert(QStringLiteral("txRemoteAvailable"), true);
        sendResponse(socket, 200,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     QJsonDocument(info).toJson(QJsonDocument::Compact));
        return;
    }

    if (path.startsWith("/api/") && !authorized(headers)) {
        sendResponse(socket, 401,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     jsonMessage(QStringLiteral("Token de acceso no válido"), false),
                     {{QByteArrayLiteral("WWW-Authenticate"), QByteArrayLiteral("Bearer")}});
        return;
    }

    if (method == "GET" && path == "/api/state") {
        noteClient(socket);
        sendResponse(socket, 200,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     radioStateJson());
        return;
    }

    if (method == "GET" && path == "/api/scope") {
        noteClient(socket);

        QJsonObject scope;
        scope.insert(QStringLiteral("ok"), true);
        scope.insert(QStringLiteral("running"), m_radio && m_radio->scopeRunning());
        scope.insert(QStringLiteral("frame"), m_radio ? m_radio->scopeFrameCounter() : 0);
        scope.insert(QStringLiteral("mode"), m_radio ? m_radio->scopeMode() : 0);
        scope.insert(QStringLiteral("modeText"), m_radio ? m_radio->scopeModeText() : QString());
        scope.insert(QStringLiteral("centerHz"), m_radio ? double(m_radio->scopeCenterFrequencyHz()) : 0.0);
        scope.insert(QStringLiteral("lowerHz"), m_radio ? double(m_radio->scopeLowerFrequencyHz()) : 0.0);
        scope.insert(QStringLiteral("higherHz"), m_radio ? double(m_radio->scopeHigherFrequencyHz()) : 0.0);
        scope.insert(QStringLiteral("spanHz"), m_radio ? double(m_radio->scopeSpanHz()) : 0.0);
        scope.insert(QStringLiteral("spanText"), m_radio ? m_radio->scopeSpanText() : QString());
        scope.insert(QStringLiteral("outOfRange"), m_radio && m_radio->scopeOutOfRange());
        scope.insert(QStringLiteral("hold"), m_radio && m_radio->scopeHold());
        scope.insert(QStringLiteral("speed"), m_radio ? m_radio->scopeSweepSpeed() : 0);
        scope.insert(QStringLiteral("speedText"), m_radio ? m_radio->scopeSweepSpeedText() : QString());
        scope.insert(QStringLiteral("vbwWide"), m_radio && m_radio->scopeVbwWide());
        scope.insert(QStringLiteral("frequencyHz"), m_radio ? double(m_radio->frequencyHz()) : 0.0);
        scope.insert(QStringLiteral("data"),
                     m_radio ? QJsonArray::fromVariantList(m_radio->scopeSpectrumData())
                             : QJsonArray());

        sendResponse(socket, 200,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     QJsonDocument(scope).toJson(QJsonDocument::Compact));
        return;
    }

    if (method == "GET" && path == "/api/memories") {
        noteClient(socket);

        QJsonObject result;
        result.insert(QStringLiteral("ok"), true);
        result.insert(QStringLiteral("revision"),
                      m_radio ? m_radio->memoriesRevision() : 0);
        result.insert(QStringLiteral("readActive"),
                      m_radio && m_radio->memoryReadActive());
        result.insert(QStringLiteral("memoryModeActive"),
                      m_radio && m_radio->memoryModeActive());
        result.insert(QStringLiteral("selectedChannel"),
                      m_radio ? m_radio->selectedMemoryChannel() : 0);
        result.insert(QStringLiteral("selectedChannelText"),
                      m_radio ? m_radio->selectedMemoryChannelText() : QString());
        result.insert(QStringLiteral("returnAvailable"),
                      m_radio && m_radio->memoryReturnAvailable());
        result.insert(QStringLiteral("returnVfoText"),
                      m_radio ? m_radio->memoryReturnVfoText() : QString());

        QJsonArray rows;
        int loadedCount = 0;
        int occupiedCount = 0;
        int blankCount = 0;

        if (m_radio) {
            const QVariantList memoryRows = m_radio->memoryRows();
            for (const QVariant &variant : memoryRows) {
                const QVariantMap row = variant.toMap();
                const bool loaded = row.value(QStringLiteral("loaded")).toBool();
                const bool blank = row.value(QStringLiteral("blank")).toBool();

                if (loaded) {
                    ++loadedCount;
                    if (blank) ++blankCount;
                    else ++occupiedCount;
                }

                QJsonObject item;
                item.insert(QStringLiteral("channel"),
                            row.value(QStringLiteral("channel")).toInt());
                item.insert(QStringLiteral("channelText"),
                            row.value(QStringLiteral("channelText")).toString());
                item.insert(QStringLiteral("loaded"), loaded);
                item.insert(QStringLiteral("blank"), blank);
                item.insert(QStringLiteral("name"),
                            row.value(QStringLiteral("name")).toString());
                item.insert(QStringLiteral("frequencyHz"),
                            row.value(QStringLiteral("frequencyHz")).toDouble());
                item.insert(QStringLiteral("frequencyText"),
                            row.value(QStringLiteral("frequencyText")).toString());
                item.insert(QStringLiteral("modeText"),
                            row.value(QStringLiteral("modeText")).toString());
                item.insert(QStringLiteral("filterText"),
                            row.value(QStringLiteral("filterText")).toString());
                item.insert(QStringLiteral("dataMode"),
                            row.value(QStringLiteral("dataMode")).toBool());
                item.insert(QStringLiteral("split"),
                            row.value(QStringLiteral("split")).toBool());
                item.insert(QStringLiteral("duplexText"),
                            row.value(QStringLiteral("duplexText")).toString());
                item.insert(QStringLiteral("selectText"),
                            row.value(QStringLiteral("selectText")).toString());
                item.insert(QStringLiteral("toneTypeText"),
                            row.value(QStringLiteral("toneTypeText")).toString());
                item.insert(QStringLiteral("repeaterToneText"),
                            row.value(QStringLiteral("repeaterToneText")).toString());
                rows.append(item);
            }
        }

        result.insert(QStringLiteral("loadedCount"), loadedCount);
        result.insert(QStringLiteral("occupiedCount"), occupiedCount);
        result.insert(QStringLiteral("blankCount"), blankCount);
        result.insert(QStringLiteral("totalCount"), 99);
        result.insert(QStringLiteral("rows"), rows);

        sendResponse(socket, 200,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     QJsonDocument(result).toJson(QJsonDocument::Compact));
        return;
    }

    if (method == "POST" && path == "/api/command") {
        noteClient(socket);
        int httpStatus = 200;
        QString errorText;
        const QByteArray response = handleCommand(body, &httpStatus, &errorText);
        sendResponse(socket, httpStatus,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     response);
        return;
    }

    if (path.startsWith("/api/") && method != "GET" && method != "POST") {
        sendResponse(socket, 405,
                     QByteArrayLiteral("application/json; charset=utf-8"),
                     jsonMessage(QStringLiteral("Método HTTP no permitido"), false));
        return;
    }

    sendResponse(socket, 404, QByteArrayLiteral("text/plain; charset=utf-8"),
                 QByteArrayLiteral("No encontrado"));
}

QByteArray RemoteServer::radioStateJson() const
{
    QJsonObject state;
    state.insert(QStringLiteral("serverVersion"), QStringLiteral("1.2.7"));
    state.insert(QStringLiteral("connected"), m_radio && m_radio->connected());
    state.insert(QStringLiteral("transmitting"), m_radio && m_radio->transmitting());
    state.insert(QStringLiteral("busy"), m_radio && m_radio->busy());
    state.insert(QStringLiteral("txRemoteAvailable"), true);

    if (m_radio) {
        state.insert(QStringLiteral("frequencyHz"), double(m_radio->frequencyHz()));
        state.insert(QStringLiteral("frequencyText"), m_radio->frequencyText());
        state.insert(QStringLiteral("band"), m_radio->bandText());
        {
            const QJsonDocument bandsDocument = QJsonDocument::fromJson(bandStateJson());
            state.insert(QStringLiteral("bands"), bandsDocument.array());
        }
        state.insert(QStringLiteral("mode"), m_radio->modeText());
        state.insert(QStringLiteral("filter"), m_radio->filterText());
        state.insert(QStringLiteral("data"), m_radio->dataMode());
        state.insert(QStringLiteral("selectedVfo"), m_radio->selectedVfo());
        state.insert(QStringLiteral("vfoAHz"), double(m_radio->vfoAFrequencyHz()));
        state.insert(QStringLiteral("vfoAText"), m_radio->vfoAFrequencyText());
        state.insert(QStringLiteral("vfoAMode"), m_radio->vfoAModeText());
        state.insert(QStringLiteral("vfoBHz"), double(m_radio->vfoBFrequencyHz()));
        state.insert(QStringLiteral("vfoBText"), m_radio->vfoBFrequencyText());
        state.insert(QStringLiteral("vfoBMode"), m_radio->vfoBModeText());
        state.insert(QStringLiteral("split"), m_radio->splitEnabled());
        state.insert(QStringLiteral("rit"), m_radio->ritEnabled());
        state.insert(QStringLiteral("deltaTx"), m_radio->deltaTxEnabled());
        state.insert(QStringLiteral("ritOffsetHz"), m_radio->ritOffsetHz());
        state.insert(QStringLiteral("afGain"), m_radio->afGain());
        state.insert(QStringLiteral("rfGain"), m_radio->rfGain());
        state.insert(QStringLiteral("squelch"), m_radio->squelch());
        state.insert(QStringLiteral("rfPower"), m_radio->rfPower());
        state.insert(QStringLiteral("preamp"), m_radio->preamp());
        state.insert(QStringLiteral("attenuator"), m_radio->attenuatorEnabled());
        state.insert(QStringLiteral("agc"), m_radio->agc());
        state.insert(QStringLiteral("tuner"), m_radio->tunerEnabled());
        state.insert(QStringLiteral("noiseBlanker"), m_radio->noiseBlankerEnabled());
        state.insert(QStringLiteral("noiseBlankerLevel"), m_radio->noiseBlankerLevel());
        state.insert(QStringLiteral("noiseReduction"), m_radio->noiseReductionEnabled());
        state.insert(QStringLiteral("noiseReductionLevel"), m_radio->noiseReductionLevel());
        state.insert(QStringLiteral("autoNotch"), m_radio->autoNotchEnabled());
        state.insert(QStringLiteral("manualNotch"), m_radio->manualNotchEnabled());
        state.insert(QStringLiteral("manualNotchPosition"), m_radio->manualNotchPosition());
        state.insert(QStringLiteral("manualNotchWidth"), m_radio->manualNotchWidth());
        state.insert(QStringLiteral("ipPlus"), m_radio->ipPlusEnabled());
        state.insert(QStringLiteral("pbt1"), m_radio->pbt1());
        state.insert(QStringLiteral("pbt2"), m_radio->pbt2());
        state.insert(QStringLiteral("filterShape"), m_radio->filterShape());
        state.insert(QStringLiteral("filterShapeText"), m_radio->filterShapeText());
        state.insert(QStringLiteral("vfoAFilter"), m_radio->vfoAFilterText());
        state.insert(QStringLiteral("vfoBFilter"), m_radio->vfoBFilterText());
        state.insert(QStringLiteral("sMeterPercent"), m_radio->sMeterPercent());
        state.insert(QStringLiteral("sMeterText"), m_radio->sMeterText());
        state.insert(QStringLiteral("scopeRunning"), m_radio->scopeRunning());
        state.insert(QStringLiteral("scopeFrame"), m_radio->scopeFrameCounter());
        state.insert(QStringLiteral("memoryReadActive"), m_radio->memoryReadActive());
        state.insert(QStringLiteral("memoryModeActive"), m_radio->memoryModeActive());
        state.insert(QStringLiteral("selectedMemoryChannel"),
                     m_radio->selectedMemoryChannel());
        state.insert(QStringLiteral("selectedMemoryChannelText"),
                     m_radio->selectedMemoryChannelText());
        state.insert(QStringLiteral("memoryReturnAvailable"),
                     m_radio->memoryReturnAvailable());
        state.insert(QStringLiteral("memoryReturnVfoText"),
                     m_radio->memoryReturnVfoText());
        state.insert(QStringLiteral("scopeMode"), m_radio->scopeMode());
        state.insert(QStringLiteral("scopeSpanText"), m_radio->scopeSpanText());
        state.insert(QStringLiteral("status"), m_radio->status());
        state.insert(QStringLiteral("actionStatus"), m_radio->actionStatus());
    }

    return QJsonDocument(state).toJson(QJsonDocument::Compact);
}

QByteArray RemoteServer::handleCommand(const QByteArray &body,
                                       int *httpStatus,
                                       QString *errorText)
{
    if (!m_radio || !m_radio->connected()) {
        *httpStatus = 503;
        *errorText = QStringLiteral("La radio no está conectada");
        return jsonMessage(*errorText, false);
    }

    // Primera versión remota: jamás cambia parámetros durante TX y no expone
    // ninguna orden PTT/TUNE. Una caída de red no puede dejar la radio en TX.
    if (m_radio->transmitting()) {
        *httpStatus = 409;
        *errorText = QStringLiteral("Cambios remotos bloqueados mientras la radio está en TX");
        return jsonMessage(*errorText, false);
    }

    if (m_radio->busy()) {
        *httpStatus = 409;
        *errorText = QStringLiteral("CI-V ocupado; espere a que termine la orden anterior");
        return jsonMessage(*errorText, false);
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        *httpStatus = 400;
        *errorText = QStringLiteral("JSON no válido");
        return jsonMessage(*errorText, false);
    }

    const QJsonObject object = document.object();
    const QString command = object.value(QStringLiteral("command")).toString().trimmed();
    const QJsonValue value = object.value(QStringLiteral("value"));

    if (command == QStringLiteral("frequency")) {
        qint64 hz = 0;
        if (!parseRemoteFrequency(value, &hz)) {
            *httpStatus = 400;
            return jsonMessage(
                QStringLiteral("Frecuencia no válida (0,030–74,800 MHz)"),
                false
            );
        }
        m_radio->setFrequency(QString::number(hz));
    } else if (command == QStringLiteral("vfoFrequency")) {
        const int vfo = object.value(QStringLiteral("vfo")).toInt(-1);
        qint64 hz = 0;
        if ((vfo != 0 && vfo != 1)
            || !parseRemoteFrequency(value, &hz)) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("VFO o frecuencia no válidos"), false);
        }
        m_radio->setVfoFrequency(vfo, QString::number(hz));
    } else if (command == QStringLiteral("band")) {
        rememberCurrentBandFrequencies();
        const QString bandName = value.toString().trimmed();
        const auto *band = remoteBandForName(bandName);
        const int vfo = object.contains(QStringLiteral("vfo"))
                            ? object.value(QStringLiteral("vfo")).toInt(-1)
                            : m_radio->selectedVfo();
        if (!band || (vfo != 0 && vfo != 1)) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Banda o VFO no válidos"), false);
        }
        const qint64 targetHz = rememberedBandFrequency(vfo, bandName);
        m_radio->setVfoFrequency(vfo, QString::number(targetHz));
    } else if (command == QStringLiteral("mode")) {
        static const QStringList modes = {
            QStringLiteral("LSB"), QStringLiteral("USB"), QStringLiteral("CW"),
            QStringLiteral("RTTY"), QStringLiteral("AM"), QStringLiteral("FM"),
            QStringLiteral("CW-R"), QStringLiteral("RTTY-R")
        };
        const QString mode = value.toString().trimmed().toUpper();
        if (!modes.contains(mode)) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Modo no válido"), false);
        }
        m_radio->setOperatingMode(mode);
    } else if (command == QStringLiteral("vfo")) {
        const QString vfo = value.toString().trimmed().toUpper();
        if (vfo == QStringLiteral("A")) {
            m_radio->selectVfoA();
        } else if (vfo == QStringLiteral("B")) {
            m_radio->selectVfoB();
        } else {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("VFO no válido"), false);
        }
    } else if (command == QStringLiteral("equalize")) {
        m_radio->equalizeVfos();
    } else if (command == QStringLiteral("exchange")) {
        m_radio->exchangeVfos();
    } else if (command == QStringLiteral("rit")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("RIT no válido"), false);
        }
        m_radio->setRitEnabled(enabled);
    } else if (command == QStringLiteral("deltaTx")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("ΔTX no válido"), false);
        }
        m_radio->setDeltaTxEnabled(enabled);
    } else if (command == QStringLiteral("ritOffset")) {
        const int offset = value.toInt(100000);
        if (offset < -9999 || offset > 9999) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Offset RIT fuera de rango"), false);
        }
        m_radio->setRitOffset(offset);
    } else if (command == QStringLiteral("filter")) {
        const int filter = value.toInt(-1);
        if (filter < 1 || filter > 3) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Filtro no válido"), false);
        }
        m_radio->setFilter(filter);
    } else if (command == QStringLiteral("data")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("DATA no válido"), false);
        }
        m_radio->setDataEnabled(enabled);
    } else if (command == QStringLiteral("split")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("SPLIT no válido"), false);
        }
        m_radio->setSplitEnabled(enabled);
    } else if (command == QStringLiteral("af")
               || command == QStringLiteral("rf")
               || command == QStringLiteral("sql")
               || command == QStringLiteral("power")) {
        const int percent = value.toInt(-1);
        if (percent < 0 || percent > 100) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Nivel fuera de rango"), false);
        }
        if (command == QStringLiteral("af")) m_radio->setAfGain(percent);
        else if (command == QStringLiteral("rf")) m_radio->setRfGain(percent);
        else if (command == QStringLiteral("sql")) m_radio->setSquelch(percent);
        else m_radio->setRfPower(percent);
    } else if (command == QStringLiteral("preamp")) {
        const int preamp = value.toInt(-1);
        if (preamp < 0 || preamp > 2) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Preamplificador no válido"), false);
        }
        m_radio->setPreamp(preamp);
    } else if (command == QStringLiteral("attenuator")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Atenuador no válido"), false);
        }
        m_radio->setAttenuatorEnabled(enabled);
    } else if (command == QStringLiteral("agc")) {
        const int agc = value.toInt(-1);
        if (agc < 1 || agc > 3) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("AGC no válido"), false);
        }
        m_radio->setAgc(agc);
    } else if (command == QStringLiteral("transmit")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("TX no válido"), false);
        }
        m_radio->setTransmit(enabled);
    } else if (command == QStringLiteral("tune")) {
        m_radio->startTuner();
    } else if (command == QStringLiteral("tuner")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Tuner no válido"), false);
        }
        m_radio->setTunerEnabled(enabled);
    } else if (command == QStringLiteral("noiseBlanker")
               || command == QStringLiteral("noiseReduction")
               || command == QStringLiteral("autoNotch")
               || command == QStringLiteral("manualNotch")
               || command == QStringLiteral("ipPlus")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Estado DSP no válido"), false);
        }
        if (command == QStringLiteral("noiseBlanker")) m_radio->setNoiseBlankerEnabled(enabled);
        else if (command == QStringLiteral("noiseReduction")) m_radio->setNoiseReductionEnabled(enabled);
        else if (command == QStringLiteral("autoNotch")) m_radio->setAutoNotchEnabled(enabled);
        else if (command == QStringLiteral("manualNotch")) m_radio->setManualNotchEnabled(enabled);
        else m_radio->setIpPlusEnabled(enabled);
    } else if (command == QStringLiteral("nbLevel")
               || command == QStringLiteral("nrLevel")
               || command == QStringLiteral("notchPosition")
               || command == QStringLiteral("pbt1")
               || command == QStringLiteral("pbt2")) {
        const int percent = value.toInt(-1);
        if (percent < 0 || percent > 100) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Nivel DSP fuera de rango"), false);
        }
        if (command == QStringLiteral("nbLevel")) m_radio->setNoiseBlankerLevel(percent);
        else if (command == QStringLiteral("nrLevel")) m_radio->setNoiseReductionLevel(percent);
        else if (command == QStringLiteral("notchPosition")) m_radio->setManualNotchPosition(percent);
        else if (command == QStringLiteral("pbt1")) m_radio->setPbt1(percent);
        else m_radio->setPbt2(percent);
    } else if (command == QStringLiteral("notchWidth")) {
        const int width = value.toInt(-1);
        if (width < 0 || width > 2) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Ancho de notch no válido"), false);
        }
        m_radio->setManualNotchWidth(width);
    } else if (command == QStringLiteral("filterShape")) {
        const int shape = value.toInt(-1);
        if (shape < 0 || shape > 1) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Forma de filtro no válida"), false);
        }
        m_radio->setFilterShape(shape);
    } else if (command == QStringLiteral("memoryReadAll")) {
        m_radio->readMemoryRange(1, 99);
    } else if (command == QStringLiteral("memoryRead")) {
        const int channel = value.toInt(-1);
        if (channel < 1 || channel > 99) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Canal de memoria no válido"), false);
        }
        m_radio->readMemoryChannel(channel);
    } else if (command == QStringLiteral("memorySelect")) {
        const int channel = value.toInt(-1);
        if (channel < 1 || channel > 99) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Canal de memoria no válido"), false);
        }
        m_radio->selectMemoryChannel(channel);
    } else if (command == QStringLiteral("memoryReturn")) {
        if (!m_radio->memoryReturnAvailable()) {
            *httpStatus = 409;
            return jsonMessage(QStringLiteral("No hay un VFO anterior al que volver"), false);
        }
        m_radio->returnToPreviousVfo();
    } else if (command == QStringLiteral("memoryCopyToVfo")) {
        const int channel = value.toInt(-1);
        if (channel < 1 || channel > 99) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Canal de memoria no válido"), false);
        }
        const QVariantMap row = m_radio->memoryRow(channel);
        if (!row.value(QStringLiteral("loaded")).toBool()
            || row.value(QStringLiteral("blank")).toBool()) {
            *httpStatus = 409;
            return jsonMessage(QStringLiteral("La memoria debe estar leída y ocupada"), false);
        }
        m_radio->copyMemoryToVfo(channel);
    } else if (command == QStringLiteral("memoryStore")) {
        const int channel = value.toInt(-1);
        if (channel < 1 || channel > 99) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Canal de memoria no válido"), false);
        }
        m_radio->storeDisplayedToMemory(channel);
    } else if (command == QStringLiteral("memoryClear")) {
        const int channel = value.toInt(-1);
        if (channel < 1 || channel > 99) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Canal de memoria no válido"), false);
        }
        m_radio->clearMemoryChannel(channel);
    } else if (command == QStringLiteral("memoryRename")) {
        const int channel = value.toInt(-1);
        const QString name =
            object.value(QStringLiteral("name")).toString().trimmed();
        if (channel < 1 || channel > 99) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Canal de memoria no válido"), false);
        }
        if (name.size() > 16) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("El nombre no puede superar 16 caracteres"), false);
        }
        const QVariantMap row = m_radio->memoryRow(channel);
        if (!row.value(QStringLiteral("loaded")).toBool()
            || row.value(QStringLiteral("blank")).toBool()) {
            *httpStatus = 409;
            return jsonMessage(QStringLiteral("Lea una memoria ocupada antes de renombrarla"), false);
        }
        m_radio->renameMemoryChannel(channel, name);
    } else if (command == QStringLiteral("scopeStart")) {
        m_radio->startSpectrumScope();
    } else if (command == QStringLiteral("scopeStop")) {
        m_radio->stopSpectrumScope();
    } else if (command == QStringLiteral("scopeMode")) {
        const int mode = value.toInt(-1);
        if (mode < 0 || mode > 3) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Modo de scope no válido"), false);
        }
        m_radio->setSpectrumScopeMode(mode);
    } else if (command == QStringLiteral("scopeSpan")) {
        const qint64 span = qint64(value.toDouble(-1));
        static const QList<qint64> spans = {
            2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000
        };
        if (!spans.contains(span)) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Span de scope no válido"), false);
        }
        m_radio->setSpectrumScopeSpan(qulonglong(span));
    } else if (command == QStringLiteral("scopeHold")) {
        bool ok = false;
        const bool enabled = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("HOLD de scope no válido"), false);
        }
        m_radio->setSpectrumScopeHold(enabled);
    } else if (command == QStringLiteral("scopeSpeed")) {
        const int speed = value.toInt(-1);
        if (speed < 0 || speed > 2) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("Velocidad de scope no válida"), false);
        }
        m_radio->setSpectrumScopeSweepSpeed(speed);
    } else if (command == QStringLiteral("scopeVbw")) {
        bool ok = false;
        const bool wide = jsonBool(value, &ok);
        if (!ok) {
            *httpStatus = 400;
            return jsonMessage(QStringLiteral("VBW de scope no válido"), false);
        }
        m_radio->setSpectrumScopeVbwWide(wide);
    } else if (command == QStringLiteral("pbtClear")) {
        m_radio->clearTwinPbt();
    } else {
        *httpStatus = 400;
        return jsonMessage(QStringLiteral("Orden remota no reconocida"), false);
    }

    *httpStatus = 200;
    return jsonMessage(QStringLiteral("Orden enviada a la cola CI-V"), true);
}

bool RemoteServer::upgradeAudioWebSocket(
    QTcpSocket *socket,
    const QByteArray &requestTarget,
    const QHash<QByteArray, QByteArray> &headers)
{
    if (!socket
        || headers.value(QByteArrayLiteral("upgrade")).toLower()
               != QByteArrayLiteral("websocket")) {
        return false;
    }

    const QUrl url = QUrl::fromEncoded(requestTarget);
    const QString suppliedToken =
        QUrlQuery(url).queryItemValue(QStringLiteral("token")).trimmed().toUpper();
    if (suppliedToken != m_accessToken) {
        return false;
    }

    const QByteArray key =
        headers.value(QByteArrayLiteral("sec-websocket-key")).trimmed();
    if (key.isEmpty()) {
        return false;
    }

    const QByteArray accept = QCryptographicHash::hash(
        key + QByteArrayLiteral("258EAFA5-E914-47DA-95CA-C5AB0DC85B11"),
        QCryptographicHash::Sha1).toBase64();

    QByteArray response = QByteArrayLiteral("HTTP/1.1 101 Switching Protocols\r\n");
    response += QByteArrayLiteral("Upgrade: websocket\r\n");
    response += QByteArrayLiteral("Connection: Upgrade\r\n");
    response += QByteArrayLiteral("Sec-WebSocket-Accept: ") + accept
                + QByteArrayLiteral("\r\n\r\n");
    socket->write(response);
    socket->flush();
    m_audioClients.append(socket);
    noteClient(socket);

    if (!startAudioCapture()) {
        sendWebSocketFrame(
            socket,
            0x01,
            QByteArrayLiteral("{\"error\":\"No se pudo abrir la entrada de audio USB\"}"));
        QTimer::singleShot(100, socket, &QTcpSocket::disconnectFromHost);
        return true;
    }

    QJsonObject format;
    format.insert(QStringLiteral("type"), QStringLiteral("format"));
    format.insert(QStringLiteral("sampleRate"), m_audioFormat.sampleRate());
    format.insert(QStringLiteral("channels"), m_audioFormat.channelCount());
    format.insert(QStringLiteral("sampleFormat"), QStringLiteral("int16"));
    sendWebSocketFrame(
        socket,
        0x01,
        QJsonDocument(format).toJson(QJsonDocument::Compact));
    return true;
}

bool RemoteServer::startAudioCapture()
{
    if (m_audioSource && m_audioInput) {
        return true;
    }

    const QList<QAudioDevice> devices = QMediaDevices::audioInputs();
    if (devices.isEmpty()) {
        return false;
    }

    QSettings settings;
    const QByteArray preferredId = QByteArray::fromBase64(
        settings.value(QStringLiteral("morse/audioDeviceId")).toByteArray());

    int selected = -1;
    for (int index = 0; index < devices.size(); ++index) {
        if (!preferredId.isEmpty() && devices.at(index).id() == preferredId) {
            selected = index;
            break;
        }
    }
    if (selected < 0) {
        int bestScore = -1000;
        for (int index = 0; index < devices.size(); ++index) {
            const int score = remoteAudioDeviceScore(devices.at(index));
            if (score > bestScore) {
                bestScore = score;
                selected = index;
            }
        }
    }

    const QAudioDevice device = devices.at(std::max(0, selected));
    const QList<QPair<int, int>> candidates = {
        {48000, 2}, {48000, 1}, {44100, 2}, {44100, 1}
    };
    QAudioFormat selectedFormat;
    for (const auto &candidate : candidates) {
        QAudioFormat format;
        format.setSampleRate(candidate.first);
        format.setChannelCount(candidate.second);
        format.setSampleFormat(QAudioFormat::Int16);
        if (device.isFormatSupported(format)) {
            selectedFormat = format;
            break;
        }
    }
    if (!selectedFormat.isValid()) {
        return false;
    }

    m_audioFormat = selectedFormat;
    m_audioSource = new QAudioSource(device, m_audioFormat, this);
    m_audioSource->setBufferSize(m_audioFormat.bytesForDuration(120000));
    m_audioInput = m_audioSource->start();
    if (!m_audioInput) {
        m_audioSource->deleteLater();
        m_audioSource = nullptr;
        return false;
    }

    connect(m_audioInput, &QIODevice::readyRead,
            this, &RemoteServer::broadcastAudio);
    return true;
}

void RemoteServer::stopAudioCaptureIfIdle()
{
    if (!m_audioClients.isEmpty()) {
        return;
    }
    if (m_audioInput) {
        disconnect(m_audioInput, nullptr, this, nullptr);
        m_audioInput = nullptr;
    }
    if (m_audioSource) {
        m_audioSource->stop();
        m_audioSource->deleteLater();
        m_audioSource = nullptr;
    }
}

void RemoteServer::broadcastAudio()
{
    if (!m_audioInput) {
        return;
    }
    const QByteArray pcm = m_audioInput->readAll();
    if (pcm.isEmpty()) {
        return;
    }
    const auto clients = m_audioClients;
    for (QTcpSocket *socket : clients) {
        if (socket && socket->state() == QAbstractSocket::ConnectedState) {
            // Evita aumentar indefinidamente la latencia de clientes lentos.
            if (socket->bytesToWrite() < 512 * 1024) {
                sendWebSocketFrame(socket, 0x02, pcm);
            }
        }
    }
}

void RemoteServer::sendWebSocketFrame(
    QTcpSocket *socket, quint8 opcode, const QByteArray &payload)
{
    if (!socket) {
        return;
    }
    QByteArray frame;
    frame.append(char(0x80 | (opcode & 0x0F)));
    const quint64 size = quint64(payload.size());
    if (size < 126) {
        frame.append(char(size));
    } else if (size <= 0xFFFF) {
        frame.append(char(126));
        frame.append(char((size >> 8) & 0xFF));
        frame.append(char(size & 0xFF));
    } else {
        frame.append(char(127));
        for (int shift = 56; shift >= 0; shift -= 8) {
            frame.append(char((size >> shift) & 0xFF));
        }
    }
    frame += payload;
    socket->write(frame);
}

QByteArray RemoteServer::loadWebPage() const
{
    QFile file(QStringLiteral(":/remote/index.html"));
    if (!file.open(QIODevice::ReadOnly)) {
        return QByteArrayLiteral("<!doctype html><html><body><h1>Control IC-7300MK2</h1><p>No se pudo cargar la interfaz remota.</p></body></html>");
    }
    return file.readAll();
}

void RemoteServer::sendResponse(
    QTcpSocket *socket,
    int statusCode,
    const QByteArray &contentType,
    const QByteArray &body,
    const QList<QPair<QByteArray, QByteArray>> &extraHeaders)
{
    if (!socket) {
        return;
    }

    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(statusCode) + " "
                + statusReason(statusCode) + "\r\n";
    response += "Content-Type: " + contentType + "\r\n";
    response += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    response += "Connection: close\r\n";
    response += "Cache-Control: no-store, no-cache, must-revalidate\r\n";
    response += "Pragma: no-cache\r\n";
    response += "X-Content-Type-Options: nosniff\r\n";
    response += "X-Frame-Options: DENY\r\n";
    response += "Referrer-Policy: no-referrer\r\n";
    response += "Content-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self' ws: wss:; img-src 'self' data:; frame-ancestors 'none'\r\n";
    for (const auto &header : extraHeaders) {
        response += header.first + ": " + header.second + "\r\n";
    }
    response += "\r\n";
    response += body;

    socket->write(response);
    socket->flush();
    socket->disconnectFromHost();
}
