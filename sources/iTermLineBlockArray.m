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
#import "LineBlock+Private.h"
#import "NSArray+iTerm.h"

//#define DEBUG_LINEBUFFER_MERGE 1

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
        int rawLines = [block numRawLines];
        // A continuation block's first raw line is logically part of the
        // previous block's last raw line, so don't double-count it.
        if (block.startsWithContinuation) {
            rawLines -= 1;
        }
        [_rawLinesCache appendValue:rawLines];
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
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block.startsWithContinuation) {
            // The continuation block adjusts its first raw line's wrapped
            // count to account for prefix characters in the previous block.
            // The previous block keeps its full count (including its partial
            // last wrapped line).
            block_lines += [block continuationWrappedLineAdjustmentForWidth:width];
        }
        [numLinesCache appendValue:block_lines];
    }
    [_numLinesCaches setNumLinesCache:numLinesCache forWidth:width];
}

- (void)oopsWithWidth:(int)width droppedChars:(long long)droppedChars block:(void (^)(void))block {
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
        [block dump:width droppedChars:droppedChars toDebugLog:YES];
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
            ITBetaAssert(lineNumber >= 0, @"Negative remainder when index=0");
            *remainderPtr = lineNumber;
        } else {
            const NSInteger absoluteLineNumber = lineNumber - numLinesCache.offset;
            *remainderPtr = absoluteLineNumber - [numLinesCache sumAtIndex:index - 1];
            ITBetaAssert(*remainderPtr >= 0, @"Negative remainder when index!=0. lineNumber=%@ numLinesCache.offset=%@ sum(at: %@)=%@ remainder=%@", @(lineNumber), @(numLinesCache.offset), @(index-1), @([numLinesCache sumAtIndex:index - 1]), @(*remainderPtr));
            VLog(@"internalIndexOfBlockContainingLineNumber: index!=0: absoluteLineNumber=%@, *remainderPtr <- %@",
                  @(absoluteLineNumber), @(*remainderPtr));
        }
    }
    return index;
}

// Converts a "contributed" wrapped-line offset (from the cache) to a
// block-local wrapped-line index suitable for LineBlock APIs.
// When continuationWrappedLineAdjustmentForWidth: is negative, the
// continuation block has hidden wrapped lines at the start that overlap
// with the predecessor block. Add those back when reading.
- (int)localWrappedOffset:(int)contributedOffset forBlock:(LineBlock *)block width:(int)width {
    if (!block.startsWithContinuation) {
        return contributedOffset;
    }
    const int adjustment = [block continuationWrappedLineAdjustmentForWidth:width];
    // adjustment is <= 0. When -1, we need to skip 1 hidden line.
    return contributedOffset + MAX(0, -adjustment);
}

- (LineBlock *)blockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    return [self blockContainingLineNumber:lineNumber width:width remainder:remainderPtr blockIndex:NULL];
}

