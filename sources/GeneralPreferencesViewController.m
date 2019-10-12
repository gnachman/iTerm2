//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"

#import "iTermAPIAuthorizationController.h"
#import "iTermAPIHelper.h"
#import "iTermAPIPermissionsWindowController.h"
#import "iTermAdvancedGPUSettingsViewController.h"
#import "iTermApplicationDelegate.h"
#import "iTermNotificationCenter.h"
#import "iTermRemotePreferences.h"
#import "iTermShellHistoryController.h"
#import "iTermWarning.h"
#import "PasteboardHistory.h"
#import "RegexKitLite.h"
#import "WindowArrangements.h"
#import "NSImage+iTerm.h"

enum {
    kUseSystemWindowRestorationSettingTag = 0,
    kOpenDefaultWindowArrangementTag = 1,
    kDontOpenAnyWindowsTag= 2
};

@implementation GeneralPreferencesViewController {
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;
    IBOutlet NSButton *_advancedGPUPrefsButton;

    // Open saved window arrangement at startup
    IBOutlet NSPopUpButton *_openWindowsAtStartup;
    IBOutlet NSTextField *_openWindowsAtStartupLabel;

    IBOutlet NSMenuItem *_openDefaultWindowArrangementItem;

    // Quit when all windows are closed
    IBOutlet NSButton *_quitWhenAllWindowsClosed;

    // Confirm closing multiple sessions
    IBOutlet id _confirmClosingMultipleSessions;

    // Warn when quitting
    IBOutlet id _promptOnQuit;
    IBOutlet NSButton *_evenIfThereAreNoWindows;

    // Instant replay memory usage.
    IBOutlet NSTextField *_irMemory;
    IBOutlet NSTextField *_irMemoryLabel;

    // Save copy paste history
    IBOutlet NSButton *_savePasteHistory;

    // Use GPU?
    IBOutlet NSButton *_gpuRendering;
    IBOutlet NSButton *_advancedGPU;
    iTermAdvancedGPUSettingsWindowController *_advancedGPUWindowController;

    IBOutlet NSButton *_enableAPI;
    IBOutlet NSButton *_resetAPIPermissions;

    // Enable bonjour
    IBOutlet NSButton *_enableBonjour;

    // Check for updates automatically
    IBOutlet NSButton *_checkUpdate;

    // Prompt for test-release updates
    IBOutlet NSButton *_checkTestRelease;

    // Load prefs from custom folder
    IBOutlet NSButton *_loadPrefsFromCustomFolder;  // Should load?
    IBOutlet NSTextField *_prefsCustomFolder;  // Path or URL text field
    IBOutlet NSImageView *_prefsDirWarning;  // Image shown when path is not writable
    IBOutlet NSButton *_browseCustomFolder;  // Push button to open file browser
    IBOutlet NSButton *_pushToCustomFolder;  // Push button to copy local to remote
    IBOutlet NSButton *_autoSaveOnQuit;  // Save settings to folder on quit

    // Copy to clipboard on selection
    IBOutlet NSButton *_selectionCopiesText;

    // Copy includes trailing newline
    IBOutlet NSButton *_copyLastNewline;

    // Triple click selects full, wrapped lines.
    IBOutlet NSButton *_tripleClickSelectsFullLines;

    // Double click perform smart selection
    IBOutlet NSButton *_doubleClickPerformsSmartSelection;

    // Allow clipboard access by terminal applications
    IBOutlet NSButton *_allowClipboardAccessFromTerminal;

    // Characters considered part of word
    IBOutlet NSTextField *_wordChars;
    IBOutlet NSTextField *_wordCharsLabel;

    // Smart window placement
    IBOutlet NSButton *_smartPlacement;

    // Adjust window size when changing font size
    IBOutlet NSButton *_adjustWindowForFontSizeChange;

    // Zoom vertically only
    IBOutlet NSButton *_maxVertically;

    // Lion-style fullscreen
    IBOutlet NSButton *_lionStyleFullscreen;

    // Open tmux windows in [windows, tabs]
    IBOutlet NSPopUpButton *_openTmuxWindows;
    IBOutlet NSTextField *_openTmuxWindowsLabel;

    // Hide the tmux client session
    IBOutlet NSButton *_autoHideTmuxClientSession;
    
    IBOutlet NSButton *_useTmuxProfile;
    IBOutlet NSButton *_useTmuxStatusBar;

    IBOutlet NSTabView *_tabView;

    iTermAPIPermissionsWindowController *_apiPermissionsWindowController;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedArrangementChanged:)
                                                     name:kSavedArrangementDidChangeNotification
                                                   object:nil];

    }
    return self;
}

