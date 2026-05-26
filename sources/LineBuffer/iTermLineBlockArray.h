//
//  iTermLineBlockArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import <Foundation/Foundation.h>
#import "ScreenCharArray.h"
#import "iTermMetadata.h"

NS_ASSUME_NONNULL_BEGIN

@class LineBlock;
@class iTermLineBlockArray;

@protocol iTermLineBlockArrayDelegate <NSObject>
- (void)lineBlockArrayDidChange:(iTermLineBlockArray *)lineBlockArray;
@end

@interface iTermLineBlockArray : NSObject<NSCopying>

@property (nonatomic, readonly) NSArray<LineBlock *> *blocks;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) LineBlock *lastBlock;
@property (nonatomic, readonly) LineBlock *firstBlock;
@property (nonatomic) BOOL resizing;
@property (nonatomic, readonly) NSString *dumpForCrashlog;
@property (nonatomic, weak) id<iTermLineBlockArrayDelegate> delegate;

- (NSString *)dumpWidths:(NSSet<NSNumber *> * _Nullable)widths;

// NOTE: Update -copyWithZone: if you add properties.

- (LineBlock *)objectAtIndexedSubscript:(NSUInteger)index;
- (LineBlock *)addBlockOfSize:(int)size
                       number:(long long)number
  mayHaveDoubleWidthCharacter:(BOOL)mayHaveDoubleWidthCharacter;
- (void)addBlock:(LineBlock *)object;
- (void)removeFirstBlock;
- (void)removeFirstBlocks:(NSInteger)count;
- (void)removeLastBlock;
- (void)setAllBlocksMayHaveDoubleWidthCharacters;
- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr;
- (nullable LineBlock *)blockContainingLineNumber:(int)lineNumber
                                            width:(int)width
                                        remainder:(out int *)remainderPtr;
- (int)numberOfWrappedLinesForWidth:(int)width;
- (void)enumerateLinesInRange:(NSRange)range
                        width:(int)width
                        block:(void (^)(const screen_char_t *chars,
                                        int length,
                                        int eol,
                                        screen_char_t continuation,
                                        iTermImmutableMetadata metadata,
                                        BOOL *stop))block;
- (NSInteger)numberOfRawLines;
- (NSInteger)rawSpaceUsed;
- (NSInteger)rawSpaceUsedInRangeOfBlocks:(NSRange)range;

// Returns the first block (lowest index) whose raw-character range covers
// `position`, using closed-right semantics: a position equal to the end of
// block i is reported as "inside block i, at offset rawSpaceUsed", not as the
// start of block i+1.
//
// Multiple blocks can contain the same raw position. Any block whose
// rawSpaceUsed is 0 (i.e. contains only empty raw lines) shares its raw
// offset with the block before and after it, and the boundary value at the
// end of block i equals the start of block i+1. The visual y-coordinate of
// the position is what disambiguates which logical block the caller meant,
// and that information lives in the LineBufferPosition's yOffset field, not
// in `position` here. Callers that need the visually-correct block (rather
// than just any block whose raw range covers `position`) must consume
// yOffset themselves by walking forward through subsequent blocks.
//
// Pass -1 for width and NULL for blockOffset to avoid building a cache.
- (LineBlock * _Nullable)firstBlockContainingPosition:(long long)p
                                                width:(int)width
                                            remainder:(nullable int *)remainder
                                          blockOffset:(nullable int *)yoffset
                                                index:(nullable int *)indexPtr;
- (void)sanityCheck:(long long)droppedChars;
- (void)oopsWithWidth:(int)width droppedChars:(long long)droppedChars block:(void (^)(void))block;
- (NSSet<NSNumber *> *)cachedWidths;
- (NSInteger)numberOfWrappedLinesForWidth:(int)width
                          upToBlockAtIndex:(NSInteger)limit;
- (NSInteger)numberOfRawLinesInRange:(NSRange)range width:(int)width;

// Tests only. Exposes the two implementations of firstBlockContainingPosition:
// so tests can verify fast/slow agree (or, when they don't, demonstrate where).
- (LineBlock * _Nullable)testOnly_fast_firstBlockContainingPosition:(long long)position
                                                              width:(int)width
                                                          remainder:(nullable int *)remainder
                                                        blockOffset:(nullable int *)blockOffset
                                                              index:(nullable int *)indexPtr;
- (LineBlock * _Nullable)testOnly_slow_firstBlockContainingPosition:(long long)position
                                                              width:(int)width
                                                          remainder:(nullable int *)remainder
                                                        blockOffset:(nullable int *)blockOffset
                                                              index:(nullable int *)indexPtr;

@end

NS_ASSUME_NONNULL_END
