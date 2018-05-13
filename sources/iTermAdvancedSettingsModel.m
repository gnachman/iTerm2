//
//  iTermAdvancedSettingsModel.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Foundation/Foundation.h>

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
} \
+ (NSString *)name##UserDefaultsKey { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return theIdentifier; \
}

#define DEFINE_SETTABLE_BOOL(name, capitalizedName, theDefault, theDescription) \
DEFINE_BOOL(name, theDefault, theDescription) \
+ (void)set##capitalizedName :(BOOL)newValue { \
    [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@#capitalizedName]; \
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAdvancedSettingsDidChange \
                                                        object:nil]; \
}

#define DEFINE_OPTIONAL_BOOL(name, theDefault, theDescription) \
+ (BOOL *)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController optionalBoolForIdentifier:theIdentifier \
                                                             defaultValue:theDefault \
                                                              description:theDescription]; \
} \
+ (NSString *)name##UserDefaultsKey { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return theIdentifier; \
}


#define DEFINE_INT(name, theDefault, theDescription) \
+ (int)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController intForIdentifier:theIdentifier \
                                                    defaultValue:theDefault \
                                                     description:theDescription]; \
}

#define DEFINE_BOUNDED_INT(name, theDefault, theDescription, minValue, maxValue) \
+ (int)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    int result = [iTermAdvancedSettingsViewController intForIdentifier:theIdentifier \
                                                          defaultValue:theDefault \
                                                           description:theDescription]; \
    return MIN(maxValue, MAX(minValue, result)); \
}

#define DEFINE_FLOAT(name, theDefault, theDescription) \
+ (double)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController floatForIdentifier:theIdentifier \
                                                      defaultValue:theDefault \
                                                           description:theDescription]; \
}

#define DEFINE_SETTABLE_FLOAT(name, capitalizedName, theDefault, theDescription) \
DEFINE_FLOAT(name, theDefault, theDescription) \
+ (void)set##capitalizedName :(double)newValue { \
    [[NSUserDefaults standardUserDefaults] setDouble:newValue forKey:@#capitalizedName]; \
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAdvancedSettingsDidChange \
                                                        object:nil]; \
}


#define DEFINE_STRING(name, theDefault, theDescription) \
+ (NSString *)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsViewController stringForIdentifier:theIdentifier \
                                                       defaultValue:theDefault \
                                                            description:theDescription]; \
}

// Convenience default value for boolean settings that are on for beta users.
#if BETA
#define YES_IF_BETA_ELSE_NO YES
#else
#define YES_IF_BETA_ELSE_NO NO
#endif


