#include "applicationlauncher.h"

#include <QFileInfo>
#include <QProcess>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUdpSocket>
#include <QHostAddress>
#include <QRandomGenerator>
#include <QtEndian>
#include <QTimer>
#include <QNetworkInterface>
#include <QSysInfo>
#include <QTime>
#include <QDateTime>

#include <algorithm>

namespace {
QByteArray lanPasscode(const QString &input)
{
    static const unsigned char seq[] = {
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0x47,0x5d,0x4c,0x42,0x66,0x20,0x23,0x46,0x4e,0x57,0x45,0x3d,0x67,0x76,0x60,0x41,
        0x62,0x39,0x59,0x2d,0x68,0x7e,0x7c,0x65,0x7d,0x49,0x29,0x72,0x73,0x78,0x21,0x6e,
        0x5a,0x5e,0x4a,0x3e,0x71,0x2c,0x2a,0x54,0x3c,0x3a,0x63,0x4f,0x43,0x75,0x27,0x79,
        0x5b,0x35,0x70,0x48,0x6b,0x56,0x6f,0x34,0x32,0x6c,0x30,0x61,0x6d,0x7b,0x2f,0x4b,
        0x64,0x38,0x2b,0x2e,0x50,0x40,0x3f,0x55,0x33,0x37,0x25,0x77,0x24,0x26,0x74,0x6a,
        0x28,0x53,0x4d,0x69,0x22,0x5c,0x44,0x31,0x36,0x58,0x3b,0x7a,0x51,0x5f,0x52
    };
    QByteArray raw = input.toLocal8Bit();
    QByteArray out;
    for (int i = 0; i < raw.size() && i < 16; ++i) {
        int p = static_cast<unsigned char>(raw.at(i)) + i;
        if (p > 126) p = 32 + p % 127;
        out.append(static_cast<char>(seq[p]));
    }
    return out;
}
const QString kDecodiumExecutable = QStringLiteral(
    "/home/ramon/Aplicaciones/Decodium/"
    "decodium4-ft2-1.0.490-linux-x86_64.AppImage"
);
const QString kFldigiExecutable = QStringLiteral("/usr/bin/fldigi");
const QString kQsstvExecutable = QStringLiteral("/usr/bin/qsstv");
const QString kJs8callExecutable = QStringLiteral("/usr/bin/js8call");
const QString kFlatpakExecutable = QStringLiteral("/usr/bin/flatpak");
const QString kJs8callFlatpakId = QStringLiteral("com.js8call.JS8Call");
}

ApplicationLauncher::ApplicationLauncher(QObject *parent)
    : QObject(parent),
      m_decodiumProcess(new QProcess(this)),
      m_fldigiProcess(new QProcess(this)),
      m_qsstvProcess(new QProcess(this)),
      m_js8callProcess(new QProcess(this)),
      m_network(new QNetworkAccessManager(this))
{
    QSettings settings;
    m_lanDataEnabled = settings.value(QStringLiteral("lan/dataEnabled"), false).toBool();
    m_rttyFrequencyHz = settings.value("digitalModes/rttyFrequencyHz",
                                       m_rttyFrequencyHz).toULongLong();
    m_cwFrequencyHz = settings.value("digitalModes/cwFrequencyHz",
                                     m_cwFrequencyHz).toULongLong();
    m_ftFrequencyHz = settings.value("digitalModes/ftFrequencyHz",
                                     m_ftFrequencyHz).toULongLong();
    m_sstvFrequencyHz = settings.value("digitalModes/sstvFrequencyHz",
                                       m_sstvFrequencyHz).toULongLong();
    m_pskFrequencyHz = settings.value("digitalModes/pskFrequencyHz",
                                      m_pskFrequencyHz).toULongLong();
    m_oliviaFrequencyHz = settings.value("digitalModes/oliviaFrequencyHz",
                                         m_oliviaFrequencyHz).toULongLong();
    m_js8FrequencyHz = settings.value("digitalModes/js8FrequencyHz",
                                      m_js8FrequencyHz).toULongLong();
    m_wefaxFrequencyHz = settings.value("digitalModes/wefaxFrequencyHz",
                                        m_wefaxFrequencyHz).toULongLong();
    m_compactWindowX = settings.value("compactWindow/x", -1).toInt();
    m_compactWindowY = settings.value("compactWindow/y", -1).toInt();
    m_superWindowX = settings.value("superWindow/x", -1).toInt();
    m_superWindowY = settings.value("superWindow/y", -1).toInt();
    m_compactWindowWidth = std::max(
        780, settings.value("compactWindow/width", 780).toInt());
    m_compactModePreferred = settings.value(
        "compactWindow/preferred", false).toBool();
    m_mainWindowX = settings.value("mainWindow/x", -1).toInt();
    m_mainWindowY = settings.value("mainWindow/y", -1).toInt();
    m_compactAlwaysOnTop = settings.value(
        "compactWindow/alwaysOnTop", true).toBool();
    m_lanHost = settings.value("lan/host", m_lanHost).toString();
    m_lanUser = settings.value("lan/user", m_lanUser).toString();
    m_lanPassword = settings.value("lan/password", m_lanPassword).toString();
    m_lanConnectionEnabled = settings.value("connection/type", settings.value("lan/enabled", false).toBool() ? 1 : 0).toInt() == 1;
    m_decodiumProcess->setStandardOutputFile(QProcess::nullDevice());
    m_decodiumProcess->setStandardErrorFile(QProcess::nullDevice());
    connect(m_decodiumProcess, &QProcess::started,
            this, [this]() {
                setStatus(QStringLiteral("DECODIUM 4 iniciado"));
                emit decodiumRunningChanged();
            });
    connect(m_decodiumProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
                setStatus(QStringLiteral("DECODIUM 4 cerrado"));
                emit decodiumRunningChanged();
            });
    connect(m_decodiumProcess, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError) {
                setStatus(QStringLiteral("No se pudo iniciar DECODIUM 4"));
                emit decodiumRunningChanged();
            });

    m_fldigiProcess->setStandardOutputFile(QProcess::nullDevice());
    m_fldigiProcess->setStandardErrorFile(QProcess::nullDevice());
    connect(m_fldigiProcess, &QProcess::started,
            this, [this]() {
                setStatus(QStringLiteral("FLDigi iniciado para RTTY"));
                emit fldigiRunningChanged();
            });
    connect(m_fldigiProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
                setStatus(QStringLiteral("FLDigi cerrado"));
                emit fldigiRunningChanged();
            });
    connect(m_fldigiProcess, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError) {
                setStatus(QStringLiteral("No se pudo iniciar FLDigi"));
                emit fldigiRunningChanged();
            });

    m_qsstvProcess->setStandardOutputFile(QProcess::nullDevice());
    m_qsstvProcess->setStandardErrorFile(QProcess::nullDevice());
    connect(m_qsstvProcess, &QProcess::started,
            this, [this]() {
                setStatus(QStringLiteral("QSSTV iniciado"));
                emit qsstvRunningChanged();
            });
    connect(m_qsstvProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
                setStatus(QStringLiteral("QSSTV cerrado"));
                emit qsstvRunningChanged();
            });
    connect(m_qsstvProcess, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError) {
                setStatus(QStringLiteral("No se pudo iniciar QSSTV"));
                emit qsstvRunningChanged();
            });

    m_js8callProcess->setStandardOutputFile(QProcess::nullDevice());
    m_js8callProcess->setStandardErrorFile(QProcess::nullDevice());
    connect(m_js8callProcess, &QProcess::started, this, [this]() {
        setStatus(QStringLiteral("JS8Call iniciado"));
        emit js8callRunningChanged();
    });
    connect(m_js8callProcess,
            qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
                m_js8callUsesFlatpak = false;
                setStatus(QStringLiteral("JS8Call cerrado"));
                emit js8callRunningChanged();
            });
    connect(m_js8callProcess, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError) {
                setStatus(QStringLiteral("No se pudo iniciar JS8Call"));
                emit js8callRunningChanged();
            });
}

qulonglong ApplicationLauncher::rttyFrequencyHz() const { return m_rttyFrequencyHz; }
qulonglong ApplicationLauncher::cwFrequencyHz() const { return m_cwFrequencyHz; }
qulonglong ApplicationLauncher::ftFrequencyHz() const { return m_ftFrequencyHz; }
qulonglong ApplicationLauncher::sstvFrequencyHz() const { return m_sstvFrequencyHz; }
qulonglong ApplicationLauncher::pskFrequencyHz() const { return m_pskFrequencyHz; }
qulonglong ApplicationLauncher::oliviaFrequencyHz() const { return m_oliviaFrequencyHz; }
qulonglong ApplicationLauncher::js8FrequencyHz() const { return m_js8FrequencyHz; }
qulonglong ApplicationLauncher::wefaxFrequencyHz() const { return m_wefaxFrequencyHz; }

namespace {
void saveDigitalFrequency(const char *key, qulonglong value)
{
    QSettings settings;
    settings.setValue(QString::fromLatin1(key), QVariant::fromValue(value));
}
}

