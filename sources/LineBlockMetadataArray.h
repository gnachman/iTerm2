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

// Stores an array of `LineBlockMetadata`. Offers copy-on-write. This is maybe
// more like a dequeue because it also tracks number of items at the head of
// the list that are invalid.
@interface LineBlockMetadataArray: NSObject

// Keep a cache of double-width characters? This used to be experimental but
// it's been on by default for a long time.
@property (nonatomic, readonly) BOOL useDWCCache;

// Number of entries that could be stored.
@property (nonatomic, readonly) int capacity;

// Number of entries present, including those dropped from the beginning of the list.
@property (nonatomic, readonly) int numEntries;

// Number of values at the start that are invalid.
@property (nonatomic, readonly) int first;

#pragma mark - Initialization

- (instancetype)initWithCapacity:(int)capacity useDWCCache:(BOOL)useDWCCache;
- (instancetype)init NS_UNAVAILABLE;

// This is used immediately after initialization when restoring state.
//
// i: Index of the entry
// components: Encoded array of values
// migrationIndex: For migrating old encoded settings. Stores the external attributes for the whole block together. Pass nil if not migrating.
// startOffset: Index into migrationIndex for this entry
// length: Length of this entry in migrationIndex.
- (void)setEntry:(int)i
  fromComponents:(NSArray *)components
migrationIndex:(iTermExternalAttributeIndex * _Nullable)migrationIndex
     startOffset:(int)startOffset
          length:(int)length;

// Sets `first`, the index of the first valid item.
- (void)setFirstIndex:(int)i;

#pragma mark - Copying

// Makes a copy. This is nearly free until a mutation is made, at which time
// the actual contents are copied.
- (LineBlockMetadataArray *)cowCopy;

#pragma mark - Reading

// precondition: i >= first && i < numEntries
- (const LineBlockMetadata *)metadataAtIndex:(int)i;
- (iTermImmutableMetadata)immutableLineMetadataAtIndex:(int)i;

// precondition: numEntries > 0
- (screen_char_t)lastContinuation;

- (iTermExternalAttributeIndex * _Nullable)lastExternalAttributeIndex;

// Used to save state for later restoration with setEntry:fromComponents:externalAttributeIndex:
- (NSArray *)encodedArray;

#pragma mark - Mutation

// Force a deep copy.
// You must manually call this before performing any mutation method. It
// ensures copy-on-write is performed.
// This assumes that willMutate is only ever called on a single thread
// for a particular instance of LineBlockMetadataArray. It can be called
// concurrently for different instances that share underlying data.
- (void)willMutate;

// Grows the space allocated for the array. You must manually call this before appending.
- (void)increaseCapacityTo:(int)newCapacity;

// numEntries <- 0, first <- 0. Releases memory as needed.
- (void)reset;

// Append to the end of the array.
- (void)append:(iTermImmutableMetadata)lineMetadata
  continuation:(screen_char_t)continuation;

// Appends to the last entry already in the array.
// numEntries > first
- (void)appendToLastLine:(iTermImmutableMetadata *)metadataToAppend
          originalLength:(int)originalLength
        additionalLength:(int)additionalLength
            continuation:(screen_char_t)continuation;

// Returns a mutable pointer to the `i`th entry.
// i >= first && i < numEntries
- (LineBlockMetadata *)mutableMetadataAtIndex:(int)i;

// Replace the external attributes in the last entry.
// numEntries > first
- (void)setLastExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex;

// Remove the first entry (by incrementing the `first` pointer and freeing
// associated memory).
- (void)removeFirst;

// Remove the first `n` entries. See -removeFirst for details.
- (void)removeFirst:(int)n;

// Remove the last entry (by decrementing `numEntries` and freeing associated
// memory).
- (void)removeLast;

// Remove cache values in the first entry.
- (void)eraseLastLineCache;

// Remove cache values in the last entry.
- (void)eraseFirstLineCache;

@end

NS_ASSUME_NONNULL_END
