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
#import "iTermAPIHelper.h"
#import "iTermBadgeConfigurationWindowController.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermImageWell.h"
#import "iTermLaunchServices.h"
#import "iTermNotificationCenter.h"
#import "iTermProfilePreferences.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermSessionTitleBuiltInFunction.h"
#import "iTermShortcutInputView.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"
#import "iTermVariableScope+Window.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "ProfileListView.h"
#import "ProfileModel.h"
#import "PreferencePanel.h"
#import "PTYSession.h"

// Tags for _commandType matrix selectedCell.
static const NSInteger kCommandTypeCustomTag = 0;
static const NSInteger kCommandTypeLoginShellTag = 1;

// Tags for _initialDirectoryType
static const NSInteger kInitialDirectoryTypeCustomTag = 0;
static const NSInteger kInitialDirectoryTypeHomeTag = 1;
static const NSInteger kInitialDirectoryTypeRecycleTag = 2;
static const NSInteger kInitialDirectoryTypeAdvancedTag = 3;

static NSString *const iTermProfilePreferencesUpdateSessionName = @"iTermProfilePreferencesUpdateSessionName";

@interface ProfilesGeneralPreferencesViewController () <iTermImageWellDelegate, iTermShortcutInputViewDelegate, NSMenuDelegate, NSTabViewDelegate, ProfileListViewDelegate>
@end

@implementation ProfilesGeneralPreferencesViewController {
    // Labels
    IBOutlet NSTextField *_basicsLabel;
    IBOutlet NSTextField *_shortcutLabel;
    IBOutlet NSTextField *_tagsLabel;
    IBOutlet NSTextField *_commandLabel;
    IBOutlet NSTextField *_sendTextAtStartLabel;
    IBOutlet NSTextField *_directoryLabel;
    IBOutlet NSTextField *_schemesHeaderLabel;
    IBOutlet NSTextField *_schemesLabel;

    // Controls
    IBOutlet NSTextField *_profileNameField;
    IBOutlet NSTextField *_profileNameFieldForEditCurrentSession;
    IBOutlet NSPopUpButton *_profileShortcut;
    IBOutlet NSTokenField *_tagsTokenField;
    IBOutlet NSMatrix *_commandType;  // Login shell vs custom command radio buttons
    IBOutlet NSTextField *_customCommand;  // Command to use instead of login shell
    IBOutlet NSTextField *_sendTextAtStart;
    IBOutlet NSMatrix *_initialDirectoryType;  // Home/Reuse/Custom/Advanced
    IBOutlet NSTextField *_customDirectory;  // Path to custom initial directory
    IBOutlet NSButton *_editAdvancedConfigButton;  // Advanced initial directory button
    IBOutlet AdvancedWorkingDirectoryWindowController *_advancedWorkingDirWindowController;
    IBOutlet NSPopUpButton *_urlSchemes;
    IBOutlet NSTextField *_badgeText;
    IBOutlet NSTextField *_badgeTextForEditCurrentSession;
    iTermFunctionCallTextFieldDelegate *_badgeTextFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_badgeTextForEditCurrentSessionFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_tabTitleTextFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_windowTitleTextFieldDelegate;
    IBOutlet NSPopUpButton *_titleSettingsForEditCurrentSession;
    IBOutlet NSPopUpButton *_icon;
    IBOutlet NSImageView *_imageWell;
    IBOutlet NSTextField *_tabTitle;
    IBOutlet NSTextField *_windowTitle;

    // Controls for Edit Info
    IBOutlet ProfileListView *_profiles;
    IBOutlet iTermShortcutInputView *_sessionHotkeyInputView;

    IBOutlet NSView *_editCurrentSessionView;
    IBOutlet NSButton *_copySettingsToProfile;
    IBOutlet NSButton *_copyProfileToSession;
    IBOutlet NSPopUpButton *_titleSettings;
    IBOutlet NSButton *_customTitleHelp;

    BOOL _profileNameChangePending;
    iTermRateLimitedUpdate *_rateLimit;
    IBOutlet NSTabView *_tabView;
    NSRect _desiredFrame;
}

