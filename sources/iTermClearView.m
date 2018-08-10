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
      [self it_commonInit];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
      [self it_commonInit];
  }
  return self;
}

- (void)it_commonInit {
    self.color = [NSColor clearColor];
}

- (void)viewDidMoveToWindow {
    if (@available(macOS 10.14, *)) {
        self.window.backgroundColor = [NSColor clearColor];
    }
    [super viewDidMoveToWindow];
}

- (void)drawRect:(NSRect)dirtyRect {
    return;
}

@end
