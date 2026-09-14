// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/eepromquery.h"
#include <cassert>
#include <stdexcept>

int main() {
    const auto hello = qdock::experimental::makeStartEepromSessionFrame(0x78563412);
    qdock::Parser helloParser;
    const auto helloEvents = helloParser.feed(hello.data(), hello.size());
    assert(helloEvents.size() == 1);
    assert(helloEvents[0].data == std::vector<std::uint8_t>({
        0x14, 0x05, 0x04, 0x00, 0x12, 0x34, 0x56, 0x78}));
    qdock::Event version{};
    version.kind = qdock::Event::Kind::Packet;
    version.data = {0x15, 0x05, 0x04, 0x00, 'T', 'E', 'S', 'T'};
    assert(qdock::experimental::isEepromSessionInfo(version));

    const auto frame = qdock::experimental::makeReadEepromFrame(0x1234, 4, 0x78563412);
    qdock::Parser parser;
    const auto events = parser.feed(frame.data(), frame.size());
    assert(events.size() == 1);
    assert(events[0].data == std::vector<std::uint8_t>({
        0x1b, 0x05, 0x08, 0x00, 0x34, 0x12, 0x04, 0x00,
        0x12, 0x34, 0x56, 0x78}));

    qdock::Event reply{};
    reply.kind = qdock::Event::Kind::Packet;
    reply.data = {0x1c, 0x05, 0x08, 0x00, 0x34, 0x12, 0x04, 0x00,
                  0xde, 0xad, 0xbe, 0xef};
    qdock::experimental::EepromReading reading;
    assert(qdock::experimental::decodeEepromInfo(reply, reading));
    assert(reading.offset == 0x1234);
    assert(reading.data == std::vector<std::uint8_t>({0xde, 0xad, 0xbe, 0xef}));

    qdock::experimental::EepromChannel channel;
    assert(qdock::experimental::decodeEepromChannel(
        {0x4c,0x48,0xde,0x00, 0x60,0xea,0x00,0x00,
         0x00,0x0b,0x10,0x02, 0x08,0x00,0x02,0x00}, channel));
    assert(channel.rxFrequencyHz == 145675000);
    assert(channel.txOffsetHz == 600000);
    assert(channel.txFrequencyHz == 145075000);
    assert(channel.modulation == 0 && channel.offsetDirection == 2);
    assert(channel.power == 2 && !channel.narrow);
    assert(channel.rxCodeType == 0 && channel.txCodeType == 1 && channel.txCode == 11);
    assert(channel.stepIndex == 2 && channel.scrambler == 0);

    reply.data[2] = 0x07;
    assert(!qdock::experimental::decodeEepromInfo(reply, reading));
    bool rejected = false;
    try { qdock::experimental::makeReadEepromFrame(0x1ff0, 32, 0); }
    catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
}
