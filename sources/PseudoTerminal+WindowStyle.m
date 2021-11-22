//
//  PseudoTerminal+WindowStyle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/21/20.
//

#import "PseudoTerminal+WindowStyle.h"
#import "PseudoTerminal+TouchBar.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermMenuBarObserver.h"
#import "iTermPreferences.h"
#import "iTermRootTerminalView.h"
#import "iTermTabBarControlView.h"
#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "NSDate+iTerm.h"
#import "NSWindow+iTerm.h"
#import "SessionView.h"
#import "PTYTab.h"
#import "PseudoTerminal+Private.h"

@implementation PseudoTerminal (WindowStyle)

#pragma mark - Window Type

iTermWindowType iTermWindowTypeNormalized(iTermWindowType windowType) {
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_NORMAL:
            return windowType;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return WINDOW_TYPE_NORMAL;

        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return WINDOW_TYPE_MAXIMIZED;

        case WINDOW_TYPE_LION_FULL_SCREEN:
            return WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
    }
}

+ (BOOL)windowTypeHasFullSizeContentView:(iTermWindowType)windowType {
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return YES;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return NO;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return YES;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_NORMAL:
            return NO;
    }
}

+ (BOOL)windowType:(iTermWindowType)windowType shouldBeCompactWithSavedWindowType:(iTermWindowType)savedWindowType {
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return YES;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_ACCESSORY:
            return NO;
            break;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return YES;
            break;

        case WINDOW_TYPE_LION_FULL_SCREEN:
            return iTermWindowTypeIsCompact(iTermThemedWindowType(savedWindowType));
    }
    return NO;
}

- (void)updateTitlebarSeparatorStyle {
    if (@available(macOS 11.0, *)) {
        // .none is harmful outside full screen mode because it causes the titlebar to be the wrong color.
        // In order to avoid having the separator in non-fullscreen windows, we use a series of disgusting hacks.
        // See commit 883a3faac0392dbea9464e5255212c96b9f1470c.
        // .none is absolutely necessary in full screen mode to avoid a flashing white line. 
        // See commit 0257ba8f8398240c813c35aa72fe2f652cb11b1e.
        if ([self lionFullScreen] && !exitingLionFullscreen_) {
            self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        } else {
            self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
        }
    }
}

- (NSWindow *)setWindowWithWindowType:(iTermWindowType)windowType
                      savedWindowType:(iTermWindowType)savedWindowType
               windowTypeForStyleMask:(iTermWindowType)windowTypeForStyleMask
                     hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                         initialFrame:(NSRect)initialFrame {
    // For reasons that defy comprehension, you have to do this when switching to full-size content
    // view style mask. Otherwise, you are left with an unusable title bar.
    if (self.window.styleMask & NSWindowStyleMaskTitled) {
        DLog(@"Remove title bar accessory view controllers to appease appkit");
        [self returnTabBarToContentView];
        while (self.window.titlebarAccessoryViewControllers.count > 0) {
            [self.window removeTitlebarAccessoryViewControllerAtIndex:0];
        }
    }

    const BOOL panel = (hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) || (windowType == WINDOW_TYPE_ACCESSORY);
    const BOOL compact = [PseudoTerminal windowType:windowType shouldBeCompactWithSavedWindowType:savedWindowType];
    Class windowClass;
    if (panel) {
        if (compact) {
            windowClass = [iTermCompactPanel class];
        } else {
            windowClass = [iTermPanel class];
        }
    } else {
        if (compact) {
            windowClass = [iTermCompactWindow class];
        } else {
            windowClass = [iTermWindow class];
        }
    }
    NSWindowStyleMask styleMask = [PseudoTerminal styleMaskForWindowType:windowTypeForStyleMask
                                                         savedWindowType:savedWindowType
                                                        hotkeyWindowType:hotkeyWindowType];
    const BOOL defer = (hotkeyWindowType != iTermHotkeyWindowTypeNone);
    NSWindow<PTYWindow> *myWindow = [[windowClass alloc] initWithContentRect:initialFrame
                                                                   styleMask:styleMask
                                                                     backing:NSBackingStoreBuffered
                                                                       defer:defer];
    myWindow.collectionBehavior = [self desiredWindowCollectionBehavior];
    if (windowType != WINDOW_TYPE_LION_FULL_SCREEN) {
        // For some reason, you don't always get the frame you requested. I saw
        // this on OS 10.10 when creating normal windows on a 2-screen display. The
        // frames were within the visible frame of screen #2.
        // However, setting the frame at this point while restoring a Lion fullscreen window causes
        // it to appear with a title bar. TODO: Test if lion fullscreen windows restore on the right
        // monitor.
        [myWindow setFrame:initialFrame display:NO];
    }
    myWindow.movable = [self.class windowTypeIsMovable:windowType];

    [self updateForTransparency:(NSWindow<PTYWindow> *)myWindow];
    [self updateTitlebarSeparatorStyle];
    [self setWindow:myWindow];

    if (@available(macOS 10.16, *)) {
        // TODO
    } else {
        NSView *view = [myWindow it_titlebarViewOfClassWithName:@"_NSTitlebarDecorationView"];
        [view setHidden:YES];
    }

    [self updateVariables];
    return myWindow;
}

