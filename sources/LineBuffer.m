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
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermLineBlockArray.h"
#import "iTermMalloc.h"
#import "iTermOrderedDictionary.h"
#import "LineBlock.h"
#import "LineBufferSorting.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSSet+iTerm.h"
#import "RegexKitLite.h"
#import <stdatomic.h>
#import <time.h>

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
static NSString *const kLineBufferBlockWrapperKey = @"Block Wrapper";

static const int kLineBufferVersion = 1;
static const NSInteger kUnicodeVersion = 9;

#pragma mark - Deterministic Perf Counters

static BOOL gLineBufferPerfCountersEnabled = NO;

static atomic_bool gLineBufferPerfRegistered = false;
static atomic_ullong gLineBufferAppendLinesCalls = 0;
static atomic_ullong gLineBufferAppendLinesNanos = 0;
static atomic_ullong gLineBufferAppendLinesItems = 0;
static atomic_ullong gLineBufferAppendLinesBulkInitCalls = 0;
static atomic_ullong gLineBufferAppendLinesBulkInitItems = 0;
static atomic_ullong gLineBufferAppendLinesLoopAppends = 0;
static atomic_ullong gLineBufferAppendLinesDWCDisabledCalls = 0;
static atomic_ullong gLineBufferReallyAppendLineCalls = 0;
static atomic_ullong gLineBufferReallyAppendLineNanos = 0;
static atomic_ullong gLineBufferMetadataPropagateCalls = 0;
static atomic_ullong gLineBufferMetadataPropagateIters = 0;
static atomic_ullong gLineBufferMetadataPropagateNanos = 0;

static inline uint64_t iTermPerfNowNanos(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static void iTermLineBufferPerfDump(void) {
    NSLog(@"ITERM_PERF_LINEBUFFER calls_appendLines=%llu ns_appendLines=%llu items_appendLines=%llu "
          @"bulkInit_calls=%llu bulkInit_items=%llu loopAppends=%llu dwcDisabled_calls=%llu "
          @"calls_reallyAppendLine=%llu ns_reallyAppendLine=%llu "
          @"metadataPropagate_calls=%llu metadataPropagate_iters=%llu ns_metadataPropagate=%llu",
          (unsigned long long)atomic_load(&gLineBufferAppendLinesCalls),
          (unsigned long long)atomic_load(&gLineBufferAppendLinesNanos),
          (unsigned long long)atomic_load(&gLineBufferAppendLinesItems),
          (unsigned long long)atomic_load(&gLineBufferAppendLinesBulkInitCalls),
          (unsigned long long)atomic_load(&gLineBufferAppendLinesBulkInitItems),
          (unsigned long long)atomic_load(&gLineBufferAppendLinesLoopAppends),
          (unsigned long long)atomic_load(&gLineBufferAppendLinesDWCDisabledCalls),
          (unsigned long long)atomic_load(&gLineBufferReallyAppendLineCalls),
          (unsigned long long)atomic_load(&gLineBufferReallyAppendLineNanos),
          (unsigned long long)atomic_load(&gLineBufferMetadataPropagateCalls),
          (unsigned long long)atomic_load(&gLineBufferMetadataPropagateIters),
          (unsigned long long)atomic_load(&gLineBufferMetadataPropagateNanos));
}

static inline void iTermLineBufferPerfRegisterIfNeeded(void) {
    bool expected = false;
    if (atomic_compare_exchange_strong(&gLineBufferPerfRegistered, &expected, true)) {
        atexit(iTermLineBufferPerfDump);
    }
}

#pragma mark - Inline Helpers

// Ensures 0 <= x < width by carrying overflow/underflow into y.
static inline VT100GridCoord LineBufferNormalizeWrappedCoord(int x, int y, int width) {
    if (x < 0) {
        // E.g. x=-5, width=10 → x=5, y-=1
        int borrow = (-x + width - 1) / width;  // ceil(-x / width)
        y -= borrow;
        x += borrow * width;
    } else if (x >= width) {
        y += x / width;
        x %= width;
    }
    return VT100GridCoordMake(x, y);
}

// Result of fetching a wrapped line with full metadata.
typedef struct {
    const screen_char_t *chars;
    int length;
    int eol;
    screen_char_t continuation;
    iTermImmutableMetadata metadata;
} iTermWrappedLineResult;

// Contributed-line bookkeeping for a single block.
// naive:       raw wrapped line count from getNumLinesWithWrapWidth:
// adjustment:  continuation adjustment (negative = hidden head lines)
// hidden:      number of hidden head lines (MAX(0, -adjustment))
// contributed: visible wrapped lines (naive + adjustment)
typedef struct {
    int naive;
    int adjustment;
    int hidden;
    int contributed;
} iTermBlockLineInfo;

NS_INLINE iTermBlockLineInfo iTermBlockContributedLines(LineBlock *block, int width) {
    int naive = [block getNumLinesWithWrapWidth:width];
    int adj = block.startsWithContinuation
        ? [block continuationWrappedLineAdjustmentForWidth:width]
        : 0;
    int hidden = MAX(0, -adj);
    int contributed = naive + adj;
    return (iTermBlockLineInfo){ naive, adj, hidden, contributed };
}

NS_INLINE int iTermSumWrappedLineLengths(LineBlock *block,
                                         int width,
                                         int startLocalWrappedLine,
                                         int count) {
    int sum = 0;
    for (int i = 0; i < count; i++) {
        int lineNum = startLocalWrappedLine + i;
        int lineLength = 0;
        int eol = EOL_SOFT;
        const screen_char_t *chars = [block getWrappedLineWithWrapWidth:width
                                                                 lineNum:&lineNum
                                                              lineLength:&lineLength
                                                       includesEndOfLine:&eol
                                                            continuation:NULL];
        if (!chars) {
            break;
        }
        sum += lineLength;
    }
    return sum;
}

// The way in which LineBuffer objects are shared is kinda complicated. Each LineBuffer is meant
// to be used by one dispatch queue. Each LineBuffer has its own private LineBlockArray. Each
// LineBlockArray has its own unique LineBlock objects. LineBlocks have pointers to CharacterBuffer
// objects, which *are* shared across dispatch queues. This is done to avoid copying big chunks of
// memory when making a copy. LineBlocks use a copy-on-write scheme for CharacterBuffers. Here is
// an object graph where the second block was modified in one of the line buffers after copying.
//
// [LineBuffer]               .----[clients: [Index 0]]------------.          [LineBuffer]
//      |                    |                                     |               |
//      V                    |    .----------owner---------------, |               V
// [LineBlockArray]          |    V                              | V          [LineBlockArray]
// [Index 0       ] --> [LineBlock] --> [CharacterBuffer] <-- [LineBlock] <-- [Index 0       ]
// [Index 1       ] --> [LineBlock]                           [LineBlock] <-- [Index 1       ]
//                           |                                     |
//                           V                                     V
//                    [CharacterBuffer]                     [CharacterBuffer]
//

@interface LineBuffer()<iTermLineBlockArrayDelegate>
@end

@implementation LineBuffer {
    // An array of LineBlock*s.
    iTermLineBlockArray *_lineBlocks;

    // The default storage for a LineBlock (some may be larger to accommodate very long lines).
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

    BOOL _wantsSeal;
    int _deferSanityCheck;
    atomic_llong _generation;
}

@synthesize mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
@synthesize delegate = _delegate;

- (void)commitLastBlock {
    if (_maintainBidiInfo) {
        [_lineBlocks.lastBlock reloadBidiInfo];
    }
}

// Append a block
- (LineBlock *)_addBlockOfSize:(int)size {
    self.dirty = YES;
    // Immediately shrink it so that it can compress down to the smallest
    // possible size. The compression code has no way of knowing how big these
    // buffers are.
    [_lineBlocks.lastBlock shrinkToFit];
    [self commitLastBlock];
    return [_lineBlocks addBlockOfSize:size
                                number:self.nextBlockNumber
           mayHaveDoubleWidthCharacter:self.mayHaveDoubleWidthCharacter];
}

- (long long)nextBlockNumber {
    return num_dropped_blocks + _lineBlocks.count;
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
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gLineBufferPerfCountersEnabled = [iTermAdvancedSettingsModel lineBufferPerfCounters];
    });
    _lineBlocks = [[iTermLineBlockArray alloc] init];
#if DEBUG
    _lineBlocks.delegate = self;
#endif
    max_lines = -1;
    num_wrapped_lines_width = -1;
    num_dropped_blocks = 0;
}

// The designated initializer. We prefer not to expose the notion of block sizes to
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

- (LineBuffer *)initWithDictionary:(NSDictionary *)dictionary
                  maintainBidiInfo:(BOOL)maintainBidiInfo {
    self = [super init];
    if (self) {
        [self commonInit];
        _maintainBidiInfo = maintainBidiInfo;
        if ([dictionary[kLineBufferVersionKey] intValue] != kLineBufferVersion) {
            return [[LineBuffer alloc] init];
        }
        _mayHaveDoubleWidthCharacter = [dictionary[kLineBufferMayHaveDWCKey] boolValue];
        block_size = [dictionary[kLineBufferBlockSizeKey] intValue];
        cursor_x = [dictionary[kLineBufferCursorXKey] intValue];
        cursor_rawline = [dictionary[kLineBufferCursorRawlineKey] intValue];
        max_lines = [dictionary[kLineBufferMaxLinesKey] intValue];
        num_dropped_blocks = [dictionary[kLineBufferNumDroppedBlocksKey] intValue];
        droppedChars = [dictionary[kLineBufferDroppedCharsKey] longLongValue];
        for (NSDictionary *maybeWrapper in dictionary[kLineBufferBlocksKey]) {
            NSDictionary *blockDictionary = maybeWrapper;
            if (maybeWrapper[kLineBufferBlockWrapperKey]) {
                blockDictionary = maybeWrapper[kLineBufferBlockWrapperKey];
            }
            LineBlock *block = [LineBlock blockWithDictionary:blockDictionary
                                          absoluteBlockNumber:num_dropped_blocks + _lineBlocks.count];
            if (!block) {
                return [[LineBuffer alloc] init];
            }
            if (_maintainBidiInfo && maybeWrapper == [dictionary[kLineBufferBlocksKey] lastObject]) {
                // Reset status in the last (non-committed) block to force bidi info to be recomputed
                // prior to display.
                [block eraseRTLStatusInAllCharacters];
            }
            [_lineBlocks addBlock:block];
            // We do not call commitLastBlock because the block can restore all of its state.
        }
    }
    return self;
}

// Sanity check that the cached number of wrapped lines is correct.
- (void)sanityCheck {
#if DEBUG
    if (_deferSanityCheck) {
        return;
    }
    int width = num_wrapped_lines_width;
    if (width == -1) {
        return;
    }
    int count = [_lineBlocks numberOfWrappedLinesForWidth:width];
    if (count != num_wrapped_lines_cache) {
        [_lineBlocks numberOfWrappedLinesForWidth:width];
         ITAssertWithMessage(count == num_wrapped_lines_cache, @"Cached number of wrapped lines is incorrect");
    }
    [self assertUniqueBlockIDs];

    // No empty interior blocks
    for (int i = 1; i + 1 < _lineBlocks.count; i++) {
        LineBlock *block = _lineBlocks[i];
        assert(!block.isEmpty);
    }

    // Continuation invariants
    for (int i = 0; i < _lineBlocks.count; i++) {
        LineBlock *block = _lineBlocks[i];
        if (block.startsWithContinuation) {
            ITAssertWithMessage(i > 0, @"First block cannot start with continuation");
            LineBlock *prevBlock = _lineBlocks[i - 1];
            ITAssertWithMessage(prevBlock.hasPartial,
                                @"Block %d starts with continuation but previous block is not partial",
                                i);
        }
    }
#endif
}

#if DEBUG
- (void)assertUniqueBlockIDs {
    NSMutableSet<NSString *> *uniqueIDs = [NSMutableSet set];
    for (LineBlock *block in _lineBlocks.blocks) {
        BOOL dup = [uniqueIDs containsObject:block.stringUniqueIdentifier];
        assert(!dup);
        [uniqueIDs addObject:block.stringUniqueIdentifier];
    }
}
#endif

- (void)setMayHaveDoubleWidthCharacter:(BOOL)mayHaveDoubleWidthCharacter {
    if (!_mayHaveDoubleWidthCharacter) {
        _mayHaveDoubleWidthCharacter = mayHaveDoubleWidthCharacter;
        [_lineBlocks setAllBlocksMayHaveDoubleWidthCharacters];
    }
}

// This is called a lot so it's a C function to avoid obj_msgSend
static int RawNumLines(LineBuffer* buffer, int width) {
    if (buffer->num_wrapped_lines_width == width) {
        return buffer->num_wrapped_lines_cache;
    }

    int count;
    count = [buffer->_lineBlocks numberOfWrappedLinesForWidth:width];

    buffer->num_wrapped_lines_width = width;
    buffer->num_wrapped_lines_cache = count;
    return count;
}


- (int)maxLines {
    return max_lines;
}

- (void)setDirty:(BOOL)dirty {
    if (dirty == _dirty) {
        return;
    }
    if (dirty) {
        atomic_fetch_add(&_generation, 1);
    }
    _dirty = dirty;
}

- (long long)generation {
    return atomic_load(&_generation);
}

- (void)setMaxLines:(int)maxLines {
    self.dirty = YES;
    max_lines = maxLines;
    num_wrapped_lines_width = -1;
}


