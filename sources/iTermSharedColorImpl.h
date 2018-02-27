//
//  iTermSharedColorImpl.h
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

// This is imported by both objc++ and metal files.

#import "iTermSharedColor.h"
#include "Metal/Shaders/iTermMetalScreenCharAccessors.h"

#ifdef __METAL_VERSION__

#define COMPAT_MIX mix
#define COMPAT_SATURATE saturate
#define COMPAT_ABS abs
#define COMPAT_MAKE_FLOAT4 float4
#define COMPAT_MAKE_FLOAT3 float3

#else  // __METAL_VERSION__

#import <algorithm>
#import <cstdlib>
#import <cmath>
using namespace std;

#define COMPAT_MIX(_c1, _c2, _alpha) ((_c2) * (_alpha) + (_c1) * (1 - (_alpha)))
#define COMPAT_SATURATE(x) MIN(1, MAX(0, x))
#warning TODO: Test simd_abs
#define COMPAT_ABS simd_abs
#define COMPAT_MAKE_FLOAT4 simd_make_float4
#define COMPAT_MAKE_FLOAT3 simd_make_float3

#endif

iTermColorMapKey TrueColorKey(int red, int green, int blue) {
    return static_cast<iTermColorMapKey>(kColorMap24bitBase +
                                         ((red & 0xff) << 16) |
                                         ((green & 0xff) << 8) |
                                         (blue & 0xff));
}

