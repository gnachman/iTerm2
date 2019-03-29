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
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setObject:value forKey:key inProfile:profile model:model];
}

- (BOOL)boolForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences boolForKey:key inProfile:profile];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setBool:value forKey:key inProfile:profile model:model];
}

- (int)intForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences intForKey:key inProfile:profile];
}

- (void)setInt:(int)value forKey:(NSString *)key {
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setInt:value forKey:key inProfile:profile model:model];
}

- (NSInteger)integerForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences integerForKey:key inProfile:profile];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setInteger:value forKey:key inProfile:profile model:model];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences unsignedIntegerForKey:key inProfile:profile];
}

- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key {
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setUnsignedInteger:value forKey:key inProfile:profile model:model];
}

- (double)floatForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences floatForKey:key inProfile:profile];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setFloat:value forKey:key inProfile:profile model:model];
}

- (double)doubleForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences doubleForKey:key inProfile:profile];
}

- (void)setDouble:(double)value forKey:(NSString *)key {
    [self.delegate profilePreferencesViewController:self willSetObjectWithKey:key];
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    ProfileModel *model = [_delegate profilePreferencesCurrentModel];
    [iTermProfilePreferences setDouble:value forKey:key inProfile:profile model:model];
}

- (NSString *)stringForKey:(NSString *)key {
    Profile *profile = [_delegate profilePreferencesCurrentProfile];
    return [iTermProfilePreferences stringForKey:key inProfile:profile];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
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
    assert(self.delegate);
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

- (void)willReloadProfile {
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
