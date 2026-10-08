// SPDX-License-Identifier: GPL-2.0-only
#include "experimental/keycontrol.h"
#include <cmath>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>

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
    frame.push_back(0xdc); frame.push_back(0xba);
    return frame;
}
}

std::vector<std::uint8_t> makeKeyPressFrame(std::uint8_t value) {
    if (value > 19) throw std::invalid_argument("tecla Quansheng fuera de rango");
    return makeFrame({0x01, 0x08, 0x02, 0x00, value, 0x00});
}

std::vector<std::vector<std::uint8_t>> makeVfoSwitchFrames() {
    return {makeKeyPressFrame(15), makeKeyPressFrame(19),
            makeKeyPressFrame(2), makeKeyPressFrame(19)};
}

std::vector<std::vector<std::uint8_t>> makeVfoModeToggleFrames(bool selectOther) {
    std::vector<std::vector<std::uint8_t>> frames;
    if (selectOther) {
        const auto select = makeVfoSwitchFrames();
        frames.insert(frames.end(), select.begin(), select.end());
    }
    frames.push_back(makeKeyPressFrame(15)); frames.push_back(makeKeyPressFrame(19));
    frames.push_back(makeKeyPressFrame(3)); frames.push_back(makeKeyPressFrame(19));
    return frames;
}

std::vector<std::vector<std::uint8_t>> makeMemoryStepFrames(bool up, bool selectOther) {
    std::vector<std::vector<std::uint8_t>> frames;
    if (selectOther) {
        const auto select = makeVfoSwitchFrames();
        frames.insert(frames.end(), select.begin(), select.end());
    }
    frames.push_back(makeKeyPressFrame(up ? 11 : 12));
    frames.push_back(makeKeyPressFrame(19));
    return frames;
}

std::vector<std::vector<std::uint8_t>> makeModeChangeFrames(std::uint8_t mode, bool selectOther) {
    if (mode > 4) throw std::invalid_argument("modo Quansheng fuera de rango");
    std::vector<std::vector<std::uint8_t>> frames;
    const auto click = [&](std::uint8_t value) {
        frames.push_back(makeKeyPressFrame(value));
        frames.push_back(makeKeyPressFrame(19));
    };
    if (selectOther) {
        const auto select = makeVfoSwitchFrames();
        frames.insert(frames.end(), select.begin(), select.end());
    }
    click(10); // MENU
    click(1);  // 13: Demodu
    click(3);
    click(10); // entrar en el ajuste
    click(mode);
    click(10); // aceptar
    click(13); // salir del menú
    return frames;
}

std::vector<std::vector<std::uint8_t>> makeMenuSettingFrames(
    std::uint8_t menuNumber, std::uint32_t value)
{
    if (menuNumber > 99 || (menuNumber == 8
            ? (value > 99999900U || value % 100U != 0)
            : value > 999U))
        throw std::invalid_argument("ajuste de menú Quansheng fuera de rango");
    std::vector<std::vector<std::uint8_t>> frames;
    const auto click = [&](std::uint8_t keyValue) {
        frames.push_back(makeKeyPressFrame(keyValue));
        frames.push_back(makeKeyPressFrame(19));
    };
    click(10); // MENU
    if (menuNumber >= 10)
        click(menuNumber / 10);
    click(menuNumber % 10);
    click(10); // entrar en el ajuste
    std::string digits = std::to_string(menuNumber == 8 ? value / 100U : value);
    if (menuNumber == 8)
        digits.insert(0, 6 - digits.size(), '0');
    for (const char digit : digits)
        click(static_cast<std::uint8_t>(digit - '0'));
    click(10); // aceptar
    click(13); // salir del menú
    return frames;
}

std::vector<std::vector<std::uint8_t>> makeDualWatchFrames(bool enabled) {
    // Firmware Dock 0.32.21q: menú 59 "RxMode", 0=OFF, 1=DWR.
    return makeMenuSettingFrames(59, enabled ? 1 : 0);
}

