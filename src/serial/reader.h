// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <QByteArray>
#include <QString>
#include <functional>
namespace qdock {
int readSerial(const QString& port, int seconds,
               const std::function<bool(const QByteArray&)>& receive);
void listPorts();
}
