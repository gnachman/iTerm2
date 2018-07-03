#import "iTermTextShaderCommon.h"

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
    out.colorModelIndex = perInstanceUniforms[iid].colorModelIndex;
    out.viewportSize = viewportSize;

    out.cellOffset = perInstanceUniforms[iid].offset.xy + offset[0];
    out.underlineStyle = perInstanceUniforms[iid].underlineStyle;
    out.underlineColor = static_cast<half4>(perInstanceUniforms[iid].underlineColor);

    return out;
}

// Fills in result with color of neighboring pixels in texture. Result must hold 8 half4's.
void SampleNeighbors(float2 textureSize,
                     float2 textureOffset,
                     float2 textureCoordinate,
                     float2 cellSize,
                     float scale,
                     texture2d<half> texture,
                     sampler textureSampler,
                     thread half4 *result) {
    const float2 pixel = (scale / 2) / textureSize;
    // I have to inset the limits by one pixel on the left and right. I guess
    // this is because clip space coordinates represent the center of a pixel,
    // so they are offset by a half pixel and will sample their neighbors. I'm
    // not 100% sure what's going on here, but it's definitely required.
    const float2 minTextureCoord = textureOffset + pixel;
    const float2 maxTextureCoord = minTextureCoord + (cellSize / textureSize) - (scale * pixel.x * 2);

    result[0] = texture.sample(textureSampler, clamp(textureCoordinate + float2(-pixel.x, -pixel.y), minTextureCoord, maxTextureCoord));
    result[1] = texture.sample(textureSampler, clamp(textureCoordinate + float2(       0, -pixel.y), minTextureCoord, maxTextureCoord));
    result[2] = texture.sample(textureSampler, clamp(textureCoordinate + float2( pixel.x, -pixel.y), minTextureCoord, maxTextureCoord));
    result[3] = texture.sample(textureSampler, clamp(textureCoordinate + float2(-pixel.x,        0), minTextureCoord, maxTextureCoord));
    result[4] = texture.sample(textureSampler, clamp(textureCoordinate + float2( pixel.x,        0), minTextureCoord, maxTextureCoord));
    result[5] = texture.sample(textureSampler, clamp(textureCoordinate + float2(-pixel.x,  pixel.y), minTextureCoord, maxTextureCoord));
    result[6] = texture.sample(textureSampler, clamp(textureCoordinate + float2(       0,  pixel.y), minTextureCoord, maxTextureCoord));
    result[7] = texture.sample(textureSampler, clamp(textureCoordinate + float2( pixel.x,  pixel.y), minTextureCoord, maxTextureCoord));
}

// Sample eight neigbors of textureCoordinate and returns a value with the minimum components from all of them.
half4 GetMinimumColorComponentsOfNeighbors(float2 textureSize,
                                           float2 textureOffset,
                                           float2 textureCoordinate,
                                           float2 cellSize,
                                           float scale,
                                           texture2d<half> texture,
                                           sampler textureSampler) {
    half4 neighbors[8];
    SampleNeighbors(textureSize,
                    textureOffset,
                    textureCoordinate,
                    cellSize,
                    scale,
                    texture,
                    textureSampler,
                    neighbors);

    const half4 mask = min(neighbors[0],
                           min(neighbors[1],
                               min(neighbors[2],
                                   min(neighbors[3],
                                       min(neighbors[4],
                                           min(neighbors[5],
                                               min(neighbors[6],
                                                   neighbors[7])))))));
    return mask;
}

// Sample eight neighbors of textureCoordinate and returns a value with the maximum components from all of them.
half4 GetMaximumColorComponentsOfNeighbors(float2 textureSize,
                                           float2 textureOffset,
                                           float2 textureCoordinate,
                                           float2 cellSize,
                                           float scale,
                                           texture2d<half> texture,
                                           sampler textureSampler) {
    half4 neighbors[8];
    SampleNeighbors(textureSize,
                    textureOffset,
                    textureCoordinate,
                    cellSize,
                    scale,
                    texture,
                    textureSampler,
                    neighbors);

    const half4 mask = max(neighbors[0],
                           max(neighbors[1],
                               max(neighbors[2],
                                   max(neighbors[3],
                                       max(neighbors[4],
                                           max(neighbors[5],
                                               max(neighbors[6],
                                                   neighbors[7])))))));
    return mask;
}

