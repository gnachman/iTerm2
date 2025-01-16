//
//  ProfilesKeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/19/14.
//
//

#import "ProfilesKeysPreferencesViewController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermApplication.h"
#import "iTermDisclosableView.h"
#import "iTermFlagsChangedNotification.h"
#import "iTermHotKeyController.h"
#import "iTermHotkeyPreferencesWindowController.h"
#import "iTermKeyMappingViewController.h"
#import "iTermKeyMappings.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermPresetKeyMappings.h"
#import "iTermSizeRememberingView.h"
#import "iTermShortcutInputView.h"
#import "iTermTouchbarMappings.h"
#import "iTermTuple.h"
#import "iTermWarning.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PreferencePanel.h"

static NSString *const kDeleteKeyString = @"0x7f-0x0";

@interface ProfilesKeysPreferencesViewController () <iTermKeyMappingViewControllerDelegate>
@end

@implementation ProfilesKeysPreferencesViewController {
    IBOutlet NSPopUpButton *_leftOptionKeyButton;
    IBOutlet NSPopUpButton *_rightOptionKeyButton;

    IBOutlet NSTextField *_optionKeySendsLabel;
    IBOutlet NSTextField *_rightOptionKeySendsLabel;
    IBOutlet NSButton *_leftOptionKeyChangeable;
    IBOutlet NSButton *_rightOptionKeyChangeable;
    IBOutlet NSButton *_deleteSendsCtrlHButton;
    IBOutlet NSButton *_applicationKeypadAllowed;
    IBOutlet NSButton *_hasHotkey;
    IBOutlet NSButton *_configureHotKey;
    IBOutlet NSButton *_useLibTickit;
    IBOutlet NSView *_hotKeyContainerView;
    IBOutlet iTermKeyMappingViewController *_keyMappingViewController;
    IBOutlet NSButton *_allowModifyOtherKeys;
    IBOutlet NSButton *_movementKeysScrollOutsideInteractiveApps;
    IBOutlet NSTabView *_tabView;
    IBOutlet NSButton *_treatOptionAsAlt;

    IBOutlet NSButton *_leftControlButton;
    IBOutlet NSButton *_rightControlButton;
    IBOutlet NSButton *_leftCommandButton;
    IBOutlet NSButton *_rightCommandButton;
    IBOutlet NSButton *_functionButton;

    IBOutlet NSTextField *_leftControlLabel;
    IBOutlet NSTextField *_rightControlLabel;
    IBOutlet NSTextField *_leftCommandLabel;
    IBOutlet NSTextField *_rightCommandLabel;
    IBOutlet NSTextField *_functionLabel;

    iTermHotkeyPreferencesWindowController *_hotkeyPanel;
    NSInteger _posting;
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
    [self defineControl:_leftOptionKeyButton
                    key:KEY_OPTION_KEY_SENDS
            relatedView:_optionKeySendsLabel
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self optionKeySendsDidChangeForControl:sender]; }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (strongSelf) {
                         [strongSelf updateOptionKeySendsForControl:strongSelf->_leftOptionKeyButton];
                         return YES;
                     } else {
                         return NO;
                     }
                 }];

    [self defineControl:_rightOptionKeyButton
                    key:KEY_RIGHT_OPTION_KEY_SENDS
            relatedView:_rightOptionKeySendsLabel
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self optionKeySendsDidChangeForControl:sender]; }
                 update:^BOOL{
                     __strong __typeof(weakSelf) strongSelf = weakSelf;
                     if (strongSelf) {
                         [strongSelf updateOptionKeySendsForControl:strongSelf->_rightOptionKeyButton];
                         return YES;
                     } else {
                         return NO;
                     }
                 }];

    [self defineControl:_leftOptionKeyChangeable
                    key:KEY_LEFT_OPTION_KEY_CHANGEABLE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_rightOptionKeyChangeable
                    key:KEY_RIGHT_OPTION_KEY_CHANGEABLE
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_applicationKeypadAllowed
                    key:KEY_APPLICATION_KEYPAD_ALLOWED
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_allowModifyOtherKeys
                    key:KEY_ALLOW_MODIFY_OTHER_KEYS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_movementKeysScrollOutsideInteractiveApps
                    key:KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_treatOptionAsAlt
                    key:KEY_TREAT_OPTION_AS_ALT
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    PreferenceInfo *info = [self defineControl:_useLibTickit
                                           key:KEY_USE_LIBTICKIT_PROTOCOL
                                   relatedView:nil
                                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [weakSelf didToggleLibtickit];
    };

    info = [self defineControl:_leftControlButton
                           key:KEY_LEFT_CONTROL
                   relatedView:_leftControlLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf updateExtendedModifierLabelColors]; };
    info = [self defineControl:_rightControlButton
                           key:KEY_RIGHT_CONTROL
                   relatedView:_rightControlLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf updateExtendedModifierLabelColors]; };
    info = [self defineControl:_leftCommandButton
                           key:KEY_LEFT_COMMAND
                   relatedView:_leftCommandLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf updateExtendedModifierLabelColors]; };
    info = [self defineControl:_rightCommandButton
                           key:KEY_RIGHT_COMMAND
                   relatedView:_rightCommandLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf updateExtendedModifierLabelColors]; };
    info = [self defineControl:_functionButton
                           key:KEY_FUNCTION
                   relatedView:_functionLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{ [weakSelf updateExtendedModifierLabelColors]; };
    [self updateExtendedModifierLabelColors];
    
    info = [self defineControl:_hasHotkey
                           key:KEY_HAS_HOTKEY
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        if ([[self stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS] length]) {
            [self setBool:([sender state] == NSControlStateValueOn) forKey:KEY_HAS_HOTKEY];
        } else {
            [self openHotKeyPanel:nil];
        }
    };
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_configureHotKey.enabled = strongSelf->_hasHotkey.state == NSControlStateValueOn;
        }
    };
    info.hasDefaultValue = ^BOOL{
        return ![weakSelf boolForKey:KEY_HAS_HOTKEY];
    };
    [self updateNonDefaultIndicatorVisibleForInfo:info];

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

    [iTermFlagsChangedNotification subscribe:self block:^(iTermFlagsChangedNotification * _Nonnull notification) {
        [weakSelf flagsDidChange];
    }];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    _hotKeyContainerView.hidden = YES;
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_KEYBOARD_MAP,
                       KEY_TOUCHBAR_MAP,
                       KEY_OPTION_KEY_SENDS,
                       KEY_RIGHT_OPTION_KEY_SENDS,
                       KEY_LEFT_OPTION_KEY_CHANGEABLE,
                       KEY_RIGHT_OPTION_KEY_CHANGEABLE,
                       KEY_APPLICATION_KEYPAD_ALLOWED,
                       KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS,
                       KEY_TREAT_OPTION_AS_ALT,
                       KEY_USE_LIBTICKIT_PROTOCOL ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self postKeyBindingsChangedNotification];
}

