//
//  ProfilesGeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/11/14.
//
//

#import "ProfilesGeneralPreferencesViewController.h"

#import "AdvancedWorkingDirectoryWindowController.h"
#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermBadgeConfigurationWindowController.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermImageWell.h"
#import "iTermLaunchServices.h"
#import "iTermNotificationCenter.h"
#import "iTermObject.h"
#import "iTermProfilePreferences.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermSessionTitleBuiltInFunction.h"
#import "iTermShortcutInputView.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"
#import "iTermVariableScope+Window.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "ProfileListView.h"
#import "ProfileModel.h"
#import "PreferencePanel.h"
#import "PTYSession.h"

// Tags for _commandType matrix selectedCell.
typedef NS_ENUM(NSInteger, iTermGeneralProfilePreferenceCustomCommandTag) {
    iTermGeneralProfilePreferenceCustomCommandTagCustom = 0,
    iTermGeneralProfilePreferenceCustomCommandTagLoginShell = 1,
    iTermGeneralProfilePreferenceCustomCommandTagCustomShell = 2
};

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
    IBOutlet NSTextField *_profileNameFieldLabel;

    IBOutlet NSTextField *_profileNameFieldForEditCurrentSession;
    IBOutlet NSPopUpButton *_profileShortcut;
    IBOutlet NSTokenField *_tagsTokenField;
    IBOutlet NSPopUpButton *_commandType;  // Login shell vs custom command
    IBOutlet NSTextField *_customCommand;  // Command to use instead of login shell
    IBOutlet NSTextField *_sendTextAtStart;
    IBOutlet NSMatrix *_initialDirectoryType;  // Home/Reuse/Custom/Advanced
    IBOutlet NSTextField *_customDirectory;  // Path to custom initial directory
    IBOutlet NSButton *_editAdvancedConfigButton;  // Advanced initial directory button
    IBOutlet AdvancedWorkingDirectoryWindowController *_advancedWorkingDirWindowController;
    IBOutlet NSPopUpButton *_urlSchemes;
    IBOutlet NSTextField *_badgeText;
    IBOutlet NSTextField *_badgeLabel;
    IBOutlet NSTextField *_badgeTextForEditCurrentSession;
    IBOutlet NSButton *_editBadgeButton;
    IBOutlet NSTextField *_subtitleLabel;
    IBOutlet NSTextField *_subtitleText;

    iTermFunctionCallTextFieldDelegate *_commandDelegate;
    iTermFunctionCallTextFieldDelegate *_sendTextAtStartDelegate;
    iTermFunctionCallTextFieldDelegate *_profileNameFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_profileNameFieldForEditCurrentSessionDelegate;
    iTermFunctionCallTextFieldDelegate *_badgeTextFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_badgeTextForEditCurrentSessionFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_tabTitleTextFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_windowTitleTextFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_customDirectoryTextFieldDelegate;
    iTermFunctionCallTextFieldDelegate *_subtitleTextDelegate;

    IBOutlet NSPopUpButton *_titleSettingsForEditCurrentSession;
    IBOutlet NSView *_iconContainer;
    IBOutlet NSPopUpButton *_icon;
    IBOutlet NSTextField *_iconLabel;
    IBOutlet NSImageView *_imageWell;
    IBOutlet NSTextField *_tabTitle;
    IBOutlet NSTextField *_windowTitle;
    IBOutlet NSButton *_allowTitleSetting;
    IBOutlet NSButton *_locked;

    IBOutlet NSView *_tallTabBarRequestView;

    // Controls for Edit Info
    IBOutlet ProfileListView *_profiles;
    IBOutlet iTermShortcutInputView *_sessionHotkeyInputView;

    IBOutlet NSView *_editCurrentSessionView;
    IBOutlet NSButton *_copySettingsToProfile;
    IBOutlet NSButton *_copyProfileToSession;
    IBOutlet NSPopUpButton *_titleSettings;
    IBOutlet NSTextField *_titleSettingsLabel;
    IBOutlet NSButton *_customTitleHelp;

    IBOutlet NSButton *_preventAutomaticProfileSwitching;

    BOOL _profileNameChangePending;
    iTermRateLimitedUpdate *_rateLimit;
    IBOutlet NSTabView *_tabView;
    NSRect _desiredFrame;
}

- (void)dealloc {
    _profileNameFieldForEditCurrentSession.delegate = nil;
}

