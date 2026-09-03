#include "radiocontroller.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QRegularExpression>
#include <QSettings>
#include <QSerialPortInfo>
#include <QVariantMap>

#include <algorithm>
#include <cmath>

namespace
{
QString stableIcomByIdPath(const QString &interfaceSuffix)
{
#ifdef Q_OS_LINUX
    const QDir byIdDir(QStringLiteral("/dev/serial/by-id"));
    if (!byIdDir.exists()) {
        return QString();
    }

    const QFileInfoList entries = byIdDir.entryInfoList(
        QDir::Files | QDir::System | QDir::NoDotAndDotDot,
        QDir::Name
    );

    for (const QFileInfo &entry : entries) {
        const QString name = entry.fileName();
        if (!name.contains(QStringLiteral("Icom"), Qt::CaseInsensitive)
            || !name.contains(QStringLiteral("7300MK2"), Qt::CaseInsensitive)
            || !name.endsWith(interfaceSuffix, Qt::CaseInsensitive)) {
            continue;
        }

        const QString path = entry.absoluteFilePath();
        if (QFileInfo::exists(path)) {
            return path;
        }
    }
#else
    Q_UNUSED(interfaceSuffix);
#endif

    return QString();
}

QString linuxUsbInterfaceNumber(const QSerialPortInfo &info)
{
#ifdef Q_OS_LINUX
    const QString portName = info.portName();
    if (portName.isEmpty()) {
        return QString();
    }

    const QFileInfo deviceLink(
        QStringLiteral("/sys/class/tty/%1/device").arg(portName)
    );
    const QString devicePath = deviceLink.canonicalFilePath();
    if (devicePath.isEmpty()) {
        return QString();
    }

    QDir deviceDir(devicePath);
    if (!deviceDir.cdUp() || !deviceDir.cdUp()) {
        return QString();
    }

    QFile interfaceFile(deviceDir.filePath(QStringLiteral("bInterfaceNumber")));
    if (!interfaceFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }

    return QString::fromLatin1(interfaceFile.readAll()).trimmed();
#else
    Q_UNUSED(info);
    return QString();
#endif
}

bool looksLikeIcom7300Mk2(const QSerialPortInfo &info)
{
    const QString searchable = QStringLiteral("%1 %2 %3 %4")
        .arg(
            info.manufacturer(),
            info.description(),
            info.serialNumber(),
            info.systemLocation()
        );

    return searchable.contains(QStringLiteral("Icom"), Qt::CaseInsensitive)
        || searchable.contains(QStringLiteral("7300MK2"), Qt::CaseInsensitive);
}

bool isBcdByte(quint8 value)
{
    return (value & 0x0F) <= 9 && ((value >> 4) & 0x0F) <= 9;
}

int bcdByteToInt(quint8 value)
{
    return int((value >> 4) & 0x0F) * 10 + int(value & 0x0F);
}

QString tuningStepName(int code)
{
    switch (code) {
    case 0x01: return QStringLiteral("0,1 kHz");
    case 0x02: return QStringLiteral("1 kHz");
    case 0x03: return QStringLiteral("5 kHz");
    case 0x04: return QStringLiteral("9 kHz");
    case 0x05: return QStringLiteral("10 kHz");
    case 0x06: return QStringLiteral("12,5 kHz");
    case 0x07: return QStringLiteral("20 kHz");
    case 0x08: return QStringLiteral("25 kHz");
    default: return QStringLiteral("OFF · 1/10 Hz");
    }
}

QString txFilterWidthName(int width)
{
    switch (width) {
    case 1: return QStringLiteral("MID");
    case 2: return QStringLiteral("NAR");
    default: return QStringLiteral("WIDE");
    }
}

QString apfModeName(int mode)
{
    switch (mode) {
    case 1: return QStringLiteral("WIDE");
    case 2: return QStringLiteral("MID");
    case 3: return QStringLiteral("NAR");
    default: return QStringLiteral("OFF");
    }
}

QString breakInModeName(int mode)
{
    switch (mode) {
    case 1: return QStringLiteral("SEMI");
    case 2: return QStringLiteral("FULL");
    default: return QStringLiteral("OFF");
    }
}

QString keyTypeName(int type)
{
    switch (type) {
    case 0: return QStringLiteral("STRAIGHT");
    case 1: return QStringLiteral("BUG");
    default: return QStringLiteral("PADDLE");
    }
}

QString rttyMarkName(int code)
{
    switch (code) {
    case 0: return QStringLiteral("1275 Hz");
    case 1: return QStringLiteral("1615 Hz");
    default: return QStringLiteral("2125 Hz");
    }
}

QString rttyShiftName(int code)
{
    switch (code) {
    case 1: return QStringLiteral("200 Hz");
    case 2: return QStringLiteral("425 Hz");
    default: return QStringLiteral("170 Hz");
    }
}

QString toneFrequencyName(int tenthsHz)
{
    tenthsHz = std::clamp(tenthsHz, 0, 2999);
    return QLocale(QLocale::Spanish)
        .toString(tenthsHz / 10.0, 'f', 1)
        + QStringLiteral(" Hz");
}

QString bandStackingName(int code)
{
    switch (code) {
    case 1: return QStringLiteral("1.8 MHz");
    case 2: return QStringLiteral("3.5 MHz");
    case 3: return QStringLiteral("7 MHz");
    case 4: return QStringLiteral("10 MHz");
    case 5: return QStringLiteral("14 MHz");
    case 6: return QStringLiteral("18 MHz");
    case 7: return QStringLiteral("21 MHz");
    case 8: return QStringLiteral("24 MHz");
    case 9: return QStringLiteral("28 MHz");
    case 10: return QStringLiteral("50 MHz");
    default: return QStringLiteral("GENE");
    }
}
}

RadioController::RadioController(QObject *parent)
    : QObject(parent)
{
    for (int channel = 0; channel < 8; ++channel) {
        m_keyerMemories.append(QString());
    }

    m_memories.resize(99);
    m_bandStackingRegisters.resize(33);

    loadConnectionSettings();

    m_txSafetyTimeoutSeconds = std::clamp(
        QSettings().value(QStringLiteral("tx/safetyTimeoutSeconds"), 180).toInt(),
        5, 3600);

    m_pollTimer.setInterval(m_pollIntervalMs);
    m_pollTimer.setTimerType(Qt::PreciseTimer);

    m_responseTimer.setSingleShot(true);
    m_responseTimer.setInterval(m_responseTimeoutMs);

    m_reconnectTimer.setSingleShot(true);
    m_reconnectTimer.setInterval(3000);
    m_txSafetyTimer.setSingleShot(true);
    m_txSafetyTimer.setInterval(m_txSafetyTimeoutSeconds * 1000);

    connect(&m_pollTimer, &QTimer::timeout,
            this, &RadioController::pollNextValue);
    connect(&m_responseTimer, &QTimer::timeout,
            this, &RadioController::onResponseTimeout);
    connect(&m_reconnectTimer, &QTimer::timeout,
            this, &RadioController::connectRadio);
    connect(&m_txSafetyTimer, &QTimer::timeout, this, [this]() {
        if (!m_pttOwned) return;
        forceReceive();
        setActionStatus(QStringLiteral(
            "TX desactivado por tiempo máximo de seguridad (%1 s)"
        ).arg(m_txSafetyTimeoutSeconds));
    });
    connect(&m_serial, &QSerialPort::readyRead,
            this, &RadioController::onReadyRead);
    connect(&m_serial, &QSerialPort::errorOccurred,
            this, &RadioController::onSerialError);

    const bool lanPreferred = QSettings().value(QStringLiteral("lan/enabled"), false).toBool();
    if (m_autoConnectEnabled && !lanPreferred) {
        QTimer::singleShot(
            300,
            this,
            &RadioController::connectRadio
        );
    } else if (lanPreferred) {
        setStatus(QStringLiteral("LAN seleccionada: conexión USB desactivada temporalmente"));
    } else {
        setStatus(
            QStringLiteral(
                "Conexión automática desactivada"
            )
        );
    }
}

RadioController::~RadioController()
{
    shutdown();
}

int RadioController::txSafetyTimeoutSeconds() const
{
    return m_txSafetyTimeoutSeconds;
}

void RadioController::setTxSafetyTimeoutSeconds(int seconds)
{
    seconds = std::clamp(seconds, 5, 3600);
    if (seconds == m_txSafetyTimeoutSeconds) return;
    m_txSafetyTimeoutSeconds = seconds;
    m_txSafetyTimer.setInterval(seconds * 1000);
    QSettings().setValue(QStringLiteral("tx/safetyTimeoutSeconds"), seconds);
    if (m_pttOwned) m_txSafetyTimer.start();
    emit txSafetySettingsChanged();
}

bool RadioController::connected() const { return m_serial.isOpen(); }
bool RadioController::transmitting() const { return m_transmitting; }
bool RadioController::pttOwned() const { return m_pttOwned; }
bool RadioController::dataMode() const { return m_dataMode; }
bool RadioController::busy() const { return m_busy; }
bool RadioController::memoryReadActive() const
{
    return m_memoryReadBatchActive;
}
bool RadioController::splitEnabled() const { return m_splitEnabled; }
bool RadioController::ritEnabled() const { return m_ritEnabled; }
bool RadioController::deltaTxEnabled() const { return m_deltaTxEnabled; }
bool RadioController::attenuatorEnabled() const { return m_attenuatorEnabled; }
bool RadioController::tunerEnabled() const { return m_tunerState == 1; }
bool RadioController::noiseBlankerEnabled() const { return m_noiseBlankerEnabled; }
bool RadioController::noiseReductionEnabled() const { return m_noiseReductionEnabled; }
bool RadioController::autoNotchEnabled() const { return m_autoNotchEnabled; }
bool RadioController::manualNotchEnabled() const { return m_manualNotchEnabled; }
bool RadioController::ipPlusEnabled() const { return m_ipPlusEnabled; }

bool RadioController::squelchOpen() const { return m_squelchOpen; }
bool RadioController::basicSquelchOpen() const { return m_basicSquelchOpen; }
QString RadioController::squelchStateText() const
{
    return m_squelchOpen ? QStringLiteral("BUSY")
                         : QStringLiteral("SQL");
}

int RadioController::radioTuningStepCode() const
{
    return m_radioTuningStepCode;
}

QString RadioController::radioTuningStepText() const
{
    return tuningStepName(m_radioTuningStepCode);
}

bool RadioController::xfcEnabled() const { return m_xfcEnabled; }
bool RadioController::civOutputEnabled() const { return m_civOutputEnabled; }

qulonglong RadioController::txFrequencyHz() const
{
    return m_txFrequencyHz;
}

QString RadioController::txFrequencyText() const
{
    return m_txFrequencyText;
}

int RadioController::txBandCount() const
{
    return m_txBandCount < 0 ? 0 : m_txBandCount;
}

QVariantList RadioController::txBandEdges() const
{
    QVariantList result;

    for (const TxBandEdge &edge : m_txBandEdges) {
        QVariantMap item;
        item.insert(QStringLiteral("number"), edge.number);
        item.insert(QStringLiteral("lowerHz"),
                    QVariant::fromValue<qulonglong>(edge.lowerHz));
        item.insert(QStringLiteral("upperHz"),
                    QVariant::fromValue<qulonglong>(edge.upperHz));
        item.insert(
            QStringLiteral("text"),
            QStringLiteral("%1. %2 – %3")
                .arg(edge.number)
                .arg(formatFrequencyMhz(edge.lowerHz))
                .arg(formatFrequencyMhz(edge.upperHz))
        );
        result.append(item);
    }

    return result;
}

QString RadioController::txBandEdgesText() const
{
    if (m_txBandCount < 0) {
        return QStringLiteral("Sin consultar");
    }

    if (m_txBandEdges.isEmpty()) {
        return m_txBandCount == 0
                   ? QStringLiteral("La radio no devolvió bandas TX")
                   : QStringLiteral("Leyendo límites…");
    }

    QStringList lines;
    for (const TxBandEdge &edge : m_txBandEdges) {
        lines.append(
            QStringLiteral("%1. %2 – %3")
                .arg(edge.number)
                .arg(formatFrequencyMhz(edge.lowerHz))
                .arg(formatFrequencyMhz(edge.upperHz))
        );
    }
    return lines.join(QLatin1Char('\n'));
}

bool RadioController::txBandEdgesLoaded() const
{
    return m_txBandCount >= 0
           && m_txBandEdges.size() >= m_txBandCount;
}

int RadioController::microphoneGain() const { return m_microphoneGain; }
int RadioController::speechCompressorLevel() const
{
    return m_speechCompressorLevel;
}
int RadioController::monitorLevel() const { return m_monitorLevel; }
int RadioController::voxGain() const { return m_voxGain; }
int RadioController::antiVoxGain() const { return m_antiVoxGain; }

bool RadioController::speechCompressorEnabled() const
{
    return m_speechCompressorEnabled;
}
bool RadioController::monitorEnabled() const { return m_monitorEnabled; }
bool RadioController::voxEnabled() const { return m_voxEnabled; }
bool RadioController::txInhibitEnabled() const
{
    return m_txInhibitEnabled;
}

int RadioController::txFilterWidth() const { return m_txFilterWidth; }
QString RadioController::txFilterWidthText() const
{
    return txFilterWidthName(m_txFilterWidth);
}

bool RadioController::cwModeActive() const
{
    return m_modeCode == 0x03 || m_modeCode == 0x07;
}

int RadioController::cwApfPeakOffsetHz() const
{
    return m_cwApfPeakOffsetHz;
}

int RadioController::cwPitchHz() const
{
    return m_cwPitchHz;
}

int RadioController::cwKeySpeedWpm() const
{
    return m_cwKeySpeedWpm;
}

int RadioController::cwBreakInDelayTenths() const
{
    return m_cwBreakInDelayTenths;
}

int RadioController::apfMode() const
{
    return m_apfMode;
}

QString RadioController::apfModeText() const
{
    return apfModeName(m_apfMode);
}

int RadioController::breakInMode() const
{
    return m_breakInMode;
}

QString RadioController::breakInModeText() const
{
    return breakInModeName(m_breakInMode);
}

int RadioController::sideToneLevel() const
{
    return m_sideToneLevel;
}

bool RadioController::sideToneLimitEnabled() const
{
    return m_sideToneLimitEnabled;
}

int RadioController::keyerRepeatSeconds() const
{
    return m_keyerRepeatSeconds;
}

int RadioController::dotDashRatioTenths() const
{
    return m_dotDashRatioTenths;
}

int RadioController::riseTimeMs() const
{
    return m_riseTimeMs;
}

bool RadioController::paddleReversed() const
{
    return m_paddleReversed;
}

int RadioController::keyType() const
{
    return m_keyType;
}

QString RadioController::keyTypeText() const
{
    return keyTypeName(m_keyType);
}

bool RadioController::micUpDownKeyerEnabled() const
{
    return m_micUpDownKeyerEnabled;
}

bool RadioController::cwDecodeDisplayEnabled() const
{
    return m_cwDecodeDisplayEnabled;
}

QVariantList RadioController::keyerMemories() const
{
    QVariantList result;

    for (int index = 0; index < m_keyerMemories.size(); ++index) {
        QVariantMap item;
        item.insert(QStringLiteral("channel"), index + 1);
        item.insert(QStringLiteral("name"),
                    QStringLiteral("M%1").arg(index + 1));
        item.insert(QStringLiteral("text"), m_keyerMemories.at(index));
        result.append(item);
    }

    return result;
}

bool RadioController::fmModeActive() const
{
    return m_modeCode == 0x05;
}

bool RadioController::rttyModeActive() const
{
    return m_modeCode == 0x04 || m_modeCode == 0x08;
}

bool RadioController::repeaterToneEnabled() const
{
    return m_repeaterToneEnabled;
}

bool RadioController::toneSquelchEnabled() const
{
    return m_toneSquelchEnabled;
}

int RadioController::repeaterToneTenthsHz() const
{
    return m_repeaterToneTenthsHz;
}

int RadioController::toneSquelchTenthsHz() const
{
    return m_toneSquelchTenthsHz;
}

QString RadioController::repeaterToneText() const
{
    return toneFrequencyName(m_repeaterToneTenthsHz);
}

QString RadioController::toneSquelchText() const
{
    return toneFrequencyName(m_toneSquelchTenthsHz);
}

bool RadioController::twinPeakEnabled() const
{
    return m_twinPeakEnabled;
}

bool RadioController::twinPeakAvailable() const
{
    return m_rttyMarkFrequencyCode == 2
           && m_rttyShiftWidthCode == 0;
}

int RadioController::rttyMarkFrequencyCode() const
{
    return m_rttyMarkFrequencyCode;
}

QString RadioController::rttyMarkFrequencyText() const
{
    return rttyMarkName(m_rttyMarkFrequencyCode);
}

int RadioController::rttyShiftWidthCode() const
{
    return m_rttyShiftWidthCode;
}

QString RadioController::rttyShiftWidthText() const
{
    return rttyShiftName(m_rttyShiftWidthCode);
}

bool RadioController::rttyKeyingReverse() const
{
    return m_rttyKeyingReverse;
}

bool RadioController::memoryModeActive() const
{
    return m_memoryModeActive;
}

int RadioController::selectedMemoryChannel() const
{
    return m_selectedMemoryChannel;
}

QString RadioController::selectedMemoryChannelText() const
{
    return QStringLiteral("M%1")
        .arg(m_selectedMemoryChannel, 2, 10, QLatin1Char('0'));
}

bool RadioController::memoryReturnAvailable() const
{
    return m_memoryVfoSnapshot.valid;
}

QString RadioController::memoryReturnVfoText() const
{
    if (!m_memoryVfoSnapshot.valid) {
        return QStringLiteral("VFO");
    }

    return m_memoryVfoSnapshot.selectedVfo == 1
           ? QStringLiteral("VFO B")
           : QStringLiteral("VFO A");
}

QVariantMap RadioController::buildMemoryRow(
    int channel
) const
{
    QVariantMap row;

    if (channel < 1 || channel > m_memories.size()) {
        return row;
    }

    const MemoryState &memory =
        m_memories.at(channel - 1);

    row.insert(QStringLiteral("channel"), channel);
    row.insert(
        QStringLiteral("channelText"),
        QStringLiteral("M%1")
            .arg(channel, 2, 10, QLatin1Char('0'))
    );
    row.insert(QStringLiteral("loaded"), memory.loaded);
    row.insert(QStringLiteral("blank"), memory.blank);
    row.insert(QStringLiteral("name"), memory.name);
    row.insert(
        QStringLiteral("frequencyHz"),
        QVariant::fromValue<qulonglong>(
            memory.receiveFrequencyHz
        )
    );
    row.insert(
        QStringLiteral("frequencyText"),
        memory.loaded && !memory.blank
            ? formatFrequencyMhz(memory.receiveFrequencyHz)
            : QStringLiteral("—")
    );
    row.insert(
        QStringLiteral("transmitFrequencyHz"),
        QVariant::fromValue<qulonglong>(
            memory.transmitFrequencyHz
        )
    );
    row.insert(
        QStringLiteral("transmitFrequencyText"),
        memory.loaded && !memory.blank
            ? formatFrequencyMhz(memory.transmitFrequencyHz)
            : QStringLiteral("—")
    );

    const qint64 repeaterOffsetHz =
        qint64(memory.transmitFrequencyHz)
        - qint64(memory.receiveFrequencyHz);
    const qint64 absoluteOffsetHz =
        repeaterOffsetHz >= 0
        ? repeaterOffsetHz
        : -repeaterOffsetHz;

    QString repeaterOffsetText =
        QStringLiteral("SIMPLEX");
    QString duplexText =
        QStringLiteral("SIMPLEX");

    if (memory.loaded
        && !memory.blank
        && repeaterOffsetHz != 0) {
        QString value =
            QString::number(
                double(absoluteOffsetHz)
                    / 1'000'000.0,
                'f',
                3
            );
        value.replace(
            QLatin1Char('.'),
            QLatin1Char(',')
        );

        const QString sign =
            repeaterOffsetHz > 0
            ? QStringLiteral("+")
            : QStringLiteral("-");

        repeaterOffsetText =
            sign
            + value
            + QStringLiteral(" MHz");

        duplexText =
            memory.split
            ? QStringLiteral("SPLIT ")
                  + repeaterOffsetText
            : QStringLiteral("DUP ")
                  + repeaterOffsetText;
    }

    row.insert(
        QStringLiteral("repeaterOffsetHz"),
        QVariant::fromValue<qlonglong>(
            repeaterOffsetHz
        )
    );
    row.insert(
        QStringLiteral("repeaterOffsetText"),
        repeaterOffsetText
    );
    row.insert(
        QStringLiteral("duplexText"),
        duplexText
    );

    row.insert(
        QStringLiteral("modeCode"),
        int(memory.receiveMode)
    );
    row.insert(
        QStringLiteral("modeText"),
        memory.loaded && !memory.blank
            ? modeName(memory.receiveMode)
            : QStringLiteral("—")
    );
    row.insert(
        QStringLiteral("filterCode"),
        int(memory.receiveFilter)
    );
    row.insert(
        QStringLiteral("filterText"),
        memory.loaded && !memory.blank
            ? filterName(memory.receiveFilter)
            : QStringLiteral("—")
    );
    row.insert(
        QStringLiteral("transmitModeCode"),
        int(memory.transmitMode)
    );
    row.insert(
        QStringLiteral("transmitModeText"),
        memory.loaded && !memory.blank
            ? modeName(memory.transmitMode)
            : QStringLiteral("—")
    );
    row.insert(
        QStringLiteral("transmitFilterCode"),
        int(memory.transmitFilter)
    );
    row.insert(
        QStringLiteral("transmitFilterText"),
        memory.loaded && !memory.blank
            ? filterName(memory.transmitFilter)
            : QStringLiteral("—")
    );
    row.insert(
        QStringLiteral("dataMode"),
        memory.receiveDataMode
    );
    row.insert(
        QStringLiteral("transmitDataMode"),
        memory.transmitDataMode
    );
    row.insert(QStringLiteral("split"), memory.split);
    row.insert(
        QStringLiteral("selectGroup"),
        memory.selectGroup
    );
    row.insert(
        QStringLiteral("selectText"),
        memory.selectGroup > 0
            ? QStringLiteral("SEL%1")
                  .arg(memory.selectGroup)
            : QStringLiteral("—")
    );
    row.insert(
        QStringLiteral("toneType"),
        memory.toneType
    );
    row.insert(
        QStringLiteral("toneTypeText"),
        memory.toneType == 1
            ? QStringLiteral("TONE")
            : memory.toneType == 2
              ? QStringLiteral("TSQL")
              : QStringLiteral("OFF")
    );
    row.insert(
        QStringLiteral("transmitToneType"),
        memory.transmitToneType
    );
    row.insert(
        QStringLiteral("transmitToneTypeText"),
        memory.transmitToneType == 1
            ? QStringLiteral("TONE")
            : memory.transmitToneType == 2
              ? QStringLiteral("TSQL")
              : QStringLiteral("OFF")
    );
    row.insert(
        QStringLiteral("repeaterToneTenthsHz"),
        memory.repeaterToneTenthsHz
    );
    row.insert(
        QStringLiteral("repeaterToneText"),
        toneFrequencyName(
            memory.repeaterToneTenthsHz
        )
    );
    row.insert(
        QStringLiteral("toneSquelchTenthsHz"),
        memory.toneSquelchTenthsHz
    );
    row.insert(
        QStringLiteral("toneSquelchText"),
        toneFrequencyName(
            memory.toneSquelchTenthsHz
        )
    );

    return row;
}

QVariantMap RadioController::memoryRow(
    int channel
) const
{
    return buildMemoryRow(channel);
}

QVariantList RadioController::memoryRows() const
{
    QVariantList rows;
    rows.reserve(m_memories.size());

    for (int channel = 1;
         channel <= m_memories.size();
         ++channel) {
        rows.append(buildMemoryRow(channel));
    }

    return rows;
}

int RadioController::memoriesRevision() const
{
    return m_memoriesRevision;
}

void RadioController::markMemoriesChanged()
{
    ++m_memoriesRevision;
    emit memoriesChanged();
}

bool RadioController::scanActive() const
{
    return m_scanActive;
}

QString RadioController::scanTypeText() const
{
    switch (m_scanSubcommand) {
    case 0x01: return QStringLiteral("AUTO");
    case 0x02: return QStringLiteral("PROGRAM");
    case 0x03: return QStringLiteral("ΔF");
    case 0x12: return QStringLiteral("FINE PROGRAM");
    case 0x13: return QStringLiteral("FINE ΔF");
    case 0x22: return QStringLiteral("MEMORY");
    case 0x23: return QStringLiteral("SELECT MEMORY");
    default: return QStringLiteral("DETENIDO");
    }
}

bool RadioController::scanSpeedFast() const
{
    return m_scanSpeedFast;
}

bool RadioController::scanResumeEnabled() const
{
    return m_scanResumeEnabled;
}

int RadioController::scanSelectGroup() const
{
    return m_scanSelectGroup;
}

int RadioController::deltaScanSpanCode() const
{
    return m_deltaScanSpanCode;
}

QString RadioController::deltaScanSpanText() const
{
    switch (m_deltaScanSpanCode) {
    case 2: return QStringLiteral("±10 kHz");
    case 3: return QStringLiteral("±20 kHz");
    case 4: return QStringLiteral("±50 kHz");
    case 5: return QStringLiteral("±100 kHz");
    case 6: return QStringLiteral("±500 kHz");
    case 7: return QStringLiteral("±1 MHz");
    default: return QStringLiteral("±5 kHz");
    }
}

QVariantList RadioController::bandStackingRows() const
{
    QVariantList rows;
    rows.reserve(m_bandStackingRegisters.size());

    for (int bandCode = 1; bandCode <= 11; ++bandCode) {
        for (int registerCode = 1;
             registerCode <= 3;
             ++registerCode) {
            const int index =
                (bandCode - 1) * 3 + (registerCode - 1);
            const BandStackingState &state =
                m_bandStackingRegisters.at(index);

            QVariantMap row;
            row.insert(QStringLiteral("bandCode"), bandCode);
            row.insert(QStringLiteral("bandText"),
                       bandStackingName(bandCode));
            row.insert(QStringLiteral("registerCode"), registerCode);
            row.insert(QStringLiteral("loaded"), state.loaded);
            row.insert(
                QStringLiteral("frequencyText"),
                state.loaded
                    ? formatFrequencyMhz(state.frequencyHz)
                    : QStringLiteral("—")
            );
            row.insert(
                QStringLiteral("modeText"),
                state.loaded
                    ? modeName(state.mode)
                    : QStringLiteral("—")
            );
            row.insert(
                QStringLiteral("filterText"),
                state.loaded
                    ? filterName(state.filter)
                    : QStringLiteral("—")
            );
            row.insert(QStringLiteral("dataMode"), state.dataMode);
            row.insert(QStringLiteral("toneType"), state.toneType);
            rows.append(row);
        }
    }

    return rows;
}

QString RadioController::status() const { return m_status; }
QString RadioController::actionStatus() const { return m_actionStatus; }
QString RadioController::portName() const { return m_portName; }

QStringList RadioController::serialPortChoices() const
{
    QStringList choices;
    choices.append(QStringLiteral("AUTO"));

    const auto ports = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo &info : ports) {
        const QString path = info.systemLocation();

        if (!path.isEmpty() && !choices.contains(path)) {
            choices.append(path);
        }
    }

    if (!m_configuredPort.isEmpty()
        && !choices.contains(m_configuredPort)) {
        choices.append(m_configuredPort);
    }

    return choices;
}

QString RadioController::configuredPort() const
{
    return m_configuredPort;
}

int RadioController::configuredBaudRate() const
{
    return m_configuredBaudRate;
}

int RadioController::civRadioAddress() const
{
    return int(m_radioAddress);
}

int RadioController::civControllerAddress() const
{
    return int(m_controllerAddress);
}

bool RadioController::autoConnectEnabled() const
{
    return m_autoConnectEnabled;
}

bool RadioController::autoReconnectEnabled() const
{
    return m_autoReconnectEnabled;
}

void RadioController::setAutoConnectPreference(bool enabled)
{
    m_autoConnectEnabled = enabled;
    QSettings().setValue(QStringLiteral("connection/autoConnect"), enabled);
    emit connectionSettingsChanged();
}

void RadioController::setAutoReconnectPreference(bool enabled)
{
    m_autoReconnectEnabled = enabled;
    QSettings().setValue(QStringLiteral("connection/autoReconnect"), enabled);
    emit connectionSettingsChanged();
}

int RadioController::pollIntervalMs() const
{
    return m_pollIntervalMs;
}

int RadioController::responseTimeoutMs() const
{
    return m_responseTimeoutMs;
}

QString RadioController::usbInterfacesText() const
{
    QStringList lines;

    const QString usbAPath = stableIcomByIdPath(QStringLiteral("-if00"));
    const QString usbBPath = stableIcomByIdPath(QStringLiteral("-if02"));

    lines.append(
        QStringLiteral("USB (A) / if00 · %1")
            .arg(
                !usbAPath.isEmpty()
                ? QStringLiteral("DETECTADA")
                : QStringLiteral("NO DETECTADA")
            )
    );
    lines.append(
        QStringLiteral("  %1")
            .arg(
                !usbAPath.isEmpty()
                ? usbAPath
                : QStringLiteral("Enlace estable /dev/serial/by-id no localizado")
            )
    );
    lines.append(
        QStringLiteral(
            "  Uso previsto: aplicación digital / audio / DECODIUM"
        )
    );
    lines.append(QString());

    lines.append(
        QStringLiteral("USB (B) / if02 · %1")
            .arg(
                !usbBPath.isEmpty()
                ? QStringLiteral("DETECTADA")
                : QStringLiteral("NO DETECTADA")
            )
    );
    lines.append(
        QStringLiteral("  %1")
            .arg(
                !usbBPath.isEmpty()
                ? usbBPath
                : QStringLiteral("Enlace estable /dev/serial/by-id no localizado")
            )
    );
    lines.append(
        QStringLiteral(
            "  Uso previsto: control CI-V de esta aplicación"
        )
    );
    lines.append(QString());
    lines.append(QStringLiteral("Puertos serie detectados:"));

    const auto ports = QSerialPortInfo::availablePorts();
    if (ports.isEmpty()) {
        lines.append(QStringLiteral("  Ninguno"));
    } else {
        for (const QSerialPortInfo &info : ports) {
            QString details =
                QStringLiteral("  %1")
                    .arg(info.systemLocation());

            const QString description =
                info.description().trimmed();
            const QString manufacturer =
                info.manufacturer().trimmed();

            if (!description.isEmpty()) {
                details +=
                    QStringLiteral(" · %1")
                        .arg(description);
            }

            if (!manufacturer.isEmpty()) {
                details +=
                    QStringLiteral(" · %1")
                        .arg(manufacturer);
            }

            lines.append(details);
        }
    }

    return lines.join(QLatin1Char('\n'));
}

QString RadioController::connectionSettingsSummary() const
{
    const QString port =
        m_configuredPort.isEmpty()
        ? QStringLiteral("AUTO / USB (B)")
        : m_configuredPort;

    return QStringLiteral(
        "%1 · %2 baudios · radio %3h · controlador %4h · "
        "poll %5 ms · timeout %6 ms"
    )
        .arg(port)
        .arg(m_configuredBaudRate)
        .arg(
            int(m_radioAddress),
            2,
            16,
            QLatin1Char('0')
        )
        .arg(
            int(m_controllerAddress),
            2,
            16,
            QLatin1Char('0')
        )
        .arg(m_pollIntervalMs)
        .arg(m_responseTimeoutMs)
        .toUpper();
}

bool RadioController::scopeRunning() const
{
    return m_scopeRunning;
}

QVariantList RadioController::scopeSpectrumData() const
{
    return m_scopeSpectrumData;
}

int RadioController::scopeFrameCounter() const
{
    return m_scopeFrameCounter;
}

int RadioController::scopeMode() const
{
    return m_scopeMode;
}

QString RadioController::scopeModeText() const
{
    switch (m_scopeMode) {
    case 1:
        return QStringLiteral("FIXED");
    case 2:
        return QStringLiteral("SCROLL-C");
    case 3:
        return QStringLiteral("SCROLL-F");
    default:
        return QStringLiteral("CENTER");
    }
}

qulonglong RadioController::scopeCenterFrequencyHz() const
{
    return m_scopeCenterFrequencyHz;
}

qulonglong RadioController::scopeLowerFrequencyHz() const
{
    return m_scopeLowerFrequencyHz;
}

qulonglong RadioController::scopeHigherFrequencyHz() const
{
    return m_scopeHigherFrequencyHz;
}

qulonglong RadioController::scopeSpanHz() const
{
    return m_scopeSpanHz;
}

QString RadioController::scopeSpanText() const
{
    if (m_scopeSpanHz >= 1'000'000) {
        return QLocale(
            QLocale::Spanish,
            QLocale::Spain
        ).toString(
            double(m_scopeSpanHz) / 1'000'000.0,
            'f',
            3
        ) + QStringLiteral(" MHz");
    }

    if (m_scopeSpanHz >= 1000) {
        return QLocale(
            QLocale::Spanish,
            QLocale::Spain
        ).toString(
            double(m_scopeSpanHz) / 1000.0,
            'f',
            m_scopeSpanHz % 1000 == 0 ? 0 : 1
        ) + QStringLiteral(" kHz");
    }

    return QString::number(m_scopeSpanHz)
           + QStringLiteral(" Hz");
}

bool RadioController::scopeOutOfRange() const
{
    return m_scopeOutOfRange;
}

bool RadioController::scopeHold() const
{
    return m_scopeHold;
}

int RadioController::scopeSweepSpeed() const
{
    return m_scopeSweepSpeed;
}

QString RadioController::scopeSweepSpeedText() const
{
    switch (m_scopeSweepSpeed) {
    case 1:
        return QStringLiteral("MID");
    case 2:
        return QStringLiteral("SLOW");
    default:
        return QStringLiteral("FAST");
    }
}

bool RadioController::scopeVbwWide() const
{
    return m_scopeVbwWide;
}

qulonglong RadioController::frequencyHz() const { return m_frequencyHz; }
QString RadioController::frequencyText() const { return m_frequencyText; }
QString RadioController::frequencyMhzText() const { return m_frequencyMhzText; }
QString RadioController::bandText() const { return m_bandText; }
QString RadioController::modeText() const { return m_modeText; }
QString RadioController::filterText() const { return m_filterText; }
QString RadioController::dataText() const
{
    return m_dataMode ? QStringLiteral("ACTIVADO")
                      : QStringLiteral("DESACTIVADO");
}
QString RadioController::txRxText() const
{
    return m_transmitting ? QStringLiteral("TX") : QStringLiteral("RX");
}
QString RadioController::vfoText() const
{
    if (m_selectedVfo == 0) return QStringLiteral("A");
    if (m_selectedVfo == 1) return QStringLiteral("B");
    return QStringLiteral("—");
}