+ (BOOL)windowTypeIsMovable:(iTermWindowType)windowType {
    switch (windowType) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return YES;

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return NO;
    }
}

- (BOOL)windowTypeIsFullScreen:(iTermWindowType)windowType {
    switch (windowType) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return NO;
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            return YES;
    }
}

- (BOOL)windowTypeHasTitleBar:(iTermWindowType)newWindowType {
    switch (self.windowType) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return YES;

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            return NO;
    }
}

- (void)changeToWindowType:(iTermWindowType)newWindowType {
    if (newWindowType == self.windowType) {
        return;
    }
    // The general categories of window are:
    // Full screen
    // Edge-attached
    // Normal
    // No title bar
    if (![self windowTypeIsFullScreen:newWindowType] && [self windowTypeIsFullScreen:self.windowType]) {
        // Exit full screen mode.
        [self toggleFullScreenMode:nil completion:^(BOOL ok) {
            if (!ok) {
                return;
            }
            [self changeToWindowType:newWindowType];
        }];
        return;
    }

    // Because this is not a transition out of full screen, we must update the saved window type
    // before calculating the style mask. That is because the style mask calculation decides
    // whether there is a full screen content view based on the *saved* window type, since it wants
    // to preserve the value when entering full screen.
    _savedWindowType = newWindowType;

    switch (newWindowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            if ([self windowTypeHasTitleBar:self.windowType]) {
                [self updateWindowForWindowType:newWindowType];
                self.windowType = newWindowType;
                [self updateTabColors];
                [self.contentView didChangeCompactness];
                [self.contentView layoutSubviews];
            } else {
                self.windowType = newWindowType;
                self.window.movable = [self.class windowTypeIsMovable:newWindowType];
            }
            [self canonicalizeWindowFrame];
            return;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_NORMAL:
            if (![self windowTypeHasTitleBar:self.windowType]) {
                [self updateWindowForWindowType:newWindowType];
                self.windowType = newWindowType;
                [self updateTabColors];
                [self.contentView didChangeCompactness];
                [self.contentView layoutSubviews];
                [self canonicalizeWindowFrame];
            } else {
                self.windowType = newWindowType;
                self.window.movable = [self.class windowTypeIsMovable:newWindowType];
            }
            [self canonicalizeWindowFrame];
            break;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            if (self.anyFullScreen) {
                return;
            }
            [self toggleFullScreenMode:nil];
            return;

        case WINDOW_TYPE_NO_TITLE_BAR:
            if ([self windowTypeHasTitleBar:self.windowType]) {
                [self updateWindowForWindowType:newWindowType];
                self.windowType = newWindowType;
                [self updateTabColors];
                [self.contentView didChangeCompactness];
                [self.contentView layoutSubviews];
                return;
            }
            self.window.movable = [self.class windowTypeIsMovable:newWindowType];
            return;
    }
}

