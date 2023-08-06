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
#import "iTermTextPopoverViewController.h"
#import "iTermTouchbarMappings.h"
#import "iTermTuple.h"
#import "iTermUserDefaults.h"
#import "iTermWarning.h"
#import "NSAppearance+iTerm.h"
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
    IBOutlet NSPopUpButton *_leftControlButton;
    IBOutlet NSPopUpButton *_rightControlButton;
    IBOutlet NSPopUpButton *_leftOptionButton;
    IBOutlet NSPopUpButton *_rightOptionButton;
    IBOutlet NSPopUpButton *_leftCommandButton;
    IBOutlet NSPopUpButton *_rightCommandButton;
    IBOutlet NSPopUpButton *_functionButton;

    IBOutlet NSButton *_resetRemappingButton;

    IBOutlet NSTextField *_leftControlButtonLabel;
    IBOutlet NSTextField *_rightControlButtonLabel;
    IBOutlet NSTextField *_leftOptionButtonLabel;
    IBOutlet NSTextField *_rightOptionButtonLabel;
    IBOutlet NSTextField *_leftCommandButtonLabel;
    IBOutlet NSTextField *_rightCommandButtonLabel;
    IBOutlet NSTextField *_functionButtonLabel;

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
    IBOutlet iTermShortcutInputView *_hotkeyField;
    IBOutlet NSTextField *_hotkeyLabel;
    IBOutlet NSButton *_configureHotKeyWindow;
    IBOutlet NSButton *_emulateUSKeyboard;

    iTermHotkeyPreferencesWindowController *_hotkeyPanel;

    IBOutlet NSTabView *_tabView;
    IBOutlet iTermShortcutInputView *_leader;
    IBOutlet NSButton *_leaderHelpButton;
    iTermTextPopoverViewController *_popoverVC;
    IBOutlet NSButton *_languageAgnosticKeyBindings;

    IBOutlet NSButton *_forceKeyboard;
    IBOutlet NSPopUpButton *_keyboardLocale;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    __weak __typeof(self) weakSelf = self;

    _leader.leaderAllowed = NO;
    iTermKeystroke *leaderKeystroke = [iTermKeyMappings leader];
    _leader.stringValue = leaderKeystroke ? [iTermKeystrokeFormatter stringForKeystroke:leaderKeystroke] : @"";

    _hotkeyField.leaderAllowed = NO;

    [_keyMappingViewController addViewsToSearchIndex:self];

    [self defineControl:_languageAgnosticKeyBindings
                    key:kPreferenceKeyLanguageAgnosticKeyBindings
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // Modifier remapping
    info = [self defineControl:_leftControlButton
                           key:kPreferenceKeyLeftControlRemapping
                   relatedView:_leftControlButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };

    info = [self defineControl:_rightControlButton
                           key:kPreferenceKeyRightControlRemapping
                   relatedView:_rightControlButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };

    info = [self defineControl:_leftOptionButton
                           key:kPreferenceKeyLeftOptionRemapping
                   relatedView:_leftOptionButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };

    info = [self defineControl:_rightOptionButton
                           key:kPreferenceKeyRightOptionRemapping
                   relatedView:_rightOptionButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };

    info = [self defineControl:_leftCommandButton
                           key:kPreferenceKeyLeftCommandRemapping
                   relatedView:_leftCommandButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };

    info = [self defineControl:_rightCommandButton
                           key:kPreferenceKeyRightCommandRemapping
                   relatedView:_rightCommandButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };

    info = [self defineControl:_functionButton
                           key:kPreferenceKeyFunctionRemapping
                   relatedView:_functionButtonLabel
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [weakSelf startEventTapIfNecessary]; [weakSelf updateRemapLabelColors]; };
    [self updateRemapLabelColors];

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


    info = [self defineControl:_forceKeyboard
                           key:kPreferenceKeyForceKeyboard
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() { [weakSelf updateKeyboardLocaleEnabled]; };

    info = [self defineControl:_keyboardLocale
                           key:kPreferenceKeyKeyboardLocale
                   displayName:@"Keyboard locale"
                          type:kPreferenceInfoTypeStringPopup];
    [self rebuildKeyboardLocales];
    [self updateKeyboardLocaleEnabled];

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

- (void)rebuildKeyboardLocales {
    while (_keyboardLocale.menu.numberOfItems > 0) {
        [_keyboardLocale.menu removeItemAtIndex:0];
    }

    // Convert system input sources into (display name, identifier) tuples.
    NSMutableArray<iTermTuple<NSString *, NSString *>  *> *items = [NSMutableArray array];
    CFArrayRef inputSources = TISCreateInputSourceList(NULL, NO);
    for (NSInteger i = 0; i < CFArrayGetCount(inputSources); i++) {
        TISInputSourceRef inputSource = (TISInputSourceRef)CFArrayGetValueAtIndex(inputSources, i);
        CFStringRef category = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceCategory);
        if (CFStringCompare(category, kTISCategoryKeyboardInputSource, 0) != kCFCompareEqualTo) {
            continue;
        }
        CFStringRef inputSourceID = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);
        CFStringRef localizedName = (CFStringRef)TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName);
        NSString *displayName = (__bridge NSString *)localizedName;
        [items addObject:[iTermTuple tupleWithObject:displayName andObject:(__bridge NSString *)inputSourceID]];
    }
    CFRelease(inputSources);

    // Sort by display name.
    [items sortUsingComparator:^NSComparisonResult(iTermTuple *lhs, iTermTuple *rhs) {
        return [lhs.firstObject localizedCaseInsensitiveCompare:rhs.firstObject];
    }];

    // Add each as a menu item.
    [items enumerateObjectsUsingBlock:^(iTermTuple<NSString *,NSString *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:tuple.firstObject
                                                      action:nil
                                               keyEquivalent:@""];
        item.representedObject = tuple.secondObject;
        [_keyboardLocale.menu addItem:item];
    }];

    NSString *identifier = [self stringForKey:kPreferenceKeyKeyboardLocale];
    NSInteger i = -1;
    if (identifier) {
        i = [_keyboardLocale indexOfItemWithRepresentedObject:identifier];
    }
    [_keyboardLocale selectItemAtIndex:i];
}