int RadioController::selectedVfo() const
{
    return m_selectedVfo;
}

bool RadioController::vfoASelected() const
{
    return m_selectedVfo == 0;
}

bool RadioController::vfoBSelected() const
{
    return m_selectedVfo == 1;
}

qulonglong RadioController::vfoAFrequencyHz() const
{
    return m_vfoStates[0].frequencyHz;
}

QString RadioController::vfoAFrequencyText() const
{
    return vfoFrequencyText(0);
}

QString RadioController::vfoABandText() const
{
    return vfoBandText(0);
}

QString RadioController::vfoAModeText() const
{
    return vfoModeText(0);
}

QString RadioController::vfoADataText() const
{
    return vfoDataText(0);
}

QString RadioController::vfoAFilterText() const
{
    return vfoFilterText(0);
}

qulonglong RadioController::vfoBFrequencyHz() const
{
    return m_vfoStates[1].frequencyHz;
}

QString RadioController::vfoBFrequencyText() const
{
    return vfoFrequencyText(1);
}

QString RadioController::vfoBBandText() const
{
    return vfoBandText(1);
}

QString RadioController::vfoBModeText() const
{
    return vfoModeText(1);
}

QString RadioController::vfoBDataText() const
{
    return vfoDataText(1);
}

QString RadioController::vfoBFilterText() const
{
    return vfoFilterText(1);
}
QString RadioController::splitText() const
{
    return m_splitEnabled ? QStringLiteral("ON") : QStringLiteral("OFF");
}
QString RadioController::ritText() const
{
    const QString sign = m_ritOffsetHz >= 0 ? QStringLiteral("+")
                                            : QStringLiteral("−");
    return sign + QLocale(QLocale::Spanish, QLocale::Spain)
                      .toString(std::abs(m_ritOffsetHz))
           + QStringLiteral(" Hz");
}
QString RadioController::deltaTxText() const
{
    return m_deltaTxEnabled ? QStringLiteral("ON") : QStringLiteral("OFF");
}
QString RadioController::preampText() const
{
    switch (m_preamp) {
    case 1: return QStringLiteral("P.AMP1");
    case 2: return QStringLiteral("P.AMP2");
    default: return QStringLiteral("OFF");
    }
}
QString RadioController::attenuatorText() const
{
    return m_attenuatorEnabled ? QStringLiteral("20 dB") : QStringLiteral("OFF");
}
QString RadioController::tunerText() const
{
    switch (m_tunerState) {
    case 1: return QStringLiteral("ON");
    case 2: return QStringLiteral("TUNE");
    default: return QStringLiteral("OFF");
    }
}
QString RadioController::agcText() const
{
    switch (m_agc) {
    case 2: return QStringLiteral("MID");
    case 3: return QStringLiteral("SLOW");
    default: return QStringLiteral("FAST");
    }
}

int RadioController::ritOffsetHz() const { return m_ritOffsetHz; }
int RadioController::afGain() const { return m_afGain; }
int RadioController::rfGain() const { return m_rfGain; }
int RadioController::squelch() const { return m_squelch; }
int RadioController::rfPower() const { return m_rfPower; }
int RadioController::preamp() const { return m_preamp; }
int RadioController::agc() const { return m_agc; }

int RadioController::noiseBlankerLevel() const { return m_noiseBlankerLevel; }
int RadioController::noiseReductionLevel() const { return m_noiseReductionLevel; }
int RadioController::pbt1() const { return m_pbt1; }
int RadioController::pbt2() const { return m_pbt2; }
int RadioController::manualNotchPosition() const { return m_manualNotchPosition; }
int RadioController::manualNotchWidth() const { return m_manualNotchWidth; }
QString RadioController::manualNotchWidthText() const
{
    switch (m_manualNotchWidth) {
    case 0: return QStringLiteral("WIDE");
    case 2: return QStringLiteral("NAR");
    default: return QStringLiteral("MID");
    }
}
int RadioController::filterShape() const { return m_filterShape; }
QString RadioController::filterShapeText() const
{
    return m_filterShape == 0 ? QStringLiteral("SHARP")
                              : QStringLiteral("SOFT");
}

int RadioController::sMeterPercent() const { return m_sMeterPercent; }
QString RadioController::sMeterText() const { return m_sMeterText; }
int RadioController::powerMeterPercent() const { return m_powerMeterPercent; }
QString RadioController::powerMeterText() const { return m_powerMeterText; }
int RadioController::swrMeterPercent() const { return m_swrMeterPercent; }
QString RadioController::swrMeterText() const { return m_swrMeterText; }
int RadioController::alcMeterPercent() const { return m_alcMeterPercent; }
QString RadioController::alcMeterText() const { return m_alcMeterText; }
int RadioController::compMeterPercent() const { return m_compMeterPercent; }
QString RadioController::compMeterText() const { return m_compMeterText; }
int RadioController::voltageMeterPercent() const { return m_voltageMeterPercent; }
QString RadioController::voltageMeterText() const { return m_voltageMeterText; }
int RadioController::currentMeterPercent() const { return m_currentMeterPercent; }
QString RadioController::currentMeterText() const { return m_currentMeterText; }
bool RadioController::overflow() const { return m_overflow; }

QString RadioController::lastTx() const { return m_lastTx; }
QString RadioController::lastRx() const { return m_lastRx; }

QString RadioController::txTrafficHistory() const
{
    return m_txTrafficLines.join(QLatin1Char('\n'));
}

QString RadioController::rxTrafficHistory() const
{
    return m_rxTrafficLines.join(QLatin1Char('\n'));
}

void RadioController::loadConnectionSettings()
{
    QSettings settings;

    m_configuredPort =
        settings.value(
            QStringLiteral("connection/port"),
            QString()
        ).toString();

    m_configuredBaudRate =
        settings.value(
            QStringLiteral("connection/baudRate"),
            115200
        ).toInt();

    m_radioAddress = quint8(
        std::clamp(
            settings.value(
                QStringLiteral("connection/radioAddress"),
                0x94
            ).toInt(),
            0,
            255
        )
    );

    m_controllerAddress = quint8(
        std::clamp(
            settings.value(
                QStringLiteral("connection/controllerAddress"),
                0xE0
            ).toInt(),
            0,
            255
        )
    );

    m_autoConnectEnabled =
        settings.value(
            QStringLiteral("connection/autoConnect"),
            true
        ).toBool();

    m_autoReconnectEnabled =
        settings.value(
            QStringLiteral("connection/autoReconnect"),
            true
        ).toBool();

    m_pollIntervalMs =
        std::clamp(
            settings.value(
                QStringLiteral("connection/pollIntervalMs"),
                90
            ).toInt(),
            40,
            500
        );

    m_responseTimeoutMs =
        std::clamp(
            settings.value(
                QStringLiteral("connection/responseTimeoutMs"),
                850
            ).toInt(),
            250,
            3000
        );

    const QList<int> supportedBaudRates = {
        9600, 19200, 38400, 57600, 115200
    };

    if (!supportedBaudRates.contains(m_configuredBaudRate)) {
        m_configuredBaudRate = 115200;
    }

    if (m_radioAddress == m_controllerAddress) {
        m_radioAddress = 0x94;
        m_controllerAddress = 0xE0;
    }
}

void RadioController::saveConnectionSettings() const
{
    QSettings settings;

    settings.setValue(
        QStringLiteral("connection/port"),
        m_configuredPort
    );
    settings.setValue(
        QStringLiteral("connection/baudRate"),
        m_configuredBaudRate
    );
    settings.setValue(
        QStringLiteral("connection/radioAddress"),
        int(m_radioAddress)
    );
    settings.setValue(
        QStringLiteral("connection/controllerAddress"),
        int(m_controllerAddress)
    );
    settings.setValue(
        QStringLiteral("connection/autoConnect"),
        m_autoConnectEnabled
    );
    settings.setValue(
        QStringLiteral("connection/autoReconnect"),
        m_autoReconnectEnabled
    );
    settings.setValue(
        QStringLiteral("connection/pollIntervalMs"),
        m_pollIntervalMs
    );
    settings.setValue(
        QStringLiteral("connection/responseTimeoutMs"),
        m_responseTimeoutMs
    );
}

void RadioController::refreshConnectionDevices()
{
    emit connectionSettingsChanged();
    setActionStatus(
        QStringLiteral(
            "Lista de puertos y conectores actualizada"
        )
    );
}

bool RadioController::applyConnectionSettings(
    const QVariantMap &settings
)
{
    QString port =
        settings.value(
            QStringLiteral("port"),
            QStringLiteral("AUTO")
        ).toString().trimmed();

    if (port.compare(
            QStringLiteral("AUTO"),
            Qt::CaseInsensitive
        ) == 0) {
        port.clear();
    }

    const int baudRate =
        settings.value(
            QStringLiteral("baudRate"),
            115200
        ).toInt();
    const int radioAddress =
        settings.value(
            QStringLiteral("radioAddress"),
            0x94
        ).toInt();
    const int controllerAddress =
        settings.value(
            QStringLiteral("controllerAddress"),
            0xE0
        ).toInt();
    const bool autoConnect =
        settings.value(
            QStringLiteral("autoConnect"),
            true
        ).toBool();
    const bool autoReconnect =
        settings.value(
            QStringLiteral("autoReconnect"),
            true
        ).toBool();
    const int pollInterval =
        settings.value(
            QStringLiteral("pollIntervalMs"),
            90
        ).toInt();
    const int responseTimeout =
        settings.value(
            QStringLiteral("responseTimeoutMs"),
            850
        ).toInt();
    const bool reconnectNow =
        settings.value(
            QStringLiteral("reconnectNow"),
            true
        ).toBool();

    const QList<int> supportedBaudRates = {
        9600, 19200, 38400, 57600, 115200
    };

    if (!supportedBaudRates.contains(baudRate)) {
        setActionStatus(
            QStringLiteral(
                "Velocidad serie no admitida"
            )
        );
        return false;
    }

    if (radioAddress < 0
        || radioAddress > 255
        || controllerAddress < 0
        || controllerAddress > 255
        || radioAddress == controllerAddress) {
        setActionStatus(
            QStringLiteral(
                "Direcciones CI-V no válidas"
            )
        );
        return false;
    }

    if (pollInterval < 40
        || pollInterval > 500
        || responseTimeout < 250
        || responseTimeout > 3000) {
        setActionStatus(
            QStringLiteral(
                "Intervalos CI-V fuera de rango"
            )
        );
        return false;
    }

    m_configuredPort = port;
    m_configuredBaudRate = baudRate;
    m_radioAddress = quint8(radioAddress);
    m_controllerAddress = quint8(controllerAddress);
    m_autoConnectEnabled = autoConnect;
    m_autoReconnectEnabled = autoReconnect;
    m_pollIntervalMs = pollInterval;
    m_responseTimeoutMs = responseTimeout;

    m_pollTimer.setInterval(m_pollIntervalMs);
    m_responseTimer.setInterval(m_responseTimeoutMs);

    saveConnectionSettings();
    emit connectionSettingsChanged();

    setActionStatus(
        QStringLiteral(
            "Configuración de conexión guardada"
        )
    );

    if (reconnectNow) {
        reconnectRadio();
    }

    return true;
}

void RadioController::restoreRecommendedConnectionSettings()
{
    m_configuredPort.clear();
    m_configuredBaudRate = 115200;
    m_radioAddress = 0x94;
    m_controllerAddress = 0xE0;
    m_autoConnectEnabled = true;
    m_autoReconnectEnabled = true;
    m_pollIntervalMs = 90;
    m_responseTimeoutMs = 850;

    m_pollTimer.setInterval(m_pollIntervalMs);
    m_responseTimer.setInterval(m_responseTimeoutMs);

    saveConnectionSettings();
    emit connectionSettingsChanged();

    setActionStatus(
        QStringLiteral(
            "Valores recomendados restaurados"
        )
    );
}

void RadioController::reconnectRadio()
{
    if (m_shuttingDown) {
        return;
    }

    if (QSettings().value(QStringLiteral("lan/enabled"), false).toBool()) {
        setStatus(QStringLiteral("LAN seleccionada: conexión USB bloqueada"));
        return;
    }

    m_reconnectTimer.stop();
    disconnectRadio();

    setActionStatus(
        QStringLiteral(
            "Reconectando con la configuración actual…"
        )
    );

    QTimer::singleShot(
        260,
        this,
        &RadioController::connectRadio
    );
}


void RadioController::startSpectrumScope()
{
    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral(
                "No se puede iniciar el scope: radio desconectada"
            )
        );
        return;
    }

    if (m_scopeRunning) {
        refreshSpectrumScopeSettings();
        return;
    }

    resetScopeAssembly();
    m_scopeRunning = true;
    m_scopeOutOfRange = false;
    emit scopeStateChanged();

    QByteArray enableScope;
    enableScope.append(char(0x27));
    enableScope.append(char(0x10));
    enableScope.append(char(0x01));
    sendCivPayload(enableScope);

    QTimer::singleShot(
        120,
        this,
        [this]() {
            if (!m_serial.isOpen()
                || !m_scopeRunning) {
                return;
            }

            QByteArray enableOutput;
            enableOutput.append(char(0x27));
            enableOutput.append(char(0x11));
            enableOutput.append(char(0x01));
            sendCivPayload(enableOutput);
        }
    );

    QTimer::singleShot(
        280,
        this,
        [this]() {
            if (m_serial.isOpen()
                && m_scopeRunning) {
                refreshSpectrumScopeSettings();
            }
        }
    );

    setActionStatus(
        QStringLiteral(
            "Spectrum Scope: esperando datos CI-V 27 00…"
        )
    );
}

void RadioController::stopSpectrumScope()
{
    const bool wasRunning =
        m_scopeRunning;

    if (m_serial.isOpen()
        && wasRunning) {
        QByteArray disableOutput;
        disableOutput.append(char(0x27));
        disableOutput.append(char(0x11));
        disableOutput.append(char(0x00));
        sendCivPayload(disableOutput);
    }

    m_scopeRunning = false;
    m_scopeOutOfRange = false;
    resetScopeAssembly();

    if (wasRunning) {
        emit scopeStateChanged();
        setActionStatus(
            QStringLiteral(
                "Salida de datos del Spectrum Scope detenida"
            )
        );
    }
}

void RadioController::refreshSpectrumScopeSettings()
{
    if (!m_serial.isOpen()) {
        return;
    }

    static const quint8 subcommands[] = {
        0x10,
        0x11,
        0x14,
        0x15,
        0x17,
        0x1A,
        0x1D
    };

    for (int index = 0;
         index < int(
             sizeof(subcommands)
             / sizeof(subcommands[0])
         );
         ++index) {
        const quint8 subcommand =
            subcommands[index];

        QTimer::singleShot(
            index * 55,
            this,
            [this, subcommand]() {
                if (m_serial.isOpen()) {
                    sendScopeQuery(subcommand);
                }
            }
        );
    }
}

void RadioController::setSpectrumScopeMode(int mode)
{
    mode = std::clamp(mode, 0, 3);

    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral(
                "No se puede cambiar el scope: radio desconectada"
            )
        );
        return;
    }

    QByteArray payload;
    payload.append(char(0x27));
    payload.append(char(0x14));
    payload.append(char(0x00));
    payload.append(char(mode));

    if (sendCivPayload(payload)) {
        m_scopeMode = mode;
        resetScopeAssembly();
        emit scopeStateChanged();

        QTimer::singleShot(
            180,
            this,
            [this]() {
                sendScopeQuery(0x14);
            }
        );
    }
}

void RadioController::setSpectrumScopeSpan(
    qulonglong spanHz
)
{
    static const quint64 allowedSpans[] = {
        2500,
        5000,
        10000,
        25000,
        50000,
        100000,
        250000,
        500000
    };

    quint64 selectedSpan =
        allowedSpans[0];
    quint64 bestDistance =
        spanHz > selectedSpan
        ? spanHz - selectedSpan
        : selectedSpan - spanHz;

    for (const quint64 candidate :
         allowedSpans) {
        const quint64 distance =
            spanHz > candidate
            ? spanHz - candidate
            : candidate - spanHz;

        if (distance < bestDistance) {
            selectedSpan = candidate;
            bestDistance = distance;
        }
    }

    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral(
                "No se puede cambiar el span: radio desconectada"
            )
        );
        return;
    }

    QByteArray payload;
    payload.append(char(0x27));
    payload.append(char(0x15));
    payload.append(char(0x00));
    payload.append(
        encodeFrequency(selectedSpan)
    );

    if (sendCivPayload(payload)) {
        m_scopeSpanHz = selectedSpan;

        if (m_scopeCenterFrequencyHz > 0) {
            const quint64 half =
                selectedSpan / 2;
            m_scopeLowerFrequencyHz =
                m_scopeCenterFrequencyHz > half
                ? m_scopeCenterFrequencyHz - half
                : 0;
            m_scopeHigherFrequencyHz =
                m_scopeCenterFrequencyHz + half;
        }

        resetScopeAssembly();
        emit scopeStateChanged();

        QTimer::singleShot(
            180,
            this,
            [this]() {
                sendScopeQuery(0x15);
            }
        );
    }
}

void RadioController::setSpectrumScopeHold(
    bool enabled
)
{
    if (!m_serial.isOpen()) {
        return;
    }

    QByteArray payload;
    payload.append(char(0x27));
    payload.append(char(0x17));
    payload.append(char(0x00));
    payload.append(char(enabled ? 0x01 : 0x00));

    if (sendCivPayload(payload)) {
        m_scopeHold = enabled;
        emit scopeStateChanged();
    }
}

void RadioController::setSpectrumScopeSweepSpeed(
    int speed
)
{
    speed = std::clamp(speed, 0, 2);

    if (!m_serial.isOpen()) {
        return;
    }

    QByteArray payload;
    payload.append(char(0x27));
    payload.append(char(0x1A));
    payload.append(char(0x00));
    payload.append(char(speed));

    if (sendCivPayload(payload)) {
        m_scopeSweepSpeed = speed;
        emit scopeStateChanged();
    }
}

void RadioController::setSpectrumScopeVbwWide(
    bool wide
)
{
    if (!m_serial.isOpen()) {
        return;
    }

    QByteArray payload;
    payload.append(char(0x27));
    payload.append(char(0x1D));
    payload.append(char(0x00));
    payload.append(char(wide ? 0x01 : 0x00));

    if (sendCivPayload(payload)) {
        m_scopeVbwWide = wide;
        emit scopeStateChanged();
    }
}

void RadioController::sendScopeQuery(
    quint8 subcommand
)
{
    QByteArray payload;
    payload.append(char(0x27));
    payload.append(char(subcommand));
    sendCivPayload(payload);
}

void RadioController::resetScopeAssembly()
{
    m_scopeWaveformAssembly.clear();
    m_scopeExpectedDivision = 0;
    m_scopeLastDivision = 0;
}

void RadioController::scheduleAutomaticReconnect()
{
    if (m_shuttingDown
        || !m_autoReconnectEnabled
        || m_reconnectTimer.isActive()
        || m_serial.isOpen()) {
        return;
    }

    setActionStatus(
        QStringLiteral(
            "Reconexión automática en 3 segundos…"
        )
    );
    m_reconnectTimer.start();
}

void RadioController::connectRadio()
{
    m_reconnectTimer.stop();

    if (m_shuttingDown) {
        return;
    }

    if (m_serial.isOpen()) {
        setStatus(QStringLiteral("Radio conectada"));
        return;
    }

    setStatus(QStringLiteral("Buscando USB (B)…"));
    const QString detectedPort = findRadioPort();

    if (detectedPort.isEmpty()) {
        setStatus(
            QStringLiteral(
                "No se encontró el puerto CI-V configurado"
            )
        );
        scheduleAutomaticReconnect();
        return;
    }

    m_serial.setPortName(detectedPort);
    m_serial.setBaudRate(m_configuredBaudRate);
    m_serial.setDataBits(QSerialPort::Data8);
    m_serial.setParity(QSerialPort::NoParity);
    m_serial.setStopBits(QSerialPort::OneStop);
    m_serial.setFlowControl(QSerialPort::NoFlowControl);

    if (!m_serial.open(QIODevice::ReadWrite)) {
        setStatus(
            QStringLiteral(
                "No se pudo abrir el puerto: %1"
            )
                .arg(m_serial.errorString())
        );
        scheduleAutomaticReconnect();
        return;
    }

    m_serial.clear(QSerialPort::AllDirections);
    m_receiveBuffer.clear();
    m_scopeRunning = false;
    m_scopeOutOfRange = false;
    m_scopeSpectrumData.clear();
    m_scopeFrameCounter = 0;
    resetScopeAssembly();
    emit scopeStateChanged();
    emit scopeWaveformChanged();

    m_pendingQuery = QueryKind::None;
    m_nextQueryIndex = 0;
    m_fastMeterIndex = 0;
    m_pollPhase = 0;
    m_nextTxBandEdgeIndex = 1;
    m_txBandCount = -1;
    m_txBandEdges.clear();
    m_pendingKeyerMemoryChannel = 0;
    m_txStateKnown = false;
    m_initialTxProbePending = false;
    m_initialTxProbeAttempts = 0;
    m_pendingMemoryReadChannel = 0;
    m_memoryReadBatchActive = false;
    m_memoryReadRequestedCount = 0;
    m_memoryReadSuccessCount = 0;
    m_memoryReadFailureCount = 0;
    m_memoryEditVerifyChannel = 0;
    m_memoryEditExpectedRaw.clear();
    m_memoryEditVerifyAttempt = 0;
    m_deferredMemoryReadPending = false;
    m_deferredMemoryReadIncludesScanSettings = false;
    m_deferredMemoryReadFirstChannel = 1;
    m_deferredMemoryReadCount = 99;
    m_cwRefreshActive = false;
    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();
    m_pendingBandStackingRequest = BandStackingRequest{};
    m_memorySequenceAction = MemorySequenceAction::None;
    m_memorySequenceChannel = 0;
    m_memorySequenceGroup = 0;
    m_memoryStoreVfoSelected = false;
    m_pendingDirectMemoryChannel = 0;
    m_memoryVfoSnapshot = MemoryVfoSnapshot{};
    m_directMemoryReturnInProgress = false;
    m_scanActive = false;
    m_scanSubcommand = 0x00;
    m_consecutiveTimeouts = 0;
    m_safetyCheckActive = false;
    m_queuedWriteKind = WriteKind::None;
    m_activeWriteKind = WriteKind::None;
    setBusy(false);

    m_portName = detectedPort;
    emit portNameChanged();
    emit connectedChanged();

    setStatus(
        QStringLiteral(
            "Conectado · CI-V %1h · %2 baudios"
        )
            .arg(
                int(m_radioAddress),
                2,
                16,
                QLatin1Char('0')
            )
            .arg(m_configuredBaudRate)
            .toUpper()
    );
    setActionStatus(QStringLiteral("Comprobando estado TX/RX inicial…"));

    // No iniciar con S-meter ni con ajustes de recepción: durante TX
    // algunas consultas no responden. La primera trama será siempre 1C 00.
    m_initialTxProbePending = true;
    m_pollTimer.stop();
    QTimer::singleShot(
        140,
        this,
        &RadioController::beginInitialTxProbe
    );

    // El scope y su salida de datos quedan habilitados por defecto. Se
    // espera a que termine la comprobación inicial TX/RX para no mezclar
    // órdenes CI-V durante la fase más sensible de la conexión.
    QTimer::singleShot(
        650,
        this,
        &RadioController::startDefaultSpectrumScope
    );
}

void RadioController::disconnectRadio()
{
    m_reconnectTimer.stop();
    m_pollTimer.stop();
    m_responseTimer.stop();
    stopSpectrumScope();
    forceReceive();
    m_pendingQuery = QueryKind::None;
    m_safetyCheckActive = false;
    m_queuedWriteKind = WriteKind::None;
    m_activeWriteKind = WriteKind::None;
    m_queuedWritePayload.clear();
    m_receiveBuffer.clear();
    m_txReleasePending = false;
    m_pendingKeyerMemoryChannel = 0;
    m_txStateKnown = false;
    m_initialTxProbePending = false;
    m_initialTxProbeAttempts = 0;
    m_pendingMemoryReadChannel = 0;
    m_memoryReadBatchActive = false;
    m_memoryReadRequestedCount = 0;
    m_memoryReadSuccessCount = 0;
    m_memoryReadFailureCount = 0;
    m_memoryEditVerifyChannel = 0;
    m_memoryEditExpectedRaw.clear();
    m_memoryEditVerifyAttempt = 0;
    m_deferredMemoryReadPending = false;
    m_deferredMemoryReadIncludesScanSettings = false;
    m_deferredMemoryReadFirstChannel = 1;
    m_deferredMemoryReadCount = 99;
    m_cwRefreshActive = false;
    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();
    m_pendingBandStackingRequest = BandStackingRequest{};
    m_memorySequenceAction = MemorySequenceAction::None;
    m_memorySequenceChannel = 0;
    m_memorySequenceGroup = 0;
    m_memoryStoreVfoSelected = false;
    m_pendingDirectMemoryChannel = 0;
    m_memoryVfoSnapshot = MemoryVfoSnapshot{};
    m_directMemoryReturnInProgress = false;
    m_scanActive = false;
    m_scanSubcommand = 0x00;
    setBusy(false);

    if (m_serial.isOpen()) {
        // Completa cualquier byte de la última orden y vacía ambos buffers
        // antes de cerrar. QSerialPort usa apertura exclusiva en Linux; el
        // close explícito libera /dev/ttyACM* para la siguiente ejecución.
        m_serial.flush();
        m_serial.waitForBytesWritten(120);
        m_serial.clear(QSerialPort::AllDirections);
        m_serial.close();
    }
    m_serial.clearError();

    emit connectedChanged();
    setStatus(QStringLiteral("Desconectado"));
    setActionStatus(QStringLiteral("Sin conexión con la radio"));
}

void RadioController::shutdown()
{
    if (m_shuttingDown) {
        return;
    }

    // Debe activarse antes de cerrar: cualquier singleShot o señal de error
    // que quedase pendiente ya no podrá volver a abrir el puerto.
    m_shuttingDown = true;
    m_reconnectTimer.stop();
    m_pollTimer.stop();
    m_responseTimer.stop();
    disconnectRadio();
}

void RadioController::beginInitialTxProbe()
{
    if (!m_serial.isOpen()) {
        return;
    }

    if (m_pendingQuery != QueryKind::None
        || m_activeWriteKind != WriteKind::None) {
        QTimer::singleShot(
            120,
            this,
            &RadioController::beginInitialTxProbe
        );
        return;
    }

    ++m_initialTxProbeAttempts;
    m_initialTxProbePending = true;

    setStatus(
        QStringLiteral("Conectado · comprobando TX/RX…")
    );

    sendQuery(QueryKind::TxStatus);

    if (m_pendingQuery == QueryKind::TxStatus) {
        return;
    }

    m_initialTxProbePending = false;

    if (m_initialTxProbeAttempts < 3) {
        QTimer::singleShot(
            180,
            this,
            &RadioController::beginInitialTxProbe
        );
        return;
    }

    setStatus(
        QStringLiteral(
            "Conectado · puerto abierto; esperando respuesta CI-V"
        )
    );
    setActionStatus(
        QStringLiteral(
            "No se confirmó TX/RX inicial; la conexión permanece abierta"
        )
    );

    if (!m_pollTimer.isActive()) {
        m_pollTimer.start();
    }

    QTimer::singleShot(
        0,
        this,
        &RadioController::pollNextValue
    );
}

void RadioController::startDefaultSpectrumScope()
{
    if (m_shuttingDown || !m_serial.isOpen() || m_scopeRunning) {
        return;
    }

    if (m_initialTxProbePending || m_transmitting) {
        QTimer::singleShot(
            500,
            this,
            &RadioController::startDefaultSpectrumScope
        );
        return;
    }

    startSpectrumScope();
}

void RadioController::deferMemoryRead(
    int firstChannel,
    int count,
    bool includeScanSettings
)
{
    m_deferredMemoryReadPending = true;
    m_deferredMemoryReadIncludesScanSettings =
        includeScanSettings;
    m_deferredMemoryReadFirstChannel =
        std::clamp(firstChannel, 1, 99);
    m_deferredMemoryReadCount =
        std::clamp(
            count,
            1,
            99 - m_deferredMemoryReadFirstChannel + 1
        );

    if (!m_txStateKnown) {
        setActionStatus(
            includeScanSettings
            ? QStringLiteral(
                  "Esperando conocer RX/TX · MEM / SCAN se leerá automáticamente"
              )
            : QStringLiteral(
                  "Esperando conocer RX/TX · las memorias se leerán automáticamente"
              )
        );
        return;
    }

    setActionStatus(
        includeScanSettings
        ? QStringLiteral(
              "Radio en TX · MEM / SCAN se leerá automáticamente al volver a RX"
          )
        : QStringLiteral(
              "Radio en TX · las memorias se leerán automáticamente al volver a RX"
          )
    );
}

void RadioController::runDeferredMemoryRead()
{
    if (!m_deferredMemoryReadPending
        || !m_serial.isOpen()
        || !m_txStateKnown
        || m_transmitting) {
        return;
    }

    if (m_busy
        || m_pendingQuery != QueryKind::None
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        QTimer::singleShot(
            120,
            this,
            &RadioController::runDeferredMemoryRead
        );
        return;
    }

    const bool includeScanSettings =
        m_deferredMemoryReadIncludesScanSettings;
    const int firstChannel =
        m_deferredMemoryReadFirstChannel;
    const int count =
        m_deferredMemoryReadCount;

    m_deferredMemoryReadPending = false;
    m_deferredMemoryReadIncludesScanSettings = false;

    if (includeScanSettings) {
        refreshMemoryScanSettings(firstChannel);
    } else {
        readMemoryRange(firstChannel, count);
    }
}


void RadioController::clearTrafficHistory()
{
    m_txTrafficLines.clear();
    m_rxTrafficLines.clear();
    m_txTrafficSequence = 0;
    m_rxTrafficSequence = 0;
    m_lastTx = QStringLiteral("—");
    m_lastRx = QStringLiteral("—");

    emit trafficChanged();
    setActionStatus(
        QStringLiteral("Historial de diagnóstico CI-V borrado")
    );
}

void RadioController::copyTextToClipboard(
    const QString &text,
    const QString &description
)
{
    if (text.trimmed().isEmpty()
        || text.trimmed() == QStringLiteral("—")) {
        setActionStatus(
            QStringLiteral("No hay tramas para copiar")
        );
        return;
    }

    QClipboard *clipboard =
        QGuiApplication::clipboard();

    if (clipboard == nullptr) {
        setActionStatus(
            QStringLiteral("No se pudo acceder al portapapeles")
        );
        return;
    }

    clipboard->setText(text);

    setActionStatus(
        QStringLiteral("%1 copiado al portapapeles")
            .arg(description)
    );
}

void RadioController::setTransmit(bool enabled)
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    // Si se suelta el botón antes de recibir PASS para TX, se conserva
    // la petición de volver a RX y se ejecuta inmediatamente después.
    if (!enabled
        && m_activeWriteKind == WriteKind::Transmit
        && m_activeDesiredValue == 1) {
        m_txReleasePending = true;
        setActionStatus(QStringLiteral("Liberación de PTT pendiente…"));
        return;
    }

    if (m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None) {
        setActionStatus(QStringLiteral("Espere a que termine la orden anterior"));
        return;
    }

    if (enabled && m_txInhibitEnabled) {
        setActionStatus(
            QStringLiteral("PTT bloqueado: TX INHIBIT está activado")
        );
        return;
    }

    if (enabled && m_transmitting) {
        setActionStatus(QStringLiteral(
            "La transmisión actual no fue iniciada por este panel"
        ));
        return;
    }

    if (!enabled && !m_pttOwned && !m_transmitting) {
        return;
    }

    sendTransmitCommand(enabled);
}

void RadioController::setFrequency(const QString &text)
{
    setVfoFrequency(m_selectedVfo, text);
}

void RadioController::setExternalFrequency(qulonglong frequencyHz)
{
    // Update the displayed/VFO state without queueing a write back to the
    // radio. This is used by the direct LAN status stream.
    decodeFrequency(encodeFrequency(frequencyHz));
}

void RadioController::adjustFrequency(int deltaHz)
{
    adjustVfoFrequency(m_selectedVfo, deltaHz);
}

void RadioController::setVfoFrequency(int vfoNumber,
                                      const QString &text)
{
    if (vfoNumber < 0 || vfoNumber > 1) {
        setActionStatus(QStringLiteral("VFO no válido"));
        return;
    }

    quint64 frequency = 0;
    QString errorText;

    if (!parseFrequency(text, frequency, errorText)) {
        setActionStatus(errorText);
        return;
    }

    const quint8 selector = selectorForActualVfo(vfoNumber);

    QByteArray payload;
    payload.append(char(0x25));
    payload.append(char(selector));
    payload.append(encodeFrequency(frequency));

    const QueryKind refresh =
        selector == 0x00
        ? QueryKind::VfoSelectedFrequency
        : QueryKind::VfoUnselectedFrequency;

    queueProtectedWrite(
        WriteKind::Frequency,
        payload,
        QStringLiteral("VFO %1 · %2 Hz")
            .arg(vfoNumber == 0 ? QStringLiteral("A")
                                : QStringLiteral("B"),
                 formatFrequency(frequency)),
        refresh
    );
}

void RadioController::adjustVfoFrequency(int vfoNumber,
                                         int deltaHz)
{
    if (vfoNumber < 0 || vfoNumber > 1) {
        setActionStatus(QStringLiteral("VFO no válido"));
        return;
    }

    quint64 current = m_vfoStates[vfoNumber].frequencyHz;

    if (!m_vfoStates[vfoNumber].frequencyValid) {
        if (vfoNumber == m_selectedVfo && m_frequencyHz != 0) {
            current = m_frequencyHz;
        } else {
            setActionStatus(
                QStringLiteral("Todavía no se conoce la frecuencia del VFO %1")
                    .arg(vfoNumber == 0 ? QStringLiteral("A")
                                        : QStringLiteral("B"))
            );
            return;
        }
    }

    const qint64 target = qint64(current) + qint64(deltaHz);

    if (target < 30000 || target > 74800000) {
        setActionStatus(
            QStringLiteral("El paso dejaría la frecuencia fuera de margen")
        );
        return;
    }

    setVfoFrequency(vfoNumber, QString::number(target));
}

void RadioController::setOperatingMode(const QString &requestedMode)
{
    const quint8 newMode = modeCodeForName(requestedMode);
    if (newMode == 0xFF) {
        setActionStatus(QStringLiteral("Modo no reconocido"));
        return;
    }

    const bool newData = modeSupportsData(newMode) ? m_dataMode : false;
    const quint8 filter = (m_filterCode >= 1 && m_filterCode <= 3)
                              ? m_filterCode : 1;

    queueProtectedWrite(WriteKind::Mode,
                        modeDataFilterPayload(newMode, newData, filter),
                        QStringLiteral("Modo %1").arg(requestedMode),
                        QueryKind::Mode);
}

