// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/rssiquery.h"
#include <QCoreApplication>
#include <QSerialPort>
#include <QTextStream>
#include <QTimer>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) {
        QTextStream(stderr) << "Uso: qdock-rssi-query /dev/ttyUSB0\n";
        return 2;
    }
    QSerialPort port;
    port.setPortName(QString::fromLocal8Bit(argv[1]));
    port.setBaudRate(38400); port.setDataBits(QSerialPort::Data8);
    port.setParity(QSerialPort::NoParity); port.setStopBits(QSerialPort::OneStop);
    port.setFlowControl(QSerialPort::NoFlowControl);
    if (!port.open(QIODevice::ReadWrite)) {
        QTextStream(stderr) << "No se puede abrir el puerto: " << port.errorString() << '\n';
        return 1;
    }
    const auto frame = qdock::experimental::makeGetRssiFrame();
    const QByteArray bytes(reinterpret_cast<const char*>(frame.data()), frame.size());
    QTextStream(stderr) << "EXPERIMENTAL: una única consulta GetRssi 0x0527; sin otros comandos.\n"
                        << "TX: " << bytes.toHex(' ') << '\n';
    if (port.write(bytes) != bytes.size() || !port.waitForBytesWritten(1000)) {
        QTextStream(stderr) << "No se pudo enviar la consulta.\n"; return 1;
    }
    qdock::Parser parser;
    QObject::connect(&port, &QSerialPort::readyRead, [&] {
        const auto incoming = port.readAll();
        for (const auto& event : parser.feed(reinterpret_cast<const std::uint8_t*>(incoming.constData()), incoming.size())) {
            qdock::experimental::RssiReading reading;
            if (qdock::experimental::decodeRssiInfo(event, reading)) {
                QTextStream(stdout) << "{\"rssi_raw\":" << reading.raw
                    << ",\"dbm_uncorrected\":" << qdock::experimental::rssiDbmUncorrected(reading.raw)
                    << ",\"noise\":" << reading.noise
                    << ",\"glitch\":" << reading.glitch << "}\n";
                app.exit(0); return;
            }
        }
    });
    QTimer::singleShot(3000, [&] { QTextStream(stderr) << "Timeout esperando RssiInfo 0x0528.\n"; app.exit(3); });
    return app.exec();
}
