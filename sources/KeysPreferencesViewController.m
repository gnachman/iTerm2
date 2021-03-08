//
//  KeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "KeysPreferencesViewController.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermHotKeyController.h"
#import "iTermHotkeyPreferencesWindowController.h"
#import "iTermAppHotKeyProvider.h"
#import "iTermKeyMappingViewController.h"
#import "iTermKeyMappings.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermModifierRemapper.h"
#import "iTermNotificationController.h"
#import "iTermPresetKeyMappings.h"
#import "iTermTouchbarMappings.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import "PSMTabBarControl.h"

static NSString *const kHotkeyWindowGeneratedProfileNameKey = @"Hotkey Window";

@interface KeysPreferencesViewController () <iTermKeyMappingViewControllerDelegate>
@end

@implementation KeysPreferencesViewController {
    IBOutlet NSPopUpButton *_controlButton;
    IBOutlet NSPopUpButton *_leftOptionButton;
    IBOutlet NSPopUpButton *_rightOptionButton;
    IBOutlet NSPopUpButton *_leftCommandButton;
    IBOutlet NSPopUpButton *_rightCommandButton;

    IBOutlet NSTextField *_controlButtonLabel;
    IBOutlet NSTextField *_leftOptionButtonLabel;
    IBOutlet NSTextField *_rightOptionButtonLabel;
    IBOutlet NSTextField *_leftCommandButtonLabel;
    IBOutlet NSTextField *_rightCommandButtonLabel;

    IBOutlet NSPopUpButton *_switchPaneModifierButton;
    IBOutlet NSPopUpButton *_switchTabModifierButton;
    IBOutlet NSPopUpButton *_switchWindowModifierButton;

    IBOutlet NSTextField *_switchPaneModifierButtonLabel;
    IBOutlet NSTextField *_switchTabModifierButtonLabel;
    IBOutlet NSTextField *_switchWindowModifierButtonLabel;

    IBOutlet iTermKeyMappingViewController *_keyMappingViewController;
    IBOutlet NSView *_keyMappingView;
    
    // Hotkey
    IBOutlet NSButton *_hotkeyEnabled;
    IBOutlet NSTextField *_shortcutOverloaded;
    IBOutlet NSTextField *_hotkeyField;
    IBOutlet NSTextField *_hotkeyLabel;
    IBOutlet NSButton *_configureHotKeyWindow;
    IBOutlet NSButton *_emulateUSKeyboard;

    iTermHotkeyPreferencesWindowController *_hotkeyPanel;

    IBOutlet NSTabView *_tabView;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    __weak __typeof(self) weakSelf = self;

    [_keyMappingViewController addViewsToSearchIndex:self];

    // Modifier remapping
    info = [self defineControl:_controlButton
                           key:kPreferenceKeyControlRemapping
                   relatedView:_controlButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; };

    info = [self defineControl:_leftOptionButton
                           key:kPreferenceKeyLeftOptionRemapping
                   relatedView:_leftOptionButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; };

    info = [self defineControl:_rightOptionButton
                           key:kPreferenceKeyRightOptionRemapping
                   relatedView:_rightOptionButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; };

    info = [self defineControl:_leftCommandButton
                           key:kPreferenceKeyLeftCommandRemapping
                   relatedView:_leftCommandButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; };

    info = [self defineControl:_rightCommandButton
                           key:kPreferenceKeyRightCommandRemapping
                   relatedView:_rightCommandButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; };

    // ---------------------------------------------------------------------------------------------
    // Modifiers for switching tabs/windows/panes.
    info = [self defineControl:_switchPaneModifierButton
                           key:kPreferenceKeySwitchPaneModifier
                   relatedView:_switchPaneModifierButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [weakSelf ensureUniquenessOfModifierForButton:strongSelf->_switchPaneModifierButton
                                            inButtons:@[ strongSelf->_switchTabModifierButton,
                                                         strongSelf->_switchWindowModifierButton ]];
        [weakSelf postModifierChangedNotification];
    };

    info = [self defineControl:_switchTabModifierButton
                           key:kPreferenceKeySwitchTabModifier
                   relatedView:_switchTabModifierButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [weakSelf ensureUniquenessOfModifierForButton:strongSelf->_switchTabModifierButton
                                            inButtons:@[ strongSelf->_switchPaneModifierButton,
                                                         strongSelf->_switchWindowModifierButton ]];
        [weakSelf postModifierChangedNotification];
    };

    info = [self defineControl:_switchWindowModifierButton
                           key:kPreferenceKeySwitchWindowModifier
                   relatedView:_switchWindowModifierButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [weakSelf ensureUniquenessOfModifierForButton:strongSelf->_switchWindowModifierButton
                                            inButtons:@[ strongSelf->_switchTabModifierButton,
                                                         strongSelf->_switchPaneModifierButton ]];
        [weakSelf postModifierChangedNotification];
    };

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_hotkeyEnabled
                           key:kPreferenceKeyHotkeyEnabled
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [weakSelf hotkeyEnabledDidChange]; };
    info.observer = ^() { [weakSelf updateHotkeyViews]; };
    [self updateDuplicateWarning];

    [self defineControl:_emulateUSKeyboard
                    key:kPreferenceKeyEmulateUSKeyboard
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self addViewToSearchIndex:_keyMappingView
                   displayName:@"Global key bindings"
                       phrases:@[ @"mapping", @"shortcuts", @"touch bar", @"preset", @"xterm", @"natural", @"terminal.app compatibility", @"numeric keypad" ]
                           key:nil];

}