- (void)awakeFromNib {
    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    [self defineControl:_openBookmark
                    key:kPreferenceKeyOpenBookmark
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_openWindowsAtStartup
                    key:kPreferenceKeyOpenArrangementAtStartup
            relatedView:_openWindowsAtStartupLabel
                   type:kPreferenceInfoTypeCheckbox
         settingChanged:^(id sender) {
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf) {
                 return;
             }
             switch ([strongSelf->_openWindowsAtStartup selectedTag]) {
                 case kUseSystemWindowRestorationSettingTag:
                     [strongSelf setBool:NO forKey:kPreferenceKeyOpenArrangementAtStartup];
                     [strongSelf setBool:NO forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                     break;

                 case kOpenDefaultWindowArrangementTag:
                     [strongSelf setBool:YES forKey:kPreferenceKeyOpenArrangementAtStartup];
                     [strongSelf setBool:NO forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                     break;

                 case kDontOpenAnyWindowsTag:
                     [strongSelf setBool:NO forKey:kPreferenceKeyOpenArrangementAtStartup];
                     [strongSelf setBool:YES forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                     break;
             }
         } update:^BOOL{
             __strong __typeof(weakSelf) strongSelf = weakSelf;
             if (!strongSelf) {
                 return NO;
             }
             if ([strongSelf boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
                 [strongSelf->_openWindowsAtStartup selectItemWithTag:kDontOpenAnyWindowsTag];
             } else if ([WindowArrangements count] &&
                        [self boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
                 [strongSelf->_openWindowsAtStartup selectItemWithTag:kOpenDefaultWindowArrangementTag];
             } else {
                 [strongSelf->_openWindowsAtStartup selectItemWithTag:kUseSystemWindowRestorationSettingTag];
             }
             return YES;
         }];
    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];
    [self defineControl:_quitWhenAllWindowsClosed
                    key:kPreferenceKeyQuitWhenAllWindowsClosed
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_confirmClosingMultipleSessions
                    key:kPreferenceKeyConfirmClosingMultipleTabs
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_promptOnQuit
                           key:kPreferenceKeyPromptOnQuit
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [weakSelf updateEnabledState];
    };

    [self defineControl:_evenIfThereAreNoWindows
                    key:kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_irMemory
                           key:kPreferenceKeyInstantReplayMemoryMegabytes
                   displayName:@"Instant Replay memory usage limit"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 1000);

    info = [self defineControl:_savePasteHistory
                           key:kPreferenceKeySavePasteAndCommandHistory
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[iTermShellHistoryController sharedInstance] backingStoreTypeDidChange];
    };

    if (@available(macOS 10.12, *)) {
        info = [self defineControl:_gpuRendering
                               key:kPreferenceKeyUseMetal
                       relatedView:nil
                              type:kPreferenceInfoTypeCheckbox];
        info.observer = ^{
            [weakSelf updateAdvancedGPUEnabled];
        };
    } else {
        _gpuRendering.enabled = NO;
        _gpuRendering.state = NSOffState;
        [self updateAdvancedGPUEnabled];
    }

    info = [self defineControl:_enableAPI
                           key:kPreferenceKeyEnableAPIServer
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        [weakSelf enableAPISettingDidChange];
    };
    [iTermPreferenceDidChangeNotification subscribe:self
                                              block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
                                                  if ([notification.key isEqualToString:kPreferenceKeyEnableAPIServer]) {
                                                      __typeof(self) strongSelf = weakSelf;
                                                      if (strongSelf) {
                                                          strongSelf->_enableAPI.state = NSOnState;
                                                          [strongSelf updateAPIEnabled];
                                                      }
                                                  }
                                              }];
    [self updateAPIEnabled];

    _advancedGPUWindowController = [[iTermAdvancedGPUSettingsWindowController alloc] initWithWindowNibName:@"iTermAdvancedGPUSettingsWindowController"];
    [_advancedGPUWindowController window];
    _advancedGPUWindowController.viewController.disableWhenDisconnected.target = self;
    _advancedGPUWindowController.viewController.disableWhenDisconnected.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.disableWhenDisconnected
                                       key:kPreferenceKeyDisableMetalWhenUnplugged
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    _advancedGPUWindowController.viewController.preferIntegratedGPU.target = self;
    _advancedGPUWindowController.viewController.preferIntegratedGPU.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.preferIntegratedGPU
                                       key:kPreferenceKeyPreferIntegratedGPU
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };
    info.onChange = ^{
        [iTermWarning showWarningWithTitle:@"You must restart iTerm2 for this change to take effect."
                                   actions:@[ @"OK" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
    };


    _advancedGPUWindowController.viewController.maximizeThroughput.target = self;
    _advancedGPUWindowController.viewController.maximizeThroughput.action = @selector(settingChanged:);

    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.maximizeThroughput
                                       key:kPreferenceKeyMetalMaximizeThroughput
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    [self addViewToSearchIndex:_advancedGPUPrefsButton
                   displayName:@"Advanced GPU settings"
                       phrases:@[ _advancedGPUWindowController.viewController.disableWhenDisconnected.title,
                                  _advancedGPUWindowController.viewController.preferIntegratedGPU.title,
                                  _advancedGPUWindowController.viewController.maximizeThroughput.title ]
                           key:nil];

    [self defineControl:_enableBonjour
                    key:kPreferenceKeyAddBonjourHostsToProfiles
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_checkUpdate
                    key:kPreferenceKeyCheckForUpdatesAutomatically
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_checkTestRelease
                    key:kPreferenceKeyCheckForTestReleases
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_loadPrefsFromCustomFolder
                           key:kPreferenceKeyLoadPrefsFromCustomFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self loadPrefsFromCustomFolderDidChange]; };
    info.observer = ^() { [self updateRemotePrefsViews]; };

    info = [self defineControl:_autoSaveOnQuit
                           key:@"NoSyncNeverRemindPrefsChangesLostForFile_selection"
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    // Called when user interacts with control
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"NoSyncNeverRemindPrefsChangesLostForFile"];
        NSNumber *value;
        if ([strongSelf->_autoSaveOnQuit state] == NSOnState) {
            value = @0;
        } else {
            value = @1;
        }
        [[NSUserDefaults standardUserDefaults] setObject:value
                                                  forKey:@"NoSyncNeverRemindPrefsChangesLostForFile_selection"];
    };

    // Called on programmatic change (e.g., selecting a different profile. Returns YES to avoid
    // normal code path.
    info.onUpdate = ^BOOL () {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSCellStateValue state;
        if ([userDefaults boolForKey:@"NoSyncNeverRemindPrefsChangesLostForFile"] &&
            [userDefaults integerForKey:@"NoSyncNeverRemindPrefsChangesLostForFile_selection"] == 0) {
            state = NSOnState;
        } else {
            state = NSOffState;
        }
        strongSelf->_autoSaveOnQuit.state = state;
        return YES;
    };
    info.onUpdate();

    // ---------------------------------------------------------------------------------------------
    info = [self defineUnsearchableControl:_prefsCustomFolder
                                       key:kPreferenceKeyCustomFolder
                                      type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    };
    info.onChange = ^() {
        [iTermRemotePreferences sharedInstance].customFolderChanged = YES;
        [self updateRemotePrefsViews];
    };
    [self updateRemotePrefsViews];

    // ---------------------------------------------------------------------------------------------
    [self defineControl:_selectionCopiesText
                    key:kPreferenceKeySelectionCopiesText
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_copyLastNewline
                    key:kPreferenceKeyCopyLastNewline
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowClipboardAccessFromTerminal
                    key:kPreferenceKeyAllowClipboardAccessFromTerminal
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_wordChars
                    key:kPreferenceKeyCharactersConsideredPartOfAWordForSelection
            relatedView:_wordCharsLabel
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_tripleClickSelectsFullLines
                    key:kPreferenceKeyTripleClickSelectsFullWrappedLines
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_doubleClickPerformsSmartSelection
                    key:kPreferenceKeyDoubleClickPerformsSmartSelection
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_smartPlacement
                    key:kPreferenceKeySmartWindowPlacement
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_adjustWindowForFontSizeChange
                    key:kPreferenceKeyAdjustWindowForFontSizeChange
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_maxVertically
                    key:kPreferenceKeyMaximizeVerticallyOnly
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_lionStyleFullscreen
                    key:kPreferenceKeyLionStyleFullscreen
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_openTmuxWindows
                           key:kPreferenceKeyOpenTmuxWindowsIn
                   relatedView:_openTmuxWindowsLabel
                          type:kPreferenceInfoTypePopup];
    // This is how it was done before the great refactoring, but I don't see why it's needed.
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    [self defineControl:_autoHideTmuxClientSession
                    key:kPreferenceKeyAutoHideTmuxClientSession
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_useTmuxProfile
                    key:kPreferenceKeyUseTmuxProfile
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_useTmuxStatusBar
                    key:kPreferenceKeyUseTmuxStatusBar
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateEnabledState];
}

