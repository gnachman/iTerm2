#import "CPKColorWell.h"
#import "CPKPopover.h"
#import "NSObject+CPK.h"

@interface CPKColorWell() <NSPopoverDelegate>
@property(nonatomic) BOOL open;
@property(nonatomic) CPKPopover *popover;
@end

@implementation CPKColorWell

- (void)awakeFromNib {
    self.cornerRadius = 3;
    self.open = NO;
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (!_disabled && !self.open && theEvent.clickCount == 1) {
        [self openPopOver];
    }
}

- (void)openPopOver {
    __weak __typeof(self) weakSelf = self;
    self.popover =
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
    self.popover.delegate = self;
}

- (void)setOpen:(BOOL)open {
    _open = open;
    [self updateBorderColor];
}

- (void)updateBorderColor {
    if (self.disabled) {
        self.borderColor = [NSColor grayColor];
    } else if (self.open) {
        self.borderColor = [NSColor lightGrayColor];
    } else {
        self.borderColor = [NSColor darkGrayColor];
    }
    [self setNeedsDisplay:YES];
}

- (void)setDisabled:(BOOL)disabled {
    _disabled = disabled;
    [self updateBorderColor];
    if (disabled && self.popover) {
        [self.popover performClose:self];
    }
}

#pragma mark - NSPopoverDelegate

- (void)popoverWillClose:(NSNotification *)notification {
    if (self.popoverWillClose) {
        self.popoverWillClose(self.color);
    }
    self.open = NO;
    self.popover = nil;
}

@end
