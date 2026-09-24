// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <array>
#include <cstdio>
#include <string>

namespace qdock {
// Firmware Dock 0.32.21q: dcs.c tables, EEPROM zero-based indices.
inline constexpr std::array<int, 50> ctcssTones{
    670,693,719,744,770,797,825,854,885,915,948,974,1000,1035,1072,1109,
    1148,1188,1230,1273,1318,1365,1413,1462,1514,1567,1598,1622,1655,1679,
    1713,1738,1773,1799,1835,1862,1899,1928,1966,1995,2035,2065,2107,2181,
    2257,2291,2336,2418,2503,2541};
inline constexpr std::array<int, 104> dcsCodes{
    023,025,026,031,032,036,043,047,051,053,054,065,071,072,073,074,
    0114,0115,0116,0122,0125,0131,0132,0134,0143,0145,0152,0155,0156,0162,
    0165,0172,0174,0205,0212,0223,0225,0226,0243,0244,0245,0246,0251,0252,
    0255,0261,0263,0265,0266,0271,0274,0306,0311,0315,0325,0331,0332,0343,
    0346,0351,0356,0364,0365,0371,0411,0412,0413,0423,0431,0432,0445,0446,
    0452,0454,0455,0462,0464,0465,0466,0503,0506,0516,0523,0526,0532,0546,
    0565,0606,0612,0624,0627,0631,0632,0654,0662,0664,0703,0712,0723,0731,
    0732,0734,0743,0754};

inline bool validTone(int type, int index) {
    return (type == 0 && index == 0)
        || (type == 1 && index >= 0 && index < int(ctcssTones.size()))
        || ((type == 2 || type == 3) && index >= 0 && index < int(dcsCodes.size()));
}
inline std::string toneLabel(int type, int index) {
    if (!validTone(type, index)) return "Desconocido (tipo " + std::to_string(type)
        + ", índice " + std::to_string(index) + ")";
    if (type == 0) return "OFF";
    char text[32];
    if (type == 1)
        std::snprintf(text, sizeof(text), "%d.%d Hz", ctcssTones[index] / 10, ctcssTones[index] % 10);
    else
        std::snprintf(text, sizeof(text), "D%03o%c", dcsCodes[index], type == 2 ? 'N' : 'I');
    return text;
}
}
