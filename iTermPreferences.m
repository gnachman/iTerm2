//
//  iTermPreferences.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferences.h"

NSString *const kPreferenceKeyOpenBookmark = @"OpenBookmark";

@implementation iTermPreferences

+ (NSDictionary *)defaultValueMap {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ kPreferenceKeyOpenBookmark: @NO };
        [dict retain];
    }
    return dict;
}

+ (id)defaultObjectForKey:(NSString *)key {
    return [self defaultValueMap][key];
}

+ (BOOL)boolForKey:(NSString *)key {
    NSNumber *object = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!object) {
        object = [self defaultObjectForKey:key];
    }
    return [object boolValue];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
}

@end
