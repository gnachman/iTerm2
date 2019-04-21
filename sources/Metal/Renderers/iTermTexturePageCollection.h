//
//  iTermTexturePageCollection.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import <Metal/Metal.h>
#import "iTermGlyphEntry.h"
#import "iTermMetalBufferPool.h"
#import "iTermTexturePage.h"
#include <unordered_map>
#include <set>

namespace iTerm2 {
    // Holds a collection of iTerm2::TexturePages. Provides an interface for finding a GlyphEntry
    // for a GlyphKey, adding a new glyph, and pruning disused texture pages. Tries to be fast.
    class TexturePageCollection : TexturePageOwner {
    public:
        TexturePageCollection(id<MTLDevice> device,
                              const vector_uint2 cellSize,
                              const int pageCapacity,
                              const int maximumNumberOfPages) :
        _device(device),
        _cellSize(cellSize),
        _pageCapacity(pageCapacity),
        _maximumNumberOfPages(maximumNumberOfPages),
        _openPage(NULL) { }

        virtual ~TexturePageCollection() {
            if (_openPage) {
                _openPage->assert_valid();
                _openPage->release(this);
                _openPage = NULL;
            }
            for (auto page : _allPages) {
                page->assert_valid();
                page->release(this);
            }
            for (auto it = _pages.begin(); it != _pages.end(); it++) {
                std::vector<const GlyphEntry *> *vector = it->second;
                for (auto glyph_entry : *vector) {
                    delete glyph_entry;
                }
                delete vector;
            }
        }

        // Returns a collection of glyph entries for a glyph key, or NULL if none exists.
        std::vector<const GlyphEntry *> *find(const GlyphKey &glyphKey) const {
            auto const it = _pages.find(glyphKey);
            if (it == _pages.end()) {
                return NULL;
            } else {
                return it->second;
            }
        }

        // Adds a collection of glyph entries for a glyph key, allocating a new texture page if
        // needed.
        std::vector<const GlyphEntry *> *add(int column,
                                             const GlyphKey &glyphKey,
                                             iTermMetalBufferPoolContext *context,
                                             NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^creator)(int, BOOL *)) {
            BOOL emoji;
            NSDictionary<NSNumber *, iTermCharacterBitmap *> *images = creator(column, &emoji);
            std::vector<const GlyphEntry *> *result = new std::vector<const GlyphEntry *>();
            _pages[glyphKey] = result;
            for (NSNumber *partNumber in images) {
                iTermCharacterBitmap *image = images[partNumber];
                const GlyphEntry *entry = internal_add(partNumber.intValue, glyphKey, image, emoji, context);
                result->push_back(entry);
            }
            DLog(@"Added %@. Count is now %@", glyphKey.description(), @(_allPages.size() * _pageCapacity));

            return result;
        }

        const vector_uint2 &get_cell_size() const {
            return _cellSize;
        }

        // Discard least-recently used texture pages.
        void prune_if_needed() {
            if (is_over_maximum_size()) {
                ELog(@"Pruning. Have %@ pages. Each page stores up to %@ glyphs. Max pages is %@",
                     @(_allPages.size()),
                     @(_pageCapacity),
                     @(_maximumNumberOfPages));
                // Create a copy of texture pages sorted by recency of use (from least recent to most).
                std::vector<TexturePage *> pages;
                std::copy(_allPages.begin(), _allPages.end(), std::back_inserter(pages));
                std::sort(pages.begin(), pages.end(), TexturePageCollection::LRUComparison);

                for (auto page : pages) {
                    page->assert_valid();
                }

                for (int i = 0; is_over_maximum_size() && i < pages.size(); i++) {
                    ITOwnershipLog(@"OWNERSHIP: Begin pruning page %p", pages[i]);
                    TexturePage *pageToPrune = pages[i];
                    internal_prune(pageToPrune);
                    ITOwnershipLog(@"OWNERSHIP: Done pruning page %p", pageToPrune);
                }
            } else {
                DLog(@"Not pruning");
            }
        }

