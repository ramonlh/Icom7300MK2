// SPDX-License-Identifier: GPL-2.0-only
#include "lan/serialsource.h"
#include "eventjson.h"
#include "serial/reader.h"
#include "experimental/rssiquery.h"
#include "experimental/registerquery.h"
#include "experimental/eepromquery.h"
#include "experimental/keycontrol.h"
#include <QDateTime>
#include <QJsonArray>
#include <QUuid>
#include <algorithm>

namespace {
QString frequencyText(quint32 hz) {
    return QString::number(hz / 1000000.0, 'f', 5);
}

QString indexedLabel(int value, const QStringList& labels, const QString& kind) {
    return value >= 0 && value < labels.size() ? labels.at(value)
                                               : QStringLiteral("%1 %2 (pendiente)").arg(kind).arg(value);
}

QString toneText(quint8 type, quint8 code) {
    switch (type) {
    case 0: return QStringLiteral("Desactivado");
    case 1: return QStringLiteral("CTCSS índice %1").arg(code);
    case 2: return QStringLiteral("DCS índice %1").arg(code);
    case 3: return QStringLiteral("DCS invertido índice %1").arg(code);
    default: return QStringLiteral("Tipo %1 / índice %2 (pendiente)").arg(type).arg(code);
    }
}

QString joinPresent(std::initializer_list<QString> values, const QString& separator) {
    QStringList present;
    for (const QString& value : values)
        if (!value.isEmpty()) present.append(value);
    return present.join(separator);
}

QJsonArray channelTable(const QByteArray& dump) {
    static const QStringList steps{QStringLiteral("2,5 kHz"), QStringLiteral("5 kHz"),
        QStringLiteral("6,25 kHz"), QStringLiteral("10 kHz"), QStringLiteral("12,5 kHz"),
        QStringLiteral("25 kHz"), QStringLiteral("8,33 kHz"), QStringLiteral("0,01 kHz"),
        QStringLiteral("0,05 kHz"), QStringLiteral("0,1 kHz"), QStringLiteral("0,25 kHz"),
        QStringLiteral("0,5 kHz"), QStringLiteral("1 kHz"), QStringLiteral("1,25 kHz"),
        QStringLiteral("9 kHz"), QStringLiteral("15 kHz"), QStringLiteral("20 kHz"),
        QStringLiteral("30 kHz"), QStringLiteral("50 kHz"), QStringLiteral("100 kHz"),
        QStringLiteral("125 kHz"), QStringLiteral("200 kHz"), QStringLiteral("250 kHz"),
        QStringLiteral("500 kHz")};
    const QStringList modes{QStringLiteral("FM"), QStringLiteral("AM"), QStringLiteral("USB")};
    const QStringList powers{QStringLiteral("Baja"), QStringLiteral("Media"),
                             QStringLiteral("Alta"), QStringLiteral("Usuario")};
    QJsonArray rows;
    for (int index = 0; index < 200; ++index) {
        const QByteArray raw = dump.mid(index * 16, 16);
        const bool empty = raw.size() != 16
            || std::all_of(raw.cbegin(), raw.cbegin() + 8,
                           [](char value) { return static_cast<uchar>(value) == 0xff; });
        QJsonObject row{{"channel", index + 1}, {"empty", empty}};
        const QByteArray nameRaw = dump.mid(0x0f50 + index * 16, 10);
        QString name;
        for (char byte : nameRaw) {
            const uchar value = static_cast<uchar>(byte);
            if (value < 32 || value > 126) break;
            name.append(QChar(value));
        }
        row.insert("name", name.trimmed());
        if (!empty) {
            std::vector<std::uint8_t> bytes(raw.cbegin(), raw.cend());
            qdock::experimental::EepromChannel channel;
            if (qdock::experimental::decodeEepromChannel(bytes, channel)) {
                row.insert("rx", frequencyText(channel.rxFrequencyHz));
                row.insert("tx", frequencyText(channel.txFrequencyHz));
                row.insert("offset", channel.offsetDirection == 0 ? QStringLiteral("Simplex")
                    : channel.offsetDirection == 1 ? QStringLiteral("+ %1 MHz").arg(frequencyText(channel.txOffsetHz))
                    : channel.offsetDirection == 2 ? QStringLiteral("− %1 MHz").arg(frequencyText(channel.txOffsetHz))
                    : QStringLiteral("Dirección %1 (pendiente)").arg(channel.offsetDirection));
                row.insert("mode", indexedLabel(channel.modulation, modes, QStringLiteral("Modo")));
                row.insert("bandwidth", channel.narrow ? QStringLiteral("Estrecho") : QStringLiteral("Ancho"));
                row.insert("power", indexedLabel(channel.power, powers, QStringLiteral("Potencia")));
                row.insert("rxTone", toneText(channel.rxCodeType, channel.rxCode));
                row.insert("txTone", toneText(channel.txCodeType, channel.txCode));
                row.insert("step", indexedLabel(channel.stepIndex, steps, QStringLiteral("Paso")));
                row.insert("flags", joinPresent({channel.reverse ? QStringLiteral("REV") : QString(),
                    channel.busyChannelLock ? QStringLiteral("BCL") : QString(),
                    channel.dtmfDecode ? QStringLiteral("DTMF") : QString(),
                    channel.scrambler ? QStringLiteral("SCR %1").arg(channel.scrambler) : QString()},
                    QStringLiteral(" · ")));
            }
        }
        const int attributeOffset = 0x0d60 + index;
        const uchar attribute = attributeOffset < dump.size()
            ? static_cast<uchar>(dump.at(attributeOffset)) : uchar(0xff);
        row.insert("scan", attribute == 0xff ? QStringLiteral("—")
            : joinPresent({attribute & 0x10 ? QStringLiteral("Lista 1") : QString(),
                           attribute & 0x20 ? QStringLiteral("Lista 2") : QString()},
                          QStringLiteral(" + ")));
        rows.append(row);
    }
    return rows;
}

QJsonArray settingsTable(const QByteArray& dump) {
    QJsonArray rows;
    const auto byte = [&](int offset) { return offset < dump.size() ? uchar(dump.at(offset)) : uchar(0xff); };
    const auto le16 = [&](int offset) { return quint16(byte(offset) | (quint16(byte(offset + 1)) << 8)); };
    const auto hex = [&](int offset, int size) { return QString::fromLatin1(dump.mid(offset, size).toHex(' ').toUpper()); };
    const auto ascii = [&](int offset, int size) {
        QString value;
        for (char raw : dump.mid(offset, size)) {
            const uchar c = static_cast<uchar>(raw);
            if (c == 0 || c == 0xff) break;
            value.append(c >= 32 && c <= 126 ? QChar(c) : QChar('.'));
        }
        return value.trimmed();
    };
    const auto add = [&](const QString& section, int address, const QString& field,
                         const QString& value, const QString& detail = {}) {
        rows.append(QJsonObject{{"section", section},
            {"address", QStringLiteral("0x%1").arg(address, 4, 16, QLatin1Char('0')).toUpper()},
            {"field", field}, {"value", value}, {"detail", detail}});
    };
    const auto yesNo = [](uchar value) { return value == 0 ? QStringLiteral("No")
        : value == 1 ? QStringLiteral("Sí") : QStringLiteral("%1 (pendiente)").arg(value); };
    const auto option = [](uchar value, const QStringList& labels, const QString& kind) {
        return value < labels.size() ? labels.at(value)
             : QStringLiteral("%1 %2 (pendiente)").arg(kind).arg(value);
    };
    const QStringList keyActions{QStringLiteral("Ninguna"), QStringLiteral("Linterna"),
        QStringLiteral("Potencia"), QStringLiteral("Monitor"), QStringLiteral("Escaneo"),
        QStringLiteral("VOX"), QStringLiteral("Alarma"), QStringLiteral("Radio FM"),
        QStringLiteral("1750 Hz"), QStringLiteral("Bloqueo"), QStringLiteral("A/B"),
        QStringLiteral("VFO/MR"), QStringLiteral("Cambiar demodulación"),
        QStringLiteral("Iluminación mínima temporal")};

    static const QStringList bandNames{QStringLiteral("50–76 MHz"), QStringLiteral("108–137 MHz"),
        QStringLiteral("137–174 MHz"), QStringLiteral("174–350 MHz"), QStringLiteral("350–400 MHz"),
        QStringLiteral("400–470 MHz"), QStringLiteral("470–600 MHz")};
    for (int band = 0; band < 7; ++band) {
        for (int vfo = 0; vfo < 2; ++vfo) {
            const int address = 0x0c80 + band * 32 + vfo * 16;
            const QByteArray raw = dump.mid(address, 16);
            std::vector<std::uint8_t> bytes(raw.cbegin(), raw.cend());
            qdock::experimental::EepromChannel channel;
            const bool empty = raw.size() != 16 || std::all_of(raw.cbegin(), raw.cend(),
                [](char value) { return static_cast<uchar>(value) == 0xff; });
            if (!empty && qdock::experimental::decodeEepromChannel(bytes, channel))
                add(QStringLiteral("VFO y bandas"), address,
                    QStringLiteral("VFO %1 · %2").arg(vfo ? QStringLiteral("B") : QStringLiteral("A"), bandNames.at(band)),
                    QStringLiteral("RX %1 MHz · TX %2 MHz").arg(frequencyText(channel.rxFrequencyHz), frequencyText(channel.txFrequencyHz)),
                    QStringLiteral("Modo %1 · paso %2").arg(channel.modulation).arg(channel.stepIndex));
        }
    }

    for (int index = 0; index < 20; ++index) {
        const quint16 value = le16(0x0e40 + index * 2);
        add(QStringLiteral("Radio FM"), 0x0e40 + index * 2,
            QStringLiteral("Memoria FM %1").arg(index + 1),
            value == 0xffff ? QStringLiteral("Vacía") : QStringLiteral("%1 MHz").arg(value / 10.0, 0, 'f', 1));
    }

    add(QStringLiteral("Ajustes generales"), 0x0e70, QStringLiteral("Canal de llamada"), QString::number(byte(0x0e70) + 1));
    add(QStringLiteral("Ajustes generales"), 0x0e71, QStringLiteral("Squelch"), QString::number(byte(0x0e71)));
    add(QStringLiteral("Ajustes generales"), 0x0e72, QStringLiteral("Temporizador TX"), QStringLiteral("Índice %1").arg(byte(0x0e72)));
    add(QStringLiteral("Ajustes generales"), 0x0e73, QStringLiteral("Escaneo NOAA automático"), yesNo(byte(0x0e73)));
    add(QStringLiteral("Ajustes generales"), 0x0e74, QStringLiteral("Bloqueo de teclado"), yesNo(byte(0x0e74)));
    add(QStringLiteral("Ajustes generales"), 0x0e75, QStringLiteral("VOX"), yesNo(byte(0x0e75)));
    add(QStringLiteral("Ajustes generales"), 0x0e76, QStringLiteral("Nivel VOX"), QString::number(byte(0x0e76)));
    add(QStringLiteral("Ajustes generales"), 0x0e77, QStringLiteral("Sensibilidad de micrófono"), QString::number(byte(0x0e77)));
    add(QStringLiteral("Pantalla y operación"), 0x0e78, QStringLiteral("Iluminación mínima / máxima"),
        QStringLiteral("%1 / %2").arg(byte(0x0e78) >> 4).arg(byte(0x0e78) & 0x0f));
    add(QStringLiteral("Pantalla y operación"), 0x0e79, QStringLiteral("Visualización de canal"),
        option(byte(0x0e79), {"Frecuencia", "Canal", "Nombre", "Nombre + frecuencia"}, QStringLiteral("Modo")));
    add(QStringLiteral("Pantalla y operación"), 0x0e7a, QStringLiteral("Cross-band"),
        option(byte(0x0e7a), {"Desactivado", "Canal A", "Canal B"}, QStringLiteral("Valor")));
    add(QStringLiteral("Pantalla y operación"), 0x0e7b, QStringLiteral("Ahorro de batería"), QStringLiteral("Nivel %1").arg(byte(0x0e7b)));
    add(QStringLiteral("Pantalla y operación"), 0x0e7c, QStringLiteral("Dual watch"),
        option(byte(0x0e7c), {"Desactivado", "Canal A", "Canal B"}, QStringLiteral("Valor")));
    add(QStringLiteral("Pantalla y operación"), 0x0e7d, QStringLiteral("Tiempo de iluminación"), QStringLiteral("Índice %1").arg(byte(0x0e7d)));
    add(QStringLiteral("Pantalla y operación"), 0x0e7e, QStringLiteral("Eliminación de cola"), yesNo(byte(0x0e7e)));
    add(QStringLiteral("Pantalla y operación"), 0x0e7f, QStringLiteral("VFO abierto"), yesNo(byte(0x0e7f)));
    add(QStringLiteral("VFO y bandas"), 0x0e80, QStringLiteral("Selección A"),
        QStringLiteral("pantalla %1 · memoria %2 · banda %3").arg(byte(0x0e80)).arg(byte(0x0e81)).arg(byte(0x0e82)));
    add(QStringLiteral("VFO y bandas"), 0x0e83, QStringLiteral("Selección B"),
        QStringLiteral("pantalla %1 · memoria %2 · banda %3").arg(byte(0x0e83)).arg(byte(0x0e84)).arg(byte(0x0e85)));
    add(QStringLiteral("Radio FM"), 0x0e88, QStringLiteral("Frecuencia seleccionada"),
        QStringLiteral("%1 MHz").arg(le16(0x0e88) / 10.0, 0, 'f', 1));
    add(QStringLiteral("Radio FM"), 0x0e8a, QStringLiteral("Memoria seleccionada"), QString::number(byte(0x0e8a) + 1));
    add(QStringLiteral("Radio FM"), 0x0e8b, QStringLiteral("Modo memoria"), yesNo(byte(0x0e8b)));
    add(QStringLiteral("Teclas y arranque"), 0x0e90, QStringLiteral("Pitido"), yesNo(byte(0x0e90) & 1));
    add(QStringLiteral("Teclas y arranque"), 0x0e90, QStringLiteral("Pulsación larga M"),
        option(byte(0x0e90) >> 1, keyActions, QStringLiteral("Acción")), QStringLiteral("Bits 1–7"));
    add(QStringLiteral("Teclas y arranque"), 0x0e91, QStringLiteral("Tecla 1 corta"), option(byte(0x0e91), keyActions, QStringLiteral("Acción")));
    add(QStringLiteral("Teclas y arranque"), 0x0e92, QStringLiteral("Tecla 1 larga"), option(byte(0x0e92), keyActions, QStringLiteral("Acción")));
    add(QStringLiteral("Teclas y arranque"), 0x0e93, QStringLiteral("Tecla 2 corta"), option(byte(0x0e93), keyActions, QStringLiteral("Acción")));
    add(QStringLiteral("Teclas y arranque"), 0x0e94, QStringLiteral("Tecla 2 larga"), option(byte(0x0e94), keyActions, QStringLiteral("Acción")));
    add(QStringLiteral("Teclas y arranque"), 0x0e95, QStringLiteral("Reanudación de escaneo"),
        option(byte(0x0e95), {"Tiempo", "Portadora", "Detener"}, QStringLiteral("Modo")));
    add(QStringLiteral("Teclas y arranque"), 0x0e96, QStringLiteral("Bloqueo automático"), yesNo(byte(0x0e96)));
    add(QStringLiteral("Teclas y arranque"), 0x0e97, QStringLiteral("Pantalla de encendido"),
        option(byte(0x0e97), {"Pantalla completa", "Mensaje", "Voltaje", "Ninguna"}, QStringLiteral("Modo")));
    add(QStringLiteral("Teclas y arranque"), 0x0e98, QStringLiteral("Contraseña de encendido"),
        hex(0x0e98, 4) == QStringLiteral("FF FF FF FF") ? QStringLiteral("No configurada") : QStringLiteral("Configurada"),
        QStringLiteral("Valor oculto"));
    add(QStringLiteral("Pantalla y operación"), 0x0ea0, QStringLiteral("Voz"),
        option(byte(0x0ea0), {"Desactivada", "Chino", "Inglés"}, QStringLiteral("Idioma")));
    add(QStringLiteral("Pantalla y operación"), 0x0ea1, QStringLiteral("Nivel S0"), QString::number(byte(0x0ea1)), QStringLiteral("Valor RSSI bruto"));
    add(QStringLiteral("Pantalla y operación"), 0x0ea2, QStringLiteral("Nivel S9"), QString::number(byte(0x0ea2)), QStringLiteral("Valor RSSI bruto"));
    add(QStringLiteral("Ajustes generales"), 0x0ea8, QStringLiteral("Modo de alarma"),
        option(byte(0x0ea8), {"Local", "Tono"}, QStringLiteral("Modo")));
    add(QStringLiteral("Ajustes generales"), 0x0ea9, QStringLiteral("Roger beep"),
        option(byte(0x0ea9), {"Desactivado", "Roger", "MDC"}, QStringLiteral("Modo")));
    add(QStringLiteral("Ajustes generales"), 0x0eaa, QStringLiteral("Cola de repetidor"), QStringLiteral("Índice %1").arg(byte(0x0eaa)));
    add(QStringLiteral("Ajustes generales"), 0x0eab, QStringLiteral("VFO de transmisión"), byte(0x0eab) ? QStringLiteral("B") : QStringLiteral("A"));
    add(QStringLiteral("Ajustes generales"), 0x0eac, QStringLiteral("Tipo de batería"), QStringLiteral("Índice %1").arg(byte(0x0eac)));
    add(QStringLiteral("Mensajes"), 0x0eb0, QStringLiteral("Bienvenida, línea 1"), ascii(0x0eb0, 16));
    add(QStringLiteral("Mensajes"), 0x0ec0, QStringLiteral("Bienvenida, línea 2"), ascii(0x0ec0, 16));

    add(QStringLiteral("DTMF"), 0x0ed0, QStringLiteral("Tono lateral"), yesNo(byte(0x0ed0)));
    add(QStringLiteral("DTMF"), 0x0ed1, QStringLiteral("Separador"), ascii(0x0ed1, 1));
    add(QStringLiteral("DTMF"), 0x0ed2, QStringLiteral("Llamada de grupo"), ascii(0x0ed2, 1));
    add(QStringLiteral("DTMF"), 0x0ed3, QStringLiteral("Respuesta de decodificación"), QStringLiteral("Modo %1").arg(byte(0x0ed3)));
    add(QStringLiteral("DTMF"), 0x0ed4, QStringLiteral("Reinicio automático"), QStringLiteral("%1 s").arg(byte(0x0ed4)));
    add(QStringLiteral("DTMF"), 0x0ed5, QStringLiteral("Tiempo de precarga"), QStringLiteral("%1 ms").arg(byte(0x0ed5) * 10));
    add(QStringLiteral("DTMF"), 0x0ed6, QStringLiteral("Persistencia primer código"), QStringLiteral("%1 ms").arg(byte(0x0ed6) * 10));
    add(QStringLiteral("DTMF"), 0x0ed7, QStringLiteral("Persistencia #"), QStringLiteral("%1 ms").arg(byte(0x0ed7) * 10));
    add(QStringLiteral("DTMF"), 0x0ed8, QStringLiteral("Persistencia de código"), QStringLiteral("%1 ms").arg(byte(0x0ed8) * 10));
    add(QStringLiteral("DTMF"), 0x0ed9, QStringLiteral("Intervalo entre códigos"), QStringLiteral("%1 ms").arg(byte(0x0ed9) * 10));
    add(QStringLiteral("DTMF"), 0x0eda, QStringLiteral("Permitir desactivación remota"), yesNo(byte(0x0eda)));
    add(QStringLiteral("DTMF"), 0x0ee0, QStringLiteral("ANI ID"), ascii(0x0ee0, 8));
    add(QStringLiteral("DTMF"), 0x0ee8, QStringLiteral("Código kill"), ascii(0x0ee8, 8).isEmpty() ? QStringLiteral("No configurado") : QStringLiteral("Configurado"), QStringLiteral("Valor oculto"));
    add(QStringLiteral("DTMF"), 0x0ef0, QStringLiteral("Código revive"), ascii(0x0ef0, 8).isEmpty() ? QStringLiteral("No configurado") : QStringLiteral("Configurado"), QStringLiteral("Valor oculto"));
    add(QStringLiteral("DTMF"), 0x0ef8, QStringLiteral("Código remoto arriba"), ascii(0x0ef8, 16));
    add(QStringLiteral("DTMF"), 0x0f08, QStringLiteral("Código remoto abajo"), ascii(0x0f08, 16));
    add(QStringLiteral("Escaneo"), 0x0f18, QStringLiteral("Lista predeterminada"), QStringLiteral("Índice %1").arg(byte(0x0f18)));
    add(QStringLiteral("Escaneo"), 0x0f19, QStringLiteral("Lista 1"), QStringLiteral("%1 · prioridad %2/%3").arg(yesNo(byte(0x0f19))).arg(byte(0x0f1a) + 1).arg(byte(0x0f1b) + 1));
    add(QStringLiteral("Escaneo"), 0x0f1c, QStringLiteral("Lista 2"), QStringLiteral("%1 · prioridad %2/%3").arg(yesNo(byte(0x0f1c))).arg(byte(0x0f1d) + 1).arg(byte(0x0f1e) + 1));
    add(QStringLiteral("Seguridad y firmware"), 0x0f30, QStringLiteral("Clave AES personalizada"),
        std::all_of(dump.cbegin() + 0x0f30, dump.cbegin() + 0x0f40,
                    [](char value) { return static_cast<uchar>(value) == 0xff; })
            ? QStringLiteral("No configurada") : QStringLiteral("Configurada"), QStringLiteral("Valor oculto"));
    add(QStringLiteral("Seguridad y firmware"), 0x0f40, QStringLiteral("Bloqueo de bandas TX"), QStringLiteral("Modo %1").arg(byte(0x0f40)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f41, QStringLiteral("TX 350 MHz"), yesNo(byte(0x0f41)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f42, QStringLiteral("Radio desactivada remotamente"), yesNo(byte(0x0f42)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f43, QStringLiteral("TX 200 MHz"), yesNo(byte(0x0f43)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f44, QStringLiteral("TX 500 MHz"), yesNo(byte(0x0f44)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f45, QStringLiteral("Recepción 350 MHz"), yesNo(byte(0x0f45)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f46, QStringLiteral("Scrambler habilitado"), yesNo(byte(0x0f46)));
    add(QStringLiteral("Seguridad y firmware"), 0x0f47, QStringLiteral("Decodificador DTMF en vivo"), yesNo((byte(0x0f47) >> 1) & 1), QStringLiteral("Bit 1"));
    add(QStringLiteral("Seguridad y firmware"), 0x0f47, QStringLiteral("Texto de batería"),
        option((byte(0x0f47) >> 2) & 3, {"Ninguno", "Voltaje", "Porcentaje"}, QStringLiteral("Modo")), QStringLiteral("Bits 2–3"));
    add(QStringLiteral("Seguridad y firmware"), 0x0f47, QStringLiteral("Barra de micrófono"), yesNo((byte(0x0f47) >> 4) & 1), QStringLiteral("Bit 4"));
    add(QStringLiteral("Seguridad y firmware"), 0x0f47, QStringLiteral("Corrección AM"), yesNo((byte(0x0f47) >> 5) & 1), QStringLiteral("Bit 5"));
    add(QStringLiteral("Seguridad y firmware"), 0x0f47, QStringLiteral("Iluminación en TX/RX"),
        QStringLiteral("Modo %1").arg((byte(0x0f47) >> 6) & 3), QStringLiteral("Bits 6–7"));

    for (int contact = 0; contact < 16; ++contact)
        add(QStringLiteral("Contactos DTMF"), 0x1c00 + contact * 32,
            QStringLiteral("Contacto %1").arg(contact + 1), hex(0x1c00 + contact * 32, 32),
            QStringLiteral("Registro bruto; estructura interna pendiente"));
    add(QStringLiteral("Calibración"), 0x1ec0, QStringLiteral("RSSI UHF"), hex(0x1ec0, 8), QStringLiteral("Valores brutos"));
    add(QStringLiteral("Calibración"), 0x1ec8, QStringLiteral("RSSI VHF"), hex(0x1ec8, 8), QStringLiteral("Valores brutos"));
    for (int index = 0; index < 6; ++index)
        add(QStringLiteral("Calibración"), 0x1f40 + index * 2,
            QStringLiteral("Batería %1").arg(index), QString::number(le16(0x1f40 + index * 2)), QStringLiteral("Valor ADC bruto"));
    add(QStringLiteral("Calibración"), 0x1f50, QStringLiteral("Umbrales VOX activación"), hex(0x1f50, 20), QStringLiteral("10 niveles · LE16 bruto"));
    add(QStringLiteral("Calibración"), 0x1f68, QStringLiteral("Umbrales VOX desactivación"), hex(0x1f68, 20), QStringLiteral("10 niveles · LE16 bruto"));
    add(QStringLiteral("Calibración"), 0x1f88, QStringLiteral("Corrección cristal BK4819"), QString::number(qint16(le16(0x1f88))), QStringLiteral("Valor firmado bruto"));
    add(QStringLiteral("Calibración"), 0x1f8e, QStringLiteral("Ganancia de volumen"), QString::number(byte(0x1f8e)));
    add(QStringLiteral("Calibración"), 0x1f8f, QStringLiteral("Ganancia DAC"), QString::number(byte(0x1f8f)));
    return rows;
}
}

SerialSource::SerialSource(QObject* parent) : QObject(parent) {
    pttTimer_.setInterval(50);
    connect(&pttTimer_, &QTimer::timeout, this, [this] {
        if (!pttOwner_) return;
        if (pttLease_.elapsed() >= 1500) { endPtt("lease_expired"); return; }
        if (pttDuration_.elapsed() >= pttMaxSeconds_ * 1000) { endPtt("max_duration"); return; }
        if (port_.bytesToWrite() != 0 || !writePttKey(true))
            finish("error", "ptt_serial_write_failed");
    });
    connect(&statsTimer_, &QTimer::timeout, this, &SerialSource::stats);
    stopTimer_.setSingleShot(true);
    connect(&stopTimer_, &QTimer::timeout, this, [this] { finish("ended"); });
    connect(&rssiTimer_, &QTimer::timeout, this, [this] {
        if (!allowRssiQuery_ || eepromBusy_ || frequencyBusy_ || vfoBusy_ || pttOwner_
                || status_ != "listening" || port_.bytesToWrite() != 0) return;
        const auto frame = qdock::experimental::makeGetRssiFrame();
        port_.write(reinterpret_cast<const char*>(frame.data()), frame.size());
    });
    connect(&registerTimer_, &QTimer::timeout, this, [this] {
        if (!allowRegisterQuery_ || eepromBusy_ || frequencyBusy_ || vfoBusy_ || pttOwner_
                || status_ != "listening" || port_.bytesToWrite() != 0) return;
        frequencyCycle_.clear();
        const auto frame = qdock::experimental::makeReadRegistersFrame({0x38, 0x39});
        port_.write(reinterpret_cast<const char*>(frame.data()), frame.size());
    });
    connect(&diagnosticTimer_, &QTimer::timeout,
            this, &SerialSource::requestDiagnosticRegisters);
    frequencyTimer_.setSingleShot(true);
    connect(&frequencyTimer_, &QTimer::timeout, this, [this] {
        const bool vfo = vfoBusy_;
        if ((!frequencyBusy_ && !vfo) || status_ != QStringLiteral("listening")) return;
        auto& frames = vfo ? vfoFrames_ : frequencyFrames_;
        if (frames.isEmpty()) {
            frequencyBusy_ = false;
            vfoBusy_ = false;
            emit message({{"message", vfo ? "vfo_status" : "frequency_status"}, {"status", "complete"}});
            return;
        }
        if (port_.bytesToWrite() != 0) { frequencyTimer_.start(20); return; }
        port_.write(frames.takeFirst());
        emit message({{"message", vfo ? "vfo_status" : "frequency_status"}, {"status", "sent"},
                      {"framesRemaining", frames.size()}});
        // El UV-K5 necesita tiempo para registrar y liberar cada tecla;
        // con intervalos menores algunos dígitos iniciales se pierden.
        frequencyTimer_.start(vfo ? 120 : 150);
    });
    eepromTimer_.setSingleShot(true);
    connect(&eepromTimer_, &QTimer::timeout, this, [this] {
        if (!eepromBusy_) return;
        eepromBusy_ = false;
        eepromAwaitingSession_ = false;
        if (eepromSquelchOnly_) {
            eepromSquelchOnly_ = false;
            emit message({{"message", "radio_settings"}, {"squelchLevel", QJsonValue::Null},
                          {"error", "Timeout leyendo nivel de squelch"}});
            return;
        }
        emit message({{"message", "eeprom_status"}, {"status", "error"},
                      {"error", "Timeout esperando respuesta EEPROM"}});
    });
    connect(&port_, &QSerialPort::readyRead, this, [this] {
        if (status_ != "listening") return;
        const auto data = port_.readAll();
        bytes_ += data.size();
        if (diagnosticRxBytes_ < 256) {
            const auto sample = data.left(256 - diagnosticRxBytes_);
            diagnosticRxBytes_ += sample.size();
            qInfo().noquote() << "Quansheng serie RX muestra" << sample.size()
                              << "bytes:" << sample.toHex(' ');
        }
        if (capture_.isOpen()) {
            const auto written = capture_.write(data);
            if (written > 0) capturedBytes_ += written;
            if (written != data.size() || !capture_.flush()) {
                finish("error", "Error guardando captura: " + capture_.errorString());
                return;
            }
        }
        for (const auto& event : parser_.feed(
                 reinterpret_cast<const std::uint8_t*>(data.constData()), data.size())) {
            emit message({{"message", "event"}, {"source", "serial"},
                          {"session", session_}, {"sequence", QString::number(++sequence_)},
                          {"observedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
                          {"quality", "candidate"}, {"decoder", "qdock-probe/0.1.0"},
                          {"event", qdock::eventJson(event)}});
            qdock::experimental::RssiReading rssi;
            if (allowRssiQuery_ && qdock::experimental::decodeRssiInfo(event, rssi)) {
                emit message({{"message", "rssi_state"},
                              {"raw", int(rssi.raw)},
                              {"dbmUncorrected", qdock::experimental::rssiDbmUncorrected(rssi.raw)},
                              {"noise", int(rssi.noise)}, {"glitch", int(rssi.glitch)},
                              {"observedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}});
            }
            qdock::experimental::RegisterReading reg;
            if (allowRegisterQuery_ && qdock::experimental::decodeRegisterInfo(event, reg)) {
                if (reg.address == 0x38 || reg.address == 0x39) {
                    frequencyCycle_.insert(reg.address, reg.value);
                    if (frequencyCycle_.size() == 2) {
                        latestFrequencyRegisters_ = frequencyCycle_;
                        const quint32 units10Hz = quint32(frequencyCycle_.value(0x38))
                                                  | (quint32(frequencyCycle_.value(0x39)) << 16);
                        emit message({{"message", "register_frequency_state"},
                                      {"frequencyHz", QString::number(quint64(units10Hz) * 10)},
                                      {"low", frequencyCycle_.value(0x38)},
                                      {"high", frequencyCycle_.value(0x39)},
                                      {"observedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}});
                        frequencyCycle_.clear();
                    }
                    continue;
                }
                registerCycle_.insert(reg.address, reg.value);
                if (registerCycle_.size() == 50) {
                    QJsonObject values;
                    for (auto it = registerCycle_.cbegin(); it != registerCycle_.cend(); ++it)
                        values.insert(QStringLiteral("%1").arg(it.key(), 2, 16, QLatin1Char('0')).toUpper(), it.value());
                    for (auto it = latestFrequencyRegisters_.cbegin(); it != latestFrequencyRegisters_.cend(); ++it)
                        values.insert(QStringLiteral("%1").arg(it.key(), 2, 16, QLatin1Char('0')).toUpper(), it.value());
                    const auto blocks = qdock::experimental::decodeRegister30(registerCycle_.value(0x30));
                    const auto agc = qdock::experimental::decodeRegister7E(registerCycle_.value(0x7e));
                    const QJsonObject blockState{{"vcoCalibration", blocks.vcoCalibration},
                        {"rxLink", int(blocks.rxLink)}, {"afDac", blocks.afDac},
                        {"discriminator", blocks.discriminator}, {"pllVco", int(blocks.pllVco)},
                        {"paGain", blocks.paGain}, {"micAdc", blocks.micAdc},
                        {"txDsp", blocks.txDsp}, {"rxDsp", blocks.rxDsp}};
                    const QJsonObject agcState{{"mode", agc.fixedAgc ? "fijo" : "auto"},
                        {"gainIndex", agc.gainIndex}, {"signalStrength", int(agc.signalStrength)},
                        {"txDcFilter", int(agc.txDcFilter)}, {"rxDcFilter", int(agc.rxDcFilter)}};
                    const int reg31 = registerCycle_.value(0x31);
                    const int reg33 = registerCycle_.value(0x33);
                    const int reg47 = registerCycle_.value(0x47);
                    const int reg48 = registerCycle_.value(0x48);
                    const int reg49 = registerCycle_.value(0x49);
                    const int reg43 = registerCycle_.value(0x43);
                    const int reg4d = registerCycle_.value(0x4d);
                    const int reg4e = registerCycle_.value(0x4e);
                    const int reg4f = registerCycle_.value(0x4f);
                    const int reg78 = registerCycle_.value(0x78);
                    const int reg36 = registerCycle_.value(0x36);
                    const int reg51 = registerCycle_.value(0x51);
                    const int reg52 = registerCycle_.value(0x52);
                    const int reg70 = registerCycle_.value(0x70);
                    const int reg19 = registerCycle_.value(0x19);
                    const int reg28 = registerCycle_.value(0x28);
                    const int reg29 = registerCycle_.value(0x29);
                    const int reg3d = registerCycle_.value(0x3d);
                    const int reg46 = registerCycle_.value(0x46);
                    const int reg79 = registerCycle_.value(0x79);
                    const int reg7a = registerCycle_.value(0x7a);
                    const QJsonObject functions{{"scrambler", bool(reg31 & 0x0002)},
                        {"vox", bool(reg31 & 0x0004)}, {"compander", bool(reg31 & 0x0008)}};
                    const QJsonObject gpio{{"rxEnable", bool(reg33 & 0x0040)},
                        {"paEnable", bool(reg33 & 0x0020)}, {"uhfLna", bool(reg33 & 0x0008)},
                        {"vhfLna", bool(reg33 & 0x0004)}, {"redLed", bool(reg33 & 0x0002)},
                        {"greenLed", bool(reg33 & 0x0001)}};
                    const QJsonObject audio{{"output", (reg47 >> 8) & 0x0f},
                        {"gain1", (reg48 >> 10) & 0x03}, {"gain2", (reg48 >> 4) & 0x3f},
                        {"dacGain", reg48 & 0x0f}};
                    const QJsonObject rfAgc{{"loMode", (reg49 >> 14) & 0x03},
                        {"highThreshold", (reg49 >> 7) & 0x7f}, {"lowThreshold", reg49 & 0x7f}};
                    const QJsonObject filter{{"rf", (reg43 >> 12) & 0x07},
                        {"weakRf", (reg43 >> 9) & 0x07}, {"doubleRf", bool(reg43 & 0x0020)},
                        {"txLpf", (reg43 >> 6) & 0x07}, {"bandwidthMode", (reg43 >> 4) & 0x03},
                        {"fmGain6dB", bool(reg43 & 0x0004)}};
                    const QJsonObject squelch{{"closeGlitch", reg4d & 0xff},
                        {"openGlitch", reg4e & 0xff}, {"openDelay", (reg4e >> 11) & 0x07},
                        {"closeDelay", (reg4e >> 9) & 0x03}, {"closeNoise", (reg4f >> 8) & 0x7f},
                        {"openNoise", reg4f & 0x7f}, {"openRssi", (reg78 >> 8) & 0xff},
                        {"closeRssi", reg78 & 0xff}};
                    const QJsonObject pa{{"bias", (reg36 >> 8) & 0xff},
                        {"enabled", bool(reg36 & 0x0080)}, {"gain1", (reg36 >> 3) & 0x07},
                        {"gain2", reg36 & 0x07}};
                    const QJsonObject css{{"enabled", bool(reg51 & 0x8000)},
                        {"gpioInput", bool(reg51 & 0x4000)}, {"negative", bool(reg51 & 0x2000)},
                        {"mode", (reg51 & 0x1000) ? "CTCSS" : "CDCSS"},
                        {"cdcss24Bit", bool(reg51 & 0x0800)}, {"detect1050", bool(reg51 & 0x0400)},
                        {"autoCdcssBw", !(reg51 & 0x0200)}, {"autoCtcssBw", !(reg51 & 0x0100)},
                        {"txGain", reg51 & 0x7f}, {"tailEnabled", bool(reg52 & 0x8000)},
                        {"tailMode", (reg52 >> 13) & 0x03}, {"percentThreshold", bool(reg52 & 0x1000)},
                        {"foundThreshold", (reg52 >> 6) & 0x3f}, {"lostThreshold", reg52 & 0x3f}};
                    const QJsonObject tones{{"tone1Enabled", bool(reg70 & 0x8000)},
                        {"tone1Gain", (reg70 >> 8) & 0x7f}, {"tone2Enabled", bool(reg70 & 0x0080)},
                        {"tone2Gain", reg70 & 0x7f}};
                    const QJsonObject advanced{{"micAgc", !(reg19 & 0x8000)},
                        {"rxExpandRatio", (reg28 >> 14) & 0x03},
                        {"rxExpandPoint", (reg28 >> 7) & 0x7f}, {"rxExpandNoise", reg28 & 0x7f},
                        {"txCompressRatio", (reg29 >> 14) & 0x03},
                        {"txCompressPoint", (reg29 >> 7) & 0x7f}, {"txCompressNoise", reg29 & 0x7f},
                        {"ifValue", reg3d}, {"voxOpen", reg46 & 0x07ff},
                        {"voxClose", reg79 & 0x07ff}, {"voxDelayCode", (reg7a >> 12) & 0x0f}};
                    emit message({{"message", "register_state"}, {"values", values},
                                  {"blocks", blockState}, {"agc", agcState},
                                  {"functions", functions}, {"gpio", gpio},
                                  {"audio", audio}, {"rfAgc", rfAgc},
                                  {"filter", filter}, {"squelch", squelch},
                                  {"pa", pa}, {"css", css}, {"tones", tones},
                                  {"advanced", advanced},
                                  {"afcEnabled", qdock::experimental::afcEnabledFromRegister73(registerCycle_.value(0x73))},
                                  {"observedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}});
                    registerCycle_.clear();
                }
            }
            qdock::experimental::EepromReading reading;
            if (eepromBusy_ && qdock::experimental::decodeEepromInfo(event, reading)
                && reading.offset == eepromOffset_) {
                eepromTimer_.stop();
                if (eepromSquelchOnly_) {
                    eepromBusy_ = false;
                    eepromSquelchOnly_ = false;
                    const int index = 0x0e71 - int(reading.offset);
                    squelchLevel_ = index >= 0 && index < int(reading.data.size())
                        ? int(reading.data.at(std::size_t(index))) : -1;
                    if (squelchLevel_ < 0 || squelchLevel_ > 9)
                        squelchLevel_ = -1;
                    emit message({{"message", "radio_settings"},
                                  {"squelchLevel", squelchLevel_ >= 0
                                      ? QJsonValue(squelchLevel_) : QJsonValue::Null}});
                    continue;
                }
                eepromData_.append(reinterpret_cast<const char*>(reading.data.data()),
                                   qsizetype(reading.data.size()));
                eepromOffset_ = quint16(eepromOffset_ + reading.data.size());
                emit message({{"message", "eeprom_status"}, {"status", "reading"},
                              {"bytesRead", eepromData_.size()}, {"totalBytes", 0x2000}});
                if (eepromOffset_ == 0x2000) {
                    eepromBusy_ = false;
                    emit message({{"message", "eeprom_dump"}, {"offset", 0},
                                  {"size", eepromData_.size()},
                                  {"channels", channelTable(eepromData_)},
                                  {"settings", settingsTable(eepromData_)},
                                  {"dataBase64", QString::fromLatin1(eepromData_.toBase64())}});
                    emit message({{"message", "eeprom_status"}, {"status", "complete"},
                                  {"bytesRead", eepromData_.size()}, {"totalBytes", 0x2000}});
                } else {
                    sendNextEepromBlock();
                }
                continue;
            }
            if (eepromBusy_ && eepromAwaitingSession_
                && qdock::experimental::isEepromSessionInfo(event)) {
                eepromTimer_.stop();
                eepromAwaitingSession_ = false;
                sendNextEepromBlock();
            }
            if (event.kind == qdock::Event::Kind::Ui && event.type == 6) {
                transmitting_ = ((event.val1 & 7) == 1);
                radioStateAge_.start();
            }
            if (displayModel_.apply(event)) {
                auto state = qdock::displayStateJson(displayModel_);
                state.insert("source", "serial");
                state.insert("session", session_);
                emit message(state);
            }
        }
    });
    connect(&port_, &QSerialPort::errorOccurred, this, [this](auto error) {
        if (error != QSerialPort::NoError && status_ == "listening")
            finish("error", port_.errorString());
    });
}

void SerialSource::start(const QString& port, int seconds, const QString& capturePath,
                         bool allowRssiQuery, bool allowRegisterQuery,
                         bool allowEepromQuery, bool allowFrequencyControl, bool allowPtt, int pttMaxSeconds) {
    if (status_ != "not_started") return;
    session_ = QUuid::createUuid().toString(QUuid::WithoutBraces);
    captureRequested_ = !capturePath.isEmpty();
    if (captureRequested_) {
        capture_.setFileName(capturePath);
        if (!capture_.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
            finish("error", "No se puede crear captura nueva: " + capture_.errorString());
            return;
        }
    }
    allowRssiQuery_ = allowRssiQuery;
    allowRegisterQuery_ = allowRegisterQuery;
    allowEepromQuery_ = allowEepromQuery;
    allowFrequencyControl_ = allowFrequencyControl;
    allowPtt_ = allowPtt;
    pttMaxSeconds_ = pttMaxSeconds;
    QString error;
    const bool opened = (allowRssiQuery_ || allowRegisterQuery_ || allowEepromQuery_ || allowFrequencyControl_ || allowPtt_)
                            ? qdock::openRssiQuery(port_, port, error)
                            : qdock::openReadOnly(port_, port, error);
    if (!opened) {
        finish("error", error);
        return;
    }
    status_ = "listening";
    emit message(snapshot());
    statsTimer_.start(1000);
    if (allowRssiQuery_) {
        qWarning().noquote() << "MODO RSSI EXPERIMENTAL: GetRssi 0x0527 cada segundo.";
        rssiTimer_.start(1000);
    }
    if (allowRegisterQuery_) {
        qWarning().noquote() << "MODO REGISTROS EXPERIMENTAL: frecuencia cada 2 s; diagnóstico cada 30 s.";
        // Desfasados de GetRssi para no iniciar consultas en el mismo instante.
        QTimer::singleShot(500, this, [this] {
            if (allowRegisterQuery_ && status_ == "listening")
                registerTimer_.start(2000);
        });
        QTimer::singleShot(3500, this, [this] {
            if (allowRegisterQuery_ && status_ == "listening") {
                requestDiagnosticRegisters();
                diagnosticTimer_.start(30000);
            }
        });
    }
    if (allowEepromQuery_)
        QTimer::singleShot(1500, this, &SerialSource::requestInitialSquelchLevel);
    stopTimer_.start(seconds * 1000);
}

void SerialSource::requestInitialSquelchLevel() {
    if (!allowEepromQuery_ || eepromBusy_ || pttOwner_ || frequencyBusy_ || vfoBusy_ || transmitting_ || status_ != QStringLiteral("listening")
        || !port_.isOpen())
        return;
    eepromBusy_ = true;
    eepromAwaitingSession_ = true;
    eepromSquelchOnly_ = true;
    eepromOffset_ = 0x0e00;
    eepromData_.clear();
    const auto frame = qdock::experimental::makeStartEepromSessionFrame(0x12345678);
    port_.write(reinterpret_cast<const char*>(frame.data()), frame.size());
    eepromTimer_.start(2000);
}

QString SerialSource::requestEepromRead() {
    if (!allowEepromQuery_) return QStringLiteral("eeprom_read_not_enabled");
    if (status_ != QStringLiteral("listening") || !port_.isOpen())
        return QStringLiteral("serial_not_listening");
    if (pttOwner_ || transmitting_ || frequencyBusy_ || vfoBusy_) return QStringLiteral("radio_control_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    eepromBusy_ = true;
    eepromAwaitingSession_ = true;
    eepromSquelchOnly_ = false;
    eepromOffset_ = 0;
    eepromData_.clear();
    emit message({{"message", "eeprom_status"}, {"status", "starting"},
                  {"bytesRead", 0}, {"totalBytes", 0x2000}});
    const auto frame = qdock::experimental::makeStartEepromSessionFrame(0x12345678);
    port_.write(reinterpret_cast<const char*>(frame.data()), frame.size());
    eepromTimer_.start(2000);
    return {};
}

QString SerialSource::requestFrequencyChange(quint32 frequencyHz) {
    if (!allowFrequencyControl_) return QStringLiteral("frequency_control_not_enabled");
    if (status_ != QStringLiteral("listening") || !port_.isOpen())
        return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("frequency_change_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("frequency_change_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    const auto active = displayModel_.activeVfo();
    const auto& vfo = active == "A" ? displayModel_.vfoA() : displayModel_.vfoB();
    if (active.empty() || vfo.memory.empty() || vfo.memory.front() != 'F')
        return QStringLiteral("frequency_vfo_required");
    std::vector<std::vector<std::uint8_t>> frames;
    try { frames = qdock::experimental::makeFrequencyEntryFrames(frequencyHz); }
    catch (const std::invalid_argument& error) { return QString::fromUtf8(error.what()); }
    frequencyFrames_.clear();
    for (const auto& frame : frames) {
        frequencyFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
        const auto release = qdock::experimental::makeKeyPressFrame(19);
        frequencyFrames_.append(QByteArray(reinterpret_cast<const char*>(release.data()), int(release.size())));
    }
    frequencyBusy_ = true;
    emit message({{"message", "frequency_status"}, {"status", "starting"},
                  {"frequencyHz", qint64(frequencyHz)}, {"vfo", QString::fromStdString(active)}});
    frequencyTimer_.start(0);
    return {};
}

QString SerialSource::requestVfoSwitch() {
    if (!allowFrequencyControl_) return QStringLiteral("frequency_control_not_enabled");
    if (status_ != QStringLiteral("listening") || !port_.isOpen()) return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("vfo_switch_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("vfo_switch_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    vfoFrames_.clear();
    for (const auto& frame : qdock::experimental::makeVfoSwitchFrames())
        vfoFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
    vfoBusy_ = true;
    emit message({{"message", "vfo_status"}, {"status", "starting"}});
    frequencyTimer_.start(0);
    return {};
}

QString SerialSource::requestVfoModeToggle(const QString& targetVfo) {
    if (targetVfo != "A" && targetVfo != "B") return QStringLiteral("vfo_invalido");
    if (!allowFrequencyControl_) return QStringLiteral("frequency_control_not_enabled");
    if (status_ != "listening" || !port_.isOpen()) return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("vfo_mode_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("vfo_mode_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    const bool selectOther = displayModel_.activeVfo() != targetVfo.toStdString();
    vfoFrames_.clear();
    for (const auto& frame : qdock::experimental::makeVfoModeToggleFrames(selectOther))
        vfoFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
    vfoBusy_ = true;
    emit message({{"message", "vfo_status"}, {"status", "starting"}, {"targetVfo", targetVfo}});
    frequencyTimer_.start(0);
    return {};
}

QString SerialSource::requestMemoryStep(const QString& targetVfo, bool up) {
    if (targetVfo != "A" && targetVfo != "B") return QStringLiteral("vfo_invalido");
    if (!allowFrequencyControl_) return QStringLiteral("frequency_control_not_enabled");
    if (status_ != "listening" || !port_.isOpen()) return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("memory_step_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("memory_step_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    const bool selectOther = displayModel_.activeVfo() != targetVfo.toStdString();
    vfoFrames_.clear();
    for (const auto& frame : qdock::experimental::makeMemoryStepFrames(up, selectOther))
        vfoFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
    vfoBusy_ = true;
    emit message({{"message", "vfo_status"}, {"status", "starting"}, {"targetVfo", targetVfo}});
    frequencyTimer_.start(0);
    return {};
}

QString SerialSource::requestModeChange(const QString& targetVfo, const QString& mode) {
    static const QStringList modes{"FM", "AM", "USB", "BYP", "RAW"};
    const int modeIndex = modes.indexOf(mode);
    if (targetVfo != "A" && targetVfo != "B") return QStringLiteral("vfo_invalido");
    if (modeIndex < 0) return QStringLiteral("modo_invalido");
    if (!allowFrequencyControl_) return QStringLiteral("frequency_control_not_enabled");
    if (status_ != "listening" || !port_.isOpen()) return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("mode_change_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("mode_change_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    const bool selectOther = displayModel_.activeVfo() != targetVfo.toStdString();
    vfoFrames_.clear();
    for (const auto& frame : qdock::experimental::makeModeChangeFrames(
             static_cast<std::uint8_t>(modeIndex), selectOther))
        vfoFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
    vfoBusy_ = true;
    emit message({{"message", "vfo_status"}, {"status", "starting"},
                  {"targetVfo", targetVfo}, {"mode", mode}});
    frequencyTimer_.start(0);
    return {};
}

QString SerialSource::requestDualWatch(bool enabled) {
    if (!allowFrequencyControl_) return QStringLiteral("radio_control_not_enabled");
    if (status_ != "listening" || !port_.isOpen()) return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("radio_control_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("dual_watch_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    vfoFrames_.clear();
    for (const auto& frame : qdock::experimental::makeDualWatchFrames(enabled))
        vfoFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
    vfoBusy_ = true;
    emit message({{"message", "vfo_status"}, {"status", "starting"},
                  {"control", "dual_watch"}, {"enabled", enabled}});
    frequencyTimer_.start(0);
    return {};
}

QString SerialSource::requestSquelch(int level) {
    if (level < 0 || level > 9) return QStringLiteral("squelch_level_invalid");
    if (!allowFrequencyControl_) return QStringLiteral("radio_control_not_enabled");
    if (status_ != "listening" || !port_.isOpen()) return QStringLiteral("serial_not_listening");
    if (frequencyBusy_ || vfoBusy_) return QStringLiteral("radio_control_busy");
    if (eepromBusy_) return QStringLiteral("eeprom_read_busy");
    if (transmitting_ || pttOwner_) return QStringLiteral("squelch_while_transmitting");
    const auto& indicators = displayModel_.indicators();
    if (indicators.locked) return QStringLiteral("radio_locked");
    if (indicators.scan) return QStringLiteral("scan_active");
    vfoFrames_.clear();
    for (const auto& frame : qdock::experimental::makeSquelchFrames(std::uint8_t(level)))
        vfoFrames_.append(QByteArray(reinterpret_cast<const char*>(frame.data()), int(frame.size())));
    vfoBusy_ = true;
    squelchLevel_ = level;
    emit message({{"message", "radio_settings"}, {"squelchLevel", squelchLevel_}});
    emit message({{"message", "vfo_status"}, {"status", "starting"},
                  {"control", "squelch"}, {"level", level}});
    frequencyTimer_.start(0);
    return {};
}

void SerialSource::sendNextEepromBlock() {
    const int remaining = eepromSquelchOnly_ ? 128 : 0x2000 - int(eepromOffset_);
    const auto size = static_cast<std::uint8_t>(qMin(128, remaining));
    const auto frame = qdock::experimental::makeReadEepromFrame(
        eepromOffset_, size, 0x12345678);
    port_.write(reinterpret_cast<const char*>(frame.data()), frame.size());
    eepromTimer_.start(2000);
}

void SerialSource::requestDiagnosticRegisters() {
    if (!allowRegisterQuery_ || eepromBusy_ || frequencyBusy_ || vfoBusy_ || pttOwner_
            || status_ != "listening" || port_.bytesToWrite() != 0)
        return;
    registerCycle_.clear();
    const auto frame = qdock::experimental::makeReadRegistersFrame({
        0x07, 0x0b, 0x0c, 0x10, 0x11, 0x12, 0x13, 0x14, 0x19, 0x21,
        0x24, 0x28, 0x29,
        0x30, 0x31, 0x32, 0x33, 0x36, 0x37, 0x3d, 0x43, 0x46, 0x47,
        0x48, 0x49, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x63, 0x64,
        0x65, 0x67, 0x68, 0x69, 0x6a, 0x6f, 0x70, 0x71, 0x72, 0x73,
        0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e});
    port_.write(reinterpret_cast<const char*>(frame.data()), frame.size());
}

void SerialSource::stop() { if (status_ == "listening") finish("ended"); }

QJsonObject SerialSource::snapshot() const {
    return {{"message", "source_status"}, {"source", "serial"}, {"session", session_},
            {"status", status_}, {"error", error_}, {"portOpen", port_.isOpen()},
            {"captureRequested", captureRequested_}, {"captureOpen", capture_.isOpen()},
            {"rssiQueryEnabled", allowRssiQuery_},
            {"registerQueryEnabled", allowRegisterQuery_},
            {"frequencyControlEnabled", allowFrequencyControl_},
            {"nextSequence", QString::number(sequence_ + 1)}};
}

QJsonObject SerialSource::displaySnapshot() const {
    auto state = qdock::displayStateJson(displayModel_);
    state.insert("source", "serial");
    state.insert("session", session_);
    state.insert("squelchLevel", squelchLevel_ >= 0
        ? QJsonValue(squelchLevel_) : QJsonValue::Null);
    return state;
}

void SerialSource::stats() {
    emit message({{"message", "stats"}, {"session", session_},
                  {"bytes", QString::number(bytes_)}, {"events", QString::number(sequence_)},
                  {"capturedBytes", QString::number(capturedBytes_)},
                  {"discarded", QString::number(parser_.discarded())},
                  {"pending", QString::number(parser_.pending())}});
}

void SerialSource::finish(const QString& status, const QString& error) {
    if (finishing_) return;
    finishing_ = true;
    endPtt("source_stopped");
    eepromTimer_.stop();
    frequencyTimer_.stop();
    frequencyFrames_.clear();
    vfoFrames_.clear();
    frequencyBusy_ = false;
    vfoBusy_ = false;
    if (eepromBusy_) {
        eepromBusy_ = false;
        eepromAwaitingSession_ = false;
        emit message({{"message", "eeprom_status"}, {"status", "error"},
                      {"error", "La fuente serie se cerró durante la lectura EEPROM"}});
    }
    status_ = status;
    error_ = error;
    statsTimer_.stop();
    rssiTimer_.stop();
    registerTimer_.stop();
    diagnosticTimer_.stop();
    stopTimer_.stop();
    port_.close();
    if (capture_.isOpen()) {
        if (!capture_.flush()) {
            status_ = "error";
            if (!error_.isEmpty()) error_ += "; ";
            error_ += "Error al finalizar captura: " + capture_.errorString();
        }
        capture_.close();
    }
    stats();
    emit message(snapshot());
    finishing_ = false;
}

// Normal Dock keypad PTT, never hardware-mode GPIO/register writes.
bool SerialSource::writePttKey(bool pressed) {
    const auto frame = qdock::experimental::makeKeyPressFrame(pressed ? 16 : 19);
    return port_.isOpen() && port_.write(reinterpret_cast<const char*>(frame.data()),
                                        frame.size()) == qint64(frame.size());
}

QString SerialSource::requestPtt(QObject* owner, const QString& action, const QString& id) {
    if (!txControlAvailable()) return QStringLiteral("ptt_not_enabled");
    if (id.isEmpty() || id.size() > 64) return QStringLiteral("invalid_ptt_id");
    if (action == "release" || action == "keepalive") {
        if (pttOwner_ != owner || pttId_ != id) return QStringLiteral("ptt_not_owner");
        // A delayed heartbeat cannot revive an expired lease.
        if (pttLease_.elapsed() >= 1500 || pttDuration_.elapsed() >= pttMaxSeconds_ * 1000) {
            endPtt(pttDuration_.elapsed() >= pttMaxSeconds_ * 1000
                       ? "max_duration" : "lease_expired");
            return QStringLiteral("ptt_expired");
        }
        if (action == "release") endPtt("released");
        else pttLease_.restart();
        return {};
    }
    if (action != "press") return QStringLiteral("invalid_ptt_action");
    if (pttOwner_) return QStringLiteral("ptt_busy");
    if (frequencyBusy_ || vfoBusy_ || eepromBusy_ || port_.bytesToWrite() != 0)
        return QStringLiteral("radio_control_busy");
    if (transmitting_) return QStringLiteral("radio_already_transmitting");
    if (!radioStateAge_.isValid() || radioStateAge_.elapsed() > 5000)
        return QStringLiteral("radio_state_stale");
    pttOwner_ = owner;
    pttId_ = id;
    pttLease_.start();
    pttDuration_.start();
    if (!writePttKey(true) || !pttOwner_) {
        finish("error", "ptt_serial_write_failed");
        return QStringLiteral("ptt_serial_write_failed");
    }
    pttTimer_.start();
    emit message({{"message", "ptt_state"}, {"active", true}, {"id", id},
                  {"reason", "pressed"}});
    return {};
}

void SerialSource::releasePtt(QObject* owner, const QString& reason) {
    if (pttOwner_ == owner) endPtt(reason);
}

void SerialSource::endPtt(const QString& reason) {
    pttTimer_.stop();
    if (!pttOwner_) return;
    const QString id = pttId_;
    pttOwner_ = nullptr; // Clear before serial operations, which may signal errors.
    pttId_.clear();
    bool sent = writePttKey(false);
    // Drain the release before closing the serial descriptor on shutdown.
    if (sent && port_.bytesToWrite() > 0)
        sent = port_.waitForBytesWritten(200) && port_.bytesToWrite() == 0;
    emit message({{"message", "ptt_state"}, {"active", false}, {"id", id},
                  {"reason", sent ? reason : QStringLiteral("release_write_failed")}});
    if (!sent && !finishing_) finish("error", "ptt_release_write_failed");
}
