//
//  iTermTexturePage.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import "iTermTextureArray.h"

#import <Metal/Metal.h>
#import <simd/simd.h>

extern "C" {
#import "DebugLogging.h"
}
#include <map>
#include <vector>

// This is useful when we over-release a texture page.
// TODO: Use shared_ptr or the like, if it can do the job.
#define ENABLE_OWNERSHIP_LOG 0
#if ENABLE_OWNERSHIP_LOG
#define ITOwnershipLog(args...) NSLog
#else
#define ITOwnershipLog(args...)
#endif

namespace iTerm2 {
    class TexturePage;

    class TexturePageOwner {
    public:
        virtual bool texture_page_owner_is_glyph_entry() {
            return false;
        }
    };

    class TexturePage {
    public:
        TexturePage(TexturePageOwner *owner,
                    id<MTLDevice> device,
                    int capacity,
                    vector_uint2 cellSize) :
        _capacity(capacity),
        _cell_size(cellSize),
        _count(0),
        _emoji(capacity) {
            retain(owner);
            _textureArray = [[iTermTextureArray alloc] initWithTextureWidth:cellSize.x
                                                              textureHeight:cellSize.y
                                                                arrayLength:capacity
                                                                     device:device];
            _atlas_size = simd_make_uint2(_textureArray.atlasSize.width,
                                          _textureArray.atlasSize.height);
            _reciprocal_atlas_size = 1.0f / simd_make_float2(_atlas_size.x, _atlas_size.y);
        }

        virtual ~TexturePage() {
            ITOwnershipLog(@"OWNERSHIP: Destructor for page %p", this);
        }

        int get_available_count() const {
            return _capacity - _count;
        }

        int add_image(iTermCharacterBitmap *image, bool is_emoji) {
            ITExtraDebugAssert(_count < _capacity);
            [_textureArray setSlice:_count withBitmap:image];
            _emoji[_count] = is_emoji;
            return _count++;
        }

        id<MTLTexture> get_texture() const {
            return _textureArray.texture;
        }

        iTermTextureArray *get_texture_array() const {
            return _textureArray;
        }

        bool get_is_emoji(const int index) const {
            return _emoji[index];
        }

        const vector_uint2 &get_cell_size() const {
            return _cell_size;
        }

        const vector_uint2 &get_atlas_size() const {
            return _atlas_size;
        }

        const vector_float2 &get_reciprocal_atlas_size() const {
            return _reciprocal_atlas_size;
        }

        void retain(TexturePageOwner *owner) {
            _owners[owner]++;
            ITOwnershipLog(@"OWNERSHIP: retain %p as owner of %p with refcount %d", owner, this, (int)_owners[owner]);
        }

        void release(TexturePageOwner *owner) {
            ITOwnershipLog(@"OWNERSHIP: release %p as owner of %p. New refcount for this owner will be %d", owner, this, (int)_owners[owner]-1);
            ITExtraDebugAssert(_owners[owner] > 0);

            auto it = _owners.find(owner);
#if ENABLE_OWNERSHIP_LOG
            if (it == _owners.end()) {
                ITOwnershipLog(@"I have %d owners", (int)_owners.size());
                for (auto pair : _owners) {
                    ITOwnershipLog(@"%p is owner", pair.first);
                }
                ITExtraDebugAssert(it != _owners.end());
            }
#endif
            it->second--;
            if (it->second == 0) {
                _owners.erase(it);
                if (_owners.empty()) {
                    ITOwnershipLog(@"OWNERSHIP: DELETE %p", this);
                    delete this;
                    return;
                }
            }
        }

        void record_use() {
            static long long use_count;
            _last_used = use_count++;
        }

        long long get_last_used() const {
            return _last_used;
        }

        std::map<TexturePageOwner *, int> get_owners() const {
#if ENABLE_OWNERSHIP_LOG
            for (auto pair : _owners) {
                ITExtraDebugAssert(pair.second > 0);
            }
#endif
            return _owners;
        }

        // This is for debugging purposes only.
        int get_retain_count() const {
            int sum = 0;
            for (auto pair : _owners) {
                sum += pair.second;
            }
            return sum;
        }

    private:
        TexturePage();
        TexturePage &operator=(const TexturePage &);
        TexturePage(const TexturePage &);

        iTermTextureArray *_textureArray;
        int _capacity;
        vector_uint2 _cell_size;
        vector_uint2 _atlas_size;
        int _count;
        std::vector<bool> _emoji;
        vector_float2 _reciprocal_atlas_size;
        std::map<TexturePageOwner *, int> _owners;
        long long _last_used;
    };
}

