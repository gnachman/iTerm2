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
}

@synthesize mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
@synthesize delegate = _delegate;

// Append a block
- (LineBlock *)_addBlockOfSize:(int)size {
    self.dirty = YES;
    // Immediately shrink it so that it can compress down to the smallest
    // possible size. The compression code has no way of knowing how big these
    // buffers are.
    [_lineBlocks.lastBlock shrinkToFit];
    return [_lineBlocks addBlockOfSize:size
                                number:num_dropped_blocks + _lineBlocks.count
           mayHaveDoubleWidthCharacter:self.mayHaveDoubleWidthCharacter];
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
    _lineBlocks = [[iTermLineBlockArray alloc] init];
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

- (LineBuffer *)initWithDictionary:(NSDictionary *)dictionary {
    self = [super init];
    if (self) {
        [self commonInit];
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
            [_lineBlocks addBlock:block];
        }
    }
    return self;
}

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
    self.dirty = YES;
    int nl = RawNumLines(self, width);
    int totalDropped = 0;
    int totalRawLinesDropped = 0;
    if (max_lines != -1 && nl > max_lines) {
        LineBlock *block = _lineBlocks[0];
        int total_lines = nl;
        while (total_lines > max_lines) {
            int extra_lines = total_lines - max_lines;

            int block_lines = [block getNumLinesWithWrapWidth: width];
#if ITERM_DEBUG
            ITAssertWithMessage(block_lines > 0, @"Empty leading block");
#endif
            int toDrop = block_lines;
            if (toDrop > extra_lines) {
                toDrop = extra_lines;
            }
            int charsDropped;
            const int numRawLinesBefore = block.numRawLines;
            int dropped = [block dropLines:toDrop withWidth:width chars:&charsDropped];
            totalDropped += dropped;
            const int numRawLinesAfter = block.numRawLines;
            assert(numRawLinesAfter <= numRawLinesBefore);
            totalRawLinesDropped += (numRawLinesBefore - numRawLinesAfter);
            droppedChars += charsDropped;
            if ([block isEmpty]) {
                [_lineBlocks removeFirstBlock];
                ++num_dropped_blocks;
                if (_lineBlocks.count > 0) {
                    block = _lineBlocks[0];
                }
            }
            total_lines -= dropped;
        }
        num_wrapped_lines_cache = total_lines;
    }
    cursor_rawline -= totalRawLinesDropped;
    [_delegate lineBufferDidDropLines:self];
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
        VLog(@"Block %d:\n", i);
        [_lineBlocks[i] dump:rawOffset toDebugLog:NO];
        rawOffset += [_lineBlocks[i] rawSpaceUsed];
    }
}
- (NSString *)dumpString {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    int i;
    for (i = 0; i < _lineBlocks.count; ++i) {
        [strings addObject:[NSString stringWithFormat:@"Block %d:", i]];
        [strings addObject:_lineBlocks[i].dumpString];
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
    self.dirty = YES;
#ifdef LOG_MUTATIONS
    NSLog(@"Append: %@\n", ScreenCharArrayToStringDebug(buffer, length));
#endif
    if (_lineBlocks.count == 0) {
        [self _addBlockOfSize:block_size];
    }

    LineBlock *block = _lineBlocks.lastBlock;

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
    if (_wantsSeal) {
        _wantsSeal = NO;
        [self ensureLastBlockUncopied];
    }
}

- (iTermImmutableMetadata)metadataForLineNumber:(int)lineNumber width:(int)width {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNumber
                                                        width:width
                                                    remainder:&remainder];
    return [block metadataForLineNumber:remainder width:width];
}

- (iTermImmutableMetadata)metadataForRawLineWithWrappedLineNumber:(int)lineNum width:(int)width {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder];
    return [block metadataForRawLineAtWrappedLineOffset:remainder width:width];
}

