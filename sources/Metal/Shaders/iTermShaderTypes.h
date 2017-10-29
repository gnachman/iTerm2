#ifndef ITERM_
#define ShaderTypes_h

#include <simd/simd.h>

typedef enum iTermVertexInputIndex {
    iTermVertexInputIndexVertices,
    iTermVertexInputIndexViewportSize,
    iTermVertexInputIndexPerInstanceUniforms,
    iTermVertexInputIndexOffset,
    iTermVertexInputIndexCursorDescription,
} iTermVertexInputIndex;

typedef enum iTermTextureIndex {
    iTermTextureIndexPrimary = 0,

    // A texture containing the background we're drawing over.
    iTermTextureIndexBackground = 1
} iTermTextureIndex;

typedef enum {
    iTermFragmentBufferIndexColorModels = 1 // Array of 256-byte color tables
} iTermFragmentBufferIndex;

typedef struct {
    // Distance in pixel space from origin
    vector_float2 position;

    // Distance in texture space from origin
    vector_float2 textureCoordinate;
} iTermVertex;

typedef struct {
    // Offset from vertex
    vector_float2 offset;

    // Offset of source texture
    vector_float2 textureOffset;

    // Values in 0-1. These will be composited over what's already rendered.
    vector_float4 backgroundColor;
    vector_float4 textColor;
} iTermTextPIU;

typedef struct {
    // Offset from vertex
    vector_float2 offset;

    // Offset of source texture
    vector_float2 textureOffset;
} iTermMarkPIU;

typedef struct {
    // Offset from vertex
    vector_float2 offset;

    // Background color
    vector_float4 color;
} iTermBackgroundColorPIU;

typedef struct {
    // Offset from vertex
    vector_float2 offset;
} iTermCursorGuidePIU;

typedef struct {
    vector_float4 color;
    vector_float2 origin;
} iTermCursorDescription;

#endif
