// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include "core/displaymodel.h"
#include <QJsonObject>
namespace qdock {
QJsonObject eventJson(const Event& event);
QJsonObject displayStateJson(const DisplayModel& model);
}
