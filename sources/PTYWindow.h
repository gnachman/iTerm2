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

@protocol PSMTabStyle;
@class PTYTab;
@class PTYSession;
@protocol PTYWindow;

// The key used for a window's arrangement in encoding restorable state.
extern NSString *const kTerminalWindowStateRestorationWindowArrangementKey;
extern NSString *const iTermWindowDocumentedEditedDidChange;

// Rate limit title changes since they force a redraw.
extern const NSTimeInterval iTermWindowTitleChangeMinimumInterval;

// Extra methods for delegates of terminal windows to implement.
@protocol PTYWindowDelegateProtocol<NSObject,NSWindowDelegate>
- (BOOL)lionFullScreen;
- (BOOL)anyFullScreen;
- (BOOL)terminalWindowIsEnteringLionFullScreen;
- (void)windowWillShowInitial;
- (void)toggleTraditionalFullScreenMode;
- (BOOL)terminalWindowShouldHaveTitlebarSeparator NS_AVAILABLE_MAC(10_16);

// Returns the tab a session belongs to.
- (PTYTab *)tabForSession:(PTYSession *)session;

// Should the window's frame be constrainted to its present screen?
- (BOOL)terminalWindowShouldConstrainFrameToScreen;
- (NSColor *)terminalWindowDecorationBackgroundColor;
- (NSColor *)terminalWindowDecorationTextColorForBackgroundColor:(NSColor *)backgroundColor;
- (id<PSMTabStyle>)terminalWindowTabStyle;
- (NSColor *)terminalWindowDecorationControlColor;
- (BOOL)terminalWindowUseMinimalStyle;
// This is called only for the menu item window > move to (screen name)
- (void)terminalWindowWillMoveToScreen:(NSScreen *)screen;
- (void)terminalWindowDidMoveToScreen:(NSScreen *)screen;

typedef NS_ENUM(NSUInteger, PTYWindowTitleBarFlavor) {
    PTYWindowTitleBarFlavorDefault,
    PTYWindowTitleBarFlavorOnePoint,  // One-point tall. Prevents overlapping the menu bar. Otherwise basically invisible.
    PTYWindowTitleBarFlavorZeroPoints  // Completely invisible and overlaps the menu bar.
};

- (PTYWindowTitleBarFlavor)ptyWindowTitleBarFlavor;

- (BOOL)ptyWindowIsDraggable:(id<PTYWindow>)window;
- (void)ptyWindowDidMakeKeyAndOrderFront:(id<PTYWindow>)window;
- (BOOL)toggleFullScreenShouldUseLionFullScreen;
- (void)ptyWindowMakeCurrentSessionFirstResponder;
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
@property(nonatomic, readonly) BOOL it_resizingForTiling;
@property (nonatomic) BOOL it_becomingKey;
@property (nonatomic) NSInteger it_accessibilityResizing;
@property(nonatomic) BOOL it_restorableStateInvalid;
@property(nonatomic) BOOL it_preventFrameChange;
@property(nonatomic, readonly) BOOL it_isMovingScreen;
- (NSColor *)it_terminalWindowDecorationBackgroundColor;
- (NSColor *)it_terminalWindowDecorationTextColorForBackgroundColor:(NSColor *)backgroundColor;
- (id<PSMTabStyle>)it_tabStyle;
- (NSColor *)it_terminalWindowDecorationControlColor;
- (BOOL)it_terminalWindowUseMinimalStyle;

- (void)smartLayout;
- (void)setLayoutDone;

- (void)enableBlur:(double)radius;
- (void)disableBlur;

- (void)setRestoreState:(NSObject *)restoreState;

// Returns the approximate fraction of this window that is occluded by other windows in this app.
- (double)approximateFractionOccluded;
- (void)it_setNeedsInvalidateShadow;
- (void)setUpdatingDividerLayer:(BOOL)value;
- (void)it_moveToScreen:(NSScreen *)screen;

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

// Called when a window gets resized via accessibility.
- (void)accessibilitySetSizeAttribute:(id)arg1;

@end

@interface NSWindow (iTermWindow)

// Returns nil if this is not a PTYWindow
- (id<PTYWindow>)ptyWindow;

@end

@interface NSWindow (SessionPrivate)
- (void)_moveToScreen:(NSScreen *)sender;
@end
