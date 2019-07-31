//
//  iTermUnusedText.metal
//  iTerm2
//
//  Created by George Nachman on 7/2/18.
//

#include "iTermTextShaderCommon.h"

// Return colored sample from texture plus underline
fragment half4
iTermTextFragmentShaderMonochromeUnderlined(iTermTextVertexFunctionOutput in [[stage_in]],
                                            texture2d<half> texture [[ texture(iTermTextureIndexPrimary) ]],
                                            texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                                            constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 textureColor = texture.sample(textureSampler, in.textureCoordinate);

    half strikethroughWeight = 0;
    if (in.underlineStyle & iTermMetalGlyphAttributesUnderlineStrikethroughFlag) {
        strikethroughWeight = ComputeWeightOfUnderlineRegular(iTermMetalGlyphAttributesUnderlineStrikethrough,
                                                              in.clipSpacePosition.xy,
                                                              in.viewportSize,
                                                              in.cellOffset,
                                                              dimensions->strikethroughOffset,
                                                              dimensions->strikethroughThickness,
                                                              dimensions->textureSize,
                                                              in.textureOffset,
                                                              in.textureCoordinate,
                                                              dimensions->glyphSize,
                                                              dimensions->cellSize,
                                                              texture,
                                                              textureSampler,
                                                              dimensions->scale);
    }
    // Underlined not emoji.
    const half underlineWeight = ComputeWeightOfUnderlineRegular((in.underlineStyle & iTermMetalGlyphAttributesUnderlineBitmask),
                                                                 in.clipSpacePosition.xy,
                                                                 in.viewportSize,
                                                                 in.cellOffset,
                                                                 dimensions->underlineOffset,
                                                                 dimensions->underlineThickness,
                                                                 dimensions->textureSize,
                                                                 in.textureOffset,
                                                                 in.textureCoordinate,
                                                                 dimensions->glyphSize,
                                                                 dimensions->cellSize,
                                                                 texture,
                                                                 textureSampler,
                                                                 dimensions->scale);

    half4 recoloredTextColor = static_cast<half4>(in.textColor);
    recoloredTextColor.w = dot(textureColor, in.alphaVector);

    // I could eke out a little speed by passing a half4 from the vector shader but this is so slow I'd rather not add the complexity.
    half4 result = mix(recoloredTextColor,
                       in.underlineColor,
                       max(strikethroughWeight, underlineWeight));
    result.xyz *= result.w;
    return result;
}