- (void)awakeFromNib {
    _rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"General prefs" minimumInterval:0.75];
    
    PreferenceInfo *info;
    __weak __typeof(self) weakSelf = self;

    [self defineControl:_allowTitleSetting
                    key:KEY_ALLOW_TITLE_SETTING
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    
    info = [self defineControl:_profileNameField
                           key:KEY_NAME
                   displayName:@"Profile name"
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

    _profileNameFieldDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                       passthrough:_profileNameField.delegate
                                                     functionsOnly:NO];
    _profileNameField.delegate = _profileNameFieldDelegate;

    info = [self defineUnsearchableControl:_profileNameFieldForEditCurrentSession
                                       key:KEY_NAME
                                      type:kPreferenceInfoTypeStringTextField];
    // Initialize with tmux pane title from server, if available.
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
        [weakSelf sessionNameDidEndEditing];
    };
    info.onUpdate = ^BOOL{
        return [weakSelf onUpdateTitle];
    };
    _profileNameFieldForEditCurrentSessionDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                       passthrough:_profileNameFieldForEditCurrentSession.delegate
                                                     functionsOnly:NO];
    _profileNameFieldForEditCurrentSession.delegate = _profileNameFieldForEditCurrentSessionDelegate;

    info = [self defineControl:_icon
                           key:KEY_ICON
                   displayName:@"Profile icon"
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
            displayName:@"Open profile shortcut keystroke"
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf setShortcutValueToSelectedItem]; }
                 update:^BOOL { [weakSelf updateShortcutTitles]; return YES; }];

    [self defineControl:_tagsTokenField
                    key:KEY_TAGS
            displayName:@"Profile tags"
                   type:kPreferenceInfoTypeTokenField];

    [self defineControl:_commandType
                    key:KEY_CUSTOM_COMMAND
            displayName:@"Profile uses login shell, custom shell, or custom command"
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf commandTypeDidChange]; }
                 update:^BOOL { [weakSelf updateCommandType]; return YES; }];

    _customCommand.cell.usesSingleLineMode = YES;
    _customCommand.hidden = YES;

    _commandDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                       passthrough:_customCommand.delegate
                                                     functionsOnly:NO];
    if ([[self objectForKey:KEY_CUSTOM_COMMAND] isEqual:kProfilePreferenceCommandTypeCustomValue]) {
        _customCommand.delegate = _commandDelegate;
    }

    info = [self defineControl:_customCommand
                           key:KEY_COMMAND_LINE
                   displayName:@"Profile custom ommand"
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL {
        __strong __typeof(weakSelf) strongSelf = self;
        if (!strongSelf) {
            return NO;
        }
        return strongSelf->_commandType.selectedTag != iTermGeneralProfilePreferenceCustomCommandTagLoginShell;
    };

    [self defineControl:_sendTextAtStart
                    key:KEY_INITIAL_TEXT
            relatedView:_sendTextAtStartLabel
                   type:kPreferenceInfoTypeStringTextField];

    _sendTextAtStartDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                       passthrough:_sendTextAtStart.delegate
                                                     functionsOnly:NO];
    _sendTextAtStart.delegate = _sendTextAtStartDelegate;


    [self defineControl:_initialDirectoryType
                    key:KEY_CUSTOM_DIRECTORY
            displayName:@"Profile initial working directory"
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [weakSelf directoryTypeDidChange]; }
                 update:^BOOL { [weakSelf updateDirectoryType]; return YES; }];

    // Remove paths that need the session fully initialized.
    NSSet<NSString *> *exclusions = [NSSet setWithArray:@[ iTermVariableKeySessionTTY,
                                                           iTermVariableKeySessionUsername,
                                                           iTermVariableKeySessionHostname,
                                                           iTermVariableKeySessionName,
                                                           iTermVariableKeySessionJob,
                                                           iTermVariableKeySessionProcessTitle,
                                                           iTermVariableKeySessionPath,
                                                           iTermVariableKeySessionJobPid] ];
    _customDirectoryTextFieldDelegate =
    [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession
                                                                                                    excluding:exclusions
                                                                                                allowUserVars:NO]
                                                       passthrough:_customDirectory.delegate
                                                     functionsOnly:NO];
    _customDirectory.delegate = _customDirectoryTextFieldDelegate;
    [self defineUnsearchableControl:_customDirectory
                                key:KEY_WORKING_DIRECTORY
                               type:kPreferenceInfoTypeStringTextField];

    [self addViewToSearchIndex:_editBadgeButton
                   displayName:@"Edit badge appearance"
                       phrases:@[ @"Badge font",
                                  @"Badge minum and maximum width",
                                  @"Badge right and top margins" ]
                           key:nil];
    [self defineControl:_badgeText
                    key:KEY_BADGE_FORMAT
            displayName:@"Profile badge"
                   type:kPreferenceInfoTypeStringTextField];
    _badgeTextFieldDelegate =
        [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                           passthrough:_badgeText.delegate
                                                         functionsOnly:NO];
    _badgeText.delegate = _badgeTextFieldDelegate;

    [self defineUnsearchableControl:_badgeTextForEditCurrentSession
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
            displayName:@"Profile title options"
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf toggleSelectedTitleComponent]; }
                 update:^BOOL {
                     [weakSelf updateTitleSettingsMenu];
                     [weakSelf updateSelectedTitleComponents];
                     [weakSelf updateEnabledState];
                     return YES;
                 }];
    [self defineControl:_titleSettingsForEditCurrentSession
                    key:KEY_TITLE_COMPONENTS
            relatedView:nil
            displayName:nil
                   type:kPreferenceInfoTypePopup
         settingChanged:^(id sender) { [weakSelf toggleSelectedTitleComponent]; }
                 update:^BOOL {
                     [weakSelf updateTitleSettingsMenu];
                     [weakSelf updateSelectedTitleComponents];
                     [weakSelf updateEnabledState];
                     return YES;
                 }
             searchable:NO];

    [self defineControl:_subtitleText
                    key:KEY_SUBTITLE
            relatedView:_subtitleLabel
                   type:kPreferenceInfoTypeStringTextField];
    _subtitleTextDelegate =
        [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                           passthrough:_subtitleText.delegate
                                                         functionsOnly:NO];
    _subtitleText.delegate = _subtitleTextDelegate;

    [self updateSubtitlesAllowed];

    [self addViewToSearchIndex:_urlSchemes
                   displayName:@"URL schemes handled by profile"
                       phrases:@[ @"ssh", @"http", @"https" ]
                           key:nil];

    [self defineControl:_preventAutomaticProfileSwitching
                    key:KEY_PREVENT_APS
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self updateSelectedTitleComponents];

    NSString *originalGUID = [self.delegate profilePreferencesCurrentProfile][KEY_ORIGINAL_GUID];
    if (originalGUID) {
        [_profiles selectRowByGuid:originalGUID];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateProfileName)
                                                 name:iTermProfilePreferencesUpdateSessionName
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didRegisterSessionTitleFunc:)
                                                 name:iTermAPIDidRegisterSessionTitleFunctionNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateSubtitlesAllowed)
                                                 name:kRefreshTerminalNotification
                                               object:nil];
    [self updateEditAdvancedConfigButton];
}

