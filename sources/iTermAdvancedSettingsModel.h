//
//  iTermAdvancedSettingsModel.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Foundation/Foundation.h>

@interface iTermAdvancedSettingsModel : NSObject

typedef enum {
    kiTermAdvancedSettingTypeBoolean,
    kiTermAdvancedSettingTypeInteger,
    kiTermAdvancedSettingTypeFloat,
    kiTermAdvancedSettingTypeString,
    kiTermAdvancedSettingTypeOptionalBoolean
} iTermAdvancedSettingType;

extern NSString *const kAdvancedSettingIdentifier;
extern NSString *const kAdvancedSettingType;
extern NSString *const kAdvancedSettingDefaultValue;
extern NSString *const kAdvancedSettingDescription;

// The model posts this notification when it makes a change.
extern NSString *const iTermAdvancedSettingsDidChange;

+ (void)enumerateDictionaries:(void (^)(NSDictionary *))block;
+ (void)loadAdvancedSettingsFromUserDefaults;

#pragma mark - Accessors

+ (BOOL)aboutToPasteTabsWithCancel;
+ (BOOL)accelerateUploads;
+ (BOOL)acceptOSC7;
+ (double)activeUpdateCadence;
+ (int)adaptiveFrameRateThroughputThreshold;
+ (BOOL)addNewTabAtEndOfTabs;
+ (BOOL)aggressiveBaseCharacterDetection;
+ (BOOL)aggressiveFocusFollowsMouse;
+ (BOOL)alertsIndicateShortcuts;
+ (BOOL)allowDragOfTabIntoNewWindow;
+ (BOOL)alternateMouseScroll;
+ (NSString *)alternateMouseScrollStringForDown;
+ (NSString *)alternateMouseScrollStringForUp;
+ (BOOL)alwaysAcceptFirstMouse;
+ (int)alwaysWarnBeforePastingOverSize;
+ (BOOL)appendToExistingDebugLog;
+ (int)autocompleteMaxOptions;
+ (NSString *)autoLogFormat;
+ (BOOL)autologAppends;
+ (NSString *)badgeFont;
+ (BOOL)badgeFontIsBold;
+ (double)badgeMaxHeightFraction;
+ (double)badgeMaxWidthFraction;
+ (int)badgeRightMargin;
+ (int)badgeTopMargin;
+ (BOOL)bootstrapDaemon;
+ (BOOL)clearBellIconAggressively;
+ (BOOL)cmdClickWhenInactiveInvokesSemanticHistory;
+ (double)coloredSelectedTabOutlineStrength;
+ (double)coloredUnselectedTabTextProminence;
+ (double)compactMinimalTabBarHeight;
+ (BOOL)conservativeURLGuessing;
+ (BOOL)convertTabDragToWindowDragForSolitaryTabInCompactOrMinimalTheme;
+ (BOOL)copyWithStylesByDefault;
+ (BOOL)darkThemeHasBlackTitlebar;
+ (CGFloat)defaultTabBarHeight;
+ (int)defaultTabStopWidth;
+ (NSString *)defaultURLScheme;
+ (BOOL)detectPasswordInput;
+ (BOOL)disableAdaptiveFrameRateInInteractiveApps;
+ (BOOL)disableAppNap;
+ (BOOL)disableCustomBoxDrawing;
+ (BOOL)disableMetalWhenIdle;
+ (BOOL)disablePasswordManagerAnimations;
+ (BOOL)disablePotentiallyInsecureEscapeSequences;
+ (BOOL)disableTabBarTooltips;
+ (BOOL)disableWindowShadowWhenTransparencyOnMojave;
+ (BOOL)disableWindowShadowWhenTransparencyPreMojave;
+ (BOOL)disableWindowSizeSnap;
+ (BOOL)disallowCopyEmptyString;
+ (BOOL)disregardDockSettingToOpenTabsInsteadOfWindows;
+ (BOOL)dockIconTogglesWindow DEPRECATED_ATTRIBUTE;
+ (BOOL)doNotSetCtype;
+ (BOOL)doubleClickTabToEdit;
+ (BOOL)doubleReportScrollWheel;
+ (NSString *)downloadsDirectory;
+ (BOOL)drawBottomLineForHorizontalTabBar;
+ (BOOL)drawOutlineAroundCursor;
+ (BOOL)dwcLineCache;
+ (NSString *)dynamicProfilesPath;
+ (double)echoProbeDuration;
+ (BOOL)enableSemanticHistoryOnNetworkMounts;
+ (BOOL)enableUnderlineSemanticHistoryOnCmdHover;
+ (BOOL)escapeWithQuotes;
+ (BOOL)excludeBackgroundColorsFromCopiedStyle;
+ (BOOL)experimentalKeyHandling;
+ (double)extraSpaceBeforeCompactTopTabBar;
+ (NSString *)fallbackLCCType;
+ (double)findDelaySeconds;

// Regular expression for finding URLs for Edit>Find>Find URLs
+ (NSString *)findUrlsRegex;