void ApplicationLauncher::setRttyFrequencyHz(qulonglong value)
{
    if (value == m_rttyFrequencyHz || value < 100000 || value > 60000000) return;
    m_rttyFrequencyHz = value;
    saveDigitalFrequency("digitalModes/rttyFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setCwFrequencyHz(qulonglong value)
{
    if (value == m_cwFrequencyHz || value < 100000 || value > 60000000) return;
    m_cwFrequencyHz = value;
    saveDigitalFrequency("digitalModes/cwFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setFtFrequencyHz(qulonglong value)
{
    if (value == m_ftFrequencyHz || value < 100000 || value > 60000000) return;
    m_ftFrequencyHz = value;
    saveDigitalFrequency("digitalModes/ftFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setSstvFrequencyHz(qulonglong value)
{
    if (value == m_sstvFrequencyHz || value < 100000 || value > 60000000) return;
    m_sstvFrequencyHz = value;
    saveDigitalFrequency("digitalModes/sstvFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setPskFrequencyHz(qulonglong value)
{
    if (value == m_pskFrequencyHz || value < 100000 || value > 60000000) return;
    m_pskFrequencyHz = value;
    saveDigitalFrequency("digitalModes/pskFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setOliviaFrequencyHz(qulonglong value)
{
    if (value == m_oliviaFrequencyHz || value < 100000 || value > 60000000) return;
    m_oliviaFrequencyHz = value;
    saveDigitalFrequency("digitalModes/oliviaFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setJs8FrequencyHz(qulonglong value)
{
    if (value == m_js8FrequencyHz || value < 100000 || value > 60000000) return;
    m_js8FrequencyHz = value;
    saveDigitalFrequency("digitalModes/js8FrequencyHz", value);
    emit digitalFrequenciesChanged();
}

void ApplicationLauncher::setWefaxFrequencyHz(qulonglong value)
{
    if (value == m_wefaxFrequencyHz || value < 100000 || value > 60000000) return;
    m_wefaxFrequencyHz = value;
    saveDigitalFrequency("digitalModes/wefaxFrequencyHz", value);
    emit digitalFrequenciesChanged();
}

int ApplicationLauncher::compactWindowX() const { return m_compactWindowX; }
int ApplicationLauncher::compactWindowY() const { return m_compactWindowY; }

void ApplicationLauncher::setCompactWindowX(int value)
{
    if (value == m_compactWindowX) return;
    m_compactWindowX = value;
    QSettings().setValue(QStringLiteral("compactWindow/x"), value);
    emit compactWindowPositionChanged();
}

QString ApplicationLauncher::lanHost() const { return m_lanHost; }
QString ApplicationLauncher::lanUser() const { return m_lanUser; }
QString ApplicationLauncher::lanPassword() const { return m_lanPassword; }
void ApplicationLauncher::setLanHost(const QString &value)
{
    const QString v = value.trimmed(); if (v == m_lanHost) return;
    m_lanHost = v; QSettings().setValue("lan/host", v); emit lanSettingsChanged();
}
void ApplicationLauncher::setLanUser(const QString &value)
{
    if (value == m_lanUser) return;
    m_lanUser = value; QSettings().setValue("lan/user", value); emit lanSettingsChanged();
}
void ApplicationLauncher::setLanPassword(const QString &value)
{
    if (value == m_lanPassword) return;
    m_lanPassword = value; QSettings().setValue("lan/password", value); emit lanSettingsChanged();
}
bool ApplicationLauncher::lanConnectionEnabled() const { return m_lanConnectionEnabled; }
bool ApplicationLauncher::lanConnected() const { return m_lanConnected; }
bool ApplicationLauncher::lanDataEnabled() const { return m_lanDataEnabled; }
void ApplicationLauncher::setLanConnectionEnabled(bool value)
{
    if (value == m_lanConnectionEnabled) return;
    m_lanConnectionEnabled = value;
    QSettings settings;
    settings.setValue("lan/enabled", value);
    settings.setValue("connection/type", value ? 1 : 0);
    settings.sync();
    emit lanSettingsChanged();
}

void ApplicationLauncher::testLanConnection()
{
    // The IC-7300 accepts a single authenticated LAN session. Always dispose
    // of sockets from a previous attempt before starting a new handshake.
    const auto previousSockets = findChildren<QUdpSocket *>();
    for (QUdpSocket *old : previousSockets) {
        if (old->property("lanRemoteId").isValid()
            || old->property("lanConnSent").isValid()
            || old->property("lanLocalIp").isValid()) {
            old->close();
            delete old;
        }
    }
    if (m_lanConnected) { m_lanConnected = false; emit lanConnectionChanged(); }
    auto *socket = new QUdpSocket(this);
    const QString host = m_lanHost.trimmed();
    if (!socket->bind(QHostAddress::AnyIPv4, 0)) {
        setStatus(QStringLiteral("LAN: no se pudo abrir el puerto UDP local"));
        if (!m_lanConnected)
            socket->deleteLater();
        return;
    }
    QHostAddress localAddress;
    const quint32 targetAddress = QHostAddress(host).toIPv4Address();
    for (const QHostAddress &address : QNetworkInterface::allAddresses()) {
        if (address.protocol() == QAbstractSocket::IPv4Protocol && !address.isLoopback()) {
            const quint32 candidate = address.toIPv4Address();
            if ((candidate & 0xffffff00u) == (targetAddress & 0xffffff00u)) {
                localAddress = address;
                break;
            }
            if (localAddress.isNull()) localAddress = address;
        }
    }
    // WFView uses the local ephemeral UDP port as the 32-bit stream ID
    // (little-endian on the wire). Including IP octets here lets the login
    // succeed but breaks heartbeat/channel association after a few seconds.
    const quint32 ip = localAddress.isNull() ? 0u : localAddress.toIPv4Address();
    const quint32 id = quint32(socket->localPort());
    socket->setProperty("lanLocalIp", ip);
    socket->setProperty("lanId", id);
    setStatus(QStringLiteral("LAN: interfaz local %1, puerto UDP %2")
                  .arg(localAddress.toString()).arg(socket->localPort()));
    QByteArray packet(16, '\0');
    packet[0] = 16; packet[4] = 3;
    qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(packet.data() + 8));
    if (!socket->writeDatagram(packet, QHostAddress(host), 50001)) {
        setStatus(QStringLiteral("LAN: no se pudo enviar la prueba"));
        socket->deleteLater();
        return;
    }
    setStatus(QStringLiteral("LAN: esperando respuesta de %1…").arg(host));
    auto *discoverTimer = new QTimer(socket);
    discoverTimer->setInterval(500);
    connect(discoverTimer, &QTimer::timeout, socket, [socket, host, id]() {
        if (socket->property("lanProbeResponded").toBool()) return;
        QByteArray probe(16, '\0');
        qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(probe.data()));
        qToLittleEndian<quint16>(3, reinterpret_cast<uchar *>(probe.data()+4));
        qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(probe.data()+8));
        socket->writeDatagram(probe, QHostAddress(host), 50001);
    });
    discoverTimer->start();
    connect(socket, &QUdpSocket::readyRead, this, [this, socket, id, host, ip]() {
        while (socket->hasPendingDatagrams()) {
            QByteArray reply;
            reply.resize(int(socket->pendingDatagramSize()));
            QHostAddress sender;
            quint16 senderPort = 0;
            socket->readDatagram(reply.data(), reply.size(), &sender, &senderPort);
            if (reply.size() < 16) continue;
            const quint16 type = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(reply.constData() + 4));
            const quint32 remoteId = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(reply.constData() + 8));
            // Keep the WFView ping exchange alive.  The sequence is advanced
            // only after the radio acknowledges our ping; advancing it when
            // sending (or sharing it with idle packets) makes the IC-7300
            // stop the session after a few seconds.
            if (reply.size() == 21 && type == 7) {
                const uchar replyKind = static_cast<uchar>(reply.at(16));
                const quint16 pingSeq = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(reply.constData()+6));
                if (replyKind == 0) {
                    QByteArray pong = reply;
                    pong[16] = char(1);
                    // WFView answers with the local/remote IDs swapped, not
                    // by echoing the radio's IDs unchanged.
                    qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(pong.data()+8));
                    qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(pong.data()+12));
                    socket->writeDatagram(pong, QHostAddress(host), senderPort ? senderPort : 50001);
                } else if (replyKind == 1
                           && pingSeq == quint16(socket->property("lanControlPingSeq").toUInt())) {
                    socket->setProperty("lanControlPingSeq", quint32(pingSeq + 1));
                }
                continue;
            }
            if (reply.size() == 0x50) {
                const quint16 remoteCivPort = qFromBigEndian<quint16>(reinterpret_cast<const uchar *>(reply.constData()+0x42));
                const quint16 remoteAudioPort = qFromBigEndian<quint16>(reinterpret_cast<const uchar *>(reply.constData()+0x46));
                if (remoteCivPort) socket->setProperty("lanRemoteCivPort", remoteCivPort);
                if (remoteAudioPort) socket->setProperty("lanRemoteAudioPort", remoteAudioPort);
                if (remoteCivPort && remoteAudioPort) {
                    setStatus(QStringLiteral("LAN: estado recibido; puertos remotos CI-V %1, audio %2").arg(remoteCivPort).arg(remoteAudioPort));
                } else if (socket->property("lanConnPacket").isValid()) {
                    setStatus(QStringLiteral("LAN: estado provisional sin puertos; reenviando conninfo"));
                    socket->writeDatagram(socket->property("lanConnPacket").toByteArray(), QHostAddress(host), 50001);
                }
            }
            if (type == 4) socket->setProperty("lanProbeResponded", true);
            if (type != 4) {
                if (type == 6 && socket->property("lanAwaitReady").toBool()) {
                    // fall through and send login after the radio's "I am ready"
                } else {
                    if (!socket->property("lanLoginSent").toBool()) {
                            if (reply.size() >= 0x90) {
                            socket->setProperty("lanConnInfoReceived", true);
                            socket->setProperty("lanConnected", true);
                            if (!m_lanConnected) { m_lanConnected = true; emit lanConnectionChanged(); }
                            setStatus(QStringLiteral("LAN: respuesta conninfo recibida (%1 bytes); CI-V negociado").arg(reply.size()));
                            if (auto *civ = qobject_cast<QUdpSocket *>(socket->property("lanCivSocket").value<QObject *>())) {
                                QByteArray hello(16, '\0');
                                qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(hello.data()));
                                qToLittleEndian<quint16>(3, reinterpret_cast<uchar *>(hello.data()+4));
                                qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(hello.data()+8));
                                qToLittleEndian<quint32>(socket->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(hello.data()+12));
                                civ->writeDatagram(hello, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                QByteArray open(0x16, '\0');
                                qToLittleEndian<quint32>(0x16, reinterpret_cast<uchar *>(open.data()));
                                qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(open.data()+8));
                                qToLittleEndian<quint32>(socket->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(open.data()+12));
                                qToLittleEndian<quint16>(0x01c0, reinterpret_cast<uchar *>(open.data()+16));
                                qToBigEndian<quint16>(0, reinterpret_cast<uchar *>(open.data()+19));
                                open[21] = char(0x04);
                                civ->writeDatagram(open, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                const QByteArray civFrame = QByteArray::fromHex("FE FE 94 E1 25 00 FD");
                                QByteArray data(21, '\0');
                                qToLittleEndian<quint32>(21 + civFrame.size(), reinterpret_cast<uchar *>(data.data()));
                                const quint16 dataSeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                                qToLittleEndian<quint16>(dataSeq, reinterpret_cast<uchar *>(data.data()+6));
                                socket->setProperty("lanCivTransportSeq", quint32(dataSeq + 1));
                                qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(data.data()+8));
                                qToLittleEndian<quint32>(socket->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(data.data()+12));
                                data[16] = char(0xc1);
                                qToLittleEndian<quint16>(civFrame.size(), reinterpret_cast<uchar *>(data.data()+17));
                                qToBigEndian<quint16>(0, reinterpret_cast<uchar *>(data.data()+19));
                                data.append(civFrame);
                                // Do not send CI-V data before the type-4/type-6
                                // handshake; the radio rejects duplicate
                                // sequence zero packets with 81 ff ff ff.
                                setStatus(QStringLiteral("LAN: canal CI-V solicitado; esperando confirmación"));
                            }
                        }
                        continue;
                    }
                }
                if (!socket->property("lanResponseLogged").toBool()) {
                    socket->setProperty("lanResponseLogged", true);
                    setStatus(QStringLiteral("LAN: datagrama posterior recibido (tipo %1, %2 bytes)").arg(type).arg(reply.size()));
                }
                if (reply.size() < 0x60 && type != 6) continue;
                // Continue below to parse the login response.
            } else {
            // The radio may repeat its identification packet; do not send
            // duplicate login requests while the first one is pending.
            if (socket->property("lanLoginSent").toBool())
                continue;
            QByteArray ready(16, '\0');
            qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(ready.data()));
            // WFView answers the radio's identification with control type 0x06
            // ("Are you ready"), sequence 1.
            qToLittleEndian<quint16>(6, reinterpret_cast<uchar *>(ready.data() + 4));
            qToLittleEndian<quint16>(1, reinterpret_cast<uchar *>(ready.data() + 6));
            qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(ready.data() + 8));
            qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(ready.data() + 12));
            socket->writeDatagram(ready, QHostAddress(host), 50001);
            socket->setProperty("lanRemoteId", remoteId);
            socket->setProperty("lanAwaitReady", true);
            setStatus(QStringLiteral("LAN: radio identificada; solicitando autorización de login"));
            // WFView repeats this control packet every 500 ms because UDP
            // delivery is not guaranteed.
            for (int retry = 1; retry <= 8; ++retry) {
                QTimer::singleShot(retry * 500, socket, [socket, host, id, remoteId]() {
                    if (!socket->property("lanAwaitReady").toBool()) return;
                    QByteArray again(16, '\0');
                    qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(again.data()));
                    // WFView keeps sending Are-You-There (0x03, seq 0)
                    // until the radio answers with the ready packet (0x06).
                    qToLittleEndian<quint16>(3, reinterpret_cast<uchar *>(again.data() + 4));
                    qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(again.data() + 6));
                    qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(again.data() + 8));
                    qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(again.data() + 12));
                    socket->writeDatagram(again, QHostAddress(host), 50001);
                });
            }
            continue;
            }
            if (type == 6 && socket->property("lanAwaitReady").toBool()) {
            socket->setProperty("lanAwaitReady", false);
            const quint32 wfviewRemoteId = socket->property("lanRemoteId").toUInt();
            QByteArray login(128, '\0');
            qToLittleEndian<quint32>(128, reinterpret_cast<uchar *>(login.data()));
            // Login packet header as used by WFView: type 0, sequence 1.
            qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(login.data() + 4));
            qToLittleEndian<quint16>(1, reinterpret_cast<uchar *>(login.data() + 6));
            qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(login.data() + 8));
            qToLittleEndian<quint32>(wfviewRemoteId, reinterpret_cast<uchar *>(login.data() + 12));
            qToBigEndian<quint32>(112, reinterpret_cast<uchar *>(login.data() + 16));
            login[20] = 1;
            qToBigEndian<quint16>(0x30, reinterpret_cast<uchar *>(login.data() + 22));
            const quint16 tokRequest = static_cast<quint16>(QRandomGenerator::global()->generate());
            qToLittleEndian<quint16>(tokRequest, reinterpret_cast<uchar *>(login.data() + 26));
            QByteArray user = lanPasscode(m_lanUser);
            QByteArray pass = lanPasscode(m_lanPassword);
            memcpy(login.data() + 64, user.constData(), size_t(user.size()));
            memcpy(login.data() + 80, pass.constData(), size_t(pass.size()));
            // Match the client name used by the known-good WFView session.
            QByteArray name = QByteArrayLiteral("ramon-HP-wfview");
            memcpy(login.data() + 96, name.constData(), size_t(name.size()));
            socket->writeDatagram(login, QHostAddress(host), 50001);
            socket->setProperty("lanProbeResponded", true);
            socket->setProperty("lanLoginSent", true);
            socket->setProperty("lanTokRequest", tokRequest);
            setStatus(QStringLiteral("LAN: radio identificada; login enviado (usuario %1)").arg(m_lanUser));
            socket->setProperty("lanRemoteId", remoteId);
            for (int retry = 1; retry <= 4; ++retry) {
                QTimer::singleShot(retry * 500, socket, [socket, host, login]() {
                    if (!socket->property("lanLoginSent").toBool()) return;
                    socket->writeDatagram(login, QHostAddress(host), 50001);
                });
            }
            return;
            }
        if (socket->property("lanLoginSent").toBool()
            && !socket->property("lanResponseLogged").toBool()) {
            socket->setProperty("lanResponseLogged", true);
            setStatus(QStringLiteral("LAN: datagrama posterior recibido (tipo %1, %2 bytes)")
                          .arg(type).arg(reply.size()));
        }
        if (socket->property("lanLoginSent").toBool() && reply.size() >= 0x60) {
            setStatus(QStringLiteral("LAN: respuesta de sesión recibida (%1 bytes)").arg(reply.size()));
            const uchar *p = reinterpret_cast<const uchar *>(reply.constData());
            const quint16 tok = qFromLittleEndian<quint16>(p + 0x1a);
            const quint32 error = qFromLittleEndian<quint32>(p + 0x30);
            const quint32 token = qFromLittleEndian<quint32>(p + 0x1c);
            const quint16 expected = static_cast<quint16>(socket->property("lanTokRequest").toUInt());
            if (error == 0xfeffffffu) {
                setStatus(QStringLiteral("LAN: usuario o contraseña rechazados"));
                socket->setProperty("lanLoginSent", false);
            } else if (tok == expected) {
                setStatus(QStringLiteral("LAN: confirmación recibida; token obtenido"));
                socket->setProperty("lanToken", token);
                QByteArray tokenPacket(0x40, '\0');
                qToLittleEndian<quint32>(0x40, reinterpret_cast<uchar *>(tokenPacket.data()));
                qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(tokenPacket.data()+4));
                qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(tokenPacket.data()+8));
                const quint32 savedRemoteId = socket->property("lanRemoteId").toUInt();
                qToLittleEndian<quint32>(savedRemoteId, reinterpret_cast<uchar *>(tokenPacket.data()+12));
                qToBigEndian<quint32>(0x30, reinterpret_cast<uchar *>(tokenPacket.data()+16));
                tokenPacket[20] = 1; tokenPacket[21] = 2;
                qToBigEndian<quint16>(0x31, reinterpret_cast<uchar *>(tokenPacket.data()+22));
                qToBigEndian<quint16>(0x0798, reinterpret_cast<uchar *>(tokenPacket.data()+36));
                qToLittleEndian<quint16>(expected, reinterpret_cast<uchar *>(tokenPacket.data()+26));
                qToLittleEndian<quint32>(token, reinterpret_cast<uchar *>(tokenPacket.data()+28));
                socket->writeDatagram(tokenPacket, QHostAddress(host), 50001);
                setStatus(QStringLiteral("LAN: token enviado; sesión autenticada"));
                auto *tokenRenew = new QTimer(socket);
                tokenRenew->setInterval(60000);
                connect(tokenRenew, &QTimer::timeout, socket, [socket, host, id]() {
                    if (!socket->property("lanConnected").toBool()) return;
                    QByteArray renew(0x40, '\0');
                    qToLittleEndian<quint32>(0x40, reinterpret_cast<uchar *>(renew.data()));
                    qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(renew.data()+4));
                    qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(renew.data()+8));
                    qToLittleEndian<quint32>(socket->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(renew.data()+12));
                    qToBigEndian<quint32>(0x30, reinterpret_cast<uchar *>(renew.data()+16));
                    renew[20] = 1; renew[21] = 5;
                    const quint16 seq = quint16(socket->property("lanAuthSeq").toUInt());
                    qToBigEndian<quint16>(seq, reinterpret_cast<uchar *>(renew.data()+22));
                    socket->setProperty("lanAuthSeq", quint32(seq + 1));
                    qToLittleEndian<quint16>(socket->property("lanTokRequest").toUInt(), reinterpret_cast<uchar *>(renew.data()+26));
                    qToLittleEndian<quint32>(socket->property("lanToken").toUInt(), reinterpret_cast<uchar *>(renew.data()+28));
                    socket->writeDatagram(renew, QHostAddress(host), 50001);
                });
                tokenRenew->start();
                // Reserve an ephemeral audio socket as WFView does.  The
                // local port, not the radio's fixed service port 50003, is
                // what must be announced in the connection-info packet.
                auto *audioSocket = new QUdpSocket(socket);
                if (!audioSocket->bind(QHostAddress::AnyIPv4, 0)) {
                    setStatus(QStringLiteral("LAN: no se pudo abrir el socket de audio local"));
                    audioSocket->deleteLater();
                } else {
                    socket->setProperty("lanAudioPort", audioSocket->localPort());
                    socket->setProperty("lanAudioSocket", QVariant::fromValue(static_cast<QObject *>(audioSocket)));
                    setStatus(QStringLiteral("LAN: socket de audio local abierto en puerto %1").arg(audioSocket->localPort()));
                    // Audio has its own keepalive stream. Reply to radio
                    // heartbeats on this socket as WFView does.
                    connect(audioSocket, &QUdpSocket::readyRead, this, [audioSocket, socket, host]() {
                        while (audioSocket->hasPendingDatagrams()) {
                            QByteArray p;
                            p.resize(int(audioSocket->pendingDatagramSize()));
                            QHostAddress sender;
                            quint16 senderPort = 0;
                            audioSocket->readDatagram(p.data(), p.size(), &sender, &senderPort);
                            if (p.size() != 21
                                || qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(p.constData()+4)) != 7)
                                continue;
                            if (static_cast<uchar>(p.at(16)) == 0) {
                                const quint32 radioId = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(p.constData()+8));
                                p[16] = char(1);
                                qToLittleEndian<quint32>(quint32(audioSocket->localPort()), reinterpret_cast<uchar *>(p.data()+8));
                                qToLittleEndian<quint32>(radioId, reinterpret_cast<uchar *>(p.data()+12));
                                audioSocket->writeDatagram(p, QHostAddress(host), senderPort ? senderPort : 50003);
                            }
                        }
                    });
                }
                // Request the CI-V serial stream on the radio's UDP 50002
                // service, using the authenticated token.
                auto *civSocket = new QUdpSocket(socket);
                if (!civSocket->bind(QHostAddress::AnyIPv4, 0)) {
                    setStatus(QStringLiteral("LAN: no se pudo abrir el socket CI-V local"));
                } else {
                    civSocket->setProperty("lanIsCiv", true);
                    socket->setProperty("lanCivPort", civSocket->localPort());
                    // WFView uses the ephemeral CI-V UDP port as the
                    // channel id (upper 16 bits remain zero).
                    // The IC-7300 CI-V service identifies this secondary
                    // channel by its ephemeral UDP port (the control socket
                    // retains the IP+port identifier used during login).
                    const quint32 civId = quint32(civSocket->localPort());
                    socket->setProperty("lanCivId", civId);
                    socket->setProperty("lanCivSeq", 1u);
                    socket->setProperty("lanCivPingSeq", 0u);
                    socket->setProperty("lanCivTransportSeq", 1u);
                    socket->setProperty("lanCivRxSeqValid", false);
                    socket->setProperty("lanCivRxSeq", 0u);
                    socket->setProperty("lanLastCivDataMs", qint64(QDateTime::currentMSecsSinceEpoch()));
                    socket->setProperty("lanCivSocket", QVariant::fromValue(static_cast<QObject *>(civSocket)));
                    auto *civPing = new QTimer(civSocket);
                    // WFView's PING_PERIOD is 100 ms; the IC-7300 expires a
                    // secondary CI-V channel quickly when these are slower.
                    civPing->setInterval(100);
                    connect(civPing, &QTimer::timeout, civSocket, [civSocket, socket, host]() {
                        QByteArray ping(21, '\0');
                        qToLittleEndian<quint32>(21, reinterpret_cast<uchar *>(ping.data()));
                        qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(ping.data()+4));
                        const quint16 seq = quint16(socket->property("lanCivPingSeq").toUInt());
                        qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(ping.data()+6));
                        socket->setProperty("lanCivPingSeq", quint32(seq + 1));
                        qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(ping.data()+8));
                        qToLittleEndian<quint32>(socket->property("lanCivRemoteId").toUInt(), reinterpret_cast<uchar *>(ping.data()+12));
                        // The ping packet has a one-byte reply field at 0x10;
                        // uptime/millisecond timestamp starts at 0x11.
                        ping[16] = 1;
                        qToLittleEndian<quint32>(quint32(QTime::currentTime().msecsSinceStartOfDay()),
                                                 reinterpret_cast<uchar *>(ping.data()+17));
                        civSocket->writeDatagram(ping, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                    });
                    civPing->start();
                    // WFView keeps each UDP stream alive with untracked idle
                    // control packets roughly every 100 ms.  Without these
                    // packets the IC-7300 stops forwarding CI-V updates after
                    // a short period even though authentication remains valid.
                    auto *civIdle = new QTimer(civSocket);
                    civIdle->setInterval(100);
                    connect(civIdle, &QTimer::timeout, civSocket, [civSocket, socket, host]() {
                        QByteArray idle(16, '\0');
                        qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(idle.data()));
                        qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(idle.data()+4));
                        const quint16 idleSeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                        qToLittleEndian<quint16>(idleSeq, reinterpret_cast<uchar *>(idle.data()+6));
                        socket->setProperty("lanCivTransportSeq", quint32(idleSeq + 1));
                        qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(idle.data()+8));
                        qToLittleEndian<quint32>(socket->property("lanCivRemoteId").toUInt(), reinterpret_cast<uchar *>(idle.data()+12));
                        civSocket->writeDatagram(idle, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                    });
                    civIdle->start();
                    // Poll frequency independently of the unsolicited stream;
                    // some firmware versions do not emit the initial stream
                    // marker, although CI-V is already usable.
                    auto *freqPollEarly = new QTimer(civSocket);
                    freqPollEarly->setInterval(1000);
                    socket->setProperty("lanFreqPollStarted", true);
                    connect(freqPollEarly, &QTimer::timeout, civSocket, [civSocket, socket, host]() {
                        const quint32 remoteId = socket->property("lanCivRemoteId").toUInt();
                        if (!remoteId) return;
                        QByteArray q(27, '\0');
                        qToLittleEndian<quint32>(28, reinterpret_cast<uchar *>(q.data()));
                        const quint16 seq = quint16(socket->property("lanCivTransportSeq").toUInt());
                        qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(q.data()+6));
                        socket->setProperty("lanCivTransportSeq", quint32(seq + 1));
                        qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(q.data()+8));
                        qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(q.data()+12));
                        q[16] = char(0xc1);
                        qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(q.data()+17));
                        const quint16 civSeq = quint16(socket->property("lanCivSeq").toUInt());
                        qToBigEndian<quint16>(civSeq, reinterpret_cast<uchar *>(q.data()+19));
                        socket->setProperty("lanCivSeq", quint32(civSeq + 1));
                        q.replace(21, 6, QByteArray::fromHex("FE FE 94 E1 25 00 FD"));
                        civSocket->writeDatagram(q, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                    });
                    freqPollEarly->start();
                    // The radio can stop a CI-V stream when it does not see
                    // the open/channel request again.  WFView has a watchdog
                    // that reopens the channel after a couple of seconds;
                    // mirror that behaviour here.
                    auto *civWatchdog = new QTimer(civSocket);
                    civWatchdog->setInterval(1000);
                    connect(civWatchdog, &QTimer::timeout, civSocket, [civSocket, socket, host]() {
                        if (!socket->property("lanCivOpened").toBool()) return;
                        const qint64 last = socket->property("lanLastCivDataMs").toLongLong();
                        if (QDateTime::currentMSecsSinceEpoch() - last < 2000) return;
                        const quint32 civId = socket->property("lanCivId").toUInt();
                        const quint32 remoteId = socket->property("lanCivRemoteId").toUInt();
                        const quint16 port = socket->property("lanRemoteCivPort").toUInt() ?: 50002;
                        QByteArray open(0x16, '\0');
                        qToLittleEndian<quint32>(0x16, reinterpret_cast<uchar *>(open.data()));
                        const quint16 openSeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                        qToLittleEndian<quint16>(openSeq, reinterpret_cast<uchar *>(open.data()+6));
                        socket->setProperty("lanCivTransportSeq", quint32(openSeq + 1));
                        qToLittleEndian<quint32>(civId, reinterpret_cast<uchar *>(open.data()+8));
                        qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(open.data()+12));
                        qToLittleEndian<quint16>(0x01c0, reinterpret_cast<uchar *>(open.data()+16));
                        open[21] = char(0x04);
                        civSocket->writeDatagram(open, QHostAddress(host), port);
                        QByteArray query(27, '\0');
                        qToLittleEndian<quint32>(28, reinterpret_cast<uchar *>(query.data()));
                        const quint16 querySeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                        qToLittleEndian<quint16>(querySeq, reinterpret_cast<uchar *>(query.data()+6));
                        socket->setProperty("lanCivTransportSeq", quint32(querySeq + 1));
                        qToLittleEndian<quint32>(civId, reinterpret_cast<uchar *>(query.data()+8));
                        qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(query.data()+12));
                        query[16] = char(0xc1);
                        qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(query.data()+17));
                        query.replace(21, 6, QByteArray::fromHex("FE FE 94 E1 25 00 FD"));
                        civSocket->writeDatagram(query, QHostAddress(host), port);
                        socket->setProperty("lanLastCivDataMs", qint64(QDateTime::currentMSecsSinceEpoch()));
                    });
                    civWatchdog->start();
                    connect(civSocket, &QUdpSocket::readyRead, this, [this, civSocket, socket, host]() {
                        while (civSocket->hasPendingDatagrams()) {
                            QByteArray civ;
                            civ.resize(int(civSocket->pendingDatagramSize()));
                            civSocket->readDatagram(civ.data(), civ.size());
                            // Tracked CI-V datagrams carry a little-endian
                            // transport sequence at offset 0x06. Mirror
                            // WFView's rxSeqBuf/rxMissing logic by asking the
                            // radio to retransmit any gap we detect.
                            const quint16 civPacketType = civ.size() >= 6
                                    ? qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+4)) : 0xffff;
                            if (civ.size() == 21 && civPacketType == 7) {
                                const uchar replyKind = static_cast<uchar>(civ.at(16));
                                const quint16 pingSeq = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+6));
                                if (replyKind == 0) {
                                    QByteArray pong = civ;
                                    pong[16] = char(1);
                                    const quint32 radioId = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(civ.constData()+8));
                                    qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(pong.data()+8));
                                    qToLittleEndian<quint32>(radioId, reinterpret_cast<uchar *>(pong.data()+12));
                                    civSocket->writeDatagram(pong, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                } else if (replyKind == 1
                                           && pingSeq == quint16(socket->property("lanCivPingSeq").toUInt())) {
                                    socket->setProperty("lanCivPingSeq", quint32(pingSeq + 1));
                                }
                                continue;
                            }
                            if (civ.size() > 21 && civPacketType == 0) {
                                const quint16 rxSeq = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+6));
                                const bool valid = socket->property("lanCivRxSeqValid").toBool();
                                const quint16 expected = quint16(socket->property("lanCivRxSeq").toUInt());
                                const quint16 port = socket->property("lanRemoteCivPort").toUInt() ?: 50002;
                                if (valid && rxSeq != expected && quint16(rxSeq - expected) < 0x8000) {
                                    // Datagrams can arrive out of order (and
                                    // waterfall packets may be filtered by the
                                    // application), so do not flood the radio
                                    // with retransmission requests here.
                                    Q_UNUSED(port);
                                }
                                socket->setProperty("lanCivRxSeqValid", true);
                                socket->setProperty("lanCivRxSeq", quint32(rxSeq + 1));
                            }
                            if (civ.size() > 21 && civPacketType == 0)
                                socket->setProperty("lanLastCivDataMs", qint64(QDateTime::currentMSecsSinceEpoch()));
                            if (civ.size() == 16 && (qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+4)) == 4
                                || qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+4)) == 6)) {
                                const quint16 civControlType = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+4));
                                const quint32 civId = socket->property("lanCivId").toUInt();
                                const quint32 remoteId = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(civ.constData()+8));
                                socket->setProperty("lanCivRemoteId", remoteId);
                                QByteArray ready(16, '\0');
                                qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(ready.data()));
                                qToLittleEndian<quint16>(6, reinterpret_cast<uchar *>(ready.data()+4));
                                qToLittleEndian<quint16>(1, reinterpret_cast<uchar *>(ready.data()+6));
                                qToLittleEndian<quint32>(civId, reinterpret_cast<uchar *>(ready.data()+8));
                                qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(ready.data()+12));
                                if (civControlType == 4)
                                    civSocket->writeDatagram(ready, QHostAddress(host), 50002);
                                if (civControlType == 4)
                                    continue;
                                if (socket->property("lanCivOpened").toBool())
                                    continue;
                                socket->setProperty("lanCivOpened", true);
                                QByteArray open(0x16, '\0');
                                qToLittleEndian<quint32>(0x16, reinterpret_cast<uchar *>(open.data()));
                                const quint16 openSeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                                qToLittleEndian<quint16>(openSeq, reinterpret_cast<uchar *>(open.data()+6));
                                socket->setProperty("lanCivTransportSeq", quint32(openSeq + 1));
                                qToLittleEndian<quint32>(civId, reinterpret_cast<uchar *>(open.data()+8));
                                qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(open.data()+12));
                                qToLittleEndian<quint16>(0x01c0, reinterpret_cast<uchar *>(open.data()+16));
                                open[21] = char(0x04);
                                civSocket->writeDatagram(open, QHostAddress(host), 50002);
                                for (int retry = 1; retry <= 8; ++retry) QTimer::singleShot(retry * 100, civSocket, [civSocket, socket, host, open]() {
                                    civSocket->writeDatagram(open, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                    const quint32 civId2 = socket->property("lanCivId").toUInt();
                                    const quint32 remoteId2 = socket->property("lanCivRemoteId").toUInt();
                                    QByteArray query(27, '\0');
                                    qToLittleEndian<quint32>(28, reinterpret_cast<uchar *>(query.data()));
                                    const quint16 querySeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                                    qToLittleEndian<quint16>(querySeq, reinterpret_cast<uchar *>(query.data()+6));
                                    socket->setProperty("lanCivTransportSeq", quint32(querySeq + 1));
                                    qToLittleEndian<quint32>(civId2, reinterpret_cast<uchar *>(query.data()+8));
                                    qToLittleEndian<quint32>(remoteId2, reinterpret_cast<uchar *>(query.data()+12));
                                    query[16] = char(0xc1);
                                    qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(query.data()+17));
                                    query.replace(21, 6, QByteArray::fromHex("FE FE 94 E1 25 00 FD"));
                                    civSocket->writeDatagram(query, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                    // Some IC-7300 firmware accepts CI-V
                                    // polling on E1 (the same source used by
                                    // its waterfall stream); try it once as
                                    // a compatibility fallback.
                                    QTimer::singleShot(200, civSocket, [civSocket, socket, host]() {
                                        QByteArray alt(27, '\0');
                                        qToLittleEndian<quint32>(28, reinterpret_cast<uchar *>(alt.data()));
                                        const quint16 altSeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                                        qToLittleEndian<quint16>(altSeq, reinterpret_cast<uchar *>(alt.data()+6));
                                        socket->setProperty("lanCivTransportSeq", quint32(altSeq + 1));
                                        qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(alt.data()+8));
                                        qToLittleEndian<quint32>(socket->property("lanCivRemoteId").toUInt(), reinterpret_cast<uchar *>(alt.data()+12));
                                        alt[16] = char(0xc1);
                                        qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(alt.data()+17));
                                        alt.replace(21, 6, QByteArray::fromHex("FE FE 94 E1 25 00 FD"));
                                        civSocket->writeDatagram(alt, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                    });
                                });
                                setStatus(QStringLiteral("LAN: apertura CI-V confirmada; consulta reenviada"));
                            }
                            // A 21-byte type-7 datagram is a ping, not a CI-V
                            // stream packet. Only type-0 data can activate
                            // the stream state machine.
                            if (civ.size() == 21 && civPacketType == 0) {
                                if (!socket->property("lanCivStreamLogged").toBool()) {
                                    socket->setProperty("lanCivStreamLogged", true);
                                    if (!m_lanConnected) { m_lanConnected = true; emit lanConnectionChanged(); }
                                    setStatus(QStringLiteral("LAN: flujo CI-V activo (paquetes de datos recibidos)"));
                                    if (!socket->property("lanFreqPollStarted").toBool()) {
                                        socket->setProperty("lanFreqPollStarted", true);
                                        auto *freqPoll = new QTimer(civSocket);
                                        freqPoll->setInterval(1000);
                                        socket->setProperty("lanFreqPollTimer", QVariant::fromValue(static_cast<QObject *>(freqPoll)));
                                        connect(freqPoll, &QTimer::timeout, civSocket, [civSocket, socket, host]() {
                                            QByteArray q(27, '\0');
                                            qToLittleEndian<quint32>(28, reinterpret_cast<uchar *>(q.data()));
                                            const quint16 pollSeq = quint16(socket->property("lanCivTransportSeq").toUInt());
                                            qToLittleEndian<quint16>(pollSeq, reinterpret_cast<uchar *>(q.data()+6));
                                            socket->setProperty("lanCivTransportSeq", quint32(pollSeq + 1));
                                            qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(q.data()+8));
                                            qToLittleEndian<quint32>(socket->property("lanCivRemoteId").toUInt(), reinterpret_cast<uchar *>(q.data()+12));
                                            q[16] = char(0xc1);
                                            qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(q.data()+17));
                                            qToBigEndian<quint16>(socket->property("lanCivSeq").toUInt(), reinterpret_cast<uchar *>(q.data()+19));
                                            socket->setProperty("lanCivSeq", socket->property("lanCivSeq").toUInt() + 1);
                                            q.replace(21, 6, QByteArray::fromHex("FE FE 94 E1 25 00 FD"));
                                            civSocket->writeDatagram(q, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                        });
                                        freqPoll->start();
                                        // Read the real DATA state after the
                                        // LAN stream becomes active; the
                                        // persisted value is only a fallback.
                                        QTimer::singleShot(150, civSocket, [civSocket, socket, host]() {
                                            QByteArray q(27, '\0');
                                            qToLittleEndian<quint32>(28, reinterpret_cast<uchar *>(q.data()));
                                            const quint16 seq = quint16(socket->property("lanCivTransportSeq").toUInt());
                                            qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(q.data()+6));
                                            socket->setProperty("lanCivTransportSeq", quint32(seq + 1));
                                            qToLittleEndian<quint32>(socket->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(q.data()+8));
                                            qToLittleEndian<quint32>(socket->property("lanCivRemoteId").toUInt(), reinterpret_cast<uchar *>(q.data()+12));
                                            q[16] = char(0xc1);
                                            qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(q.data()+17));
                                            qToBigEndian<quint16>(quint16(socket->property("lanCivSeq").toUInt()), reinterpret_cast<uchar *>(q.data()+19));
                                            socket->setProperty("lanCivSeq", socket->property("lanCivSeq").toUInt() + 1);
                                            q.replace(21, 6, QByteArray::fromHex("FE FE 94 E1 1A 06"));
                                            q.append(char(0xfd));
                                            civSocket->writeDatagram(q, QHostAddress(host), socket->property("lanRemoteCivPort").toUInt() ?: 50002);
                                        });
                                    }
                                }
                                continue;
                            }
                            if (civ.size() == 16) {
                                const quint16 packetType = qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(civ.constData()+4));
                                // Type 0/1 packets are transport ACK/sequence
                                // acknowledgements, not CI-V payloads.
                                if (packetType == 0 || packetType == 1)
                                    continue;
                            }
                            if (civ.size() != 518)
                                setStatus(QStringLiteral("LAN: respuesta CI-V recibida (%1 bytes)").arg(civ.size()));
                            if (civ.size() <= 32)
                                setStatus(QStringLiteral("LAN: trama CI-V %1").arg(civ.toHex(' ')));
                            if (civ.size() > 100 && civ.size() != 518)
                                setStatus(QStringLiteral("LAN: cabecera CI-V %1").arg(civ.left(80).toHex(' ')));
                            if (civ.size() >= 27) {
                                const QByteArray frame = civ.mid(21);
                                // DATA query response: FE FE 00 94 1A 06
                                // <state> FD. Reflect the radio's real state
                                // in the LAN-specific UI property.
                                for (int off = 0; off + 7 < frame.size(); ++off) {
                                    if (quint8(frame.at(off)) == 0xfe
                                        && quint8(frame.at(off + 1)) == 0xfe
                                        && quint8(frame.at(off + 2)) == 0x00
                                        && quint8(frame.at(off + 3)) == 0x94
                                        && quint8(frame.at(off + 4)) == 0x1a
                                        && quint8(frame.at(off + 5)) == 0x06) {
                                        const bool enabled = quint8(frame.at(off + 6)) == 0x01;
                                        if (m_lanDataEnabled != enabled) {
                                            m_lanDataEnabled = enabled;
                                            QSettings().setValue(QStringLiteral("lan/dataEnabled"), enabled);
                                            emit lanDataEnabledChanged();
                                        }
                                        break;
                                    }
                                }
                                for (int off = 0; off + 10 < frame.size(); ++off) {
                                // IC-7300 LAN unsolicited frequency status:
                                // FE FE 00 94 00 00 [five BCD bytes] FD.
                                if (static_cast<unsigned char>(frame.at(off)) == 0xfe
                                    && static_cast<unsigned char>(frame.at(off + 1)) == 0xfe
                                    && static_cast<unsigned char>(frame.at(off + 2)) == 0x00
                                    && static_cast<unsigned char>(frame.at(off + 3)) == 0x94
                                    && static_cast<unsigned char>(frame.at(off + 4)) == 0x00
                                    && static_cast<unsigned char>(frame.at(off + 5)) == 0x00) {
                                    quint64 hz = 0, mult = 1;
                                    for (int i = 5; i < 10; ++i) {
                                        const unsigned char b = static_cast<unsigned char>(frame.at(off + i));
                                        hz += ((b & 0x0f) + ((b >> 4) * 10)) * mult;
                                        mult *= 100;
                                    }
                                    setStatus(QStringLiteral("LAN: frecuencia CI-V recibida: %1 Hz").arg(hz));
                                    emit lanFrequencyReceived(hz);
                                    break;
                                }
                                if (static_cast<unsigned char>(frame.at(off)) != 0xfe
                                    || static_cast<unsigned char>(frame.at(off + 1)) != 0xfe
                                    || static_cast<unsigned char>(frame.at(off + 3)) != 0x94
                                    || (static_cast<unsigned char>(frame.at(off + 4)) != 0x03
                                        && static_cast<unsigned char>(frame.at(off + 4)) != 0x11)) continue;
                                    quint64 hz = 0;
                                    quint64 mult = 1;
                                    for (int i = 5; i < 10; ++i) {
                                        const unsigned char b = static_cast<unsigned char>(frame.at(off + i));
                                        hz += ((b & 0x0f) + ((b >> 4) * 10)) * mult;
                                        mult *= 100;
                                    }
                                    setStatus(QStringLiteral("LAN: frecuencia CI-V recibida: %1 Hz").arg(hz));
                                    break;
                                }
                            }
                        }
                    });
                    setStatus(QStringLiteral("LAN: socket CI-V local abierto en puerto %1").arg(civSocket->localPort()));
                }
                QByteArray conn(0x90, '\0');
                qToLittleEndian<quint32>(0x90, reinterpret_cast<uchar *>(conn.data()));
                qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(conn.data()+4));
                qToLittleEndian<quint16>(2, reinterpret_cast<uchar *>(conn.data()+6));
                qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(conn.data()+8));
                qToLittleEndian<quint32>(savedRemoteId, reinterpret_cast<uchar *>(conn.data()+12));
                qToBigEndian<quint32>(0x80, reinterpret_cast<uchar *>(conn.data()+16));
                conn[20] = 1; conn[21] = 3;
                // CONNINFO innerseq is the authentication sequence (big
                // endian), not a fixed capability value.  WFView increments
                // it for every stream request.
                const quint16 connInnerSeq = socket->property("lanAuthSeq").isValid()
                        ? quint16(socket->property("lanAuthSeq").toUInt()) : quint16(0x32);
                qToBigEndian<quint16>(connInnerSeq, reinterpret_cast<uchar *>(conn.data()+22));
                socket->setProperty("lanAuthSeq", quint32(connInnerSeq + 1));
                qToLittleEndian<quint16>(expected, reinterpret_cast<uchar *>(conn.data()+26));
                qToLittleEndian<quint32>(token, reinterpret_cast<uchar *>(conn.data()+28));
                // WFView advertises the IC-7300 common capability in every
                // stream request; without it some firmware accepts login
                // but silently ignores conninfo.
                qToLittleEndian<quint16>(0x8010, reinterpret_cast<uchar *>(conn.data()+0x27));
                QByteArray connName = QByteArrayLiteral("IC-7300MK2");
                memcpy(conn.data()+0x40, connName.constData(), size_t(connName.size()));
                QByteArray encodedUser = lanPasscode(m_lanUser);
                memcpy(conn.data()+0x60, encodedUser.constData(), size_t(encodedUser.size()));
                conn[0x70] = 1; // RX enabled
                conn[0x71] = 0; // TX disabled for this probe
                conn[0x72] = 4; // LPCM16
                qToBigEndian<quint32>(48000, reinterpret_cast<uchar *>(conn.data()+0x74));
                qToBigEndian<quint32>(48000, reinterpret_cast<uchar *>(conn.data()+0x78));
                qToBigEndian<quint32>(socket->property("lanCivPort").toUInt(), reinterpret_cast<uchar *>(conn.data()+0x7c));
                qToBigEndian<quint32>(socket->property("lanAudioPort").toUInt(), reinterpret_cast<uchar *>(conn.data()+0x80));
                qToBigEndian<quint32>(320, reinterpret_cast<uchar *>(conn.data()+0x84));
                conn[0x88] = 1;
                socket->writeDatagram(conn, QHostAddress(host), 50001);
                socket->setProperty("lanConnPacket", conn);
                socket->setProperty("lanPingSeq", 0u);
                socket->setProperty("lanControlPingSeq", 0u);
                auto *controlPing = new QTimer(socket);
                controlPing->setInterval(100);
                connect(controlPing, &QTimer::timeout, socket, [socket, host, id]() {
                    if (!socket->property("lanConnected").toBool()) return;
                    QByteArray ping(21, '\0');
                    qToLittleEndian<quint32>(21, reinterpret_cast<uchar *>(ping.data()));
                    qToLittleEndian<quint16>(7, reinterpret_cast<uchar *>(ping.data()+4));
                    const quint16 seq = quint16(socket->property("lanControlPingSeq").toUInt());
                    qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(ping.data()+6));
                    qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(ping.data()+8));
                    qToLittleEndian<quint32>(socket->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(ping.data()+12));
                    ping[16] = 1;
                    qToLittleEndian<quint32>(quint32(QTime::currentTime().msecsSinceStartOfDay()),
                                             reinterpret_cast<uchar *>(ping.data()+17));
                    socket->writeDatagram(ping, QHostAddress(host), 50001);
                });
                controlPing->start();
                auto *controlIdle = new QTimer(socket);
                controlIdle->setInterval(100);
                connect(controlIdle, &QTimer::timeout, socket, [socket, host, id]() {
                    if (!socket->property("lanConnected").toBool()) return;
                    QByteArray idle(16, '\0');
                    qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(idle.data()));
                    qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(idle.data()+4));
                    const quint16 idleSeq = quint16(socket->property("lanPingSeq").toUInt());
                    qToLittleEndian<quint16>(idleSeq, reinterpret_cast<uchar *>(idle.data()+6));
                    socket->setProperty("lanPingSeq", quint32(idleSeq + 1));
                    qToLittleEndian<quint32>(id, reinterpret_cast<uchar *>(idle.data()+8));
                    qToLittleEndian<quint32>(socket->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(idle.data()+12));
                    socket->writeDatagram(idle, QHostAddress(host), 50001);
                });
                controlIdle->start();
                socket->setProperty("lanConnSent", true);
                setStatus(QStringLiteral("LAN: solicitud CI-V enviada; esperando respuesta del puerto 50002"));
                for (int retry = 1; retry <= 5; ++retry) {
                    QTimer::singleShot(retry * 500, socket, [socket, host, conn]() {
                        if (!socket->property("lanConnSent").toBool()
                            || socket->property("lanConnInfoReceived").toBool()) return;
                        socket->writeDatagram(conn, QHostAddress(host), 50001);
                    });
                }
                socket->setProperty("lanLoginSent", false);
            } else {
                setStatus(QStringLiteral("LAN: respuesta recibida, token no coincide"));
            }
        }
        }
    });
    QTimer::singleShot(10000, socket, [this, socket]() {
        if (!socket->property("lanProbeResponded").toBool()) {
            setStatus(QStringLiteral("LAN: sin respuesta; comprueba IP y control remoto"));
            socket->deleteLater();
        } else if (socket->property("lanLoginSent").toBool()
                   && !socket->property("lanConnInfoReceived").toBool()) {
            setStatus(QStringLiteral("LAN: sin confirmación de sesión; revisa usuario/contraseña y puertos UDP"));
            socket->deleteLater();
        }
    });
}

