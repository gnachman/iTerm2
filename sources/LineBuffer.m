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

#import "LineBuffer.h"

#import "BackgroundThread.h"
#import "LineBlock.h"
#import "RegexKitLite.h"

static NSString *const kLineBufferVersionKey = @"Version";
static NSString *const kLineBufferBlocksKey = @"Blocks";
static NSString *const kLineBufferBlockSizeKey = @"Block Size";
static NSString *const kLineBufferCursorXKey = @"Cursor X";
static NSString *const kLineBufferCursorRawlineKey = @"Cursor Rawline";
static NSString *const kLineBufferMaxLinesKey = @"Max Lines";
static NSString *const kLineBufferNumDroppedBlocksKey = @"Num Dropped Blocks";
static NSString *const kLineBufferDroppedCharsKey = @"Dropped Chars";
static NSString *const kLineBufferTruncatedKey = @"Truncated";
static NSString *const kLineBufferMayHaveDWCKey = @"May Have Double Width Character";

static const int kLineBufferVersion = 1;

@implementation LineBuffer {
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

    // The number of blocks at the head of the list that have been removed.
    int num_dropped_blocks;

    // Cache of the number of wrapped lines
    int num_wrapped_lines_cache;
    int num_wrapped_lines_width;

    // Number of char that have been dropped
    long long droppedChars;
}

// Append a block
- (LineBlock*) _addBlockOfSize: (int) size
{
    LineBlock* block = [[LineBlock alloc] initWithRawBufferSize: size];
    block.mayHaveDoubleWidthCharacter = self.mayHaveDoubleWidthCharacter;
    [blocks addObject:block];
    [block release];
    return block;
}

- (instancetype)init {
    // I picked 8k because it's a multiple of the page size and should hold about 100-200 lines
    // on average. Very small blocks make finding a wrapped line expensive because caching the
    // number of wrapped lines is spread out over more blocks. Very large blocks are expensive
    // because of the linear search through a block for the start of a wrapped line. This is
    // in the middle. Ideally, the number of blocks would equal the number of wrapped lines per
    // block, and this should be in that neighborhood for typical uses.
    const int BLOCK_SIZE = 1024 * 8;
    return [self initWithBlockSize:BLOCK_SIZE];
}

- (void)commonInit {
    blocks = [[NSMutableArray alloc] init];
    max_lines = -1;
    num_wrapped_lines_width = -1;
    num_dropped_blocks = 0;
}

// The designated initializer. We prefer not to explose the notion of block sizes to
// clients, so this is internal.
- (LineBuffer*)initWithBlockSize:(int)bs
{
    self = [super init];
    if (self) {
        [self commonInit];
        block_size = bs;
        [self _addBlockOfSize:block_size];
    }
    return self;
}

- (LineBuffer *)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        [self commonInit];
        if ([dictionary[kLineBufferVersionKey] intValue] != kLineBufferVersion) {
            [self autorelease];
            return nil;
        }
        _mayHaveDoubleWidthCharacter = [dictionary[kLineBufferMayHaveDWCKey] boolValue];
        block_size = [dictionary[kLineBufferBlockSizeKey] intValue];
        cursor_x = [dictionary[kLineBufferCursorXKey] intValue];
        cursor_rawline = [dictionary[kLineBufferCursorRawlineKey] intValue];
        max_lines = [dictionary[kLineBufferMaxLinesKey] intValue];
        num_dropped_blocks = [dictionary[kLineBufferNumDroppedBlocksKey] intValue];
        droppedChars = [dictionary[kLineBufferDroppedCharsKey] longLongValue];
        for (NSDictionary *blockDictionary in dictionary[kLineBufferBlocksKey]) {
            LineBlock *block = [LineBlock blockWithDictionary:blockDictionary];
            if (!block) {
                [self autorelease];
                return nil;
            }
            [blocks addObject:block];
        }
    }
    return self;
}