- (void)dealloc {
    _profileNameFieldForEditCurrentSession.delegate = nil;
}

- (void)awakeFromNib {
    _rateLimit = [[iTermRateLimitedUpdate alloc] init];
    _rateLimit.minimumInterval = 0.75;
    
    PreferenceInfo *info;
    __weak __typeof(self) weakSelf = self;

    info = [self defineControl:_profileNameField
                           key:KEY_NAME
                          type:kPreferenceInfoTypeStringTextField];
    __weak PreferenceInfo *weakInfo = info;
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameWillChange];
        assert(weakInfo);
        [strongSelf setString:strongSelf->_profileNameField.stringValue forKey:weakInfo.key];
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameDidChange];
    };
    info.willChange = ^() {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameWillChange];
    };

    info = [self defineControl:_profileNameFieldForEditCurrentSession
                           key:KEY_NAME
                          type:kPreferenceInfoTypeStringTextField];
    info.willChange = ^() {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameWillChange];
    };
    info.onChange = ^() {
        [weakSelf ensureSessionNameVisible];
    };
    info.controlTextDidEndEditing = ^(NSNotification *notification) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_profileDelegate profilesGeneralPreferencesNameDidEndEditing];
    };

    info = [self defineControl:_icon
                           key:KEY_ICON
                          type:kPreferenceInfoTypePopup];
    info.onChange = ^{
        [weakSelf iconDidChange];
    };
    info.observer = ^{
        [weakSelf updateImageWell];
    };
    [self updateImageWell];
    [self updateImageWellHidden];

    [self defineControl:_profileShortcut
                    key:KEY_SHORTCUT
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf setShortcutValueToSelectedItem]; }
                 update:^BOOL { [weakSelf updateShortcutTitles]; return YES; }];

    [self defineControl:_tagsTokenField
                    key:KEY_TAGS
                   type:kPreferenceInfoTypeTokenField];

    [self defineControl:_commandType
                    key:KEY_CUSTOM_COMMAND
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [weakSelf commandTypeDidChange]; }
                 update:^BOOL { [weakSelf updateCommandType]; return YES; }];

    info = [self defineControl:_customCommand
                           key:KEY_COMMAND_LINE
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return NO;
        }
        return [strongSelf->_commandType.selectedCell tag] == kCommandTypeCustomTag;
    };

    [self defineControl:_sendTextAtStart
                    key:KEY_INITIAL_TEXT
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_initialDirectoryType
                    key:KEY_CUSTOM_DIRECTORY
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [weakSelf directoryTypeDidChange]; }
                 update:^BOOL { [weakSelf updateDirectoryType]; return YES; }];

    [self defineControl:_customDirectory
                    key:KEY_WORKING_DIRECTORY
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_badgeText
                    key:KEY_BADGE_FORMAT
                   type:kPreferenceInfoTypeStringTextField];
    _badgeTextFieldDelegate =
        [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                           passthrough:_badgeText.delegate
                                                         functionsOnly:NO];
    _badgeText.delegate = _badgeTextFieldDelegate;

    [self defineControl:_badgeTextForEditCurrentSession
                    key:KEY_BADGE_FORMAT
                   type:kPreferenceInfoTypeStringTextField];
    _badgeTextForEditCurrentSessionFieldDelegate =
        [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                           passthrough:_badgeTextForEditCurrentSession.delegate
                                                         functionsOnly:NO];
    _badgeTextForEditCurrentSession.delegate = _badgeTextForEditCurrentSessionFieldDelegate;

    _tabTitleTextFieldDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextTab]
                                                       passthrough:_tabTitle.delegate
                                                     functionsOnly:NO];
    _tabTitle.delegate = _tabTitleTextFieldDelegate;

    _windowTitleTextFieldDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextWindow]
                                                       passthrough:_windowTitle.delegate
                                                     functionsOnly:NO];
    _windowTitle.delegate = _windowTitleTextFieldDelegate;

    [self defineControl:_titleSettings
                    key:KEY_TITLE_COMPONENTS
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf toggleSelectedTitleComponent]; }
                 update:^BOOL {
                     [self updateTitleSettingsMenu];
                     [self updateSelectedTitleComponents];
                     return YES;
                 }];
    [self defineControl:_titleSettingsForEditCurrentSession
                    key:KEY_TITLE_COMPONENTS
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf toggleSelectedTitleComponent]; }
                 update:^BOOL {
                     [self updateTitleSettingsMenu];
                     [self updateSelectedTitleComponents];
                     return YES;
                 }];
    [self updateSelectedTitleComponents];

    [_profiles selectRowByGuid:[self.delegate profilePreferencesCurrentProfile][KEY_ORIGINAL_GUID]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateProfileName)
                                                 name:iTermProfilePreferencesUpdateSessionName
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didRegisterSessionTitleFunc:)
                                                 name:iTermAPIDidRegisterSessionTitleFunctionNotification
                                               object:nil];
    [self updateEditAdvancedConfigButton];
}

