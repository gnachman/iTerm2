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

@implementation ProfilesKeysPreferencesViewController {
    IBOutlet NSMatrix *_optionKeySends;
    IBOutlet NSMatrix *_rightOptionKeySends;
}

- (void)awakeFromNib {
    [self defineControl:_optionKeySends
                    key:KEY_OPTION_KEY_SENDS
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self optionKeySendsDidChangeForControl:sender]; }
                 update:^BOOL{ [self updateOptionKeySendsForControl:_optionKeySends]; return YES; }];

    [self defineControl:_rightOptionKeySends
                    key:KEY_RIGHT_OPTION_KEY_SENDS
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self optionKeySendsDidChangeForControl:sender]; }
                 update:^BOOL{ [self updateOptionKeySendsForControl:_rightOptionKeySends]; return YES; }];
}

- (void)reloadProfile {
    [super reloadProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}

#pragma mark - Option Key Sends

- (void)optionKeySendsDidChangeForControl:(NSMatrix *)sender {
    if (sender == _optionKeySends && [[_optionKeySends selectedCell] tag] == OPT_META) {
        [self maybeWarnAboutMeta];
    } else if (sender == _rightOptionKeySends && [[_rightOptionKeySends selectedCell] tag] == OPT_META) {
        [self maybeWarnAboutMeta];
    }
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);
    [self setInt:[sender selectedTag] forKey:info.key];
}

- (void)updateOptionKeySendsForControl:(NSMatrix *)control {
    PreferenceInfo *info = [self infoForControl:control];
    assert(info);
    [control selectCellWithTag:[self intForKey:info.key]];
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

- (void)maybeWarnAboutMeta {
    [iTermWarning showWarningWithTitle:@"You have chosen to have an option key act as Meta. "
                                       @"This option is useful for backward compatibility with older "
                                       @"systems. The \"+Esc\" option is recommended for most users."
                               actions:@[ @"OK" ]
                            identifier:@"NeverWarnAboutMeta"
                           silenceable:kiTermWarningTypePermanentlySilenceable];
}

@end
