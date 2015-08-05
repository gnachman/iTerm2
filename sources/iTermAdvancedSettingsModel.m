//
//  iTermAdvancedSettingsModel.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermAdvancedSettingsModel.h"
#import "iTermAdvancedSettingsViewController.h"
#import "NSStringITerm.h"

@implementation iTermAdvancedSettingsModel

#define DEFINE_BOOL(name, theDefault, theDescription) \
+ (BOOL)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController boolForIdentifier:theIdentifier \
                                                     defaultValue:theDefault \
                                                      description:theDescription]; \
}

#define DEFINE_INT(name, theDefault, theDescription) \
+ (int)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController intForIdentifier:theIdentifier \
                                                    defaultValue:theDefault \
                                                     description:theDescription]; \
}

#define DEFINE_FLOAT(name, theDefault, theDescription) \
+ (double)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController floatForIdentifier:theIdentifier \
                                                      defaultValue:theDefault \
                                                           description:theDescription]; \
}

#define DEFINE_STRING(name, theDefault, theDescription) \
+ (NSString *)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController stringForIdentifier:theIdentifier \
                                                       defaultValue:theDefault \
                                                            description:theDescription]; \
}

#pragma mark Tabs
DEFINE_BOOL(useUnevenTabs, NO, @"Tabs: Uneven tab widths allowed.");
DEFINE_INT(minTabWidth, 75, @"Tabs: Minimum tab width when using uneven tab widths.");
DEFINE_INT(minCompactTabWidth, 60, @"Tabs: Minimum tab width when using uneven tab widths for compact tabs.");
DEFINE_INT(optimumTabWidth, 175, @"Tabs: Preferred tab width when tabs are equally sized.");
DEFINE_BOOL(addNewTabAtEndOfTabs, YES, @"Tabs: Add new tabs at the end of the tab bar, not next to current tab.");
DEFINE_BOOL(navigatePanesInReadingOrder, YES, @"Tabs: Next Pane and Previous Pane commands use reading order, not the time of last use.");
DEFINE_BOOL(eliminateCloseButtons, NO, @"Tabs: Eliminate close buttons from tabs, even on mouse-over.");

#pragma mark Mouse
DEFINE_BOOL(alternateMouseScroll, NO, @"Mouse: Scroll wheel sends arrow keys when in alternate screen mode.");
DEFINE_BOOL(pinchToChangeFontSizeDisabled, NO, @"Mouse: Disable changing font size in response to a pinch gesture.");
DEFINE_BOOL(useSystemCursorWhenPossible, NO, @"Mouse: Use system cursor icons when possible.");
DEFINE_BOOL(alwaysAcceptFirstMouse, NO, @"Mouse: Always accept first mouse event on terminal windows.\nThis means clicks will work the same when iTerm2 is active as when it’s inactive.");

#pragma mark Terminal
DEFINE_BOOL(traditionalVisualBell, NO, @"Terminal: Visual bell flashes the whole screen, not just a bell icon.");
DEFINE_FLOAT(antiIdleTimerPeriod, 60, @"Terminal: Anti-idle interval in seconds.\nWill not go faster than 60 seconds.");
DEFINE_FLOAT(timeBetweenBlinks, 0.5, @"Terminal: Cursor blink speed (seconds).");
DEFINE_BOOL(doNotSetCtype, NO, @"Terminal: Never set the CTYPE environment variable.");
// For these, 1 is more aggressive and 0 turns the feature off:
DEFINE_FLOAT(smartCursorColorBgThreshold, 0.5, @"Terminal: Threshold for Smart Cursor Color for background color (0 to 1).\n0 means the cursor’s background color will always be the cell’s text color, while 1 means it will always be black or white.");
DEFINE_FLOAT(smartCursorColorFgThreshold, 0.75, @"Terminal: Threshold for Smart Cursor Color for text color (0 to 1).\n0 means the cursor’s text color will always be the cell’s background color, while 1 means it will always be black or white.");
DEFINE_STRING(findUrlsRegex,
              @"https?://([a-z0-9A-Z]+(:[a-zA-Z0-9]+)?@)?[-a-z0-9A-Z\\-]+(\\.[-a-z0-9A-Z\\-]+)*"
              @"((:[0-9]+)?)(/[a-zA-Z0-9;:/\\.\\-_+%~?&amp;@=#\\(\\)]*)?",
              @"Terminal: Regular expression for “Find URLs” command.");
