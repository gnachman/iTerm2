//
//  iTermNoColorAccessoryButton.m
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

#import "iTermNoColorAccessoryButton.h"

@implementation iTermNoColorAccessoryButton

- (instancetype)init {
  NSImage *image = [NSImage imageNamed:@"NoColor"];
  static const CGFloat kTopBottomMargin = 8;
  self = [super initWithFrame:NSMakeRect(0, 0, image.size.width, image.size.height + kTopBottomMargin * 2)];
  [self setButtonType:NSMomentaryPushInButton];
  [self setImage:image];
  [self setTarget:nil];
  [self setAction:@selector(noColorChosen:)];
  [self setBordered:NO];
  [[self cell] setHighlightsBy:NSContentsCellMask];
  [self setTitle:@""];
  return self;
}

@end
