//
//  iTermCharacterSets.m
//  iTerm2
//
//  Fast character set membership tests using bitmaps and binary search.
//  Replaces NSCharacterSet lookups in StringToScreenChars hot path.
//
//  THIS FILE IS AUTO-GENERATED. DO NOT EDIT DIRECTLY.
//  Run tools/generate_nscharacterset.py to regenerate.
//

#import "iTermCharacterSets.h"
#import <Foundation/Foundation.h>
#include <string.h>

// ============================================================================
// Bitmap infrastructure (same approach as iTermCharacterWidth.c)
// ============================================================================

typedef struct {
    uint64_t bits[1024];  // 65536 bits = BMP
} BMPBitmap;

typedef struct {
    uint32_t start;
    uint32_t end;  // inclusive
} CharRange;

NS_INLINE void setBit(BMPBitmap *bmp, uint32_t cp) {
    bmp->bits[cp >> 6] |= (1ULL << (cp & 63));
}

NS_INLINE BOOL testBit(const BMPBitmap *bmp, uint32_t cp) {
    return (bmp->bits[cp >> 6] & (1ULL << (cp & 63))) != 0;
}

NS_INLINE void setRange(BMPBitmap *bmp, uint32_t start, uint32_t count) {
    for (uint32_t i = start; i < start + count; i++) {
        setBit(bmp, i);
    }
}

static BOOL inRanges(uint32_t cp, const CharRange *ranges, int count) {
    int lo = 0, hi = count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (cp < ranges[mid].start) {
            hi = mid - 1;
        } else if (cp > ranges[mid].end) {
            lo = mid + 1;
        } else {
            return YES;
        }
    }
    return NO;
}

// ============================================================================
// Static bitmaps
// ============================================================================

static BMPBitmap sIgnorableBMP;
static BMPBitmap sSpacingCombiningMarksBMP;
static BMPBitmap sEmojiAcceptingVS16BMP;
static BMPBitmap sRTLBMP;
static BMPBitmap sCodePointsWithOwnCellBMP;

// ============================================================================
// Supplementary plane ranges
// ============================================================================

// Ignorable supplementary ranges
static const CharRange sIgnorableSupp[] = {
    {0x1bca0, 0x1bca3},
    {0x1d173, 0x1d17a},
    {0xe0000, 0xe0fff},
};
static const int sIgnorableSuppCount = sizeof(sIgnorableSupp) / sizeof(sIgnorableSupp[0]);

// Spacing combining marks supplementary ranges
static const CharRange sSpacingCombiningMarksSupp[] = {
    {0x11000, 0x11000},
    {0x11002, 0x11002},
    {0x11082, 0x11082},
    {0x110b0, 0x110b2},
    {0x110b7, 0x110b8},
    {0x1112c, 0x1112c},
    {0x11145, 0x11146},
    {0x11182, 0x11182},
    {0x111b3, 0x111b5},
    {0x111bf, 0x111c0},
    {0x111ce, 0x111ce},
    {0x1122c, 0x1122e},
    {0x11232, 0x11233},
    {0x11235, 0x11235},
    {0x112e0, 0x112e2},
    {0x11302, 0x11303},
    {0x1133e, 0x1133f},
    {0x11341, 0x11344},
    {0x11347, 0x11348},
    {0x1134b, 0x1134d},
    {0x11357, 0x11357},
    {0x11362, 0x11363},
    {0x113b8, 0x113ba},
    {0x113c2, 0x113c2},
    {0x113c5, 0x113c5},
    {0x113c7, 0x113ca},
    {0x113cc, 0x113cd},
    {0x113cf, 0x113cf},
    {0x11435, 0x11437},
    {0x11440, 0x11441},
    {0x11445, 0x11445},
    {0x114b0, 0x114b2},
    {0x114b9, 0x114b9},
    {0x114bb, 0x114be},
    {0x114c1, 0x114c1},
    {0x115af, 0x115b1},
    {0x115b8, 0x115bb},
    {0x115be, 0x115be},
    {0x11630, 0x11632},
    {0x1163b, 0x1163c},
    {0x1163e, 0x1163e},
    {0x116ac, 0x116ac},
    {0x116ae, 0x116af},
    {0x116b6, 0x116b6},
    {0x1171e, 0x1171e},
    {0x11720, 0x11721},
    {0x11726, 0x11726},
    {0x1182c, 0x1182e},
    {0x11838, 0x11838},
    {0x11930, 0x11935},
    {0x11937, 0x11938},
    {0x1193d, 0x1193d},
    {0x11940, 0x11940},
    {0x11942, 0x11942},
    {0x119d1, 0x119d3},
    {0x119dc, 0x119df},
    {0x119e4, 0x119e4},
    {0x11a39, 0x11a39},
    {0x11a57, 0x11a58},
    {0x11a97, 0x11a97},
    {0x11b61, 0x11b61},
    {0x11b65, 0x11b65},
    {0x11b67, 0x11b67},
    {0x11c2f, 0x11c2f},
    {0x11c3e, 0x11c3e},
    {0x11ca9, 0x11ca9},
    {0x11cb1, 0x11cb1},
    {0x11cb4, 0x11cb4},
    {0x11d8a, 0x11d8e},
    {0x11d93, 0x11d94},
    {0x11d96, 0x11d96},
    {0x11ef5, 0x11ef6},
    {0x11f03, 0x11f03},
    {0x11f34, 0x11f35},
    {0x11f3e, 0x11f3f},
    {0x11f41, 0x11f41},
    {0x1612a, 0x1612c},
    {0x16f51, 0x16f87},
    {0x16ff0, 0x16ff1},
    {0x1d165, 0x1d166},
    {0x1d16d, 0x1d172},
};
static const int sSpacingCombiningMarksSuppCount =
    sizeof(sSpacingCombiningMarksSupp) / sizeof(sSpacingCombiningMarksSupp[0]);

// Emoji accepting VS16 supplementary ranges
static const CharRange sEmojiAcceptingVS16Supp[] = {
    {0x1f170, 0x1f171},
    {0x1f17e, 0x1f17f},
    {0x1f202, 0x1f202},
    {0x1f237, 0x1f237},
    {0x1f321, 0x1f321},
    {0x1f324, 0x1f32c},
    {0x1f336, 0x1f336},
    {0x1f37d, 0x1f37d},
    {0x1f396, 0x1f397},
    {0x1f399, 0x1f39b},
    {0x1f39e, 0x1f39f},
    {0x1f3cb, 0x1f3ce},
    {0x1f3d4, 0x1f3df},
    {0x1f3f3, 0x1f3f3},
    {0x1f3f5, 0x1f3f5},
    {0x1f3f7, 0x1f3f7},
    {0x1f43f, 0x1f43f},
    {0x1f441, 0x1f441},
    {0x1f4fd, 0x1f4fd},
    {0x1f549, 0x1f54a},
    {0x1f56f, 0x1f570},
    {0x1f573, 0x1f579},
    {0x1f587, 0x1f587},
    {0x1f58a, 0x1f58d},
    {0x1f590, 0x1f590},
    {0x1f5a5, 0x1f5a5},
    {0x1f5a8, 0x1f5a8},
    {0x1f5b1, 0x1f5b2},
    {0x1f5bc, 0x1f5bc},
    {0x1f5c2, 0x1f5c4},
    {0x1f5d1, 0x1f5d3},
    {0x1f5dc, 0x1f5de},
    {0x1f5e1, 0x1f5e1},
    {0x1f5e3, 0x1f5e3},
    {0x1f5e8, 0x1f5e8},
    {0x1f5ef, 0x1f5ef},
    {0x1f5f3, 0x1f5f3},
    {0x1f5fa, 0x1f5fa},
    {0x1f6cb, 0x1f6cb},
    {0x1f6cd, 0x1f6cf},
    {0x1f6e0, 0x1f6e5},
    {0x1f6e9, 0x1f6e9},
    {0x1f6f0, 0x1f6f0},
    {0x1f6f3, 0x1f6f3},
};
static const int sEmojiAcceptingVS16SuppCount =
    sizeof(sEmojiAcceptingVS16Supp) / sizeof(sEmojiAcceptingVS16Supp[0]);

