// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include <cstdint>
#include <vector>

namespace qdock::experimental {

struct EepromReading {
    std::uint16_t offset = 0;
    std::vector<std::uint8_t> data;
};

struct EepromChannel {
    std::uint32_t rxFrequencyHz = 0;
    std::uint32_t txOffsetHz = 0;
    std::uint32_t txFrequencyHz = 0;
    std::uint8_t rxCode = 0;
    std::uint8_t txCode = 0;
    std::uint8_t rxCodeType = 0;
    std::uint8_t txCodeType = 0;
    std::uint8_t modulation = 0;
    std::uint8_t offsetDirection = 0;
    std::uint8_t power = 0;
    bool narrow = false;
    bool reverse = false;
    bool busyChannelLock = false;
    bool dtmfDecode = false;
    std::uint8_t dtmfPttId = 0;
    std::uint8_t stepIndex = 0;
    std::uint8_t scrambler = 0;
};

std::vector<std::uint8_t> makeStartEepromSessionFrame(std::uint32_t sessionId);
bool isEepromSessionInfo(const Event& event);
// Builds only ReadEeprom 0x051B. The caller must supply the identifier of an
// already established radio session; this function never starts one.
std::vector<std::uint8_t> makeReadEepromFrame(std::uint16_t offset,
                                               std::uint8_t size,
                                               std::uint32_t sessionId);
bool decodeEepromInfo(const Event& event, EepromReading& reading);
// Decodes the 16-byte channel record used at EEPROM offsets channel * 16.
bool decodeEepromChannel(const std::vector<std::uint8_t>& data, EepromChannel& channel);

} // namespace qdock::experimental
