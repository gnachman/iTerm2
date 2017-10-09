#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

#pragma mark - Solid color cursor

typedef struct {
    float4 clipSpacePosition [[position]];
    float4 color;
} iTermCursorVertexFunctionOutput;

vertex iTermCursorVertexFunctionOutput
iTermCursorVertexShader(uint vertexID [[ vertex_id ]],
                                 constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                 constant iTermCursorDescription *description [[ buffer(iTermVertexInputIndexCursorDescription) ]]) {
    iTermCursorVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + description->origin + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.color = description->color;

    return out;
}

fragment float4
iTermCursorFragmentShader(iTermCursorVertexFunctionOutput in [[stage_in]]) {
    return in.color;
}

#pragma mark - Texture-based cursor

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermTextureCursorVertexFunctionOutput;

vertex iTermTextureCursorVertexFunctionOutput
iTermTextureCursorVertexShader(uint vertexID [[ vertex_id ]],
                        constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                        constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                        constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                        constant iTermCursorDescription *description [[ buffer(iTermVertexInputIndexCursorDescription) ]]) {
    iTermTextureCursorVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + description->origin + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment float4
iTermTextureCursorFragmentShader(iTermTextureCursorVertexFunctionOutput in [[stage_in]],
                                   texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    const half4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    return float4(colorSample);
}
