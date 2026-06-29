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
        [self setScriptErrorString:@"The Python API is not enabled."];
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

    NSString *appName = self.arguments[@"appName"] ?: @"An app";
    NSString *message = [NSString stringWithFormat:@"%@ requests a reusable API cookie.", appName];

    __weak __typeof(self) weakSelf = self;
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:message
                                                         style:kiTermAnnouncementViewStyleQuestion
                                                   withActions:@[ @"_24 Hours",
                                                                  @"Forever",
                                                                  @"Always Allow All Apps",
                                                                  @"Deny" ]
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
            [self logEntry:@"Reusable API cookie granted (24 hours) by Applescript."];
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
            [self logEntry:@"Permanent reusable API cookie granted by Applescript."];
            break;
        }
        case 2: {
            // Always allow all apps — disable automation auth.
            [iTermAPIHelper setRequireApplescriptAuth:NO window:nil];
            cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
            [self logEntry:@"Automation auth disabled. Single-use API cookie granted by Applescript."];
            break;
        }
        default: {
            // Deny or dismissed.
            [self setScriptErrorNumber:2];
            [self setScriptErrorString:@"User denied the reusable cookie request."];
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