- (void)viewWillAppear {
    [self updateDuplicateWarning];
}

- (iTermHotKeyDescriptor *)hotkeyDescriptor {
    int theChar = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
    int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
    int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
    if (code || theChar) {
        return [NSDictionary descriptorWithKeyCode:code modifiers:modifiers];
    } else {
        return nil;
    }
}

- (void)updateDuplicateWarning {
    NSArray<iTermHotKeyDescriptor *> *descriptors = [[iTermHotKeyController sharedInstance] descriptorsForProfileHotKeysExcept:nil];
    _shortcutOverloaded.hidden = ![descriptors containsObject:[self hotkeyDescriptor]];
}

- (void)ensureUniquenessOfModifierForButton:(NSPopUpButton *)buttonThatChanged
                                  inButtons:(NSArray *)buttons {
    if (buttonThatChanged.selectedTag == kPreferenceModifierTagNone) {
        return;
    }
    for (NSPopUpButton *button in buttons) {
        if (button.selectedTag == buttonThatChanged.selectedTag) {
            [button selectItemWithTag:kPreferenceModifierTagNone];
            PreferenceInfo *info = [self infoForControl:button];
            [self setInt:kPreferenceModifierTagNone forKey:info.key];
        }
    }
}

- (void)generateHotkeyWindowProfile {
    NSArray<iTermProfileHotKey *> *profileHotKeys = [[iTermHotKeyController sharedInstance] profileHotKeys];
    if (profileHotKeys.count > 0) {
        NSArray<NSString *> *names = [profileHotKeys mapWithBlock:^id(iTermProfileHotKey *profileHotKey) {
            return [NSString stringWithFormat:@"“%@”", profileHotKey.profile[KEY_NAME]];
        }];
        NSString *joinedNames = [names componentsJoinedWithOxfordComma];
        NSString *namesSentence = nil;
        NSArray *actions = @[ @"OK", @"Cancel"];

        iTermWarningSelection cancel = kiTermWarningSelection1;
        iTermWarningSelection edit = kItermWarningSelectionError;

        if (profileHotKeys.count == 1) {
            namesSentence = [NSString stringWithFormat:@"You already have a Profile with a Hotkey Window named %@", joinedNames];
            actions = @[ @"OK", @"Configure Existing Profile", @"Cancel"];
            edit = kiTermWarningSelection1;
            cancel = kiTermWarningSelection2;
        } else {
            namesSentence = [NSString stringWithFormat:@"You already have Profiles with Hotkey Windows named %@", joinedNames];
        }
        namesSentence = [namesSentence stringByInsertingTerminalPunctuation:@"."];

        iTermWarningSelection selection = [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"%@", namesSentence]
                                                                     actions:actions
                                                                   accessory:nil
                                                                  identifier:@"NoSyncSuppressAddAnotherHotkeyProfileWarning"
                                                                 silenceable:kiTermWarningTypePersistent
                                                                     heading:@"Add Another Hotkey Window Profile?"
                                                                      window:self.view.window];
        if (selection == cancel) {
            return;
        } else if (selection == edit) {
            [[PreferencePanel sharedInstance] configureHotkeyForProfile:[profileHotKeys.firstObject profile]];
        }
    }
    iTermHotkeyPreferencesModel *model = [[iTermHotkeyPreferencesModel alloc] init];
    _hotkeyPanel = [[iTermHotkeyPreferencesWindowController alloc] init];
    [_hotkeyPanel setExplanation:@"This panel helps you configure a new profile that will be bound to a keystroke you assign. Pressing the hotkey (even when iTerm2 is not active) will toggle a special window."];
    _hotkeyPanel.descriptorsInUseByOtherProfiles = [[iTermHotKeyController sharedInstance] descriptorsForProfileHotKeysExcept:nil];
    _hotkeyPanel.model = model;

    [self.view.window beginSheet:_hotkeyPanel.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            if (!model.hotKeyAssigned) {
                return;
            }
            NSMutableDictionary *dict = [[[ProfileModel sharedInstance] defaultBookmark] mutableCopy];
            dict[KEY_WINDOW_TYPE] = @(WINDOW_TYPE_TOP);
            dict[KEY_ROWS] = @25;
            dict[KEY_TRANSPARENCY] = @0.3;
            dict[KEY_INITIAL_USE_TRANSPARENCY] = @YES;
            dict[KEY_BLEND] = @0.5;
            dict[KEY_BLUR_RADIUS] = @2.0;
            dict[KEY_BLUR] = @YES;
            dict[KEY_SCREEN] = @-1;
            dict[KEY_SPACE] = @(iTermProfileJoinsAllSpaces);
            dict[KEY_SHORTCUT] = @"";
            NSString *newProfileName = kHotkeyWindowGeneratedProfileNameKey;
            NSInteger number = 1;
            while ([[ProfileModel sharedInstance] bookmarkWithName:newProfileName]) {
                newProfileName = [NSString stringWithFormat:@"%@ (%@)", kHotkeyWindowGeneratedProfileNameKey, @(number)];
                number++;
            }
            dict[KEY_NAME] = newProfileName;
            dict[KEY_DEFAULT_BOOKMARK] = @"No";
            dict[KEY_GUID] = [ProfileModel freshGuid];

            // Assign cmd-t to "new tab with profile" with this profile.
            NSMutableDictionary *keyboardMap = [dict[KEY_KEYBOARD_MAP] ?: @{} mutableCopy];
            iTermKeyBindingAction *action = [iTermKeyBindingAction withAction:KEY_ACTION_NEW_TAB_WITH_PROFILE
                                                                    parameter:dict[KEY_GUID]
                                                     useCompatibilityEscaping:NO];
            iTermKeystroke *keystroke = [iTermKeystroke withCharacter:'t' modifierFlags:NSEventModifierFlagCommand];
            keyboardMap[keystroke.serialized] = action.dictionaryValue;
            dict[KEY_KEYBOARD_MAP] = keyboardMap;

            [dict removeObjectForKey:KEY_TAGS];

            // Copy values from the profile model's generated dictionary.
            [model.dictionaryValue enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key,
                                                                       id _Nonnull obj,
                                                                       BOOL *_Nonnull stop) {
                [dict setObject:obj forKey:key];
            }];
            [[ProfileModel sharedInstance] addBookmark:dict];
            [[ProfileModel sharedInstance] flush];
            [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                                object:nil
                                                              userInfo:nil];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Hotkey Window Successfully Configured";
            alert.informativeText = [NSString stringWithFormat:@"A new profile called “%@” was created for you. It is tuned to work well "
                                     @"for the Hotkey Window feature and it can be customized in the Profiles tab.",
                                     newProfileName];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        }
    }];
}

