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
#import "NSData+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"
#import "NSCharacterSet+iTerm.h"
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
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth {
    if (unicode <= 0xa0 ||
        (unicode > 0x452 && unicode < 0x1100)) {
        // Quickly cover the common cases.
        return NO;
    }

    if ([[NSCharacterSet fullWidthCharacterSet] longCharacterIsMember:unicode]) {
        return YES;
    }
    if (ambiguousIsDoubleWidth &&
        [[NSCharacterSet ambiguousWidthCharacterSet] longCharacterIsMember:unicode]) {
        return YES;
    }
    return NO;
}

+ (NSString *)stringFromPasteboard {
    NSPasteboard *board;

    board = [NSPasteboard generalPasteboard];
    assert(board != nil);

    NSArray *supportedTypes = @[ NSFilenamesPboardType, NSStringPboardType ];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    NSString* info = nil;
    DLog(@"Getting pasteboard string...");
    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [board propertyListForType:NSFilenamesPboardType];
        NSMutableArray *escapedFilenames = [NSMutableArray array];
        DLog(@"Pasteboard has filenames: %@.", filenames);
        for (NSString *filename in filenames) {
            [escapedFilenames addObject:[filename stringWithEscapedShellCharacters]];
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
    return info;
}

+ (NSString *)shellEscapableCharacters {
    return @"\\ ()\"&'!$<>;|*?[]#`";
}

- (NSString *)stringWithEscapedShellCharacters {
    NSMutableString *aMutableString = [[[NSMutableString alloc] initWithString:self] autorelease];
    [aMutableString escapeShellCharacters];
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

- (NSArray *)componentsBySplittingProfileListQuery {
    return [self componentsBySplittingStringWithQuotesAndBackslashEscaping:@{}];
}

- (NSArray *)componentsInShellCommand {
    return [self componentsBySplittingStringWithQuotesAndBackslashEscaping:@{ @'n': @"\n",
                                                                              @'a': @"\x07",
                                                                              @'t': @"\t",
                                                                              @'r': @"\r" } ];
}

- (NSArray *)componentsBySplittingStringWithQuotesAndBackslashEscaping:(NSDictionary *)escapes {
    NSMutableArray *result = [NSMutableArray array];

    int inQuotes = 0; // Are we inside double quotes?
    BOOL escape = NO;  // Should this char be escaped?
    NSMutableString *currentValue = [NSMutableString string];
    BOOL valueStarted = NO;
    BOOL firstCharacterNotQuotedOrEscaped = NO;

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
        }

        if (c == '\\' && !escape) {
            escape = YES;
            continue;
        }

        if (escape) {
            valueStarted = YES;
            escape = NO;
            if (escapes[@(c)]) {
                [currentValue appendString:escapes[@(c)]];
            } else {
                [currentValue appendFormat:@"%C", c];
            }
            continue;
        }

        if (c == '"') {
            inQuotes = !inQuotes;
            valueStarted = YES;
            continue;
        }

        if (c == 0) {
            inQuotes = NO;
        }

        // Treat end-of-string like whitespace.
        BOOL isWhitespace = (c == 0 || iswspace(c));

        if (!inQuotes && isWhitespace) {
            if (valueStarted) {
                if (firstCharacterNotQuotedOrEscaped) {
                    [result addObject:[currentValue stringByExpandingTildeInPath]];
                } else {
                    [result addObject:currentValue];
                }
                currentValue = [NSMutableString string];
                firstCharacterNotQuotedOrEscaped = NO;
                valueStarted = NO;
            }
            // If !valueStarted, this char is meaningless whitespace.
            continue;
        }

        if (!valueStarted) {
            firstCharacterNotQuotedOrEscaped = !inQuotes;
        }
        valueStarted = YES;
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
    return [[[NSString alloc] initWithData:[NSData dataWithBase64EncodedString:self]
                                  encoding:encoding] autorelease];
}

- (NSString *)stringByTrimmingTrailingWhitespace {
    return [self stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSString *)stringByTrimmingTrailingCharactersFromCharacterSet:(NSCharacterSet *)charset {
    NSCharacterSet *invertedCharset = [charset invertedSet];
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:invertedCharset
                                                               options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        return self;
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
    if (closingString) {
        self = [self substringFromIndex:1];
        NSRange range = [self rangeOfString:closingString];
        if (range.location != NSNotFound) {
            return [self substringToIndex:range.location];
        }
    }

    return self;
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
        NSCharacterSet *alphaNumericCharset = [NSCharacterSet alphanumericCharacterSet];
        for (NSInteger i = ((NSInteger)range.location) - 1; i >= 0; i--) {
            if (![alphaNumericCharset characterIsMember:[trimmedURLString characterAtIndex:i]]) {
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
    int index;
    for (index = 0; 2*index < self.length; index++) {
      unichar start = [self characterAtIndex:index];
      unichar end = [self characterAtIndex:self.length-index-1];
      if (!((start == '(' && end == ')') ||
            (start == '<' && end == '>') ||
            (start == '[' && end == ']') ||
            (start == '{' && end == '}') ||
            (start == '\'' && end == '\'') ||
            (start == '"' && end == '"'))) {
          break;
      }
    }
    return [self substringWithRange:NSMakeRange(index, self.length-2*index)];
}

- (NSString *)stringByRemovingTerminatingPunctuation {
    NSString *s = self;
    NSArray *punctuationMarks = @[ @"!", @"?", @".", @",", @";", @":", @"...", @"…" ];
    BOOL found;
    do {
        found = NO;
        for (NSString *punctuationString in punctuationMarks) {
            if ([s hasSuffix:punctuationString]) {
                s = [s substringToIndex:s.length - 1];
                found = YES;
            }
        }
    } while (found);
    
    return s;
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
        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        // doubles run out of precision at 2^53. The largest Java timestamp we will convert is less
        // than 2^41, so this is fine.
        NSTimeInterval timestamp = [self doubleValue];
        NSString *template;
        if (self.length == kJavaTimestampLength) {
            // Convert milliseconds to seconds
            timestamp /= 1000.0;
            template = @"yyyyMMMd hh:mm:ss.SSS z";
        } else {
            template = @"yyyyMMMd hh:mm:ss z";
        }
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:template
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
        return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
    } else {
        return nil;
    }
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

    NSNumberFormatter *numberFormatter = [[[NSNumberFormatter alloc] init] autorelease];
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
    return [[result copy] autorelease];
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
    return [[result copy] autorelease];
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
    unichar *in = malloc(in_len);
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
    out = malloc(sizeof(unichar) * out_len);
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
    if (c < 'a' || c >= 'z') {
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
        [[[NSAttributedString alloc] initWithString:self attributes:attributes] autorelease];
    return [attributedString heightForWidth:maxWidth];
}

- (NSArray *)keyValuePair {
    NSRange range = [self rangeOfString:@"="];
    if (range.location == NSNotFound) {
        return @[ self, @"" ];
    } else {
        return @[ [self substringToIndex:range.location],
                  [self substringFromIndex:range.location + 1] ];
    }
}

- (NSString *)stringByPerformingSubstitutions:(NSDictionary *)substitutions {
    NSMutableString *temp = [[self mutableCopy] autorelease];
    for (NSString *original in substitutions) {
        NSString *replacement = substitutions[original];
        [temp replaceOccurrencesOfString:original
                              withString:replacement
                                 options:NSLiteralSearch
                                   range:NSMakeRange(0, temp.length)];
    }
    return temp;
}

// Replace substrings like \(foo) or \1...\9 with the value of vars[@"foo"] or vars[@"1"].
- (NSString *)stringByReplacingVariableReferencesWithVariables:(NSDictionary *)vars {
    unichar *chars = (unichar *)malloc(self.length * sizeof(unichar));
    [self getCharacters:chars];
    enum {
        kLiteral,
        kEscaped,
        kInParens
    } state = kLiteral;
    NSMutableString *result = [NSMutableString string];
    NSMutableString *varName = nil;
    for (int i = 0; i < self.length; i++) {
        unichar c = chars[i];
        switch (state) {
            case kLiteral:
                if (c == '\\') {
                    state = kEscaped;
                } else {
                    [result appendFormat:@"%C", c];
                }
                break;

            case kEscaped:
                if (c == '(') {
                    state = kInParens;
                    varName = [NSMutableString string];
                } else {
                    // \1...\9 also work as subs.
                    NSString *singleCharVar = [NSString stringWithFormat:@"%C", c];
                    if (singleCharVar.integerValue > 0 && vars[singleCharVar]) {
                        [result appendString:vars[singleCharVar]];
                    } else {
                        [result appendFormat:@"\\%C", c];
                    }
                    state = kLiteral;
                }
                break;

            case kInParens:
                if (c == ')') {
                    state = kLiteral;
                    NSString *value = vars[varName];
                    if (value) {
                        [result appendString:value];
                    }
                } else {
                    [varName appendFormat:@"%C", c];
                }
                break;
        }
    }
    free(chars);
    return result;
}

- (BOOL)containsString:(NSString *)substring {
    return [self rangeOfString:substring].location != NSNotFound;
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
    if (keyMods & NSControlKeyMask) {
        [theKeyString appendString: @"^"];
    }
    if (keyMods & NSAlternateKeyMask) {
        [theKeyString appendString: @"⌥"];
    }
    if (keyMods & NSShiftKeyMask) {
        [theKeyString appendString: @"⇧"];
    }
    if (keyMods & NSCommandKeyMask) {
        [theKeyString appendString: @"⌘"];
    }
    return theKeyString;
}

+ (NSString *)uuid {
    CFUUIDRef uuidObj = CFUUIDCreate(nil);
    NSString *uuidString = (NSString *)CFUUIDCreateString(nil, uuidObj);
    CFRelease(uuidObj);
    return [uuidString autorelease];
}

- (NSString *)stringByReplacingControlCharsWithQuestionMark {
    return [self stringByReplacingOccurrencesOfRegex:@"[\x00-\x1f\x7f]" withString:@"?"];
}

- (NSSet *)doubleDollarVariables {
    NSMutableSet *set = [NSMutableSet set];
    [self enumerateStringsMatchedByRegex:@"\\$\\$(.*?)\\$\\$"
                                 options:RKLNoOptions
                                 inRange:NSMakeRange(0, self.length)
                                   error:nil
                      enumerationOptions:RKLRegexEnumerationNoOptions
                              usingBlock:^(NSInteger captureCount, NSString *const *capturedStrings, const NSRange *capturedRanges, volatile BOOL *const stop) {
                                  [set addObject:[[capturedStrings[0] copy] autorelease]];
                              }];
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
    CFIndex index = 0;
    NSRange range;
    do {
        CFRange tempRange = CFStringGetRangeOfComposedCharactersAtIndex((CFStringRef)self, index);
        range = NSMakeRange(tempRange.location, tempRange.length);
        if (range.length > 0) {
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
    NSMutableDictionary *attributes = [[baseAttributes ?: @{} mutableCopy] autorelease];
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

- (void)escapeShellCharacters {
    NSString* charsToEscape = [NSString shellEscapableCharacters];
    for (int i = 0; i < [charsToEscape length]; i++) {
        NSString* before = [charsToEscape substringWithRange:NSMakeRange(i, 1)];
        NSString* after = [@"\\" stringByAppendingString:before];
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