iTermColorMapKey ColorMapKey(const int code,
                             const int green,
                             const int blue,
                             const ColorMode theMode,
                             const BOOL isBold,
                             const BOOL isBackground,
                             const BOOL useBrightBold) {
    int theIndex = code;
    BOOL isBackgroundForDefault = isBackground;
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

#ifdef __METAL_VERSION__
vector_float4 ColorMapLookup(COMPAT_COLORMAP *colorMap,
                                    iTermColorMapKey key) {
    if (key >= kColorMap24bitBase) {
        // Decode a true-color key
        const int rgb = key - kColorMap24bitBase;
        return COMPAT_MAKE_FLOAT4(((rgb >> 16) & 0xff) / 255.0,
                                  ((rgb >> 8) & 0xff) / 255.0,
                                  ((rgb >> 0) & 0xff) / 255.0,
                                  1);
    } else {
        int i = key * 4;
        return COMPAT_MAKE_FLOAT4(colorMap[i] / 255.0,
                                  colorMap[i + 1] / 255.0,
                                  colorMap[i + 2] / 255.0,
                                  colorMap[i + 3] / 255.0);
    }
}
#else
static vector_float4 ColorMapLookup(COMPAT_COLORMAP *colorMap,
                                    iTermColorMapKey key) {
    return [colorMap fastColorForKey:key];
}
#endif

vector_float4 iTermGetColor(const int code,
                            const int green,
                            const int blue,
                            const ColorMode theMode,
                            const BOOL isBold,
                            const BOOL isFaint,
                            const BOOL isBackground,
                            const BOOL useBrightBold,
                            COMPAT_COLORMAP *colorMap) {
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

float Float3PerceivedBrightness(vector_float3 color) {
    vector_float3 b = color * COMPAT_MAKE_FLOAT3(0.30, 0.59, 0.11);
    return b.x + b.y + b.z;
}

vector_float4 ProcessBackgroundColor(vector_float4 unprocessed,
                                     COMPAT_COLORMAP *colorMap,
                                     float mutingAmount,
                                     BOOL dimOnlyText,
                                     float dimmingAmount) {
    vector_float4 defaultBackgroundColor = ColorMapLookup(colorMap, kColorMapBackground);
    vector_float4 muted = COMPAT_MIX(unprocessed, defaultBackgroundColor, mutingAmount);
    vector_float4 gray = COMPAT_MAKE_FLOAT4(0.5, 0.5, 0.5, 1);
    BOOL shouldDim = !dimOnlyText &&  dimmingAmount > 0;
    if (dimOnlyText) {
        vector_float4 diff = COMPAT_ABS(unprocessed - defaultBackgroundColor);
        BOOL isDefaultBackgroundColor = (diff.x < 0.01 &&
                                         diff.y < 0.01 &&
                                         diff.z < 0.01);
        if (!isDefaultBackgroundColor) {
            float backgroundBrightness = Float3PerceivedBrightness(defaultBackgroundColor.xyz);
            gray = COMPAT_MAKE_FLOAT4(backgroundBrightness,
                                      backgroundBrightness,
                                      backgroundBrightness,
                                      1);
            shouldDim = true;
        }
    }

    vector_float4 dimmed;
    if (shouldDim) {
        dimmed = COMPAT_MIX(muted, gray, dimmingAmount);
    } else {
        dimmed = muted;
    }
    dimmed.w = unprocessed.w;
    return dimmed;
}

// NOTE: this should match -[iTermTextDrawingHelper selectionColorForCurrentFocus]
vector_float4 SelectionColorForCurrentFocus(BOOL isFrontTextView,
                                            float mutingAmount,
                                            BOOL dimOnlyText,
                                            float dimmingAmount,
                                            vector_float4 unfocusedSelectionColor,
                                            COMPAT_COLORMAP *colorMap) {
    if (isFrontTextView) {
        vector_float4 selectionColor = ColorMapLookup(colorMap, kColorMapSelection);
        return ProcessBackgroundColor(selectionColor,
                                      colorMap,
                                      mutingAmount,
                                      dimOnlyText,
                                      dimmingAmount);  // TODO: This is bugwards compatible. It should be an unprocessed color here and in iTermTextDrawingHelper.m
    } else {
        return unfocusedSelectionColor;
    }
}

vector_float4 UnprocessedBackgroundColor(COMPAT_DEVICE screen_char_t *c,
                                         COMPAT_COLORMAP *colorMap,
                                         float transparencyAlpha,
                                         BOOL transparencyAffectsOnlyDefaultBackgroundColor,
                                         BOOL reverseVideo,
                                         BOOL useBrightBold,
                                         BOOL isFrontTextView,
                                         float mutingAmount,
                                         BOOL dimOnlyText,
                                         float dimmingAmount,
                                         BOOL hasBackgroundImage,
                                         float blend,
                                         BOOL selected,
                                         BOOL isFindMatch,
                                         vector_float4 unfocusedSelectionColor) {
    float alpha = transparencyAlpha;
    vector_float4 color = COMPAT_MAKE_FLOAT4(0, 0, 0, 0);
    if (selected) {
        color = SelectionColorForCurrentFocus(isFrontTextView,
                                              mutingAmount,
                                              dimOnlyText,
                                              dimmingAmount,
                                              unfocusedSelectionColor,
                                              colorMap);
        if (transparencyAffectsOnlyDefaultBackgroundColor) {
            alpha = 1;
        }
    } else if (isFindMatch) {
        color = COMPAT_MAKE_FLOAT4(1, 1, 0, 1);
    } else {
        const BOOL defaultBackground = (SCBackgroundColor(c) == ALTSEM_DEFAULT &&
                                        SCBackgroundMode(c) == ColorModeAlternate);
        // When set in preferences, applies alpha only to the defaultBackground
        // color, useful for keeping Powerline segments opacity(background)
        // consistent with their seperator glyphs opacity(foreground).
        if (transparencyAffectsOnlyDefaultBackgroundColor && !defaultBackground) {
            alpha = 1;
        }
        if (reverseVideo && defaultBackground) {
            // Reverse video is only applied to default background-
            // color chars.
            color = iTermGetColor(ALTSEM_DEFAULT,
                                  0,
                                  0,
                                  ColorModeAlternate,
                                  false,
                                  false,
                                  false,
                                  useBrightBold,
                                  colorMap);
        } else {
            // Use the regular background color.
            color = iTermGetColor(SCBackgroundColor(c),
                                  SCBackgroundGreen(c),
                                  SCBackgroundBlue(c),
                                  SCBackgroundMode(c),
                                  false,
                                  false,
                                  true,
                                  useBrightBold,
                                  colorMap);
        }
#ifndef __METAL_VERSION
        if (defaultBackground && hasBackgroundImage) {
#warning TEST THIS IN METAL
            alpha = 1 - blend;
        }
#endif
    }
    color.w = alpha;
    return color;
}

vector_float4 BackgroundColor(COMPAT_DEVICE screen_char_t *c,
                              float transparencyAlpha,
                              BOOL transparencyAffectsOnlyDefaultBackgroundColor,
                              BOOL reverseVideo,
                              BOOL useBrightBold,
                              BOOL isFrontTextView,
                              float mutingAmount,
                              BOOL dimOnlyText,
                              float dimmingAmount,
                              BOOL hasBackgroundImage,
                              vector_float4 unfocusedSelectionColor,
                              COMPAT_COLORMAP *colorMap,
                              BOOL selected,
                              BOOL isFindMatch) {
    vector_float4 unprocessed = UnprocessedBackgroundColor(c,
                                                           colorMap,
                                                           transparencyAlpha,
                                                           transparencyAffectsOnlyDefaultBackgroundColor,
                                                           reverseVideo,
                                                           useBrightBold,
                                                           isFrontTextView,
                                                           mutingAmount,
                                                           dimOnlyText,
                                                           dimmingAmount,
                                                           hasBackgroundImage,
                                                           0,
                                                           selected,
                                                           isFindMatch,
                                                           unfocusedSelectionColor);
    return ProcessBackgroundColor(unprocessed,
                                  colorMap,
                                  mutingAmount,
                                  dimOnlyText,
                                  dimmingAmount);
}

vector_float4 UnderlineColor(vector_float4 underlineColor,
                             vector_float4 textColor,
                             BOOL annotated,
                             BOOL marked) {
    if (annotated || marked) {
        return COMPAT_MAKE_FLOAT4(1, 1, 0, 1);
    } else if (underlineColor.w > 0) {
        return underlineColor;
    } else {
        return textColor;
    }
}

iTermMetalGlyphAttributesUnderline UnderlineStyle(COMPAT_DEVICE screen_char_t *c,
                                                  BOOL annotated,
                                                  BOOL inUnderlinedRange) {
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

/*
 Given:
 a vector c [c1, c2, c3] (the starting color)
 a vector e [e1, e2, e3] (an extreme color we are moving to, normally black or white)
 a vector A [a1, a2, a3] (the perceived brightness transform)
 a linear function f(Y)=AY (perceived brightness for color Y)
 a constant t (target perceived brightness)
 find a vector X such that F(X)=t
 and X lies on a straight line between c and e

 Define a parametric vector x(p) = [x1(p), x2(p), x3(p)]:
 x1(p) = p*e1 + (1-p)*c1
 x2(p) = p*e2 + (1-p)*c2
 x3(p) = p*e3 + (1-p)*c3

 when p=0, x=c
 when p=1, x=e

 the line formed by x(p) from p=0 to p=1 is the line from c to e.

 Our goal: find the value of p where f(x(p))=t

 We know that:
 [x1(p)]
 f(X) = AX = [a1 a2 a3] [x2(p)] = a1x1(p) + a2x2(p) + a3x3(p)
 [x3(p)]
 Expand and solve for p:
 t = a1*(p*e1 + (1-p)*c1) + a2*(p*e2 + (1-p)*c2) + a3*(p*e3 + (1-p)*c3)
 t = a1*(p*e1 + c1 - p*c1) + a2*(p*e2 + c2 - p*c2) + a3*(p*e3 + c3 - p*c3)
 t = a1*p*e1 + a1*c1 - a1*p*c1 + a2*p*e2 + a2*c2 - a2*p*c2 + a3*p*e3 + a3*c3 - a3*p*c3
 t = a1*p*e1 - a1*p*c1 + a2*p*e2 - a2*p*c2 + a3*p*e3 - a3*p*c3 + a1*c1 + a2*c2 + a3*c3
 t = p*(a2*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3) + a1*c1 + a2*c2 + a3*c3
 t - (a1*c1 + a2*c2 + a3*c3) = p*(a1*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3)
 p = (t - (a1*c1 + a2*c2 + a3*c3)) / (a1*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3)

 The PerceivedBrightness() function is a dot product between the a vector and its input, so the
 previous equation is equivalent to:
 p = (t - PerceivedBrightness(c1, c2, c3) / PerceivedBrightness(e1-c1, e2-c2, e3-c3)
 */
vector_float4 ForceBrightness(vector_float4 c,
                              float t) {
    float k;
    float brightness = Float3PerceivedBrightness(c.xyz);
    if (brightness < t) {
        k = 1;
    } else {
        k = 0;
    }
    vector_float3 e = COMPAT_MAKE_FLOAT3(k, k, k);
    float p = (t - brightness) / Float3PerceivedBrightness(e - c.xyz);
    p = COMPAT_SATURATE(p);
    vector_float4 result;
    result.xyz = COMPAT_MIX(c.xyz, e, p);
    result.w = c.w;
    return result;
}

vector_float4 ApplyMinimumContrast(vector_float4 textColor,
                                   vector_float4 backgroundColor,
                                   float minimumContrast) {
    // rgba come from textColor
    // o[rgb] come from backgroundColor
    float textBrightness = Float3PerceivedBrightness(textColor.xyz);
    float backgroundBrightness = Float3PerceivedBrightness(backgroundColor.xyz);
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
            const float altContrast = min(alternative, 1.0f) - backgroundBrightness;
            if (altContrast > baseContrast) {
                targetBrightness = alternative;
            }
        }
    } else {
        targetBrightness += error;
        if (targetBrightness > 1) {
            const float alternative = backgroundBrightness - minimumContrast;
            const float baseContrast = 1 - backgroundBrightness;
            const float altContrast = backgroundBrightness - max(alternative, 0.0f);
            if (altContrast > baseContrast) {
                targetBrightness = alternative;
            }
        }
    }

    targetBrightness = COMPAT_SATURATE(targetBrightness);
    return ForceBrightness(textColor, targetBrightness);
}

vector_float4 ProcessTextColor(vector_float4 textColor,
                               vector_float4 backgroundColor,
                               float minimumContrast,
                               float mutingAmount,
                               BOOL dimOnlyText,
                               float dimmingAmount,
                               COMPAT_COLORMAP *colorMap) {
    // Fist apply minimum contrast, then muting, then dimming (as needed).
    vector_float4 contrastingColor = ApplyMinimumContrast(textColor, backgroundColor, minimumContrast);
    vector_float4 defaultBackgroundColor = ColorMapLookup(colorMap, kColorMapBackground);
    vector_float4 mutedColor = COMPAT_MIX(contrastingColor, defaultBackgroundColor, mutingAmount);
    float grayLevel;
    if (dimOnlyText) {
        grayLevel = Float3PerceivedBrightness(defaultBackgroundColor.xyz);
    } else {
        grayLevel = 0.5;
    }
    vector_float3 gray = COMPAT_MAKE_FLOAT3(grayLevel,
                                            grayLevel,
                                            grayLevel);
    vector_float3 dimmed = COMPAT_MIX(mutedColor.xyz, gray, dimmingAmount);
    vector_float4 result;
    result.xyz = COMPAT_MIX(backgroundColor.xyz, dimmed, textColor.w);
    result.w = 1;
    return result;
}

// NOTE! IF YOU CHANGE THIS ALSO UPDATE CODE IN iTermMetalGlue.mm and iTermTextDrawingHelper.mm!
#ifdef __METAL_VERSION__
vector_float4 TextColor(COMPAT_DEVICE screen_char_t *c,
                        float minimumContrast,
                        float dimmingAmount,
                        float mutingAmount,
                        BOOL dimOnlyText,
                        BOOL reverseVideo,
                        BOOL useBrightBold,
                        COMPAT_COLORMAP *colorMap,
                        vector_float4 backgroundColor,
                        BOOL selected,
                        BOOL findMatch,
                        BOOL inUnderlinedRange) {
    vector_float4 rawColor = { 0, 0, 0, 0 };
    const BOOL needsProcessing = (minimumContrast > 0.001 ||
                                  dimmingAmount > 0.001 ||
                                  mutingAmount > 0.001 ||
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
    } else if (reverseVideo && ((SCForegroundColor(c) == ALTSEM_DEFAULT && SCForegroundMode(c) == ColorModeAlternate) ||
                                (SCForegroundColor(c) == ALTSEM_CURSOR && SCForegroundMode(c) == ColorModeAlternate))) {
        // Reverse video is on. Either is cursor or has default foreground color. Use
        // background color.
        rawColor = ColorMapLookup(colorMap, kColorMapBackground);
    } else {
        // "Normal" case. Recompute the unprocessed color from the character.
        rawColor = iTermGetColor(SCForegroundColor(c),
                                 SCForegroundGreen(c),
                                 SCForegroundBlue(c),
                                 SCForegroundMode(c),
                                 SCBold(c),
                                 SCFaint(c),
                                 false,
                                 useBrightBold,
                                 colorMap);
    }

    if (needsProcessing) {
        return ProcessTextColor(rawColor,
                                backgroundColor,
                                minimumContrast,
                                mutingAmount,
                                dimOnlyText,
                                dimmingAmount,
                                colorMap);
    } else {
        return rawColor;
    }
}
#else  // defined(__METAL_VERSION__)

// The non-metal version adds a bunch of caching.
vector_float4 TextColor(COMPAT_DEVICE screen_char_t *c,
                        float minimumContrast,
                        float dimmingAmount,
                        float mutingAmount,
                        BOOL dimOnlyText,
                        BOOL reverseVideo,
                        BOOL useBrightBold,
                        COMPAT_COLORMAP *colorMap,
                        vector_float4 backgroundColor,
                        BOOL selected,
                        BOOL findMatch,
                        BOOL inUnderlinedRange,
                        vector_float4 *lastUnprocessedColorPtr,
                        vector_float4 *previousForegroundColorPtr,
                        BOOL *havePreviousForegroundColorPtr,
                        BOOL *havePreviousCharacterAttributesPtr,
                        screen_char_t *previousCharacterAttributesPtr) {
    vector_float4 rawColor = { 0, 0, 0, 0 };
    const BOOL needsProcessing = (minimumContrast > 0.001 ||
                                  dimmingAmount > 0.001 ||
                                  mutingAmount > 0.001 ||
                                  SCFaint(c));  // faint implies alpha<1 and is faster than getting the alpha component

    if (findMatch) {
        // Black-on-yellow search result.
        rawColor = (vector_float4){ 0, 0, 0, 1 };
        *havePreviousCharacterAttributesPtr = NO;
    } else if (inUnderlinedRange) {
        // Blue link text.
        rawColor = ColorMapLookup(colorMap, kColorMapLink);
        *havePreviousCharacterAttributesPtr = NO;
    } else if (selected) {
        // Selected text.
        rawColor = ColorMapLookup(colorMap, kColorMapSelectedText);
        *havePreviousCharacterAttributesPtr = NO;
    } else if (reverseVideo && ((SCForegroundColor(c) == ALTSEM_DEFAULT && SCForegroundMode(c) == ColorModeAlternate) ||
                                (SCForegroundColor(c) == ALTSEM_CURSOR && SCForegroundMode(c) == ColorModeAlternate))) {
        // Reverse video is on. Either is cursor or has default foreground color. Use
        // background color.
        rawColor = ColorMapLookup(colorMap, kColorMapBackground);
        *havePreviousCharacterAttributesPtr = NO;
    } else if (!*havePreviousCharacterAttributesPtr ||
               c->foregroundColor != previousCharacterAttributesPtr->foregroundColor ||
               c->fgGreen != previousCharacterAttributesPtr->fgGreen ||
               c->fgBlue != previousCharacterAttributesPtr->fgBlue ||
               c->foregroundColorMode != previousCharacterAttributesPtr->foregroundColorMode ||
               c->bold != previousCharacterAttributesPtr->bold ||
               c->faint != previousCharacterAttributesPtr->faint ||
               !*havePreviousForegroundColorPtr) {
        // "Normal" case. Recompute the unprocessed color from the character.
        *previousCharacterAttributesPtr = *c;
        *havePreviousCharacterAttributesPtr = YES;
        rawColor = iTermGetColor(SCForegroundColor(c),
                                 SCForegroundGreen(c),
                                 SCForegroundBlue(c),
                                 SCForegroundMode(c),
                                 SCBold(c),
                                 SCFaint(c),
                                 false,
                                 useBrightBold,
                                 colorMap);
    } else {
        // Foreground attributes are just like the last character. There is a cached foreground color.
        if (needsProcessing) {
            // Process the text color for the current background color, which has changed since
            // the last cell.
            rawColor = *lastUnprocessedColorPtr;
        } else {
            // Text color is unchanged. Either it's independent of the background color or the
            // background color has not changed.
            return *previousForegroundColorPtr;
        }
    }

    *lastUnprocessedColorPtr = rawColor;

    vector_float4 result;
    if (needsProcessing) {
        result = ProcessTextColor(rawColor,
                                  backgroundColor,
                                  minimumContrast,
                                  mutingAmount,
                                  dimOnlyText,
                                  dimmingAmount,
                                  colorMap);
    } else {
        result = rawColor;
    }
    *previousForegroundColorPtr = result;
    *havePreviousForegroundColorPtr = YES;
    return result;
}
#endif

BOOL UseThinStrokes(iTermThinStrokesSetting thinStrokesSetting,
                    BOOL isRetina,
                    vector_float4 backgroundColor,
                    vector_float4 textColor) {
    switch (thinStrokesSetting) {
    case iTermThinStrokesSettingAlways:
        return true;

    case iTermThinStrokesSettingDarkBackgroundsOnly:
        break;

    case iTermThinStrokesSettingNever:
        return false;

    case iTermThinStrokesSettingRetinaDarkBackgroundsOnly:
        if (!isRetina) {
            return false;
        }
        break;

    case iTermThinStrokesSettingRetinaOnly:
        return isRetina;
    }

    const float backgroundBrightness = Float3PerceivedBrightness(backgroundColor.xyz);
    const float foregroundBrightness = Float3PerceivedBrightness(textColor.xyz);
    return backgroundBrightness < foregroundBrightness;
}


