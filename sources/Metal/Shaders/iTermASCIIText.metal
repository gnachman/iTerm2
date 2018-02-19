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
#import "iTermShaderTypes.h"
#import "iTermTextShared.h"
#import "iTermColorMapKey.h"
#import "iTermScreenChar.h"

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

unichar SCCode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return (p[1] << 8) | p[0];
}

unsigned int SCForegroundColor(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[2];
}

unsigned int SCForegroundGreen(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[3];
}

unsigned int SCForegroundBlue(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[4];
}

unsigned int SCBackgroundColor(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[5];
}

unsigned int SCBackgroundGreen(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[6];
}

unsigned int SCBackgroundBlue(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return p[7];
}

ColorMode SCForegroundMode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return static_cast<ColorMode>(p[8] & 3);
}

ColorMode SCBackgroundMode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return static_cast<ColorMode>((p[8] >> 2) & 3);
}

bool SCComplex(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 16);
}

bool SCBold(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 32);
}

bool SCFaint(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 64);
}

bool SCItalic(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[8] & 128);
}

bool SCBlink(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[9] & 1);
}

bool SCUnderline(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[9] & 2);
}

bool SCImage(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return !!(p[9] & 4);
}

unsigned short SCURLCode(device screen_char_t *c) {
    device unsigned char *p = (device unsigned char *)c;
    return (p[11] << 8) | p[10];
}

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

iTermColorMapKey TrueColorKey(int red, int green, int blue) {
    return static_cast<iTermColorMapKey>(kColorMap24bitBase + ((red & 0xff) << 16) + ((green & 0xff) << 8) + (blue & 0xff));
}

