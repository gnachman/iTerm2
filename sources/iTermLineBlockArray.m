//
//  iTermLineBlockArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import "iTermLineBlockArray.h"

#import "DebugLogging.h"
#import "iTermCumulativeSumCache.h"
#import "LineBlock.h"

#define PERFORM_SANITY_CHECKS SANITY_CHECK_CUMULATIVE_CACHE

@interface iTermLineBlockArray()<iTermLineBlockObserver>
@end

@implementation iTermLineBlockArray {
    NSMutableArray<LineBlock *> *_blocks;
    BOOL _mayHaveDoubleWidthCharacter;
    int _width;
    iTermCumulativeSumCache *_numLinesCache;
    iTermCumulativeSumCache *_rawSpaceCache;
    iTermCumulativeSumCache *_rawLinesCache;
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
    if (_mayHaveDoubleWidthCharacter) {
        return;
    }
    _mayHaveDoubleWidthCharacter = YES;
    BOOL changed = NO;
    for (LineBlock *block in _blocks) {
        if (!block.mayHaveDoubleWidthCharacter) {
            changed = YES;
        }
        block.mayHaveDoubleWidthCharacter = YES;
    }
    if (changed) {
        _numLinesCache = nil;
    }
}

- (void)buildCacheForWidth:(int)width {
    [self buildNumLinesCacheForWidth:width];
    if (!_rawSpaceCache) {
        [self buildWidthInsensitiveCaches];
    }
}

- (void)buildWidthInsensitiveCaches {
    _rawSpaceCache = [[iTermCumulativeSumCache alloc] init];
    _rawLinesCache = [[iTermCumulativeSumCache alloc] init];
    for (LineBlock *block in _blocks) {
        [_rawSpaceCache appendValue:[block rawSpaceUsed]];
        [_rawLinesCache appendValue:[block numRawLines]];
    }
}

- (void)buildNumLinesCacheForWidth:(int)width {
    _width = width;
    _numLinesCache = [[iTermCumulativeSumCache alloc] init];

    for (LineBlock *block in _blocks) {
        const int block_lines = [block getNumLinesWithWrapWidth:width];
        [_numLinesCache appendValue:block_lines];
    }
}

- (void)eraseCache {
    _width = -1;
    _numLinesCache = nil;
}

- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    if (_numLinesCache && width != _width) {
        [self eraseCache];
    }
    if (!_numLinesCache) {
        [self buildCacheForWidth:width];
    }
    if (_numLinesCache) {
        int r;
        NSInteger actual = [self fastIndexOfBlockContainingLineNumber:lineNumber remainder:&r verbose:NO];
#if PERFORM_SANITY_CHECKS
        int ar;
        NSInteger expected = [self slowIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&ar verbose:NO];
        if (actual != expected || r != ar) {
            if (actual == expected && actual == NSNotFound) {
                // The remainder is undefined
                return actual;
            }
            [self fastIndexOfBlockContainingLineNumber:lineNumber remainder:&r verbose:YES];
            [self slowIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&ar verbose:YES];
            assert(NO);
        }
#endif
        if (remainderPtr) {
            *remainderPtr = r;
        }
        return actual;
    }

    return [self slowIndexOfBlockContainingLineNumber:lineNumber width:width remainder:remainderPtr verbose:NO];
}

