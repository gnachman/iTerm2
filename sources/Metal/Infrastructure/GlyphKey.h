//
//  GlyphKey.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/19/17.
//

#import <Foundation/Foundation.h>

namespace iTerm2 {
    template <class T>
    inline void hash_combine(std::size_t& seed, const T& v) {
        std::hash<T> hasher;
        seed ^= hasher(v) + 0x9e3779b9 + (seed<<6) + (seed>>2);
    }

    class GlyphKey {
    private:
        iTermMetalGlyphKey _repr;
        // Glyphs larger than once cell are broken into multiple parts.
        int _part;

        GlyphKey();

    public:
        GlyphKey(const iTermMetalGlyphKey *repr, int part) : _repr(*repr), _part(part) { }

        // Copy constructor
        GlyphKey(const GlyphKey &other) {
            _repr = other._repr;
            _part = other._part;
        }

        inline bool operator==(const GlyphKey &other) const {
            return (_repr.code == other._repr.code &&
                    _repr.isComplex == other._repr.isComplex &&
                    _repr.image == other._repr.image &&
                    _repr.boxDrawing == other._repr.boxDrawing &&
                    _repr.thinStrokes == other._repr.thinStrokes &&
                    _part == other._part);
        }

        inline std::size_t get_hash() const {
            std::size_t seed = 0;
            hash_combine(seed, _repr.code);
            hash_combine(seed, _repr.isComplex);
            hash_combine(seed, _repr.image);
            hash_combine(seed, _repr.boxDrawing);
            hash_combine(seed, _repr.thinStrokes);
            hash_combine(seed, _repr.thinStrokes);
            hash_combine(seed, _part);
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

