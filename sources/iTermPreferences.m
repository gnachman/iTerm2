//
//  iTermPreferences.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
// At a minimum, each preference must have:
// - A key declared in the header and defined here
// - A default value in +defaultValueMap
// - A control defined in its view controller
//
// Optionally, it may have a function that computes its value (set in +computedObjectDictionary)
// and the view controller may customize how its control's appearance changes dynamically.

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermPreferences.h"
#import "iTermRemotePreferences.h"
#import "iTermUserDefaultsObserver.h"
#import "WindowArrangements.h"
#import "PSMTabBarControl.h"

#define BLOCK(x) [^id() { return [self x]; } copy]

NSString *const kPreferenceKeyOpenBookmark = @"OpenBookmark";
NSString *const kPreferenceKeyOpenArrangementAtStartup = @"OpenArrangementAtStartup";
NSString *const kPreferenceKeyAlwaysOpenWindowAtStartup = @"AlwaysOpenWindowAtStartup";
NSString *const kPreferenceKeyRestoreWindowsToSameSpaces = @"RestoreWindowsToSameSpaces";
NSString *const kPreferenceKeyOpenNoWindowsAtStartup = @"OpenNoWindowsAtStartup";
NSString *const kPreferenceKeyQuitWhenAllWindowsClosed = @"QuitWhenAllWindowsClosed";
NSString *const kPreferenceKeyConfirmClosingMultipleTabs = @"OnlyWhenMoreTabs";  // The key predates split panes
NSString *const kPreferenceKeyPromptOnQuit = @"PromptOnQuit";
NSString *const kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows = @"PromptOnQuitEvenIfThereAreNoWindows";
NSString *const kPreferenceKeyInstantReplayMemoryMegabytes = @"IRMemory";
NSString *const kPreferenceKeySavePasteAndCommandHistory = @"SavePasteHistory";  // The key predates command history
NSString *const kPreferenceKeyAddBonjourHostsToProfiles = @"EnableRendezvous";  // The key predates the name Bonjour
NSString *const kPreferenceKeyNotifyOnlyForCriticalShellIntegrationUpdates = @"NotifyOnlyForCriticalShellIntegrationUpdates";  // BOOL
NSString *const kPreferenceKeyCheckForUpdatesAutomatically = @"SUEnableAutomaticChecks";  // Key defined by Sparkle
NSString *const kPreferenceKeyCheckForTestReleases = @"CheckTestRelease";
NSString *const kPreferenceKeyLoadPrefsFromCustomFolder = @"LoadPrefsFromCustomFolder";
NSString *const kPreferenceKeyUseCustomScriptsFolder = @"UseCustomScriptsFolder";

// This pref was originally a suppressable warning plus a user default, which is why it's in two
// parts.

// 0 = on quit, 1 = never, 2 = always
NSString *const kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection = @"NoSyncNeverRemindPrefsChangesLostForFile_selection";

// YES = apply preference from above key, NO = ask on exit if changes exist
NSString *const kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection = @"NoSyncNeverRemindPrefsChangesLostForFile";

NSString *const iTermMetalSettingsDidChangeNotification = @"iTermMetalSettingsDidChangeNotification";
NSString *const iTermAutoComposerDidChangeNotification = @"iTermAutoComposerDidChangeNotification";

NSString *const kPreferenceKeyCustomFolder = @"PrefsCustomFolder";
NSString *const kPreferenceKeyCustomScriptsFolder = @"CustomScriptsFolder";  // String
NSString *const kPreferenceKeySelectionCopiesText = @"CopySelection";
NSString *const kPreferenceKeyCopyLastNewline = @"CopyLastNewline";
NSString *const kPreferenceKeyAllowClipboardAccessFromTerminal = @"AllowClipboardAccess";
NSString *const kPreferenceKeyCharactersConsideredPartOfAWordForSelection = @"WordCharacters";
NSString *const kPreferenceKeySmartWindowPlacement = @"SmartPlacement";
NSString *const kPreferenceKeyAdjustWindowForFontSizeChange = @"AdjustWindowForFontSizeChange";
NSString *const kPreferenceKeyMaximizeVerticallyOnly = @"MaxVertically";
NSString *const kPreferenceKeyLionStyleFullscreen = @"UseLionStyleFullscreen";
NSString *const kPreferenceKeySeparateWindowTitlePerTab = @"SeparateWindowTitlePerTab";
NSString *const kPreferenceKeyOpenTmuxWindowsIn = @"OpenTmuxWindowsIn";
NSString *const kPreferenceKeyTmuxDashboardLimit = @"TmuxDashboardLimit";
NSString *const kPreferenceKeyAutoHideTmuxClientSession = @"AutoHideTmuxClientSession";
NSString *const kPreferenceKeyUseTmuxProfile = @"TmuxUsesDedicatedProfile";
NSString *const kPreferenceKeyUseTmuxStatusBar = @"UseTmuxStatusBar";
NSString *const kPreferenceKeyTmuxPauseModeAgeLimit = @"TmuxPauseModeAgeLimit";
NSString *const kPreferenceKeyTmuxUnpauseAutomatically = @"TmuxUnpauseAutomatically";
NSString *const kPreferenceKeyTmuxWarnBeforePausing = @"TmuxWarnBeforePausing";
NSString *const kPreferenceKeyTmuxSyncClipboard = @"TmuxSyncClipboard";
NSString *const kPreferenceKeyPhonyAllowSendingClipboardContents = @"PhonyAllowSendingClipboardContents";

