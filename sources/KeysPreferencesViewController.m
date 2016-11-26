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
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermModifierRemapper.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
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

    IBOutlet NSPopUpButton *_switchPaneModifierButton;
    IBOutlet NSPopUpButton *_switchTabModifierButton;
    IBOutlet NSPopUpButton *_switchWindowModifierButton;

    // Hotkey
    IBOutlet NSButton *_hotkeyEnabled;
    IBOutlet NSTextField *_hotkeyField;
    IBOutlet NSTextField *_hotkeyLabel;
    IBOutlet NSButton *_configureHotKeyWindow;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)awakeFromNib {
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
                                                                     heading:@"Add Another Hotkey Window Profile?"];
        if (selection == cancel) {
            return;
        } else if (selection == edit) {
            [[PreferencePanel sharedInstance] configureHotkeyForProfile:[profileHotKeys.firstObject profile]];
        }
    }
    iTermHotkeyPreferencesModel *model = [[[iTermHotkeyPreferencesModel alloc] init] autorelease];
    iTermHotkeyPreferencesWindowController *panel = [[iTermHotkeyPreferencesWindowController alloc] init];
    [panel setExplanation:@"This panel helps you configure a new profile that will be bound to a keystroke you assign. Pressing the hotkey (even when iTerm2 is not active) will toggle a special window."];
    panel.descriptorsInUseByOtherProfiles = [[iTermHotKeyController sharedInstance] descriptorsForProfileHotKeysExcept:nil];
    panel.model = model;

    [self.view.window beginSheet:panel.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            if (!model.hotKeyAssigned) {
                return;
            }
            NSMutableDictionary *dict = [[[[ProfileModel sharedInstance] defaultBookmark] mutableCopy] autorelease];
            dict[KEY_WINDOW_TYPE] = @(WINDOW_TYPE_TOP);
            dict[KEY_ROWS] = @25;
            dict[KEY_TRANSPARENCY] = @0.3;
            dict[KEY_BLEND] = @0.5;
            dict[KEY_BLUR_RADIUS] = @2.0;
            dict[KEY_BLUR] = @YES;
            dict[KEY_SCREEN] = @-1;
            dict[KEY_SPACE] = @-1;
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

            NSRunAlertPanel(@"Hotkey Window Successfully Configured",
                            @"A new profile called “%@” was created for you. It is tuned to work well "
                            @"for the Hotkey Window feature and it can be customized in the Profiles tab.",
                            @"OK",
                            nil,
                            nil,
                            newProfileName);
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
            [self setHotKeyChar:' ' code:kVK_Space mods:NSAlternateKeyMask];
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
        NSString *identifier = [NSString stringWithFormat:@"0x%x-0x%x", theChar, modifiers];
        _hotkeyField.stringValue = [iTermKeyBindingMgr formatKeyCombination:identifier];
    } else {
        _hotkeyField.stringValue = @"";
    }

    // Update the enabled status of all other views.
    BOOL isEnabled = [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
    _hotkeyField.enabled = isEnabled;
    _hotkeyLabel.labelEnabled = isEnabled;
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

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    unsigned int keyMods;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unsigned short keyChar = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int keyCode = [event keyCode];

    [self setHotKeyChar:keyChar code:keyCode mods:keyMods];
    
    if (!event) {
        BOOL wasEnabled = [self boolForKey:kPreferenceKeyHotkeyEnabled];
        [self setBool:NO forKey:kPreferenceKeyHotkeyEnabled];
        if (wasEnabled) {
            [self hotkeyEnabledDidChange];
            _hotkeyEnabled.state = NSOffState;
        }
    }
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

- (NSArray *)keyMappingSortedTouchBarKeys:(iTermKeyMappingViewController *)viewController {
    NSDictionary *dict = [iTermKeyBindingMgr globalTouchBarMap];
    return [iTermKeyBindingMgr sortedTouchBarKeysInDictionary:dict];
}

- (NSDictionary *)keyMappingTouchBarItems {
    return [iTermKeyBindingMgr globalTouchBarMap];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
      didChangeKey:(NSString *)theKey
    isTouchBarItem:(BOOL)isTouchBarItem
            atIndex:(NSInteger)index
          toAction:(int)action
         parameter:(NSString *)parameter
             label:(NSString *)label  // for touch bar only
        isAddition:(BOOL)addition {
    NSMutableDictionary *dict;
    if (isTouchBarItem) {
        dict = [NSMutableDictionary dictionaryWithDictionary:[iTermKeyBindingMgr globalTouchBarMap]];
        [iTermKeyBindingMgr updateDictionary:dict forTouchBarItem:theKey action:action value:parameter label:label];
        [iTermKeyBindingMgr setGlobalTouchBarMap:dict];
    } else {
        dict = [NSMutableDictionary dictionaryWithDictionary:[iTermKeyBindingMgr globalKeyMap]];
        if ([self anyBookmarkHasKeyMapping:theKey]) {
            if (![self warnAboutPossibleOverride]) {
                return;
            }
        }
        [iTermKeyBindingMgr setMappingAtIndex:index
                                       forKey:theKey
                                       action:action
                                        value:parameter
                                    createNew:addition
                                 inDictionary:dict];
        [iTermKeyBindingMgr setGlobalKeyMap:dict];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
         removeKey:(NSString *)key
    isTouchBarItem:(BOOL)isTouchBarItem {
    if (isTouchBarItem) {
        [iTermKeyBindingMgr removeTouchBarItem:key];
    } else {
        NSUInteger index = [[iTermKeyBindingMgr sortedGlobalKeyCombinations] indexOfObject:key];
        assert(index != NSNotFound);
        [iTermKeyBindingMgr setGlobalKeyMap:[iTermKeyBindingMgr removeMappingAtIndex:index
                                                                        inDictionary:[iTermKeyBindingMgr globalKeyMap]]];
    }
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

@end