- (void)clear {
    const int saved = max_lines;
    [self setMaxLines:0];
    [self dropExcessLinesWithWidth:num_wrapped_lines_width > 0 ? num_wrapped_lines_width : 80];
    [self setMaxLines:saved];
}

- (int)dropExcessLinesWithWidth:(int)width {
    _deferSanityCheck++;
    const int result = [self reallyDropExcessLinesWithWidth:width];
    _deferSanityCheck--;
    [self sanityCheck];
    return result;
}

- (int)reallyDropExcessLinesWithWidth:(int)width {
    self.dirty = YES;
    int nl = RawNumLines(self, width);
    int totalDropped = 0;
    int totalRawLinesDropped = 0;
#if DEBUG
    [self assertUniqueBlockIDs];
    [self sanityCheck];
#endif
    NSMutableArray<LineBlock *> *blocksToDealloc = [NSMutableArray array];
    if (max_lines != -1 && nl > max_lines) {
        LineBlock *block = _lineBlocks[0];
        int total_lines = nl;
        while (total_lines > max_lines) {
            const int extra_lines = total_lines - max_lines;
            const int block_lines = [block getNumLinesWithWrapWidth:width];
#if ITERM_DEBUG
            ITAssertWithMessage(block_lines > 0, @"Empty leading block");
#endif
            if (extra_lines >= block_lines) {
                // Drop the entire block.
                int rawLinesInBlock = block.numRawLines;
                // If the successor is a continuation of this block, its first
                // raw line is logically part of this block's last raw line.
                // removeFirstBlock will clear the continuation, restoring that
                // raw line as standalone. So the net raw lines removed from the
                // logical view is numRawLines - 1, not numRawLines.
                const BOOL successorContinues = (_lineBlocks.count > 1 &&
                                                 _lineBlocks[1].startsWithContinuation);
                int successorAdjustment = 0;
                if (successorContinues) {
                    rawLinesInBlock -= 1;
                    // removeFirstBlock will clear the successor's continuation,
                    // changing its wrapped count from (naive + adjustment) to
                    // naive. Adjust total_lines to compensate, since it was
                    // computed using the contributed (adjusted) count.
                    successorAdjustment = [_lineBlocks[1] continuationWrappedLineAdjustmentForWidth:width];
                }
                totalRawLinesDropped += rawLinesInBlock;
                droppedChars += block.nonDroppedSpaceUsed;
                [blocksToDealloc addObject:block];
                [_lineBlocks removeFirstBlock];
                num_dropped_blocks += 1;
                if (_lineBlocks.count > 0) {
                    block = _lineBlocks[0];
                }
                total_lines -= block_lines;
                totalDropped += block_lines;
                // Compensate for the successor's wrapped count change.
                // adjustment is typically negative, so subtracting it
                // increases total_lines (and decreases totalDropped) to
                // reflect that the successor "gained back" lines when its
                // continuation was cleared.
                total_lines -= successorAdjustment;
                totalDropped += successorAdjustment;
#if DEBUG
                num_wrapped_lines_cache = total_lines;
                [self assertUniqueBlockIDs];
                [self sanityCheck];
                if (total_lines > max_lines) {
                    ITAssertWithMessage([block getNumLinesWithWrapWidth:width] > 0, @"Empty leading block");
                }
#endif
            } else {
                int charsDropped;
                const int numRawLinesBefore = block.numRawLines;
                int dropped = [block dropLines:extra_lines withWidth:width chars:&charsDropped];
#if DEBUG
                [self assertUniqueBlockIDs];
                [self sanityCheck];
#endif
                totalDropped += dropped;
                const int numRawLinesAfter = block.numRawLines;
                assert(numRawLinesAfter <= numRawLinesBefore);
                totalRawLinesDropped += (numRawLinesBefore - numRawLinesAfter);
                droppedChars += charsDropped;
                const BOOL blockIsEmpty = block.isEmpty;
                if (blockIsEmpty) {
                    [_lineBlocks removeFirstBlock];
                    ++num_dropped_blocks;
                    [blocksToDealloc addObject:block];
                    if (_lineBlocks.count > 0) {
                        block = _lineBlocks[0];
                    }
#if DEBUG
                    [self assertUniqueBlockIDs];
                    [self sanityCheck];
#endif
                }
                total_lines -= dropped;
#if DEBUG
                if (total_lines > max_lines) {
                    ITAssertWithMessage([block getNumLinesWithWrapWidth:width] > 0, @"Empty leading block");
                }
#endif
            }
        }
        num_wrapped_lines_cache = total_lines;
    }
    if (blocksToDealloc.count) {
        dispatch_async(gDeallocQueue, ^{
            // LineBlock's dealloc is surprsingly slow considering how little it does, taking over
            // 1% of total time in a benchmark of printing a large ascii file.
            [blocksToDealloc removeAllObjects];
        });
    }
#if DEBUG
    [self assertUniqueBlockIDs];
#endif
    cursor_rawline -= totalRawLinesDropped;
    [_delegate lineBufferDidDropLines:self];
#if DEBUG
    [self assertUniqueBlockIDs];
#endif
    assert(totalRawLinesDropped >= 0);
    return totalDropped;
}

- (NSString *)debugString {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < _lineBlocks.count; i++) {
        LineBlock *block = _lineBlocks[i];
        [block appendToDebugString:s];
    }
    return [s length] ? [s substringToIndex:s.length - 1] : @"";  // strip trailing newline
}

- (void)dump {
    int i;
    int rawOffset = 0;
    for (i = 0; i < _lineBlocks.count; ++i) {
        NSLog(@"\n-- BEGIN BLOCK %d --\n", i);
        [_lineBlocks[i] dump:rawOffset droppedChars:droppedChars toDebugLog:NO];
        rawOffset += [_lineBlocks[i] rawSpaceUsed];
    }
}
- (NSString *)dumpString {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    int i;
    long long pos = droppedChars;
    for (i = 0; i < _lineBlocks.count; ++i) {
        [strings addObject:@""];
        const int rawSpaceUsed = [_lineBlocks[i] rawSpaceUsed];
        [strings addObject:[NSString stringWithFormat:@"-- BEGIN BLOCK %d (abs block number %d, abs-position %@, raw size %@) --",
                            i,
                            i + num_dropped_blocks,
                            @(pos),
                            @(rawSpaceUsed)]];
        [strings addObject:[_lineBlocks[i] dumpStringWithDroppedChars:pos]];
        pos += rawSpaceUsed;
    }
    return [strings componentsJoinedByString:@"\n"];
}

