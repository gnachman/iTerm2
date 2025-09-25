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

- (void)it_openURL:(NSURL *)url style:(iTermOpenStyle)style {
    [self it_openURL:url configuration:[NSWorkspaceOpenConfiguration configuration] style:iTermOpenStyleTab];
}

- (void)it_openURL:(NSURL *)url
     configuration:(NSWorkspaceOpenConfiguration *)configuration
             style:(iTermOpenStyle)style {
    DLog(@"%@", url);
    if (!url) {
        return;
    }
    if (![@[ @"http", @"https", @"ftp"] containsObject:url.scheme]) {
        // The browser configured in advanced settings and the built-in browser don't handle this scheme.
        DLog(@"Non-web scheme");
        [self openURL:url configuration:configuration completionHandler:nil];
    }

    NSString *bundleID = [iTermAdvancedSettingsModel browserBundleID];

    if ([iTermAdvancedSettingsModel browserProfiles]) {
        if ([iTermBrowserMetadata.supportedSchemes containsObject:url.scheme]) {
            if ([iTermBrowserGateway browserAllowedCheckingIfNot:YES] &&
                ([bundleID isEqual:NSBundle.mainBundle.bundleIdentifier] || [self it_isDefaultAppForURL:url])) {
                // We are the default app. Skip all the machinery and open it directly.
                if ([self it_openURLLocally:url
                              configuration:configuration
                                  openStyle:style]) {
                    return;
                }
            }
            // This feature is new and this is the main way people will discover it. Sorry for the annoyance :(
            if ([self it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:url
                                                            configuration:configuration
                                                                    style:style]) {
                return;
            }
        }
    }

    if ([bundleID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
        // No custom app configured in advanced settings so use the systemwide default.
        DLog(@"Empty custom bundle ID “%@”", bundleID);
        return [self openURL:url configuration:configuration completionHandler:nil];
    }
    NSURL *appURL = [self URLForApplicationWithBundleIdentifier:bundleID];
    if (!appURL) {
        // The custom app configured in advanced settings isn't installed. Use the sytemwide default.
        DLog(@"No url for bundle ID %@", bundleID);
        return [self openURL:url configuration:configuration completionHandler:nil];
    }

    // Open with the advanced-settings-configured default browser.
    DLog(@"Open %@ with %@", url, appURL);
    [self openURLs:@[ url ]
withApplicationAtURL:appURL
     configuration:configuration
 completionHandler:^(NSRunningApplication * _Nullable app, NSError * _Nullable error) {
        if (error) {
            // That didn't work so just use the default browser
            return [self openURL:url configuration:configuration completionHandler:nil];
        }
    }];
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

- (BOOL)it_tryToOpenURLLocallyDespiteNotBeingDefaultBrowser:(NSURL *)url
                                              configuration:(NSWorkspaceOpenConfiguration *)configuration
                                                      style:(iTermOpenStyle)style {
    if (![iTermBrowserGateway browserAllowedCheckingIfNot:YES]) {
        if ([iTermBrowserGateway shouldOfferPlugin]) {
            switch ([iTermBrowserGateway upsell]) {
                case iTermTriStateTrue:
                    // User is downloading plugin. Return yes and you'll have to try again.
                    return YES;
                case iTermTriStateFalse:
                    // Use system browser.
                    return NO;
                case iTermTriStateOther:
                    // Cancel.
                    return YES;
            }
        } else {
            // Plugin not available, just use system browser.
            return NO;
        }
    }
    if ([iTermWarning showWarningWithTitle:@"iTerm2 can display web pages! Would you like to open this link in iTerm2?"
                                   actions:@[ @"Use Default Browser", @"Open in iTerm2"]
                                 accessory:nil
                                identifier:@"NoSyncOpenLinksInApp"
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                   heading:@"Open in iTerm2?"
                                    window:nil] == kiTermWarningSelection1) {
        return [self it_openURLLocally:url configuration:configuration openStyle:style];
    }
    return NO;
}

- (BOOL)it_openURLLocally:(NSURL *)url
            configuration:(NSWorkspaceOpenConfiguration *)configuration
                openStyle:(iTermOpenStyle)openStyle {
    return [[iTermController sharedInstance] openURL:url
                                           openStyle:openStyle
                                              select:configuration.activates];
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

- (void)it_revealInFinder:(NSString *)path {
    NSURL *finderURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.finder"];
    if (!finderURL) {
        DLog(@"Can't find Finder");
        return;
    }
    [[NSWorkspace sharedWorkspace] openURLs:@[ [NSURL fileURLWithPath:path] ]
                       withApplicationAtURL:finderURL
                              configuration:[NSWorkspaceOpenConfiguration configuration]
                          completionHandler:nil];
}

@end