DEFINE_FLOAT(echoProbeDuration, 0.5, @"Terminal: Amount of time to wait while testing if echo is on (seconds).\nThis is used by the password manager to ensure you're at a password prompt.");
DEFINE_BOOL(optionIsMetaForSpecialChars, YES, @"Terminal: When you press an arrow key or other function key that transmits the modifiers, should Option be translated to Meta?\nIf this is set to No then it will be translated to Alt.");
DEFINE_BOOL(noSyncSilenceAnnoyingBellAutomatically, NO, @"Terminal: Automatically silence bell when it rings too much.");
DEFINE_BOOL(restoreWindowContents, YES, @"Terminal: Restore window contents at startup.\nThis requires “System Prefs>General>Close windows when quitting an app” to be off.");
DEFINE_INT(numberOfLinesForAccessibility, 1000, @"Terminal: Maximum number of lines of history to expose to Accessibility.\nAccessibility APIs can make iTerm2 slow. In order to limit the effect, you can restrict the number of lines in each session that are visible to accessibility. The last lines of each session will be made accessible.");
DEFINE_INT(triggerRadius, 3, @"Terminal: Number of screen lines to match against trigger regular expressions.\nTrigger regular expressions are matched against the last logical line of text when a newline is received. A search is performed to find the start of the line. Since very long lines would cause performance problems, the search (and consequently the regular expression match, highlighting, and so on) is limited to this many screen lines.");

#pragma mark Hotkey
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, @"Hotkey: Duration in seconds of the hotkey window animation.");
DEFINE_BOOL(dockIconTogglesWindow, NO, @"Hotkey: If the only window is a hotkey window, then clicking the dock icon shows or hides it.");

#pragma mark General
DEFINE_STRING(searchCommand, @"http://google.com/search?q=%@", @"General: Template for URL of search engine.\niTerm2 replaces the string “%@” with the text to search for. Query parameter percent escaping is used.");
DEFINE_INT(autocompleteMaxOptions, 20, @"General: Number of autocomplete options to present.\nA value less than 100 is recommended.");
DEFINE_FLOAT(minRunningTime, 10, @"General: Grace period for automatic quitting after the last window is closed.\nIf iTerm2 is configured to quit automatically when the last window is closed, this setting gives a grace period (in seconds) after startup where that feature is disabled. Set to 0 to have no grace period.");
DEFINE_FLOAT(updateScreenParamsDelay, 1, @"General: Delay after changing number of screens/resolution until refresh (seconds).\nThis works around OS bugs where it takes some time after a screen change before it is safe to resize windows.");
DEFINE_BOOL(disableAppNap, NO, @"General: Disable App Nap.\nChange effective after restarting iTerm2.");
DEFINE_FLOAT(idleTimeSeconds, 2, @"General: Time in seconds before a session is considered idle.\nUsed for updating icons and activity indicator in tabs.");
DEFINE_FLOAT(findDelaySeconds, 1, @"General: Time to wait before performing Find action on 1- or 2- character queries.");
DEFINE_INT(maximumBytesToProvideToServices, 100000, @"General: Maximum number of bytes of selection to provide to Services.\nA large value here can cause performance issues when you have a big selection.");
DEFINE_BOOL(useOpenDirectory, YES, @"General: Use Open Directory to determine the user shell");

#pragma mark - Semantic History
DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, @"Semantic History: Ignore hard newlines for the purposes of locating URLs for Semantic History.\nIf a hard newline occurs at the end of a line then cmd-click will not see it all unless this setting is turned on. This is useful for some interactive applications.");
// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'()|[]", @"Semantic History: Non-alphanumeric characters considered part of a URL for Semantic History.\nLetters and numbers are always considered part of the URL. These non-alphanumeric characters are used in addition for the purposes of figuring out where a URL begins and ends.");

#pragma mark - Debugging
DEFINE_BOOL(startDebugLoggingAutomatically, NO, @"Debugging: Start debug logging automatically when iTerm2 is launched.");
DEFINE_BOOL(logDrawingPerformance, NO, @"Debugging: Log stats about text drawing performance to console.\nUsed for performance testing.");

