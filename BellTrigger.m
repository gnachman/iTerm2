//
//  BellTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BellTrigger.h"


@implementation BellTrigger

- (NSString *)title
{
    return @"Ring Bell";
}

- (BOOL)takesParameter
{
    return NO;
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    NSBeep();
}

@end
