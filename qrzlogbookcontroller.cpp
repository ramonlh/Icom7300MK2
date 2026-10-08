#include "qrzlogbookcontroller.h"

#include <QDate>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrl>
#include <QUrlQuery>

#include <algorithm>

namespace {
constexpr int QrzPageSize = 250;

quint64 recordLogId(const QVariantMap &record)
{
    return record.value(QStringLiteral("logId")).toULongLong();
}

QByteArray decodeAdifPayload(QByteArray payload)
{
    QString decoded = QString::fromUtf8(payload);
    if (decoded.contains(QStringLiteral("%3c"), Qt::CaseInsensitive)) {
        payload.replace('+', ' ');
        decoded = QUrl::fromPercentEncoding(payload);
    }

    decoded.replace(QStringLiteral("&lt;"), QStringLiteral("<"), Qt::CaseInsensitive);
    decoded.replace(QStringLiteral("&gt;"), QStringLiteral(">"), Qt::CaseInsensitive);
    decoded.replace(QStringLiteral("&quot;"), QStringLiteral("\""), Qt::CaseInsensitive);
    decoded.replace(QStringLiteral("&#39;"), QStringLiteral("'"), Qt::CaseInsensitive);
    decoded.replace(QStringLiteral("&apos;"), QStringLiteral("'"), Qt::CaseInsensitive);
    decoded.replace(QStringLiteral("&amp;"), QStringLiteral("&"), Qt::CaseInsensitive);
    return decoded.toUtf8();
}
}

QrzLogbookController::QrzLogbookController(QObject *parent)
    : QObject(parent)
{
    QSettings settings;
    m_apiKey = settings.value(QStringLiteral("qrz/apiKey")).toString().trimmed();
    m_qsoCount = settings.value(QStringLiteral("qrz/qsoCount"), -1).toInt();
    m_confirmedCount = settings.value(QStringLiteral("qrz/confirmedCount"), -1).toInt();
    m_dxccCount = settings.value(QStringLiteral("qrz/dxccCount"), -1).toInt();
    m_lastLogId = settings.value(QStringLiteral("qrz/lastLogId"), 0).toULongLong();

    const QJsonDocument cached = QJsonDocument::fromJson(
        settings.value(QStringLiteral("qrz/recentQsos")).toByteArray());
    if (cached.isArray())
        m_recentQsos = cached.array().toVariantList();

    if (!m_recentQsos.isEmpty()) {
        QStringList summaries;
        for (const QVariant &value : m_recentQsos) {
            const QVariantMap qso = value.toMap();
            QString line = qso.value(QStringLiteral("call")).toString();
            const QString band = qso.value(QStringLiteral("band")).toString();
            const QString mode = qso.value(QStringLiteral("mode")).toString();
            const QString time = qso.value(QStringLiteral("time")).toString();
            if (!band.isEmpty())
                line += QStringLiteral(" · ") + band;
            if (!mode.isEmpty())
                line += QStringLiteral(" ") + mode;
            if (!time.isEmpty())
                line += QStringLiteral(" · ") + time;
            summaries.append(line);
        }
        m_recentSummary = summaries.join(QStringLiteral("   |   "));
    }

    m_status = m_apiKey.isEmpty()
                   ? QStringLiteral("Clave API QRZ no configurada")
                   : (m_recentQsos.isEmpty()
                          ? QStringLiteral("Pendiente de actualizar QRZ")
                          : QStringLiteral("Datos QRZ guardados"));
}

QrzLogbookController::~QrzLogbookController()
{
    if (m_reply)
        m_reply->abort();
}

QString QrzLogbookController::apiKey() const { return m_apiKey; }
bool QrzLogbookController::configured() const { return !m_apiKey.isEmpty(); }
bool QrzLogbookController::loading() const { return m_loading; }
QString QrzLogbookController::status() const { return m_status; }
int QrzLogbookController::qsoCount() const { return m_qsoCount; }
int QrzLogbookController::confirmedCount() const { return m_confirmedCount; }
int QrzLogbookController::dxccCount() const { return m_dxccCount; }
QVariantList QrzLogbookController::recentQsos() const { return m_recentQsos; }
QString QrzLogbookController::recentSummary() const { return m_recentSummary; }

