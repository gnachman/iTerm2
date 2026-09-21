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
    iTermVertexColorArray,  // Points at per-quad vector_float4 color
    iTermVertexInputIndexBgColorChecksum,  // Issue 12791: iTermBgColorChecksumParams (expected FNV-1a hash of the 6-vertex quad)
    iTermVertexInputIndexBgColorVertexWitness,  // Issue 12791: device iTermBgColorVertexWitnessSlot[6], written by the vertex shader
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
    iTermFragmentBufferIndexScale = 7,  // backing scale factor float
    iTermFragmentBufferIndexBgColorChecksumReport = 9,  // Issue 12791: device atomic_uint
    iTermFragmentBufferIndexBgColorCoverageReport = 10,  // Issue 12791: device atomic_uint[2], per-triangle rasterized coverage
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
    iTermMetalGlyphAttributesUnderlineDotted = 6,
    iTermMetalGlyphAttributesUnderlineDashed = 7,

    iTermMetalGlyphAttributesUnderlineStrikethrough = iTermMetalGlyphAttributesUnderlineStrikethroughFlag,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndSingle = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 1,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndDouble = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 2,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndDashedSingle = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 3,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndCurly = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 4,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndDotted = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 6,
    iTermMetalGlyphAttributesUnderlineStrikethroughAndDashed = iTermMetalGlyphAttributesUnderlineStrikethroughFlag + 7,
} iTermMetalGlyphAttributesUnderline;

typedef enum {
    iTermBackgroundColorRendererModeAll = 0,
    iTermBackgroundColorRendererModeDefaultOnly = 1,
    iTermBackgroundColorRendererModeNondefaultOnly = 2
} iTermBackgroundColorRendererMode;

typedef struct {
    vector_float4 defaultBackgroundColor;  // Emulates the iTermBackgroundColorView.
    iTermBackgroundColorRendererMode mode;
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

    // Is default background color?
    unsigned char isDefault;
} iTermBackgroundColorPIU;

// Issue 12791: bg-color geometry checksum witness. The expected hash rides via
// setVertexBytes (inline command-buffer payload, not an MTLBuffer) so a stomp on the
// pooled unit-quad vertex buffer between CPU write and GPU read produces a mismatch.
// This witnesses the ONE input that can make one triangle of the merged default-
// background quad differ from the other: the per-vertex geometry (the PIU-derived
// color is uniform across all 6 vertices). expected==0 means "don't check this draw".
typedef struct {
    unsigned int expected;     // FNV-1a-32 of the count*4 floats of the vertex array (0 = skip)
    unsigned int vertexCount;  // number of iTermVertex to hash (normally 6)

    // Issue 12791: which instance of this draw the vertex shader should record into the
    // vertex witness buffer. The CPU picks the largest merged multi-row run (the quad the
    // diagonal tracks) so only one instance writes and the six slots describe one quad.
    // iTermBgColorNoVertexWitnessInstance means "this draw records nothing".
    unsigned int witnessInstance;
} iTermBgColorChecksumParams;

#define iTermBgColorNoVertexWitnessInstance 0xffffffffu

// Issue 12791: what the VERTEX stage actually saw, one slot per vertex of the witnessed
// quad. Vertex shading runs before clipping and rasterization, so a triangle that never
// produces a fragment still fills these in. Comparing them against the values the CPU
// believes it sent distinguishes "the GPU read different inputs than we wrote" from "the
// inputs were right and the triangle was dropped downstream". Writes are plain stores
// into a fixed slot rather than atomic accumulation because Apple GPUs may run a vertex
// function more than once for the same vertex; storing the same bytes twice is harmless.
typedef struct {
    vector_float2 vertexPosition;      // vertexArray[vertexID].position, the cell-sized unit quad
    vector_float2 pixelSpacePosition;  // after PIU stretch and offset
    vector_float2 clipSpacePosition;   // what the rasterizer receives
    vector_float2 viewportSize;        // the viewport the GPU divided by, not the one the CPU meant
    vector_float2 instanceOffset;      // perInstanceUniforms[iid].offset
    vector_float2 runLengthNumRows;    // perInstanceUniforms[iid].runLength, .numRows
    unsigned int instanceID;           // the iid that wrote this slot
    unsigned int written;              // 1 if the vertex stage reached this slot at all
} iTermBgColorVertexWitnessSlot;

typedef struct {
    vector_float4 color;
    vector_float4 defaultBackgroundColor;
    float yOffset;
} iTermMarginExtensionPIU;

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
    float cellWidth;
    unsigned int numInstances;
    float verticalOffset;  // For non-grid-aligned text, such as offscreen command line.
} iTermVertexTextInfoStruct;

typedef struct {
    vector_float4 color;
    float lineOffset;     // distance from cell bottom in pixels
    float lineThickness;  // in pixels
    int style;            // iTermMetalGlyphAttributesUnderline base style or strikethrough
    float scale;
} iTermUnderlineSpanInfo;

#endif
