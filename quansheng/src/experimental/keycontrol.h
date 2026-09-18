// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include <cstdint>
#include <vector>

namespace qdock::experimental {

// Builds the upstream CMD_0801 key-press frame. A value of 19 releases the key.
std::vector<std::uint8_t> makeKeyPressFrame(std::uint8_t key);
std::vector<std::vector<std::uint8_t>> makeVfoSwitchFrames();
std::vector<std::vector<std::uint8_t>> makeVfoModeToggleFrames(bool selectOther);
std::vector<std::vector<std::uint8_t>> makeMemoryStepFrames(bool up, bool selectOther);
std::vector<std::vector<std::uint8_t>> makeModeChangeFrames(std::uint8_t mode, bool selectOther);
std::vector<std::vector<std::uint8_t>> makeDualWatchFrames(bool enabled);
std::vector<std::vector<std::uint8_t>> makeSquelchFrames(std::uint8_t level);

// Converts a VFO frequency in Hz to the six-digit keypad entry used by the
// stock firmware (frequency in kHz), returning one frame per digit. The
// caller schedules a release frame between digits.
std::vector<std::vector<std::uint8_t>> makeFrequencyEntryFrames(std::uint32_t frequencyHz);

}
