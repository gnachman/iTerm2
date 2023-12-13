#import "iTermProfileHotKey.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermController.h"
#import "iTermMenuBarObserver.h"
#import "iTermNotificationController.h"
#import "iTermPreferences.h"
#import "iTermPresentationController.h"
#import "iTermProfilePreferences.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermSessionLauncher.h"
#import "NSArray+iTerm.h"
#import "NSScreen+iTerm.h"
#import "PseudoTerminal.h"
#import "SolidColorView.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSUInteger, iTermAnimationDirection) {
    kAnimationDirectionDown,
    kAnimationDirectionRight,
    kAnimationDirectionLeft,
    kAnimationDirectionUp
};

static iTermAnimationDirection iTermAnimationDirectionOpposite(iTermAnimationDirection direction) {
    switch (direction) {
        case kAnimationDirectionRight:
            return kAnimationDirectionLeft;
        case kAnimationDirectionLeft:
            return kAnimationDirectionRight;
        case kAnimationDirectionDown:
            return kAnimationDirectionUp;
        case kAnimationDirectionUp:
            return kAnimationDirectionDown;
    }
    assert(false);
}
static NSString *const kGUID = @"GUID";
static NSString *const kArrangement = @"Arrangement";

@interface iTermProfileHotKey()
@property(nonatomic, copy) NSString *profileGuid;
@property(nonatomic, retain) NSDictionary *restorableState;  // non-sqlite legacy
@property(nonatomic, readwrite) BOOL rollingIn;
@property(nonatomic) BOOL birthingWindow;
@property(nonatomic, retain) NSWindowController *windowControllerBeingBorn;
@end

@implementation iTermProfileHotKey {
    BOOL _activationPending;
}

- (instancetype)initWithShortcuts:(NSArray<iTermShortcut *> *)shortcuts
          hasModifierActivation:(BOOL)hasModifierActivation
             modifierActivation:(iTermHotKeyModifierActivation)modifierActivation
                        profile:(Profile *)profile {
    self = [super initWithShortcuts:shortcuts
              hasModifierActivation:hasModifierActivation
                 modifierActivation:modifierActivation];

    if (self) {
        _allowsStateRestoration = YES;
        _profileGuid = [profile[KEY_GUID] copy];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(terminalWindowControllerCreated:)
                                                     name:kTerminalWindowControllerWasCreatedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(characterPanelWillOpen:)
                                                     name:iTermApplicationCharacterPaletteWillOpen
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(characterPanelDidClose:)
                                                     name:iTermApplicationCharacterPaletteDidClose
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(inputMethodEditorDidOpen:)
                                                     name:iTermApplicationInputMethodEditorDidOpen
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(inputMethodEditorDidClose:)
                                                     name:iTermApplicationInputMethodEditorDidClose
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateWindowLevel)
                                                     name:iTermApplicationWillShowModalWindow
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateWindowLevel)
                                                     name:iTermApplicationDidCloseModalWindow
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChange:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_restorableState release];
    [_profileGuid release];
    [_windowController release];
    [_windowControllerBeingBorn release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p shortcuts=%@ hasModAct=%@ modAct=%@ profile.name=%@ profile.guid=%@ open=%@>",
            [self class], self, self.shortcuts,
            @(self.hasModifierActivation), @(self.modifierActivation),
            self.profile[KEY_NAME], self.profile[KEY_GUID], @(self.isHotKeyWindowOpen)];
}

#pragma mark - APIs

- (Profile *)profile {
    return [[ProfileModel sharedInstance] bookmarkWithGuid:_profileGuid];
}

- (void)createWindowWithCompletion:(void (^)(void))completion {
    [self createWindowWithURL:nil
                   completion:completion];
}

- (void)createWindowWithURL:(NSURL *)url completion:(void (^)(void))completion {
    if (self.windowController.weaklyReferencedObject) {
        if (completion) {
            completion();
        }
        return;
    }

    DLog(@"Create new window controller for profile hotkey");
    PseudoTerminal *windowController = [self windowControllerFromRestorableState];
    [_windowController release];
    _windowController = nil;
    if (windowController) {
        if (url) {
            [iTermSessionLauncher launchBookmark:self.profile
                                      inTerminal:windowController
                                         withURL:url.absoluteString
                                hotkeyWindowType:[self hotkeyWindowType]
                                         makeKey:YES
                                     canActivate:YES
                              respectTabbingMode:NO
                                           index:nil
                                         command:nil
                                     makeSession:nil
                                  didMakeSession:nil
                                      completion:nil];
        }
        self.windowController = [windowController weakSelf];
        completion();
        return;
    }
    [self getWindowControllerFromProfile:[self profile] url:url completion:^(PseudoTerminal *windowController) {
        if (_windowController.weaklyReferencedObject == nil) {
            self.windowController = [windowController weakSelf];
        }
        if (completion) {
            completion();
        }
    }];
}

