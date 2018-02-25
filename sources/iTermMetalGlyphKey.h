//
//  iTermMetalGlyphKey.h
//  iTerm2
//
//  Created by George Nachman on 10/9/17.
//

#include <simd/simd.h>
#import "iTermShaderTypes.h"

// Gives number of bits needed to contain a typeface flag.
#define iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded 2

// This must be kept in sync with iTermASCIITextureAttributes
typedef NS_OPTIONS(int, iTermMetalGlyphKeyTypeface) {
    iTermMetalGlyphKeyTypefaceRegular = 0,
    iTermMetalGlyphKeyTypefaceBold = (1 << 0),
    iTermMetalGlyphKeyTypefaceItalic = (1 << 1),
    iTermMetalGlyphKeyTypefaceBoldItalic = (iTermMetalGlyphKeyTypefaceBold | iTermMetalGlyphKeyTypefaceItalic)
};

typedef struct {
    unichar code;
    BOOL isComplex;
    BOOL boxDrawing;
    BOOL thinStrokes;
    BOOL drawable;  // If this is NO it will be ignored
    iTermMetalGlyphKeyTypeface typeface : iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded;
} iTermMetalGlyphKey;

NS_INLINE NSString *iTermMetalGlyphKeyDescription(iTermMetalGlyphKey *key) {
    if (!key->drawable) {
        return @"not drawable";
    }
    id formattedCode;
    if (!key->isComplex) {
        formattedCode = [NSString stringWithFormat:@"0x%x (%C)", key->code, key->code];
    } else {
        formattedCode = @(key->code);
    }
    NSString *typefaceString = @"";
    if (key->typeface & iTermMetalGlyphKeyTypefaceBold) {
        typefaceString = [typefaceString stringByAppendingString:@"B"];
    }
    if (key->typeface & iTermMetalGlyphKeyTypefaceItalic) {
        typefaceString = [typefaceString stringByAppendingString:@"I"];
    }

    return [NSString stringWithFormat:@"code=%@ complex=%@ boxDrawing=%@ thinStrokes=%@ typeface=%@",
            formattedCode,
            key->isComplex ? @"YES" : @"NO",
            key->boxDrawing ? @"YES" : @"NO",
            key->thinStrokes ? @"YES" : @"NO",
            typefaceString];
}

NS_INLINE NSString *iTermStringFromColorVectorFloat4(vector_float4 v) {
    return [NSString stringWithFormat:@"(%0.2f, %0.2f, %0.2f, %0.2f)", v.x, v.y, v.z, v.w];
}

