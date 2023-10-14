#ifndef ITERM_
#define ShaderTypes_h

#include <simd/simd.h>

typedef enum iTermVertexInputIndex {
    iTermVertexInputIndexVertices,
    iTermVertexInputIndexViewportSize,
    iTermVertexInputIndexPerInstanceUniforms,
    iTermVertexInputIndexOffset,
    iTermVertexInputIndexCursorDescription,
    iTermVertexInputIndexDefaultBackgroundColorInfo,  // Points at iTermMetalBackgroundColorInfo
    iTermVertexTextInfo,
    iTermVertexColorArray  // Points at per-quad vector_float4 color
} iTermVertexInputIndex;

typedef enum iTermTextureIndex {
    iTermTextureIndexPrimary = 0,

    // A texture containing the background we're drawing over.
    iTermTextureIndexBackground = 1,

    // Texture with subpixel model data for blending.
    iTermTextureIndexSubpixelModels = 2,
} iTermTextureIndex;

typedef enum {
    iTermFragmentBufferIndexMarginColor = 0,  // Points at a single float4
    iTermFragmentInputIndexTextureDimensions = 2,  // Points at iTermTextureDimensions
    iTermFragmentBufferIndexIndicatorAlpha = 3, // Points at a single float giving alpha value
    iTermFragmentBufferIndexFullScreenFlashColor = 4, // Points at a float4
    iTermFragmentInputIndexAlpha = 5,  // float4 pointer. Used by transparent windows on 10.14
    iTermFragmentInputIndexColor = 6,  // float4. Gives color for letterboxes/pillarboxes
} iTermFragmentBufferIndex;

// AND with mask to remove strikethrough bit
#define iTermMetalGlyphAttributesUnderlineBitmask 7
// OR this to set the strikethrough bit
#define iTermMetalGlyphAttributesUnderlineStrikethroughFlag 8
// If this grows update the size of the bit field in iTermMetalGlyphAttributes.
typedef enum {
    iTermMetalGlyphAttributesUnderlineNone = 0,
    iTermMetalGlyphAttributesUnderlineSingle = 1,
    iTermMetalGlyphAttributesUnderlineDouble = 2,
    iTermMetalGlyphAttributesUnderlineDashedSingle = 3,
    iTermMetalGlyphAttributesUnderlineCurly = 4,
    iTermMetalGlyphAttributesUnderlineHyperlink = 5,  // Rendered as a single with a dashed under it. Used for underlined text with hyperlink.

    iTermMetalGlyphAttributesUnderlineStrikethrough = iTermMetalGlyphAttributesUnderlineStrikethroughFlag,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndSingle = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 1,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndDouble = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 2,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndDashedSingle = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 3,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndCurly = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 4,
} iTermMetalGlyphAttributesUnderline;

typedef struct {
    vector_float4 defaultBackgroundColor;  // Emulates the iTermBackgroundColorView.
} iTermMetalBackgroundColorInfo;

typedef struct {
    // Distance in pixel space from origin
    vector_float2 position;

    // Distance in texture space from origin
    vector_float2 textureCoordinate;
} iTermVertex;

typedef struct iTermTextPIU {
#ifdef __cplusplus
    iTermTextPIU() {}
#endif
    // Offset from vertex in pixels.
    vector_float2 offset;

    // Offset of source texture
    vector_float2 textureOffset;

    // Values in 0-1. This will be composited over what's already rendered.
    vector_float4 textColor;

    // What kind of underline to draw. The offset is provided in iTermTextureDimensions.
    iTermMetalGlyphAttributesUnderline underlineStyle;

    // Color for underline, if one is to be drawn
    vector_float4 underlineColor;
} iTermTextPIU;

typedef struct {
    // Offset from vertex in pixels.
    vector_float2 offset;

    // Offset of source texture in pixels.
    vector_float2 textureOffset;
} iTermMarkPIU;

typedef struct {
    float y;
    vector_float4 color;
    float rightInset;
} iTermLineStyleMarkPIU;

typedef struct {
    // Offset from vertex
    vector_float2 offset;

    // Number of cells occupied (stretches to the right)
    unsigned short runLength;

    // Number of rows occupied (stretches down)
    unsigned short numRows;

    // Background color
    vector_float4 color;
} iTermBackgroundColorPIU;

typedef struct {
    vector_float4 color;
    vector_float2 origin;
} iTermCursorDescription;

typedef struct {
    vector_float2 textureSize;  // Size of texture atlas in pixels
    vector_float2 glyphSize;  // Size of a glyph within the atlas in pixels
    vector_float2 cellSize;  // Size of a cell
    vector_float2 underlineOffset;  // Distance from bottom left of cell to underline in pixels
    float underlineThickness;  // Thickness of underline in pixels
    vector_float2 strikethroughOffset;
    float strikethroughThickness;
    float scale;  // 2 for retina, 1 for non retina
} iTermTextureDimensions;

#define iTermTextVertexInfoFlagsSolidUnderlines 1
typedef struct {
    int flags;  // See iTermTextVertexInfoFlags defines
    float glyphWidth;
    unsigned int numInstances;
    float verticalOffset;  // For non-grid-aligned text, such as offscreen command line.
} iTermVertexTextInfoStruct;

#endif