- (void)updateEnabledState {
    [super updateEnabledState];
    _evenIfThereAreNoWindows.enabled = [self boolForKey:kPreferenceKeyPromptOnQuit];
}

- (void)updateAdvancedGPUEnabled {
    if (@available(macOS 10.12, *)) {
        _advancedGPU.enabled = [self boolForKey:kPreferenceKeyUseMetal];
    } else {
        _advancedGPU.enabled = NO;
    }
}

- (BOOL)enableAPISettingDidChange {
    const BOOL enabled = _enableAPI.state == NSOnState;
    if (enabled) {
        // Prompt the user. If they agree, or have permanently agreed, set the user default to YES.
        if ([iTermAPIHelper confirmShouldStartServerAndUpdateUserDefaultsForced:YES]) {
            [iTermAPIHelper sharedInstance];
        } else {
            return NO;
        }
    } else {
        [iTermAPIHelper setEnabled:NO];
    }
    [self updateAPIEnabled];
    if (enabled && ![iTermAPIHelper isEnabled]) {
        _enableAPI.state = NSOffState;
        return NO;
    }
    return YES;
}

- (void)updateAPIEnabled {
    _resetAPIPermissions.enabled = [iTermAPIHelper isEnabled];
}

#pragma mark - Actions

- (IBAction)editAPIPermissions:(id)sender {
    _apiPermissionsWindowController = [[iTermAPIPermissionsWindowController alloc] initWithWindowNibName:@"iTermAPIPermissionsWindowController"];
    [self.view.window beginSheet:_apiPermissionsWindowController.window
               completionHandler:^(NSModalResponse returnCode) {}];
}

