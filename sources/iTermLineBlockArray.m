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

typedef struct {
    BOOL tailIsEmpty;
} LineBlockArrayCacheHint;

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
- (NSSet<NSNumber *> *)cachedWidths;
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

- (NSString *)dumpWidths:(NSSet<NSNumber *> *)widths {
    return [[_caches mapWithBlock:^id(iTermTuple<NSNumber *,iTermCumulativeSumCache *> *anObject) {
        if ([widths containsObject:anObject.firstObject]) {
            return [NSString stringWithFormat:@"Cache for width %@:\n%@", anObject.firstObject, anObject.secondObject];
        } else {
            return nil;
        }
    }] componentsJoinedByString:@"\n\n"];
}

- (NSString *)dumpForCrashlog {
    return [[_caches mapWithBlock:^id(iTermTuple<NSNumber *,iTermCumulativeSumCache *> *anObject) {
        return [NSString stringWithFormat:@"Cache for width %@:\n%@", anObject.firstObject, anObject.secondObject];
    }] componentsJoinedByString:@"\n\n"];
}

- (NSSet<NSNumber *> *)cachedWidths {
    return [NSSet setWithArray:[_caches mapWithBlock:^id(iTermTuple<NSNumber *,iTermCumulativeSumCache *> *anObject) {
        return [anObject firstObject];
    }]];
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

- (void)setLastValue:(NSInteger)value {
    for (iTermTuple<NSNumber *, iTermCumulativeSumCache *> *tuple in _caches) {
        [tuple.secondObject setLastValue:value];
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

static NSUInteger iTermLineBlockArrayNextUniqueID;

@implementation iTermLineBlockArray {
    NSUInteger _uid;
    NSMutableArray<LineBlock *> *_blocks;
    BOOL _mayHaveDoubleWidthCharacter;
    iTermLineBlockCacheCollection *_numLinesCaches;

    iTermCumulativeSumCache *_rawSpaceCache;
    iTermCumulativeSumCache *_rawLinesCache;

    LineBlock *_head;
    LineBlock *_tail;
    NSUInteger _lastHeadGeneration;
    NSUInteger _lastTailGeneration;
    // NOTE: Update -copyWithZone: if you add member variables.
}

- (instancetype)init {
    self = [super init];
    if (self) {
        @synchronized ([iTermLineBlockArray class]) {
            _uid = iTermLineBlockArrayNextUniqueID++;
        }
        _blocks = [NSMutableArray array];
        _numLinesCaches = [[iTermLineBlockCacheCollection alloc] init];
        _lastHeadGeneration = [self generationOf:nil];
        _lastTailGeneration = [self generationOf:nil];
    }
    return self;
}

- (void)dealloc {
    // Do this serially to avoid lock contention.
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.free-line-blocks", DISPATCH_QUEUE_SERIAL);
    });
    NSMutableArray<LineBlock *> *blocks = _blocks;
    dispatch_async(queue, ^{
        [blocks removeAllObjects];
    });
}

- (NSString *)dumpForCrashlog {
    return [_numLinesCaches dumpForCrashlog];
}

- (NSString *)dumpWidths:(NSSet<NSNumber *> *)widths {
    return [_numLinesCaches dumpWidths:widths];
}

- (NSSet<NSNumber *> *)cachedWidths {
    return _numLinesCaches.cachedWidths;
}

- (BOOL)isEqual:(id)object {
    iTermLineBlockArray *other = [iTermLineBlockArray castFrom:object];
    if (!other) {
        return NO;
    }
    if (self.count != other.count) {
        return NO;
    }
    for (NSInteger i = 0; i < self.count; i++) {
        LineBlock *lhs = self[i];
        LineBlock *rhs = other[i];
        if (![lhs isEqual:rhs]) {
            return NO;
        }
    }
    return YES;
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
    VLog(@"indexOfBlockContainingLineNumber:%@ width:%@", @(lineNumber), @(width));
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];

    __block int r = 0;
    const NSInteger result = [self internalIndexOfBlockContainingLineNumber:lineNumber width:width remainder:&r];
    if (remainderPtr) {
        VLog(@"indexOfBlockContainingLineNumber: remainderPtr <- %@", @(r));
        *remainderPtr = r;
    }
    VLog(@"indexOfBlockContainingLineNumber:%@ width:%@ returning %@", @(lineNumber), @(width), @(result));
    return result;
}

