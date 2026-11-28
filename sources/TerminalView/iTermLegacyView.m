//
//  iTermLegacyView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/5/21.
//

#import "iTermLegacyView.h"

@implementation iTermLegacyView

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    [self.delegate legacyView:self drawRect:dirtyRect];
}

- (BOOL)isFlipped {
    return YES;
}

// This view draws only until the GPU renderer has a frame to show, but its layer would keep the
// drawing (which AppKit records as a display list with many small allocations) for as long as the
// session lives.
- (void)setHidden:(BOOL)hidden {
    const BOOL changed = (hidden != self.isHidden);
    [super setHidden:hidden];
    if (!changed) {
        return;
    }
    if (hidden) {
        self.layer.contents = nil;
    } else {
        [self setNeedsDisplay:YES];
    }
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
}

@end
