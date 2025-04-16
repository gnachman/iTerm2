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
extern NSString *const kAdvancedSettingSetter;
extern NSString *const kAdvancedSettingGetter;

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
+ (BOOL)addUtilitiesToPATH;
+ (BOOL)advancedPasteWaitsForPromptByDefault;
+ (BOOL)aggressiveBaseCharacterDetection;
+ (BOOL)aggressiveFocusFollowsMouse;
+ (NSString *)aiModernModelPrefixes;
+ (int)aiResponseMaxTokens;
+ (double)alertTriggerRateLimit;
+ (BOOL)alertsIndicateShortcuts;
+ (BOOL)allowDragOfTabIntoNewWindow;
+ (BOOL)allowDragOnAddTabButton;
+ (BOOL)allowIdempotentTriggers;
+ (BOOL)allowInteractiveSwipeBetweenTabs;
+ (BOOL)allowTabbarInTitlebarAccessoryBigSur;
+ (BOOL)allowLiveResize;
+ (BOOL)alternateMouseScroll;
+ (BOOL)alwaysUseLineStyleMarks;
+ (BOOL)alwaysUseStatusBarComposer;
+ (double)alphaForDeselectedCommandShade;
#if DEBUG
+ (NSString *)alternateSSHIntegrationScript;
#endif
+ (BOOL)animateGraphStatusBarComponents;
+ (BOOL)autoSearch;
+ (void)setAlternateMouseScroll:(BOOL)value;
+ (NSString *)alternateMouseScrollStringForDown;
+ (NSString *)alternateMouseScrollStringForUp;
+ (BOOL)alwaysAcceptFirstMouse;
+ (int)alwaysWarnBeforePastingOverSize;
+ (BOOL)anonymousTmuxWindowsOpenInCurrentWindow;
+ (BOOL)appendToExistingDebugLog;
+ (BOOL)aquaSKKBugfixEnabled;
+ (BOOL)autoLockSessionNameOnEdit;
+ (int)autocompleteMaxOptions;
+ (BOOL)autodetectMouseReportingStuck;
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
+ (BOOL)bidi;
+ (BOOL)alternateScreenBidi;
+ (BOOL)bordersOnlyInLightMode;
+ (BOOL)bounceOnInactiveBell;
+ (BOOL)bootstrapDaemon;
#if ITERM2_SHARED_ARC
+ (NSString *)browserBundleID;
#endif  // ITERM2_SHARED_ARC
+ (BOOL)chaseAnchoredScreen;
+ (BOOL)channelsEnabled;
+ (BOOL)clearBellIconAggressively;
+ (BOOL)cmdClickWhenInactiveInvokesSemanticHistory;
+ (int)codeciergeCommandWarningCount;
+ (NSString *)codeciergeGhostRidingPrompt;
+ (NSString *)codeciergeRegularPrompt;
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
+ (double)darkModeInactiveTabDarkness;
+ (BOOL)darkThemeHasBlackTitlebar;
+ (CGFloat)defaultTabBarHeight;
+ (void)setDefaultTabBarHeight:(CGFloat)value;
+ (int)defaultTabStopWidth;
+ (NSString *)defaultURLScheme;
+ (BOOL)defaultIconsUsingLetters;
+ (BOOL)defaultWideMode;
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
+ (BOOL)disableSmartSelectionActionsOnClick;
+ (BOOL)disableTabBarTooltips;
+ (BOOL)disableTopRightIndicators;
+ (BOOL)disableTmuxWindowPositionRestoration;
+ (BOOL)disableTmuxWindowResizing;
+ (BOOL)disableWindowShadowWhenTransparencyOnMojave;
+ (BOOL)disableWindowShadowWhenTransparencyPreMojave;
+ (BOOL)disableWindowSizeSnap;
+ (BOOL)disallowCopyEmptyString;
+ (BOOL)disclaimChildren;
// Use PTYScrollView.shouldDismember, since disabling dismemberment is 10.15+
+ (BOOL)dismemberScrollView;
+ (BOOL)disregardDockSettingToOpenTabsInsteadOfWindows;
+ (BOOL)dockIconTogglesWindow DEPRECATED_ATTRIBUTE;
+ (BOOL)doNotSetCtype;
+ (BOOL)doubleClickTabToEdit;
+ (BOOL)doubleReportScrollWheel;
+ (NSString *)downloadsDirectory;
+ (double)noSyncDownloadPrefsTimeout;
+ (BOOL)drawBottomLineForHorizontalTabBar;
+ (BOOL)drawOutlineAroundCursor;
+ (BOOL)dwcLineCache;
+ (double)dynamicProfilesNotificationLatency;
+ (NSString *)dynamicProfilesPath;
+ (double)echoProbeDuration;
+ (void)setEchoProbeDuration:(double)value;
+ (BOOL)enableCharacterAccentMenu;
+ (BOOL)enableCmdClickPromptForShowCommandInfo;

