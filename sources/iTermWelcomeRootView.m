//
//  iTermWelcomeRootView.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermWelcomeRootView.h"

@implementation iTermWelcomeRootView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
  [[NSColor clearColor] set];
  NSRectFill(self.bounds);

  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5)
                                                       xRadius:5
                                                       yRadius:5];
  [[[NSColor whiteColor] colorWithAlphaComponent:0.95] set];
  [path fill];
  [[NSColor colorWithCalibratedWhite:0.75 alpha:1] set];
  [path stroke];
}

@end
