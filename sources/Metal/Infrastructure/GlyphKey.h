//
//  GlyphKey.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalGlyphKey.h"
#import "NSFont+iTerm.h"

namespace iTerm2 {
    template <class T>
    inline void hash_combine(std::size_t& seed, const T& v) {
        std::hash<T> hasher;
        seed ^= hasher(v) + 0x9e3779b9 + (seed<<6) + (seed>>2);
    }

    class GlyphKey {
    private:
        iTermMetalGlyphKey _repr;
        std::size_t _hash;

    public:
        explicit GlyphKey(const iTermMetalGlyphKey *repr) : _repr(*repr) {
            _hash = compute_hash();
        }
        GlyphKey() : _hash(0) { }

        // Copy constructor
        GlyphKey(const GlyphKey &other) {
            _repr = other._repr;
            _hash = other._hash;
        }

        inline bool operator==(const GlyphKey &other) const {
            if (_repr.type != other._repr.type ||
                _repr.typeface != other._repr.typeface ||
                _repr.visualColumn != other._repr.visualColumn ||
                _repr.thinStrokes != other._repr.thinStrokes) {
                return false;
            }

            switch (_repr.type) {
                case iTermMetalGlyphTypeRegular:
                    return (_repr.payload.regular.code == other._repr.payload.regular.code &&
                            _repr.payload.regular.combiningSuccessor == other._repr.payload.regular.combiningSuccessor &&
                            _repr.payload.regular.isComplex == other._repr.payload.regular.isComplex &&
                            _repr.payload.regular.boxDrawing == other._repr.payload.regular.boxDrawing);
                case iTermMetalGlyphTypeDecomposed:
                    return (_repr.payload.decomposed.fontID == other._repr.payload.decomposed.fontID &&
                            _repr.payload.decomposed.fakeBold == other._repr.payload.decomposed.fakeBold &&
                            _repr.payload.decomposed.fakeItalic == other._repr.payload.decomposed.fakeItalic &&
                            _repr.payload.decomposed.glyphNumber == other._repr.payload.decomposed.glyphNumber &&
                            NSEqualPoints(_repr.payload.decomposed.position,
                                          other._repr.payload.decomposed.position));
            }
        }

        inline std::size_t get_hash() const {
            return _hash;
        }

        NSString *description() const {
            switch (_repr.type) {
                case iTermMetalGlyphTypeRegular:
                    return [NSString stringWithFormat:@"[GlyphKey regular: code=%@ combiningSuccessor=%@ complex=%@ boxdrawing=%@ thinStrokes=%@ drawable=%@ typeface=%@]",
                            @(_repr.payload.regular.code),
                            @(_repr.payload.regular.combiningSuccessor),
                            @(_repr.payload.regular.isComplex),
                            @(_repr.payload.regular.boxDrawing),
                            @(_repr.thinStrokes),
                            @(_repr.payload.regular.drawable),
                            iTermGlyphTypefaceString(&_repr)];
                case iTermMetalGlyphTypeDecomposed:
                    return [NSString stringWithFormat:@"[GlyphKey decomposed: font=%@ fakeBold=%@ fakeItalic=%@ glyph=%@ thinStrokes=%@ typeface=%@]",
                            [NSFont it_fontWithMetalID:_repr.payload.decomposed.fontID],
                            @(_repr.payload.decomposed.fakeBold),
                            @(_repr.payload.decomposed.fakeItalic),
                            @(_repr.payload.decomposed.glyphNumber),
                            @(_repr.thinStrokes),
                            iTermGlyphTypefaceString(&_repr)];
            }
        }

    private:
        inline std::size_t compute_hash() const {
            std::size_t seed = 0;

            hash_combine(seed, _repr.type);
            hash_combine(seed, _repr.thinStrokes);
            hash_combine(seed, _repr.typeface);
            switch (_repr.type) {
                case iTermMetalGlyphTypeRegular:
                    // No need to include _repr.drawable because we just skip those glyphs.
                    hash_combine(seed, _repr.payload.regular.code);
                    hash_combine(seed, _repr.payload.regular.combiningSuccessor);
                    hash_combine(seed, _repr.payload.regular.isComplex);
                    hash_combine(seed, _repr.payload.regular.boxDrawing);
                    break;

                case iTermMetalGlyphTypeDecomposed:
                    hash_combine(seed, _repr.payload.decomposed.fontID);
                    hash_combine(seed, _repr.payload.decomposed.glyphNumber);
                    hash_combine(seed, _repr.payload.decomposed.fakeBold);
                    hash_combine(seed, _repr.payload.decomposed.fakeItalic);
                    hash_combine(seed, _repr.payload.decomposed.position.x);
                    hash_combine(seed, _repr.payload.decomposed.position.y);
                    break;
            }

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

