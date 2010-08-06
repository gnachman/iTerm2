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

#import <Cocoa/Cocoa.h>

typedef struct screen_char_t
{
    // ch has some special meanings:
    //   0: Signifies no character was ever set at this location. Not selectable.
    //   0xffff: The next character is a double-width character.
    // In the WIDTH+1 position on a line, this takes the value of 0 or 1. If 1, then the
    // next line is a continuation of this one (it's a long line that wrapped).
    unichar ch;            // the actual character.
    unsigned int bg_color; // background color
    unsigned int fg_color; // foreground color
} screen_char_t;

// LineBlock represents an ordered collection of lines of text. It stores them contiguously
// in a buffer.
@interface LineBlock : NSObject {
    // The raw lines, end-to-end. There is no delimiter between each line.
    screen_char_t* raw_buffer;
    screen_char_t* buffer_start;  // usable start of buffer (stuff before this is dropped)
    
    int start_offset;  // distance from raw_buffer to buffer_start
    int first_entry;  // first valid cumulative_line_length
    
    // The number of elements allocated for raw_buffer.
    int buffer_size;
    
    // There will be as many entries in this array as there are lines in raw_buffer.
    // The ith value is the length of the ith line plus the value of 
    // cumulative_line_lengths[i-1] for i>0 or 0 for i==0.
    int* cumulative_line_lengths;
    
    // The number of elements allocated for cumulative_line_lengths.
    int cll_capacity;
    
    // The number of values in the cumulative_line_lengths array.
    int cll_entries;
    
    // If true, then the last raw line does not include a logical newline at its terminus.
    BOOL is_partial;
    
    // The number of wrapped lines if width==cached_numlines_width.
    int cached_numlines;
    
    // This is -1 if the cache is invalid; otherwise it specifies the width for which
    // cached_numlines is correct.
    int cached_numlines_width;
}

- (LineBlock*) initWithRawBufferSize: (int) size;

- (void) dealloc;

// Try to append a line to the end of the buffer. Returns false if it does not fit. If length > buffer_size it will never succeed.
// Callers should split such lines into multiple pieces.
- (BOOL) appendLine: (screen_char_t*) buffer length: (int) length partial: (BOOL) partial;

// Try to get a line that is lineNum after the first line in this block after wrapping them to a given width.
// If the line is present, return a pointer to its start and fill in *lineLength with the number of bytes in the line.
// If the line is not present, decrement *lineNum by the number of lines in this block and return NULL.
- (screen_char_t*) getWrappedLineWithWrapWidth: (int) width lineNum: (int*) lineNum lineLength: (int*) lineLength includesEndOfLine: (BOOL*) includesEndOfLine;

// Get the number of lines in this block at a given screen width.
- (int) getNumLinesWithWrapWidth: (int) width;

// Returns whether getNumLinesWithWrapWidth will be fast.
- (BOOL) hasCachedNumLinesForWidth: (int) width;

// Returns true if the last line is incomplete.
- (BOOL) hasPartial;

// Remove the last line. Returns false if there was none.
- (BOOL) popLastLineInto: (screen_char_t**) ptr withLength: (int*) length upToWidth: (int) width;

// Drop lines from the start of the buffer. Returns the number of lines actually dropped
// (either n or the number of lines in the block).
- (int) dropLines: (int) n withWidth: (int) width;

// Returns true if there are no lines in the block
- (BOOL) isEmpty;

// Grow the buffer.
- (void) changeBufferSize: (int) capacity;

// Get the size of the raw buffer.
- (int) rawBufferSize;

// Return the number of raw (unwrapped) lines
- (int) numRawLines;

// Return the position of the first used character in the raw buffer. Only valid if not empty.
- (int) startOffset;

// Return the length of a raw (unwrapped) line
- (int) getRawLineLength: (int) linenum;

// Remove extra space from the end of the buffer. Future appends will fail.
- (void) shrinkToFit;

// Append a value to cumulativeLineLengths.
- (void) _appendCumulativeLineLength: (int) cumulativeLength;

// NSLog the contents of the block. For debugging.
- (void) dump;
@end

