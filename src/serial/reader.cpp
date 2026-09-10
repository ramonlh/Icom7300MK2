// SPDX-License-Identifier: GPL-2.0-only
#include "serial/reader.h"
#include <QCoreApplication>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QTextStream>
#include <QTimer>
#include <termios.h>

namespace qdock {
void listPorts() {
    QTextStream out(stdout);
    for (const auto& info : QSerialPortInfo::availablePorts())
        out << info.systemLocation() << '\t' << info.description() << '\n';
}
int readSerial(const QString& name, int seconds,
               const std::function<bool(const QByteArray&)>& receive) {
    QSerialPort port;
    port.setPortName(name);
    if (!port.setBaudRate(38400) || !port.setDataBits(QSerialPort::Data8) ||
        !port.setParity(QSerialPort::NoParity) || !port.setStopBits(QSerialPort::OneStop) ||
        !port.setFlowControl(QSerialPort::NoFlowControl) || !port.open(QIODevice::ReadOnly)) {
        QTextStream(stderr) << "No se puede abrir/configurar el puerto: " << port.errorString() << '\n';
        return 1;
    }
    port.setReadBufferSize(65536);
    termios settings{};
    if (tcgetattr(port.handle(), &settings) != 0 ||
        cfgetispeed(&settings) != B38400 || cfgetospeed(&settings) != B38400 ||
        (settings.c_cflag & CSIZE) != CS8 ||
        (settings.c_cflag & (PARENB | CSTOPB | CRTSCTS)) != 0 ||
        (settings.c_iflag & (IXON | IXOFF | ISTRIP | INLCR | IGNCR | ICRNL)) != 0 ||
        (settings.c_lflag & (ICANON | ECHO | ISIG)) != 0) {
        QTextStream(stderr) << "La configuración efectiva del puerto no es 38400 8N1 raw sin control de flujo.\n";
        return 1;
    }
    QObject::connect(&port, &QSerialPort::readyRead, &port, [&] {
        if (!receive(port.readAll())) QCoreApplication::exit(1);
    });
    QObject::connect(&port, &QSerialPort::errorOccurred, &port, [&](auto error) {
        if (error != QSerialPort::NoError) {
            QTextStream(stderr) << "Error serie: " << port.errorString() << '\n';
            QCoreApplication::exit(1);
        }
    });
    QTimer::singleShot(seconds * 1000, QCoreApplication::instance(), &QCoreApplication::quit);
    QTextStream(stderr) << "Escucha READ-ONLY 38400 8N1 durante " << seconds << " s; sin handshake.\n";
    return QCoreApplication::exec();
}
}
