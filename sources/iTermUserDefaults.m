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
static NSString *const iTermSecureKeyboardEntryEnabledUserDefaultsKey = @"Secure Input";
// Set to YES after warning the user about respecting the dock setting to prefer tabs over windows.
static NSString *const kPreferenceKeyHaveBeenWarnedAboutTabDockSetting = @"NoSyncHaveBeenWarnedAboutTabDockSetting";

static NSString *const iTermUserDefaultsKeySearchHistory = @"NoSyncSearchHistory";
static NSString *const iTermUserDefaultsKeyEnableAutomaticProfileSwitchingLogging = @"NoSyncEnableAutomaticProfileSwitchingLogging";

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

+ (BOOL)secureKeyboardEntry {
    return [[NSUserDefaults standardUserDefaults] boolForKey:iTermUserDefaultsKeySearchHistory];
}

+ (void)setSecureKeyboardEntry:(BOOL)secureKeyboardEntry {
    [[NSUserDefaults standardUserDefaults] setBool:secureKeyboardEntry
                                            forKey:iTermUserDefaultsKeySearchHistory];
}

+ (iTermAppleWindowTabbingMode)appleWindowTabbingMode {
    static NSUserDefaults *globalDomain;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We overwrite this key in the app domain to fool Cocoa, so we need to
        // read it from the global domain. You can't create an instance of
        // NSUserDefaults with the suite NSGlobalDefaults because AppKit is not
        // good, so instead we have to lie to it.
        globalDomain = [[NSUserDefaults alloc] initWithSuiteName:@"com.iterm2.fake"];
    });
    NSString *value = [globalDomain objectForKey:@"AppleWindowTabbingMode"];
    if ([value isEqualToString:@"always"]) {
        return iTermAppleWindowTabbingModeAlways;
    }
    if ([value isEqualToString:@"manual"]) {
        return iTermAppleWindowTabbingModeManual;
    }
    return iTermAppleWindowTabbingModeFullscreen;
}

+ (BOOL)haveBeenWarnedAboutTabDockSetting {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kPreferenceKeyHaveBeenWarnedAboutTabDockSetting];
}

+ (void)setHaveBeenWarnedAboutTabDockSetting:(BOOL)haveBeenWarnedAboutTabDockSetting {
    [[NSUserDefaults standardUserDefaults] setBool:haveBeenWarnedAboutTabDockSetting forKey:kPreferenceKeyHaveBeenWarnedAboutTabDockSetting];
}

+ (BOOL)enableAutomaticProfileSwitchingLogging {
    return [[NSUserDefaults standardUserDefaults] boolForKey:iTermUserDefaultsKeyEnableAutomaticProfileSwitchingLogging];
}

+ (void)setEnableAutomaticProfileSwitchingLogging:(BOOL)enableAutomaticProfileSwitchingLogging {
    [[NSUserDefaults standardUserDefaults] setBool:enableAutomaticProfileSwitchingLogging
                                            forKey:iTermUserDefaultsKeyEnableAutomaticProfileSwitchingLogging];
}

@end
