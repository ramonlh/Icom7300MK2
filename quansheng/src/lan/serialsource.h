// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include "core/displaymodel.h"
#include <QFile>
#include <QJsonObject>
#include <QMap>
#include <QObject>
#include <QSerialPort>
#include <QTimer>

// One read-only acquisition session, independent of subscriber lifetimes.
class SerialSource final : public QObject {
    Q_OBJECT
public:
    explicit SerialSource(QObject* parent = nullptr);
    void start(const QString& port, int seconds, const QString& capturePath = {},
               bool allowRssiQuery = false, bool allowRegisterQuery = false,
               bool allowEepromQuery = false);
    QString requestEepromRead();
    bool eepromReadAvailable() const { return allowEepromQuery_; }
    void stop();
    QJsonObject snapshot() const;
    QJsonObject displaySnapshot() const;
signals:
    void message(const QJsonObject& object);
private:
    void finish(const QString& status, const QString& error = {});
    void stats();
    void requestDiagnosticRegisters();
    void sendNextEepromBlock();
    QSerialPort port_;
    QFile capture_;
    bool captureRequested_ = false;
    qint64 capturedBytes_ = 0;
    QTimer statsTimer_, stopTimer_, rssiTimer_, registerTimer_, diagnosticTimer_, eepromTimer_;
    qdock::Parser parser_;
    qdock::DisplayModel displayModel_;
    QString session_, status_ = "not_started", error_;
    quint64 sequence_ = 0;
    qint64 bytes_ = 0;
    qsizetype diagnosticRxBytes_ = 0;
    bool allowRssiQuery_ = false;
    bool allowRegisterQuery_ = false;
    bool allowEepromQuery_ = false;
    bool eepromBusy_ = false;
    bool eepromAwaitingSession_ = false;
    quint16 eepromOffset_ = 0;
    QByteArray eepromData_;
    QMap<int, int> registerCycle_;
    QMap<int, int> frequencyCycle_;
    QMap<int, int> latestFrequencyRegisters_;
};
