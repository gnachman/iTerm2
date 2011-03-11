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

static const int MIN_SESSION_ROWS = 2;
static const int MIN_SESSION_COLUMNS = 2;

@class PTYSession;
@class PseudoTerminal;
@class FakeWindow;
@class SessionView;

// This implements NSSplitViewDelegate but it was an informal protocol in 10.5. If 10.5 support
// is eventually dropped, change this to make it official.
@interface PTYTab : NSObject {
    PTYSession* activeSession_;

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

    // The root of a tree of split views whose leaves are SessionViews. The root is the view of the
    // NSTabViewItem.
    //
    // NSTabView -> NSTabViewItem -> NSSplitView (root) -> ... -> SessionView -> PTYScrollView -> etc.
    NSSplitView* root_;

    // If non-nil, this session may not change size.
    PTYSession* lockedSession_;

    // The active pane is maximized, meaning there are other panes that are hidden.
    BOOL isMaximized_;
    NSMutableDictionary* idMap_;  // maps saved session id to ptysession.
    NSDictionary* savedArrangement_;  // layout of splitters pre-maximize
    NSSize savedSize_;  // pre-maximize active session size.

    // An array of view IDs that can be thought of as cyclic, ordered from least
    // recently used to most recently, beginning at currentViewIndex_.
    NSMutableArray* viewOrder_;
    int currentViewIndex_;

    // This is >0 if currently inside setActiveSessionPreservingViewOrder, and the
    // view order should not be changed.
    int preserveOrder_;
}

// init/dealloc
- (id)initWithSession:(PTYSession*)session;
- (id)initWithRoot:(NSSplitView*)root;
- (void)dealloc;

- (NSRect)absoluteFrame;
- (PTYSession*)activeSession;
- (void)setActiveSessionPreservingViewOrder:(PTYSession*)session;
- (void)setActiveSession:(PTYSession*)session;
- (NSTabViewItem *)tabViewItem;
- (void)setTabViewItem:(NSTabViewItem *)theTabViewItem;
- (void)previousSession;
- (void)nextSession;

- (void)setLockedSession:(PTYSession*)lockedSession;
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
- (void)fitSessionToCurrentViewSize:(PTYSession*)aSession;

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
- (BOOL)realIsProcessing;
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
- (BOOL)hasMultipleSessions;
- (NSSize)size;
- (NSSize)minSize;
- (void)setSize:(NSSize)newSize;
- (PTYSession*)sessionLeftOf:(PTYSession*)session;
- (PTYSession*)sessionRightOf:(PTYSession*)session;
- (PTYSession*)sessionAbove:(PTYSession*)session;
- (PTYSession*)sessionBelow:(PTYSession*)session;
- (BOOL)canSplitVertically:(BOOL)isVertical withSize:(NSSize)newSessionSize;
- (NSImage*)image:(BOOL)withSpaceForFrame;
- (bool)blur;
- (void)recheckBlur;

- (NSSize)_minSessionSize:(SessionView*)sessionView;
- (NSSize)_sessionSize:(SessionView*)sessionView;

// Remove a dead session. This should be called from [session terminate] only.
- (void)removeSession:(PTYSession*)aSession;

// If the active session's parent splitview has:
//   only one child: make its orientation vertical and add a new subview.
//   more than one child and a vertical orientation: add a new subview and return it.
//   more than one child and a horizontal orientation: add a new split subview with vertical orientation and add a sessionview subview to it and return that sessionview.
- (SessionView*)splitVertically:(BOOL)isVertical targetSession:(PTYSession*)targetSession;
- (NSSize)_recursiveMinSize:(NSSplitView*)node;
- (PTYSession*)_recursiveSessionAtPoint:(NSPoint)point relativeTo:(NSView*)node;

+ (void)openTabWithArrangement:(NSDictionary*)arrangement inTerminal:(PseudoTerminal*)term;
- (NSDictionary*)arrangement;

- (BOOL)hasMaximizedPane;
- (void)maximize;
- (void)unmaximize;

#pragma mark NSSplitView delegate methods
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification;
// This is the implementation of splitViewDidResizeSubviews. The delegate method isn't called when
// views are added or adjusted, so we often have to call this ourselves.
- (void)_splitViewDidResizeSubviews:(NSSplitView*)splitView;
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition ofSubviewAt:(NSInteger)dividerIndex;
- (void)_recursiveRemoveView:(NSView*)theView;

@end


@interface PTYTab (Private)

- (void)_setLabelAttributesForDeadSession;
- (void)_setLabelAttributesForForegroundTab;
- (void)_setLabelAttributesForActiveBackgroundTab;
- (void)_setLabelAttributesForIdleBackgroundTabAtTime:(struct timeval)now;

@end
