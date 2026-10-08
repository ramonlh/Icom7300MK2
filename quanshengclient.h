#pragma once

#include <QObject>
#include <QAbstractSocket>
#include <QByteArray>
#include <QDateTime>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <QTcpSocket>
#include <QTimer>
#include <QVariantList>

class QuanshengClient final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString token READ token WRITE setToken NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString serverLocation READ serverLocation WRITE setServerLocation NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QVariantList localSerialPorts READ localSerialPorts NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString localSerialDevice READ localSerialDevice WRITE setLocalSerialDevice NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoReconnect READ autoReconnect WRITE setAutoReconnect NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoConnectOnStartup READ autoConnectOnStartup WRITE setAutoConnectOnStartup NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoStartLocalServer READ autoStartLocalServer WRITE setAutoStartLocalServer NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString sourceStatus READ sourceStatus NOTIFY stateChanged)
    Q_PROPERTY(bool serialAvailable READ serialAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString serialPortState READ serialPortState NOTIFY stateChanged)
    Q_PROPERTY(QString serialPortDevice READ serialPortDevice NOTIFY stateChanged)
    Q_PROPERTY(QString serialPortError READ serialPortError NOTIFY stateChanged)
    Q_PROPERTY(QString serialPortUpdatedAt READ serialPortUpdatedAt NOTIFY stateChanged)
    Q_PROPERTY(QString serialPortBytes READ serialPortBytes NOTIFY stateChanged)
    Q_PROPERTY(int serialDisconnectCount READ serialDisconnectCount NOTIFY stateChanged)
    Q_PROPERTY(int serialRecoveryCount READ serialRecoveryCount NOTIFY stateChanged)
    Q_PROPERTY(QString serialDiagnostic READ serialDiagnostic NOTIFY stateChanged)
    Q_PROPERTY(bool pttPressed READ pttPressed NOTIFY stateChanged)
    Q_PROPERTY(QString pttStatus READ pttStatus NOTIFY stateChanged)
    Q_PROPERTY(bool txControlAvailable READ txControlAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool eepromReadAvailable READ eepromReadAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool frequencyControlAvailable READ frequencyControlAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString frequencyControlStatus READ frequencyControlStatus NOTIFY stateChanged)
    Q_PROPERTY(bool controlBusy READ controlBusy NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap menuValues READ menuValues NOTIFY stateChanged)
    Q_PROPERTY(QString menuReadStatus READ menuReadStatus NOTIFY stateChanged)
    Q_PROPERTY(bool menuReadAvailable READ menuReadAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool toneControlAvailable READ toneControlAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString toneStatus READ toneStatus NOTIFY stateChanged)
    Q_PROPERTY(QString toneLog READ toneLog NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap toneState READ toneState NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap toneStates READ toneStates NOTIFY stateChanged)
    Q_PROPERTY(bool eepromBusy READ eepromBusy NOTIFY stateChanged)
    Q_PROPERTY(QString eepromStatus READ eepromStatus NOTIFY stateChanged)
    Q_PROPERTY(QString eepromHexDump READ eepromHexDump NOTIFY stateChanged)
    Q_PROPERTY(QVariantList eepromChannelRows READ eepromChannelRows NOTIFY stateChanged)
    Q_PROPERTY(QVariantList eepromSettingRows READ eepromSettingRows NOTIFY stateChanged)
    Q_PROPERTY(QString candidateState READ candidateState NOTIFY stateChanged)
    Q_PROPERTY(double batteryVolts READ batteryVolts NOTIFY stateChanged)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY stateChanged)
    Q_PROPERTY(int signalLevel READ signalLevel NOTIFY stateChanged)
    Q_PROPERTY(int signalOver READ signalOver NOTIFY stateChanged)
    Q_PROPERTY(int rssiRaw READ rssiRaw NOTIFY stateChanged)
    Q_PROPERTY(int rssiDbmUncorrected READ rssiDbmUncorrected NOTIFY stateChanged)
    Q_PROPERTY(int hardwareRegisterCount READ hardwareRegisterCount NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareBlocksText READ hardwareBlocksText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareAgcText READ hardwareAgcText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareAfcText READ hardwareAfcText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareRegistersRawText READ hardwareRegistersRawText NOTIFY stateChanged)
    Q_PROPERTY(QVariantList hardwareRegisterRows READ hardwareRegisterRows NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareFunctionsText READ hardwareFunctionsText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareGpioText READ hardwareGpioText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareAudioText READ hardwareAudioText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareRfAgcText READ hardwareRfAgcText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareFilterText READ hardwareFilterText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareSquelchText READ hardwareSquelchText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwarePaText READ hardwarePaText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareCssText READ hardwareCssText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareTonesText READ hardwareTonesText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareScanText READ hardwareScanText NOTIFY stateChanged)
    Q_PROPERTY(QString hardwareDtmfText READ hardwareDtmfText NOTIFY stateChanged)
    Q_PROPERTY(QString stepText READ stepText NOTIFY stateChanged)
    Q_PROPERTY(QString toneIndicator READ toneIndicator NOTIFY stateChanged)
    Q_PROPERTY(QString indicatorsText READ indicatorsText NOTIFY stateChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY stateChanged)
    Q_PROPERTY(bool dualWatch READ dualWatch NOTIFY stateChanged)
    Q_PROPERTY(bool dualWatchKnown READ dualWatchKnown NOTIFY stateChanged)
    Q_PROPERTY(bool vox READ vox NOTIFY stateChanged)
    Q_PROPERTY(bool voxKnown READ voxKnown NOTIFY stateChanged)
    Q_PROPERTY(int voxLevel READ voxLevel NOTIFY stateChanged)
    Q_PROPERTY(int squelchLevel READ squelchLevel NOTIFY stateChanged)
    Q_PROPERTY(QString lastDtmf READ lastDtmf NOTIFY stateChanged)
    Q_PROPERTY(QString frequencyText READ frequencyText NOTIFY stateChanged)
    Q_PROPERTY(QString activeVfo READ activeVfo NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAFrequencyText READ vfoAFrequencyText NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBFrequencyText READ vfoBFrequencyText NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAMode READ vfoAMode NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBMode READ vfoBMode NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAMemory READ vfoAMemory NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBMemory READ vfoBMemory NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAName READ vfoAName NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBName READ vfoBName NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAPower READ vfoAPower NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAStep READ vfoAStep NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBStep READ vfoBStep NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBPower READ vfoBPower NOTIFY stateChanged)
    Q_PROPERTY(qulonglong eventCount READ eventCount NOTIFY countersChanged)
    Q_PROPERTY(qulonglong bytesReceived READ bytesReceived NOTIFY countersChanged)
    Q_PROPERTY(qulonglong discardedBytes READ discardedBytes NOTIFY countersChanged)
    Q_PROPERTY(int pendingBytes READ pendingBytes NOTIFY countersChanged)
    Q_PROPERTY(QString lastObservationAt READ lastObservationAt NOTIFY stateChanged)
    Q_PROPERTY(bool observationFresh READ observationFresh NOTIFY stateChanged)
    Q_PROPERTY(int observationAgeSeconds READ observationAgeSeconds NOTIFY stateChanged)
    Q_PROPERTY(int eventSilenceSeconds READ eventSilenceSeconds NOTIFY stateChanged)
    Q_PROPERTY(bool eventStreamStalled READ eventStreamStalled NOTIFY stateChanged)
    Q_PROPERTY(QString lastObservationText READ lastObservationText NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit QuanshengClient(QObject *parent = nullptr);
    ~QuanshengClient() override;

    QString host() const { return m_host; }
    int port() const { return m_port; }
    QString token() const { return m_token; }
    QString serverLocation() const { return m_serverLocation; }
    QVariantList localSerialPorts() const { return m_localSerialPorts; }
    QString localSerialDevice() const { return m_localSerialDevice; }
    bool autoReconnect() const { return m_autoReconnect; }
    bool autoConnectOnStartup() const { return m_autoConnectOnStartup; }
    bool autoStartLocalServer() const { return m_autoStartLocalServer; }
    bool connected() const { return m_socket && m_socket->state() ==  QAbstractSocket::ConnectedState; }
    QString sourceStatus() const { return m_sourceStatus; }
    bool serialAvailable() const { return m_serialAvailable; }
    QString serialPortState() const { return m_serialPortState; }
    QString serialPortDevice() const { return m_serialPortDevice; }
    QString serialPortError() const { return m_serialPortError; }
    QString serialPortUpdatedAt() const { return m_serialPortUpdatedAt; }
    QString serialPortBytes() const { return m_serialPortBytes; }
    int serialDisconnectCount() const { return m_serialDisconnectCount; }
    int serialRecoveryCount() const { return m_serialRecoveryCount; }
    QString serialDiagnostic() const { return m_serialDiagnostic; }
    bool pttPressed() const { return m_pttPressed; }
    QString pttStatus() const { return m_pttStatus; }
    bool txControlAvailable() const { return m_txControlAvailable; }
    bool eepromReadAvailable() const { return m_eepromReadAvailable; }
    bool frequencyControlAvailable() const { return m_frequencyControlAvailable; }
    QString frequencyControlStatus() const { return m_frequencyControlStatus; }
    bool controlBusy() const { return m_controlBusy; }
    QVariantMap menuValues() const { return m_menuValues; }
    QString menuReadStatus() const { return m_menuReadStatus; }
    bool menuReadAvailable() const { return m_menuReadAvailable; }
    bool eepromBusy() const { return m_eepromBusy; }
    QString eepromStatus() const { return m_eepromStatus; }
    QString eepromHexDump() const { return m_eepromHexDump; }
    QVariantList eepromChannelRows() const { return m_eepromChannelRows; }
    QVariantList eepromSettingRows() const { return m_eepromSettingRows; }
    QString candidateState() const { return m_candidateState; }
    double batteryVolts() const { return m_batteryVolts; }
    int batteryPercent() const { return m_batteryPercent; }
    int signalLevel() const { return m_signalLevel; }
    int signalOver() const { return m_signalOver; }
    int rssiRaw() const { return m_rssiRaw; }
    int rssiDbmUncorrected() const { return m_rssiDbmUncorrected; }
    int hardwareRegisterCount() const { return m_hardwareRegisterCount; }
    QString hardwareBlocksText() const { return m_hardwareBlocksText; }
    QString hardwareAgcText() const { return m_hardwareAgcText; }
    QString hardwareAfcText() const { return m_hardwareAfcText; }
    QString hardwareRegistersRawText() const { return m_hardwareRegistersRawText; }
    QVariantList hardwareRegisterRows() const { return m_hardwareRegisterRows; }
    QString hardwareFunctionsText() const { return m_hardwareFunctionsText; }
    QString hardwareGpioText() const { return m_hardwareGpioText; }
    QString hardwareAudioText() const { return m_hardwareAudioText; }
    QString hardwareRfAgcText() const { return m_hardwareRfAgcText; }
    QString hardwareFilterText() const { return m_hardwareFilterText; }
    QString hardwareSquelchText() const { return m_hardwareSquelchText; }
    QString hardwarePaText() const { return m_hardwarePaText; }
    QString hardwareCssText() const { return m_hardwareCssText; }
    QString hardwareTonesText() const { return m_hardwareTonesText; }
    QString hardwareScanText() const { return m_hardwareScanText; }
    QString hardwareDtmfText() const { return m_hardwareDtmfText; }
    QString stepText() const { return m_stepText; }
    QString toneIndicator() const { return m_toneIndicator; }
    QString indicatorsText() const { return m_indicatorsText; }
    bool charging() const { return m_charging; }
    bool dualWatch() const { return m_dualWatch; }
    bool dualWatchKnown() const { return m_dualWatchKnown; }
    bool vox() const { return m_vox; }
    bool voxKnown() const { return m_voxKnown; }
    int voxLevel() const { return m_voxLevel; }
    int squelchLevel() const { return m_squelchLevel; }
    QString lastDtmf() const { return m_lastDtmf; }
    QString frequencyText() const { return m_frequencyText; }
    QString activeVfo() const { return m_activeVfo; }
    QString vfoAFrequencyText() const { return m_vfoAFrequencyText; }
    QString vfoBFrequencyText() const { return m_vfoBFrequencyText; }
    QString vfoAMode() const { return m_vfoAMode; }
    QString vfoBMode() const { return m_vfoBMode; }
    QString vfoAMemory() const { return m_vfoAMemory; }
    QString vfoBMemory() const { return m_vfoBMemory; }
    QString vfoAName() const { return m_vfoAName; }
    QString vfoBName() const { return m_vfoBName; }
    QString vfoAPower() const { return m_vfoAPower; }
    QString vfoAStep() const { return m_vfoAStep; }
    QString vfoBStep() const { return m_vfoBStep; }
    QString vfoBPower() const { return m_vfoBPower; }
    qulonglong eventCount() const { return m_eventCount; }
    qulonglong bytesReceived() const { return m_bytesReceived; }
    qulonglong discardedBytes() const { return m_discardedBytes; }
    int pendingBytes() const { return m_pendingBytes; }
    QString lastObservationAt() const { return m_lastObservationAt; }
    bool observationFresh() const { return m_observationFresh; }
    int observationAgeSeconds() const { return m_observationAgeSeconds; }
    int eventSilenceSeconds() const { return m_eventSilenceSeconds; }
    bool eventStreamStalled() const { return m_eventStreamStalled; }
    QString lastObservationText() const { return m_lastObservationText; }
    QString error() const { return m_error; }

    void setHost(const QString &host);
    void setPort(int port);
    void setToken(const QString &token);
    void setServerLocation(const QString &location);
    void setLocalSerialDevice(const QString &device);
    void setAutoReconnect(bool enabled);
    void setAutoConnectOnStartup(bool enabled);
    void setAutoStartLocalServer(bool enabled);

    Q_INVOKABLE void connectToServer();
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void startServerGuiBySsh();
    Q_INVOKABLE void stopServerGuiBySsh();
    Q_INVOKABLE void refreshLocalSerialPorts();
    Q_INVOKABLE void restartServer();
    Q_INVOKABLE void resetCounters();
    Q_INVOKABLE void readEeprom();
    Q_INVOKABLE void setFrequency(const QString &frequencyMHz);
    Q_INVOKABLE void switchVfo();
    Q_INVOKABLE void toggleVfoMode(const QString &vfo);
    Q_INVOKABLE void stepMemory(const QString &vfo, bool up);
    Q_INVOKABLE void stepFrequency(const QString &vfo, bool up);
    Q_INVOKABLE void setMode(const QString &vfo, const QString &mode);
    Q_INVOKABLE void setDualWatch(bool enabled);
    Q_INVOKABLE void setSquelch(int level);
    Q_INVOKABLE void setVox(bool enabled);
    Q_INVOKABLE void setVoxLevel(int level);
    Q_INVOKABLE void setMenuOption(int menu, int value, const QString &label);
    Q_INVOKABLE void readMenuValues(const QVariantList &menus,
                                    bool preserveExisting = false);
    bool toneControlAvailable() const { return m_toneControlAvailable; }
    QString toneStatus() const { return m_toneStatus; }
    QString toneLog() const { return m_toneLog.join(QLatin1Char('\n')); }
    QVariantMap toneState() const { return m_toneState; }
    QVariantMap toneStates() const { return m_toneStates; }
    Q_INVOKABLE QVariantList toneOptions(int type) const;
    Q_INVOKABLE void readTones(const QString& vfo, bool txCtcssOnly = false);
    Q_INVOKABLE void setTone(const QString& vfo, const QString& direction, int type, int index);
    Q_INVOKABLE void clearToneLog();
    Q_INVOKABLE void pressPtt();
    Q_INVOKABLE void releasePtt();
    void shutdown();

signals:
    void connectionSettingsChanged();
    void connectedChanged();
    void stateChanged();
    void countersChanged();
    void errorChanged();

private slots:
    void onConnected();
    void onReadyRead();
    void onSocketError(QAbstractSocket::SocketError error);
    void onDisconnected();

private:
    bool m_toneControlAvailable = false;
    bool m_toneBusy = false;
    bool m_toneRequestPending = false;
    QString m_toneStatus = QStringLiteral("Tonos sin leer");
    QStringList m_toneLog;
    QVariantMap m_toneState;
    QVariantMap m_toneStates;

    void sendJson(const QJsonObject &object);
    void processLine(const QByteArray &line);
    void setError(const QString &error);
    void readMemoryTonesIfNeeded(const QString &vfo = {});
    void retryPendingMemoryToneRead();
    void appendToneLog(const QString &message);
    void finishRadioControlWait();
    void scheduleMenuWriteReadback();
    void updateSerialPortStatus(const QJsonObject &object);

    QTcpSocket *m_socket = nullptr;
    QTimer m_pttTimer;
    bool m_pttPressed = false;
    bool m_skipMemoryToneReadAfterPttRelease = false;
    bool m_memoryStepPending = false;
    QString m_memoryStepVfo;
    int m_memoryToneReadAttempts = 0;
    QString m_pttId;
    QString m_pttStatus = QStringLiteral("PTT no disponible");
    QTimer m_reconnectTimer;
    QTimer m_observationTimer;
    QTimer m_notifyTimer;
    QTimer m_controlSettleTimer;
    bool m_waitingControlDisplayState = false;
    bool m_notificationPending = false;
    QByteArray m_buffer;
    QString m_host = QStringLiteral("127.0.0.1");
    int m_port = 8765;
    QString m_token;
    QString m_serverLocation = QStringLiteral("local");
    QString m_localSerialDevice;
    QVariantList m_localSerialPorts;
    QString m_connectionToken;
    bool m_autoReconnect = true;
    bool m_autoConnectOnStartup = false;
    bool m_autoStartLocalServer = false;
    bool m_reconnectRequested = false;
    bool m_shuttingDown = false;
    QString m_sourceStatus = QStringLiteral("desconectado");
    bool m_serialAvailable = false;
    QString m_serialPortState = QStringLiteral("unknown");
    QString m_serialPortDevice;
    QString m_serialPortError;
    QString m_serialPortUpdatedAt;
    QString m_serialPortBytes;
    int m_serialDisconnectCount = 0;
    int m_serialRecoveryCount = 0;
    QString m_serialDiagnostic;
    bool m_txControlAvailable = false;
    bool m_eepromReadAvailable = false;
    bool m_frequencyControlAvailable = false;
    QString m_frequencyControlStatus = QStringLiteral("No disponible");
    bool m_controlBusy = false;
    QString m_controlOperation;
    QVariantMap m_menuValues;
    QString m_menuReadStatus = QStringLiteral("Valores sin leer");
    bool m_menuReadAvailable = false;
    QString m_pendingVfoModeTarget;
    QString m_pendingVfoModePreviousMemory;
    QString m_pendingRadioControl;
    int m_pendingMenuReadback = -1;
    bool m_pendingDualWatchPrevious = false;
    int m_pendingSquelchPrevious = -1;
    bool m_pendingVoxPrevious = false;
    int m_pendingVoxLevelPrevious = 0;
    bool m_eepromBusy = false;
    QString m_eepromStatus = QStringLiteral("Sin leer");
    QString m_eepromHexDump;
    QVariantList m_eepromChannelRows;
    QVariantList m_eepromSettingRows;
    QString m_candidateState;
    double m_batteryVolts = 0.0;
    int m_batteryPercent = -1;
    int m_signalLevel = -1;
    int m_signalOver = 0;
    int m_rssiRaw = -1;
    int m_rssiDbmUncorrected = 0;
    int m_hardwareRegisterCount = 0;
    QString m_hardwareBlocksText;
    QString m_hardwareAgcText;
    QString m_hardwareAfcText;
    QString m_hardwareRegistersRawText;
    QVariantList m_hardwareRegisterRows;
    QString m_hardwareFunctionsText;
    QString m_hardwareGpioText;
    QString m_hardwareAudioText;
    QString m_hardwareRfAgcText;
    QString m_hardwareFilterText;
    QString m_hardwareSquelchText;
    QString m_hardwarePaText;
    QString m_hardwareCssText;
    QString m_hardwareTonesText;
    QString m_hardwareScanText;
    QString m_hardwareDtmfText;
    QString m_stepText;
    QString m_toneIndicator;
    QString m_indicatorsText;
    bool m_charging = false;
    bool m_dualWatch = false;
    bool m_dualWatchKnown = false;
    bool m_vox = false;
    bool m_voxKnown = false;
    int m_voxLevel = 0;
    int m_squelchLevel = -1;
    QString m_lastDtmf;
    QString m_frequencyText;
    QString m_activeVfo;
    QString m_vfoAFrequencyText;
    QString m_vfoBFrequencyText;
    QString m_vfoAMode;
    QString m_vfoBMode;
    QString m_vfoAMemory;
    QString m_vfoBMemory;
    QString m_vfoAName;
    QString m_vfoBName;
    QString m_vfoAPower;
    QString m_vfoAStep, m_vfoBStep;
    QString m_vfoBPower;
    qulonglong m_eventCount = 0;
    qulonglong m_bytesReceived = 0;
    qulonglong m_discardedBytes = 0;
    int m_pendingBytes = 0;
    QString m_lastObservationAt;
    QString m_lastObservationText;
    bool m_observationFresh = false;
    int m_observationAgeSeconds = -1;
    QDateTime m_lastEventReceivedAt;
    int m_eventSilenceSeconds = -1;
    bool m_eventStreamStalled = false;
    QString m_error;
};