- (NSInteger)fastIndexOfBlockContainingLineNumber:(int)lineNumber remainder:(out nonnull int *)remainderPtr verbose:(BOOL)verbose {
    const NSInteger index = verbose ? [_numLinesCache verboseIndexContainingValue:lineNumber] : [_numLinesCache indexContainingValue:lineNumber];

    if (index == NSNotFound) {
        return NSNotFound;
    }

    if (remainderPtr) {
        if (index == 0) {
            if (verbose) {
                NSLog(@"Index is 0 so return block 0 and remainder of %@", @(lineNumber));
            }
            *remainderPtr = lineNumber;
        } else {
            const NSInteger absoluteLineNumber = lineNumber - _numLinesCache.offset;
            if (verbose) {
                NSLog(@"Remainder is absoluteLineNumber-cache[i-1]: %@ - %@",
                      @(absoluteLineNumber),
                      _numLinesCache.values[index - 1]);
            }
            *remainderPtr = absoluteLineNumber - _numLinesCache.sums[index - 1].integerValue;
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
    if (_numLinesCache && width != _width) {
        [self eraseCache];
    }
    if (!_numLinesCache) {
        [self buildCacheForWidth:width];
    }
    if (_numLinesCache) {
        int actual = [self fast_numberOfWrappedLinesForWidth:width];
#if PERFORM_SANITY_CHECKS
        int expected = [self slow_numberOfWrappedLinesForWidth:width];
        assert(actual == expected);
#endif
        return actual;
    }
    return [self slow_numberOfWrappedLinesForWidth:width];
}

- (int)fast_numberOfWrappedLinesForWidth:(int)width {
    return _numLinesCache.sumOfAllValues;
}

- (int)slow_numberOfWrappedLinesForWidth:(int)width {
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
    if (_rawLinesCache) {
        NSInteger result = [self fast_numberOfRawLines];
#if PERFORM_SANITY_CHECKS
        NSInteger expected = [self slow_numberOfRawLines];
        if (result != expected) {
            [self slow_numberOfRawLines];
            [self fast_numberOfRawLines];
            assert(NO);
        }
#endif
        return result;
    } else {
        return [self slow_numberOfRawLines];
    }
}

- (NSInteger)fast_numberOfRawLines {
    return _rawLinesCache.sumOfAllValues;
}

- (NSInteger)slow_numberOfRawLines {
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
    if (_rawSpaceCache) {
        const NSInteger actual = [self fast_rawSpaceUsedInRangeOfBlocks:range];
#if PERFORM_SANITY_CHECKS
        const NSInteger expected = [self slow_rawSpaceUsedInRangeOfBlocks:range];
        assert(actual == expected);
#endif
        return actual;
    } else {
        return [self slow_rawSpaceUsedInRangeOfBlocks:range];
    }
}

- (NSInteger)fast_rawSpaceUsedInRangeOfBlocks:(NSRange)range {
    return [_rawSpaceCache sumOfValuesInRange:range];
}

- (NSInteger)slow_rawSpaceUsedInRangeOfBlocks:(NSRange)range {
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
    // NOTE: line number cache is not used if yoffsetPtr is nil.
    if (yoffsetPtr && _numLinesCache && width != _width) {
        [self eraseCache];
    }
    if (width > 0 && !_numLinesCache) {
        [self buildCacheForWidth:width];
    }
    if (_rawSpaceCache) {
        int r=0, y=0, i=0;
        LineBlock *actual = [self fast_blockContainingPosition:position remainder:&r blockOffset:yoffsetPtr ? &y : NULL index:&i verbose:NO];
#if PERFORM_SANITY_CHECKS
        int ar=0, ay=0, ai=0;
        LineBlock *expected = [self slow_blockContainingPosition:position width:width remainder:&ar blockOffset:yoffsetPtr ? &ay : NULL index:&ai verbose:NO];

        if (actual != expected ||
            r != ar ||
            y != ay ||
            i != ai) {
            [self fast_blockContainingPosition:position remainder:&r blockOffset:yoffsetPtr ? &y : NULL index:&i verbose:YES];
            [self slow_blockContainingPosition:position width:width remainder:&ar blockOffset:yoffsetPtr ? &ay : NULL index:&ai verbose:YES];
        }
        assert(actual == expected);
        assert(r == ar);
        assert(y == ay);
        assert(i == ai);
#endif
        if (remainderPtr) {
            *remainderPtr = r;
        }
        if (yoffsetPtr) {
            *yoffsetPtr = y;
        }
        if (indexPtr) {
            *indexPtr = i;
        }
        return actual;
    } else {
        return [self slow_blockContainingPosition:position width:width remainder:remainderPtr blockOffset:yoffsetPtr index:indexPtr verbose:NO];
    }
}

- (LineBlock *)fast_blockContainingPosition:(long long)position
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)yoffsetPtr
                                      index:(int *)indexPtr
                                    verbose:(BOOL)verbose {
    NSInteger index = verbose ? [_rawSpaceCache verboseIndexContainingValue:position] : [_rawSpaceCache indexContainingValue:position];
    if (index == NSNotFound) {
        if (verbose) {
            NSLog(@"Index is past the end. Return nil.");
        }
        return nil;
    }

    if (remainderPtr) {
        *remainderPtr = position - [_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)];
        if (verbose) {
            NSLog(@"Remainder is position - space before index %@: %@-%@=%@",
                  @(index), @(position), @([_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)]), @(*remainderPtr));
        }
    }
    if (yoffsetPtr) {
        *yoffsetPtr = [_numLinesCache sumOfValuesInRange:NSMakeRange(0, index)];
        if (verbose) {
            NSLog(@"yoffset is sum of blocks up to but not including %@: %@", @(index), @(*yoffsetPtr));
        }
    }
    if (indexPtr) {
        *indexPtr = index;
    }
    return _blocks[index];
}