NSString *const kPreferenceKeyUseMetal = @"UseMetal";
NSString *const kPreferenceKeyDisableMetalWhenUnplugged = @"disableMetalWhenUnplugged";
NSString *const kPreferenceKeyDisableInLowPowerMode = @"disableMetalInLowPowerMode";
NSString *const kPreferenceKeyPreferIntegratedGPU = @"preferIntegratedGPU";
NSString *const kPreferenceKeyMaximizeThroughput = @"metalMaximizeThroughput";  // Used to be metal-specific but not any more
NSString *const kPreferenceKeyEnableAPIServer = @"EnableAPIServer";
NSString *const kPreferenceKeyAPIAuthentication = @"API Authentication Method";

NSString *const kPreferenceKeyTabStyle_Deprecated = @"TabStyle";  // Pre-10.14
NSString *const kPreferenceKeyTabStyle = @"TabStyleWithAutomaticOption";  // Pre-10.14
NSString *const kPreferenceKeyTabPosition = @"TabViewType";
NSString *const kPreferenceKeyStatusBarPosition = @"StatusBarPosition";
NSString *const kPreferenceKeySideMargins = @"TerminalMargin";
NSString *const kPreferenceKeyTopBottomMargins = @"TerminalVMargin";
NSString *const kPreferenceKeyHideTabBar = @"HideTab";
NSString *const kPreferenceKeyHideTabNumber = @"HideTabNumber";
NSString *const kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges = @"PreserveWindowSizeWhenTabBarVisibilityChanges";
NSString *const kPreferenceKeyHideTabCloseButton = @"HideTabCloseButton";  // Deprecated
NSString *const kPreferenceKeyTabsHaveCloseButton = @"TabsHaveCloseButton";
NSString *const kPreferenceKeyHideTabActivityIndicator = @"HideActivityIndicator";
NSString *const kPreferenceKeyShowNewOutputIndicator = @"ShowNewOutputIndicator";
NSString *const kPreferenceKeyShowPaneTitles = @"ShowPaneTitles";
NSString *const kPreferenceKeyPerPaneBackgroundImage = @"PerPaneBackgroundImage";
NSString *const kPreferenceKeyStretchTabsToFillBar = @"StretchTabsToFillBar";
NSString *const kPreferenceKeyHideMenuBarInFullscreen = @"HideMenuBarInFullscreen";
NSString *const kPreferenceKeyUIElement = @"HideFromDockAndAppSwitcher";
NSString *const kPreferenceKeyUIElementRequiresHotkeys = @"UIElementRequiresHotkeys";
NSString *const kPreferenceKeyFlashTabBarInFullscreen = @"FlashTabBarInFullscreen";
NSString *const kPreferenceKeyShowWindowNumber = @"WindowNumber";
NSString *const kPreferenceKeyShowJobName_Deprecated = @"JobName";
NSString *const kPreferenceKeyShowProfileName_Deprecated = @"ShowBookmarkName";  // The key predates bookmarks being renamed to profiles
NSString *const kPreferenceKeyDimOnlyText = @"DimOnlyText";
NSString *const kPreferenceKeyDimmingAmount = @"SplitPaneDimmingAmount";
NSString *const kPreferenceKeyDimInactiveSplitPanes = @"DimInactiveSplitPanes";
NSString *const kPreferenceKeyShowWindowBorder = @"UseBorder";
NSString *const kPreferenceKeyHideScrollbar = @"HideScrollbar";
NSString *const kPreferenceKeyDisableFullscreenTransparencyByDefault = @"DisableFullscreenTransparency";
NSString *const kPreferenceKeyEnableDivisionView = @"EnableDivisionView";
NSString *const kPreferenceKeyEnableProxyIcon = @"EnableProxyIcon";
NSString *const kPreferenceKeyDimBackgroundWindows = @"DimBackgroundWindows";
NSString *const kPreferenceKeySeparateStatusBarsPerPane = @"SeparateStatusBarsPerPane";

NSString *const kPreferenceKeyControlRemapping_Deprecated = @"Control"; // deprecated
NSString *const kPreferenceKeyLeftControlRemapping = @"LeftControl";
NSString *const kPreferenceKeyRightControlRemapping = @"RightControl";
NSString *const kPreferenceKeyLeftOptionRemapping = @"LeftOption";
NSString *const kPreferenceKeyRightOptionRemapping = @"RightOption";
NSString *const kPreferenceKeyLeftCommandRemapping = @"LeftCommand";
NSString *const kPreferenceKeyRightCommandRemapping = @"RightCommand";
NSString *const kPreferenceKeyFunctionRemapping = @"FunctionKey";
NSString *const kPreferenceKeySwitchPaneModifier = @"SwitchPaneModifier";
NSString *const kPreferenceKeySwitchTabModifier = @"SwitchTabModifier";
NSString *const kPreferenceKeySwitchWindowModifier = @"SwitchWindowModifier";
NSString *const kPreferenceKeyEmulateUSKeyboard = @"UseVirtualKeyCodesForDetectingDigits";

NSString *const kPreferenceKeyHotkeyEnabled = @"Hotkey";
NSString *const kPreferenceKeyHotKeyCode = @"HotkeyCode";
NSString *const kPreferenceKeyHotkeyCharacter = @"HotkeyChar";  // Nonzero if hotkey char is set.
NSString *const kPreferenceKeyHotkeyModifiers = @"HotkeyModifiers";
NSString *const kPreferenceKeyEnableHapticFeedbackForEsc = @"HapticFeedbackForEsc";
NSString *const kPreferenceKeyEnableSoundForEsc = @"SoundForEsc";
NSString *const kPreferenceKeyVisualIndicatorForEsc = @"VisualIndicatorForEsc";
NSString *const kPreferenceKeyLanguageAgnosticKeyBindings = @"LanguageAgnosticKeyBindings";
NSString *const kPreferenceKeyForceKeyboard = @"ForceKeyboard";  // bool
NSString *const kPreferenceKeyKeyboardLocale = @"KeyboardLocale";  // string

