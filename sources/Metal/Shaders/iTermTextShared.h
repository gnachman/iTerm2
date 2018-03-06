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
                               float scale);

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
                                       float scale);

static inline float4 RemapColor(float4 textColor_in,
                                float4 backgroundColor_in,
                                half4 bwColor_in,
                                texture2d<half> models) {
    half4 bwColor = round(bwColor_in * 255) * 18 + 0.5;
    float4 textColor = textColor_in * 17;
    float4 backgroundColor = backgroundColor_in * 17 + 0.5;

    constexpr sampler s(coord::pixel,
                        filter::linear);
    half r = models.sample(s, float2(bwColor.x + textColor.x,
                                     backgroundColor.x)).x;
    half g = models.sample(s, float2(bwColor.y + textColor.y,
                                     backgroundColor.y)).x;
    half b = models.sample(s, float2(bwColor.z + textColor.z,
                                     backgroundColor.z)).x;
    return float4(r, g, b, 1);
}


