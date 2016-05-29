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

#import "DebugLogging.h"
#import "iTermDynamicProfileManager.h"
#import "iTermKeyBindingMgr.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#include <arpa/inet.h>

const NSTimeInterval kMinimumAntiIdlePeriod = 1.0;

@implementation ITAddressBookMgr {
    NSNetServiceBrowser *sshBonjourBrowser;
    NSNetServiceBrowser *ftpBonjourBrowser;
    NSNetServiceBrowser *telnetBonjourBrowser;
    NSMutableArray *bonjourServices;
    iTermDynamicProfileManager *_dynamicProfileManager;
}

+ (id)sharedInstance {
    static ITAddressBookMgr* shared = nil;

    if (!shared) {
        shared = [[ITAddressBookMgr alloc] init];
    }

    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
        _dynamicProfileManager = [iTermDynamicProfileManager sharedInstance];
        if ([prefs objectForKey:KEY_DEPRECATED_BOOKMARKS] &&
            [[prefs objectForKey:KEY_DEPRECATED_BOOKMARKS] isKindOfClass:[NSDictionary class]] &&
            ![prefs objectForKey:KEY_NEW_BOOKMARKS]) {
            // Have only old-style bookmarks. Load them and convert them to new-style
            // bookmarks.
            [self recursiveMigrateBookmarks:[prefs objectForKey:KEY_DEPRECATED_BOOKMARKS] path:@[]];
            [prefs removeObjectForKey:KEY_DEPRECATED_BOOKMARKS];
            [prefs setObject:[[ProfileModel sharedInstance] rawData] forKey:KEY_NEW_BOOKMARKS];
            [[ProfileModel sharedInstance] removeAllBookmarks];
        }

        // Load new-style bookmarks.
        id newBookmarks = [prefs objectForKey:KEY_NEW_BOOKMARKS];
        NSString *originalDefaultGuid = [[[prefs objectForKey:KEY_DEFAULT_GUID] copy] autorelease];
        if ([newBookmarks isKindOfClass:[NSArray class]]) {
            [self setBookmarks:newBookmarks
                   defaultGuid:[prefs objectForKey:KEY_DEFAULT_GUID]];
        } else if ([newBookmarks isKindOfClass:[NSString class]]) {
            NSLog(@"Loading profiles from %@", newBookmarks);
            NSMutableArray *profiles = [NSMutableArray array];
            NSMutableSet *guids = [NSMutableSet set];
            if ([_dynamicProfileManager loadDynamicProfilesFromFile:(NSString *)newBookmarks
                                                          intoArray:profiles
                                                              guids:guids] &&
                [profiles count] > 0) {
                NSString *defaultGuid = profiles[0][KEY_GUID];
                for (Profile *profile in profiles) {
                    if ([profile[KEY_DEFAULT_BOOKMARK] isEqualToString:@"Yes"]) {
                        defaultGuid = profile[KEY_GUID];
                        break;
                    }
                }
                [self setBookmarks:profiles defaultGuid:defaultGuid];
            } else {
                NSLog(@"Failed to load profiles from %@", newBookmarks);
                exit(1);
            }
        }

        // Make sure there is at least one bookmark.
        if ([[ProfileModel sharedInstance] numberOfBookmarks] == 0) {
            NSMutableDictionary* aDict = [[NSMutableDictionary alloc] init];
            [ITAddressBookMgr setDefaultsInBookmark:aDict];
            [[ProfileModel sharedInstance] addBookmark:aDict];
            [aDict release];
        }

        if ([iTermPreferences boolForKey:kPreferenceKeyAddBonjourHostsToProfiles]) {
            [self locateBonjourServices];
        }

        [iTermPreferences addObserverForKey:kPreferenceKeyAddBonjourHostsToProfiles
                                      block:^(id previousValue, id newValue) {
                                          if ([newValue boolValue]) {
                                              [self locateBonjourServices];
                                          } else {
                                              [self stopLocatingBonjourServices];
                                              [self removeBonjourProfiles];
                                          }
                                      }];

        BOOL bookmarkWithDefaultGuidExisted =
            ([[ProfileModel sharedInstance] bookmarkWithGuid:originalDefaultGuid] != nil);
        [_dynamicProfileManager reloadDynamicProfiles];
        if (!bookmarkWithDefaultGuidExisted &&
            [[ProfileModel sharedInstance] bookmarkWithGuid:originalDefaultGuid] != nil) {
            // One of the dynamic profiles has the default guid.
            [[ProfileModel sharedInstance] setDefaultByGuid:originalDefaultGuid];
        }
    }

    return self;
}

