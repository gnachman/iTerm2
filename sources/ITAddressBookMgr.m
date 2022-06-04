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
#import "iTermExpressionEvaluator.h"
#import "iTermHotKeyController.h"
#import "iTermHotKeyMigrationHelper.h"
#import "iTermHotKeyProfileBindingController.h"
#import "iTermKeyMappings.h"
#import "iTermMigrationHelper.h"
#import "iTermPreferences.h"
#import "iTermProfilesMenuController.h"
#import "iTermProfilePreferences.h"
#import "PreferencePanel.h"
#import "ProfileModel.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#include <arpa/inet.h>

NSString *const iTermUnicodeVersionDidChangeNotification = @"iTermUnicodeVersionDidChangeNotification";

NSString *const kProfilePreferenceCommandTypeCustomValue = @"Yes";
NSString *const kProfilePreferenceCommandTypeLoginShellValue = @"No";
NSString *const kProfilePreferenceCommandTypeCustomShellValue = @"Custom Shell";
NSString *const kProfilePreferenceCommandTypeSSHValue = @"SSH";

const NSTimeInterval kMinimumAntiIdlePeriod = 1.0;
const NSInteger iTermMaxInitialSessionSize = 1250;

static NSMutableArray<NSNotification *> *sDelayedNotifications;

static NSString *iTermPathToSSH(void) {
    return [[NSBundle bundleForClass:[ITAddressBookMgr class]] pathForResource:@"it2ssh" ofType:nil];
}

iTermWindowType iTermWindowDefaultType(void) {
    return iTermThemedWindowType(WINDOW_TYPE_NORMAL);
}

iTermWindowType iTermThemedWindowType(iTermWindowType windowType) {
    switch (windowType) {
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_NORMAL:
            switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
                case TAB_STYLE_COMPACT:
                case TAB_STYLE_MINIMAL:
                    return WINDOW_TYPE_COMPACT;

                case TAB_STYLE_AUTOMATIC:
                case TAB_STYLE_LIGHT:
                case TAB_STYLE_DARK:
                case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                case TAB_STYLE_DARK_HIGH_CONTRAST:
                    return WINDOW_TYPE_NORMAL;
            }
            assert(false);
            return windowType;

        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_MAXIMIZED:
            switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
                case TAB_STYLE_COMPACT:
                case TAB_STYLE_MINIMAL:
                    return WINDOW_TYPE_COMPACT_MAXIMIZED;

                case TAB_STYLE_AUTOMATIC:
                case TAB_STYLE_LIGHT:
                case TAB_STYLE_DARK:
                case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                case TAB_STYLE_DARK_HIGH_CONTRAST:
                    return WINDOW_TYPE_MAXIMIZED;
            }
            assert(false);
            return windowType;

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return windowType;
    }
    ITAssertWithMessage(NO, @"Unknown window type %@", @(windowType));
    return WINDOW_TYPE_NORMAL;
}

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
            [iTermMigrationHelper recursiveMigrateBookmarks:[prefs objectForKey:KEY_DEPRECATED_BOOKMARKS] path:@[]];
            [prefs removeObjectForKey:KEY_DEPRECATED_BOOKMARKS];
            [prefs setObject:[[ProfileModel sharedInstance] rawData] forKey:KEY_NEW_BOOKMARKS];
            [[ProfileModel sharedInstance] removeAllBookmarks];
        }

        iTermProfilesMenuController *menuController = [[iTermProfilesMenuController alloc] init];
        [[ProfileModel sharedInstance] setMenuController:menuController];
        // Load new-style bookmarks.
        id newBookmarks = [prefs objectForKey:KEY_NEW_BOOKMARKS];
        NSString *originalDefaultGuid = [[prefs objectForKey:KEY_DEFAULT_GUID] copy];
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
            NSMutableDictionary *aDict = [[NSMutableDictionary alloc] init];
            [ITAddressBookMgr setDefaultsInBookmark:aDict];
            [[ProfileModel sharedInstance] addBookmark:aDict];
            [[ProfileModel sharedInstance] flush];
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

        [[iTermHotKeyMigrationHelper sharedInstance] migrateSingleHotkeyToMulti];
        [[iTermHotKeyProfileBindingController sharedInstance] refresh];
    }

    return self;
}