void ApplicationLauncher::disconnectLanConnection()
{
    shutdownLanConnection();
    const auto sockets = findChildren<QUdpSocket *>();
    for (QUdpSocket *s : sockets) {
        if (s->property("lanRemoteId").isValid() || s->property("lanConnSent").isValid())
            s->deleteLater();
    }
    if (m_lanConnected) {
        m_lanConnected = false;
        emit lanConnectionChanged();
    }
    setStatus(QStringLiteral("LAN: desconectada"));
}

void ApplicationLauncher::shutdownLanConnection()
{
    const auto sockets = findChildren<QUdpSocket *>();
    for (QUdpSocket *s : sockets) {
        if (!s->property("lanLocalIp").isValid())
            continue;
        const QString host = m_lanHost;
        // WFView first destroys the data/audio objects. Their destructors send
        // the stream close packets on their own sockets, then the handler sends
        // one token-removal request and finally its control disconnect.
        for (const char *prop : {"lanCivSocket", "lanAudioSocket"}) {
            auto *stream = qobject_cast<QUdpSocket *>(s->property(prop).value<QObject *>());
            if (!stream) continue;
            QByteArray close(16, '\0');
            qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(close.data()));
            qToLittleEndian<quint16>(5, reinterpret_cast<uchar *>(close.data()+4));
            qToLittleEndian<quint32>(s->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(close.data()+8));
            qToLittleEndian<quint32>(s->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(close.data()+12));
            const quint16 remotePort = (QString::fromLatin1(prop) == QStringLiteral("lanCivSocket"))
                    ? quint16(s->property("lanRemoteCivPort").toUInt() ?: 50002)
                    : quint16(s->property("lanRemoteAudioPort").toUInt() ?: 50003);
            stream->writeDatagram(close, QHostAddress(host), remotePort);
            if (QString::fromLatin1(prop) == QStringLiteral("lanCivSocket")) {
                QByteArray openClose(0x16, '\0');
                qToLittleEndian<quint32>(0x16, reinterpret_cast<uchar *>(openClose.data()));
                const quint16 seq = quint16(s->property("lanCivTransportSeq").toUInt());
                qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(openClose.data()+6));
                s->setProperty("lanCivTransportSeq", quint32(seq + 1));
                qToLittleEndian<quint32>(s->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(openClose.data()+8));
                qToLittleEndian<quint32>(s->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(openClose.data()+12));
                qToLittleEndian<quint16>(0x01c0, reinterpret_cast<uchar *>(openClose.data()+16));
                qToBigEndian<quint16>(quint16(s->property("lanCivSeq").toUInt()), reinterpret_cast<uchar *>(openClose.data()+19));
                openClose[21] = char(0x00);
                stream->writeDatagram(openClose, QHostAddress(host), remotePort);
            }
            stream->close();
        }
        // Token packet layout matches WFView's token_packet exactly.
        QByteArray token(0x40, '\0');
        qToLittleEndian<quint32>(0x40, reinterpret_cast<uchar *>(token.data()));
        qToLittleEndian<quint16>(0, reinterpret_cast<uchar *>(token.data()+4));
        const quint16 seq = quint16(s->property("lanPingSeq").toUInt());
        qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(token.data()+6));
        s->setProperty("lanPingSeq", quint32(seq + 1));
        qToLittleEndian<quint32>(s->property("lanId").toUInt(), reinterpret_cast<uchar *>(token.data()+8));
        qToLittleEndian<quint32>(s->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(token.data()+12));
        qToBigEndian<quint32>(0x30, reinterpret_cast<uchar *>(token.data()+16));
        token[20] = char(0x01); // requestreply
        token[21] = char(0x01); // token removal
        const quint16 authSeq = quint16(s->property("lanAuthSeq").toUInt());
        qToBigEndian<quint16>(authSeq, reinterpret_cast<uchar *>(token.data()+22));
        s->setProperty("lanAuthSeq", quint32(authSeq + 1));
        qToLittleEndian<quint16>(quint16(s->property("lanTokRequest").toUInt()), reinterpret_cast<uchar *>(token.data()+26));
        qToLittleEndian<quint32>(s->property("lanToken").toUInt(), reinterpret_cast<uchar *>(token.data()+28));
        qToBigEndian<quint16>(0x0798, reinterpret_cast<uchar *>(token.data()+36));
        s->writeDatagram(token, QHostAddress(host), 50001);

        QByteArray disconnect(16, '\0');
        qToLittleEndian<quint32>(16, reinterpret_cast<uchar *>(disconnect.data()));
        qToLittleEndian<quint16>(5, reinterpret_cast<uchar *>(disconnect.data()+4));
        const quint16 dseq = quint16(s->property("lanPingSeq").toUInt());
        qToLittleEndian<quint16>(dseq, reinterpret_cast<uchar *>(disconnect.data()+6));
        qToLittleEndian<quint32>(s->property("lanId").toUInt(), reinterpret_cast<uchar *>(disconnect.data()+8));
        qToLittleEndian<quint32>(s->property("lanRemoteId").toUInt(), reinterpret_cast<uchar *>(disconnect.data()+12));
        s->writeDatagram(disconnect, QHostAddress(host), 50001);
        s->close();
    }
}

