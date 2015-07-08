//
//  iTermRoundedCornerScrollView.m
//  iTerm2
//
//  Created by George Nachman on 7/8/15.
//
//

#import "iTermRoundedCornerScrollView.h"

@implementation iTermRoundedCornerScrollView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    [self initializeRoundedCornerScrollView];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    [self initializeRoundedCornerScrollView];
  }
  return self;
}

- (void)initializeRoundedCornerScrollView {
  self.wantsLayer = YES;
  [self makeBackingLayer];
  self.layer.cornerRadius = 4;
  self.borderType = NSNoBorder;
}

@end
