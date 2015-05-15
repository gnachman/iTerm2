//
//  SendTextTrigger.m
//  iTerm
//
//  Created by George Nachman on 9/24/11.
//

#import "SendTextTrigger.h"
#import "PTYSession.h"

@implementation SendTextTrigger

+ (NSString *)title
{
    return @"Send Text…";
}

- (BOOL)takesParameter
{
    return YES;
}

- (NSString *)paramPlaceholder
{
    return @"Enter text to send";
}


- (BOOL)performActionWithValues:(NSArray *)values inSession:(PTYSession *)aSession onString:(NSString *)string atAbsoluteLineNumber:(long long)absoluteLineNumber
{
    NSString *message = [self paramWithBackreferencesReplacedWithValues:values];
    [aSession writeTask:[message dataUsingEncoding:NSUTF8StringEncoding]];
    return YES;
}

@end
