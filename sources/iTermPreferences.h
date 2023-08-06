//
//  iTermPreferences.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Foundation/Foundation.h>
#import "PreferenceInfo.h"

extern NSString *const iTermMetalSettingsDidChangeNotification;
extern NSString *const iTermAutoComposerDidChangeNotification;

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
    TAB_STYLE_DARK_HIGH_CONTRAST = 3,
    TAB_STYLE_AUTOMATIC = 4,  // automatic + normal windows. This has the side-effect of changing compact windows to normal.
    TAB_STYLE_MINIMAL = 5,  // minimal + compact windows. Changes normal windows to compact.
    TAB_STYLE_COMPACT = 6  // automatic + compact windows. This should be like automatic, except it has a side-effect of changing normal windows to compact.
};

typedef NS_ENUM(NSUInteger, iTermStatusBarPosition) {
    iTermStatusBarPositionTop,
    iTermStatusBarPositionBottom
};

// Values for kPreferenceKeyTabPosition (corresponds to tags in control).
#define TAB_POSITION_TOP PSMTab_TopTab
#define TAB_POSITION_BOTTOM PSMTab_BottomTab
#define TAB_POSITION_LEFT PSMTab_LeftTab

// Values for kPreferenceKeyXxxRemapping (corresponds to tags in controls).
// Note that this serves two purposes. It describes what keys are remapped to and also the shortcuts
// for navigating to tab/window/pane by number.
typedef NS_ENUM(int, iTermPreferencesModifierTag) {
    // This was the old way of remapping right control and also continues to describe either control for the puporses of switching windows/tabs.
    kPreferencesModifierTagLegacyRightControl = 1,
    kPreferencesModifierTagLeftOption = 2,
    kPreferencesModifierTagRightOption = 3,
    kPreferencesModifierTagEitherCommand = 4,
    kPreferencesModifierTagEitherOption = 5,  // refers to any option key
    kPreferencesModifierTagCommandAndOption = 6,  // both cmd and opt at the same time
    kPreferencesModifierTagLeftCommand = 7,
    kPreferencesModifierTagRightCommand = 8,

    kPreferenceModifierTagNone = 9,  // No modifier assigned (not available for all popups)

    kPreferenceModifierTagFunction = 10,  // fn key, and no l/r distinction exists here

    // Modern way of remapping control.
    kPreferencesModifierTagLeftControl = 11,
    kPreferencesModifierTagRightControl = 12,

};

typedef NS_ENUM(NSInteger, iTermPreferenceSavePrefsMode) {
    iTermPreferenceSavePrefsModeOnQuit = 0,
    iTermPreferenceSavePrefsModeNever = 1,  // default
    iTermPreferenceSavePrefsModeAlways = 2
};

// General
extern NSString *const kPreferenceKeyOpenBookmark;
extern NSString *const kPreferenceKeyOpenArrangementAtStartup;
extern NSString *const kPreferenceKeyAlwaysOpenWindowAtStartup;
extern NSString *const kPreferenceKeyRestoreWindowsToSameSpaces;
extern NSString *const kPreferenceKeyOpenNoWindowsAtStartup;
extern NSString *const kPreferenceKeyQuitWhenAllWindowsClosed;
extern NSString *const kPreferenceKeyConfirmClosingMultipleTabs;
extern NSString *const kPreferenceKeyPromptOnQuit;
extern NSString *const kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows;
extern NSString *const kPreferenceKeyInstantReplayMemoryMegabytes;
extern NSString *const kPreferenceKeySavePasteAndCommandHistory;
extern NSString *const kPreferenceKeyAddBonjourHostsToProfiles;
extern NSString *const kPreferenceKeyNotifyOnlyForCriticalShellIntegrationUpdates;
extern NSString *const kPreferenceKeyCheckForUpdatesAutomatically;
extern NSString *const kPreferenceKeyCheckForTestReleases;
extern NSString *const kPreferenceKeyLoadPrefsFromCustomFolder;
extern NSString *const kPreferenceKeyUseCustomScriptsFolder;  // Bool
extern NSString *const kPreferenceKeyOpenAIAPIKey;
extern NSString *const kPreferenceKeyAIPrompt;

