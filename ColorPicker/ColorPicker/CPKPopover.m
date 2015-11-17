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
    return [self presentRelativeToRect:positioningRect
                                ofView:positioningView
                         preferredEdge:preferredEdge
                          initialColor:color
                               options:(alphaAllowed ? CPKMainViewControllerOptionsAlpha : 0)
                    selectionDidChange:block
                  useSystemColorPicker:nil];
}

+ (instancetype)presentRelativeToRect:(NSRect)positioningRect
                               ofView:(NSView *)positioningView
                        preferredEdge:(NSRectEdge)preferredEdge
                         initialColor:(NSColor *)color
                         options:(CPKMainViewControllerOptions)options
                   selectionDidChange:(void (^)(NSColor *))block
                 useSystemColorPicker:(void (^)())useSystemColorPicker {
    CPKPopover *popover = [[CPKPopover alloc] init];
    popover.mainViewController = [[CPKMainViewController alloc] initWithBlock:block
                                                         useSystemColorPicker:useSystemColorPicker
                                                                        color:color
                                                                      options:options];
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
