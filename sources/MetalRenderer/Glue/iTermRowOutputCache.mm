//
//  iTermRowOutputCache.mm
//  iTerm2
//

#import "iTermRowOutputCache.h"
#import "iTermData.h"
#import "iTermMetalGlyphKey.h"
#import "unordered_dense/unordered_dense.h"

#import <list>
#import <string.h>

namespace {

// Owns malloc'd copies of the three blobs (no ObjC objects in the container, so
// no ARC-in-C++-container subtleties). Move-only.
struct Entry {
    iTermRowCacheKey key;
    void *glyphKeys = nullptr;
    size_t glyphKeysLength = 0;
    void *attributes = nullptr;
    size_t attributesLength = 0;
    void *background = nullptr;
    size_t backgroundLength = 0;
    NSUInteger glyphKeyCount = 0;
    int rleCount = 0;
    int drawableGlyphs = 0;
    bool hasUnderlineOrStrikethrough = false;

    Entry() = default;
    ~Entry() {
        free(glyphKeys);
        free(attributes);
        free(background);
    }
    Entry(Entry &&other) noexcept { moveFrom(other); }
    Entry &operator=(Entry &&other) noexcept {
        if (this != &other) {
            free(glyphKeys);
            free(attributes);
            free(background);
            moveFrom(other);
        }
        return *this;
    }
    Entry(const Entry &) = delete;
    Entry &operator=(const Entry &) = delete;

private:
    void moveFrom(Entry &other) {
        key = other.key;
        glyphKeys = other.glyphKeys;             glyphKeysLength = other.glyphKeysLength;
        attributes = other.attributes;           attributesLength = other.attributesLength;
        background = other.background;            backgroundLength = other.backgroundLength;
        glyphKeyCount = other.glyphKeyCount;
        rleCount = other.rleCount;
        drawableGlyphs = other.drawableGlyphs;
        hasUnderlineOrStrikethrough = other.hasUnderlineOrStrikethrough;
        other.glyphKeys = other.attributes = other.background = nullptr;
    }
};

struct KeyHash {
    using is_avalanching = void;
    size_t operator()(const iTermRowCacheKey &k) const noexcept {
        return (size_t)ankerl::unordered_dense::detail::wyhash::hash(&k, sizeof(k));
    }
};

struct KeyEqual {
    bool operator()(const iTermRowCacheKey &a, const iTermRowCacheKey &b) const noexcept {
        return memcmp(&a, &b, sizeof(a)) == 0;
    }
};

}  // namespace

@implementation iTermRowOutputCache {
    NSUInteger _capacity;
    // Most-recently-used at the front.
    std::list<Entry> _lru;
    ankerl::unordered_dense::map<iTermRowCacheKey, std::list<Entry>::iterator, KeyHash, KeyEqual> _map;
}

- (instancetype)initWithCapacity:(NSUInteger)maxEntries {
    self = [super init];
    if (self) {
        _capacity = MAX(1, maxEntries);
    }
    return self;
}

- (NSUInteger)count {
    return _map.size();
}

- (BOOL)lookup:(const iTermRowCacheKey *)key
     glyphKeys:(iTermGlyphKeyData *)glyphKeys
    attributes:(void *)attributes
    background:(void *)background
 glyphKeyCount:(out NSUInteger *)glyphKeyCount
      rleCount:(out int *)rleCount
drawableGlyphs:(out int *)drawableGlyphs
hasUnderlineOrStrikethrough:(out BOOL *)hasUnderlineOrStrikethrough {
    auto it = _map.find(*key);
    if (it == _map.end()) {
        return NO;
    }
    std::list<Entry>::iterator entryIt = it->second;
    // Promote to most-recently-used.
    _lru.splice(_lru.begin(), _lru, entryIt);

    const Entry &entry = *entryIt;
    // Grow the glyph-keys buffer if the cached blob has more entries than it
    // currently holds (decomposition can exceed the column count).
    if (glyphKeys.count < entry.glyphKeyCount) {
        glyphKeys.count = entry.glyphKeyCount;
    }
    memcpy(glyphKeys.mutableBytes, entry.glyphKeys, entry.glyphKeysLength);
    memcpy(attributes, entry.attributes, entry.attributesLength);
    memcpy(background, entry.background, entry.backgroundLength);
    *glyphKeyCount = entry.glyphKeyCount;
    *rleCount = entry.rleCount;
    *drawableGlyphs = entry.drawableGlyphs;
    *hasUnderlineOrStrikethrough = entry.hasUnderlineOrStrikethrough ? YES : NO;
    return YES;
}

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
hasUnderlineOrStrikethrough:(BOOL)hasUnderlineOrStrikethrough {
    // If already present, drop the old entry so we replace it.
    auto existing = _map.find(*key);
    if (existing != _map.end()) {
        _lru.erase(existing->second);
        _map.erase(existing);
    }

    Entry entry;
    entry.key = *key;
    entry.glyphKeys = malloc(glyphKeysLength);
    memcpy(entry.glyphKeys, glyphKeys, glyphKeysLength);
    entry.glyphKeysLength = glyphKeysLength;
    entry.attributes = malloc(attributesLength);
    memcpy(entry.attributes, attributes, attributesLength);
    entry.attributesLength = attributesLength;
    entry.background = malloc(backgroundLength);
    memcpy(entry.background, background, backgroundLength);
    entry.backgroundLength = backgroundLength;
    entry.glyphKeyCount = glyphKeyCount;
    entry.rleCount = rleCount;
    entry.drawableGlyphs = drawableGlyphs;
    entry.hasUnderlineOrStrikethrough = hasUnderlineOrStrikethrough ? true : false;

    _lru.push_front(std::move(entry));
    _map[*key] = _lru.begin();

    while (_map.size() > _capacity) {
        auto &lruEntry = _lru.back();
        _map.erase(lruEntry.key);
        _lru.pop_back();
    }
}

- (void)removeAllObjects {
    _map.clear();
    _lru.clear();
}

@end
