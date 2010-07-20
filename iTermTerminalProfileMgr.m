/*
 **  iTermTerminalProfileMgr.m
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Tianming Yang
 **
 **  Project: iTerm
 **
 **  Description: terminal profile manager.
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


#import "ITAddressBookMgr.h"
#import <iTerm/iTermTerminalProfileMgr.h>

static iTermTerminalProfileMgr *singleInstance = nil;

@implementation iTermTerminalProfileMgr

// Class methods
+ (id) singleInstance
{
	if(singleInstance == nil)
	{
		singleInstance = [[iTermTerminalProfileMgr alloc] init];
	}
	
	return (singleInstance);
}

// Instance methods
- (id) init
{
	self = [super init];

	if(!self)
	return (nil);

	profiles = [[NSMutableDictionary alloc] init];

	return (self);
}

- (void) dealloc
{
	[profiles release];
	[super dealloc];
}

- (NSDictionary *) profiles
{
	return (profiles);
}

- (void) setProfiles: (NSMutableDictionary *) aDict
{
	NSEnumerator *keyEnumerator;
	NSMutableDictionary *mappingDict;
	NSString *profileName;
	NSDictionary *sourceDict;
	
	// recursively copy the dictionary to ensure mutability
	if(aDict != nil)
	{
		keyEnumerator = [aDict keyEnumerator];
		while((profileName = [keyEnumerator nextObject]) != nil)
		{
			sourceDict = [aDict objectForKey: profileName];
			mappingDict = [[NSMutableDictionary alloc] initWithDictionary: sourceDict];
			[profiles setObject: mappingDict forKey: profileName];
			[mappingDict release];
		}		
	}
    else  // if we don't have any profile, create a default profile
	{
		NSMutableDictionary *aProfile;
		NSString *defaultName;
		
		defaultName = NSLocalizedStringFromTableInBundle(@"Default",@"iTerm", [NSBundle bundleForClass: [self class]],
														 @"Terminal Profiles");
		
		
		aProfile = [[NSMutableDictionary alloc] init];
		[profiles setObject: aProfile forKey: defaultName];
		[aProfile release];
		
		[aProfile setObject: @"Yes" forKey: @"Default Profile"];
		
		[self setType: @"xterm" forProfile: defaultName];
		[self setEncoding: NSUTF8StringEncoding forProfile: defaultName];
		[self setScrollbackLines: 1000 forProfile: defaultName];
		[self setSilenceBell: NO forProfile: defaultName];
		[self setBlinkCursor: NO forProfile: defaultName];
		[self setCloseOnSessionEnd: YES forProfile: defaultName];
		[self setDoubleWidth: YES forProfile: defaultName];
		[self setSendIdleChar: NO forProfile: defaultName];
		[self setIdleChar: 0 forProfile: defaultName];
	
	}
}

- (NSString *) defaultProfileName
{
	NSDictionary *aProfile;
	NSEnumerator *keyEnumerator;
	NSString *aKey, *aProfileName;
	
	keyEnumerator = [profiles keyEnumerator];
	aProfileName = nil;
	while ((aKey = [keyEnumerator nextObject]))
	{
		aProfile = [profiles objectForKey: aKey];
		if([self isDefaultProfile: aKey])
		{
			aProfileName = aKey;
			break;
		}
	}
	
	return (aProfileName);
}

- (void) addProfileWithName: (NSString *) newProfile copyProfile: (NSString *) sourceProfile
{
	NSMutableDictionary *aMutableDict, *aProfile;
	
	if([sourceProfile length] > 0 && [newProfile length] > 0)
	{
		aProfile = [profiles objectForKey: sourceProfile];
		aMutableDict = [[NSMutableDictionary alloc] initWithDictionary: aProfile];
		[aMutableDict removeObjectForKey: @"Default Profile"];
		[profiles setObject: aMutableDict forKey: newProfile];
		[aMutableDict release];
	}
}

- (void) deleteProfileWithName: (NSString *) profileName
{
	
	if([profileName length] <= 0)
		return;
	
	[self updateBookmarkProfile: profileName with:@"Default"];
	[profiles removeObjectForKey: profileName];
}

- (BOOL) isDefaultProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	
	return ([[aProfile objectForKey: @"Default Profile"] isEqualToString: @"Yes"]);
}


- (NSString *) typeForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;

	if([profileName length] <= 0)
		return (nil);

	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (nil);
		
	return ([aProfile objectForKey: @"Term Type"]);	
}

- (void) setType: (NSString *) type forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0 || [type length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: type forKey: @"Term Type"];	
}

- (NSStringEncoding) encodingForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *encoding;
	
	if([profileName length] <= 0)
		return (NSUTF8StringEncoding);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (NSUTF8StringEncoding);
	
	encoding = [aProfile objectForKey: @"Encoding"];
	if(encoding == nil)
		return (NSUTF8StringEncoding);
	
	return ([encoding unsignedIntValue]);	
	
}

- (void) setEncoding: (NSStringEncoding) encoding forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithUnsignedInt: (unsigned int) encoding] forKey: @"Encoding"];	
}


- (int) scrollbackLinesForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *lines;

	if([profileName length] <= 0)
	return (0);

	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
	return (0);

	lines = [aProfile objectForKey: @"Scrollback"];
	if(lines == nil)
	return (0);

	return ([lines unsignedIntValue]);	
}

- (void) setScrollbackLines: (int) lines forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithInt: (lines < 0 ? -1 : lines)] forKey: @"Scrollback"];	
}


- (BOOL) silenceBellForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *silent;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (NO);
	
	silent = [aProfile objectForKey: @"Silence Bell"];
	if(silent == nil)
		return (NO);
	
	return ([silent boolValue]);	
}

- (void) setSilenceBell: (BOOL) silent forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: silent] forKey: @"Silence Bell"];	
}

- (BOOL) showBellForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *showBell;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (NO);
	
	showBell = [aProfile objectForKey: @"Show Bell"];
	if(showBell == nil)
		return (YES);
	
	return ([showBell boolValue]);	
}

- (void) setShowBell: (BOOL) showBell forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: showBell] forKey: @"Show Bell"];	
}

- (BOOL) growlForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *growl;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (NO);
	
	growl = [aProfile objectForKey: @"Growl"];
	if(growl == nil)
		return (YES);
	
	return ([growl boolValue]);	
}

- (void) setGrowl: (BOOL) growl forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: growl] forKey: @"Growl"];	
}


- (BOOL) blinkCursorForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *blink;
	
	if([profileName length] <= 0)
		return (YES);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (YES);
	
	blink = [aProfile objectForKey: @"Blink"];
	if(blink == nil)
		return (YES);
	
	return ([blink boolValue]);	
}

- (void) setBlinkCursor: (BOOL) blink forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: blink] forKey: @"Blink"];	
}


- (BOOL) closeOnSessionEndForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *close;
	
	if([profileName length] <= 0)
		return (YES);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (YES);
	
	close = [aProfile objectForKey: @"Auto Close"];
	if(close == nil)
		return (YES);
	
	return ([close boolValue]);	
}

- (void) setCloseOnSessionEnd: (BOOL) close forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: close] forKey: @"Auto Close"];	
}


- (BOOL) doubleWidthForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *doubleWidth;
	
	if([profileName length] <= 0)
		return (YES);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (YES);
	
	doubleWidth = [aProfile objectForKey: @"Double Width"];
	if(doubleWidth == nil)
		return (YES);
	
	return ([doubleWidth boolValue]);	
}

- (void) setDoubleWidth: (BOOL) doubleWidth forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: doubleWidth] forKey: @"Double Width"];	
}


- (BOOL) sendIdleCharForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *send;
	
	if([profileName length] <= 0)
		return (YES);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (YES);
	
	send = [aProfile objectForKey: @"Send Idle Char"];
	if(send == nil)
		return (YES);
	
	return ([send boolValue]);	
}

- (void) setSendIdleChar: (BOOL) send forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: send] forKey: @"Send Idle Char"];	
}


- (char) idleCharForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *idleChar;
	
	if([profileName length] <= 0)
		return (0);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (0);
	
	idleChar = [aProfile objectForKey: @"Idle Char"];
	if(idleChar == nil)
		return (0);
	
	return ([idleChar unsignedIntValue]);	
}

- (void) setIdleChar: (char) idle forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithChar: idle] forKey: @"Idle Char"];	
}

- (BOOL) xtermMouseReportingForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *xtermMouseReporting;
	
	if([profileName length] <= 0)
		return (YES);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (YES);
	
	xtermMouseReporting = [aProfile objectForKey: @"Xterm Mouse Reporting"];
	if(xtermMouseReporting == nil)
		return (YES);
	
	return ([xtermMouseReporting boolValue]);	
}

- (void) setXtermMouseReporting: (BOOL) xtermMouseReporting forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: xtermMouseReporting] forKey: @"Xterm Mouse Reporting"];	
}

- (BOOL) appendTitleForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *appendTitle;
	
	if([profileName length] <= 0)
		return (YES);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (NO);
	
	appendTitle = [aProfile objectForKey: @"Append Title"];
	if(appendTitle == nil)
		return (NO);
	
	return ([appendTitle boolValue]);	
}

- (void) setAppendTitle: (BOOL) appendTitle forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: appendTitle] forKey: @"Append Title"];	
}

- (BOOL) noResizingForProfile: (NSString *) profileName
{
	NSDictionary *aProfile;
	NSNumber *noResizing;
	
	if([profileName length] <= 0)
		return (NO);
	
	aProfile = [profiles objectForKey: profileName];
	if(aProfile == nil)
		return (NO);
	
	noResizing = [aProfile objectForKey: @"No Resizing"];
	if(noResizing == nil)
		return (NO);
	
	return ([noResizing boolValue]);	
}

- (void) setNoResizing: (BOOL) noResizing forProfile: (NSString *) profileName
{
	NSMutableDictionary *aProfile;
	
	if([profileName length] <= 0)
		return;
	
	aProfile = [profiles objectForKey: profileName];
	
	if(aProfile == nil)
		return;
	
	[aProfile setObject: [NSNumber numberWithBool: noResizing] forKey: @"No Resizing"];	
}

- (void) updateBookmarkNode: (TreeNode *)node forProfile: (NSString*) oldProfile with:(NSString*)newProfile
{
	int i;
	TreeNode *child;
	NSDictionary *aDict;
	int n = [node numberOfChildren];
	
	for (i=0;i<n;i++) {
		child = [node childAtIndex:i];
		if ([child isLeaf]) {
			aDict = [child nodeData];
			if ([[aDict objectForKey:KEY_TERMINAL_PROFILE] isEqualToString: oldProfile]) {
				NSMutableDictionary *newBookmark= [[NSMutableDictionary alloc] initWithDictionary: aDict];
				[newBookmark setObject: newProfile forKey: KEY_TERMINAL_PROFILE];
				[child setNodeData: newBookmark];
				[newBookmark release];
			}
		}
		else {
			[self updateBookmarkNode: child forProfile: oldProfile with:newProfile];
		}
	}
}

- (void) updateBookmarkProfile: (NSString*) oldProfile with:(NSString*)newProfile
{
	[self updateBookmarkNode: [[ITAddressBookMgr sharedInstance] rootNode] forProfile: oldProfile with:newProfile];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}


@end
