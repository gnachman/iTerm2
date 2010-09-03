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
#import <iTerm/iTermKeyBindingMgr.h>
#include <netinet/in.h>
#include <arpa/inet.h>


@implementation ITAddressBookMgr

+ (id)sharedInstance
{
    static ITAddressBookMgr* shared = nil;
    
    if (!shared) {
        shared = [[ITAddressBookMgr alloc] init];
    }
    
    return shared;
}

- (id)init
{
    self = [super init];
    
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];

    if ([prefs objectForKey:KEY_DEPRECATED_BOOKMARKS] && ![prefs objectForKey:KEY_NEW_BOOKMARKS]) {
        // Have only old-style bookmarks. Load them and convert them to new-style
        // bookmarks.
        [self recursiveMigrateBookmarks:[prefs objectForKey:KEY_DEPRECATED_BOOKMARKS] path:[NSArray arrayWithObjects:nil]];
        [prefs removeObjectForKey:KEY_DEPRECATED_BOOKMARKS];
        [prefs setObject:[[BookmarkModel sharedInstance] rawData] forKey:KEY_NEW_BOOKMARKS];
        [[BookmarkModel sharedInstance] removeAllBookmarks];
    }
    
    // Load new-style bookmarks.
    if ([prefs objectForKey:KEY_NEW_BOOKMARKS]) {
        [self setBookmarks:[prefs objectForKey:KEY_NEW_BOOKMARKS] 
               defaultGuid:[prefs objectForKey:KEY_DEFAULT_GUID]];
    }
    
    // Make sure there is at least one bookmark.
    if ([[BookmarkModel sharedInstance] numberOfBookmarks] == 0) {
        NSMutableDictionary* aDict = [[NSMutableDictionary alloc] init];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [[BookmarkModel sharedInstance] addBookmark:aDict];
        [aDict release];
    }
    
    return self;
}

- (void)dealloc
{
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

+ (NSArray*)encodeColor:(NSColor*)origColor
{
    NSColor* color = [origColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	CGFloat red, green, blue, alpha;
	[color getRed:&red green:&green blue:&blue alpha:&alpha];
    return [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:red], @"Red Component",
                                                      [NSNumber numberWithFloat:green], @"Green Component",
                                                      [NSNumber numberWithFloat:blue], @"Blue Component",
                                                      nil];
}

+ (NSColor*)decodeColor:(NSDictionary*)plist
{
    if ([plist count] != 3) {
        return [NSColor blackColor];
    }
    
    return [NSColor colorWithCalibratedRed:[[plist objectForKey:@"Red Component"] floatValue]
                                     green:[[plist objectForKey:@"Green Component"] floatValue]
                                      blue:[[plist objectForKey:@"Blue Component"] floatValue]
                                     alpha:1.0];
}

- (void)copyProfileToBookmark:(NSMutableDictionary *)dict
{
 	NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"MigrationMap" ofType:@"plist"];   
    NSDictionary* fileDict = [NSDictionary dictionaryWithContentsOfFile: plistFile];
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];    
    NSDictionary* keybindingProfiles = [prefs objectForKey: @"KeyBindings"];
	NSDictionary* displayProfiles =  [prefs objectForKey: @"Displays"];
	NSDictionary* terminalProfiles = [prefs objectForKey: @"Terminals"];
    NSArray* xforms = [fileDict objectForKey:@"Migration Map"];
    for (int i = 0; i < [xforms count]; ++i) {
        NSDictionary* xform = [xforms objectAtIndex:i];
        NSString* destination = [xform objectForKey:@"Destination"];
        if ([dict objectForKey:destination]) {
            continue;
        }
        NSString* prefix = [xform objectForKey:@"Prefix"];
        NSString* suffix = [xform objectForKey:@"Suffix"];
        id defaultValue = [xform objectForKey:@"Default"];
        
        NSDictionary* parent = nil;
        if ([prefix isEqualToString:@"Terminal"]) {
            parent = [terminalProfiles objectForKey:[dict objectForKey:KEY_TERMINAL_PROFILE]];
        } else if ([prefix isEqualToString:@"Displays"]) {
            parent = [displayProfiles objectForKey:[dict objectForKey:KEY_DISPLAY_PROFILE]];
        } else if ([prefix isEqualToString:@"KeyBindings"]) {
            parent = [keybindingProfiles objectForKey:[dict objectForKey:KEY_KEYBOARD_PROFILE]];
        } else {
            NSAssert(0, @"Bad prefix");
        }
        id value = nil;
        if (parent) {
            value = [parent objectForKey:suffix];
        }
        if (!value) {
            value = defaultValue;
        }
        [dict setObject:value forKey:destination];
    }
}