void ApplicationLauncher::testLanMode()
{
    testLanModeName(QStringLiteral("USB"));
}

void ApplicationLauncher::testLanModeName(const QString &mode)
{
    QUdpSocket *civSocket = nullptr;
    QUdpSocket *owner = nullptr;
    for (QUdpSocket *s : findChildren<QUdpSocket *>()) {
        if (s->property("lanIsCiv").toBool() && s->isOpen()) {
            civSocket = s;
            owner = qobject_cast<QUdpSocket *>(s->parent());
            break;
        }
        if (s->property("lanCivSocket").isValid()) {
            owner = s;
            civSocket = qobject_cast<QUdpSocket *>(s->property("lanCivSocket").value<QObject *>());
            break;
        }
    }
    if (!civSocket || !owner
        || !(owner->property("lanCivRemoteId").toUInt()
             || owner->property("lanRemoteId").toUInt())) {
        setStatus(QStringLiteral("LAN: no hay canal CI-V activo para probar el modo"));
        return;
    }
    const quint32 remoteId = owner->property("lanCivRemoteId").toUInt()
                           ?: owner->property("lanRemoteId").toUInt();
    const QHash<QString, quint8> modeCodes{{QStringLiteral("LSB"),0x00},{QStringLiteral("USB"),0x01},{QStringLiteral("AM"),0x02},{QStringLiteral("CW"),0x03},{QStringLiteral("RTTY"),0x04},{QStringLiteral("FM"),0x05},{QStringLiteral("CW-R"),0x07},{QStringLiteral("RTTY-R"),0x08}};
    const quint8 code = modeCodes.value(mode, 0x01);
    // WFView writes the mode with the compact CI-V command (mode byte only).
    // The longer 26 00 / mode / data / filter form is a read/state frame and
    // is ignored by the IC-7300 when used as a mode write.
    QByteArray civ = QByteArray::fromHex("FE FE 94 E1 26 01 FD");
    civ[5] = char(code);
    QByteArray packet(21, '\0');
    qToLittleEndian<quint32>(21 + civ.size(), reinterpret_cast<uchar *>(packet.data()));
    const quint16 seq = quint16(owner->property("lanCivTransportSeq").toUInt());
    qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(packet.data()+6));
    owner->setProperty("lanCivTransportSeq", quint32(seq + 1));
    qToLittleEndian<quint32>(owner->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(packet.data()+8));
    qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(packet.data()+12));
    packet[16] = char(0xc1);
    qToLittleEndian<quint16>(civ.size(), reinterpret_cast<uchar *>(packet.data()+17));
    qToBigEndian<quint16>(quint16(owner->property("lanCivSeq").toUInt()), reinterpret_cast<uchar *>(packet.data()+19));
    owner->setProperty("lanCivSeq", owner->property("lanCivSeq").toUInt() + 1);
    packet.append(civ);
    civSocket->writeDatagram(packet, QHostAddress(m_lanHost), owner->property("lanRemoteCivPort").toUInt() ?: 50002);
    setStatus(QStringLiteral("LAN: comando de modo %1 enviado por CI-V (E1): %2").arg(mode, civ.toHex(' ')));
}

