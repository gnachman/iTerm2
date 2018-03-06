//
//  iTermTextShared.metal
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

#include <metal_stdlib>
using namespace metal;
#import "iTermShaderTypes.h"
#import "iTermTextShared.h"

// Fills in result with color of neighboring pixels in texture. Result must hold 8 half4's.
void SampleNeighbors(float2 textureSize,
                     float2 textureOffset,
                     float2 textureCoordinate,
                     float2 cellSize,
                     texture2d<half> texture,
                     sampler textureSampler,
                     thread half4 *result) {
    const float2 pixel = 1.0 / textureSize;
    // I have to inset the limits by one pixel on the left and right. I guess
    // this is because clip space coordinates represent the center of a pixel,
    // so they are offset by a half pixel and will sample their neighbors. I'm
    // not 100% sure what's going on here, but it's definitely required.
    const float2 minTextureCoord = textureOffset + float2(pixel.x, 0);
    const float2 maxTextureCoord = minTextureCoord + (cellSize / textureSize) - float2(2 * pixel.x, 0);

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
                                           texture2d<half> texture,
                                           sampler textureSampler) {
    half4 neighbors[8];
    SampleNeighbors(textureSize,
                    textureOffset,
                    textureCoordinate,
                    cellSize,
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
                                           texture2d<half> texture,
                                           sampler textureSampler) {
    half4 neighbors[8];
    SampleNeighbors(textureSize,
                    textureOffset,
                    textureCoordinate,
                    cellSize,
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
        // the second underline will draw above it. This is different than
        // the non-metal codepath which will draw an underline lower than the
        // bottom of the cell. Double underlines are rare enough that I doubt
        // anyone will notice.
        underlineOffset = max(0.0, underlineOffset - underlineThickness);
    }
    float weight = FractionOfPixelThatIntersectsUnderline(clipSpacePosition,
                                                          viewportSize,
                                                          cellOffset,
                                                          underlineOffset,
                                                          underlineThickness);
    if (weight == 0 && underlineStyle == iTermMetalGlyphAttributesUnderlineDouble) {
        // Check if this pixel is in the second underline.
        weight = FractionOfPixelThatIntersectsUnderline(clipSpacePosition,
                                                        viewportSize,
                                                        cellOffset,
                                                        underlineOffset + underlineThickness * 2,
                                                        underlineThickness);
    } else if (weight > 0 &&
               underlineStyle == iTermMetalGlyphAttributesUnderlineDashedSingle &&
               fmod(clipSpacePosition.x - 0.5, 7 * scale) >= 4 * scale) {
        // 4 on 3 off. This is the off.
        return 0;
    }
    return weight;
}

// Returns the weight in [0, 1] of underline for a pixel at `clipSpacePosition`.
// This ignores the alpha channel of the texture and assumes white pixels are
// background.
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
                                                      texture,
                                                      textureSampler);
    if (mask.x + mask.y + mask.z >= 3) {
        return weight;
    } else {
        return 0;
    }
}

// Returns the weight in [0, 1] of underline for a pixel at `clipSpacePosition`
// when drawing underlined emoji. This respects the alpha channel of the texture.
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
                                                         texture,
                                                         textureSampler).w;
    if (maxAlpha == 0) {
        return weight;
    } else {
        return 0;
    }
}


