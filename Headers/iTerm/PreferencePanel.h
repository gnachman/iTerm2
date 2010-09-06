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

    IBOutlet BookmarkListView* bookmarksForUrlsTable;
    
    IBOutlet NSTextField* tagFilter;
    
    // List of URL schemes.
	IBOutlet NSTableView *urlTable;
    
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

    // only when multiple sessions close
    IBOutlet id onlyWhenMoreTabs;
    BOOL defaultOnlyWhenMoreTabs;
    
    // Focus follows mouse
    IBOutlet NSButton *focusFollowsMouse;
    BOOL defaultFocusFollowsMouse;

    // Characters considered part of word
	IBOutlet NSTextField *wordChars;
	NSString *defaultWordChars;

    // Enable bonjour
	IBOutlet NSButton *enableBonjour;
	BOOL defaultEnableBonjour;

    // Enable growl notifications
    IBOutlet NSButton *enableGrowl;
	BOOL defaultEnableGrowl;

    // cmd-click to launch url
    IBOutlet NSButton *cmdSelection;
	BOOL defaultCmdSelection;

    // Zoom vertically only
	IBOutlet NSButton *maxVertically;
	BOOL defaultMaxVertically;

    // use compact tab labels
	IBOutlet NSButton *useCompactLabel;
    BOOL defaultUseCompactLabel;
    
    // open bookmarks when iterm starts
    IBOutlet NSButton *openBookmark;
    BOOL defaultOpenBookmark;

    // display refresh rate
    IBOutlet NSSlider *refreshRate;
    int  defaultRefreshRate;

    // quit when all windows are closed
	IBOutlet NSButton *quitWhenAllWindowsClosed;
    BOOL defaultQuitWhenAllWindowsClosed;
    
    // check for updates automatically
    IBOutlet NSButton *checkUpdate;
	BOOL defaultCheckUpdate;

    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
	IBOutlet NSMatrix *cursorType;
	ITermCursorType defaultCursorType;

    IBOutlet NSButton *checkColorInvertedCursor;
	BOOL defaultColorInvertedCursor;

    // border at bottom
	IBOutlet NSButton *useBorder;
	BOOL defaultUseBorder;
    
    // hide scrollbar and resize
	IBOutlet NSButton *hideScrollbar;
	BOOL defaultHideScrollbar;

    // smart window placement
    IBOutlet NSButton *smartPlacement;
    BOOL defaultSmartPlacement;
    
    // prompt for test-release updates
    IBOutlet NSButton *checkTestRelease;
	BOOL defaultCheckTestRelease;
	
    IBOutlet NSView* bookmarksSettingsTabViewParent;
    
    NSUserDefaults *prefs;

    IBOutlet NSToolbar* toolbar;
    IBOutlet NSTabView* tabView;
    IBOutlet NSToolbarItem* globalToolbarItem;
	IBOutlet NSTabViewItem* globalTabViewItem;
    IBOutlet NSToolbarItem* bookmarksToolbarItem;
    IBOutlet NSTabViewItem* bookmarksTabViewItem;
    IBOutlet NSToolbarItem* advancedToolbarItem;
    IBOutlet NSTabViewItem* advancedTabViewItem;
    NSString* globalToolbarId;
    NSString* bookmarksToolbarId;
    NSString* advancedToolbarId;
    
	// url handler stuff
	NSMutableArray *urlTypes;
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
    
    // Display tab
	IBOutlet NSView *displayFontAccessoryView;
	IBOutlet NSSlider *displayFontSpacingWidth;
	IBOutlet NSSlider *displayFontSpacingHeight;
    IBOutlet NSTextField *columnsField;
    IBOutlet NSTextField *rowsField;
    IBOutlet NSTextField *normalFontField;
    IBOutlet NSTextField *nonAsciiFontField;
    
    IBOutlet NSButton* blinkingCursor;
    IBOutlet NSButton* disableBold;
    IBOutlet NSSlider *transparency;
    IBOutlet NSButton* blur;
    IBOutlet NSButton* antiAliasing;
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
    IBOutlet NSButton* xtermMouseReporting;
    IBOutlet NSButton* bookmarkGrowlNotifications;
    IBOutlet NSTextField* scrollbackLines;
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
    IBOutlet NSButton* removeMappingButton;
    IBOutlet NSTextField* escPlus;
    IBOutlet NSMatrix *optionKeySends;
    IBOutlet NSTokenField* tags;
    
    NSString* keyString;  // hexcode-hexcode rep of keystring in current sheet
    BOOL newMapping;  // true if the keymap sheet is open for adding a new entry
    
    // Copy from...
    IBOutlet BookmarkListView *copyFromBookmarks;
    IBOutlet NSPanel* copyFromView;
    IBOutlet NSPopUpButton* bookmarksPopup;
    NSString* copyTo;

}

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
- (BOOL)onlyWhenMoreTabs;
- (BOOL)focusFollowsMouse;
- (BOOL)enableBonjour;
- (BOOL)enableGrowl;
- (BOOL)cmdSelection;
- (BOOL)maxVertically;
- (BOOL)useCompactLabel;
- (BOOL)openBookmark;
- (int)refreshRate;
- (NSString *)wordChars;
- (ITermCursorType)cursorType;
- (BOOL)useBorder;
- (BOOL)hideScrollbar;
- (BOOL)smartPlacement;
- (BOOL)checkColorInvertedCursor;
- (BOOL)checkTestRelease;
- (BOOL)colorInvertedCursor;
- (BOOL)quitWhenAllWindowsClosed;
- (BOOL)useUnevenTabs;
- (int)minTabWidth;
- (int)minCompactTabWidth;
- (int)optimumTabWidth;
- (NSString *)searchCommand;
- (Bookmark *)handlerBookmarkForURL:(NSString *)url;
- (int)numberOfRowsInTableView: (NSTableView *)aTableView;
- (NSString*)keyComboAtIndex:(int)rowIndex;
- (NSDictionary*)keyInfoAtIndex:(int)rowIndex;
- (NSString*)formattedKeyCombinationForRow:(int)rowIndex;
- (NSString*)formattedActionForRow:(int)rowIndex;
- (NSString*)valueToSendForRow:(int)rowIndex;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex;
- (void)_updateFontsDisplay;
- (void)updateBookmarkFields:(NSDictionary *)dict  ;
- (void)_commonDisplaySelectFont:(id)sender;
- (IBAction)displaySelectFont:(id)sender;
- (void)changeFont:(id)fontManager;
- (NSString*)_chooseBackgroundImage;
- (IBAction)bookmarkSettingChanged:(id)sender;
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;
- (IBAction)showGlobalTabView:(id)sender;
- (IBAction)showBookmarksTabView:(id)sender;
- (IBAction)showAdvancedTabView:(id)sender;
- (IBAction)connectURL:(id)sender;
- (IBAction)closeWindow:(id)sender;
- (void)controlTextDidChange:(NSNotification *)aNotification;
- (void)textDidChange:(NSNotification *)aNotification;
- (BOOL)onScreen;
- (NSTextField*)shortcutKeyTextField;
- (void)shortcutKeyDown:(NSEvent*)event;
- (void)updateValueToSend;
- (IBAction)actionChanged:(id)sender;
- (NSWindow*)keySheet;
- (IBAction)addNewMapping:(id)sender;
- (IBAction)removeMapping:(id)sender;
- (void)setKeyMappingsToPreset:(NSString*)presetName;
- (IBAction)useBasicKeyMappings:(id)sender;
- (IBAction)useXtermKeyMappings:(id)sender;
- (void)_loadPresetColors:(NSString*)presetName;
- (IBAction)loadLightBackgroundPreset:(id)sender;
- (IBAction)loadDarkBackgroundPreset:(id)sender;
- (IBAction)addBookmark:(id)sender;
- (IBAction)removeBookmark:(id)sender;
- (IBAction)duplicateBookmark:(id)sender;
- (IBAction)setAsDefault:(id)sender;
- (NSArray *)tokenField:(NSTokenField *)tokenField completionsForSubstring:(NSString *)substring indexOfToken:(NSInteger)tokenIndex indexOfSelectedItem:(NSInteger *)selectedIndex;
- (void)bookmarkTableSelectionDidChange:(id)bookmarkTable;
- (void)bookmarkTableSelectionWillChange:(id)aBookmarkTableView;
- (void)bookmarkTableRowSelected:(id)bookmarkTable;
- (IBAction)doCopyFrom:(id)sender;
- (IBAction)cancelCopyFrom:(id)sender;
- (IBAction)openCopyFromColors:(id)sender;
- (IBAction)openCopyFromDisplay:(id)sender;
- (IBAction)openCopyFromTerminal:(id)sender;
- (IBAction)openCopyFromKeyboard:(id)sender;
- (void)showBookmarks;
- (void)openToBookmark:(NSString*)guid;
- (id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell representedObjectForEditingString:(NSString *)editingString;

@end

