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
#import <iTerm/BookmarkModel.h>
#import "BookmarkListView.h"

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

@class iTermController;

typedef enum { CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX } ITermCursorType;

@interface PreferencePanel : NSWindowController <BookmarkTableDelegate>
{
    BookmarkModel* dataSource;
    BOOL oneBookmarkMode;

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

    // Copy to clipboard on selection
    IBOutlet NSButton *selectionCopiesText;
    BOOL defaultCopySelection;

    // Middle button paste from clipboard
    IBOutlet NSButton *middleButtonPastesFromClipboard;
    BOOL defaultPasteFromClipboard;

    // Hide tab bar when there is only one session
    IBOutlet id hideTab;
    BOOL defaultHideTab;

    // Warn me when a session closes
    IBOutlet id promptOnClose;
    BOOL defaultPromptOnClose;

    // Warn when quitting
    IBOutlet id promptOnQuit;
    BOOL defaultPromptOnQuit;

    // only when multiple sessions close
    IBOutlet id onlyWhenMoreTabs;
    BOOL defaultOnlyWhenMoreTabs;

    // Focus follows mouse
    IBOutlet NSButton *focusFollowsMouse;
    BOOL defaultFocusFollowsMouse;

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

    // Window border
    IBOutlet NSButton* showWindowBorder;
    BOOL defaultShowWindowBorder;

    // hide scrollbar and resize
    IBOutlet NSButton *hideScrollbar;
    BOOL defaultHideScrollbar;

    // smart window placement
    IBOutlet NSButton *smartPlacement;
    BOOL defaultSmartPlacement;

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
    IBOutlet NSTabViewItem* keyboardTabViewItem;
    IBOutlet NSToolbarItem* bookmarksToolbarItem;
    IBOutlet NSTabViewItem* bookmarksTabViewItem;
    NSString* globalToolbarId;
    NSString* appearanceToolbarId;
    NSString* keyboardToolbarId;
    NSString* bookmarksToolbarId;

    // url handler stuff
    NSMutableDictionary *urlHandlersByGuid;

    // Bookmarks -----------------------------
    IBOutlet BookmarkListView *bookmarksTableView;
    IBOutlet NSTableColumn *shellImageColumn;
    IBOutlet NSTableColumn *nameShortcutColumn;
    IBOutlet NSButton *removeBookmarkButton;
    IBOutlet NSButton *addBookmarkButton;

    // General tab
    IBOutlet NSTextField *bookmarkName;
    IBOutlet NSPopUpButton *bookmarkShortcutKey;
    IBOutlet NSMatrix *bookmarkCommandType;
    IBOutlet NSTextField *bookmarkCommand;
    IBOutlet NSMatrix *bookmarkDirectoryType;
    IBOutlet NSTextField *bookmarkDirectory;
    IBOutlet NSTextField *bookmarkShortcutKeyLabel;
    IBOutlet NSTextField *bookmarkShortcutKeyModifiersLabel;
    IBOutlet NSTextField *bookmarkTagsLabel;
    IBOutlet NSTextField *bookmarkCommandLabel;
    IBOutlet NSTextField *bookmarkDirectoryLabel;
    IBOutlet NSTextField *bookmarkUrlSchemesHeaderLabel;
    IBOutlet NSTextField *bookmarkUrlSchemesLabel;
    IBOutlet NSPopUpButton* bookmarkUrlSchemes;
    IBOutlet NSButton* copyToProfileButton;

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
    IBOutlet NSButton* blur;
    IBOutlet NSButton* asciiAntiAliased;
    IBOutlet NSButton* nonasciiAntiAliased;
    IBOutlet NSButton* backgroundImage;
    NSString* backgroundImageFilename;
    IBOutlet NSImageView* backgroundImagePreview;
    IBOutlet NSTextField* displayFontsLabel;
    IBOutlet NSButton* displayRegularFontButton;
    IBOutlet NSButton* displayNAFontButton;

    NSFont* normalFont;
    NSFont *nonAsciiFont;
    BOOL changingNAFont; // true if font dialog is currently modifying the non-ascii font