// User interacted with it
- (void)iconDidChange {
    const iTermProfileIcon icon = [self unsignedIntegerForKey:KEY_ICON];
    if (icon == iTermProfileIconCustom && _imageWell.image == nil) {
        [self openFilePicker];
        _imageWell.hidden = NO;
    } else if (icon != iTermProfileIconCustom) {
        _imageWell.hidden = YES;
    } else {
        _imageWell.hidden = NO;
    }
}

- (void)updateImageWell {
    NSString *iconPath = [self stringForKey:KEY_ICON_PATH];
    _imageWell.image = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
}

- (void)openFilePicker {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = NO;
    [panel setAllowedFileTypes:[NSImage imageTypes]];

    void (^completion)(NSInteger) = ^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            NSURL *url = [[panel URLs] objectAtIndex:0];
            if (![self loadIconWithFilename:url.path]) {
                NSBeep();
            }
        }
        if (self->_imageWell.image == nil) {
            [self setUnsignedInteger:iTermProfileIconNone forKey:KEY_ICON];
        }
        [self updateImageWellHidden];
    };

    [panel beginSheetModalForWindow:self.view.window completionHandler:completion];
}

- (BOOL)loadIconWithFilename:(NSString *)path {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (image) {
        [self setString:path forKey:KEY_ICON_PATH];
    }
    _imageWell.image = image;
    return image != nil;
}

- (void)updateImageWellHidden {
    _imageWell.hidden = ([self unsignedIntegerForKey:KEY_ICON] != iTermProfileIconCustom ||
                         _imageWell.image == nil);
}

- (void)windowWillClose {
    if (_profileNameChangePending) {
        [self updateProfileName];
    }
    [_rateLimit invalidate];
    if ([_tagsTokenField textFieldIsFirstResponder]) {
        // The token field's editor is the first responder. Force the token field to end editing
        // so the last token entered will be tokenized and prefs saved with it.
        [self.view.window makeFirstResponder:self.view];
    } else if ([_profileNameFieldForEditCurrentSession textFieldIsFirstResponder]) {
        [_profileDelegate profilesGeneralPreferencesNameDidEndEditing];
    }
}

- (NSArray *)keysForBulkCopy {
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:[_advancedWorkingDirWindowController allKeys]];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    self.view = _editCurrentSessionView;
}

- (id<iTermSessionScope>)scope {
    return [self.profileDelegate profilesGeneralPreferencesScope];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self populateBookmarkUrlSchemesFromProfile:[self.delegate profilePreferencesCurrentProfile]];
    [_profiles selectRowByGuid:[self.delegate profilePreferencesCurrentProfile][KEY_ORIGINAL_GUID]];
    _sessionHotkeyInputView.shortcut = [iTermShortcut shortcutWithDictionary:(NSDictionary *)[self objectForKey:KEY_SESSION_HOTKEY]];
    id<iTermSessionScope> scope = self.scope;
    if (scope) {
        _tabTitle.stringValue =  scope.tab.tabTitleOverrideFormat ?: @"";
        _windowTitle.stringValue = scope.tab.window.windowTitleOverrideFormat ?: @"";
    }
}

- (NSString *)selectedGuid {
    return [_profiles selectedGuid];
}

