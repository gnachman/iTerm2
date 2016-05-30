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

#define DEFINE_SETTABLE_BOOL(name, capitalizedName, theDefault, theDescription) \
DEFINE_BOOL(name, theDefault, theDescription) \
+ (void)set##capitalizedName :(BOOL)newValue { \
    [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@#capitalizedName]; \
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAdvancedSettingsDidChange \
                                                        object:nil]; \
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
DEFINE_FLOAT(tabAutoShowHoldTime, 1.0, @"Tabs: How long in seconds to show tabs in fullscreen.\nThe tab bar appears briefly in fullscreen when the number of tabs changes or you switch tabs. This setting gives the time in seconds for it to remain visible.");
DEFINE_BOOL(allowDragOfTabIntoNewWindow, YES, @"Tabs: Allow a tab to be dragged and dropped outside any existing tab bar to create a new window.");

#pragma mark Mouse
DEFINE_STRING(alternateMouseScrollStringForUp, @"",
              @"Mouse: Scroll wheel up sends the specified text when in alternate screen mode.\n"
              @"The value should use Vim syntax, such as \\e for escape.");
DEFINE_STRING(alternateMouseScrollStringForDown, @"",
              @"Mouse: Scroll wheel down sends the specified text when in alternate screen mode.\n"
              @"The value should use Vim syntax, such as \\e for escape.");
DEFINE_BOOL(alternateMouseScroll, NO, @"Mouse: Scroll wheel sends arrow keys when in alternate screen mode.");
DEFINE_BOOL(pinchToChangeFontSizeDisabled, NO, @"Mouse: Disable changing font size in response to a pinch gesture.");
DEFINE_BOOL(useSystemCursorWhenPossible, NO, @"Mouse: Use system cursor icons when possible.");
DEFINE_BOOL(alwaysAcceptFirstMouse, NO, @"Mouse: Always accept first mouse event on terminal windows.\nThis means clicks will work the same when iTerm2 is active as when it’s inactive.");
DEFINE_BOOL(doubleReportScrollWheel, NO, @"Mouse: Double-report scroll wheel events to work around tmux scrolling bug.");
DEFINE_BOOL(stealKeyFocus, NO, @"Mouse: When Focus Follows Mouse is enabled, steal key focus even when inactive.");
DEFINE_BOOL(cmdClickWhenInactiveInvokesSemanticHistory, NO, @"Mouse: ⌘-click in an active pane while iTerm2 isn't the active app invokes Semantic History.\nBy default, iTerm2 respects the OS standard that ⌘-click in an app that doesn't have keyboard focus behaves like a non-⌘ click that does not raise the window.");

#pragma mark Terminal
DEFINE_BOOL(traditionalVisualBell, NO, @"Terminal: Visual bell flashes the whole screen, not just a bell icon.");
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
DEFINE_BOOL(requireCmdForDraggingText, NO, @"Terminal: To drag images or selected text, you must hold ⌘. This prevents accidental drags.");
DEFINE_BOOL(focusReportingEnabled, YES, @"Terminal: Apps may turn on Focus Reporting.\nFocus reporting causes iTerm2 to send an escape sequence when a session gains or loses focus. It can cause problems when an ssh session dies unexpectedly because it gets left on, so some users prefer to disable it.");

#pragma mark Hotkey
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, @"Hotkey: Duration in seconds of the hotkey window animation.\nWarning: reducing this value may cause problems if you have multiple displays.");
DEFINE_BOOL(dockIconTogglesWindow, NO, @"Hotkey: If the only window is a hotkey window, then clicking the dock icon shows or hides it.");
DEFINE_BOOL(hotkeyWindowFloatsAboveOtherWindows, NO, @"Hotkey: The hotkey window floats above other windows even when another application is active.\nYou must disable “Prefs > Keys > Hotkey window hides when focus is lost” for this setting to be effective.");

