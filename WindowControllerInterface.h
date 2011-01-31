// -*- mode:objc -*-
/*
 **  WindowControllerInterface
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Defines a protocol shared by PseudoTerminal and FakeWindow.
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
@class PTYSession;
@class PTYTabView;
@class PTYTab;

@protocol WindowControllerInterface <NSObject>

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;
- (BOOL)fullScreen;
- (BOOL)sendInputToAllSessions;
- (void)closeSession:(PTYSession*)aSession;
- (IBAction)nextTab:(id)sender;
- (IBAction)previousTab:(id)sender;
- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem;
- (void)setTabColor:(NSColor *)color forTabViewItem:tabViewItem;
- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem;
- (void)enableBlur;
- (void)disableBlur;
- (BOOL)tempTitle;
- (void)fitWindowToTab:(PTYTab*)tab;
- (PTYTabView *)tabView;
- (PTYSession *)currentSession;
- (void)sendInputToAllSessions:(NSData *)data;
- (void)setWindowTitle;
- (void)resetTempTitle;
- (PTYTab*)currentTab;
- (void)closeTab:(PTYTab*)theTab;

- (void)windowSetFrameTopLeftPoint:(NSPoint)point;
- (void)windowPerformMiniaturize:(id)sender;
- (void)windowDeminiaturize:(id)sender;
- (void)windowOrderFront:(id)sender;
- (void)windowOrderBack:(id)sender;
- (BOOL)windowIsMiniaturized;
- (NSRect)windowFrame;
- (NSScreen*)windowScreen;

@end
