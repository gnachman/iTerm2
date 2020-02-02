//
//  iTermPresentationController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/20.
//

#import "iTermPresentationController.h"

#import "DebugLogging.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSScreen+iTerm.h"


@implementation iTermPresentationController

+ (instancetype)sharedInstance {
    static iTermPresentationController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)update {
    [self updateWithSanityCheck:YES];
}

- (void)updateWithSanityCheck:(BOOL)sanityCheck {
    DLog(@"BEGIN update sanityCheck=%@", @(sanityCheck));
    if ([[NSScreen screens] count] == 0) {
        DLog(@"No screens attached");
        return;
    }
    NSMutableArray<NSScreen *> *screensToHideDock = [NSMutableArray array];
    NSMutableArray<NSScreen *> *screensToHideMenu = [NSMutableArray array];
    const BOOL active = NSApp.isActive;
    DLog(@"App active=%@", @(active));
    if (active) {
        [self findScreensToHideDock:screensToHideDock
                               menu:screensToHideMenu];
    }

    if (gDebugLogging) {
        DLog(@"Screens to hide menu bar: %@", screensToHideMenu);
        DLog(@"Screens to hide dock: %@", screensToHideDock);
        [self logScreens];
    }

    const BOOL shouldHideMenuBar = [self anyScreenHasMenuBar:screensToHideMenu];
    const BOOL shouldHideDock = [self anyScreenHasDock:screensToHideDock];

    if (sanityCheck &&
        !shouldHideDock &&
        ![self anyScreenHasDock] &&
        [self dockIsCurrentlyHidden] &&
        screensToHideDock.count > 0) {
        // This happens when -update is called when a fullscreen window is causing the dock to be
        // hidden. The easiest way to reproduce it is to turn off input broadcasting.
        DLog(@"Schedule sanity check for next spin of the runlooop. Showing the dock while hidden and no screen has the dock and there is a full screen window.");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateWithSanityCheck:NO];
        });
    }

    [self setApplicationPresentationFlagsWithHiddenDock:shouldHideDock
                                                menuBar:shouldHideMenuBar];
    DLog(@"END update");
}

- (void)logScreens {
    for (NSScreen *screen in [NSScreen screens]) {
        DLog(@"Screen %@ frame=%@ visibleFrame=%@: has menu bar=%@ has dock=%@",
             screen,
             NSStringFromRect(screen.frame),
             NSStringFromRect(screen.visibleFrame),
             @([self screenHasMenuBar:screen]),
             @(screen.hasDock));
    }
}

- (BOOL)dockIsCurrentlyHidden {
    return (NSApp.presentationOptions & NSApplicationPresentationAutoHideDock) != 0;
}

- (BOOL)anyScreenHasDock {
    for (NSScreen *screen in NSScreen.screens) {
        if (screen.hasDock) {
            return YES;
        }
    }
    return NO;
}

- (void)forceShowMenuBarAndDock {
    [self setApplicationPresentationFlagsWithHiddenDock:NO menuBar:NO];
}

- (void)setApplicationPresentationFlagsWithHiddenDock:(BOOL)shouldHideDock
                                              menuBar:(BOOL)shouldHideMenuBar {
    DLog(@"setting options: hide dock=%@ hide menu bar=%@", @(shouldHideDock), @(shouldHideMenuBar));

    const NSApplicationPresentationOptions mask = (NSApplicationPresentationAutoHideMenuBar |
                                                   NSApplicationPresentationAutoHideDock);
    NSApplicationPresentationOptions presentationOptions = (NSApp.presentationOptions & ~mask);
    if (shouldHideDock) {
        presentationOptions |= NSApplicationPresentationAutoHideDock;
    }
    if (shouldHideMenuBar) {
        presentationOptions |= NSApplicationPresentationAutoHideMenuBar;
    }
    NSApp.presentationOptions = presentationOptions;
}

