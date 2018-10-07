#ifndef ITERM_
#define ShaderTypes_h

#include <simd/simd.h>

typedef enum iTermVertexInputIndex {
    iTermVertexInputIndexVertices,
    iTermVertexInputIndexViewportSize,
    iTermVertexInputIndexPerInstanceUniforms,
    iTermVertexInputIndexOffset,
    iTermVertexInputIndexCursorDescription,
    iTermVertexInputMojaveVertexTextInfo
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
    iTermFragmentBufferIndexColorModels = 1, // Array of 256-byte color tables
    iTermFragmentInputIndexTextureDimensions = 2,  // Points at iTermTextureDimensions
    iTermFragmentBufferIndexIndicatorAlpha = 3, // Points at a single float giving alpha value
    iTermFragmentBufferIndexFullScreenFlashColor = 4, // Points at a float4
    iTermFragmentInputIndexAlpha = 5,  // float4 pointer. Used by transparent windows on 10.14
} iTermFragmentBufferIndex;

typedef enum {
    iTermMetalGlyphAttributesUnderlineNone = 0,
    iTermMetalGlyphAttributesUnderlineSingle = 1,
    iTermMetalGlyphAttributesUnderlineDouble = 2,
    iTermMetalGlyphAttributesUnderlineDashedSingle = 3
} iTermMetalGlyphAttributesUnderline;

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

    // Values in 0-1. These will be composited over what's already rendered.
    vector_float4 backgroundColor;
    vector_float4 textColor;

    // Passed through to the solid background color fragment shader.
    vector_int3 colorModelIndex;  // deprecated for macOS 10.14+

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
    float underlineOffset;  // Distance from bottom of cell to underline in pixels
    float underlineThickness;  // Thickness of underline in pixels
    float scale;  // 2 for retina, 1 for non retina
} iTermTextureDimensions;

typedef struct {
    vector_uint2 viewportSize;

    // Used to adjust the alpha channel. Defines a function f(x)=c+m*b where
    // f(x) is the alpha value to output, x is the alpha value of a pixel, and
    // b is the perceived brightness of the text color. c is powerConstant,
    // m is powerMultiplier.
    float powerConstant;
    float powerMultiplier;
} iTermVertexInputMojaveVertexTextInfoStruct;

#endif