#if ITERM2_SHARED_ARC
+ (BOOL)enableSecureKeyboardEntryAutomatically;
#endif  // ITERM2_SHARED_ARC

+ (BOOL)enableSemanticHistoryOnNetworkMounts;
+ (BOOL)enableUnderlineSemanticHistoryOnCmdHover;
+ (BOOL)enableZoomMenu;
+ (BOOL)escapeWithQuotes;
+ (BOOL)excludeBackgroundColorsFromCopiedStyle;
+ (BOOL)excludeUtunFromNetworkUtilization;
+ (BOOL)experimentalKeyHandling;
+ (double)extraSpaceBeforeCompactTopTabBar;
+ (double)fakeNotchHeight;
+ (NSString *)fallbackLCCType;
+ (BOOL)fastForegroundJobUpdates;
+ (BOOL)fastTriggerRegexes;
+ (BOOL)fastTrackpad;
+ (NSString *)fileDropCoprocess;
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
+ (BOOL)fullWidthFlags;
+ (BOOL)generativeAIAllowed;
+ (NSString *)gitSearchPath;
+ (double)gitTimeout;
+ (BOOL)hdrCursor;
+ (BOOL)hideStuckTooltips;
+ (BOOL)highVisibility;
+ (double)horizontalScrollingSensitivity;
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
+ (double)lightModeInactiveTabDarkness;
+ (NSString *)llmPlatform;
+ (BOOL)logDrawingPerformance;
+ (BOOL)logRestorableStateSize;
+ (NSString *)logTimestampFormat;
+ (BOOL)logTimestampsWithPlainText;
+ (BOOL)logToSyslog;
+ (BOOL)lowFiCombiningMarks;
+ (BOOL)makeSomePowerlineSymbolsWide;
+ (int)maxURLLength;
+ (double)maximumFrameRate;
+ (int)maxHistoryLinesToRestore;
+ (int)maximumBytesToProvideToServices;
+ (int)maximumBytesToProvideToPythonAPI;
+ (int)maximumNumberOfTriggerCommands;
+ (int)maxSemanticHistoryPrefixOrSuffix;
+ (double)menuTipDelay;
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
+ (BOOL)naturalScrollingAffectsHorizontalMouseReporting;
+ (BOOL)navigatePanesInReadingOrder;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)noSyncDisableOpenURL;
+ (void)setNoSyncDisableOpenURL:(BOOL)value;
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
+ (BOOL)noSyncNeverAskAboutDEC2048Frustration;
+ (void)setNoSyncNeverAskAboutMouseReportingFrustration:(BOOL)value;
+ (void)setNoSyncNeverAskAboutDEC2048Frustration:(BOOL)value;
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
+ (NSString *)onePasswordAccount;
+ (void)setOnePasswordAccount:(NSString *)value;
+ (BOOL)openFileInNewWindows;
+ (BOOL)openFileOverridesSendText;
+ (BOOL)openNewWindowAtStartup;
+ (BOOL)openUntitledFile;
+ (int)optimumTabWidth;
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
+ (BOOL)placeTabsInTitlebarAccessoryInFullScreen;
+ (BOOL)pollForTmuxForegroundJob;
+ (BOOL)postFakeFlagsChangedEvents;
+ (BOOL)preferSpeedToFullLigatureSupport;
+ (NSString *)preferredBaseDir;
+ (const BOOL *)preventEscapeSequenceFromClearingHistory;
+ (BOOL)prioritizeSmartSelectionActions;
+ (BOOL)saveScrollBufferWhenClearing;
+ (BOOL)saveProfilesToRecentDocuments;
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
+ (BOOL)remapModifiersWithoutEventTap;
+ (BOOL)rememberTmuxWindowSizes;

