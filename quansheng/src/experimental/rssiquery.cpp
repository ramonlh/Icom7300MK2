// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/rssiquery.h"

namespace qdock::experimental {
namespace {
constexpr std::uint8_t key[] = {0x16,0x6c,0x14,0xe6,0x2e,0x91,0x0d,0x40,
                               0x21,0x35,0xd5,0x40,0x13,0x03,0xe9,0x80};
}

std::vector<std::uint8_t> makeGetRssiFrame() {
    const std::vector<std::uint8_t> payload{0x27, 0x05, 0x00, 0x00};
    const auto crc = crc16(payload);
    std::vector<std::uint8_t> frame{0xab, 0xcd, 0x04, 0x00};
    for (std::size_t i = 0; i < payload.size(); ++i)
        frame.push_back(payload[i] ^ key[i]);
    frame.push_back(static_cast<std::uint8_t>(crc) ^ key[payload.size()]);
    frame.push_back(static_cast<std::uint8_t>(crc >> 8) ^ key[payload.size() + 1]);
    frame.push_back(0xdc); frame.push_back(0xba);
    return frame;
}

bool decodeRssiInfo(const Event& event, RssiReading& reading) {
    if (event.kind != Event::Kind::Packet || event.data.size() != 8
        || event.data[0] != 0x28 || event.data[1] != 0x05
        || event.data[2] != 0x04 || event.data[3] != 0x00)
        return false;
    reading.raw = event.data[4] | (static_cast<std::uint16_t>(event.data[5]) << 8);
    reading.noise = event.data[6] & 0x7f;
    reading.glitch = event.data[7];
    return reading.raw <= 0x01ff;
}

int rssiDbmUncorrected(std::uint16_t raw) {
    return static_cast<int>(raw / 2) - 160;
}
}
