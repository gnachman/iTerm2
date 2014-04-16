/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/*
 * Preferences in iTerm2 are complicated, to say the least. Here is how the classes are organized.
 *
 * - PreferencePanel: There are two instances of this class: -sharedInstance and -sessionsInstance.
 *       The sharedInstance is the app settings panel, while sessionsInstance is for editing a
 *       single session (View>Edit Current Session).
 *     - GeneralPreferencesViewController:    View controller for Prefs>General
 *     - AppearancePreferencesViewController: View controller for Prefs>Appearance
 *     - KeysPreferencesViewController:       View controller for Prefs>Keys
 *     - PointerPreferencesViewController:    View controller for Prefs>Pointer
 *     - ProfilePreferencesViewController:    View controller for Prefs>Profiles
 *     - WindowArrangements:                  Owns Prefs>Arrangements
 *     - iTermAdvancedSettingsController:     Owns Prefs>Advanced
 *
 *  View controllers of tabs in PreferencePanel derive from iTermPreferencesBaseViewController.
 *  iTermPreferencesBaseViewController provides a map from NSControl* to PreferenceInfo.
 *  PreferenceInfo stores a pref's type, user defaults key, can constrain its value, and
 *  stores pointers to blocks that are run when a value is changed or a field needs to be updated
 *  for customizing how controls are bound to storage. Each view controller defines these bindings
 *  in its -awakeFromNib method.
 *
 *  User defaults are accessed through iTermPreferences, which assigns string constants to user
 *  defaults keys, defines default values for each key, and provides accessors. It also allows the
 *  exposed values to be computed from underlying values. (Currently, iTermPreferences is not used
 *  by advanced settings, but that should change).
 *
 *  Because per-profile preferences are similar, a parallel class structure exists for them.
 *  The following classes are view controllers for tabs in Prefs>Profiles:
 *
 *  - ProfilesGeneralPreferencesViewController
 *  - ProfilesColorPreferencesViewController
 *  - ProfilesTextPreferencesViewController
 *  - More coming
 *
 *  These derive from iTermProfilePreferencesBaseViewController, which is just like
 *  iTermPreferencesBaseViewController, but its methods for accessing preference values take an
 *  additional profile: parameter. The analog of iTermPreferences is iTermProfilePreferences.
 *  */
#import "PreferencePanel.h"

#import "GeneralPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermFontPanel.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyMappingViewController.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "iTermSettingsModel.h"
#import "iTermURLSchemeController.h"
#import "iTermWarning.h"
#import "KeysPreferencesViewController.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSPopUpButton+iTerm.h"
#import "NSStringITerm.h"
#import "PasteboardHistory.h"
#import "PointerPrefsController.h"
#import "ProfileModel.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "SessionView.h"
#import "SmartSelectionController.h"
#import "TriggerController.h"
#import "TrouterPrefsController.h"
#import "WindowArrangements.h"
#include <stdlib.h>

static NSString *const kDeleteKeyString = @"0x7f-0x0";

NSString *const kRefreshTerminalNotification = @"kRefreshTerminalNotification";
NSString *const kUpdateLabelsNotification = @"kUpdateLabelsNotification";
NSString *const kKeyBindingsChangedNotification = @"kKeyBindingsChangedNotification";
NSString *const kReloadAllProfiles = @"kReloadAllProfiles";
NSString *const kPreferencePanelDidUpdateProfileFields = @"kPreferencePanelDidUpdateProfileFields";

@implementation PreferencePanel {
    ProfileModel* dataSource;
    BOOL oneBookmarkMode;
    IBOutlet TriggerController *triggerWindowController_;
    IBOutlet SmartSelectionController *smartSelectionWindowController_;
    IBOutlet TrouterPrefsController *trouterPrefController_;
    IBOutlet GeneralPreferencesViewController *_generalPreferencesViewController;
    IBOutlet KeysPreferencesViewController *_keysViewController;
    IBOutlet ProfilePreferencesViewController *_profilesViewController;

    // instant replay
    BOOL defaultInstantReplay;

    NSUserDefaults *prefs;

    IBOutlet NSToolbar* toolbar;
    IBOutlet NSTabView* tabView;
    IBOutlet NSToolbarItem* globalToolbarItem;
    IBOutlet NSTabViewItem* globalTabViewItem;
    IBOutlet NSToolbarItem* appearanceToolbarItem;
    IBOutlet NSTabViewItem* appearanceTabViewItem;
    IBOutlet NSToolbarItem* keyboardToolbarItem;
    IBOutlet NSToolbarItem* arrangementsToolbarItem;
    IBOutlet NSTabViewItem* keyboardTabViewItem;
    IBOutlet NSTabViewItem* arrangementsTabViewItem;
    IBOutlet NSToolbarItem* bookmarksToolbarItem;
    IBOutlet NSTabViewItem* bookmarksTabViewItem;
    IBOutlet NSToolbarItem* mouseToolbarItem;
    IBOutlet NSTabViewItem* mouseTabViewItem;
    IBOutlet NSToolbarItem* advancedToolbarItem;
    IBOutlet NSTabViewItem* advancedTabViewItem;
    NSString *globalToolbarId;
    NSString *appearanceToolbarId;
    NSString *keyboardToolbarId;
    NSString *arrangementsToolbarId;
    NSString *bookmarksToolbarId;
    NSString *mouseToolbarId;
    NSString *advancedToolbarId;

    // Bookmarks -----------------------------

    // Display tab
    IBOutlet NSView *displayFontAccessoryView;
    IBOutlet NSSlider *displayFontSpacingWidth;
    IBOutlet NSSlider *displayFontSpacingHeight;
    IBOutlet NSTextField *columnsField;
    IBOutlet NSTextField *columnsLabel;
    IBOutlet NSTextField *rowsLabel;
    IBOutlet NSTextField *rowsField;
    IBOutlet NSTextField* windowTypeLabel;
    IBOutlet NSPopUpButton* screenButton;
    IBOutlet NSTextField* spaceLabel;
    IBOutlet NSPopUpButton* spaceButton;

    IBOutlet NSPopUpButton* windowTypeButton;
    IBOutlet NSTextField *normalFontField;
    IBOutlet NSTextField *nonAsciiFontField;
    IBOutlet NSTextField *newWindowttributesHeader;
    IBOutlet NSTextField *screenLabel;

    IBOutlet NSButton* blinkAllowed;
    IBOutlet NSButton* useBrightBold;
    IBOutlet NSButton* useItalicFont;
    IBOutlet NSSlider *transparency;
    IBOutlet NSSlider *blend;
    IBOutlet NSButton* blur;
    IBOutlet NSSlider *blurRadius;
    IBOutlet NSButton* asciiAntiAliased;
    IBOutlet NSButton* useNonAsciiFont;
    IBOutlet NSView* nonAsciiFontView;  // Hide this view to hide all non-ascii font settings
    IBOutlet NSButton* nonasciiAntiAliased;
    IBOutlet NSButton* backgroundImage;
    NSString* backgroundImageFilename;
    IBOutlet NSButton* backgroundImageTiled;
    IBOutlet NSImageView* backgroundImagePreview;
    IBOutlet NSTextField* displayFontsLabel;
    IBOutlet NSButton* displayRegularFontButton;
    IBOutlet NSButton* displayNAFontButton;

    NSFont* normalFont;
    NSFont *nonAsciiFont;
    BOOL changingNonAsciiFont; // true if font dialog is currently modifying the non-ascii font

    // Terminal tab
    IBOutlet NSButton* disableWindowResizing;
    IBOutlet NSButton* preventTab;
    IBOutlet NSButton* hideAfterOpening;
    IBOutlet NSButton* syncTitle;
    IBOutlet NSButton* closeSessionsOnEnd;
    IBOutlet NSButton* nonAsciiDoubleWidth;
    IBOutlet NSButton* silenceBell;
    IBOutlet NSButton* visualBell;
    IBOutlet NSButton* flashingBell;
    IBOutlet NSButton* xtermMouseReporting;
    IBOutlet NSButton* disableSmcupRmcup;
    IBOutlet NSButton* allowTitleReporting;
    IBOutlet NSButton* allowTitleSetting;
    IBOutlet NSButton* disablePrinting;
    IBOutlet NSButton* scrollbackWithStatusBar;
    IBOutlet NSButton* scrollbackInAlternateScreen;
    IBOutlet NSButton* bookmarkGrowlNotifications;
    IBOutlet NSTextField* scrollbackLines;
    IBOutlet NSButton* unlimitedScrollback;
    IBOutlet NSComboBox* terminalType;
    IBOutlet NSPopUpButton* characterEncoding;
    IBOutlet NSButton* setLocaleVars;

    // Keyboard tab
    IBOutlet NSMatrix *optionKeySends;
    IBOutlet NSMatrix *rightOptionKeySends;

    // Session --------------------------------
    IBOutlet NSTableView *jobsTable_;
    IBOutlet NSButton *autoLog;
    IBOutlet NSTextField *logDir;
    IBOutlet NSButton *changeLogDir;
    IBOutlet NSImageView *logDirWarning;
    IBOutlet NSButton* sendCodeWhenIdle;
    IBOutlet NSTextField* idleCode;
    IBOutlet NSButton* removeJobButton_;
    IBOutlet NSMatrix* promptBeforeClosing_;

    // Keyboard ------------------------------
    IBOutlet NSButton* deleteSendsCtrlHButton;
    IBOutlet NSButton* applicationKeypadAllowed;

    IBOutlet WindowArrangements *arrangements_;
    BOOL _haveAwoken;  // Can kill this when profiles stuff is migrated
}

