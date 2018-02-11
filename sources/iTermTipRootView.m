//
//  iTermWelcomeRootView.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipRootView.h"

@implementation iTermTipRootView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    [[NSColor clearColor] set];
    NSRectFill(self.bounds);
}

- (BOOL)isFlipped {
  return YES;
}

@end