- (void)recursiveMigrateBookmarks:(NSDictionary*)node path:(NSArray*)path
{
    NSDictionary* data = [node objectForKey:@"Data"];

	if ([data objectForKey:KEY_COMMAND]) {
        // Not just a folder if it has a command.
        NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:data];
        [self copyProfileToBookmark:temp];
        [temp setObject:[BookmarkModel newGuid] forKey:KEY_GUID];
        [temp setObject:path forKey:KEY_TAGS];
        [temp setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
        NSString* dir = [data objectForKey:KEY_WORKING_DIRECTORY];
        if (dir && [dir length] > 0) {
            [temp setObject:@"Yes" forKey:KEY_CUSTOM_DIRECTORY];
        } else {
            [temp setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
        }
        [[BookmarkModel sharedInstance] addBookmark:temp];
	}
    
    NSArray* entries = [node objectForKey:@"Entries"];
    for (int i = 0; i < [entries count]; ++i) {
        NSMutableArray* childPath = [NSMutableArray arrayWithArray:path];
        NSDictionary* dataDict = [node objectForKey:@"Data"];
        if (dataDict) {
            NSString* name = [dataDict objectForKey:@"Name"];
            if (name) {
                [childPath addObject:name];
            }
        }
		[self recursiveMigrateBookmarks:[entries objectAtIndex:i] path:childPath];
	}
}

+ (NSFont *)fontWithDesc:(NSString *)fontDesc
{
	float fontSize;
	char utf8FontName[128];
	NSFont *aFont;
	
	if ([fontDesc length] == 0) {
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
	}
    
	sscanf([fontDesc UTF8String], "%s %g", utf8FontName, &fontSize);
	
	aFont = [NSFont fontWithName:[NSString stringWithFormat: @"%s", utf8FontName] size:fontSize];
	if (aFont == nil) {
		return ([NSFont userFixedPitchFontOfSize: 0.0]);
    }
	
    return aFont;
}

- (void)setBookmarks:(NSArray*)newBookmarksArray defaultGuid:(NSString*)guid
{
    [[BookmarkModel sharedInstance] load:newBookmarksArray];
    if (guid) {
        if ([[BookmarkModel sharedInstance] bookmarkWithGuid:guid]) {
            [[BookmarkModel sharedInstance] setDefaultByGuid:guid];
        }
    }
}

- (BookmarkModel*)model
{
    return [BookmarkModel sharedInstance];
}

// NSNetServiceBrowser delegate methods
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing 
{
	// resolve the service and add to temporary array to retain it so that 
    // resolving works.
	[bonjourServices addObject:aNetService];
	[aNetService setDelegate:self];		
    [aNetService resolve];
}


- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing 
{
	if (aNetService == nil) {
		return;
    }
		
	// remove host entry from this group
    BOOL sshService = NO;
    NSMutableArray* toRemove = [[[NSMutableArray alloc] init] autorelease];
    for (int i = 0; i < [[BookmarkModel sharedInstance] numberOfBookmarksWithFilter:@"bonjour"]; ++i) {
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkAtIndex:i withFilter:@"bonjour"];
        if ([[bookmark objectForKey:KEY_NAME] isEqualToString:[aNetService name]]) {
            if ([[bookmark objectForKey:KEY_BONJOUR_SERVICE] isEqualToString:@"ssh"]) {
                sshService = YES;
            }
            [toRemove addObject:[NSNumber numberWithInt:i]];
        }
    }
    for (int i = [toRemove count]-1; i >= 0; --i) {
        [[BookmarkModel sharedInstance] removeBookmarkAtIndex:[[toRemove objectAtIndex:i] intValue] withFilter:@"bonjour"];
    }
    if (sshService) {
        int i = [[BookmarkModel sharedInstance] indexOfBookmarkWithName:[aNetService name]];
        if (i >= 0) {
            [toRemove addObject:[NSNumber numberWithInt:i]];
        }
    }
    [toRemove removeAllObjects];	
}

