#include "radiocontroller.h"
#include <QCoreApplication>
#include <QSettings>
#include <QTemporaryDir>
#include <QDebug>
#include <cstdlib>

static void require(bool condition, const char *message)
{
    if (!condition) {
        qCritical() << message;
        std::exit(1);
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir settingsDirectory;
    require(settingsDirectory.isValid(), "Temporary settings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDirectory.path());
    app.setOrganizationName("IcomTests");
    app.setApplicationName("LanReceiver");
    QSettings().setValue("connection/autoConnect", false);
    RadioController radio;
    QList<QByteArray> writes;
    radio.setLanReceiverWriter([&writes](const QByteArray &payload, const QString &) {
        writes.append(payload);
        return true;
    });
    radio.setPreamp(2);
    radio.setAttenuatorEnabled(true);
    radio.setAgc(3);
    radio.setNoiseBlankerEnabled(true);
    radio.setNoiseReductionEnabled(true);
    radio.setAutoNotchEnabled(true);
    radio.setManualNotchEnabled(true);
    radio.setIpPlusEnabled(true);
    radio.setFilterShape(1);
    QList<QByteArray> expected{
        QByteArray::fromHex("160202"), QByteArray::fromHex("1120"),
        QByteArray::fromHex("161203"), QByteArray::fromHex("162201"),
        QByteArray::fromHex("164001"), QByteArray::fromHex("164101"),
        QByteArray::fromHex("164801"), QByteArray::fromHex("166501")};
    expected.append(QByteArray::fromHex("165601"));
    require(writes == expected, "Reception buttons must use LAN without an open serial port");
    radio.setAfGain(100);
    radio.setRfGain(0);
    radio.setSquelch(100);
    radio.setNoiseBlankerLevel(100);
    radio.setNoiseReductionLevel(100);
    radio.setManualNotchPosition(100);
    require(writes.size() == 15, "All six reception sliders must use LAN");
    require(writes.at(9) == QByteArray::fromHex("14010255"), "AF level BCD encoding");
    require(writes.at(10) == QByteArray::fromHex("14020000"), "RF zero level encoding");
    require(radio.preamp() == 0, "No optimistic state before a radio reply");
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefe94e0160202fd"));
    require(radio.preamp() == 0, "Ignore command echoes");
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefee094160202fd"));
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefe00941120fd"));
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefee094161203fd"));
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefee09415020078fd"));
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefee09425010000 00 00 12 34 fd"));
    require(radio.preamp() == 2, "Decode preamp response");
    require(radio.attenuatorEnabled(), "Decode broadcast attenuator response");
    require(radio.agc() == 3, "Decode AGC response");
    require(radio.sMeterPercent() > 0, "Decode LAN S-meter response");
    require(radio.vfoBFrequencyHz() > 0, "Decode LAN VFO B frequency response");
    for (int filter = 1; filter <= 3; ++filter) {
        QByteArray reply = QByteArray::fromHex("fefee0942600010101fd");
        reply[8] = char(filter);
        radio.receiveLanReceiverFrame(reply);
        require(radio.filterText() == QStringLiteral("FIL%1").arg(filter),
                "LAN filter reply must update the property used by button highlighting");
        require(radio.dataMode(), "Filter readback must retain the received DATA state");
    }
    radio.receiveLanReceiverFrame(QByteArray::fromHex("fefee0941602fd"));
    require(radio.preamp() == 2, "Ignore incomplete response");
    radio.setRfPower(30);
    require(writes.size() == 15, "Unimplemented controls must not enter the reception transport");
    radio.setLanReceiverWriter({});
    radio.setPreamp(1);
    require(writes.size() == 15, "Disconnect must disable LAN routing");
    qInfo() << "LAN receiver routing and readback tests passed";
}
