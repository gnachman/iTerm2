/*
 **  PTYWindow.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: NSWindow subclass. Implements smart window placement and blur.
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
#import "iTermWeakReference.h"

@class PTYTab;
@class PTYSession;

// The key used for a window's arrangement in encoding restorable state.
extern NSString *const kTerminalWindowStateRestorationWindowArrangementKey;

// Rate limit title changes since they force a redraw.
extern const NSTimeInterval iTermWindowTitleChangeMinimumInterval;

// Extra methods for delegates of terminal windows to implement.
@protocol PTYWindowDelegateProtocol<NSObject,NSWindowDelegate>
- (BOOL)lionFullScreen;
- (BOOL)anyFullScreen;
- (void)windowWillShowInitial;
- (void)toggleTraditionalFullScreenMode;

// Returns the tab a session belongs to.
- (PTYTab *)tabForSession:(PTYSession *)session;

// Should the window's frame be constrainted to its present screen?
- (BOOL)terminalWindowShouldConstrainFrameToScreen;
- (NSColor *)terminalWindowDecorationBackgroundColor;
- (NSColor *)terminalWindowDecorationTextColor;
- (BOOL)terminalWindowUseMinimalStyle;

@end

// Common methods implemented by terminal windows of both kinds.
@protocol PTYWindow<NSObject>
@property(nonatomic, readonly) int screenNumber;
@property(nonatomic, readonly, getter=isTogglingLionFullScreen) BOOL togglingLionFullScreen;
// A unique identifier that does not get recycled during the program's lifetime.
@property(nonatomic, readonly) NSString *windowIdentifier;
@property(nonatomic, readonly) id<PTYWindowDelegateProtocol> ptyDelegate;
@property(nonatomic, readonly) BOOL titleChangedRecently;
@property(nonatomic, readonly) BOOL isCompact;
@property(nonatomic) NSInteger it_openingSheet;

- (NSColor *)it_terminalWindowDecorationBackgroundColor;
- (NSColor *)it_terminalWindowDecorationTextColor;
- (BOOL)it_terminalWindowUseMinimalStyle;

- (void)smartLayout;
- (void)setLayoutDone;

- (void)enableBlur:(double)radius;
- (void)disableBlur;

- (void)setRestoreState:(NSObject *)restoreState;

// Returns the approximate fraction of this window that is occluded by other windows in this app.
- (double)approximateFractionOccluded;

@end

typedef NSWindow<iTermWeaklyReferenceable, PTYWindow> iTermTerminalWindow;

// A normal terminal window.
@interface iTermWindow : NSWindow<iTermWeaklyReferenceable, PTYWindow>

@end

@interface iTermCompactWindow : NSWindow<iTermWeaklyReferenceable, PTYWindow>
@end

// A floating hotkey window. This can overlap a lion fullscreen window.
@interface iTermPanel : NSPanel<iTermWeaklyReferenceable, PTYWindow>

@end

@interface iTermCompactPanel : NSPanel<iTermWeaklyReferenceable, PTYWindow>
@end

@interface NSWindow (Private)

// Private NSWindow method, needed to avoid ghosting when using transparency.
- (BOOL)_setContentHasShadow:(BOOL)contentHasShadow;

@end

@interface NSWindow (iTermWindow)

// Returns nil if this is not a PTYWindow
- (id<PTYWindow>)ptyWindow;

@end

