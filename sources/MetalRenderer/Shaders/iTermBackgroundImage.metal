#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
    float isValid;  // Issue 12604: 1.0 = valid, 0.0 = invalid (interpolates across triangle)
} iTermBackgroundImageVertexFunctionOutput;

// Issue 12604/12791: FNV-1a-32 over the 24 uint32 words of the 6-vertex array.
// Must match the CPU-side implementation in iTermBackgroundImageRenderer.m.
static inline uint iTermBgImageVertexHash(constant iTermVertex *vertexArray) {
    uint hash = 2166136261u;
    for (uint i = 0; i < 6; i++) {
        uint words[4] = {
            as_type<uint>(vertexArray[i].position.x),
            as_type<uint>(vertexArray[i].position.y),
            as_type<uint>(vertexArray[i].textureCoordinate.x),
            as_type<uint>(vertexArray[i].textureCoordinate.y)
        };
        for (uint j = 0; j < 4; j++) {
            hash ^= words[j];
            hash *= 16777619u;
        }
    }
    // Match CPU-side: reserve 0 as a "skip check" sentinel.
    return hash == 0u ? 1u : hash;
}

vertex iTermBackgroundImageVertexFunctionOutput
iTermBackgroundImageVertexShader(uint vertexID [[ vertex_id ]],
                                 constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                 constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                                 constant uint *validationFlag [[ buffer(iTermVertexInputIndexValidationFlag) ]],
                                 constant uint *expectedChecksum [[ buffer(iTermVertexInputIndexBgImageChecksum) ]]) {
    iTermBackgroundImageVertexFunctionOutput out;

    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    const float2 coord = vertexArray[vertexID].textureCoordinate;
    out.textureCoordinate = float2(coord.x, 1 - coord.y);

    // Issue 12604: Validate the quad in the vertex shader
    float epsilon = 0.01;

    // Check shared vertices: v[0]==v[3] and v[2]==v[4]
    bool sharedMatch =
        (abs(vertexArray[0].position.x - vertexArray[3].position.x) < epsilon) &&
        (abs(vertexArray[0].position.y - vertexArray[3].position.y) < epsilon) &&
        (abs(vertexArray[2].position.x - vertexArray[4].position.x) < epsilon) &&
        (abs(vertexArray[2].position.y - vertexArray[4].position.y) < epsilon);

    // Check for NaN in current vertex
    bool noNaN = !isnan(pixelSpacePosition.x) && !isnan(pixelSpacePosition.y) &&
                 !isnan(coord.x) && !isnan(coord.y);

    // Check bounds
    float maxBound = max(viewportSize.x, viewportSize.y) * 3;
    bool inBounds = abs(pixelSpacePosition.x) < maxBound && abs(pixelSpacePosition.y) < maxBound;

    // Check CPU validation flag (bit 0 = 1 means CPU detected invalid)
    bool cpuValid = (*validationFlag & 1) == 0;

    // Issue 12604/12791: Independent checksum witness. The expected hash arrives via
    // setVertexBytes (inline command-buffer payload, not an MTLBuffer), so a stomp on
    // the vertex buffer's pool memory would produce a mismatch. Expected==0 is a
    // sentinel meaning "don't check this draw" (used for letterbox boxes). The
    // fragment shader is what actually writes to the device-side report buffer:
    // vertex shaders aren't allowed writable resources when they return a value.
    uint expected = *expectedChecksum;
    bool checksumMatch = true;
    if (expected != 0u) {
        uint computed = iTermBgImageVertexHash(vertexArray);
        checksumMatch = (computed == expected);
    }

    out.isValid = (sharedMatch && noNaN && inBounds && cpuValid && checksumMatch) ? 1.0 : 0.0;

    return out;
}

// https://en.wikipedia.org/wiki/Alpha_compositing
// c_o = c_a + c_b(1 - ⍺_a)
// ⍺_o = ⍺_a + ⍺_b(1 - ⍺_a)
// Blends a OVER b.
static inline float4 blend(float4 a, float4 b) {
    return a + b * (1 - a.w);
}

// Issue 12604/12791: Fragment shaders carry the device-writable report buffer so
// the vertex shader can stay a pure (return-value) function. When isValid < 0.5 we
// both paint red for visual confirmation AND atomically signal the CPU side via the
// report buffer (read in -[iTermBackgroundImageRendererTransientState didComplete]).
static inline void iTermBgImageReport(device atomic_uint *report) {
    atomic_fetch_or_explicit(report, 1u, memory_order_relaxed);
}

fragment float4
iTermBackgroundImageClampFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                        texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                        constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]],
                                        device atomic_uint *checksumReport [[ buffer(iTermFragmentBufferIndexBgImageChecksumReport) ]]) {
    // Issue 12604: Draw red if validation failed
    if (in.isValid < 0.5) {
        iTermBgImageReport(checksumReport);
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    return blend(texture.sample(textureSampler, in.textureCoordinate), backgroundColor);
}

fragment float4
iTermBackgroundImageRepeatFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                         texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                         constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]],
                                         device atomic_uint *checksumReport [[ buffer(iTermFragmentBufferIndexBgImageChecksumReport) ]]) {
    // Issue 12604: Draw red if validation failed
    if (in.isValid < 0.5) {
        iTermBgImageReport(checksumReport);
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);

    return blend(texture.sample(textureSampler, in.textureCoordinate), backgroundColor);
}

fragment float4
iTermBackgroundImageWithAlphaClampFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                                 constant float *alpha [[ buffer(iTermFragmentInputIndexAlpha) ]],
                                                 texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                 constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]],
                                                 device atomic_uint *checksumReport [[ buffer(iTermFragmentBufferIndexBgImageChecksumReport) ]]) {
    // Issue 12604: Draw red if validation failed
    if (in.isValid < 0.5) {
        iTermBgImageReport(checksumReport);
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    float4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    return blend(colorSample, backgroundColor) * *alpha;
}

fragment float4
iTermBackgroundImageWithAlphaRepeatFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                                  constant float *alpha [[ buffer(iTermFragmentInputIndexAlpha) ]],
                                                  texture2d<float> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                  constant float4 &backgroundColor [[ buffer(iTermFragmentInputIndexColor) ]],
                                                  device atomic_uint *checksumReport [[ buffer(iTermFragmentBufferIndexBgImageChecksumReport) ]]) {
    // Issue 12604: Draw red if validation failed
    if (in.isValid < 0.5) {
        iTermBgImageReport(checksumReport);
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::repeat);

    float4 colorSample = texture.sample(textureSampler, in.textureCoordinate);
    return blend(colorSample, backgroundColor) * *alpha;
}

fragment float4
iTermBackgroundImageLetterboxFragmentShader(iTermBackgroundImageVertexFunctionOutput in [[stage_in]],
                                            constant float4 &color [[ buffer(iTermFragmentInputIndexColor) ]],
                                            device atomic_uint *checksumReport [[ buffer(iTermFragmentBufferIndexBgImageChecksumReport) ]]) {
    // Issue 12604: Draw red if validation failed
    if (in.isValid < 0.5) {
        iTermBgImageReport(checksumReport);
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    return color;
}
