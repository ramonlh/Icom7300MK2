#pragma once

#include <QObject>
#include <QAbstractSocket>
#include <QByteArray>
#include <QJsonObject>
#include <QString>
#include <QTcpSocket>
#include <QTimer>

class QuanshengClient final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY connectionSettingsChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY connectionSettingsChanged)
    Q_PROPERTY(QString token READ token WRITE setToken NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoReconnect READ autoReconnect WRITE setAutoReconnect NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool autoConnectOnStartup READ autoConnectOnStartup WRITE setAutoConnectOnStartup NOTIFY connectionSettingsChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString sourceStatus READ sourceStatus NOTIFY stateChanged)
    Q_PROPERTY(bool serialAvailable READ serialAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool txControlAvailable READ txControlAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString candidateState READ candidateState NOTIFY stateChanged)
    Q_PROPERTY(double batteryVolts READ batteryVolts NOTIFY stateChanged)
    Q_PROPERTY(QString frequencyText READ frequencyText NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAFrequencyText READ vfoAFrequencyText NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBFrequencyText READ vfoBFrequencyText NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAMode READ vfoAMode NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBMode READ vfoBMode NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAMemory READ vfoAMemory NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBMemory READ vfoBMemory NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAName READ vfoAName NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBName READ vfoBName NOTIFY stateChanged)
    Q_PROPERTY(QString vfoAPower READ vfoAPower NOTIFY stateChanged)
    Q_PROPERTY(QString vfoBPower READ vfoBPower NOTIFY stateChanged)
    Q_PROPERTY(qulonglong eventCount READ eventCount NOTIFY countersChanged)
    Q_PROPERTY(qulonglong bytesReceived READ bytesReceived NOTIFY countersChanged)
    Q_PROPERTY(qulonglong discardedBytes READ discardedBytes NOTIFY countersChanged)
    Q_PROPERTY(int pendingBytes READ pendingBytes NOTIFY countersChanged)
    Q_PROPERTY(QString lastObservationAt READ lastObservationAt NOTIFY stateChanged)
    Q_PROPERTY(bool observationFresh READ observationFresh NOTIFY stateChanged)
    Q_PROPERTY(int observationAgeSeconds READ observationAgeSeconds NOTIFY stateChanged)
    Q_PROPERTY(QString lastObservationText READ lastObservationText NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit QuanshengClient(QObject *parent = nullptr);
    ~QuanshengClient() override;

    QString host() const { return m_host; }
    int port() const { return m_port; }
    QString token() const { return m_token; }
    bool autoReconnect() const { return m_autoReconnect; }
    bool autoConnectOnStartup() const { return m_autoConnectOnStartup; }
    bool connected() const { return m_socket && m_socket->state() ==  QAbstractSocket::ConnectedState; }
    QString sourceStatus() const { return m_sourceStatus; }
    bool serialAvailable() const { return m_serialAvailable; }
    bool txControlAvailable() const { return m_txControlAvailable; }
    QString candidateState() const { return m_candidateState; }
    double batteryVolts() const { return m_batteryVolts; }
    QString frequencyText() const { return m_frequencyText; }
    QString vfoAFrequencyText() const { return m_vfoAFrequencyText; }
    QString vfoBFrequencyText() const { return m_vfoBFrequencyText; }
    QString vfoAMode() const { return m_vfoAMode; }
    QString vfoBMode() const { return m_vfoBMode; }
    QString vfoAMemory() const { return m_vfoAMemory; }
    QString vfoBMemory() const { return m_vfoBMemory; }
    QString vfoAName() const { return m_vfoAName; }
    QString vfoBName() const { return m_vfoBName; }
    QString vfoAPower() const { return m_vfoAPower; }
    QString vfoBPower() const { return m_vfoBPower; }
    qulonglong eventCount() const { return m_eventCount; }
    qulonglong bytesReceived() const { return m_bytesReceived; }
    qulonglong discardedBytes() const { return m_discardedBytes; }
    int pendingBytes() const { return m_pendingBytes; }
    QString lastObservationAt() const { return m_lastObservationAt; }
    bool observationFresh() const { return m_observationFresh; }
    int observationAgeSeconds() const { return m_observationAgeSeconds; }
    QString lastObservationText() const { return m_lastObservationText; }
    QString error() const { return m_error; }

    void setHost(const QString &host);
    void setPort(int port);
    void setToken(const QString &token);
    void setAutoReconnect(bool enabled);
    void setAutoConnectOnStartup(bool enabled);

    Q_INVOKABLE void connectToServer();
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void resetCounters();
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
    void sendJson(const QJsonObject &object);
    void processLine(const QByteArray &line);
    void setError(const QString &error);

    QTcpSocket *m_socket = nullptr;
    QTimer m_reconnectTimer;
    QTimer m_observationTimer;
    QTimer m_notifyTimer;
    bool m_notificationPending = false;
    QByteArray m_buffer;
    QString m_host = QStringLiteral("127.0.0.1");
    int m_port = 8765;
    QString m_token;
    bool m_autoReconnect = true;
    bool m_autoConnectOnStartup = false;
    bool m_reconnectRequested = false;
    bool m_shuttingDown = false;
    QString m_sourceStatus = QStringLiteral("desconectado");
    bool m_serialAvailable = false;
    bool m_txControlAvailable = false;
    QString m_candidateState;
    double m_batteryVolts = 0.0;
    QString m_frequencyText;
    QString m_vfoAFrequencyText;
    QString m_vfoBFrequencyText;
    QString m_vfoAMode;
    QString m_vfoBMode;
    QString m_vfoAMemory;
    QString m_vfoBMemory;
    QString m_vfoAName;
    QString m_vfoBName;
    QString m_vfoAPower;
    QString m_vfoBPower;
    qulonglong m_eventCount = 0;
    qulonglong m_bytesReceived = 0;
    qulonglong m_discardedBytes = 0;
    int m_pendingBytes = 0;
    QString m_lastObservationAt;
    QString m_lastObservationText;
    bool m_observationFresh = false;
    int m_observationAgeSeconds = -1;
    QString m_error;
};
