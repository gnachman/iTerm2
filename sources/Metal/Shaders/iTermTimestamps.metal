#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermTimestampsVertexFunctionOutput;

vertex iTermTimestampsVertexFunctionOutput
iTermTimestampsVertexShader(uint vertexID [[ vertex_id ]],
                            constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                            constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermTimestampsVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment float4
iTermTimestampsFragmentShader(iTermTimestampsVertexFunctionOutput in [[stage_in]],
                              texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    colorSample.xyz *= colorSample.w;
    return float4(colorSample);
}

