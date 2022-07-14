//
//  iTermPresentationController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/20.
//

#import "iTermPresentationController.h"

#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermPreferences.h"
#import "NSArray+iTerm.h"
#import "NSScreen+iTerm.h"

// macOS sends a *LOT* of screenParametersDidChange notifications for all kinds of unexpected reasons.
// For example, changing desktops will do it. So will miniaturizing. I've even seen it simply because
// the app got activated. We need to destroy and re-create metal views when a display is detached
// and re-attached. That is rare compared to all the other stuff. This is an attempt to detect
// screen removal/additions. There are still a lot of false positives, but maybe it will help.
// This doesn't really belong in this file but I don't have a better place for it yet.
NSNotificationName const iTermScreenParametersDidChangeNontrivally = @"iTermScreenParametersDidChangeNontrivally";
static _Atomic int gShouldPostNontrivialScreenParametersChange;
static void iTermDisplayReconfigurationCallback(CGDirectDisplayID display,
                                                CGDisplayChangeSummaryFlags flags,
                                                void *userInfo) {
    DLog(@"iTermDisplayReconfigurationCallback display=%@ flags=%@", @(display), @(flags));
    if (gShouldPostNontrivialScreenParametersChange) {
        return;
    }
    const CGDisplayChangeSummaryFlags mask = (kCGDisplayAddFlag | kCGDisplayRemoveFlag);
    if (flags & mask) {
        gShouldPostNontrivialScreenParametersChange = YES;
        DLog(@"Set needs iTermScreenParametersDidChangeNontrivally");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gShouldPostNontrivialScreenParametersChange) {
                gShouldPostNontrivialScreenParametersChange = NO;
                DLog(@"Post iTermScreenParametersDidChangeNontrivally");
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermScreenParametersDidChangeNontrivally
                                                                    object:nil];
            }
        });
    }
}

@implementation iTermPresentationController {
    NSScreen *_lastScreen;

    // Remembers the last screen frames so we can ignore
    // screenParametersDidChange: calls that don't affect the screens' frames.
    NSArray<NSValue *> *_screenFrames;
}

+ (instancetype)sharedInstance {
    static iTermPresentationController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _screenFrames = [self currentScreenFrames];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChange:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screenParametersDidChange:)
                                                     name:NSApplicationDidChangeScreenParametersNotification
                                                   object:nil];
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            CGDisplayRegisterReconfigurationCallback(iTermDisplayReconfigurationCallback, nil);
        });
    }
    return self;
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    [self update];
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
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
    NSScreen *currentScreenWithDock = [self screenWithDockFromScreens:screensToHideDock];

    const BOOL shouldHideDock = currentScreenWithDock != nil || [self haveFullScreenWindowOnSameScreenWhereDockWasLastHidden];
    // If hiding the sock, set screenWithDock to the best guess of the screen that has the dock.
    // It could be that currentScreenWithDock is nil because our presentation is hiding the dock.
    // In that case, carry forward our best guess from _lastScreen.
    // This value becomes the new _lastScreen, provided shouldHideDock is true.
    NSScreen *screenWithDock = shouldHideDock ? (currentScreenWithDock ?: _lastScreen) : nil;

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
                                                menuBar:shouldHideMenuBar
                                         screenWithDock:screenWithDock];
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

