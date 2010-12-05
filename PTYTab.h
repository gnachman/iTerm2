// -*- mode:objc -*-
/*
 **  PTYTab.h
 **
 **  Copyright (c) 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: PTYTab abstracts the concept of a tab. This is
 **  attached to the tabview's identifier and is the owner of
 **  PTYSession.
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
#import "WindowControllerInterface.h"

@class PTYSession;
@class PseudoTerminal;
@class FakeWindow;

@interface PTYTab : NSObject {
    PTYSession* session_;

    // Owning tab view item
    NSTabViewItem* tabViewItem_;

    id<WindowControllerInterface> parentWindow_;  // Parent controller. Always set. Equals one of realParent or fakeParent.
    PseudoTerminal* realParentWindow_;  // non-nil only if parent is PseudoTerminal*
    FakeWindow* fakeParentWindow_;  // non-nil only if parent is FakeWindow*

    // The tab number that is observed by PSMTabBarControl.
    int objectCount_;

    // The icon to display in the tab. Observed by PSMTabBarControl.
    NSImage* icon_;

    // Whether the session is "busy". Observed by PSMTabBarControl.
    BOOL isProcessing_;

    // Does any session have new output?
    BOOL newOutput_;
}

// init/dealloc
- (id)initWithSession:(PTYSession*)session;
- (void)dealloc;

- (PTYSession*)activeSession;
- (NSTabViewItem *)tabViewItem;
- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem;

- (PTYSession*)activeSession;
- (id<WindowControllerInterface>)parentWindow;
- (PseudoTerminal*)realParentWindow;
- (void)setParentWindow:(PseudoTerminal*)theParent;
- (void)setFakeParentWindow:(FakeWindow*)theParent;
- (FakeWindow*)fakeWindow;
- (NSTabViewItem *)tabViewItem;
- (void)setTabViewItem: (NSTabViewItem *)theTabViewItem;

- (void)setBell:(BOOL)flag;
- (void)nameOfSession:(PTYSession*)session didChangeTo:(NSString*)newName;

- (BOOL)isForegroundTab;
- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;

// Tab index.
- (int)number;

- (int)realObjectCount;
// These values are observed by PSMTTabBarControl:
// Tab number for display
- (int)objectCount;
- (void)setObjectCount:(int)value;
// Icon to display in tab
- (NSImage *)icon;
- (void)setIcon:(NSImage *)anIcon;
// Should show busy indicator in tab?
- (BOOL)isProcessing;
- (void)setIsProcessing:(BOOL)aFlag;
- (BOOL)isActiveSession;
- (BOOL)anySessionHasNewOutput;
- (void)setLabelAttributes;
- (void)closeSession:(PTYSession*)session;
- (void)terminateAllSessions;
- (NSArray*)sessions;
- (BOOL)allSessionsExited;
- (void)setDvrInSession:(PTYSession*)newSession;
- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession;

@end


@interface PTYTab (Private)

- (void)_setLabelAttributesForDeadSession;
- (void)_setLabelAttributesForForegroundTab;
- (void)_setLabelAttributesForActiveBackgroundTab;
- (void)_setLabelAttributesForIdleBackgroundTabAtTime:(struct timeval)now;

@end