- (void)dealloc
{
    // This causes the blocks to be released in a background thread.
    // When a LineBuffer is really gigantic, it can take
    // quite a bit of time to release all the blocks.
    [blocks performSelector:@selector(removeAllObjects)
                   onThread:[BackgroundThread backgroundThread]
                 withObject:nil
              waitUntilDone:NO];
    [blocks release];
    [super dealloc];
}

- (void)setMayHaveDoubleWidthCharacter:(BOOL)mayHaveDoubleWidthCharacter {
    if (!_mayHaveDoubleWidthCharacter) {
        _mayHaveDoubleWidthCharacter = mayHaveDoubleWidthCharacter;
        for (LineBlock *block in blocks) {
            block.mayHaveDoubleWidthCharacter = YES;
        }
    }
}

// This is called a lot so it's a C function to avoid obj_msgSend
static int RawNumLines(LineBuffer* buffer, int width) {
    if (buffer->num_wrapped_lines_width == width) {
        return buffer->num_wrapped_lines_cache;
    }
    int count = 0;
    int i;
    const int numBlocks = [buffer->blocks count];
    for (i = 0; i < numBlocks; ++i) {
        LineBlock* block = [buffer->blocks objectAtIndex: i];
        count += [block getNumLinesWithWrapWidth: width];
    }
    buffer->num_wrapped_lines_width = width;
    buffer->num_wrapped_lines_cache = count;
    return count;
}


- (void) setMaxLines: (int) maxLines
{
    max_lines = maxLines;
    num_wrapped_lines_width = -1;
}


- (int)dropExcessLinesWithWidth: (int) width
{
    int nl = RawNumLines(self, width);
    int totalDropped = 0;
    if (max_lines != -1 && nl > max_lines) {
        LineBlock *block = blocks[0];
        int total_lines = nl;
        while (total_lines > max_lines) {
            int extra_lines = total_lines - max_lines;
            
            int block_lines = [block getNumLinesWithWrapWidth: width];
#if ITERM_DEBUG
            NSAssert(block_lines > 0, @"Empty leading block");
#endif
            int toDrop = block_lines;
            if (toDrop > extra_lines) {
                toDrop = extra_lines;
            }
            int charsDropped;
            int dropped = [block dropLines:toDrop withWidth:width chars:&charsDropped];
            totalDropped += dropped;
            droppedChars += charsDropped;
            if ([block isEmpty]) {
                [blocks removeObjectAtIndex:0];
                ++num_dropped_blocks;
                if ([blocks count] > 0) {
                    block = blocks[0];
                }
            }
            total_lines -= dropped;
        }
        num_wrapped_lines_cache = total_lines;
    }
#if ITERM_DEBUG
    assert(totalDropped == (nl - RawNumLines(self, width)));
#endif
    return totalDropped;
}

- (NSString *)debugString {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < [blocks count]; i++) {
        LineBlock *block = [blocks objectAtIndex:i];
        [block appendToDebugString:s];
    }
    return [s length] ? [s substringToIndex:s.length - 1] : @"";  // strip trailing newline
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

- (NSString *)compactLineDumpWithWidth:(int)width andContinuationMarks:(BOOL)continuationMarks {
    NSMutableString *s = [NSMutableString string];
    int n = [self numLinesWithWidth:width];
    for (int i = 0; i < n; i++) {
        screen_char_t continuation;
        ScreenCharArray *line = [self wrappedLineAtIndex:i width:width continuation:&continuation];
        [s appendFormat:@"%@", ScreenCharArrayToStringDebug(line.line, line.length)];
        for (int j = line.length; j < width; j++) {
            [s appendString:@"."];
        }
        if (continuationMarks) {
            if (continuation.code == EOL_HARD) {
                [s appendString:@"!"];
            } else if (continuation.code == EOL_SOFT) {
                [s appendString:@"+"];
            } else if (continuation.code == EOL_DWC) {
                [s appendString:@">"];
            } else {
                [s appendString:@"?"];
            }
        }
        if (i < n - 1) {
            [s appendString:@"\n"];
        }
    }
    return s;
}

- (void)dumpWrappedToWidth:(int)width
{
    NSLog(@"%@", [self compactLineDumpWithWidth:width andContinuationMarks:NO]);
}

