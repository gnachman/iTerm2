//
//  iTermTextShared.h
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

void SampleNeighbors(float2 textureSize,
                     float2 textureOffset,
                     float2 textureCoordinate,
                     float2 cellSize,
                     texture2d<half> texture,
                     sampler textureSampler,
                     thread half4 *result);

half ComputeWeightOfUnderline(int underlineStyle,  // iTermMetalGlyphAttributesUnderline
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
                               float scale);

half ComputeWeightOfUnderlineForEmoji(int underlineStyle,  // iTermMetalGlyphAttributesUnderline
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
                                       float scale);

// scaledTextColor is the text color multiplied by float4(17).
static inline half4 RemapColor(half4 scaledTextColor,
                               float4 backgroundColor_in,
                               half4 bwColor_in,
                               texture2d<half> models) {
    half4 bwColor = round(bwColor_in * 255) * 18 + 0.5;
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