- (void)setWindowController:(PseudoTerminal<iTermWeakReference> *)windowController {
    // Since this is public and we don't want to accidentally change an
    // existing window controller, we assert that it's nil. This complicates
    // internal calls, unfortunately, but better to catch the bugs.
    assert(!_windowController.weaklyReferencedObject);

    [_windowController release];
    _windowController = [windowController.weakSelf retain];
    if (!_windowController.weaklyReferencedObject) {
        return;
    }

    [self updateWindowLevel];
    _windowController.hotkeyWindowType = [self hotkeyWindowType];

    [_windowController.window setAlphaValue:0];
    if (_windowController.windowType != WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [_windowController.window setCollectionBehavior:self.windowController.window.collectionBehavior & ~NSWindowCollectionBehaviorFullScreenPrimary];
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (!self.floats) {
        return;
    }
    const NSWindowLevel before = _windowController.window.level;
    [self updateWindowLevel];
    const NSWindowLevel after = _windowController.window.level;
    if (before != after && after == NSNormalWindowLevel) {
        [[NSApp keyWindow] makeKeyAndOrderFront:nil];
    }
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    DLog(@"activeSpaceDidChangei %@", self.windowController);
    if (!self.isHotKeyWindowOpen) {
        DLog(@"Not open");
        return;
    }
    if (self.autoHides) {
        DLog(@"Autohides");
        return;
    }
    if (self.windowController.spaceSetting != iTermProfileJoinsAllSpaces) {
        DLog(@"Doesn't join all spaces");
        return;
    }
    if (!self.windowController.window.isKeyWindow) {
        DLog(@"Not key");
        return;
    }
    // I'm not proud. One spin is enough when switching desktops when both have
    // apps. When switching from a desktop with nothing to a desktop with
    // another app, you resign key and get deactivated over two spins. Sigh.
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Two spins after activeSpaceDidChange %@", self.windowController);
            if (self.windowController.window.isKeyWindow) {
                DLog(@"Hotkey window still key a spin after changing spaces. Inexplicable.");
                return;
            }
            DLog(@"One spin after changing spaces with open non-autohiding joins-all-spaces key hotkey window that lost key status. Make key.");
            [self.windowController.window makeKeyAndOrderFront:nil];
        });
    });
}

- (void)updateWindowLevel {
    if (self.floats) {
        _windowController.window.level = self.floatingLevel;
    } else {
        _windowController.window.level = NSNormalWindowLevel;
    }
}

- (NSWindowLevel)floatingLevel {
    iTermApplication *app = [iTermApplication sharedApplication];
    if (app.it_characterPanelIsOpen || app.it_modalWindowOpen || app.it_imeOpen) {
        DLog(@"Use floating window level. characterPanelIsOpen=%@, modalWindowOpen=%@ imeOpen=%@",
             @(app.it_characterPanelIsOpen), @(app.it_modalWindowOpen),
             @(app.it_imeOpen));
        return NSFloatingWindowLevel;
    }
    NSWindow *const keyWindow = [NSApp keyWindow];
    if (keyWindow != nil && keyWindow != _windowController.window) {
        DLog(@"Use normal window level. Key window is %@, my window is %@",
             keyWindow, _windowController.window);
        return NSNormalWindowLevel;
    }
    DLog(@"Use main menu window level (I am key, no detected panels are open)");
    NSWindowLevel windowLevelJustBelowNotificiations;
    if (@available(macOS 10.16, *)) {
        windowLevelJustBelowNotificiations = NSMainMenuWindowLevel - 2;
    } else {
        windowLevelJustBelowNotificiations = 17;
    }
    // These are the window levels in play:
    //
    // NSStatusWindowLevel (25) -                Floating hotkey panels overlapping a fixed, visible menu bar.
    // NSMainMenuWindowLevel (24) -              Menu bar, dock. (maybe notification center on macOS < 12? I should check)
    // 23 -                                      Notification center (macOS 11+)
    // 22 -                                      (macOS 11+) Hotkey windows under a hidden-but-not-auto-hidden menu bar.
    // 18 -                                      Notification center (macOS 10.x)
    // 17 -                                      (macOS 10.x) Hotkey windows under a hidden-but-not-auto-hidden menu bar.
    //
    // NSTornOffMenuWindowLevel (3) -            Just too low, used to use this, but not any more because it's under the dock.

    // A brief history and rationale:
    //
    // NSStatusWindowLevel overlaps the menu bar and the dock. This is obviously desirable because
    // you don't want these things blocking your view. But if you've configured your menu bar to
    // automatically hide (system prefs > general > automatically hide and show menu bar) then the
    // menu bar gets overlapped when you show it and that is lame (issue 7924).
    //
    // NSTornOffMenuWindowLevel does not overlap the dock, so it is no good. You can't go having
    // your dock overlapping your fullscreen hotkey window, as that is lame (issue 7963).
    //
    // NSMainMenuWindowLevel seems to do what you'd want, but I think it just works by accident.
    //
    // It seems the sweet spot is between the dock and main menu levels, of which there are
    // three (21…23). They are unnamed.
    //
    // It is ok to be leveled below the main menu because the window is always positioned under the
    // menu bar *except* when the menu bar is auto-hidden.
    //
    // However, there is an exception for floating panels. iTerm2 does not get activated when you
    // open a floating panel. That means it does not have the ability to hide the menu bar.
    // We *want* floating panels to be overlapped by an auto-hiding menu bar, but not by a fixed
    // menu bar. So use the status window level for them when the menu bar is set to auto-hide.
    // See issue 7984 for why we want a floating panel hotkey window to overlap the menu bar.
    //
    // Mind you, this is all irrelevant if iTerm2's "auto-hide menu bar in non-native full screen"
    // is turned off. Then the window is just shifted down and the menu bar hangs around.
    if (self.hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) {
        if (![self menuBarAutoHides]) {
            if (![[iTermMenuBarObserver sharedInstance] menuBarVisibleOnScreen:_windowController.window.screen]) {
                // No menu bar currently. Optimistically take that as evidence that it won't suddenly
                // appear on us overlapping the hotkey window. This is the case when on another app's
                // full screen window. Do this to avoid overlapping notifications.
                return windowLevelJustBelowNotificiations;
            }
            if (!self.windowController.fullScreen) {
                // Non-fullscreen windows have their frame set below the menu bar so we can let
                // notifications overlap them.
                return windowLevelJustBelowNotificiations;
            }
            // Floating fullscreen panel and fixed menu bar — overlap the menu bar.
            // Unfortunately, this overlaps notification center since it is at the same level as
            // the menu bar. If iTerm2 is not active then it can't hide the menu bar by setting
            // presentation options. To move this below notifications we'd also need to adjust the
            // window's frame as the menu bar hides and shows (e.g., if iTerm2 is activated then
            // it gains the ability to hide the menu bar, and the frame would need to change).
            return NSStatusWindowLevel;
        }
    }
    // Floating hotkey window that does not join all spaces. This doesn't seem to work well in the
    // presence of other apps' fullscreen windows, regardless of level.
    return windowLevelJustBelowNotificiations;
}

