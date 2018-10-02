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

#pragma mark - Accessors

+ (BOOL)aboutToPasteTabsWithCancel;
+ (BOOL)acceptOSC7;
+ (double)activeUpdateCadence;
+ (int)adaptiveFrameRateThroughputThreshold;
+ (BOOL)addNewTabAtEndOfTabs;
+ (BOOL)aggressiveFocusFollowsMouse;
+ (BOOL)allowDragOfTabIntoNewWindow;
+ (BOOL)alternateMouseScroll;
+ (NSString *)alternateMouseScrollStringForDown;
+ (NSString *)alternateMouseScrollStringForUp;
+ (BOOL)alwaysAcceptFirstMouse;
+ (BOOL)appendToExistingDebugLog;
+ (int)autocompleteMaxOptions;
+ (NSString *)autoLogFormat;
+ (NSString *)badgeFont;
+ (BOOL)badgeFontIsBold;
+ (double)badgeMaxHeightFraction;
+ (double)badgeMaxWidthFraction;
+ (int)badgeRightMargin;
+ (int)badgeTopMargin;
+ (BOOL)cmdClickWhenInactiveInvokesSemanticHistory;
+ (double)coloredSelectedTabOutlineStrength;
+ (double)coloredUnselectedTabTextProminence;
+ (BOOL)conservativeURLGuessing;
+ (BOOL)copyWithStylesByDefault;
+ (BOOL)darkThemeHasBlackTitlebar;
+ (BOOL)detectPasswordInput;
+ (BOOL)disableAdaptiveFrameRateInInteractiveApps;
+ (BOOL)disableAppNap;
+ (BOOL)disableCustomBoxDrawing;
+ (BOOL)disableMetalWhenIdle;
+ (BOOL)disablePasswordManagerAnimations;
+ (BOOL)disablePotentiallyInsecureEscapeSequences;
+ (BOOL)disableWindowSizeSnap;
+ (BOOL)disallowCopyEmptyString;
+ (BOOL)dockIconTogglesWindow DEPRECATED_ATTRIBUTE;
+ (BOOL)doNotSetCtype;
+ (BOOL)doubleReportScrollWheel;
+ (NSString *)downloadsDirectory;
+ (BOOL)drawOutlineAroundCursor;
+ (BOOL)dwcLineCache;
+ (double)echoProbeDuration;
+ (BOOL)eliminateCloseButtons;
+ (BOOL)enableAPIServer;
+ (BOOL)enableUnderlineSemanticHistoryOnCmdHover;
+ (BOOL)excludeBackgroundColorsFromCopiedStyle;
+ (BOOL)experimentalKeyHandling;
+ (NSString *)fallbackLCCType;
+ (double)findDelaySeconds;
// Regular expression for finding URLs for Edit>Find>Find URLs
+ (NSString *)findUrlsRegex;
+ (BOOL)focusNewSplitPaneWithFocusFollowsMouse;
+ (BOOL)focusReportingEnabled;
+ (BOOL)fontChangeAffectsBroadcastingSessions;
+ (double)fractionOfCharacterSelectingNextNeighbor;
+ (BOOL)fullHeightCursor;
+ (BOOL)hideStuckTooltips;
+ (double)hotKeyDoubleTapMaxDelay;
+ (double)hotKeyDoubleTapMinDelay;
+ (double)hotkeyTermAnimationDuration;
+ (BOOL)hotkeyWindowFloatsAboveOtherWindows DEPRECATED_ATTRIBUTE;
+ (double)idleTimeSeconds;
+ (BOOL)ignoreHardNewlinesInURLs;
+ (BOOL)includePasteHistoryInAdvancedPaste;
+ (BOOL)indicateBellsInDockBadgeLabel;
+ (BOOL)invalidateShadowAfterEachDraw;
+ (BOOL)jiggleTTYSizeOnClearBuffer;
+ (BOOL)killJobsInServersOnQuit;
+ (BOOL)killSessionsOnLogout;
+ (BOOL)logDrawingPerformance;
+ (BOOL)logRestorableStateSize;
+ (BOOL)lowFiCombiningMarks;
+ (int)maximumBytesToProvideToServices;
+ (int)maxSemanticHistoryPrefixOrSuffix;
+ (double)metalSlowFrameRate;
+ (BOOL)middleClickClosesTab;
+ (int)minCompactTabWidth;
+ (int)minimumTabDragDistance;
+ (int)minimumWeightDifferenceForBoldFont;
+ (double)minRunningTime;
+ (int)minTabWidth;
+ (BOOL)navigatePanesInReadingOrder;
+ (BOOL)neverWarnAboutMeta;
+ (BOOL)neverWarnAboutOverrides;
+ (BOOL)neverWarnAboutPossibleOverrides;
+ (BOOL)noSyncDoNotWarnBeforeMultilinePaste;
+ (NSString *)noSyncDoNotWarnBeforeMultilinePasteUserDefaultsKey;
+ (BOOL)noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt;
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
+ (BOOL)noSyncSuppressMissingProfileInArrangementWarning;
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
+ (BOOL)performDictionaryLookupOnQuickLook;
+ (BOOL)pinchToChangeFontSizeDisabled;
+ (double)pointSizeOfTimeStamp;
+ (BOOL)preventEscapeSequenceFromClearingHistory;
+ (BOOL)profilesWindowJoinsActiveSpace;
+ (BOOL)promptForPasteWhenNotAtPrompt;
+ (BOOL)proportionalScrollWheelReporting;
+ (int)quickPasteBytesPerCall;
+ (double)quickPasteDelayBetweenCalls;
// Remember window positions? If off, lets the OS pick the window position. Smart window placement takes precedence over this.
+ (BOOL)rememberWindowPositions;
+ (BOOL)requireCmdForDraggingText;
+ (BOOL)resetSGROnPrompt;
+ (BOOL)restoreWindowContents;
+ (BOOL)retinaInlineImages;
+ (BOOL)runJobsInServers;
+ (NSString *)searchCommand;
+ (BOOL)sensitiveScrollWheel;
+ (BOOL)serializeOpeningMultipleFullScreenWindows;
+ (void)setNoSyncDoNotWarnBeforeMultilinePaste:(BOOL)value;
+ (void)setNoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt:(BOOL)value;
+ (void)setNoSyncSuppressClipboardAccessDeniedWarning:(BOOL)value;
+ (void)setNoSyncSuppressMissingProfileInArrangementWarning:(BOOL)value;
+ (void)setPromptForPasteWhenNotAtPrompt:(BOOL)value;
+ (void)setSuppressRestartAnnouncement:(BOOL)value;
+ (void)setTimeBetweenTips:(double)time;
+ (double)shortLivedSessionDuration;
+ (BOOL)showBlockBoundaries;
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
+ (BOOL)startDebugLoggingAutomatically;
+ (BOOL)statusBarIcon;
+ (BOOL)stealKeyFocus;
+ (BOOL)supportREPCode;
+ (BOOL)suppressMultilinePasteWarningWhenNotAtShellPrompt;
+ (BOOL)suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline;
+ (BOOL)suppressRestartAnnouncement;
+ (double)tabAutoShowHoldTime;
+ (double)tabFlashAnimationDuration;
+ (BOOL)tabsWrapAround;
+ (BOOL)tabTitlesUseSmartTruncation;
+ (int)terminalMargin;
+ (int)terminalVMargin;
+ (BOOL)throttleMetalConcurrentFrames;
+ (double)timeBetweenBlinks;
+ (double)timeBetweenTips;
+ (double)timeToWaitForEmojiPanel;
+ (BOOL)tmuxUsesDedicatedProfile;
+ (BOOL)tolerateUnrecognizedTmuxCommands;
+ (BOOL)trackingRunloopForLiveResize;
+ (BOOL)traditionalVisualBell;
+ (int)triggerRadius;
+ (BOOL)trimWhitespaceOnCopy;
+ (BOOL)typingClearsSelection;
+ (double)underlineCursorOffset;
+ (double)updateScreenParamsDelay;
+ (NSString *)URLCharacterSet;
+ (BOOL)useAdaptiveFrameRate;
+ (BOOL)useColorfgbgFallback;
+ (BOOL)useExperimentalFontMetrics;
+ (BOOL)useGCDUpdateTimer;
+ (BOOL)useModernScrollWheelAccumulator;
+ (BOOL)useOpenDirectory;
+ (BOOL)useSystemCursorWhenPossible;
+ (BOOL)useUnevenTabs;
+ (CGFloat)verticalBarCursorWidth;
+ (NSString *)viewManPageCommand;
+ (BOOL)wrapFocus;
+ (BOOL)zeroWidthSpaceAdvancesCursor;
+ (BOOL)zippyTextDrawing;

@end
