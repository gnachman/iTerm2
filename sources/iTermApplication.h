// -*- mode:objc -*-
// $Id: iTermApplication.h,v 1.4 2006-11-07 08:03:08 yfabian Exp $
//
/*
 **  iTermApplication.h
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

#import <Cocoa/Cocoa.h>
#import "PTYWindow.h"

// Used for keys you can press on the touch bar that have no equivalent on physical keyboards that Apple recognizes
extern unsigned short iTermBogusVirtualKeyCode;

// Notifications posted when the character panel opens/closes. A pile of hacks.
extern NSString *const iTermApplicationCharacterPaletteWillOpen;
extern NSString *const iTermApplicationCharacterPaletteDidClose;
extern NSString *const iTermApplicationInputMethodEditorDidOpen;
extern NSString *const iTermApplicationInputMethodEditorDidClose;

extern NSString *const iTermApplicationWillShowModalWindow;
extern NSString *const iTermApplicationDidCloseModalWindow;

@class iTermApplicationDelegate;
@class iTermScriptingWindow;

@protocol iTermApplicationDelegate<NSApplicationDelegate>
- (NSMenu *)statusBarMenu;
@end

@interface iTermApplication : NSApplication

+ (iTermApplication *)sharedApplication;

- (NSArray<NSWindow *> *)orderedWindowsPlusVisibleHotkeyPanels;
- (NSArray<NSWindow *> *)orderedWindowsPlusAllHotkeyPanels;

// Sets the return value for -currentEvent. Only for testing.
@property(atomic, retain) NSEvent *fakeCurrentEvent;
@property(nonatomic, readonly) NSStatusItem *statusBarItem;
@property(nonatomic) BOOL isUIElement;
@property(nonatomic) BOOL localAuthenticationDialogOpen;
@property(nonatomic) BOOL it_characterPanelIsOpen;
@property(nonatomic, readonly) BOOL it_modalWindowOpen;
@property(nonatomic, readonly) BOOL it_imeOpen;

- (void)sendEvent:(NSEvent *)anEvent;
- (iTermApplicationDelegate<iTermApplicationDelegate> *)delegate;
- (BOOL)routeEventToShortcutInputView:(NSEvent *)event;

// Like orderedWindows, but only iTermWindow/iTermPanel objects wrapped in iTermScriptingWindow*s are returned.
- (NSArray<iTermScriptingWindow *> *)orderedScriptingWindows;

- (void)activateAppWithCompletion:(void (^)(void))completion;

@end
