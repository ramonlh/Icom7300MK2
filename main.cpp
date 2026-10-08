#include <QCoreApplication>
#include <QGuiApplication>
#include <QIcon>
#include <QLockFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <qqml.h>
#include <QUrl>
#include <QDir>
#include <QDebug>
#include <QStandardPaths>
#include <QTimer>
#include <cstdio>

#include "radiocontroller.h"
#include "morsetrainer.h"
#include "remoteserver.h"
#include "applicationlauncher.h"
#include "quanshengclient.h"
#include "videocapturecontroller.h"
#include "qrzlogbookcontroller.h"
#include "build_timestamp.h"

int main(int argc, char *argv[])
{
    std::fprintf(stderr, "Inicio: entrando en main()\n");
    std::fflush(stderr);
    QGuiApplication app(argc, argv);
    std::fprintf(stderr, "Inicio: QGuiApplication creada\n");
    std::fflush(stderr);

    QString runtimeDirectory = QStandardPaths::writableLocation(
        QStandardPaths::RuntimeLocation);
    if (runtimeDirectory.isEmpty())
        runtimeDirectory = QDir::tempPath();
    const bool lanDiagnostic = app.arguments().contains(
        QStringLiteral("--lan-diagnostic"));
    QLockFile instanceLock(
        QDir(runtimeDirectory).filePath(
            lanDiagnostic
                ? QStringLiteral("Icom7300Mk2Control-lan-diagnostic.lock")
                : QStringLiteral("Icom7300Mk2Control.lock")));
    // Recover automatically if a diagnostic run or a crash leaves the lock
    // file behind.  A zero stale time disables age-based recovery entirely.
    instanceLock.setStaleLockTime(1000);
    if (!instanceLock.tryLock(100)) {
        // QLockFile can leave a dead PID behind after SIGTERM (for example
        // when a timed diagnostic ends).  removeStaleLockFile validates the
        // recorded process before deleting, so a live instance stays safe.
        if (!instanceLock.removeStaleLockFile()
            || !instanceLock.tryLock(100))
            return 0;
    }
    std::fprintf(stderr, "Inicio: bloqueo de instancia adquirido\n");
    std::fflush(stderr);

    // La vista compacta sustituye temporalmente a la ventana principal.
    // No se debe terminar el proceso durante ese intercambio; el cierre
    // explícito desde QML sigue llamando a Qt.quit().
    app.setQuitOnLastWindowClosed(false);

    QGuiApplication::setOrganizationName(QStringLiteral("Icom7300Mk2"));
    QGuiApplication::setApplicationName(
        QStringLiteral("Icom7300Mk2Control")
    );
    QGuiApplication::setApplicationVersion(
        QStringLiteral("1.2.13")
    );
    QGuiApplication::setApplicationDisplayName(
        QStringLiteral("IC-7300MK2 / Quansheng UV-K5 Control")
    );

    // Linux/Wayland y varios escritorios modernos relacionan la ventana
    // con su lanzador mediante el nombre base del archivo .desktop.
    QGuiApplication::setDesktopFileName(
        QStringLiteral(
            "org.icom.Icom7300Mk2Control"
        )
    );

    QIcon applicationIcon;
    applicationIcon.addFile(
        QStringLiteral(
            ":/icons/icom7300mk2_control_32.png"
        )
    );
    applicationIcon.addFile(
        QStringLiteral(
            ":/icons/icom7300mk2_control_48.png"
        )
    );
    applicationIcon.addFile(
        QStringLiteral(
            ":/icons/icom7300mk2_control_64.png"
        )
    );
    applicationIcon.addFile(
        QStringLiteral(
            ":/icons/icom7300mk2_control_128.png"
        )
    );
    applicationIcon.addFile(
        QStringLiteral(
            ":/icons/icom7300mk2_control_256.png"
        )
    );
    applicationIcon.addFile(
        QStringLiteral(
            ":/icons/icom7300mk2_control_512.png"
        )
    );
    QGuiApplication::setWindowIcon(applicationIcon);

    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    std::fprintf(stderr, "Inicio: creando controladores\n");
    std::fflush(stderr);
    RadioController radioController;
    std::fprintf(stderr, "Inicio: RadioController creado\n");
    std::fflush(stderr);
    MorseTrainer morseTrainer;
    ApplicationLauncher applicationLauncher;
    std::fprintf(stderr, "Inicio: ApplicationLauncher creado\n");
    std::fflush(stderr);
    QuanshengClient quanshengClient;
    VideoCaptureController videoCapture;
    QrzLogbookController qrzLogbook;
    RemoteServer remoteServer(&radioController, &quanshengClient);
    std::fprintf(stderr, "Inicio: controladores creados\n");
    std::fflush(stderr);
    QObject::connect(&applicationLauncher, &ApplicationLauncher::lanFrequencyReceived,
                     &radioController, [&radioController](qulonglong hz) {
        radioController.setExternalFrequency(hz);
    });
    QObject::connect(&applicationLauncher, &ApplicationLauncher::lanReceiverFrameReceived,
                     &radioController, &RadioController::receiveLanReceiverFrame);
    QObject::connect(&applicationLauncher, &ApplicationLauncher::lanConnectionChanged,
                     &radioController, [&applicationLauncher, &radioController]() {
        if (applicationLauncher.lanConnected()) {
            radioController.setLanReceiverWriter(
                [&applicationLauncher](const QByteArray &payload, const QString &label) {
                    return applicationLauncher.sendLanReceiverCommand(payload, label);
                });
            // Start the memory cache once the LAN CI-V writer is available.
            // The QML connection signal can otherwise race the handshake.
            QTimer::singleShot(800, &radioController, [&radioController]() {
                radioController.readMemoryRange(1, 99);
            });
            QTimer::singleShot(2500, &radioController, [&radioController]() {
                if (!radioController.memoryReadActive())
                    radioController.readMemoryRange(1, 99);
            });
            QTimer::singleShot(5000, &radioController, [&radioController]() {
                if (!radioController.memoryReadActive())
                    radioController.readMemoryRange(1, 99);
            });
        } else {
            radioController.setLanReceiverWriter({});
        }
    });
    QTimer lanReceiverPoll;
    lanReceiverPoll.setInterval(500);
    QObject::connect(&lanReceiverPoll, &QTimer::timeout,
                     &applicationLauncher, &ApplicationLauncher::pollLanReceiverState);
    lanReceiverPoll.start();
    QTimer lanSmeterPoll;
    // The S-Meter has its own fast queue. It is sent without per-packet
    // retries because the next reading arrives shortly afterwards.
    lanSmeterPoll.setInterval(250);
    QObject::connect(&lanSmeterPoll, &QTimer::timeout,
                     &applicationLauncher, &ApplicationLauncher::pollLanSmeter);
    lanSmeterPoll.start();
    if (applicationLauncher.lanConnectionEnabled() && radioController.autoConnectEnabled()) {
        QTimer::singleShot(500, &applicationLauncher, [&applicationLauncher]() {
            applicationLauncher.testLanConnection();
        });
        // DHCP/radio startup can make the first discovery packet arrive too
        // early. Retry a few seconds later if LAN is still disconnected.
        QTimer::singleShot(8000, &applicationLauncher, [&applicationLauncher]() {
            if (!applicationLauncher.lanConnected())
                applicationLauncher.testLanConnection();
        });
        QTimer::singleShot(16000, &applicationLauncher, [&applicationLauncher]() {
            if (!applicationLauncher.lanConnected())
                applicationLauncher.testLanConnection();
        });
    }

    // Reproducible LAN soak test.  It is opt-in so normal launches are not
    // affected: --lan-diagnostic runs mode/DATA probes and exits after five
    // minutes while the timestamped protocol trace is captured on stderr.
    if (lanDiagnostic) {
        QTimer::singleShot(30000, &applicationLauncher, [&applicationLauncher]() {
            applicationLauncher.testLanModeName(QStringLiteral("LSB"));
        });
        QTimer::singleShot(45000, &applicationLauncher, [&applicationLauncher]() {
            applicationLauncher.testLanModeName(QStringLiteral("USB"));
        });
        QTimer::singleShot(60000, &applicationLauncher, [&applicationLauncher]() {
            applicationLauncher.setLanDataEnabled(true, QStringLiteral("USB"));
        });
        QTimer::singleShot(75000, &applicationLauncher, [&applicationLauncher]() {
            applicationLauncher.setLanDataEnabled(false, QStringLiteral("USB"));
        });
        QTimer::singleShot(300000, &app, &QCoreApplication::quit);
    }

    // El puerto CI-V debe cerrarse antes de que desaparezca el bucle de
    // eventos. Así se libera inmediatamente el bloqueo exclusivo de Linux,
    // incluso si alguna ventana QML auxiliar quedó creada pero oculta.
    QObject::connect(
        &app,
        &QCoreApplication::aboutToQuit,
        &applicationLauncher,
        &ApplicationLauncher::shutdownLanConnection,
        Qt::DirectConnection
    );
    QObject::connect(
        &app,
        &QCoreApplication::aboutToQuit,
        &quanshengClient,
        &QuanshengClient::shutdown,
        Qt::DirectConnection
    );
    QObject::connect(
        &app,
        &QCoreApplication::aboutToQuit,
        &radioController,
        &RadioController::shutdown,
        Qt::DirectConnection
    );
    QObject::connect(
        &app,
        &QCoreApplication::aboutToQuit,
        &morseTrainer,
        [&morseTrainer]() {
            morseTrainer.stopReceptionPlayback();
            morseTrainer.stopCapture();
        },
        Qt::DirectConnection
    );
    QObject::connect(
        &app,
        &QCoreApplication::aboutToQuit,
        &videoCapture,
        &VideoCaptureController::stopCapture,
        Qt::DirectConnection
    );
    QObject::connect(
        &app,
        &QCoreApplication::aboutToQuit,
        &remoteServer,
        &RemoteServer::shutdown,
        Qt::DirectConnection
    );

    QQmlApplicationEngine engine;
    qmlRegisterType<VideoFrameItem>("Icom.Video", 1, 0, "VideoFrameItem");
    engine.rootContext()->setContextProperty(
        QStringLiteral("buildTimestamp"),
        QStringLiteral(APP_BUILD_TIMESTAMP)
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("radioController"),
        &radioController
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("morseTrainer"),
        &morseTrainer
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("remoteServer"),
        &remoteServer
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("applicationLauncher"),
        &applicationLauncher
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("quanshengClient"),
        &quanshengClient
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("videoCapture"),
        &videoCapture
    );
    engine.rootContext()->setContextProperty(
        QStringLiteral("qrzLogbook"),
        &qrzLogbook
    );

    const QUrl mainQmlUrl(QStringLiteral("qrc:/Main.qml"));

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [mainQmlUrl](QObject *object, const QUrl &objectUrl) {
            if (!object && objectUrl == mainQmlUrl) {
                qCritical().noquote()
                    << "QML: no se pudo crear la ventana principal:" << objectUrl;
                QCoreApplication::exit(-1);
                return;
            }
            auto *window = qobject_cast<QQuickWindow *>(object);
            if (!window)
                return;
            const auto reportWindow = [window](const char *stage) {
                qInfo().noquote()
                    << "Inicio QML:" << stage
                    << "visible=" << window->isVisible()
                    << "visibility=" << window->visibility()
                    << "geometry=" << window->geometry();
            };
            reportWindow("raiz creada");
            QObject::connect(window, &QWindow::visibleChanged, window,
                [reportWindow](bool) { reportWindow("cambio de visibilidad"); });
            QTimer::singleShot(1500, window,
                [reportWindow]() { reportWindow("1,5 s"); });
        },
        Qt::QueuedConnection
    );

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
        [](const QList<QQmlError> &warnings) {
            for (const QQmlError &warning : warnings)
                qWarning().noquote() << "QML:" << warning.toString();
        });

    std::fprintf(stderr, "Inicio: cargando Main.qml\n");
    std::fflush(stderr);
    engine.load(mainQmlUrl);
    std::fprintf(stderr, "Inicio: engine.load() terminado, raíces=%zu\n",
                 static_cast<size_t>(engine.rootObjects().size()));
    std::fflush(stderr);

    if (quanshengClient.autoConnectOnStartup()
        || (quanshengClient.serverLocation() == QStringLiteral("local")
            && quanshengClient.autoStartLocalServer())) {
        QTimer::singleShot(0, &quanshengClient, [&quanshengClient]() {
            if (quanshengClient.serverLocation() == QStringLiteral("local")
                && quanshengClient.autoStartLocalServer())
                quanshengClient.startServerGuiBySsh();
            else
                quanshengClient.connectToServer();
        });
    }

    std::fprintf(stderr, "Inicio: entrando en app.exec()\n");
    std::fflush(stderr);
    return app.exec();
}
