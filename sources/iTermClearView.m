//
//  iTermClearView.m
//  iTerm2
//
//  Created by George Nachman on 7/8/15.
//
//

#import "iTermClearView.h"

@implementation iTermClearView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.color = [NSColor clearColor];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    self.color = [NSColor clearColor];
  }
  return self;
}

@end
