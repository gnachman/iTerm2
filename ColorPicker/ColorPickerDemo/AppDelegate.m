#import "AppDelegate.h"
#import "ColorPicker.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSColorWell *nativeColorWell;
@property (nonatomic) CPKMainViewController *viewController;
@end

@interface CustomWell : CPKColorWell
@end

@implementation CustomWell

- (NSView *)presentingView {
    return self.window.contentView;
}

- (NSRect)presentationRect {
    return NSMakeRect(0, 0, 1, 1);
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.colorWell.color = [NSColor blackColor];
    self.colorWell.target = self;
    self.colorWell.action = @selector(colorDidChange:);
    self.colorWell.continuous = NO;

    self.viewController = [[CPKMainViewController alloc] initWithBlock:^(NSColor *color) {
        self.loremIpsum.textColor = color;
    }
                                                                 color:[NSColor blackColor]
                                                          alphaAllowed:YES];
    [self.window.contentView addSubview:self.viewController.view];
    NSRect frame = self.viewController.view.frame;
    frame.origin.y = 0;
    self.viewController.view.frame = frame;

    // This opens the popover from the left side even though the well is on the right.
    frame = NSMakeRect([self.window.contentView frame].size.width - 50, 0, 50, 25);
    CustomWell *customWell = [[CustomWell alloc] initWithFrame:frame];
    [self.window.contentView addSubview:customWell];
}

- (void)colorDidChange:(id)sender {
    self.loremIpsum.textColor = [sender color];
}

@end