void ApplicationLauncher::setLanFrequency(qulonglong frequencyHz)
{
    QUdpSocket *civSocket = nullptr;
    QUdpSocket *owner = nullptr;
    for (QUdpSocket *s : findChildren<QUdpSocket *>()) {
        if (s->property("lanIsCiv").toBool() && s->isOpen()) {
            civSocket = s;
            owner = qobject_cast<QUdpSocket *>(s->parent());
            break;
        }
    }
    if (!civSocket || !owner) {
        setStatus(QStringLiteral("LAN: no hay canal CI-V activo para cambiar frecuencia"));
        return;
    }
    const quint32 remoteId = owner->property("lanCivRemoteId").toUInt()
                           ?: owner->property("lanRemoteId").toUInt();
    if (!remoteId) return;
    QByteArray civ = QByteArray::fromHex("FE FE 94 E1 25 00");
    quint64 value = frequencyHz;
    for (int i = 0; i < 5; ++i) {
        const quint8 lo = quint8(value % 10); value /= 10;
        const quint8 hi = quint8(value % 10); value /= 10;
        civ.append(char(lo | (hi << 4)));
    }
    civ.append(char(0xfd));
    QByteArray packet(21, '\0');
    qToLittleEndian<quint32>(21 + civ.size(), reinterpret_cast<uchar *>(packet.data()));
    const quint16 seq = quint16(owner->property("lanCivTransportSeq").toUInt());
    qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(packet.data()+6));
    owner->setProperty("lanCivTransportSeq", quint32(seq + 1));
    qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(packet.data()+8));
    qToLittleEndian<quint32>(owner->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(packet.data()+12));
    packet[16] = char(0xc1);
    qToLittleEndian<quint16>(civ.size(), reinterpret_cast<uchar *>(packet.data()+17));
    const quint16 civSeq = quint16(owner->property("lanCivSeq").toUInt());
    qToBigEndian<quint16>(civSeq, reinterpret_cast<uchar *>(packet.data()+19));
    owner->setProperty("lanCivSeq", quint32(civSeq + 1));
    packet.append(civ);
    civSocket->writeDatagram(packet, QHostAddress(m_lanHost), owner->property("lanRemoteCivPort").toUInt() ?: 50002);
    setStatus(QStringLiteral("LAN: frecuencia %1 Hz enviada por CI-V").arg(frequencyHz));
}

