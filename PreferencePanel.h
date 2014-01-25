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
#import "PTYTextViewDataSource.h"

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

@interface PreferencePanel : NSWindowController <
    ProfileListViewDelegate,
    TriggerDelegate,
    SmartSelectionDelegate,
    NSTokenFieldDelegate,
    NSWindowDelegate,
    NSTextFieldDelegate,
    NSMenuDelegate>

@property(nonatomic, readonly) NSString *currentProfileGuid;

+ (PreferencePanel*)sharedInstance;
+ (PreferencePanel*)sessionsInstance;
+ (BOOL)migratePreferences;
+ (BOOL)loadingPrefsFromCustomFolder;
+ (void)populatePopUpButtonWithBookmarks:(NSPopUpButton*)button selectedGuid:(NSString*)selectedGuid;

- (void)openToBookmark:(NSString*)guid;

- (BOOL)loadPrefs;
- (void)updateBookmarkFields:(NSDictionary *)dict;

- (void)triggerChanged:(TriggerController *)triggerController;
- (void)smartSelectionChanged:(SmartSelectionController *)smartSelectionController;

- (void)awakeFromNib;
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
- (IBAction)closeKeyMapping:(id)sender;
- (IBAction)settingChanged:(id)sender;
- (IBAction)pushToCustomFolder:(id)sender;
- (IBAction)bookmarkSettingChanged:(id)sender;
- (IBAction)copyToProfile:(id)sender;
- (IBAction)bookmarkUrlSchemeHandlerChanged:(id)sender;
- (IBAction)showGlobalTabView:(id)sender;
- (IBAction)showAppearanceTabView:(id)sender;
- (IBAction)showBookmarksTabView:(id)sender;
- (IBAction)showKeyboardTabView:(id)sender;
- (IBAction)showArrangementsTabView:(id)sender;
- (IBAction)showMouseTabView:(id)sender;
- (IBAction)closeWindow:(id)sender;
- (IBAction)selectLogDir:(id)sender;
- (IBAction)actionChanged:(id)sender;
- (IBAction)addNewMapping:(id)sender;
- (IBAction)removeMapping:(id)sender;
- (IBAction)globalRemoveMapping:(id)sender;
- (IBAction)presetKeyMappingsItemSelected:(id)sender;
- (IBAction)toggleTags:(id)sender;
- (IBAction)addBookmark:(id)sender;
- (IBAction)removeBookmark:(id)sender;
- (IBAction)duplicateBookmark:(id)sender;
- (IBAction)setAsDefault:(id)sender;
- (IBAction)openCopyBookmarks:(id)sender;
- (IBAction)copyBookmarks:(id)sender;
- (IBAction)cancelCopyBookmarks:(id)sender;

- (BOOL)keySheetIsOpen;
- (WindowArrangements *)arrangements;
- (void)savePreferences;
- (void)run;
- (float)fsTabDelay;
- (BOOL)trimTrailingWhitespace;
- (int)modifierTagToMask:(int)tag;
- (BOOL)allowClipboardAccess;
- (BOOL)copySelection;
- (BOOL)copyLastNewline;
- (BOOL)legacyPasteFromClipboard;
- (BOOL)pasteFromClipboard;
- (BOOL)legacyThreeFingerEmulatesMiddle;
- (BOOL)threeFingerEmulatesMiddle;
- (BOOL)hideTab;
- (void)setTabViewType:(NSTabViewType)type;
- (NSTabViewType)tabViewType;
- (int)windowStyle;
- (BOOL)promptOnQuit;
- (BOOL)onlyWhenMoreTabs;
- (BOOL)focusFollowsMouse;
- (BOOL)tripleClickSelectsFullLines;
// Returns true if ANY profile has growl enabled (preserves interface from back
// when there was a global growl setting as well as a per-profile setting).
- (BOOL)enableGrowl;
- (BOOL)cmdSelection;
- (BOOL)optionClickMovesCursor;
- (BOOL)passOnControlLeftClick;
- (BOOL)maxVertically;
- (BOOL)closingHotkeySwitchesSpaces;
- (BOOL)useCompactLabel;
- (BOOL)hideActivityIndicator;
- (BOOL)highlightTabLabels;
- (BOOL)hideMenuBarInFullscreen;
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
- (short)hotkeyChar;  // Nonzero if hotkey is set validly
- (int)hotkeyCode;
- (int)hotkeyModifiers;
- (NSTextField*)hotkeyField;

- (BOOL)showWindowBorder;
- (BOOL)lionStyleFullscreen;
- (BOOL)dimInactiveSplitPanes;
- (BOOL)dimBackgroundWindows;
- (BOOL)animateDimming;
- (BOOL)dimOnlyText;
- (float)dimmingAmount;
- (BOOL)legacySmartCursorColor;
- (float)legacyMinimumContrast;
- (BOOL)quitWhenAllWindowsClosed;
- (BOOL)useUnevenTabs;
- (int)minTabWidth;
- (int)minCompactTabWidth;
- (int)optimumTabWidth;
- (BOOL)traditionalVisualBell;
- (float)hotkeyTermAnimationDuration;
- (NSString *)searchCommand;
- (Profile *)handlerBookmarkForURL:(NSString *)url;
- (void)changeFont:(id)fontManager;
- (BOOL)prefsDifferFromRemote;
- (NSString *)remotePrefsLocation;
- (BOOL)customFolderChanged;
- (BOOL)onScreen;
- (NSTextField*)shortcutKeyTextField;
- (void)shortcutKeyDown:(NSEvent*)event;
- (void)hotkeyKeyDown:(NSEvent*)event;
- (void)disableHotkey;
- (NSWindow*)keySheet;
- (void)showBookmarks;
- (void)underlyingBookmarkDidChange;
- (int)openTmuxWindowsIn;
- (BOOL)autoHideTmuxClientSession;
- (int)tmuxDashboardLimit;

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
- (NSTimeInterval)timeBetweenBlinks;

- (Profile*)hotkeyBookmark;

- (BOOL)importColorPresetFromFile:(NSString*)filename;

@end
