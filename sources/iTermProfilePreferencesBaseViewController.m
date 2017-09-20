//
//  iTermProfilePreferencesBaseViewController.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"
#import "iTermProfilePreferences.h"

@implementation iTermProfilePreferencesBaseViewController

- (void)setObjectsFromDictionary:(NSDictionary *)dictionary {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setObjectsFromDictionary:dictionary inProfile:profile model:model];
}

- (NSObject *)objectForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences objectForKey:key inProfile:profile];
}

- (void)setObject:(NSObject *)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setObject:value forKey:key inProfile:profile model:model];
}

- (BOOL)boolForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences boolForKey:key inProfile:profile];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setBool:value forKey:key inProfile:profile model:model];
}

- (int)intForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences intForKey:key inProfile:profile];
}

- (void)setInt:(int)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setInt:value forKey:key inProfile:profile model:model];
}

- (NSInteger)integerForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences integerForKey:key inProfile:profile];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setInteger:value forKey:key inProfile:profile model:model];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences unsignedIntegerForKey:key inProfile:profile];
}

- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setUnsignedInteger:value forKey:key inProfile:profile model:model];
}

- (double)floatForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences floatForKey:key inProfile:profile];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setFloat:value forKey:key inProfile:profile model:model];
}

- (double)doubleForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences doubleForKey:key inProfile:profile];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setDouble:value forKey:key inProfile:profile model:model];
}

- (NSString *)stringForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences stringForKey:key inProfile:profile];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setString:value forKey:key inProfile:profile model:model];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)(void))update {
    assert(self.delegate);
    return [super defineControl:control
                            key:key
                           type:type
                 settingChanged:settingChanged
                         update:update];
}

- (BOOL)shouldUpdateOtherPanels {
    return [self.delegate profilePreferencesCurrentModel] == [ProfileModel sharedInstance];
}

- (BOOL)keyHasDefaultValue:(NSString *)key {
    return [iTermProfilePreferences keyHasDefaultValue:key];
}

- (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type {
    return [iTermProfilePreferences defaultValueForKey:key isCompatibleWithType:type];
}

- (void)willReloadProfile {
}

- (void)reloadProfile {
    for (NSControl *control in self.keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        [self updateValueForInfo:info];
    }
}

@end
