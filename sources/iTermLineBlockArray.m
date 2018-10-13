//
//  iTermLineBlockArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import "iTermLineBlockArray.h"

#import "DebugLogging.h"
#import "iTermCumulativeSumCache.h"
#import "iTermTuple.h"
#import "LineBlock.h"
#import "NSArray+iTerm.h"

#define PERFORM_SANITY_CHECKS SANITY_CHECK_CUMULATIVE_CACHE

@interface iTermLineBlockArray()<iTermLineBlockObserver>
// NOTE: Update -copyWithZone: if you add properties.
@end

@interface iTermLineBlockCacheCollection : NSObject<NSCopying>
@property (nonatomic) int capacity;

- (iTermCumulativeSumCache *)numLinesCacheForWidth:(int)width;
- (void)setNumLinesCache:(iTermCumulativeSumCache *)numLinesCache
                forWidth:(int)width;
- (void)removeFirstValue;
- (void)removeLastValue;
- (void)setFirstValueWithBlock:(NSInteger (^)(int width))block;
- (void)setLastValueWithBlock:(NSInteger (^)(int width))block;
- (void)appendValue:(NSInteger)value;
@end

@implementation iTermLineBlockCacheCollection {
    NSMutableArray<iTermTuple<NSNumber *, iTermCumulativeSumCache *> *> *_caches;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _capacity = 1;
        _caches = [NSMutableArray array];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    iTermLineBlockCacheCollection *theCopy = [[iTermLineBlockCacheCollection alloc] init];
    theCopy.capacity = self.capacity;
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [theCopy->_caches addObject:[iTermTuple tupleWithObject:tuple.firstObject andObject:tuple.secondObject.copy]];
    }
    return theCopy;
}

- (void)setCapacity:(int)capacity {
    _capacity = capacity;
    [self evictIfNeeded];
}

- (iTermCumulativeSumCache *)numLinesCacheForWidth:(int)width {
    NSInteger index = [_caches indexOfObjectPassingTest:^BOOL(iTermTuple<NSNumber *,iTermCumulativeSumCache *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        return tuple.firstObject.intValue == width;
    }];
    if (index == NSNotFound) {
        return nil;
    }
    if (index == 0) {
        return _caches[0].secondObject;
    }

    // Bump to top of the list
    iTermTuple *tuple = _caches[index];
    [_caches removeObjectAtIndex:index];
    [_caches insertObject:tuple atIndex:0];
    return tuple.secondObject;
}

- (void)setNumLinesCache:(iTermCumulativeSumCache *)numLinesCache forWidth:(int)width {
    iTermCumulativeSumCache *existing = [self numLinesCacheForWidth:width];
    assert(!existing);
    [_caches insertObject:[iTermTuple tupleWithObject:@(width) andObject:numLinesCache] atIndex:0];
    [self evictIfNeeded];
}

- (void)evictIfNeeded {
    while (_caches.count > _capacity) {
        DLog(@"Evicted cache of width %@", _caches.lastObject.firstObject);
        [_caches removeLastObject];
    }
}

- (void)removeLastValue {
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [tuple.secondObject removeLastValue];
    }
}

- (void)removeFirstValue {
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [tuple.secondObject removeFirstValue];
    }
}

- (void)setFirstValueWithBlock:(NSInteger (^)(int width))block {
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [tuple.secondObject setFirstValue:block(tuple.firstObject.intValue)];
    }
}

- (void)setLastValueWithBlock:(NSInteger (^)(int width))block {
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [tuple.secondObject setLastValue:block(tuple.firstObject.intValue)];
    }
}

- (void)appendValue:(NSInteger)value {
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [tuple.secondObject appendValue:value];
    }
}

@end

