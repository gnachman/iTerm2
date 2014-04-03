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
#import "NSStringITerm.h"
#import <apr-1/apr_base64.h>
#import <wctype.h>

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

- (NSString *)stringWithShellEscapedTabs
{
    const int kLNEXT = 22;
    NSString *replacement = [NSString stringWithFormat:@"%c\t", kLNEXT];

    return [self stringByReplacingOccurrencesOfString:@"\t" withString:replacement];
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

- (NSString*)stringWithLinefeedNewlines
{
    return [[self stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"]
               stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
}

- (void)breakDownCommandToPath:(NSString **)cmd cmdArgs:(NSArray **)path
{
    NSMutableArray *mutableCmdArgs;
    char *cmdLine; // The temporary UTF-8 version of the command line
    char *nextChar; // The character we will process next
    char *argStart; // The start of the current argument we are processing
    char *copyPos; // The position where we are currently writing characters
    int inQuotes = 0; // Are we inside double quotes?
    BOOL inWhitespace = NO;  // Last char was whitespace if true

    mutableCmdArgs = [[NSMutableArray alloc] init];

    // The value returned by [self UTF8String] is automatically freed (when the
    // autorelease context containing this is destroyed). We need to copy the
    // string, as the tokenisation is easier when we can modify string we are
    // working with.
    cmdLine = strdup([self UTF8String]);
    nextChar = cmdLine;
    copyPos = cmdLine;
    argStart = cmdLine;

    if (!cmdLine) {
        // We could not allocate enough memory for the cmdLine... bailing
        *path = [[NSArray alloc] init];
        [mutableCmdArgs release];
        return;
    }

    char c;
    while ((c = *nextChar++)) {
        switch (c) {
            case '\\':
                inWhitespace = NO;
                if (*nextChar == '\0') {
                    // This is the last character, thus this is a malformed
                    // command line, we will just leave the "\" character as a
                    // literal.
                }

                // We need to copy the next character verbatim.
                *copyPos++ = *nextChar++;
                break;
            case '\"':
                inWhitespace = NO;
                // Time to toggle the quotation mode
                inQuotes = !inQuotes;
                // Note: Since we don't copy to/increment copyPos, this
                // character will be dropped from the output string.
                break;
            case ' ':
            case '\t':
            case '\n':
                if (inQuotes) {
                    // We need to copy the current character verbatim.
                    *copyPos++ = c;
                } else {
                    if (!inWhitespace) {
                        // Time to split the command
                        *copyPos = '\0';
                        [mutableCmdArgs addObject:[NSString stringWithUTF8String:argStart]];
                        argStart = nextChar;
                        copyPos = nextChar;
                        inWhitespace = YES;
                    } else {
                        // Skip possible start of next arg when seeing Nth
                        // consecutive whitespace for N > 1.
                        ++argStart;
                    }
                }
                break;
            default:
                // Just copy the current character.
                // Note: This could be made more efficient for the 'normal
                // case' where copyPos is not offset from the current place we
                // are reading from. Since this function is called rarely, and
                // it isn't that slow, we will just ignore the optimisation.
                inWhitespace = NO;
                *copyPos++ = c;
                break;
        }
    }

    if (copyPos != argStart) {
        // We have data that we have not copied into mutableCmdArgs.
        *copyPos = '\0';
        [mutableCmdArgs addObject:[NSString stringWithUTF8String: argStart]];
    }

    if ([mutableCmdArgs count] > 0) {
        *cmd = [mutableCmdArgs objectAtIndex:0];
        [mutableCmdArgs removeObjectAtIndex:0];
    } else {
        // This will only occur if the input string is empty.
        // Note: The old code did nothing in this case, so neither will we.
    }

    free(cmdLine);
    *path = [NSArray arrayWithArray:mutableCmdArgs];
    [mutableCmdArgs release];
}

- (NSString *)stringByReplacingBackreference:(int)n withString:(NSString *)s
{
    return [self stringByReplacingEscapedChar:'0' + n withString:s];
}

static BOOL ishex(unichar c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static int fromhex(unichar c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return c - 'A' + 10;
}

- (NSData *)dataFromHexValues
{
	NSMutableData *data = [NSMutableData data];
        int length = self.length;  // Convert to signed so length-1 is safe below.
	for (int i = 0; i < length - 1; i+=2) {
		const char high = fromhex([self characterAtIndex:i]) << 4;
		const char low = fromhex([self characterAtIndex:i + 1]);
		const char b = high | low;
		[data appendBytes:&b length:1];
	}
	return data;
}

- (NSString *)stringByReplacingEscapedHexValuesWithChars
{
    NSMutableArray *ranges = [NSMutableArray array];
    NSRange range = [self rangeOfString:@"\\x"];
    while (range.location != NSNotFound) {
        int numSlashes = 0;
        for (int i = range.location - 1; i >= 0 && [self characterAtIndex:i] == '\\'; i--) {
            ++numSlashes;
        }
        if (range.location + 3 < self.length) {
            if (numSlashes % 2 == 0) {
                unichar c1 = [self characterAtIndex:range.location + 2];
                unichar c2 = [self characterAtIndex:range.location + 3];
                if (ishex(c1) && ishex(c2)) {
                    range.length += 2;
                    [ranges insertObject:[NSValue valueWithRange:range] atIndex:0];
                }
            }
        }
        range = [self rangeOfString:@"\\x"
                            options:0
                              range:NSMakeRange(range.location + 1, self.length - range.location - 1)];
    }

    NSString *newString = self;
    for (NSValue *value in ranges) {
        NSRange r = [value rangeValue];

        unichar c1 = [self characterAtIndex:r.location + 2];
        unichar c2 = [self characterAtIndex:r.location + 3];
        unichar c = (fromhex(c1) << 4) + fromhex(c2);
        NSString *s = [NSString stringWithCharacters:&c length:1];
        newString = [newString stringByReplacingCharactersInRange:r withString:s];
    }

    return newString;
}

- (NSString *)stringByReplacingEscapedChar:(unichar)echar withString:(NSString *)s
{
    NSString *br = [NSString stringWithFormat:@"\\%C", echar];
    NSMutableArray *ranges = [NSMutableArray array];
    NSRange range = [self rangeOfString:br];
    while (range.location != NSNotFound) {
        int numSlashes = 0;
        for (int i = range.location - 1; i >= 0 && [self characterAtIndex:i] == '\\'; i--) {
            ++numSlashes;
        }
        if (numSlashes % 2 == 0) {
            [ranges insertObject:[NSValue valueWithRange:range] atIndex:0];
        }
        range = [self rangeOfString:br
                            options:0
                              range:NSMakeRange(range.location + 1, self.length - range.location - 1)];
    }

    NSString *newString = self;
    for (NSValue *value in ranges) {
        NSRange r = [value rangeValue];
        newString = [newString stringByReplacingCharactersInRange:r withString:s];
    }

    return newString;
}

// foo"bar -> foo\"bar
// foo\bar -> foo\\bar
// foo\"bar -> foo\\\"bar
- (NSString *)stringByEscapingQuotes {
    return [[self stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
               stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

// Returns the number of valid bytes in a sequence from a row in table 3-7 of the Unicode 6.2 spec.
// Returns 0 if no bytes are valid (a true maximal subpart is never less than 1).
static int maximal_subpart_of_row(const unsigned char *datap,
                                  int datalen,
                                  int bytesInRow,
                                  int *min,  // array of min values, with |bytesInRow| elements.
                                  int *max)  // array of max values, with |bytesInRow| elements.
{
    for (int i = 0; i < bytesInRow && i < datalen; i++) {
        const int v = datap[i];
        if (v < min[i] || v > max[i]) {
            return i;
        }
    }
    return bytesInRow;
}

// This function finds the longest intial sequence of bytes that look like a valid UTF-8 sequence.
// It's used to gobble them up and replace them with a <?> replacement mark in an invalid sequence.
static int minimal_subpart(const unsigned char *datap, int datalen)
{
    // This comes from table 3-7 in http://www.unicode.org/versions/Unicode6.2.0/ch03.pdf
    struct {
        int numBytes;  // Num values in min, max arrays
        int min[4];    // Minimum values for each byte in a utf-8 sequence.
        int max[4];    // Max values.
    } wellFormedSequencesTable[] = {
        {
            1,
            { 0x00, -1, -1, -1, },
            { 0x7f, -1, -1, -1, },
        },
        {
            2,
            { 0xc2, 0x80, -1, -1, },
            { 0xdf, 0xbf, -1, -1 },
        },
        {
            3,
            { 0xe0, 0xa0, 0x80, -1, },
            { 0xe0, 0xbf, 0xbf, -1 },
        },
        {
            3,
            { 0xe1, 0x80, 0x80, -1, },
            { 0xec, 0xbf, 0xbf, -1, },
        },
        {
            3,
            { 0xed, 0x80, 0x80, -1, },
            { 0xed, 0x9f, 0xbf, -1 },
        },
        {
            3,
            { 0xee, 0x80, 0x80, -1, },
            { 0xef, 0xbf, 0xbf, -1, },
        },
        {
            4,
            { 0xf0, 0x90, 0x80, -1, },
            { 0xf0, 0xbf, 0xbf, -1, },
        },
        {
            4,
            { 0xf1, 0x80, 0x80, 0x80, },
            { 0xf3, 0xbf, 0xbf, 0xbf, },
        },
        {
            4,
            { 0xf4, 0x80, 0x80, 0x80, },
            { 0xf4, 0x8f, 0xbf, 0xbf },
        },
        { -1, { -1 }, { -1 } }
    };

    int longest = 0;
    for (int row = 0; wellFormedSequencesTable[row].numBytes > 0; row++) {
        longest = MAX(longest,
                      maximal_subpart_of_row(datap,
                                             datalen,
                                             wellFormedSequencesTable[row].numBytes,
                                             wellFormedSequencesTable[row].min,
                                             wellFormedSequencesTable[row].max));
    }
    return MIN(datalen, MAX(1, longest));
}

int decode_utf8_char(const unsigned char *datap,
                     int datalen,
                     int * restrict result)
{
    unsigned int theChar;
    int utf8Length;
    unsigned char c;
    // This maps a utf-8 sequence length to the smallest code point it should
    // encode (e.g., using 5 bytes to encode an ascii character would be
    // considered an error).
    unsigned int smallest[7] = { 0, 0, 0x80UL, 0x800UL, 0x10000UL, 0x200000UL, 0x4000000UL };

    if (datalen == 0) {
        return 0;
    }

    c = *datap;
    if ((c & 0x80) == 0x00) {
        *result = c;
        return 1;
    } else if ((c & 0xE0) == 0xC0) {
        theChar = c & 0x1F;
        utf8Length = 2;
    } else if ((c & 0xF0) == 0xE0) {
        theChar = c & 0x0F;
        utf8Length = 3;
    } else if ((c & 0xF8) == 0xF0) {
        theChar = c & 0x07;
        utf8Length = 4;
    } else if ((c & 0xFC) == 0xF8) {
        theChar = c & 0x03;
        utf8Length = 5;
    } else if ((c & 0xFE) == 0xFC) {
        theChar = c & 0x01;
        utf8Length = 6;
    } else {
        return -1;
    }
    for (int i = 1; i < utf8Length; i++) {
        if (datalen <= i) {
            return 0;
        }
        c = datap[i];
        if ((c & 0xc0) != 0x80) {
            // Expected a continuation character but did not get one.
            return -i;
        }
        theChar = (theChar << 6) | (c & 0x3F);
    }

    if (theChar < smallest[utf8Length]) {
        // A too-long sequence was used to encode a value. For example, a 4-byte sequence must encode
        // a value of at least 0x10000 (it is F0 90 80 80). A sequence like F0 8F BF BF is invalid
        // because there is a 3-byte sequence to encode U+FFFF (the sequence is EF BF BF).
        return -minimal_subpart(datap, datalen);
    }

    // Reject UTF-16 surrogates. They are invalid UTF-8 sequences.
    // Reject characters above U+10FFFF, as they are also invalid UTF-8 sequences.
    if ((theChar >= 0xD800 && theChar <= 0xDFFF) || theChar > 0x10FFFF) {
        return -minimal_subpart(datap, datalen);
    }

    *result = (int)theChar;
    return utf8Length;
}

- (NSString *)initWithUTF8DataIgnoringErrors:(NSData *)data {
    const unsigned char *p = data.bytes;
    int len = data.length;
    int utf8DecodeResult;
    int theChar = 0;
    NSMutableData *utf16Data = [NSMutableData data];

    while (len > 0) {
        utf8DecodeResult = decode_utf8_char(p, len, &theChar);
        if (utf8DecodeResult == 0) {
            // Stop on end of stream.
            break;
        } else if (utf8DecodeResult < 0) {
            theChar = UNICODE_REPLACEMENT_CHAR;
            utf8DecodeResult = -utf8DecodeResult;
        } else if (theChar > 0xFFFF) {
            // Convert to surrogate pair.
           UniChar high, low;
           high = ((theChar - 0x10000) >> 10) + 0xd800;
           low = (theChar & 0x3ff) + 0xdc00;

           [utf16Data appendBytes:&high length:sizeof(high)];
           theChar = low;
        }

        UniChar c = theChar;
        [utf16Data appendBytes:&c length:sizeof(c)];

        p += utf8DecodeResult;
        len -= utf8DecodeResult;
    }

    return [self initWithData:utf16Data encoding:NSUTF16LittleEndianStringEncoding];
}

- (NSString *)stringWithOnlyDigits {
  NSMutableString *s = [NSMutableString string];
  for (int i = 0; i < self.length; i++) {
    unichar c = [self characterAtIndex:i];
    if (iswdigit(c)) {
      [s appendFormat:@"%c", (char)c];
    }
  }
  return s;
}

- (NSString*)stringByTrimmingLeadingWhitespace {
    int i = 0;

    while ((i < self.length) &&
           [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[self characterAtIndex:i]]) {
        i++;
    }
    return [self substringFromIndex:i];
}

- (NSString *)stringByBase64DecodingStringWithEncoding:(NSStringEncoding)encoding {
    const char *buffer = [self UTF8String];
    int destLength = apr_base64_decode_len(buffer);
    if (destLength <= 0) {
        return nil;
    }
    
    NSMutableData *data = [NSMutableData dataWithLength:destLength];
    char *decodedBuffer = [data mutableBytes];
    int resultLength = apr_base64_decode(decodedBuffer, buffer);
    return [[[NSString alloc] initWithBytes:decodedBuffer
                                     length:resultLength
                                   encoding:NSISOLatin1StringEncoding] autorelease];
}

- (NSString *)stringByTrimmingTrailingWhitespace {
    NSCharacterSet *nonWhitespaceSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:nonWhitespaceSet
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        return self;
    } else if (rangeOfLastWantedCharacter.location < self.length - 1) {
        NSUInteger i = rangeOfLastWantedCharacter.location + 1;
        return [self substringToIndex:i];
    }
    return self;
}

// Returns a substring of contiguous characters only from a given character set
// including some character in the middle of the "haystack" (source) string.
- (NSString *)substringIncludingOffset:(int)offset
            fromCharacterSet:(NSCharacterSet *)charSet
        charsTakenFromPrefix:(int*)charsTakenFromPrefixPtr
{
    if (![self length]) {
        if (charsTakenFromPrefixPtr) {
            *charsTakenFromPrefixPtr = 0;
        }
        return @"";
    }
    NSRange firstBadCharRange = [self rangeOfCharacterFromSet:[charSet invertedSet]
                                                      options:NSBackwardsSearch
                                                        range:NSMakeRange(0, offset)];
    NSRange lastBadCharRange = [self rangeOfCharacterFromSet:[charSet invertedSet]
                                                     options:0
                                                       range:NSMakeRange(offset, [self length] - offset)];
    int start = 0;
    int end = [self length];
    if (firstBadCharRange.location != NSNotFound) {
        start = firstBadCharRange.location + 1;
        if (charsTakenFromPrefixPtr) {
            *charsTakenFromPrefixPtr = offset - start;
        }
    } else if (charsTakenFromPrefixPtr) {
        *charsTakenFromPrefixPtr = offset;
    }
    
    if (lastBadCharRange.location != NSNotFound) {
        end = lastBadCharRange.location;
    }
    
    return [self substringWithRange:NSMakeRange(start, end - start)];
}

// This handles a few kinds of URLs, after trimming whitespace from the beginning and end:
// 1. Well formed strings like:
//    "http://example.com/foo?query#fragment"
// 2. URLs in parens:
//    "(http://example.com/foo?query#fragment)" -> http://example.com/foo?query#fragment
// 3. URLs at the end of a sentence:
//    "http://example.com/foo?query#fragment." -> http://example.com/foo?query#fragment
// 4. Case 2 & 3 combined:
//    "(http://example.com/foo?query#fragment)." -> http://example.com/foo?query#fragment
// 5. Strings without a scheme (http is assumed, previous cases do not apply)
//    "example.com/foo?query#fragment" -> http://example.com/foo?query#fragment
// *offset will be set to the number of characters at the start of self that were skipped past.
// offset may be nil. If |length| is not nil, then *length will be set to the number of chars matched
// in self.
- (NSString *)URLInStringWithOffset:(int *)offset length:(int *)length
{
    NSString* trimmedURLString;
    
    trimmedURLString = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (![trimmedURLString length]) {
        return nil;
    }
    if (offset) {
        *offset = 0;
    }
    
    NSRange range = [trimmedURLString rangeOfString:@":"];
    if (range.location == NSNotFound) {
        if (length) {
            *length = trimmedURLString.length;
        }
        trimmedURLString = [NSString stringWithFormat:@"http://%@", trimmedURLString];
    } else {
        if (length) {
            *length = trimmedURLString.length;
        }
        // Search backwards for the start of the scheme.
        for (int i = range.location - 1; 0 <= i; i--) {
            unichar c = [trimmedURLString characterAtIndex:i];
            if (!isalnum(c)) {
                // Remove garbage before the scheme part
                trimmedURLString = [trimmedURLString substringFromIndex:i + 1];
                if (offset) {
                    *offset = i + 1;
                }
                if (length) {
                    *length = trimmedURLString.length;
                }
                if (c == '(') {
                    // If an open parenthesis is right before the
                    // scheme part, remove the closing parenthesis
                    NSRange closer = [trimmedURLString rangeOfString:@")"];
                    if (closer.location != NSNotFound) {
                        trimmedURLString = [trimmedURLString substringToIndex:closer.location];
                        if (length) {
                            *length = trimmedURLString.length;
                        }
                    }
                }
                break;
            }
        }
    }
    
    // Remove trailing punctuation.
    NSArray *punctuation = @[ @".", @",", @";", @":", @"!" ];
    BOOL found;
    do {
        found = NO;
        for (NSString *pchar in punctuation) {
            if ([trimmedURLString hasSuffix:pchar]) {
                trimmedURLString = [trimmedURLString substringToIndex:trimmedURLString.length - 1];
                found = YES;
                if (length) {
                    (*length)--;
                }
            }
        }
    } while (found);
    
    return trimmedURLString;
}

- (NSString *)stringByEscapingForURL {
    NSString *theString =
        (NSString *) CFURLCreateStringByAddingPercentEscapes(NULL,
                                                             (CFStringRef)self,
                                                             (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                             NULL,
                                                             kCFStringEncodingUTF8);
    return [theString autorelease];
}

- (NSString *)stringByCapitalizingFirstLetter {
    if ([self length] == 0) {
        return self;
    }
    NSString *prefix = [self substringToIndex:1];
    NSString *suffix = [self substringFromIndex:1];
    return [[prefix uppercaseString] stringByAppendingString:suffix];
}

- (NSString *)hexOrDecimalConversionHelp {
    unsigned long long value;
    BOOL decToHex;
    if ([self hasPrefix:@"0x"] && [self length] <= 18) {
        decToHex = NO;
        NSScanner *scanner = [NSScanner scannerWithString:self];
        
        [scanner setScanLocation:2]; // bypass 0x
        if (![scanner scanHexLongLong:&value]) {
            return nil;
        }
    } else {
        decToHex = YES;
        value = [self longLongValue];
    }
    if (!value) {
        return nil;
    }
    
    BOOL is32bit;
    if (decToHex) {
        is32bit = ((long long)value >= -2147483648LL && (long long)value <= 2147483647LL);
    } else {
        is32bit = [self length] <= 10;
    }
    
    if (is32bit) {
        // Value fits in a signed 32-bit value, so treat it as such
        int intValue = (int)value;
        if (decToHex) {
            return [NSString stringWithFormat:@"%d = 0x%x", intValue, intValue];
        } else if (intValue >= 0) {
            return [NSString stringWithFormat:@"0x%x = %d", intValue, intValue];
        } else {
            return [NSString stringWithFormat:@"0x%x = %d or %u", intValue, intValue, intValue];
        }
    } else {
        // 64-bit value
        if (decToHex) {
            return [NSString stringWithFormat:@"%lld = 0x%llx", value, value];
        } else if ((long long)value >= 0) {
            return [NSString stringWithFormat:@"0x%llx = %lld", value, value];
        } else {
            return [NSString stringWithFormat:@"0x%llx = %lld or %llu", value, value, value];
        }
    }
}

- (BOOL)stringIsUrlLike {
    return [self hasPrefix:@"http://"] || [self hasPrefix:@"https://"];
}

@end

@implementation NSMutableString (iTerm)

- (void)trimTrailingWhitespace {
    NSCharacterSet *nonWhitespaceSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:nonWhitespaceSet
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        [self deleteCharactersInRange:NSMakeRange(0, self.length)];
    } else if (rangeOfLastWantedCharacter.location < self.length - 1) {
        NSUInteger i = rangeOfLastWantedCharacter.location + 1;
        [self deleteCharactersInRange:NSMakeRange(i, self.length - i)];
    }
}

@end