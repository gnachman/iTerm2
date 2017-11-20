//
//  TextureMap.h
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

extern "C" {
#import "DebugLogging.h"
}
#import "GlyphKey.h"
#import "TextureMapStage.h"
#import "lrucache.hpp"

#include <map>
#include <unordered_map>
#include <vector>

// Define as NSLog or DLog to debug locking issues
#define DLogLock(args...)

namespace iTerm2 {

class TextureMap {
private:
    // map     lru  entries
    // a -> 0  0    a
    // b -> 1  2    b
    // c -> 2  1    c

    // Maps a character description to its index in a texture sprite sheet.
    cache::lru_cache<GlyphKey, TextureEntry> _lru;

    // Tracks which glyph key is at which index.
    std::vector<GlyphKey *> _entries;

    // Maps an index to the lock count. Values > 0 are locked.
    std::vector<int> _locks;

    // Maps an index to a map from part to related index.
    std::unordered_map<int, std::map<int, int>> _relatedIndexes;

    // Maximum number of entries.
    const int _capacity;
public:
    explicit TextureMap(const int capacity) : _lru(capacity), _locks(capacity), _capacity(capacity) { }

    inline int get_index(const GlyphKey &key, TextureMapStage *textureMapStage, std::map<int, int> *related, BOOL *emoji) {
        const TextureEntry *value = textureMapStage->lookup(key, &_lru);
        if (value == nullptr) {
            return -1;
        } else {
            const TextureEntry &entry = *value;
            const int &index = entry.index;

            *emoji = entry.emoji;
            *related = _relatedIndexes[index];
            if (related->size() == 1) {
                _locks[index]++;
                DLogLock(@"Get %d sets lock to %d", index, _locks[index]);
            } else {
                for (auto kvp : *related) {
                    const int i = kvp.second;
                    _locks[i]++;
                    DLogLock(@"Lock related %d; lock is now %d", i, _locks[i]);
                }
            }
            return index;
        }
    }

    inline std::pair<int, int> allocate_index(const GlyphKey &key, TextureMapStage *stage, const BOOL emoji) {
        const int index = produce();
        assert(_locks[index] == 0);
        remove_relations(index);
        _locks[index]++;
        DLogLock(@"Allocate %d sets lock to %d", index, _locks[index]);
        assert(index <= _capacity);
        const TextureEntry entry = { .index = index, .emoji = emoji };
        _lru.put(key, entry);

        const int stageIndex = stage->will_blit(index);
        return std::make_pair(stageIndex, index);
    }

    void unlock_stage(TextureMapStage *stage) {
        stage->unlock_all();
    }

    inline void unlock(int index) {
        _locks[index]--;
        DLogLock(@"Unlock %d sets lock to %d", index, _locks[index]);
        assert(_locks[index] >= 0);
    }

    void define_class(const std::map<int, int> &relation) {
        for (auto kvp : relation) {
            const int i = kvp.second;
            _relatedIndexes[i] = relation;
        }
    }

private:
    // Return the next index to use. Either a never-before used one or the least-recently used one.
    inline int produce() {
        if (_lru.size() == _capacity) {
            // Recycle the value of the least-recently used GlyphKey.
            return _lru.get_lru().second.index;
        } else {
            return _lru.size();
        }
    }

    inline void remove_relations(const int index) {
        // Remove all relations of the index that will be recycled.
        auto it = _relatedIndexes.find(index);
        if (it != _relatedIndexes.end()) {
            auto temp = it->second;
            for (auto kvp : temp) {
                const int i = kvp.second;
                assert(_locks[i] == 0);
                _relatedIndexes.erase(i);
            }
        }
    }
};

}
