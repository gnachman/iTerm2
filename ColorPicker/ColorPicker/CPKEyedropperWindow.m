#import "CPKEyedropperWindow.h"
#import "CPKEyedropperView.h"
#import "CPKScreenshot.h"
#import "NSColor+CPK.h"
#import "NSColorSpace+CPK.h"

// Size in points of one edge of the window. It is square.
const CGFloat kSize = 200;

// How often to update the view for the current mouse coordinates
const NSTimeInterval kUpdateInterval = 1.0 / 60.0;

@interface CPKEyedropperWindow ()
@property(nonatomic) NSMutableArray<CPKScreenshot *> *screenshots;
@property(nonatomic) NSColor *selectedColor;
@property(nonatomic) CPKEyedropperView *eyedropperView;
@property(nonatomic, strong) NSWindow *previousKeyWindow;

- (void)accept;
- (void)dismiss;
@end

@implementation CPKEyedropperWindow {
    NSColorSpace *_colorSpace;
}

// Gives the origin for the window.
+ (NSPoint)origin {
    NSPoint origin = [NSEvent mouseLocation];
    origin.x -= kSize / 2;
    origin.y -= kSize / 2;
    return origin;
}

+ (BOOL)canTakeScreenshot {
    if (@available(macOS 10.16, *)) {
      return CGPreflightScreenCaptureAccess();
    }
    return YES;
}

+ (void)complainAboutScreenCapturePermission {
    if (@available(macOS 10.15, *)) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Permission Needed";
        alert.informativeText = @"The eyedropper needs Screen Recording permission to work.";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            CGRequestScreenCaptureAccess();
            NSURL *URL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
            [[NSWorkspace sharedWorkspace] openURL:URL];
        }
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Permission Needed";
    alert.informativeText = [NSString stringWithFormat:@"The eyedropper requires screen recording permission.\n\nYou can enable this by adding %@ to System Preferences > Security & Privacy > Privacy > Screen Recording.", [NSRunningApplication currentApplication].localizedName];
    [alert addButtonWithTitle:@"Open System Preferences"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSURL *URL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
        [[NSWorkspace sharedWorkspace] openURL:URL];
    }
}

+ (void)pickColorWithCompletion:(void (^)(NSColor *color, NSColorSpace *colorSpace))completion {
    if (![self canTakeScreenshot]) {
        [self complainAboutScreenCapturePermission];
        if (![self canTakeScreenshot]) {
            return;
        }
    }
    NSPoint origin = [CPKEyedropperWindow origin];
    NSRect frame = NSMakeRect(origin.x, origin.y, kSize, kSize);
    CPKEyedropperWindow *eyedropperWindow =
            [[CPKEyedropperWindow alloc] initWithContentRect:frame
                                           styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    eyedropperWindow->_colorSpace = nil;
    eyedropperWindow.opaque = NO;
    eyedropperWindow.backgroundColor = [NSColor clearColor];
    eyedropperWindow.hasShadow = NO;
    eyedropperWindow.previousKeyWindow = [NSApp keyWindow];
    NSRect rect = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    // Use P3 for display purposes since it has the widest gamut
    eyedropperWindow.eyedropperView = [[CPKEyedropperView alloc] initWithFrame:rect colorSpace:[NSColorSpace displayP3ColorSpace]];
    __weak __typeof(eyedropperWindow) weakWindow = eyedropperWindow;
    eyedropperWindow.eyedropperView.click = ^() {
        [weakWindow accept];
        [weakWindow dismiss];
    };
    eyedropperWindow.eyedropperView.cancel = ^() {
        [weakWindow dismiss];
    };
    eyedropperWindow.contentView = eyedropperWindow.eyedropperView;

    // It takes a spin of the mainloop for this to take effect
    eyedropperWindow.level = NSMainMenuWindowLevel + 1;
    [eyedropperWindow makeKeyAndOrderFront:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        [eyedropperWindow finishPickingColorWithCompletion:completion];
    });
}

- (void)finishPickingColorWithCompletion:(void (^)(NSColor *color, NSColorSpace *colorSpace))completion {
    [[NSCursor crosshairCursor] push];
    [self doPick];
    [[NSCursor crosshairCursor] pop];
    NSColor *selectedColor = [self selectedColor];
    if (@available(macOS 10.13, *)) {
        [self orderOut:nil];
    }
    if (selectedColor.alphaComponent == 0) {
        completion(nil, nil);
    } else {
        completion(selectedColor, _colorSpace);
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)grabScreenshots {
    self.screenshots = [NSMutableArray array];
    for (NSScreen *screen in [NSScreen screens]) {
        // Pass nil for colorSpace to capture in the screen's native colorspace
        CPKScreenshot *screenshot = [CPKScreenshot grabFromScreen:screen colorSpace:nil];
        [self.screenshots addObject:screenshot];
    }
}

- (void)doPick {
    [self grabScreenshots];

    NSModalSession session = [NSApp beginModalSessionForWindow:self];
    NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop];
    // This keeps the runloop blocking when nothing else is going on.
    NSPort *port = [NSMachPort port];
    [myRunLoop addPort:port
               forMode:NSDefaultRunLoopMode];
    NSTimer *timer = [NSTimer timerWithTimeInterval:kUpdateInterval
                                             target:self
                                           selector:@selector(sampleForPick:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(stopPicking:)
               name:NSApplicationDidChangeScreenParametersNotification
             object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(stopPicking:)
                                                 name:NSApplicationWillResignActiveNotification
                                               object:nil];

    [myRunLoop addTimer:timer forMode:NSDefaultRunLoopMode];
    while (1) {
        if ([NSApp runModalSession:session] != NSModalResponseContinue) {
            break;
        }
        [myRunLoop runMode:NSDefaultRunLoopMode
                beforeDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateInterval]];
    }
    [timer invalidate];
    [NSApp endModalSession:session];
}

