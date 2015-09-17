#import "CPKColorWell.h"
#import "CPKPopover.h"
#import "NSObject+CPK.h"

@interface CPKColorWell() <NSPopoverDelegate>
@property(nonatomic) BOOL open;
@end

@implementation CPKColorWell

- (void)awakeFromNib {
    self.cornerRadius = 3;
    self.open = NO;
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 1) {
        __weak __typeof(self) weakSelf = self;
        CPKPopover *popover =
            [CPKPopover presentRelativeToRect:self.bounds
                                       ofView:self
                                preferredEdge:CGRectMinYEdge
                                 initialColor:self.color
                                 alphaAllowed:self.alphaAllowed
                           selectionDidChange:^(NSColor *color) {
                               weakSelf.color = color;
                               if (weakSelf.colorDidChange) {
                                   weakSelf.colorDidChange(color);
                               }
                               [weakSelf setNeedsDisplay:YES];
                           }];
        self.open = YES;
        popover.delegate = self;
    }
}

- (void)setOpen:(BOOL)open {
    _open = open;
    self.borderColor = open ? [NSColor whiteColor] : [NSColor grayColor];
    [self setNeedsDisplay:YES];
}

#pragma mark - NSPopoverDelegate

- (void)popoverWillClose:(NSNotification *)notification {
    self.open = NO;
}

@end