#pragma mark Tabs
DEFINE_BOOL(useUnevenTabs, NO, @"Tabs: Uneven tab widths allowed.");
DEFINE_INT(minTabWidth, 75, @"Tabs: Minimum tab width when using uneven tab widths.");
DEFINE_INT(minCompactTabWidth, 60, @"Tabs: Minimum tab width when using uneven tab widths for compact tabs.");
DEFINE_INT(optimumTabWidth, 175, @"Tabs: Preferred tab width when tabs are equally sized.");
DEFINE_BOOL(addNewTabAtEndOfTabs, YES, @"Tabs: Add new tabs at the end of the tab bar, not next to current tab.");
DEFINE_BOOL(navigatePanesInReadingOrder, YES, @"Tabs: Next Pane and Previous Pane commands use reading order, not the time of last use.");
DEFINE_BOOL(eliminateCloseButtons, NO, @"Tabs: Eliminate close buttons from tabs, even on mouse-over.");
DEFINE_FLOAT(tabAutoShowHoldTime, 1.0, @"Tabs: How long in seconds to show tabs in fullscreen.\nThe tab bar appears briefly in fullscreen when the number of tabs changes or you switch tabs. This setting gives the time in seconds for it to remain visible.");
DEFINE_FLOAT(tabFlashAnimationDuration, 0.25, @"Tabs: Animation duration for fade in/out animation of tabs in full screen, in seconds.")
DEFINE_BOOL(allowDragOfTabIntoNewWindow, YES, @"Tabs: Allow a tab to be dragged and dropped outside any existing tab bar to create a new window.");
DEFINE_INT(minimumTabDragDistance, 10, @"Tabs: How far must the mouse move before a tab drag is initiated?\nYou must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(tabTitlesUseSmartTruncation, YES, @"Tabs: Use “smart truncation” for tab titles.\nIf a tab‘s title is too long to fit, ellipsize the start of the title if more tabs have unique suffixes than prefixes in a given window.");
DEFINE_BOOL(middleClickClosesTab, YES, @"Tabs: Should middle-click on a tab in the tab bar close the tab?");

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
DEFINE_BOOL(aggressiveFocusFollowsMouse, NO, @"Mouse: When Focus Follows Mouse is enabled, activate the window under the cursor when iTerm2 becomes active?");
DEFINE_BOOL(cmdClickWhenInactiveInvokesSemanticHistory, NO, @"Mouse: ⌘-click in an active pane while iTerm2 isn't the active app invokes Semantic History.\nBy default, iTerm2 respects the OS standard that ⌘-click in an app that doesn't have keyboard focus behaves like a non-⌘ click that does not raise the window.");
DEFINE_BOOL(enableUnderlineSemanticHistoryOnCmdHover, YES, @"Mouse: Underline Semantic History-selectable items under the cursor while holding ⌘?");
DEFINE_BOOL(sensitiveScrollWheel, NO, @"Mouse: Scroll on any scroll wheel movement, no matter how small?");

#pragma mark Terminal
DEFINE_BOOL(traditionalVisualBell, NO, @"Terminal: Visual bell flashes the whole screen, not just a bell icon.");
DEFINE_FLOAT(timeBetweenBlinks, 0.5, @"Terminal: Cursor blink speed (seconds).");
DEFINE_BOOL(doNotSetCtype, NO, @"Terminal: Never set the CTYPE environment variable.");
// For these, 1 is more aggressive and 0 turns the feature off:
DEFINE_FLOAT(smartCursorColorBgThreshold, 0.5, @"Terminal: Threshold for Smart Cursor Color for background color (0 to 1).\n0 means the cursor’s background color will always be the cell’s text color, while 1 means it will always be black or white.");
DEFINE_FLOAT(smartCursorColorFgThreshold, 0.75, @"Terminal: Threshold for Smart Cursor Color for text color (0 to 1).\n0 means the cursor’s text color will always be the cell’s background color, while 1 means it will always be black or white.");
DEFINE_STRING(findUrlsRegex,
              @"https?://([a-z0-9A-Z]+(:[a-zA-Z0-9]+)?@)?[a-z0-9A-Z\\-]+(\\.[a-z0-9A-Z\\-]+)*"
              @"((:[0-9]+)?)(/[a-zA-Z0-9;:/\\.\\-_+%~?&amp;@=#\\(\\)]*)?",
              @"Terminal: Regular expression for “Find URLs” command.");
DEFINE_FLOAT(echoProbeDuration, 0.5, @"Terminal: Amount of time to wait while testing if echo is on (seconds).\nThis is used by the password manager to ensure you're at a password prompt.");
DEFINE_BOOL(disablePasswordManagerAnimations, NO, @"Terminal: Disable animations for showing/hiding password manager.");
DEFINE_BOOL(optionIsMetaForSpecialChars, YES, @"Terminal: When you press an arrow key or other function key that transmits the modifiers, should ⌥ be translated to Meta?\nIf this is set to No then it will be translated to Alt.");
DEFINE_BOOL(noSyncSilenceAnnoyingBellAutomatically, NO, @"Terminal: Automatically silence bell when it rings too much.");
DEFINE_BOOL(restoreWindowContents, YES, @"Terminal: Restore window contents at startup.\nThis requires “System Prefs>General>Close windows when quitting an app” to be off.");
DEFINE_INT(numberOfLinesForAccessibility, 1000, @"Terminal: Maximum number of lines of history to expose to Accessibility.\nAccessibility APIs can make iTerm2 slow. In order to limit the effect, you can restrict the number of lines in each session that are visible to accessibility. The last lines of each session will be made accessible.");
DEFINE_INT(triggerRadius, 3, @"Terminal: Number of screen lines to match against trigger regular expressions.\nTrigger regular expressions are matched against the last logical line of text when a newline is received. A search is performed to find the start of the line. Since very long lines would cause performance problems, the search (and consequently the regular expression match, highlighting, and so on) is limited to this many screen lines.");
DEFINE_BOOL(requireCmdForDraggingText, NO, @"Terminal: To drag images or selected text, you must hold ⌘. This prevents accidental drags.");
DEFINE_BOOL(focusReportingEnabled, YES, @"Terminal: Apps may turn on Focus Reporting.\nFocus reporting causes iTerm2 to send an escape sequence when a session gains or loses focus. It can cause problems when an ssh session dies unexpectedly because it gets left on, so some users prefer to disable it.");
DEFINE_BOOL(useColorfgbgFallback, YES, @"Terminal: Use fallback for COLORFGBG if no exact match found?\nThe COLORFGBG variable indicates the ANSI colors that match the foreground and background colors. If no colors match and this setting is enabled, then the variable will be set to 15;0 to indicate a dark background or 0;15 to indicate a light background.");
DEFINE_BOOL(zeroWidthSpaceAdvancesCursor, YES, @"Terminal: Zero-Width Space (U+200B) advances cursor?\nWhile a zero-width space should not advance the cursor per the Unicode spec, both Terminal.app and Konsole do this, and Weechat depends on it. You must restart iTerm2 after changing this setting.");
DEFINE_BOOL(fullHeightCursor, NO, @"Terminal: Cursor occupies line spacing area.\nIf lines have more than 100% vertical spacing and this setting is enabled the bottom of the cursor will be aligned to the bottom of the spacing area.");
DEFINE_FLOAT(underlineCursorOffset, 0, @"Terminal: Vertical offset for underline cursor.\nPositive values move it up, negative values move it down.");
DEFINE_BOOL(preventEscapeSequenceFromClearingHistory, NO, @"Terminal: Prevent CSI 3 J from clearing scrollback history?\nThis is also known as thethe terminfo E3 capability.");
DEFINE_FLOAT(verticalBarCursorWidth, 1, @"Terminal: Width of vertical bar cursor.");
DEFINE_BOOL(acceptOSC7, YES, @"Terminal: Accept OSC 7 to set username, hostname, and path.");
DEFINE_BOOL(detectPasswordInput, YES, @"Terminal: Show key at cursor at password prompt?");
DEFINE_BOOL(tabsWrapAround, NO, @"Terminal: Tabs wrap around to the next line.\nThis is useful for preserving tabs for later copying to the pasteboard. It breaks backward compatibility and may cause layout problems with programs that don’t expect this behavior.");
#pragma mark Hotkey
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, @"Hotkey: Duration in seconds of the hotkey window animation.\nWarning: reducing this value may cause problems if you have multiple displays.");
DEFINE_BOOL(dockIconTogglesWindow, NO, @"Hotkey: If the only window is a hotkey window, then clicking the dock icon shows or hides it.");
DEFINE_BOOL(hotkeyWindowFloatsAboveOtherWindows, NO, @"Hotkey: The hotkey window floats above other windows even when another application is active.\nYou must disable “Prefs > Keys > Hotkey window hides when focus is lost” for this setting to be effective.");
DEFINE_FLOAT(hotKeyDoubleTapMaxDelay, 0.3, @"Hotkey: The maximum amount of time allowed between presses of a modifier key when performing a modifier double-tap.");
DEFINE_FLOAT(hotKeyDoubleTapMinDelay, 0.01, @"Hotkey: The minimum amount of time required between presses of a modifier key when performing a modifier double-tap.");

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
DEFINE_BOOL(disablePotentiallyInsecureEscapeSequences, NO, @"General: Disable potentially insecure escape sequences.\nSome features of iTerm2 expand the surface area for security issues. Consider turning this on when viewing untrusted content. The following custom escape sequences will be disabled: RemoteHost, StealFocus, CurrentDir, SetProfile, CopyToClipboard, EndCopy, File, SetBackgroundImageFile. The following DEC sequences are disabled: DECRQCRA. The following xterm extensions are disabled: Window Title Reporting, Icon Title Reporting. This will break displaying inline images, file download, some shell integration features, and other features.");
DEFINE_BOOL(performDictionaryLookupOnQuickLook, YES, @"General: Perform dictionary lookups on force press.\nIf this is NO, force press will still preview the Semantic History action; only dictionary lookups can be disabled.");
DEFINE_BOOL(jiggleTTYSizeOnClearBuffer, NO, @"General: Redraw the screen after the Clear Buffer menu item is selected.\nWhen enabled, the TTY size is briefly changed after clearing the buffer to cause the shell or current app to redraw.");
DEFINE_BOOL(indicateBellsInDockBadgeLabel, YES, @"General: Indicate the number of bells rung while the app is inactive in the dock icon’s badge label");
DEFINE_STRING(downloadsDirectory, @"", @"General: Downloads folder.\nIf set, downloaded files go to this location instead of the user’s $HOME/Downloads folder.");
DEFINE_FLOAT(pointSizeOfTimeStamp, 10, @"General: Point size for timestamps");
DEFINE_BOUNDED_INT(terminalMargin, 5, @"General: Width of left and right margins in terminal panes\nHow much space to leave between the left and right edges of the terminal.\nYou must restart iTerm2 after modifying this property. Saved window arrangements should be re-created.", 1, 100);
DEFINE_INT(terminalVMargin, 2, @"General: Height of top and bottom margins in terminal panes\nHow much space to leave between the top and bottom edges of the terminal.\nYou must restart iTerm2 after modifying this property. Saved window arrangements should be re-created.");
DEFINE_BOOL(useVirtualKeyCodesForDetectingDigits, YES, @"General: On keyboards that require a modifier to press a digit, do not require that modifier for switching between windows, tabs, and panes by number.\nFor example, AZERTY requires you to hold down Shift to enter a number. To switch tabs with ⌘+Number on an AZERTY keyboard, you must enable this setting. Then, for example, ⌘-& switches to tab 1. When this setting is enabled, some user-defined shortcuts may become unavailable because the tab/window/pane switching behavior takes precedence.");
DEFINE_STRING(viewManPageCommand, @"man %@ || sleep 3", @"General: Command to view man pages.\nUsed when you press the man page button on the touch bar. %@ is replaced with the command. End the command with & to avoid opening an iTerm2 window (e.g., if you're launching an external viewer).");
DEFINE_BOOL(hideStuckTooltips, YES, @"General: Hide stuck tooltips.\nWhen you hide iTerm2 using a hotkey while a tooltip is fading out it gets stuck because of an OS bug. Work around it with a nasty hack by enabling this feature.")
DEFINE_BOOL(openFileOverridesSendText, YES, @"General: Should opening a script with iTerm2 disable the default profile's “Send Text at Start” setting?\nIf you use “open iTerm2 file.command” or drag a script onto iTerm2's icon and this setting is enabled then the script will be executed in lieu of the profile's “Send Text at Start” setting. If this setting is off then both will be executed.");
DEFINE_BOOL(statusBarIcon, YES, @"General: Add status bar icon when excluded from dock?\nWhen you turn on “Exclude from Dock and ⌘-Tab Application Switcher” a status bar icon is added to the menu bar so you can switch the setting back off. Disable this to remove the status bar icon. Doing so makes it very hard to get to Preferences. You must restart iTerm2 after changing this setting.");
DEFINE_BOOL(wrapFocus, YES, @"General: Should the directional focus hotkeys wrap");
DEFINE_BOOL(disableGrowl, YES_IF_BETA_ELSE_NO, @"General: Disable Growl notifications.\nSend notifications directly to Notification Center instead of relying on Growl to deliver them. Enables sound alerts on notifications.");
DEFINE_BOOL(openUntitledFile, YES, @"General: Open a new window when you click the dock icon and no windows are already open?");
DEFINE_BOOL(openNewWindowAtStartup, YES, @"General: Open a window at startup?\nThis is useful if you wish to use the system window restoration settings but not create a new window if none would be restored.");

