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

#import "PreferencePanel.h"

#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermFontPanel.h"
#import "iTermKeyBindingMgr.h"
#import "iTermRemotePreferences.h"
#import "iTermSettingsModel.h"
#import "iTermWarning.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "PasteboardHistory.h"
#import "PointerPrefsController.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "SessionView.h"
#import "SmartSelectionController.h"
#import "TriggerController.h"
#import "TrouterPrefsController.h"
#import "WindowArrangements.h"
#include <stdlib.h>

static NSString * const kCustomColorPresetsKey = @"Custom Color Presets";
static NSString * const kHotkeyWindowGeneratedProfileNameKey = @"Hotkey Window";
static NSString * const kDeleteKeyString = @"0x7f-0x0";
static NSString * const kRebuildColorPresetsMenuNotification = @"kRebuildColorPresetsMenuNotification";

@interface PreferencePanel ()
@property(nonatomic, copy) NSString *currentProfileGuid;
@end

@implementation PreferencePanel {
    ProfileModel* dataSource;
    BOOL oneBookmarkMode;
    IBOutlet TriggerController *triggerWindowController_;
    IBOutlet SmartSelectionController *smartSelectionWindowController_;
    IBOutlet TrouterPrefsController *trouterPrefController_;
    
    // This is actually the tab style. It takes one of these values:
    // 0: Metal
    // 1: Aqua
    // 2: Unified
    // other: Adium
    // Bound to Metal/Aqua/Unified/Adium button
    IBOutlet NSPopUpButton *windowStyle;
    int defaultWindowStyle;

    // This gives a value from NSTabViewType, which as of OS 10.6 is:
    // Bound to Top/Bottom button
    // NSTopTabsBezelBorder     = 0,
    // NSLeftTabsBezelBorder    = 1,
    // NSBottomTabsBezelBorder  = 2,
    // NSRightTabsBezelBorder   = 3,
    // NSNoTabsBezelBorder      = 4,
    // NSNoTabsLineBorder       = 5,
    // NSNoTabsNoBorder         = 6
    IBOutlet NSPopUpButton *tabPosition;
    int defaultTabViewType;
    
    IBOutlet NSTextField* tagFilter;
    
    // Allow clipboard access by terminal applications
    IBOutlet NSButton *allowClipboardAccessFromTerminal;
    BOOL defaultAllowClipboardAccess;
    
    // Copy to clipboard on selection
    IBOutlet NSButton *selectionCopiesText;
    BOOL defaultCopySelection;
    
    // Copy includes trailing newline
    IBOutlet NSButton *copyLastNewline;
    BOOL defaultCopyLastNewline;
    
    // Middle button paste from clipboard
    IBOutlet NSButton *middleButtonPastesFromClipboard;
    BOOL defaultPasteFromClipboard;
    
    // Three finger click emulates middle button
    IBOutlet NSButton *threeFingerEmulatesMiddle;
    BOOL defaultThreeFingerEmulatesMiddle;
    
    // Hide tab bar when there is only one session
    IBOutlet id hideTab;
    BOOL defaultHideTab;
    
    // Warn when quitting
    IBOutlet id promptOnQuit;
    BOOL defaultPromptOnQuit;
    
    // only when multiple sessions close
    IBOutlet id onlyWhenMoreTabs;
    BOOL defaultOnlyWhenMoreTabs;
    
    // Focus follows mouse
    IBOutlet NSButton *focusFollowsMouse;
    BOOL defaultFocusFollowsMouse;
    
    // Triple click selects full, wrapped lines
    IBOutlet NSButton *tripleClickSelectsFullLines;
    BOOL defaultTripleClickSelectsFullLines;
    
    // Characters considered part of word
    IBOutlet NSTextField *wordChars;
    NSString *defaultWordChars;
    
    // Hotkey opens dedicated window
    IBOutlet NSButton* hotkeyTogglesWindow;
    IBOutlet NSButton* hotkeyAutoHides;
    BOOL defaultHotkeyTogglesWindow;
    BOOL defaultHotkeyAutoHides;
    IBOutlet NSPopUpButton* hotkeyBookmark;
    NSString* defaultHotKeyBookmarkGuid;
    
    // Enable bonjour
    IBOutlet NSButton *enableBonjour;
    BOOL defaultEnableBonjour;
    
    // cmd-click to launch url
    IBOutlet NSButton *cmdSelection;
    BOOL defaultCmdSelection;
    
    // pass on ctrl-click
    IBOutlet NSButton* controlLeftClickActsLikeRightClick;
    BOOL defaultPassOnControlLeftClick;
    
    // Opt-click moves cursor
    IBOutlet NSButton *optionClickMovesCursor;
    BOOL defaultOptionClickMovesCursor;
    
    // Zoom vertically only
    IBOutlet NSButton *maxVertically;
    BOOL defaultMaxVertically;
    
    // use compact tab labels
    IBOutlet NSButton *hideTabNumber;
    IBOutlet NSButton *hideTabCloseButton;
    BOOL defaultHideTabNumber;
    BOOL defaultHideTabCloseButton;
    
    // hide activity indicator
    IBOutlet NSButton *hideActivityIndicator;
    BOOL defaultHideActivityIndicator;
    
    // Highlight tab labels on activity
    IBOutlet NSButton *highlightTabLabels;
    BOOL defaultHighlightTabLabels;
    
    // Hide menu bar in non-lion fullscreen
    IBOutlet NSButton *hideMenuBarInFullscreen;
    BOOL defaultHideMenuBarInFullscreen;
    
    // Minimum contrast
    IBOutlet NSSlider* minimumContrast;
    
    // open bookmarks when iterm starts
    IBOutlet NSButton *openBookmark;
    BOOL defaultOpenBookmark;
    
    // quit when all windows are closed
    IBOutlet NSButton *quitWhenAllWindowsClosed;
    BOOL defaultQuitWhenAllWindowsClosed;
    
    // check for updates automatically
    IBOutlet NSButton *checkUpdate;
    BOOL defaultCheckUpdate;
    
    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
    IBOutlet NSMatrix *cursorType;
    
    IBOutlet NSButton *useTabColor;
    IBOutlet NSButton *checkColorInvertedCursor;
    BOOL defaultColorInvertedCursor;
    
    // Dim inactive split panes
    IBOutlet NSButton* dimInactiveSplitPanes;
    BOOL defaultDimInactiveSplitPanes;
    
    // Animate dimming
    IBOutlet NSButton* animateDimming;
    BOOL defaultAnimateDimming;
    
    // Dim background windows
    IBOutlet NSButton* dimBackgroundWindows;
    BOOL defaultDimBackgroundWindows;
    
    // Dim text (and non-default background colors)
    IBOutlet NSButton* dimOnlyText;
    BOOL defaultDimOnlyText;
    
    // Dimming amount
    IBOutlet NSSlider* dimmingAmount;
    float defaultDimmingAmount;
    
    // Window border
    IBOutlet NSButton* showWindowBorder;
    BOOL defaultShowWindowBorder;
    
    // Lion-style fullscreen
    IBOutlet NSButton* lionStyleFullscreen;
    BOOL defaultLionStyleFullscreen;
    
    // Open tmux dashboard if there are more than N windows
    IBOutlet NSTextField *tmuxDashboardLimit;
    int defaultTmuxDashboardLimit;
    
    // Open tmux windows in
    IBOutlet NSPopUpButton *openTmuxWindows;
    int defaultOpenTmuxWindowsIn;
    
    // Hide the tmux client session
    IBOutlet NSButton *autoHideTmuxClientSession;
    BOOL defaultAutoHideTmuxClientSession;
    
    // Load prefs from custom folder
    IBOutlet NSButton *loadPrefsFromCustomFolder;
    IBOutlet NSTextField *prefsCustomFolder;
    IBOutlet NSButton *browseCustomFolder;
    IBOutlet NSButton *pushToCustomFolder;
    IBOutlet NSImageView *prefsDirWarning;
    BOOL customFolderChanged_;
    
    // hide scrollbar and resize
    IBOutlet NSButton *hideScrollbar;
    BOOL defaultHideScrollbar;
    
    // show pane titles
    IBOutlet NSButton *showPaneTitles;
    BOOL defaultShowPaneTitles;
    
    // Disable transparency in fullscreen by default
    IBOutlet NSButton *disableFullscreenTransparency;
    BOOL defaultDisableFullscreenTransparency;
    
    // smart window placement
    IBOutlet NSButton *smartPlacement;
    BOOL defaultSmartPlacement;
    
    // Adjust window size when changing font size
    IBOutlet NSButton *adjustWindowForFontSizeChange;
    BOOL defaultAdjustWindowForFontSizeChange;
    
    // Delay before showing tabs in fullscreen mode
    IBOutlet NSSlider* fsTabDelay;
    float defaultFsTabDelay;
    
    // Window/tab title customization
    IBOutlet NSButton* windowNumber;
    BOOL defaultWindowNumber;
    
    // Show job name in title
    IBOutlet NSButton* jobName;
    BOOL defaultJobName;
    
    // Show bookmark name in title
    IBOutlet NSButton* showBookmarkName;
    BOOL defaultShowBookmarkName;
    
    // instant replay
    IBOutlet NSButton *instantReplay;
    BOOL defaultInstantReplay;
    
    // instant replay memory usage.
    IBOutlet NSTextField* irMemory;
    int defaultIrMemory;
    
    // hotkey
    IBOutlet NSButton *hotkey;
    IBOutlet NSTextField* hotkeyLabel;
    BOOL defaultHotkey;
    
    // hotkey code
    IBOutlet NSTextField* hotkeyField;
    int defaultHotkeyChar;
    int defaultHotkeyCode;
    int defaultHotkeyModifiers;
    
    // Save copy paste history
    IBOutlet NSButton *savePasteHistory;
    BOOL defaultSavePasteHistory;
    
    // Open saved window arrangement at startup
    IBOutlet NSButton *openArrangementAtStartup;
    BOOL defaultOpenArrangementAtStartup;
    
    // prompt for test-release updates
    IBOutlet NSButton *checkTestRelease;
    BOOL defaultCheckTestRelease;
    
    IBOutlet NSTabView* bookmarksSettingsTabViewParent;
    IBOutlet NSTabViewItem* bookmarkSettingsGeneralTab;
    
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
    
    // url handler stuff
    NSMutableDictionary *urlHandlersByGuid;
    
    // Bookmarks -----------------------------
    IBOutlet ProfileListView *bookmarksTableView;
    IBOutlet NSTableColumn *shellImageColumn;
    IBOutlet NSTableColumn *nameShortcutColumn;
    IBOutlet NSButton *removeBookmarkButton;
    IBOutlet NSButton *addBookmarkButton;
    IBOutlet NSButton *toggleTagsButton;
    
    // General tab
    IBOutlet NSTextField *basicsLabel;
    IBOutlet NSTextField *bookmarkName;
    IBOutlet NSPopUpButton *bookmarkShortcutKey;
    IBOutlet NSMatrix *bookmarkCommandType;
    IBOutlet NSTextField *bookmarkCommand;
    IBOutlet NSTextField *initialText;
    IBOutlet NSMatrix *bookmarkDirectoryType;
    IBOutlet NSTextField *bookmarkDirectory;
    IBOutlet NSTextField *bookmarkShortcutKeyLabel;
    IBOutlet NSTextField *bookmarkShortcutKeyModifiersLabel;
    IBOutlet NSTextField *bookmarkTagsLabel;
    IBOutlet NSTextField *bookmarkCommandLabel;
    IBOutlet NSTextField *initialTextLabel;
    IBOutlet NSTextField *bookmarkDirectoryLabel;
    IBOutlet NSTextField *bookmarkUrlSchemesHeaderLabel;
    IBOutlet NSTextField *bookmarkUrlSchemesLabel;
    IBOutlet NSPopUpButton* bookmarkUrlSchemes;
    IBOutlet NSButton* editAdvancedConfigButton;
    
    // Advanced working dir sheet
    IBOutlet NSPanel* advancedWorkingDirSheet_;
    IBOutlet NSMatrix* awdsWindowDirectoryType;
    IBOutlet NSTextField* awdsWindowDirectory;
    IBOutlet NSMatrix* awdsTabDirectoryType;
    IBOutlet NSTextField* awdsTabDirectory;
    IBOutlet NSMatrix* awdsPaneDirectoryType;
    IBOutlet NSTextField* awdsPaneDirectory;
    
    // Only visible in Get Info mode
    IBOutlet NSButton* copyToProfileButton;
    IBOutlet NSTextField* setProfileLabel;
    IBOutlet ProfileListView* setProfileBookmarkListView;
    IBOutlet NSButton* changeProfileButton;
    
    // Colors tab
    IBOutlet NSColorWell *ansi0Color;
    IBOutlet NSColorWell *ansi1Color;
    IBOutlet NSColorWell *ansi2Color;
    IBOutlet NSColorWell *ansi3Color;
    IBOutlet NSColorWell *ansi4Color;
    IBOutlet NSColorWell *ansi5Color;
    IBOutlet NSColorWell *ansi6Color;
    IBOutlet NSColorWell *ansi7Color;
    IBOutlet NSColorWell *ansi8Color;
    IBOutlet NSColorWell *ansi9Color;
    IBOutlet NSColorWell *ansi10Color;
    IBOutlet NSColorWell *ansi11Color;
    IBOutlet NSColorWell *ansi12Color;
    IBOutlet NSColorWell *ansi13Color;
    IBOutlet NSColorWell *ansi14Color;
    IBOutlet NSColorWell *ansi15Color;
    IBOutlet NSColorWell *foregroundColor;
    IBOutlet NSColorWell *backgroundColor;
    IBOutlet NSColorWell *boldColor;
    IBOutlet NSColorWell *selectionColor;
    IBOutlet NSColorWell *selectedTextColor;
    IBOutlet NSColorWell *cursorColor;
    IBOutlet NSColorWell *cursorTextColor;
    IBOutlet NSColorWell *tabColor;
    IBOutlet NSTextField *cursorColorLabel;
    IBOutlet NSTextField *cursorTextColorLabel;
    IBOutlet NSMenu *presetsMenu;
    
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
    
    IBOutlet NSButton* blinkingCursor;
    IBOutlet NSButton* blinkAllowed;
    IBOutlet NSButton* useBoldFont;
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
    IBOutlet NSTableView* keyMappings;
    IBOutlet NSTableColumn* keyCombinationColumn;
    IBOutlet NSTableColumn* actionColumn;
    IBOutlet NSWindow* editKeyMappingWindow;
    IBOutlet NSTextField* keyPress;
    IBOutlet NSPopUpButton* action;
    IBOutlet NSTextField* valueToSend;
    IBOutlet NSTextField* profileLabel;
    IBOutlet NSPopUpButton* bookmarkPopupButton;
    IBOutlet NSPopUpButton* menuToSelect;
    IBOutlet NSButton* removeMappingButton;
    IBOutlet NSTextField* escPlus;
    IBOutlet NSMatrix *optionKeySends;
    IBOutlet NSMatrix *rightOptionKeySends;
    IBOutlet NSTokenField* tags;
    
    IBOutlet NSPopUpButton* presetsPopupButton;
    IBOutlet NSTextField*   presetsErrorLabel;
    
    NSString* keyString;  // hexcode-hexcode rep of keystring in current sheet
    BOOL newMapping;  // true if the keymap sheet is open for adding a new entry
    id modifyMappingOriginator;  // widget that caused add new mapping window to open
    IBOutlet NSPopUpButton* bookmarksPopup;
    IBOutlet NSButton* addNewMapping;
    
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
    
    // Copy Bookmark Settings...
    IBOutlet NSTextField* bulkCopyLabel;
    IBOutlet NSPanel* copyPanel;
    IBOutlet NSButton* copyColors;
    IBOutlet NSButton* copyDisplay;
    IBOutlet NSButton* copyTerminal;
    IBOutlet NSButton* copyWindow;
    IBOutlet NSButton* copyKeyboard;
    IBOutlet NSButton* copySession;
    IBOutlet NSButton* copyAdvanced;
    IBOutlet ProfileListView* copyTo;
    IBOutlet NSButton* copyButton;
    
    // Keyboard ------------------------------
    int defaultControl;
    IBOutlet NSPopUpButton* controlButton;
    int defaultLeftOption;
    IBOutlet NSPopUpButton* leftOptionButton;
    int defaultRightOption;
    IBOutlet NSPopUpButton* rightOptionButton;
    int defaultLeftCommand;
    IBOutlet NSPopUpButton* leftCommandButton;
    int defaultRightCommand;
    IBOutlet NSPopUpButton* rightCommandButton;
    
    int defaultSwitchTabModifier;
    IBOutlet NSPopUpButton* switchTabModifierButton;
    int defaultSwitchWindowModifier;
    IBOutlet NSPopUpButton* switchWindowModifierButton;
    
    IBOutlet NSButton* deleteSendsCtrlHButton;
    IBOutlet NSButton* applicationKeypadAllowed;
    IBOutlet NSTableView* globalKeyMappings;
    IBOutlet NSTableColumn* globalKeyCombinationColumn;
    IBOutlet NSTableColumn* globalActionColumn;
    IBOutlet NSButton* globalRemoveMappingButton;
    IBOutlet NSButton* globalAddNewMapping;
    
    IBOutlet WindowArrangements *arrangements_;
}

+ (PreferencePanel*)sharedInstance
{
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[ProfileModel sharedInstance]
                                     userDefaults:[NSUserDefaults standardUserDefaults]
                                  oneBookmarkMode:NO];
    }

    return shared;
}

+ (PreferencePanel*)sessionsInstance
{
    static PreferencePanel* shared = nil;

    if (!shared) {
        shared = [[self alloc] initWithDataSource:[ProfileModel sessionsInstance]
                                     userDefaults:nil
                                  oneBookmarkMode:YES];
    }

    return shared;
}