- (BOOL)menuBarAutoHides {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"_HIHideMenuBar"]) {
        return YES;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen]) {
        return YES;
    }
    return NO;
}

- (NSPoint)destinationPointForInitialPoint:(NSPoint)point
              forAnimationInDirection:(iTermAnimationDirection)direction
                                 size:(NSSize)size {
    switch (direction) {
        case kAnimationDirectionUp:
            return NSMakePoint(point.x, point.y + size.height);
        case kAnimationDirectionDown:
            return NSMakePoint(point.x, point.y - size.height);
        case kAnimationDirectionLeft:
            return NSMakePoint(point.x - size.width, point.y);
        case kAnimationDirectionRight:
            return NSMakePoint(point.x + size.width, point.y);
    }
    assert(false);
}

- (NSRect)preferredFrameForWindowController:(PseudoTerminal<iTermWeakReference> *)windowController {
    // This can be the anchored screen (typically the screen the window was created
    // with, but can be changed by -moveToPreferredScreen). If unanchored, then
    // it is the current screen.
    NSScreen *screen = windowController.screen;

    switch (windowController.windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return [windowController canonicalFrameForScreen:screen];

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return [self frameByMovingFrame:windowController.window.frame
                                 fromScreen:windowController.window.screen
                                   toScreen:screen];
    }
    assert(false);
}

- (NSRect)frameByMovingFrame:(NSRect)sourceFrame fromScreen:(NSScreen *)sourceScreen toScreen:(NSScreen *)destinationScreen {
    NSSize originOffset = NSMakeSize(sourceFrame.origin.x - sourceScreen.visibleFrame.origin.x,
                                     sourceFrame.origin.y - sourceScreen.visibleFrame.origin.y);

    NSRect destination = sourceFrame;
    destination.origin = destinationScreen.visibleFrame.origin;
    destination.origin.x += originOffset.width;
    destination.origin.y += originOffset.height;
    return destination;
}

- (NSPoint)hiddenOriginForScreen:(NSScreen *)screen {
    NSRect rect = self.windowController.window.frame;
    DLog(@"Basing hidden origin on screen frame (IHD) %@", NSStringFromRect(screen.visibleFrameIgnoringHiddenDock));
    switch (self.windowController.windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            return NSMakePoint(rect.origin.x, NSMaxY(screen.visibleFrame));

        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            return NSMakePoint(NSMinX(screen.visibleFrameIgnoringHiddenDock), rect.origin.y);

        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return NSMakePoint(NSMaxX(screen.visibleFrameIgnoringHiddenDock), rect.origin.y);

        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            return NSMakePoint(rect.origin.x, NSMinY(screen.visibleFrameIgnoringHiddenDock) - NSHeight(rect));

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return [self frameByMovingFrame:rect fromScreen:self.windowController.window.screen toScreen:screen].origin;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return screen.visibleFrameIgnoringHiddenDock.origin;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
            return screen.frame.origin;

        case WINDOW_TYPE_LION_FULL_SCREEN:
            return rect.origin;
    }
    return rect.origin;
}

