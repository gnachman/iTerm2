//
//  NSWorkspace+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "NSWorkspace+iTerm.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"
#import "iTermWarning.h"

@implementation NSWorkspace (iTerm)

- (NSString *)temporaryFileNameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
    NSString *template = [NSString stringWithFormat:@"%@XXXXXX%@", prefix ?: @"", suffix ?: @""];
    NSString *tempFileTemplate =
    [NSTemporaryDirectory() stringByAppendingPathComponent:template];
    const char *tempFileTemplateCString =
    [tempFileTemplate fileSystemRepresentation];
    char *tempFileNameCString = (char *)iTermMalloc(strlen(tempFileTemplateCString) + 1);
    strcpy(tempFileNameCString, tempFileTemplateCString);
    int fileDescriptor = mkstemps(tempFileNameCString, suffix.length);

    if (fileDescriptor == -1) {
        XLog(@"mkstemps failed with template %s: %s", tempFileNameCString, strerror(errno));
        free(tempFileNameCString);
        return nil;
    }
    close(fileDescriptor);
    NSString *filename = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString
                                                                                     length:strlen(tempFileNameCString)];
    free(tempFileNameCString);
    return filename;
}

- (BOOL)it_securityAgentIsActive {
    NSRunningApplication *activeApplication = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *bundleIdentifier = activeApplication.bundleIdentifier;
    return [bundleIdentifier isEqualToString:@"com.apple.SecurityAgent"];
}

- (BOOL)it_openURL:(NSURL *)url {
    return [self it_openURL:url options:0];
}

- (BOOL)it_openURL:(NSURL *)url options:(NSWorkspaceLaunchOptions)options {
    DLog(@"%@", url);
    if (!url) {
        return NO;
    }
    if (![@[ @"http", @"https", @"ftp"] containsObject:url.scheme]) {
        // The browser configured in advanced settings and the built-in browser don't handle this scheme.
        DLog(@"Non-web scheme");
        NSError *error = nil;
        return [self openURL:url options:options configuration:@{} error:&error];
    }

    NSString *bundleID = [iTermAdvancedSettingsModel browserBundleID];

    if ([iTermAdvancedSettingsModel browserProfiles]) {
        if (@available(macOS 11, *)) {
            if ([iTermBrowserMetadata.supportedSchemes containsObject:url.scheme]) {
                if ([bundleID isEqual:NSBundle.mainBundle.bundleIdentifier] || [self it_isDefaultAppForURL:url]) {
                    // We are the default app. Skip all the machinery and open it directly.
                    if ([self it_openURLLocally:url options:options]) {
                        return YES;
                    }
                }
                // This feature is new and this is the main way people will discover it. Sorry for the annoyance :(
                if ([self it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:url options:options]) {
                    return YES;
                }
            }
        }
    }

    if ([bundleID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
        // No custom app configured in advanced settings so use the systemwide default.
        DLog(@"Empty custom bundle ID “%@”", bundleID);
        NSError *error = nil;
        return [self openURL:url options:options configuration:@{} error:&error];
    }
    NSURL *appURL = [self URLForApplicationWithBundleIdentifier:bundleID];
    if (!appURL) {
        // The custom app configured in advanced settings isn't installed. Use the sytemwide default.
        DLog(@"No url for bundle ID %@", bundleID);
        NSError *error = nil;
        return [self openURL:url options:options configuration:@{} error:&error];
    }

    // Open with the advanced-settings-configured default browser.
    DLog(@"Open %@ with %@", url, appURL);
    NSError *error = nil;
    [self openURLs:@[ url ] withApplicationAtURL:appURL options:options configuration:@{} error:&error];
    DLog(@"%@", error);

    if (error) {
        // That didn't work so just use the default browser
        NSError *error = nil;
        return [self openURL:url options:options configuration:@{} error:&error];
    }
    return YES;
}

- (BOOL)it_isDefaultAppForURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    // Ask NSWorkspace for the app that would open it
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:url];

    // Extract its bundle ID
    if (appURL != nil) {
        NSBundle *bundle = [NSBundle bundleWithURL:appURL];
        NSString *bundleID = bundle.bundleIdentifier;
        return [bundleID isEqual:NSBundle.mainBundle.bundleIdentifier];
    }
    return NO;
}

- (BOOL)it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:(NSURL *)url options:(NSWorkspaceLaunchOptions)options {
    if ([iTermWarning showWarningWithTitle:@"iTerm2 can display web pages! Would you like to open this link in iTem2?"
                                   actions:@[ @"Use Default Browser", @"Open in iTerm2"]
                                 accessory:nil
                                identifier:@"NoSyncOpenLinksInApp"
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:@"Open in iTerm2?"
                                    window:nil] == kiTermWarningSelection1) {
        return [self it_openURLLocally:url options:options];
    }
    return NO;
}

- (BOOL)it_openURLLocally:(NSURL *)url options:(NSWorkspaceLaunchOptions)options {
    return [[iTermController sharedInstance] openURLInNewBrowserTab:url
                                                          selectTab:(options & NSWorkspaceLaunchWithoutActivation) == 0];
}

static NSMutableSet<NSString * > *urlTokens;

- (NSString *)it_newToken {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        urlTokens = [NSMutableSet set];
    });
    NSString *token = [[NSUUID UUID] UUIDString];
    [urlTokens addObject:token];
    return token;
}

- (BOOL)it_checkToken:(NSString *)token {
    if (![urlTokens containsObject:token]) {
        return NO;
    }
    [urlTokens removeObject:token];
    return YES;
}

@end