// Computes the fraction of a pixel in clipspace coordinates that intersects a range of scanlines.
float FractionOfPixelThatIntersectsUnderline(float2 clipSpacePosition,
                                             float2 viewportSize,
                                             float2 cellOffset,
                                             float underlineOffset,
                                             float underlineThickness) {
    // Flip the clipSpacePosition and shift it by half a pixel so it refers to the minimum coordinate
    // that contains this pixel with y=0 on the bottom. This only considers the vertical position
    // of the line.
    float originOnScreenInPixelSpace = viewportSize.y - (clipSpacePosition.y - 0.5);
    float originOfCellInPixelSpace = originOnScreenInPixelSpace - cellOffset.y;

    // Compute a value between 0 and 1 giving how much of the range [y, y+1) intersects
    // the range [underlineOffset, underlineOffset + underlineThickness].
    const float lowerBound = max(originOfCellInPixelSpace, underlineOffset);
    const float upperBound = min(originOfCellInPixelSpace + 1, underlineOffset + underlineThickness);
    const float intersection = max(0.0, upperBound - lowerBound);

    return intersection;
}

float FractionOfPixelThatIntersectsUnderlineForStyle(int underlineStyle,  // iTermMetalGlyphAttributesUnderline
                                                     float2 clipSpacePosition,
                                                     float2 viewportSize,
                                                     float2 cellOffset,
                                                     float underlineOffset,
                                                     float underlineThickness,
                                                     float scale) {
    if (underlineStyle == iTermMetalGlyphAttributesUnderlineDouble) {
        // We can't draw the underline lower than the bottom of the cell, so
        // move the lower underline down by one thickness, if possible, and
        // the second underline will draw above it. The same hack was added
        // to the non-metal code path so this isn't a glaring difference.
        underlineOffset = max(0.0, underlineOffset - underlineThickness);
    }
    float weight = FractionOfPixelThatIntersectsUnderline(clipSpacePosition,
                                                          viewportSize,
                                                          cellOffset,
                                                          underlineOffset,
                                                          underlineThickness);
    switch (static_cast<iTermMetalGlyphAttributesUnderline>(underlineStyle)) {
        case iTermMetalGlyphAttributesUnderlineNone:
        case iTermMetalGlyphAttributesUnderlineSingle:
            return weight;

        case iTermMetalGlyphAttributesUnderlineDouble:
            // Single & dashed
            if (weight > 0 && fmod(clipSpacePosition.x, 7 * scale) >= 4 * scale) {
                // Make a hole in the bottom underline
                return 0;
            } else if (weight == 0) {
                // Add a top underline if the y coordinate is right
                return FractionOfPixelThatIntersectsUnderline(clipSpacePosition,
                                                              viewportSize,
                                                              cellOffset,
                                                              underlineOffset + underlineThickness * 2,
                                                              underlineThickness);
            } else {
                // Visible part of dashed bottom underline
                return weight;
            }

        case iTermMetalGlyphAttributesUnderlineDashedSingle:
            if (weight > 0 && fmod(clipSpacePosition.x, 7 * scale) >= 4 * scale) {
                return 0;
            } else {
                return weight;
            }
    }

    // Shouldn't get here
    return weight;
}

float ComputeWeightOfUnderline(int underlineStyle,  // iTermMetalGlyphAttributesUnderline
                               float2 clipSpacePosition,
                               float2 viewportSize,
                               float2 cellOffset,
                               float underlineOffset,
                               float underlineThickness,
                               float2 textureSize,
                               float2 textureOffset,
                               float2 textureCoordinate,
                               float2 cellSize,
                               texture2d<half> texture,
                               sampler textureSampler,
                               float scale) {
    float weight = FractionOfPixelThatIntersectsUnderlineForStyle(underlineStyle,
                                                                  clipSpacePosition,
                                                                  viewportSize,
                                                                  cellOffset,
                                                                  underlineOffset,
                                                                  underlineThickness,
                                                                  scale);
    if (weight == 0) {
        return 0;
    }

    half4 mask = GetMinimumColorComponentsOfNeighbors(textureSize,
                                                      textureOffset,
                                                      textureCoordinate,
                                                      cellSize,
                                                      scale,
                                                      texture,
                                                      textureSampler);
    float opacity = (mask.x + mask.y + mask.z) / 3.0;
    if (scale > 1) {
        if (opacity >= 0.99) {
            return weight;
        } else {
            return 0;
        }
    } else {
        return weight * min(1.0, pow(opacity * 1.1, 10));
    }
}

