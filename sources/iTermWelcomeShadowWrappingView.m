//
//  iTermWelcomeShadowWrappingView.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermWelcomeShadowWrappingView.h"

@implementation iTermWelcomeShadowWrappingView

- (void)drawRect:(NSRect)dirtyRect {
  NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
  [dropShadow setShadowColor:[NSColor blackColor]];
  [dropShadow setShadowOffset:NSMakeSize(0, -2.0)];
  [dropShadow setShadowBlurRadius:4.0];
  [dropShadow set];
  NSRectFill(NSInsetRect(self.bounds, 5, 5));

  [super drawRect:dirtyRect];
}

@end
