 //
//  iTermAdvancedSettingsModel.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Foundation/Foundation.h>

@interface iTermAdvancedSettingsModel : NSObject

+ (BOOL)useUnevenTabs;
+ (int)minTabWidth;
+ (int)minCompactTabWidth;
+ (int)optimumTabWidth;
+ (BOOL)alternateMouseScroll;
+ (NSString *)alternateMouseScrollStringForUp;
+ (NSString *)alternateMouseScrollStringForDown;
+ (BOOL)traditionalVisualBell;
+ (double)hotkeyTermAnimationDuration;
+ (BOOL)hotkeyWindowFloatsAboveOtherWindows DEPRECATED_ATTRIBUTE;
+ (NSString *)searchCommand;
+ (BOOL)dockIconTogglesWindow DEPRECATED_ATTRIBUTE;
+ (double)timeBetweenBlinks;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)trimWhitespaceOnCopy;
+ (int)autocompleteMaxOptions;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForUrl;
+ (BOOL)noSyncNeverRemindPrefsChangesLostForFile;
+ (BOOL)openFileInNewWindows;
+ (double)minRunningTime;
+ (double)updateScreenParamsDelay;
+ (int)quickPasteBytesPerCall;
+ (double)quickPasteDelayBetweenCalls;
+ (int)slowPasteBytesPerCall;
+ (double)slowPasteDelayBetweenCalls;
+ (int)pasteHistoryMaxOptions;
+ (BOOL)pinchToChangeFontSizeDisabled;
+ (BOOL)doNotSetCtype;

// The cursor's background goes to the "most different" color from its neighbors if the difference
// in brightness between the proposed background color and the neighbors' background color is less
// than this threshold.
+ (double)smartCursorColorBgThreshold;
// The cursor's text is forced to black or white if it is too similar to the
// background. If the brightness difference is less than this value then the text color becomes
// black or white.
+ (double)smartCursorColorFgThreshold;

+ (BOOL)logDrawingPerformance;
+ (BOOL)ignoreHardNewlinesInURLs;
+ (BOOL)copyWithStylesByDefault;
+ (NSString *)URLCharacterSet;
+ (BOOL)addNewTabAtEndOfTabs;

// Remember window positions? If off, lets the OS pick the window position. Smart window placement takes precedence over this.
+ (BOOL)rememberWindowPositions;

// Regular expression for finding URLs for Edit>Find>Find URLs
+ (NSString *)findUrlsRegex;

+ (BOOL)suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline;
+ (BOOL)suppressMultilinePasteWarningWhenNotAtShellPrompt;
+ (BOOL)noSyncSuppressBroadcastInputWarning;

+ (BOOL)useSystemCursorWhenPossible;

+ (double)echoProbeDuration;

+ (BOOL)navigatePanesInReadingOrder;

+ (BOOL)noSyncSuppressCaptureOutputRequiresShellIntegrationWarning;
+ (BOOL)noSyncSuppressCaptureOutputToolNotVisibleWarning;
+ (BOOL)noSyncSuppressAnnyoingBellOffer;
+ (BOOL)noSyncSilenceAnnoyingBellAutomatically;

+ (BOOL)disableAppNap;
+ (double)idleTimeSeconds;

+ (double)findDelaySeconds;
+ (BOOL)optionIsMetaForSpecialChars;

+ (BOOL)startDebugLoggingAutomatically;
+ (BOOL)aboutToPasteTabsWithCancel;

+ (BOOL)alwaysAcceptFirstMouse;

+ (BOOL)restoreWindowContents;
+ (BOOL)tolerateUnrecognizedTmuxCommands;

+ (int)maximumBytesToProvideToServices;

+ (BOOL)disableWindowSizeSnap;
+ (BOOL)eliminateCloseButtons;

+ (BOOL)runJobsInServers;
+ (BOOL)killJobsInServersOnQuit;

+ (BOOL)noSyncDoNotWarnBeforeMultilinePaste;
+ (NSString *)noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey;
+ (void)setNoSyncDoNotWarnBeforeMultilinePaste:(BOOL)value;
+ (BOOL)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt;
+ (NSString *)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPromptUserDefaultsKey;
+ (void)setNoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt:(BOOL)value;

+ (BOOL)noSyncTipsDisabled;
+ (int)numberOfLinesForAccessibility;

+ (int)triggerRadius;
+ (BOOL)useOpenDirectory;
+ (BOOL)disallowCopyEmptyString;
+ (BOOL)profilesWindowJoinsActiveSpace;

