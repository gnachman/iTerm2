//
//  RoundedRectView.m
//  iTerm
//
//  Created by George Nachman on 3/13/13.
//
//

#import "RoundedRectView.h"

@implementation RoundedRectView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // TODO(georgen): Make these values settable
        color_ = [[[NSColor darkGrayColor] colorWithAlphaComponent:0.8] retain];
        borderColor_ = [[NSColor whiteColor] retain];
    }
    
    return self;
}

- (void)dealloc {
    [color_ release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor clearColor] set];
    NSRectFill(dirtyRect);

    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 10;
    NSRect rect = self.bounds;
    // Add a half pixel or else the corners look too thick.
    rect.origin.x += 0.5;
    rect.origin.y += 0.5;
    rect.size.width -= 1;
    rect.size.height -= 1;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect
                                                         xRadius:radius
                                                         yRadius:radius];
    [color_ set];
    [path fill];
    [borderColor_ set];
    [path stroke];
    [super drawRect:dirtyRect];
}

@end