// RTL supplementary ranges
static const CharRange sRTLSupp[] = {
    {0x10800, 0x10805},
    {0x10808, 0x10808},
    {0x1080a, 0x10835},
    {0x10837, 0x10838},
    {0x1083c, 0x1083c},
    {0x1083f, 0x10855},
    {0x10857, 0x1089e},
    {0x108a7, 0x108af},
    {0x108e0, 0x108f2},
    {0x108f4, 0x108f5},
    {0x108fb, 0x1091b},
    {0x10920, 0x10939},
    {0x1093f, 0x10959},
    {0x10980, 0x109b7},
    {0x109bc, 0x109cf},
    {0x109d2, 0x10a00},
    {0x10a10, 0x10a13},
    {0x10a15, 0x10a17},
    {0x10a19, 0x10a35},
    {0x10a40, 0x10a48},
    {0x10a50, 0x10a58},
    {0x10a60, 0x10a9f},
    {0x10ac0, 0x10ae4},
    {0x10aeb, 0x10af6},
    {0x10b00, 0x10b35},
    {0x10b40, 0x10b55},
    {0x10b58, 0x10b72},
    {0x10b78, 0x10b91},
    {0x10b99, 0x10b9c},
    {0x10ba9, 0x10baf},
    {0x10c00, 0x10c48},
    {0x10c80, 0x10cb2},
    {0x10cc0, 0x10cf2},
    {0x10cfa, 0x10d23},
    {0x10d30, 0x10d39},
    {0x10d40, 0x10d65},
    {0x10d6f, 0x10d85},
    {0x10d8e, 0x10d8f},
    {0x10e60, 0x10e7e},
    {0x10e80, 0x10ea9},
    {0x10ead, 0x10ead},
    {0x10eb0, 0x10eb1},
    {0x10ec2, 0x10ec7},
    {0x10f00, 0x10f27},
    {0x10f30, 0x10f45},
    {0x10f51, 0x10f59},
    {0x10f70, 0x10f81},
    {0x10f86, 0x10f89},
    {0x10fb0, 0x10fcb},
    {0x10fe0, 0x10ff6},
    {0x1e800, 0x1e8c4},
    {0x1e8c7, 0x1e8cf},
    {0x1e900, 0x1e943},
    {0x1e94b, 0x1e94b},
    {0x1e950, 0x1e959},
    {0x1e95e, 0x1e95f},
    {0x1ec71, 0x1ecb4},
    {0x1ed01, 0x1ed3d},
    {0x1ee00, 0x1ee03},
    {0x1ee05, 0x1ee1f},
    {0x1ee21, 0x1ee22},
    {0x1ee24, 0x1ee24},
    {0x1ee27, 0x1ee27},
    {0x1ee29, 0x1ee32},
    {0x1ee34, 0x1ee37},
    {0x1ee39, 0x1ee39},
    {0x1ee3b, 0x1ee3b},
    {0x1ee42, 0x1ee42},
    {0x1ee47, 0x1ee47},
    {0x1ee49, 0x1ee49},
    {0x1ee4b, 0x1ee4b},
    {0x1ee4d, 0x1ee4f},
    {0x1ee51, 0x1ee52},
    {0x1ee54, 0x1ee54},
    {0x1ee57, 0x1ee57},
    {0x1ee59, 0x1ee59},
    {0x1ee5b, 0x1ee5b},
    {0x1ee5d, 0x1ee5d},
    {0x1ee5f, 0x1ee5f},
    {0x1ee61, 0x1ee62},
    {0x1ee64, 0x1ee64},
    {0x1ee67, 0x1ee6a},
    {0x1ee6c, 0x1ee72},
    {0x1ee74, 0x1ee77},
    {0x1ee79, 0x1ee7c},
    {0x1ee7e, 0x1ee7e},
    {0x1ee80, 0x1ee89},
    {0x1ee8b, 0x1ee9b},
    {0x1eea1, 0x1eea3},
    {0x1eea5, 0x1eea9},
    {0x1eeab, 0x1eebb},
};
static const int sRTLSuppCount = sizeof(sRTLSupp) / sizeof(sRTLSupp[0]);