// Remember window positions? If off, lets the OS pick the window position. Smart window placement takes precedence over this.
+ (BOOL)rememberWindowPositions;

+ (BOOL)removeAddTabButton;
+ (BOOL)reportOnFirstMouse;
+ (BOOL)restrictSemanticHistoryPrefixAndSuffixToLogicalWindow;
+ (BOOL)requireCmdForDraggingText;
+ (BOOL)requireOptionToDragSplitPaneTitleBar;
+ (BOOL)requireSlashInURLGuess;
+ (BOOL)resetSGROnPrompt;
+ (BOOL)restoreKeyModeAutomaticallyOnHostChange;
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
+ (BOOL)showButtonsForSelectedCommand;
+ (BOOL)showHintsInSplitPaneMenuItems;
+ (BOOL)showMetalFPSmeter;
+ (BOOL)showLocationsInScrollbar;
+ (BOOL)showMarksInScrollbar;
+ (BOOL)showPinnedIndicator;
+ (void)setShowSecureKeyboardEntryIndicator:(BOOL)value;
+ (BOOL)showSecureKeyboardEntryIndicator;
+ (BOOL)showSessionRestoredBanner;
+ (BOOL)showURLPreviewForSemanticHistory;
+ (BOOL)showWindowTitleWhenTabBarInvisible;
+ (BOOL)showYellowMarkForJobStoppedBySignal;
+ (BOOL)silentUserNotifications;
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
+ (BOOL)smartLoggingWithAutoComposer;
+ (int)smartSelectionRadius;
+ (BOOL)solidUnderlines;
+ (NSString *)splitPaneColor;
+ (BOOL)squareWindowCorners;
+ (NSString *)sshSchemePath;
+ (BOOL)sshURLsSupportPath;
+ (BOOL)startDebugLoggingAutomatically;
+ (double)statusBarHeight;
+ (BOOL)statusBarIcon;
+ (BOOL)stealKeyFocus;
+ (BOOL)storeStateInSqlite;
+ (NSString *)successSound;
+ (NSString *)errorSound;
+ (BOOL)supportDecsetMetaSendsEscape;
+ (BOOL)supportREPCode;
+ (BOOL)suppressMultilinePasteWarningWhenNotAtShellPrompt;
+ (BOOL)suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline;
+ (BOOL)supportPowerlineExtendedSymbols;
+ (BOOL)suppressRestartAnnouncement;
+ (BOOL)swapFindNextPrevious;
+ (BOOL)synchronizeQueryWithFindPasteboard;
+ (void)setSuppressRestartAnnouncement:(BOOL)value;
+ (double)tabAutoShowHoldTime;
+ (NSString *)tabColorMenuOptions;
+ (double)tabFlashAnimationDuration;
+ (BOOL)tabsWrapAround;
+ (BOOL)tabTitlesUseSmartTruncation;
+ (BOOL)tabCloseButtonsAlwaysVisible;
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
+ (NSString *)unameCommand;
+ (double)underlineCursorHeight;
+ (double)underlineCursorOffset;
+ (BOOL)underlineHyperlinks;
+ (double)updateScreenParamsDelay;
+ (BOOL)useCustomTabBarFontSize;
+ (BOOL)useDoubleClickDelayForCommandSelection;
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
+ (BOOL)useSSHIntegrationForURLOpening;
+ (BOOL)useSystemCursorWhenPossible;
+ (BOOL)useUnevenTabs;
+ (double)userNotificationTriggerRateLimit;
+ (BOOL)openProfilesInNewWindow;
+ (NSString *)validCharactersInSSHUserNames;
+ (BOOL)vs16Supported;
+ (BOOL)vs16SupportedInPrimaryScreen;

+ (BOOL)warnAboutSecureKeyboardInputWithOpenCommand;
+ (void)setWarnAboutSecureKeyboardInputWithOpenCommand:(BOOL)value;

+ (NSString *)webUserAgent;
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
