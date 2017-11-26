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
#define DLogLock(args...) DLog(@"LOCK: " args)

namespace iTerm2 {

class TextureMap {
private:
    // map     lru  entries
    // a -> 0  0    a
    // b -> 1  2    b
    // c -> 2  1    c

    // Maps a character description to its index in a texture sprite sheet.
    cache::lru_cache<GlyphKey, TextureEntry> _lru;

    // Maps a character description to its index in a texture sprite sheet. These glyph keys
    // cannot be recycled.
    std::unordered_map<GlyphKey, TextureEntry> _inuse;

    // Tracks which glyph key is at which index.
    std::vector<GlyphKey> _entries;

    // Maps an index to the lock count. Values > 0 are locked.
    std::vector<int> _locks;

    // Maps an index to a map from part to related index.
    std::unordered_map<int, std::map<int, int>> _relatedIndexes;

    // Maximum number of entries.
    const int _capacity;

    // Number of unlocked entries.
    int _freeCount;

private:
    void move_from_lru_to_inuse(const int &i) {
        const GlyphKey &key = _entries[i];
        const TextureEntry *textureEntry = _lru.peek(key);
        assert(textureEntry);
        _inuse[key] = *textureEntry;
        _lru.erase(key);
    }

    void move_from_inuse_to_lru(const int &i) {
        const GlyphKey &key = _entries[i];
        auto it = _inuse.find(key);
        assert(it != _inuse.end());
        _lru.put(it->first, it->second);
        _inuse.erase(it);
    }

    inline void lock(const int &i) {
        int &lock = _locks[i];
        if (lock == 0) {
            move_from_lru_to_inuse(i);
            _freeCount--;
            assert(_freeCount >= 0);
        }
        lock++;
    }

    inline void unlock_internal(const int &i) {
        int &lock = _locks[i];
        lock--;
        if (lock == 0) {
            move_from_inuse_to_lru(i);

            _freeCount++;
            assert(_freeCount <= _capacity);
        }
    }

    // Find the texture entry for the key in either inuse or lru
    inline const TextureEntry *lookup(const GlyphKey &key) const {
        auto it = _inuse.find(key);
        if (it != _inuse.end()) {
            const TextureEntry &value = it->second;
            assert(_locks[value.index] > 0);
            return &value;
        } else {
            const TextureEntry *value = _lru.peek(key);
            if (value) {
                assert(_locks[value->index] == 0);
            }
            return value;
        }
    }

public:
    explicit TextureMap(const int capacity) : _lru(capacity), _inuse(capacity), _entries(capacity), _locks(capacity), _capacity(capacity), _freeCount(capacity) { }

    inline int get_index(const GlyphKey &key, TextureMapStage *textureMapStage, std::map<int, int> *related, BOOL *emoji) {
        const TextureEntry *value = lookup(key);
        if (value == nullptr) {
            return -1;
        } else {
            const TextureEntry entry = *value;
            const int &index = entry.index;

            *emoji = entry.emoji;
            *related = _relatedIndexes[index];
            if (related->size() == 1) {
                lock(index);
                DLogLock(@"Get index %d sets lock to %d", index, _locks[index]);
            } else {
                for (auto kvp : *related) {
                    const int i = kvp.second;
                    lock(i);
                    DLogLock(@"Lock related index %d; lock is now %d", i, _locks[i]);
                }
            }
            return index;
        }
    }

    // returns (stage index, global index) on success or (-1, -1) on error. Adds it to the inuse
    // map.
    inline std::pair<int, int> allocate_index(const GlyphKey &key, TextureMapStage *stage, const BOOL emoji) {
        if (_freeCount == 0) {
            return std::make_pair(-1, -1);
        }
        const int index = produce();
        assert(index >= 0);
        assert(index <= _capacity);
        assert(_lru.peek(key) == nullptr);

        // Remove relationships related to index.
        remove_relations(index);

        // Add it to LRU.
        const TextureEntry entry = { .index = index, .emoji = emoji };
        _lru.put(key, entry);
        _entries[index] = key;

        // Lock it. This moves it from LRU to inuse.
        lock(index);
        assert(_inuse.find(key) != _inuse.end());

        DLogLock(@"Allocate index %d sets lock to %d", index, _locks[index]);

        const int stageIndex = stage->will_blit(index);
        return std::make_pair(stageIndex, index);
    }

    int get_free_count() const {
        return _freeCount;
    }

    void unlock_stage(TextureMapStage *stage) {
        stage->unlock_all();
    }

    inline void unlock(int index) {
        unlock_internal(index);
        DLogLock(@"Unlock index %d sets lock to %d", index, _locks[index]);
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
    // Returns -1 on out of memory. Otherwise the caller must add it to the inuse map immediately
    // to avoid a leak.
    inline int produce() {
        const int lru_size = _lru.size();
        const int size = lru_size + _inuse.size();
        if (size == _capacity) {
            if (lru_size == 0) {
                // There's no LRU entry to use. This should never happen.
                return -1;
            }

            // Recycle the value of the least-recently used GlyphKey. Find the least recently used key-value pair.
            std::pair<GlyphKey, TextureEntry> entry = _lru.get_lru();

            // Remove it from LRU under the assumption that it'll be added to inuse right away
            _lru.erase(entry.first);

            // Sanity check and return index
            const int &indexToRecycle = entry.second.index;
            assert(_locks[indexToRecycle] == 0);
            return indexToRecycle;
        } else {
            return size;
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