void RadioController::setOperatingModeState(
    const QString &requestedMode,
    bool dataEnabled,
    int filterNumber)
{
    const quint8 newMode = modeCodeForName(requestedMode);
    if (newMode == 0xFF) {
        setActionStatus(QStringLiteral("Modo no reconocido"));
        return;
    }

    if (filterNumber < 1 || filterNumber > 3) {
        setActionStatus(QStringLiteral("Filtro no válido"));
        return;
    }

    const bool restoredData =
        dataEnabled && modeSupportsData(newMode);

    queueProtectedWrite(
        WriteKind::Mode,
        modeDataFilterPayload(newMode,
                              restoredData,
                              quint8(filterNumber)),
        QStringLiteral("Modo %1 · %2 · FIL%3")
            .arg(requestedMode,
                 restoredData
                     ? QStringLiteral("DATA")
                     : QStringLiteral("DATA OFF"))
            .arg(filterNumber),
        QueryKind::Mode
    );
}

void RadioController::setDataEnabled(bool enabled)
{
    if (m_modeCode == 0xFF) {
        setActionStatus(QStringLiteral("Todavía no se conoce el modo de la radio"));
        return;
    }
    if (enabled && !modeSupportsData(m_modeCode)) {
        setActionStatus(QStringLiteral("DATA no está disponible en %1")
                            .arg(m_modeText));
        return;
    }

    const quint8 filter = (m_filterCode >= 1 && m_filterCode <= 3)
                              ? m_filterCode : 1;
    queueProtectedWrite(WriteKind::DataMode,
                        modeDataFilterPayload(m_modeCode, enabled, filter),
                        enabled ? QStringLiteral("DATA activado")
                                : QStringLiteral("DATA desactivado"),
                        QueryKind::DataMode);
}

void RadioController::setFilter(int filterNumber)
{
    if (m_modeCode == 0xFF) {
        setActionStatus(QStringLiteral("Todavía no se conoce el modo de la radio"));
        return;
    }
    if (filterNumber < 1 || filterNumber > 3) {
        setActionStatus(QStringLiteral("Filtro no válido"));
        return;
    }

    queueProtectedWrite(WriteKind::Filter,
                        modeDataFilterPayload(m_modeCode, m_dataMode,
                                              quint8(filterNumber)),
                        QStringLiteral("FIL%1").arg(filterNumber),
                        QueryKind::Mode);
}

void RadioController::selectVfoA()
{
    queueProtectedWrite(WriteKind::SelectVfo,
                        QByteArray::fromHex("0700"),
                        QStringLiteral("VFO A"),
                        QueryKind::Frequency, 0);
}

void RadioController::selectVfoB()
{
    queueProtectedWrite(WriteKind::SelectVfo,
                        QByteArray::fromHex("0701"),
                        QStringLiteral("VFO B"),
                        QueryKind::Frequency, 1);
}

void RadioController::equalizeVfos()
{
    queueProtectedWrite(WriteKind::EqualizeVfos,
                        QByteArray::fromHex("07A0"),
                        QStringLiteral("A = B"),
                        QueryKind::Frequency);
}

void RadioController::exchangeVfos()
{
    queueProtectedWrite(WriteKind::ExchangeVfos,
                        QByteArray::fromHex("07B0"),
                        QStringLiteral("Intercambio A ↔ B"),
                        QueryKind::Frequency);
}

void RadioController::setSplitEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x0F));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(WriteKind::Split, payload,
                        enabled ? QStringLiteral("SPLIT activado")
                                : QStringLiteral("SPLIT desactivado"),
                        QueryKind::Split);
}

void RadioController::setRitOffset(int offsetHz)
{
    offsetHz = std::clamp(offsetHz, -9999, 9999);
    QByteArray payload;
    payload.append(char(0x21));
    payload.append(char(0x00));
    payload.append(encodeRitOffset(offsetHz));
    queueProtectedWrite(WriteKind::RitOffset, payload,
                        QStringLiteral("RIT %1")
                            .arg(offsetHz >= 0
                                     ? QStringLiteral("+%1 Hz").arg(offsetHz)
                                     : QStringLiteral("%1 Hz").arg(offsetHz)),
                        QueryKind::RitOffset,
                        offsetHz);
}

void RadioController::setRitEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x21));
    payload.append(char(0x01));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(WriteKind::RitEnabled, payload,
                        enabled ? QStringLiteral("RIT activado")
                                : QStringLiteral("RIT desactivado"),
                        QueryKind::RitEnabled);
}

void RadioController::setDeltaTxEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x21));
    payload.append(char(0x02));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(WriteKind::DeltaTxEnabled, payload,
                        enabled ? QStringLiteral("ΔTX activado")
                                : QStringLiteral("ΔTX desactivado"),
                        QueryKind::DeltaTxEnabled);
}

void RadioController::setAfGain(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x01));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(WriteKind::AfGain, payload,
                        QStringLiteral("AF %1 %").arg(clampPercent(percent)),
                        QueryKind::AfGain);
}

void RadioController::setRfGain(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x02));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(WriteKind::RfGain, payload,
                        QStringLiteral("RF %1 %").arg(clampPercent(percent)),
                        QueryKind::RfGain);
}

void RadioController::setSquelch(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x03));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(WriteKind::Squelch, payload,
                        QStringLiteral("SQL %1 %").arg(clampPercent(percent)),
                        QueryKind::Squelch);
}

void RadioController::setRfPower(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x0A));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(WriteKind::RfPower, payload,
                        QStringLiteral("Potencia RF %1 %")
                            .arg(clampPercent(percent)),
                        QueryKind::RfPower);
}


void RadioController::setMicrophoneGain(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x0B));
    payload.append(encodeLevel(percent));

    queueProtectedWrite(
        WriteKind::MicrophoneGain,
        payload,
        QStringLiteral("Ganancia MIC %1 %").arg(clampPercent(percent)),
        QueryKind::MicrophoneGain
    );
}

void RadioController::setSpeechCompressorLevel(int level)
{
    level = std::clamp(level, 0, 10);

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x0E));
    payload.append(encodeLevel(level * 10));

    queueProtectedWrite(
        WriteKind::SpeechCompressorLevel,
        payload,
        QStringLiteral("Nivel COMP %1").arg(level),
        QueryKind::SpeechCompressorLevel
    );
}

void RadioController::setMonitorLevel(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x15));
    payload.append(encodeLevel(percent));

    queueProtectedWrite(
        WriteKind::MonitorLevel,
        payload,
        QStringLiteral("Nivel MONITOR %1 %").arg(clampPercent(percent)),
        QueryKind::MonitorLevel
    );
}

void RadioController::setVoxGain(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x16));
    payload.append(encodeLevel(percent));

    queueProtectedWrite(
        WriteKind::VoxGain,
        payload,
        QStringLiteral("Ganancia VOX %1 %").arg(clampPercent(percent)),
        QueryKind::VoxGain
    );
}

void RadioController::setAntiVoxGain(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x17));
    payload.append(encodeLevel(percent));

    queueProtectedWrite(
        WriteKind::AntiVoxGain,
        payload,
        QStringLiteral("ANTI-VOX %1 %").arg(clampPercent(percent)),
        QueryKind::AntiVoxGain
    );
}

void RadioController::setSpeechCompressorEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x44));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::SpeechCompressor,
        payload,
        enabled ? QStringLiteral("Compresor ON")
                : QStringLiteral("Compresor OFF"),
        QueryKind::SpeechCompressor
    );
}

void RadioController::setMonitorEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x45));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::Monitor,
        payload,
        enabled ? QStringLiteral("Monitor ON")
                : QStringLiteral("Monitor OFF"),
        QueryKind::Monitor
    );
}

void RadioController::setVoxEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x46));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::Vox,
        payload,
        enabled ? QStringLiteral("VOX ON")
                : QStringLiteral("VOX OFF"),
        QueryKind::Vox
    );
}

void RadioController::setTxFilterWidth(int width)
{
    width = std::clamp(width, 0, 2);

    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x58));
    payload.append(char(width));

    queueProtectedWrite(
        WriteKind::TxFilterWidth,
        payload,
        QStringLiteral("Filtro TX %1").arg(txFilterWidthName(width)),
        QueryKind::TxFilterWidth
    );
}

void RadioController::setTxInhibitEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x66));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::TxInhibit,
        payload,
        enabled ? QStringLiteral("TX INHIBIT activado")
                : QStringLiteral("TX INHIBIT desactivado"),
        QueryKind::TxInhibit
    );
}

void RadioController::refreshTxAudioSettings()
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("Conecte la radio para leer TX/AUDIO"));
        return;
    }

    m_nextQueryIndex = int(QueryKind::MicrophoneGain) + 1;

    if (m_pendingQuery == QueryKind::None
        && m_activeWriteKind == WriteKind::None
        && !m_busy) {
        sendQuery(QueryKind::MicrophoneGain);
        setActionStatus(QStringLiteral("Actualizando ajustes TX/AUDIO…"));
    }
}


void RadioController::setCwApfPeakOffsetHz(int offsetHz)
{
    offsetHz = std::clamp(offsetHz, -550, 550);
    offsetHz = int(std::lround(offsetHz / 10.0)) * 10;

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x05));
    payload.append(encodeRawLevel(
        rangeToRaw(offsetHz, -550, 550)
    ));

    queueProtectedWrite(
        WriteKind::CwApfPeak,
        payload,
        QStringLiteral("Pico APF CW %1 Hz")
            .arg(offsetHz >= 0
                     ? QStringLiteral("+%1").arg(offsetHz)
                     : QString::number(offsetHz)),
        QueryKind::CwApfPeak,
        offsetHz
    );
}

void RadioController::setCwPitchHz(int pitchHz)
{
    pitchHz = std::clamp(pitchHz, 300, 900);
    pitchHz = int(std::lround(pitchHz / 5.0)) * 5;

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x09));
    payload.append(encodeRawLevel(
        rangeToRaw(pitchHz, 300, 900)
    ));

    queueProtectedWrite(
        WriteKind::CwPitch,
        payload,
        QStringLiteral("CW PITCH %1 Hz").arg(pitchHz),
        QueryKind::CwPitch,
        pitchHz
    );
}

void RadioController::setCwKeySpeedWpm(int speedWpm)
{
    speedWpm = std::clamp(speedWpm, 6, 48);

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x0C));
    payload.append(encodeRawLevel(
        rangeToRaw(speedWpm, 6, 48)
    ));

    queueProtectedWrite(
        WriteKind::CwKeySpeed,
        payload,
        QStringLiteral("Velocidad CW %1 WPM").arg(speedWpm),
        QueryKind::CwKeySpeed,
        speedWpm
    );
}

void RadioController::setCwBreakInDelayTenths(int tenths)
{
    tenths = std::clamp(tenths, 20, 130);

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x0F));
    payload.append(encodeRawLevel(
        rangeToRaw(tenths, 20, 130)
    ));

    queueProtectedWrite(
        WriteKind::CwBreakInDelay,
        payload,
        QStringLiteral("Retardo Break-in %1 d")
            .arg(QString::number(tenths / 10.0, 'f', 1)),
        QueryKind::CwBreakInDelay,
        tenths
    );
}

void RadioController::setApfMode(int mode)
{
    mode = std::clamp(mode, 0, 3);

    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x32));
    payload.append(char(mode));

    queueProtectedWrite(
        WriteKind::ApfMode,
        payload,
        QStringLiteral("APF %1").arg(apfModeName(mode)),
        QueryKind::ApfMode,
        mode
    );
}

void RadioController::setBreakInMode(int mode)
{
    mode = std::clamp(mode, 0, 2);

    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x47));
    payload.append(char(mode));

    queueProtectedWrite(
        WriteKind::BreakInMode,
        payload,
        QStringLiteral("Break-in %1").arg(breakInModeName(mode)),
        QueryKind::BreakInMode,
        mode
    );
}

void RadioController::setSideToneLevel(int percent)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x18));
    payload.append(encodeLevel(percent));

    queueProtectedWrite(
        WriteKind::SideToneLevel,
        payload,
        QStringLiteral("Nivel Side Tone %1 %")
            .arg(clampPercent(percent)),
        QueryKind::SideToneLevel,
        clampPercent(percent)
    );
}

void RadioController::setSideToneLimitEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x19));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::SideToneLimit,
        payload,
        enabled ? QStringLiteral("Límite Side Tone ON")
                : QStringLiteral("Límite Side Tone OFF"),
        QueryKind::SideToneLimit,
        enabled ? 1 : 0
    );
}

void RadioController::setKeyerRepeatSeconds(int seconds)
{
    seconds = std::clamp(seconds, 1, 60);

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x20));
    payload.append(char(encodeBcdNumber(seconds)));

    queueProtectedWrite(
        WriteKind::KeyerRepeatTime,
        payload,
        QStringLiteral("Repetición Keyer %1 s").arg(seconds),
        QueryKind::KeyerRepeatTime,
        seconds
    );
}

void RadioController::setDotDashRatioTenths(int tenths)
{
    tenths = std::clamp(tenths, 28, 45);

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x21));
    payload.append(char(encodeBcdNumber(tenths)));

    queueProtectedWrite(
        WriteKind::DotDashRatio,
        payload,
        QStringLiteral("Relación punto/raya 1:1:%1")
            .arg(QString::number(tenths / 10.0, 'f', 1)),
        QueryKind::DotDashRatio,
        tenths
    );
}

void RadioController::setRiseTimeMs(int milliseconds)
{
    static constexpr int validValues[] = {2, 4, 6, 8};

    int selected = 2;
    int smallestDistance = std::abs(milliseconds - selected);

    for (const int value : validValues) {
        const int distance = std::abs(milliseconds - value);
        if (distance < smallestDistance) {
            selected = value;
            smallestDistance = distance;
        }
    }

    const int code = (selected - 2) / 2;

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x22));
    payload.append(char(code));

    queueProtectedWrite(
        WriteKind::RiseTime,
        payload,
        QStringLiteral("Rise Time %1 ms").arg(selected),
        QueryKind::RiseTime,
        selected
    );
}

void RadioController::setPaddleReversed(bool reversed)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x23));
    payload.append(char(reversed ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::PaddlePolarity,
        payload,
        reversed ? QStringLiteral("Paddle Reverse")
                 : QStringLiteral("Paddle Normal"),
        QueryKind::PaddlePolarity,
        reversed ? 1 : 0
    );
}

void RadioController::setKeyType(int type)
{
    type = std::clamp(type, 0, 2);

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x24));
    payload.append(char(type));

    queueProtectedWrite(
        WriteKind::KeyType,
        payload,
        QStringLiteral("Tipo de llave %1").arg(keyTypeName(type)),
        QueryKind::KeyType,
        type
    );
}

void RadioController::setMicUpDownKeyerEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x25));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::MicUpDownKeyer,
        payload,
        enabled ? QStringLiteral("MIC Up/Down Keyer ON")
                : QStringLiteral("MIC Up/Down Keyer OFF"),
        QueryKind::MicUpDownKeyer,
        enabled ? 1 : 0
    );
}

void RadioController::setCwDecodeDisplayEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x26));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::CwDecodeDisplay,
        payload,
        enabled ? QStringLiteral("CW Decode Display ON")
                : QStringLiteral("CW Decode Display OFF"),
        QueryKind::CwDecodeDisplay,
        enabled ? 1 : 0
    );
}

void RadioController::refreshCwSettings()
{
    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("Conecte la radio para leer CW SET")
        );
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(
            QStringLiteral("Espere a que termine la orden CI-V actual")
        );
        return;
    }

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    m_cwRefreshQueries.enqueue(QueryKind::CwApfPeak);
    m_cwRefreshQueries.enqueue(QueryKind::CwPitch);
    m_cwRefreshQueries.enqueue(QueryKind::CwKeySpeed);
    m_cwRefreshQueries.enqueue(QueryKind::CwBreakInDelay);
    m_cwRefreshQueries.enqueue(QueryKind::ApfMode);
    m_cwRefreshQueries.enqueue(QueryKind::BreakInMode);

    m_cwRefreshQueries.enqueue(QueryKind::SideToneLevel);
    m_cwRefreshQueries.enqueue(QueryKind::SideToneLimit);
    m_cwRefreshQueries.enqueue(QueryKind::KeyerRepeatTime);
    m_cwRefreshQueries.enqueue(QueryKind::DotDashRatio);
    m_cwRefreshQueries.enqueue(QueryKind::RiseTime);
    m_cwRefreshQueries.enqueue(QueryKind::PaddlePolarity);
    m_cwRefreshQueries.enqueue(QueryKind::KeyType);
    m_cwRefreshQueries.enqueue(QueryKind::MicUpDownKeyer);
    m_cwRefreshQueries.enqueue(QueryKind::CwDecodeDisplay);

    for (int channel = 1; channel <= 8; ++channel) {
        m_keyerReadQueue.enqueue(channel);
    }

    m_manualRefreshCompletionText =
        QStringLiteral("Configuración CW actualizada");
    m_cwRefreshActive = true;
    setActionStatus(QStringLiteral("Leyendo configuración CW…"));

    if (m_pendingQuery == QueryKind::None) {
        sendNextCwRefreshQuery();
    }
}

void RadioController::readKeyerMemory(int channel)
{
    if (channel < 1 || channel > 8) {
        setActionStatus(QStringLiteral("Memoria Keyer no válida"));
        return;
    }

    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();
    m_keyerReadQueue.enqueue(channel);
    m_manualRefreshCompletionText =
        QStringLiteral("Memoria Keyer actualizada");
    m_cwRefreshActive = true;
    setActionStatus(
        QStringLiteral("Leyendo memoria M%1…").arg(channel)
    );

    if (m_pendingQuery == QueryKind::None) {
        sendNextCwRefreshQuery();
    }
}

void RadioController::readAllKeyerMemories()
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    for (int channel = 1; channel <= 8; ++channel) {
        m_keyerReadQueue.enqueue(channel);
    }

    m_manualRefreshCompletionText =
        QStringLiteral("Memorias Keyer actualizadas");
    m_cwRefreshActive = true;
    setActionStatus(QStringLiteral("Leyendo memorias M1–M8…"));

    if (m_pendingQuery == QueryKind::None) {
        sendNextCwRefreshQuery();
    }
}

void RadioController::writeKeyerMemory(
    int channel,
    const QString &text
)
{
    if (channel < 1 || channel > 8) {
        setActionStatus(QStringLiteral("Memoria Keyer no válida"));
        return;
    }

    QByteArray encoded;
    QString errorText;

    if (!encodeKeyerMemoryText(text, encoded, errorText)) {
        setActionStatus(errorText);
        return;
    }

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x02));
    payload.append(char(channel));
    payload.append(encoded);

    queueProtectedWrite(
        WriteKind::KeyerMemory,
        payload,
        QStringLiteral("Guardar memoria M%1").arg(channel),
        QueryKind::None,
        channel
    );
}

void RadioController::sendCwMessage(const QString &text)
{
    QByteArray encoded;
    QString errorText;

    if (!encodeDirectCwText(text, encoded, errorText)) {
        setActionStatus(errorText);
        return;
    }

    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (!cwModeActive()) {
        setActionStatus(
            QStringLiteral("Seleccione CW o CW-R para enviar el mensaje")
        );
        return;
    }

    if (m_txInhibitEnabled && !m_transmitting) {
        setActionStatus(
            QStringLiteral("TX bloqueado: TX INHIBIT está activado")
        );
        return;
    }

    if (!m_transmitting && m_breakInMode == 0) {
        setActionStatus(
            QStringLiteral(
                "Active Semi o Full Break-in, o ponga la radio en TX"
            )
        );
        return;
    }

    QByteArray payload;
    payload.append(char(0x17));
    payload.append(encoded);

    sendDirectCwWrite(
        WriteKind::CwMessage,
        payload,
        QStringLiteral("Mensaje CW")
    );
}

void RadioController::stopCwMessage()
{
    QByteArray payload;
    payload.append(char(0x17));
    payload.append(char(0xFF));

    sendDirectCwWrite(
        WriteKind::CwStop,
        payload,
        QStringLiteral("Detener mensaje CW")
    );
}

void RadioController::sendDirectCwWrite(
    WriteKind kind,
    const QByteArray &payload,
    const QString &label
)
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_pendingQuery != QueryKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    m_activeWriteKind = kind;
    m_activeWriteLabel = label;
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = 0;
    setBusy(true);
    setActionStatus(QStringLiteral("Enviando: %1…").arg(label));

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        setBusy(false);
        return;
    }

    m_responseTimer.start();
}

void RadioController::sendNextCwRefreshQuery()
{
    if (!m_cwRefreshActive) {
        return;
    }

    if (!m_serial.isOpen()) {
        m_cwRefreshActive = false;
        m_cwRefreshQueries.clear();
        m_keyerReadQueue.clear();
        m_memoryReadQueue.clear();
        m_bandStackingReadQueue.clear();
        m_pendingMemoryReadChannel = 0;
        const bool memoryReadWasActive = m_memoryReadBatchActive;
        m_memoryReadBatchActive = false;
        if (memoryReadWasActive) emit memoryReadActiveChanged();
        m_memoryReadRequestedCount = 0;
        m_memoryReadSuccessCount = 0;
        m_memoryReadFailureCount = 0;
        m_pendingBandStackingRequest = BandStackingRequest{};
        setActionStatus(QStringLiteral("Se perdió la conexión con la radio"));
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_pendingQuery != QueryKind::None) {
        return;
    }

    if (!m_cwRefreshQueries.isEmpty()) {
        sendQuery(m_cwRefreshQueries.dequeue());
        return;
    }

    if (!m_keyerReadQueue.isEmpty()) {
        m_pendingKeyerMemoryChannel = m_keyerReadQueue.dequeue();
        sendQuery(QueryKind::KeyerMemory);
        return;
    }

    if (!m_memoryReadQueue.isEmpty()) {
        m_pendingMemoryReadChannel = m_memoryReadQueue.dequeue();
        setActionStatus(
            QStringLiteral("Solicitando M%1…")
                .arg(
                    m_pendingMemoryReadChannel,
                    2,
                    10,
                    QLatin1Char('0')
                )
        );
        sendQuery(QueryKind::MemoryContent);
        return;
    }

    if (!m_bandStackingReadQueue.isEmpty()) {
        m_pendingBandStackingRequest =
            m_bandStackingReadQueue.dequeue();
        sendQuery(QueryKind::BandStacking);
        return;
    }

    m_cwRefreshActive = false;
    m_pendingKeyerMemoryChannel = 0;
    m_pendingMemoryReadChannel = 0;
    m_pendingBandStackingRequest = BandStackingRequest{};

    if (m_memoryReadBatchActive) {
        const int unanswered =
            std::max(
                0,
                m_memoryReadRequestedCount
                - m_memoryReadSuccessCount
                - m_memoryReadFailureCount
            );

        setActionStatus(
            QStringLiteral(
                "Memorias leídas: %1/%2 · fallos: %3 · sin respuesta: %4"
            )
                .arg(m_memoryReadSuccessCount)
                .arg(m_memoryReadRequestedCount)
                .arg(m_memoryReadFailureCount)
                .arg(unanswered)
        );

        m_memoryReadBatchActive = false;
        emit memoryReadActiveChanged();
        m_memoryReadRequestedCount = 0;
        m_memoryReadSuccessCount = 0;
        m_memoryReadFailureCount = 0;
    } else {
        setActionStatus(m_manualRefreshCompletionText);
    }

    if (m_serial.isOpen() && !m_pollTimer.isActive()) {
        m_pollTimer.start();
    }
}

void RadioController::setRepeaterToneEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x42));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::RepeaterTone,
        payload,
        enabled ? QStringLiteral("Tono de repetidor ON")
                : QStringLiteral("Tono de repetidor OFF"),
        QueryKind::RepeaterTone,
        enabled ? 1 : 0
    );
}

void RadioController::setToneSquelchEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x43));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::ToneSquelch,
        payload,
        enabled ? QStringLiteral("Tone Squelch ON")
                : QStringLiteral("Tone Squelch OFF"),
        QueryKind::ToneSquelch,
        enabled ? 1 : 0
    );
}

void RadioController::setRepeaterToneTenthsHz(int tenthsHz)
{
    tenthsHz = std::clamp(tenthsHz, 0, 2999);

    QByteArray payload;
    payload.append(char(0x1B));
    payload.append(char(0x00));
    payload.append(encodeToneFrequency(tenthsHz));

    queueProtectedWrite(
        WriteKind::RepeaterToneFrequency,
        payload,
        QStringLiteral("Tono repetidor %1")
            .arg(toneFrequencyName(tenthsHz)),
        QueryKind::RepeaterToneFrequency,
        tenthsHz
    );
}

void RadioController::setToneSquelchTenthsHz(int tenthsHz)
{
    tenthsHz = std::clamp(tenthsHz, 0, 2999);

    QByteArray payload;
    payload.append(char(0x1B));
    payload.append(char(0x01));
    payload.append(encodeToneFrequency(tenthsHz));

    queueProtectedWrite(
        WriteKind::ToneSquelchFrequency,
        payload,
        QStringLiteral("TSQL %1")
            .arg(toneFrequencyName(tenthsHz)),
        QueryKind::ToneSquelchFrequency,
        tenthsHz
    );
}

void RadioController::setTwinPeakEnabled(bool enabled)
{
    if (enabled && !twinPeakAvailable()) {
        setActionStatus(
            QStringLiteral(
                "Twin Peak requiere MARK 2125 Hz y SHIFT 170 Hz"
            )
        );
        return;
    }

    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x4F));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::TwinPeak,
        payload,
        enabled ? QStringLiteral("Twin Peak ON")
                : QStringLiteral("Twin Peak OFF"),
        QueryKind::TwinPeak,
        enabled ? 1 : 0
    );
}

void RadioController::setRttyMarkFrequencyCode(int code)
{
    code = std::clamp(code, 0, 2);

    if (m_twinPeakEnabled && code != 2) {
        setActionStatus(
            QStringLiteral(
                "Desactive Twin Peak antes de cambiar MARK"
            )
        );
        return;
    }

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x00));
    payload.append(char(0x39));
    payload.append(char(code));

    queueProtectedWrite(
        WriteKind::RttyMarkFrequency,
        payload,
        QStringLiteral("RTTY MARK %1")
            .arg(rttyMarkName(code)),
        QueryKind::RttyMarkFrequency,
        code
    );
}

void RadioController::setRttyShiftWidthCode(int code)
{
    code = std::clamp(code, 0, 2);

    if (m_twinPeakEnabled && code != 0) {
        setActionStatus(
            QStringLiteral(
                "Desactive Twin Peak antes de cambiar SHIFT"
            )
        );
        return;
    }

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x00));
    payload.append(char(0x40));
    payload.append(char(code));

    queueProtectedWrite(
        WriteKind::RttyShiftWidth,
        payload,
        QStringLiteral("RTTY SHIFT %1")
            .arg(rttyShiftName(code)),
        QueryKind::RttyShiftWidth,
        code
    );
}

void RadioController::setRttyKeyingReverse(bool reversed)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x00));
    payload.append(char(0x41));
    payload.append(char(reversed ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::RttyKeyingPolarity,
        payload,
        reversed ? QStringLiteral("RTTY Keying Reverse")
                 : QStringLiteral("RTTY Keying Normal"),
        QueryKind::RttyKeyingPolarity,
        reversed ? 1 : 0
    );
}

void RadioController::refreshToneRttySettings()
{
    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("Conecte la radio para leer TONE / RTTY")
        );
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(
            QStringLiteral("Espere a que termine la orden CI-V actual")
        );
        return;
    }

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    m_cwRefreshQueries.enqueue(QueryKind::RepeaterTone);
    m_cwRefreshQueries.enqueue(QueryKind::ToneSquelch);
    m_cwRefreshQueries.enqueue(QueryKind::RepeaterToneFrequency);
    m_cwRefreshQueries.enqueue(QueryKind::ToneSquelchFrequency);
    m_cwRefreshQueries.enqueue(QueryKind::TwinPeak);
    m_cwRefreshQueries.enqueue(QueryKind::RttyMarkFrequency);
    m_cwRefreshQueries.enqueue(QueryKind::RttyShiftWidth);
    m_cwRefreshQueries.enqueue(QueryKind::RttyKeyingPolarity);

    m_manualRefreshCompletionText =
        QStringLiteral("Configuración TONE / RTTY actualizada");
    m_cwRefreshActive = true;
    setActionStatus(
        QStringLiteral("Leyendo configuración TONE / RTTY…")
    );

    if (m_pendingQuery == QueryKind::None) {
        sendNextCwRefreshQuery();
    }
}


void RadioController::readMemoryChannel(int channel)
{
    readMemoryRange(channel, 1);
}

void RadioController::readMemoryRange(int firstChannel, int count)
{
    firstChannel = std::clamp(firstChannel, 1, 99);
    count = std::clamp(count, 1, 99 - firstChannel + 1);

    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (!m_txStateKnown || m_transmitting) {
        deferMemoryRead(
            firstChannel,
            count,
            false
        );
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    // Se detiene el sondeo periódico para reservar el enlace CI-V.
    // Si ya había una consulta ordinaria pendiente, la dejamos terminar;
    // acknowledgePendingQuery() iniciará después la cola de memorias.
    m_pollTimer.stop();

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    for (int channel = firstChannel;
         channel < firstChannel + count;
         ++channel) {
        m_memoryReadQueue.enqueue(channel);
    }

    const bool memoryReadWasActive = m_memoryReadBatchActive;
    m_memoryReadBatchActive = true;
    if (!memoryReadWasActive) emit memoryReadActiveChanged();
    m_memoryReadRequestedCount = count;
    m_memoryReadSuccessCount = 0;
    m_memoryReadFailureCount = 0;

    m_manualRefreshCompletionText =
        count == 1
        ? QStringLiteral("Memoria M%1 actualizada")
              .arg(firstChannel, 2, 10, QLatin1Char('0'))
        : QStringLiteral("Memorias M%1–M%2 actualizadas")
              .arg(firstChannel, 2, 10, QLatin1Char('0'))
              .arg(firstChannel + count - 1,
                   2,
                   10,
                   QLatin1Char('0'));

    m_cwRefreshActive = true;
    setActionStatus(
        m_pendingQuery == QueryKind::None
        ? QStringLiteral("Leyendo memorias…")
        : QStringLiteral(
              "Esperando la consulta CI-V actual para leer memorias…"
          )
    );
    sendNextCwRefreshQuery();
}

void RadioController::refreshMemoryScanSettings(int firstChannel)
{
    firstChannel = std::clamp(firstChannel, 1, 99);

    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("Conecte la radio para leer MEM / SCAN")
        );
        return;
    }

    if (!m_txStateKnown || m_transmitting) {
        deferMemoryRead(
            firstChannel,
            99,
            true
        );
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    m_pollTimer.stop();

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    m_cwRefreshQueries.enqueue(QueryKind::ScanSpeed);
    m_cwRefreshQueries.enqueue(QueryKind::ScanResume);

    // MEM/SCAN mantiene una lista única de los 99 canales. Al actualizar,
    // se leen todos de forma secuencial reservando temporalmente el enlace
    // CI-V para que el sondeo periódico no interfiera.
    for (int channel = 1; channel <= 99; ++channel) {
        m_memoryReadQueue.enqueue(channel);
    }

    const bool memoryReadWasActive = m_memoryReadBatchActive;
    m_memoryReadBatchActive = true;
    if (!memoryReadWasActive) emit memoryReadActiveChanged();
    m_memoryReadRequestedCount = 99;
    m_memoryReadSuccessCount = 0;
    m_memoryReadFailureCount = 0;

    m_manualRefreshCompletionText =
        QStringLiteral("MEM / SCAN · 99 memorias actualizadas");
    m_cwRefreshActive = true;
    setActionStatus(
        m_pendingQuery == QueryKind::None
        ? QStringLiteral("Leyendo las 99 memorias y el escáner…")
        : QStringLiteral(
              "Esperando la consulta CI-V actual para leer MEM / SCAN…"
          )
    );
    sendNextCwRefreshQuery();
}

void RadioController::selectMemoryChannel(int channel)
{
    if (channel < 1 || channel > 99) {
        setActionStatus(
            QStringLiteral("Canal de memoria no válido")
        );
        return;
    }

    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("La radio no está conectada")
        );
        return;
    }

    if (m_scanActive) {
        setActionStatus(
            QStringLiteral(
                "Detenga el escaneo antes de seleccionar una memoria"
            )
        );
        return;
    }

    // No interrumpir una escritura persistente. Las consultas y la lectura
    // masiva sí se cancelan porque IR es una operación de navegación.
    if (m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_safetyCheckActive) {
        setActionStatus(
            QStringLiteral(
                "Espere: hay una modificación de la radio en curso"
            )
        );
        return;
    }

    if (!m_memoryModeActive
        && !m_memoryVfoSnapshot.valid) {
        captureMemoryReturnState();
    }

    m_pendingDirectMemoryChannel = channel;

    cancelManualReadForMemorySelection();
    m_pollTimer.stop();

    // Las tramas reales han demostrado que 1C 00 devuelve 01: la radio está
    // transmitiendo. En ese estado los botones anteriores no generaban el
    // clic. Ahora IR permanece disponible y fuerza primero la recepción.
    if (m_transmitting) {
        if (!sendMemoryReceiveStage(channel)) {
            m_pendingDirectMemoryChannel = 0;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }
        }
        return;
    }

    if (!sendMemoryModeStage(channel)) {
        m_pendingDirectMemoryChannel = 0;

        if (m_serial.isOpen()
            && !m_pollTimer.isActive()) {
            m_pollTimer.start();
        }
    }
}

void RadioController::toggleMemoryChannel(
    int channel
)
{
    if (m_memoryModeActive
        && m_selectedMemoryChannel == channel) {
        returnToPreviousVfo();
        return;
    }

    selectMemoryChannel(channel);
}

void RadioController::captureMemoryReturnState()
{
    const int vfo =
        m_selectedVfo == 1 ? 1 : 0;

    m_memoryVfoSnapshot.valid = true;
    m_memoryVfoSnapshot.selectedVfo = vfo;
    m_memoryVfoSnapshot.vfoState =
        m_vfoStates[vfo];

    // Si el sondeo de VFO todavía no ha rellenado el estado, conservar
    // igualmente la información que se muestra actualmente.
    if (!m_memoryVfoSnapshot.vfoState.frequencyValid
        && m_frequencyHz != 0) {
        m_memoryVfoSnapshot.vfoState.frequencyHz =
            m_frequencyHz;
        m_memoryVfoSnapshot.vfoState.frequencyValid =
            true;
    }

    if (!m_memoryVfoSnapshot.vfoState.modeValid
        && m_modeCode != 0xFF) {
        m_memoryVfoSnapshot.vfoState.modeCode =
            m_modeCode;
        m_memoryVfoSnapshot.vfoState.filterCode =
            m_filterCode;
        m_memoryVfoSnapshot.vfoState.dataMode =
            m_dataMode;
        m_memoryVfoSnapshot.vfoState.modeValid =
            true;
    }

    m_memoryVfoSnapshot.splitEnabled =
        m_splitEnabled;
    m_memoryVfoSnapshot.ritOffsetHz =
        m_ritOffsetHz;
    m_memoryVfoSnapshot.ritEnabled =
        m_ritEnabled;
    m_memoryVfoSnapshot.deltaTxEnabled =
        m_deltaTxEnabled;

    m_memoryVfoSnapshot.repeaterToneEnabled =
        m_repeaterToneEnabled;
    m_memoryVfoSnapshot.toneSquelchEnabled =
        m_toneSquelchEnabled;
    m_memoryVfoSnapshot.repeaterToneTenthsHz =
        m_repeaterToneTenthsHz;
    m_memoryVfoSnapshot.toneSquelchTenthsHz =
        m_toneSquelchTenthsHz;

    emit memoryModeChanged();
}

