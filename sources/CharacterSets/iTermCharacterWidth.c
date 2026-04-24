//
//  iTermCharacterWidth.c
//  iTerm2
//
//  Fast character width determination using bitmaps and binary search.
//

#include "iTermCharacterWidth.h"
#include <string.h>
#include <stdatomic.h>

// Bitmap for BMP characters (0-0xFFFF): 8KB per set
typedef struct {
    uint64_t bits[1024];  // 65536 bits = 1024 * 64
} BMPBitmap;

// Range for supplementary plane characters
typedef struct {
    uint32_t start;
    uint32_t end;  // inclusive
} CharRange;

// Static bitmaps (initialized once)
static BMPBitmap sFullWidthBMP8;
static BMPBitmap sFullWidthBMP9;
static BMPBitmap sAmbiguousBMP8;
static BMPBitmap sAmbiguousBMP9;

// Supplementary plane ranges for full-width Unicode 8
static const CharRange sFullWidthSupp8[] = {
    {0x1b000, 0x1b001},
    {0x1f200, 0x1f202},
    {0x1f210, 0x1f23a},
    {0x1f240, 0x1f248},
    {0x1f250, 0x1f251},
    {0x20000, 0x2fffd},
    {0x30000, 0x3fffd},
};
static const int sFullWidthSupp8Count = sizeof(sFullWidthSupp8) / sizeof(sFullWidthSupp8[0]);

// Supplementary plane ranges for full-width Unicode 9
// Generated from Unicode 17.0.0 by tools/eastasian.py
static const CharRange sFullWidthSupp9[] = {
    {0x16fe0, 0x16fe4},
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
    {0x1d300, 0x1d356},
    {0x1d360, 0x1d376},
    {0x1f004, 0x1f004},
    {0x1f0cf, 0x1f0cf},
    {0x1f18e, 0x1f18e},
    {0x1f191, 0x1f19a},
    {0x1f200, 0x1f202},
    {0x1f210, 0x1f23b},
    {0x1f240, 0x1f248},
    {0x1f250, 0x1f251},
    {0x1f260, 0x1f265},
    {0x1f300, 0x1f320},
    {0x1f32d, 0x1f335},
    {0x1f337, 0x1f37c},
    {0x1f37e, 0x1f393},
    {0x1f3a0, 0x1f3ca},
    {0x1f3cf, 0x1f3d3},
    {0x1f3e0, 0x1f3f0},
    {0x1f3f4, 0x1f3f4},
    {0x1f3f8, 0x1f43e},
    {0x1f440, 0x1f440},
    {0x1f442, 0x1f4fc},
    {0x1f4ff, 0x1f53d},
    {0x1f54b, 0x1f54e},
    {0x1f550, 0x1f567},
    {0x1f57a, 0x1f57a},
    {0x1f595, 0x1f596},
    {0x1f5a4, 0x1f5a4},
    {0x1f5fb, 0x1f64f},
    {0x1f680, 0x1f6c5},
    {0x1f6cc, 0x1f6cc},
    {0x1f6d0, 0x1f6d2},
    {0x1f6d5, 0x1f6d8},
    {0x1f6dc, 0x1f6df},
    {0x1f6eb, 0x1f6ec},
    {0x1f6f4, 0x1f6fc},
    {0x1f7e0, 0x1f7eb},
    {0x1f7f0, 0x1f7f0},
    {0x1f90c, 0x1f93a},
    {0x1f93c, 0x1f945},
    {0x1f947, 0x1f9ff},
    {0x1fa70, 0x1fa7c},
    {0x1fa80, 0x1fa8a},
    {0x1fa8e, 0x1fac6},
    {0x1fac8, 0x1fac8},
    {0x1facd, 0x1fadc},
    {0x1fadf, 0x1faea},
    {0x1faef, 0x1faf8},
    {0x20000, 0x2fffd},
    {0x30000, 0x3fffd},
};
static const int sFullWidthSupp9Count = sizeof(sFullWidthSupp9) / sizeof(sFullWidthSupp9[0]);

// Supplementary plane ranges for ambiguous Unicode 8
static const CharRange sAmbiguousSupp8[] = {
    {0x1f100, 0x1f10a},
    {0x1f110, 0x1f12d},
    {0x1f130, 0x1f169},
    {0x1f170, 0x1f19a},
    {0xe0100, 0xe01ef},
    {0xf0000, 0xffffd},
    {0x100000, 0x10fffd},
};
static const int sAmbiguousSupp8Count = sizeof(sAmbiguousSupp8) / sizeof(sAmbiguousSupp8[0]);

// Supplementary plane ranges for ambiguous Unicode 9
// Generated from Unicode 17.0.0 by tools/eastasian.py
static const CharRange sAmbiguousSupp9[] = {
    {0x1f100, 0x1f10a},
    {0x1f110, 0x1f12d},
    {0x1f130, 0x1f169},
    {0x1f170, 0x1f18d},
    {0x1f18f, 0x1f190},
    {0x1f19b, 0x1f1ac},
    {0xe0100, 0xe01ef},
    {0xf0000, 0xffffd},
    {0x100000, 0x10fffd},
};
static const int sAmbiguousSupp9Count = sizeof(sAmbiguousSupp9) / sizeof(sAmbiguousSupp9[0]);

// Flag character ranges (version 9+)
static const CharRange sFlagRanges[] = {
    {0x1F1E6, 0x1F1FF},  // Regional indicator symbols
    {0x1F3F4, 0x1F3F4},  // Black flag (tag sequences)
};
static const int sFlagRangesCount = sizeof(sFlagRanges) / sizeof(sFlagRanges[0]);

// Initialization flag
static atomic_int sInitialized = 0;

