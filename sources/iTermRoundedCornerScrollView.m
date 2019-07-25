//
//  iTermRoundedCornerScrollView.m
//  iTerm2
//
//  Created by George Nachman on 7/8/15.
//
//

#import "iTermRoundedCornerScrollView.h"
#import "NSView+iTerm.h"

@implementation iTermRoundedCornerScrollView {
    NSVisualEffectView *_vev;
}

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
    _vev = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    _vev.material = NSVisualEffectMaterialMenu;
    _vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    [self insertSubview:_vev atIndex:0];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    _vev.frame = self.bounds;
}
@end