// Code points with own cell supplementary ranges
// (Grapheme_Base - Default_Ignorable) + spacing combining marks (gc=Mc) + modifier letters (gc=Lm)
static const CharRange sCodePointsWithOwnCellSupp[] = {
    {0x10000, 0x1000b},
    {0x1000d, 0x10026},
    {0x10028, 0x1003a},
    {0x1003c, 0x1003d},
    {0x1003f, 0x1004d},
    {0x10050, 0x1005d},
    {0x10080, 0x100fa},
    {0x10100, 0x10102},
    {0x10107, 0x10133},
    {0x10137, 0x1018e},
    {0x10190, 0x1019c},
    {0x101a0, 0x101a0},
    {0x101d0, 0x101fc},
    {0x10280, 0x1029c},
    {0x102a0, 0x102d0},
    {0x102e1, 0x102fb},
    {0x10300, 0x10323},
    {0x1032d, 0x1034a},
    {0x10350, 0x10375},
    {0x10380, 0x1039d},
    {0x1039f, 0x103c3},
    {0x103c8, 0x103d5},
    {0x10400, 0x1049d},
    {0x104a0, 0x104a9},
    {0x104b0, 0x104d3},
    {0x104d8, 0x104fb},
    {0x10500, 0x10527},
    {0x10530, 0x10563},
    {0x1056f, 0x1057a},
    {0x1057c, 0x1058a},
    {0x1058c, 0x10592},
    {0x10594, 0x10595},
    {0x10597, 0x105a1},
    {0x105a3, 0x105b1},
    {0x105b3, 0x105b9},
    {0x105bb, 0x105bc},
    {0x105c0, 0x105f3},
    {0x10600, 0x10736},
    {0x10740, 0x10755},
    {0x10760, 0x10767},
    {0x10780, 0x10785},
    {0x10787, 0x107b0},
    {0x107b2, 0x107ba},
    {0x10800, 0x10805},
    {0x10808, 0x10808},
    {0x1080a, 0x10835},
    {0x10837, 0x10838},
    {0x1083c, 0x1083c},
    {0x1083f, 0x10855},
    {0x10857, 0x1089e},
    {0x108a7, 0x108af},
    {0x108e0, 0x108f2},
    {0x108f4, 0x108f5},
    {0x108fb, 0x1091b},
    {0x1091f, 0x10939},
    {0x1093f, 0x10959},
    {0x10980, 0x109b7},
    {0x109bc, 0x109cf},
    {0x109d2, 0x10a00},
    {0x10a10, 0x10a13},
    {0x10a15, 0x10a17},
    {0x10a19, 0x10a35},
    {0x10a40, 0x10a48},
    {0x10a50, 0x10a58},
    {0x10a60, 0x10a9f},
    {0x10ac0, 0x10ae4},
    {0x10aeb, 0x10af6},
    {0x10b00, 0x10b35},
    {0x10b39, 0x10b55},
    {0x10b58, 0x10b72},
    {0x10b78, 0x10b91},
    {0x10b99, 0x10b9c},
    {0x10ba9, 0x10baf},
    {0x10c00, 0x10c48},
    {0x10c80, 0x10cb2},
    {0x10cc0, 0x10cf2},
    {0x10cfa, 0x10d23},
    {0x10d30, 0x10d39},
    {0x10d40, 0x10d65},
    {0x10d6e, 0x10d85},
    {0x10d8e, 0x10d8f},
    {0x10e60, 0x10e7e},
    {0x10e80, 0x10ea9},
    {0x10ead, 0x10ead},
    {0x10eb0, 0x10eb1},
    {0x10ec2, 0x10ec7},
    {0x10ed0, 0x10ed8},
    {0x10f00, 0x10f27},
    {0x10f30, 0x10f45},
    {0x10f51, 0x10f59},
    {0x10f70, 0x10f81},
    {0x10f86, 0x10f89},
    {0x10fb0, 0x10fcb},
    {0x10fe0, 0x10ff6},
    {0x11000, 0x11000},
    {0x11002, 0x11037},
    {0x11047, 0x1104d},
    {0x11052, 0x1106f},
    {0x11071, 0x11072},
    {0x11075, 0x11075},
    {0x11082, 0x110b2},
    {0x110b7, 0x110b8},
    {0x110bb, 0x110bc},
    {0x110be, 0x110c1},
    {0x110d0, 0x110e8},
    {0x110f0, 0x110f9},
    {0x11103, 0x11126},
    {0x1112c, 0x1112c},
    {0x11136, 0x11147},
    {0x11150, 0x11172},
    {0x11174, 0x11176},
    {0x11182, 0x111b5},
    {0x111bf, 0x111c8},
    {0x111cd, 0x111ce},
    {0x111d0, 0x111df},
    {0x111e1, 0x111f4},
    {0x11200, 0x11211},
    {0x11213, 0x1122e},
    {0x11232, 0x11233},
    {0x11235, 0x11235},
    {0x11238, 0x1123d},
    {0x1123f, 0x11240},
    {0x11280, 0x11286},
    {0x11288, 0x11288},
    {0x1128a, 0x1128d},
    {0x1128f, 0x1129d},
    {0x1129f, 0x112a9},
    {0x112b0, 0x112de},
    {0x112e0, 0x112e2},
    {0x112f0, 0x112f9},
    {0x11302, 0x11303},
    {0x11305, 0x1130c},
    {0x1130f, 0x11310},
    {0x11313, 0x11328},
    {0x1132a, 0x11330},
    {0x11332, 0x11333},
    {0x11335, 0x11339},
    {0x1133d, 0x1133f},
    {0x11341, 0x11344},
    {0x11347, 0x11348},
    {0x1134b, 0x1134d},
    {0x11350, 0x11350},
    {0x11357, 0x11357},
    {0x1135d, 0x11363},
    {0x11380, 0x11389},
    {0x1138b, 0x1138b},
    {0x1138e, 0x1138e},
    {0x11390, 0x113b5},
    {0x113b7, 0x113ba},
    {0x113c2, 0x113c2},
    {0x113c5, 0x113c5},
    {0x113c7, 0x113ca},
    {0x113cc, 0x113cd},
    {0x113cf, 0x113cf},
    {0x113d1, 0x113d1},
    {0x113d3, 0x113d5},
    {0x113d7, 0x113d8},
    {0x11400, 0x11437},
    {0x11440, 0x11441},
    {0x11445, 0x11445},
    {0x11447, 0x1145b},
    {0x1145d, 0x1145d},
    {0x1145f, 0x11461},
    {0x11480, 0x114b2},
    {0x114b9, 0x114b9},
    {0x114bb, 0x114be},
    {0x114c1, 0x114c1},
    {0x114c4, 0x114c7},
    {0x114d0, 0x114d9},
    {0x11580, 0x115b1},
    {0x115b8, 0x115bb},
    {0x115be, 0x115be},
    {0x115c1, 0x115db},
    {0x11600, 0x11632},
    {0x1163b, 0x1163c},
    {0x1163e, 0x1163e},
    {0x11641, 0x11644},
    {0x11650, 0x11659},
    {0x11660, 0x1166c},
    {0x11680, 0x116aa},
    {0x116ac, 0x116ac},
    {0x116ae, 0x116af},
    {0x116b6, 0x116b6},
    {0x116b8, 0x116b9},
    {0x116c0, 0x116c9},
    {0x116d0, 0x116e3},
    {0x11700, 0x1171a},
    {0x1171e, 0x1171e},
    {0x11720, 0x11721},
    {0x11726, 0x11726},
    {0x11730, 0x11746},
    {0x11800, 0x1182e},
    {0x11838, 0x11838},
    {0x1183b, 0x1183b},
    {0x118a0, 0x118f2},
    {0x118ff, 0x11906},
    {0x11909, 0x11909},
    {0x1190c, 0x11913},
    {0x11915, 0x11916},
    {0x11918, 0x11935},
    {0x11937, 0x11938},
    {0x1193d, 0x1193d},
    {0x1193f, 0x11942},
    {0x11944, 0x11946},
    {0x11950, 0x11959},
    {0x119a0, 0x119a7},
    {0x119aa, 0x119d3},
    {0x119dc, 0x119df},
    {0x119e1, 0x119e4},
    {0x11a00, 0x11a00},
    {0x11a0b, 0x11a32},
    {0x11a39, 0x11a3a},
    {0x11a3f, 0x11a46},
    {0x11a50, 0x11a50},
    {0x11a57, 0x11a58},
    {0x11a5c, 0x11a89},
    {0x11a97, 0x11a97},
    {0x11a9a, 0x11aa2},
    {0x11ab0, 0x11af8},
    {0x11b00, 0x11b09},
    {0x11b61, 0x11b61},
    {0x11b65, 0x11b65},
    {0x11b67, 0x11b67},
    {0x11bc0, 0x11be1},
    {0x11bf0, 0x11bf9},
    {0x11c00, 0x11c08},
    {0x11c0a, 0x11c2f},
    {0x11c3e, 0x11c3e},
    {0x11c40, 0x11c45},
    {0x11c50, 0x11c6c},
    {0x11c70, 0x11c8f},
    {0x11ca9, 0x11ca9},
    {0x11cb1, 0x11cb1},
    {0x11cb4, 0x11cb4},
    {0x11d00, 0x11d06},
    {0x11d08, 0x11d09},
    {0x11d0b, 0x11d30},
    {0x11d46, 0x11d46},
    {0x11d50, 0x11d59},
    {0x11d60, 0x11d65},
    {0x11d67, 0x11d68},
    {0x11d6a, 0x11d8e},
    {0x11d93, 0x11d94},
    {0x11d96, 0x11d96},
    {0x11d98, 0x11d98},
    {0x11da0, 0x11da9},
    {0x11db0, 0x11ddb},
    {0x11de0, 0x11de9},
    {0x11ee0, 0x11ef2},
    {0x11ef5, 0x11ef8},
    {0x11f02, 0x11f10},
    {0x11f12, 0x11f35},
    {0x11f3e, 0x11f3f},
    {0x11f41, 0x11f41},
    {0x11f43, 0x11f59},
    {0x11fb0, 0x11fb0},
    {0x11fc0, 0x11ff1},
    {0x11fff, 0x12399},
    {0x12400, 0x1246e},
    {0x12470, 0x12474},
    {0x12480, 0x12543},
    {0x12f90, 0x12ff2},
    {0x13000, 0x1342f},
    {0x13441, 0x13446},
    {0x13460, 0x143fa},
    {0x14400, 0x14646},
    {0x16100, 0x1611d},
    {0x1612a, 0x1612c},
    {0x16130, 0x16139},
    {0x16800, 0x16a38},
    {0x16a40, 0x16a5e},
    {0x16a60, 0x16a69},
    {0x16a6e, 0x16abe},
    {0x16ac0, 0x16ac9},
    {0x16ad0, 0x16aed},
    {0x16af5, 0x16af5},
    {0x16b00, 0x16b2f},
    {0x16b37, 0x16b45},
    {0x16b50, 0x16b59},
    {0x16b5b, 0x16b61},
    {0x16b63, 0x16b77},
    {0x16b7d, 0x16b8f},
    {0x16d40, 0x16d79},
    {0x16e40, 0x16e9a},
    {0x16ea0, 0x16eb8},
    {0x16ebb, 0x16ed3},
    {0x16f00, 0x16f4a},
    {0x16f50, 0x16f87},
    {0x16f93, 0x16f9f},
    {0x16fe0, 0x16fe3},
    {0x16ff0, 0x16ff6},
    {0x17000, 0x18cd5},
    {0x18cff, 0x18d1e},
    {0x18d80, 0x18df2},
    {0x1aff0, 0x1aff3},
    {0x1aff5, 0x1affb},
    {0x1affd, 0x1affe},
    {0x1b000, 0x1b122},
    {0x1b132, 0x1b132},
    {0x1b150, 0x1b152},
    {0x1b155, 0x1b155},
    {0x1b164, 0x1b167},
    {0x1b170, 0x1b2fb},
    {0x1bc00, 0x1bc6a},
    {0x1bc70, 0x1bc7c},
    {0x1bc80, 0x1bc88},
    {0x1bc90, 0x1bc99},
    {0x1bc9c, 0x1bc9c},
    {0x1bc9f, 0x1bc9f},
    {0x1cc00, 0x1ccfc},
    {0x1cd00, 0x1ceb3},
    {0x1ceba, 0x1ced0},
    {0x1cee0, 0x1cef0},
    {0x1cf50, 0x1cfc3},
    {0x1d000, 0x1d0f5},
    {0x1d100, 0x1d126},
    {0x1d129, 0x1d166},
    {0x1d16a, 0x1d172},
    {0x1d183, 0x1d184},
    {0x1d18c, 0x1d1a9},
    {0x1d1ae, 0x1d1ea},
    {0x1d200, 0x1d241},
    {0x1d245, 0x1d245},
    {0x1d2c0, 0x1d2d3},
    {0x1d2e0, 0x1d2f3},
    {0x1d300, 0x1d356},
    {0x1d360, 0x1d378},
    {0x1d400, 0x1d454},
    {0x1d456, 0x1d49c},
    {0x1d49e, 0x1d49f},
    {0x1d4a2, 0x1d4a2},
    {0x1d4a5, 0x1d4a6},
    {0x1d4a9, 0x1d4ac},
    {0x1d4ae, 0x1d4b9},
    {0x1d4bb, 0x1d4bb},
    {0x1d4bd, 0x1d4c3},
    {0x1d4c5, 0x1d505},
    {0x1d507, 0x1d50a},
    {0x1d50d, 0x1d514},
    {0x1d516, 0x1d51c},
    {0x1d51e, 0x1d539},
    {0x1d53b, 0x1d53e},
    {0x1d540, 0x1d544},
    {0x1d546, 0x1d546},
    {0x1d54a, 0x1d550},
    {0x1d552, 0x1d6a5},
    {0x1d6a8, 0x1d7cb},
    {0x1d7ce, 0x1d9ff},
    {0x1da37, 0x1da3a},
    {0x1da6d, 0x1da74},
    {0x1da76, 0x1da83},
    {0x1da85, 0x1da8b},
    {0x1df00, 0x1df1e},
    {0x1df25, 0x1df2a},
    {0x1e030, 0x1e06d},
    {0x1e100, 0x1e12c},
    {0x1e137, 0x1e13d},
    {0x1e140, 0x1e149},
    {0x1e14e, 0x1e14f},
    {0x1e290, 0x1e2ad},
    {0x1e2c0, 0x1e2eb},
    {0x1e2f0, 0x1e2f9},
    {0x1e2ff, 0x1e2ff},
    {0x1e4d0, 0x1e4eb},
    {0x1e4f0, 0x1e4f9},
    {0x1e5d0, 0x1e5ed},
    {0x1e5f0, 0x1e5fa},
    {0x1e5ff, 0x1e5ff},
    {0x1e6c0, 0x1e6de},
    {0x1e6e0, 0x1e6e2},
    {0x1e6e4, 0x1e6e5},
    {0x1e6e7, 0x1e6ed},
    {0x1e6f0, 0x1e6f4},
    {0x1e6fe, 0x1e6ff},
    {0x1e7e0, 0x1e7e6},
    {0x1e7e8, 0x1e7eb},
    {0x1e7ed, 0x1e7ee},
    {0x1e7f0, 0x1e7fe},
    {0x1e800, 0x1e8c4},
    {0x1e8c7, 0x1e8cf},
    {0x1e900, 0x1e943},
    {0x1e94b, 0x1e94b},
    {0x1e950, 0x1e959},
    {0x1e95e, 0x1e95f},
    {0x1ec71, 0x1ecb4},
    {0x1ed01, 0x1ed3d},
    {0x1ee00, 0x1ee03},
    {0x1ee05, 0x1ee1f},
    {0x1ee21, 0x1ee22},
    {0x1ee24, 0x1ee24},
    {0x1ee27, 0x1ee27},
    {0x1ee29, 0x1ee32},
    {0x1ee34, 0x1ee37},
    {0x1ee39, 0x1ee39},
    {0x1ee3b, 0x1ee3b},
    {0x1ee42, 0x1ee42},
    {0x1ee47, 0x1ee47},
    {0x1ee49, 0x1ee49},
    {0x1ee4b, 0x1ee4b},
    {0x1ee4d, 0x1ee4f},
    {0x1ee51, 0x1ee52},
    {0x1ee54, 0x1ee54},
    {0x1ee57, 0x1ee57},
    {0x1ee59, 0x1ee59},
    {0x1ee5b, 0x1ee5b},
    {0x1ee5d, 0x1ee5d},
    {0x1ee5f, 0x1ee5f},
    {0x1ee61, 0x1ee62},
    {0x1ee64, 0x1ee64},
    {0x1ee67, 0x1ee6a},
    {0x1ee6c, 0x1ee72},
    {0x1ee74, 0x1ee77},
    {0x1ee79, 0x1ee7c},
    {0x1ee7e, 0x1ee7e},
    {0x1ee80, 0x1ee89},
    {0x1ee8b, 0x1ee9b},
    {0x1eea1, 0x1eea3},
    {0x1eea5, 0x1eea9},
    {0x1eeab, 0x1eebb},
    {0x1eef0, 0x1eef1},
    {0x1f000, 0x1f02b},
    {0x1f030, 0x1f093},
    {0x1f0a0, 0x1f0ae},
    {0x1f0b1, 0x1f0bf},
    {0x1f0c1, 0x1f0cf},
    {0x1f0d1, 0x1f0f5},
    {0x1f100, 0x1f1ad},
    {0x1f1e6, 0x1f202},
    {0x1f210, 0x1f23b},
    {0x1f240, 0x1f248},
    {0x1f250, 0x1f251},
    {0x1f260, 0x1f265},
    {0x1f300, 0x1f6d8},
    {0x1f6dc, 0x1f6ec},
    {0x1f6f0, 0x1f6fc},
    {0x1f700, 0x1f7d9},
    {0x1f7e0, 0x1f7eb},
    {0x1f7f0, 0x1f7f0},
    {0x1f800, 0x1f80b},
    {0x1f810, 0x1f847},
    {0x1f850, 0x1f859},
    {0x1f860, 0x1f887},
    {0x1f890, 0x1f8ad},
    {0x1f8b0, 0x1f8bb},
    {0x1f8c0, 0x1f8c1},
    {0x1f8d0, 0x1f8d8},
    {0x1f900, 0x1fa57},
    {0x1fa60, 0x1fa6d},
    {0x1fa70, 0x1fa7c},
    {0x1fa80, 0x1fa8a},
    {0x1fa8e, 0x1fac6},
    {0x1fac8, 0x1fac8},
    {0x1facd, 0x1fadc},
    {0x1fadf, 0x1faea},
    {0x1faef, 0x1faf8},
    {0x1fb00, 0x1fb92},
    {0x1fb94, 0x1fbfa},
    {0x20000, 0x2a6df},
    {0x2a700, 0x2b81d},
    {0x2b820, 0x2cead},
    {0x2ceb0, 0x2ebe0},
    {0x2ebf0, 0x2ee5d},
    {0x2f800, 0x2fa1d},
    {0x30000, 0x3134a},
    {0x31350, 0x33479},
};
static const int sCodePointsWithOwnCellSuppCount =
    sizeof(sCodePointsWithOwnCellSupp) / sizeof(sCodePointsWithOwnCellSupp[0]);

