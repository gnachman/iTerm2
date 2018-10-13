//
//  iTermLineBlockArray.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import "iTermLineBlockArray.h"
#import "LineBlock.h"

@interface iTermLineBlockArray()
@end

@implementation iTermLineBlockArray {
    NSMutableArray<LineBlock *> *_blocks;
    NSMutableArray<NSNumber *> *_cache;  // If nonnil, gives the cumulative number of lines for each block and is 1:1 with _blocks
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // This causes the blocks to be released in a background thread.
    // When a LineBuffer is really gigantic, it can take
    // quite a bit of time to release all the blocks.
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
}

- (LineBlock *)blockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr {
    int line = lineNumber;
    for (LineBlock *block in _blocks) {
        if (line == 0) {
            // I don't think a block will ever have 0 lines, but this prevents an infinite loop if that does happen.
            return block;
        }
        // getNumLinesWithWrapWidth caches its result for the last-used width so
        // this is usually faster than calling getWrappedLineWithWrapWidth since
        // most calls to the latter will just decrement line and return NULL.
        int block_lines = [block getNumLinesWithWrapWidth:width];
        if (block_lines <= line) {
            line -= block_lines;
            continue;
        }

        if (remainderPtr) {
            *remainderPtr = line;
        }
        return block;
    }
    return nil;
}

#pragma mark - Low level method

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return _blocks[index];
}

- (void)addBlock:(LineBlock *)block {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(lineBlockDidChange:)
                                                 name:iTermLineBlockDidChangeNotification
                                               object:block];
    [_blocks addObject:block];
}

- (void)removeFirstBlock {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:iTermLineBlockDidChangeNotification
                                                  object:_blocks[0]];
    [_blocks removeObjectAtIndex:0];
}

- (void)removeFirstBlocks:(NSInteger)count {
    for (NSInteger i = 0; i < count; i++) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:iTermLineBlockDidChangeNotification
                                                      object:_blocks[i]];
    }
    [_blocks removeObjectsInRange:NSMakeRange(0, count)];
}

- (void)removeLastBlock {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:iTermLineBlockDidChangeNotification
                                                  object:_blocks.lastObject];
    [_blocks removeLastObject];
}

- (NSUInteger)count {
    return _blocks.count;
}

- (LineBlock *)lastBlock {
    return _blocks.lastObject;
}

- (void)lineBlockDidChange:(NSNotification *)notification {
    _cache = nil;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermLineBlockArray *theCopy = [[self.class alloc] init];
    theCopy->_blocks = [_blocks mutableCopy];
    return theCopy;
}

@end