- (BOOL)rect:(NSRect)rect intersectsAnyScreenExcept:(NSScreen *)allowedScreen {
    return [[NSScreen screens] anyWithBlock:^BOOL(NSScreen *screen) {
        if (screen == allowedScreen) {
            return NO;
        }
        NSRect screenFrame = screen.frame;
        return NSIntersectsRect(rect, screenFrame);
    }];
}

- (void)rollInAnimatingInDirection:(iTermAnimationDirection)direction {
    [self moveToPreferredScreen];
    self.windowController.window.alphaValue = 0;

    NSRect destination = [self preferredFrameForWindowController:self.windowController];
    NSRect proposedHiddenRect = self.windowController.window.frame;
    proposedHiddenRect.origin = [self hiddenOriginForScreen:self.windowController.screen];
    if ([self rect:proposedHiddenRect intersectsAnyScreenExcept:self.windowController.window.screen]) {
        [self.windowController.window setFrame:destination display:YES];
    } else {
        [self.windowController.window setFrameOrigin:proposedHiddenRect.origin];
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        [context setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
        [self.windowController.window.animator setFrame:destination display:NO];
        [self.windowController.window.animator setAlphaValue:1];
    }
                        completionHandler:^{
                            [self rollInFinished];
                        }];
}

- (void)rollOutAnimatingInDirection:(iTermAnimationDirection)direction causedByKeypress:(BOOL)causedByKeypress {
    _activationPending = NO;
    NSRect source = self.windowController.window.frame;
    NSRect destination = source;
    destination.origin = [self hiddenOriginForScreen:self.windowController.window.screen];

    if ([self rect:destination intersectsAnyScreenExcept:self.windowController.window.screen]) {
        destination = source;
    }

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        [context setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
        [self.windowController.window.animator setFrame:destination display:NO];
        [self.windowController.window.animator setAlphaValue:0];
    }
                        completionHandler:^{
        [self didFinishRollingOut:causedByKeypress];
    }];

}

- (void)moveToPreferredScreen {
    // If the window was created with a profile that moved it to the screen
    // with the cursor, anchor it to the screen that currently has the cursor.
    // Doing so changes what -[PseudoTerminal screen] returns. If any other
    // screen preference was selected this does nothing.
    [self.windowController moveToPreferredScreen];

    NSRect destination = [self preferredFrameForWindowController:self.windowController];
    DLog(@"iTermProfileHotKey: move to preferred screen setting frame to %@", NSStringFromRect(destination));
    [self.windowController.window setFrame:destination display:NO];
}

- (void)fadeIn {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self rollInFinished];
    }];
    [[self.windowController.window animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
}

- (void)fadeOut:(BOOL)causedByKeypress {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self didFinishRollingOut:causedByKeypress];
    }];
    self.windowController.window.animator.alphaValue = 0;
#if BETA
    SetPinnedDebugLogMessage([NSString stringWithFormat:@"Fade out hotkey window %p", self],
                             [[NSThread callStackSymbols] componentsJoinedByString:@"\n"]);
#endif
    [NSAnimationContext endGrouping];
}

- (iTermAnimationDirection)animateInDirectionForWindowType:(iTermWindowType)windowType {
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            return kAnimationDirectionDown;
            break;

        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            return kAnimationDirectionRight;
            break;

        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return kAnimationDirectionLeft;
            break;

        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            return kAnimationDirectionUp;
            break;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
            assert(false);
    }
}

- (BOOL)floats {
    return [iTermProfilePreferences boolForKey:KEY_HOTKEY_FLOAT inProfile:self.profile];
}

- (void)rollInAnimated:(BOOL)animated {
    DLog(@"Roll in [show] hotkey window");
    if (_rollingIn) {
        DLog(@"Already rolling in");
        return;
    }
    if (_rollingOut) {
        DLog(@"Rolling out. Cancel roll in");
        return;
    }
    _rollingIn = YES;
    if (self.windowController.windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        // This has to be done before making it key or the dock will be hidden based on the
        // display it was last on, not the display it will be on. I think it might be safe to
        // do this for all window types, but I don't want to risk introducing bugs here.
        [self moveToPreferredScreen];
    }
    if (self.hotkeyWindowType != iTermHotkeyWindowTypeFloatingPanel) {
        DLog(@"Activate iTerm2 prior to animating hotkey window in");
        _activationPending = YES;
        [self.windowController.window makeKeyAndOrderFront:nil];
        [[iTermApplication sharedApplication] activateAppWithCompletion:^{
            [self reallyRollInAnimated:animated];
        }];
    } else {
        [self reallyRollInAnimated:animated];
    }
}

