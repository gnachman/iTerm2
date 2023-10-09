//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedGPUSettingsViewController.h"
#import "iTermApplicationDelegate.h"
#import "iTermBuriedSessions.h"
#import "iTermHotKeyController.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermRemotePreferences.h"
#import "iTermScriptsMenuController.h"
#import "iTermShellHistoryController.h"
#import "iTermUserDefaultsObserver.h"
#import "iTermWarning.h"
#import "NSBundle+iTerm.h"
#import "NSTextField+iTerm.h"
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
    IBOutlet NSButton *_alwaysOpenWindowAtStartup;
    IBOutlet NSTextField *_alwaysOpenLegend;
    IBOutlet NSButton *_restoreWindowsToSameSpaces;

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
    IBOutlet NSPopUpButton *_apiPermission;

    // Enable bonjour
    IBOutlet NSButton *_enableBonjour;

    IBOutlet NSButton *_notifyOnlyCriticalShellIntegrationUpdates;

    // Check for updates automatically
    IBOutlet NSButton *_checkUpdate;

    // Prompt for test-release updates
    IBOutlet NSButton *_checkTestRelease;

    // Warning that nightly builds can't update to beta/release
    IBOutlet NSTextField *_nightlyBuildNotice;

    // Load prefs from custom folder
    IBOutlet NSButton *_loadPrefsFromCustomFolder;  // Should load?
    IBOutlet NSTextField *_prefsCustomFolder;  // Path or URL text field
    IBOutlet NSImageView *_prefsDirWarning;  // Image shown when path is not writable
    IBOutlet NSButton *_browseCustomFolder;  // Push button to open file browser
    IBOutlet NSButton *_pushToCustomFolder;  // Push button to copy local to remote
    IBOutlet NSPopUpButton *_saveChanges;  // Save settings to folder when
    IBOutlet NSTextField *_saveChangesLabel;

    IBOutlet NSButton *_useCustomScriptsFolder;
    IBOutlet NSTextField *_customScriptsFolder;
    IBOutlet NSImageView *_customScriptsFolderWarning;
    IBOutlet NSButton *_browseCustomScriptsFolder;

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

    IBOutlet NSButton *_separateWindowTitlePerTab;

    // Lion-style fullscreen
    IBOutlet NSButton *_lionStyleFullscreen;

    // Open tmux windows in [windows, tabs]
    IBOutlet NSPopUpButton *_openTmuxWindows;
    IBOutlet NSTextField *_openTmuxWindowsLabel;

    // Hide the tmux client session
    IBOutlet NSButton *_autoHideTmuxClientSession;
    
    IBOutlet NSButton *_useTmuxProfile;
    IBOutlet NSButton *_useTmuxStatusBar;

    IBOutlet NSTextField *_tmuxPauseModeAgeLimit;
    IBOutlet NSButton *_unpauseTmuxAutomatically;
    IBOutlet NSButton *_tmuxWarnBeforePausing;

    IBOutlet NSButton *_syncTmuxClipboard;

    IBOutlet NSTabView *_tabView;

    IBOutlet NSButton *_enterCopyModeAutomatically;
    IBOutlet NSButton *_warningButton;
    iTermUserDefaultsObserver *_observer;

    IBOutlet NSPopUpButton *_allowsSendingClipboardContents;
    IBOutlet NSTextField *_allowsSendingClipboardContentsLabel;

    IBOutlet NSButton *_disableConfirmationOnShutdown;

    IBOutlet NSTextField *_openAIAPIKey;
    IBOutlet NSTextField *_openAIAPIKeyLabel;

    IBOutlet NSTextField *_aiPrompt;
    IBOutlet NSTextField *_aiPromptLabel;
    IBOutlet NSImageView *_aiPromptWarning;  // Image shown when prompt lacks \(ai.prompt)

    IBOutlet NSButton *_compressHistory;

    BOOL _customScriptsFolderDidChange;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedArrangementChanged:)
                                                     name:kSavedArrangementDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didRevertPythonAuthenticationMethod:)
                                                     name:iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateAlwaysOpenLegend)
                                                     name:iTermSessionBuriedStateChangeTabNotification
                                                   object:nil];
        _observer = [[iTermUserDefaultsObserver alloc] init];
        __weak __typeof(self) weakSelf = self;
        [_observer observeKey:@"NSQuitAlwaysKeepsWindows" block:^{
            [weakSelf updateEnabledState];
        }];
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
             [strongSelf updateEnabledState];
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
             [strongSelf updateEnabledState];
             return YES;
         }];
    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];

    [self defineControl:_restoreWindowsToSameSpaces
                    key:kPreferenceKeyRestoreWindowsToSameSpaces
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_alwaysOpenWindowAtStartup
                    key:kPreferenceKeyAlwaysOpenWindowAtStartup
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateAlwaysOpenLegend];

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

    [self defineControl:_disableConfirmationOnShutdown
                    key:kPreferenceKeyNeverBlockSystemShutdown
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

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

    info = [self defineControl:_gpuRendering
                           key:kPreferenceKeyUseMetal
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateAdvancedGPUEnabled];
    };

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
                                                          strongSelf->_enableAPI.state = NSControlStateValueOn;
                                                      }
                                                  }
                                              }];

    info = [self defineControl:_apiPermission
                           key:kPreferenceKeyAPIAuthentication
                   displayName:@"Authentication method for Python API"
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        return @([iTermAPIHelper requireApplescriptAuth] ? 0 : 1);
    };
    info.syntheticSetter = ^(NSNumber *newValue) {
        const BOOL useApplescript = (newValue.intValue == 0);
        [iTermAPIHelper setRequireApplescriptAuth:useApplescript
                                           window:self.view.window];
        [weakSelf updateAPIEnabledState];
    };
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyEnableAPIServer];
    };
    
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

    _advancedGPUWindowController.viewController.disableInLowPowerMode.target = self;
    _advancedGPUWindowController.viewController.disableInLowPowerMode.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.disableInLowPowerMode
                                       key:kPreferenceKeyDisableInLowPowerMode
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
                                  _advancedGPUWindowController.viewController.disableInLowPowerMode.title,
                                  _advancedGPUWindowController.viewController.preferIntegratedGPU.title,
                                  _advancedGPUWindowController.viewController.maximizeThroughput.title ]
                           key:nil];

    [self defineControl:_enableBonjour
                    key:kPreferenceKeyAddBonjourHostsToProfiles
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_notifyOnlyCriticalShellIntegrationUpdates
                    key:kPreferenceKeyNotifyOnlyForCriticalShellIntegrationUpdates
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_checkUpdate
                    key:kPreferenceKeyCheckForUpdatesAutomatically
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    if ([NSBundle it_isNightlyBuild]) {
        _checkTestRelease.enabled = NO;
    } else {
        _nightlyBuildNotice.hidden = YES;
    }
    [self defineControl:_checkTestRelease
                    key:kPreferenceKeyCheckForTestReleases
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_useCustomScriptsFolder
                           key:kPreferenceKeyUseCustomScriptsFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [self useCustomScriptsFolderDidChange];
        [weakSelf customScriptsFolderDidChange];
        [weakSelf postCustomScriptsFolderDidChangeNotificationIfNeeded];
    };
    info.observer = ^() { [self updateCustomScriptsFolderViews]; };

    info = [self defineControl:_customScriptsFolder
                           key:kPreferenceKeyCustomScriptsFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    };
    info.onChange = ^() {
        [self updateCustomScriptsFolderViews];
        [weakSelf customScriptsFolderDidChange];
    };
    info.controlTextDidEndEditing = ^(NSNotification *notif) {
        // Post here instead of onChange since a patial path, like "/", would kick off a very slow
        // recursive search for scripts.
        [weakSelf postCustomScriptsFolderDidChangeNotificationIfNeeded];
    };
    [self updateCustomScriptsFolderViews];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_loadPrefsFromCustomFolder
                           key:kPreferenceKeyLoadPrefsFromCustomFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self loadPrefsFromCustomFolderDidChange]; };
    info.observer = ^() { [self updateRemotePrefsViews]; };

    info = [self defineControl:_saveChanges
                           key:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection
                   relatedView:_saveChangesLabel
                          type:kPreferenceInfoTypePopup];
    // Called when user interacts with control
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection];
        [[NSUserDefaults standardUserDefaults] setObject:@([strongSelf->_saveChanges selectedTag])
                                                  forKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection];
    };

    // Called on programmatic change (e.g., selecting a different profile. Returns YES to avoid
    // normal code path.
    info.onUpdate = ^BOOL () {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSUInteger tag = iTermPreferenceSavePrefsModeNever;
        if ([userDefaults boolForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection]) {
            tag = [userDefaults integerForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection];
        }
        [strongSelf->_saveChanges selectItemWithTag:tag];
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
    info = [self defineControl:_doubleClickPerformsSmartSelection
                           key:kPreferenceKeyDoubleClickPerformsSmartSelection
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_wordChars.enabled = ![strongSelf boolForKey:kPreferenceKeyDoubleClickPerformsSmartSelection];
        strongSelf->_wordCharsLabel.labelEnabled = ![strongSelf boolForKey:kPreferenceKeyDoubleClickPerformsSmartSelection];
    };
    [self defineControl:_enterCopyModeAutomatically
                    key:kPreferenceKeyEnterCopyModeAutomatically
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

    [self defineControl:_separateWindowTitlePerTab
                    key:kPreferenceKeySeparateWindowTitlePerTab
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

    [self defineControl:_tmuxPauseModeAgeLimit
                    key:kPreferenceKeyTmuxPauseModeAgeLimit
            displayName:@"Pause a tmux pane if it would take more than this many seconds to catch up."
                   type:kPreferenceInfoTypeUnsignedIntegerTextField];
    [self defineControl:_unpauseTmuxAutomatically
                    key:kPreferenceKeyTmuxUnpauseAutomatically
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_tmuxWarnBeforePausing
                    key:kPreferenceKeyTmuxWarnBeforePausing
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_syncTmuxClipboard
                    key:kPreferenceKeyTmuxSyncClipboard
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_openAIAPIKey
                    key:kPreferenceKeyOpenAIAPIKey
            relatedView:_openAIAPIKeyLabel
                   type:kPreferenceInfoTypeStringTextField];
    info = [self defineControl:_aiPrompt
                           key:kPreferenceKeyAIPrompt
                   relatedView:_aiPromptLabel
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^{
        [weakSelf updateAIPromptWarning];
    };
    [self defineControl:_compressHistory
                    key:kPreferenceKeyCompressHistory
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_allowsSendingClipboardContents
                           key:kPreferenceKeyPhonyAllowSendingClipboardContents
                   relatedView:_allowsSendingClipboardContentsLabel
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        return @([iTermPasteboardReporter configuration]);
    };
    info.syntheticSetter = ^(NSNumber *newValue) {
        [iTermPasteboardReporter setConfiguration:newValue.intValue];
    };
    PreferenceInfo *allowSendingClipboardInfo = info;

    [self updateEnabledState];
    [self commitControls];
    [self updateValueForInfo:allowSendingClipboardInfo];
}

- (void)customScriptsFolderDidChange {
    _customScriptsFolderDidChange = YES;
}

- (void)postCustomScriptsFolderDidChangeNotificationIfNeeded {
    if (_customScriptsFolderDidChange) {
        _customScriptsFolderDidChange = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptsFolderDidChange object:nil];
    }
}

- (void)windowWillClose {
    [self postCustomScriptsFolderDidChangeNotificationIfNeeded];
}

- (void)willDeselectTab {
    [self postCustomScriptsFolderDidChangeNotificationIfNeeded];
}

- (void)updateAIPromptWarning {
    if ([[self stringForKey:kPreferenceKeyAIPrompt] containsString:@"\\(ai.prompt)"]) {
        _aiPromptWarning.alphaValue = 0.0;
    } else {
        _aiPromptWarning.alphaValue = 1.0;
    }
}

- (NSString *)alwaysOpenLegend {
    if ([iTermScriptsMenuController autoLaunchFolderExists]) {
        return @"The presence of auto-launch scripts disables opening a window at startup.";
    }
    if ([[[iTermHotKeyController sharedInstance] profileHotKeys] count] > 0) {
        return @"The existence of hotkey windows disables opening a window at startup.";
    }
    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count] > 0) {
        return @"The existence of buried sessions disables opening a window at startup.";
    }
    return nil;
}

