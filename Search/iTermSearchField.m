// -*- mode:objc -*-                                                                     
/*                                                                                       
 **  iTermSearchField.m
 **                                                                                      
 **  Copyright (c) 2011                                                                  
 **                                                                                      
 **  Author: George Nachman                                                              
 **                                                                                      
 **  Project: iTerm2                                                                     
 **                                                                                      
 **  Description: Subclass of NSSearchField that delegates up/down arrows to
 **   another class.                                                                   
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
#import "iTermSearchField.h"


@implementation iTermSearchField

- (void)setArrowHandler:(id)handler
{
    arrowHandler_ = handler;
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
    unsigned int modflag;
    unsigned short keycode;
    modflag = [theEvent modifierFlags];
    keycode = [theEvent keyCode];
    
    const int mask = NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask;
    // TODO(georgen): Not getting normal keycodes here, but 125 and 126 are up and down arrows.
    // This is a pretty ugly hack. Also, calling keyDown from here is probably not cool.
    BOOL handled = NO;
    if (!(mask & modflag) && (keycode == 125 || keycode == 126)) {
        [arrowHandler_ keyDown:theEvent];
        handled = YES;
        
    } else {
        handled = [super performKeyEquivalent:theEvent];
    }
    return handled;
}

@end
