#import "CPKColorWell.h"
#import "CPKPopover.h"
#import "NSObject+CPK.h"

@interface CPKColorWellView : CPKSwatchView

/** Block invoked when the user changes the color. */
@property(nonatomic, copy) void (^colorDidChange)(NSColor *);

/** User can adjust alpha value. */
@property(nonatomic, assign) BOOL alphaAllowed;

/** Color well is disabled? */
@property(nonatomic, assign) BOOL disabled;

@end

@interface CPKColorWellView() <NSPopoverDelegate>
@property(nonatomic) BOOL open;
@property(nonatomic) CPKPopover *popover;
@end

@implementation CPKColorWellView

- (void)awakeFromNib {
    self.cornerRadius = 3;
    self.open = NO;
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (!_disabled && theEvent.clickCount == 1) {
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
}

- (void)setOpen:(BOOL)open {
    _open = open;
    [self updateBorderColor];
}

- (void)updateBorderColor {
    if (self.disabled) {
        self.borderColor = [NSColor grayColor];
    } else if (self.open) {
        self.borderColor = [NSColor whiteColor];
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
    self.open = NO;
    self.popover = nil;
}

@end

@implementation CPKColorWell {
  CPKColorWellView *_view;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  return [super initWithCoder:coder];
}

- (void)awakeFromNib {
  _view = [[CPKColorWellView alloc] initWithFrame:self.bounds];
  [self addSubview:_view];
  _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.autoresizesSubviews = YES;
  _view.alphaAllowed = _alphaAllowed;
  __weak __typeof(self) weakSelf = self;
  _view.colorDidChange = ^(NSColor *color) {
    [weakSelf sendAction:weakSelf.action to:weakSelf.target];
  };
}

- (NSColor *)color {
  return _view.color;
}

- (void)setColor:(NSColor *)color {
  _view.color = color;
}

- (void)setAlphaAllowed:(BOOL)alphaAllowed {
  _alphaAllowed = alphaAllowed;
  _view.alphaAllowed = alphaAllowed;
}

- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  _view.disabled = !enabled;
}

@end