+ (PreferencePanel*)sharedInstance {
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[ProfileModel sharedInstance]
                                     userDefaults:[NSUserDefaults standardUserDefaults]
                                  oneBookmarkMode:NO];
    }

    return shared;
}

+ (PreferencePanel*)sessionsInstance {
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[ProfileModel sessionsInstance]
                                     userDefaults:nil
                                  oneBookmarkMode:YES];
    }

    return shared;
}

- (id)initWithDataSource:(ProfileModel*)model
            userDefaults:(NSUserDefaults*)userDefaults
         oneBookmarkMode:(BOOL)obMode
{
    self = [super init];
    if (self) {
        dataSource = model;
        prefs = userDefaults;
        if (userDefaults) {
            [[iTermRemotePreferences sharedInstance] copyRemotePrefsToLocalUserDefaults];
        }
        // Override smooth scrolling, which breaks various things (such as the
        // assumption, when detectUserScroll is called, that scrolls happen
        // immediately), and generally sucks with a terminal.
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"NSScrollAnimationEnabled"];

        [toolbar setSelectedItemIdentifier:globalToolbarId];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_reloadURLHandlers:)
                                                     name:@"iTermReloadAddressBook"
                                                   object:nil];

        oneBookmarkMode = obMode;
    }
    return self;
}

#pragma mark - View layout

- (void)awakeFromNib
{
    // Because the ProfilePreferencesViewController awakes before PreferencePanel, it calls
    // profilePreferencesModelDidAwakeFromNib which in turn calls this to ensure everything is
    // initialized so that the rest of [-ProfilePreferencesViewController awakeFromNib] can run
    // successfully. This is an awful hack and will go away.
    if (_haveAwoken) {
        return;
    }

    [self window];
    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    bookmarksToolbarId = [bookmarksToolbarItem itemIdentifier];
    globalToolbarId = [globalToolbarItem itemIdentifier];
    appearanceToolbarId = [appearanceToolbarItem itemIdentifier];
    keyboardToolbarId = [keyboardToolbarItem itemIdentifier];
    arrangementsToolbarId = [arrangementsToolbarItem itemIdentifier];
    mouseToolbarId = [mouseToolbarItem itemIdentifier];
    advancedToolbarId = [advancedToolbarItem itemIdentifier];

    [globalToolbarItem setEnabled:YES];
    [toolbar setSelectedItemIdentifier:globalToolbarId];

    // add list of encodings
    [characterEncoding removeAllItems];
    for (NSNumber *anEncoding in [[iTermController sharedInstance] sortedEncodingList]) {
        [characterEncoding addItemWithTitle:[NSString localizedNameOfStringEncoding:[anEncoding unsignedIntValue]]];
        [[characterEncoding lastItem] setTag:[anEncoding unsignedIntValue]];
    }
    [self setScreens];

    [blurRadius setContinuous:YES];
    [transparency setContinuous:YES];
    [blend setContinuous:YES];

    if (oneBookmarkMode) {
        [self layoutSubviewsForSingleBookmarkMode];
    }
}

- (void)layoutSubviewsForSingleBookmarkMode
{
    [self showBookmarks];
    [_profilesViewController layoutSubviewsForSingleBookmarkMode];
    [toolbar setVisible:NO];

    [columnsLabel setTextColor:[NSColor disabledControlTextColor]];
    [rowsLabel setTextColor:[NSColor disabledControlTextColor]];
    [columnsField setEnabled:NO];
    [rowsField setEnabled:NO];
    [windowTypeButton setEnabled:NO];
    [screenLabel setTextColor:[NSColor disabledControlTextColor]];
    [screenButton setEnabled:NO];
    [spaceButton setEnabled:NO];
    [spaceLabel setTextColor:[NSColor disabledControlTextColor]];
    [windowTypeLabel setTextColor:[NSColor disabledControlTextColor]];
    [newWindowttributesHeader setTextColor:[NSColor disabledControlTextColor]];

    NSRect newFrame = [[self window] frame];
    newFrame.size.width = [_profilesViewController size].width + 26;
    [[self window] setFrame:newFrame display:YES];
}

#pragma mark - API

- (void)showBookmarks
{
    [tabView selectTabViewItem:bookmarksTabViewItem];
    [toolbar setSelectedItemIdentifier:bookmarksToolbarId];
}

- (void)openToBookmark:(NSString*)guid {
    [self run];
    [self showBookmarks];
    [_profilesViewController openToProfileWithGuid:guid];
}

- (Profile*)hotkeyBookmark {
    return [_keysViewController hotkeyProfile];
}

- (void)triggerChanged:(TriggerController *)triggerController
{
    [self bookmarkSettingChanged:nil];
}

- (void)smartSelectionChanged:(SmartSelectionController *)smartSelectionController
{
    [self bookmarkSettingChanged:nil];
}


#pragma mark - Notification handlers

- (void)_reloadURLHandlers:(NSNotification *)aNotification {
    // TODO: maybe something here for the current bookmark?
    [_keysViewController populateHotKeyProfilesMenu];
}

#pragma mark - NSWindowController

// NSWindow delegate
- (void)windowWillLoad
{
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setWindowFrameAutosaveName:@"Preferences"];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [self savePreferences];

}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"nonTerminalWindowBecameKey"
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - IBActions

- (IBAction)closeCurrentSession:(id)sender
{
    if ([[self window] isKeyWindow]) {
        [self closeWindow:self];
    }
}

- (IBAction)displaySelectFont:(id)sender
{
    changingNonAsciiFont = [sender tag] == 1;
    [self _showFontPanel];
}

- (NSString*)_chooseBackgroundImage
{
    NSOpenPanel *panel;
    int sts;
    NSString *filename = nil;

    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection: NO];

    sts = [panel legacyRunModalForDirectory: NSHomeDirectory() file:@"" types: [NSImage imageFileTypes]];
    if (sts == NSOKButton) {
        if ([[panel legacyFilenames] count] > 0) {
            filename = [[panel legacyFilenames] objectAtIndex: 0];
        }

        if ([filename length] > 0) {
            NSImage *anImage = [[NSImage alloc] initWithContentsOfFile: filename];
            if (anImage != nil) {
                [backgroundImagePreview setImage:anImage];
                [anImage release];
                return filename;
            } else {
                [backgroundImage setState: NSOffState];
            }
        } else {
            [backgroundImage setState: NSOffState];
        }
    } else {
        [backgroundImage setState: NSOffState];
    }
    return nil;
}

