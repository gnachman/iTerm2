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

@protocol PTYWindowDelegateProtocol
- (void)windowWillToggleToolbarVisibility:(id)sender;
- (void)windowDidToggleToolbarVisibility:(id)sender;
- (BOOL)lionFullScreen;
@end

// See http://www.google.com/search?sourceid=chrome&ie=UTF-8&q=_setContentHasShadow
// Solves bug 299 (ghosting of contents with highly transparent windows--the window's
// views cast a shadow, and the window shadow gets messed up, which you can see through
// the transparent window.) but causes bug 2925 (artifacts in the corners).
@interface NSWindow (NSWindowPrivate)  // private method
- (void)_setContentHasShadow:(BOOL)shadow;
@end

@interface PTYWindow : NSWindow

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag;

- (void)toggleToolbarShown:(id)sender;

- (void)smartLayout;
- (void)setLayoutDone;

- (void)enableBlur:(double)radius;
- (void)disableBlur;

- (int)screenNumber;
- (BOOL)isTogglingLionFullScreen;

- (void)setRestoreState:(NSObject *)restoreState;

// Returns the approximate fraction of this window that is occluded by other windows in this app.
- (double)approximateFractionOccluded;

@end

