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

float4 RemapColor(float4 textColor,
                  float4 backgroundColor,
                  half4 bwColor,
                  constant unsigned char *colorModels);