// ============================================================================
// Initialization
// ============================================================================

static void iTermCharacterSetsInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        memset(&sIgnorableBMP, 0, sizeof(sIgnorableBMP));
        setRange(&sIgnorableBMP, 0xad, 1);
        setRange(&sIgnorableBMP, 0x34f, 1);
        setRange(&sIgnorableBMP, 0x61c, 1);
        setRange(&sIgnorableBMP, 0x115f, 2);
        setRange(&sIgnorableBMP, 0x17b4, 2);
        setRange(&sIgnorableBMP, 0x180b, 5);
        setRange(&sIgnorableBMP, 0x200c, 4);
        setRange(&sIgnorableBMP, 0x202a, 5);
        setRange(&sIgnorableBMP, 0x2060, 16);
        setRange(&sIgnorableBMP, 0x3164, 1);
        setRange(&sIgnorableBMP, 0xfe00, 16);
        setRange(&sIgnorableBMP, 0xfeff, 1);
        setRange(&sIgnorableBMP, 0xffa0, 1);
        setRange(&sIgnorableBMP, 0xfff0, 9);

        memset(&sSpacingCombiningMarksBMP, 0, sizeof(sSpacingCombiningMarksBMP));
        setRange(&sSpacingCombiningMarksBMP, 0x903, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x93b, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x93e, 3);
        setRange(&sSpacingCombiningMarksBMP, 0x949, 4);
        setRange(&sSpacingCombiningMarksBMP, 0x94e, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x982, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x9be, 3);
        setRange(&sSpacingCombiningMarksBMP, 0x9c7, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x9cb, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x9d7, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xa03, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xa3e, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xa83, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xabe, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xac9, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xacb, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xb02, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xb3e, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xb40, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xb47, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xb4b, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xb57, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xbbe, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xbc1, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xbc6, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xbca, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xbd7, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xc01, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xc41, 4);
        setRange(&sSpacingCombiningMarksBMP, 0xc82, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xcbe, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xcc0, 5);
        setRange(&sSpacingCombiningMarksBMP, 0xcc7, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xcca, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xcd5, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xcf3, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xd02, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xd3e, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xd46, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xd4a, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xd57, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xd82, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xdcf, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xdd8, 8);
        setRange(&sSpacingCombiningMarksBMP, 0xdf2, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xf3e, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xf7f, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x102b, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1031, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1038, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x103b, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1056, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1062, 3);
        setRange(&sSpacingCombiningMarksBMP, 0x1067, 7);
        setRange(&sSpacingCombiningMarksBMP, 0x1083, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1087, 6);
        setRange(&sSpacingCombiningMarksBMP, 0x108f, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x109a, 3);
        setRange(&sSpacingCombiningMarksBMP, 0x1715, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1734, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x17b6, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x17be, 8);
        setRange(&sSpacingCombiningMarksBMP, 0x17c7, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1923, 4);
        setRange(&sSpacingCombiningMarksBMP, 0x1929, 3);
        setRange(&sSpacingCombiningMarksBMP, 0x1930, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1933, 6);
        setRange(&sSpacingCombiningMarksBMP, 0x1a19, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1a55, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1a57, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1a61, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1a63, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1a6d, 6);
        setRange(&sSpacingCombiningMarksBMP, 0x1b04, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1b35, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1b3b, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1b3d, 5);
        setRange(&sSpacingCombiningMarksBMP, 0x1b43, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1b82, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1ba1, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1ba6, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1baa, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1be7, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1bea, 3);
        setRange(&sSpacingCombiningMarksBMP, 0x1bee, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1bf2, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1c24, 8);
        setRange(&sSpacingCombiningMarksBMP, 0x1c34, 2);
        setRange(&sSpacingCombiningMarksBMP, 0x1ce1, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x1cf7, 1);
        setRange(&sSpacingCombiningMarksBMP, 0x302e, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xa823, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xa827, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xa880, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xa8b4, 16);
        setRange(&sSpacingCombiningMarksBMP, 0xa952, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xa983, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xa9b4, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xa9ba, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xa9be, 3);
        setRange(&sSpacingCombiningMarksBMP, 0xaa2f, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xaa33, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xaa4d, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xaa7b, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xaa7d, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xaaeb, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xaaee, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xaaf5, 1);
        setRange(&sSpacingCombiningMarksBMP, 0xabe3, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xabe6, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xabe9, 2);
        setRange(&sSpacingCombiningMarksBMP, 0xabec, 1);

        memset(&sEmojiAcceptingVS16BMP, 0, sizeof(sEmojiAcceptingVS16BMP));
        setRange(&sEmojiAcceptingVS16BMP, 0x23, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2a, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x30, 10);
        setRange(&sEmojiAcceptingVS16BMP, 0xa9, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0xae, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x203c, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2049, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2122, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2139, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2194, 6);
        setRange(&sEmojiAcceptingVS16BMP, 0x21a9, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2328, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x23cf, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x23ed, 3);
        setRange(&sEmojiAcceptingVS16BMP, 0x23f1, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x23f8, 3);
        setRange(&sEmojiAcceptingVS16BMP, 0x24c2, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x25aa, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x25b6, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x25c0, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x25fb, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2600, 5);
        setRange(&sEmojiAcceptingVS16BMP, 0x260e, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2611, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2618, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x261d, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2620, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2622, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2626, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x262a, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x262e, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2638, 3);
        setRange(&sEmojiAcceptingVS16BMP, 0x2640, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2642, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x265f, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2663, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2665, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2668, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x267b, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x267e, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2692, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2694, 4);
        setRange(&sEmojiAcceptingVS16BMP, 0x2699, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x269b, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x26a0, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26a7, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26b0, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x26c8, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26cf, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26d1, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26d3, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26e9, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26f0, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x26f4, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x26f7, 3);
        setRange(&sEmojiAcceptingVS16BMP, 0x2702, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2708, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x270c, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x270f, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2712, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2714, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2716, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x271d, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2721, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2733, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2744, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2747, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2763, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x27a1, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x2934, 2);
        setRange(&sEmojiAcceptingVS16BMP, 0x2b05, 3);
        setRange(&sEmojiAcceptingVS16BMP, 0x3030, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x303d, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x3297, 1);
        setRange(&sEmojiAcceptingVS16BMP, 0x3299, 1);

        memset(&sRTLBMP, 0, sizeof(sRTLBMP));
        setRange(&sRTLBMP, 0x5be, 1);
        setRange(&sRTLBMP, 0x5c0, 1);
        setRange(&sRTLBMP, 0x5c3, 1);
        setRange(&sRTLBMP, 0x5c6, 1);
        setRange(&sRTLBMP, 0x5d0, 27);
        setRange(&sRTLBMP, 0x5ef, 6);
        setRange(&sRTLBMP, 0x600, 6);
        setRange(&sRTLBMP, 0x608, 1);
        setRange(&sRTLBMP, 0x60b, 1);
        setRange(&sRTLBMP, 0x60d, 1);
        setRange(&sRTLBMP, 0x61b, 48);
        setRange(&sRTLBMP, 0x660, 10);
        setRange(&sRTLBMP, 0x66b, 5);
        setRange(&sRTLBMP, 0x671, 101);
        setRange(&sRTLBMP, 0x6dd, 1);
        setRange(&sRTLBMP, 0x6e5, 2);
        setRange(&sRTLBMP, 0x6ee, 2);
        setRange(&sRTLBMP, 0x6fa, 20);
        setRange(&sRTLBMP, 0x70f, 2);
        setRange(&sRTLBMP, 0x712, 30);
        setRange(&sRTLBMP, 0x74d, 89);
        setRange(&sRTLBMP, 0x7b1, 1);
        setRange(&sRTLBMP, 0x7c0, 43);
        setRange(&sRTLBMP, 0x7f4, 2);
        setRange(&sRTLBMP, 0x7fa, 1);
        setRange(&sRTLBMP, 0x7fe, 24);
        setRange(&sRTLBMP, 0x81a, 1);
        setRange(&sRTLBMP, 0x824, 1);
        setRange(&sRTLBMP, 0x828, 1);
        setRange(&sRTLBMP, 0x830, 15);
        setRange(&sRTLBMP, 0x840, 25);
        setRange(&sRTLBMP, 0x85e, 1);
        setRange(&sRTLBMP, 0x860, 11);
        setRange(&sRTLBMP, 0x870, 34);
        setRange(&sRTLBMP, 0x8a0, 42);
        setRange(&sRTLBMP, 0x8e2, 1);
        setRange(&sRTLBMP, 0x200f, 1);
        setRange(&sRTLBMP, 0x202a, 5);
        setRange(&sRTLBMP, 0x2066, 4);
        setRange(&sRTLBMP, 0xfb1d, 1);
        setRange(&sRTLBMP, 0xfb1f, 10);
        setRange(&sRTLBMP, 0xfb2a, 13);
        setRange(&sRTLBMP, 0xfb38, 5);
        setRange(&sRTLBMP, 0xfb3e, 1);
        setRange(&sRTLBMP, 0xfb40, 2);
        setRange(&sRTLBMP, 0xfb43, 2);
        setRange(&sRTLBMP, 0xfb46, 125);
        setRange(&sRTLBMP, 0xfbd3, 363);
        setRange(&sRTLBMP, 0xfd50, 64);
        setRange(&sRTLBMP, 0xfd92, 54);
        setRange(&sRTLBMP, 0xfdf0, 13);
        setRange(&sRTLBMP, 0xfe70, 5);
        setRange(&sRTLBMP, 0xfe76, 135);

        memset(&sCodePointsWithOwnCellBMP, 0, sizeof(sCodePointsWithOwnCellBMP));
        setRange(&sCodePointsWithOwnCellBMP, 0x20, 95);
        setRange(&sCodePointsWithOwnCellBMP, 0xa0, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0xae, 594);
        setRange(&sCodePointsWithOwnCellBMP, 0x370, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0x37a, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x384, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x38c, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x38e, 20);
        setRange(&sCodePointsWithOwnCellBMP, 0x3a3, 224);
        setRange(&sCodePointsWithOwnCellBMP, 0x48a, 166);
        setRange(&sCodePointsWithOwnCellBMP, 0x531, 38);
        setRange(&sCodePointsWithOwnCellBMP, 0x559, 50);
        setRange(&sCodePointsWithOwnCellBMP, 0x58d, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x5be, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x5c0, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x5c3, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x5c6, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x5d0, 27);
        setRange(&sCodePointsWithOwnCellBMP, 0x5ef, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x606, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x61b, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x61d, 46);
        setRange(&sCodePointsWithOwnCellBMP, 0x660, 16);
        setRange(&sCodePointsWithOwnCellBMP, 0x671, 101);
        setRange(&sCodePointsWithOwnCellBMP, 0x6de, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x6e5, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x6e9, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x6ee, 32);
        setRange(&sCodePointsWithOwnCellBMP, 0x710, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x712, 30);
        setRange(&sCodePointsWithOwnCellBMP, 0x74d, 89);
        setRange(&sCodePointsWithOwnCellBMP, 0x7b1, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x7c0, 43);
        setRange(&sCodePointsWithOwnCellBMP, 0x7f4, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x7fe, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0x81a, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x824, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x828, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x830, 15);
        setRange(&sCodePointsWithOwnCellBMP, 0x840, 25);
        setRange(&sCodePointsWithOwnCellBMP, 0x85e, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x860, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0x870, 32);
        setRange(&sCodePointsWithOwnCellBMP, 0x8a0, 42);
        setRange(&sCodePointsWithOwnCellBMP, 0x903, 55);
        setRange(&sCodePointsWithOwnCellBMP, 0x93b, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x93d, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x949, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x94e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x958, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x964, 29);
        setRange(&sCodePointsWithOwnCellBMP, 0x982, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x985, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0x98f, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x993, 22);
        setRange(&sCodePointsWithOwnCellBMP, 0x9aa, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x9b2, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x9b6, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x9bd, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x9c7, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x9cb, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x9ce, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x9d7, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x9dc, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x9df, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x9e6, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0xa03, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xa05, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xa0f, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa13, 22);
        setRange(&sCodePointsWithOwnCellBMP, 0xa2a, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xa32, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa35, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa38, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa3e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xa59, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xa5e, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xa66, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xa72, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xa76, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xa83, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xa85, 9);
        setRange(&sCodePointsWithOwnCellBMP, 0xa8f, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xa93, 22);
        setRange(&sCodePointsWithOwnCellBMP, 0xaaa, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xab2, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xab5, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xabd, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xac9, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xacb, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xad0, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xae0, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xae6, 12);
        setRange(&sCodePointsWithOwnCellBMP, 0xaf9, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xb02, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb05, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xb0f, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb13, 22);
        setRange(&sCodePointsWithOwnCellBMP, 0xb2a, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xb32, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb35, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xb3d, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb40, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xb47, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb4b, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb57, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xb5c, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb5f, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xb66, 18);
        setRange(&sCodePointsWithOwnCellBMP, 0xb83, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xb85, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xb8e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xb92, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xb99, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xb9c, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xb9e, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xba3, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xba8, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xbae, 12);
        setRange(&sCodePointsWithOwnCellBMP, 0xbbe, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xbc1, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xbc6, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xbca, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xbd0, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xbd7, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xbe6, 21);
        setRange(&sCodePointsWithOwnCellBMP, 0xc01, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xc05, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xc0e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xc12, 23);
        setRange(&sCodePointsWithOwnCellBMP, 0xc2a, 16);
        setRange(&sCodePointsWithOwnCellBMP, 0xc3d, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xc41, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xc58, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xc5c, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xc60, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xc66, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xc77, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xc82, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0xc8e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xc92, 23);
        setRange(&sCodePointsWithOwnCellBMP, 0xcaa, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xcb5, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xcbd, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xcc0, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xcc7, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xcca, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xcd5, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xcdc, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xce0, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xce6, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xcf1, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xd02, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0xd0e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xd12, 41);
        setRange(&sCodePointsWithOwnCellBMP, 0xd3d, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xd46, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xd4a, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xd4e, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xd54, 14);
        setRange(&sCodePointsWithOwnCellBMP, 0xd66, 26);
        setRange(&sCodePointsWithOwnCellBMP, 0xd82, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xd85, 18);
        setRange(&sCodePointsWithOwnCellBMP, 0xd9a, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0xdb3, 9);
        setRange(&sCodePointsWithOwnCellBMP, 0xdbd, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xdc0, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xdcf, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xdd8, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xde6, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xdf2, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xe01, 48);
        setRange(&sCodePointsWithOwnCellBMP, 0xe32, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xe3f, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xe4f, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0xe81, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xe84, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xe86, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xe8c, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0xea5, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xea7, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xeb2, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xebd, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xec0, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xec6, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xed0, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xedc, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xf00, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0xf1a, 27);
        setRange(&sCodePointsWithOwnCellBMP, 0xf36, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xf38, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xf3a, 14);
        setRange(&sCodePointsWithOwnCellBMP, 0xf49, 36);
        setRange(&sCodePointsWithOwnCellBMP, 0xf7f, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xf85, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xf88, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xfbe, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xfc7, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xfce, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0x1000, 45);
        setRange(&sCodePointsWithOwnCellBMP, 0x1031, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1038, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x103b, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x103f, 25);
        setRange(&sCodePointsWithOwnCellBMP, 0x105a, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1061, 16);
        setRange(&sCodePointsWithOwnCellBMP, 0x1075, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0x1083, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1087, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x108e, 15);
        setRange(&sCodePointsWithOwnCellBMP, 0x109e, 40);
        setRange(&sCodePointsWithOwnCellBMP, 0x10c7, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x10cd, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x10d0, 143);
        setRange(&sCodePointsWithOwnCellBMP, 0x1161, 232);
        setRange(&sCodePointsWithOwnCellBMP, 0x124a, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1250, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x1258, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x125a, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1260, 41);
        setRange(&sCodePointsWithOwnCellBMP, 0x128a, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1290, 33);
        setRange(&sCodePointsWithOwnCellBMP, 0x12b2, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x12b8, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x12c0, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x12c2, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x12c8, 15);
        setRange(&sCodePointsWithOwnCellBMP, 0x12d8, 57);
        setRange(&sCodePointsWithOwnCellBMP, 0x1312, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1318, 67);
        setRange(&sCodePointsWithOwnCellBMP, 0x1360, 29);
        setRange(&sCodePointsWithOwnCellBMP, 0x1380, 26);
        setRange(&sCodePointsWithOwnCellBMP, 0x13a0, 86);
        setRange(&sCodePointsWithOwnCellBMP, 0x13f8, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1400, 669);
        setRange(&sCodePointsWithOwnCellBMP, 0x16a0, 89);
        setRange(&sCodePointsWithOwnCellBMP, 0x1700, 18);
        setRange(&sCodePointsWithOwnCellBMP, 0x1715, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x171f, 19);
        setRange(&sCodePointsWithOwnCellBMP, 0x1734, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x1740, 18);
        setRange(&sCodePointsWithOwnCellBMP, 0x1760, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0x176e, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x1780, 52);
        setRange(&sCodePointsWithOwnCellBMP, 0x17b6, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x17be, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0x17c7, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x17d4, 9);
        setRange(&sCodePointsWithOwnCellBMP, 0x17e0, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x17f0, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x1800, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0x1810, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x1820, 89);
        setRange(&sCodePointsWithOwnCellBMP, 0x1880, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0x1887, 34);
        setRange(&sCodePointsWithOwnCellBMP, 0x18aa, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x18b0, 70);
        setRange(&sCodePointsWithOwnCellBMP, 0x1900, 31);
        setRange(&sCodePointsWithOwnCellBMP, 0x1923, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1929, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x1930, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1933, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1940, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1944, 42);
        setRange(&sCodePointsWithOwnCellBMP, 0x1970, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0x1980, 44);
        setRange(&sCodePointsWithOwnCellBMP, 0x19b0, 26);
        setRange(&sCodePointsWithOwnCellBMP, 0x19d0, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0x19de, 57);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a19, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a1e, 56);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a57, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a61, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a63, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a6d, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a80, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x1a90, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x1aa0, 14);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b04, 48);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b35, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b3b, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b3d, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b43, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b4e, 29);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b74, 12);
        setRange(&sCodePointsWithOwnCellBMP, 0x1b82, 32);
        setRange(&sCodePointsWithOwnCellBMP, 0x1ba6, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1baa, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1bae, 56);
        setRange(&sCodePointsWithOwnCellBMP, 0x1be7, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1bea, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x1bee, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1bf2, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1bfc, 48);
        setRange(&sCodePointsWithOwnCellBMP, 0x1c34, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x1c3b, 15);
        setRange(&sCodePointsWithOwnCellBMP, 0x1c4d, 62);
        setRange(&sCodePointsWithOwnCellBMP, 0x1c90, 43);
        setRange(&sCodePointsWithOwnCellBMP, 0x1cbd, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0x1cd3, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1ce1, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1ce9, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0x1cee, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1cf5, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x1cfa, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1d00, 192);
        setRange(&sCodePointsWithOwnCellBMP, 0x1e00, 278);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f18, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f20, 38);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f48, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f50, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f59, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f5b, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f5d, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f5f, 31);
        setRange(&sCodePointsWithOwnCellBMP, 0x1f80, 53);
        setRange(&sCodePointsWithOwnCellBMP, 0x1fb6, 15);
        setRange(&sCodePointsWithOwnCellBMP, 0x1fc6, 14);
        setRange(&sCodePointsWithOwnCellBMP, 0x1fd6, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0x1fdd, 19);
        setRange(&sCodePointsWithOwnCellBMP, 0x1ff2, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0x1ff6, 9);
        setRange(&sCodePointsWithOwnCellBMP, 0x2000, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0x2010, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0x202f, 49);
        setRange(&sCodePointsWithOwnCellBMP, 0x2070, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x2074, 27);
        setRange(&sCodePointsWithOwnCellBMP, 0x2090, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0x20a0, 34);
        setRange(&sCodePointsWithOwnCellBMP, 0x2100, 140);
        setRange(&sCodePointsWithOwnCellBMP, 0x2190, 666);
        setRange(&sCodePointsWithOwnCellBMP, 0x2440, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0x2460, 1812);
        setRange(&sCodePointsWithOwnCellBMP, 0x2b76, 377);
        setRange(&sCodePointsWithOwnCellBMP, 0x2cf2, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x2cf9, 45);
        setRange(&sCodePointsWithOwnCellBMP, 0x2d27, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x2d2d, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0x2d30, 56);
        setRange(&sCodePointsWithOwnCellBMP, 0x2d6f, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0x2d80, 23);
        setRange(&sCodePointsWithOwnCellBMP, 0x2da0, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2da8, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2db0, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2db8, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2dc0, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2dc8, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2dd0, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2dd8, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0x2e00, 94);
        setRange(&sCodePointsWithOwnCellBMP, 0x2e80, 26);
        setRange(&sCodePointsWithOwnCellBMP, 0x2e9b, 89);
        setRange(&sCodePointsWithOwnCellBMP, 0x2f00, 214);
        setRange(&sCodePointsWithOwnCellBMP, 0x2ff0, 58);
        setRange(&sCodePointsWithOwnCellBMP, 0x302e, 18);
        setRange(&sCodePointsWithOwnCellBMP, 0x3041, 86);
        setRange(&sCodePointsWithOwnCellBMP, 0x309b, 101);
        setRange(&sCodePointsWithOwnCellBMP, 0x3105, 43);
        setRange(&sCodePointsWithOwnCellBMP, 0x3131, 51);
        setRange(&sCodePointsWithOwnCellBMP, 0x3165, 42);
        setRange(&sCodePointsWithOwnCellBMP, 0x3190, 86);
        setRange(&sCodePointsWithOwnCellBMP, 0x31ef, 48);
        setRange(&sCodePointsWithOwnCellBMP, 0x3220, 29293);
        setRange(&sCodePointsWithOwnCellBMP, 0xa490, 55);
        setRange(&sCodePointsWithOwnCellBMP, 0xa4d0, 348);
        setRange(&sCodePointsWithOwnCellBMP, 0xa640, 47);
        setRange(&sCodePointsWithOwnCellBMP, 0xa673, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xa67e, 32);
        setRange(&sCodePointsWithOwnCellBMP, 0xa6a0, 80);
        setRange(&sCodePointsWithOwnCellBMP, 0xa6f2, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xa700, 221);
        setRange(&sCodePointsWithOwnCellBMP, 0xa7f1, 17);
        setRange(&sCodePointsWithOwnCellBMP, 0xa803, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xa807, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xa80c, 25);
        setRange(&sCodePointsWithOwnCellBMP, 0xa827, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xa830, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xa840, 56);
        setRange(&sCodePointsWithOwnCellBMP, 0xa880, 68);
        setRange(&sCodePointsWithOwnCellBMP, 0xa8ce, 12);
        setRange(&sCodePointsWithOwnCellBMP, 0xa8f2, 13);
        setRange(&sCodePointsWithOwnCellBMP, 0xa900, 38);
        setRange(&sCodePointsWithOwnCellBMP, 0xa92e, 25);
        setRange(&sCodePointsWithOwnCellBMP, 0xa952, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa95f, 30);
        setRange(&sCodePointsWithOwnCellBMP, 0xa983, 48);
        setRange(&sCodePointsWithOwnCellBMP, 0xa9b4, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa9ba, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xa9be, 16);
        setRange(&sCodePointsWithOwnCellBMP, 0xa9cf, 11);
        setRange(&sCodePointsWithOwnCellBMP, 0xa9de, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xa9e6, 25);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa00, 41);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa2f, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa33, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa40, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa44, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa4d, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa50, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa5c, 32);
        setRange(&sCodePointsWithOwnCellBMP, 0xaa7d, 51);
        setRange(&sCodePointsWithOwnCellBMP, 0xaab1, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xaab5, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xaab9, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xaac0, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xaac2, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xaadb, 17);
        setRange(&sCodePointsWithOwnCellBMP, 0xaaee, 8);
        setRange(&sCodePointsWithOwnCellBMP, 0xab01, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xab09, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xab11, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xab20, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xab28, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xab30, 60);
        setRange(&sCodePointsWithOwnCellBMP, 0xab70, 117);
        setRange(&sCodePointsWithOwnCellBMP, 0xabe6, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xabe9, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xabf0, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xac00, 11172);
        setRange(&sCodePointsWithOwnCellBMP, 0xd7b0, 23);
        setRange(&sCodePointsWithOwnCellBMP, 0xd7cb, 49);
        setRange(&sCodePointsWithOwnCellBMP, 0xf900, 366);
        setRange(&sCodePointsWithOwnCellBMP, 0xfa70, 106);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb00, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb13, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb1d, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb1f, 24);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb38, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb3e, 1);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb40, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb43, 2);
        setRange(&sCodePointsWithOwnCellBMP, 0xfb46, 650);
        setRange(&sCodePointsWithOwnCellBMP, 0xfdf0, 16);
        setRange(&sCodePointsWithOwnCellBMP, 0xfe10, 10);
        setRange(&sCodePointsWithOwnCellBMP, 0xfe30, 35);
        setRange(&sCodePointsWithOwnCellBMP, 0xfe54, 19);
        setRange(&sCodePointsWithOwnCellBMP, 0xfe68, 4);
        setRange(&sCodePointsWithOwnCellBMP, 0xfe70, 5);
        setRange(&sCodePointsWithOwnCellBMP, 0xfe76, 135);
        setRange(&sCodePointsWithOwnCellBMP, 0xff01, 159);
        setRange(&sCodePointsWithOwnCellBMP, 0xffa1, 30);
        setRange(&sCodePointsWithOwnCellBMP, 0xffc2, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xffca, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xffd2, 6);
        setRange(&sCodePointsWithOwnCellBMP, 0xffda, 3);
        setRange(&sCodePointsWithOwnCellBMP, 0xffe0, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xffe8, 7);
        setRange(&sCodePointsWithOwnCellBMP, 0xfffc, 2);
    });
}

