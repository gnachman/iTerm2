//
//  iTermProgressIndicator.m
//  iTerm
//
//  Created by George Nachman on 4/26/14.
//
//

#import "iTermProgressIndicator.h"

@implementation iTermProgressIndicator

- (BOOL)isOpaque {
    return NO;
}

- (BOOL)lightMode {
    return [[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameAqua];
}

- (BOOL)darkMode {
    return ![self lightMode];
}

- (BOOL)shouldOutline {
    return [self lightMode];
}

- (NSColor *)gray {
    if ([self lightMode]) {
        // Light
        return [NSColor colorWithSRGBRed:221 / 255.0
                                   green:221 / 255.0
                                    blue:221 / 255.0
                                   alpha:1];
    }
    if ([self darkMode]) {
        // Dark
        return [NSColor colorWithSRGBRed:78 / 255.0
                                   green:80 / 255.0
                                    blue:82 / 255.0
                                   alpha:1];
    }
    return [NSColor colorWithCalibratedRed:0.5 green:0.7 blue:1.0 alpha:1.0];
}

- (NSColor *)blue {
    if ([self lightMode]) {
        // Light
        return [NSColor colorWithSRGBRed:59 / 255.0
                                   green:136 / 255.0
                                    blue:253 / 255.0
                                   alpha:1];
    }
    if ([self darkMode]) {
        // Dark
        return [NSColor colorWithSRGBRed:23 / 255.0
                                   green:105 / 255.0
                                    blue:230 / 255.0
                                   alpha:1];
    }
    return [NSColor colorWithCalibratedRed:0.5 green:0.7 blue:1.0 alpha:1.0];
}

- (NSBezierPath *)fullPath {
    const CGFloat r = self.bounds.size.height / 2;
    NSRect rect = NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height);
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:r yRadius:r];
}

- (NSBezierPath *)fractionPath {
    NSRect rect = NSMakeRect(0, 0, self.bounds.size.width * self.fraction, self.bounds.size.height);
    return [NSBezierPath bezierPathWithRect:rect];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFill(self.bounds);

    [[self fullPath] setClip];

    [[self gray] set];
    [[self fullPath] fill];

    [[self blue] set];
    [[self fractionPath] fill];

    if ([self shouldOutline]) {
        [[NSColor colorWithWhite:0 alpha:0.12] set];
        [[self fullPath] stroke];
    }
}

@end

