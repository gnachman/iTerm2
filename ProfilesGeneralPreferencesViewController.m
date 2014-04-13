//
//  ProfilesGeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "ProfilesGeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "NSTextField+iTerm.h"
#import "ProfileModel.h"

@implementation ProfilesGeneralPreferencesViewController {
    IBOutlet NSTextField *_profileNameField;
    IBOutlet NSPopUpButton *_profileShortcut;
    IBOutlet NSTokenField *_tagsTokenField;
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:self.view.window];

    PreferenceInfo *info;
    
    info = [self defineControl:_profileNameField
                           key:KEY_NAME
                          type:kPreferenceInfoTypeStringTextField];
    info.willChange = ^() { [_profileDelegate profilesGeneralPreferencesNameWillChange]; };
    
    [self defineControl:_profileShortcut
                    key:KEY_SHORTCUT
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [self setShortcutValueToSelectedItem]; }
                 update:^BOOL { [self updateShortcutTitles]; return YES; }];
    
    [self defineControl:_tagsTokenField
                    key:KEY_TAGS
                   type:kPreferenceInfoTypeTokenField];
}

- (void)layoutSubviewsForSingleBookmarkMode {
    _profileShortcut.hidden = YES;
    _tagsTokenField.hidden = YES;
}

#pragma mark - Shortcuts

- (void)setShortcutValueToSelectedItem {
    NSString* shortcut = [self shortcutKeyForTag:[[_profileShortcut selectedItem] tag]];
    if (shortcut) {
        Profile *currentProfile = [self.delegate profilePreferencesCurrentProfile];
        
        // If any profile has this shortcut, clear its shortcut.
        NSMutableArray *guidsOfProfilesToModify = [NSMutableArray array];
        for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
            NSString* existingShortcut = profile[KEY_SHORTCUT];
            if ([shortcut length] > 0 &&
                [existingShortcut isEqualToString:shortcut] &&
                profile != currentProfile) {
                [guidsOfProfilesToModify addObject:profile[KEY_GUID]];
            }
        }
        
        if (guidsOfProfilesToModify.count) {
            for (NSString *guid in guidsOfProfilesToModify) {
                Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
                [[ProfileModel sharedInstance] setObject:nil forKey:KEY_SHORTCUT inBookmark:profile];
            }
            [[ProfileModel sharedInstance] flush];
        }
    }
    [self setString:shortcut forKey:KEY_SHORTCUT];
    [self updateShortcutTitles];
    [[ProfileModel sharedInstance] flush];
}

- (NSString*)shortcutKeyForTag:(int)tag {
    if (tag == -1) {
        return @"";
    }
    if (tag >= 0 && tag <= 25) {
        return [NSString stringWithFormat:@"%c", 'A' + tag];
    }
    if (tag >= 100 && tag <= 109) {
        return [NSString stringWithFormat:@"%c", '0' + tag - 100];
    }
    return @"";
}

- (int)shortcutTagForKey:(NSString*)key {
    const char* chars = [key UTF8String];
    if (!chars || !*chars) {
        return -1;
    }
    char c = *chars;
    if (c >= 'A' && c <= 'Z') {
        return c - 'A';
    }
    if (c >= '0' && c <= '9') {
        return 100 + c - '0';
    }
    return -1;
}

- (void)updateShortcutTitles {
    // Reset titles of all shortcuts.
    for (NSMenuItem *item in _profileShortcut.menu.itemArray) {
        [item setTitle:[self shortcutKeyForTag:[item tag]]];
    }
    
    // Add bookmark names to shortcuts that are bound.
    ProfileModel *profileModel = [ProfileModel sharedInstance];
    for (Profile *profile in [profileModel bookmarks]) {
        NSString* existingShortcut = profile[KEY_SHORTCUT];
        const int tag = [self shortcutTagForKey:existingShortcut];
        if (tag != -1) {
            const int theIndex = [_profileShortcut indexOfItemWithTag:tag];
            NSMenuItem *item = [_profileShortcut itemAtIndex:theIndex];
            NSString* newTitle = [NSString stringWithFormat:@"%@ (%@)",
                                  existingShortcut, profile[KEY_NAME]];
            [item setTitle:newTitle];
        }
    }
    
    NSString *theString = [self stringForKey:KEY_SHORTCUT];
    [_profileShortcut selectItemWithTag:[self shortcutTagForKey:theString]];
}

#pragma mark - Notifications

- (void)windowWillClose:(NSNotification *)notification {
    NSResponder *firstResponder = [[[self view] window] firstResponder];
    if (firstResponder && [firstResponder respondsToSelector:@selector(delegate)]) {
        id delegate = [firstResponder performSelector:@selector(delegate)];
        if (delegate == _tagsTokenField) {
            // The token field's editor is the first responder. Force the token field to end editing
            // so the last token entered will be tokenized.
            [self.view.window makeFirstResponder:self.view];
        }
    }
}

#pragma mark - NSTokenField delegate

- (NSArray *)tokenField:(NSTokenField *)tokenField
    completionsForSubstring:(NSString *)substring
               indexOfToken:(NSInteger)tokenIndex
        indexOfSelectedItem:(NSInteger *)selectedIndex {
    ProfileModel *model = [ProfileModel sharedInstance];
    NSArray *allTags = [[model allTags] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *aTag in allTags) {
        if ([aTag hasPrefix:substring]) {
            [result addObject:[aTag retain]];
        }
    }
    return result;
}

- (id)tokenField:(NSTokenField *)tokenField
    representedObjectForEditingString:(NSString *)editingString {
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - NSTokenFieldCell delegate

- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
    representedObjectForEditingString:(NSString *)editingString {
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end
