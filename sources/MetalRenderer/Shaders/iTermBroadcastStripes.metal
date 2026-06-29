#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermBroadcastStripesVertexFunctionOutput;

vertex iTermBroadcastStripesVertexFunctionOutput
iTermBroadcastStripesVertexShader(uint vertexID [[ vertex_id ]],
                                   constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                   constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermBroadcastStripesVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    const float2 coord = vertexArray[vertexID].textureCoordinate;
    out.textureCoordinate = float2(coord.x, coord.y);

    return out;
}

fragment float4
iTermBroadcastStripesFragmentShader(iTermBroadcastStripesVertexFunctionOutput in [[stage_in]],
                                     texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);
    return texture.sample(textureSampler, in.textureCoordinate);
}
