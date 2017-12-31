#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermFullScreenFlashVertexFunctionOutput;

vertex iTermFullScreenFlashVertexFunctionOutput
iTermFullScreenFlashVertexShader(uint vertexID [[ vertex_id ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermFullScreenFlashVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment float4
iTermFullScreenFlashFragmentShader(iTermFullScreenFlashVertexFunctionOutput in [[stage_in]],
                                   constant float4 *color [[ buffer(iTermFragmentBufferIndexFullScreenFlashColor) ]],
                                   texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    return *color;
}