- (void)ensureSessionNameVisible {
    // Unless a custom title function is in use, ensure session name is visible in the title.
    NSUInteger components = [self unsignedIntegerForKey:KEY_TITLE_COMPONENTS];

    if (components & (iTermTitleComponentsSessionName | iTermTitleComponentsProfileAndSessionName)) {
        return;
    }
    if (components == iTermTitleComponentsCustom) {
        return;
    }
    if (components & iTermTitleComponentsProfileName) {
        NSUInteger updated = components;
        updated &= ~iTermTitleComponentsProfileName;
        updated |= iTermTitleComponentsProfileAndSessionName;
        [self setUnsignedInteger:updated
                          forKey:KEY_TITLE_COMPONENTS];
        return;
    }
    [self setUnsignedInteger:(components | iTermTitleComponentsSessionName)
                      forKey:KEY_TITLE_COMPONENTS];
}

- (void)updateTitleSettingsMenu {
    [self updateTitleSettingsMenuForView:_titleSettings];
    [self updateTitleSettingsMenuForView:_titleSettingsForEditCurrentSession];
}

- (void)updateTitleSettingsMenuForView:(NSPopUpButton *)titleSettings {
    // First remove any programmatically added items
    NSIndexSet *indexSet = [titleSettings.menu.itemArray indexesOfObjectsPassingTest:^BOOL(NSMenuItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.tag == -1;
    }];
    [indexSet enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [titleSettings.menu removeItemAtIndex:idx];
    }];

    NSArray<iTermSessionTitleProvider *> *funcs = [iTermAPIHelper sessionTitleFunctions];
    if (funcs.count) {
        NSMenuItem *separator = [NSMenuItem separatorItem];
        separator.identifier = @"";
        [titleSettings.menu addItem:separator];
    }
    NSString *uniqueIdentifier = [self titleFunctionUniqueIdentifier];
    NSString *funcName = [self titleFunctionDisplayName];
    for (iTermSessionTitleProvider *provider in funcs) {
        NSMenuItem *item = [[NSMenuItem alloc] init];
        item.title = provider.displayName;
        item.identifier = provider.uniqueIdentifier;
        if (uniqueIdentifier && [uniqueIdentifier isEqualToString:provider.uniqueIdentifier]) {
            uniqueIdentifier = nil;
        }
        item.tag = -1;
        [titleSettings.menu addItem:item];
    }
    if (uniqueIdentifier) {
        // Did not find the currently selected func. Maybe the script hasn't started, crashed, etc.
        NSMenuItem *item = [[NSMenuItem alloc] init];
        item.title = funcName;
        item.identifier = uniqueIdentifier;
        item.enabled = NO;
        item.tag = -1;
        [titleSettings.menu addItem:item];
    }
}

#pragma mark - Badge

- (IBAction)configureBadge:(id)sender {
    iTermBadgeConfigurationWindowController *badgeConfigurationWindowController =
    [[iTermBadgeConfigurationWindowController alloc] initWithProfile:[self.delegate profilePreferencesCurrentProfile]];
    [badgeConfigurationWindowController window];  // force the window to load
    __weak typeof(self) weakSelf = self;
    [self.view.window beginSheet:badgeConfigurationWindowController.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        if (!badgeConfigurationWindowController.ok) {
            return;
        }
        NSDictionary *mutations = badgeConfigurationWindowController.profileMutations;
        [mutations enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull value, BOOL * _Nonnull stop) {
            [strongSelf setObject:value forKey:key];
        }];
        [badgeConfigurationWindowController.window close];
    }];
}

#pragma mark - Copy current session to Profile

// Replace a Profile in the sessions profile with a new dictionary that preserves the original
// name and guid, takes all other fields from |bookmark|, and has KEY_ORIGINAL_GUID point at the
// guid of the profile from which all that data came.n
- (IBAction)changeProfile:(id)sender {
    NSString *guid = [_profiles selectedGuid];
    if (guid) {
        Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        Profile *origProfile = [self.delegate profilePreferencesCurrentProfile];
        NSString* origGuid = origProfile[KEY_GUID];
        [[ProfileModel sessionsInstance] setProfilePreservingGuidWithGuid:origGuid
                                                              fromProfile:bookmark];
        [self reloadProfile];
    }
}

