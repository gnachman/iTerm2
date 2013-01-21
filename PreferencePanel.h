/*
 **  PreferencePanel.h
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

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"
#import "ProfileListView.h"
#import "WindowArrangements.h"
#import "TriggerController.h"
#import "SmartSelectionController.h"
#import "FutureMethods.h"

#define OPT_NORMAL 0
#define OPT_META   1
#define OPT_ESC    2

// Modifier tags
#define MOD_TAG_CONTROL 1
#define MOD_TAG_LEFT_OPTION 2
#define MOD_TAG_RIGHT_OPTION 3
#define MOD_TAG_ANY_COMMAND 4
#define MOD_TAG_OPTION 5  // refers to any option key
#define MOD_TAG_CMD_OPT 6  // both cmd and opt at the same time
#define MOD_TAG_LEFT_COMMAND 7
#define MOD_TAG_RIGHT_COMMAND 8

// Constants for KEY_PROMPT_CLOSE
// Never prompt on close
#define PROMPT_NEVER 0
// Always prompt on close
#define PROMPT_ALWAYS 1
// Prompt on close if jobs (excluding some in a list) are running.
#define PROMPT_EX_JOBS 2

#define OPEN_TMUX_WINDOWS_IN_WINDOWS 0
#define OPEN_TMUX_WINDOWS_IN_TABS 1

@class iTermController;
@class TriggerController;
@class SmartSelectionController;
@class TrouterPrefsController;

typedef enum { CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX } ITermCursorType;

@interface PreferencePanel : NSWindowController <
    ProfileListViewDelegate,
    TriggerDelegate,
    SmartSelectionDelegate,
    NSTokenFieldDelegate,
    NSWindowDelegate,
    NSTextFieldDelegate,
    NSMenuDelegate>
{
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
    BOOL oneBookmarkOnly;

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
    BOOL defaultHotkeyTogglesWindow;
    IBOutlet NSPopUpButton* hotkeyBookmark;
    NSString* defaultHotKeyBookmarkGuid;

    // Enable bonjour
    IBOutlet NSButton *enableBonjour;
    BOOL defaultEnableBonjour;

    // cmd-click to launch url
    IBOutlet NSButton *cmdSelection;
    BOOL defaultCmdSelection;

    // pass on ctrl-click
    IBOutlet NSButton* passOnControlLeftClick;
    BOOL defaultPassOnControlLeftClick;

    // Zoom vertically only
    IBOutlet NSButton *maxVertically;
    BOOL defaultMaxVertically;

    // Closing hotkey window may switch Spaces
    IBOutlet NSButton* closingHotkeySwitchesSpaces;
    BOOL defaultClosingHotkeySwitchesSpaces;

    // use compact tab labels
    IBOutlet NSButton *useCompactLabel;
    BOOL defaultUseCompactLabel;

    // hide activity indicator
    IBOutlet NSButton *hideActivityIndicator;
    BOOL defaultHideActivityIndicator;

    // Highlight tab labels on activity
    IBOutlet NSButton *highlightTabLabels;
    BOOL defaultHighlightTabLabels;

    // Advanced font rendering
    IBOutlet NSButton* advancedFontRendering;
    BOOL defaultAdvancedFontRendering;
    IBOutlet NSSlider* strokeThickness;
    float defaultStrokeThickness;
    IBOutlet NSTextField* strokeThicknessLabel;
    IBOutlet NSTextField* strokeThicknessMinLabel;
    IBOutlet NSTextField* strokeThicknessMaxLabel;

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
    BOOL defaultLoadPrefsFromCustomFolder;
    IBOutlet NSTextField *prefsCustomFolder;
    NSString *defaultPrefsCustomFolder;
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
    NSString* globalToolbarId;
    NSString* appearanceToolbarId;
    NSString* keyboardToolbarId;
    NSString* arrangementsToolbarId;
    NSString* bookmarksToolbarId;
    NSString *mouseToolbarId;
  
    // url handler stuff
    NSMutableDictionary *urlHandlersByGuid;

    // Bookmarks -----------------------------
    IBOutlet ProfileListView *bookmarksTableView;
    IBOutlet NSTableColumn *shellImageColumn;
    IBOutlet NSTableColumn *nameShortcutColumn;
    IBOutlet NSButton *removeBookmarkButton;
    IBOutlet NSButton *addBookmarkButton;

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
    IBOutlet NSSlider *transparency;
    IBOutlet NSSlider *blend;
    IBOutlet NSButton* blur;
    IBOutlet NSSlider *blurRadius;
    IBOutlet NSButton* asciiAntiAliased;
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
    BOOL changingNAFont; // true if font dialog is currently modifying the non-ascii font

    // Terminal tab
    IBOutlet NSButton* disableWindowResizing;
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
    IBOutlet NSButton* disablePrinting;
    IBOutlet NSButton* scrollbackWithStatusBar;
    IBOutlet NSButton* scrollbackInAlternateScreen;
    IBOutlet NSButton* bookmarkGrowlNotifications;
    IBOutlet NSTextField* scrollbackLines;
    IBOutlet NSButton* unlimitedScrollback;
    IBOutlet NSComboBox* terminalType;
    IBOutlet NSPopUpButton* characterEncoding;
    IBOutlet NSButton* setLocaleVars;
    IBOutlet NSButton* useCanonicalParser;

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

    IBOutlet NSTableView* globalKeyMappings;
    IBOutlet NSTableColumn* globalKeyCombinationColumn;
    IBOutlet NSTableColumn* globalActionColumn;
    IBOutlet NSButton* globalRemoveMappingButton;
    IBOutlet NSButton* globalAddNewMapping;

    IBOutlet WindowArrangements *arrangements_;
}

void LoadPrefsFromCustomFolder(void);

typedef enum {
    BulkCopyColors,
    BulkCopyDisplay,
    BulkCopyWindow,
    BulkCopyTerminal,
    BulkCopyKeyboard,
    BulkCopySession,
    BulkCopyAdvanced,
} BulkCopySettings;

+ (PreferencePanel*)sharedInstance;
+ (PreferencePanel*)sessionsInstance;
+ (BOOL)migratePreferences;
+ (BOOL)loadingPrefsFromCustomFolder;
+ (void)populatePopUpButtonWithBookmarks:(NSPopUpButton*)button selectedGuid:(NSString*)selectedGuid;

- (BOOL)loadPrefs;
- (id)initWithDataSource:(ProfileModel*)model userDefaults:(NSUserDefaults*)userDefaults;

- (void)triggerChanged:(TriggerController *)triggerController;
- (void)smartSelectionChanged:(SmartSelectionController *)smartSelectionController;

- (void)setOneBookmarkOnly;
- (void)awakeFromNib;
- (void)handleWindowWillCloseNotification:(NSNotification *)notification;
- (void)genericCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)editKeyMapping:(id)sender;
- (IBAction)showAdvancedWorkingDirConfigPanel:(id)sender;
- (IBAction)closeAdvancedWorkingDirSheet:(id)sender;
- (IBAction)editSmartSelection:(id)sender;
- (IBAction)closeSmartSelectionSheet:(id)sender;
- (IBAction)editTriggers:(id)sender;
- (IBAction)closeTriggersSheet:(id)sender;
- (IBAction)changeProfile:(id)sender;
- (IBAction)addJob:(id)sender;
- (IBAction)removeJob:(id)sender;
- (IBAction)saveKeyMapping:(id)sender;
- (BOOL)keySheetIsOpen;
- (WindowArrangements *)arrangements;
- (IBAction)closeKeyMapping:(id)sender;
- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem;
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag;
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (NSArray *)toolbarSelectableItemIdentifiers: (NSToolbar *)toolbar;
- (void)dealloc;
- (void)readPreferences;
- (void)savePreferences;
- (void)run;
- (IBAction)settingChanged:(id)sender;
- (float)fsTabDelay;
- (BOOL)trimTrailingWhitespace;
- (BOOL)advancedFontRendering;
- (float)strokeThickness;
- (int)modifierTagToMask:(int)tag;
- (void)windowWillLoad;
- (void)windowWillClose:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (BOOL)allowClipboardAccess;
- (void)setAllowClipboardAccess:(BOOL)flag;
- (BOOL)copySelection;
- (BOOL)copyLastNewline;
- (void)setCopySelection:(BOOL)flag;
- (BOOL)legacyPasteFromClipboard;
- (BOOL)pasteFromClipboard;
- (BOOL)legacyThreeFingerEmulatesMiddle;
- (BOOL)threeFingerEmulatesMiddle;
- (void)setPasteFromClipboard:(BOOL)flag;
- (BOOL)hideTab;
- (void)setTabViewType:(NSTabViewType)type;
- (NSTabViewType)tabViewType;
- (int)windowStyle;
- (BOOL)promptOnQuit;
- (BOOL)onlyWhenMoreTabs;
- (BOOL)focusFollowsMouse;
- (BOOL)tripleClickSelectsFullLines;
- (BOOL)enableBonjour;
// Returns true if ANY profile has growl enabled (preserves interface from back
// when there was a global growl setting as well as a per-profile setting).
- (BOOL)enableGrowl;
- (BOOL)cmdSelection;
- (BOOL)passOnControlLeftClick;
- (BOOL)maxVertically;
- (BOOL)closingHotkeySwitchesSpaces;
- (BOOL)useCompactLabel;
- (BOOL)hideActivityIndicator;
- (BOOL)highlightTabLabels;
- (BOOL)openBookmark;
- (NSString *)wordChars;
- (ITermCursorType)legacyCursorType;
- (BOOL)hideScrollbar;
- (BOOL)showPaneTitles;
- (BOOL)disableFullscreenTransparency;
- (BOOL)smartPlacement;
- (BOOL)adjustWindowForFontSizeChange;
- (BOOL)windowNumber;
- (BOOL)jobName;
- (BOOL)showBookmarkName;
- (BOOL)instantReplay;
- (BOOL)savePasteHistory;
- (BOOL)openArrangementAtStartup;
- (int)irMemory;
- (BOOL)hotkey;
- (int)hotkeyCode;
- (int)hotkeyModifiers;
- (NSTextField*)hotkeyField;

- (BOOL)showWindowBorder;
- (BOOL)lionStyleFullscreen;
- (NSString *)loadPrefsFromCustomFolder;
- (BOOL)dimInactiveSplitPanes;
- (BOOL)dimBackgroundWindows;
- (BOOL)animateDimming;
- (BOOL)dimOnlyText;
- (float)dimmingAmount;
- (BOOL)checkTestRelease;
- (BOOL)legacySmartCursorColor;
- (float)legacyMinimumContrast;
- (BOOL)quitWhenAllWindowsClosed;
- (BOOL)useUnevenTabs;
- (int)minTabWidth;
- (int)minCompactTabWidth;
- (int)optimumTabWidth;
- (float)hotkeyTermAnimationDuration;
- (NSString *)searchCommand;
- (Profile *)handlerBookmarkForURL:(NSString *)url;
- (int)numberOfRowsInTableView: (NSTableView *)aTableView;
- (NSString*)keyComboAtIndex:(int)rowIndex originator:(id)originator;
- (NSDictionary*)keyInfoAtIndex:(int)rowIndex originator:(id)originator;
- (NSString*)formattedKeyCombinationForRow:(int)rowIndex originator:(id)originator;
- (NSString*)formattedActionForRow:(int)rowIndex originator:(id)originator;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex;
- (void)_updateFontsDisplay;
- (void)updateBookmarkFields:(NSDictionary *)dict  ;
- (void)_commonDisplaySelectFont:(id)sender;
- (IBAction)displaySelectFont:(id)sender;
- (void)changeFont:(id)fontManager;
- (NSString*)_chooseBackgroundImage;
- (IBAction)browseCustomFolder:(id)sender;
- (BOOL)prefsDifferFromRemote;
- (NSString *)remotePrefsLocation;
- (IBAction)pushToCustomFolder:(id)sender;
- (BOOL)customFolderChanged;
- (IBAction)bookmarkSettingChanged:(id)sender;
- (IBAction)copyToProfile:(id)sender;
- (IBAction)bookmarkUrlSchemeHandlerChanged:(id)sender;
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;
- (IBAction)showGlobalTabView:(id)sender;
- (IBAction)showAppearanceTabView:(id)sender;
- (IBAction)showBookmarksTabView:(id)sender;
- (IBAction)showKeyboardTabView:(id)sender;
- (IBAction)showArrangementsTabView:(id)sender;
- (IBAction)showMouseTabView:(id)sender;
- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme;
- (void)disconnectHandlerForScheme:(NSString*)scheme;
- (IBAction)closeWindow:(id)sender;
- (IBAction)selectLogDir:(id)sender;
- (void)controlTextDidChange:(NSNotification *)aNotification;
- (void)textDidChange:(NSNotification *)aNotification;
- (BOOL)onScreen;
- (NSTextField*)shortcutKeyTextField;
- (void)shortcutKeyDown:(NSEvent*)event;
- (void)hotkeyKeyDown:(NSEvent*)event;
- (void)disableHotkey;
- (void)updateValueToSend;
- (IBAction)actionChanged:(id)sender;
- (NSWindow*)keySheet;
- (IBAction)addNewMapping:(id)sender;
- (IBAction)removeMapping:(id)sender;
- (IBAction)globalRemoveMapping:(id)sender;
- (void)setKeyMappingsToPreset:(NSString*)presetName;
- (IBAction)presetKeyMappingsItemSelected:(id)sender;
- (void)_loadPresetColors:(NSString*)presetName;
- (void)loadColorPreset:(id)sender;
- (IBAction)addBookmark:(id)sender;
- (IBAction)removeBookmark:(id)sender;
- (IBAction)duplicateBookmark:(id)sender;
- (IBAction)setAsDefault:(id)sender;
- (NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(NSInteger *)selectedIndex;
- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent;
- (void)profileTableSelectionDidChange:(id)profileTable;
- (void)profileTableSelectionWillChange:(id)profileTable;
- (void)profileTableRowSelected:(id)profileTable;
- (void)showBookmarks;
- (void)openToBookmark:(NSString*)guid;
- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell representedObjectForEditingString:(NSString *)editingString;
- (void)underlyingBookmarkDidChange;
- (int)openTmuxWindowsIn;
- (BOOL)autoHideTmuxClientSession;
- (int)tmuxDashboardLimit;
- (IBAction)openCopyBookmarks:(id)sender;
- (IBAction)copyBookmarks:(id)sender;
- (IBAction)cancelCopyBookmarks:(id)sender;
- (void)copyAttributes:(BulkCopySettings)attributes fromBookmark:(NSString*)guid toBookmark:(NSString*)destGuid;

- (int)control;
- (int)leftOption;
- (int)rightOption;
- (int)leftCommand;
- (int)rightCommand;
- (BOOL)isAnyModifierRemapped;
- (int)switchTabModifier;
- (int)switchWindowModifier;

- (BOOL)remappingDisabledTemporarily;
- (BOOL)hotkeyTogglesWindow;
- (BOOL)dockIconTogglesWindow;
- (Profile*)hotkeyBookmark;

- (BOOL)importColorPresetFromFile:(NSString*)filename;

@end

@interface PreferencePanel (KeyValueCoding)
- (BOOL)haveJobsForCurrentBookmark;
- (void)setHaveJobsForCurrentBookmark:(BOOL)value;

@end
