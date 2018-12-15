//
//  iTermLineBlockArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import <Foundation/Foundation.h>
#import "ScreenChar.h"

NS_ASSUME_NONNULL_BEGIN

@class LineBlock;

@interface iTermLineBlockArray : NSObject<NSCopying>

@property (nonatomic, readonly) NSArray<LineBlock *> *blocks;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) LineBlock *lastBlock;
@property (nonatomic) BOOL resizing;

// NOTE: Update -copyWithZone: if you add properties.

- (LineBlock *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)addBlock:(LineBlock *)object;
- (void)removeFirstBlock;
- (void)removeFirstBlocks:(NSInteger)count;
- (void)removeLastBlock;
- (void)replaceLastBlockWithCopy;
- (void)setAllBlocksMayHaveDoubleWidthCharacters;
- (NSInteger)indexOfBlockContainingLineNumber:(int)lineNumber width:(int)width remainder:(out nonnull int *)remainderPtr;
- (nullable LineBlock *)blockContainingLineNumber:(int)lineNumber
                                            width:(int)width
                                        remainder:(out int *)remainderPtr;
- (int)numberOfWrappedLinesForWidth:(int)width;
- (void)enumerateLinesInRange:(NSRange)range
                        width:(int)width
                        block:(void (^)(screen_char_t *chars, int length, int eol, screen_char_t continuation, BOOL *stop))block;
- (NSInteger)numberOfRawLines;
- (NSInteger)rawSpaceUsed;
- (NSInteger)rawSpaceUsedInRangeOfBlocks:(NSRange)range;

// If you don't need a yoffset pass -1 for width and NULL for blockOffset to avoid building a cache.
- (LineBlock *)blockContainingPosition:(long long)p
                                 width:(int)width
                             remainder:(nullable int *)remainder
                           blockOffset:(nullable int *)yoffset
                                 index:(nullable int *)indexPtr;
- (void)sanityCheck;
- (void)oopsWithWidth:(int)width block:(void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