- (BOOL)replaceWindowWithWindowOfType:(iTermWindowType)newWindowType {
    if (_willClose) {
        return NO;
    }
    iTermWindowType effectiveWindowType;
    if (_windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        effectiveWindowType = _savedWindowType;
    } else {
        effectiveWindowType = _windowType;
    }
    if (newWindowType == effectiveWindowType) {
        return NO;
    }
    NSWindow *oldWindow = self.window;
    oldWindow.delegate = nil;
    iTermRootTerminalView *originalCntentView NS_VALID_UNTIL_END_OF_SCOPE = self.contentView;
    [self setWindowWithWindowType:newWindowType
                  savedWindowType:self.savedWindowType
           windowTypeForStyleMask:newWindowType
                 hotkeyWindowType:self.hotkeyWindowType
                     initialFrame:[self traditionalFullScreenFrameForScreen:self.window.screen]];
    [self.window.ptyWindow setLayoutDone];
    iTermRootTerminalView *contentView = self.contentView;
    [contentView removeFromSuperview];
    self.window.contentView = contentView;
    self.window.opaque = NO;
    self.window.delegate = self;
    self.isReplacingWindow = YES;
    [oldWindow close];
    self.isReplacingWindow = NO;
    return YES;
}

- (iTermWindowType)windowTypeImpl {
    return iTermThemedWindowType(_windowType);
}

- (iTermWindowType)savedWindowType {
    return iTermThemedWindowType(_savedWindowType);
}

- (void)setWindowType:(iTermWindowType)windowType {
    _windowType = iTermThemedWindowType(windowType);
}

- (void)updateWindowType {
    if (self.windowType == _windowType) {
        return;
    }
    // -updateWindowForWindowType: assigns a new contentView which causes
    // -viewDidChangeEffectiveAppearance to be called, which eventually calls back into this method.
    // Then cocoa 💩s when you try to change the content view from within setContentView:.
    if (_updatingWindowType) {
        return;
    }
    assert(_windowType == WINDOW_TYPE_NORMAL ||
           _windowType == WINDOW_TYPE_COMPACT ||
           _windowType == WINDOW_TYPE_MAXIMIZED ||
           _windowType == WINDOW_TYPE_COMPACT_MAXIMIZED);
    assert(self.windowType == WINDOW_TYPE_NORMAL ||
           self.windowType == WINDOW_TYPE_COMPACT ||
           self.windowType == WINDOW_TYPE_MAXIMIZED ||
           self.windowType == WINDOW_TYPE_COMPACT_MAXIMIZED);

    _updatingWindowType = YES;
    [self updateWindowForWindowType:self.windowType];
    _updatingWindowType = NO;

    _windowType = self.windowType;
}

- (void)updateWindowForWindowType:(iTermWindowType)windowType {
    if (_willClose) {
        return;
    }
    NSRect frame = self.window.frame;
    NSString *title = [self.window.title copy];
    const BOOL changed = [self replaceWindowWithWindowOfType:windowType];
    [self.window setFrame:frame display:YES];
    [self.window orderFront:nil];
    [self.contentView layoutSubviews];
    self.window.title = title;

    if (changed) {
        [self forceFrame:frame];
    }
}

#pragma mark - Traditional Full Screen

- (void)willEnterTraditionalFullScreenMode {
    DLog(@"willEnterTraditionalFullScreenMode");
    oldFrame_ = self.window.frame;
    oldFrameSizeIsBogus_ = NO;
    DLog(@"Set saved window type to %@", @(self.windowType));
    _savedWindowType = self.windowType;
    if (self.contentView.tabBarControlOnLoan) {
        DLog(@"returnTabBarToContentView");
        [self returnTabBarToContentView];
    }
    [_shortcutAccessoryViewController removeFromParentViewController];
    [self.window setOpaque:NO];
    self.window.alphaValue = 0;
    if (self.ptyWindow.isCompact) {
        [self replaceWindowWithWindowOfType:WINDOW_TYPE_TRADITIONAL_FULL_SCREEN];
        self.windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
    } else {
        self.windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        [self safelySetStyleMask:self.styleMask];
        [self.window setFrame:[self traditionalFullScreenFrameForScreen:self.window.screen]
                      display:YES];
    }
    self.window.alphaValue = 1;
}