- (void)hotkeyEnabledDidChange {
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled]) {
        // Hotkey was enabled but might be unassigned; give it a default value if needed.
        int theChar = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
        int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
        int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
        if (!theChar) {
            [self setHotKeyChar:' ' code:kVK_Space mods:NSEventModifierFlagOption];
        } else {
            [self setHotKeyChar:theChar code:code mods:modifiers];
        }
    } else {
        [[iTermAppHotKeyProvider sharedInstance] invalidate];
        [self updateHotkeyViews];
    }
}

- (void)updateHotkeyViews {
    // Update the field's values.
    int theChar = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
    int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
    int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
    if (code || theChar) {
        iTermKeystroke *keystroke = [[iTermKeystroke alloc] initWithVirtualKeyCode:code
                                                                     modifierFlags:modifiers
                                                                         character:theChar];
        _hotkeyField.stringValue = [iTermKeystrokeFormatter stringForKeystroke:keystroke];
    } else {
        _hotkeyField.stringValue = @"";
    }

    // Update the enabled status of all other views.
    BOOL isEnabled = [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
    _hotkeyField.enabled = isEnabled;
    _hotkeyLabel.labelEnabled = isEnabled;
    [self updateDuplicateWarning];
}

// Set the local copy of the hotkey, update the pref panel, and register it after a delay.
- (void)setHotKeyChar:(unsigned short)keyChar
                 code:(unsigned int)keyCode
                 mods:(unsigned int)keyMods {
    [iTermPreferences setInt:keyChar forKey:kPreferenceKeyHotkeyCharacter];
    [iTermPreferences setInt:keyCode forKey:kPreferenceKeyHotKeyCode];
    [iTermPreferences setInt:keyMods forKey:kPreferenceKeyHotkeyModifiers];

    PreferencePanel *prefs = [PreferencePanel sharedInstance];
    [prefs.window makeFirstResponder:prefs.window];
    [self updateHotkeyViews];
    [[iTermAppHotKeyProvider sharedInstance] invalidate];
}


- (void)startEventTapIfNecessary {
    if ([[iTermModifierRemapper sharedInstance] isAnyModifierRemapped]) {
        [[iTermModifierRemapper sharedInstance] setRemapModifiers:YES];
    }
}

- (void)postModifierChangedNotification {
    NSDictionary *userInfo =
        @{ kPSMTabModifierKey: @([iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]]) };
    [[NSNotificationCenter defaultCenter] postNotificationName:kPSMModifierChangedNotification
                                                        object:nil
                                                      userInfo:userInfo];
}