- (void)appendLine:(screen_char_t*)buffer
            length:(int)length
           partial:(BOOL)partial
             width:(int)width
         timestamp:(NSTimeInterval)timestamp
      continuation:(screen_char_t)continuation
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
    if (![block appendLine:buffer
                    length:length
                   partial:partial
                     width:width
                 timestamp:timestamp
              continuation:continuation]) {
        // It's going to be complicated. Invalidate the number of wrapped lines
        // cache.
        num_wrapped_lines_width = -1;
        int prefix_len = 0;
        NSTimeInterval prefixTimestamp = 0;
        screen_char_t* prefix = NULL;
        if ([block hasPartial]) {
            // There is a line that's too long for the current block to hold.
            // Remove its prefix from the current block and later add the
            // concatenation of prefix + buffer to a larger block.
            screen_char_t* temp;
            BOOL ok = [block popLastLineInto:&temp
                                  withLength:&prefix_len
                                   upToWidth:[block rawBufferSize]+1
                                   timestamp:&prefixTimestamp
                                continuation:NULL];
            assert(ok);
            prefix = (screen_char_t*) malloc(MAX(1, prefix_len) * sizeof(screen_char_t));
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
            BOOL ok __attribute__((unused)) =
                [block appendLine:prefix
                           length:prefix_len
                          partial:YES
                            width:width
                        timestamp:prefixTimestamp
                     continuation:continuation];
            NSAssert(ok, @"append can't fail here");
            free(prefix);
        }
        // Finally, append this line to the new block. We know it'll fit because we made
        // enough room for it.
        BOOL ok __attribute__((unused)) =
            [block appendLine:buffer
                       length:length
                      partial:partial
                        width:width
                    timestamp:timestamp
                 continuation:continuation];
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

- (NSTimeInterval)timestampForLineNumber:(int)lineNum width:(int)width
{
    int line = lineNum;
    int i;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        NSAssert(block, @"Null block");
        
        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines <= line) {
            line -= block_lines;
            continue;
        }
        
        return [block timestampForLineNumber:line width:width];
    }
    return 0;
}

// Copy a line into the buffer. If the line is shorter than 'width' then only
// the first 'width' characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
- (int)copyLineToBuffer:(screen_char_t *)buffer
                  width:(int)width
                lineNum:(int)lineNum
           continuation:(screen_char_t *)continuationPtr
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
        screen_char_t continuation;
        screen_char_t* p = [block getWrappedLineWithWrapWidth:width
                                                      lineNum:&line
                                                   lineLength:&length
                                            includesEndOfLine:&eol
                                                 continuation:&continuation];
        if (continuationPtr) {
            *continuationPtr = continuation;
        }
        if (p) {
            NSAssert(length <= width, @"Length too long");
            memcpy((char*) buffer, (char*) p, length * sizeof(screen_char_t));
            [self extendContinuation:continuation inBuffer:buffer ofLength:length toWidth:width];
            return eol;
        }
    }
    NSLog(@"Couldn't find line %d", lineNum);
    NSAssert(NO, @"Tried to get non-existant line");
    return NO;
}

- (void)extendContinuation:(screen_char_t)continuation
                  inBuffer:(screen_char_t *)buffer
                  ofLength:(int)length
                   toWidth:(int)width {
    // The LineBlock stores a "continuation" screen_char_t for each line.
    // Clients set this when appending a line to the LineBuffer that has an
    // EOL_HARD. It defines the foreground and background color that null cells
    // added after the end of the line stored in the LineBuffer will have
    // onscreen. We take the continuation and extend it to the end of the
    // buffer, zeroing out the code.
    for (int i = length; i < width; i++) {
        buffer[i] = continuation;
        buffer[i].code = 0;
        buffer[i].complexChar = NO;
    }
}

