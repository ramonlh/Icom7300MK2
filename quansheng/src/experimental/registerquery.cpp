// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/registerquery.h"
#include <stdexcept>

namespace qdock::experimental {
namespace {
constexpr std::uint8_t key[] = {0x16,0x6c,0x14,0xe6,0x2e,0x91,0x0d,0x40,
                               0x21,0x35,0xd5,0x40,0x13,0x03,0xe9,0x80};
}

std::vector<std::uint8_t> makeReadRegistersFrame(const std::vector<std::uint16_t>& addresses) {
    if (addresses.empty() || addresses.size() > 50)
        throw std::invalid_argument("ReadRegisters requiere entre 1 y 50 direcciones");
    std::vector<std::uint8_t> payload{0x51, 0x08, 0x00, 0x00,
                                      static_cast<std::uint8_t>(addresses.size()), 0x00};
    for (const auto address : addresses) {
        if (address > 0x7f)
            throw std::invalid_argument("dirección BK4819 fuera de 0x00-0x7F");
        payload.push_back(static_cast<std::uint8_t>(address));
        payload.push_back(0x00);
    }
    const auto parameterSize = static_cast<std::uint16_t>(payload.size() - 4);
    payload[2] = static_cast<std::uint8_t>(parameterSize);
    payload[3] = static_cast<std::uint8_t>(parameterSize >> 8);
    const auto crc = crc16(payload);
    std::vector<std::uint8_t> frame{0xab, 0xcd,
                                    static_cast<std::uint8_t>(payload.size()),
                                    static_cast<std::uint8_t>(payload.size() >> 8)};
    for (std::size_t i = 0; i < payload.size(); ++i)
        frame.push_back(payload[i] ^ key[i % 16]);
    frame.push_back(static_cast<std::uint8_t>(crc) ^ key[payload.size() % 16]);
    frame.push_back(static_cast<std::uint8_t>(crc >> 8) ^ key[(payload.size() + 1) % 16]);
    frame.push_back(0xdc);
    frame.push_back(0xba);
    return frame;
}

bool decodeRegisterInfo(const Event& event, RegisterReading& reading) {
    if (event.kind != Event::Kind::Packet || event.data.size() != 8
        || event.data[0] != 0x51 || event.data[1] != 0x09
        || event.data[2] != 0x04 || event.data[3] != 0x00)
        return false;
    reading.address = event.data[4] | (static_cast<std::uint16_t>(event.data[5]) << 8);
    reading.value = event.data[6] | (static_cast<std::uint16_t>(event.data[7]) << 8);
    return reading.address <= 0x7f;
}

Register30State decodeRegister30(std::uint16_t value) {
    return {bool(value & 0x8000), bool(value & 0x0200), bool(value & 0x0100),
            bool(value & 0x0008), bool(value & 0x0004), bool(value & 0x0002),
            bool(value & 0x0001), std::uint8_t((value >> 10) & 0x0f),
            std::uint8_t((value >> 4) & 0x0f)};
}

Register7EState decodeRegister7E(std::uint16_t value) {
    int gainIndex = (value >> 12) & 0x07;
    if (gainIndex & 0x04) gainIndex -= 8;
    return {bool(value & 0x8000), gainIndex, std::uint8_t((value >> 5) & 0x7f),
            std::uint8_t((value >> 3) & 0x07), std::uint8_t(value & 0x07)};
}

bool afcEnabledFromRegister73(std::uint16_t value) {
    return (value & 0x0010) == 0;
}
}
