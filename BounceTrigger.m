//
//  BounceTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "BounceTrigger.h"


@implementation BounceTrigger

- (NSString *)title
{
    return @"Bounce Dock Icon";
}

- (BOOL)takesParameter
{
    return NO;
}

- (void)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession
{
    [NSApp requestUserAttention:NSCriticalRequest];
}

@end
