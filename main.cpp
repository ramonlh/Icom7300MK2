#include <QCoreApplication>
#include <QGuiApplication>
#include <QIcon>
#include <QLockFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>
#include <QDir>
#include <QStandardPaths>
#include <QTimer>

#include "radiocontroller.h"
#include "morsetrainer.h"
#include "remoteserver.h"
#include "applicationlauncher.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

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

    // La vista compacta sustituye temporalmente a la ventana principal.
    // No se debe terminar el proceso durante ese intercambio; el cierre
    // explícito desde QML sigue llamando a Qt.quit().
    app.setQuitOnLastWindowClosed(false);

    QGuiApplication::setOrganizationName(QStringLiteral("RamonLorenzo"));
    QGuiApplication::setApplicationName(
        QStringLiteral("Icom7300Mk2Control")
    );
    QGuiApplication::setApplicationVersion(
        QStringLiteral("1.2.12")
    );
    QGuiApplication::setApplicationDisplayName(
        QStringLiteral("IC-7300MK2 Control")
    );

    // Linux/Wayland y varios escritorios modernos relacionan la ventana
    // con su lanzador mediante el nombre base del archivo .desktop.
    QGuiApplication::setDesktopFileName(
        QStringLiteral(
            "es.ramonlorenzo.Icom7300Mk2Control"
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

    RadioController radioController;
    MorseTrainer morseTrainer;
    RemoteServer remoteServer(&radioController);
    ApplicationLauncher applicationLauncher;
    QObject::connect(&applicationLauncher, &ApplicationLauncher::lanFrequencyReceived,
                     &radioController, [&radioController](qulonglong hz) {
        radioController.setExternalFrequency(hz);
    });
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
        &remoteServer,
        &RemoteServer::shutdown,
        Qt::DirectConnection
    );

    QQmlApplicationEngine engine;
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

    const QUrl mainQmlUrl(QStringLiteral("qrc:/Main.qml"));

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [mainQmlUrl](QObject *object, const QUrl &objectUrl) {
            if (!object && objectUrl == mainQmlUrl) {
                QCoreApplication::exit(-1);
            }
        },
        Qt::QueuedConnection
    );

    engine.load(mainQmlUrl);

    return app.exec();
}
