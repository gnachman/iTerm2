// -*- mode:objc -*-
// $Id: iTermApplication.m,v 1.10 2006-11-07 08:03:08 yfabian Exp $
//
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
#import "HotkeyWindowController.h"
#import "NSTextField+iTerm.h"
#import "PTYSession.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"

@implementation iTermApplication

- (BOOL)_eventUsesNavigationKeys:(NSEvent*)event
{
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

// override to catch key press events very early on
- (void)sendEvent:(NSEvent*)event
{
    if ([event type] == NSKeyDown) {
        iTermController* cont = [iTermController sharedInstance];
#ifdef FAKE_EVENT_TAP
        event = [cont runEventTapHandler:event];
        if (!event) {
            return;
        }
#endif
        PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
        if ([prefPanel isAnyModifierRemapped] &&
            (IsSecureEventInputEnabled() || ![[HotkeyWindowController sharedInstance] haveEventTap])) {
            // The event tap is not working, but we can still remap modifiers for non-system
            // keys. Only things like cmd-tab will not be remapped in this case. Otherwise,
            // the event tap performs the remapping.
            event = [iTermKeyBindingMgr remapModifiers:event prefPanel:prefPanel];
        }
        if (IsSecureEventInputEnabled() &&
            [[HotkeyWindowController sharedInstance] eventIsHotkey:event]) {
            // User pressed the hotkey while secure input is enabled so the event
            // tap won't get it. Do what the event tap would do in this case.
            OnHotKeyEvent();
            return;
        }
        PreferencePanel* privatePrefPanel = [PreferencePanel sessionsInstance];
        PseudoTerminal* currentTerminal = [cont currentTerminal];
        PTYTabView* tabView = [currentTerminal tabView];
        PTYSession* currentSession = [currentTerminal currentSession];
        NSResponder *responder;

        if (([event modifierFlags] & (NSControlKeyMask | NSCommandKeyMask | NSAlternateKeyMask)) == [prefPanel modifierTagToMask:[prefPanel switchWindowModifier]]) {
            // Command-Alt (or selected modifier) + number: Switch to window by number.
            int digit = [[event charactersIgnoringModifiers] intValue];
            if (!digit) {
                digit = [[event characters] intValue];
            }
            if (digit >= 1 && digit <= 9) {
                PseudoTerminal* termWithNumber = [cont terminalWithNumber:(digit - 1)];
                if (termWithNumber) {
                    if ([termWithNumber isHotKeyWindow] && [[termWithNumber window] alphaValue] < 1) {
                        [[HotkeyWindowController sharedInstance] showHotKeyWindow];
                    } else {
                        [[termWithNumber window] makeKeyAndOrderFront:self];
                    }
                }
                return;
            }
        }
        if ([prefPanel keySheet] == [self keyWindow] &&
            [prefPanel keySheetIsOpen] &&
            [[prefPanel shortcutKeyTextField] textFieldIsFirstResponder]) {
            // Focus is in the shortcut field in prefspanel. Pass events directly to it.
            [prefPanel shortcutKeyDown:event];
            return;
        } else if ([privatePrefPanel keySheet] == [self keyWindow] &&
                   [privatePrefPanel keySheetIsOpen] &&
                   [[privatePrefPanel shortcutKeyTextField] textFieldIsFirstResponder]) {
            // Focus is in the shortcut field in sessions prefspanel. Pass events directly to it.
            [privatePrefPanel shortcutKeyDown:event];
            return;
        } else if ([prefPanel window] == [self keyWindow] &&
                   [[prefPanel hotkeyField] textFieldIsFirstResponder]) {
            // Focus is in the hotkey field in prefspanel. Pass events directly to it.
            [prefPanel hotkeyKeyDown:event];
            return;
        } else if ([[self keyWindow] isKindOfClass:[PTYWindow class]]) {
            // Focus is in a terminal window.
            responder = [[self keyWindow] firstResponder];
            bool inTextView = [responder isKindOfClass:[PTYTextView class]];

            if (inTextView && [(PTYTextView *)responder hasMarkedText]) {
                // Let the IM process it (I used to call interpretKeyEvents:
                // here but it caused bug 2882).
                [super sendEvent:event];
                return;
            }

            const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
            if (([event modifierFlags] & mask) == [prefPanel modifierTagToMask:[prefPanel switchTabModifier]]) {
                int digit = [[event charactersIgnoringModifiers] intValue];
                if (!digit) {
                    digit = [[event characters] intValue];
                }
                if (digit == 9 && [tabView numberOfTabViewItems] > 0) {
                    // Command (or selected modifier)+9: Switch to last tab if there are fewer than 9.
                    [tabView selectTabViewItemAtIndex:[tabView numberOfTabViewItems]-1];
                    return;
                }
                if (digit >= 1 && digit <= [tabView numberOfTabViewItems]) {
                    // Command (or selected modifier)+number: Switch to tab by number.
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
                [currentSession keyDown:event];
                return;
            }
        } else {
            // Focus not in terminal window.
            if ([PTYSession handleShortcutWithoutTerminal:event]) {
                return;
            }
        }
    }

    [super sendEvent:event];
}

- (NSString *)uriToken
{
    return [[self delegate] uriToken];
}

- (iTermApplicationDelegate *)delegate
{
    return (iTermApplicationDelegate *)[super delegate];
}

@end