#pragma mark - URL Schemes

- (BOOL)profileHandlesScheme:(NSString *)scheme {
    Profile *handler = [[iTermLaunchServices sharedInstance] profileForScheme:scheme];
    NSString *guid = [self stringForKey:KEY_GUID];
    return (handler &&
            [[handler objectForKey:KEY_GUID] isEqualToString:guid] &&
            [[iTermLaunchServices sharedInstance] iTermIsDefaultForScheme:scheme]);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.menu == _urlSchemes.menu) {
        menuItem.state = [self profileHandlesScheme:menuItem.title] ? NSOnState : NSOffState;
    }
    return YES;
}

- (IBAction)urlSchemeHandlerDidChange:(id)sender {
    Profile *profile = [self.delegate profilePreferencesCurrentProfile];
    NSString *guid = profile[KEY_GUID];
    NSString *scheme = [[_urlSchemes selectedItem] title];
    iTermLaunchServices *schemeController = [iTermLaunchServices sharedInstance];
    NSString *boundGuid = [schemeController guidForScheme:scheme];
    if ([boundGuid isEqualToString:guid]) {
        [schemeController disconnectHandlerForScheme:scheme];
    } else {
        [schemeController connectBookmarkWithGuid:guid toScheme:scheme];
    }
    [self populateBookmarkUrlSchemesFromProfile:[[ProfileModel sharedInstance] bookmarkWithGuid:guid]];
}

- (void)populateBookmarkUrlSchemesFromProfile:(Profile*)profile {
    if ([[[_urlSchemes menu] itemArray] count] == 0) {
        NSArray* urlArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        [_urlSchemes addItemWithTitle:@"Select URL Schemes…"];
        for (NSDictionary *dict in urlArray) {
            NSString *scheme = dict[@"CFBundleURLSchemes"][0];
            [_urlSchemes addItemWithTitle:scheme];
        }
        [_urlSchemes setTitle:@"Select URL Schemes…"];
    }

    [[_urlSchemes menu] setAutoenablesItems:YES];
    [[_urlSchemes menu] setDelegate:self];
}

#pragma mark - Advanced initial directory settings

- (void)updateEditAdvancedConfigButton {
    NSString *directoryType = [self stringForKey:KEY_CUSTOM_DIRECTORY];
    BOOL isAdvanced = [directoryType isEqualToString:kProfilePreferenceInitialDirectoryAdvancedValue];
    [_editAdvancedConfigButton setEnabled:isAdvanced];
}

- (IBAction)showAdvancedWorkingDirConfigPanel:(id)sender {
    [_advancedWorkingDirWindowController window];  // force the window to load
    _advancedWorkingDirWindowController.profile = [self.delegate profilePreferencesCurrentProfile];
    __weak typeof(self) weakSelf = self;
    [self.view.window beginSheet:_advancedWorkingDirWindowController.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return;
        }
        for (NSString *key in [strongSelf->_advancedWorkingDirWindowController allKeys]) {
            [strongSelf setString:strongSelf->_advancedWorkingDirWindowController.profile[key] forKey:key];
        }
        [strongSelf->_advancedWorkingDirWindowController.window close];
    }];
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
        NSString *theKey = [self shortcutKeyForTag:[item tag]];
        if (theKey.length) {
            theKey = [@"⌘⌃" stringByAppendingString:theKey];
        }
        [item setTitle:theKey];
    }

    // Add bookmark names to shortcuts that are bound.
    ProfileModel *profileModel = [ProfileModel sharedInstance];
    for (Profile *profile in [profileModel bookmarks]) {
        NSString* existingShortcut = profile[KEY_SHORTCUT];
        const int tag = [self shortcutTagForKey:existingShortcut];
        if (tag != -1) {
            const int theIndex = [_profileShortcut indexOfItemWithTag:tag];
            NSMenuItem *item = [_profileShortcut itemAtIndex:theIndex];
            NSString* newTitle = [NSString stringWithFormat:@"⌃⌘%@ (%@)",
                                  existingShortcut, profile[KEY_NAME]];
            [item setTitle:newTitle];
        }
    }

    NSString *theString = [self stringForKey:KEY_SHORTCUT];
    [_profileShortcut selectItemWithTag:[self shortcutTagForKey:theString]];
    [_profileShortcut sizeToFit];
}