- (void)postKeyBindingsChangedNotification {
    _posting += 1;
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil];
    _posting -= 1;
}

#pragma mark - CSI u

// Returns (Combo, Action)
- (NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *)incompatibleKeystrokeOrTouchbarBindings {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }

    NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *inProfile =
        [iTermKeyMappings tuplesOfActionsInProfile:profile];
    // (Combo) -> (Combo, Action)
    NSDictionary<iTermKeystroke *, NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *> *inProfileDict =
    [inProfile classifyWithBlock:^id(iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *tuple) {
        return [tuple.firstObject keystrokeWithoutVirtualKeyCode];
    }];
    NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *inAnyPreset = [iTermPresetKeyMappings keystrokeTuplesInAllPresets];

    return [inAnyPreset mapWithBlock:^id(iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *inPreset) {
        iTermKeystroke *key = [inPreset.firstObject keystrokeWithoutVirtualKeyCode];
        NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *actions = inProfileDict[key];
        if (actions.count == 0) {
            return nil;
        }
        return inPreset;
    }];
}

// (Combo, Action)
- (void)removeKeystrokeBindings:(NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *)bindingsToRemove {
    NSMutableDictionary *profile = [[self.delegate profilePreferencesCurrentProfile] mutableCopy];
    if (!profile) {
        return;
    }
    // (Combo, Action)
    [bindingsToRemove enumerateObjectsUsingBlock:^(iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> * _Nonnull tuple,
                                                   NSUInteger idx,
                                                   BOOL * _Nonnull stop) {
        const NSUInteger index = [[iTermKeyMappings sortedKeystrokesForProfile:profile] indexOfObject:tuple.firstObject];
        if (index != NSNotFound) {
            [iTermKeyMappings removeMappingAtIndex:index fromProfile:profile];
        }
    }];

    [self commitChangesToProfile:profile];
}

