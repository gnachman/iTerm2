//
//  iTermColorMap.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "iTermColorMap.h"
#import "DebugLogging.h"
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
// This value plus 0...255 are accepted.
const int kColorMap8bitBase = 9;
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
@property(nonatomic, retain) NSMutableDictionary *dimmedColorCache;
@property(nonatomic, retain) NSMutableDictionary *map;
@property(nonatomic, retain) NSMutableDictionary *mutedMap;
@end

@implementation iTermColorMap {
    double _backgroundBrightness;
    CGFloat _backgroundRed;
    CGFloat _backgroundGreen;
    CGFloat _backgroundBlue;

    // Previous contrasting color returned
    NSColor *memoizedContrastingColor_;
    double memoizedMainRGB_[4];  // rgba for "main" color memoized.
    double memoizedOtherRGB_[3];  // rgb for "other" color memoized.
}

+ (iTermColorMapKey)keyFor8bitRed:(int)red
                            green:(int)green
                             blue:(int)blue {
    return kColorMap24bitBase + ((red & 0xff) << 16) + ((green & 0xff) << 8) + (blue & 0xff);
}

- (id)init {
    self = [super init];
    if (self) {
        _dimmedColorCache = [[NSMutableDictionary alloc] init];
        _map = [[NSMutableDictionary alloc] init];
        _mutedMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_dimmedColorCache release];
    [_map release];
    [_mutedMap release];
    [memoizedContrastingColor_ release];
    [super dealloc];
}

- (void)setMinimumContrast:(double)value {
    DLog(@"iTermColorMap: set minimum contrast to %f from %@", value, [NSThread callStackSymbols]);
    _minimumContrast = value;
    [memoizedContrastingColor_ release];
    memoizedContrastingColor_ = nil;
    [self invalidateCache];
}

- (void)setDimmingAmount:(double)dimmingAmount {
    DLog(@"iTermColorMap: set dimming amount to %f from %@", dimmingAmount, [NSThread callStackSymbols]);
    _dimmingAmount = dimmingAmount;
    [self invalidateCache];
    [_delegate colorMap:self dimmingAmountDidChangeTo:dimmingAmount];
}

- (void)setMutingAmount:(double)mutingAmount {
   DLog(@"iTermColorMap: set muting amount to %f from %@", mutingAmount, [NSThread callStackSymbols]);
    _mutingAmount = mutingAmount;
    [_mutedMap removeAllObjects];
    [_delegate colorMap:self mutingAmountDidChangeTo:mutingAmount];
}

- (void)setColor:(NSColor *)theColor forKey:(iTermColorMapKey)theKey {
    if (!theColor || theColor == _map[@(theKey)] || theKey >= kColorMap24bitBase) {
        return;
    }
    DLog(@"Set key %d to %@", (int)theKey, theColor);
    if (theKey == kColorMapBackground) {
        _backgroundRed = [theColor redComponent];
        _backgroundGreen = [theColor greenComponent];
        _backgroundBlue = [theColor blueComponent];
    }
    theColor = [theColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    _map[@(theKey)] = theColor;
    _mutedMap[@(theKey)] = [theColor colorMutedBy:_mutingAmount
                                          towards:_map[@(kColorMapBackground)]];
    [_dimmedColorCache removeAllObjects];
    if (theKey == kColorMapBackground) {
        _backgroundBrightness = [theColor perceivedBrightness];
    }
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
        NSColor *result = _map[@(theKey)];
        if (!result) {
            result = [NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1];
        }
        return result;
    }
}

- (NSColor *)mutedColorForKey:(iTermColorMapKey)theKey {
    DLog(@"Look up muted color for key %d", theKey);
    if (_mutingAmount == 0) {
        DLog(@"No muting, just use real color");
        return [self colorForKey:theKey];
    } else {
            if (theKey == kColorMapInvalid) {
                return [NSColor redColor];
            } else if (theKey >= kColorMap24bitBase) {
                int n = theKey - kColorMap24bitBase;
                int blue = (n & 0xff);
                int green = (n >> 8) & 0xff;
                int red = (n >> 16) & 0xff;
                NSColor *result = [NSColor colorWith8BitRed:red
                                           green:green
                                            blue:blue
                                          muting:_mutingAmount
                                   backgroundRed:_backgroundRed
                                 backgroundGreen:_backgroundGreen
                                  backgroundBlue:_backgroundBlue];
                DLog(@"The muted version of 24-bit color [%d,%d,%d] is %@", red, green, blue, result);
                return result;
            } else {
                NSColor *result = nil;
                if (!result) {
                    result = [_map[@(theKey)] colorMutedBy:_mutingAmount
                                                   towards:_map[@(kColorMapBackground)]];
                    DLog(@"Return %@ muted by %f toward %@, which is %@", _map[@(theKey)], _mutingAmount, _map[@(kColorMapBackground)], result);
                  _mutedMap[@(theKey)] = result;
                }
                return result;
            }
    }
}

