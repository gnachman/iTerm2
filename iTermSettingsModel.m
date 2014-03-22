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

DEFINE_BOOL(useUnevenTabs, NO, @"Uneven tab widths allowed")
DEFINE_INT(minTabWidth, 75, @"Minimum tab width")
DEFINE_INT(minCompactTabWidth, 60, @"Minimum tab width for tabs without close button or number")
DEFINE_INT(optimumTabWidth, 175, @"Preferred tab width")
DEFINE_BOOL(alternateMouseScroll, NO, @"Scroll wheel sends arrow keys in alternate screen mode")
DEFINE_BOOL(traditionalVisualBell, NO, @"Visual bell flashes the whole screen, not just a bell icon")
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, @"Duration in seconds of the hotkey window animation")
DEFINE_STRING(searchCommand, @"http://google.com/search?q=%@", @"Template for URL of search engine")
DEFINE_FLOAT(antiIdleTimerPeriod, 60, @"Anti-idle interval in seconds. Will not go faster than 60 seconds.")
DEFINE_BOOL(dockIconTogglesWindow, NO, @"If the only window is a hotkey window, then clicking the dock icon shows/hides it")
DEFINE_FLOAT(timeBetweenBlinks, 0.5, @"Time in seconds between cursor blinking on/off when a blinking cursor is enabled")
DEFINE_BOOL(neverWarnAboutMeta, NO, @"Suppress a warning when Option Key Acts as Meta is enabled");
DEFINE_BOOL(neverWarnAboutSpaces, NO, @"Suppress a warning about how to configure Spaces when setting a window's Space")
DEFINE_BOOL(neverWarnAboutOverrides, NO, @"Suppress a warning about a change to a Profile key setting that overrides a global setting")
DEFINE_BOOL(neverWarnAboutPossibleOverrides, NO, @"Suppress a warning about a change to a global key that's overridden by a Profile")
DEFINE_BOOL(trimWhitespaceOnCopy, YES, @"Trim whitespace when copying to pasteboard")
DEFINE_INT(autocompleteMaxOptions, 20, @"Number of autocomplete options to present (less than 100 recommended)")
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForUrl, NO, @"Suppress warning shown when a setting changed but prefs are loaded from a URL")
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForFile, NO, @"Suppress warning shown when a setting changed but prefs are loaded from a custom folder")
DEFINE_BOOL(openFileInNewWindows, NO, @"Open files (like shell scripts opened from Finder) in new windows, not new tabs")
DEFINE_FLOAT(minRunningTime, 10, @"Don't let iTerm2 quit automatically until it's been running for this many seconds (0 disables)")
DEFINE_FLOAT(updateScreenParamsDelay, 1, @"Wait this long after display settings change before updating windows")
DEFINE_INT(quickPasteBytesPerCall, 1024, @"Bytes to paste in each chunk when pasting normally")
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01, @"Delay in seconds between chunks when pasting normally")
DEFINE_INT(slowPasteBytesPerCall, 16, @"Bytes to paste in each chunk when pasting slowly")
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, @"Delay in seconds between chunks when pasting slowly")
DEFINE_INT(pasteHistoryMaxOptions, 20, @"Number of entires to show in Paste History (will not go below 2 or above 100)")
DEFINE_BOOL(pinchToChangeFontSizeDisabled, NO, @"Disable using a pinch gesture to change font size")
DEFINE_BOOL(doNotSetCtype, NO, @"Never set the CTYPE environment variable")
DEFINE_BOOL(debugKeyDown, NO, @"Log verbose debug info about key presses")
DEFINE_BOOL(growlOnForegroundTabs, NO, @"Enable Growl or Notification Center notifications for the foreground tab")
DEFINE_FLOAT(smartCursorColorBgThreshold, 0.5, @"Threshold for Smart Cursor Color for background color (0 to 1, larger values are more aggressive)")
DEFINE_FLOAT(smartCursorColorFgThreshold, 0.75, @"Threshold for Smart Cursor Color for text color (0 to 1, larger values are more aggressive)")
DEFINE_BOOL(logDrawingPerformance, NO, @"Log stats about text drawing performance to console")
DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, @"Ignore hard newlines for the purposes of locating URLs for Cmd-click")
DEFINE_BOOL(copyWithStylesByDefault, NO, @"Copy to pasteboard includes color and font style")

// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'()|[]", @"Non-alphanumeric characters considered part of a URL for Cmd-click")

@end