- (void)commitChangesToProfile:(NSDictionary *)profile {
    [[self.delegate profilePreferencesCurrentModel] setBookmark:profile withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [self postKeyBindingsChangedNotification];
}


#pragma mark - Actions

- (BOOL)modifiersSet:(NSEventModifierFlags)flags {
    return ([[NSApp currentEvent] modifierFlags] & flags) == flags;
}
- (void)flagsDidChange {
    NSFont *systemFont = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSFont *boldSystemFont = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];

    _leftControlLabel.font = [self modifiersSet:(NSEventModifierFlagControl | NX_DEVICELCTLKEYMASK)] ? boldSystemFont : systemFont;
    _rightControlLabel.font = [self modifiersSet:(NSEventModifierFlagControl | NX_DEVICERCTLKEYMASK)] ? boldSystemFont : systemFont;

    _leftCommandLabel.font = [self modifiersSet:(NSEventModifierFlagCommand | NX_DEVICELCMDKEYMASK)] ? boldSystemFont : systemFont;
    _rightCommandLabel.font = [self modifiersSet:(NSEventModifierFlagCommand | NX_DEVICERCMDKEYMASK)] ? boldSystemFont : systemFont;

    _functionLabel.font = [(iTermApplication *)NSApp it_functionPressed] ? boldSystemFont : systemFont;;
}

- (IBAction)optionAsMetaHelp:(id)sender {
    [[NSView castFrom:sender] it_showWarningWithMarkdown:@"In most key reporting modes, when reporting special keys like arrows, the ⌥ key may act as either Meta or Alt. Prior to version 3.5.6, iTerm2 used Meta. The default changed to Alt because some programs like Emacs expect it."];
}

- (void)updateExtendedModifierLabelColors {
    NSColor *blue = [NSColor it_blue];
    _leftControlLabel.textColor = _leftControlButton.selectedTag == 0 ? NSColor.controlTextColor : blue;
    _rightControlLabel.textColor = _rightControlButton.selectedTag == 0 ? NSColor.controlTextColor : blue;
    _leftCommandLabel.textColor = _leftCommandButton.selectedTag == 0 ? NSColor.controlTextColor : blue;
    _rightCommandLabel.textColor = _rightCommandButton.selectedTag == 0 ? NSColor.controlTextColor : blue;
    _functionLabel.textColor = _functionButton.selectedTag == 0 ? NSColor.controlTextColor : blue;
}

- (void)didToggleLibtickit {
    if (_useLibTickit.state != NSControlStateValueOn) {
        return;
    }
    iTermWarning *warning = [[iTermWarning alloc] init];
    NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *incompatibles =
        [self incompatibleKeystrokeOrTouchbarBindings];
    if (incompatibles.count == 0) {
        return;
    }
    NSArray<NSString *> *descriptions = [incompatibles mapWithBlock:^id(iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *tuple) {
        NSString *formattedCombo = [iTermKeystrokeFormatter stringForKeystroke:tuple.firstObject];
        iTermKeyBindingAction *action = tuple.secondObject;
        NSString *formattedAction = action.displayName;
        return [NSString stringWithFormat:@"%@\t%@", formattedCombo, formattedAction];
    }];
    warning.title = [NSString stringWithFormat  :@"This profile has some key bindings from a preset that conflict with CSI u. Remove them?"];
    NSString *message = [descriptions componentsJoinedByString:@"\n"];

    iTermScrollingDisclosableView *accessory = [[iTermScrollingDisclosableView alloc] initWithFrame:NSZeroRect
                                                                                             prompt:@"Show incompatible key bindings"
                                                                                            message:message
                                                                                      maximumHeight:150];
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.tabStops = @[ [[NSTextTab alloc] initWithType:NSLeftTabStopType location:100] ];

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
        [self removeKeystrokeBindings:incompatibles];
    }],
                          [iTermWarningAction warningActionWithLabel:@"Cancel" block:^(iTermWarningSelection selection) {}] ];
    warning.warningActions = actions;
    warning.warningType = kiTermWarningTypePersistent;
    warning.window = self.view.window;
    [warning runModal];
}

- (IBAction)csiuHelp:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://iterm2.com/documentation-csiu.html"];
    [[NSWorkspace sharedWorkspace] it_openURL:url];
}

