#import "iTermProfileHotKey.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "PseudoTerminal.h"

static NSString *const kGUID = @"GUID";
static NSString *const kArrangement = @"Arrangement";

@interface iTermProfileHotKey()
@property(nonatomic, copy) NSString *profileGuid;

@property(nonatomic, retain) NSDictionary *restorableState;

@property(nonatomic, readwrite) BOOL rollingIn;

@property(nonatomic, readwrite, getter=isHotKeyWindowOpen) BOOL hotKeyWindowOpen;

@property(nonatomic, retain) PseudoTerminal *windowController;

@end

@implementation iTermProfileHotKey

- (instancetype)initWithKeyCode:(NSUInteger)keyCode
                      modifiers:(NSEventModifierFlags)modifiers
                        profile:(Profile *)profile {
    self = [super initWithKeyCode:keyCode modifiers:modifiers];
    if (self) {
        _profileGuid = [profile[KEY_GUID] copy];
    }
    return self;
}

- (void)dealloc {
    [_restorableState release];
    [_profileGuid release];
    [super dealloc];
}

#pragma mark - APIs

- (Profile *)profile {
    return [[ProfileModel sharedInstance] bookmarkWithGuid:_profileGuid];
}

- (void)createWindow {
    if (self.windowController) {
        return;
    }

    DLog(@"Create new window controller for profile hotkey");
    self.windowController = [self windowControllerFromRestorableState];
    if (!self.windowController) {
        self.windowController = [self windowControllerFromProfile:[self profile]];
    }
    if (!self.windowController) {
        return;
    }

    if ([iTermAdvancedSettingsModel hotkeyWindowFloatsAboveOtherWindows]) {
        self.windowController.window.level = NSFloatingWindowLevel;
    } else {
        self.windowController.window.level = NSNormalWindowLevel;
    }
    self.windowController.isHotKeyWindow = YES;

    [self.windowController.window setAlphaValue:0];
    if (self.windowController.windowType != WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [self.windowController.window setCollectionBehavior:self.windowController.window.collectionBehavior & ~NSWindowCollectionBehaviorFullScreenPrimary];
    }
}

- (void)rollIn {
    DLog(@"Roll in [show] hotkey window");

    _rollingIn = YES;
    [NSApp activateIgnoringOtherApps:YES];
    [self.windowController.window makeKeyAndOrderFront:nil];
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self rollInFinished];
    }];
    [[self.windowController.window animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
}

- (void)rollOut {
    DLog(@"Roll out [hide] hotkey window");
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

    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self didFinishRollingOut];
    }];
    self.windowController.window.animator.alphaValue = 0;
    [NSAnimationContext endGrouping];
}

- (void)saveHotKeyWindowState {
    BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
    NSDictionary *arrangement = [self.windowController arrangementExcludingTmuxTabs:YES
                                                                  includingContents:includeContents];
    self.restorableState = @{ kGUID: self.profileGuid,
                              kArrangement: arrangement };
}

- (void)loadRestorableStateFromArray:(NSArray *)states {
    for (NSDictionary *state in states) {
        if ([state[kGUID] isEqualToString:self.profileGuid]) {
            self.restorableState = state;
            return;
        }
    }
}

#pragma mark - Protected

