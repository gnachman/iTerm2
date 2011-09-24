//
//  InteractiveScriptTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "InteractiveScriptTrigger.h"
#import "PTYsession.h"
#import "PTYtask.h"

@implementation InteractiveScriptTrigger

- (NSString *)title
{
    return @"Run Interactive Command…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)paramPlaceholder
{
    return @"Enter command to run";
}

- (void)executeCommand:(NSString *)command inSession:(PTYSession *)aSession
{
    NSMutableArray *taskArgs = [NSMutableArray array];
    [taskArgs addObject:@"-c"];
    [taskArgs addObject:command];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setArguments:taskArgs];
    [task setLaunchPath:@"/bin/sh"];
    NSPipe *inputPipe = [NSPipe pipe];
    [task setStandardInput:inputPipe];
    NSPipe *outputPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    [task launch];
    [[aSession SHELL] addCoprocess:task withInputPipe:inputPipe outputPipe:outputPipe];
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    NSString *command = [self paramWithBackreferencesReplacedWithValues:values];
    [self executeCommand:command inSession:aSession];
}

@end