- (LineBlock *)slow_blockContainingPosition:(long long)position
                                      width:(int)width
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)yoffsetPtr
                                      index:(int *)indexPtr
                                    verbose:(BOOL)verbose {
    if (verbose) {
        NSLog(@"Begin slow block containing position.");
        NSLog(@"Look for position %@ for width %@", @(position), @(width));
    }
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
            if (verbose) {
                NSLog(@"Block %@: used=%@, p<-%@ numLines=%@ yoffset<-%@",
                      @(index), @(used), @(p), @([block getNumLinesWithWrapWidth:width]), @(yoffset));
            }
        } else {
            if (verbose) {
                NSLog(@"Block %@: used=%@. Return remainder=%@, yoffset=%@", @(index), @(used), @(p), @(yoffset));
            }
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
    if (verbose) {
        NSLog(@"Ran out of blocks, return nil");
    }
    return nil;
}

#pragma mark - Low level method

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return _blocks[index];
}

- (void)replaceLastBlockWithCopy {
    NSInteger index = _blocks.count;
    if (index == 0) {
        return;
    }
    index--;
    _blocks[index] = [_blocks[index] copy];
    [_blocks[index] addObserver:self];
}

- (void)addBlock:(LineBlock *)block {
    [block addObserver:self];
    [_blocks addObject:block];
    if (_numLinesCache) {
        [_numLinesCache appendValue:0];
    }
    if (_rawSpaceCache) {
        [_rawSpaceCache appendValue:0];
        [_rawLinesCache appendValue:0];
        // The block might not be empty. Treat it like a bunch of lines just got appended.
        [self updateCacheForBlock:block];
    }
#if PERFORM_SANITY_CHECKS
    [self sanityCheck];
#endif
}

- (void)removeFirstBlock {
    [_blocks.firstObject removeObserver:self];
    [_numLinesCache removeFirstValue];
    [_rawSpaceCache removeFirstValue];
    [_rawLinesCache removeFirstValue];
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
    [_numLinesCache removeLastValue];
    [_rawSpaceCache removeLastValue];
    [_rawLinesCache removeLastValue];
}

- (NSUInteger)count {
    return _blocks.count;
}

- (LineBlock *)lastBlock {
#if PERFORM_SANITY_CHECKS
    [self sanityCheck];
#endif
    return _blocks.lastObject;
}

- (void)updateCacheForBlock:(LineBlock *)block {
    if (_numLinesCache) {
        assert(_numLinesCache.sums.count == _blocks.count);
        assert(_numLinesCache.values.count == _blocks.count);
    }
    assert(_rawSpaceCache.sums.count == _blocks.count);
    assert(_rawSpaceCache.values.count == _blocks.count);
    assert(_rawLinesCache.sums.count == _blocks.count);
    assert(_rawLinesCache.values.count == _blocks.count);
    assert(_blocks.count > 0);

    if (block == _blocks.firstObject) {
        [_numLinesCache setFirstValue:[block getNumLinesWithWrapWidth:_width]];
        [_rawSpaceCache setFirstValue:[block rawSpaceUsed]];
        [_rawLinesCache setFirstValue:[block numRawLines]];
    } else if (block == _blocks.lastObject) {
        [_numLinesCache setLastValue:[block getNumLinesWithWrapWidth:_width]];
        [_rawSpaceCache setLastValue:[block rawSpaceUsed]];
        [_rawLinesCache setLastValue:[block numRawLines]];
    } else {
        ITAssertWithMessage(block == _blocks.firstObject || block == _blocks.lastObject,
                            @"Block with index %@/%@ changed", @([_blocks indexOfObject:block]), @(_blocks.count));
    }
#if PERFORM_SANITY_CHECKS
    [self sanityCheck];
#endif
}

- (void)sanityCheck {
    if (_rawLinesCache == nil) {
        return;
    }
    for (int i = 0; i < _blocks.count; i++) {
        LineBlock *block = _blocks[i];
        BOOL ok = [block numRawLines] == _rawLinesCache.values[i].integerValue;
        assert(ok);
        assert([block hasObserver:self]);
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermLineBlockArray *theCopy = [[self.class alloc] init];
    theCopy->_blocks = [_blocks mutableCopy];
    theCopy->_numLinesCache = [_numLinesCache copy];
    theCopy->_rawSpaceCache = [_rawSpaceCache copy];
    theCopy->_rawLinesCache = [_rawLinesCache copy];
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
    for (LineBlock *block in _blocks) {
        [block addObserver:theCopy];
    }

    return theCopy;
}

#pragma mark - iTermLineBlockObserver

- (void)lineBlockDidChange:(LineBlock *)lineBlock {
    if (_rawSpaceCache || _numLinesCache || _rawLinesCache) {
        [self updateCacheForBlock:lineBlock];
    }
}

@end
