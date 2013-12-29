//
//  NSDictionary+iTerm.m
//  iTerm
//
//  Created by George Nachman on 1/2/14.
//
//

#import "NSDictionary+iTerm.h"

@implementation NSDictionary (iTerm)

- (BOOL)boolValueDefaultingToYesForKey:(id)key
{
    id object = [self objectForKey:key];
    if (object) {
        return [object boolValue];
    } else {
        return YES;
    }
}

@end
