//
//  KeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "KeysPreferencesViewController.h"
#import "DebugLogging.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermWarning.h"
#import "NSPopUpButton+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import "PSMTabBarControl.h"

static NSString * const kHotkeyWindowGeneratedProfileNameKey = @"Hotkey Window";

@interface KeysPreferencesViewController () <iTermKeyMappingViewControllerDelegate>
@end

@implementation KeysPreferencesViewController {
    IBOutlet NSPopUpButton *_controlButton;
    IBOutlet NSPopUpButton *_leftOptionButton;
    IBOutlet NSPopUpButton *_rightOptionButton;
    IBOutlet NSPopUpButton *_leftCommandButton;
    IBOutlet NSPopUpButton *_rightCommandButton;

    IBOutlet NSPopUpButton *_switchPaneModifierButton;
    IBOutlet NSPopUpButton *_switchTabModifierButton;
    IBOutlet NSPopUpButton *_switchWindowModifierButton;

    // Hotkey
    IBOutlet NSButton *_hotkeyEnabled;
    IBOutlet NSTextField *_hotkeyField;
    IBOutlet NSTextField *_hotkeyLabel;

    // Hotkey opens dedicated window
    IBOutlet NSButton *_hotkeyTogglesWindow;
    IBOutlet NSButton *_hotkeyAutoHides;
    IBOutlet NSPopUpButton *_hotkeyBookmark;
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadAddressBookNotification:)
                                                 name:kReloadAddressBookNotification
                                               object:nil];
    
    PreferenceInfo *info;

    // Modifier remapping
    info = [self defineControl:_controlButton
                           key:kPreferenceKeyControlRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_leftOptionButton
                           key:kPreferenceKeyLeftOptionRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_rightOptionButton
                           key:kPreferenceKeyRightOptionRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_leftCommandButton
                           key:kPreferenceKeyLeftCommandRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    info = [self defineControl:_rightCommandButton
                           key:kPreferenceKeyRightCommandRemapping
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self startEventTapIfNecessary]; };

    // ---------------------------------------------------------------------------------------------
    // Modifiers for switching tabs/windows/panes.
    info = [self defineControl:_switchPaneModifierButton
                           key:kPreferenceKeySwitchPaneModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        [self ensureUniqunessOfModifierForButton:_switchPaneModifierButton
                                       inButtons:@[ _switchTabModifierButton,
                                                    _switchWindowModifierButton ]];
        [self postModifierChangedNotification];
    };

    info = [self defineControl:_switchTabModifierButton
                           key:kPreferenceKeySwitchTabModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        [self ensureUniqunessOfModifierForButton:_switchTabModifierButton
                                       inButtons:@[ _switchPaneModifierButton,
                                                    _switchWindowModifierButton ]];
        [self postModifierChangedNotification];
    };

    info = [self defineControl:_switchWindowModifierButton
                           key:kPreferenceKeySwitchWindowModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() {
        [self ensureUniqunessOfModifierForButton:_switchWindowModifierButton
                                       inButtons:@[ _switchTabModifierButton,
                                                    _switchPaneModifierButton ]];
        [self postModifierChangedNotification];
    };

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_hotkeyEnabled
                           key:kPreferenceKeyHotkeyEnabled
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self hotkeyEnabledDidChange]; };
    info.observer = ^() { [self updateHotkeyViews]; };

    info = [self defineControl:_hotkeyTogglesWindow
                           key:kPreferenceKeyHotKeyTogglesWindow
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self hotkeyTogglesWindowDidChange]; };

    info = [self defineControl:_hotkeyAutoHides
                           key:kPreferenceKeyHotkeyAutoHides
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self postRefreshNotification]; };
    // You can change this setting with a key binding action, so we observer it to update the
    // control when the user default changes.
    [iTermPreferences addObserverForKey:kPreferenceKeyHotkeyAutoHides
                                  block:^(id before, id after) {
                                      [self updateValueForInfo:info];
                                  }];

    [self defineControl:_hotkeyBookmark
                    key:kPreferenceKeyHotkeyProfileGuid
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self hotkeyProfileDidChange]; }
                 update:^BOOL { [self populateHotKeyProfilesMenu]; return YES; }];
    [self populateHotKeyProfilesMenu];
}