void RadioController::clearMemoryReturnState()
{
    const bool changed =
        m_memoryVfoSnapshot.valid
        || m_directMemoryReturnInProgress;

    m_memoryVfoSnapshot =
        MemoryVfoSnapshot{};
    m_directMemoryReturnInProgress = false;

    if (changed) {
        emit memoryModeChanged();
    }
}

void RadioController::restoreMemoryReturnStateLocally()
{
    if (!m_memoryVfoSnapshot.valid) {
        return;
    }

    const int vfo =
        m_memoryVfoSnapshot.selectedVfo == 1
        ? 1
        : 0;

    m_vfoStates[vfo] =
        m_memoryVfoSnapshot.vfoState;
    emitVfoStateSignal(vfo);

    updateVfo(vfo);
    syncActiveStateFromSelectedVfo();

    bool splitChangedValue = false;
    bool ritChangedValue = false;
    bool deltaChangedValue = false;
    bool toneChangedValue = false;

    if (m_splitEnabled
        != m_memoryVfoSnapshot.splitEnabled) {
        m_splitEnabled =
            m_memoryVfoSnapshot.splitEnabled;
        splitChangedValue = true;
    }

    if (m_ritOffsetHz
            != m_memoryVfoSnapshot.ritOffsetHz
        || m_ritEnabled
            != m_memoryVfoSnapshot.ritEnabled) {
        m_ritOffsetHz =
            m_memoryVfoSnapshot.ritOffsetHz;
        m_ritEnabled =
            m_memoryVfoSnapshot.ritEnabled;
        ritChangedValue = true;
    }

    if (m_deltaTxEnabled
        != m_memoryVfoSnapshot.deltaTxEnabled) {
        m_deltaTxEnabled =
            m_memoryVfoSnapshot.deltaTxEnabled;
        deltaChangedValue = true;
    }

    if (m_repeaterToneEnabled
            != m_memoryVfoSnapshot
               .repeaterToneEnabled
        || m_toneSquelchEnabled
            != m_memoryVfoSnapshot
               .toneSquelchEnabled
        || m_repeaterToneTenthsHz
            != m_memoryVfoSnapshot
               .repeaterToneTenthsHz
        || m_toneSquelchTenthsHz
            != m_memoryVfoSnapshot
               .toneSquelchTenthsHz) {
        m_repeaterToneEnabled =
            m_memoryVfoSnapshot
            .repeaterToneEnabled;
        m_toneSquelchEnabled =
            m_memoryVfoSnapshot
            .toneSquelchEnabled;
        m_repeaterToneTenthsHz =
            m_memoryVfoSnapshot
            .repeaterToneTenthsHz;
        m_toneSquelchTenthsHz =
            m_memoryVfoSnapshot
            .toneSquelchTenthsHz;
        toneChangedValue = true;
    }

    if (splitChangedValue) {
        emit splitChanged();
    }
    if (ritChangedValue) {
        emit ritChanged();
    }
    if (deltaChangedValue) {
        emit deltaTxChanged();
    }
    if (toneChangedValue) {
        emit toneRttyChanged();
    }
}

void RadioController::returnToPreviousVfo()
{
    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("La radio no está conectada")
        );
        return;
    }

    if (!m_memoryModeActive) {
        setActionStatus(
            QStringLiteral("La radio ya está en VFO")
        );
        return;
    }

    if (!m_memoryVfoSnapshot.valid) {
        setActionStatus(
            QStringLiteral(
                "No se conoce el VFO anterior"
            )
        );
        return;
    }

    if (m_scanActive) {
        setActionStatus(
            QStringLiteral(
                "Detenga el escaneo antes de volver al VFO"
            )
        );
        return;
    }

    if (m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_safetyCheckActive) {
        setActionStatus(
            QStringLiteral(
                "Espere: hay una operación de la radio en curso"
            )
        );
        return;
    }

    const int vfo =
        m_memoryVfoSnapshot.selectedVfo == 1
        ? 1
        : 0;

    m_directMemoryReturnInProgress = true;

    cancelManualReadForMemorySelection();
    m_pollTimer.stop();

    if (m_transmitting) {
        if (!sendMemoryReturnReceiveStage(vfo)) {
            m_directMemoryReturnInProgress = false;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }
        }
        return;
    }

    if (!sendMemoryReturnStage(vfo)) {
        m_directMemoryReturnInProgress = false;

        if (m_serial.isOpen()
            && !m_pollTimer.isActive()) {
            m_pollTimer.start();
        }
    }
}

bool RadioController::sendMemoryReturnReceiveStage(
    int vfoNumber
)
{
    if (!m_serial.isOpen()
        || vfoNumber < 0
        || vfoNumber > 1) {
        return false;
    }

    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x00));
    payload.append(char(0x00));

    m_activeWriteKind =
        WriteKind::MemoryReturnReceive;
    m_activeWriteLabel =
        QStringLiteral("Pasar a RX antes de volver a %1")
            .arg(
                vfoNumber == 1
                ? QStringLiteral("VFO B")
                : QStringLiteral("VFO A")
            );
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = vfoNumber;

    setBusy(true);
    setActionStatus(
        QStringLiteral(
            "Volviendo a %1 · pasando primero a RX…"
        )
            .arg(
                vfoNumber == 1
                ? QStringLiteral("VFO B")
                : QStringLiteral("VFO A")
            )
    );

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeDesiredValue = 0;
        setBusy(false);
        return false;
    }

    m_responseTimer.start();
    return true;
}

bool RadioController::sendMemoryReturnStage(
    int vfoNumber
)
{
    if (!m_serial.isOpen()
        || vfoNumber < 0
        || vfoNumber > 1) {
        return false;
    }

    const QByteArray payload =
        vfoNumber == 1
        ? QByteArray::fromHex("0701")
        : QByteArray::fromHex("0700");

    m_activeWriteKind =
        WriteKind::MemoryReturnVfo;
    m_activeWriteLabel =
        QStringLiteral("Volver a %1")
            .arg(
                vfoNumber == 1
                ? QStringLiteral("VFO B")
                : QStringLiteral("VFO A")
            );
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = vfoNumber;

    setBusy(true);
    setActionStatus(
        QStringLiteral("Restaurando %1…")
            .arg(
                vfoNumber == 1
                ? QStringLiteral("VFO B")
                : QStringLiteral("VFO A")
            )
    );

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeDesiredValue = 0;
        setBusy(false);
        return false;
    }

    m_responseTimer.start();
    return true;
}

void RadioController::refreshAfterMemoryReturn()
{
    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    m_cwRefreshQueries.enqueue(
        QueryKind::Frequency);
    m_cwRefreshQueries.enqueue(
        QueryKind::Mode);
    m_cwRefreshQueries.enqueue(
        QueryKind::DataMode);
    m_cwRefreshQueries.enqueue(
        QueryKind::VfoSelectedFrequency);
    m_cwRefreshQueries.enqueue(
        QueryKind::VfoUnselectedFrequency);
    m_cwRefreshQueries.enqueue(
        QueryKind::VfoSelectedMode);
    m_cwRefreshQueries.enqueue(
        QueryKind::VfoUnselectedMode);

    m_cwRefreshQueries.enqueue(
        QueryKind::Split);
    m_cwRefreshQueries.enqueue(
        QueryKind::RitOffset);
    m_cwRefreshQueries.enqueue(
        QueryKind::RitEnabled);
    m_cwRefreshQueries.enqueue(
        QueryKind::DeltaTxEnabled);

    m_cwRefreshQueries.enqueue(
        QueryKind::Preamp);
    m_cwRefreshQueries.enqueue(
        QueryKind::Attenuator);
    m_cwRefreshQueries.enqueue(
        QueryKind::Agc);
    m_cwRefreshQueries.enqueue(
        QueryKind::NoiseBlanker);
    m_cwRefreshQueries.enqueue(
        QueryKind::NoiseBlankerLevel);
    m_cwRefreshQueries.enqueue(
        QueryKind::NoiseReduction);
    m_cwRefreshQueries.enqueue(
        QueryKind::NoiseReductionLevel);
    m_cwRefreshQueries.enqueue(
        QueryKind::AutoNotch);
    m_cwRefreshQueries.enqueue(
        QueryKind::ManualNotch);
    m_cwRefreshQueries.enqueue(
        QueryKind::ManualNotchPosition);
    m_cwRefreshQueries.enqueue(
        QueryKind::ManualNotchWidth);
    m_cwRefreshQueries.enqueue(
        QueryKind::Pbt1);
    m_cwRefreshQueries.enqueue(
        QueryKind::Pbt2);
    m_cwRefreshQueries.enqueue(
        QueryKind::IpPlus);
    m_cwRefreshQueries.enqueue(
        QueryKind::FilterShape);

    m_cwRefreshQueries.enqueue(
        QueryKind::RepeaterTone);
    m_cwRefreshQueries.enqueue(
        QueryKind::ToneSquelch);
    m_cwRefreshQueries.enqueue(
        QueryKind::RepeaterToneFrequency);
    m_cwRefreshQueries.enqueue(
        QueryKind::ToneSquelchFrequency);

    m_manualRefreshCompletionText =
        QStringLiteral(
            "VFO y opciones anteriores restaurados"
        );
    m_cwRefreshActive = true;

    QTimer::singleShot(
        80,
        this,
        &RadioController::sendNextCwRefreshQuery
    );
}

void RadioController::cancelManualReadForMemorySelection()
{
    m_pollTimer.stop();
    m_responseTimer.stop();

    m_pendingQuery = QueryKind::None;
    m_safetyCheckActive = false;

    m_cwRefreshActive = false;
    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    m_pendingKeyerMemoryChannel = 0;
    m_pendingMemoryReadChannel = 0;
    m_pendingBandStackingRequest = BandStackingRequest{};

    const bool memoryReadWasActive = m_memoryReadBatchActive;
    m_memoryReadBatchActive = false;
    if (memoryReadWasActive) emit memoryReadActiveChanged();
    m_memoryReadRequestedCount = 0;
    m_memoryReadSuccessCount = 0;
    m_memoryReadFailureCount = 0;

    setBusy(false);
}

bool RadioController::sendMemoryReceiveStage(
    int channel
)
{
    if (!m_serial.isOpen()
        || channel < 1
        || channel > 99) {
        return false;
    }

    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x00));
    payload.append(char(0x00));

    m_activeWriteKind = WriteKind::MemoryReceive;
    m_activeWriteLabel =
        QStringLiteral("Pasar a RX antes de M%1")
            .arg(channel, 2, 10, QLatin1Char('0'));
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = channel;

    setBusy(true);
    setActionStatus(
        QStringLiteral(
            "IR M%1 · la radio está en TX · enviando 1C 00 00…"
        )
            .arg(channel, 2, 10, QLatin1Char('0'))
    );

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeDesiredValue = 0;
        setBusy(false);
        return false;
    }

    m_responseTimer.start();
    return true;
}

bool RadioController::sendMemoryModeStage(
    int channel
)
{
    if (!m_serial.isOpen()
        || channel < 1
        || channel > 99) {
        return false;
    }

    m_activeWriteKind = WriteKind::MemoryMode;
    m_activeWriteLabel =
        QStringLiteral("Entrar en modo memoria");
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = channel;

    setBusy(true);
    setActionStatus(
        QStringLiteral(
            "IR M%1 · enviando 08…"
        )
            .arg(channel, 2, 10, QLatin1Char('0'))
    );

    const QByteArray payload(1, char(0x08));

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeDesiredValue = 0;
        setBusy(false);
        return false;
    }

    m_responseTimer.start();
    return true;
}

bool RadioController::sendMemorySelectionStage(
    int channel
)
{
    if (!m_serial.isOpen()
        || channel < 1
        || channel > 99) {
        return false;
    }

    QByteArray payload;
    payload.append(char(0x08));
    payload.append(encodeMemoryChannel(channel));

    m_activeWriteKind = WriteKind::MemorySelect;
    m_activeWriteLabel =
        QStringLiteral("Seleccionar M%1")
            .arg(channel, 2, 10, QLatin1Char('0'));
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = channel;

    setBusy(true);
    setActionStatus(
        QStringLiteral(
            "IR M%1 · enviando 08 00 %2…"
        )
            .arg(channel, 2, 10, QLatin1Char('0'))
            .arg(
                channel,
                2,
                10,
                QLatin1Char('0')
            )
    );

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeDesiredValue = 0;
        setBusy(false);
        return false;
    }

    m_responseTimer.start();
    return true;
}

void RadioController::storeDisplayedToMemory(int channel)
{
    beginMemorySequence(MemorySequenceAction::Store, channel);
}

void RadioController::copyMemoryToVfo(int channel)
{
    beginMemorySequence(MemorySequenceAction::CopyToVfo, channel);
}

void RadioController::clearMemoryChannel(int channel)
{
    beginMemorySequence(MemorySequenceAction::Clear, channel);
}

void RadioController::renameMemoryChannel(
    int channel,
    const QString &name
)
{
    if (channel < 1 || channel > 99) {
        setActionStatus(QStringLiteral("Canal de memoria no válido"));
        return;
    }

    if (m_scanActive) {
        setActionStatus(
            QStringLiteral("Detenga el escaneo antes de modificar memorias")
        );
        return;
    }

    const MemoryState &memory = m_memories.at(channel - 1);
    if (!memory.loaded) {
        setActionStatus(
            QStringLiteral("Lea M%1 antes de cambiar el nombre")
                .arg(channel, 2, 10, QLatin1Char('0'))
        );
        return;
    }
    if (memory.blank || memory.raw.size() < 47) {
        setActionStatus(QStringLiteral("No se puede nombrar una memoria vacía"));
        return;
    }

    QByteArray encodedName;
    QString errorText;
    if (!validateMemoryName(name, encodedName, errorText)) {
        setActionStatus(errorText);
        return;
    }

    QByteArray raw = memory.raw;
    for (int index = 0; index < 16; ++index) {
        raw[31 + index] =
            index < encodedName.size()
            ? encodedName.at(index)
            : char(0x20);
    }

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x00));
    payload.append(raw);

    queueProtectedWrite(
        WriteKind::MemoryRename,
        payload,
        QStringLiteral("Renombrar M%1")
            .arg(channel, 2, 10, QLatin1Char('0')),
        QueryKind::None,
        channel
    );
}


bool RadioController::queueMemoryEditWhenReady(
    int channel,
    const QVariantMap &values,
    int attempt
)
{
    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("La radio no está conectada")
        );
        return false;
    }

    if (attempt > 20) {
        setActionStatus(
            QStringLiteral(
                "No se pudo reservar el enlace CI-V para editar M%1"
            )
                .arg(channel, 2, 10, QLatin1Char('0'))
        );
        return false;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_safetyCheckActive
        || m_pendingQuery != QueryKind::None) {
        setActionStatus(
            QStringLiteral(
                "Esperando a que quede libre el enlace CI-V para M%1…"
            )
                .arg(channel, 2, 10, QLatin1Char('0'))
        );

        QTimer::singleShot(
            120,
            this,
            [this, channel, values, attempt]() {
                queueMemoryEditWhenReady(
                    channel,
                    values,
                    attempt + 1
                );
            }
        );
        return true;
    }

    return updateMemoryChannel(channel, values);
}

bool RadioController::updateMemoryChannel(
    int channel,
    const QVariantMap &values
)
{
    if (channel < 1 || channel > 99) {
        setActionStatus(QStringLiteral("Canal de memoria no válido"));
        return false;
    }
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return false;
    }
    if (m_scanActive) {
        setActionStatus(QStringLiteral("Detenga el escaneo antes de editar memorias"));
        return false;
    }
    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_safetyCheckActive
        || m_pendingQuery != QueryKind::None) {
        return queueMemoryEditWhenReady(
            channel,
            values,
            0
        );
    }

    // Una lectura de memorias es una operación pasiva. Al aplicar cambios,
    // se cancela y se reserva inmediatamente el enlace para la escritura.
    if (m_cwRefreshActive
        || m_memoryReadBatchActive) {
        cancelManualReadForMemorySelection();
        setActionStatus(
            QStringLiteral(
                "Lectura de memorias detenida · preparando la escritura…"
            )
        );
    }
    if (m_transmitting) {
        setActionStatus(QStringLiteral("No se puede editar una memoria mientras la radio transmite"));
        return false;
    }

    const MemoryState &memory = m_memories.at(channel - 1);
    if (!memory.loaded) {
        setActionStatus(QStringLiteral("Lea M%1 antes de editarla")
                            .arg(channel, 2, 10, QLatin1Char('0')));
        return false;
    }
    if (memory.blank || memory.raw.size() < 47) {
        setActionStatus(QStringLiteral("M%1 está vacía: use primero «Guardar estado actual»")
                            .arg(channel, 2, 10, QLatin1Char('0')));
        return false;
    }

    QByteArray encodedName;
    QString errorText;
    if (!validateMemoryName(values.value(QStringLiteral("name")).toString(),
                            encodedName, errorText)) {
        setActionStatus(errorText);
        return false;
    }

    quint64 receiveFrequencyHz = 0;
    if (!parseFrequency(values.value(QStringLiteral("receiveFrequency")).toString(),
                        receiveFrequencyHz, errorText)) {
        setActionStatus(QStringLiteral("RX: %1").arg(errorText));
        return false;
    }
    quint64 transmitFrequencyHz = 0;
    if (!parseFrequency(values.value(QStringLiteral("transmitFrequency")).toString(),
                        transmitFrequencyHz, errorText)) {
        setActionStatus(QStringLiteral("TX: %1").arg(errorText));
        return false;
    }

    const quint8 receiveMode = modeCodeForName(
        values.value(QStringLiteral("receiveMode")).toString());
    const quint8 transmitMode = modeCodeForName(
        values.value(QStringLiteral("transmitMode")).toString());
    if (receiveMode == 0xFF || transmitMode == 0xFF) {
        setActionStatus(QStringLiteral("Modo RX o TX no válido"));
        return false;
    }

    const int receiveFilter = std::clamp(
        values.value(QStringLiteral("receiveFilter"), 1).toInt(), 1, 3);
    const int transmitFilter = std::clamp(
        values.value(QStringLiteral("transmitFilter"), 1).toInt(), 1, 3);
    const bool receiveData = values.value(QStringLiteral("receiveData")).toBool();
    const bool transmitData = values.value(QStringLiteral("transmitData")).toBool();
    if (receiveData && !modeSupportsData(receiveMode)) {
        setActionStatus(QStringLiteral("DATA RX no es compatible con el modo elegido"));
        return false;
    }
    if (transmitData && !modeSupportsData(transmitMode)) {
        setActionStatus(QStringLiteral("DATA TX no es compatible con el modo elegido"));
        return false;
    }

    const int receiveToneType = std::clamp(
        values.value(QStringLiteral("receiveToneType"), 0).toInt(), 0, 2);
    const int transmitToneType = std::clamp(
        values.value(QStringLiteral("transmitToneType"), 0).toInt(), 0, 2);
    const int repeaterToneTenthsHz = std::clamp(
        values.value(QStringLiteral("repeaterToneTenthsHz"), 885).toInt(), 0, 2999);
    const int toneSquelchTenthsHz = std::clamp(
        values.value(QStringLiteral("toneSquelchTenthsHz"), 885).toInt(), 0, 2999);
    const bool split = values.value(QStringLiteral("split")).toBool();
    const int selectGroup = std::clamp(
        values.value(QStringLiteral("selectGroup"), 0).toInt(), 0, 3);

    QByteArray raw = memory.raw.left(47);
    if (raw.size() < 47) raw.append(QByteArray(47 - raw.size(), char(0x20)));

    raw[2] = char((split ? 0x10 : 0x00) | selectGroup);
    raw.replace(3, 5, encodeFrequency(receiveFrequencyHz));
    raw[8] = char(receiveMode);
    raw[9] = char(receiveFilter);
    raw[10] = char((receiveData ? 0x10 : 0x00) | receiveToneType);
    raw.replace(11, 3, encodeToneFrequency(repeaterToneTenthsHz));
    raw.replace(14, 3, encodeToneFrequency(toneSquelchTenthsHz));

    raw.replace(17, 5, encodeFrequency(transmitFrequencyHz));
    raw[22] = char(transmitMode);
    raw[23] = char(transmitFilter);
    raw[24] = char((transmitData ? 0x10 : 0x00) | transmitToneType);
    raw.replace(25, 3, encodeToneFrequency(repeaterToneTenthsHz));
    raw.replace(28, 3, encodeToneFrequency(toneSquelchTenthsHz));

    for (int index = 0; index < 16; ++index) {
        raw[31 + index] = index < encodedName.size()
            ? encodedName.at(index) : char(0x20);
    }

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x00));
    payload.append(raw);

    queueProtectedWrite(WriteKind::MemoryEdit, payload,
        QStringLiteral("Editar M%1").arg(channel, 2, 10, QLatin1Char('0')),
        QueryKind::None, channel);

    if (m_queuedWriteKind != WriteKind::MemoryEdit) return false;

    m_memoryEditVerifyChannel = channel;
    m_memoryEditExpectedRaw = raw;
    m_memoryEditVerifyAttempt = 0;
    setActionStatus(
        QStringLiteral(
            "Enviando los campos editados de M%1 mediante 1A 00…"
        )
            .arg(channel, 2, 10, QLatin1Char('0'))
    );
    return true;
}


void RadioController::scheduleMemoryEditVerification(int delayMs)
{
    if (m_memoryEditVerifyChannel < 1 || m_memoryEditVerifyChannel > 99
        || m_memoryEditExpectedRaw.size() != 47) return;

    QTimer::singleShot(std::max(0, delayMs), this, [this]() {
        if (m_memoryEditVerifyChannel < 1 || m_memoryEditVerifyChannel > 99
            || m_memoryEditExpectedRaw.size() != 47 || !m_serial.isOpen()) return;

        if (m_busy || m_activeWriteKind != WriteKind::None
            || m_queuedWriteKind != WriteKind::None
            || m_pendingQuery != QueryKind::None
            || m_cwRefreshActive || m_memoryReadBatchActive) {
            scheduleMemoryEditVerification(180);
            return;
        }

        ++m_memoryEditVerifyAttempt;
        setActionStatus(QStringLiteral("Verificando M%1 en la radio · intento %2/3…")
            .arg(m_memoryEditVerifyChannel, 2, 10, QLatin1Char('0'))
            .arg(std::min(3, m_memoryEditVerifyAttempt)));
        readMemoryChannel(m_memoryEditVerifyChannel);
    });
}

void RadioController::setMemorySelectGroup(int channel, int group)
{
    group = std::clamp(group, 0, 3);
    beginMemorySequence(
        MemorySequenceAction::SelectGroup,
        channel,
        group
    );
}

void RadioController::startContextScan()
{
    queueScanCommand(
        0x01,
        QStringLiteral("Escaneo automático"),
        true
    );
}

void RadioController::startProgrammedScan(bool fine)
{
    queueScanCommand(
        fine ? 0x12 : 0x02,
        fine ? QStringLiteral("Escaneo fino programado")
             : QStringLiteral("Escaneo programado"),
        true
    );
}

void RadioController::startMemoryScan()
{
    queueScanCommand(
        0x22,
        QStringLiteral("Escaneo de memorias"),
        true
    );
}

void RadioController::startSelectMemoryScan()
{
    queueScanCommand(
        0x23,
        QStringLiteral("Escaneo de memorias seleccionadas"),
        true
    );
}

void RadioController::startDeltaScan(bool fine)
{
    queueScanCommand(
        fine ? 0x13 : 0x03,
        fine ? QStringLiteral("Escaneo fino ΔF")
             : QStringLiteral("Escaneo ΔF"),
        true
    );
}

void RadioController::stopScan()
{
    queueScanCommand(
        0x00,
        QStringLiteral("Detener escaneo"),
        false
    );
}

void RadioController::setScanSpeedFast(bool fast)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x53));
    payload.append(char(fast ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::ScanSpeed,
        payload,
        fast ? QStringLiteral("Velocidad de escaneo rápida")
             : QStringLiteral("Velocidad de escaneo lenta"),
        QueryKind::ScanSpeed,
        fast ? 1 : 0
    );
}

void RadioController::setScanResumeEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x05));
    payload.append(char(0x02));
    payload.append(char(0x54));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::ScanResume,
        payload,
        enabled ? QStringLiteral("SCAN Resume ON")
                : QStringLiteral("SCAN Resume OFF"),
        QueryKind::ScanResume,
        enabled ? 1 : 0
    );
}

void RadioController::setScanSelectGroup(int group)
{
    group = std::clamp(group, 0, 3);

    QByteArray payload;
    payload.append(char(0x0E));
    payload.append(char(0xB2));
    payload.append(char(group));

    queueProtectedWrite(
        WriteKind::ScanSelectGroup,
        payload,
        group == 0
            ? QStringLiteral("Escanear todos los grupos SEL")
            : QStringLiteral("Escanear solo SEL%1").arg(group),
        QueryKind::None,
        group
    );
}

void RadioController::setDeltaScanSpanCode(int code)
{
    code = std::clamp(code, 1, 7);

    QByteArray payload;
    payload.append(char(0x0E));
    payload.append(char(0xA0 | code));

    queueProtectedWrite(
        WriteKind::DeltaScanSpan,
        payload,
        QStringLiteral("Span ΔF %1")
            .arg([code]() {
                switch (code) {
                case 2: return QStringLiteral("±10 kHz");
                case 3: return QStringLiteral("±20 kHz");
                case 4: return QStringLiteral("±50 kHz");
                case 5: return QStringLiteral("±100 kHz");
                case 6: return QStringLiteral("±500 kHz");
                case 7: return QStringLiteral("±1 MHz");
                default: return QStringLiteral("±5 kHz");
                }
            }()),
        QueryKind::None,
        code
    );
}


void RadioController::readBandStackingBand(int bandCode)
{
    bandCode = std::clamp(bandCode, 1, 11);

    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_pendingQuery != QueryKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    for (int registerCode = 1;
         registerCode <= 3;
         ++registerCode) {
        BandStackingRequest request;
        request.bandCode = bandCode;
        request.registerCode = registerCode;
        m_bandStackingReadQueue.enqueue(request);
    }

    m_manualRefreshCompletionText =
        QStringLiteral("Registros de %1 actualizados")
            .arg(bandStackingName(bandCode));
    m_cwRefreshActive = true;
    setActionStatus(
        QStringLiteral("Leyendo registros de apilamiento…")
    );
    sendNextCwRefreshQuery();
}

void RadioController::readAllBandStacking()
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_pendingQuery != QueryKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden actual"));
        return;
    }

    m_cwRefreshQueries.clear();
    m_keyerReadQueue.clear();
    m_memoryReadQueue.clear();
    m_bandStackingReadQueue.clear();

    for (int bandCode = 1; bandCode <= 11; ++bandCode) {
        for (int registerCode = 1;
             registerCode <= 3;
             ++registerCode) {
            BandStackingRequest request;
            request.bandCode = bandCode;
            request.registerCode = registerCode;
            m_bandStackingReadQueue.enqueue(request);
        }
    }

    m_manualRefreshCompletionText =
        QStringLiteral("Registros de apilamiento actualizados");
    m_cwRefreshActive = true;
    setActionStatus(
        QStringLiteral("Leyendo los 33 registros de apilamiento…")
    );
    sendNextCwRefreshQuery();
}

void RadioController::storeCurrentToBandStacking(
    int bandCode,
    int registerCode
)
{
    bandCode = std::clamp(bandCode, 1, 11);
    registerCode = std::clamp(registerCode, 1, 3);

    if (m_frequencyHz == 0 || m_modeCode == 0xFF) {
        setActionStatus(
            QStringLiteral("Todavía no se conoce el estado del VFO")
        );
        return;
    }

    if (m_scanActive) {
        setActionStatus(
            QStringLiteral("Detenga el escaneo antes de guardar registros")
        );
        return;
    }

    const int toneType =
        m_toneSquelchEnabled ? 2
        : m_repeaterToneEnabled ? 1
        : 0;

    QByteArray payload;
    payload.append(char(0x1A));
    payload.append(char(0x01));
    payload.append(char(bandCode));
    payload.append(char(registerCode));
    payload.append(encodeFrequency(m_frequencyHz));
    payload.append(char(m_modeCode));
    payload.append(char(
        m_filterCode >= 1 && m_filterCode <= 3
        ? m_filterCode
        : 0x01
    ));
    payload.append(char(
        (m_dataMode ? 0x10 : 0x00)
        | toneType
    ));
    payload.append(encodeToneFrequency(m_repeaterToneTenthsHz));
    payload.append(encodeToneFrequency(m_toneSquelchTenthsHz));

    queueProtectedWrite(
        WriteKind::BandStacking,
        payload,
        QStringLiteral("Guardar %1 · registro %2")
            .arg(bandStackingName(bandCode))
            .arg(registerCode),
        QueryKind::None,
        bandCode * 10 + registerCode
    );
}

void RadioController::beginMemorySequence(
    MemorySequenceAction action,
    int channel,
    int group
)
{
    if (channel < 1 || channel > 99) {
        setActionStatus(QStringLiteral("Canal de memoria no válido"));
        return;
    }

    if (m_scanActive) {
        setActionStatus(
            QStringLiteral("Detenga el escaneo antes de usar memorias")
        );
        return;
    }

    if (m_memorySequenceAction != MemorySequenceAction::None) {
        setActionStatus(QStringLiteral("Ya hay una operación de memoria activa"));
        return;
    }

    m_memorySequenceAction = action;
    m_memorySequenceChannel = channel;
    m_memorySequenceGroup = std::clamp(group, 0, 3);
    m_memoryStoreVfoSelected = false;

    QByteArray payload;
    payload.append(char(0x08));
    payload.append(encodeMemoryChannel(channel));

    queueProtectedWrite(
        WriteKind::MemorySelect,
        payload,
        QStringLiteral("Seleccionar M%1")
            .arg(channel, 2, 10, QLatin1Char('0')),
        QueryKind::None,
        channel
    );

    if (m_queuedWriteKind != WriteKind::MemorySelect
        && m_activeWriteKind != WriteKind::MemorySelect) {
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
        m_memoryStoreVfoSelected = false;
    }
}

void RadioController::continueMemorySequence()
{
    const int channel = m_memorySequenceChannel;

    switch (m_memorySequenceAction) {
    case MemorySequenceAction::GoTo:
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
        m_memoryStoreVfoSelected = false;

        setActionStatus(
            QStringLiteral("Radio situada en M%1")
                .arg(channel, 2, 10, QLatin1Char('0'))
        );

        // El comando 08 ya ha sido aceptado. Se solicita inmediatamente
        // la frecuencia para que la pantalla de la aplicación refleje el
        // contenido de la memoria sin esperar al siguiente sondeo.
        QTimer::singleShot(
            120,
            this,
            [this]() {
                if (m_serial.isOpen()
                    && m_pendingQuery == QueryKind::None
                    && m_activeWriteKind == WriteKind::None
                    && m_queuedWriteKind == WriteKind::None) {
                    sendQuery(QueryKind::Frequency);
                }
            }
        );
        break;

    case MemorySequenceAction::Store:
        if (!m_memoryStoreVfoSelected) {
            m_memoryStoreVfoSelected = true;
            queueProtectedWrite(
                WriteKind::MemoryReturnVfo,
                m_selectedVfo == 0
                    ? QByteArray::fromHex("0700")
                    : QByteArray::fromHex("0701"),
                QStringLiteral("Volver al VFO antes de guardar M%1")
                    .arg(channel, 2, 10, QLatin1Char('0')),
                QueryKind::None,
                m_selectedVfo
            );
        } else {
            queueProtectedWrite(
                WriteKind::MemoryStore,
                QByteArray(1, char(0x09)),
                QStringLiteral("Guardar contenido actual en M%1")
                    .arg(channel, 2, 10, QLatin1Char('0')),
                QueryKind::None,
                channel
            );
        }
        break;

    case MemorySequenceAction::CopyToVfo:
        queueProtectedWrite(
            WriteKind::MemoryCopyToVfo,
            QByteArray(1, char(0x0A)),
            QStringLiteral("Copiar M%1 al VFO")
                .arg(channel, 2, 10, QLatin1Char('0')),
            QueryKind::None,
            channel
        );
        break;

    case MemorySequenceAction::Clear:
        queueProtectedWrite(
            WriteKind::MemoryClear,
            QByteArray(1, char(0x0B)),
            QStringLiteral("Borrar M%1")
                .arg(channel, 2, 10, QLatin1Char('0')),
            QueryKind::None,
            channel
        );
        break;

    case MemorySequenceAction::SelectGroup: {
        QByteArray payload;
        payload.append(char(0x0E));
        payload.append(
            char(m_memorySequenceGroup == 0 ? 0xB0 : 0xB1)
        );
        if (m_memorySequenceGroup > 0) {
            payload.append(char(m_memorySequenceGroup));
        }

        queueProtectedWrite(
            WriteKind::MemorySelectGroup,
            payload,
            m_memorySequenceGroup == 0
                ? QStringLiteral("Quitar M%1 de grupos SEL")
                      .arg(channel, 2, 10, QLatin1Char('0'))
                : QStringLiteral("Asignar M%1 a SEL%2")
                      .arg(channel, 2, 10, QLatin1Char('0'))
                      .arg(m_memorySequenceGroup),
            QueryKind::None,
            m_memorySequenceGroup
        );
        break;
    }

    case MemorySequenceAction::None:
        break;
    }

    if (m_queuedWriteKind == WriteKind::None
        && m_activeWriteKind == WriteKind::None) {
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
    }
}

void RadioController::queueScanCommand(
    quint8 subcommand,
    const QString &label,
    bool startsScan
)
{
    QByteArray payload;
    payload.append(char(0x0E));
    payload.append(char(subcommand));

    const int desiredValue =
        (startsScan ? 0x100 : 0x000) | int(subcommand);

    queueProtectedWrite(
        WriteKind::ScanControl,
        payload,
        label,
        QueryKind::None,
        desiredValue
    );
}

void RadioController::setPreamp(int value)
{
    value = std::clamp(value, 0, 2);
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x02));
    payload.append(char(value));
    queueProtectedWrite(WriteKind::Preamp, payload,
                        value == 0 ? QStringLiteral("Preamplificador OFF")
                                   : QStringLiteral("P.AMP%1").arg(value),
                        QueryKind::Preamp);
}

