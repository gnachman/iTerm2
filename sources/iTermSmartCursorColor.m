//
//  iTermSmartCursorColor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/28/17.
//

#import "iTermSmartCursorColor.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSColor+iTerm.h"

@implementation iTermSmartCursorColor

- (NSColor *)backgroundColorForCharacter:(screen_char_t)screenChar {
    iTermCursorNeighbors neighbors = [self.delegate cursorNeighbors];
    NSColor *bgColor = [self.delegate cursorColorForCharacter:screenChar
                                               wantBackground:NO
                                                        muted:NO];

    NSMutableArray* constraints = [NSMutableArray arrayWithCapacity:2];
    for (int y = 0; y < 3; y++) {
        for (int x = 0; x < 3; x++) {
            if (neighbors.valid[y][x]) {
                NSLog(@"Background color for dx=%d dy=%d is %@", x-1, y-1, [self backgroundColorForChar:neighbors.chars[y][x]]);
                [constraints addObject:@([self brightnessOfCharBackground:neighbors.chars[y][x]])];
            }
        }
    }
    CGFloat bgBrightness = [bgColor perceivedBrightness];
    if ([self minimumDistanceOf:bgBrightness fromAnyValueIn:constraints] <
        [iTermAdvancedSettingsModel smartCursorColorBgThreshold]) {
        CGFloat b = [self farthestValueFromAnyValueIn:constraints];
        bgColor = [NSColor colorWithCalibratedRed:b green:b blue:b alpha:1];
    }
    return [[self.delegate cursorColorByDimmingSmartColor:bgColor] colorWithAlphaComponent:1];
}

- (NSColor *)textColorForCharacter:(screen_char_t)screenChar
                  regularTextColor:(NSColor *)proposedForeground
              smartBackgroundColor:(NSColor *)backgroundColor {
    proposedForeground = [proposedForeground colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    return [self overrideColorForSmartCursorWithForegroundColor:proposedForeground
                                                backgroundColor:backgroundColor];
}

#pragma mark - Private

// Return the value in 'values' closest to target.
- (CGFloat)minimumDistanceOf:(CGFloat)target fromAnyValueIn:(NSArray*)values {
    CGFloat md = 1;
    for (NSNumber* n in values) {
        CGFloat dist = fabs(target - [n doubleValue]);
        if (dist < md) {
            md = dist;
        }
    }
    return md;
}

// Return the value between 0 and 1 that is farthest from any value in 'constraints'.
- (CGFloat)farthestValueFromAnyValueIn:(NSArray*)constraints {
    if ([constraints count] == 0) {
        return 0;
    }

    NSArray* sortedConstraints = [constraints sortedArrayUsingSelector:@selector(compare:)];
    double minVal = [[sortedConstraints objectAtIndex:0] doubleValue];
    double maxVal = [[sortedConstraints lastObject] doubleValue];

    CGFloat bestDistance = 0;
    CGFloat bestValue = -1;
    CGFloat prev = [[sortedConstraints objectAtIndex:0] doubleValue];
    for (NSNumber* np in sortedConstraints) {
        CGFloat n = [np doubleValue];
        const CGFloat dist = fabs(n - prev) / 2;
        if (dist > bestDistance) {
            bestDistance = dist;
            bestValue = (n + prev) / 2;
        }
        prev = n;
    }
    if (minVal > bestDistance) {
        bestValue = 0;
        bestDistance = minVal;
    }
    if (1 - maxVal > bestDistance) {
        bestValue = 1;
        bestDistance = 1 - maxVal;
    }
    DLog(@"Best distance is %f", (float)bestDistance);

    return bestValue;
}

- (double)brightnessOfCharBackground:(screen_char_t)c {
    return [[self backgroundColorForChar:c] perceivedBrightness];
}

- (NSColor *)backgroundColorForChar:(screen_char_t)c {
    c.bold = NO;
    c.faint = NO;
    return [self.delegate cursorColorForCharacter:c wantBackground:YES muted:YES];
}

- (NSColor *)overrideColorForSmartCursorWithForegroundColor:(NSColor *)proposedForeground
                                            backgroundColor:(NSColor *)backgroundColor {
    CGFloat fgBrightness = [proposedForeground perceivedBrightness];
    CGFloat bgBrightness = [backgroundColor perceivedBrightness];
    const double threshold = [iTermAdvancedSettingsModel smartCursorColorFgThreshold];
    if (fabs(fgBrightness - bgBrightness) < threshold) {
        // Foreground and background are very similar. Just use black and
        // white.
        if (bgBrightness < 0.5) {
            return [self.delegate cursorWhiteColor];
        } else {
            return [self.delegate cursorBlackColor];
        }
    } else {
        return proposedForeground;
    }
}

@end
