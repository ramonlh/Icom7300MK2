#pragma once

#include <QObject>
#include <QAudioFormat>
#include <QHash>
#include <QList>
#include <QPair>
#include <QStringList>

class QTcpServer;
class QTcpSocket;
class QTimer;
class QAudioSource;
class QIODevice;
class RadioController;

class RemoteServer final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int port READ port NOTIFY settingsChanged)
    Q_PROPERTY(QString accessToken READ accessToken NOTIFY settingsChanged)
    Q_PROPERTY(QStringList accessUrls READ accessUrls NOTIFY networkInfoChanged)
    Q_PROPERTY(QString primaryUrl READ primaryUrl NOTIFY networkInfoChanged)
    Q_PROPERTY(QString localTestUrl READ localTestUrl NOTIFY networkInfoChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(int activeClients READ activeClients NOTIFY activeClientsChanged)
    Q_PROPERTY(bool autoStart READ autoStart NOTIFY settingsChanged)

public:
    explicit RemoteServer(RadioController *radioController,
                          QObject *parent = nullptr);
    ~RemoteServer() override;

    [[nodiscard]] bool running() const;
    [[nodiscard]] int port() const;
    [[nodiscard]] QString accessToken() const;
    [[nodiscard]] QStringList accessUrls() const;
    [[nodiscard]] QString primaryUrl() const;
    [[nodiscard]] QString localTestUrl() const;
    [[nodiscard]] QString status() const;
    [[nodiscard]] int activeClients() const;
    [[nodiscard]] bool autoStart() const;

    Q_INVOKABLE bool start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE bool setPort(int port);
    Q_INVOKABLE void setAutoStart(bool enabled);
    Q_INVOKABLE bool setAccessToken(const QString &token);
    Q_INVOKABLE void regenerateToken();
    Q_INVOKABLE void refreshNetworkInfo();

signals:
    void runningChanged();
    void settingsChanged();
    void networkInfoChanged();
    void statusChanged();
    void activeClientsChanged();

private:
    void loadSettings();
    void saveSettings() const;
    void setStatus(const QString &status);
    void updateAccessUrls();
    void pruneClients();
    void noteClient(QTcpSocket *socket);
    void rememberCurrentBandFrequencies();
    void rememberBandFrequency(int vfoNumber, qint64 frequencyHz);
    [[nodiscard]] qint64 rememberedBandFrequency(int vfoNumber, const QString &bandName) const;
    [[nodiscard]] QByteArray bandStateJson() const;

    void onNewConnection();
    void onReadyRead(QTcpSocket *socket);
    void processRequest(QTcpSocket *socket, const QByteArray &request);
    bool upgradeAudioWebSocket(
        QTcpSocket *socket,
        const QByteArray &requestTarget,
        const QHash<QByteArray, QByteArray> &headers
    );
    bool startAudioCapture();
    void stopAudioCaptureIfIdle();
    void broadcastAudio();
    void sendWebSocketFrame(QTcpSocket *socket,
                            quint8 opcode,
                            const QByteArray &payload);

    [[nodiscard]] bool authorized(const QHash<QByteArray, QByteArray> &headers) const;
    [[nodiscard]] QByteArray radioStateJson() const;
    [[nodiscard]] QByteArray handleCommand(const QByteArray &body,
                                           int *httpStatus,
                                           QString *errorText);
    [[nodiscard]] QByteArray loadWebPage() const;

    void sendResponse(QTcpSocket *socket,
                      int statusCode,
                      const QByteArray &contentType,
                      const QByteArray &body,
                      const QList<QPair<QByteArray, QByteArray>> &extraHeaders = {});

    RadioController *m_radio = nullptr;
    QTcpServer *m_server = nullptr;
    QTimer *m_clientTimer = nullptr;
    QHash<QTcpSocket *, QByteArray> m_buffers;
    QHash<QString, qint64> m_clients;
    QHash<QString, qint64> m_bandMemories;
    QList<QTcpSocket *> m_audioClients;
    QAudioSource *m_audioSource = nullptr;
    QIODevice *m_audioInput = nullptr;
    QAudioFormat m_audioFormat;

    int m_port = 7300;
    QString m_accessToken;
    QStringList m_accessUrls;
    QString m_primaryUrl;
    QString m_status = QStringLiteral("Servidor remoto detenido");
    bool m_autoStart = false;
};
