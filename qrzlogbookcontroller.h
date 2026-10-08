#pragma once

#include <QDateTime>
#include <QNetworkAccessManager>
#include <QObject>
#include <QStringList>
#include <QVariantList>

#include <functional>

class QNetworkReply;

class QrzLogbookController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString apiKey READ apiKey WRITE setApiKey NOTIFY apiKeyChanged)
    Q_PROPERTY(bool configured READ configured NOTIFY apiKeyChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(int qsoCount READ qsoCount NOTIFY dataChanged)
    Q_PROPERTY(int confirmedCount READ confirmedCount NOTIFY dataChanged)
    Q_PROPERTY(int dxccCount READ dxccCount NOTIFY dataChanged)
    Q_PROPERTY(QVariantList recentQsos READ recentQsos NOTIFY dataChanged)
    Q_PROPERTY(QString recentSummary READ recentSummary NOTIFY dataChanged)

public:
    explicit QrzLogbookController(QObject *parent = nullptr);
    ~QrzLogbookController() override;

    QString apiKey() const;
    void setApiKey(const QString &key);
    bool configured() const;
    bool loading() const;
    QString status() const;
    int qsoCount() const;
    int confirmedCount() const;
    int dxccCount() const;
    QVariantList recentQsos() const;
    QString recentSummary() const;

    Q_INVOKABLE bool saveApiKey(const QString &key);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void clearApiKey();

signals:
    void apiKeyChanged();
    void loadingChanged();
    void statusChanged();
    void dataChanged();

private:
    using Fields = QList<QPair<QString, QString>>;
    using ReplyHandler = std::function<void(const QByteArray &, const QString &)>;

    void setLoading(bool loading);
    void setStatus(const QString &status);
    void sendRequest(const Fields &fields, ReplyHandler handler);
    void fetchPage();
    void finishFetch(const QString &error = {});
    void saveData();
    static Fields parseResponse(const QByteArray &body);
    static QString field(const Fields &fields, const QStringList &names);
    static QVariantList parseAdif(const QByteArray &adif,
                                 const QStringList &logIds = {});
    static QString normalizeName(const QString &name);

    QNetworkAccessManager m_network;
    QNetworkReply *m_reply = nullptr;
    QString m_apiKey;
    QString m_status = QStringLiteral("Clave API QRZ no configurada");
    QString m_recentSummary;
    QVariantList m_recentQsos;
    QList<QVariantMap> m_fetchRecords;
    int m_qsoCount = -1;
    int m_confirmedCount = -1;
    int m_dxccCount = -1;
    quint64 m_lastLogId = 0;
    quint64 m_fetchAfterLogId = 0;
    quint64 m_fetchMaxLogId = 0;
    quint64 m_requestGeneration = 0;
    bool m_loading = false;
    bool m_initialFetch = false;
};
