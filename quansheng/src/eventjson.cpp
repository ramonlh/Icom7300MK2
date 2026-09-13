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
}
