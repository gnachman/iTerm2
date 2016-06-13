#import "iTermHotKeyController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermPreferences.h"
#import "iTermShortcutInputView.h"
#import "iTermSystemVersion.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "SBSystemPreferences.h"
#import <Carbon/Carbon.h>
#import <ScriptingBridge/ScriptingBridge.h>

#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

#define HKWLog DLog

const NSEventModifierFlags kHotKeyModifierMask = (NSCommandKeyMask |
                                                  NSAlternateKeyMask |
                                                  NSShiftKeyMask |
                                                  NSControlKeyMask);


@interface iTermHotKeyController()
// For restoring previously active app when exiting hotkey window.
@property(nonatomic, copy) NSNumber *previouslyActiveAppPID;
@end

@implementation iTermHotKeyController {
    // Records the index of the front terminal in -[iTermController terminals]
    // at the time the hotkey window was opened. -1 if invalid. Used to bring
    // the proper window front when hiding "quickly" (when entering Expose
    // while a hotkey window is open). TODO: I'm not sure why this is necessary.
    NSInteger _savedIndexOfFrontTerminal;

    // Set while window is appearing.
    BOOL _rollingIn;

    // Set while window is disappearing.
    BOOL _rollingOut;

    // Set when iTerm was key at the time the hotkey window was opened.
    BOOL _itermWasActiveWhenHotkeyOpened;

    // The keycode that opens the hotkey window
    int _hotkeyCode;

    // Modifiers for the keypress that opens the hotkey window
    int _hotkeyModifiers;

    // The registered carbon hotkey that listens for hotkey presses.
    iTermHotKey *_carbonHotKey;
}
    
+ (iTermHotKeyController *)sharedInstance {
    static iTermHotKeyController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _savedIndexOfFrontTerminal = -1;
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChange:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [_restorableState release];
    [_previouslyActiveAppPID release];
    [super dealloc];
}

#pragma mark - APIs

- (void)closeWindowReturningToHotkeyWindowIfPossible:(NSWindow *)window {
    PseudoTerminal *hotkeyTerm = [self hotKeyWindow];
    if (hotkeyTerm && [[hotkeyTerm window] alphaValue]) {
        [[hotkeyTerm window] makeKeyWindow];
    }
    [window close];
}

- (void)showHotKeyWindow {
    [self storePreviouslyActiveApp];
    _itermWasActiveWhenHotkeyOpened = [NSApp isActive];
    _savedIndexOfFrontTerminal = [self indexOfFrontTerminal];

    PseudoTerminal *hotkeyTerm = [self hotKeyWindow];
    if (hotkeyTerm) {
        HKWLog(@"Showing existing hotkey window");
    } else {
        HKWLog(@"Create new hotkey window");
        hotkeyTerm = [self createHotKeyWindow];
        if (!hotkeyTerm) {
            HKWLog(@"Failed to create hotkey window");
            return;
        }
    }
    
    [self rollInWindowController:hotkeyTerm];
}

- (PseudoTerminal *)createHotKeyWindow {
    PseudoTerminal *term = [self hotKeyWindow];
    if (term) {
        return term;
    }

    HKWLog(@"Open hotkey window");
    term = [self windowFromRestorableState];
    if (!term) {
        term = [self windowFromProfile:[self profile]];
    }
    if (!term) {
        return nil;
    }

    if ([iTermAdvancedSettingsModel hotkeyWindowFloatsAboveOtherWindows]) {
        term.window.level = NSFloatingWindowLevel;
    } else {
        term.window.level = NSNormalWindowLevel;
    }
    [term setIsHotKeyWindow:YES];

    [[term window] setAlphaValue:0];
    if ([term windowType] != WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [[term window] setCollectionBehavior:[[term window] collectionBehavior] & ~NSWindowCollectionBehaviorFullScreenPrimary];
    }
    return term;
}

