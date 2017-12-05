//
//  iTermMetalGlyphKey.h
//  iTerm2
//
//  Created by George Nachman on 10/9/17.
//

#include <simd/simd.h>

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
    BOOL image;
    BOOL boxDrawing;
    BOOL thinStrokes;
    BOOL drawable;  // If this is NO it will be ignored
    iTermMetalGlyphKeyTypeface typeface : iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded;
} iTermMetalGlyphKey;

// Features of a cell that do not affect which texture is selected as source material.
typedef struct {
    vector_float4 foregroundColor;
    vector_float4 backgroundColor;
    bool underline;
} iTermMetalGlyphAttributes;