- (void)findScreensToHideDock:(NSMutableArray<NSScreen *> *)screensToHideDock
                         menu:(NSMutableArray<NSScreen *> *)screensToHideMenu {
    NSArray<id<iTermPresentationControllerManagedWindowController>> *windowControllers =
        [self.delegate presentationControllerManagedWindows];

    DLog(@"Considering the following window controllers: %@", windowControllers);
    for (id<iTermPresentationControllerManagedWindowController> windowController in windowControllers) {
        NSScreen *screen = nil;
        if (![self windowControllerIsWorthyOfConsideration:windowController screen:&screen]) {
            continue;
        }
        [screensToHideDock addObject:screen];
        if (![screensToHideMenu containsObject:screen] &&
            [self shouldHideMenuForWindowController:windowController]) {
            [screensToHideMenu addObject:screen];
        }
    }
}

- (BOOL)windowControllerIsWorthyOfConsideration:(id<iTermPresentationControllerManagedWindowController>)windowController
                                         screen:(out NSScreen **)screenPtr {
    DLog(@"Checking if %@ is worthy of consideration", windowController);
    BOOL lion = NO;
    const BOOL fullscreen = [windowController presentationControllerManagedWindowControllerIsFullScreen:&lion];
    if (!fullscreen) {
        DLog(@"  NO: Not fullscreen");
        return NO;
    }
    if (lion) {
        DLog(@"  NO: Lion fullscreen");
        return NO;
    }
    NSWindow *window = [windowController presentationControllerManagedWindowControllerWindow];;
    if (!window) {
        DLog(@"  NO: No window");
        return NO;
    }
    if (!window.isKeyWindow) {
        DLog(@"  NO: Not key");
        return NO;
    }
    if (window.alphaValue == 0) {
        DLog(@"  NO: Alpha is 0");
        return NO;
    }
    NSScreen *screen = window.screen;
    if (!screen) {
        DLog(@"  NO: No screen for window");
        return NO;
    }
    if (!window.isOnActiveSpace) {
        DLog(@"  NO: Not on active space");
        return NO;
    }
    if (!window.isVisible) {
        DLog(@"  NO: Not visible");
        return NO;
    }
    DLog(@"  YES");
    *screenPtr = screen;
    return YES;
}

- (BOOL)anyScreenHasMenuBar:(NSArray<NSScreen *> *)screens {
    return [screens anyWithBlock:^BOOL(NSScreen *screen) {
        return [self screenHasMenuBar:screen];
    }];
}

- (BOOL)anyScreenHasDock:(NSArray<NSScreen *> *)screens {
    DLog(@"Checking if any screen has dock in %@", screens);
    const BOOL result = [screens anyWithBlock:^BOOL(NSScreen *screen) {
        // We need to check both the screen we were given as well as the current "real" screen,
        // because they can have different visibleFrames. My theory is that NSScreen is immutable
        // and copies of it proliferate with different attributes.
        const BOOL result = [screen hasDock] || [[NSScreen screenWithFrame:screen.frame] hasDock];
        DLog(@"  Screen %@ with frame %@ and visible frame %@ hasdock=%@",
             screen,
             NSStringFromRect(screen.frame),
             NSStringFromRect(screen.visibleFrame),
             @(result));
        return result;
    }];
    return result;
}

- (BOOL)shouldHideMenuForWindowController:(id<iTermPresentationControllerManagedWindowController>)windowController {
    DLog(@"Checking if the menu bar should be hidden for this window");
    if ([iTermPreferences boolForKey:kPreferenceKeyUIElement]) {
        DLog(@"  NO because I am a UIElement");
        // I can't affect the menu bar
        return NO;
    }
    const BOOL result = [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen];
    DLog(@"  %@: based on hide menu bar in fullscreen setting", result ? @"YES" : @"NO");
    return result;
}

- (BOOL)screenHasMenuBar:(NSScreen *)currentScreen {
    if ([NSScreen screensHaveSeparateSpaces]) {
        return YES;
    }
    return currentScreen != nil && currentScreen == [[NSScreen screens] firstObject];
}

@end
