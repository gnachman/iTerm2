/*
 **  iTermNotificationController.h
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for notifications using Notification Center.
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
 **          withDescription: @"This is the description"];
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

@interface iTermNotificationController : NSObject <
  NSUserNotificationCenterDelegate>

+ (instancetype)sharedInstance;

// Generate a message with no description.
- (void)notify:(NSString *)title;

//  Generate a 'full' message with a specified notification type.
- (void)notify:(NSString *)title
    withDescription:(NSString *)description;

// Generate a 'full' message with a specified notification type,
// associated with a particular window/tab/view.
//
// Returns YES if the notification was posted.
- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex;

// Generate a notification with all possible fields.
// title, subtitle, and image file are all optional
// and can be nil.  The description argument must
// not be nil, but can be the empty string.
//
// Returns YES if the notification was posted.
- (BOOL)notifyRich:(NSString *)title
      withSubtitle:(NSString *)subtitle
   withDescription:(NSString *)description
         withImage:(NSString *)image
       windowIndex:(int)windowIndex
          tabIndex:(int)tabIndex
         viewIndex:(int)viewIndex;

// Adds the sticky argument.
- (BOOL)notify:(NSString *)title
    withDescription:(NSString *)description
        windowIndex:(int)windowIndex
           tabIndex:(int)tabIndex
          viewIndex:(int)viewIndex
             sticky:(BOOL)sticky;

- (void)postNotificationWithTitle:(NSString *)title
                           detail:(NSString *)detail
                              URL:(NSURL *)url;

- (void)postNotificationWithTitle:(NSString *)title
                           detail:(NSString *)detail
         callbackNotificationName:(NSString *)name
     callbackNotificationUserInfo:(NSDictionary *)userInfo;

- (void)postNotificationWithTitle:(NSString *)title
                           detail:(NSString *)detail
         callbackNotificationName:(NSString *)name
     callbackNotificationUserInfo:(NSDictionary *)userInfo
                actionButtonTitle:(NSString *)actionButtonTitle;

@end