NSString *const kPreferenceKeyHotKeyTogglesWindow_Deprecated = @"HotKeyTogglesWindow";  // deprecated
NSString *const kPreferenceKeyHotkeyProfileGuid_Deprecated = @"HotKeyBookmark";  // deprecated
NSString *const kPreferenceKeyHotkeyAutoHides_Deprecated = @"HotkeyAutoHides";  // deprecated

NSString *const kPreferenceKeyCmdClickOpensURLs = @"CommandSelection";
NSString *const kPreferenceKeyControlLeftClickBypassesContextMenu = @"PassOnControlClick";
NSString *const kPreferenceKeyOptionClickMovesCursor = @"OptionClickMovesCursor";
NSString *const kPreferenceKeyThreeFingerEmulatesMiddle = @"ThreeFingerEmulates";
NSString *const kPreferenceKeyFocusFollowsMouse = @"FocusFollowsMouse";
NSString *const kPreferenceKeyTripleClickSelectsFullWrappedLines = @"TripleClickSelectsFullWrappedLines";
NSString *const kPreferenceKeyDoubleClickPerformsSmartSelection = @"DoubleClickPerformsSmartSelection";
NSString *const kPreferenceKeyEnterCopyModeAutomatically = @"EnterCopyModeAutomatically";
NSString *const kPreferenceKeyFocusOnRightOrMiddleClick = @"FocusOnRightOrMiddleClick";
NSString *const kPreferenceKeyClickToSelectCommand = @"ClickToSelectCommand";

NSString *const kPreferenceKeyAppVersion = @"iTerm Version";  // Excluded from syncing
NSString *const kPreferenceKeyAllAppVersions = @"NoSyncAllAppVersions";  // Array of known iTerm2 versions this user has used on this machine.
NSString *const kPreferenceAutoCommandHistory = @"AutoCommandHistory";
NSString *const kPreferenceAutoComposer = @"AutoComposer";
NSString *const kPreferenceKeyOSVersion = @"NoSyncLastOSVersion";

NSString *const kPreferenceKeyPasteSpecialChunkSize = @"PasteSpecialChunkSize";
NSString *const kPreferenceKeyPasteSpecialChunkDelay = @"PasteSpecialChunkDelay";
NSString *const kPreferenceKeyPasteSpecialSpacesPerTab = @"NumberOfSpacesPerTab";
NSString *const kPreferenceKeyPasteSpecialTabTransform = @"TabTransform";
NSString *const kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash = @"EscapeShellCharsWithBackslash";
NSString *const kPreferenceKeyPasteSpecialConvertUnicodePunctuation = @"ConvertUnicodePunctuation";
NSString *const kPreferenceKeyPasteSpecialConvertDosNewlines = @"ConvertDosNewlines";
NSString *const kPreferenceKeyPasteSpecialRemoveControlCodes = @"RemoveControlCodes";
NSString *const kPreferenceKeyPasteSpecialBracketedPasteMode = @"BracketedPasteMode";
NSString *const kPreferencesKeyPasteSpecialUseRegexSubstitution = @"PasteSpecialUseRegexSubstitution";
NSString *const kPreferencesKeyPasteSpecialRegex = @"PasteSpecialRegex";
NSString *const kPreferencesKeyPasteSpecialSubstitution = @"PasteSpecialSubstitution";
NSString *const kPreferenceKeyLeftTabBarWidth = @"LeftTabBarWidth";

NSString *const kPreferenceKeyPasteWarningNumberOfSpacesPerTab = @"PasteTabToStringTabStopSize";

NSString *const kPreferenceKeyShowFullscreenTabBar = @"ShowFullScreenTabBar";
NSString *const kPreferenceKeyHotkeyMigratedFromSingleToMulti = @"HotkeyMigratedFromSingleToMulti";
NSString *const kPreferenceKeyDefaultToolbeltWidth = @"Default Toolbelt Width";
NSString *const kPreferenceKeySizeChangesAffectProfile = @"Size Changes Affect Profile";
NSString *const kPreferenceKeyActions = @"Actions";
NSString *const kPreferenceKeySnippets = @"Snippets";
NSString *const kPreferenceKeyHTMLTabTitles = @"HTMLTabTitles";
NSString *const kPreferenceKeyDisableTransparencyForKeyWindow = @"DisableTransparencyForKeyWindow";
NSString *const kPreferenceKeyNeverBlockSystemShutdown = @"NeverBlockSystemShutdown";

NSString *const kPreferenceKeyOpenAIAPIKey = @"NoSyncOpenAIAPIKey";
NSString *const kPreferenceKeyAIPrompt = @"AI Prompt";
NSString *const kPreferenceKeyAlertOnMarksInOffscreenSessions = @"Alert On Marks in Offscreen Sessions";
NSString *const kPreferenceKeyCompressHistory = @"Compress History";
NSString *const kPreferenceKeyAIModel = @"AiModel";
NSString *const kPreferenceKeyAITokenLimit = @"AiMaxTokens";

NSString *const iTermDefaultAIPrompt = @"Return commands suitable for copy/pasting into \\(shell) on \\(uname). Do NOT include commentary NOR Markdown triple-backtick code blocks as your whole response will be copied into my terminal automatically.\n"
@"\n"
@"The script should do this: \\(ai.prompt)";

