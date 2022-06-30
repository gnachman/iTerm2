/*
 **  iTermApplication.m
 **
 **  Copyright (c) 2002-2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: overrides sendEvent: so that key mappings with command mask
 **               are handled properly.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermApplication.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermEventTap.h"
#import "iTermFlagsChangedNotification.h"
#import "iTermHotKeyController.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermModifierRemapper.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferences.h"
#import "iTermScriptingWindow.h"
#import "iTermShortcutInputView.h"
#import "iTermWindowHacks.h"
#import "NSArray+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSResponder+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWindow+iTerm.h"
#import "NSResponder+iTerm.h""
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"

unsigned short iTermBogusVirtualKeyCode = 0xffff;
NSString *const iTermApplicationCharacterPaletteWillOpen = @"iTermApplicationCharacterPaletteWillOpen";
NSString *const iTermApplicationCharacterPaletteDidClose = @"iTermApplicationCharacterPaletteDidClose";

NSString *const iTermApplicationInputMethodEditorDidOpen = @"iTermApplicationInputMethodEditorDidOpen";
NSString *const iTermApplicationInputMethodEditorDidClose = @"iTermApplicationInputMethodEditorDidClose";

NSString *const iTermApplicationWillShowModalWindow = @"iTermApplicationWillShowModalWindow";
NSString *const iTermApplicationDidCloseModalWindow = @"iTermApplicationDidCloseModalWindow";

@interface iTermApplication()
@property(nonatomic, strong) NSStatusItem *statusBarItem;
@end

static const char *iTermApplicationKVOKey = "iTermApplicationKVOKey";

@interface iTermApplication()
@property(nonatomic, strong, readwrite) NSWindow *it_windowBecomingKey;
@end

@implementation iTermApplication {
    BOOL _it_characterPanelIsOpen;
    BOOL _it_characterPanelShouldOpenSoon;
    // Are we within one spin of didBecomeActive?
    BOOL _it_justBecameActive;
    // Have we received didBecomeActive without a subsequent didResignActive?
    BOOL _it_active;
    BOOL _it_restorableStateInvalid;
    BOOL _leader;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"modalWindow"];
}

+ (iTermApplication *)sharedApplication {
    __kindof NSApplication *sharedApplication = [super sharedApplication];
    assert([sharedApplication isKindOfClass:[iTermApplication class]]);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [sharedApplication addObserver:sharedApplication
                            forKeyPath:@"modalWindow"
                               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                               context:(void *)iTermApplicationKVOKey];
        [[NSNotificationCenter defaultCenter] addObserver:sharedApplication
                                                 selector:@selector(it_windowDidOrderOnScreen:)
                                                     name:@"NSWindowDidOrderOnScreenAndFinishAnimatingNotification"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:sharedApplication
                                                 selector:@selector(it_windowDidOrderOffScreen:)
                                                     name:@"NSWindowDidOrderOffScreenAndFinishAnimatingNotification"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:sharedApplication
                                                 selector:@selector(it_applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:sharedApplication
                                                 selector:@selector(it_applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];

    });
    return sharedApplication;
}

// Giant pile of private API hacks for issue 7521.
- (void)it_windowDidOrderOnScreen:(NSNotification *)notification {
    DLog(@"windowDidOrderOnScreen");
    NSObject *object = notification.object;
    if ([NSStringFromClass(object.class) isEqualToString:@"NSPanelViewBridge"]) {
        _it_imeOpen = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationInputMethodEditorDidOpen object:nil];
    }
}

- (void)it_windowDidOrderOffScreen:(NSNotification *)notification {
    DLog(@"windowDidOrderOffScreen");
    NSObject *object = notification.object;
    if ([NSStringFromClass(object.class) isEqualToString:@"NSPanelViewBridge"]) {
        _it_imeOpen = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationInputMethodEditorDidClose object:nil];
    }
}

- (void)it_applicationDidResignActive:(NSNotification *)notification {
    DLog(@"Resign active");
    if (_leader) {
        [self toggleLeader];
    }
    _it_active = NO;
}

- (void)it_applicationDidBecomeActive:(NSNotification *)notification {
    _it_active = YES;
    _it_justBecameActive = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf it_resetJustBecameActive];
    });
}

- (BOOL)it_justBecameActive {
    return _it_justBecameActive || (self.isActive && !_it_active);
}

- (void)it_resetJustBecameActive {
    _it_justBecameActive = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != iTermApplicationKVOKey) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if ([keyPath isEqualToString:@"modalWindow"]) {
        NSDictionary *dict = [change dictionaryByRemovingNullValues];
        [self it_modalWindowDidChangeFrom:dict[NSKeyValueChangeOldKey] to:dict[NSKeyValueChangeNewKey]];
        return;
    }
}

- (void)it_modalWindowDidChangeFrom:(NSWindow *)oldValue to:(NSWindow *)newValue {
    DLog(@"modal window did change from %@ to %@", oldValue, newValue);
    if (oldValue == nil && newValue != nil) {
        _it_modalWindowOpen = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationWillShowModalWindow object:nil];
        return;
    }
    if (oldValue != nil && newValue == nil) {
        _it_modalWindowOpen = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationDidCloseModalWindow object:nil];
    }
}

- (BOOL)_eventUsesNavigationKeys:(NSEvent*)event {
    NSString* unmodkeystr = [event charactersIgnoringModifiers];
    if ([unmodkeystr length] == 0) {
        return NO;
    }
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    switch (unmodunicode) {
        case NSUpArrowFunctionKey:
        case NSDownArrowFunctionKey:
        case NSLeftArrowFunctionKey:
        case NSRightArrowFunctionKey:
        case NSInsertFunctionKey:
        case NSDeleteFunctionKey:
        case NSDeleteCharFunctionKey:
        case NSHomeFunctionKey:
        case NSEndFunctionKey:
            return YES;
        default:
            return NO;
    }
}

- (NSEvent *)eventByRemappingForSecureInput:(NSEvent *)event {
    if ([[iTermModifierRemapper sharedInstance] isAnyModifierRemapped] &&
        (IsSecureEventInputEnabled() || ![[iTermModifierRemapper sharedInstance] isRemappingModifiers])) {
        // The event tap is not working, but we can still remap modifiers for non-system
        // keys. Only things like cmd-tab will not be remapped in this case. Otherwise,
        // the event tap performs the remapping.
        CGEventRef maybeRemappedCGEvent = [[iTermModifierRemapper sharedInstance] eventByRemappingEvent:[event CGEvent]
                                                                                               eventTap:nil];
        if (!maybeRemappedCGEvent) {
            return nil;
        }
        event = [NSEvent eventWithCGEvent:maybeRemappedCGEvent];
        DLog(@"Remapped modifiers to %@", event);
    }
    return event;
}

- (NSWindow *)it_keyWindow {
    NSWindow *window = self.keyWindow;
    while (window.sheets.count) {
        window = window.sheets.lastObject;
    }
    return window;
}

- (iTermShortcutInputView *)focusedShortcutInputView {
    NSResponder *firstResponder = [[NSApp it_keyWindow] firstResponder];
    if ([firstResponder isKindOfClass:[iTermShortcutInputView class]]) {
        return (iTermShortcutInputView *)firstResponder;
    }
    return nil;
}

- (BOOL)routeEventToShortcutInputView:(NSEvent *)event {
    iTermShortcutInputView *shortcutView = [self focusedShortcutInputView];
    if (!shortcutView) {
        DLog(@"No shortcut input view");
        return NO;
    }
    if (event.keyCode == iTermBogusVirtualKeyCode) {
        // You can't register a carbon hotkey for these so just ignore them when listening for a shortcut.
        DLog(@"Bogus keycode");
        return YES;
    }
    DLog(@"Routing event to shortcut input view");
    [shortcutView handleShortcutEvent:event];
    return YES;
}

- (int)digitKeyForEvent:(NSEvent *)event {
    if ([iTermPreferences boolForKey:kPreferenceKeyEmulateUSKeyboard]) {
        switch (event.keyCode) {
            case kVK_ANSI_1:
            case kVK_ANSI_Keypad1:
                return 1;
            case kVK_ANSI_2:
            case kVK_ANSI_Keypad2:
                return 2;
            case kVK_ANSI_3:
            case kVK_ANSI_Keypad3:
                return 3;
            case kVK_ANSI_4:
            case kVK_ANSI_Keypad4:
                return 4;
            case kVK_ANSI_5:
            case kVK_ANSI_Keypad5:
                return 5;
            case kVK_ANSI_6:
            case kVK_ANSI_Keypad6:
                return 6;
            case kVK_ANSI_7:
            case kVK_ANSI_Keypad7:
                return 7;
            case kVK_ANSI_8:
            case kVK_ANSI_Keypad8:
                return 8;
            case kVK_ANSI_9:
            case kVK_ANSI_Keypad9:
                return 9;
        }
        return -1;
    } else {
        int digit = [[event charactersIgnoringModifiers] intValue];
        if (!digit) {
            digit = [[event characters] intValue];
        }
        return digit;
    }
}

- (BOOL)switchToWindowByNumber:(NSEvent *)event {
    const NSUInteger allModifiers =
        (NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption);
    const NSUInteger maskedValue = ([event it_modifierFlags] & allModifiers);
    const NSUInteger requirement = [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchWindowModifier]];
    if (maskedValue == requirement) {
        // Command-Alt (or selected modifier) + number: Switch to window by number.
        int digit = [self digitKeyForEvent:event];
        if (digit >= 1 && digit <= 9) {
            PseudoTerminal* termWithNumber = [[iTermController sharedInstance] terminalWithNumber:(digit - 1)];
            DLog(@"Switching windows");
            if (termWithNumber) {
                if ([termWithNumber isHotKeyWindow] && [[termWithNumber window] alphaValue] < 1) {
                    iTermProfileHotKey *hotKey =
                        [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:termWithNumber];
                    [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:hotKey url:nil];
                } else {
                    [[termWithNumber window] makeKeyAndOrderFront:self];
                }
            }
            return YES;
        }
    }
    return NO;
}

- (BOOL)switchToPaneInWindowController:(PseudoTerminal *)currentTerminal byNumber:(NSEvent *)event {
    const int mask = NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
    if (([event it_modifierFlags] & mask) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchPaneModifier]]) {
        int digit = [self digitKeyForEvent:event];
        NSArray *orderedSessions = currentTerminal.currentTab.orderedSessions;
        int numSessions = [orderedSessions count];
        if (digit == 9 && numSessions > 0) {
            // Modifier+9: Switch to last split pane if there are fewer than 9.
            DLog(@"Switching to last split pane");
            [currentTerminal.currentTab setActiveSession:[orderedSessions lastObject]];
            return YES;
        }
        if (digit >= 1 && digit <= numSessions) {
            // Modifier+number: Switch to split pane by number.
            DLog(@"Switching to split pane");
            [currentTerminal.currentTab setActiveSession:orderedSessions[digit - 1]];
            return YES;
        }
        if (digit >= 1 && digit <= 9) {
            // Ignore Modifier+Number if there's no matching split pane. Issue 6624.
            return YES;
        }
    }
    return NO;
}

- (BOOL)switchToTabInTabView:(PTYTabView *)tabView byNumber:(NSEvent *)event {
    const int mask = NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
    if (([event it_modifierFlags] & mask) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]]) {
        int digit = [self digitKeyForEvent:event];
        if (digit == 9 && [tabView numberOfTabViewItems] > 0) {
            // Command (or selected modifier)+9: Switch to last tab if there are fewer than 9.
            DLog(@"Switching to last tab");
            [tabView selectTabViewItemAtIndex:[tabView numberOfTabViewItems]-1];
            return YES;
        }
        if (digit >= 1 && digit <= [tabView numberOfTabViewItems]) {
            // Command (or selected modifier)+number: Switch to tab by number.
            DLog(@"Switching tabs");
            [tabView selectTabViewItemAtIndex:digit-1];
            return YES;
        }
        if (digit >= 1 && digit <= 9) {
            // Ignore Modifier+Number if there's no matching tab. Issue 6624.
            return YES;
        }
    }
    return NO;
}

- (BOOL)remapEvent:(NSEvent *)event inResponder:(NSResponder *)responder currentSession:(PTYSession *)currentSession {
    BOOL okToRemap = YES;
    if ([responder isKindOfClass:[NSTextView class]]) {
        // Disable keymaps that send text
        if ([currentSession hasTextSendingKeyMappingForEvent:event]) {
            okToRemap = NO;
        }
        if ([self _eventUsesNavigationKeys:event]) {
            okToRemap = NO;
        }
    }

    if (okToRemap && [currentSession hasActionableKeyMappingForEvent:event]) {
        if ([currentSession sessionModeConsumesEvent:event]) {
            return NO;
        }
        // Remap key.
        DLog(@"Remapping to actionable event");
        [currentSession keyDown:event];
        return YES;
    }
    return NO;
}

- (BOOL)handleLeader:(NSEvent *)event {
    if (event.modifierFlags & iTermLeaderModifierFlag) {
        DLog(@"Leader flag unset");
        return NO;
    }
    if (_leader) {
        DLog(@"Re-send event with leader modifier flag set");
        NSEvent *modified = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:event.locationInWindow
                                        modifierFlags:event.modifierFlags | iTermLeaderModifierFlag
                                            timestamp:event.timestamp
                                         windowNumber:event.windowNumber
                                              context:nil
                                           characters:event.characters
                          charactersIgnoringModifiers:event.charactersIgnoringModifiers
                                            isARepeat:event.isARepeat
                                              keyCode:event.keyCode];
        [self sendEvent:modified];
        DLog(@"Now disable leader");
        [self toggleLeader];
        return YES;
    }
    if ([[iTermKeyMappings leader] isEqual:[iTermKeystroke withEvent:event]]) {
        // Pressed the leader
        DLog(@"Leader pressed");
        iTermShortcutInputView *shortcutInputView = [self focusedShortcutInputView];
        if (!shortcutInputView || shortcutInputView.leaderAllowed) {
            DLog(@"Not in a shortcut input view. Toggle leader.");
            [self toggleLeader];
            return YES;
        }
    }
    return NO;
}

- (BOOL)dispatchHotkeyLocally:(NSEvent *)event {
    if (IsSecureEventInputEnabled() &&
        [[iTermHotKeyController sharedInstance] eventIsHotkey:event]) {
        // User pressed the hotkey while secure input is enabled so the event
        // tap won't get it. Do what the event tap would do in this case.
        DLog(@"Directing to hotkey handler");
        [[iTermHotKeyController sharedInstance] hotkeyPressed:event];
        return YES;
    }
    return NO;
}

- (BOOL)inputMethodHandlerTakesPrecedenceForResponder:(NSResponder *)responder {
    const BOOL inTextView = [responder isKindOfClass:[PTYTextView class]];
    return (inTextView && [(PTYTextView *)responder hasMarkedText]);
}

- (BOOL)handleKeypressInTerminalWindow:(NSEvent *)event {
    if ([[self keyWindow] isTerminalWindow]) {
        // Focus is in a terminal window.
        NSResponder *responder = [[self keyWindow] firstResponder];

        if ([self inputMethodHandlerTakesPrecedenceForResponder:responder]) {
            // Let the IM process it (I used to call interpretKeyEvents:
            // here but it caused bug 2882).
            DLog(@"Sending to input method handler");
            [super sendEvent:event];
            return YES;
        }

        PseudoTerminal* currentTerminal = [[iTermController sharedInstance] currentTerminal];
        if ([self switchToPaneInWindowController:currentTerminal byNumber:event]) {
            return YES;
        }
        if ([self switchToTabInTabView:[currentTerminal tabView] byNumber:event]) {
            return YES;
        }
        if ([self remapEvent:event inResponder:responder currentSession:[currentTerminal currentSession]]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)handleShortcutWithoutTerminal:(NSEvent *)event {
    if ([[self keyWindow] isTerminalWindow] && [[[self keyWindow] firstResponder] it_isTerminalResponder]) {
        // Route to PTYTextView through normal channels.
        return NO;
    }
    // A special key binding action that works regardless of first responder.
    if ([PTYSession handleShortcutWithoutTerminal:event]) {
        DLog(@"handled by session");
        return YES;
    }
    return NO;
}

- (void)reportKeyDownToAPIClientsIfNeeded:(NSEvent *)event {
    if (![event it_eventGetsSpecialHandlingForAPINotifications]) {
        return;
    }
    if (![[self keyWindow] isTerminalWindow]) {
        return;
    }
    __kindof NSResponder *responder = [self.keyWindow firstResponder];
    if (![responder conformsToProtocol:@protocol(iTermSpecialHandlerForAPIKeyDownNotifications)]) {
        return;
    }
    id<iTermSpecialHandlerForAPIKeyDownNotifications> observer = responder;
    [observer handleSpecialKeyDown:event];
}


- (BOOL)handleFlagsChangedEvent:(NSEvent *)event {
    if (_leader && !(event.modifierFlags & iTermLeaderModifierFlag)) {
        DLog(@"Flags changed while leader on. Rewrite event with leader flag and resend");
        NSEvent *flagChangedPlusHelp = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
                                                        location:event.locationInWindow
                                                   modifierFlags:event.modifierFlags | iTermLeaderModifierFlag
                                                       timestamp:event.timestamp
                                                    windowNumber:event.windowNumber
                                                         context:nil
                                                      characters:@""
                                     charactersIgnoringModifiers:@""
                                                       isARepeat:NO
                                                         keyCode:event.keyCode];
        [self sendEvent:flagChangedPlusHelp];
        return YES;
    }
    if ([self routeEventToShortcutInputView:event]) {
        [[iTermFlagsChangedEventTap sharedInstance] resetCount];
        return YES;
    }
    DLog(@"Posting flags-changed notification for event %@", event);
    [[iTermFlagsChangedNotification notificationWithEvent:event] post];
    return NO;
}

- (BOOL)handleKeyDownEvent:(NSEvent *)event {
    DLog(@"Received KeyDown event: %@. Key window is %@. First responder is %@", event, [self keyWindow], [[self keyWindow] firstResponder]);
    if ((event.modifierFlags & iTermLeaderModifierFlag)) {
        DLog(@"Leader flag set");
    }

    if ([self handleLeader:event]) {
        return YES;
    }

    if ([self dispatchHotkeyLocally:event]) {
        return YES;
    }

    if ([self routeEventToShortcutInputView:event]) {
        return YES;
    }

    if ([self switchToWindowByNumber:event]) {
        return YES;
    }

    if ([self handleKeypressInTerminalWindow:event]) {
        return YES;
    }

    if ([self handleShortcutWithoutTerminal:event]) {
        return YES;
    }

    [self reportKeyDownToAPIClientsIfNeeded:event];
    
    return NO;
}

- (void)handleScrollWheelEvent:(NSEvent *)event {
    NSPoint point = event.locationInWindow;
    if (event.window) {
        point = [event.window convertPointToScreen:point];
    }
    NSView *current = [NSView viewAtScreenCoordinate:point];
    if (current.window != event.window) {
        return;
    }
    while (current) {
        if ([current respondsToSelector:@selector(it_wantsScrollWheelMomentumEvents)] &&
            [current it_wantsScrollWheelMomentumEvents]) {
            DLog(@"Deliver scroll event %@ to %@", event, current);
            [current it_scrollWheelMomentum:event];
            return;
        }
        current = current.superview;
    }
}

// override to catch key press events very early on
- (void)sendEvent:(NSEvent *)event {
    if ([event type] == NSEventTypeFlagsChanged) {
        if (_leader) {
            [self makeCursorSparkles];
        }
        event = [self eventByRemappingForSecureInput:event];
        if (!event) {
            DLog(@"Disard event");
            return;
        }
        if ([self handleFlagsChangedEvent:event]) {
            return;
        }
    } else if ([event type] == NSEventTypeKeyDown) {
        event = [self eventByRemappingForSecureInput:event];
        if (!event) {
            DLog(@"Disard event");
            return;
        }
        if ([self handleKeyDownEvent:event]) {
            return;
        }
        DLog(@"NSKeyDown event taking the regular path");
    } else if (event.type == NSEventTypeKeyUp) {
        if (_leader) {
            [self makeCursorSparkles];
        }
    } else if (event.type == NSEventTypeScrollWheel && (event.momentumPhase == NSEventPhaseChanged ||
                                                        event.momentumPhase == NSEventPhaseEnded)) {
        [self handleScrollWheelEvent:event];
    }

    [super sendEvent:event];
}

- (iTermApplicationDelegate *)delegate {
    return (iTermApplicationDelegate *)[super delegate];
}

- (NSEvent *)currentEvent {
    if (_fakeCurrentEvent) {
        return _fakeCurrentEvent;
    } else {
        return [super currentEvent];
    }
}

- (NSArray<iTermScriptingWindow *> *)orderedScriptingWindows {
    return [self.orderedWindows mapWithBlock:^id(NSWindow *window) {
        if ([window conformsToProtocol:@protocol(PTYWindow)]) {
            return [iTermScriptingWindow scriptingWindowWithWindow:window];
        } else {
            return nil;
        }
    }];
}

- (void)setIsUIElement:(BOOL)uiElement {
    if (uiElement == _isUIElement) {
        return;
    }
    _isUIElement = uiElement;

    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn,
                         uiElement ? kProcessTransformToUIElementApplication :
                                     kProcessTransformToForegroundApplication);
    if (uiElement) {
        // Gotta wait for a spin of the runloop or else it doesn't activate. That's bad news
        // when toggling the preference because all the windows disappear.
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        });

        if ([iTermAdvancedSettingsModel statusBarIcon]) {
            NSImage *image = [NSImage it_imageNamed:@"StatusItem" forClass:self.class];
            self.statusBarItem = [[NSStatusBar systemStatusBar] statusItemWithLength:image.size.width];
            _statusBarItem.button.title = @"";
            _statusBarItem.button.image = image;
            _statusBarItem.button.alternateImage = [NSImage it_imageNamed:@"StatusItemAlt" forClass:self.class];
            ((NSButtonCell *)_statusBarItem.button.cell).highlightsBy = NSChangeBackgroundCellMask;

            _statusBarItem.menu = [(id<iTermApplicationDelegate>)[self delegate] statusBarMenu];
        }
    } else if (_statusBarItem != nil) {
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusBarItem];
        self.statusBarItem = nil;
    }
}

- (NSArray<NSWindow *> *)orderedWindowsPlusVisibleHotkeyPanels {
    NSArray<NSWindow *> *panels = [[iTermHotKeyController sharedInstance] visibleFloatingHotkeyWindows] ?: @[];
    return [panels arrayByAddingObjectsFromArray:[self orderedWindows]];
}

- (NSArray<NSWindow *> *)orderedWindowsPlusAllHotkeyPanels {
    NSArray<NSWindow *> *panels = [[iTermHotKeyController sharedInstance] allFloatingHotkeyWindows] ?: @[];
    return [panels arrayByAddingObjectsFromArray:[self orderedWindows]];
}

- (void)activateAppWithCompletion:(void (^)(void))completion {
    DLog(@"Activate with completion...");
    if ([self isActive]) {
        DLog(@"Application already active. Run completion block synchronously");
        completion();
    } else {
        __block id observer;
        DLog(@"Register an observer");
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification
                                                                     object:nil
                                                                      queue:NULL
                                                                 usingBlock:^(NSNotification * _Nonnull note) {
                                                                     DLog(@"Application did become active. Invoke completion block");
                                                                     completion();
                                                                     DLog(@"Application did become active completion block finished. Removing observer.");
                                                                     [[NSNotificationCenter defaultCenter] removeObserver:observer];
                                                                 }];
        // It's not clear how this differs from [self activateIgnoringOtherApps:YES], but on 10.13
        // it does not cause previously ordered-out windows to be ordered over other applications'
        // windows. See issue 6875.
        [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    }
}

- (BOOL)it_characterPanelIsOpen {
    return _it_characterPanelShouldOpenSoon || _it_characterPanelIsOpen;
}

- (void)orderFrontCharacterPalette:(id)sender {
    _it_characterPanelShouldOpenSoon = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationCharacterPaletteWillOpen
                                                        object:nil];
    [super orderFrontCharacterPalette:sender];
    const NSTimeInterval deadlineToOpen = ([NSDate timeIntervalSinceReferenceDate] +
                                           [iTermAdvancedSettingsModel timeToWaitForEmojiPanel]);
    [iTermWindowHacks pollForCharacterPanelToOpenOrCloseWithCompletion:^BOOL(BOOL open) {
        if (open && self->_it_characterPanelShouldOpenSoon) {
            self->_it_characterPanelShouldOpenSoon = NO;
            self->_it_characterPanelIsOpen = YES;
        } else if (!open && self.it_characterPanelIsOpen) {
            self->_it_characterPanelShouldOpenSoon = NO;
            self->_it_characterPanelIsOpen = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationCharacterPaletteDidClose
                                                                object:nil];
        }
        return open || ([NSDate timeIntervalSinceReferenceDate] < deadlineToOpen);  // keep running while open
    }];
}

- (void)it_makeWindowKey:(NSWindow *)window {
    NSWindow *saved = self.it_windowBecomingKey;
    self.it_windowBecomingKey = window;
    [window makeKeyAndOrderFront:nil];
    self.it_windowBecomingKey = saved;
}

- (void)invalidateRestorableState {
    [super invalidateRestorableState];
    _it_restorableStateInvalid = YES;
}

- (void)toggleLeader {
    if (_leader) {
        DLog(@"leader up");
        [[NSCursor arrowCursor] set];
        NSEvent *event = [self currentEvent];
        NSEvent *flagUp = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
                                           location:event.locationInWindow
                                      modifierFlags:event.modifierFlags & ~iTermLeaderModifierFlag
                                          timestamp:event.timestamp
                                       windowNumber:event.windowNumber
                                            context:nil
                                         characters:@""
                        charactersIgnoringModifiers:@""
                                          isARepeat:NO
                                            keyCode:kVK_Help];
        [self sendEvent:flagUp];
    } else {
        DLog(@"leader down");
        [self makeCursorSparkles];
        NSEvent *event = [self currentEvent];
        NSEvent *flagDown = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
                                             location:event.locationInWindow
                                        modifierFlags:event.modifierFlags | iTermLeaderModifierFlag
                                            timestamp:event.timestamp
                                         windowNumber:event.windowNumber
                                              context:nil
                                           characters:@""
                          charactersIgnoringModifiers:@""
                                            isARepeat:NO
                                              keyCode:kVK_Help];
        [self sendEvent:flagDown];
    }
    _leader = !_leader;
}

- (void)makeCursorSparkles {
    if (@available(macOS 11.0, *)) {
        static NSCursor *sparkles;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSImage *image = [NSImage imageWithSystemSymbolName:@"sparkles"
                                       accessibilityDescription:@"Leader pending"];
            NSImage *black = [image it_imageWithTintColor:[NSColor blackColor]];
            NSImage *white = [image it_imageWithTintColor:[NSColor whiteColor]];
            NSSize size = image.size;
            size.width *= 1.25;
            size.height *= 1.25;
            NSImage *composite = [NSImage imageOfSize:NSMakeSize(size.width + 1, size.height + 1)
                                            drawBlock:^{
                for (int dx = 0; dx <= 2; dx++) {
                    for (int dy = 0; dy <= 2; dy++){
                        if (dx == 1 && dy == 1) {
                            continue;
                        }
                        [white drawInRect:NSMakeRect(dx / 2,
                                                     dy / 2,
                                                     size.width,
                                                     size.height)
                                 fromRect:NSZeroRect
                                operation:NSCompositingOperationSourceOver
                                 fraction:1];
                    }
                }
                [black drawInRect:NSMakeRect(1.0 / 2,
                                             1.0 / 2,
                                             size.width,
                                             size.height)
                         fromRect:NSZeroRect
                        operation:NSCompositingOperationSourceOver
                         fraction:1];
            }];
            sparkles = [[NSCursor alloc] initWithImage:composite hotSpot:NSMakePoint(size.width / 2.0, size.height / 2.0)];
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            [sparkles set];
        });
    }
}

@end