@implementation iTermLineBlockArray {
    NSMutableArray<LineBlock *> *_blocks;
    BOOL _mayHaveDoubleWidthCharacter;
    iTermLineBlockCacheCollection *_numLinesCaches;

    iTermCumulativeSumCache *_rawSpaceCache;
    iTermCumulativeSumCache *_rawLinesCache;

    LineBlock *_head;
    LineBlock *_tail;
    BOOL _headDirty;
    BOOL _tailDirty;
    // NOTE: Update -copyWithZone: if you add member variables.
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = [NSMutableArray array];
        _numLinesCaches = [[iTermLineBlockCacheCollection alloc] init];
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

- (void)setResizing:(BOOL)resizing {
    _resizing = resizing;
    if (resizing) {
        _numLinesCaches.capacity = 2;
    } else {
        _numLinesCaches.capacity = 1;
    }
}

- (void)setAllBlocksMayHaveDoubleWidthCharacters {
    if (_mayHaveDoubleWidthCharacter) {
        return;
    }
    [self updateCacheIfNeeded];
    _mayHaveDoubleWidthCharacter = YES;
    BOOL changed = NO;
    for (LineBlock *block in _blocks) {
        if (!block.mayHaveDoubleWidthCharacter) {
            changed = YES;
        }
        block.mayHaveDoubleWidthCharacter = YES;
    }
    if (changed) {
        _numLinesCaches = [[iTermLineBlockCacheCollection alloc] init];
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
    assert(width > 0);
    iTermCumulativeSumCache *numLinesCache = [_numLinesCaches numLinesCacheForWidth:width];
    if (numLinesCache) {
        return;
    }

    numLinesCache = [[iTermCumulativeSumCache alloc] init];
    for (LineBlock *block in _blocks) {
        const int block_lines = [block getNumLinesWithWrapWidth:width];
        [numLinesCache appendValue:block_lines];
    }
    [_numLinesCaches setNumLinesCache:numLinesCache forWidth:width];
}

- (void)oopsWithWidth:(int)width block:(void (^)(void))block {
    TurnOnDebugLoggingSilently();

    if (width > 0) {
        DLog(@"Begin num lines cache dump for width %@", @(width));
        [[_numLinesCaches numLinesCacheForWidth:width] dump];
    }
    DLog(@"-- Begin raw lines dump --");
    [_rawLinesCache dump];
    DLog(@"-- Begin raw space dump --");
    [_rawSpaceCache dump];
    DLog(@"-- Begin blocks dump --");
    int i = 0;
    for (LineBlock *block in _blocks) {
        DLog(@"-- BEGIN BLOCK %@ --", @(i++));
        [block dump:width toDebugLog:YES];
    }
    DLog(@"-- End of boilerplate dumps --");
    block();
    ITCriticalError(NO, @"New history algorithm bug detected");
}

- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr verbose:(BOOL)verbose {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];

    __block int r;
    NSInteger actual = [self fastIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&r verbose:verbose];
#if PERFORM_SANITY_CHECKS
    __block int ar;
    NSInteger expected = [self slowIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&ar verbose:NO];
    if (actual != expected || r != ar) {
        if (actual == expected && actual == NSNotFound) {
            // The remainder is undefined
            return actual;
        }
        [self oopsWithWidth:width block:^{
            DLog(@"lineNumber=%@ width=%@", @(lineNumber), @(width));
            DLog(@"Actual=%@ expected=%@", @(actual), @(expected));
            [self fastIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&r verbose:YES];
            [self slowIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&ar verbose:YES];
        }];
    }
#endif
    if (remainderPtr) {
        *remainderPtr = r;
    }
    return actual;
}

- (NSInteger)fastIndexOfBlockContainingLineNumber:(int)lineNumber
                                            width:(int)width
                                        remainder:(out nonnull int *)remainderPtr
                                          verbose:(BOOL)verbose {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];
    iTermCumulativeSumCache *numLinesCache = [_numLinesCaches numLinesCacheForWidth:width];
    const NSInteger index = verbose ? [numLinesCache verboseIndexContainingValue:lineNumber] : [numLinesCache indexContainingValue:lineNumber];

    if (index == NSNotFound) {
        return NSNotFound;
    }

    if (remainderPtr) {
        if (index == 0) {
            if (verbose) {
                DLog(@"Index is 0 so return block 0 and remainder of %@", @(lineNumber));
            }
            *remainderPtr = lineNumber;
        } else {
            const NSInteger absoluteLineNumber = lineNumber - numLinesCache.offset;
            if (verbose) {
                DLog(@"Remainder is absoluteLineNumber-cache[i-1]: %@ - %@",
                     @(absoluteLineNumber),
                     @([numLinesCache valueAtIndex:index - 1]));
            }
            *remainderPtr = absoluteLineNumber - [numLinesCache sumAtIndex:index - 1];
        }
    }
    if (verbose) {
        DLog(@"Return index %@", @(index));
    }
    return index;
}