// Class method to copy old preferences file, iTerm.plist or net.sourceforge.iTerm.plist, to new
// preferences file, com.googlecode.iterm2.plist
+ (BOOL)migratePreferences
{
    NSString *prefDir = [[NSHomeDirectory()
        stringByAppendingPathComponent:@"Library"]
        stringByAppendingPathComponent:@"Preferences"];

    NSString *reallyOldPrefs = [prefDir stringByAppendingPathComponent:@"iTerm.plist"];
    NSString *somewhatOldPrefs = [prefDir stringByAppendingPathComponent:@"net.sourceforge.iTerm.plist"];
    NSString *newPrefs = [prefDir stringByAppendingPathComponent:@"com.googlecode.iterm2.plist"];

    NSFileManager *mgr = [NSFileManager defaultManager];

    if ([mgr fileExistsAtPath:newPrefs]) {
        return NO;
    }
    NSString* source;
    if ([mgr fileExistsAtPath:somewhatOldPrefs]) {
        source = somewhatOldPrefs;
    } else if ([mgr fileExistsAtPath:reallyOldPrefs]) {
        source = reallyOldPrefs;
    } else {
        return NO;
    }

    NSLog(@"Preference file migrated");
    [mgr copyItemAtPath:source toPath:newPrefs error:nil];
    [NSUserDefaults resetStandardUserDefaults];
    return (YES);
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

        [self readPreferences];
        if (defaultEnableBonjour == YES) {
            [[ITAddressBookMgr sharedInstance] locateBonjourServices];
        }

        // get the version
        NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];

        // sync the version number
        if (prefs) {
            [prefs setObject:[myDict objectForKey:@"CFBundleVersion"] forKey:@"iTerm Version"];
        }
        [toolbar setSelectedItemIdentifier:globalToolbarId];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_reloadURLHandlers:)
                                                     name:@"iTermReloadAddressBook"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_savedArrangementChanged:)
                                                     name:@"iTermSavedArrangementChanged"
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyBindingsChanged)
                                                     name:@"iTermKeyBindingsChanged"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(rebuildColorPresetsMenu)
                                                     name:kRebuildColorPresetsMenuNotification
                                                   object:nil];
        oneBookmarkMode = obMode;
    }
    return self;
}

#pragma mark - View layout

- (void)awakeFromNib
{
    [self window];
    [[self window] setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    NSAssert(bookmarksTableView, @"Null table view");
    [bookmarksTableView setUnderlyingDatasource:dataSource];
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
    NSEnumerator *anEnumerator;
    NSNumber *anEncoding;

    [characterEncoding removeAllItems];
    anEnumerator = [[[iTermController sharedInstance] sortedEncodingList] objectEnumerator];
    while ((anEncoding = [anEnumerator nextObject]) != NULL) {
        [characterEncoding addItemWithTitle:[NSString localizedNameOfStringEncoding:[anEncoding unsignedIntValue]]];
        [[characterEncoding lastItem] setTag:[anEncoding unsignedIntValue]];
    }
    [self setScreens];

    [keyMappings setDoubleAction:@selector(editKeyMapping:)];
    [globalKeyMappings setDoubleAction:@selector(editKeyMapping:)];
    keyString = nil;

    [copyTo allowMultipleSelections];

    // Add presets to preset color selection.
    [self rebuildColorPresetsMenu];

    // Add preset keybindings to button-popup-list.
    NSArray* presetArray = [iTermKeyBindingMgr presetKeyMappingsNames];
    if (presetArray != nil) {
        [presetsPopupButton addItemsWithTitles:presetArray];
    } else {
        [presetsPopupButton setEnabled:NO];
        [presetsErrorLabel setFont:[NSFont boldSystemFontOfSize:12]];
        [presetsErrorLabel setStringValue:@"PresetKeyMappings.plist failed to load"];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleWindowWillCloseNotification:)
                                                 name:NSWindowWillCloseNotification object: [self window]];
    if (oneBookmarkMode) {
        [self layoutSubviewsForSingleBookmarkMode];
    }
    [[tags cell] setDelegate:self];
    [tags setDelegate:self];

    [lionStyleFullscreen setHidden:NO];
    [initialText setContinuous:YES];
    [blurRadius setContinuous:YES];
    [transparency setContinuous:YES];
    [blend setContinuous:YES];
    [dimmingAmount setContinuous:YES];
    [minimumContrast setContinuous:YES];

    BOOL shouldLoadRemotePrefs = [[iTermRemotePreferences sharedInstance] shouldLoadRemotePrefs];
    [prefsCustomFolder setEnabled:shouldLoadRemotePrefs];
    [browseCustomFolder setEnabled:shouldLoadRemotePrefs];
    [pushToCustomFolder setEnabled:shouldLoadRemotePrefs];
    [self _updatePrefsDirWarning];
}

- (void)layoutSubviewsForSingleBookmarkMode
{
    [self showBookmarks];
    [toolbar setVisible:NO];
    [editAdvancedConfigButton setHidden:YES];
    [bookmarksTableView setHidden:YES];
    [addBookmarkButton setHidden:YES];
    [removeBookmarkButton setHidden:YES];
    [bookmarksPopup setHidden:YES];
    [bookmarkDirectory setHidden:YES];
    [bookmarkShortcutKeyLabel setHidden:YES];
    [bookmarkShortcutKeyModifiersLabel setHidden:YES];
    [bookmarkTagsLabel setHidden:YES];
    [bookmarkCommandLabel setHidden:YES];
    [initialTextLabel setHidden:YES];
    [bookmarkDirectoryLabel setHidden:YES];
    [bookmarkShortcutKey setHidden:YES];
    [tags setHidden:YES];
    [bookmarkCommandType setHidden:YES];
    [bookmarkCommand setHidden:YES];
    [initialText setHidden:YES];
    [bookmarkDirectoryType setHidden:YES];
    [bookmarkDirectory setHidden:YES];
    [bookmarkUrlSchemes setHidden:YES];
    [bookmarkUrlSchemesHeaderLabel setHidden:YES];
    [bookmarkUrlSchemesLabel setHidden:YES];
    [copyToProfileButton setHidden:NO];
    [setProfileLabel setHidden:NO];
    [setProfileBookmarkListView setHidden:NO];
    [changeProfileButton setHidden:NO];
    [toggleTagsButton setHidden:YES];
    
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

    NSRect newFrame = [bookmarksSettingsTabViewParent frame];
    newFrame.origin.x = 0;
    [bookmarksSettingsTabViewParent setFrame:newFrame];

    newFrame = [[self window] frame];
    newFrame.size.width = [bookmarksSettingsTabViewParent frame].size.width + 26;
    [[self window] setFrame:newFrame display:YES];
}

#pragma mark - API

- (BOOL)onScreen
{
    return [self window] && [[self window] isVisible];
}

- (void)showBookmarks
{
    [tabView selectTabViewItem:bookmarksTabViewItem];
    [toolbar setSelectedItemIdentifier:bookmarksToolbarId];
}

- (void)openToBookmark:(NSString*)guid
{
    [self run];
    [self updateBookmarkFields:[dataSource bookmarkWithGuid:guid]];
    [self showBookmarks];
    [bookmarksTableView selectRowByGuid:guid];
    [setProfileBookmarkListView selectRowByGuid:nil];
    [bookmarksSettingsTabViewParent selectTabViewItem:bookmarkSettingsGeneralTab];
    [[self window] makeFirstResponder:bookmarkName];
    self.currentProfileGuid = guid;
}

- (Profile*)hotkeyBookmark
{
    if (defaultHotKeyBookmarkGuid) {
        return [[ProfileModel sharedInstance] bookmarkWithGuid:defaultHotKeyBookmarkGuid];
    } else {
        return nil;
    }
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

- (void)_reloadURLHandlers:(NSNotification *)aNotification
{
    // TODO: maybe something here for the current bookmark?
    [self _populateHotKeyBookmarksMenu];
}

- (void)_savedArrangementChanged:(id)sender
{
    [openArrangementAtStartup setState:defaultOpenArrangementAtStartup ? NSOnState : NSOffState];
    [openArrangementAtStartup setEnabled:[WindowArrangements count] > 0];
    if ([WindowArrangements count] == 0) {
        [openArrangementAtStartup setState:NO];
    }
}

- (void)keyBindingsChanged
{
    [keyMappings reloadData];
}

- (void)rebuildColorPresetsMenu
{
    while ([presetsMenu numberOfItems] > 1) {
        [presetsMenu removeItemAtIndex:1];
    }

    NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"ColorPresets"
                                                                            ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    [self _addColorPresetsInDict:presetsDict toMenu:presetsMenu];

    NSDictionary* customPresets = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    if (customPresets && [customPresets count] > 0) {
        [presetsMenu addItem:[NSMenuItem separatorItem]];
        [self _addColorPresetsInDict:customPresets toMenu:presetsMenu];
    }

    [presetsMenu addItem:[NSMenuItem separatorItem]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Import..."
                                                     action:@selector(importColorPreset:)
                                              keyEquivalent:@""] autorelease]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Export..."
                                                     action:@selector(exportColorPreset:)
                                              keyEquivalent:@""] autorelease]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Delete Preset..."
                                                     action:@selector(deleteColorPreset:)
                                              keyEquivalent:@""] autorelease]];
    [presetsMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Visit Online Gallery"
                                                     action:@selector(visitGallery:)
                                              keyEquivalent:@""] autorelease]];
}

- (void)handleWindowWillCloseNotification:(NSNotification *)notification
{
    // This is so tags get saved because Cocoa doesn't notify you that the
    // field changed unless the user presses enter twice in it (!).
    [self bookmarkSettingChanged:nil];
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
    [self settingChanged:nil];
    [self savePreferences];
    self.currentProfileGuid = nil;

}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"nonTerminalWindowBecameKey"
                                                        object:nil
                                                      userInfo:nil];
}

#pragma mark - IBActions

- (IBAction)settingChanged:(id)sender
{
    if (sender == lionStyleFullscreen) {
        defaultLionStyleFullscreen = ([lionStyleFullscreen state] == NSOnState);
    } else if (sender == loadPrefsFromCustomFolder) {
        BOOL shouldLoadRemotePrefs = [loadPrefsFromCustomFolder state] == NSOnState;
        [[iTermRemotePreferences sharedInstance] setShouldLoadRemotePrefs:shouldLoadRemotePrefs];
        if (shouldLoadRemotePrefs) {
            // Just turned it on.
            if ([[prefsCustomFolder stringValue] length] == 0) {
                // Field was initially empty so browse for a dir.
                if ([self choosePrefsCustomFolder]) {
                    // User didn't hit cancel; if he chose a writable directory ask if he wants to write to it.
                    if ([[iTermRemotePreferences sharedInstance] remoteLocationIsValid]) {
                        if ([[NSAlert alertWithMessageText:@"Copy local preferences to custom folder now?"
                                             defaultButton:@"Copy"
                                           alternateButton:@"Don't Copy"
                                               otherButton:nil
                                 informativeTextWithFormat:@""] runModal] == NSOKButton) {
                            [self pushToCustomFolder:nil];
                        }
                    }
                }
            }
        }
        [prefsCustomFolder setEnabled:shouldLoadRemotePrefs];
        [browseCustomFolder setEnabled:shouldLoadRemotePrefs];
        [pushToCustomFolder setEnabled:shouldLoadRemotePrefs];
        [self _updatePrefsDirWarning];
    } else if (sender == prefsCustomFolder) {
        // The OS will never call us directly with this sender, but we do call ourselves this way.
        [[iTermRemotePreferences sharedInstance] setCustomFolderOrURL:[prefsCustomFolder stringValue]];
        customFolderChanged_ = YES;
        [self _updatePrefsDirWarning];
    } else if (sender == windowStyle ||
               sender == tabPosition ||
               sender == hideTab ||
               sender == hideTabCloseButton ||
               sender == hideTabNumber ||
               sender == hideActivityIndicator ||
               sender == highlightTabLabels ||
               sender == hideMenuBarInFullscreen ||
               sender == hideScrollbar ||
               sender == showPaneTitles ||
               sender == disableFullscreenTransparency ||
               sender == dimInactiveSplitPanes ||
               sender == dimBackgroundWindows ||
               sender == animateDimming ||
               sender == dimOnlyText ||
               sender == dimmingAmount ||
               sender == openTmuxWindows ||
               sender == threeFingerEmulatesMiddle ||
               sender == autoHideTmuxClientSession ||
               sender == showWindowBorder ||
               sender == hotkeyAutoHides) {
        defaultWindowStyle = [windowStyle indexOfSelectedItem];
        defaultOpenTmuxWindowsIn = [[openTmuxWindows selectedItem] tag];
        defaultAutoHideTmuxClientSession = ([autoHideTmuxClientSession state] == NSOnState);
        defaultTabViewType=[tabPosition indexOfSelectedItem];
        defaultHideTabCloseButton = ([hideTabCloseButton state] == NSOnState);
        defaultHideTabNumber = ([hideTabNumber state] == NSOnState);
        defaultHideActivityIndicator = ([hideActivityIndicator state] == NSOnState);
        defaultHighlightTabLabels = ([highlightTabLabels state] == NSOnState);
        defaultHideMenuBarInFullscreen = ([hideMenuBarInFullscreen state] == NSOnState);
        defaultShowPaneTitles = ([showPaneTitles state] == NSOnState);
        defaultHideTab = ([hideTab state] == NSOnState);
        defaultDimInactiveSplitPanes = ([dimInactiveSplitPanes state] == NSOnState);
        defaultDimBackgroundWindows = ([dimBackgroundWindows state] == NSOnState);
        defaultAnimateDimming= ([animateDimming state] == NSOnState);
        defaultDimOnlyText = ([dimOnlyText state] == NSOnState);
        defaultDimmingAmount = [dimmingAmount floatValue];
        defaultShowWindowBorder = ([showWindowBorder state] == NSOnState);
        defaultThreeFingerEmulatesMiddle=([threeFingerEmulatesMiddle state] == NSOnState);
        defaultHideScrollbar = ([hideScrollbar state] == NSOnState);
        defaultDisableFullscreenTransparency = ([disableFullscreenTransparency state] == NSOnState);
        defaultHotkeyAutoHides = ([hotkeyAutoHides state] == NSOnState);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermRefreshTerminal"
                                                            object:nil
                                                          userInfo:nil];
        if (sender == threeFingerEmulatesMiddle) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                                object:nil
                                                              userInfo:nil];
        }
    } else if (sender == windowNumber ||
               sender == jobName ||
               sender == showBookmarkName) {
        defaultWindowNumber = ([windowNumber state] == NSOnState);
        defaultJobName = ([jobName state] == NSOnState);
        defaultShowBookmarkName = ([showBookmarkName state] == NSOnState);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermUpdateLabels"
                                                            object:nil
                                                          userInfo:nil];
    } else if (sender == switchTabModifierButton ||
               sender == switchWindowModifierButton) {
        defaultSwitchTabModifier = [switchTabModifierButton selectedTag];
        defaultSwitchWindowModifier = [switchWindowModifierButton selectedTag];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermModifierChanged"
                                                            object:nil
                                                          userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                    [NSNumber numberWithInt:[self modifierTagToMask:defaultSwitchTabModifier]], @"TabModifier",
                                                                    [NSNumber numberWithInt:[self modifierTagToMask:defaultSwitchWindowModifier]], @"WindowModifier",
                                                                    nil, nil]];
    } else {
        if (sender == hotkeyTogglesWindow &&
            [hotkeyTogglesWindow state] == NSOnState &&
            ![[ProfileModel sharedInstance] bookmarkWithName:kHotkeyWindowGeneratedProfileNameKey]) {
            // User's turning on hotkey window. There is no bookmark with the autogenerated name.
            [self _generateHotkeyWindowProfile];
            [hotkeyBookmark selectItemWithTitle:kHotkeyWindowGeneratedProfileNameKey];
            NSRunAlertPanel(@"Set Up Hotkey Window",
                            @"A new profile called \"%@\" was created for you. It is tuned to work well"
                            @"for the Hotkey Window feature, but you can change it in the Profiles tab.",
                            @"OK",
                            nil,
                            nil,
                            kHotkeyWindowGeneratedProfileNameKey);
        }
        defaultFsTabDelay = [fsTabDelay floatValue];
        defaultAllowClipboardAccess = ([allowClipboardAccessFromTerminal state]==NSOnState);
        defaultCopySelection = ([selectionCopiesText state]==NSOnState);
        defaultCopyLastNewline = ([copyLastNewline state] == NSOnState);
        defaultPasteFromClipboard=([middleButtonPastesFromClipboard state]==NSOnState);
        defaultPromptOnQuit = ([promptOnQuit state] == NSOnState);
        defaultOnlyWhenMoreTabs = ([onlyWhenMoreTabs state] == NSOnState);
        defaultFocusFollowsMouse = ([focusFollowsMouse state] == NSOnState);
        defaultTripleClickSelectsFullLines = ([tripleClickSelectsFullLines state] == NSOnState);
        defaultHotkeyTogglesWindow = ([hotkeyTogglesWindow state] == NSOnState);
        [defaultHotKeyBookmarkGuid release];
        defaultHotKeyBookmarkGuid = [[[hotkeyBookmark selectedItem] representedObject] copy];
        BOOL bonjourBefore = defaultEnableBonjour;
        defaultEnableBonjour = ([enableBonjour state] == NSOnState);
        if (bonjourBefore != defaultEnableBonjour) {
            if (defaultEnableBonjour == YES) {
                [[ITAddressBookMgr sharedInstance] locateBonjourServices];
            } else {
                [[ITAddressBookMgr sharedInstance] stopLocatingBonjourServices];

                // Remove existing bookmarks with the "bonjour" tag. Even if
                // network browsing is re-enabled, these bookmarks would never
                // be automatically removed.
                ProfileModel* model = [ProfileModel sharedInstance];
                NSString* kBonjourTag = @"bonjour";
                int n = [model numberOfBookmarksWithFilter:kBonjourTag];
                for (int i = n - 1; i >= 0; --i) {
                    Profile* bookmark = [model profileAtIndex:i withFilter:kBonjourTag];
                    if ([model bookmark:bookmark hasTag:kBonjourTag]) {
                        [model removeBookmarkAtIndex:i withFilter:kBonjourTag];
                    }
                }
            }
        }

        defaultCmdSelection = ([cmdSelection state] == NSOnState);
        defaultOptionClickMovesCursor = ([optionClickMovesCursor state] == NSOnState);
        defaultPassOnControlLeftClick = ([controlLeftClickActsLikeRightClick state] == NSOffState);
        defaultMaxVertically = ([maxVertically state] == NSOnState);
        defaultOpenBookmark = ([openBookmark state] == NSOnState);
        [defaultWordChars release];
        defaultWordChars = [[wordChars stringValue] retain];
        defaultTmuxDashboardLimit = [[tmuxDashboardLimit stringValue] intValue];
        defaultQuitWhenAllWindowsClosed = ([quitWhenAllWindowsClosed state] == NSOnState);
        defaultCheckUpdate = ([checkUpdate state] == NSOnState);
        defaultSmartPlacement = ([smartPlacement state] == NSOnState);
        defaultAdjustWindowForFontSizeChange = ([adjustWindowForFontSizeChange state] == NSOnState);
        defaultSavePasteHistory = ([savePasteHistory state] == NSOnState);
        if (!defaultSavePasteHistory) {
            [[PasteboardHistory sharedInstance] eraseHistory];
        }
        defaultOpenArrangementAtStartup = ([openArrangementAtStartup state] == NSOnState);

        defaultIrMemory = [irMemory intValue];
        BOOL oldDefaultHotkey = defaultHotkey;
        defaultHotkey = ([hotkey state] == NSOnState);
        if (defaultHotkey != oldDefaultHotkey) {
            if (defaultHotkey) {
                // Hotkey was enabled but might be unassigned; give it a default value if needed.
                [self sanityCheckHotKey];
            } else {
                [[HotkeyWindowController sharedInstance] unregisterHotkey];
            }
        }
        [hotkeyField setEnabled:defaultHotkey];
        [hotkeyLabel setTextColor:defaultHotkey ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
        [hotkeyTogglesWindow setEnabled:defaultHotkey];
        [hotkeyAutoHides setEnabled:(defaultHotkey && defaultHotkeyTogglesWindow)];
        [hotkeyBookmark setEnabled:(defaultHotkey && defaultHotkeyTogglesWindow)];

        if (prefs &&
            defaultCheckTestRelease != ([checkTestRelease state] == NSOnState)) {
            defaultCheckTestRelease = ([checkTestRelease state] == NSOnState);

            NSString *appCast = defaultCheckTestRelease ?
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
            [prefs setObject:appCast forKey:@"SUFeedURL"];
        }
    }

    // Keyboard tab
    BOOL wasAnyModifierRemapped = [self isAnyModifierRemapped];
    defaultControl = [controlButton selectedTag];
    defaultLeftOption = [leftOptionButton selectedTag];
    defaultRightOption = [rightOptionButton selectedTag];
    defaultLeftCommand = [leftCommandButton selectedTag];
    defaultRightCommand = [rightCommandButton selectedTag];
    if ((!wasAnyModifierRemapped && [self isAnyModifierRemapped]) ||
        ([self isAnyModifierRemapped] && ![[HotkeyWindowController sharedInstance] haveEventTap])) {
        [[HotkeyWindowController sharedInstance] beginRemappingModifiers];
    }

    int rowIndex = [globalKeyMappings selectedRow];
    if (rowIndex >= 0) {
        [globalRemoveMappingButton setEnabled:YES];
    } else {
        [globalRemoveMappingButton setEnabled:NO];
    }
    [globalKeyMappings reloadData];
}

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