- (void)willExitTraditionalFullScreenMode {
    DLog(@"%@", self);
    BOOL shouldForce = NO;
    if ([PseudoTerminal windowType:self.savedWindowType shouldBeCompactWithSavedWindowType:self.savedWindowType]) {
        shouldForce = [self replaceWindowWithWindowOfType:self.savedWindowType];
        self.windowType = self.savedWindowType;
    } else {
        // NOTE: Setting the style mask causes the presentation options to be
        // changed (menu/dock hidden) because refreshTerminal gets called.
        iTermWindowType newType = self.savedWindowType;
        if (newType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
            // Hm, how'd that happen?
            newType = WINDOW_TYPE_NORMAL;
        }
        self.windowType = newType;
        [self safelySetStyleMask:[self styleMask]];
    }
    [[iTermPresentationController sharedInstance] update];

    // This will be close but probably not quite right because tweaking to the decoration size
    // happens later.
    if (oldFrameSizeIsBogus_) {
        oldFrame_.size = [self preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration];
    }
    [self.window setFrame:oldFrame_ display:YES];
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            if (shouldForce) {
                [self forceFrame:oldFrame_];
            }
            break;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            break;
    }

    [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
    [self updateTabBarControlIsTitlebarAccessory];

    DLog(@"toggleFullScreenMode - allocate new terminal");
}

- (void)updateTransparencyBeforeTogglingTraditionalFullScreenMode {
    if (!_fullScreen &&
        [iTermPreferences boolForKey:kPreferenceKeyDisableFullscreenTransparencyByDefault]) {
        oldUseTransparency_ = useTransparency_;
        useTransparency_ = NO;
        restoreUseTransparency_ = YES;
    } else {
        if (_fullScreen && restoreUseTransparency_) {
            useTransparency_ = oldUseTransparency_;
        } else {
            restoreUseTransparency_ = NO;
        }
    }
}

- (void)toggleTraditionalFullScreenModeImpl {
    [SessionView windowDidResize];
    DLog(@"toggleFullScreenMode called");
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    CGFloat savedToolbeltWidth = self.contentView.toolbeltWidth;
    if (!_fullScreen) {
        [self willEnterTraditionalFullScreenMode];
    } else {
        [self willExitTraditionalFullScreenMode];
    }
    [self updateForTransparency:self.ptyWindow];

    [self updateTransparencyBeforeTogglingTraditionalFullScreenMode];
    _fullScreen = !_fullScreen;
    [self didToggleTraditionalFullScreenModeWithSavedToolbeltWidth:savedToolbeltWidth];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad didToggleTraditionalFullScreenMode];
    DLog(@"done toggling trad fullscreen. fullscreen=%@", @(_fullScreen));
}

- (void)didExitTraditionalFullScreenMode {
    NSSize contentSize = self.window.frame.size;
    NSSize decorationSize = self.windowDecorationSize;
    if (self.contentView.shouldShowToolbelt) {
        decorationSize.width += self.contentView.toolbelt.frame.size.width;
    }
    contentSize.width -= decorationSize.width;
    contentSize.height -= decorationSize.height;

    self.window.movable = [self.class windowTypeIsMovable:self.windowType];
    [self fitWindowToTabSize:contentSize];
}