#pragma mark - Actions

- (IBAction)configureHotKeyWindow:(id)sender {
    [self generateHotkeyWindowProfile];
}

- (IBAction)emulateUsKeyboardHelp:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Emulate US Keyboard";
    alert.informativeText = @"Some keyboard layouts (such as AZERTY) require a modifier to press a number key. This causes problems for switching to a window, tab, or split pane by pressing modifier+number: you might need other modifiers or conflicting modifiers. When “Emulate US Keyboard” is enabled, you can press the configured modifier plus the key on the top row that corresponds to a number key on a US keyboard. For example, on AZERTY, the & key would act as the 1 key.";
    [alert runModal];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    unsigned int keyMods;
    NSString *unmodkeystr;

    keyMods = [event it_modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unsigned short keyChar = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int keyCode = [event keyCode];

    [self setHotKeyChar:keyChar code:keyCode mods:keyMods];

    if (!event) {
        BOOL wasEnabled = [self boolForKey:kPreferenceKeyHotkeyEnabled];
        [self setBool:NO forKey:kPreferenceKeyHotkeyEnabled];
        if (wasEnabled) {
            [self hotkeyEnabledDidChange];
            _hotkeyEnabled.state = NSControlStateValueOff;
        }
    }
}

- (BOOL)anyProfileHasMappingForKeystroke:(iTermKeystroke *)keystroke {
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        if ([iTermKeyMappings haveKeyMappingForKeystroke:keystroke inProfile:profile]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)warnAboutPossibleOverride {
    switch ([iTermWarning showWarningWithTitle:@"The global keyboard shortcut you have set is overridden by at least one profile. "
                                               @"Check your profiles’ keyboard settings if it doesn't work as expected."
                                       actions:@[ @"OK", @"Cancel" ]
                                    identifier:@"NeverWarnAboutPossibleOverrides"
                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                        window:self.view.window]) {
        case kiTermWarningSelection1:
            return NO;
        default:
            return YES;
    }
}


#pragma mark - iTermKeyMappingViewControllerDelegate

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyMappings globalKeyMap];
}

- (NSArray<iTermKeystroke *> *)keyMappingSortedKeystrokes:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyMappings sortedGlobalKeystrokes];
}

- (NSArray<iTermTouchbarItem *> *)keyMappingSortedTouchbarItems:(iTermKeyMappingViewController *)viewController {
    NSDictionary *dict = [iTermTouchbarMappings globalTouchBarMap];
    return [iTermTouchbarMappings sortedTouchbarItemsInDictionary:dict];
}

- (NSDictionary *)keyMappingTouchBarItems {
    return [iTermTouchbarMappings globalTouchBarMap];
}