// NOTE: If you update this list, also update preferences.py.

static NSMutableDictionary *gObservers;
static NSString *sPreviousVersion;

@implementation iTermPreferences

+ (NSString *)appVersionBeforeThisLaunch {
    if (!sPreviousVersion) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        sPreviousVersion = [[userDefaults objectForKey:kPreferenceKeyAppVersion] copy];
    }
    return sPreviousVersion;
}

+ (NSSet<NSString *> *)allAppVersionsUsedOnThisMachine {
    static NSSet<NSString *> *versions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versions = [NSSet setWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyAllAppVersions] ?: @[]];
    });
    return versions;

}

+ (void)initializeAppVersionBeforeThisLaunch:(NSString *)thisVersion {
    // Force it to be lazy-loaded.
    [self appVersionBeforeThisLaunch];
    // Then overwrite it with the current version
    [[NSUserDefaults standardUserDefaults] setObject:thisVersion forKey:kPreferenceKeyAppVersion];
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    [[NSUserDefaults standardUserDefaults] setObject:processInfo.operatingSystemVersionString
                                              forKey:kPreferenceKeyOSVersion];
}

+ (void)initializeAllAppVersionsUsedOnThisMachine:(NSString *)thisVersion {
    // Update all app versions ever seena.
    NSMutableSet *allVersions = [NSMutableSet setWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyAllAppVersions] ?: @[]];
    
    NSString *const before = [self appVersionBeforeThisLaunch];
    if (before) {
        [allVersions addObject:before];
    }

    [allVersions addObject:thisVersion];
    [allVersions removeObject:@"unknown"];
    [[NSUserDefaults standardUserDefaults] setObject:allVersions.allObjects forKey:kPreferenceKeyAllAppVersions];
}

+ (NSDictionary *)systemPreferenceOverrides {
    return @{
        // Force antialiasing to be allowed on small font sizes
        @"AppleAntiAliasingThreshold": @1,
        @"AppleSmoothFixedFontsSizeThreshold": @1,

        // Turn off high sierra's native tabs
        @"AppleWindowTabbingMode": @"manual",

        // Turn off scroll animations because they screw up the terminal scrolling.
        @"AppleScrollAnimationEnabled": @0,

        // Turn off accent menu
        @"ApplePressAndHoldEnabled": @NO,

        // Override smooth scrolling, which breaks various things (such as the
        // assumption, when detectUserScroll is called, that scrolls happen
        // immediately), and generally sucks with a terminal.
        @"NSScrollAnimationEnabled": @NO,

        // Disable under-titlebar mirror view.

        // OS 10.10 has a spiffy feature where it finds a scrollview that is
        // adjacent to the title bar and then does some magic to makes the
        // scrollview's content show up with "vibrancy" (i.e., blur) under the
        // title bar. The way it does this is to create an "NSScrollViewMirrorView"
        // in the title bar's view hierarchy, under a view whose class is
        // NSTitlebarContainerView. Unfortunately there is no way to turn
        // this off. You can move the scroll view at least two points away from the
        // title bar, but that looks terrible. Terminal.app went so far as to stop
        // using scroll views! Trying to replace NSScrollView with my custom
        // implementation seems fraught with peril. Trying to hide the mirror view
        // doesn't work because it only becomes visible once the scroll view is
        // taller than the window's content view (I think that is new in 10.10.3).
        // I tried swizzling addSubview: in NSTitlebarContainerView to hide
        // mirror views when they get added, but it caused some performance problems
        // I can't reproduce (see issue 3499).
        //
        // Another option, which seems more fragile, is to override
        // -[PTYScrollView _makeUnderTitlebarView] and have it return nil. That works
        // in testing but could break things pretty badly.
        //
        // I found this undocumented setting while disassembling the caller to _makeUnderTitlebarView,
        // and it seems to work.
        //
        // See issue 3244 for details.
        @"NSScrollViewShouldScrollUnderTitlebar": @NO,

        // macOS does an insane thing and looks for views that might possibly be trying to do something
        // clever with scrollers and then if it finds them changes to legacy scrollers. Quothe the
        // mailing list https://lists.apple.com/archives/cocoa-dev/2012/Mar/msg00939.html
        //  NSScrollView does various checks to see if the App is trying to put placards in the
        //  scroller area. If NSScrollView thinks there are placards, then it reverts back to legacy
        //  scrollers for compatibility. Some apps have been known to do this via a sibling view
        //  instead of a subview. This is why it intermittently happens during your animation as
        //  your sibling views momentarily overlap
        //
        // In addition to being a bad idea, it is poorly implemented and the scrollers randomly
        // have the wrong light/dark appearance, in addition to other visual glitches that words
        // can't describe.
        //
        // Well, I am trying to do something clever and I damn well want it to work. With a bit of
        // the old disassembler, I found this user default which seems to turn off the stupid.
        @"NSOverlayScrollersFallBackForAccessoryViews": @NO,
    };
}

+ (void)initializeUserDefaults {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [[self systemPreferenceOverrides] enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        [userDefaults setObject:obj forKey:key];
    }];

    NSDictionary *infoDictionary = [[NSBundle bundleForClass:[self class]] infoDictionary];
    NSString *const thisVersion = infoDictionary[@"CFBundleVersion"];
    [self initializeAppVersionBeforeThisLaunch:thisVersion];
    [self initializeAllAppVersionsUsedOnThisMachine:thisVersion];

    // Load prefs from remote.
    [[iTermRemotePreferences sharedInstance] copyRemotePrefsToLocalUserDefaultsPreserving:self.systemPreferenceOverrides.allKeys];

    if ([iTermAdvancedSettingsModel enableCharacterAccentMenu]) {
        DLog(@"Accent menu enabled");
        [userDefaults setBool:YES forKey:@"ApplePressAndHoldEnabled"];
    }
}