- (void)ensureUniqunessOfModifierForButton:(NSPopUpButton *)buttonThatChanged
                                 inButtons:(NSArray *)buttons {
    if (buttonThatChanged.selectedTag == kPreferenceModifierTagNone) {
        return;
    }
    for (NSPopUpButton *button in buttons) {
        if (button.selectedTag == buttonThatChanged.selectedTag) {
            [button selectItemWithTag:kPreferenceModifierTagNone];
        }
    }
}

- (void)hotkeyProfileDidChange {
    [iTermPreferences setString:[[_hotkeyBookmark selectedItem] representedObject]
                         forKey:kPreferenceKeyHotkeyProfileGuid];
    [[HotkeyWindowController sharedInstance] saveHotkeyWindowState];
}

- (void)hotkeyTogglesWindowDidChange {
    if ([iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow] &&
        ![[ProfileModel sharedInstance] bookmarkWithName:kHotkeyWindowGeneratedProfileNameKey]) {
        // User's turning on hotkey window. There is no bookmark with the autogenerated name.
        [self generateHotkeyWindowProfile];
        [_hotkeyBookmark selectItemWithTitle:kHotkeyWindowGeneratedProfileNameKey];
        [self hotkeyProfileDidChange];
        NSRunAlertPanel(@"Set Up Hotkey Window",
                        @"A new profile called \"%@\" was created for you. It is tuned to work well "
                        @"for the Hotkey Window feature and can be customized in the Profiles tab.",
                        @"OK",
                        nil,
                        nil,
                        kHotkeyWindowGeneratedProfileNameKey);
    }
    [self updateHotkeyViews];
}

