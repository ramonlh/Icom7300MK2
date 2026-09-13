// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include <QFile>
#include <QJsonObject>
#include <QObject>
#include <QSerialPort>
#include <QTimer>

// One read-only acquisition session, independent of subscriber lifetimes.
class SerialSource final : public QObject {
    Q_OBJECT
public:
    explicit SerialSource(QObject* parent = nullptr);
    void start(const QString& port, int seconds, const QString& capturePath = {});
    void stop();
    QJsonObject snapshot() const;
signals:
    void message(const QJsonObject& object);
private:
    void finish(const QString& status, const QString& error = {});
    void stats();
    QSerialPort port_;
    QFile capture_;
    bool captureRequested_ = false;
    qint64 capturedBytes_ = 0;
    QTimer statsTimer_, stopTimer_;
    qdock::Parser parser_;
    QString session_, status_ = "not_started", error_;
    quint64 sequence_ = 0;
    qint64 bytes_ = 0;
    qsizetype diagnosticRxBytes_ = 0;
};
