// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <QByteArray>
#include <QString>
#include <functional>
class QSerialPort;
namespace qdock {
bool openReadOnly(QSerialPort& port, const QString& name, QString& error);
bool openRssiQuery(QSerialPort& port, const QString& name, QString& error);
int readSerial(const QString& port, int seconds,
               const std::function<bool(const QByteArray&)>& receive);
void listPorts();
}