- (void)reallyRollInAnimated:(BOOL)animated {
    DLog(@"Consummating roll in");
    [self.windowController.window makeKeyAndOrderFront:nil];
    if (animated) {
        switch (self.windowController.windowType) {
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
                [self rollInAnimatingInDirection:[self animateInDirectionForWindowType:self.windowController.windowType]];
                break;

            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_COMPACT:
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
            case WINDOW_TYPE_ACCESSORY:
                [self moveToPreferredScreen];
                [self fadeIn];
                break;

            case WINDOW_TYPE_LION_FULL_SCREEN:
                assert(false);
        }
    } else {
        [self moveToPreferredScreen];
        self.windowController.window.alphaValue = 1;
        [self rollInFinished];
    }
}

- (void)rollOut:(BOOL)causedByKeypress {
    DLog(@"Roll out [hide] hotkey window");
    DLog(@"\n%@", [NSThread callStackSymbols]);
    if (_rollingOut) {
        DLog(@"Already rolling out");
        return;
    }
    // Note: the test for alpha is because when you become an LSUIElement, the
    // window's alpha could be 1 but it's still invisible.
    if (self.windowController.window.alphaValue == 0) {
        DLog(@"RollOutHotkeyTerm returning because term isn't visible.");
        return;
    }

    _rollingOut = YES;

    if ([iTermProfilePreferences boolForKey:KEY_HOTKEY_ANIMATE inProfile:self.profile]) {
        switch (self.windowController.windowType) {
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_BOTTOM_PARTIAL: {
                iTermAnimationDirection inDirection = [self animateInDirectionForWindowType:self.windowController.windowType];
                iTermAnimationDirection outDirection = iTermAnimationDirectionOpposite(inDirection);
                [self rollOutAnimatingInDirection:outDirection causedByKeypress:causedByKeypress];
                break;
            }

            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_COMPACT:
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:  // Framerate drops too much to roll this (2014 5k iMac)
            case WINDOW_TYPE_ACCESSORY:
                [self fadeOut:causedByKeypress];
                break;

            case WINDOW_TYPE_LION_FULL_SCREEN:
                assert(false);
        }
    } else {
        self.windowController.window.alphaValue = 0;
        [self didFinishRollingOut:causedByKeypress];
    }
}

// Non-sqlite legacy code path
- (void)saveHotKeyWindowState {
    if (self.windowController.weaklyReferencedObject && self.profileGuid) {
        DLog(@"Saving hotkey window state for %@", self);
        const BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
        NSDictionary *arrangement = [self.windowController arrangementExcludingTmuxTabs:YES
                                                                      includingContents:includeContents];
        if (arrangement) {
            self.restorableState = @{ kGUID: self.profileGuid,
                                      kArrangement: arrangement };
        } else {
            self.restorableState = nil;
        }
    } else if ([iTermController sharedInstance]) {
        DLog(@"Not saving hotkey window state for %@", self);
        self.restorableState = nil;
    }
}

- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder {
    if (!self.windowController.weaklyReferencedObject || !self.profileGuid) {
        DLog(@"Not encoding hotkey window state for %@", self);
        return NO;
    }
    if (![self.windowController conformsToProtocol:@protocol(iTermGraphCodable)]) {
        XLog(@"Window controller %@ does not conform to iTermGraphCodable", self.windowController);
        return NO;
    }
    id<iTermGraphCodable> codable = (id<iTermGraphCodable>)self.windowController;

    [encoder encodeString:self.profileGuid forKey:kGUID];
    [encoder encodeChildWithKey:kArrangement
                     identifier:@""
                     generation:iTermGenerationAlwaysEncode
                          block:^BOOL(iTermGraphEncoder * _Nonnull subencoder) {
        return [codable encodeGraphWithEncoder:subencoder];
    }];
    return YES;
}

// Non-sqlite legacy code path
- (BOOL)loadRestorableStateFromArray:(NSArray *)states {
    for (NSDictionary *state in states) {
        if ([state[kGUID] isEqualToString:self.profileGuid]) {
            self.restorableState = state;
            return YES;
        }
    }
    return NO;
}

- (BOOL)isHotKeyWindowOpen {
    return self.windowController.window.alphaValue > 0;
}

- (void)revealForScripting {
    [self showHotKeyWindow];
}

- (void)hideForScripting {
    [self hideHotKeyWindowAnimated:YES suppressHideApp:NO otherIsRollingIn:NO causedByKeypress:NO];
}

- (void)toggleForScripting {
    if (self.isRevealed) {
        [self hideForScripting];
    } else {
        [self revealForScripting];
    }
}

- (BOOL)isRevealed {
    return self.windowController.window.alphaValue == 1 && self.windowController.window.isVisible;
}

