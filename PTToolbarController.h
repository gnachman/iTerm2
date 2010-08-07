/*
 **  PTToolbarController.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: manages an the toolbar.
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

extern NSString *NewToolbarItem;
extern NSString *ABToolbarItem;
extern NSString *CloseToolbarItem;
extern NSString *ConfigToolbarItem;
extern NSString *CommandToolbarItem;

@class PseudoTerminal;

@interface PTToolbarController : NSObject 
{
    NSToolbar* _toolbar;
    PseudoTerminal* _pseudoTerminal;
}

- (id)initWithPseudoTerminal:(PseudoTerminal*)terminal;

@end
