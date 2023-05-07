//
//  iTermUserDefaults.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "iTermUserDefaults.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"

NSString *const kSelectionRespectsSoftBoundariesKey = @"Selection Respects Soft Boundaries";
static NSString *const iTermSecureKeyboardEntryEnabledUserDefaultsKey = @"Secure Input";
// Set to YES after warning the user about respecting the dock setting to prefer tabs over windows.
static NSString *const kPreferenceKeyHaveBeenWarnedAboutTabDockSetting = @"NoSyncHaveBeenWarnedAboutTabDockSetting";

static NSString *const iTermUserDefaultsKeyBuggySecureKeyboardEntry = @"NoSyncSearchHistory";  // DEPRECATED - See issue 8118
static NSString *const iTermUserDefaultsKeySearchHistory = @"NoSyncSearchHistory2";

static NSString *const iTermUserDefaultsKeyEnableAutomaticProfileSwitchingLogging = @"NoSyncEnableAutomaticProfileSwitchingLogging";

static NSString *const iTermUserDefaultsKeyRequireAuthenticationAfterScreenLocks = @"RequireAuthenticationAfterScreenLocks";
static NSString *const iTermUserDefaultsKeyOpenTmuxDashboardIfHiddenWindows = @"OpenTmuxDashboardIfHiddenWindows";
static NSString *const iTermUserDefaultsKeyHaveExplainedHowToAddTouchbarControls = @"NoSyncHaveExplainedHowToAddTouchbarControls";
static NSString *const iTermUserDefaultsKeyIgnoreSystemWindowRestoration = @"NoSyncIgnoreSystemWindowRestoration";
static NSString *const iTermUserDefaultsKeyGlobalSearchMode = @"NoSyncGlobalSearchMode";
static NSString *const iTermUserDefaultsKeyAddTriggerInstant = @"NoSyncAddTriggerInstant";
static NSString *const iTermUserDefaultsKeyAddTriggerUpdateProfile = @"NoSyncAddTriggerUpdateProfile";
static NSString *const iTermUserDefaultsKeyLastSystemPythonVersionRequirement = @"NoSyncLastSystemPythonVersionRequirement";
static NSString *const iTermUserDefaultsKeyProbeForPassword = @"ProbeForPassword";
static NSString *const iTermUserDefaultsKeyImportPath = @"ImportPath";

@implementation iTermUserDefaults

static NSArray *iTermUserDefaultsGetTypedArray(NSUserDefaults *userDefaults, Class objectClass, NSString *key) {
    return [[NSArray castFrom:[userDefaults objectForKey:iTermUserDefaultsKeySearchHistory]] mapWithBlock:^id(id anObject) {
        return [objectClass castFrom:anObject];
    }];
}

static void iTermUserDefaultsSetTypedArray(NSUserDefaults *userDefaults, Class objectClass, NSString *key, id value) {
    NSArray *array = [[NSArray castFrom:value] mapWithBlock:^id(id anObject) {
        return [objectClass castFrom:anObject];
    }];
    [userDefaults setObject:array forKey:key];
}

static NSUserDefaults *iTermPrivateUserDefaults(void) {
    static dispatch_once_t onceToken;
    static NSUserDefaults *privateUserDefaults;
    dispatch_once(&onceToken, ^{
        privateUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.googlecode.iterm2.private"];
    });
    return privateUserDefaults;
}

+ (NSUserDefaults *)userDefaults {
    static NSUserDefaults *userDefaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults registerDefaults:@{ iTermUserDefaultsKeyOpenTmuxDashboardIfHiddenWindows: @YES }];
    });
    return userDefaults;
}

+ (void)performMigrations {
    id obj = [self.userDefaults objectForKey:iTermUserDefaultsKeySearchHistory];
    if (!obj) {
        return;
    }
    [self setSearchHistory:obj];
    [self.userDefaults removeObjectForKey:iTermUserDefaultsKeySearchHistory];

    id maybeSearchHistory = [self.userDefaults objectForKey:iTermUserDefaultsKeyBuggySecureKeyboardEntry];
    if (maybeSearchHistory && ![maybeSearchHistory isKindOfClass:[NSNumber class]]) {
        [self.userDefaults removeObjectForKey:iTermUserDefaultsKeyBuggySecureKeyboardEntry];
    }
}

+ (NSArray<NSString *> *)searchHistory {
    return iTermUserDefaultsGetTypedArray(iTermPrivateUserDefaults(), [NSString class], iTermUserDefaultsKeySearchHistory) ?: @[];
}

+ (void)setSearchHistory:(NSArray<NSString *> *)objects {
    iTermUserDefaultsSetTypedArray(iTermPrivateUserDefaults(), [NSString class], iTermUserDefaultsKeySearchHistory, objects);
}

+ (BOOL)secureKeyboardEntry {
    NSNumber *buggy = [NSNumber castFrom:[self.userDefaults objectForKey:iTermUserDefaultsKeyBuggySecureKeyboardEntry]];
    if (buggy) {
        // If the buggy one exists and is a number, then it was your secure keyboard setting as
        // written by version 3.3.0 or 3.3.1. Prefer it because updating the secure keyboard entry
        // setting in 3.3.2 or later will remove the buggy value.
        // If it exists and is not a number then it may have been set in an earlier
        // (non-buggy) version.
        return [buggy boolValue];
    }
    return [self.userDefaults boolForKey:iTermSecureKeyboardEntryEnabledUserDefaultsKey];
}

