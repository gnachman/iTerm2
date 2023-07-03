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

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermOrderedDictionary.h"
#import "iTermPreferences.h"
#import "iTermSwiftyStringParser.h"
#import "iTermTuple.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSAttributedString+PSM.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSLocale+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"
#import "NSCharacterSet+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "RegexKitLite.h"
#import "ScreenChar.h"
#import <apr-1/apr_base64.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#import <wctype.h>

@implementation NSString (iTerm)

+ (NSString *)stringWithInt:(int)num {
    return [NSString stringWithFormat:@"%d", num];
}

+ (BOOL)isDoubleWidthCharacter:(int)unicode
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
                unicodeVersion:(NSInteger)version
                fullWidthFlags:(BOOL)fullWidthFlags {
    if (unicode <= 0xa0 ||
        (unicode > 0x452 && unicode < 0x1100)) {
        // Quickly cover the common cases.
        return NO;
    }

    if ([[NSCharacterSet fullWidthCharacterSetForUnicodeVersion:version] longCharacterIsMember:unicode]) {
        return YES;
    }
    if (ambiguousIsDoubleWidth &&
        [[NSCharacterSet ambiguousWidthCharacterSetForUnicodeVersion:version] longCharacterIsMember:unicode]) {
        return YES;
    }
    if (fullWidthFlags && [[NSCharacterSet flagCharactersForUnicodeVersion:version] longCharacterIsMember:unicode]) {
        return YES;
    }
    return NO;
}

+ (NSString *)stringWithLongCharacter:(UTF32Char)longCharacter {
    if (longCharacter <= 0xffff) {
        unichar c = longCharacter;
        return [self stringWithCharacters:&c length:1];
    }
    UniChar c[2];
    CFStringGetSurrogatePairForLongCharacter(longCharacter, c);
    return [[NSString alloc] initWithCharacters:c length:2];
}

+ (NSString *)stringFromPasteboard {
    NSPasteboard *board;
    if (gDebugLogging) {
        DLog(@"--- begin list of items ---");
        for (NSPasteboardItem *item in [[NSPasteboard generalPasteboard] pasteboardItems]) {
            DLog(@"Item=%@", item);
            for (NSPasteboardType type in item.types) {
                DLog(@"  For type %@: plist=%@ data=%@ string=%@", type, [item propertyListForType:type], [item dataForType:type], [item stringForType:type]);
            }
        }
        DLog(@"--- end list of items ---");
    }
    board = [NSPasteboard generalPasteboard];
    if (!board) {
        DLog(@"Failed to get the general pasteboard!");
        return nil;
    }

    NSArray *supportedTypes = @[ NSPasteboardTypeFileURL, NSPasteboardTypeString ];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    NSString* info = nil;
    DLog(@"Getting pasteboard string...");
    const BOOL remote = ([board availableTypeFromArray:@[ (NSPasteboardType)@"com.apple.is-remote-clipboard" ]] != nil);
    const BOOL isURL = [bestType isEqualToString:NSPasteboardTypeFileURL];
    if (remote && isURL) {
        DLog(@"Pasteboard has a string from a remote clipboard");
        NSArray<NSURL *> *urls = [board readObjectsForClasses:@[ [NSURL class] ]
                                                           options:nil];
        NSArray<NSString *> *strings = [urls mapWithBlock:^id _Nullable(NSURL * _Nonnull url) {
            DLog(@"Load %@", url);
            NSAttributedString *attributedString = [[NSAttributedString alloc] initWithURL:url
                                                                                   options:@{}
                                                                        documentAttributes:nil
                                                                                     error:nil];
            DLog(@"Got string of length %@", @(attributedString.length));
            return attributedString.string;
        }];
        DLog(@"Concatenate %@ strings", @(strings.count));
        info = [strings componentsJoinedByString:@"\n"];
    } else if (isURL) {
        NSArray<NSURL *> *urls = [board readObjectsForClasses:@[ [NSURL class] ]
                                                           options:nil];
        NSMutableArray *escapedFilenames = [NSMutableArray array];
        DLog(@"Pasteboard has filenames: %@.", urls);
        for (NSURL *url in urls) {
            NSString *filename = url.path;
            [escapedFilenames addObject:[filename stringWithEscapedShellCharactersIncludingNewlines:YES]];
        }
        if (escapedFilenames.count > 0) {
            info = [escapedFilenames componentsJoinedByString:@" "];
        }
        if ([info length] == 0) {
            info = nil;
        }
    } else {
        DLog(@"Pasteboard has a string.");
        info = [board stringForType:NSPasteboardTypeString];
    }
    if (!info) {
        DLog(@"Using fallback technique of iterating pasteboard items %@", [[NSPasteboard generalPasteboard] pasteboardItems]);
        for (NSPasteboardItem *item in [[NSPasteboard generalPasteboard] pasteboardItems]) {
            info = [item stringForType:(NSString *)kUTTypeUTF8PlainText];
            if (info) {
                return info;
            }
        }
    }
    return info;
}

+ (NSString *)shellEscapableCharacters {
    return @"\\ ()\"&'!$<>;|*?[]#`\t{}";
}

- (NSString *)stringWithBackslashEscapedShellCharactersIncludingNewlines:(BOOL)includingNewlines {
    NSMutableString *aMutableString = [[NSMutableString alloc] initWithString:self];
    [aMutableString escapeShellCharactersWithBackslashIncludingNewlines:includingNewlines];
    return [NSString stringWithString:aMutableString];
}

- (NSString *)stringEscapedForBash {
    NSMutableString *aMutableString = [[NSMutableString alloc] initWithString:self];
    [aMutableString escapeShellCharactersForBash];
    return [NSString stringWithString:aMutableString];
}

- (NSString *)stringWithEscapedShellCharactersIncludingNewlines:(BOOL)includingNewlines {
    NSMutableString *aMutableString = [[NSMutableString alloc] initWithString:self];
    [aMutableString escapeShellCharactersIncludingNewlines:includingNewlines];
    return [NSString stringWithString:aMutableString];
}

- (NSString *)stringWithEscapedShellCharactersExceptTabAndNewline {
    NSMutableString *aMutableString = [[NSMutableString alloc] initWithString:self];
    [aMutableString escapeShellCharactersExceptTabAndNewline];
    return [NSString stringWithString:aMutableString];
}

- (NSString *)stringWithShellEscapedTabs
{
    const int kLNEXT = 22;
    NSString *replacement = [NSString stringWithFormat:@"%c\t", kLNEXT];

    return [self stringByReplacingOccurrencesOfString:@"\t" withString:replacement];
}

