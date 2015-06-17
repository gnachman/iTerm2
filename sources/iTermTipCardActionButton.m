//
//  iTermWelcomeCardActionButton.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardActionButton.h"
#import "iTermTipCardActionButtonCell.h"

static const CGFloat kStandardButtonHeight = 34;
@implementation iTermTipCardActionButton {
    CGFloat _desiredHeight;
}

+ (Class)cellClass {
    return [iTermTipCardActionButtonCell class];
}

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        iTermTipCardActionButtonCell *cell =
            [[[iTermTipCardActionButtonCell alloc] init] autorelease];
        _desiredHeight = 34;
        cell.inset = NSMakeSize(10, 5);
        [self setCell:cell];
    }
    return self;
}

- (void)dealloc {
    [_block release];
    [super dealloc];
}

- (NSString *)title {
    iTermTipCardActionButtonCell *cell = (iTermTipCardActionButtonCell *)self.cell;
    return cell.title;
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
    return NSMakeSize(size.width, _desiredHeight);
}

- (void)sizeToFit {
    NSRect rect = self.frame;
    rect.size.height = _desiredHeight;
    self.frame = rect;
}

- (void)setCollapsed:(BOOL)collapsed {
    _desiredHeight = collapsed ? 0 : kStandardButtonHeight;
}

@end