- (void)cancelRollOut {
    DLog(@"cancelRollOut requested");
    if (_rollOutCancelable && _rollingOut) {
        DLog(@"Cancelling roll out");
        _rollingOut = NO;
        _rollOutCancelable = NO;
        [self orderOut];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_activationPending && ![NSApp isActive]) {
                [NSApp activateIgnoringOtherApps:YES];
            }
        });
    } else {
        DLog(@"Cannot cancel. cancelable=%@ rollingOut=%@", @(_rollOutCancelable), @(_rollingOut));
    }
}

#pragma mark - Protected

- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)genericSiblings {
    DLog(@"hotKeypressedWithSiblings called on %@ with siblings %@", self, genericSiblings);
    DLog(@"Secure input=%@", @([[iTermSecureKeyboardEntryController sharedInstance] isEnabled]));
    if (@available(macOS 12.0, *)) {
        if ([[iTermSecureKeyboardEntryController sharedInstance] isEnabled] &&
            ![NSApp isActive]) {
            DLog(@"Notify");
            [[iTermNotificationController sharedInstance] notify:@"Hotkeys Unavailable"
                                                 withDescription:@"Another app has enabled secure keyboard input. That prevents hotkey windows from being shown."];
            return @[];
        }
    }
    genericSiblings = [genericSiblings arrayByAddingObject:self];

    NSArray<iTermProfileHotKey *> *siblings = [genericSiblings mapWithBlock:^id(iTermBaseHotKey *anObject) {
        if ([anObject isKindOfClass:[iTermProfileHotKey class]]) {
            return anObject;
        } else {
            return nil;
        }
    }];
    DLog(@"hotkey sibs are %@", siblings);
    // If any sibling is rolling out but we can cancel the rollout, do so. This is after the window
    // has finished animating out but we're in the delay period before activating the app the user
    // was in before pressing the hotkey to reveal the hotkey window.
    for (iTermProfileHotKey *other in siblings) {
        if (other.rollingOut && other.rollOutCancelable) {
            DLog(@"cancel rollout");
            [other cancelRollOut];
        }
    }
    // If any sibling is rolling in or rolling out, do nothing. This keeps us from ending up in
    // a broken state where some siblings are in and others are out.
    BOOL anyTransitioning = [siblings anyWithBlock:^BOOL(iTermProfileHotKey *other) {
        BOOL result = other.rollingIn || other.rollingOut;
        if (result) {
            DLog(@"Found a transitioning sibling: %@ rollingIn=%@ rollingOut=%@", other, @(other.rollingIn), @(other.rollingOut));
        }
        return result;
    }];
    if (anyTransitioning) {
        DLog(@"One or more siblings is transitioning so I'm returning without doing anything.");
        return siblings;
    }
    DLog(@"toggle window %@. siblings=%@", self, siblings);
    BOOL allSiblingsOpen = [siblings allWithBlock:^BOOL(iTermProfileHotKey *sibling) {
        iTermProfileHotKey *other = (iTermProfileHotKey *)sibling;
        return other.isHotKeyWindowOpen;
    }];

    BOOL anyIsKey = [siblings anyWithBlock:^BOOL(iTermProfileHotKey *anObject) {
        return anObject.windowController.window.isKeyWindow;
    }];

    DLog(@"Hotkey pressed. All open=%@  any is key=%@  siblings=%@",
         @(allSiblingsOpen), @(anyIsKey), siblings);
    for (iTermProfileHotKey *sibling in [NSSet setWithArray:[siblings arrayByAddingObject:self]]) {
        DLog(@"Invoking handleHotkeyPressWithAllOpen:%@ anyIsKey:%@ on %@", @(allSiblingsOpen), @(anyIsKey), sibling);
        [sibling handleHotkeyPressWithAllOpen:allSiblingsOpen anyIsKey:anyIsKey];
    }
    return siblings;
}

- (void)handleHotkeyPressWithAllOpen:(BOOL)allSiblingsOpen anyIsKey:(BOOL)anyIsKey {
    DLog(@"handleHotkeyPressWithAllOpen");
    if (self.windowController.weaklyReferencedObject) {
        DLog(@"already have a hotkey window created");
        if (self.windowController.window.alphaValue == 1) {
            if (self.windowController.spaceSetting == iTermProfileOpenInCurrentSpace &&
                !self.windowController.window.isOnActiveSpace) {
                DLog(@"Move already-open hotkey window to current space");
                NSWindow *window = self.windowController.window;
                // I tested this on 10.12 and it's sufficient to move the window. Maybe not in older OS versions?
                NSWindowCollectionBehavior collectionBehavior = window.collectionBehavior;
                window.collectionBehavior = (collectionBehavior | NSWindowCollectionBehaviorCanJoinAllSpaces);
                window.collectionBehavior = collectionBehavior;
                return;
            }
            DLog(@"hotkey window opaque");
            if (!allSiblingsOpen) {
                DLog(@"Not all siblings open. Doing nothing.");
                return;
            }
            self.wasAutoHidden = NO;
            if (anyIsKey || ![self switchToVisibleHotKeyWindowIfPossible]) {
                DLog(@"Hide hotkey window");
                [self hideHotKeyWindowAnimated:YES suppressHideApp:NO otherIsRollingIn:NO causedByKeypress:YES];
            }
        } else {
            DLog(@"hotkey window not opaque");
            [self showHotKeyWindow];
        }
    } else {
        DLog(@"no hotkey window created yet");
        [self showHotKeyWindow];
    }
}