- (IBAction)openHotKeyPanel:(id)sender {
    iTermHotkeyPreferencesModel *model = [[iTermHotkeyPreferencesModel alloc] init];
    model.hasModifierActivation = [self boolForKey:KEY_HOTKEY_ACTIVATE_WITH_MODIFIER];
    model.modifierActivation = [self unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_ACTIVATION];
    model.primaryShortcut = [[iTermShortcut alloc] initWithKeyCode:[self unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE]
                                                        hasKeyCode:YES
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
            strongSelf->_hasHotkey.state = [strongSelf boolForKey:KEY_HAS_HOTKEY] ? NSControlStateValueOn : NSControlStateValueOff;
        }
        strongSelf->_configureHotKey.enabled = [strongSelf boolForKey:KEY_HAS_HOTKEY];
    }];
}

#pragma mark - Notifications

- (void)keyBindingDidChange {
    [self updateDeleteSendsCtrlH];
    if (!_posting) {
        [_keyMappingViewController reloadData];
    }
}

#pragma mark - Delete sends Ctrl H

- (IBAction)deleteSendsCtrlHDidChange:(id)sender {
    // Resolve any conflict between key mappings and delete sends ^h by
    // modifying key mappings.
    BOOL sendCtrlH = ([sender state] == NSControlStateValueOn);
    NSMutableDictionary *mutableProfile =
        [[self.delegate profilePreferencesCurrentProfile] mutableCopy];
    if (sendCtrlH) {
        [iTermKeyMappings setMappingAtIndex:0
                               forKeystroke:[iTermKeystroke backspace]
                                     action:[iTermKeyBindingAction withAction:KEY_ACTION_SEND_C_H_BACKSPACE
                                                                    parameter:@""
                                                                     escaping:iTermSendTextEscapingCommon
                                                                    applyMode:iTermActionApplyModeCurrentSession]
                                  createNew:YES
                                  inProfile:mutableProfile];
    } else {
        [iTermKeyMappings removeKeystroke:[iTermKeystroke backspace]
                              fromProfile:mutableProfile];
    }
    [self updatePrivateNonDefaultInicators];
    [self commitChangesToProfile:mutableProfile];
}

- (void)updateDeleteSendsCtrlH {
    // If a keymapping for the delete key was added, make sure the
    // delete sends ^h checkbox is correct
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    iTermKeyBindingAction *action = [iTermKeyMappings localActionForKeystroke:[iTermKeystroke backspace]
                                                                  keyMappings:profile[KEY_KEYBOARD_MAP]];
    const BOOL sendCH = (action.keyAction == KEY_ACTION_SEND_C_H_BACKSPACE);
    _deleteSendsCtrlHButton.state = (sendCH ? NSControlStateValueOn : NSControlStateValueOff);
    [self updatePrivateNonDefaultInicators];
}

- (void)updateNonDefaultIndicators {
    [super updateNonDefaultIndicators];
    [self updatePrivateNonDefaultInicators];
}

- (void)updatePrivateNonDefaultInicators {
    BOOL sendCtrlH = ([_deleteSendsCtrlHButton state] == NSControlStateValueOn);
    _deleteSendsCtrlHButton.it_showNonDefaultIndicator = [iTermPreferences boolForKey:kPreferenceKeyIndicateNonDefaultValues] && sendCtrlH;
}

#pragma mark - Option Key Sends

- (void)optionKeySendsDidChangeForControl:(NSPopUpButton *)sender {
    if (sender == _leftOptionKeyButton && [_leftOptionKeyButton selectedTag] == OPT_META) {
        [self maybeWarnAboutMeta];
    } else if (sender == _rightOptionKeyButton && [_rightOptionKeyButton selectedTag] == OPT_META) {
        [self maybeWarnAboutMeta];
    }
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);
    [self setInt:[sender selectedTag] forKey:info.key];
}

- (void)updateOptionKeySendsForControl:(NSPopUpButton *)control {
    PreferenceInfo *info = [self infoForControl:control];
    assert(info);
    [control selectItemWithTag:[self intForKey:info.key]];
}

#pragma mark - iTermKeyMappingViewControllerDelegate

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyMappings keyMappingsForProfile:profile];
}

- (NSArray<iTermKeystroke *> *)keyMappingSortedKeystrokes:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyMappings sortedKeystrokesForProfile:profile];
}

