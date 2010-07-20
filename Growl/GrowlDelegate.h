//
//  GrowlDelegate.h
//  Growl
//
//  Created by Ingmar Stein on 16.04.05.
//  Copyright 2004-2005 The Growl Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GrowlApplicationBridge.h"

/*
 * A convenience class for applications which don't need feedback from
 * Growl (e.g. growlIsReady or growlNotificationWasClicked). It can also be used
 * with scripting languages such as F-Script (http://www.fscript.org).
 */
@interface GrowlDelegate : NSObject <GrowlApplicationBridgeDelegate> {
	NSDictionary	*registrationDictionary;
	NSString		*applicationNameForGrowl;
	NSData			*applicationIconDataForGrowl;
}
- (id) initWithAllNotifications:(NSArray *)allNotifications defaultNotifications:(NSArray *)defaultNotifications;
- (NSDictionary *) registrationDictionaryForGrowl;
- (NSString *) applicationNameForGrowl;
- (void) setApplicationNameForGrowl:(NSString *)name;
- (NSData *) applicationIconDataForGrowl;
- (void) setApplicationIconDataForGrowl:(NSData *)data;

@end