#pragma mark - Private

- (PseudoTerminal *)windowControllerFromRestorableState {
    NSDictionary *arrangement = [[self.restorableState[kArrangement] copy] autorelease];
    self.restorableState = nil;
    if (!arrangement) {
        return nil;
    }

    PseudoTerminal *term = [PseudoTerminal terminalWithArrangement:arrangement
                                                             named:nil
                                          forceOpeningHotKeyWindow:NO];
    if (term) {
        [[iTermController sharedInstance] addTerminalWindow:term];
    }
    return term;
}

- (iTermHotkeyWindowType)hotkeyWindowType {
    if (self.floats) {
        if ([iTermProfilePreferences intForKey:KEY_SPACE inProfile:self.profile] == iTermProfileJoinsAllSpaces) {
            // This makes it possible to overlap Lion fullscreen windows.
            return iTermHotkeyWindowTypeFloatingPanel;
        } else {
            return iTermHotkeyWindowTypeFloatingWindow;
        }
    } else {
        return iTermHotkeyWindowTypeRegular;
    }
}

- (void)getWindowControllerFromProfile:(Profile *)hotkeyProfile
                                   url:(NSURL *)url
                            completion:(void (^)(PseudoTerminal *))completion {
    if (!hotkeyProfile) {
        completion(nil);
        return;
    }
    if ([[hotkeyProfile objectForKey:KEY_WINDOW_TYPE] intValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
        // Lion fullscreen doesn't make sense with hotkey windows. Change
        // window type to traditional fullscreen.
        NSMutableDictionary *replacement = [[hotkeyProfile mutableCopy] autorelease];
        replacement[KEY_WINDOW_TYPE] = @(WINDOW_TYPE_TRADITIONAL_FULL_SCREEN);
        hotkeyProfile = replacement;
    }
    [self.delegate hotKeyWillCreateWindow:self];
    self.birthingWindow = YES;
    [iTermSessionLauncher launchBookmark:hotkeyProfile
                              inTerminal:nil
                                 withURL:url.absoluteString
                        hotkeyWindowType:[self hotkeyWindowType]
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:nil
                          didMakeSession:^(PTYSession * _Nonnull session) {
        self.birthingWindow = NO;

        [self.delegate hotKeyDidCreateWindow:self];
        PseudoTerminal *result = nil;
        if (session) {
            result = [[iTermController sharedInstance] terminalWithSession:session];
        }
        self.windowControllerBeingBorn = nil;
        completion(result);
    }
                              completion:nil];
}

- (void)rollInFinished {
    DLog(@"Roll-in finished for %@", self);
    _rollingIn = NO;
    if (self.windowController.window) {
        [[iTermApplication sharedApplication] it_makeWindowKey:self.windowController.window];
    }
    [self.windowController.window makeFirstResponder:self.windowController.currentSession.textview];
    [[self.windowController currentTab] recheckBlur];
    self.windowController.window.collectionBehavior = self.windowController.desiredWindowCollectionBehavior;
    [[iTermPresentationController sharedInstance] update];
}

- (void)didFinishRollingOut:(BOOL)causedByKeypress {
    DLog(@"didFinishRollingOut");
    _activationPending = NO;
    DLog(@"Invoke willFinishRollingOutProfileHotKey:");
    BOOL activatingOtherApp = [self.delegate willFinishRollingOutProfileHotKey:self
                                                              causedByKeypress:causedByKeypress];
    if (activatingOtherApp) {
        _rollOutCancelable = YES;
        DLog(@"Schedule order-out");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_rollingOut) {
                DLog(@"Order out with secure keyboard entry=%@", @(IsSecureEventInputEnabled()));
                _rollOutCancelable = NO;
                [self orderOut];
            }
        });
    } else {
        [self orderOut];
    }
    self.windowController.window.collectionBehavior = self.windowController.desiredWindowCollectionBehavior;
}

- (void)orderOut {
    DLog(@"Call orderOut: on terminal %@", self.windowController);
    [self.windowController.window orderOut:self];
    DLog(@"Returned from orderOut:. Set _rollingOut=NO");

    // This must be done after orderOut: so autoHideHotKeyWindowsExcept: will know to throw out the
    // previous state.
    _rollingOut = NO;
}

- (BOOL)autoHides {
    return [iTermProfilePreferences boolForKey:KEY_HOTKEY_AUTOHIDE inProfile:self.profile];
}