// ============================================================================
// Query functions
// ============================================================================

BOOL iTermIsIgnorableCharacter(uint32_t cp, BOOL zeroWidthSpaceAdvancesCursor) {
    iTermCharacterSetsInit();
    if (cp == 0x200b) {
        return !zeroWidthSpaceAdvancesCursor;
    }
    if (cp < 0x10000) {
        return testBit(&sIgnorableBMP, cp);
    }
    return inRanges(cp, sIgnorableSupp, sIgnorableSuppCount);
}

BOOL iTermIsSpacingCombiningMark(uint32_t cp) {
    iTermCharacterSetsInit();
    if (cp < 0x10000) {
        return testBit(&sSpacingCombiningMarksBMP, cp);
    }
    return inRanges(cp, sSpacingCombiningMarksSupp, sSpacingCombiningMarksSuppCount);
}

BOOL iTermIsEmojiAcceptingVS16(uint32_t cp) {
    iTermCharacterSetsInit();
    if (cp < 0x10000) {
        return testBit(&sEmojiAcceptingVS16BMP, cp);
    }
    return inRanges(cp, sEmojiAcceptingVS16Supp, sEmojiAcceptingVS16SuppCount);
}

BOOL iTermIsRTLCodePoint(uint32_t cp) {
    iTermCharacterSetsInit();
    if (cp < 0x10000) {
        return testBit(&sRTLBMP, cp);
    }
    return inRanges(cp, sRTLSupp, sRTLSuppCount);
}