- (void)setSelectedColor:(NSColor *)selectedColor {
    _selectedColor = selectedColor;
}

- (void)stopPicking:(NSNotification *)notification {
    self.selectedColor = [NSColor clearColor];
    [self dismiss];
}

- (NSInteger)currentScreenIndex {
    NSPoint location = [NSEvent mouseLocation];
    __block NSInteger result = -1;
    [[NSScreen screens] enumerateObjectsUsingBlock:^(NSScreen * _Nonnull screen, NSUInteger idx, BOOL * _Nonnull stop) {
        if (NSPointInRect(location, screen.frame)) {
            result = idx;
            *stop = YES;
        }
    }];
    return result;
}

- (CPKScreenshot *)currentScreenScreenshot {
    NSInteger i = [self currentScreenIndex];
    if (i < 0) {
        return nil;
    }
    return self.screenshots[i];
}

- (NSArray *)colorGrid {
    NSArray *screens = [NSScreen screens];
    NSInteger index = self.currentScreenIndex;
    if (index < 0 || index >= screens.count) {
        return nil;
    }
    NSScreen *screen = screens[index];
    NSPoint location = [NSEvent mouseLocation];
    NSPoint point = NSMakePoint(location.x - screen.frame.origin.x,
                                location.y - screen.frame.origin.y);
    point.y = screen.frame.size.height - point.y;
    point.x *= screen.backingScaleFactor;
    point.y *= screen.backingScaleFactor;

    NSMutableArray *outerArray = [NSMutableArray array];
    const NSInteger radius = 9;
    CPKScreenshot *screenshot = [self currentScreenScreenshot];
    // Use P3 for display since it has the widest gamut
    NSColor *blackColor = [NSColor cpk_colorWithRed:0 green:0 blue:0 alpha:1 colorSpace:[NSColorSpace displayP3ColorSpace]];
    for (NSInteger x = point.x - radius; x <= point.x + radius; x++) {
        NSMutableArray *innerArray = [NSMutableArray array];
        for (NSInteger y = point.y - radius; y <= point.y + radius; y++) {
            NSColor *color = blackColor;
            @try {
                color = [screenshot colorAtX:x y:y];
                if (!color) {
                    color = blackColor;
                }
            }
            @catch (NSException *exception) {
                color = blackColor;
            }
            [innerArray addObject:color];
        }
        [outerArray addObject:innerArray];
    }
    return outerArray;
}

- (void)sampleForPick:(NSTimer *)timer {
    NSArray *grid = [self colorGrid];
    if (!grid) {
        return;
    }
    [self.eyedropperView setColors:grid];

    NSPoint origin = [CPKEyedropperWindow origin];
    NSRect frame = NSMakeRect(origin.x, origin.y, kSize, kSize);
    [self setFrame:frame display:YES];
}

- (void)accept {
    NSPoint location = [NSEvent mouseLocation];
    NSScreen *screen = [[NSScreen screens] objectAtIndex:self.currentScreenIndex];
    NSPoint point = NSMakePoint(location.x - screen.frame.origin.x,
                                location.y - screen.frame.origin.y);
    point.y = screen.frame.size.height - point.y;
    point.x *= screen.backingScaleFactor;
    point.y *= screen.backingScaleFactor;

    CPKScreenshot *screenshot = self.currentScreenScreenshot;
    NSColor *nativeColor = [screenshot colorAtX:point.x y:point.y];
    if (nativeColor) {
        NSColorSpace *nativeColorSpace = screenshot.colorSpace;

        // Map the native colorspace to one of the supported colorspaces
        NSColorSpace *supportedColorSpace = [NSColorSpace cpk_supportedColorSpaceForColorSpace:nativeColorSpace];

        // Convert the color to the supported colorspace
        NSColor *convertedColor = [nativeColor colorUsingColorSpace:supportedColorSpace];

        self.selectedColor = convertedColor;
        _colorSpace = supportedColorSpace;
    } else {
        self.selectedColor = nil;
        self.colorSpace = [NSColorSpace displayP3ColorSpace];
    }
}

- (void)dismiss {
    [NSApp stopModal];
    [_previousKeyWindow makeKeyAndOrderFront:nil];
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

@end