- (BOOL)keyMapping:(iTermKeyMappingViewController *)viewController shouldImportKeystrokes:(NSSet<iTermKeystroke *> *)keystrokesThatWillChange {
    NSSet<iTermKeystroke *> *keystrokesInGlobalMapping = [iTermKeyMappings keystrokesInGlobalMapping];
    if (![keystrokesInGlobalMapping isSubsetOfSet:keystrokesThatWillChange]) {
        NSNumber *n = [viewController removeBeforeLoading:@"importing mappings"];
        if (!n) {
            return NO;
        }
        if (n.boolValue) {
            [iTermKeyMappings removeAllGlobalKeyMappings];
        }
    }
    return YES;
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
     didChangeItem:(iTermKeystrokeOrTouchbarItem *)item
           atIndex:(NSInteger)index
          toAction:(iTermKeyBindingAction *)action
        isAddition:(BOOL)addition {
    [item whenFirst:
     ^(iTermKeystroke * _Nonnull keystroke) {
        NSMutableDictionary *dict = [[iTermKeyMappings globalKeyMap] mutableCopy];
        if ([self anyProfileHasMappingForKeystroke:keystroke]) {
            if (![self warnAboutPossibleOverride]) {
                return;
            }
        }
        [iTermKeyMappings setMappingAtIndex:index
                               forKeystroke:keystroke
                                     action:action
                                  createNew:addition
                               inDictionary:dict];
        [iTermKeyMappings setGlobalKeyMap:dict];
    }
             second:
     ^(iTermTouchbarItem * _Nonnull touchbarItem) {
        NSMutableDictionary *dict = [[iTermTouchbarMappings globalTouchBarMap] mutableCopy];
        [iTermTouchbarMappings updateDictionary:dict
                                forTouchbarItem:touchbarItem
                                         action:action];
        [iTermTouchbarMappings setGlobalTouchBarMap:dict];
        [self maybeExplainHowToEditTouchBarControls];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)maybeExplainHowToEditTouchBarControls {
    if ([iTermUserDefaults haveExplainedHowToAddTouchbarControls]) {
        return;
    }
    if ([[iTermTouchbarMappings globalTouchBarMap] count] != 1) {
        return;
    }
    [[iTermNotificationController sharedInstance] notify:@"Touch Bar Item Added"
                                         withDescription:@"Select View > Customize Touch Bar to enable your new touch bar item."];
    [iTermUserDefaults setHaveExplainedHowToAddTouchbarControls:YES];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  removeKeystrokes:(NSSet<iTermKeystroke *> *)keystrokes
     touchbarItems:(NSSet<iTermTouchbarItem *> *)touchbarItems {
    [keystrokes enumerateObjectsUsingBlock:^(iTermKeystroke * _Nonnull keystroke, BOOL * _Nonnull stop) {
        NSUInteger index = [[iTermKeyMappings sortedGlobalKeystrokes] indexOfObject:keystroke];
        assert(index != NSNotFound);
        [iTermKeyMappings setGlobalKeyMap:[iTermKeyMappings removeMappingAtIndex:index
                                                                    inDictionary:[iTermKeyMappings globalKeyMap]]];
    }];
    [touchbarItems enumerateObjectsUsingBlock:^(iTermTouchbarItem * _Nonnull touchbarItem, BOOL * _Nonnull stop) {
        [iTermTouchbarMappings removeTouchbarItem:touchbarItem];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController {
    return [iTermPresetKeyMappings globalPresetNames];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  loadPresetsNamed:(NSString *)presetName {

    NSSet<iTermKeystroke *> *keystrokesThatWillChange = [iTermPresetKeyMappings keystrokesInGlobalPreset:presetName];
    NSSet<iTermKeystroke *> *keystrokesInGlobalMapping = [iTermKeyMappings keystrokesInGlobalMapping];
    BOOL replaceAll = YES;
    if (![keystrokesInGlobalMapping isSubsetOfSet:keystrokesThatWillChange]) {
        NSNumber *n = [viewController removeBeforeLoading:@"loading preset"];
        if (!n) {
            return;
        }
        replaceAll = n.boolValue;
    }

    [iTermPresetKeyMappings setGlobalKeyMappingsToPreset:presetName byReplacingAll:replaceAll];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (NSNumber *)removeBeforeLoading:(NSString *)thing {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Remove all key mappings before loading %@?", thing]
                               actions:@[ @"Keep", @"Remove", @"Cancel" ]
                             accessory:nil
                            identifier:@"RemoveExistingGlobalKeyMappingsBeforeLoading"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Load Preset"
                                window:self.view.window];
    switch (selection) {
        case kiTermWarningSelection0:
            return @NO;
        case kiTermWarningSelection1:
            return @YES;
        case kiTermWarningSelection2:
            return nil;
        default:
            assert(NO);
    }
    return nil;
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 468;
}

@end