- (void)didToggleTraditionalFullScreenModeWithSavedToolbeltWidth:(CGFloat)savedToolbeltWidth {
    [self didChangeAnyFullScreen];
    [self.contentView.tabBarControl updateFlashing];
    togglingFullScreen_ = YES;
    self.contentView.toolbeltWidth = savedToolbeltWidth;
    [self.contentView constrainToolbeltWidth];
    [self.contentView updateToolbeltForWindow:self.window];
    [self updateUseTransparency];

    if (_fullScreen) {
        DLog(@"toggleFullScreenMode - call adjustFullScreenWindowForBottomBarChange");
        [self fitTabsToWindow];
        [[iTermPresentationController sharedInstance] update];
    }

    // The toolbelt may try to become the first responder.
    [[self window] makeFirstResponder:[[self currentSession] textview]];

    if (!_fullScreen) {
        // Find the largest possible session size for the existing window frame
        // and fit the window to an imaginary session of that size.
        [self didExitTraditionalFullScreenMode];
    }
    togglingFullScreen_ = NO;
    DLog(@"toggleFullScreenMode - calling updateSessionScrollbars");
    [self updateSessionScrollbars];
    DLog(@"toggleFullScreenMode - calling fitTabsToWindow");
    [self.contentView layoutSubviews];

    if (!_fullScreen && oldFrameSizeIsBogus_) {
        // The window frame can be established exactly, now.
        if (oldFrameSizeIsBogus_) {
            oldFrame_.size = [self preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration];
        }
        [self.window setFrame:oldFrame_ display:YES];
    }

    [self fitTabsToWindow];
    DLog(@"toggleFullScreenMode - calling fitWindowToTabs");
    [self fitWindowToTabsExcludingTmuxTabs:YES];
    for (TmuxController *c in [self uniqueTmuxControllers]) {
        [c windowDidResize:self];
    }

    DLog(@"toggleFullScreenMode - calling setWindowTitle");
    [self setWindowTitle];
    DLog(@"toggleFullScreenMode - calling window update");
    [[self window] update];
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    if (_fullScreen) {
        [self notifyTmuxOfWindowResize];
    }
    DLog(@"toggleFullScreenMode returning");
    togglingFullScreen_ = false;

    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            [self forceFrame:self.window.frame];
            break;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            break;
    }

    [self.window performSelector:@selector(makeKeyAndOrderFront:) withObject:nil afterDelay:0];
    [self.window makeFirstResponder:[[self currentSession] textview]];
    if (iTermWindowTypeIsCompact(self.savedWindowType) ||
        iTermWindowTypeIsCompact(self.windowType)) {
        [self didChangeCompactness];
    }
    [self refreshTools];
    [self updateTabColors];
    [self saveTmuxWindowOrigins];
    [self didChangeCompactness];
    [self updateTouchBarIfNeeded:NO];
    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    [self updateWindowMenu];
}

- (BOOL)fullScreenImpl {
    return _fullScreen;
}