- (ScreenCharArray *)wrappedLineAtIndex:(int)lineNum
                                  width:(int)width
                           continuation:(screen_char_t *)continuation {
    int line = lineNum;
    int i;
    ScreenCharArray *result = [[[ScreenCharArray alloc] init] autorelease];
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];

        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines < line) {
            line -= block_lines;
            continue;
        }

        int length, eol;
        result.line = [block getWrappedLineWithWrapWidth:width
                                                 lineNum:&line
                                              lineLength:&length
                                       includesEndOfLine:&eol
                                            continuation:continuation];
        if (result.line) {
            result.length = length;
            result.eol = eol;
            NSAssert(result.length <= width, @"Length too long");
            return result;
        }
    }
    NSLog(@"Couldn't find line %d", lineNum);
    NSAssert(NO, @"Tried to get non-existant line");
    return nil;
}

- (int)numLinesWithWidth:(int)width {
    if (width == 0) {
        return 0;
    }
    return RawNumLines(self, width);
}

- (BOOL)popAndCopyLastLineInto:(screen_char_t*)ptr
                         width:(int)width
             includesEndOfLine:(int*)includesEndOfLine
                     timestamp:(NSTimeInterval *)timestampPtr
                  continuation:(screen_char_t *)continuationPtr
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
    screen_char_t continuation;
    BOOL ok __attribute__((unused)) =
        [block popLastLineInto:&temp
                    withLength:&length
                     upToWidth:width
                     timestamp:timestampPtr
                  continuation:&continuation];
    if (continuationPtr) {
        *continuationPtr = continuation;
    }
    NSAssert(ok, @"Unexpected empty block");
    NSAssert(length <= width, @"Length too large");
    NSAssert(length >= 0, @"Negative length");

    // Copy into the provided buffer.
    memcpy(ptr, temp, sizeof(screen_char_t) * length);
    [self extendContinuation:continuation inBuffer:ptr ofLength:length toWidth:width];

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
                                                   width,
                                                   _mayHaveDoubleWidthCharacter);
        int min_x = OffsetOfWrappedLine(lastRawLine,
                                        num_overflow_lines,
                                        last_line_length,
                                        width,
                                        _mayHaveDoubleWidthCharacter);
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

