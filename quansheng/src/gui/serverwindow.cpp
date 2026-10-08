// SPDX-License-Identifier: GPL-2.0-only
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QProcess>
#include <QProcessEnvironment>
#include <QPushButton>
#include <QRegularExpression>
#include <QSettings>
#include <QSerialPortInfo>
#include <QSpinBox>
#include <QStandardPaths>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

namespace {
constexpr int restartExitCode = 75;
constexpr qint64 diagnosticLogLimit = 5 * 1024 * 1024;

QString diagnosticLogPath()
{
    return QDir::home().filePath(QStringLiteral(".local/state/qdock/serial-diagnostics.log"));
}

void appendDiagnostic(const QByteArray &source, const QByteArray &data)
{
    if (data.isEmpty())
        return;

    const QString path = diagnosticLogPath();
    const QFileInfo info(path);
    QDir().mkpath(info.absolutePath());
    if (info.exists() && info.size() + data.size() + 64 > diagnosticLogLimit) {
        QFile::remove(path + QStringLiteral(".1"));
        QFile::rename(path, path + QStringLiteral(".1"));
    }

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append))
        return;
    file.write(QDateTime::currentDateTime().toString(Qt::ISODateWithMs).toUtf8());
    file.write(" [");
    file.write(source);
    file.write("] ");
    file.write(data);
    if (!data.endsWith('\n'))
        file.write("\n");
}

QString portLabel(const QSerialPortInfo &info)
{
    QString label = info.systemLocation();
    QStringList details;
    if (!info.description().isEmpty())
        details << info.description();
    if (!info.manufacturer().isEmpty())
        details << info.manufacturer();
    if (info.hasVendorIdentifier() && info.hasProductIdentifier())
        details << QStringLiteral("VID:PID %1:%2")
                       .arg(QString::number(info.vendorIdentifier(), 16).rightJustified(4, QLatin1Char('0')).toUpper(),
                            QString::number(info.productIdentifier(), 16).rightJustified(4, QLatin1Char('0')).toUpper());
    if (!details.isEmpty())
        label += QStringLiteral("  -  ") + details.join(QStringLiteral(" · "));
    return label;
}

QString selectedPortName(const QComboBox *port)
{
    const int index = port->currentIndex();
    if (index >= 0 && port->currentText() == port->itemText(index)) {
        const QString value = port->itemData(index).toString();
        if (!value.isEmpty())
            return value;
    }
    return port->currentText().trimmed();
}

QString tokenPath()
{
    return QDir::homePath() + QStringLiteral("/.config/qdock/lan-token");
}

QByteArray readToken(QString &error)
{
    const QByteArray environmentToken = qgetenv("QDOCK_LAN_TOKEN").trimmed();
    if (!environmentToken.isEmpty()) {
        if (environmentToken.size() < 16)
            error = QStringLiteral("QDOCK_LAN_TOKEN requiere al menos 16 caracteres.");
        return environmentToken;
    }
    QFile file(tokenPath());
    if (!file.open(QIODevice::ReadOnly)) {
        error = QStringLiteral("No se puede leer %1: %2").arg(tokenPath(), file.errorString());
        return {};
    }
    const QByteArray token = file.readAll().trimmed();
    if (token.size() < 16)
        error = QStringLiteral("El token LAN debe tener al menos 16 caracteres.");
    return token;
}

