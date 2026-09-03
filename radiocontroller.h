#pragma once

#include <QObject>
#include <QQueue>
#include <QSerialPort>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class RadioController final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool transmitting READ transmitting NOTIFY transmittingChanged)
    Q_PROPERTY(bool pttOwned READ pttOwned NOTIFY transmittingChanged)
    Q_PROPERTY(int txSafetyTimeoutSeconds READ txSafetyTimeoutSeconds
               WRITE setTxSafetyTimeoutSeconds NOTIFY txSafetySettingsChanged)
    Q_PROPERTY(bool dataMode READ dataMode NOTIFY dataModeChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool memoryReadActive READ memoryReadActive
               NOTIFY memoryReadActiveChanged)

    Q_PROPERTY(bool splitEnabled READ splitEnabled NOTIFY splitChanged)
    Q_PROPERTY(bool ritEnabled READ ritEnabled NOTIFY ritChanged)
    Q_PROPERTY(bool deltaTxEnabled READ deltaTxEnabled NOTIFY deltaTxChanged)
    Q_PROPERTY(bool attenuatorEnabled READ attenuatorEnabled NOTIFY attenuatorChanged)
    Q_PROPERTY(bool tunerEnabled READ tunerEnabled NOTIFY tunerChanged)

    Q_PROPERTY(bool noiseBlankerEnabled READ noiseBlankerEnabled
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(bool noiseReductionEnabled READ noiseReductionEnabled
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(bool autoNotchEnabled READ autoNotchEnabled
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(bool manualNotchEnabled READ manualNotchEnabled
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(bool ipPlusEnabled READ ipPlusEnabled
               NOTIFY advancedReceiveChanged)

    Q_PROPERTY(bool squelchOpen READ squelchOpen
               NOTIFY squelchStateChanged)
    Q_PROPERTY(bool basicSquelchOpen READ basicSquelchOpen
               NOTIFY squelchStateChanged)
    Q_PROPERTY(QString squelchStateText READ squelchStateText
               NOTIFY squelchStateChanged)

    Q_PROPERTY(int radioTuningStepCode READ radioTuningStepCode
               NOTIFY radioTuningStepChanged)
    Q_PROPERTY(QString radioTuningStepText READ radioTuningStepText
               NOTIFY radioTuningStepChanged)

    Q_PROPERTY(bool xfcEnabled READ xfcEnabled NOTIFY xfcChanged)
    Q_PROPERTY(bool civOutputEnabled READ civOutputEnabled
               NOTIFY civSettingsChanged)

    Q_PROPERTY(qulonglong txFrequencyHz READ txFrequencyHz
               NOTIFY txFrequencyChanged)
    Q_PROPERTY(QString txFrequencyText READ txFrequencyText
               NOTIFY txFrequencyChanged)

    Q_PROPERTY(int txBandCount READ txBandCount
               NOTIFY capabilitiesChanged)
    Q_PROPERTY(QVariantList txBandEdges READ txBandEdges
               NOTIFY capabilitiesChanged)
    Q_PROPERTY(QString txBandEdgesText READ txBandEdgesText
               NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool txBandEdgesLoaded READ txBandEdgesLoaded
               NOTIFY capabilitiesChanged)

    Q_PROPERTY(int microphoneGain READ microphoneGain
               NOTIFY txAudioChanged)
    Q_PROPERTY(int speechCompressorLevel READ speechCompressorLevel
               NOTIFY txAudioChanged)
    Q_PROPERTY(int monitorLevel READ monitorLevel
               NOTIFY txAudioChanged)
    Q_PROPERTY(int voxGain READ voxGain
               NOTIFY txAudioChanged)
    Q_PROPERTY(int antiVoxGain READ antiVoxGain
               NOTIFY txAudioChanged)

    Q_PROPERTY(bool speechCompressorEnabled READ speechCompressorEnabled
               NOTIFY txAudioChanged)
    Q_PROPERTY(bool monitorEnabled READ monitorEnabled
               NOTIFY txAudioChanged)
    Q_PROPERTY(bool voxEnabled READ voxEnabled
               NOTIFY txAudioChanged)
    Q_PROPERTY(bool txInhibitEnabled READ txInhibitEnabled
               NOTIFY txAudioChanged)

    Q_PROPERTY(int txFilterWidth READ txFilterWidth
               NOTIFY txAudioChanged)
    Q_PROPERTY(QString txFilterWidthText READ txFilterWidthText
               NOTIFY txAudioChanged)

    Q_PROPERTY(bool cwModeActive READ cwModeActive NOTIFY modeChanged)
    Q_PROPERTY(int cwApfPeakOffsetHz READ cwApfPeakOffsetHz
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int cwPitchHz READ cwPitchHz
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int cwKeySpeedWpm READ cwKeySpeedWpm
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int cwBreakInDelayTenths READ cwBreakInDelayTenths
               NOTIFY cwSettingsChanged)

    Q_PROPERTY(int apfMode READ apfMode NOTIFY cwSettingsChanged)
    Q_PROPERTY(QString apfModeText READ apfModeText
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int breakInMode READ breakInMode
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(QString breakInModeText READ breakInModeText
               NOTIFY cwSettingsChanged)

    Q_PROPERTY(int sideToneLevel READ sideToneLevel
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(bool sideToneLimitEnabled READ sideToneLimitEnabled
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int keyerRepeatSeconds READ keyerRepeatSeconds
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int dotDashRatioTenths READ dotDashRatioTenths
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int riseTimeMs READ riseTimeMs
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(bool paddleReversed READ paddleReversed
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(int keyType READ keyType NOTIFY cwSettingsChanged)
    Q_PROPERTY(QString keyTypeText READ keyTypeText
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(bool micUpDownKeyerEnabled READ micUpDownKeyerEnabled
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(bool cwDecodeDisplayEnabled READ cwDecodeDisplayEnabled
               NOTIFY cwSettingsChanged)
    Q_PROPERTY(QVariantList keyerMemories READ keyerMemories
               NOTIFY keyerMemoriesChanged)

    Q_PROPERTY(bool fmModeActive READ fmModeActive NOTIFY modeChanged)
    Q_PROPERTY(bool rttyModeActive READ rttyModeActive NOTIFY modeChanged)

    Q_PROPERTY(bool repeaterToneEnabled READ repeaterToneEnabled
               NOTIFY toneRttyChanged)
    Q_PROPERTY(bool toneSquelchEnabled READ toneSquelchEnabled
               NOTIFY toneRttyChanged)
    Q_PROPERTY(int repeaterToneTenthsHz READ repeaterToneTenthsHz
               NOTIFY toneRttyChanged)
    Q_PROPERTY(int toneSquelchTenthsHz READ toneSquelchTenthsHz
               NOTIFY toneRttyChanged)
    Q_PROPERTY(QString repeaterToneText READ repeaterToneText
               NOTIFY toneRttyChanged)
    Q_PROPERTY(QString toneSquelchText READ toneSquelchText
               NOTIFY toneRttyChanged)

    Q_PROPERTY(bool twinPeakEnabled READ twinPeakEnabled
               NOTIFY toneRttyChanged)
    Q_PROPERTY(bool twinPeakAvailable READ twinPeakAvailable
               NOTIFY toneRttyChanged)
    Q_PROPERTY(int rttyMarkFrequencyCode READ rttyMarkFrequencyCode
               NOTIFY toneRttyChanged)
    Q_PROPERTY(QString rttyMarkFrequencyText READ rttyMarkFrequencyText
               NOTIFY toneRttyChanged)
    Q_PROPERTY(int rttyShiftWidthCode READ rttyShiftWidthCode
               NOTIFY toneRttyChanged)
    Q_PROPERTY(QString rttyShiftWidthText READ rttyShiftWidthText
               NOTIFY toneRttyChanged)
    Q_PROPERTY(bool rttyKeyingReverse READ rttyKeyingReverse
               NOTIFY toneRttyChanged)

    Q_PROPERTY(bool memoryModeActive READ memoryModeActive
               NOTIFY memoryModeChanged)
    Q_PROPERTY(int selectedMemoryChannel READ selectedMemoryChannel
               NOTIFY memoryModeChanged)
    Q_PROPERTY(QString selectedMemoryChannelText
               READ selectedMemoryChannelText
               NOTIFY memoryModeChanged)
    Q_PROPERTY(bool memoryReturnAvailable
               READ memoryReturnAvailable
               NOTIFY memoryModeChanged)
    Q_PROPERTY(QString memoryReturnVfoText
               READ memoryReturnVfoText
               NOTIFY memoryModeChanged)
    Q_PROPERTY(QVariantList memoryRows READ memoryRows
               NOTIFY memoriesChanged)
    Q_PROPERTY(int memoriesRevision READ memoriesRevision
               NOTIFY memoriesChanged)

    Q_PROPERTY(bool scanActive READ scanActive
               NOTIFY scanChanged)
    Q_PROPERTY(QString scanTypeText READ scanTypeText
               NOTIFY scanChanged)
    Q_PROPERTY(bool scanSpeedFast READ scanSpeedFast
               NOTIFY scanChanged)
    Q_PROPERTY(bool scanResumeEnabled READ scanResumeEnabled
               NOTIFY scanChanged)
    Q_PROPERTY(int scanSelectGroup READ scanSelectGroup
               NOTIFY scanChanged)
    Q_PROPERTY(int deltaScanSpanCode READ deltaScanSpanCode
               NOTIFY scanChanged)
    Q_PROPERTY(QString deltaScanSpanText READ deltaScanSpanText
               NOTIFY scanChanged)
    Q_PROPERTY(QVariantList bandStackingRows READ bandStackingRows
               NOTIFY bandStackingChanged)

    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString actionStatus READ actionStatus NOTIFY actionStatusChanged)
    Q_PROPERTY(QString portName READ portName NOTIFY portNameChanged)

    Q_PROPERTY(QStringList serialPortChoices READ serialPortChoices
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString configuredPort READ configuredPort
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int configuredBaudRate READ configuredBaudRate
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int civRadioAddress READ civRadioAddress
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int civControllerAddress READ civControllerAddress
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoConnectEnabled READ autoConnectEnabled
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoReconnectEnabled READ autoReconnectEnabled
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int pollIntervalMs READ pollIntervalMs
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int responseTimeoutMs READ responseTimeoutMs
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString usbInterfacesText READ usbInterfacesText
               NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString connectionSettingsSummary
               READ connectionSettingsSummary
               NOTIFY connectionSettingsChanged)

    Q_PROPERTY(bool scopeRunning READ scopeRunning
               NOTIFY scopeStateChanged)
    Q_PROPERTY(QVariantList scopeSpectrumData READ scopeSpectrumData
               NOTIFY scopeWaveformChanged)
    Q_PROPERTY(int scopeFrameCounter READ scopeFrameCounter
               NOTIFY scopeWaveformChanged)
    Q_PROPERTY(int scopeMode READ scopeMode
               NOTIFY scopeStateChanged)
    Q_PROPERTY(QString scopeModeText READ scopeModeText
               NOTIFY scopeStateChanged)
    Q_PROPERTY(qulonglong scopeCenterFrequencyHz
               READ scopeCenterFrequencyHz
               NOTIFY scopeStateChanged)
    Q_PROPERTY(qulonglong scopeLowerFrequencyHz
               READ scopeLowerFrequencyHz
               NOTIFY scopeStateChanged)
    Q_PROPERTY(qulonglong scopeHigherFrequencyHz
               READ scopeHigherFrequencyHz
               NOTIFY scopeStateChanged)
    Q_PROPERTY(qulonglong scopeSpanHz READ scopeSpanHz
               NOTIFY scopeStateChanged)
    Q_PROPERTY(QString scopeSpanText READ scopeSpanText
               NOTIFY scopeStateChanged)
    Q_PROPERTY(bool scopeOutOfRange READ scopeOutOfRange
               NOTIFY scopeStateChanged)
    Q_PROPERTY(bool scopeHold READ scopeHold
               NOTIFY scopeStateChanged)
    Q_PROPERTY(int scopeSweepSpeed READ scopeSweepSpeed
               NOTIFY scopeStateChanged)
    Q_PROPERTY(QString scopeSweepSpeedText READ scopeSweepSpeedText
               NOTIFY scopeStateChanged)
    Q_PROPERTY(bool scopeVbwWide READ scopeVbwWide
               NOTIFY scopeStateChanged)

    // Estado del VFO activo, conservado por compatibilidad con las versiones
    // anteriores de la interfaz.
    Q_PROPERTY(qulonglong frequencyHz READ frequencyHz NOTIFY frequencyChanged)
    Q_PROPERTY(QString frequencyText READ frequencyText NOTIFY frequencyChanged)
    Q_PROPERTY(QString frequencyMhzText READ frequencyMhzText NOTIFY frequencyChanged)
    Q_PROPERTY(QString bandText READ bandText NOTIFY frequencyChanged)

    Q_PROPERTY(QString modeText READ modeText NOTIFY modeChanged)
    Q_PROPERTY(QString filterText READ filterText NOTIFY filterChanged)
    Q_PROPERTY(QString dataText READ dataText NOTIFY dataModeChanged)
    Q_PROPERTY(QString txRxText READ txRxText NOTIFY transmittingChanged)
    Q_PROPERTY(QString vfoText READ vfoText NOTIFY vfoChanged)

    // Estado completo e independiente de VFO A y VFO B.
    Q_PROPERTY(int selectedVfo READ selectedVfo NOTIFY vfoChanged)
    Q_PROPERTY(bool vfoASelected READ vfoASelected NOTIFY vfoChanged)
    Q_PROPERTY(bool vfoBSelected READ vfoBSelected NOTIFY vfoChanged)

    Q_PROPERTY(qulonglong vfoAFrequencyHz READ vfoAFrequencyHz
               NOTIFY vfoAStateChanged)
    Q_PROPERTY(QString vfoAFrequencyText READ vfoAFrequencyText
               NOTIFY vfoAStateChanged)
    Q_PROPERTY(QString vfoABandText READ vfoABandText
               NOTIFY vfoAStateChanged)
    Q_PROPERTY(QString vfoAModeText READ vfoAModeText
               NOTIFY vfoAStateChanged)
    Q_PROPERTY(QString vfoADataText READ vfoADataText
               NOTIFY vfoAStateChanged)
    Q_PROPERTY(QString vfoAFilterText READ vfoAFilterText
               NOTIFY vfoAStateChanged)

    Q_PROPERTY(qulonglong vfoBFrequencyHz READ vfoBFrequencyHz
               NOTIFY vfoBStateChanged)
    Q_PROPERTY(QString vfoBFrequencyText READ vfoBFrequencyText
               NOTIFY vfoBStateChanged)
    Q_PROPERTY(QString vfoBBandText READ vfoBBandText
               NOTIFY vfoBStateChanged)
    Q_PROPERTY(QString vfoBModeText READ vfoBModeText
               NOTIFY vfoBStateChanged)
    Q_PROPERTY(QString vfoBDataText READ vfoBDataText
               NOTIFY vfoBStateChanged)
    Q_PROPERTY(QString vfoBFilterText READ vfoBFilterText
               NOTIFY vfoBStateChanged)

    Q_PROPERTY(QString splitText READ splitText NOTIFY splitChanged)
    Q_PROPERTY(QString ritText READ ritText NOTIFY ritChanged)
    Q_PROPERTY(QString deltaTxText READ deltaTxText NOTIFY deltaTxChanged)
    Q_PROPERTY(QString preampText READ preampText NOTIFY preampChanged)
    Q_PROPERTY(QString attenuatorText READ attenuatorText NOTIFY attenuatorChanged)
    Q_PROPERTY(QString tunerText READ tunerText NOTIFY tunerChanged)
    Q_PROPERTY(QString agcText READ agcText NOTIFY agcChanged)

    Q_PROPERTY(int ritOffsetHz READ ritOffsetHz NOTIFY ritChanged)
    Q_PROPERTY(int afGain READ afGain NOTIFY afGainChanged)
    Q_PROPERTY(int rfGain READ rfGain NOTIFY rfGainChanged)
    Q_PROPERTY(int squelch READ squelch NOTIFY squelchChanged)
    Q_PROPERTY(int rfPower READ rfPower NOTIFY rfPowerChanged)
    Q_PROPERTY(int preamp READ preamp NOTIFY preampChanged)
    Q_PROPERTY(int agc READ agc NOTIFY agcChanged)

    Q_PROPERTY(int noiseBlankerLevel READ noiseBlankerLevel
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(int noiseReductionLevel READ noiseReductionLevel
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(int pbt1 READ pbt1 NOTIFY advancedReceiveChanged)
    Q_PROPERTY(int pbt2 READ pbt2 NOTIFY advancedReceiveChanged)
    Q_PROPERTY(int manualNotchPosition READ manualNotchPosition
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(int manualNotchWidth READ manualNotchWidth
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(QString manualNotchWidthText READ manualNotchWidthText
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(int filterShape READ filterShape
               NOTIFY advancedReceiveChanged)
    Q_PROPERTY(QString filterShapeText READ filterShapeText
               NOTIFY advancedReceiveChanged)

    Q_PROPERTY(int sMeterPercent READ sMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString sMeterText READ sMeterText NOTIFY metersChanged)
    Q_PROPERTY(int powerMeterPercent READ powerMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString powerMeterText READ powerMeterText NOTIFY metersChanged)
    Q_PROPERTY(int swrMeterPercent READ swrMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString swrMeterText READ swrMeterText NOTIFY metersChanged)
    Q_PROPERTY(int alcMeterPercent READ alcMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString alcMeterText READ alcMeterText NOTIFY metersChanged)
    Q_PROPERTY(int compMeterPercent READ compMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString compMeterText READ compMeterText NOTIFY metersChanged)
    Q_PROPERTY(int voltageMeterPercent READ voltageMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString voltageMeterText READ voltageMeterText NOTIFY metersChanged)
    Q_PROPERTY(int currentMeterPercent READ currentMeterPercent NOTIFY metersChanged)
    Q_PROPERTY(QString currentMeterText READ currentMeterText NOTIFY metersChanged)
    Q_PROPERTY(bool overflow READ overflow NOTIFY metersChanged)

    Q_PROPERTY(QString lastTx READ lastTx NOTIFY trafficChanged)
    Q_PROPERTY(QString lastRx READ lastRx NOTIFY trafficChanged)
    Q_PROPERTY(QString txTrafficHistory READ txTrafficHistory
               NOTIFY trafficChanged)
    Q_PROPERTY(QString rxTrafficHistory READ rxTrafficHistory
               NOTIFY trafficChanged)

public:
    explicit RadioController(QObject *parent = nullptr);
    ~RadioController() override;

    [[nodiscard]] bool connected() const;
    [[nodiscard]] bool transmitting() const;
    [[nodiscard]] bool pttOwned() const;
    [[nodiscard]] int txSafetyTimeoutSeconds() const;
    void setTxSafetyTimeoutSeconds(int seconds);
    [[nodiscard]] bool dataMode() const;
    [[nodiscard]] bool busy() const;
    [[nodiscard]] bool memoryReadActive() const;
    [[nodiscard]] bool splitEnabled() const;
    [[nodiscard]] bool ritEnabled() const;
    [[nodiscard]] bool deltaTxEnabled() const;
    [[nodiscard]] bool attenuatorEnabled() const;
    [[nodiscard]] bool tunerEnabled() const;
    [[nodiscard]] bool noiseBlankerEnabled() const;
    [[nodiscard]] bool noiseReductionEnabled() const;
    [[nodiscard]] bool autoNotchEnabled() const;
    [[nodiscard]] bool manualNotchEnabled() const;
    [[nodiscard]] bool ipPlusEnabled() const;

    [[nodiscard]] bool squelchOpen() const;
    [[nodiscard]] bool basicSquelchOpen() const;
    [[nodiscard]] QString squelchStateText() const;

    [[nodiscard]] int radioTuningStepCode() const;
    [[nodiscard]] QString radioTuningStepText() const;

    [[nodiscard]] bool xfcEnabled() const;
    [[nodiscard]] bool civOutputEnabled() const;

    [[nodiscard]] qulonglong txFrequencyHz() const;
    [[nodiscard]] QString txFrequencyText() const;

    [[nodiscard]] int txBandCount() const;
    [[nodiscard]] QVariantList txBandEdges() const;
    [[nodiscard]] QString txBandEdgesText() const;
    [[nodiscard]] bool txBandEdgesLoaded() const;

    [[nodiscard]] int microphoneGain() const;
    [[nodiscard]] int speechCompressorLevel() const;
    [[nodiscard]] int monitorLevel() const;
    [[nodiscard]] int voxGain() const;
    [[nodiscard]] int antiVoxGain() const;

    [[nodiscard]] bool speechCompressorEnabled() const;
    [[nodiscard]] bool monitorEnabled() const;
    [[nodiscard]] bool voxEnabled() const;
    [[nodiscard]] bool txInhibitEnabled() const;

    [[nodiscard]] int txFilterWidth() const;
    [[nodiscard]] QString txFilterWidthText() const;

    [[nodiscard]] bool cwModeActive() const;
    [[nodiscard]] int cwApfPeakOffsetHz() const;
    [[nodiscard]] int cwPitchHz() const;
    [[nodiscard]] int cwKeySpeedWpm() const;
    [[nodiscard]] int cwBreakInDelayTenths() const;
    [[nodiscard]] int apfMode() const;
    [[nodiscard]] QString apfModeText() const;
    [[nodiscard]] int breakInMode() const;
    [[nodiscard]] QString breakInModeText() const;

    [[nodiscard]] int sideToneLevel() const;
    [[nodiscard]] bool sideToneLimitEnabled() const;
    [[nodiscard]] int keyerRepeatSeconds() const;
    [[nodiscard]] int dotDashRatioTenths() const;
    [[nodiscard]] int riseTimeMs() const;
    [[nodiscard]] bool paddleReversed() const;
    [[nodiscard]] int keyType() const;
    [[nodiscard]] QString keyTypeText() const;
    [[nodiscard]] bool micUpDownKeyerEnabled() const;
    [[nodiscard]] bool cwDecodeDisplayEnabled() const;
    [[nodiscard]] QVariantList keyerMemories() const;

    [[nodiscard]] bool fmModeActive() const;
    [[nodiscard]] bool rttyModeActive() const;
    [[nodiscard]] bool repeaterToneEnabled() const;
    [[nodiscard]] bool toneSquelchEnabled() const;
    [[nodiscard]] int repeaterToneTenthsHz() const;
    [[nodiscard]] int toneSquelchTenthsHz() const;
    [[nodiscard]] QString repeaterToneText() const;
    [[nodiscard]] QString toneSquelchText() const;

    [[nodiscard]] bool twinPeakEnabled() const;
    [[nodiscard]] bool twinPeakAvailable() const;
    [[nodiscard]] int rttyMarkFrequencyCode() const;
    [[nodiscard]] QString rttyMarkFrequencyText() const;
    [[nodiscard]] int rttyShiftWidthCode() const;
    [[nodiscard]] QString rttyShiftWidthText() const;
    [[nodiscard]] bool rttyKeyingReverse() const;

    [[nodiscard]] bool memoryModeActive() const;
    [[nodiscard]] int selectedMemoryChannel() const;
    [[nodiscard]] QString selectedMemoryChannelText() const;
    [[nodiscard]] bool memoryReturnAvailable() const;
    [[nodiscard]] QString memoryReturnVfoText() const;
    [[nodiscard]] QVariantList memoryRows() const;
    [[nodiscard]] int memoriesRevision() const;

    [[nodiscard]] bool scanActive() const;
    [[nodiscard]] QString scanTypeText() const;
    [[nodiscard]] bool scanSpeedFast() const;
    [[nodiscard]] bool scanResumeEnabled() const;
    [[nodiscard]] int scanSelectGroup() const;
    [[nodiscard]] int deltaScanSpanCode() const;
    [[nodiscard]] QString deltaScanSpanText() const;
    [[nodiscard]] QVariantList bandStackingRows() const;

    [[nodiscard]] QString status() const;
    [[nodiscard]] QString actionStatus() const;
    [[nodiscard]] QString portName() const;

    [[nodiscard]] QStringList serialPortChoices() const;
    [[nodiscard]] QString configuredPort() const;
    [[nodiscard]] int configuredBaudRate() const;
    [[nodiscard]] int civRadioAddress() const;
    [[nodiscard]] int civControllerAddress() const;
    [[nodiscard]] bool autoConnectEnabled() const;
    [[nodiscard]] bool autoReconnectEnabled() const;
    Q_INVOKABLE void setAutoConnectPreference(bool enabled);
    Q_INVOKABLE void setAutoReconnectPreference(bool enabled);
    [[nodiscard]] int pollIntervalMs() const;
    [[nodiscard]] int responseTimeoutMs() const;
    [[nodiscard]] QString usbInterfacesText() const;
    [[nodiscard]] QString connectionSettingsSummary() const;

    [[nodiscard]] bool scopeRunning() const;
    [[nodiscard]] QVariantList scopeSpectrumData() const;
    [[nodiscard]] int scopeFrameCounter() const;
    [[nodiscard]] int scopeMode() const;
    [[nodiscard]] QString scopeModeText() const;
    [[nodiscard]] qulonglong scopeCenterFrequencyHz() const;
    [[nodiscard]] qulonglong scopeLowerFrequencyHz() const;
    [[nodiscard]] qulonglong scopeHigherFrequencyHz() const;
    [[nodiscard]] qulonglong scopeSpanHz() const;
    [[nodiscard]] QString scopeSpanText() const;
    [[nodiscard]] bool scopeOutOfRange() const;
    [[nodiscard]] bool scopeHold() const;
    [[nodiscard]] int scopeSweepSpeed() const;
    [[nodiscard]] QString scopeSweepSpeedText() const;
    [[nodiscard]] bool scopeVbwWide() const;

    [[nodiscard]] qulonglong frequencyHz() const;
    [[nodiscard]] QString frequencyText() const;
    [[nodiscard]] QString frequencyMhzText() const;
    [[nodiscard]] QString bandText() const;

    [[nodiscard]] QString modeText() const;
    [[nodiscard]] QString filterText() const;
    [[nodiscard]] QString dataText() const;
    [[nodiscard]] QString txRxText() const;
    [[nodiscard]] QString vfoText() const;

    [[nodiscard]] int selectedVfo() const;
    [[nodiscard]] bool vfoASelected() const;
    [[nodiscard]] bool vfoBSelected() const;

    [[nodiscard]] qulonglong vfoAFrequencyHz() const;
    [[nodiscard]] QString vfoAFrequencyText() const;
    [[nodiscard]] QString vfoABandText() const;
    [[nodiscard]] QString vfoAModeText() const;
    [[nodiscard]] QString vfoADataText() const;
    [[nodiscard]] QString vfoAFilterText() const;

    [[nodiscard]] qulonglong vfoBFrequencyHz() const;
    [[nodiscard]] QString vfoBFrequencyText() const;
    [[nodiscard]] QString vfoBBandText() const;
    [[nodiscard]] QString vfoBModeText() const;
    [[nodiscard]] QString vfoBDataText() const;
    [[nodiscard]] QString vfoBFilterText() const;

    [[nodiscard]] QString splitText() const;
    [[nodiscard]] QString ritText() const;
    [[nodiscard]] QString deltaTxText() const;
    [[nodiscard]] QString preampText() const;
    [[nodiscard]] QString attenuatorText() const;
    [[nodiscard]] QString tunerText() const;
    [[nodiscard]] QString agcText() const;

    [[nodiscard]] int ritOffsetHz() const;
    [[nodiscard]] int afGain() const;
    [[nodiscard]] int rfGain() const;
    [[nodiscard]] int squelch() const;
    [[nodiscard]] int rfPower() const;
    [[nodiscard]] int preamp() const;
    [[nodiscard]] int agc() const;

    [[nodiscard]] int noiseBlankerLevel() const;
    [[nodiscard]] int noiseReductionLevel() const;
    [[nodiscard]] int pbt1() const;
    [[nodiscard]] int pbt2() const;
    [[nodiscard]] int manualNotchPosition() const;
    [[nodiscard]] int manualNotchWidth() const;
    [[nodiscard]] QString manualNotchWidthText() const;
    [[nodiscard]] int filterShape() const;
    [[nodiscard]] QString filterShapeText() const;

    [[nodiscard]] int sMeterPercent() const;
    [[nodiscard]] QString sMeterText() const;
    [[nodiscard]] int powerMeterPercent() const;
    [[nodiscard]] QString powerMeterText() const;
    [[nodiscard]] int swrMeterPercent() const;
    [[nodiscard]] QString swrMeterText() const;
    [[nodiscard]] int alcMeterPercent() const;
    [[nodiscard]] QString alcMeterText() const;
    [[nodiscard]] int compMeterPercent() const;
    [[nodiscard]] QString compMeterText() const;
    [[nodiscard]] int voltageMeterPercent() const;
    [[nodiscard]] QString voltageMeterText() const;
    [[nodiscard]] int currentMeterPercent() const;
    [[nodiscard]] QString currentMeterText() const;
    [[nodiscard]] bool overflow() const;

    [[nodiscard]] QString lastTx() const;
    [[nodiscard]] QString lastRx() const;
    [[nodiscard]] QString txTrafficHistory() const;
    [[nodiscard]] QString rxTrafficHistory() const;

    Q_INVOKABLE void connectRadio();
    Q_INVOKABLE void disconnectRadio();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void reconnectRadio();
    Q_INVOKABLE void refreshConnectionDevices();
    Q_INVOKABLE bool applyConnectionSettings(
        const QVariantMap &settings
    );
    Q_INVOKABLE void restoreRecommendedConnectionSettings();
    Q_INVOKABLE void clearTrafficHistory();
    Q_INVOKABLE void copyTextToClipboard(
        const QString &text,
        const QString &description);
    Q_INVOKABLE void setTransmit(bool enabled);

    Q_INVOKABLE void startSpectrumScope();
    Q_INVOKABLE void stopSpectrumScope();
    Q_INVOKABLE void refreshSpectrumScopeSettings();
    Q_INVOKABLE void setSpectrumScopeMode(int mode);
    Q_INVOKABLE void setSpectrumScopeSpan(qulonglong spanHz);
    Q_INVOKABLE void setSpectrumScopeHold(bool enabled);
    Q_INVOKABLE void setSpectrumScopeSweepSpeed(int speed);
    Q_INVOKABLE void setSpectrumScopeVbwWide(bool wide);

    Q_INVOKABLE void setFrequency(const QString &text);
    void setExternalFrequency(qulonglong frequencyHz);
    Q_INVOKABLE void adjustFrequency(int deltaHz);

    Q_INVOKABLE void setVfoFrequency(int vfoNumber,
                                     const QString &text);
    Q_INVOKABLE void adjustVfoFrequency(int vfoNumber,
                                        int deltaHz);

    Q_INVOKABLE void setOperatingMode(const QString &modeName);
    Q_INVOKABLE void setOperatingModeState(const QString &modeName,
                                           bool dataEnabled,
                                           int filterNumber);
    Q_INVOKABLE void setDataEnabled(bool enabled);
    Q_INVOKABLE void setFilter(int filterNumber);

    Q_INVOKABLE void selectVfoA();
    Q_INVOKABLE void selectVfoB();
    Q_INVOKABLE void equalizeVfos();
    Q_INVOKABLE void exchangeVfos();
    Q_INVOKABLE void setSplitEnabled(bool enabled);

    Q_INVOKABLE void setRitOffset(int offsetHz);
    Q_INVOKABLE void setRitEnabled(bool enabled);
    Q_INVOKABLE void setDeltaTxEnabled(bool enabled);

    Q_INVOKABLE void setAfGain(int percent);
    Q_INVOKABLE void setRfGain(int percent);
    Q_INVOKABLE void setSquelch(int percent);
    Q_INVOKABLE void setRfPower(int percent);
    Q_INVOKABLE void setPreamp(int value);
    Q_INVOKABLE void setAttenuatorEnabled(bool enabled);
    Q_INVOKABLE void setAgc(int value);
    Q_INVOKABLE void setTunerEnabled(bool enabled);
    Q_INVOKABLE void startTuner();

    Q_INVOKABLE void setNoiseBlankerEnabled(bool enabled);
    Q_INVOKABLE void setNoiseBlankerLevel(int percent);
    Q_INVOKABLE void setNoiseReductionEnabled(bool enabled);
    Q_INVOKABLE void setNoiseReductionLevel(int percent);
    Q_INVOKABLE void setAutoNotchEnabled(bool enabled);
    Q_INVOKABLE void setManualNotchEnabled(bool enabled);
    Q_INVOKABLE void setManualNotchPosition(int percent);
    Q_INVOKABLE void setManualNotchWidth(int width);
    Q_INVOKABLE void setPbt1(int percent);
    Q_INVOKABLE void setPbt2(int percent);
    Q_INVOKABLE void clearTwinPbt();
    Q_INVOKABLE void setIpPlusEnabled(bool enabled);
    Q_INVOKABLE void setFilterShape(int shape);

    Q_INVOKABLE void setRadioTuningStep(int code);
    Q_INVOKABLE void setXfcEnabled(bool enabled);
    Q_INVOKABLE void setCivOutputEnabled(bool enabled);
    Q_INVOKABLE void refreshCapabilities();

    Q_INVOKABLE void setMicrophoneGain(int percent);
    Q_INVOKABLE void setSpeechCompressorLevel(int level);
    Q_INVOKABLE void setMonitorLevel(int percent);
    Q_INVOKABLE void setVoxGain(int percent);
    Q_INVOKABLE void setAntiVoxGain(int percent);

    Q_INVOKABLE void setSpeechCompressorEnabled(bool enabled);
    Q_INVOKABLE void setMonitorEnabled(bool enabled);
    Q_INVOKABLE void setVoxEnabled(bool enabled);
    Q_INVOKABLE void setTxFilterWidth(int width);
    Q_INVOKABLE void setTxInhibitEnabled(bool enabled);
    Q_INVOKABLE void refreshTxAudioSettings();

    Q_INVOKABLE void setCwApfPeakOffsetHz(int offsetHz);
    Q_INVOKABLE void setCwPitchHz(int pitchHz);
    Q_INVOKABLE void setCwKeySpeedWpm(int speedWpm);
    Q_INVOKABLE void setCwBreakInDelayTenths(int tenths);
    Q_INVOKABLE void setApfMode(int mode);
    Q_INVOKABLE void setBreakInMode(int mode);

    Q_INVOKABLE void setSideToneLevel(int percent);
    Q_INVOKABLE void setSideToneLimitEnabled(bool enabled);
    Q_INVOKABLE void setKeyerRepeatSeconds(int seconds);
    Q_INVOKABLE void setDotDashRatioTenths(int tenths);
    Q_INVOKABLE void setRiseTimeMs(int milliseconds);
    Q_INVOKABLE void setPaddleReversed(bool reversed);
    Q_INVOKABLE void setKeyType(int type);
    Q_INVOKABLE void setMicUpDownKeyerEnabled(bool enabled);
    Q_INVOKABLE void setCwDecodeDisplayEnabled(bool enabled);

    Q_INVOKABLE void refreshCwSettings();
    Q_INVOKABLE void readKeyerMemory(int channel);
    Q_INVOKABLE void readAllKeyerMemories();
    Q_INVOKABLE void writeKeyerMemory(int channel,
                                      const QString &text);
    Q_INVOKABLE void sendCwMessage(const QString &text);
    Q_INVOKABLE void stopCwMessage();

    Q_INVOKABLE void setRepeaterToneEnabled(bool enabled);
    Q_INVOKABLE void setToneSquelchEnabled(bool enabled);
    Q_INVOKABLE void setRepeaterToneTenthsHz(int tenthsHz);
    Q_INVOKABLE void setToneSquelchTenthsHz(int tenthsHz);

    Q_INVOKABLE void setTwinPeakEnabled(bool enabled);
    Q_INVOKABLE void setRttyMarkFrequencyCode(int code);
    Q_INVOKABLE void setRttyShiftWidthCode(int code);
    Q_INVOKABLE void setRttyKeyingReverse(bool reversed);
    Q_INVOKABLE void refreshToneRttySettings();

    Q_INVOKABLE QVariantMap memoryRow(int channel) const;
    Q_INVOKABLE void readMemoryChannel(int channel);
    Q_INVOKABLE void readMemoryRange(int firstChannel, int count);
    Q_INVOKABLE void refreshMemoryScanSettings(int firstChannel);
    Q_INVOKABLE void selectMemoryChannel(int channel);
    Q_INVOKABLE void toggleMemoryChannel(int channel);
    Q_INVOKABLE void returnToPreviousVfo();
    Q_INVOKABLE void storeDisplayedToMemory(int channel);
    Q_INVOKABLE void copyMemoryToVfo(int channel);
    Q_INVOKABLE void clearMemoryChannel(int channel);
    Q_INVOKABLE void renameMemoryChannel(int channel,
                                         const QString &name);
    Q_INVOKABLE bool updateMemoryChannel(
        int channel,
        const QVariantMap &values
    );
    Q_INVOKABLE void setMemorySelectGroup(int channel, int group);

    Q_INVOKABLE void startContextScan();
    Q_INVOKABLE void startProgrammedScan(bool fine);
    Q_INVOKABLE void startMemoryScan();
    Q_INVOKABLE void startSelectMemoryScan();
    Q_INVOKABLE void startDeltaScan(bool fine);
    Q_INVOKABLE void stopScan();
    Q_INVOKABLE void setScanSpeedFast(bool fast);
    Q_INVOKABLE void setScanResumeEnabled(bool enabled);
    Q_INVOKABLE void setScanSelectGroup(int group);
    Q_INVOKABLE void setDeltaScanSpanCode(int code);
    Q_INVOKABLE void readBandStackingBand(int bandCode);
    Q_INVOKABLE void readAllBandStacking();
    Q_INVOKABLE void storeCurrentToBandStacking(int bandCode,
                                                int registerCode);

signals:
    void connectedChanged();
    void transmittingChanged();
    void dataModeChanged();
    void busyChanged();
    void statusChanged();
    void actionStatusChanged();
    void portNameChanged();
    void connectionSettingsChanged();
    void txSafetySettingsChanged();
    void scopeStateChanged();
    void scopeWaveformChanged();

    void frequencyChanged();
    void modeChanged();
    void filterChanged();

    void vfoChanged();
    void vfoAStateChanged();
    void vfoBStateChanged();

    void splitChanged();
    void ritChanged();
    void deltaTxChanged();
    void afGainChanged();
    void rfGainChanged();
    void squelchChanged();
    void rfPowerChanged();
    void preampChanged();
    void attenuatorChanged();
    void tunerChanged();
    void agcChanged();
    void advancedReceiveChanged();
    void metersChanged();
    void squelchStateChanged();
    void radioTuningStepChanged();
    void xfcChanged();
    void civSettingsChanged();
    void txFrequencyChanged();
    void capabilitiesChanged();
    void txAudioChanged();
    void cwSettingsChanged();
    void keyerMemoriesChanged();
    void toneRttyChanged();
    void memoryModeChanged();
    void memoriesChanged();
    void memoryReadActiveChanged();
    void scanChanged();
    void bandStackingChanged();
    void trafficChanged();

private slots:
    void pollNextValue();
    void onReadyRead();
    void onSerialError(QSerialPort::SerialPortError error);
    void onResponseTimeout();

private:
    enum class QueryKind {
        None = -1,
        Frequency = 0,
        Mode,
        DataMode,
        VfoSelectedFrequency,
        VfoUnselectedFrequency,
        VfoSelectedMode,
        VfoUnselectedMode,
        TxStatus,
        Split,
        RitOffset,
        RitEnabled,
        DeltaTxEnabled,
        AfGain,
        RfGain,
        Squelch,
        RfPower,

        MicrophoneGain,
        SpeechCompressorLevel,
        MonitorLevel,
        VoxGain,
        AntiVoxGain,
        SpeechCompressor,
        Monitor,
        Vox,
        TxFilterWidth,
        TxInhibit,

        Preamp,
        Attenuator,
        Tuner,
        Agc,
        TuningStep,
        Xfc,
        TxFrequency,
        CivOutput,
        TxBandCount,
        TxBandEdge,
        SquelchBasic,
        SquelchFull,

        NoiseBlanker,
        NoiseBlankerLevel,
        NoiseReduction,
        NoiseReductionLevel,
        AutoNotch,
        ManualNotch,
        ManualNotchPosition,
        ManualNotchWidth,
        Pbt1,
        Pbt2,
        IpPlus,
        FilterShape,

        CwApfPeak,
        CwPitch,
        CwKeySpeed,
        CwBreakInDelay,
        ApfMode,
        BreakInMode,

        Smeter,
        PowerMeter,
        SwrMeter,
        AlcMeter,
        CompMeter,
        VoltageMeter,
        CurrentMeter,
        Overflow,

        SideToneLevel,
        SideToneLimit,
        KeyerRepeatTime,
        DotDashRatio,
        RiseTime,
        PaddlePolarity,
        KeyType,
        MicUpDownKeyer,
        CwDecodeDisplay,
        KeyerMemory,

        RepeaterTone,
        ToneSquelch,
        RepeaterToneFrequency,
        ToneSquelchFrequency,
        TwinPeak,
        RttyMarkFrequency,
        RttyShiftWidth,
        RttyKeyingPolarity,

        MemoryContent,
        ScanSpeed,
        ScanResume,
        BandStacking,

        Count
    };

    enum class WriteKind {
        None,
        Frequency,
        Mode,
        DataMode,
        Filter,
        SelectVfo,
        EqualizeVfos,
        ExchangeVfos,
        Split,
        RitOffset,
        RitEnabled,
        DeltaTxEnabled,
        AfGain,
        RfGain,
        Squelch,
        RfPower,

        MicrophoneGain,
        SpeechCompressorLevel,
        MonitorLevel,
        VoxGain,
        AntiVoxGain,
        SpeechCompressor,
        Monitor,
        Vox,
        TxFilterWidth,
        TxInhibit,

        Preamp,
        Attenuator,
        Tuner,
        TunerStart,
        Agc,
        NoiseBlanker,
        NoiseBlankerLevel,
        NoiseReduction,
        NoiseReductionLevel,
        AutoNotch,
        ManualNotch,
        ManualNotchPosition,
        ManualNotchWidth,
        Pbt1,
        Pbt2,
        IpPlus,
        FilterShape,

        CwApfPeak,
        CwPitch,
        CwKeySpeed,
        CwBreakInDelay,
        ApfMode,
        BreakInMode,
        SideToneLevel,
        SideToneLimit,
        KeyerRepeatTime,
        DotDashRatio,
        RiseTime,
        PaddlePolarity,
        KeyType,
        MicUpDownKeyer,
        CwDecodeDisplay,
        KeyerMemory,
        CwMessage,
        CwStop,

        RepeaterTone,
        ToneSquelch,
        RepeaterToneFrequency,
        ToneSquelchFrequency,
        TwinPeak,
        RttyMarkFrequency,
        RttyShiftWidth,
        RttyKeyingPolarity,

        MemoryReceive,
        MemoryMode,
        MemorySelect,
        MemoryReturnReceive,
        MemoryReturnVfo,
        MemoryStore,
        MemoryCopyToVfo,
        MemoryClear,
        MemoryRename,
        MemoryEdit,
        MemorySelectGroup,
        ScanControl,
        ScanSpeed,
        ScanResume,
        ScanSelectGroup,
        DeltaScanSpan,
        BandStacking,

        TuningStep,
        Xfc,
        CivOutput,
        Transmit
    };

    struct VfoState {
        quint64 frequencyHz = 0;
        quint8 modeCode = 0xFF;
        quint8 filterCode = 0x01;
        bool dataMode = false;
        bool frequencyValid = false;
        bool modeValid = false;
    };

    struct MemoryVfoSnapshot {
        bool valid = false;
        int selectedVfo = 0;
        VfoState vfoState;

        bool splitEnabled = false;
        int ritOffsetHz = 0;
        bool ritEnabled = false;
        bool deltaTxEnabled = false;

        bool repeaterToneEnabled = false;
        bool toneSquelchEnabled = false;
        int repeaterToneTenthsHz = 885;
        int toneSquelchTenthsHz = 885;
    };

    struct TxBandEdge {
        int number = 0;
        quint64 lowerHz = 0;
        quint64 upperHz = 0;
    };

    struct BandStackingState {
        bool loaded = false;
        QByteArray raw;
        quint64 frequencyHz = 0;
        quint8 mode = 0xFF;
        quint8 filter = 0x01;
        bool dataMode = false;
        int toneType = 0;
        int repeaterToneTenthsHz = 885;
        int toneSquelchTenthsHz = 885;
    };

    struct BandStackingRequest {
        int bandCode = 0;
        int registerCode = 0;
    };

    struct MemoryState {
        bool loaded = false;
        bool blank = true;
        QByteArray raw;
        QString name;
        quint64 receiveFrequencyHz = 0;
        quint64 transmitFrequencyHz = 0;
        quint8 receiveMode = 0xFF;
        quint8 receiveFilter = 0x01;
        quint8 transmitMode = 0xFF;
        quint8 transmitFilter = 0x01;
        bool receiveDataMode = false;
        bool transmitDataMode = false;
        int toneType = 0;
        int transmitToneType = 0;
        int repeaterToneTenthsHz = 885;
        int toneSquelchTenthsHz = 885;
        bool split = false;
        int selectGroup = 0;
    };

    enum class MemorySequenceAction {
        None,
        GoTo,
        Store,
        CopyToVfo,
        Clear,
        SelectGroup
    };

    [[nodiscard]] QString findRadioPort() const;

    void sendQuery(QueryKind query);
    [[nodiscard]] bool sendCivPayload(const QByteArray &payload);

    void queueProtectedWrite(WriteKind kind,
                             const QByteArray &payload,
                             const QString &label,
                             QueryKind refreshQuery = QueryKind::None,
                             int desiredValue = 0);
    void startSafetyCheck();
    void sendQueuedWrite();
    void completeWrite(bool accepted);
    void cancelQueuedWrite(const QString &message);
    void setBusy(bool busy);
    void sendTransmitCommand(bool enabled);
    void forceReceive();

    void processReceiveBuffer();
    void processFrame(const QByteArray &frame);
    void acknowledgePendingQuery(const QByteArray &frame);

    void updateScopeWaveform(const QByteArray &frame);
    void updateScopeSetting(const QByteArray &frame);
    void resetScopeAssembly();
    void sendScopeQuery(quint8 subcommand);

    void decodeFrequency(const QByteArray &fiveBcdBytes);
    void updateMode(quint8 modeCode);
    void updateFilter(quint8 filterCode);
    void updateDataMode(quint8 dataCode);

    void updateVfoFrequency(int vfoNumber,
                            const QByteArray &fiveBcdBytes);
    void updateVfoModeState(int vfoNumber,
                            quint8 modeCode,
                            quint8 dataCode,
                            quint8 filterCode);
    void syncActiveStateFromSelectedVfo();
    void emitVfoStateSignal(int vfoNumber);

    [[nodiscard]] int actualVfoForSelector(quint8 selector) const;
    [[nodiscard]] quint8 selectorForActualVfo(int vfoNumber) const;

    void updateTxStatus(quint8 txCode);
    void updateSplit(quint8 value);
    void updateRitOffset(const QByteArray &data);
    void updateRitEnabled(quint8 value);
    void updateDeltaTxEnabled(quint8 value);
    void updateLevel(QueryKind kind, const QByteArray &data);
    void updatePreamp(quint8 value);
    void updateAttenuator(quint8 value);
    void updateTuner(quint8 value);
    void updateAgc(quint8 value);
    void updateAdvancedSwitch(QueryKind kind, quint8 value);
    void updateAdvancedLevel(QueryKind kind, const QByteArray &data);
    void updateMeter(QueryKind kind, const QByteArray &data);
    void updateOverflow(quint8 value);
    void updateSquelchState(QueryKind kind, quint8 value);
    void updateRadioTuningStep(quint8 value);
    void updateXfc(quint8 value);
    void updateCivOutput(quint8 value);
    void updateTxFrequency(const QByteArray &fiveBcdBytes);
    void updateTxBandCount(quint8 value);
    void updateTxBandEdge(const QByteArray &frame);
    void updateTxAudioLevel(QueryKind kind, const QByteArray &data);
    void updateTxAudioSwitch(QueryKind kind, quint8 value);
    void updateCwLevel(QueryKind kind, const QByteArray &data);
    void updateCwSwitch(QueryKind kind, quint8 value);
    void updateCwMenuSetting(quint8 item, const QByteArray &data);
    void updateKeyerMemory(int channel, const QByteArray &data);
    void updateToneRttySwitch(QueryKind kind, quint8 value);
    void updateToneFrequency(QueryKind kind, const QByteArray &data);
    void updateRttyMenuSetting(quint8 item, quint8 value);
    [[nodiscard]] QVariantMap buildMemoryRow(
        int channel) const;
    void markMemoriesChanged();
    void updateMemoryContent(const QByteArray &data);
    void updateScanSetting(quint8 item, quint8 value);
    void updateBandStacking(const QByteArray &data);
    void sendNextCwRefreshQuery();
    void beginInitialTxProbe();
    void startDefaultSpectrumScope();
    void deferMemoryRead(int firstChannel,
                         int count,
                         bool includeScanSettings);
    void runDeferredMemoryRead();
    void scheduleMemoryEditVerification(int delayMs = 900);
    bool queueMemoryEditWhenReady(
        int channel,
        const QVariantMap &values,
        int attempt = 0
    );
    void beginMemorySequence(MemorySequenceAction action,
                             int channel,
                             int group = 0);
    void continueMemorySequence();
    void cancelManualReadForMemorySelection();
    bool sendMemoryReceiveStage(int channel);
    bool sendMemoryModeStage(int channel);
    bool sendMemorySelectionStage(int channel);

    void captureMemoryReturnState();
    void clearMemoryReturnState();
    void restoreMemoryReturnStateLocally();
    bool sendMemoryReturnReceiveStage(int vfoNumber);
    bool sendMemoryReturnStage(int vfoNumber);
    void refreshAfterMemoryReturn();
    void queueScanCommand(quint8 subcommand,
                          const QString &label,
                          bool startsScan);
    void sendDirectCwWrite(WriteKind kind,
                           const QByteArray &payload,
                           const QString &label);
    void updateVfo(int vfoNumber);

    [[nodiscard]] QByteArray modeDataFilterPayload(quint8 modeCode,
                                                   bool dataEnabled,
                                                   quint8 filterCode) const;
    [[nodiscard]] static QByteArray encodeFrequency(quint64 frequencyHz);
    [[nodiscard]] static quint8 encodeBcdNumber(int value);
    [[nodiscard]] static quint64 decodeFrequencyValue(
        const QByteArray &fiveBcdBytes,
        bool &ok);
    [[nodiscard]] static QByteArray encodeLevel(int percent);
    [[nodiscard]] static QByteArray encodeRawLevel(int rawValue);
    [[nodiscard]] static int decodeLevel(const QByteArray &data);
    [[nodiscard]] static int decodeRawLevel(const QByteArray &data);
    [[nodiscard]] static int rawToRange(int rawValue,
                                        int minimum,
                                        int maximum,
                                        int step);
    [[nodiscard]] static int rangeToRaw(int value,
                                        int minimum,
                                        int maximum);
    [[nodiscard]] static bool encodeDirectCwText(
        const QString &text,
        QByteArray &encoded,
        QString &errorText);
    [[nodiscard]] static bool encodeKeyerMemoryText(
        const QString &text,
        QByteArray &encoded,
        QString &errorText);
    [[nodiscard]] static QByteArray encodeToneFrequency(
        int tenthsHz);
    [[nodiscard]] static int decodeToneFrequency(
        const QByteArray &data);
    [[nodiscard]] static QByteArray encodeMemoryChannel(int channel);
    [[nodiscard]] static int decodeMemoryChannel(
        const QByteArray &data);
    [[nodiscard]] static bool validateMemoryName(
        const QString &name,
        QByteArray &encoded,
        QString &errorText);
    [[nodiscard]] static QByteArray encodeRitOffset(int offsetHz);
    [[nodiscard]] static int decodeRitOffset(const QByteArray &data,
                                             bool &ok);
    [[nodiscard]] static bool parseFrequency(const QString &text,
                                             quint64 &frequencyHz,
                                             QString &errorText);
    [[nodiscard]] static quint8 modeCodeForName(const QString &modeName);
    [[nodiscard]] static bool modeSupportsData(quint8 modeCode);
    [[nodiscard]] static int clampPercent(int percent);

    void setStatus(const QString &text);
    void setActionStatus(const QString &text);
    void setLastTx(const QByteArray &data);
    void setLastRx(const QByteArray &data);

    [[nodiscard]] static QString formatHex(const QByteArray &data);
    [[nodiscard]] static QString formatFrequency(quint64 frequencyHz);
    [[nodiscard]] static QString formatFrequencyMhz(quint64 frequencyHz);
    [[nodiscard]] static QString bandForFrequency(quint64 frequencyHz);
    [[nodiscard]] static QString modeName(quint8 modeCode);
    [[nodiscard]] static QString filterName(quint8 filterCode);

    [[nodiscard]] QString vfoFrequencyText(int vfoNumber) const;
    [[nodiscard]] QString vfoBandText(int vfoNumber) const;
    [[nodiscard]] QString vfoModeText(int vfoNumber) const;
    [[nodiscard]] QString vfoDataText(int vfoNumber) const;
    [[nodiscard]] QString vfoFilterText(int vfoNumber) const;

    void loadConnectionSettings();
    void saveConnectionSettings() const;
    void scheduleAutomaticReconnect();

    QSerialPort m_serial;
    QTimer m_pollTimer;
    QTimer m_responseTimer;
    QTimer m_reconnectTimer;
    QTimer m_txSafetyTimer;

    QString m_configuredPort;
    int m_configuredBaudRate = 115200;
    quint8 m_radioAddress = 0x94;
    quint8 m_controllerAddress = 0xE0;
    bool m_autoConnectEnabled = true;
    bool m_autoReconnectEnabled = true;
    bool m_shuttingDown = false;
    int m_pollIntervalMs = 90;
    int m_responseTimeoutMs = 850;
    int m_txSafetyTimeoutSeconds = 180;

    QByteArray m_receiveBuffer;

    bool m_scopeRunning = false;
    QVariantList m_scopeSpectrumData;
    int m_scopeFrameCounter = 0;
    int m_scopeMode = 0;
    quint64 m_scopeCenterFrequencyHz = 0;
    quint64 m_scopeLowerFrequencyHz = 0;
    quint64 m_scopeHigherFrequencyHz = 0;
    quint64 m_scopeSpanHz = 100000;
    bool m_scopeOutOfRange = false;
    bool m_scopeHold = false;
    int m_scopeSweepSpeed = 0;
    bool m_scopeVbwWide = false;

    QByteArray m_scopeWaveformAssembly;
    int m_scopeExpectedDivision = 0;
    int m_scopeLastDivision = 0;

    QueryKind m_pendingQuery = QueryKind::None;
    int m_nextQueryIndex = 0;
    int m_fastMeterIndex = 0;
    int m_pollPhase = 0;
    int m_nextTxBandEdgeIndex = 1;
    int m_pendingKeyerMemoryChannel = 0;
    int m_consecutiveTimeouts = 0;
    bool m_txStateKnown = false;
    bool m_initialTxProbePending = false;
    int m_initialTxProbeAttempts = 0;
    bool m_safetyCheckActive = false;
    bool m_cwRefreshActive = false;
    QQueue<QueryKind> m_cwRefreshQueries;
    QQueue<int> m_keyerReadQueue;
    QQueue<int> m_memoryReadQueue;
    int m_pendingMemoryReadChannel = 0;
    bool m_memoryReadBatchActive = false;
    int m_memoryReadRequestedCount = 0;
    int m_memoryReadSuccessCount = 0;
    int m_memoryReadFailureCount = 0;

    int m_memoryEditVerifyChannel = 0;
    QByteArray m_memoryEditExpectedRaw;
    int m_memoryEditVerifyAttempt = 0;

    bool m_deferredMemoryReadPending = false;
    bool m_deferredMemoryReadIncludesScanSettings = false;
    int m_deferredMemoryReadFirstChannel = 1;
    int m_deferredMemoryReadCount = 99;
    QQueue<BandStackingRequest> m_bandStackingReadQueue;
    BandStackingRequest m_pendingBandStackingRequest;
    QString m_manualRefreshCompletionText =
        QStringLiteral("Configuración actualizada");

    WriteKind m_queuedWriteKind = WriteKind::None;
    WriteKind m_activeWriteKind = WriteKind::None;
    QueryKind m_queuedRefreshQuery = QueryKind::None;
    QueryKind m_activeRefreshQuery = QueryKind::None;
    QByteArray m_queuedWritePayload;
    QString m_queuedWriteLabel;
    QString m_activeWriteLabel;
    int m_queuedDesiredValue = 0;
    int m_activeDesiredValue = 0;

    bool m_busy = false;
    bool m_txReleasePending = false;
    bool m_pttOwned = false;

    QString m_status = QStringLiteral("Buscando radio…");
    QString m_actionStatus = QStringLiteral("Listo para controlar la radio");
    QString m_portName = QStringLiteral("Sin asignar");

    quint64 m_frequencyHz = 0;
    QString m_frequencyText = QStringLiteral("---.---.---");
    QString m_frequencyMhzText = QStringLiteral("--,------ MHz");
    QString m_bandText = QStringLiteral("—");

    quint8 m_modeCode = 0xFF;
    quint8 m_filterCode = 0x01;
    QString m_modeText = QStringLiteral("—");
    QString m_filterText = QStringLiteral("—");

    bool m_dataMode = false;
    bool m_transmitting = false;

    // En este equipo el uso normal parte de VFO A. La selección queda
    // corregida automáticamente cuando la radio o la aplicación emiten 07 00/01.
    int m_selectedVfo = 0;
    VfoState m_vfoStates[2];

    bool m_splitEnabled = false;
    int m_ritOffsetHz = 0;
    bool m_ritEnabled = false;
    bool m_deltaTxEnabled = false;

    int m_afGain = 0;
    int m_rfGain = 0;
    int m_squelch = 0;
    int m_rfPower = 0;
    int m_preamp = 0;
    bool m_attenuatorEnabled = false;
    int m_tunerState = 0;
    int m_agc = 1;

    bool m_noiseBlankerEnabled = false;
    int m_noiseBlankerLevel = 0;
    bool m_noiseReductionEnabled = false;
    int m_noiseReductionLevel = 0;
    bool m_autoNotchEnabled = false;
    bool m_manualNotchEnabled = false;
    int m_manualNotchPosition = 50;
    int m_manualNotchWidth = 1;
    int m_pbt1 = 50;
    int m_pbt2 = 50;
    bool m_twinPbtClearPending = false;
    bool m_ipPlusEnabled = false;
    int m_filterShape = 0;

    bool m_basicSquelchOpen = false;
    bool m_squelchOpen = false;

    int m_radioTuningStepCode = 0;
    bool m_xfcEnabled = false;
    bool m_civOutputEnabled = false;

    quint64 m_txFrequencyHz = 0;
    QString m_txFrequencyText = QStringLiteral("---.---.---");

    int m_txBandCount = -1;
    QVector<TxBandEdge> m_txBandEdges;

    int m_microphoneGain = 0;
    int m_speechCompressorLevel = 0;
    int m_monitorLevel = 0;
    int m_voxGain = 0;
    int m_antiVoxGain = 0;

    bool m_speechCompressorEnabled = false;
    bool m_monitorEnabled = false;
    bool m_voxEnabled = false;
    bool m_txInhibitEnabled = false;
    int m_txFilterWidth = 0;

    int m_cwApfPeakOffsetHz = 0;
    int m_cwPitchHz = 600;
    int m_cwKeySpeedWpm = 20;
    int m_cwBreakInDelayTenths = 70;
    int m_apfMode = 0;
    int m_breakInMode = 0;

    int m_sideToneLevel = 50;
    bool m_sideToneLimitEnabled = false;
    int m_keyerRepeatSeconds = 10;
    int m_dotDashRatioTenths = 30;
    int m_riseTimeMs = 4;
    bool m_paddleReversed = false;
    int m_keyType = 2;
    bool m_micUpDownKeyerEnabled = false;
    bool m_cwDecodeDisplayEnabled = false;
    QStringList m_keyerMemories;

    bool m_repeaterToneEnabled = false;
    bool m_toneSquelchEnabled = false;
    int m_repeaterToneTenthsHz = 885;
    int m_toneSquelchTenthsHz = 885;

    bool m_twinPeakEnabled = false;
    int m_rttyMarkFrequencyCode = 2;
    int m_rttyShiftWidthCode = 0;
    bool m_rttyKeyingReverse = false;

    QVector<MemoryState> m_memories;
    int m_memoriesRevision = 0;
    QVector<BandStackingState> m_bandStackingRegisters;
    bool m_memoryModeActive = false;
    int m_selectedMemoryChannel = 1;
    MemorySequenceAction m_memorySequenceAction =
        MemorySequenceAction::None;
    int m_memorySequenceChannel = 0;
    int m_memorySequenceGroup = 0;
    bool m_memoryStoreVfoSelected = false;
    int m_pendingDirectMemoryChannel = 0;

    MemoryVfoSnapshot m_memoryVfoSnapshot;
    bool m_directMemoryReturnInProgress = false;

    bool m_scanActive = false;
    quint8 m_scanSubcommand = 0x00;
    bool m_scanSpeedFast = false;
    bool m_scanResumeEnabled = true;
    int m_scanSelectGroup = 0;
    int m_deltaScanSpanCode = 1;

    int m_sMeterPercent = 0;
    QString m_sMeterText = QStringLiteral("S0");
    int m_powerMeterPercent = 0;
    QString m_powerMeterText = QStringLiteral("0 %");
    int m_swrMeterPercent = 0;
    QString m_swrMeterText = QStringLiteral("1,0");
    int m_alcMeterPercent = 0;
    QString m_alcMeterText = QStringLiteral("0 %");
    int m_compMeterPercent = 0;
    QString m_compMeterText = QStringLiteral("0 dB");
    int m_voltageMeterPercent = 0;
    QString m_voltageMeterText = QStringLiteral("— V");
    int m_currentMeterPercent = 0;
    QString m_currentMeterText = QStringLiteral("— A");
    bool m_overflow = false;

    QString m_lastTx = QStringLiteral("—");
    QString m_lastRx = QStringLiteral("—");

    QStringList m_txTrafficLines;
    QStringList m_rxTrafficLines;
    quint64 m_txTrafficSequence = 0;
    quint64 m_rxTrafficSequence = 0;

    static constexpr int TrafficHistoryMaximumLines = 300;
};
