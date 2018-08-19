#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} iTermBackgroundImageVertexFunctionOutput;

vertex iTermBackgroundImageVertexFunctionOutput
iTermBackgroundImageVertexShader(uint vertexID [[ vertex_id ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    iTermBackgroundImageVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

fragment half4
iTermBackgroundImageClampFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                        texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    return texture.sample(textureSampler, in.textureCoordinate);
}

fragment half4
iTermBackgroundImageRepeatFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                         texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);
    
    return texture.sample(textureSampler, in.textureCoordinate);
}

fragment half4
iTermBackgroundImageWithAlphaClampFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                                 constant float *alpha [[ buffer(iTermFragmentInputIndexAlpha) ]],
                                                 texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    
    half4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    colorSample.w = static_cast<half>(*alpha);
    return colorSample;
}

fragment half4
iTermBackgroundImageWithAlphaRepeatFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                                  constant float *alpha [[ buffer(iTermFragmentInputIndexAlpha) ]],
                                                  texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);
    
    half4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    colorSample.w = static_cast<half>(*alpha);
    return colorSample;
}
