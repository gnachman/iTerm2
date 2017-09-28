//
//  iTermHotkeyPreferencesModel.m
//  iTerm2
//
//  Created by George Nachman on 7/7/16.
//
//

#import "iTermHotkeyPreferencesModel.h"
#import "NSArray+iTerm.h"

@implementation iTermHotkeyPreferencesModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _autoHide = YES;
        _animate = YES;
    }
    return self;
}

- (void)dealloc {
    [_primaryShortcut release];
    [_alternateShortcuts release];
    [super dealloc];
}

- (NSDictionary<NSString *, id> *)dictionaryValue {
    return @{ KEY_HAS_HOTKEY: @(self.hotKeyAssigned),
              KEY_HOTKEY_ACTIVATE_WITH_MODIFIER: @(self.hasModifierActivation),
              KEY_HOTKEY_MODIFIER_ACTIVATION: @(self.modifierActivation),
              KEY_HOTKEY_KEY_CODE: @(_primaryShortcut.keyCode),
              KEY_HOTKEY_CHARACTERS: _primaryShortcut.characters ?: @"",
              KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS: _primaryShortcut.charactersIgnoringModifiers ?: @"",
              KEY_HOTKEY_MODIFIER_FLAGS: @(_primaryShortcut.modifiers),
              KEY_HOTKEY_AUTOHIDE: @(self.autoHide),
              KEY_HOTKEY_REOPEN_ON_ACTIVATION: @(self.showAutoHiddenWindowOnAppActivation),
              KEY_HOTKEY_ANIMATE: @(self.animate),
              KEY_HOTKEY_FLOAT: @(self.floats),
              KEY_HOTKEY_DOCK_CLICK_ACTION: @(self.dockPreference),
              KEY_HOTKEY_ALTERNATE_SHORTCUTS: [self alternateShortcutDictionaries] ?: @[] };
}

- (NSArray<NSDictionary *> *)alternateShortcutDictionaries {
    return [self.alternateShortcuts mapWithBlock:^id(iTermShortcut *shortcut) {
        return shortcut.dictionaryValue;
    }];
}

- (void)setAlternateShortcutDictionaries:(NSArray<NSDictionary *> *)dictionaries {
    self.alternateShortcuts = [dictionaries mapWithBlock:^id(NSDictionary *dictionary) {
        return [iTermShortcut shortcutWithDictionary:dictionary];
    }];
}

- (BOOL)hotKeyAssigned {
    BOOL hasAlternate = [self.alternateShortcuts anyWithBlock:^BOOL(iTermShortcut *shortcut) {
        return shortcut.charactersIgnoringModifiers.length > 0 || shortcut.characters.length > 0 || shortcut.keyCode != 0;
    }];
    return (_primaryShortcut.isAssigned ||
            self.hasModifierActivation ||
            hasAlternate);
}

@end

