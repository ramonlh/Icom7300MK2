// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

namespace qdock {
struct Event {
    enum class Kind { Packet, Ui } kind;
    std::vector<std::uint8_t> data;
    std::uint8_t type = 0, val1 = 0, val2 = 0, val3 = 0, field = 0;
    bool crcMatches = false;
};
std::uint16_t crc16(const std::vector<std::uint8_t>& data);
class Parser {
public:
    // Protocol length is uint16; buffer never holds more than one maximum frame.
    std::vector<Event> feed(const std::uint8_t* data, std::size_t size);
    std::size_t pending() const { return buffer_.size(); }
    std::size_t discarded() const { return discarded_; }
private:
    std::vector<std::uint8_t> buffer_;
    std::size_t discarded_ = 0;
    void drain(std::vector<Event>& events);
};
}
