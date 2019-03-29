//
//  ProfilesKeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesKeysPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermDisclosableView.h"
#import "iTermHotKeyController.h"
#import "iTermHotkeyPreferencesWindowController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermSizeRememberingView.h"
#import "iTermShortcutInputView.h"
#import "iTermTuple.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "PreferencePanel.h"

static NSString *const kDeleteKeyString = @"0x7f-0x0";

@interface ProfilesKeysPreferencesViewController () <iTermKeyMappingViewControllerDelegate>
@end

@implementation ProfilesKeysPreferencesViewController {
    IBOutlet NSMatrix *_optionKeySends;
    IBOutlet NSMatrix *_rightOptionKeySends;
    IBOutlet NSTextField *_optionKeySendsLabel;
    IBOutlet NSTextField *_rightOptionKeySendsLabel;
    IBOutlet NSButton *_deleteSendsCtrlHButton;
    IBOutlet NSButton *_applicationKeypadAllowed;
    IBOutlet NSButton *_hasHotkey;
    IBOutlet NSButton *_configureHotKey;
    IBOutlet NSButton *_useLibTickit;
    IBOutlet NSView *_hotKeyContainerView;
    IBOutlet iTermKeyMappingViewController *_keyMappingViewController;
    iTermHotkeyPreferencesWindowController *_hotkeyPanel;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyBindingDidChange)
                                                 name:kKeyBindingsChangedNotification
                                               object:nil];
    __weak __typeof(self) weakSelf = self;
    [self defineControl:_optionKeySends
                    key:KEY_OPTION_KEY_SENDS
            relatedView:_optionKeySendsLabel
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self optionKeySendsDidChangeForControl:sender]; }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (strongSelf) {
                         [strongSelf updateOptionKeySendsForControl:strongSelf->_optionKeySends];
                         return YES;
                     } else {
                         return NO;
                     }
                 }];

    [self defineControl:_rightOptionKeySends
                    key:KEY_RIGHT_OPTION_KEY_SENDS
            relatedView:_rightOptionKeySendsLabel
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self optionKeySendsDidChangeForControl:sender]; }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (strongSelf) {
                         [strongSelf updateOptionKeySendsForControl:strongSelf->_rightOptionKeySends];
                         return YES;
                     } else {
                         return NO;
                     }
                 }];

    [self defineControl:_applicationKeypadAllowed
                    key:KEY_APPLICATION_KEYPAD_ALLOWED
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    PreferenceInfo *info = [self defineControl:_useLibTickit
                                           key:KEY_USE_LIBTICKIT_PROTOCOL
                                   relatedView:nil
                                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [weakSelf didToggleLibtickit];
    };

    info = [self defineControl:_hasHotkey
                           key:KEY_HAS_HOTKEY
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        if ([[self stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS] length]) {
            [self setBool:([sender state] == NSOnState) forKey:KEY_HAS_HOTKEY];
        } else {
            [self openHotKeyPanel:nil];
        }
    };
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_configureHotKey.enabled = strongSelf->_hasHotkey.state == NSOnState;
        }
    };

    [self addViewToSearchIndex:_configureHotKey
                   displayName:@"Configure hotkey window"
                       phrases:@[]
                           key:nil];

    [self addViewToSearchIndex:_keyMappingViewController.view
                   displayName:@"Profile key bindings"
                       phrases:@[ @"mapping", @"shortcuts", @"touch bar", @"preset", @"xterm", @"natural", @"terminal.app compatibility", @"numeric keypad" ]
                           key:nil];

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
    NSArray *keys = @[ KEY_KEYBOARD_MAP, KEY_TOUCHBAR_MAP, KEY_OPTION_KEY_SENDS, KEY_RIGHT_OPTION_KEY_SENDS, KEY_APPLICATION_KEYPAD_ALLOWED, KEY_USE_LIBTICKIT_PROTOCOL ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)reloadProfile {
    [super reloadProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}

#pragma mark - CSI u

// Returns (Combo, Action, IsTouchBar)
- (NSArray<iTermTriple<NSString *, NSDictionary *, NSNumber *> *> *)incompatibleKeyBindings {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }

    NSArray<iTermTriple<NSString *, NSDictionary *, NSNumber *> *> *inProfile = [iTermKeyBindingMgr triplesOfIdentifiersAndMappingsInProfile:profile];
    // (Combo, IsTouchBar) -> (Combo, Action, IsTouchBar)
    NSDictionary<iTermTuple<NSString *, NSNumber *> *, NSArray<iTermTriple<NSString *, NSDictionary *, NSNumber *> *> *> *inProfileDict =
        [inProfile classifyWithBlock:^id(iTermTriple<NSString *, NSDictionary *, NSNumber *> *triple) {
            return [iTermTuple tupleWithObject:triple.firstObject andObject:triple.thirdObject];
        }];
    NSArray<iTermTuple<NSString *, NSDictionary *> *> *inAnyPreset = [iTermKeyBindingMgr tuplesInAllPresets];

    return [inAnyPreset mapWithBlock:^id(iTermTuple<NSString *,NSDictionary *> *inPreset) {
        iTermTuple<NSString *, NSNumber *> *key = [iTermTuple tupleWithObject:inPreset.firstObject andObject:@NO];
        NSArray<iTermTriple<NSString *, NSDictionary *, NSNumber *> *> *actions = inProfileDict[key];
        if (actions.count == 0) {
            return nil;
        }
        return [iTermTriple tripleWithObject:inPreset.firstObject
                                   andObject:inPreset.secondObject
                                      object:@NO];
    }];
}