#pragma mark - Drawing
DEFINE_BOOL(zippyTextDrawing, YES, @"Drawing: Use zippy text drawing algorithm?\nThis draws non-ASCII text more quickly but with lower fidelity. This setting is ignored if ligatures are enabled in Prefs > Profiles > Text.");
DEFINE_BOOL(lowFiCombiningMarks, NO, @"Drawing: Prefer speed to accuracy for characters with combining marks?");
DEFINE_BOOL(useAdaptiveFrameRate, YES, @"Drawing: Use adaptive framerate.\nWhen throughput is low, the screen will update at 60 frames per second. When throughput is higher, it will drop to a configurable rate (15 fps by default). Does not apply to Metal renderer.");
DEFINE_FLOAT(slowFrameRate, 15.0, @"Drawing: When adaptive framerate is enabled, refresh at this rate during high throughput conditions (FPS).");
DEFINE_FLOAT(activeUpdateCadence, 60.0, @"Drawing: Maximum frame rate (FPS) when adaptive framerate is disabled or GPU renderer is enabled.\nModifications to this setting will not affect existing sessions.");
DEFINE_INT(adaptiveFrameRateThroughputThreshold, 10000, @"Drawing: Throughput threshold for adaptive frame rate.\nIf more than this many bytes per second are received, use the lower frame rate of 30 fps.");
DEFINE_BOOL(dwcLineCache, YES, @"Drawing: Enable cache of double-width character locations?\nThis should improve performance. It is always on in nightly builds. You must restart iTerm2 for this setting to take effect.");
DEFINE_BOOL(useGCDUpdateTimer, YES, @"Drawing: Use GCD-based update timer instead of NSTimer.\nThis should cause more regular screen updates. Restart iTerm2 after changing this setting.");
DEFINE_BOOL(drawOutlineAroundCursor, NO, @"Drawing: Draw outline around underline and vertical bar cursors using background color.");
DEFINE_BOOL(disableCustomBoxDrawing, NO, @"Drawing: Use your typeface’s box-drawing characters instead of iTerm2’s custom drawing code.\nYou must restart iTerm2 after changing this setting.");