- (NSColor *)dimmedColorForKey:(iTermColorMapKey)theKey {
    if (_dimmingAmount == 0) {
        DLog(@"Dimming amount is 0 so use muted color");
        return [self mutedColorForKey:theKey];
    }
    NSColor *theColor = _dimmedColorCache[@(theKey)];
    DLog(@"    Pick color from cache: %@", theColor);
    if (!theColor) {
        DLog(@"    Not in cache. Get dimmed version of %@", [self colorForKey:theKey]);
        theColor = [self dimmedColorForColor:[self colorForKey:theKey]];
        DLog(@"      The dimmed version is %@", theColor);
        if (theKey < kColorMap24bitBase) {
            // We don't cache dimmed versions of 24 bit colors because it would get too big.
            _dimmedColorCache[@(theKey)] = theColor;
        }
    }
    return theColor;
}

- (void)invalidateCache {
    DLog(@"Invalidate cache from %@", [NSThread callStackSymbols]);
    [_dimmedColorCache removeAllObjects];
}

- (NSColor *)dimmedColorForColor:(NSColor *)theColor {
    if (_dimOnlyText) {
        return [theColor colorDimmedBy:_dimmingAmount towardsGrayLevel:_backgroundBrightness];
    } else {
        return [theColor colorDimmedBy:_dimmingAmount towardsGrayLevel:0.5];
    }
}

- (void)setDimOnlyText:(BOOL)dimOnlyText {
    _dimOnlyText = dimOnlyText;
    [_delegate colorMap:self dimmingAmountDidChangeTo:_dimmingAmount];
}

- (NSColor*)color:(NSColor*)mainColor withContrastAgainst:(NSColor*)otherColor
{
    double rgb[4];
    rgb[0] = [mainColor redComponent];
    rgb[1] = [mainColor greenComponent];
    rgb[2] = [mainColor blueComponent];
    rgb[3] = [mainColor alphaComponent];

    double orgb[3];
    orgb[0] = [otherColor redComponent];
    orgb[1] = [otherColor greenComponent];
    orgb[2] = [otherColor blueComponent];

    if (!memoizedContrastingColor_ ||
        memcmp(rgb, memoizedMainRGB_, sizeof(rgb)) ||
        memcmp(orgb, memoizedOtherRGB_, sizeof(orgb))) {
        // We memoize the last returned value not so much for performance as for
        // consistency. It ensures that two consecutive calls for the same color
        // will return the same pointer. See the note at the call site in
        // _constructRuns:theLine:...matches:.
        [memoizedContrastingColor_ autorelease];
        CGFloat backgroundComponents[3] = { _backgroundRed, _backgroundGreen, _backgroundBlue };
        NSColor *contrastingColor = [NSColor colorWithComponents:rgb
                                   withContrastAgainstComponents:orgb
                                                 minimumContrast:_minimumContrast
                                                         mutedBy:_mutingAmount
                                                towardComponents:backgroundComponents];
        DLog(@"Compute color with minimum contrast %f, muting %f", _minimumContrast, _mutingAmount);
        NSColor *dimmedContrastingColor = [self dimmedColorForColor:contrastingColor];
        memoizedContrastingColor_ = [dimmedContrastingColor retain];
        if (!memoizedContrastingColor_) {
            memoizedContrastingColor_ = [mainColor retain];
        }
        memmove(memoizedMainRGB_, rgb, sizeof(rgb));
        memmove(memoizedOtherRGB_, orgb, sizeof(orgb));
    }
    return memoizedContrastingColor_;
}
@end
