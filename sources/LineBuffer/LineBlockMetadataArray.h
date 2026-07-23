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

@class LineBlockMetadataArray;
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
// _array is held unretained: providers are intended to be stack-local within
// a single method call on LineBlockMetadataArray's owner, which keeps the
// array alive for the provider's lifetime. Storing an unretained back-pointer
// instead of a copy-on-write trigger block avoids per-call Block_copy in tight
// inner loops like -[LineBlock locationOfRawLineForWidth:lineNum:].
//
// The entry is identified by (array, index), not by an interior pointer:
// willMutate can replace the backing storage with a copy-on-write split and
// increaseCapacityTo: can realloc it, so a pointer captured at creation time
// may not target the array's current storage by the time it is used. A
// pointer that goes stale this way writes into the storage retained by the
// OTHER sharer of the copy-on-write data, corrupting it across threads.
// The accessors below instead resolve the entry at call time.
//
// _generation captures the array's structural generation at creation time.
// The accessors assert it is unchanged, so a provider cannot silently alias
// a different logical entry after removeLast/append churn reuses its index.
typedef struct {
    __unsafe_unretained LineBlockMetadataArray *_array;
    int _index;
    int64_t _generation;
} iTermLineBlockMetadataProvider;


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
- (const iTermMetadata *)appendToLastLine:(const iTermImmutableMetadata *)metadataToAppend
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

// Provider plumbing. Do not call directly; use
// iTermLineBlockMetadataProviderGetImmutable/GetMutable, which resolve the
// entry through the array's *current* storage. Asserts that `generation`
// matches the current structural generation and that `index` names a live
// entry. objc_direct keeps the provider accessors as cheap as the raw
// pointer they replaced.
- (LineBlockMetadata *)providerEntryAtIndex:(int)index
                                 generation:(int64_t)generation __attribute__((objc_direct));

@end

// Defined after the @interface so -willMutate is visible at the call site.
NS_INLINE const LineBlockMetadata *iTermLineBlockMetadataProviderGetImmutable(iTermLineBlockMetadataProvider provider) {
    return [provider._array providerEntryAtIndex:provider._index
                                      generation:provider._generation];
}

NS_INLINE LineBlockMutableMetadata iTermLineBlockMetadataProvideGetMutable(iTermLineBlockMetadataProvider provider) {
    // willMutate may replace the backing storage with a private copy
    // (copy-on-write split), so the entry must be resolved after it returns.
    [provider._array willMutate];
    LineBlockMetadata *metadata = [provider._array providerEntryAtIndex:provider._index
                                                             generation:provider._generation];
    return (LineBlockMutableMetadata) {
        .metadata = metadata,
        .mutableBidiDisplayInfo = metadata->bidi_display_info,
    };
}

NS_ASSUME_NONNULL_END