- (void)dealloc {
    [bonjourServices removeAllObjects];

    [sshBonjourBrowser stop];
    [ftpBonjourBrowser stop];
    [telnetBonjourBrowser stop];
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
    sshBonjourBrowser = nil;

    [ftpBonjourBrowser stop];
    ftpBonjourBrowser = nil;

    [telnetBonjourBrowser stop];
    telnetBonjourBrowser = nil;

    bonjourServices = nil;
}

+ (NSDictionary*)encodeColor:(NSColor*)origColor {
    return [origColor dictionaryValue];
}

+ (NSColor *)decodeColor:(NSDictionary*)plist {
    return [plist colorValue];
}

+ (NSFont *)fontWithDesc:(NSString *)fontDesc {
    return [fontDesc fontValue];
}

- (void)setBookmarks:(NSArray *)newBookmarksArray defaultGuid:(NSString *)guid {
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
    NSMutableArray *toRemove = [[NSMutableArray alloc] init];
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
    [aDict setObject:kProfilePreferenceCommandTypeLoginShellValue forKey:KEY_CUSTOM_COMMAND];
    [aDict setObject:@"" forKey: KEY_COMMAND_LINE];
    [aDict setObject:aName forKey: KEY_DESCRIPTION];
    [aDict setObject:kProfilePreferenceInitialDirectoryHomeValue
              forKey:KEY_CUSTOM_DIRECTORY];
    [aDict setObject:NSHomeDirectory() forKey: KEY_WORKING_DIRECTORY];
}

- (BOOL)usernameIsSafe:(NSString *)username {
    NSCharacterSet *unsafeSet = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz_1234567890"] invertedSet];
    const NSRange range = [username rangeOfCharacterFromSet:unsafeSet
                                                    options:NSCaseInsensitiveSearch];
    return range.location == NSNotFound;
}

