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
    const float2 coord = vertexArray[vertexID].textureCoordinate;
    out.textureCoordinate = float2(coord.x, 1 - coord.y);

    return out;
}

// https://en.wikipedia.org/wiki/Alpha_compositing
// c_o = c_a + c_b(1 - ⍺_a)
// ⍺_o = ⍺_a + ⍺_b(1 - ⍺_a)
// Blends a OVER b.
static inline float4 blend(float4 a, float4 b) {
    return a + b * (1 - a.w);
}

fragment float4
iTermBackgroundImageClampFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                        texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                        constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    return blend(texture.sample(textureSampler, in.textureCoordinate), backgroundColor);
}

fragment float4
iTermBackgroundImageRepeatFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                         texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                         constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);
    
    return blend(texture.sample(textureSampler, in.textureCoordinate), backgroundColor);
}

fragment float4
iTermBackgroundImageWithAlphaClampFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                                 constant float *alpha [[ buffer(iTermFragmentInputIndexAlpha) ]],
                                                 texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                 constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    
    float4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    return blend(colorSample, backgroundColor) * *alpha;
}

fragment float4
iTermBackgroundImageWithAlphaRepeatFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                                  constant float *alpha [[ buffer(iTermFragmentInputIndexAlpha) ]],
                                                  texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                  constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);

    float4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    return blend(colorSample, backgroundColor) * *alpha;

}

fragment float4
iTermBackgroundImageLetterboxFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                            constant float4 &color [[ buffer(iTermFragmentInputIndexColor) ]]) {
    return color;
}
