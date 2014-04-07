//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"

#import "CommandHistory.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "PasteboardHistory.h"
#import "WindowArrangements.h"

typedef enum {
    kPreferenceInfoTypeCheckbox,
    kPreferenceInfoTypeIntegerTextField,
    kPreferenceInfoTypeStringTextField,
    kPreferenceInfoTypePopup
} PreferenceInfoType;

@interface PreferenceInfo : NSObject

@property(nonatomic, retain) NSString *key;
@property(nonatomic, assign) PreferenceInfoType type;
@property(nonatomic, retain) NSControl *control;

// A function that indicates if the control should be enabled. If nil, then the control is always
// enabled.
@property(nonatomic, copy) BOOL (^shouldBeEnabled)();

// Called when value changes with PreferenceInfo as object.
@property(nonatomic, copy) void (^onChange)();

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control;

@end

@implementation PreferenceInfo

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control {
    PreferenceInfo *info = [[self alloc] init];
    info.key = key;
    info.type = type;
    info.control = control;
    return info;
}

- (void)dealloc {
    [_key release];
    [_control release];
    [_shouldBeEnabled release];
    [super dealloc];
}

@end

@interface GeneralPreferencesViewController ()
@end

@implementation GeneralPreferencesViewController {
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;
    
    // Open saved window arrangement at startup
    IBOutlet NSButton *_openArrangementAtStartup;

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

    NSMapTable *_keyMap;  // Maps views to PreferenceInfo.
}

- (void)dealloc {
    [_keyMap release];
    [super dealloc];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
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
    _keyMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                        valueOptions:NSPointerFunctionsStrongMemory
                                            capacity:16];
    
    PreferenceInfo *info;
    
    [self defineControl:_openBookmark
                    key:kPreferenceKeyOpenBookmark
                   type:kPreferenceInfoTypeCheckbox];
    
    info = [self defineControl:_openArrangementAtStartup
                           key:kPreferenceKeyOpenArrangementAtStartup
                          type:kPreferenceInfoTypeCheckbox];
    info.shouldBeEnabled = ^BOOL() { return [WindowArrangements count] > 0; };

    [self defineControl:_quitWhenAllWindowsClosed
                    key:kPreferenceKeyQuitWhenAllWindowsClosed
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_confirmClosingMultipleSessions
                    key:kPreferenceKeyConfirmClosingMultipleTabs
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_promptOnQuit
                    key:kPreferenceKeyPromptOnQuit
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_irMemory
                    key:kPreferenceKeyInstantReplayMemoryMegabytes
                   type:kPreferenceInfoTypeIntegerTextField];

    info = [self defineControl:_savePasteHistory
                           key:kPreferenceKeySavePasteAndCommandHistory
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        if (![iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
            [[PasteboardHistory sharedInstance] eraseHistory];
            [[CommandHistory sharedInstance] eraseHistory];
        }
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
    info.onChange = ^() {
        [self loadPrefsFromCustomFolderDidChange];
    };
    [self updateEnabledStateForCustomFolderButtons];

    
    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_prefsCustomFolder
                           key:kPreferenceKeyCustomFolder
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    };
    info.onChange = ^() {
        [iTermRemotePreferences sharedInstance].customFolderChanged = YES;
        [self updatePrefsDirWarning];
    };
    [self updatePrefsDirWarning];
    
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
    info.onChange = ^() { [self postRefreshNotification]; };
}

- (void)postRefreshNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)updateValueForInfo:(PreferenceInfo *)info {
    switch (info.type) {
        case kPreferenceInfoTypeCheckbox: {
            assert([info.control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)info.control;
            button.state = [iTermPreferences boolForKey:info.key] ? NSOnState : NSOffState;
            break;
        }
            
        case kPreferenceInfoTypeIntegerTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.intValue = [iTermPreferences intForKey:info.key];
            break;
        }
            
        case kPreferenceInfoTypeStringTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.stringValue = [iTermPreferences stringForKey:info.key];
            break;
        }
            
        case kPreferenceInfoTypePopup: {
            assert([info.control isKindOfClass:[NSPopUpButton class]]);
            NSPopUpButton *popup = (NSPopUpButton *)info.control;
            [popup selectItemWithTag:[iTermPreferences intForKey:info.key]];
            break;
        }
            
        default:
            assert(false);
    }
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type {
    assert(![_keyMap objectForKey:key]);
    assert(key);
    assert(control);
    assert([iTermPreferences keyHasDefaultValue:key]);

    PreferenceInfo *info = [PreferenceInfo infoForPreferenceWithKey:key
                                                               type:type
                                                            control:control];
    [_keyMap setObject:info forKey:control];
    [self updateValueForInfo:info];
    
    return info;
}