+ (void)setSecureKeyboardEntry:(BOOL)secureKeyboardEntry {
    // See comment in +secureKeyboardEntry.
    [self.userDefaults removeObjectForKey:iTermUserDefaultsKeyBuggySecureKeyboardEntry];
    [self.userDefaults setBool:secureKeyboardEntry
                        forKey:iTermSecureKeyboardEntryEnabledUserDefaultsKey];
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
    return [self.userDefaults boolForKey:kPreferenceKeyHaveBeenWarnedAboutTabDockSetting];
}

+ (void)setHaveBeenWarnedAboutTabDockSetting:(BOOL)haveBeenWarnedAboutTabDockSetting {
    [self.userDefaults setBool:haveBeenWarnedAboutTabDockSetting forKey:kPreferenceKeyHaveBeenWarnedAboutTabDockSetting];
}

+ (BOOL)enableAutomaticProfileSwitchingLogging {
    return [self.userDefaults boolForKey:iTermUserDefaultsKeyEnableAutomaticProfileSwitchingLogging];
}

+ (void)setEnableAutomaticProfileSwitchingLogging:(BOOL)enableAutomaticProfileSwitchingLogging {
    [self.userDefaults setBool:enableAutomaticProfileSwitchingLogging
                        forKey:iTermUserDefaultsKeyEnableAutomaticProfileSwitchingLogging];
}

+ (BOOL)requireAuthenticationAfterScreenLocks {
    return [self.userDefaults boolForKey:iTermUserDefaultsKeyRequireAuthenticationAfterScreenLocks];
}

+ (void)setRequireAuthenticationAfterScreenLocks:(BOOL)requireAuthenticationAfterScreenLocks {
    [self.userDefaults setBool:requireAuthenticationAfterScreenLocks
                        forKey:iTermUserDefaultsKeyRequireAuthenticationAfterScreenLocks];
}
+ (BOOL)openTmuxDashboardIfHiddenWindows {
    return [self.userDefaults boolForKey:iTermUserDefaultsKeyOpenTmuxDashboardIfHiddenWindows];
}

+ (void)setOpenTmuxDashboardIfHiddenWindows:(BOOL)openTmuxDashboardIfHiddenWindows {
    [self.userDefaults setBool:openTmuxDashboardIfHiddenWindows
                        forKey:iTermUserDefaultsKeyOpenTmuxDashboardIfHiddenWindows];
}

+ (BOOL)haveExplainedHowToAddTouchbarControls {
    return [self.userDefaults boolForKey:iTermUserDefaultsKeyHaveExplainedHowToAddTouchbarControls];
}

+ (void)setHaveExplainedHowToAddTouchbarControls:(BOOL)haveExplainedHowToAddTouchbarControls {
    [self.userDefaults setBool:haveExplainedHowToAddTouchbarControls
                        forKey:iTermUserDefaultsKeyHaveExplainedHowToAddTouchbarControls];
}

+ (BOOL)ignoreSystemWindowRestoration {
    return [self.userDefaults boolForKey:iTermUserDefaultsKeyIgnoreSystemWindowRestoration];
}

+ (void)setIgnoreSystemWindowRestoration:(BOOL)ignoreSystemWindowRestoration {
    [self.userDefaults setBool:ignoreSystemWindowRestoration
                        forKey:iTermUserDefaultsKeyIgnoreSystemWindowRestoration];
}

+ (NSUInteger)globalSearchMode {
    return [[self.userDefaults objectForKey:iTermUserDefaultsKeyGlobalSearchMode] unsignedIntegerValue];
}

+ (void)setGlobalSearchMode:(NSUInteger)globalSearchMode {
    [self.userDefaults setObject:@(globalSearchMode) forKey:iTermUserDefaultsKeyGlobalSearchMode];
}

+ (BOOL)addTriggerInstant {
    return [[self.userDefaults objectForKey:iTermUserDefaultsKeyAddTriggerInstant] boolValue];
}

+ (void)setAddTriggerInstant:(BOOL)addTriggerInstant {
    [self.userDefaults setObject:@(addTriggerInstant) forKey:iTermUserDefaultsKeyAddTriggerInstant];
}

+ (BOOL)addTriggerUpdateProfile {
    return [[self.userDefaults objectForKey:iTermUserDefaultsKeyAddTriggerUpdateProfile] boolValue];
}

+ (void)setAddTriggerUpdateProfile:(BOOL)addTriggerUpdateProfile {
    [self.userDefaults setObject:@(addTriggerUpdateProfile) forKey:iTermUserDefaultsKeyAddTriggerUpdateProfile];
}

+ (NSString *)lastSystemPythonVersionRequirement {
    return [self.userDefaults objectForKey:iTermUserDefaultsKeyLastSystemPythonVersionRequirement];
}

+ (void)setLastSystemPythonVersionRequirement:(NSString *)lastSystemPythonVersionRequirement {
    [self.userDefaults setObject:lastSystemPythonVersionRequirement forKey:iTermUserDefaultsKeyLastSystemPythonVersionRequirement];
}

+ (BOOL)probeForPassword {
    NSNumber *n = [self.userDefaults objectForKey:iTermUserDefaultsKeyProbeForPassword] ?: @YES;
    return n.boolValue;
}

+ (void)setProbeForPassword:(BOOL)probeForPassword {
    if (probeForPassword && [iTermAdvancedSettingsModel echoProbeDuration] == 0) {
        // Revert legacy setting when user demonstrates intent to turn probe on.
        [iTermAdvancedSettingsModel setEchoProbeDuration:0.5];
    }
    [self.userDefaults setBool:probeForPassword forKey:iTermUserDefaultsKeyProbeForPassword];
}

+ (NSString *)importPath {
    return [self.userDefaults objectForKey:iTermUserDefaultsKeyImportPath];
}

+ (void)setImportPath:(NSString *)importPath {
    [self.userDefaults setObject:importPath forKey:iTermUserDefaultsKeyImportPath];
}

@end
