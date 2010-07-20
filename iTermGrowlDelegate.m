// -*- mode:objc -*- vim: filetype=objcpp
// $Id: iTermGrowlDelegate.m,v 1.10 2006-10-09 22:24:52 yfabian Exp $
//
/*
 **  iTermGrowlDelegate.m
 **
 **  Copyright (c) 2006
 **
 **  Author: David E. Nedrow
 **
 **  Project: iTerm
 **
 **  Description: Implements the delegate for Growl notifications.
 **               See iTermGrowlDelegate.h for usage information.
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

#import <iTermGrowlDelegate.h>
#import <PreferencePanel.h>

/**
 **  The category is used to extend iTermGrowlDelegate with private methods.
 **
 **  Any methods that should not be exposed to the 'outside world' by being
 **  included in the class header file should be declared here and implemented
 **  in @implementation.
 */
@interface
	iTermGrowlDelegate (PrivateMethods )

  // - (void) examplePrivateMethodDeclaration;
@end

@implementation iTermGrowlDelegate

+ (id) sharedInstance {
	static iTermGrowlDelegate* shared = nil;
	if(!shared)
		shared = [iTermGrowlDelegate new];
	return shared;
}

- (id) init {
	if ((self = [super init])) {

		notifications = [[NSArray arrayWithObjects: 
			OURNOTIFICATIONS,
			nil] retain];

		[GrowlApplicationBridge setGrowlDelegate: self];
		[self registrationDictionaryForGrowl];
		[self setEnabled: YES];
        
		return self;
	} else {
		return nil;
	}
}

- (void) dealloc {
    [notifications release];
	[super dealloc];
}

- (BOOL) isEnabled {
	if ([GrowlApplicationBridge isGrowlInstalled]) {
		return enabled;
	} else {
		return NO;
	}
}

- (void) setEnabled: (BOOL) newState {
	enabled = newState;
}

- (void) growlNotify: (NSString *) title {

	if(![self isEnabled]) {
		//NSLog(@"%s(%d):-[Growl not enabled.]",  __FILE__, __LINE__);
		return;
	}

    if ([[PreferencePanel sharedInstance] enableGrowl])
        [GrowlApplicationBridge 
            notifyWithTitle: title
                description: nil
           notificationName: DEFAULTNOTIFICATION
                   iconData: nil
                   priority: 0
                   isSticky: NO
               clickContext: nil];
}

- (void) growlNotify: (NSString *) title 
	 withDescription: (NSString *) description {

	if(![self isEnabled]) {
		//NSLog(@"%s(%d):-[Growl not enabled.]",  __FILE__, __LINE__);
		return;
	}
	
    if ([[PreferencePanel sharedInstance] enableGrowl])
        [GrowlApplicationBridge 
            notifyWithTitle: title
                description: description
           notificationName: DEFAULTNOTIFICATION
                   iconData: nil
                   priority: 0
                   isSticky: NO
               clickContext: nil];
}

- (void) growlNotify: (NSString *) title 
	 withDescription: (NSString *) description 
	 andNotification: (NSString *) notification {

	if(![self isEnabled]) {
		//NSLog(@"%s(%d):-[Growl not enabled.]",  __FILE__, __LINE__);
		return;
	}
    
    if ([[PreferencePanel sharedInstance] enableGrowl])
        [GrowlApplicationBridge 
            notifyWithTitle: title
                description: description
           notificationName: notification
                   iconData: nil
                   priority: 0
                   isSticky: NO
               clickContext: nil];
}

- (NSDictionary *) registrationDictionaryForGrowl {
	
	NSDictionary *regDict = [NSDictionary dictionaryWithObjectsAndKeys:
		OURGROWLAPPNAME, GROWL_APP_NAME,
		notifications, GROWL_NOTIFICATIONS_ALL,
		notifications, GROWL_NOTIFICATIONS_DEFAULT,
		nil];
	
	return regDict;
}

@end
