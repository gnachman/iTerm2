#import "AppDelegate.h"
#import "ColorPicker.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic) CPKMainViewController *viewController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.colorWell.color = [NSColor blackColor];
    self.colorWell.colorDidChange = ^(NSColor *color) {
        self.loremIpsum.textColor = color;
    };

    self.viewController = [[CPKMainViewController alloc] initWithBlock:^(NSColor *color) {
        self.loremIpsum.textColor = color;
    }
                                                                 color:[NSColor blackColor]
                                                          alphaAllowed:YES];
    [self.window.contentView addSubview:self.viewController.view];
    NSRect frame = self.viewController.view.frame;
    frame.origin.y = 0;
    self.viewController.view.frame = frame;
}


@end
