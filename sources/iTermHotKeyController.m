#import "iTermHotKeyController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermPreviousState.h"
#import "iTermProfilePreferences.h"
#import "iTermShortcutInputView.h"
#import "iTermSystemVersion.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "SBSystemPreferences.h"
#import <Carbon/Carbon.h>
#import <ScriptingBridge/ScriptingBridge.h>

#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

#define HKWLog DLog

@interface iTermHotKeyController()<iTermHotKeyDelegate>
@property(nonatomic, retain) iTermPreviousState *previousState;
@end

@interface NSWindow(HotkeyWindow)
- (BOOL)autoHidesHotKeyWindow;
@end

@interface NSWindowController(HotkeyWindow)
- (BOOL)autoHidesHotKeyWindow;
@end

@implementation iTermHotKeyController {
    NSMutableArray<iTermBaseHotKey *> *_hotKeys;
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
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChange:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
        _hotKeys = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [_hotKeys release];
    [_previousState release];
    [super dealloc];
}

#pragma mark - APIs

- (PseudoTerminal *)topMostVisibleHotKeyWindow {
    // TODO: Verify the order of windows is really front-to-back
    for (NSWindow *window in [NSApp orderedWindows]) {
        PseudoTerminal *term = [[iTermController sharedInstance] terminalForWindow:window];
        if (term.isHotKeyWindow && [[term window] alphaValue] > 0) {
            return term;
        }
    }
    return nil;
}

- (void)showWindowForProfileHotKey:(iTermProfileHotKey *)profileHotKey {
    DLog(@"Show window for profile hotkey %@", profileHotKey);
    [profileHotKey showHotKeyWindow];
}

- (BOOL)eventIsHotkey:(NSEvent *)event {
    for (iTermBaseHotKey *hotKey in _hotKeys) {
        if ([hotKey keyDownEventTriggers:event]) {
            return YES;
        }
    }
    return NO;
}

- (void)addHotKey:(iTermBaseHotKey *)hotKey {
    hotKey.delegate = self;
    [_hotKeys addObject:hotKey];
    [hotKey register];
}

- (void)removeHotKey:(iTermBaseHotKey *)hotKey {
    assert([_hotKeys containsObject:hotKey]);
    [_hotKeys removeObject:hotKey];
    [hotKey unregister];
}

- (void)saveHotkeyWindowStates {
    for (__kindof iTermBaseHotKey *hotKey in _hotKeys) {
        if ([hotKey isKindOfClass:[iTermProfileHotKey class]]) {
            iTermProfileHotKey *profileHotKey = hotKey;
            [profileHotKey saveHotKeyWindowState];
        }
    }
    [NSApp invalidateRestorableState];
}

- (iTermProfileHotKey *)profileHotKeyForWindowController:(PseudoTerminal *)windowController {
    for (__kindof iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey isKindOfClass:[iTermProfileHotKey class]]) {
            if ([[hotkey windowController] weaklyReferencedObject] == windowController) {
                return hotkey;
            }
        }
    }
    return nil;
}

- (void)hotKeyWindowWillClose:(PseudoTerminal *)windowController {
    iTermProfileHotKey *hotKey = [self profileHotKeyForWindowController:windowController];
    if (hotKey) {
        [_hotKeys removeObject:hotKey];
    }
}

- (void)hotkeyPressed:(NSEvent *)event {
    for (iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey keyDownEventTriggers:event]) {
            [hotkey simulatePress];
        }
    }
}

- (void)createHiddenWindowsFromRestorableStates:(NSArray *)states {
    for (__kindof iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey isKindOfClass:[iTermProfileHotKey class]]) {
            iTermProfileHotKey *profileHotKey = hotkey;
            [profileHotKey loadRestorableStateFromArray:states];
            [profileHotKey createWindow];
            [profileHotKey.windowController.window orderOut:nil];  // Issue 4065
        }
    }
}

- (NSArray *)restorableStates {
    NSMutableArray *array = [NSMutableArray array];
    for (__kindof iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey isKindOfClass:[iTermProfileHotKey class]]) {
            NSDictionary *state = [hotkey restorableState];
            if (state) {
                [array addObject:state];
            }
        }
    }
    return array;
}

- (void)autoHideHotKeyWindows {
    [self autoHideHotKeyWindows:self.hotKeyWindowControllers];
}

