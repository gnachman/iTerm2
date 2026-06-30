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
    kiTermAdvancedSettingTypeOptionalBoolean,

    // An integer whose value is the index of a choice presented in a popup
    // button. The kAdvancedSettingOptions key holds an array of option titles.
    kiTermAdvancedSettingTypeIntEnum
} iTermAdvancedSettingType;

// Where a tmux window created outside iTerm2 (e.g., by running `tmux new-window`
// at the command line) should open. Stored as the integer value of
// +anonymousTmuxWindowsOpenInCurrentWindow. The raw values are persisted in user
// defaults, so do not renumber them.
typedef NS_ENUM(int, iTermOpenAnonymousTmuxWindowLocation) {
    iTermOpenAnonymousTmuxWindowLocationNewWindow = 0,
    iTermOpenAnonymousTmuxWindowLocationFocusedWindow = 1,
    iTermOpenAnonymousTmuxWindowLocationTopmostSessionWindow = 2,
};

extern NSString *const kAdvancedSettingIdentifier;
extern NSString *const kAdvancedSettingType;
extern NSString *const kAdvancedSettingDefaultValue;
extern NSString *const kAdvancedSettingDescription;
extern NSString *const kAdvancedSettingSetter;
extern NSString *const kAdvancedSettingGetter;

// For kiTermAdvancedSettingTypeIntEnum: an NSArray<NSString *> of option titles,
// indexed by the setting's integer value.
extern NSString *const kAdvancedSettingOptions;

// The model posts this notification when it makes a change.
extern NSString *const iTermAdvancedSettingsDidChange;

+ (void)enumerateDictionaries:(void (^)(NSDictionary *))block;
+ (void)loadAdvancedSettingsFromUserDefaults;

#pragma mark - Accessors

+ (BOOL)aboutToPasteTabsWithCancel;
+ (BOOL)accelerateUploads;
+ (BOOL)webKitAdblockEnabled;
+ (void)setWebKitAdblockEnabled:(BOOL)value;
+ (NSString *)adblockListURL;
+ (void)setAdblockListURL:(NSString *)value;
+ (BOOL)browserProxyEnabled;
+ (void)setBrowserProxyEnabled:(BOOL)value;
+ (NSString *)browserProxyHost;
+ (void)setBrowserProxyHost:(NSString *)value;
+ (int)browserProxyPort;
+ (void)setBrowserProxyPort:(int)value;
+ (BOOL)acceptOSC7;
+ (double)activeUpdateCadence;
+ (int)adaptiveFrameRateThroughputThreshold;
+ (BOOL)addTabButtonUsesCurrentProfile;
+ (BOOL)addUtilitiesToPATH;
+ (BOOL)advancedPasteWaitsForPromptByDefault;
+ (BOOL)aggressiveBaseCharacterDetection;
+ (BOOL)aggressiveFocusFollowsMouse;
+ (NSString *)aiModelCatalogURL;
+ (NSString *)aiModernModelPrefixes;
+ (NSString *)aiProxy;
+ (double)alertTriggerRateLimit;
+ (BOOL)alertsIndicateShortcuts;
+ (BOOL)allowDragOfTabIntoNewWindow;
+ (BOOL)allowDragOnAddTabButton;
+ (BOOL)allowIdempotentTriggers;
+ (BOOL)allowInteractiveSwipeBetweenTabs;
+ (BOOL)allowTabbarInTitlebarAccessoryBigSur;
+ (BOOL)allowLiveResize;
+ (BOOL)allowSendingFunctionKeysToCocoa;
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
+ (int)anonymousTmuxWindowsOpenInCurrentWindow;
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
+ (BOOL)alternateScreenBidi;
+ (BOOL)bordersOnlyInLightMode;
+ (BOOL)bounceOnInactiveBell;
+ (BOOL)bootstrapDaemon;
#if ITERM2_SHARED_ARC
+ (NSString *)browserBundleID;
#endif  // ITERM2_SHARED_ARC
+ (NSString *)browserPluginPathHint;
+ (void)setBrowserPluginPathHint:(NSString *)newValue;
+ (BOOL)browserProfiles;
+ (BOOL)companionStreamFrameNumbers;
+ (int)companionStreamMaxLeadMilliseconds;
+ (int)companionStreamMaxQueueDepth;
+ (double)companionStreamBitrateMultiplier;
+ (int)bufferDepth;
+ (BOOL)chaseAnchoredScreen;
+ (BOOL)channelsEnabled;
+ (BOOL)clearBellIconAggressively;
+ (NSString *)clippingSeparator;
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
+ (BOOL)conservativeURLGuessing;
+ (BOOL)convertItalicsToReverseVideoForTmux;
+ (BOOL)convertItalicsToReverseVideoForTmuxBugwardsCompatible;
+ (BOOL)convertTabDragToWindowDragForSolitaryTabInCompactOrMinimalTheme;
+ (BOOL)copyBackgroundColor;
+ (BOOL)copyWithStylesByDefault;
+ (CGFloat)cursorAnimationMinDistance;
+ (double)cursorSmearAnimationDuration;
+ (double)cursorSlideAnimationDuration;
+ (int)cursorSlideAnimationMaxCells;
+ (CGFloat)customTabBarFontSize;
+ (double)darkModeInactiveTabDarkness;
+ (BOOL)darkThemeHasBlackTitlebar;
+ (BOOL)debugShowPromptMarkRangesInLegacyRenderer;
+ (CGFloat)defaultTabBarHeight;
+ (void)setDefaultTabBarHeight:(CGFloat)value;
+ (int)defaultTabStopWidth;
+ (NSString *)defaultURLScheme;
+ (BOOL)defaultIconsUsingLetters;
+ (BOOL)defaultWideMode;
+ (BOOL)detectParagraphDirection;
+ (BOOL)detectPasswordInput;
+ (double)detectPasswordInputDebounce;
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
+ (BOOL)twoRowTabBar;
+ (BOOL)doubleReportScrollWheel;
+ (NSString *)downloadsDirectory;
+ (double)noSyncDownloadPrefsTimeout;
+ (BOOL)noSyncOpenLinksInApp;
+ (void)setNoSyncOpenLinksInApp:(BOOL)value;
+ (BOOL)drawBottomLineForHorizontalTabBar;
+ (BOOL)drawOutlineAroundCursor;
+ (BOOL)dryRunEraseAllSettingsAndData;
+ (BOOL)dwcLineCache;
+ (double)dynamicProfilesNotificationLatency;
+ (NSString *)dynamicProfilesPath;
+ (BOOL)addDynamicTagToDynamicProfiles;
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
+ (BOOL)extendBackgroundColorIntoMargins;
+ (double)extraSpaceBeforeCompactTopTabBar;
+ (double)fakeNotchHeight;
+ (NSString *)fakeFullyQualifiedDomainName;
+ (NSString *)fallbackLCCType;
+ (BOOL)fastForegroundJobUpdates;
+ (BOOL)fastTriggerRegexes;
+ (BOOL)fastTrackpad;
+ (NSString *)fileDropCoprocess;
+ (NSString *)filenameCharacterSet;
+ (double)findDelaySeconds;

