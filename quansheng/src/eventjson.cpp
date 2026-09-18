// SPDX-License-Identifier: GPL-2.0-only
#include "eventjson.h"
#include <QByteArray>
namespace qdock {
QJsonObject eventJson(const Event& e) {
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
    return json;
}

QJsonObject displayStateJson(const DisplayModel& model) {
    const auto vfo = [](const DisplayVfo& value) {
        return QJsonObject{{"frequencyText", QString::fromStdString(value.frequency)},
                           {"memory", QString::fromStdString(value.memory)},
                           {"name", QString::fromStdString(value.name)},
                           {"mode", QString::fromStdString(value.mode)},
                           {"power", QString::fromStdString(value.power)},
                           {"step", QString::fromStdString(value.step)},
                           {"selected", value.selected}};
    };
    const auto& flags = model.indicators();
    return {{"message", "display_state"},
            {"activeVfo", QString::fromStdString(model.activeVfo())},
            {"vfoA", vfo(model.vfoA())}, {"vfoB", vfo(model.vfoB())},
            {"indicators", QJsonObject{
                {"signalLevel", flags.signalLevel}, {"signalOver", flags.signalOver},
                {"batteryPercent", flags.batteryPercent}, {"noa", flags.noa},
                {"dtmf", flags.dtmf}, {"broadcastFm", flags.broadcastFm},
                {"scan", flags.scan}, {"dualWatch", flags.dualWatch},
                {"crossBand", flags.crossBand}, {"xb", flags.xb},
                {"vox", flags.vox}, {"locked", flags.locked},
                {"function", flags.function}, {"charging", flags.charging},
                {"statusCode", QString::fromStdString(flags.statusCode)},
                {"tone", QString::fromStdString(flags.tone)},
                {"step", QString::fromStdString(flags.step)},
                {"lastDtmf", QString::fromStdString(flags.lastDtmf)}}}};
}
}