- (void)hideHotKeyWindowAnimated:(BOOL)animated
                 suppressHideApp:(BOOL)suppressHideApp {
    HKWLog(@"Hide hotkey window. animated=%@ suppressHideApp=%@", @(animated), @(suppressHideApp));

    if (suppressHideApp) {
        _itermWasActiveWhenHotkeyOpened = YES;
    }
    if (!animated) {
        [self fastHideHotKeyWindow];
    }

    PseudoTerminal *hotkeyTerm = [self hotKeyWindow];
    // This used to iterate over hotkeyTerm.window.sheets, which seemed to
    // work, but sheets wasn't defined prior to 10.9. Consider going back to
    // that technique if this doesn't work well.
    while (hotkeyTerm.window.attachedSheet) {
        [NSApp endSheet:hotkeyTerm.window.attachedSheet];
    }
    HKWLog(@"Hide hotkey window.");
    // Note: the test for alpha is because when you become an LSUIElement, the
    // window's alpha could be 1 but it's still invisible.
    if ([[hotkeyTerm window] alphaValue] > 0) {
        HKWLog(@"key window is %@", [NSApp keyWindow]);
        NSWindow *theKeyWindow = [NSApp keyWindow];
        if (!theKeyWindow ||
            ([theKeyWindow isKindOfClass:[PTYWindow class]] &&
             [(PseudoTerminal*)[theKeyWindow windowController] isHotKeyWindow])) {
                [self restorePreviouslyActiveApp];
            }
    }
    [self rollOut:hotkeyTerm];
}

- (BOOL)eventIsHotkey:(NSEvent *)event {
    return (_hotkeyCode &&
            ([event modifierFlags] & kHotKeyModifierMask) == (_hotkeyModifiers & kHotKeyModifierMask) &&
            [event keyCode] == _hotkeyCode);
}

- (BOOL)registerHotkey:(NSUInteger)keyCode modifiers:(NSEventModifierFlags)modifiers {
    if (_carbonHotKey) {
        [self unregisterHotkey];
    }
    _hotkeyCode = keyCode;
    _hotkeyModifiers = modifiers & kHotKeyModifierMask;

    _carbonHotKey =
        [[[iTermCarbonHotKeyController sharedInstance] registerKeyCode:keyCode
                                                             modifiers:_hotkeyModifiers
                                                                target:self
                                                              selector:@selector(carbonHotkeyPressed:)
                                                              userData:nil] retain];
    return YES;
}

- (void)unregisterHotkey {
    _hotkeyCode = 0;
    _hotkeyModifiers = 0;
    [[iTermCarbonHotKeyController sharedInstance] unregisterHotKey:_carbonHotKey];
    [_carbonHotKey release];
    _carbonHotKey = nil;
}

- (void)saveHotkeyWindowState {
    PseudoTerminal *term = [self hotKeyWindow];
    if (term) {
        BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
        self.restorableState = [term arrangementExcludingTmuxTabs:YES
                                                includingContents:includeContents];
    } else {
        self.restorableState = nil;
    }
    [NSApp invalidateRestorableState];
}

- (void)restorePreviouslyActiveApp {
    if (!_previouslyActiveAppPID) {
        return;
    }

    NSRunningApplication *app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:[_previouslyActiveAppPID intValue]];

    if (app) {
        DLog(@"Restore app %@", app);
        [app activateWithOptions:0];
    }
    self.previouslyActiveAppPID = nil;
}

- (void)hotkeyPressed {
    HKWLog(@"hotkey pressed");
    if ([iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow]) {
        [self toggleHotKeyWindow];
    } else {
        [self toggleApp];
    }
}
    
#pragma mark - Notifications

- (void)activeSpaceDidChange:(NSNotification *)notification {
    PseudoTerminal *term = [self hotKeyWindow];
    NSWindow *window = [term window];
    // Issue 3199: With a non-autohiding hotkey window that is on all spaces, changing spaces makes
    // another app key, leaving the hotkey window open underneath other windows.
    if ([window isVisible] &&
        window.isOnActiveSpace &&
        ([window collectionBehavior] & NSWindowCollectionBehaviorCanJoinAllSpaces) &&
        ![iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides]) {
      DLog(@"Just switched spaces. Hotkey window is visible, joins all spaces, and does not autohide. Show it in half a second.");
        [self performSelector:@selector(bringHotkeyWindowToFore:) withObject:window afterDelay:0.5];
    }
    if ([window isVisible] && window.isOnActiveSpace && [term fullScreen]) {
        // Issue 4136: If you press the hotkey while in a fullscreen app, the
        // dock stays up. Looks like the OS doesn't respect the window's
        // presentation option when switching from a fullscreen app, so we have
        // to toggle it after the switch is complete.
        [term showMenuBar];
        [term hideMenuBar];
    }
}

#pragma mark - Actions

- (void)carbonHotkeyPressed:(NSDictionary *)userInfo {
    if (![[[iTermApplication sharedApplication] delegate] workspaceSessionActive]) {
        return;
    }

    [self hotkeyPressed];
}

#pragma mark - Private

