#ifndef ITERM_
#define ShaderTypes_h

#include <simd/simd.h>
#import "iTermThinStrokes.h"

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#else
#import <Foundation/Foundation.h>
#endif

typedef enum iTermVertexInputIndex {
    iTermVertexInputIndexVertices = 0,
    iTermVertexInputIndexViewportSize = 1,
    iTermVertexInputIndexPerInstanceUniforms = 2,
    iTermVertexInputIndexOffset = 3,
    iTermVertexInputIndexCursorDescription = 4,
    iTermVertexInputIndexASCIITextConfiguration = 5,  // iTermASCIITextConfiguration
    iTermVertexInputIndexASCIITextRowInfo = 6,  // iTermASCIIRowInfo
    iTermVertexInputIndexColorMap = 7,  // data with serialized iTermColorMap
    iTermVertexInputSelectedIndices = 8,  // data is an array of bits giving selected indices
    iTermVertexInputFindMatchIndices = 9,  // data is an array of bits giving find-match indices to highlight
    iTermVertexInputMarkedIndices = 10,  // data is an array of bits giving marked text locations
    iTermVertexInputUnderlinedIndices = 11,  // data is an array of bits giving underlined range locations
    iTermVertexInputAnnotatedIndices = 12,  // data in array of bits giving annotation locations
    iTermVertexInputDebugBuffer = 13,  // iTermMetalDebugBuffer
    iTermVertexInputCellColors = 14,  // iTermCellColors
    iTermVertexInputBackgroundColorConfiguration = 15,  // iTermBackgroundColorConfiguration
    iTermVertexInputMask = 16,  // int (0=evens, 1=odds)
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

typedef NS_ENUM(int, iTermComputeIndex) {
    iTermComputeIndexScreenChars = 0,  // screen_char_t *
    iTermComputeIndexColors = 1,  // iTermCellColors *
    iTermComputeIndexColorsConfig = 2,  // iTermColorsConfig
};

typedef NS_ENUM(int, iTermFragmentBufferIndex) {
    iTermFragmentBufferIndexMarginColor = 0,  // Points at a single float4
    iTermFragmentBufferIndexColorModels = 1, // Array of 256-byte color tables
    iTermFragmentInputIndexTextureDimensions = 2,  // Points at iTermTextureDimensions
    iTermFragmentBufferIndexIndicatorAlpha = 3, // Points at a single float giving alpha value
    iTermFragmentBufferIndexFullScreenFlashColor = 4, // Points at a float4
};

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

    // Index into colors array
    int cellIndex;

    // This is true for text and false for emoji.
    bool remapColors;

    bool thinStrokes;
} iTermTextPIU;

typedef struct {
    // Offset from vertex in pixels.
    vector_float2 offset;

    // Offset of source texture
    vector_float2 textureOffset;
} iTermMarkPIU;

typedef struct {
    // Offset from vertex
    vector_float2 cellSize;
    vector_uint2 gridSize;
} iTermBackgroundColorConfiguration;

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
    vector_uint2 gridSize;  // Does not include EOL marker
    float scale;
    float minimumContrast;
    float dimmingAmount;
    float mutingAmount;
    bool reverseVideo;
    bool useBrightBold;
    float blend;
    float transparencyAlpha;
    bool transparencyAffectsOnlyDefaultBackgroundColor;
    vector_float4 unfocusedSelectionColor;  // see PTYTextView colorMap:didChangeColorForKey:
    bool isFrontTextView;
    bool dimOnlyText;
#warning TODO: This should also handle non-ascii
    vector_float4 asciiUnderlineColor;
    iTermThinStrokesSetting thinStrokesSetting;
    bool hasBackgroundImage;
} iTermColorsConfiguration;

typedef struct {
    vector_uint2 gridSize;  // does not include EOL marker
    vector_float2 cellSize;
    float scale;
    vector_float2 atlasSize;
} iTermASCIITextConfiguration;

#define METAL_DEBUG_BUFFER_SIZE 10240
typedef struct {
    char storage[METAL_DEBUG_BUFFER_SIZE];
    int offset;
    int capacity;
} iTermMetalDebugBuffer;

typedef struct {
    int row;
    int debugX;
} iTermASCIIRowInfo;

#define ENABLE_DEBUG_COLOR_COMPUTER 0

typedef struct {
#if ENABLE_DEBUG_COLOR_COMPUTER
    // for debugging only
    vector_uint2 coord;
    int index;
#endif

    bool nonascii;
    vector_float4 textColor;
    vector_float4 backgroundColor;
    vector_float4 underlineColor;
    iTermMetalGlyphAttributesUnderline underlineStyle;
    bool useThinStrokes;
} iTermCellColors;

#endif
