#include "core/displaymodel.h"
#include <cassert>

qdock::Event ui(int type, int x, int line, const char* text = "", int selected = 0) {
    qdock::Event e{qdock::Event::Kind::Ui};
    e.type = type; e.val1 = x; e.val2 = line; e.field = selected;
    if (type == 7) e.val2 = selected;
    while (*text) e.data.push_back(static_cast<unsigned char>(*text++));
    return e;
}

int main() {
    qdock::DisplayModel model;
    model.apply(ui(7, 1, 0, "", 1));
    model.apply(ui(1, 2, 1, "M1"));
    model.apply(ui(2, 36, 0, "VA.LEON"));
    model.apply(ui(1, 36, 1, "145.67500"));
    model.apply(ui(1, 152, 1, "FM"));
    model.apply(ui(1, 152, 1, "CT"));
    model.apply(ui(1, 174, 1, "H"));
    model.apply(ui(1, 113, 5, "50"));
    model.apply(ui(3, 32, 4, "110.937"));
    assert(model.activeVfo() == "A");
    assert(model.vfoA().frequency == "145.67500");
    assert(model.vfoA().memory == "M1" && model.vfoA().name == "VA.LEON");
    assert(model.vfoA().mode == "FM" && model.vfoA().power == "H");
    assert(model.vfoB().frequency == "110.93750");
    auto falsePositive = ui(0, 36, 1, "145.67500");
    falsePositive.data.push_back(0);
    assert(!model.apply(falsePositive));
    auto clear = ui(5, 1, 7); clear.val1 = 1; clear.val2 = 7;
    model.apply(clear);
    assert(model.vfoA().frequency.empty() && model.vfoB().frequency.empty());

    // Physical VFO screen captured on 2026-09-13: suffix precedes main text.
    model.apply(ui(1, 113, 1, "00"));
    model.apply(ui(3, 32, 0, "435.900"));
    model.apply(ui(1, 2, 1, "F6"));
    model.apply(ui(1, 174, 1, "L"));
    assert(model.vfoA().frequency == "435.90000");
    assert(model.vfoA().memory == "F6" && model.vfoA().power == "L");
    assert(model.vfoA().mode == "FM"); // FM se representa sin rótulo propio.

    // Physical TxPwr screen captured on 2026-09-13: LOW/MID/HIGH belongs
    // to the most recently selected VFO, even after the VFO lines are cleared.
    auto clearForMenu = ui(5, 1, 7); clearForMenu.val1 = 1; clearForMenu.val2 = 7;
    model.apply(clearForMenu);
    auto midPower = ui(0, 77, 2, "MID"); midPower.val3 = 8;
    assert(model.apply(midPower));
    assert(model.vfoA().power == "M");
    auto usbMode = ui(0, 77, 2, "USB"); usbMode.val3 = 8;
    assert(model.apply(usbMode));
    assert(model.vfoA().mode == "USB");
    auto rawMode = ui(0, 77, 2, "RAW"); rawMode.val3 = 8;
    assert(model.apply(rawMode));
    assert(model.vfoA().mode == "RAW");
    auto bypassMode = ui(0, 77, 2, "BYP"); bypassMode.val3 = 8;
    assert(model.apply(bypassMode));
    assert(model.vfoA().mode == "BYP");

    auto status = ui(6, 0, 0); status.val1 = 128 | 64 | 16; status.val2 = 4 | 8 | 32;
    status.val3 = 'R'; status.field = 196; model.apply(status);
    auto signal = ui(8, 0, 0); signal.val1 = 9; signal.val2 = 3; model.apply(signal);
    auto corruptSignal = ui(8, 0, 0); corruptSignal.val1 = 4; corruptSignal.field = 181;
    assert(!model.apply(corruptSignal));
    auto step = ui(0, 61, 2, "5.00kHz"); model.apply(step);
    auto tone = ui(1, 123, 0, "C"); model.apply(tone);
    auto dtmf = ui(10, 11, 0); dtmf.val1 = 11; model.apply(dtmf);
    const auto& flags = model.indicators();
    assert(flags.dualWatch && flags.scan && flags.dtmf && flags.vox);
    assert(flags.locked && flags.charging && flags.batteryPercent == 93);
    assert(flags.signalLevel == 9 && flags.signalOver == 3);
    assert(flags.step == "5.00kHz" && flags.tone == "C" && flags.lastDtmf == "B");
    auto idle = ui(6, 0, 0); idle.val1 = 0; idle.field = 196; model.apply(idle);
    assert(model.indicators().signalLevel == -1 && model.indicators().signalOver == 0);
}
