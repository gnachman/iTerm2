//
//  iTermPreferences.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferences.h"
#import "WindowArrangements.h"

#define BLOCK(x) [^id() { return [self x]; } copy]

NSString *const kPreferenceKeyOpenBookmark = @"OpenBookmark";
NSString *const kPreferenceKeyOpenArrangementAtStartup = @"OpenArrangementAtStartup";
NSString *const kPreferenceKeyQuitWhenAllWindowsClosed = @"QuitWhenAllWindowsClosed";

@implementation iTermPreferences

#pragma mark - Default values

+ (NSDictionary *)defaultValueMap {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ kPreferenceKeyOpenBookmark: @NO,
                  kPreferenceKeyOpenArrangementAtStartup: @NO,
                  kPreferenceKeyQuitWhenAllWindowsClosed: @NO };
        [dict retain];
    }
    return dict;
}

+ (id)defaultObjectForKey:(NSString *)key {
    return [self defaultValueMap][key];
}

#pragma mark - Computed values

// Returns a dictionary from key to a ^id() block. The block will return an object value for the
// preference or nil if the normal path (of taking the NSUserDefaults value or +defaultObjectForKey)
// should be used.
+ (NSDictionary *)computedObjectDictionary {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ kPreferenceKeyOpenArrangementAtStartup: BLOCK(computedOpenArrangementAtStartup) };
        [dict retain];
    }
    return dict;
}

+ (id)computedObjectForKey:(NSString *)key {
    id (^block)() = [self computedObjectDictionary][key];
    if (block) {
        return block();
    } else {
        return nil;
    }
}

#pragma mark - APIs

+ (BOOL)keyHasDefaultValue:(NSString *)key {
    return [self defaultObjectForKey:key] != nil;
}

+ (BOOL)boolForKey:(NSString *)key {
    NSNumber *object;
    object = [self computedObjectForKey:key];
    if (!object) {
        object = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    }
    if (!object) {
        object = [self defaultObjectForKey:key];
    }
    return [object boolValue];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
}

#pragma mark - Value Computation Methods

+ (NSNumber *)computedOpenArrangementAtStartup {
    if ([WindowArrangements count] == 0) {
        return @NO;
    } else {
        return nil;
    }
}

@end
