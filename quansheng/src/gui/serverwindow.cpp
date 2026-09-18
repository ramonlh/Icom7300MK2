// SPDX-License-Identifier: GPL-2.0-only
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCoreApplication>
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
#include <QSerialPortInfo>
#include <QSpinBox>
#include <QStandardPaths>
#include <QVBoxLayout>
#include <QWidget>

namespace {
QString tokenPath()
{
    return QDir::homePath() + QStringLiteral("/.config/qdock/lan-token");
}

QByteArray readToken(QString &error)
{
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
    ptt->setToolTip(QStringLiteral("PTT momentáneo desde LAN; permite emitir RF. Máximo 60 s."));
    options->addWidget(ptt);
    options->addStretch();
    root->addLayout(options);

    auto *buttons = new QHBoxLayout;
    auto *start = new QPushButton(QStringLiteral("Iniciar servidor"));
    auto *stop = new QPushButton(QStringLiteral("Detener"));
    auto *clear = new QPushButton(QStringLiteral("Limpiar registro"));
    stop->setEnabled(false);
    buttons->addWidget(start);
    buttons->addWidget(stop);
    buttons->addWidget(clear);
    buttons->addStretch();
    root->addLayout(buttons);

    auto *log = new QPlainTextEdit;
    log->setReadOnly(true);
    log->setMaximumBlockCount(5000);
    log->setPlaceholderText(QStringLiteral("Aquí aparecerá el registro del servidor…"));
    root->addWidget(log, 1);

    auto *safety = new QLabel(QStringLiteral(
        "PTT requiere marcar Permitir PTT antes de iniciar. Escritura EEPROM/registros/GPIO bloqueada."));
    safety->setStyleSheet(QStringLiteral("color:#8fdb9b"));
    root->addWidget(safety);

    QProcess server(&window);
    server.setProcessChannelMode(QProcess::MergedChannels);

    const auto refreshPorts = [port, log] {
        const QString previous = port->currentText();
        port->clear();
        for (const QSerialPortInfo &info : QSerialPortInfo::availablePorts())
            port->addItem(info.systemLocation(), info.description());
        int preferred = port->findText(QStringLiteral("/dev/ttyACM0"));
        if (preferred < 0) preferred = port->findText(QStringLiteral("/dev/ttyUSB0"));
        const int old = port->findText(previous);
        if (old >= 0) preferred = old;
        if (preferred >= 0) port->setCurrentIndex(preferred);
        if (port->count() == 0) {
            port->setEditText(QStringLiteral("/dev/ttyACM0"));
            log->appendPlainText(QStringLiteral("No se detectan puertos serie; revise el cable USB."));
        }
    };
    QObject::connect(refresh, &QPushButton::clicked, &window, refreshPorts);
    QObject::connect(clear, &QPushButton::clicked, log, &QPlainTextEdit::clear);
    QObject::connect(&server, &QProcess::readyRead, &window, [&server, log] {
        log->moveCursor(QTextCursor::End);
        log->insertPlainText(QString::fromLocal8Bit(server.readAll()));
        log->moveCursor(QTextCursor::End);
    });
    QObject::connect(&server, &QProcess::errorOccurred, &window,
                     [status, log](QProcess::ProcessError) {
        status->setText(QStringLiteral("Error"));
        status->setStyleSheet(QStringLiteral("color:#ff6b6b;font-weight:bold"));
        log->appendPlainText(QStringLiteral("No se pudo iniciar o mantener el proceso servidor."));
    });
    QObject::connect(&server, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
                     &window, [=](int code, QProcess::ExitStatus) {
        status->setText(QStringLiteral("Detenido (código %1)").arg(code));
        status->setStyleSheet(QStringLiteral("color:#d2b36f;font-weight:bold"));
        start->setEnabled(true); stop->setEnabled(false);
        port->setEnabled(true); refresh->setEnabled(true); ptt->setEnabled(true);
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
        QStringList arguments{QStringLiteral("--serial"), port->currentText().trimmed(),
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
        log->appendPlainText(QStringLiteral("Iniciando %1 en %2…")
                             .arg(QFileInfo(executable).fileName(), port->currentText()));
        server.start(executable, arguments);
        if (!server.waitForStarted(3000)) return;
        status->setText(QStringLiteral("En ejecución"));
        status->setStyleSheet(QStringLiteral("color:#8fdb9b;font-weight:bold"));
        start->setEnabled(false); stop->setEnabled(true);
        port->setEnabled(false); refresh->setEnabled(false); ptt->setEnabled(false);
    });

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &window, [&server] {
        if (server.state() == QProcess::NotRunning) return;
        server.terminate();
        if (!server.waitForFinished(1500)) server.kill();
    });

    refreshPorts();
    window.show();
    return app.exec();
}