- (void)setAutoHides:(BOOL)autoHides {
    [iTermProfilePreferences setBool:autoHides
                              forKey:KEY_HOTKEY_AUTOHIDE
                           inProfile:self.profile
                               model:[ProfileModel sharedInstance]];
}

// If there's a visible hotkey window that is either not key or is on another space, switch to it.
// Save the previously active app unless switching spaces (why the exception? Not sure.)
// Return YES if it was switched to, or NO if the window isn't suitable for switching to.
- (BOOL)switchToVisibleHotKeyWindowIfPossible {
    DLog(@"switchToVisibleHotKeyWindowIfPossible");
    const BOOL activateStickyHotkeyWindow = (!self.autoHides &&
                                             !self.windowController.window.isKeyWindow);
    if (activateStickyHotkeyWindow && ![NSApp isActive]) {
        DLog(@"Storing previously active app");
        [self.delegate storePreviouslyActiveApp:self];
    }
    const BOOL hotkeyWindowOnOtherSpace = ![self.windowController.window isOnActiveSpace];
    if (hotkeyWindowOnOtherSpace || activateStickyHotkeyWindow) {
        DLog(@"Hotkey window is active on another space, or else it doesn't autohide but isn't key. Switch to it.");
        if (self.hotkeyWindowType != iTermHotkeyWindowTypeFloatingPanel) {
            [NSApp activateIgnoringOtherApps:YES];
        }
        [self.windowController.window makeKeyAndOrderFront:nil];
        return YES;
    } else {
        return NO;
    }
}

- (void)showAlreadyVisibleHotKeyWindow {
    DLog(@"showAlreadyVisibleHotKeyWindow");
    if (![self switchToVisibleHotKeyWindowIfPossible]) {
        DLog(@"Make window key, make textview first responder.");
        [self.windowController.window makeKeyAndOrderFront:nil];
        [self.windowController.window makeFirstResponder:self.windowController.currentSession.textview];
    }
}

- (void)showHotKeyWindow {
    [self showHotKeyWindowCreatingWithURLIfNeeded:nil];
}

- (BOOL)showHotKeyWindowCreatingWithURLIfNeeded:(NSURL *)url {
    DLog(@"showHotKeyWindow: %@", self);

    if (self.windowController.window.alphaValue == 1 && self.windowController.window.isVisible) {
        // This path is taken when you use a session hotkey to navigate to an already-open hotkey window.
        [self showAlreadyVisibleHotKeyWindow];
        return NO;
    }
    [self.delegate storePreviouslyActiveApp:self];

    BOOL result = NO;
    if (!self.windowController.weaklyReferencedObject) {
        DLog(@"Create new hotkey window");
        [self createWindowWithURL:url completion:^{
            [self rollInAnimated:[iTermProfilePreferences boolForKey:KEY_HOTKEY_ANIMATE inProfile:self.profile]];
        }];
        result = YES;
    } else {
        DLog(@"reveal existing hotkey window");
        [self rollInAnimated:[iTermProfilePreferences boolForKey:KEY_HOTKEY_ANIMATE inProfile:self.profile]];
    }
    return result;
}

- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp
                otherIsRollingIn:(BOOL)otherIsRollingIn
                causedByKeypress:(BOOL)causedByKeypress {
    DLog(@"Hide hotkey window. animated=%@ suppressHideApp=%@", @(animated), @(suppressHideApp));

    if (suppressHideApp) {
        [self.delegate suppressHideApp];
    }
    if (!animated) {
        [self fastHideHotKeyWindow];
    }

    for (NSWindow *sheet in self.windowController.window.sheets) {
        [self.windowController.window endSheet:sheet];
    }
    self.closedByOtherHotkeyWindowOpening = otherIsRollingIn;
    [self rollOut:causedByKeypress];
}

- (void)windowWillClose {
    [_windowController release];
    _windowController = nil;
    self.restorableState = nil;
}

- (void)fastHideHotKeyWindow {
    DLog(@"fastHideHotKeyWindow");
    [self.windowController.window orderOut:nil];
    self.windowController.window.alphaValue = 0;
}

#pragma mark - Notifications

- (void)terminalWindowControllerCreated:(NSNotification *)notification {
    if (self.birthingWindow) {
        self.windowControllerBeingBorn = notification.object;
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _activationPending = NO;
}

- (void)characterPanelWillOpen:(NSNotification *)notification {
    [self updateWindowLevel];
}

- (void)characterPanelDidClose:(NSNotification *)notification {
    [self updateWindowLevel];
}

- (void)inputMethodEditorDidOpen:(NSNotification *)notification {
    DLog(@"inputMethodEditorDidOpen");
    [self updateWindowLevel];
}

- (void)inputMethodEditorDidClose:(NSNotification *)notification {
    DLog(@"inputMethodEditorDidClose");
    [self updateWindowLevel];
}

@end