BOOL iTermIsCodePointWithOwnCell(uint32_t cp) {
    iTermCharacterSetsInit();
    if (cp < 0x10000) {
        return testBit(&sCodePointsWithOwnCellBMP, cp);
    }
    return inRanges(cp, sCodePointsWithOwnCellSupp, sCodePointsWithOwnCellSuppCount);
}

// ============================================================================
// String scanning functions
// ============================================================================

// Decode a UTF-16 code unit at position i, advancing i past the character.
NS_INLINE uint32_t decodeUTF16(const UniChar *chars, CFIndex len, CFIndex *i) {
    UniChar c = chars[*i];
    if (c >= 0xD800 && c <= 0xDBFF && *i + 1 < len) {
        UniChar low = chars[*i + 1];
        if (low >= 0xDC00 && low <= 0xDFFF) {
            *i += 2;
            return 0x10000 + ((uint32_t)(c - 0xD800) << 10) + (low - 0xDC00);
        }
    }
    *i += 1;
    return c;
}

BOOL iTermStringContainsRTL(CFStringRef s) {
    iTermCharacterSetsInit();
    CFIndex len = CFStringGetLength(s);
    if (len == 0) return NO;

    const UniChar *chars = CFStringGetCharactersPtr(s);
    UniChar stackBuf[256];

    if (chars) {
        // Fast path: direct pointer to UTF-16 buffer
        for (CFIndex i = 0; i < len;) {
            UniChar c = chars[i];
            // Fast skip for ASCII/Latin (below first RTL range at 0x5BE)
            if (c < 0x5be) {
                i++;
                continue;
            }
            uint32_t cp = decodeUTF16(chars, len, &i);
            if (iTermIsRTLCodePoint(cp)) return YES;
        }
    } else {
        // Fallback: copy chunks into stack buffer
        CFIndex remaining = len;
        CFIndex offset = 0;
        while (remaining > 0) {
            CFIndex chunk = remaining > 256 ? 256 : remaining;
            CFStringGetCharacters(s, CFRangeMake(offset, chunk), stackBuf);
            for (CFIndex i = 0; i < chunk;) {
                UniChar c = stackBuf[i];
                if (c < 0x5be) {
                    i++;
                    continue;
                }
                uint32_t cp = decodeUTF16(stackBuf, chunk, &i);
                if (iTermIsRTLCodePoint(cp)) return YES;
            }
            offset += chunk;
            remaining -= chunk;
        }
    }
    return NO;
}