- (void)updateSubtitlesAllowed {
    const BOOL subtitlesAllowed = ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_MINIMAL || [iTermAdvancedSettingsModel defaultTabBarHeight] >= 28);
    _subtitleText.hidden = !subtitlesAllowed;
    [_subtitleLabel setLabelEnabled:subtitlesAllowed];
    _tallTabBarRequestView.hidden = subtitlesAllowed;
}

- (BOOL)onUpdateTitle {
    NSString *tmuxPaneTitle = [self stringForKey:KEY_TMUX_PANE_TITLE];
    if (!tmuxPaneTitle) {
        return NO;
    }
    if ([_profileNameFieldForEditCurrentSession textFieldIsFirstResponder] && _profileNameFieldForEditCurrentSession.window.isKeyWindow) {
        // Don't allow it to change to a server-set value during editing.
        return YES;
    }
    _profileNameFieldForEditCurrentSession.stringValue = tmuxPaneTitle;
    return YES;
}

- (void)sessionNameDidEndEditing {
    if ([self stringForKey:KEY_TMUX_PANE_TITLE]) {
        [self setString:_profileNameFieldForEditCurrentSession.stringValue forKey:KEY_TMUX_PANE_TITLE];
    } else {
        [self setString:_profileNameFieldForEditCurrentSession.stringValue forKey:KEY_NAME];
    }
    [_rateLimit force];
    [_profileDelegate profilesGeneralPreferencesNameDidEndEditing];
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
        if (result == NSModalResponseOK) {
            NSURL *url = [[panel URLs] objectAtIndex:0];
            if (![self loadIconWithFilename:url.path]) {
                DLog(@"Beep: Failed to load icon at %@", url);
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

    PreferenceInfo *info = [self infoForControl:_allowTitleSetting];
    [self setControl:_locked inPreference:info];
    __weak __typeof(self) weakSelf = self;
    info.observer = ^{
        [weakSelf updateLockImage];
    };
    info.customSettingChangedHandler = ^(id sender) {
        [weakSelf toggleLock];
    };
    [self updateLockImage];
}

- (void)toggleLock {
    [self setBool:![self boolForKey:KEY_ALLOW_TITLE_SETTING] forKey:KEY_ALLOW_TITLE_SETTING];
}

- (void)updateLockImage {
    static NSImage *unlockedImage;
    static NSImage *lockedImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unlockedImage = [NSImage imageNamed:NSImageNameLockUnlockedTemplate];
        lockedImage = [NSImage imageNamed:NSImageNameLockLockedTemplate];
    });
    const BOOL unlocked = [self boolForKey:KEY_ALLOW_TITLE_SETTING];
    _locked.image = unlocked ? unlockedImage : lockedImage;
}

