// SPDX-License-Identifier: GPL-2.0-only
// Protocol adapted from QuanshengDock Serial/Comms.cs, code by -nicsure- 2024.
#include "core/parser.h"
#include <utility>

namespace qdock {
namespace {
constexpr std::uint8_t key[] = {0x16,0x6c,0x14,0xe6,0x2e,0x91,0x0d,0x40,
                               0x21,0x35,0xd5,0x40,0x13,0x03,0xe9,0x80};
}
std::uint16_t crc16(const std::vector<std::uint8_t>& data) {
    std::uint16_t crc = 0;
    for (auto byte : data) {
        crc ^= static_cast<std::uint16_t>(byte) << 8;
        for (int i = 0; i < 8; ++i)
            crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1;
    }
    return crc;
}
std::vector<Event> Parser::feed(const std::uint8_t* data, std::size_t size) {
    std::vector<Event> events;
    for (std::size_t i = 0; i < size; ++i) {
        buffer_.push_back(data[i]);
        drain(events);
    }
    return events;
}
void Parser::drain(std::vector<Event>& events) {
    while (!buffer_.empty()) {
        auto reject = [this] { buffer_.erase(buffer_.begin()); ++discarded_; };
        if (buffer_[0] == 0xb5) {
            if (buffer_.size() < 6) return;
            const std::size_t size = 6 + (buffer_[1] == 6 ? 0 : buffer_[5]);
            if (buffer_.size() < size) return;
            Event e{};
            e.kind = Event::Kind::Ui;
            e.type = buffer_[1]; e.val1 = buffer_[2]; e.val2 = buffer_[3];
            e.val3 = buffer_[4]; e.field = buffer_[5];
            e.data.assign(buffer_.begin()+6, buffer_.begin()+size);
            events.push_back(std::move(e));
            buffer_.erase(buffer_.begin(), buffer_.begin()+size);
        } else if (buffer_[0] == 0xab) {
            if (buffer_.size() < 2) return;
            if (buffer_[1] != 0xcd) { reject(); continue; }
            if (buffer_.size() < 4) return;
            const std::size_t len = buffer_[2] | (buffer_[3] << 8);
            if (len < 4) { reject(); continue; }
            const auto size = len + 8;
            if (buffer_.size() < size) return;
            if (buffer_[size-2] != 0xdc || buffer_[size-1] != 0xba) {
                reject(); continue;
            }
            Event e{};
            e.kind = Event::Kind::Packet;
            for (std::size_t i = 0; i < len; ++i)
                e.data.push_back(buffer_[4+i] ^ key[i%16]);
            const auto received = (buffer_[4+len] ^ key[len%16]) |
                ((buffer_[5+len] ^ key[(len+1)%16]) << 8);
            e.crcMatches = received == crc16(e.data);
            events.push_back(std::move(e));
            buffer_.erase(buffer_.begin(), buffer_.begin()+size);
        } else reject();
    }
}
}
