/*
 **  iTermNotificationController.h
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for notifications. When available
 **      Notification Center is used either as a fallback from Growl or
 **      directly (if the corresponding advanced setting is turned on).
 **
 **  Usage:
 **      In your class header file, add the following @class directive
 **
 **          @class iTermNotificationController;
 **
 **      and declare an iTermNotificationController variable in the @interface
 **
 **          iTermNotificationController* gd;
 **
 **      In your class implementation file, add the following import
 **
 **          #import "iTermNotificationController.h"
 **
 **      In the class init, get a copy of the shared delegate
 **
 **          gd = [iTermNotificationController sharedInstance];
 **
 **      There are several notify methods in iTermNotificationController.
 **      See the header file for details.
 **
 **      Example usage:
 **
 **          [gd notify: @"This is the title"
 **          withDescription: @"This is the description"
 **          andNotification: @"Bells"];
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

#ifndef ITERM_LIB
#import <Growl/Growl.h>
#endif

@interface iTermNotificationController : NSObject <
#ifndef ITERM_LIB
  GrowlApplicationBridgeDelegate,
#endif
  NSUserNotificationCenterDelegate>

+ (instancetype)sharedInstance;

// Generate a message with no description and a Growl notification type
// of "Miscellaneous".
- (void)notify:(NSString *)title;

// Generate a message with a Growl notification type of "Miscellaneous".
- (void)notify:(NSString *)title withDescription:(NSString *)description;

//  Generate a 'full' message with a specified notification type.
- (void)notify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification;

// Generate a 'full' message with a specified notification type,
// associated with a particular window/tab/view.
//
// Returns YES if the notification was posted.
- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex;

// Adds the sticky argument.
- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex
             sticky:(BOOL)sticky;

@end