- (PreferenceInfo *)infoForControl:(NSControl *)control {
    PreferenceInfo *info = [_keyMap objectForKey:control];
    assert(info);
    return info;
}

- (IBAction)settingChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);

    switch (info.type) {
        case kPreferenceInfoTypeCheckbox:
            [iTermPreferences setBool:([sender state] == NSOnState) forKey:info.key];
            break;
            
        case kPreferenceInfoTypeIntegerTextField:
            [iTermPreferences setInt:[sender intValue] forKey:info.key];
            break;

        case kPreferenceInfoTypeStringTextField:
            [iTermPreferences setString:[sender stringValue] forKey:info.key];
            break;

        case kPreferenceInfoTypePopup:
            [iTermPreferences setInt:[sender selectedTag] forKey:info.key];
            break;

        default:
            assert(false);
    }
    if (info.onChange) {
        info.onChange();
    }
}

- (IBAction)browseCustomFolder:(id)sender {
    [self choosePrefsCustomFolder];
}

- (IBAction)pushToCustomFolder:(id)sender {
    [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
}

- (void)updateEnabledStateForInfo:(PreferenceInfo *)info {
    if (info.shouldBeEnabled) {
        [info.control setEnabled:info.shouldBeEnabled()];
    }
}

- (void)updateEnabledState {
    for (NSControl *control in _keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        [self updateEnabledStateForInfo:info];
    }
}

#pragma mark - Notifications

- (void)savedArrangementChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:_openArrangementAtStartup];
    [self updateValueForInfo:info];
    [self updateEnabledStateForInfo:info];
}

// This is a notification signature but it gets called because we're the delegate of text fields.
- (void)controlTextDidChange:(NSNotification *)aNotification {
    id control = [aNotification object];
    if (control == _prefsCustomFolder ||
        control == _wordChars) {
        [self settingChanged:control];
    }
}


#pragma mark - Remote Prefs

- (void)updatePrefsDirWarning
{
    BOOL shouldLoadRemotePrefs =
        [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    if (!shouldLoadRemotePrefs) {
        [_prefsDirWarning setHidden:YES];
        return;
    }
    
    BOOL remoteLocationIsValid = [[iTermRemotePreferences sharedInstance] remoteLocationIsValid];
    [_prefsDirWarning setHidden:remoteLocationIsValid];
}


- (void)updateEnabledStateForCustomFolderButtons {
    BOOL shouldLoadRemotePrefs = [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [_browseCustomFolder setEnabled:shouldLoadRemotePrefs];
    [_pushToCustomFolder setEnabled:shouldLoadRemotePrefs];
    [_prefsCustomFolder setEnabled:shouldLoadRemotePrefs];
    [self updatePrefsDirWarning];
}

- (void)loadPrefsFromCustomFolderDidChange {
    BOOL shouldLoadRemotePrefs = [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [self updateEnabledStateForCustomFolderButtons];
    if (shouldLoadRemotePrefs) {
        // Just turned it on.
        if ([[_prefsCustomFolder stringValue] length] == 0) {
            // Field was initially empty so browse for a dir.
            if ([self choosePrefsCustomFolder]) {
                // User didn't hit cancel; if he chose a writable directory, ask if he wants to write to it.
                if ([[iTermRemotePreferences sharedInstance] remoteLocationIsValid]) {
                    if ([[NSAlert alertWithMessageText:@"Copy local preferences to custom folder now?"
                                         defaultButton:@"Copy"
                                       alternateButton:@"Don't Copy"
                                           otherButton:nil
                             informativeTextWithFormat:@""] runModal] == NSOKButton) {
                        [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
                    }
                }
            }
        }
    }
    [self updatePrefsDirWarning];
}

- (BOOL)choosePrefsCustomFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    
    if ([panel runModal] == NSOKButton) {
        [_prefsCustomFolder setStringValue:[panel legacyDirectory]];
        [self settingChanged:_prefsCustomFolder];
        return YES;
    }  else {
        return NO;
    }
}

@end