- (IBAction)bookmarkSettingChanged:(id)sender
{
    if (sender == optionKeySends && [[optionKeySends selectedCell] tag] == OPT_META) {
        [self _maybeWarnAboutMeta];
    } else if (sender == rightOptionKeySends && [[rightOptionKeySends selectedCell] tag] == OPT_META) {
        [self _maybeWarnAboutMeta];
    }
    if (sender == spaceButton && [spaceButton selectedTag] > 0) {
        [self _maybeWarnAboutSpaces];
    }
    Profile *origBookmark = [_profilesViewController selectedProfile];
    NSString *guid = origBookmark[KEY_GUID];
    if (!guid || !origBookmark) {
        return;
    }
    NSMutableDictionary* newDict = [NSMutableDictionary dictionary];
    [_profilesViewController copyOwnedValuesToDict:newDict];
    NSString* isDefault = [origBookmark objectForKey:KEY_DEFAULT_BOOKMARK];
    if (!isDefault) {
        isDefault = @"No";
    }
    [newDict setObject:isDefault forKey:KEY_DEFAULT_BOOKMARK];
    newDict[KEY_NAME] = origBookmark[KEY_NAME];
    [newDict setObject:guid forKey:KEY_GUID];
    NSString* origGuid = [origBookmark objectForKey:KEY_ORIGINAL_GUID];
    if (origGuid) {
        [newDict setObject:origGuid forKey:KEY_ORIGINAL_GUID];
    }

    // Display tab
    int rows, cols;
    rows = [rowsField intValue];
    cols = [columnsField intValue];
    if (cols > 0) {
        [newDict setObject:[NSNumber numberWithInt:cols] forKey:KEY_COLUMNS];
    }
    if (rows > 0) {
        [newDict setObject:[NSNumber numberWithInt:rows] forKey:KEY_ROWS];
    }
    [newDict setObject:[NSNumber numberWithInt:[windowTypeButton selectedTag]] forKey:KEY_WINDOW_TYPE];
    [self setScreens];
    [newDict setObject:[NSNumber numberWithInt:[screenButton selectedTag]] forKey:KEY_SCREEN];
    if ([spaceButton selectedTag]) {
        [newDict setObject:[NSNumber numberWithInt:[spaceButton selectedTag]] forKey:KEY_SPACE];
    }
    [newDict setObject:[ITAddressBookMgr descFromFont:normalFont] forKey:KEY_NORMAL_FONT];
    [newDict setObject:[ITAddressBookMgr descFromFont:nonAsciiFont] forKey:KEY_NON_ASCII_FONT];
    [newDict setObject:[NSNumber numberWithFloat:[displayFontSpacingWidth floatValue]] forKey:KEY_HORIZONTAL_SPACING];
    [newDict setObject:[NSNumber numberWithFloat:[displayFontSpacingHeight floatValue]] forKey:KEY_VERTICAL_SPACING];
    [newDict setObject:[NSNumber numberWithBool:([blinkAllowed state]==NSOnState)] forKey:KEY_BLINK_ALLOWED];
    [newDict setObject:[NSNumber numberWithBool:([useBrightBold state]==NSOnState)] forKey:KEY_USE_BRIGHT_BOLD];
    [newDict setObject:[NSNumber numberWithBool:([useItalicFont state]==NSOnState)] forKey:KEY_USE_ITALIC_FONT];
    [newDict setObject:[NSNumber numberWithFloat:[transparency floatValue]] forKey:KEY_TRANSPARENCY];
    [newDict setObject:[NSNumber numberWithFloat:[blend floatValue]] forKey:KEY_BLEND];
    [newDict setObject:[NSNumber numberWithFloat:[blurRadius floatValue]] forKey:KEY_BLUR_RADIUS];
    [newDict setObject:[NSNumber numberWithBool:([blur state]==NSOnState)] forKey:KEY_BLUR];
    [newDict setObject:[NSNumber numberWithBool:([useNonAsciiFont state]==NSOnState)] forKey:KEY_USE_NONASCII_FONT];
    [newDict setObject:[NSNumber numberWithBool:([asciiAntiAliased state]==NSOnState)] forKey:KEY_ASCII_ANTI_ALIASED];
    [newDict setObject:[NSNumber numberWithBool:([nonasciiAntiAliased state]==NSOnState)] forKey:KEY_NONASCII_ANTI_ALIASED];
    [self _updateFontsDisplay];

    [nonAsciiFontView setHidden:(useNonAsciiFont.state == NSOffState)];

    if (sender == backgroundImage) {
        NSString* filename = nil;
        if ([sender state] == NSOnState) {
            filename = [self _chooseBackgroundImage];
        }
        if (!filename) {
            [backgroundImagePreview setImage: nil];
            filename = @"";
        }
        backgroundImageFilename = filename;
    }
    [newDict setObject:backgroundImageFilename forKey:KEY_BACKGROUND_IMAGE_LOCATION];
    [newDict setObject:[NSNumber numberWithBool:([backgroundImageTiled state]==NSOnState)] forKey:KEY_BACKGROUND_IMAGE_TILED];

    // Terminal tab
    [newDict setObject:[NSNumber numberWithBool:([disableWindowResizing state]==NSOnState)] forKey:KEY_DISABLE_WINDOW_RESIZING];
    [newDict setObject:[NSNumber numberWithBool:([preventTab state]==NSOnState)] forKey:KEY_PREVENT_TAB];
    [newDict setObject:[NSNumber numberWithBool:([hideAfterOpening state]==NSOnState)] forKey:KEY_HIDE_AFTER_OPENING];
    [newDict setObject:[NSNumber numberWithBool:([syncTitle state]==NSOnState)] forKey:KEY_SYNC_TITLE];
    [newDict setObject:[NSNumber numberWithBool:([nonAsciiDoubleWidth state]==NSOnState)] forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
    [newDict setObject:[NSNumber numberWithBool:([silenceBell state]==NSOnState)] forKey:KEY_SILENCE_BELL];
    [newDict setObject:[NSNumber numberWithBool:([visualBell state]==NSOnState)] forKey:KEY_VISUAL_BELL];
    [newDict setObject:[NSNumber numberWithBool:([flashingBell state]==NSOnState)] forKey:KEY_FLASHING_BELL];
    [newDict setObject:[NSNumber numberWithBool:([xtermMouseReporting state]==NSOnState)] forKey:KEY_XTERM_MOUSE_REPORTING];
    [newDict setObject:[NSNumber numberWithBool:([disableSmcupRmcup state]==NSOnState)] forKey:KEY_DISABLE_SMCUP_RMCUP];
    [newDict setObject:[NSNumber numberWithBool:([allowTitleReporting state]==NSOnState)] forKey:KEY_ALLOW_TITLE_REPORTING];
    [newDict setObject:[NSNumber numberWithBool:([allowTitleSetting state]==NSOnState)] forKey:KEY_ALLOW_TITLE_SETTING];
    [newDict setObject:[NSNumber numberWithBool:([disablePrinting state]==NSOnState)] forKey:KEY_DISABLE_PRINTING];
    [newDict setObject:[NSNumber numberWithBool:([scrollbackWithStatusBar state]==NSOnState)] forKey:KEY_SCROLLBACK_WITH_STATUS_BAR];
    [newDict setObject:[NSNumber numberWithBool:([scrollbackInAlternateScreen state]==NSOnState)] forKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN];
    [newDict setObject:[NSNumber numberWithBool:([bookmarkGrowlNotifications state]==NSOnState)] forKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS];
    [newDict setObject:[NSNumber numberWithBool:([setLocaleVars state]==NSOnState)] forKey:KEY_SET_LOCALE_VARS];
    [newDict setObject:[NSNumber numberWithUnsignedInt:[[characterEncoding selectedItem] tag]] forKey:KEY_CHARACTER_ENCODING];
    [newDict setObject:[NSNumber numberWithInt:[[[scrollbackLines stringValue] stringWithOnlyDigits] intValue]] forKey:KEY_SCROLLBACK_LINES];
    [newDict setObject:[NSNumber numberWithBool:([unlimitedScrollback state]==NSOnState)] forKey:KEY_UNLIMITED_SCROLLBACK];
    [scrollbackLines setEnabled:[unlimitedScrollback state]==NSOffState];
    if ([unlimitedScrollback state] == NSOnState) {
        [scrollbackLines setStringValue:@""];
    } else if (sender == unlimitedScrollback) {
        [scrollbackLines setStringValue:@"10000"];
    }

    [newDict setObject:[terminalType stringValue] forKey:KEY_TERMINAL_TYPE];

    // Keyboard tab
    [newDict setObject:[origBookmark objectForKey:KEY_KEYBOARD_MAP] forKey:KEY_KEYBOARD_MAP];
    [newDict setObject:[NSNumber numberWithInt:[[optionKeySends selectedCell] tag]] forKey:KEY_OPTION_KEY_SENDS];
    [newDict setObject:[NSNumber numberWithInt:[[rightOptionKeySends selectedCell] tag]] forKey:KEY_RIGHT_OPTION_KEY_SENDS];
    [newDict setObject:[NSNumber numberWithInt:([applicationKeypadAllowed state]==NSOnState)] forKey:KEY_APPLICATION_KEYPAD_ALLOWED];

    BOOL reloadKeyMappings = NO;
    if (sender == deleteSendsCtrlHButton) {
        // Resolve any conflict between key mappings and delete sends ^h by
        // modifying key mappings.
        [self _setDeleteKeyMapToCtrlH:[deleteSendsCtrlHButton state] == NSOnState
                           inBookmark:newDict];
        reloadKeyMappings = YES;
    } else {
        // If a keymapping for the delete key was added, make sure the
        // delete sends ^h checkbox is correct
        BOOL sendCH = [self _deleteSendsCtrlHInBookmark:newDict];
        [deleteSendsCtrlHButton setState:sendCH ? NSOnState : NSOffState];
    }

    // Session tab
    [newDict setObject:[NSNumber numberWithBool:([closeSessionsOnEnd state]==NSOnState)] forKey:KEY_CLOSE_SESSIONS_ON_END];
    [newDict setObject:[NSNumber numberWithInt:[[promptBeforeClosing_ selectedCell] tag]]
                forKey:KEY_PROMPT_CLOSE];
    [newDict setObject:[origBookmark objectForKey:KEY_JOBS] ? [origBookmark objectForKey:KEY_JOBS] : [NSArray array]
                forKey:KEY_JOBS];
    [newDict setObject:[NSNumber numberWithBool:([autoLog state]==NSOnState)] forKey:KEY_AUTOLOG];
    [newDict setObject:[logDir stringValue] forKey:KEY_LOGDIR];
    [logDir setEnabled:[autoLog state] == NSOnState];
    [changeLogDir setEnabled:[autoLog state] == NSOnState];
    [self _updateLogDirWarning];
    [newDict setObject:[NSNumber numberWithBool:([sendCodeWhenIdle state]==NSOnState)] forKey:KEY_SEND_CODE_WHEN_IDLE];
    [newDict setObject:[NSNumber numberWithInt:[idleCode intValue]] forKey:KEY_IDLE_CODE];

    // Advanced tab
    [newDict setObject:[triggerWindowController_ triggers] forKey:KEY_TRIGGERS];
    [newDict setObject:[smartSelectionWindowController_ rules] forKey:KEY_SMART_SELECTION_RULES];
    [newDict setObject:[trouterPrefController_ prefs] forKey:KEY_TROUTER];

    // Epilogue
    [_profilesViewController updateProfileInModel:newDict];

    // Save changes
    if (prefs) {
        [prefs setObject:[dataSource rawData] forKey:@"New Bookmarks"];
    }

    // Update existing sessions
    int n = [[iTermController sharedInstance] numberOfTerminals];
    for (int i = 0; i < n; ++i) {
        PseudoTerminal* pty = [[iTermController sharedInstance] terminalAtIndex:i];
        [pty reloadBookmarks];
    }
    if (reloadKeyMappings) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                            object:nil
                                                          userInfo:nil];
    }
}