- (void)updateKeyboardLocaleEnabled {
    _keyboardLocale.enabled = [self boolForKey:kPreferenceKeyForceKeyboard];
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
                                                                     escaping:iTermSendTextEscapingCommon
                                                                    applyMode:iTermActionApplyModeCurrentSession];
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
                                                                         character:theChar
                                                                 modifiedCharacter:theChar];
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

- (NSArray<iTermTuple<NSControl *, NSNumber *> *> *)modifierRemappingTuples {
    return @[[iTermTuple tupleWithObject:_leftControlButton andObject:@(kPreferencesModifierTagLeftControl)],
             [iTermTuple tupleWithObject:_rightControlButton andObject:@(kPreferencesModifierTagRightControl)],
             [iTermTuple tupleWithObject:_leftOptionButton andObject:@(kPreferencesModifierTagLeftOption)],
             [iTermTuple tupleWithObject:_rightOptionButton andObject:@(kPreferencesModifierTagRightOption)],
             [iTermTuple tupleWithObject:_leftCommandButton andObject:@(kPreferencesModifierTagLeftCommand)],
             [iTermTuple tupleWithObject:_rightCommandButton andObject:@(kPreferencesModifierTagRightCommand)],
             [iTermTuple tupleWithObject:_functionButton andObject:@(kPreferenceModifierTagFunction)]];
}

- (void)startEventTapIfNecessary {
    if ([[iTermModifierRemapper sharedInstance] isAnyModifierRemapped]) {
        [[iTermModifierRemapper sharedInstance] setRemapModifiers:YES];
    }
}

- (void)updateRemapLabelColors {
    BOOL remappingAnyModifier = NO;
    for (iTermTuple<NSControl *, NSNumber *> *tuple in [self modifierRemappingTuples]) {
        PreferenceInfo *info = [self infoForControl:tuple.firstObject];
        NSTextField *textField = [NSTextField castFrom:info.relatedView];
        if ([self intForKey:info.key] == tuple.secondObject.intValue) {
            textField.textColor = [NSColor controlTextColor];
        } else {
            remappingAnyModifier = YES;
            textField.textColor = [NSColor colorWithName:@"iTermBlueTextColor" dynamicProvider:^NSColor * _Nonnull(NSAppearance * _Nonnull appearance) {
                if (appearance.it_isDark) {
                    return [NSColor colorWithSRGBRed:0.8 green:0.8 blue:1.0 alpha:1.0];
                } else {
                    return [NSColor colorWithSRGBRed:0.3 green:0.3 blue:0.55 alpha:1.0];
                }
            }];
        }
    }

    _resetRemappingButton.enabled = remappingAnyModifier;
}

