//
//  NSBundle+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 6/29/17.
//
//

#import "NSBundle+iTerm.h"

@implementation NSBundle (iTerm)

+ (BOOL)it_isNightlyBuild {
    NSString *testingFeed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"];
    return [testingFeed containsString:@"nightly"];
}

+ (BOOL)it_isEarlyAdopter {
    NSString *testingFeed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"];
    return [testingFeed containsString:@"testing3.xml"];
}

@end
