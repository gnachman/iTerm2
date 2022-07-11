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
+ (double)alertTriggerRateLimit;
+ (BOOL)alertsIndicateShortcuts;
+ (BOOL)allowDragOfTabIntoNewWindow;
+ (BOOL)allowIdempotentTriggers;
+ (BOOL)allowInteractiveSwipeBetweenTabs;
+ (BOOL)allowTabbarInTitlebarAccessoryBigSur;
+ (BOOL)alternateMouseScroll;
+ (BOOL)alwaysUseStatusBarComposer;
+ (BOOL)animateGraphStatusBarComponents;
+ (void)setAlternateMouseScroll:(BOOL)value;
+ (NSString *)alternateMouseScrollStringForDown;
+ (NSString *)alternateMouseScrollStringForUp;
+ (BOOL)alwaysAcceptFirstMouse;
+ (int)alwaysWarnBeforePastingOverSize;
+ (BOOL)anonymousTmuxWindowsOpenInCurrentWindow;
+ (BOOL)appendToExistingDebugLog;
+ (BOOL)autoLockSessionNameOnEdit;
+ (int)autocompleteMaxOptions;
#ifdef ENABLE_DEPRECATED_ADVANCED_SETTINGS
+ (NSString *)autoLogFormat;  // Use the per-profile setting instead. This is only around for migrating the default.
#endif
+ (BOOL)autologAppends;
+ (NSString *)badgeFont;
+ (BOOL)badgeFontIsBold;
+ (double)badgeMaxHeightFraction;
+ (double)badgeMaxWidthFraction;
+ (int)badgeRightMargin;
+ (int)badgeTopMargin;
+ (double)bellRateLimit;
+ (BOOL)bordersOnlyInLightMode;
+ (BOOL)bootstrapDaemon;
+ (BOOL)clearBellIconAggressively;
+ (BOOL)cmdClickWhenInactiveInvokesSemanticHistory;
+ (double)coloredSelectedTabOutlineStrength;
+ (double)coloredUnselectedTabTextProminence;
+ (double)commandHistoryUsePower;
+ (double)commandHistoryAgePower;
+ (double)compactEdgeDragSize;
+ (double)compactMinimalTabBarHeight;
+ (NSString *)composerClearSequence;
+ (BOOL)concurrentMutation;
+ (BOOL)conservativeURLGuessing;
+ (BOOL)convertItalicsToReverseVideoForTmux;
+ (BOOL)convertTabDragToWindowDragForSolitaryTabInCompactOrMinimalTheme;
+ (BOOL)copyBackgroundColor;
+ (BOOL)copyWithStylesByDefault;
+ (CGFloat)customTabBarFontSize;
+ (BOOL)darkThemeHasBlackTitlebar;
+ (CGFloat)defaultTabBarHeight;
+ (void)setDefaultTabBarHeight:(CGFloat)value;
+ (int)defaultTabStopWidth;
+ (NSString *)defaultURLScheme;
+ (BOOL)detectPasswordInput;
+ (BOOL)disableAdaptiveFrameRateInInteractiveApps;
+ (BOOL)disableAppNap;
+ (BOOL)disableCustomBoxDrawing;
+ (BOOL)disableDECRQCRA;
+ (BOOL)disableDocumentedEditedIndicator;
+ (void)setNoSyncDisableDECRQCRA:(BOOL)newValue;
+ (BOOL)disableMetalWhenIdle;
+ (BOOL)disablePasswordManagerAnimations;
+ (BOOL)disablePotentiallyInsecureEscapeSequences;
+ (BOOL)disableTabBarTooltips;
+ (BOOL)disableTopRightIndicators;
+ (BOOL)disableTmuxWindowPositionRestoration;
+ (BOOL)disableTmuxWindowResizing;
+ (BOOL)disableWindowShadowWhenTransparencyOnMojave;
+ (BOOL)disableWindowShadowWhenTransparencyPreMojave;
+ (BOOL)disableWindowSizeSnap;
+ (BOOL)disallowCopyEmptyString;
// Use PTYScrollView.shouldDismember, since disabling dismemberment is 10.15+
+ (BOOL)dismemberScrollView;
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
+ (void)setEchoProbeDuration:(double)value;
+ (BOOL)enableCharacterAccentMenu;
+ (BOOL)enableSemanticHistoryOnNetworkMounts;
+ (BOOL)enableUnderlineSemanticHistoryOnCmdHover;
+ (BOOL)escapeWithQuotes;
+ (BOOL)excludeBackgroundColorsFromCopiedStyle;
+ (BOOL)experimentalKeyHandling;
+ (double)extraSpaceBeforeCompactTopTabBar;
+ (double)fakeNotchHeight;
+ (NSString *)fallbackLCCType;
+ (BOOL)fastForegroundJobUpdates;
+ (BOOL)fastTriggerRegexes;
+ (BOOL)fastTrackpad;
+ (double)findDelaySeconds;