// Note: if kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection is false, then use the default value (.never).
// Otherwise, respect this value.
extern NSString *const kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection;  // iTermPreferenceSavePrefsMode
extern NSString *const kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection;
extern NSString *const kPreferenceKeyCustomFolder;  // Path/URL to location with prefs. Path may have ~ in it.
extern NSString *const kPreferenceKeyCustomScriptsFolder;  // Path to scripts folder
extern NSString *const kPreferenceKeySelectionCopiesText;
extern NSString *const kPreferenceKeyCopyLastNewline;
extern NSString *const kPreferenceKeyAllowClipboardAccessFromTerminal;
extern NSString *const kPreferenceKeyCharactersConsideredPartOfAWordForSelection;
extern NSString *const kPreferenceKeySmartWindowPlacement;
extern NSString *const kPreferenceKeyAdjustWindowForFontSizeChange;
extern NSString *const kPreferenceKeyMaximizeVerticallyOnly;
extern NSString *const kPreferenceKeyLionStyleFullscreen;
extern NSString *const kPreferenceKeySeparateWindowTitlePerTab;
extern NSString *const kPreferenceKeyOpenTmuxWindowsIn;
extern NSString *const kPreferenceKeyTmuxDashboardLimit;
extern NSString *const kPreferenceKeyAutoHideTmuxClientSession;
extern NSString *const kPreferenceKeyUseTmuxProfile;
extern NSString *const kPreferenceKeyUseTmuxStatusBar;
extern NSString *const kPreferenceKeyTmuxPauseModeAgeLimit;
extern NSString *const kPreferenceKeyTmuxUnpauseAutomatically;
extern NSString *const kPreferenceKeyTmuxWarnBeforePausing;
extern NSString *const kPreferenceKeyTmuxSyncClipboard;
extern NSString *const kPreferenceKeyUseMetal;
extern NSString *const kPreferenceKeyDisableMetalWhenUnplugged;
extern NSString *const kPreferenceKeyDisableInLowPowerMode;
extern NSString *const kPreferenceKeyPreferIntegratedGPU;
extern NSString *const kPreferenceKeyMetalMaximizeThroughput;
extern NSString *const kPreferenceKeyEnableAPIServer;
extern NSString *const kPreferenceKeyAPIAuthentication;
extern NSString *const kPreferenceKeyPhonyAllowSendingClipboardContents;

// Appearance
extern NSString *const kPreferenceKeyTabStyle_Deprecated;
extern NSString *const kPreferenceKeyTabStyle;
extern NSString *const kPreferenceKeyTabPosition;
extern NSString *const kPreferenceKeyStatusBarPosition;
extern NSString *const kPreferenceKeyHideTabBar;
extern NSString *const kPreferenceKeyHideTabNumber;
extern NSString *const kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges;
extern NSString *const kPreferenceKeyHideTabCloseButton;  // DEPRECATED
extern NSString *const kPreferenceKeyTabsHaveCloseButton;
extern NSString *const kPreferenceKeyHideTabActivityIndicator;
extern NSString *const kPreferenceKeyShowNewOutputIndicator;
extern NSString *const kPreferenceKeyShowPaneTitles;
extern NSString *const kPreferenceKeyPerPaneBackgroundImage;
extern NSString *const kPreferenceKeyHideMenuBarInFullscreen;
extern NSString *const kPreferenceKeyUIElement;
extern NSString *const kPreferenceKeyUIElementRequiresHotkeys;
extern NSString *const kPreferenceKeyFlashTabBarInFullscreen;
extern NSString *const kPreferenceKeyStretchTabsToFillBar;
extern NSString *const kPreferenceKeyShowWindowNumber;
extern NSString *const kPreferenceKeyShowJobName_Deprecated;  // DEPRECATED
extern NSString *const kPreferenceKeyShowProfileName_Deprecated;  // DEPRECATED
extern NSString *const kPreferenceKeyDimOnlyText;
extern NSString *const kPreferenceKeyDimmingAmount;
extern NSString *const kPreferenceKeyDimInactiveSplitPanes;
extern NSString *const kPreferenceKeyShowWindowBorder;
extern NSString *const kPreferenceKeyHideScrollbar;
extern NSString *const kPreferenceKeyDisableFullscreenTransparencyByDefault;
extern NSString *const kPreferenceKeyEnableDivisionView;
extern NSString *const kPreferenceKeyEnableProxyIcon;
extern NSString *const kPreferenceKeyDimBackgroundWindows;
extern NSString *const kPreferenceKeySeparateStatusBarsPerPane;
extern NSString *const kPreferenceKeyHTMLTabTitles;
extern NSString *const kPreferenceKeySideMargins;
extern NSString *const kPreferenceKeyTopBottomMargins;

