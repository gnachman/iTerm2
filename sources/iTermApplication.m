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
#import "iTermHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermModifierRemapper.h"
#import "iTermPreferences.h"
#import "iTermScriptingWindow.h"
#import "iTermShortcutInputView.h"
#import "iTermWindowHacks.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"
#import "NSImage+iTerm.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"

unsigned short iTermBogusVirtualKeyCode = 0xffff;
NSString *const iTermApplicationCharacterPaletteWillOpen = @"iTermApplicationCharacterPaletteWillOpen";
NSString *const iTermApplicationCharacterPaletteDidClose = @"iTermApplicationCharacterPaletteDidClose";

NSString *const iTermApplicationWillShowModalWindow = @"iTermApplicationWillShowModalWindow";
NSString *const iTermApplicationDidCloseModalWindow = @"iTermApplicationDidCloseModalWindow";

@interface iTermApplication()
@property(nonatomic, retain) NSStatusItem *statusBarItem;
@end

static const char *iTermApplicationKVOKey = "iTermApplicationKVOKey";

@implementation iTermApplication {
    BOOL _it_characterPanelIsOpen;
    BOOL _it_characterPanelShouldOpenSoon;
}

- (void)dealloc {
    [_fakeCurrentEvent release];
    [_statusBarItem release];
    [self removeObserver:self forKeyPath:@"modalWindow"];
    [super dealloc];
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
    });
    return sharedApplication;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context == iTermApplicationKVOKey &&
        [keyPath isEqualToString:@"modalWindow"]) {
        change = [change dictionaryByRemovingNullValues];
        if (change[NSKeyValueChangeOldKey] == nil &&
            change[NSKeyValueChangeNewKey] != nil) {
            _it_modalWindowOpen = YES;
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationWillShowModalWindow object:nil];
        } else if (change[NSKeyValueChangeOldKey] != nil &&
                   change[NSKeyValueChangeNewKey] == nil) {
            _it_modalWindowOpen = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationDidCloseModalWindow object:nil];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
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
        event = [iTermKeyBindingMgr remapModifiers:event];
        DLog(@"Remapped modifiers to %@", event);
    }
    return event;
}

- (BOOL)routeEventToShortcutInputView:(NSEvent *)event {
    NSResponder *firstResponder = [[NSApp keyWindow] firstResponder];
    if ([firstResponder isKindOfClass:[iTermShortcutInputView class]]) {
        iTermShortcutInputView *shortcutView = (iTermShortcutInputView *)firstResponder;
        if (shortcutView) {
            if (event.keyCode == iTermBogusVirtualKeyCode) {
                // You can't register a carbon hotkey for these so just ignore them when listining for a shortcut.
                return YES;
            }
            [shortcutView handleShortcutEvent:event];
            return YES;
        }
    }
    return NO;
}

- (int)digitKeyForEvent:(NSEvent *)event {
    if ([iTermAdvancedSettingsModel useVirtualKeyCodesForDetectingDigits]) {
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
    if (([event modifierFlags] & allModifiers) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchWindowModifier]]) {
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
    if (([event modifierFlags] & mask) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchPaneModifier]]) {
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
    if (([event modifierFlags] & mask) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]]) {
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

    if (okToRemap && [currentSession hasActionableKeyMappingForEvent:event] && !currentSession.copyMode) {
        // Remap key.
        DLog(@"Remapping to actionable event");
        [currentSession keyDown:event];
        return YES;
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
    if ([[self keyWindow] isTerminalWindow]) {
        return NO;
    }
    if ([PTYSession handleShortcutWithoutTerminal:event]) {
        DLog(@"handled by session");
        return YES;
    }
    return NO;
}

- (BOOL)handleFlagsChangedEvent:(NSEvent *)event {
    if ([self routeEventToShortcutInputView:event]) {
        return YES;
    }

    return NO;
}

- (BOOL)handleKeyDownEvent:(NSEvent *)event {
    DLog(@"Received KeyDown event: %@. Key window is %@. First responder is %@", event, [self keyWindow], [[self keyWindow] firstResponder]);

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

    return NO;
}

// override to catch key press events very early on
- (void)sendEvent:(NSEvent *)event {
    if ([event type] == NSEventTypeFlagsChanged) {
        event = [self eventByRemappingForSecureInput:event];
        if ([self handleFlagsChangedEvent:event]) {
            return;
        }
    } else if ([event type] == NSEventTypeKeyDown) {
        event = [self eventByRemappingForSecureInput:event];
        if ([self handleKeyDownEvent:event]) {
            return;
        }
        DLog(@"NSKeyDown event taking the regular path");
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
            _statusBarItem.title = @"";
            _statusBarItem.image = image;
            _statusBarItem.alternateImage = [NSImage it_imageNamed:@"StatusItemAlt" forClass:self.class];
            _statusBarItem.highlightMode = YES;

            _statusBarItem.menu = [[self delegate] statusBarMenu];
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
        if (open && _it_characterPanelShouldOpenSoon) {
            _it_characterPanelShouldOpenSoon = NO;
            _it_characterPanelIsOpen = YES;
        } else if (!open && self.it_characterPanelIsOpen) {
            self->_it_characterPanelShouldOpenSoon = NO;
            self->_it_characterPanelIsOpen = NO;
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermApplicationCharacterPaletteDidClose
                                                                object:nil];
        }
        return open || ([NSDate timeIntervalSinceReferenceDate] < deadlineToOpen);  // keep running while open
    }];
}

@end

