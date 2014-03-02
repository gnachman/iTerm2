//
//  iTermColorMap.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "iTermColorMap.h"
#import "NSColor+iTerm.h"

const int kColorMapForeground = 0;
const int kColorMapBackground = 1;
const int kColorMapBold = 2;
const int kColorMapSelection = 3;
const int kColorMapSelectedText = 4;
const int kColorMapCursor = 5;
const int kColorMapCursorText = 6;
const int kColorMapInvalid = 7;
// This value plus 0...255 are accepted.
const int kColorMap8bitBase = 8;
// This value plus 0...2^24-1 are accepted as read-only keys. These must be the highest-valued keys.
const int kColorMap24bitBase = kColorMap8bitBase + 256;

@interface iTermColorMap ()
@property(nonatomic, retain) NSMutableDictionary *dimmedColorCache;
@property(nonatomic, retain) NSMutableDictionary *map;
@end

@implementation iTermColorMap {
    double _backgroundBrightness;
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
    }
    return self;
}

- (void)dealloc {
    [_dimmedColorCache release];
    [_map release];
    [super dealloc];
}

- (void)setDimmingAmount:(double)dimmingAmount {
    _dimmingAmount = dimmingAmount;
    [self invalidateCache];
    [_delegate colorMap:self dimmingAmountDidChangeTo:dimmingAmount];
}

- (void)setColor:(NSColor *)theColor forKey:(iTermColorMapKey)theKey {
    if (!theColor || theColor == _map[@(theKey)] || theKey >= kColorMap24bitBase) {
        return;
    }
    theColor = [theColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    _map[@(theKey)] = theColor;
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

- (NSColor *)dimmedColorForKey:(iTermColorMapKey)theKey {
    if (_dimmingAmount == 0) {
        return [self colorForKey:theKey];
    }
    NSColor *theColor = _dimmedColorCache[@(theKey)];
    if (!theColor) {
        theColor = [self dimmedColorForColor:[self colorForKey:theKey]];
        if (theKey < kColorMap24bitBase) {
            // We don't cache dimmed versions of 24 bit colors because it would get too big.
            _dimmedColorCache[@(theKey)] = theColor;
        }
    }
    return theColor;
}

- (void)invalidateCache {
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

@end
