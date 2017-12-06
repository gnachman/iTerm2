#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"

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
                      constant iTermTextPIU *perInstanceUniforms [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
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

float4 RemapColor(float4 textColor,
                  float4 backgroundColor,
                  half4 bwColor,
                  constant unsigned char *colorModels) {
    // For a discussion of this code, see this document:
    // https://docs.google.com/document/d/1vfBq6vg409Zky-IQ7ne-Yy7olPtVCl0dq3PG20E8KDs

    // The formulas for bilinear interpolation came from:
    // https://en.wikipedia.org/wiki/Bilinear_interpolation
    //
    // The goal is to estimate the color of a pixel at P. We have to find the correct remapping
    // table for this cell's foreground/background color. The x axis is the text color and the
    // y axis is the background color.
    //
    // We'll find the four remapping tables that are closest to representing the text/background
    // color at this cell. We'll look up the black-and-white glyph's  color for this pixel in those
    // in those four remapping tables. Then we'll use bilinear interpolation to come up with an
    // estimate of what color to output.
    //
    // From a random sample of 1000 text/bg color combinations this gets within 2.3/255 of the
    // correct color in the worst case.
    //
    // TODO: Ask someone smart if there's a more efficient way to do this.
    //
    //    |   Q12             Q22
    // y2 |..*...............*...........
    //    |  :       :       :
    //    |  :       :P      :
    //  y |..........*...................
    //    |  :       :       :
    //    |  :       :       :
    //    |  :Q11    :       :Q21
    // y1 |..*...............*...........
    //    |  :       :       :
    //    |  :       :       :
    //    +---------------------------------
    //      x1       x       x2

    // Get text and background color in [0, 255]
    const float4 x = textColor * 255.0;
    const float4 y = backgroundColor * 255.0;

    // Indexes to upper and lower neighbors for x in [0, 17]
    const int4 x2i = min(17, static_cast<int4>(floor(x / 15.0)) + 1);  // This is at least 1
    const int4 x1i = x2i - 1;

    // Values of lower and upper neighbors for x in [0, 255]
    const float4 x1 = static_cast<float4>(x1i) * 15.0;
    const float4 x2 = static_cast<float4>(x2i) * 15.0;

    // Indexes to upper and lower neighbors for y in [0, 17]
    const int4 y2i = min(17, static_cast<int4>(floor(y / 15.0)) + 1);  // This is at least 1
    const int4 y1i = y2i - 1;

    // Values of lower and upper neighbors for y in [0, 255]
    const float4 y1 = static_cast<float4>(y1i) * 15.0;
    const float4 y2 = static_cast<float4>(y2i) * 15.0;

    // Index into tables (x,y,z ~ index for r,g,b)
    const int4 i = static_cast<int4>(round(bwColor * 255));

    // indexes to use to look up f(Q_y_x)
    // 18 is the multiplier because the color models are quantized to the color in [0,255] / 17.0 and
    // there's an off-by-one thing going on here.
    const int4 fq11i = 256 * (x1i * 18 + y1i) + i;
    const int4 fq12i = 256 * (x1i * 18 + y2i) + i;
    const int4 fq21i = 256 * (x2i * 18 + y1i) + i;
    const int4 fq22i = 256 * (x2i * 18 + y2i) + i;

    // Four neighbors' values in [0, 255]. The vectors' x,y,z correspond to red, green, and blue.
    const float4 fq11 = float4(colorModels[fq11i.x],
                               colorModels[fq11i.y],
                               colorModels[fq11i.z],
                               255);
    const float4 fq12 = float4(colorModels[fq12i.x],
                               colorModels[fq12i.y],
                               colorModels[fq12i.z],
                               255);
    const float4 fq21 = float4(colorModels[fq21i.x],
                               colorModels[fq21i.y],
                               colorModels[fq21i.z],
                               255);
    const float4 fq22 = float4(colorModels[fq22i.x],
                               colorModels[fq22i.y],
                               colorModels[fq22i.z],
                               255);

    // Do bilinear interpolation on the r, g, and b values simultaneously.
    const float4 x_alpha  = (x2 - x) / (x2 - x1);
    const float4 f_x_y1 = mix(fq21, fq11, x_alpha);
    const float4 f_x_y2 = mix(fq22, fq12, x_alpha);

    const float4 y_alpha = (y - y1) / (y2 - y1);
    const float4 f_x_y = mix(f_x_y2, f_x_y1, y_alpha);

    return float4(f_x_y.x,
                  f_x_y.y,
                  f_x_y.z,
                  255) / 255.0;
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

