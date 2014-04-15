//
//  ProfilesGeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "ProfilesGeneralPreferencesViewController.h"
#import "AdvancedWorkingDirectoryWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"
#import "NSTextField+iTerm.h"
#import "ProfileModel.h"

// Tags for _commandType matrix selectedCell.
static const NSInteger kCommandTypeCustomTag = 0;
static const NSInteger kCommandTypeLoginShellTag = 1;

// Tags for _initialDirectoryType
static const NSInteger kInitialDirectoryTypeCustomTag = 0;
static const NSInteger kInitialDirectoryTypeHomeTag = 1;
static const NSInteger kInitialDirectoryTypeRecycleTag = 2;
static const NSInteger kInitialDirectoryTypeAdvancedTag = 3;

@implementation ProfilesGeneralPreferencesViewController {
    IBOutlet NSTextField *_profileNameField;
    IBOutlet NSPopUpButton *_profileShortcut;
    IBOutlet NSTokenField *_tagsTokenField;
    IBOutlet NSMatrix *_commandType;  // Login shell vs custom command radio buttons
    IBOutlet NSTextField *_customCommand;  // Command to use instead of login shell
    IBOutlet NSTextField *_sendTextAtStart;
    IBOutlet NSMatrix *_initialDirectoryType;  // Home/Reuse/Custom/Advanced
    IBOutlet NSTextField *_customDirectory;  // Path to custom initial directory
    IBOutlet NSButton *_editAdvancedConfigButton;  // Advanced initial directory button
    IBOutlet AdvancedWorkingDirectoryWindowController *_advancedWorkingDirWindowController;
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
    
    [self defineControl:_commandType
                    key:KEY_CUSTOM_COMMAND
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self commandTypeDidChange]; }
                 update:^BOOL { [self updateCommandType]; return YES; }];
    
    info = [self defineControl:_customCommand
                           key:KEY_COMMAND
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL {
        return [_commandType.selectedCell tag] == kCommandTypeCustomTag;
    };
    
    [self defineControl:_sendTextAtStart
                    key:KEY_INITIAL_TEXT
                   type:kPreferenceInfoTypeStringTextField];
    
    [self defineControl:_initialDirectoryType
                    key:KEY_CUSTOM_DIRECTORY
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self directoryTypeDidChange]; }
                 update:^BOOL { [self updateDirectoryType]; return YES; }];
    
    [self defineControl:_customDirectory
                    key:KEY_WORKING_DIRECTORY
                   type:kPreferenceInfoTypeStringTextField];

    [self updateEditAdvancedConfigButton];
}

- (void)copyOwnedValuesToDict:(NSMutableDictionary *)dict {
    [super copyOwnedValuesToDict:dict];
    [_advancedWorkingDirWindowController copyOwnedValuesToDict:dict];
}

- (void)layoutSubviewsForSingleBookmarkMode {
    NSArray *viewsToHide = @[ _profileShortcut,
                              _tagsTokenField,
                              _commandType,
                              _customCommand,
                              _sendTextAtStart,
                              _initialDirectoryType,
                              _customDirectory,
                              _editAdvancedConfigButton,
                             ];
    for (NSView *view in viewsToHide) {
        view.hidden = YES;
    }
}

#pragma mark - Advanced initial directory settings

- (void)updateEditAdvancedConfigButton {
    NSString *directoryType = [self stringForKey:KEY_CUSTOM_DIRECTORY];
    BOOL isAdvanced = [directoryType isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue];
    [_editAdvancedConfigButton setEnabled:isAdvanced];
}

- (IBAction)showAdvancedWorkingDirConfigPanel:(id)sender
{
    [_advancedWorkingDirWindowController window];  // force the window to load
    _advancedWorkingDirWindowController.profile = [self.delegate profilePreferencesCurrentProfile];
    [NSApp beginSheet:_advancedWorkingDirWindowController.window
       modalForWindow:self.view.window
        modalDelegate:self
       didEndSelector:@selector(advancedWorkingDirSheetClosed:returnCode:contextInfo:)
          contextInfo:nil];
}

- (void)advancedWorkingDirSheetClosed:(NSWindow *)sheet
                           returnCode:(int)returnCode
                          contextInfo:(void *)contextInfo {
    for (NSString *key in [_advancedWorkingDirWindowController allKeys]) {
        [self setString:_advancedWorkingDirWindowController.profile[key] forKey:key];
    }
    [sheet close];
}

#pragma mark - Directory type

- (void)directoryTypeDidChange {
    NSInteger tag = [[_initialDirectoryType selectedCell] tag];
    NSString *value;

    switch (tag) {
        case kInitialDirectoryTypeCustomTag:
            value = kProfilePreferenceInitialDirectoryCustomValue;
            break;
            
        case kInitialDirectoryTypeRecycleTag:
            value = kProfilePreferenceInitialDirectoryRecycleValue;
            break;
            
        case kInitialDirectoryTypeAdvancedTag:
            value = kProfilePreferenceInitialDirectoryAdvancedValue;
            break;
            
        case kInitialDirectoryTypeHomeTag:
        default:
            value = kProfilePreferenceInitialDirectoryHomeValue;
            break;
    }
    
    [self setString:value forKey:KEY_CUSTOM_DIRECTORY];
    [self updateEditAdvancedConfigButton];
}

- (void)updateDirectoryType {
    NSDictionary *map =
        @{ kProfilePreferenceInitialDirectoryCustomValue: @(kInitialDirectoryTypeCustomTag),
           kProfilePreferenceInitialDirectoryRecycleValue: @(kInitialDirectoryTypeRecycleTag),
           kProfilePreferenceInitialDirectoryAdvancedValue: @(kInitialDirectoryTypeAdvancedTag),
           kProfilePreferenceInitialDirectoryHomeValue: @(kInitialDirectoryTypeHomeTag) };
    NSString *value = [self stringForKey:KEY_CUSTOM_DIRECTORY];
    NSNumber *tagNumber = map[value];
    if (!tagNumber) {
        tagNumber = @(kInitialDirectoryTypeHomeTag);
    }
    [_initialDirectoryType selectCellWithTag:[tagNumber integerValue]];
    [self updateEditAdvancedConfigButton];
}

#pragma mark - Command Type

- (void)commandTypeDidChange {
    NSInteger tag = [[_commandType selectedCell] tag];
    NSString *value;
    if (tag == kCommandTypeCustomTag) {
        value = kProfilePreferenceCommandTypeCustomValue;
    } else {
        value = kProfilePreferenceCommandTypeLoginShellValue;
    }
    [self setString:value forKey:KEY_CUSTOM_COMMAND];
    [self updateEnabledState];
}

- (void)updateCommandType {
    NSString *value = [self stringForKey:KEY_CUSTOM_COMMAND];
    if ([value isEqualToString:kProfilePreferenceCommandTypeCustomValue]) {
        [_commandType selectCellWithTag:kCommandTypeCustomTag];
    } else {
        [_commandType selectCellWithTag:kCommandTypeLoginShellTag];
    }
    [self updateEnabledState];
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
