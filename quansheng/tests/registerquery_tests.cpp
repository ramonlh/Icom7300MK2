// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/registerquery.h"
#include <cassert>
#include <stdexcept>

int main() {
    const auto frame = qdock::experimental::makeReadRegistersFrame({0x00, 0x38, 0x7f});
    assert(frame.size() == 20);
    qdock::Parser parser;
    const auto events = parser.feed(frame.data(), frame.size());
    assert(events.size() == 1);
    assert(events[0].data == std::vector<std::uint8_t>({0x51, 0x08, 0x08, 0x00,
                                                        0x03, 0x00, 0x00, 0x00,
                                                        0x38, 0x00, 0x7f, 0x00}));
    qdock::Event reply{};
    reply.kind = qdock::Event::Kind::Packet;
    reply.data = {0x51, 0x09, 0x04, 0x00, 0x38, 0x00, 0x34, 0x12};
    qdock::experimental::RegisterReading reading;
    assert(qdock::experimental::decodeRegisterInfo(reply, reading));
    assert(reading.address == 0x38 && reading.value == 0x1234);
    const auto blocks = qdock::experimental::decodeRegister30(0xbff1);
    assert(blocks.vcoCalibration && blocks.rxLink == 15 && blocks.afDac);
    assert(blocks.discriminator && blocks.pllVco == 15 && blocks.rxDsp);
    assert(!blocks.paGain && !blocks.micAdc && !blocks.txDsp);
    const auto agc = qdock::experimental::decodeRegister7E(0x302e);
    assert(!agc.fixedAgc && agc.gainIndex == 3 && agc.signalStrength == 1);
    assert(agc.txDcFilter == 5 && agc.rxDcFilter == 6);
    assert(qdock::experimental::afcEnabledFromRegister73(0x4682));
    bool rejected = false;
    try { qdock::experimental::makeReadRegistersFrame(std::vector<std::uint16_t>(51, 0)); }
    catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
}
