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
#import "iTermSwiftyStringParser.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
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
#import <wctype.h>

@implementation NSString (iTerm)

+ (NSString *)stringWithInt:(int)num {
    return [NSString stringWithFormat:@"%d", num];
}

+ (BOOL)isDoubleWidthCharacter:(int)unicode
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
                unicodeVersion:(NSInteger)version {
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

    NSArray *supportedTypes = @[ NSFilenamesPboardType, NSStringPboardType ];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    NSString* info = nil;
    DLog(@"Getting pasteboard string...");
    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [board propertyListForType:NSFilenamesPboardType];
        NSMutableArray *escapedFilenames = [NSMutableArray array];
        DLog(@"Pasteboard has filenames: %@.", filenames);
        for (NSString *filename in filenames) {
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
        info = [board stringForType:NSStringPboardType];
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

- (NSString *)stringWithPercentEscape
{
    // From
    // http://stackoverflow.com/questions/705448/iphone-sdk-problem-with-ampersand-in-the-url-string
    static NSMutableCharacterSet *allowedCharacters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowedCharacters = [[NSCharacterSet URLHostAllowedCharacterSet] mutableCopy];
        [allowedCharacters removeCharactersInString:@"￼=,!$&'()*+;@?\n\"<>#\t :/"];
    });

    return [self stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters];
}