// A LineBuffer represents an ordered collection of strings of screen_char_t. Each string forms a
// logical line of text plus color information. Logic is provided for the following major functions:
//   - If the lines are wrapped onto a screen of some width, find the Nth wrapped line
//   - Append a line
//   - If the lines are wrapped onto a screen of some width, remove the last wrapped line
//   - Store and retrieve a cursor position
//   - Store an unlimited or a fixed number of wrapped lines
// The implementation uses an array of small blocks that hold a few kb of unwrapped lines. Each
// block caches some information to speed up repeated lookups with the same screen width.
@interface LineBuffer : NSObject {
    // An array of LineBlock*s.
    NSMutableArray* blocks;
    
    // The default storage for a LineBlock (some may be larger to accomodate very long lines).
    int block_size;
    
    // If a cursor size is saved, this gives its offset from the start of its line.
    int cursor_x;
    
    // The raw line number (in lines from the first block) of the cursor.
    int cursor_rawline;
    
    // The maximum number of lines to store. In truth, more lines will be stored, but no more
    // than max_lines will be exposed by the interface.
    int max_lines;
}

- (LineBuffer*) initWithBlockSize: (int) bs;

- (LineBuffer*) init;

// Call this immediately after init. Otherwise the buffer will hold unlimited lines (until you
// run out of memory).
- (void) setMaxLines: (int) maxLines;

// Add a line to the buffer. Set partial to true if there's more coming for this line:
// that is to say, this buffer contains only a prefix or infix of the entire line.
//
// NOTE: call dropExcessLinesWithWidth after this if you want to limit the buffer to max_lines.
- (void) appendLine: (screen_char_t*) buffer length: (int) length partial: (BOOL) partial;

// If more lines are in the buffer than max_lines, call this function. It will adjust the count
// of excess lines and try to free the first block(s) if they are unused. Because this could happen
// after any call to appendLines, you should always call this after appendLines.
//
// Returns the number of lines in the buffer that overflowed max_lines.
//
// NOTE: This invalidates the cursor position.
- (int) dropExcessLinesWithWidth: (int) width;

// Copy a line into the buffer. If the line is shorter than 'width' then only the first 'width'
// characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
// Returns true if a continuation marker is needed at the end of this line.
- (BOOL) copyLineToBuffer: (screen_char_t*) buffer width: (int) width lineNum: (int) lineNum;

// Copy up to width chars from the last line into *ptr. The last line will be removed or
// truncated from the buffer. Sets *includesEndOfLine to true if this line should have a
// continuation marker.
- (BOOL) popAndCopyLastLineInto: (screen_char_t*) ptr width: (int) width includesEndOfLine: (BOOL*) includesEndOfLine;

// Get the number of buffer lines at a given width.
- (int) numLinesWithWidth: (int) width;

// Save the cursor position. Call this just before appending the line the cursor is in. 
// x gives the offset from the start of the next line appended. The cursor position is
// invalidated if dropExcessLinesWithWidth is called.
- (void) setCursor: (int) x;

// If the last wrapped line has the cursor, return true and set *x to its horizontal position.
// 0 <= *x <= width (if *x == width then the cursor is actually on the next line).
// Call this just before popAndCopyLastLineInto:width:includesEndOfLine.
- (BOOL) getCursorInLastLineWithWidth: (int) width atX: (int*) x;

// Print the raw lines to the console for debugging.
- (void) dump;

// Search for a substring. If found, return the position of the hit. Otherwise return -1. Use 0 for the start to indicate the beginning of the buffer or
// pass the result of a previous findSubstring result. The number of positions the result occupies will be set in *length (which would be different than the
// length of the substring in the presence of double-width characters.
#define FindOptCaseInsensitive (1 << 0)
#define FindOptBackwards       (1 << 1)
- (int) findSubstring: (NSString*) substring startingAt: (int) start resultLength: (int*) length options: (int) options stopAt: (int) stopAt;

// Convert a position (as returned by findSubstring) into an x,y position.
// Returns TRUE if the conversion was successful, false if the position was out of bounds.
- (BOOL) convertPosition: (int) position withWidth: (int) width toX: (int*) x toY: (int*) y;

// Convert x,y coordinates (with y=0 being the first line) into a position. Offset is added to the position safely.
// Returns TRUE if the conversion was successful, false, if out of bounds.
- (BOOL) convertCoordinatesAtX: (int) x atY: (int) y withWidth: (int) width toPosition: (int*) position offset:(int)offset;

// Returns the position at the stat of the buffer
- (int) firstPos;

// Returns the position at the end of the buffer
- (int) lastPos;

@end