- (NSInteger)internalIndexOfBlockContainingLineNumber:(int)lineNumber
                                                width:(int)width
                                            remainder:(out nonnull int *)remainderPtr {
    VLog(@"internalIndexOfBlockContainingLineNumber:%@ width:%@", @(lineNumber), @(width));
    
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];
    iTermCumulativeSumCache *numLinesCache = [_numLinesCaches numLinesCacheForWidth:width];
    BOOL roundUp = YES;
    const NSInteger index = [numLinesCache indexContainingValue:lineNumber roundUp:&roundUp];

    if (index == NSNotFound) {
        VLog(@"internalIndexOfBlockContainingLineNumber returning NSNotFound because indexContainingvalue:roundUp returned NSNotFound");
        return NSNotFound;
    }

    if (remainderPtr) {
        VLog(@"internalIndexOfBlockContainingLineNumber: Have a remainder pointer");
        if (index == 0) {
            VLog(@"internalIndexOfBlockContainingLineNumber: index==0: *remainderPtr <- %@", @(lineNumber));
            *remainderPtr = lineNumber;
        } else {
            const NSInteger absoluteLineNumber = lineNumber - numLinesCache.offset;
            *remainderPtr = absoluteLineNumber - [numLinesCache sumAtIndex:index - 1];
            VLog(@"internalIndexOfBlockContainingLineNumber: index!=0: absoluteLineNumber=%@, *remainderPtr <- %@",
                  @(absoluteLineNumber), @(*remainderPtr));
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
        if (!block.isEmpty) {
            assert(*remainderPtr < nl);
        }
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
                        block:(void (^)(const screen_char_t * _Nonnull,
                                        int,
                                        int,
                                        screen_char_t,
                                        iTermImmutableMetadata,
                                        BOOL * _Nullable))callback {
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
        int line = remainder;
        do {
            int length, eol;
            screen_char_t continuation;
            int temp = line;
            iTermImmutableMetadata metadata;
            const screen_char_t *chars = [block getWrappedLineWithWrapWidth:width
                                                                    lineNum:&temp
                                                                 lineLength:&length
                                                          includesEndOfLine:&eol
                                                                    yOffset:NULL
                                                               continuation:&continuation
                                                       isStartOfWrappedLine:NULL
                                                                   metadata:&metadata];
            if (chars == NULL) {
                return;
            }
            ITAssertWithMessage(length <= width, @"Length too long");
            callback(chars, length, eol, continuation, metadata, &stop);
            if (stop) {
                return;
            }
            numberLeft--;
            line++;
        } while (numberLeft > 0 && block_lines >= remainder);
        remainder = line;
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
                               yOffset:(int)yOffset
                                 width:(int)width
                             remainder:(int *)remainderPtr
                           blockOffset:(int *)blockOffsetPtr
                                 index:(int *)indexPtr {
    if (position < 0) {
        DLog(@"Block with negative position %@ requested, returning nil", @(position));
        return nil;
    }
    if (width > 0) {
        [self buildCacheForWidth:width];
    }
    [self updateCacheIfNeeded];
    if (width > 0 && _rawSpaceCache) {
        int r=0, y=0, i=0;
        LineBlock *result = [self fast_blockContainingPosition:position
                                                       yOffset:yOffset
                                                         width:width
                                                     remainder:&r
                                                   blockOffset:blockOffsetPtr ? &y : NULL
                                                         index:&i];
        if (remainderPtr) {
            *remainderPtr = r;
        }
        if (blockOffsetPtr) {
            *blockOffsetPtr = y;
        }
        if (indexPtr) {
            *indexPtr = i;
        }
        return result;
    } else {
        return [self slow_blockContainingPosition:position
                                          yOffset:yOffset
                                            width:width
                                        remainder:remainderPtr
                                      blockOffset:blockOffsetPtr
                                            index:indexPtr];
    }
}

- (LineBlock *)fast_blockContainingPosition:(long long)position
                                    yOffset:(int)originalDesiredYOffset
                                      width:(int)width
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)blockOffsetPtr
                                      index:(int *)indexPtr {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];
    BOOL roundUp = NO;
    NSInteger index = [_rawSpaceCache indexContainingValue:position roundUp:&roundUp];
    if (index == NSNotFound) {
        return nil;
    }
    LineBlock *block = _blocks[index];

    // To avoid double-counting Y offsetes, reduce the offset in lines within the block by the number
    // of empty lines that were skipped.
    int dy = 0;

    int desiredYOffset = originalDesiredYOffset;
    if (roundUp) {
        // Seek forward until we find a block that contains this position.
        if (block.numberOfTrailingEmptyLines <= desiredYOffset) {
            // Skip over trailing lines.
            const int emptyCount = block.numberOfTrailingEmptyLines;
            desiredYOffset -= emptyCount;
            // In the diagrams below the | indicates the location given by position.
            //
            // Cases 1 and 2 involve the unfortunate behavior that occurds for the position after a
            // non-empty line not belonging to the next wrapped line but to the location just after
            // the last character on the non-empty line.
            //
            // 1. The block has trailing empty lines
            //        abc
            //        xyz|
            //        (empty)
            //    In this case, advancing to the next block moves the cursor down two lines:
            //    first to the start of the empty line and then to the start of the line after it.
            //
            // 2. The block does not have trailing empty lines
            //        abc
            //        xyz|
            //    In this case, advancing to the next block moves the cursor down one line: just to
            //    the beginning of the line that starts the next block.
            //
            // 3. The block has only empty lines.
            //        |(empty)
            //        (empty)
            //    In this case, advancing the the next block moves the cursor down by the number of
            //    empty lines in this block.
            dy += emptyCount;
            if (!block.allLinesAreEmpty) {
                // case 1 or 2
                dy += 1;
            }
            index += 1;
            block = _blocks[index];

            // Skip over entirely empty blocks.
            while (!block.containsAnyNonEmptyLine &&
                   block.numberOfLeadingEmptyLines <= desiredYOffset &&
                   index + 1 < _blocks.count) {
                const int emptyCount = block.numberOfTrailingEmptyLines;
                desiredYOffset -= emptyCount;
                // Here this is no +1. We begin with something like:
                //     |(empty)
                //     (empty)
                // Moving the cursor to the next block advances by exactly as many lines as the
                // number of lines in the block.
                dy += emptyCount;
                index += 1;
                block = _blocks[index];
            }
        }
    }

    if (remainderPtr) {
        *remainderPtr = position - [_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)];
        assert(*remainderPtr >= 0);
    }
    if (blockOffsetPtr) {
        *blockOffsetPtr = [[_numLinesCaches numLinesCacheForWidth:width] sumOfValuesInRange:NSMakeRange(0, index)] - dy;
    }
    if (indexPtr) {
        *indexPtr = index;
    }
    return block;
}