iTermColorMapKey ColorMapKey(const int code,
                             const int green,
                             const int blue,
                             const ColorMode theMode,
                             const bool isBold,
                             const bool isBackground,
                             const bool useBrightBold) {
    int theIndex = code;
    bool isBackgroundForDefault = isBackground;
    switch (theMode) {
        case ColorModeAlternate:
            switch (theIndex) {
                case ALTSEM_SELECTED:
                    if (isBackground) {
                        return kColorMapSelection;
                    } else {
                        return kColorMapSelectedText;
                    }
                case ALTSEM_CURSOR:
                    if (isBackground) {
                        return kColorMapCursor;
                    } else {
                        return kColorMapCursorText;
                    }
                case ALTSEM_REVERSED_DEFAULT:
                    isBackgroundForDefault = !isBackgroundForDefault;
                    // Fall through.
                case ALTSEM_DEFAULT:
                    if (isBackgroundForDefault) {
                        return kColorMapBackground;
                    } else {
                        if (isBold && useBrightBold) {
                            return kColorMapBold;
                        } else {
                            return kColorMapForeground;
                        }
                    }
            }
            break;
        case ColorMode24bit:
            return TrueColorKey(theIndex, green, blue);
        case ColorModeNormal:
            // Render bold text as bright. The spec (ECMA-48) describes the intense
            // display setting (esc[1m) as "bold or bright". We make it a
            // preference.
            if (isBold &&
                useBrightBold &&
                (theIndex < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
                theIndex |= 8;  // set "bright" bit.
            }
            return static_cast<iTermColorMapKey>(kColorMap8bitBase + (theIndex & 0xff));

        case ColorModeInvalid:
            return kColorMapInvalid;
    }
    return kColorMapInvalid;
}

vector_float4 ColorMapLookup(device unsigned char *colorMap,
                             int key) {
    if (key >= kColorMap24bitBase) {
        // Decode a true-color key
        const int rgb = key - kColorMap24bitBase;
        return vector_float4(((rgb >> 16) & 0xff) / 255.0,
                             ((rgb >> 8) & 0xff) / 255.0,
                             ((rgb >> 0) & 0xff) / 255.0,
                             1);
    } else {
        int i = key * 4;
        return vector_float4(colorMap[i] / 255.0,
                             colorMap[i + 1] / 255.0,
                             colorMap[i + 2] / 255.0,
                             colorMap[i + 3] / 255.0);
    }
}

vector_float4 GetColor(const int code,
                       const int green,
                       const int blue,
                       const ColorMode theMode,
                       const bool isBold,
                       const bool isFaint,
                       const bool isBackground,
                       const bool useBrightBold,
                       device unsigned char *colorMap) {
    // bold is correct here and return color is respected
    iTermColorMapKey key = ColorMapKey(code, green, blue, theMode, isBold, isBackground, useBrightBold);
    if (isBackground) {
        return ColorMapLookup(colorMap, key);
    } else {
        vector_float4 color = ColorMapLookup(colorMap, key);
        if (isFaint) {
            color.w = 0.5;
        }
        return color;
    }
}

float PerceivedBrightness(vector_float3 color) {
    vector_float3 b = color * vector_float3(0.30, 0.59, 0.11);
    return b.x + b.y + b.z;
}

float4 ProcessBackgroundColor(float4 unprocessed,
                              device unsigned char *colorMap,
                              device iTermASCIITextConfiguration *config) {
    float4 defaultBackgroundColor = ColorMapLookup(colorMap, kColorMapBackground);
    float4 muted = mix(unprocessed, defaultBackgroundColor, config->mutingAmount);
    float4 gray = float4(0.5, 0.5, 0.5, 1);
    bool shouldDim = !config->dimOnlyText && config->dimmingAmount > 0;
    if (config->dimOnlyText) {
        vector_float4 diff = abs(unprocessed - defaultBackgroundColor);
        bool isDefaultBackgroundColor = (diff.x < 0.01 &&
                                         diff.y < 0.01 &&
                                         diff.z < 0.01);
        if (!isDefaultBackgroundColor) {
            float backgroundBrightness = PerceivedBrightness(defaultBackgroundColor.xyz);
            gray = float4(backgroundBrightness,
                          backgroundBrightness,
                          backgroundBrightness,
                          1);
            shouldDim = true;
        }
    }

    float4 dimmed;
    if (shouldDim) {
        dimmed = mix(muted, gray, config->dimmingAmount);
    } else {
        dimmed = muted;
    }
    dimmed.w = unprocessed.w;
    return dimmed;
}

float4 SelectionColorForCurrentFocus(device iTermASCIITextConfiguration *config,
                                     device unsigned char *colorMap) {
    if (config->isFrontTextView) {
        float4 selectionColor = ColorMapLookup(colorMap, kColorMapSelection);
        return ProcessBackgroundColor(selectionColor,
                                      colorMap,
                                      config);  // TODO: This is bugwards compatible. It should be an unprocessed color here and in iTermTextDrawingHelper.m
    } else {
        return config->unfocusedSelectionColor;
    }
}

float4 UnprocessedBackgroundColor(device screen_char_t *c,
                                  device unsigned char *colorMap,
                                  device iTermASCIITextConfiguration *config,
                                  bool selected,
                                  bool isFindMatch) {
    float alpha = config->transparencyAlpha;
    float4 color = float4(0, 0, 0, 0);
    if (selected) {
        color = SelectionColorForCurrentFocus(config, colorMap);
        if (config->transparencyAffectsOnlyDefaultBackgroundColor) {
            alpha = 1;
        }
    } else if (isFindMatch) {
        color = float4(1, 1, 0, 1);
    } else {
        const bool defaultBackground = (SCBackgroundColor(c) == ALTSEM_DEFAULT &&
                                        SCBackgroundMode(c) == ColorModeAlternate);
        // When set in preferences, applies alpha only to the defaultBackground
        // color, useful for keeping Powerline segments opacity(background)
        // consistent with their seperator glyphs opacity(foreground).
        if (config->transparencyAffectsOnlyDefaultBackgroundColor && !defaultBackground) {
            alpha = 1;
        }
        if (config->reverseVideo && defaultBackground) {
            // Reverse video is only applied to default background-
            // color chars.
            color = GetColor(ALTSEM_DEFAULT,
                             0,
                             0,
                             ColorModeAlternate,
                             false,
                             false,
                             false,
                             config->useBrightBold,
                             colorMap);
        } else {
            // Use the regular background color.
            color = GetColor(SCBackgroundColor(c),
                             SCBackgroundGreen(c),
                             SCBackgroundBlue(c),
                             SCBackgroundMode(c),
                             false,
                             false,
                             true,
                             config->useBrightBold,
                             colorMap);
        }
    }
    color.w = alpha;
    return color;
}

float4 BackgroundColor(device screen_char_t *c,
                       device iTermASCIITextConfiguration *config,
                       device unsigned char *colorMap,
                       bool selected,
                       bool isFindMatch) {
    float4 unprocessed = UnprocessedBackgroundColor(c,
                                                    colorMap,
                                                    config,
                                                    selected,
                                                    isFindMatch);
    return ProcessBackgroundColor(unprocessed,
                                  colorMap,
                                  config);
}

float4 UnderlineColor(device screen_char_t *c,  // TODO: Unused param
                      device iTermASCIITextConfiguration *config,
                      float4 textColor,
                      bool annotated,
                      bool marked) {
    if (annotated || marked) {
        return float4(1, 1, 0, 1);
    } else if (config->asciiUnderlineColor.w > 0) {
        return config->asciiUnderlineColor;
    } else {
        return textColor;
    }
}

float2 CellOffset(int i, uint2 gridSize, float2 cellSize, float2 offset) {
    float2 coord = float2(i % gridSize.x,
                          gridSize.y - 1 - i / gridSize.y);
    return coord * cellSize + offset;
}

int UnderlineStyle(device screen_char_t *c,
                   bool annotated,
                   bool inUnderlinedRange) {
    if (annotated) {
        return iTermMetalGlyphAttributesUnderlineSingle;
    } else if (SCUnderline(c) || inUnderlinedRange) {
        if (SCURLCode(c)) {
            return iTermMetalGlyphAttributesUnderlineDouble;
        } else {
            return iTermMetalGlyphAttributesUnderlineSingle;
        }
    } else if (SCURLCode(c)) {
        return iTermMetalGlyphAttributesUnderlineDashedSingle;
    } else {
        return iTermMetalGlyphAttributesUnderlineNone;
    }
}

vector_float4 ForceBrightness(vector_float4 c,
                              float t) {
    float k;
    float brightness = PerceivedBrightness(c.xyz);
    if (brightness < t) {
        k = 1;
    } else {
        k = 0;
    }
    vector_float3 e = float3(k, k, k);
    float p = (t - brightness) / PerceivedBrightness(e - c.xyz);
    p = min(1.0, max(0.0, p));
    vector_float4 result;
    result.xyz = mix(c.xyz, e, p);
    result.w = c.w;
    return result;
}

vector_float4 ApplyMinimumContrast(vector_float4 textColor,
                                   vector_float4 backgroundColor,
                                   float minimumContrast) {
    // rgba come from textColor
    // o[rgb] come from backgroundColor
    float textBrightness = PerceivedBrightness(textColor.xyz);
    float backgroundBrightness = PerceivedBrightness(backgroundColor.xyz);
    float brightnessDiff = fabs(textBrightness - backgroundBrightness);
    if (brightnessDiff >= minimumContrast) {
        return textColor;
    }

    float error = fabs(brightnessDiff - minimumContrast);
    float targetBrightness = textBrightness;
    if (textBrightness < backgroundBrightness) {
        targetBrightness -= error;
        if (targetBrightness < 0) {
            const float alternative = backgroundBrightness + minimumContrast;
            const float baseContrast = backgroundBrightness;
            const float altContrast = min(alternative, 1.0) - backgroundBrightness;
            if (altContrast > baseContrast) {
                targetBrightness = alternative;
            }
        }
    } else {
        targetBrightness += error;
        if (targetBrightness > 1) {
            const float alternative = backgroundBrightness - minimumContrast;
            const float baseContrast = 1 - backgroundBrightness;
            const float altContrast = backgroundBrightness - max(alternative, 0.0);
            if (altContrast > baseContrast) {
                targetBrightness = alternative;
            }
        }
    }

    targetBrightness = saturate(targetBrightness);
    return ForceBrightness(textColor, targetBrightness);
}

vector_float4 ProcessTextColor(vector_float4 textColor,
                               vector_float4 backgroundColor,
                               device iTermASCIITextConfiguration *config,
                               device unsigned char *colorMap) {
    // Fist apply minimum contrast, then muting, then dimming (as needed).
    vector_float4 contrastingColor = ApplyMinimumContrast(textColor, backgroundColor, config->minimumContrast);
    vector_float4 defaultBackgroundColor = ColorMapLookup(colorMap, kColorMapBackground);
    vector_float4 mutedColor = mix(contrastingColor, defaultBackgroundColor, config->mutingAmount);
    float grayLevel;
    if (config->dimOnlyText) {
        grayLevel = PerceivedBrightness(defaultBackgroundColor.xyz);
    } else {
        grayLevel = 0.5;
    }
    vector_float3 gray = float3(grayLevel,
                                grayLevel,
                                grayLevel);
    vector_float3 dimmed = mix(mutedColor.xyz, gray, config->dimmingAmount);
    vector_float4 result;
    result.xyz = mix(backgroundColor.xyz, dimmed, textColor.w);
    result.w = 1;
    return result;
}

// NOTE! IF YOU CHANGE THIS ALSO UPDATE CODE IN iTermMetalGlue.mm and iTermTextDrawingHelper.mm!
vector_float4 TextColor(device screen_char_t *c,
                        device unsigned char *selectedIndices,
                        device unsigned char *findMatchIndices,
                        device iTermASCIITextConfiguration *config,
                        device iTermASCIIRowInfo *rowInfo,
                        device unsigned char *colorMap,
                        int x,
                        vector_float4 backgroundColor,
                        bool selected,
                        bool findMatch,
                        bool inUnderlinedRange) {
    vector_float4 rawColor = { 0, 0, 0, 0 };
    const bool needsProcessing = (config->minimumContrast > 0.001 ||
                                  config->dimmingAmount > 0.001 ||
                                  config->mutingAmount > 0.001 ||
                                  SCFaint(c));  // faint implies alpha<1 and is faster than getting the alpha component

    if (findMatch) {
        // Black-on-yellow search result.
        rawColor = (vector_float4){ 0, 0, 0, 1 };
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = ColorMapLookup(colorMap, kColorMapLink);
    } else if (selected) {
        // Selected text.
        rawColor = ColorMapLookup(colorMap, kColorMapSelectedText);
    } else if (config->reverseVideo && ((SCForegroundColor(c) == ALTSEM_DEFAULT && SCForegroundMode(c) == ColorModeAlternate) ||
                                        (SCForegroundColor(c) == ALTSEM_CURSOR && SCForegroundMode(c) == ColorModeAlternate))) {
        // Reverse video is on. Either is cursor or has default foreground color. Use
        // background color.
        rawColor = ColorMapLookup(colorMap, kColorMapBackground);
    } else {
        // "Normal" case. Recompute the unprocessed color from the character.
        rawColor = GetColor(SCForegroundColor(c),
                            SCForegroundGreen(c),
                            SCForegroundBlue(c),
                            SCForegroundMode(c),
                            SCBold(c),
                            SCFaint(c),
                            false,
                            config->useBrightBold,
                            colorMap);
    }

    if (needsProcessing) {
        return ProcessTextColor(rawColor, backgroundColor, config, colorMap);
    } else {
        return rawColor;
    }
}

bool UseThinStrokes(device iTermASCIITextConfiguration *config,
                    float4 backgroundColor,
                    float4 textColor) {
    switch (config->thinStrokesSetting) {
        case iTermThinStrokesSettingAlways:
            return true;

        case iTermThinStrokesSettingDarkBackgroundsOnly:
            break;

        case iTermThinStrokesSettingNever:
            return false;

        case iTermThinStrokesSettingRetinaDarkBackgroundsOnly:
            if (config->scale < 2) {
                return false;
            }
            break;

        case iTermThinStrokesSettingRetinaOnly:
            return (config->scale >= 2);
    }

    const float backgroundBrightness = PerceivedBrightness(backgroundColor.xyz);
    const float foregroundBrightness = PerceivedBrightness(textColor.xyz);
    return backgroundBrightness < foregroundBrightness;
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
                                          config,
                                          colorMap,
                                          selected,
                                          findMatch);
    out.textColor = TextColor(&line[x],
                              selectedIndices,
                              findMatchIndices,
                              config,
                              rowInfo,
                              colorMap,
                              x,
                              out.backgroundColor,
                              selected,
                              findMatch,
                              inUnderlinedRange);
    out.underlineStyle = UnderlineStyle(&line[x], annotated, inUnderlinedRange);
    if (out.underlineStyle != iTermMetalGlyphAttributesUnderlineNone) {
        out.underlineColor = UnderlineColor(&line[x],
                                            config,
                                            out.textColor,
                                            annotated,
                                            marked);
    }
    out.cellOffset = CellOffset(x, config->gridSize, config->cellSize, *offset);
    out.viewportSize = viewportSize;
    out.scale = config->scale;

    out.bold = SCBold(&line[x]);
    out.thin = UseThinStrokes(config, out.backgroundColor, out.textColor);
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
    } else {
        return RemapColor(in.textColor, backgroundColor, bwColor, colorModels);
    }
}