- (NSInteger)slowIndexOfBlockContainingLineNumber:(int)lineNumber
                                            width:(int)width
                                        remainder:(out nonnull int *)remainderPtr
                                          verbose:(BOOL)verbose {
    int line = lineNumber;
    if (verbose) {
        DLog(@"Begin SLOW search for line number %@", @(lineNumber));
    }
    for (NSInteger i = 0; i < _blocks.count; i++) {
        if (verbose) {
            DLog(@"Block %@", @(i));
        }
        if (line == 0) {
            // I don't think a block will ever have 0 lines, but this prevents an infinite loop if that does happen.
            *remainderPtr = 0;
            if (verbose) {
                DLog(@"hm, line is 0. All done I guess");
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
                DLog(@"Consume %@ lines from block %@. Have %@ more to go.", @(block_lines), @(i), @(line));
            }
            continue;
        }

        if (verbose) {
            DLog(@"Result is at block %@ with a remainder of %@", @(i), @(line));
        }
        if (remainderPtr) {
            *remainderPtr = line;
        }
        assert(line < block_lines);
        return i;
    }
    return NSNotFound;
}

- (LineBlock *)blockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr verbose:(BOOL)verbose {
    int remainder = 0;
    NSInteger i = [self indexOfBlockContainingLineNumber:lineNumber
                                                   width:width
                                               remainder:&remainder
                                                 verbose:verbose];
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
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];

    int actual = [self fast_numberOfWrappedLinesForWidth:width];
#if PERFORM_SANITY_CHECKS
    int expected = [self slow_numberOfWrappedLinesForWidth:width verbose:NO];
    if (actual != expected) {
        [self oopsWithWidth:width block:^{
            DLog(@"width=%@", @(width));
            DLog(@"actual=%@ expected=%@", @(actual), @(expected));
            [self slow_numberOfWrappedLinesForWidth:width verbose:YES];
        }];
    }
#endif
    return actual;
}

- (int)fast_numberOfWrappedLinesForWidth:(int)width {
    [self buildCacheForWidth:width];
    return [[_numLinesCaches numLinesCacheForWidth:width] sumOfAllValues];
}

- (int)slow_numberOfWrappedLinesForWidth:(int)width verbose:(BOOL)verbose {
    int count = 0;
    for (LineBlock *block in _blocks) {
        const int n = [block getNumLinesWithWrapWidth:width];
        count += n;
        if (verbose) {
            DLog(@"count += %@, giving %@", @(n), @(count));
        }
    }
    return count;
}

- (void)enumerateLinesInRange:(NSRange)range
                        width:(int)width
                      verbose:(BOOL)verbose
                        block:(void (^)(screen_char_t * _Nonnull, int, int, screen_char_t, BOOL * _Nonnull))callback {
    int remainder;
    NSInteger startIndex = [self indexOfBlockContainingLineNumber:range.location width:width remainder:&remainder verbose:verbose];
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
        [self updateCacheIfNeeded];
        NSInteger result = [self fast_numberOfRawLines];
#if PERFORM_SANITY_CHECKS
        NSInteger expected = [self slow_numberOfRawLinesVerbose:NO];
        if (result != expected) {
            [self oopsWithWidth:0 block:^{
                [self slow_numberOfRawLinesVerbose:YES];
                [self fast_numberOfRawLines];
            }];
        }
#endif
        return result;
    } else {
        return [self slow_numberOfRawLinesVerbose:NO];
    }
}

- (NSInteger)fast_numberOfRawLines {
    return _rawLinesCache.sumOfAllValues;
}

- (NSInteger)slow_numberOfRawLinesVerbose:(BOOL)verbose {
    NSInteger sum = 0;
    for (LineBlock *block in _blocks) {
        int n = [block numRawLines];
        sum += n;
        if (verbose) {
            DLog(@"sum += %@, giving %@", @(n), @(sum));
        }
    }
    return sum;
}

- (NSInteger)rawSpaceUsedVerbose:(BOOL)verbose {
    return [self rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, _blocks.count) verbose:verbose];
}

- (NSInteger)rawSpaceUsedInRangeOfBlocks:(NSRange)range
                                 verbose:(BOOL)verbose {
    if (_rawSpaceCache) {
        [self updateCacheIfNeeded];
        const NSInteger actual = [self fast_rawSpaceUsedInRangeOfBlocks:range];
#if PERFORM_SANITY_CHECKS
        const NSInteger expected = [self slow_rawSpaceUsedInRangeOfBlocks:range verbose:verbose];
        if (actual != expected) {
            [self oopsWithWidth:0 block:^{
                DLog(@"range=%@", NSStringFromRange(range));
                DLog(@"actual=%@ expected=%@", @(actual), @(expected));
                [self slow_rawSpaceUsedInRangeOfBlocks:range verbose:YES];
            }];
        }
#endif
        return actual;
    } else {
        return [self slow_rawSpaceUsedInRangeOfBlocks:range verbose:verbose];
    }
}

