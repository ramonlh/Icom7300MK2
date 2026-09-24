// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/keycontrol.h"
#include "core/tones.h"
#include <cassert>
#include <stdexcept>

int main() {
    assert(qdock::toneLabel(1, 0) == "67.0 Hz");
    assert(qdock::toneLabel(1, 8) == "88.5 Hz");
    assert(qdock::toneLabel(1, 49) == "254.1 Hz");
    assert(qdock::toneLabel(2, 0) == "D023N");
    assert(qdock::toneLabel(3, 103) == "D754I");
    assert(qdock::toneLabel(0, 0) == "OFF");
    assert(!qdock::validTone(1, -1) && !qdock::validTone(1, 50));
    assert(!qdock::validTone(2, 104) && !qdock::validTone(3, 104));
    assert(!qdock::validTone(0, 1) && !qdock::validTone(4, 0));
    const auto frames = qdock::experimental::makeFrequencyEntryFrames(145675000);
    assert(frames.size() == 6);
    const std::uint8_t expectedDigits[] = {1, 4, 5, 6, 7, 5};
    for (std::size_t index = 0; index < frames.size(); ++index) {
        qdock::Parser parser;
        const auto& frame = frames[index];
        const auto events = parser.feed(frame.data(), frame.size());
        assert(events.size() == 1 && events[0].data.size() == 6);
        assert(events[0].data[0] == 0x01 && events[0].data[1] == 0x08);
        assert(events[0].data[2] == 0x02 && events[0].data[3] == 0x00);
        assert(events[0].data[4] == expectedDigits[index] && events[0].data[5] == 0x00);
    }
    const auto lowFrames = qdock::experimental::makeFrequencyEntryFrames(18000000);
    const std::uint8_t expectedLowDigits[] = {0, 1, 8, 0, 0, 0};
    assert(lowFrames.size() == 6);
    for (std::size_t index = 0; index < lowFrames.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(lowFrames[index].data(), lowFrames[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedLowDigits[index]);
    }
    assert(qdock::experimental::makeKeyPressFrame(19).size() == 14);
    bool rejected = false;
    try { qdock::experimental::makeFrequencyEntryFrames(1000000); }
    catch (const std::invalid_argument&) { rejected = true; }
    assert(rejected);
    const auto vfo = qdock::experimental::makeVfoSwitchFrames();
    assert(vfo.size() == 4);
    for (const auto& frame : vfo) {
        qdock::Parser parser;
        const auto events = parser.feed(frame.data(), frame.size());
        assert(events.size() == 1 && events[0].data.size() == 6);
    }
    const auto mode = qdock::experimental::makeModeChangeFrames(4, false);
    const std::uint8_t expectedModeKeys[] = {10, 19, 1, 19, 3, 19, 10, 19,
                                              4, 19, 10, 19, 13, 19};
    assert(mode.size() == 14);
    for (std::size_t index = 0; index < mode.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(mode[index].data(), mode[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedModeKeys[index]);
    }
    const auto dualWatch = qdock::experimental::makeDualWatchFrames(true);
    const std::uint8_t expectedDualWatchKeys[] = {10,19, 5,19, 9,19, 10,19,
                                                   1,19, 10,19, 13,19};
    assert(dualWatch.size() == 14);
    for (std::size_t index = 0; index < dualWatch.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(dualWatch[index].data(), dualWatch[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedDualWatchKeys[index]);
    }
    const auto squelch = qdock::experimental::makeSquelchFrames(7);
    const std::uint8_t expectedSquelchKeys[] = {10,19, 6,19, 1,19, 10,19,
                                                7,19, 10,19, 13,19};
    assert(squelch.size() == 14);
    for (std::size_t index = 0; index < squelch.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(squelch[index].data(), squelch[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedSquelchKeys[index]);
    }
}
