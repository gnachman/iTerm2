//
//  iTermColorMap.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "iTermColorMap.h"
#import "iTermSharedColor.h"
#import "ITAddressBookMgr.h"
#import "NSColor+iTerm.h"
#import "NSMutableData+iTerm.h"
#include <unordered_map>
#import <simd/simd.h>


@interface iTermColorMap ()
@property(nonatomic, retain) NSMutableDictionary *map;
@end

@implementation iTermColorMap {
    // Cached values
    double _backgroundBrightness;
    CGFloat _backgroundRed;
    CGFloat _backgroundGreen;
    CGFloat _backgroundBlue;

    // Memoized colors and components
    // Only 3 components are used here, but I'm paranoid screwing up and overflowing.
    vector_float4 _lastTextColorVector;
    NSColor *_lastTextColor;

    vector_float4 _lastBackgroundColorVector;
    NSColor *_lastBackgroundColor;

    std::unordered_map<int, vector_float4> *_fastMap;
    NSMutableData *_serializedData;
}

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue {
    return TrueColorKey(red, green, blue);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _map = [[NSMutableDictionary alloc] init];
        _fastMap = new std::unordered_map<int, vector_float4>();
    }
    return self;
}

- (void)dealloc {
    [_map release];
    [_lastTextColor release];
    [_lastBackgroundColor release];
    delete _fastMap;
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
        _fastMap->erase(theKey);
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
    CGFloat components[4];
    [theColor getComponents:components];

    if (theKey == kColorMapBackground) {
        _backgroundBrightness = [theColor perceivedBrightness];
    }

    _map[@(theKey)] = theColor;
    (*_fastMap)[theKey] = (vector_float4){
        (float)components[0],
        (float)components[1],
        (float)components[2],
        (float)components[3]
   };
    _generation++;
    [_serializedData autorelease];
    _serializedData = nil;
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
        return (*_fastMap)[theKey];
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
                        overBackgroundColor:(NSColor *)backgroundColor {
    if (!textColor) {
        return nil;
    }

    vector_float4 processed = ProcessTextColor(textColor.vector,
                                               backgroundColor.vector,
                                               _minimumContrast,
                                               _mutingAmount,
                                               _dimOnlyText,
                                               _dimmingAmount,
                                               self);
    if (!_lastTextColor || !simd_equal(processed, _lastTextColorVector)) {
        [_lastTextColor autorelease];
        _lastTextColorVector = processed;
        CGFloat components[4] = { processed.x, processed.y, processed.z, processed.w };
        _lastTextColor = [[NSColor colorWithColorSpace:textColor.colorSpace
                                            components:components
                                                 count:4] retain];
    }
    return _lastTextColor;
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
    [self getComponents:mutedRgb
        byAveragingComponents:components
               withComponents:defaultBackgroundComponents
                        alpha:_mutingAmount];
    mutedRgb[3] = components[3];

    return simd_make_float4(mutedRgb[0], mutedRgb[1], mutedRgb[2], components[3]);
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

- (vector_float4)fastProcessedBackgroundColorForBackgroundColor:(vector_float4)backgroundColor {
    vector_float4 defaultBackgroundComponents = (*_fastMap)[kColorMapBackground];
    const vector_float4 mutedRgb = [self fastAverageComponents:backgroundColor with:defaultBackgroundComponents alpha:_mutingAmount];
    vector_float4 grayRgb { 0.5, 0.5, 0.5, 1 };

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

    vector_float4 processed = ProcessBackgroundColor(backgroundColor.vector,
                                                     self,
                                                     _mutingAmount,
                                                     _dimOnlyText,
                                                     _dimmingAmount);
    if (!simd_equal(processed, _lastBackgroundColorVector)) {
        _lastBackgroundColorVector = processed;
        [_lastBackgroundColor autorelease];
        CGFloat components[4] = { processed.x, processed.y, processed.z, processed.w };
        _lastBackgroundColor = [[NSColor colorWithColorSpace:backgroundColor.colorSpace
                                                  components:components
                                                       count:4] retain];
    }
    return _lastBackgroundColor;
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

- (id)copyWithZone:(NSZone *)zone {
    iTermColorMap *other = [[iTermColorMap alloc] init];
    if (!other) {
        return nil;
    }

    other->_backgroundBrightness = _backgroundBrightness;
    other->_backgroundRed = _backgroundRed;
    other->_backgroundGreen = _backgroundGreen;
    other->_backgroundBlue = _backgroundBlue;
    other->_lastTextColorVector = _lastTextColorVector;
    other->_lastTextColor = [_lastTextColor retain];
    other->_lastBackgroundColorVector = _lastBackgroundColorVector;
    other->_lastBackgroundColor = [_lastBackgroundColor retain];

    other->_dimOnlyText = _dimOnlyText;
    other->_dimmingAmount = _dimmingAmount;

    other->_mutingAmount = _mutingAmount;

    other->_minimumContrast = _minimumContrast;

    other->_delegate = _delegate;

    [other->_map release];
    other->_map = [_map mutableCopy];

    delete other->_fastMap;
    other->_fastMap = new std::unordered_map<int, vector_float4>(*_fastMap);

    return other;
}

- (NSData *)serializedData {
    if (!_serializedData) {
        _serializedData = [[NSMutableData uninitializedDataWithLength:kColorMap24bitBase * 4] retain];
        unsigned char *bytes = static_cast<unsigned char *>(_serializedData.mutableBytes);
        for (int i = 0, o = 0; i < kColorMap24bitBase; i++, o += 4) {
            const vector_float4 &color = (*_fastMap)[i];
            bytes[o + 0] = color.x * 255;
            bytes[o + 1] = color.y * 255;
            bytes[o + 2] = color.z * 255;
            bytes[o + 3] = color.w * 255;
        }
    }
    return _serializedData;
}

@end
