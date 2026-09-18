// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include "core/displaymodel.h"
#include <QFile>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QMap>
#include <QObject>
#include <QSerialPort>
#include <QTimer>

// Shared acquisition; optional controls have separate explicit permissions.
class SerialSource final : public QObject {
    Q_OBJECT
public:
    explicit SerialSource(QObject* parent = nullptr);
    void start(const QString& port, int seconds, const QString& capturePath = {},
               bool allowRssiQuery = false, bool allowRegisterQuery = false,
               bool allowEepromQuery = false, bool allowFrequencyControl = false,
               bool allowPtt = false, int pttMaxSeconds = 60);
    QString requestPtt(QObject* owner, const QString& action, const QString& id);
    void releasePtt(QObject* owner, const QString& reason);
    bool txControlAvailable() const { return allowPtt_ && status_ == "listening"; }
    QString requestEepromRead();
    QString requestFrequencyChange(quint32 frequencyHz);
    QString requestVfoSwitch();
    QString requestVfoModeToggle(const QString& targetVfo);
    QString requestMemoryStep(const QString& targetVfo, bool up);
    QString requestModeChange(const QString& targetVfo, const QString& mode);
    QString requestDualWatch(bool enabled);
    QString requestSquelch(int level);
    bool eepromReadAvailable() const { return allowEepromQuery_; }
    bool frequencyControlAvailable() const { return allowFrequencyControl_; }
    void stop();
    QJsonObject snapshot() const;
    QJsonObject displaySnapshot() const;
signals:
    void message(const QJsonObject& object);
private:
    void endPtt(const QString& reason);
    bool writePttKey(bool pressed);
    void finish(const QString& status, const QString& error = {});
    void stats();
    void requestDiagnosticRegisters();
    void requestInitialSquelchLevel();
    void sendNextEepromBlock();
    QSerialPort port_;
    QFile capture_;
    bool captureRequested_ = false;
    qint64 capturedBytes_ = 0;
    QTimer statsTimer_, stopTimer_, rssiTimer_, registerTimer_, diagnosticTimer_, eepromTimer_, frequencyTimer_;
    qdock::Parser parser_;
    qdock::DisplayModel displayModel_;
    QString session_, status_ = "not_started", error_;
    quint64 sequence_ = 0;
    qint64 bytes_ = 0;
    qsizetype diagnosticRxBytes_ = 0;
    bool allowRssiQuery_ = false;
    bool allowRegisterQuery_ = false;
    bool allowEepromQuery_ = false;
    bool allowFrequencyControl_ = false;
    bool frequencyBusy_ = false;
    bool transmitting_ = false;
    bool allowPtt_ = false;
    bool finishing_ = false;
    QObject* pttOwner_ = nullptr;
    QString pttId_;
    int pttMaxSeconds_ = 60;
    QTimer pttTimer_;
    QElapsedTimer pttLease_, pttDuration_, radioStateAge_;
    QVector<QByteArray> frequencyFrames_;
    QVector<QByteArray> vfoFrames_;
    bool vfoBusy_ = false;
    bool eepromBusy_ = false;
    bool eepromAwaitingSession_ = false;
    bool eepromSquelchOnly_ = false;
    quint16 eepromOffset_ = 0;
    QByteArray eepromData_;
    int squelchLevel_ = -1;
    QMap<int, int> registerCycle_;
    QMap<int, int> frequencyCycle_;
    QMap<int, int> latestFrequencyRegisters_;
};
