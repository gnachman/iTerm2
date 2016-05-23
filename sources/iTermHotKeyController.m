#import "iTermHotKeyController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermPreferences.h"
#import "iTermPreviousState.h"
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

@interface iTermHotKeyController()<iTermHotKeyDelegate>
@property(nonatomic, retain) iTermPreviousState *previousState;
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
            if ([hotkey windowController] == windowController) {
                return hotkey;
            }
        }
    }
    return nil;
}

- (void)hotKeyWindowWillClose:(PseudoTerminal *)windowController {
    iTermProfileHotKey *hotKey = [self profileHotKeyForWindowController:windowController];
    if (!hotKey) {
        return;
    }
    [_hotKeys removeObject:hotKey];
    [self willHideOrCloseProfileHotKey:hotKey];
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
            [array addObject:[hotkey restorableState]];
        }
    }
    return array;
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

- (BOOL)anyHotkeyBoundToProfile {
    for (__kindof iTermBaseHotKey *hotKey in _hotKeys) {
        if ([hotKey isKindOfClass:[iTermProfileHotKey class]] && [hotKey profile]) {
            return YES;
        }
    }
    return NO;
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

- (void)willHideOrCloseProfileHotKey:(iTermProfileHotKey *)profileHotKey {
    if (![_hotKeys isEqualToArray:@[ profileHotKey ]]) {
        [self.previousState restorePreviouslyActiveApp];
    }
}

- (void)didFinishRollingOutProfileHotKey:(iTermProfileHotKey *)profileHotKey {
    [self.previousState restore];
}

@end
