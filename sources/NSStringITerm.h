// $Id: NSStringITerm.h,v 1.2 2006-11-13 06:57:47 yfabian Exp $
//
//  NSStringJTerminal.h
//
//  Additional fucntion to NSString Class by Category
//  2001.11.13 by Y.Hanahara
//  2002.05.18 by Kiichi Kusama
/*
 **  NSStringIterm.h
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

#import <Cocoa/Cocoa.h>

// This is the standard unicode replacement character for when input couldn't
// be parsed properly but we need to render something there.
#define UNICODE_REPLACEMENT_CHAR 0xfffd

// Examine the leading UTF-8 sequence in a char array and check that it
// is properly encoded. Computes the number of bytes to use for the
// first code point. Returns the first code point, if it exists, in *result.
//
// Return value:
// positive: This many bytes compose a legal Unicode character.
// negative: abs(this many) bytes are illegal, should be replaced by one
//   single replacement symbol.
// zero: Unfinished sequence, input needs to grow.
int decode_utf8_char(const unsigned char * restrict datap,
                     int datalen,
                     int * restrict result);

@interface NSString (iTerm)

+ (NSString *)stringWithInt:(int)num;
+ (BOOL)isDoubleWidthCharacter:(int)unicode
        ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth;

// Returns the current string on the pasteboard (if any).
+ (NSString *)stringFromPasteboard;

// Returns the set of characters that should be backslash-escaped.
+ (NSString *)shellEscapableCharacters;

// Returns the number of lines in a string.
- (NSUInteger)numberOfLines;
- (NSString *)stringWithEscapedShellCharacters;

// Replaces tab with ^V + tab.
- (NSString *)stringWithShellEscapedTabs;

// Properly escapes chars for a string to stick in a URL query param.
- (NSString*)stringWithPercentEscape;

// Convert DOS-style and \n newlines to \r newlines.
- (NSString*)stringWithLinefeedNewlines;

// Takes a shell command like
//   foo ~root "~"    bar\ baz   ""
// and returns an array like:
//   @[ @"foo", @"/Users/root", @"~", @"bar baz", @"" ]
- (NSArray *)componentsInShellCommand;

// Same as componentsInShellCommand but \r, \n, \t, and \a map to the letters r, n, t, and a,
// not to controls.
- (NSArray *)componentsBySplittingProfileListQuery;

- (NSString *)stringByReplacingBackreference:(int)n withString:(NSString *)s;
- (NSString *)stringByReplacingEscapedChar:(unichar)echar withString:(NSString *)s;
- (NSString *)stringByReplacingEscapedHexValuesWithChars;
- (NSString *)stringByEscapingQuotes;

// Convert a string of hex values (an even number of [0-9A-Fa-f]) into data.
- (NSData *)dataFromHexValues;

// Always returns a non-null vaule, but it may contain replacement chars for
// malformed utf-8 sequences.
- (NSString *)initWithUTF8DataIgnoringErrors:(NSData *)data;

// Returns a string containing only the digits.
- (NSString *)stringWithOnlyDigits;

- (NSString *)stringByTrimmingLeadingWhitespace;
- (NSString *)stringByTrimmingTrailingWhitespace;

- (NSString *)stringByTrimmingTrailingCharactersFromCharacterSet:(NSCharacterSet *)charset;

- (NSString *)stringByBase64DecodingStringWithEncoding:(NSStringEncoding)encoding;

// Returns a substring of contiguous characters only from a given character set
// including some character in the middle of the target.
- (NSString *)substringIncludingOffset:(int)offset
                      fromCharacterSet:(NSCharacterSet *)charSet
                  charsTakenFromPrefix:(int*)charsTakenFromPrefixPtr;

// This handles a few kinds of URLs, after trimming whitespace from the beginning and end:
// 1. Well formed strings like:
//    "http://example.com/foo?query#fragment"
// 2. URLs in parens:
//    "(http://example.com/foo?query#fragment)" -> http://example.com/foo?query#fragment
// 3. URLs at the end of a sentence:
//    "http://example.com/foo?query#fragment." -> http://example.com/foo?query#fragment
// 4. Case 2 & 3 combined:
//    "(http://example.com/foo?query#fragment)." -> http://example.com/foo?query#fragment
//    "(http://example.com/foo?query#fragment.)" -> http://example.com/foo?query#fragment
// 5. Strings wrapped by parens, square brackets, double quotes, or single quotes.
//    "'example.com/foo'" -> http://example.com/foo
//    "(example.com/foo)" -> http://example.com/foo
//    "[example.com/foo]" -> http://example.com/foo
//    "\"example.com/foo\"" -> http://example.com/foo
//    "(example.com/foo.)" -> http://example.com/foo
// 6. URLs with cruft before the scheme
//    "*http://example.com" -> "http://example.com"
- (NSRange)rangeOfURLInString;

- (NSString *)stringByRemovingEnclosingBrackets;

- (NSString *)stringByEscapingForURL;
- (NSString *)stringByCapitalizingFirstLetter;

- (NSArray<NSString *> *)helpfulSynonyms;

// String starts with http:// or https://. Used to tell if a custom prefs
// location is a path or URL.
- (BOOL)stringIsUrlLike;

// Fonts are encoded as strings when stored in a profile. This returns the font for such a string.
- (NSFont *)fontValue;

// Returns a 2-hex-chars-per-char encoding of this string.
- (NSString *)hexEncodedString;
+ (NSString *)stringWithHexEncodedString:(NSString *)hexEncodedString;

// Compose/Decompose UTF8 string without normalization

// This is better than -precomposedStringWithCanonicalMapping because it preserves compatability
// equivalence. It's most relevant when two canonically equivalent characters have different widths
// (one is half-width while the other is ambiguous width). The difference is in the following
// ranges: 2000-2FFF, F900-FAFF, 2F800-2FAFF. See issue 2872.
- (NSString *)precomposedStringWithHFSPlusMapping;
- (NSString *)decomposedStringWithHFSPlusMapping;

// Expands a vim-style string's special characters
- (NSString *)stringByExpandingVimSpecialCharacters;

// How tall is this string when rendered within a fixed width?
- (CGFloat)heightWithAttributes:(NSDictionary *)attributes constrainedToWidth:(CGFloat)maxWidth;

- (NSArray *)keyValuePair;

- (NSString *)stringByReplacingVariableReferencesWithVariables:(NSDictionary *)vars;
- (NSString *)stringByPerformingSubstitutions:(NSDictionary *)substituions;

// Does self contain |substring|?
- (BOOL)containsString:(NSString *)substring;

// Returns self repeated |n| times.
- (NSString *)stringRepeatedTimes:(int)n;

// Truncates the string and adds an ellipsis if it is longer than maxLength.
- (NSString *)ellipsizedDescriptionNoLongerThan:(int)maxLength;

// Turns a string like fooBar into FooBar.
- (NSString *)stringWithFirstLetterCapitalized;

// Given a bitmask of modifiers like NSAlternateKeyMask, return a string indicating those modifiers.
+ (NSString *)stringForModifiersWithMask:(NSUInteger)mask;

// Returns a fresh UUID
+ (NSString *)uuid;

// Characters in [0, 31] and 127 get replaced with ?
- (NSString *)stringByReplacingControlCharsWithQuestionMark;

// Returns the set of $$VARIABLES$$ in the string.
- (NSSet *)doubleDollarVariables;

// Returns whether |self| is matched by |glob|, which is a shell-like glob pattern (e.g., *x or
// x*y).
// Only * is supported as a wildcard.
- (BOOL)stringMatchesGlobPattern:(NSString *)glob caseSensitive:(BOOL)caseSensitive;

// Call |block| for each composed character in the string. If it is a single base character or a
// high surrogate, then |simple| will be valid and |complex| will be nil. Otherwise, |complex| will
// be non-nil.
- (void)enumerateComposedCharacters:(void (^)(NSRange range,
                                              unichar simple,
                                              NSString *complexString,
                                              BOOL *stop))block;

- (NSUInteger)iterm_unsignedIntegerValue;

// Returns modified attributes for drawing self fitting size within one point.
- (NSDictionary *)attributesUsingFont:(NSFont *)font fittingSize:(NSSize)size attributes:(NSDictionary *)attributes;

// Removes trailing zeros from a floating point value, leaving at most one.
// 1.0000 -> 1.0
// 1.0010 -> 1.001
- (NSString *)stringByCompactingFloatingPointString;

// A fast, non-cryto-quality hash.
- (NSUInteger)hashWithDJB2;

// Returns an array of numbers giving code points for each character in the string. Surrogate pairs
// get combined. Combining marks do not.
- (NSArray<NSNumber *> *)codePoints;

@end

@interface NSMutableString (iTerm)

- (void)trimTrailingWhitespace;

// Puts backslashes before characters in shellEscapableCharacters.
- (void)escapeShellCharacters;

// Convenience method to append a single character.
- (void)appendCharacter:(unichar)c;

@end
