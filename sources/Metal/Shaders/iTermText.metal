#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"
#import "iTermTextShared.h"

typedef struct {
    bool discard;
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureCoordinate;
    float2 backgroundTextureCoordinate;
    float4 scaledTextColor;
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
                      device iTermCellColors *cellColors [[ buffer(iTermVertexInputCellColors) ]],
                      unsigned int iid [[instance_id]]) {
    iTermTextVertexFunctionOutput out;
    const int i = perInstanceUniforms[iid].cellIndex;
    out.discard = cellColors[i].useThinStrokes != perInstanceUniforms[iid].thinStrokes;
    if (out.discard) {
        return out;
    }

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
    out.recolor = perInstanceUniforms[iid].remapColors;
    out.viewportSize = viewportSize;

    out.cellOffset = perInstanceUniforms[iid].offset.xy + offset[0];

    out.scaledTextColor = cellColors[i].textColor * 17;
    out.backgroundColor = cellColors[i].backgroundColor;
    out.underlineColor = cellColors[i].underlineColor;
    out.underlineStyle = cellColors[i].underlineStyle;

    return out;
}

// This path is slow but can deal with any combination of foreground/background
// color components. It's used when there's a background image, a badge,
// broadcast image stripes, or anything else nontrivial behind the text.
fragment half4
iTermTextFragmentShaderWithBlending(iTermTextVertexFunctionOutput in [[stage_in]],
                                    texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                    texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                    texture2d<half> colorModelsTexture [[ texture(iTermTextureIndexColorModels) ]],
                                    constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    if (in.discard) {
        discard_fragment();
        return half4(0, 0, 0, 0);
    }
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
            return static_cast<half4>(mix(static_cast<float4>(bwColor),
                                          in.underlineColor,
                                          weight));
        } else {
            return bwColor;
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
                return static_cast<half4>(mix(backgroundColor,
                                              in.underlineColor,
                                              weight));
            }
        }
        discard_fragment();
    }

    return RemapColor(in.scaledTextColor, backgroundColor, bwColor, colorModelsTexture);
}

