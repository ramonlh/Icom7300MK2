#include "quanshengclient.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QSettings>
#include <QTcpServer>
#include <QTemporaryDir>
#include <QThread>
#include <cstdlib>
#include <functional>

#define require(ok) do { if (!(ok)) qFatal("PTT client check failed at line %d: %s", __LINE__, #ok); } while (false)
static void waitFor(const std::function<bool()>& ready) {
    QElapsedTimer timer; timer.start();
    while (!ready() && timer.elapsed() < 2500) {
        QCoreApplication::processEvents();
        QThread::msleep(2);
    }
    require(ready());
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    QTemporaryDir settings;
    require(settings.isValid());
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settings.path());
    app.setOrganizationName("qdock-offline-test");
    app.setApplicationName("ptt-client");
    QTcpServer server;
    require(server.listen(QHostAddress::LocalHost, 0));
    QuanshengClient client;
    client.setHost("127.0.0.1");
    client.setPort(server.serverPort());
    client.setToken("offline-client-test-token");
    client.setAutoReconnect(false);
    client.connectToServer();
    waitFor([&] { return server.hasPendingConnections(); });
    auto* peer = server.nextPendingConnection();
    const auto read = [&] {
        waitFor([&] { return peer->canReadLine(); });
        return QJsonDocument::fromJson(peer->readLine()).object();
    };
    const auto send = [&](const QJsonObject& obj) {
        peer->write(QJsonDocument(obj).toJson(QJsonDocument::Compact) + '\n');
        peer->flush();
    };
    require(read()["message"] == "hello");
    client.pressPtt(); // Not available before authentication.
    require(!client.pttPressed());
    send({{"message", "welcome"}, {"txControlAvailable", true}, {"source", "serial"}});
    require(read()["message"] == "subscribe");
    send({{"message", "source_status"}, {"status", "listening"}});
    waitFor([&] { return client.sourceStatus() == "listening"; });
    client.pressPtt();
    require(client.pttPressed());
    const auto first = read();
    require(first["message"] == "ptt" && first["action"] == "press");
    const auto id = first["id"].toString();
    require(!id.isEmpty());
    client.pressPtt(); // Repeated UI event must not create a second press.
    const auto hold = read();
    require(hold["action"] == "keepalive" && hold["id"] == id);
    send({{"message", "ptt_state"}, {"active", true}, {"id", id}});
    client.releasePtt();
    require(!client.pttPressed());
    require(read()["action"] == "release");
    send({{"message", "ptt_state"}, {"active", false}, {"id", id}, {"reason", "released"}});
    waitFor([&] { return client.pttStatus() == "PTT liberado"; });
    client.pressPtt();
    const auto second = read();
    require(second["action"] == "press" && second["id"] != id);
    send({{"message", "ptt_status"}, {"id", second["id"]}, {"error", "radio_control_busy"}});
    waitFor([&] { return !client.pttPressed(); });
    require(client.pttStatus().contains("radio_control_busy"));
    client.pressPtt();
    const auto third = read();
    require(third["action"] == "press");
    send({{"message", "ptt_state"}, {"active", false}, {"id", third["id"]}, {"reason", "lease_expired"}});
    waitFor([&] { return !client.pttPressed(); });
    QElapsedTimer quiet; quiet.start();
    while (quiet.elapsed() < 400) { QCoreApplication::processEvents(); QThread::msleep(2); }
    require(peer->bytesAvailable() == 0); // No automatic re-key after timeout.
    client.pressPtt();
    require(read()["action"] == "press");
    peer->disconnectFromHost();
    waitFor([&] { return !client.connected(); });
    require(!client.pttPressed() && !client.txControlAvailable());
    client.pressPtt();
    require(!client.pttPressed());
    return EXIT_SUCCESS;
}