#pragma mark - Default values

+ (NSDictionary *)defaultValueMap {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ kPreferenceKeyOpenBookmark: @NO,
                  kPreferenceKeyOpenArrangementAtStartup: @NO,
                  kPreferenceKeyAlwaysOpenWindowAtStartup: @NO,
                  kPreferenceKeyRestoreWindowsToSameSpaces: @NO,
                  kPreferenceKeyOpenNoWindowsAtStartup: @NO,
                  kPreferenceKeyQuitWhenAllWindowsClosed: @NO,
                  kPreferenceKeyConfirmClosingMultipleTabs: @YES,
                  kPreferenceKeyPromptOnQuit: @YES,
                  kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows: @NO,
                  kPreferenceKeyInstantReplayMemoryMegabytes: @4,
                  kPreferenceKeySavePasteAndCommandHistory: @NO,
                  kPreferenceKeyAddBonjourHostsToProfiles: @NO,
                  kPreferenceKeyNotifyOnlyForCriticalShellIntegrationUpdates: @YES,
                  kPreferenceKeyCheckForUpdatesAutomatically: @YES,
                  kPreferenceKeyCheckForTestReleases: @NO,
                  kPreferenceKeyLoadPrefsFromCustomFolder: @NO,
                  kPreferenceKeyUseCustomScriptsFolder: @NO,
                  kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection: @NO,
                  kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection: @0,
                  kPreferenceKeyCustomFolder: [NSNull null],
                  kPreferenceKeyCustomScriptsFolder: [NSNull null],
                  kPreferenceKeySelectionCopiesText: @YES,
                  kPreferenceKeyCopyLastNewline: @NO,
                  kPreferenceKeyAllowClipboardAccessFromTerminal: @NO,
                  kPreferenceKeyCharactersConsideredPartOfAWordForSelection: @"/-+\\~_.",
                  kPreferenceKeySmartWindowPlacement: @NO,
                  kPreferenceKeyAdjustWindowForFontSizeChange: @YES,
                  kPreferenceKeyMaximizeVerticallyOnly: @NO,
                  kPreferenceKeyLionStyleFullscreen: @YES,
                  kPreferenceKeySeparateWindowTitlePerTab: @YES,
                  kPreferenceKeyOpenTmuxWindowsIn: @(kOpenTmuxWindowsAsNativeWindows),
                  kPreferenceKeyTmuxDashboardLimit: @10,
                  kPreferenceKeyAutoHideTmuxClientSession: @NO,
                  kPreferenceKeyUseTmuxProfile: @YES,
                  kPreferenceKeyUseTmuxStatusBar: @YES,
                  kPreferenceKeyTmuxPauseModeAgeLimit: @120,
                  kPreferenceKeyTmuxUnpauseAutomatically: @NO,
                  kPreferenceKeyPhonyAllowSendingClipboardContents: @(iTermPasteboardReporterConfigurationAskEachTime),
                  kPreferenceKeyTmuxWarnBeforePausing: @YES,
                  kPreferenceKeyTmuxSyncClipboard: @NO,
                  kPreferenceKeyUseMetal: @YES,
                  kPreferenceKeyDisableMetalWhenUnplugged: @YES,
                  kPreferenceKeyDisableInLowPowerMode: @YES,
                  kPreferenceKeyPreferIntegratedGPU: @YES,
                  kPreferenceKeyMaximizeThroughput: @YES,
                  kPreferenceKeyEnableAPIServer: @NO,
                  kPreferenceKeyAPIAuthentication: @0,  // ignored — synthetic value
                  kPreferenceKeyOpenAIAPIKey: @"",
                  kPreferenceKeyAIPrompt: iTermDefaultAIPrompt,
                  kPreferenceKeyAlertOnMarksInOffscreenSessions: @NO,
                  kPreferenceKeyAIModel: @"gpt-3.5-turbo",
                  kPreferenceKeyAITokenLimit: @4000,
                  
                  kPreferenceKeyTabStyle_Deprecated: @(TAB_STYLE_LIGHT),
                  kPreferenceKeyTabStyle: @(TAB_STYLE_LIGHT),
                  
                  kPreferenceKeyTabPosition: @(TAB_POSITION_TOP),
                  kPreferenceKeyStatusBarPosition: @(iTermStatusBarPositionTop),
                  kPreferenceKeyTopBottomMargins: @2,
                  kPreferenceKeySideMargins: @5,
                  kPreferenceKeyHideTabBar: @YES,
                  kPreferenceKeyHideTabNumber: @NO,
                  kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges: @NO,
                  kPreferenceKeyHideTabCloseButton: @NO,  // Deprecated
                  kPreferenceKeyTabsHaveCloseButton: @YES,
                  kPreferenceKeyHideTabActivityIndicator: @NO,
                  kPreferenceKeyShowNewOutputIndicator: @YES,
                  kPreferenceKeyStretchTabsToFillBar: @YES,

                  kPreferenceKeyShowPaneTitles: @YES,
                  kPreferenceKeyPerPaneBackgroundImage: @YES,
                  kPreferenceKeyHideMenuBarInFullscreen:@YES,
                  kPreferenceKeyUIElement: @NO,
                  kPreferenceKeyUIElementRequiresHotkeys: @NO,
                  kPreferenceKeyFlashTabBarInFullscreen:@NO,
                  kPreferenceKeyShowWindowNumber: @YES,
                  kPreferenceKeyShowJobName_Deprecated: @YES,
                  kPreferenceKeyShowProfileName_Deprecated: @NO,
                  kPreferenceKeyDimOnlyText: @NO,
                  kPreferenceKeyDimmingAmount: @0.4,
                  kPreferenceKeyDimInactiveSplitPanes: @YES,
                  kPreferenceKeyShowWindowBorder: @NO,
                  kPreferenceKeyHideScrollbar: @NO,
                  kPreferenceKeyDisableFullscreenTransparencyByDefault: @NO,
                  kPreferenceKeyEnableDivisionView: @YES,
                  kPreferenceKeyEnableProxyIcon: @NO,
                  kPreferenceKeyDimBackgroundWindows: @NO,
                  kPreferenceKeySeparateStatusBarsPerPane: @NO,

                  kPreferenceKeyControlRemapping_Deprecated: @(kPreferencesModifierTagLegacyRightControl),
                  kPreferenceKeyLeftControlRemapping: @(kPreferencesModifierTagLeftControl),
                  kPreferenceKeyRightControlRemapping: @(kPreferencesModifierTagRightControl),
                  kPreferenceKeyKeyboardLocale: [NSNull null],
                  
                  kPreferenceKeyLeftOptionRemapping: @(kPreferencesModifierTagLeftOption),
                  kPreferenceKeyRightOptionRemapping: @(kPreferencesModifierTagRightOption),
                  kPreferenceKeyLeftCommandRemapping: @(kPreferencesModifierTagLeftCommand),
                  kPreferenceKeyRightCommandRemapping: @(kPreferencesModifierTagRightCommand),
                  kPreferenceKeyFunctionRemapping: @(kPreferenceModifierTagFunction),
                  kPreferenceKeySwitchPaneModifier: @(kPreferenceModifierTagNone),
                  kPreferenceKeySwitchTabModifier: @(kPreferencesModifierTagEitherCommand),
                  kPreferenceKeySwitchWindowModifier: @(kPreferencesModifierTagCommandAndOption),
                  kPreferenceKeyEmulateUSKeyboard: @NO,
                  kPreferenceKeyHotkeyEnabled: @NO,
                  kPreferenceKeyForceKeyboard: @NO,
                  kPreferenceKeyHotKeyCode: @0,
                  kPreferenceKeyHotkeyCharacter: @0,
                  kPreferenceKeyHotkeyModifiers: @0,
                  kPreferenceKeyHotKeyTogglesWindow_Deprecated: @NO,
                  kPreferenceKeyHotkeyProfileGuid_Deprecated: [NSNull null],
                  kPreferenceKeyHotkeyAutoHides_Deprecated: @YES,
                  kPreferenceKeyEnableHapticFeedbackForEsc: @NO,
                  kPreferenceKeyEnableSoundForEsc: @NO,
                  kPreferenceKeyVisualIndicatorForEsc: @NO,
                  kPreferenceKeyLanguageAgnosticKeyBindings: @NO,

                  kPreferenceKeyCmdClickOpensURLs: @YES,
                  kPreferenceKeyControlLeftClickBypassesContextMenu: @NO,
                  kPreferenceKeyOptionClickMovesCursor: @YES,
                  kPreferenceKeyThreeFingerEmulatesMiddle: @NO,
                  kPreferenceKeyFocusFollowsMouse: @NO,
                  kPreferenceKeyFocusOnRightOrMiddleClick: @NO,
                  kPreferenceKeyTripleClickSelectsFullWrappedLines: @YES,
                  kPreferenceKeyDoubleClickPerformsSmartSelection: @NO,
                  kPreferenceKeyEnterCopyModeAutomatically: @YES,
                  kPreferenceKeyClickToSelectCommand: @YES,

                  kPreferenceAutoCommandHistory: @NO,
                  kPreferenceAutoComposer: @NO,
                  
                  kPreferenceKeyPasteSpecialChunkSize: @1024,
                  kPreferenceKeyPasteSpecialChunkDelay: @0.01,
                  kPreferenceKeyPasteSpecialSpacesPerTab: @4,
                  kPreferenceKeyPasteSpecialTabTransform: @0,
                  kPreferenceKeyPasteSpecialEscapeShellCharsWithBackslash: @NO,
                  kPreferenceKeyPasteSpecialConvertUnicodePunctuation: @NO,
                  kPreferenceKeyPasteSpecialConvertDosNewlines: @YES,
                  kPreferenceKeyPasteSpecialRemoveControlCodes: @YES,
                  kPreferenceKeyPasteSpecialBracketedPasteMode: @YES,
                  kPreferencesKeyPasteSpecialUseRegexSubstitution: @NO,
                  kPreferencesKeyPasteSpecialRegex: @"",
                  kPreferencesKeyPasteSpecialSubstitution: @"",

                  kPreferenceKeyPasteWarningNumberOfSpacesPerTab: @4,
                  kPreferenceKeyShowFullscreenTabBar: @YES,
                  kPreferenceKeyHotkeyMigratedFromSingleToMulti: @NO,
                  kPreferenceKeyLeftTabBarWidth: @150,
                  kPreferenceKeyDefaultToolbeltWidth: @250,
                  kPreferenceKeySizeChangesAffectProfile: @NO,
                  kPreferenceKeyHTMLTabTitles: @NO,

                  kPreferenceKeyDisableTransparencyForKeyWindow: @NO,
                  kPreferenceKeyNeverBlockSystemShutdown: @NO,
                  kPreferenceKeyCompressHistory: @YES
              };
    }
    return dict;
}

