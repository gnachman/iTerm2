//
//  UnderlineComposite.metal
//  iTerm2
//
//  Composites text (T) and underline (U) offscreen textures.
//  Text and underlines are rendered to separate textures so this shader can
//  subtract a smeared (dilated) version of the text silhouette from the
//  underlines, creating breaks where descenders would intersect.
//

#include <metal_stdlib>
using namespace metal;
#import "iTermShaderTypes.h"

struct UnderlineCompositeVertexOutput {
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex UnderlineCompositeVertexOutput
iTermUnderlineCompositeVertexShader(uint vertexID [[ vertex_id ]],
                                    constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                                    constant vector_uint2 *viewportSizePointer [[ buffer(iTermVertexInputIndexViewportSize) ]]) {
    UnderlineCompositeVertexOutput out;
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    out.position.xy = pixelSpacePosition / viewportSize;
    out.position.z = 0.0;
    out.position.w = 1;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

// Composite underlines behind text with descender-break smearing.
//
// The smear pattern matches iTermTextDrawingHelper.m:2183-2193:
//   radius = 1
//   X offsets: -1, -0.5, 0, 0.5, 1  (5 steps)
//   Y offsets: -1, 0, 1              (3 steps)
//   Total: 15 samples
//
// Where smeared text is detected, the underline is suppressed. This creates
// visual breaks in the underline around descenders (g, p, y, etc.).
fragment float4
iTermUnderlineCompositeFragmentShader(UnderlineCompositeVertexOutput in [[stage_in]],
                                      texture2d<float> textTexture [[texture(0)]],
                                      texture2d<float> underlineTexture [[texture(1)]],
                                      constant float *scalePtr [[buffer(0)]],
                                      constant int *solidModePtr [[buffer(1)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);

    float4 u = underlineTexture.sample(s, in.textureCoordinate);
    float4 t = textTexture.sample(s, in.textureCoordinate);

    // Early out: if no underline at this pixel, just return text.
    if (u.a <= 0) {
        return t;
    }

    if (!(*solidModePtr)) {
        // Smear: sample text in a 15-point neighborhood and take max alpha.
        // Pixel size in texture coordinates.
        const float scale = *scalePtr;
        float2 pixelSize = scale / float2(textTexture.get_width(), textTexture.get_height());

        float maxAlpha = 0;
        for (int xi = -2; xi <= 2; xi++) {       // -1.0, -0.5, 0.0, 0.5, 1.0
            float dx = float(xi) * 0.5 * pixelSize.x;
            for (int yi = -1; yi <= 1; yi++) {   // -1, 0, 1
                float dy = float(yi) * pixelSize.y;
                float4 sample = textTexture.sample(s, in.textureCoordinate + float2(dx, dy));
                maxAlpha = max(maxAlpha, sample.a);
            }
        }

        // Subtract smeared text from underline.
        u = u * (1.0 - maxAlpha);
    }

    // Premultiplied source-over: text on top of (masked) underline.
    float4 result = t + u * (1.0 - t.a);
    return result;
}