- (NSString *)compactLineDumpWithWidth:(int)width andContinuationMarks:(BOOL)continuationMarks {
    NSMutableString *s = [NSMutableString string];
    int n = [self numLinesWithWidth:width];
    for (int i = 0; i < n; i++) {
        screen_char_t continuation;
        ScreenCharArray *line = [self wrappedLineAtIndex:i width:width continuation:&continuation];
        if (!line) {
            [s appendFormat:@"(nil)"];
            continue;
        }
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

- (NSString *)compactLineDumpWithBlockDelimitersAndWidth:(int)width andContinuationMarks:(BOOL)continuationMarks {
    NSMutableString *s = [NSMutableString string];
    int n = [self numLinesWithWidth:width];
    LineBlock *block = nil;
    LineBlock *lastBlock = nil;
    for (int i = 0; i < n; i++) {
        screen_char_t continuation;
        int remainder = 0;
        block = [_lineBlocks blockContainingLineNumber:i width:width remainder:&remainder];
        if (block != lastBlock) {
            [s appendFormat:@"\n-- Begin block %@ --\n", @(block.absoluteBlockNumber)];
            lastBlock = block;
        }
        ScreenCharArray *line = [self wrappedLineAtIndex:i width:width continuation:&continuation];
        if (!line) {
            [s appendFormat:@"(nil)"];
            continue;
        }
        [s appendFormat:@"%9d: %@", i, ScreenCharArrayToStringDebug(line.line, line.length)];
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

- (void)dumpLinesWithWidth:(int)width {
    NSMutableString *s = [NSMutableString string];
    int n = [self numLinesWithWidth:width];
    int k = 0;
    for (int i = 0; i < n; i++) {
        screen_char_t continuation;
        ScreenCharArray *line = [self wrappedLineAtIndex:i width:width continuation:&continuation];
        [s appendFormat:@"%@", ScreenCharArrayToStringDebug(line.line, line.length)];
        for (int j = line.length; j < width; j++) {
            [s appendString:@"."];
        }
        if (continuation.code == EOL_HARD) {
            [s appendString:@"!"];
        } else if (continuation.code == EOL_SOFT) {
            [s appendString:@"+"];
        } else if (continuation.code == EOL_DWC) {
            [s appendString:@">"];
        } else {
            [s appendString:@"?"];
        }
        if (i < n - 1) {
            NSLog(@"%4d: %@", k++, s);
            s = [NSMutableString string];
        }
    }
    NSLog(@"%4d: %@", k++, s);
}

- (void)dumpWrappedToWidth:(int)width {
    NSLog(@"%@", [self compactLineDumpWithWidth:width andContinuationMarks:NO]);
}

- (void)appendScreenCharArray:(ScreenCharArray *)sca
                        width:(int)width {
    [self appendLine:sca.line
              length:sca.length
             partial:sca.eol != EOL_HARD
               width:width
            metadata:sca.metadata
        continuation:sca.continuation];
}

- (void)appendLine:(const screen_char_t *)buffer
            length:(int)length
           partial:(BOOL)partial
             width:(int)width
          metadata:(iTermImmutableMetadata)metadataObj
      continuation:(screen_char_t)continuation {
    _deferSanityCheck++;
    [self reallyAppendLine:buffer length:length partial:partial width:width metadata:metadataObj continuation:continuation];
    _deferSanityCheck--;
    [self sanityCheck];
}

- (void)setBidiForLastRawLine:(iTermBidiDisplayInfo *)bidi {
    if (!_maintainBidiInfo) {
        return;
    }
    [_lineBlocks.lastBlock setBidiForLastRawLine:bidi];
}

// Returns YES if any item from fromIndex onward contains DWC_RIGHT.
// Invariant: DWC content is always stored with DWC_RIGHT markers by
// StringToScreenChars. If this invariant changes, this scan will need
// to be updated.
static BOOL iTermAppendItemsHaveDWC(CTVector(iTermAppendItem) *items, int fromIndex) {
    const int count = CTVectorCount(items);
    for (int i = fromIndex; i < count; i++) {
        const iTermAppendItem item = CTVectorGet(items, i);
        const screen_char_t *buf = item.buffer;
        const int len = item.length;
        for (int j = 0; j < len; j++) {
            if (buf[j].code == DWC_RIGHT) {
                return YES;
            }
        }
    }
    return NO;
}

- (void)appendLines:(CTVector(iTermAppendItem) *)items width:(int)width {
    const BOOL perfEnabled = gLineBufferPerfCountersEnabled;
    uint64_t appendLinesStart = 0;
    if (perfEnabled) {
        iTermLineBufferPerfRegisterIfNeeded();
        appendLinesStart = iTermPerfNowNanos();
        atomic_fetch_add(&gLineBufferAppendLinesCalls, 1);
        atomic_fetch_add(&gLineBufferAppendLinesItems, CTVectorCount(items));
    }
    self.dirty = YES;
#ifdef LOG_MUTATIONS
    NSLog(@"Append: %@\n", ScreenCharArrayToStringDebug(buffer, length));
#endif
    [self removeTrailingEmptyBlocks];
#if DEBUG
    [self sanityCheck];
#endif
    int first = 0;
    int charsAppendedInLoop = 0;
    // Decide whether DWC in the actual data prevents the bulk path. Only
    // check when the buffer-wide flag is set (sticky from any prior DWC
    // event). This avoids permanently penalizing ASCII streams after a
    // single DWC character appeared somewhere in the buffer's history.
    BOOL bulkPathDisabledByDWC = NO;
    if (_mayHaveDoubleWidthCharacter) {
        if (iTermAppendItemsHaveDWC(items, 0)) {
            bulkPathDisabledByDWC = YES;
        } else {
            // Items are DWC-free. Check the full logical prefix across
            // the continuation chain for DWC.
            LineBlock *lb = _lineBlocks.lastBlock;
            if (lb.hasPartial) {
                if (lb.startsWithContinuation) {
                    bulkPathDisabledByDWC = lb.prefixHasDWC || [lb lastRawLineHasDWC];
                } else {
                    bulkPathDisabledByDWC = [lb lastRawLineHasDWC];
                }
            }
        }
    }
    if (bulkPathDisabledByDWC && perfEnabled) {
        atomic_fetch_add(&gLineBufferAppendLinesDWCDisabledCalls, 1);
    }
    while (first < CTVectorCount(items)) {
        LineBlock *lastBlock = _lineBlocks.lastBlock;
        if (!lastBlock.hasPartial) {
            break;
        }
        iTermAppendItem item = CTVectorGet(items, first);
        if (item.length > 0 || !item.partial) {
            [self appendLine:item.buffer
                      length:item.length
                     partial:item.partial
                       width:width
                    metadata:item.metadata
                continuation:item.continuation];
            charsAppendedInLoop += item.length;
            if (perfEnabled) {
                atomic_fetch_add(&gLineBufferAppendLinesLoopAppends, 1);
            }
#if DEBUG
    [self sanityCheck];
#endif
        }
#if DEBUG
    [self sanityCheck];
#endif
        first += 1;
        // When DWC is present in the logical prefix or items, wrapping is
        // column-based, not character-based. The character-count alignment
        // and continuation adjustment formulas don't work with DWC, so
        // consume all partial items one-at-a-time. This flag is computed
        // once before the loop by scanning the actual data, not the
        // buffer-wide sticky flag, so ASCII streams after a DWC event
        // still use the O(1) bulk path.
        if (bulkPathDisabledByDWC) {
            continue;
        }
        // Switch to the bulk initWithItems: path once the logical partial-line
        // length (the value that becomes continuationPrefixCharacters) aligns
        // to `width`. This ensures the continuation block has
        // continuationPrefixCharacters % width == 0, so no wrapped-line
        // adjustment is needed and wrappedLine(at:) never loses boundary data.
        // Without any break here, all partial items would go one-at-a-time
        // into a single ever-growing block, causing O(n^2) COW clone cost.
        //
        // We check the logical partial-line length (inherited prefix +
        // current partial), not rawSpaceUsed, because prior complete lines in
        // the block don't affect the continuation boundary.
        //
        // If alignment can't be achieved within `width` chars (e.g., when
        // gcd(item_length, width) doesn't divide the offset), stop anyway.
        // The continuation adjustment machinery handles the resulting
        // misalignment correctly.
        if (charsAppendedInLoop >= width) {
            break;
        }
        if (width > 0) {
            lastBlock = _lineBlocks.lastBlock;
            if (lastBlock.hasPartial) {
                const int partialLength = [lastBlock lengthOfLastLine];
                const int logicalPrefix = (lastBlock.startsWithContinuation
                                           ? lastBlock.continuationPrefixCharacters
                                           : 0) + partialLength;
                if (logicalPrefix % width == 0) {
                    break;
                }
            }
        }
    }


    if (first < CTVectorCount(items)) {
        if (perfEnabled) {
            atomic_fetch_add(&gLineBufferAppendLinesBulkInitCalls, 1);
            atomic_fetch_add(&gLineBufferAppendLinesBulkInitItems, CTVectorCount(items) - first);
        }
        [self removeTrailingEmptyBlocks];
#if DEBUG
    [self sanityCheck];
#endif
        int prefixCharacters = -1;
        BOOL prefixHasDWC = NO;
        LineBlock *lastBlock = _lineBlocks.lastBlock;
        if (lastBlock.hasPartial) {
            const int lastRawLineLength = [lastBlock lengthOfLastLine];
            prefixCharacters = (lastBlock.startsWithContinuation
                                ? lastBlock.continuationPrefixCharacters
                                : 0) + lastRawLineLength;
            // Propagate DWC knowledge through the continuation chain.
            if (lastBlock.startsWithContinuation) {
                prefixHasDWC = lastBlock.prefixHasDWC || [lastBlock lastRawLineHasDWC];
            } else {
                prefixHasDWC = [lastBlock lastRawLineHasDWC];
            }
        }
        LineBlock *block = [[LineBlock alloc] initWithItems:items
                                                  fromIndex:first
                                                      width:width
                                        absoluteBlockNumber:self.nextBlockNumber
                                  continuationPrefixCharacters:prefixCharacters
                                               prefixHasDWC:prefixHasDWC];
        if (!block.isEmpty) {
#if DEBUG
            [self sanityCheck];
            assert(!block.isEmpty);
#endif
            if (num_wrapped_lines_width == width) {
                int lines = [block getNumLinesWithWrapWidth:width];
                if (block.startsWithContinuation) {
                    lines += [block continuationWrappedLineAdjustmentForWidth:width];
                }
                num_wrapped_lines_cache += lines;
            } else {
                // Width change. Invalidate the wrapped lines cache.
                num_wrapped_lines_width = -1;
            }
            [_lineBlocks addBlock:block];
#if DEBUG
            [self sanityCheck];
            assert(!block.isEmpty);
#endif
        }
    }

    if (_wantsSeal) {
        _wantsSeal = NO;
        [self ensureLastBlockUncopied];
    }
    [self sanityCheck];
    if (perfEnabled) {
        atomic_fetch_add(&gLineBufferAppendLinesNanos, iTermPerfNowNanos() - appendLinesStart);
    }
}

- (void)reallyAppendLine:(const screen_char_t *)buffer
                  length:(int)length
                 partial:(BOOL)partial
                   width:(int)width
                metadata:(iTermImmutableMetadata)metadataObj
            continuation:(screen_char_t)continuation {
    const BOOL perfEnabled = gLineBufferPerfCountersEnabled;
    uint64_t reallyAppendStart = 0;
    if (perfEnabled) {
        reallyAppendStart = iTermPerfNowNanos();
        atomic_fetch_add(&gLineBufferReallyAppendLineCalls, 1);
    }
    self.dirty = YES;
#ifdef LOG_MUTATIONS
    NSLog(@"Append: %@\n", ScreenCharArrayToStringDebug(buffer, length));
#endif
    if (_lineBlocks.count == 0) {
        [self _addBlockOfSize:block_size];
    }

    LineBlock *block = _lineBlocks.lastBlock;
    const BOOL wasPartialContinuation = (block.hasPartial &&
                                          block.startsWithContinuation &&
                                          [block numRawLines] == 1);

    int beforeLines = [block getNumLinesWithWrapWidth:width];
    if (![block appendLine:buffer
                    length:length
                   partial:partial
                     width:width
                  metadata:metadataObj
              continuation:continuation]) {
        // It's going to be complicated. Invalidate the number of wrapped lines
        // cache.
        num_wrapped_lines_width = -1;
        int prefix_len = 0;
        iTermImmutableMetadata prefixMetadata = iTermMetadataMakeImmutable(iTermMetadataDefault());
        screen_char_t* prefix = NULL;
        if ([block hasPartial]) {
            // There is a line that's too long for the current block to hold.
            // Remove its prefix from the current block and later add the
            // concatenation of prefix + buffer to a larger block.
            const screen_char_t *temp;
            BOOL ok = [block popLastLineInto:&temp
                                  withLength:&prefix_len
                                   upToWidth:[block rawBufferSize] + 1
                                    metadata:&prefixMetadata
                                continuation:NULL];
            assert(ok);
            prefix = (screen_char_t*)iTermMalloc(MAX(1, prefix_len) * sizeof(screen_char_t));
            memcpy(prefix, temp, prefix_len * sizeof(screen_char_t));
            ITAssertWithMessage(ok, @"hasPartial but pop failed.");
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
                block = [self _addBlockOfSize:length + prefix_len];
            } else {
                block = [self _addBlockOfSize:block_size];
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
                     metadata:prefixMetadata
                 continuation:continuation];
            ITAssertWithMessage(ok, @"append can't fail here");
            free(prefix);
        }
        // Finally, append this line to the new block. We know it'll fit because we made
        // enough room for it.
        BOOL ok __attribute__((unused)) =
        [block appendLine:buffer
                   length:length
                  partial:partial
                    width:width
                 metadata:metadataObj
             continuation:continuation];
        ITAssertWithMessage(ok, @"append can't fail here");
    } else if (num_wrapped_lines_width == width) {
        // Straightforward addition of a line to an existing block. Update the
        // wrapped lines cache.
        int afterLines = [block getNumLinesWithWrapWidth:width];
        num_wrapped_lines_cache += (afterLines - beforeLines);
    } else {
        // Width change. Invalidate the wrapped lines cache.
        num_wrapped_lines_width = -1;
    }

    // Disabled for throughput investigation: this backward walk is O(chain length)
    // on every append and can dominate bulk throughput.
    (void)wasPartialContinuation;
    (void)metadataObj;
    (void)length;

    if (_wantsSeal) {
        _wantsSeal = NO;
        [self ensureLastBlockUncopied];
    }
    if (perfEnabled) {
        atomic_fetch_add(&gLineBufferReallyAppendLineNanos, iTermPerfNowNanos() - reallyAppendStart);
    }
}

- (iTermImmutableMetadata)metadataByProjectingContinuationForBlock:(LineBlock *)block
                                                         blockIndex:(NSInteger)blockIndex
                                                   localWrappedLine:(int)localWrappedLine
                                                              width:(int)width
                                                           fallback:(iTermImmutableMetadata)fallback {
    if (!block || width <= 0 || blockIndex < 0) {
        return fallback;
    }
    const NSArray<LineBlock *> *blocks = _lineBlocks.blocks;
    if (blockIndex >= (NSInteger)blocks.count) {
        return fallback;
    }

    const NSInteger nextIndex = blockIndex + 1;
    if (nextIndex >= (NSInteger)blocks.count) {
        return fallback;
    }
    LineBlock *nextBlock = blocks[nextIndex];
    if (!nextBlock.startsWithContinuation) {
        return fallback;
    }

    NSNumber *rawLineNumber = [block rawLineNumberAtWrappedLineOffset:localWrappedLine width:width];
    if (!rawLineNumber) {
        return fallback;
    }
    if (rawLineNumber.intValue != [block numRawLines] - 1) {
        return fallback;
    }

    // The predecessor's boundary stitched line has explicitly merged metadata.
    // Keep its existing metadata path and only project metadata for non-stitched
    // predecessor wrapped lines.
    if (nextBlock.continuationPrefixCharacters % width != 0) {
        const int naiveLines = [block getNumLinesWithWrapWidth:width];
        if (localWrappedLine == naiveLines - 1) {
            return fallback;
        }
    }

    iTermImmutableMetadata projected = fallback;
    NSInteger candidateIndex = nextIndex;
    while (candidateIndex < (NSInteger)blocks.count) {
        LineBlock *candidate = blocks[candidateIndex];
        if (!candidate.startsWithContinuation) {
            break;
        }
        projected = [candidate metadataForRawLineAtWrappedLineOffset:0 width:width];
        // A continuation chain for the same logical line can only extend
        // through blocks whose first raw line is also their last raw line.
        if ([candidate numRawLines] != 1) {
            break;
        }
        candidateIndex += 1;
    }
    return projected;
}

- (iTermImmutableMetadata)metadataForLineNumber:(int)lineNumber width:(int)width {
    int remainder = 0;
    NSInteger blockIndex = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNumber
                                                        width:width
                                                    remainder:&remainder
                                                   blockIndex:&blockIndex];
    iTermImmutableMetadata metadata = [block metadataForLineNumber:remainder width:width];
    return [self metadataByProjectingContinuationForBlock:block
                                               blockIndex:blockIndex
                                         localWrappedLine:remainder
                                                    width:width
                                                 fallback:metadata];
}

- (iTermBidiDisplayInfo * _Nullable)bidiInfoForLine:(int)lineNumber width:(int)width {
    if (!_maintainBidiInfo) {
        return nil;
    }
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNumber
                                                        width:width
                                                    remainder:&remainder];
    return [block bidiInfoForLineNumber:remainder width:width];
}

- (BOOL)isFirstLineOfBlock:(int)lineNumber width:(int)width {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNumber
                                                        width:width
                                                    remainder:&remainder];
    return block != nil && remainder == 0;
}

- (iTermImmutableMetadata)metadataForRawLineWithWrappedLineNumber:(int)lineNum width:(int)width {
    int remainder = 0;
    NSInteger blockIndex = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum
                                                        width:width
                                                    remainder:&remainder
                                                   blockIndex:&blockIndex];
    iTermImmutableMetadata metadata = [block metadataForRawLineAtWrappedLineOffset:remainder width:width];
    return [self metadataByProjectingContinuationForBlock:block
                                               blockIndex:blockIndex
                                         localWrappedLine:remainder
                                                    width:width
                                                 fallback:metadata];
}

// Copy a line into the buffer. If the line is shorter than 'width' then only
// the first 'width' characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
- (int)copyLineToBuffer:(screen_char_t *)buffer
                  width:(int)width
                lineNum:(int)lineNum
           continuation:(screen_char_t *)continuationPtr {
    return [self copyLineToBuffer:buffer
                       byteLength:(width + 1) * sizeof(screen_char_t)
                            width:width
                          lineNum:lineNum
                     continuation:continuationPtr];
}

- (int)copyLineToData:(NSMutableData *)destinationData
                width:(int)width
              lineNum:(int)lineNum
         continuation:(screen_char_t * _Nullable)continuationPtr {
    return [self copyLineToBuffer:destinationData.mutableBytes
                       byteLength:destinationData.length
                            width:width
                          lineNum:lineNum
                     continuation:continuationPtr];
}

