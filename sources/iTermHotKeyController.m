#import "iTermHotKeyController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
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
#import "PTYWindow.h"
#import "SBSystemPreferences.h"
#import <Carbon/Carbon.h>
#import <ScriptingBridge/ScriptingBridge.h>

#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

NSString *const TERMINAL_ARRANGEMENT_PROFILE_GUID = @"Hotkey Profile GUID";

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
    NSMutableArray<iTermProfileHotKey *> *_profileHotKeysBirthingWindows;
    BOOL _disableAutoHide;
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        _hotKeys = [[NSMutableArray alloc] init];
        _profileHotKeysBirthingWindows = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_hotKeys release];
    [_previousState release];
    [_profileHotKeysBirthingWindows release];
    [super dealloc];
}

#pragma mark - APIs

- (BOOL)showWindowForProfileHotKey:(iTermProfileHotKey *)profileHotKey url:(NSURL *)url {
    DLog(@"Show window for profile hotkey %@", profileHotKey);
    return [profileHotKey showHotKeyWindowCreatingWithURLIfNeeded:url];
}

- (BOOL)eventIsHotkey:(NSEvent *)event {
    for (iTermBaseHotKey *hotKey in _hotKeys) {
        if ([hotKey keyDownEventIsHotKeyShortcutPress:event]) {
            return YES;
        }
    }
    return NO;
}

- (void)addHotKey:(iTermBaseHotKey *)hotKey {
    DLog(@"Add %@ from %@", hotKey, [NSThread callStackSymbols]);
    hotKey.delegate = self;
    [_hotKeys addObject:hotKey];
    [hotKey register];
}

- (void)removeHotKey:(iTermBaseHotKey *)hotKey {
    DLog(@"Remove %@ from %@", hotKey, [NSThread callStackSymbols]);
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
            if ([[hotkey windowController] weaklyReferencedObject] == windowController ||
                [hotkey windowControllerBeingBorn] == windowController) {
                return hotkey;
            }
        }
    }
    return nil;
}

- (void)hotkeyPressed:(NSEvent *)event {
    for (iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey keyDownEventIsHotKeyShortcutPress:event]) {
            [hotkey simulatePress];
        }
    }
}

- (void)createHiddenWindowsFromRestorableStates:(NSArray *)states {
    for (__kindof iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey isKindOfClass:[iTermProfileHotKey class]]) {
            iTermProfileHotKey *profileHotKey = hotkey;
            if ([profileHotKey loadRestorableStateFromArray:states]) {
                [profileHotKey createWindow];
                [profileHotKey.windowController.window orderOut:nil];  // Issue 4065
            }
        }
    }
}

- (void)createHiddenWindowFromLegacyRestorableState:(NSDictionary *)legacyState {
    for (__kindof iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey isKindOfClass:[iTermProfileHotKey class]]) {
            iTermProfileHotKey *profileHotKey = hotkey;
            legacyState = [legacyState dictionaryBySettingObject:profileHotKey.profile[KEY_GUID]
                                                          forKey:TERMINAL_ARRANGEMENT_PROFILE_GUID];
            [profileHotKey setLegacyState:legacyState];
            [profileHotKey createWindow];
            [profileHotKey.windowController.window orderOut:nil];  // Issue 4065
            break;
        }
    }
}

