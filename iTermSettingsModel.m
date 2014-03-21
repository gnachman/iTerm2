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

DEFINE_BOOL(useUnevenTabs, NO, @"Uneven tab widths allowed")
DEFINE_INT(minTabWidth, 75, @"Minimum tab width")
DEFINE_INT(minCompactTabWidth, 60, @"Minimum tab width for tabs without close button or number")
DEFINE_INT(optimumTabWidth, 175, @"Preferred tab width")
DEFINE_BOOL(alternateMouseScroll, NO, @"Scroll wheel sends arrow keys in alternate screen mode")
DEFINE_BOOL(traditionalVisualBell, NO, @"Visual bell flashes the whole screen, not just a bell icon")
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, @"Duration in seconds of the hotkey window animation")

@end