- (int)copyLineToBuffer:(screen_char_t *)buffer
             byteLength:(int)bufferLengthInBytes
                  width:(int)width
                lineNum:(int)lineNum
           continuation:(screen_char_t * _Nullable)continuationPtr {
    ITBetaAssert(lineNum >= 0, @"Negative lineNum to copyLineToBuffer");
    int remainder = 0;
    NSInteger blockIndex = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder blockIndex:&blockIndex];
    ITBetaAssert(remainder >= 0, @"Negative lineNum BEFORE consuming block_lines");
    if (!block) {
        NSLog(@"Couldn't find line %d", lineNum);
#if DEBUG
        [self sanityCheck];
#endif
        memset(buffer, 0, width * sizeof(screen_char_t));
        return EOL_HARD;
    }

    const int requestedLine = remainder;
    __weak __typeof(self) weakSelf = self;
    __weak __typeof(block) weakBlock = block;
    block.debugInfo = ^NSString *{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return nil;
        }
        const NSInteger i = [strongSelf->_lineBlocks.blocks indexOfObject:weakBlock];
        NSString *lineBlockDump = [strongSelf->_lineBlocks dumpForCrashlog];
        return [NSString stringWithFormat:@"Block index %@, width=%@, lineNum=%@, remainder=%@\n%@",
                @(i), @(width), @(lineNum), @(remainder), lineBlockDump];
    };
    iTermWrappedLineResult r;
    if (![self getWrappedLineFromBlock:block width:width remainder:remainder result:&r]) {
        ITAssertWithMessage(NO, @"Nil wrapped line %@ for block with width %@", @(requestedLine), @(width));
#if DEBUG
        [self sanityCheck];
#endif
        memset(buffer, 0, width * sizeof(screen_char_t));
        return EOL_HARD;
    }
    ITAssertWithMessage(r.length >= 0, @"Length is negative %@", @(r.length));
    r.metadata = [self metadataByProjectingContinuationForBlock:block
                                                     blockIndex:blockIndex
                                               localWrappedLine:requestedLine
                                                          width:width
                                                       fallback:r.metadata];

    if (continuationPtr) {
        *continuationPtr = r.continuation;
    }
    ITAssertWithMessage(r.length <= width, @"Length too long");

    // Use the shared stitch helper for boundary-spanning wrapped lines.
    ScreenCharArray *stitched = [self stitchedLineFromBlockAtIndex:blockIndex
                                                             width:width
                                             localWrappedLineIndex:requestedLine];
    if (stitched) {
        ITAssertWithMessage(bufferLengthInBytes >= width * (int)sizeof(screen_char_t),
                            @"Buffer too small for stitched line");
        memcpy(buffer, stitched.line, stitched.length * sizeof(screen_char_t));
        [self extendContinuation:stitched.continuation inBuffer:buffer ofLength:stitched.length toWidth:width];
        if (continuationPtr) {
            *continuationPtr = stitched.continuation;
        }
        return stitched.eol;
    }

    if (r.length > 0 && r.chars[0].code ^ r.chars[r.length - 1].code) {
        // This is here to figure out if a segfault I see a lot of is due to reading or writing.
        // If it crashes in the if statement's condition, it's on the read side.
        // If it crashes in memcpy/memmove below it's on the write side.
        DLog(@"*p");
    }
    ITAssertWithMessage(bufferLengthInBytes >= r.length * sizeof(screen_char_t),
                        @"Destination data has length %@ but I have %@ chars totaling %@ bytes to copy. width=%@",
                        @(bufferLengthInBytes), @(r.length), @(r.length * sizeof(screen_char_t)), @(width));
    memcpy((char*) buffer, (char*) r.chars, r.length * sizeof(screen_char_t));
    [self extendContinuation:r.continuation inBuffer:buffer ofLength:r.length toWidth:width];

    if (requestedLine == 0 && [iTermAdvancedSettingsModel showBlockBoundaries]) {
        for (int i = 0; i < width; i++) {
            buffer[i].code = 'X';
            buffer[i].complexChar = NO;
            buffer[i].image = NO;
            buffer[i].virtualPlaceholder = NO;
        }
    }
    return r.eol;
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

// Fetch a wrapped line from a block with all metadata in one call.
// Returns YES if the line was found, NO otherwise. On success, result is filled in.
- (BOOL)getWrappedLineFromBlock:(LineBlock *)block
                          width:(int)width
                      remainder:(int)remainder
                         result:(iTermWrappedLineResult *)result {
    int lineNum = remainder;
    result->chars = [block getWrappedLineWithWrapWidth:width
                                               lineNum:&lineNum
                                            lineLength:&result->length
                                     includesEndOfLine:&result->eol
                                               yOffset:NULL
                                          continuation:&result->continuation
                                  isStartOfWrappedLine:NULL
                                              metadata:&result->metadata];
    return result->chars != NULL;
}

// Delegates to the canonical stitch implementation on iTermLineBlockArray.
- (ScreenCharArray *)stitchedLineFromBlockAtIndex:(NSInteger)blockIndex
                                            width:(int)width
                            localWrappedLineIndex:(int)localWrappedLineIndex {
    return [_lineBlocks stitchedLineFromBlockAtIndex:blockIndex
                                               width:width
                               localWrappedLineIndex:localWrappedLineIndex];
}

- (int)appendContentsOfLineBuffer:(LineBuffer *)other width:(int)width includingCursor:(BOOL)cursor {
#if DEBUG
    [self assertUniqueBlockIDs];
#endif
    _deferSanityCheck += 1;
    self.dirty = YES;
    int offset = 0;
    if (cursor) {
        offset = TotalNumberOfRawLines(self);
    }
    while (_lineBlocks.lastBlock.isEmpty) {
        [_lineBlocks removeLastBlock];
    }
    for (LineBlock *block in other->_lineBlocks.blocks) {
        [_lineBlocks addBlock:[block copyWithAbsoluteBlockNumber:num_dropped_blocks + _lineBlocks.count]];
        if (block != other->_lineBlocks.lastBlock) {
            [self commitLastBlock];
        }
    }
    if (cursor) {
        cursor_rawline = other->cursor_rawline + offset;
        cursor_x = other->cursor_x;
    }

    num_wrapped_lines_width = -1;
    _deferSanityCheck -= 1;
    return [self dropExcessLinesWithWidth:width];
}

- (ScreenCharArray *)screenCharArrayForLine:(int)line
                                      width:(int)width
                                   paddedTo:(int)paddedSize
                                 eligibleForDWC:(BOOL)eligibleForDWC {
    int remainder = 0;
    NSInteger blockIndex = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:line width:width remainder:&remainder blockIndex:&blockIndex];
    if (!block) {
        ITAssertWithMessage(NO, @"Failed to find line %@ with width %@. Cache is: %@", @(line), @(width),
                            [[[[_lineBlocks dumpForCrashlog] dataUsingEncoding:NSUTF8StringEncoding] it_compressedData] it_hexEncoded]);
        return nil;
    }
    const int localWrappedLineIndex = remainder;
    iTermWrappedLineResult r;
    if (![self getWrappedLineFromBlock:block width:width remainder:remainder result:&r]) {
        return nil;
    }
    r.metadata = [self metadataByProjectingContinuationForBlock:block
                                                     blockIndex:blockIndex
                                               localWrappedLine:localWrappedLineIndex
                                                          width:width
                                                       fallback:r.metadata];
    ScreenCharArray *stitched = [self stitchedLineFromBlockAtIndex:blockIndex
                                                             width:width
                                                localWrappedLineIndex:localWrappedLineIndex];
    if (stitched) {
        return [stitched paddedToLength:paddedSize eligibleForDWC:eligibleForDWC];
    }
    ScreenCharArray *sca = [[ScreenCharArray alloc] initWithLine:r.chars
                                                          length:r.length
                                                        metadata:r.metadata
                                                    continuation:r.continuation];
    return [sca paddedToLength:paddedSize eligibleForDWC:eligibleForDWC];
}

- (ScreenCharArray *)maybeScreenCharArrayForLine:(int)line
                                           width:(int)width
                                        paddedTo:(int)paddedSize
                                  eligibleForDWC:(BOOL)eligibleForDWC {
    int remainder = 0;
    NSInteger blockIndex = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:line width:width remainder:&remainder blockIndex:&blockIndex];
    if (!block) {
        return nil;
    }
    const int localWrappedLineIndex = remainder;
    iTermWrappedLineResult r;
    if (![self getWrappedLineFromBlock:block width:width remainder:remainder result:&r]) {
        return nil;
    }
    r.metadata = [self metadataByProjectingContinuationForBlock:block
                                                     blockIndex:blockIndex
                                               localWrappedLine:localWrappedLineIndex
                                                          width:width
                                                       fallback:r.metadata];
    ScreenCharArray *stitched = [self stitchedLineFromBlockAtIndex:blockIndex
                                                             width:width
                                             localWrappedLineIndex:localWrappedLineIndex];
    if (stitched) {
        return [stitched paddedToLength:paddedSize eligibleForDWC:eligibleForDWC];
    }
    ScreenCharArray *sca = [[ScreenCharArray alloc] initWithLine:r.chars
                                                          length:r.length
                                                        metadata:r.metadata
                                                    continuation:r.continuation];
    return [sca paddedToLength:paddedSize eligibleForDWC:eligibleForDWC];
}

- (ScreenCharArray *)wrappedLineAtIndex:(int)lineNum
                                  width:(int)width {
    return [self wrappedLineAtIndex:lineNum width:width continuation:NULL];
}

- (ScreenCharArray *)wrappedLineAtIndex:(int)lineNum
                                  width:(int)width
                           continuation:(screen_char_t *)continuationPtr {
    int remainder = 0;
    NSInteger blockIndex = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder blockIndex:&blockIndex];
    if (!block) {
        ITAssertWithMessage(NO, @"Failed to find line %@ with width %@. Cache is: %@", @(lineNum), @(width),
                            [[[[_lineBlocks dumpForCrashlog] dataUsingEncoding:NSUTF8StringEncoding] it_compressedData] it_hexEncoded]);
        return nil;
    }

    const int localWrappedLineIndex = remainder;
    iTermWrappedLineResult r;
    if (![self getWrappedLineFromBlock:block width:width remainder:remainder result:&r]) {
        NSLog(@"Couldn't find line %d", lineNum);
        ITAssertWithMessage(NO, @"Tried to get non-existent line");
        return nil;
    }
    if (continuationPtr) {
        *continuationPtr = r.continuation;
    }
    r.metadata = [self metadataByProjectingContinuationForBlock:block
                                                     blockIndex:blockIndex
                                               localWrappedLine:localWrappedLineIndex
                                                          width:width
                                                       fallback:r.metadata];
    ScreenCharArray *stitched = [self stitchedLineFromBlockAtIndex:blockIndex
                                                             width:width
                                             localWrappedLineIndex:localWrappedLineIndex];
    if (stitched) {
        if (continuationPtr) {
            *continuationPtr = stitched.continuation;
        }
        return stitched;
    }
    ScreenCharArray *result = [[ScreenCharArray alloc] initWithLine:r.chars
                                                             length:r.length
                                                           metadata:r.metadata
                                                       continuation:r.continuation];
    ITAssertWithMessage(result.length <= width, @"Length too long");
    return result;
}

- (ScreenCharArray * _Nonnull)rawLineAtWrappedLine:(int)lineNum width:(int)width {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder];
    return [block rawLineAtWrappedLineOffset:remainder width:width];
}

- (ScreenCharArray *)unwrappedLineAtIndex:(int)i {
    int passed = 0;
    for (LineBlock *block in _lineBlocks.blocks) {
        int count = [block numRawLines];
        if (block.startsWithContinuation) {
            count -= 1;
        }
        if (i >= passed && i < passed + count) {
            int localIndex = i - passed;
            if (block.startsWithContinuation) {
                // Skip over the continuation entry (raw line 0 in this block
                // is part of the previous block's last raw line).
                localIndex += 1;
            }
            return [block screenCharArrayForRawLine:localIndex + block.firstEntry];
        }
        passed += count;
    }
    return nil;
}

- (NSArray<ScreenCharArray *> *)wrappedLinesFromIndex:(int)lineNum width:(int)width count:(int)count {
    if (count <= 0) {
        return @[];
    }

    NSMutableArray<ScreenCharArray *> *arrays = [NSMutableArray array];
    [_lineBlocks enumerateLinesInRange:NSMakeRange(lineNum, count)
                                 width:width
                                 block:^(const screen_char_t * _Nonnull chars,
                                         int length,
                                         int eol,
                                         screen_char_t continuation,
                                         iTermImmutableMetadata metadata,
                                         BOOL * _Nonnull stop) {
        ScreenCharArray *lineResult = [[ScreenCharArray alloc] initWithLine:chars
                                                                     length:length
                                                               continuation:continuation];
        [arrays addObject:lineResult];
    }];
    return arrays;
}

- (void)enumerateLinesInRange:(NSRange)range
                        width:(int)width
                        block:(void (^)(int, ScreenCharArray *, iTermImmutableMetadata, BOOL *))block {
    __block int count = range.location;
    [_lineBlocks enumerateLinesInRange:range
                                 width:width
                                 block:
     ^(const screen_char_t * _Nonnull chars,
       int length,
       int eol,
       screen_char_t continuation,
       iTermImmutableMetadata metadata,
       BOOL * _Nonnull stop) {
        ScreenCharArray *array = [[ScreenCharArray alloc] initWithLine:chars
                                                                length:length
                                                          continuation:continuation];
        const int lineNumber = count++;
        const iTermImmutableMetadata projected = [self metadataForLineNumber:lineNumber width:width];
        block(lineNumber, array, projected, stop);
    }];
}

- (int)numLinesWithWidth:(int)width {
    if (width == 0) {
        return 0;
    }
    return RawNumLines(self, width);
}

- (void)removeLastRawLine {
    _deferSanityCheck++;
    self.dirty = YES;
    [_lineBlocks.lastBlock removeLastRawLine];
    if (_lineBlocks.lastBlock.numRawLines == 0 && _lineBlocks.count > 1) {
        [_lineBlocks removeLastBlock];
    }
    // Invalidate the cache
    num_wrapped_lines_width = -1;
    _deferSanityCheck--;
}