#warning Bring this back
//DEFINE_BOOL(useLowPowerGPUWhenUnplugged, NO, @"Drawing: Metal renderer uses integrated GPU when not connected to power?\nFor this to be effective you must disable “Disable Metal renderer when not connected to power”.");

#pragma mark - Semantic History
DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, @"Semantic History: Ignore hard newlines for the purposes of locating URLs and file names for Semantic History.\nIf a hard newline occurs at the end of a line then ⌘-click will not see it all unless this setting is turned on. This is useful for some interactive applications. Turning this on will remove newlines from the \\3 and \\4 substitutions.");
// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'(（)）|[]", @"Semantic History: Non-alphanumeric characters considered part of a URL for Semantic History.\nLetters and numbers are always considered part of the URL. These non-alphanumeric characters are used in addition for the purposes of figuring out where a URL begins and ends.");
DEFINE_INT(maxSemanticHistoryPrefixOrSuffix, 2000, @"Semantic History: Maximum number of bytes of text before and after click location to take into account.\nThis also limits the size of the \\3 and \\4 substitutions.");
DEFINE_STRING(pathsToIgnore, @"", @"Semantic History: Paths to ignore for Semantic History.\nSeparate paths with a comma. Any file under one of these paths will not be openable with Semantic History. It is wise to add network file systems to this list, since they can be very slow.");
DEFINE_BOOL(showYellowMarkForJobStoppedBySignal, YES, @"Semantic History: Use a yellow for a Shell Integration prompt mark when the job is stopped by a signal.");
DEFINE_BOOL(conservativeURLGuessing, NO, @"Semantic History: URLs must contain a scheme?\nEnable this to reduce the number of false positives that semantic history things are a URL");

