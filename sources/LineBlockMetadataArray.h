//
//  LineBlockMetadataArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/19/24.
//

#import <Foundation/Foundation.h>
#import "iTermMetadata.h"

typedef struct {
    iTermMetadata lineMetadata;
    screen_char_t continuation;
    int number_of_wrapped_lines;
    int width_for_number_of_wrapped_lines;

    // Remembers the offsets at which double-width characters that are wrapped
    // to the next line occur for a pane of width
    // width_for_double_width_characters_cache.
    NSMutableIndexSet *_Nullable double_width_characters;
    int width_for_double_width_characters_cache;
} LineBlockMetadata;

NS_ASSUME_NONNULL_BEGIN

@interface LineBlockMetadataArray : NSObject

@property (nonatomic, readonly) BOOL useDWCCache;
@property (nonatomic, readonly) int capacity;
@property (nonatomic, readonly) int numEntries;
@property (nonatomic, readonly) int first;  // Number of initial values that have been erased.

#pragma mark - Initialization

- (instancetype)initWithCapacity:(int)capacity useDWCCache:(BOOL)useDWCCache NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setEntry:(int)i fromComponents:(NSArray *)components externalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex;
- (void)setFirstIndex:(int)i;

#pragma mark - Copying

- (LineBlockMetadataArray *)cowCopy;

#pragma mark - Reading

- (const LineBlockMetadata *)metadataAtIndex:(int)i;
- (iTermImmutableMetadata)immutableLineMetadataAtIndex:(int)i;
- (screen_char_t)lastContinuation;
- (iTermExternalAttributeIndex *)lastExternalAttributeIndex;
- (NSArray *)encodedArray;

#pragma mark - Mutation

- (void)increaseCapacityTo:(int)newCapacity;
// You must have erased all entries before calling reset.
- (void)reset;

- (void)append:(iTermImmutableMetadata)lineMetadata continuation:(screen_char_t)continuation;
- (void)appendToLastLine:(iTermImmutableMetadata *)metadataToAppend
          originalLength:(int)originalLength
        additionalLength:(int)additionalLength
            continuation:(screen_char_t)continuation;

- (LineBlockMetadata *)mutableMetadataAtIndex:(int)i;
- (void)setLastExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex;

- (void)removeFirst;
- (void)removeFirst:(int)n;
- (void)removeLast;

- (void)eraseLastLineCache;
- (void)eraseFirstLineCache;

@end

NS_ASSUME_NONNULL_END