- (NSArray<iTermTouchbarItem *> *)keyMappingSortedTouchbarItems:(iTermKeyMappingViewController *)viewController {
    return nil;
}

- (NSDictionary *)keyMappingTouchBarItems {
    return nil;
}

- (BOOL)keyMapping:(iTermKeyMappingViewController *)viewController shouldImportKeystrokes:(NSSet<iTermKeystroke *> *)keystrokesThatWillChange {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSSet<iTermKeystroke *> *keystrokesInProfile = [iTermKeyMappings keystrokesInKeyMappingsInProfile:profile];
    if (![keystrokesInProfile isSubsetOfSet:keystrokesThatWillChange]) {
        NSNumber *n = [viewController removeBeforeLoading:@"importing mappings"];
        if (!n) {
            return NO;
        }
        if (n.boolValue) {
            NSMutableDictionary *dict = [profile mutableCopy];
            [iTermKeyMappings removeAllMappingsInProfile:dict];
            [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
            [[self.delegate profilePreferencesCurrentModel] flush];
            [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
            [self postKeyBindingsChangedNotification];
        }
    }
    return YES;
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
     didChangeItem:(iTermKeystrokeOrTouchbarItem *)item
           atIndex:(NSInteger)index
          toAction:(iTermKeyBindingAction *)action
        isAddition:(BOOL)addition {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);
    NSMutableDictionary *dict = [profile mutableCopy];

    __block iTermKeystroke *keystroke;
    [item whenFirst:^(iTermKeystroke * _Nonnull theKeystroke) {
        keystroke = theKeystroke;
    } second:^(iTermTouchbarItem * _Nonnull object) {
        keystroke = nil;
    }];
    if (!keystroke) {
        return;
    }
    if ([iTermKeyMappings haveGlobalKeyMappingForKeystroke:keystroke]) {
        if (![self warnAboutOverride]) {
            return;
        }
    }

    [iTermKeyMappings setMappingAtIndex:index
                           forKeystroke:keystroke
                                 action:action
                              createNew:addition
                              inProfile:dict];
    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [self postKeyBindingsChangedNotification];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  removeKeystrokes:(NSSet<iTermKeystroke *> *)keystrokes
     touchbarItems:(NSSet<iTermTouchbarItem *> *)touchbarItems {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);

    MutableProfile *dict = [profile mutableCopy];
    [keystrokes enumerateObjectsUsingBlock:^(iTermKeystroke * _Nonnull keystroke, BOOL * _Nonnull stop) {
        NSUInteger index =
            [[iTermKeyMappings sortedKeystrokesForProfile:dict] indexOfObject:keystroke];
        assert(index != NSNotFound);

        [iTermKeyMappings removeMappingAtIndex:index fromProfile:dict];
    }];

    // Ignore touch bar items because we don't support profile-specific touch bar items.

    [[self.delegate profilePreferencesCurrentModel] setBookmark:dict withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [self postKeyBindingsChangedNotification];
}

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController {
    return [iTermPresetKeyMappings presetKeyMappingsNames];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  loadPresetsNamed:(NSString *)presetName {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    assert(profile);

    NSSet<iTermKeystroke *> *keystrokesThatWillChange = [iTermPresetKeyMappings keystrokesInKeyMappingPresetWithName:presetName];
    NSSet<iTermKeystroke *> *keystrokesInProfile = [iTermKeyMappings keystrokesInKeyMappingsInProfile:profile];
    BOOL replaceAll = NO;
    if (![keystrokesInProfile isSubsetOfSet:keystrokesThatWillChange]) {
        NSNumber *n = [viewController removeBeforeLoading:@"loading preset"];
        if (!n) {
            return;
        }
        replaceAll = n.boolValue;
    }

    Profile *updatedProfile = [iTermPresetKeyMappings profileByLoadingPresetNamed:presetName
                                                                      intoProfile:profile
                                                                   byReplacingAll:replaceAll];
    [[self.delegate profilePreferencesCurrentModel] setBookmark:updatedProfile
                                                       withGuid:profile[KEY_GUID]];
    [[self.delegate profilePreferencesCurrentModel] flush];

    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles object:nil];
    [self postKeyBindingsChangedNotification];
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
                                       @"systems. The \"Esc+\" option is recommended for most users."
                               actions:@[ @"OK" ]
                            identifier:@"NeverWarnAboutMeta"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                                window:self.view.window];
}

@end
