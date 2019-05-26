//
//  GlyphKey.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import <Foundation/Foundation.h>
#import "iTermMetalGlyphKey.h"

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
            return (_repr.code == other._repr.code &&
                    _repr.combiningSuccessor == other._repr.combiningSuccessor &&
                    _repr.isComplex == other._repr.isComplex &&
                    _repr.boxDrawing == other._repr.boxDrawing &&
                    _repr.thinStrokes == other._repr.thinStrokes &&
                    _repr.typeface == other._repr.typeface);
        }

        inline std::size_t get_hash() const {
            return _hash;
        }

        NSString *description() const {
            return [NSString stringWithFormat:@"[GlyphKey: code=%@ combiningSuccessor=%@ complex=%@ boxdrawing=%@ thinstrokes=%@ drawable=%@ typeface=%@]",
                    @(_repr.code),
                    @(_repr.combiningSuccessor),
                    @(_repr.isComplex),
                    @(_repr.boxDrawing),
                    @(_repr.thinStrokes),
                    @(_repr.drawable),
                    @(_repr.typeface)];
        }

    private:
        inline std::size_t compute_hash() const {
            std::size_t seed = 0;

            hash_combine(seed, _repr.code);
            hash_combine(seed, _repr.combiningSuccessor);
            hash_combine(seed, _repr.isComplex);
            hash_combine(seed, _repr.boxDrawing);
            hash_combine(seed, _repr.thinStrokes);
            // No need to include _repr.drawable because we just skip those glyphs.
            hash_combine(seed, _repr.typeface);

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

