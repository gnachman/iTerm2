//
//  iTermLineBlockArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import "iTermLineBlockArray.h"

#import "DebugLogging.h"
#import "LineBlock.h"

@interface iTermLineBlockArray()<iTermLineBlockObserver>
@end

@implementation iTermLineBlockArray {
    NSMutableArray<LineBlock *> *_blocks;
    NSInteger _width;  // width for the cache
    NSInteger _offset;  // Number of lines removed from the head
    NSMutableArray<NSNumber *> *_cache;  // If nonnil, gives the cumulative number of lines for each block and is 1:1 with _blocks
    NSMutableArray<NSNumber *> *_numLines;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = [NSMutableArray array];
        _width = -1;
    }
    return self;
}

- (void)dealloc {
    // This causes the blocks to be released in a background thread.
    // When a LineBuffer is really gigantic, it can take
    // quite a bit of time to release all the blocks.
    for (LineBlock *block in _blocks) {
        [block removeObserver:self];
    }
    NSMutableArray<LineBlock *> *blocks = _blocks;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [blocks removeAllObjects];
    });
}

#pragma mark - High level methods

- (void)setAllBlocksMayHaveDoubleWidthCharacters {
    for (LineBlock *block in _blocks) {
        block.mayHaveDoubleWidthCharacter = YES;
    }
    _cache = nil;
    _numLines = nil;
    _width = -1;
}

- (void)buildCacheForWidth:(int)width {
    _offset = 0;
    _width = width;
    _cache = [NSMutableArray array];
    _numLines = [NSMutableArray array];
    NSInteger sum = 0;
    for (LineBlock *block in _blocks) {
        int block_lines = [block getNumLinesWithWrapWidth:width];
        sum += block_lines;
        [_cache addObject:@(sum)];
        [_numLines addObject:@(block_lines)];
    }
}

- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    if (width != _width) {
        _cache = nil;
        _numLines = nil;
    }
    if (!_cache) {
        [self buildCacheForWidth:width];
    }
    if (_cache) {
        return [self fastIndexOfBlockContainingLineNumber:lineNumber remainder:remainderPtr verbose:NO];
    }

    return [self slowIndexOfBlockContainingLineNumber:lineNumber width:width remainder:remainderPtr verbose:NO];
}

- (NSInteger)fastIndexOfBlockContainingLineNumber:(int)lineNumber remainder:(out nonnull int *)remainderPtr verbose:(BOOL)verbose {
    // Subtract the offset because the offset is negative and our line numbers are higher than what is exposed by the interface.
    const NSInteger absoluteLineNumber = lineNumber - _offset;
    if (verbose) {
        NSLog(@"Begin fast search for line number %@, absolute line number %@", @(lineNumber), @(absoluteLineNumber));
    }
    const NSInteger insertionIndex = [_cache indexOfObject:@(absoluteLineNumber)
                                             inSortedRange:NSMakeRange(0, _cache.count)
                                                   options:NSBinarySearchingInsertionIndex
                                           usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                               return [obj1 compare:obj2];
                                           }];
    if (verbose) {
        NSLog(@"Binary search gave me insertion index %@. Cache for that one is %@", @(insertionIndex), _cache[insertionIndex]);
    }

    NSInteger index = insertionIndex;
    while (index + 1 < _cache.count &&
           _cache[index].integerValue == absoluteLineNumber) {
        index++;
        if (verbose) {
            NSLog(@"The cache entry exactly equals the line number so advance to index %@ with cache value %@", @(index), _cache[index]);
        }
    }
    if (index == _cache.count) {
        return NSNotFound;
    }

    if (remainderPtr) {
        if (index == 0) {
            if (verbose) {
                NSLog(@"Index is 0 so return block 0 and remainder of %@", @(lineNumber));
            }
            *remainderPtr = lineNumber;
        } else {
            if (verbose) {
                NSLog(@"Remainder is absoluteLineNumber-cache[i-1]: %@ - %@",
                      @(absoluteLineNumber),
                      _cache[index - 1]);
            }
            *remainderPtr = absoluteLineNumber - _cache[index - 1].integerValue;
        }
    }
    if (verbose) {
        NSLog(@"Return index %@", @(index));
    }
    return index;
}

