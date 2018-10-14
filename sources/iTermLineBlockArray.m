//
//  iTermLineBlockArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import "iTermLineBlockArray.h"

#import "DebugLogging.h"
#import "LineBlock.h"

#define PERFORM_SANITY_CHECKS 1

@interface iTermCumulativeSumCache : NSObject<NSCopying>
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *sums;
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *values;
@property (nonatomic) NSInteger offset;
@property (nonatomic, readonly) int width;

- (instancetype)initWithWidth:(int)width NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSInteger)insertionIndexForValue:(NSInteger)value;
// Add a 0 to the end
- (void)extend;
- (void)removeFirstValue;
- (void)removeLastValue;
- (void)setLastValue:(NSInteger)value;
- (void)setFirstValue:(NSInteger)value;

@end

@implementation iTermCumulativeSumCache

- (instancetype)initWithWidth:(int)width {
    self = [super init];
    if (self) {
        _sums = [NSMutableArray array];
        _values = [NSMutableArray array];
        _width = width;
    }
    return self;
}

- (NSInteger)insertionIndexForValue:(NSInteger)value {
    // Subtract the offset because the offset is negative and our values are higher than what is exposed by the owner's interface.
    const NSInteger adjustedValue = value - _offset;
    const NSInteger insertionIndex = [_sums indexOfObject:@(adjustedValue)
                                            inSortedRange:NSMakeRange(0, _sums.count)
                                                  options:NSBinarySearchingInsertionIndex
                                          usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                              return [obj1 compare:obj2];
                                          }];
    NSInteger index = insertionIndex;
    while (index + 1 < _sums.count &&
           _sums[index].integerValue == adjustedValue) {
        index++;
    }
    if (index == _sums.count) {
        return NSNotFound;
    }

    return index;
}

- (void)extend {
    [_sums addObject:_sums.lastObject ?: @(-_offset)];
    [_values addObject:@0];
}

- (void)removeFirstValue {
    _offset -= _values[0].integerValue;
    [_sums removeObjectAtIndex:0];
    [_values removeObjectAtIndex:0];
}

- (void)removeLastValue {
    [_sums removeLastObject];
    [_values removeLastObject];
}

- (void)setLastValue:(NSInteger)value {
    const NSInteger index = _sums.count - 1;
    assert(index >= 1);
    _values[index] = @(value);
    _sums[index] = @(_sums[index - 1].integerValue + value);
}

- (void)setFirstValue:(NSInteger)value {
    const NSInteger cachedNumLines = _values[0].integerValue;
    const NSInteger delta = value - cachedNumLines;
    if (_sums.count > 1) {
        // Only ok to _drop_ lines from the first block when there are others after it.
        assert(delta <= 0);
    }
    _offset += delta;
    _values[0] = @(value);
}

- (id)copyWithZone:(NSZone *)zone {
    iTermCumulativeSumCache *theCopy = [[iTermCumulativeSumCache alloc] initWithWidth:_width];
    theCopy->_sums = [_sums mutableCopy];
    theCopy->_values = [_values mutableCopy];
    theCopy->_offset = _offset;
    return theCopy;
}

@end

@interface iTermLineBlockArray()<iTermLineBlockObserver>
@end

@implementation iTermLineBlockArray {
    NSMutableArray<LineBlock *> *_blocks;
    NSInteger _width;  // width for the cache

    iTermCumulativeSumCache *_numLinesCache;

    NSInteger _rawOffset;
    NSMutableArray<NSNumber *> *_sumRawSpace;
    NSMutableArray<NSNumber *> *_rawSpace;
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
    _numLinesCache = nil;
    _sumRawSpace = nil;
    _rawSpace = nil;
    _width = -1;
}

- (void)buildCacheForWidth:(int)width {
    _width = width;

    _numLinesCache = [[iTermCumulativeSumCache alloc] initWithWidth:width];

    _rawOffset = 0;
    _sumRawSpace = [NSMutableArray array];
    _rawSpace = [NSMutableArray array];

    NSInteger sumNumLines = 0;
    NSInteger sumRawSpace = 0;
    for (LineBlock *block in _blocks) {
        int block_lines = [block getNumLinesWithWrapWidth:width];
        sumNumLines += block_lines;
        [_numLinesCache.sums addObject:@(sumNumLines)];
        [_numLinesCache.values addObject:@(block_lines)];

        int rawSpace = [block rawSpaceUsed];
        sumRawSpace += rawSpace;
        [_sumRawSpace addObject:@(sumRawSpace)];
        [_rawSpace addObject:@(rawSpace)];
    }
}

- (void)eraseCache {
    _numLinesCache = nil;
    _sumRawSpace = nil;
    _rawSpace = nil;
}

- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    if (width != _width) {
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
    const NSInteger index = [_numLinesCache insertionIndexForValue:lineNumber];

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
#warning TODO: Optimize this
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
#warning TODO: Optimize this
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
    if (_rawSpace) {
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
    if (range.length == 0) {
        return 0;
    }
    const int lowIndex = range.location;
    const int highIndex = NSMaxRange(range) - 1;
    return _sumRawSpace[highIndex].integerValue - _sumRawSpace[lowIndex].integerValue + _rawSpace[lowIndex].integerValue;
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
    if (width != _width) {
        [self eraseCache];
    }
    if (_rawSpace) {
        int r, y, i;
        LineBlock *actual = [self fast_blockContainingPosition:position width:width remainder:&r blockOffset:&y index:&i verbose:NO];
#if PERFORM_SANITY_CHECKS
        int ar, ay, ai;
        LineBlock *expected = [self slow_blockContainingPosition:position width:width remainder:&ar blockOffset:&ay index:&ai verbose:NO];

        if (actual != expected ||
            r != ar ||
            y != ay ||
            i != ai) {
            [self fast_blockContainingPosition:position width:width remainder:&r blockOffset:&y index:&i verbose:YES];
            [self slow_blockContainingPosition:position width:width remainder:&ar blockOffset:&ay index:&ai verbose:YES];
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
                                      width:(int)width
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)yoffsetPtr
                                      index:(int *)indexPtr
                                    verbose:(BOOL)verbose {
    if (verbose) {
        NSLog(@"Begin fast");
        NSLog(@"Look for block containing %@ for width %@", @(position), @(width));
    }
    const NSInteger adjustedPosition = position - _rawOffset;
    const NSInteger insertionIndex = [_sumRawSpace indexOfObject:@(adjustedPosition)
                                                   inSortedRange:NSMakeRange(0, _sumRawSpace.count)
                                                         options:NSBinarySearchingInsertionIndex
                                                 usingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                                                     return [obj1 compare:obj2];
                                                 }];
    if (verbose) {
        NSLog(@"Insertion index for adjusted position %@ is %@", @(adjustedPosition), @(insertionIndex));
    }
    NSInteger index = insertionIndex;
    while (index + 1 < _sumRawSpace.count &&
           _sumRawSpace[index].integerValue == adjustedPosition) {
        index++;
        if (verbose) {
            NSLog(@"Increment index because adjusted position exactly matches the sumRawSpace. Index is now %@", @(index));
        }
    }
    if (index == _sumRawSpace.count) {
        if (verbose) {
            NSLog(@"Index is past the end. Return nil.");
        }
        return nil;
    }

    if (remainderPtr) {
        const NSInteger rawSpaceBeforeIndex = _sumRawSpace[index].integerValue - _rawSpace[index].integerValue;
        if (verbose) {
            NSLog(@"Remainder is adjustedPosition-rawSpaceBeforeIndex: %@-%@=%@", @(adjustedPosition), @(_sumRawSpace[index].integerValue), @(adjustedPosition - rawSpaceBeforeIndex));
            NSLog(@"rawSpaceBeforeIndex = _sumRaw[index]-raw[index]: %@-%@", _sumRawSpace[index], _rawSpace[index]);
        }
        *remainderPtr = adjustedPosition - rawSpaceBeforeIndex;
    }
    if (yoffsetPtr) {
        if (verbose) {
            NSLog(@"yoffset is sum[index]-lines[index]+offset: %@-%@+%@=%@",
                  _numLinesCache.sums[index],
                  _numLinesCache.values[index],
                  @(_numLinesCache.offset),
                  @(_numLinesCache.sums[index].integerValue - _numLinesCache.values[index].integerValue + _numLinesCache.offset));
        }
        *yoffsetPtr = _numLinesCache.sums[index].integerValue - _numLinesCache.values[index].integerValue + _numLinesCache.offset;
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
}

- (void)addBlock:(LineBlock *)block {
    [block addObserver:self];
    [_blocks addObject:block];
    if (_numLinesCache) {
        [_numLinesCache extend];
        [_sumRawSpace addObject:_sumRawSpace.lastObject ?: @(-_rawOffset)];
        [_rawSpace addObject:@0];
        // The block might not be empty. Treat it like a bunch of lines just got appended.
        [self updateCacheForBlock:block];
    }
}

- (void)removeFirstBlock {
    [_blocks.firstObject removeObserver:self];
    if (_numLinesCache) {
        [_numLinesCache removeFirstValue];

        _rawOffset -= _rawSpace[0].integerValue;
        [_sumRawSpace removeObjectAtIndex:0];
        [_rawSpace removeObjectAtIndex:0];
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
    [_numLinesCache removeLastValue];
    [_sumRawSpace removeLastObject];
    [_rawSpace removeLastObject];
}

- (NSUInteger)count {
    return _blocks.count;
}

- (LineBlock *)lastBlock {
    return _blocks.lastObject;
}

- (void)updateCacheForBlock:(LineBlock *)block {
    assert(_width > 0);
    assert(_numLinesCache.sums.count == _blocks.count);
    assert(_numLinesCache.values.count == _blocks.count);
    assert(_sumRawSpace.count == _blocks.count);
    assert(_rawSpace.count == _blocks.count);
    assert(_blocks.count > 0);

    if (block == _blocks.firstObject) {
        [_numLinesCache setFirstValue:[block getNumLinesWithWrapWidth:_width]];

        const NSInteger cachedRawSpace = _rawSpace[0].integerValue;
        const NSInteger actualRawSpace = [block rawSpaceUsed];
        const NSInteger deltaRawSpace = actualRawSpace - cachedRawSpace;
        if (_blocks.count > 1) {
            assert(deltaRawSpace <= 0);
        }
        _rawOffset += deltaRawSpace;
        _rawSpace[0] = @(actualRawSpace);
    } else if (block == _blocks.lastObject) {
        [_numLinesCache setLastValue:[block getNumLinesWithWrapWidth:_width]];

        const NSInteger rawSpace = [block rawSpaceUsed];
        const NSInteger index = _rawSpace.count - 1;
        _rawSpace[index] = @(rawSpace);
        _sumRawSpace[index] = @(_sumRawSpace[index - 1].integerValue + rawSpace);
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

    theCopy->_numLinesCache = [_numLinesCache copy];

    theCopy->_rawOffset = _rawOffset;
    theCopy->_sumRawSpace = [_sumRawSpace mutableCopy];
    theCopy->_rawSpace = [_rawSpace mutableCopy];

    return theCopy;
}

#pragma mark - iTermLineBlockObserver

- (void)lineBlockDidChange:(LineBlock *)lineBlock {
    if (_numLinesCache) {
        [self updateCacheForBlock:lineBlock];
    }
}

@end
