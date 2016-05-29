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
typedef NS_ENUM(NSInteger, iTermOpenTmuxWindowsMode) {
    kOpenTmuxWindowsAsNativeWindows = 0,
    kOpenTmuxWindowsAsNativeTabsInNewWindow = 1,
    kOpenTmuxWindowsAsNativeTabsInExistingWindow = 2
};

// Values for kPreferenceKeyTabStyle. Do not alter values in this enumeration as they are saved in the preferences.
typedef NS_ENUM(int, iTermPreferencesTabStyle) {
    TAB_STYLE_LIGHT = 0,
    TAB_STYLE_DARK = 1,
    TAB_STYLE_LIGHT_HIGH_CONTRAST = 2,
    TAB_STYLE_DARK_HIGH_CONTRAST = 3
};

// Values for kPreferenceKeyTabPosition (corresponds to tags in control).
#define TAB_POSITION_TOP PSMTab_TopTab
#define TAB_POSITION_BOTTOM PSMTab_BottomTab
#define TAB_POSITION_LEFT PSMTab_LeftTab

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

    kPreferenceModifierTagNone = 9,  // No modifier assigned (not available for all popups)
};

// General
extern NSString *const kPreferenceKeyOpenBookmark;
extern NSString *const kPreferenceKeyOpenArrangementAtStartup;
extern NSString *const kPreferenceKeyOpenNoWindowsAtStartup;
extern NSString *const kPreferenceKeyQuitWhenAllWindowsClosed;
extern NSString *const kPreferenceKeyConfirmClosingMultipleTabs;
extern NSString *const kPreferenceKeyPromptOnQuit;
extern NSString *const kPreferenceKeyInstantReplayMemoryMegabytes;
extern NSString *const kPreferenceKeySavePasteAndCommandHistory;
extern NSString *const kPreferenceKeyAddBonjourHostsToProfiles;
extern NSString *const kPreferenceKeyCheckForUpdatesAutomatically;
extern NSString *const kPreferenceKeyCheckForTestReleases;
extern NSString *const kPreferenceKeyLoadPrefsFromCustomFolder;
extern NSString *const kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection;
extern NSString *const kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection;
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
extern NSString *const kPreferenceKeyTabStyle;
extern NSString *const kPreferenceKeyTabPosition;
extern NSString *const kPreferenceKeyHideTabBar;
extern NSString *const kPreferenceKeyHideTabNumber;
extern NSString *const kPreferenceKeyHideTabCloseButton;
extern NSString *const kPreferenceKeyHideTabActivityIndicator;
extern NSString *const kPreferenceKeyShowNewOutputIndicator;
extern NSString *const kPreferenceKeyShowPaneTitles;
extern NSString *const kPreferenceKeyHideMenuBarInFullscreen;
extern NSString *const kPreferenceKeyFlashTabBarInFullscreen;
extern NSString *const kPreferenceKeyShowWindowNumber;
extern NSString *const kPreferenceKeyShowJobName;
extern NSString *const kPreferenceKeyShowProfileName;
extern NSString *const kPreferenceKeyDimOnlyText;
extern NSString *const kPreferenceKeyDimmingAmount;
extern NSString *const kPreferenceKeyDimInactiveSplitPanes;
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
extern NSString *const kPreferenceKeySwitchPaneModifier;
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
extern NSString *const kPreferenceKeyDoubleClickPerformsSmartSelection;

// Not in prefs
// Stores the last CFBundleVersion run.
extern NSString *const kPreferenceKeyAppVersion;

// Auto-command history (set through menu)
extern NSString *const kPreferenceAutoCommandHistory;

extern NSString *const kPreferenceKeyPasteSpecialChunkSize;
extern NSString *const kPreferenceKeyPasteSpecialChunkDelay;
extern NSString *const kPreferenceKeyPasteSpecialSpacesPerTab;
extern NSString *const kPreferenceKeyPasteSpecialTabTransform;
extern NSString *const kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash;
extern NSString *const kPreferenceKeyPasteSpecialConvertUnicodePunctuation;
extern NSString *const kPreferenceKeyPasteSpecialConvertDosNewlines;
extern NSString *const kPreferenceKeyPasteSpecialRemoveControlCodes;
extern NSString *const kPreferenceKeyPasteSpecialBracketedPasteMode;
extern NSString *const kPreferencesKeyPasteSpecialUseRegexSubstitution;
extern NSString *const kPreferencesKeyPasteSpecialRegex;
extern NSString *const kPreferencesKeyPasteSpecialSubstitution;
extern NSString *const kPreferenceKeyLeftTabBarWidth;

extern NSString *const kPreferenceKeyPasteWarningNumberOfSpacesPerTab;

extern NSString *const kPreferenceKeyShowFullscreenTabBar;

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

+ (NSUInteger)unsignedIntegerForKey:(NSString *)key;
+ (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key;

+ (double)floatForKey:(NSString *)key;
+ (void)setFloat:(double)value forKey:(NSString *)key;

+ (double)doubleForKey:(NSString *)key;
+ (void)setDouble:(double)value forKey:(NSString *)key;

+ (NSString *)stringForKey:(NSString *)key;
+ (void)setString:(NSString *)value forKey:(NSString *)key;

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key;
+ (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type;

// When the value held by |key| changes, the block is invoked with the old an
// new values. Either may be nil, but they are guaranteed to be different by
// value equality with isEqual:.
+ (void)addObserverForKey:(NSString *)key block:(void (^)(id before, id after))block;

+ (NSUInteger)maskForModifierTag:(iTermPreferencesModifierTag)tag;

@end
