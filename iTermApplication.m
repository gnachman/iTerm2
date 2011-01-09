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
#import <iTerm/iTermController.h>
#import <iTerm/PTYWindow.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYSession.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/PTYTextView.h>

@implementation iTermApplication

+ (BOOL)isTextFieldInFocus:(NSTextField *)textField
{
    BOOL inFocus = NO;

    // If the textfield's widow's first responder is a text view and
    // the default editor for the text field exists and
    // the textfield is the textfield's window's first responder's delegate
    inFocus = ([[[textField window] firstResponder] isKindOfClass:[NSTextView class]]
               && [[textField window] fieldEditor:NO forObject:nil]!=nil
               && [textField isEqualTo:(id)[(NSTextView *)[[textField window] firstResponder]delegate]]);
    
    return inFocus;
}

// override to catch key press events very early on
- (void)sendEvent:(NSEvent*)event
{
    if ([event type] == NSKeyDown) {
        if (IsSecureEventInputEnabled() &&
            [[iTermController sharedInstance] eventIsHotkey:event]) {
            // User pressed the hotkey while secure input is enabled so the event
            // tap won't get it. Do what the event tap would do in this case.
            OnHotKeyEvent();
            return;
        }
        PreferencePanel* prefPanel = [PreferencePanel sharedInstance];
        PreferencePanel* privatePrefPanel = [PreferencePanel sessionsInstance];
        PseudoTerminal* currentTerminal = [[iTermController sharedInstance] currentTerminal];
        PTYTabView* tabView = [currentTerminal tabView];
        PTYSession* currentSession = [currentTerminal currentSession];
        NSResponder *responder;

        if (([event modifierFlags] & (NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask)) == (NSCommandKeyMask | NSAlternateKeyMask)) {
            // Command-Alt number: Switch to window by number.
            int digit = [[event charactersIgnoringModifiers] intValue];
            if (digit >= 1 && digit <= 9 && [[iTermController sharedInstance] numberOfTerminals] >= digit) {
                PseudoTerminal* termWithNumber = [[iTermController sharedInstance] terminalAtIndex:(digit - 1)];
                [[termWithNumber window] makeKeyAndOrderFront:self];
                return;
            }
        }
        if ([prefPanel keySheet] == [self keyWindow] &&
            [prefPanel keySheetIsOpen] &&
            [iTermApplication isTextFieldInFocus:[prefPanel shortcutKeyTextField]]) {
            // Focus is in the shortcut field in prefspanel. Pass events directly to it.
            [prefPanel shortcutKeyDown:event];
            return;
        } else if ([privatePrefPanel keySheet] == [self keyWindow] &&
                   [privatePrefPanel keySheetIsOpen] &&
                   [iTermApplication isTextFieldInFocus:[privatePrefPanel shortcutKeyTextField]]) {
            // Focus is in the shortcut field in sessions prefspanel. Pass events directly to it.
            [privatePrefPanel shortcutKeyDown:event];
            return;
        } else if ([prefPanel window] == [self keyWindow] &&
                   [iTermApplication isTextFieldInFocus:[prefPanel hotkeyField]]) {
            // Focus is in the hotkey field in prefspanel. Pass events directly to it.
            [prefPanel hotkeyKeyDown:event];
            return;
        } else if ([[self keyWindow] isKindOfClass:[PTYWindow class]]) {
            // Focus is in a terminal window.
            responder = [[self keyWindow] firstResponder];
            bool inTextView = [responder isKindOfClass:[PTYTextView class]];

            if (inTextView &&
                [(PTYTextView *)responder hasMarkedText]) {
                // Let the IM process it
                [(PTYTextView *)responder interpretKeyEvents:[NSArray arrayWithObject:event]];
                return;
            }

            const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
            if (([event modifierFlags] & mask) == NSCommandKeyMask) {
                int digit = [[event charactersIgnoringModifiers] intValue];
                if (digit >= 1 && digit <= [tabView numberOfTabViewItems]) {
                    // Command+number: Switch to tab by number.
                    [tabView selectTabViewItemAtIndex:digit-1];
                    return;
                }
            }

            if (inTextView &&
                [currentSession hasKeyMappingForEvent:event highPriority:YES]) {
                // Remap key.
                [currentSession keyDown:event];
                return;
            }
        }
    }

    [super sendEvent: event];
}

@end