- (NSRect)traditionalFullScreenFrameForScreen:(NSScreen *)screen {
    NSRect screenFrame = [screen frame];
    NSRect frameMinusMenuBar = screenFrame;
    frameMinusMenuBar.size.height -= [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    BOOL menuBarIsVisible = NO;

    if ([self fullScreenWindowFrameShouldBeShiftedDownBelowMenuBarOnScreen:screen]) {
        menuBarIsVisible = YES;
    }
    if (menuBarIsVisible) {
        DLog(@"Subtract menu bar from frame");
    } else {
        DLog(@"Do not subtract menu bar from frame");
    }
    return menuBarIsVisible ? frameMinusMenuBar : screenFrame;
}

- (BOOL)fullScreenWindowFrameShouldBeShiftedDownBelowMenuBarOnScreen:(NSScreen *)screen {
    const BOOL wantToHideMenuBar = [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen];
    const BOOL canHideMenuBar = ![[iTermApplication sharedApplication] isUIElement];
    const BOOL menuBarIsHidden = ![[iTermMenuBarObserver sharedInstance] menuBarVisibleOnScreen:screen];
    const BOOL canOverlapMenuBar = [self.window isKindOfClass:[iTermPanel class]];

    DLog(@"Checking if the fullscreen window frame should be shifted down below the menu bar. "
         @"wantToHideMenuBar=%@, canHideMenuBar=%@, menuIsHidden=%@, canOverlapMenuBar=%@",
         @(wantToHideMenuBar), @(canHideMenuBar), @(menuBarIsHidden), @(canOverlapMenuBar));
    if (wantToHideMenuBar && canHideMenuBar) {
        DLog(@"Nope");
        return NO;
    }
    if (menuBarIsHidden) {
        DLog(@"Nope");
        return NO;
    }
    if (canOverlapMenuBar && wantToHideMenuBar) {
        DLog(@"Nope");
        return NO;
    }

    DLog(@"Yep");
    return YES;
}

// Like toggleTraditionalFullScreenMode but does nothing if it's already
// fullscreen. Save to call from a timer.
- (void)enterTraditionalFullScreenMode {
    if (!togglingFullScreen_ &&
        !togglingLionFullScreen_ &&
        ![self anyFullScreen]) {
        [self toggleTraditionalFullScreenMode];
    }
}

- (NSRect)traditionalFullScreenFrame {
    return [self traditionalFullScreenFrameForScreen:self.window.screen];
}

#pragma mark - General Full Screen

- (void)didChangeAnyFullScreen {
    for (PTYSession *session in self.allSessions) {
        [session updateStatusBarStyle];
    }
    if (!togglingLionFullScreen_ && !exitingLionFullscreen_) {
        if (lionFullScreen_) {
            [self safelySetStyleMask:self.styleMask | NSWindowStyleMaskFullScreen];
        } else {
            NSRect frameBefore = self.window.frame;
            [self safelySetStyleMask:[self styleMask]];
            if (!_fullScreen) {
                // Changing the style mask can cause the frame to change.
                [self.window setFrame:frameBefore display:YES];
            }
        }
        [self.contentView layoutSubviews];
    }
    [self.contentView invalidateAutomaticTabBarBackingHiding];
}

- (void)toggleFullScreenModeImpl:(id)sender
                      completion:(void (^)(BOOL))completion {
    DLog(@"toggleFullScreenMode:. window type is %d", self.windowType);
    if (self.toggleFullScreenShouldUseLionFullScreen) {
        [[self ptyWindow] toggleFullScreen:self];
        if (completion) {
            [_toggleFullScreenModeCompletionBlocks addObject:[completion copy]];
        }
        return;
    }

    [self toggleTraditionalFullScreenMode];
    if (completion) {
        completion(YES);
    }
}

- (void)delayedEnterFullscreenImpl {
    if (self.windowType == WINDOW_TYPE_LION_FULL_SCREEN &&
        [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscreen]) {
        if (![[[iTermController sharedInstance] keyTerminalWindow] lionFullScreen]) {
            // call enter(Traditional)FullScreenMode instead of toggle... because
            // when doing a lion resume, the window may be toggled immediately
            // after creation by the window restorer.
            _haveDelayedEnterFullScreenMode = YES;
            [self performSelector:@selector(enterFullScreenMode)
                       withObject:nil
                       afterDelay:0];
        }
    } else if (!_fullScreen) {
        [self performSelector:@selector(enterTraditionalFullScreenMode)
                   withObject:nil
                   afterDelay:0];
    }
}

// Like toggleFullScreenMode but does nothing if it's already fullscreen.
// Save to call from a timer.
- (void)enterFullScreenMode {
    _haveDelayedEnterFullScreenMode = NO;
    if (!togglingFullScreen_ &&
        !togglingLionFullScreen_ &&
        ![self anyFullScreen]) {
        [self toggleFullScreenMode:nil];
    }
}

#pragma mark - Lion Full screen

- (void)windowWillEnterFullScreenImpl:(NSNotification *)notification {
    DLog(@"Window will enter lion fullscreen %@", self);
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    togglingLionFullScreen_ = YES;
    [self didChangeAnyFullScreen];
    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    [self.contentView layoutSubviews];
    [self.contentView didChangeCompactness];
    [self updateTabBarControlIsTitlebarAccessory];
    if (self.windowType != WINDOW_TYPE_LION_FULL_SCREEN) {
        DLog(@"Set saved window type to %@", @(self.windowType));
        _savedWindowType = self.windowType;
        _windowType = WINDOW_TYPE_LION_FULL_SCREEN;
    }
    if ([iTermAdvancedSettingsModel workAroundBigSurBug]) {
        while (self.window.it_titlebarAccessoryViewControllers.count > 0) {
            [self.window removeTitlebarAccessoryViewControllerAtIndex:0];
        }
    }
}

- (void)windowDidEnterFullScreenImpl:(NSNotification *)notification {
    DLog(@"Window did enter lion fullscreen %@", self);

    zooming_ = NO;
    togglingLionFullScreen_ = NO;
    _fullScreenRetryCount = 0;
    lionFullScreen_ = YES;
    [self updateTitlebarSeparatorStyle];
    [self updateTabBarControlIsTitlebarAccessory];
    [self didChangeAnyFullScreen];
    [self.contentView.tabBarControl setFlashing:YES];
    [self.contentView updateToolbeltForWindow:self.window];
    [self.contentView layoutSubviews];
    // Set scrollbars appropriately
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self invalidateRestorableState];
    [self notifyTmuxOfWindowResize];
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    [self saveTmuxWindowOrigins];
    [self.window makeFirstResponder:self.currentSession.textview];
    if (self.didEnterLionFullscreen) {
        self.didEnterLionFullscreen(self);
        self.didEnterLionFullscreen = nil;
    }
    [self updateTouchBarIfNeeded:NO];

    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    [self didFinishFullScreenTransitionSuccessfully:YES];
    [self updateVariables];
}

