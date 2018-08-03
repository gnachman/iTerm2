#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermCopyBackgroundVertexFunctionOutput;

vertex iTermCopyBackgroundVertexFunctionOutput
iTermCopyBackgroundVertexShader(uint vertexID [[ vertex_id ]],
                                constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermCopyBackgroundVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment half4
iTermCopyBackgroundFragmentShader(iTermCopyBackgroundVertexFunctionOutput in [[stage_in]],
                                  texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    return texture.sample(textureSampler, in.textureCoordinate);
}

