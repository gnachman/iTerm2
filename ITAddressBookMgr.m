
/*
 **  ITAddressBookMgr.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: keeps track of the address book data.
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

#import <iTerm/PreferencePanel.h>
#import <iTerm/Tree.h>
#import <iTerm/iTermTerminalProfileMgr.h>
#import <iTerm/iTermKeyBindingMgr.h>
#import <iTerm/iTermDisplayProfileMgr.h>
#include <netinet/in.h>
#include <arpa/inet.h>


#define SAFENODE(n) 		((TreeNode*)((n)?(n):(bookmarks)))

static NSString* ADDRESS_BOOK_FILE = @"~/Library/Application Support/iTerm/AddressBook";


static TreeNode *defaultBookmark = nil;

@implementation ITAddressBookMgr

+ (id)sharedInstance;
{
    static ITAddressBookMgr* shared = nil;
    
    if (!shared)
        shared = [[ITAddressBookMgr alloc] init];
    
    return shared;
}

- (id)init;
{
    self = [super init];
    	
    return self;
}

- (void)dealloc;
{
	[bookmarks release];
	[bonjourGroup release];	
	[bonjourServices removeAllObjects];
	[bonjourServices release];
	
	[sshBonjourBrowser stop];
	[ftpBonjourBrowser stop];
	[telnetBonjourBrowser stop];	
	[sshBonjourBrowser release];
	[ftpBonjourBrowser release];
	[telnetBonjourBrowser release];
	
    [super dealloc];
}

- (void) locateBonjourServices
{
	sshBonjourBrowser = [[NSNetServiceBrowser alloc] init];
	ftpBonjourBrowser = [[NSNetServiceBrowser alloc] init];
	telnetBonjourBrowser = [[NSNetServiceBrowser alloc] init];
	
	bonjourServices = [[NSMutableArray alloc] init];
	
	[sshBonjourBrowser setDelegate: self];
	[ftpBonjourBrowser setDelegate: self];
	[telnetBonjourBrowser setDelegate: self];
	[sshBonjourBrowser searchForServicesOfType: @"_ssh._tcp." inDomain: @""];
	[ftpBonjourBrowser searchForServicesOfType: @"_ftp._tcp." inDomain: @""];
	[telnetBonjourBrowser searchForServicesOfType: @"_telnet._tcp." inDomain: @""];		
	
}

- (void) setBookmarks: (NSDictionary *) aDict
{
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aDict);
	[bookmarks release];
	bookmarks = [TreeNode treeFromDictionary: aDict];
	[bookmarks setIsLeaf: NO];
	[bookmarks retain];
	
	// make sure we have a default bookmark
	if([self _checkForDefaultBookmark: bookmarks defaultBookmark: &defaultBookmark] == NO)
	{
		NSMutableDictionary *aDict;
		char *userShell, *thisUser;
		NSString *shell;
		NSString *aName;
		TreeNode *childNode;
				
		aDict = [[NSMutableDictionary alloc] init];
		
		// Get the user's default shell
		if((thisUser = getenv("USER")) != NULL) {
			shell = [NSString stringWithFormat: @"login -fp %s", thisUser];
		} else if((userShell = getenv("SHELL")) != NULL) {
			shell = [NSString stringWithCString: userShell];
		} else {
			shell = @"/bin/bash --login";
		}
		
		aName = NSLocalizedStringFromTableInBundle(@"Default",@"iTerm", [NSBundle bundleForClass: [self class]],
												   @"Terminal Profiles");
		[aDict setObject: aName forKey: KEY_NAME];
		[aDict setObject: shell forKey: KEY_COMMAND];
		[aDict setObject: shell forKey: KEY_DESCRIPTION];
		[aDict setObject: NSHomeDirectory() forKey: KEY_WORKING_DIRECTORY];
		[aDict setObject: [[iTermTerminalProfileMgr singleInstance] defaultProfileName] forKey: KEY_TERMINAL_PROFILE];
		[aDict setObject: [[iTermKeyBindingMgr singleInstance] globalProfileName] forKey: KEY_KEYBOARD_PROFILE];
		[aDict setObject: [[iTermDisplayProfileMgr singleInstance] defaultProfileName] forKey: KEY_DISPLAY_PROFILE];
		[aDict setObject: @"Yes" forKey: KEY_DEFAULT_BOOKMARK];

		childNode = [[TreeNode alloc] initWithData: aDict parent: nil children: [NSArray array]];
		[childNode setIsLeaf: YES];
		[bookmarks insertChild: childNode atIndex: [bookmarks numberOfChildren]];
		[aDict release];
		[childNode release];
		
		defaultBookmark = childNode;
		
	}
	
	// add any bonjour services if we have any
	if([bonjourGroup numberOfChildren] > 0)
	{
		[bookmarks insertChild: bonjourGroup atIndex: [bookmarks numberOfChildren]];
	}	

    //[bookmarks recursiveSortChildren];
}

- (NSDictionary *) bookmarks
{
	NSDictionary *aDict;
	int anIndex;
	
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	
	// remove bonjour group since we do not want to save that
	anIndex = [[bookmarks children] indexOfObject: bonjourGroup];
	[bonjourGroup retain];
	[bookmarks  removeChild: bonjourGroup];	
	aDict = [bookmarks dictionary];
	if(anIndex != NSNotFound)
		[bookmarks insertChild: bonjourGroup atIndex: anIndex];	
	[bonjourGroup release];
	
	return (aDict);
}

- (BOOL) mayDeleteBookmarkNode: (TreeNode *) aNode
{
	BOOL mayDeleteNode = YES;
	
	if([defaultBookmark isDescendantOfNode: aNode])
		mayDeleteNode = NO;
	
	if([aNode isDescendantOfNode: bonjourGroup])
		mayDeleteNode = NO;
	
	return (mayDeleteNode);
}

// Model for NSOutlineView tree structure

- (id) child:(int)index ofItem:(id)item
{	
	return ([SAFENODE(item) childAtIndex: index]);
}

- (BOOL) isExpandable:(id)item
{
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, item);
	return (![SAFENODE(item) isLeaf]);
}

- (int) numberOfChildrenOfItem:(id)item
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	return ([SAFENODE(item) numberOfChildren]);
}

- (id) objectForKey: (id) key inItem: (id) item
{	
	NSDictionary *data = [SAFENODE(item) nodeData];
	
	return ([data objectForKey: key]);
}

- (void) setObjectValue: (id) object forKey: (id) key inItem: (id) item
{
	NSMutableDictionary *aDict;
	
	aDict = [[NSMutableDictionary alloc] initWithDictionary: [SAFENODE(item) nodeData]];
	[aDict setObject: object forKey: key];
	[SAFENODE(item) setNodeData: aDict];
	[aDict release];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (void) addFolder: (NSString *) folderName toNode: (TreeNode *) aNode
{
	TreeNode *targetNode, *childNode;
	NSMutableDictionary *aDict;
	
	// NSLog(@"%s: %@", __PRETTY_FUNCTION__, folderName);
	
	targetNode = SAFENODE(aNode);
	
	aDict = [[NSMutableDictionary alloc] init];
	[aDict setObject: folderName forKey: KEY_NAME];
	[aDict setObject: @"" forKey: KEY_DESCRIPTION];
	
	childNode = [[TreeNode alloc] initWithData: aDict parent: nil children: [NSArray array]];
	[childNode setIsLeaf: NO];
	[targetNode insertChild: childNode atIndex: [targetNode numberOfChildren]];
	[aDict release];
	[childNode release];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (void) addBookmarkWithData: (NSDictionary *) data toNode: (TreeNode *) aNode;
{
	TreeNode *targetNode, *childNode;
	NSMutableDictionary *aDict;
		
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	
	if(data == nil)
		return;
	
	targetNode = SAFENODE(aNode);
	
	aDict = [[NSMutableDictionary alloc] initWithDictionary: data];
	
	childNode = [[TreeNode alloc] initWithData: aDict parent: nil children: [NSArray array]];
	[childNode setIsLeaf: YES];
	[targetNode insertChild: childNode atIndex: [targetNode numberOfChildren]];
	[aDict release];
	[childNode release];
	

	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (void) setBookmarkWithData: (NSDictionary *) data forNode: (TreeNode *) aNode
{
	NSMutableDictionary *aDict;
	
	aDict = [[NSMutableDictionary alloc] initWithDictionary: [SAFENODE(aNode) nodeData]];
	[aDict addEntriesFromDictionary: data];
	[SAFENODE(aNode) setNodeData: aDict];
	[aDict release];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (void) deleteBookmarkNode: (TreeNode *) aNode
{
	[aNode removeFromParent];
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		
}

- (TreeNode *) rootNode
{
	return (bookmarks);
}

- (TreeNode *) defaultBookmark
{
	return (defaultBookmark);
}

- (void) setDefaultBookmark: (TreeNode *) aNode
{
	NSMutableDictionary *aMutableDict;
	
	if(aNode == nil)
		return;
	
	// get the current default bookmark
	aMutableDict = [NSMutableDictionary dictionaryWithDictionary: [defaultBookmark nodeData]];
	[aMutableDict removeObjectForKey: KEY_DEFAULT_BOOKMARK];
	[defaultBookmark setNodeData: aMutableDict];
	
	// set the new default bookmark
	aMutableDict = [NSMutableDictionary dictionaryWithDictionary: [aNode nodeData]];
	[aMutableDict setObject: @"Yes" forKey: KEY_DEFAULT_BOOKMARK];
	[aNode setNodeData: aMutableDict];
	defaultBookmark = aNode;
	
}

- (NSDictionary *) defaultBookmarkData
{
	return ([defaultBookmark nodeData]);
}

- (NSDictionary *) dataForBookmarkWithName: (NSString *) bookmarkName
{
	NSArray *pathComponents;
	NSEnumerator *anEnumerator;
	NSString *aPathComponent;
	TreeNode *theNode;
	NSDictionary *theData;
	
	// break up into path components
	pathComponents = [bookmarkName componentsSeparatedByString: @"/"];
	anEnumerator = [pathComponents objectEnumerator];
	theNode = bookmarks;
	while((aPathComponent = [anEnumerator nextObject]) != NULL && theNode != NULL)
	{
		theNode = [self _getBookmarkNodeWithName: aPathComponent searchFromNode: theNode];
	}
	if([theNode isGroup])
		theData = nil;
	else
		theData = [theNode nodeData];
	
	return (theData);
}

// migrate any old bookmarks in the old format we might have
- (void) migrateOldBookmarks
{
	NSMutableArray *_addressBookArray = [[NSUnarchiver unarchiveObjectWithFile: [ADDRESS_BOOK_FILE stringByExpandingTildeInPath]] retain];
	NSDictionary *_adEntry;
	NSMutableDictionary *aBookmarkData;
	int i;
	NSFileManager *fileManager;
	TreeNode *childNode;
	NSString *shortcut;
	
	for (i = 0; i < [_addressBookArray count]; i++)
	{
		_adEntry = [_addressBookArray objectAtIndex: i];
		
		// add all entries except for default entry
		if([[_adEntry objectForKey:@"DefaultEntry"] boolValue] == NO)
		{
			aBookmarkData = [[NSMutableDictionary alloc] init];
			[aBookmarkData setObject: [_adEntry objectForKey: @"Name"] forKey: KEY_NAME];
			[aBookmarkData setObject: [_adEntry objectForKey: @"Command"] forKey: KEY_DESCRIPTION];
			[aBookmarkData setObject: [_adEntry objectForKey: @"Command"] forKey: KEY_COMMAND];
			[aBookmarkData setObject: [_adEntry objectForKey: @"Directory"] forKey: KEY_WORKING_DIRECTORY];
			[aBookmarkData setObject: [[iTermTerminalProfileMgr singleInstance] defaultProfileName] forKey: KEY_TERMINAL_PROFILE];
			[aBookmarkData setObject: [[iTermKeyBindingMgr singleInstance] globalProfileName] forKey: KEY_KEYBOARD_PROFILE];
			[aBookmarkData setObject: [[iTermDisplayProfileMgr singleInstance] defaultProfileName] forKey: KEY_DISPLAY_PROFILE];
			
			shortcut=([[_adEntry objectForKey:@"Shortcut"] intValue]? [NSString stringWithFormat:@"%c",[[_adEntry objectForKey:@"Shortcut"] intValue]]:@"");
			shortcut = [shortcut lowercaseString];
			[aBookmarkData setObject: shortcut forKey: KEY_SHORTCUT];
			
			childNode = [[TreeNode alloc] initWithData: aBookmarkData parent: nil children: [NSArray array]];
			[childNode setIsLeaf: YES];
			[bookmarks insertChild: childNode atIndex: [bookmarks numberOfChildren]];
			[childNode release];						
			[aBookmarkData release];
		}
		
	}
	
	// delete old addressbook file.
	fileManager = [NSFileManager defaultManager];
	if([fileManager isDeletableFileAtPath: [ADDRESS_BOOK_FILE stringByExpandingTildeInPath]])
		[fileManager removeFileAtPath: [ADDRESS_BOOK_FILE stringByExpandingTildeInPath] handler: nil];
	
}

- (int) indexForBookmark: (NSDictionary *)bookmark
{
	return [[self rootNode] indexForNode: bookmark];
}

- (NSDictionary *) bookmarkForIndex: (int)index
{
	return [[self rootNode] nodeForIndex: index];
}

// NSNetServiceBrowser delegate methods
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing 
{
	NSMutableDictionary *aDict;

	// Get the OS info without using Carbon. This method is recommended by Apple
	NSDictionary *systemVersionDict = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
	NSString *versionString = [systemVersionDict objectForKey:@"ProductVersion"];
	NSArray *osArray = [versionString componentsSeparatedByString:@"."];
	int osElementCount = [osArray count];
	int osMajor = (osElementCount >= 1) ? [[osArray objectAtIndex:0] intValue] : 0;
	int osMinor = (osElementCount >= 2) ? [[osArray objectAtIndex:1] intValue] : 0;
	//int osBugfix = (osElementCount >= 3) ? [[osArray objectAtIndex:2] intValue] : 0;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aNetService);
	
	if(bonjourGroup == nil)
	{
		aDict = [[NSMutableDictionary alloc] init];
		[aDict setObject: @"Bonjour" forKey: KEY_NAME];
		[aDict setObject: @"" forKey: KEY_DESCRIPTION];
		[aDict setObject: @"Yes" forKey: KEY_BONJOUR_GROUP];
						
		bonjourGroup = [[TreeNode alloc] initWithData: aDict parent: nil children: [NSArray array]];
		[bonjourGroup setIsLeaf: NO];
		[aDict release];
	}
	
	// add a subgroup for this service if it does not already exist
	[self _getBonjourServiceTypeNode: [aNetService type]];
	
	// resolve the service
	// add to temporary array to retain it so that resolving works.
	[bonjourServices addObject: aNetService];
	[aNetService setDelegate: self];
		
	if (osMajor == 10 && osMinor >= 4)
		[aNetService resolveWithTimeout: (NSTimeInterval)5];
	else
		[aNetService resolve];
}


- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing 
{
	TreeNode *serviceNode, *childNode, *parentNode;
	NSDictionary *nodeData;
	NSEnumerator *anEnumerator;
	BOOL sshService = NO;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aNetService);
	
	if(aNetService == nil)
		return;
		
	// grab the service group node in the tree
	serviceNode = [self _getBonjourServiceTypeNode: [aNetService type]];
	
	// remove host entry from this group
	anEnumerator = [[serviceNode children] objectEnumerator];
	while ((childNode = [anEnumerator nextObject]))
	{
		nodeData = [childNode nodeData];
		if([[nodeData objectForKey: KEY_NAME] isEqualToString: [aNetService name]])
		{
			// check for ssh service to remove sftp service below
			if([[[serviceNode nodeData] objectForKey: KEY_BONJOUR_SERVICE] isEqualToString: @"ssh"])
				sshService = YES;
			parentNode = [childNode nodeParent];
			[childNode removeFromParent];
			if([parentNode numberOfChildren] == 0)
				[parentNode removeFromParent];
			
			break;			
		}
	}
	
	// if this was an ssh service, remove associated sftp service also
	if(sshService == YES)
	{
		// grab the service group node in the tree
		serviceNode = [self _getBonjourServiceTypeNode: @"_sftp.tcp."];
		
		// remove host entry from this group
		anEnumerator = [[serviceNode children] objectEnumerator];
		while ((childNode = [anEnumerator nextObject]))
		{
			nodeData = [childNode nodeData];
			if([[nodeData objectForKey: KEY_NAME] isEqualToString: [aNetService name]])
			{
				parentNode = [childNode nodeParent];
				[childNode removeFromParent];
				if([parentNode numberOfChildren] == 0)
					[parentNode removeFromParent];
				
				
				break;			
			}
		}
	}
	
	// if bonjour group is empty, remove it
	if([bonjourGroup numberOfChildren] == 0)
		[bonjourGroup removeFromParent];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    		

	
}

// NSNetService delegate
- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
	NSMutableDictionary *aDict;
	NSData  *address = nil;
	struct sockaddr_in  *socketAddress;
	NSString	*ipAddressString = nil;
	TreeNode *serviceNode;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, sender);
	
	// cancel the resolution
	[sender stop];
	
	if([bonjourServices containsObject: sender] == NO)
		return;
	
	// now that we have at least one resolved service, add the bonjour group to the bookmarks.
	if([[bookmarks children] containsObject: bonjourGroup] == NO)
	{
		[bookmarks insertChild: bonjourGroup atIndex: [bookmarks numberOfChildren]];
	}	
	
	// grab the address
	address = [[sender addresses] objectAtIndex: 0];
	socketAddress = (struct sockaddr_in *)[address bytes];
	ipAddressString = [NSString stringWithFormat:@"%s", inet_ntoa(socketAddress->sin_addr)];
	
	aDict = [[NSMutableDictionary alloc] init];

	serviceNode = [self _getBonjourServiceTypeNode: [sender type]];
	
	[aDict setObject: [NSString stringWithFormat: @"%@", [sender name]] forKey: KEY_NAME];
	[aDict setObject: [NSString stringWithFormat: @"%@", [sender name]] forKey: KEY_DESCRIPTION];
	[aDict setObject: [NSString stringWithFormat: @"%@ %@", 
		[[serviceNode nodeData] objectForKey: KEY_BONJOUR_SERVICE], ipAddressString] forKey: KEY_COMMAND];
	[aDict setObject: @"" forKey: KEY_WORKING_DIRECTORY];
	[aDict setObject: [[iTermTerminalProfileMgr singleInstance] defaultProfileName] forKey: KEY_TERMINAL_PROFILE];
	[aDict setObject: [[iTermKeyBindingMgr singleInstance] globalProfileName] forKey: KEY_KEYBOARD_PROFILE];
	[aDict setObject: [[iTermDisplayProfileMgr singleInstance] defaultProfileName] forKey: KEY_DISPLAY_PROFILE];
	[aDict setObject: ipAddressString forKey: KEY_BONJOUR_SERVICE_ADDRESS];
	
	[[ITAddressBookMgr sharedInstance] addBookmarkWithData: aDict toNode: serviceNode];

	// No bonjour service for sftp. Rides over ssh, so try to detect that
	if([[[serviceNode nodeData] objectForKey: KEY_BONJOUR_SERVICE] isEqualToString: @"ssh"])
	{
		serviceNode = [self _getBonjourServiceTypeNode: @"_sftp._tcp."];
		
		[aDict setObject: [NSString stringWithFormat: @"%@", [sender name]] forKey: KEY_NAME];
		[aDict setObject: [NSString stringWithFormat: @"%@", [sender name]] forKey: KEY_DESCRIPTION];
		[aDict setObject: [NSString stringWithFormat: @"%@ %@", 
			[[serviceNode nodeData] objectForKey: KEY_BONJOUR_SERVICE], ipAddressString] forKey: KEY_COMMAND];
		[aDict setObject: @"" forKey: KEY_WORKING_DIRECTORY];
		[aDict setObject: [[iTermTerminalProfileMgr singleInstance] defaultProfileName] forKey: KEY_TERMINAL_PROFILE];
		[aDict setObject: [[iTermKeyBindingMgr singleInstance] globalProfileName] forKey: KEY_KEYBOARD_PROFILE];
		[aDict setObject: [[iTermDisplayProfileMgr singleInstance] defaultProfileName] forKey: KEY_DISPLAY_PROFILE];
		
		[[ITAddressBookMgr sharedInstance] addBookmarkWithData: aDict toNode: serviceNode];
	}
	
	[aDict release];
	
	// remove from array now that resolving is done
	if([bonjourServices containsObject: sender])
		[bonjourServices removeObject: sender];
	
	// Post a notification for all listeners that bookmarks have changed
	[[NSNotificationCenter defaultCenter] postNotificationName: @"iTermReloadAddressBook" object: nil userInfo: nil];    	
		
}

- (void)netService:(NSNetService *)aNetService didNotResolve:(NSDictionary *)errorDict
{
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aNetService);
	[aNetService stop];
}

- (void)netServiceWillResolve:(NSNetService *)aNetService
{
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aNetService);
}

- (void)netServiceDidStop:(NSNetService *)aNetService
{
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, aNetService);
}

@end

@implementation ITAddressBookMgr (Private);

- (BOOL) _checkForDefaultBookmark: (TreeNode *) rootNode defaultBookmark: (TreeNode **) aNode
{
	BOOL haveDefaultBookmark = NO;
	NSEnumerator *entryEnumerator;
	NSDictionary *dataDict;
	TreeNode *entry;
	
	entryEnumerator = [[rootNode children] objectEnumerator];
	while ((entry = [entryEnumerator nextObject]))
	{
		if([entry isGroup])
			haveDefaultBookmark = [self _checkForDefaultBookmark: entry defaultBookmark: aNode];
		else
		{
			dataDict = [entry nodeData];
			if([[dataDict objectForKey: KEY_DEFAULT_BOOKMARK] isEqualToString: @"Yes"])
			{
				if(aNode)
					*aNode = entry;
				haveDefaultBookmark = YES;
			}			
		}
		if(haveDefaultBookmark)
			break;
	}

	return (haveDefaultBookmark);
}

- (TreeNode *) _getBookmarkNodeWithName: (NSString *) aName searchFromNode: (TreeNode *) aNode
{
	NSEnumerator *entryEnumerator;
	NSDictionary *dataDict;
	TreeNode *entry, *theNode;
	
	dataDict = nil;
	
	entryEnumerator = [[aNode children] objectEnumerator];
	while ((entry = [entryEnumerator nextObject]))
	{
		dataDict = [entry nodeData];
		
		if([[dataDict objectForKey: KEY_NAME] isEqualToString: aName])
		{
			return (entry);
		}					
		else if([entry isGroup])
		{
			theNode = [self _getBookmarkNodeWithName: aName searchFromNode: entry];
			if(theNode != nil)
				return (theNode);
		}
	}
	
	return (nil);
}

- (TreeNode *) _getBonjourServiceTypeNode: (NSString *) aType
{
	NSEnumerator *keyEnumerator;
	BOOL aBool;
	TreeNode *childNode;
	NSRange aRange;
	NSString *serviceType = aType;
	NSMutableDictionary *aDict;
	
	if([aType length] <= 0)
		return (nil);
	
	aRange = [serviceType rangeOfString: @"."];
	if(aRange.location != NSNotFound)
	{
		serviceType = [serviceType substringWithRange: NSMakeRange(1, aRange.location - 1)];
	}	
	
	aBool = NO;
	keyEnumerator = [[bonjourGroup children] objectEnumerator];
	while ((childNode = [keyEnumerator nextObject]))
	{
		if([[[childNode nodeData] objectForKey: KEY_NAME] isEqualToString: serviceType])
		{
			aBool = YES;
			break;
		}
	}
	if(aBool == NO)
	{
		aDict = [[NSMutableDictionary alloc] init];
		[aDict setObject: serviceType forKey: KEY_NAME];
		[aDict setObject: @"" forKey: KEY_DESCRIPTION];
		[aDict setObject: serviceType forKey: KEY_BONJOUR_SERVICE];
		
		childNode = [[TreeNode alloc] initWithData: aDict parent: nil children: [NSArray array]];
		[childNode setIsLeaf: NO];
		[aDict release];
		
		[bonjourGroup insertChild: childNode atIndex: [bonjourGroup numberOfChildren]];
		[childNode release];		

	}
	
	return (childNode);
}

@end

