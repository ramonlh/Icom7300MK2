// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/eepromquery.h"
#include <stdexcept>

namespace qdock::experimental {
namespace {
constexpr std::uint8_t key[] = {0x16,0x6c,0x14,0xe6,0x2e,0x91,0x0d,0x40,
                                0x21,0x35,0xd5,0x40,0x13,0x03,0xe9,0x80};

std::vector<std::uint8_t> makeFrame(const std::vector<std::uint8_t>& payload) {
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
}

std::vector<std::uint8_t> makeStartEepromSessionFrame(std::uint32_t sessionId) {
    return makeFrame({0x14, 0x05, 0x04, 0x00,
                      static_cast<std::uint8_t>(sessionId),
                      static_cast<std::uint8_t>(sessionId >> 8),
                      static_cast<std::uint8_t>(sessionId >> 16),
                      static_cast<std::uint8_t>(sessionId >> 24)});
}

bool isEepromSessionInfo(const Event& event) {
    return event.kind == Event::Kind::Packet && event.data.size() >= 8
            && event.data[0] == 0x15 && event.data[1] == 0x05;
}

std::vector<std::uint8_t> makeReadEepromFrame(std::uint16_t offset,
                                               std::uint8_t size,
                                               std::uint32_t sessionId) {
    if (size == 0 || size > 128)
        throw std::invalid_argument("ReadEeprom requiere entre 1 y 128 bytes");
    if (static_cast<std::uint32_t>(offset) + size > 0x2000)
        throw std::invalid_argument("lectura EEPROM fuera de 0x0000-0x1FFF");

    std::vector<std::uint8_t> payload{
        0x1b, 0x05, 0x08, 0x00,
        static_cast<std::uint8_t>(offset), static_cast<std::uint8_t>(offset >> 8),
        size, 0x00,
        static_cast<std::uint8_t>(sessionId),
        static_cast<std::uint8_t>(sessionId >> 8),
        static_cast<std::uint8_t>(sessionId >> 16),
        static_cast<std::uint8_t>(sessionId >> 24)};
    return makeFrame(payload);
}

bool decodeEepromInfo(const Event& event, EepromReading& reading) {
    if (event.kind != Event::Kind::Packet || event.data.size() < 9
        || event.data[0] != 0x1c || event.data[1] != 0x05)
        return false;
    const std::uint16_t parameterSize = event.data[2]
            | (static_cast<std::uint16_t>(event.data[3]) << 8);
    const std::uint8_t size = event.data[6];
    if (size == 0 || size > 128 || parameterSize != size + 4
        || event.data.size() != static_cast<std::size_t>(size) + 8)
        return false;
    reading.offset = event.data[4]
            | (static_cast<std::uint16_t>(event.data[5]) << 8);
    if (static_cast<std::uint32_t>(reading.offset) + size > 0x2000)
        return false;
    reading.data.assign(event.data.begin() + 8, event.data.end());
    return true;
}

bool decodeEepromChannel(const std::vector<std::uint8_t>& data, EepromChannel& channel) {
    if (data.size() != 16)
        return false;
    auto le32 = [&](std::size_t at) {
        return static_cast<std::uint32_t>(data[at])
            | (static_cast<std::uint32_t>(data[at + 1]) << 8)
            | (static_cast<std::uint32_t>(data[at + 2]) << 16)
            | (static_cast<std::uint32_t>(data[at + 3]) << 24);
    };
    channel.rxFrequencyHz = le32(0) * 10U;
    channel.txOffsetHz = le32(4) * 10U;
    channel.rxCode = data[8];
    channel.txCode = data[9];
    channel.rxCodeType = data[10] & 0x0f;
    channel.txCodeType = data[10] >> 4;
    channel.offsetDirection = data[11] & 0x0f;
    channel.modulation = data[11] >> 4;
    channel.busyChannelLock = (data[12] & 0x10) != 0;
    channel.power = (data[12] >> 2) & 0x03;
    channel.narrow = (data[12] & 0x02) != 0;
    channel.reverse = (data[12] & 0x01) != 0;
    channel.dtmfPttId = (data[13] >> 1) & 0x07;
    channel.dtmfDecode = (data[13] & 0x01) != 0;
    channel.stepIndex = data[14];
    channel.scrambler = data[15];
    channel.txFrequencyHz = channel.rxFrequencyHz;
    if (channel.offsetDirection == 1)
        channel.txFrequencyHz += channel.txOffsetHz;
    else if (channel.offsetDirection == 2)
        channel.txFrequencyHz = channel.rxFrequencyHz >= channel.txOffsetHz
            ? channel.rxFrequencyHz - channel.txOffsetHz : 0;
    return true;
}

} // namespace qdock::experimental