- (void)didFinishFullScreenTransitionSuccessfully:(BOOL)success {
    DLog(@"didFinishFullScreenTransitionSuccessfully:%@", @(success));
    NSArray<void (^)(BOOL)> *blocks = [_toggleFullScreenModeCompletionBlocks copy];
    [_toggleFullScreenModeCompletionBlocks removeAllObjects];
    for (void (^block)(BOOL) in blocks) {
        block(success);
    }
}

- (void)windowDidFailToEnterFullScreenImpl:(NSWindow *)window {
    DLog(@"windowDidFailToEnterFullScreen %@", self);
    [self didFinishFullScreenTransitionSuccessfully:NO];
    if (!togglingLionFullScreen_) {
        DLog(@"It's ok though because togglingLionFullScreen is off");
        return;
    }
    if (_fullScreenRetryCount < 3) {
        _fullScreenRetryCount++;
        DLog(@"Increment retry count to %@ and schedule an attempt after a delay %@", @(_fullScreenRetryCount), self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DLog(@"About to retry entering full screen with count %@: %@", @(self->_fullScreenRetryCount), self);
            [self.window toggleFullScreen:self];
        });
    } else {
        DLog(@"Giving up after three retries: %@", self);
        togglingLionFullScreen_ = NO;
        _fullScreenRetryCount = 0;
        [self.contentView didChangeCompactness];
        [self.contentView layoutSubviews];
    }
    [self updateVariables];
}

- (void)windowWillExitFullScreenImpl:(NSNotification *)notification {
    DLog(@"Window will exit lion fullscreen %@", self);
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    exitingLionFullscreen_ = YES;
    [self updateTitlebarSeparatorStyle];
    [self updateTabBarControlIsTitlebarAccessory];
    [self updateForTransparency:(NSWindow<PTYWindow> *)self.window];
    [self.contentView.tabBarControl updateFlashing];
    [self fitTabsToWindow];
    self.window.hasShadow = YES;
    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    self.windowType = WINDOW_TYPE_LION_FULL_SCREEN;
    if (![self shouldRevealStandardWindowButtons]) {
        [self hideStandardWindowButtonsAndTitlebarAccessories];
    }
    [self.contentView didChangeCompactness];
    [self.contentView layoutSubviews];
}

- (void)windowDidExitFullScreenImpl:(NSNotification *)notification {
    DLog(@"Window did exit lion fullscreen %@", self);
    exitingLionFullscreen_ = NO;
    zooming_ = NO;
    lionFullScreen_ = NO;

    DLog(@"Window did exit fullscreen. Set window type to %d", self.savedWindowType);
    [self safelySetStyleMask:[PseudoTerminal styleMaskForWindowType:self.savedWindowType
                                                    savedWindowType:self.savedWindowType
                                                   hotkeyWindowType:self.hotkeyWindowType]];
    const iTermWindowType desiredWindowType = self.savedWindowType;
    [self updateWindowForWindowType:desiredWindowType];
    self.windowType = desiredWindowType;
    [self didChangeAnyFullScreen];

    [self updateTabBarControlIsTitlebarAccessory];
    [self.contentView.tabBarControl updateFlashing];
    // Set scrollbars appropriately
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self.contentView layoutSubviews];
    [self invalidateRestorableState];
    [self.contentView updateToolbeltForWindow:self.window];

    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    [self.currentTab recheckBlur];
    [self notifyTmuxOfWindowResize];
    [self saveTmuxWindowOrigins];
    [self.window makeFirstResponder:self.currentSession.textview];
    [self updateTouchBarIfNeeded:NO];
    [self updateUseMetalInAllTabs];
    [self.contentView didChangeCompactness];
    [self.contentView layoutSubviews];
    [self updateForTransparency:self.ptyWindow];
    [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
    [self updateTabColors];  // This updates the window's background colors in case some panes are now transparent.
    [self didFinishFullScreenTransitionSuccessfully:YES];
    [self updateVariables];

    // Windows forget their collection behavior when exiting full screen when the app is a LSUIElement. Issue 8048.
    if ([[iTermApplication sharedApplication] isUIElement]) {
        self.window.collectionBehavior = self.desiredWindowCollectionBehavior;
    }
    self.window.movable = [self.class windowTypeIsMovable:self.windowType];
}