void RadioController::setAttenuatorEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x11));
    payload.append(char(enabled ? 0x20 : 0x00));
    queueProtectedWrite(WriteKind::Attenuator, payload,
                        enabled ? QStringLiteral("Atenuador 20 dB")
                                : QStringLiteral("Atenuador OFF"),
                        QueryKind::Attenuator);
}

void RadioController::setAgc(int value)
{
    value = std::clamp(value, 1, 3);
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x12));
    payload.append(char(value));
    queueProtectedWrite(WriteKind::Agc, payload,
                        QStringLiteral("AGC %1")
                            .arg(value == 1 ? QStringLiteral("FAST")
                                            : value == 2 ? QStringLiteral("MID")
                                                         : QStringLiteral("SLOW")),
                        QueryKind::Agc);
}

void RadioController::setTunerEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x01));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(WriteKind::Tuner, payload,
                        enabled ? QStringLiteral("Tuner ON")
                                : QStringLiteral("Tuner OFF"),
                        QueryKind::Tuner);
}

void RadioController::startTuner()
{
    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x01));
    payload.append(char(0x02));
    queueProtectedWrite(WriteKind::TunerStart, payload,
                        QStringLiteral("Inicio de sintonización"),
                        QueryKind::Tuner);
}


void RadioController::setNoiseBlankerEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x22));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(
        WriteKind::NoiseBlanker,
        payload,
        enabled ? QStringLiteral("Noise Blanker ON")
                : QStringLiteral("Noise Blanker OFF"),
        QueryKind::NoiseBlanker
    );
}

void RadioController::setNoiseBlankerLevel(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x12));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(
        WriteKind::NoiseBlankerLevel,
        payload,
        QStringLiteral("Nivel NB %1 %").arg(clampPercent(percent)),
        QueryKind::NoiseBlankerLevel
    );
}

void RadioController::setNoiseReductionEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x40));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(
        WriteKind::NoiseReduction,
        payload,
        enabled ? QStringLiteral("Noise Reduction ON")
                : QStringLiteral("Noise Reduction OFF"),
        QueryKind::NoiseReduction
    );
}

void RadioController::setNoiseReductionLevel(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x06));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(
        WriteKind::NoiseReductionLevel,
        payload,
        QStringLiteral("Nivel NR %1 %").arg(clampPercent(percent)),
        QueryKind::NoiseReductionLevel
    );
}

void RadioController::setAutoNotchEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x41));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(
        WriteKind::AutoNotch,
        payload,
        enabled ? QStringLiteral("Auto Notch ON")
                : QStringLiteral("Auto Notch OFF"),
        QueryKind::AutoNotch
    );
}

void RadioController::setManualNotchEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x48));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(
        WriteKind::ManualNotch,
        payload,
        enabled ? QStringLiteral("Manual Notch ON")
                : QStringLiteral("Manual Notch OFF"),
        QueryKind::ManualNotch
    );
}

void RadioController::setManualNotchPosition(int percent)
{
    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x0D));
    payload.append(encodeLevel(percent));
    queueProtectedWrite(
        WriteKind::ManualNotchPosition,
        payload,
        QStringLiteral("Posición Notch %1 %").arg(clampPercent(percent)),
        QueryKind::ManualNotchPosition
    );
}

void RadioController::setManualNotchWidth(int width)
{
    width = std::clamp(width, 0, 2);

    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x57));
    payload.append(char(width));

    const QString name =
        width == 0 ? QStringLiteral("WIDE")
                   : width == 1 ? QStringLiteral("MID")
                                : QStringLiteral("NAR");

    queueProtectedWrite(
        WriteKind::ManualNotchWidth,
        payload,
        QStringLiteral("Ancho Notch %1").arg(name),
        QueryKind::ManualNotchWidth
    );
}

void RadioController::setPbt1(int percent)
{
    const int value = clampPercent(percent);

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x07));
    payload.append(encodeLevel(value));
    queueProtectedWrite(
        WriteKind::Pbt1,
        payload,
        QStringLiteral("PBT1 %1 %").arg(value),
        QueryKind::Pbt1,
        value
    );
}

void RadioController::setPbt2(int percent)
{
    const int value = clampPercent(percent);

    QByteArray payload;
    payload.append(char(0x14));
    payload.append(char(0x08));
    payload.append(encodeLevel(value));
    queueProtectedWrite(
        WriteKind::Pbt2,
        payload,
        QStringLiteral("PBT2 %1 %").arg(value),
        QueryKind::Pbt2,
        value
    );
}

void RadioController::clearTwinPbt()
{
    if (!m_serial.isOpen()) {
        setActionStatus(
            QStringLiteral("La radio no está conectada")
        );
        return;
    }

    if (m_busy
        || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(
            QStringLiteral(
                "Espere a que termine la orden CI-V actual"
            )
        );
        return;
    }

    if (m_transmitting) {
        setActionStatus(
            QStringLiteral(
                "No se puede centrar Twin PBT durante TX"
            )
        );
        return;
    }

    // Las dos órdenes no pueden enviarse consecutivamente desde QML:
    // queueProtectedWrite protege la primera y rechaza la segunda mientras
    // la anterior sigue pendiente. Se encadenan tras cada PASS CI-V.
    m_twinPbtClearPending = true;
    setActionStatus(
        QStringLiteral("Centrando PBT1 y PBT2…")
    );
    setPbt1(50);
}

void RadioController::setIpPlusEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x65));
    payload.append(char(enabled ? 0x01 : 0x00));
    queueProtectedWrite(
        WriteKind::IpPlus,
        payload,
        enabled ? QStringLiteral("IP+ ON")
                : QStringLiteral("IP+ OFF"),
        QueryKind::IpPlus
    );
}

void RadioController::setFilterShape(int shape)
{
    shape = std::clamp(shape, 0, 1);

    QByteArray payload;
    payload.append(char(0x16));
    payload.append(char(0x56));
    payload.append(char(shape));

    queueProtectedWrite(
        WriteKind::FilterShape,
        payload,
        shape == 0 ? QStringLiteral("Filtro SHARP")
                   : QStringLiteral("Filtro SOFT"),
        QueryKind::FilterShape
    );
}


void RadioController::setRadioTuningStep(int code)
{
    code = std::clamp(code, 0, 8);

    QByteArray payload;
    payload.append(char(0x10));
    payload.append(char(code));

    queueProtectedWrite(
        WriteKind::TuningStep,
        payload,
        QStringLiteral("TS radio %1").arg(tuningStepName(code)),
        QueryKind::TuningStep,
        code
    );
}

void RadioController::setXfcEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x02));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::Xfc,
        payload,
        enabled ? QStringLiteral("XFC activado")
                : QStringLiteral("XFC desactivado"),
        QueryKind::Xfc,
        enabled ? 1 : 0
    );
}

void RadioController::setCivOutputEnabled(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x04));
    payload.append(char(enabled ? 0x01 : 0x00));

    queueProtectedWrite(
        WriteKind::CivOutput,
        payload,
        enabled
            ? QStringLiteral("CI-V Output (for ANT) activado")
            : QStringLiteral("CI-V Output (for ANT) desactivado"),
        QueryKind::CivOutput,
        enabled ? 1 : 0
    );
}

void RadioController::refreshCapabilities()
{
    m_txBandCount = -1;
    m_txBandEdges.clear();
    m_nextTxBandEdgeIndex = 1;
    emit capabilitiesChanged();

    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("Conecte la radio para leer sus límites"));
        return;
    }

    if (m_pendingQuery == QueryKind::None
        && m_activeWriteKind == WriteKind::None
        && !m_busy) {
        sendQuery(QueryKind::TxBandCount);
    } else {
        setActionStatus(
            QStringLiteral("Los límites se leerán cuando termine la orden actual")
        );
    }
}

void RadioController::pollNextValue()
{
    if (!m_serial.isOpen() || m_busy
        || m_pendingQuery != QueryKind::None
        || m_activeWriteKind != WriteKind::None) {
        return;
    }

    // Hasta conocer el estado real, solo se consulta 1C 00.
    if (!m_txStateKnown) {
        sendQuery(QueryKind::TxStatus);
        return;
    }

    if (!m_transmitting
        && m_deferredMemoryReadPending) {
        runDeferredMemoryRead();
        return;
    }

    if (m_cwRefreshActive) {
        sendNextCwRefreshQuery();
        return;
    }

    ++m_pollPhase;

    // En TX no se consultan ajustes de recepción. Se mantienen solamente
    // el estado TX/RX y los medidores válidos durante transmisión.
    if (m_transmitting) {
        if ((m_pollPhase % 2) == 0) {
            sendQuery(QueryKind::TxStatus);
            return;
        }

        static constexpr QueryKind txMeters[] = {
            QueryKind::PowerMeter,
            QueryKind::SwrMeter,
            QueryKind::AlcMeter,
            QueryKind::CompMeter,
            QueryKind::TxFrequency,
            QueryKind::VoltageMeter,
            QueryKind::CurrentMeter
        };

        const QueryKind meterQuery =
            txMeters[
                m_fastMeterIndex
                % int(sizeof(txMeters) / sizeof(txMeters[0]))
            ];

        ++m_fastMeterIndex;
        sendQuery(meterQuery);
        return;
    }

    // Prioridad alta para detectar TX/RX externo.
    if ((m_pollPhase % 3) == 0) {
        sendQuery(QueryKind::TxStatus);
        return;
    }

    // Un turno completo se reserva al S-meter. Antes se mezclaba con los
    // medidores lentos y aparecían pausas de más de un segundo entre varias
    // lecturas consecutivas. Así la cadencia queda estable (270 ms con el
    // intervalo normal de 90 ms).
    if ((m_pollPhase % 3) == 1) {
        sendQuery(QueryKind::Smeter);
        return;
    }

    // Los valores auxiliares de recepción cambian mucho más despacio. Se
    // intercalan aproximadamente cada 1,35 s sin interrumpir el S-meter.
    if ((m_pollPhase % 15) == 2) {
        static constexpr QueryKind slowRxMeters[] = {
            QueryKind::SquelchFull,
            QueryKind::VoltageMeter,
            QueryKind::CurrentMeter,
            QueryKind::Overflow
        };

        const QueryKind meterQuery =
            slowRxMeters[
                m_fastMeterIndex
                % int(sizeof(slowRxMeters)
                      / sizeof(slowRxMeters[0]))
            ];

        ++m_fastMeterIndex;
        sendQuery(meterQuery);
        return;
    }

    // El tercer turno recorre los estados de configuración.
    const int configurationCount = int(QueryKind::Smeter);

    QueryKind query =
        static_cast<QueryKind>(m_nextQueryIndex);

    m_nextQueryIndex =
        (m_nextQueryIndex + 1) % configurationCount;

    if (query == QueryKind::TxStatus) {
        query = static_cast<QueryKind>(m_nextQueryIndex);
        m_nextQueryIndex =
            (m_nextQueryIndex + 1) % configurationCount;
    }

    sendQuery(query);
}

void RadioController::sendQuery(QueryKind query)
{
    QByteArray payload;
    switch (query) {
    case QueryKind::Frequency:
        payload.append(char(0x03));
        break;
    case QueryKind::Mode:
        payload.append(char(0x04));
        break;
    case QueryKind::DataMode:
        payload.append(char(0x1A));
        payload.append(char(0x06));
        break;
    case QueryKind::VfoSelectedFrequency:
        payload.append(char(0x25));
        payload.append(char(0x00));
        break;
    case QueryKind::VfoUnselectedFrequency:
        payload.append(char(0x25));
        payload.append(char(0x01));
        break;
    case QueryKind::VfoSelectedMode:
        payload.append(char(0x26));
        payload.append(char(0x00));
        break;
    case QueryKind::VfoUnselectedMode:
        payload.append(char(0x26));
        payload.append(char(0x01));
        break;
    case QueryKind::TxStatus:
        payload.append(char(0x1C));
        payload.append(char(0x00));
        break;
    case QueryKind::Split: payload.append(char(0x0F)); break;
    case QueryKind::RitOffset: payload.append(char(0x21)); payload.append(char(0x00)); break;
    case QueryKind::RitEnabled: payload.append(char(0x21)); payload.append(char(0x01)); break;
    case QueryKind::DeltaTxEnabled: payload.append(char(0x21)); payload.append(char(0x02)); break;
    case QueryKind::AfGain: payload.append(char(0x14)); payload.append(char(0x01)); break;
    case QueryKind::RfGain: payload.append(char(0x14)); payload.append(char(0x02)); break;
    case QueryKind::Squelch: payload.append(char(0x14)); payload.append(char(0x03)); break;
    case QueryKind::RfPower:
        payload.append(char(0x14));
        payload.append(char(0x0A));
        break;
    case QueryKind::MicrophoneGain:
        payload.append(char(0x14));
        payload.append(char(0x0B));
        break;
    case QueryKind::SpeechCompressorLevel:
        payload.append(char(0x14));
        payload.append(char(0x0E));
        break;
    case QueryKind::MonitorLevel:
        payload.append(char(0x14));
        payload.append(char(0x15));
        break;
    case QueryKind::VoxGain:
        payload.append(char(0x14));
        payload.append(char(0x16));
        break;
    case QueryKind::AntiVoxGain:
        payload.append(char(0x14));
        payload.append(char(0x17));
        break;
    case QueryKind::SpeechCompressor:
        payload.append(char(0x16));
        payload.append(char(0x44));
        break;
    case QueryKind::Monitor:
        payload.append(char(0x16));
        payload.append(char(0x45));
        break;
    case QueryKind::Vox:
        payload.append(char(0x16));
        payload.append(char(0x46));
        break;
    case QueryKind::TxFilterWidth:
        payload.append(char(0x16));
        payload.append(char(0x58));
        break;
    case QueryKind::TxInhibit:
        payload.append(char(0x16));
        payload.append(char(0x66));
        break;
    case QueryKind::Preamp:
        payload.append(char(0x16));
        payload.append(char(0x02));
        break;
    case QueryKind::Attenuator: payload.append(char(0x11)); break;
    case QueryKind::Tuner: payload.append(char(0x1C)); payload.append(char(0x01)); break;
    case QueryKind::Agc:
        payload.append(char(0x16));
        payload.append(char(0x12));
        break;
    case QueryKind::TuningStep:
        payload.append(char(0x10));
        break;
    case QueryKind::Xfc:
        payload.append(char(0x1C));
        payload.append(char(0x02));
        break;
    case QueryKind::TxFrequency:
        payload.append(char(0x1C));
        payload.append(char(0x03));
        break;
    case QueryKind::CivOutput:
        payload.append(char(0x1C));
        payload.append(char(0x04));
        break;
    case QueryKind::TxBandCount:
        if (m_txBandCount >= 0) return;
        payload.append(char(0x1E));
        payload.append(char(0x00));
        break;
    case QueryKind::TxBandEdge:
        if (m_txBandCount <= 0
            || m_nextTxBandEdgeIndex > m_txBandCount) {
            return;
        }
        payload.append(char(0x1E));
        payload.append(char(0x01));
        payload.append(char(encodeBcdNumber(m_nextTxBandEdgeIndex)));
        break;
    case QueryKind::SquelchBasic:
        payload.append(char(0x15));
        payload.append(char(0x01));
        break;
    case QueryKind::SquelchFull:
        payload.append(char(0x15));
        payload.append(char(0x05));
        break;

    case QueryKind::NoiseBlanker:
        payload.append(char(0x16)); payload.append(char(0x22)); break;
    case QueryKind::NoiseBlankerLevel:
        payload.append(char(0x14)); payload.append(char(0x12)); break;
    case QueryKind::NoiseReduction:
        payload.append(char(0x16)); payload.append(char(0x40)); break;
    case QueryKind::NoiseReductionLevel:
        payload.append(char(0x14)); payload.append(char(0x06)); break;
    case QueryKind::AutoNotch:
        payload.append(char(0x16)); payload.append(char(0x41)); break;
    case QueryKind::ManualNotch:
        payload.append(char(0x16)); payload.append(char(0x48)); break;
    case QueryKind::ManualNotchPosition:
        payload.append(char(0x14)); payload.append(char(0x0D)); break;
    case QueryKind::ManualNotchWidth:
        payload.append(char(0x16)); payload.append(char(0x57)); break;
    case QueryKind::Pbt1:
        payload.append(char(0x14)); payload.append(char(0x07)); break;
    case QueryKind::Pbt2:
        payload.append(char(0x14)); payload.append(char(0x08)); break;
    case QueryKind::IpPlus:
        payload.append(char(0x16)); payload.append(char(0x65)); break;
    case QueryKind::FilterShape:
        payload.append(char(0x16)); payload.append(char(0x56)); break;

    case QueryKind::CwApfPeak:
        payload.append(char(0x14));
        payload.append(char(0x05));
        break;
    case QueryKind::CwPitch:
        payload.append(char(0x14));
        payload.append(char(0x09));
        break;
    case QueryKind::CwKeySpeed:
        payload.append(char(0x14));
        payload.append(char(0x0C));
        break;
    case QueryKind::CwBreakInDelay:
        payload.append(char(0x14));
        payload.append(char(0x0F));
        break;
    case QueryKind::ApfMode:
        payload.append(char(0x16));
        payload.append(char(0x32));
        break;
    case QueryKind::BreakInMode:
        payload.append(char(0x16));
        payload.append(char(0x47));
        break;

    case QueryKind::Smeter:
        payload.append(char(0x15)); payload.append(char(0x02)); break;
    case QueryKind::PowerMeter:
        payload.append(char(0x15)); payload.append(char(0x11)); break;
    case QueryKind::SwrMeter:
        payload.append(char(0x15)); payload.append(char(0x12)); break;
    case QueryKind::AlcMeter:
        payload.append(char(0x15)); payload.append(char(0x13)); break;
    case QueryKind::CompMeter:
        payload.append(char(0x15)); payload.append(char(0x14)); break;
    case QueryKind::VoltageMeter:
        payload.append(char(0x15)); payload.append(char(0x15)); break;
    case QueryKind::CurrentMeter:
        payload.append(char(0x15)); payload.append(char(0x16)); break;
    case QueryKind::Overflow:
        payload.append(char(0x15)); payload.append(char(0x07)); break;

    case QueryKind::SideToneLevel:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x18));
        break;
    case QueryKind::SideToneLimit:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x19));
        break;
    case QueryKind::KeyerRepeatTime:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x20));
        break;
    case QueryKind::DotDashRatio:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x21));
        break;
    case QueryKind::RiseTime:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x22));
        break;
    case QueryKind::PaddlePolarity:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x23));
        break;
    case QueryKind::KeyType:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x24));
        break;
    case QueryKind::MicUpDownKeyer:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x25));
        break;
    case QueryKind::CwDecodeDisplay:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x26));
        break;
    case QueryKind::KeyerMemory:
        if (m_pendingKeyerMemoryChannel < 1
            || m_pendingKeyerMemoryChannel > 8) {
            return;
        }
        payload.append(char(0x1A));
        payload.append(char(0x02));
        payload.append(char(m_pendingKeyerMemoryChannel));
        break;

    case QueryKind::RepeaterTone:
        payload.append(char(0x16));
        payload.append(char(0x42));
        break;
    case QueryKind::ToneSquelch:
        payload.append(char(0x16));
        payload.append(char(0x43));
        break;
    case QueryKind::RepeaterToneFrequency:
        payload.append(char(0x1B));
        payload.append(char(0x00));
        break;
    case QueryKind::ToneSquelchFrequency:
        payload.append(char(0x1B));
        payload.append(char(0x01));
        break;
    case QueryKind::TwinPeak:
        payload.append(char(0x16));
        payload.append(char(0x4F));
        break;
    case QueryKind::RttyMarkFrequency:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x00));
        payload.append(char(0x39));
        break;
    case QueryKind::RttyShiftWidth:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x00));
        payload.append(char(0x40));
        break;
    case QueryKind::RttyKeyingPolarity:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x00));
        payload.append(char(0x41));
        break;

    case QueryKind::MemoryContent:
        if (m_pendingMemoryReadChannel < 1
            || m_pendingMemoryReadChannel > 99) {
            return;
        }
        payload.append(char(0x1A));
        payload.append(char(0x00));
        payload.append(
            encodeMemoryChannel(m_pendingMemoryReadChannel)
        );
        break;
    case QueryKind::ScanSpeed:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x53));
        break;
    case QueryKind::ScanResume:
        payload.append(char(0x1A));
        payload.append(char(0x05));
        payload.append(char(0x02));
        payload.append(char(0x54));
        break;
    case QueryKind::BandStacking:
        if (m_pendingBandStackingRequest.bandCode < 1
            || m_pendingBandStackingRequest.bandCode > 11
            || m_pendingBandStackingRequest.registerCode < 1
            || m_pendingBandStackingRequest.registerCode > 3) {
            return;
        }
        payload.append(char(0x1A));
        payload.append(char(0x01));
        payload.append(char(
            m_pendingBandStackingRequest.bandCode
        ));
        payload.append(char(
            m_pendingBandStackingRequest.registerCode
        ));
        break;

    case QueryKind::None:
    case QueryKind::Count:
        return;
    }

    if (!sendCivPayload(payload)) {
        if (m_cwRefreshActive) {
            if (query == QueryKind::MemoryContent
                && m_memoryReadBatchActive) {
                ++m_memoryReadFailureCount;
            }

            QTimer::singleShot(
                0,
                this,
                &RadioController::sendNextCwRefreshQuery
            );
        }
        return;
    }

    m_pendingQuery = query;
    m_responseTimer.start();
}

bool RadioController::sendCivPayload(const QByteArray &payload)
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return false;
    }

    QByteArray frame;
    frame.reserve(payload.size() + 5);
    frame.append(char(0xFE));
    frame.append(char(0xFE));
    frame.append(char(m_radioAddress));
    frame.append(char(m_controllerAddress));
    frame.append(payload);
    frame.append(char(0xFD));

    const qint64 written = m_serial.write(frame);
    if (written != frame.size()) {
        setActionStatus(QStringLiteral("No se pudo enviar la orden CI-V"));
        return false;
    }

    m_serial.flush();
    setLastTx(frame);
    return true;
}

void RadioController::sendTransmitCommand(bool enabled)
{
    QByteArray payload;
    payload.append(char(0x1C));
    payload.append(char(0x00));
    payload.append(char(enabled ? 0x01 : 0x00));

    m_txReleasePending = false;
    m_activeWriteKind = WriteKind::Transmit;
    m_activeWriteLabel = enabled
        ? QStringLiteral("PTT TX")
        : QStringLiteral("PTT RX");
    m_activeRefreshQuery = QueryKind::TxStatus;
    m_activeDesiredValue = enabled ? 1 : 0;

    setBusy(true);
    setActionStatus(enabled
        ? QStringLiteral("Activando transmisión…")
        : QStringLiteral("Volviendo a recepción…"));

    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeRefreshQuery = QueryKind::None;
        m_activeDesiredValue = 0;
        setBusy(false);
        return;
    }

    m_responseTimer.start();
}

void RadioController::forceReceive()
{
    if (!m_serial.isOpen() || !m_pttOwned) {
        return;
    }

    QByteArray frame;
    frame.append(char(0xFE));
    frame.append(char(0xFE));
    frame.append(char(m_radioAddress));
    frame.append(char(m_controllerAddress));
    frame.append(char(0x1C));
    frame.append(char(0x00));
    frame.append(char(0x00));
    frame.append(char(0xFD));

    m_serial.write(frame);
    m_serial.flush();
    m_serial.waitForBytesWritten(180);
    m_pttOwned = false;
    m_txSafetyTimer.stop();
}

void RadioController::queueProtectedWrite(WriteKind kind,
                                          const QByteArray &payload,
                                          const QString &label,
                                          QueryKind refreshQuery,
                                          int desiredValue)
{
    if (!m_serial.isOpen()) {
        setActionStatus(QStringLiteral("La radio no está conectada"));
        return;
    }
    if (m_busy || m_activeWriteKind != WriteKind::None
        || m_queuedWriteKind != WriteKind::None
        || m_cwRefreshActive) {
        setActionStatus(QStringLiteral("Espere a que termine la orden anterior"));
        return;
    }
    if (m_transmitting) {
        setActionStatus(QStringLiteral("Cambio bloqueado: la radio está transmitiendo"));
        return;
    }

    m_queuedWriteKind = kind;
    m_queuedWritePayload = payload;
    m_queuedWriteLabel = label;
    m_queuedRefreshQuery = refreshQuery;
    m_queuedDesiredValue = desiredValue;
    setBusy(true);
    setActionStatus(QStringLiteral("Comprobando que la radio está en RX…"));

    if (m_pendingQuery == QueryKind::None) {
        QTimer::singleShot(0, this, &RadioController::startSafetyCheck);
    }
}

void RadioController::startSafetyCheck()
{
    if (!m_serial.isOpen()) {
        cancelQueuedWrite(QStringLiteral("Se perdió la conexión con la radio"));
        return;
    }
    if (m_pendingQuery != QueryKind::None
        || m_activeWriteKind != WriteKind::None) {
        return;
    }

    m_safetyCheckActive = true;
    sendQuery(QueryKind::TxStatus);
    if (m_pendingQuery != QueryKind::TxStatus) {
        m_safetyCheckActive = false;
        cancelQueuedWrite(QStringLiteral("No se pudo comprobar RX/TX"));
    }
}

void RadioController::sendQueuedWrite()
{
    if (m_queuedWriteKind == WriteKind::None) {
        setBusy(false);
        return;
    }
    if (m_transmitting) {
        cancelQueuedWrite(QStringLiteral("Cambio cancelado: la radio está en TX"));
        return;
    }

    const QByteArray payload = m_queuedWritePayload;
    m_activeWriteKind = m_queuedWriteKind;
    m_activeWriteLabel = m_queuedWriteLabel;
    m_activeRefreshQuery = m_queuedRefreshQuery;
    m_activeDesiredValue = m_queuedDesiredValue;

    m_queuedWriteKind = WriteKind::None;
    m_queuedWritePayload.clear();
    m_queuedWriteLabel.clear();
    m_queuedRefreshQuery = QueryKind::None;
    m_queuedDesiredValue = 0;

    setActionStatus(QStringLiteral("Aplicando: %1…").arg(m_activeWriteLabel));
    if (!sendCivPayload(payload)) {
        m_activeWriteKind = WriteKind::None;
        if (m_memorySequenceAction != MemorySequenceAction::None) {
            m_memorySequenceAction = MemorySequenceAction::None;
            m_memorySequenceChannel = 0;
            m_memorySequenceGroup = 0;
            m_memoryStoreVfoSelected = false;
        }
        setBusy(false);
        return;
    }
    m_responseTimer.start();
}

void RadioController::completeWrite(bool accepted)
{
    m_responseTimer.stop();
    const WriteKind completedKind = m_activeWriteKind;
    const QString completedLabel = m_activeWriteLabel;
    const QueryKind refreshQuery = m_activeRefreshQuery;
    const int desiredValue = m_activeDesiredValue;

    m_activeWriteKind = WriteKind::None;
    m_activeWriteLabel.clear();
    m_activeRefreshQuery = QueryKind::None;
    m_activeDesiredValue = 0;
    setBusy(false);

    if (!accepted) {
        if (completedKind == WriteKind::Transmit) {
            // Ante cualquier duda, se fuerza RX para evitar una portadora
            // mantenida accidentalmente.
            m_pttOwned = true;
            forceReceive();
            m_txReleasePending = false;
            m_txSafetyTimer.stop();
        }

        if (m_memorySequenceAction != MemorySequenceAction::None) {
            m_memorySequenceAction = MemorySequenceAction::None;
            m_memorySequenceChannel = 0;
            m_memorySequenceGroup = 0;
            m_memoryStoreVfoSelected = false;
        }

        if (completedKind == WriteKind::MemoryReceive
            || completedKind == WriteKind::MemoryMode
            || completedKind == WriteKind::MemorySelect) {
            m_pendingDirectMemoryChannel = 0;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }
        }

        if (completedKind
                == WriteKind::MemoryReturnReceive
            || (completedKind
                == WriteKind::MemoryReturnVfo
                && m_directMemoryReturnInProgress)) {
            m_directMemoryReturnInProgress = false;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }
        }

        if (completedKind == WriteKind::MemoryEdit) {
            m_memoryEditVerifyChannel = 0;
            m_memoryEditExpectedRaw.clear();
            m_memoryEditVerifyAttempt = 0;
        }

        if (m_twinPbtClearPending
            && (completedKind == WriteKind::Pbt1
                || completedKind == WriteKind::Pbt2)) {
            m_twinPbtClearPending = false;
        }

        setActionStatus(QStringLiteral("La radio rechazó: %1").arg(completedLabel));
        return;
    }

    if (completedKind == WriteKind::SelectVfo) {
        updateVfo(desiredValue);
        if (m_memoryModeActive) {
            m_memoryModeActive = false;
        }
        clearMemoryReturnState();
        emit memoryModeChanged();
    }

    if (completedKind == WriteKind::MemoryReturnReceive) {
        updateTxStatus(0x00);
        m_pttOwned = false;
        m_txReleasePending = false;

        if (!sendMemoryReturnStage(desiredValue)) {
            m_directMemoryReturnInProgress = false;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }

            setActionStatus(
                QStringLiteral(
                    "La radio pasó a RX, pero no se pudo restaurar %1"
                )
                    .arg(
                        desiredValue == 1
                        ? QStringLiteral("VFO B")
                        : QStringLiteral("VFO A")
                    )
            );
        }
        return;
    }

    if (completedKind == WriteKind::MemoryReceive) {
        // 1C 00 00 ha sido aceptado. Reflejar RX inmediatamente y continuar
        // con el cambio de modo sin reactivar todavía el sondeo.
        updateTxStatus(0x00);
        m_pttOwned = false;
        m_txReleasePending = false;

        if (!sendMemoryModeStage(desiredValue)) {
            m_pendingDirectMemoryChannel = 0;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }

            setActionStatus(
                QStringLiteral(
                    "La radio pasó a RX, pero no se pudo enviar 08 para M%1"
                )
                    .arg(
                        desiredValue,
                        2,
                        10,
                        QLatin1Char('0')
                    )
            );
        }
        return;
    }

    if (completedKind == WriteKind::MemoryMode) {
        // La radio ya ha confirmado que está en modo memoria. Se envía ahora
        // el canal concreto como una segunda orden CI-V independiente.
        if (!sendMemorySelectionStage(desiredValue)) {
            m_pendingDirectMemoryChannel = 0;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }

            setActionStatus(
                QStringLiteral(
                    "No se pudo enviar la selección de M%1"
                )
                    .arg(
                        desiredValue,
                        2,
                        10,
                        QLatin1Char('0')
                    )
            );
        }
        return;
    }

    if (completedKind == WriteKind::MemorySelect) {
        m_pendingDirectMemoryChannel = 0;
        m_selectedMemoryChannel = desiredValue;
        m_memoryModeActive = true;
        emit memoryModeChanged();

        if (m_memorySequenceAction != MemorySequenceAction::None) {
            QTimer::singleShot(
                0,
                this,
                &RadioController::continueMemorySequence
            );
            return;
        }

        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;

        // Refrescar frecuencia, modo y DATA después de cambiar realmente
        // a modo memoria. Durante estas tres consultas el polling normal
        // permanece detenido.
        m_cwRefreshQueries.clear();
        m_keyerReadQueue.clear();
        m_memoryReadQueue.clear();
        m_bandStackingReadQueue.clear();

        m_cwRefreshQueries.enqueue(QueryKind::Frequency);
        m_cwRefreshQueries.enqueue(QueryKind::Mode);
        m_cwRefreshQueries.enqueue(QueryKind::DataMode);

        m_manualRefreshCompletionText =
            QStringLiteral("Radio situada en M%1")
                .arg(desiredValue, 2, 10, QLatin1Char('0'));
        m_cwRefreshActive = true;

        QTimer::singleShot(
            100,
            this,
            &RadioController::sendNextCwRefreshQuery
        );
        return;
    }

    // La radio ha confirmado el ajuste: se refleja de inmediato
    // sin esperar al siguiente ciclo de lectura CI-V.
    if (completedKind == WriteKind::Pbt1) {
        if (m_pbt1 != desiredValue) {
            m_pbt1 = desiredValue;
            emit advancedReceiveChanged();
        }

        if (m_twinPbtClearPending) {
            setActionStatus(
                QStringLiteral(
                    "PBT1 centrado · centrando PBT2…"
                )
            );

            QTimer::singleShot(
                120,
                this,
                [this]() {
                    if (m_twinPbtClearPending) {
                        setPbt2(50);
                    }
                }
            );
            return;
        }
    }

    if (completedKind == WriteKind::Pbt2) {
        if (m_pbt2 != desiredValue) {
            m_pbt2 = desiredValue;
            emit advancedReceiveChanged();
        }

        if (m_twinPbtClearPending) {
            m_twinPbtClearPending = false;
            setActionStatus(
                QStringLiteral(
                    "Twin PBT centrado: PBT1 50 · PBT2 50"
                )
            );

            // El sondeo normal volverá a confirmar ambos valores.
            m_nextQueryIndex = int(QueryKind::Pbt1);
            QTimer::singleShot(
                120,
                this,
                &RadioController::pollNextValue
            );
            return;
        }
    }

    if (completedKind == WriteKind::RitOffset
        && m_ritOffsetHz != desiredValue) {
        m_ritOffsetHz = desiredValue;
        emit ritChanged();
    }

    if (completedKind == WriteKind::TuningStep) {
        updateRadioTuningStep(quint8(desiredValue));
    }

    if (completedKind == WriteKind::Xfc) {
        updateXfc(quint8(desiredValue));
    }

    if (completedKind == WriteKind::CivOutput) {
        updateCivOutput(quint8(desiredValue));
    }

    if (completedKind == WriteKind::MemoryReturnVfo) {
        if (m_directMemoryReturnInProgress) {
            const QString restoredVfo =
                desiredValue == 1
                ? QStringLiteral("VFO B")
                : QStringLiteral("VFO A");

            restoreMemoryReturnStateLocally();

            m_memoryModeActive = false;
            m_directMemoryReturnInProgress = false;
            m_pendingDirectMemoryChannel = 0;

            emit memoryModeChanged();

            // El snapshot ya se ha aplicado localmente. Se elimina después
            // de capturar el nombre del VFO y se consulta de nuevo la radio
            // para confirmar frecuencia, modo, filtros y opciones.
            m_memoryVfoSnapshot.valid = false;

            setActionStatus(
                QStringLiteral(
                    "%1 restaurado · comprobando opciones…"
                )
                    .arg(restoredVfo)
            );

            refreshAfterMemoryReturn();
            return;
        }

        if (m_memoryModeActive) {
            m_memoryModeActive = false;
            emit memoryModeChanged();
        }

        QTimer::singleShot(
            0,
            this,
            &RadioController::continueMemorySequence
        );
        return;
    }

    if (completedKind == WriteKind::MemoryStore) {
        const int channel = m_memorySequenceChannel;
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
        m_memoryStoreVfoSelected = false;
        clearMemoryReturnState();

        setActionStatus(
            QStringLiteral("Contenido actual guardado en M%1")
                .arg(channel, 2, 10, QLatin1Char('0'))
        );
        QTimer::singleShot(
            180,
            this,
            [this, channel]() {
                readMemoryChannel(channel);
            }
        );
        return;
    }

    if (completedKind == WriteKind::MemoryCopyToVfo) {
        const int channel = m_memorySequenceChannel;
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
        m_memoryStoreVfoSelected = false;
        setActionStatus(
            QStringLiteral("M%1 copiada al VFO")
                .arg(channel, 2, 10, QLatin1Char('0'))
        );
        return;
    }

    if (completedKind == WriteKind::MemoryClear) {
        const int channel = m_memorySequenceChannel;
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
        m_memoryStoreVfoSelected = false;

        if (channel >= 1 && channel <= m_memories.size()) {
            MemoryState empty;
            empty.loaded = true;
            empty.blank = true;
            m_memories[channel - 1] = empty;
            markMemoriesChanged();
        }

        setActionStatus(
            QStringLiteral("M%1 borrada")
                .arg(channel, 2, 10, QLatin1Char('0'))
        );
        return;
    }

    if (completedKind == WriteKind::MemorySelectGroup) {
        const int channel = m_memorySequenceChannel;
        const int group = desiredValue;
        m_memorySequenceAction = MemorySequenceAction::None;
        m_memorySequenceChannel = 0;
        m_memorySequenceGroup = 0;
        m_memoryStoreVfoSelected = false;

        if (channel >= 1 && channel <= m_memories.size()) {
            m_memories[channel - 1].selectGroup = group;
            markMemoriesChanged();
        }

        setActionStatus(
            group == 0
                ? QStringLiteral("M%1 retirada de grupos SEL")
                      .arg(channel, 2, 10, QLatin1Char('0'))
                : QStringLiteral("M%1 asignada a SEL%2")
                      .arg(channel, 2, 10, QLatin1Char('0'))
                      .arg(group)
        );
        return;
    }

    if (completedKind == WriteKind::MemoryRename) {
        setActionStatus(
            QStringLiteral("Nombre de M%1 guardado")
                .arg(desiredValue, 2, 10, QLatin1Char('0'))
        );
        QTimer::singleShot(
            160,
            this,
            [this, desiredValue]() {
                readMemoryChannel(desiredValue);
            }
        );
        return;
    }

    if (completedKind == WriteKind::MemoryEdit) {
        setActionStatus(
            QStringLiteral("La radio aceptó M%1 · esperando la escritura interna para verificar…")
                .arg(desiredValue, 2, 10, QLatin1Char('0'))
        );
        scheduleMemoryEditVerification(900);
        return;
    }

    if (completedKind == WriteKind::ScanControl) {
        m_scanSubcommand = quint8(desiredValue & 0xFF);
        m_scanActive = (desiredValue & 0x100) != 0;
        emit scanChanged();
        setActionStatus(
            m_scanActive
                ? QStringLiteral("Escaneo iniciado: %1")
                      .arg(scanTypeText())
                : QStringLiteral("Escaneo detenido")
        );
        return;
    }

    if (completedKind == WriteKind::ScanSpeed) {
        const bool fast = desiredValue == 1;
        if (m_scanSpeedFast != fast) {
            m_scanSpeedFast = fast;
            emit scanChanged();
        }
    }

    if (completedKind == WriteKind::ScanResume) {
        const bool enabled = desiredValue == 1;
        if (m_scanResumeEnabled != enabled) {
            m_scanResumeEnabled = enabled;
            emit scanChanged();
        }
    }

    if (completedKind == WriteKind::ScanSelectGroup) {
        if (m_scanSelectGroup != desiredValue) {
            m_scanSelectGroup = desiredValue;
            emit scanChanged();
        }
    }

    if (completedKind == WriteKind::DeltaScanSpan) {
        if (m_deltaScanSpanCode != desiredValue) {
            m_deltaScanSpanCode = desiredValue;
            emit scanChanged();
        }
    }

    if (completedKind == WriteKind::BandStacking) {
        const int bandCode = desiredValue / 10;
        const int registerCode = desiredValue % 10;
        setActionStatus(
            QStringLiteral("%1 · registro %2 guardado")
                .arg(bandStackingName(bandCode))
                .arg(registerCode)
        );
        QTimer::singleShot(
            160,
            this,
            [this, bandCode]() {
                readBandStackingBand(bandCode);
            }
        );
        return;
    }

    if (completedKind == WriteKind::KeyerMemory) {
        setActionStatus(
            QStringLiteral("Memoria M%1 guardada").arg(desiredValue)
        );
        QTimer::singleShot(
            120,
            this,
            [this, desiredValue]() {
                readKeyerMemory(desiredValue);
            }
        );
        return;
    }

    if (completedKind == WriteKind::CwMessage) {
        setActionStatus(QStringLiteral("Mensaje CW aceptado por la radio"));
        return;
    }

    if (completedKind == WriteKind::CwStop) {
        setActionStatus(QStringLiteral("Envío CW detenido"));
        return;
    }

    if (completedKind == WriteKind::Transmit) {
        const bool releaseAfterTx = desiredValue == 1 && m_txReleasePending;

        m_pttOwned = desiredValue == 1;

        if (desiredValue == 1)
            m_txSafetyTimer.start();
        else
            m_txSafetyTimer.stop();

        if (desiredValue == 0) {
            m_txReleasePending = false;
        }

        setActionStatus(desiredValue == 1
            ? QStringLiteral("PTT activo: mantenga pulsado para transmitir")
            : QStringLiteral("Radio en recepción"));

        if (releaseAfterTx) {
            m_txReleasePending = false;
            QTimer::singleShot(0, this, [this]() {
                sendTransmitCommand(false);
            });
            return;
        }
    } else {
        setActionStatus(QStringLiteral("Aplicado correctamente: %1")
                            .arg(completedLabel));
    }

    if (refreshQuery != QueryKind::None) {
        m_nextQueryIndex = int(refreshQuery);
        QTimer::singleShot(90, this, &RadioController::pollNextValue);
    }
}

