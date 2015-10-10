// -*- mode:objc -*- vim: filetype=objcpp:
// $Id: iTermGrowlDelegate.h,v 1.7 2006-09-21 00:55:10 yfabian Exp $
//
/*
 **  iTermGrowlDelegate.h
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for Growl notifications. When
 **      available, Notifiation Center is used as a fallback.
 **
 **  Usage:
 **      In your class header file, add the following @class directive
 **
 **          @class iTermGrowlDelegate;
 **
 **      and declare an iTermGrowlDelegate variable in the @interface
 **
 **          iTermGrowlDelegate* gd;
 **
 **      In your class implementation file, add the following import
 **
 **          #import "iTermGrowlDelegate.h"
 **
 **      In the class init, get a copy of the shared delegate
 **
 **          gd = [iTermGrowlDelegate sharedInstance];
 **
 **      There are several growlNotify methods in iTermGrowlDelegate.
 **      See the header file for details.
 **
 **      Example usage:
 **
 **          [gd growlNotify: @"This is the title"
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
#import <Growl/Growl.h>

@interface iTermGrowlDelegate : NSObject <
  GrowlApplicationBridgeDelegate,
  NSUserNotificationCenterDelegate>

+ (instancetype)sharedInstance;

// Generate a Growl message with no description and a notification type
// of "Miscellaneous".
- (void)growlNotify:(NSString *)title;

// Generate a Growl message with a notification type of "Miscellaneous".
- (void)growlNotify:(NSString *)title withDescription:(NSString *)description;

//  Generate a 'full' Growl message with a specified notification type.
- (void)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification;

// Generate a 'full' Growl message with a specified notification type,
// associated with a particular window/tab/view.
//
// Returns YES if the notification was posted.
- (BOOL)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex;

// Adds the sticky argument. Only works with Growl, not notification center.
- (BOOL)growlNotify:(NSString *)title
    withDescription:(NSString *)description
    andNotification:(NSString *)notification
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex
             sticky:(BOOL)sticky;

@end
