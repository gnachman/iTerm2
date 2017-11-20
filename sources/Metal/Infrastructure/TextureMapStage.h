//
//  TextureMapStage.h
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

#include <unordered_set>
#include <vector>

namespace iTerm2 {
struct TextureEntry {
    int index;
    BOOL emoji;
};

class TextureMapStage {
private:
    // Maps stage indexes that need blitting to their destination indices.
    std::unordered_map<int, int> _indexesToBlit;

    // Glyph keys accessed this frame. Stored so we don't waste time promoting more than once
    // in the LRU cache.
    std::unordered_set<iTerm2::GlyphKey> _usedThisFrame;

    // Held locks
    std::vector<int> _lockedIndexes;

    int _nextStageIndex;
public:
    int will_blit(const int index) {
        const int stageIndex = _nextStageIndex++;
        _indexesToBlit[stageIndex] = index;
        return stageIndex;
    }

    const bool have_indexes_to_blit() const {
        return !_indexesToBlit.empty();
    }

    void blit(iTermTextureArray *source, iTermTextureArray *destination, id <MTLBlitCommandEncoder> blitter) {
        for (auto it = _indexesToBlit.begin(); it != _indexesToBlit.end(); it++) {
            [source copyTextureAtIndex:it->first
                               toArray:destination
                                 index:it->second
                               blitter:blitter];
        }
        _indexesToBlit.clear();
        _nextStageIndex = 0;
    }

    void unlock_all() {
        _lockedIndexes.clear();
    }

    // Looks up the key in the LRU, promoting it only if it hasn't been used before this frame.
    const TextureEntry *lookup(const GlyphKey &key, cache::lru_cache<GlyphKey, TextureEntry> *lru) {
        const TextureEntry *valuePtr;
        if (_usedThisFrame.find(key) != _usedThisFrame.end()) {
            // key was already used this frame. Don't promote it in the LRU.
            valuePtr = lru->peek(key);
        } else {
            // first use of key this frame. Promote it and record its use.
            const TextureEntry *value = lru->get(key);
            _usedThisFrame.insert(key);
            valuePtr = value;
        }
        if (valuePtr) {
            _lockedIndexes.push_back(valuePtr->index);
        }
        return valuePtr;
    }
};
}
