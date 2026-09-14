#include "experimental/rssiquery.h"
#include <cassert>

int main() {
    const auto frame = qdock::experimental::makeGetRssiFrame();
    assert(frame.size() == 12 && frame[0] == 0xab && frame[1] == 0xcd);
    qdock::Parser parser;
    const auto events = parser.feed(frame.data(), frame.size());
    assert(events.size() == 1 && events[0].data == std::vector<std::uint8_t>({0x27,0x05,0,0}));
    qdock::Event reply{qdock::Event::Kind::Packet};
    reply.data = {0x28,0x05,0x04,0x00,0xa4,0x00,0x52,0x06};
    qdock::experimental::RssiReading reading;
    assert(qdock::experimental::decodeRssiInfo(reply, reading));
    assert(reading.raw == 164 && reading.noise == 82 && reading.glitch == 6);
    assert(qdock::experimental::rssiDbmUncorrected(164) == -78);
    assert(qdock::experimental::rssiDbmUncorrected(345) == 12);
    reply.data[0] = 0x29;
    assert(!qdock::experimental::decodeRssiInfo(reply, reading));
}
