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
    const auto tuned = qdock::experimental::makeFrequencyChangeFrames(145600120, true);
    const std::uint8_t expectedTuneKeys[] = {
        10,19, 1,19, 10,19, 0,19, 10,19, 13,19,
        1,19, 4,19, 5,19, 6,19, 0,19, 0,19,
        11,19, 11,19, 11,19, 11,19, 11,19, 11,19,
        11,19, 11,19, 11,19, 11,19, 11,19, 11,19
    };
    assert(tuned.size() == sizeof(expectedTuneKeys) / sizeof(expectedTuneKeys[0]));
    for (std::size_t index = 0; index < tuned.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(tuned[index].data(), tuned[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedTuneKeys[index]);
    }
    const auto fineUp = qdock::experimental::makeFrequencyStepFrames(true, false);
    const auto fineDown = qdock::experimental::makeFrequencyStepFrames(false, false);
    assert(fineUp.size() == 2 && fineDown.size() == 2);
    for (const auto& check : {std::pair{fineUp[0], std::uint8_t(11)},
                              std::pair{fineDown[0], std::uint8_t(12)}}) {
        qdock::Parser parser;
        const auto events = parser.feed(check.first.data(), check.first.size());
        assert(events.size() == 1 && events[0].data[4] == check.second);
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
    const auto vox = qdock::experimental::makeVoxFrames(5);
    const std::uint8_t expectedVoxKeys[] = {10,19, 5,19, 7,19, 10,19,
                                            5,19, 10,19, 13,19};
    assert(vox.size() == 14);
    for (std::size_t index = 0; index < vox.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(vox[index].data(), vox[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedVoxKeys[index]);
    }
    const auto txTimeout = qdock::experimental::makeMenuSettingFrames(29, 3);
    const std::uint8_t expectedTxTimeoutKeys[] = {10,19, 2,19, 9,19, 10,19,
                                                  3,19, 10,19, 13,19};
    assert(txTimeout.size() == 14);
    for (std::size_t index = 0; index < txTimeout.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(txTimeout[index].data(), txTimeout[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedTxTimeoutKeys[index]);
    }
    const auto step = qdock::experimental::makeMenuSettingFrames(1, 4);
    const std::uint8_t expectedStepKeys[] = {10,19, 1,19, 10,19,
                                             4,19, 10,19, 13,19};
    assert(step.size() == 12);
    for (std::size_t index = 0; index < step.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(step[index].data(), step[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedStepKeys[index]);
    }
    const auto repeaterOffset = qdock::experimental::makeMenuSettingFrames(8, 60000);
    const std::uint8_t expectedOffsetKeys[] = {10,19, 8,19, 10,19,
                                                0,19, 0,19, 0,19, 6,19, 0,19, 0,19,
                                                10,19, 13,19};
    assert(repeaterOffset.size() == sizeof(expectedOffsetKeys) / sizeof(expectedOffsetKeys[0]));
    for (std::size_t index = 0; index < repeaterOffset.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(repeaterOffset[index].data(), repeaterOffset[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedOffsetKeys[index]);
    }
    bool offsetRejected = false;
    try { qdock::experimental::makeMenuSettingFrames(8, 60001); }
    catch (const std::invalid_argument&) { offsetRejected = true; }
    assert(offsetRejected);
    const auto txTimeout15Min = qdock::experimental::makeMenuSettingFrames(29, 10);
    const std::uint8_t expectedTxTimeout15MinKeys[] = {10,19, 2,19, 9,19, 10,19,
                                                        1,19, 0,19, 10,19, 13,19};
    assert(txTimeout15Min.size() == 16);
    for (std::size_t index = 0; index < txTimeout15Min.size(); ++index) {
        qdock::Parser parser;
        const auto events = parser.feed(txTimeout15Min[index].data(), txTimeout15Min[index].size());
        assert(events.size() == 1 && events[0].data[4] == expectedTxTimeout15MinKeys[index]);
    }
}
