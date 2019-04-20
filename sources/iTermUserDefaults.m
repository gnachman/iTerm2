//
//  iTermUserDefaults.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "iTermUserDefaults.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

NSString *const kSelectionRespectsSoftBoundariesKey = @"Selection Respects Soft Boundaries";

static NSString *const iTermUserDefaultsKeySearchHistory = @"NoSyncSearchHistory";

@implementation iTermUserDefaults

static NSArray *iTermUserDefaultsGetTypedArray(Class objectClass, NSString *key) {
    return [[NSArray castFrom:[[NSUserDefaults standardUserDefaults] objectForKey:iTermUserDefaultsKeySearchHistory]] mapWithBlock:^id(id anObject) {
        return [objectClass castFrom:anObject];
    }];
}

static void iTermUserDefaultsSetTypedArray(Class objectClass, NSString *key, id value) {
    NSArray *array = [[NSArray castFrom:value] mapWithBlock:^id(id anObject) {
        return [objectClass castFrom:anObject];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:array forKey:key];
}

+ (NSArray<NSString *> *)searchHistory {
    return iTermUserDefaultsGetTypedArray([NSString class], iTermUserDefaultsKeySearchHistory) ?: @[];
}

+ (void)setSearchHistory:(NSArray<NSString *> *)objects {
    iTermUserDefaultsSetTypedArray([NSString class], iTermUserDefaultsKeySearchHistory, objects);
}

@end