- (IBAction)copyToProfile:(id)sender
{
    NSString* sourceGuid = [bookmarksTableView selectedGuid];
    if (!sourceGuid) {
        return;
    }
    Profile* sourceBookmark = [dataSource bookmarkWithGuid:sourceGuid];
    NSString* profileGuid = [sourceBookmark objectForKey:KEY_ORIGINAL_GUID];
    Profile* destination = [[ProfileModel sharedInstance] bookmarkWithGuid:profileGuid];
    // TODO: changing color presets in cmd-i causes profileGuid=null.
    if (sourceBookmark && destination) {
        NSMutableDictionary* copyOfSource = [[sourceBookmark mutableCopy] autorelease];
        [copyOfSource setObject:profileGuid forKey:KEY_GUID];
        [copyOfSource removeObjectForKey:KEY_ORIGINAL_GUID];
        [copyOfSource setObject:[destination objectForKey:KEY_NAME] forKey:KEY_NAME];
        [[ProfileModel sharedInstance] setBookmark:copyOfSource withGuid:profileGuid];

        [[PreferencePanel sharedInstance] profileTableSelectionDidChange:[PreferencePanel sharedInstance]->bookmarksTableView];

        // Update existing sessions
        int n = [[iTermController sharedInstance] numberOfTerminals];
        for (int i = 0; i < n; ++i) {
            PseudoTerminal* pty = [[iTermController sharedInstance] terminalAtIndex:i];
            [pty reloadBookmarks];
        }

        // Update user defaults
        [[NSUserDefaults standardUserDefaults] setObject:[[ProfileModel sharedInstance] rawData]
                                                  forKey: @"New Bookmarks"];
    }
}

- (IBAction)browseCustomFolder:(id)sender
{
    [self choosePrefsCustomFolder];
}

- (IBAction)pushToCustomFolder:(id)sender
{
    [self savePreferences];
    [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
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
    NSString* name = [bookmarkName stringValue];
    NSString* shortcut = [self shortcutKeyForTag:[[bookmarkShortcutKey selectedItem] tag]];
    NSString* command = [bookmarkCommand stringValue];
    NSString *text = [initialText stringValue];
    if (!text) {
        text = @"";
    }
    NSString* dir = [bookmarkDirectory stringValue];

    NSString* customCommand = [[bookmarkCommandType selectedCell] tag] == 0 ? @"Yes" : @"No";
    NSString* customDir;
    switch ([[bookmarkDirectoryType selectedCell] tag]) {
        case 0:
            customDir = @"Yes";
            break;

        case 2:
            customDir = @"Recycle";
            break;

        case 3:
            customDir = @"Advanced";
            break;

        case 1:
        default:
            customDir = @"No";
            break;
    }
    [editAdvancedConfigButton setEnabled:[customDir isEqualToString:@"Advanced"]];

    if (sender == optionKeySends && [[optionKeySends selectedCell] tag] == OPT_META) {
        [self _maybeWarnAboutMeta];
    } else if (sender == rightOptionKeySends && [[rightOptionKeySends selectedCell] tag] == OPT_META) {
        [self _maybeWarnAboutMeta];
    }
    if (sender == spaceButton && [spaceButton selectedTag] > 0) {
        [self _maybeWarnAboutSpaces];
    }
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Profile* origBookmark = [dataSource bookmarkWithGuid:guid];
    if (!origBookmark) {
        return;
    }
    NSMutableDictionary* newDict = [[NSMutableDictionary alloc] init];
    [newDict autorelease];
    NSString* isDefault = [origBookmark objectForKey:KEY_DEFAULT_BOOKMARK];
    if (!isDefault) {
        isDefault = @"No";
    }
    [newDict setObject:isDefault forKey:KEY_DEFAULT_BOOKMARK];
    [newDict setObject:name forKey:KEY_NAME];
    [newDict setObject:guid forKey:KEY_GUID];
    NSString* origGuid = [origBookmark objectForKey:KEY_ORIGINAL_GUID];
    if (origGuid) {
        [newDict setObject:origGuid forKey:KEY_ORIGINAL_GUID];
    }
    if (shortcut) {
        // If any bookmark has this shortcut, clear its shortcut.
        for (int i = 0; i < [dataSource numberOfBookmarks]; ++i) {
            Profile* temp = [dataSource profileAtIndex:i];
            NSString* existingShortcut = [temp objectForKey:KEY_SHORTCUT];
            if ([shortcut length] > 0 &&
                [existingShortcut isEqualToString:shortcut] &&
                temp != origBookmark) {
                [dataSource setObject:nil forKey:KEY_SHORTCUT inBookmark:temp];
            }
        }

        [newDict setObject:shortcut forKey:KEY_SHORTCUT];
    }
    [newDict setObject:command forKey:KEY_COMMAND];
    [newDict setObject:text forKey:KEY_INITIAL_TEXT];
    [newDict setObject:dir forKey:KEY_WORKING_DIRECTORY];
    [newDict setObject:customCommand forKey:KEY_CUSTOM_COMMAND];
    [newDict setObject:customDir forKey:KEY_CUSTOM_DIRECTORY];

    // Just copy over advanced working dir settings
    NSArray *valuesToCopy = [NSArray arrayWithObjects:
                             KEY_AWDS_WIN_OPTION,
                             KEY_AWDS_WIN_DIRECTORY,
                             KEY_AWDS_TAB_OPTION,
                             KEY_AWDS_TAB_DIRECTORY,
                             KEY_AWDS_PANE_OPTION,
                             KEY_AWDS_PANE_DIRECTORY,
                             nil];
    for (NSString *key in valuesToCopy) {
        id value = [origBookmark objectForKey:key];
        if (value) {
            [newDict setObject:value forKey:key];
        }
    }

    // Colors tab
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi0Color color]] forKey:KEY_ANSI_0_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi1Color color]] forKey:KEY_ANSI_1_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi2Color color]] forKey:KEY_ANSI_2_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi3Color color]] forKey:KEY_ANSI_3_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi4Color color]] forKey:KEY_ANSI_4_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi5Color color]] forKey:KEY_ANSI_5_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi6Color color]] forKey:KEY_ANSI_6_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi7Color color]] forKey:KEY_ANSI_7_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi8Color color]] forKey:KEY_ANSI_8_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi9Color color]] forKey:KEY_ANSI_9_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi10Color color]] forKey:KEY_ANSI_10_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi11Color color]] forKey:KEY_ANSI_11_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi12Color color]] forKey:KEY_ANSI_12_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi13Color color]] forKey:KEY_ANSI_13_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi14Color color]] forKey:KEY_ANSI_14_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[ansi15Color color]] forKey:KEY_ANSI_15_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[foregroundColor color]] forKey:KEY_FOREGROUND_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[backgroundColor color]] forKey:KEY_BACKGROUND_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[boldColor color]] forKey:KEY_BOLD_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[selectionColor color]] forKey:KEY_SELECTION_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[selectedTextColor color]] forKey:KEY_SELECTED_TEXT_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[cursorColor color]] forKey:KEY_CURSOR_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[cursorTextColor color]] forKey:KEY_CURSOR_TEXT_COLOR];
    [newDict setObject:[ITAddressBookMgr encodeColor:[tabColor color]] forKey:KEY_TAB_COLOR];
    [newDict setObject:[NSNumber numberWithBool:[useTabColor state]] forKey:KEY_USE_TAB_COLOR];
    [newDict setObject:[NSNumber numberWithBool:[checkColorInvertedCursor state]] forKey:KEY_SMART_CURSOR_COLOR];
    [newDict setObject:[NSNumber numberWithFloat:[minimumContrast floatValue]] forKey:KEY_MINIMUM_CONTRAST];

    [tabColor setEnabled:[useTabColor state] == NSOnState];
    [cursorColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

    [cursorTextColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorTextColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

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
    [newDict setObject:[NSNumber numberWithBool:([blinkingCursor state]==NSOnState)] forKey:KEY_BLINKING_CURSOR];
    [newDict setObject:[NSNumber numberWithBool:([blinkAllowed state]==NSOnState)] forKey:KEY_BLINK_ALLOWED];
    [newDict setObject:[NSNumber numberWithInt:[[cursorType selectedCell] tag]] forKey:KEY_CURSOR_TYPE];
    [newDict setObject:[NSNumber numberWithBool:([useBoldFont state]==NSOnState)] forKey:KEY_USE_BOLD_FONT];
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
    [self _updatePrefsDirWarning];
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
    [newDict setObject:[tags objectValue] forKey:KEY_TAGS];

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
    [dataSource setBookmark:newDict withGuid:guid];
    [bookmarksTableView reloadData];
    if (reloadKeyMappings) {
        [keyMappings reloadData];
    }

    // Selectively update form fields.
    [self updateShortcutTitles];

    // Update existing sessions
    int n = [[iTermController sharedInstance] numberOfTerminals];
    for (int i = 0; i < n; ++i) {
        PseudoTerminal* pty = [[iTermController sharedInstance] terminalAtIndex:i];
        [pty reloadBookmarks];
    }
    if (prefs) {
        [prefs setObject:[dataSource rawData] forKey:@"New Bookmarks"];
    }
}

- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme
{
    NSURL *appURL = nil;
    OSStatus err;
    BOOL set = YES;

    err = LSGetApplicationForURL(
                                 (CFURLRef)[NSURL URLWithString:[scheme stringByAppendingString:@":"]],
                                 kLSRolesAll, NULL, (CFURLRef *)&appURL);
    if (err != noErr) {
        set = NSRunAlertPanel([NSString stringWithFormat:@"iTerm is not the default handler for %@. Would you like to set iTerm as the default handler?",
                               scheme],
                              @"There is currently no handler.",
                              @"OK",
                              @"Cancel",
                              nil) == NSAlertDefaultReturn;
    } else if (![[[NSFileManager defaultManager] displayNameAtPath:[appURL path]] isEqualToString:@"iTerm 2"]) {
        NSString *theTitle = [NSString stringWithFormat:@"iTerm is not the default handler for %@. "
                              @"Would you like to set iTerm as the default handler?", scheme];
        set = NSRunAlertPanel(theTitle,
                              @"The current handler is: %@",
                              @"OK",
                              @"Cancel",
                              nil,
                              [[NSFileManager defaultManager] displayNameAtPath:[appURL path]]) == NSAlertDefaultReturn;
    }

    if (set) {
        [urlHandlersByGuid setObject:guid
                              forKey:scheme];
        LSSetDefaultHandlerForURLScheme((CFStringRef)scheme,
                                        (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
    }
}

- (IBAction)bookmarkUrlSchemeHandlerChanged:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSString* scheme = [[bookmarkUrlSchemes selectedItem] title];
    if ([urlHandlersByGuid objectForKey:scheme]) {
        [self disconnectHandlerForScheme:scheme];
    } else {
        [self connectBookmarkWithGuid:guid toScheme:scheme];
    }
    [self _populateBookmarkUrlSchemesFromDict:[dataSource bookmarkWithGuid:guid]];
}

- (IBAction)addJob:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
    NSMutableArray *augmented;
    if (jobNames) {
        augmented = [NSMutableArray arrayWithArray:jobNames];
        [augmented addObject:@"Job Name"];
    } else {
        augmented = [NSMutableArray arrayWithObject:@"Job Name"];
    }
    [dataSource setObject:augmented forKey:KEY_JOBS inBookmark:bookmark];
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
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
    NSMutableArray *mod = [NSMutableArray arrayWithArray:jobNames];
    [mod removeObjectAtIndex:selectedIndex];

    [dataSource setObject:mod forKey:KEY_JOBS inBookmark:bookmark];
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

- (IBAction)actionChanged:(id)sender
{
    [action setTitle:[[sender selectedItem] title]];
    [PreferencePanel populatePopUpButtonWithBookmarks:bookmarkPopupButton
                                         selectedGuid:[[bookmarkPopupButton selectedItem] representedObject]];
    [PreferencePanel populatePopUpButtonWithMenuItems:menuToSelect
                                        selectedValue:[[menuToSelect selectedItem] title]];
    [self updateValueToSend];
}

// Replace a Profile in the sessions profile with a new dictionary that preserves the original
// name and guid, takes all other fields from |bookmark|, and has KEY_ORIGINAL_GUID point at the
// guid of the profile from which all that data came.n
- (IBAction)changeProfile:(id)sender
{
    NSString *guid = [setProfileBookmarkListView selectedGuid];
    if (guid) {
        NSString* origGuid = [bookmarksTableView selectedGuid];
        Profile* origBookmark = [dataSource bookmarkWithGuid:origGuid];
        NSString *theName = [[[origBookmark objectForKey:KEY_NAME] copy] autorelease];
        Profile *bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
        [dict setObject:theName forKey:KEY_NAME];
        [dict setObject:origGuid forKey:KEY_GUID];

        // Change the dict in the sessions bookmarks so that if you copy it back, it gets copied to
        // the new profile.
        [dict setObject:guid forKey:KEY_ORIGINAL_GUID];
        [dataSource setBookmark:dict withGuid:origGuid];

        [self updateBookmarkFields:dict];
        [self bookmarkSettingChanged:nil];
    }
}

- (IBAction)addNewMapping:(id)sender
{
    [self _addMappingWithContextInfo:sender];
}

- (IBAction)removeMapping:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    NSMutableDictionary* tempDict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
    NSAssert(tempDict, @"Can't find node");
    [iTermKeyBindingMgr removeMappingAtIndex:[keyMappings selectedRow] inBookmark:tempDict];
    [dataSource setBookmark:tempDict withGuid:guid];
    [keyMappings reloadData];
}

- (IBAction)globalRemoveMapping:(id)sender
{
    [iTermKeyBindingMgr setGlobalKeyMap:[iTermKeyBindingMgr removeMappingAtIndex:[globalKeyMappings selectedRow]
                                                                    inDictionary:[iTermKeyBindingMgr globalKeyMap]]];
    [self settingChanged:nil];
    [keyMappings reloadData];
}

- (IBAction)toggleTags:(id)sender {
    [bookmarksTableView toggleTags];
}

- (void)profileTableTagsVisibilityDidChange:(ProfileListView *)profileListView {
    [toggleTagsButton setTitle:profileListView.tagsVisible ? @"< Tags" : @"Tags >"];
}

- (IBAction)addBookmark:(id)sender
{
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] init] autorelease];
    // Copy the default bookmark's settings in
    Profile* prototype = [dataSource defaultBookmark];
    if (!prototype) {
        [ITAddressBookMgr setDefaultsInBookmark:newDict];
    } else {
        [newDict setValuesForKeysWithDictionary:[dataSource defaultBookmark]];
    }
    [newDict setObject:@"New Profile" forKey:KEY_NAME];
    [newDict setObject:@"" forKey:KEY_SHORTCUT];
    NSString* guid = [ProfileModel freshGuid];
    [newDict setObject:guid forKey:KEY_GUID];
    [newDict removeObjectForKey:KEY_DEFAULT_BOOKMARK];  // remove depreated attribute with side effects
    [newDict setObject:[NSArray arrayWithObjects:nil] forKey:KEY_TAGS];
    if ([[ProfileModel sharedInstance] bookmark:newDict hasTag:@"bonjour"]) {
        [newDict removeObjectForKey:KEY_BONJOUR_GROUP];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE_ADDRESS];
        [newDict setObject:@"" forKey:KEY_COMMAND];
        [newDict setObject:@"" forKey:KEY_INITIAL_TEXT];
        [newDict setObject:@"No" forKey:KEY_CUSTOM_COMMAND];
        [newDict setObject:@"" forKey:KEY_WORKING_DIRECTORY];
        [newDict setObject:@"No" forKey:KEY_CUSTOM_DIRECTORY];
    }
    [dataSource addBookmark:newDict];
    [bookmarksTableView reloadData];
    [bookmarksTableView eraseQuery];
    [bookmarksTableView selectRowByGuid:guid];
    [bookmarksSettingsTabViewParent selectTabViewItem:bookmarkSettingsGeneralTab];
    [[self window] makeFirstResponder:bookmarkName];
    [bookmarkName selectText:self];
}