- (void)hotKeyPressed {
    DLog(@"toggle window");
    if (self.windowController) {
        DLog(@"already have a hotkey window created");
        if (self.windowController.window.alphaValue == 1) {
            DLog(@"hotkey window opaque");
            [self hideHotKeyWindow];
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
    if (!arrangement) {
        // If the user had an arrangement saved in user defaults, restore it and delete it. This is
        // how hotkey window state was preserved prior to 12/9/14 when it was moved into application-
        // level restorable state. Eventually this migration code can be deleted.
        NSString *const kUserDefaultsHotkeyWindowArrangement = @"NoSyncHotkeyWindowArrangement";  // DEPRECATED
        arrangement =
            [[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaultsHotkeyWindowArrangement];
        if (arrangement) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserDefaultsHotkeyWindowArrangement];
        }
    }
    self.restorableState = nil;
    if (!arrangement) {
        return nil;
    }

    PseudoTerminal *term = [PseudoTerminal terminalWithArrangement:arrangement];
    if (term) {
        [[iTermController sharedInstance] addTerminalWindow:term];
    }
    return term;
}

- (PseudoTerminal *)windowControllerFromProfile:(Profile *)hotkeyProfile {
    if (!hotkeyProfile) {
        return nil;
    }
    if ([[hotkeyProfile objectForKey:KEY_WINDOW_TYPE] intValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
        // Lion fullscreen doesn't make sense with hotkey windows. Change
        // window type to traditional fullscreen.
        NSMutableDictionary *replacement = [[hotkeyProfile mutableCopy] autorelease];
        replacement[KEY_WINDOW_TYPE] = @(WINDOW_TYPE_TRADITIONAL_FULL_SCREEN);
        hotkeyProfile = replacement;
    }
    PTYSession *session = [[iTermController sharedInstance] launchBookmark:hotkeyProfile
                                                                inTerminal:nil
                                                                   withURL:nil
                                                                  isHotkey:YES
                                                                   makeKey:YES
                                                               canActivate:YES
                                                                   command:nil
                                                                     block:nil];
    if (session) {
        return [[iTermController sharedInstance] terminalWithSession:session];
    } else {
        return nil;
    }
}

- (void)rollInFinished {
    _rollingIn = NO;
    [self.windowController.window makeKeyAndOrderFront:nil];
    [self.windowController.window makeFirstResponder:self.windowController.currentSession.textview];
    [[self.windowController currentTab] recheckBlur];
}

- (void)didFinishRollingOut {
    _rollingOut = NO;
    
    [self.delegate didFinishRollingOutProfileHotKey:self];

    // NOTE: There used be an option called "closing hotkey switches spaces". I've removed the
    // "off" behavior and made the "on" behavior the only option. Various things didn't work
    // right, and the worst one was in this thread: "[iterm2-discuss] Possible bug when using Hotkey window?"
    // where clicks would be swallowed up by the invisible hotkey window. The "off" mode would do
    // this:
    // [[term window] orderWindow:NSWindowBelow relativeTo:0];
    // And the window was invisible only because its alphaValue was set to 0 elsewhere.
    [self.windowController.window orderOut:self];
}

- (BOOL)autoHides {
    // TODO: Add a new pref and return that from the profile.
    return [iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides];
}

- (void)hideHotKeyWindow {
    const BOOL activateStickyHotkeyWindow = (!self.autoHides &&
                                             !self.windowController.window.isKeyWindow);
    if (activateStickyHotkeyWindow && ![NSApp isActive]) {
        DLog(@"Storing previously active app");
        [self.delegate storePreviouslyActiveApp];
    }
    const BOOL hotkeyWindowOnOtherSpace = ![self.windowController.window isOnActiveSpace];
    if (hotkeyWindowOnOtherSpace || activateStickyHotkeyWindow) {
        DLog(@"Hotkey window is active on another space, or else it doesn't autohide but isn't key. Switch to it.");
        [NSApp activateIgnoringOtherApps:YES];
        [self.windowController.window makeKeyAndOrderFront:nil];
    } else {
        DLog(@"Hide hotkey window");
        [self hideHotKeyWindowAnimated:YES suppressHideApp:NO];
    }
}

- (void)showHotKeyWindow {
    DLog(@"showHotKeyWindow: %@", self);
    [self.delegate storePreviouslyActiveApp];

    if (!self.windowController) {
        DLog(@"Create new hotkey window");
        [self createWindow];
    }
    [self rollIn];
}

- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp {
    DLog(@"Hide hotkey window. animated=%@ suppressHideApp=%@", @(animated), @(suppressHideApp));

    if (suppressHideApp) {
        [self.delegate suppressHideApp];
    }
    if (!animated) {
        [self fastHideHotKeyWindow];
    }

    // This used to iterate over hotkeyTerm.window.sheets, which seemed to
    // work, but sheets wasn't defined prior to 10.9. Consider going back to
    // that technique if this doesn't work well.
    while (self.windowController.window.attachedSheet) {
        [NSApp endSheet:self.windowController.window.attachedSheet];
    }
    DLog(@"Hide hotkey window.");
    // Note: the test for alpha is because when you become an LSUIElement, the
    // window's alpha could be 1 but it's still invisible.
    if (self.windowController.window.alphaValue > 0) {
        DLog(@"key window is %@", [NSApp keyWindow]);
        NSWindow *theKeyWindow = [NSApp keyWindow];
        if (!theKeyWindow ||
            ([theKeyWindow isKindOfClass:[PTYWindow class]] &&
             [(PseudoTerminal*)[theKeyWindow windowController] isHotKeyWindow])) {
                [self.delegate willHideOrCloseProfileHotKey:self];
            }
    }
    [self rollOut];
}

- (void)fastHideHotKeyWindow {
    DLog(@"fastHideHotKeyWindow");
    if (self.windowController) {
        DLog(@"fastHideHotKeyWindow - found a hot term");
        // Temporarily tell the hotkeywindow that it's not hot so that it doesn't try to hide itself
        // when losing key status.
        self.windowController.isHotKeyWindow = NO;

        // Immediately hide the hotkey window.
        [self.windowController.window orderOut:nil];
        self.windowController.window.alphaValue = 0;

        // Restore hotkey window's status.
        self.windowController.isHotKeyWindow = YES;
    }
}

@end