- (void)removeLastWrappedLines:(int)numberOfLinesToRemove
                         width:(int)width {
    self.dirty = YES;
    // Invalidate the cache
    num_wrapped_lines_width = -1;

    int linesToRemoveRemaining = numberOfLinesToRemove;
    while (linesToRemoveRemaining > 0 && _lineBlocks.count > 0) {
        LineBlock *block = _lineBlocks.lastBlock;
        iTermBlockLineInfo info = iTermBlockContributedLines(block, width);

        if (info.contributed > linesToRemoveRemaining) {
            // Partial remove — block has more visible lines than we need to remove.
            if (info.hidden > 0) {
                // Continuation block: remove by exact visible wrapped-line
                // lengths. Do not assume kept lines are full width (hard-EOL
                // short lines can appear in continuation blocks).
                const int keptLines = info.contributed - linesToRemoveRemaining;
                const int firstVisibleLocalLine = info.hidden;
                const int totalVisibleCells = iTermSumWrappedLineLengths(block,
                                                                         width,
                                                                         firstVisibleLocalLine,
                                                                         info.contributed);
                const int keptVisibleCells = iTermSumWrappedLineLengths(block,
                                                                        width,
                                                                        firstVisibleLocalLine,
                                                                        keptLines);
                const int cellsToRemove = MAX(0, totalVisibleCells - keptVisibleCells);
                if (cellsToRemove > 0) {
                    [block removeLastCells:cellsToRemove];
                }
            } else {
                [block removeLastWrappedLines:linesToRemoveRemaining width:width];
            }
            return;
        }
        if (info.contributed == linesToRemoveRemaining && info.hidden > 0) {
            // Block's visible lines exactly match what remains, but hidden
            // lines exist at the head. Do a partial remove so the block
            // object survives, preserving predecessor boundary content.
            const int firstVisibleLocalLine = info.hidden;
            const int totalVisibleCells = iTermSumWrappedLineLengths(block,
                                                                     width,
                                                                     firstVisibleLocalLine,
                                                                     info.contributed);
            if (totalVisibleCells > 0) {
                [block removeLastCells:totalVisibleCells];
            }
            return;
        }
        // contributed <= linesToRemoveRemaining: remove whole block.
        [_lineBlocks removeLastBlock];
        linesToRemoveRemaining -= info.contributed;
    }
}

- (ScreenCharArray * _Nullable)popLastLineWithWidth:(int)width {
    screen_char_t *buffer = iTermCalloc(width, sizeof(screen_char_t));
    int eol = 0;
    iTermImmutableMetadata metadata;
    screen_char_t continuation;
    const BOOL ok = [self popAndCopyLastLineInto:buffer
                                           width:width
                               includesEndOfLine:&eol
                                        metadata:&metadata
                                    continuation:&continuation];
    if (!ok) {
        free(buffer);
        return nil;
    }
    return [[ScreenCharArray alloc] initWithLine:buffer
                                          length:width
                                        metadata:metadata
                                    continuation:continuation
                                   freeOnRelease:YES];
}

- (void)removeTrailingEmptyBlocks {
    _deferSanityCheck++;
    while (_lineBlocks.count && _lineBlocks.lastBlock.isEmpty) {
        [_lineBlocks removeLastBlock];
        num_wrapped_lines_width = -1;
    }
    _deferSanityCheck--;
}

- (BOOL)popAndCopyLastLineInto:(screen_char_t*)ptr
                         width:(int)width
             includesEndOfLine:(int*)includesEndOfLine
                      metadata:(out iTermImmutableMetadata *)metadataPtr
                  continuation:(screen_char_t *)continuationPtr {
    const int n = [self numLinesWithWidth:width];
    if (n == 0) {
        return NO;
    }
    _deferSanityCheck++;
    self.dirty = YES;
    num_wrapped_lines_width = -1;

    // Fetch the last visible wrapped line via the high-level API, which
    // handles stitching across continuation block boundaries correctly.
    const int lastLineIndex = n - 1;
    screen_char_t continuation = { 0 };
    ScreenCharArray *lastLine = [self wrappedLineAtIndex:lastLineIndex
                                                   width:width
                                            continuation:&continuation];
    ITAssertWithMessage(lastLine != nil, @"wrappedLineAtIndex returned nil for last line");
    ITAssertWithMessage(lastLine.length <= width, @"Length too large");
    ITAssertWithMessage(lastLine.length >= 0, @"Negative length");

    *includesEndOfLine = lastLine.eol;
    if (metadataPtr) {
        *metadataPtr = lastLine.metadata;
    }
    if (continuationPtr) {
        *continuationPtr = continuation;
    }

    // Copy into the provided buffer.
    memcpy(ptr, lastLine.line, sizeof(screen_char_t) * lastLine.length);
    [self extendContinuation:continuation inBuffer:ptr ofLength:lastLine.length toWidth:width];

    // Remove the last visible wrapped line using the continuation-aware
    // removal that preserves hidden head content in continuation blocks.
    [self removeLastWrappedLines:1 width:width];

#ifdef LOG_MUTATIONS
    NSLog(@"Pop: %@\n", ScreenCharArrayToStringDebug(ptr, width));
#endif
    _deferSanityCheck--;
    return YES;
}

NS_INLINE int TotalNumberOfRawLines(LineBuffer *self) {
    return self->_lineBlocks.numberOfRawLines;
}

- (void)setCursor:(int)x {
    self.dirty = YES;
    LineBlock *block = _lineBlocks.lastBlock;
    if ([block hasPartial]) {
        int last_line_length = [block lengthOfRawLine:[block numEntries]-1];
        cursor_x = x + last_line_length;
        cursor_rawline = -1;
    } else {
        cursor_x = x;
        cursor_rawline = 0;
    }

    cursor_rawline += TotalNumberOfRawLines(self);
}