#pragma mark General
DEFINE_STRING(searchCommand, @"https://google.com/search?q=%@", @"General: Template for URL of search engine.\niTerm2 replaces the string “%@” with the text to search for. Query parameter percent escaping is used.");
DEFINE_INT(autocompleteMaxOptions, 20, @"General: Number of autocomplete options to present.\nA value less than 100 is recommended.");
DEFINE_FLOAT(minRunningTime, 10, @"General: Grace period for automatic quitting after the last window is closed.\nIf iTerm2 is configured to quit automatically when the last window is closed, this setting gives a grace period (in seconds) after startup where that feature is disabled. Set to 0 to have no grace period.");
DEFINE_FLOAT(updateScreenParamsDelay, 1, @"General: Delay after changing number of screens/resolution until refresh (seconds).\nThis works around OS bugs where it takes some time after a screen change before it is safe to resize windows.");
DEFINE_BOOL(disableAppNap, NO, @"General: Disable App Nap.\nChange effective after restarting iTerm2.");
DEFINE_FLOAT(idleTimeSeconds, 2, @"General: Time in seconds before a session is considered idle.\nUsed for updating icons and activity indicator in tabs.");
DEFINE_FLOAT(findDelaySeconds, 1, @"General: Time to wait before performing Find action on 1- or 2- character queries.");
DEFINE_INT(maximumBytesToProvideToServices, 100000, @"General: Maximum number of bytes of selection to provide to Services.\nA large value here can cause performance issues when you have a big selection.");
DEFINE_BOOL(useOpenDirectory, YES, @"General: Use Open Directory to determine the user shell");
DEFINE_BOOL(hideFromDockAndAppSwitcher, NO, @"General: Hide iTerm2 from the dock and from the ⌘-Tab app switcher. This also hides the menu bar.\nYou must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(disablePotentiallyInsecureEscapeSequences, NO, @"General: Disable potentially insecure escape sequences.\nSome features of iTerm2 expand the surface area for security issues. Consider turning this on when viewing untrusted content. The following custom escape sequences will be disabled: RemoteHost, StealFocus, CurrentDir, SetProfile, CopyToClipboard, EndCopy, File, SetBackgroundImageFile. The following DEC sequences are disabled: DECRQCRA. The following xterm extensions are disabled: Window Title Reporting, Icon Title Reporting.");
DEFINE_BOOL(performDictionaryLookupOnQuickLook, YES, @"General: Perform dictionary lookups on force press.\nIf this is NO, force press will still preview the Semantic History action; only dictionary lookups can be disabled.");
DEFINE_BOOL(jiggleTTYSizeOnClearBuffer, NO, @"General: Redraw the screen after the Clear Buffer menu item is selected.\nWhen enabled, the TTY size is briefly changed after clearing the buffer to cause the shell or current app to redraw.");

#pragma mark - Semantic History
DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, @"Semantic History: Ignore hard newlines for the purposes of locating URLs for Semantic History.\nIf a hard newline occurs at the end of a line then cmd-click will not see it all unless this setting is turned on. This is useful for some interactive applications.");
// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'()|[]", @"Semantic History: Non-alphanumeric characters considered part of a URL for Semantic History.\nLetters and numbers are always considered part of the URL. These non-alphanumeric characters are used in addition for the purposes of figuring out where a URL begins and ends.");
DEFINE_INT(maxSemanticHistoryPrefixOrSuffix, 2000, @"Semantic History: Maximum number of bytes of text before and after click location to take into account.\nThis also limits the size of the \\3 and \\4 substitutions.");
DEFINE_STRING(pathsToIgnore, @"", @"Semantic History: Paths to ignore for Semantic History.\nSeparate paths with a comma. Any file under one of these paths will not be openable with Semantic History.");

#pragma mark - Debugging
DEFINE_BOOL(startDebugLoggingAutomatically, NO, @"Debugging: Start debug logging automatically when iTerm2 is launched.");
DEFINE_BOOL(logDrawingPerformance, NO, @"Debugging: Log stats about text drawing performance to console.\nUsed for performance testing.");

