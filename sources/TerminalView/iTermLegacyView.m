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

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
}

@end