- (BOOL)getCursorInLastLineWithWidth:(int)width atX:(int *)x {
    [self removeTrailingEmptyBlocks];
    int total_raw_lines = TotalNumberOfRawLines(self);
    if (cursor_rawline == total_raw_lines-1) {
        // The cursor is on the last line in the buffer.
        LineBlock* block = _lineBlocks.lastBlock;
        int last_line_length = [block lengthOfRawLine:([block numEntries]-1)];
        const screen_char_t *lastRawLine = [block rawLine:([block numEntries]-1)];
        int num_overflow_lines = [block numberOfFullLinesFromBuffer:lastRawLine length:last_line_length width:width];

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

- (BOOL)_findPosition:(LineBufferPosition *)start inBlock:(int*)block_num inOffset:(int*)offset {
    LineBlock *block = [_lineBlocks blockContainingPosition:start.absolutePosition - droppedChars
                                                    yOffset:start.yOffset
                                                      width:-1
                                                  remainder:offset
                                                blockOffset:NULL
                                                      index:block_num];
    if (!block) {
        return NO;
    }
    return YES;
}

- (int)_blockPosition:(int) block_num {
    return [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, block_num)];
}

- (BOOL)setStartCoord:(VT100GridCoord)coord ofFindContext:(FindContext *)findContext width:(int)width {
    LineBufferPosition *position = [self positionForCoordinate:coord width:width offset:0];
    int absBlockNum = 0;
    int offset = 0;
    if (![self _findPosition:position inBlock:&absBlockNum inOffset:&offset]) {
        return NO;
    }
    findContext.offset = offset;
    findContext.absBlockNum = absBlockNum + num_dropped_blocks;
    return YES;
}

- (void)prepareToSearchFor:(NSString*)substring
                startingAt:(LineBufferPosition *)start
                   options:(FindOptions)options
                      mode:(iTermFindMode)mode
               withContext:(FindContext*)context {
    DLog(@"Prepare to search for %@", substring);
    context.substring = substring;
    context.options = options;
    if (options & FindOptBackwards) {
        context.dir = -1;
    } else {
        context.dir = 1;
    }
    context.mode = mode;
    int offset = context.offset;
    int absBlockNum = context.absBlockNum;
    if ([self _findPosition:start inBlock:&absBlockNum inOffset:&offset]) {
        DLog(@"Converted %@ to absBlock=%@, offset=%@", start, @(absBlockNum), @(offset));
        context.offset = offset;
        context.absBlockNum = absBlockNum + num_dropped_blocks;
        context.status = Searching;
    } else {
        DLog(@"Failed to convert %@", start);
        [self _findPosition:start inBlock:&absBlockNum inOffset:&offset];
        context.status = NotFound;
    }
    context.results = [NSMutableArray array];
}

- (void)findSubstring:(FindContext*)context stopAt:(LineBufferPosition *)stopPosition {
    NSInteger blockIndex = context.absBlockNum - num_dropped_blocks;
    const NSInteger numBlocks = _lineBlocks.count;  // This avoids involving unsigned integers in comparisons
    if (context.dir > 0) {
        // Search forwards
        if (context.absBlockNum < num_dropped_blocks) {
            // The next block to search was dropped. Skip ahead to the first block.
            // NSLog(@"Next to search was dropped. Skip to start");
            context.absBlockNum = num_dropped_blocks;
        }
        if (blockIndex >= numBlocks) {
            // Got to bottom
            // NSLog(@"Got to bottom");
            context.status = NotFound;
            return;
        }
        if (blockIndex < 0) {
            DLog(@"Negative index %@ in forward search", @(blockIndex));
            context.status = NotFound;
            return;
        }
    } else {
        // Search backwards
        if (blockIndex < 0) {
            // Got to top
            // NSLog(@"Got to top");
            context.status = NotFound;
            return;
        }
        if (blockIndex >= numBlocks) {
            DLog(@"Out of bounds index %@ (>=%@) in backward search", @(blockIndex), @(numBlocks));
            context.status = NotFound;
            return;
        }
    }

    assert(blockIndex >= 0);
    assert(blockIndex < numBlocks);
    LineBlock* block = _lineBlocks[blockIndex];

    if (blockIndex == 0 &&
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

    const NSRange blockAbsolutePositions = NSMakeRange([self absPositionOfAbsBlock:blockIndex + num_dropped_blocks],
                                                       block.rawSpaceUsed);
    BOOL includesPartialLastLine = NO;
    LineBlockMultiLineSearchState *continuationState = nil;
    NSInteger crossBlockResultCount = 0;
    [block findSubstring:context.substring
                 options:context.options
                    mode:context.mode
                atOffset:context.offset
                 results:context.results
         multipleResults:((context.options & FindMultipleResults) != 0)
 includesPartialLastLine:&includesPartialLastLine
     multiLinePriorState:context.multiLineSearchState
       continuationState:&continuationState
   crossBlockResultCount:&crossBlockResultCount];
    context.lastAbsPositionsSearched = blockAbsolutePositions;
    context.includesPartialLastLine = includesPartialLastLine && (blockIndex + 1 == numBlocks);
    NSMutableArray* filtered = [NSMutableArray arrayWithCapacity:[context.results count]];
    BOOL haveOutOfRangeResults = NO;
    const int blockPosition = [self _blockPosition:blockIndex];
    if (continuationState && !context.multiLineSearchState) {
        // This is a new partial match starting in this block.
        // Save the block's global position so we can compute the correct final position later.
        continuationState.startingBlockPosition = blockPosition;
    } else if (continuationState && context.multiLineSearchState) {
        // Continuing a partial match that spans multiple blocks.
        // Preserve the starting block position from the prior state.
        continuationState.startingBlockPosition = context.multiLineSearchState.startingBlockPosition;
    }
    context.multiLineSearchState = continuationState;
    const int blockSize = _lineBlocks.blocks[blockIndex].rawSpaceUsed;  // TODO: Is this right when lines are dropped?
    const int stopAt = stopPosition.absolutePosition - droppedChars;
    if (context.dir > 0 && blockPosition >= stopAt) {
        DLog(@"status<-NotFound because dir>0, blockPosition(%@)>=stopAt(%@)", @(blockPosition), @(stopAt));
        context.status = NotFound;
    } else if (context.dir < 0 && blockPosition + blockSize < stopAt) {
        DLog(@"status<-NotFound because dir<0, blockPosition(%@)+blockSize(%@)<stopAt(%@)", @(blockPosition), @(blockSize), @(stopAt));
        context.status = NotFound;
    } else {
        NSInteger resultIndex = 0;
        for (ResultRange* range in context.results) {
            // Skip position adjustment for cross-block results (they already have global positions).
            // This relies on cross-block results being at the beginning of context.results,
            // which is guaranteed because the continuation handler in findSubstring: appends
            // them before the main search loop runs.
            if (resultIndex >= crossBlockResultCount) {
                range->position += blockPosition;
            }
            resultIndex++;
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
- (NSArray<XYRange *> *)convertPositions:(NSArray<ResultRange *> *)resultRanges withWidth:(int)width {
    return [self convertPositions:resultRanges expandedResultRanges:nil withWidth:width];
}

- (NSArray<XYRange *> * _Nullable)convertPositions:(NSArray<ResultRange *> * _Nonnull)resultRanges
                              expandedResultRanges:(NSMutableArray<ResultRange *> * _Nullable)expandedResultRanges
                                         withWidth:(int)width {
    const BOOL expanded = (expandedResultRanges != nil);
    if (width <= 0) {
        return nil;
    }
    int *sortedPositions = SortedPositionsFromResultRanges(resultRanges, !expanded);
    int i = 0;
    int yoffset = 0;
    int numBlocks = _lineBlocks.count;
    int passed = 0;
    LineBlock *block = _lineBlocks[0];
    int used = [block rawSpaceUsed];

    LineBufferSearchIntermediateMap *intermediate = [[LineBufferSearchIntermediateMap alloc] initWithCapacity:resultRanges.count * 2];
    int prev = -1;
    const int numPositions = resultRanges.count * (expanded ? 1 : 2);
    int lastPositionToConvert = -1;
    for (int j = 0; j < numPositions; j++) {
        const int position = sortedPositions[j];
        if (position == prev) {
            continue;
        }
        prev = position;

        // Advance block until it includes this position
        while (position >= passed + used && i < numBlocks) {
            passed += used;
            int blockLines = [block getNumLinesWithWrapWidth:width];
            if (block.startsWithContinuation) {
                blockLines += [block continuationWrappedLineAdjustmentForWidth:width];
            }
            yoffset += blockLines;
            i++;
            if (i < numBlocks) {
                block = _lineBlocks.blocks[i];
                used = [block rawSpaceUsed];
            }
        }
        if (i < numBlocks) {
            int x, y;
            assert(position >= passed);
            assert(position < passed + used);
            assert(used == [block rawSpaceUsed]);
            const int positionToConvert = expanded ? [block offsetOfStartOfLineIncludingOffset:position - passed] : position - passed;
            if (expanded) {
                // Prevent duplicates when expanding.
                if (positionToConvert == lastPositionToConvert) {
                    continue;
                }
                lastPositionToConvert = positionToConvert;
            }
            // convertPosition returns y in naive block-local space.
            // Continuation blocks with adjustment=-1 have a hidden first
            // wrapped line that is part of the stitched boundary line from
            // the previous block. yoffset already excludes this hidden
            // line, so subtract it from the block-local y before adding
            // yoffset to avoid double-counting.
            const int hidden = block.startsWithContinuation
                ? MAX(0, -[block continuationWrappedLineAdjustmentForWidth:width])
                : 0;
            BOOL isOk = [block convertPosition:positionToConvert
                                     withWidth:width
                                     wrapOnEOL:YES
                                           toX:&x
                                           toY:&y];
            int blockLocalY = y;
            if (isOk) {
                // convertPosition returns x in naive block-local space without
                // accounting for the continuation prefix column offset. Only the
                // first wrapped line (naiveY==0) needs shifting; later wrapped
                // lines already have correct offsets via
                // cacheAwareOffsetOfWrappedLineInBuffer.
                if (block.startsWithContinuation) {
                    const int pCol = block.continuationPrefixCharacters % width;
                    if (pCol > 0 && y == 0) {
                        x += pCol;
                    }
                }
                VT100GridCoord normalized = LineBufferNormalizeWrappedCoord(x, y, width);
                x = normalized.x;
                y = normalized.y;
                y = y - hidden + yoffset;
                [intermediate addCoordinate:VT100GridCoordMake(x, y)
                                forPosition:positionToConvert + passed];
            } else {
                assert(false);
            }
            if (expanded) {
                // Use naive block-local y for block-internal queries.
                const NSNumber *rawLineNumber = [block rawLineNumberAtWrappedLineOffset:blockLocalY
                                                                                  width:width];
                if (rawLineNumber) {
                    const int length = [block lengthOfRawLine:rawLineNumber.intValue];
                    [expandedResultRanges addObject:[[ResultRange alloc] initWithPosition:positionToConvert + passed
                                                                                   length:length]];

                    isOk = [block convertPosition:positionToConvert + length - 1
                                        withWidth:width
                                        wrapOnEOL:YES
                                              toX:&x
                                              toY:&y];
                    if (isOk) {
                        if (block.startsWithContinuation) {
                            const int pCol = block.continuationPrefixCharacters % width;
                            if (pCol > 0 && y == 0) {
                                x += pCol;
                            }
                        }
                        VT100GridCoord normalized2 = LineBufferNormalizeWrappedCoord(x, y, width);
                        x = normalized2.x;
                        y = normalized2.y;
                        y = y - hidden + yoffset;
                        [intermediate addCoordinate:VT100GridCoordMake(x, y)
                                        forPosition:positionToConvert + passed + length - 1];
                    } else {
                        assert(false);
                    }
                }
            }
        }
    }

    // Walk the positions array and populate results by looking up points in intermediate dict.
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[resultRanges count] * 2];
    [intermediate enumerateCoordPairsForRanges:(expandedResultRanges ?: resultRanges)
                                         block:^(VT100GridCoord start, VT100GridCoord end) {
        XYRange *xyrange = [[XYRange alloc] init];
        xyrange->xStart = start.x;
        xyrange->yStart = start.y;
        xyrange->xEnd = end.x;
        xyrange->yEnd = end.y;
        [result addObject:xyrange];
    }];
    free(sortedPositions);
    return result;
}

- (LineBufferPosition *)positionOfFindContext:(FindContext *)context width:(int)width {
    if (context.absBlockNum < num_dropped_blocks) {
        // Before beginning
        DLog(@"Position of find context with block %@ before beginning", @(context.absBlockNum));
        return [self firstPosition];
    }
    if (context.absBlockNum - num_dropped_blocks >= _lineBlocks.count) {
        DLog(@"Position of find context (%@-%@=%@) is after last block (%@)", @(context.absBlockNum), @(num_dropped_blocks), @(context.absBlockNum - num_dropped_blocks), @(_lineBlocks.count));
        return [self lastPosition];
    }
    int blockNumber = context.absBlockNum - num_dropped_blocks;
    LineBufferPosition *position = [LineBufferPosition position];
    if (context.offset >= 0) {
        const long long precedingBlocksLength = [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, blockNumber)];
        position.absolutePosition = precedingBlocksLength + context.offset + droppedChars;
    } else {
        // Offset of -1 means we will search beginning at the end of the specified block regardless
        // of its length.
        const long long blocksLength = [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, blockNumber + 1)];
        position.absolutePosition = blocksLength + droppedChars;
    }
    position.yOffset = 0;
    position.extendsToEndOfLine = NO;
    return position;
}

- (LineBufferPosition *)positionForCoordinate:(VT100GridCoord)coord
                                        width:(int)width
                                       offset:(int)offset {
    ITBetaAssert(coord.y >= 0, @"Negative y coord to positionForCoordinate");
    VLog(@"positionForCoord:%@ width:%@ offset:%@", VT100GridCoordDescription(coord), @(width), @(offset));

    int x = coord.x;
    int y = coord.y;
    int line = y;
    NSInteger index;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:y
                                                       width:width
                                                   remainder:&line
                                                  blockIndex:&index];
    if (!block) {
        VLog(@"positionForCoord returning nil because blockContainingLineNumber returned nil");
        return nil;
    }
    long long absolutePosition = droppedChars + [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, index)];
    VLog(@"positionForCoord: Absolute position of block %@ is %@", @(index), @(absolutePosition));
    int pos;
    int yOffset = 0;  // Number of lines from start of block to coord
    BOOL extends = NO;
    const int localWrappedLineIndex = line;
    pos = [block getPositionOfLine:&line
                               atX:x
                         withWidth:width
                           yOffset:&yOffset
                           extends:&extends];
    if (pos < 0) {
        VLog(@"positionForCoordinate: returning nil because getPositionOfLine returned a negative value");
        DLog(@"failed to get position of line %@", @(line));
        return nil;
    }

    // Stitch-boundary fixup: when the coordinate is on a stitched line and
    // x falls in the head (block B's contribution), recompute pos to point
    // into block B rather than past the end of block A's tail.
    if (index + 1 < (NSInteger)_lineBlocks.count) {
        LineBlock *nextBlock = _lineBlocks[index + 1];
        if (nextBlock.startsWithContinuation) {
            const int pCol = nextBlock.continuationPrefixCharacters % width;
            if (pCol > 0 && localWrappedLineIndex == [block getNumLinesWithWrapWidth:width] - 1) {
                // Get actual tail length from block A's last wrapped line.
                int tailLineNum = localWrappedLineIndex;
                int tailLength = 0;
                int tailEOL = 0;
                const screen_char_t *tailP = [block getWrappedLineWithWrapWidth:width
                                                                        lineNum:&tailLineNum
                                                                     lineLength:&tailLength
                                                              includesEndOfLine:&tailEOL
                                                                        yOffset:NULL
                                                                   continuation:NULL
                                                           isStartOfWrappedLine:NULL
                                                                       metadata:NULL];
                // The stitched boundary consumes from block B's first *raw* line.
                // Wrapped line 0 can start after this consumed head segment when
                // continuation adjustment is 0, so it cannot be used to size headUsed.
                const int rawHeadLength = [nextBlock lengthOfRawLine:nextBlock.firstEntry];
                const int headUsed = MIN(width - tailLength, MAX(0, rawHeadLength));
                const int stitchedLength = tailLength + headUsed;

                if (tailP && x >= tailLength) {
                    VLog(@"positionForCoord: stitch boundary at block %@, tailLength=%@, headUsed=%@, x=%@",
                         @(index), @(tailLength), @(headUsed), @(x));
                    if (x < stitchedLength) {
                        pos = [block rawSpaceUsed] + (x - tailLength);
                        extends = NO;
                    } else {
                        pos = [block rawSpaceUsed] + headUsed;
                        extends = YES;
                    }
                    yOffset = 0;
                    VLog(@"positionForCoord: stitch fixup: pos=%@, extends=%@", @(pos), @(extends));
                }
            }
        }
    }

    absolutePosition += pos + offset;
    LineBufferPosition *result = [LineBufferPosition position];
    result.absolutePosition = absolutePosition;
    result.yOffset = yOffset;
    result.extendsToEndOfLine = extends;
    VLog(@"positionForCoord: Initialize result %@", result);

    // Make sure position is valid (might not be because of offset).
    BOOL ok;
    const VT100GridCoord resultingCoord =
    [self coordinateForPosition:result
                          width:width
                   extendsRight:YES  // doesn't matter for deciding if the result is valid
                             ok:&ok];
    if (!ok) {
        VLog(@"positionForCoord: failed to calculate the resulting coord");
        return nil;
    }
    VLog(@"positionForCoord: The resulting coord is %@ (want %@)", VT100GridCoordDescription(resultingCoord),
         VT100GridCoordDescription(coord));

    const int residual = coord.y - resultingCoord.y;
    VLog(@"positionForCoord: residual is %@", @(residual));

    if (residual > 0) {
        // This can happen if you want the position for a coord that is preceded by empty lines.
        //
        // Block 0
        //     abc
        //
        // Block 1
        //     (empty)
        //     (empty)      [want a position at the start of this line]
        //     xyz

        // Given coord x=0,y=2 `result` (prior to the next line) will be pos=3,yOffset=1. That has the block-relative
        // yOffset, but that's insufficient to find the right position since you'll need to traverse
        // empty lines between pos=3 and the start of this block (in this case 1, but empty blocks or
        // trailing empty lines in block 0 could cause it to be more).
        // The resultingCoord, therefore, will be x=0,y=1. The correct yOffset is found by adding the
        // missing lines back (in this case, 1 to go from y=1 to the y=2 that we want).
        result.yOffset += residual;
        VLog(@"positionForCoord: Advance result by %d", residual);
    }
    VLog(@"positionForCoordinate: returning %@", result);
    return result;
}

// Note this function returns a closed interval on end.x
- (VT100GridCoord)coordinateForPosition:(LineBufferPosition *)position
                                  width:(int)width
                           extendsRight:(BOOL)extendsRight
                                     ok:(BOOL *)ok {
    VLog(@"coordinateForPosition:%@ width:%@ extendsRight:%@", position, @(width), @(extendsRight));

    if (position.absolutePosition == self.lastPosition.absolutePosition) {
        VLog(@"coordinateForPosition: is last position");
        VT100GridCoord result;
        // If the absolute position is equal to the last position, then
        // numLinesWithWidth: will give the wrapped line number after all
        // trailing empty lines. They all have the same position because they
        // are empty. We need to back up by the number of empty lines and then
        // use position.yOffset to disambiguate.
        result.y = MAX(0, [self numLinesWithWidth:width] - 1 - [_lineBlocks.lastBlock numberOfTrailingEmptyLines]);
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
            if (extendsRight) {
                result.x = width - 1;  // closed interval
            }
        }
        if (ok) {
            *ok = YES;
        }
        VLog(@"coordinateForPosition: return %@", VT100GridCoordDescription(result));
        return result;
    }

    int p;
    int yoffset;
    VLog(@"coordinateForPosition: find block with position %@, yoffset=%@",
         @(position.absolutePosition - droppedChars), @(position.yOffset));
    LineBlock *block = [_lineBlocks blockContainingPosition:position.absolutePosition - droppedChars
                                                    yOffset:position.yOffset
                                                      width:width
                                                  remainder:&p
                                                blockOffset:&yoffset
                                                      index:NULL];
    if (!block) {
        VLog(@"coordinateForPosition: failed, returning error");
        if (ok) {
            *ok = NO;
        }
        return VT100GridCoordMake(0, 0);
    }
    VLog(@"coordinateForPosition: p=%@ yoffset=%@", @(p), @(yoffset));

    int y;
    int x;
    VLog(@"coordinateForPosition: calling convertPosition:%@ withWidth:%@", @(p), @(width));
    BOOL positionIsValid = [block convertPosition:p
                                        withWidth:width
                                        wrapOnEOL:NO  //  using extendsRight here is wrong because extension happens below
                                              toX:&x
                                              toY:&y];
    if (ok) {
        VLog(@"coordinateForPosition: got a valid reslut. x=%d, y=%d", x, y);
        *ok = positionIsValid;
    } else {
        VLog(@"coordinateForPosition: failed to convert position");
    }
    // Apply pCol shift and hidden-line correction for continuation blocks.
    if (block.startsWithContinuation) {
        const int pCol = block.continuationPrefixCharacters % width;
        if (pCol > 0 && y == 0) {
            x += pCol;
            VT100GridCoord normalized = LineBufferNormalizeWrappedCoord(x, y, width);
            x = normalized.x;
            y = normalized.y;
        }
        const int hidden = MAX(0, -[block continuationWrappedLineAdjustmentForWidth:width]);
        y -= hidden;
    }
    if (position.yOffset > 0) {
        if (!position.extendsToEndOfLine) {
            VLog(@"coordinateForPosition: wrap x to next line");
            x = 0;
        }
        y += position.yOffset;
        VLog(@"coordinateForPosition: advance y by %d to %d", position.yOffset, y);
    }
    if (position.extendsToEndOfLine) {
        if (extendsRight) {
            VLog(@"coordinateForPosition: extends right is true, set x to last column");
            x = width - 1;
        } else {
            VLog(@"coordinateForPosition: extends right is false, set x to 0");
            x = 0;
        }
    }
    VT100GridCoord coord = VT100GridCoordMake(x, y + yoffset);
    VLog(@"coordinateForPosition: return %@", VT100GridCoordDescription(coord));
    return coord;
}

