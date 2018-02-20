//
//  iTermASCIIText.metal
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;
typedef unsigned short unichar;

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
    float4 textColor;
    float4 backgroundColor;
    float4 underlineColor;
    float2 cellOffset;  // Coordinate of bottom left of cell in pixel coordinates. 0,0 is the bottom left of the screen.
    int underlineStyle;  // should draw an underline? For some stupid reason the compiler won't let me set the type as iTermMetalGlyphAttributesUnderline
    float2 viewportSize;  // size of viewport in pixels. TODO: see if I can avoid passing this to fragment function.
    float scale;  // 2 for retina, 1 for non-retina
    bool bold;
    bool italic;
    bool thin;
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

float2 CellOffset(int i, uint2 gridSize, float2 cellSize, float2 offset) {
    float2 coord = float2(i % gridSize.x,
                          gridSize.y - 1 - i / gridSize.y);
    return coord * cellSize + offset;
}

vertex iTermASCIITextVertexFunctionOutput
iTermASCIITextVertexShader(uint vertexID [[ vertex_id ]],
                           constant float2 *offset [[ buffer(iTermVertexInputIndexOffset) ]],
                           constant iTermVertex *vertexArray [[ buffer(iTermVertexInputIndexVertices) ]],
                           constant vector_uint2 *viewportSizePointer  [[ buffer(iTermVertexInputIndexViewportSize) ]],
                           device screen_char_t *line [[ buffer(iTermVertexInputIndexPerInstanceUniforms) ]],
                           unsigned int x [[instance_id]],
                           device iTermASCIITextConfiguration *config [[ buffer(iTermVertexInputIndexASCIITextConfiguration) ]],
                           device iTermASCIIRowInfo *rowInfo [[ buffer(iTermVertexInputIndexASCIITextRowInfo) ]],
                           device unsigned char *colorMap [[ buffer(iTermVertexInputIndexColorMap) ]],
                           device unsigned char *selectedIndices [[ buffer(iTermVertexInputSelectedIndices) ]],
                           device unsigned char *findMatchIndices [[ buffer(iTermVertexInputFindMatchIndices) ]],
                           device unsigned char *annotatedIndices [[ buffer(iTermVertexInputAnnotatedIndices) ]],
                           device unsigned char *markedIndices [[ buffer(iTermVertexInputMarkedIndices) ]],
                           device unsigned char *underlinedIndices [[ buffer(iTermVertexInputUnderlinedIndices) ]],
                           device iTermMetalDebugBuffer *debugBuffer [[ buffer(iTermVertexInputDebugBuffer) ]]) {
    iTermASCIITextVertexFunctionOutput out;
    if (SCComplex(&line[x]) ||
        SCImage(&line[x]) ||
        SCCode(&line[x]) < ' ' ||
        SCCode(&line[x]) > 126) {
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

    out.textureOffset = NormalizedTextureOffset(SCCode(&line[x]),
                                                config->cellSize,
                                                config->atlasSize);

    out.textureCoordinate = vertexArray[vertexID].textureCoordinate + out.textureOffset;

    out.backgroundTextureCoordinate = pixelSpacePosition / viewportSize;
    out.backgroundTextureCoordinate.y = 1 - out.backgroundTextureCoordinate.y;

    const int mask = 1 << (x & 7);
    const bool selected = !!(selectedIndices[x / 8] & mask);
    const bool findMatch = !!(findMatchIndices[x / 8] & mask);
    const bool annotated = !!(annotatedIndices[x / 8] & mask);
    const bool marked = !!(markedIndices[x / 8] & mask);
    const bool inUnderlinedRange = !!(underlinedIndices[x / 8] & mask);

    out.backgroundColor = BackgroundColor(&line[x],
                                          config->transparencyAlpha,
                                          config->transparencyAffectsOnlyDefaultBackgroundColor,
                                          config->reverseVideo,
                                          config->useBrightBold,
                                          config->isFrontTextView,
                                          config->mutingAmount,
                                          config->dimOnlyText,
                                          config->dimmingAmount,
                                          config->hasBackgroundImage,
                                          config->unfocusedSelectionColor,
                                          colorMap,
                                          selected,
                                          findMatch);
    out.textColor = TextColor(&line[x],
                              config->minimumContrast,
                              config->dimmingAmount,
                              config->mutingAmount,
                              config->dimOnlyText,
                              config->reverseVideo,
                              config->useBrightBold,
                              colorMap,
                              out.backgroundColor,
                              selected,
                              findMatch,
                              inUnderlinedRange && !annotated);
    out.underlineStyle = UnderlineStyle(&line[x], annotated, inUnderlinedRange);
    if (out.underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
        out.underlineColor = UnderlineColor(config->asciiUnderlineColor,
                                            out.textColor,
                                            annotated,
                                            marked);
    }
    out.cellOffset = CellOffset(x, config->gridSize, config->cellSize, *offset);
    out.viewportSize = viewportSize;
    out.scale = config->scale;

    out.bold = SCBold(&line[x]);
    out.thin = UseThinStrokes(config->thinStrokesSetting,
                              config->scale > 1,
                              out.backgroundColor,
                              out.textColor);
    out.italic = SCItalic(&line[x]);

    return out;
}

texture2d<half> GetTexture(bool bold,
                           bool italic,
                           bool thin,
                           texture2d<half> plainTexture,
                           texture2d<half> boldTexture,
                           texture2d<half> italicTexture,
                           texture2d<half> boldItalicTexture,
                           texture2d<half> thinTexture,
                           texture2d<half> thinBoldTexture,
                           texture2d<half> thinItalicTexture,
                           texture2d<half> thinBoldItalicTexture) {
    if (bold) {
        if (italic) {
            if (thin) {
                return thinBoldItalicTexture;
            } else {
                return boldItalicTexture;
            }
        } else {
            if (thin) {
                return thinBoldTexture;
            } else {
                return boldTexture;
            }
        }
    } else {
        if (italic) {
            if (thin) {
                return thinItalicTexture;
            } else {
                return italicTexture;
            }
        } else {
            if (thin) {
                return thinTexture;
            } else {
                return plainTexture;
            }
        }
    }
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
    }
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear);
    texture2d<half> texture = GetTexture(in.bold,
                                         in.italic,
                                         in.thin,
                                         plainTexture,
                                         boldTexture,
                                         italicTexture,
                                         boldItalicTexture,
                                         thinTexture,
                                         thinBoldTexture,
                                         thinItalicTexture,
                                         thinBoldItalicTexture);
    half4 bwColor = texture.sample(textureSampler, in.textureCoordinate);

    // TODO: You can't always sample the drawable
//    const float4 backgroundColor = static_cast<float4>(drawable.sample(textureSampler, in.backgroundTextureCoordinate));
#warning TODO: Support sampling from drawable when needed
    const float4 backgroundColor = in.backgroundColor;

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
        return float4(0, 0, 0, 0);
    } else {
        return RemapColor(in.textColor, backgroundColor, bwColor, colorModels);
    }
}