#pragma mark - Debugging
DEFINE_BOOL(startDebugLoggingAutomatically, NO, @"Debugging: Start debug logging automatically when iTerm2 is launched.");
DEFINE_BOOL(appendToExistingDebugLog, NO, @"Debugging: Append to existing debug log rather than replacing it.");
DEFINE_BOOL(logDrawingPerformance, NO, @"Debugging: Log stats about text drawing performance to console.\nUsed for performance testing.");
DEFINE_BOOL(logRestorableStateSize, NO, @"Debugging: Log restorable state size info to /tmp/statesize.*.txt.");

#pragma mark - Session
DEFINE_BOOL(runJobsInServers, YES, @"Session: Enable session restoration.\nSession restoration runs jobs in separate processes. They will survive crashes, force quits, and upgrades.\nYou must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(killJobsInServersOnQuit, YES, @"Session: User-initiated Quit (⌘Q) of iTerm2 will kill all running jobs.\nApplies only when session restoration is on.");
DEFINE_SETTABLE_BOOL(suppressRestartAnnouncement, SuppressRestartAnnouncement, NO, @"Session: Suppress the Restart Session offer.\nWhen a session terminates, it will offer to restart itself. Turn this on to suppress the offer permanently.");
DEFINE_BOOL(showSessionRestoredBanner, YES, @"Session: When restoring a session without restoring a running job, draw a banner saying “Session Restored” below the restored contents.");
DEFINE_STRING(autoLogFormat,
              @"\\(session.creationTimeString).\\(session.name).\\(session.termid).\\(iterm2.pid).\\(session.autoLogId).log",
              @"Session: Format for automatic session log filenames.\nSee the Badges documentation for supported substitutions.");
DEFINE_BOOL(focusNewSplitPaneWithFocusFollowsMouse, YES, @"Session: When focus follows mouse is enabled, should new split panes automatically be focused?");
DEFINE_BOOL(NoSyncSuppressRestartSessionConfirmationAlert, NO, @"Session: Suppress restart session confirmation alert.\nDon't ask for a confirmation when manually restarting a session.");

#pragma mark - Window
DEFINE_BOOL(openFileInNewWindows, NO, @"Windows: Open files in new windows, not new tabs.\nThis affects shell scripts opened from Finder, for example.");
DEFINE_BOOL(rememberWindowPositions, YES, @"Windows: Remember window locations even after the windows are closed.\nWhen a new window is opened, one of the recorded locations is used.");
DEFINE_BOOL(disableWindowSizeSnap, NO, @"Windows: Terminal windows resize smoothly.\nDisables snapping to character grid. Holding Control will temporarily disable snap-to-grid.");
DEFINE_BOOL(profilesWindowJoinsActiveSpace, NO, @"Windows: If the Profiles window is open, it always moves to join the active Space.\nYou must restart iTerm2 for a change in this setting to take effect.");
DEFINE_BOOL(darkThemeHasBlackTitlebar, YES, @"Windows: Dark themes give terminal windows black title bars by default.");
DEFINE_BOOL(fontChangeAffectsBroadcastingSessions, NO, @"Windows: Should growing or shrinking the font in a session that's broadcasting input affect all session that broadcast input?\nThis only applies to changing the font size with Make Text Bigger, Make Text Normal Size, and Make Text Smaller");
DEFINE_BOOL(serializeOpeningMultipleFullScreenWindows, YES, @"Windows: When opening multiple fullscreen windows, enter fullscreen one window at a time.");
DEFINE_BOOL(trackingRunloopForLiveResize, YES, @"Windows: Use a tracking runloop for live resizing.\nThis allows the terminal to redraw during a resizing drag.");

#pragma mark tmux
DEFINE_BOOL(noSyncNewWindowOrTabFromTmuxOpensTmux, NO, @"Tmux Integration: Suppress alert asking what kind of tab/window to open in tmux integration.");
DEFINE_BOOL(tmuxUsesDedicatedProfile, YES, @"Tmux Integration: Tmux always uses the “tmux” profile.\nIf disabled, tmux sessions use the profile of the session you ran tmux -CC in.");
DEFINE_BOOL(tolerateUnrecognizedTmuxCommands, NO, @"Tmux Integration: Tolerate unrecognized commands from server.\nIf enabled, an unknown command from tmux (such as output from ssh or wall) will end the session. Turning this off helps detect dead ssh sessions.");

#pragma mark Warnings
DEFINE_BOOL(neverWarnAboutMeta, NO, @"Warnings: Suppress a warning when ⌥ Key Acts as Meta is enabled in Prefs>Profiles>Keys.");
DEFINE_BOOL(neverWarnAboutSpaces, NO, @"Warnings: Suppress a warning about how to configure Spaces when setting a window's Space.");
DEFINE_BOOL(neverWarnAboutOverrides, NO, @"Warnings: Suppress a warning about a change to a Profile key setting that overrides a global setting.");
DEFINE_BOOL(neverWarnAboutPossibleOverrides, NO, @"Warnings: Suppress a warning about a change to a global key that's overridden by a Profile.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForUrl, NO, @"Warnings: Suppress changed-setting warning when prefs are loaded from a URL.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForFile, NO, @"Warnings: Suppress changed-setting warning when prefs are loaded from a custom folder.");
DEFINE_BOOL(noSyncSuppressAnnyoingBellOffer, NO, @"Warnings: Suppress offer to silence bell when it rings too much.");

DEFINE_BOOL(suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline, NO, @"Warnings: Suppress warning about multi-line paste when pasting a single line ending with a newline.\nThis supresses all multi-line paste warnings when a single line is being pasted.");
DEFINE_BOOL(suppressMultilinePasteWarningWhenNotAtShellPrompt, NO, @"Warnings: Suppress warning about multi-line paste when not at prompt.\nRequires Shell Integration to be installed.");
DEFINE_BOOL(noSyncSuppressBroadcastInputWarning, NO, @"Warnings: Suppress warning about broadcasting input.");
DEFINE_BOOL(noSyncSuppressCaptureOutputRequiresShellIntegrationWarning, NO,
            @"Warnings: Suppress warning “Shell Integration is required for Capture Output.”");
DEFINE_BOOL(noSyncSuppressCaptureOutputToolNotVisibleWarning, NO,
            @"Warnings: Suppress warning that the Captured Output tool is not visible.");
DEFINE_BOOL(closingTmuxWindowKillsTmuxWindows, NO, @"Warnings: Suppress kill/hide dialog when closing a tmux window.");
DEFINE_BOOL(closingTmuxTabKillsTmuxWindows, NO, @"Warnings: Suppress kill/hide dialog when closing a tmux tab.");
DEFINE_BOOL(aboutToPasteTabsWithCancel, NO, @"Warnings: Suppress warning about pasting tabs with offer to convert them to spaces.");
DEFINE_FLOAT(shortLivedSessionDuration, 3, @"Warnings: Warn about short-lived sessions that live less than this many seconds.");

DEFINE_SETTABLE_BOOL(noSyncDoNotWarnBeforeMultilinePaste, NoSyncDoNotWarnBeforeMultilinePaste, NO, @"Warnings: Suppress warning about multi-line pastes (or a single line ending in a newline).\nThis applies whether you are at the shell prompt or not, provided two or more lines are being pasted.");
DEFINE_SETTABLE_BOOL(noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt, NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt, NO, @"Warnings: Suppress warning about pasting a single line ending in a newline when at the shell prompt.\nThis requires Shell Integration to be installed.");

DEFINE_BOOL(noSyncReplaceProfileWarning, NO, @"Warnings: Suppress warning about copying a session's settings over a Profile");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffFocusReportingOnHostChange, nil, @"Warnings: Always turn off focus reporting when host changes?");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffMouseReportingOnHostChange, nil, @"Warnings: Always turn off mouse reporting when host changes?");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffBracketedPasteOnHostChange, nil, @"Warnings: Always turn off paste bracketing when host changes?");