// Copy a line into the buffer. If the line is shorter than 'width' then only
// the first 'width' characters will be modified.
// 0 <= lineNum < numLinesWithWidth:width
- (int)copyLineToBuffer:(screen_char_t *)buffer
                  width:(int)width
                lineNum:(int)lineNum
           continuation:(screen_char_t *)continuationPtr {
    ITBetaAssert(lineNum >= 0, @"Negative lineNum to copyLineToBuffer");
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder];
    ITBetaAssert(remainder >= 0, @"Negative lineNum BEFORE consuming block_lines");
    if (!block) {
        NSLog(@"Couldn't find line %d", lineNum);
        ITAssertWithMessage(NO, @"Tried to get non-existent line");
        return NO;
    }

    int length;
    int eol;
    screen_char_t continuation;
    const int requestedLine = remainder;
    const screen_char_t *p = [block getWrappedLineWithWrapWidth:width
                                                        lineNum:&remainder
                                                     lineLength:&length
                                              includesEndOfLine:&eol
                                                   continuation:&continuation];
    if (p == nil) {
        ITAssertWithMessage(NO, @"Nil wrapped line %@ for block with width %@", @(requestedLine), @(width));
        return NO;
    }

    if (continuationPtr) {
        *continuationPtr = continuation;
    }
    ITAssertWithMessage(length <= width, @"Length too long");
    if (length > 0 && p[0].code ^ p[length - 1].code) {
        // This is here to figure out if a segfault I see a lot of is due to reading or writing.
        // If it crashes in the if statement's condition, it's on the read side.
        // If it crashes in memcpy/memmove below it's on the write side.
        DLog(@"*p");
    }
    memcpy((char*) buffer, (char*) p, length * sizeof(screen_char_t));
    [self extendContinuation:continuation inBuffer:buffer ofLength:length toWidth:width];

    if (requestedLine == 0 && [iTermAdvancedSettingsModel showBlockBoundaries]) {
        for (int i = 0; i < width; i++) {
            buffer[i].code = 'X';
            buffer[i].complexChar = NO;
            buffer[i].image = NO;
        }
    }
    return eol;
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

- (int)appendContentsOfLineBuffer:(LineBuffer *)other width:(int)width includingCursor:(BOOL)cursor {
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
    }
    if (cursor) {
        cursor_rawline = other->cursor_rawline + offset;
        cursor_x = other->cursor_x;
    }

    num_wrapped_lines_width = -1;
    return [self dropExcessLinesWithWidth:width];
}

- (ScreenCharArray *)screenCharArrayForLine:(int)line
                                      width:(int)width
                                   paddedTo:(int)paddedSize
                             eligibleForDWC:(BOOL)eligibleForDWC {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:line width:width remainder:&remainder];
    if (!block) {
        ITAssertWithMessage(NO, @"Failed to find line %@ with width %@. Cache is: %@", @(line), @(width),
                            [[[[_lineBlocks dumpForCrashlog] dataUsingEncoding:NSUTF8StringEncoding] it_compressedData] it_hexEncoded]);
        return nil;
    }
    return [block screenCharArrayForWrappedLineWithWrapWidth:width
                                                     lineNum:remainder
                                                    paddedTo:paddedSize
                                              eligibleForDWC:eligibleForDWC];
}

- (ScreenCharArray *)wrappedLineAtIndex:(int)lineNum
                                  width:(int)width {
    return [self wrappedLineAtIndex:lineNum width:width continuation:NULL];
}

- (ScreenCharArray *)wrappedLineAtIndex:(int)lineNum
                                  width:(int)width
                           continuation:(screen_char_t *)continuationPtr {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder];
    if (!block) {
        ITAssertWithMessage(NO, @"Failed to find line %@ with width %@. Cache is: %@", @(lineNum), @(width),
                            [[[[_lineBlocks dumpForCrashlog] dataUsingEncoding:NSUTF8StringEncoding] it_compressedData] it_hexEncoded]);
        return nil;
    }

    int length, eol;
    screen_char_t continuation;
    const screen_char_t *line = [block getWrappedLineWithWrapWidth:width
                                                           lineNum:&remainder
                                                        lineLength:&length
                                                 includesEndOfLine:&eol
                                                      continuation:&continuation];
    if (continuationPtr) {
        *continuationPtr = continuation;
    }
    if (!line) {
        NSLog(@"Couldn't find line %d", lineNum);
        ITAssertWithMessage(NO, @"Tried to get non-existent line");
        return nil;
    }
    ScreenCharArray *result = [[ScreenCharArray alloc] initWithLine:line
                                                             length:length
                                                       continuation:continuation];
    ITAssertWithMessage(result.length <= width, @"Length too long");
    return result;
}

