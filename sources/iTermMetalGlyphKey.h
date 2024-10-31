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

typedef NS_ENUM(unsigned char, iTermMetalGlyphType) {
    iTermMetalGlyphTypeRegular,
    iTermMetalGlyphTypeDecomposed
};

typedef struct {
    unichar code;
    unichar combiningSuccessor;  // 0 if none, which is the normal case.
    BOOL isComplex;
    BOOL boxDrawing;
    BOOL drawable;  // If this is NO it will be ignored
} iTermRegularGlyphPayload;

typedef struct {
    unsigned int fontID;
    unsigned short glyphNumber;
    NSPoint position;
    unsigned int fakeBold : 1;
    unsigned int fakeItalic : 1;
} iTermDecomposedGlyphPayload;

typedef struct iTermMetalGlyphKey {
    iTermMetalGlyphType type;
    union {
        iTermRegularGlyphPayload regular;
        iTermDecomposedGlyphPayload decomposed;
    } payload;

    iTermMetalGlyphKeyTypeface typeface : iTermMetalGlyphKeyTypefaceNumberOfBitsNeeded;
    BOOL thinStrokes;
    int visualColumn;
    int logicalIndex;
} iTermMetalGlyphKey;

// Features of a cell that do not affect which texture is selected as source material.
typedef struct {
    vector_float4 foregroundColor;
    vector_float4 backgroundColor;
    vector_float4 unprocessedBackgroundColor;
    BOOL hasUnderlineColor;
    vector_float4 underlineColor;
    iTermMetalGlyphAttributesUnderline underlineStyle : 4;
    BOOL annotation;  // affects underline color
} iTermMetalGlyphAttributes;

NS_INLINE NSString *iTermMetalGlyphTypeDecomposedDescription(const iTermDecomposedGlyphPayload *payload) {
    return [NSString stringWithFormat:@"Decomposed: font=%@ fakeBold=%@ fakeItalic=%@ glyph=%@ position=%@",
            @(payload->fontID),
            @(payload->fakeBold),
            @(payload->fakeItalic),
            @(payload->glyphNumber),
            NSStringFromPoint(payload->position)];
}

NS_INLINE NSString *iTermGlyphTypefaceString(const iTermMetalGlyphKey *key) {
    NSString *typefaceString = @"";
    if (key->typeface & iTermMetalGlyphKeyTypefaceBold) {
        typefaceString = [typefaceString stringByAppendingString:@"B"];
    }
    if (key->typeface & iTermMetalGlyphKeyTypefaceItalic) {
        typefaceString = [typefaceString stringByAppendingString:@"I"];
    }
    return typefaceString;
}

NS_INLINE NSString *iTermRegularGlyphPayloadDescription(const iTermRegularGlyphPayload *key) {
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


    return [NSString stringWithFormat:@"Regular: code=%@ combiningSuccessor=%@ complex=%@ boxDrawing=%@",
            formattedCode,
            formattedCombiningSuccessor,
            key->isComplex ? @"YES" : @"NO",
            key->boxDrawing ? @"YES" : @"NO"];
}

NS_INLINE NSString *iTermMetalGlyphKeyDescription(const iTermMetalGlyphKey *key) {
    NSString *payload = @"Invalid payload";
    switch (key->type) {
        case iTermMetalGlyphTypeRegular:
            payload = iTermRegularGlyphPayloadDescription(&key->payload.regular);
            break;
        case iTermMetalGlyphTypeDecomposed:
            payload = iTermMetalGlyphTypeDecomposedDescription(&key->payload.decomposed);
            break;
    }
    return [NSString stringWithFormat:@"%@ thinStrokes=%@ visualColumn=%@ typeface=%@",
            payload, key->thinStrokes ? @"YES" : @"NO", @(key->visualColumn), iTermGlyphTypefaceString(key)];
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