- (IBAction)removeBookmark:(id)sender
{
    if ([dataSource numberOfBookmarks] == 1) {
        NSBeep();
    } else {
        if ([self confirmProfileDeletion:[[bookmarksTableView selectedGuids] allObjects]]) {
            BOOL found = NO;
            int lastIndex = 0;
            int numRemoved = 0;
            for (NSString* guid in [bookmarksTableView selectedGuids]) {
                found = YES;
                int i = [bookmarksTableView selectedRow];
                if (i > lastIndex) {
                    lastIndex = i;
                }
                ++numRemoved;
                [self _removeKeyMappingsReferringToBookmarkGuid:guid];
                [dataSource removeBookmarkWithGuid:guid];
            }
            [bookmarksTableView reloadData];
            int toSelect = lastIndex - numRemoved;
            if (toSelect < 0) {
                toSelect = 0;
            }
            [bookmarksTableView selectRowIndex:toSelect];
            if (!found) {
                NSBeep();
            }
        }
    }
}

- (IBAction)setAsDefault:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    [dataSource setDefaultByGuid:guid];
}

- (IBAction)duplicateBookmark:(id)sender
{
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        NSBeep();
        return;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    NSString* newName = [NSString stringWithFormat:@"Copy of %@", [newDict objectForKey:KEY_NAME]];

    [newDict setObject:newName forKey:KEY_NAME];
    [newDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    [newDict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [newDict setObject:@"" forKey:KEY_SHORTCUT];
    [dataSource addBookmark:newDict];
    [bookmarksTableView reloadData];
    [bookmarksTableView selectRowByGuid:[newDict objectForKey:KEY_GUID]];
}

- (IBAction)openCopyBookmarks:(id)sender
{
    [bulkCopyLabel setStringValue:[NSString stringWithFormat:
                                   @"Copy these settings from profile \"%@\":",
                                   [[dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]] objectForKey:KEY_NAME]]];
    [NSApp beginSheet:copyPanel
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (IBAction)copyBookmarks:(id)sender
{
    NSString* srcGuid = [bookmarksTableView selectedGuid];
    if (!srcGuid) {
        NSBeep();
        return;
    }

    NSSet* destGuids = [copyTo selectedGuids];
    for (NSString* destGuid in destGuids) {
        if ([destGuid isEqualToString:srcGuid]) {
            continue;
        }

        if (![dataSource bookmarkWithGuid:destGuid]) {
            NSLog(@"Selected bookmark %@ doesn't exist", destGuid);
            continue;
        }

        if ([copyColors state] == NSOnState) {
            [self copyAttributes:BulkCopyColors fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyDisplay state] == NSOnState) {
            [self copyAttributes:BulkCopyDisplay fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyWindow state] == NSOnState) {
            [self copyAttributes:BulkCopyWindow fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyTerminal state] == NSOnState) {
            [self copyAttributes:BulkCopyTerminal fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyKeyboard state] == NSOnState) {
            [self copyAttributes:BulkCopyKeyboard fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copySession state] == NSOnState) {
            [self copyAttributes:BulkCopySession fromBookmark:srcGuid toBookmark:destGuid];
        }
        if ([copyAdvanced state] == NSOnState) {
            [self copyAttributes:BulkCopyAdvanced fromBookmark:srcGuid toBookmark:destGuid];
        }
    }
    [NSApp endSheet:copyPanel];
}

- (IBAction)cancelCopyBookmarks:(id)sender
{
    [NSApp endSheet:copyPanel];
}

#pragma mark - Color Presets

- (void)_addColorPresetsInDict:(NSDictionary*)presetsDict toMenu:(NSMenu*)theMenu
{
    for (NSString* key in  [[presetsDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSMenuItem* presetItem = [[NSMenuItem alloc] initWithTitle:key action:@selector(loadColorPreset:) keyEquivalent:@""];
        [theMenu addItem:presetItem];
        [presetItem release];
    }
}

- (void)_addColorPreset:(NSString*)presetName withColors:(NSDictionary*)theDict
{
    NSMutableDictionary* customPresets = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey]];
    if (!customPresets) {
        customPresets = [NSMutableDictionary dictionaryWithCapacity:1];
    }
    int i = 1;
    NSString* temp = presetName;
    while ([customPresets objectForKey:temp]) {
        ++i;
        temp = [NSString stringWithFormat:@"%@ (%d)", presetName, i];
    }
    [customPresets setObject:theDict forKey:temp];
    [[NSUserDefaults standardUserDefaults] setObject:customPresets forKey:kCustomColorPresetsKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:kRebuildColorPresetsMenuNotification
                                                        object:nil];
}

- (NSString*)_presetNameFromFilename:(NSString*)filename
{
    return [[filename stringByDeletingPathExtension] lastPathComponent];
}

- (BOOL)importColorPresetFromFile:(NSString*)filename
{
    NSDictionary* aDict = [NSDictionary dictionaryWithContentsOfFile:filename];
    if (!aDict) {
        NSRunAlertPanel(@"Import Failed.",
                        @"The selected file could not be read or did not contain a valid color scheme.",
                        @"OK",
                        nil,
                        nil);
        return NO;
    } else {
        [self _addColorPreset:[self _presetNameFromFilename:filename]
                   withColors:aDict];
        return YES;
    }
}

- (void)importColorPreset:(id)sender
{
    // Create the File Open Dialog class.
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];

    // Set options.
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:NO];
    [openDlg setAllowsMultipleSelection:YES];
    [openDlg setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    // Display the dialog.  If the OK button was pressed,
    // process the files.
    if ([openDlg legacyRunModalForDirectory:nil file:nil] == NSOKButton) {
        // Get an array containing the full filenames of all
        // files and directories selected.
        for (NSString* filename in [openDlg legacyFilenames]) {
            [self importColorPresetFromFile:filename];
        }
    }
}

- (void)_exportColorPresetToFile:(NSString*)filename
{
    NSArray* colorKeys = @[ KEY_ANSI_0_COLOR,
                            KEY_ANSI_1_COLOR,
                            KEY_ANSI_2_COLOR,
                            KEY_ANSI_3_COLOR,
                            KEY_ANSI_4_COLOR,
                            KEY_ANSI_5_COLOR,
                            KEY_ANSI_6_COLOR,
                            KEY_ANSI_7_COLOR,
                            KEY_ANSI_8_COLOR,
                            KEY_ANSI_9_COLOR,
                            KEY_ANSI_10_COLOR,
                            KEY_ANSI_11_COLOR,
                            KEY_ANSI_12_COLOR,
                            KEY_ANSI_13_COLOR,
                            KEY_ANSI_14_COLOR,
                            KEY_ANSI_15_COLOR,
                            KEY_FOREGROUND_COLOR,
                            KEY_BACKGROUND_COLOR,
                            KEY_BOLD_COLOR,
                            KEY_SELECTION_COLOR,
                            KEY_SELECTED_TEXT_COLOR,
                            KEY_CURSOR_COLOR,
                            KEY_CURSOR_TEXT_COLOR,
                            KEY_TAB_COLOR ];
    NSColorWell* wells[] = {
        ansi0Color,
        ansi1Color,
        ansi2Color,
        ansi3Color,
        ansi4Color,
        ansi5Color,
        ansi6Color,
        ansi7Color,
        ansi8Color,
        ansi9Color,
        ansi10Color,
        ansi11Color,
        ansi12Color,
        ansi13Color,
        ansi14Color,
        ansi15Color,
        foregroundColor,
        backgroundColor,
        boldColor,
        selectionColor,
        selectedTextColor,
        cursorColor,
        cursorTextColor,
        tabColor
    };
    NSMutableDictionary* theDict = [NSMutableDictionary dictionaryWithCapacity:24];
    int i = 0;
    for (NSString* colorKey in colorKeys) {
        [theDict setObject:[ITAddressBookMgr encodeColor:[wells[i++] color]] forKey:colorKey];
    }
    if (![theDict writeToFile:filename atomically:NO]) {
        NSRunAlertPanel(@"Save Failed.",
                        @"Could not save to %@",
                        @"OK",
                        nil,
                        nil,
                        filename);
    }
}

- (void)exportColorPreset:(id)sender
{
    // Create the File Open Dialog class.
    NSSavePanel* saveDlg = [NSSavePanel savePanel];

    // Set options.
    [saveDlg setAllowedFileTypes:[NSArray arrayWithObject:@"itermcolors"]];

    if ([saveDlg legacyRunModalForDirectory:nil file:nil] == NSOKButton) {
        [self _exportColorPresetToFile:[saveDlg legacyFilename]];
    }
}

- (void)deleteColorPreset:(id)sender
{
    NSDictionary* customPresets = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
    if (!customPresets || [customPresets count] == 0) {
        NSRunAlertPanel(@"No deletable color presets.",
                        @"You cannot erase the built-in presets and no custom presets have been imported.",
                        @"OK",
                        nil,
                        nil);
        return;
    }

    NSAlert *alert = [NSAlert alertWithMessageText:@"Select a preset to delete:"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@""];

    NSPopUpButton* pub = [[[NSPopUpButton alloc] init] autorelease];
    for (NSString* key in [[customPresets allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [pub addItemWithTitle:key];
    }
    [pub sizeToFit];
    [alert setAccessoryView:pub];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        NSMutableDictionary* newCustom = [NSMutableDictionary dictionaryWithDictionary:customPresets];
        [newCustom removeObjectForKey:[[pub selectedItem] title]];
        [[NSUserDefaults standardUserDefaults] setObject:newCustom
                                                  forKey:kCustomColorPresetsKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:kRebuildColorPresetsMenuNotification
                                                            object:nil];
    }
}

- (void)visitGallery:(id)sender
{
    static NSString * const kColorGalleryURL = @"http://www.iterm2.com/colorgallery";
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:kColorGalleryURL]];
}

- (void)_loadPresetColors:(NSString*)presetName
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");

    NSString* plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"ColorPresets"
                                                                            ofType:@"plist"];
    NSDictionary* presetsDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
    NSDictionary* settings = [presetsDict objectForKey:presetName];
    if (!settings) {
        presetsDict = [[NSUserDefaults standardUserDefaults] objectForKey:kCustomColorPresetsKey];
        settings = [presetsDict objectForKey:presetName];
    }
    NSMutableDictionary* newDict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];

    for (id colorName in settings) {
        NSDictionary* preset = [settings objectForKey:colorName];
        NSColor* color = [ITAddressBookMgr decodeColor:preset];
        NSAssert([newDict objectForKey:colorName], @"Missing color in existing dict");
        [newDict setObject:[ITAddressBookMgr encodeColor:color] forKey:colorName];
    }

    [dataSource setBookmark:newDict withGuid:guid];
    [self updateBookmarkFields:newDict];
    [self bookmarkSettingChanged:self];  // this causes existing sessions to be updated
}

- (void)loadColorPreset:(id)sender
{
    [self _loadPresetColors:[sender title]];
}

#pragma mark - Preferences folder

- (void)_updatePrefsDirWarning
{
    [prefsDirWarning setHidden:[[iTermRemotePreferences sharedInstance] remoteLocationIsValid]];
}

- (BOOL)customFolderChanged
{
    return customFolderChanged_;
}

- (BOOL)choosePrefsCustomFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSOKButton) {
        [prefsCustomFolder setStringValue:[panel legacyDirectory]];
        [self settingChanged:prefsCustomFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (BOOL)remoteLocationIsValid {
    if (![[iTermRemotePreferences sharedInstance] shouldLoadRemotePrefs]) {
        return YES;
    }
    return [[iTermRemotePreferences sharedInstance] remoteLocationIsValid];
}

#pragma mark - Sheet handling
- (void)genericCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [action setTitle:@"Ignore"];
    [sheet close];
}

#pragma mark - Advanced working dir prefs

- (void)safelySetStringValue:(NSString *)value in:(NSTextField *)field
{
    if (value) {
        [field setStringValue:value];
    } else {
        [field setStringValue:@""];
    }
}

- (void)setAdvancedBookmarkMatrix:(NSMatrix *)matrix withValue:(NSString *)value
{
    if ([value isEqualToString:@"Yes"]) {
        [matrix selectCellWithTag:0];
    } else if ([value isEqualToString:@"Recycle"]) {
        [matrix selectCellWithTag:2];
    } else {
        [matrix selectCellWithTag:1];
    }
}

- (IBAction)showAdvancedWorkingDirConfigPanel:(id)sender
{
    // Populate initial values
    Profile* bookmark = [dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]];

    [self setAdvancedBookmarkMatrix:awdsWindowDirectoryType
                          withValue:[bookmark objectForKey:KEY_AWDS_WIN_OPTION]];
    [self safelySetStringValue:[bookmark objectForKey:KEY_AWDS_WIN_DIRECTORY]
                            in:awdsWindowDirectory];

    [self setAdvancedBookmarkMatrix:awdsTabDirectoryType
                          withValue:[bookmark objectForKey:KEY_AWDS_TAB_OPTION]];
    [self safelySetStringValue:[bookmark objectForKey:KEY_AWDS_TAB_DIRECTORY]
                            in:awdsTabDirectory];

    [self setAdvancedBookmarkMatrix:awdsPaneDirectoryType
                          withValue:[bookmark objectForKey:KEY_AWDS_PANE_OPTION]];
    [self safelySetStringValue:[bookmark objectForKey:KEY_AWDS_PANE_DIRECTORY]
                            in:awdsPaneDirectory];


    [NSApp beginSheet:advancedWorkingDirSheet_
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(advancedWorkingDirSheetClosed:returnCode:contextInfo:)
          contextInfo:nil];
}

- (void)setValueInBookmark:(NSMutableDictionary *)dict
        forAdvancedWorkingDirMatrix:(NSMatrix *)matrix
        key:(NSString *)key
{
    NSString *value;
    NSString *values[] = { @"Yes", @"No", @"Recycle" };
    value = values[matrix.selectedTag];
    [dict setObject:value forKey:key];
}

- (IBAction)closeAdvancedWorkingDirSheet:(id)sender
{
    Profile* bookmark = [dataSource bookmarkWithGuid:[bookmarksTableView selectedGuid]];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:bookmark];
    [self setValueInBookmark:dict
          forAdvancedWorkingDirMatrix:awdsWindowDirectoryType
          key:KEY_AWDS_WIN_OPTION];
    [dict setObject:[awdsWindowDirectory stringValue] forKey:KEY_AWDS_WIN_DIRECTORY];

    [self setValueInBookmark:dict
          forAdvancedWorkingDirMatrix:awdsTabDirectoryType
          key:KEY_AWDS_TAB_OPTION];
    [dict setObject:[awdsTabDirectory stringValue] forKey:KEY_AWDS_TAB_DIRECTORY];

    [self setValueInBookmark:dict
          forAdvancedWorkingDirMatrix:awdsPaneDirectoryType
          key:KEY_AWDS_PANE_OPTION];
    [dict setObject:[awdsPaneDirectory stringValue] forKey:KEY_AWDS_PANE_DIRECTORY];

    [dataSource setBookmark:dict withGuid:[bookmark objectForKey:KEY_GUID]];
    [self bookmarkSettingChanged:nil];

    [NSApp endSheet:advancedWorkingDirSheet_];
}

- (void)advancedWorkingDirSheetClosed:(NSWindow *)sheet
                           returnCode:(int)returnCode
                          contextInfo:(void *)contextInfo
{
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

+ (void)populatePopUpButtonWithBookmarks:(NSPopUpButton*)button selectedGuid:(NSString*)selectedGuid
{
    int selectedIndex = 0;
    int i = 0;
    [button removeAllItems];
    NSArray* bookmarks = [[ProfileModel sharedInstance] bookmarks];
    for (Profile* bookmark in bookmarks) {
        int j = 0;
        NSString* temp;
        do {
            if (j == 0) {
                temp = [bookmark objectForKey:KEY_NAME];
            } else {
                temp = [NSString stringWithFormat:@"%@ (%d)", [bookmark objectForKey:KEY_NAME], j];
            }
            j++;
        } while ([button indexOfItemWithTitle:temp] != -1);
        [button addItemWithTitle:temp];
        NSMenuItem* item = [button lastItem];
        [item setRepresentedObject:[bookmark objectForKey:KEY_GUID]];
        if ([[item representedObject] isEqualToString:selectedGuid]) {
            selectedIndex = i;
        }
        i++;
    }
    [button selectItemAtIndex:selectedIndex];
}

+ (void)recursiveAddMenu:(NSMenu *)menu
            toButtonMenu:(NSMenu *)buttonMenu
                   depth:(int)depth{
    for (NSMenuItem* item in [menu itemArray]) {
        if ([item isSeparatorItem]) {
            continue;
        }
        if ([[item title] isEqualToString:@"Services"] ||  // exclude services menu
            isnumber([[item title] characterAtIndex:0])) {  // exclude windows in window menu
            continue;
        }
        NSMenuItem *theItem = [[[NSMenuItem alloc] init] autorelease];
        [theItem setTitle:[item title]];
        [theItem setIndentationLevel:depth];
        if ([item hasSubmenu]) {
            if (depth == 0 && [[buttonMenu itemArray] count]) {
                [buttonMenu addItem:[NSMenuItem separatorItem]];
            }
            [theItem setEnabled:NO];
            [buttonMenu addItem:theItem];
            [PreferencePanel recursiveAddMenu:[item submenu]
                                 toButtonMenu:buttonMenu
                                        depth:depth + 1];
        } else {
            [buttonMenu addItem:theItem];
        }
    }
}

+ (void)populatePopUpButtonWithMenuItems:(NSPopUpButton *)button
                           selectedValue:(NSString *)selectedValue {
    [PreferencePanel recursiveAddMenu:[NSApp mainMenu]
                         toButtonMenu:[button menu]
                                depth:0];
    if (selectedValue) {
        NSMenuItem *theItem = [[button menu] itemWithTitle:selectedValue];
        if (theItem) {
            [button setTitle:selectedValue];
            [theItem setState:NSOnState];
        }
    }
}

#pragma mark - Key mappings

- (BOOL)_originatorIsBookmark:(id)originator
{
    return originator == addNewMapping || originator == keyMappings;
}

- (NSString*)keyComboAtIndex:(int)rowIndex originator:(id)originator
{
    if ([self _originatorIsBookmark:originator]) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");
        return [iTermKeyBindingMgr shortcutAtIndex:rowIndex forBookmark:bookmark];
    } else {
        return [iTermKeyBindingMgr globalShortcutAtIndex:rowIndex];
    }
}

- (NSDictionary*)keyInfoAtIndex:(int)rowIndex originator:(id)originator
{
    if ([self _originatorIsBookmark:originator]) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");
        return [iTermKeyBindingMgr mappingAtIndex:rowIndex forBookmark:bookmark];
    } else {
        return [iTermKeyBindingMgr globalMappingAtIndex:rowIndex];
    }
}

- (NSString*)formattedKeyCombinationForRow:(int)rowIndex originator:(id)originator
{
    return [iTermKeyBindingMgr formatKeyCombination:[self keyComboAtIndex:rowIndex
                                                               originator:originator]];
}

