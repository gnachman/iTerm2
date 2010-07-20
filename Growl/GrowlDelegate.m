//
//  GrowlDelegate.m
//  Growl
//
//  Created by Ingmar Stein on 16.04.05.
//  Copyright 2004-2005 The Growl Project. All rights reserved.
//

#import "GrowlDelegate.h"

@implementation GrowlDelegate
- (id) initWithAllNotifications:(NSArray *)allNotifications defaultNotifications:(NSArray *)defaultNotifications {
	if ((self = [super init])) {
		registrationDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
			allNotifications,     GROWL_NOTIFICATIONS_ALL,
			defaultNotifications, GROWL_NOTIFICATIONS_DEFAULT,
			nil];
	}
	return self;
}

- (void) dealloc {
	[registrationDictionary      release];
	[applicationNameForGrowl     release];
	[applicationIconDataForGrowl release];
	[super dealloc];
}

- (NSDictionary *) registrationDictionaryForGrowl {
	return registrationDictionary;
}

- (NSString *) applicationNameForGrowl {
	return applicationNameForGrowl;
}

- (void) setApplicationNameForGrowl:(NSString *)name {
	if (name != applicationNameForGrowl) {
		[applicationNameForGrowl release];
		applicationNameForGrowl = [name retain];
	}
}

- (NSData *) applicationIconDataForGrowl {
	return applicationIconDataForGrowl;
}

- (void) setApplicationIconDataForGrowl:(NSData *)data {
	if (data != applicationIconDataForGrowl) {
		[applicationIconDataForGrowl release];
		applicationIconDataForGrowl = [data retain];
	}
}

@end