- (void)_addBonjourHostProfileWithName:(NSString *)serviceName
                       ipAddressString:(NSString *)address
                                  port:(int)port
                           serviceType:(NSString *)serviceType
                              userName:(NSString *)username {
    NSArray<NSString *> *allowedServices = @[ @"ssh", @"scp", @"sftp" ];
    if (![allowedServices containsObject:serviceType]) {
        return;
    }

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
    NSString *userNameArg = @"";
    NSString *destination = address;
    if (username.length > 0 && [self usernameIsSafe:username]) {
        if ([serviceType isEqualToString:@"ssh"]) {
            userNameArg = [NSString stringWithFormat:@"-l %@ ", username];
        } else {
            destination = [NSString stringWithFormat:@"%@@%@", username, address];
        }
    }
    [newBookmark setObject:[NSString stringWithFormat:@"%@ %@%@%@", serviceType, userNameArg, optionalPortArg, destination]
                    forKey:KEY_COMMAND_LINE];
    [newBookmark setObject:@"" forKey:KEY_WORKING_DIRECTORY];
    [newBookmark setObject:kProfilePreferenceCommandTypeCustomValue forKey:KEY_CUSTOM_COMMAND];
    [newBookmark setObject:kProfilePreferenceInitialDirectoryHomeValue
                    forKey:KEY_CUSTOM_DIRECTORY];
    [newBookmark setObject:destination forKey:KEY_BONJOUR_SERVICE_ADDRESS];
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

- (NSString *)usernameFromTXTRecord:(NSData *)txtData {
    NSDictionary<NSString *, NSData *> *txtFields = [NSNetService dictionaryFromTXTRecordData:txtData];
    // https://kodi.wiki/view/Avahi_Zeroconf
    NSData *usernameData = txtFields[@"u"] ?: txtFields[@"username"];
    NSString *usernameString = [[NSString alloc] initWithData:usernameData encoding:NSUTF8StringEncoding];
    return usernameString;
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
        
        NSString *username = [self usernameFromTXTRecord:sender.TXTRecordData];
        [self _addBonjourHostProfileWithName:serviceName
                             ipAddressString:[NSString stringWithFormat:@"%s", strAddr]
                                        port:[self portFromSockaddr:socketAddress]
                                 serviceType:serviceType
                                    userName:username];

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

+ (NSString *)sanitizedCustomShell:(NSString *)customShell {
    NSArray<NSString *> *parts = [customShell componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([parts[0] length] == 0) {
        return nil;
    }
    return parts[0];
}

+ (NSString *)shellLauncherCommandWithCustomShell:(NSString *)customShell {
    NSString *sanitizedCustomShell = [self sanitizedCustomShell:customShell];
    NSString *customShellArg = sanitizedCustomShell ? [@" SHELL=" stringByAppendingString:sanitizedCustomShell] : @"";
    NSString *shellLauncher = [[NSBundle bundleForClass:self.class] pathForAuxiliaryExecutable:@"ShellLauncher"];

    return [NSString stringWithFormat:@"/usr/bin/login -f%@pl %@ %@ --launch_shell%@",
            [self hushlogin] ? @"q" : @"",
            [NSUserName() stringWithBackslashEscapedShellCharactersIncludingNewlines:YES],
            [shellLauncher stringWithBackslashEscapedShellCharactersIncludingNewlines:YES],
            customShellArg];
}

+ (NSString*)loginShellCommandForBookmark:(Profile*)profile
                            forObjectType:(iTermObjectType)objectType {
    NSString *customDirectoryString;
    if ([profile[KEY_CUSTOM_DIRECTORY] isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue]) {
        switch (objectType) {
            case iTermWindowObject:
                customDirectoryString = profile[KEY_AWDS_WIN_OPTION];
                break;
            case iTermTabObject:
                customDirectoryString = profile[KEY_AWDS_TAB_OPTION];
                break;
            case iTermPaneObject:
                customDirectoryString = profile[KEY_AWDS_PANE_OPTION];
                break;
            default:
                NSLog(@"Bogus object type %d", (int)objectType);
                customDirectoryString = kProfilePreferenceInitialDirectoryHomeValue;
        }
    } else {
        customDirectoryString = profile[KEY_CUSTOM_DIRECTORY];
    }

    if ([customDirectoryString isEqualToString:kProfilePreferenceInitialDirectoryHomeValue] &&
        [[self customShellForProfile:profile] length] == 0) {
        // Run login without -l argument: this is a login session and will use the home dir.
        return [self standardLoginCommand];
    } else {
        // Not using the home directory/default shell. This requires some trickery.
        // Run iTerm2's executable with a special flag that makes it run the shell as a login shell
        // (with "-" inserted at the start of argv[0]). See shell_launcher.c for more details.
        NSString *launchShellCommand = [self shellLauncherCommandWithCustomShell:[self customShellForProfile:profile]];
        return launchShellCommand;
    }
}

// See issue 4425 for why we do this.
+ (BOOL)hushlogin {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".hushlogin"];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSString *)standardLoginCommand {
    NSString *userName = NSUserName();
    // Active directory users have backslash in their user name (issue 6999)
    // Somehow, users can have spaces in their user name (issue 8360)
    //
    // Avoid using standard escaping which is wrong for a quoted string. I don't know why
    // this is in quotes, but I'm afraid to change it because it's been that way for so
    // long and the original commit message was lost.
    //
    // The returned value gets parsed into an argument array using -componentsInShellCommand
    // by computeArgvForCommand:substitutions:completion:.
    userName = [userName stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    userName = [userName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"login -f%@p \"%@\"", [self hushlogin] ? @"q" : @"",
            userName];
}

+ (void)computeCommandForProfile:(Profile *)profile
                      objectType:(iTermObjectType)objectType
                           scope:(iTermVariableScope *)scope
                      completion:(void (^)(NSString *, BOOL))completion {
    const BOOL ssh = [profile[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeSSHValue];
    const BOOL custom = [profile[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomValue];
    NSString *swifty = [self bookmarkCommandSwiftyString:profile forObjectType:objectType];
    if (!custom && !ssh) {
        DLog(@"Don't have a custom command. Computed command is %@", swifty);
        completion(swifty, ssh);
        return;
    }

    DLog(@"Must evaluate swifty string: %@", swifty);
    iTermExpressionEvaluator *evaluator =
    [[iTermExpressionEvaluator alloc] initWithStrictInterpolatedString:swifty
                                                                 scope:scope];
    [evaluator evaluateWithTimeout:5 completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        NSString *string = [NSString castFrom:evaluator.value];
        DLog(@"Evaluation finished with value %@", string);
        string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!string.length) {
            string = [ITAddressBookMgr loginShellCommandForBookmark:profile
                                                      forObjectType:objectType];
        }
        DLog(@"Finish with %@", string);
        completion(string, ssh);
    }];
}

+ (NSString *)bookmarkCommandSwiftyString:(Profile *)bookmark
                            forObjectType:(iTermObjectType)objectType {
    const BOOL custom = [bookmark[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomValue];
    const BOOL ssh = [bookmark[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeSSHValue];
    if (custom || ssh) {
        NSString *command = bookmark[KEY_COMMAND_LINE];
        if ([[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] ] length] > 0) {
            if (ssh) {
                NSString *wrappedCommand = [NSString stringWithFormat:@"%@ %@",
                                            iTermPathToSSH(),
                                            command];
                command = [NSString stringWithFormat:@"/usr/bin/login -fpq %@ %@ -c %@",
                           [NSUserName() stringWithBackslashEscapedShellCharactersIncludingNewlines:YES],
                           [iTermOpenDirectory userShell],
                           [wrappedCommand stringWithBackslashEscapedShellCharactersIncludingNewlines:YES]];
            }
            return command;
        }
    }
    return [ITAddressBookMgr loginShellCommandForBookmark:bookmark
                                            forObjectType:objectType];
}

+ (NSString *)customShellForProfile:(Profile *)profile {
    if (![profile[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomShellValue]) {
        return nil;
    }
    NSString *customShell = profile[KEY_COMMAND_LINE];
    customShell = [customShell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (customShell.length == 0) {
        return nil;
    }
    return customShell;
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

+ (BOOL)removeProfile:(NSDictionary *)profile fromModel:(ProfileModel *)model {
    NSString *guid = profile[KEY_GUID];
    DLog(@"Remove profile with guid %@...", guid);
    if ([model numberOfBookmarks] == 1) {
        DLog(@"Refusing to remove only profile");
        return NO;
    }

    DLog(@"Removing key bindings that reference the guid being removed");
    [self removeKeyMappingsReferringToGuid:guid];
    DLog(@"Removing profile from model");
    [model removeProfileWithGuid:guid];

    // Ensure all profile list views reload their data to avoid issue 4033.
    DLog(@"Posting profile was deleted notification");
    [self postNotificationName:kProfileWasDeletedNotification object:nil userInfo:nil];
    [model flush];
    return YES;
}

+ (void)removeKeyMappingsReferringToGuid:(NSString *)badRef {
    [iTermKeyMappings suppressNotifications:^{
        for (NSString* guid in [[ProfileModel sharedInstance] guids]) {
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
            profile = [iTermKeyMappings removeKeyMappingsReferencingGuid:badRef fromProfile:profile];
            if (profile) {
                [[ProfileModel sharedInstance] setBookmark:profile withGuid:guid];
            }
        }
        for (NSString* guid in [[ProfileModel sessionsInstance] guids]) {
            Profile* profile = [[ProfileModel sessionsInstance] bookmarkWithGuid:guid];
            profile = [iTermKeyMappings removeKeyMappingsReferencingGuid:badRef fromProfile:profile];
            if (profile) {
                [[ProfileModel sessionsInstance] setBookmark:profile withGuid:guid];
            }
        }
        [iTermKeyMappings removeKeyMappingsReferencingGuid:badRef fromProfile:nil];
    }];
    [self postNotificationName:kKeyBindingsChangedNotification object:nil userInfo:nil];
}

+ (void)postNotificationName:(NSString *)name object:(id)object userInfo:(id)userInfo {
    NSNotification *notification = [NSNotification notificationWithName:name object:object userInfo:userInfo];
    [self postNotification:notification];
}

+ (void)postNotification:(NSNotification *)notification {
    if (sDelayedNotifications) {
        for (NSNotification *existing in sDelayedNotifications) {
            if ([existing.name isEqualToString:notification.name] &&
                (existing.object == notification.object || [existing.object isEqual:notification.object]) &&
                (existing.userInfo == notification.userInfo || [existing.userInfo isEqual:notification.userInfo])) {
                // Already have a notification like this
                return;
            }
        }
        [sDelayedNotifications addObject:notification];
    } else {
        [[NSNotificationCenter defaultCenter] postNotification:notification];
    }
}

+ (void)performBlockWithCoalescedNotifications:(void (^)(void))block {
    if (!sDelayedNotifications) {
        sDelayedNotifications = [[NSMutableArray alloc] init];

        block();

        for (NSNotification *notification in sDelayedNotifications) {
            [[NSNotificationCenter defaultCenter] postNotification:notification];
        }
        sDelayedNotifications = nil;
    } else {
        block();
    }
}

// identifier is optional. Old shortcuts only have a title.
+ (BOOL)shortcutIdentifier:(NSString *)identifier title:(NSString *)title matchesItem:(NSMenuItem *)item {
    if (item.identifier && [identifier isEqualToString:item.identifier]) {
        return YES;
    }
    if (!identifier && [title isEqualToString:[item title]]) {
        return YES;
    }

    return NO;
}

@end