- (NSString*)formattedActionForRow:(int)rowIndex originator:(id)originator
{
    return [iTermKeyBindingMgr formatAction:[self keyInfoAtIndex:rowIndex originator:originator]];
}

- (void)editKeyMapping:(id)sender
{
    int rowIndex;
    modifyMappingOriginator = sender;
    if ([self _originatorIsBookmark:sender]) {
        rowIndex = [keyMappings selectedRow];
    } else {
        rowIndex = [globalKeyMappings selectedRow];
    }
    if (rowIndex < 0) {
        [self addNewMapping:sender];
        return;
    }
    [keyPress setStringValue:[self formattedKeyCombinationForRow:rowIndex originator:sender]];
    if (keyString) {
        [keyString release];
    }
    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    for (NSMenuItem* item in [action itemArray]) {
        [item setState:NSOffState];
    }
    keyString = [[self keyComboAtIndex:rowIndex originator:sender] copy];
    int theTag = [[[self keyInfoAtIndex:rowIndex originator:sender] objectForKey:@"Action"] intValue];
    [action selectItemWithTag:theTag];
    // Can't search for an item with tag 0 using the API, so search manually.
    for (NSMenuItem* anItem in [[action menu] itemArray]) {
        if (![anItem isSeparatorItem] && [anItem tag] == theTag) {
            [action setTitle:[anItem title]];
            break;
        }
    }
    NSString* text = [[self keyInfoAtIndex:rowIndex originator:sender] objectForKey:@"Text"];
    [valueToSend setStringValue:text ? text : @""];
    [PreferencePanel populatePopUpButtonWithBookmarks:bookmarkPopupButton
                                         selectedGuid:text];
    [PreferencePanel populatePopUpButtonWithMenuItems:menuToSelect
                                         selectedValue:text];
    [self updateValueToSend];
    newMapping = NO;
    [NSApp beginSheet:editKeyMappingWindow
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:nil];
}

- (NSWindow*)keySheet
{
    return editKeyMappingWindow;
}


- (BOOL)_anyBookmarkHasKeyMapping:(NSString*)theString
{
    for (Profile* bookmark in [[ProfileModel sharedInstance] bookmarks]) {
        if ([iTermKeyBindingMgr haveKeyMappingForKeyString:theString inBookmark:bookmark]) {
            return YES;
        }
    }
    return NO;
}

- (IBAction)saveKeyMapping:(id)sender
{
    if ([[keyPress stringValue] length] == 0) {
        NSBeep();
        return;
    }
    NSMutableDictionary* dict;
    NSString* theParam = [valueToSend stringValue];
    int theAction = [[action selectedItem] tag];
    if (theAction == KEY_ACTION_SELECT_MENU_ITEM) {
        theParam = [[menuToSelect selectedItem] title];
    } else if (theAction == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
        theAction == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE ||
        theAction == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
        theAction == KEY_ACTION_NEW_WINDOW_WITH_PROFILE) {
        theParam = [[bookmarkPopupButton selectedItem] representedObject];
    }
    if ([self _originatorIsBookmark:modifyMappingOriginator]) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        dict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
        NSAssert(dict, @"Can't find node");
        if ([iTermKeyBindingMgr haveGlobalKeyMappingForKeyString:keyString]) {
            if (![self _warnAboutOverride]) {
                return;
            }
        }

        [iTermKeyBindingMgr setMappingAtIndex:[keyMappings selectedRow]
                                       forKey:keyString
                                       action:theAction
                                        value:theParam
                                    createNew:newMapping
                                   inBookmark:dict];
        [dataSource setBookmark:dict withGuid:guid];
        [keyMappings reloadData];
        [self bookmarkSettingChanged:sender];
    } else {
        dict = [NSMutableDictionary dictionaryWithDictionary:[iTermKeyBindingMgr globalKeyMap]];
        if ([self _anyBookmarkHasKeyMapping:keyString]) {
            if (![self _warnAboutPossibleOverride]) {
                return;
            }
        }
        [iTermKeyBindingMgr setMappingAtIndex:[globalKeyMappings selectedRow]
                                       forKey:keyString
                                       action:theAction
                                        value:theParam
                                    createNew:newMapping
                                 inDictionary:dict];
        [iTermKeyBindingMgr setGlobalKeyMap:dict];
        [globalKeyMappings reloadData];
        [self settingChanged:nil];
    }

    [self closeKeyMapping:sender];
}

- (BOOL)keySheetIsOpen
{
    return [editKeyMappingWindow isVisible];
}

- (WindowArrangements *)arrangements
{
    return arrangements_;
}

- (IBAction)closeKeyMapping:(id)sender
{
    [NSApp endSheet:editKeyMappingWindow];
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

- (void)_addMappingWithContextInfo:(id)info
{
    if (keyString) {
        [keyString release];
    }
    [keyPress setStringValue:@""];
    keyString = [[NSString alloc] init];
    // For some reason, the first item is checked by default. Make sure every
    // item is unchecked before making a selection.
    for (NSMenuItem* item in [action itemArray]) {
        [item setState:NSOffState];
    }
    [action selectItemWithTag:KEY_ACTION_IGNORE];
    [valueToSend setStringValue:@""];
    [self updateValueToSend];
    newMapping = YES;

    modifyMappingOriginator = info;
    [NSApp beginSheet:editKeyMappingWindow
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
          contextInfo:info];
}

- (void)setKeyMappingsToPreset:(NSString*)presetName
{
    NSString* guid = [bookmarksTableView selectedGuid];
    NSAssert(guid, @"Null guid unexpected here");
    NSMutableDictionary* tempDict = [NSMutableDictionary dictionaryWithDictionary:[dataSource bookmarkWithGuid:guid]];
    NSAssert(tempDict, @"Can't find node");
    [iTermKeyBindingMgr setKeyMappingsToPreset:presetName inBookmark:tempDict];
    [dataSource setBookmark:tempDict withGuid:guid];
    [keyMappings reloadData];
    [self bookmarkSettingChanged:nil];
}

- (void)setGlobalKeyMappingsToPreset:(NSString*)presetName
{
    [iTermKeyBindingMgr setGlobalKeyMappingsToPreset:presetName];
    [globalKeyMappings reloadData];
    [self settingChanged:nil];
}

- (IBAction)presetKeyMappingsItemSelected:(id)sender
{
    [self setKeyMappingsToPreset:[[sender selectedItem] title]];
}

- (IBAction)useFactoryGlobalKeyMappings:(id)sender
{
    [self setGlobalKeyMappingsToPreset:@"Factory Defaults"];
}

- (void)_removeKeyMappingsReferringToBookmarkGuid:(NSString*)badRef
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
    [[PreferencePanel sharedInstance]->keyMappings reloadData];
    [[PreferencePanel sessionsInstance]->keyMappings reloadData];
}

- (BOOL)remappingDisabledTemporarily
{
    return [[self keySheet] isKeyWindow] && [self keySheetIsOpen] && ([action selectedTag] == KEY_ACTION_DO_NOT_REMAP_MODIFIERS ||
                                                                      [action selectedTag] == KEY_ACTION_REMAP_LOCALLY);
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

- (void)readPreferences
{
    if (!prefs) {
        // In one-bookmark mode there are no prefs, but this function only reads
        // non-bookmark related stuff.
        return;
    }
    // Force antialiasing to be allowed on small font sizes
    [prefs setInteger:1 forKey:@"AppleAntiAliasingThreshold"];
    [prefs setInteger:1 forKey:@"AppleSmoothFixedFontsSizeThreshold"];
    [prefs setInteger:0 forKey:@"AppleScrollAnimationEnabled"];

    defaultWindowStyle=[prefs objectForKey:@"WindowStyle"]?[prefs integerForKey:@"WindowStyle"]:0;
    defaultOpenTmuxWindowsIn = [prefs objectForKey:@"OpenTmuxWindowsIn"]?[prefs integerForKey:@"OpenTmuxWindowsIn"]:OPEN_TMUX_WINDOWS_IN_WINDOWS;
    defaultAutoHideTmuxClientSession = [prefs objectForKey:@"AutoHideTmuxClientSession"] ? [[prefs objectForKey:@"AutoHideTmuxClientSession"] boolValue] : NO;
    defaultTabViewType=[prefs objectForKey:@"TabViewType"]?[prefs integerForKey:@"TabViewType"]:0;
    if (defaultTabViewType > 1) {
        defaultTabViewType = 0;
    }
    defaultAllowClipboardAccess=[prefs objectForKey:@"AllowClipboardAccess"]?[[prefs objectForKey:@"AllowClipboardAccess"] boolValue]:NO;
    defaultCopySelection=[prefs objectForKey:@"CopySelection"]?[[prefs objectForKey:@"CopySelection"] boolValue]:YES;
    defaultCopyLastNewline = [prefs objectForKey:@"CopyLastNewline"] ? [[prefs objectForKey:@"CopyLastNewline"] boolValue] : NO;
    defaultPasteFromClipboard=[prefs objectForKey:@"PasteFromClipboard"]?[[prefs objectForKey:@"PasteFromClipboard"] boolValue]:YES;
    defaultThreeFingerEmulatesMiddle=[prefs objectForKey:@"ThreeFingerEmulates"]?[[prefs objectForKey:@"ThreeFingerEmulates"] boolValue]:NO;
    defaultHideTab=[prefs objectForKey:@"HideTab"]?[[prefs objectForKey:@"HideTab"] boolValue]: YES;
    defaultPromptOnQuit = [prefs objectForKey:@"PromptOnQuit"]?[[prefs objectForKey:@"PromptOnQuit"] boolValue]: YES;
    defaultOnlyWhenMoreTabs = [prefs objectForKey:@"OnlyWhenMoreTabs"]?[[prefs objectForKey:@"OnlyWhenMoreTabs"] boolValue]: YES;
    defaultFocusFollowsMouse = [prefs objectForKey:@"FocusFollowsMouse"]?[[prefs objectForKey:@"FocusFollowsMouse"] boolValue]: NO;
    defaultTripleClickSelectsFullLines = [prefs objectForKey:@"TripleClickSelectsFullWrappedLines"] ? [[prefs objectForKey:@"TripleClickSelectsFullWrappedLines"] boolValue] : NO;
    defaultHotkeyTogglesWindow = [prefs objectForKey:@"HotKeyTogglesWindow"]?[[prefs objectForKey:@"HotKeyTogglesWindow"] boolValue]: NO;
    defaultHotkeyAutoHides = [prefs objectForKey:@"HotkeyAutoHides"] ? [[prefs objectForKey:@"HotkeyAutoHides"] boolValue] : YES;
    defaultHotKeyBookmarkGuid = [[prefs objectForKey:@"HotKeyBookmark"] copy];
    defaultEnableBonjour = [prefs objectForKey:@"EnableRendezvous"]?[[prefs objectForKey:@"EnableRendezvous"] boolValue]: NO;
    defaultCmdSelection = [prefs objectForKey:@"CommandSelection"]?[[prefs objectForKey:@"CommandSelection"] boolValue]: YES;
    defaultOptionClickMovesCursor = [prefs objectForKey:@"OptionClickMovesCursor"]?[[prefs objectForKey:@"OptionClickMovesCursor"] boolValue]: YES;
    defaultPassOnControlLeftClick = [prefs objectForKey:@"PassOnControlClick"]?[[prefs objectForKey:@"PassOnControlClick"] boolValue] : NO;
    defaultMaxVertically = [prefs objectForKey:@"MaxVertically"] ? [[prefs objectForKey:@"MaxVertically"] boolValue] : NO;
    defaultFsTabDelay = [prefs objectForKey:@"FsTabDelay"] ? [[prefs objectForKey:@"FsTabDelay"] floatValue] : 1.0;

    defaultHideTabCloseButton = [prefs boolForKey:@"HideTabCloseButton"];
    defaultHideTabNumber = [prefs boolForKey:@"HideTabNumber"];
    defaultHideActivityIndicator = [prefs objectForKey:@"HideActivityIndicator"]?[[prefs objectForKey:@"HideActivityIndicator"] boolValue]: NO;
    defaultHighlightTabLabels = [prefs objectForKey:@"HighlightTabLabels"]?[[prefs objectForKey:@"HighlightTabLabels"] boolValue]: YES;
    defaultHideMenuBarInFullscreen = [prefs objectForKey:@"HideMenuBarInFullscreen"]?[[prefs objectForKey:@"HideMenuBarInFullscreen"] boolValue] : YES;
    [defaultWordChars release];
    defaultWordChars = [prefs objectForKey: @"WordCharacters"]?[[prefs objectForKey: @"WordCharacters"] retain]:@"/-+\\~_.";
    defaultTmuxDashboardLimit = [prefs objectForKey: @"TmuxDashboardLimit"]?[[prefs objectForKey:@"TmuxDashboardLimit"] intValue]:10;
    defaultOpenBookmark = [prefs objectForKey:@"OpenBookmark"]?[[prefs objectForKey:@"OpenBookmark"] boolValue]: NO;
    defaultQuitWhenAllWindowsClosed = [prefs objectForKey:@"QuitWhenAllWindowsClosed"]?[[prefs objectForKey:@"QuitWhenAllWindowsClosed"] boolValue]: NO;
    defaultCheckUpdate = [prefs objectForKey:@"SUEnableAutomaticChecks"]?[[prefs objectForKey:@"SUEnableAutomaticChecks"] boolValue]: YES;
    defaultHideScrollbar = [prefs objectForKey:@"HideScrollbar"]?[[prefs objectForKey:@"HideScrollbar"] boolValue]: NO;
    defaultShowPaneTitles = [prefs objectForKey:@"ShowPaneTitles"]?[[prefs objectForKey:@"ShowPaneTitles"] boolValue]: YES;
    defaultDisableFullscreenTransparency = [prefs objectForKey:@"DisableFullscreenTransparency"] ? [[prefs objectForKey:@"DisableFullscreenTransparency"] boolValue] : NO;
    defaultSmartPlacement = [prefs objectForKey:@"SmartPlacement"]?[[prefs objectForKey:@"SmartPlacement"] boolValue]: NO;
    defaultAdjustWindowForFontSizeChange = [prefs objectForKey:@"AdjustWindowForFontSizeChange"]?[[prefs objectForKey:@"AdjustWindowForFontSizeChange"] boolValue]: YES;
    defaultWindowNumber = [prefs objectForKey:@"WindowNumber"]?[[prefs objectForKey:@"WindowNumber"] boolValue]: YES;
    defaultJobName = [prefs objectForKey:@"JobName"]?[[prefs objectForKey:@"JobName"] boolValue]: YES;
    defaultShowBookmarkName = [prefs objectForKey:@"ShowBookmarkName"]?[[prefs objectForKey:@"ShowBookmarkName"] boolValue] : NO;
    defaultHotkey = [prefs objectForKey:@"Hotkey"]?[[prefs objectForKey:@"Hotkey"] boolValue]: NO;
    defaultHotkeyCode = [prefs objectForKey:@"HotkeyCode"]?[[prefs objectForKey:@"HotkeyCode"] intValue]: 0;
    defaultHotkeyChar = [prefs objectForKey:@"HotkeyChar"]?[[prefs objectForKey:@"HotkeyChar"] intValue]: 0;
    defaultHotkeyModifiers = [prefs objectForKey:@"HotkeyModifiers"]?[[prefs objectForKey:@"HotkeyModifiers"] intValue]: 0;
    defaultSavePasteHistory = [prefs objectForKey:@"SavePasteHistory"]?[[prefs objectForKey:@"SavePasteHistory"] boolValue]: NO;
    if ([WindowArrangements count] > 0) {
        defaultOpenArrangementAtStartup = [prefs objectForKey:@"OpenArrangementAtStartup"]?[[prefs objectForKey:@"OpenArrangementAtStartup"] boolValue]: NO;
    } else {
        defaultOpenArrangementAtStartup = NO;
    }
    defaultIrMemory = [prefs objectForKey:@"IRMemory"]?[[prefs objectForKey:@"IRMemory"] intValue] : 4;
    defaultCheckTestRelease = [prefs objectForKey:@"CheckTestRelease"]?[[prefs objectForKey:@"CheckTestRelease"] boolValue]: YES;
    defaultDimInactiveSplitPanes = [prefs objectForKey:@"DimInactiveSplitPanes"]?[[prefs objectForKey:@"DimInactiveSplitPanes"] boolValue]: YES;
    defaultDimBackgroundWindows = [prefs objectForKey:@"DimBackgroundWindows"]?[[prefs objectForKey:@"DimBackgroundWindows"] boolValue]: NO;
    defaultAnimateDimming = [prefs objectForKey:@"AnimateDimming"]?[[prefs objectForKey:@"AnimateDimming"] boolValue]: NO;
    defaultDimOnlyText = [prefs objectForKey:@"DimOnlyText"]?[[prefs objectForKey:@"DimOnlyText"] boolValue]: NO;
    defaultDimmingAmount = [prefs objectForKey:@"SplitPaneDimmingAmount"] ? [[prefs objectForKey:@"SplitPaneDimmingAmount"] floatValue] : 0.4;
    defaultShowWindowBorder = [[prefs objectForKey:@"UseBorder"] boolValue];
    defaultLionStyleFullscreen = [prefs objectForKey:@"UseLionStyleFullscreen"] ? [[prefs objectForKey:@"UseLionStyleFullscreen"] boolValue] : YES;

    defaultControl = [prefs objectForKey:@"Control"] ? [[prefs objectForKey:@"Control"] intValue] : MOD_TAG_CONTROL;
    defaultLeftOption = [prefs objectForKey:@"LeftOption"] ? [[prefs objectForKey:@"LeftOption"] intValue] : MOD_TAG_LEFT_OPTION;
    defaultRightOption = [prefs objectForKey:@"RightOption"] ? [[prefs objectForKey:@"RightOption"] intValue] : MOD_TAG_RIGHT_OPTION;
    defaultLeftCommand = [prefs objectForKey:@"LeftCommand"] ? [[prefs objectForKey:@"LeftCommand"] intValue] : MOD_TAG_LEFT_COMMAND;
    defaultRightCommand = [prefs objectForKey:@"RightCommand"] ? [[prefs objectForKey:@"RightCommand"] intValue] : MOD_TAG_RIGHT_COMMAND;
    if ([self isAnyModifierRemapped]) {
        // Use a brief delay so windows have a chance to open before the dialog is shown.
        [[HotkeyWindowController sharedInstance] performSelector:@selector(beginRemappingModifiers)
                                                      withObject:nil
                                                      afterDelay:0.5];
    }
    defaultSwitchTabModifier = [prefs objectForKey:@"SwitchTabModifier"] ? [[prefs objectForKey:@"SwitchTabModifier"] intValue] : MOD_TAG_ANY_COMMAND;
    defaultSwitchWindowModifier = [prefs objectForKey:@"SwitchWindowModifier"] ? [[prefs objectForKey:@"SwitchWindowModifier"] intValue] : MOD_TAG_CMD_OPT;

    NSString *appCast = defaultCheckTestRelease ?
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForTesting"] :
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURLForFinal"];
    [prefs setObject:appCast forKey:@"SUFeedURL"];

    // Migrate old-style (iTerm 0.x) URL handlers.
    // make sure bookmarks are loaded
    [ITAddressBookMgr sharedInstance];

    // read in the handlers by converting the index back to bookmarks
    urlHandlersByGuid = [[NSMutableDictionary alloc] init];
    NSDictionary *tempDict = [prefs objectForKey:@"URLHandlersByGuid"];
    if (!tempDict) {
        // Iterate over old style url handlers (which stored bookmark by index)
        // and add guid->urlkey to urlHandlersByGuid.
        tempDict = [prefs objectForKey:@"URLHandlers"];

        if (tempDict) {
            NSEnumerator *enumerator = [tempDict keyEnumerator];
            id key;

            while ((key = [enumerator nextObject])) {
                //NSLog(@"%@\n%@",[tempDict objectForKey:key], [[ITAddressBookMgr sharedInstance] bookmarkForIndex:[[tempDict objectForKey:key] intValue]]);
                int theIndex = [[tempDict objectForKey:key] intValue];
                if (theIndex >= 0 &&
                    theIndex  < [dataSource numberOfBookmarks]) {
                    NSString* guid = [[dataSource profileAtIndex:theIndex] objectForKey:KEY_GUID];
                    [urlHandlersByGuid setObject:guid forKey:key];
                }
            }
        }
    } else {
        NSEnumerator *enumerator = [tempDict keyEnumerator];
        id key;

        while ((key = [enumerator nextObject])) {
            //NSLog(@"%@\n%@",[tempDict objectForKey:key], [[ITAddressBookMgr sharedInstance] bookmarkForIndex:[[tempDict objectForKey:key] intValue]]);
            NSString* guid = [tempDict objectForKey:key];
            if ([dataSource indexOfProfileWithGuid:guid] >= 0) {
                [urlHandlersByGuid setObject:guid forKey:key];
            }
        }
    }
}

- (void)savePreferences
{
    if (!prefs) {
        // In one-bookmark mode there are no prefs but this function doesn't
        // affect bookmarks.
        return;
    }

    [prefs setBool:defaultAllowClipboardAccess forKey:@"AllowClipboardAccess"];
    [prefs setBool:defaultCopySelection forKey:@"CopySelection"];
    [prefs setBool:defaultCopyLastNewline forKey:@"CopyLastNewline"];
    [prefs setBool:defaultPasteFromClipboard forKey:@"PasteFromClipboard"];
    [prefs setBool:defaultThreeFingerEmulatesMiddle forKey:@"ThreeFingerEmulates"];
    [prefs setBool:defaultHideTab forKey:@"HideTab"];
    [prefs setInteger:defaultWindowStyle forKey:@"WindowStyle"];
        [prefs setInteger:defaultOpenTmuxWindowsIn forKey:@"OpenTmuxWindowsIn"];
    [prefs setBool:defaultAutoHideTmuxClientSession forKey:@"AutoHideTmuxClientSession"];
    [prefs setInteger:defaultTabViewType forKey:@"TabViewType"];
    [prefs setBool:defaultPromptOnQuit forKey:@"PromptOnQuit"];
    [prefs setBool:defaultOnlyWhenMoreTabs forKey:@"OnlyWhenMoreTabs"];
    [prefs setBool:defaultFocusFollowsMouse forKey:@"FocusFollowsMouse"];
    [prefs setBool:defaultTripleClickSelectsFullLines forKey:@"TripleClickSelectsFullWrappedLines"];
    [prefs setBool:defaultHotkeyTogglesWindow forKey:@"HotKeyTogglesWindow"];
    [prefs setBool:defaultHotkeyAutoHides forKey:@"HotkeyAutoHides"];
    [prefs setValue:defaultHotKeyBookmarkGuid forKey:@"HotKeyBookmark"];
    [prefs setBool:defaultEnableBonjour forKey:@"EnableRendezvous"];
    [prefs setBool:defaultCmdSelection forKey:@"CommandSelection"];
    [prefs setBool:defaultOptionClickMovesCursor forKey:@"OptionClickMovesCursor"];
    [prefs setFloat:defaultFsTabDelay forKey:@"FsTabDelay"];
    [prefs setBool:defaultPassOnControlLeftClick forKey:@"PassOnControlClick"];
    [prefs setBool:defaultMaxVertically forKey:@"MaxVertically"];
    [prefs setBool:defaultHideTabNumber forKey:@"HideTabNumber"];
    [prefs setBool:defaultHideTabCloseButton forKey:@"HideTabCloseButton"];
    [prefs setBool:defaultHideActivityIndicator forKey:@"HideActivityIndicator"];
    [prefs setBool:defaultHighlightTabLabels forKey:@"HighlightTabLabels"];
    [prefs setBool:defaultHideMenuBarInFullscreen forKey:@"HideMenuBarInFullscreen"];
    [prefs setObject:defaultWordChars forKey: @"WordCharacters"];
    [prefs setObject:[NSNumber numberWithInt:defaultTmuxDashboardLimit]
                          forKey:@"TmuxDashboardLimit"];
    [prefs setBool:defaultOpenBookmark forKey:@"OpenBookmark"];
    [prefs setObject:[dataSource rawData] forKey: @"New Bookmarks"];
    [prefs setBool:defaultQuitWhenAllWindowsClosed forKey:@"QuitWhenAllWindowsClosed"];
    [prefs setBool:defaultCheckUpdate forKey:@"SUEnableAutomaticChecks"];
    [prefs setBool:defaultHideScrollbar forKey:@"HideScrollbar"];
    [prefs setBool:defaultShowPaneTitles forKey:@"ShowPaneTitles"];
    [prefs setBool:defaultDisableFullscreenTransparency forKey:@"DisableFullscreenTransparency"];
    [prefs setBool:defaultSmartPlacement forKey:@"SmartPlacement"];
    [prefs setBool:defaultAdjustWindowForFontSizeChange forKey:@"AdjustWindowForFontSizeChange"];
    [prefs setBool:defaultWindowNumber forKey:@"WindowNumber"];
    [prefs setBool:defaultJobName forKey:@"JobName"];
    [prefs setBool:defaultShowBookmarkName forKey:@"ShowBookmarkName"];
    [prefs setBool:defaultHotkey forKey:@"Hotkey"];
    [prefs setInteger:defaultHotkeyCode forKey:@"HotkeyCode"];
    [prefs setInteger:defaultHotkeyChar forKey:@"HotkeyChar"];
    [prefs setInteger:defaultHotkeyModifiers forKey:@"HotkeyModifiers"];
    [prefs setBool:defaultSavePasteHistory forKey:@"SavePasteHistory"];
    [prefs setBool:defaultOpenArrangementAtStartup forKey:@"OpenArrangementAtStartup"];
    [prefs setInteger:defaultIrMemory forKey:@"IRMemory"];
    [prefs setBool:defaultCheckTestRelease forKey:@"CheckTestRelease"];
    [prefs setBool:defaultDimInactiveSplitPanes forKey:@"DimInactiveSplitPanes"];
    [prefs setBool:defaultDimBackgroundWindows forKey:@"DimBackgroundWindows"];
    [prefs setBool:defaultAnimateDimming forKey:@"AnimateDimming"];
    [prefs setBool:defaultDimOnlyText forKey:@"DimOnlyText"];
    [prefs setFloat:defaultDimmingAmount forKey:@"SplitPaneDimmingAmount"];
    [prefs setBool:defaultShowWindowBorder forKey:@"UseBorder"];
    [prefs setBool:defaultLionStyleFullscreen forKey:@"UseLionStyleFullscreen"];

    [prefs setInteger:defaultControl forKey:@"Control"];
    [prefs setInteger:defaultLeftOption forKey:@"LeftOption"];
    [prefs setInteger:defaultRightOption forKey:@"RightOption"];
    [prefs setInteger:defaultLeftCommand forKey:@"LeftCommand"];
    [prefs setInteger:defaultRightCommand forKey:@"RightCommand"];
    [prefs setInteger:defaultSwitchTabModifier forKey:@"SwitchTabModifier"];
    [prefs setInteger:defaultSwitchWindowModifier forKey:@"SwitchWindowModifier"];

    // save the handlers by converting the bookmark into an index
    [prefs setObject:urlHandlersByGuid forKey:@"URLHandlersByGuid"];

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

- (void)updateValueToSend
{
    int tag = [[action selectedItem] tag];
    if (tag == KEY_ACTION_HEX_CODE) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"ex: 0x7f 0x20"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_TEXT) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"Enter value to send"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_RUN_COPROCESS) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"Enter command to run"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_SELECT_MENU_ITEM) {
        [valueToSend setHidden:YES];
        [[valueToSend cell] setPlaceholderString:@"Enter name of menu item"];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [menuToSelect setHidden:NO];
        [profileLabel setHidden:YES];
    } else if (tag == KEY_ACTION_ESCAPE_SEQUENCE) {
        [valueToSend setHidden:NO];
        [[valueToSend cell] setPlaceholderString:@"characters to send"];
        [escPlus setHidden:NO];
        [escPlus setStringValue:@"Esc+"];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE ||
               tag == KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE ||
               tag == KEY_ACTION_NEW_TAB_WITH_PROFILE ||
               tag == KEY_ACTION_NEW_WINDOW_WITH_PROFILE) {
        [valueToSend setHidden:YES];
        [profileLabel setHidden:NO];
        [bookmarkPopupButton setHidden:NO];
        [escPlus setHidden:YES];
        [menuToSelect setHidden:YES];
    } else if (tag == KEY_ACTION_DO_NOT_REMAP_MODIFIERS ||
               tag == KEY_ACTION_REMAP_LOCALLY) {
        [valueToSend setHidden:YES];
        [valueToSend setStringValue:@""];
        [escPlus setHidden:NO];
        [escPlus setStringValue:@"Modifier remapping disabled: type the actual key combo you want to affect."];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    } else {
        [valueToSend setHidden:YES];
        [valueToSend setStringValue:@""];
        [escPlus setHidden:YES];
        [bookmarkPopupButton setHidden:YES];
        [profileLabel setHidden:YES];
        [menuToSelect setHidden:YES];
    }
}

