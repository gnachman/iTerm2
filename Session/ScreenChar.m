// -*- mode:objc -*-
/*
 **  ScreenChar.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Code related to screen_char_t. Most of this has to do with
 **    storing multiple code points together in one cell by using a "color
 **    palette" approach where the code point can be used as an index into a
 **    string table, and the strings can have surrogate pairs and combining
 **    marks.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "ScreenChar.h"

// Maps codes to strings
static NSMutableDictionary* complexCharMap;
// Maps strings to codes.
static NSMutableDictionary* inverseComplexCharMap;
// Next available code.
static int ccmNextKey = 1;
// If ccmNextKey has wrapped then this is set to true and we have to delete old
// strings before creating a new one with a recycled code.
static BOOL hasWrapped = NO;

NSString* ComplexCharToStr(int key)
{
    if (key == UNKNOWN) {
        return ReplacementString();
    }

    return [complexCharMap objectForKey:[NSNumber numberWithInt:key]];
}

NSString* ScreenCharToStr(screen_char_t* sct)
{
    return CharToStr(sct->code, sct->complexChar);
}

NSString* CharToStr(unichar code, BOOL isComplex)
{
    if (code == UNKNOWN) {
        return ReplacementString();
    }

    if (isComplex) {
        return ComplexCharToStr(code);
    } else {
        return [NSString stringWithCharacters:&code length:1];
    }
}

int ExpandScreenChar(screen_char_t* sct, unichar* dest) {
    NSString* value = nil;
    if (sct->code == UNKNOWN) {
        value = ReplacementString();
    } else if (sct->complexChar) {
        value = ComplexCharToStr(sct->code);
    } else {
        *dest = sct->code;
        return 1;
    }
    assert(value);
    [value getCharacters:dest];
    return [value length];
}

UTF32Char CharToLongChar(unichar code, BOOL isComplex)
{
    NSString* aString = CharToStr(code, isComplex);
    unichar firstChar = [aString characterAtIndex:0];
    if (IsHighSurrogate(firstChar) && [aString length] >= 2) {
        unichar secondChar = [aString characterAtIndex:0];
        return DecodeSurrogatePair(firstChar, secondChar);
    } else {
        return firstChar;
    }
}

static int GetOrSetComplexChar(NSString* str)
{
    if (!complexCharMap) {
        complexCharMap = [[NSMutableDictionary alloc] initWithCapacity:1000];
        inverseComplexCharMap = [[NSMutableDictionary alloc] initWithCapacity:1000];
    }
    NSNumber* number = [inverseComplexCharMap objectForKey:str];
    if (number) {
        return [number intValue];
    }

    int newKey = ccmNextKey++;
    number = [NSNumber numberWithInt:newKey];
    if (hasWrapped) {
        NSString* oldStr = [complexCharMap objectForKey:number];
        if (oldStr) {
            [inverseComplexCharMap removeObjectForKey:oldStr];
        }
    }
    [complexCharMap setObject:str
                       forKey:number];
    [inverseComplexCharMap setObject:number forKey:str];
    if (ccmNextKey == 0xf000) {
        ccmNextKey = 1;
        hasWrapped = YES;
    }
    return newKey;
}

int AppendToComplexChar(int key, unichar codePoint)
{
    if (key == UNKNOWN) {
        return UNKNOWN;
    }

    NSString* str = [complexCharMap objectForKey:[NSNumber numberWithInt:key]];
    if ([str length] == kMaxParts) {
        NSLog(@"Warning: char <<%@>> with key %d reached max length %d", str,
              key, kMaxParts);
        return key;
    }
    assert(str);
    NSMutableString* temp = [NSMutableString stringWithString:str];
    [temp appendString:[NSString stringWithCharacters:&codePoint length:1]];

    return GetOrSetComplexChar(temp);
}

int BeginComplexChar(unichar initialCodePoint, unichar combiningChar)
{
    if (initialCodePoint == UNKNOWN) {
        return UNKNOWN;
    }

    unichar temp[2];
    temp[0] = initialCodePoint;
    temp[1] = combiningChar;
    return GetOrSetComplexChar([NSString stringWithCharacters:temp length:2]);
}

BOOL IsCombiningMark(UTF32Char c)
{
    static NSCharacterSet* combiningMarks;
    if (!combiningMarks) {
        struct {
            int minVal;
            int maxVal;
        } ranges[] = {
            // These are all the combining marks in Unicode 6.0 from:
            // http://www.fileformat.info/info/unicode/category/Mc/list.htm
            // http://www.fileformat.info/info/unicode/category/Mn/list.htm
            // http://www.fileformat.info/info/unicode/category/Me/list.htm
            //
            // Per http://www.unicode.org/versions/Unicode6.0.0/ch03.pdf#G30602
            // D52, Spacing Combining Marks, Nonspacing Marks, and
            // Enclosing Marks make up the set of combining marks.
            { 0x300, 0x36f }, { 0x483, 0x489 }, { 0x591, 0x5bd }, { 0x5bf, 0x5bf },
            { 0x5c1, 0x5c2 }, { 0x5c4, 0x5c5 }, { 0x5c7, 0x5c7 }, { 0x610, 0x61a },
            { 0x64b, 0x65f }, { 0x670, 0x670 }, { 0x6d6, 0x6dc }, { 0x6df, 0x6e4 },
            { 0x6e7, 0x6e8 }, { 0x6ea, 0x6ed }, { 0x711, 0x711 }, { 0x730, 0x74a },
            { 0x7a6, 0x7b0 }, { 0x7eb, 0x7f3 }, { 0x816, 0x819 }, { 0x81b, 0x823 },
            { 0x825, 0x827 }, { 0x829, 0x82d }, { 0x859, 0x85b }, { 0x900, 0x903 },
            { 0x93a, 0x93c }, { 0x93e, 0x94f }, { 0x951, 0x957 }, { 0x962, 0x963 },
            { 0x981, 0x983 }, { 0x9bc, 0x9bc }, { 0x9be, 0x9c4 }, { 0x9c7, 0x9c8 },
            { 0x9cb, 0x9cd }, { 0x9d7, 0x9d7 }, { 0x9e2, 0x9e3 }, { 0xa01, 0xa03 },
            { 0xa3c, 0xa3c }, { 0xa3e, 0xa42 }, { 0xa47, 0xa48 }, { 0xa4b, 0xa4d },
            { 0xa51, 0xa51 }, { 0xa70, 0xa71 }, { 0xa75, 0xa75 }, { 0xa81, 0xa83 },
            { 0xabc, 0xabc }, { 0xabe, 0xac5 }, { 0xac7, 0xac9 }, { 0xacb, 0xacd },
            { 0xae2, 0xae3 }, { 0xb01, 0xb03 }, { 0xb3c, 0xb3c }, { 0xb3e, 0xb44 },
            { 0xb47, 0xb48 }, { 0xb4b, 0xb4d }, { 0xb56, 0xb57 }, { 0xb62, 0xb63 },
            { 0xb82, 0xb82 }, { 0xbbe, 0xbc2 }, { 0xbc6, 0xbc8 }, { 0xbca, 0xbcd },
            { 0xbd7, 0xbd7 }, { 0xc01, 0xc03 }, { 0xc3e, 0xc44 }, { 0xc46, 0xc48 },
            { 0xc4a, 0xc4d }, { 0xc55, 0xc56 }, { 0xc62, 0xc63 }, { 0xc82, 0xc83 },
            { 0xcbc, 0xcbc }, { 0xcbe, 0xcc4 }, { 0xcc6, 0xcc8 }, { 0xcca, 0xccd },
            { 0xcd5, 0xcd6 }, { 0xce2, 0xce3 }, { 0xd02, 0xd03 }, { 0xd3e, 0xd44 },
            { 0xd46, 0xd48 }, { 0xd4a, 0xd4d }, { 0xd57, 0xd57 }, { 0xd62, 0xd63 },
            { 0xd82, 0xd83 }, { 0xdca, 0xdca }, { 0xdcf, 0xdd4 }, { 0xdd6, 0xdd6 },
            { 0xdd8, 0xddf }, { 0xdf2, 0xdf3 }, { 0xe31, 0xe31 }, { 0xe34, 0xe3a },
            { 0xe47, 0xe4e }, { 0xeb1, 0xeb1 }, { 0xeb4, 0xeb9 }, { 0xebb, 0xebc },
            { 0xec8, 0xecd }, { 0xf18, 0xf19 }, { 0xf35, 0xf35 }, { 0xf37, 0xf37 },
            { 0xf39, 0xf39 }, { 0xf3e, 0xf3f }, { 0xf71, 0xf84 }, { 0xf86, 0xf87 },
            { 0xf8d, 0xf97 }, { 0xf99, 0xfbc }, { 0xfc6, 0xfc6 }, { 0x102b, 0x103e },
            { 0x1056, 0x1059 }, { 0x105e, 0x1060 }, { 0x1062, 0x1064 }, { 0x1067, 0x106d },
            { 0x1071, 0x1074 }, { 0x1082, 0x108d }, { 0x108f, 0x108f }, { 0x109a, 0x109d },
            { 0x135d, 0x135f }, { 0x1712, 0x1714 }, { 0x1732, 0x1734 }, { 0x1752, 0x1753 },
            { 0x1772, 0x1773 }, { 0x17b6, 0x17d3 }, { 0x17dd, 0x17dd }, { 0x180b, 0x180d },
            { 0x18a9, 0x18a9 }, { 0x1920, 0x192b }, { 0x1930, 0x193b }, { 0x19b0, 0x19c0 },
            { 0x19c8, 0x19c9 }, { 0x1a17, 0x1a1b }, { 0x1a55, 0x1a5e }, { 0x1a60, 0x1a7c },
            { 0x1a7f, 0x1a7f }, { 0x1b00, 0x1b04 }, { 0x1b34, 0x1b44 }, { 0x1b6b, 0x1b73 },
            { 0x1b80, 0x1b82 }, { 0x1ba1, 0x1baa }, { 0x1be6, 0x1bf3 }, { 0x1c24, 0x1c37 },
            { 0x1cd0, 0x1cd2 }, { 0x1cd4, 0x1ce8 }, { 0x1ced, 0x1ced }, { 0x1cf2, 0x1cf2 },
            { 0x1dc0, 0x1de6 }, { 0x1dfc, 0x1dff }, { 0x20d0, 0x20f0 }, { 0x2cef, 0x2cf1 },
            { 0x2d7f, 0x2d7f }, { 0x2de0, 0x2dff }, { 0x302a, 0x302f }, { 0x3099, 0x309a },
            { 0xa66f, 0xa672 }, { 0xa67c, 0xa67d }, { 0xa6f0, 0xa6f1 }, { 0xa802, 0xa802 },
            { 0xa806, 0xa806 }, { 0xa80b, 0xa80b }, { 0xa823, 0xa827 }, { 0xa880, 0xa881 },
            { 0xa8b4, 0xa8c4 }, { 0xa8e0, 0xa8f1 }, { 0xa926, 0xa92d }, { 0xa947, 0xa953 },
            { 0xa980, 0xa983 }, { 0xa9b3, 0xa9c0 }, { 0xaa29, 0xaa36 }, { 0xaa43, 0xaa43 },
            { 0xaa4c, 0xaa4d }, { 0xaa7b, 0xaa7b }, { 0xaab0, 0xaab0 }, { 0xaab2, 0xaab4 },
            { 0xaab7, 0xaab8 }, { 0xaabe, 0xaabf }, { 0xaac1, 0xaac1 }, { 0xabe3, 0xabea },
            { 0xabec, 0xabed }, { 0xfb1e, 0xfb1e }, { 0xfe00, 0xfe0f }, { 0xfe20, 0xfe26 },
            { 0x101fd, 0x101fd }, { 0x10a01, 0x10a03 }, { 0x10a05, 0x10a06 },
            { 0x10a0c, 0x10a0f }, { 0x10a38, 0x10a3a }, { 0x10a3f, 0x10a3f },
            { 0x11000, 0x11002 }, { 0x11038, 0x11046 }, { 0x11080, 0x11082 },
            { 0x110b0, 0x110ba }, { 0x1d165, 0x1d169 }, { 0x1d16d, 0x1d172 },
            { 0x1d17b, 0x1d182 }, { 0x1d185, 0x1d18b }, { 0x1d1aa, 0x1d1ad },
            { 0x1d242, 0x1d244 },
            { 0xe0100, 0xe01ef },
            { 0, 0 }
        };

        NSMutableCharacterSet* temp = [[NSMutableCharacterSet alloc] init];
        for (int i = 0; ranges[i].minVal; ++i) {
            for (int j = ranges[i].minVal; j <= ranges[i].maxVal; ++j) {
                [temp addCharactersInRange:NSMakeRange(ranges[i].minVal,
                                                       ranges[i].maxVal - ranges[i].minVal + 1)];
            }
        }
        combiningMarks = temp;
    }
    return [combiningMarks longCharacterIsMember:c];
}

UTF32Char DecodeSurrogatePair(unichar high, unichar low)
{
    return 0x10000 + (high - 0xd800) * 0x400 + (low - 0xdc00);
}

BOOL IsLowSurrogate(unichar c)
{
    // http://en.wikipedia.org/wiki/Mapping_of_Unicode_characters#Surrogates
    return c >= 0xdc00 && c <= 0xdfff;
}

BOOL IsHighSurrogate(unichar c)
{
    // http://en.wikipedia.org/wiki/Mapping_of_Unicode_characters#Surrogates
    return c >= 0xd800 && c <= 0xdbff;
}

NSString* ScreenCharArrayToString(screen_char_t* screenChars,
                                  int start,
                                  int end,
                                  unichar** backingStorePtr,
                                  int** deltasPtr) {
    const int lineLength = end - start;
    unichar* charHaystack = malloc(sizeof(unichar) * lineLength * kMaxParts + 1);
    *backingStorePtr = charHaystack;
    int* deltas = malloc(sizeof(int) * (lineLength * kMaxParts + 1));
    *deltasPtr = deltas;
    // The 'deltas' array gives the difference in position between the screenChars
    // and the charHaystack. The formula to convert an index in the charHaystack
    // 'i' into an index in the screenChars 'r' is:
    //     r = i + deltas[i]
    //
    // Original string with some double-width characters, where DWC_RIGHT is
    // shown as '-':
    // 0123456789
    // ab-c-de-fg
    //
    // charHaystack, with combining marks/low surrogates shown as '*':
    // 0123456789A
    // abcd**ef**g
    //
    // Mapping:
    // charHaystack index i -> screenChars index  deltas[i]
    // 0 -> 0   (a@0->a@0)                        0
    // 1 -> 1   (b@1->b-@1)                       0
    // 2 -> 3   (c@2->c-@3)                       1
    // 3 -> 5   (d@3->d@5)                        2
    // 4 -> 5   (*@4->d@5)                        1
    // 5 -> 5   (*@5->d@5)                        0
    // 6 -> 6   (e@6->e-@6)                       0
    // 7 -> 8   (f@7->f@8)                        1
    // 8 -> 8   (*@8->f@8)                        0
    // 9 -> 8   (*@9->f@8)                       -1
    // A -> 9   (g@A->g@9)                       -1
    //
    // Note that delta is just the difference of the indices.
    int delta = 0;
    int o = 0;
    for (int i = start; i < end; ++i) {
        unichar c = screenChars[i].code;
        if (c == DWC_RIGHT) {
            ++delta;
        } else {
            const int len = ExpandScreenChar(&screenChars[i], charHaystack + o);
            ++delta;
            for (int j = o; j < o + len; ++j) {
                deltas[j] = --delta;
            }
            o += len;
        }
    }
    deltas[o] = delta;
    // I have no idea why NSUnicodeStringEncoding doesn't work, but it has
    // the wrong endianness on x86. Perhaps it's a relic of PPC days? Anyway,
    // LittleEndian seems to work on my x86, and BigEndian works under Rosetta
    // with a ppc-only binary. Oddly, testing for defined(LITTLE_ENDIAN) does
    // not produce the correct results under ppc+Rosetta.
    int encoding;
#if defined(__ppc__) || defined(__ppc64__)
    encoding = NSUTF16BigEndianStringEncoding;
#else
    encoding = NSUTF16LittleEndianStringEncoding;
#endif
    return [[[NSString alloc] initWithBytesNoCopy:charHaystack
                                           length:o * sizeof(unichar)
                                         encoding:encoding
                                     freeWhenDone:NO] autorelease];
}

int EffectiveLineLength(screen_char_t* theLine, int totalLength) {
    for (int i = totalLength-1; i >= 0; i--) {
        if (theLine[i].complexChar || theLine[i].code) {
            return i + 1;
        }
    }
    return 0;
}