void RadioController::cancelQueuedWrite(const QString &message)
{
    m_responseTimer.stop();
    m_safetyCheckActive = false;
    m_queuedWriteKind = WriteKind::None;
    m_queuedWritePayload.clear();
    m_queuedWriteLabel.clear();
    m_queuedRefreshQuery = QueryKind::None;
    m_activeWriteKind = WriteKind::None;
    m_activeWriteLabel.clear();
    m_activeRefreshQuery = QueryKind::None;
    m_txReleasePending = false;
    m_twinPbtClearPending = false;
    m_memorySequenceAction = MemorySequenceAction::None;
    m_memorySequenceChannel = 0;
    m_memorySequenceGroup = 0;
    m_memoryStoreVfoSelected = false;
    m_pendingDirectMemoryChannel = 0;
    setBusy(false);

    if (m_serial.isOpen()
        && !m_pollTimer.isActive()) {
        m_pollTimer.start();
    }

    setActionStatus(message);
}

void RadioController::setBusy(bool busyValue)
{
    if (m_busy == busyValue) return;
    m_busy = busyValue;
    emit busyChanged();
}

void RadioController::onReadyRead()
{
    const QByteArray data = m_serial.readAll();
    if (!data.isEmpty()) {
        m_receiveBuffer.append(data);
        processReceiveBuffer();
    }
}

void RadioController::onSerialError(QSerialPort::SerialPortError error)
{
    if (error == QSerialPort::NoError || m_shuttingDown) return;
    switch (error) {
    case QSerialPort::ResourceError:
    case QSerialPort::DeviceNotFoundError:
    case QSerialPort::PermissionError: {
        const QString errorText = m_serial.errorString();
        m_pollTimer.stop();
        m_responseTimer.stop();
        if (m_serial.isOpen()) m_serial.close();
        m_pendingQuery = QueryKind::None;
        m_scopeRunning = false;
        m_scopeOutOfRange = false;
        resetScopeAssembly();
        emit scopeStateChanged();
        cancelQueuedWrite(QStringLiteral("Error serie: %1").arg(errorText));
        emit connectedChanged();
        setStatus(QStringLiteral("Desconectado por error"));
        scheduleAutomaticReconnect();
        break;
    }
    default:
        break;
    }
}

void RadioController::onResponseTimeout()
{
    if (m_activeWriteKind != WriteKind::None) {
        const WriteKind timedOutKind = m_activeWriteKind;
        const QString label = m_activeWriteLabel;

        m_activeWriteKind = WriteKind::None;
        m_activeWriteLabel.clear();
        m_activeRefreshQuery = QueryKind::None;
        m_activeDesiredValue = 0;
        setBusy(false);

        if (m_twinPbtClearPending
            && (timedOutKind == WriteKind::Pbt1
                || timedOutKind == WriteKind::Pbt2)) {
            m_twinPbtClearPending = false;
        }

        if (m_memorySequenceAction != MemorySequenceAction::None) {
            m_memorySequenceAction = MemorySequenceAction::None;
            m_memorySequenceChannel = 0;
            m_memorySequenceGroup = 0;
            m_memoryStoreVfoSelected = false;
        }

        if (timedOutKind
                == WriteKind::MemoryReturnReceive
            && m_directMemoryReturnInProgress
            && m_memoryVfoSnapshot.valid) {
            const int vfo =
                m_memoryVfoSnapshot.selectedVfo == 1
                ? 1
                : 0;

            setActionStatus(
                QStringLiteral(
                    "RX sin confirmación · intentando volver directamente a %1…"
                )
                    .arg(
                        vfo == 1
                        ? QStringLiteral("VFO B")
                        : QStringLiteral("VFO A")
                    )
            );

            if (sendMemoryReturnStage(vfo)) {
                return;
            }

            m_directMemoryReturnInProgress = false;
        }

        if (timedOutKind == WriteKind::MemoryReceive
            && m_pendingDirectMemoryChannel >= 1
            && m_pendingDirectMemoryChannel <= 99) {
            const int channel =
                m_pendingDirectMemoryChannel;

            setActionStatus(
                QStringLiteral(
                    "RX sin confirmación · intentando 08 para M%1…"
                )
                    .arg(
                        channel,
                        2,
                        10,
                        QLatin1Char('0')
                    )
            );

            if (sendMemoryModeStage(channel)) {
                return;
            }

            m_pendingDirectMemoryChannel = 0;
        }

        if (timedOutKind == WriteKind::MemoryMode
            && m_pendingDirectMemoryChannel >= 1
            && m_pendingDirectMemoryChannel <= 99) {
            const int channel =
                m_pendingDirectMemoryChannel;

            setActionStatus(
                QStringLiteral(
                    "08 sin confirmación · probando directamente M%1…"
                )
                    .arg(
                        channel,
                        2,
                        10,
                        QLatin1Char('0')
                    )
            );

            if (sendMemorySelectionStage(channel)) {
                return;
            }

            m_pendingDirectMemoryChannel = 0;
        }

        if (timedOutKind
                == WriteKind::MemoryReturnVfo
            && m_directMemoryReturnInProgress) {
            m_directMemoryReturnInProgress = false;

            if (m_serial.isOpen()
                && !m_pollTimer.isActive()) {
                m_pollTimer.start();
            }

            setActionStatus(
                QStringLiteral(
                    "Sin confirmación al volver al VFO; puede volver a intentarlo"
                )
            );
            return;
        }

        if (timedOutKind == WriteKind::MemoryEdit) {
            m_memoryEditVerifyChannel = 0;
            m_memoryEditExpectedRaw.clear();
            m_memoryEditVerifyAttempt = 0;
        }

        if (timedOutKind == WriteKind::Transmit) {
            // La ausencia de PASS no demuestra que la orden TX no se haya
            // ejecutado. Se envía RX de emergencia antes de continuar.
            m_pttOwned = true;
            forceReceive();
            m_txReleasePending = false;
            setActionStatus(QStringLiteral(
                "PTT sin confirmación: se ha forzado recepción"
            ));
        } else if (timedOutKind == WriteKind::CwMessage
                   || timedOutKind == WriteKind::CwStop) {
            setActionStatus(
                QStringLiteral("Mensaje CW sin confirmación CI-V")
            );
        } else {
            setActionStatus(QStringLiteral("Sin confirmación de la radio: %1")
                                .arg(label));
        }

        if (m_serial.isOpen()
            && !m_pollTimer.isActive()) {
            m_pollTimer.start();
        }
        return;
    }

    const bool wasSafetyCheck =
        m_safetyCheckActive;
    const bool wasInitialTxProbe =
        m_initialTxProbePending
        && m_pendingQuery == QueryKind::TxStatus;

    m_safetyCheckActive = false;
    m_pendingQuery = QueryKind::None;

    if (wasInitialTxProbe) {
        m_initialTxProbePending = false;

        if (m_initialTxProbeAttempts < 3) {
            setActionStatus(
                QStringLiteral(
                    "Reintentando la comprobación TX/RX inicial…"
                )
            );
            QTimer::singleShot(
                180,
                this,
                &RadioController::beginInitialTxProbe
            );
            return;
        }

        setStatus(
            QStringLiteral(
                "Conectado · puerto abierto; esperando respuesta CI-V"
            )
        );
        setActionStatus(
            QStringLiteral(
                "No se confirmó TX/RX inicial; la conexión permanece abierta"
            )
        );

        if (!m_pollTimer.isActive()) {
            m_pollTimer.start();
        }

        QTimer::singleShot(
            0,
            this,
            &RadioController::pollNextValue
        );
        return;
    }

    if (wasSafetyCheck) {
        cancelQueuedWrite(QStringLiteral("Cambio cancelado: no se pudo confirmar RX/TX"));
        return;
    }

    ++m_consecutiveTimeouts;
    if (m_consecutiveTimeouts >= 3 && m_serial.isOpen()) {
        setStatus(QStringLiteral("Conectado · alguna respuesta CI-V se retrasa"));
    }

    if (m_cwRefreshActive) {
        QTimer::singleShot(
            0,
            this,
            &RadioController::sendNextCwRefreshQuery
        );
        return;
    }

    if (m_busy && m_queuedWriteKind != WriteKind::None) {
        QTimer::singleShot(0, this, &RadioController::startSafetyCheck);
    }
}

QString RadioController::findRadioPort() const
{
    if (!m_configuredPort.isEmpty()) {
        if (QFileInfo::exists(m_configuredPort)) {
            return m_configuredPort;
        }

        const auto configuredPorts =
            QSerialPortInfo::availablePorts();

        for (const QSerialPortInfo &info : configuredPorts) {
            if (info.systemLocation() == m_configuredPort
                || info.portName() == m_configuredPort) {
                return info.systemLocation();
            }
        }

        return QString();
    }

    // En Linux se prefiere el enlace persistente generado por udev para
    // la interfaz USB (B) / if02. El nombre se busca dinámicamente: nunca
    // se guarda en el código el número de serie de una radio concreta.
    const QString stableUsbBPath =
        stableIcomByIdPath(QStringLiteral("-if02"));
    if (!stableUsbBPath.isEmpty()) {
        return stableUsbBPath;
    }

    const auto ports = QSerialPortInfo::availablePorts();

    // Segundo criterio en Linux: si /dev/serial/by-id no está disponible,
    // consultar sysfs para identificar específicamente bInterfaceNumber=02.
    for (const QSerialPortInfo &info : ports) {
        if (looksLikeIcom7300Mk2(info)
            && linuxUsbInterfaceNumber(info)
                .compare(QStringLiteral("02"), Qt::CaseInsensitive) == 0) {
            return info.systemLocation();
        }
    }

    // Último recurso multiplataforma: escoger un puerto que se identifique
    // como Icom / IC-7300MK2. Si hay más de uno y no puede conocerse la
    // interfaz, se deja una selección determinista y el usuario puede fijar
    // manualmente el puerto desde la configuración.
    QStringList candidates;
    for (const QSerialPortInfo &info : ports) {
        if (looksLikeIcom7300Mk2(info)) {
            candidates.append(info.systemLocation());
        }
    }

    std::sort(candidates.begin(), candidates.end());
    return candidates.isEmpty() ? QString() : candidates.constLast();
}

void RadioController::processReceiveBuffer()
{
    while (true) {
        const qsizetype frameEnd = m_receiveBuffer.indexOf(char(0xFD));
        if (frameEnd < 0) return;

        QByteArray frame = m_receiveBuffer.left(frameEnd + 1);
        m_receiveBuffer.remove(0, frameEnd + 1);

        qsizetype frameStart = -1;
        for (qsizetype i = 0; i + 1 < frame.size(); ++i) {
            if (quint8(frame.at(i)) == 0xFE
                && quint8(frame.at(i + 1)) == 0xFE) {
                frameStart = i;
                break;
            }
        }
        if (frameStart < 0) continue;
        if (frameStart > 0) frame.remove(0, frameStart);

        const bool scopeWaveformFrame =
            frame.size() >= 7
            && quint8(frame.at(4)) == 0x27
            && quint8(frame.at(5)) == 0x00;

        if (!scopeWaveformFrame) {
            setLastRx(frame);
        }

        processFrame(frame);
    }
}

void RadioController::processFrame(const QByteArray &frame)
{
    if (frame.size() < 6) return;

    const quint8 destination = quint8(frame.at(2));
    const quint8 source = quint8(frame.at(3));
    const quint8 command = quint8(frame.at(4));

    if (destination == m_radioAddress && source == m_controllerAddress) return;
    if (source != m_radioAddress) return;

    if (command == 0xFB && m_activeWriteKind != WriteKind::None) {
        completeWrite(true);
        return;
    }
    if (command == 0xFA && m_activeWriteKind != WriteKind::None) {
        completeWrite(false);
        return;
    }

    if (command == 0xFA
        && m_pendingQuery != QueryKind::None) {
        const QueryKind failedQuery = m_pendingQuery;

        m_responseTimer.stop();
        m_pendingQuery = QueryKind::None;

        if (failedQuery == QueryKind::MemoryContent) {
            if (m_memoryReadBatchActive) {
                ++m_memoryReadFailureCount;
            }

            setActionStatus(
                QStringLiteral(
                    "La radio rechazó la lectura de M%1"
                )
                    .arg(
                        m_pendingMemoryReadChannel,
                        2,
                        10,
                        QLatin1Char('0')
                    )
            );
        } else {
            setActionStatus(
                QStringLiteral(
                    "La radio rechazó una consulta CI-V"
                )
            );
        }

        if (m_cwRefreshActive) {
            QTimer::singleShot(
                0,
                this,
                &RadioController::sendNextCwRefreshQuery
            );
        }

        return;
    }

    bool recognized = false;

    if ((command == 0x03 || command == 0x00) && frame.size() >= 11) {
        decodeFrequency(frame.mid(5, 5));
        recognized = true;
    }
    if ((command == 0x04 || command == 0x01) && frame.size() >= 8) {
        updateMode(quint8(frame.at(5)));
        updateFilter(quint8(frame.at(6)));
        recognized = true;
    }
    if (command == 0x07 && frame.size() >= 7) {
        const quint8 sub = quint8(frame.at(5));
        if (sub == 0x00 || sub == 0x01) updateVfo(sub);
        recognized = true;
    }
    if (command == 0x0F && frame.size() >= 7) {
        updateSplit(quint8(frame.at(5)));
        recognized = true;
    }
    if (command == 0x10 && frame.size() >= 7) {
        updateRadioTuningStep(quint8(frame.at(5)));
        recognized = true;
    }
    if (command == 0x11 && frame.size() >= 7) {
        updateAttenuator(quint8(frame.at(5)));
        recognized = true;
    }
    if (command == 0x14 && frame.size() >= 9) {
        const quint8 sub = quint8(frame.at(5));
        QueryKind kind = QueryKind::None;

        if (sub == 0x01) kind = QueryKind::AfGain;
        else if (sub == 0x02) kind = QueryKind::RfGain;
        else if (sub == 0x03) kind = QueryKind::Squelch;
        else if (sub == 0x05) kind = QueryKind::CwApfPeak;
        else if (sub == 0x06) kind = QueryKind::NoiseReductionLevel;
        else if (sub == 0x07) kind = QueryKind::Pbt1;
        else if (sub == 0x08) kind = QueryKind::Pbt2;
        else if (sub == 0x09) kind = QueryKind::CwPitch;
        else if (sub == 0x0A) kind = QueryKind::RfPower;
        else if (sub == 0x0B) kind = QueryKind::MicrophoneGain;
        else if (sub == 0x0C) kind = QueryKind::CwKeySpeed;
        else if (sub == 0x0D) kind = QueryKind::ManualNotchPosition;
        else if (sub == 0x0E) kind = QueryKind::SpeechCompressorLevel;
        else if (sub == 0x0F) kind = QueryKind::CwBreakInDelay;
        else if (sub == 0x15) kind = QueryKind::MonitorLevel;
        else if (sub == 0x16) kind = QueryKind::VoxGain;
        else if (sub == 0x17) kind = QueryKind::AntiVoxGain;
        else if (sub == 0x12) kind = QueryKind::NoiseBlankerLevel;

        if (kind == QueryKind::AfGain
            || kind == QueryKind::RfGain
            || kind == QueryKind::Squelch
            || kind == QueryKind::RfPower) {
            updateLevel(kind, frame.mid(6, 2));
            recognized = true;
        } else if (kind == QueryKind::MicrophoneGain
                   || kind == QueryKind::SpeechCompressorLevel
                   || kind == QueryKind::MonitorLevel
                   || kind == QueryKind::VoxGain
                   || kind == QueryKind::AntiVoxGain) {
            updateTxAudioLevel(kind, frame.mid(6, 2));
            recognized = true;
        } else if (kind == QueryKind::CwApfPeak
                   || kind == QueryKind::CwPitch
                   || kind == QueryKind::CwKeySpeed
                   || kind == QueryKind::CwBreakInDelay) {
            updateCwLevel(kind, frame.mid(6, 2));
            recognized = true;
        } else if (kind != QueryKind::None) {
            updateAdvancedLevel(kind, frame.mid(6, 2));
            recognized = true;
        }
    }
    if (command == 0x15 && frame.size() >= 8) {
        const quint8 sub = quint8(frame.at(5));
        QueryKind kind = QueryKind::None;

        if (sub == 0x01) kind = QueryKind::SquelchBasic;
        else if (sub == 0x02) kind = QueryKind::Smeter;
        else if (sub == 0x05) kind = QueryKind::SquelchFull;
        else if (sub == 0x11) kind = QueryKind::PowerMeter;
        else if (sub == 0x12) kind = QueryKind::SwrMeter;
        else if (sub == 0x13) kind = QueryKind::AlcMeter;
        else if (sub == 0x14) kind = QueryKind::CompMeter;
        else if (sub == 0x15) kind = QueryKind::VoltageMeter;
        else if (sub == 0x16) kind = QueryKind::CurrentMeter;

        if ((kind == QueryKind::SquelchBasic
             || kind == QueryKind::SquelchFull)
            && frame.size() >= 8) {
            updateSquelchState(kind, quint8(frame.at(6)));
            recognized = true;
        } else if (kind != QueryKind::None && frame.size() >= 9) {
            updateMeter(kind, frame.mid(6, 2));
            recognized = true;
        } else if (sub == 0x07) {
            updateOverflow(quint8(frame.at(6)));
            recognized = true;
        }
    }

    if (command == 0x16 && frame.size() >= 8) {
        const quint8 sub = quint8(frame.at(5));
        QueryKind kind = QueryKind::None;

        if (sub == 0x02) {
            updatePreamp(quint8(frame.at(6)));
            recognized = true;
        } else if (sub == 0x12) {
            updateAgc(quint8(frame.at(6)));
            recognized = true;
        } else {
            if (sub == 0x22) kind = QueryKind::NoiseBlanker;
            else if (sub == 0x32) kind = QueryKind::ApfMode;
            else if (sub == 0x40) kind = QueryKind::NoiseReduction;
            else if (sub == 0x41) kind = QueryKind::AutoNotch;
            else if (sub == 0x42) kind = QueryKind::RepeaterTone;
            else if (sub == 0x43) kind = QueryKind::ToneSquelch;
            else if (sub == 0x44) kind = QueryKind::SpeechCompressor;
            else if (sub == 0x45) kind = QueryKind::Monitor;
            else if (sub == 0x46) kind = QueryKind::Vox;
            else if (sub == 0x47) kind = QueryKind::BreakInMode;
            else if (sub == 0x48) kind = QueryKind::ManualNotch;
            else if (sub == 0x4F) kind = QueryKind::TwinPeak;
            else if (sub == 0x57) kind = QueryKind::ManualNotchWidth;
            else if (sub == 0x58) kind = QueryKind::TxFilterWidth;
            else if (sub == 0x65) kind = QueryKind::IpPlus;
            else if (sub == 0x66) kind = QueryKind::TxInhibit;
            else if (sub == 0x56) kind = QueryKind::FilterShape;

            if (kind == QueryKind::SpeechCompressor
                || kind == QueryKind::Monitor
                || kind == QueryKind::Vox
                || kind == QueryKind::TxFilterWidth
                || kind == QueryKind::TxInhibit) {
                updateTxAudioSwitch(kind, quint8(frame.at(6)));
                recognized = true;
            } else if (kind == QueryKind::ApfMode
                       || kind == QueryKind::BreakInMode) {
                updateCwSwitch(kind, quint8(frame.at(6)));
                recognized = true;
            } else if (kind == QueryKind::RepeaterTone
                       || kind == QueryKind::ToneSquelch
                       || kind == QueryKind::TwinPeak) {
                updateToneRttySwitch(
                    kind,
                    quint8(frame.at(6))
                );
                recognized = true;
            } else if (kind != QueryKind::None) {
                updateAdvancedSwitch(kind, quint8(frame.at(6)));
                recognized = true;
            }
        }
    }
    if (command == 0x1A && frame.size() >= 7) {
        const quint8 sub = quint8(frame.at(5));

        if (sub == 0x00 && frame.size() >= 10) {
            const qsizetype dataLength =
                std::max<qsizetype>(0, frame.size() - 7);
            updateMemoryContent(
                frame.mid(6, dataLength)
            );
            recognized = true;
        } else if (sub == 0x01 && frame.size() >= 23) {
            const qsizetype dataLength =
                std::max<qsizetype>(0, frame.size() - 7);
            updateBandStacking(
                frame.mid(6, dataLength)
            );
            recognized = true;
        } else if (sub == 0x06 && frame.size() >= 9) {
            updateDataMode(quint8(frame.at(6)));
            if (quint8(frame.at(6)) == 0x01) {
                updateFilter(quint8(frame.at(7)));
            }
            recognized = true;
        } else if (sub == 0x02 && frame.size() >= 8) {
            const int channel = int(quint8(frame.at(6)));
            const qsizetype dataLength =
                std::max<qsizetype>(0, frame.size() - 8);
            updateKeyerMemory(
                channel,
                frame.mid(7, dataLength)
            );
            recognized = channel >= 1 && channel <= 8;
        } else if (sub == 0x05
                   && frame.size() >= 10
                   && quint8(frame.at(6)) == 0x02) {
            const quint8 item = quint8(frame.at(7));
            const qsizetype dataLength =
                std::max<qsizetype>(0, frame.size() - 9);

            if (item >= 0x18 && item <= 0x26) {
                updateCwMenuSetting(
                    item,
                    frame.mid(8, dataLength)
                );
                recognized = true;
            } else if (item == 0x53 || item == 0x54) {
                updateScanSetting(
                    item,
                    quint8(frame.at(8))
                );
                recognized = true;
            }
        } else if (sub == 0x05
                   && frame.size() >= 10
                   && quint8(frame.at(6)) == 0x00) {
            const quint8 item = quint8(frame.at(7));
            updateRttyMenuSetting(
                item,
                quint8(frame.at(8))
            );
            recognized =
                item >= 0x39 && item <= 0x41;
        }
    }

    if (command == 0x1B && frame.size() >= 10) {
        const quint8 sub = quint8(frame.at(5));

        if (sub == 0x00) {
            updateToneFrequency(
                QueryKind::RepeaterToneFrequency,
                frame.mid(6, 3)
            );
            recognized = true;
        } else if (sub == 0x01) {
            updateToneFrequency(
                QueryKind::ToneSquelchFrequency,
                frame.mid(6, 3)
            );
            recognized = true;
        }
    }

    if (command == 0x1C && frame.size() >= 8) {
        const quint8 sub = quint8(frame.at(5));

        if (sub == 0x00) {
            updateTxStatus(quint8(frame.at(6)));
            recognized = true;
        } else if (sub == 0x01) {
            updateTuner(quint8(frame.at(6)));
            recognized = true;
        } else if (sub == 0x02) {
            updateXfc(quint8(frame.at(6)));
            recognized = true;
        } else if (sub == 0x03 && frame.size() >= 12) {
            updateTxFrequency(frame.mid(6, 5));
            recognized = true;
        } else if (sub == 0x04) {
            updateCivOutput(quint8(frame.at(6)));
            recognized = true;
        }
    }
    if (command == 0x1E && frame.size() >= 8) {
        const quint8 sub = quint8(frame.at(5));

        if (sub == 0x00) {
            updateTxBandCount(quint8(frame.at(6)));
            recognized = true;
        } else if (sub == 0x01 && frame.size() >= 20) {
            updateTxBandEdge(frame);
            recognized = true;
        }
    }


    if (command == 0x27 && frame.size() >= 7) {
        const quint8 sub =
            quint8(frame.at(5));

        if (sub == 0x00) {
            updateScopeWaveform(frame);
            return;
        }

        updateScopeSetting(frame);
        recognized = true;
    }

    if (command == 0x21 && frame.size() >= 8) {
        const quint8 sub = quint8(frame.at(5));
        if (sub == 0x00 && frame.size() >= 10) updateRitOffset(frame.mid(6, 3));
        else if (sub == 0x01) updateRitEnabled(quint8(frame.at(6)));
        else if (sub == 0x02) updateDeltaTxEnabled(quint8(frame.at(6)));
        recognized = (sub <= 0x02);
    }
    if (command == 0x25 && frame.size() >= 12) {
        const quint8 selector = quint8(frame.at(5));
        if (selector <= 0x01) {
            updateVfoFrequency(
                actualVfoForSelector(selector),
                frame.mid(6, 5)
            );
            recognized = true;
        }
    }

    if (command == 0x26 && frame.size() >= 10) {
        const quint8 selector = quint8(frame.at(5));
        if (selector <= 0x01) {
            updateVfoModeState(
                actualVfoForSelector(selector),
                quint8(frame.at(6)),
                quint8(frame.at(7)),
                quint8(frame.at(8))
            );
            recognized = true;
        }
    }

    if (recognized) {
        acknowledgePendingQuery(frame);
        m_consecutiveTimeouts = 0;
        setStatus(m_transmitting
                      ? QStringLiteral("Conectado · transmitiendo")
                      : QStringLiteral("Conectado · recepción"));
    }
}


void RadioController::updateScopeWaveform(
    const QByteArray &frame
)
{
    // FE FE DEST SRC 27 00 [DATA] FD
    const int dataLength =
        frame.size() - 7;

    if (dataLength < 3) {
        return;
    }

    const QByteArray data =
        frame.mid(6, dataLength);

    auto divisionNumber =
        [](quint8 encoded) {
            return isBcdByte(encoded)
                   ? bcdByteToInt(encoded)
                   : int(encoded);
        };

    const int currentDivision =
        divisionNumber(
            quint8(data.at(1))
        );
    const int maximumDivision =
        divisionNumber(
            quint8(data.at(2))
        );

    if (currentDivision == 1) {
        if (data.size() < 15
            || maximumDivision < 1) {
            resetScopeAssembly();
            return;
        }

        resetScopeAssembly();
        m_scopeExpectedDivision =
            maximumDivision;
        m_scopeLastDivision = 1;

        const int newMode =
            std::clamp(
                int(quint8(data.at(3))),
                0,
                3
            );
        bool stateChanged =
            newMode != m_scopeMode;
        m_scopeMode = newMode;

        bool firstOk = false;
        bool secondOk = false;
        const quint64 firstFrequency =
            decodeFrequencyValue(
                data.mid(4, 5),
                firstOk
            );
        const quint64 secondFrequency =
            decodeFrequencyValue(
                data.mid(9, 5),
                secondOk
            );

        if (m_scopeMode == 0) {
            if (firstOk) {
                if (m_scopeCenterFrequencyHz
                    != firstFrequency) {
                    stateChanged = true;
                }

                m_scopeCenterFrequencyHz =
                    firstFrequency;
            }

            if (secondOk
                && secondFrequency > 0) {
                if (m_scopeSpanHz
                    != secondFrequency) {
                    stateChanged = true;
                }

                m_scopeSpanHz =
                    secondFrequency;
            }

            const quint64 half =
                m_scopeSpanHz / 2;
            const quint64 newLower =
                m_scopeCenterFrequencyHz > half
                ? m_scopeCenterFrequencyHz - half
                : 0;
            const quint64 newHigher =
                m_scopeCenterFrequencyHz + half;

            if (newLower
                    != m_scopeLowerFrequencyHz
                || newHigher
                    != m_scopeHigherFrequencyHz) {
                stateChanged = true;
            }

            m_scopeLowerFrequencyHz =
                newLower;
            m_scopeHigherFrequencyHz =
                newHigher;
        } else {
            if (firstOk) {
                if (m_scopeLowerFrequencyHz
                    != firstFrequency) {
                    stateChanged = true;
                }

                m_scopeLowerFrequencyHz =
                    firstFrequency;
            }

            if (secondOk) {
                if (m_scopeHigherFrequencyHz
                    != secondFrequency) {
                    stateChanged = true;
                }

                m_scopeHigherFrequencyHz =
                    secondFrequency;
            }

            if (m_scopeHigherFrequencyHz
                > m_scopeLowerFrequencyHz) {
                const quint64 newSpan =
                    m_scopeHigherFrequencyHz
                    - m_scopeLowerFrequencyHz;
                const quint64 newCenter =
                    m_scopeLowerFrequencyHz
                    + newSpan / 2;

                if (newSpan != m_scopeSpanHz
                    || newCenter
                    != m_scopeCenterFrequencyHz) {
                    stateChanged = true;
                }

                m_scopeSpanHz = newSpan;
                m_scopeCenterFrequencyHz =
                    newCenter;
            }
        }

        const bool outOfRange =
            quint8(data.at(14)) != 0;

        if (outOfRange
            != m_scopeOutOfRange) {
            m_scopeOutOfRange =
                outOfRange;
            stateChanged = true;
        }

        if (!m_scopeRunning) {
            m_scopeRunning = true;
            stateChanged = true;
        }

        if (stateChanged) {
            emit scopeStateChanged();
        }

        return;
    }

    if (currentDivision < 2
        || maximumDivision < 2
        || m_scopeExpectedDivision
           != maximumDivision
        || currentDivision
           != m_scopeLastDivision + 1) {
        resetScopeAssembly();
        return;
    }

    for (int index = 3;
         index < data.size();
         ++index) {
        const int value =
            std::clamp(
                int(quint8(data.at(index))),
                0,
                160
            );

        m_scopeWaveformAssembly.append(
            char(value)
        );
    }

    m_scopeLastDivision =
        currentDivision;

    if (currentDivision
        != maximumDivision) {
        return;
    }

    if (m_scopeWaveformAssembly.size()
        < 475) {
        resetScopeAssembly();
        return;
    }

    if (m_scopeWaveformAssembly.size()
        > 475) {
        m_scopeWaveformAssembly.resize(475);
    }

    QVariantList waveform;
    waveform.reserve(475);

    for (const char rawValue :
         m_scopeWaveformAssembly) {
        waveform.append(
            int(quint8(rawValue))
        );
    }

    m_scopeSpectrumData =
        waveform;
    ++m_scopeFrameCounter;

    emit scopeWaveformChanged();

    resetScopeAssembly();
}

