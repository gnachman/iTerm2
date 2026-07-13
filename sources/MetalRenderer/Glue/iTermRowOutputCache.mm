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
#import <string>
#import <string_view>

namespace {

// Owns byte copies of the three blobs in std::string members (arbitrary bytes,
// not text), so the struct is trivially movable/destructible: no ObjC objects in
// the container (no ARC-in-C++-container subtleties) and no hand-rolled
// rule-of-five to keep in sync.
struct Entry {
    iTermRowCacheKey key{};
    std::string glyphKeys;
    std::string attributes;
    std::string background;
    NSUInteger glyphKeyCount = 0;
    int rleCount = 0;
    int drawableGlyphs = 0;
    bool hasUnderlineOrStrikethrough = false;
};

struct KeyHash {
    using is_avalanching = void;
    size_t operator()(const iTermRowCacheKey &k) const noexcept {
        // Hash the key's raw bytes via the library's PUBLIC string_view hash
        // (avoiding the detail::wyhash internal path, which could move on a
        // library update). Safe because the key is hole-free and memset(0) before
        // population, so its byte image is deterministic.
        return (size_t)ankerl::unordered_dense::hash<std::string_view>{}(
            std::string_view(reinterpret_cast<const char *>(&k), sizeof(k)));
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
    memcpy(glyphKeys.mutableBytes, entry.glyphKeys.data(), entry.glyphKeys.size());
    memcpy(attributes, entry.attributes.data(), entry.attributes.size());
    memcpy(background, entry.background.data(), entry.background.size());
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
    entry.glyphKeys.assign(reinterpret_cast<const char *>(glyphKeys), glyphKeysLength);
    entry.attributes.assign(reinterpret_cast<const char *>(attributes), attributesLength);
    entry.background.assign(reinterpret_cast<const char *>(background), backgroundLength);
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