+ (BOOL)focusNewSplitPaneWithFocusFollowsMouse;
+ (BOOL)focusReportingEnabled;
+ (BOOL)fontChangeAffectsBroadcastingSessions;
+ (double)fractionOfCharacterSelectingNextNeighbor;
+ (BOOL)fullHeightCursor;
+ (NSString *)gitSearchPath;
+ (double)gitTimeout;
+ (BOOL)hideStuckTooltips;
+ (BOOL)highVisibility;
+ (double)hotKeyDoubleTapMaxDelay;
+ (double)hotKeyDoubleTapMinDelay;
+ (double)hotkeyTermAnimationDuration;
+ (BOOL)hotkeyWindowsExcludedFromCycling;
+ (BOOL)hotkeyWindowFloatsAboveOtherWindows DEPRECATED_ATTRIBUTE;
+ (double)idleTimeSeconds;
+ (BOOL)ignoreHardNewlinesInURLs;
+ (BOOL)includePasteHistoryInAdvancedPaste;
+ (BOOL)indicateBellsInDockBadgeLabel;
+ (double)indicatorFlashInitialAlpha;
+ (double)invalidateShadowTimesPerSecond;
+ (BOOL)jiggleTTYSizeOnClearBuffer;
+ (BOOL)killJobsInServersOnQuit;
+ (BOOL)killSessionsOnLogout;
+ (BOOL)laxNilPolicyInInterpolatedStrings;
+ (BOOL)loadFromFindPasteboard;
+ (BOOL)logDrawingPerformance;
+ (BOOL)logRestorableStateSize;
+ (BOOL)lowFiCombiningMarks;
+ (int)maximumBytesToProvideToServices;
+ (int)maxSemanticHistoryPrefixOrSuffix;
+ (double)metalSlowFrameRate;
+ (BOOL)middleClickClosesTab;
+ (int)minCompactTabWidth;
+ (double)minimalSplitPaneDividerProminence;
+ (double)minimalTabStyleBackgroundColorDifference;
+ (BOOL)minimalTabStyleTreatLeftInsetAsPartOfFirstTab;
+ (double)minimalTabStyleOutlineStrength;
+ (int)minimumTabDragDistance;
+ (double)minimumTabLabelWidth;
+ (int)minimumWeightDifferenceForBoldFont;
+ (double)minRunningTime;
+ (int)minTabWidth;
+ (BOOL)navigatePanesInReadingOrder;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)noSyncDoNotWarnBeforeMultilinePaste;
+ (void)setNoSyncDoNotWarnBeforeMultilinePaste:(BOOL)value;
+ (NSString *)noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey;
+ (BOOL)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt;
+ (void)setNoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt:(BOOL)value;
+ (NSString *)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPromptUserDefaultsKey;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForFile;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForUrl;
+ (BOOL)noSyncReplaceProfileWarning;
+ (BOOL)noSyncSilenceAnnoyingBellAutomatically;
+ (BOOL)noSyncSuppressAnnyoingBellOffer;
+ (BOOL)noSyncSuppressBroadcastInputWarning;
+ (BOOL)noSyncSuppressCaptureOutputRequiresShellIntegrationWarning;
+ (BOOL)noSyncSuppressCaptureOutputToolNotVisibleWarning;
+ (BOOL)noSyncSuppressClipboardAccessDeniedWarning;
+ (void)setNoSyncSuppressClipboardAccessDeniedWarning:(BOOL)value;
+ (BOOL)noSyncSuppressMissingProfileInArrangementWarning;
+ (void)setNoSyncSuppressMissingProfileInArrangementWarning:(BOOL)value;
+ (BOOL)NoSyncSuppressRestartSessionConfirmationAlert;
+ (BOOL)noSyncTipsDisabled;
+ (int)numberOfLinesForAccessibility;
+ (BOOL)openFileInNewWindows;
+ (BOOL)openFileOverridesSendText;
+ (BOOL)openNewWindowAtStartup;
+ (BOOL)openUntitledFile;
+ (int)optimumTabWidth;
+ (BOOL)optionIsMetaForSpecialChars;
+ (int)pasteHistoryMaxOptions;
+ (NSString *)pathsToIgnore;
+ (NSString *)pathToFTP;
+ (NSString *)pathToTelnet;
+ (BOOL)performDictionaryLookupOnQuickLook;
+ (BOOL)pinEditSession;
+ (BOOL)pinchToChangeFontSizeDisabled;
+ (double)pointSizeOfTimeStamp;
+ (BOOL)preferSpeedToFullLigatureSupport;
+ (BOOL)preventEscapeSequenceFromClearingHistory;
+ (BOOL)profilesWindowJoinsActiveSpace;
+ (BOOL)promptForPasteWhenNotAtPrompt;
+ (NSString *)pythonRuntimeDownloadURL;
+ (void)setPromptForPasteWhenNotAtPrompt:(BOOL)value;
+ (BOOL)proportionalScrollWheelReporting;
+ (int)quickPasteBytesPerCall;
+ (double)quickPasteDelayBetweenCalls;
+ (BOOL)remapModifiersWithoutEventTap;

