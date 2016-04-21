//
//  iTermProfilePreferences.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermProfilePreferences.h"
#import "ITAddressBookMgr.h"
#import "iTermCursor.h"
#import "NSColor+iTerm.h"
#import "PreferencePanel.h"

#define PROFILE_BLOCK(x) [[^id(Profile *profile) { return [self x:profile]; } copy] autorelease]

NSString *const kProfilePreferenceCommandTypeCustomValue = @"Yes";
NSString *const kProfilePreferenceCommandTypeLoginShellValue = @"No";

NSString *const kProfilePreferenceInitialDirectoryCustomValue = @"Yes";
NSString *const kProfilePreferenceInitialDirectoryHomeValue = @"No";
NSString *const kProfilePreferenceInitialDirectoryRecycleValue = @"Recycle";
NSString *const kProfilePreferenceInitialDirectoryAdvancedValue = @"Advanced";

@implementation iTermProfilePreferences

#pragma mark - APIs

+ (BOOL)boolForKey:(NSString *)key inProfile:(Profile *)profile {
    return [[self objectForKey:key inProfile:profile] boolValue];
}

+ (void)setBool:(BOOL)value
         forKey:(NSString *)key
      inProfile:(Profile *)profile
          model:(ProfileModel *)model {
    [self setObject:@(value) forKey:key inProfile:profile model:model];
}

+ (int)intForKey:(NSString *)key inProfile:(Profile *)profile {
    return [[self objectForKey:key inProfile:profile] intValue];
}

+ (void)setInt:(int)value
        forKey:(NSString *)key
     inProfile:(Profile *)profile
         model:(ProfileModel *)model {
    [self setObject:@(value) forKey:key inProfile:profile model:model];
}

+ (NSUInteger)unsignedIntegerForKey:(NSString *)key inProfile:(Profile *)profile {
    return [[self objectForKey:key inProfile:profile] unsignedIntegerValue];
}

+ (void)setUnsignedInteger:(NSUInteger)value
        forKey:(NSString *)key
     inProfile:(Profile *)profile
         model:(ProfileModel *)model {
    [self setObject:@(value) forKey:key inProfile:profile model:model];
}

+ (double)floatForKey:(NSString *)key inProfile:(Profile *)profile {
    return [[self objectForKey:key inProfile:profile] doubleValue];
}

+ (void)setFloat:(double)value
          forKey:(NSString *)key
       inProfile:(Profile *)profile
           model:(ProfileModel *)model {
    [self setObject:@(value) forKey:key inProfile:profile model:model];
}

+ (double)doubleForKey:(NSString *)key inProfile:(Profile *)profile {
    return [[self objectForKey:key inProfile:profile] doubleValue];
}

+ (void)setDouble:(double)value
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model {
    [self setObject:@(value) forKey:key inProfile:profile model:model];
}

+ (NSString *)stringForKey:(NSString *)key inProfile:(Profile *)profile {
    return [self objectForKey:key inProfile:profile];
}

+ (void)setString:(NSString *)value
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model {
    [self setObject:value forKey:key inProfile:profile model:model];
}

// This is used for ensuring that all controls have default values.
+ (BOOL)keyHasDefaultValue:(NSString *)key {
    return ([self defaultValueMap][key] != nil);
}

