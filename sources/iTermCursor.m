//
//  iTermCursor.m
//  iTerm2
//
//  Created by George Nachman on 3/13/15.
//
//

#import "iTermCursor.h"
#import "DebugLogging.h"
#import "NSColor+iTerm.h"
#import "iTermAdvancedSettingsModel.h"

@interface iTermUnderlineCursor : iTermCursor
@end

@interface iTermVerticalCursor : iTermCursor
@end

@interface iTermBoxCursor : iTermCursor
@end

@interface iTermCopyModeCursor : iTermCursor
@property (nonatomic) BOOL selecting;
@end

@implementation iTermCursor

+ (iTermCursor *)cursorOfType:(ITermCursorType)theType {
    switch (theType) {
        case CURSOR_UNDERLINE:
            return [[[iTermUnderlineCursor alloc] init] autorelease];

        case CURSOR_VERTICAL:
            return [[[iTermVerticalCursor alloc] init] autorelease];

        case CURSOR_BOX:
            return [[[iTermBoxCursor alloc] init] autorelease];

        default:
            return nil;
    }
}

+ (instancetype)copyModeCursorInSelectionState:(BOOL)selecting {
    iTermCopyModeCursor *cursor = [[[iTermCopyModeCursor alloc] init] autorelease];
    cursor.selecting = selecting;
    return cursor;
}

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
}

- (void)drawOutlineOfRect:(NSRect)cursorRect withColor:(NSColor *)color {
    [[color colorWithAlphaComponent:0.75] set];
    NSRect rect = cursorRect;
    CGFloat frameWidth = 0.5;
    rect.origin.x -= frameWidth;
    rect.origin.y -= frameWidth;
    rect.size.width += frameWidth * 2;
    rect.size.height += frameWidth * 2;
    NSFrameRectWithWidthUsingOperation(rect, 0.5, NSCompositeSourceOver);
}

@end

@implementation iTermUnderlineCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    const CGFloat height = 2;
    NSRect cursorRect = NSMakeRect(rect.origin.x,
                                   rect.origin.y + rect.size.height - height - [iTermAdvancedSettingsModel underlineCursorOffset],
                                   ceil(rect.size.width),
                                   height);
    if (outline) {
        [self drawOutlineOfRect:cursorRect withColor:backgroundColor];
    } else {
        [backgroundColor set];
        NSRectFill(cursorRect);
    }
}

@end

@implementation iTermVerticalCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    NSRect cursorRect = NSMakeRect(rect.origin.x, rect.origin.y, 1, rect.size.height);
    if (outline) {
        [self drawOutlineOfRect:cursorRect withColor:backgroundColor];
    } else {
        [backgroundColor set];
        NSRectFill(cursorRect);
    }
}

@end

@implementation iTermCopyModeCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    const CGFloat heightFraction = 1 / 3.0;
    NSRect cursorRect = NSMakeRect(rect.origin.x - rect.size.width,
                                   rect.origin.y,
                                   rect.size.width * 2,
                                   rect.size.height * heightFraction);

    const CGFloat r = self.selecting ? 2 : 1;
    NSBezierPath *path = [[[NSBezierPath alloc] init] autorelease];
    path = [[[NSBezierPath alloc] init] autorelease];
    [path moveToPoint:NSMakePoint(NSMinX(cursorRect), NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) - r, NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMidX(cursorRect) + r, NSMaxY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMaxX(cursorRect), NSMinY(cursorRect))];
    [path lineToPoint:NSMakePoint(NSMinX(cursorRect), NSMinY(cursorRect))];
    if (self.selecting) {
        [[NSColor colorWithRed:0xc1 / 255.0 green:0xde / 255.0 blue:0xff / 255.0 alpha:1] set];
    } else {
        [[NSColor whiteColor] set];
    }
    [path fill];

    [[NSColor blackColor] set];
    [path stroke];
}

@end

@implementation iTermBoxCursor

- (void)drawWithRect:(NSRect)rect
         doubleWidth:(BOOL)doubleWidth
          screenChar:(screen_char_t)screenChar
     backgroundColor:(NSColor *)backgroundColor
     foregroundColor:(NSColor *)foregroundColor
               smart:(BOOL)smart
             focused:(BOOL)focused
               coord:(VT100GridCoord)coord
             outline:(BOOL)outline {
    assert(!outline);

    // Draw the colored box/frame
    if (smart) {
        iTermCursorNeighbors neighbors = [self.delegate cursorNeighbors];
        backgroundColor = [[self smartCursorColorForChar:screenChar
                                               neighbors:neighbors] colorWithAlphaComponent:1.0];
    }
    [backgroundColor set];
    const BOOL frameOnly = !focused;
    if (frameOnly) {
        NSFrameRect(rect);
        return;
    } else {
        NSRectFill(rect);
    }

    if (screenChar.code) {
        // Draw the character over the cursor.
        CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
        if (smart && focused) {
            [self drawSmartCursorCharacter:screenChar
                               doubleWidth:doubleWidth
                           backgroundColor:backgroundColor
                                       ctx:ctx
                                     coord:coord];
        } else {
            // Non-smart
            [self.delegate cursorDrawCharacterAt:coord
                                     doubleWidth:doubleWidth
                                   overrideColor:foregroundColor
                                         context:ctx
                                 backgroundColor:backgroundColor];
        }
    }
}

- (void)drawSmartCursorCharacter:(screen_char_t)screenChar
                     doubleWidth:(BOOL)doubleWidth
                 backgroundColor:(NSColor *)backgroundColor
                             ctx:(CGContextRef)ctx
                           coord:(VT100GridCoord)coord {
    NSColor *proposedForeground = [self.delegate cursorColorForCharacter:screenChar
                                                          wantBackground:YES
                                                                   muted:NO];
    proposedForeground = [proposedForeground colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSColor *overrideColor = [self overrideColorForSmartCursorWithForegroundColor:proposedForeground
                                                                  backgroundColor:backgroundColor];

    [self.delegate cursorDrawCharacterAt:coord
                             doubleWidth:doubleWidth
                           overrideColor:overrideColor
                                 context:ctx
                         backgroundColor:nil];

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

#pragma mark - Smart cursor color

- (NSColor *)smartCursorColorForChar:(screen_char_t)screenChar
                           neighbors:(iTermCursorNeighbors)neighbors {
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
    return [self.delegate cursorColorByDimmingSmartColor:bgColor];
}

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


@end
