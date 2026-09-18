// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include "core/parser.h"
#include <string>

namespace qdock {
struct DisplayVfo {
    std::string frequency, memory, name, mode, power, step;
    bool selected = false;
};
struct DisplayIndicators {
    int signalLevel = -1, signalOver = 0, batteryPercent = -1;
    bool noa = false, dtmf = false, broadcastFm = false, scan = false;
    bool dualWatch = false, crossBand = false, xb = false, vox = false;
    bool locked = false, function = false, charging = false;
    std::string statusCode, tone, step, lastDtmf;
};

class DisplayModel {
public:
    bool apply(const Event& event);
    const DisplayVfo& vfoA() const { return a_; }
    const DisplayVfo& vfoB() const { return b_; }
    const DisplayIndicators& indicators() const { return indicators_; }
    std::string activeVfo() const;
private:
    static bool printable(const Event& event);
    static bool validFrequency(const std::string& text);
    static bool validMode(const std::string& text);
    void clearLines(int first, int last);
    void updateAfrequency();
    void updateBfrequency();
    DisplayVfo a_, b_;
    DisplayIndicators indicators_;
    std::string lastActiveVfo_;
    std::string aFrequencyMain_, aFrequencySuffix_;
    std::string bFrequencyMain_, bFrequencySuffix_;
};
}