- (NSInteger)slowIndexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr verbose:(BOOL)verbose {
    int line = lineNumber;
    if (verbose) {
        NSLog(@"Begin SLOW search for line number %@", @(lineNumber));
    }
    for (NSInteger i = 0; i < _blocks.count; i++) {
        if (verbose) {
            NSLog(@"Block %@", @(i));
        }
        if (line == 0) {
            // I don't think a block will ever have 0 lines, but this prevents an infinite loop if that does happen.
            *remainderPtr = 0;
            if (verbose) {
                NSLog(@"hm, line is 0. All done I guess");
            }
            return i;
        }
        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        LineBlock *block = _blocks[i];
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines <= line) {
            line -= block_lines;
            if (verbose) {
                NSLog(@"Consume %@ lines from block %@. Have %@ more to go.", @(block_lines), @(i), @(line));
            }
            continue;
        }

        if (verbose) {
            NSLog(@"Result is at block %@ with a remainder of %@", @(i), @(line));
        }
        if (remainderPtr) {
            *remainderPtr = line;
        }
        assert(line < block_lines);
        return i;
    }
    return NSNotFound;
}

- (LineBlock *)blockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    int remainder = 0;
    NSInteger i = [self indexOfBlockContainingLineNumber:lineNumber
                                                   width:width
                                               remainder:&remainder];
    if (i == NSNotFound) {
        return nil;
    }
    LineBlock *block = _blocks[i];

    if (remainderPtr) {
        *remainderPtr = remainder;
        int nl = [block getNumLinesWithWrapWidth:width];
        assert(*remainderPtr < nl);
    }
    return block;
}

- (int)numberOfWrappedLinesForWidth:(int)width {
    int count = 0;
    for (LineBlock *block in _blocks) {
        count += [block getNumLinesWithWrapWidth:width];
    }
    return count;
}

- (void)enumerateLinesInRange:(NSRange)range
                        width:(int)width
                        block:(void (^)(screen_char_t * _Nonnull, int, int, screen_char_t, BOOL * _Nonnull))callback {
    int remainder;
    NSInteger startIndex = [self indexOfBlockContainingLineNumber:range.location width:width remainder:&remainder];
    ITAssertWithMessage(startIndex != NSNotFound, @"Line %@ not found", @(range.location));
    
    int numberLeft = range.length;
    ITAssertWithMessage(numberLeft >= 0, @"Invalid length in range %@", NSStringFromRange(range));
    for (NSInteger i = startIndex; i < _blocks.count; i++) {
        LineBlock *block = _blocks[i];
        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines <= remainder) {
            remainder -= block_lines;
            continue;
        }

        // Grab lines from this block until we're done or reach the end of the block.
        BOOL stop = NO;
        do {
            int length, eol;
            screen_char_t continuation;
            screen_char_t *chars = [block getWrappedLineWithWrapWidth:width
                                                              lineNum:&remainder
                                                           lineLength:&length
                                                    includesEndOfLine:&eol
                                                         continuation:&continuation];
            if (chars == NULL) {
                return;
            }
            NSAssert(length <= width, @"Length too long");
            callback(chars, length, eol, continuation, &stop);
            if (stop) {
                return;
            }
            numberLeft--;
            remainder++;
        } while (numberLeft > 0 && block_lines >= remainder);
        if (numberLeft == 0) {
            break;
        }
    }
    ITAssertWithMessage(numberLeft == 0, @"not all lines available in range %@. Have %@ remaining.", NSStringFromRange(range), @(numberLeft));
}

- (NSInteger)numberOfRawLines {
    NSInteger sum = 0;
    for (LineBlock *block in _blocks) {
        sum += [block numRawLines];
    }
    return sum;
}

- (NSInteger)rawSpaceUsed {
    return [self rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, _blocks.count)];
}

