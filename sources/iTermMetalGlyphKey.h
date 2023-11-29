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
    unichar combiningSuccessor;  // 0 if none, which is the normal case.
    BOOL isComplex;
    BOOL boxDrawing;
    BOOL thinStrokes;
    BOOL drawable;  // If this is NO it will be ignored
    BOOL antialiased;  // Only relevant for non-ascii glyphs
    iTermMetalGlyphKeyTypeface typeface : iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded;
} iTermMetalGlyphKey;

// Features of a cell that do not affect which texture is selected as source material.
typedef struct {
    vector_float4 foregroundColor;
    vector_float4 backgroundColor;
    BOOL hasUnderlineColor;
    vector_float4 underlineColor;
    iTermMetalGlyphAttributesUnderline underlineStyle : 4;
    BOOL annotation;  // affects underline color
} iTermMetalGlyphAttributes;

NS_INLINE NSString *iTermMetalGlyphKeyDescription(const iTermMetalGlyphKey *key) {
    if (!key->drawable) {
        return @"not drawable";
    }
    id formattedCode;
    if (!key->isComplex) {
        formattedCode = [NSString stringWithFormat:@"0x%x (%C)", key->code, key->code];
    } else {
        formattedCode = @(key->code);
    }

    id formattedCombiningSuccessor;
    if (key->combiningSuccessor) {
        formattedCombiningSuccessor = [NSString stringWithFormat:@"0x%x (%C)", key->combiningSuccessor, key->combiningSuccessor];
    } else {
        formattedCombiningSuccessor = @"none";
    }

    NSString *typefaceString = @"";
    if (key->typeface & iTermMetalGlyphKeyTypefaceBold) {
        typefaceString = [typefaceString stringByAppendingString:@"B"];
    }
    if (key->typeface & iTermMetalGlyphKeyTypefaceItalic) {
        typefaceString = [typefaceString stringByAppendingString:@"I"];
    }

    return [NSString stringWithFormat:@"code=%@ combiningSuccessor=%@ complex=%@ boxDrawing=%@ thinStrokes=%@ typeface=%@ antialiased=%@",
            formattedCode,
            formattedCombiningSuccessor,
            key->isComplex ? @"YES" : @"NO",
            key->boxDrawing ? @"YES" : @"NO",
            key->thinStrokes ? @"YES" : @"NO",
            typefaceString,
            key->antialiased ? @"YES" : @"NO"];
}

NS_INLINE NSString *iTermStringFromColorVectorFloat4(vector_float4 v) {
    return [NSString stringWithFormat:@"(%0.2f, %0.2f, %0.2f, %0.2f)", v.x, v.y, v.z, v.w];
}

NS_INLINE NSString *iTermMetalGlyphAttributesDescription(iTermMetalGlyphAttributes *attrs) {
    NSString *underline;
    switch (attrs->underlineStyle) {
        case iTermMetalGlyphAttributesUnderlineNone:
            underline = @"none";
            break;
        case iTermMetalGlyphAttributesUnderlineDouble:
            underline = @"DOUBLE";
            break;
        case iTermMetalGlyphAttributesUnderlineHyperlink:
            underline = @"HYPERLINK";
            break;
        case iTermMetalGlyphAttributesUnderlineSingle:
            underline = @"SINGLE";
            break;
        case iTermMetalGlyphAttributesUnderlineDashedSingle:
            underline = @"DASHED SINGLE";
            break;
        case iTermMetalGlyphAttributesUnderlineCurly:
            underline = @"CURLY";
            break;
        case iTermMetalGlyphAttributesUnderlineStrikethrough:
            underline = @"STRIKETHROUGH";
            break;
        case iTermMetalGlyphAttributesUnderlineStrikethroughAndDouble:
            underline = @"STRIKETHROUGH+DOUBLE";
            break;
        case iTermMetalGlyphAttributesUnderlineStrikethroughAndSingle:
            underline = @"STRIKETHROUGH+SINGLE";
            break;
        case iTermMetalGlyphAttributesUnderlineStrikethroughAndDashedSingle:
            underline = @"STRIKETHROUGH+DASHED SINGLE";
            break;
        case iTermMetalGlyphAttributesUnderlineStrikethroughAndCurly:
            underline = @"STRIKETHROUGH+CURLY";
            break;
    }
    return [NSString stringWithFormat:@"fg=%@ bg=%@ underline=%@ hasUnderlineColor=%@ underlineColor=%@ annotation=%@",
            iTermStringFromColorVectorFloat4(attrs->foregroundColor),
            iTermStringFromColorVectorFloat4(attrs->backgroundColor),
            underline,
            @(attrs->hasUnderlineColor),
            iTermStringFromColorVectorFloat4(attrs->underlineColor),
            attrs->annotation ? @"YES" : @"NO"];
}
