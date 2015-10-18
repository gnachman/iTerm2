#import "CPKPopover.h"
#import "CPKMainViewController.h"

@interface CPKPopover() <NSPopoverDelegate>
@property(nonatomic) CPKMainViewController *mainViewController;
@end

@implementation CPKPopover

+ (instancetype)presentRelativeToRect:(NSRect)positioningRect
                               ofView:(NSView *)positioningView
                        preferredEdge:(NSRectEdge)preferredEdge
                         initialColor:(NSColor *)color
                         alphaAllowed:(BOOL)alphaAllowed
                   selectionDidChange:(void (^)(NSColor *))block {
    CPKPopover *popover = [[CPKPopover alloc] init];
    popover.mainViewController = [[CPKMainViewController alloc] initWithBlock:block
                                                                        color:color
                                                                 alphaAllowed:alphaAllowed];
    popover.contentSize = popover.mainViewController.desiredSize;
    popover.behavior = NSPopoverBehaviorSemitransient;
    popover.contentViewController = popover.mainViewController;
    [popover showRelativeToRect:positioningRect
                         ofView:positioningView
                  preferredEdge:preferredEdge];
    // See note in class comment.
    popover.delegate = popover;
    return popover;
}

- (NSColor *)selectedColor {
    return self.mainViewController.selectedColor;
}

- (void)setSelectedColor:(NSColor *)selectedColor {
  [self.mainViewController selectColor:selectedColor];
}

#pragma mark - NSPopoverDelegate

- (void)popoverWillClose:(NSNotification *)notification {
    if (self.willClose) {
        self.willClose();
    }
}

@end
