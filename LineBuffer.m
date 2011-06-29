// -*- mode:objc -*-
// $Id: $
/*
 **  LineBuffer.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: George Nachman
 **
 **  Project: iTerm
 **
 **  Description: Implements a buffer of lines. It can hold a large number
 **   of lines and can quickly format them to a fixed width.
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

#import <LineBuffer.h>
#import "RegexKitLite/RegexKitLite.h"

@implementation ResultRange
@end

@implementation LineBlock

- (LineBlock*) initWithRawBufferSize: (int) size
{
    raw_buffer = (screen_char_t*) malloc(sizeof(screen_char_t) * size);
    buffer_start = raw_buffer;
    start_offset = 0;
    first_entry = 0;
    buffer_size = size;
    // Allocate enough space for a bunch of 80-character lines. It can grow if needed.
    cll_capacity = 1 + size/80;
    cll_entries = 0;
    cumulative_line_lengths = (int*) malloc(sizeof(int) * cll_capacity);
    is_partial = NO;
    cached_numlines_width = -1;

    return self;
}

- (void) dealloc
{
    if (raw_buffer) {
        free(raw_buffer);
    }
    if (cumulative_line_lengths) {
        free(cumulative_line_lengths);
    }
    [super dealloc];
}

- (int) rawSpaceUsed
{
    if (cll_entries == 0) {
        return 0;
    } else {
        return cumulative_line_lengths[cll_entries - 1];
    }
}

- (void) _appendCumulativeLineLength: (int) cumulativeLength
{
    if (cll_entries == cll_capacity) {
        cll_capacity *= 2;
        cumulative_line_lengths = (int*) realloc((void*) cumulative_line_lengths, cll_capacity * sizeof(int));
    }
    cumulative_line_lengths[cll_entries] = cumulativeLength;
    ++cll_entries;
}

// used by dump to format a line of screen_char_t's into an asciiz string.
static char* formatsct(screen_char_t* src, int len, char* dest) {
    if (len > 999) len = 999;
    int i;
    for (i = 0; i < len; ++i) {
        dest[i] = (src[i].code && !src[i].complexChar) ? src[i].code : '.';
    }
    dest[i] = 0;
    return dest;
}

- (void)dump:(int)rawOffset
{
    char temp[1000];
    int i;
    int prev;
    if (first_entry > 0) {
        prev = cumulative_line_lengths[first_entry - 1];
    } else {
        prev = 0;
    }
    for (i = first_entry; i < cll_entries; ++i) {
        BOOL iscont = (i == cll_entries-1) && is_partial;
        NSLog(@"Line %d, length %d, offset from raw=%d, abs pos=%d, continued=%s: %s\n", i, cumulative_line_lengths[i] - prev, prev, prev + rawOffset, iscont?"yes":"no",
              formatsct(buffer_start+prev-start_offset, cumulative_line_lengths[i]-prev, temp));
        prev = cumulative_line_lengths[i];
    }
}

- (BOOL) appendLine: (screen_char_t*) buffer length: (int) length partial:(BOOL) partial
{
    const int space_used = [self rawSpaceUsed];
    const int free_space = buffer_size - space_used - start_offset;
    if (length > free_space) {
        return NO;
    }
    // There's a bit of an edge case here: if you're appending an empty
    // non-partial line to a partial line, we need it to append a blank line
    // after the continued line. In practice this happens because a line is
    // long but then the wrapped portion is erased and the EOL_SOFT flag stays
    // behind. It would be really complex to ensure consistency of line-wrapping
    // flags because the screen contents are changed in so many places.
    if (is_partial && !(!partial && length == 0)) {
        // append to an existing line
        NSAssert(cll_entries > 0, @"is_partial but has no entries");
        cumulative_line_lengths[cll_entries - 1] += length;
    } else {
        // add a new line
        [self _appendCumulativeLineLength: (space_used + length)];
    }
    is_partial = partial;
    memcpy(raw_buffer + space_used, buffer, sizeof(screen_char_t) * length);
    cached_numlines_width = -1;
    return YES;
}

- (int) getPositionOfLine: (int*)lineNum atX: (int) x withWidth: (int)width
{
    int length;
    int eol;
    screen_char_t* p = [self getWrappedLineWithWrapWidth: width
                                                 lineNum: lineNum
                                              lineLength: &length
                                       includesEndOfLine: &eol];
    if (!p) {
        return -1;
    } else {
        return p - raw_buffer + x;
    }
}

// Count the number of "full lines" in buffer up to position 'length'. A full
// line is one that, after wrapping, goes all the way to the edge of the screen
// and has at least one character wrap around. It is equal to the number of
// lines after wrapping minus one. Examples:
//
// 2 Full Lines:    0 Full Lines:   0 Full Lines:    1 Full Line:
// |xxxxx|          |x     |        |xxxxxx|         |xxxxxx|
// |xxxxx|                                           |x     |
// |x    |
static int NumberOfFullLines(screen_char_t* buffer, int length, int width)
{
    // In the all-single-width case, it should return (length - 1) / width.
    int fullLines = 0;
    for (int i = width; i < length; i += width) {
        if (buffer[i].code == DWC_RIGHT) {
            --i;
        }
        ++fullLines;
    }
    return fullLines;
}

// Finds a where the nth line begins after wrapping and returns its offset from the start of the buffer.
//
// In the following example, this would return:
// pointer to a if n==0, pointer to g if n==1, asserts if n > 1
// |abcdef|
// |ghi   |
//
// It's more complex with double-width characters.
// In this example, suppose XX is a double-width character.
//
// Returns a pointer to a if n==0, pointer XX if n==1, asserts if n > 1:
// |abcde|   <- line is short after wrapping
// |XXzzzz|
static int OffsetOfWrappedLine(screen_char_t* p, int n, int length, int width) {
    int lines = 0;
    int i = 0;
    while (lines < n) {
        // Advance i to the start of the next line
        i += width;
        ++lines;
        assert(i < length);
        if (p[i].code == DWC_RIGHT) {
            // Oops, the line starts with the second half of a double-width
            // character. Wrap the last character of the previous line on to
            // this line.
            --i;
        }
    }
    return i;
}

- (screen_char_t*) getWrappedLineWithWrapWidth: (int) width
                                       lineNum: (int*) lineNum
                                    lineLength: (int*) lineLength
                             includesEndOfLine: (int*) includesEndOfLine
{
    int prev = 0;
    int length;
    int i;
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        length = cll - prev;
        int spans = NumberOfFullLines(buffer_start + prev, length, width);
        if (*lineNum > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            *lineNum -= consume;
        } else {  // *lineNum <= spans
            // We found the raw line that inclues the wrapped line we're searching for.
            // eat up *lineNum many width-sized wrapped lines from this start of the current full line
            int offset = OffsetOfWrappedLine(buffer_start + prev,
                                             *lineNum,
                                             length,
                                             width);
            *lineNum = 0;
            // offset: the relevant part of the raw line begins at this offset into it
            *lineLength = length - offset;  // the length of the suffix of the raw line, beginning at the wrapped line we want
            if (*lineLength > width) {
                // return an infix of the full line
                if (buffer_start[prev + offset + width].code == DWC_RIGHT) {
                    // Result would end with the first half of a double-width character
                    *lineLength = width - 1;
                    *includesEndOfLine = EOL_DWC;
                } else {
                    *lineLength = width;
                    *includesEndOfLine = EOL_SOFT;
                }
            } else {
                // return a suffix of the full line
                if (i == cll_entries - 1 && is_partial) {
                    // If this is the last line and it's partial then it doesn't have an end-of-line.
                    *includesEndOfLine = EOL_SOFT;
                } else {
                    *includesEndOfLine = EOL_HARD;
                }
            }
            return buffer_start + prev + offset;
        }
        prev = cll;
    }
    return NULL;
}

- (int) getNumLinesWithWrapWidth: (int) width
{
    if (width == cached_numlines_width) {
        return cached_numlines;
    }

    int count = 0;
    int prev = 0;
    int i;
    // Count the number of wrapped lines in the block by computing the sum of the number
    // of wrapped lines each raw line would use.
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        int length = cll - prev;
        count += NumberOfFullLines(buffer_start + prev, length, width) + 1;
        prev = cll;
    }

    // Save the result so it doesn't have to be recalculated until some relatively rare operation
    // occurs that invalidates the cache.
    cached_numlines_width = width;
    cached_numlines = count;

    return count;
}

- (BOOL) hasCachedNumLinesForWidth: (int) width
{
    return cached_numlines_width == width;
}

- (BOOL) popLastLineInto: (screen_char_t**) ptr withLength: (int*) length upToWidth: (int) width
{
    if (cll_entries == first_entry) {
        // There is no last line to pop.
        return NO;
    }
    int start;
    if (cll_entries == first_entry + 1) {
        start = 0;
    } else {
        start = cumulative_line_lengths[cll_entries - 2] - start_offset;
    }
    const int end = cumulative_line_lengths[cll_entries - 1] - start_offset;
    const int available_len = end - start;
    if (available_len > width) {
        // The last raw line is longer than width. So get the last part of it after wrapping.
        // If the width is four and the last line is "0123456789" then return "89". It would
        // wrap as: 0123/4567/89. If there are double-width characters, this ensures they are
        // not split across lines when computing the wrapping.
        // If there were only single width characters, the formula would be:
        //     width * ((available_len - 1) / width);
        int offset_from_start = OffsetOfWrappedLine(buffer_start + start,
                                                    NumberOfFullLines(buffer_start + start,
                                                                      available_len,
                                                                      width),
                                                    available_len,
                                                    width);
        *length = available_len - offset_from_start;
        *ptr = buffer_start + start + offset_from_start;
        cumulative_line_lengths[cll_entries - 1] -= *length;
        is_partial = YES;
    } else {
        // The last raw line is not longer than width. Return the whole thing.
        *length = available_len;
        *ptr = buffer_start + start;
        --cll_entries;
        is_partial = NO;
    }

    if (cll_entries == first_entry) {
        // Popped the last line. Reset everything.
        buffer_start = raw_buffer;
        start_offset = 0;
        first_entry = 0;
        cll_entries = 0;
    }

    // Mark the cache dirty.
    cached_numlines_width = -1;
    return YES;
}

- (BOOL) isEmpty
{
    return cll_entries == first_entry;
}

- (int) numRawLines
{
    return cll_entries - first_entry;
}

- (int) numEntries
{
    return cll_entries;
}

- (int) startOffset
{
    return start_offset;
}

- (int) getRawLineLength: (int) linenum
{
    NSAssert(linenum < cll_entries && linenum >= 0, @"Out of bounds");
    int prev;
    if (linenum == 0) {
        prev = 0;
    } else {
        prev = cumulative_line_lengths[linenum-1] - start_offset;
    }
    return cumulative_line_lengths[linenum] - start_offset - prev;
}

- (screen_char_t*) rawLine: (int) linenum
{
    int start;
    if (linenum == 0) {
        start = 0;
    } else {
        start = cumulative_line_lengths[linenum - 1];
    }
    return raw_buffer + start;
}

- (void) changeBufferSize: (int) capacity
{
    NSAssert(capacity >= [self rawSpaceUsed], @"Truncating used space");
    raw_buffer = (screen_char_t*) realloc((void*) raw_buffer, sizeof(screen_char_t) * capacity);
    buffer_start = raw_buffer + start_offset;
    buffer_size = capacity;
    cached_numlines_width = -1;
}

- (int) rawBufferSize
{
    return buffer_size;
}

- (BOOL) hasPartial
{
    return is_partial;
}

- (void) shrinkToFit
{
    [self changeBufferSize: [self rawSpaceUsed]];
}

- (int) dropLines: (int) n withWidth: (int) width;
{
    cached_numlines_width = -1;
    int orig_n = n;
    int prev = 0;
    int length;
    int i;
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        length = cll - prev;
        // Get the number of full-length wrapped lines in this raw line. If there
        // were only single-width characters the formula would be:
        //     (length - 1) / width;
        int spans = NumberOfFullLines(buffer_start + prev, length, width);
        if (n > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            n -= consume;
        } else {  // n <= spans
            // We found the raw line that inclues the wrapped line we're searching for.
            // Set offset to the offset into the raw line where the nth wrapped
            // line begins. If there were only single-width characters the formula
            // would be:
            //   offset = n * width;
            int offset = OffsetOfWrappedLine(buffer_start + prev, n, length, width);
            buffer_start += prev + offset;
            start_offset = buffer_start - raw_buffer;
            first_entry = i;
            return orig_n;
        }
        prev = cll;
    }
    // Consumed the whole buffer.
    cll_entries = 0;
    buffer_start = raw_buffer;
    start_offset = 0;
    first_entry = 0;

    return orig_n - n;
}

- (int) _lineRawOffset: (int) anIndex
{
    if (anIndex == first_entry) {
        return start_offset;
    } else {
        return cumulative_line_lengths[anIndex - 1];
    }
}

const unichar kPrefixChar = 1;
const unichar kSuffixChar = 2;

static NSString* RewrittenRegex(NSString* originalRegex) {
    // Convert ^ in a context where it refers to the start of string to kPrefixChar
    // Convert $ in a context where it refers to the end of string to kSuffixChar
    // ^ is NOT start-of-string when:
    //   - it is escaped
    //   - it is preceeded by an unescaped [
    //   - it is preceeded by an unescaped [:
    // $ is NOT end-of-string when:
    //   - it is escaped
    //
    // It might be possible to write this as a regular substitution but it would be a crazy mess.

    NSMutableString* rewritten = [NSMutableString stringWithCapacity:[originalRegex length]];
    BOOL escaped = NO;
    BOOL inSet = NO;
    BOOL firstCharInSet = NO;
    unichar prevChar = 0;
    for (int i = 0; i < [originalRegex length]; i++) {
        BOOL nextCharIsFirstInSet = NO;
        unichar c = [originalRegex characterAtIndex:i];
        switch (c) {
            case '\\':
                escaped = !escaped;
                break;

            case '[':
                if (!inSet && !escaped) {
                    inSet = YES;
                    nextCharIsFirstInSet = YES;
                }
                break;

            case ']':
                if (inSet && !escaped) {
                    inSet = NO;
                }
                break;

            case ':':
                if (inSet && firstCharInSet && prevChar == '[') {
                    nextCharIsFirstInSet = YES;
                }
                break;

            case '^':
                if (!escaped && !firstCharInSet) {
                    c = kPrefixChar;
                }
                break;

            case '$':
                if (!escaped) {
                    c = kSuffixChar;
                }
                break;
        }
        prevChar = c;
        firstCharInSet = nextCharIsFirstInSet;
        [rewritten appendFormat:@"%C", c];
    }

    return rewritten;
}

static int Search(NSString* needle,
                  screen_char_t* rawline,
                  int raw_line_length,
                  int start,
                  int end,
                  int options,
                  int* resultLength)
{
    NSString* haystack;
    unichar* charHaystack;
    int* deltas;
    haystack = ScreenCharArrayToString(rawline,
                                       start,
                                       end,
                                       &charHaystack,
                                       &deltas);
                                       
    int apiOptions = 0;
    NSRange range;
    BOOL regex;
    if (options & FindOptRegex) {
        regex = YES;
    } else {
        regex = NO;
    }
    if (regex) {
        BOOL backwards = NO;
        if (options & FindOptBackwards) {
            backwards = YES;
        }
        if (options & FindOptCaseInsensitive) {
            apiOptions |= RKLCaseless;
        }

        NSError* regexError = nil;
        NSRange temp;
        NSString* rewrittenRegex = RewrittenRegex(needle);
        NSString* sanitizedHaystack = [haystack stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%c", kPrefixChar]
                                                                          withString:[NSString stringWithFormat:@"%c", 3]];
        sanitizedHaystack = [sanitizedHaystack stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"%c", kSuffixChar]
                                                                         withString:[NSString stringWithFormat:@"%c", 3]];

        NSString* sandwich;
        BOOL hasPrefix = YES;
        BOOL hasSuffix = YES;
        if (end == raw_line_length) {
            if (start == 0) {
                sandwich = [NSString stringWithFormat:@"%C%@%C", kPrefixChar, sanitizedHaystack, kSuffixChar];
            } else {
                hasPrefix = NO;
                sandwich = [NSString stringWithFormat:@"%@%C", sanitizedHaystack, kSuffixChar];
            }
        } else {
            hasSuffix = NO;
            sandwich = [NSString stringWithFormat:@"%C%@", kPrefixChar, sanitizedHaystack, kSuffixChar];
        }

        temp = [sandwich rangeOfRegex:rewrittenRegex
                              options:apiOptions
                              inRange:NSMakeRange(0, [sandwich length])
                              capture:0
                                error:&regexError];
        range = temp;

        if (backwards) {
            int locationAdjustment = hasSuffix ? 1 : 0;
            // keep searching from one char after the start of the match until we don't find anything.
            // regexes aren't good at searching backwards.
            while (!regexError && temp.location != NSNotFound && temp.location+locationAdjustment < [sandwich length]) {
                if (temp.length != 0) {
                    range = temp;
                }
                temp.location += MAX(1, temp.length);
                temp = [sandwich rangeOfRegex:rewrittenRegex
                                      options:apiOptions
                                      inRange:NSMakeRange(temp.location, [sandwich length] - temp.location)
                                      capture:0
                                        error:&regexError];
            }
        }
        if (range.length == 0) {
            range.location = NSNotFound;
        }
        if (!regexError && range.location != NSNotFound) {
            if (hasSuffix && range.location + range.length == [sandwich length]) {
                // match includes $
                --range.length;
                if (range.length == 0) {
                    // matched only on $
                    --range.location;
                }
            }
            if (hasPrefix && range.location == 0) {
                --range.length;
            } else if (hasPrefix) {
                --range.location;
            }
        }
        if (range.length <= 0) {
            // match on ^ or $
            range.location = NSNotFound;
        }
        if (regexError) {
            NSLog(@"regex error: %@", regexError);
            range.length = 0;
            range.location = NSNotFound;
        }
    } else {
        if (options & FindOptBackwards) {
            apiOptions |= NSBackwardsSearch;
        }
        if (options & FindOptCaseInsensitive) {
            apiOptions |= NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
        }
        range = [haystack rangeOfString:needle options:apiOptions];
    }
    int result = -1;
    if (range.location != NSNotFound) {
        int adjustedLocation;
        int adjustedLength;
        adjustedLocation = range.location + deltas[range.location];
        adjustedLength = range.length + deltas[range.location + range.length] -
            deltas[range.location];
        *resultLength = adjustedLength;
        result = adjustedLocation + start;
    }
    free(deltas);
    free(charHaystack);
    return result;
}

- (void) _findInRawLine:(int) entry
                 needle:(NSString*)needle
                options:(int) options
                   skip:(int) skip
                 length:(int) raw_line_length
        multipleResults:(BOOL)multipleResults
                results:(NSMutableArray*)results
{
    screen_char_t* rawline = raw_buffer + [self _lineRawOffset:entry];
    if (skip > raw_line_length) {
        skip = raw_line_length;
    }
    if (skip < 0) {
        skip = 0;
    }
    if (options & FindOptBackwards) {
        // This algorithm is wacky and slow but stay with me here:
        // When you search backward, the most common case is that you are
        // repeating the previous search but with a one-character longer
        // needle (having grown at the end). So the rightmost result we can
        // accept is one whose leftmost position is at the leftmost position of
        // the previous result.
        //
        // Example: Consider a previosu search of [jump]
        //  The quick brown fox jumps over the lazy dog.
        //                      ^^^^
        // The search is then extended to [jumps]. We want to return:
        //  The quick brown fox jumps over the lazy dog.
        //                      ^^^^^
        // Ideally, we would search only the necessary part of the haystack:
        //  Search("The quick brown fox jumps", "jumps")
        //
        // But what we did there was to add one byte to the haystack. That works
        // for ascii, but not in other cases. Let us consider a localized
        // German search where "ss" matches "ß". Let's first search for [jump]
        // in this translation:
        //
        //  Ein quicken Braunfox jumpss uber die Lazydog.
        //                       ^^^^
        // Then the needle becomes [jumpß]. Under the previous algorithm we'd
        // extend the haystack to:
        //  Ein quicken Braunfox jumps
        // And there is no match for jumpß.
        //
        // So to do the optimal algorithm, you'd have to know how many characters
        // to add to the haystack in the worst localized case. With decomposed
        // diacriticals, the upper bound is unclear.
        //
        // I'm going to err on the side of correctness over performance. I'm
        // sure this could be improved if needed. One obvious
        // approach is to use the naïve algorithm when the text is all ASCII.
        //
        // Thus, the algorithm is to do a reverse search until a hit is found
        // that begins not before 'skip', which is the leftmost acceptable
        // position.

        int limit = raw_line_length;
        int tempResultLength;
        int tempPosition;
        do {
            tempPosition =  Search(needle, rawline, raw_line_length, 0, limit,
                                   options, &tempResultLength);
            limit = tempPosition + tempResultLength - 1;
            if (tempPosition != -1 && tempPosition <= skip) {
                ResultRange* r = [[[ResultRange alloc] init] autorelease];
                r->position = tempPosition;
                r->length = tempResultLength;
                [results addObject:r];
            }
        } while (tempPosition != -1 && (multipleResults || tempPosition > skip));
    } else {
        // Search forward
        // TODO: test this
        int tempResultLength;
        int tempPosition;
        while (skip < raw_line_length) {
            tempPosition = Search(needle, rawline, raw_line_length, skip, raw_line_length,
                                        options, &tempResultLength);
            if (tempPosition != -1) {
                ResultRange* r = [[[ResultRange alloc] init] autorelease];
                r->position = tempPosition;
                r->length = tempResultLength;
                [results addObject:r];
                if (!multipleResults) {
                    break;
                }
                skip = tempPosition + 1;
            } else {
                break;
            }
        }
    }
}

- (int) _lineLength: (int) anIndex
{
    int prev;
    if (anIndex == first_entry) {
        prev = start_offset;
    } else {
        prev = cumulative_line_lengths[anIndex - 1];
    }
    return cumulative_line_lengths[anIndex] - prev;
}

- (int) _findEntryBeforeOffset: (int) offset
{
    assert(offset >= start_offset);
    int i;
    for (i = first_entry; i < cll_entries; ++i) {
        if (cumulative_line_lengths[i] > offset) {
            return i;
        }
    }
    return -1;
}

- (void) findSubstring: (NSString*) substring
               options: (int) options
              atOffset: (int) offset
               results: (NSMutableArray*) results
       multipleResults:(BOOL)multipleResults
{
    if (offset == -1) {
        offset = [self rawSpaceUsed] - 1;
    }
    int entry;
    int limit;
    int dir;
    if (options & FindOptBackwards) {
        entry = [self _findEntryBeforeOffset: offset];
        if (entry == -1) {
            // Maybe there were no lines or offset was <= start_offset.
            return;
        }
        limit = first_entry - 1;
        dir = -1;
    } else {
        entry = first_entry;
        limit = cll_entries;
        dir = 1;
    }
    while (entry != limit) {
        int line_raw_offset = [self _lineRawOffset:entry];
        int skipped = offset - line_raw_offset;
        if (skipped < 0) {
            skipped = 0;
        }
        NSMutableArray* newResults = [NSMutableArray arrayWithCapacity:1];
        [self _findInRawLine:entry
                      needle:substring
                     options:options
                        skip:skipped
                      length:[self _lineLength: entry]
             multipleResults:multipleResults
                     results:newResults];
        for (ResultRange* r in newResults) {
            r->position += line_raw_offset;
            [results addObject:r];
        }
        if ([newResults count] && !multipleResults) {
            return;
        }
        entry += dir;
    }
}

- (BOOL) convertPosition: (int) position withWidth: (int) width toX: (int*) x toY: (int*) y
{
    int i;
    *x = 0;
    *y = 0;
    int prev = start_offset;
    for (i = first_entry; i < cll_entries; ++i) {
        int eol = cumulative_line_lengths[i];
        int line_length = eol - prev;
        if (position >= eol) {
            // Get the number of full-width lines in the raw line. If there were
            // only single-width characters the formula would be:
            //     spans = (line_length - 1) / width;
            int spans = NumberOfFullLines(raw_buffer + prev, line_length, width);
            *y += spans + 1;
        } else {
            // The position we're searching for is in this (unwrapped) line.
            int bytes_to_consume_in_this_line = position - prev;
            int dwc_peek = 0;

            // If the position is the left half of a double width char then include the right half in
            // the following call to NumberOfFullLines.

            if (bytes_to_consume_in_this_line < line_length &&
                prev + bytes_to_consume_in_this_line + 1 < eol) {
                assert(prev + bytes_to_consume_in_this_line + 1 < buffer_size);
                if (raw_buffer[prev + bytes_to_consume_in_this_line + 1].code == DWC_RIGHT) {    
                    ++dwc_peek;
                }
            }
            int consume = NumberOfFullLines(raw_buffer + prev,
                                            MIN(line_length, bytes_to_consume_in_this_line + 1 + dwc_peek),
                                            width);
            *y += consume;
            if (consume > 0) {
                // Offset from prev where the consume'th line begin.
                int offset = OffsetOfWrappedLine(raw_buffer + prev,
                                                 consume,
                                                 line_length,
                                                 width);
                // We know that position falls in this line. Set x to the number
                // of chars after the beginning on the line. If there were only
                // single-width chars the formula would be:
                //     bytes_to_consume_in_this_line % (consume * width);
                *x = position - (prev + offset);
            } else {
                *x = bytes_to_consume_in_this_line;
            }
            return YES;
        }
        prev = eol;
    }
    NSLog(@"Didn't find position %d", position);
    return NO;
}

@end

@implementation LineBuffer

// Append a block
- (LineBlock*) _addBlockOfSize: (int) size
{
    LineBlock* block = [[LineBlock alloc] initWithRawBufferSize: size];
    [blocks addObject: block];
    [block release];
    return block;
}

// The real implementation of init. We prefer not to explose the notion of block sizes to
// clients, so this is internal.
- (LineBuffer*) initWithBlockSize: (int) bs
{
    block_size = bs;
    blocks = [[NSMutableArray alloc] initWithCapacity: 1];
    [self _addBlockOfSize: block_size];
    max_lines = -1;
    num_wrapped_lines_width = -1;
    num_dropped_blocks = 0;
    return self;
}

- (void)dealloc
{
    [blocks release];
    [super dealloc];
}

// This is called a lot so it's a C function to avoid obj_msgSend
static int RawNumLines(LineBuffer* buffer, int width) {
    if (buffer->num_wrapped_lines_width == width) {
        return buffer->num_wrapped_lines_cache;
    }
    int count = 0;
    int i;
    for (i = 0; i < [buffer->blocks count]; ++i) {
        LineBlock* block = [buffer->blocks objectAtIndex: i];
        count += [block getNumLinesWithWrapWidth: width];
    }
    buffer->num_wrapped_lines_width = width;
    buffer->num_wrapped_lines_cache = count;
    return count;
}

// drop lines if needed until max_lines is reached.
- (void) _dropLinesForWidth: (int) width
{
    if (max_lines == -1) {
        // Do nothing: the buffer is infinite.
        return;
    }

    int total_lines = RawNumLines(self, width);
    while (total_lines > max_lines) {
        int extra_lines = total_lines - max_lines;

        NSAssert([blocks count] > 0, @"No blocks");
        LineBlock* block = [blocks objectAtIndex: 0];
        int block_lines = [block getNumLinesWithWrapWidth: width];
        NSAssert(block_lines > 0, @"Empty leading block");
        int toDrop = block_lines;
        if (toDrop > extra_lines) {
            toDrop = extra_lines;
        }
        int dropped = [block dropLines: toDrop withWidth: width];

        if ([block isEmpty]) {
            [blocks removeObjectAtIndex:0];
            ++num_dropped_blocks;
        }
        total_lines -= dropped;
    }
    num_wrapped_lines_cache = total_lines;
}

- (void) setMaxLines: (int) maxLines
{
    max_lines = maxLines;
    num_wrapped_lines_width = -1;
}


- (int) dropExcessLinesWithWidth: (int) width
{
    int nl = RawNumLines(self, width);
    if (nl > max_lines) {
        [self _dropLinesForWidth: width];
    }
    return nl - RawNumLines(self, width);
}

- (void) dump
{
    int i;
    int rawOffset = 0;
    for (i = 0; i < [blocks count]; ++i) {
        NSLog(@"Block %d:\n", i);
        [[blocks objectAtIndex: i] dump:rawOffset];
        rawOffset += [[blocks objectAtIndex:i] rawSpaceUsed];
    }
}

- (LineBuffer*) init
{
    // I picked 8k because it's a multiple of the page size and should hold about 100-200 lines
    // on average. Very small blocks make finding a wrapped line expensive because caching the
    // number of wrapped lines is spread out over more blocks. Very large blocks are expensive
    // because of the linear search through a block for the start of a wrapped line. This is
    // in the middle. Ideally, the number of blocks would equal the number of wrapped lines per
    // block, and this should be in that neighborhood for typical uses.
    const int BLOCK_SIZE = 1024 * 8;
    [self initWithBlockSize: BLOCK_SIZE];
    return self;
}

- (void) appendLine: (screen_char_t*) buffer length: (int) length partial: (BOOL) partial width:(int) width
{
#ifdef LOG_MUTATIONS
    {
        char a[1000];
        int i;
        for (i = 0; i < length; i++) {
            a[i] = (buffer[i].code && !buffer[i].complex) ? buffer[i].code : '.';
        }
        a[i] = '\0';
        NSLog(@"Append: %s\n", a);
    }
#endif
    if ([blocks count] == 0) {
        [self _addBlockOfSize: block_size];
    }

    LineBlock* block = [blocks objectAtIndex: ([blocks count] - 1)];

    int beforeLines = [block getNumLinesWithWrapWidth:width];
    if (![block appendLine: buffer length: length partial: partial]) {
        // It's going to be complicated. Invalidate the number of wrapped lines
        // cache.
        num_wrapped_lines_width = -1;
        int prefix_len = 0;
        screen_char_t* prefix = NULL;
        if ([block hasPartial]) {
            // There is a line that's too long for the current block to hold.
            // Remove its prefix fromt he current block and later add the
            // concatenation of prefix + buffer to a larger block.
            screen_char_t* temp;
            BOOL ok = [block popLastLineInto: &temp
                                  withLength: &prefix_len
                                   upToWidth: [block rawBufferSize]+1];
            prefix = (screen_char_t*) malloc(prefix_len * sizeof(screen_char_t));
            memcpy(prefix, temp, prefix_len * sizeof(screen_char_t));
            NSAssert(ok, @"hasPartial but pop failed.");
        }
        if ([block isEmpty]) {
            // The buffer is empty but it's not large enough to hold a whole line. It must be grown.
            if (partial) {
                // The line is partial so we know there's more coming. Allocate enough space to hold the current line
                // plus the usual block size (this is the case when the line is freaking huge).
                // We could double the size to ensure better asymptotic runtime but you'd run out of memory
                // faster with huge lines.
                [block changeBufferSize: length + prefix_len + block_size];
            } else {
                // Allocate exactly enough space to hold this one line.
                [block changeBufferSize: length + prefix_len];
            }
        } else {
            // The existing buffer can't hold this line, but it has preceding line(s). Shrink it and
            // allocate a new buffer that is large enough to hold this line.
            [block shrinkToFit];
            if (length + prefix_len > block_size) {
                block = [self _addBlockOfSize: length + prefix_len];
            } else {
                block = [self _addBlockOfSize: block_size];
            }
        }

        // Append the prefix if there is one (the prefix was a partial line that we're
        // moving out of the last block into the new block)
        if (prefix) {
            BOOL ok = [block appendLine: prefix length: prefix_len partial: YES];
            NSAssert(ok, @"append can't fail here");
            free(prefix);
        }
        // Finally, append this line to the new block. We know it'll fit because we made
        // enough room for it.
        BOOL ok = [block appendLine: buffer length: length partial: partial];
        NSAssert(ok, @"append can't fail here");
    } else if (num_wrapped_lines_width == width) {
        // Straightforward addition of a line to an existing block. Update the
        // wrapped lines cache.
        int afterLines = [block getNumLinesWithWrapWidth:width];
        num_wrapped_lines_cache += (afterLines - beforeLines);
    } else {
        // Width change. Invalidate the wrapped lines cache.
        num_wrapped_lines_width = -1;
    }
}

// Copy a line into the buffer. If the line is shorter than 'width' then only
// the first 'width' characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
- (int) copyLineToBuffer: (screen_char_t*) buffer width: (int) width lineNum: (int) lineNum
{
    int line = lineNum;
    int i;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex: i];
        NSAssert(block, @"Null block");

        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines < line) {
            line -= block_lines;
            continue;
        }

        int length;
        int eol;
        screen_char_t* p = [block getWrappedLineWithWrapWidth: width
                                                      lineNum: &line
                                                   lineLength: &length
                                            includesEndOfLine: &eol];
        if (p) {
            NSAssert(length <= width, @"Length too long");
            memcpy((char*) buffer, (char*) p, length * sizeof(screen_char_t));
            return eol;
        }
    }
    NSLog(@"Couldn't find line %d", lineNum);
    NSAssert(NO, @"Tried to get non-existant line");
    return NO;
}

- (int) numLinesWithWidth: (int) width
{
    return RawNumLines(self, width);
}

- (BOOL) popAndCopyLastLineInto: (screen_char_t*) ptr width: (int) width includesEndOfLine: (int*) includesEndOfLine;
{
    if ([self numLinesWithWidth: width] == 0) {
        return NO;
    }
    num_wrapped_lines_width = -1;

    LineBlock* block = [blocks lastObject];

    // If the line is partial the client will want to add a continuation marker so
    // tell him there's no EOL in that case.
    *includesEndOfLine = [block hasPartial] ? EOL_SOFT : EOL_HARD;

    // Pop the last up-to-width chars off the last line.
    int length;
    screen_char_t* temp;
    BOOL ok = [block popLastLineInto: &temp withLength: &length upToWidth: width];
    NSAssert(ok, @"Unexpected empty block");
    NSAssert(length <= width, @"Length too large");
    NSAssert(length >= 0, @"Negative length");

    // Copy into the provided buffer.
    memcpy(ptr, temp, sizeof(screen_char_t) * length);

    // Clean up the block if the whole thing is empty, otherwise another call
    // to this function would not work correctly.
    if ([block isEmpty]) {
        [blocks removeLastObject];
    }

#ifdef LOG_MUTATIONS
    {
        char a[1000];
        int i;
        for (i = 0; i < width; i++) {
            a[i] = (ptr[i].code && !ptr[i].complexChar) ? ptr[i].code : '.';
        }
        a[i] = '\0';
        NSLog(@"Pop: %s\n", a);
    }
#endif
    return YES;
}

- (void) setCursor: (int) x
{
    LineBlock* block = [blocks lastObject];
    if ([block hasPartial]) {
        int last_line_length = [block getRawLineLength: [block numEntries]-1];
        cursor_x = x + last_line_length;
        cursor_rawline = -1;
    } else {
        cursor_x = x;
        cursor_rawline = 0;
    }

    int i;
    for (i = 0; i < [blocks count]; ++i) {
        cursor_rawline += [[blocks objectAtIndex: i] numRawLines];
    }
}

- (BOOL) getCursorInLastLineWithWidth: (int) width atX: (int*) x
{
    int total_raw_lines = 0;
    int i;
    for (i = 0; i < [blocks count]; ++i) {
        total_raw_lines += [[blocks objectAtIndex:i] numRawLines];
    }
    if (cursor_rawline == total_raw_lines-1) {
        // The cursor is on the last line in the buffer.
        LineBlock* block = [blocks lastObject];
        int last_line_length = [block getRawLineLength: ([block numEntries]-1)];
        screen_char_t* lastRawLine = [block rawLine: ([block numEntries]-1)];
        int num_overflow_lines = NumberOfFullLines(lastRawLine,
                                                   last_line_length,
                                                   width);
        int min_x = OffsetOfWrappedLine(lastRawLine,
                                        num_overflow_lines,
                                        last_line_length,
                                        width);
        //int num_overflow_lines = (last_line_length-1) / width;
        //int min_x = num_overflow_lines * width;
        int max_x = min_x + width;  // inclusive because the cursor wraps to the next line on the last line in the buffer
        if (cursor_x >= min_x && cursor_x <= max_x) {
            *x = cursor_x - min_x;
            return YES;
        }
    }
    return NO;
}

- (BOOL) _findPosition: (int) start inBlock: (int*) block_num inOffset: (int*) offset
{
    int i;
    int position = start;
    for (i = 0; position >= 0 && i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        int used = [block rawSpaceUsed];
        if (position >= used) {
            position -= used;
        } else {
            *block_num = i;
            *offset = position;
            return YES;
        }
    }
    return NO;
}

- (int) _blockPosition: (int) block_num
{
    int i;
    int position = 0;
    for (i = 0; i < block_num; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        position += [block rawSpaceUsed];
    }
    return position;

}

- (void)initFind:(NSString*)substring startingAt:(int)start options:(int)options withContext:(FindContext*)context
{
    context->substring = [[NSString alloc] initWithString:substring];
    context->options = options;
    if (options & FindOptBackwards) {
        context->dir = -1;
    } else {
        context->dir = 1;
    }
    if ([self _findPosition:start inBlock:&context->absBlockNum inOffset:&context->offset]) {
        context->absBlockNum += num_dropped_blocks;
        context->status = Searching;
    } else {
        context->status = NotFound;
    }
    context->results = [[NSMutableArray alloc] init];
}

- (void)releaseFind:(FindContext*)context
{
    if (context->substring) {
        [context->substring release];
        context->substring = nil;
    }
    [context->results release];
}

- (void)findSubstring:(FindContext*)context stopAt:(int)stopAt
{
    if (context->dir > 0) {
        // Search forwards
        if (context->absBlockNum < num_dropped_blocks) {
            // The next block to search was dropped. Skip ahead to the first block.
            // NSLog(@"Next to search was dropped. Skip to start");
            context->absBlockNum = num_dropped_blocks;
        }
        if (context->absBlockNum - num_dropped_blocks >= [blocks count]) {
            // Got to bottom
            // NSLog(@"Got to bottom");
            context->status = NotFound;
            return;
        }
    } else {
        // Search backwards
        if (context->absBlockNum < num_dropped_blocks) {
            // Got to top
            // NSLog(@"Got to top");
            context->status = NotFound;
            return;
        }
    }

    NSAssert(context->absBlockNum - num_dropped_blocks >= 0, @"bounds check");
    NSAssert(context->absBlockNum - num_dropped_blocks < [blocks count], @"bounds check");
    LineBlock* block = [blocks objectAtIndex:context->absBlockNum - num_dropped_blocks];

    if (context->absBlockNum - num_dropped_blocks == 0 &&
        context->offset != -1 &&
        context->offset < [block startOffset]) {
        if (context->dir > 0) {
            // Part of the first block has been dropped. Skip ahead to its
            // current beginning.
            context->offset = [block startOffset];
        } else {
            // This block has scrolled off.
            // NSLog(@"offset=%d, block's startOffset=%d. give up", context->offset, [block startOffset]);
            context->status = NotFound;
            return;
        }
    }

    // NSLog(@"search block %d starting at offset %d", context->absBlockNum - num_dropped_blocks, context->offset);

    [block findSubstring:context->substring
                 options:context->options
                atOffset:context->offset
                 results:context->results
         multipleResults:((context->options & FindMultipleResults) != 0)];
    NSMutableArray* filtered = [NSMutableArray arrayWithCapacity:[context->results count]];
    BOOL haveOutOfRangeResults = NO;
    for (ResultRange* range in context->results) {
        range->position += [self _blockPosition:context->absBlockNum - num_dropped_blocks];
        if (context->dir * (range->position - stopAt) > 0 ||
            context->dir * (range->position + context->matchLength - stopAt) > 0) {
            // result was outside the range to be searched
            haveOutOfRangeResults = YES;
        } else {
            // Found a good result.
            context->status = Matched;
            [filtered addObject:range];
        }
    }
    [context->results release];
    context->results = [filtered retain];
    if ([filtered count] == 0 && haveOutOfRangeResults) {
        context->status = NotFound;
    }

    // Prepare to continue searching next block.
    if (context->dir < 0) {
        context->offset = -1;
    } else {
        context->offset = 0;
    }
    context->absBlockNum += context->dir;
}

- (BOOL) convertPosition: (int) position withWidth: (int) width toX: (int*) x toY: (int*) y
{
    int i;
    int yoffset = 0;
    for (i = 0; position >= 0 && i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        int used = [block rawSpaceUsed];
        if (position >= used) {
            position -= used;
            yoffset += [block getNumLinesWithWrapWidth:width];
        } else {
            BOOL result = [block convertPosition: position withWidth: width toX: x toY: y];
            *y += yoffset;
            return result;
        }
    }
    return NO;
}

- (BOOL) convertCoordinatesAtX: (int) x atY: (int) y withWidth: (int) width toPosition: (int*) position offset:(int)offset
{
    int line = y;
    int i;
    *position = 0;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex: i];
        NSAssert(block, @"Null block");

        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines <= line) {
            line -= block_lines;
            *position += [block rawSpaceUsed];
            continue;
        }

        int pos;
        pos = [block getPositionOfLine: &line atX: x withWidth: width];
        if (pos >= 0) {
            int tempx=0, tempy=0;
            // The correct position has been computed:
            // *position = start of block
            // pos = offset within block
            // offset = additional offset the user requested
            // but we need to see if the position actually exists after adding offset. If it can be
            // converted to an x,y position the it's all right.
            if ([self convertPosition:*position+pos+offset withWidth:width toX:&tempx toY:&tempy] && tempy >= 0 && tempx >= 0) {
                *position += pos + offset;
                return YES;
            } else {
                return NO;
            }
        }
    }
    return NO;
}

- (int) firstPos
{
    int i;
    int position = 0;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        if (![block isEmpty]) {
            position += [block startOffset];
            break;
        } else {
            position += [block rawSpaceUsed];
        }
    }
    return position;
}

- (int) lastPos
{
    int i;
    int position = 0;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        if (![block isEmpty]) {
            position += [block rawSpaceUsed];
        } else {
            position += [block rawSpaceUsed];
        }
    }
    return position;
}


@end
