//
//  iTermColorMap.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "iTermColorMap.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "NSColor+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import <simd/simd.h>

const int kColorMapForeground = 0;
const int kColorMapBackground = 1;
const int kColorMapBold = 2;
const int kColorMapSelection = 3;
const int kColorMapSelectedText = 4;
const int kColorMapCursor = 5;
const int kColorMapCursorText = 6;
const int kColorMapInvalid = 7;
const int kColorMapLink = 8;
const int kColorMapUnderline = 9;
// This value plus 0...255 are accepted.
const int kColorMap8bitBase = 10;
const int kColorMapNumberOf8BitColors = 256;
// This value plus 0...2^24-1 are accepted as read-only keys. These must be the highest-valued keys.
const int kColorMap24bitBase = kColorMap8bitBase + 256;

const int kColorMapAnsiBlack = kColorMap8bitBase + 0;
const int kColorMapAnsiRed = kColorMap8bitBase + 1;
const int kColorMapAnsiGreen = kColorMap8bitBase + 2;
const int kColorMapAnsiYellow = kColorMap8bitBase + 3;
const int kColorMapAnsiBlue = kColorMap8bitBase + 4;
const int kColorMapAnsiMagenta = kColorMap8bitBase + 5;
const int kColorMapAnsiCyan = kColorMap8bitBase + 6;
const int kColorMapAnsiWhite = kColorMap8bitBase + 7;
const int kColorMapAnsiBrightModifier = 8;

@interface iTermColorMapSanitizingAdapter: NSProxy<iTermColorMapReading>
- (instancetype)initWithSource:(iTermColorMap *)source;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermColorMap ()
@property(nonatomic, strong) NSMutableDictionary *map;
@end

@implementation iTermColorMap {
    double _backgroundBrightness;

    // Memoized colors and components
    // Only 3 components are used here, but I'm paranoid screwing up and overflowing.
    CGFloat _lastTextComponents[4];
    NSColor *_lastTextColor;

    // This one actually uses four components.
    CGFloat _lastBackgroundComponents[4];
    NSColor *_lastBackgroundColor;

    NSMutableDictionary<NSNumber *, NSData *> *_fastMap;
    id<iTermColorMapReading> _sanitizingAdapter;
}

@synthesize generation = _generation;

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue {
    return kColorMap24bitBase + ((red & 0xff) << 16) + ((green & 0xff) << 8) + (blue & 0xff);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _map = [[NSMutableDictionary alloc] init];
        _fastMap = [[NSMutableDictionary alloc] init];
        _faintTextAlpha = 0.5;
    }
    return self;
}

- (void)setDimmingAmount:(double)dimmingAmount {
    _generation += 1;
    _dimmingAmount = dimmingAmount;
    [self.delegate colorMap:self dimmingAmountDidChangeTo:dimmingAmount];
}

- (void)setMutingAmount:(double)mutingAmount {
    if (_mutingAmount == mutingAmount) {
        return;
    }
    _generation += 1;
    _mutingAmount = mutingAmount;
    [self.delegate colorMap:self mutingAmountDidChangeTo:mutingAmount];
}

- (void)setColor:(NSColor *)colorInArbitrarySpace forKey:(iTermColorMapKey)theKey {
    if (theKey >= kColorMap24bitBase) {
        return;
    }
    _generation += 1;

    if (!colorInArbitrarySpace) {
        [_map removeObjectForKey:@(theKey)];
        [_fastMap removeObjectForKey:@(theKey)];
        return;
    }

    NSColor *theColor = [colorInArbitrarySpace colorUsingColorSpace:[NSColorSpace it_defaultColorSpace]];
    NSColor *oldColor = _map[@(theKey)];
    {
        if (theColor == oldColor || [theColor isEqual:oldColor]) {
            DLog(@"Color with key %@ unchanged (%@)", @(theKey), oldColor);
            return;
        }
    }

    if (theKey == kColorMapBackground) {
        _backgroundBrightness = [theColor perceivedBrightness];
    }

    _map[@(theKey)] = theColor;

    // Get components again, now in the default color space (which might be the same)
    CGFloat components[4];
    [theColor getComponents:components];
    vector_float4 value = {
        (float)components[0],
        (float)components[1],
        (float)components[2],
        (float)components[3]
   };
    _fastMap[@(theKey)] = [NSData dataWithBytes:&value length:sizeof(value)];
    [self.delegate colorMap:self didChangeColorForKey:theKey from:oldColor to:theColor];
}

