#pragma once

#include <QObject>

class QProcess;
class QNetworkAccessManager;

class ApplicationLauncher final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool decodiumRunning READ decodiumRunning
               NOTIFY decodiumRunningChanged)
    Q_PROPERTY(bool fldigiRunning READ fldigiRunning
               NOTIFY fldigiRunningChanged)
    Q_PROPERTY(bool qsstvRunning READ qsstvRunning
               NOTIFY qsstvRunningChanged)
    Q_PROPERTY(bool js8callRunning READ js8callRunning
               NOTIFY js8callRunningChanged)
    Q_PROPERTY(qulonglong rttyFrequencyHz READ rttyFrequencyHz
               WRITE setRttyFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong cwFrequencyHz READ cwFrequencyHz
               WRITE setCwFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong ftFrequencyHz READ ftFrequencyHz
               WRITE setFtFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong sstvFrequencyHz READ sstvFrequencyHz
               WRITE setSstvFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong pskFrequencyHz READ pskFrequencyHz
               WRITE setPskFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong oliviaFrequencyHz READ oliviaFrequencyHz
               WRITE setOliviaFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong js8FrequencyHz READ js8FrequencyHz
               WRITE setJs8FrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(qulonglong wefaxFrequencyHz READ wefaxFrequencyHz
               WRITE setWefaxFrequencyHz NOTIFY digitalFrequenciesChanged)
    Q_PROPERTY(int compactWindowX READ compactWindowX
               WRITE setCompactWindowX NOTIFY compactWindowPositionChanged)
    Q_PROPERTY(int compactWindowY READ compactWindowY
               WRITE setCompactWindowY NOTIFY compactWindowPositionChanged)
    Q_PROPERTY(int superWindowX READ superWindowX WRITE setSuperWindowX NOTIFY compactWindowPositionChanged)
    Q_PROPERTY(int superWindowY READ superWindowY WRITE setSuperWindowY NOTIFY compactWindowPositionChanged)
    Q_PROPERTY(int compactWindowWidth READ compactWindowWidth
               WRITE setCompactWindowWidth NOTIFY compactWindowSizeChanged)
    Q_PROPERTY(bool compactModePreferred READ compactModePreferred
               WRITE setCompactModePreferred NOTIFY compactModePreferredChanged)
    Q_PROPERTY(int mainWindowX READ mainWindowX
               WRITE setMainWindowX NOTIFY mainWindowPositionChanged)
    Q_PROPERTY(int mainWindowY READ mainWindowY
               WRITE setMainWindowY NOTIFY mainWindowPositionChanged)
    Q_PROPERTY(bool compactAlwaysOnTop READ compactAlwaysOnTop
               WRITE setCompactAlwaysOnTop NOTIFY compactAlwaysOnTopChanged)
    Q_PROPERTY(QString lanHost READ lanHost WRITE setLanHost NOTIFY lanSettingsChanged)
    Q_PROPERTY(QString lanUser READ lanUser WRITE setLanUser NOTIFY lanSettingsChanged)
    Q_PROPERTY(QString lanPassword READ lanPassword WRITE setLanPassword NOTIFY lanSettingsChanged)
    Q_PROPERTY(bool lanConnectionEnabled READ lanConnectionEnabled WRITE setLanConnectionEnabled NOTIFY lanSettingsChanged)
    Q_PROPERTY(bool lanConnected READ lanConnected NOTIFY lanConnectionChanged)
    Q_PROPERTY(bool lanDataEnabled READ lanDataEnabled NOTIFY lanDataEnabledChanged)
    Q_PROPERTY(QString lanMode READ lanMode NOTIFY lanModeChanged)

public:
    explicit ApplicationLauncher(QObject *parent = nullptr);

    [[nodiscard]] QString status() const;
    [[nodiscard]] bool decodiumRunning() const;
    Q_INVOKABLE bool launchDecodium();
    Q_INVOKABLE void stopDecodium();
    [[nodiscard]] bool fldigiRunning() const;
    Q_INVOKABLE bool launchFldigi();
    Q_INVOKABLE void stopFldigi();
    Q_INVOKABLE void setFldigiMode(const QString &modeName);
    Q_INVOKABLE void setFldigiReverse(bool enabled);
    [[nodiscard]] bool qsstvRunning() const;
    Q_INVOKABLE bool launchQsstv();
    Q_INVOKABLE void stopQsstv();
    [[nodiscard]] bool js8callRunning() const;
    Q_INVOKABLE bool launchJs8call();
    Q_INVOKABLE void stopJs8call();
    [[nodiscard]] qulonglong rttyFrequencyHz() const;
    [[nodiscard]] qulonglong cwFrequencyHz() const;
    [[nodiscard]] qulonglong ftFrequencyHz() const;
    [[nodiscard]] qulonglong sstvFrequencyHz() const;
    [[nodiscard]] qulonglong pskFrequencyHz() const;
    [[nodiscard]] qulonglong oliviaFrequencyHz() const;
    [[nodiscard]] qulonglong js8FrequencyHz() const;
    [[nodiscard]] qulonglong wefaxFrequencyHz() const;
    void setRttyFrequencyHz(qulonglong value);
    void setCwFrequencyHz(qulonglong value);
    void setFtFrequencyHz(qulonglong value);
    void setSstvFrequencyHz(qulonglong value);
    void setPskFrequencyHz(qulonglong value);
    void setOliviaFrequencyHz(qulonglong value);
    void setJs8FrequencyHz(qulonglong value);
    void setWefaxFrequencyHz(qulonglong value);
    [[nodiscard]] int compactWindowX() const;
    [[nodiscard]] int compactWindowY() const;
    void setCompactWindowX(int value);
    void setCompactWindowY(int value);
    [[nodiscard]] int superWindowX() const;
    [[nodiscard]] int superWindowY() const;
    void setSuperWindowX(int value);
    void setSuperWindowY(int value);
    [[nodiscard]] int compactWindowWidth() const;
    void setCompactWindowWidth(int value);
    [[nodiscard]] bool compactModePreferred() const;
    void setCompactModePreferred(bool value);
    [[nodiscard]] int mainWindowX() const;
    [[nodiscard]] int mainWindowY() const;
    void setMainWindowX(int value);
    void setMainWindowY(int value);
    [[nodiscard]] bool compactAlwaysOnTop() const;
    void setCompactAlwaysOnTop(bool value);
    QString lanHost() const;
    QString lanUser() const;
    QString lanPassword() const;
    void setLanHost(const QString &value);
    void setLanUser(const QString &value);
    void setLanPassword(const QString &value);
    bool lanConnectionEnabled() const;
    bool lanConnected() const;
    bool lanDataEnabled() const;
    QString lanMode() const;
    void setLanConnectionEnabled(bool value);
    Q_INVOKABLE void testLanConnection();
    Q_INVOKABLE void disconnectLanConnection();
    Q_INVOKABLE void testLanMode();
    Q_INVOKABLE void testLanModeName(const QString &mode);
    Q_INVOKABLE void setLanFrequency(qulonglong frequencyHz);
    Q_INVOKABLE void setLanDataEnabled(bool enabled, const QString &mode = QStringLiteral("USB"));
    Q_INVOKABLE void shutdownLanConnection();

signals:
    void statusChanged();
    void decodiumRunningChanged();
    void fldigiRunningChanged();
    void qsstvRunningChanged();
    void js8callRunningChanged();
    void digitalFrequenciesChanged();
    void compactWindowPositionChanged();
    void compactWindowSizeChanged();
    void compactModePreferredChanged();
    void mainWindowPositionChanged();
    void compactAlwaysOnTopChanged();
    void lanSettingsChanged();
    void lanFrequencyReceived(qulonglong frequencyHz);
    void lanConnectionChanged();
    void lanDataEnabledChanged();
    void lanModeChanged();

private:
    void setStatus(const QString &status);

    QString m_status;
    QProcess *m_decodiumProcess = nullptr;
    QProcess *m_fldigiProcess = nullptr;
    QProcess *m_qsstvProcess = nullptr;
    QProcess *m_js8callProcess = nullptr;
    QNetworkAccessManager *m_network = nullptr;
    bool m_js8callUsesFlatpak = false;
    qulonglong m_rttyFrequencyHz = 14080000;
    qulonglong m_cwFrequencyHz = 14060000;
    qulonglong m_ftFrequencyHz = 14074000;
    qulonglong m_sstvFrequencyHz = 14230000;
    qulonglong m_pskFrequencyHz = 14070000;
    qulonglong m_oliviaFrequencyHz = 14105000;
    qulonglong m_js8FrequencyHz = 14078000;
    qulonglong m_wefaxFrequencyHz = 13880600;
    int m_compactWindowX = -1;
    int m_compactWindowY = -1;
    int m_superWindowX = -1;
    int m_superWindowY = -1;
    int m_compactWindowWidth = 780;
    bool m_compactModePreferred = false;
    int m_mainWindowX = -1;
    int m_mainWindowY = -1;
    bool m_compactAlwaysOnTop = true;
    QString m_lanHost = QStringLiteral("192.168.1.154");
    QString m_lanUser;
    QString m_lanPassword;
    bool m_lanConnectionEnabled = false;
    bool m_lanConnected = false;
    bool m_lanDataEnabled = false;
    QString m_lanMode;
};