    private:
        const GlyphEntry *internal_add(int part, const GlyphKey &key, iTermCharacterBitmap *image, bool is_emoji, iTermMetalBufferPoolContext *context) {
            if (!_openPage) {
                _openPage = new TexturePage(this, _device, _pageCapacity, _cellSize);  // Retains this for _openPage
                [context didAddTextureOfSize:_cellSize.x * _cellSize.y * _pageCapacity];
                // Add to allPages and retain that reference too
                _allPages.insert(_openPage);
                _openPage->retain(this);
                _openPage->assert_valid();
            }

            TexturePage *openPage = _openPage;
            openPage->assert_valid();
            ITExtraDebugAssert(_openPage->get_available_count() > 0);
            const GlyphEntry *result = new GlyphEntry(part,
                                                      key,
                                                      openPage,
                                                      openPage->add_image(image, is_emoji),
                                                      is_emoji);
            if (openPage->get_available_count() == 0) {
                openPage->release(this);
                _openPage = NULL;
            }
            return result;
        }

        // Remove all references to `pageToPrune` and all glyph entries that reference the page.
        void internal_prune(TexturePage *pageToPrune) {
            pageToPrune->assert_valid();
            if (pageToPrune == _openPage) {
                pageToPrune->release(this);
                _openPage = NULL;
            }
            _allPages.erase(pageToPrune);
            bool freed = pageToPrune->release(this);
#if DEBUG
            assert(!freed);
#endif
            ITExtraDebugAssert(pageToPrune->get_retain_count() > 0);

            // Make all glyph entries remove their references to the page. Remove our
            // references to the glyph entries.
            auto owners = pageToPrune->get_owners();  // map<TexturePageOwner *, int>
            ITOwnershipLog(@"OWNERSHIP: page %p has %d owners", pageToPrune, (int)owners.size());
            for (auto pair : owners) {
                auto owner = pair.first;  // TexturePageOwner *
                auto count = pair.second;  // int
                ITOwnershipLog(@"OWNERSHIP: remove all %d references by owner %p", count, owner);
                for (int j = 0; j < count; j++) {
                    if (owner->texture_page_owner_is_glyph_entry()) {
                        GlyphEntry *glyph_entry = static_cast<GlyphEntry *>(owner);
#if DEBUG
                        assert(!freed);
#endif
                        freed = pageToPrune->release(glyph_entry);
                        auto it = _pages.find(glyph_entry->_key);
                        if (it != _pages.end()) {
                            // Remove from _pages as soon as the first part is found for this glyph
                            // key. Subsequent parts won't need to remove an entry from _pages.
                            std::vector<const GlyphEntry *> *entries = it->second;
                            delete entries;
                            _pages.erase(it);
                        }
                    }
                }
            }
        }

        static bool LRUComparison(TexturePage *a, TexturePage *b) {
            return a->get_last_used() < b->get_last_used();
        }

        bool is_over_maximum_size() const {
            return _allPages.size() > _maximumNumberOfPages;
        }

    private:
        TexturePageCollection &operator=(const TexturePageCollection &);
        TexturePageCollection(const TexturePageCollection &);

        id<MTLDevice> _device;
        const vector_uint2 _cellSize;
        const int _pageCapacity;
        const int _maximumNumberOfPages;
        std::unordered_map<GlyphKey, std::vector<const GlyphEntry *> *> _pages;
        std::set<TexturePage *> _allPages;
        TexturePage *_openPage;
    };
}

@interface iTermTexturePageCollectionSharedPointer : NSObject
@property (nonatomic, readonly) iTerm2::TexturePageCollection *object;

- (instancetype)initWithObject:(iTerm2::TexturePageCollection *)object;
- (instancetype)init NS_UNAVAILABLE;

@end