- (void)copyAttributes:(BulkCopySettings)attributes fromBookmark:(NSString*)guid toBookmark:(NSString*)destGuid
{
    Profile* dest = [dataSource bookmarkWithGuid:destGuid];
    Profile* src = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] initWithDictionary:dest] autorelease];
    NSString** keys = NULL;
    NSString* colorsKeys[] = {
        KEY_FOREGROUND_COLOR,
        KEY_BACKGROUND_COLOR,
        KEY_BOLD_COLOR,
        KEY_SELECTION_COLOR,
        KEY_SELECTED_TEXT_COLOR,
        KEY_CURSOR_COLOR,
        KEY_CURSOR_TEXT_COLOR,
        KEY_ANSI_0_COLOR,
        KEY_ANSI_1_COLOR,
        KEY_ANSI_2_COLOR,
        KEY_ANSI_3_COLOR,
        KEY_ANSI_4_COLOR,
        KEY_ANSI_5_COLOR,
        KEY_ANSI_6_COLOR,
        KEY_ANSI_7_COLOR,
        KEY_ANSI_8_COLOR,
        KEY_ANSI_9_COLOR,
        KEY_ANSI_10_COLOR,
        KEY_ANSI_11_COLOR,
        KEY_ANSI_12_COLOR,
        KEY_ANSI_13_COLOR,
        KEY_ANSI_14_COLOR,
        KEY_ANSI_15_COLOR,
        KEY_SMART_CURSOR_COLOR,
        KEY_MINIMUM_CONTRAST,
        nil
    };
    NSString* displayKeys[] = {
        KEY_NORMAL_FONT,
        KEY_NON_ASCII_FONT,
        KEY_HORIZONTAL_SPACING,
        KEY_VERTICAL_SPACING,
        KEY_BLINKING_CURSOR,
        KEY_BLINK_ALLOWED,
        KEY_CURSOR_TYPE,
        KEY_USE_BOLD_FONT,
        KEY_USE_BRIGHT_BOLD,
        KEY_USE_ITALIC_FONT,
        KEY_ASCII_ANTI_ALIASED,
        KEY_NONASCII_ANTI_ALIASED,
        KEY_USE_NONASCII_FONT,
        KEY_ANTI_ALIASING,
        KEY_AMBIGUOUS_DOUBLE_WIDTH,
        nil
    };
    NSString* windowKeys[] = {
        KEY_ROWS,
        KEY_COLUMNS,
        KEY_WINDOW_TYPE,
        KEY_SCREEN,
        KEY_SPACE,
        KEY_TRANSPARENCY,
        KEY_BLEND,
        KEY_BLUR_RADIUS,
        KEY_BLUR,
        KEY_BACKGROUND_IMAGE_LOCATION,
        KEY_BACKGROUND_IMAGE_TILED,
        KEY_SYNC_TITLE,
        KEY_DISABLE_WINDOW_RESIZING,
        KEY_PREVENT_TAB,
        KEY_HIDE_AFTER_OPENING,
        nil
    };
    NSString* terminalKeys[] = {
        KEY_XTERM_MOUSE_REPORTING,
        KEY_DISABLE_SMCUP_RMCUP,
        KEY_ALLOW_TITLE_REPORTING,
        KEY_ALLOW_TITLE_SETTING,
        KEY_DISABLE_PRINTING,
        KEY_CHARACTER_ENCODING,
        KEY_SCROLLBACK_LINES,
        KEY_SCROLLBACK_WITH_STATUS_BAR,
        KEY_SCROLLBACK_IN_ALTERNATE_SCREEN,
        KEY_UNLIMITED_SCROLLBACK,
        KEY_TERMINAL_TYPE,
        KEY_USE_CANONICAL_PARSER,
        KEY_SILENCE_BELL,
        KEY_VISUAL_BELL,
        KEY_FLASHING_BELL,
        KEY_BOOKMARK_GROWL_NOTIFICATIONS,
        KEY_SET_LOCALE_VARS,
        nil
    };
    NSString *sessionKeys[] = {
        KEY_CLOSE_SESSIONS_ON_END,
        KEY_PROMPT_CLOSE,
        KEY_JOBS,
        KEY_AUTOLOG,
        KEY_LOGDIR,
        KEY_SEND_CODE_WHEN_IDLE,
        KEY_IDLE_CODE,
        nil
    };

    NSString* keyboardKeys[] = {
        KEY_KEYBOARD_MAP,
        KEY_OPTION_KEY_SENDS,
        KEY_RIGHT_OPTION_KEY_SENDS,
        KEY_APPLICATION_KEYPAD_ALLOWED,
        nil
    };
    NSString *advancedKeys[] = {
        KEY_TRIGGERS,
        KEY_SMART_SELECTION_RULES,
        nil
    };
    switch (attributes) {
        case BulkCopyColors:
            keys = colorsKeys;
            break;
        case BulkCopyDisplay:
            keys = displayKeys;
            break;
        case BulkCopyWindow:
            keys = windowKeys;
            break;
        case BulkCopyTerminal:
            keys = terminalKeys;
            break;
        case BulkCopyKeyboard:
            keys = keyboardKeys;
            break;
        case BulkCopySession:
            keys = sessionKeys;
            break;
        case BulkCopyAdvanced:
            keys = advancedKeys;
            break;
        default:
            NSLog(@"Unexpected copy attribute %d", (int)attributes);
            return;
    }

    for (int i = 0; keys[i]; ++i) {
        id srcValue = [src objectForKey:keys[i]];
        if (srcValue) {
            [newDict setObject:srcValue forKey:keys[i]];
        } else {
            [newDict removeObjectForKey:keys[i]];
        }
    }

    [dataSource setBookmark:newDict withGuid:[dest objectForKey:KEY_GUID]];
}

#pragma mark - Hotkey Window

- (NSTextField*)shortcutKeyTextField
{
    return keyPress;
}

- (void)shortcutKeyDown:(NSEvent*)event
{
    unsigned int keyMods;
    unsigned short keyCode;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    keyCode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;

    // turn off all the other modifier bits we don't care about
    unsigned int theModifiers = keyMods &
    (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask |
     NSCommandKeyMask | NSNumericPadKeyMask);

    // on some keyboards, arrow keys have NSNumericPadKeyMask bit set; manually set it for keyboards that don't
    if (keyCode >= NSUpArrowFunctionKey &&
        keyCode <= NSRightArrowFunctionKey) {
        theModifiers |= NSNumericPadKeyMask;
    }
    if (keyString) {
        [keyString release];
    }
    keyString = [[NSString stringWithFormat:@"0x%x-0x%x", keyCode,
                  theModifiers] retain];

    [keyPress setStringValue:[iTermKeyBindingMgr formatKeyCombination:keyString]];
}

- (void)_generateHotkeyWindowProfile
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:[[ProfileModel sharedInstance] defaultBookmark]];
    [dict setObject:[NSNumber numberWithInt:WINDOW_TYPE_TOP] forKey:KEY_WINDOW_TYPE];
    [dict setObject:[NSNumber numberWithInt:25] forKey:KEY_ROWS];
    [dict setObject:[NSNumber numberWithFloat:0.3] forKey:KEY_TRANSPARENCY];
    [dict setObject:[NSNumber numberWithFloat:0.5] forKey:KEY_BLEND];
    [dict setObject:[NSNumber numberWithFloat:2.0] forKey:KEY_BLUR_RADIUS];
    [dict setObject:[NSNumber numberWithBool:YES] forKey:KEY_BLUR];
    [dict setObject:[NSNumber numberWithInt:-1] forKey:KEY_SCREEN];
    [dict setObject:[NSNumber numberWithInt:-1] forKey:KEY_SPACE];
    [dict setObject:@"" forKey:KEY_SHORTCUT];
    [dict setObject:kHotkeyWindowGeneratedProfileNameKey forKey:KEY_NAME];
    [dict removeObjectForKey:KEY_TAGS];
    [dict setObject:@"No" forKey:KEY_DEFAULT_BOOKMARK];
    [dict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
    [[ProfileModel sharedInstance] addBookmark:dict];
}

