//
//  iTermASCIIText.metal
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermShaderTypes.h"
#import "iTermTextShared.h"

typedef unsigned short unichar;

#include "iTermScreenChar.h"

typedef struct {
    bool discard;
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureOffset;  // Normalized offset in texture.
    float2 textureCoordinate;
    float2 backgroundTextureCoordinate;
    float4 textColor;
    float4 backgroundColor;
    float4 underlineColor;
    float2 cellOffset;  // Coordinate of bottom left of cell in pixel coordinates. 0,0 is the bottom left of the screen.
    int underlineStyle;  // should draw an underline? For some stupid reason the compiler won't let me set the type as iTermMetalGlyphAttributesUnderline
    float2 viewportSize;  // size of viewport in pixels. TODO: see if I can avoid passing this to fragment function.
    float scale;  // 2 for retina, 1 for non-retina
} iTermASCIITextVertexFunctionOutput;

float2 PixelSpaceOrigin(int x, int y, device iTermASCIITextConfiguration *config) {
    return float2(x,
                  config->gridSize.y - y - 1) * config->cellSize;
}

float2 NormalizedTextureOffset(unichar code, float2 cellSize, float2 atlasSize) {
    float2 normalizeCoefficient = cellSize / atlasSize;
    int stride = static_cast<int>(atlasSize.x) / static_cast<int>(cellSize.x);
    const int i = 1 + (code - 32) * 3;
    return float2(i % stride,
                  i / stride) * normalizeCoefficient;
}

float4 TextColor(device screen_char_t *c) {
    return float4(1, 1, 1, 1);
    // TODO
}

float4 BackgroundColor(device screen_char_t *c) {
    return float4(0, 0, 0, 1);
    // TODO
}

float4 UnderlineColor(device screen_char_t *c) {
    return float4(1, 0, 0, 1);
    // TODO
}

float2 CellOffset(int i, uint2 gridSize, float2 cellSize, float2 offset) {
    float2 coord = float2(i % gridSize.x,
                          gridSize.y - 1 - i / gridSize.y);
    return coord * cellSize + offset;
}

int UnderlineStyle(device screen_char_t *c, int x, device iTermASCIITextConfiguration *config) {
    return 0;
    // TODO
}

vertex iTermASCIITextVertexFunctionOutput
iTermASCIITextVertexShader(uint vertexID [[ vertex_id ]],
                           constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           device screen_char_t *line [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                           unsigned int x [[instance_id]],
                           device iTermASCIITextConfiguration *config [[ buffer(iTermVertexInputIndexASCIITextConfiguration) ]],
                           device iTermASCIIRowInfo *rowInfo [[ buffer(iTermVertexInputIndexASCIITextRowInfo) ]]) {
    iTermASCIITextVertexFunctionOutput out;
    if (line[x].complexChar ||
        line[x].image ||
        line[x].code < ' ' ||
        line[x].code > 126) {
        out.discard = true;
        return out;
    } else {
        out.discard = false;
    }

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + PixelSpaceOrigin(x, rowInfo->row, config) + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    out.textureOffset = NormalizedTextureOffset(line[x].code,
                                                config->cellSize,
                                                config->atlasSize);

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + out.textureOffset;

    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;

    out.backgroundColor = BackgroundColor(&line[x]);
    out.textColor = TextColor(&line[x]);
    out.underlineColor = UnderlineColor(&line[x]);

    out.cellOffset = CellOffset(x, config->gridSize, config->cellSize, *offset);
    out.underlineStyle = UnderlineStyle(&line[x], x, config);
    out.viewportSize = viewportSize;
    out.scale = config->scale;
    return out;
}

fragment float4
iTermASCIITextFragmentShader(iTermASCIITextVertexFunctionOutput in [[stage_in]],
                             texture2d<half> plainTexture [[ texture(iTermTextureIndexPlain) ]],
                             texture2d<half> boldTexture [[ texture(iTermTextureIndexBold) ]],
                             texture2d<half> italicTexture [[ texture(iTermTextureIndexItalic) ]],
                             texture2d<half> boldItalicTexture [[ texture(iTermTextureIndexBoldItalic) ]],
                             texture2d<half> thinTexture [[ texture(iTermTextureIndexThin) ]],
                             texture2d<half> thinBoldTexture [[ texture(iTermTextureIndexThinBold) ]],
                             texture2d<half> thinItalicTexture [[ texture(iTermTextureIndexThinItalic) ]],
                             texture2d<half> thinBoldItalicTexture [[ texture(iTermTextureIndexThinBoldItalic) ]],
                             texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                             constant unsigned char *colorModels [[ buffer(iTermFragmentBufferIndexColorModels) ]],
                             constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    if (in.discard) {
        discard_fragment();
        return float4(0, 0, 0, 0);
    }
    texture2d<half> &texture = plainTexture;
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);

    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);
    return static_cast<float4>(bwColor);

    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));

    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        // No text in this pixel
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
