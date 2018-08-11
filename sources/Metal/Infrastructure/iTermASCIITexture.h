//
//  iTermASCIITexture.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/17.
//

#import <Cocoa/Cocoa.h>

#if __cplusplus
extern "C" {
#endif
#import "DebugLogging.h"
#if __cplusplus
}
#endif

#import "iTermMetalGlyphKey.h"
#import "iTermTextureArray.h"

#import <simd/simd.h>

// This must be kept in sync with iTermMetalGlyphKeyTypeface
typedef NS_OPTIONS(NSUInteger, iTermASCIITextureAttributes) {
    iTermASCIITextureAttributesBold = (1 << 0),
    iTermASCIITextureAttributesItalic = (1 << 1),
    iTermASCIITextureAttributesThinStrokes = (1 << 2),

    iTermASCIITextureAttributesMax = (1 << 2)  // Equals the largest value above
};
#if __cplusplus
static_assert(iTermASCIITextureAttributesBold == iTermMetalGlyphKeyTypefaceBold, "Bold flags differ");
static_assert(iTermASCIITextureAttributesItalic == iTermMetalGlyphKeyTypefaceItalic, "Italic flags differ");
#endif

NS_INLINE iTermASCIITextureAttributes iTermASCIITextureAttributesFromGlyphKeyTypeface(iTermMetalGlyphKeyTypeface typeface,
                                                                                      BOOL thinStrokes) {
    static const int mask = ((1 << iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded) - 1);
    iTermASCIITextureAttributes result = (typeface & mask);
    if (thinStrokes) {
        result |= iTermASCIITextureAttributesThinStrokes;
    }
    return result;
}

extern const unsigned char iTermASCIITextureMinimumCharacter;
extern const unsigned char iTermASCIITextureMaximumCharacter;

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(int, iTermASCIITextureParts) {
    iTermASCIITexturePartsLeft = (1 << 0),
    iTermASCIITexturePartsCenter = (1 << 1),
    iTermASCIITexturePartsRight = (1 << 2)
};

@class iTermCharacterBitmap;

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermASCIITexture : NSObject

@property (nonatomic, readonly) iTermTextureArray *textureArray;
@property (nonatomic, readonly) iTermASCIITextureAttributes attributes;
// C array that maps an ASCII code to which parts are present
@property (nonatomic, readonly) iTermASCIITextureParts *parts;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttributes:(iTermASCIITextureAttributes)attributes
                         glyphSize:(CGSize)glyphSize
                            device:(id<MTLDevice>)device
                          creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> * _Nonnull (^)(char, iTermASCIITextureAttributes))creation NS_DESIGNATED_INITIALIZER;

@end

typedef NS_ENUM(int, iTermASCIITextureOffset) {
    iTermASCIITextureOffsetLeft = 0,
    iTermASCIITextureOffsetCenter = 1,
    iTermASCIITextureOffsetRight = 2,

    iTermASCIITextureOffsetCount = 3
};

// Convert a drawable ASCII character into an index into the texture array. Note that control
// character, SPACE, and DEL (127) are not accepted.
NS_INLINE int iTermASCIITextureIndexOfCode(char code, iTermASCIITextureOffset offset) {
    ITDebugAssert(code >= iTermASCIITextureMinimumCharacter);
    ITDebugAssert(code <= iTermASCIITextureMaximumCharacter);
    return offset + iTermASCIITextureOffsetCount * (code - iTermASCIITextureMinimumCharacter);
}

// Implements isEqual:
NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermASCIITextureGroup : NSObject {
@public
    iTermASCIITexture *_textures[iTermASCIITextureAttributesMax * 2];
}

@property (nonatomic, readonly) CGSize glyphSize;
@property (nonatomic, strong, readonly) id<MTLDevice> device;
@property (nonatomic, copy, readonly) NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^creation)(char, iTermASCIITextureAttributes);
@property (nonatomic, readonly) id creationIdentifier;
@property (nonatomic, readonly) vector_float2 atlasSize;

- (instancetype)initWithGlyphSize:(CGSize)glyphSize
                           device:(id<MTLDevice>)device
               creationIdentifier:(id)creationIdentifier
                         creation:(NSDictionary<NSNumber *, iTermCharacterBitmap *> *(^)(char, iTermASCIITextureAttributes))creation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (iTermASCIITexture *)asciiTextureForAttributes:(iTermASCIITextureAttributes)attributes;

@end

NS_ASSUME_NONNULL_END
