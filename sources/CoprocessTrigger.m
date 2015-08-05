//
//  InteractiveScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "CoprocessTrigger.h"
#import "iTermAnnouncementViewController.h"
#import "PTYSession.h"

static NSString *const kSuppressCoprocessTriggerWarning = @"NoSyncSuppressCoprocessTriggerWarning";

@implementation CoprocessTrigger

+ (NSString *)title
{
    return @"Run Coprocess…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)paramPlaceholder
{
    return @"Enter coprocess command to run";
}

- (void)executeCommand:(NSString *)command inSession:(PTYSession *)aSession
{
    [aSession launchCoprocessWithCommand:command];
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    if ([aSession hasCoprocess]) {
        [self.class showCoprocessAnnouncementInSession:aSession];
    } else {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                      count:captureCount];
        [self executeCommand:command inSession:aSession];
    }
    return YES;
}

+ (void)showCoprocessAnnouncementInSession:(PTYSession *)aSession {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCoprocessTriggerWarning]) {
        [aSession retain];
        void (^completion)(int selection) = ^(int selection) {
            switch (selection) {
                case -2:
                    [aSession release];
                    break;

                case 0:
                    [[NSUserDefaults standardUserDefaults] setBool:YES
                                                            forKey:kSuppressCoprocessTriggerWarning];
                    break;
            }
        };
        NSString *title = @"A Coprocess trigger fired but could not run because a coprocess is already running.";
        iTermAnnouncementViewController *announcement =
            [iTermAnnouncementViewController announcementWithTitle:title
                                                             style:kiTermAnnouncementViewStyleWarning
                                                       withActions:@[ @"Silence Warning" ]
                                                        completion:completion];
        [aSession queueAnnouncement:announcement
                         identifier:kSuppressCoprocessTriggerWarning];
    }
}

@end

@implementation MuteCoprocessTrigger

+ (NSString *)title
{
    return @"Run Silent Coprocess…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)paramPlaceholder
{
    return @"Enter coprocess command to run";
}

- (void)executeCommand:(NSString *)command inSession:(PTYSession *)aSession
{
    [aSession launchSilentCoprocessWithCommand:command];
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    if ([aSession hasCoprocess]) {
        [CoprocessTrigger showCoprocessAnnouncementInSession:aSession];
    } else {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                      count:captureCount];
        [self executeCommand:command inSession:aSession];
    }
    return YES;
}

@end