#pragma mark Pasteboard
DEFINE_BOOL(trimWhitespaceOnCopy, YES, @"Pasteboard: Trim whitespace when copying to pasteboard.");
DEFINE_INT(quickPasteBytesPerCall, 667, @"Pasteboard: Number of bytes to paste in each chunk when pasting normally.");
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01530456, @"Pasteboard: Delay in seconds between chunks when pasting normally.")
DEFINE_INT(slowPasteBytesPerCall, 16, @"Pasteboard: Number of bytes to paste in each chunk when pasting slowly.");
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, @"Pasteboard: Delay in seconds between chunks when pasting slowly");
DEFINE_BOOL(copyWithStylesByDefault, NO, @"Pasteboard: Copy to pasteboard on selection includes color and font style.");
DEFINE_INT(pasteHistoryMaxOptions, 20, @"Pasteboard: Number of entries to save in Paste History.\n.");
DEFINE_BOOL(disallowCopyEmptyString, NO, @"Pasteboard: Disallow copying empty string to pasteboard.\nIf enabled, selecting an empty string (or all whitespace if trimming is enabled) will not erase the contents of the pasteboard.");
DEFINE_BOOL(typingClearsSelection, YES, @"Pasteboard: Pressing a key will remove the selection.");
DEFINE_SETTABLE_BOOL(promptForPasteWhenNotAtPrompt, PromptForPasteWhenNotAtPrompt, NO, @"Pasteboard: Warn before pasting when not at shell prompt?");
DEFINE_SETTABLE_BOOL(noSyncSuppressClipboardAccessDeniedWarning, NoSyncSuppressClipboardAccessDeniedWarning, NO, @"Session: Suppress the notification that the terminal attempted to access the clipboard but it was denied?");
DEFINE_SETTABLE_BOOL(noSyncSuppressMissingProfileInArrangementWarning, NoSyncSuppressMissingProfileInArrangementWarning, NO, @"Session: Suppress the notification that a restored session’s profile no longer exists?");
DEFINE_BOOL(excludeBackgroundColorsFromCopiedStyle, NO, @"Pasteboard: Exclude background colors when text is copied with color and font style?");
DEFINE_BOOL(includePasteHistoryInAdvancedPaste, YES, @"Pasteboard: Include paste history in the advanced paste menu.");

