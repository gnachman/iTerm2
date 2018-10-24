//
//  iTermFullDiskAccessManager.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/20/18.
//

#import "iTermFullDiskAccessManager.h"

#import "NSFileManager+iTerm.h"
#import <Cocoa/Cocoa.h>
#include <dirent.h>

@implementation iTermFullDiskAccessManager

+ (BOOL)haveRequestedFullDiskAccess NS_AVAILABLE_MAC(10_14) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"NoSyncHaveRequestedFullDiskAccess"];
}

+ (BOOL)lacksFullDiskAccess NS_AVAILABLE_MAC(10_14) {
    NSString *library = [[NSFileManager defaultManager] libraryDirectoryFor:nil];
    DIR *d = opendir(library.UTF8String);
    if (d == NULL) {
        return NO;
    }
    closedir(d);

    NSString *path = [[NSFileManager defaultManager] libraryDirectoryFor:@"Safari"];
    d = opendir(path.UTF8String);
    if (d == NULL && errno == EPERM) {
        return YES;
    }

    closedir(d);
    return NO;
}

+ (void)maybeRequestFullDiskAccess NS_AVAILABLE_MAC(10_14) {
    if (![self haveRequestedFullDiskAccess] && [self lacksFullDiskAccess]) {
        [self reallyRequestFullDiskAccess];
    }
}

+ (void)reallyRequestFullDiskAccess NS_AVAILABLE_MAC(10_14) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Full Disk Access";
    alert.informativeText = @"iTerm2 requires full disk access for some programs (such as crontab) to work correctly.\n"
    @"To grant access:\n\n"
    @"1. Go to System Preferences > Security & Privacy.\n"
    @"2. Select Full Disk Access on the left.\n"
    @"3. Add iTerm2 to the list of apps on the right.";
    [alert addButtonWithTitle:@"Open System Preferences"];
    [alert addButtonWithTitle:@"Learn More"];
    [alert addButtonWithTitle:@"Remind Me Later"];
    [alert addButtonWithTitle:@"Never Ask Again"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NoSyncHaveRequestedFullDiskAccess"];
        [self openSystemPreferencesToSecurityAndPrivacy];
    } else if (response == NSAlertSecondButtonReturn) {
        [self openFullDiskAccessDocs];
    } else if (response == NSAlertFirstButtonReturn + 3) {
        return [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NoSyncHaveRequestedFullDiskAccess"];
    }
}

+ (void)openSystemPreferencesToSecurityAndPrivacy NS_AVAILABLE_MAC(10_14) {
    NSURL *url = [NSURL fileURLWithPath:@"/System/Library/PreferencePanes/Security.prefPane"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

+ (void)openFullDiskAccessDocs NS_AVAILABLE_MAC(10_14) {
    NSURL *url = [NSURL URLWithString:@"https://iterm2.com/full-disk-access"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
