//
//  iTermWelcomeCardActionButton.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardActionButton.h"
#import "iTermTipCardActionButtonCell.h"

@implementation iTermTipCardActionButton

+ (Class)cellClass {
  return [iTermTipCardActionButtonCell class];
}

- (id)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    iTermTipCardActionButtonCell *cell =
        [[[iTermTipCardActionButtonCell alloc] init] autorelease];
    cell.inset = NSMakeSize(10, 5);
    [self setCell:cell];
  }
  return self;
}

- (void)dealloc {
  [_block release];
  [super dealloc];
}

- (void)setTitle:(NSString *)title {
  iTermTipCardActionButtonCell *cell = (iTermTipCardActionButtonCell *)self.cell;
  cell.title = title;
}

- (void)setIcon:(NSImage *)image {
  iTermTipCardActionButtonCell *cell = (iTermTipCardActionButtonCell *)self.cell;
  cell.icon = image;
}

- (NSSize)sizeThatFits:(NSSize)size {
  return NSMakeSize(size.width, 34);
}

- (void)sizeToFit {
  NSRect rect = self.frame;
  rect.size.height = 34;
  self.frame = rect;
}

@end