- (BOOL)togglingLionFullScreenImpl {
    return togglingLionFullScreen_;
}

- (IBAction)toggleFullScreenModeImpl:(id)sender {
    [self toggleFullScreenMode:sender completion:nil];
}

#pragma mark - Compact Style

BOOL iTermWindowTypeIsCompact(iTermWindowType windowType) {
    return windowType == WINDOW_TYPE_COMPACT || windowType == WINDOW_TYPE_COMPACT_MAXIMIZED;
}

- (void)didChangeCompactness {
    [self updateForTransparency:(NSWindow<PTYWindow> *)self.window];
    [self.contentView didChangeCompactness];
}

#pragma mark - Style Mask

+ (NSWindowStyleMask)styleMaskForWindowType:(iTermWindowType)windowType
                            savedWindowType:(iTermWindowType)savedWindowType
                           hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    NSWindowStyleMask mask = 0;
    if (hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) {
        mask = NSWindowStyleMaskNonactivatingPanel;
    }
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return (mask |
                    NSWindowStyleMaskFullSizeContentView |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskResizable);

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return mask | NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable;

        case WINDOW_TYPE_COMPACT:
            return (mask |
                    NSWindowStyleMaskFullSizeContentView |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskResizable);

        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return (mask |
                    NSWindowStyleMaskFullSizeContentView |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskTexturedBackground |
                    NSWindowStyleMaskResizable);

        case WINDOW_TYPE_MAXIMIZED:
            return (mask |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskTexturedBackground |
                    NSWindowStyleMaskResizable);

        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_NORMAL:
            if ([self windowTypeHasFullSizeContentView:iTermThemedWindowType(savedWindowType)]) {
                mask |= NSWindowStyleMaskFullSizeContentView;
            }
            return (mask |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskResizable |
                    NSWindowStyleMaskTexturedBackground);
    }
}

- (NSWindowStyleMask)styleMask {
    NSWindowStyleMask styleMask = [PseudoTerminal styleMaskForWindowType:self.windowType
                                                         savedWindowType:self.savedWindowType
                                                        hotkeyWindowType:self.hotkeyWindowType];
    if (self.lionFullScreen || togglingLionFullScreen_) {
        styleMask |= NSWindowStyleMaskFullScreen;
    }
    DLog(@"Returning style mask of %@", @(styleMask));
    return styleMask;
}

- (void)safelySetStyleMask:(NSWindowStyleMask)styleMask {
    assert(!_settingStyleMask);
    _settingStyleMask = YES;
    self.window.styleMask = styleMask;
    _settingStyleMask = NO;
}

#pragma mark - Force Frame

// When you replace the window with one of a different type and then order it
// front, the window gets moved to the first screen after a little while. It's
// not after one spin of the runloop, but just a little while later. I can't
// tell why. But it's horrible and I can't find a better workaround than to
// just muscle it back to the frame we want if it changes for apparently no
// reason for some time.
- (void)forceFrame:(NSRect)frame {
    if (![iTermAdvancedSettingsModel workAroundMultiDisplayOSBug]) {
        return;
    }
    if (NSEqualRects(frame, NSIntersectionRect(frame, NSScreen.screens.firstObject.frame))) {
        DLog(@"Frame is entirely in the first screen. Not forcing.");
        return;
    }
    [self clearForceFrame];
    _forceFrame = frame;
    _screenConfigurationAtTimeOfForceFrame = [self screenConfiguration];
    _forceFrameUntil = [NSDate it_timeSinceBoot] + 2;
    DLog(@"Force frame to %@", NSStringFromRect(frame));
    [self.window setFrame:frame display:YES animate:NO];
}

- (void)clearForceFrame {
    _screenConfigurationAtTimeOfForceFrame = nil;
    _forceFrameUntil = 0;
    _forceFrame = NSZeroRect;
}

@end
