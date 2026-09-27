//
//  iTermRequestCookieCommand.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/20.
//

#import "iTermRequestCookieCommand.h"

#import "iTermAnnouncementViewController.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermAPIHelper.h"
#import "iTermController.h"
#import "iTermScriptHistory.h"
#import "iTermWebSocketCookieJar.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"

static NSString *const kReusableCookieAnnouncementIdentifier = @"ReusableCookieAnnouncement";

@implementation iTermRequestCookieCommand

- (id)performDefaultImplementation {
    if (![iTermAPIHelper isEnabled]) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:NSLocalizedStringWithDefaultValue(@"RequestCookie.PythonAPINotEnabled", nil, [NSBundle mainBundle], @"The Python API is not enabled.", @"AppleScript error shown when the Python API is disabled")];
        return nil;
    }

    BOOL reusable = [self.arguments[@"reusable"] boolValue];
    if (reusable) {
        [self suspendExecution];
        [self showReusableCookieAnnouncement];
        return nil;
    }

    return [self issueResultWithCookie:[[iTermWebSocketCookieJar sharedInstance] randomStringForCookie]];
}

#pragma mark - Reusable Cookie Flow

- (void)showReusableCookieAnnouncement {
    PTYSession *session = [self targetSession];
    if (!session) {
        // No session to show announcement in — fall back to single-use.
        [self resumeExecutionWithResult:[self issueResultWithCookie:[[iTermWebSocketCookieJar sharedInstance] randomStringForCookie]]];
        return;
    }

    NSString *appName = self.arguments[@"appName"] ?: NSLocalizedStringWithDefaultValue(@"RequestCookie.DefaultAppName", nil, [NSBundle mainBundle], @"An app", @"Fallback name for an unnamed app requesting an API cookie");
    NSString *message = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"RequestCookie.ReusableCookieMessage", nil, [NSBundle mainBundle], @"%@ requests a reusable API cookie.", @"Announcement title; %@ is the name of the app requesting a reusable API cookie"), appName];

    __weak __typeof(self) weakSelf = self;
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:message
                                                         style:kiTermAnnouncementViewStyleQuestion
                                                   withActions:@[ NSLocalizedStringWithDefaultValue(@"RequestCookie.Action24Hours", nil, [NSBundle mainBundle], @"_24 Hours", @"Button granting a reusable API cookie for 24 hours; leading underscore marks the keyboard shortcut"),
                                                                  NSLocalizedStringWithDefaultValue(@"RequestCookie.ActionForever", nil, [NSBundle mainBundle], @"Forever", @"Button granting a reusable API cookie that never expires"),
                                                                  NSLocalizedStringWithDefaultValue(@"RequestCookie.ActionAlwaysAllowAll", nil, [NSBundle mainBundle], @"Always Allow All Apps", @"Button to disable automation auth for all apps"),
                                                                  NSLocalizedStringWithDefaultValue(@"RequestCookie.ActionDeny", nil, [NSBundle mainBundle], @"Deny", @"Button to deny the reusable API cookie request") ]
                                                    completion:^(int selection) {
            [weakSelf handleReusableCookieSelection:selection];
        }];
    [session queueAnnouncement:announcement identifier:kReusableCookieAnnouncementIdentifier];
}

- (void)handleReusableCookieSelection:(int)selection {
    NSString *cookie = nil;
    switch (selection) {
        case 0: {
            // 24 hours.
            NSTimeInterval duration = 24 * 60 * 60;
            cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForReusableCookieWithDuration:duration];
            [self logEntry:NSLocalizedStringWithDefaultValue(@"RequestCookie.Log24Hours", nil, [NSBundle mainBundle], @"Reusable API cookie granted (24 hours) by Applescript.", @"Script history log entry when a 24-hour reusable cookie is granted")];
            break;
        }
        case 1: {
            // Forever — reusable with no expiration.
            cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
            // Remove the cookie from single-use tracking by adding a far-future expiration.
            // Actually, just use removeCookieExpiration after making it reusable.
            // Simpler: add it as reusable with a very long duration.
            [[iTermWebSocketCookieJar sharedInstance] removeCookie:cookie];
            cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForReusableCookieWithDuration:100 * 365.25 * 24 * 60 * 60];
            [self logEntry:NSLocalizedStringWithDefaultValue(@"RequestCookie.LogPermanent", nil, [NSBundle mainBundle], @"Permanent reusable API cookie granted by Applescript.", @"Script history log entry when a permanent reusable cookie is granted")];
            break;
        }
        case 2: {
            // Always allow all apps — disable automation auth.
            [iTermAPIHelper setRequireApplescriptAuth:NO window:nil];
            cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
            [self logEntry:NSLocalizedStringWithDefaultValue(@"RequestCookie.LogAuthDisabled", nil, [NSBundle mainBundle], @"Automation auth disabled. Single-use API cookie granted by Applescript.", @"Script history log entry when automation auth is disabled and a single-use cookie is granted")];
            break;
        }
        default: {
            // Deny or dismissed.
            [self setScriptErrorNumber:2];
            [self setScriptErrorString:NSLocalizedStringWithDefaultValue(@"RequestCookie.UserDenied", nil, [NSBundle mainBundle], @"User denied the reusable cookie request.", @"AppleScript error shown when the user denies a reusable API cookie request")];
            [self resumeExecutionWithResult:nil];
            return;
        }
    }

    [self resumeExecutionWithResult:[self issueResultWithCookie:cookie]];
}

#pragma mark - Helpers

- (NSString *)issueResultWithCookie:(NSString *)cookie {
    NSString *name = self.arguments[@"appName"];
    if (name) {
        NSString *key = [[NSUUID UUID] UUIDString];
        NSString *identifier = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
        iTermScriptHistoryEntry *entry = [[iTermScriptHistoryEntry alloc] initWithName:[@"\u2248" stringByAppendingString:name]
                                                                              fullPath:nil
                                                                            identifier:identifier
                                                                              relaunch:nil];
        [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
        return [NSString stringWithFormat:@"%@ %@", cookie, key];
    }
    return cookie;
}

- (void)logEntry:(NSString *)message {
    NSString *name = self.arguments[@"appName"];
    if (!name) {
        return;
    }
    NSString *key = [[NSUUID UUID] UUIDString];
    NSString *identifier = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistoryEntry alloc] initWithName:[@"\u2248" stringByAppendingString:name]
                                                                          fullPath:nil
                                                                        identifier:identifier
                                                                          relaunch:nil];
    [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
    [entry addOutput:message completion:^{}];
}

- (PTYSession *)targetSession {
    NSString *sessionId = self.arguments[@"sessionId"];
    if (sessionId) {
        NSRange colonRange = [sessionId rangeOfString:@":"];
        NSString *guid = colonRange.location != NSNotFound
            ? [sessionId substringFromIndex:colonRange.location + 1]
            : sessionId;
        PTYSession *session = [[iTermAPIHelper sharedInstance] sessionForAPIIdentifier:guid
                                                                includeBuriedSessions:NO];
        if (session) {
            return session;
        }
    }
    return [[[iTermController sharedInstance] currentTerminal] currentSession];
}

@end
