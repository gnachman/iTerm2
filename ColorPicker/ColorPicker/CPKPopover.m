#import "CPKPopover.h"
#import "CPKMainViewController.h"

@interface CPKPopover()
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
    return popover;
}

- (NSColor *)selectedColor {
    return self.mainViewController.selectedColor;
}

@end
