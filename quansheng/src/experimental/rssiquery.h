// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include <cstdint>
#include <vector>

namespace qdock::experimental {
struct RssiReading {
    std::uint16_t raw = 0;
    std::uint8_t noise = 0;
    std::uint8_t glitch = 0;
};
std::vector<std::uint8_t> makeGetRssiFrame();
bool decodeRssiInfo(const Event& event, RssiReading& reading);
int rssiDbmUncorrected(std::uint16_t raw);
}