+ (void)setDefaultsInBookmark:(NSMutableDictionary*)aDict
{
 	NSString* plistFile = [[NSBundle bundleForClass:[self class]] 
                                    pathForResource:@"DefaultBookmark" 
                                             ofType:@"plist"];   
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile: plistFile];
    [aDict addEntriesFromDictionary:presetsDict];

    NSString *aName;
    
    aName = NSLocalizedStringFromTableInBundle(@"Default",
                                               @"iTerm", 
                                               [NSBundle bundleForClass: [self class]],
                                               @"Terminal Profiles");
    [aDict setObject:aName forKey: KEY_NAME];
    [aDict setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
    [aDict setObject:@"" forKey: KEY_COMMAND];
    [aDict setObject:aName forKey: KEY_DESCRIPTION];
    [aDict setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
    [aDict setObject:NSHomeDirectory() forKey: KEY_WORKING_DIRECTORY];
}

// NSNetService delegate
- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
	NSMutableDictionary *aDict;
	NSData  *address = nil;
	struct sockaddr_in  *socketAddress;
	NSString	*ipAddressString = nil;
	
	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, sender);
	
	// cancel the resolution
	[sender stop];
	
	if ([bonjourServices containsObject: sender] == NO) {
		return;
    }
	
	// grab the address
    if ([[sender addresses] count] == 0) {
        return;
    }
	address = [[sender addresses] objectAtIndex: 0];
	socketAddress = (struct sockaddr_in *)[address bytes];
	ipAddressString = [NSString stringWithFormat:@"%s", inet_ntoa(socketAddress->sin_addr)];
	
    Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
    if (prototype) {
        aDict = [NSMutableDictionary dictionaryWithDictionary:prototype];
    } else {
        aDict = [[NSMutableDictionary alloc] init];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
    }
    
    NSString* serviceType = [self getBonjourServiceType:[sender type]];
	
	[aDict setObject:[NSString stringWithFormat:@"%@", [sender name]] forKey:KEY_NAME];
	[aDict setObject:[NSString stringWithFormat:@"%@", [sender name]] forKey:KEY_DESCRIPTION];
	[aDict setObject:[NSString stringWithFormat:@"%@ %@", serviceType, ipAddressString] forKey:KEY_COMMAND];
	[aDict setObject:@"" forKey:KEY_WORKING_DIRECTORY];
	[aDict setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
	[aDict setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
	[aDict setObject:ipAddressString forKey:KEY_BONJOUR_SERVICE_ADDRESS];
    [aDict setObject:[NSArray arrayWithObjects:@"bonjour",nil] forKey:KEY_TAGS];
    [aDict setObject:[BookmarkModel newGuid] forKey:KEY_GUID];    
    [aDict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [[BookmarkModel sharedInstance] addBookmark:aDict];

	// No bonjour service for sftp. Rides over ssh, so try to detect that
	if ([serviceType isEqualToString:@"ssh"]) {
        [aDict setObject:[NSString stringWithFormat:@"%@-sftp", [sender name]] forKey:KEY_NAME];
        [aDict setObject:[NSArray arrayWithObjects:@"bonjour", @"sftp", nil] forKey:KEY_TAGS];
        [aDict setObject:[BookmarkModel newGuid] forKey:KEY_GUID];
        [aDict setObject:[NSString stringWithFormat:@"sftp %@", ipAddressString] forKey:KEY_COMMAND];
        [[BookmarkModel sharedInstance] addBookmark:aDict];
	}
	
	// remove from array now that resolving is done
	if ([bonjourServices containsObject:sender]) {
		[bonjourServices removeObject:sender];
    }
		
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

- (NSString*)getBonjourServiceType:(NSString*)aType
{
    NSString *serviceType = aType;
    if ([aType length] <= 0) {
        return nil;
    }
    NSRange aRange = [serviceType rangeOfString: @"."];
    if(aRange.location != NSNotFound) {
        return [serviceType substringWithRange: NSMakeRange(1, aRange.location - 1)];
    } else {
        return serviceType;
    }
}

+ (NSString*)loginShellCommandForBookmark:(Bookmark*)bookmark
{
    char* thisUser = getenv("USER");
    char* userShell = getenv("SHELL");
    if (thisUser) {
        if ([[bookmark objectForKey:KEY_CUSTOM_DIRECTORY] isEqualToString:@"Yes"]) {
            return [NSString stringWithFormat:@"login -fpl %s", thisUser];
        } else {
            return [NSString stringWithFormat:@"login -fp %s", thisUser];
        }
    } else if (userShell) {
        return [NSString stringWithCString:userShell];
    } else {
        return @"/bin/bash --login";
    }
}

+ (NSString*)bookmarkCommand:(Bookmark*)bookmark
{
    BOOL custom = [[bookmark objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"];
    if (custom) {
        return [bookmark objectForKey:KEY_COMMAND];
    } else {
        return [ITAddressBookMgr loginShellCommandForBookmark:bookmark];
    }
}


+ (NSString*)bookmarkWorkingDirectory:(Bookmark*)bookmark
{
    BOOL custom = [[bookmark objectForKey:KEY_CUSTOM_DIRECTORY] isEqualToString:@"Yes"];
    if (custom) {
        return [bookmark objectForKey:KEY_WORKING_DIRECTORY];
    } else {
        return NSHomeDirectory();
    }
}

@end