- (void)updateAlwaysOpenLegend {
    NSString *legend = [self alwaysOpenLegend];
    if (!legend) {
        _alwaysOpenLegend.hidden = YES;
        return;
    }
    _alwaysOpenLegend.stringValue = legend;
    _alwaysOpenLegend.hidden = NO;
}

- (void)updateAPIEnabledState {
    _enableAPI.state = [self boolForKey:kPreferenceKeyEnableAPIServer];
    [_apiPermission selectItemWithTag:[iTermAPIHelper requireApplescriptAuth] ? 0 : 1];
    [self updateEnabledState];
}

- (BOOL)shouldEnableAlwaysOpenWindowAtStartup {
    if ([self boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
        return NO;
    }
    if ([self boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
        return NO;
    }
    return YES;
}

- (void)updateEnabledState {
    [super updateEnabledState];
    [_apiPermission selectItemWithTag:[iTermAPIHelper requireApplescriptAuth] ? 0 : 1];
    _evenIfThereAreNoWindows.enabled = [self boolForKey:kPreferenceKeyPromptOnQuit];
    const BOOL useSystemWindowRestoration = (![self boolForKey:kPreferenceKeyOpenArrangementAtStartup] &&
                                             ![self boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]);
    const BOOL systemRestorationEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"];
    _warningButton.hidden = (!useSystemWindowRestoration || systemRestorationEnabled);
    _alwaysOpenWindowAtStartup.enabled = [self shouldEnableAlwaysOpenWindowAtStartup];
    _restoreWindowsToSameSpaces.enabled = systemRestorationEnabled && useSystemWindowRestoration;
}

- (void)updateAdvancedGPUEnabled {
    _advancedGPU.enabled = [self boolForKey:kPreferenceKeyUseMetal];
}

- (BOOL)enableAPISettingDidChange {
    const BOOL result = [self reallyEnableAPISettingDidChange];
    [self updateEnabledState];
    return result;
}

- (BOOL)reallyEnableAPISettingDidChange {
    const BOOL enabled = _enableAPI.state == NSControlStateValueOn;
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
    if (enabled && ![iTermAPIHelper isEnabled]) {
        _enableAPI.state = NSControlStateValueOff;
        return NO;
    }
    return YES;
}

#pragma mark - Actions

- (IBAction)exportAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport exportAll] title:@"Problem Exporting"];
}