#pragma mark - Session
DEFINE_BOOL(runJobsInServers, YES, @"Session: Enable session restoration.\nSession restoration runs jobs in separate processes. They will survive crashes, force quits, and upgrades.\nYou must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(killJobsInServersOnQuit, YES, @"Session: User-initiated Quit (⌘Q) of iTerm2 will kill all running jobs.\nApplies only when session restoration is on.");
DEFINE_SETTABLE_BOOL(suppressRestartAnnouncement, SuppressRestartAnnouncement, NO, @"Session: Suppress the Restart Session offer.\nWhen a sessions terminates, it will offer to restart itself. Turn this on to suppress the offer permanently.");


#pragma mark - Window
DEFINE_BOOL(openFileInNewWindows, NO, @"Windows: Open files in new windows, not new tabs.\nThis affects shell scripts opened from Finder, for example.");
DEFINE_BOOL(rememberWindowPositions, YES, @"Windows: Remember window locations even after the windows are closed.\nWhen a new window is opened, one of the recorded locations is used.");
DEFINE_BOOL(disableWindowSizeSnap, NO, @"Windows: Terminal windows resize smoothly.\nDisables snapping to character grid. Holding Control will temporarily disable snap-to-grid.");
DEFINE_BOOL(profilesWindowJoinsActiveSpace, NO, @"Windows: If the Profiles window is open, it always moves to join the active Space.\nYou must restart iTerm2 for a change in this setting to take effect.");

#pragma mark tmux
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
DEFINE_BOOL(noSyncReplaceProfileWarning, NO, @"Warnings: Suppress warning about copying a session's settings over a Profile");

#pragma mark Pasteboard
DEFINE_BOOL(trimWhitespaceOnCopy, YES, @"Pasteboard: Trim whitespace when copying to pasteboard.");
DEFINE_INT(quickPasteBytesPerCall, 667, @"Pasteboard: Number of bytes to paste in each chunk when pasting normally.");
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01530456, @"Pasteboard: Delay in seconds between chunks when pasting normally.")
DEFINE_INT(slowPasteBytesPerCall, 16, @"Pasteboard: Number of bytes to paste in each chunk when pasting slowly.");
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, @"Pasteboard: Delay in seconds between chunks when pasting slowly");
DEFINE_BOOL(copyWithStylesByDefault, NO, @"Pasteboard: Copy to pasteboard on selection includes color and font style.");
DEFINE_INT(pasteHistoryMaxOptions, 20, @"Pasteboard: Number of entires to show in Paste History.\nThe value must be between 2 and 100.");
DEFINE_BOOL(disallowCopyEmptyString, NO, @"Pasteboard: Disallow copying empty string to pasteboard.\nIf enabled, selecting an empty string (or all whitespace if trimming is enabled) will not erase the contents of the pasteboard.");
DEFINE_BOOL(typingClearsSelection, YES, @"Pasteboard: Pressing a key will remove the selection.");

#pragma mark - Tip of the day

DEFINE_BOOL(noSyncTipsDisabled, NO, @"Tip of the Day: Disable the Tip of the Day?");

#pragma mark - Badge
DEFINE_STRING(badgeFont, @"Helvetica", @"Badge: Font to use for the badge.");
DEFINE_BOOL(badgeFontIsBold, YES, @"Badge: Should the badge render in bold type?");
DEFINE_FLOAT(badgeMaxWidthFraction, 0.5, @"Badge: Maximum width of the badge\nAs a fraction of the width of the terminal, between 0 and 1.0.");
DEFINE_FLOAT(badgeMaxHeightFraction, 0.2, @"Badge: Maximum height of the badge\nAs a fraction of the height of the terminal, between 0 and 1.0.");
DEFINE_INT(badgeRightMargin, 10, @"Badge: Right Margin\nHow much space to leave between the right edge of the badge and the right edge of the terminal.");
DEFINE_INT(badgeTopMargin, 10, @"Badge: Top Margin\nHow much space to leave between the top edge of the badge and the top edge of the terminal.");

#pragma mark - Experimental Features
DEFINE_BOOL(includePasteHistoryInAdvancedPaste, NO, @"Experimental Features: Include paste history in the advanced paste menu.");
DEFINE_BOOL(tolerateUnrecognizedTmuxCommands, YES, @"Experimental Features: Tolerate unrecognized commands from server.\nNormally, an unknown command from tmux will not end the session.");
DEFINE_BOOL(serializeOpeningMultipleFullScreenWindows, NO, @"Experimental Features: When opening multiple fullscreen windows, enter fullscreen one window at a time.");
DEFINE_BOOL(useAdaptiveFrameRate, NO, @"Experimental Features: Use adaptive framerate.\nWhen throughput is low, the screen will update at 60 frames per second. When throughput is higher, it will update at 30 frames per second.");
DEFINE_INT(adaptiveFrameRateThroughputThreshold, 10000, @"Experimental Features: Throughput threshold for adaptive frame rate.\nIf more than this many bytes per second are received, use the lower frame rate of 30 fps.");
DEFINE_BOOL(hotkeyWindowIgnoresSpotlight, NO, @"Experimental Features: Prevent Spotlight and Alfred from auto-closing the hotkey window.\nThis feature is experimental and may have unexpected side-effects.");
DEFINE_BOOL(tabTitlesUseSmartTruncation, NO, @"Experimental Features: Use “smart truncation” for tab titles.\nIf a tab‘s title is too long to fit, ellipsize the start of the title if more tabs have unique suffixes than prefixes in a given window.");
DEFINE_BOOL(experimentalKeyHandling, NO, @"Experimental Features: Improved support for input method editors like AquaSKK.");
DEFINE_BOOL(hideStuckTooltips, NO, @"Experimental Features: Hide stuck tooltips.\nWhen you hide iTerm2 using a hotkey while a tooltip is fading out it gets stuck because of an OS bug. Work around it with a nasty hack by enabling this feature.")

@end