- (BOOL)_findPosition:(LineBufferPosition *)start inBlock:(int*)block_num inOffset:(int*)offset
{
    int i;
    int position = start.absolutePosition - droppedChars;
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

- (void)prepareToSearchFor:(NSString*)substring
                startingAt:(LineBufferPosition *)start
                   options:(FindOptions)options
               withContext:(FindContext*)context {
    context.substring = substring;
    context.options = options;
    if (options & FindOptBackwards) {
        context.dir = -1;
    } else {
        context.dir = 1;
    }
    int offset = context.offset;
    int absBlockNum = context.absBlockNum;
    if ([self _findPosition:start inBlock:&absBlockNum inOffset:&offset]) {
        context.offset = offset;
        context.absBlockNum = absBlockNum + num_dropped_blocks;
        context.status = Searching;
    } else {
        context.status = NotFound;
    }
    context.results = [NSMutableArray array];
}

- (void)findSubstring:(FindContext*)context stopAt:(int)stopAt
{
    if (context.dir > 0) {
        // Search forwards
        if (context.absBlockNum < num_dropped_blocks) {
            // The next block to search was dropped. Skip ahead to the first block.
            // NSLog(@"Next to search was dropped. Skip to start");
            context.absBlockNum = num_dropped_blocks;
        }
        if (context.absBlockNum - num_dropped_blocks >= [blocks count]) {
            // Got to bottom
            // NSLog(@"Got to bottom");
            context.status = NotFound;
            return;
        }
    } else {
        // Search backwards
        if (context.absBlockNum < num_dropped_blocks) {
            // Got to top
            // NSLog(@"Got to top");
            context.status = NotFound;
            return;
        }
    }

    NSAssert(context.absBlockNum - num_dropped_blocks >= 0, @"bounds check");
    NSAssert(context.absBlockNum - num_dropped_blocks < [blocks count], @"bounds check");
    LineBlock* block = [blocks objectAtIndex:context.absBlockNum - num_dropped_blocks];

    if (context.absBlockNum - num_dropped_blocks == 0 &&
        context.offset != -1 &&
        context.offset < [block startOffset]) {
        if (context.dir > 0) {
            // Part of the first block has been dropped. Skip ahead to its
            // current beginning.
            context.offset = [block startOffset];
        } else {
            // This block has scrolled off.
            // NSLog(@"offset=%d, block's startOffset=%d. give up", context.offset, [block startOffset]);
            context.status = NotFound;
            return;
        }
    }

    // NSLog(@"search block %d starting at offset %d", context.absBlockNum - num_dropped_blocks, context.offset);

    [block findSubstring:context.substring
                 options:context.options
                atOffset:context.offset
                 results:context.results
         multipleResults:((context.options & FindMultipleResults) != 0)];
    NSMutableArray* filtered = [NSMutableArray arrayWithCapacity:[context.results count]];
    BOOL haveOutOfRangeResults = NO;
    int blockPosition = [self _blockPosition:context.absBlockNum - num_dropped_blocks];
    for (ResultRange* range in context.results) {
        range->position += blockPosition;
        if (context.dir * (range->position - stopAt) > 0 ||
            context.dir * (range->position + context.matchLength - stopAt) > 0) {
            // result was outside the range to be searched
            haveOutOfRangeResults = YES;
        } else {
            // Found a good result.
            context.status = Matched;
            [filtered addObject:range];
        }
    }
    context.results = filtered;
    if ([filtered count] == 0 && haveOutOfRangeResults) {
        context.status = NotFound;
    }

    // Prepare to continue searching next block.
    if (context.dir < 0) {
        context.offset = -1;
    } else {
        context.offset = 0;
    }
    context.absBlockNum = context.absBlockNum + context.dir;
}

// Returns an array of XRange values
- (NSArray*)convertPositions:(NSArray*)resultRanges withWidth:(int)width
{
    // Create sorted array of all positions to convert.
    NSMutableArray* unsortedPositions = [NSMutableArray arrayWithCapacity:[resultRanges count] * 2];
    for (ResultRange* rr in resultRanges) {
        [unsortedPositions addObject:[NSNumber numberWithInt:rr->position]];
        [unsortedPositions addObject:[NSNumber numberWithInt:rr->position + rr->length - 1]];
    }

    // Walk blocks and positions in parallel, converting each position in order. Store in
    // intermediate dict, mapping position->NSPoint(x,y)
    NSArray *positionsArray = [unsortedPositions sortedArrayUsingSelector:@selector(compare:)];
    int i = 0;
    int yoffset = 0;
    int numBlocks = [blocks count];
    int passed = 0;
    LineBlock *block = [blocks objectAtIndex:0];
    int used = [block rawSpaceUsed];
    NSMutableDictionary* intermediate = [NSMutableDictionary dictionaryWithCapacity:[resultRanges count] * 2];
    int prev = -1;
    for (NSNumber* positionNum in positionsArray) {
        int position = [positionNum intValue];
        if (position == prev) {
            continue;
        }
        prev = position;

        // Advance block until it includes this position
        while (position >= passed + used && i < numBlocks) {
            passed += used;
            yoffset += [block getNumLinesWithWrapWidth:width];
            i++;
            if (i < numBlocks) {
                block = [blocks objectAtIndex:i];
                used = [block rawSpaceUsed];
            }
        }
        if (i < numBlocks) {
            int x, y;
            assert(position >= passed);
            assert(position < passed + used);
            assert(used == [block rawSpaceUsed]);
            BOOL isOk = [block convertPosition:position - passed
                                     withWidth:width
                                           toX:&x
                                           toY:&y];
            assert(x < 2000);
            if (isOk) {
                y += yoffset;
                [intermediate setObject:[NSValue valueWithPoint:NSMakePoint(x, y)]
                                 forKey:positionNum];
            } else {
                assert(false);
            }
        }
    }

    // Walk the positions array and populate results by looking up points in intermediate dict.
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[resultRanges count]];
    for (ResultRange* rr in resultRanges) {
        NSValue *start = [intermediate objectForKey:[NSNumber numberWithInt:rr->position]];
        NSValue *end = [intermediate objectForKey:[NSNumber numberWithInt:rr->position + rr->length - 1]];
        if (start && end) {
            XYRange *xyrange = [[[XYRange alloc] init] autorelease];
            NSPoint startPoint = [start pointValue];
            NSPoint endPoint = [end pointValue];
            xyrange->xStart = startPoint.x;
            xyrange->yStart = startPoint.y;
            xyrange->xEnd = endPoint.x;
            xyrange->yEnd = endPoint.y;
            [result addObject:xyrange];
        } else {
            assert(false);
            [result addObject:[NSNull null]];
        }
    }

    return result;
}

