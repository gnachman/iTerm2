#import "HotkeyWindowController.h"

#import "DebugLogging.h"
#import "GTMCarbonEvent.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "SBSystemPreferences.h"
#import <Carbon/Carbon.h>
#import <ScriptingBridge/ScriptingBridge.h>

#define HKWLog DLog

@implementation HotkeyWindowController

+ (HotkeyWindowController *)sharedInstance {
    static HotkeyWindowController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

static PseudoTerminal* GetHotkeyWindow()
{
    iTermController* cont = [iTermController sharedInstance];
    NSArray* terminals = [cont terminals];
    for (PseudoTerminal* term in terminals) {
        if ([term isHotKeyWindow]) {
            return term;
        }
    }
    return nil;
}

- (PseudoTerminal*)hotKeyWindow
{
    return GetHotkeyWindow();
}

static void RollInHotkeyTerm(PseudoTerminal* term)
{
    HKWLog(@"Roll in [show] hotkey window");

    [NSApp activateIgnoringOtherApps:YES];
    [[term window] makeKeyAndOrderFront:nil];
    [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
    [[[term window] animator] setAlphaValue:1];
    [[HotkeyWindowController sharedInstance] performSelector:@selector(rollInFinished)
                                                  withObject:nil
                                                  afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)rollInFinished
{
    rollingIn_ = NO;
    PseudoTerminal* term = GetHotkeyWindow();
    [[term window] makeKeyAndOrderFront:nil];
    [[term window] makeFirstResponder:[[term currentSession] textview]];
}

static BOOL OpenHotkeyWindow()
{
    HKWLog(@"Open hotkey window");
    iTermController* cont = [iTermController sharedInstance];
    Profile* bookmark = [[PreferencePanel sharedInstance] hotkeyBookmark];
    if (bookmark) {
        if ([[bookmark objectForKey:KEY_WINDOW_TYPE] intValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
            // Lion fullscreen doesn't make sense with hotkey windows. Change
            // window type to traditional fullscreen.
            NSMutableDictionary* replacement = [NSMutableDictionary dictionaryWithDictionary:bookmark];
            [replacement setObject:[NSNumber numberWithInt:WINDOW_TYPE_FULL_SCREEN]
                            forKey:KEY_WINDOW_TYPE];
            bookmark = replacement;
        }
        PTYSession *session = [cont launchBookmark:bookmark
                                        inTerminal:nil
                                           withURL:nil
                                          isHotkey:YES
                                           makeKey:YES];
        PseudoTerminal* term = [[iTermController sharedInstance] terminalWithSession:session];
        [term setIsHotKeyWindow:YES];

        [[term window] setAlphaValue:0];
        if ([term windowType] != WINDOW_TYPE_FULL_SCREEN) {
            [[term window] setCollectionBehavior:[[term window] collectionBehavior] & ~NSWindowCollectionBehaviorFullScreenPrimary];
        }
        RollInHotkeyTerm(term);
        return YES;
    }
    return NO;
}

- (void)showNonHotKeyWindowsAndSetAlphaTo:(float)a
{
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        [[term window] setAlphaValue:a];
        if (term != hotkeyTerm) {
            [[term window] makeKeyAndOrderFront:nil];
        }
    }
    // Unhide all windows and bring the one that was at the top to the front.
    int i = [[iTermController sharedInstance] keyWindowIndexMemo];
    if (i >= 0 && i < [[[iTermController sharedInstance] terminals] count]) {
        [[[[[iTermController sharedInstance] terminals] objectAtIndex:i] window] makeKeyAndOrderFront:nil];
    }
}

- (BOOL)rollingInHotkeyTerm
{
    return rollingIn_;
}

static void RollOutHotkeyTerm(PseudoTerminal* term, BOOL itermWasActiveWhenHotkeyOpened)
{
    HKWLog(@"Roll out [hide] hotkey window");
    if (![[term window] isVisible]) {
        HKWLog(@"RollOutHotkeyTerm returning because term isn't visible.");
        return;
    }
    BOOL temp = [term isHotKeyWindow];
    [[NSAnimationContext currentContext] setDuration:[[PreferencePanel sharedInstance] hotkeyTermAnimationDuration]];
    [[[term window] animator] setAlphaValue:0];

    [[HotkeyWindowController sharedInstance] performSelector:@selector(restoreNormalcy:)
                                                  withObject:term
                                                  afterDelay:[[NSAnimationContext currentContext] duration]];
    [term setIsHotKeyWindow:temp];
}

- (void)doNotOrderOutWhenHidingHotkeyWindow
{
    itermWasActiveWhenHotkeyOpened_ = YES;
}

- (void)restoreNormalcy:(PseudoTerminal*)term
{
    if (!itermWasActiveWhenHotkeyOpened_) {
        [NSApp hide:nil];
        [self performSelector:@selector(unhide) withObject:nil afterDelay:0.1];
    } else {
        PseudoTerminal* currentTerm = [[iTermController sharedInstance] currentTerminal];
        if (currentTerm && ![currentTerm isHotKeyWindow] && [currentTerm fullScreen]) {
            [currentTerm hideMenuBar];
        } else {
            [currentTerm showMenuBar];
        }
    }

    if ([[PreferencePanel sharedInstance] closingHotkeySwitchesSpaces]) {
        [[term window] orderOut:self];
    } else {
        // Place behind all other windows at this level
        [[term window] orderWindow:NSWindowBelow relativeTo:0];
        // If you orderOut the hotkey term (term variable) then it switches to the
        // space in which your next window exists. So leave key status in the hotkey
        // window although it's invisible.
    }
}

- (void)unhide
{
    [NSApp unhideWithoutActivation];
    for (PseudoTerminal* t in [[iTermController sharedInstance] terminals]) {
        if (![t isHotKeyWindow]) {
            [[[t window] animator] setAlphaValue:1];
        }
    }
}

- (void)showHotKeyWindow
{
    [[iTermController sharedInstance] storePreviouslyActiveApp];
    itermWasActiveWhenHotkeyOpened_ = [NSApp isActive];
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    if (hotkeyTerm) {
        HKWLog(@"Showing existing hotkey window");
        int i = 0;
        [[iTermController sharedInstance] setKeyWindowIndexMemo:-1];
        for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
            if ([NSApp isActive]) {
                if (term != hotkeyTerm && [[term window] isKeyWindow]) {
                    [[iTermController sharedInstance] setKeyWindowIndexMemo:i];
                }
            }
            i++;
        }
        HKWLog(@"Activate iterm2");
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        rollingIn_ = YES;
        RollInHotkeyTerm(hotkeyTerm);
    } else {
        HKWLog(@"Open new hotkey window window");
        if (OpenHotkeyWindow()) {
            rollingIn_ = YES;
        }
    }
}

- (BOOL)isHotKeyWindowOpen
{
    PseudoTerminal* term = GetHotkeyWindow();
    return term && [[term window] isVisible];
}

- (void)fastHideHotKeyWindow
{
    HKWLog(@"fastHideHotKeyWindow");
    PseudoTerminal* term = GetHotkeyWindow();
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

- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm
{
    HKWLog(@"Hide hotkey window.");
    if ([[hotkeyTerm window] isVisible]) {
        HKWLog(@"key window is %@", [NSApp keyWindow]);
        NSWindow *theKeyWindow = [NSApp keyWindow];
        if (!theKeyWindow ||
            ([theKeyWindow isKindOfClass:[PTYWindow class]] &&
             [(PseudoTerminal*)[theKeyWindow windowController] isHotKeyWindow])) {
                [[iTermController sharedInstance] restorePreviouslyActiveApp];
            }
    }
    RollOutHotkeyTerm(hotkeyTerm, itermWasActiveWhenHotkeyOpened_);
}

void OnHotKeyEvent(void)
{
    HKWLog(@"hotkey pressed");
    PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
    if ([prefPanel hotkeyTogglesWindow]) {
        HKWLog(@"hotkey window enabled");
        PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
        if (hotkeyTerm) {
            HKWLog(@"already have a hotkey window created");
            if ([[hotkeyTerm window] alphaValue] == 1) {
                HKWLog(@"hotkey window opaque");
                [[HotkeyWindowController sharedInstance] hideHotKeyWindow:hotkeyTerm];
            } else {
                HKWLog(@"hotkey window not opaque");
                [[HotkeyWindowController sharedInstance] showHotKeyWindow];
            }
        } else {
            HKWLog(@"no hotkey window created yet");
            [[HotkeyWindowController sharedInstance] showHotKeyWindow];
        }
    } else if ([NSApp isActive]) {
        NSWindow* prefWindow = [prefPanel window];
        NSWindow* appKeyWindow = [[NSApplication sharedApplication] keyWindow];
        if (prefWindow != appKeyWindow ||
            ![[prefPanel hotkeyField] textFieldIsFirstResponder]) {
            [NSApp hide:nil];
        }
    } else {
        iTermController* controller = [iTermController sharedInstance];
        int n = [controller numberOfTerminals];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        if (n == 0) {
            [controller newWindow:nil];
        }
    }
}

- (BOOL)eventIsHotkey:(NSEvent*)e
{
    const int mask = (NSCommandKeyMask | NSAlternateKeyMask | NSShiftKeyMask | NSControlKeyMask);
    return (hotkeyCode_ &&
            ([e modifierFlags] & mask) == (hotkeyModifiers_ & mask) &&
            [e keyCode] == hotkeyCode_);
}

/*
 * The callback is passed a proxy for the tap, the event type, the incoming event,
 * and the refcon the callback was registered with.
 * The function should return the (possibly modified) passed in event,
 * a newly constructed event, or NULL if the event is to be deleted.
 *
 * The CGEventRef passed into the callback is retained by the calling code, and is
 * released after the callback returns and the data is passed back to the event
 * system.  If a different event is returned by the callback function, then that
 * event will be released by the calling code along with the original event, after
 * the event data has been passed back to the event system.
 */
static CGEventRef OnTappedEvent(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    iTermApplicationDelegate *ad = [[NSApplication sharedApplication] delegate];
    if (!ad.workspaceSessionActive) {
        return event;
    }
    HotkeyWindowController* cont = refcon;
    if (type == kCGEventTapDisabledByTimeout) {
        NSLog(@"kCGEventTapDisabledByTimeout");
        if (cont->machPortRef_) {
            NSLog(@"Re-enabling event tap");
            CGEventTapEnable(cont->machPortRef_, true);
        }
        return NULL;
    } else if (type == kCGEventTapDisabledByUserInput) {
        NSLog(@"kCGEventTapDisabledByUserInput");
        if (cont->machPortRef_) {
            NSLog(@"Re-enabling event tap");
            CGEventTapEnable(cont->machPortRef_, true);
        }
        return NULL;
    }

    NSEvent* cocoaEvent = [NSEvent eventWithCGEvent:event];
    BOOL callDirectly = NO;
    BOOL local = NO;
    if ([NSApp isActive]) {
        // Remap modifier keys only while iTerm2 is active; otherwise you could just use the
        // OS's remap feature.
        NSString* unmodkeystr = [cocoaEvent charactersIgnoringModifiers];
        unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
        unsigned int modflag = [cocoaEvent modifierFlags];
        NSString *keyBindingText;
        PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
        BOOL tempDisabled = [prefPanel remappingDisabledTemporarily];
        int action = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                modifiers:modflag
                                                     text:&keyBindingText
                                              keyMappings:nil];
        BOOL isDoNotRemap = (action == KEY_ACTION_DO_NOT_REMAP_MODIFIERS);
        local = action == KEY_ACTION_REMAP_LOCALLY;
        CGEventRef eventCopy = CGEventCreateCopy(event);
        if (local) {
            // The remapping should be applied and sent to [NSApp sendEvent:]
            // and not be returned from here. Apply the remapping to a copy
            // of the original event.
            CGEventRef temp = event;
            event = eventCopy;
            eventCopy = temp;
        }
        BOOL keySheetOpen = [[prefPanel keySheet] isKeyWindow] && [prefPanel keySheetIsOpen];
        if ((!tempDisabled && !isDoNotRemap) ||  // normal case, whether keysheet is open or not
            (!tempDisabled && isDoNotRemap && keySheetOpen)) {  // about to change dnr to non-dnr
            [iTermKeyBindingMgr remapModifiersInCGEvent:event
                                              prefPanel:prefPanel];
            cocoaEvent = [NSEvent eventWithCGEvent:event];
        }
        if (local) {
            // Now that the cocoaEvent has the remapped version, restore
            // the original event.
            CGEventRef temp = event;
            event = eventCopy;
            eventCopy = temp;
        }
        CFRelease(eventCopy);
        if (tempDisabled && !isDoNotRemap) {
            callDirectly = YES;
        }
    } else {
        // Update cocoaEvent with a remapped modifier (if it appropriate to do
        // so). This has an effect only if the remapped key is the hotkey.
        CGEventRef eventCopy = CGEventCreateCopy(event);
        NSString* unmodkeystr = [cocoaEvent charactersIgnoringModifiers];
        unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
        unsigned int modflag = [cocoaEvent modifierFlags];
        NSString *keyBindingText;
        int action = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                modifiers:modflag
                                                     text:&keyBindingText
                                              keyMappings:nil];
        BOOL isDoNotRemap = (action == KEY_ACTION_DO_NOT_REMAP_MODIFIERS) || (action == KEY_ACTION_REMAP_LOCALLY);
        if (!isDoNotRemap) {
            [iTermKeyBindingMgr remapModifiersInCGEvent:eventCopy
                                              prefPanel:[PreferencePanel sharedInstance]];
        }
        cocoaEvent = [NSEvent eventWithCGEvent:eventCopy];
        CFRelease(eventCopy);
    }
#ifdef USE_EVENT_TAP_FOR_HOTKEY
    if ([cont eventIsHotkey:cocoaEvent]) {
        OnHotKeyEvent();
        return NULL;
    }
#endif

    if (callDirectly) {
        // Send keystroke directly to preference panel when setting do-not-remap for a key; for
        // system keys, NSApp sendEvent: is never called so this is the last chance.
        [[PreferencePanel sharedInstance] shortcutKeyDown:cocoaEvent];
        return nil;
    }
    if (local) {
        // Send event directly to iTerm2 and do not allow other apps to see the
        // event at all.
        [NSApp sendEvent:cocoaEvent];
        return nil;
    } else {
        // Normal case.
        return event;
    }
}

- (NSEvent*)runEventTapHandler:(NSEvent*)event
{
    CGEventRef newEvent = OnTappedEvent(nil, kCGEventKeyDown, [event CGEvent], self);
    if (newEvent) {
        return [NSEvent eventWithCGEvent:newEvent];
    } else {
        return nil;
    }
}

- (void)unregisterHotkey
{
    hotkeyCode_ = 0;
    hotkeyModifiers_ = 0;
#ifndef USE_EVENT_TAP_FOR_HOTKEY
    [[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler] unregisterHotKey:carbonHotKey_];
    [carbonHotKey_ release];
    carbonHotKey_ = nil;
#endif
}

- (BOOL)haveEventTap
{
    return machPortRef_ != 0;
}

- (void)stopEventTap
{
    if ([self haveEventTap]) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                              eventSrc_,
                              kCFRunLoopCommonModes);
        CFMachPortInvalidate(machPortRef_); // switches off the event tap;
        CFRelease(machPortRef_);
        machPortRef_ = 0;
    }
}