void RadioController::updateScopeSetting(
    const QByteArray &frame
)
{
    if (frame.size() < 7) {
        return;
    }

    const quint8 sub =
        quint8(frame.at(5));
    bool changed = false;

    switch (sub) {
    case 0x10:
        // Estado del scope de la pantalla de la radio.
        break;

    case 0x11: {
        const bool enabled =
            quint8(frame.at(6)) != 0;

        if (enabled != m_scopeRunning) {
            m_scopeRunning = enabled;
            changed = true;
        }
        break;
    }

    case 0x14:
        if (frame.size() >= 9) {
            const int mode =
                std::clamp(
                    int(quint8(frame.at(7))),
                    0,
                    3
                );

            if (mode != m_scopeMode) {
                m_scopeMode = mode;
                changed = true;
            }
        }
        break;

    case 0x15:
        if (frame.size() >= 13) {
            bool ok = false;
            const quint64 span =
                decodeFrequencyValue(
                    frame.mid(7, 5),
                    ok
                );

            if (ok
                && span > 0
                && span != m_scopeSpanHz) {
                m_scopeSpanHz = span;
                changed = true;
            }
        }
        break;

    case 0x17:
        if (frame.size() >= 9) {
            const bool hold =
                quint8(frame.at(7)) != 0;

            if (hold != m_scopeHold) {
                m_scopeHold = hold;
                changed = true;
            }
        }
        break;

    case 0x1A:
        if (frame.size() >= 9) {
            const int speed =
                std::clamp(
                    int(quint8(frame.at(7))),
                    0,
                    2
                );

            if (speed
                != m_scopeSweepSpeed) {
                m_scopeSweepSpeed =
                    speed;
                changed = true;
            }
        }
        break;

    case 0x1D:
        if (frame.size() >= 9) {
            const bool wide =
                quint8(frame.at(7)) != 0;

            if (wide
                != m_scopeVbwWide) {
                m_scopeVbwWide =
                    wide;
                changed = true;
            }
        }
        break;

    default:
        break;
    }

    if (changed) {
        emit scopeStateChanged();
    }
}

void RadioController::acknowledgePendingQuery(const QByteArray &frame)
{
    if (m_pendingQuery == QueryKind::None || frame.size() < 6) return;

    const quint8 command = quint8(frame.at(4));
    const quint8 sub = frame.size() > 6 ? quint8(frame.at(5)) : 0xFF;
    bool matches = false;

    switch (m_pendingQuery) {
    case QueryKind::Frequency:
        matches = command == 0x03;
        break;
    case QueryKind::Mode:
        matches = command == 0x04;
        break;
    case QueryKind::DataMode:
        matches = command == 0x1A && sub == 0x06;
        break;
    case QueryKind::VfoSelectedFrequency:
        matches = command == 0x25 && sub == 0x00;
        break;
    case QueryKind::VfoUnselectedFrequency:
        matches = command == 0x25 && sub == 0x01;
        break;
    case QueryKind::VfoSelectedMode:
        matches = command == 0x26 && sub == 0x00;
        break;
    case QueryKind::VfoUnselectedMode:
        matches = command == 0x26 && sub == 0x01;
        break;
    case QueryKind::TxStatus:
        matches = command == 0x1C && sub == 0x00;
        break;
    case QueryKind::Split: matches = command == 0x0F; break;
    case QueryKind::RitOffset: matches = command == 0x21 && sub == 0x00; break;
    case QueryKind::RitEnabled: matches = command == 0x21 && sub == 0x01; break;
    case QueryKind::DeltaTxEnabled: matches = command == 0x21 && sub == 0x02; break;
    case QueryKind::AfGain: matches = command == 0x14 && sub == 0x01; break;
    case QueryKind::RfGain: matches = command == 0x14 && sub == 0x02; break;
    case QueryKind::Squelch: matches = command == 0x14 && sub == 0x03; break;
    case QueryKind::RfPower:
        matches = command == 0x14 && sub == 0x0A;
        break;
    case QueryKind::MicrophoneGain:
        matches = command == 0x14 && sub == 0x0B;
        break;
    case QueryKind::SpeechCompressorLevel:
        matches = command == 0x14 && sub == 0x0E;
        break;
    case QueryKind::MonitorLevel:
        matches = command == 0x14 && sub == 0x15;
        break;
    case QueryKind::VoxGain:
        matches = command == 0x14 && sub == 0x16;
        break;
    case QueryKind::AntiVoxGain:
        matches = command == 0x14 && sub == 0x17;
        break;
    case QueryKind::SpeechCompressor:
        matches = command == 0x16 && sub == 0x44;
        break;
    case QueryKind::Monitor:
        matches = command == 0x16 && sub == 0x45;
        break;
    case QueryKind::Vox:
        matches = command == 0x16 && sub == 0x46;
        break;
    case QueryKind::TxFilterWidth:
        matches = command == 0x16 && sub == 0x58;
        break;
    case QueryKind::TxInhibit:
        matches = command == 0x16 && sub == 0x66;
        break;
    case QueryKind::Preamp:
        matches = command == 0x16 && sub == 0x02;
        break;
    case QueryKind::Attenuator: matches = command == 0x11; break;
    case QueryKind::Tuner: matches = command == 0x1C && sub == 0x01; break;
    case QueryKind::Agc:
        matches = command == 0x16 && sub == 0x12;
        break;
    case QueryKind::TuningStep:
        matches = command == 0x10;
        break;
    case QueryKind::Xfc:
        matches = command == 0x1C && sub == 0x02;
        break;
    case QueryKind::TxFrequency:
        matches = command == 0x1C && sub == 0x03;
        break;
    case QueryKind::CivOutput:
        matches = command == 0x1C && sub == 0x04;
        break;
    case QueryKind::TxBandCount:
        matches = command == 0x1E && sub == 0x00;
        break;
    case QueryKind::TxBandEdge:
        matches = command == 0x1E && sub == 0x01;
        break;
    case QueryKind::SquelchBasic:
        matches = command == 0x15 && sub == 0x01;
        break;
    case QueryKind::SquelchFull:
        matches = command == 0x15 && sub == 0x05;
        break;

    case QueryKind::NoiseBlanker:
        matches = command == 0x16 && sub == 0x22; break;
    case QueryKind::NoiseBlankerLevel:
        matches = command == 0x14 && sub == 0x12; break;
    case QueryKind::NoiseReduction:
        matches = command == 0x16 && sub == 0x40; break;
    case QueryKind::NoiseReductionLevel:
        matches = command == 0x14 && sub == 0x06; break;
    case QueryKind::AutoNotch:
        matches = command == 0x16 && sub == 0x41; break;
    case QueryKind::ManualNotch:
        matches = command == 0x16 && sub == 0x48; break;
    case QueryKind::ManualNotchPosition:
        matches = command == 0x14 && sub == 0x0D; break;
    case QueryKind::ManualNotchWidth:
        matches = command == 0x16 && sub == 0x57; break;
    case QueryKind::Pbt1:
        matches = command == 0x14 && sub == 0x07; break;
    case QueryKind::Pbt2:
        matches = command == 0x14 && sub == 0x08; break;
    case QueryKind::IpPlus:
        matches = command == 0x16 && sub == 0x65; break;
    case QueryKind::FilterShape:
        matches = command == 0x16 && sub == 0x56; break;

    case QueryKind::CwApfPeak:
        matches = command == 0x14 && sub == 0x05;
        break;
    case QueryKind::CwPitch:
        matches = command == 0x14 && sub == 0x09;
        break;
    case QueryKind::CwKeySpeed:
        matches = command == 0x14 && sub == 0x0C;
        break;
    case QueryKind::CwBreakInDelay:
        matches = command == 0x14 && sub == 0x0F;
        break;
    case QueryKind::ApfMode:
        matches = command == 0x16 && sub == 0x32;
        break;
    case QueryKind::BreakInMode:
        matches = command == 0x16 && sub == 0x47;
        break;

    case QueryKind::Smeter:
        matches = command == 0x15 && sub == 0x02; break;
    case QueryKind::PowerMeter:
        matches = command == 0x15 && sub == 0x11; break;
    case QueryKind::SwrMeter:
        matches = command == 0x15 && sub == 0x12; break;
    case QueryKind::AlcMeter:
        matches = command == 0x15 && sub == 0x13; break;
    case QueryKind::CompMeter:
        matches = command == 0x15 && sub == 0x14; break;
    case QueryKind::VoltageMeter:
        matches = command == 0x15 && sub == 0x15; break;
    case QueryKind::CurrentMeter:
        matches = command == 0x15 && sub == 0x16; break;
    case QueryKind::Overflow:
        matches = command == 0x15 && sub == 0x07; break;

    case QueryKind::SideToneLevel:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x18;
        break;
    case QueryKind::SideToneLimit:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x19;
        break;
    case QueryKind::KeyerRepeatTime:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x20;
        break;
    case QueryKind::DotDashRatio:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x21;
        break;
    case QueryKind::RiseTime:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x22;
        break;
    case QueryKind::PaddlePolarity:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x23;
        break;
    case QueryKind::KeyType:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x24;
        break;
    case QueryKind::MicUpDownKeyer:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x25;
        break;
    case QueryKind::CwDecodeDisplay:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x26;
        break;
    case QueryKind::KeyerMemory:
        matches = command == 0x1A
                  && sub == 0x02
                  && frame.size() >= 7
                  && int(quint8(frame.at(6)))
                     == m_pendingKeyerMemoryChannel;
        break;

    case QueryKind::RepeaterTone:
        matches = command == 0x16 && sub == 0x42;
        break;
    case QueryKind::ToneSquelch:
        matches = command == 0x16 && sub == 0x43;
        break;
    case QueryKind::RepeaterToneFrequency:
        matches = command == 0x1B && sub == 0x00;
        break;
    case QueryKind::ToneSquelchFrequency:
        matches = command == 0x1B && sub == 0x01;
        break;
    case QueryKind::TwinPeak:
        matches = command == 0x16 && sub == 0x4F;
        break;
    case QueryKind::RttyMarkFrequency:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x00
                  && quint8(frame.at(7)) == 0x39;
        break;
    case QueryKind::RttyShiftWidth:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x00
                  && quint8(frame.at(7)) == 0x40;
        break;
    case QueryKind::RttyKeyingPolarity:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x00
                  && quint8(frame.at(7)) == 0x41;
        break;

    case QueryKind::MemoryContent:
        matches = command == 0x1A
                  && sub == 0x00
                  && frame.size() >= 8
                  && decodeMemoryChannel(frame.mid(6, 2))
                     == m_pendingMemoryReadChannel;
        break;
    case QueryKind::ScanSpeed:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x53;
        break;
    case QueryKind::ScanResume:
        matches = command == 0x1A
                  && sub == 0x05
                  && frame.size() >= 8
                  && quint8(frame.at(6)) == 0x02
                  && quint8(frame.at(7)) == 0x54;
        break;
    case QueryKind::BandStacking:
        matches = command == 0x1A
                  && sub == 0x01
                  && frame.size() >= 8
                  && int(quint8(frame.at(6)))
                     == m_pendingBandStackingRequest.bandCode
                  && int(quint8(frame.at(7)))
                     == m_pendingBandStackingRequest.registerCode;
        break;

    case QueryKind::None:
    case QueryKind::Count:
        break;
    }
    if (!matches) return;

    const QueryKind completedQuery =
        m_pendingQuery;
    const bool completedSafetyCheck =
        m_safetyCheckActive
        && completedQuery == QueryKind::TxStatus;
    const bool completedInitialTxProbe =
        m_initialTxProbePending
        && completedQuery == QueryKind::TxStatus;

    m_responseTimer.stop();
    m_pendingQuery = QueryKind::None;

    if (completedInitialTxProbe) {
        m_initialTxProbePending = false;
        m_initialTxProbeAttempts = 0;

        if (!m_pollTimer.isActive()) {
            m_pollTimer.start();
        }

        setActionStatus(
            m_transmitting
            ? QStringLiteral(
                  "Radio conectada en TX · esperando RX para completar la lectura"
              )
            : QStringLiteral("Control habilitado")
        );

        QTimer::singleShot(
            0,
            this,
            &RadioController::pollNextValue
        );
        return;
    }

    if (completedSafetyCheck) {
        m_safetyCheckActive = false;
        if (m_transmitting) {
            cancelQueuedWrite(QStringLiteral("Cambio cancelado: la radio está transmitiendo"));
        } else {
            QTimer::singleShot(0, this, &RadioController::sendQueuedWrite);
        }
        return;
    }

    if (m_cwRefreshActive) {
        QTimer::singleShot(
            0,
            this,
            &RadioController::sendNextCwRefreshQuery
        );
        return;
    }

    if (m_busy && m_queuedWriteKind != WriteKind::None) {
        QTimer::singleShot(0, this, &RadioController::startSafetyCheck);
    }
}

void RadioController::decodeFrequency(
    const QByteArray &fiveBcdBytes
)
{
    bool ok = false;
    const quint64 frequency =
        decodeFrequencyValue(fiveBcdBytes, ok);

    if (!ok) {
        setStatus(QStringLiteral(
            "Respuesta CI-V con BCD no válido"
        ));
        return;
    }

    if (frequency != m_frequencyHz) {
        m_frequencyHz = frequency;
        m_frequencyText = formatFrequency(frequency);
        m_frequencyMhzText = formatFrequencyMhz(frequency);
        m_bandText = bandForFrequency(frequency);
        emit frequencyChanged();
    }

    const int activeVfo =
        (m_selectedVfo == 1) ? 1 : 0;

    VfoState &state = m_vfoStates[activeVfo];

    if (!state.frequencyValid
        || state.frequencyHz != frequency) {
        state.frequencyHz = frequency;
        state.frequencyValid = true;
        emitVfoStateSignal(activeVfo);
    }
}

void RadioController::updateVfoFrequency(
    int vfoNumber,
    const QByteArray &fiveBcdBytes
)
{
    if (vfoNumber < 0 || vfoNumber > 1) {
        return;
    }

    bool ok = false;
    const quint64 frequency =
        decodeFrequencyValue(fiveBcdBytes, ok);

    if (!ok) {
        return;
    }

    VfoState &state = m_vfoStates[vfoNumber];

    if (!state.frequencyValid
        || state.frequencyHz != frequency) {
        state.frequencyHz = frequency;
        state.frequencyValid = true;
        emitVfoStateSignal(vfoNumber);
    }

    if (vfoNumber == m_selectedVfo) {
        syncActiveStateFromSelectedVfo();
    }
}

void RadioController::updateVfoModeState(
    int vfoNumber,
    quint8 modeCode,
    quint8 dataCode,
    quint8 filterCode
)
{
    if (vfoNumber < 0 || vfoNumber > 1) {
        return;
    }

    VfoState &state = m_vfoStates[vfoNumber];

    const bool newDataMode = dataCode == 0x01;
    const quint8 validFilter =
        (filterCode >= 1 && filterCode <= 3)
        ? filterCode
        : 1;

    const bool changed =
        !state.modeValid
        || state.modeCode != modeCode
        || state.dataMode != newDataMode
        || state.filterCode != validFilter;

    state.modeCode = modeCode;
    state.dataMode = newDataMode;
    state.filterCode = validFilter;
    state.modeValid = true;

    if (changed) {
        emitVfoStateSignal(vfoNumber);
    }

    if (vfoNumber == m_selectedVfo) {
        syncActiveStateFromSelectedVfo();
    }
}

void RadioController::syncActiveStateFromSelectedVfo()
{
    const int activeVfo =
        (m_selectedVfo == 1) ? 1 : 0;

    const VfoState &state = m_vfoStates[activeVfo];

    if (state.frequencyValid
        && state.frequencyHz != m_frequencyHz) {
        m_frequencyHz = state.frequencyHz;
        m_frequencyText = formatFrequency(state.frequencyHz);
        m_frequencyMhzText = formatFrequencyMhz(state.frequencyHz);
        m_bandText = bandForFrequency(state.frequencyHz);
        emit frequencyChanged();
    }

    if (state.modeValid) {
        const QString newMode = modeName(state.modeCode);
        const QString newFilter =
            filterName(state.filterCode);

        if (m_modeCode != state.modeCode
            || m_modeText != newMode) {
            m_modeCode = state.modeCode;
            m_modeText = newMode;
            emit modeChanged();
        }

        if (m_filterCode != state.filterCode
            || m_filterText != newFilter) {
            m_filterCode = state.filterCode;
            m_filterText = newFilter;
            emit filterChanged();
        }

        if (m_dataMode != state.dataMode) {
            m_dataMode = state.dataMode;
            emit dataModeChanged();
        }
    }
}

void RadioController::emitVfoStateSignal(int vfoNumber)
{
    if (vfoNumber == 0) {
        emit vfoAStateChanged();
    } else if (vfoNumber == 1) {
        emit vfoBStateChanged();
    }
}

int RadioController::actualVfoForSelector(
    quint8 selector
) const
{
    const int selected =
        (m_selectedVfo == 1) ? 1 : 0;

    return selector == 0x00
           ? selected
           : 1 - selected;
}

quint8 RadioController::selectorForActualVfo(
    int vfoNumber
) const
{
    const int selected =
        (m_selectedVfo == 1) ? 1 : 0;

    return vfoNumber == selected
           ? quint8(0x00)
           : quint8(0x01);
}

void RadioController::updateMode(quint8 modeCode)
{
    const QString newMode = modeName(modeCode);
    m_modeCode = modeCode;

    if (newMode != m_modeText) {
        m_modeText = newMode;
        emit modeChanged();
    }

    const int activeVfo =
        (m_selectedVfo == 1) ? 1 : 0;
    VfoState &state = m_vfoStates[activeVfo];

    if (!state.modeValid
        || state.modeCode != modeCode) {
        state.modeCode = modeCode;
        state.modeValid = true;
        emitVfoStateSignal(activeVfo);
    }
}

void RadioController::updateFilter(quint8 filterCode)
{
    if (filterCode >= 1 && filterCode <= 3) {
        m_filterCode = filterCode;
    }

    const QString newFilter = filterName(filterCode);

    if (newFilter != m_filterText) {
        m_filterText = newFilter;
        emit filterChanged();
    }

    if (filterCode >= 1 && filterCode <= 3) {
        const int activeVfo =
            (m_selectedVfo == 1) ? 1 : 0;
        VfoState &state = m_vfoStates[activeVfo];

        if (!state.modeValid
            || state.filterCode != filterCode) {
            state.filterCode = filterCode;
            state.modeValid = true;
            emitVfoStateSignal(activeVfo);
        }
    }
}

void RadioController::updateDataMode(quint8 dataCode)
{
    const bool value = dataCode == 0x01;

    if (value != m_dataMode) {
        m_dataMode = value;
        emit dataModeChanged();
    }

    const int activeVfo =
        (m_selectedVfo == 1) ? 1 : 0;
    VfoState &state = m_vfoStates[activeVfo];

    if (!state.modeValid
        || state.dataMode != value) {
        state.dataMode = value;
        state.modeValid = true;
        emitVfoStateSignal(activeVfo);
    }
}

void RadioController::updateTxStatus(quint8 txCode)
{
    const bool value = txCode == 0x01;
    const bool wasTransmitting =
        m_transmitting;

    m_txStateKnown = true;

    if (!value) {
        m_pttOwned = false;
    }

    if (value != m_transmitting) {
        m_transmitting = value;
        emit transmittingChanged();
    }

    if (wasTransmitting
        && !value
        && m_deferredMemoryReadPending) {
        setActionStatus(
            QStringLiteral(
                "Radio en RX · iniciando la lectura de memorias aplazada…"
            )
        );
        QTimer::singleShot(
            0,
            this,
            &RadioController::runDeferredMemoryRead
        );
    }
}

void RadioController::updateSplit(quint8 value)
{
    const bool enabled = value == 0x01;
    if (enabled != m_splitEnabled) {
        m_splitEnabled = enabled;
        emit splitChanged();
    }
}

void RadioController::updateRitOffset(const QByteArray &data)
{
    bool ok = false;
    const int value = decodeRitOffset(data, ok);
    if (ok && value != m_ritOffsetHz) {
        m_ritOffsetHz = value;
        emit ritChanged();
    }
}

void RadioController::updateRitEnabled(quint8 value)
{
    const bool enabled = value == 0x01;
    if (enabled != m_ritEnabled) {
        m_ritEnabled = enabled;
        emit ritChanged();
    }
}

void RadioController::updateDeltaTxEnabled(quint8 value)
{
    const bool enabled = value == 0x01;
    if (enabled != m_deltaTxEnabled) {
        m_deltaTxEnabled = enabled;
        emit deltaTxChanged();
    }
}

void RadioController::updateLevel(QueryKind kind, const QByteArray &data)
{
    const int percent = decodeLevel(data);
    if (percent < 0) return;

    switch (kind) {
    case QueryKind::AfGain:
        if (percent != m_afGain) { m_afGain = percent; emit afGainChanged(); }
        break;
    case QueryKind::RfGain:
        if (percent != m_rfGain) { m_rfGain = percent; emit rfGainChanged(); }
        break;
    case QueryKind::Squelch:
        if (percent != m_squelch) { m_squelch = percent; emit squelchChanged(); }
        break;
    case QueryKind::RfPower:
        if (percent != m_rfPower) { m_rfPower = percent; emit rfPowerChanged(); }
        break;
    default:
        break;
    }
}

void RadioController::updatePreamp(quint8 value)
{
    const int newValue = std::clamp(int(value), 0, 2);
    if (newValue != m_preamp) {
        m_preamp = newValue;
        emit preampChanged();
    }
}

void RadioController::updateAttenuator(quint8 value)
{
    const bool enabled = value == 0x20;
    if (enabled != m_attenuatorEnabled) {
        m_attenuatorEnabled = enabled;
        emit attenuatorChanged();
    }
}

void RadioController::updateTuner(quint8 value)
{
    const int state = std::clamp(int(value), 0, 2);
    if (state != m_tunerState) {
        m_tunerState = state;
        emit tunerChanged();
    }
}

void RadioController::updateAgc(quint8 value)
{
    const int newValue = std::clamp(int(value), 1, 3);
    if (newValue != m_agc) {
        m_agc = newValue;
        emit agcChanged();
    }
}


void RadioController::updateAdvancedSwitch(
    QueryKind kind,
    quint8 value
)
{
    bool changed = false;

    switch (kind) {
    case QueryKind::NoiseBlanker: {
        const bool enabled = value == 0x01;
        if (enabled != m_noiseBlankerEnabled) {
            m_noiseBlankerEnabled = enabled;
            changed = true;
        }
        break;
    }
    case QueryKind::NoiseReduction: {
        const bool enabled = value == 0x01;
        if (enabled != m_noiseReductionEnabled) {
            m_noiseReductionEnabled = enabled;
            changed = true;
        }
        break;
    }
    case QueryKind::AutoNotch: {
        const bool enabled = value == 0x01;
        if (enabled != m_autoNotchEnabled) {
            m_autoNotchEnabled = enabled;
            changed = true;
        }
        break;
    }
    case QueryKind::ManualNotch: {
        const bool enabled = value == 0x01;
        if (enabled != m_manualNotchEnabled) {
            m_manualNotchEnabled = enabled;
            changed = true;
        }
        break;
    }
    case QueryKind::ManualNotchWidth: {
        const int width = std::clamp(int(value), 0, 2);
        if (width != m_manualNotchWidth) {
            m_manualNotchWidth = width;
            changed = true;
        }
        break;
    }
    case QueryKind::IpPlus: {
        const bool enabled = value == 0x01;
        if (enabled != m_ipPlusEnabled) {
            m_ipPlusEnabled = enabled;
            changed = true;
        }
        break;
    }
    case QueryKind::FilterShape: {
        const int shape = std::clamp(int(value), 0, 1);
        if (shape != m_filterShape) {
            m_filterShape = shape;
            changed = true;
        }
        break;
    }
    default:
        break;
    }

    if (changed) {
        emit advancedReceiveChanged();
    }
}

void RadioController::updateAdvancedLevel(
    QueryKind kind,
    const QByteArray &data
)
{
    const int percent = decodeLevel(data);
    if (percent < 0) {
        return;
    }

    bool changed = false;

    switch (kind) {
    case QueryKind::NoiseBlankerLevel:
        if (percent != m_noiseBlankerLevel) {
            m_noiseBlankerLevel = percent;
            changed = true;
        }
        break;
    case QueryKind::NoiseReductionLevel:
        if (percent != m_noiseReductionLevel) {
            m_noiseReductionLevel = percent;
            changed = true;
        }
        break;
    case QueryKind::Pbt1:
        if (percent != m_pbt1) {
            m_pbt1 = percent;
            changed = true;
        }
        break;
    case QueryKind::Pbt2:
        if (percent != m_pbt2) {
            m_pbt2 = percent;
            changed = true;
        }
        break;
    case QueryKind::ManualNotchPosition:
        if (percent != m_manualNotchPosition) {
            m_manualNotchPosition = percent;
            changed = true;
        }
        break;
    default:
        break;
    }

    if (changed) {
        emit advancedReceiveChanged();
    }
}

void RadioController::updateMeter(
    QueryKind kind,
    const QByteArray &data
)
{
    const int raw = decodeRawLevel(data);
    if (raw < 0) {
        return;
    }

    switch (kind) {
    case QueryKind::Smeter: {
        m_sMeterPercent =
            std::clamp(int(std::lround(raw * 100.0 / 241.0)), 0, 100);

        if (raw <= 120) {
            const double sValue = raw * 9.0 / 120.0;
            m_sMeterText =
                QStringLiteral("S%1").arg(
                    QString::number(sValue, 'f', 1)
                );
        } else {
            const int db =
                int(std::lround((raw - 120) * 60.0 / 121.0));
            m_sMeterText =
                QStringLiteral("S9+%1 dB").arg(db);
        }
        break;
    }

    case QueryKind::PowerMeter: {
        double percent = 0.0;
        if (raw <= 143) {
            percent = raw * 50.0 / 143.0;
        } else {
            percent = 50.0 + (raw - 143) * 50.0 / 70.0;
        }
        m_powerMeterPercent =
            std::clamp(int(std::lround(percent)), 0, 100);
        m_powerMeterText =
            QStringLiteral("%1 %").arg(m_powerMeterPercent);
        break;
    }

    case QueryKind::SwrMeter: {
        double swr = 1.0;
        if (raw <= 48) {
            swr = 1.0 + raw * 0.5 / 48.0;
        } else if (raw <= 80) {
            swr = 1.5 + (raw - 48) * 0.5 / 32.0;
        } else if (raw <= 120) {
            swr = 2.0 + (raw - 80) * 1.0 / 40.0;
        } else {
            swr = 3.0 + (raw - 120) * 7.0 / 135.0;
        }

        m_swrMeterPercent =
            std::clamp(int(std::lround(raw * 100.0 / 120.0)), 0, 100);
        m_swrMeterText =
            QString::number(swr, 'f', 1).replace('.', ',');
        if (m_pttOwned && swr > 2.5) {
            forceReceive();
            setActionStatus(QStringLiteral(
                "TX desactivado por SWR alto (%1)"
            ).arg(QString::number(swr, 'f', 1).replace('.', ',')));
        }
        break;
    }

    case QueryKind::AlcMeter:
        m_alcMeterPercent =
            std::clamp(int(std::lround(raw * 100.0 / 120.0)), 0, 100);
        m_alcMeterText =
            QStringLiteral("%1 %").arg(m_alcMeterPercent);
        break;

    case QueryKind::CompMeter: {
        double db = 0.0;
        if (raw <= 130) {
            db = raw * 15.0 / 130.0;
        } else {
            db = 15.0 + (raw - 130) * 15.0 / 80.0;
        }

        m_compMeterPercent =
            std::clamp(int(std::lround(db * 100.0 / 30.0)), 0, 100);
        m_compMeterText =
            QStringLiteral("%1 dB")
                .arg(QString::number(db, 'f', 1).replace('.', ','));
        break;
    }

    case QueryKind::VoltageMeter: {
        double volts = 0.0;
        if (raw <= 13) {
            volts = raw * 10.0 / 13.0;
        } else {
            volts = 10.0 + (raw - 13) * 6.0 / 228.0;
        }

        m_voltageMeterPercent =
            std::clamp(int(std::lround(volts * 100.0 / 16.0)), 0, 100);
        m_voltageMeterText =
            QStringLiteral("%1 V")
                .arg(QString::number(volts, 'f', 1).replace('.', ','));
        break;
    }

    case QueryKind::CurrentMeter: {
        double amps = 0.0;
        if (raw <= 97) {
            amps = raw * 10.0 / 97.0;
        } else if (raw <= 146) {
            amps = 10.0 + (raw - 97) * 5.0 / 49.0;
        } else {
            amps = 15.0 + (raw - 146) * 10.0 / 95.0;
        }

        m_currentMeterPercent =
            std::clamp(int(std::lround(amps * 100.0 / 25.0)), 0, 100);
        m_currentMeterText =
            QStringLiteral("%1 A")
                .arg(QString::number(amps, 'f', 1).replace('.', ','));
        break;
    }

    default:
        return;
    }

    emit metersChanged();
}

void RadioController::updateOverflow(quint8 value)
{
    const bool active = value == 0x01;
    if (active != m_overflow) {
        m_overflow = active;
        emit metersChanged();
    }
}


void RadioController::updateSquelchState(
    QueryKind kind,
    quint8 value
)
{
    const bool open = value == 0x01;
    bool changed = false;

    if (kind == QueryKind::SquelchBasic
        && open != m_basicSquelchOpen) {
        m_basicSquelchOpen = open;
        changed = true;
    }

    if (kind == QueryKind::SquelchFull
        && open != m_squelchOpen) {
        m_squelchOpen = open;
        changed = true;
    }

    if (changed) {
        emit squelchStateChanged();
    }
}

void RadioController::updateRadioTuningStep(quint8 value)
{
    const int code = std::clamp(int(value), 0, 8);

    if (code == m_radioTuningStepCode) {
        return;
    }

    m_radioTuningStepCode = code;
    emit radioTuningStepChanged();
}

void RadioController::updateXfc(quint8 value)
{
    const bool enabled = value == 0x01;

    if (enabled == m_xfcEnabled) {
        return;
    }

    m_xfcEnabled = enabled;
    emit xfcChanged();
}

void RadioController::updateCivOutput(quint8 value)
{
    const bool enabled = value == 0x01;

    if (enabled == m_civOutputEnabled) {
        return;
    }

    m_civOutputEnabled = enabled;
    emit civSettingsChanged();
}

void RadioController::updateTxFrequency(
    const QByteArray &fiveBcdBytes
)
{
    bool ok = false;
    const quint64 frequency =
        decodeFrequencyValue(fiveBcdBytes, ok);

    if (!ok) {
        return;
    }

    if (frequency != m_txFrequencyHz) {
        m_txFrequencyHz = frequency;
        m_txFrequencyText = formatFrequency(frequency);
        emit txFrequencyChanged();
    }
}

void RadioController::updateTxBandCount(quint8 value)
{
    int count = isBcdByte(value)
                    ? bcdByteToInt(value)
                    : int(value);

    count = std::clamp(count, 0, 30);

    if (m_txBandCount != count) {
        m_txBandCount = count;
        m_txBandEdges.clear();
        m_nextTxBandEdgeIndex = 1;
        emit capabilitiesChanged();
    }

    if (count == 0) {
        return;
    }
}

void RadioController::updateTxBandEdge(
    const QByteArray &frame
)
{
    if (frame.size() < 20) {
        return;
    }

    const quint8 encodedNumber = quint8(frame.at(6));
    const int number = isBcdByte(encodedNumber)
                           ? bcdByteToInt(encodedNumber)
                           : int(encodedNumber);

    bool lowerOk = false;
    bool upperOk = false;

    const quint64 lower =
        decodeFrequencyValue(frame.mid(7, 5), lowerOk);
    const quint64 upper =
        decodeFrequencyValue(frame.mid(14, 5), upperOk);

    if (!lowerOk || !upperOk || number <= 0) {
        return;
    }

    bool replaced = false;

    for (TxBandEdge &edge : m_txBandEdges) {
        if (edge.number == number) {
            edge.lowerHz = lower;
            edge.upperHz = upper;
            replaced = true;
            break;
        }
    }

    if (!replaced) {
        TxBandEdge edge;
        edge.number = number;
        edge.lowerHz = lower;
        edge.upperHz = upper;
        m_txBandEdges.append(edge);

        std::sort(
            m_txBandEdges.begin(),
            m_txBandEdges.end(),
            [](const TxBandEdge &left,
               const TxBandEdge &right) {
                return left.number < right.number;
            }
        );
    }

    if (number >= m_nextTxBandEdgeIndex) {
        m_nextTxBandEdgeIndex = number + 1;
    }

    emit capabilitiesChanged();
}


void RadioController::updateTxAudioLevel(
    QueryKind kind,
    const QByteArray &data
)
{
    const int percent = decodeLevel(data);
    if (percent < 0) {
        return;
    }

    bool changed = false;

    switch (kind) {
    case QueryKind::MicrophoneGain:
        if (m_microphoneGain != percent) {
            m_microphoneGain = percent;
            changed = true;
        }
        break;

    case QueryKind::SpeechCompressorLevel: {
        const int level =
            std::clamp(int(std::lround(percent / 10.0)), 0, 10);
        if (m_speechCompressorLevel != level) {
            m_speechCompressorLevel = level;
            changed = true;
        }
        break;
    }

    case QueryKind::MonitorLevel:
        if (m_monitorLevel != percent) {
            m_monitorLevel = percent;
            changed = true;
        }
        break;

    case QueryKind::VoxGain:
        if (m_voxGain != percent) {
            m_voxGain = percent;
            changed = true;
        }
        break;

    case QueryKind::AntiVoxGain:
        if (m_antiVoxGain != percent) {
            m_antiVoxGain = percent;
            changed = true;
        }
        break;

    default:
        break;
    }

    if (changed) {
        emit txAudioChanged();
    }
}

