//
//  iTermASCIIText.metal
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "iTermMetalLogging.h"
#import "iTermMetalScreenCharAccessors.h"
#import "iTermShaderTypes.h"
#import "iTermTextShared.h"
#import "iTermColorMapKey.h"
#import "iTermSharedColorImpl.h"

typedef struct {
    bool discard;
    float4 clipSpacePosition [[position]];  // In vector function is normalized. In fragment function is in pixels, with a half pixel offset since it refers to the center of the pixel.
    float2 textureOffset;  // Normalized offset in texture.
    float2 textureCoordinate;
    float2 backgroundTextureCoordinate;
    half4 scaledTextColor;
    float4 backgroundColor;
    half4 underlineColor;
    float2 cellOffset;  // Coordinate of bottom left of cell in pixel coordinates. 0,0 is the bottom left of the screen.
    int underlineStyle;  // should draw an underline? For some stupid reason the compiler won't let me set the type as iTermMetalGlyphAttributesUnderline
} iTermASCIITextVertexFunctionOutput;


float2 PixelSpaceOrigin(int x, int y, device iTermASCIITextConfiguration *config) {
    return float2(x,
                  config->gridSize.y - y - 1) * config->cellSize;
}

int CodeIndex(unichar code) {
    // Something spooky is going on. If I don't test code, it fails. The test doesn't matter, as
    // long as it isn't compiled out. This demands more investigation.
    if (code >= 32) {
        return 1 + (static_cast<int>(code) - 32) * 3;
    } else {
        return 0;
    }
}

float2 NormalizedTextureOffset(int i, float2 cellSize, float2 atlasSize) {
    float2 normalizeCoefficient = cellSize / atlasSize;
    int stride = static_cast<int>(atlasSize.x) / static_cast<int>(cellSize.x);
    return float2(i % stride,
                  i / stride) * normalizeCoefficient;
}

// i is CodeIndex(screen_char_t.code).
float2 CellOffset(int i, uint2 gridSize, float2 cellSize, float2 offset) {
    int width = gridSize.x + 1;
    float2 coord = float2(i % width,
                          gridSize.y - 1 - i / width);
    return coord * cellSize + offset;
}

vertex iTermASCIITextVertexFunctionOutput
iTermASCIITextVertexShader(uint vertexID [[ vertex_id ]],
                           constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           device screen_char_t *line [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                           unsigned int i [[instance_id]],
                           device iTermASCIITextConfiguration *config [[ buffer(iTermVertexInputIndexASCIITextConfiguration) ]],
                           device iTermCellColors *colors [[ buffer(iTermVertexInputCellColors) ]],
                           device int *mask [[ buffer(iTermVertexInputMask) ]]) {
    iTermASCIITextVertexFunctionOutput out;

    if (colors[i].nonascii) {
        out.discard = true;
        out.clipSpacePosition = float4(0, 0, 0, 0);
        return out;
    } else {
        out.discard = false;
    }

    if (*mask) {
        // want odds
        if ((i & 1) == 0) {
            out.discard = true;
            out.clipSpacePosition = float4(0, 0, 0, 0);
            return out;
        }
    } else {
        // want evens
        if ((i & 1) == 1) {
            out.discard = true;
            out.clipSpacePosition = float4(0, 0, 0, 0);
            return out;
        }
    }

    const int width = (config->gridSize.x + 1);  // includes eol marker
    const int x = i % width;
    const int y = i / width;

    // pixelSpacePosition is in pixels
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy + PixelSpaceOrigin(x, y, config) + offset[0];
    float2 viewportSize = float2(*viewportSizePointer);

    out.clipSpacePosition.xy = pixelSpacePosition / viewportSize;
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1;

    device screen_char_t *sct = SCIndex(line, i);
    const unichar code = SCCode(sct);

    const int style = (SCBold(sct) ? 1 : 0) | (SCItalic(sct) ? 2 : 0) | (colors[i].useThinStrokes ? 4 : 0);
    out.textureOffset = NormalizedTextureOffset(CodeIndex(code + style * iTermASCIITextureGlyphsPerStyle),
                                                config->cellSize,
                                                config->atlasSize);
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + out.textureOffset;

    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;

    out.backgroundColor = colors[i].backgroundColor;
    out.scaledTextColor = static_cast<half4>(colors[i].textColor * 17);
    out.underlineStyle = colors[i].underlineStyle;
    out.underlineColor = static_cast<half4>(colors[i].underlineColor);

    out.cellOffset = CellOffset(i, config->gridSize, config->cellSize, *offset);

    return out;
}

static bool
InCenterThird(float2 clipSpacePosition,
              float2 cellOffset,
              float2 cellSize) {
    float originOnScreenInPixelSpace = clipSpacePosition.x - 0.5;
    float originOfCellInPixelSpace = originOnScreenInPixelSpace - cellOffset.x;
    return (originOfCellInPixelSpace >= 0 && originOfCellInPixelSpace < cellSize.x);
}

fragment half4
iTermASCIITextFragmentShader(iTermASCIITextVertexFunctionOutput in [[stage_in]],
                             texture2d<half> glyphs [[ texture(iTermTextureIndexASCIICompositeGlpyhs) ]],
                             texture2d<half> drawable [[ texture(iTermTextureIndexBackground) ]],
                             texture2d<half> colorModelsTexture [[ texture(iTermTextureIndexColorModels) ]],
                             constant iTermTextureDimensions *dimensions  [[ buffer(iTermFragmentInputIndexTextureDimensions) ]]) {
    if (in.discard) {
        discard_fragment();
        return half4(0, 0, 0, 0);
    }
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    half4 bwColor = glyphs.sample(textureSampler, in.textureCoordinate);
    // TODO: Some fragments could avoid the expensive call to RemapColor and simply look up the
    // cell's background color in colorMap[offset + bwColor * 255] (where offset is the beginning
    // of the lookup table for the current text/bg color combination).
    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));
    if (bwColor.x == 1 && bwColor.y == 1 && bwColor.z == 1) {
        // No text in this pixel. But we might need to draw some background here.
        if (in.underlineStyle != iTermMetalGlyphAttributesUnderlineNone &&
            InCenterThird(in.clipSpacePosition.xy, in.cellOffset, dimensions->cellSize)) {
            const half weight = ComputeWeightOfUnderline(in.underlineStyle,
                                                          in.clipSpacePosition.xy,
                                                          static_cast<float2>(dimensions->viewportSize),
                                                          in.cellOffset,
                                                          dimensions->underlineOffset,
                                                          dimensions->underlineThickness,
                                                          dimensions->textureSize,
                                                          in.textureOffset,
                                                          in.textureCoordinate,
                                                          dimensions->cellSize,
                                                          glyphs,
                                                          textureSampler,
                                                          dimensions->scale);
            if (weight > 0) {
                return static_cast<half4>(mix(static_cast<half4>(backgroundColor),
                                              in.underlineColor,
                                              weight));
            }
        }
        discard_fragment();
        return half4(0, 0, 0, 0);
    } else {
        return RemapColor(in.scaledTextColor,
                          backgroundColor,
                          bwColor,
                          colorModelsTexture);
    }
}