+ (id)defaultObjectForKey:(NSString *)key {
    id obj = [self defaultValueMap][key];
    if ([obj isKindOfClass:[NSNull class]]) {
        return nil;
    } else {
        return obj;
    }
}

+ (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type {
    id defaultValue = [self defaultValueMap][key];
    switch (type) {
        case kPreferenceInfoTypeIntegerTextField:
        case kPreferenceInfoTypeDoubleTextField:
        case kPreferenceInfoTypePopup:
            return ([defaultValue isKindOfClass:[NSNumber class]] &&
                    [defaultValue doubleValue] == ceil([defaultValue doubleValue]));
        case kPreferenceInfoTypeUnsignedIntegerTextField:
        case kPreferenceInfoTypeUnsignedIntegerPopup:
            return ([defaultValue isKindOfClass:[NSNumber class]]);
        case kPreferenceInfoTypeCheckbox:
        case kPreferenceInfoTypeInvertedCheckbox:
            return ([defaultValue isKindOfClass:[NSNumber class]] &&
                    ([defaultValue intValue] == YES ||
                     [defaultValue intValue] == NO));
        case kPreferenceInfoTypeSlider:
            return [defaultValue isKindOfClass:[NSNumber class]];
        case kPreferenceInfoTypeTokenField:
            return ([defaultValue isKindOfClass:[NSArray class]] ||
                    [defaultValue isKindOfClass:[NSNull class]]);
        case kPreferenceInfoTypeStringPopup:
        case kPreferenceInfoTypeStringTextField:
            return ([defaultValue isKindOfClass:[NSString class]] ||
                    [defaultValue isKindOfClass:[NSNull class]]);
        case kPreferenceInfoTypeMatrix:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeRadioButton:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeColorWell:
            return [defaultValue isKindOfClass:[NSDictionary class]];
    }

    return NO;
}

#pragma mark - Computed values

// Returns a dictionary from key to a ^id() block. The block will return an object value for the
// preference or nil if the normal path (of taking the NSUserDefaults value or +defaultObjectForKey)
// should be used.
+ (NSDictionary *)computedObjectDictionary {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ kPreferenceKeyOpenArrangementAtStartup: BLOCK(computedOpenArrangementAtStartup),
                  kPreferenceKeyCustomFolder: BLOCK(computedCustomFolder),
                  kPreferenceKeyCustomScriptsFolder: BLOCK(computedCustomScriptsFolder),
                  kPreferenceKeyCharactersConsideredPartOfAWordForSelection: BLOCK(computedWordChars),
                  kPreferenceKeyTabStyle: BLOCK(computedTabStyle),
                  kPreferenceKeyUseMetal: BLOCK(computedUseMetal),
                  kPreferenceKeyTabsHaveCloseButton: BLOCK(computedTabsHaveCloseButton),
                  kPreferenceKeyLeftControlRemapping: BLOCK(computedLeftControlRemapping),
                  kPreferenceKeyRightControlRemapping: BLOCK(computedRightControlRemapping),
                  };
    }
    return dict;
}

