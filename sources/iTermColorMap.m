//
//  iTermColorMap.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "iTermColorMap.h"
#import "ITAddressBookMgr.h"
#import "NSColor+iTerm.h"

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

@interface iTermColorMap ()
@property(nonatomic, retain) NSMutableDictionary *map;
@end

@implementation iTermColorMap {
    double _backgroundBrightness;
    CGFloat _backgroundRed;
    CGFloat _backgroundGreen;
    CGFloat _backgroundBlue;

    // Memoized colors and components
    // Only 3 components are used here, but I'm paranoid screwing up and overflowing.
    CGFloat _lastTextComponents[4];
    NSColor *_lastTextColor;

    // This one actually uses four components.
    CGFloat _lastBackgroundComponents[4];
    NSColor *_lastBackgroundColor;
}

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue {
    return kColorMap24bitBase + ((red & 0xff) << 16) + ((green & 0xff) << 8) + (blue & 0xff);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _map = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_map release];
    [_lastTextColor release];
    [_lastBackgroundColor release];
    [super dealloc];
}

- (void)setDimmingAmount:(double)dimmingAmount {
    _dimmingAmount = dimmingAmount;
    [_delegate colorMap:self dimmingAmountDidChangeTo:dimmingAmount];
}

- (void)setMutingAmount:(double)mutingAmount {
    _mutingAmount = mutingAmount;
    [_delegate colorMap:self mutingAmountDidChangeTo:mutingAmount];
}

