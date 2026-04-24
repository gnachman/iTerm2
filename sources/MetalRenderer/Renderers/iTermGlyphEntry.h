//
//  iTermGlyphEntry.h
//  iTerm2
//
//  Created by George Nachman on 12/22/17.
//

#import "GlyphKey.h"
#import "iTermTexturePage.h"
#import <Metal/Metal.h>

namespace iTerm2 {
    enum dontcare2 {
        glyphEntryMagic = 0xfeedb0b0
    };

    struct GlyphEntry : TexturePageOwner {
        unsigned int _magic;

        GlyphEntry(int part,
                   GlyphKey key,
                   TexturePage *page,
                   int index,
                   bool is_emoji) :
        _magic(glyphEntryMagic),
        _part(part),
        _key(key),
        _page(page),
        _index(index),
        _is_emoji(is_emoji),
        _origin([_page->get_texture_array() offsetForIndex:_index]) {
            page->retain(this);
        }

        virtual ~GlyphEntry() {
            assert_valid();
            _magic = 0;
            _page->release(this);
        }

        void assert_valid() const {
            assert(_magic == glyphEntryMagic);
        }

        const MTLOrigin &get_origin() const {
            return _origin;
        }

        virtual bool texture_page_owner_is_glyph_entry() {
            return true;
        }

        NSString *description() const {
            return [NSString stringWithFormat:@"<iTerm2::GlyphEntry: %p part=%@ key=%@ page=%p index=%@ emoji=%@>",
                    this, @(_part), _key.description(), _page, @(_index), @(_is_emoji)];
        }
        int _part;
        GlyphKey _key;
        TexturePage *_page;
        int _index;
        bool _is_emoji;

    private:
        MTLOrigin _origin;
    };
}