- (IBAction)browseCustomFolder:(id)sender {
    [self choosePrefsCustomFolder];
}

- (IBAction)pushToCustomFolder:(id)sender {
    [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
}

- (IBAction)advancedGPU:(NSView *)sender {
    [self.view.window beginSheet:_advancedGPUWindowController.window completionHandler:^(NSModalResponse returnCode) {
    }];
}

#pragma mark - Notifications

- (void)savedArrangementChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:_openWindowsAtStartup];
    [self updateValueForInfo:info];
    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];
}

#pragma mark - Remote Prefs

- (void)updateRemotePrefsViews {
    BOOL shouldLoadRemotePrefs =
        [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [_browseCustomFolder setEnabled:shouldLoadRemotePrefs];
    [_prefsCustomFolder setEnabled:shouldLoadRemotePrefs];

    if (shouldLoadRemotePrefs) {
        _prefsDirWarning.alphaValue = 1;
    } else {
        if (_prefsCustomFolder.stringValue.length > 0) {
            _prefsDirWarning.alphaValue = 0.5;
        } else {
            _prefsDirWarning.alphaValue = 0;
        }
    }

    BOOL remoteLocationIsValid = [[iTermRemotePreferences sharedInstance] remoteLocationIsValid];
    _prefsDirWarning.image = remoteLocationIsValid ? [NSImage it_imageNamed:@"CheckMark" forClass:self.class] : [NSImage it_imageNamed:@"WarningSign" forClass:self.class];
    BOOL isValidFile = (shouldLoadRemotePrefs &&
                        remoteLocationIsValid &&
                        ![[iTermRemotePreferences sharedInstance] remoteLocationIsURL]);
    [_autoSaveOnQuit setEnabled:isValidFile];
    [_pushToCustomFolder setEnabled:isValidFile];
}

- (void)loadPrefsFromCustomFolderDidChange {
    BOOL shouldLoadRemotePrefs = [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [self updateRemotePrefsViews];
    if (shouldLoadRemotePrefs) {
        // Just turned it on.
        if ([[_prefsCustomFolder stringValue] length] == 0 && ![self pasteboardHasGitlabURL]) {
            // Field was initially empty so browse for a dir.
            if ([self choosePrefsCustomFolder]) {
                // User didn't hit cancel; if he chose a writable directory, ask if he wants to write to it.
                if ([[iTermRemotePreferences sharedInstance] remoteLocationIsValid]) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Copy local preferences to custom folder now?";
                    [alert addButtonWithTitle:@"Copy"];
                    [alert addButtonWithTitle:@"Don’t Copy"];
                    if ([alert runModal] == NSAlertFirstButtonReturn) {
                        [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
                    }
                }
            }
        }
    }
    [self updateRemotePrefsViews];
}

- (BOOL)pasteboardHasGitlabURL {
    NSString *pasteboardString = [NSString stringFromPasteboard];
    return [pasteboardString isMatchedByRegex:@"^https://gitlab.com/gnachman/iterm2/uploads/[a-f0-9]*/com.googlecode.iterm2.plist$"];
}

- (BOOL)choosePrefsCustomFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK && panel.directoryURL.path) {
        [_prefsCustomFolder setStringValue:panel.directoryURL.path];
        [self settingChanged:_prefsCustomFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 598;
}

@end