bool QrzLogbookController::saveApiKey(const QString &key)
{
    setApiKey(key);
    QSettings settings;
    settings.sync();
    return settings.status() == QSettings::NoError
           && settings.value(QStringLiteral("qrz/apiKey")).toString() == key.trimmed();
}

void QrzLogbookController::setApiKey(const QString &key)
{
    const QString normalized = key.trimmed();
    QSettings settings;
    settings.setValue(QStringLiteral("qrz/apiKey"), normalized);
    settings.sync();
    if (settings.status() != QSettings::NoError) {
        setStatus(QStringLiteral("No se pudo guardar la clave QRZ en la configuración local"));
        return;
    }
    if (normalized == m_apiKey) {
        if (!normalized.isEmpty())
            setStatus(QStringLiteral("Clave guardada; pulsa Actualizar"));
        return;
    }

    ++m_requestGeneration;
    if (m_reply) {
        m_reply->abort();
        m_reply = nullptr;
    }
    setLoading(false);

    m_apiKey = normalized;
    emit apiKeyChanged();
    m_qsoCount = -1;
    m_confirmedCount = -1;
    m_dxccCount = -1;
    m_lastLogId = 0;
    m_recentQsos.clear();
    m_recentSummary.clear();
    QSettings cacheSettings;
    cacheSettings.remove(QStringLiteral("qrz/qsoCount"));
    cacheSettings.remove(QStringLiteral("qrz/confirmedCount"));
    cacheSettings.remove(QStringLiteral("qrz/dxccCount"));
    cacheSettings.remove(QStringLiteral("qrz/lastLogId"));
    cacheSettings.remove(QStringLiteral("qrz/recentQsos"));
    emit dataChanged();
    if (m_apiKey.isEmpty()) {
        setStatus(QStringLiteral("Clave API QRZ no configurada"));
    } else {
        setStatus(QStringLiteral("Clave guardada; pulsa Actualizar"));
    }
}

void QrzLogbookController::clearApiKey()
{
    setApiKey({});
}

void QrzLogbookController::setLoading(bool loading)
{
    if (m_loading == loading)
        return;
    m_loading = loading;
    emit loadingChanged();
}

void QrzLogbookController::setStatus(const QString &status)
{
    if (status == m_status)
        return;
    m_status = status;
    emit statusChanged();
}

void QrzLogbookController::refresh()
{
    if (m_apiKey.isEmpty()) {
        setStatus(QStringLiteral("Configura la clave API QRZ"));
        return;
    }
    if (m_loading)
        return;

    setLoading(true);
    setStatus(QStringLiteral("Consultando QRZ…"));
    m_initialFetch = (m_lastLogId == 0 || m_recentQsos.isEmpty());
    m_fetchRecords.clear();
    if (!m_initialFetch) {
        for (const QVariant &value : m_recentQsos)
            m_fetchRecords.append(value.toMap());
    }
    m_fetchMaxLogId = m_lastLogId;
    m_fetchAfterLogId = m_initialFetch ? 0 : m_lastLogId + 1;

    const quint64 generation = m_requestGeneration;
    sendRequest({{QStringLiteral("KEY"), m_apiKey},
                 {QStringLiteral("ACTION"), QStringLiteral("STATUS")}},
                [this, generation](const QByteArray &body, const QString &error) {
        if (generation != m_requestGeneration)
            return;
        if (!error.isEmpty()) {
            finishFetch(error);
            return;
        }

        Fields fields = parseResponse(body);
        const QString result = field(fields, {QStringLiteral("RESULT"),
                                               QStringLiteral("STATUS")}).toUpper();
        if (result == QStringLiteral("AUTH") || result == QStringLiteral("FAIL")
            || result == QStringLiteral("ERROR")) {
            const QString reason = field(fields, {QStringLiteral("REASON")});
            finishFetch(reason.isEmpty()
                            ? QStringLiteral("QRZ rechazó la clave API")
                            : QStringLiteral("QRZ: ") + reason);
            return;
        }

        const QString data = field(fields, {QStringLiteral("DATA")});
        if (!data.isEmpty()) {
            const Fields nested = parseResponse(data.toUtf8());
            for (const auto &item : nested)
                fields.append(item);
        }

        bool ok = false;
        QString value = field(fields, {QStringLiteral("TOTALQSOS"),
                                       QStringLiteral("TOTALQSO"),
                                       QStringLiteral("QSOS"),
                                       QStringLiteral("QSOCOUNT"),
                                       QStringLiteral("TOTAL"),
                                       QStringLiteral("COUNT")});
        int parsed = value.toInt(&ok);
        if (ok)
            m_qsoCount = parsed;

        value = field(fields, {QStringLiteral("CONFIRMED"),
                               QStringLiteral("CONFIRMEDQSOS"),
                               QStringLiteral("QSOSCONFIRMED"),
                               QStringLiteral("CONFIRMEDCOUNT"),
                               QStringLiteral("TOTALCONFIRMED"),
                               QStringLiteral("QSLCOUNT")});
        parsed = value.toInt(&ok);
        if (ok)
            m_confirmedCount = parsed;

        value = field(fields, {QStringLiteral("DXCCTOTAL"),
                               QStringLiteral("DXCCCOUNT"),
                               QStringLiteral("DXCC"),
                               QStringLiteral("COUNTRIES"),
                               QStringLiteral("COUNTRYCOUNT")});
        parsed = value.toInt(&ok);
        if (ok)
            m_dxccCount = parsed;
        emit dataChanged();
        fetchPage();
    });
}