- (void)dealloc {
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

- (void)removeBonjourProfiles {
    // Remove existing bookmarks with the "bonjour" tag. Even if
    // network browsing is re-enabled, these bookmarks would never
    // be automatically removed.
    ProfileModel* model = [ProfileModel sharedInstance];
    NSString* kBonjourTag = @"bonjour";
    int n = [model numberOfBookmarksWithFilter:kBonjourTag];
    for (int i = n - 1; i >= 0; --i) {
        Profile* bookmark = [model profileAtIndex:i withFilter:kBonjourTag];
        if ([model bookmark:bookmark hasTag:kBonjourTag]) {
            [model removeBookmarkAtIndex:i withFilter:kBonjourTag];
        }
    }
}

- (void)locateBonjourServices {
    if (!bonjourServices) {
        sshBonjourBrowser = [[NSNetServiceBrowser alloc] init];
        ftpBonjourBrowser = [[NSNetServiceBrowser alloc] init];
        telnetBonjourBrowser = [[NSNetServiceBrowser alloc] init];

        bonjourServices = [[NSMutableArray alloc] init];

        [sshBonjourBrowser setDelegate:self];
        [ftpBonjourBrowser setDelegate:self];
        [telnetBonjourBrowser setDelegate:self];
        [sshBonjourBrowser searchForServicesOfType:@"_ssh._tcp." inDomain:@""];
        [ftpBonjourBrowser searchForServicesOfType:@"_ftp._tcp." inDomain:@""];
        [telnetBonjourBrowser searchForServicesOfType:@"_telnet._tcp." inDomain:@""];
    }
}

- (void)stopLocatingBonjourServices {
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

+ (NSDictionary*)encodeColor:(NSColor*)origColor {
    return [origColor dictionaryValue];
}

// This method always returns a color in the calibrated color space. If the
// color space in the plist is not calibrated, it is converted (which preserves
// the actual color values).
+ (NSColor *)decodeColor:(NSDictionary*)plist {
    return [plist colorValue];
}

- (void)copyProfileToBookmark:(NSMutableDictionary *)dict
{
    NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"MigrationMap"
                                                                           ofType:@"plist"];
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

    if ([data objectForKey:KEY_COMMAND_LINE]) {
        // Not just a folder if it has a command.
        NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:data];
        [self copyProfileToBookmark:temp];
        [temp setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        [temp setObject:path forKey:KEY_TAGS];
        [temp setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
        NSString* dir = [data objectForKey:KEY_WORKING_DIRECTORY];
        if (dir && [dir length] > 0) {
            [temp setObject:kProfilePreferenceInitialDirectoryCustomValue
                     forKey:KEY_CUSTOM_DIRECTORY];
        } else if (dir && [dir length] == 0) {
            [temp setObject:kProfilePreferenceInitialDirectoryRecycleValue
                     forKey:KEY_CUSTOM_DIRECTORY];
        } else {
            [temp setObject:kProfilePreferenceInitialDirectoryHomeValue
                     forKey:KEY_CUSTOM_DIRECTORY];
        }
        [[ProfileModel sharedInstance] addBookmark:temp];
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

+ (NSFont *)fontWithDesc:(NSString *)fontDesc {
    return [fontDesc fontValue];
}

- (void)setBookmarks:(NSArray*)newBookmarksArray defaultGuid:(NSString*)guid
{
    [[ProfileModel sharedInstance] load:newBookmarksArray];
    if (guid) {
        if ([[ProfileModel sharedInstance] bookmarkWithGuid:guid]) {
            [[ProfileModel sharedInstance] setDefaultByGuid:guid];
        }
    }
}

- (ProfileModel*)model
{
    return [ProfileModel sharedInstance];
}

- (BOOL)verbose {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"iTermDebugBonjour"];
}

// NSNetServiceBrowser delegate methods
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
           didFindService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing
{
    if ([self verbose]) {
        NSLog(@"netServiceBrowser:%@ didFindService:%@ moreComing:%d",
              aNetServiceBrowser, aNetService, (int)moreComing);
    }
    // resolve the service and add to temporary array to retain it so that
    // resolving works.
    [bonjourServices addObject:aNetService];
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:5];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser
         didRemoveService:(NSNetService *)aNetService
               moreComing:(BOOL)moreComing {
    if (aNetService == nil) {
        return;
    }
    if ([self verbose]) {
        NSLog(@"netServiceBrowser:%@ didRemoveService:%@ moreComing:%d",
              aNetServiceBrowser, aNetService, (int)moreComing);
    }

    // remove host entry from this group
    NSMutableArray* toRemove = [[[NSMutableArray alloc] init] autorelease];
#ifdef SUPPORT_SFTP
    NSString* sftpName = [NSString stringWithFormat:@"%@-sftp", [aNetService name]];
#endif
    for (NSNumber* n in [[ProfileModel sharedInstance] bookmarkIndicesMatchingFilter:@"tag:^bonjour$"]) {
        int i = [n intValue];
        Profile* bookmark = [[ProfileModel sharedInstance] profileAtIndex:i];
        NSString* bookmarkName = [bookmark objectForKey:KEY_NAME];
        if ([bookmarkName isEqualToString:[aNetService name]]
#ifdef SUPPORT_SFTP
            || [bookmarkName isEqualToString:sftpName]
#endif
            ) {
            if ([self verbose]) {
                NSLog(@"remove profile with name %@", bookmarkName);
            }
            [toRemove addObject:[NSNumber numberWithInt:i]];
        }
    }
    [[ProfileModel sharedInstance] removeBookmarksAtIndices:toRemove];
}

+ (NSString*)descFromFont:(NSFont*)font {
    return [font stringValue];
}

+ (void)setDefaultsInBookmark:(NSMutableDictionary*)aDict {
    NSString* plistFile = [[NSBundle bundleForClass:[self class]]
                                    pathForResource:@"DefaultBookmark"
                                             ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile: plistFile];
    [aDict addEntriesFromDictionary:presetsDict];
    [aDict setObject:@"xterm-256color" forKey:KEY_TERMINAL_TYPE];

    NSString *aName;

    aName = NSLocalizedStringFromTableInBundle(@"Default",
                                               @"iTerm",
                                               [NSBundle bundleForClass: [self class]],
                                               @"Terminal Profiles");
    [aDict setObject:aName forKey: KEY_NAME];
    [aDict setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
    [aDict setObject:@"" forKey: KEY_COMMAND_LINE];
    [aDict setObject:aName forKey: KEY_DESCRIPTION];
    [aDict setObject:kProfilePreferenceInitialDirectoryHomeValue
              forKey:KEY_CUSTOM_DIRECTORY];
    [aDict setObject:NSHomeDirectory() forKey: KEY_WORKING_DIRECTORY];
}

- (void)_addBonjourHostProfileWithName:(NSString *)serviceName
                       ipAddressString:(NSString *)ipAddressString
                                  port:(int)port
                           serviceType:(NSString *)serviceType {
    NSMutableDictionary *newBookmark;
    Profile* prototype = [[ProfileModel sharedInstance] defaultBookmark];
    if (prototype) {
        newBookmark = [NSMutableDictionary dictionaryWithDictionary:prototype];
    } else {
        newBookmark = [NSMutableDictionary dictionaryWithCapacity:20];
        [ITAddressBookMgr setDefaultsInBookmark:newBookmark];
    }


    [newBookmark setObject:serviceName forKey:KEY_NAME];
    [newBookmark setObject:serviceName forKey:KEY_DESCRIPTION];
    NSString *optionalPortArg = @"";
    if ([serviceType isEqualToString:@"ssh"] && port != 22) {
        optionalPortArg = [NSString stringWithFormat:@"-p %d ", port];
    }
    [newBookmark setObject:[NSString stringWithFormat:@"%@ %@%@", serviceType, optionalPortArg, ipAddressString]
                    forKey:KEY_COMMAND_LINE];
    [newBookmark setObject:@"" forKey:KEY_WORKING_DIRECTORY];
    [newBookmark setObject:@"Yes" forKey:KEY_CUSTOM_COMMAND];
    [newBookmark setObject:kProfilePreferenceInitialDirectoryHomeValue
                    forKey:KEY_CUSTOM_DIRECTORY];
    [newBookmark setObject:ipAddressString forKey:KEY_BONJOUR_SERVICE_ADDRESS];
    [newBookmark setObject:[NSArray arrayWithObjects:@"bonjour",nil] forKey:KEY_TAGS];
    [newBookmark setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    [newBookmark setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [newBookmark removeObjectForKey:KEY_SHORTCUT];
    [[ProfileModel sharedInstance] addBookmark:newBookmark];

#ifdef SUPPORT_SFTP
    // No bonjour service for sftp. Rides over ssh, so try to detect that
    if ([serviceType isEqualToString:@"ssh"]) {
        [newBookmark setObject:[NSString stringWithFormat:@"%@-sftp", serviceName] forKey:KEY_NAME];
        [newBookmark setObject:[NSArray arrayWithObjects:@"bonjour", @"sftp", nil] forKey:KEY_TAGS];
        [newBookmark setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        [newBookmark setObject:[NSString stringWithFormat:@"sftp %@", ipAddressString] forKey:KEY_COMMAND_LINE];
        [[ProfileModel sharedInstance] addBookmark:newBookmark];
    }
#endif
}

- (void *)inaddrFromSockaddr:(struct sockaddr *)sa
{
    if (sa->sa_family == AF_INET) {
        return &(((struct sockaddr_in*)sa)->sin_addr);
    } else {
        // Assume ipv6
        return &(((struct sockaddr_in6*)sa)->sin6_addr);
    }
}

- (unsigned short)portFromSockaddr:(struct sockaddr *)sa
{
    if (sa->sa_family == AF_INET) {
        return htons(((struct sockaddr_in*)sa)->sin_port);
    } else {
        // Assume ipv6
        return htons(((struct sockaddr_in6*)sa)->sin6_port);
    }
}

// NSNetService delegate
- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
    //NSLog(@"%s: %@", __PRETTY_FUNCTION__, sender);

    // cancel the resolution
    [sender stop];

    if ([self verbose]) {
        NSLog(@"netServiceDidResolveAddress:%@", sender);
    }
    if ([bonjourServices containsObject: sender] == NO) {
        if ([self verbose]) {
            NSLog(@"netServiceDidResolveAddress sender not in services %@", bonjourServices);
        }
        return;
    }

    // grab the address
    if ([[sender addresses] count] == 0) {
        if ([self verbose]) {
            NSLog(@"netServiceDidResolveAddress sender has no addresses");
        }
        return;
    }
    NSString* serviceType = [self getBonjourServiceType:[sender type]];
    NSString* serviceName = [sender name];
    NSData* address = [[sender addresses] objectAtIndex: 0];
    if ([self verbose]) {
        NSLog(@"netServiceDidResolveAddress type=%@ name=%@ address=%@", serviceType, serviceName, address);
    }
    struct sockaddr *socketAddress = (struct sockaddr *)[address bytes];
    char buffer[INET6_ADDRSTRLEN + 1];
    const char *strAddr = inet_ntop(socketAddress->sa_family,
                                    [self inaddrFromSockaddr:socketAddress],
                                    buffer,
                                    sizeof(buffer));
    if (strAddr) {
        if ([self verbose]) {
            NSLog(@"netServiceDidResolveAddress add profile with address %s", strAddr);
        }
        [self _addBonjourHostProfileWithName:serviceName
                             ipAddressString:[NSString stringWithFormat:@"%s", strAddr]
                                        port:[self portFromSockaddr:socketAddress]
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
    if ([self verbose]) {
        NSLog(@"getBonjourServiceType:%@", aType);
    }
    NSString *serviceType = aType;
    if ([aType length] <= 0) {
        if ([self verbose]) {
            NSLog(@"netServiceDidResolveAddress empty type");
        }
        return nil;
    }
    NSRange aRange = [serviceType rangeOfString: @"."];
    if(aRange.location != NSNotFound) {
        if ([self verbose]) {
            NSLog(@"netServiceDidResolveAddress return value prior to first .");
        }
        return [serviceType substringWithRange: NSMakeRange(1, aRange.location - 1)];
    } else {
        if ([self verbose]) {
            NSLog(@"netServiceDidResolveAddress no . found, return whole value");
        }
        return serviceType;
    }
}

+ (NSString *)shellLauncherCommand {
    return [NSString stringWithFormat:@"/usr/bin/login -f%@pl %@ %@ --launch_shell",
            [self hushlogin] ? @"q" : @"",
            [NSUserName() stringWithEscapedShellCharacters],
            [[[NSBundle mainBundle] executablePath] stringWithEscapedShellCharacters]];
}

+ (NSString*)loginShellCommandForBookmark:(Profile*)bookmark
                            forObjectType:(iTermObjectType)objectType {
    NSString *customDirectoryString;
    if ([[bookmark objectForKey:KEY_CUSTOM_DIRECTORY] isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue]) {
        switch (objectType) {
            case iTermWindowObject:
                customDirectoryString = [bookmark objectForKey:KEY_AWDS_WIN_OPTION];
                break;
            case iTermTabObject:
                customDirectoryString = [bookmark objectForKey:KEY_AWDS_TAB_OPTION];
                break;
            case iTermPaneObject:
                customDirectoryString = [bookmark objectForKey:KEY_AWDS_PANE_OPTION];
                break;
            default:
                NSLog(@"Bogus object type %d", (int)objectType);
                customDirectoryString = kProfilePreferenceInitialDirectoryHomeValue;
        }
    } else {
        customDirectoryString = [bookmark objectForKey:KEY_CUSTOM_DIRECTORY];
    }

    if ([customDirectoryString isEqualToString:kProfilePreferenceInitialDirectoryHomeValue]) {
        // Run login without -l argument: this is a login session and will use the home dir.
        return [self standardLoginCommand];
    } else {
        // Not using the home directory. This requires some trickery.
        // Run iTerm2's executable with a special flag that makes it run the shell as a login shell
        // (with "-" inserted at the start of argv[0]). See shell_launcher.c for more details.
        NSString *launchShellCommand = [self shellLauncherCommand];
        return launchShellCommand;
    }
}

// See issue 4425 for why we do this.
+ (BOOL)hushlogin {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".hushlogin"];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSString *)standardLoginCommand {
    return [NSString stringWithFormat:@"login -f%@p \"%@\"", [self hushlogin] ? @"q" : @"", NSUserName()];
}

+ (NSString*)bookmarkCommand:(Profile*)bookmark
               forObjectType:(iTermObjectType)objectType
{
    BOOL custom = [[bookmark objectForKey:KEY_CUSTOM_COMMAND] isEqualToString:@"Yes"];
    if (custom) {
        return [bookmark objectForKey:KEY_COMMAND_LINE];
    } else {
        return [ITAddressBookMgr loginShellCommandForBookmark:bookmark
                                                forObjectType:objectType];
    }
}

+ (NSString *)_advancedWorkingDirWithOption:(NSString *)option
                                  directory:(NSString *)pwd
{
    if ([option isEqualToString:kProfilePreferenceInitialDirectoryCustomValue]) {
        return pwd;
    } else if ([option isEqualToString:kProfilePreferenceInitialDirectoryRecycleValue]) {
        return @"";
    } else {
        // Home dir, option == "No"
        return NSHomeDirectory();
    }
}

+ (NSString*)bookmarkWorkingDirectory:(Profile*)bookmark forObjectType:(iTermObjectType)objectType
{
    NSString* custom = [bookmark objectForKey:KEY_CUSTOM_DIRECTORY];
    if ([custom isEqualToString:kProfilePreferenceInitialDirectoryCustomValue]) {
        return [bookmark objectForKey:KEY_WORKING_DIRECTORY];
    } else if ([custom isEqualToString:kProfilePreferenceInitialDirectoryRecycleValue]) {
        return @"";
    } else if ([custom isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue]) {
        switch (objectType) {
          case iTermWindowObject:
              return [ITAddressBookMgr _advancedWorkingDirWithOption:[bookmark objectForKey:KEY_AWDS_WIN_OPTION]
                                                           directory:[bookmark objectForKey:KEY_AWDS_WIN_DIRECTORY]];
          case iTermTabObject:
              return [ITAddressBookMgr _advancedWorkingDirWithOption:[bookmark objectForKey:KEY_AWDS_TAB_OPTION]
                                                           directory:[bookmark objectForKey:KEY_AWDS_TAB_DIRECTORY]];
          case iTermPaneObject:
              return [ITAddressBookMgr _advancedWorkingDirWithOption:[bookmark objectForKey:KEY_AWDS_PANE_OPTION]
                                                           directory:[bookmark objectForKey:KEY_AWDS_PANE_DIRECTORY]];
          default:
              NSLog(@"Bogus object type %d", (int)objectType);
              return NSHomeDirectory();  // Shouldn't happen
        }
    } else {
        // Home dir, custom == "No"
        return NSHomeDirectory();
    }
}

+ (BOOL)canRemoveProfile:(NSDictionary *)profile fromModel:(ProfileModel *)model {
    DLog(@"removeProfile called");
    if (!profile) {
        DLog(@"Nil profile");
        return NO;
    }

    if (![model bookmarkWithGuid:profile[KEY_GUID]]) {
        DLog(@"Can't remove profile not in shared profile model");
        return NO;
    }

    if ([model numberOfBookmarks] < 2) {
        DLog(@"Can't remove last profile");
        return NO;
    }

    DLog(@"Ok to remove.");
    return YES;
}

+ (void)removeProfile:(NSDictionary *)profile fromModel:(ProfileModel *)model {
    NSString *guid = profile[KEY_GUID];
    DLog(@"Remove profile with guid %@...", guid);
    if ([model numberOfBookmarks] == 1) {
        DLog(@"Refusing to remove only profile");
        return;
    }

    DLog(@"Removing key bindings that reference the guid being removed");
    [self removeKeyMappingsReferringToGuid:guid];
    DLog(@"Removing profile from model");
    [model removeProfileWithGuid:guid];

    // Ensure all profile list views reload their data to avoid issue 4033.
    DLog(@"Posting profile was deleted notification");
    [[NSNotificationCenter defaultCenter] postNotificationName:kProfileWasDeletedNotification
                                                        object:nil];
    [model flush];
}

+ (void)removeKeyMappingsReferringToGuid:(NSString *)badRef {
    for (NSString* guid in [[ProfileModel sharedInstance] guids]) {
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        profile = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:profile];
        if (profile) {
            [[ProfileModel sharedInstance] setBookmark:profile withGuid:guid];
        }
    }
    for (NSString* guid in [[ProfileModel sessionsInstance] guids]) {
        Profile* profile = [[ProfileModel sessionsInstance] bookmarkWithGuid:guid];
        profile = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:profile];
        if (profile) {
            [[ProfileModel sessionsInstance] setBookmark:profile withGuid:guid];
        }
    }
    [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

@end
