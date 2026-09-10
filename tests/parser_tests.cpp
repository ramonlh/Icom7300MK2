// SPDX-License-Identifier: GPL-2.0-only
#include "core/parser.h"
#include <cstdlib>
#include <iostream>
#include <string>

void check(bool ok, const char* message) {
    if (!ok) { std::cerr << message << '\n'; std::exit(1); }
}
int main() {
    const std::string known = "123456789";
    check(qdock::crc16({known.begin(), known.end()}) == 0x31c3, "CRC-16/XMODEM vector");
    // Hello command fixture from upstream algorithm: command 0514, 4 params, 12345678.
    const std::vector<std::uint8_t> frame = {0xab,0xcd,8,0,2,0x69,0x10,0xe6,0x56,0xc7,0x39,0x52,0x04,0xa8,0xdc,0xba};
    for (std::size_t split = 0; split <= frame.size(); ++split) {
        qdock::Parser p;
        auto first = p.feed(frame.data(), split);
        auto second = p.feed(frame.data()+split, frame.size()-split);
        first.insert(first.end(), second.begin(), second.end());
        check(first.size() == 1 && p.pending() == 0, "fragmented frame");
        check(first[0].data == std::vector<std::uint8_t>({0x14,5,4,0,0x78,0x56,0x34,0x12}), "XOR decode");
        check(first[0].crcMatches, "fixture CRC");
    }
    qdock::Parser p;
    const std::vector<std::uint8_t> ui = {0x99,0xab,0xb5,6,2,0,0,200,0xb5,0,0,1,0,3,'1','4','5'};
    std::vector<qdock::Event> events;
    for (auto b : ui) { auto e = p.feed(&b, 1); events.insert(events.end(), e.begin(), e.end()); }
    check(events.size() == 2 && events[0].data.empty() && events[0].field == 200, "UI type 6 has no payload");
    check(events[1].data == std::vector<std::uint8_t>({'1','4','5'}), "UI text");
    check(p.discarded() == 2, "noise accounting");
    auto bad = frame; bad[12] ^= 1;
    check(!p.feed(bad.data(), bad.size())[0].crcMatches, "CRC mismatch reported, retained like upstream");
    bad = frame; bad.back() = 0;
    bad.insert(bad.end(), frame.begin(), frame.end());
    check(p.feed(bad.data(), bad.size()).size() == 1, "resync after bad trailer");
    const std::uint8_t zero[] = {0xab,0xcd,0,0};
    p.feed(zero, sizeof zero);
    check(p.pending() == 0, "zero length rejected");
    p.feed(frame.data(), frame.size()-1);
    check(p.pending() == frame.size()-1, "truncation retained");
    qdock::Parser noise;
    std::vector<std::uint8_t> garbage(1000000, 0x42);
    check(noise.feed(garbage.data(), garbage.size()).empty() && noise.pending() == 0, "bounded noise");
    std::cout << "Parser checks passed\n";
}
