//
//  ProfilesKeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesKeysPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermHotKeyController.h"
#import "iTermHotkeyPreferencesWindowController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermSizeRememberingView.h"
#import "iTermShortcutInputView.h"
#import "iTermWarning.h"
#import "PreferencePanel.h"

static NSString *const kDeleteKeyString = @"0x7f-0x0";

@interface ProfilesKeysPreferencesViewController () <iTermKeyMappingViewControllerDelegate>
@end

@implementation ProfilesKeysPreferencesViewController {
    __weak IBOutlet NSMatrix *_optionKeySends;
    __weak IBOutlet NSMatrix *_rightOptionKeySends;
    __weak IBOutlet NSButton *_deleteSendsCtrlHButton;
    __weak IBOutlet NSButton *_applicationKeypadAllowed;
    __weak IBOutlet NSButton *_hasHotkey;
    __weak IBOutlet NSButton *_configureHotKey;
    __weak IBOutlet NSView *_hotKeyContainerView;
    __weak IBOutlet iTermKeyMappingViewController *_keyMappingViewController;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyBindingDidChange)
                                                 name:kKeyBindingsChangedNotification
                                               object:nil];
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

    [self defineControl:_applicationKeypadAllowed
                    key:KEY_APPLICATION_KEYPAD_ALLOWED
                   type:kPreferenceInfoTypeCheckbox];

    PreferenceInfo *info = [self defineControl:_hasHotkey
                                           key:KEY_HAS_HOTKEY
                                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        if ([[self stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS] length]) {
            [self setBool:([sender state] == NSOnState) forKey:KEY_HAS_HOTKEY];
        } else {
            [self openHotKeyPanel:nil];
        }
    };
    info.observer = ^() {
        _configureHotKey.enabled = _hasHotkey.state == NSOnState;
    };

    [self updateDeleteSendsCtrlH];
    [_keyMappingViewController hideAddTouchBarItem];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    _hotKeyContainerView.hidden = YES;

    // Update the "original" size of the view.
    iTermSizeRememberingView *sizeRememberingView = (iTermSizeRememberingView *)self.view;
    CGSize size = sizeRememberingView.originalSize;
    size.height -= _hotKeyContainerView.frame.size.height;
    sizeRememberingView.originalSize = size;
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_KEYBOARD_MAP, KEY_TOUCHBAR_MAP, KEY_OPTION_KEY_SENDS, KEY_RIGHT_OPTION_KEY_SENDS, KEY_APPLICATION_KEYPAD_ALLOWED ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)reloadProfile {
    [super reloadProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}

#pragma mark - Actions

- (IBAction)openHotKeyPanel:(id)sender {
    iTermHotkeyPreferencesModel *model = [[[iTermHotkeyPreferencesModel alloc] init] autorelease];
    model.hasModifierActivation = [self boolForKey:KEY_HOTKEY_ACTIVATE_WITH_MODIFIER];
    model.modifierActivation = [self unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_ACTIVATION];
    model.primaryShortcut = [[[iTermShortcut alloc] initWithKeyCode:[self unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE]
                                                          modifiers:[self unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS]
                                                         characters:[self stringForKey:KEY_HOTKEY_CHARACTERS]
                                        charactersIgnoringModifiers:[self stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS]] autorelease];
    model.autoHide = [self boolForKey:KEY_HOTKEY_AUTOHIDE];
    model.showAutoHiddenWindowOnAppActivation = [self boolForKey:KEY_HOTKEY_REOPEN_ON_ACTIVATION];
    model.animate = [self boolForKey:KEY_HOTKEY_ANIMATE];
    model.floats = [self boolForKey:KEY_HOTKEY_FLOAT];
    model.dockPreference = [self intForKey:KEY_HOTKEY_DOCK_CLICK_ACTION];
    [model setAlternateShortcutDictionaries:(id)[self objectForKey:KEY_HOTKEY_ALTERNATE_SHORTCUTS]];

    iTermHotkeyPreferencesWindowController *panel = [[iTermHotkeyPreferencesWindowController alloc] init];
    panel.descriptorsInUseByOtherProfiles =
        [[iTermHotKeyController sharedInstance] descriptorsForProfileHotKeysExcept:self.delegate.profilePreferencesCurrentProfile];
    panel.model = model;

    [self.view.window beginSheet:panel.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [self setObjectsFromDictionary:model.dictionaryValue];
            _hasHotkey.state = [self boolForKey:KEY_HAS_HOTKEY] ? NSOnState : NSOffState;
        }
        _configureHotKey.enabled = [self boolForKey:KEY_HAS_HOTKEY];
    }];
}

#pragma mark - Notifications

- (void)keyBindingDidChange {
    [self updateDeleteSendsCtrlH];
}

#pragma mark - Delete sends Ctrl H

- (IBAction)deleteSendsCtrlHDidChange:(id)sender {
    // Resolve any conflict between key mappings and delete sends ^h by
    // modifying key mappings.
    BOOL sendCtrlH = ([sender state] == NSOnState);
    NSMutableDictionary *mutableProfile =
        [[[self.delegate profilePreferencesCurrentProfile] mutableCopy] autorelease];
    if (sendCtrlH) {
        [iTermKeyBindingMgr setMappingAtIndex:0
                                       forKey:kDeleteKeyString
                                       action:KEY_ACTION_SEND_C_H_BACKSPACE
                                        value:@""
                                    createNew:YES
                                   inBookmark:mutableProfile];
    } else {
        [iTermKeyBindingMgr removeMappingWithCode:0x7f
                                        modifiers:0
                                       inBookmark:mutableProfile];
    }
    [[self.delegate profilePreferencesCurrentModel] setBookmark:mutableProfile
                                                       withGuid:mutableProfile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}

- (void)updateDeleteSendsCtrlH {
    // If a keymapping for the delete key was added, make sure the
    // delete sends ^h checkbox is correct
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSString* text;
    BOOL sendCH =
        ([iTermKeyBindingMgr localActionForKeyCode:0x7f
                                         modifiers:0
                                              text:&text
                                       keyMappings:profile[KEY_KEYBOARD_MAP]] == KEY_ACTION_SEND_C_H_BACKSPACE);
    _deleteSendsCtrlHButton.state = (sendCH ? NSOnState : NSOffState);
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

- (NSArray *)keyMappingSortedTouchBarKeys:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyBindingMgr sortedTouchBarItemsForProfile:profile];
}

- (NSDictionary *)keyMappingTouchBarItems {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyBindingMgr touchBarItemsForProfile:profile];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
      didChangeKey:(NSString *)keyCombo
    isTouchBarItem:(BOOL)isTouchBarItem
           atIndex:(NSInteger)index
          toAction:(int)action
         parameter:(NSString *)parameter
             label:(NSString *)label
        isAddition:(BOOL)addition {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);
    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];

    if (isTouchBarItem) {
        [iTermKeyBindingMgr setTouchBarItemWithKey:keyCombo toAction:action value:parameter label:label inProfile:dict];
    } else {
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
    }
    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
         removeKey:(NSString *)keyCombo
    isTouchBarItem:(BOOL)isTouchBarItem {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);

    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];
    if (isTouchBarItem) {
        [iTermKeyBindingMgr removeTouchBarItemWithKey:keyCombo inMutableProfile:dict];
    } else {
        NSUInteger index =
            [[iTermKeyBindingMgr sortedKeyCombinationsForProfile:profile] indexOfObject:keyCombo];
        assert(index != NSNotFound);

        [iTermKeyBindingMgr removeMappingAtIndex:index inBookmark:dict];
    }
    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
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
