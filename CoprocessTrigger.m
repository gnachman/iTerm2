//
//  InteractiveScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "CoprocessTrigger.h"
#import "PTYsession.h"

@implementation CoprocessTrigger

- (NSString *)title
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

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    if (![aSession hasCoprocess]) {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:values];
        [self executeCommand:command inSession:aSession];
    }
}

@end