// Regular expression for finding URLs for Edit>Find>Find URLs
+ (NSString *)findUrlsRegex;

// When finding URLs, extend results across soft boundaries (like tmux pane dividers)
+ (BOOL)findURLsRespectsSoftBoundaries;

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
+ (BOOL)companionPairingAllowed;
+ (NSString *)companionRelayOrigin;
+ (NSString *)gitSearchPath;
+ (double)gitTimeout;
+ (void)setGitTimeout:(double)value;
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
+ (BOOL)jiggleTTYSizeOnClearBuffer;
+ (BOOL)killJobsInServersOnQuit;
+ (BOOL)killSessionsOnLogout;
+ (NSString *)lastpassGroups;
+ (BOOL)laxNilPolicyInInterpolatedStrings;
+ (BOOL)leftAlignTitleBarMinimalTahoe;
+ (double)lightModeInactiveTabDarkness;
+ (NSString *)llmPlatform;
+ (BOOL)logDrawingPerformance;
+ (BOOL)logRestorableStateSize;
+ (NSString *)logTimestampFormat;
+ (BOOL)logTimestampsWithPlainText;
+ (BOOL)logToSyslog;
+ (BOOL)aiChatVerboseConsoleLogging;
+ (BOOL)aiChatRawWireLogging;
+ (BOOL)lowFiCombiningMarks;
+ (double)lowPowerModeFrameRate;
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
+ (BOOL)moveLeftAfterClosingTab;
+ (BOOL)multiserver;
+ (NSString *)nativeRenderingCSSLight;
+ (NSString *)nativeRenderingCSSDark;
+ (BOOL)naturalScrollingAffectsHorizontalMouseReporting;
+ (BOOL)navigatePanesInReadingOrder;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)noSyncBrowserUpsell;
+ (void)setNoSyncBrowserUpsell:(BOOL)value;
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
+ (int)numberOfLinesForAccessibility;
+ (NSString *)onePasswordAccount;
+ (void)setOnePasswordAccount:(NSString *)value;
+ (BOOL)openFileInNewWindows;
+ (BOOL)openFileInSplitPanes;
+ (BOOL)openFileInVerticalSplitPane;
+ (int)newInstanceOpenStyle;
+ (BOOL)openFileOverridesSendText;
+ (BOOL)openNewWindowAtStartup;
+ (double)openQuicklyAnimationDuration;
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
+ (int)pinnedTabWidth;
+ (BOOL)pinchToChangeFontSizeDisabled;
+ (BOOL)placeTabsInTitlebarAccessoryInFullScreen;
+ (BOOL)pollForTmuxForegroundJob;
+ (BOOL)postFakeFlagsChangedEvents;
+ (BOOL)preconvertStringsOnParserThread;
+ (BOOL)asyncPreconvertStrings;
+ (int)asyncPreconvertMinStringLength;
+ (int)asyncPreconvertMaxOutstandingBytes;
+ (BOOL)logNonASCIIStringLengthHistogram;
+ (BOOL)preferSpeedToFullLigatureSupport;
+ (BOOL)enableContextualAlternates;
+ (BOOL)preserveFontSizeOnAutomaticProfileSwitch;
+ (NSString *)preferredBaseDir;
+ (const BOOL *)preventEscapeSequenceFromClearingHistory;
+ (BOOL)prioritizeSmartSelectionActions;
+ (BOOL)saveScrollBufferWhenClearing;
+ (BOOL)saveScrollbackWhenCursorMovesAbovePrompt;
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
+ (BOOL)tmuxWindowsOpenInBackground;
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
+ (BOOL)revealExportedSettingsAndData;
+ (BOOL)rightJustifyRTLLines;
+ (BOOL)runJobsInServers;
+ (BOOL)saveToPasteHistoryWhenSecureInputEnabled;
+ (double)scrollWheelAcceleration;
+ (NSString *)searchCommand;
+ (void)setSearchCommand:(NSString *)newValue;
+ (NSString *)searchSuggestURL;
+ (void)setSearchSuggestURL:(NSString *)newValue;
+ (BOOL)selectsTabsOnMouseDown;
+ (BOOL)sensitiveScrollWheel;
+ (BOOL)serializeOpeningMultipleFullScreenWindows;
+ (int)screenshotMaxPixelHeight;
+ (NSString *)screenshotSaveLocation;
+ (BOOL)setCookie;
+ (void)setSetCookie:(BOOL)value;
+ (BOOL)setIT2AppPath;
+ (void)setSetIT2AppPath:(BOOL)value;
+ (double)shortLivedSessionDuration;
+ (BOOL)shouldSetLCTerminal;
+ (BOOL)shouldSetTerminfoDirs;
+ (BOOL)showAutomaticProfileSwitchingBanner;
+ (BOOL)showBlockBoundaries;
+ (BOOL)showButtonsForSelectedCommand;
+ (BOOL)showDirtyRectsInLegacyRenderer;
+ (BOOL)showHintsInSplitPaneMenuItems;
+ (BOOL)showMetalFPSmeter;
+ (void)setShowMetalFPSmeter:(BOOL)value;
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
+ (BOOL)simpleNotifications;
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
+ (int)wordSelectionRegexRadius;
+ (BOOL)solidUnderlines;
+ (BOOL)useMultiPassUnderlineRenderer;
+ (NSString *)splitPaneColor;
+ (CGFloat)splitPaneDividerWidth;
+ (NSString *)paneTitleBarBackgroundColor;
+ (NSString *)paneTitleBarTextColor;
+ (NSString *)splitPaneSourceFillColor;
+ (NSString *)splitPaneSourceBorderColor;
+ (NSString *)splitPaneSourceInnerBorderColor;
+ (NSString *)splitPaneTargetDropFillColor;
+ (NSString *)splitPaneTargetDropBorderColor;
+ (NSString *)splitPaneTargetDropInnerBorderColor;
+ (BOOL)squareWindowCorners;
+ (NSString *)windowBorderColor;
+ (NSString *)windowBorderColorUnfocused;
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
+ (NSString *)sessionEndMessageText;
+ (NSString *)sessionEndMessageDividerCharacter;
+ (NSString *)sessionRestartedMessageText;
+ (NSString *)sessionFinishedMessageText;
+ (double)tabAutoShowHoldTime;
+ (NSString *)tabColorMenuOptions;
+ (double)tabFlashAnimationDuration;
+ (BOOL)tabsWrapAround;
+ (BOOL)tabTitlesUseSmartTruncation;
+ (BOOL)tabCloseButtonsAlwaysVisible;
+ (BOOL)threeFingerDragSendsMouseReports;
+ (BOOL)throttleMetalConcurrentFrames;
+ (BOOL)metalSynchronizedDrawing;
+ (BOOL)metalRowOutputCacheEnabled;
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
+ (BOOL)useSequoiaStyleTabs;
+ (BOOL)useShortcutAccessoryViewController;
+ (NSString *)URLCharacterSet;
+ (NSString *)URLCharacterSetExclusions;
+ (NSString *)urlHandlerCommand;
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
+ (NSString *)validCharactersInSSHUserNames;
+ (BOOL)vs16Supported;
+ (BOOL)vs16SupportedInPrimaryScreen;

+ (BOOL)warnAboutSecureKeyboardInputWithOpenCommand;
+ (void)setWarnAboutSecureKeyboardInputWithOpenCommand:(BOOL)value;
+ (double)webInstantReplayFrameRate;
+ (NSString *)webUserAgent;
+ (BOOL)workAroundMultiDisplayOSBug;
+ (BOOL)workAroundNumericKeypadBug;
+ (int)xtermVersion;
+ (CGFloat)verticalBarCursorWidth;
+ (NSString *)viewManPageCommand;
+ (BOOL)wrapFocus;
+ (BOOL)zeroWidthSpaceAdvancesCursor;
+ (BOOL)zippyTextDrawing;



@end