- (LineBlock *)blockContainingLineNumber:(int)lineNumber
                                   width:(int)width
                               remainder:(out nonnull int *)remainderPtr
                              blockIndex:(out nullable NSInteger *)blockIndexPtr {
    int remainder = 0;
    NSInteger i = [self indexOfBlockContainingLineNumber:lineNumber
                                                   width:width
                                               remainder:&remainder];
    if (i == NSNotFound) {
        return nil;
    }
    LineBlock *block = _blocks[i];

    if (remainderPtr) {
        *remainderPtr = [self localWrappedOffset:remainder forBlock:block width:width];
        int nl = [block getNumLinesWithWrapWidth:width];
        if (!block.isEmpty) {
            assert(*remainderPtr < nl);
        }
    }
    if (blockIndexPtr) {
        *blockIndexPtr = i;
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
        // Use the contributed (adjusted) line count for skipping blocks and
        // bounding the inner loop. The naive getNumLinesWithWrapWidth: count
        // can differ from the contributed count for continuation blocks.
        int contributed_lines = [block getNumLinesWithWrapWidth:width];
        if (block.startsWithContinuation) {
            const int adj = [block continuationWrappedLineAdjustmentForWidth:width];
            contributed_lines += adj;
#if DEBUG
            // Hidden-line invariant: when adjustment == -1, the predecessor
            // must be able to produce a boundary stitch (short soft tail).
            if (adj == -1 && i > 0) {
                LineBlock *pred = _blocks[i - 1];
                const int predLines = [pred getNumLinesWithWrapWidth:width];
                int predLastLineNum = predLines - 1;
                int predLength = 0;
                int predEOL = EOL_HARD;
                [pred getWrappedLineWithWrapWidth:width
                                          lineNum:&predLastLineNum
                                       lineLength:&predLength
                                includesEndOfLine:&predEOL
                                     continuation:NULL];
                ITAssertWithMessage(predLength < width && predEOL == EOL_SOFT,
                                    @"Hidden-line invariant violated: predecessor block %@ "
                                    @"last line has length=%@ eol=%@ at width=%@, "
                                    @"expected short soft tail for stitch",
                                    @(i - 1), @(predLength), @(predEOL), @(width));
            }
#endif
        }
        if (contributed_lines <= remainder) {
            remainder -= contributed_lines;
            continue;
        }

        // Grab lines from this block until we're done or reach the end of the block.
        BOOL stop = NO;
        const int localLine = [self localWrappedOffset:remainder forBlock:block width:width];
        const int naiveLines = [block getNumLinesWithWrapWidth:width];
        int line = localLine;
        while (numberLeft > 0 && line < naiveLines) {
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
                break;
            }
            ITAssertWithMessage(length <= width, @"Length too long");

            // Use the shared stitch helper for boundary-spanning wrapped lines.
            ScreenCharArray *stitched = [self stitchedLineFromBlockAtIndex:i
                                                                     width:width
                                                     localWrappedLineIndex:line];
            if (stitched) {
                callback(stitched.line, stitched.length, stitched.eol,
                         stitched.continuation, stitched.metadata, &stop);
                if (stop) {
                    return;
                }
                numberLeft--;
                line++;
                continue;
            }

            callback(chars, length, eol, continuation, metadata, &stop);
            if (stop) {
                return;
            }
            numberLeft--;
            line++;
        }
        remainder = 0;
        if (numberLeft == 0) {
            break;
        }
    }
    ITAssertWithMessage(numberLeft == 0, @"not all lines available in range %@. Have %@ remaining.", NSStringFromRange(range), @(numberLeft));
}

