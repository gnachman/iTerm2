//
//  BellTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BellTrigger.h"
#import "PTYSession.h"
#import "VT100Screen.h"

@implementation BellTrigger

+ (NSString *)title
{
    return @"Ring Bell";
}

- (BOOL)takesParameter
{
    return NO;
}

- (BOOL)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber
{
    [aSession.screen activateBell];
    return YES;
}

@end