#pragma mark - Tip of the day

DEFINE_BOOL(noSyncTipsDisabled, NO, @"Tip of the Day: Disable the Tip of the Day?");
DEFINE_SETTABLE_FLOAT(timeBetweenTips, TimeBetweenTips, 24 * 60 * 60, @"Tip of the Day: Time between tips (in seconds)");

#pragma mark - Badge
DEFINE_STRING(badgeFont, @"Helvetica", @"Badge: Font to use for the badge.");
DEFINE_BOOL(badgeFontIsBold, YES, @"Badge: Should the badge render in bold type?");
DEFINE_FLOAT(badgeMaxWidthFraction, 0.5, @"Badge: Maximum width of the badge\nAs a fraction of the width of the terminal, between 0 and 1.0.");
DEFINE_FLOAT(badgeMaxHeightFraction, 0.2, @"Badge: Maximum height of the badge\nAs a fraction of the height of the terminal, between 0 and 1.0.");
DEFINE_INT(badgeRightMargin, 10, @"Badge: Right Margin for the badge\nHow much space to leave between the right edge of the badge and the right edge of the terminal.");
DEFINE_INT(badgeTopMargin, 10, @"Badge: Top Margin for the badge\nHow much space to leave between the top edge of the badge and the top edge of the terminal.");

