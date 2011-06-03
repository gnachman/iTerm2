// $Id: NSStringITerm.m,v 1.11 2008-09-24 22:35:38 yfabian Exp $
/*
 **  NSStringIterm.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements NSString extensions.
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

#define NSSTRINGJTERMINAL_CLASS_COMPILE
#import "Misc/NSStringITerm.h"

#define AMB_CHAR_NUMBER (sizeof(ambiguous_chars) / sizeof(int))

static const int ambiguous_chars[] = {
    0xa1, 0xa4, 0xa7, 0xa8, 0xaa, 0xad, 0xae, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb6, 0xb7,
    0xb8, 0xb9, 0xba, 0xbc, 0xbd, 0xbe, 0xbf, 0xc6, 0xd0, 0xd7, 0xd8, 0xde, 0xdf, 0xe0,
    0xe1, 0xe6, 0xe8, 0xe9, 0xea, 0xec, 0xed, 0xf0, 0xf2, 0xf3, 0xf7, 0xf8, 0xf9, 0xfa,
    0xfc, 0xfe, 0x101, 0x111, 0x113, 0x11b, 0x126, 0x127, 0x12b, 0x131, 0x132, 0x133,
    0x138, 0x13f, 0x140, 0x141, 0x142, 0x144, 0x148, 0x149, 0x14a, 0x14b, 0x14d, 0x152,
    0x153, 0x166, 0x167, 0x16b, 0x1ce, 0x1d0, 0x1d2, 0x1d4, 0x1d6, 0x1d8, 0x1da, 0x1dc,
    0x251, 0x261, 0x2c4, 0x2c7, 0x2c9, 0x2ca, 0x2cb, 0x2cd, 0x2d0, 0x2d8, 0x2d9, 0x2da,
    0x2db, 0x2dd, 0x2df, 0x3a3, 0x3a4, 0x3a5, 0x3a6, 0x3a7, 0x3a8, 0x3a9, 0x3c3, 0x3c4,
    0x3c5, 0x3c6, 0x3c7, 0x3c8, 0x3c9, 0x401, 0x451, 0x2010, 0x2013, 0x2014, 0x2015,
    0x2016, 0x2018, 0x2019, 0x201c, 0x201d, 0x2020, 0x2021, 0x2022, 0x2024, 0x2025,
    0x2026, 0x2027, 0x2030, 0x2032, 0x2033, 0x2035, 0x203b, 0x203e, 0x2074, 0x207f,
    0x2081, 0x2082, 0x2083, 0x2084, 0x20ac, 0x2103, 0x2105, 0x2109, 0x2113, 0x2116,
    0x2121, 0x2122, 0x2126, 0x212b, 0x2153, 0x2154, 0x215b, 0x215c, 0x215d, 0x215e,
    0x2189, 0x21b8, 0x21b9, 0x21d2, 0x21d4, 0x21e7, 0x2200, 0x2202, 0x2203, 0x2207,
    0x2208, 0x220b, 0x220f, 0x2211, 0x2215, 0x221a, 0x221d, 0x221e, 0x221f, 0x2220,
    0x2223, 0x2225, 0x2227, 0x2228, 0x2229, 0x222a, 0x222b, 0x222c, 0x222e, 0x2234,
    0x2235, 0x2236, 0x2237, 0x223c, 0x223d, 0x2248, 0x224c, 0x2252, 0x2260, 0x2261,
    0x2264, 0x2265, 0x2266, 0x2267, 0x226a, 0x226b, 0x226e, 0x226f, 0x2282, 0x2283,
    0x2286, 0x2287, 0x2295, 0x2299, 0x22a5, 0x22bf, 0x2312, 0x2592, 0x2593, 0x2594,
    0x2595, 0x25a0, 0x25a1, 0x25a3, 0x25a4, 0x25a5, 0x25a6, 0x25a7, 0x25a8, 0x25a9,
    0x25b2, 0x25b3, 0x25b6, 0x25b7, 0x25bc, 0x25bd, 0x25c0, 0x25c1, 0x25c6, 0x25c7,
    0x25c8, 0x25cb, 0x25ce, 0x25cf, 0x25d0, 0x25d1, 0x25e2, 0x25e3, 0x25e4, 0x25e5,
    0x25ef, 0x2605, 0x2606, 0x2609, 0x260e, 0x260f, 0x2614, 0x2615, 0x261c, 0x261e,
    0x2640, 0x2642, 0x2660, 0x2661, 0x2663, 0x2664, 0x2665, 0x2667, 0x2668, 0x2669,
    0x266a, 0x266c, 0x266d, 0x266f, 0x269e, 0x269f, 0x26be, 0x26bf, 0x26e3, 0x273d,
    0x2757, 0x2b55, 0x2b56, 0x2b57, 0x2b58, 0x2b59, 0xfffd
    // This is not a complete list - there are also several large ranges that
    // are found in the code.
};


@implementation NSString (iTerm)

+ (NSString *)stringWithInt:(int)num
{
    return [NSString stringWithFormat:@"%d", num];
}

+ (BOOL)isDoubleWidthCharacter:(int)unicode
                      encoding:(NSStringEncoding)e
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
{
    if (unicode <= 0xa0 ||
        (unicode > 0x452 && unicode < 0x1100)) {
        // Quickly cover the common cases.
        return NO;
    }

    // This list of fullwidth and wide characters comes from Unicode 6.0:
    // http://www.unicode.org/Public/6.0.0/ucd/EastAsianWidth.txt
    if ((unicode >= 0x1100 && unicode <= 0x115f) ||
        (unicode >= 0x11a3 && unicode <= 0x11a7) ||
        (unicode >= 0x11fa && unicode <= 0x11ff) ||
        (unicode >= 0x2329 && unicode <= 0x232a) ||
        (unicode >= 0x2e80 && unicode <= 0x2e99) ||
        (unicode >= 0x2e9b && unicode <= 0x2ef3) ||
        (unicode >= 0x2f00 && unicode <= 0x2fd5) ||
        (unicode >= 0x2ff0 && unicode <= 0x2ffb) ||
        (unicode >= 0x3000 && unicode <= 0x303e) ||
        (unicode >= 0x3041 && unicode <= 0x3096) ||
        (unicode >= 0x3099 && unicode <= 0x30ff) ||
        (unicode >= 0x3105 && unicode <= 0x312d) ||
        (unicode >= 0x3131 && unicode <= 0x318e) ||
        (unicode >= 0x3190 && unicode <= 0x31ba) ||
        (unicode >= 0x31c0 && unicode <= 0x31e3) ||
        (unicode >= 0x31f0 && unicode <= 0x321e) ||
        (unicode >= 0x3220 && unicode <= 0x3247) ||
        (unicode >= 0x3250 && unicode <= 0x32fe) ||
        (unicode >= 0x3300 && unicode <= 0x4dbf) ||
        (unicode >= 0x4e00 && unicode <= 0xa48c) ||
        (unicode >= 0xa490 && unicode <= 0xa4c6) ||
        (unicode >= 0xa960 && unicode <= 0xa97c) ||
        (unicode >= 0xac00 && unicode <= 0xd7a3) ||
        (unicode >= 0xd7b0 && unicode <= 0xd7c6) ||
        (unicode >= 0xd7cb && unicode <= 0xd7fb) ||
        (unicode >= 0xf900 && unicode <= 0xfaff) ||
        (unicode >= 0xfe10 && unicode <= 0xfe19) ||
        (unicode >= 0xfe30 && unicode <= 0xfe52) ||
        (unicode >= 0xfe54 && unicode <= 0xfe66) ||
        (unicode >= 0xfe68 && unicode <= 0xfe6b) ||
        (unicode >= 0xff01 && unicode <= 0xff60) ||
        (unicode >= 0xffe0 && unicode <= 0xffe6) ||
        (unicode >= 0x1b000 && unicode <= 0x1b001) ||
        (unicode >= 0x1f200 && unicode <= 0x1f202) ||
        (unicode >= 0x1f210 && unicode <= 0x1f23a) ||
        (unicode >= 0x1f240 && unicode <= 0x1f248) ||
        (unicode >= 0x1f250 && unicode <= 0x1f251) ||
        (unicode >= 0x20000 && unicode <= 0x2fffd) ||
        (unicode >= 0x30000 && unicode <= 0x3fffd)) {
        return YES;
    }

    // These are the ambiguous-width characters (ibid.)
    if (ambiguousIsDoubleWidth) {
        // First check if the character falls in any range of consecutive
        // ambiguous-width characters before performing the binary search.
        // This keeps the list from being absurdly large.
        if ((unicode >= 0x300 && unicode <= 0x36f) ||
            (unicode >= 0x391 && unicode <= 0x3a1) ||
            (unicode >= 0x3b1 && unicode <= 0x3c1) ||
            (unicode >= 0x410 && unicode <= 0x44f) ||
            (unicode >= 0x2160 && unicode <= 0x216b) ||
            (unicode >= 0x2170 && unicode <= 0x2179) ||
            (unicode >= 0x2190 && unicode <= 0x2199) ||
            (unicode >= 0x2460 && unicode <= 0x24e9) ||
            (unicode >= 0x24eb && unicode <= 0x254b) ||
            (unicode >= 0x2550 && unicode <= 0x2573) ||
            (unicode >= 0x2580 && unicode <= 0x258f) ||
            (unicode >= 0x26c4 && unicode <= 0x26cd) ||
            (unicode >= 0x26cf && unicode <= 0x26e1) ||
            (unicode >= 0x26e8 && unicode <= 0x26ff) ||
            (unicode >= 0x2776 && unicode <= 0x277f) ||
            (unicode >= 0x3248 && unicode <= 0x324f) ||
            (unicode >= 0xe000 && unicode <= 0xf8ff) ||
            (unicode >= 0xfe00 && unicode <= 0xfe0f) ||
            (unicode >= 0x1f100 && unicode <= 0x1f10a) ||
            (unicode >= 0x1f110 && unicode <= 0x1f12d) ||
            (unicode >= 0x1f130 && unicode <= 0x1f169) ||
            (unicode >= 0x1f170 && unicode <= 0x1f19a) ||
            (unicode >= 0xe0100 && unicode <= 0xe01ef) ||
            (unicode >= 0xf0000 && unicode <= 0xffffd) ||
            (unicode >= 0x100000 && unicode <= 0x10fffd)) {
            return YES;
        }

        // Now do a binary search of the individual ambiguous width code points
        // in the array above.
        int ind = AMB_CHAR_NUMBER / 2;
        int start = 0;
        int end = AMB_CHAR_NUMBER;
        while (start < end) {
            if (ambiguous_chars[ind] == unicode) {
                return YES;
            } else if (ambiguous_chars[ind] < unicode) {
                start = ind + 1;
                ind = (start + end) / 2;
            } else {
                end = ind;
                ind = (start + end) / 2;
            }
        }
        // Fall through if not in ambiguous character list.
    }

    return NO;
}

//
// Replace Substring
//
- (NSMutableString *) stringReplaceSubstringFrom:(NSString *)oldSubstring to:(NSString *)newSubstring
{
    unsigned int     len;
    NSMutableString *mstr;
    NSRange          searchRange;
    NSRange          resultRange;

#define ADDON_SPACE 10

    searchRange.location = 0;
    searchRange.length = len = [self length];
    mstr = [NSMutableString stringWithCapacity:(len + ADDON_SPACE)];
    NSParameterAssert(mstr != nil);

    for (;;)
    {
        resultRange = [self rangeOfString:oldSubstring options:NSLiteralSearch range:searchRange];
        if (resultRange.length == 0)
            break;  // Not found!

        // append and replace
        [mstr appendString:[self substringWithRange:
            NSMakeRange(searchRange.location, resultRange.location - searchRange.location)] ];
        [mstr appendString:newSubstring];

        // update search Range
        searchRange.location = resultRange.location + resultRange.length;
        searchRange.length   = len - searchRange.location;

        //  NSLog(@"resultRange.location=%d\n", resultRange.location);
        //  NSLog(@"resultRange.length=%d\n", resultRange.length);
    }

    [mstr appendString:[self substringWithRange:searchRange]];

    return mstr;
}

- (NSString *)stringWithEscapedShellCharacters
{
    NSMutableString *aMutableString = [[[NSMutableString alloc] initWithString: self] autorelease];
    NSString* charsToEscape = @"\\ ()\"&'!$<>;|*?[]#`";
    for (int i = 0; i < [charsToEscape length]; i++) {
        NSString* before = [charsToEscape substringWithRange:NSMakeRange(i, 1)];
        NSString* after = [@"\\" stringByAppendingString:before];
        [aMutableString replaceOccurrencesOfString:before
                                        withString:after
                                           options:0
                                             range:NSMakeRange(0, [aMutableString length])];
    }

    return [NSString stringWithString:aMutableString];
}

- (NSString*)stringWithPercentEscape
{
    // From
    // http://stackoverflow.com/questions/705448/iphone-sdk-problem-with-ampersand-in-the-url-string
    return [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                (CFStringRef)[[self mutableCopy] autorelease],
                                                                NULL,
                                                                CFSTR("￼=,!$&'()*+;@?\n\"<>#\t :/"),
                                                                kCFStringEncodingUTF8) autorelease];
}

@end