void ApplicationLauncher::setLanDataEnabled(bool enabled, const QString &mode)
{
    QUdpSocket *civSocket = nullptr;
    QUdpSocket *owner = nullptr;
    for (QUdpSocket *s : findChildren<QUdpSocket *>()) {
        if (s->property("lanIsCiv").toBool()) { civSocket = s; owner = qobject_cast<QUdpSocket *>(s->parent()); break; }
    }
    if (!civSocket || !owner) {
        setStatus(QStringLiteral("LAN: no hay canal CI-V activo para cambiar DATA"));
        return;
    }
    const quint32 remoteId = owner->property("lanCivRemoteId").toUInt() ?: owner->property("lanRemoteId").toUInt();
    const QHash<QString, quint8> modeCodes{{QStringLiteral("LSB"),0x00},{QStringLiteral("USB"),0x01},{QStringLiteral("AM"),0x02},{QStringLiteral("CW"),0x03},{QStringLiteral("RTTY"),0x04},{QStringLiteral("FM"),0x05},{QStringLiteral("CW-R"),0x07},{QStringLiteral("RTTY-R"),0x08}};
    const quint8 modeCode = modeCodes.value(mode, 0x01);
    // DATA is part of the standard CI-V 0x26 mode command.  The previous
    // 0x1A/0x06 packet is a different radio function and is ignored here.
    QByteArray civ = QByteArray::fromHex("FE FE 94 E1 26 00 01 00 01 FD");
    civ[6] = char(modeCode);
    civ[7] = char(enabled ? 0x01 : 0x00);
    QByteArray packet(21, '\0');
    qToLittleEndian<quint32>(21 + civ.size(), reinterpret_cast<uchar *>(packet.data()));
    const quint16 seq = quint16(owner->property("lanCivTransportSeq").toUInt());
    qToLittleEndian<quint16>(seq, reinterpret_cast<uchar *>(packet.data()+6)); owner->setProperty("lanCivTransportSeq", quint32(seq + 1));
    qToLittleEndian<quint32>(owner->property("lanCivId").toUInt(), reinterpret_cast<uchar *>(packet.data()+8));
    qToLittleEndian<quint32>(remoteId, reinterpret_cast<uchar *>(packet.data()+12)); packet[16] = char(0xc1);
    qToLittleEndian<quint16>(civ.size(), reinterpret_cast<uchar *>(packet.data()+17));
    qToBigEndian<quint16>(quint16(owner->property("lanCivSeq").toUInt()), reinterpret_cast<uchar *>(packet.data()+19));
    owner->setProperty("lanCivSeq", owner->property("lanCivSeq").toUInt() + 1); packet.append(civ);
    civSocket->writeDatagram(packet, QHostAddress(m_lanHost), owner->property("lanRemoteCivPort").toUInt() ?: 50002);
    if (m_lanDataEnabled != enabled) {
        m_lanDataEnabled = enabled;
        QSettings().setValue(QStringLiteral("lan/dataEnabled"), enabled);
        emit lanDataEnabledChanged();
    }
    setStatus(QStringLiteral("LAN: DATA %1 enviado por CI-V").arg(enabled ? QStringLiteral("activado") : QStringLiteral("desactivado")));
}