- (IBAction)importAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport importAll] title:@"Problem Importing"];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!message) {
        return;
    }
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                               heading:title
                                window:self.view.window];
}

- (IBAction)warning:(id)sender {
    NSString *message;
    NSString *action;
    NSString *path;
    if (@available(macOS 13, *)) {
        message = @"System window restoration has been disabled, which prevents iTerm2 from respecting this setting. Disable ”System Settings > Desktop & Dock > Close windows when quitting an application“ to enable window restoration.";
        action = @"Open System Settings";
        path = @"/System/Library/PreferencePanes/Dock.prefPane";
    } else {
        message = @"System window restoration has been disabled, which prevents iTerm2 from respecting this setting. Disable System Preferences > General > Close windows when quitting an app to enable window restoration.";
        action = @"Open System Preferences";
        path = @"/System/Library/PreferencePanes/Appearance.prefPane";
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ action, @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncWindowRestorationDisabled"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Window Restoration Disabled"
                                window:self.view.window];
    if (selection == kiTermWarningSelection0) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
    }
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

- (IBAction)pythonAPIAuthHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/python-api-auth.html"]];
}

- (IBAction)resetAIPrompt:(id)sender {
    [self setString:iTermDefaultAIPrompt forKey:kPreferenceKeyAIPrompt];
    _aiPrompt.stringValue = iTermDefaultAIPrompt;
}