- (void)postModifierChangedNotification {
    NSDictionary *userInfo =
        @{ kPSMTabModifierKey: @([iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]]) };
    [[NSNotificationCenter defaultCenter] postNotificationName:kPSMModifierChangedNotification
                                                        object:nil
                                                      userInfo:userInfo];
}

#pragma mark - Actions

- (IBAction)resetModifierRemapping:(id)sender {
    for (iTermTuple<NSControl *, NSNumber *> *tuple in [self modifierRemappingTuples]) {
        PreferenceInfo *info = [self infoForControl:tuple.firstObject];
        [self setObject:tuple.secondObject forKey:info.key];
        [self updateValueForInfo:info];
    }
    [self startEventTapIfNecessary];
    [self updateRemapLabelColors];
}

- (IBAction)configureHotKeyWindow:(id)sender {
    [self generateHotkeyWindowProfile];
}

- (IBAction)emulateUsKeyboardHelp:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Emulate US Keyboard";
    alert.informativeText = @"Some keyboard layouts (such as AZERTY) require a modifier to press a number key. This causes problems for switching to a window, tab, or split pane by pressing modifier+number: you might need other modifiers or conflicting modifiers. When “Emulate US Keyboard” is enabled, you can press the configured modifier plus the key on the top row that corresponds to a number key on a US keyboard. For example, on AZERTY, the & key would act as the 1 key.";
    [alert runModal];
}

- (IBAction)showLeaderHelp:(id)sender {
    [_popoverVC.popover close];
    _popoverVC = [[iTermTextPopoverViewController alloc] initWithNibName:@"iTermTextPopoverViewController"
                                                                  bundle:[NSBundle bundleForClass:self.class]];
    _popoverVC.popover.behavior = NSPopoverBehaviorTransient;
    [_popoverVC view];
    _popoverVC.textView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    _popoverVC.textView.drawsBackground = NO;
    [_popoverVC appendString:@"The leader behaves like a modifier key, such as Command or Option, but is a separate keystroke. It can be used in key bindings. For example, if you set the leader to ⌘s then you could bind an action to the two-keystroke sequence “⌘s x”."];
    NSRect frame = _popoverVC.view.frame;
    frame.size.width = 300;
    frame.size.height = 108;
    _popoverVC.view.frame = frame;
    [_popoverVC.popover showRelativeToRect:_leaderHelpButton.bounds
                                    ofView:_leaderHelpButton
                             preferredEdge:NSRectEdgeMaxY];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    if (view == _hotkeyField) {
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
    } else if (view == _leader) {
        if (event) {
            [iTermKeyMappings setLeader:[iTermKeystroke withEvent:event]];
        } else {
            [iTermKeyMappings setLeader:nil];
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
    [iTermKeyMappings suppressNotifications:^{
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
    [iTermKeyMappings suppressNotifications:^{
        [keystrokes enumerateObjectsUsingBlock:^(iTermKeystroke * _Nonnull keystroke, BOOL * _Nonnull stop) {
            NSUInteger index = [[iTermKeyMappings sortedGlobalKeystrokes] indexOfObject:keystroke];
            assert(index != NSNotFound);
            [iTermKeyMappings setGlobalKeyMap:[iTermKeyMappings removeMappingAtIndex:index
                                                                        inDictionary:[iTermKeyMappings globalKeyMap]]];
        }];
        [touchbarItems enumerateObjectsUsingBlock:^(iTermTouchbarItem * _Nonnull touchbarItem, BOOL * _Nonnull stop) {
            [iTermTouchbarMappings removeTouchbarItem:touchbarItem];
        }];
    }];

    // iTermKeyMappings posts this for you but iTermTouchbarMappings does not.
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

    [iTermKeyMappings suppressNotifications:^{
        [iTermPresetKeyMappings setGlobalKeyMappingsToPreset:presetName byReplacingAll:replaceAll];
    }];
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
