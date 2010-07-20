/* -*- mode:objc -*- */
/* $Id: PTYWindow.h,v 1.6 2008-09-07 21:54:44 yfabian Exp $ */
/* Incorporated into iTerm.app by Ujwal S. Setlur */
/*
 **  PTYWindow.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: NSWindow subclass. Implements transparency.
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
- (void) windowWillToggleToolbarVisibility: (id) sender;
- (void) windowDidToggleToolbarVisibility: (id) sender;
@end


@interface PTYWindow : NSWindow 
{
	IBOutlet NSDrawer *drawer;

	int blurFilter;
	BOOL layoutDone;
}

- initWithContentRect:(NSRect)contentRect 
            styleMask:(unsigned int)aStyle 
	      backing:(NSBackingStoreType)bufferingType 
		defer:(BOOL)flag;

- (void)toggleToolbarShown:(id)sender;

- (NSDrawer *) drawer;
- (void) setDrawer: (NSDrawer *) aDrawer;

- (void)smartLayout;
- (void)setLayoutDone;

- (void)enableBlur;
- (void)disableBlur;

- (int)screenNumber;

@end