+ (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type {
    id defaultValue = [self defaultValueMap][key];
    switch (type) {
        case kPreferenceInfoTypeIntegerTextField:
        case kPreferenceInfoTypeDoubleTextField:
        case kPreferenceInfoTypePopup:
            return ([defaultValue isKindOfClass:[NSNumber class]] &&
                    [defaultValue doubleValue] == ceil([defaultValue doubleValue]));
        case kPreferenceInfoTypeUnsignedIntegerTextField:
        case kPreferenceInfoTypeUnsignedIntegerPopup:
            return ([defaultValue isKindOfClass:[NSNumber class]]);
        case kPreferenceInfoTypeCheckbox:
        case kPreferenceInfoTypeInvertedCheckbox:
            return ([defaultValue isKindOfClass:[NSNumber class]] &&
                    ([defaultValue intValue] == YES ||
                     [defaultValue intValue] == NO));
        case kPreferenceInfoTypeSlider:
            return [defaultValue isKindOfClass:[NSNumber class]];
        case kPreferenceInfoTypeStringTextField:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeTokenField:
            return ([defaultValue isKindOfClass:[NSNull class]] ||
                    [defaultValue isKindOfClass:[NSArray class]]);
        case kPreferenceInfoTypeMatrix:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeColorWell:
            return ([defaultValue isKindOfClass:[NSNull class]] ||
                    [defaultValue isKindOfClass:[NSDictionary class]]);
    }

    return NO;
}

#pragma mark - Private

+ (NSDictionary *)defaultValueMap {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ KEY_NAME: @"Default",
                  KEY_SHORTCUT: [NSNull null],
                  KEY_TAGS: [NSNull null],
                  KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeLoginShellValue,
                  KEY_COMMAND_LINE: @"",
                  KEY_INITIAL_TEXT: @"",
                  KEY_CUSTOM_DIRECTORY: kProfilePreferenceInitialDirectoryHomeValue,
                  KEY_WORKING_DIRECTORY: @"",
                  KEY_BADGE_FORMAT: @"",
                  // Note: these defaults aren't used, except for link color and cursor guide color, because they are always specified.
                  KEY_FOREGROUND_COLOR:    [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_BACKGROUND_COLOR:    [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_BOLD_COLOR:          [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_LINK_COLOR:          [[NSColor colorWithCalibratedRed:0.023 green:0.270 blue:0.678 alpha:1] dictionaryValue],
                  KEY_SELECTION_COLOR:     [[NSColor colorWithCalibratedRed:0.709 green:0.835 blue:1.000 alpha:1] dictionaryValue],
                  KEY_SELECTED_TEXT_COLOR: [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_CURSOR_COLOR:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_CURSOR_TEXT_COLOR:   [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_0_COLOR:        [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_1_COLOR:        [[NSColor colorWithCalibratedRed:0.733 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_2_COLOR:        [[NSColor colorWithCalibratedRed:0.000 green:0.733 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_3_COLOR:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_4_COLOR:        [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_5_COLOR:        [[NSColor colorWithCalibratedRed:0.733 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_6_COLOR:        [[NSColor colorWithCalibratedRed:0.000 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_7_COLOR:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_8_COLOR:        [[NSColor colorWithCalibratedRed:0.333 green:0.333 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_9_COLOR:        [[NSColor colorWithCalibratedRed:1.000 green:0.333 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_10_COLOR:       [[NSColor colorWithCalibratedRed:0.333 green:1.000 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_11_COLOR:       [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_12_COLOR:       [[NSColor colorWithCalibratedRed:0.333 green:0.333 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_13_COLOR:       [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_14_COLOR:       [[NSColor colorWithCalibratedRed:0.333 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_15_COLOR:       [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_CURSOR_GUIDE_COLOR:  [[NSColor colorWithCalibratedRed:0.650 green:0.910 blue:1.000 alpha:0.25] dictionaryValue],
                  KEY_BADGE_COLOR:         [[NSColor colorWithCalibratedRed:1.0 green:0.000 blue:0.000 alpha:0.5] dictionaryValue],
                  KEY_USE_CURSOR_GUIDE: @NO,
                  KEY_TAB_COLOR: [NSNull null],
                  KEY_USE_TAB_COLOR: @NO,
                  KEY_SMART_CURSOR_COLOR: @NO,
                  KEY_MINIMUM_CONTRAST: @0.0,
                  KEY_CURSOR_BOOST: @0.0,
                  KEY_CURSOR_TYPE: @(CURSOR_BOX),
                  KEY_BLINKING_CURSOR: @NO,
                  KEY_USE_BOLD_FONT: @YES,
                  KEY_THIN_STROKES: @(iTermThinStrokesSettingRetinaOnly),
                  KEY_USE_BRIGHT_BOLD: @YES,
                  KEY_BLINK_ALLOWED: @NO,
                  KEY_USE_ITALIC_FONT: @YES,
                  KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO,
                  KEY_USE_HFS_PLUS_MAPPING: @NO,
                  KEY_HORIZONTAL_SPACING: @1.0,
                  KEY_VERTICAL_SPACING: @1.0,
                  KEY_USE_NONASCII_FONT: @YES,
                  KEY_TRANSPARENCY: @0.0,
                  KEY_BLUR: @NO,
                  KEY_BLUR_RADIUS: @2.0,
                  KEY_BACKGROUND_IMAGE_TILED: @NO,
                  KEY_BLEND: @0.5,
                  KEY_COLUMNS: @80,
                  KEY_ROWS: @25,
                  KEY_HIDE_AFTER_OPENING: @NO,
                  KEY_WINDOW_TYPE: @(WINDOW_TYPE_NORMAL),
                  KEY_SCREEN: @-1,
                  KEY_SPACE: @0,
                  KEY_SYNC_TITLE: @NO,
                  KEY_DISABLE_WINDOW_RESIZING: @NO,
                  KEY_PREVENT_TAB: @NO,
                  KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR: @NO,
                  KEY_OPEN_TOOLBELT: @NO,
                  KEY_ASCII_ANTI_ALIASED: @NO,
                  KEY_NONASCII_ANTI_ALIASED: @NO,
                  KEY_SCROLLBACK_LINES: @1000,
                  KEY_UNLIMITED_SCROLLBACK: @NO,
                  KEY_SCROLLBACK_WITH_STATUS_BAR: @NO,
                  KEY_SCROLLBACK_IN_ALTERNATE_SCREEN: @YES,
                  KEY_CHARACTER_ENCODING: @(NSUTF8StringEncoding),
                  KEY_TERMINAL_TYPE: @"xterm",
                  KEY_ANSWERBACK_STRING: @"",
                  KEY_XTERM_MOUSE_REPORTING: @NO,
                  KEY_ALLOW_TITLE_REPORTING: @NO,
                  KEY_ALLOW_TITLE_SETTING: @YES,
                  KEY_DISABLE_PRINTING: @NO,
                  KEY_DISABLE_SMCUP_RMCUP: @NO,
                  KEY_SILENCE_BELL: @NO,
                  KEY_BOOKMARK_GROWL_NOTIFICATIONS: @NO,
                  KEY_SEND_BELL_ALERT: @YES,
                  KEY_SEND_IDLE_ALERT: @NO,
                  KEY_SEND_NEW_OUTPUT_ALERT: @NO,
                  KEY_SEND_SESSION_ENDED_ALERT: @YES,
                  KEY_SEND_TERMINAL_GENERATED_ALERT: @YES,
                  KEY_FLASHING_BELL: @NO,
                  KEY_VISUAL_BELL: @NO,
                  KEY_SET_LOCALE_VARS: @YES,
                  KEY_CLOSE_SESSIONS_ON_END: @NO,
                  KEY_PROMPT_CLOSE: @(PROMPT_NEVER),
                  KEY_UNDO_TIMEOUT: @(5),
                  KEY_JOBS: @[],
                  KEY_REDUCE_FLICKER: @NO,
                  KEY_AUTOLOG: @NO,
                  KEY_LOGDIR: @"",
                  KEY_SEND_CODE_WHEN_IDLE: @NO,
                  KEY_IDLE_CODE: @0,
                  KEY_IDLE_PERIOD: @60,
                  KEY_OPTION_KEY_SENDS: @(OPT_NORMAL),
                  KEY_RIGHT_OPTION_KEY_SENDS: @(OPT_NORMAL),
                  KEY_APPLICATION_KEYPAD_ALLOWED: @NO,
                  KEY_PLACE_PROMPT_AT_FIRST_COLUMN: @YES,
                  KEY_SHOW_MARK_INDICATORS: @YES,
                };
        [dict retain];
    }
    return dict;
}

+ (id)objectForKey:(NSString *)key inProfile:(Profile *)profile {
    id object = [self computedObjectForKey:key inProfile:profile];
    if (!object) {
        object = [self uncomputedObjectForKey:key inProfile:profile];
    }
    return object;
}

+ (void)setObject:(id)object
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model {
    [model setObject:object forKey:key inBookmark:profile];
    [model flush];
    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                        object:nil
                                                      userInfo:nil];
}

+ (id)defaultObjectForKey:(NSString *)key {
    id obj = [self defaultValueMap][key];
    if ([obj isKindOfClass:[NSNull class]]) {
        return nil;
    } else {
        return obj;
    }
}

#pragma mark - Computed values

// Returns a dictionary from key to a ^id() block. The block will return an object value for the
// preference or nil if the normal path (of taking the NSUserDefaults value or +defaultObjectForKey)
// should be used.
+ (NSDictionary *)computedObjectDictionary {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ KEY_IDLE_PERIOD: PROFILE_BLOCK(antiIdlePeriodWithLegacyDefaultInProfile) };
        [dict retain];
    }
    return dict;
}

+ (id)computedObjectForKey:(NSString *)key inProfile:(Profile *)profile {
    id (^block)(Profile *) = [self computedObjectDictionary][key];
    if (block) {
        return block(profile);
    } else {
        return nil;
    }
}

+ (NSString *)uncomputedObjectForKey:(NSString *)key inProfile:(Profile *)profile {
    id object = profile[key];
    if (!object) {
        object = [self defaultObjectForKey:key];
    }
    return object;
}

+ (id)antiIdlePeriodWithLegacyDefaultInProfile:(Profile *)profile {
    NSString *const key = KEY_IDLE_PERIOD;

    // If the profile has a value.
    NSNumber *value = profile[key];
    if (value) {
        return value;
    }

    // If the user set a preference with the now-removed advanced setting, use it.
    NSNumber *legacyDefault = [[NSUserDefaults standardUserDefaults] objectForKey:@"AntiIdleTimerPeriod"];
    if (legacyDefault) {
        return legacyDefault;
    }

    // Fall back to the default from the dictionary.
    return [self defaultObjectForKey:key];
}

@end
