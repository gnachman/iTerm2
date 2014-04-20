//
//  iTermPreferences.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Foundation/Foundation.h>
#import "PreferenceInfo.h"
#import "PSMTabBarControl.h"

// Values for kPreferenceKeyOpenTmuxWindowsIn (corresponds to tags in control).
#define OPEN_TMUX_WINDOWS_IN_WINDOWS 0
#define OPEN_TMUX_WINDOWS_IN_TABS 1

// Values for kPreferenceKeyWindowStyle (corresponds to tags in control).
typedef NS_ENUM(int, iTermPreferencesTabStyle) {
    TAB_STYLE_METAL = 0,
    TAB_STYLE_AQUA = 1,
    TAB_STYLE_UNIFIED = 2,
    TAB_STYLE_ADIUM = 3
};

extern NSString *const kTabStyleMetal;
extern NSString *const kTabStyleAqua;
extern NSString *const kTabStyleUnified;
extern NSString *const kTabStyleAdium;

// Values for kPreferenceKeyTabPosition (corresponds to tags in control).
#define TAB_POSITION_TOP PSMTab_TopTab
#define TAB_POSITION_BOTTOM PSMTab_BottomTab

// Values for kPreferenceKeyXxxRemapping (corresponds to tags in controls).
typedef NS_ENUM(int, iTermPreferencesModifierTag) {
    kPreferencesModifierTagControl = 1,
    kPreferencesModifierTagLeftOption = 2,
    kPreferencesModifierTagRightOption = 3,
    kPreferencesModifierTagEitherCommand = 4,
    kPreferencesModifierTagEitherOption = 5,  // refers to any option key
    kPreferencesModifierTagCommandAndOption = 6,  // both cmd and opt at the same time
    kPreferencesModifierTagLeftCommand = 7,
    kPreferencesModifierTagRightCommand = 8,
};

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
extern NSString *const kPreferenceKeyDimmingAmount;
extern NSString *const kPreferenceKeyDimInactiveSplitPanes;
extern NSString *const kPreferenceKeyAnimateDimming;
extern NSString *const kPreferenceKeyShowWindowBorder;
extern NSString *const kPreferenceKeyHideScrollbar;
extern NSString *const kPreferenceKeyDisableFullscreenTransparencyByDefault;
extern NSString *const kPreferenceKeyDimBackgroundWindows;

// Keys
extern NSString *const kPreferenceKeyControlRemapping;
extern NSString *const kPreferenceKeyLeftOptionRemapping;
extern NSString *const kPreferenceKeyRightOptionRemapping;
extern NSString *const kPreferenceKeyLeftCommandRemapping;
extern NSString *const kPreferenceKeyRightCommandRemapping;
extern NSString *const kPreferenceKeySwitchTabModifier;
extern NSString *const kPreferenceKeySwitchWindowModifier;
extern NSString *const kPreferenceKeyHotkeyEnabled;
extern NSString *const kPreferenceKeyHotKeyCode;
extern NSString *const kPreferenceKeyHotkeyCharacter;
extern NSString *const kPreferenceKeyHotkeyModifiers;
extern NSString *const kPreferenceKeyHotKeyTogglesWindow;
extern NSString *const kPreferenceKeyHotkeyProfileGuid;
extern NSString *const kPreferenceKeyHotkeyAutoHides;

// Pointer
extern NSString *const kPreferenceKeyCmdClickOpensURLs;
extern NSString *const kPreferenceKeyControlLeftClickBypassesContextMenu;
extern NSString *const kPreferenceKeyOptionClickMovesCursor;
extern NSString *const kPreferenceKeyThreeFingerEmulatesMiddle;
extern NSString *const kPreferenceKeyFocusFollowsMouse;
extern NSString *const kPreferenceKeyTripleClickSelectsFullWrappedLines;

// Not in prefs
// Stores the last CFBundleVersion run.
extern NSString *const kPreferenceKeyAppVersion;

// Auto-command history (set through menu)
extern NSString *const kPreferenceAutoCommandHistory;

@interface iTermPreferences : NSObject

// This should be called early during startup to set user defaults keys that fix problematic Apple
// settings and update the last-used version number.
+ (void)initializeUserDefaults;

+ (void)setObject:(id)object forKey:(NSString *)key;
+ (NSObject *)objectForKey:(NSString *)key;

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
+ (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type;

// When the value held by |key| changes, the block is invoked with the old an
// new values. Either may be nil, but they are guaranteed to be different by
// value equality with isEqual:.
+ (void)addObserverForKey:(NSString *)key block:(void (^)(id before, id after))block;

// Class method to copy old preferences file, iTerm.plist or net.sourceforge.iTerm.plist, to new
// preferences file, com.googlecode.iterm2.plist
+ (BOOL)migratePreferences;

+ (NSUInteger)maskForModifierTag:(iTermPreferencesModifierTag)tag;

@end
