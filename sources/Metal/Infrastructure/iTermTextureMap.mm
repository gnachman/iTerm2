#import "iTermTextureMap.h"

#import "iTermTextureArray.h"
#import "iTermMetalGlyphKey.h"

#define DLog(format, ...)

#include <list>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

static const NSInteger iTermTextureMapNumberOfStages = 2;

/*
 Copyright (c) 2014, lamerman
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 * Neither the name of lamerman nor the names of its
 contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
#warning TODO: Add this to the documentation
// https://github.com/lamerman/cpp-lru-cache
namespace cache {
    template<typename key_t, typename value_t>
    class lru_cache {
    public:
        typedef typename std::pair<key_t, value_t> key_value_pair_t;
        typedef typename std::list<key_value_pair_t>::iterator list_iterator_t;

        lru_cache(size_t max_size) :
        _max_size(max_size) {
        }

        inline void put(const key_t& key, const value_t& value) {
            auto it = _cache_items_map.find(key);
            _cache_items_list.push_front(key_value_pair_t(key, value));
            if (it != _cache_items_map.end()) {
                _cache_items_list.erase(it->second);
                _cache_items_map.erase(it);
            }
            _cache_items_map[key] = _cache_items_list.begin();

            if (_cache_items_map.size() > _max_size) {
                auto last = _cache_items_list.end();
                last--;
                _cache_items_map.erase(last->first);
                _cache_items_list.pop_back();
            }
        }

        inline const value_t *get(const key_t& key) {
            auto it = _cache_items_map.find(key);
            if (it == _cache_items_map.end()) {
                return nullptr;
            } else {
                _cache_items_list.splice(_cache_items_list.begin(), _cache_items_list, it->second);
                return &it->second->second;
            }
        }

        inline const value_t *peek(const key_t& key) {
            auto it = _cache_items_map.find(key);
            if (it == _cache_items_map.end()) {
                return nullptr;
            } else {
                return &it->second->second;
            }
        }

        inline void erase(const key_t &key) {
            auto it = _cache_items_map.find(key);
            if (it != _cache_items_map.end()) {
                _cache_items_list.erase(it->second);
                _cache_items_map.erase(it);
            }
        }

        inline bool exists(const key_t& key) const {
            return _cache_items_map.find(key) != _cache_items_map.end();
        }

        inline size_t size() const {
            return _cache_items_map.size();
        }

    private:
        std::list<key_value_pair_t> _cache_items_list;
        std::unordered_map<key_t, list_iterator_t> _cache_items_map;
        size_t _max_size;
    };

} // namespace cache

namespace iTerm2 {
    template <class T>
    inline void hash_combine(std::size_t& seed, const T& v) {
        std::hash<T> hasher;
        seed ^= hasher(v) + 0x9e3779b9 + (seed<<6) + (seed>>2);
    }

    class GlyphKey {
    private:
        iTermMetalGlyphKey _repr;

        GlyphKey();

    public:
        explicit GlyphKey(const iTermMetalGlyphKey *repr) : _repr(*repr) { }

        // Copy constructor
        GlyphKey(const GlyphKey &other) {
            _repr = other._repr;
        }

        inline bool operator==(const GlyphKey &other) const {
            return (_repr.code == other._repr.code &&
                    _repr.isComplex == other._repr.isComplex &&
                    _repr.image == other._repr.image &&
                    _repr.boxDrawing == other._repr.boxDrawing &&
                    _repr.thinStrokes == other._repr.thinStrokes);
        }

        inline std::size_t get_hash() const {
            std::size_t seed = 0;
            hash_combine(seed, _repr.code);
            hash_combine(seed, _repr.isComplex);
            hash_combine(seed, _repr.image);
            hash_combine(seed, _repr.boxDrawing);
            hash_combine(seed, _repr.thinStrokes);
            hash_combine(seed, _repr.thinStrokes);
            return seed;
        }
    };
}

namespace std {
    template <>
    struct hash<iTerm2::GlyphKey> {
        std::size_t operator()(const iTerm2::GlyphKey& glyphKey) const {
            return glyphKey.get_hash();
        }
    };
}

namespace iTerm2 {
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

        void unlock_all(std::vector<int> *locks) {
            for (auto it = _lockedIndexes.begin(); it != _lockedIndexes.end(); it++) {
                (*locks)[*it]--;
            }
            _lockedIndexes.clear();
        }

        // Looks up the key in the LRU, promoting it only if it hasn't been used before this frame.
        const int *lookup(const GlyphKey &key, cache::lru_cache<GlyphKey, int> *lru) {
            const int *valuePtr;
            if (_usedThisFrame.find(key) != _usedThisFrame.end()) {
                // key was already used this frame. Don't promote it in the LRU.
                valuePtr = lru->peek(key);
            } else {
                // first use of key this frame. Promote it and record its use.
                const int *value = lru->get(key);
                _usedThisFrame.insert(key);
                valuePtr = value;
            }
            if (valuePtr) {
                _lockedIndexes.push_back(*valuePtr);
            }
            return valuePtr;
        }
    };

    class TextureMap {
    private:
        // map     lru  entries
        // a -> 0  0    a
        // b -> 1  2    b
        // c -> 2  1    c

        // Maps a character description to its index in a texture sprite sheet.
        cache::lru_cache<GlyphKey, int> _lru;

        // Tracks which glyph key is at which index.
        std::vector<GlyphKey *> _entries;

        // Maps an index to the lock count. Values > 0 are locked.
        std::vector<int> _locks;

        // Maximum number of entries.
        const int _capacity;
    public:
        explicit TextureMap(const int capacity) : _lru(capacity), _locks(capacity), _capacity(capacity) { }

        inline int get_index(const GlyphKey &key, TextureMapStage *textureMapStage) {
            const int *value;
            value = textureMapStage->lookup(key, &_lru);
            if (value == nullptr) {
                return -1;
            } else {
                const int index = *value;
                _locks[index]++;
                return index;
            }
        }

        inline std::pair<int, int> allocate_index(const GlyphKey &key, TextureMapStage *stage) {
            const int index = _lru.size() + 1;
            _locks[index]++;
            assert(index <= _capacity);
            _lru.put(key, index);
            const int stageIndex = stage->will_blit(index);
            return std::make_pair(stageIndex, index);
        }

        void unlock_stage(TextureMapStage *stage) {
            stage->unlock_all(&_locks);
        }
    };
}

@interface iTermTextureMapStage()
- (instancetype)initWithTextureMap:(iTermTextureMap *)textureMap
                        stageArray:(iTermTextureArray *)stageArray NS_DESIGNATED_INITIALIZER;
- (void)startNewFrame;
- (iTerm2::TextureMapStage *)textureMapStage;
@end

@implementation iTermTextureMap {
    iTerm2::TextureMap *_textureMap;
    NSMutableArray<iTermTextureMapStage *> *_stages;
    NSMutableArray<void (^)(iTermTextureMapStage *)> *_completionBlocks;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                      cellSize:(CGSize)cellSize
                      capacity:(NSInteger)capacity {
    self = [super init];
    if (self) {
        _capacity = capacity;
        _cellSize = cellSize;
        _completionBlocks = [NSMutableArray array];
        _array = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.width
                                                   textureHeight:cellSize.height
                                                     arrayLength:_capacity
                                                          device:device];
        _textureMap = new iTerm2::TextureMap(capacity);
        _stages = [NSMutableArray array];
        for (NSInteger i = 0; i < iTermTextureMapNumberOfStages; i++) {
            [_stages addObject:[[iTermTextureMapStage alloc] initWithTextureMap:self
                                                                     stageArray:[self newTextureArrayForStageWithDevice:device]]];
        }
    }
    return self;
}

- (void)dealloc {
    delete _textureMap;
}

- (BOOL)haveStageAvailable {
    @synchronized(self) {
        return _stages.count > 0;
    }
}

- (void)requestStage:(void (^)(iTermTextureMapStage *stage))completion {
    iTermTextureMapStage *stage = nil;
    @synchronized(self) {
        stage = [self nextStage];
    }
    if (stage) {
        completion(stage);
    } else {
        [_completionBlocks addObject:[completion copy]];
    }
}

- (iTermTextureMapStage *)nextStage {
    iTermTextureMapStage *stage = _stages.lastObject;
    [_stages removeLastObject];
    [stage startNewFrame];
    return stage;
}

- (void)unlockIndexesFromStage:(iTerm2::TextureMapStage *)textureMapStage {
    _textureMap->unlock_stage(textureMapStage);
}

- (void)returnStage:(iTermTextureMapStage *)stage {
    [self unlockIndexesFromStage:stage.textureMapStage];

    [_stages insertObject:stage atIndex:0];
    if (_completionBlocks.count) {
        void (^block)(iTermTextureMapStage *) = _completionBlocks.firstObject;
        [_completionBlocks removeObjectAtIndex:0];
        block([self nextStage]);
    }
}

- (iTermTextureArray *)newTextureArrayForStageWithDevice:(id<MTLDevice>)device {
    return [[iTermTextureArray alloc] initWithTextureWidth:_cellSize.width
                                             textureHeight:_cellSize.height
                                               arrayLength:_capacity / 2
                                                    device:device];
}

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                       textureMapStage:(iTerm2::TextureMapStage *)textureMapStage
                                            stageArray:(iTermTextureArray *)stageArray
                                              creation:(NSImage *(^)(int))creation {
    const iTerm2::GlyphKey glyphKey(key);

    int index = _textureMap->get_index(glyphKey, textureMapStage);
    if (index >= 0) {
        DLog(@"%@: locked existing texture %@", self.label, @(index));
        return index;
    } else {
        NSImage *image = creation(column);
        if (image != nil) {
            auto stageAndGlobalIndex = _textureMap->allocate_index(glyphKey, textureMapStage);
            DLog(@"%@: create and stage new texture %@", self.label, @(index));
            DLog(@"Stage %@ at %@", key, @(index));
            [stageArray setSlice:stageAndGlobalIndex.first withImage:image];
            return stageAndGlobalIndex.second;
        } else {
            return -1;
        }
    }
}

- (void)doNoOpBlitWithStage:(iTermTextureArray *)stageArray
               commandQueue:(id<MTLCommandQueue>)commandQueue {
    id <MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"Blit from stage";
    id <MTLBlitCommandEncoder> blitter = [commandBuffer blitCommandEncoder];
    [stageArray copyTextureAtIndex:0
                           toArray:_array
                             index:0
                           blitter:blitter];
    [blitter endEncoding];
    [commandBuffer commit];
}

- (void)blitFromStage:(iTerm2::TextureMapStage *)textureMapStage
                array:(iTermTextureArray *)stageArray
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    id<MTLBlitCommandEncoder> blitter = [commandBuffer blitCommandEncoder];
    textureMapStage->blit(stageArray, _array, blitter);
    [blitter endEncoding];
}

@end

@implementation iTermTextureMapStage {
    __weak iTermTextureMap *_textureMap;
    iTerm2::TextureMapStage *_textureMapStage;
}

- (instancetype)initWithTextureMap:(iTermTextureMap *)textureMap stageArray:(iTermTextureArray *)stageArray {
    self = [super init];
    if (self) {
        stageArray.texture.label = @"Stage";
        _textureMap = textureMap;
        _stageArray = stageArray;
    }
    return self;
}

- (void)dealloc {
    if (_textureMapStage) {
        delete _textureMapStage;
    }
}

- (void)startNewFrame {
    if (_textureMapStage) {
        delete _textureMapStage;
    }
    _textureMapStage = new iTerm2::TextureMapStage();
}

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                              creation:(NSImage *(^)(int))creation {
    return [_textureMap findOrAllocateIndexOfLockedTextureWithKey:key
                                                           column:column
                                                  textureMapStage:_textureMapStage
                                                       stageArray:_stageArray
                                                         creation:creation];
}

- (void)blitNewTexturesFromStagingAreaWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    DLog(@"%@: blit from staging to completion: %@", self.label, _indexesToBlit);
    if (!_textureMapStage->have_indexes_to_blit()) {
        // Uncomment to make the stage appear in the GPU debugger
        // [self doNoOpBlitWithStage:];
        return;
    }

    [_textureMap blitFromStage:_textureMapStage array:_stageArray commandBuffer:commandBuffer];
}

- (iTerm2::TextureMapStage *)textureMapStage {
    return _textureMapStage;
}

@end