- (void)fastHideHotKeyWindow {
    HKWLog(@"fastHideHotKeyWindow");
    PseudoTerminal *term = [self hotKeyWindow];
    if (term) {
        HKWLog(@"fastHideHotKeyWindow - found a hot term");
        // Temporarily tell the hotkeywindow that it's not hot so that it doesn't try to hide itself
        // when losing key status.
        BOOL temp = [term isHotKeyWindow];
        [term setIsHotKeyWindow:NO];

        // Immediately hide the hotkey window.
        [[term window] orderOut:nil];

        [[term window] setAlphaValue:0];

        // Immediately show all other windows.
        [self showNonHotKeyWindowsAndSetAlphaTo:1];

        // Restore hotkey window's status.
        [term setIsHotKeyWindow:temp];
    }
}

- (NSInteger)indexOfFrontTerminal {
    PseudoTerminal *hotkeyTerm = [self hotKeyWindow];
    if (!hotkeyTerm || ![NSApp isActive]) {
        return -1;
    }

    __block NSInteger result = -1;
    [[[iTermController sharedInstance] terminals] enumerateObjectsUsingBlock:^(PseudoTerminal *_Nonnull term,
                                                                               NSUInteger idx,
                                                                               BOOL *_Nonnull stop) {
        if (term != hotkeyTerm && [[term window] isKeyWindow]) {
            result = idx;
        }
    }];
    
    return result;
}

- (PseudoTerminal *)windowFromRestorableState {
    PseudoTerminal *term = nil;
    NSDictionary *arrangement = [[self.restorableState copy] autorelease];
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
    if (arrangement) {
        term = [PseudoTerminal terminalWithArrangement:arrangement];
        if (term) {
            [[iTermController sharedInstance] addTerminalWindow:term];
        }
    }
    return term;
}

- (PseudoTerminal *)windowFromProfile:(Profile *)hotkeyProfile {
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

- (void)rollInWindowController:(PseudoTerminal *)term {
    HKWLog(@"Roll in [show] hotkey window");

    _rollingIn = YES;
    [NSApp activateIgnoringOtherApps:YES];
    [[term window] makeKeyAndOrderFront:nil];
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[iTermHotKeyController sharedInstance] rollInFinished];
    }];
    [[[term window] animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
}

- (void)bringHotkeyWindowToFore:(NSWindow *)window {
    DLog(@"Bring hotkey window %@ to front", window);
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
}

- (void)rollInFinished {
    _rollingIn = NO;
    PseudoTerminal* term = [self hotKeyWindow];
    [[term window] makeKeyAndOrderFront:nil];
    [[term window] makeFirstResponder:[[term currentSession] textview]];
    [[[[iTermHotKeyController sharedInstance] hotKeyWindow] currentTab] recheckBlur];
}

- (void)showNonHotKeyWindowsAndSetAlphaTo:(CGFloat)newAlphaValue {
    PseudoTerminal *hotkeyTerm = [self hotKeyWindow];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        [[term window] setAlphaValue:newAlphaValue];
        if (term != hotkeyTerm) {
            [[term window] makeKeyAndOrderFront:nil];
        }
    }
    // Unhide all windows and bring the one that was at the top to the front.
    NSInteger i = _savedIndexOfFrontTerminal;
    if (i >= 0 && i < [[[iTermController sharedInstance] terminals] count]) {
        [[[[[iTermController sharedInstance] terminals] objectAtIndex:i] window] makeKeyAndOrderFront:nil];
    }
}

- (void)rollOut:(PseudoTerminal *)term {
    HKWLog(@"Roll out [hide] hotkey window");
    if (_rollingOut) {
        HKWLog(@"Already rolling out");
        return;
    }
    // Note: the test for alpha is because when you become an LSUIElement, the
    // window's alpha could be 1 but it's still invisible.
    if ([[term window] alphaValue] == 0) {
        HKWLog(@"RollOutHotkeyTerm returning because term isn't visible.");
        return;
    }
    BOOL temp = [term isHotKeyWindow];

    _rollingOut = YES;

    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        _rollingOut = NO;
        [self didFinishRollingOutHotkeyWindow:term];
    }];
    [[[term window] animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];

    [term setIsHotKeyWindow:temp];
}

