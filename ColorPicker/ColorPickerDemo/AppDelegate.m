#import "AppDelegate.h"
#import "ColorPicker.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSColorWell *nativeColorWell;
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
    self.colorWell.noColorAllowed = YES;
    self.colorWell.colorSpace = [NSColorSpace sRGBColorSpace];

    self.continuousColorWell.color = [NSColor blackColor];
    self.continuousColorWell.noColorAllowed = YES;
    self.continuousColorWell.target = self;
    self.continuousColorWell.action = @selector(colorDidChange:);
    self.continuousColorWell.colorSpace = [NSColorSpace sRGBColorSpace];

    self.p3ColorWell.color = [NSColor blackColor];
    self.p3ColorWell.target = self;
    self.p3ColorWell.action = @selector(colorDidChange:);
    self.p3ColorWell.continuous = NO;
    self.p3ColorWell.noColorAllowed = YES;
    self.p3ColorWell.colorSpace = [NSColorSpace displayP3ColorSpace];

    self.p3ContinuousColorWell.color = [NSColor blackColor];
    self.p3ContinuousColorWell.noColorAllowed = YES;
    self.p3ContinuousColorWell.target = self;
    self.p3ContinuousColorWell.action = @selector(colorDidChange:);
    self.p3ContinuousColorWell.colorSpace = [NSColorSpace displayP3ColorSpace];

    // This opens the popover from the left side even though the well is on the right.
    NSRect frame = NSMakeRect([self.window.contentView frame].size.width - 60, 10, 50, 25);
    const BOOL useSRGB = NO;
    NSColorSpace *colorSpace = useSRGB ? [NSColorSpace sRGBColorSpace] : [NSColorSpace displayP3ColorSpace];
    CustomWell *customWell = [[CustomWell alloc] initWithFrame:frame
                                                    colorSpace:colorSpace];
    [self.window.contentView addSubview:customWell];
}

- (IBAction)colorDidChange:(id)sender {
    self.loremIpsum.textColor = [sender color];
}

@end