- (BOOL)startEventTap
{
#ifdef FAKE_EVENT_TAP
    return YES;
#endif

    if (![self haveEventTap]) {
        DebugLog(@"Register event tap.");
        machPortRef_ = CGEventTapCreate(kCGHIDEventTap,
                                        kCGTailAppendEventTap,
                                        kCGEventTapOptionDefault,
                                        CGEventMaskBit(kCGEventKeyDown),
                                        (CGEventTapCallBack)OnTappedEvent,
                                        self);
        if (machPortRef_) {
            eventSrc_ = CFMachPortCreateRunLoopSource(NULL, machPortRef_, 0);
            if (eventSrc_ == NULL) {
                DebugLog(@"CFMachPortCreateRunLoopSource failed.");
                NSLog(@"CFMachPortCreateRunLoopSource failed.");
                CFRelease(machPortRef_);
                machPortRef_ = 0;
                return NO;
            } else {
                DebugLog(@"Adding run loop source.");
                // Get the CFRunLoop primitive for the Carbon Main Event Loop, and add the new event souce
                CFRunLoopAddSource(CFRunLoopGetCurrent(),
                                   eventSrc_,
                                   kCFRunLoopCommonModes);
                CFRelease(eventSrc_);
            }
            return YES;
        } else {
            return NO;
        }
    } else {
        return YES;
    }
}

