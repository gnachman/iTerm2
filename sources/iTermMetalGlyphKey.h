//
//  iTermMetalGlyphKey.h
//  iTerm2
//
//  Created by George Nachman on 10/9/17.
//

#include <simd/simd.h>

typedef struct {
    unichar code;
    BOOL isComplex;
    BOOL image;
    BOOL boxDrawing;
    BOOL thinStrokes;
} iTermMetalGlyphKey;

typedef struct {
    vector_float4 foregroundColor;
    vector_float4 backgroundColor;
} iTermMetalGlyphAttributes;

