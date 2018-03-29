//
//  iTermCornerCutout.metal
//  iTerm2
//
//  Created by George Nachman on 11/19/17.
//

#include <metal_stdlib>
using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermCornerCutoutVertexFunctionOutput;

vertex iTermCornerCutoutVertexFunctionOutput
iTermCornerCutoutVertexShader(uint vertexID [[ vertex_id ]],
                              constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                              constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermCornerCutoutVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment half4
iTermCornerCutoutFragmentShader(iTermCornerCutoutVertexFunctionOutput in [[stage_in]],
                                texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    half4 sample = texture.sample(textureSampler, in.textureCoordinate);
    return sample.xxxx;
}
