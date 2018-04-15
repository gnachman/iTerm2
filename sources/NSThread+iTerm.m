//
//  NSThread+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/18.
//

#import "NSThread+iTerm.h"
#import "NSArray+iTerm.h"

@implementation NSThread (iTerm)

+ (NSArray<NSString *> *)trimCallStackSymbols {
    return [[self callStackSymbols] filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return [anObject containsString:@" iTerm2 "];
    }];
}

@end
