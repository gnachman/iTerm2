#import "CPKEyedropperWindow.h"
#import "CPKEyedropperView.h"

// Size in points of one edge of the window. It is square.
const CGFloat kSize = 200;

// How often to update the view for the current mouse coordinates
const NSTimeInterval kUpdateInterval = 1.0 / 60.0;

@interface CPKEyedropperWindow ()
@property(nonatomic) NSMutableArray *screenshots;
@property(nonatomic) NSColor *selectedColor;
@property(nonatomic) CPKEyedropperView *eyedropperView;
- (void)stop;
@end

@implementation CPKEyedropperWindow

// Gives the origin for the window.
+ (NSPoint)origin {
    NSPoint origin = [NSEvent mouseLocation];
    origin.x -= kSize / 2;
    origin.y -= kSize / 2;
    return origin;
}

+ (NSColor *)pickColor {
    NSPoint origin = [CPKEyedropperWindow origin];
    NSRect frame = NSMakeRect(origin.x, origin.y, kSize, kSize);
    CPKEyedropperWindow *eyedropperWindow =
            [[CPKEyedropperWindow alloc] initWithContentRect:frame
                                           styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    eyedropperWindow.opaque = NO;
    eyedropperWindow.backgroundColor = [NSColor clearColor];
    eyedropperWindow.hasShadow = NO;
    NSRect rect = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    eyedropperWindow.eyedropperView = [[CPKEyedropperView alloc] initWithFrame:rect];
    __weak __typeof(eyedropperWindow) weakWindow = eyedropperWindow;
    eyedropperWindow.eyedropperView.click = ^() { [weakWindow stop]; };
    eyedropperWindow.contentView = eyedropperWindow.eyedropperView;

    // Doesn't work if you do it immediately.
    dispatch_async(dispatch_get_main_queue(), ^{
        eyedropperWindow.level = NSMainMenuWindowLevel + 1;
    });
    [[NSCursor crosshairCursor] push];
    [eyedropperWindow doPick];
    [[NSCursor crosshairCursor] pop];
    if (eyedropperWindow.selectedColor.alphaComponent == 0) {
        return nil;
    } else {
        return eyedropperWindow.selectedColor;
    }
}

- (void)grabScreenshots {
    self.screenshots = [NSMutableArray array];
    for (NSScreen *screen in [NSScreen screens]) {
        NSDictionary *dict = screen.deviceDescription;
        CGDirectDisplayID displayId = [dict[@"NSScreenNumber"] unsignedIntValue];
        CGImageRef image = CGDisplayCreateImage(displayId);
        NSSize size = screen.frame.size;
        size.width *= screen.backingScaleFactor;
        size.height *= screen.backingScaleFactor;

        NSBitmapImageRep *imageRep =
        [[NSBitmapImageRep alloc] initWithData:[[[NSImage alloc] initWithCGImage:image
                                                                            size:size]
                                                TIFFRepresentation]];
        [self.screenshots addObject:imageRep];
    }
}

- (void)doPick {
    [self grabScreenshots];

    NSModalSession session = [NSApp beginModalSessionForWindow:self];
    NSRunLoop* myRunLoop = [NSRunLoop currentRunLoop];
    // This keeps the runloop blocking when nothing else is going on.
    [myRunLoop addPort:[NSMachPort port]
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
    while (!self.selectedColor) {
        [NSApp runModalSession:session];
        [myRunLoop runMode:NSDefaultRunLoopMode
                beforeDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateInterval]];
    }
    [timer invalidate];

    [NSApp runModalSession:session];
    [myRunLoop runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateInterval]];

    [NSApp endModalSession:session];

    // The framework seems to want a spin of the runloop after ending a modal session before we can
    // close ourselves.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf close];
    });
}

- (void)stopPicking:(NSNotification *)notification {
    self.selectedColor = [NSColor clearColor];
}

- (NSInteger)currentScreenIndex {
    NSInteger i = 0;
    NSPoint location = [NSEvent mouseLocation];
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(location, screen.frame)) {
            return i;
        }
    }
    return -1;
}

- (NSBitmapImageRep *)currentScreenScreenshot {
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
    NSBitmapImageRep *screenshot = [self currentScreenScreenshot];
    NSColor *blackColor = [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
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

- (void)stop {
    NSPoint location = [NSEvent mouseLocation];
    NSScreen *screen = [[NSScreen screens] objectAtIndex:self.currentScreenIndex];
    NSPoint point = NSMakePoint(location.x - screen.frame.origin.x,
                                location.y - screen.frame.origin.y);
    point.y = screen.frame.size.height - point.y;
    point.x *= screen.backingScaleFactor;
    point.y *= screen.backingScaleFactor;
    self.selectedColor = [self.currentScreenScreenshot colorAtX:point.x y:point.y];

}

@end
