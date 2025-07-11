//
//  iTermProfilePreferencesBaseViewController.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermProfilePreferencesBaseViewController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "NSObject+iTerm.h"

@implementation iTermProfilePreferencesBaseViewController

- (void)setObjectsFromDictionary:(NSDictionary *)dictionary {
    for (NSString *key in dictionary.allKeys) {
        [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setObjectsFromDictionary:dictionary inProfile:profile model:model];
}

- (NSObject *)objectForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences objectForKey:key inProfile:profile];
}

- (void)setObject:(NSObject *)value forKey:(NSString *)key {
    [self setObject:value forKey:key withSideEffects:YES];
}

- (void)setObject:(NSObject *)value forKey:(NSString *)key withSideEffects:(BOOL)sideEffects {
    if (sideEffects) {
        [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setObject:value forKey:key inProfile:profile model:model withSideEffects:sideEffects];
}

- (BOOL)boolForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [[self syntheticObjectForKey:key] boolValue];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences boolForKey:key inProfile:profile];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:@(value) forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setBool:value forKey:key inProfile:profile model:model];
}

- (int)intForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [[self syntheticObjectForKey:key] intValue];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences intForKey:key inProfile:profile];
}

- (void)setInt:(int)value forKey:(NSString *)key {
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:@(value) forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setInt:value forKey:key inProfile:profile model:model];
}

- (NSInteger)integerForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [[self syntheticObjectForKey:key] integerValue];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences integerForKey:key inProfile:profile];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:@(value) forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setInteger:value forKey:key inProfile:profile model:model];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [[self syntheticObjectForKey:key] unsignedIntegerValue];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences unsignedIntegerForKey:key inProfile:profile];
}

- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key {
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:@(value) forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setUnsignedInteger:value forKey:key inProfile:profile model:model];
}

- (double)floatForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [[self syntheticObjectForKey:key] doubleValue];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences floatForKey:key inProfile:profile];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:@(value) forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setFloat:value forKey:key inProfile:profile model:model];
}

- (double)doubleForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [[self syntheticObjectForKey:key] doubleValue];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences doubleForKey:key inProfile:profile];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:@(value) forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setDouble:value forKey:key inProfile:profile model:model];
}

- (NSString *)stringForKey:(NSString *)key {
    if ([self keyHasSyntheticGetter:key]) {
        return [self syntheticObjectForKey:key];
    }
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences stringForKey:key inProfile:profile];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    DLog(@"setString:%@ forKey:%@", value,key);
    if ([self keyHasSyntheticSetter:key]) {
        [self setSyntheticValue:value forKey:key];
        return;
    }
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setString:value forKey:key inProfile:profile model:model];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                      relatedView:(NSView *)relatedView
                             type:(PreferenceInfoType)type {
    assert(self.delegate);
    return [super defineControl:control key:key relatedView:relatedView type:type];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                      displayName:(NSString *)displayName // for search
                             type:(PreferenceInfoType)type {
    assert(self.delegate);
    return [super defineControl:control key:key displayName:displayName type:type];
}

- (PreferenceInfo *)defineUnsearchableControl:(NSControl *)control
                                          key:(NSString *)key
                                         type:(PreferenceInfoType)type {
    assert(self.delegate);
    return [super defineUnsearchableControl:control key:key type:type];
}

// Define a control with a custom settingChanged and update handler. If they're both not null then
// the default value is not type checked.
- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                      relatedView:(NSView *)relatedView
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)(void))update {
    assert(self.delegate);
    return [super defineControl:control key:key relatedView:relatedView type:type settingChanged:settingChanged update:update];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                      displayName:(NSString *)displayName // for search
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)(void))update {
    assert(self.delegate);
    return [super defineControl:control key:key displayName:displayName type:type settingChanged:settingChanged update:update];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                      relatedView:(NSView *)relatedView
                      displayName:(NSString *)forceDisplayName
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)(void))update
                       searchable:(BOOL)searchable {
    ITAssertWithMessage(self.delegate != nil, @"No delegate for control %@ with key %@", control, key);
    return [super defineControl:control key:key relatedView:relatedView displayName:forceDisplayName type:type settingChanged:settingChanged update:update searchable:searchable];
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

- (id)defaultValueForKey:(NSString *)key {
    return [iTermProfilePreferences defaultObjectForKey:key];
}

- (BOOL)valueOfKeyEqualsDefaultValue:(NSString *)key {
    static NSDictionary *presetsDict;
    static dispatch_once_t onceToken;
    // See discussion in issue 11998 for why I do this.
    dispatch_once(&onceToken, ^{
        NSString *plistFile = [[NSBundle bundleForClass:[self class]]
                                        pathForResource:@"DefaultBookmark"
                                                 ofType:@"plist"];
        presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    });
    id defaultValue = presetsDict[key] ?: [iTermProfilePreferences defaultObjectForKey:key];
    return [NSObject object:defaultValue isNullablyEqualToObject:[self objectForKey:key] epsilon:0.001];
}

- (void)willReloadProfile {
}

- (void)updateBrowserSpecific {
}

- (ProfileType)profileType {
    if ([[self stringForKey:KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeBrowserValue]) {
        return ProfileTypeBrowser;
    } else {
        return ProfileTypeTerminal;
    }
}

- (void)reloadProfile {
    for (NSControl *control in self.keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        [self updateValueForInfo:info];
    }
}

- (NSView *)searchableViewControllerRevealItemForDocument:(iTermPreferencesSearchDocument *)document
                                                 forQuery:(NSString *)query
                                            willChangeTab:(BOOL *)willChangeTab {
    const BOOL didChange = [self.delegate profilePreferencesRevealViewController:self];
    NSView *view = [super searchableViewControllerRevealItemForDocument:document
                                                               forQuery:query
                                                          willChangeTab:willChangeTab];

    [self scrollViewToVisible:view];

    *willChangeTab = didChange;
    return view;
}

- (void)scrollViewToVisible:(NSView *)view {
    if (!view.enclosingScrollView) {
        return;
    }

    // Find the outermost scroll view
    NSView *temp = view;
    NSScrollView *outermostScrollview = nil;
    while (temp.enclosingScrollView) {
        outermostScrollview = temp.enclosingScrollView;
        temp = outermostScrollview;
    }

    // Decide whether we're scrolling view or its enclosing scrollview to visible. This happens when
    // view is a tableview.
    NSView *viewToScroll;
    if (view.enclosingScrollView == outermostScrollview) {
        viewToScroll = view;
    } else {
        viewToScroll = view.enclosingScrollView;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [viewToScroll scrollRectToVisible:viewToScroll.bounds];
    });

}

@end
