//
//  KeysPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "KeysPreferencesViewController.h"
#import "HotkeyWindowController.h"
#import "iTermKeyBindingMgr.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"
#import "PSMTabBarControl.h"

@implementation KeysPreferencesViewController {
    IBOutlet NSPopUpButton *_controlButton;
    IBOutlet NSPopUpButton *_leftOptionButton;
    IBOutlet NSPopUpButton *_rightOptionButton;
    IBOutlet NSPopUpButton *_leftCommandButton;
    IBOutlet NSPopUpButton *_rightCommandButton;

    IBOutlet NSPopUpButton *_switchTabModifierButton;
    IBOutlet NSPopUpButton *_switchWindowModifierButton;

    IBOutlet NSButton *_hotkeyEnabled;
    IBOutlet NSTextField *_hotkeyField;
    IBOutlet NSTextField *_hotkeyLabel;

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
    // Modifiers for switching tabs.
    info = [self defineControl:_switchTabModifierButton
                           key:kPreferenceKeySwitchTabModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postModifierChangedNotification]; };

    info = [self defineControl:_switchWindowModifierButton
                           key:kPreferenceKeySwitchWindowModifier
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^() { [self postModifierChangedNotification]; };

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_hotkeyEnabled
                           key:kPreferenceKeyHotkeyEnabled
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self hotkeyEnabledDidChange]; };
    [self updateHotkeyFieldValue];
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
        [self updateHotkeyFieldValue];
    }
    [[HotkeyWindowController sharedInstance] saveHotkeyWindowState];
}

- (void)updateHotkeyFieldValue {
    int theChar = [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
    int modifiers = [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
    int code = [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
    if (code || theChar) {
        NSString *identifier = [NSString stringWithFormat:@"0x%x-0x%x", theChar, modifiers];
        _hotkeyField.stringValue = [iTermKeyBindingMgr formatKeyCombination:identifier];
    } else {
        _hotkeyField.stringValue = @"";
    }
    _hotkeyField.enabled = [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
    _hotkeyLabel.enabled = [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
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
    [self updateHotkeyFieldValue];
    [self performSelector:@selector(registerHotkey) withObject:self afterDelay:0.01];
}


- (void)startEventTapIfNecessary {
    PreferencePanel *prefs = [PreferencePanel sharedInstance];
    if (([prefs isAnyModifierRemapped] && ![[HotkeyWindowController sharedInstance] haveEventTap])) {
        [[HotkeyWindowController sharedInstance] beginRemappingModifiers];
    }
}

- (void)postModifierChangedNotification {
    PreferencePanel *prefs = [PreferencePanel sharedInstance];
    NSDictionary *userInfo =
        @{ kPSMTabModifierKey: @([prefs modifierTagToMask:[prefs switchTabModifier]]) };
    [[NSNotificationCenter defaultCenter] postNotificationName:kPSMModifierChangedNotification
                                                        object:nil
                                                      userInfo:userInfo];
}

- (void)hotkeyKeyDown:(NSEvent*)event {
    unsigned int keyMods;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unsigned short keyChar = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int keyCode = [event keyCode];

    [self setHotKeyChar:keyChar code:keyCode mods:keyMods];
}

@end