void ApplicationLauncher::setCompactWindowY(int value)
{
    if (value == m_compactWindowY) return;
    m_compactWindowY = value;
    QSettings().setValue(QStringLiteral("compactWindow/y"), value);
    emit compactWindowPositionChanged();
}

int ApplicationLauncher::superWindowX() const { return m_superWindowX; }
int ApplicationLauncher::superWindowY() const { return m_superWindowY; }
void ApplicationLauncher::setSuperWindowX(int value)
{
    if (value == m_superWindowX) return;
    m_superWindowX = value;
    QSettings().setValue(QStringLiteral("superWindow/x"), value);
    emit compactWindowPositionChanged();
}
void ApplicationLauncher::setSuperWindowY(int value)
{
    if (value == m_superWindowY) return;
    m_superWindowY = value;
    QSettings().setValue(QStringLiteral("superWindow/y"), value);
    emit compactWindowPositionChanged();
}

int ApplicationLauncher::compactWindowWidth() const
{
    return m_compactWindowWidth;
}

void ApplicationLauncher::setCompactWindowWidth(int value)
{
    value = std::max(780, value);
    if (value == m_compactWindowWidth) return;
    m_compactWindowWidth = value;
    QSettings().setValue(QStringLiteral("compactWindow/width"), value);
    emit compactWindowSizeChanged();
}

