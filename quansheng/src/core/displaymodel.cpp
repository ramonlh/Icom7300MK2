// SPDX-License-Identifier: GPL-2.0-only
#include "core/displaymodel.h"
#include <algorithm>
#include <cmath>

namespace qdock {
bool DisplayModel::printable(const Event& event) {
    return !event.data.empty() && event.data.size() <= 32
        && std::all_of(event.data.begin(), event.data.end(),
                       [](auto c) { return c >= 0x20 && c <= 0x7e; });
}

bool DisplayModel::validFrequency(const std::string& text) {
    if (text.empty() || text.find('.') == std::string::npos) return false;
    double value = 0.0, fraction = 0.1;
    bool decimal = false, haveDigit = false;
    for (const unsigned char character : text) {
        if (character == '.' && !decimal) {
            decimal = true;
            continue;
        }
        if (character < '0' || character > '9') return false;
        haveDigit = true;
        if (decimal) {
            value += (character - '0') * fraction;
            fraction *= 0.1;
        } else {
            value = value * 10.0 + (character - '0');
        }
    }
    return haveDigit && decimal && std::isfinite(value)
        && value >= 18.0 && value <= 1300.0;
}

bool DisplayModel::validMode(const std::string& text) {
    static const std::string modes[] = {"AM", "FM", "NFM", "WFM",
                                        "USB", "LSB", "CW", "RAW", "BYP"};
    return std::find(std::begin(modes), std::end(modes), text) != std::end(modes);
}

void DisplayModel::clearLines(int first, int last) {
    if (first <= 3 && last >= 1) {
        a_ = {};
        aFrequencyMain_.clear();
        aFrequencySuffix_.clear();
    }
    if (first <= 7 && last >= 5) {
        b_ = {};
        bFrequencyMain_.clear();
        bFrequencySuffix_.clear();
    }
}

void DisplayModel::updateAfrequency() {
    const auto combined = aFrequencyMain_ + aFrequencySuffix_;
    a_.frequency = validFrequency(combined) ? combined
        : (validFrequency(aFrequencyMain_) ? aFrequencyMain_ : std::string{});
}

void DisplayModel::updateBfrequency() {
    const auto combined = bFrequencyMain_ + bFrequencySuffix_;
    b_.frequency = validFrequency(combined) ? combined
        : (validFrequency(bFrequencyMain_) ? bFrequencyMain_ : std::string{});
}

bool DisplayModel::apply(const Event& event) {
    if (event.kind != Event::Kind::Ui) return false;
    if (event.type == 6) {
        indicators_.noa = event.val1 & 8;
        indicators_.dtmf = event.val1 & 16;
        indicators_.broadcastFm = event.val1 & 32;
        indicators_.scan = event.val1 & 64;
        indicators_.dualWatch = event.val1 & 128;
        indicators_.crossBand = event.val2 & 1;
        indicators_.xb = event.val2 & 2;
        indicators_.vox = event.val2 & 4;
        indicators_.locked = event.val2 & 8;
        indicators_.function = event.val2 & 16;
        indicators_.charging = event.val2 & 32;
        indicators_.statusCode = event.val3 == 0 ? std::string{}
            : std::string(1, static_cast<char>(event.val3));
        indicators_.batteryPercent = std::min(100, static_cast<int>(event.field / 2.1 + 0.5));
        if ((event.val1 & 7) != 2) {
            indicators_.signalLevel = -1;
            indicators_.signalOver = 0;
        }
        return true;
    }
    if (event.type == 8) {
        if (event.field != 0 || !event.data.empty() || event.val1 > 9) return false;
        indicators_.signalLevel = event.val1;
        indicators_.signalOver = event.val2;
        return true;
    }
    if (event.type == 10) {
        static const char digits[] = "0123456789ABCD*#";
        indicators_.lastDtmf = event.val1 < 16 ? std::string(1, digits[event.val1]) : "?";
        return true;
    }
    if (event.type == 5) {
        clearLines(event.val1, event.val2);
        return true;
    }
    if (event.type == 7 && (event.val1 == 1 || event.val1 == 5)) {
        if (event.val2 != 0) {
            a_.selected = event.val1 == 1;
            b_.selected = event.val1 == 5;
            lastActiveVfo_ = event.val1 == 1 ? "A" : "B";
        } else if (event.val1 == 1) a_.selected = false;
        else b_.selected = false;
        return true;
    }
    if (event.type > 3 || !printable(event)) return false;
    const std::string text(event.data.begin(), event.data.end());
    const int line = event.val2 + 1;
    bool changed = false;
    if (event.type == 0 && event.val2 == 2 && event.val3 == 8
        && (text == "LOW" || text == "MID" || text == "HIGH")
        && !lastActiveVfo_.empty()) {
        const std::string power(1, text.front());
        if (lastActiveVfo_ == "A") a_.power = power;
        else b_.power = power;
        changed = true;
    }
    if (event.type == 0 && event.val2 == 2 && event.val3 == 8
        && (text == "AM" || text == "FM" || text == "USB"
            || text == "RAW" || text == "BYP")
        && !lastActiveVfo_.empty()) {
        if (lastActiveVfo_ == "A") a_.mode = text;
        else b_.mode = text;
        changed = true;
    }
    if (text.size() >= 3 && text.size() <= 12
        && text.compare(text.size() - 3, 3, "kHz") == 0) {
        indicators_.step = text;
        changed = true;
    }
    if (line == 1 && event.val1 == 123 && text.size() == 1) {
        indicators_.tone = text;
        changed = true;
    }
    if (line >= 1 && line <= 3) {
        if (line == 2 && event.val1 == 36 && validFrequency(text)) {
            aFrequencyMain_.clear(); aFrequencySuffix_.clear();
            a_.frequency = text; changed = true;
        }
        else if (line == 1 && event.type == 3 && event.val1 == 32
                 && validFrequency(text))
            aFrequencyMain_ = text, updateAfrequency(), changed = true;
        else if (line == 2 && event.val1 == 113 && text.size() <= 3
                 && std::all_of(text.begin(), text.end(),
                                [](unsigned char c) { return c >= '0' && c <= '9'; }))
            aFrequencySuffix_ = text, updateAfrequency(), changed = true;
        else if (line == 2 && event.val1 == 2 && text.size() <= 4) a_.memory = text, changed = true;
        else if (line == 1 && event.val1 == 36) a_.name = text, changed = true;
        else if (line == 2 && event.val1 == 152 && validMode(text)) a_.mode = text, changed = true;
        else if (line == 2 && event.val1 == 174) a_.power = text, changed = true;
    } else if (line >= 5 && line <= 7) {
        if (line == 5 && event.val1 == 32 && validFrequency(text)) bFrequencyMain_ = text, updateBfrequency(), changed = true;
        else if (line == 6 && event.val1 == 113 && text.size() <= 3
                 && std::all_of(text.begin(), text.end(),
                                [](unsigned char c) { return c >= '0' && c <= '9'; }))
            bFrequencySuffix_ = text, updateBfrequency(), changed = true;
        else if (line == 6 && event.val1 == 2 && text.size() <= 4) b_.memory = text, changed = true;
        else if (line == 5 && event.val1 == 36) b_.name = text, changed = true;
        else if (line == 6 && event.val1 == 152 && validMode(text)) b_.mode = text, changed = true;
        else if (line == 6 && event.val1 == 174) b_.power = text, changed = true;
    }
    return changed;
}

std::string DisplayModel::activeVfo() const {
    if (a_.selected == b_.selected) return {};
    return a_.selected ? "A" : "B";
}
}