- (NSString*)stringWithLinefeedNewlines
{
    return [[self stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"]
               stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
}

- (NSArray *)componentsBySplittingProfileListQuery {
    return [self componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
}

- (NSString *)it_substringToIndex:(NSInteger)index {
    if (index < 0) {
        return @"";
    }
    if (self.length < index) {
        return self;
    }
    return [self substringToIndex:index];
}

- (void)enumerateLongCharacters:(void (^)(UTF32Char c, BOOL *stop))block {
    const NSInteger length = self.length;
    BOOL expectingLowSurrogate = NO;
    unichar highSurrogate = 0;

    BOOL stop = NO;
    for (NSInteger i = 0; !stop && i < length; i++) {
        unichar c = [self characterAtIndex:i];
        if (IsHighSurrogate(c)) {
            // If the previous character was also a high surrogate, quitely ignore it.
            expectingLowSurrogate = YES;
            highSurrogate = c;
            continue;
        }
        if (IsLowSurrogate(c)) {
            if (expectingLowSurrogate) {
                block(DecodeSurrogatePair(highSurrogate, c), &stop);
                expectingLowSurrogate = NO;
            }
            // If the previous character was not a high surrogate, quitely ignore this one.
            continue;
        }
        // Not a surrogate
        block(c, &stop);
    }
}

- (NSString *)it_escapedForRegex {
    NSMutableString *result = [NSMutableString string];
    [self enumerateLongCharacters:^(UTF32Char c, BOOL *stop) {
        [result appendFormat:@"\\U%08x", c];
    }];
    return result;
}

- (NSArray<NSString *> *)componentsInShellCommand {
    NSNumber *nkey = @'n';
    NSNumber *akey = @'a';
    NSNumber *tkey = @'t';
    NSNumber *rkey = @'r';
    return [self componentsBySplittingStringWithQuotesAndBackslashEscaping:@{ nkey: @"\n",
                                                                              akey: @"\x07",
                                                                              tkey: @"\t",
                                                                              rkey: @"\r" } ];
}

- (NSString *)it_compressedString {
    NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
    data = [data it_compressedData];
    return [data base64EncodedStringWithOptions:0];
}

- (NSString *)it_stringByExpandingBackslashEscapedCharacters {
    NSNumber *nkey = @'n';
    NSNumber *akey = @'a';
    NSNumber *tkey = @'t';
    NSNumber *rkey = @'r';
    NSNumber *bskey = @'\\';
    NSNumber *ekey = @'e';
    NSDictionary *escapes = @{ nkey: @('\n'),
                               akey: @('\x07'),
                               tkey: @('\t'),
                               rkey: @('\r'),
                               bskey: @('\\'),
                               ekey: @('\e') };
    NSMutableString *result = [NSMutableString string];
    NSInteger start = 0;
    BOOL escape = NO;
    for (NSInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        if (escape) {
            if (c == 'u' && i + 4 < self.length) {
                NSString *substring = [self substringWithRange:NSMakeRange(i + 1, 4)];
                NSScanner *scanner = [NSScanner scannerWithString:substring];
                unsigned int hexValue = 0;

                if ([scanner scanHexInt:&hexValue] && scanner.scanLocation == 4) {
                    NSString *replacement = [NSString stringWithLongCharacter:hexValue];
                    [result appendString:[self substringWithRange:NSMakeRange(start, i - start - 1)]];
                    [result appendString:replacement];
                    i += 4;
                    start = i + 1;
                }
            } else {
                NSNumber *replacement = escapes[@(c)];
                if (replacement) {
                    [result appendString:[self substringWithRange:NSMakeRange(start, i - start - 1)]];
                    [result appendCharacter:replacement.shortValue];
                    start = i + 1;
                }
            }
            escape = NO;
        } else if (c == '\\') {
            escape = YES;
        }
    }
    if (self.length > start) {
        [result appendString:[self substringWithRange:NSMakeRange(start, self.length - start)]];
    }
    return result;
}

- (NSArray<NSString *> *)componentsBySplittingStringWithQuotesAndBackslashEscaping:(NSDictionary *)escapes {
    NSMutableArray<NSString *> *result = [NSMutableArray array];

    BOOL inSingleQuotes = NO;
    BOOL inDoubleQuotes = NO; // Are we inside double quotes?
    BOOL escape = NO;  // Should this char be escaped?
    NSMutableString *currentValue = [NSMutableString string];
    BOOL isFirstCharacterOfWord = YES;
    BOOL firstCharacterOfThisWordWasQuoted = YES;

    for (NSInteger i = 0; i <= self.length; i++) {
        unichar c;
        if (i < self.length) {
            c = [self characterAtIndex:i];
            if (c == 0) {
                // Pretty sure this can't happen, but better to be safe.
                c = ' ';
            }
        } else {
            // Signifies end-of-string.
            c = 0;
            escape = NO;
        }

        if (c == '\\' && !escape) {
            escape = YES;
            continue;
        }

        if (escape) {
            isFirstCharacterOfWord = NO;
            escape = NO;
            if (escapes[@(c)]) {
                [currentValue appendString:escapes[@(c)]];
            } else if (inDoubleQuotes) {
                // Determined by testing with bash.
                if (c == '"') {
                    [currentValue appendString:@"\""];
                } else if (c == '\\') {
                    [currentValue appendString:@"\\"];
                } else {
                    [currentValue appendFormat:@"\\%C", c];
                }
            } else if (inSingleQuotes) {
                // Determined by testing with bash.
                if (c == '\'') {
                    [currentValue appendFormat:@"\\"];
                } else {
                    [currentValue appendFormat:@"\\%C", c];
                }
            } else {
                [currentValue appendFormat:@"%C", c];
            }
            continue;
        }

        if (c == '"' && !inSingleQuotes) {
            inDoubleQuotes = !inDoubleQuotes;
            isFirstCharacterOfWord = NO;
            continue;
        }
        if (c == '\'' && !inDoubleQuotes) {
            inSingleQuotes = !inSingleQuotes;
            isFirstCharacterOfWord = NO;
            continue;
        }
        if (c == 0) {
            inSingleQuotes = NO;
            inDoubleQuotes = NO;
        }

        // Treat end-of-string like whitespace.
        BOOL isWhitespace = (c == 0 || iswspace(c));

        if (!inSingleQuotes && !inDoubleQuotes && isWhitespace) {
            if (!isFirstCharacterOfWord) {
                if (!firstCharacterOfThisWordWasQuoted) {
                    [result addObject:[currentValue stringByExpandingTildeInPathPreservingSlash]];
                } else {
                    [result addObject:currentValue];
                }
                currentValue = [NSMutableString string];
                firstCharacterOfThisWordWasQuoted = YES;
                isFirstCharacterOfWord = YES;
            }
            // Ignore whitespace not in quotes or escaped.
            continue;
        }

        if (isFirstCharacterOfWord) {
            firstCharacterOfThisWordWasQuoted = inDoubleQuotes || inSingleQuotes;
            isFirstCharacterOfWord = NO;
        }
        [currentValue appendFormat:@"%C", c];
    }

    return result;
}

// For unknown reasons stringByExpandingTildeInPath removes terminal slashes. This method puts them
// back. That is useful for completion suggestions.
// ~                   -> /Users/example
// ~/                  -> /Users/example/
// /Users/example/foo  -> /Users/example/foo
// /Users/example/foo/ -> /Users/example/foo/
- (NSString *)stringByExpandingTildeInPathPreservingSlash {
    NSString *candidate = [self stringByExpandingTildeInPath];
    if ([self hasSuffix:@"/"] && ![candidate hasSuffix:@"/"]) {
        return [candidate stringByAppendingString:@"/"];
    }
    return candidate;
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

- (NSData *)dataFromHexValues {
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

- (NSData *)dataFromWhitespaceDelimitedHexValues {
    if (![self isMatchedByRegex:@"^[0-9A-Fa-f\\s]+$"]) {
        return nil;
    }
    NSArray<NSString *> *parts = [self componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableData *result = [NSMutableData data];
    for (NSString *string in parts) {
        if (string.length % 2 != 0) {
            return nil;
        }
        NSData *subdata = [string dataFromHexValues];
        [result appendData:subdata];
    }
    return result;
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

- (NSString *)stringByReplacingEscapedChar:(unichar)echar withString:(NSString *)maybeString {
    NSString *s = maybeString ?: @"";
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

- (NSString *)stringByReplacingCommonlyEscapedCharactersWithControls {
    NSString *p = [self stringByReplacingEscapedChar:'a' withString:@"\x07"];
    p = [p stringByReplacingEscapedChar:'b' withString:@"\x08"];
    p = [p stringByReplacingEscapedChar:'e' withString:@"\x1b"];
    p = [p stringByReplacingEscapedChar:'n' withString:@"\n"];
    p = [p stringByReplacingEscapedChar:'r' withString:@"\r"];
    p = [p stringByReplacingEscapedChar:'t' withString:@"\t"];
    p = [p stringByReplacingEscapedChar:'\\' withString:@"\\"];
    p = [p stringByReplacingEscapedHexValuesWithChars];
    return p;
}

- (NSString *)stringByEscapingControlCharactersAndBackslash {
    NSString *result = [self stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    for (int i = 0; i < 32; i++) {
        NSString *replacement = [NSString stringWithFormat:@"\\x%04x", i];
        if (i == '\n') {
            replacement = @"\\n";
        } else if (i == '\r') {
            replacement = @"\\r";
        } else if (i == '\t') {
            replacement = @"\\t";
        }
        result = [result stringByReplacingOccurrencesOfString:[NSString stringWithLongCharacter:i]
                                                   withString:replacement];
    }
    return result;
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

// This function finds the longest initial sequence of bytes that look like a valid UTF-8 sequence.
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

- (NSString *)base64EncodedWithEncoding:(NSStringEncoding)encoding {
    NSData *data = [self dataUsingEncoding:encoding];
    return [data base64EncodedStringWithOptions:0];
}

- (NSString *)stringByBase64DecodingStringWithEncoding:(NSStringEncoding)encoding {
    return [[NSString alloc] initWithData:[NSData dataWithBase64EncodedString:self]
                                 encoding:encoding];
}

- (NSString *)stringByTrimmingTrailingWhitespace {
    return [self stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSString *)stringByTrimmingTrailingCharactersFromCharacterSet:(NSCharacterSet *)charset {
    NSCharacterSet *invertedCharset = [charset invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:invertedCharset
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        if ([self rangeOfCharacterFromSet:charset].location == NSNotFound) {
            return self;
        } else {
            return @"";
        }
    } else if (rangeOfLastWantedCharacter.location + rangeOfLastWantedCharacter.length < self.length) {
        NSUInteger i = rangeOfLastWantedCharacter.location + rangeOfLastWantedCharacter.length;
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
        start = NSMaxRange(firstBadCharRange);
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

// Transforms a string like "(abc)def" into "abc".
- (NSString *)stringByRemovingEnclosingPunctuationMarks {
    if (self.length == 0) {
        return self;
    }
    NSDictionary *wrappers = @{ @('('): @")",
                                @('[') : @"]",
                                @('"'): @"\"",
                                @('\''): @"'" };
    unichar c = [self characterAtIndex:0];
    NSString *closingString = wrappers[@(c)];
    NSString *string = self;
    if (closingString) {
        string = [string substringFromIndex:1];
        NSRange range = [string rangeOfString:closingString];
        if (range.location != NSNotFound) {
            return [string substringToIndex:range.location];
        }
    }

    return string;
}

- (NSRange)rangeOfURLInString {
    NSString *trimmedURLString;

    // Trim whitespace
    trimmedURLString = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (![trimmedURLString length]) {
        return NSMakeRange(NSNotFound, 0);
    }

    NSRange range = [trimmedURLString rangeOfString:@":"];
    if (range.location != NSNotFound) {
        // Search backward to find the start of the scheme.
        NSMutableCharacterSet *schemeCharacterSet = [NSMutableCharacterSet alphanumericCharacterSet];
        [schemeCharacterSet addCharactersInString:@"-"];  // for chrome-devtools: and x-man-page:, issue 5298
        for (NSInteger i = ((NSInteger)range.location) - 1; i >= 0; i--) {
            if (![schemeCharacterSet characterIsMember:[trimmedURLString characterAtIndex:i]]) {
                trimmedURLString = [trimmedURLString substringFromIndex:i];

                // Handle URLs like *(http://example.com)
                NSInteger lengthBefore = trimmedURLString.length;
                trimmedURLString = [trimmedURLString stringByRemovingEnclosingPunctuationMarks];
                if (trimmedURLString.length == lengthBefore) {
                    // Handle URLs like *http://example.com
                    trimmedURLString = [trimmedURLString substringFromIndex:1];
                }
                break;
            }
        }
    } else {
        // If the string begins with an opening brace or quote, return just the bracketed string.
        trimmedURLString = [trimmedURLString stringByRemovingEnclosingPunctuationMarks];
    }
    if (![trimmedURLString length]) {
        return NSMakeRange(NSNotFound, 0);
    }

    // Remove trailing punctuation.
    trimmedURLString = [trimmedURLString stringByRemovingTerminatingPunctuation];
    trimmedURLString = [trimmedURLString stringByTrimmingLeadingHyphens];

    return [self rangeOfString:trimmedURLString];
}

- (NSString *)stringByRemovingSuffix:(NSString *)suffix {
    if (![self hasSuffix:suffix]) {
        return self;
    }
    return [self stringByDroppingLastCharacters:suffix.length];
}

- (NSString *)stringByRemovingPrefix:(NSString *)prefix {
    if (![self hasPrefix:prefix]) {
        return self;
    }
    return [self substringFromIndex:prefix.length];
}

- (NSString *)stringByRemovingTerminatingPunctuation {
    NSCharacterSet *punctuationCharacterSet = [NSCharacterSet characterSetWithCharactersInString:[iTermAdvancedSettingsModel trailingPunctuationMarks]];
    NSRange range = [self rangeOfCharacterFromSet:punctuationCharacterSet options:(NSBackwardsSearch | NSAnchoredSearch)];
    if (range.length > 0 && range.location != NSNotFound) {
        return [self substringToIndex:range.location];
    } else {
        return self;
    }
}

- (NSString *)stringByTrimmingLeadingHyphens {
    NSCharacterSet *characterSet = [[NSCharacterSet characterSetWithCharactersInString:@"-"] invertedSet];
    const NSRange range = [self rangeOfCharacterFromSet:characterSet];
    if (range.location == NSNotFound) {
        return @"";
    }
    return [self substringFromIndex:range.location];
}

- (NSString *)stringByCapitalizingFirstLetter {
    if ([self length] == 0) {
        return self;
    }
    NSString *prefix = [self substringToIndex:1];
    NSString *suffix = [self substringFromIndex:1];
    return [[prefix uppercaseString] stringByAppendingString:suffix];
}

- (NSString *)it_contentHash {
    return [self dataUsingEncoding:NSUTF8StringEncoding].it_sha256.it_hexEncoded;
}

- (NSString *)it_unescapedTmuxWindowName {
    return [self stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
}

- (BOOL)stringIsUrlLike {
    return [self hasPrefix:@"http://"] || [self hasPrefix:@"https://"];
}

- (NSFont *)fontValue {
    if ([self length] == 0) {
        return [NSFont userFixedPitchFontOfSize:0.0] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    NSScanner *scanner = [NSScanner scannerWithString:self];
    NSString *fontName = nil;
    [scanner scanUpToString:@" " intoString:&fontName];
    if (!fontName) {
        DLog(@"Failed to scan font name from “%@” so using system standard font", self);
        return [NSFont userFixedPitchFontOfSize:0.0] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@" "];
    float fontSize = 0;
    if (![scanner scanFloat:&fontSize]) {
        DLog(@"Failed to scan font size from “%@” so using system standard font", self);
        return [NSFont userFixedPitchFontOfSize:0.0] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    if (@available(macOS 12, *)) {
        if ([fontName hasPrefix:@"."] && ![fontName hasPrefix:@".AppleSystemUIFont"]) {
            // Well this is terrible
            // Starting in, I guess, Ventura you can't round-trip font names for some mystery fonts.
            // Somehow users have a font name of .SFNS-Regular in their prefs. This came from maybe
            // an older OS version? Who the hell knows.
            // Anyway when you try to create it now it gives you motherfucking times roman out of pure
            // unadulterated spite.
            // I reversed coretext and found that it fucks you for not names that start with a . except
            // .AppleSystemUIFont. I guess I have to reverse this code every new OS version?
            // 🖕to you too, CoreText.
            // This will probably break something but fucked if I know what.
            // Issue 10625
            DLog(@"Translate font %@ to system font", fontName);
            return [NSFont systemFontOfSize:fontSize];
        }
    }
    NSString *suffix = [self substringFromIndex:scanner.scanLocation];
    NSDictionary *dict = [NSDictionary castFrom:[NSJSONSerialization JSONObjectWithData:[suffix dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]];
    NSArray *featureSettings = [NSArray castFrom:dict[@"featureSettings"]];
    NSMutableDictionary *attributes = [@{
        NSFontNameAttribute: fontName,
        NSFontSizeAttribute: @(fontSize),
    } mutableCopy];
    if (featureSettings) {
        attributes[NSFontFeatureSettingsAttribute] = featureSettings;
    }
    NSFontDescriptor *descriptor = [[NSFontDescriptor alloc] initWithFontAttributes:attributes];
    NSFont *aFont = [NSFont fontWithDescriptor:descriptor textTransform:nil];
    if (aFont == nil) {
        DLog(@"Failed to look up font named %@. Falling back to to user font", fontName);
        return [NSFont userFixedPitchFontOfSize:0.0] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    DLog(@"Font %@ is %@", fontName, aFont);

    return aFont;
}

- (NSString *)hexEncodedString {
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < self.length; i++) {
        [result appendFormat:@"%02X", [self characterAtIndex:i]];
    }
    return [result copy];
}

+ (NSString *)stringWithHexEncodedString:(NSString *)hexEncodedString {
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i + 1 < hexEncodedString.length; i += 2) {
        char buffer[3] = { [hexEncodedString characterAtIndex:i],
                           [hexEncodedString characterAtIndex:i + 1],
                           0 };
        int value;
        sscanf(buffer, "%02x", &value);
        [result appendFormat:@"%C", (unichar)value];
    }
    return [result copy];
}

// Return TEC converter between UTF16 variants, or NULL on failure.
// You should call TECDisposeConverter on the returned obj.
static TECObjectRef CreateTECConverterForUTF8Variants(TextEncodingVariant variant) {
    TextEncoding utf16Encoding = CreateTextEncoding(kTextEncodingUnicodeDefault,
                                                    kTextEncodingDefaultVariant,
                                                    kUnicodeUTF16Format);
    TextEncoding hfsPlusEncoding = CreateTextEncoding(kTextEncodingUnicodeDefault,
                                                      variant,
                                                      kUnicodeUTF16Format);

    TECObjectRef conv;
    if (TECCreateConverter(&conv, utf16Encoding, hfsPlusEncoding) != noErr) {
        NSLog(@"Failed to create HFS Plus converter.\n");
        return NULL;
    }

    return conv;
}

- (NSString *)_convertBetweenUTF8AndHFSPlusAsPrecomposition:(BOOL)precompose {
    static TECObjectRef gHFSPlusComposed;
    static TECObjectRef gHFSPlusDecomposed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gHFSPlusComposed = CreateTECConverterForUTF8Variants(kUnicodeHFSPlusCompVariant);
        gHFSPlusDecomposed = CreateTECConverterForUTF8Variants(kUnicodeHFSPlusDecompVariant);
    });

    size_t in_len = sizeof(unichar) * [self length];
    size_t out_len;
    unichar *in = iTermMalloc(in_len);
    if (!in) {
        return self;
    }
    unichar *out;
    NSString *ret;

    [self getCharacters:in range:NSMakeRange(0, [self length])];
    out_len = in_len;
    if (!precompose) {
        out_len *= 2;
    }
    out = iTermMalloc(sizeof(unichar) * out_len);
    if (!out) {
        free(in);
        return self;
    }

    if (TECConvertText(precompose ? gHFSPlusComposed : gHFSPlusDecomposed,
                       (TextPtr)in,
                       in_len,
                       &in_len,
                       (TextPtr)out,
                       out_len,
                       &out_len) != noErr) {
        ret = self;
    } else {
        int numCharsOut = out_len / sizeof(unichar);
        ret = [NSString stringWithCharacters:out length:numCharsOut];
    }

    free(in);
    free(out);

    return ret;
}

- (NSString *)precomposedStringWithHFSPlusMapping {
    return [self _convertBetweenUTF8AndHFSPlusAsPrecomposition:YES];
}

- (NSString *)decomposedStringWithHFSPlusMapping {
    return [self _convertBetweenUTF8AndHFSPlusAsPrecomposition:NO];
}

- (NSUInteger)indexOfSubstring:(NSString *)substring fromIndex:(NSUInteger)index {
    return [self rangeOfString:substring options:0 range:NSMakeRange(index, self.length - index)].location;
}

- (NSString *)octalCharacter {
    unichar value = 0;
    for (int i = 0; i < self.length; i++) {
        value *= 8;
        unichar c = [self characterAtIndex:i];
        if (c < '0' || c >= '8') {
            return @"";
        }
        value += c - '0';
    }
    return [NSString stringWithCharacters:&value length:1];
}

- (NSString *)hexCharacter {
    if (self.length == 0 || self.length == 3 || self.length > 4) {
        return @"";
    }

    unsigned int value;
    NSScanner *scanner = [NSScanner scannerWithString:self];
    if (![scanner scanHexInt:&value]) {
        return @"";
    }

    unichar c = value;
    return [NSString stringWithCharacters:&c length:1];
}

- (NSString *)controlCharacter {
    unichar c = [[self lowercaseString] characterAtIndex:0];
    if (c < 'a' || c > 'z') {
        return @"";
    }
    c -= 'a' - 1;
    return [NSString stringWithFormat:@"%c", c];
}

- (NSString *)metaCharacter {
    return [NSString stringWithFormat:@"%c%@", 27, self];
}

- (NSString *)stringByExpandingVimSpecialCharacters {
    enum {
        kSpecialCharacterThreeDigitOctal,  // \...    three-digit octal number (e.g., "\316")
        kSpecialCharacterTwoDigitOctal,    // \..     two-digit octal number (must be followed by non-digit)
        kSpecialCharacterOneDigitOctal,    // \.      one-digit octal number (must be followed by non-digit)
        kSpecialCharacterTwoDigitHex,      // \x..    byte specified with two hex numbers (e.g., "\x1f")
        kSpecialCharacterOneDigitHex,      // \x.     byte specified with one hex number (must be followed by non-hex char)
        kSpecialCharacterFourDigitUnicode, // \u....  character specified with up to 4 hex numbers
        kSpecialCharacterBackspace,        // \b      backspace <BS>
        kSpecialCharacterEscape,           // \e      escape <Esc>
        kSpecialCharacterFormFeed,         // \f      formfeed <FF>
        kSpecialCharacterNewline,          // \n      newline <NL>
        kSpecialCharacterReturn,           // \r      return <CR>
        kSpecialCharacterTab,              // \t      tab <Tab>
        kSpecialCharacterBackslash,        // \\      backslash
        kSpecialCharacterDoubleQuote,      // \"      double quote
        kSpecialCharacterControlKey,       // \<C-W>  Control key
        kSpecialCharacterMetaKey,          // \<M-W>  Meta key
    };

    NSDictionary *regexes =
        @{ @"^(([0-7]{3}))": @(kSpecialCharacterThreeDigitOctal),
           @"^(([0-7]{2}))(?:[^0-8]|$)": @(kSpecialCharacterTwoDigitOctal),
           @"^(([0-7]))(?:[^0-8]|$)": @(kSpecialCharacterOneDigitOctal),
           @"^(x([0-9a-fA-F]{2}))": @(kSpecialCharacterTwoDigitHex),
           @"^(x([0-9a-fA-F]))(?:[^0-9a-fA-F]|$)": @(kSpecialCharacterOneDigitHex),
           @"^(u([0-9a-fA-F]{4}))": @(kSpecialCharacterFourDigitUnicode),
           @"^(b)": @(kSpecialCharacterBackspace),
           @"^(e)": @(kSpecialCharacterEscape),
           @"^(f)": @(kSpecialCharacterFormFeed),
           @"^(n)": @(kSpecialCharacterNewline),
           @"^(r)": @(kSpecialCharacterReturn),
           @"^(t)": @(kSpecialCharacterTab),
           @"^(\\\\)": @(kSpecialCharacterBackslash),
           @"^(\")": @(kSpecialCharacterDoubleQuote),
           @"^(<C-([A-Za-z])>)": @(kSpecialCharacterControlKey),
           @"^(<M-([A-Za-z])>)": @(kSpecialCharacterMetaKey) };


    NSMutableString *result = [NSMutableString string];
    __block int haveAppendedUpToIndex = 0;
    NSUInteger index = [self indexOfSubstring:@"\\" fromIndex:0];
    while (index != NSNotFound && index < self.length) {
        [result appendString:[self substringWithRange:NSMakeRange(haveAppendedUpToIndex,
                                                                  index - haveAppendedUpToIndex)]];
        haveAppendedUpToIndex = index + 1;
        NSString *fragment = [self substringFromIndex:haveAppendedUpToIndex];
        BOOL foundMatch = NO;
        for (NSString *regex in regexes) {
            NSRange regexRange = [fragment rangeOfRegex:regex];
            if (regexRange.location != NSNotFound) {
                foundMatch = YES;
                NSArray *capture = [fragment captureComponentsMatchedByRegex:regex];
                index += [capture[1] length] + 1;
                // capture[0]: The whole match
                // capture[1]: Characters to consume
                // capture[2]: Optional. Characters of interest.
                switch ([regexes[regex] intValue]) {
                    case kSpecialCharacterThreeDigitOctal:
                    case kSpecialCharacterTwoDigitOctal:
                    case kSpecialCharacterOneDigitOctal:
                        [result appendString:[capture[2] octalCharacter]];
                        break;

                    case kSpecialCharacterFourDigitUnicode:
                    case kSpecialCharacterTwoDigitHex:
                    case kSpecialCharacterOneDigitHex:
                        [result appendString:[capture[2] hexCharacter]];
                        break;

                    case kSpecialCharacterBackspace:
                        [result appendFormat:@"%c", 0x7f];
                        break;

                    case kSpecialCharacterEscape:
                        [result appendFormat:@"%c", 27];
                        break;

                    case kSpecialCharacterFormFeed:
                        [result appendFormat:@"%c", 12];
                        break;

                    case kSpecialCharacterNewline:
                        [result appendString:@"\n"];
                        break;

                    case kSpecialCharacterReturn:
                        [result appendString:@"\r"];
                        break;

                    case kSpecialCharacterTab:
                        [result appendString:@"\t"];
                        break;

                    case kSpecialCharacterBackslash:
                        [result appendString:@"\\"];
                        break;

                    case kSpecialCharacterDoubleQuote:
                        [result appendString:@"\""];
                        break;

                    case kSpecialCharacterControlKey:
                        [result appendString:[capture[2] controlCharacter]];
                        break;

                    case kSpecialCharacterMetaKey:
                        [result appendString:[capture[2] metaCharacter]];
                        break;
                }
                haveAppendedUpToIndex = index;
                break;
            }  // If a regex matched
        }  // for loop over regexes
        if (!foundMatch) {
            ++index;
        }
        index = [self indexOfSubstring:@"\\" fromIndex:index];
    }  // while searching for backslashes

    index = self.length;
    [result appendString:[self substringWithRange:NSMakeRange(haveAppendedUpToIndex,
                                                              index - haveAppendedUpToIndex)]];

    return result;
}

- (CGFloat)heightWithAttributes:(NSDictionary *)attributes constrainedToWidth:(CGFloat)maxWidth {
    NSAttributedString *attributedString =
        [[NSAttributedString alloc] initWithString:self attributes:attributes];
    return [attributedString heightForWidth:maxWidth];
}

- (iTermTuple *)keyValuePair {
    return [self it_stringBySplittingOnFirstSubstring:@"="];
}

- (iTermTuple<NSString *, NSString *> *)it_stringBySplittingOnFirstSubstring:(NSString *)substring {
    NSRange range = [self rangeOfString:substring];
    if (range.location == NSNotFound) {
        return nil;
    } else {
        return [iTermTuple tupleWithObject:[self substringToIndex:range.location]
                                 andObject:[self substringFromIndex:range.location + 1]];
    }
}

- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)searchSet fromIndex:(NSInteger)index {
    if (index >= self.length) {
        return NSMakeRange(NSNotFound, 0);
    }
    return [self rangeOfCharacterFromSet:searchSet options:0 range:NSMakeRange(index, self.length - index)];
}

- (NSIndexSet *)indicesOfCharactersInSet:(NSCharacterSet *)characterSet {
    NSMutableIndexSet *result = [[NSMutableIndexSet alloc] init];
    NSInteger start = 0;
    NSRange range = [self rangeOfCharacterFromSet:characterSet fromIndex:start];
    while (range.location != NSNotFound) {
        [result addIndex:range.location];
        start = range.location + 1;
        range = [self rangeOfCharacterFromSet:characterSet fromIndex:start];
    }
    return result;
}

- (NSString *)stringByPerformingSubstitutions:(NSDictionary *)substitutions {
    NSMutableString *temp = [self mutableCopy];
    for (NSString *original in substitutions) {
        NSString *replacement = substitutions[original];
        [temp replaceOccurrencesOfString:original
                              withString:replacement
                                 options:NSLiteralSearch
                                   range:NSMakeRange(0, temp.length)];
    }
    return temp;
}

- (BOOL)interpolatedStringContainsNonliteral {
    iTermSwiftyStringParser *parser = [[iTermSwiftyStringParser alloc] initWithString:self];
    __block BOOL result = NO;
    [parser enumerateSwiftySubstringsWithBlock:^(NSUInteger index,
                                                 NSString * _Nonnull substring,
                                                 BOOL isLiteral,
                                                 BOOL * _Nonnull stop) {
        if (!isLiteral) {
            result = YES;
            *stop = YES;
        }
    }];
    return result;
}

- (void)enumerateSwiftySubstrings:(void (^)(NSUInteger index, NSString *substring, BOOL isLiteral, BOOL *stop))block {
    iTermSwiftyStringParser *parser = [[iTermSwiftyStringParser alloc] initWithString:self];
    [parser enumerateSwiftySubstringsWithBlock:block];
}

- (NSString *)stringRepeatedTimes:(int)n {
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < n; i++) {
        [result appendString:self];
    }
    return result;
}

- (NSUInteger)numberOfLines {
    NSUInteger stringLength = [self length];
    NSUInteger numberOfLines = 0;
    for (NSUInteger index = 0; index < stringLength; numberOfLines++) {
        index = NSMaxRange([self lineRangeForRange:NSMakeRange(index, 0)]);
    }
    return numberOfLines;
}

- (NSString *)ellipsizedDescriptionNoLongerThan:(int)maxLength {
    NSString *noNewlineSelf = [self stringByReplacingOccurrencesOfRegex:@"[\\r\\n]" withString:@"↩"];
    if (noNewlineSelf.length <= maxLength) {
        return [noNewlineSelf stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange firstNonWhitespaceRange = [noNewlineSelf rangeOfCharacterFromSet:[whitespace invertedSet]];
    if (firstNonWhitespaceRange.location == NSNotFound) {
        return @"";
    }
    int length = noNewlineSelf.length - firstNonWhitespaceRange.location;
    NSString *prefix;
    BOOL truncated = NO;
    if (length < maxLength) {
        prefix = [noNewlineSelf substringFromIndex:firstNonWhitespaceRange.location];
    } else {
        prefix = [noNewlineSelf substringWithRange:NSMakeRange(firstNonWhitespaceRange.location, maxLength - 1)];
        truncated = YES;
    }
    prefix = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *result = prefix;
    if (truncated) {
        result = [result stringByAppendingString:@"…"];
    }
    return result;
}

- (NSString *)stringWithFirstLetterCapitalized {
    if (self.length == 0) {
        return self;
    }
    if (self.length == 1) {
        return [self uppercaseString];
    }
    return [[[self substringToIndex:1] uppercaseString] stringByAppendingString:[self substringFromIndex:1]];
}

+ (NSString *)stringForModifiersWithMask:(NSUInteger)keyMods {
    NSMutableString *theKeyString = [NSMutableString string];
    if (keyMods & iTermLeaderModifierFlag) {
        [theKeyString appendString:[self stringForLeader]];
    }
    if (keyMods & NSEventModifierFlagControl) {
        [theKeyString appendString:@"^"];
    }
    if (keyMods & NSEventModifierFlagOption) {
        [theKeyString appendString:@"⌥"];
    }
    if (keyMods & NSEventModifierFlagShift) {
        [theKeyString appendString:@"⇧"];
    }
    if (keyMods & NSEventModifierFlagCommand) {
        [theKeyString appendString:@"⌘"];
    }
    if (keyMods & NSEventModifierFlagFunction) {
        [theKeyString appendString:@"fn"];
    }
    return theKeyString;
}

+ (NSString *)stringForLeader {
    iTermKeystroke *leader = [[iTermKeyMappings leader] copy];
    if (!leader) {
        return @"L⃢";
    }
    leader.modifierFlags &= ~iTermLeaderModifierFlag;
    return [[iTermKeystrokeFormatter stringForKeystroke:leader] stringByAppendingString:@" "];
}

+ (NSString *)uuid {
    return [[NSUUID UUID] UUIDString];
}

- (NSString *)stringByReplacingControlCharactersWithCaretLetter {
    return [self stringByReplacingOccurrencesOfRegex:@"[\x00-\x1f\x7f]" usingBlock:^NSString *(NSInteger captureCount, NSString *const __unsafe_unretained *capturedStrings, const NSRange *capturedRanges, volatile BOOL *const stop) {
        NSMutableString *replacement = [NSMutableString string];
        const NSInteger index = capturedRanges[0].location;
        for (NSInteger i = 0; i < capturedRanges[0].length; i++) {
            unichar c = [[self substringWithRange:NSMakeRange(index + i, 1)] characterAtIndex:0];
            if (c == 0x7f) {
                [replacement appendString:@"^?"];
            } else {
                [replacement appendFormat:@"^%c", c + '@'];
            }
        }
        return replacement;
    }];
}

- (NSSet *)doubleDollarVariables {
    NSMutableSet *set = [NSMutableSet set];
    NSRange rangeToSearch = NSMakeRange(0, self.length);
    NSInteger start = -1;
    NSRange range;
    while (rangeToSearch.length > 0) {
        range = [self rangeOfString:@"$$" options:NSLiteralSearch range:rangeToSearch];
        if (start < 0) {
            start = range.location;
        } else if (range.location == NSNotFound) {
            break;
        } else {
            NSRange capture = NSMakeRange(start, NSMaxRange(range) - start);
            NSString *string = [self substringWithRange:capture];
            if (string.length >= 4) {  // length of 4 implies $$$$, which should be interpreted as $$
                [set addObject:string];
            }
            start = -1;
        }
        rangeToSearch = NSMakeRange(NSMaxRange(range), MAX(0, (NSInteger)self.length - (NSInteger)NSMaxRange(range)));
    }

    return set;
}

- (BOOL)stringMatchesGlobPattern:(NSString *)glob caseSensitive:(BOOL)caseSensitive {
    NSArray *parts = [glob componentsSeparatedByString:@"*"];
    const BOOL anchorToStart = ![glob hasPrefix:@"*"];

    NSUInteger start = 0;
    for (NSString *part in parts) {
        if (part.length == 0) {
            // This happens with an empty glob or with two stars in a row.
            continue;
        }
        assert(start <= self.length);
        NSRange searchRange = NSMakeRange(start, self.length - start);
        NSRange matchingRange = [self rangeOfString:part
                                            options:caseSensitive ? 0 : NSCaseInsensitiveSearch
                                              range:searchRange];
        if (matchingRange.location == NSNotFound) {
            return NO;
        }
        if (anchorToStart && start == 0 && matchingRange.location != 0) {
            return NO;
        }
        start = NSMaxRange(matchingRange);
    }

    const BOOL anchorToEnd = ![glob hasSuffix:@"*"];
    if (anchorToEnd) {
        return start == self.length;
    } else {
        return YES;
    }
}

- (void)enumerateComposedCharacters:(void (^)(NSRange, unichar, NSString *, BOOL *))block {
    if (self.length == 0) {
        return;
    }
    static dispatch_once_t onceToken;
    static NSCharacterSet *exceptions;
    dispatch_once(&onceToken, ^{
        // These characters are forced to be base characters. Apple's function
        // is a bit overzealous in its definition of composed characters. For
        // example, it treats 0b95 0bcd 0b95 0bc1 as a single composed
        // character. In issue 7788 we see this violates user expectations;
        // since b95 is a base character, it doesn't make sense. However Apple
        // has decided to define grapheme cluster, it doesn't match what we
        // actually want, which is to segment on base characters. It isn't as
        // simple as simply splitting on base characters because combining
        // marks can be picky about which preceding characters they'll combine
        // with. For example, skin tone modifiers don't combine with all emoji. 
        // Apple's function does pick those out properly, so we use it as a
        // starting point and then segment further where we're sure it's safe
        // to do so.
        //
        // Furthermore, (at least some) combining spacing marks behave better
        // when they have their own cell. For example, U+0BC6 when combined with
        // U+0B95. See issue 7788.
        //
        // This also came up in issue 6048 for FF9E and FF9F (HALFWIDTH KATAKANA VOICED SOUND MARK)
        if ([iTermAdvancedSettingsModel aggressiveBaseCharacterDetection]) {
            exceptions = [NSCharacterSet codePointsWithOwnCell];
        } else {
            exceptions = [NSCharacterSet characterSetWithCharactersInString:@"\uff9e\uff9f"];
        }
    });
    CFIndex index = 0;
    NSInteger minimumLocation = 0;
    NSRange range;
    do {
        CFRange tempRange = CFStringGetRangeOfComposedCharactersAtIndex((CFStringRef)self, index);
        if (tempRange.location < minimumLocation) {
            NSInteger diff = minimumLocation - tempRange.location;
            tempRange.location += diff;
            if (diff > tempRange.length) {
                tempRange.length = 0;
            } else {
                tempRange.length -= diff;
            }
        }
        range = NSMakeRange(tempRange.location, tempRange.length);
        if (range.length > 0) {
            NSRange rangeOfFirstException = [self rangeOfCharacterFromSet:exceptions
                                                                  options:NSLiteralSearch
                                                                    range:NSMakeRange(range.location + 1, range.length - 1)];
            if (rangeOfFirstException.location != NSNotFound) {
                const BOOL precededByZWJ = (rangeOfFirstException.location > 0 &&
                                            [self characterAtIndex:rangeOfFirstException.location - 1] == 0x200d);
                if (!precededByZWJ) {
                    range.length = rangeOfFirstException.location - range.location;
                    minimumLocation = NSMaxRange(range);
                }
            }
            unichar simple = range.length == 1 ? [self characterAtIndex:range.location] : 0;
            NSString *complexString = range.length == 1 ? nil : [self substringWithRange:range];
            BOOL stop = NO;
            block(range, simple, complexString, &stop);
            if (stop) {
                return;
            }
        }
        index = NSMaxRange(range);
    } while (NSMaxRange(range) < self.length);
}

- (NSString *)firstComposedCharacter:(NSString **)rest {
    __block NSString *first = nil;
    __block NSString *tail = self;
    [self enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
        first = [self substringWithRange:range];
        tail = [self substringFromIndex:NSMaxRange(range)];
        *stop = YES;
    }];
    if (rest) {
        *rest = tail;
    }
    return first;
}

- (NSString *)lastComposedCharacter {
    __block NSString *substring = nil;
    [self enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
        substring = [self substringWithRange:range];
    }];
    return substring;
}

- (NSInteger)numberOfComposedCharacters {
    __block NSInteger count = 0;
    [self enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
        count += 1;
    }];
    return count;
}

- (NSString *)byTruncatingComposedCharactersInCenter:(NSInteger)numberToOmit {
    const NSInteger length = self.numberOfComposedCharacters;
    if (length < numberToOmit + 2) {
        return nil;
    }
    NSMutableArray<NSString *> *characters = [NSMutableArray array];
    [self enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
        [characters addObject:[self substringWithRange:range]];
    }];
    const NSInteger prefixLength = (length - numberToOmit) / 2;
    NSString *prefix = [[characters subarrayWithRange:NSMakeRange(0, prefixLength)] componentsJoinedByString:@""];
    const NSInteger suffixLength = length - numberToOmit - prefixLength;
    NSString *suffix = [[characters subarrayWithRange:NSMakeRange(characters.count - suffixLength, suffixLength)] componentsJoinedByString:@""];
    return [NSString stringWithFormat:@"%@…%@", prefix, suffix];
}

- (void)reverseEnumerateSubstringsEqualTo:(NSString *)query
                                    block:(void (^ NS_NOESCAPE)(NSRange range))block {
    NSRange range = [self rangeOfString:query options:NSBackwardsSearch];
    while (range.location != NSNotFound) {
        block(range);
        range = [self rangeOfString:query options:NSBackwardsSearch range:NSMakeRange(0, range.location)];
    }
}

- (NSUInteger)iterm_unsignedIntegerValue {
    NSScanner *scanner = [NSScanner scannerWithString:self];
    unsigned long long ull;
    if (![scanner scanUnsignedLongLong:&ull]) {
        ull = 0;
    }
    return ull;
}

- (NSDictionary *)attributesUsingFont:(NSFont *)font fittingSize:(NSSize)maxSize attributes:(NSDictionary *)baseAttributes {
    // Perform a binary search for the point size that best fits |maxSize|.
    CGFloat min = 4;
    CGFloat max = 100;
    int points = (min + max) / 2;
    int prevPoints = -1;
    NSMutableDictionary *attributes = [baseAttributes ?: @{} mutableCopy];
    while (points != prevPoints) {
        attributes[NSFontAttributeName] = [NSFont fontWithName:font.fontName size:points];
        NSRect boundingRect = [self boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                                 options:NSStringDrawingUsesLineFragmentOrigin
                                              attributes:attributes];
        if (boundingRect.size.width > maxSize.width ||
            boundingRect.size.height > maxSize.height) {
            max = points;
        } else if (boundingRect.size.width < maxSize.width &&
                   boundingRect.size.height < maxSize.height) {
            min = points;
        }
        prevPoints = points;
        points = (min + max) / 2;
    }

    attributes[NSFontAttributeName] = [NSFont fontWithName:font.fontName size:points];
    return attributes;
}

- (NSString *)stringByCompactingFloatingPointString {
    if ([self rangeOfString:@"."].location == NSNotFound) {
        // Bogus input. Don't even try.
        return self;
    }
    NSString *compact = [self stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"0"]];
    if ([compact hasSuffix:@"."]) {
        compact = [compact stringByAppendingString:@"0"];
    }
    return compact;
}

// http://www.cse.yorku.ca/~oz/hash.html
- (NSUInteger)hashWithDJB2 {
    NSUInteger hash = 5381;

    for (NSUInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        hash = (hash * 33) ^ c;
    }

    return hash;
}

- (NSData *)hashWithSHA256 {
    return [[self dataUsingEncoding:NSUTF8StringEncoding] it_sha256];
}

- (UTF32Char)firstCharacter {
    if (self.length == 0) {
        return 0;
    } else {
        unichar firstUTF16 = [self characterAtIndex:0];
        if (self.length == 1 || !IsHighSurrogate(firstUTF16)) {
            return firstUTF16;
        }
        unichar secondUTF16 = [self characterAtIndex:1];
        if (!IsLowSurrogate(secondUTF16)) {
            return 0;
        }
        return DecodeSurrogatePair(firstUTF16, secondUTF16);
    }
}

- (BOOL)startsWithQuotationMark {
    return [self hasPrefix:[[NSLocale currentLocale] objectForKey:NSLocaleQuotationBeginDelimiterKey]];
}

- (BOOL)endsWithQuotationMark {
    return [self hasSuffix:[[NSLocale currentLocale] objectForKey:NSLocaleQuotationEndDelimiterKey]];
}

- (BOOL)isInQuotationMarks {
    return [self startsWithQuotationMark] && [self endsWithQuotationMark];
}

- (NSString *)stringByInsertingTerminalPunctuation:(NSString *)punctuation {
    if ([[NSLocale currentLocale] commasAndPeriodsGoInsideQuotationMarks] && [self endsWithQuotationMark]) {
        NSString *endQuote = [[NSLocale currentLocale] objectForKey:NSLocaleQuotationEndDelimiterKey];
        NSInteger quotationLength = [endQuote length];
        NSString *stringWithoutEndQuote = [self substringToIndex:self.length - quotationLength];
        return [[stringWithoutEndQuote stringByAppendingString:punctuation] stringByAppendingString:endQuote];
    } else {
        return [self stringByAppendingString:punctuation];
    }
}

- (NSString *)stringByEscapingForJSON {
    // Escape backslash and " with unicode literals.
    NSString *escaped =
	[[self stringByReplacingOccurrencesOfString:@"\\" withString:@"\\u005c"]
               stringByReplacingOccurrencesOfString:@"\"" withString:@"\\u0022"];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

- (NSString *)stringByEscapingForXML {
    return [[[[[self stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
                     stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]
                     stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"]
                     stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"]
                     stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
}

- (NSArray<NSNumber *> *)codePoints {
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        if (IsHighSurrogate(c) && i + 1 < self.length) {
            i++;
            unichar c2 = [self characterAtIndex:i];
            [result addObject:@(DecodeSurrogatePair(c, c2))];
        } else if (!IsHighSurrogate(c) && !IsLowSurrogate(c)) {
            [result addObject:@(c)];
        }
    }
    return result;
}

- (NSString *)surname {
    return [[self componentsSeparatedByString:@" "] lastObject];
}

- (BOOL)isNumeric {
    if (self.length == 0) {
        return NO;
    }
    NSCharacterSet *nonNumericCharacterSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSRange range = [self rangeOfCharacterFromSet:nonNumericCharacterSet];
    return range.location == NSNotFound;
}

- (BOOL)isNonnegativeFractionalNumber {
    NSArray<NSString *> *parts = [self componentsSeparatedByString:@"."];
    if (parts.count == 0 || parts.count > 2) {
        return NO;
    }
    if (parts.count == 1) {
        // "123"
        return [parts.firstObject isNumeric];
    }
    if (parts.count == 2) {
        if (parts[0].length == 0) {
            // ".1"
            return [parts[1] isNumeric];
        }
        // "1.2"
        return [parts[0] isNumeric] && [parts[1] isNumeric];
    }
    return NO;
}

- (BOOL)startsWithDigit {
    if (![self length]) {
        return NO;
    }

    NSCharacterSet *digitsSet = [NSCharacterSet decimalDigitCharacterSet];
    return [digitsSet characterIsMember:[self characterAtIndex:0]];
}

- (NSRange)makeRangeSafe:(NSRange)range {
    if (range.location == NSNotFound || range.length == 0) {
        return range;
    }
    unichar lastCharacter = [self characterAtIndex:NSMaxRange(range) - 1];
    if (CFStringIsSurrogateHighCharacter(lastCharacter)) {
        if (NSMaxRange(range) == self.length) {
            range.length -= 1;
        } else {
            range.length += 1;
        }
    }
    return range;
}

- (NSString *)stringByMakingControlCharactersToPrintable {
    if (self.length == 0) {
        return self;
    }
    NSMutableString *temp = [self mutableCopy];
    for (NSInteger i = temp.length - 1; i >= 0; i--) {
        unichar c = [temp characterAtIndex:i];
        NSString *replacement = nil;
        if (c >= 1 && c <= 26) {
            replacement = [NSString stringWithFormat:@"^%c", c - 1 + 'A'];
        } else if (c == 0) {
            replacement = @"^@";
        } else if (c == 27) {
            replacement = @"^[";
        } else if (c == 28) {
            replacement = @"^\\";
        } else if (c == 29) {
            replacement = @"^]";
        } else if (c == 30) {
            replacement = @"^^";
        } else if (c == 31) {
            replacement = @"^_";
        } else if (c == 127) {
            replacement = @"^?";
        }
        if (replacement) {
            [temp replaceCharactersInRange:NSMakeRange(i, 1) withString:replacement];
        }
    }
    return temp;
}

- (NSRect)it_boundingRectWithSize:(NSSize)bounds attributes:(NSDictionary *)attributes truncated:(BOOL *)truncated {
    CGSize size = { 0, 0 };
    *truncated = NO;
    for (NSString *part in [self componentsSeparatedByString:@"\n"]) {
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:part
                                                                     attributes:attributes];

        CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((__bridge CFMutableAttributedStringRef)string);
        CFRange fitRange;

        CFRange textRange = CFRangeMake(0, part.length);
        CGSize frameSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
                                                                        textRange,
                                                                        NULL,
                                                                        bounds,
                                                                        &fitRange);
        if (fitRange.length != part.length) {
            *truncated = YES;
        }
        CFRelease(framesetter);
        size.width = MAX(size.width, frameSize.width);
        size.height += frameSize.height;
    }

    return NSMakeRect(0, 0, ceil(size.width), ceil(size.height));
}

- (void)it_drawInRect:(CGRect)rect attributes:(NSDictionary *)attributes {
    [self it_drawInRect:rect attributes:attributes alpha:1];
}

- (void)it_drawInRect:(CGRect)rect attributes:(NSDictionary *)attributes alpha:(CGFloat)alpha {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(ctx);
    CGContextSetAlpha(ctx, alpha);

    for (NSString *part in [self componentsSeparatedByString:@"\n"]) {
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:part
                                                                     attributes:attributes];

        CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((__bridge CFMutableAttributedStringRef)string);

        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, rect);

        CTFrameRef textFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0,0), path, NULL);

        CTFrameDraw(textFrame, ctx);

        CFRelease(textFrame);
        
        CFRange fitRange;

        // Get the height of the line and translate the context down by it
        CFRange textRange = CFRangeMake(0, part.length);
        CGSize frameSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
                                                                        textRange,
                                                                        NULL,
                                                                        rect.size,
                                                                        &fitRange);
        CGContextTranslateCTM(ctx, 0, -frameSize.height);


        CGPathRelease(path);
        CFRelease(framesetter);

    }

    CGContextRestoreGState(ctx);
}

- (BOOL)startsWithEmoji {
    static dispatch_once_t onceToken;
    static NSMutableCharacterSet *emojiSet;
    dispatch_once(&onceToken, ^{
        emojiSet = [[NSMutableCharacterSet alloc] init];
        void (^addRange)(NSUInteger, NSUInteger) = ^(NSUInteger first, NSUInteger last){
            [emojiSet addCharactersInRange:NSMakeRange(first, last - first + 1)];
        };
        addRange(0x1F600, 0x1F64F);  // Emoticons
        addRange(0x1F300, 0x1F5FF);  // Misc Symbols and Pictographs
        addRange(0x1F680, 0x1F6FF);  // Transport and Map
        addRange(0x2600, 0x26FF);    // Misc symbols
        addRange(0x2700, 0x27BF);    // Dingbats
        addRange(0xFE00, 0xFE0F);    // Variation Selectors
        addRange(0x1F900, 0x1F9FF);  // Supplemental Symbols and Pictographs
    });
    return [emojiSet longCharacterIsMember:[self firstCharacter]];
}

- (NSString *)jsonEncodedString {
    NSMutableString *s = [NSMutableString stringWithString:self];
    [s replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"/" withString:@"\\/" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"\n" withString:@"\\n" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"\b" withString:@"\\b" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"\f" withString:@"\\f" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"\r" withString:@"\\r" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];
    [s replaceOccurrencesOfString:@"\t" withString:@"\\t" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [s length])];

    static dispatch_once_t onceToken;
    static NSMutableArray *froms;
    static NSMutableArray *tos;
    static const int numberOfControlCharacters = 0x20;
    dispatch_once(&onceToken, ^{
        froms = [[NSMutableArray alloc] init];
        tos = [[NSMutableArray alloc] init];
        for (int i = 0; i < numberOfControlCharacters; i++) {
            unichar c = i;
            NSString *from = [NSString stringWithCharacters:&c length:1];
            NSString *to = [NSString stringWithFormat:@"\\u%04x", i];
            [froms addObject:from];
            [tos addObject:to];
        }
    });
    for (int i = 0; i < numberOfControlCharacters ; i++) {
        [s replaceOccurrencesOfString:froms[i]
                           withString:tos[i]
                              options:0
                                range:NSMakeRange(0, [s length])];
    }
    return [NSString stringWithFormat:@"\"%@\"", s];
}

+ (NSString *)it_formatBytes:(double)bytes {
    const double k = 1000.0;
    const double mb = k * k;
    const double gb = mb * k;
    const double tb = gb * k;
    const double pb = tb * k;
    struct {
        double limit;
        double divisor;
        NSString *format;
    } units[] = {
        { 1,        1, @"%.0f bytes" }, // 0 bytes
        { k,        1, @"%.0f bytes" }, // 999 bytes
        { 10 * k,   k, @"%.1f kB" },  // 9.9 KB
        { mb,       k, @"%.0f kB" },  // 999 KB
        { 10 * mb, mb, @"%.1f MB" },  // 9.9 MB
        { gb,      mb, @"%.0f MB" },  // 999 MB
        { 10 * gb, gb, @"%.1f GB" },  // 9.9 GB
        { tb,      gb, @"%.0f GB" },  // 999 GB
        { 10 * tb, tb, @"%.1f TB" },  // 9.9 TB
        { pb,      tb, @"%.0f TB" },  // 999 TB
        { 10 * pb, pb, @"%.1f PB" },  // 9.9 PB
        { k * pb,  pb, @"%.0f PB" },  // 999 PB
    };

    for (int i = 0; i < sizeof(units) / sizeof(*units); i++) {
        if (bytes < units[i].limit) {
            return [NSString stringWithFormat:units[i].format, bytes / units[i].divisor];
        }
    }
    return @"∞";
}

+ (NSString *)it_formatBytesCompact:(double)bytes {
    const double k = 1000.0;
    const double mb = k * k;
    const double gb = mb * k;
    const double tb = gb * k;
    const double pb = tb * k;
    struct {
        double limit;
        double divisor;
        NSString *format;
    } units[] = {
        { 10 * k,   k, @"%1.1f kB" },  // 9.9 KB
        { 100 * k,  k, @" %2.0f kB" }, //  99 KB
        { mb,       k, @"%3.0f kB" },  // 999 KB

        { 10 * mb,  mb, @"%1.1f MB" },  // 9.9 MB
        { 100 * mb, mb, @" %2.0f MB" }, //  99 MB
        { gb,       mb, @"%3.0f MB" },  // 999 MB

        { 10 * gb,  gb, @"%1.1f GB" },  // 9.9 GB
        { 100 * gb, gb, @" %2.0f GB" }, //  99 GB
        { tb,       gb, @"%3.0f GB" },  // 999 GB

        { 10 * tb,  tb, @"%1.1f TB" },  // 9.9 TB
        { 100 * tb, tb, @" %2.0f TB" }, //  99 TB
        { pb,       tb, @"%3.0f TB" },  // 999 GB
    };

    for (int i = 0; i < sizeof(units) / sizeof(*units); i++) {
        if (bytes < units[i].limit) {
            return [NSString stringWithFormat:units[i].format, bytes / units[i].divisor];
        }
    }
    return @"     ∞";
}

+ (NSString *)sparkWithHeight:(double)fraction {
    if (fraction <= 0) {
        return @" ";
    }
    if (fraction != fraction) {
        return @" ";
    }
    if (fraction > 1) {
        fraction = 1;
    }
    NSArray *characters = @[ @"▁", @"▂", @"▃", @"▄", @"▅", @"▆", @"▇", @"█" ];
    int index = round(fraction * (characters.count - 1));
    return characters[index];
}

- (id)it_jsonSafeValue {
    return self;
}

- (NSInteger)it_numberOfLines {
    if (self.length == 0) {
        return 0;
    }
    NSMutableData *data = [NSMutableData dataWithLength:self.length * sizeof(unichar)];
    unichar *bytes = data.mutableBytes;
    [self getCharacters:bytes];
    const NSInteger length = self.length;
    NSInteger numberOfLines = 1;
    for (NSInteger i = 0; i < length; i++) {
        if (bytes[i] == '\r' || bytes[i] == '\n') {
            numberOfLines++;
        }
    }
    return numberOfLines;
}

- (BOOL)it_hasPrefix:(NSString *)prefix {
    return prefix.length == 0 || [self hasPrefix:prefix];
}

- (NSString *)it_twoPartVersionNumber {
    NSArray<NSString *> *parts = [self componentsSeparatedByString:@"."];
    if (![parts allWithBlock:^BOOL(NSString *anObject) {
        return anObject.isNumeric;
    }]) {
        return nil;
    }
    if (parts.count < 2) {
        return nil;
    }
    return [[parts subarrayToIndex:2] componentsJoinedByString:@"."];
}

// Adapted from Chromium's Sandbox::QuotePlainString
- (NSString *)stringByEscapingForSandboxLiteral {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        if (c < 128) {
            switch (c) {
                case '\b':
                    [result appendString:@"\\b"];
                    break;
                case '\f':
                    [result appendString:@"\\f"];
                    break;
                case '\n':
                    [result appendString:@"\\n"];
                    break;
                case '\r':
                    [result appendString:@"\\r"];
                    break;
                case '\t':
                    [result appendString:@"\\t"];
                    break;
                case '\\':
                    [result appendString:@"\\\\"];
                    break;
                case '"':
                    [result appendString:@"\\\""];
                    break;
                default:
                    [result appendCharacter:c];
                    break;
            }
        } else {
            [result appendFormat:@"\\u%04X", (unsigned int)c];
        }
    }
    return result;
}

- (NSString *)stringByKeepingLastCharacters:(NSInteger)count {
    if (count >= self.length) {
        return self;
    }
    if (count <= 0) {
        return @"";
    }
    return [self substringFromIndex:self.length - count];
}

- (NSString *)stringByAppendingVariablePathComponent:(NSString *)component {
    if (self.length == 0) {
        return component;
    } else {
        return [self stringByAppendingFormat:@".%@", component];
    }
}

- (NSString *)stringByTrimmingOrphanedSurrogates {
    if (self.length == 0) {
        return self;
    }
    NSInteger i;
    for (i = 0; i < self.length; i++) {
        const unichar firstUTF16 = [self characterAtIndex:i];
        if (!IsHighSurrogate(firstUTF16)) {
            break;
        }
    }
    if (i == self.length) {
        return @"";
    }
    const NSInteger startIndex = i;
    for (i = self.length - 1; i > startIndex; i--) {
        const unichar utf16 = [self characterAtIndex:i];
        if (!IsLowSurrogate(utf16)) {
            break;
        }
    }
    const NSInteger endIndex = i;
    assert(endIndex >= startIndex);
    return [self substringWithRange:NSMakeRange(startIndex, endIndex - startIndex + 1)];
}

- (NSString *)stringByAppendingPathComponents:(NSArray<NSString *> *)pathComponents {
    NSString *result = self;
    for (NSString *component in pathComponents) {
        result = [result stringByAppendingPathComponent:component];
    }
    return result;
}
        
- (NSArray<NSString *> *)it_normalizedTokens {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    [self enumerateSubstringsInRange:NSMakeRange(0, self.length)
                             options:NSStringEnumerationByWords
                          usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
                              [tokens addObject:[substring localizedLowercaseString]];
                          }];
    return tokens;
}

- (double)it_localizedDoubleValue {
    if ([[self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"∞"]) {
        return INFINITY;
    }
    if ([[self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"-∞"]) {
        return -INFINITY;
    }
    NSScanner *scanner = [NSScanner localizedScannerWithString:self];
    double d;
    if (![scanner scanDouble:&d]) {
        return 0;
    }
    return d;
}

- (NSString *)it_escapedForEnv {
    NSArray<iTermTuple<NSString *, NSString *> *> *substitutions =
    @[
        [iTermTuple tupleWithObject:@"\\" andObject:@"\\\\"],
        [iTermTuple tupleWithObject:@"\f" andObject:@"\\f"],
        [iTermTuple tupleWithObject:@"\n" andObject:@"\\n"],
        [iTermTuple tupleWithObject:@"\r" andObject:@"\\r"],
        [iTermTuple tupleWithObject:@"\t" andObject:@"\\t"],
        [iTermTuple tupleWithObject:@"\v" andObject:@"\\v"],
        [iTermTuple tupleWithObject:@"#" andObject:@"\\#"],
        [iTermTuple tupleWithObject:@"$" andObject:@"\\$"],
        [iTermTuple tupleWithObject:@" " andObject:@"\\_"],
        [iTermTuple tupleWithObject:@"\"" andObject:@"\\\""],
        [iTermTuple tupleWithObject:@"'" andObject:@"\\'"],
    ];
    return [self stringByPerformingOrderedSubstitutions:[iTermOrderedDictionary withTuples:substitutions]];
}

- (NSString *)stringByPerformingOrderedSubstitutions:(iTermOrderedDictionary<NSString *, NSString *> *)substitutions {
    return [substitutions.keys reduceWithFirstValue:self block:^NSString *(NSString *accumulator, NSString *key) {
        NSString *replacement = substitutions[key];
        return [accumulator stringByReplacingOccurrencesOfString:key withString:replacement];
    }];
}

- (NSString *)stringByReplacingCharactersAtIndices:(NSIndexSet *)indexSet
                               withStringFromBlock:(NSString *(^ NS_NOESCAPE)(void))replacement {
    NSMutableString *result = [self mutableCopy];
    [indexSet enumerateRangesWithOptions:NSEnumerationReverse usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
        [result replaceCharactersInRange:range withString:replacement()];
    }];
    return [result copy];
}

- (BOOL)caseInsensitiveHasPrefix:(NSString *)prefix {
    const NSRange prefixRange = [self rangeOfString:prefix
                                            options:(NSAnchoredSearch | NSCaseInsensitiveSearch)];
    return prefixRange.location == 0;
}

- (NSString *)removingHTMLFromTabTitleIfNeeded {
    if (![iTermPreferences boolForKey:kPreferenceKeyHTMLTabTitles]) {
        return self;
    }
    NSAttributedString *attributedString = [NSAttributedString newAttributedStringWithHTML:self attributes:@{}];
    return attributedString.string;
}

- (NSNumber *)integerNumber {
    NSInteger value;
    NSScanner *scanner = [NSScanner scannerWithString:self];
    if (![scanner scanInteger:&value]) {
        return nil;
    }
    return @(value);
}

- (BOOL)getHashColorRed:(unsigned int *)red green:(unsigned int *)green blue:(unsigned int *)blue {
    if (![self hasPrefix:@"#"]) {
        return NO;
    }
    if (self.length == 4) {
        NSString *first = [self substringWithRange:NSMakeRange(1, 1)];
        NSString *second = [self substringWithRange:NSMakeRange(2, 1)];
        NSString *third = [self substringWithRange:NSMakeRange(3, 1)];
        NSString *extended = [NSString stringWithFormat:@"#%@%@%@%@%@%@", first, first, second, second, third, third];
        return [extended getHashColorRed:red green:green blue:blue];
    }
    if (self.length == 7) {
        NSScanner *scanner = [NSScanner scannerWithString:[self substringFromIndex:1]];
        unsigned long long ll;
        if (![scanner scanHexLongLong:&ll]) {
            return NO;
        }
        // Callers divide the result by 65535 and we want them to get the same as when they used to divide it by 255.
        double (^f)(long long) = ^double(long long ival) {
            return ((ival & 0xff) * 257);
        };
        *red = f(ll >> 16);
        *green = f(ll >> 8);
        *blue = f(ll >> 0);
        return YES;
    }
    if (self.length != 13) {
        return NO;
    }

    NSUInteger offset = 1;
    const NSUInteger stride = 4;
    unsigned int *pointers[] = {red, green, blue};
    for (int i = 0; i < 3; i++, offset += stride) {
        NSScanner *scanner = [NSScanner scannerWithString:[self substringWithRange:NSMakeRange(offset, 4)]];
        unsigned long long ll;
        if (![scanner scanHexLongLong:&ll]) {
            return NO;
        }
        *pointers[i] = (unsigned int)ll;
    }
    return YES;
}

- (NSString *)it_stringByAppendingCharacter:(unichar)theChar {
    return [self stringByAppendingString:[NSString stringWithCharacters:&theChar length:1]];
}

- (NSDictionary<NSString *, NSString *> *)it_keyValuePairsSeparatedBy:(NSString *)separator {
    NSArray<iTermTuple<NSString *, NSString *> *> *parts = [[self componentsSeparatedByString:separator] mapWithBlock:^id _Nullable(NSString * _Nonnull string) {
        return [string keyValuePair];
    }];
    NSDictionary<NSString *, iTermTuple<NSString *,NSString *> *> *tupleDict = [parts classifyUniquelyWithBlock:^id(iTermTuple<NSString *,NSString *> *tuple) {
        return tuple.firstObject;
    }];
    NSDictionary<NSString *, NSString *> *dict = [tupleDict mapValuesWithBlock:^id(NSString *key, iTermTuple<NSString *, NSString *> *tuple) {
        return tuple.secondObject;
    }];
    return dict;
}

- (UTF32Char)longCharacterAtIndex:(NSInteger)i {
    if (self.length == 0) {
        return 0;
    }
    const UniChar c1 = [self characterAtIndex:0];
    if (!IsHighSurrogate(c1)) {
        return c1;
    }
    if (self.length < 2) {
        return 0;
    }
    const UniChar c2 = [self characterAtIndex:1];
    if (!IsLowSurrogate(c2)) {
        return 0;
    }
    return CFStringGetLongCharacterForSurrogatePair(c1, c2);
}

- (NSString *)stringByReplacingBaseCharacterWith:(UTF32Char)base {
    NSString *baseString = [NSString stringWithLongCharacter:base];
    const NSUInteger length = self.length;
    if (length == 0) {
        return baseString;
    }
    if (IsHighSurrogate([self characterAtIndex:0])) {
        if (length == 1) {
            return baseString;
        }
        if (IsLowSurrogate([self characterAtIndex:1])) {
            return [baseString stringByAppendingString:[self substringFromIndex:2]];
        }
    }
    return [baseString stringByAppendingString:[self substringFromIndex:1]];
}

- (BOOL)beginsWithWhitespace {
    if (self.length == 0) {
        return NO;
    }
    return [[NSCharacterSet whitespaceAndNewlineCharacterSet] longCharacterIsMember:[self longCharacterAtIndex:0]];
}

- (BOOL)endsWithWhitespace {
    if (self.length == 0) {
        return NO;
    }
    NSInteger i = self.length - 1;
    return [[NSCharacterSet whitespaceAndNewlineCharacterSet] longCharacterIsMember:[self longCharacterAtIndex:i]];
}

- (NSRange)rangeOfLastWordFromIndex:(NSUInteger)index {
    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    const NSRange searchRange = NSMakeRange(0, index);
    const NSRange nonWhitespaceRange = [self rangeOfCharacterFromSet:whitespaceCharacterSet.invertedSet
                                                             options:NSBackwardsSearch
                                                               range:searchRange];
    if (nonWhitespaceRange.location == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }

    const NSRange whitespaceRange = [self rangeOfCharacterFromSet:whitespaceCharacterSet
                                                           options:NSBackwardsSearch
                                                             range:NSMakeRange(0, nonWhitespaceRange.location)];
    const NSUInteger startIndex = whitespaceRange.location == NSNotFound ? 0 : NSMaxRange(whitespaceRange);
    const NSUInteger endIndex = NSMaxRange(nonWhitespaceRange);
    return NSMakeRange(startIndex, endIndex - startIndex);
}

- (NSArray<NSString *> *)lastWords:(NSUInteger)count {
    NSMutableArray<NSString *> *words = [NSMutableArray arrayWithCapacity:count];
    NSUInteger index = [self length];

    while ([words count] < count && index > 0) {
        const NSRange range = [self rangeOfLastWordFromIndex:index];
        NSString *word = [self substringWithRange:range];
        if (word.length > 0) {
            [words insertObject:word atIndex:0];
        }
        index = range.location;
    }

    return words;
}

- (NSString *)firstNonEmptyLine {
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    const NSInteger indexOfFirstNonWhitespace = [self rangeOfCharacterFromSet:[whitespace invertedSet]].location;
    if (indexOfFirstNonWhitespace == NSNotFound) {
        return @"";
    }

    NSCharacterSet *newlines = [NSCharacterSet newlineCharacterSet];
    const NSInteger indexOfSubsequentNewline =
    [self rangeOfCharacterFromSet:newlines
                          options:0
                            range:NSMakeRange(indexOfFirstNonWhitespace,
                                              self.length - indexOfFirstNonWhitespace)].location;
    if (indexOfSubsequentNewline == NSNotFound) {
        return [self substringFromIndex:indexOfFirstNonWhitespace];
    }
    return [self substringWithRange:NSMakeRange(indexOfFirstNonWhitespace,
                                                indexOfSubsequentNewline - indexOfFirstNonWhitespace)];
}

- (NSString *)truncatedToLength:(NSInteger)maxLength ellipsis:(NSString *)ellipsis {
    if (self.length <= maxLength) {
        return self;
    }
    return [[self substringToIndex:maxLength - 1] stringByAppendingString:ellipsis];
}

@end

@implementation NSMutableString (iTerm)

- (void)trimTrailingWhitespace {
    NSCharacterSet *nonWhitespaceSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:nonWhitespaceSet
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        [self deleteCharactersInRange:NSMakeRange(0, self.length)];
    } else if (NSMaxRange(rangeOfLastWantedCharacter) < self.length) {
        [self deleteCharactersInRange:NSMakeRange(NSMaxRange(rangeOfLastWantedCharacter),
                                                  self.length - NSMaxRange(rangeOfLastWantedCharacter))];
    }
}

- (void)escapeShellCharactersExceptTabAndNewline {
    NSString *charsToEscape = [[NSString shellEscapableCharacters] stringByReplacingOccurrencesOfString:@"\t" withString:@""];
    return [self escapeCharacters:charsToEscape];
}

- (void)escapeShellCharactersForBash {
    [self escapeShellCharactersWithSingleQuotesIncludingNewlines:YES
                                                         forBash:YES];
}
        
- (void)escapeShellCharactersIncludingNewlines:(BOOL)includingNewlines {
    if ([iTermAdvancedSettingsModel escapeWithQuotes]) {
        [self escapeShellCharactersWithSingleQuotesIncludingNewlines:includingNewlines];
    } else {
        [self escapeShellCharactersWithBackslashIncludingNewlines:includingNewlines];
    }
}

- (void)escapeShellCharactersWithSingleQuotesIncludingNewlines:(BOOL)includingNewlines {
    return [self escapeShellCharactersWithSingleQuotesIncludingNewlines:includingNewlines
                                                                forBash:NO];
}
        
- (void)escapeShellCharactersWithSingleQuotesIncludingNewlines:(BOOL)includingNewlines
                                                       forBash:(BOOL)forBash {
    // Only need to escape single quote and backslash in a single-quoted string
    NSMutableString *charsToEscape = [@"\\'" mutableCopy];
    NSMutableCharacterSet *charsToSearch = [NSMutableCharacterSet characterSetWithCharactersInString:[NSString shellEscapableCharacters]];
    if (includingNewlines) {
        [charsToEscape appendString:@"\r\n"];
        [charsToSearch addCharactersInString:@"\r\n"];
    }
    if ([self rangeOfCharacterFromSet:charsToSearch].location != NSNotFound) {
        [self escapeCharacters:charsToEscape forBash:forBash];
        if (forBash) {
            [self insertString:@"$'" atIndex:0];
        } else {
            [self insertString:@"'" atIndex:0];
        }
        [self appendString:@"'"];
    }
}

- (void)escapeShellCharactersWithBackslashIncludingNewlines:(BOOL)includingNewlines {
    NSString *charsToEscape = [NSString shellEscapableCharacters];
    if (includingNewlines) {
        charsToEscape = [charsToEscape stringByAppendingString:@"\r\n"];
    }
    [self escapeCharacters:charsToEscape];
}

- (void)escapeCharacters:(NSString *)charsToEscape {
    [self escapeCharacters:charsToEscape forBash:NO];
}

- (void)escapeCharacters:(NSString *)charsToEscape forBash:(BOOL)forBash {
    for (int i = 0; i < [charsToEscape length]; i++) {
        NSString *before = [charsToEscape substringWithRange:NSMakeRange(i, 1)];
        NSString *after = [@"\\" stringByAppendingString:before];
        if (forBash & [before isEqualToString:@"'"]) {
            after = @"\\x27";
        }
        [self replaceOccurrencesOfString:before
                              withString:after
                                 options:0
                                   range:NSMakeRange(0, [self length])];
    }
}

- (void)appendCharacter:(unichar)c {
    [self appendString:[NSString stringWithCharacters:&c length:1]];
}

@end