- (void)autoHideHotKeyWindowsExcept:(NSWindowController *)exception {
    if ([exception isKindOfClass:[PseudoTerminal class]]) {
        PseudoTerminal *term = (PseudoTerminal *)exception;
        BOOL anyWindowRollingOut = [[self profileHotKeys] anyWithBlock:^BOOL(iTermProfileHotKey *anObject) {
            return [anObject rollingOut];
        }];
        if (![term isHotKeyWindow] && !anyWindowRollingOut) {
            // Going from hotkey window to non-hotkey window. Forget the previous state because
            // there's no need to ever return to it now. This happens when navigating explicitly from
            // a hotkey window to a non-hotkey terminal.
            self.previousState = nil;
        }
    }

    NSMutableArray *controllers = [[[self hotKeyWindowControllers] mutableCopy] autorelease];
    [controllers removeObject:exception];
    [self autoHideHotKeyWindows:controllers];
}

- (void)autoHideHotKeyWindow:(NSWindowController *)windowController {
    [self autoHideHotKeyWindows:@[ windowController ]];
}

- (void)autoHideHotKeyWindows:(NSArray<NSWindowController *> *)windowControllersToConsiderHiding {
    DLog(@"** Begin considering autohiding these windows:");
    DLog(@"%@", windowControllersToConsiderHiding);
    DLog(@"From:\n%@", [NSThread callStackSymbols]);
    
    if (![self shouldAutoHide]) {
        DLog(@"shouldAutoHide returned NO");
        return;
    }
    DLog(@"shouldAutoHide returned YES");
    for (PseudoTerminal *hotKeyWindowController in windowControllersToConsiderHiding) {
        DLog(@"Consider auto-hiding %@", hotKeyWindowController);
        if (hotKeyWindowController.window.alphaValue == 0) {
            DLog(@"Alpha is 0 for %@", hotKeyWindowController);
            continue;
        }
        iTermProfileHotKey *profileHotKey =
            [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:hotKeyWindowController];
        if (!profileHotKey.autoHides) {
            DLog(@"Autohide disabled for %@", hotKeyWindowController);
            continue;
        }

        if (profileHotKey.rollingIn) {
            DLog(@"Currently rollkng in %@", hotKeyWindowController);
            continue;
        }

        DLog(@"Auto-hiding %@", hotKeyWindowController);
        BOOL suppressHide =
            [[[NSApp keyWindow] windowController] isKindOfClass:[PseudoTerminal class]];
        [profileHotKey hideHotKeyWindowAnimated:YES suppressHideApp:suppressHide];
    }
}

- (NSArray<iTermHotKeyDescriptor *> *)descriptorsForProfileHotKeysExcept:(Profile *)profile {
    return [self.profileHotKeys mapWithBlock:^id(iTermProfileHotKey *profileHotKey) {
        if (![profileHotKey.profile[KEY_GUID] isEqualToString:profile[KEY_GUID]] &&
            [iTermProfilePreferences stringForKey:KEY_HAS_HOTKEY inProfile:profileHotKey.profile]) {
            NSUInteger keyCode = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE
                                                                      inProfile:profileHotKey.profile];
            NSString *characters = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS
                                                               inProfile:profileHotKey.profile];
            NSEventModifierFlags modifiers = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS
                                                                                  inProfile:profileHotKey.profile];
            return [iTermHotKeyDescriptor descriptorWithKeyCode:keyCode
                                                     characters:characters
                                                      modifiers:modifiers];
        } else {
            return nil;
        }
    }];
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

#pragma mark - Private

- (void)bringHotkeyWindowToFore:(NSWindow *)window {
    DLog(@"Bring hotkey window %@ to front", window);
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
}