- (NSColor *)colorForKey:(iTermColorMapKey)theKey {
    if (theKey == kColorMapInvalid) {
        return [NSColor redColor];
    } else if (theKey >= kColorMap24bitBase) {
        int n = theKey - kColorMap24bitBase;
        int blue = (n & 0xff);
        int green = (n >> 8) & 0xff;
        int red = (n >> 16) & 0xff;
        return [NSColor colorWith8BitRed:red green:green blue:blue];
    } else {
        return _map[@(theKey)];
    }
}

- (vector_float4)fastColorForKey:(iTermColorMapKey)theKey {
    if (theKey == kColorMapInvalid) {
        return simd_make_float4(1, 0, 0, 1);
    } else if (theKey >= kColorMap24bitBase) {
        int n = theKey - kColorMap24bitBase;
        int blue = (n & 0xff);
        int green = (n >> 8) & 0xff;
        int red = (n >> 16) & 0xff;
        return simd_make_float4(red / 255.0,
                                green / 255.0,
                                blue / 255.0,
                                1);
    } else {
        NSData *data = _fastMap[@(theKey)];
        vector_float4 value;
        memmove(&value, data.bytes, sizeof(value));
        return value;
    }
}

- (void)setDimOnlyText:(BOOL)dimOnlyText {
    if (dimOnlyText == _dimOnlyText) {
        return;
    }
    _generation += 1;
    _dimOnlyText = dimOnlyText;
    [self.delegate colorMap:self dimmingAmountDidChangeTo:_dimmingAmount];
}

- (void)setDarkMode:(BOOL)darkMode {
    _darkMode = darkMode;
    _generation += 1;
}

- (void)setUseSeparateColorsForLightAndDarkMode:(BOOL)useSeparateColorsForLightAndDarkMode {
    _useSeparateColorsForLightAndDarkMode = useSeparateColorsForLightAndDarkMode;
    _generation += 1;
}

