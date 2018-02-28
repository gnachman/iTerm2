//
//  iTermSharedColor.h
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

#import "iTermScreenChar.h"
#import "iTermColorMapKey.h"

#ifdef __METAL_VERSION__

#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#define COMPAT_DEVICE device
#define COMPAT_COLORMAP device unsigned char
#define BOOL bool

#else  // __METAL_VERSION__

#import <Foundation/Foundation.h>
#import "iTermColorMap.h"
#import "iTermShaderTypes.h"

#define COMPAT_DEVICE
#define COMPAT_COLORMAP iTermColorMap
#import <simd/simd.h>

#if __cplusplus
extern "C" {
#define ITERM_TERMINATE_EXTERN_C
#endif

#endif


// Declarations for code shared between Metal and Obj-c

iTermColorMapKey TrueColorKey(int red, int green, int blue);

iTermColorMapKey ColorMapKey(const int code,
                             const int green,
                             const int blue,
                             const ColorMode theMode,
                             const BOOL isBold,
                             const BOOL isBackground,
                             const BOOL useBrightBold);

vector_float4 iTermGetColor(const int code,
                            const int green,
                            const int blue,
                            const ColorMode theMode,
                            const BOOL isBold,
                            const BOOL isFaint,
                            const BOOL isBackground,
                            const BOOL useBrightBold,
                            COMPAT_COLORMAP *colorMap);

float Float3PerceivedBrightness(vector_float3 color);

vector_float4 ProcessBackgroundColor(vector_float4 unprocessed,
                              COMPAT_COLORMAP *colormap,
                              float mutingAmount,
                              BOOL dimOnlyText,
                              float dimmingAmount);

vector_float4 SelectionColorForCurrentFocus(BOOL isFrontTextView,
                                            float mutingAmount,
                                            BOOL dimOnlyText,
                                            float dimmingAmount,
                                            vector_float4 unfocusedSelectionColor,
                                            COMPAT_COLORMAP *colorMap);

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
                                         vector_float4 unfocusedSelectionColor);

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
                              float blend,
                              vector_float4 unfocusedSelectionColor,
                              COMPAT_COLORMAP *colorMap,
                              BOOL selected,
                              BOOL isFindMatch);

vector_float4 UnderlineColor(vector_float4 underlineColor,
                      vector_float4 textColor,
                      BOOL annotated,
                      BOOL marked);

iTermMetalGlyphAttributesUnderline UnderlineStyle(COMPAT_DEVICE screen_char_t *c,
                                                  BOOL annotated,
                                                  BOOL inUnderlinedRange);

vector_float4 ProcessTextColor(vector_float4 textColor,
                               vector_float4 backgroundColor,
                               float minimumContrast,
                               float mutingAmount,
                               BOOL dimOnlyText,
                               float dimmingAmount,
                               COMPAT_COLORMAP *colorMap);

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
                        BOOL inUnderlinedRange);
#else  // defined(__METAL_VERSION__)
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
                        screen_char_t *previousCharacterAttributesPtr);
#endif

BOOL UseThinStrokes(iTermThinStrokesSetting thinStrokesSetting,
                    BOOL isRetina,
                    vector_float4 backgroundColor,
                    vector_float4 textColor);

vector_float4 ApplyMinimumContrast(vector_float4 textColor,
                                   vector_float4 backgroundColor,
                                   float minimumContrast);

vector_float4 ForceBrightness(vector_float4 c,
                              float t);

#ifdef __METAL_VERSION__
vector_float4 ColorMapLookup(COMPAT_COLORMAP *colorMap,
                             iTermColorMapKey key);
#endif

#ifdef ITERM_TERMINATE_EXTERN_C
}
#endif

