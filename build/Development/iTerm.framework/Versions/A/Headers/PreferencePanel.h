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

#define OPT_NORMAL 0
#define OPT_META   1
#define OPT_ESC    2

@class iTermController;
@class TreeNode;

typedef enum { CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX } ITermCursorType;

@interface PreferencePanel : NSWindowController
{
    
	IBOutlet NSPopUpButton *windowStyle;
	IBOutlet NSPopUpButton *tabPosition;
    IBOutlet NSOutlineView *urlHandlerOutline;
	IBOutlet NSTableView *urlTable;
    IBOutlet NSButton *selectionCopiesText;
	IBOutlet NSButton *middleButtonPastesFromClipboard;
    IBOutlet id hideTab;
    IBOutlet id promptOnClose;
    IBOutlet id onlyWhenMoreTabs;
    IBOutlet NSButton *focusFollowsMouse;
	IBOutlet NSTextField *wordChars;
	IBOutlet NSButton *enableBonjour;
    IBOutlet NSButton *enableGrowl;
    IBOutlet NSButton *cmdSelection;
	IBOutlet NSButton *maxVertically;
	IBOutlet NSButton *useCompactLabel;
    IBOutlet NSButton *openBookmark;
    IBOutlet NSSlider *refreshRate;
	IBOutlet NSButton *quitWhenAllWindowsClosed;
    IBOutlet NSButton *checkUpdate;
	IBOutlet NSMatrix *cursorType;
	IBOutlet NSButton *useBorder;
	IBOutlet NSButton *hideScrollbar;
    IBOutlet NSButton *checkTestRelease;
	
    NSUserDefaults *prefs;

	int defaultWindowStyle;
    BOOL defaultCopySelection;
	BOOL defaultPasteFromClipboard;
    BOOL defaultHideTab;
    int defaultTabViewType;
    BOOL defaultPromptOnClose;
    BOOL defaultOnlyWhenMoreTabs;
    BOOL defaultFocusFollowsMouse;
	BOOL defaultEnableBonjour;
	BOOL defaultEnableGrowl;
	BOOL defaultCmdSelection;
	BOOL defaultMaxVertically;
    BOOL defaultUseCompactLabel;
    BOOL defaultOpenBookmark;
    int  defaultRefreshRate;
	NSString *defaultWordChars;
    BOOL defaultQuitWhenAllWindowsClosed;
	BOOL defaultCheckUpdate;
	BOOL defaultUseBorder;
	BOOL defaultHideScrollbar;
	BOOL defaultCheckTestRelease;
	ITermCursorType defaultCursorType;
	
	// url handler stuff
	NSMutableArray *urlTypes;
	NSMutableDictionary *urlHandlers;
}


+ (PreferencePanel*)sharedInstance;

+ (BOOL) migratePreferences;
- (void) readPreferences;
- (void) savePreferences;

- (IBAction)settingChanged:(id)sender;
- (IBAction)connectURL:(id)sender;

- (void)run;


- (BOOL) copySelection;
- (void) setCopySelection: (BOOL) flag;
- (BOOL) pasteFromClipboard;
- (void) setPasteFromClipboard: (BOOL) flag;
- (BOOL) hideTab;
- (NSTabViewType) tabViewType;
- (int) windowStyle;
- (void) setTabViewType: (NSTabViewType) type;
- (BOOL) promptOnClose;
- (BOOL) onlyWhenMoreTabs;
- (BOOL) focusFollowsMouse;
- (BOOL) enableBonjour;
- (BOOL) enableGrowl;
- (BOOL) cmdSelection;
- (BOOL) maxVertically;
- (BOOL) useCompactLabel;
- (BOOL) openBookmark;
- (BOOL) useBorder;
- (BOOL) hideScrollbar;
- (int)  refreshRate;
- (NSString *) wordChars;
- (BOOL) quitWhenAllWindowsClosed;
- (BOOL) checkTestRelease;
- (ITermCursorType) cursorType;
- (TreeNode *) handlerBookmarkForURL:(NSString *)url;

// Hidden preferences
- (BOOL) useUnevenTabs;
- (int) minTabWidth;
- (int) minCompactTabWidth;
- (int) optimumTabWidth;
- (NSString *) searchCommand;

@end

@interface PreferencePanel (Private)

@end