+ (NSString *)badgeFont;
+ (BOOL)badgeFontIsBold;
+ (double)badgeMaxWidthFraction;
+ (double)badgeMaxHeightFraction;
+ (int)badgeRightMargin;
+ (int)badgeTopMargin;
+ (BOOL)noSyncReplaceProfileWarning;
+ (BOOL)requireCmdForDraggingText;
+ (double)tabAutoShowHoldTime;
+ (BOOL)doubleReportScrollWheel;
+ (BOOL)stealKeyFocus;
+ (BOOL)allowDragOfTabIntoNewWindow;
+ (BOOL)typingClearsSelection;
+ (BOOL)focusReportingEnabled;

+ (BOOL)tabTitlesUseSmartTruncation;
+ (BOOL)serializeOpeningMultipleFullScreenWindows;
+ (BOOL)disablePotentiallyInsecureEscapeSequences;
+ (int)maxSemanticHistoryPrefixOrSuffix;
+ (BOOL)performDictionaryLookupOnQuickLook;
+ (NSString *)pathsToIgnore;
+ (BOOL)jiggleTTYSizeOnClearBuffer;
+ (BOOL)cmdClickWhenInactiveInvokesSemanticHistory;
+ (BOOL)suppressRestartAnnouncement;
+ (BOOL)showSessionRestoredBanner;
+ (void)setSuppressRestartAnnouncement:(BOOL)value;
+ (BOOL)useAdaptiveFrameRate;
+ (int)adaptiveFrameRateThroughputThreshold;
+ (BOOL)includePasteHistoryInAdvancedPaste;
+ (BOOL)experimentalKeyHandling;
+ (double)hotKeyDoubleTapMaxDelay;
+ (double)hotKeyDoubleTapMinDelay;
+ (BOOL)hideStuckTooltips;
+ (BOOL)indicateBellsInDockBadgeLabel;
+ (double)tabFlashAnimationDuration;
+ (NSString *)downloadsDirectory;
+ (double)pointSizeOfTimeStamp;
+ (BOOL)showYellowMarkForJobStoppedBySignal;
+ (double)slowFrameRate;
+ (double)timeBetweenTips;
+ (void)setTimeBetweenTips:(double)time;
+ (BOOL)openFileOverridesSendText;
+ (BOOL)useLayers;
+ (int)terminalMargin;
+ (int)terminalVMargin;
+ (BOOL)useColorfgbgFallback;
+ (BOOL)promptForPasteWhenNotAtPrompt;
+ (void)setPromptForPasteWhenNotAtPrompt:(BOOL)value;
+ (BOOL)zeroWidthSpaceAdvancesCursor;
+ (BOOL)darkThemeHasBlackTitlebar;
+ (BOOL)fontChangeAffectsBroadcastingSessions;
+ (BOOL)zippyTextDrawing;
+ (BOOL)noSyncSuppressClipboardAccessDeniedWarning;
+ (void)setNoSyncSuppressClipboardAccessDeniedWarning:(BOOL)value;
+ (BOOL)noSyncSuppressMissingProfileInArrangementWarning;
+ (void)setNoSyncSuppressMissingProfileInArrangementWarning:(BOOL)value;
+ (BOOL)acceptOSC7;
+ (BOOL)trackingRunloopForLiveResize;
+ (BOOL)enableAPIServer;
+ (double)shortLivedSessionDuration;
+ (int)minimumTabDragDistance;
+ (BOOL)useVirtualKeyCodesForDetectingDigits;
+ (BOOL)excludeBackgroundColorsFromCopiedStyle;
+ (BOOL)useGCDUpdateTimer;
+ (BOOL)fullHeightCursor;
+ (BOOL)drawOutlineAroundCursor;
+ (double)underlineCursorOffset;
+ (BOOL)logRestorableStateSize;
+ (NSString *)autoLogFormat;
+ (BOOL)killSessionsOnLogout;
+ (BOOL)tmuxUsesDedicatedProfile;
+ (BOOL)detectPasswordInput;
+ (BOOL)disablePasswordManagerAnimations;
+ (BOOL)focusNewSplitPaneWithFocusFollowsMouse;
+ (BOOL)suppressRestartSessionConfirmationAlert;
+ (NSString *)viewManPageCommand;
+ (BOOL)preventEscapeSequenceFromClearingHistory;
+ (BOOL)dwcLineCache;
+ (BOOL)lowFiCombiningMarks;
+ (CGFloat)verticalBarCursorWidth;
+ (BOOL)statusBarIcon;
+ (BOOL)sensitiveScrollWheel;
+ (BOOL)disableCustomBoxDrawing;
+ (BOOL)useExperimentalFontMetrics;
+ (BOOL)supportREPCode;
+ (BOOL)showBlockBoundaries;

@end
