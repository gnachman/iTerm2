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
}

@end
