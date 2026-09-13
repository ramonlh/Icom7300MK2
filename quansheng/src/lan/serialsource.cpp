// SPDX-License-Identifier: GPL-2.0-only
#include "lan/serialsource.h"
#include "eventjson.h"
#include "serial/reader.h"
#include <QDateTime>
#include <QUuid>

SerialSource::SerialSource(QObject* parent) : QObject(parent) {
    connect(&statsTimer_, &QTimer::timeout, this, &SerialSource::stats);
    stopTimer_.setSingleShot(true);
    connect(&stopTimer_, &QTimer::timeout, this, [this] { finish("ended"); });
    connect(&port_, &QSerialPort::readyRead, this, [this] {
        if (status_ != "listening") return;
        const auto data = port_.readAll();
        bytes_ += data.size();
        if (diagnosticRxBytes_ < 256) {
            const auto sample = data.left(256 - diagnosticRxBytes_);
            diagnosticRxBytes_ += sample.size();
            qInfo().noquote() << "Quansheng serie RX muestra" << sample.size()
                              << "bytes:" << sample.toHex(' ');
        }
        if (capture_.isOpen()) {
            const auto written = capture_.write(data);
            if (written > 0) capturedBytes_ += written;
            if (written != data.size() || !capture_.flush()) {
                finish("error", "Error guardando captura: " + capture_.errorString());
                return;
            }
        }
        for (const auto& event : parser_.feed(
                 reinterpret_cast<const std::uint8_t*>(data.constData()), data.size())) {
            emit message({{"message", "event"}, {"source", "serial"},
                          {"session", session_}, {"sequence", QString::number(++sequence_)},
                          {"observedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
                          {"quality", "candidate"}, {"decoder", "qdock-probe/0.1.0"},
                          {"event", qdock::eventJson(event)}});
        }
    });
    connect(&port_, &QSerialPort::errorOccurred, this, [this](auto error) {
        if (error != QSerialPort::NoError && status_ == "listening")
            finish("error", port_.errorString());
    });
}

void SerialSource::start(const QString& port, int seconds, const QString& capturePath) {
    if (status_ != "not_started") return;
    session_ = QUuid::createUuid().toString(QUuid::WithoutBraces);
    captureRequested_ = !capturePath.isEmpty();
    if (captureRequested_) {
        capture_.setFileName(capturePath);
        if (!capture_.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
            finish("error", "No se puede crear captura nueva: " + capture_.errorString());
            return;
        }
    }
    QString error;
    if (!qdock::openReadOnly(port_, port, error)) {
        finish("error", error);
        return;
    }
    status_ = "listening";
    emit message(snapshot());
    statsTimer_.start(1000);
    stopTimer_.start(seconds * 1000);
}

void SerialSource::stop() { if (status_ == "listening") finish("ended"); }

QJsonObject SerialSource::snapshot() const {
    return {{"message", "source_status"}, {"source", "serial"}, {"session", session_},
            {"status", status_}, {"error", error_}, {"portOpen", port_.isOpen()},
            {"captureRequested", captureRequested_}, {"captureOpen", capture_.isOpen()},
            {"nextSequence", QString::number(sequence_ + 1)}};
}

void SerialSource::stats() {
    emit message({{"message", "stats"}, {"session", session_},
                  {"bytes", QString::number(bytes_)}, {"events", QString::number(sequence_)},
                  {"capturedBytes", QString::number(capturedBytes_)},
                  {"discarded", QString::number(parser_.discarded())},
                  {"pending", QString::number(parser_.pending())}});
}

void SerialSource::finish(const QString& status, const QString& error) {
    status_ = status;
    error_ = error;
    statsTimer_.stop();
    stopTimer_.stop();
    port_.close();
    if (capture_.isOpen()) {
        if (!capture_.flush()) {
            status_ = "error";
            if (!error_.isEmpty()) error_ += "; ";
            error_ += "Error al finalizar captura: " + capture_.errorString();
        }
        capture_.close();
    }
    stats();
    emit message(snapshot());
}
