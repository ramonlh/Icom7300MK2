// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/eepromquery.h"
#include <QCoreApplication>
#include <QSerialPort>
#include <QTextStream>
#include <QTimer>

namespace {
constexpr std::uint32_t sessionId = 0x12345678;

QString modulationName(std::uint8_t value) {
    static const char* names[] = {"FM", "AM", "USB", "LSB", "BYP", "RAW"};
    return value < 6 ? QString::fromLatin1(names[value]) : QStringLiteral("desconocido");
}

QString powerName(std::uint8_t value) {
    static const char* names[] = {"Low", "Med", "High"};
    return value < 3 ? QString::fromLatin1(names[value]) : QStringLiteral("desconocida");
}

QString offsetName(std::uint8_t value) {
    return value == 1 ? QStringLiteral("+") : value == 2 ? QStringLiteral("-")
                                                       : QStringLiteral("off");
}

int ctcssTenths(std::uint8_t index) {
    static const int tones[] = {
        670,693,719,744,770,797,825,854,885,915,948,974,1000,1035,1072,
        1109,1148,1188,1230,1273,1318,1365,1413,1462,1514,1567,1598,1622,
        1655,1679,1713,1738,1773,1799,1835,1862,1899,1928,1966,1995,2035,
        2065,2107,2181,2257,2291,2336,2418,2503,2541
    };
    return index < sizeof(tones) / sizeof(tones[0]) ? tones[index] : 0;
}

int stepHz(std::uint8_t index) {
    static const int steps[] = {2500,5000,6250,10000,12500,25000,8330,1,10,
                                100,500,1000,15000,30000,50000,100000,125000,
                                250000,500000};
    return index < sizeof(steps) / sizeof(steps[0]) ? steps[index] : 0;
}
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (argc != 4) {
        QTextStream(stderr) << "Uso: qdock-eeprom-query /dev/ttyUSB0 OFFSET TAMAÑO\n"
                            << "OFFSET admite decimal o 0xHEX; TAMAÑO: 1-128.\n";
        return 2;
    }
    bool offsetOk = false, sizeOk = false;
    const QString offsetText = QString::fromLocal8Bit(argv[2]);
    const int base = offsetText.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive) ? 16 : 10;
    const uint offset = offsetText.toUInt(&offsetOk, base);
    const uint size = QString::fromLocal8Bit(argv[3]).toUInt(&sizeOk, 10);
    if (!offsetOk || !sizeOk || offset > 0xffff || size == 0 || size > 128
        || offset + size > 0x2000) {
        QTextStream(stderr) << "Rango inválido; EEPROM 0x0000-0x1FFF, bloques de 1-128 bytes.\n";
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

    qdock::Parser parser;
    QTimer timeout;
    timeout.setSingleShot(true);
    bool readSent = false;
    auto send = [&](const std::vector<std::uint8_t>& frame) {
        const QByteArray bytes(reinterpret_cast<const char*>(frame.data()), frame.size());
        return port.write(bytes) == bytes.size() && port.waitForBytesWritten(1000);
    };

    QObject::connect(&timeout, &QTimer::timeout, [&] {
        QTextStream(stderr) << (readSent ? "Timeout esperando ReadEepromReply 0x051C.\n"
                                           : "Timeout esperando sesión 0x0515.\n");
        app.exit(3);
    });
    QObject::connect(&port, &QSerialPort::readyRead, [&] {
        const auto incoming = port.readAll();
        for (const auto& event : parser.feed(
                 reinterpret_cast<const std::uint8_t*>(incoming.constData()), incoming.size())) {
            if (!readSent && qdock::experimental::isEepromSessionInfo(event)) {
                const auto request = qdock::experimental::makeReadEepromFrame(
                    static_cast<std::uint16_t>(offset), static_cast<std::uint8_t>(size), sessionId);
                if (!send(request)) {
                    QTextStream(stderr) << "No se pudo enviar ReadEeprom 0x051B.\n";
                    app.exit(1);
                    return;
                }
                readSent = true;
                timeout.start(3000);
                continue;
            }
            qdock::experimental::EepromReading reading;
            if (readSent && qdock::experimental::decodeEepromInfo(event, reading)
                && reading.offset == offset && reading.data.size() == size) {
                const QByteArray data(reinterpret_cast<const char*>(reading.data.data()),
                                      static_cast<qsizetype>(reading.data.size()));
                QTextStream(stdout) << "{\"offset\":\"0x"
                    << QString::number(reading.offset, 16).rightJustified(4, '0').toUpper()
                    << "\",\"size\":" << reading.data.size()
                    << ",\"data_hex\":\"" << data.toHex() << "\"";
                qdock::experimental::EepromChannel channel;
                if ((reading.offset % 16) == 0
                    && qdock::experimental::decodeEepromChannel(reading.data, channel)) {
                    QTextStream(stdout)
                        << ",\"channel\":{"
                        << "\"number\":" << (reading.offset / 16)
                        << ",\"rx_hz\":" << channel.rxFrequencyHz
                        << ",\"tx_hz\":" << channel.txFrequencyHz
                        << ",\"offset_hz\":" << channel.txOffsetHz
                        << ",\"offset_direction\":\"" << offsetName(channel.offsetDirection) << "\""
                        << ",\"mode\":\"" << modulationName(channel.modulation) << "\""
                        << ",\"power\":\"" << powerName(channel.power) << "\""
                        << ",\"bandwidth\":\"" << (channel.narrow ? "Narrow" : "Wide") << "\""
                        << ",\"rx_code_type\":" << channel.rxCodeType
                        << ",\"rx_code_index\":" << channel.rxCode
                        << ",\"tx_code_type\":" << channel.txCodeType
                        << ",\"tx_code_index\":" << channel.txCode
                        << ",\"tx_ctcss_hz\":"
                        << (channel.txCodeType == 1 ? ctcssTenths(channel.txCode) / 10.0 : 0.0)
                        << ",\"step_index\":" << channel.stepIndex
                        << ",\"step_hz\":" << stepHz(channel.stepIndex)
                        << ",\"busy_lock\":" << (channel.busyChannelLock ? "true" : "false")
                        << ",\"reverse\":" << (channel.reverse ? "true" : "false")
                        << ",\"dtmf_decode\":" << (channel.dtmfDecode ? "true" : "false")
                        << ",\"dtmf_ptt_id\":" << channel.dtmfPttId
                        << ",\"scrambler\":" << channel.scrambler << '}';
                }
                QTextStream(stdout) << "}\n";
                timeout.stop();
                app.exit(0);
                return;
            }
        }
    });

    QTextStream(stderr) << "EXPERIMENTAL: una lectura EEPROM; cero escrituras.\n"
                        << "Hello 0x0514 establece sesión y puede apagar la luz de pantalla.\n"
                        << "Lectura solicitada: 0x"
                        << QString::number(offset, 16).rightJustified(4, '0').toUpper()
                        << ", " << size << " bytes.\n";
    if (!send(qdock::experimental::makeStartEepromSessionFrame(sessionId))) {
        QTextStream(stderr) << "No se pudo iniciar la sesión EEPROM.\n";
        return 1;
    }
    timeout.start(3000);
    return app.exec();
}
