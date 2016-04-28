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
#import "FutureMethods.h"
#import "ProfileModel.h"
#import "ProfileListView.h"
#import "PTYTextViewDataSource.h"
#import "SmartSelectionController.h"
#import "TriggerController.h"
#import "WindowArrangements.h"

extern NSString *const kRefreshTerminalNotification;
extern NSString *const kUpdateLabelsNotification;
extern NSString *const kKeyBindingsChangedNotification;
extern NSString *const kPreferencePanelDidUpdateProfileFields;
extern NSString *const kSessionProfileDidChange;  // Posted by a session when it changes to update the Get Info window.

#define OPT_NORMAL 0
#define OPT_META   1
#define OPT_ESC    2

// Constants for KEY_PROMPT_CLOSE
// Never prompt on close
#define PROMPT_NEVER 0
// Always prompt on close
#define PROMPT_ALWAYS 1
// Prompt on close if jobs (excluding some in a list) are running.
#define PROMPT_EX_JOBS 2

@class iTermController;
@class iTermSemanticHistoryPrefsController;
@class SmartSelectionController;
@class TriggerController;

void LoadPrefsFromCustomFolder(void);

@interface PreferencePanel : NSWindowController <
    ProfileListViewDelegate,
    NSTokenFieldDelegate,
    NSWindowDelegate,
    NSMenuDelegate>

@property(nonatomic, readonly) NSString *currentProfileGuid;

+ (instancetype)sharedInstance;
+ (instancetype)sessionsInstance;

- (void)openToProfileWithGuid:(NSString*)guid selectGeneralTab:(BOOL)selectGeneralTab;

- (IBAction)showGlobalTabView:(id)sender;
- (IBAction)showAppearanceTabView:(id)sender;
- (IBAction)showBookmarksTabView:(id)sender;
- (IBAction)showKeyboardTabView:(id)sender;
- (IBAction)showArrangementsTabView:(id)sender;
- (IBAction)showMouseTabView:(id)sender;

- (void)underlyingBookmarkDidChange;

- (WindowArrangements *)arrangements;
- (void)run;
// Returns true if ANY profile has growl enabled (preserves interface from back
// when there was a global growl setting as well as a per-profile setting).
- (NSTextField*)hotkeyField;

- (void)changeFont:(id)fontManager;
- (void)selectProfilesTab;

@end
