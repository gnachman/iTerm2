//
//  InteractiveScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "CoprocessTrigger.h"
#import "PTYSession.h"

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

- (BOOL)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber
{
    if (![aSession hasCoprocess]) {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:values];
        [self executeCommand:command inSession:aSession];
    }
    return YES;
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

- (BOOL)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber
{
    if (![aSession hasCoprocess]) {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:values];
        [self executeCommand:command inSession:aSession];
    }
    return YES;
}

@end
