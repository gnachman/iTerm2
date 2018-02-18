#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"
#import "iTermTextShared.h"

typedef struct {
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureCoordinate;
    float2 backgroundTextureCoordinate;
    float4 textColor;
    float4 backgroundColor;
    float4 underlineColor;
    bool recolor;
    int3 colorModelIndex;
    float2 textureOffset;  // Normalized offset in texture.
    float2 cellOffset;  // Coordinate of bottom left of cell in pixel coordinates. 0,0 is the bottom left of the screen.
    int underlineStyle;  // should draw an underline? For some stupid reason the compiler won't let me set the type as iTermMetalGlyphAttributesUnderline
    float2 viewportSize;  // size of viewport in pixels. TODO: see if I can avoid passing this to fragment function.
    float scale;  // 2 for retina, 1 for non-retina
} iTermTextVertexFunctionOutput;

vertex iTermTextVertexFunctionOutput
iTermTextVertexShader(uint vertexID [[ vertex_id ]],
                      constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                      constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                      constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                      device iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                      unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutput out;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + perInstanceUniforms[iid].offset.xy + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;
    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;
    out.textureOffset = perInstanceUniforms[iid].textureOffset;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + perInstanceUniforms[iid].textureOffset;
    out.textColor = perInstanceUniforms[iid].textColor;
    out.backgroundColor = perInstanceUniforms[iid].backgroundColor;
    out.recolor = perInstanceUniforms[iid].remapColors;
    out.colorModelIndex = perInstanceUniforms[iid].colorModelIndex;
    out.viewportSize = viewportSize;

    out.cellOffset = perInstanceUniforms[iid].offset.xy + offset[0];
    out.underlineStyle = perInstanceUniforms[iid].underlineStyle;
    out.underlineColor = perInstanceUniforms[iid].underlineColor;

    return out;
}

// Used when there is no intermediate pass and we know text will always be
// rendered over a solid background color. This is much faster because the
// shader is quite simple. It uses 256 bytes of buffer for each combination of
// foreground/background color component.
fragment float4
iTermTextFragmentShaderSolidBackground(iTermTextVertexFunctionOutput in [[stage_in]],
                                       texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                       constant unsigned char *colorModels [[ buffer(iTermFragmentBufferIndexColorModels) ]],
                                       constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    if (!in.recolor) {
        // Emoji code path
        if (in.underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
            const float weight = ComputeWeightOfUnderlineForEmoji(in.underlineStyle,
                                                                  in.clipSpacePosition.xy,
                                                                  in.viewportSize,
                                                                  in.cellOffset,
                                                                  dimensions->underlineOffset,
                                                                  dimensions->underlineThickness,
                                                                  dimensions->textureSize,
                                                                  in.textureOffset,
                                                                  in.textureCoordinate,
                                                                  dimensions->cellSize,
                                                                  texture,
                                                                  textureSampler,
                                                                  dimensions->scale);
            return mix(static_cast<float4>(bwColor),
                       in.underlineColor,
                       weight);
        } else {
            return static_cast<float4>(bwColor);
        }
    } else if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        // Background shows through completely. Not emoji.
        if (in.underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
            const float weight = ComputeWeightOfUnderline(in.underlineStyle,
                                                          in.clipSpacePosition.xy,
                                                          in.viewportSize,
                                                          in.cellOffset,
                                                          dimensions->underlineOffset,
                                                          dimensions->underlineThickness,
                                                          dimensions->textureSize,
                                                          in.textureOffset,
                                                          in.textureCoordinate,
                                                          dimensions->cellSize,
                                                          texture,
                                                          textureSampler,
                                                          dimensions->scale);
            if (weight > 0) {
                return mix(in.backgroundColor,
                           in.underlineColor,
                           weight);
            } else {
                discard_fragment();
            }
        } else {
            discard_fragment();
        }
    }
    const short4 bwIntIndices = static_cast<short4>(bwColor * 255);

    // Base index for this color model
    const int3 i = in.colorModelIndex * 256;
    // Find RGB values to map colors in the black-on-white glyph to
    const uchar4 rgba = uchar4(colorModels[i.x + bwIntIndices.x],
                               colorModels[i.y + bwIntIndices.y],
                               colorModels[i.z + bwIntIndices.z],
                               255);
    return static_cast<float4>(rgba) / 255;
}

// This path is slow but can deal with any combination of foreground/background
// color components. It's used when there's a background image, a badge,
// broadcast image stripes, or anything else nontrivial behind the text.
fragment float4
iTermTextFragmentShaderWithBlending(iTermTextVertexFunctionOutput in [[stage_in]],
                                    texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                    texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                    constant unsigned char *colorModels [[ buffer(iTermFragmentBufferIndexColorModels) ]],
                                    constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));

    if (!in.recolor) {
        // Emoji code path
        if (in.underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
            const float weight = ComputeWeightOfUnderlineForEmoji(in.underlineStyle,
                                                                  in.clipSpacePosition.xy,
                                                                  in.viewportSize,
                                                                  in.cellOffset,
                                                                  dimensions->underlineOffset,
                                                                  dimensions->underlineThickness,
                                                                  dimensions->textureSize,
                                                                  in.textureOffset,
                                                                  in.textureCoordinate,
                                                                  dimensions->cellSize,
                                                                  texture,
                                                                  textureSampler,
                                                                  dimensions->scale);
            return mix(static_cast<float4>(bwColor),
                       in.underlineColor,
                       weight);
        } else {
            return static_cast<float4>(bwColor);
        }
    } else if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        // Background shows through completely. Not emoji.
        if (in.underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
            const float weight = ComputeWeightOfUnderline(in.underlineStyle,
                                                          in.clipSpacePosition.xy,
                                                          in.viewportSize,
                                                          in.cellOffset,
                                                          dimensions->underlineOffset,
                                                          dimensions->underlineThickness,
                                                          dimensions->textureSize,
                                                          in.textureOffset,
                                                          in.textureCoordinate,
                                                          dimensions->cellSize,
                                                          texture,
                                                          textureSampler,
                                                          dimensions->scale);
            if (weight > 0) {
                return mix(backgroundColor,
                           in.underlineColor,
                           weight);
            }
        }
        discard_fragment();
    }

    return RemapColor(in.textColor, backgroundColor, bwColor, colorModels);
}

