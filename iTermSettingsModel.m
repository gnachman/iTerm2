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
DEFINE_BOOL(neverWarnAboutOverrides, NO, @"Suppress a warning about a Profile key setting overriding a global setting")

@end
