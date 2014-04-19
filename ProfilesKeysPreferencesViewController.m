//
//  ProfilesKeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesKeysPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermShortcutInputView.h"
#import "iTermWarning.h"
#import "PreferencePanel.h"

@interface ProfilesKeysPreferencesViewController () <iTermKeyMappingViewControllerDelegate>
@end

@implementation ProfilesKeysPreferencesViewController

- (void)awakeFromNib {
}

- (void)reloadProfile {
    [super reloadProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}

#pragma mark - iTermKeyMappingViewControllerDelegate

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyBindingMgr keyMappingsForProfile:profile];
}

- (NSArray *)keyMappingSortedKeys:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyBindingMgr sortedKeyCombinationsForProfile:profile];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
 didChangeKeyCombo:(NSString *)keyCombo
           atIndex:(NSInteger)index
          toAction:(int)action
         parameter:(NSString *)parameter
        isAddition:(BOOL)addition {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);
    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];
    
    if ([iTermKeyBindingMgr haveGlobalKeyMappingForKeyString:keyCombo]) {
        if (![self warnAboutOverride]) {
            return;
        }
    }
    
    [iTermKeyBindingMgr setMappingAtIndex:index
                                   forKey:keyCombo
                                   action:action
                                    value:parameter
                                createNew:addition
                               inBookmark:dict];
    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}


- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    removeKeyCombo:(NSString *)keyCombo {
    
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);
    
    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];
    NSUInteger index =
        [[iTermKeyBindingMgr sortedKeyCombinationsForProfile:profile] indexOfObject:keyCombo];
    assert(index != NSNotFound);
    
    [iTermKeyBindingMgr removeMappingAtIndex:index inBookmark:dict];
    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyBindingMgr presetKeyMappingsNames];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  loadPresetsNamed:(NSString *)presetName {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);
    
    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];
    
    [iTermKeyBindingMgr setKeyMappingsToPreset:presetName inBookmark:dict];
    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
}

#pragma mark - Warnings

- (BOOL)warnAboutOverride {
    switch ([iTermWarning showWarningWithTitle:@"The keyboard shortcut you have set for this profile "
                                               @"will take precedence over an existing shortcut for "
                                               @"the same key combination in a global shortcut."
                                       actions:@[ @"OK", @"Cancel" ]
                                    identifier:@"NeverWarnAboutOverrides"
                                   silenceable:kiTermWarningTypePermanentlySilenceable]) {
        case kiTermWarningSelection1:
            return NO;
        default:
            return YES;
    }
}

@end