- (void)setColor:(NSColor *)theColor forKey:(iTermColorMapKey)theKey {
    if (theKey >= kColorMap24bitBase)
        return;

    if (!theColor) {
        [_map removeObjectForKey:@(theKey)];
        return;
    }

    if (theColor == _map[@(theKey)])
        return;

    if (theKey == kColorMapBackground) {
        _backgroundRed = [theColor redComponent];
        _backgroundGreen = [theColor greenComponent];
        _backgroundBlue = [theColor blueComponent];
    }

    theColor = [theColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];

    if (theKey == kColorMapBackground) {
        _backgroundBrightness = [theColor perceivedBrightness];
    }

    _map[@(theKey)] = theColor;

    [_delegate colorMap:self didChangeColorForKey:theKey];
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

- (void)setDimOnlyText:(BOOL)dimOnlyText {
    _dimOnlyText = dimOnlyText;
    [_delegate colorMap:self dimmingAmountDidChangeTo:_dimmingAmount];
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (void)getComponents:(CGFloat *)result
    byAveragingComponents:(CGFloat *)rgb1
       withComponents:(CGFloat *)rgb2
                alpha:(CGFloat)alpha {
    for (int i = 0; i < 3; i++) {
        result[i] = rgb1[i] * (1 - alpha) + rgb2[i] * alpha;
    }
    result[3] = rgb1[3];
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (NSColor *)processedTextColorForTextColor:(NSColor *)textColor
                        overBackgroundColor:(NSColor *)backgroundColor {
    if (!textColor) {
        return nil;
    }
    // Fist apply minimum contrast, then muting, then dimming (as needed).
    CGFloat textRgb[4];
    [textColor getComponents:textRgb];
    CGFloat backgroundRgb[4];
    [backgroundColor getComponents:backgroundRgb];

    CGFloat contrastingRgb[4];
    if (backgroundColor) {
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
    [self getComponents:mutedRgb
        byAveragingComponents:contrastingRgb
               withComponents:defaultBackgroundComponents
                        alpha:_mutingAmount];

    CGFloat dimmedRgb[4];
    CGFloat grayRgb[] = { _backgroundBrightness, _backgroundBrightness, _backgroundBrightness };
    if (!_dimOnlyText) {
        grayRgb[0] = grayRgb[1] = grayRgb[2] = 0.5;
    }
    [self getComponents:dimmedRgb
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
        [_lastTextColor autorelease];
        memmove(_lastTextComponents, dimmedRgb, sizeof(CGFloat) * 3);
        _lastTextColor = [[NSColor colorWithColorSpace:textColor.colorSpace
                                            components:dimmedRgb
                                                 count:4] retain];
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

    CGFloat defaultBackgroundComponents[4];
    [_map[@(kColorMapBackground)] getComponents:defaultBackgroundComponents];

    CGFloat mutedRgb[4];
    [self getComponents:mutedRgb
        byAveragingComponents:components
               withComponents:defaultBackgroundComponents
                        alpha:_mutingAmount];
    mutedRgb[3] = components[3];

    return [NSColor colorWithColorSpace:color.colorSpace
                             components:mutedRgb
                                  count:4];
}

// There is an issue where where the passed-in color can be in a different color space than the
// default background color. It doesn't make sense to combine RGB values from different color
// spaces. The effects are generally subtle.
- (NSColor *)colorByDimmingTextColor:(NSColor *)color {
    if (_dimmingAmount < 0.01) {
        return color;
    }

    CGFloat components[4];
    [color getComponents:components];

    CGFloat defaultBackgroundComponents[4];
    [_map[@(kColorMapBackground)] getComponents:defaultBackgroundComponents];

    CGFloat dimmedRgb[4];
    CGFloat grayRgb[] = { _backgroundBrightness, _backgroundBrightness, _backgroundBrightness };
    if (!_dimOnlyText) {
        grayRgb[0] = grayRgb[1] = grayRgb[2] = 0.5;
    }
    [self getComponents:dimmedRgb
      byAveragingComponents:components
             withComponents:grayRgb
                      alpha:_dimmingAmount];
    dimmedRgb[3] = components[3];

    return [NSColor colorWithColorSpace:color.colorSpace
                             components:dimmedRgb
                                  count:4];
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
    [self getComponents:mutedRgb
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
        [self getComponents:dimmedRgb
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
        [_lastBackgroundColor autorelease];
        memmove(_lastBackgroundComponents, dimmedRgb, sizeof(CGFloat) * 4);
        _lastBackgroundColor = [[NSColor colorWithColorSpace:backgroundColor.colorSpace
                                                  components:dimmedRgb
                                                       count:4] retain];
        return _lastBackgroundColor;
    }
}

- (NSString *)profileKeyForColorMapKey:(int)theKey {
    switch (theKey) {
        case kColorMapForeground:
            return KEY_FOREGROUND_COLOR;
        case kColorMapBackground:
            return KEY_BACKGROUND_COLOR;
        case kColorMapBold:
            return KEY_BOLD_COLOR;
        case kColorMapLink:
            return KEY_LINK_COLOR;
        case kColorMapSelection:
            return KEY_SELECTION_COLOR;
        case kColorMapSelectedText:
            return KEY_SELECTED_TEXT_COLOR;
        case kColorMapCursor:
            return KEY_CURSOR_COLOR;
        case kColorMapCursorText:
            return KEY_CURSOR_TEXT_COLOR;
        case kColorMapUnderline:
            return KEY_UNDERLINE_COLOR;

        case kColorMapAnsiBlack:
            return KEY_ANSI_0_COLOR;
        case kColorMapAnsiRed:
            return KEY_ANSI_1_COLOR;
        case kColorMapAnsiGreen:
            return KEY_ANSI_2_COLOR;
        case kColorMapAnsiYellow:
            return KEY_ANSI_3_COLOR;
        case kColorMapAnsiBlue:
            return KEY_ANSI_4_COLOR;
        case kColorMapAnsiMagenta:
            return KEY_ANSI_5_COLOR;
        case kColorMapAnsiCyan:
            return KEY_ANSI_6_COLOR;
        case kColorMapAnsiWhite:
            return KEY_ANSI_7_COLOR;

        case kColorMapAnsiBlack + kColorMapAnsiBrightModifier:
            return KEY_ANSI_8_COLOR;
        case kColorMapAnsiRed + kColorMapAnsiBrightModifier:
            return KEY_ANSI_9_COLOR;
        case kColorMapAnsiGreen + kColorMapAnsiBrightModifier:
            return KEY_ANSI_10_COLOR;
        case kColorMapAnsiYellow + kColorMapAnsiBrightModifier:
            return KEY_ANSI_11_COLOR;
        case kColorMapAnsiBlue + kColorMapAnsiBrightModifier:
            return KEY_ANSI_12_COLOR;
        case kColorMapAnsiMagenta + kColorMapAnsiBrightModifier:
            return KEY_ANSI_13_COLOR;
        case kColorMapAnsiCyan + kColorMapAnsiBrightModifier:
            return KEY_ANSI_14_COLOR;
        case kColorMapAnsiWhite + kColorMapAnsiBrightModifier:
            return KEY_ANSI_15_COLOR;
    }

    return nil;
}

@end
