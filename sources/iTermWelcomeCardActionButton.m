//
//  iTermWelcomeCardActionButton.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermWelcomeCardActionButton.h"
#import "iTermWelcomeCardActionButtonCell.h"

@implementation iTermWelcomeCardActionButton

+ (Class)cellClass {
  return [iTermWelcomeCardActionButtonCell class];
}

- (id)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    iTermWelcomeCardActionButtonCell *cell =
        [[[iTermWelcomeCardActionButtonCell alloc] init] autorelease];
    cell.inset = NSMakeSize(10, 3);
    [self setCell:cell];
  }
  return self;
}

- (void)dealloc {
  [_block release];
  [super dealloc];
}

- (void)setTitle:(NSString *)title {
  iTermWelcomeCardActionButtonCell *cell = (iTermWelcomeCardActionButtonCell *)self.cell;
  cell.title = title;
}

- (void)setIcon:(NSImage *)image {
  iTermWelcomeCardActionButtonCell *cell = (iTermWelcomeCardActionButtonCell *)self.cell;
  cell.icon = image;
}

- (NSSize)sizeThatFits:(NSSize)size {
  return NSMakeSize(size.width, 30);
}

- (void)sizeToFit {
  NSRect rect = self.frame;
  rect.size.height = 30;
  self.frame = rect;
}

@end