- (IBAction)aiPromptHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/ai-prompt-help"]];
}

#pragma mark - Notifications

- (void)savedArrangementChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:_openWindowsAtStartup];
    [self updateValueForInfo:info];
    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];
}

// The API helper just noticed that the file's contents changed.
- (void)didRevertPythonAuthenticationMethod:(NSNotification *)notification {
    [self updateAPIEnabledState];
}

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    [self updateAlwaysOpenLegend];
    [super preferenceDidChangeFromOtherPanel:notification];
}


#pragma mark - Remote Prefs

- (void)updateCustomScriptsFolderViews {
    BOOL haveCustomFolder = [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    _browseCustomScriptsFolder.enabled = haveCustomFolder;
    _customScriptsFolder.enabled = haveCustomFolder;
    if (haveCustomFolder) {
        _customScriptsFolderWarning.alphaValue = 1;
    } else {
        if (_customScriptsFolder.stringValue.length > 0) {
            _customScriptsFolderWarning.alphaValue = 0.5;
        } else {
            _customScriptsFolderWarning.alphaValue = 0;
        }
    }
    const BOOL locationIsValid = [[NSFileManager defaultManager] customScriptsFolderIsValid:_customScriptsFolder.stringValue];
    _customScriptsFolderWarning.image = locationIsValid ? [NSImage it_imageNamed:@"CheckMark" forClass:self.class] : [NSImage it_imageNamed:@"WarningSign" forClass:self.class];
}

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
    [_saveChanges setEnabled:isValidFile];
    [_saveChangesLabel setLabelEnabled:isValidFile];
    [_pushToCustomFolder setEnabled:isValidFile];
}

- (void)useCustomScriptsFolderDidChange {
    const BOOL newValue = [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    [self updateCustomScriptsFolderViews];
    if (newValue) {
        // Just turned it on
        if ([[_customScriptsFolder stringValue] length] == 0) {
            // Filed was initially empty so browse for a dir.
            if ([self chooseCustomScriptsFolder]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptsFolderDidChange object:nil];
            }
        }
    }
    [self updateCustomScriptsFolderViews];
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

- (BOOL)chooseCustomScriptsFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK && panel.directoryURL.path) {
        [_customScriptsFolder setStringValue:panel.directoryURL.path];
        [self settingChanged:_customScriptsFolder];
        return YES;
    }  else {
        return NO;
    }
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