+ (id)computedObjectForKey:(NSString *)key {
    id (^block)(void) = [self computedObjectDictionary][key];
    if (block) {
        return block();
    } else {
        return nil;
    }
}

+ (NSString *)uncomputedObjectForKey:(NSString *)key {
    id object = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (!object) {
        object = [self defaultObjectForKey:key];
    }
    return object;
}

+ (id)objectForKey:(NSString *)key {
    id object = [self computedObjectForKey:key];
    if (!object) {
        object = [self uncomputedObjectForKey:key];
    }
    return object;
}

+ (void)setObject:(id)object forKey:(NSString *)key {
    NSArray *observers = gObservers[key];
    id before = nil;
    if (observers) {
        before = [self objectForKey:key];

        // nil out observers if there is no change.
        if (before && object && [before isEqual:object]) {
            observers = nil;
        } else if (!before && !object) {
            observers = nil;
        }
    }
    if (object) {
        [[NSUserDefaults standardUserDefaults] setObject:object forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }

    for (void (^block)(id, id) in observers) {
        block(before, object);
    }

    [[iTermPreferenceDidChangeNotification notificationWithKey:key value:object] post];
}

#pragma mark - APIs

+ (BOOL)keyHasDefaultValue:(NSString *)key {
    return ([self defaultValueMap][key] != nil);
}

+ (BOOL)boolForKey:(NSString *)key {
    return [(NSNumber *)[self objectForKey:key] boolValue];
}

+ (void)setBool:(BOOL)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (int)intForKey:(NSString *)key {
    return [(NSNumber *)[self objectForKey:key] intValue];
}

+ (void)setInt:(int)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (NSInteger)integerForKey:(NSString *)key {
    return [(NSNumber *)[self objectForKey:key] integerValue];
}

+ (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (NSUInteger)unsignedIntegerForKey:(NSString *)key {
    return [(NSNumber *)[self objectForKey:key] unsignedIntegerValue];
}

+ (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (double)floatForKey:(NSString *)key {
    return [(NSNumber *)[self objectForKey:key] doubleValue];
}

+ (void)setFloat:(double)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (double)doubleForKey:(NSString *)key {
    return [(NSNumber *)[self objectForKey:key] doubleValue];
}

+ (void)setDouble:(double)value forKey:(NSString *)key {
    [self setObject:@(value) forKey:key];
}

+ (NSString *)stringForKey:(NSString *)key {
    id object = [self objectForKey:key];
    assert(!object || [object isKindOfClass:[NSString class]]);
    return object;
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
    [self setObject:value forKey:key];
}

+ (void)addObserverForKey:(NSString *)key block:(void (^)(id before, id after))block {
    if (!gObservers) {
        gObservers = [[NSMutableDictionary alloc] init];
    }
    NSMutableArray *observersForKey = gObservers[key];
    if (!observersForKey) {
        observersForKey = [NSMutableArray array];
        gObservers[key] = observersForKey;
    }
    [observersForKey addObject:[block copy]];
}

+ (NSUInteger)maskForModifierTag:(iTermPreferencesModifierTag)tag {
    switch (tag) {
        case kPreferencesModifierTagLegacyRightControl:
            return NSEventModifierFlagControl;

        case kPreferencesModifierTagEitherCommand:
            return NSEventModifierFlagCommand;

        case kPreferencesModifierTagCommandAndOption:
            return NSEventModifierFlagCommand | NSEventModifierFlagOption;

        case kPreferencesModifierTagEitherOption:
            return NSEventModifierFlagOption;

        case kPreferenceModifierTagNone:
            return NSUIntegerMax;

        case kPreferenceModifierTagFunction:
            return NSEventModifierFlagFunction;

        default:
            NSLog(@"Unexpected value for maskForModifierTag: %d", tag);
            return NSEventModifierFlagCommand | NSEventModifierFlagOption;
    }
}

#pragma mark - Value Computation Methods

+ (NSNumber *)computedOpenArrangementAtStartup {
    if ([WindowArrangements count] == 0) {
        return @NO;
    } else {
        return nil;
    }
}

// Text fields don't like nil strings.
+ (NSString *)computedCustomFolder {
    NSString *prefsCustomFolder = [self uncomputedObjectForKey:kPreferenceKeyCustomFolder];
    return prefsCustomFolder ?: @"";
}

+ (NSString *)computedCustomScriptsFolder {
    NSString *folder = [self uncomputedObjectForKey:kPreferenceKeyCustomScriptsFolder];
    return folder ?: @"";
}

// Text fields don't like nil strings.
+ (NSString *)computedWordChars {
    NSString *wordChars =
        [self uncomputedObjectForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelection];
    return wordChars ?: @"";
}

// Migrates all pre-10.14 users now on 10.14 to automatic, since anything else looks bad.
+ (NSNumber *)computedTabStyle {
    NSNumber *value;
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyTabStyle];
    if (value) {
        return value;
    }
    // New value is not set yet. This migrates all users to automatic.
    return @(TAB_STYLE_AUTOMATIC);
}

+ (NSNumber *)computedLeftControlRemapping {
    NSNumber *value;
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyLeftControlRemapping];
    if (value) {
        return value;
    }
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyControlRemapping_Deprecated];
    if (value) {
        return @(value.intValue);
    }
    return [self defaultObjectForKey:kPreferenceKeyLeftControlRemapping];
}

