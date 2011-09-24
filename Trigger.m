//
//  Trigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "Trigger.h"
#import "RegexKitLite.h"

NSString * const kTriggerRegexKey = @"regex";
NSString * const kTriggerActionKey = @"action";
NSString * const kTriggerParameterKey = @"parameter";

@implementation Trigger

@synthesize regex = regex_;
@synthesize action = action_;
@synthesize param = param_;

+ (Trigger *)triggerFromDict:(NSDictionary *)dict
{
    NSString *className = [dict objectForKey:kTriggerActionKey];
    Class class = NSClassFromString(className);
    Trigger *trigger = [[class alloc] init];
    trigger.regex = [dict objectForKey:kTriggerRegexKey];
    trigger.param = [dict objectForKey:kTriggerParameterKey];
    return trigger;
}

- (NSString *)action
{
    return NSStringFromClass([self class]);
}

- (NSString *)title
{
    assert(false);
}

- (BOOL)takesParameter
{
    assert(false);
}

- (void)dealloc {
    [regex_ release];
    [action_ release];
    [param_ release];
    
    [super dealloc];
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    assert(false);
}

- (void)tryString:(NSString *)s inSession:(PTYSession *)aSession
{
    NSRange range = [s rangeOfRegex:regex_];
    if (range.location != NSNotFound) {
        NSArray *captures = [s arrayOfCaptureComponentsMatchedByRegex:regex_];
        for (NSArray *matches in captures) {
            [self performActionWithValues:matches
                                inSession:aSession];
        }
    }
}

- (NSString *)paramWithBackreferencesReplacedWithValues:(NSArray *)values
{
    NSString *p = self.param;
    for (int i = 0; i < 9; i++) {
        NSString *rep = @"";
        if (values.count > i) {
            rep = [values objectAtIndex:i];
        }
        p = [p stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"\\%d", i]
                                         withString:rep];
    }
    return p;
}

@end