// Helper to set a bit in a bitmap
static inline void setBit(BMPBitmap *bmp, uint32_t cp) {
    if (cp < 0x10000) {
        bmp->bits[cp >> 6] |= (1ULL << (cp & 63));
    }
}

// Helper to set a range of bits in a bitmap
static void setBitRange(BMPBitmap *bmp, uint32_t start, uint32_t end) {
    for (uint32_t cp = start; cp <= end && cp < 0x10000; cp++) {
        setBit(bmp, cp);
    }
}

// Helper to check if a bit is set
static inline bool testBit(const BMPBitmap *bmp, uint32_t cp) {
    return (bmp->bits[cp >> 6] & (1ULL << (cp & 63))) != 0;
}

// Binary search for supplementary plane characters
static bool inRanges(uint32_t cp, const CharRange *ranges, int count) {
    int lo = 0, hi = count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (cp < ranges[mid].start) {
            hi = mid - 1;
        } else if (cp > ranges[mid].end) {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

// Initialize full-width bitmap for Unicode 8
static void initFullWidth8(void) {
    memset(&sFullWidthBMP8, 0, sizeof(sFullWidthBMP8));

    setBitRange(&sFullWidthBMP8, 0x1100, 0x115f);
    setBitRange(&sFullWidthBMP8, 0x11a3, 0x11a7);
    setBitRange(&sFullWidthBMP8, 0x11fa, 0x11ff);
    setBitRange(&sFullWidthBMP8, 0x2329, 0x232a);
    setBitRange(&sFullWidthBMP8, 0x2e80, 0x2e99);
    setBitRange(&sFullWidthBMP8, 0x2e9b, 0x2ef3);
    setBitRange(&sFullWidthBMP8, 0x2f00, 0x2fd5);
    setBitRange(&sFullWidthBMP8, 0x2ff0, 0x2ffb);
    setBitRange(&sFullWidthBMP8, 0x3000, 0x303e);
    setBitRange(&sFullWidthBMP8, 0x3041, 0x3096);
    setBitRange(&sFullWidthBMP8, 0x3099, 0x30ff);
    setBitRange(&sFullWidthBMP8, 0x3105, 0x312d);
    setBitRange(&sFullWidthBMP8, 0x3131, 0x318e);
    setBitRange(&sFullWidthBMP8, 0x3190, 0x31ba);
    setBitRange(&sFullWidthBMP8, 0x31c0, 0x31e3);
    setBitRange(&sFullWidthBMP8, 0x31f0, 0x321e);
    setBitRange(&sFullWidthBMP8, 0x3220, 0x3247);
    setBitRange(&sFullWidthBMP8, 0x3250, 0x32fe);
    setBitRange(&sFullWidthBMP8, 0x3300, 0x4dbf);
    setBitRange(&sFullWidthBMP8, 0x4e00, 0xa48c);
    setBitRange(&sFullWidthBMP8, 0xa490, 0xa4c6);
    setBitRange(&sFullWidthBMP8, 0xa960, 0xa97c);
    setBitRange(&sFullWidthBMP8, 0xac00, 0xd7a3);
    setBitRange(&sFullWidthBMP8, 0xd7b0, 0xd7c6);
    setBitRange(&sFullWidthBMP8, 0xd7cb, 0xd7fb);
    setBitRange(&sFullWidthBMP8, 0xf900, 0xfaff);
    setBitRange(&sFullWidthBMP8, 0xfe10, 0xfe19);
    setBitRange(&sFullWidthBMP8, 0xfe30, 0xfe52);
    setBitRange(&sFullWidthBMP8, 0xfe54, 0xfe66);
    setBitRange(&sFullWidthBMP8, 0xfe68, 0xfe6b);
    setBitRange(&sFullWidthBMP8, 0xff01, 0xff60);
    setBitRange(&sFullWidthBMP8, 0xffe0, 0xffe6);
}

// Initialize full-width bitmap for Unicode 9
// Generated from Unicode 17.0.0 by tools/eastasian.py
static void initFullWidth9(void) {
    memset(&sFullWidthBMP9, 0, sizeof(sFullWidthBMP9));

    setBitRange(&sFullWidthBMP9, 0x1100, 0x115f);
    setBitRange(&sFullWidthBMP9, 0x231a, 0x231b);
    setBitRange(&sFullWidthBMP9, 0x2329, 0x232a);
    setBitRange(&sFullWidthBMP9, 0x23e9, 0x23ec);
    setBit(&sFullWidthBMP9, 0x23f0);
    setBit(&sFullWidthBMP9, 0x23f3);
    setBitRange(&sFullWidthBMP9, 0x25fd, 0x25fe);
    setBitRange(&sFullWidthBMP9, 0x2614, 0x2615);
    setBitRange(&sFullWidthBMP9, 0x2630, 0x2637);
    setBitRange(&sFullWidthBMP9, 0x2648, 0x2653);
    setBit(&sFullWidthBMP9, 0x267f);
    setBitRange(&sFullWidthBMP9, 0x268a, 0x268f);
    setBit(&sFullWidthBMP9, 0x2693);
    setBit(&sFullWidthBMP9, 0x26a1);
    setBitRange(&sFullWidthBMP9, 0x26aa, 0x26ab);
    setBitRange(&sFullWidthBMP9, 0x26bd, 0x26be);
    setBitRange(&sFullWidthBMP9, 0x26c4, 0x26c5);
    setBit(&sFullWidthBMP9, 0x26ce);
    setBit(&sFullWidthBMP9, 0x26d4);
    setBit(&sFullWidthBMP9, 0x26ea);
    setBitRange(&sFullWidthBMP9, 0x26f2, 0x26f3);
    setBit(&sFullWidthBMP9, 0x26f5);
    setBit(&sFullWidthBMP9, 0x26fa);
    setBit(&sFullWidthBMP9, 0x26fd);
    setBit(&sFullWidthBMP9, 0x2705);
    setBitRange(&sFullWidthBMP9, 0x270a, 0x270b);
    setBit(&sFullWidthBMP9, 0x2728);
    setBit(&sFullWidthBMP9, 0x274c);
    setBit(&sFullWidthBMP9, 0x274e);
    setBitRange(&sFullWidthBMP9, 0x2753, 0x2755);
    setBit(&sFullWidthBMP9, 0x2757);
    setBitRange(&sFullWidthBMP9, 0x2795, 0x2797);
    setBit(&sFullWidthBMP9, 0x27b0);
    setBit(&sFullWidthBMP9, 0x27bf);
    setBitRange(&sFullWidthBMP9, 0x2b1b, 0x2b1c);
    setBit(&sFullWidthBMP9, 0x2b50);
    setBit(&sFullWidthBMP9, 0x2b55);
    setBitRange(&sFullWidthBMP9, 0x2e80, 0x2e99);
    setBitRange(&sFullWidthBMP9, 0x2e9b, 0x2ef3);
    setBitRange(&sFullWidthBMP9, 0x2f00, 0x2fd5);
    setBitRange(&sFullWidthBMP9, 0x2ff0, 0x303e);
    setBitRange(&sFullWidthBMP9, 0x3041, 0x3096);
    setBitRange(&sFullWidthBMP9, 0x3099, 0x30ff);
    setBitRange(&sFullWidthBMP9, 0x3105, 0x312f);
    setBitRange(&sFullWidthBMP9, 0x3131, 0x318e);
    setBitRange(&sFullWidthBMP9, 0x3190, 0x31e5);
    setBitRange(&sFullWidthBMP9, 0x31ef, 0x321e);
    setBitRange(&sFullWidthBMP9, 0x3220, 0x3247);
    setBitRange(&sFullWidthBMP9, 0x3250, 0xa48c);
    setBitRange(&sFullWidthBMP9, 0xa490, 0xa4c6);
    setBitRange(&sFullWidthBMP9, 0xa960, 0xa97c);
    setBitRange(&sFullWidthBMP9, 0xac00, 0xd7a3);
    setBitRange(&sFullWidthBMP9, 0xf900, 0xfaff);
    setBitRange(&sFullWidthBMP9, 0xfe10, 0xfe19);
    setBitRange(&sFullWidthBMP9, 0xfe30, 0xfe52);
    setBitRange(&sFullWidthBMP9, 0xfe54, 0xfe66);
    setBitRange(&sFullWidthBMP9, 0xfe68, 0xfe6b);
    setBitRange(&sFullWidthBMP9, 0xff01, 0xff60);
    setBitRange(&sFullWidthBMP9, 0xffe0, 0xffe6);
}

// Initialize ambiguous width bitmap for Unicode 8
static void initAmbiguous8(void) {
    memset(&sAmbiguousBMP8, 0, sizeof(sAmbiguousBMP8));

    // Individual characters
    setBit(&sAmbiguousBMP8, 0xa1);
    setBit(&sAmbiguousBMP8, 0xa4);
    setBit(&sAmbiguousBMP8, 0xa7);
    setBit(&sAmbiguousBMP8, 0xa8);
    setBit(&sAmbiguousBMP8, 0xaa);
    setBit(&sAmbiguousBMP8, 0xad);
    setBit(&sAmbiguousBMP8, 0xae);
    setBit(&sAmbiguousBMP8, 0xb0);
    setBit(&sAmbiguousBMP8, 0xb1);
    setBit(&sAmbiguousBMP8, 0xb2);
    setBit(&sAmbiguousBMP8, 0xb3);
    setBit(&sAmbiguousBMP8, 0xb4);
    setBit(&sAmbiguousBMP8, 0xb6);
    setBit(&sAmbiguousBMP8, 0xb7);
    setBit(&sAmbiguousBMP8, 0xb8);
    setBit(&sAmbiguousBMP8, 0xb9);
    setBit(&sAmbiguousBMP8, 0xba);
    setBit(&sAmbiguousBMP8, 0xbc);
    setBit(&sAmbiguousBMP8, 0xbd);
    setBit(&sAmbiguousBMP8, 0xbe);
    setBit(&sAmbiguousBMP8, 0xbf);
    setBit(&sAmbiguousBMP8, 0xc6);
    setBit(&sAmbiguousBMP8, 0xd0);
    setBit(&sAmbiguousBMP8, 0xd7);
    setBit(&sAmbiguousBMP8, 0xd8);
    setBit(&sAmbiguousBMP8, 0xde);
    setBit(&sAmbiguousBMP8, 0xdf);
    setBit(&sAmbiguousBMP8, 0xe0);
    setBit(&sAmbiguousBMP8, 0xe1);
    setBit(&sAmbiguousBMP8, 0xe6);
    setBit(&sAmbiguousBMP8, 0xe8);
    setBit(&sAmbiguousBMP8, 0xe9);
    setBit(&sAmbiguousBMP8, 0xea);
    setBit(&sAmbiguousBMP8, 0xec);
    setBit(&sAmbiguousBMP8, 0xed);
    setBit(&sAmbiguousBMP8, 0xf0);
    setBit(&sAmbiguousBMP8, 0xf2);
    setBit(&sAmbiguousBMP8, 0xf3);
    setBit(&sAmbiguousBMP8, 0xf7);
    setBit(&sAmbiguousBMP8, 0xf8);
    setBit(&sAmbiguousBMP8, 0xf9);
    setBit(&sAmbiguousBMP8, 0xfa);
    setBit(&sAmbiguousBMP8, 0xfc);
    setBit(&sAmbiguousBMP8, 0xfe);
    setBit(&sAmbiguousBMP8, 0x101);
    setBit(&sAmbiguousBMP8, 0x111);
    setBit(&sAmbiguousBMP8, 0x113);
    setBit(&sAmbiguousBMP8, 0x11b);
    setBit(&sAmbiguousBMP8, 0x126);
    setBit(&sAmbiguousBMP8, 0x127);
    setBit(&sAmbiguousBMP8, 0x12b);
    setBit(&sAmbiguousBMP8, 0x131);
    setBit(&sAmbiguousBMP8, 0x132);
    setBit(&sAmbiguousBMP8, 0x133);
    setBit(&sAmbiguousBMP8, 0x138);
    setBit(&sAmbiguousBMP8, 0x13f);
    setBit(&sAmbiguousBMP8, 0x140);
    setBit(&sAmbiguousBMP8, 0x141);
    setBit(&sAmbiguousBMP8, 0x142);
    setBit(&sAmbiguousBMP8, 0x144);
    setBit(&sAmbiguousBMP8, 0x148);
    setBit(&sAmbiguousBMP8, 0x149);
    setBit(&sAmbiguousBMP8, 0x14a);
    setBit(&sAmbiguousBMP8, 0x14b);
    setBit(&sAmbiguousBMP8, 0x14d);
    setBit(&sAmbiguousBMP8, 0x152);
    setBit(&sAmbiguousBMP8, 0x153);
    setBit(&sAmbiguousBMP8, 0x166);
    setBit(&sAmbiguousBMP8, 0x167);
    setBit(&sAmbiguousBMP8, 0x16b);
    setBit(&sAmbiguousBMP8, 0x1ce);
    setBit(&sAmbiguousBMP8, 0x1d0);
    setBit(&sAmbiguousBMP8, 0x1d2);
    setBit(&sAmbiguousBMP8, 0x1d4);
    setBit(&sAmbiguousBMP8, 0x1d6);
    setBit(&sAmbiguousBMP8, 0x1d8);
    setBit(&sAmbiguousBMP8, 0x1da);
    setBit(&sAmbiguousBMP8, 0x1dc);
    setBit(&sAmbiguousBMP8, 0x251);
    setBit(&sAmbiguousBMP8, 0x261);
    setBit(&sAmbiguousBMP8, 0x2c4);
    setBit(&sAmbiguousBMP8, 0x2c7);
    setBit(&sAmbiguousBMP8, 0x2c9);
    setBit(&sAmbiguousBMP8, 0x2ca);
    setBit(&sAmbiguousBMP8, 0x2cb);
    setBit(&sAmbiguousBMP8, 0x2cd);
    setBit(&sAmbiguousBMP8, 0x2d0);
    setBit(&sAmbiguousBMP8, 0x2d8);
    setBit(&sAmbiguousBMP8, 0x2d9);
    setBit(&sAmbiguousBMP8, 0x2da);
    setBit(&sAmbiguousBMP8, 0x2db);
    setBit(&sAmbiguousBMP8, 0x2dd);
    setBit(&sAmbiguousBMP8, 0x2df);

    // Ranges
    setBitRange(&sAmbiguousBMP8, 0x300, 0x36f);
    setBitRange(&sAmbiguousBMP8, 0x391, 0x3a1);
    setBitRange(&sAmbiguousBMP8, 0x3a3, 0x3a9);
    setBitRange(&sAmbiguousBMP8, 0x3b1, 0x3c1);
    setBitRange(&sAmbiguousBMP8, 0x3c3, 0x3c9);
    setBitRange(&sAmbiguousBMP8, 0x401, 0x401);
    setBitRange(&sAmbiguousBMP8, 0x410, 0x44f);
    setBitRange(&sAmbiguousBMP8, 0x451, 0x451);
    setBitRange(&sAmbiguousBMP8, 0x2010, 0x2010);
    setBitRange(&sAmbiguousBMP8, 0x2013, 0x2016);
    setBitRange(&sAmbiguousBMP8, 0x2018, 0x2019);
    setBitRange(&sAmbiguousBMP8, 0x201c, 0x201d);
    setBitRange(&sAmbiguousBMP8, 0x2020, 0x2022);
    setBitRange(&sAmbiguousBMP8, 0x2024, 0x2027);
    setBitRange(&sAmbiguousBMP8, 0x2030, 0x2030);
    setBitRange(&sAmbiguousBMP8, 0x2032, 0x2033);
    setBitRange(&sAmbiguousBMP8, 0x2035, 0x2035);
    setBitRange(&sAmbiguousBMP8, 0x203b, 0x203b);
    setBitRange(&sAmbiguousBMP8, 0x203e, 0x203e);
    setBitRange(&sAmbiguousBMP8, 0x2074, 0x2074);
    setBitRange(&sAmbiguousBMP8, 0x207f, 0x207f);
    setBitRange(&sAmbiguousBMP8, 0x2081, 0x2084);
    setBitRange(&sAmbiguousBMP8, 0x20ac, 0x20ac);
    setBitRange(&sAmbiguousBMP8, 0x2103, 0x2103);
    setBitRange(&sAmbiguousBMP8, 0x2105, 0x2105);
    setBitRange(&sAmbiguousBMP8, 0x2109, 0x2109);
    setBitRange(&sAmbiguousBMP8, 0x2113, 0x2113);
    setBitRange(&sAmbiguousBMP8, 0x2116, 0x2116);
    setBitRange(&sAmbiguousBMP8, 0x2121, 0x2122);
    setBitRange(&sAmbiguousBMP8, 0x2126, 0x2126);
    setBitRange(&sAmbiguousBMP8, 0x212b, 0x212b);
    setBitRange(&sAmbiguousBMP8, 0x2153, 0x2154);
    setBitRange(&sAmbiguousBMP8, 0x215b, 0x215e);
    setBitRange(&sAmbiguousBMP8, 0x2160, 0x216b);
    setBitRange(&sAmbiguousBMP8, 0x2170, 0x2179);
    setBitRange(&sAmbiguousBMP8, 0x2189, 0x2189);
    setBitRange(&sAmbiguousBMP8, 0x2190, 0x2199);
    setBitRange(&sAmbiguousBMP8, 0x21b8, 0x21b9);
    setBitRange(&sAmbiguousBMP8, 0x21d2, 0x21d2);
    setBitRange(&sAmbiguousBMP8, 0x21d4, 0x21d4);
    setBitRange(&sAmbiguousBMP8, 0x21e7, 0x21e7);
    setBitRange(&sAmbiguousBMP8, 0x2200, 0x2200);
    setBitRange(&sAmbiguousBMP8, 0x2202, 0x2203);
    setBitRange(&sAmbiguousBMP8, 0x2207, 0x2208);
    setBitRange(&sAmbiguousBMP8, 0x220b, 0x220b);
    setBitRange(&sAmbiguousBMP8, 0x220f, 0x220f);
    setBitRange(&sAmbiguousBMP8, 0x2211, 0x2211);
    setBitRange(&sAmbiguousBMP8, 0x2215, 0x2215);
    setBitRange(&sAmbiguousBMP8, 0x221a, 0x221a);
    setBitRange(&sAmbiguousBMP8, 0x221d, 0x2220);
    setBitRange(&sAmbiguousBMP8, 0x2223, 0x2223);
    setBitRange(&sAmbiguousBMP8, 0x2225, 0x2225);
    setBitRange(&sAmbiguousBMP8, 0x2227, 0x222c);
    setBitRange(&sAmbiguousBMP8, 0x222e, 0x222e);
    setBitRange(&sAmbiguousBMP8, 0x2234, 0x2237);
    setBitRange(&sAmbiguousBMP8, 0x223c, 0x223d);
    setBitRange(&sAmbiguousBMP8, 0x2248, 0x2248);
    setBitRange(&sAmbiguousBMP8, 0x224c, 0x224c);
    setBitRange(&sAmbiguousBMP8, 0x2252, 0x2252);
    setBitRange(&sAmbiguousBMP8, 0x2260, 0x2261);
    setBitRange(&sAmbiguousBMP8, 0x2264, 0x2267);
    setBitRange(&sAmbiguousBMP8, 0x226a, 0x226b);
    setBitRange(&sAmbiguousBMP8, 0x226e, 0x226f);
    setBitRange(&sAmbiguousBMP8, 0x2282, 0x2283);
    setBitRange(&sAmbiguousBMP8, 0x2286, 0x2287);
    setBitRange(&sAmbiguousBMP8, 0x2295, 0x2295);
    setBitRange(&sAmbiguousBMP8, 0x2299, 0x2299);
    setBitRange(&sAmbiguousBMP8, 0x22a5, 0x22a5);
    setBitRange(&sAmbiguousBMP8, 0x22bf, 0x22bf);
    setBitRange(&sAmbiguousBMP8, 0x2312, 0x2312);
    setBitRange(&sAmbiguousBMP8, 0x2460, 0x24e9);
    setBitRange(&sAmbiguousBMP8, 0x24eb, 0x254b);
    setBitRange(&sAmbiguousBMP8, 0x2550, 0x2573);
    setBitRange(&sAmbiguousBMP8, 0x2580, 0x258f);
    setBitRange(&sAmbiguousBMP8, 0x2592, 0x2595);
    setBitRange(&sAmbiguousBMP8, 0x25a0, 0x25a1);
    setBitRange(&sAmbiguousBMP8, 0x25a3, 0x25a9);
    setBitRange(&sAmbiguousBMP8, 0x25b2, 0x25b3);
    setBitRange(&sAmbiguousBMP8, 0x25b6, 0x25b7);
    setBitRange(&sAmbiguousBMP8, 0x25bc, 0x25bd);
    setBitRange(&sAmbiguousBMP8, 0x25c0, 0x25c1);
    setBitRange(&sAmbiguousBMP8, 0x25c6, 0x25c8);
    setBitRange(&sAmbiguousBMP8, 0x25cb, 0x25cb);
    setBitRange(&sAmbiguousBMP8, 0x25ce, 0x25d1);
    setBitRange(&sAmbiguousBMP8, 0x25e2, 0x25e5);
    setBitRange(&sAmbiguousBMP8, 0x25ef, 0x25ef);
    setBitRange(&sAmbiguousBMP8, 0x2605, 0x2606);
    setBitRange(&sAmbiguousBMP8, 0x2609, 0x2609);
    setBitRange(&sAmbiguousBMP8, 0x260e, 0x260f);
    setBitRange(&sAmbiguousBMP8, 0x2614, 0x2615);
    setBitRange(&sAmbiguousBMP8, 0x261c, 0x261c);
    setBitRange(&sAmbiguousBMP8, 0x261e, 0x261e);
    setBitRange(&sAmbiguousBMP8, 0x2640, 0x2640);
    setBitRange(&sAmbiguousBMP8, 0x2642, 0x2642);
    setBitRange(&sAmbiguousBMP8, 0x2660, 0x2661);
    setBitRange(&sAmbiguousBMP8, 0x2663, 0x2665);
    setBitRange(&sAmbiguousBMP8, 0x2667, 0x266a);
    setBitRange(&sAmbiguousBMP8, 0x266c, 0x266d);
    setBitRange(&sAmbiguousBMP8, 0x266f, 0x266f);
    setBitRange(&sAmbiguousBMP8, 0x269e, 0x269f);
    setBitRange(&sAmbiguousBMP8, 0x26be, 0x26bf);
    setBitRange(&sAmbiguousBMP8, 0x26c4, 0x26cd);
    setBitRange(&sAmbiguousBMP8, 0x26cf, 0x26e1);
    setBitRange(&sAmbiguousBMP8, 0x26e3, 0x26e3);
    setBitRange(&sAmbiguousBMP8, 0x26e8, 0x26ff);
    setBitRange(&sAmbiguousBMP8, 0x273d, 0x273d);
    setBitRange(&sAmbiguousBMP8, 0x2757, 0x2757);
    setBitRange(&sAmbiguousBMP8, 0x2776, 0x277f);
    setBitRange(&sAmbiguousBMP8, 0x2b55, 0x2b59);
    setBitRange(&sAmbiguousBMP8, 0x3248, 0x324f);
    setBitRange(&sAmbiguousBMP8, 0xe000, 0xf8ff);
    setBitRange(&sAmbiguousBMP8, 0xfe00, 0xfe0f);
    setBitRange(&sAmbiguousBMP8, 0xfffd, 0xfffd);
}

// Initialize ambiguous width bitmap for Unicode 9
// Generated from Unicode 17.0.0 by tools/eastasian.py
static void initAmbiguous9(void) {
    memset(&sAmbiguousBMP9, 0, sizeof(sAmbiguousBMP9));

    setBit(&sAmbiguousBMP9, 0xa1);
    setBit(&sAmbiguousBMP9, 0xa4);
    setBitRange(&sAmbiguousBMP9, 0xa7, 0xa8);
    setBit(&sAmbiguousBMP9, 0xaa);
    setBitRange(&sAmbiguousBMP9, 0xad, 0xae);
    setBitRange(&sAmbiguousBMP9, 0xb0, 0xb4);
    setBitRange(&sAmbiguousBMP9, 0xb6, 0xba);
    setBitRange(&sAmbiguousBMP9, 0xbc, 0xbf);
    setBit(&sAmbiguousBMP9, 0xc6);
    setBit(&sAmbiguousBMP9, 0xd0);
    setBitRange(&sAmbiguousBMP9, 0xd7, 0xd8);
    setBitRange(&sAmbiguousBMP9, 0xde, 0xe1);
    setBit(&sAmbiguousBMP9, 0xe6);
    setBitRange(&sAmbiguousBMP9, 0xe8, 0xea);
    setBitRange(&sAmbiguousBMP9, 0xec, 0xed);
    setBit(&sAmbiguousBMP9, 0xf0);
    setBitRange(&sAmbiguousBMP9, 0xf2, 0xf3);
    setBitRange(&sAmbiguousBMP9, 0xf7, 0xfa);
    setBit(&sAmbiguousBMP9, 0xfc);
    setBit(&sAmbiguousBMP9, 0xfe);
    setBit(&sAmbiguousBMP9, 0x101);
    setBit(&sAmbiguousBMP9, 0x111);
    setBit(&sAmbiguousBMP9, 0x113);
    setBit(&sAmbiguousBMP9, 0x11b);
    setBitRange(&sAmbiguousBMP9, 0x126, 0x127);
    setBit(&sAmbiguousBMP9, 0x12b);
    setBitRange(&sAmbiguousBMP9, 0x131, 0x133);
    setBit(&sAmbiguousBMP9, 0x138);
    setBitRange(&sAmbiguousBMP9, 0x13f, 0x142);
    setBit(&sAmbiguousBMP9, 0x144);
    setBitRange(&sAmbiguousBMP9, 0x148, 0x14b);
    setBit(&sAmbiguousBMP9, 0x14d);
    setBitRange(&sAmbiguousBMP9, 0x152, 0x153);
    setBitRange(&sAmbiguousBMP9, 0x166, 0x167);
    setBit(&sAmbiguousBMP9, 0x16b);
    setBit(&sAmbiguousBMP9, 0x1ce);
    setBit(&sAmbiguousBMP9, 0x1d0);
    setBit(&sAmbiguousBMP9, 0x1d2);
    setBit(&sAmbiguousBMP9, 0x1d4);
    setBit(&sAmbiguousBMP9, 0x1d6);
    setBit(&sAmbiguousBMP9, 0x1d8);
    setBit(&sAmbiguousBMP9, 0x1da);
    setBit(&sAmbiguousBMP9, 0x1dc);
    setBit(&sAmbiguousBMP9, 0x251);
    setBit(&sAmbiguousBMP9, 0x261);
    setBit(&sAmbiguousBMP9, 0x2c4);
    setBit(&sAmbiguousBMP9, 0x2c7);
    setBitRange(&sAmbiguousBMP9, 0x2c9, 0x2cb);
    setBit(&sAmbiguousBMP9, 0x2cd);
    setBit(&sAmbiguousBMP9, 0x2d0);
    setBitRange(&sAmbiguousBMP9, 0x2d8, 0x2db);
    setBit(&sAmbiguousBMP9, 0x2dd);
    setBit(&sAmbiguousBMP9, 0x2df);
    setBitRange(&sAmbiguousBMP9, 0x300, 0x36f);
    setBitRange(&sAmbiguousBMP9, 0x391, 0x3a1);
    setBitRange(&sAmbiguousBMP9, 0x3a3, 0x3a9);
    setBitRange(&sAmbiguousBMP9, 0x3b1, 0x3c1);
    setBitRange(&sAmbiguousBMP9, 0x3c3, 0x3c9);
    setBit(&sAmbiguousBMP9, 0x401);
    setBitRange(&sAmbiguousBMP9, 0x410, 0x44f);
    setBit(&sAmbiguousBMP9, 0x451);
    setBit(&sAmbiguousBMP9, 0x2010);
    setBitRange(&sAmbiguousBMP9, 0x2013, 0x2016);
    setBitRange(&sAmbiguousBMP9, 0x2018, 0x2019);
    setBitRange(&sAmbiguousBMP9, 0x201c, 0x201d);
    setBitRange(&sAmbiguousBMP9, 0x2020, 0x2022);
    setBitRange(&sAmbiguousBMP9, 0x2024, 0x2027);
    setBit(&sAmbiguousBMP9, 0x2030);
    setBitRange(&sAmbiguousBMP9, 0x2032, 0x2033);
    setBit(&sAmbiguousBMP9, 0x2035);
    setBit(&sAmbiguousBMP9, 0x203b);
    setBit(&sAmbiguousBMP9, 0x203e);
    setBit(&sAmbiguousBMP9, 0x2074);
    setBit(&sAmbiguousBMP9, 0x207f);
    setBitRange(&sAmbiguousBMP9, 0x2081, 0x2084);
    setBit(&sAmbiguousBMP9, 0x20ac);
    setBit(&sAmbiguousBMP9, 0x2103);
    setBit(&sAmbiguousBMP9, 0x2105);
    setBit(&sAmbiguousBMP9, 0x2109);
    setBit(&sAmbiguousBMP9, 0x2113);
    setBit(&sAmbiguousBMP9, 0x2116);
    setBitRange(&sAmbiguousBMP9, 0x2121, 0x2122);
    setBit(&sAmbiguousBMP9, 0x2126);
    setBit(&sAmbiguousBMP9, 0x212b);
    setBitRange(&sAmbiguousBMP9, 0x2153, 0x2154);
    setBitRange(&sAmbiguousBMP9, 0x215b, 0x215e);
    setBitRange(&sAmbiguousBMP9, 0x2160, 0x216b);
    setBitRange(&sAmbiguousBMP9, 0x2170, 0x2179);
    setBit(&sAmbiguousBMP9, 0x2189);
    setBitRange(&sAmbiguousBMP9, 0x2190, 0x2199);
    setBitRange(&sAmbiguousBMP9, 0x21b8, 0x21b9);
    setBit(&sAmbiguousBMP9, 0x21d2);
    setBit(&sAmbiguousBMP9, 0x21d4);
    setBit(&sAmbiguousBMP9, 0x21e7);
    setBit(&sAmbiguousBMP9, 0x2200);
    setBitRange(&sAmbiguousBMP9, 0x2202, 0x2203);
    setBitRange(&sAmbiguousBMP9, 0x2207, 0x2208);
    setBit(&sAmbiguousBMP9, 0x220b);
    setBit(&sAmbiguousBMP9, 0x220f);
    setBit(&sAmbiguousBMP9, 0x2211);
    setBit(&sAmbiguousBMP9, 0x2215);
    setBit(&sAmbiguousBMP9, 0x221a);
    setBitRange(&sAmbiguousBMP9, 0x221d, 0x2220);
    setBit(&sAmbiguousBMP9, 0x2223);
    setBit(&sAmbiguousBMP9, 0x2225);
    setBitRange(&sAmbiguousBMP9, 0x2227, 0x222c);
    setBit(&sAmbiguousBMP9, 0x222e);
    setBitRange(&sAmbiguousBMP9, 0x2234, 0x2237);
    setBitRange(&sAmbiguousBMP9, 0x223c, 0x223d);
    setBit(&sAmbiguousBMP9, 0x2248);
    setBit(&sAmbiguousBMP9, 0x224c);
    setBit(&sAmbiguousBMP9, 0x2252);
    setBitRange(&sAmbiguousBMP9, 0x2260, 0x2261);
    setBitRange(&sAmbiguousBMP9, 0x2264, 0x2267);
    setBitRange(&sAmbiguousBMP9, 0x226a, 0x226b);
    setBitRange(&sAmbiguousBMP9, 0x226e, 0x226f);
    setBitRange(&sAmbiguousBMP9, 0x2282, 0x2283);
    setBitRange(&sAmbiguousBMP9, 0x2286, 0x2287);
    setBit(&sAmbiguousBMP9, 0x2295);
    setBit(&sAmbiguousBMP9, 0x2299);
    setBit(&sAmbiguousBMP9, 0x22a5);
    setBit(&sAmbiguousBMP9, 0x22bf);
    setBit(&sAmbiguousBMP9, 0x2312);
    setBitRange(&sAmbiguousBMP9, 0x2460, 0x24e9);
    setBitRange(&sAmbiguousBMP9, 0x24eb, 0x254b);
    setBitRange(&sAmbiguousBMP9, 0x2550, 0x2573);
    setBitRange(&sAmbiguousBMP9, 0x2580, 0x258f);
    setBitRange(&sAmbiguousBMP9, 0x2592, 0x2595);
    setBitRange(&sAmbiguousBMP9, 0x25a0, 0x25a1);
    setBitRange(&sAmbiguousBMP9, 0x25a3, 0x25a9);
    setBitRange(&sAmbiguousBMP9, 0x25b2, 0x25b3);
    setBitRange(&sAmbiguousBMP9, 0x25b6, 0x25b7);
    setBitRange(&sAmbiguousBMP9, 0x25bc, 0x25bd);
    setBitRange(&sAmbiguousBMP9, 0x25c0, 0x25c1);
    setBitRange(&sAmbiguousBMP9, 0x25c6, 0x25c8);
    setBit(&sAmbiguousBMP9, 0x25cb);
    setBitRange(&sAmbiguousBMP9, 0x25ce, 0x25d1);
    setBitRange(&sAmbiguousBMP9, 0x25e2, 0x25e5);
    setBit(&sAmbiguousBMP9, 0x25ef);
    setBitRange(&sAmbiguousBMP9, 0x2605, 0x2606);
    setBit(&sAmbiguousBMP9, 0x2609);
    setBitRange(&sAmbiguousBMP9, 0x260e, 0x260f);
    setBit(&sAmbiguousBMP9, 0x261c);
    setBit(&sAmbiguousBMP9, 0x261e);
    setBit(&sAmbiguousBMP9, 0x2640);
    setBit(&sAmbiguousBMP9, 0x2642);
    setBitRange(&sAmbiguousBMP9, 0x2660, 0x2661);
    setBitRange(&sAmbiguousBMP9, 0x2663, 0x2665);
    setBitRange(&sAmbiguousBMP9, 0x2667, 0x266a);
    setBitRange(&sAmbiguousBMP9, 0x266c, 0x266d);
    setBit(&sAmbiguousBMP9, 0x266f);
    setBitRange(&sAmbiguousBMP9, 0x269e, 0x269f);
    setBit(&sAmbiguousBMP9, 0x26bf);
    setBitRange(&sAmbiguousBMP9, 0x26c6, 0x26cd);
    setBitRange(&sAmbiguousBMP9, 0x26cf, 0x26d3);
    setBitRange(&sAmbiguousBMP9, 0x26d5, 0x26e1);
    setBit(&sAmbiguousBMP9, 0x26e3);
    setBitRange(&sAmbiguousBMP9, 0x26e8, 0x26e9);
    setBitRange(&sAmbiguousBMP9, 0x26eb, 0x26f1);
    setBit(&sAmbiguousBMP9, 0x26f4);
    setBitRange(&sAmbiguousBMP9, 0x26f6, 0x26f9);
    setBitRange(&sAmbiguousBMP9, 0x26fb, 0x26fc);
    setBitRange(&sAmbiguousBMP9, 0x26fe, 0x26ff);
    setBit(&sAmbiguousBMP9, 0x273d);
    setBitRange(&sAmbiguousBMP9, 0x2776, 0x277f);
    setBitRange(&sAmbiguousBMP9, 0x2b56, 0x2b59);
    setBitRange(&sAmbiguousBMP9, 0x3248, 0x324f);
    setBitRange(&sAmbiguousBMP9, 0xe000, 0xf8ff);
    setBitRange(&sAmbiguousBMP9, 0xfe00, 0xfe0f);
    setBit(&sAmbiguousBMP9, 0xfffd);
}

// Initialize all bitmaps
static void ensureInitialized(void) {
    if (atomic_load(&sInitialized)) {
        return;
    }

    // Use compare-exchange for thread-safe initialization
    int expected = 0;
    if (atomic_compare_exchange_strong(&sInitialized, &expected, 1)) {
        initFullWidth8();
        initFullWidth9();
        initAmbiguous8();
        initAmbiguous9();
        atomic_store(&sInitialized, 2);  // Mark as fully initialized
    } else {
        // Another thread is initializing, wait for it
        while (atomic_load(&sInitialized) != 2) {
            // Spin wait
        }
    }
}

bool iTermIsFullWidthCharacter(uint32_t unicode, int unicodeVersion) {
    ensureInitialized();

    if (unicode < 0x10000) {
        // BMP: use bitmap
        if (unicodeVersion >= 9) {
            return testBit(&sFullWidthBMP9, unicode);
        } else {
            return testBit(&sFullWidthBMP8, unicode);
        }
    } else {
        // Supplementary planes: use binary search
        if (unicodeVersion >= 9) {
            return inRanges(unicode, sFullWidthSupp9, sFullWidthSupp9Count);
        } else {
            return inRanges(unicode, sFullWidthSupp8, sFullWidthSupp8Count);
        }
    }
}

bool iTermIsAmbiguousWidthCharacter(uint32_t unicode, int unicodeVersion) {
    ensureInitialized();

    if (unicode < 0x10000) {
        // BMP: use bitmap
        if (unicodeVersion >= 9) {
            return testBit(&sAmbiguousBMP9, unicode);
        } else {
            return testBit(&sAmbiguousBMP8, unicode);
        }
    } else {
        // Supplementary planes: use binary search
        if (unicodeVersion >= 9) {
            return inRanges(unicode, sAmbiguousSupp9, sAmbiguousSupp9Count);
        } else {
            return inRanges(unicode, sAmbiguousSupp8, sAmbiguousSupp8Count);
        }
    }
}

bool iTermIsFlagCharacter(uint32_t unicode, int unicodeVersion) {
    if (unicodeVersion < 9) {
        return false;
    }
    return inRanges(unicode, sFlagRanges, sFlagRangesCount);
}

bool iTermIsDoubleWidthCharacter(uint32_t unicode,
                                 bool ambiguousIsDoubleWidth,
                                 int unicodeVersion,
                                 bool fullWidthFlags) {
    // Fast path for common ASCII and Latin-1 characters
    if (unicode <= 0xa0 || (unicode > 0x452 && unicode < 0x1100)) {
        return false;
    }

    if (iTermIsFullWidthCharacter(unicode, unicodeVersion)) {
        return true;
    }

    if (ambiguousIsDoubleWidth && iTermIsAmbiguousWidthCharacter(unicode, unicodeVersion)) {
        return true;
    }

    if (fullWidthFlags && iTermIsFlagCharacter(unicode, unicodeVersion)) {
        return true;
    }

    return false;
}