+ (NSNumber *)computedRightControlRemapping {
    NSNumber *value;
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyRightControlRemapping];
    if (value) {
        return value;
    }
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyControlRemapping_Deprecated];
    if (value) {
        return @(value.intValue);
    }
    return [self defaultObjectForKey:kPreferenceKeyRightControlRemapping];
}

+ (NSNumber *)computedTabsHaveCloseButton {
    NSNumber *value;
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyTabsHaveCloseButton];
    if (value) {
        return value;
    }

    value = [[NSUserDefaults standardUserDefaults] objectForKey:@"eliminateCloseButtons"];
    if (value) {
        return @(!value.boolValue);
    }

    return [self defaultObjectForKey:kPreferenceKeyTabsHaveCloseButton];
}

+ (NSNumber *)computedUseMetal {
    NSNumber *value;
    value = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyUseMetal];
    if (value) {
        return value;
    }

    return @YES;
}

+ (iTermUserDefaultsObserver *)sharedObserver {
    static iTermUserDefaultsObserver *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermUserDefaultsObserver alloc] init];
    });
    return instance;
}

+ (NSString *)warningIdentifierForNeverWarnAboutShortLivedSessions:(NSString *)guid {
    return [NSString stringWithFormat:@"NeverWarnAboutShortLivedSessions_%@", guid];
}

@end

typedef struct {
    NSString *key;
    BOOL value;
    dispatch_once_t onceToken;
} iTermPreferencesBoolCache;

#define FAST_BOOL_ACCESSOR(accessorName, userDefaultsKey) \
+ (BOOL)accessorName { \
    static iTermPreferencesBoolCache cache = { \
        .key = userDefaultsKey, \
        .value = NO, \
        .onceToken = 0 \
    }; \
    return [self boolWithCache:&cache]; \
}

@implementation iTermPreferences (FastAccessors)

+ (BOOL)boolWithCache:(iTermPreferencesBoolCache *)cache {
    dispatch_once(&cache->onceToken, ^{
        cache->value = [self boolForKey:cache->key];
        [[self sharedObserver] observeKey:cache->key block:^{
            cache->value = [self boolForKey:cache->key];
        }];
    });
    return cache->value;
}

FAST_BOOL_ACCESSOR(hideTabActivityIndicator, kPreferenceKeyHideTabActivityIndicator)
FAST_BOOL_ACCESSOR(maximizeThroughput, kPreferenceKeyMaximizeThroughput)
FAST_BOOL_ACCESSOR(useTmuxProfile, kPreferenceKeyUseTmuxProfile)

@end
