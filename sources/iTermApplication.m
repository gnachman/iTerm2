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
#import "iTermController.h"
#import "iTermHotKeyController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermModifierRemapper.h"
#import "iTermPreferences.h"
#import "iTermScriptingWindow.h"
#import "iTermShortcutInputView.h"
#import "NSArray+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"

@interface iTermApplication()
@property(nonatomic, retain) NSStatusItem *statusBarItem;
@end

@implementation iTermApplication {
    BOOL _isUIElement;
}

- (void)dealloc {
    [_fakeCurrentEvent release];
    [super dealloc];
}

+ (iTermApplication *)sharedApplication {
    __kindof NSApplication *sharedApplication = [super sharedApplication];
    assert([sharedApplication isKindOfClass:[iTermApplication class]]);
    return sharedApplication;
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
            [shortcutView handleShortcutEvent:event];
            return YES;
        }
    }
    return NO;
}

// override to catch key press events very early on
- (void)sendEvent:(NSEvent *)event {
    if ([event type] == NSFlagsChanged) {
        event = [self eventByRemappingForSecureInput:event];
        if ([self routeEventToShortcutInputView:event]) {
            return;
        }
    } else if ([event type] == NSKeyDown) {
        iTermController* cont = [iTermController sharedInstance];

        event = [self eventByRemappingForSecureInput:event];
        if (IsSecureEventInputEnabled() &&
            [[iTermHotKeyController sharedInstance] eventIsHotkey:event]) {
            // User pressed the hotkey while secure input is enabled so the event
            // tap won't get it. Do what the event tap would do in this case.
            DLog(@"Directing to hotkey handler");
            [[iTermHotKeyController sharedInstance] hotkeyPressed:event];
            return;
        }
        PseudoTerminal* currentTerminal = [cont currentTerminal];
        PTYTabView* tabView = [currentTerminal tabView];
        PTYSession* currentSession = [currentTerminal currentSession];
        NSResponder *responder;

        if ([self routeEventToShortcutInputView:event]) {
            return;
        }

        const NSUInteger allModifiers =
            (NSShiftKeyMask | NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask);
        if (([event modifierFlags] & allModifiers) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchWindowModifier]]) {
            // Command-Alt (or selected modifier) + number: Switch to window by number.
            int digit = [[event charactersIgnoringModifiers] intValue];
            if (!digit) {
                digit = [[event characters] intValue];
            }
            if (digit >= 1 && digit <= 9) {
                PseudoTerminal* termWithNumber = [cont terminalWithNumber:(digit - 1)];
                DLog(@"Switching windows");
                if (termWithNumber) {
                    if ([termWithNumber isHotKeyWindow] && [[termWithNumber window] alphaValue] < 1) {
                        iTermProfileHotKey *hotKey =
                            [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:termWithNumber];
                        [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:hotKey];
                    } else {
                        [[termWithNumber window] makeKeyAndOrderFront:self];
                    }
                }
                return;
            }
        }

        if ([[self keyWindow] isTerminalWindow]) {
            // Focus is in a terminal window.
            responder = [[self keyWindow] firstResponder];
            bool inTextView = [responder isKindOfClass:[PTYTextView class]];

            if (inTextView && [(PTYTextView *)responder hasMarkedText]) {
                // Let the IM process it (I used to call interpretKeyEvents:
                // here but it caused bug 2882).
                DLog(@"Sending to input method handler");
                [super sendEvent:event];
                return;
            }

            const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
            if (([event modifierFlags] & mask) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchPaneModifier]]) {
                int digit = [[event charactersIgnoringModifiers] intValue];
                if (!digit) {
                    digit = [[event characters] intValue];
                }
                NSArray *orderedSessions = currentTerminal.currentTab.orderedSessions;
                int numSessions = [orderedSessions count];
                if (digit == 9 && numSessions > 0) {
                    // Modifier+9: Switch to last split pane if there are fewer than 9.
                    DLog(@"Switching to last split pane");
                    [currentTerminal.currentTab setActiveSession:[orderedSessions lastObject]];
                    return;
                }
                if (digit >= 1 && digit <= numSessions) {
                    // Modifier+number: Switch to split pane by number.
                    DLog(@"Switching to split pane");
                    [currentTerminal.currentTab setActiveSession:orderedSessions[digit - 1]];
                    return;
                }
            }
            if (([event modifierFlags] & mask) == [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]]) {
                int digit = [[event charactersIgnoringModifiers] intValue];
                if (!digit) {
                    digit = [[event characters] intValue];
                }
                if (digit == 9 && [tabView numberOfTabViewItems] > 0) {
                    // Command (or selected modifier)+9: Switch to last tab if there are fewer than 9.
                    DLog(@"Switching to last tab");
                    [tabView selectTabViewItemAtIndex:[tabView numberOfTabViewItems]-1];
                    return;
                }
                if (digit >= 1 && digit <= [tabView numberOfTabViewItems]) {
                    // Command (or selected modifier)+number: Switch to tab by number.
                    DLog(@"Switching tabs");
                    [tabView selectTabViewItemAtIndex:digit-1];
                    return;
                }
            }

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
                // Remap key.
                DLog(@"Remapping to actionable event");
                [currentSession keyDown:event];
                return;
            }
        } else {
            // Focus not in terminal window.
            if ([PTYSession handleShortcutWithoutTerminal:event]) {
                DLog(@"handled by session");
                return;
            }
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
    return [self.windows mapWithBlock:^id(NSWindow *window) {
        if ([window conformsToProtocol:@protocol(PTYWindow)]) {
            return [iTermScriptingWindow scriptingWindowWithWindow:window];
        } else {
            return nil;
        }
    }];
}

- (void)setIsUIElementApplication:(BOOL)uiElement {
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
        
        NSImage *image = [NSImage imageNamed:@"StatusItem"];
        self.statusBarItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:image.size.width] retain];
        _statusBarItem.title = @"";
        _statusBarItem.image = image;
        _statusBarItem.alternateImage = [NSImage imageNamed:@"StatusItemAlt"];
        _statusBarItem.highlightMode = YES;
        
        _statusBarItem.menu = [[self delegate] statusBarMenu];
        
    } else {
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

@end