- (NSInteger)fast_rawSpaceUsedInRangeOfBlocks:(NSRange)range {
    return [_rawSpaceCache sumOfValuesInRange:range];
}

- (NSInteger)slow_rawSpaceUsedInRangeOfBlocks:(NSRange)range verbose:(BOOL)verbose {
    NSInteger position = 0;
    for (NSInteger i = 0; i < range.length; i++) {
        LineBlock *block = _blocks[i + range.location];
        int  n = [block rawSpaceUsed];
        position += n;
        if (verbose) {
            DLog(@"position += %@, giving %@", @(n), @(position));
        }
    }
    return position;
}

- (LineBlock *)blockContainingPosition:(long long)position
                                 width:(int)width
                             remainder:(int *)remainderPtr
                           blockOffset:(int *)yoffsetPtr
                                 index:(int *)indexPtr
                               verbose:(BOOL)verbose {
    if (width > 0) {
        [self buildCacheForWidth:width];
    }
    [self updateCacheIfNeeded];
    if (width > 0 && _rawSpaceCache && !verbose) {
        int r=0, y=0, i=0;
        LineBlock *actual = [self fast_blockContainingPosition:position width:width remainder:&r blockOffset:yoffsetPtr ? &y : NULL index:&i verbose:NO];
#if PERFORM_SANITY_CHECKS
        int ar=0, ay=0, ai=0;
        LineBlock *expected = [self slow_blockContainingPosition:position width:width remainder:&ar blockOffset:yoffsetPtr ? &ay : NULL index:&ai verbose:NO];

        if (actual != expected ||
            r != ar ||
            y != ay ||
            i != ai) {
            [self oopsWithWidth:width block:^{
                DLog(@"position=%@ width=%@ r=%@ y=%@ i=%@ ar=%@ ay=%@ ai=%@",
                     @(position), @(width), @(r), @(y), @(i), @(ar), @(ay), @(ai));
                DLog(@"Actual:");
                [actual dump:width toDebugLog:YES];
                DLog(@"Expected:");
                [expected dump:width toDebugLog:YES];
                DLog(@"-- End dumps --");
                int r=0, y=0, i=0;
                [self fast_blockContainingPosition:position width:width remainder:&r blockOffset:yoffsetPtr ? &y : NULL index:&i verbose:YES];
                int ar=0, ay=0, ai=0;
                [self slow_blockContainingPosition:position width:width remainder:&ar blockOffset:yoffsetPtr ? &ay : NULL index:&ai verbose:YES];
            }];
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
        return [self slow_blockContainingPosition:position width:width remainder:remainderPtr blockOffset:yoffsetPtr index:indexPtr verbose:verbose];
    }
}

- (LineBlock *)fast_blockContainingPosition:(long long)position
                                      width:(int)width
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)yoffsetPtr
                                      index:(int *)indexPtr
                                    verbose:(BOOL)verbose {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];
    NSInteger index = verbose ? [_rawSpaceCache verboseIndexContainingValue:position] : [_rawSpaceCache indexContainingValue:position];
    if (index == NSNotFound) {
        if (verbose) {
            DLog(@"Index is past the end. Return nil.");
        }
        return nil;
    }

    if (remainderPtr) {
        *remainderPtr = position - [_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)];
        if (verbose) {
            DLog(@"Remainder is position - space before index %@: %@-%@=%@",
                  @(index), @(position), @([_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)]), @(*remainderPtr));
        }
    }
    if (yoffsetPtr) {
        *yoffsetPtr = [[_numLinesCaches numLinesCacheForWidth:width] sumOfValuesInRange:NSMakeRange(0, index)];
        if (verbose) {
            DLog(@"yoffset is sum of blocks up to but not including %@: %@", @(index), @(*yoffsetPtr));
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
        DLog(@"Begin slow block containing position.");
        DLog(@"Look for position %@ for width %@", @(position), @(width));
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
                DLog(@"Block %@: used=%@, p<-%@ numLines=%@ yoffset<-%@",
                      @(index), @(used), @(p), @([block getNumLinesWithWrapWidth:width]), @(yoffset));
            }
        } else {
            if (verbose) {
                DLog(@"Block %@: used=%@. Return remainder=%@, yoffset=%@", @(index), @(used), @(p), @(yoffset));
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
        DLog(@"Ran out of blocks, return nil");
    }
    return nil;
}

