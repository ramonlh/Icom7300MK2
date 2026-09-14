// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include <cstdint>
#include <vector>

namespace qdock::experimental {
struct RegisterReading {
    std::uint16_t address = 0;
    std::uint16_t value = 0;
};

struct Register30State {
    bool vcoCalibration, afDac, discriminator, paGain, micAdc, txDsp, rxDsp;
    std::uint8_t rxLink, pllVco;
};

struct Register7EState {
    bool fixedAgc;
    int gainIndex;
    std::uint8_t signalStrength, txDcFilter, rxDcFilter;
};

std::vector<std::uint8_t> makeReadRegistersFrame(const std::vector<std::uint16_t>& addresses);
bool decodeRegisterInfo(const Event& event, RegisterReading& reading);
Register30State decodeRegister30(std::uint16_t value);
Register7EState decodeRegister7E(std::uint16_t value);
bool afcEnabledFromRegister73(std::uint16_t value);
}