// Regular expression for finding URLs for Edit>Find>Find URLs
+ (NSString *)findUrlsRegex;
+ (BOOL)fixMouseWheel;
+ (NSString *)fontsForGenerousRounding;
+ (BOOL)focusNewSplitPaneWithFocusFollowsMouse;
+ (BOOL)focusReportingEnabled;
+ (BOOL)forceAntialiasingOnRetina;
+ (BOOL)fontChangeAffectsBroadcastingSessions;
+ (double)fractionOfCharacterSelectingNextNeighbor;
+ (BOOL)fullHeightCursor;
+ (NSString *)gitSearchPath;
+ (double)gitTimeout;
+ (BOOL)hdrCursor;
+ (BOOL)hideStuckTooltips;
+ (BOOL)highVisibility;
+ (double)hotKeyDoubleTapMaxDelay;
+ (double)hotKeyDoubleTapMinDelay;
+ (double)hotkeyTermAnimationDuration;
+ (BOOL)hotkeyWindowsExcludedFromCycling;
+ (BOOL)hotkeyWindowFloatsAboveOtherWindows DEPRECATED_ATTRIBUTE;
+ (double)idempotentTriggerModeRateLimit;
+ (double)idleTimeSeconds;
+ (BOOL)ignoreHardNewlinesInURLs;
+ (BOOL)includePasteHistoryInAdvancedPaste;
+ (BOOL)includeShortcutInWindowsMenu;
+ (BOOL)indicateBellsInDockBadgeLabel;
+ (double)indicatorFlashInitialAlpha;
+ (double)invalidateShadowTimesPerSecond;
+ (BOOL)jiggleTTYSizeOnClearBuffer;
+ (BOOL)killJobsInServersOnQuit;
+ (BOOL)killSessionsOnLogout;
+ (NSString *)lastpassGroups;
+ (BOOL)laxNilPolicyInInterpolatedStrings;
+ (BOOL)logDrawingPerformance;
+ (BOOL)logRestorableStateSize;
+ (BOOL)logTimestampsWithPlainText;
+ (BOOL)lowFiCombiningMarks;
+ (double)maximumFrameRate;
+ (int)maxHistoryLinesToRestore;
+ (int)maximumBytesToProvideToServices;
+ (int)maximumBytesToProvideToPythonAPI;
+ (int)maximumNumberOfTriggerCommands;
+ (int)maxSemanticHistoryPrefixOrSuffix;
+ (double)metalRedrawPeriod;
+ (double)metalSlowFrameRate;
+ (BOOL)middleClickClosesTab;
+ (int)minCompactTabWidth;
+ (double)minimalDeslectedColoredTabAlpha;
+ (double)minimalEdgeDragSize;
+ (double)minimalSelectedTabUnderlineProminence;
+ (double)minimalSplitPaneDividerProminence;
+ (double)minimalTabStyleBackgroundColorDifference;
+ (BOOL)minimalTabStyleTreatLeftInsetAsPartOfFirstTab;
+ (double)minimalTabStyleOutlineStrength;
+ (int)minimumTabDragDistance;
+ (double)minimalTextLegibilityAdjustment;
+ (double)minimumTabLabelWidth;
+ (int)minimumWeightDifferenceForBoldFont;
+ (double)minRunningTime;
+ (int)minTabWidth;
+ (BOOL)multiserver;
+ (NSString *)nativeRenderingCSSLight;
+ (NSString *)nativeRenderingCSSDark;
+ (BOOL)navigatePanesInReadingOrder;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)noSyncDontWarnAboutTmuxPause;
+ (void)setNoSyncDontWarnAboutTmuxPause:(BOOL)value;
+ (BOOL)noSyncSuppressDownloadConfirmation;
+ (BOOL)noSyncDoNotWarnBeforeMultilinePaste;
+ (void)setNoSyncDoNotWarnBeforeMultilinePaste:(BOOL)value;
+ (NSString *)noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey;
+ (BOOL)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt;
+ (void)setNoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt:(BOOL)value;
+ (NSString *)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPromptUserDefaultsKey;
+ (BOOL)noSyncNeverAskAboutMouseReportingFrustration;
+ (void)setNoSyncNeverAskAboutMouseReportingFrustration:(BOOL)value;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForFile;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForUrl;
+ (BOOL)noSyncReplaceProfileWarning;
+ (BOOL)noSyncSilenceAnnoyingBellAutomatically;
+ (BOOL)noSyncSuppressAnnyoingBellOffer;
+ (BOOL)noSyncSuppressBadPWDInArrangementWarning;
+ (void)setNoSyncSuppressBadPWDInArrangementWarning:(BOOL)value;
+ (BOOL)noSyncSuppressBroadcastInputWarning;
+ (BOOL)noSyncSuppressCaptureOutputRequiresShellIntegrationWarning;
+ (BOOL)noSyncSuppressCaptureOutputToolNotVisibleWarning;
+ (BOOL)noSyncSuppressClipboardAccessDeniedWarning;
+ (void)setNoSyncSuppressClipboardAccessDeniedWarning:(BOOL)value;
+ (BOOL)noSyncSuppressMissingProfileInArrangementWarning;
+ (void)setNoSyncSuppressMissingProfileInArrangementWarning:(BOOL)value;
+ (BOOL)NoSyncSuppressRestartSessionConfirmationAlert;
+ (BOOL)noSyncTipsDisabled;
+ (NSString *)noSyncVariablesToReport;
+ (void)setNoSyncVariablesToReport:(NSString *)value;
+ (double)notificationOcclusionThreshold;
+ (int)numberOfLinesForAccessibility;
+ (BOOL)openFileInNewWindows;
+ (BOOL)openFileOverridesSendText;
+ (BOOL)openNewWindowAtStartup;
+ (BOOL)openUntitledFile;
+ (int)optimumTabWidth;
+ (BOOL)optionIsMetaForSpecialChars;
+ (BOOL)oscColorReport16Bits;
+ (BOOL)p3;
+ (int)pasteHistoryMaxOptions;
+ (BOOL)pastingClearsSelection;
+ (NSString *)pathsToIgnore;
+ (NSString *)pathToFTP;
+ (NSString *)pathToTelnet;
+ (BOOL)performDictionaryLookupOnQuickLook;
+ (BOOL)performSQLiteIntegrityCheck;
+ (BOOL)pinEditSession;
+ (BOOL)pinchToChangeFontSizeDisabled;
+ (BOOL)pollForTmuxForegroundJob;
+ (BOOL)postFakeFlagsChangedEvents;
+ (BOOL)preferSpeedToFullLigatureSupport;
+ (NSString *)preferredBaseDir;
+ (const BOOL *)preventEscapeSequenceFromClearingHistory;
+ (BOOL)saveScrollBufferWhenClearing;
+ (void)setPreventEscapeSequenceFromClearingHistory:(const BOOL *)value;
+ (const BOOL *)preventEscapeSequenceFromChangingProfile;
+ (void)setPreventEscapeSequenceFromChangingProfile:(const BOOL *)value;
+ (BOOL)profilesWindowJoinsActiveSpace;
+ (BOOL)promptForPasteWhenNotAtPrompt;
+ (NSString *)pythonRuntimeBetaDownloadURL;
+ (NSString *)pythonRuntimeDownloadURL;
+ (void)setPromptForPasteWhenNotAtPrompt:(BOOL)value;
+ (BOOL)proportionalScrollWheelReporting;
+ (int)quickPasteBytesPerCall;
+ (double)quickPasteDelayBetweenCalls;
+ (BOOL)recordTimerDebugInfo;
+ (BOOL)remapModifiersWithoutEventTap;

