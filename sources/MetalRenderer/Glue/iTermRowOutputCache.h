//
//  iTermRowOutputCache.h
//  iTerm2
//
//  An LRU cache of the expensive per-row build output (the glyph-keys,
//  per-cell-attributes, and background-color-RLE blobs produced by
//  -[iTermMetalPerFrameState metalGetGlyphKeysData:...]), keyed on a row's
//  config generation and content identity. On a hit the caller memcpy's the
//  cached blobs into its row buffers and skips the attributed-string build.
//
//  One instance per text view, owned by iTermMetalGlue. Accessed only from the
//  metal driver's serial queue during a frame build, so it needs no locking.
//
//  This hand-rolls its LRU (a std::list spliced via an unordered_dense map
//  iterator) rather than reusing iTermLRUDictionary on purpose: the key is a
//  hole-free POD compared/hashed byte-wise and the values are raw byte blobs, so
//  the custom container avoids NSNumber key boxing and NSData value boxing on the
//  per-row hot path. That is the tradeoff for maintaining a second LRU.
//

#import <Foundation/Foundation.h>
#import "iTermRowContentIdentity.h"

@class iTermGlyphKeyData;

NS_ASSUME_NONNULL_BEGIN

// POD cache key. Both members are exactly comparable (no lossy hashes), and the
// struct is hole-free so it can be compared/hashed byte-wise. The owner must
// memset(0) it before populating so padding is defined.
typedef struct {
    uint64_t configGeneration;
    iTermRowContentIdentity contentIdentity;
} iTermRowCacheKey;

@interface iTermRowOutputCache : NSObject

// maxEntries bounds memory; least-recently-used entries are evicted.
- (instancetype)initWithCapacity:(NSUInteger)maxEntries NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// On a hit, copies the cached blobs into the caller's buffers, fills the
// scalars, and returns YES. The glyph-keys buffer is grown if the cached blob
// has more glyph keys than it currently holds (decomposition can exceed the
// column count); the attributes and background buffers are column-bounded and
// must already be large enough. On a miss returns NO and touches nothing.
- (BOOL)lookup:(const iTermRowCacheKey *)key
     glyphKeys:(iTermGlyphKeyData *)glyphKeys
    attributes:(void *)attributes
    background:(void *)background
 glyphKeyCount:(out NSUInteger *)glyphKeyCount
      rleCount:(out int *)rleCount
drawableGlyphs:(out int *)drawableGlyphs
hasUnderlineOrStrikethrough:(out BOOL *)hasUnderlineOrStrikethrough;

// Copies the given blobs into a new entry.
- (void)store:(const iTermRowCacheKey *)key
    glyphKeys:(const void *)glyphKeys
glyphKeysLength:(size_t)glyphKeysLength
   attributes:(const void *)attributes
attributesLength:(size_t)attributesLength
   background:(const void *)background
backgroundLength:(size_t)backgroundLength
glyphKeyCount:(NSUInteger)glyphKeyCount
     rleCount:(int)rleCount
drawableGlyphs:(int)drawableGlyphs
hasUnderlineOrStrikethrough:(BOOL)hasUnderlineOrStrikethrough;

- (void)removeAllObjects;

@property (nonatomic, readonly) NSUInteger count;

@end

NS_ASSUME_NONNULL_END