void QrzLogbookController::sendRequest(const Fields &fields,
                                       ReplyHandler handler)
{
    QUrlQuery form;
    for (const auto &item : fields)
        form.addQueryItem(item.first, item.second);

    QNetworkRequest request(QUrl(QStringLiteral("https://logbook.qrz.com/api")));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));
    request.setRawHeader("User-Agent", "Icom7300Mk2Control/1.2.13");
    request.setTransferTimeout(20000);
    const quint64 generation = m_requestGeneration;
    QNetworkReply *reply = m_network.post(
        request, form.query(QUrl::FullyEncoded).toUtf8());
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, generation, handler = std::move(handler)]() mutable {
        const QByteArray body = reply->readAll();
        const QString error = reply->error() == QNetworkReply::NoError
                                  ? QString()
                                  : reply->errorString();
        if (m_reply == reply)
            m_reply = nullptr;
        reply->deleteLater();
        if (generation == m_requestGeneration)
            handler(body, error);
    });
}

void QrzLogbookController::fetchPage()
{
    const quint64 generation = m_requestGeneration;
    sendRequest({{QStringLiteral("KEY"), m_apiKey},
                 {QStringLiteral("ACTION"), QStringLiteral("FETCH")},
                 {QStringLiteral("OPTION"),
                  QStringLiteral("TYPE:ADIF,MAX:%1,AFTERLOGID:%2")
                      .arg(QrzPageSize)
                      .arg(m_fetchAfterLogId)}},
                [this, generation](const QByteArray &body, const QString &error) {
        if (generation != m_requestGeneration)
            return;
        if (!error.isEmpty()) {
            finishFetch(error);
            return;
        }

        QByteArray metadata = body;
        QByteArray adifBytes;
        int adifMarker = -1;
        int searchFrom = 0;
        while ((searchFrom = body.indexOf("ADIF=", searchFrom)) >= 0) {
            if (searchFrom == 0 || body.at(searchFrom - 1) == '&'
                || body.at(searchFrom - 1) == ';') {
                adifMarker = searchFrom;
                break;
            }
            searchFrom += 5;
        }
        if (adifMarker >= 0) {
            metadata = body.left(adifMarker);
            if (!metadata.isEmpty()
                && (metadata.endsWith('&') || metadata.endsWith(';')))
                metadata.chop(1);
            adifBytes = decodeAdifPayload(body.mid(adifMarker + 5));
        }

        const Fields fields = parseResponse(metadata);
        const QString result = field(fields, {QStringLiteral("RESULT"),
                                               QStringLiteral("STATUS")}).toUpper();
        if (adifMarker < 0) {
            finishFetch(QStringLiteral("QRZ respondió sin el campo ADIF"));
            return;
        }
        const QString ids = field(fields, {QStringLiteral("LOGIDS")});
        const QString count = field(fields, {QStringLiteral("COUNT")});
        if (result == QStringLiteral("AUTH") || result == QStringLiteral("ERROR")
            || result == QStringLiteral("FAIL")) {
            const QString reason = field(fields, {QStringLiteral("REASON")});
            finishFetch(reason.isEmpty() ? QStringLiteral("Error al leer QSOs de QRZ")
                                         : QStringLiteral("QRZ: ") + reason);
            return;
        }

        const QStringList logIds = ids.split(QLatin1Char(','), Qt::SkipEmptyParts);
        const QVariantList page = parseAdif(adifBytes, logIds);
        if (page.isEmpty()) {
            if ((m_initialFetch && m_qsoCount != 0) || count.toInt() > 0) {
                finishFetch(QStringLiteral("QRZ devolvió ADIF (%1 bytes, %2 IDs), pero no se pudo interpretar")
                                .arg(adifBytes.size())
                                .arg(logIds.size()));
                return;
            }
            finishFetch();
            return;
        }

        for (const QVariant &value : page) {
            const QVariantMap record = value.toMap();
            const quint64 id = recordLogId(record);
            if (id == 0) {
                finishFetch(QStringLiteral("QRZ devolvió un QSO sin identificador"));
                return;
            }
            m_fetchMaxLogId = std::max(m_fetchMaxLogId, id);
            bool duplicate = false;
            for (QVariantMap &existing : m_fetchRecords) {
                if (recordLogId(existing) == id) {
                    existing = record;
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate)
                m_fetchRecords.append(record);
        }

        if (page.size() >= QrzPageSize) {
            if (m_fetchMaxLogId < m_fetchAfterLogId) {
                finishFetch(QStringLiteral("No se pudo avanzar por el logbook QRZ"));
                return;
            }
            m_fetchAfterLogId = m_fetchMaxLogId + 1;
            fetchPage();
            return;
        }
        finishFetch();
    });
}

void QrzLogbookController::finishFetch(const QString &error)
{
    if (error.isEmpty()) {
        std::sort(m_fetchRecords.begin(), m_fetchRecords.end(),
                  [](const QVariantMap &left, const QVariantMap &right) {
            const QString leftKey = left.value(QStringLiteral("dateSort")).toString()
                                    + left.value(QStringLiteral("timeSort")).toString();
            const QString rightKey = right.value(QStringLiteral("dateSort")).toString()
                                     + right.value(QStringLiteral("timeSort")).toString();
            return leftKey > rightKey;
        });
        while (m_fetchRecords.size() > 3)
            m_fetchRecords.removeLast();
        m_recentQsos.clear();
        QStringList summaries;
        for (const QVariantMap &qso : m_fetchRecords) {
            m_recentQsos.append(qso);
            QString line = qso.value(QStringLiteral("call")).toString();
            const QString band = qso.value(QStringLiteral("band")).toString();
            const QString mode = qso.value(QStringLiteral("mode")).toString();
            const QString time = qso.value(QStringLiteral("time")).toString();
            if (!band.isEmpty())
                line += QStringLiteral(" · ") + band;
            if (!mode.isEmpty())
                line += QStringLiteral(" ") + mode;
            if (!time.isEmpty())
                line += QStringLiteral(" · ") + time;
            summaries.append(line);
        }
        m_recentSummary = summaries.join(QStringLiteral("   |   "));
        m_lastLogId = m_fetchMaxLogId;
        saveData();
        setStatus(QStringLiteral("QRZ actualizado %1")
                      .arg(QDateTime::currentDateTime().toString(QStringLiteral("dd/MM/yyyy HH:mm"))));
        emit dataChanged();
    } else {
        setStatus(error);
    }
    setLoading(false);
}

void QrzLogbookController::saveData()
{
    QSettings settings;
    settings.setValue(QStringLiteral("qrz/qsoCount"), m_qsoCount);
    settings.setValue(QStringLiteral("qrz/confirmedCount"), m_confirmedCount);
    settings.setValue(QStringLiteral("qrz/dxccCount"), m_dxccCount);
    settings.setValue(QStringLiteral("qrz/lastLogId"), QVariant::fromValue(m_lastLogId));
    settings.setValue(QStringLiteral("qrz/recentQsos"),
                      QJsonDocument::fromVariant(m_recentQsos).toJson(QJsonDocument::Compact));
}

QrzLogbookController::Fields QrzLogbookController::parseResponse(const QByteArray &body)
{
    QUrlQuery query(QString::fromUtf8(body).trimmed());
    Fields result;
    for (const auto &item : query.queryItems(QUrl::FullyDecoded))
        result.append(qMakePair(item.first, item.second));
    return result;
}

QString QrzLogbookController::field(const Fields &fields,
                                    const QStringList &names)
{
    QStringList normalizedNames;
    normalizedNames.reserve(names.size());
    for (const QString &name : names)
        normalizedNames.append(normalizeName(name));
    for (const auto &item : fields) {
        if (normalizedNames.contains(normalizeName(item.first)))
            return item.second.trimmed();
    }
    return {};
}

QVariantList QrzLogbookController::parseAdif(const QByteArray &adif,
                                             const QStringList &logIds)
{
    QVariantList records;
    QVariantMap current;
    int position = 0;
    int sequentialLogId = 0;

    auto finishRecord = [&]() {
        const QString call = current.value(QStringLiteral("call")).toString().trimmed();
        if (call.isEmpty()) {
            current.clear();
            return;
        }
        if (current.value(QStringLiteral("logId")).toULongLong() == 0
            && sequentialLogId < logIds.size()) {
            bool ok = false;
            const quint64 id = logIds.at(sequentialLogId).toULongLong(&ok);
            if (ok)
                current.insert(QStringLiteral("logId"), QVariant::fromValue(id));
        }
        ++sequentialLogId;
        const QString date = current.value(QStringLiteral("qsoDate")).toString();
        current.insert(QStringLiteral("dateSort"), date);
        current.insert(QStringLiteral("date"), date);
        current.insert(QStringLiteral("timeSort"), current.value(QStringLiteral("timeRaw")));
        current.insert(QStringLiteral("time"), current.value(QStringLiteral("timeRaw")).toString().left(4));
        QString time = current.value(QStringLiteral("time")).toString();
        if (time.size() == 4)
            time.insert(2, QLatin1Char(':'));
        else if (time.size() == 2)
            time += QStringLiteral(":00");
        current.insert(QStringLiteral("time"), time);
        const QDate parsedDate = QDate::fromString(date, QStringLiteral("yyyyMMdd"));
        if (parsedDate.isValid())
            current.insert(QStringLiteral("date"), parsedDate.toString(QStringLiteral("dd/MM")));
        records.append(current);
        current.clear();
    };

    while (position < adif.size()) {
        const int start = adif.indexOf('<', position);
        if (start < 0)
            break;
        const int end = adif.indexOf('>', start + 1);
        if (end < 0)
            break;
        const QByteArray header = adif.mid(start + 1, end - start - 1).trimmed();
        const QList<QByteArray> parts = header.split(':');
        const QString name = QString::fromLatin1(parts.value(0)).toLower();
        position = end + 1;
        if (name == QStringLiteral("eor")) {
            finishRecord();
            continue;
        }
        if (name == QStringLiteral("eoh") || parts.size() < 2)
            continue;
        bool ok = false;
        const int length = parts.at(1).toInt(&ok);
        if (!ok || length < 0 || position + length > adif.size())
            continue;
        const QString value = QString::fromUtf8(adif.mid(position, length)).trimmed();
        position += length;

        if (name == QStringLiteral("call"))
            current.insert(QStringLiteral("call"), value);
        else if (name == QStringLiteral("band"))
            current.insert(QStringLiteral("band"), value);
        else if (name == QStringLiteral("mode"))
            current.insert(QStringLiteral("mode"), value);
        else if (name == QStringLiteral("qso_date"))
            current.insert(QStringLiteral("qsoDate"), value);
        else if (name == QStringLiteral("time_on"))
            current.insert(QStringLiteral("timeRaw"), value);
        else if (name == QStringLiteral("app_qrzlog_logid")) {
            bool idOk = false;
            const quint64 id = value.toULongLong(&idOk);
            if (idOk)
                current.insert(QStringLiteral("logId"), QVariant::fromValue(id));
        }
    }
    if (!current.isEmpty())
        finishRecord();
    return records;
}

QString QrzLogbookController::normalizeName(const QString &name)
{
    QString normalized;
    normalized.reserve(name.size());
    for (const QChar character : name) {
        if (character.isLetterOrNumber())
            normalized.append(character.toLower());
    }
    return normalized;
}
