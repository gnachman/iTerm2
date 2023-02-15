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

+ (iTermCursorNeighbors)neighborsForCursorAtCoord:(VT100GridCoord)cursorCoord
                                         gridSize:(VT100GridSize)gridSize
                                       lineSource:(const screen_char_t *(^NS_NOESCAPE)(int))lineSource {
    iTermCursorNeighbors neighbors;
    memset(&neighbors, 0, sizeof(neighbors));
    NSArray *coords = @[ @[ @0,    @(-1) ],     // Above
                         @[ @(-1), @0    ],     // Left
                         @[ @1,    @0    ],     // Right
                         @[ @0,    @1    ] ];   // Below
    int prevY = -2;

    for (NSArray *tuple in coords) {
        int dx = [tuple[0] intValue];
        int dy = [tuple[1] intValue];
        int x = cursorCoord.x + dx;
        int y = cursorCoord.y + dy;

        const screen_char_t *theLine = nil;

        if (y != prevY) {
            if (y >= 0 && y < gridSize.height) {
                theLine = lineSource(y);
            } else {
                theLine = nil;
            }
        }
        prevY = y;

        int xi = dx + 1;
        int yi = dy + 1;
        if (theLine && x >= 0 && x < gridSize.width) {
            neighbors.chars[yi][xi] = theLine[x];
            neighbors.valid[yi][xi] = YES;
        }

    }
    return neighbors;
}


- (NSColor *)backgroundColorForCharacter:(screen_char_t)screenChar {
    iTermCursorNeighbors neighbors = [self.delegate cursorNeighbors];
    NSColor *bgColor = [self.delegate cursorColorForCharacter:screenChar
                                               wantBackground:NO
                                                        muted:NO];

    NSMutableArray* constraints = [NSMutableArray arrayWithCapacity:2];
    for (int y = 0; y < 3; y++) {
        for (int x = 0; x < 3; x++) {
            if (neighbors.valid[y][x]) {
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
    proposedForeground = [proposedForeground colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
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
