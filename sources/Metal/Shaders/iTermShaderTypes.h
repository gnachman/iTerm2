#ifndef ITERM_
#define ShaderTypes_h

#include <simd/simd.h>
#import "iTermThinStrokes.h"

typedef enum iTermVertexInputIndex {
    iTermVertexInputIndexVertices = 0,
    iTermVertexInputIndexViewportSize = 1,
    iTermVertexInputIndexPerInstanceUniforms = 2,
    iTermVertexInputIndexOffset = 3,
    iTermVertexInputIndexCursorDescription = 4,
    iTermVertexInputIndexASCIITextConfiguration = 5,
    iTermVertexInputIndexASCIITextRowInfo = 6,  // iTermASCIIRowInfo
    iTermVertexInputIndexColorMap = 7,  // data with serialized iTermColorMap
    iTermVertexInputSelectedIndices = 8,  // data is an array of bits giving selected indices
    iTermVertexInputFindMatchIndices = 9,  // data is an array of bits giving find-match indices to highlight
    iTermVertexInputMarkedIndices = 10,  // data is an array of bits giving marked text locations
    iTermVertexInputUnderlinedIndices = 11,  // data is an array of bits giving underlined range locations
    iTermVertexInputAnnotatedIndices = 12,  // data in array of bits giving annotation locations
    iTermVertexInputDebugBuffer = 13,  // iTermMetalDebugBuffer
} iTermVertexInputIndex;

typedef enum iTermTextureIndex {
    iTermTextureIndexPrimary = 0,

    // A texture containing the background we're drawing over.
    iTermTextureIndexBackground = 1,

    // Texture atlases used by the ASCII renderer
    iTermTextureIndexPlain = 2,
    iTermTextureIndexBold = 3,
    iTermTextureIndexItalic = 4,
    iTermTextureIndexBoldItalic = 5,
    iTermTextureIndexThin = 6,
    iTermTextureIndexThinBold = 7,
    iTermTextureIndexThinItalic = 8,
    iTermTextureIndexThinBoldItalic = 9,

} iTermTextureIndex;

typedef enum {
    iTermFragmentBufferIndexMarginColor = 0,  // Points at a single float4
    iTermFragmentBufferIndexColorModels = 1, // Array of 256-byte color tables
    iTermFragmentInputIndexTextureDimensions = 2,  // Points at iTermTextureDimensions
    iTermFragmentBufferIndexIndicatorAlpha = 3, // Points at a single float giving alpha value
    iTermFragmentBufferIndexFullScreenFlashColor = 4, // Points at a float4
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

    // This is true for text and false for emoji.
    bool remapColors;

    // Passed through to the solid background color fragment shader.
    vector_int3 colorModelIndex;

    // What kind of underline to draw. The offset is provided in iTermTextureDimensions.
    iTermMetalGlyphAttributesUnderline underlineStyle;

    // Color for underline, if one is to be drawn
    vector_float4 underlineColor;
} iTermTextPIU;

typedef struct {
    // Offset from vertex in pixels.
    vector_float2 offset;

    // Offset of source texture
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
    vector_float2 cellSize;  // Size of a cell within the atlas in pixels
    float underlineOffset;  // Distance from bottom of cell to underline in pixels
    float underlineThickness;  // Thickness of underline in pixels
    float scale;  // 2 for retina, 1 for non retina
} iTermTextureDimensions;

typedef struct {
    // These do not need to be initialized by the data source.
    vector_float2 cellSize;
    vector_uint2 gridSize;
    float scale;
    vector_float2 atlasSize;

    // Everything below this line needs to be initialized by the data source.
    float minimumContrast;
    float dimmingAmount;
    float mutingAmount;
    bool reverseVideo;

    bool useBrightBold;

    float transparencyAlpha;
    bool transparencyAffectsOnlyDefaultBackgroundColor;
    vector_float4 unfocusedSelectionColor;  // see PTYTextView colorMap:didChangeColorForKey:
    bool isFrontTextView;
    bool dimOnlyText;
    vector_float4 asciiUnderlineColor;
    iTermThinStrokesSetting thinStrokesSetting;
} iTermASCIITextConfiguration;

typedef struct {
    char storage[1024];
    int offset;
    int capacity;
} iTermMetalDebugBuffer;

typedef struct {
    int row;
    int debugX;
} iTermASCIIRowInfo;

#endif