- (NSInteger)rawSpaceUsedInRangeOfBlocks:(NSRange)range {
    NSInteger position = 0;
    for (NSInteger i = 0; i < range.length; i++) {
        LineBlock *block = _blocks[i + range.location];
        position += [block rawSpaceUsed];
    }
    return position;
}

- (LineBlock *)blockContainingPosition:(long long)position
                                 width:(int)width
                             remainder:(int *)remainderPtr
                           blockOffset:(int *)yoffsetPtr
                                 index:(int *)indexPtr {
    long long p = position;
    int yoffset = 0;
    int index = 0;
    for (LineBlock *block in _blocks) {
        const int used = [block rawSpaceUsed];
        if (p >= used) {
            p -= used;
            if (yoffsetPtr) {
                yoffset += [block getNumLinesWithWrapWidth:width];
            }
        } else {
            if (remainderPtr) {
                *remainderPtr = p;
            }
            if (yoffsetPtr) {
                *yoffsetPtr = yoffset;
            }
            if (indexPtr) {
                *indexPtr = index;
            }
            return block;
        }
        index++;
    }
    return nil;

}
#pragma mark - Low level method

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return _blocks[index];
}

- (void)addBlock:(LineBlock *)block {
    [block addObserver:self];
    [_blocks addObject:block];
    if (_cache) {
        [_cache addObject:_cache.lastObject];
        [_numLines addObject:@0];
        // The block might not be empty. Treat it like a bunch of lines just got appended.
        [self updateCacheForBlock:block];
    }
}

- (void)removeFirstBlock {
    [_blocks.firstObject removeObserver:self];
    if (_cache) {
        _offset -= _numLines[0].integerValue;
        [_cache removeObjectAtIndex:0];
        [_numLines removeObjectAtIndex:0];
    }
    [_blocks removeObjectAtIndex:0];
}

- (void)removeFirstBlocks:(NSInteger)count {
    for (NSInteger i = 0; i < count; i++) {
        [self removeFirstBlock];
    }
}

- (void)removeLastBlock {
    [_blocks.lastObject removeObserver:self];
    [_blocks removeLastObject];
    [_cache removeLastObject];
    [_numLines removeLastObject];
}

- (NSUInteger)count {
    return _blocks.count;
}

- (LineBlock *)lastBlock {
    return _blocks.lastObject;
}

- (void)updateCacheForBlock:(LineBlock *)block {
    assert(_width > 0);
    assert(_cache.count == _blocks.count);
    assert(_blocks.count > 0);
    if (block == _blocks.firstObject) {
        const NSInteger cached = _numLines[0].integerValue;
        const NSInteger actual = [block getNumLinesWithWrapWidth:_width];
        const NSInteger delta = actual - cached;
        if (_blocks.count > 1) {
            // Only ok to _drop_ lines from the first block when there are others after it.
            assert(delta < 0);
        }
        _offset += delta;
        _numLines[0] = @(actual);
    } else if (block == _blocks.lastObject) {
        const NSInteger index = _cache.count - 1;
        assert(index >= 1);
        const int numLines = [block getNumLinesWithWrapWidth:_width];
        _numLines[index] = @(numLines);
        _cache[index] = @(_cache[index - 1].integerValue + numLines);
    } else {
        ITAssertWithMessage(block == _blocks.firstObject || block == _blocks.lastObject,
                            @"Block with index %@/%@ changed", @([_blocks indexOfObject:block]), @(_blocks.count));
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermLineBlockArray *theCopy = [[self.class alloc] init];
    theCopy->_blocks = [_blocks mutableCopy];
    theCopy->_width = _width;
    theCopy->_offset = _offset;
    theCopy->_cache = [_cache mutableCopy];
    theCopy->_numLines = [_numLines mutableCopy];
    return theCopy;
}

#pragma mark - iTermLineBlockObserver

- (void)lineBlockDidChange:(LineBlock *)lineBlock {
    if (_cache) {
        [self updateCacheForBlock:lineBlock];
    }
}

@end
