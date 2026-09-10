// SPDX-License-Identifier: GPL-2.0-only
#include "core/parser.h"
#ifdef QDOCK_SERIAL
#include "serial/reader.h"
#endif
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    app.setApplicationName("qdock-probe");
    app.setApplicationVersion("0.1.0");
    QCommandLineParser cli;
    cli.setApplicationDescription("Probe pasivo QuanshengDock. Sin escrituras, handshake ni PTT.");
    cli.addHelpOption(); cli.addVersionOption();
    cli.addOptions({{{"r", "replay"}, "Leer captura binaria sin radio.", "archivo"},
                    {{"p", "port"}, "Escuchar puerto autorizado explícitamente.", "puerto"},
                    {"list-ports", "Enumerar puertos sin abrirlos."},
                    {"seconds", "Duración de escucha (1–86400).", "segundos", "15"},
                    {"capture", "Guardar bytes recibidos en un archivo nuevo.", "archivo"}});
    cli.process(app);
    auto fail = [](const QString& message) { QTextStream(stderr) << message << '\n'; return 1; };
    if (!cli.positionalArguments().isEmpty()) return fail("No se admiten argumentos posicionales.");
    const int modes = cli.isSet("replay") + cli.isSet("port") + cli.isSet("list-ports");
    if (modes != 1) return fail("Elige --replay, --port o --list-ports. Consulta --help.");
    bool valid = false;
    const int seconds = cli.value("seconds").toInt(&valid);
    if (!valid || seconds < 1 || seconds > 86400) return fail("Duración inválida.");
    if (cli.isSet("seconds") && !cli.isSet("port")) return fail("--seconds requiere --port.");
    if (cli.isSet("capture") && !cli.isSet("port")) return fail("--capture requiere --port.");
#ifndef QDOCK_SERIAL
    if (!cli.isSet("replay")) return fail("Compilado sin SerialPort. Instala qt6-serialport-dev y recompila con -DQDOCK_SERIAL=ON.");
#else
    if (cli.isSet("list-ports")) { qdock::listPorts(); return 0; }
#endif
    QFile capture(cli.value("capture"));
    if (cli.isSet("capture") && !capture.open(QIODevice::WriteOnly | QIODevice::NewOnly))
        return fail("No se puede crear captura: " + capture.errorString());
    qdock::Parser parser;
    qint64 bytes = 0, count = 0;
    auto receive = [&](const QByteArray& chunk) {
        bytes += chunk.size();
        if (capture.isOpen() && capture.write(chunk) != chunk.size()) {
            fail("Error guardando captura: " + capture.errorString()); return false;
        }
        for (const auto& e : parser.feed(reinterpret_cast<const std::uint8_t*>(chunk.constData()), chunk.size())) {
            ++count;
            QJsonObject json;
            json["data_hex"] = QString::fromLatin1(QByteArray(reinterpret_cast<const char*>(e.data.data()), e.data.size()).toHex());
            if (e.kind == qdock::Event::Kind::Packet) {
                json["kind"] = "packet";
                json["command"] = int(e.data[0] | (e.data[1] << 8));
                json["crc_matches_command_algorithm"] = e.crcMatches;
            } else {
                json["kind"] = "ui"; json["type"] = e.type;
                json["val1"] = e.val1; json["val2"] = e.val2; json["val3"] = e.val3;
                json["field"] = e.field;
                if (e.type <= 3)
                    json["text"] = QString::fromLatin1(reinterpret_cast<const char*>(e.data.data()), e.data.size());
                if (e.type == 6) {
                    json["battery_volts"] = qMin(e.field * 0.04, 8.4);
                    switch (e.val1 & 7) {
                    case 1: json["state"] = "TX"; break;
                    case 2: json["state"] = "RX"; break;
                    case 4: json["state"] = "power_save"; break;
                    default: json["state"] = "idle";
                    }
                }
            }
            QTextStream(stdout) << QJsonDocument(json).toJson(QJsonDocument::Compact) << Qt::endl;
        }
        return true;
    };
    int result = 0;
    if (cli.isSet("replay")) {
        QFile input(cli.value("replay"));
        if (!input.open(QIODevice::ReadOnly)) return fail("No se puede leer captura: " + input.errorString());
        while (!input.atEnd()) {
            auto chunk = input.read(4096);
            if (input.error() != QFileDevice::NoError) return fail("Error leyendo captura: " + input.errorString());
            if (!receive(chunk)) return 1;
        }
    }
#ifdef QDOCK_SERIAL
    else result = qdock::readSerial(cli.value("port"), seconds, receive);
#endif
    if (capture.isOpen() && !capture.flush()) result = fail("Error al finalizar la captura: " + capture.errorString());
    QTextStream(stderr) << "bytes=" << bytes << " eventos=" << count
                        << " descartados=" << parser.discarded() << " pendientes=" << parser.pending() << '\n';
    if (bytes == 0) QTextStream(stderr) << "Sin tráfico; la escucha pasiva no activa el modo Dock.\n";
    if (parser.pending()) QTextStream(stderr) << "Trama incompleta al terminar.\n";
    return result;
}
