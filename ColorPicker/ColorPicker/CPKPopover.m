#import "CPKPopover.h"
#import "CPKLogging.h"
#import "CPKMainViewController.h"

@interface CPKPopover() <NSPopoverDelegate>
@property(nonatomic) CPKMainViewController *mainViewController;
@end

@implementation CPKPopover

+ (instancetype)presentRelativeToRect:(NSRect)positioningRect
                               ofView:(NSView *)positioningView
                        preferredEdge:(NSRectEdge)preferredEdge
                         initialColor:(NSColor *)color
                           colorSpace:(NSColorSpace *)colorSpace
                              options:(CPKMainViewControllerOptions)options
                   selectionDidChange:(void (^)(NSColor *))block
                 useSystemColorPicker:(void (^)(void))useSystemColorPicker {
    CPKPopover *popover = [[CPKPopover alloc] init];
    __weak __typeof(popover) weakPopover = popover;
    popover.mainViewController = [[CPKMainViewController alloc] initWithBlock:block
                                                         useSystemColorPicker:useSystemColorPicker
                                                                        color:color
                                                                      options:options
                                                                   colorSpace:colorSpace];
    popover.mainViewController.colorSpaceDidChangeBlock = ^(NSColorSpace *newColorSpace) {
        if (weakPopover.colorSpaceDidChange) {
            weakPopover.colorSpaceDidChange(newColorSpace);
        }
    };
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
    CPKLog(@"CPKPopover.setSelectedColor:%@", selectedColor);
    [self.mainViewController selectColor:selectedColor];
}

- (NSColorSpace *)colorSpace {
    NSAssert(self.mainViewController != nil, @"mainViewController is nil in colorSpace getter");
    NSColorSpace *result = self.mainViewController.colorSpace;
    NSAssert(result != nil, @"mainViewController.colorSpace is nil in popover colorSpace getter");
    return result;
}

- (void)setColorSpace:(NSColorSpace *)colorSpace {
    self.mainViewController.colorSpace = colorSpace;
    if (self.colorSpaceDidChange) {
        self.colorSpaceDidChange(colorSpace);
    }
}

#pragma mark - NSPopoverDelegate

- (void)popoverWillClose:(NSNotification *)notification {
    if (self.willClose) {
        _closing = YES;
        self.willClose();
    }
}

@end