    // Terminal tab
    IBOutlet NSButton* disableWindowResizing;
    IBOutlet NSButton* syncTitle;
    IBOutlet NSButton* closeSessionsOnEnd;
    IBOutlet NSButton* nonAsciiDoubleWidth;
    IBOutlet NSButton* silenceBell;
    IBOutlet NSButton* visualBell;
    IBOutlet NSButton* flashingBell;
    IBOutlet NSButton* xtermMouseReporting;
    IBOutlet NSButton* disableSmcupRmcup;
    IBOutlet NSButton* scrollbackWithStatusBar;
    IBOutlet NSButton* bookmarkGrowlNotifications;
    IBOutlet NSTextField* scrollbackLines;
    IBOutlet NSButton* unlimitedScrollback;
    IBOutlet NSComboBox* terminalType;
    IBOutlet NSButton* sendCodeWhenIdle;
    IBOutlet NSTextField* idleCode;
    IBOutlet NSPopUpButton* characterEncoding;

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

    // Copy Bookmark Settings...
    IBOutlet NSTextField* bulkCopyLabel;
    IBOutlet NSPanel* copyPanel;
    IBOutlet NSButton* copyColors;
    IBOutlet NSButton* copyDisplay;
    IBOutlet NSButton* copyTerminal;
    IBOutlet NSButton* copyWindow;
    IBOutlet NSButton* copyKeyboard;
    IBOutlet BookmarkListView* copyTo;
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
}

typedef enum { BulkCopyColors, BulkCopyDisplay, BulkCopyWindow, BulkCopyTerminal, BulkCopyKeyboard } BulkCopySettings;

+ (PreferencePanel*)sharedInstance;
+ (PreferencePanel*)sessionsInstance;
+ (BOOL)migratePreferences;
- (id)initWithDataSource:(BookmarkModel*)model userDefaults:(NSUserDefaults*)userDefaults;
- (void)setOneBokmarkOnly;
- (void)awakeFromNib;
- (void)handleWindowWillCloseNotification:(NSNotification *)notification;
- (void)genericCloseSheet:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)editKeyMapping:(id)sender;
- (IBAction)saveKeyMapping:(id)sender;
- (BOOL)keySheetIsOpen;
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
- (BOOL)advancedFontRendering;
- (float)strokeThickness;
- (float)fsTabDelay;
- (int)modifierTagToMask:(int)tag;
- (void)windowWillLoad;
- (void)windowWillClose:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (BOOL)copySelection;
- (void)setCopySelection:(BOOL)flag;
- (BOOL)pasteFromClipboard;
- (void)setPasteFromClipboard:(BOOL)flag;
- (BOOL)hideTab;
- (void)setTabViewType:(NSTabViewType)type;
- (NSTabViewType)tabViewType;
- (int)windowStyle;
- (BOOL)promptOnClose;
- (BOOL)promptOnQuit;
- (BOOL)onlyWhenMoreTabs;
- (BOOL)focusFollowsMouse;
- (BOOL)enableBonjour;
// Returns true if ANY profile has growl enabled (preserves interface from back
// when there was a global growl setting as well as a per-profile setting).
- (BOOL)enableGrowl;
- (BOOL)cmdSelection;
- (BOOL)passOnControlLeftClick;
- (BOOL)maxVertically;
- (BOOL)closingHotkeySwitchesSpaces;
- (BOOL)useCompactLabel;
- (BOOL)highlightTabLabels;
- (BOOL)openBookmark;
- (NSString *)wordChars;
- (ITermCursorType)legacyCursorType;
- (BOOL)hideScrollbar;
- (BOOL)smartPlacement;
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
- (BOOL)dimInactiveSplitPanes;
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
- (Bookmark *)handlerBookmarkForURL:(NSString *)url;
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
- (IBAction)bookmarkSettingChanged:(id)sender;
- (IBAction)copyToProfile:(id)sender;
- (IBAction)bookmarkUrlSchemeHandlerChanged:(id)sender;
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;
- (IBAction)showGlobalTabView:(id)sender;
- (IBAction)showAppearanceTabView:(id)sender;
- (IBAction)showBookmarksTabView:(id)sender;
- (IBAction)showKeyboardTabView:(id)sender;
- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme;
- (void)disconnectHandlerForScheme:(NSString*)scheme;
- (IBAction)closeWindow:(id)sender;
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
- (NSMenu*)bookmarkTable:(id)bookmarkTable menuForEvent:(NSEvent*)theEvent;
- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable;
- (void)bookmarkTableSelectionWillChange:(id)aBookmarkTableView;
- (void)bookmarkTableRowSelected:(id)bookmarkTable;
- (void)showBookmarks;
- (void)openToBookmark:(NSString*)guid;
- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell representedObjectForEditingString:(NSString *)editingString;
- (void)underlyingBookmarkDidChange;

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
- (Bookmark*)hotkeyBookmark;

@end