BOOL iTermStringContainsSpacingCombiningMark(CFStringRef s) {
    iTermCharacterSetsInit();
    CFIndex len = CFStringGetLength(s);
    if (len == 0) return NO;

    const UniChar *chars = CFStringGetCharactersPtr(s);
    UniChar stackBuf[64];

    if (!chars) {
        if (len > 64) len = 64;
        CFStringGetCharacters(s, CFRangeMake(0, len), stackBuf);
        chars = stackBuf;
    }

    for (CFIndex i = 0; i < len;) {
        uint32_t cp = decodeUTF16(chars, len, &i);
        if (cp < 0x10000) {
            if (testBit(&sSpacingCombiningMarksBMP, cp)) return YES;
        } else {
            if (inRanges(cp, sSpacingCombiningMarksSupp, sSpacingCombiningMarksSuppCount)) return YES;
        }
    }
    return NO;
}

BOOL iTermStringContainsModifierForcingFullWidth(CFStringRef s) {
    CFIndex len = CFStringGetLength(s);
    if (len == 0) return NO;

    // Skin tone modifiers in UTF-16: high=0xD83C, low=0xDFFB..0xDFFF
    const UniChar *chars = CFStringGetCharactersPtr(s);
    UniChar stackBuf[64];  // composed strings are short

    if (!chars) {
        if (len > 64) len = 64;
        CFStringGetCharacters(s, CFRangeMake(0, len), stackBuf);
        chars = stackBuf;
    }

    for (CFIndex i = 0; i < len; i++) {
        if (chars[i] == 0xFE0F) return YES;
        if (chars[i] == 0xD83C && i + 1 < len &&
            chars[i + 1] >= 0xDFFB && chars[i + 1] <= 0xDFFF) {
            return YES;
        }
    }
    return NO;
}