- (NSString *)accessibilityMessageForHotkey {
    return @"You have assigned a \"hotkey\" that opens iTerm2 at any time. "
    @"To use it, you must turn on \"access for assistive devices\" in the Universal "
    @"Access preferences panel in System Preferences and restart iTerm2.";
}

- (NSString *)accessibilityMessageForModifier {
    return @"You have chosen to remap certain modifier keys. For this to work for all key "
    @"combinations (such as cmd-tab), you must turn on \"access for assistive devices\" "
    @"in the Universal Access preferences panel in System Preferences and restart iTerm2.";
}

- (void)openMavericksAccessibilityPane
{
    [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/Security.prefPane"];
    SBSystemPreferencesApplication *systemPrefs =
        [SBApplication applicationWithBundleIdentifier:@"com.apple.systempreferences"];

    [systemPrefs activate];

    SBElementArray *panes = [systemPrefs panes];
    SBSystemPreferencesPane *speechPane = nil;

    for (SBSystemPreferencesPane *pane in panes) {
        if ([[pane id] isEqualToString:@"com.apple.preference.security"]) {
            speechPane = pane;
            break;
        }
    }
    [systemPrefs setCurrentPane:speechPane];

    SBElementArray *anchors = [speechPane anchors];

    for (SBSystemPreferencesAnchor *anchor in anchors) {
        if ([anchor.name isEqualToString:@"Privacy"]) {
            [anchor reveal];
        }
    }

    for (SBSystemPreferencesAnchor *anchor in anchors) {
        if ([anchor.name isEqualToString:@"Privacy_Accessibility"]) {
            [anchor reveal];
        }
    }
}

- (void)navigatePrefPane
{
    // NOTE: Pre-Mavericks only.
    [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/UniversalAccessPref.prefPane"];
}

- (NSString *)accessibilityActionMessage {
    return @"Open System Preferences";
}

- (BOOL)registerHotkey:(int)keyCode modifiers:(int)modifiers
{
    if (carbonHotKey_) {
        [self unregisterHotkey];
    }
    hotkeyCode_ = keyCode;
    hotkeyModifiers_ = modifiers & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSShiftKeyMask);
#ifdef USE_EVENT_TAP_FOR_HOTKEY
    if (![self startEventTap]) {
        if (IsMavericksOrLater()) {
            [self requestAccessibilityPermissionMavericks];
            return;
        }
        switch (NSRunAlertPanel(@"Could not enable hotkey",
                                [self accessibilityMessageForHotkey],
                                @"OK",
                                [self accessibilityActionMessage],
                                @"Disable Hotkey",
                                nil)) {
            case NSAlertOtherReturn:
                [[PreferencePanel sharedInstance] disableHotkey];
                break;

            case NSAlertAlternateReturn:
                [self navigatePrefPane]
                return NO;
        }
    }
    return YES;
#else
    carbonHotKey_ = [[[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler]
                      registerHotKey:keyCode
                      modifiers:hotkeyModifiers_
                      target:self
                      action:@selector(carbonHotkeyPressed)
                      userInfo:nil
                      whenPressed:YES] retain];
    return YES;
#endif
}

- (void)carbonHotkeyPressed
{
    iTermApplicationDelegate *ad = [[NSApplication sharedApplication] delegate];
    if (!ad.workspaceSessionActive) {
        return;
    }
    OnHotKeyEvent();
}

- (void)requestAccessibilityPermissionMavericks {
    static BOOL alreadyAsked;
    if (alreadyAsked) {
        return;
    }
    alreadyAsked = YES;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1090
    NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                        forKey:(NSString *)kAXTrustedCheckOptionPrompt];
    // Show a dialog prompting the user to open system prefs.
    if (!AXIsProcessTrustedWithOptions((CFDictionaryRef)options)) {
        return;
    }
#endif
}

- (void)beginRemappingModifiers
{
    if (![self startEventTap]) {
        if (IsMavericksOrLater()) {
            [self requestAccessibilityPermissionMavericks];
            return;
        }
        switch (NSRunAlertPanel(@"Could not remap modifiers",
                                [self accessibilityMessageForModifier],
                                @"OK",
                                [self accessibilityActionMessage],
                                nil,
                                nil)) {
            case NSAlertAlternateReturn:
                [self navigatePrefPane];
                break;
        }
    }
}


@end