- (void)didFinishRollingOutHotkeyWindow:(PseudoTerminal *)hotKeyTerm {
    if (!_itermWasActiveWhenHotkeyOpened) {
        // TODO: This is weird. What is its purpose? After I fix the bug where non-hotkey windows
        // get ordered front is this still necessary?
        [NSApp hide:nil];
        [self performSelector:@selector(unhide) withObject:nil afterDelay:0.1];
    } else {
        PseudoTerminal *currentTerm = [[iTermController sharedInstance] currentTerminal];
        if (currentTerm && ![currentTerm isHotKeyWindow] && [currentTerm fullScreen]) {
            [currentTerm hideMenuBar];
        } else {
            [currentTerm showMenuBar];
        }
    }

    // NOTE: There used be an option called "closing hotkey switches spaces". I've removed the
    // "off" behavior and made the "on" behavior the only option. Various things didn't work
    // right, and the worst one was in this thread: "[iterm2-discuss] Possible bug when using Hotkey window?"
    // where clicks would be swallowed up by the invisible hotkey window. The "off" mode would do
    // this:
    // [[term window] orderWindow:NSWindowBelow relativeTo:0];
    // And the window was invisible only because its alphaValue was set to 0 elsewhere.
    [[hotKeyTerm window] orderOut:self];
}

- (void)unhide {
    [NSApp unhideWithoutActivation];
    for (PseudoTerminal *terminal in [[iTermController sharedInstance] terminals]) {
        if (![terminal isHotKeyWindow]) {
            [[[terminal window] animator] setAlphaValue:1];
        }
    }
}

- (void)storePreviouslyActiveApp {
    NSDictionary *activeAppDict = [[NSWorkspace sharedWorkspace] activeApplication];
    HKWLog(@"Active app is %@", activeAppDict);
    if (![[activeAppDict objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
        self.previouslyActiveAppPID = activeAppDict[@"NSApplicationProcessIdentifier"];
    } else {
        self.previouslyActiveAppPID = nil;
    }
}

- (void)hideHotkeyWindow:(PseudoTerminal *)hotkeyTerm {
    const BOOL activateStickyHotkeyWindow = (![iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides] &&
                                             ![[hotkeyTerm window] isKeyWindow]);
    if (activateStickyHotkeyWindow && ![NSApp isActive]) {
        HKWLog(@"Storing previously active app");
        [[iTermHotKeyController sharedInstance] storePreviouslyActiveApp];
    }
    const BOOL hotkeyWindowOnOtherSpace = ![[hotkeyTerm window] isOnActiveSpace];
    if (hotkeyWindowOnOtherSpace || activateStickyHotkeyWindow) {
        DLog(@"Hotkey window is active on another space, or else it doesn't autohide but isn't key. Switch to it.");
        [NSApp activateIgnoringOtherApps:YES];
        [[hotkeyTerm window] makeKeyAndOrderFront:nil];
    } else {
        DLog(@"Hide hotkey window");
        [[iTermHotKeyController sharedInstance] hideHotKeyWindowAnimated:YES suppressHideApp:NO];
    }
}

- (void)toggleHotKeyWindow {
    HKWLog(@"hotkey window enabled");
    PseudoTerminal *hotkeyTerm = [self hotKeyWindow];
    if (hotkeyTerm) {
        HKWLog(@"already have a hotkey window created");
        if ([[hotkeyTerm window] alphaValue] == 1) {
            HKWLog(@"hotkey window opaque");
            [self hideHotkeyWindow:hotkeyTerm];
        } else {
            HKWLog(@"hotkey window not opaque");
            [[iTermHotKeyController sharedInstance] showHotKeyWindow];
        }
    } else {
        HKWLog(@"no hotkey window created yet");
        [[iTermHotKeyController sharedInstance] showHotKeyWindow];
    }
}

- (void)toggleApp {
    if ([NSApp isActive]) {
        PreferencePanel *prefsWindowController = [PreferencePanel sharedInstance];
        NSWindow *prefsWindow = [prefsWindowController window];
        NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
        if (prefsWindow != keyWindow ||
            ![[prefsWindowController hotkeyField] textFieldIsFirstResponder]) {
            [NSApp hide:nil];
        }
    } else {
        iTermController *controller = [iTermController sharedInstance];
        int numberOfTerminals = [controller numberOfTerminals];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        if (numberOfTerminals == 0) {
            [controller newWindow:nil];
        }
    }
}

#pragma mark - Accessors

- (BOOL)isHotKeyWindowOpen {
    return [[[self hotKeyWindow] window] alphaValue] > 0;
}

- (PseudoTerminal *)hotKeyWindow {
    NSArray<PseudoTerminal *> *terminals = [[iTermController sharedInstance] terminals];
    for (PseudoTerminal *term in terminals) {
        if ([term isHotKeyWindow]) {
            return term;
        }
    }
    return nil;
}

- (Profile *)profile {
    NSString *guid = [iTermPreferences stringForKey:kPreferenceKeyHotkeyProfileGuid];
    if (guid) {
        return [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    } else {
        return nil;
    }
}

- (BOOL)haveHotkeyBoundToWindow {
    return [iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow] && [self profile] != nil;
}

@end