// Remember window positions? If off, lets the OS pick the window position. Smart window placement takes precedence over this.
+ (BOOL)rememberWindowPositions;

+ (BOOL)removeAddTabButton;
+ (BOOL)restrictSemanticHistoryPrefixAndSuffixToLogicalWindow;
+ (BOOL)requireCmdForDraggingText;
+ (BOOL)resetSGROnPrompt;
+ (BOOL)restoreWindowContents;
+ (BOOL)restoreWindowsWithinScreens;
+ (BOOL)retinaInlineImages;
+ (BOOL)runJobsInServers;
+ (BOOL)saveToPasteHistoryWhenSecureInputEnabled;
+ (double)scrollWheelAcceleration;
+ (NSString *)searchCommand;
+ (BOOL)selectsTabsOnMouseDown;
+ (BOOL)sensitiveScrollWheel;
+ (BOOL)serializeOpeningMultipleFullScreenWindows;
+ (BOOL)setCookie;
+ (void)setSetCookie:(BOOL)value;
+ (double)shortLivedSessionDuration;
+ (BOOL)shouldSetLCTerminal;
+ (BOOL)shouldSetTerminfoDirs;
+ (BOOL)showAutomaticProfileSwitchingBanner;
+ (BOOL)showBlockBoundaries;
+ (BOOL)showHintsInSplitPaneMenuItems;
+ (BOOL)showMetalFPSmeter;
+ (BOOL)showLocationsInScrollbar;
+ (BOOL)showMarksInScrollbar;
+ (BOOL)showSessionRestoredBanner;
+ (BOOL)showTimestampsByDefault;
+ (BOOL)showWindowTitleWhenTabBarInvisible;
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
+ (int)smartSelectionRadius;
+ (BOOL)solidUnderlines;
+ (NSString *)splitPaneColor;
+ (BOOL)squareWindowCorners;
+ (BOOL)sshURLsSupportPath;
+ (BOOL)startDebugLoggingAutomatically;
+ (double)statusBarHeight;
+ (BOOL)statusBarIcon;
+ (BOOL)stealKeyFocus;
+ (BOOL)storeStateInSqlite;
+ (BOOL)supportDecsetMetaSendsEscape;
+ (BOOL)supportREPCode;
+ (BOOL)suppressMultilinePasteWarningWhenNotAtShellPrompt;
+ (BOOL)suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline;
+ (BOOL)suppressRestartAnnouncement;
+ (BOOL)swapFindNextPrevious;
+ (BOOL)synchronizeQueryWithFindPasteboard;
+ (void)setSuppressRestartAnnouncement:(BOOL)value;
+ (double)tabAutoShowHoldTime;
+ (NSString *)tabColorMenuOptions;
+ (double)tabFlashAnimationDuration;
+ (BOOL)tabsWrapAround;
+ (BOOL)tabTitlesUseSmartTruncation;
+ (BOOL)throttleMetalConcurrentFrames;
+ (double)timeBetweenBlinks;
+ (double)timeBetweenTips;
+ (void)setTimeBetweenTips:(double)time;
+ (BOOL)synergyModifierRemappingEnabled;
+ (double)timeoutForStringEvaluation;
+ (double)timeoutForDaemonAttachment;
+ (double)timeToWaitForEmojiPanel;
+ (BOOL)tmuxIncludeClientNameInWindowTitle;
+ (NSString *)tmuxTitlePrefix;
+ (BOOL)tmuxVariableWindowSizesSupported;
+ (const BOOL *)tmuxWindowsShouldCloseAfterDetach;
+ (void)setTmuxWindowsShouldCloseAfterDetach:(const BOOL *)value;
+ (BOOL)tolerateUnrecognizedTmuxCommands;
+ (NSString *)toolbeltFont;
+ (double)toolbeltFontSize;
+ (BOOL)trackingRunloopForLiveResize;
+ (BOOL)traditionalVisualBell;
+ (NSString *)trailingPunctuationMarks;
+ (BOOL)translateScreenToXterm;
+ (int)triggerRadius;
+ (BOOL)trimWhitespaceOnCopy;
+ (BOOL)typingClearsSelection;
+ (double)underlineCursorHeight;
+ (double)underlineCursorOffset;
+ (BOOL)underlineHyperlinks;
+ (double)updateScreenParamsDelay;
+ (BOOL)useCustomTabBarFontSize;
+ (BOOL)useRestorableStateController;
+ (BOOL)useShortcutAccessoryViewController;
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
+ (BOOL)useNewContentFormat;
+ (BOOL)useOldStyleDropDownViews;
+ (BOOL)useOpenDirectory;
+ (BOOL)useSystemCursorWhenPossible;
+ (BOOL)useUnevenTabs;
+ (double)userNotificationTriggerRateLimit;
+ (BOOL)openProfilesInNewWindow;
+ (BOOL)vs16Supported;
+ (BOOL)vs16SupportedInPrimaryScreen;
+ (BOOL)workAroundBigSurBug;
+ (BOOL)workAroundMultiDisplayOSBug;
+ (BOOL)workAroundNumericKeypadBug;
+ (int)xtermVersion;
+ (CGFloat)verticalBarCursorWidth;
+ (NSString *)viewManPageCommand;
+ (BOOL)wrapFocus;
+ (BOOL)zeroWidthSpaceAdvancesCursor;
+ (BOOL)zippyTextDrawing;



@end