- (LineBufferPosition *)positionForCoordinate:(VT100GridCoord)coord
                                        width:(int)width
                                       offset:(int)offset
{
    int x = coord.x;
    int y = coord.y;
    long long absolutePosition = droppedChars;

    int line = y;
    int i;
    for (i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex: i];
        NSAssert(block, @"Null block");

        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines <= line) {
            line -= block_lines;
            absolutePosition += [block rawSpaceUsed];
            continue;
        }

        int pos;
        int yOffset = 0;
        BOOL extends = NO;
        pos = [block getPositionOfLine:&line
                                   atX:x
                             withWidth:width
                               yOffset:&yOffset
                               extends:&extends];
        if (pos >= 0) {
            absolutePosition += pos + offset;
            LineBufferPosition *result = [LineBufferPosition position];
            result.absolutePosition = absolutePosition;
            result.yOffset = yOffset;
            result.extendsToEndOfLine = extends;

            // Make sure position is valid (might not be because of offset).
            BOOL ok;
            [self coordinateForPosition:result width:width ok:&ok];
            if (ok) {
                return result;
            } else {
                return nil;
            }
        }
    }
    return nil;
}

- (VT100GridCoord)coordinateForPosition:(LineBufferPosition *)position
                                  width:(int)width
                                     ok:(BOOL *)ok
{
    if (position.absolutePosition == [self lastPos] + droppedChars) {
        VT100GridCoord result;
        // If the absolute position is equal to the last position, then
        // numLinesWithWidth: will give the wrapped line number after all
        // trailing empty lines. They all have the same position because they
        // are empty. We need to back up by the number of empty lines and then
        // use position.yOffset to disambiguate.
        result.y = [self numLinesWithWidth:width] - 1 - [blocks.lastObject numberOfTrailingEmptyLines];
        ScreenCharArray *lastLine = [self wrappedLineAtIndex:result.y
                                                       width:width
                                                continuation:NULL];
        result.x = lastLine.length;
        if (position.yOffset > 0) {
            result.x = 0;
            result.y += position.yOffset;
        } else {
            result.x = lastLine.length;
        }
        if (position.extendsToEndOfLine) {
            result.x = width - 1;
        }
        if (ok) {
            *ok = YES;
        }
        return result;
    }
    int i;
    int yoffset = 0;
    int p = position.absolutePosition - droppedChars;
    for (i = 0; p >= 0 && i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        int used = [block rawSpaceUsed];
        if (p >= used) {
            p -= used;
            yoffset += [block getNumLinesWithWrapWidth:width];
        } else {
            int y;
            int x;
            BOOL positionIsValid = [block convertPosition:p
                                                withWidth:width
                                                      toX:&x
                                                      toY:&y];
            if (ok) {
                *ok = positionIsValid;
            }
            if (position.yOffset > 0) {
                x = 0;
                y += position.yOffset;
            }
            if (position.extendsToEndOfLine) {
                x = width - 1;
            }
            return VT100GridCoordMake(x, y + yoffset);
        }
    }
    if (ok) {
        *ok = NO;
    }
    return VT100GridCoordMake(0, 0);
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

- (LineBufferPosition *)firstPosition {
    LineBufferPosition *position = [LineBufferPosition position];
    position.absolutePosition = droppedChars;
    return position;
}

- (LineBufferPosition *)lastPosition {
    LineBufferPosition *position = [LineBufferPosition position];

    position.absolutePosition = droppedChars;
    for (int i = 0; i < [blocks count]; ++i) {
        LineBlock* block = [blocks objectAtIndex:i];
        position.absolutePosition = position.absolutePosition + [block rawSpaceUsed];
    }

    return position;
}

- (long long)absPositionOfFindContext:(FindContext *)findContext
{
    long long offset = droppedChars + findContext.offset;
    int numBlocks = findContext.absBlockNum - num_dropped_blocks;
    for (LineBlock *block in blocks) {
        if (!numBlocks) {
            break;
        }
        --numBlocks;
        offset += [block rawSpaceUsed];
    }
    return offset;
}

- (int)positionForAbsPosition:(long long)absPosition
{
    absPosition -= droppedChars;
    if (absPosition < 0) {
        return [[blocks objectAtIndex:0] startOffset];
    }
    if (absPosition > INT_MAX) {
        absPosition = INT_MAX;
    }
    return (int)absPosition;
}

- (long long)absPositionForPosition:(int)pos
{
    long long absPos = pos;
    return absPos + droppedChars;
}

- (int)absBlockNumberOfAbsPos:(long long)absPos
{
    int absBlock = num_dropped_blocks;
    long long cumPos = droppedChars;
    for (LineBlock *block in blocks) {
        cumPos += [block rawSpaceUsed];
        if (cumPos >= absPos) {
            return absBlock;
        }
        ++absBlock;
    }
    return absBlock;
}

- (long long)absPositionOfAbsBlock:(int)absBlockNum
{
    long long cumPos = droppedChars;
    for (int i = 0; i < blocks.count && i + num_dropped_blocks < absBlockNum; i++) {
        cumPos += [[blocks objectAtIndex:i] rawSpaceUsed];
    }
    return cumPos;
}

- (void)storeLocationOfAbsPos:(long long)absPos
                    inContext:(FindContext *)context
{
    context.absBlockNum = [self absBlockNumberOfAbsPos:absPos];
    long long absOffset = [self absPositionOfAbsBlock:context.absBlockNum];
    context.offset = MAX(0, absPos - absOffset);
}

- (LineBuffer *)newAppendOnlyCopy {
    LineBuffer *theCopy = [[LineBuffer alloc] init];
    [theCopy->blocks release];
    theCopy->blocks = [[NSMutableArray alloc] initWithArray:blocks];
    LineBlock *lastBlock = [blocks lastObject];
    if (lastBlock) {
        [theCopy->blocks removeLastObject];
        [theCopy->blocks addObject:[[lastBlock copy] autorelease]];
    }
    theCopy->block_size = block_size;
    theCopy->cursor_x = cursor_x;
    theCopy->cursor_rawline = cursor_rawline;
    theCopy->max_lines = max_lines;
    theCopy->num_dropped_blocks = num_dropped_blocks;
    theCopy->num_wrapped_lines_cache = num_wrapped_lines_cache;
    theCopy->num_wrapped_lines_width = num_wrapped_lines_width;
    theCopy->droppedChars = droppedChars;
    theCopy.mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;

    return theCopy;
}

- (int)numberOfDroppedBlocks {
    return num_dropped_blocks;
}

- (int)largestAbsoluteBlockNumber {
    return blocks.count + num_dropped_blocks;
}

- (NSArray *)codedBlocks:(BOOL *)truncated {
    *truncated = NO;
    NSMutableArray *codedBlocks = [NSMutableArray array];
    int numLines = 0;
    for (LineBlock *block in [blocks reverseObjectEnumerator]) {
        [codedBlocks insertObject:[block dictionary] atIndex:0];

        // This caps the amount of data at a reasonable but arbitrary size.
        numLines += [block getNumLinesWithWrapWidth:80];
        if (numLines >= 10000) {
            *truncated = YES;
            break;
        }
    }
    return codedBlocks;
}

- (NSDictionary *)dictionary {
    BOOL truncated;
    NSArray *codedBlocks = [self codedBlocks:&truncated];
    return @{ kLineBufferVersionKey: @(kLineBufferVersion),
              kLineBufferBlocksKey: codedBlocks,
              kLineBufferTruncatedKey: @(truncated),
              kLineBufferBlockSizeKey: @(block_size),
              kLineBufferCursorXKey: @(cursor_x),
              kLineBufferCursorRawlineKey: @(cursor_rawline),
              kLineBufferMaxLinesKey: @(max_lines),
              kLineBufferNumDroppedBlocksKey: @(num_dropped_blocks),
              kLineBufferDroppedCharsKey: @(droppedChars),
              kLineBufferMayHaveDWCKey: @(_mayHaveDoubleWidthCharacter) };
}

- (void)appendMessage:(NSString *)message {
    if (!blocks.count) {
        [self _addBlockOfSize:message.length];
    }
    screen_char_t defaultBg = { 0 };
    screen_char_t buffer[message.length];
    int len;
    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };
    fg.foregroundColor = ALTSEM_REVERSED_DEFAULT;
    fg.backgroundColorMode = ColorModeAlternate;
    bg.backgroundColor = ALTSEM_REVERSED_DEFAULT;
    bg.backgroundColorMode = ColorModeAlternate;
    StringToScreenChars(message, buffer, fg, bg, &len, NO, NULL, NULL, NO);
    [self appendLine:buffer
              length:0
             partial:NO
               width:num_wrapped_lines_width > 0 ?: 80
           timestamp:[NSDate timeIntervalSinceReferenceDate]
        continuation:defaultBg];

    [self appendLine:buffer
              length:len
             partial:NO
               width:num_wrapped_lines_width > 0 ?: 80
           timestamp:[NSDate timeIntervalSinceReferenceDate]
        continuation:bg];

    [self appendLine:buffer
              length:0
             partial:NO
               width:num_wrapped_lines_width > 0 ?: 80
           timestamp:[NSDate timeIntervalSinceReferenceDate]
        continuation:defaultBg];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    LineBuffer *theCopy = [[LineBuffer alloc] initWithBlockSize:block_size];

    for (LineBlock *block in blocks) {
        [theCopy->blocks addObject:block];
    }
    theCopy->cursor_x = cursor_x;
    theCopy->cursor_rawline = cursor_rawline;
    theCopy->max_lines = max_lines;
    theCopy->num_dropped_blocks = num_dropped_blocks;
    theCopy->num_wrapped_lines_cache = num_wrapped_lines_cache;
    theCopy->num_wrapped_lines_width = num_wrapped_lines_width;
    theCopy->droppedChars = droppedChars;

    return theCopy;
}

