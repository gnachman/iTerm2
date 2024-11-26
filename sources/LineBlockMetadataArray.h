//
//  LineBlockMetadataArray.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/19/24.
//

#import <Foundation/Foundation.h>
#import "iTermDoubleWidthCharacterCache.h"
#import "iTermMetadata.h"
#import "iTermPromise.h"

@class iTermBidiDisplayInfo;

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    iTermMetadata lineMetadata;
    screen_char_t continuation;
    int number_of_wrapped_lines;
    int width_for_number_of_wrapped_lines;

    iTermDoubleWidthCharacterCache *_Nullable doubleWidthCharacters;
    iTermBidiDisplayInfo *_Nullable bidi_display_info;
} LineBlockMetadata;

typedef struct {
    LineBlockMetadata *metadata;
    iTermBidiDisplayInfo *_Nullable mutableBidiDisplayInfo;
} LineBlockMutableMetadata;

// Don't access this directly. Use the functions below.
typedef struct {
    LineBlockMetadata *_metadata;
    void (^_Nullable _willMutate)(void);
} iTermLineBlockMetadataProvider;

NS_INLINE const LineBlockMetadata *iTermLineBlockMetadataProviderGetImmutable(iTermLineBlockMetadataProvider provider) {
    return provider._metadata;
}

NS_INLINE LineBlockMutableMetadata iTermLineBlockMetadataProvideGetMutable(iTermLineBlockMetadataProvider provider) {
    if (provider._willMutate) {
        provider._willMutate();
        provider._willMutate = nil;
    }
    return (LineBlockMutableMetadata) {
        .metadata = provider._metadata,
        .mutableBidiDisplayInfo = provider._metadata->bidi_display_info,
    };
}


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

- (id<iTermExternalAttributeIndexReading> _Nullable)lastExternalAttributeIndex;

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
- (const iTermMetadata *)appendToLastLine:(iTermImmutableMetadata *)metadataToAppend
                           originalLength:(int)originalLength
                         additionalLength:(int)additionalLength
                             continuation:(screen_char_t)continuation;

- (void)setBidiInfo:(iTermBidiDisplayInfo * _Nullable)bidiInfo
             atLine:(int)line
           rtlFound:(BOOL)rtlFound;

// Returns a provider for the `i`th entry. From the provider, you can get a mutable object.
// i >= first && i < numEntries
- (iTermLineBlockMetadataProvider)metadataProviderAtIndex:(int)i;

// Replace the external attributes in the last entry.
// numEntries > first
- (void)setLastExternalAttributeIndex:(iTermExternalAttributeIndex *)eaIndex;

- (void)setRTLFound:(BOOL)rtlFound atIndex:(NSInteger)index;

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
