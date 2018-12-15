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

- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];

    __block int r;
    const NSInteger result = [self internalIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&r];
    if (remainderPtr) {
        *remainderPtr = r;
    }
    return result;
}

- (NSInteger)internalIndexOfBlockContainingLineNumber:(int)lineNumber
                                                width:(int)width
                                            remainder:(out nonnull int *)remainderPtr {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];
    iTermCumulativeSumCache *numLinesCache = [_numLinesCaches numLinesCacheForWidth:width];
    const NSInteger index = [numLinesCache indexContainingValue:lineNumber];

    if (index == NSNotFound) {
        return NSNotFound;
    }

    if (remainderPtr) {
        if (index == 0) {
            *remainderPtr = lineNumber;
        } else {
            const NSInteger absoluteLineNumber = lineNumber - numLinesCache.offset;
            *remainderPtr = absoluteLineNumber - [numLinesCache sumAtIndex:index - 1];
        }
    }
    return index;
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
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];

    return [[_numLinesCaches numLinesCacheForWidth:width] sumOfAllValues];
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
        [self updateCacheIfNeeded];
        const NSInteger result = _rawLinesCache.sumOfAllValues;
        return result;
    } else {
        return [self slow_numberOfRawLines];
    }
}

- (NSInteger)slow_numberOfRawLines {
    NSInteger sum = 0;
    for (LineBlock *block in _blocks) {
        int n = [block numRawLines];
        sum += n;
    }
    return sum;
}

- (NSInteger)rawSpaceUsed {
    return [self rawSpaceUsedInRangeOfBlocks:NSMakeRange(0, _blocks.count)];
}

- (NSInteger)rawSpaceUsedInRangeOfBlocks:(NSRange)range{
    if (_rawSpaceCache) {
        [self updateCacheIfNeeded];
        const NSInteger result = [_rawSpaceCache sumOfValuesInRange:range];
        return result;
    } else {
        return [self slow_rawSpaceUsedInRangeOfBlocks:range];
    }
}

- (NSInteger)slow_rawSpaceUsedInRangeOfBlocks:(NSRange)range {
    NSInteger position = 0;
    for (NSInteger i = 0; i < range.length; i++) {
        LineBlock *block = _blocks[i + range.location];
        int  n = [block rawSpaceUsed];
        position += n;
    }
    return position;
}

- (LineBlock *)blockContainingPosition:(long long)position
                                 width:(int)width
                             remainder:(int *)remainderPtr
                           blockOffset:(int *)yoffsetPtr
                                 index:(int *)indexPtr {
    if (width > 0) {
        [self buildCacheForWidth:width];
    }
    [self updateCacheIfNeeded];
    if (width > 0 && _rawSpaceCache) {
        int r=0, y=0, i=0;
        LineBlock *result = [self fast_blockContainingPosition:position width:width remainder:&r blockOffset:yoffsetPtr ? &y : NULL index:&i];
        if (remainderPtr) {
            *remainderPtr = r;
        }
        if (yoffsetPtr) {
            *yoffsetPtr = y;
        }
        if (indexPtr) {
            *indexPtr = i;
        }
        return result;
    } else {
        return [self slow_blockContainingPosition:position width:width remainder:remainderPtr blockOffset:yoffsetPtr index:indexPtr];
    }
}

- (LineBlock *)fast_blockContainingPosition:(long long)position
                                      width:(int)width
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)yoffsetPtr
                                      index:(int *)indexPtr {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];
    NSInteger index = [_rawSpaceCache indexContainingValue:position];
    if (index == NSNotFound) {
        return nil;
    }

    if (remainderPtr) {
        *remainderPtr = position - [_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)];
    }
    if (yoffsetPtr) {
        *yoffsetPtr = [[_numLinesCaches numLinesCacheForWidth:width] sumOfValuesInRange:NSMakeRange(0, index)];
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
