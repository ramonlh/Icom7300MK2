// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/registerquery.h"
#include <QCoreApplication>
#include <QSerialPort>
#include <QTextStream>
#include <QTimer>
#include <array>
#include <set>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) {
        QTextStream(stderr) << "Uso: qdock-register-query /dev/ttyUSB0\n";
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

    const std::array<std::pair<int, int>, 3> batches{{{0x00, 0x31}, {0x32, 0x63}, {0x64, 0x7f}}};
    int batchIndex = 0;
    std::set<std::uint16_t> received;
    qdock::Parser parser;
    QTimer timeout;
    timeout.setSingleShot(true);

    auto sendBatch = [&] {
        const auto [first, last] = batches[batchIndex];
        std::vector<std::uint16_t> addresses;
        for (int address = first; address <= last; ++address)
            addresses.push_back(static_cast<std::uint16_t>(address));
        const auto frame = qdock::experimental::makeReadRegistersFrame(addresses);
        const QByteArray bytes(reinterpret_cast<const char*>(frame.data()), frame.size());
        QTextStream(stderr) << "Consulta " << (batchIndex + 1) << "/3: registros 0x"
                            << QString::number(first, 16).rightJustified(2, '0').toUpper()
                            << "-0x" << QString::number(last, 16).rightJustified(2, '0').toUpper()
                            << " (" << addresses.size() << ")\n";
        if (port.write(bytes) != bytes.size() || !port.waitForBytesWritten(1000)) {
            QTextStream(stderr) << "No se pudo enviar la consulta.\n";
            app.exit(1);
            return;
        }
        timeout.start(3000);
    };

    QObject::connect(&timeout, &QTimer::timeout, [&] {
        QTextStream(stderr) << "Timeout: recibidos " << received.size() << " de 128 registros.\n";
        app.exit(3);
    });
    QObject::connect(&port, &QSerialPort::readyRead, [&] {
        const auto incoming = port.readAll();
        for (const auto& event : parser.feed(reinterpret_cast<const std::uint8_t*>(incoming.constData()), incoming.size())) {
            qdock::experimental::RegisterReading reading;
            if (!qdock::experimental::decodeRegisterInfo(event, reading))
                continue;
            if (!received.insert(reading.address).second)
                continue;
            QTextStream(stdout) << "{\"register\":\"0x"
                << QString::number(reading.address, 16).rightJustified(2, '0').toUpper()
                << "\",\"value\":\"0x"
                << QString::number(reading.value, 16).rightJustified(4, '0').toUpper()
                << "\",\"decimal\":" << reading.value << "}\n";
        }
        const auto [first, last] = batches[batchIndex];
        bool complete = true;
        for (int address = first; address <= last; ++address)
            complete = complete && received.count(static_cast<std::uint16_t>(address));
        if (!complete)
            return;
        timeout.stop();
        if (++batchIndex < static_cast<int>(batches.size())) {
            QTimer::singleShot(100, sendBatch);
        } else {
            QTextStream(stderr) << "Completado: 128 de 128 registros leídos; cero escrituras de registros.\n";
            app.exit(0);
        }
    });

    QTextStream(stderr) << "EXPERIMENTAL: lectura BK4819 0x00-0x7F mediante ReadRegisters 0x0851.\n"
                        << "No usa WriteRegisters, EEPROM, GPIO, teclas, frecuencia, TX ni PTT.\n";
    QTimer::singleShot(0, sendBatch);
    return app.exec();
}
