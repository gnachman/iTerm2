#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

// MARK: - Arrow Style

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;  // pixel coords
} iTermMarkVertexFunctionOutput;

vertex iTermMarkVertexFunctionOutput
iTermMarkVertexShader(uint vertexID [[ vertex_id ]],
                      constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                      constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                      constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                      device iTermMarkPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                      unsigned int iid [[instance_id]]) {
    iTermMarkVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;

    return out;
}

fragment float4
iTermMarkFragmentShader(iTermMarkVertexFunctionOutput in [[stage_in]],
                        texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     coord::pixel);

    return texture.sample(textureSampler, in.textureCoordinate);
}

// MARK: - Line Style

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
} iTermLineStyleMarkVertexFunctionOutput;

vertex iTermLineStyleMarkVertexFunctionOutput
iTermLineStyleMarkVertexShader(uint vertexID [[ vertex_id ]],
                      constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                      constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                      constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                      device iTermLineStyleMarkPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                      unsigned int iid [[instance_id]]) {
    iTermLineStyleMarkVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    if (pixelSpacePosition.x > 0) {
        pixelSpacePosition.x -= perInstanceUniforms[iid].rightInset;
    }
    pixelSpacePosition.y += perInstanceUniforms[iid].y;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.color = perInstanceUniforms[iid].color;

    return out;
}

fragment float4
iTermLineStyleMarkFragmentShader(iTermLineStyleMarkVertexFunctionOutput in [[stage_in]],
                                 texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    return in.color;
}