CFIndex iTermFindFirstCodePointWithOwnCell(const UniChar *chars,
                                           CFIndex start,
                                           CFIndex length,
                                           BOOL aggressive) {
    iTermCharacterSetsInit();
    CFIndex end = start + length;
    if (!aggressive) {
        // Only check for 0xFF9E and 0xFF9F (halfwidth katakana voiced sound marks)
        for (CFIndex i = start; i < end; i++) {
            if (chars[i] == 0xFF9E || chars[i] == 0xFF9F) {
                return i;
            }
        }
        return kCFNotFound;
    }
    for (CFIndex i = start; i < end;) {
        UniChar c = chars[i];
        // Fast path: most BMP characters
        if (c < 0xD800 || c > 0xDBFF) {
            if (testBit(&sCodePointsWithOwnCellBMP, c)) {
                return i;
            }
            i++;
        } else if (i + 1 < end) {
            // Surrogate pair
            UniChar low = chars[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                uint32_t cp = 0x10000 + ((uint32_t)(c - 0xD800) << 10) + (low - 0xDC00);
                if (inRanges(cp, sCodePointsWithOwnCellSupp, sCodePointsWithOwnCellSuppCount)) {
                    return i;
                }
                i += 2;
            } else {
                i++;
            }
        } else {
            i++;
        }
    }
    return kCFNotFound;
}