#pragma mark - Title Components

- (void)toggleSelectedTitleComponent {
    [self toggleSelectedTitleComponentForView:_titleSettings];
    [self toggleSelectedTitleComponentForView:_titleSettingsForEditCurrentSession];
}

- (void)toggleSelectedTitleComponentForView:(NSPopUpButton *)titleSettings {
    NSMenuItem *menuItem = [NSMenuItem castFrom:[titleSettings selectedItem]];
    if (menuItem.tag == -1) {
        // Selected a registered title function.
        NSString *uniqueIdentifier = menuItem.identifier;
        NSString *displayName = menuItem.title;
        iTermTuple<NSString *, NSString *> *tuple = [iTermTuple tupleWithObject:displayName andObject:uniqueIdentifier];
        [self setTuple:tuple forKey:KEY_TITLE_FUNC];

        [self setUnsignedInteger:iTermTitleComponentsCustom forKey:KEY_TITLE_COMPONENTS];
        [self updateSelectedTitleComponents];
        return;
    }

    const iTermTitleComponents originalValue = [self unsignedIntegerForKey:KEY_TITLE_COMPONENTS];
    const iTermTitleComponents selectedTag = (iTermTitleComponents)titleSettings.selectedItem.tag;
    NSUInteger newValue = originalValue;

    if (selectedTag == iTermTitleComponentsCustom &&
        originalValue != iTermTitleComponentsCustom) {
        newValue = iTermTitleComponentsCustom;
    } else {
        newValue &= ~iTermTitleComponentsCustom;
        newValue ^= selectedTag;
    }

    NSUInteger nameTagsMask = (iTermTitleComponentsProfileName |
                               iTermTitleComponentsSessionName |
                               iTermTitleComponentsProfileAndSessionName);
    if (selectedTag & nameTagsMask) {
        // Selected a name tag. Deselect all other name tags. Toggle the selected one.
        const NSUInteger originalTitleBits = (originalValue & nameTagsMask);
        const NSUInteger toggledTitleBits = (originalTitleBits ^ selectedTag);
        const NSUInteger nonTitleBits = (newValue & ~nameTagsMask);
        const NSUInteger selectedBit = (selectedTag & toggledTitleBits);
        newValue = nonTitleBits | selectedBit;
    }

    if (newValue == 0 && originalValue != 0) {
        newValue = originalValue;
    } else if (newValue == 0) {
        // Shouldn't happen
        newValue = iTermTitleComponentsSessionName;
    }
    [self setUnsignedInteger:newValue forKey:KEY_TITLE_COMPONENTS];
    [self updateSelectedTitleComponents];
}

- (iTermTuple<NSString *, NSString *> *)stringTupleForKey:(NSString *)key {
    return [iTermTuple fromPlistValue:[self objectForKey:key]];
}

- (void)setTuple:(iTermTuple<NSString *, NSString *> *)tuple forKey:(NSString *)key {
    [self setObject:tuple.plistValue forKey:key];
}

- (NSString *)titleFunctionDisplayName {
    return [[self stringTupleForKey:KEY_TITLE_FUNC] firstObject];
}

- (NSString *)titleFunctionUniqueIdentifier {
    return [[self stringTupleForKey:KEY_TITLE_FUNC] secondObject];
}

- (void)updateSelectedTitleComponents {
    [self updateSelectedTitleComponentsForView:_titleSettings];
    [self updateSelectedTitleComponentsForView:_titleSettingsForEditCurrentSession];
}