- (void)updateTmuxTabTitle {
    iTermVariableScope *scope = (iTermVariableScope *)self.scope.tab;
    NSString *tmuxTabTitle = [scope valueForVariableName:iTermVariableKeyTabTmuxWindowName];
    if (tmuxTabTitle) {
        _tabTitle.stringValue = tmuxTabTitle;
    }
}

- (id<iTermSessionScope>)scope {
    return [self.profileDelegate profilesGeneralPreferencesScope];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self populateBookmarkUrlSchemesFromProfile:[self.delegate profilePreferencesCurrentProfile]];
    NSString *originalGUID = [self.delegate profilePreferencesCurrentProfile][KEY_ORIGINAL_GUID];
    if (originalGUID) {
        [_profiles selectRowByGuid:originalGUID];
    }
    _sessionHotkeyInputView.shortcut = [iTermShortcut shortcutWithDictionary:(NSDictionary *)[self objectForKey:KEY_SESSION_HOTKEY]];
    id<iTermSessionScope> scope = self.scope;
    if (scope) {
        _tabTitle.stringValue =  scope.tab.tabTitleOverrideFormat ?: @"";
        _windowTitle.stringValue = scope.tab.window.windowTitleOverrideFormat ?: @"";
        [self updateTmuxTabTitle];
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

- (void)updateEnabledState {
    [super updateEnabledState];
    if ([[self stringForKey:KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomValue] ||
        [[self stringForKey:KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomShellValue]) {
        _customCommand.hidden = NO;
        _customCommand.enabled = YES;
    } else {
        _customCommand.hidden = YES;
        _customCommand.enabled = NO;
    }
    _customDirectory.enabled = ([[self stringForKey:KEY_CUSTOM_DIRECTORY] isEqualToString:kProfilePreferenceInitialDirectoryCustomValue]);
}

#pragma mark - Tall Tab Bar

- (IBAction)enableTallTabBar:(id)sender {
    [iTermAdvancedSettingsModel setDefaultTabBarHeight:28];
    [self updateSubtitlesAllowed];
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification object:nil];
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
    if (!guid) {
        return;
    }
    Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    Profile *origProfile = [self.delegate profilePreferencesCurrentProfile];
    NSString* origGuid = origProfile[KEY_GUID];
    NSDictionary<NSString *, id> *overrides;
    if ([self boolForKey:KEY_PREVENT_APS]) {
        overrides = @{ KEY_PREVENT_APS: @YES };
    } else {
        overrides = @{};
    }
    [[ProfileModel sessionsInstance] setProfilePreservingGuidWithGuid:origGuid
                                                          fromProfile:bookmark
                                                            overrides:overrides];
    [self reloadProfile];
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
        menuItem.state = [self profileHandlesScheme:menuItem.title] ? NSControlStateValueOn : NSControlStateValueOff;
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
    [self updateEnabledState];
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
    [self updateEnabledState];
}

#pragma mark - Command Type

- (void)commandTypeDidChange {
    NSInteger tag = _commandType.selectedTag;
    NSString *value;
    switch (tag) {
        case iTermGeneralProfilePreferenceCustomCommandTagCustom:
            value = kProfilePreferenceCommandTypeCustomValue;
            _customCommand.delegate = _commandDelegate;
            break;
        case iTermGeneralProfilePreferenceCustomCommandTagLoginShell:
            value = kProfilePreferenceCommandTypeLoginShellValue;
            _customCommand.delegate = _commandDelegate.passthrough;
            break;
        case iTermGeneralProfilePreferenceCustomCommandTagCustomShell:
            value = kProfilePreferenceCommandTypeCustomShellValue;
            _customCommand.delegate = _commandDelegate.passthrough;
            break;
    }
    [self setString:value forKey:KEY_CUSTOM_COMMAND];
    [self updateEnabledState];
}

- (void)updateCommandType {
    NSString *value = [self stringForKey:KEY_CUSTOM_COMMAND];
    if ([value isEqualToString:kProfilePreferenceCommandTypeCustomValue]) {
        [_commandType selectItemWithTag:iTermGeneralProfilePreferenceCustomCommandTagCustom];
        _customCommand.placeholderString = @"Enter command to run when a new session is created";
    } else if ([value isEqualToString:kProfilePreferenceCommandTypeCustomShellValue]) {
        [_commandType selectItemWithTag:iTermGeneralProfilePreferenceCustomCommandTagCustomShell];
        _customCommand.placeholderString = @"Enter full path to shell";
        [self removeWhitespaceFromCustomCommand];
        [[NSUserDefaults standardUserDefaults] setObject:_customCommand.stringValue
                                                  forKey:KEY_COMMAND_LINE];
    } else {
        [_commandType selectItemWithTag:iTermGeneralProfilePreferenceCustomCommandTagLoginShell];
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

    // Ensure only one of job or commandline is enabled.
    if ((newValue & iTermTitleComponentsJob) &&
        (newValue & iTermTitleComponentsCommandLine)) {
        if (menuItem.tag == iTermTitleComponentsCommandLine) {
            newValue ^= iTermTitleComponentsJob;
        } else {
            newValue ^= iTermTitleComponentsCommandLine;
        }
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
        item.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        if (selected) {
            [parts addObject:item.title];
        }
    }

    titleSettings.title = customName ?: [iTermSessionTitleBuiltInFunction titleForSessionName:@"Name"
                                                                                  profileName:@"Profile"
                                                                                          job:@"Job"
                                                                                  commandLine:@"Job+Args"
                                                                                          pwd:@"PWD"
                                                                                          tty:@"TTY"
                                                                                         user:@"User"
                                                                                         host:@"Host"
                                                                                     tmuxPane:nil
                                                                                     iconName:@"“Shell”"
                                                                                   windowName:@""
                                                                               tmuxWindowName:nil
                                                                              tmuxWindowTitle:nil
                                                                                         rows:@80
                                                                                      columns:@25
                                                                                   components:value
                                                                                isWindowTitle:NO];

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
        if ([self boolForKey:KEY_ALLOW_TITLE_SETTING] &&
            [iTermAdvancedSettingsModel autoLockSessionNameOnEdit]) {
            [self toggleLock];
        }
        return;
    }
    if (control == _tabTitle) {
        [self tabTitleDidChange];
        return;
    }
    if (control == _windowTitle) {
        [self windowTitleDidChange];
    }
    if (control == _customCommand) {
        if ([[self stringForKey:KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeCustomShellValue]) {
            [self removeWhitespaceFromCustomCommand];
        }
    }
    [super controlTextDidChange:aNotification];
}

- (void)removeWhitespaceFromCustomCommand {
    while (1) {
        const NSRange range = [_customCommand.stringValue rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        if (range.location == NSNotFound) {
            return;
        }
        _customCommand.stringValue = [_customCommand.stringValue stringByReplacingCharactersInRange:range withString:@""];
    }
}

- (void)sessionNameDidChange {
    _profileNameChangePending = YES;
    [_rateLimit performRateLimitedSelector:@selector(postUpdateSessionNameNotification)
                                  onTarget:self
                                withObject:nil];
}

- (void)tabTitleDidChange {
    NSString *value = _tabTitle.stringValue ?: @"";
    // Do this rather than updating the variable directly because tmux needs special handling.
    iTermCallMethodByIdentifier(self.scope.tab.tabID,
                                @"iterm2.set_title",
                                @{ @"title": value },
                                nil);
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