- (ScreenCharArray * _Nonnull)rawLineAtWrappedLine:(int)lineNum width:(int)width {
    int remainder = 0;
    LineBlock *block = [_lineBlocks blockContainingLineNumber:lineNum width:width remainder:&remainder];
    return [block rawLineAtWrappedLineOffset:remainder width:width];
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
        block(count++, array, metadata, stop);
    }];
}

- (int)numLinesWithWidth:(int)width {
    if (width == 0) {
        return 0;
    }
    return RawNumLines(self, width);
}

- (void)removeLastRawLine {
    self.dirty = YES;
    [_lineBlocks.lastBlock removeLastRawLine];
    if (_lineBlocks.lastBlock.numRawLines == 0 && _lineBlocks.count > 1) {
        [_lineBlocks removeLastBlock];
    }
    // Invalidate the cache
    num_wrapped_lines_width = -1;
}

- (void)removeLastWrappedLines:(int)numberOfLinesToRemove
                         width:(int)width {
    self.dirty = YES;
    // Invalidate the cache
    num_wrapped_lines_width = -1;

    int linesToRemoveRemaining = numberOfLinesToRemove;
    while (linesToRemoveRemaining > 0 && _lineBlocks.count > 0) {
        LineBlock *block = _lineBlocks.lastBlock;
        const int numberOfLinesInBlock = [block getNumLinesWithWrapWidth:width];
        if (numberOfLinesInBlock > linesToRemoveRemaining) {
            // Keep part of block
            [block removeLastWrappedLines:linesToRemoveRemaining width:width];
            return;
        }
        // Remove the whole block and try again.
        [_lineBlocks removeLastBlock];
        linesToRemoveRemaining -= numberOfLinesInBlock;
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
    while (_lineBlocks.count && _lineBlocks.lastBlock.isEmpty) {
        [_lineBlocks removeLastBlock];
        num_wrapped_lines_width = -1;
    }
}

- (BOOL)popAndCopyLastLineInto:(screen_char_t*)ptr
                         width:(int)width
             includesEndOfLine:(int*)includesEndOfLine
                      metadata:(out iTermImmutableMetadata *)metadataPtr
                  continuation:(screen_char_t *)continuationPtr {
    if ([self numLinesWithWidth:width] == 0) {
        return NO;
    }
    [self removeTrailingEmptyBlocks];
    self.dirty = YES;
    num_wrapped_lines_width = -1;

    LineBlock* block = _lineBlocks.lastBlock;

    // If the line is partial the client will want to add a continuation marker so
    // tell him there's no EOL in that case.
    *includesEndOfLine = [block hasPartial] ? EOL_SOFT : EOL_HARD;

    // Pop the last up-to-width chars off the last line.
    int length;
    const screen_char_t *temp;
    screen_char_t continuation;
    BOOL ok __attribute__((unused)) =
    [block popLastLineInto:&temp
                withLength:&length
                 upToWidth:width
                  metadata:metadataPtr
              continuation:&continuation];
    if (continuationPtr) {
        *continuationPtr = continuation;
    }
    ITAssertWithMessage(ok, @"Unexpected empty block");
    ITAssertWithMessage(length <= width, @"Length too large");
    ITAssertWithMessage(length >= 0, @"Negative length");

    // Copy into the provided buffer.
    memcpy(ptr, temp, sizeof(screen_char_t) * length);
    [self extendContinuation:continuation inBuffer:ptr ofLength:length toWidth:width];

    // Clean up the block if the whole thing is empty, otherwise another call
    // to this function would not work correctly.
    if ([block isEmpty]) {
        [_lineBlocks removeLastBlock];
    }

#ifdef LOG_MUTATIONS
    NSLog(@"Pop: %@\n", ScreenCharArrayToStringDebug(ptr, width));
#endif
    return YES;
}

NS_INLINE int TotalNumberOfRawLines(LineBuffer *self) {
    return self->_lineBlocks.numberOfRawLines;
}

- (void)setCursor:(int)x {
    self.dirty = YES;
    LineBlock *block = _lineBlocks.lastBlock;
    if ([block hasPartial]) {
        int last_line_length = [block getRawLineLength: [block numEntries]-1];
        cursor_x = x + last_line_length;
        cursor_rawline = -1;
    } else {
        cursor_x = x;
        cursor_rawline = 0;
    }

    cursor_rawline += TotalNumberOfRawLines(self);
}

- (BOOL)getCursorInLastLineWithWidth:(int)width atX:(int *)x {
    int total_raw_lines = TotalNumberOfRawLines(self);
    if (cursor_rawline == total_raw_lines-1) {
        // The cursor is on the last line in the buffer.
        LineBlock* block = _lineBlocks.lastBlock;
        int last_line_length = [block getRawLineLength: ([block numEntries]-1)];
        const screen_char_t *lastRawLine = [block rawLine: ([block numEntries]-1)];
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
        context.offset = offset;
        context.absBlockNum = absBlockNum + num_dropped_blocks;
        context.status = Searching;
    } else {
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

    BOOL includesPartialLastLine = NO;
    [block findSubstring:context.substring
                 options:context.options
                    mode:context.mode
                atOffset:context.offset
                 results:context.results
         multipleResults:((context.options & FindMultipleResults) != 0)
 includesPartialLastLine:&includesPartialLastLine];
    context.includesPartialLastLine = includesPartialLastLine && (blockIndex + 1 == numBlocks);
    NSMutableArray* filtered = [NSMutableArray arrayWithCapacity:[context.results count]];
    BOOL haveOutOfRangeResults = NO;
    int blockPosition = [self _blockPosition:context.absBlockNum - num_dropped_blocks];
    const int stopAt = stopPosition.absolutePosition - droppedChars;
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
- (NSArray *)convertPositions:(NSArray *)resultRanges withWidth:(int)width {
    if (width <= 0) {
        return nil;
    }
    int *sortedPositions = SortedPositionsFromResultRanges(resultRanges);
    int i = 0;
    int yoffset = 0;
    int numBlocks = _lineBlocks.count;
    int passed = 0;
    LineBlock *block = _lineBlocks[0];
    int used = [block rawSpaceUsed];

    LineBufferSearchIntermediateMap *intermediate = [[LineBufferSearchIntermediateMap alloc] initWithCapacity:resultRanges.count * 2];
    int prev = -1;
    const int numPositions = resultRanges.count * 2;
    for (int j = 0; j < numPositions; j++) {
        const int position = sortedPositions[j];
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
                block = _lineBlocks.blocks[i];
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
                                     wrapOnEOL:YES
                                           toX:&x
                                           toY:&y];
            assert(x < 2000);
            if (isOk) {
                y += yoffset;
                [intermediate addCoordinate:VT100GridCoordMake(x, y)
                                forPosition:position];
            } else {
                assert(false);
            }
        }
    }

    // Walk the positions array and populate results by looking up points in intermediate dict.
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[resultRanges count] * 2];
    [intermediate enumerateCoordPairsForRanges:resultRanges block:^(VT100GridCoord start, VT100GridCoord end) {
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
    if (context.absBlockNum > num_dropped_blocks) {
        // Before beginning
        return [self firstPosition];
    }
    int blockNumber = context.absBlockNum - num_dropped_blocks;
    LineBufferPosition *position = [LineBufferPosition position];
    const long long precedingBlocksLength = [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, blockNumber)];
    position.absolutePosition = precedingBlocksLength + context.offset;
    position.yOffset = 0;
    position.extendsToEndOfLine = NO;
    return position;
}

- (LineBufferPosition *)positionForCoordinate:(VT100GridCoord)coord
                                        width:(int)width
                                       offset:(int)offset {
    VLog(@"positionForCoord:%@ width:%@ offset:%@", VT100GridCoordDescription(coord), @(width), @(offset));
    
    int x = coord.x;
    int y = coord.y;
    int line = y;
    NSInteger index = [_lineBlocks indexOfBlockContainingLineNumber:y width:width remainder:&line];
    if (index == NSNotFound) {
        VLog(@"positionForCoord returning nil because indexOfBlockCOntainingLineNumber returned NSNotFound");
        return nil;
    }

    LineBlock *block = _lineBlocks[index];
    long long absolutePosition = droppedChars + [_lineBlocks rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, index)];
    VLog(@"positionForCoord: Absolute position of block %@ is %@", @(index), @(absolutePosition));
    int pos;
    int yOffset = 0;  // Number of lines from start of block to coord
    BOOL extends = NO;
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

- (long long)absPositionForPosition:(int)pos
{
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
            numLines += [block getNumLinesWithWrapWidth:80];
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
    StringToScreenChars(message, buffer, fg, bg, &len, NO, NULL, NULL, NO, kUnicodeVersion, NO);
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
    if (gDebugLogging) {
        [_lineBlocks sanityCheck];
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
        [_lineBlocks sanityCheck];
    }
}


#pragma mark - NSCopying

- (LineBlock *)copy {
    return [self copyWithZone:nil];
}

- (id)copyWithZone:(NSZone *)zone {
    LineBuffer *theCopy = [[LineBuffer alloc] initWithBlockSize:block_size];
    theCopy->_lineBlocks = [_lineBlocks copy];
    theCopy->cursor_x = cursor_x;
    theCopy->cursor_rawline = cursor_rawline;
    theCopy->max_lines = max_lines;
    theCopy->num_dropped_blocks = num_dropped_blocks;
    theCopy->num_wrapped_lines_cache = num_wrapped_lines_cache;
    theCopy->num_wrapped_lines_width = num_wrapped_lines_width;
    theCopy->droppedChars = droppedChars;
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;

    return theCopy;
}

- (int)numBlocksAtEndToGetMinimumLines:(int)minLines width:(int)width {
    int numBlocks = 0;
    int lines = 0;
    for (LineBlock *block in _lineBlocks.blocks.reverseObjectEnumerator) {
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

    // Remove the blocks we don't need.
    [theCopy->_lineBlocks removeFirstBlocks:numDroppedBlocks];

    // Update stats and nuke cache.
    theCopy->num_dropped_blocks += numDroppedBlocks;
    theCopy->num_wrapped_lines_width = -1;
    theCopy->droppedChars += [self numCharsInRangeOfBlocks:NSMakeRange(0, numDroppedBlocks)];

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

- (LineBlock *)testOnlyBlockAtIndex:(int)i {
    return _lineBlocks[i];
}

- (unsigned int)numberOfUnwrappedLines {
    unsigned int sum = 0;
    for (LineBlock *block in _lineBlocks.blocks) {
        sum += [block numRawLines];
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
    self.dirty = YES;
    if (_lineBlocks.lastBlock == nil || _lineBlocks.lastBlock.isEmpty) {
        return;
    }
    [self _addBlockOfSize:block_size];
}

- (void)forceMergeFrom:(LineBuffer *)source {
    source.dirty = YES;
    [self mergeFrom:source];
}

- (void)mergeFrom:(LineBuffer *)source {
    // State used when debugging
    NSSet<NSNumber *> *commonWidths = nil;
    NSString *before = nil;
    NSString *stage1 = nil;
    NSString *stage2 = nil;
    NSString *stage3 = nil;
    NSString *stage4 = nil;

    if (gDebugLogging) {
        DLog(@"merge");
        [_lineBlocks sanityCheck];
        [source->_lineBlocks sanityCheck];
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
        if (gDebugLogging) {
            [_lineBlocks sanityCheck];
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
    const int y1 = wrappedLineRange.location;
    const int y2 = VT100GridRangeMax(wrappedLineRange);
    
    int startLine = y1;
    const NSInteger firstBlockIndex = [_lineBlocks indexOfBlockContainingLineNumber:y1
                                                                              width:width
                                                                          remainder:&startLine];
    if (firstBlockIndex == NSNotFound) {
        return 0;
    }

    int lastLine = y2;
    const NSInteger lastBlockIndex = [_lineBlocks indexOfBlockContainingLineNumber:y2
                                                                             width:width
                                                                         remainder:&lastLine];
    if (lastBlockIndex == NSNotFound) {
        return 0;
    }

    NSInteger sum = 0;
    for (NSInteger i = firstBlockIndex; i <= lastBlockIndex; i++) {
        NSInteger size = [_lineBlocks[i] sizeFromLine:startLine width:width];
        startLine = 0;
        if (i == lastBlockIndex) {
            size -= [_lineBlocks[i] sizeFromLine:lastLine width:width];
        }
        sum += size;
    }
    return sum;
}

@end