- (IBAction)addJob:(id)sender
{
    Profile *profile = [_profilesViewController selectedProfile];
    NSString* guid = profile[KEY_GUID];
    if (!guid) {
        return;
    }
    NSArray *jobNames = [profile objectForKey:KEY_JOBS];
    NSMutableArray *augmented;
    if (jobNames) {
        augmented = [NSMutableArray arrayWithArray:jobNames];
        [augmented addObject:@"Job Name"];
    } else {
        augmented = [NSMutableArray arrayWithObject:@"Job Name"];
    }
    [dataSource setObject:augmented forKey:KEY_JOBS inBookmark:profile];
    [jobsTable_ reloadData];
    [jobsTable_ selectRowIndexes:[NSIndexSet indexSetWithIndex:[augmented count] - 1]
            byExtendingSelection:NO];
    [jobsTable_ editColumn:0
                       row:[self numberOfRowsInTableView:jobsTable_] - 1
                 withEvent:nil
                    select:YES];
    [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    [self bookmarkSettingChanged:nil];
}

- (IBAction)removeJob:(id)sender
{
    // Causes editing to end. If you try to remove a cell that is being edited,
    // it tries to dereference the deleted cell. There doesn't seem to be an
    // API that explicitly ends editing.
    [jobsTable_ reloadData];

    NSInteger selectedIndex = [jobsTable_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    Profile *profile = [_profilesViewController selectedProfile];
    NSString *guid = profile[KEY_GUID];
    if (!guid) {
        return;
    }
    NSArray *jobNames = profile[KEY_JOBS];
    NSMutableArray *mod = [NSMutableArray arrayWithArray:jobNames];
    [mod removeObjectAtIndex:selectedIndex];

    [dataSource setObject:mod forKey:KEY_JOBS inBookmark:profile];
    [jobsTable_ reloadData];
    [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    [self bookmarkSettingChanged:nil];
}

- (IBAction)showGlobalTabView:(id)sender
{
    [tabView selectTabViewItem:globalTabViewItem];
}

- (IBAction)showAppearanceTabView:(id)sender
{
    [tabView selectTabViewItem:appearanceTabViewItem];
}

- (IBAction)showBookmarksTabView:(id)sender
{
    [tabView selectTabViewItem:bookmarksTabViewItem];
}

- (IBAction)showKeyboardTabView:(id)sender
{
    [tabView selectTabViewItem:keyboardTabViewItem];
}

- (IBAction)showArrangementsTabView:(id)sender
{
    [tabView selectTabViewItem:arrangementsTabViewItem];
}

- (IBAction)showMouseTabView:(id)sender
{
    [tabView selectTabViewItem:mouseTabViewItem];
}

- (IBAction)showAdvancedTabView:(id)sender
{
    [tabView selectTabViewItem:advancedTabViewItem];
}

- (IBAction)closeWindow:(id)sender
{
    [[self window] close];
}

- (IBAction)selectLogDir:(id)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSOKButton) {
        [logDir setStringValue:[panel legacyDirectory]];
    }
    [self _updateLogDirWarning];
}

- (void)_updateLogDirWarning
{
    [logDirWarning setHidden:[autoLog state] == NSOffState || [self _logDirIsWritable]];
}

- (BOOL)_logDirIsWritable
{
    return [[NSFileManager defaultManager] directoryIsWritable:[logDir stringValue]];
}

- (IBAction)setAsDefault:(id)sender
{
    Profile *origProfile = [_profilesViewController selectedProfile];
    NSString* guid = origProfile[KEY_GUID];
    if (!guid) {
        NSBeep();
        return;
    }
    [dataSource setDefaultByGuid:guid];
}

#pragma mark - Color Presets

- (BOOL)importColorPresetFromFile:(NSString*)filename {
    return [_profilesViewController importColorPresetFromFile:filename];
}

#pragma mark - Preferences folder

- (BOOL)remoteLocationIsValid {
    if (![[iTermRemotePreferences sharedInstance] shouldLoadRemotePrefs]) {
        return YES;
    }
    return [[iTermRemotePreferences sharedInstance] remoteLocationIsValid];
}

#pragma mark - Sheet handling

- (void)genericCloseSheet:(NSWindow *)sheet
               returnCode:(int)returnCode
              contextInfo:(void *)contextInfo {
    [sheet close];
}

#pragma mark - Advanced tab sheets

- (void)advancedTabCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet close];
}

#pragma mark - Smart selection

