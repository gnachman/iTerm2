#import "HotkeyWindowController.h"

#import "DebugLogging.h"
#import "GTMCarbonEvent.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
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

@interface HotkeyWindowController()
// For restoring previously active app when exiting hotkey window.
@property(nonatomic, copy) NSNumber *previouslyActiveAppPID;
@end

@implementation HotkeyWindowController {
    // Records the index of the front terminal in -[iTermController terminals]
    // at the time the hotkey window was opened. -1 if invalid. Used to bring
    // the proper window front when hiding "quickly" (when entering Expose
    // while a hotkey window is open). TODO: I'm not sure why this is necessary.
    NSInteger _savedIndexOfFrontTerminal;
}

+ (HotkeyWindowController *)sharedInstance {
    static HotkeyWindowController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

+ (void)closeWindowReturningToHotkeyWindowIfPossible:(NSWindow *)window {
    PseudoTerminal *hotkeyTerm = GetHotkeyWindow();
    if (hotkeyTerm && [[hotkeyTerm window] alphaValue]) {
        [[hotkeyTerm window] makeKeyWindow];
    }
    [window close];
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
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[HotkeyWindowController sharedInstance] rollInFinished];
    }];
    [[[term window] animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
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

- (void)bringHotkeyWindowToFore:(NSWindow *)window {
    DLog(@"Bring hotkey window %@ to front", window);
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
}

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

- (void)rollInFinished
{
    rollingIn_ = NO;
    PseudoTerminal* term = GetHotkeyWindow();
    [[term window] makeKeyAndOrderFront:nil];
    [[term window] makeFirstResponder:[[term currentSession] textview]];
    [[[[HotkeyWindowController sharedInstance] hotKeyWindow] currentTab] recheckBlur];
}

- (Profile *)profile {
    NSString *guid = [iTermPreferences stringForKey:kPreferenceKeyHotkeyProfileGuid];
    if (guid) {
        return [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    } else {
        return nil;
    }
}

- (BOOL)openHotkeyWindowAndRollIn:(BOOL)rollIn {
    HKWLog(@"Open hotkey window");
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
    PseudoTerminal *term = nil;
    if (arrangement) {
        term = [PseudoTerminal terminalWithArrangement:arrangement];
        if (term) {
            [[iTermController sharedInstance] addTerminalWindow:term];
        }
    }
    
    iTermController* cont = [iTermController sharedInstance];
    Profile* bookmark = [self profile];
    if (!term && bookmark) {
        if ([[bookmark objectForKey:KEY_WINDOW_TYPE] intValue] == WINDOW_TYPE_LION_FULL_SCREEN) {
            // Lion fullscreen doesn't make sense with hotkey windows. Change
            // window type to traditional fullscreen.
            NSMutableDictionary* replacement = [NSMutableDictionary dictionaryWithDictionary:bookmark];
            [replacement setObject:[NSNumber numberWithInt:WINDOW_TYPE_TRADITIONAL_FULL_SCREEN]
                            forKey:KEY_WINDOW_TYPE];
            bookmark = replacement;
        }
        PTYSession *session = [cont launchBookmark:bookmark
                                        inTerminal:nil
                                           withURL:nil
                                          isHotkey:YES
                                           makeKey:YES
                                       canActivate:YES
                                           command:nil
                                             block:nil];
        if (session) {
            term = [[iTermController sharedInstance] terminalWithSession:session];
        }
    }
    if (term) {
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
        if (rollIn) {
            RollInHotkeyTerm(term);
        } else {
            // Order out for issue 4065.
            [[term window] orderOut:nil];
        }
        return YES;
    }
    return NO;
}

- (void)showNonHotKeyWindowsAndSetAlphaTo:(float)a {
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        [[term window] setAlphaValue:a];
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
    [[NSAnimationContext currentContext] setDuration:[iTermAdvancedSettingsModel hotkeyTermAnimationDuration]];
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

    // NOTE: There used be an option called "closing hotkey switches spaces". I've removed the
    // "off" behavior and made the "on" behavior the only option. Various things didn't work
    // right, and the worst one was in this thread: "[iterm2-discuss] Possible bug when using Hotkey window?"
    // where clicks would be swallowed up by the invisible hotkey window. The "off" mode would do
    // this:
    // [[term window] orderWindow:NSWindowBelow relativeTo:0];
    // And the window was invisible only because its alphaValue was set to 0 elsewhere.
    [[term window] orderOut:self];
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

- (void)storePreviouslyActiveApp {
    NSDictionary *activeAppDict = [[NSWorkspace sharedWorkspace] activeApplication];
    HKWLog(@"Active app is %@", activeAppDict);
    if (![[activeAppDict objectForKey:@"NSApplicationBundleIdentifier"] isEqualToString:@"com.googlecode.iterm2"]) {
        self.previouslyActiveAppPID = activeAppDict[@"NSApplicationProcessIdentifier"];
    } else {
        self.previouslyActiveAppPID = nil;
    }
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

- (void)showHotKeyWindow {
    [self storePreviouslyActiveApp];
    itermWasActiveWhenHotkeyOpened_ = [NSApp isActive];
    PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
    if (hotkeyTerm) {
        HKWLog(@"Showing existing hotkey window");
        NSInteger i = 0;
        _savedIndexOfFrontTerminal = -1;
        for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
            if ([NSApp isActive]) {
                if (term != hotkeyTerm && [[term window] isKeyWindow]) {
                    _savedIndexOfFrontTerminal = i;
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
        if ([self openHotkeyWindowAndRollIn:YES]) {
            rollingIn_ = YES;
        }
    }
}

- (void)createHiddenHotkeyWindow {
    if (GetHotkeyWindow()) {
        return;
    }
    [self openHotkeyWindowAndRollIn:NO];
}

- (BOOL)isHotKeyWindowOpen
{
    PseudoTerminal* term = GetHotkeyWindow();
    return term && [[term window] isVisible];
}

- (void)fastHideHotKeyWindow {
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

- (void)hideHotKeyWindow:(PseudoTerminal*)hotkeyTerm {
    // This used to iterate over hotkeyTerm.window.sheets, which seemed to
    // work, but sheets wasn't defined prior to 10.9. Consider going back to
    // that technique if this doesn't work well.
    while (hotkeyTerm.window.attachedSheet) {
        [NSApp endSheet:hotkeyTerm.window.attachedSheet];
    }
    HKWLog(@"Hide hotkey window.");
    if ([[hotkeyTerm window] isVisible]) {
        HKWLog(@"key window is %@", [NSApp keyWindow]);
        NSWindow *theKeyWindow = [NSApp keyWindow];
        if (!theKeyWindow ||
            ([theKeyWindow isKindOfClass:[PTYWindow class]] &&
             [(PseudoTerminal*)[theKeyWindow windowController] isHotKeyWindow])) {
                [self restorePreviouslyActiveApp];
            }
    }
    RollOutHotkeyTerm(hotkeyTerm, itermWasActiveWhenHotkeyOpened_);
}

void OnHotKeyEvent(void)
{
    HKWLog(@"hotkey pressed");
    PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
    if ([iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow]) {
        HKWLog(@"hotkey window enabled");
        PseudoTerminal* hotkeyTerm = GetHotkeyWindow();
        if (hotkeyTerm) {
            HKWLog(@"already have a hotkey window created");
            if ([[hotkeyTerm window] alphaValue] == 1) {
                HKWLog(@"hotkey window opaque");
                const BOOL activateStickyHotkeyWindow = (![iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides] &&
                                                         ![[hotkeyTerm window] isKeyWindow]);
                if (activateStickyHotkeyWindow && ![NSApp isActive]) {
                    HKWLog(@"Storing previously active app");
                    [[HotkeyWindowController sharedInstance] storePreviouslyActiveApp];
                }
                const BOOL hotkeyWindowOnOtherSpace = ![[hotkeyTerm window] isOnActiveSpace];
                if (hotkeyWindowOnOtherSpace || activateStickyHotkeyWindow) {
                    DLog(@"Hotkey window is active on another space, or else it doesn't autohide but isn't key. Switch to it.");
                    [NSApp activateIgnoringOtherApps:YES];
                    [[hotkeyTerm window] makeKeyAndOrderFront:nil];
                } else {
                    DLog(@"Hide hotkey window");
                    [[HotkeyWindowController sharedInstance] hideHotKeyWindow:hotkeyTerm];
                }
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

// Indicates if the user at the keyboard is the same user that owns this process. Used to avoid
// remapping keys when the user has switched users with fast user switching.
static BOOL UserIsActive() {
    CFDictionaryRef sessionInfoDict;

    sessionInfoDict = CGSessionCopyCurrentDictionary();
    if (sessionInfoDict) {
        NSNumber *userIsActiveNumber = CFDictionaryGetValue(sessionInfoDict,
                                                            kCGSessionOnConsoleKey);
        if (!userIsActiveNumber) {
            CFRelease(sessionInfoDict);
            return YES;
        } else {
            BOOL value = [userIsActiveNumber boolValue];
            CFRelease(sessionInfoDict);
            return value;
        }
    }
    return YES;
}

static BOOL ShouldRemap(BOOL disableRemapping, BOOL isDoNotRemap) {
    if (disableRemapping) {
        return NO;
    } else {
        // Remap unless bound action is DNR
        return !isDoNotRemap;
    }
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
    iTermApplicationDelegate *ad = iTermApplication.sharedApplication.delegate;
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

    if (!UserIsActive()) {
        // Fast user switching has switched to another user, don't do any remapping.
        DLog(@"** not doing any remapping for event %@", [NSEvent eventWithCGEvent:event]);
        return event;
    }

    NSEvent* cocoaEvent = [NSEvent eventWithCGEvent:event];
    BOOL callDirectly = NO;
    BOOL local = NO;
    iTermShortcutInputView *shortcutView = nil;
    if ([NSApp isActive]) {
        shortcutView = [iTermShortcutInputView firstResponder];

        // Remap modifier keys only while iTerm2 is active; otherwise you could just use the
        // OS's remap feature.
        NSString* unmodkeystr = [cocoaEvent charactersIgnoringModifiers];
        unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
        unsigned int modflag = [cocoaEvent modifierFlags];
        NSString *keyBindingText;
        BOOL disableRemapping = shortcutView.disableKeyRemapping;

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
        if (ShouldRemap(disableRemapping, isDoNotRemap)) {
            [iTermKeyBindingMgr remapModifiersInCGEvent:event];
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
        if (disableRemapping) {
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
            [iTermKeyBindingMgr remapModifiersInCGEvent:eventCopy];
        }
        cocoaEvent = [NSEvent eventWithCGEvent:eventCopy];
        CFRelease(eventCopy);
    }

    if (callDirectly) {
        // Send keystroke directly to preference panel when setting do-not-remap for a key; for
        // system keys, NSApp sendEvent: is never called so this is the last chance.
        [shortcutView handleShortcutEvent:cocoaEvent];
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
    [[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler] unregisterHotKey:carbonHotKey_];
    [carbonHotKey_ release];
    carbonHotKey_ = nil;
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

    carbonHotKey_ = [[[GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler]
                      registerHotKey:keyCode
                      modifiers:hotkeyModifiers_
                      target:self
                      action:@selector(carbonHotkeyPressed:)
                      userInfo:nil
                      whenPressed:YES] retain];
    return YES;
}

- (void)carbonHotkeyPressed:(id)handler {
    iTermApplicationDelegate *ad = iTermApplication.sharedApplication.delegate;
    if (!ad.workspaceSessionActive) {
        return;
    }
    OnHotKeyEvent();
}

- (void)requestAccessibilityPermissionMavericks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *options = @{ (NSString *)kAXTrustedCheckOptionPrompt: @YES };
        // Show a dialog prompting the user to open system prefs.
        if (!AXIsProcessTrustedWithOptions((CFDictionaryRef)options)) {
            return;
        }
    });
}

- (void)beginRemappingModifiers
{
    if (![self startEventTap]) {
        if (IsMavericksOrLater()) {
            [self requestAccessibilityPermissionMavericks];
            return;
        }
        switch (NSRunAlertPanel(@"Could not remap modifiers",
                                @"%@",
                                @"OK",
                                [self accessibilityActionMessage],
                                nil,
                                [self accessibilityMessageForModifier])) {
            case NSAlertAlternateReturn:
                [self navigatePrefPane];
                break;
        }
    }
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

- (int)controlRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyControlRemapping];
}

- (int)leftOptionRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyLeftOptionRemapping];
}

- (int)rightOptionRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyRightOptionRemapping];
}

- (int)leftCommandRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyLeftCommandRemapping];
}

- (int)rightCommandRemapping {
    return [iTermPreferences intForKey:kPreferenceKeyRightCommandRemapping];
}

- (BOOL)isAnyModifierRemapped
{
    return ([self controlRemapping] != kPreferencesModifierTagControl ||
            [self leftOptionRemapping] != kPreferencesModifierTagLeftOption ||
            [self rightOptionRemapping] != kPreferencesModifierTagRightOption ||
            [self leftCommandRemapping] != kPreferencesModifierTagLeftCommand ||
            [self rightCommandRemapping] != kPreferencesModifierTagRightCommand);
}

@end