- (void)disableHotkey
{
    [hotkey setState:NSOffState];
    BOOL oldDefaultHotkey = defaultHotkey;
    defaultHotkey = NO;
    if (defaultHotkey != oldDefaultHotkey) {
        [[HotkeyWindowController sharedInstance] unregisterHotkey];
    }
    [self savePreferences];
}

- (void)_populateHotKeyBookmarksMenu
{
    if (!hotkeyBookmark) {
        return;
    }
    [PreferencePanel populatePopUpButtonWithBookmarks:hotkeyBookmark
                                         selectedGuid:defaultHotKeyBookmarkGuid];
}

// Set the local copy of the hotkey, update the pref panel, and register it after a delay.
- (void)setHotKeyChar:(unsigned short)keyChar code:(unsigned int)keyCode mods:(unsigned int)keyMods
{
    defaultHotkeyChar = keyChar;
    defaultHotkeyCode = keyCode;
    defaultHotkeyModifiers = keyMods;
    [[[PreferencePanel sharedInstance] window] makeFirstResponder:[[PreferencePanel sharedInstance] window]];
    [hotkeyField setStringValue:[iTermKeyBindingMgr formatKeyCombination:[NSString stringWithFormat:@"0x%x-0x%x", keyChar, keyMods]]];
    [self performSelector:@selector(setHotKey) withObject:self afterDelay:0.01];
}

- (void)sanityCheckHotKey
{
    if (!defaultHotkeyChar) {
        [self setHotKeyChar:' ' code:kVK_Space mods:NSAlternateKeyMask];
    } else {
        [self setHotKeyChar:defaultHotkeyChar code:defaultHotkeyCode mods:defaultHotkeyModifiers];
    }
}

- (void)hotkeyKeyDown:(NSEvent*)event
{
    unsigned int keyMods;
    NSString *unmodkeystr;

    keyMods = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unsigned short keyChar = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    unsigned int keyCode = [event keyCode];

    [self setHotKeyChar:keyChar code:keyCode mods:keyMods];
}

- (void)setHotKey
{
    [[HotkeyWindowController sharedInstance] registerHotkey:defaultHotkeyCode modifiers:defaultHotkeyModifiers];
}

#pragma mark - Accessors

- (float)fsTabDelay
{
    return defaultFsTabDelay;
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
    return defaultAllowClipboardAccess;
}

- (void) setAllowClipboardAccess:(BOOL)flag
{
    defaultAllowClipboardAccess = flag;
}

- (BOOL)copySelection
{
    return defaultCopySelection;
}

- (BOOL)copyLastNewline
{
    return defaultCopyLastNewline;
}

- (void) setCopySelection:(BOOL)flag
{
    defaultCopySelection = flag;
}

- (BOOL)legacyPasteFromClipboard
{
    return defaultPasteFromClipboard;
}

- (BOOL)pasteFromClipboard
{
    return defaultPasteFromClipboard;
}

- (BOOL)legacyThreeFingerEmulatesMiddle
{
    return defaultThreeFingerEmulatesMiddle;
}

- (BOOL)threeFingerEmulatesMiddle
{
    return defaultThreeFingerEmulatesMiddle;
}

- (void)setPasteFromClipboard:(BOOL)flag
{
    defaultPasteFromClipboard = flag;
}

- (BOOL)hideTab
{
    return defaultHideTab;
}

- (void)setTabViewType:(NSTabViewType)type
{
    defaultTabViewType = type;
}

- (NSTabViewType)tabViewType
{
    return defaultTabViewType;
}

- (int)windowStyle
{
    return defaultWindowStyle;
}

- (int)openTmuxWindowsIn
{
    return defaultOpenTmuxWindowsIn;
}

- (BOOL)autoHideTmuxClientSession
{
    return defaultAutoHideTmuxClientSession;
}

- (int)tmuxDashboardLimit
{
    return defaultTmuxDashboardLimit;
}

- (BOOL)promptOnQuit
{
    return defaultPromptOnQuit;
}

- (BOOL)onlyWhenMoreTabs
{
    return defaultOnlyWhenMoreTabs;
}

- (BOOL)focusFollowsMouse
{
    return defaultFocusFollowsMouse;
}

- (BOOL)tripleClickSelectsFullLines
{
    return defaultTripleClickSelectsFullLines;
}

- (BOOL)enableBonjour
{
    return defaultEnableBonjour;
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

- (BOOL)cmdSelection
{
    return defaultCmdSelection;
}

- (BOOL)optionClickMovesCursor
{
    return defaultOptionClickMovesCursor;
}

- (BOOL)passOnControlLeftClick
{
    return defaultPassOnControlLeftClick;
}

- (BOOL)maxVertically
{
    return defaultMaxVertically;
}

- (BOOL)hideTabNumber {
    return defaultHideTabNumber;
}

- (BOOL)hideTabCloseButton {
    return defaultHideTabCloseButton;
}

- (BOOL)hideActivityIndicator
{
    return defaultHideActivityIndicator;
}

- (BOOL)highlightTabLabels
{
    return defaultHighlightTabLabels;
}

- (BOOL)hideMenuBarInFullscreen
{
    return defaultHideMenuBarInFullscreen;
}

- (BOOL)openBookmark
{
    return defaultOpenBookmark;
}

- (NSString *)wordChars
{
    if ([defaultWordChars length] <= 0) {
        return @"";
    }
    return defaultWordChars;
}

- (ITermCursorType)legacyCursorType
{
    return [prefs objectForKey:@"CursorType"] ? [prefs integerForKey:@"CursorType"] : CURSOR_BOX;
}

- (BOOL)hideScrollbar
{
    return defaultHideScrollbar;
}

- (BOOL)showPaneTitles
{
    return defaultShowPaneTitles;
}

- (BOOL)disableFullscreenTransparency
{
    return defaultDisableFullscreenTransparency;
}

- (BOOL)smartPlacement
{
    return defaultSmartPlacement;
}

- (BOOL)adjustWindowForFontSizeChange
{
    return defaultAdjustWindowForFontSizeChange;
}

- (BOOL)windowNumber
{
    return defaultWindowNumber;
}

- (BOOL)jobName
{
    return defaultJobName;
}

- (BOOL)showBookmarkName
{
    return defaultShowBookmarkName;
}

- (BOOL)instantReplay
{
    return YES;
}

- (BOOL)savePasteHistory
{
    return defaultSavePasteHistory;
}

- (int)control
{
    return defaultControl;
}

- (int)leftOption
{
    return defaultLeftOption;
}

- (int)rightOption
{
    return defaultRightOption;
}

- (int)leftCommand
{
    return defaultLeftCommand;
}

- (int)rightCommand
{
    return defaultRightCommand;
}

- (BOOL)isAnyModifierRemapped
{
    return ([self control] != MOD_TAG_CONTROL ||
            [self leftOption] != MOD_TAG_LEFT_OPTION ||
            [self rightOption] != MOD_TAG_RIGHT_OPTION ||
            [self leftCommand] != MOD_TAG_LEFT_COMMAND ||
            [self rightCommand] != MOD_TAG_RIGHT_COMMAND);
}

- (int)switchTabModifier
{
    return defaultSwitchTabModifier;
}

- (int)switchWindowModifier
{
    return defaultSwitchWindowModifier;
}

- (BOOL)openArrangementAtStartup
{
    return defaultOpenArrangementAtStartup;
}

- (int)irMemory
{
    return defaultIrMemory;
}

- (BOOL)hotkey
{
    return defaultHotkey;
}

- (short)hotkeyChar
{
    return defaultHotkeyChar;
}

- (int)hotkeyCode
{
    return defaultHotkeyCode;
}

- (int)hotkeyModifiers
{
    return defaultHotkeyModifiers;
}

- (NSTextField*)hotkeyField
{
    return hotkeyField;
}

- (BOOL)dimInactiveSplitPanes
{
    return defaultDimInactiveSplitPanes;
}

- (BOOL)dimBackgroundWindows
{
    return defaultDimBackgroundWindows;
}

- (BOOL)animateDimming
{
    return defaultAnimateDimming;
}

- (BOOL)dimOnlyText
{
    return defaultDimOnlyText;
}

- (float)dimmingAmount
{
    return defaultDimmingAmount;
}

- (BOOL)showWindowBorder
{
    return defaultShowWindowBorder;
}

- (BOOL)lionStyleFullscreen
{
    return defaultLionStyleFullscreen;
}

- (BOOL)checkTestRelease
{
    return defaultCheckTestRelease;
}

// Smart cursor color used to be a global value. This provides the default when
// migrating.
- (BOOL)legacySmartCursorColor
{
    return [prefs objectForKey:@"ColorInvertedCursor"]?[[prefs objectForKey:@"ColorInvertedCursor"] boolValue]: YES;
}

- (BOOL)quitWhenAllWindowsClosed
{
    return defaultQuitWhenAllWindowsClosed;
}

// The following are preferences with no UI, but accessible via "defaults read/write"
// examples:
//  defaults write com.googlecode.iterm2 UseUnevenTabs -bool true
//  defaults write com.googlecode.iterm2 MinTabWidth -int 100
//  defaults write com.googlecode.iterm2 MinCompactTabWidth -int 120
//  defaults write com.googlecode.iterm2 OptimumTabWidth -int 100
//  defaults write com.googlecode.iterm2 TraditionalVisualBell -bool true
//  defaults write com.googlecode.iterm2 AlternateMouseScroll -bool true

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

- (float) hotkeyTermAnimationDuration
{
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

- (BOOL)hotkeyTogglesWindow
{
    return defaultHotkeyTogglesWindow;
}

- (BOOL)hotkeyAutoHides
{
    return defaultHotkeyAutoHides;
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

#pragma mark - URL Handler

- (Profile *)handlerBookmarkForURL:(NSString *)url
{
    NSString* handlerId = (NSString*) LSCopyDefaultHandlerForURLScheme((CFStringRef) url);
    if ([handlerId isEqualToString:@"com.googlecode.iterm2"] ||
        [handlerId isEqualToString:@"net.sourceforge.iterm"]) {
        CFRelease(handlerId);
        NSString* guid = [urlHandlersByGuid objectForKey:url];
        if (!guid) {
            return nil;
        }
        int theIndex = [dataSource indexOfProfileWithGuid:guid];
        if (theIndex < 0) {
            return nil;
        }
        return [dataSource profileAtIndex:theIndex];
    } else {
        if (handlerId) {
            CFRelease(handlerId);
        }
        return nil;
    }
}

- (void)_populateBookmarkUrlSchemesFromDict:(Profile*)dict
{
    if ([[[bookmarkUrlSchemes menu] itemArray] count] == 0) {
        NSArray* urlArray = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleURLTypes"];
        for (int i=0; i<[urlArray count]; i++) {
            [bookmarkUrlSchemes addItemWithTitle:[[[urlArray objectAtIndex:i] objectForKey: @"CFBundleURLSchemes"] objectAtIndex:0]];
        }
        [bookmarkUrlSchemes setTitle:@"Select URL Schemes…"];
    }

    NSString* guid = [dict objectForKey:KEY_GUID];
    [[bookmarkUrlSchemes menu] setAutoenablesItems:YES];
    [[bookmarkUrlSchemes menu] setDelegate:self];
    for (NSMenuItem* item in [[bookmarkUrlSchemes menu] itemArray]) {
        Profile* handler = [self handlerBookmarkForURL:[item title]];
        if (handler && [[handler objectForKey:KEY_GUID] isEqualToString:guid]) {
            [item setState:NSOnState];
        } else {
            [item setState:NSOffState];
        }
    }
}

- (void)disconnectHandlerForScheme:(NSString*)scheme
{
    [urlHandlersByGuid removeObjectForKey:scheme];
}

#pragma mark - NSTableViewDataSource

- (int)numberOfRowsInTableView: (NSTableView *)aTableView
{
    if (aTableView == keyMappings) {
        NSString* guid = [bookmarksTableView selectedGuid];
        if (!guid) {
            return 0;
        }
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Null node");
        return [iTermKeyBindingMgr numberOfMappingsForBookmark:bookmark];
    } else if (aTableView == globalKeyMappings) {
        return [[iTermKeyBindingMgr globalKeyMap] count];
    } else if (aTableView == jobsTable_) {
        NSString* guid = [bookmarksTableView selectedGuid];
        if (!guid) {
            return 0;
        }
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
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
        NSString* guid = [bookmarksTableView selectedGuid];
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSMutableArray *jobs = [NSMutableArray arrayWithArray:[bookmark objectForKey:KEY_JOBS]];
        [jobs replaceObjectAtIndex:rowIndex withObject:anObject];
        [dataSource setObject:jobs forKey:KEY_JOBS inBookmark:bookmark];
    }
    [self bookmarkSettingChanged:nil];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    if (aTableView == keyMappings) {
        NSString* guid = [bookmarksTableView selectedGuid];
        NSAssert(guid, @"Null guid unexpected here");
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        NSAssert(bookmark, @"Can't find node");

        if (aTableColumn == keyCombinationColumn) {
            return [iTermKeyBindingMgr formatKeyCombination:[iTermKeyBindingMgr shortcutAtIndex:rowIndex forBookmark:bookmark]];
        } else if (aTableColumn == actionColumn) {
            return [iTermKeyBindingMgr formatAction:[iTermKeyBindingMgr mappingAtIndex:rowIndex forBookmark:bookmark]];
        }
    } else if (aTableView == globalKeyMappings) {
        if (aTableColumn == globalKeyCombinationColumn) {
            return [iTermKeyBindingMgr formatKeyCombination:[iTermKeyBindingMgr globalShortcutAtIndex:rowIndex]];
        } else if (aTableColumn == globalActionColumn) {
            return [iTermKeyBindingMgr formatAction:[iTermKeyBindingMgr globalMappingAtIndex:rowIndex]];
        }
    } else if (aTableView == jobsTable_) {
        NSString* guid = [bookmarksTableView selectedGuid];
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        return [[bookmark objectForKey:KEY_JOBS] objectAtIndex:rowIndex];
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

    [wordChars setDelegate: self];

    [windowStyle selectItemAtIndex: defaultWindowStyle];
    [openTmuxWindows selectItemAtIndex: defaultOpenTmuxWindowsIn];
    [autoHideTmuxClientSession setState:defaultAutoHideTmuxClientSession?NSOnState:NSOffState];
    [tabPosition selectItemAtIndex: defaultTabViewType];
    [allowClipboardAccessFromTerminal setState:defaultAllowClipboardAccess?NSOnState:NSOffState];
    [selectionCopiesText setState:defaultCopySelection?NSOnState:NSOffState];
    [copyLastNewline setState:defaultCopyLastNewline ? NSOnState : NSOffState];
    [middleButtonPastesFromClipboard setState:defaultPasteFromClipboard?NSOnState:NSOffState];
    [threeFingerEmulatesMiddle setState:defaultThreeFingerEmulatesMiddle ? NSOnState : NSOffState];
    [hideTab setState:defaultHideTab?NSOnState:NSOffState];
    [promptOnQuit setState:defaultPromptOnQuit?NSOnState:NSOffState];
    [onlyWhenMoreTabs setState:defaultOnlyWhenMoreTabs?NSOnState:NSOffState];
    [focusFollowsMouse setState: defaultFocusFollowsMouse?NSOnState:NSOffState];
    [tripleClickSelectsFullLines setState:defaultTripleClickSelectsFullLines?NSOnState:NSOffState];
    [hotkeyTogglesWindow setState: defaultHotkeyTogglesWindow?NSOnState:NSOffState];
    [hotkeyAutoHides setState: defaultHotkeyAutoHides?NSOnState:NSOffState];
    [self _populateHotKeyBookmarksMenu];
    [enableBonjour setState: defaultEnableBonjour?NSOnState:NSOffState];
    [cmdSelection setState: defaultCmdSelection?NSOnState:NSOffState];
    [optionClickMovesCursor setState: defaultOptionClickMovesCursor?NSOnState:NSOffState];
    [controlLeftClickActsLikeRightClick setState: defaultPassOnControlLeftClick?NSOffState:NSOnState];
    [maxVertically setState: defaultMaxVertically?NSOnState:NSOffState];
    [hideTabCloseButton setState: defaultHideTabCloseButton?NSOnState:NSOffState];
    [hideTabNumber setState: defaultHideTabNumber?NSOnState:NSOffState];
    [hideActivityIndicator setState:defaultHideActivityIndicator?NSOnState:NSOffState];
    [highlightTabLabels setState: defaultHighlightTabLabels?NSOnState:NSOffState];
    [hideMenuBarInFullscreen setState:defaultHideMenuBarInFullscreen ? NSOnState:NSOffState];
    [fsTabDelay setFloatValue:defaultFsTabDelay];

    [openBookmark setState: defaultOpenBookmark?NSOnState:NSOffState];
    [wordChars setStringValue: ([defaultWordChars length] > 0)?defaultWordChars:@""];
    [tmuxDashboardLimit setIntValue:defaultTmuxDashboardLimit];
    [quitWhenAllWindowsClosed setState: defaultQuitWhenAllWindowsClosed?NSOnState:NSOffState];
    [checkUpdate setState: defaultCheckUpdate?NSOnState:NSOffState];
    [hideScrollbar setState: defaultHideScrollbar?NSOnState:NSOffState];
    [showPaneTitles setState:defaultShowPaneTitles?NSOnState:NSOffState];
    [disableFullscreenTransparency setState:defaultDisableFullscreenTransparency ? NSOnState : NSOffState];
    [smartPlacement setState: defaultSmartPlacement?NSOnState:NSOffState];
    [adjustWindowForFontSizeChange setState: defaultAdjustWindowForFontSizeChange?NSOnState:NSOffState];
    [windowNumber setState: defaultWindowNumber?NSOnState:NSOffState];
    [jobName setState: defaultJobName?NSOnState:NSOffState];
    [showBookmarkName setState: defaultShowBookmarkName?NSOnState:NSOffState];
    [savePasteHistory setState: defaultSavePasteHistory?NSOnState:NSOffState];
    [openArrangementAtStartup setState:defaultOpenArrangementAtStartup ? NSOnState : NSOffState];
    [openArrangementAtStartup setEnabled:[WindowArrangements count] > 0];
    if ([WindowArrangements count] == 0) {
        [openArrangementAtStartup setState:NO];
    }
    [hotkey setState: defaultHotkey?NSOnState:NSOffState];
    if (defaultHotkeyCode || defaultHotkeyChar) {
        [hotkeyField setStringValue:[iTermKeyBindingMgr formatKeyCombination:[NSString stringWithFormat:@"0x%x-0x%x", defaultHotkeyChar, defaultHotkeyModifiers]]];
    } else {
        [hotkeyField setStringValue:@""];
    }
    [hotkeyField setEnabled:defaultHotkey];
    [hotkeyLabel setTextColor:defaultHotkey ? [NSColor blackColor] : [NSColor disabledControlTextColor]];
    [hotkeyTogglesWindow setEnabled:defaultHotkey];
    [hotkeyAutoHides setEnabled:(defaultHotkey && defaultHotkeyTogglesWindow)];
    [hotkeyBookmark setEnabled:(defaultHotkey && defaultHotkeyTogglesWindow)];

    [irMemory setIntValue:defaultIrMemory];
    [checkTestRelease setState:defaultCheckTestRelease?NSOnState:NSOffState];
    [dimInactiveSplitPanes setState:defaultDimInactiveSplitPanes?NSOnState:NSOffState];
    [animateDimming setState:defaultAnimateDimming?NSOnState:NSOffState];
    [dimBackgroundWindows setState:defaultDimBackgroundWindows?NSOnState:NSOffState];
    [dimOnlyText setState:defaultDimOnlyText?NSOnState:NSOffState];
    [dimmingAmount setFloatValue:defaultDimmingAmount];
    [showWindowBorder setState:defaultShowWindowBorder?NSOnState:NSOffState];
    [lionStyleFullscreen setState:defaultLionStyleFullscreen?NSOnState:NSOffState];
    [loadPrefsFromCustomFolder setState:[[iTermRemotePreferences sharedInstance] shouldLoadRemotePrefs] ? NSOnState : NSOffState];
    [prefsCustomFolder setStringValue:[[iTermRemotePreferences sharedInstance] customFolderOrURL]];

    [self showWindow: self];
    [[self window] setLevel:NSNormalWindowLevel];
    NSString* guid = [bookmarksTableView selectedGuid];
    [bookmarksTableView reloadData];
    if ([[bookmarksTableView selectedGuids] count] == 1) {
        Profile* dict = [dataSource bookmarkWithGuid:guid];
        [bookmarksSettingsTabViewParent setHidden:NO];
        [bookmarksPopup setEnabled:NO];
        [self updateBookmarkFields:dict];
    } else {
        [bookmarksPopup setEnabled:YES];
        [bookmarksSettingsTabViewParent setHidden:YES];
        if ([[bookmarksTableView selectedGuids] count] == 0) {
            [removeBookmarkButton setEnabled:NO];
        } else {
            [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [[bookmarksTableView dataSource] numberOfBookmarks]];
        }
        [self updateBookmarkFields:nil];
    }

    if (![bookmarksTableView selectedGuid] && [bookmarksTableView numberOfRows]) {
        [bookmarksTableView selectRowIndex:0];
    }

    [controlButton selectItemWithTag:defaultControl];
    [leftOptionButton selectItemWithTag:defaultLeftOption];
    [rightOptionButton selectItemWithTag:defaultRightOption];
    [leftCommandButton selectItemWithTag:defaultLeftCommand];
    [rightCommandButton selectItemWithTag:defaultRightCommand];

    [switchTabModifierButton selectItemWithTag:defaultSwitchTabModifier];
    [switchWindowModifierButton selectItemWithTag:defaultSwitchWindowModifier];

    int rowIndex = [globalKeyMappings selectedRow];
    if (rowIndex >= 0) {
        [globalRemoveMappingButton setEnabled:YES];
    } else {
        [globalRemoveMappingButton setEnabled:NO];
    }
    [globalKeyMappings reloadData];

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
    NSString* guid = [bookmarksTableView selectedGuid];
    if (guid) {
        Profile* bookmark = [dataSource bookmarkWithGuid:guid];
        if (bookmark) {
            [self updateBookmarkFields:bookmark];
        }
    }
}

- (int)shortcutTagForKey:(NSString*)key
{
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
    // NSLog(@"Unexpected shortcut key: '%@'", key);
    return -1;
}

- (NSString*)shortcutKeyForTag:(int)tag
{
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

- (void)updateShortcutTitles
{
    // Reset titles of all shortcuts.
    for (int i = 0; i < [bookmarkShortcutKey numberOfItems]; ++i) {
        NSMenuItem* item = [bookmarkShortcutKey itemAtIndex:i];
        [item setTitle:[self shortcutKeyForTag:[item tag]]];
    }

    // Add bookmark names to shortcuts that are bound.
    for (int i = 0; i < [dataSource numberOfBookmarks]; ++i) {
        Profile* temp = [dataSource profileAtIndex:i];
        NSString* existingShortcut = [temp objectForKey:KEY_SHORTCUT];
        const int tag = [self shortcutTagForKey:existingShortcut];
        if (tag != -1) {
            //NSLog(@"Bookmark %@ has shortcut %@", [temp objectForKey:KEY_NAME], existingShortcut);
            const int theIndex = [bookmarkShortcutKey indexOfItemWithTag:tag];
            NSMenuItem* item = [bookmarkShortcutKey itemAtIndex:theIndex];
            NSString* newTitle = [NSString stringWithFormat:@"%@ (%@)", existingShortcut, [temp objectForKey:KEY_NAME]];
            [item setTitle:newTitle];
        }
    }
}

// Update the values in form fields to reflect the bookmark's state
- (void)updateBookmarkFields:(NSDictionary *)dict
{
    if ([dataSource numberOfBookmarks] < 2 || !dict) {
        [removeBookmarkButton setEnabled:NO];
    } else {
        [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [dataSource numberOfBookmarks]];
    }
    if (!dict) {
        [bookmarksSettingsTabViewParent setHidden:YES];
        [bookmarksPopup setEnabled:NO];
        return;
    } else {
        [bookmarksSettingsTabViewParent setHidden:NO];
        [bookmarksPopup setEnabled:YES];
    }

    NSString* name;
    NSString* shortcut;
    NSString* command;
    NSString* text;
    NSString* dir;
    NSString* customCommand;
    NSString* customDir;
    name = [dict objectForKey:KEY_NAME];
    shortcut = [dict objectForKey:KEY_SHORTCUT];
    command = [dict objectForKey:KEY_COMMAND];
    text = [dict objectForKey:KEY_INITIAL_TEXT];
    if (!text) {
        text = @"";
    }
    dir = [dict objectForKey:KEY_WORKING_DIRECTORY];
    customCommand = [dict objectForKey:KEY_CUSTOM_COMMAND];
    customDir = [dict objectForKey:KEY_CUSTOM_DIRECTORY];

    // General tab
    [bookmarkName setStringValue:name];
    [bookmarkShortcutKey selectItemWithTag:[self shortcutTagForKey:shortcut]];

    [self updateShortcutTitles];

    if ([customCommand isEqualToString:@"Yes"]) {
        [bookmarkCommandType selectCellWithTag:0];
    } else {
        [bookmarkCommandType selectCellWithTag:1];
    }
    [bookmarkCommand setStringValue:command];
    [initialText setStringValue:text];

    BOOL enabledAdvancedEdit = NO;
    if ([customDir isEqualToString:@"Yes"]) {
        [bookmarkDirectoryType selectCellWithTag:0];
    } else if ([customDir isEqualToString:@"Recycle"]) {
        [bookmarkDirectoryType selectCellWithTag:2];
    } else if ([customDir isEqualToString:@"Advanced"]) {
        [bookmarkDirectoryType selectCellWithTag:3];
        enabledAdvancedEdit = YES;
    } else {
        [bookmarkDirectoryType selectCellWithTag:1];
    }
    [editAdvancedConfigButton setEnabled:enabledAdvancedEdit];

    [bookmarkDirectory setStringValue:dir];
    [self _populateBookmarkUrlSchemesFromDict:dict];

    // Colors tab
    [ansi0Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_0_COLOR]]];
    [ansi1Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_1_COLOR]]];
    [ansi2Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_2_COLOR]]];
    [ansi3Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_3_COLOR]]];
    [ansi4Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_4_COLOR]]];
    [ansi5Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_5_COLOR]]];
    [ansi6Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_6_COLOR]]];
    [ansi7Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_7_COLOR]]];
    [ansi8Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_8_COLOR]]];
    [ansi9Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_9_COLOR]]];
    [ansi10Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_10_COLOR]]];
    [ansi11Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_11_COLOR]]];
    [ansi12Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_12_COLOR]]];
    [ansi13Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_13_COLOR]]];
    [ansi14Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_14_COLOR]]];
    [ansi15Color setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_ANSI_15_COLOR]]];
    [foregroundColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_FOREGROUND_COLOR]]];
    [backgroundColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_BACKGROUND_COLOR]]];
    [boldColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_BOLD_COLOR]]];
    [selectionColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_SELECTION_COLOR]]];
    [selectedTextColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_SELECTED_TEXT_COLOR]]];
    [cursorColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_CURSOR_COLOR]]];
    [cursorTextColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_CURSOR_TEXT_COLOR]]];
    [tabColor setColor:[ITAddressBookMgr decodeColor:[dict objectForKey:KEY_TAB_COLOR]]];
    [useTabColor setState:[[dict objectForKey:KEY_USE_TAB_COLOR] boolValue]];
    [tabColor setEnabled:[useTabColor state] == NSOnState];

    BOOL smartCursorColor;
    if ([dict objectForKey:KEY_SMART_CURSOR_COLOR]) {
        smartCursorColor = [[dict objectForKey:KEY_SMART_CURSOR_COLOR] boolValue];
    } else {
        smartCursorColor = [self legacySmartCursorColor];
    }
    [checkColorInvertedCursor setState:smartCursorColor ? NSOnState : NSOffState];

    [cursorColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

    [cursorTextColor setEnabled:[checkColorInvertedCursor state] == NSOffState];
    [cursorTextColorLabel setTextColor:([checkColorInvertedCursor state] == NSOffState) ? [NSColor blackColor] : [NSColor disabledControlTextColor]];

    float minContrast;
    if ([dict objectForKey:KEY_MINIMUM_CONTRAST]) {
        minContrast = [[dict objectForKey:KEY_MINIMUM_CONTRAST] floatValue];
    } else {
        minContrast = [self legacyMinimumContrast];
    }
    [minimumContrast setFloatValue:minContrast];

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
    [blinkingCursor setState:[[dict objectForKey:KEY_BLINKING_CURSOR] boolValue] ? NSOnState : NSOffState];
    [blinkAllowed setState:[[dict objectForKey:KEY_BLINK_ALLOWED] boolValue] ? NSOnState : NSOffState];
    [cursorType selectCellWithTag:[dict objectForKey:KEY_CURSOR_TYPE] ? [[dict objectForKey:KEY_CURSOR_TYPE] intValue] : [self legacyCursorType]];

    NSNumber* useBoldFontEntry = [dict objectForKey:KEY_USE_BOLD_FONT];
    NSNumber* disableBoldEntry = [dict objectForKey:KEY_DISABLE_BOLD];
    if (useBoldFontEntry) {
        [useBoldFont setState:[useBoldFontEntry boolValue] ? NSOnState : NSOffState];
    } else if (disableBoldEntry) {
        // Only deprecated option is set.
        [useBoldFont setState:[disableBoldEntry boolValue] ? NSOffState : NSOnState];
    } else {
        [useBoldFont setState:NSOnState];
    }

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
    int rowIndex = [keyMappings selectedRow];
    if (rowIndex >= 0) {
        [removeMappingButton setEnabled:YES];
    } else {
        [removeMappingButton setEnabled:NO];
    }
    [keyMappings reloadData];
    [optionKeySends selectCellWithTag:[[dict objectForKey:KEY_OPTION_KEY_SENDS] intValue]];
    id rightOptPref = [dict objectForKey:KEY_RIGHT_OPTION_KEY_SENDS];
    if (!rightOptPref) {
        rightOptPref = [dict objectForKey:KEY_OPTION_KEY_SENDS];
    }
    [rightOptionKeySends selectCellWithTag:[rightOptPref intValue]];
    [tags setObjectValue:[dict objectForKey:KEY_TAGS]];
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
    [bookmarksTableView reloadData];
    [copyTo reloadData];
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

- (BOOL)_warnAboutPossibleOverride
{
    switch ([iTermWarning showWarningWithTitle:@"The global keyboard shortcut you have set is overridden by at least one profile. "
                                               @"Check your profiles’ keyboard settings if it doesn't work as expected."
                                       actions:@[ @"OK", @"Cancel" ]
                                    identifier:@"NeverWarnAboutPossibleOverrides"
                                   silenceable:kiTermWarningTypePermanentlySilenceable]) {
        case kiTermWarningSelection1:
            return NO;
        default:
            return YES;
    }
}

- (BOOL)confirmProfileDeletion:(NSArray *)guids {
    NSMutableString *question = [NSMutableString stringWithString:@"Delete profile"];
    if (guids.count > 1) {
        [question appendString:@"s "];
    } else {
        [question appendString:@" "];
    }
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *guid in guids) {
        Profile *profile = [dataSource bookmarkWithGuid:guid];
        NSString *name = [profile objectForKey:KEY_NAME];
        [names addObject:[NSString stringWithFormat:@"\"%@\"", name]];
    }
    [question appendString:[names componentsJoinedByString:@", "]];
    [question appendString:@"?"];
    static NSTimeInterval lastQuell;
    NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    if (lastQuell && (now - lastQuell) < 600) {
        return YES;
    }

    NSAlert *alert;
    alert = [NSAlert alertWithMessageText:@"Confirm Deletion"
                            defaultButton:@"Delete"
                          alternateButton:@"Cancel"
                              otherButton:nil
                informativeTextWithFormat:@"%@", question];
    [alert setShowsSuppressionButton:YES];
    [[alert suppressionButton] setTitle:@"Suppress deletion confirmations temporarily."];
    BOOL result = NO;
    if ([alert runModal] == NSAlertDefaultReturn) {
        result = YES;
    }
    if ([[alert suppressionButton] state] == NSOnState) {
        lastQuell = now;
    }
    return result;
}