// (Combo, Action, IsTouchBar)
- (void)removeKeyBindings:(NSArray<iTermTriple<NSString *, NSDictionary *, NSNumber *> *> *)bindingsToRemove {
    NSMutableDictionary *profile = [[self.delegate profilePreferencesCurrentProfile] mutableCopy];
    if (!profile) {
        return;
    }
    // (Combo, Action, IsTouchBar)
    [bindingsToRemove enumerateObjectsUsingBlock:^(iTermTriple<NSString *,NSDictionary *,NSNumber *> * _Nonnull triple, NSUInteger idx, BOOL * _Nonnull stop) {
        if (triple.thirdObject.boolValue) {
            [iTermKeyBindingMgr removeTouchBarItemWithKey:triple.firstObject inMutableProfile:profile];
        } else {
            const NSUInteger index = [[iTermKeyBindingMgr sortedKeyCombinationsForProfile:profile] indexOfObject:triple.firstObject];
            [iTermKeyBindingMgr removeMappingAtIndex:index inBookmark:profile];
        }
    }];

    [self commitChangesToProfile:profile];
}

- (void)commitChangesToProfile:(NSDictionary *)profile {
    [[self.delegate profilePreferencesCurrentModel] setBookmark:profile withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
}


#pragma mark - Actions

- (void)didToggleLibtickit {
    if (_useLibTickit.state != NSOnState) {
        return;
    }
    iTermWarning *warning = [[iTermWarning alloc] init];
    NSArray<iTermTriple<NSString *, NSDictionary *, NSNumber *> *> *incompatibleKeyBindings = [self incompatibleKeyBindings];
    if (incompatibleKeyBindings.count == 0) {
        return;
    }
    NSArray<NSString *> *descriptions = [incompatibleKeyBindings mapWithBlock:^id(iTermTriple<NSString *, NSDictionary *, NSNumber *> *triple) {
        NSString *formattedCombo = [iTermKeyBindingMgr formatKeyCombination:triple.firstObject];
        NSString *formattedAction = [iTermKeyBindingMgr formatAction:triple.secondObject];
        return [NSString stringWithFormat:@"“%@”\t%@", formattedCombo, formattedAction];
    }];
    warning.title = [NSString stringWithFormat:@"This profile has some key bindings from a Preset that conflict with CSI u. Remove them?"];
    NSString *message = [descriptions componentsJoinedByString:@"\n"];

    iTermScrollingDisclosableView *accessory = [[iTermScrollingDisclosableView alloc] initWithFrame:NSZeroRect
                                                                                             prompt:@"Show incompatible key bindings"
                                                                                            message:message
                                                                                      maximumHeight:150];
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.tabStops = @[ [[NSTextTab alloc] initWithType:NSLeftTabStopType location:100]
                                 ];

    NSMutableAttributedString *attributedString = [accessory.textView.attributedString mutableCopy];
    [attributedString enumerateAttributesInRange:NSMakeRange(0, attributedString.string.length)
                                         options:0
                                      usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
                                          attrs = [attrs dictionaryBySettingObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
                                          [attributedString setAttributes:attrs range:range];
                                      }];
    [accessory.textView.textStorage setAttributedString:attributedString];

    warning.accessory = accessory;
    accessory.frame = NSMakeRect(0,
                                 0,
                                 accessory.intrinsicContentSize.width,
                                 accessory.intrinsicContentSize.height);
    warning.heading = @"Remove Incompatible Key Bindings?";
    NSArray *actions = @[ [iTermWarningAction warningActionWithLabel:@"Remove" block:^(iTermWarningSelection selection) {
        [self removeKeyBindings:incompatibleKeyBindings];
    }],
                          [iTermWarningAction warningActionWithLabel:@"OK" block:^(iTermWarningSelection selection) {}] ];
    warning.warningActions = actions;
    warning.warningType = kiTermWarningTypePersistent;
    warning.window = self.view.window;
    [warning runModal];
}

- (IBAction)csiuHelp:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://iterm2.com/documentation-csiu.html"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)openHotKeyPanel:(id)sender {
    iTermHotkeyPreferencesModel *model = [[iTermHotkeyPreferencesModel alloc] init];
    model.hasModifierActivation = [self boolForKey:KEY_HOTKEY_ACTIVATE_WITH_MODIFIER];
    model.modifierActivation = [self unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_ACTIVATION];
    model.primaryShortcut = [[iTermShortcut alloc] initWithKeyCode:[self unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE]
                                                         modifiers:[self unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS]
                                                        characters:[self stringForKey:KEY_HOTKEY_CHARACTERS]
                                       charactersIgnoringModifiers:[self stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS]];
    model.autoHide = [self boolForKey:KEY_HOTKEY_AUTOHIDE];
    model.showAutoHiddenWindowOnAppActivation = [self boolForKey:KEY_HOTKEY_REOPEN_ON_ACTIVATION];
    model.animate = [self boolForKey:KEY_HOTKEY_ANIMATE];
    model.floats = [self boolForKey:KEY_HOTKEY_FLOAT];
    model.dockPreference = [self intForKey:KEY_HOTKEY_DOCK_CLICK_ACTION];
    [model setAlternateShortcutDictionaries:(id)[self objectForKey:KEY_HOTKEY_ALTERNATE_SHORTCUTS]];

    _hotkeyPanel = [[iTermHotkeyPreferencesWindowController alloc] init];
    _hotkeyPanel.descriptorsInUseByOtherProfiles =
        [[iTermHotKeyController sharedInstance] descriptorsForProfileHotKeysExcept:self.delegate.profilePreferencesCurrentProfile];
    _hotkeyPanel.model = model;

    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_hotkeyPanel.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (returnCode == NSModalResponseOK) {
            [self setObjectsFromDictionary:model.dictionaryValue];
            strongSelf->_hasHotkey.state = [strongSelf boolForKey:KEY_HAS_HOTKEY] ? NSOnState : NSOffState;
        }
        strongSelf->_configureHotKey.enabled = [strongSelf boolForKey:KEY_HAS_HOTKEY];
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
        [[self.delegate profilePreferencesCurrentProfile] mutableCopy];
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
    [self commitChangesToProfile:mutableProfile];
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
    NSMutableDictionary *dict = [profile mutableCopy];

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

    NSMutableDictionary *dict = [profile mutableCopy];
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

    NSMutableDictionary *dict = [profile mutableCopy];

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
                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                        window:self.view.window]) {
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
                           silenceable:kiTermWarningTypePermanentlySilenceable
                                window:self.view.window];
}

@end
