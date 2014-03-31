//
//  iTermSettingsModel.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermSettingsModel.h"
#import "iTermAdvancedSettingsController.h"
#import "NSStringITerm.h"

@implementation iTermSettingsModel

#define DEFINE_BOOL(name, theDefault, theDescription) \
+ (BOOL)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsController boolForIdentifier:theIdentifier \
                                                 defaultValue:theDefault \
                                                  description:theDescription]; \
}

#define DEFINE_INT(name, theDefault, theDescription) \
+ (int)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsController intForIdentifier:theIdentifier \
                                                defaultValue:theDefault \
                                                 description:theDescription]; \
}

#define DEFINE_FLOAT(name, theDefault, theDescription) \
+ (double)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsController floatForIdentifier:theIdentifier \
                                                  defaultValue:theDefault \
                                                   description:theDescription]; \
}

#define DEFINE_STRING(name, theDefault, theDescription) \
+ (NSString *)name { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return [iTermAdvancedSettingsController stringForIdentifier:theIdentifier \
                                                   defaultValue:theDefault \
                                                    description:theDescription]; \
}

#pragma mark Tabs
DEFINE_BOOL(useUnevenTabs, NO, @"Tabs: Uneven tab widths allowed")
DEFINE_INT(minTabWidth, 75, @"Tabs: Minimum tab width")
DEFINE_INT(minCompactTabWidth, 60, @"Tabs: Minimum tab width for tabs without close button or number")
DEFINE_INT(optimumTabWidth, 175, @"Tabs: Preferred tab width")
DEFINE_BOOL(addNewTabAtEndOfTabs, YES, @"Tabs: New tabs are added at the end, not next to current tab")

#pragma mark Mouse
DEFINE_BOOL(alternateMouseScroll, NO, @"Mouse: Scroll wheel sends arrow keys in alternate screen mode")
DEFINE_BOOL(pinchToChangeFontSizeDisabled, NO, @"Mouse: Disable using a pinch gesture to change font size")

#pragma mark Terminal
DEFINE_BOOL(traditionalVisualBell, NO, @"Terminal: Visual bell flashes the whole screen, not just a bell icon")
DEFINE_FLOAT(antiIdleTimerPeriod, 60, @"Terminal: Anti-idle interval in seconds. Will not go faster than 60 seconds.")
DEFINE_FLOAT(timeBetweenBlinks, 0.5, @"Terminal: Cursor blink speed (seconds)")
DEFINE_BOOL(doNotSetCtype, NO, @"Terminal: Never set the CTYPE environment variable")
// For these, 1 is more aggressive and 0 turns the feature off:
DEFINE_FLOAT(smartCursorColorBgThreshold, 0.5, @"Terminal: Threshold for Smart Cursor Color for background color (0 to 1)")
DEFINE_FLOAT(smartCursorColorFgThreshold, 0.75, @"Terminal: Threshold for Smart Cursor Color for text color (0 to 1)")

#pragma mark Hotkey
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, @"Hotkey: Duration in seconds of the hotkey window animation")
DEFINE_BOOL(dockIconTogglesWindow, NO, @"Hotkey: If the only window is a hotkey window, then clicking the dock icon shows/hides it")

#pragma mark General
DEFINE_STRING(searchCommand, @"General: http://google.com/search?q=%@", @"Template for URL of search engine")
DEFINE_INT(autocompleteMaxOptions, 20, @"General: Number of autocomplete options to present (less than 100 recommended)")
DEFINE_BOOL(openFileInNewWindows, NO, @"General: Open files (like shell scripts opened from Finder) in new windows, not new tabs")
DEFINE_FLOAT(minRunningTime, 10, @"General: Automatic quit suspended for this manys seconds after startup (0 disables)")
DEFINE_FLOAT(updateScreenParamsDelay, 1, @"General: Delay after changing number of screens/resolution until refresh (seconds)")
DEFINE_INT(pasteHistoryMaxOptions, 20, @"General: Number of entires to show in Paste History (will not go below 2 or above 100)")
DEFINE_BOOL(debugKeyDown, NO, @"General: Log verbose debug info about key presses")
DEFINE_BOOL(logDrawingPerformance, NO, @"General: Log stats about text drawing performance to console")
DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, @"General: Ignore hard newlines for the purposes of locating URLs for Cmd-click")
// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'()|[]", @"General: Non-alphanumeric characters considered part of a URL for Cmd-click")
DEFINE_BOOL(rememberWindowPositions, YES, @"General: Remember window locations even after they’re closed");
DEFINE_BOOL(disableToolbar, NO, @"General: Completely disable toolbar");

#pragma mark Warnings
DEFINE_BOOL(neverWarnAboutMeta, NO, @"Warnings: Suppress a warning when Option Key Acts as Meta is enabled");
DEFINE_BOOL(neverWarnAboutSpaces, NO, @"Warnings: Suppress a warning about how to configure Spaces when setting a window's Space")
DEFINE_BOOL(neverWarnAboutOverrides, NO, @"Warnings: Suppress a warning about a change to a Profile key setting that overrides a global setting")
DEFINE_BOOL(neverWarnAboutPossibleOverrides, NO, @"Warnings: Suppress a warning about a change to a global key that's overridden by a Profile")
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForUrl, NO, @"Warnings: Suppress changed-setting warning when prefs are loaded from a URL")
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForFile, NO, @"Warnings: Suppress changed-setting warning when prefs are loaded from a custom folder")

#pragma mark Pasteboard
DEFINE_BOOL(trimWhitespaceOnCopy, YES, @"Pasteboard: Trim whitespace when copying to pasteboard")
DEFINE_INT(quickPasteBytesPerCall, 1024, @"Pasteboard: Bytes to paste in each chunk when pasting normally")
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01, @"Pasteboard: Delay in seconds between chunks when pasting normally")
DEFINE_INT(slowPasteBytesPerCall, 16, @"Pasteboard: Bytes to paste in each chunk when pasting slowly")
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, @"Pasteboard: Delay in seconds between chunks when pasting slowly")
DEFINE_BOOL(copyWithStylesByDefault, NO, @"Pasteboard: Copy to pasteboard includes color and font style")

@end