#pragma mark - Low level method

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return _blocks[index];
}

- (void)replaceLastBlockWithCopy {
    [self updateCacheIfNeeded];
    NSInteger index = _blocks.count;
    if (index == 0) {
        return;
    }
    index--;
    [_blocks[index] removeObserver:self];
    _blocks[index] = [_blocks[index] copy];
    [_blocks[index] addObserver:self];
    _head = _blocks.firstObject;
    _tail = _blocks.lastObject;
}

- (void)addBlock:(LineBlock *)block {
    [self updateCacheIfNeeded];
    [block addObserver:self];
    [_blocks addObject:block];
    if (_blocks.count == 1) {
        _head = block;
    }
    _tail = block;
    [_numLinesCaches appendValue:0];
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
    [self updateCacheIfNeeded];
    [_blocks.firstObject removeObserver:self];
    [_numLinesCaches removeFirstValue];
    [_rawSpaceCache removeFirstValue];
    [_rawLinesCache removeFirstValue];
    [_blocks removeObjectAtIndex:0];
    _head = _blocks.firstObject;
    _tail = _blocks.lastObject;
}

- (void)removeFirstBlocks:(NSInteger)count {
    for (NSInteger i = 0; i < count; i++) {
        [self removeFirstBlock];
    }
}

- (void)removeLastBlock {
    [self updateCacheIfNeeded];
    [_blocks.lastObject removeObserver:self];
    [_blocks removeLastObject];
    [_numLinesCaches removeLastValue];
    [_rawSpaceCache removeLastValue];
    [_rawLinesCache removeLastValue];
    _head = _blocks.firstObject;
    _tail = _blocks.lastObject;
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
    if (_rawSpaceCache) {
        assert(_rawSpaceCache.count == _blocks.count);
        assert(_rawLinesCache.count == _blocks.count);
    }
    assert(_blocks.count > 0);

    if (block == _blocks.firstObject) {
        _headDirty = NO;
        [_numLinesCaches setFirstValueWithBlock:^NSInteger(int width) {
            return [block getNumLinesWithWrapWidth:width];
        }];
        [_rawSpaceCache setFirstValue:[block rawSpaceUsed]];
        [_rawLinesCache setFirstValue:[block numRawLines]];
    } else if (block == _blocks.lastObject) {
        _tailDirty = NO;
        [_numLinesCaches setLastValueWithBlock:^NSInteger(int width) {
            return [block getNumLinesWithWrapWidth:width];
        }];
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
    [self updateCacheIfNeeded];
    for (int i = 0; i < _blocks.count; i++) {
        LineBlock *block = _blocks[i];
        assert([block hasObserver:self]);
        BOOL ok = [block numRawLines] == [_rawLinesCache valueAtIndex:i];
        if (!ok) {
            [self oopsWithWidth:0 block:^{
                DLog(@"Sanity check failed");
            }];

        }
    }
}

- (void)updateCacheIfNeeded {
    if (_headDirty) {
        [self updateCacheForBlock:_blocks.firstObject];
    }
    if (_tailDirty) {
        [self updateCacheForBlock:_blocks.lastObject];
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermLineBlockArray *theCopy = [[self.class alloc] init];
    theCopy->_blocks = [_blocks mutableCopy];
    theCopy->_numLinesCaches = [_numLinesCaches copy];
    theCopy->_rawSpaceCache = [_rawSpaceCache copy];
    theCopy->_rawLinesCache = [_rawLinesCache copy];
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
    theCopy->_head = _head;
    theCopy->_headDirty = _headDirty;
    theCopy->_tail = _tail;
    theCopy->_tailDirty = _tailDirty;
    theCopy->_resizing = _resizing;
    for (LineBlock *block in _blocks) {
        [block addObserver:theCopy];
    }

    return theCopy;
}

#pragma mark - iTermLineBlockObserver

- (void)lineBlockDidChange:(LineBlock *)lineBlock {
    if (lineBlock == _head) {
        _headDirty = YES;
    } else if (lineBlock == _tail) {
        _tailDirty = YES;
    }
}

@end
