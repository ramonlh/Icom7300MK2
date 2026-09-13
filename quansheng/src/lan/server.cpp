// SPDX-License-Identifier: GPL-2.0-only
#include "eventjson.h"
#ifdef QDOCK_SERIAL
#include "lan/serialsource.h"
#endif
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonDocument>
#include <QTcpServer>
#include "qdock_build_timestamp.h"
#include <QTcpSocket>
#include <QTextStream>
#include <QTimer>
#include <QUuid>
#include <csignal>

namespace {
constexpr qint64 maxRequest = 4096;
constexpr qint64 maxQueue = 1024 * 1024;
constexpr qint64 eventQueueLimit = 256 * 1024;
constexpr int maxClients = 8;
volatile std::sig_atomic_t stopRequested = 0;

void requestStop(int) { stopRequested = 1; }

// Diagnostic replays are per connection; live acquisition is shared server-wide.
class ClientConnection final : public QObject {
public:
    ClientConnection(QTcpSocket* socket, QString path, QByteArray token, QObject* source)
        : QObject(socket), socket_(socket), path_(std::move(path)),
          token_(std::move(token)), input_(path_), source_(source) {
        qInfo().noquote() << "qdock cliente conectado:"
                          << "ip=" + socket_->peerAddress().toString()
                          << "host=" + (socket_->peerName().isEmpty()
                                             ? QStringLiteral("(sin-nombre)")
                                             : socket_->peerName())
                          << "puerto=" + QString::number(socket_->peerPort())
                          << "local=" + socket_->localAddress().toString()
                          << QStringLiteral("localPuerto=") + QString::number(socket_->localPort());
        socket_->setReadBufferSize(maxRequest + 1);
        connect(socket_, &QTcpSocket::readyRead, this, [this] { receive(); });
        connect(socket_, &QTcpSocket::disconnected, this, [this] {
            qInfo().noquote() << "qdock cliente desconectado:"
                              << "ip=" + socket_->peerAddress().toString()
                              << "host=" + (socket_->peerName().isEmpty()
                                                 ? QStringLiteral("(sin-nombre)")
                                                 : socket_->peerName());
        });
        connect(&timer_, &QTimer::timeout, this, [this] { tick(); });
        QTimer::singleShot(5000, this, [this] {
            if (!authenticated_) fail("authentication_timeout");
        });
    }
private:
    bool send(QJsonObject object) {
        if (socket_->state() != QAbstractSocket::ConnectedState) return false;
        const auto line = QJsonDocument(object).toJson(QJsonDocument::Compact) + '\n';
        // A live serial source can produce bursts faster than a GUI client can
        // consume them.  Observations are lossy by design, so shed event
        // messages while the per-client queue is backed up instead of
        // aborting the whole authenticated session.
        if (object.value("message").toString() == "event"
            && socket_->bytesToWrite() > eventQueueLimit)
            return true;
        if (socket_->bytesToWrite() + line.size() > maxQueue) {
            socket_->abort(); // Never accumulate unbounded data for a slow client.
            timer_.stop();
            return false;
        }
        return socket_->write(line) == line.size();
    }
    void fail(const QString& code) {
        timer_.stop();
        send({{"message", "error"}, {"code", code}});
        closing_ = true;
        socket_->disconnectFromHost();
    }
    void receive() {
        while (!closing_ && socket_->bytesAvailable()) {
            buffer_ += socket_->read(maxRequest + 1 - buffer_.size());
            qsizetype newline;
            while (!closing_ && (newline = buffer_.indexOf('\n')) >= 0) {
                if (newline > maxRequest) { fail("message_too_large"); return; }
                const auto line = buffer_.left(newline);
                buffer_.remove(0, newline + 1);
                QJsonParseError error;
                const auto doc = QJsonDocument::fromJson(line, &error);
                if (error.error != QJsonParseError::NoError || !doc.isObject()) {
                    fail("invalid_json"); return;
                }
                request(doc.object());
            }
            if (buffer_.size() > maxRequest) { fail("message_too_large"); return; }
        }
    }
    void request(const QJsonObject& object) {
        const auto message = object.value("message").toString();
        if (!authenticated_) {
            if (message != "hello" || object.value("protocol") != "qdock-lan/1") {
                fail("protocol_mismatch"); return;
            }
            if (object.value("token").toString().toUtf8() != token_) {
                fail("unauthorized"); return;
            }
            authenticated_ = true;
            qInfo().noquote() << "qdock cliente autenticado:"
                              << "ip=" + socket_->peerAddress().toString()
                              << "host=" + (socket_->peerName().isEmpty()
                                                 ? QStringLiteral("(sin-nombre)")
                                                 : socket_->peerName());
            send({{"message", "welcome"}, {"protocol", "qdock-lan/1"},
                  {"source", source_ ? "serial" : "replay"}, {"serialAvailable", source_ != nullptr},
                  {"txControlAvailable", false}, {"radioControlAvailable", false},
                  {"normalizedStateAvailable", false}});
        } else if (message == "ping") {
            send({{"message", "pong"}});
        } else if (message == "subscribe" && !started_) {
#ifdef QDOCK_SERIAL
            if (auto* serial = qobject_cast<SerialSource*>(source_)) {
                started_ = true;
                connect(serial, &SerialSource::message, this, [this](const QJsonObject& object) {
                    if (!closing_) send(object);
                });
                send(serial->snapshot());
                return;
            }
#endif
            if (!input_.open(QIODevice::ReadOnly)) { fail("replay_open_failed"); return; }
            started_ = true;
            session_ = QUuid::createUuid().toString(QUuid::WithoutBraces);
            send({{"message", "source_status"}, {"source", "replay"},
                  {"session", session_}, {"status", "replaying"}});
            timer_.start(10);
        } else {
            // Includes PTT, EEPROM, raw-write and every non-whitelisted control.
            fail("unsupported_message");
        }
    }
    void tick() {
        const auto bytes = input_.read(256);
        if (input_.error() != QFileDevice::NoError) { fail("replay_read_failed"); return; }
        totalBytes_ += bytes.size();
        const auto events = parser_.feed(
            reinterpret_cast<const std::uint8_t*>(bytes.constData()), bytes.size());
        for (const auto& event : events) {
            if (!send({{"message", "event"}, {"source", "replay"},
                       {"session", session_}, {"sequence", QString::number(++sequence_)},
                       {"observedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
                       {"quality", "candidate"}, {"decoder", "qdock-probe/0.1.0"},
                       {"event", qdock::eventJson(event)}})) return;
        }
        if (input_.atEnd()) {
            timer_.stop();
            input_.close();
            send({{"message", "stats"}, {"session", session_},
                  {"bytes", QString::number(totalBytes_)},
                  {"events", QString::number(sequence_)},
                  {"discarded", QString::number(parser_.discarded())},
                  {"pending", QString::number(parser_.pending())}});
            send({{"message", "source_status"}, {"source", "replay"},
                  {"session", session_}, {"status", "ended"}});
        }
    }
    QTcpSocket* socket_;
    QString path_;
    QByteArray token_, buffer_;
    QFile input_;
    QObject* source_;
    QTimer timer_;
    qdock::Parser parser_;
    QString session_;
    qint64 totalBytes_ = 0;
    quint64 sequence_ = 0;
    bool authenticated_ = false, started_ = false, closing_ = false;
};
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    app.setApplicationName("qdock-server");
    QCommandLineParser cli;
    cli.setApplicationDescription("Servidor Quansheng de observación READ-ONLY; sin control de radio.");
    cli.addHelpOption();
    cli.addOptions({{"replay", "Captura binaria regular, nunca un dispositivo.", "archivo"},
                    {"serial", "Puerto serie autorizado para escucha READ-ONLY.", "dispositivo"},
                    {"capture", "Captura cruda en archivo nuevo del servidor; requiere --serial.", "archivo"},
                    {"seconds", "Duración serie (1–86400); no hay reapertura automática.", "segundos", "15"},
                    {"listen", "Dirección IP local de escucha.", "ip", "127.0.0.1"},
                    {"port", "Puerto TCP (0 elige uno libre).", "puerto", "8765"}});
    cli.process(app);
    auto fail = [](const QString& text) { QTextStream(stderr) << text << Qt::endl; return 1; };
    bool ok = false;
    const int port = cli.value("port").toInt(&ok);
    const QHostAddress address(cli.value("listen"));
    const QByteArray token = qgetenv("QDOCK_LAN_TOKEN");
    if (!cli.positionalArguments().isEmpty() || !ok || port < 0 || port > 65535 || address.isNull())
        return fail("Dirección o puerto inválido.");
    if (token.size() < 16 || token.size() > 256 || QString::fromUtf8(token).toUtf8() != token)
        return fail("QDOCK_LAN_TOKEN requiere 16–256 bytes UTF-8.");
    const QFileInfo replay(cli.value("replay"));
    if (cli.isSet("replay") == cli.isSet("serial"))
        return fail("Elige exactamente --replay o --serial.");
    if (cli.isSet("replay") && (!replay.isFile() || !replay.isReadable()))
        return fail("--replay requiere un archivo regular legible.");
    const int seconds = cli.value("seconds").toInt(&ok);
    if (!ok || seconds < 1 || seconds > 86400 || (cli.isSet("seconds") && !cli.isSet("serial")))
        return fail("--seconds requiere --serial y duración 1–86400.");
    if (cli.isSet("serial") && cli.value("serial").isEmpty()) return fail("Puerto serie vacío.");
    if (cli.isSet("capture") && (!cli.isSet("serial") || cli.value("capture").isEmpty()))
        return fail("--capture requiere --serial y un nombre de archivo nuevo.");
    qInfo().noquote() << "Compilación qdock-server:"
                      << QStringLiteral(QDOCK_BUILD_TIMESTAMP);
    QObject* source = nullptr;
#ifdef QDOCK_SERIAL
    SerialSource serial;
    if (cli.isSet("serial")) {
        source = &serial;
        QObject::connect(&app, &QCoreApplication::aboutToQuit, &serial, &SerialSource::stop);
    }
#else
    if (cli.isSet("serial")) return fail("Compilado sin SerialPort; configura QDOCK_SERIAL=ON.");
#endif
    QTcpServer server;
    int clients = 0;
    QObject::connect(&server, &QTcpServer::newConnection, &app, [&] {
        while (auto* socket = server.nextPendingConnection()) {
            if (clients >= maxClients) { socket->abort(); socket->deleteLater(); continue; }
            ++clients;
            qInfo().noquote() << "qdock clientes activos:" << clients;
            new ClientConnection(socket, replay.absoluteFilePath(), token, source);
            QObject::connect(socket, &QTcpSocket::disconnected, &app, [&, socket] {
                --clients;
                qInfo().noquote() << "qdock clientes activos:" << clients;
                socket->deleteLater();
            });
        }
    });
    if (!server.listen(address, quint16(port))) return fail(server.errorString());
    std::signal(SIGINT, requestStop);
    std::signal(SIGTERM, requestStop);
    QTimer signalTimer;
    QObject::connect(&signalTimer, &QTimer::timeout, &app, [&app] {
        if (stopRequested) app.quit();
    });
    signalTimer.start(100);
#ifdef QDOCK_SERIAL
    if (source) serial.start(cli.value("serial"), seconds, cli.value("capture"));
#endif
    QTextStream(stdout) << QJsonDocument(QJsonObject{{"listening", address.toString()},
        {"port", server.serverPort()}, {"source", source ? "serial" : "replay"},
        {"build", QStringLiteral(QDOCK_BUILD_TIMESTAMP)}}).toJson(QJsonDocument::Compact) << Qt::endl;
    return app.exec();
}