QString serverPath()
{
    return QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("qdock-server"));
}
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Servidor Quansheng UV-K5"));

    QWidget window;
    window.setWindowTitle(QStringLiteral("Servidor Quansheng UV-K5 · LAN"));
    window.resize(760, 520);

    auto *root = new QVBoxLayout(&window);
    auto *title = new QLabel(QStringLiteral("<b>Servidor Quansheng UV-K5 · LAN</b>"));
    auto *status = new QLabel(QStringLiteral("Detenido"));
    status->setStyleSheet(QStringLiteral("color:#d2b36f;font-weight:bold"));
    auto *heading = new QHBoxLayout;
    heading->addWidget(title);
    heading->addStretch();
    heading->addWidget(status);
    root->addLayout(heading);

    auto *form = new QFormLayout;
    auto *port = new QComboBox;
    port->setEditable(true);
    auto *refresh = new QPushButton(QStringLiteral("Actualizar puertos"));
    auto *portRow = new QHBoxLayout;
    portRow->addWidget(port, 1);
    portRow->addWidget(refresh);
    form->addRow(QStringLiteral("Puerto de la radio:"), portRow);

    auto *listenAddress = new QLineEdit(QStringLiteral("0.0.0.0"));
    auto *listenPort = new QSpinBox;
    listenPort->setRange(1, 65535);
    listenPort->setValue(8765);
    bool portOk = false;
    const int environmentPort = qEnvironmentVariableIntValue("QDOCK_LAN_PORT", &portOk);
    if (portOk && environmentPort >= 1 && environmentPort <= 65535)
        listenPort->setValue(environmentPort);
    auto *networkRow = new QHBoxLayout;
    networkRow->addWidget(listenAddress, 1);
    networkRow->addWidget(new QLabel(QStringLiteral("Puerto:")));
    networkRow->addWidget(listenPort);
    form->addRow(QStringLiteral("Escucha LAN:"), networkRow);
    root->addLayout(form);

    auto *options = new QHBoxLayout;
    auto *rssi = new QCheckBox(QStringLiteral("RSSI 1 s"));
    auto *registers = new QCheckBox(QStringLiteral("Registros"));
    auto *eeprom = new QCheckBox(QStringLiteral("Lectura EEPROM"));
    auto *frequency = new QCheckBox(QStringLiteral("Frecuencia/VFO"));
    for (auto *box : {rssi, registers, eeprom, frequency}) {
        box->setChecked(true);
        options->addWidget(box);
    }
    auto *ptt = new QCheckBox(QStringLiteral("Permitir PTT"));
    ptt->setChecked(true);
    ptt->setToolTip(QStringLiteral("PTT momentáneo desde LAN; permite emitir RF. Máximo 60 s."));
    options->addWidget(ptt);
    auto *autoStart = new QCheckBox(QStringLiteral("Iniciar al abrir"));
    QSettings settings;
    autoStart->setChecked(settings.value(QStringLiteral("serverGui/autoStart"), false).toBool());
    if (qEnvironmentVariableIntValue("QDOCK_GUI_AUTOSTART") > 0)
        autoStart->setChecked(true);
    autoStart->setToolTip(QStringLiteral("Arranca el servidor automáticamente al abrir esta ventana."));
    options->addWidget(autoStart);
    options->addStretch();
    root->addLayout(options);

    auto *buttons = new QHBoxLayout;
    auto *start = new QPushButton(QStringLiteral("Iniciar servidor"));
    auto *stop = new QPushButton(QStringLiteral("Detener"));
    auto *clear = new QPushButton(QStringLiteral("Limpiar registro"));
    auto *eventCounter = new QLabel(QStringLiteral("Eventos: 0 · Bytes: 0 · Descartados: 0 · Pendientes: 0"));
    eventCounter->setStyleSheet(QStringLiteral("color:#000000;font-weight:normal"));
    stop->setEnabled(false);
    buttons->addWidget(start);
    buttons->addWidget(stop);
    buttons->addWidget(clear);
    buttons->addStretch();
    buttons->addWidget(eventCounter);
    root->addLayout(buttons);

    auto *log = new QPlainTextEdit;
    log->setReadOnly(true);
    log->setMaximumBlockCount(5000);
    log->setPlaceholderText(QStringLiteral("Aquí aparecerá el registro del servidor…"));
    root->addWidget(log, 1);

    auto *safety = new QLabel(QStringLiteral(
        "PTT LAN habilitado para pruebas controladas. Escritura EEPROM/registros/GPIO bloqueada."));
    safety->setStyleSheet(QStringLiteral("color:#8fdb9b"));
    root->addWidget(safety);

    auto *diagnosticPath = new QLabel(QStringLiteral("Registro persistente: %1").arg(diagnosticLogPath()));
    diagnosticPath->setTextInteractionFlags(Qt::TextSelectableByMouse);
    diagnosticPath->setStyleSheet(QStringLiteral("color:#aab3bc"));
    root->addWidget(diagnosticPath);

    QProcess server(&window);
    server.setProcessChannelMode(QProcess::MergedChannels);
    QProcess kernelLog(&window);
    kernelLog.setProcessChannelMode(QProcess::SeparateChannels);
    QString serverOutputBuffer;
    bool restartRequested = false;

    const auto refreshPorts = [port, log] {
        const QString previous = selectedPortName(port);
        port->clear();
        for (const QSerialPortInfo &info : QSerialPortInfo::availablePorts())
            port->addItem(portLabel(info), info.systemLocation());
        auto findPort = [port](const QString &name) {
            for (int i = 0; i < port->count(); ++i) {
                if (port->itemData(i).toString() == name)
                    return i;
            }
            return -1;
        };
        int preferred = findPort(QStringLiteral("/dev/ttyACM0"));
        if (preferred < 0) preferred = findPort(QStringLiteral("/dev/ttyUSB0"));
        const QString environmentPort = QString::fromLocal8Bit(qgetenv("QDOCK_SERIAL_DEVICE")).trimmed();
        const int environmentIndex = findPort(environmentPort);
        if (environmentIndex >= 0)
            preferred = environmentIndex;
        const int old = findPort(previous);
        if (old >= 0) preferred = old;
        if (preferred >= 0) port->setCurrentIndex(preferred);
        if (port->count() == 0) {
            port->setEditText(QStringLiteral("/dev/ttyACM0"));
            log->appendPlainText(QStringLiteral("No se detectan puertos serie; revise el cable USB."));
        }
    };
    QObject::connect(refresh, &QPushButton::clicked, &window, refreshPorts);
    QObject::connect(autoStart, &QCheckBox::toggled, &window, [](bool checked) {
        QSettings settings;
        settings.setValue(QStringLiteral("serverGui/autoStart"), checked);
    });
    QObject::connect(clear, &QPushButton::clicked, log, &QPlainTextEdit::clear);
    QObject::connect(&server, &QProcess::readyRead, &window, [&server, log, eventCounter, &serverOutputBuffer] {
        const QByteArray received = server.readAll();
        appendDiagnostic("server", received);
        static const QRegularExpression statsPattern(
            QStringLiteral("qdock stats bytes=\\s*(\\d+)\\s+events=\\s*(\\d+)\\s+discarded=\\s*(\\d+)\\s+pending=\\s*(\\d+)"));
        serverOutputBuffer += QString::fromLocal8Bit(received);
        QString visibleText;
        while (true) {
            const qsizetype newline = serverOutputBuffer.indexOf(QLatin1Char('\n'));
            if (newline < 0)
                break;
            const QString line = serverOutputBuffer.left(newline + 1);
            serverOutputBuffer.remove(0, newline + 1);
            const QRegularExpressionMatch match = statsPattern.match(line);
            if (match.hasMatch()) {
                eventCounter->setText(QStringLiteral("Eventos: %1 · Bytes: %2 · Descartados: %3 · Pendientes: %4")
                                      .arg(match.captured(2), match.captured(1),
                                           match.captured(3), match.captured(4)));
                continue;
            }
            visibleText += line;
        }
        if (!visibleText.isEmpty()) {
            log->moveCursor(QTextCursor::End);
            log->insertPlainText(visibleText);
            log->moveCursor(QTextCursor::End);
        }
        const QRegularExpressionMatch pendingStats = statsPattern.match(serverOutputBuffer);
        if (pendingStats.hasMatch()) {
            eventCounter->setText(QStringLiteral("Eventos: %1 · Bytes: %2 · Descartados: %3 · Pendientes: %4")
                                  .arg(pendingStats.captured(2), pendingStats.captured(1),
                                       pendingStats.captured(3), pendingStats.captured(4)));
        }
    });
    QObject::connect(&kernelLog, &QProcess::readyReadStandardOutput, &window, [&kernelLog] {
        appendDiagnostic("kernel", kernelLog.readAllStandardOutput());
    });
    QObject::connect(&kernelLog, &QProcess::readyReadStandardError, &window, [&kernelLog] {
        appendDiagnostic("kernel-monitor", kernelLog.readAllStandardError());
    });
    QObject::connect(&kernelLog, &QProcess::errorOccurred, &window, [&kernelLog](QProcess::ProcessError error) {
        appendDiagnostic("kernel-monitor",
                         QStringLiteral("journalctl -k -f error=%1: %2\n")
                             .arg(int(error)).arg(kernelLog.errorString()).toUtf8());
    });
    QObject::connect(&server, &QProcess::errorOccurred, &window,
                     [status, log](QProcess::ProcessError) {
        status->setText(QStringLiteral("Error"));
        status->setStyleSheet(QStringLiteral("color:#ff6b6b;font-weight:bold"));
        log->appendPlainText(QStringLiteral("No se pudo iniciar o mantener el proceso servidor."));
    });
    QObject::connect(&server, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                     &window, [=, &restartRequested](int code, QProcess::ExitStatus) {
        const bool shouldRestart = code == restartExitCode;
        status->setText(QStringLiteral("Detenido (código %1)").arg(code));
        status->setStyleSheet(QStringLiteral("color:#d2b36f;font-weight:bold"));
        eventCounter->setText(QStringLiteral("Eventos: 0 · Bytes: 0 · Descartados: 0 · Pendientes: 0"));
        start->setEnabled(true); stop->setEnabled(false);
        port->setEnabled(true); refresh->setEnabled(true); ptt->setEnabled(true); autoStart->setEnabled(true);
        if (shouldRestart) {
            restartRequested = true;
            log->appendPlainText(QStringLiteral("Reinicio solicitado desde cliente LAN; relanzando servidor…"));
            QTimer::singleShot(700, start, &QPushButton::click);
        }
    });
    QObject::connect(stop, &QPushButton::clicked, &server, [&server] {
        server.terminate();
        if (!server.waitForFinished(2000)) server.kill();
    });
    QObject::connect(start, &QPushButton::clicked, &window,
                     [&, start, stop, port, refresh, listenAddress, listenPort,
                      rssi, registers, eeprom, frequency, ptt, log, status] {
        if (server.state() != QProcess::NotRunning) return;
        QString error;
        const QByteArray token = readToken(error);
        if (!error.isEmpty()) {
            QMessageBox::critical(&window, QStringLiteral("Token LAN"), error);
            return;
        }
        const QString executable = serverPath();
        if (!QFileInfo::exists(executable)) {
            QMessageBox::critical(&window, QStringLiteral("Servidor no encontrado"), executable);
            return;
        }
        const QString selectedPort = selectedPortName(port);
        QStringList arguments{QStringLiteral("--serial"), selectedPort,
                              QStringLiteral("--seconds"), QStringLiteral("86400"),
                              QStringLiteral("--listen"), listenAddress->text().trimmed(),
                              QStringLiteral("--port"), QString::number(listenPort->value())};
        if (rssi->isChecked()) arguments << QStringLiteral("--allow-rssi-query");
        if (registers->isChecked()) arguments << QStringLiteral("--allow-register-query");
        if (eeprom->isChecked()) arguments << QStringLiteral("--allow-eeprom-query");
        if (frequency->isChecked()) arguments << QStringLiteral("--allow-frequency-control");
        if (ptt->isChecked()) arguments << QStringLiteral("--allow-ptt");
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("QDOCK_LAN_TOKEN"), QString::fromUtf8(token));
        server.setProcessEnvironment(environment);
        eventCounter->setText(QStringLiteral("Eventos: 0 · Bytes: 0 · Descartados: 0 · Pendientes: 0"));
        serverOutputBuffer.clear();
        log->appendPlainText(QStringLiteral("%1 %2 en %3…")
                             .arg(restartRequested ? QStringLiteral("Reiniciando")
                                                    : QStringLiteral("Iniciando"),
                                  QFileInfo(executable).fileName(), selectedPort));
        restartRequested = false;
        server.start(executable, arguments);
        if (!server.waitForStarted(3000)) return;
        status->setText(QStringLiteral("En ejecución"));
        status->setStyleSheet(QStringLiteral("color:#8fdb9b;font-weight:bold"));
        start->setEnabled(false); stop->setEnabled(true);
        port->setEnabled(false); refresh->setEnabled(false); ptt->setEnabled(false); autoStart->setEnabled(false);
    });

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &window, [&server] {
        if (server.state() == QProcess::NotRunning) return;
        server.terminate();
        if (!server.waitForFinished(1500)) server.kill();
    });

    refreshPorts();
    appendDiagnostic("monitor", "Inicio de monitor serie/USB.\n");
    kernelLog.start(QStringLiteral("journalctl"),
                    {QStringLiteral("-k"), QStringLiteral("-f"), QStringLiteral("-o"),
                     QStringLiteral("short-iso-precise")});
    for (QLabel *label : window.findChildren<QLabel *>())
        label->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
    window.show();
    if (autoStart->isChecked())
        QTimer::singleShot(0, start, &QPushButton::click);
    return app.exec();
}