// Keys
extern NSString *const kPreferenceKeyControlRemapping_Deprecated;  // Deprecated
extern NSString *const kPreferenceKeyLeftControlRemapping;
extern NSString *const kPreferenceKeyRightControlRemapping;
extern NSString *const kPreferenceKeyLeftOptionRemapping;
extern NSString *const kPreferenceKeyRightOptionRemapping;
extern NSString *const kPreferenceKeyLeftCommandRemapping;
extern NSString *const kPreferenceKeyRightCommandRemapping;
extern NSString *const kPreferenceKeyFunctionRemapping;
extern NSString *const kPreferenceKeySwitchPaneModifier;
extern NSString *const kPreferenceKeySwitchTabModifier;
extern NSString *const kPreferenceKeySwitchWindowModifier;
extern NSString *const kPreferenceKeyEmulateUSKeyboard;  // See issue 6994

extern NSString *const kPreferenceKeyHotkeyEnabled;
extern NSString *const kPreferenceKeyForceKeyboard;
extern NSString *const kPreferenceKeyKeyboardLocale;
extern NSString *const kPreferenceKeyHotKeyCode;
extern NSString *const kPreferenceKeyHotkeyCharacter;
extern NSString *const kPreferenceKeyHotkeyModifiers;
extern NSString *const kPreferenceKeyEnableHapticFeedbackForEsc;
extern NSString *const kPreferenceKeyEnableSoundForEsc;
extern NSString *const kPreferenceKeyVisualIndicatorForEsc;

extern NSString *const kPreferenceKeyLanguageAgnosticKeyBindings;

// Migration to multi-hotkey window will move these settings into a profile.
extern NSString *const kPreferenceKeyHotKeyTogglesWindow_Deprecated;  // Deprecated
extern NSString *const kPreferenceKeyHotkeyProfileGuid_Deprecated;  // Deprecated
extern NSString *const kPreferenceKeyHotkeyAutoHides_Deprecated;  // Deprecated

// Pointer
extern NSString *const kPreferenceKeyCmdClickOpensURLs;
extern NSString *const kPreferenceKeyControlLeftClickBypassesContextMenu;
extern NSString *const kPreferenceKeyOptionClickMovesCursor;
extern NSString *const kPreferenceKeyThreeFingerEmulatesMiddle;
extern NSString *const kPreferenceKeyFocusFollowsMouse;
extern NSString *const kPreferenceKeyTripleClickSelectsFullWrappedLines;
extern NSString *const kPreferenceKeyDoubleClickPerformsSmartSelection;
extern NSString *const kPreferenceKeyEnterCopyModeAutomatically;
extern NSString *const kPreferenceKeyFocusOnRightOrMiddleClick;

// Not in prefs
// Stores the last CFBundleVersion run.
extern NSString *const kPreferenceKeyAppVersion;
extern NSString *const kPreferenceKeyAllAppVersions;

// Auto-command history (set through menu)
extern NSString *const kPreferenceAutoCommandHistory;
extern NSString *const kPreferenceAutoComposer;

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
extern NSString *const kPreferenceKeyDefaultToolbeltWidth;
extern NSString *const kPreferenceKeySizeChangesAffectProfile;
extern NSString *const kPreferenceKeyAlertOnMarksInOffscreenSessions;

// Set to YES on the first launch of a version that supports multiple hotkey windows.
extern NSString *const kPreferenceKeyHotkeyMigratedFromSingleToMulti;

// See iTermActionsModel. NOTE: This cannot be accessed with the usual getters and setters because
// it is array-valued.
extern NSString *const kPreferenceKeyActions;
// See iTermSnippetsModel. NOTE: This cannot be accessed with the useal getters and setters because
// it is array-valued.
extern NSString *const kPreferenceKeySnippets;

extern NSString *const kPreferenceKeyDisableTransparencyForKeyWindow;
extern NSString *const kPreferenceKeyNeverBlockSystemShutdown;

extern NSString *const iTermDefaultAIPrompt;

@interface iTermPreferences : NSObject

// This should be called early during startup to set user defaults keys that fix problematic Apple
// settings and update the last-used version number.
+ (void)initializeUserDefaults;

// Last app version launched, if any.
+ (NSString *)appVersionBeforeThisLaunch;
+ (NSSet<NSString *> *)allAppVersionsUsedOnThisMachine;

+ (void)setObject:(id)object forKey:(NSString *)key;
+ (NSObject *)objectForKey:(NSString *)key;

+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;

+ (int)intForKey:(NSString *)key;
+ (void)setInt:(int)value forKey:(NSString *)key;

+ (NSInteger)integerForKey:(NSString *)key;
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;

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

+ (NSString *)warningIdentifierForNeverWarnAboutShortLivedSessions:(NSString *)guid;

@end

@interface iTermPreferences (FastAccessors)
+ (BOOL)hideTabActivityIndicator;
+ (BOOL)maximizeMetalThroughput;
+ (BOOL)useTmuxProfile;
@end
