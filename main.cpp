#include <QCoreApplication>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "radiocontroller.h"
#include "morsetrainer.h"
#include "remoteserver.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QGuiApplication::setOrganizationName(QStringLiteral("RamonLorenzo"));
    QGuiApplication::setApplicationName(
        QStringLiteral("Icom7300Mk2Control")
    );
    QGuiApplication::setApplicationVersion(
        QStringLiteral("1.2.11")
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

    // El puerto CI-V debe cerrarse antes de que desaparezca el bucle de
    // eventos. Así se libera inmediatamente el bloqueo exclusivo de Linux,
    // incluso si alguna ventana QML auxiliar quedó creada pero oculta.
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