- (ScreenCharArray *)stitchedLineFromBlockAtIndex:(NSInteger)blockIndex
                                            width:(int)width
                            localWrappedLineIndex:(int)localWrappedLineIndex {
    if (blockIndex + 1 >= (NSInteger)_blocks.count) {
        return nil;
    }
    LineBlock *currentBlock = _blocks[blockIndex];
    LineBlock *nextBlock = _blocks[blockIndex + 1];
    if (!nextBlock.startsWithContinuation) {
        return nil;
    }
    const int pCol = nextBlock.continuationPrefixCharacters % width;
    if (pCol == 0) {
        return nil;
    }
    // Verify this is the predecessor's last local wrapped line.
    const int naiveLines = [currentBlock getNumLinesWithWrapWidth:width];
    if (localWrappedLineIndex != naiveLines - 1) {
        return nil;
    }

    // Re-fetch the tail (predecessor's last wrapped line) at explicit index.
    int tailLineNum = naiveLines - 1;
    int tailLength = 0;
    int tailEOL = EOL_SOFT;
    screen_char_t tailContinuation = { 0 };
    iTermImmutableMetadata tailMetadata;
    const screen_char_t *tail = [currentBlock getWrappedLineWithWrapWidth:width
                                                                  lineNum:&tailLineNum
                                                               lineLength:&tailLength
                                                        includesEndOfLine:&tailEOL
                                                                  yOffset:NULL
                                                             continuation:&tailContinuation
                                                     isStartOfWrappedLine:NULL
                                                                 metadata:&tailMetadata];
    if (!tail || tailLength >= width || tailLength == 0 || tailEOL != EOL_SOFT) {
        return nil;
    }

    // Get the head directly from the next block's first raw line.
    // This works for both adjustment==-1 (hidden head at offset 0) and
    // adjustment==0 (head chars at offset 0 that aren't part of any
    // contributed line). Using rawLine avoids depending on
    // cacheAwareOffsetOfWrappedLineInBuffer.
    const screen_char_t *rawHead = [nextBlock rawLine:nextBlock.firstEntry];
    const int rawHeadLength = [nextBlock lengthOfRawLine:nextBlock.firstEntry];
    // A zero-length first raw line is valid (e.g., immediate hard-EOL append).
    // We still need to stitch so the predecessor tail gets correct EOL semantics.
    if (rawHeadLength < 0 || (rawHeadLength > 0 && !rawHead)) {
        return nil;
    }

    const int headNeeded = width - tailLength;
    const BOOL consumedEntireHead = (rawHeadLength <= headNeeded);
    const int usedLength = MIN(headNeeded, rawHeadLength);
    screen_char_t *buf = (screen_char_t *)malloc(sizeof(screen_char_t) * width);
    memcpy(buf, tail, sizeof(screen_char_t) * tailLength);
    if (usedLength > 0) {
        memcpy(buf + tailLength, rawHead, sizeof(screen_char_t) * usedLength);
    }
    for (int i = tailLength + usedLength; i < width; i++) {
        buf[i] = tailContinuation;
        buf[i].code = 0;
        buf[i].complexChar = NO;
    }
    // Preserve the tail's style fields (fg/bg color, bold, italic, etc.)
    // in the stitched continuation. Only update the EOL code based on
    // whether the head was fully consumed.
    screen_char_t stitchedContinuation = tailContinuation;
    if (consumedEntireHead) {
        // Get the EOL from the next block's first wrapped line to determine
        // whether the stitched line ends (EOL_HARD) or wraps (EOL_SOFT).
        int tempLineNum = 0;
        int tempLength = 0;
        int tempEOL = EOL_SOFT;
        screen_char_t tempCont = { 0 };
        [nextBlock getWrappedLineWithWrapWidth:width
                                       lineNum:&tempLineNum
                                    lineLength:&tempLength
                             includesEndOfLine:&tempEOL
                                  continuation:&tempCont];
        stitchedContinuation.code = tempEOL;
    } else {
        stitchedContinuation.code = EOL_SOFT;
    }
    // Merge metadata in display order: tail then head, using the same
    // append semantics as the monolithic appendToLastLine path.
    ScreenCharArray *result;
    if (usedLength > 0) {
        iTermImmutableMetadata headRawMeta = [nextBlock screenCharArrayForRawLine:nextBlock.firstEntry].metadata;
        iTermMetadata headSlice;
        iTermMetadataInitCopyingSubrange(&headSlice, &headRawMeta, 0, usedLength);
        iTermImmutableMetadata immutableHeadSlice = iTermMetadataMakeImmutable(headSlice);

        iTermMetadata merged = iTermImmutableMetadataMutableCopy(tailMetadata);
        iTermMetadataAppend(&merged, tailLength, &immutableHeadSlice, usedLength);

        result = [[ScreenCharArray alloc] initWithLine:buf
                                                length:tailLength + usedLength
                                              metadata:iTermMetadataMakeImmutable(merged)
                                          continuation:stitchedContinuation
                                         freeOnRelease:YES];
        iTermMetadataRelease(headSlice);
        iTermMetadataRelease(merged);
    } else {
        result = [[ScreenCharArray alloc] initWithLine:buf
                                                length:tailLength + usedLength
                                              metadata:tailMetadata
                                          continuation:stitchedContinuation
                                         freeOnRelease:YES];
    }
    return result;
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
        if (block.startsWithContinuation) {
            n -= 1;
        }
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

    // To avoid double-counting Y offsets, reduce the offset in lines within the block by the number
    // of empty lines that were skipped.
    int dy = 0;
    int additionalRemainder = 0;
    int desiredYOffset = originalDesiredYOffset;
    if (roundUp) {
        // Seek forward until we find a block that contains this position.
        if (block.numberOfTrailingEmptyLines <= desiredYOffset) {
            // Skip over trailing lines.
            const int emptyCount = block.numberOfTrailingEmptyLines;
            desiredYOffset -= emptyCount;
            // In the diagrams below the | indicates the location given by position.
            //
            // Cases 1 and 2 involve the unfortunate behavior that occurs for the position after a
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
                if (block.numberOfTrailingEmptyLines == 0) {
                    // Case 2
                    // The X position will be equal to the length of the last wrapped line.
                    // For case 1, the x position will be 0.
                    additionalRemainder = [block lengthOfLastWrappedLineForWidth:width];
                }
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
        *remainderPtr = position - [_rawSpaceCache sumOfValuesInRange:NSMakeRange(0, index)] + additionalRemainder;
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
                int lines = [block getNumLinesWithWrapWidth:width];
                if (block.startsWithContinuation) {
                    lines += [block continuationWrappedLineAdjustmentForWidth:width];
                }
                yoffset += lines;
            }
        } else if (p == used) {
            // It might be in this block!
            if (blockOffsetPtr) {
                int lines = [block getNumLinesWithWrapWidth:width];
                if (block.startsWithContinuation) {
                    lines += [block continuationWrappedLineAdjustmentForWidth:width];
                }
                yoffset += lines;
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

- (NSInteger)numberOfRawLinesInRange:(NSRange)range width:(int)width {
    if (range.length == 0) {
        return 0;
    }

    // Step 1: Find which blocks contain your wrapped lines
    int startWrappedLineInBlock = 0;
    NSInteger startBlockIndex = [self indexOfBlockContainingLineNumber:range.location
                                                                        width:width
                                                                    remainder:&startWrappedLineInBlock];

    int endWrappedLineInBlock = 0;
    NSInteger endBlockIndex = [self indexOfBlockContainingLineNumber:NSMaxRange(range) - 1
                                                                      width:width
                                                                  remainder:&endWrappedLineInBlock];

    if (startBlockIndex == NSNotFound || endBlockIndex == NSNotFound) {
        return 0;
    }

    // Step 2: Convert wrapped line offsets to raw line numbers within their blocks
    LineBlock *startBlock = self[startBlockIndex];
    NSNumber *startRawLineNum = [startBlock rawLineNumberAtWrappedLineOffset:[self localWrappedOffset:startWrappedLineInBlock forBlock:startBlock width:width]
                                                                       width:width];

    LineBlock *endBlock = self[endBlockIndex];
    NSNumber *endRawLineNum = [endBlock rawLineNumberAtWrappedLineOffset:[self localWrappedOffset:endWrappedLineInBlock forBlock:endBlock width:width]
                                                                   width:width];

    // Step 3: Count raw lines
    if (startBlockIndex == endBlockIndex) {
        // Same block - simple subtraction
        return [endRawLineNum intValue] - [startRawLineNum intValue] + 1;
    } else {
        // Multiple blocks - sum raw lines across blocks
        int count = 0;

        // Raw lines from start to end of first block
        count += (startBlock.numRawLines - [startRawLineNum intValue]);

        // All raw lines in intermediate blocks
        for (NSInteger i = startBlockIndex + 1; i < endBlockIndex; i++) {
            int n = _blocks[i].numRawLines;
            if (_blocks[i].startsWithContinuation) {
                n -= 1;
            }
            count += n;
        }

        // Raw lines from start of last block to end position.
        // If the end block starts with continuation, its raw line 0 is
        // the same raw line as the previous block's last line, which
        // was already counted.
        int endRawLines = [endRawLineNum intValue] + 1;
        if (endBlock.startsWithContinuation) {
            endRawLines -= 1;
        }
        count += endRawLines;
        return count;
    }
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
    [_delegate lineBlockArrayDidChange:self];
}

- (void)removeFirstBlock {
    [self updateCacheIfNeeded];
    [_blocks.firstObject invalidate];
    [_numLinesCaches removeFirstValue];
    [_rawSpaceCache removeFirstValue];
    [_rawLinesCache removeFirstValue];
    [_blocks removeObjectAtIndex:0];
    _head = _blocks.firstObject;
    // If the new head was a continuation of the removed block, clear its
    // continuation status and recompute its cached values since it's now
    // a standalone block.
    if (_head.startsWithContinuation) {
        const int oldPrefixCharacters = _head.continuationPrefixCharacters;
        [_head clearContinuation];
        // The raw lines cache entry needs +1 (was decremented for continuation).
        if (_rawLinesCache) {
            const NSInteger rawValue = [_rawLinesCache valueAtIndex:0];
            [_rawLinesCache setFirstValue:rawValue + 1];
        }
        // The num lines cache entries need recomputation.
        // The head's wrapped count was adjusted down; restore to unadjusted.
        __weak __typeof(self) weakSelf = self;
        [_numLinesCaches setFirstValueWithBlock:^NSInteger(int width) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return 0;
            }
            return [strongSelf->_head getNumLinesWithWrapWidth:width];
        }];
        (void)oldPrefixCharacters;
    }
    _lastHeadGeneration = [self generationOf:_head];
    _tail = _blocks.lastObject;
    _lastTailGeneration = [self generationOf:_tail];
    [_delegate lineBlockArrayDidChange:self];
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
    [_delegate lineBlockArrayDidChange:self];
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
            int value = [block getNumLinesWithWrapWidth:width];
            if (block.startsWithContinuation) {
                value += [block continuationWrappedLineAdjustmentForWidth:width];
            }
            return value;
        }];
        [_rawSpaceCache setFirstValue:[block rawSpaceUsed]];
        int rawLines = [block numRawLines];
        if (block.startsWithContinuation) {
            rawLines -= 1;
        }
        [_rawLinesCache setFirstValue:rawLines];
        if (block == _blocks.lastObject) {
            _lastTailGeneration = [self generationOf:_tail];
        }
    } else if (block == _blocks.lastObject) {
        // NOTE: If you modify this also modify addBlock:hints:
        _lastTailGeneration = [self generationOf:_tail];
        [_numLinesCaches setLastValueWithBlock:^NSInteger(int width) {
            int value = [block getNumLinesWithWrapWidth:width];
            if (block.startsWithContinuation) {
                value += [block continuationWrappedLineAdjustmentForWidth:width];
            }
            return value;
        }];
        [_rawSpaceCache setLastValue:[block rawSpaceUsed]];
        int rawLines = [block numRawLines];
        if (block.startsWithContinuation) {
            rawLines -= 1;
        }
        [_rawLinesCache setLastValue:rawLines];
    } else {
        ITAssertWithMessage(block == _blocks.firstObject || block == _blocks.lastObject,
                            @"Block with index %@/%@ changed", @([_blocks indexOfObject:block]), @(_blocks.count));
    }
}

- (void)sanityCheck {
    [self sanityCheck:0];
}

- (void)sanityCheck:(long long)droppedChars {
    if (_rawLinesCache == nil) {
        return;
    }
    [self reallyUpdateCacheIfNeeded];
    const int w = [[[self cachedWidths] anyObject] intValue];
    for (int i = 0; i < _blocks.count; i++) {
        LineBlock *block = _blocks[i];
        int expectedRawLines = [block numRawLines];
        if (block.startsWithContinuation) {
            expectedRawLines -= 1;
        }
        BOOL ok = expectedRawLines == [_rawLinesCache valueAtIndex:i];
        if (ok && w > 0) {
            int expectedWrappedLines = [block totallyUncachedNumLinesWithWrapWidth:w];
            if (block.startsWithContinuation) {
                expectedWrappedLines += [block continuationWrappedLineAdjustmentForWidth:w];
            }
            ok = expectedWrappedLines == [[_numLinesCaches numLinesCacheForWidth:w] valueAtIndex:i];
        }
        if (!ok) {
            [self oopsWithWidth:0 droppedChars:droppedChars block:^{
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