- (void)setMinimumContrast:(double)minimumContrast {
    _minimumContrast = minimumContrast;
    _generation += 1;
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
+ (void)getComponents:(CGFloat *)result
    byAveragingComponents:(CGFloat *)rgb1
       withComponents:(CGFloat *)rgb2
                alpha:(CGFloat)alpha {
    for (int i = 0; i < 3; i++) {
        result[i] = rgb1[i] * (1 - alpha) + rgb2[i] * alpha;
    }
    result[3] = rgb1[3];
}

- (vector_float4)fastAverageComponents:(vector_float4)rgb1 with:(vector_float4)rgb2 alpha:(float)alpha {
    vector_float4 result = {
        rgb1.x * (1 - alpha) + rgb2.x * alpha,
        rgb1.y * (1 - alpha) + rgb2.y * alpha,
        rgb1.z * (1 - alpha) + rgb2.z * alpha,
        rgb1.w
    };
    return result;
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (NSColor *)processedTextColorForTextColor:(NSColor *)textColor
                        overBackgroundColor:(NSColor *)backgroundColor
                     disableMinimumContrast:(BOOL)disableMinimumContrast {
    if (!textColor) {
        return nil;
    }
    // Fist apply minimum contrast, then muting, then dimming (as needed).
    CGFloat textRgb[4];
    [textColor getComponents:textRgb];
    CGFloat backgroundRgb[4];
    [backgroundColor getComponents:backgroundRgb];

    CGFloat contrastingRgb[4];
    if (backgroundColor && !disableMinimumContrast) {
        [NSColor getComponents:contrastingRgb
                 forComponents:textRgb
            withContrastAgainstComponents:backgroundRgb
                          minimumContrast:_minimumContrast];
    } else {
        memmove(contrastingRgb, textRgb, sizeof(textRgb));
    }

    CGFloat defaultBackgroundComponents[4];
    [_map[@(kColorMapBackground)] getComponents:defaultBackgroundComponents];

    CGFloat mutedRgb[4];
    [iTermColorMap getComponents:mutedRgb
           byAveragingComponents:contrastingRgb
                  withComponents:defaultBackgroundComponents
                           alpha:_mutingAmount];

    CGFloat dimmedRgb[4];
    CGFloat grayRgb[] = { _backgroundBrightness, _backgroundBrightness, _backgroundBrightness };
    if (!_dimOnlyText) {
        grayRgb[0] = grayRgb[1] = grayRgb[2] = 0.5;
    }
    [iTermColorMap getComponents:dimmedRgb
           byAveragingComponents:mutedRgb
                  withComponents:grayRgb
                           alpha:_dimmingAmount];

    // Premultiply alpha
    CGFloat alpha = textRgb[3];
    for (int i = 0; i < 3; i++) {
        dimmedRgb[i] = dimmedRgb[i] * alpha + backgroundRgb[i] * (1 - alpha);
    }
    dimmedRgb[3] = 1;

    if (_lastTextColor && !memcmp(_lastTextComponents, dimmedRgb, sizeof(CGFloat) * 3)) {
        return _lastTextColor;
    } else {
        memmove(_lastTextComponents, dimmedRgb, sizeof(CGFloat) * 3);
        _lastTextColor = [NSColor colorWithColorSpace:textColor.colorSpace
                                           components:dimmedRgb
                                                count:4];
        return _lastTextColor;
    }
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (NSColor *)colorByMutingColor:(NSColor *)color {
    if (_mutingAmount < 0.01) {
        return color;
    }

    CGFloat components[4];
    [color getComponents:components];

    vector_float4 colorVector = simd_make_float4(components[0],
                                                 components[1],
                                                 components[2],
                                                 components[3]);
    vector_float4 v = [self commonColorByMutingColor:colorVector];

    CGFloat mutedRgb[4] = { v.x, v.y, v.z, v.w };
    return [NSColor colorWithColorSpace:color.colorSpace
                             components:mutedRgb
                                  count:4];
}

- (vector_float4)fastColorByMutingColor:(vector_float4)color {
    if (_mutingAmount < 0.01) {
        return color;
    }

    return [self commonColorByMutingColor:color];
}

- (vector_float4)commonColorByMutingColor:(vector_float4)color {
    CGFloat components[4] = { color.x, color.y, color.z, color.w };
    CGFloat defaultBackgroundComponents[4];
    [_map[@(kColorMapBackground)] getComponents:defaultBackgroundComponents];

    CGFloat mutedRgb[4];
    [iTermColorMap getComponents:mutedRgb
           byAveragingComponents:components
                  withComponents:defaultBackgroundComponents
                           alpha:_mutingAmount];
    mutedRgb[3] = components[3];

    return simd_make_float4(mutedRgb[0], mutedRgb[1], mutedRgb[2], components[3]);
}

+ (NSColor *)dimmedTextColor:(NSColor *)color
        backgroundBrightness:(CGFloat)backgroundBrightness
               dimmingAmount:(CGFloat)dimmingAmount
                 dimOnlyText:(BOOL)dimOnlyText {
    CGFloat components[4];
    [color getComponents:components];

    CGFloat dimmedRgb[4];
    CGFloat grayRgb[] = { backgroundBrightness, backgroundBrightness, backgroundBrightness };
    if (!dimOnlyText) {
        grayRgb[0] = grayRgb[1] = grayRgb[2] = 0.5;
    }
    [iTermColorMap getComponents:dimmedRgb
           byAveragingComponents:components
                  withComponents:grayRgb
                           alpha:dimmingAmount];
    dimmedRgb[3] = components[3];

    return [NSColor colorWithColorSpace:color.colorSpace
                             components:dimmedRgb
                                  count:4];
}
// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (NSColor *)colorByDimmingTextColor:(NSColor *)color {
    if (_dimmingAmount < 0.01) {
        return color;
    }

    CGFloat defaultBackgroundComponents[4];
    [_map[@(kColorMapBackground)] getComponents:defaultBackgroundComponents];

    return [iTermColorMap dimmedTextColor:color
                     backgroundBrightness:_backgroundBrightness
                            dimmingAmount:_dimmingAmount
                              dimOnlyText:_dimOnlyText];
}

- (vector_float4)fastProcessedBackgroundColorForBackgroundColor:(vector_float4)backgroundColor {
    vector_float4 defaultBackgroundComponents = [self fastColorForKey:kColorMapBackground];
    const vector_float4 mutedRgb = [self fastAverageComponents:backgroundColor with:defaultBackgroundComponents alpha:_mutingAmount];
    vector_float4 grayRgb = { 0.5, 0.5, 0.5, 1 };

    BOOL shouldDim = !_dimOnlyText && _dimmingAmount > 0;
    // If dimOnlyText is set then text and non-default background colors get dimmed toward black.
    if (_dimOnlyText) {
        const BOOL isDefaultBackgroundColor =
        (fabs(backgroundColor.x - defaultBackgroundComponents.x) < 0.01 &&
         fabs(backgroundColor.y - defaultBackgroundComponents.y) < 0.01 &&
         fabs(backgroundColor.z - defaultBackgroundComponents.z) < 0.01);
        if (!isDefaultBackgroundColor) {
            grayRgb = (vector_float4){
                (float)_backgroundBrightness,
                (float)_backgroundBrightness,
                (float)_backgroundBrightness,
                1
            };
            shouldDim = YES;
        }
    }

    vector_float4 dimmedRgb;
    if (shouldDim) {
        dimmedRgb = [self fastAverageComponents:mutedRgb with:grayRgb alpha:_dimmingAmount];
    } else {
        dimmedRgb = mutedRgb;
    }
    dimmedRgb.w = backgroundColor.w;

    return dimmedRgb;
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (NSColor *)processedBackgroundColorForBackgroundColor:(NSColor *)backgroundColor {
    if (!backgroundColor) {
        return nil;
    }
    // Fist apply muting then dimming (as needed).
    CGFloat backgroundRgb[4];
    [backgroundColor getComponents:backgroundRgb];

    CGFloat defaultBackgroundComponents[4];
    [_map[@(kColorMapBackground)] getComponents:defaultBackgroundComponents];

    CGFloat mutedRgb[4];
    [iTermColorMap getComponents:mutedRgb
           byAveragingComponents:backgroundRgb
                  withComponents:defaultBackgroundComponents
                           alpha:_mutingAmount];

    CGFloat dimmedRgb[4];
    CGFloat grayRgb[] = { 0.5, 0.5, 0.5 };
    BOOL shouldDim = !_dimOnlyText && _dimmingAmount > 0;
    // If dimOnlyText is set then text and non-default background colors get dimmed toward black.
    if (_dimOnlyText) {
        const BOOL isDefaultBackgroundColor =
            (fabs(backgroundRgb[0] - defaultBackgroundComponents[0]) < 0.01 &&
             fabs(backgroundRgb[1] - defaultBackgroundComponents[1]) < 0.01 &&
             fabs(backgroundRgb[2] - defaultBackgroundComponents[2]) < 0.01);
        if (!isDefaultBackgroundColor) {
            for (int j = 0; j < 3; j++) {
                grayRgb[j] = _backgroundBrightness;
            }
            shouldDim = YES;
        }
    }

    if (shouldDim) {
        [iTermColorMap getComponents:dimmedRgb
               byAveragingComponents:mutedRgb
                      withComponents:grayRgb
                               alpha:_dimmingAmount];
    } else {
        memmove(dimmedRgb, mutedRgb, sizeof(CGFloat) * 3);
    }
    dimmedRgb[3] = backgroundRgb[3];

    if (!memcmp(_lastBackgroundComponents, dimmedRgb, sizeof(CGFloat) * 4)) {
        return _lastBackgroundColor;
    } else {
        memmove(_lastBackgroundComponents, dimmedRgb, sizeof(CGFloat) * 4);
        _lastBackgroundColor = [NSColor colorWithColorSpace:backgroundColor.colorSpace
                                                 components:dimmedRgb
                                                      count:4];
        return _lastBackgroundColor;
    }
}

- (NSString *)profileKeyForColorMapKey:(int)theKey {
    NSString *baseKey = [self baseProfileKeyForColorMapKey:theKey];
    return [self profileKeyForBaseKey:baseKey];
}

- (NSString *)profileKeyForBaseKey:(NSString *)baseKey {
    if (!self.useSeparateColorsForLightAndDarkMode) {
        return baseKey;
    }
    if (self.darkMode) {
        return [baseKey stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
    }
    return [baseKey stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
}

- (NSString *)baseProfileKeyForColorMapKey:(int)theKey {
    return self.colormapKeyToProfileKeyDictionary[@(theKey)];
}

- (NSDictionary<NSNumber *, NSString *> *)colormapKeyToProfileKeyDictionary {
    static dispatch_once_t onceToken;
    static NSDictionary<NSNumber *, NSString *> *dict;
    dispatch_once(&onceToken, ^{
        dict = @{
            @(kColorMapForeground): KEY_FOREGROUND_COLOR,
            @(kColorMapBackground): KEY_BACKGROUND_COLOR,
            @(kColorMapBold): KEY_BOLD_COLOR,
            @(kColorMapLink): KEY_LINK_COLOR,
            @(kColorMapSelection): KEY_SELECTION_COLOR,
            @(kColorMapSelectedText): KEY_SELECTED_TEXT_COLOR,
            @(kColorMapCursor): KEY_CURSOR_COLOR,
            @(kColorMapCursorText): KEY_CURSOR_TEXT_COLOR,
            @(kColorMapUnderline): KEY_UNDERLINE_COLOR,
            @(kColorMapAnsiBlack): KEY_ANSI_0_COLOR,
            @(kColorMapAnsiRed): KEY_ANSI_1_COLOR,
            @(kColorMapAnsiGreen): KEY_ANSI_2_COLOR,
            @(kColorMapAnsiYellow): KEY_ANSI_3_COLOR,
            @(kColorMapAnsiBlue): KEY_ANSI_4_COLOR,
            @(kColorMapAnsiMagenta): KEY_ANSI_5_COLOR,
            @(kColorMapAnsiCyan): KEY_ANSI_6_COLOR,
            @(kColorMapAnsiWhite): KEY_ANSI_7_COLOR,
            @(kColorMapAnsiBlack + kColorMapAnsiBrightModifier): KEY_ANSI_8_COLOR,
            @(kColorMapAnsiRed + kColorMapAnsiBrightModifier): KEY_ANSI_9_COLOR,
            @(kColorMapAnsiGreen + kColorMapAnsiBrightModifier): KEY_ANSI_10_COLOR,
            @(kColorMapAnsiYellow + kColorMapAnsiBrightModifier): KEY_ANSI_11_COLOR,
            @(kColorMapAnsiBlue + kColorMapAnsiBrightModifier): KEY_ANSI_12_COLOR,
            @(kColorMapAnsiMagenta + kColorMapAnsiBrightModifier): KEY_ANSI_13_COLOR,
            @(kColorMapAnsiCyan + kColorMapAnsiBrightModifier): KEY_ANSI_14_COLOR,
            @(kColorMapAnsiWhite + kColorMapAnsiBrightModifier): KEY_ANSI_15_COLOR,
        };
    });
    return dict;
}

- (NSColor *)colorForCode:(int)theIndex
                    green:(int)green
                     blue:(int)blue
                colorMode:(ColorMode)theMode
                     bold:(BOOL)isBold
                    faint:(BOOL)isFaint
             isBackground:(BOOL)isBackground
       useCustomBoldColor:(BOOL)useCustomBoldColor
             brightenBold:(BOOL)brightenBold {
    iTermColorMapKey key = [self keyForColor:theIndex
                                       green:green
                                        blue:blue
                                   colorMode:theMode
                                        bold:isBold
                                isBackground:isBackground
                          useCustomBoldColor:useCustomBoldColor
                                brightenBold:brightenBold];
    NSColor *color  = [self colorForKey:key];;
    if (!isBackground && isFaint) {
        color = [color colorWithAlphaComponent:0.5];
    }
    return color;
}

- (iTermColorMap *)copy {
    return [self copyWithZone:nil];
}

- (id)copyWithZone:(NSZone *)zone {
    iTermColorMap *other = [[iTermColorMap alloc] init];
    if (!other) {
        return nil;
    }

    other->_backgroundBrightness = _backgroundBrightness;

    memmove(other->_lastTextComponents, _lastTextComponents, sizeof(_lastTextComponents));
    other->_lastTextColor = _lastTextColor;

    memmove(other->_lastBackgroundComponents, _lastBackgroundComponents, sizeof(_lastBackgroundComponents));
    other->_lastBackgroundColor = _lastBackgroundColor;

    other->_dimOnlyText = _dimOnlyText;
    other->_dimmingAmount = _dimmingAmount;

    other->_mutingAmount = _mutingAmount;

    other->_minimumContrast = _minimumContrast;

    other->_delegate = self.delegate;

    other->_map = [_map mutableCopy];

    other->_fastMap = [_fastMap mutableCopy];
    other->_useSeparateColorsForLightAndDarkMode = _useSeparateColorsForLightAndDarkMode;
    other->_darkMode = _darkMode;
    other->_faintTextAlpha = _faintTextAlpha;

    return other;
}

- (iTermColorMapKey)keyForSystemMessageForBackground:(BOOL)background {
    const vector_float4 color = [self fastColorForKey:kColorMapBackground];
    const float brightness = SIMDPerceivedBrightness(color);
    const float magnitude = background ? 0.15 : 0.4;
    const float sign = brightness > 0.5 ? -1 : 1;
    const double delta = magnitude * sign;
    const int value = floor((brightness + delta) * 255);
    return [iTermColorMap keyFor8bitRed:value green:value blue:value];
}

- (iTermColorMapKey)keyForColor:(int)color
                          green:(int)green
                           blue:(int)blue
                      colorMode:(ColorMode)mode
                           bold:(BOOL)isBold
                   isBackground:(BOOL)isBackground
             useCustomBoldColor:(BOOL)useCustomBoldColor
                   brightenBold:(BOOL)brightenBold {
    BOOL isBackgroundForDefault = isBackground;
    switch (mode) {
        case ColorModeAlternate:
            switch (color) {
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
                case ALTSEM_SYSTEM_MESSAGE:
                    return [self keyForSystemMessageForBackground:isBackground];
                case ALTSEM_REVERSED_DEFAULT:
                    isBackgroundForDefault = !isBackgroundForDefault;
                    // Fall through.
                case ALTSEM_DEFAULT:
                    if (isBackgroundForDefault) {
                        return kColorMapBackground;
                    } else {
                        if (isBold && useCustomBoldColor) {
                            return kColorMapBold;
                        } else {
                            return kColorMapForeground;
                        }
                    }
            }
            break;
        case ColorMode24bit:
            return [iTermColorMap keyFor8bitRed:color green:green blue:blue];
        case ColorModeNormal:
            // Render bold text as bright. The spec (ECMA-48) describes the intense
            // display setting (esc[1m) as "bold or bright". We make it a
            // preference.
            if (isBold &&
                brightenBold &&
                (color < 8) &&
                !isBackground) { // Only colors 0-7 can be made "bright".
                color |= 8;  // set "bright" bit.
            }
            return kColorMap8bitBase + (color & 0xff);

        case ColorModeInvalid:
            return kColorMapInvalid;
    }
    ITAssertWithMessage(ok, @"Bogus color mode %d", (int)mode);
    return kColorMapInvalid;
}

- (id<iTermColorMapReading>)sanitizingAdapter {
    if (!_sanitizingAdapter) {
        _sanitizingAdapter = [[iTermColorMapSanitizingAdapter alloc] initWithSource:self];
    }
    return _sanitizingAdapter;
}

- (VT100SavedColorsSlot *)savedColorsSlot {
    DLog(@"begin");
    return [[VT100SavedColorsSlot alloc] initWithTextColor:[self colorForKey:kColorMapForeground]
                                            backgroundColor:[self colorForKey:kColorMapBackground]
                                         selectionTextColor:[self colorForKey:kColorMapSelectedText]
                                   selectionBackgroundColor:[self colorForKey:kColorMapSelection]
                                       indexedColorProvider:^NSColor *(NSInteger index) {
        return [self colorForKey:kColorMap8bitBase + index] ?: [NSColor clearColor];
    }];
}

@end

@interface iTermColorMapSanitizingAdapterImpl: NSObject
@end

@implementation iTermColorMapSanitizingAdapterImpl {
    __weak id<iTermColorMapDelegate> _delegate;
    __weak iTermColorMap *_source;
}

- (instancetype)initWithSource:(iTermColorMap *)source {
    self = [super init];
    if (self) {
        _source = source;
    }
    return self;
}

- (id<iTermColorMapDelegate>)delegate {
    return _delegate;
}

- (void)setDelegate:(id<iTermColorMapDelegate>)delegate {
    _delegate = delegate;
}

- (id)copyWithZone:(NSZone *)zone {
    return [_source copyWithZone:zone];
}

@end

// Proxies calls to iTermColorMap but maintains a separate delegate. This is
// useful while main & mutation queues are joined.
@implementation iTermColorMapSanitizingAdapter {
    iTermColorMapSanitizingAdapterImpl *_impl;
    __weak iTermColorMap *_source;
}

@dynamic dimOnlyText;
@dynamic dimmingAmount;
@dynamic faintTextAlpha;
@dynamic mutingAmount;
@dynamic minimumContrast;
@dynamic useSeparateColorsForLightAndDarkMode;
@dynamic darkMode;
@dynamic generation;

- (instancetype)initWithSource:(iTermColorMap *)source {
    _impl = [[iTermColorMapSanitizingAdapterImpl alloc] initWithSource:source];
    _impl.delegate = source.delegate;
    _source = source;
    return self;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([_impl respondsToSelector:aSelector]) {
        return _impl;
    }
    return _source;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [_impl respondsToSelector:aSelector] || [_source respondsToSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [_source methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    anInvocation.target = [_impl respondsToSelector:anInvocation.selector] ? _impl : _source;
    [anInvocation invoke];
}

@end