- (LineBufferPosition *)firstPosition {
    LineBufferPosition *position = [LineBufferPosition position];
    position.absolutePosition = droppedChars;
    return position;
}

- (LineBufferPosition *)lastPosition {
    LineBufferPosition *position = [LineBufferPosition position];

    position.absolutePosition = droppedChars + [_lineBlocks rawSpaceUsed];

    return position;
}

- (LineBufferPosition *)penultimatePosition {
    if (_lineBlocks.rawSpaceUsed == 0) {
        return [self lastPosition];
    }
    return [[self lastPosition] predecessor];
}

- (LineBufferPosition * _Nonnull)positionForStartOfResultRange:(ResultRange *)resultRange {
    LineBufferPosition *position = [LineBufferPosition position];
    position.absolutePosition = droppedChars + resultRange.position;
    return position;
}

- (LineBufferPosition * _Nonnull)positionForStartOfLastLineBeforePosition:(LineBufferPosition *)limit {
    [self removeTrailingEmptyBlocks];
    int blockNum = 0;
    int offset = 0;
    if (![self _findPosition:limit inBlock:&blockNum inOffset:&offset]) {
        return [self positionForStartOfLastLine];
    }
    const long long precedingBlocksLength = [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, blockNum)];
    LineBlock *block = _lineBlocks[blockNum];
    LineBufferPosition *position = [LineBufferPosition position];
    const int offsetInBlock = [block offsetOfStartOfLineIncludingOffset:offset];
    position.absolutePosition = droppedChars + precedingBlocksLength + offsetInBlock;
    return position;
}

- (LineBufferPosition *)positionForStartOfLastLine {
    LineBufferPosition *position = [self lastPosition];
    const long long length = [_lineBlocks.lastBlock lengthOfLastLine];
    assert(length >= 0);
    assert(length <= position.absolutePosition);
    position.absolutePosition -= length;
    return position;
}

- (long long)absPositionOfFindContext:(FindContext *)findContext {
    if (findContext.absBlockNum < 0) {
        if (_lineBlocks.count == 0) {
            return 0;
        }
        return findContext.offset + droppedChars + [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, _lineBlocks.count)];
    }
    const int numBlocks = MIN(_lineBlocks.count, findContext.absBlockNum - num_dropped_blocks);
    const NSInteger rawSpaceUsed = numBlocks > 0 ? [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, numBlocks)] : 0;
    return droppedChars + rawSpaceUsed + findContext.offset;
}

- (int)positionForAbsPosition:(long long)absPosition
{
    absPosition -= droppedChars;
    if (absPosition < 0) {
        return [_lineBlocks[0] startOffset];
    }
    if (absPosition > INT_MAX) {
        absPosition = INT_MAX;
    }
    return (int)absPosition;
}

- (long long)absPositionForPosition:(int)pos {
    long long absPos = pos;
    return absPos + droppedChars;
}

- (int)absBlockNumberOfAbsPos:(long long)absPos {
    int index;
    LineBlock *block = [_lineBlocks blockContainingPosition:absPos - droppedChars
                                                    yOffset:0
                                                      width:0
                                                  remainder:NULL
                                                blockOffset:NULL
                                                      index:&index];
    if (!block) {
        return _lineBlocks.count + num_dropped_blocks;
    }
    return index + num_dropped_blocks;
}

- (long long)absPositionOfAbsBlock:(int)absBlockNum {
    if (absBlockNum <= num_dropped_blocks) {
        return droppedChars;
    }
    return droppedChars + [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, absBlockNum - num_dropped_blocks)];
}

- (void)storeLocationOfAbsPos:(long long)absPos
                    inContext:(FindContext *)context
{
    context.absBlockNum = [self absBlockNumberOfAbsPos:absPos];
    long long absOffset = [self absPositionOfAbsBlock:context.absBlockNum];
    context.offset = MAX(0, absPos - absOffset);
}

- (long long)numberOfDroppedChars {
    return droppedChars;
}

- (int)numberOfDroppedBlocks {
    return num_dropped_blocks;
}

- (int)largestAbsoluteBlockNumber {
    return _lineBlocks.count + num_dropped_blocks;
}

// Returns whether we truncated lines.
- (BOOL)encodeBlocks:(id<iTermEncoderAdapter>)encoder
            maxLines:(NSInteger)maxLines {
    __block BOOL truncated = NO;
    __block NSInteger numLines = 0;

    iTermOrderedDictionary<NSString *, LineBlock *> *index =
    [iTermOrderedDictionary byMappingEnumerator:_lineBlocks.blocks.reverseObjectEnumerator
                                          block:^id _Nonnull(NSUInteger index,
                                                             LineBlock *_Nonnull block) {
        DLog(@"Maybe encode block %p with guid %@", block, block.stringUniqueIdentifier);
        return block.stringUniqueIdentifier;
    }];
    [encoder encodeArrayWithKey:kLineBufferBlocksKey
                    identifiers:index.keys
                     generation:iTermGenerationAlwaysEncode
                        options:iTermGraphEncoderArrayOptionsReverse
                          block:^BOOL(id<iTermEncoderAdapter> _Nonnull encoder,
                                      NSInteger i,
                                      NSString * _Nonnull identifier,
                                      BOOL *stop) {
        LineBlock *block = index[identifier];
        DLog(@"Encode %@ with identifier %@ and generation %@", block, identifier, @(block.generation));
        return [encoder encodeDictionaryWithKey:kLineBufferBlockWrapperKey
                                     generation:block.generation
                                          block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
            assert(!truncated);
            DLog(@"Really encode block %p with guid %@", block, block.stringUniqueIdentifier);
            [encoder mergeDictionary:block.dictionary];
            // This caps the amount of data at a reasonable but arbitrary size.
            // Use contributed wrapped-line count so continuation blocks are
            // accounted for consistently with numLinesWithWidth:.
            int contributedLines = [block getNumLinesWithWrapWidth:80];
            if (block.startsWithContinuation) {
                contributedLines += [block continuationWrappedLineAdjustmentForWidth:80];
            }
            numLines += contributedLines;
            if (numLines >= maxLines) {
                truncated = YES;
                *stop = YES;
            }
            return YES;
        }];
    }];

    return truncated;
}

- (void)encode:(id<iTermEncoderAdapter>)encoder maxLines:(NSInteger)maxLines {
    const BOOL truncated = [self encodeBlocks:encoder maxLines:maxLines];

    [encoder mergeDictionary:
     @{ kLineBufferVersionKey: @(kLineBufferVersion),
        kLineBufferTruncatedKey: @(truncated),
        kLineBufferBlockSizeKey: @(block_size),
        kLineBufferCursorXKey: @(cursor_x),
        kLineBufferCursorRawlineKey: @(cursor_rawline),
        kLineBufferMaxLinesKey: @(max_lines),
        kLineBufferNumDroppedBlocksKey: @(num_dropped_blocks),
        kLineBufferDroppedCharsKey: @(droppedChars),
        kLineBufferMayHaveDWCKey: @(_mayHaveDoubleWidthCharacter) }];
}

- (void)appendMessage:(NSString *)message {
    if (!_lineBlocks.count) {
        [self _addBlockOfSize:message.length];
    }
    screen_char_t defaultBg = { 0 };
    screen_char_t buffer[message.length];
    int len;
    screen_char_t fg = { 0 };
    screen_char_t bg = { 0 };
    fg.foregroundColor = ALTSEM_SYSTEM_MESSAGE;
    fg.backgroundColorMode = ColorModeAlternate;
    bg.backgroundColor = ALTSEM_SYSTEM_MESSAGE;
    bg.backgroundColorMode = ColorModeAlternate;
    StringToScreenChars(message, buffer, fg, bg, &len, NO, NULL, NULL, NO, kUnicodeVersion, NO, NULL);
    [self appendLine:buffer
              length:0
             partial:NO
               width:num_wrapped_lines_width > 0 ?: 80
            metadata:iTermMetadataMakeImmutable(iTermMetadataTemporaryWithTimestamp([NSDate timeIntervalSinceReferenceDate]))
        continuation:defaultBg];

    [self appendLine:buffer
              length:len
             partial:NO
               width:num_wrapped_lines_width > 0 ?: 80
            metadata:iTermMetadataMakeImmutable(iTermMetadataTemporaryWithTimestamp([NSDate timeIntervalSinceReferenceDate]))
        continuation:bg];

    [self appendLine:buffer
              length:0
             partial:NO
               width:num_wrapped_lines_width > 0 ?: 80
            metadata:iTermMetadataMakeImmutable(iTermMetadataTemporaryWithTimestamp([NSDate timeIntervalSinceReferenceDate]))
        continuation:defaultBg];
}

// Note that the current implementation restores appends but not other kinds of
// changes like deleting from the start or end.
- (void)performBlockWithTemporaryChanges:(void (^ NS_NOESCAPE)(void))block {
    _deferSanityCheck++;
    if (gDebugLogging) {
        [_lineBlocks sanityCheck:droppedChars];
    }

    LineBlock *lastBlock = [_lineBlocks.blocks.lastObject cowCopy];
    const int savedMaxLines = max_lines;
    const int savedNumLines = num_wrapped_lines_cache;
    const int savedNumLinesWidth = num_wrapped_lines_width;
    const int savedCursorRawline = cursor_rawline;
    const int savedDroppedChars = droppedChars;
    const int savedNumDroppedBlocks = num_dropped_blocks;
    const int savedCursorX = cursor_x;

    // Don't try to restore _mayHaveDoubleWidthCharacter because setting it also modifies the line
    // blocks. It has to be a monotonic transition and is OK to leave because it's merely a
    // heuristic.

    const NSInteger numberOfBlocks = _lineBlocks.blocks.count;

    max_lines = -1;
    block();
    max_lines = savedMaxLines;
    num_wrapped_lines_cache = savedNumLines;
    num_wrapped_lines_width = savedNumLinesWidth;
    cursor_rawline = savedCursorRawline;
    droppedChars = savedDroppedChars;
    num_dropped_blocks = savedNumDroppedBlocks;
    cursor_x = savedCursorX;

    while (_lineBlocks.blocks.count > numberOfBlocks) {
        [_lineBlocks removeLastBlock];
    }
    if (lastBlock) {
        [_lineBlocks removeLastBlock];
        [_lineBlocks addBlock:lastBlock];
    }
    
    if (gDebugLogging) {
        [_lineBlocks sanityCheck:droppedChars];
    }
    _deferSanityCheck--;
    [self sanityCheck];
}

- (ScreenCharArray *)lastRawLine {
    return _lineBlocks.lastBlock.lastRawLine;
}

#pragma mark - NSCopying

- (LineBlock *)copy {
    return [self copyWithZone:nil];
}

- (id)copyWithZone:(NSZone *)zone {
    LineBuffer *theCopy = [[LineBuffer alloc] initWithBlockSize:block_size];
    theCopy->_lineBlocks = [_lineBlocks copy];
    theCopy->_lineBlocks.delegate = theCopy;
    theCopy->cursor_x = cursor_x;
    theCopy->cursor_rawline = cursor_rawline;
    theCopy->max_lines = max_lines;
    theCopy->num_dropped_blocks = num_dropped_blocks;
    theCopy->num_wrapped_lines_cache = num_wrapped_lines_cache;
    theCopy->num_wrapped_lines_width = num_wrapped_lines_width;
    theCopy->droppedChars = droppedChars;
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
    theCopy->_maintainBidiInfo = _maintainBidiInfo;
    [theCopy sanityCheck];

    return theCopy;
}

- (int)numBlocksAtEndToGetMinimumLines:(int)minLines width:(int)width {
    int numBlocks = 0;
    int lines = 0;
    for (LineBlock *block in _lineBlocks.blocks.reverseObjectEnumerator) {
        int blockLines = [block getNumLinesWithWrapWidth:width];
        if (block.startsWithContinuation) {
            blockLines += [block continuationWrappedLineAdjustmentForWidth:width];
        }
        lines += blockLines;
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
        n += [_lineBlocks[j] numberOfCharacters];
    }
    return n;
}

- (LineBuffer *)copyWithMinimumLines:(int)minLines atWidth:(int)width {
    // Calculate how many blocks to keep.
    const int numBlocks = [self numBlocksAtEndToGetMinimumLines:minLines width:width];
    const int totalBlocks = _lineBlocks.count;
    const int numDroppedBlocks = totalBlocks - numBlocks;

    // Make a copy of the whole thing (cheap)
    LineBuffer *theCopy = [self copy];
    theCopy->_deferSanityCheck++;

    // Remove the blocks we don't need.
    [theCopy->_lineBlocks removeFirstBlocks:numDroppedBlocks];

    // Update stats and nuke cache.
    theCopy->num_dropped_blocks += numDroppedBlocks;
    theCopy->num_wrapped_lines_width = -1;
    theCopy->droppedChars += [self numCharsInRangeOfBlocks:NSMakeRange(0, numDroppedBlocks)];
    theCopy->_deferSanityCheck--;

    return theCopy;
}