- (void)updateSelectedTitleComponentsForView:(NSPopUpButton *)titleSettings {
    const iTermTitleComponents value = [self unsignedIntegerForKey:KEY_TITLE_COMPONENTS];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *currentUniqueIdentifier = self.titleFunctionUniqueIdentifier;
    NSString *customName = nil;
    for (NSMenuItem *item in titleSettings.menu.itemArray) {
        BOOL selected = !!(item.tag & value);
        if (value & iTermTitleComponentsCustom) {
            selected = [NSObject object:item.identifier isEqualToObject:currentUniqueIdentifier];
            customName = [self titleFunctionDisplayName];
        } else if (item.tag == -1) {
            selected = NO;
        }
        item.state = selected ? NSOnState : NSOffState;
        if (selected) {
            [parts addObject:item.title];
        }
    }

    titleSettings.title = customName ?: [iTermSessionTitleBuiltInFunction titleForSessionName:@"Name"
                                                                                  profileName:@"Profile"
                                                                                          job:@"Job"
                                                                                          pwd:@"PWD"
                                                                                          tty:@"TTY"
                                                                                         user:@"User"
                                                                                         host:@"Host"
                                                                                         tmux:nil
                                                                                     iconName:@"“Shell”"
                                                                                   windowName:@""
                                                                                   components:value];

    const CGFloat maxWidth = NSMinX(_customTitleHelp.frame) - NSMinX(titleSettings.frame) - 5;
    [titleSettings sizeToFit];
    NSRect frame = titleSettings.frame;
    frame.size.width = MIN(maxWidth, frame.size.width);
    titleSettings.frame = frame;
}

- (IBAction)titleHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/documentation-session-title.html"]];
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
            [result addObject:aTag];
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

#pragma mark - ProfileListViewDelegate

- (void)profileTableSelectionDidChange:(id)profileTable {
    [_copySettingsToProfile setEnabled:[_profiles hasSelection]];
    [_copyProfileToSession setEnabled:[_profiles hasSelection]];
}

- (void)profileTableRowSelected:(id)profileTable {
    [self changeProfile:self];
}

#pragma mark - iTermShortcutInputViewDelegate

- (void)shortcutInputView:(iTermShortcutInputView *)view didReceiveKeyPressEvent:(NSEvent *)event {
    [self setObject:view.shortcut.dictionaryValue forKey:KEY_SESSION_HOTKEY];
    [_profileDelegate profilesGeneralPreferencesSessionHotkeyDidChange];
}

#pragma mark - NSControlSubclassNotifications

- (void)controlTextDidChange:(NSNotification *)aNotification {
    id control = [aNotification object];
    if (control == _profileNameFieldForEditCurrentSession) {
        [self sessionNameDidChange];
        return;
    }
    if (control == _tabTitle) {
        [self tabTitleDidChange];
        return;
    }
    if (control == _windowTitle) {
        [self windowTitleDidChange];
    }
    [super controlTextDidChange:aNotification];
}

- (void)sessionNameDidChange {
    _profileNameChangePending = YES;
    [_rateLimit performRateLimitedSelector:@selector(postUpdateSessionNameNotification)
                                  onTarget:self
                                withObject:nil];
}

- (void)tabTitleDidChange {
    NSString *value = _tabTitle.stringValue;
    if (value.length == 0) {
        value = nil;
    }
    self.scope.tab.tabTitleOverrideFormat = value;
}

- (void)windowTitleDidChange {
    NSString *value = _windowTitle.stringValue;
    if (value.length == 0) {
        value = nil;
    }
    self.scope.tab.window.windowTitleOverrideFormat = value;
}

#pragma mark - Notifications

- (void)postUpdateSessionNameNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermProfilePreferencesUpdateSessionName object:nil];
}

- (void)updateProfileName {
    if (_profileNameChangePending) {
        [self settingChanged:_profileNameFieldForEditCurrentSession];
        _profileNameChangePending = NO;
    }
}

- (void)didRegisterSessionTitleFunc:(NSNotification *)notification {
    [self updateTitleSettingsMenu];
    [self updateSelectedTitleComponents];
}

#pragma mark - iTermImageWellDelegate

- (void)imageWellDidClick:(iTermImageWell *)imageWell {
    [self openFilePicker];
}

- (void)imageWellDidPerformDropOperation:(iTermImageWell *)imageWell filename:(NSString *)filename {
    [self loadIconWithFilename:filename];
}

@end
