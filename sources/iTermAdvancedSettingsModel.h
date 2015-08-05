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
+ (BOOL)traditionalVisualBell;
+ (double)hotkeyTermAnimationDuration;
+ (NSString *)searchCommand;
+ (double)antiIdleTimerPeriod;
+ (BOOL)dockIconTogglesWindow;
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
+ (BOOL)aboutToPasteTabs;

+ (BOOL)alwaysAcceptFirstMouse;

+ (BOOL)restoreWindowContents;
+ (BOOL)tolerateUnrecognizedTmuxCommands;

+ (int)maximumBytesToProvideToServices;

+ (BOOL)disableWindowSizeSnap;
+ (BOOL)eliminateCloseButtons;

+ (BOOL)runJobsInServers;
+ (BOOL)killJobsInServersOnQuit;

+ (BOOL)noSyncDoNotWarnBeforeMultilinePaste;

+ (BOOL)noSyncTipsDisabled;
+ (int)numberOfLinesForAccessibility;

+ (int)triggerRadius;
+ (BOOL)useOpenDirectory;
+ (BOOL)disallowCopyEmptyString;

@end
