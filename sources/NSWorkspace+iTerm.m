//
//  NSWorkspace+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "NSWorkspace+iTerm.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermMalloc.h"

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
    DLog(@"%@", url);
    if (!url) {
        return NO;
    }
    if (![@[ @"http", @"https", @"ftp"] containsObject:url.scheme]) {
        DLog(@"Non-web scheme");
        return [self openURL:url];
    }
    NSString *bundleID = [iTermAdvancedSettingsModel browserBundleID];
    if ([bundleID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
        DLog(@"Empty custom bundle ID “%@”", bundleID);
        return [self openURL:url];
    }
    NSURL *appURL = [self URLForApplicationWithBundleIdentifier:bundleID];
    if (!appURL) {
        DLog(@"No url for bundle ID %@", bundleID);
        return [self openURL:url];
    }

    DLog(@"Open %@ with %@", url, appURL);
    NSError *error = nil;
    [self openURLs:@[ url ] withApplicationAtURL:appURL options:0 configuration:@{} error:&error];
    DLog(@"%@", error);
    if (error) {
        return [self openURL:url];
    }
    return YES;
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
