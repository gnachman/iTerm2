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
 **				  are handled properly.
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


@implementation iTermApplication

// override to catch key press events very early on
- (void)sendEvent:(NSEvent*)event
{
	if([event type] == NSKeyDown) {
		if([[self keyWindow] isKindOfClass:[PTYWindow class]]) {
			PseudoTerminal* currentTerminal = [[iTermController sharedInstance] currentTerminal];
			PTYTabView* tabView = [currentTerminal tabView];
			PTYSession* currentSession = [currentTerminal currentSession];

			if(([event modifierFlags] & 0xffff0000) == NSCommandKeyMask) {
				int digit = [[event charactersIgnoringModifiers] intValue];
				if(digit >= 1 && digit <= [tabView numberOfTabViewItems]) {
					[tabView selectTabViewItemAtIndex:digit-1];
					return;
				}
			}

			if([currentSession hasKeyMappingForEvent:event highPriority:YES]) {
				[currentSession keyDown:event];
				return;
			}
		}
	}

	[super sendEvent: event];
}

@end

