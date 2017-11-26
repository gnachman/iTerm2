//
//  iTermMetalGlyphKey.h
//  iTerm2
//
//  Created by George Nachman on 10/9/17.
//

#include <simd/simd.h>

#warning TODO: Add fakeBold and fakeItalic
typedef struct {
    unichar code;
    BOOL isComplex;
    BOOL image;
    BOOL boxDrawing;
    BOOL thinStrokes;
    BOOL drawable;  // If this is NO it will be ignored
} iTermMetalGlyphKey;

typedef struct {
    vector_float4 foregroundColor;
    vector_float4 backgroundColor;
} iTermMetalGlyphAttributes;

