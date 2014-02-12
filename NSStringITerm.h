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

#import <Foundation/Foundation.h>

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

- (NSMutableString *)stringReplaceSubstringFrom:(NSString *)oldSubstring to:(NSString *)newSubstring;
- (NSString *)stringWithEscapedShellCharacters;

// Properly escapes chars for a string to stick in a URL query param.
- (NSString*)stringWithPercentEscape;

// Convert DOS-style and \n newlines to \r newlines.
- (NSString*)stringWithLinefeedNewlines;

- (void)breakDownCommandToPath:(NSString **)cmd cmdArgs:(NSArray **)path;
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

- (NSString *)stringByBase64DecodingStringWithEncoding:(NSStringEncoding)encoding;

// Returns a substring of contiguous characters only from a given character set
// including some character in the middle of the target.
- (NSString *)substringIncludingOffset:(int)offset
                      fromCharacterSet:(NSCharacterSet *)charSet
                  charsTakenFromPrefix:(int*)charsTakenFromPrefixPtr;

- (NSString *)URLInStringWithOffset:(int *)offset length:(int *)length;

- (NSString *)stringByEscapingForURL;

@end

@interface NSMutableString (iTerm)

- (void)trimTrailingWhitespace;

@end