- (void)generateHotkeyWindowProfile {
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:[[ProfileModel sharedInstance] defaultBookmark]];
    [dict setObject:[NSNumber numberWithInt:WINDOW_TYPE_TOP] forKey:KEY_WINDOW_TYPE];
    [dict setObject:[NSNumber numberWithInt:25] forKey:KEY_ROWS];
    [dict setObject:[NSNumber numberWithFloat:0.3] forKey:KEY_TRANSPARENCY];
    [dict setObject:[NSNumber numberWithFloat:0.5] forKey:KEY_BLEND];
    [dict setObject:[NSNumber numberWithFloat:2.0] forKey:KEY_BLUR_RADIUS];
    [dict setObject:[NSNumber numberWithBool:YES] forKey:KEY_BLUR];
    [dict setObject:[NSNumber numberWithInt:-1] forKey:KEY_SCREEN];
    [dict setObject:[NSNumber numberWithInt:-1] forKey:KEY_SPACE];
    [dict setObject:@"" forKey:KEY_SHORTCUT];
    [dict setObject:kHotkeyWindowGeneratedProfileNameKey forKey:KEY_NAME];
    [dict removeObjectForKey:KEY_TAGS];
    [dict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [dict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    [[ProfileModel sharedInstance] addBookmark:dict];
    [[ProfileModel sharedInstance] flush];
}

- (void)hotkeyEnabledDidChange {
    if ([iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled]) {
        // Hotkey was enabled but might be unassigned; give it a default value if needed.
        int theChar = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
        int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
        int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
        if (!theChar) {
            [self setHotKeyChar:' ' code:kVK_Space mods:NSAlternateKeyMask];
        } else {
            [self setHotKeyChar:theChar code:code mods:modifiers];
        }
    } else {
        [[HotkeyWindowController sharedInstance] unregisterHotkey];
        [self updateHotkeyViews];
    }
    [[HotkeyWindowController sharedInstance] saveHotkeyWindowState];
}

- (void)updateHotkeyViews {
    // Update the field's values.
    int theChar = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
    int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
    int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
    if (code || theChar) {
        NSString *identifier = [NSString stringWithFormat:@"0x%x-0x%x", theChar, modifiers];
        _hotkeyField.stringValue = [iTermKeyBindingMgr formatKeyCombination:identifier];
    } else {
        _hotkeyField.stringValue = @"";
    }

    // Update the enabled status of all other views.
    BOOL isEnabled = [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
    _hotkeyField.enabled = isEnabled;
    _hotkeyLabel.labelEnabled = isEnabled;
    _hotkeyTogglesWindow.enabled = isEnabled;

    BOOL hasDedicatedWindow = [iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow];
    _hotkeyAutoHides.enabled = isEnabled && hasDedicatedWindow;
    _hotkeyBookmark.enabled = isEnabled && hasDedicatedWindow;
}

- (void)registerHotkey {
    int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
    int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
    [[HotkeyWindowController sharedInstance] registerHotkey:code
                                                  modifiers:modifiers];
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
    [self performSelector:@selector(registerHotkey) withObject:self afterDelay:0.01];
}


- (void)startEventTapIfNecessary {
    if (([[HotkeyWindowController sharedInstance] isAnyModifierRemapped] &&
         ![[HotkeyWindowController sharedInstance] haveEventTap])) {
        [[HotkeyWindowController sharedInstance] beginRemappingModifiers];
    }
}

- (void)postModifierChangedNotification {
    NSDictionary *userInfo =
        @{ kPSMTabModifierKey: @([iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]]) };
    [[NSNotificationCenter defaultCenter] postNotificationName:kPSMModifierChangedNotification
                                                        object:nil
                                                      userInfo:userInfo];
}

- (void)populateHotKeyProfilesMenu {
    DLog(@"Populating hotkey profiles menu");
    if (!_hotkeyBookmark) {
        return;
    }
    NSString *guid = [iTermPreferences stringForKey:kPreferenceKeyHotkeyProfileGuid];
    [_hotkeyBookmark populateWithProfilesSelectingGuid:guid];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    unsigned int keyMods;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unsigned short keyChar = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int keyCode = [event keyCode];

    [self setHotKeyChar:keyChar code:keyCode mods:keyMods];
}

- (BOOL)anyBookmarkHasKeyMapping:(NSString*)theString {
    for (Profile* bookmark in [[ProfileModel sharedInstance] bookmarks]) {
        if ([iTermKeyBindingMgr haveKeyMappingForKeyString:theString inBookmark:bookmark]) {
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
                                   silenceable:kiTermWarningTypePermanentlySilenceable]) {
        case kiTermWarningSelection1:
            return NO;
        default:
            return YES;
    }
}


#pragma mark - iTermKeyMappingViewControllerDelegate

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyBindingMgr globalKeyMap];
}

- (NSArray *)keyMappingSortedKeys:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyBindingMgr sortedGlobalKeyCombinations];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
 didChangeKeyCombo:(NSString *)keyCombo
            atIndex:(NSInteger)index
          toAction:(int)action
         parameter:(NSString *)parameter
        isAddition:(BOOL)addition {
    NSMutableDictionary *dict =
            [NSMutableDictionary dictionaryWithDictionary:[iTermKeyBindingMgr globalKeyMap]];
    if ([self anyBookmarkHasKeyMapping:keyCombo]) {
        if (![self warnAboutPossibleOverride]) {
            return;
        }
    }
    [iTermKeyBindingMgr setMappingAtIndex:index
                                   forKey:keyCombo
                                   action:action
                                    value:parameter
                                createNew:addition
                             inDictionary:dict];
    [iTermKeyBindingMgr setGlobalKeyMap:dict];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}


- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    removeKeyCombo:(NSString *)keyCombo {
    NSUInteger index = [[iTermKeyBindingMgr sortedGlobalKeyCombinations] indexOfObject:keyCombo];
    assert(index != NSNotFound);
    [iTermKeyBindingMgr setGlobalKeyMap:[iTermKeyBindingMgr removeMappingAtIndex:index
                                                                    inDictionary:[iTermKeyBindingMgr globalKeyMap]]];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyBindingMgr globalPresetNames];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  loadPresetsNamed:(NSString *)presetName {
    [iTermKeyBindingMgr setGlobalKeyMappingsToPreset:presetName];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - Notification handlers

- (void)reloadAddressBookNotification:(NSNotification *)aNotification {
    [self populateHotKeyProfilesMenu];
}

@end
