//
//  iTermProgressIndicator.m
//  iTerm
//
//  Created by George Nachman on 4/26/14.
//
//

#import "iTermProgressIndicator.h"

@implementation iTermProgressIndicator

- (void)drawRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        [[[NSColor textBackgroundColor] colorWithAlphaComponent:0.8] set];
    } else {
        [[NSColor colorWithCalibratedWhite:0.8 alpha:1] set];
    }
    NSRectFill(self.bounds);

    [[NSColor colorWithCalibratedRed:0.5 green:0.7 blue:1.0 alpha:1.0] set];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width * self.fraction, self.bounds.size.height));
}

@end

