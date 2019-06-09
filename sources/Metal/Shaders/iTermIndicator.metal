#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermIndicatorVertexFunctionOutput;

vertex iTermIndicatorVertexFunctionOutput
iTermIndicatorVertexShader(uint vertexID [[ vertex_id ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermIndicatorVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment float4
iTermIndicatorFragmentShader(iTermIndicatorVertexFunctionOutput in [[stage_in]],
                             constant float *alpha [[ buffer(iTermFragmentBufferIndexIndicatorAlpha) ]],
                             texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    colorSample.w *= *alpha;
    return float4(colorSample);
}