- (int)numberOfWrappedLinesWithWidth:(int)width {
    return [_lineBlocks numberOfWrappedLinesForWidth:width];
}

- (int)numberOfWrappedLinesWithWidth:(int)width upToAbsoluteBlockNumber:(int)absBlock {
    if (absBlock <= num_dropped_blocks) {
        return 0;
    }
    return [_lineBlocks numberOfWrappedLinesForWidth:width upToBlockAtIndex:absBlock - num_dropped_blocks];
}

- (void)beginResizing {
    assert(!_lineBlocks.resizing);
    _lineBlocks.resizing = YES;
    _wantsSeal = NO;
    [self removeTrailingEmptyBlocks];
    self.dirty = YES;
}

- (void)endResizing {
    assert(_lineBlocks.resizing);
    _lineBlocks.resizing = NO;
    self.dirty = YES;
}

- (void)setPartial:(BOOL)partial {
    self.dirty = YES;
    [_lineBlocks.lastBlock setPartial:partial];
}

- (BOOL)isPartial {
    return _lineBlocks.lastBlock.hasPartial;
}

- (LineBlock *)testOnlyBlockAtIndex:(int)i {
    return _lineBlocks[i];
}

- (int)testOnlyNumberOfBlocks {
    return (int)_lineBlocks.count;
}

- (void)testOnlyAppendPartialItems:(int)count
                          ofLength:(int)itemLength
                             width:(int)width {
    screen_char_t *buf = (screen_char_t *)calloc(count * itemLength, sizeof(screen_char_t));
    for (int i = 0; i < count * itemLength; i++) {
        buf[i].code = 'A' + (i % 26);
    }
    CTVector(iTermAppendItem) items;
    CTVectorCreate(&items, count);
    for (int i = 0; i < count; i++) {
        iTermAppendItem item = {
            .buffer = buf + i * itemLength,
            .length = itemLength,
            .partial = 1,
            .metadata = iTermImmutableMetadataDefault(),
            .continuation = { 0 }
        };
        item.continuation.code = EOL_SOFT;
        CTVectorAppend(&items, item);
    }
    [self appendLines:&items width:width];
    CTVectorDestroy(&items);
    free(buf);
}

- (void)testOnlyAppendPartialItems:(int)count
                          ofLength:(int)itemLength
                             width:(int)width
                          metadata:(iTermImmutableMetadata)metadata
                      continuation:(screen_char_t)continuation {
    screen_char_t *buf = (screen_char_t *)calloc(count * itemLength, sizeof(screen_char_t));
    for (int i = 0; i < count * itemLength; i++) {
        buf[i].code = 'A' + (i % 26);
    }
    CTVector(iTermAppendItem) items;
    CTVectorCreate(&items, count);
    for (int i = 0; i < count; i++) {
        iTermAppendItem item = {
            .buffer = buf + i * itemLength,
            .length = itemLength,
            .partial = 1,
            .metadata = metadata,
            .continuation = continuation
        };
        CTVectorAppend(&items, item);
    }
    [self appendLines:&items width:width];
    CTVectorDestroy(&items);
    free(buf);
}

- (void)testOnlyAppendItemsWithLengths:(NSArray<NSNumber *> *)lengths
                              partials:(NSArray<NSNumber *> *)partials
                                 width:(int)width {
    NSCParameterAssert(lengths.count == partials.count);
    const int count = (int)lengths.count;
    int totalLength = 0;
    for (NSNumber *n in lengths) {
        totalLength += n.intValue;
    }
    screen_char_t *buf = (screen_char_t *)calloc(totalLength, sizeof(screen_char_t));
    int offset = 0;
    for (int i = 0; i < count; i++) {
        for (int j = 0; j < lengths[i].intValue; j++) {
            buf[offset + j].code = 'A' + ((offset + j) % 26);
        }
        offset += lengths[i].intValue;
    }
    CTVector(iTermAppendItem) items;
    CTVectorCreate(&items, count);
    offset = 0;
    for (int i = 0; i < count; i++) {
        iTermAppendItem item = {
            .buffer = buf + offset,
            .length = lengths[i].intValue,
            .partial = partials[i].boolValue ? 1 : 0,
            .metadata = iTermImmutableMetadataDefault(),
            .continuation = { 0 }
        };
        item.continuation.code = partials[i].boolValue ? EOL_SOFT : EOL_HARD;
        CTVectorAppend(&items, item);
        offset += lengths[i].intValue;
    }
    [self appendLines:&items width:width];
    CTVectorDestroy(&items);
    free(buf);
}

- (unsigned int)numberOfUnwrappedLines {
    unsigned int sum = 0;
    for (LineBlock *block in _lineBlocks.blocks) {
        int n = [block numRawLines];
        if (block.startsWithContinuation) {
            n -= 1;
        }
        sum += n;
    }
    return sum;
}

- (void)ensureLastBlockUncopied {
    LineBlock *lastBlock = _lineBlocks.lastBlock;
    if (lastBlock.hasPartial) {
        // Can't have an interior block that is partial.
        _wantsSeal = YES;
        return;
    }
    if (!lastBlock.hasBeenCopied) {
        return;
    }
    [self seal];
}

- (void)seal {
    if (_lineBlocks.lastBlock.hasPartial) {
        // Can't have an interior block that is partial.
        return;
    }
    if (_lineBlocks.lastBlock.rawSpaceUsed < 1024) {
        // Avoid accruing lots of tiny blocks.
        return;
    }
    self.dirty = YES;
    if (_lineBlocks.lastBlock == nil || _lineBlocks.lastBlock.isEmpty) {
        return;
    }
    [self _addBlockOfSize:block_size];
}

- (void)forceSeal {
    assert(!_lineBlocks.lastBlock.hasPartial);
    assert(_lineBlocks.lastBlock != nil);
    assert(!_lineBlocks.lastBlock.isEmpty);
    self.dirty = YES;
    [self _addBlockOfSize:block_size];
}

- (void)forceMergeFrom:(LineBuffer *)source {
    source.dirty = YES;
    [self mergeFrom:source];
}

- (void)mergeFrom:(LineBuffer *)source {
    _deferSanityCheck++;
    [self reallyMergeFrom:source];
    _deferSanityCheck--;
    [self sanityCheck];
}

- (void)reallyMergeFrom:(LineBuffer *)source {
    // State used when debugging
    NSSet<NSNumber *> *commonWidths = nil;
    NSString *before = nil;
    NSString *stage1 = nil;
    NSString *stage2 = nil;
    NSString *stage3 = nil;
    NSString *stage4 = nil;

    if (gDebugLogging) {
        DLog(@"merge");
        [_lineBlocks sanityCheck:droppedChars];
        [source->_lineBlocks sanityCheck:source->droppedChars];
        commonWidths = [[_lineBlocks cachedWidths] setByIntersectingWithSet:source->_lineBlocks.cachedWidths];
        before = [_lineBlocks dumpWidths:commonWidths];
    }

    assert(source != nil);
    if (!source.dirty) {
        return;
    }
    source.dirty = NO;

    cursor_x = source->cursor_x;
    cursor_rawline = source->cursor_rawline;
    max_lines = source->max_lines;
    num_wrapped_lines_cache = source->num_wrapped_lines_cache;
    num_wrapped_lines_width = source->num_wrapped_lines_width;
    droppedChars = source->droppedChars;
    _mayHaveDoubleWidthCharacter = source->_mayHaveDoubleWidthCharacter;

    // Drop initial blocks
    while (_lineBlocks.firstBlock != nil &&
           _lineBlocks.firstBlock.progenitor != source->_lineBlocks.firstBlock) {
        DLog(@"Drop initial");
        [_lineBlocks removeFirstBlock];
        ++num_dropped_blocks;
    }
    if (gDebugLogging) {
        stage1 = [_lineBlocks dumpWidths:commonWidths];
    }

    // Drop blocks from the end until we get to one that is in sync.
    // Note that if the first block has experienced drops but not appends then it will still have
    // its progenitor as its owner and be considered "synchronized".
    while (_lineBlocks.count > 0 && ![_lineBlocks.lastBlock isSynchronizedWithProgenitor]) {
        DLog(@"remove last");
        [_lineBlocks removeLastBlock];
    }
    if (gDebugLogging) {
        stage2 = [_lineBlocks dumpWidths:commonWidths];
    }

    if (_lineBlocks.count > 0) {
        DLog(@"mirror first");
        [_lineBlocks.firstBlock dropMirroringProgenitor:source->_lineBlocks.firstBlock];
    }
    if (gDebugLogging) {
        stage3 = [_lineBlocks dumpWidths:commonWidths];
    }

    // Add copies of terminal blocks.
    while (_lineBlocks.count < source->_lineBlocks.count) {
        DLog(@"append");
        LineBlock *sourceBlock = source->_lineBlocks[_lineBlocks.count];
        LineBlock *theCopy = [sourceBlock cowCopy];
        [_lineBlocks addBlock:theCopy];
        if (_lineBlocks.count < source->_lineBlocks.count) {
            [self commitLastBlock];
        }
        if (gDebugLogging) {
            [_lineBlocks sanityCheck:droppedChars];
        }
    }

    num_dropped_blocks = source->num_dropped_blocks;
    //assert([self isEqual:source]);

    if (gDebugLogging) {
        stage4 = [_lineBlocks dumpWidths:commonWidths];

        if (![[_lineBlocks dumpWidths:commonWidths] isEqual:[source->_lineBlocks dumpWidths:commonWidths]]) {
            DLog(@"Before:\n%@\nAfter:\n%@\nExpected:\n%@",
                 before,
                 [_lineBlocks dumpWidths:commonWidths],
                 [source->_lineBlocks dumpWidths:commonWidths]);
            DLog(@"Stage 1:\n%@", stage1);
            DLog(@"Stage 2:\n%@", stage2);
            DLog(@"Stage 3:\n%@", stage3);
            DLog(@"Stage 4:\n%@", stage4);
        }
    }
    [self sanityCheck];
}

- (BOOL)isEqual:(LineBuffer *)other {
    if (![other isKindOfClass:[LineBuffer class]]) {
        return NO;
    }
    if (block_size != other->block_size) {
        return NO;
    }
    if (cursor_x != other->cursor_x) {
        return NO;
    }
    if (cursor_rawline != other->cursor_rawline) {
        return NO;
    }
    if (max_lines != other->max_lines) {
        return NO;
    }
    if (num_dropped_blocks != other->num_dropped_blocks) {
        return NO;
    }
    if (droppedChars != other->droppedChars) {
        return NO;
    }

    return [_lineBlocks isEqual:other->_lineBlocks];
}

- (long long)safeAbsoluteBlockNumber:(long long)unsafe {
    assert(_lineBlocks.count > 0);

    if (unsafe < num_dropped_blocks) {
        return num_dropped_blocks;
    }
    const long long limit = num_dropped_blocks + _lineBlocks.count;
    if (unsafe >= limit) {
        return limit - 1;
    }
    return unsafe;
}

- (NSInteger)numberOfCellsUsedInWrappedLineRange:(VT100GridRange)wrappedLineRange
                                           width:(int)width {
    if (wrappedLineRange.length <= 0) {
        return 0;
    }
    const int firstWrappedLine = wrappedLineRange.location;
    const int lastWrappedLine = wrappedLineRange.location + wrappedLineRange.length - 1;
    int remainder = 0;
    const NSInteger firstBlockIndex = [_lineBlocks indexOfBlockContainingLineNumber:firstWrappedLine
                                                                              width:width
                                                                          remainder:&remainder];
    if (firstBlockIndex == NSNotFound) {
        return 0;
    }
    const NSInteger lastBlockIndex = [_lineBlocks indexOfBlockContainingLineNumber:lastWrappedLine
                                                                             width:width
                                                                         remainder:&remainder];
    if (lastBlockIndex == NSNotFound) {
        return 0;
    }

    __block NSInteger sum = 0;
    [_lineBlocks enumerateLinesInRange:NSMakeRange(firstWrappedLine, wrappedLineRange.length)
                                 width:width
                                 block:^(const screen_char_t * _Nonnull chars,
                                         int length,
                                         int eol,
                                         screen_char_t continuation,
                                         iTermImmutableMetadata metadata,
                                         BOOL * _Nullable stop) {
        (void)chars;
        (void)eol;
        (void)continuation;
        (void)metadata;
        (void)stop;
        sum += length;
    }];
    return sum;
}

- (int)numberOfWrappedLinesAtPartialEndforWidth:(int)width {
    LineBlock *block = _lineBlocks.lastBlock;
    if (!block) {
        return 0;
    }
    if (!block.hasPartial) {
        return 0;
    }
    return [block numberOfWrappedLinesForLastRawLineWrappedToWidth:width];
}

- (NSInteger)numberOfUnwrappedLinesInRange:(VT100GridRange)range width:(int)width {
    return [_lineBlocks numberOfRawLinesInRange:NSMakeRange(range.location, range.length)
                                          width:width];
}

#pragma mark - iTermLineBlockArrayDelegate

- (void)lineBlockArrayDidChange:(iTermLineBlockArray *)lineBlockArray {
    [self sanityCheck];
}

@end