// When the dock is hidden because we have set the auto-hide dock presentation option, we can't
// figure out which screen *would* have the dock because their frames equal their visibleFrames.
// Instead, try to figure out which of the current screens is like the last screen where we saw
// the dock, just before hiding it. This can go wrong if the screen configuration changes. That is
// mitigated by resetting everything when screen parameters change.
- (BOOL)haveFullScreenWindowOnSameScreenWhereDockWasLastHidden {
    DLog(@"Checking if there's still a full screen window on the same screen where we last saw the dock. The last such screen had frame %@",
         NSStringFromRect(_lastScreen.frame));
    if (!_lastScreen) {
        DLog(@"  Don't have a lastScreen, so no");
        return NO;
    }
    if (!self.dockIsCurrentlyHidden) {
        DLog(@"  Dock isn't currently hidden, so no");
        return NO;
    }
    NSArray<id<iTermPresentationControllerManagedWindowController>> *windowControllers =
        [self.delegate presentationControllerManagedWindows];
    for (id<iTermPresentationControllerManagedWindowController> windowController in windowControllers) {
        NSScreen *screen = nil;
        if (![self windowControllerIsWorthyOfConsideration:windowController screen:&screen]) {
            continue;
        }
        NSWindow *window = [windowController presentationControllerManagedWindowControllerWindow];
        DLog(@"  Considering fullscreen window controller %@ whose screen has frame %@", windowController,
             NSStringFromRect(window.screen.frame));
        if (window.screen && NSIntersectsRect(window.screen.frame, _lastScreen.frame)) {
            DLog(@"  > Yup");
            return YES;
        }
    }
    DLog(@"  > Nope");
    return NO;
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
    [self setApplicationPresentationFlagsWithHiddenDock:NO menuBar:NO screenWithDock:nil];
}

NSString *PODescription(NSApplicationPresentationOptions presentationOptions) {
    NSMutableArray *array = [NSMutableArray array];
    if ((presentationOptions & (1 <<  0))) { [array addObject:@"NSApplicationPresentationAutoHideDock"]; }
    if ((presentationOptions & (1 <<  1))) { [array addObject:@"NSApplicationPresentationHideDock"]; }
    if ((presentationOptions & (1 <<  2))) { [array addObject:@"NSApplicationPresentationAutoHideMenuBar"]; }
    if ((presentationOptions & (1 <<  3))) { [array addObject:@"NSApplicationPresentationHideMenuBar"]; }
    if ((presentationOptions & (1 <<  4))) { [array addObject:@"NSApplicationPresentationDisableAppleMenu"]; }
    if ((presentationOptions & (1 <<  5))) { [array addObject:@"NSApplicationPresentationDisableProcessSwitching"]; }
    if ((presentationOptions & (1 <<  6))) { [array addObject:@"NSApplicationPresentationDisableForceQuit"]; }
    if ((presentationOptions & (1 <<  7))) { [array addObject:@"NSApplicationPresentationDisableSessionTermination"]; }
    if ((presentationOptions & (1 <<  8))) { [array addObject:@"NSApplicationPresentationDisableHideApplication"]; }
    if ((presentationOptions & (1 <<  9))) { [array addObject:@"NSApplicationPresentationDisableMenuBarTransparency"]; }
    if ((presentationOptions & (1 << 10))) { [array addObject:@"NSApplicationPresentationFullScreen"]; }
    if ((presentationOptions & (1 << 11))) { [array addObject:@"NSApplicationPresentationAutoHideToolbar"]; }
    if ((presentationOptions & (1 << 12))) { [array addObject:@"NSApplicationPresentationDisableCursorLocationAssistance"]; }
    return [array componentsJoinedByString:@", "];
}