std::vector<std::vector<std::uint8_t>> makeSquelchFrames(std::uint8_t level) {
    if (level > 9) throw std::invalid_argument("nivel de squelch fuera de 0-9");
    // Firmware Dock 0.32.21q: menú 61 "Sql".
    return makeMenuSettingFrames(61, level);
}

std::vector<std::vector<std::uint8_t>> makeVoxFrames(std::uint8_t level) {
    if (level > 9) throw std::invalid_argument("nivel VOX fuera de 0-9");
    // Firmware Dock 0.32.21q: menú 57 "VOX"; 0=OFF, 1..9=nivel por teclado.
    return makeMenuSettingFrames(57, level);
}

std::vector<std::vector<std::uint8_t>> makeFrequencyEntryFrames(std::uint32_t frequencyHz) {
    if (frequencyHz < 18000000 || frequencyHz > 1300000000
            || (frequencyHz > 630000000 && frequencyHz < 840000000))
        throw std::invalid_argument("frecuencia no utilizable (18-1300 MHz; 630-840 MHz excluidos)");
    const auto khz = static_cast<std::uint32_t>(std::llround(frequencyHz / 1000.0));
    std::ostringstream formatted;
    formatted << std::setw(6) << std::setfill('0') << khz;
    const auto text = formatted.str();
    if (text.size() != 6)
        throw std::invalid_argument("la entrada de frecuencia requiere seis dígitos");
    std::vector<std::vector<std::uint8_t>> frames;
    frames.reserve(text.size());
    for (const char digit : text)
        frames.push_back(makeKeyPressFrame(static_cast<std::uint8_t>(digit - '0')));
    return frames;
}

std::vector<std::vector<std::uint8_t>> makeFrequencyChangeFrames(
    std::uint32_t frequencyHz, bool configureTenHzStep) {
    if (frequencyHz < 18000000 || frequencyHz > 1300000000
            || (frequencyHz > 630000000 && frequencyHz < 840000000))
        throw std::invalid_argument("frecuencia no utilizable (18-1300 MHz; 630-840 MHz excluidos)");
    const auto target = ((frequencyHz + 5u) / 10u) * 10u;
    const auto khz = ((target + 500u) / 1000u) * 1000u;
    if (khz < 18000000u || khz > 1300000000u
            || (khz > 630000000u && khz < 840000000u))
        throw std::invalid_argument("frecuencia base fuera de banda utilizable");

    std::vector<std::vector<std::uint8_t>> frames;
    const auto click = [&frames](std::uint8_t keyValue) {
        frames.push_back(makeKeyPressFrame(keyValue));
        frames.push_back(makeKeyPressFrame(19));
    };
    if (configureTenHzStep) {
        const auto step = makeMenuSettingFrames(1, 0);
        frames.insert(frames.end(), step.begin(), step.end());
    }
    for (const auto& digit : makeFrequencyEntryFrames(khz)) {
        frames.push_back(digit);
        frames.push_back(makeKeyPressFrame(19));
    }
    const auto delta = static_cast<std::int64_t>(target) - static_cast<std::int64_t>(khz);
    const auto keyValue = delta >= 0 ? std::uint8_t(11) : std::uint8_t(12);
    const auto steps = (delta < 0 ? -delta : delta) / 10;
    for (std::int64_t count = 0; count < steps; ++count)
        click(keyValue);
    return frames;
}

std::vector<std::vector<std::uint8_t>> makeFrequencyStepFrames(bool up, bool configureTenHzStep) {
    std::vector<std::vector<std::uint8_t>> frames;
    if (configureTenHzStep) {
        const auto step = makeMenuSettingFrames(1, 0);
        frames.insert(frames.end(), step.begin(), step.end());
    }
    frames.push_back(makeKeyPressFrame(up ? 11 : 12));
    frames.push_back(makeKeyPressFrame(19));
    return frames;
}
}