bool ApplicationLauncher::compactModePreferred() const
{
    return m_compactModePreferred;
}

void ApplicationLauncher::setCompactModePreferred(bool value)
{
    if (value == m_compactModePreferred) return;
    m_compactModePreferred = value;
    QSettings().setValue(QStringLiteral("compactWindow/preferred"), value);
    emit compactModePreferredChanged();
}

int ApplicationLauncher::mainWindowX() const { return m_mainWindowX; }
int ApplicationLauncher::mainWindowY() const { return m_mainWindowY; }

void ApplicationLauncher::setMainWindowX(int value)
{
    if (value == m_mainWindowX) return;
    m_mainWindowX = value;
    QSettings().setValue(QStringLiteral("mainWindow/x"), value);
    emit mainWindowPositionChanged();
}

void ApplicationLauncher::setMainWindowY(int value)
{
    if (value == m_mainWindowY) return;
    m_mainWindowY = value;
    QSettings().setValue(QStringLiteral("mainWindow/y"), value);
    emit mainWindowPositionChanged();
}

bool ApplicationLauncher::compactAlwaysOnTop() const
{
    return m_compactAlwaysOnTop;
}

void ApplicationLauncher::setCompactAlwaysOnTop(bool value)
{
    if (value == m_compactAlwaysOnTop) return;
    m_compactAlwaysOnTop = value;
    QSettings().setValue(QStringLiteral("compactWindow/alwaysOnTop"), value);
    emit compactAlwaysOnTopChanged();
}

QString ApplicationLauncher::status() const
{
    return m_status;
}

bool ApplicationLauncher::decodiumRunning() const
{
    return m_decodiumProcess
           && m_decodiumProcess->state() != QProcess::NotRunning;
}

bool ApplicationLauncher::launchDecodium()
{
    if (decodiumRunning()) {
        setStatus(QStringLiteral("DECODIUM 4 ya está activo"));
        return true;
    }

    const QFileInfo executable(kDecodiumExecutable);
    if (!executable.exists() || !executable.isFile()) {
        setStatus(QStringLiteral("No se encontró DECODIUM 4"));
        return false;
    }
    if (!executable.isExecutable()) {
        setStatus(QStringLiteral("DECODIUM 4 no tiene permiso de ejecución"));
        return false;
    }

    stopFldigi();
    stopQsstv();
    stopJs8call();

    m_decodiumProcess->setProgram(executable.absoluteFilePath());
    m_decodiumProcess->setArguments({});
    m_decodiumProcess->setWorkingDirectory(executable.absolutePath());
    m_decodiumProcess->start();
    return m_decodiumProcess->waitForStarted(1200);
}

void ApplicationLauncher::stopDecodium()
{
    if (!decodiumRunning()) {
        return;
    }

    setStatus(QStringLiteral("Cerrando DECODIUM 4…"));
    m_decodiumProcess->terminate();
    QTimer::singleShot(1800, m_decodiumProcess, [this]() {
        if (decodiumRunning()) {
            m_decodiumProcess->kill();
        }
    });
}

bool ApplicationLauncher::fldigiRunning() const
{
    return m_fldigiProcess
           && m_fldigiProcess->state() != QProcess::NotRunning;
}

bool ApplicationLauncher::launchFldigi()
{
    if (fldigiRunning()) {
        return true;
    }

    const QFileInfo executable(kFldigiExecutable);
    if (!executable.exists() || !executable.isExecutable()) {
        setStatus(QStringLiteral("No se encontró FLDigi en /usr/bin/fldigi"));
        return false;
    }

    stopDecodium();
    stopQsstv();
    stopJs8call();
    m_fldigiProcess->setProgram(executable.absoluteFilePath());
    m_fldigiProcess->setArguments({});
    m_fldigiProcess->setWorkingDirectory(executable.absolutePath());
    m_fldigiProcess->start();
    return m_fldigiProcess->waitForStarted(1200);
}

void ApplicationLauncher::stopFldigi()
{
    if (!fldigiRunning()) {
        return;
    }

    setStatus(QStringLiteral("Cerrando FLDigi…"));
    m_fldigiProcess->terminate();
    QTimer::singleShot(1800, m_fldigiProcess, [this]() {
        if (fldigiRunning()) {
            m_fldigiProcess->kill();
        }
    });
}

void ApplicationLauncher::setFldigiMode(const QString &modeName)
{
    if (modeName.isEmpty()) return;

    QString escaped = modeName.toHtmlEscaped();
    const QByteArray body = QStringLiteral(
        "<?xml version=\"1.0\"?>"
        "<methodCall><methodName>modem.set_by_name</methodName>"
        "<params><param><value><string>%1</string></value>"
        "</param></params></methodCall>").arg(escaped).toUtf8();

    const auto sendRequest = [this, body]() {
        QNetworkRequest request(QUrl(QStringLiteral("http://127.0.0.1:7362/")));
        request.setHeader(QNetworkRequest::ContentTypeHeader,
                          QStringLiteral("text/xml"));
        QNetworkReply *reply = m_network->post(request, body);
        connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
    };

    sendRequest();
    QTimer::singleShot(700, this, sendRequest);
    QTimer::singleShot(1600, this, sendRequest);
    QTimer::singleShot(2800, this, sendRequest);
}

void ApplicationLauncher::setFldigiReverse(bool enabled)
{
    const QByteArray body = QStringLiteral(
        "<?xml version=\"1.0\"?>"
        "<methodCall><methodName>main.set_reverse</methodName>"
        "<params><param><value><boolean>%1</boolean></value>"
        "</param></params></methodCall>")
        .arg(enabled ? 1 : 0).toUtf8();

    const auto sendRequest = [this, body]() {
        QNetworkRequest request(QUrl(QStringLiteral("http://127.0.0.1:7362/")));
        request.setHeader(QNetworkRequest::ContentTypeHeader,
                          QStringLiteral("text/xml"));
        QNetworkReply *reply = m_network->post(request, body);
        connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
    };

    sendRequest();
    QTimer::singleShot(750, this, sendRequest);
    QTimer::singleShot(1650, this, sendRequest);
    QTimer::singleShot(2850, this, sendRequest);
}

bool ApplicationLauncher::qsstvRunning() const
{
    return m_qsstvProcess
           && m_qsstvProcess->state() != QProcess::NotRunning;
}

bool ApplicationLauncher::launchQsstv()
{
    if (qsstvRunning()) {
        return true;
    }

    const QFileInfo executable(kQsstvExecutable);
    if (!executable.exists() || !executable.isExecutable()) {
        setStatus(QStringLiteral("No se encontró QSSTV en /usr/bin/qsstv"));
        return false;
    }

    stopDecodium();
    stopFldigi();
    stopJs8call();
    m_qsstvProcess->setProgram(executable.absoluteFilePath());
    m_qsstvProcess->setArguments({});
    m_qsstvProcess->setWorkingDirectory(executable.absolutePath());
    m_qsstvProcess->start();
    return m_qsstvProcess->waitForStarted(1200);
}

void ApplicationLauncher::stopQsstv()
{
    if (!qsstvRunning()) {
        return;
    }

    setStatus(QStringLiteral("Cerrando QSSTV…"));
    m_qsstvProcess->terminate();
    QTimer::singleShot(1800, m_qsstvProcess, [this]() {
        if (qsstvRunning()) {
            m_qsstvProcess->kill();
        }
    });
}

bool ApplicationLauncher::js8callRunning() const
{
    return m_js8callUsesFlatpak
           || (m_js8callProcess
               && m_js8callProcess->state() != QProcess::NotRunning);
}

bool ApplicationLauncher::launchJs8call()
{
    if (js8callRunning()) return true;
    const QFileInfo executable(kJs8callExecutable);
    if (executable.exists() && executable.isExecutable()) {
        m_js8callUsesFlatpak = false;
        m_js8callProcess->setProgram(executable.absoluteFilePath());
        m_js8callProcess->setArguments({});
        m_js8callProcess->setWorkingDirectory(executable.absolutePath());
    } else {
        const QFileInfo flatpak(kFlatpakExecutable);
        if (!flatpak.exists() || !flatpak.isExecutable()) {
            setStatus(QStringLiteral("No se encontró JS8Call"));
            return false;
        }
        m_js8callProcess->setProgram(flatpak.absoluteFilePath());
        m_js8callUsesFlatpak = true;
        m_js8callProcess->setArguments({QStringLiteral("run"),
                                        kJs8callFlatpakId});
        m_js8callProcess->setWorkingDirectory(flatpak.absolutePath());
    }
    stopDecodium();
    stopFldigi();
    stopQsstv();
    m_js8callProcess->start();
    return m_js8callProcess->waitForStarted(1200);
}

void ApplicationLauncher::stopJs8call()
{
    if (m_js8callUsesFlatpak) {
        QProcess::startDetached(kFlatpakExecutable,
                                {QStringLiteral("kill"),
                                 kJs8callFlatpakId});
        m_js8callUsesFlatpak = false;
    }
    if (!js8callRunning()) {
        emit js8callRunningChanged();
        return;
    }
    setStatus(QStringLiteral("Cerrando JS8Call…"));
    m_js8callProcess->terminate();
    QTimer::singleShot(1800, m_js8callProcess, [this]() {
        if (js8callRunning()) m_js8callProcess->kill();
    });
}

void ApplicationLauncher::setStatus(const QString &status)
{
    if (m_status == status) {
        return;
    }
    m_status = status;
    emit statusChanged();
}
