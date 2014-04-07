//
//  iTermPreferences.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Foundation/Foundation.h>
#import "PSMTabBarControl.h"

// Values for kPreferenceKeyOpenTmuxWindowsIn (corresponds to tags in control).
#define OPEN_TMUX_WINDOWS_IN_WINDOWS 0
#define OPEN_TMUX_WINDOWS_IN_TABS 1

// Values for kPreferenceKeyWindowStyle (corresponds to tags in control).
#define TAB_STYLE_METAL 0
#define TAB_STYLE_AQUA 1
#define TAB_STYLE_UNIFIED 2
#define TAB_STYLE_ADIUM 3

// Values for kPreferenceKeyTabPosition (correspond to tags in control).
#define TAB_POSITION_TOP PSMTab_TopTab
#define TAB_POSITION_BOTTOM PSMTab_BottomTab

// General
extern NSString *const kPreferenceKeyOpenBookmark;
extern NSString *const kPreferenceKeyOpenArrangementAtStartup;
extern NSString *const kPreferenceKeyQuitWhenAllWindowsClosed;
extern NSString *const kPreferenceKeyConfirmClosingMultipleTabs;
extern NSString *const kPreferenceKeyPromptOnQuit;
extern NSString *const kPreferenceKeyInstantReplayMemoryMegabytes;
extern NSString *const kPreferenceKeySavePasteAndCommandHistory;
extern NSString *const kPreferenceKeyAddBonjourHostsToProfiles;
extern NSString *const kPreferenceKeyCheckForUpdatesAutomatically;
extern NSString *const kPreferenceKeyCheckForTestReleases;
extern NSString *const kPreferenceKeyLoadPrefsFromCustomFolder;
extern NSString *const kPreferenceKeyCustomFolder;  // Path/URL to location with prefs. Path may have ~ in it.
extern NSString *const kPreferenceKeySelectionCopiesText;
extern NSString *const kPreferenceKeyCopyLastNewline;
extern NSString *const kPreferenceKeyAllowClipboardAccessFromTerminal;
extern NSString *const kPreferenceKeyCharactersConsideredPartOfAWordForSelection;
extern NSString *const kPreferenceKeySmartWindowPlacement;
extern NSString *const kPreferenceKeyAdjustWindowForFontSizeChange;
extern NSString *const kPreferenceKeyMaximizeVerticallyOnly;
extern NSString *const kPreferenceKeyLionStyleFullscren;
extern NSString *const kPreferenceKeyOpenTmuxWindowsIn;
extern NSString *const kPreferenceKeyTmuxDashboardLimit;
extern NSString *const kPreferenceKeyAutoHideTmuxClientSession;

// Appearance
extern NSString *const kPreferenceKeyWindowStyle;
extern NSString *const kPreferenceKeyTabPosition;
extern NSString *const kPreferenceKeyHideTabBar;
extern NSString *const kPreferenceKeyHighlightTabLabels;
extern NSString *const kPreferenceKeyHideTabNumber;
extern NSString *const kPreferenceKeyHideTabCloseButton;
extern NSString *const kPreferenceKeyHideTabActivityIndicator;
extern NSString *const kPreferenceKeyTimeToHoldCmdToShowTabsInFullScreen;
extern NSString *const kPreferenceKeyShowPaneTitles;
extern NSString *const kPreferenceKeyHideMenuBarInFullscreen;
extern NSString *const kPreferenceKeyShowWindowNumber;
extern NSString *const kPreferenceKeyShowJobName;
extern NSString *const kPreferenceKeyShowProfileName;
extern NSString *const kPreferenceKeyDimOnlyText;

@interface iTermPreferences : NSObject

+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

+ (int)intForKey:(NSString *)key;
+ (void)setInt:(int)value forKey:(NSString *)key;

+ (double)floatForKey:(NSString *)key;
+ (void)setFloat:(double)value forKey:(NSString *)key;

+ (NSString *)stringForKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;

// When the value held by |key| changes, the block is invoked with the old an
// new values. Either may be nil, but they are guaranteed to be different by
// value equality with isEqual:.
+ (void)addObserverForKey:(NSString *)key block:(void (^)(id before, id after))block;

@end