// Remember window positions? If off, lets the OS pick the window position. Smart window placement takes precedence over this.
+ (BOOL)rememberWindowPositions;

+ (BOOL)restrictSemanticHistoryPrefixAndSuffixToLogicalWindow;
+ (BOOL)requireCmdForDraggingText;
+ (BOOL)resetSGROnPrompt;
+ (BOOL)restoreWindowContents;
+ (BOOL)restoreWindowsWithinScreens;
+ (BOOL)retinaInlineImages;
+ (BOOL)runJobsInServers;
+ (BOOL)saveToPasteHistoryWhenSecureInputEnabled;
+ (NSString *)searchCommand;
+ (BOOL)sensitiveScrollWheel;
+ (BOOL)serializeOpeningMultipleFullScreenWindows;
+ (double)shortLivedSessionDuration;
+ (BOOL)shouldSetLCTerminal;
+ (BOOL)showBlockBoundaries;
+ (BOOL)showHintsInSplitPaneMenuItems;
+ (BOOL)showMetalFPSmeter;
+ (BOOL)showSessionRestoredBanner;
+ (BOOL)showYellowMarkForJobStoppedBySignal;
+ (double)slowFrameRate;
+ (int)slowPasteBytesPerCall;
+ (double)slowPasteDelayBetweenCalls;

// The cursor's background goes to the "most different" color from its neighbors if the difference
// in brightness between the proposed background color and the neighbors' background color is less
// than this threshold.
+ (double)smartCursorColorBgThreshold;

// The cursor's text is forced to black or white if it is too similar to the
// background. If the brightness difference is less than this value then the text color becomes
// black or white.
+ (double)smartCursorColorFgThreshold;

+ (NSString *)spacelessApplicationSupport;
+ (NSString *)sshSchemePath;
+ (BOOL)sshURLsSupportPath;
+ (BOOL)startDebugLoggingAutomatically;
+ (BOOL)statusBarIcon;
+ (BOOL)stealKeyFocus;
+ (BOOL)supportREPCode;
+ (BOOL)suppressMultilinePasteWarningWhenNotAtShellPrompt;
+ (BOOL)suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline;
+ (BOOL)suppressRestartAnnouncement;
+ (BOOL)swapFindNextPrevious;
+ (void)setSuppressRestartAnnouncement:(BOOL)value;
+ (double)tabAutoShowHoldTime;
+ (double)tabFlashAnimationDuration;
+ (BOOL)tabsWrapAround;
+ (BOOL)tabTitlesUseSmartTruncation;
+ (int)terminalMargin;
+ (int)terminalVMargin;
+ (BOOL)throttleMetalConcurrentFrames;
+ (double)timeBetweenBlinks;
+ (double)timeBetweenTips;
+ (void)setTimeBetweenTips:(double)time;
+ (BOOL)synergyModifierRemappingEnabled;
+ (double)timeoutForStringEvaluation;
+ (double)timeToWaitForEmojiPanel;
+ (BOOL)tmuxVariableWindowSizesSupported;
+ (BOOL)tolerateUnrecognizedTmuxCommands;
+ (BOOL)trackingRunloopForLiveResize;
+ (BOOL)traditionalVisualBell;
+ (NSString *)trailingPunctuationMarks;
+ (int)triggerRadius;
+ (BOOL)trimWhitespaceOnCopy;
+ (BOOL)typingClearsSelection;
+ (double)underlineCursorHeight;
+ (double)underlineCursorOffset;
+ (BOOL)underlineHyperlinks;
+ (double)updateScreenParamsDelay;
+ (NSString *)URLCharacterSet;
+ (NSString *)URLCharacterSetExclusions;
+ (BOOL)useAdaptiveFrameRate;
+ (BOOL)useBlackFillerColorForTmuxInFullScreen;
+ (BOOL)useColorfgbgFallback;
+ (BOOL)useDivorcedProfileToSplit;
+ (BOOL)useExperimentalFontMetrics;
+ (BOOL)useGCDUpdateTimer;

#if ENABLE_LOW_POWER_GPU_DETECTION
+ (BOOL)useLowPowerGPUWhenUnplugged;
#endif

+ (BOOL)useModernScrollWheelAccumulator;
+ (BOOL)useOldStyleDropDownViews;
+ (BOOL)useOpenDirectory;
+ (BOOL)useSystemCursorWhenPossible;
+ (BOOL)useUnevenTabs;
+ (BOOL)openProfilesInNewWindow;
+ (BOOL)workAroundMultiDisplayOSBug;
+ (BOOL)workAroundNumericKeypadBug;
+ (CGFloat)verticalBarCursorWidth;
+ (NSString *)viewManPageCommand;
+ (BOOL)wrapFocus;
+ (BOOL)zeroWidthSpaceAdvancesCursor;
+ (BOOL)zippyTextDrawing;



@end