#pragma mark - ProfileListViewDelegate

- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent
{
    return nil;
}

- (void)profileTableFilterDidChange:(ProfileListView*)profileListView
{
    [addBookmarkButton setEnabled:![profileListView searchFieldHasText]];
}

- (void)profileTableSelectionWillChange:(id)profileTable
{
    if ([[bookmarksTableView selectedGuids] count] == 1) {
        [self bookmarkSettingChanged:nil];
    }
}

- (void)profileTableSelectionDidChange:(id)profileTable
{
    if ([[bookmarksTableView selectedGuids] count] != 1) {
        [bookmarksSettingsTabViewParent setHidden:YES];
        [bookmarksPopup setEnabled:NO];

        if ([[bookmarksTableView selectedGuids] count] == 0) {
            [removeBookmarkButton setEnabled:NO];
        } else {
            [removeBookmarkButton setEnabled:[[bookmarksTableView selectedGuids] count] < [[bookmarksTableView dataSource] numberOfBookmarks]];
        }
    } else {
        [bookmarksSettingsTabViewParent setHidden:NO];
        [bookmarksPopup setEnabled:YES];
        [removeBookmarkButton setEnabled:NO];
        if (profileTable == bookmarksTableView) {
            NSString* guid = [bookmarksTableView selectedGuid];
            triggerWindowController_.guid = guid;
            smartSelectionWindowController_.guid = guid;
            trouterPrefController_.guid = guid;
            [self updateBookmarkFields:[dataSource bookmarkWithGuid:guid]];
        }
    }
    [self setHaveJobsForCurrentBookmark:[self haveJobsForCurrentBookmark]];
}

- (void)profileTableRowSelected:(id)profileTable
{
    // Do nothing for double click
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    //NSLog(@"%s", __PRETTY_FUNCTION__);
    if ([aNotification object] == keyMappings) {
        int rowIndex = [keyMappings selectedRow];
        if (rowIndex >= 0) {
            [removeMappingButton setEnabled:YES];
        } else {
            [removeMappingButton setEnabled:NO];
        }
    } else if ([aNotification object] == globalKeyMappings) {
        int rowIndex = [globalKeyMappings selectedRow];
        if (rowIndex >= 0) {
            [globalRemoveMappingButton setEnabled:YES];
        } else {
            [globalRemoveMappingButton setEnabled:NO];
        }
    } else if ([aNotification object] == jobsTable_) {
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
    if (obj == wordChars) {
        defaultWordChars = [[wordChars stringValue] retain];
        } else if (obj == tmuxDashboardLimit) {
                [self forceTextFieldToBeNumber:tmuxDashboardLimit
                                           acceptableRange:NSMakeRange(0, 1000)];
                defaultTmuxDashboardLimit = [[tmuxDashboardLimit stringValue] intValue];
    } else if (obj == scrollbackLines) {
                [self forceTextFieldToBeNumber:scrollbackLines
                                           acceptableRange:NSMakeRange(0, 10 * 1000 * 1000)];
        [self bookmarkSettingChanged:nil];
    } else if (obj == columnsField ||
               obj == rowsField ||
               obj == terminalType ||
               obj == initialText ||
               obj == idleCode) {
        [self bookmarkSettingChanged:nil];
    } else if (obj == logDir) {
        [self _updateLogDirWarning];
    } else if (obj == prefsCustomFolder) {
        [self settingChanged:prefsCustomFolder];
    } else if (obj == tagFilter) {
        NSLog(@"Tag filter changed");
    }
}

#pragma mark - NSTokenField delegate

- (NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(NSInteger *)selectedIndex
{
    if (tokenField != tags) {
        return nil;
    }

    NSArray *allTags = [[dataSource allTags] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableArray *result = [[[NSMutableArray alloc] init] autorelease];
    for (NSString *aTag in allTags) {
        if ([aTag hasPrefix:substring]) {
            [result addObject:[aTag retain]];
        }
    }
    return result;
}

- (id)tokenField:(NSTokenField *)tokenField representedObjectForEditingString:(NSString *)editingString
{
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - NSTokenFieldCell delegate

- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell representedObjectForEditingString:(NSString *)editingString
{
    static BOOL running;
    if (!running) {
        running = YES;
        [self bookmarkSettingChanged:tags];
        running = NO;
    }
    return [editingString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

#pragma mark - Cocoa Bindings

// An experiment with cocoa bindings. This is bound to the "enabled" status of
// the "remove job" button.
- (BOOL)haveJobsForCurrentBookmark
{
    if ([jobsTable_ selectedRow] < 0) {
        return NO;
    }
    NSString* guid = [bookmarksTableView selectedGuid];
    if (!guid) {
        return NO;
    }
    Profile* bookmark = [dataSource bookmarkWithGuid:guid];
    NSArray *jobNames = [bookmark objectForKey:KEY_JOBS];
    return [jobNames count] > 0;
}

- (void)setHaveJobsForCurrentBookmark:(BOOL)value
{
    // observed but has no effect because the getter does all the computation.
}

@end