- (int)numBlocksAtEndToGetMinimumLines:(int)minLines width:(int)width {
    int numBlocks = 0;
    int lines = 0;
    for (LineBlock *block in blocks.reverseObjectEnumerator) {
        lines += [block getNumLinesWithWrapWidth:width];
        ++numBlocks;
        if (lines > minLines) {
            break;
        }
    }
    return numBlocks;
}

- (long long)numCharsInRangeOfBlocks:(NSRange)range {
    long long n = 0;
    for (int i = 0; i < range.length; i++) {
        NSUInteger j = range.location + i;
        n += [blocks[j] numberOfCharacters];
    }
    return n;
}

- (LineBuffer *)appendOnlyCopyWithMinimumLines:(int)minLines atWidth:(int)width {
    // Calculate how many blocks to keep.
    const int numBlocks = [self numBlocksAtEndToGetMinimumLines:minLines width:width];
    const int totalBlocks = blocks.count;
    const int numDroppedBlocks = totalBlocks - numBlocks;

    // Make a copy of the whole thing (cheap)
    LineBuffer *theCopy = [[self newAppendOnlyCopy] autorelease];

    // Remove the blocks we don't need.
    [theCopy->blocks removeObjectsInRange:NSMakeRange(0, numDroppedBlocks)];

    // Update stats and nuke cache.
    theCopy->num_dropped_blocks += numDroppedBlocks;
    theCopy->num_wrapped_lines_width = -1;
    theCopy->droppedChars += [self numCharsInRangeOfBlocks:NSMakeRange(0, numDroppedBlocks)];

    return theCopy;
}

@end
