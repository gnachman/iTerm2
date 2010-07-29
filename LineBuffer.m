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
        dest[i] = src[i].ch ? src[i].ch : '.';
    }
    dest[i] = 0;
    return dest;
}

- (void) dump
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
        NSLog(@"Line %d, length %d, offset from raw=%d, continued=%s: %s\n", i, cumulative_line_lengths[i] - prev, prev, iscont?"yes":"no", 
              formatsct(buffer_start+prev-start_offset, cumulative_line_lengths[i]-prev, temp));
        prev = cumulative_line_lengths[i];
    }
}

- (BOOL) appendLine: (screen_char_t*) buffer length: (int) length partial: (BOOL) partial
{
    const int space_used = [self rawSpaceUsed];
    const int free_space = buffer_size - space_used - start_offset;
    if (length > free_space) {
        return NO;
    }
    if (is_partial) {
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
	BOOL eol;
	screen_char_t* p = [self getWrappedLineWithWrapWidth: width lineNum: lineNum lineLength: &length includesEndOfLine: &eol];
	if (!p) {
		return -1;
	} else {
		return p - raw_buffer + x;
	}
}

- (screen_char_t*) getWrappedLineWithWrapWidth: (int) width lineNum: (int*) lineNum lineLength: (int*) lineLength includesEndOfLine: (BOOL*) includesEndOfLine
{
    int prev = 0;
    int length;
    int i;
    for (i = first_entry; i < cll_entries; ++i) {
        int cll = cumulative_line_lengths[i] - start_offset;
        length = cll - prev;
        int spans = (length - 1) / width;
        if (*lineNum > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            *lineNum -= consume;
        } else {  // *lineNum <= spans
            // We found the raw line that inclues the wrapped line we're searching for.
            int consume = *lineNum;  // eat up this many width-sized wrapped lines from this start of the current full line
            *lineNum = 0;
            int offset = consume * width;  // the relevant part of the raw line begins at this offset into it
            *lineLength = length - offset;  // the length of the suffix of the raw line, beginning at the wrapped line we want
            if (*lineLength > width) {
                // return an infix of the full line
                *lineLength = width;
                *includesEndOfLine = NO;
            } else {
                // return a suffix of the full line
                if (i == cll_entries - 1 && is_partial) {
                    // If this is the last line and it's partial then it doesn't have an end-of-line.
                    *includesEndOfLine = NO;
                } else {
                    *includesEndOfLine = YES;
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
        count += (length - 1) / width + 1;
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
        // wrap as: 0123/4567/89
        int offset_from_start = width * ((available_len - 1) / width);
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
        int spans = (length - 1) / width;
        if (n > spans) {
            // Consume the entire raw line and keep looking for more.
            int consume = spans + 1;
            n -= consume;
        } else {  // n <= spans
            // We found the raw line that inclues the wrapped line we're searching for.
            int consume = n;  // eat up this many width-sized wrapped lines from this start of the current full line
            int offset = consume * width;  // the relevant part of the raw line begins at this offset into it
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

// TODO: Make this more unicode friendly
BOOL stringCaseCompare(unichar* needle, int needle_len, screen_char_t* haystack, int haystack_len, int* result_length)
{
	int i;
	if (needle_len > haystack_len) {
		return NO;
	}
	for (i = 0; i < needle_len; ++i) {
		if (haystack[i].ch != 0xffff && tolower(needle[i]) != tolower(haystack[i].ch)) {
			return NO;
		}
	}
	*result_length = i;
	return YES;
} 

BOOL stringCompare(unichar* needle, int needle_len, screen_char_t* haystack, int haystack_len, int* result_length)
{
	int i;
	if (needle_len > haystack_len) {
		return NO;
	}
	for (i = 0; i < needle_len; ++i) {
		if (haystack[i].ch != 0xffff && needle[i] != haystack[i].ch) {
			return NO;
		}
	}
	*result_length = i;
	return YES;
}

- (int) _lineRawOffset: (int) index
{
	if (index == first_entry) {
		return start_offset;
	} else {
		return cumulative_line_lengths[index - 1];
	}
}

- (int) _findInRawLine:(int) entry needle:(NSString*) substring options: (int) options skip: (int) skip length: (int) raw_line_length resultLength: (int*) resultLength
{
	screen_char_t* rawline = raw_buffer + [self _lineRawOffset:entry];
	unichar buffer[1000];
	NSRange range;
	range.location = 0;
	range.length = [substring length];
	if (range.length > 1000) {
		range.length = 1000;
	}
	[substring getCharacters:buffer range:range];

	// TODO: use a smarter search algorithm
	if (options & FindOptBackwards) {
		int i;
		NSAssert(skip >= 0, @"Negative skip");
		if (skip + range.length > raw_line_length) {
			skip = raw_line_length - range.length;
		}
		if (skip < 0) {
			return -1;
		}
		if (options & FindOptCaseInsensitive) {
			for (i = skip; i >= 0; --i) {
				if (stringCaseCompare(buffer, range.length, rawline + i, raw_line_length - i, resultLength)) {
					return i;
				}
			}
		} else {
			for (i = skip; i >= 0; --i) {
				if (stringCompare(buffer, range.length, rawline + i, raw_line_length - i, resultLength)) {
					return i;
				}
			}
		}
	} else {
		int i;
		int limit = raw_line_length - [substring length];
		if (skip + range.length > raw_line_length) {
			return -1;
		}
		if (options & FindOptCaseInsensitive) {
			for (i = skip; i <= limit; ++i) {
				if (stringCaseCompare(buffer, range.length, rawline + i, raw_line_length - i, resultLength)) {
					return i;
				}
			}
		} else {
			for (i = skip; i <= limit; ++i) {
				if (stringCompare(buffer, range.length, rawline + i, raw_line_length - i, resultLength)) {
					return i;
				}
			}
		}			
	}
	return -1;
}
				
- (int) _lineLength: (int) index
{
	int prev;
	if (index == first_entry) {
		prev = start_offset;
	} else {
		prev = cumulative_line_lengths[index - 1];
	}
	return cumulative_line_lengths[index] - prev;
}

- (int) _findEntryBeforeOffset: (int) offset
{
	NSAssert(offset >= start_offset, @"Offset before start_offset");
	int i;
	for (i = first_entry; i < cll_entries; ++i) {
		if (cumulative_line_lengths[i] > offset) {
			return i;
		}
	}
	NSAssert(NO, @"Offset not in block");
	return cll_entries - 1;
}

- (int) findSubstring: (NSString*) substring options: (int) options atOffset: (int) offset resultLength: (int*) resultLength
{
	if (offset == -1) {
		offset = [self rawSpaceUsed] - 1;
	}
	int entry;
	int limit;
	int dir;
	if (options & FindOptBackwards) {
		entry = [self _findEntryBeforeOffset: offset];
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
		int pos = [self _findInRawLine:entry needle:substring options:options skip: skipped length: [self _lineLength: entry] resultLength: resultLength];
		if (pos != -1) {
			return pos + line_raw_offset;
		}
		entry += dir;
	}
	return -1;
}

- (BOOL) convertPosition: (int) position withWidth: (int) width toX: (int*) x toY: (int*) y
{
	int i;
	*x = 0;
	*y = 0;
	int prev = start_offset;
	for (i = first_entry; i < cll_entries; ++i) {
		int eol = cumulative_line_lengths[i];
		int line_length = eol-prev;
		if (position >= eol) {
			int spans = (line_length - 1) / width;
			*y += spans + 1;
		} else {
			int bytes_to_consume_in_this_line = position - prev;
			int consume = bytes_to_consume_in_this_line / width;
			*y += consume;
			if (consume > 0) {
				*x = bytes_to_consume_in_this_line % (consume * width);
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
    return self;
}

// Return the number of wrapped lines, not including dropped lines.
- (int) _rawNumLinesWithWidth: (int) width
{
    int count = 0;
    int i;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex: i];
        count += [block getNumLinesWithWrapWidth: width];
    }
    return count;
}

// drop lines if needed until max_lines is reached.
- (void) _dropLinesForWidth: (int) width
{
    if (max_lines == -1) {
        // Do nothing: the buffer is infinite.
        return;
    }
    
    int total_lines = [self _rawNumLinesWithWidth: width];
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
        }
        total_lines -= dropped;
    }
}

- (void) setMaxLines: (int) maxLines
{
    max_lines = maxLines;
}


- (int) dropExcessLinesWithWidth: (int) width
{
    int nl = [self _rawNumLinesWithWidth: width];
    if (nl > max_lines) {
        [self _dropLinesForWidth: width];
    }
    return nl - [self _rawNumLinesWithWidth: width];
}

- (void) dump
{
    int i;
    for (i = 0; i < [blocks count]; ++i) {
        NSLog(@"Block %d:\n", i);
        [[blocks objectAtIndex: i] dump];
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

- (void) appendLine: (screen_char_t*) buffer length: (int) length partial: (BOOL) partial
{
#ifdef LOG_MUTATIONS
    {
        char a[1000];
        int i;
        for (i = 0; i < length; i++) {
            a[i] = buffer[i].ch ? buffer[i].ch : '.';
        }
        a[i] = '\0';
        NSLog(@"Append: %s\n", a);
    }
#endif
    if ([blocks count] == 0) {
        [self _addBlockOfSize: block_size];
    }
    
    LineBlock* block = [blocks objectAtIndex: ([blocks count] - 1)]; 
    if (![block appendLine: buffer length: length partial: partial]) {
        int prefix_len = 0;
        screen_char_t* prefix = NULL;
        if ([block hasPartial]) {
            // There is a line that's too long for the current block to hold.
            // Remove its prefix fromt he current block and later add the
            // concatenation of prefix + buffer to a larger block.
            screen_char_t* temp;
            BOOL ok = [block popLastLineInto: &temp withLength: &prefix_len upToWidth: [block rawBufferSize]+1];
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
    }
}

// Copy a line into the buffer. If the line is shorter than 'width' then only the first 'width' characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
- (BOOL) copyLineToBuffer: (screen_char_t*) buffer width: (int) width lineNum: (int) lineNum
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
        BOOL eol;
        screen_char_t* p = [block getWrappedLineWithWrapWidth: width lineNum: &line lineLength: &length includesEndOfLine: &eol];
        if (p) {
            NSAssert(length <= width, @"Length too long");
            memcpy((char*) buffer, (char*) p, length * sizeof(screen_char_t));
            return !eol;
        }
    }
    NSLog(@"Couldn't find line %d", lineNum);
    NSAssert(NO, @"Tried to get non-existant line");
    return NO;
}

- (int) numLinesWithWidth: (int) width
{
    return [self _rawNumLinesWithWidth: width];
}

- (BOOL) popAndCopyLastLineInto: (screen_char_t*) ptr width: (int) width includesEndOfLine: (BOOL*) includsEndOfLine;
{
    if ([self numLinesWithWidth: width] == 0) {
        return NO;
    }
    
    LineBlock* block = [blocks lastObject];
    
    // If the line is partial the client will want to add a continuation marker so 
    // tell him there's no EOL in that case.
    *includsEndOfLine = ![block hasPartial];
    
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
            a[i] = ptr[i].ch ? ptr[i].ch : '.';
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
        int last_line_length = [block getRawLineLength: [block numRawLines]-1];
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
        int last_line_length = [block getRawLineLength: [block numRawLines]-1];
        int num_overflow_lines = (last_line_length-1) / width;
        int min_x = num_overflow_lines * width;
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

- (int) findSubstring: (NSString*) substring startingAt: (int) start resultLength: (int*) length options: (int) options stopAt: (int) stopAt
{
	int i;
	int offset;
	if ([self _findPosition: start inBlock: &i inOffset: &offset]) {
		int dir;
		if (options & FindOptBackwards) {
			dir = -1;
		} else {
			dir = 1;
		}
		while (i >= 0 && i < [blocks count]) {
			LineBlock* block = [blocks objectAtIndex:i];
			int position = [block findSubstring: substring options: options atOffset: offset resultLength: length];
			if (position >= 0) {
				position += [self _blockPosition:i];
				if (dir * (position - stopAt) > 0 || dir * (position + *length - stopAt) > 0) {
					return -1;
				}
			}
			if (position >= 0) {
				return position;
			}
			if (dir < 0) {
				offset = -1;
			} else {
				offset = 0;
			}
			i += dir;
		}
	}
	return -1;
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
        if (block_lines < line) {
            line -= block_lines;
			*position += [block rawSpaceUsed];
            continue;
        }
		
		int pos;
		pos = [block getPositionOfLine: &line atX: x withWidth: width];
		if (pos >= 0) {
			int tempx, tempy;
			if ([self convertPosition:pos+offset withWidth:width toX:&tempx toY:&tempy]) {
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