- (NSArray *)restorableStates {
    NSMutableArray *array = [NSMutableArray array];
    for (__kindof iTermBaseHotKey *hotkey in _hotKeys) {
        if ([hotkey isKindOfClass:[iTermProfileHotKey class]]) {
            iTermProfileHotKey *profileHotKey = (iTermProfileHotKey *)hotkey;
            if (!profileHotKey.allowsStateRestoration) {
                continue;
            }
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

- (void)nonHotKeyWindowDidBecomeKey {
    BOOL anyWindowRollingOut = [[self profileHotKeys] anyWithBlock:^BOOL(iTermProfileHotKey *anObject) {
        return [anObject rollingOut];
    }];
    BOOL anyWindowRollingIn = [[self profileHotKeys] anyWithBlock:^BOOL(iTermProfileHotKey *anObject) {
        return [anObject rollingIn];
    }];
    if (!anyWindowRollingOut && !anyWindowRollingIn) {
        // If there is previous state:
        // Going from hotkey window to non-hotkey window. Forget the previous state because
        // there's no need to ever return to it now. This happens when navigating explicitly from
        // a hotkey window to a non-hotkey terminal.
        DLog(@"A non-hotkey window became key. Removing previous state %p", self.previousState);
        self.previousState = nil;
    }

    // Clear the `wasAutoHidden` flag if the auto-hide was not due to the application resigning
    // active state. We can detect this because the only other way a window would auto-hide is if
    // another window becomes key.
    for (iTermProfileHotKey *profileHotKey in self.profileHotKeys) {
        profileHotKey.wasAutoHidden = NO;
    }
}

- (void)autoHideHotKeyWindowsExcept:(NSArray<NSWindowController *> *)exceptions {
    NSMutableArray *controllers = [[[self hotKeyWindowControllers] mutableCopy] autorelease];
    [controllers removeObjectsInArray:exceptions];
    [self autoHideHotKeyWindows:controllers];
}

- (void)autoHideHotKeyWindows:(NSArray<NSWindowController *> *)windowControllersToConsiderHiding {
    DLog(@"** Begin considering autohiding these windows:");
    DLog(@"%@", windowControllersToConsiderHiding);
    DLog(@"From:\n%@", [NSThread callStackSymbols]);

    if (![self shouldAutoHide]) {
        DLog(@"shouldAutoHide returned NO");
        return;
    }

    // If any window is rolling in, then we don't want this window to restore the previously active
    // app when it finishes rolling out.
    BOOL anyHotkeyWindowIsRollingIn = [self.profileHotKeys anyWithBlock:^BOOL(iTermProfileHotKey *anObject) {
        return anObject.rollingIn;
    }];

    DLog(@"shouldAutoHide returned YES");
    for (PseudoTerminal *hotKeyWindowController in windowControllersToConsiderHiding) {
        DLog(@"Consider auto-hiding %@", hotKeyWindowController);
        if (hotKeyWindowController.window.alphaValue == 0) {
            DLog(@"Alpha is 0 for %@ so not auto-hiding it", hotKeyWindowController);
            continue;
        }
        iTermProfileHotKey *profileHotKey =
            [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:hotKeyWindowController];
        if (!profileHotKey.autoHides) {
            DLog(@"Autohide disabled for %@ so not auto-hiding it", hotKeyWindowController);
            continue;
        }

        if (profileHotKey.rollingIn) {
            DLog(@"Currently rolling in %@ so not auto-hiding it", hotKeyWindowController);
            continue;
        }

        DLog(@"Auto-hiding %@", hotKeyWindowController);
        DLog(@"%@", [NSThread callStackSymbols]);
        BOOL suppressHide =
            [[[NSApp keyWindow] windowController] isKindOfClass:[PseudoTerminal class]];
        [profileHotKey hideHotKeyWindowAnimated:YES
                                suppressHideApp:suppressHide
                               otherIsRollingIn:anyHotkeyWindowIsRollingIn];
        profileHotKey.wasAutoHidden = YES;
    }
}

- (NSArray<iTermHotKeyDescriptor *> *)descriptorsForProfileHotKeysExcept:(Profile *)profile {
    return [self.profileHotKeys flatMapWithBlock:^id(iTermProfileHotKey *profileHotKey) {
        if (![profileHotKey.profile[KEY_GUID] isEqualToString:profile[KEY_GUID]]) {
            NSMutableArray *result = [NSMutableArray array];
            if ([iTermProfilePreferences stringForKey:KEY_HAS_HOTKEY inProfile:profileHotKey.profile]) {
                NSUInteger keyCode = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE
                                                                          inProfile:profileHotKey.profile];
                NSEventModifierFlags modifiers = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS
                                                                                      inProfile:profileHotKey.profile];
                [result addObject:[iTermHotKeyDescriptor descriptorWithKeyCode:keyCode
                                                                     modifiers:modifiers]];
            }

            if ([iTermProfilePreferences boolForKey:KEY_HOTKEY_ACTIVATE_WITH_MODIFIER inProfile:profileHotKey.profile]) {
                iTermHotKeyModifierActivation modifierActivation =
                    [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_ACTIVATION
                                                         inProfile:profileHotKey.profile];
                [result addObject:[iTermHotKeyDescriptor descriptorWithModifierActivation:modifierActivation]];
            }
            return result;
        } else {
            return nil;
        }
    }];
}

- (NSArray<PseudoTerminal *> *)siblingWindowControllersOf:(PseudoTerminal *)windowController {
    NSArray<iTermHotKeyDescriptor *> *referenceHotKeyDescriptors = [[self profileHotKeyForWindowController:windowController] hotKeyDescriptors];
    iTermHotKeyDescriptor *referenceModifierActivationDescriptor = [[self profileHotKeyForWindowController:windowController] modifierActivationDescriptor];
    return [self.profileHotKeys mapWithBlock:^id(iTermProfileHotKey *profileHotKey) {
        if ([profileHotKey.hotKeyDescriptors isEqual:referenceHotKeyDescriptors] ||
            [profileHotKey.modifierActivationDescriptor isEqual:referenceModifierActivationDescriptor]) {
            NSWindowController *windowController = profileHotKey.windowController.weaklyReferencedObject;
            if (windowController) {
                return windowController;
            } else {
                return profileHotKey.windowControllerBeingBorn;
            }
        } else {
            return nil;
        }
    }];
}

- (BOOL)dockIconClicked {
    __block BOOL handled = NO;
    if (self.visibleWindowControllers.count > 0) {
        [self.profileHotKeys enumerateObjectsUsingBlock:^(iTermProfileHotKey  *_Nonnull profileHotKey,
                                                          NSUInteger idx,
                                                          BOOL *_Nonnull stop) {
            if (profileHotKey.hotKeyWindowOpen) {
                [profileHotKey hideHotKeyWindowAnimated:YES suppressHideApp:NO otherIsRollingIn:NO];
                profileHotKey.wasAutoHidden = NO;
                handled = YES;
            }
        }];
    } else {
        NSUInteger numberOfTerminalWindowsOpen = [[[(iTermApplication *)NSApp orderedWindowsPlusVisibleHotkeyPanels] filteredArrayUsingBlock:^BOOL(NSWindow *window) {
            return [window.windowController isKindOfClass:[PseudoTerminal class]] && [window isVisible];
        }] count];
        [self.profileHotKeys enumerateObjectsUsingBlock:^(iTermProfileHotKey  *_Nonnull profileHotKey,
                                                          NSUInteger idx,
                                                          BOOL *_Nonnull stop) {
            switch ([iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_DOCK_CLICK_ACTION inProfile:profileHotKey.profile]) {
                case iTermHotKeyDockPreferenceDoNotShow:
                    break;
                case iTermHotKeyDockPreferenceAlwaysShow:
                    [profileHotKey showHotKeyWindow];
                    handled = YES;
                    break;
                case iTermHotKeyDockPreferenceShowIfNoOtherWindowsOpen:
                    if (numberOfTerminalWindowsOpen == 0) {
                        [profileHotKey showHotKeyWindow];
                        handled = YES;
                    }
                    break;
            }
        }];
    }
    return handled;
}

- (BOOL)addRevivedHotkeyWindowController:(PseudoTerminal *)windowController
                      forProfileWithGUID:(NSString *)guid {
    iTermProfileHotKey *profileHotKey = [self profileHotKeyForGUID:guid];
    if (!profileHotKey || profileHotKey.windowController.weaklyReferencedObject) {
        return NO;
    }
    profileHotKey.windowController = windowController.weakSelf;
    return YES;
}

- (iTermProfileHotKey *)didCreateWindowController:(PseudoTerminal *)windowController
                                      withProfile:(Profile *)profile
                                             show:(BOOL)show {
    iTermProfileHotKey *profileHotKey = [_hotKeys objectOfClass:[iTermProfileHotKey class]
                                                    passingTest:^BOOL(id element, NSUInteger index, BOOL *stop) {
                                                        return [[element profile][KEY_GUID] isEqualToString:profile[KEY_GUID]];
                                                    }];
    if (!profileHotKey) {
        return nil;
    }
    if (!profileHotKey.windowController.weaklyReferencedObject) {
        profileHotKey.windowController = windowController.weakSelf;
        iTermHotkeyWindowType hotkeyWindowType;
        if ([windowController.window isKindOfClass:[iTermPanel class]]) {
            hotkeyWindowType = iTermHotkeyWindowTypeFloatingPanel;
        } else if (windowController.window.level == NSNormalWindowLevel){
            hotkeyWindowType = iTermHotkeyWindowTypeFloatingWindow;
        } else {
            hotkeyWindowType = iTermHotkeyWindowTypeRegular;
        }
        windowController.hotkeyWindowType = hotkeyWindowType;
        if (show) {
            [profileHotKey showHotKeyWindow];
        }
        return profileHotKey;
    } else {
        return nil;
    }
}

- (void)fastHideAllHotKeyWindows {
    _disableAutoHide = YES;
    for (PseudoTerminal *term in [self hotKeyWindowControllers]) {
        iTermProfileHotKey *hotKey = [self profileHotKeyForWindowController:term];
        [hotKey hideHotKeyWindowAnimated:NO suppressHideApp:NO otherIsRollingIn:NO];
    }
    _disableAutoHide = NO;
}

- (NSArray<iTermPanel *> *)visibleFloatingHotkeyWindows {
    return [[self allFloatingHotkeyWindows] filteredArrayUsingBlock:^BOOL(iTermPanel *anObject) {
        return anObject.alphaValue == 1;
    }];
}

- (NSArray<iTermPanel *> *)allFloatingHotkeyWindows {
    // Note iTermPanel class is implied by appearing on all spaces and floating.
    return [[self profileHotKeys] mapWithBlock:^id(iTermProfileHotKey *anObject) {
        NSWindow *window = anObject.windowController.window;
        if ([window isKindOfClass:[iTermPanel class]]) {
            return window;
        } else {
            return nil;
        }
    }];
}

- (iTermProfileHotKey *)profileHotKeyForGUID:(NSString *)guid {
    NSArray<iTermProfileHotKey *> *profileHotKeys = [_hotKeys objectsOfClasses:@[ [iTermProfileHotKey class] ]];
    iTermProfileHotKey *profileHotKey = [profileHotKeys objectPassingTest:^BOOL(iTermProfileHotKey *element,
                                                                                NSUInteger index,
                                                                                BOOL *stop) {
        return [element.profile[KEY_GUID] isEqualToString:guid];
    }];
    return profileHotKey;
}

#pragma mark - Notifications

- (void)activeSpaceDidChange:(NSNotification *)notification {
    DLog(@"Active space did change");
    for (iTermProfileHotKey *profileHotKey in self.profileHotKeys) {
        PseudoTerminal *term = profileHotKey.windowController;
        NSWindow *window = [term window];
        if ([window isVisible] && window.isOnActiveSpace && [term fullScreen]) {
            // Issue 4136: If you press the hotkey while in a fullscreen app, the
            // dock stays up. Looks like the OS doesn't respect the window's
            // presentation option when switching from a fullscreen app, so we have
            // to toggle it after the switch is complete.
            [term showMenuBar];
            [term hideMenuBar];
        }
    }
}

#pragma mark - Private

- (BOOL)shouldAutoHide {
    if (_disableAutoHide) {
        DLog(@"Auto-hide temporarily disabled");
        return NO;
    }
    if ([[iTermApplication sharedApplication] localAuthenticationDialogOpen]) {
        DLog(@"Local auth dialog is open");
        return NO;
    }
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

    NSArray<iTermTerminalWindow *> *keyTerminalWindows = [[iTermController sharedInstance] keyTerminalWindows];
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

    return YES;
}

#pragma mark - Accessors

// NOTE: This does not return window controllers that are still being born.
- (NSArray<PseudoTerminal *> *)hotKeyWindowControllers {
    NSArray<iTermProfileHotKey *> *profileHotKeys = [self profileHotKeys];
    NSArray<PseudoTerminal *> *hotKeyWindowControllers = [profileHotKeys mapWithBlock:^id(iTermProfileHotKey *profileHotKey) {
        return profileHotKey.windowController.weaklyReferencedObject;
    }];
    return hotKeyWindowControllers;
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

- (void)storePreviouslyActiveApp:(iTermProfileHotKey *)profileHotKey {
    if (self.previousState && [NSApp isActive]) {
        DLog(@"Not updating previous state because we are active and already have previous state");
        return;
    }
    if (self.previousState.owner.rollingIn) {
        // Is the previous state for a hotkey window that's rolling in? If so, keep it, because it
        // will know about the previously active app.
        DLog(@"Not updating previous state because the existing previous state's owner is rolling in");
        return;
    }
    self.previousState = [[[iTermPreviousState alloc] init] autorelease];
    self.previousState.owner = profileHotKey;
    DLog(@"Stored previous state");
}

- (BOOL)otherHotKeyWindowWillBecomeKeyAfterOrderOut:(iTermProfileHotKey *)profileHotKey {
    PseudoTerminal *myWindowController = profileHotKey.windowController;

    for (NSWindow *window in [NSApp orderedWindows]) {
        if (!window.isVisible) {
            continue;
        }
        NSWindowController *windowController = [window windowController];
        if ([windowController isKindOfClass:[PseudoTerminal class]]) {
            PseudoTerminal *term = (PseudoTerminal *)windowController;
            if (term == myWindowController) {
                continue;
            }
            if (!term.isHotKeyWindow) {
                return NO;
            }
            iTermProfileHotKey *other = [self profileHotKeyForWindowController:term];
            if ([other rollingOut]) {
                continue;
            }
            return term.hasBeenKeySinceActivation;
        }
    }
    return NO;
}

- (BOOL)willFinishRollingOutProfileHotKey:(iTermProfileHotKey *)profileHotKey {
    // Restore the previous state (key window or active app) unless we switched
    // to another hotkey window.
    DLog(@"Finished rolling out %p. key window is %@.", profileHotKey.windowController, [[NSApp keyWindow] windowController]);
    if (![self otherHotKeyWindowWillBecomeKeyAfterOrderOut:profileHotKey]) {
        DLog(@"Restoring the previous state %p", self.previousState);
        BOOL result = [self.previousState restoreAllowingAppSwitch:!profileHotKey.closedByOtherHotkeyWindowOpening];
        if (!profileHotKey.closedByOtherHotkeyWindowOpening) {
            self.previousState = nil;
        }
        return result;
    }
    return NO;
}

- (void)hotKeyWillCreateWindow:(iTermBaseHotKey *)hotKey {
    if ([hotKey isKindOfClass:[iTermProfileHotKey class]]) {
        [_profileHotKeysBirthingWindows addObject:(iTermProfileHotKey *)hotKey];
    }
}

- (void)hotKeyDidCreateWindow:(iTermBaseHotKey *)hotKey {
    if ([hotKey isKindOfClass:[iTermProfileHotKey class]]) {
        [_profileHotKeysBirthingWindows removeLastObject];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    for (iTermProfileHotKey *profileHotKey in self.profileHotKeys) {
        if (profileHotKey.windowController.weaklyReferencedObject &&
            profileHotKey.wasAutoHidden &&
            [iTermProfilePreferences boolForKey:KEY_HOTKEY_REOPEN_ON_ACTIVATION inProfile:profileHotKey.profile]) {
            [profileHotKey showHotKeyWindow];
        }
    }
}

@end