// TODO: Test the case where the position is at the start of block 1 (pos=1, desiredYOffset=1) in this example:
// block 0
// x
//
// block 1
// (empty)
// (empty)
// y

- (LineBlock *)slow_blockContainingPosition:(long long)position
                                    yOffset:(int)desiredYOffset
                                      width:(int)width
                                  remainder:(int *)remainderPtr
                                blockOffset:(int *)blockOffsetPtr
                                      index:(int *)indexPtr {
    long long p = position;
    int emptyLinesLeftToSkip = desiredYOffset;
    int yoffset = 0;
    int index = 0;
    for (LineBlock *block in _blocks) {
        const int used = [block rawSpaceUsed];
        BOOL found = NO;
        if (p > used) {
            // It's definitely not in this block.
            p -= used;
            if (blockOffsetPtr) {
                yoffset += [block getNumLinesWithWrapWidth:width];
            }
        } else if (p == used) {
            // It might be in this block!
            if (blockOffsetPtr) {
                yoffset += [block getNumLinesWithWrapWidth:width];
            }
            const int numTrailingEmptyLines = [block numberOfTrailingEmptyLines];
            if (numTrailingEmptyLines < emptyLinesLeftToSkip) {
                // Need to keep consuming empty lines.
                emptyLinesLeftToSkip -= numTrailingEmptyLines;
                p = 0;
            } else {
                // This block has enough trailing blank lines.
                found = YES;
            }
        } else {
            // It was not in the previous block and this one has enough raw spaced used that it must
            // contain it.
            found = YES;
        }
        if (found) {
            // It is in this block.
            assert(p >= 0);
            if (remainderPtr) {
                *remainderPtr = p;
            }
            if (blockOffsetPtr) {
                *blockOffsetPtr = yoffset;
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

- (NSInteger)numberOfWrappedLinesForWidth:(int)width
                          upToBlockAtIndex:(NSInteger)limit {
    [self buildCacheForWidth:width];
    [self updateCacheIfNeeded];

    return [[_numLinesCaches numLinesCacheForWidth:width] sumOfValuesInRange:NSMakeRange(0, limit)];
}

#pragma mark - Low level method

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return _blocks[index];
}

- (NSUInteger)generationOf:(LineBlock *)lineBlock {
    if (!lineBlock) {
        return 0xffffffffffffffffLL;
    }
    return (((NSUInteger)lineBlock.index) << 32) | lineBlock.generation;
}

- (LineBlock *)addBlockOfSize:(int)size 
                       number:(long long)number
  mayHaveDoubleWidthCharacter:(BOOL)mayHaveDoubleWidthCharacter {
    LineBlock* block = [[LineBlock alloc] initWithRawBufferSize:size absoluteBlockNumber:number];
    block.mayHaveDoubleWidthCharacter = mayHaveDoubleWidthCharacter;
    [self addBlock:block hints:(LineBlockArrayCacheHint){ .tailIsEmpty = YES }];
    return block;
}

- (void)addBlock:(LineBlock *)block {
    [self addBlock:block hints:(LineBlockArrayCacheHint){0}];
}

- (void)addBlock:(LineBlock *)block hints:(LineBlockArrayCacheHint)hints {
    [self updateCacheIfNeeded];
    [_blocks addObject:block];
    if (_blocks.count == 1) {
        _head = block;
        _lastHeadGeneration = [self generationOf:block];
    }
    _tail = block;
    _lastTailGeneration = [self generationOf:block];
    [_numLinesCaches appendValue:0];
    if (_rawSpaceCache) {
        [_rawSpaceCache appendValue:0];
        [_rawLinesCache appendValue:0];
        // The block might not be empty. Treat it like a bunch of lines just got appended.
        if (hints.tailIsEmpty && _blocks.count > 1) {
            // NOTE: If you update this also update updateCacheForBlock:
            _lastTailGeneration = [self generationOf:block];
            [_numLinesCaches setLastValue:0];
            [_rawSpaceCache setLastValue:0];
            [_rawLinesCache setLastValue:0];
        } else {
            [self updateCacheForBlock:block];
        }
    }
}

- (void)removeFirstBlock {
    [self updateCacheIfNeeded];
    [_blocks.firstObject invalidate];
    [_numLinesCaches removeFirstValue];
    [_rawSpaceCache removeFirstValue];
    [_rawLinesCache removeFirstValue];
    [_blocks removeObjectAtIndex:0];
    _head = _blocks.firstObject;
    _lastHeadGeneration = [self generationOf:_head];
    _tail = _blocks.lastObject;
    _lastTailGeneration = [self generationOf:_tail];
}

- (void)removeFirstBlocks:(NSInteger)count {
    for (NSInteger i = 0; i < count; i++) {
        [self removeFirstBlock];
    }
}

- (void)removeLastBlock {
    [self updateCacheIfNeeded];
    [_blocks.lastObject invalidate];
    [_blocks removeLastObject];
    [_numLinesCaches removeLastValue];
    [_rawSpaceCache removeLastValue];
    [_rawLinesCache removeLastValue];
    _head = _blocks.firstObject;
    _lastHeadGeneration = [self generationOf:_head];
    _tail = _blocks.lastObject;
    _lastTailGeneration = [self generationOf:_tail];
}

- (NSUInteger)count {
    return _blocks.count;
}

- (LineBlock *)lastBlock {
    return _blocks.lastObject;
}

- (LineBlock *)firstBlock {
    return _blocks.firstObject;
}

// NOTE: If you modify this also modify addBlock:hints:
- (void)updateCacheForBlock:(LineBlock *)block {
    if (_rawSpaceCache) {
        assert(_rawSpaceCache.count == _blocks.count);
        assert(_rawLinesCache.count == _blocks.count);
    }
    assert(_blocks.count > 0);

    if (block == _blocks.firstObject) {
        _lastHeadGeneration = [self generationOf:_head];
        [_numLinesCaches setFirstValueWithBlock:^NSInteger(int width) {
            const int value = [block getNumLinesWithWrapWidth:width];
            return value;
        }];
        [_rawSpaceCache setFirstValue:[block rawSpaceUsed]];
        [_rawLinesCache setFirstValue:[block numRawLines]];
        if (block == _blocks.lastObject) {
            _lastTailGeneration = [self generationOf:_tail];
        }
    } else if (block == _blocks.lastObject) {
        // NOTE: If you modify this also modify addBlock:hints:
        _lastTailGeneration = [self generationOf:_tail];
        [_numLinesCaches setLastValueWithBlock:^NSInteger(int width) {
            const int value = [block getNumLinesWithWrapWidth:width];
            return value;
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
    [self reallyUpdateCacheIfNeeded];
    const int w = [[[self cachedWidths] anyObject] intValue];
    for (int i = 0; i < _blocks.count; i++) {
        LineBlock *block = _blocks[i];
        BOOL ok = [block numRawLines] == [_rawLinesCache valueAtIndex:i];
        if (ok && w > 0) {
            ok = [block getNumLinesWithWrapWidth:w] == [[_numLinesCaches numLinesCacheForWidth:w] valueAtIndex:i];
        }
        if (!ok) {
            [self oopsWithWidth:0 block:^{
                DLog(@"Sanity check failed");
            }];

        }
    }
}

- (void)updateCacheIfNeeded {
    [self reallyUpdateCacheIfNeeded];
#ifdef DEBUG_LINEBUFFER_MERGE
    [self sanityCheck];
#endif
}

- (void)reallyUpdateCacheIfNeeded {
    if (_lastHeadGeneration != [self generationOf:_head]) {
        [self updateCacheForBlock:_blocks.firstObject];
    }
    if (_lastTailGeneration != [self generationOf:_tail]) {
        [self updateCacheForBlock:_blocks.lastObject];
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermLineBlockArray *theCopy = [[self.class alloc] init];
    theCopy->_blocks = [NSMutableArray array];
    for (LineBlock *block in _blocks) {
        LineBlock *copiedBlock = [block cowCopy];
        [theCopy->_blocks addObject:copiedBlock];
    }
    theCopy->_numLinesCaches = [_numLinesCaches copy];
    theCopy->_rawSpaceCache = [_rawSpaceCache copy];
    theCopy->_rawLinesCache = [_rawLinesCache copy];
    theCopy->_mayHaveDoubleWidthCharacter = _mayHaveDoubleWidthCharacter;
    theCopy->_head = theCopy->_blocks.firstObject;
    theCopy->_lastHeadGeneration = _lastHeadGeneration;
    theCopy->_tail = theCopy->_blocks.lastObject;
    theCopy->_lastTailGeneration = _lastTailGeneration;
    theCopy->_resizing = _resizing;

    return theCopy;
}

@end