- (BOOL)shouldAutoHide {
    NSWindow *keyWindow = [NSApp keyWindow];
    if ([keyWindow respondsToSelector:@selector(autoHidesHotKeyWindow)] &&
        ![keyWindow autoHidesHotKeyWindow]) {
        DLog(@"The key window does not auto-hide the hotkey window: %@", keyWindow);
        return NO;
    }
    NSWindowController *keyWindowController = [keyWindow windowController];
    if ([keyWindowController respondsToSelector:@selector(autoHidesHotKeyWindow)] &&
        ![keyWindowController autoHidesHotKeyWindow]) {
        DLog(@"The key window's controller does not auto-hide the hotkey window: %@", keyWindow);
        return NO;
    }
    
    // Don't hide when a panel becomes key
    if ([keyWindow isKindOfClass:[NSPanel class]]) {
        DLog(@"A panel %@ just became key", keyWindow);
        return NO;
    }

    // We want to dismiss the hotkey window when some other window
    // becomes key. Note that if a popup closes this function shouldn't
    // be called at all because it makes us key before closing itself.
    // If a popup is opening, though, we shouldn't close ourselves.
    if ([iTermWarning showingWarning]) {
        DLog(@"A warning is showing");
        return NO;
    }
    if (keyWindow.sheetParent) {
        DLog(@"The key window is a sheet");
        return NO;
    }

    // The hotkey window can co-exist with these apps.
    static NSString *kAlfredBundleId = @"com.runningwithcrayons.Alfred-2";
    static NSString *kApptivateBundleId = @"se.cocoabeans.apptivate";
    NSArray *bundleIdsToNotDismissFor = @[ kAlfredBundleId, kApptivateBundleId ];
    NSString *frontmostBundleId = [[[NSWorkspace sharedWorkspace] frontmostApplication] bundleIdentifier];
    DLog(@"Frontmost bundle id is %@", frontmostBundleId);
    if ([bundleIdsToNotDismissFor containsObject:frontmostBundleId]) {
        DLog(@"The frontmost application is whitelisted");
        return NO;
    }
    
    if ([iTermAdvancedSettingsModel hotkeyWindowIgnoresSpotlight]) {
        // This tries to detect if the Spotlight window is open.
        if ([[iTermController sharedInstance] keystrokesBeingStolen]) {
            DLog(@"Keystrokes being stolen (spotlight open?)");
            return NO;
        }
    }
    
    NSArray<PTYWindow *> *keyTerminalWindows = [[iTermController sharedInstance] keyTerminalWindows];
    NSArray<PseudoTerminal *> *hotKeyWindowControllers = self.hotKeyWindowControllers;
    BOOL nonHotkeyTerminalIsKey = [keyTerminalWindows containsObjectBesidesObjectsInArray:hotKeyWindowControllers];
    BOOL haveMain = [[iTermController sharedInstance] anyWindowIsMain];
    DLog(@"main window is %@, key terminals are %@, hotkey terminals are %@", [NSApp mainWindow], keyTerminalWindows, hotKeyWindowControllers);
    if (haveMain && !nonHotkeyTerminalIsKey) {
        // Issue 1251: we can take this path when a "clipboard manager" window is open.
        DLog(@"Some non-terminal window is now main. Key terminal windows are %@",
             [[iTermController sharedInstance] keyTerminalWindows]);
        return NO;
    }
    
//    if ([keyTerminalWindows anyWithBlock:^BOOL(PTYWindow *window) { return [window.windowController isHotKeyWindow]; }]) {
//        DLog(@"A hotkey window is key");
//        return NO;
//    }
    return YES;
}

#pragma mark - Accessors

- (NSArray<PseudoTerminal *> *)hotKeyWindowControllers {
    NSArray<iTermProfileHotKey *> *profileHotKeys = [self profileHotKeys];
    NSArray<PseudoTerminal *> *hotKeyWindowControllers = [profileHotKeys mapWithBlock:^id(iTermProfileHotKey *profileHotKey) {
        return profileHotKey.windowController.weaklyReferencedObject;
    }];
    return hotKeyWindowControllers;
}

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

- (NSArray *)visibleWindowControllers {
    NSArray *allWindowControllers = self.hotKeyWindowControllers;
    return [allWindowControllers filteredArrayUsingBlock:^BOOL(id anObject) {
        PseudoTerminal *windowController = anObject;
        return windowController.window.isVisible && windowController.window.alphaValue > 0;
    }];
}

- (NSArray<iTermProfileHotKey *> *)profileHotKeys {
    return [_hotKeys filteredArrayUsingBlock:^BOOL(id anObject) {
        return [anObject isKindOfClass:[iTermProfileHotKey class]];
    }];
}

#pragma mark - iTermHotKeyDelegate

- (void)suppressHideApp {
    [self.previousState suppressHideApp];
}

- (void)storePreviouslyActiveApp {
    if (!self.previousState || ![NSApp isActive]) {
        self.previousState = [[[iTermPreviousState alloc] init] autorelease];
    }
}

- (BOOL)anyHotKeyWindowIsKey {
    NSWindowController *windowController = [[NSApp keyWindow] windowController];
    if ([windowController isKindOfClass:[PseudoTerminal class]]) {
        PseudoTerminal *term = (PseudoTerminal *)windowController;
        if ([term isHotKeyWindow]) {
            return YES;
        }
    }
    return NO;
}

- (void)didFinishRollingOutProfileHotKey:(iTermProfileHotKey *)profileHotKey {
    // Restore the previous state (key window or active app) unless we switched
    // to another hotkey window.
    if (![self anyHotKeyWindowIsKey]) {
        DLog(@"Restoring the previous state");
        [self.previousState restore];
        self.previousState = nil;
    }
}

@end

