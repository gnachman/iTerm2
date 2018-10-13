//
//  iTermLineBlockArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 13.10.18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LineBlock;

@interface iTermLineBlockArray : NSObject<NSCopying>

@property (nonatomic, readonly) NSArray<LineBlock *> *blocks;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) LineBlock *lastBlock;

- (LineBlock *)objectAtIndexedSubscript:(NSUInteger)index;
- (void)addBlock:(LineBlock *)object;
- (void)removeFirstBlock;
- (void)removeFirstBlocks:(NSInteger)count;
- (void)removeLastBlock;

- (void)setAllBlocksMayHaveDoubleWidthCharacters;
- (nullable LineBlock *)blockContainingLineNumber:(int)lineNumber
                                            width:(int)width
                                        remainder:(out int *)remainderPtr;
- (int)numberOfWrappedLinesForWidth:(int)width;

@end

NS_ASSUME_NONNULL_END