- (NSString*)stringWithLinefeedNewlines
{
    return [[self stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"]
               stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
}

- (NSArray *)componentsBySplittingProfileListQuery {
    return [self componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
}

- (NSArray *)componentsInShellCommand {
    return [self componentsBySplittingStringWithQuotesAndBackslashEscaping:@{ @'n': @"\n",
                                                                              @'a': @"\x07",
                                                                              @'t': @"\t",
                                                                              @'r': @"\r" } ];
}

- (NSString *)it_stringByExpandingBackslashEscapedCharacters {
    NSDictionary *escapes = @{ @'n': @('\n'),
                               @'a': @('\x07'),
                               @'t': @('\t'),
                               @'r': @('\r'),
                               @'\\': @('\\') };
    NSMutableString *result = [NSMutableString string];
    NSInteger start = 0;
    BOOL escape = NO;
    for (NSInteger i = 0; i < self.length; i++) {
        unichar c = [self characterAtIndex:i];
        if (escape) {
            NSNumber *replacement = escapes[@(c)] ?: @(c);
            [result appendString:[self substringWithRange:NSMakeRange(start, i - start - 1)]];
            [result appendCharacter:replacement.shortValue];
            start = i + 1;
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

- (NSArray *)componentsBySplittingStringWithQuotesAndBackslashEscaping:(NSDictionary *)escapes {
    NSMutableArray *result = [NSMutableArray array];

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
                    [result addObject:[currentValue stringByExpandingTildeInPath]];
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

    return [self rangeOfString:trimmedURLString];
}

- (NSString *)stringByRemovingEnclosingBrackets {
    if (self.length < 2) {
        return self;
    }
    NSString *trimmed = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *pairs = @[ @[ @"(", @")" ],
                        @[ @"<", @">" ],
                        @[ @"[", @"]" ],
                        @[ @"{", @"}", ],
                        @[ @"\'", @"\'" ],
                        @[ @"\"", @"\"" ] ];
    for (NSArray *pair in pairs) {
        if ([trimmed hasPrefix:pair[0]] && [trimmed hasSuffix:pair[1]]) {
            return [[self substringWithRange:NSMakeRange(1, self.length - 2)] stringByRemovingEnclosingBrackets];
        }
    }
    return self;
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


- (NSString *)stringByEscapingForURL {
    static NSMutableCharacterSet *allowedCharacters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowedCharacters = [[NSCharacterSet URLHostAllowedCharacterSet] mutableCopy];
        [allowedCharacters addCharactersInString:@"!*'();:@&=+$,/?%#[]"];
    });

    return [self stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters];
}

- (NSString *)stringByCapitalizingFirstLetter {
    if ([self length] == 0) {
        return self;
    }
    NSString *prefix = [self substringToIndex:1];
    NSString *suffix = [self substringFromIndex:1];
    return [[prefix uppercaseString] stringByAppendingString:suffix];
}

+ (instancetype)stringWithHumanReadableSize:(unsigned long long)value {
    if (value < 1024) {
        return nil;
    }
    unsigned long long num = value;
    int pow = 0;
    BOOL exact = YES;
    while (num >= 1024 * 1024) {
        pow++;
        if (num % 1024 != 0) {
            exact = NO;
        }
        num /= 1024;
    }
    // Show 2 fraction digits, always rounding downwards. Printf rounds floats to the nearest
    // representable value, so do the calculation with integers until we get 100-fold the desired
    // value, and then switch to float.
    if (100 * num % 1024 != 0) {
        exact = NO;
    }
    num = 100 * num / 1024;
    NSArray *iecPrefixes = @[ @"Ki", @"Mi", @"Gi", @"Ti", @"Pi", @"Ei" ];
    return [NSString stringWithFormat:@"%@%.2f %@",
               exact ? @"" :@ "≈", (double)num / 100, iecPrefixes[pow]];
}

- (NSArray<NSString *> *)helpfulSynonyms {
    NSMutableArray *array = [NSMutableArray array];
    NSString *hexOrDecimalConversion = [self hexOrDecimalConversionHelp];
    if (hexOrDecimalConversion) {
        [array addObject:hexOrDecimalConversion];
    }
    NSString *timestampConversion = [self timestampConversionHelp];
    if (timestampConversion) {
        [array addObject:timestampConversion];
    }
    NSString *utf8Help = [self utf8Help];
    if (utf8Help) {
        [array addObject:utf8Help];
    }
    if (array.count) {
        return array;
    } else {
        return nil;
    }
}

- (NSString *)utf8Help {
    if (self.length == 0) {
        return nil;
    }

    CFRange graphemeClusterRange = CFStringGetRangeOfComposedCharactersAtIndex((CFStringRef)self, 0);
    if (graphemeClusterRange.location != 0 ||
        graphemeClusterRange.length != self.length) {
        // Only works for a single grapheme cluster.
        return nil;
    }

    if ([self characterAtIndex:0] < 128 && self.length == 1) {
        // No help for ASCII
        return nil;
    }

    // Convert to UCS-4
    NSData *data = [self dataUsingEncoding:NSUTF32StringEncoding];
    const int *characters = (int *)data.bytes;
    int numCharacters = data.length / 4;

    // Output UTF-8 hex codes
    NSMutableArray *byteStrings = [NSMutableArray array];
    const char *utf8 = [self UTF8String];
    for (size_t i = 0; utf8[i]; i++) {
        [byteStrings addObject:[NSString stringWithFormat:@"0x%02x", utf8[i] & 0xff]];
    }
    NSString *utf8String = [byteStrings componentsJoinedByString:@" "];

    // Output UCS-4 hex codes
    NSMutableArray *ucs4Strings = [NSMutableArray array];
    for (NSUInteger i = 0; i < numCharacters; i++) {
        if (characters[i] == 0xfeff) {
            // Ignore byte order mark
            continue;
        }
        [ucs4Strings addObject:[NSString stringWithFormat:@"U+%04x", characters[i]]];
    }
    NSString *ucs4String = [ucs4Strings componentsJoinedByString:@" "];

    return [NSString stringWithFormat:@"“%@” = %@ = %@ (UTF-8)", self, ucs4String, utf8String];
}

- (NSString *)timestampConversionHelp {
    NSDate *date;
    date = [self dateValueFromUnix];
    if (!date) {
        date = [self dateValueFromUTC];
    }
    if (date) {
        NSString *template;
        if (fmod(date.timeIntervalSince1970, 1) > 0.001) {
            template = @"yyyyMMMd hh:mm:ss.SSS z";
        } else {
            template = @"yyyyMMMd hh:mm:ss z";
        }
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:template
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
        return [fmt stringFromDate:date];
    } else {
        return nil;
    }
}

- (NSDate *)dateValueFromUnix {
    static const NSUInteger kTimestampLength = 10;
    static const NSUInteger kJavaTimestampLength = 13;
    if ((self.length == kTimestampLength ||
         self.length == kJavaTimestampLength) &&
        [self hasPrefix:@"1"]) {
        for (int i = 0; i < kTimestampLength; i++) {
            if (!isdigit([self characterAtIndex:i])) {
                return nil;
            }
        }
        // doubles run out of precision at 2^53. The largest Java timestamp we will convert is less
        // than 2^41, so this is fine.
        NSTimeInterval timestamp = [self doubleValue];
        if (self.length == kJavaTimestampLength) {
            // Convert milliseconds to seconds
            timestamp /= 1000.0;
        }
        return [NSDate dateWithTimeIntervalSince1970:timestamp];
    } else {
        return nil;
    }
}

- (NSString *)it_contentHash {
    return [self dataUsingEncoding:NSUTF8StringEncoding].it_sha256.it_hexEncoded;
}

- (NSString *)it_unescapedTmuxWindowName {
    return [self stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
}

- (NSDate *)dateValueFromUTC {
    NSArray<NSString *> *formats = @[ @"E, d MMM yyyy HH:mm:ss zzz",
                                      @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                                      @"yyyy-MM-dd't'HH:mm:ss.SSS'z'",
                                      @"yyyy-MM-dd'T'HH:mm:ss'Z'",
                                      @"yyyy-MM-dd't'HH:mm:ss'z'",
                                      @"yyyy-MM-dd'T'HH:mm'Z'",
                                      @"yyyy-MM-dd't'HH:mm'z'" ];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    for (NSString *format in formats) {
        dateFormatter.dateFormat = format;
        dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        NSDate *date = [dateFormatter dateFromString:self];
        if (date) {
            return date;
        }
    }
    return nil;
}

- (NSString *)hexOrDecimalConversionHelp {
    unsigned long long value;
    BOOL mustBePositive = NO;
    BOOL decToHex;
    BOOL is32bit;
    if ([self hasPrefix:@"0x"] && [self length] <= 18) {
        decToHex = NO;
        NSScanner *scanner = [NSScanner scannerWithString:self];
        [scanner setScanLocation:2]; // bypass 0x
        if (![scanner scanHexLongLong:&value]) {
            return nil;
        }
        is32bit = [self length] <= 10;
    } else {
        decToHex = YES;
        NSDecimalNumber *temp = [NSDecimalNumber decimalNumberWithString:self];
        if ([temp isEqual:[NSDecimalNumber notANumber]]) {
            return nil;
        }
        NSDecimalNumber *smallestSignedLongLong =
            [NSDecimalNumber decimalNumberWithString:@"-9223372036854775808"];
        NSDecimalNumber *largestUnsignedLongLong =
            [NSDecimalNumber decimalNumberWithString:@"18446744073709551615"];
        if ([temp doubleValue] > 0) {
            if ([temp compare:largestUnsignedLongLong] == NSOrderedDescending) {
                return nil;
            }
            mustBePositive = YES;
            is32bit = ([temp compare:@2147483648LL] == NSOrderedAscending);
        } else if ([temp compare:smallestSignedLongLong] == NSOrderedAscending) {
            // Negative but smaller than a signed 64 bit can hold
            return nil;
        } else {
            // Negative but fits in signed 64 bit
            is32bit = ([temp compare:@-2147483649LL] == NSOrderedDescending);
        }
        value = [temp unsignedLongLongValue];
    }

    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    NSString *humanReadableSize = [NSString stringWithHumanReadableSize:value];
    if (humanReadableSize) {
        humanReadableSize = [NSString stringWithFormat:@" (%@)", humanReadableSize];
    } else {
        humanReadableSize = @"";
    }

    if (is32bit) {
        // Value fits in a signed 32-bit value, so treat it as such
        int intValue =
        (int)value;
        NSString *formattedDecimalValue = [numberFormatter stringFromNumber:@(intValue)];
        if (decToHex) {
            if (intValue < 0) {
                humanReadableSize = @"";
            }
            return [NSString stringWithFormat:@"%@ = 0x%x%@",
                       formattedDecimalValue, intValue, humanReadableSize];
        } else if (intValue >= 0) {
            return [NSString stringWithFormat:@"0x%x = %@%@",
                       intValue, formattedDecimalValue, humanReadableSize];
        } else {
            unsigned int unsignedIntValue = (unsigned int)value;
            NSString *formattedUnsignedDecimalValue =
                [numberFormatter stringFromNumber:@(unsignedIntValue)];
            return [NSString stringWithFormat:@"0x%x = %@ or %@%@",
                       intValue, formattedDecimalValue, formattedUnsignedDecimalValue,
                       humanReadableSize];
        }
    } else {
        // 64-bit value
        NSDecimalNumber *decimalNumber;
        long long signedValue = value;
        if (!mustBePositive && signedValue < 0) {
            decimalNumber = [NSDecimalNumber decimalNumberWithMantissa:-signedValue
                                                              exponent:0
                                                            isNegative:YES];
        } else {
            decimalNumber = [NSDecimalNumber decimalNumberWithMantissa:value
                                                              exponent:0
                                                            isNegative:NO];
        }
        NSString *formattedDecimalValue = [numberFormatter stringFromNumber:decimalNumber];
        if (decToHex) {
            if (!mustBePositive && signedValue < 0) {
                humanReadableSize = @"";
            }
            return [NSString stringWithFormat:@"%@ = 0x%llx%@",
                       formattedDecimalValue, value, humanReadableSize];
        } else if (signedValue >= 0) {
            return [NSString stringWithFormat:@"0x%llx = %@%@",
                       value, formattedDecimalValue, humanReadableSize];
        } else {
            // Value is negative and converting hex to decimal.
            NSDecimalNumber *unsignedDecimalNumber =
                [NSDecimalNumber decimalNumberWithMantissa:value
                                                  exponent:0
                                                isNegative:NO];
            NSString *formattedUnsignedDecimalValue =
                [numberFormatter stringFromNumber:unsignedDecimalNumber];
            return [NSString stringWithFormat:@"0x%llx = %@ or %@%@",
                       value, formattedDecimalValue, formattedUnsignedDecimalValue,
                       humanReadableSize];
        }
    }
}

- (BOOL)stringIsUrlLike {
    return [self hasPrefix:@"http://"] || [self hasPrefix:@"https://"];
}

- (NSFont *)fontValue {
    float fontSize;
    char utf8FontName[128];
    NSFont *aFont;

    if ([self length] == 0) {
        return ([NSFont userFixedPitchFontOfSize:0.0]);
    }

    sscanf([self UTF8String], "%127s %g", utf8FontName, &fontSize);
    // The sscanf man page is unclear whether it will always null terminate when the length hits the
    // maximum field width, so ensure it is null terminated.
    utf8FontName[127] = '\0';

    aFont = [NSFont fontWithName:[NSString stringWithFormat:@"%s", utf8FontName] size:fontSize];
    if (aFont == nil) {
        return ([NSFont userFixedPitchFontOfSize:0.0]);
    }

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
    NSString *noNewlineSelf = [self stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (noNewlineSelf.length <= maxLength) {
        return noNewlineSelf;
    }
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange firstNonWhitespaceRange = [noNewlineSelf rangeOfCharacterFromSet:[whitespace invertedSet]];
    if (firstNonWhitespaceRange.location == NSNotFound) {
        return @"";
    }
    int length = noNewlineSelf.length - firstNonWhitespaceRange.location;
    if (length < maxLength) {
        return [noNewlineSelf substringFromIndex:firstNonWhitespaceRange.location];
    } else {
        NSString *prefix = [noNewlineSelf substringWithRange:NSMakeRange(firstNonWhitespaceRange.location, maxLength - 1)];
        return [prefix stringByAppendingString:@"…"];
    }
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
    return theKeyString;
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
        } else {
            NSRange capture = NSMakeRange(start, NSMaxRange(range) - start);
            NSString *string = [self substringWithRange:capture];
            if (string.length > 4) {  // length of 4 implies $$$$, which should be interpreted as $$
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
                range.length = rangeOfFirstException.location - range.location;
                minimumLocation = NSMaxRange(range);
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

- (void)reverseEnumerateSubstringsEqualTo:(NSString *)query
                                    block:(void (^)(NSRange range))block {
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

- (NSUInteger)firstCharacter {
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

    return NSMakeRect(0, 0, size.width, size.height);
}

- (void)it_drawInRect:(CGRect)rect attributes:(NSDictionary *)attributes {
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(ctx);

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
            char utf8[2] = { i, 0 };
            NSString *from = [NSString stringWithUTF8String:utf8];
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

- (NSString *)stringByDroppingLastCharacters:(NSInteger)count {
    if (count >= self.length) {
        return @"";
    }
    if (count <= 0) {
        return self;
    }
    return [self substringWithRange:NSMakeRange(0, self.length - count)];
}

- (NSString *)stringByAppendingVariablePathComponent:(NSString *)component {
    if (self.length == 0) {
        return component;
    } else {
        return [self stringByAppendingFormat:@".%@", component];
    }
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
    NSScanner *scanner = [NSScanner localizedScannerWithString:self];
    double d;
    if (![scanner scanDouble:&d]) {
        return 0;
    }
    return d;
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

- (void)escapeShellCharactersIncludingNewlines:(BOOL)includingNewlines {
    if ([iTermAdvancedSettingsModel escapeWithQuotes]) {
        [self escapeShellCharactersWithSingleQuotesIncludingNewlines:includingNewlines];
    } else {
        [self escapeShellCharactersWithBackslashIncludingNewlines:includingNewlines];
    }
}

- (void)escapeShellCharactersWithSingleQuotesIncludingNewlines:(BOOL)includingNewlines {
    // Only need to escape single quote and backslash in a single-quoted string
    NSMutableString *charsToEscape = [@"\\'" mutableCopy];
    NSMutableCharacterSet *charsToSearch = [NSMutableCharacterSet characterSetWithCharactersInString:[NSString shellEscapableCharacters]];
    if (includingNewlines) {
        [charsToEscape appendString:@"\r\n"];
        [charsToSearch addCharactersInString:@"\r\n"];
    }
    if ([self rangeOfCharacterFromSet:charsToSearch].location != NSNotFound) {
        [self escapeCharacters:charsToEscape];
        [self insertString:@"'" atIndex:0];
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
    for (int i = 0; i < [charsToEscape length]; i++) {
        NSString *before = [charsToEscape substringWithRange:NSMakeRange(i, 1)];
        NSString *after = [@"\\" stringByAppendingString:before];
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