- (void)setApplicationPresentationFlagsWithHiddenDock:(BOOL)shouldHideDock
                                              menuBar:(BOOL)shouldHideMenuBar
                                       screenWithDock:(NSScreen *)screenWithDock {
    DLog(@"setting options: hide dock=%@ hide menu bar=%@", @(shouldHideDock), @(shouldHideMenuBar));

    const NSApplicationPresentationOptions mask = (NSApplicationPresentationAutoHideMenuBar |
                                                   NSApplicationPresentationAutoHideDock);
    NSApplicationPresentationOptions presentationOptions = (NSApp.presentationOptions & ~mask);
    if (shouldHideDock) {
        presentationOptions |= NSApplicationPresentationAutoHideDock;
        DLog(@"Set lastScreen to %@", NSStringFromRect(screenWithDock.frame));
        _lastScreen = screenWithDock;
    } else {
        // Forget _lastScreen. It records the screen that had the dock last
        // time we were able to see it. Since we're hiding the dock now, we can
        // expect to compute a more accurate version of it next time we go to
        // hide the dock.
        DLog(@"Set lastScreen to nil");
        _lastScreen = nil;
    }
    if (shouldHideMenuBar) {
        presentationOptions |= NSApplicationPresentationAutoHideMenuBar;
    }

    if (NSApp.presentationOptions == presentationOptions) {
        return;
    }
    if (presentationOptions & NSApplicationPresentationFullScreen) {
        // Do not remove auto-hide dock/menubar when in full screen or else you don't get
        // a title bar w/ title bar view controller. A new feature of macOS 10.15.6.
        // Issue 9164
        if (NSApp.presentationOptions & NSApplicationPresentationAutoHideDock) {
            presentationOptions |= NSApplicationPresentationAutoHideDock;
        }
        if (NSApp.presentationOptions & NSApplicationPresentationAutoHideMenuBar) {
            presentationOptions |= NSApplicationPresentationAutoHideMenuBar;
        }
    }
    DLog(@"Set presentation options from %@ to %@", PODescription(NSApp.presentationOptions), PODescription(presentationOptions));

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
        screen = [NSScreen screenWithFrame:screen.frame];
        if (!screen) {
            DLog(@"No screen has frame %@", NSStringFromRect(screen.frame));
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

// This method lies to you when you do this:
// 1. Put window on screen 2
// 2. Cause dock to be hidden
// 3. Move dock to screen 1
// 4. Resign active
// 5. Become actgive
//
// For some reason the screen visibleFrame is wrong at this point. Another cycle of resign & become
// active fixes it.
- (NSScreen *)screenWithDockFromScreens:(NSArray<NSScreen *> *)screens {
    DLog(@"Checking if any screen has dock in %@", screens);
    return [screens objectPassingTest:^BOOL(NSScreen *screen, NSUInteger index, BOOL *stop) {
        // We need to check both the screen we were given as well as the current "real" screen,
        // because they can have different visibleFrames. My theory is that NSScreen is immutable
        // and copies of it proliferate with different attributes.
        BOOL result = NO;
        if ([screen hasDock]) {
            DLog(@"Screen %@ hasDock", screen);
            result = YES;
        }
        if ([[NSScreen screenWithFrame:screen.frame] hasDock]) {
            DLog(@"Screen with frame %@ - %@ - hasDock",
                 NSStringFromRect(screen.frame), [NSScreen screenWithFrame:screen.frame]);
            result = YES;
        }
        DLog(@"  Screen %@ with frame %@ and visible frame %@ hasdock=%@",
             screen,
             NSStringFromRect(screen.frame),
             NSStringFromRect(screen.visibleFrame),
             @(result));
        return result;
    }];
}

- (BOOL)shouldHideMenuForWindowController:(id<iTermPresentationControllerManagedWindowController>)windowController {
    DLog(@"Checking if the menu bar should be hidden for this window");
    if ([[iTermApplication sharedApplication] isUIElement]) {
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

- (NSArray<NSValue *> *)currentScreenFrames {
    return [[NSScreen screens] mapWithBlock:^id(NSScreen *screen) {
        return [NSValue valueWithRect:screen.frame];
    }];
}

- (BOOL)screenParametersReallyDidChange {
    NSArray<NSValue *> *frames = [self currentScreenFrames];
    if ([frames isEqualToArray:_screenFrames]) {
        return NO;
    }
    _screenFrames = frames;
    return YES;
}

- (void)screenParametersDidChange:(NSNotification *)notification {
    DLog(@"screenParametersDidChange");
    if (![self screenParametersReallyDidChange]) {
        DLog(@"That was a lie. Frames are still %@", _screenFrames);
        return;
    }
    DLog(@"screen parameters did change. Set lastScreen to nil and update. This could cause the dock to spuriously appear.");
    _lastScreen = nil;
    [self update];
}

@end