void RadioController::updateTxAudioSwitch(
    QueryKind kind,
    quint8 value
)
{
    bool changed = false;

    switch (kind) {
    case QueryKind::SpeechCompressor: {
        const bool enabled = value == 0x01;
        if (m_speechCompressorEnabled != enabled) {
            m_speechCompressorEnabled = enabled;
            changed = true;
        }
        break;
    }

    case QueryKind::Monitor: {
        const bool enabled = value == 0x01;
        if (m_monitorEnabled != enabled) {
            m_monitorEnabled = enabled;
            changed = true;
        }
        break;
    }

    case QueryKind::Vox: {
        const bool enabled = value == 0x01;
        if (m_voxEnabled != enabled) {
            m_voxEnabled = enabled;
            changed = true;
        }
        break;
    }

    case QueryKind::TxFilterWidth: {
        const int width = std::clamp(int(value), 0, 2);
        if (m_txFilterWidth != width) {
            m_txFilterWidth = width;
            changed = true;
        }
        break;
    }

    case QueryKind::TxInhibit: {
        const bool enabled = value == 0x01;
        if (m_txInhibitEnabled != enabled) {
            m_txInhibitEnabled = enabled;
            changed = true;
        }
        break;
    }

    default:
        break;
    }

    if (changed) {
        emit txAudioChanged();
    }
}


void RadioController::updateCwLevel(
    QueryKind kind,
    const QByteArray &data
)
{
    const int raw = decodeRawLevel(data);
    if (raw < 0) {
        return;
    }

    bool changed = false;

    switch (kind) {
    case QueryKind::CwApfPeak: {
        const int value = rawToRange(raw, -550, 550, 10);
        if (m_cwApfPeakOffsetHz != value) {
            m_cwApfPeakOffsetHz = value;
            changed = true;
        }
        break;
    }

    case QueryKind::CwPitch: {
        const int value = rawToRange(raw, 300, 900, 5);
        if (m_cwPitchHz != value) {
            m_cwPitchHz = value;
            changed = true;
        }
        break;
    }

    case QueryKind::CwKeySpeed: {
        const int value = rawToRange(raw, 6, 48, 1);
        if (m_cwKeySpeedWpm != value) {
            m_cwKeySpeedWpm = value;
            changed = true;
        }
        break;
    }

    case QueryKind::CwBreakInDelay: {
        const int value = rawToRange(raw, 20, 130, 1);
        if (m_cwBreakInDelayTenths != value) {
            m_cwBreakInDelayTenths = value;
            changed = true;
        }
        break;
    }

    default:
        break;
    }

    if (changed) {
        emit cwSettingsChanged();
    }
}

void RadioController::updateCwSwitch(
    QueryKind kind,
    quint8 value
)
{
    bool changed = false;

    if (kind == QueryKind::ApfMode) {
        const int mode = std::clamp(int(value), 0, 3);
        if (m_apfMode != mode) {
            m_apfMode = mode;
            changed = true;
        }
    } else if (kind == QueryKind::BreakInMode) {
        const int mode = std::clamp(int(value), 0, 2);
        if (m_breakInMode != mode) {
            m_breakInMode = mode;
            changed = true;
        }
    }

    if (changed) {
        emit cwSettingsChanged();
    }
}

void RadioController::updateCwMenuSetting(
    quint8 item,
    const QByteArray &data
)
{
    bool changed = false;

    switch (item) {
    case 0x18: {
        const int level = decodeLevel(data.left(2));
        if (level >= 0 && m_sideToneLevel != level) {
            m_sideToneLevel = level;
            changed = true;
        }
        break;
    }

    case 0x19:
        if (!data.isEmpty()) {
            const bool enabled = quint8(data.at(0)) == 0x01;
            if (m_sideToneLimitEnabled != enabled) {
                m_sideToneLimitEnabled = enabled;
                changed = true;
            }
        }
        break;

    case 0x20:
        if (!data.isEmpty() && isBcdByte(quint8(data.at(0)))) {
            const int seconds =
                std::clamp(
                    bcdByteToInt(quint8(data.at(0))),
                    1,
                    60
                );
            if (m_keyerRepeatSeconds != seconds) {
                m_keyerRepeatSeconds = seconds;
                changed = true;
            }
        }
        break;

    case 0x21:
        if (!data.isEmpty() && isBcdByte(quint8(data.at(0)))) {
            const int ratio =
                std::clamp(
                    bcdByteToInt(quint8(data.at(0))),
                    28,
                    45
                );
            if (m_dotDashRatioTenths != ratio) {
                m_dotDashRatioTenths = ratio;
                changed = true;
            }
        }
        break;

    case 0x22:
        if (!data.isEmpty()) {
            const int milliseconds =
                2 + 2 * std::clamp(int(quint8(data.at(0))), 0, 3);
            if (m_riseTimeMs != milliseconds) {
                m_riseTimeMs = milliseconds;
                changed = true;
            }
        }
        break;

    case 0x23:
        if (!data.isEmpty()) {
            const bool reversed = quint8(data.at(0)) == 0x01;
            if (m_paddleReversed != reversed) {
                m_paddleReversed = reversed;
                changed = true;
            }
        }
        break;

    case 0x24:
        if (!data.isEmpty()) {
            const int type =
                std::clamp(int(quint8(data.at(0))), 0, 2);
            if (m_keyType != type) {
                m_keyType = type;
                changed = true;
            }
        }
        break;

    case 0x25:
        if (!data.isEmpty()) {
            const bool enabled = quint8(data.at(0)) == 0x01;
            if (m_micUpDownKeyerEnabled != enabled) {
                m_micUpDownKeyerEnabled = enabled;
                changed = true;
            }
        }
        break;

    case 0x26:
        if (!data.isEmpty()) {
            const bool enabled = quint8(data.at(0)) == 0x01;
            if (m_cwDecodeDisplayEnabled != enabled) {
                m_cwDecodeDisplayEnabled = enabled;
                changed = true;
            }
        }
        break;

    default:
        break;
    }

    if (changed) {
        emit cwSettingsChanged();
    }
}

void RadioController::updateKeyerMemory(
    int channel,
    const QByteArray &data
)
{
    if (channel < 1 || channel > 8) {
        return;
    }

    QByteArray cleaned = data;

    while (!cleaned.isEmpty()
           && (cleaned.endsWith(' ')
               || cleaned.endsWith(char(0x00)))) {
        cleaned.chop(1);
    }

    const QString text = QString::fromLatin1(cleaned);
    const int index = channel - 1;

    if (index >= m_keyerMemories.size()) {
        return;
    }

    if (m_keyerMemories.at(index) != text) {
        m_keyerMemories[index] = text;
        emit keyerMemoriesChanged();
    }
}


void RadioController::updateToneRttySwitch(
    QueryKind kind,
    quint8 value
)
{
    const bool enabled = value == 0x01;
    bool changed = false;

    switch (kind) {
    case QueryKind::RepeaterTone:
        if (m_repeaterToneEnabled != enabled) {
            m_repeaterToneEnabled = enabled;
            changed = true;
        }
        break;

    case QueryKind::ToneSquelch:
        if (m_toneSquelchEnabled != enabled) {
            m_toneSquelchEnabled = enabled;
            changed = true;
        }
        break;

    case QueryKind::TwinPeak:
        if (m_twinPeakEnabled != enabled) {
            m_twinPeakEnabled = enabled;
            changed = true;
        }
        break;

    default:
        break;
    }

    if (changed) {
        emit toneRttyChanged();
    }
}

void RadioController::updateToneFrequency(
    QueryKind kind,
    const QByteArray &data
)
{
    const int tenthsHz = decodeToneFrequency(data);
    if (tenthsHz < 0) {
        return;
    }

    bool changed = false;

    if (kind == QueryKind::RepeaterToneFrequency
        && m_repeaterToneTenthsHz != tenthsHz) {
        m_repeaterToneTenthsHz = tenthsHz;
        changed = true;
    } else if (kind == QueryKind::ToneSquelchFrequency
               && m_toneSquelchTenthsHz != tenthsHz) {
        m_toneSquelchTenthsHz = tenthsHz;
        changed = true;
    }

    if (changed) {
        emit toneRttyChanged();
    }
}

void RadioController::updateRttyMenuSetting(
    quint8 item,
    quint8 value
)
{
    bool changed = false;

    switch (item) {
    case 0x39: {
        const int code = std::clamp(int(value), 0, 2);
        if (m_rttyMarkFrequencyCode != code) {
            m_rttyMarkFrequencyCode = code;
            changed = true;
        }
        break;
    }

    case 0x40: {
        const int code = std::clamp(int(value), 0, 2);
        if (m_rttyShiftWidthCode != code) {
            m_rttyShiftWidthCode = code;
            changed = true;
        }
        break;
    }

    case 0x41: {
        const bool reversed = value == 0x01;
        if (m_rttyKeyingReverse != reversed) {
            m_rttyKeyingReverse = reversed;
            changed = true;
        }
        break;
    }

    default:
        break;
    }

    if (changed) {
        emit toneRttyChanged();
    }
}


void RadioController::updateMemoryContent(
    const QByteArray &data
)
{
    if (data.size() < 3) {
        return;
    }

    const int channel = decodeMemoryChannel(data.left(2));
    if (channel < 1 || channel > 99) {
        return;
    }

    MemoryState memory;
    memory.loaded = true;

    if (quint8(data.at(2)) == 0xFF) {
        memory.blank = true;
        m_memories[channel - 1] = memory;
        markMemoriesChanged();

        if (m_memoryReadBatchActive
            && channel == m_pendingMemoryReadChannel) {
            ++m_memoryReadSuccessCount;
        }

        setActionStatus(
            QStringLiteral("M%1 leída · canal vacío")
                .arg(channel, 2, 10, QLatin1Char('0'))
        );
        return;
    }

    // Los bytes anteriores al nombre son siempre 31.
    // El nombre puede contener de 0 a 16 caracteres; la radio no está
    // obligada a rellenarlo con espacios hasta alcanzar 16 bytes.
    if (data.size() < 31) {
        if (m_memoryReadBatchActive
            && channel == m_pendingMemoryReadChannel) {
            ++m_memoryReadFailureCount;
        }

        setActionStatus(
            QStringLiteral(
                "Respuesta incompleta al leer M%1 (%2 bytes)"
            )
                .arg(channel, 2, 10, QLatin1Char('0'))
                .arg(data.size())
        );
        return;
    }

    memory.blank = false;

    QByteArray canonicalRaw = data.left(47);
    if (canonicalRaw.size() < 47) {
        canonicalRaw.append(QByteArray(47 - canonicalRaw.size(), char(0x20)));
    }

    const bool verifyingEditedMemory =
        channel == m_memoryEditVerifyChannel
        && m_memoryEditExpectedRaw.size() == 47;
    const bool verifiedExactly =
        verifyingEditedMemory && canonicalRaw == m_memoryEditExpectedRaw;

    if (verifyingEditedMemory && !verifiedExactly
        && m_memoryEditVerifyAttempt < 3) {
        if (m_memoryReadBatchActive && channel == m_pendingMemoryReadChannel)
            ++m_memoryReadSuccessCount;
        setActionStatus(QStringLiteral("M%1 aún devuelve los datos anteriores · se repetirá la verificación")
            .arg(channel, 2, 10, QLatin1Char('0')));
        scheduleMemoryEditVerification(700);
        return;
    }

    memory.raw = canonicalRaw;

    const quint8 flags = quint8(data.at(2));
    memory.split = ((flags >> 4) & 0x0F) == 0x01;
    memory.selectGroup = std::clamp(int(flags & 0x0F), 0, 3);

    bool receiveFrequencyOk = false;
    memory.receiveFrequencyHz =
        decodeFrequencyValue(data.mid(3, 5), receiveFrequencyOk);
    if (!receiveFrequencyOk) {
        memory.receiveFrequencyHz = 0;
    }

    memory.receiveMode = quint8(data.at(8));
    memory.receiveFilter = quint8(data.at(9));

    const quint8 receiveDataTone = quint8(data.at(10));
    memory.receiveDataMode =
        ((receiveDataTone >> 4) & 0x0F) == 0x01;
    memory.toneType =
        std::clamp(int(receiveDataTone & 0x0F), 0, 2);
    memory.repeaterToneTenthsHz =
        std::max(0, decodeToneFrequency(data.mid(11, 3)));
    memory.toneSquelchTenthsHz =
        std::max(0, decodeToneFrequency(data.mid(14, 3)));

    bool transmitFrequencyOk = false;
    memory.transmitFrequencyHz =
        decodeFrequencyValue(data.mid(17, 5), transmitFrequencyOk);
    if (!transmitFrequencyOk) {
        memory.transmitFrequencyHz = memory.receiveFrequencyHz;
    }

    memory.transmitMode = quint8(data.at(22));
    memory.transmitFilter = quint8(data.at(23));

    const quint8 transmitDataTone = quint8(data.at(24));
    memory.transmitDataMode =
        ((transmitDataTone >> 4) & 0x0F) == 0x01;
    memory.transmitToneType =
        std::clamp(int(transmitDataTone & 0x0F), 0, 2);

    const qsizetype availableNameBytes =
        std::max<qsizetype>(
            0,
            std::min<qsizetype>(
                16,
                data.size() - 31
            )
        );

    QByteArray nameBytes =
        availableNameBytes > 0
        ? data.mid(31, availableNameBytes)
        : QByteArray();

    while (!nameBytes.isEmpty()
           && (nameBytes.endsWith(char(0x20))
               || nameBytes.endsWith(char(0x00)))) {
        nameBytes.chop(1);
    }

    memory.name = QString::fromLatin1(nameBytes);

    m_memories[channel - 1] = memory;
    markMemoriesChanged();

    if (m_memoryReadBatchActive
        && channel == m_pendingMemoryReadChannel) {
        ++m_memoryReadSuccessCount;
    }

    if (verifyingEditedMemory) {
        const bool finalMatch = memory.raw == m_memoryEditExpectedRaw;
        m_memoryEditVerifyChannel = 0;
        m_memoryEditExpectedRaw.clear();
        m_memoryEditVerifyAttempt = 0;
        setActionStatus(
            finalMatch
            ? QStringLiteral("M%1 guardada, recuperada y verificada correctamente")
                  .arg(channel, 2, 10, QLatin1Char('0'))
            : QStringLiteral("M%1 se releyó, pero la radio devolvió valores distintos")
                  .arg(channel, 2, 10, QLatin1Char('0'))
        );
        return;
    }

    setActionStatus(
        memory.name.isEmpty()
        ? QStringLiteral("M%1 leída · sin nombre")
              .arg(channel, 2, 10, QLatin1Char('0'))
        : QStringLiteral("M%1 leída · %2")
              .arg(channel, 2, 10, QLatin1Char('0'))
              .arg(memory.name)
    );
}

void RadioController::updateScanSetting(
    quint8 item,
    quint8 value
)
{
    bool changed = false;

    if (item == 0x53) {
        const bool fast = value == 0x01;
        if (m_scanSpeedFast != fast) {
            m_scanSpeedFast = fast;
            changed = true;
        }
    } else if (item == 0x54) {
        const bool enabled = value == 0x01;
        if (m_scanResumeEnabled != enabled) {
            m_scanResumeEnabled = enabled;
            changed = true;
        }
    }

    if (changed) {
        emit scanChanged();
    }
}


void RadioController::updateBandStacking(
    const QByteArray &data
)
{
    if (data.size() < 16) {
        return;
    }

    const int bandCode = int(quint8(data.at(0)));
    const int registerCode = int(quint8(data.at(1)));

    if (bandCode < 1 || bandCode > 11
        || registerCode < 1 || registerCode > 3) {
        return;
    }

    BandStackingState state;
    state.loaded = true;
    state.raw = data.mid(2, 14);

    bool frequencyOk = false;
    state.frequencyHz =
        decodeFrequencyValue(data.mid(2, 5), frequencyOk);
    if (!frequencyOk) {
        state.frequencyHz = 0;
    }

    state.mode = quint8(data.at(7));
    state.filter = quint8(data.at(8));

    const quint8 dataTone = quint8(data.at(9));
    state.dataMode = ((dataTone >> 4) & 0x0F) == 0x01;
    state.toneType =
        std::clamp(int(dataTone & 0x0F), 0, 2);
    state.repeaterToneTenthsHz =
        std::max(0, decodeToneFrequency(data.mid(10, 3)));
    state.toneSquelchTenthsHz =
        std::max(0, decodeToneFrequency(data.mid(13, 3)));

    const int index =
        (bandCode - 1) * 3 + (registerCode - 1);
    m_bandStackingRegisters[index] = state;
    emit bandStackingChanged();
}

void RadioController::updateVfo(int vfoNumber)
{
    if (vfoNumber < 0 || vfoNumber > 1) {
        return;
    }

    if (vfoNumber != m_selectedVfo) {
        m_selectedVfo = vfoNumber;
        emit vfoChanged();
        syncActiveStateFromSelectedVfo();

        // Al cambiar la referencia seleccionado/no seleccionado,
        // se vuelven a consultar ambos VFO inmediatamente.
        m_nextQueryIndex =
            int(QueryKind::VfoSelectedFrequency);
    }
}

QByteArray RadioController::modeDataFilterPayload(quint8 modeCode,
                                                   bool dataEnabled,
                                                   quint8 filterCode) const
{
    QByteArray payload;
    payload.append(char(0x26));
    payload.append(char(0x00));
    payload.append(char(modeCode));
    payload.append(char(dataEnabled ? 0x01 : 0x00));
    payload.append(char(filterCode));
    return payload;
}


quint8 RadioController::encodeBcdNumber(int value)
{
    value = std::clamp(value, 0, 99);
    return quint8(((value / 10) << 4) | (value % 10));
}

QByteArray RadioController::encodeMemoryChannel(int channel)
{
    channel = std::clamp(channel, 1, 99);

    QByteArray data;
    data.append(char(0x00));
    data.append(char(encodeBcdNumber(channel)));
    return data;
}

int RadioController::decodeMemoryChannel(
    const QByteArray &data
)
{
    if (data.size() < 2) {
        return -1;
    }

    const quint8 high = quint8(data.at(0));
    const quint8 low = quint8(data.at(1));

    if (!isBcdByte(high) || !isBcdByte(low)) {
        return -1;
    }

    return bcdByteToInt(high) * 100 + bcdByteToInt(low);
}

bool RadioController::validateMemoryName(
    const QString &name,
    QByteArray &encoded,
    QString &errorText
)
{
    encoded.clear();
    errorText.clear();

    if (name.size() > 16) {
        errorText =
            QStringLiteral("El nombre admite un máximo de 16 caracteres");
        return false;
    }

    encoded = name.toLatin1();
    if (QString::fromLatin1(encoded) != name) {
        errorText =
            QStringLiteral("El nombre contiene caracteres no ASCII");
        encoded.clear();
        return false;
    }

    for (const char character : encoded) {
        const quint8 value = quint8(character);
        if (value < 0x20 || value > 0x7E) {
            errorText =
                QStringLiteral("El nombre contiene un carácter no permitido");
            encoded.clear();
            return false;
        }
    }

    return true;
}

QByteArray RadioController::encodeFrequency(quint64 frequencyHz)
{
    QByteArray result;
    result.reserve(5);
    for (int i = 0; i < 5; ++i) {
        const quint8 lowDigit = quint8(frequencyHz % 10);
        frequencyHz /= 10;
        const quint8 highDigit = quint8(frequencyHz % 10);
        frequencyHz /= 10;
        result.append(char((highDigit << 4) | lowDigit));
    }
    return result;
}

quint64 RadioController::decodeFrequencyValue(
    const QByteArray &fiveBcdBytes,
    bool &ok
)
{
    ok = false;

    if (fiveBcdBytes.size() != 5) {
        return 0;
    }

    quint64 frequency = 0;
    quint64 factor = 1;

    for (const char rawByte : fiveBcdBytes) {
        const quint8 byte = quint8(rawByte);
        const quint8 lowDigit = byte & 0x0F;
        const quint8 highDigit = (byte >> 4) & 0x0F;

        if (lowDigit > 9 || highDigit > 9) {
            return 0;
        }

        frequency += quint64(lowDigit) * factor;
        factor *= 10;

        frequency += quint64(highDigit) * factor;
        factor *= 10;
    }

    ok = true;
    return frequency;
}

QByteArray RadioController::encodeLevel(int percent)
{
    const int value =
        int(std::lround(clampPercent(percent) * 255.0 / 100.0));
    return encodeRawLevel(value);
}

QByteArray RadioController::encodeRawLevel(int rawValue)
{
    rawValue = std::clamp(rawValue, 0, 255);

    const int hundreds = rawValue / 100;
    const int remainder = rawValue % 100;

    QByteArray data;
    data.append(char(hundreds));
    data.append(
        char(((remainder / 10) << 4) | (remainder % 10))
    );
    return data;
}

int RadioController::decodeLevel(const QByteArray &data)
{
    if (data.size() != 2) return -1;
    const quint8 first = quint8(data.at(0));
    const quint8 second = quint8(data.at(1));
    if (!isBcdByte(first) || !isBcdByte(second)) return -1;
    const int value = bcdByteToInt(first) * 100 + bcdByteToInt(second);
    if (value < 0 || value > 255) return -1;
    return int(std::lround(value * 100.0 / 255.0));
}


int RadioController::decodeRawLevel(
    const QByteArray &data
)
{
    if (data.size() != 2) {
        return -1;
    }

    const quint8 first = quint8(data.at(0));
    const quint8 second = quint8(data.at(1));

    if (!isBcdByte(first) || !isBcdByte(second)) {
        return -1;
    }

    const int value =
        bcdByteToInt(first) * 100
        + bcdByteToInt(second);

    return (value >= 0 && value <= 255)
           ? value
           : -1;
}


int RadioController::rawToRange(
    int rawValue,
    int minimum,
    int maximum,
    int step
)
{
    rawValue = std::clamp(rawValue, 0, 255);
    step = std::max(step, 1);

    const double normalized = rawValue / 255.0;
    const double unrounded =
        minimum + normalized * (maximum - minimum);

    int value =
        minimum
        + int(std::lround(
              (unrounded - minimum) / step
          )) * step;

    return std::clamp(value, minimum, maximum);
}

int RadioController::rangeToRaw(
    int value,
    int minimum,
    int maximum
)
{
    if (maximum <= minimum) {
        return 0;
    }

    value = std::clamp(value, minimum, maximum);

    const double normalized =
        double(value - minimum)
        / double(maximum - minimum);

    return std::clamp(
        int(std::lround(normalized * 255.0)),
        0,
        255
    );
}

bool RadioController::encodeDirectCwText(
    const QString &text,
    QByteArray &encoded,
    QString &errorText
)
{
    encoded.clear();
    errorText.clear();

    if (text.isEmpty()) {
        errorText = QStringLiteral("Escriba un mensaje CW");
        return false;
    }

    if (text.size() > 30) {
        errorText =
            QStringLiteral("El mensaje CW admite un máximo de 30 caracteres");
        return false;
    }

    static const QByteArray symbols =
        QByteArrayLiteral("/?.-,: '()=+\"@^");

    const QByteArray latin = text.toLatin1();

    if (QString::fromLatin1(latin) != text) {
        errorText =
            QStringLiteral("El mensaje CW contiene caracteres no ASCII");
        return false;
    }

    for (const char character : latin) {
        const bool alphaNumeric =
            (character >= '0' && character <= '9')
            || (character >= 'A' && character <= 'Z')
            || (character >= 'a' && character <= 'z');

        if (!alphaNumeric && !symbols.contains(character)) {
            errorText =
                QStringLiteral(
                    "Carácter no permitido en el mensaje CW: %1"
                ).arg(QChar::fromLatin1(character));
            return false;
        }
    }

    encoded = latin;
    return true;
}

bool RadioController::encodeKeyerMemoryText(
    const QString &text,
    QByteArray &encoded,
    QString &errorText
)
{
    encoded.clear();
    errorText.clear();

    QString normalized = text.toUpper();

    if (normalized.isEmpty()) {
        // La guía indica que uno o más espacios borran la memoria.
        normalized = QStringLiteral(" ");
    }

    if (normalized.size() > 70) {
        errorText =
            QStringLiteral("La memoria Keyer admite un máximo de 70 caracteres");
        return false;
    }

    static const QByteArray symbols =
        QByteArrayLiteral("/?,.@^* ");

    const QByteArray latin = normalized.toLatin1();

    if (QString::fromLatin1(latin) != normalized) {
        errorText =
            QStringLiteral("La memoria Keyer contiene caracteres no ASCII");
        return false;
    }

    for (const char character : latin) {
        const bool alphaNumeric =
            (character >= '0' && character <= '9')
            || (character >= 'A' && character <= 'Z');

        if (!alphaNumeric && !symbols.contains(character)) {
            errorText =
                QStringLiteral(
                    "Carácter no permitido en la memoria Keyer: %1"
                ).arg(QChar::fromLatin1(character));
            return false;
        }
    }

    encoded = latin;
    return true;
}


QByteArray RadioController::encodeToneFrequency(int tenthsHz)
{
    tenthsHz = std::clamp(tenthsHz, 0, 2999);

    const int hundreds = (tenthsHz / 1000) % 10;
    const int tens = (tenthsHz / 100) % 10;
    const int units = (tenthsHz / 10) % 10;
    const int tenths = tenthsHz % 10;

    QByteArray data;
    data.append(char(0x00));
    data.append(char((hundreds << 4) | tens));
    data.append(char((units << 4) | tenths));
    return data;
}

int RadioController::decodeToneFrequency(
    const QByteArray &data
)
{
    if (data.size() < 2) {
        return -1;
    }

    const qsizetype offset =
        data.size() >= 3 ? data.size() - 2 : 0;

    const quint8 high = quint8(data.at(offset));
    const quint8 low = quint8(data.at(offset + 1));

    if (!isBcdByte(high) || !isBcdByte(low)) {
        return -1;
    }

    const int tenthsHz =
        bcdByteToInt(high) * 100
        + bcdByteToInt(low);

    return std::clamp(tenthsHz, 0, 2999);
}

QByteArray RadioController::encodeRitOffset(int offsetHz)
{
    const int bounded = std::clamp(offsetHz, -9999, 9999);
    int value = std::abs(bounded);
    const int ones = value % 10;
    value /= 10;
    const int tens = value % 10;
    value /= 10;
    const int hundreds = value % 10;
    value /= 10;
    const int thousands = value % 10;

    QByteArray data;
    data.append(char((tens << 4) | ones));
    data.append(char((thousands << 4) | hundreds));
    data.append(char(bounded < 0 ? 0x01 : 0x00));
    return data;
}

int RadioController::decodeRitOffset(const QByteArray &data, bool &ok)
{
    ok = false;
    if (data.size() != 3) return 0;
    const quint8 low = quint8(data.at(0));
    const quint8 high = quint8(data.at(1));
    const quint8 sign = quint8(data.at(2));
    if (!isBcdByte(low) || !isBcdByte(high) || sign > 1) return 0;

    const int value = bcdByteToInt(low) + bcdByteToInt(high) * 100;
    ok = true;
    return sign == 0x01 ? -value : value;
}

bool RadioController::parseFrequency(const QString &text,
                                     quint64 &frequencyHz,
                                     QString &errorText)
{
    QString cleaned = text.trimmed().toLower();
    cleaned.remove(QStringLiteral("mhz"));
    cleaned.remove(QStringLiteral("khz"));
    cleaned.remove(QStringLiteral("hz"));
    cleaned.remove(QRegularExpression(QStringLiteral("\\s+")));
    if (cleaned.isEmpty()) {
        errorText = QStringLiteral("Introduzca una frecuencia");
        return false;
    }

    const int separators = cleaned.count(QLatin1Char('.'))
                           + cleaned.count(QLatin1Char(','));
    bool ok = false;
    double hzValue = 0.0;

    if (separators >= 2) {
        cleaned.remove(QLatin1Char('.'));
        cleaned.remove(QLatin1Char(','));
        hzValue = double(cleaned.toULongLong(&ok));
    } else if (separators == 1) {
        cleaned.replace(QLatin1Char(','), QLatin1Char('.'));
        const double value = cleaned.toDouble(&ok);
        if (ok) {
            if (value < 1000.0) hzValue = value * 1'000'000.0;
            else if (value < 100000.0) hzValue = value * 1000.0;
            else hzValue = value;
        }
    } else {
        const qulonglong value = cleaned.toULongLong(&ok);
        if (ok) {
            if (value < 1000ULL) hzValue = double(value) * 1'000'000.0;
            else if (value < 100000ULL) hzValue = double(value) * 1000.0;
            else hzValue = double(value);
        }
    }

    if (!ok || !std::isfinite(hzValue)) {
        errorText = QStringLiteral("Formato de frecuencia no válido");
        return false;
    }

    const quint64 rounded = quint64(std::llround(hzValue));
    if (rounded < 30000ULL || rounded > 74800000ULL) {
        errorText = QStringLiteral("Frecuencia fuera del margen 0,030–74,800 MHz");
        return false;
    }
    frequencyHz = rounded;
    return true;
}

quint8 RadioController::modeCodeForName(const QString &requestedMode)
{
    const QString mode = requestedMode.trimmed().toUpper();
    if (mode == QStringLiteral("LSB")) return 0x00;
    if (mode == QStringLiteral("USB")) return 0x01;
    if (mode == QStringLiteral("AM")) return 0x02;
    if (mode == QStringLiteral("CW")) return 0x03;
    if (mode == QStringLiteral("RTTY")) return 0x04;
    if (mode == QStringLiteral("FM")) return 0x05;
    if (mode == QStringLiteral("CW-R")) return 0x07;
    if (mode == QStringLiteral("RTTY-R")) return 0x08;
    return 0xFF;
}

bool RadioController::modeSupportsData(quint8 modeCode)
{
    return modeCode == 0x00 || modeCode == 0x01
           || modeCode == 0x02 || modeCode == 0x05;
}

int RadioController::clampPercent(int percent)
{
    return std::clamp(percent, 0, 100);
}

QString RadioController::vfoFrequencyText(
    int vfoNumber
) const
{
    if (vfoNumber < 0 || vfoNumber > 1
        || !m_vfoStates[vfoNumber].frequencyValid) {
        return QStringLiteral("---.---.---");
    }

    return formatFrequency(
        m_vfoStates[vfoNumber].frequencyHz
    );
}

QString RadioController::vfoBandText(
    int vfoNumber
) const
{
    if (vfoNumber < 0 || vfoNumber > 1
        || !m_vfoStates[vfoNumber].frequencyValid) {
        return QStringLiteral("—");
    }

    return bandForFrequency(
        m_vfoStates[vfoNumber].frequencyHz
    );
}

QString RadioController::vfoModeText(
    int vfoNumber
) const
{
    if (vfoNumber < 0 || vfoNumber > 1
        || !m_vfoStates[vfoNumber].modeValid) {
        return QStringLiteral("—");
    }

    return modeName(
        m_vfoStates[vfoNumber].modeCode
    );
}

QString RadioController::vfoDataText(
    int vfoNumber
) const
{
    if (vfoNumber < 0 || vfoNumber > 1
        || !m_vfoStates[vfoNumber].modeValid) {
        return QStringLiteral("—");
    }

    return m_vfoStates[vfoNumber].dataMode
           ? QStringLiteral("DATA ON")
           : QStringLiteral("DATA OFF");
}

QString RadioController::vfoFilterText(
    int vfoNumber
) const
{
    if (vfoNumber < 0 || vfoNumber > 1
        || !m_vfoStates[vfoNumber].modeValid) {
        return QStringLiteral("—");
    }

    return filterName(
        m_vfoStates[vfoNumber].filterCode
    );
}

void RadioController::setStatus(const QString &text)
{
    if (text != m_status) { m_status = text; emit statusChanged(); }
}
void RadioController::setActionStatus(const QString &text)
{
    if (text != m_actionStatus) { m_actionStatus = text; emit actionStatusChanged(); }
}
void RadioController::setLastTx(const QByteArray &data)
{
    m_lastTx = formatHex(data);
    ++m_txTrafficSequence;

    m_txTrafficLines.append(
        QStringLiteral("%1  %2")
            .arg(
                m_txTrafficSequence,
                5,
                10,
                QLatin1Char('0')
            )
            .arg(m_lastTx)
    );

    while (m_txTrafficLines.size()
           > TrafficHistoryMaximumLines) {
        m_txTrafficLines.removeFirst();
    }

    emit trafficChanged();
}

void RadioController::setLastRx(const QByteArray &data)
{
    m_lastRx = formatHex(data);
    ++m_rxTrafficSequence;

    m_rxTrafficLines.append(
        QStringLiteral("%1  %2")
            .arg(
                m_rxTrafficSequence,
                5,
                10,
                QLatin1Char('0')
            )
            .arg(m_lastRx)
    );

    while (m_rxTrafficLines.size()
           > TrafficHistoryMaximumLines) {
        m_rxTrafficLines.removeFirst();
    }

    emit trafficChanged();
}

QString RadioController::formatHex(const QByteArray &data)
{
    return QString::fromLatin1(data.toHex(' ').toUpper());
}
QString RadioController::formatFrequency(quint64 frequencyHz)
{
    return QLocale(QLocale::Spanish, QLocale::Spain).toString(frequencyHz);
}
QString RadioController::formatFrequencyMhz(quint64 frequencyHz)
{
    QString text = QString::number(double(frequencyHz) / 1'000'000.0, 'f', 6);
    text.replace(QLatin1Char('.'), QLatin1Char(','));
    return text + QStringLiteral(" MHz");
}
QString RadioController::bandForFrequency(quint64 frequencyHz)
{
    struct BandRange { quint64 low; quint64 high; const char *name; };
    static constexpr BandRange bands[] = {
        {135700,137800,"2200 m"},{472000,479000,"630 m"},
        {1800000,2000000,"160 m"},{3500000,4000000,"80 m"},
        {5250000,5450000,"60 m"},{7000000,7300000,"40 m"},
        {10100000,10150000,"30 m"},{14000000,14350000,"20 m"},
        {18068000,18168000,"17 m"},{21000000,21450000,"15 m"},
        {24890000,24990000,"12 m"},{28000000,29700000,"10 m"},
        {50000000,54000000,"6 m"},{70000000,70500000,"4 m"}
    };
    for (const BandRange &band : bands) {
        if (frequencyHz >= band.low && frequencyHz <= band.high)
            return QString::fromLatin1(band.name);
    }
    return QStringLiteral("Fuera de banda");
}
QString RadioController::modeName(quint8 modeCode)
{
    switch (modeCode) {
    case 0x00: return QStringLiteral("LSB");
    case 0x01: return QStringLiteral("USB");
    case 0x02: return QStringLiteral("AM");
    case 0x03: return QStringLiteral("CW");
    case 0x04: return QStringLiteral("RTTY");
    case 0x05: return QStringLiteral("FM");
    case 0x07: return QStringLiteral("CW-R");
    case 0x08: return QStringLiteral("RTTY-R");
    default: return QStringLiteral("DESCONOCIDO");
    }
}
QString RadioController::filterName(quint8 filterCode)
{
    switch (filterCode) {
    case 0x01: return QStringLiteral("FIL1");
    case 0x02: return QStringLiteral("FIL2");
    case 0x03: return QStringLiteral("FIL3");
    default: return QStringLiteral("—");
    }
}