float ComputeWeightOfUnderlineForEmoji(int underlineStyle,  // iTermMetalGlyphAttributesUnderline
                                       float2 clipSpacePosition,
                                       float2 viewportSize,
                                       float2 cellOffset,
                                       float underlineOffset,
                                       float underlineThickness,
                                       float2 textureSize,
                                       float2 textureOffset,
                                       float2 textureCoordinate,
                                       float2 cellSize,
                                       texture2d<half> texture,
                                       sampler textureSampler,
                                       float scale) {
    float weight = FractionOfPixelThatIntersectsUnderlineForStyle(underlineStyle,
                                                                  clipSpacePosition,
                                                                  viewportSize,
                                                                  cellOffset,
                                                                  underlineOffset,
                                                                  underlineThickness,
                                                                  scale);
    if (weight == 0) {
        return 0;
    }

    half maxAlpha = GetMaximumColorComponentsOfNeighbors(textureSize,
                                                         textureOffset,
                                                         textureCoordinate,
                                                         cellSize,
                                                         scale,
                                                         texture,
                                                         textureSampler).w;
    float opacity = 1 - maxAlpha;
    if (scale > 1) {
        if (opacity >= 0.99) {
            return weight;
        } else {
            return 0;
        }
    } else {
        return weight * min(1.0, pow(opacity * 1.1, 10));
    }
}

// For a discussion of this code, see this document:
// https://docs.google.com/document/d/1vfBq6vg409Zky-IQ7ne-Yy7olPtVCl0dq3PG20E8KDs
//
// This simply implements bilinear interpolation using the sampler. See
// iTermTextRenderer.mm for details on how the texture is structured.
static inline half4 RemapColor(float4 scaledTextColor,  // scaledTextColor is the text color multiplied by float4(17).
                               float4 backgroundColor_in,
                               float4 bwColor_in,
                               texture2d<half> models) {
    float4 bwColor = round(bwColor_in * 255) * 18 + 0.5;
    float4 backgroundColor = backgroundColor_in * 17 + 0.5;

    constexpr sampler s(coord::pixel,
                        filter::linear);
    half r = models.sample(s, float2(bwColor.x + scaledTextColor.x,
                                     backgroundColor.x)).x;
    half g = models.sample(s, float2(bwColor.y + scaledTextColor.y,
                                     backgroundColor.y)).x;
    half b = models.sample(s, float2(bwColor.z + scaledTextColor.z,
                                     backgroundColor.z)).x;
    return half4(r, g, b, 1);
}

// The underlining fragment shaders are separate from the non-underlining ones
// because of an apparent compiler bug. See issue 6779.

// "Blending" is slower but can deal with any combination of foreground/background
// color components. It's used when there's a background image, a badge,
// broadcast image stripes, or anything else nontrivial behind the text.
fragment half4
iTermTextFragmentShaderWithBlendingEmoji(iTermTextVertexFunctionOutput in [[stage_in]],
                                         texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                         texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                         texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                         constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    return texture.sample(textureSampler, in.textureCoordinate);
}

fragment half4
iTermTextFragmentShaderWithBlending(iTermTextVertexFunctionOutput in [[stage_in]],
                                    texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                    texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                    texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                    constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));

    // Not emoji, not underlined.
    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    return RemapColor(in.textColor * 17.0, backgroundColor, static_cast<float4>(bwColor), colorModels);
}

fragment half4
iTermTextFragmentShaderWithBlendingUnderlinedEmoji(iTermTextVertexFunctionOutput in [[stage_in]],
                                                   texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                                   texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                                   texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                                   constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    // Underlined emoji code path
    const half underlineWeight = ComputeWeightOfUnderlineForEmoji(in.underlineStyle,
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
    return mix(bwColor,
               in.underlineColor,
               underlineWeight);
}

fragment half4
iTermTextFragmentShaderWithBlendingUnderlined(iTermTextVertexFunctionOutput in [[stage_in]],
                                              texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                              texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                              texture2d<half> colorModels [[ texture(iTermTextureIndexSubpixelModels) ]],
                                              constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));

    // Underlined not emoji.
    const half underlineWeight = ComputeWeightOfUnderline(in.underlineStyle,
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
    if (underlineWeight == 0 && bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        discard_fragment();
    }

    half4 textColor = RemapColor(in.textColor * 17.0, backgroundColor, static_cast<float4>(bwColor), colorModels);
    return mix(textColor, in.underlineColor, underlineWeight);
}

