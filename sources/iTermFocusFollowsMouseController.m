//
//  iTermFocusFollowsMouseController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/24/20.
//

#import "iTermFocusFollowsMouseController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

@implementation iTermFocusFollowsMouseController {
    // Location of mouse when the app became inactive.
    NSPoint _savedMouseLocation;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChange:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
    }
    return self;
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    if (![iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse]) {
        return;
    }
    const NSPoint savedMouseLocation = _savedMouseLocation;
    _savedMouseLocation = NSMakePoint(NAN, NAN);
    if ([iTermAdvancedSettingsModel aggressiveFocusFollowsMouse]) {
        [self handleActivationAggressively:savedMouseLocation];
        return;
    }
    [self handleActivationRegularly];
}

- (void)handleActivationRegularly {
    DLog(@"Using non-aggressive FFM");
    const NSPoint mouseLocation = [NSEvent mouseLocation];
    NSView *view = [NSView viewAtScreenCoordinate:mouseLocation];
    if (![view conformsToProtocol:@protocol(iTermFocusFollowsMouseFocusReceiver)]) {
        return;
    }
    id<iTermFocusFollowsMouseFocusReceiver> receiver = (id)view;
    [receiver refuseFirstResponderAtCurrentMouseLocation];
}

- (void)handleActivationAggressively:(NSPoint)savedMouseLocation {
    DLog(@"Using aggressive FFM");
    const NSPoint mouseLocation = [NSEvent mouseLocation];
    // If focus follows mouse is on, find the window under the cursor and make it key. If a
    // id<iTermFocusFollowsMouseFocusReceiver> is under the cursor make it first responder.
    if (NSEqualPoints(mouseLocation, savedMouseLocation)) {
        return;
    }
    // Dispatch async because when you cmd-tab into iTerm2 the windows are briefly
    // out of order. Looks like an OS bug to me. They fix themselves right away,
    // and a dispatch async seems to give it enough time to right itself before
    // we iterate front to back.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self selectWindowAtScreenCoordinate:mouseLocation];
    });
}

- (void)selectWindowAtScreenCoordinate:(NSPoint)mousePoint {
    NSView *view = [NSView viewAtScreenCoordinate:mousePoint];
    NSWindow *window = view.window;
    if (view) {
        DLog(@"Will activate %@", window.title);
        [window makeKeyAndOrderFront:nil];
        if ([view conformsToProtocol:@protocol(iTermFocusFollowsMouseFocusReceiver)]) {
            [window makeFirstResponder:view];
        }
        return;
    }
}

- (void)applicationDidResignActive:(NSNotification *)aNotification {
    DLog(@"Save mouse location");
    _savedMouseLocation = [NSEvent mouseLocation];
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    if (![iTermAdvancedSettingsModel aggressiveFocusFollowsMouse]) {
        return;
    }
    const NSPoint mouseLocation = [NSEvent mouseLocation];
    NSView *view = [NSView viewAtScreenCoordinate:mouseLocation];
    if ([view conformsToProtocol:@protocol(iTermFocusFollowsMouseFocusReceiver)]) {
        [view.window makeFirstResponder:view];
    }
}

@end
