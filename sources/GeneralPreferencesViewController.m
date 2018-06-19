//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"

#import "iTermAdvancedGPUSettingsViewController.h"
#import "iTermApplicationDelegate.h"
#import "iTermRemotePreferences.h"
#import "iTermShellHistoryController.h"
#import "PasteboardHistory.h"
#import "WindowArrangements.h"

@interface iTermCustomFolderTextFieldCell : NSTextFieldCell
@end

@implementation iTermCustomFolderTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSRect rect = [super drawingRectForBounds:theRect];
    rect.size.width -= 23;  // Width of warning icon
    return rect;
}

@end

enum {
    kUseSystemWindowRestorationSettingTag = 0,
    kOpenDefaultWindowArrangementTag = 1,
    kDontOpenAnyWindowsTag= 2
};

@implementation GeneralPreferencesViewController {
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;

    // Open saved window arrangement at startup
    IBOutlet NSPopUpButton *_openWindowsAtStartup;
    IBOutlet NSMenuItem *_openDefaultWindowArrangementItem;

    // Quit when all windows are closed
    IBOutlet NSButton *_quitWhenAllWindowsClosed;

    // Confirm closing multiple sessions
    IBOutlet id _confirmClosingMultipleSessions;

    // Warn when quitting
    IBOutlet id _promptOnQuit;

    // Instant replay memory usage.
    IBOutlet NSTextField *_irMemory;

    // Save copy paste history
    IBOutlet NSButton *_savePasteHistory;

    // Use GPU?
    IBOutlet NSButton *_gpuRendering;
    IBOutlet NSButton *_advancedGPU;
    IBOutlet iTermAdvancedGPUSettingsViewController *_advancedGPUViewController;

    // Enable bonjour
    IBOutlet NSButton *_enableBonjour;

    // Check for updates automatically
    IBOutlet NSButton *_checkUpdate;

    // Prompt for test-release updates
    IBOutlet NSButton *_checkTestRelease;

    // Load prefs from custom folder
    IBOutlet NSButton *_loadPrefsFromCustomFolder;  // Should load?
    IBOutlet iTermCustomFolderTextFieldCell *_customFolderTextFieldCell;
    IBOutlet NSTextField *_prefsCustomFolder;  // Path or URL text field
    IBOutlet NSImageView *_prefsDirWarning;  // Image shown when path is not writable
    IBOutlet NSButton *_browseCustomFolder;  // Push button to open file browser
    IBOutlet NSButton *_pushToCustomFolder;  // Push button to copy local to remote
    IBOutlet NSButton *_autoSaveOnQuit;  // Save settings to folder on quit

    // Copy to clipboard on selection
    IBOutlet NSButton *_selectionCopiesText;

    // Copy includes trailing newline
    IBOutlet NSButton *_copyLastNewline;

    // Allow clipboard access by terminal applications
    IBOutlet NSButton *_allowClipboardAccessFromTerminal;

    // Characters considered part of word
    IBOutlet NSTextField *_wordChars;

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

    // Open tmux dashboard if there are more than N windows
    IBOutlet NSTextField *_tmuxDashboardLimit;

    // Hide the tmux client session
    IBOutlet NSButton *_autoHideTmuxClientSession;
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
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_openWindowsAtStartup
                    key:kPreferenceKeyOpenArrangementAtStartup
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
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_confirmClosingMultipleSessions
                    key:kPreferenceKeyConfirmClosingMultipleTabs
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_promptOnQuit
                    key:kPreferenceKeyPromptOnQuit
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_irMemory
                           key:kPreferenceKeyInstantReplayMemoryMegabytes
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 1000);

    info = [self defineControl:_savePasteHistory
                           key:kPreferenceKeySavePasteAndCommandHistory
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[iTermShellHistoryController sharedInstance] backingStoreTypeDidChange];
    };

    if (@available(macOS 10.12, *)) {
        info = [self defineControl:_gpuRendering
                               key:kPreferenceKeyUseMetal
                              type:kPreferenceInfoTypeCheckbox];
        info.observer = ^{
            [weakSelf updateAdvancedGPUEnabled];
        };
    } else {
        _gpuRendering.enabled = NO;
        _gpuRendering.state = NSOffState;
        [self updateAdvancedGPUEnabled];
    }

    [_advancedGPUViewController view];
    _advancedGPUViewController.disableWhenDisconnected.target = self;
    _advancedGPUViewController.disableWhenDisconnected.action = @selector(settingChanged:);
    info = [self defineControl:_advancedGPUViewController.disableWhenDisconnected
                           key:kPreferenceKeyDisableMetalWhenUnplugged
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    _advancedGPUViewController.preferIntegratedGPU.target = self;
    _advancedGPUViewController.preferIntegratedGPU.action = @selector(settingChanged:);
    info = [self defineControl:_advancedGPUViewController.preferIntegratedGPU
                           key:kPreferenceKeyPreferIntegratedGPU
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };


    _advancedGPUViewController.maximizeThroughput.target = self;
    _advancedGPUViewController.maximizeThroughput.action = @selector(settingChanged:);
#warning TODO: This should also defer currentDrawable, but that feature is only on the master branch.
    info = [self defineControl:_advancedGPUViewController.maximizeThroughput
                           key:kPreferenceKeyMetalMaximizeThroughput
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    [self defineControl:_enableBonjour
                    key:kPreferenceKeyAddBonjourHostsToProfiles
                            type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_checkUpdate
                    key:kPreferenceKeyCheckForUpdatesAutomatically
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_checkTestRelease
                    key:kPreferenceKeyCheckForTestReleases
                   type:kPreferenceInfoTypeCheckbox];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_loadPrefsFromCustomFolder
                           key:kPreferenceKeyLoadPrefsFromCustomFolder
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self loadPrefsFromCustomFolderDidChange]; };
    info.observer = ^() { [self updateRemotePrefsViews]; };

    info = [self defineControl:_autoSaveOnQuit
                           key:@"NoSyncNeverRemindPrefsChangesLostForFile_selection"
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
    info = [self defineControl:_prefsCustomFolder
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
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_copyLastNewline
                    key:kPreferenceKeyCopyLastNewline
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowClipboardAccessFromTerminal
                    key:kPreferenceKeyAllowClipboardAccessFromTerminal
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_wordChars
                    key:kPreferenceKeyCharactersConsideredPartOfAWordForSelection
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_smartPlacement
                    key:kPreferenceKeySmartWindowPlacement
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_adjustWindowForFontSizeChange
                    key:kPreferenceKeyAdjustWindowForFontSizeChange
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_maxVertically
                    key:kPreferenceKeyMaximizeVerticallyOnly
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_lionStyleFullscreen
                    key:kPreferenceKeyLionStyleFullscren
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_openTmuxWindows
                           key:kPreferenceKeyOpenTmuxWindowsIn
                          type:kPreferenceInfoTypePopup];
    // This is how it was done before the great refactoring, but I don't see why it's needed.
    info.onChange = ^() { [weakSelf postRefreshNotification]; };

    info = [self defineControl:_tmuxDashboardLimit
                           key:kPreferenceKeyTmuxDashboardLimit
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 1000);

    [self defineControl:_autoHideTmuxClientSession
                    key:kPreferenceKeyAutoHideTmuxClientSession
                   type:kPreferenceInfoTypeCheckbox];
}

- (void)updateAdvancedGPUEnabled {
    if (@available(macOS 10.12, *)) {
        _advancedGPU.enabled = [self boolForKey:kPreferenceKeyUseMetal];
    } else {
        _advancedGPU.enabled = NO;
    }
}

#pragma mark - Actions

- (IBAction)browseCustomFolder:(id)sender {
    [self choosePrefsCustomFolder];
}

- (IBAction)pushToCustomFolder:(id)sender {
    [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
}

- (IBAction)advancedGPU:(NSView *)sender {
    // Create popover
    NSPopover *popover = [[NSPopover alloc] init];
    [popover setContentSize:_advancedGPUViewController.view.frame.size];
    [popover setBehavior:NSPopoverBehaviorTransient];
    [popover setAnimates:YES];
    [popover setContentViewController:_advancedGPUViewController];

    // Show popover
    [popover showRelativeToRect:sender.bounds
                              ofView:sender
                       preferredEdge:NSMaxYEdge];
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
    _prefsDirWarning.image = remoteLocationIsValid ? [NSImage imageNamed:@"CheckMark"] : [NSImage imageNamed:@"WarningSign"];
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
        if ([[_prefsCustomFolder stringValue] length] == 0) {
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

@end