#pragma mark - Session Restoration
DEFINE_BOOL(runJobsInServers, YES, @"Session Restoration: Enable session restoration.\nSession restoration runs jobs in separate processes. They will survive crashes, force quits, and upgrades.\nYou must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(killJobsInServersOnQuit, YES, @"Session Restoration: User-initiated Quit (⌘Q) of iTerm2 will kill all running jobs.\nApplies only when session restoration is on.");

#pragma mark - Window
DEFINE_BOOL(openFileInNewWindows, NO, @"Windows: Open files in new windows, not new tabs.\nThis affects shell scripts opened from Finder, for example.");
DEFINE_BOOL(rememberWindowPositions, YES, @"Windows: Remember window locations even after the windows are closed.\nWhen a new window is opened, one of the recorded locations is used.");
DEFINE_BOOL(disableWindowSizeSnap, NO, @"Windows: Terminal windows resize smoothly.\nDisables snapping to character grid. Holding Control will temporarily disable snap-to-grid.");

#pragma mark tmux
DEFINE_BOOL(tolerateUnrecognizedTmuxCommands, YES, @"Tmux Integration: Tolerate unrecognized commands from server.\nNormally, an unknown command from tmux will end the session.");
DEFINE_BOOL(noSyncNewWindowOrTabFromTmuxOpensTmux, NO, @"Tmux Integration: Suppress alert asking what kind of tab/window to open in tmux integration.");

#pragma mark Warnings
DEFINE_BOOL(neverWarnAboutMeta, NO, @"Warnings: Suppress a warning when Option Key Acts as Meta is enabled in Prefs>Profiles>Keys.");
DEFINE_BOOL(neverWarnAboutSpaces, NO, @"Warnings: Suppress a warning about how to configure Spaces when setting a window's Space.");
DEFINE_BOOL(neverWarnAboutOverrides, NO, @"Warnings: Suppress a warning about a change to a Profile key setting that overrides a global setting.");
DEFINE_BOOL(neverWarnAboutPossibleOverrides, NO, @"Warnings: Suppress a warning about a change to a global key that's overridden by a Profile.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForUrl, NO, @"Warnings: Suppress changed-setting warning when prefs are loaded from a URL.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForFile, NO, @"Warnings: Suppress changed-setting warning when prefs are loaded from a custom folder.");
DEFINE_BOOL(noSyncSuppressAnnyoingBellOffer, NO, @"Warnings: Suppress offer to silence bell when it rings too much.");

DEFINE_BOOL(suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline, NO, @"Warnings: Suppress warning about multiline paste when pasting a single line ending with a newline.");
DEFINE_BOOL(suppressMultilinePasteWarningWhenNotAtShellPrompt, NO, @"Warnings: Suppress warning about multiline paste when not at prompt.\nRequires Shell Integration to be installed.");
DEFINE_BOOL(noSyncSuppressBroadcastInputWarning, NO, @"Warnings: Suppress warning about broadcasting input.");
DEFINE_BOOL(noSyncSuppressCaptureOutputRequiresShellIntegrationWarning, NO,
            @"Warnings: Suppress warning “Shell Integration is required for Capture Output.”");
DEFINE_BOOL(noSyncSuppressCaptureOutputToolNotVisibleWarning, NO,
            @"Warnings: Suppress warning that the Captured Output tool is not visible.");
DEFINE_BOOL(closingTmuxWindowKillsTmuxWindows, NO, @"Warnings: Suppress kill/hide dialog when closing a tmux window.");
DEFINE_BOOL(closingTmuxTabKillsTmuxWindows, NO, @"Warnings: Suppress kill/hide dialog when closing a tmux tab.");
DEFINE_BOOL(aboutToPasteTabs, NO, @"Warnings: Suppress warning about pasting tabs with offer to convert them to spaces.");
DEFINE_BOOL(noSyncDoNotWarnBeforeMultilinePaste, NO, @"Warnings: Suppress warning about pasting multiple lines (or a line ending in a newline).");

#pragma mark Pasteboard
DEFINE_BOOL(trimWhitespaceOnCopy, YES, @"Pasteboard: Trim whitespace when copying to pasteboard.");
DEFINE_INT(quickPasteBytesPerCall, 1024, @"Pasteboard: Number of bytes to paste in each chunk when pasting normally.");
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01, @"Pasteboard: Delay in seconds between chunks when pasting normally.")
DEFINE_INT(slowPasteBytesPerCall, 16, @"Pasteboard: Number of bytes to paste in each chunk when pasting slowly.");
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, @"Pasteboard: Delay in seconds between chunks when pasting slowly");
DEFINE_BOOL(copyWithStylesByDefault, NO, @"Pasteboard: Copy to pasteboard on selection includes color and font style.");
DEFINE_INT(pasteHistoryMaxOptions, 20, @"Pasteboard: Number of entires to show in Paste History.\nThe value must be between 2 and 100.");
DEFINE_BOOL(disallowCopyEmptyString, NO, @"Pasteboard: Disallow copying empty string to pasteboard.\nIf enabled, selecting an empty string (or all whitespace if trimming is enabled) will not erase the contents of the pasteboard.");

#pragma mark - Tip of the day

DEFINE_BOOL(noSyncTipsDisabled, NO, @"Tip of the Day: Disable the Tip of the Day?");

@end