#pragma mark - Experimental Features

DEFINE_BOOL(enableAPIServer, NO, @"Experimental Features: Enable websocket API server.\nYou must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(killSessionsOnLogout, NO, @"Experimental Features: Kill sessions on logout.\nA possible fix for issue 4147.");

// This causes problems like issue 6052, where repeats cause the IME to swallow subsequent keypresses.
DEFINE_BOOL(experimentalKeyHandling, NO, @"General: Improved support for input method editors like AquaSKK.");

DEFINE_BOOL(useExperimentalFontMetrics, NO, @"Experimental Features: Use a more theoretically correct technique to measure line height.\nYou must restart iTerm2 or adjust a session's font size for this change to take effect.");
DEFINE_BOOL(supportREPCode, YES_IF_BETA_ELSE_NO, @"Experimental Features: Enable support for REP (Repeat previous character) escape sequence?");

DEFINE_BOOL(showBlockBoundaries, NO, @"Debugging: Show line buffer block boundaries (issue 6207)");
DEFINE_BOOL(showMetalFPSmeter, NO, @"Experimental Features: Show FPS meter\nRequires Metal renderer");
DEFINE_BOOL(disableMetalWhenUnplugged, YES, @"Experimental Features: Disable Metal renderer when not connected to power?\nThis helps to conserve energy.");

// TODO: Turn this back on by default in a few days. Let's see if it is responsible for the spike in nightly build crasehs starting with the 3-12-2018 build.
// The number of crashes fell off a cliff starting with the 3/18 build (usually 0, never more than 2/day, while it had been at 47 on the 3/15 build). I'm switching the default back to YES for the 4/18 build to see if the number climbs.
DEFINE_BOOL(disableMetalWhenIdle, NO, @"Experimental Features: Disable metal renderer when idle to save CPU utilization?\nRequires Metal renderer");

DEFINE_BOOL(proportionalScrollWheelReporting, YES_IF_BETA_ELSE_NO, @"Experimental Features: Report multiple mouse scroll events when scrolling quickly?");
DEFINE_BOOL(useModernScrollWheelAccumulator, NO, @"Experimental Features: Use modern scroll wheel accumulator.\nThis should support wheel mice better and feel more natural.");
DEFINE_BOOL(resetSGROnPrompt, YES_IF_BETA_ELSE_NO, @"Experimental Features: Reset colors at shell prompt?\nUses shell integration to detect a shell prompt and, if enabled, resets colors to their defaults.");
DEFINE_BOOL(retinaInlineImages, YES_IF_BETA_ELSE_NO, @"Experimental Features: Show inline images at Retina resolution.");

@end