- (IBAction)editSmartSelection:(id)sender
{
    [smartSelectionWindowController_ window];
    [smartSelectionWindowController_ windowWillOpen];
    [NSApp beginSheet:[smartSelectionWindowController_ window]
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeSmartSelectionSheet:(id)sender
{
    [NSApp endSheet:[smartSelectionWindowController_ window]];
}

#pragma mark - Triggers

- (IBAction)editTriggers:(id)sender
{
    [NSApp beginSheet:[triggerWindowController_ window]
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(advancedTabCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)closeTriggersSheet:(id)sender
{
    [NSApp endSheet:[triggerWindowController_ window]];
}

- (WindowArrangements *)arrangements
{
    return arrangements_;
}

// Force the key binding for delete to be either ^H or absent.
- (void)_setDeleteKeyMapToCtrlH:(BOOL)sendCtrlH inBookmark:(NSMutableDictionary*)bookmark
{
    if (sendCtrlH) {
        [iTermKeyBindingMgr setMappingAtIndex:0
                                       forKey:kDeleteKeyString
                                       action:KEY_ACTION_SEND_C_H_BACKSPACE
                                        value:@""
                                    createNew:YES
                                   inBookmark:bookmark];
    } else {
        [iTermKeyBindingMgr removeMappingWithCode:0x7f
                                        modifiers:0
                                       inBookmark:bookmark];
    }
}

// Returns true if and only if there is a key mapping in the bookmark for delete
// to send exactly ^H.
- (BOOL)_deleteSendsCtrlHInBookmark:(Profile*)bookmark
{
    NSString* text;
    return ([iTermKeyBindingMgr localActionForKeyCode:0x7f
                                            modifiers:0
                                                 text:&text
                                          keyMappings:[bookmark objectForKey:KEY_KEYBOARD_MAP]] == KEY_ACTION_SEND_C_H_BACKSPACE);
}

- (void)removeKeyMappingsReferringToBookmarkGuid:(NSString*)badRef
{
    for (NSString* guid in [[ProfileModel sharedInstance] guids]) {
        Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        bookmark = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:bookmark];
        if (bookmark) {
            [[ProfileModel sharedInstance] setBookmark:bookmark withGuid:guid];
        }
    }
    for (NSString* guid in [[ProfileModel sessionsInstance] guids]) {
        Profile* bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:guid];
        bookmark = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:bookmark];
        if (bookmark) {
            [[ProfileModel sessionsInstance] setBookmark:bookmark withGuid:guid];
        }
    }
    [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - NSToolbarDelegate and ToolbarItemValidation

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    return TRUE;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag
{
    if (!flag) {
        return nil;
    }
    if ([itemIdentifier isEqual:globalToolbarId]) {
        return globalToolbarItem;
    } else if ([itemIdentifier isEqual:appearanceToolbarId]) {
        return appearanceToolbarItem;
    } else if ([itemIdentifier isEqual:bookmarksToolbarId]) {
        return bookmarksToolbarItem;
    } else if ([itemIdentifier isEqual:keyboardToolbarId]) {
        return keyboardToolbarItem;
    } else if ([itemIdentifier isEqual:arrangementsToolbarId]) {
        return arrangementsToolbarItem;
    } else if ([itemIdentifier isEqual:mouseToolbarId]) {
        return mouseToolbarItem;
    } else if ([itemIdentifier isEqual:advancedToolbarId]) {
        return advancedToolbarItem;
    } else {
        return nil;
    }
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    return @[ globalToolbarId,
              appearanceToolbarId,
              bookmarksToolbarId,
              keyboardToolbarId,
              arrangementsToolbarId,
              mouseToolbarId,
              advancedToolbarId ];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    return [NSArray arrayWithObjects:globalToolbarId, appearanceToolbarId, bookmarksToolbarId,
            keyboardToolbarId, arrangementsToolbarId, mouseToolbarId, nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar
{
    // Optional delegate method: Returns the identifiers of the subset of
    // toolbar items that are selectable.
    return @[ globalToolbarId,
              appearanceToolbarId,
              bookmarksToolbarId,
              keyboardToolbarId,
              arrangementsToolbarId,
              mouseToolbarId,
              advancedToolbarId ];
}

#pragma mark - NSUserDefaults wrangling

- (void)savePreferences {
    if (!prefs) {
        // In one-bookmark mode there are no prefs but this function doesn't
        // affect bookmarks.
        return;
    }

    [prefs setObject:[dataSource rawData] forKey: @"New Bookmarks"];

    [prefs synchronize];
}

#pragma mark - Utilities

- (int)modifierTagToMask:(int)tag
{
    switch (tag) {
        case MOD_TAG_ANY_COMMAND:
            return NSCommandKeyMask;

        case MOD_TAG_CMD_OPT:
            return NSCommandKeyMask | NSAlternateKeyMask;

        case MOD_TAG_OPTION:
            return NSAlternateKeyMask;

        default:
            NSLog(@"Unexpected value for modifierTagToMask: %d", tag);
            return NSCommandKeyMask | NSAlternateKeyMask;
    }
}

// Pick out the digits from s and clamp it to a range.
- (int)intForString:(NSString *)s inRange:(NSRange)range
{
    NSString *i = [s stringWithOnlyDigits];

    int val = 0;
    if ([i length]) {
        val = [i intValue];
    }
    val = MAX(val, range.location);
    val = MIN(val, range.location + range.length);
    return val;
}

#pragma mark - Hotkey Window

- (NSTextField*)hotkeyField {
    return _keysViewController.hotkeyField;
}

#pragma mark - Accessors

- (NSString *)currentProfileGuid {
    return [_profilesViewController selectedProfile][KEY_GUID];
}

- (float)fsTabDelay {
    return [iTermPreferences floatForKey:kPreferenceKeyTimeToHoldCmdToShowTabsInFullScreen];
}

- (BOOL)trimTrailingWhitespace
{
    return [iTermSettingsModel trimWhitespaceOnCopy];
}

- (float)legacyMinimumContrast
{
    return [prefs objectForKey:@"MinimumContrast"] ? [[prefs objectForKey:@"MinimumContrast"] floatValue] : 0;;
}

- (BOOL)allowClipboardAccess
{
    return [iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal];
}

- (BOOL)copySelection
{
    return [iTermPreferences boolForKey:kPreferenceKeySelectionCopiesText];
}

- (BOOL)copyLastNewline {
    return [iTermPreferences boolForKey:kPreferenceKeyCopyLastNewline];
}

- (BOOL)legacyPasteFromClipboard {
    // This is used for migrating old prefs to the new configurable pointer action system.
    return [prefs boolForKey:@"PasteFromClipboard"];
}

- (BOOL)threeFingerEmulatesMiddle {
    return [iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle];
}

- (BOOL)hideTab {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabBar];
}

- (int)tabViewType {
    return [iTermPreferences intForKey:kPreferenceKeyTabPosition];
}

- (int)windowStyle {
    return [iTermPreferences intForKey:kPreferenceKeyWindowStyle];
}

- (int)openTmuxWindowsIn {
    return [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn];
}

- (BOOL)autoHideTmuxClientSession {
    return [iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession];
}

- (int)tmuxDashboardLimit {
    return [iTermPreferences intForKey:kPreferenceKeyTmuxDashboardLimit];
}

- (BOOL)promptOnQuit
{
    return [iTermPreferences boolForKey:kPreferenceKeyPromptOnQuit];
}

- (BOOL)onlyWhenMoreTabs
{
    return [iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs];
}

- (BOOL)focusFollowsMouse {
    return [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse];
}

- (BOOL)tripleClickSelectsFullLines {
    return [iTermPreferences boolForKey:kPreferenceKeyTripleClickSelectsFullWrappedLines];
}

- (BOOL)enableBonjour
{
    return [iTermPreferences boolForKey:kPreferenceKeyAddBonjourHostsToProfiles];
}

- (BOOL)enableGrowl
{
    for (Profile* bookmark in [[ProfileModel sharedInstance] bookmarks]) {
        if ([[bookmark objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]) {
            return YES;
        }
    }
    for (Profile* bookmark in [[ProfileModel sessionsInstance] bookmarks]) {
        if ([[bookmark objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)cmdSelection {
    return [iTermPreferences boolForKey:kPreferenceKeyCmdClickOpensURLs];
}

- (BOOL)optionClickMovesCursor {
    return [iTermPreferences boolForKey:kPreferenceKeyOptionClickMovesCursor];
}

- (BOOL)passOnControlLeftClick {
    return [iTermPreferences boolForKey:kPreferenceKeyControlLeftClickBypassesContextMenu];
}

- (BOOL)maxVertically {
    return [iTermPreferences boolForKey:kPreferenceKeyMaximizeVerticallyOnly];
}

- (BOOL)hideTabNumber {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabNumber];
}

- (BOOL)hideTabCloseButton {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabCloseButton];
}

- (BOOL)hideActivityIndicator {
    return [iTermPreferences boolForKey:kPreferenceKeyHideTabActivityIndicator];
}

- (BOOL)highlightTabLabels {
    return [iTermPreferences boolForKey:kPreferenceKeyHighlightTabLabels];
}

- (BOOL)hideMenuBarInFullscreen {
    return [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen];
}

- (BOOL)openBookmark
{
    return [iTermPreferences boolForKey:kPreferenceKeyOpenBookmark];
}

- (NSString *)wordChars {
    return [iTermPreferences stringForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection];
}

- (BOOL)hideScrollbar {
    return [iTermPreferences boolForKey:kPreferenceKeyHideScrollbar];
}

- (BOOL)showPaneTitles {
    return [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
}

- (BOOL)disableFullscreenTransparency {
    return [iTermPreferences boolForKey:kPreferenceKeyDisableFullscreenTransparencyByDefault];
}

- (BOOL)smartPlacement {
    return [iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement];
}

- (BOOL)adjustWindowForFontSizeChange {
    return [iTermPreferences boolForKey:kPreferenceKeyAdjustWindowForFontSizeChange];
}

- (BOOL)windowNumber {
    return [iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber];
}

- (BOOL)jobName {
    return [iTermPreferences boolForKey:kPreferenceKeyShowJobName];
}

- (BOOL)showBookmarkName {
    return [iTermPreferences boolForKey:kPreferenceKeyShowProfileName];
}

- (BOOL)instantReplay
{
    return YES;
}

- (BOOL)savePasteHistory
{
    return [iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory];
}

- (int)control {
    return [iTermPreferences intForKey:kPreferenceKeyControlRemapping];
}

- (int)leftOption {
    return [iTermPreferences intForKey:kPreferenceKeyLeftOptionRemapping];
}

- (int)rightOption {
    return [iTermPreferences intForKey:kPreferenceKeyRightOptionRemapping];
}

- (int)leftCommand {
    return [iTermPreferences intForKey:kPreferenceKeyLeftCommandRemapping];
}

- (int)rightCommand {
    return [iTermPreferences intForKey:kPreferenceKeyRightCommandRemapping];
}

- (BOOL)isAnyModifierRemapped
{
    return ([self control] != MOD_TAG_CONTROL ||
            [self leftOption] != MOD_TAG_LEFT_OPTION ||
            [self rightOption] != MOD_TAG_RIGHT_OPTION ||
            [self leftCommand] != MOD_TAG_LEFT_COMMAND ||
            [self rightCommand] != MOD_TAG_RIGHT_COMMAND);
}

- (int)switchTabModifier {
    return [iTermPreferences intForKey:kPreferenceKeySwitchTabModifier];
}

- (int)switchWindowModifier {
    return [iTermPreferences intForKey:kPreferenceKeySwitchWindowModifier];
}

- (BOOL)openArrangementAtStartup
{
    return [iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup];
}

- (int)irMemory
{
    return [iTermPreferences intForKey:kPreferenceKeyInstantReplayMemoryMegabytes];
}

- (BOOL)hotkey {
    return [iTermPreferences boolForKey:kPreferenceKeyHotkeyEnabled];
}

- (short)hotkeyChar
{
    return [iTermPreferences intForKey:kPreferenceKeyHotkeyCharacter];
}

- (int)hotkeyCode
{
    return [iTermPreferences intForKey:kPreferenceKeyHotKeyCode];
}

- (int)hotkeyModifiers
{
    return [iTermPreferences intForKey:kPreferenceKeyHotkeyModifiers];
}

- (BOOL)dimInactiveSplitPanes {
    return [iTermPreferences boolForKey:kPreferenceKeyDimInactiveSplitPanes];
}

- (BOOL)dimBackgroundWindows {
    return [iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows];
}

- (BOOL)animateDimming {
    return [iTermPreferences boolForKey:kPreferenceKeyAnimateDimming];
}

- (BOOL)dimOnlyText {
    return [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
}

- (float)dimmingAmount {
    return [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount];
}

- (BOOL)showWindowBorder {
    return [iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder];
}

- (BOOL)lionStyleFullscreen {
    return [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren];
}

- (BOOL)checkTestRelease
{
    return [iTermPreferences boolForKey:kPreferenceKeyCheckForTestReleases];
}

// Smart cursor color used to be a global value. This provides the default when
// migrating.
- (BOOL)legacySmartCursorColor
{
    return [prefs objectForKey:@"ColorInvertedCursor"]?[[prefs objectForKey:@"ColorInvertedCursor"] boolValue]: YES;
}

- (BOOL)quitWhenAllWindowsClosed
{
    return [iTermPreferences boolForKey:kPreferenceKeyQuitWhenAllWindowsClosed];
}

- (BOOL)useUnevenTabs {
    return [iTermSettingsModel useUnevenTabs];
}

- (int)minTabWidth {
    return [iTermSettingsModel minTabWidth];
}

- (int)minCompactTabWidth {
    return [iTermSettingsModel minCompactTabWidth];
}

- (int)optimumTabWidth {
    return [iTermSettingsModel optimumTabWidth];
}

- (BOOL)traditionalVisualBell {
    return [iTermSettingsModel traditionalVisualBell];
}

- (BOOL) alternateMouseScroll {
    return [iTermSettingsModel alternateMouseScroll];
}

- (float)hotkeyTermAnimationDuration {
    return [iTermSettingsModel hotkeyTermAnimationDuration];
}

- (NSString *)searchCommand
{
    return [iTermSettingsModel searchCommand];
}

- (NSTimeInterval)antiIdleTimerPeriod {
    NSTimeInterval period = [iTermSettingsModel antiIdleTimerPeriod];
    if (period > 0) {
        return period;
    } else {
        return 30;
    }
}

- (BOOL)hotkeyTogglesWindow {
    return [iTermPreferences boolForKey:kPreferenceKeyHotKeyTogglesWindow];
}

- (BOOL)hotkeyAutoHides {
    return [iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides];
}

- (BOOL)dockIconTogglesWindow
{
    return [iTermSettingsModel dockIconTogglesWindow];
}

- (NSTimeInterval)timeBetweenBlinks
{
    return [iTermSettingsModel timeBetweenBlinks];
}

- (BOOL)autoCommandHistory
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"AutoCommandHistory"];
}

- (void)setAutoCommandHistory:(BOOL)value
{
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:@"AutoCommandHistory"];
}

#pragma mark - NSTableViewDataSource

- (int)numberOfRowsInTableView: (NSTableView *)aTableView
{
    if (aTableView == jobsTable_) {
        Profile *profile = [_profilesViewController selectedProfile];
        if (!profile) {
            return 0;
        }
        NSArray *jobNames = profile[KEY_JOBS];
        return [jobNames count];
    }
    // We can only get here while loading the nib (on some machines, this function is called
    // before the IBOutlets are populated).
    return 0;
}


- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    if (aTableView == jobsTable_) {
        Profile *profile = [_profilesViewController selectedProfile];
        NSMutableArray *jobs = [NSMutableArray arrayWithArray:[profile objectForKey:KEY_JOBS]];
        [jobs replaceObjectAtIndex:rowIndex withObject:anObject];
        [dataSource setObject:jobs forKey:KEY_JOBS inBookmark:profile];
    }
    [self bookmarkSettingChanged:nil];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                          row:(int)rowIndex {
    if (aTableView == jobsTable_) {
        Profile *profile = [_profilesViewController selectedProfile];
        return [profile[KEY_JOBS] objectAtIndex:rowIndex];
    }
    // Shouldn't get here but must return something to avoid a warning.
    return nil;
}

#pragma mark - Update view contents

- (void)run
{
    // load nib if we haven't already
    if ([self window] == nil) {
        [self initWithWindowNibName:@"PreferencePanel"];
    }

    [[self window] setDelegate: self]; // also forces window to load

    [_generalPreferencesViewController updateEnabledState];

    [self showWindow:self];
    [[self window] setLevel:NSNormalWindowLevel];

    [_profilesViewController selectFirstProfileIfNecessary];

    // Show the window.
    [[self window] makeKeyAndOrderFront:self];
}

- (void)setScreens
{
    int selectedTag = [screenButton selectedTag];
    [screenButton removeAllItems];
    int i = 0;
    [screenButton addItemWithTitle:@"No Preference"];
    [[screenButton lastItem] setTag:-1];
    const int numScreens = [[NSScreen screens] count];
    for (i = 0; i < numScreens; i++) {
        if (i == 0) {
            [screenButton addItemWithTitle:[NSString stringWithFormat:@"Main Screen"]];
        } else {
            [screenButton addItemWithTitle:[NSString stringWithFormat:@"Screen %d", i+1]];
        }
        [[screenButton lastItem] setTag:i];
    }
    if (selectedTag >= 0 && selectedTag < i) {
        [screenButton selectItemWithTag:selectedTag];
    } else {
        [screenButton selectItemWithTag:-1];
    }
    if ([windowTypeButton selectedTag] == WINDOW_TYPE_NORMAL) {
        [screenButton setEnabled:NO];
        [screenLabel setTextColor:[NSColor disabledControlTextColor]];
        [screenButton selectItemWithTag:-1];
    } else if (!oneBookmarkMode) {
        [screenButton setEnabled:YES];
        [screenLabel setTextColor:[NSColor blackColor]];
    }
}

- (void)_updateFontsDisplay
{
    // load the fonts
    NSString *fontName;
    if (normalFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@", [normalFont pointSize], [normalFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [normalFontField setStringValue: fontName];

    if (nonAsciiFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@", [nonAsciiFont pointSize], [nonAsciiFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [nonAsciiFontField setStringValue: fontName];
}

- (void)underlyingBookmarkDidChange
{
    Profile *profile = [_profilesViewController selectedProfile];
    if (profile) {
        [self updateBookmarkFields:profile];
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)updateBookmarkFields:(NSDictionary *)dict
{
    [_profilesViewController updateSubviewsForProfile:dict];
    if (_profilesViewController.tabView.isHidden) {
        return;
    }

    NSString* name;
    name = [dict objectForKey:KEY_NAME];

    // Display tab
    int cols = [[dict objectForKey:KEY_COLUMNS] intValue];
    [columnsField setStringValue:[NSString stringWithFormat:@"%d", cols]];
    int rows = [[dict objectForKey:KEY_ROWS] intValue];
    [rowsField setStringValue:[NSString stringWithFormat:@"%d", rows]];
    [windowTypeButton selectItemWithTag:[dict objectForKey:KEY_WINDOW_TYPE] ? [[dict objectForKey:KEY_WINDOW_TYPE] intValue] : WINDOW_TYPE_NORMAL];
    [self setScreens];
    if (![screenButton selectItemWithTag:[dict objectForKey:KEY_SCREEN] ? [[dict objectForKey:KEY_SCREEN] intValue] : -1]) {
        [screenButton selectItemWithTag:-1];
    }
    if ([dict objectForKey:KEY_SPACE]) {
        [spaceButton selectItemWithTag:[[dict objectForKey:KEY_SPACE] intValue]];
    } else {
        [spaceButton selectItemWithTag:0];
    }
    [normalFontField setStringValue:[[ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NORMAL_FONT]] displayName]];
    if (normalFont) {
        [normalFont release];
    }
    normalFont = [ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NORMAL_FONT]];
    [normalFont retain];

    [nonAsciiFontField setStringValue:[[ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NON_ASCII_FONT]] displayName]];
    if (nonAsciiFont) {
        [nonAsciiFont release];
    }
    nonAsciiFont = [ITAddressBookMgr fontWithDesc:[dict objectForKey:KEY_NON_ASCII_FONT]];
    [nonAsciiFont retain];

    [self _updateFontsDisplay];

    float horizontalSpacing = [[dict objectForKey:KEY_HORIZONTAL_SPACING] floatValue];
    float verticalSpacing = [[dict objectForKey:KEY_VERTICAL_SPACING] floatValue];

    [displayFontSpacingWidth setFloatValue:horizontalSpacing];
    [displayFontSpacingHeight setFloatValue:verticalSpacing];
    [blinkAllowed setState:[[dict objectForKey:KEY_BLINK_ALLOWED] boolValue] ? NSOnState : NSOffState];


    
    if ([dict objectForKey:KEY_USE_BRIGHT_BOLD] != nil) {
        [useBrightBold setState:[[dict objectForKey:KEY_USE_BRIGHT_BOLD] boolValue] ? NSOnState : NSOffState];
    } else {
        [useBrightBold setState:NSOnState];
    }

    [useItalicFont setState:[[dict objectForKey:KEY_USE_ITALIC_FONT] boolValue] ? NSOnState : NSOffState];

    [transparency setFloatValue:[[dict objectForKey:KEY_TRANSPARENCY] floatValue]];
        if ([dict objectForKey:KEY_BLEND]) {
          [blend setFloatValue:[[dict objectForKey:KEY_BLEND] floatValue]];
        } else {
                // Old clients used transparency for blending
                [blend setFloatValue:[[dict objectForKey:KEY_TRANSPARENCY] floatValue]];
        }
    [blurRadius setFloatValue:[dict objectForKey:KEY_BLUR_RADIUS] ? [[dict objectForKey:KEY_BLUR_RADIUS] floatValue] : 2.0];
    [blur setState:[[dict objectForKey:KEY_BLUR] boolValue] ? NSOnState : NSOffState];
    if ([dict objectForKey:KEY_USE_NONASCII_FONT]) {
        [useNonAsciiFont setState:[[dict objectForKey:KEY_USE_NONASCII_FONT] boolValue] ? NSOnState : NSOffState];
    } else {
        // Default to ON for backward compatibility
        [useNonAsciiFont setState:NSOnState];
    }
    if ([dict objectForKey:KEY_ASCII_ANTI_ALIASED]) {
        [asciiAntiAliased setState:[[dict objectForKey:KEY_ASCII_ANTI_ALIASED] boolValue] ? NSOnState : NSOffState];
    } else {
        [asciiAntiAliased setState:[[dict objectForKey:KEY_ANTI_ALIASING] boolValue] ? NSOnState : NSOffState];
    }
    [nonAsciiFontView setHidden:(useNonAsciiFont.state == NSOffState)];
    if ([dict objectForKey:KEY_NONASCII_ANTI_ALIASED]) {
        [nonasciiAntiAliased setState:[[dict objectForKey:KEY_NONASCII_ANTI_ALIASED] boolValue] ? NSOnState : NSOffState];
    } else {
        [nonasciiAntiAliased setState:[[dict objectForKey:KEY_ANTI_ALIASING] boolValue] ? NSOnState : NSOffState];
    }
    NSString* imageFilename = [dict objectForKey:KEY_BACKGROUND_IMAGE_LOCATION];
    if (!imageFilename) {
        imageFilename = @"";
    }
    [backgroundImage setState:[imageFilename length] > 0 ? NSOnState : NSOffState];
    [backgroundImagePreview setImage:[[[NSImage alloc] initByReferencingFile:imageFilename] autorelease]];
    backgroundImageFilename = imageFilename;
    [backgroundImageTiled setState:[[dict objectForKey:KEY_BACKGROUND_IMAGE_TILED] boolValue] ? NSOnState : NSOffState];

    // Terminal tab
    [disableWindowResizing setState:[[dict objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue] ? NSOnState : NSOffState];
    [preventTab setState:[[dict objectForKey:KEY_PREVENT_TAB] boolValue] ? NSOnState : NSOffState];
    [hideAfterOpening setState:[[dict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue] ? NSOnState : NSOffState];
    [syncTitle setState:[[dict objectForKey:KEY_SYNC_TITLE] boolValue] ? NSOnState : NSOffState];
    [nonAsciiDoubleWidth setState:[[dict objectForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH] boolValue] ? NSOnState : NSOffState];
    [silenceBell setState:[[dict objectForKey:KEY_SILENCE_BELL] boolValue] ? NSOnState : NSOffState];
    [visualBell setState:[[dict objectForKey:KEY_VISUAL_BELL] boolValue] ? NSOnState : NSOffState];
    [flashingBell setState:[[dict objectForKey:KEY_FLASHING_BELL] boolValue] ? NSOnState : NSOffState];
    [xtermMouseReporting setState:[[dict objectForKey:KEY_XTERM_MOUSE_REPORTING] boolValue] ? NSOnState : NSOffState];
    [disableSmcupRmcup setState:[[dict objectForKey:KEY_DISABLE_SMCUP_RMCUP] boolValue] ? NSOnState : NSOffState];
    [allowTitleReporting setState:[[dict objectForKey:KEY_ALLOW_TITLE_REPORTING] boolValue] ? NSOnState : NSOffState];
    NSNumber *allowTitleSettingNumber = [dict objectForKey:KEY_ALLOW_TITLE_SETTING];
    if (!allowTitleSettingNumber) {
        allowTitleSettingNumber = @YES;
    }
    [allowTitleSetting setState:[allowTitleSettingNumber boolValue] ? NSOnState : NSOffState];
    [disablePrinting setState:[[dict objectForKey:KEY_DISABLE_PRINTING] boolValue] ? NSOnState : NSOffState];
    [scrollbackWithStatusBar setState:[[dict objectForKey:KEY_SCROLLBACK_WITH_STATUS_BAR] boolValue] ? NSOnState : NSOffState];
    [scrollbackInAlternateScreen setState:[dict objectForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN] ?
         ([[dict objectForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN] boolValue] ? NSOnState : NSOffState) : NSOnState];
    [bookmarkGrowlNotifications setState:[[dict objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue] ? NSOnState : NSOffState];
    [setLocaleVars setState:[dict objectForKey:KEY_SET_LOCALE_VARS] ? ([[dict objectForKey:KEY_SET_LOCALE_VARS] boolValue] ? NSOnState : NSOffState) : NSOnState];
    [characterEncoding setTitle:[NSString localizedNameOfStringEncoding:[[dict objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue]]];
    [scrollbackLines setIntValue:[[dict objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    [unlimitedScrollback setState:[[dict objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue] ? NSOnState : NSOffState];
    [scrollbackLines setEnabled:[unlimitedScrollback state] == NSOffState];
    if ([unlimitedScrollback state] == NSOnState) {
        [scrollbackLines setStringValue:@""];
    }
    [terminalType setStringValue:[dict objectForKey:KEY_TERMINAL_TYPE]];

    // Keyboard tab
    [optionKeySends selectCellWithTag:[[dict objectForKey:KEY_OPTION_KEY_SENDS] intValue]];
    id rightOptPref = [dict objectForKey:KEY_RIGHT_OPTION_KEY_SENDS];
    if (!rightOptPref) {
        rightOptPref = [dict objectForKey:KEY_OPTION_KEY_SENDS];
    }
    [rightOptionKeySends selectCellWithTag:[rightOptPref intValue]];
    // If a keymapping for the delete key was added, make sure the
    // "delete sends ^h" checkbox is correct
    BOOL sendCH = [self _deleteSendsCtrlHInBookmark:dict];
    [deleteSendsCtrlHButton setState:sendCH ? NSOnState : NSOffState];
    [applicationKeypadAllowed setState:[dict boolValueDefaultingToYesForKey:KEY_APPLICATION_KEYPAD_ALLOWED] ? NSOnState : NSOffState];

    // Session tab
    [closeSessionsOnEnd setState:[[dict objectForKey:KEY_CLOSE_SESSIONS_ON_END] boolValue] ? NSOnState : NSOffState];
    [promptBeforeClosing_ selectCellWithTag:[[dict objectForKey:KEY_PROMPT_CLOSE] intValue]];
    [jobsTable_ reloadData];
    [autoLog setState:[[dict objectForKey:KEY_AUTOLOG] boolValue] ? NSOnState : NSOffState];
    [logDir setStringValue:[dict objectForKey:KEY_LOGDIR] ? [dict objectForKey:KEY_LOGDIR] : @""];
    [logDir setEnabled:[autoLog state] == NSOnState];
    [changeLogDir setEnabled:[autoLog state] == NSOnState];
    [self _updateLogDirWarning];
    [sendCodeWhenIdle setState:[[dict objectForKey:KEY_SEND_CODE_WHEN_IDLE] boolValue] ? NSOnState : NSOffState];
    [idleCode setIntValue:[[dict objectForKey:KEY_IDLE_CODE] intValue]];

    // Epilogue
    [_profilesViewController reloadData];

    [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidUpdateProfileFields
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - NSFontPanel and NSFontManager

- (void)_showFontPanel
{
    // make sure we get the messages from the NSFontManager
    [[self window] makeFirstResponder:self];

    NSFontPanel* aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
    [aFontPanel setAccessoryView: displayFontAccessoryView];
    [[NSFontManager sharedFontManager] setSelectedFont:(changingNonAsciiFont ? nonAsciiFont : normalFont) isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}

// sent by NSFontManager up the responder chain
- (void)changeFont:(id)fontManager
{
    if (changingNonAsciiFont) {
        NSFont* oldFont = nonAsciiFont;
        nonAsciiFont = [fontManager convertFont:oldFont];
        [nonAsciiFont retain];
        if (oldFont) {
            [oldFont release];
        }
    } else {
        NSFont* oldFont = normalFont;
        normalFont = [fontManager convertFont:oldFont];
        [normalFont retain];
        if (oldFont) {
            [oldFont release];
        }
    }

    [self bookmarkSettingChanged:fontManager];
}

#pragma mark - Warning Dialogs

- (void)_maybeWarnAboutMeta
{
    [iTermWarning showWarningWithTitle:@"You have chosen to have an option key act as Meta. This option is useful for backward "
                                       @"compatibility with older systems. The \"+Esc\" option is recommended for most users."
                               actions:@[ @"OK" ]
                            identifier:@"NeverWarnAboutMeta"
                           silenceable:kiTermWarningTypePermanentlySilenceable];
}

- (void)_maybeWarnAboutSpaces
{
    [iTermWarning showWarningWithTitle:@"To have a new window open in a specific space, make sure that Spaces is enabled in System "
                                       @"Preferences and that it is configured to switch directly to a space with ^ Number Keys."
                               actions:@[ @"OK" ]
                            identifier:@"NeverWarnAboutSpaces"
                           silenceable:kiTermWarningTypePermanentlySilenceable];
}

- (BOOL)_warnAboutOverride
{
    switch ([iTermWarning showWarningWithTitle:@"The keyboard shortcut you have set for this profile will take precedence over "
                                               @"an existing shortcut for the same key combination in a global shortcut."
                                       actions:@[ @"OK", @"Cancel" ]
                                    identifier:@"NeverWarnAboutOverrides"
                                   silenceable:kiTermWarningTypePermanentlySilenceable]) {
        case kiTermWarningSelection1:
            return NO;
        default:
            return YES;
    }
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    if ([aNotification object] == jobsTable_) {
        [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    }
}

#pragma mark - NSTextFieldDelegate

- (void)forceTextFieldToBeNumber:(NSTextField *)textField
                 acceptableRange:(NSRange)range
{
    // NSNumberFormatter seems to have lost its mind on Lion. See a description of the problem here:
    // http://stackoverflow.com/questions/7976951/nsnumberformatter-erasing-value-when-it-violates-constraints
    int iv = [self intForString:[textField stringValue] inRange:range];
    unichar lastChar = '0';
    int numChars = [[textField stringValue] length];
    if (numChars) {
        lastChar = [[textField stringValue] characterAtIndex:numChars - 1];
    }
    if (iv != [textField intValue] || (lastChar < '0' || lastChar > '9')) {
        // If the int values don't match up or there are terminal non-number
        // chars, then update the value.
        [textField setIntValue:iv];
    }
}

// Technically, this is part of NSTextDelegate
- (void)textDidChange:(NSNotification *)aNotification
{
    [self bookmarkSettingChanged:nil];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    id obj = [aNotification object];
    if (obj == scrollbackLines) {
                [self forceTextFieldToBeNumber:scrollbackLines
                                           acceptableRange:NSMakeRange(0, 10 * 1000 * 1000)];
        [self bookmarkSettingChanged:nil];
    } else if (obj == columnsField ||
               obj == rowsField ||
               obj == terminalType ||
               obj == idleCode) {
        [self bookmarkSettingChanged:nil];
    } else if (obj == logDir) {
        [self _updateLogDirWarning];
    }
}

#pragma mark - Cocoa Bindings

// An experiment with cocoa bindings. This is bound to the "enabled" status of
// the "remove job" button.
- (BOOL)haveJobsForCurrentBookmark
{
    if ([jobsTable_ selectedRow] < 0) {
        return NO;
    }
    Profile *profile = [_profilesViewController selectedProfile];
    if (!profile) {
        return NO;
    }
    NSArray *jobNames = profile[KEY_JOBS];
    return [jobNames count] > 0;
}

- (void)setHaveJobsForCurrentBookmark:(BOOL)value
{
    // observed but has no effect because the getter does all the computation.
}

#pragma mark - iTermKeyMappingViewControllerDelegate

- (NSDictionary *)keyMappingDictionary:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [_profilesViewController selectedProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyBindingMgr keyMappingsForProfile:profile];
}

- (NSArray *)keyMappingSortedKeys:(iTermKeyMappingViewController *)viewController {
    Profile *profile = [_profilesViewController selectedProfile];
    if (!profile) {
        return nil;
    }
    return [iTermKeyBindingMgr sortedKeyCombinationsForProfile:profile];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
 didChangeKeyCombo:(NSString *)keyCombo
           atIndex:(NSInteger)index
          toAction:(int)action
         parameter:(NSString *)parameter
        isAddition:(BOOL)addition {
    Profile *profile = [_profilesViewController selectedProfile];
    assert(profile);
    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];

    if ([iTermKeyBindingMgr haveGlobalKeyMappingForKeyString:keyCombo]) {
        if (![self _warnAboutOverride]) {
            return;
        }
    }

    [iTermKeyBindingMgr setMappingAtIndex:index
                                   forKey:keyCombo
                                   action:action
                                    value:parameter
                                createNew:addition
                               inBookmark:dict];
    [dataSource setBookmark:dict withGuid:profile[KEY_GUID]];
    [self bookmarkSettingChanged:nil];
}


- (void)keyMapping:(iTermKeyMappingViewController *)viewController
    removeKeyCombo:(NSString *)keyCombo {

    Profile *profile = [_profilesViewController selectedProfile];
    assert(profile);

    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];
    NSUInteger index =
        [[iTermKeyBindingMgr sortedKeyCombinationsForProfile:profile] indexOfObject:keyCombo];
    assert(index != NSNotFound);

    [iTermKeyBindingMgr removeMappingAtIndex:index inBookmark:dict];
    [dataSource setBookmark:dict withGuid:profile[KEY_GUID]];
    [self bookmarkSettingChanged:nil];
}

- (NSArray *)keyMappingPresetNames:(iTermKeyMappingViewController *)viewController {
    return [iTermKeyBindingMgr presetKeyMappingsNames];
}

- (void)keyMapping:(iTermKeyMappingViewController *)viewController
  loadPresetsNamed:(NSString *)presetName {
    Profile *profile = [_profilesViewController selectedProfile];
    assert(profile);

    NSMutableDictionary *dict = [[profile mutableCopy] autorelease];

    [iTermKeyBindingMgr setKeyMappingsToPreset:presetName inBookmark:dict];
    [dataSource setBookmark:dict withGuid:profile[KEY_GUID]];

    [self bookmarkSettingChanged:nil];
}

- (void)profileWithGuidWasSelected:(NSString *)guid {
    if (guid) {
        triggerWindowController_.guid = guid;
        smartSelectionWindowController_.guid = guid;
        trouterPrefController_.guid = guid;
        [self updateBookmarkFields:[dataSource bookmarkWithGuid:guid]];

        [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
    }
}

- (ProfileModel *)profilePreferencesModel {
    return dataSource;
}

- (void)profilePreferencesModelDidAwakeFromNib {
    [self awakeFromNib];
}

@end

