/*
 **  ITAddressBookMgr.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
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
#include <sys/types.h>
#include <pwd.h>

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

- (void)locateBonjourServices
{
    if (!bonjourServices) {
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
}

- (void)stopLocatingBonjourServices
{
    [sshBonjourBrowser stop];
    [sshBonjourBrowser release];
    sshBonjourBrowser = nil;

    [ftpBonjourBrowser stop];
    [ftpBonjourBrowser release];
    ftpBonjourBrowser = nil;

    [telnetBonjourBrowser stop];
    [telnetBonjourBrowser release];
    telnetBonjourBrowser = nil;

    [bonjourServices release];
    bonjourServices = nil;
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
        [temp setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
        [temp setObject:path forKey:KEY_TAGS];
        [temp setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
        NSString* dir = [data objectForKey:KEY_WORKING_DIRECTORY];
        if (dir && [dir length] > 0) {
            [temp setObject:@"Yes" forKey:KEY_CUSTOM_DIRECTORY];
        } else if (dir && [dir length] == 0) {
            [temp setObject:@"Recycle" forKey:KEY_CUSTOM_DIRECTORY];
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
    NSMutableArray* toRemove = [[[NSMutableArray alloc] init] autorelease];
    NSString* sftpName = [NSString stringWithFormat:@"%@-sftp", [aNetService name]];
    for (NSNumber* n in [[BookmarkModel sharedInstance] bookmarkIndicesMatchingFilter:@"bonjour"]) {
        int i = [n intValue];
        Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkAtIndex:i];
        NSString* bookmarkName = [bookmark objectForKey:KEY_NAME];
        if ([bookmarkName isEqualToString:[aNetService name]] ||
            [bookmarkName isEqualToString:sftpName]) {
            [toRemove addObject:[NSNumber numberWithInt:i]];
        }
    }
    [[BookmarkModel sharedInstance] removeBookmarksAtIndices:toRemove];
}

+ (NSString*)descFromFont:(NSFont*)font
{
    return [NSString stringWithFormat:@"%s %g", [[font fontName] UTF8String], [font pointSize]];
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

- (void)_addBonjourHostProfileWithName:(NSString *)serviceName
                       ipAddressString:(NSString *)ipAddressString
                           serviceType:(NSString *)serviceType
{
  NSMutableDictionary *newBookmark;
    Bookmark* prototype = [[BookmarkModel sharedInstance] defaultBookmark];
    if (prototype) {
        newBookmark = [NSMutableDictionary dictionaryWithDictionary:prototype];
    } else {
        newBookmark = [NSMutableDictionary dictionaryWithCapacity:20];
        [ITAddressBookMgr setDefaultsInBookmark:newBookmark];
    }


    [newBookmark setObject:serviceName forKey:KEY_NAME];
    [newBookmark setObject:serviceName forKey:KEY_DESCRIPTION];
    [newBookmark setObject:[NSString stringWithFormat:@"%@ %@", serviceType, ipAddressString] forKey:KEY_COMMAND];
    [newBookmark setObject:@"" forKey:KEY_WORKING_DIRECTORY];
    [newBookmark setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
    [newBookmark setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
    [newBookmark setObject:ipAddressString forKey:KEY_BONJOUR_SERVICE_ADDRESS];
    [newBookmark setObject:[NSArray arrayWithObjects:@"bonjour",nil] forKey:KEY_TAGS];
    [newBookmark setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
    [newBookmark setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [newBookmark removeObjectForKey:KEY_SHORTCUT];
    [[BookmarkModel sharedInstance] addBookmark:newBookmark];

    // No bonjour service for sftp. Rides over ssh, so try to detect that
    if ([serviceType isEqualToString:@"ssh"]) {
        [newBookmark setObject:[NSString stringWithFormat:@"%@-sftp", serviceName] forKey:KEY_NAME];
        [newBookmark setObject:[NSArray arrayWithObjects:@"bonjour", @"sftp", nil] forKey:KEY_TAGS];
        [newBookmark setObject:[BookmarkModel freshGuid] forKey:KEY_GUID];
        [newBookmark setObject:[NSString stringWithFormat:@"sftp %@", ipAddressString] forKey:KEY_COMMAND];
        [[BookmarkModel sharedInstance] addBookmark:newBookmark];
    }

}
// NSNetService delegate
- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
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
    NSString* serviceType = [self getBonjourServiceType:[sender type]];
    NSString* serviceName = [sender name];
    NSData* address = [[sender addresses] objectAtIndex: 0];
    struct sockaddr_in *socketAddress = (struct sockaddr_in *)[address bytes];
    char buffer[INET6_ADDRSTRLEN + 1];

    const char* strAddr = inet_ntop(socketAddress->sin_family, &socketAddress->sin_addr,
                                    buffer, [address length]);
    if (strAddr) {
          [self _addBonjourHostProfileWithName:serviceName
                               ipAddressString:[NSString stringWithFormat:@"%s", strAddr]
                                   serviceType:serviceType];

        // remove from array now that resolving is done
        if ([bonjourServices containsObject:sender]) {
            [bonjourServices removeObject:sender];
        }
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

static NSString* UserShell() {
    struct passwd* pw;
    pw = getpwuid(geteuid());
    if (!pw) {
        NSLog(@"No passwd entry for effective uid %d", geteuid());
        endpwent();
        return nil;
    }
    NSString* shell = [NSString stringWithUTF8String:pw->pw_shell];
    endpwent();
    return shell;
}

+ (NSString*)loginShellCommandForBookmark:(Bookmark*)bookmark asLoginShell:(BOOL*)asLoginShell
{
    NSString* thisUser = NSUserName();
    NSString* userShell = UserShell();
    if ([[bookmark objectForKey:KEY_CUSTOM_DIRECTORY] isEqualToString:@"No"]) {
        // Run login without -l argument: this is a login session and will use the home dir.
        *asLoginShell = NO;
        return [NSString stringWithFormat:@"login -fp \"%@\"", thisUser];
    } else if (userShell) {
        // This is the normal case when using a custom dir or reusing previous tab's dir:
        // Run the shell with - as the first char of argv[0]. It won't update
        // utmpx (only login does), though.
        *asLoginShell = YES;
        return userShell;
    } else if (thisUser) {
        // No shell known (not sure why this would happen) and we want a non-login shell.
        *asLoginShell = NO;
        // -l specifies a NON-LOGIN shell which doesn't changed the pwd.
        // (there is either a custom dir or we're recycling the last tab's dir)
        return [NSString stringWithFormat:@"login -fpl \"%@\"", thisUser];
    } else {
        // Can't get the shell or the user name. Should never happen.
        *asLoginShell = YES;
        return @"/bin/bash --login";
    }
}

+ (NSString*)bookmarkCommand:(Bookmark*)bookmark isLoginSession:(BOOL*)isLoginSession
{
    BOOL custom = [[bookmark objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"];
    if (custom) {
        *isLoginSession = NO;
        return [bookmark objectForKey:KEY_COMMAND];
    } else {
        return [ITAddressBookMgr loginShellCommandForBookmark:bookmark asLoginShell:isLoginSession];
    }
}


+ (NSString*)bookmarkWorkingDirectory:(Bookmark*)bookmark
{
    NSString* custom = [bookmark objectForKey:KEY_CUSTOM_DIRECTORY];
    if ([custom isEqualToString:@"Yes"]) {
        return [bookmark objectForKey:KEY_WORKING_DIRECTORY];
    } else if ([custom isEqualToString:@"No"]) {
        return NSHomeDirectory();
    } else {
        // recycle
        return @"";
    }
}

@end
