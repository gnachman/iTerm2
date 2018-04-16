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
    static dispatch_once_t onceToken;
    static BOOL result;
    dispatch_once(&onceToken, ^{
        NSString *testingFeed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"];
        result = [testingFeed containsString:@"nightly"];
    });
    return result;
}

+ (BOOL)it_isEarlyAdopter {
    NSString *testingFeed = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"];
    return [testingFeed containsString:@"testing3.xml"];
}

+ (NSDate *)it_buildDate {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    [dateFormatter setDateFormat:@"LLL d yyyy HH:mm:ss v"];
    NSString *string = [NSString stringWithFormat:@"%s %s PT", __DATE__, __TIME__];
    return [dateFormatter dateFromString:string];
}

@end
