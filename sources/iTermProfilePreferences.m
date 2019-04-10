//
//  iTermProfilePreferences.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermProfilePreferences.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCursor.h"
#import "iTermPreferences.h"
#import "iTermStatusBarLayout.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "PreferencePanel.h"

#define PROFILE_BLOCK(x) [^id(Profile *profile) { return [self x:profile]; } copy]

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

+ (NSInteger)integerForKey:(NSString *)key inProfile:(Profile *)profile {
    return [[self objectForKey:key inProfile:profile] integerValue];
}

+ (void)setInteger:(NSInteger)value
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
        case kPreferenceInfoTypeRadioButton:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeColorWell:
            return ([defaultValue isKindOfClass:[NSNull class]] ||
                    [defaultValue isKindOfClass:[NSDictionary class]]);
    }

    return NO;
}

+ (NSArray<NSString *> *)allKeys {
    // KEY_ASK_ABOUT_OUTDATED_KEYMAPS excluded because it should be deprecated.
    NSArray<NSString *> *keysWithoutDefaultValues =
        @[ KEY_GUID, KEY_TRIGGERS, KEY_SMART_SELECTION_RULES, KEY_SEMANTIC_HISTORY, KEY_BOUND_HOSTS,
           KEY_ORIGINAL_GUID, KEY_AWDS_WIN_OPTION, KEY_AWDS_WIN_DIRECTORY, KEY_AWDS_TAB_OPTION,
           KEY_AWDS_TAB_DIRECTORY, KEY_AWDS_PANE_OPTION, KEY_AWDS_PANE_DIRECTORY,
           KEY_NORMAL_FONT, KEY_NON_ASCII_FONT, KEY_BACKGROUND_IMAGE_LOCATION, KEY_KEYBOARD_MAP,
           KEY_TOUCHBAR_MAP, KEY_DYNAMIC_PROFILE_PARENT_NAME, KEY_DYNAMIC_PROFILE_FILENAME ];
    return [self.defaultValueMap.allKeys arrayByAddingObjectsFromArray:keysWithoutDefaultValues];
}

+ (NSString *)jsonEncodedValueForKey:(NSString *)key inProfile:(Profile *)profile {
    id value = [self objectForKey:key inProfile:profile];
    if (!value) {
        return nil;
    }
    return [NSJSONSerialization it_jsonStringForObject:value];
}

#pragma mark - Private

+ (BOOL)valueIsLegal:(id)value forKey:(NSString *)key {
    NSArray *string = @[ KEY_NAME, KEY_BADGE_FORMAT, KEY_ANSWERBACK_STRING ];

    NSArray *color = @[ KEY_FOREGROUND_COLOR, KEY_BACKGROUND_COLOR, KEY_BOLD_COLOR,
                        KEY_LINK_COLOR, KEY_SELECTION_COLOR, KEY_SELECTED_TEXT_COLOR,
                        KEY_CURSOR_COLOR, KEY_CURSOR_TEXT_COLOR, KEY_ANSI_0_COLOR,
                        KEY_ANSI_1_COLOR, KEY_ANSI_2_COLOR, KEY_ANSI_3_COLOR, KEY_ANSI_4_COLOR,
                        KEY_ANSI_5_COLOR, KEY_ANSI_6_COLOR, KEY_ANSI_7_COLOR, KEY_ANSI_8_COLOR,
                        KEY_ANSI_9_COLOR, KEY_ANSI_10_COLOR, KEY_ANSI_11_COLOR, KEY_ANSI_12_COLOR,
                        KEY_ANSI_13_COLOR, KEY_ANSI_14_COLOR, KEY_ANSI_15_COLOR,
                        KEY_CURSOR_GUIDE_COLOR, KEY_BADGE_COLOR, KEY_TAB_COLOR,
                        KEY_UNDERLINE_COLOR ];

    NSArray *number = @[ KEY_USE_CURSOR_GUIDE, KEY_USE_TAB_COLOR, KEY_USE_UNDERLINE_COLOR,
                         KEY_SMART_CURSOR_COLOR, KEY_MINIMUM_CONTRAST, KEY_CURSOR_BOOST,
                         KEY_CURSOR_TYPE, KEY_BLINKING_CURSOR, KEY_USE_BOLD_FONT, KEY_THIN_STROKES,
                         KEY_ASCII_LIGATURES, KEY_NON_ASCII_LIGATURES, KEY_USE_BOLD_COLOR,
                         KEY_BLINK_ALLOWED, KEY_USE_ITALIC_FONT, KEY_AMBIGUOUS_DOUBLE_WIDTH,
                         KEY_UNICODE_NORMALIZATION, KEY_HORIZONTAL_SPACING, KEY_VERTICAL_SPACING,
                         KEY_USE_NONASCII_FONT, KEY_TRANSPARENCY, KEY_INITIAL_USE_TRANSPARENCY,
                         KEY_BLUR, KEY_BLUR_RADIUS,
                         KEY_BACKGROUND_IMAGE_TILED_DEPRECATED, KEY_BACKGROUND_IMAGE_MODE, KEY_BLEND, KEY_SYNC_TITLE_DEPRECATED,
                         KEY_DISABLE_WINDOW_RESIZING,
                         KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR,
                         KEY_ASCII_ANTI_ALIASED, KEY_NONASCII_ANTI_ALIASED, KEY_SCROLLBACK_LINES,
                         KEY_UNLIMITED_SCROLLBACK, KEY_SCROLLBACK_WITH_STATUS_BAR,
                         KEY_SCROLLBACK_IN_ALTERNATE_SCREEN, KEY_CHARACTER_ENCODING,
                         KEY_XTERM_MOUSE_REPORTING, KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL,
                         KEY_UNICODE_VERSION, KEY_ALLOW_TITLE_REPORTING, KEY_ALLOW_TITLE_SETTING,
                         KEY_DISABLE_PRINTING, KEY_DISABLE_SMCUP_RMCUP, KEY_SILENCE_BELL,
                         KEY_BOOKMARK_USER_NOTIFICATIONS, KEY_SEND_BELL_ALERT, KEY_SEND_IDLE_ALERT,
                         KEY_SEND_NEW_OUTPUT_ALERT, KEY_SEND_SESSION_ENDED_ALERT,
                         KEY_SEND_TERMINAL_GENERATED_ALERT, KEY_FLASHING_BELL, KEY_VISUAL_BELL,
                         KEY_CLOSE_SESSIONS_ON_END, KEY_PROMPT_CLOSE,
                         KEY_UNDO_TIMEOUT, KEY_REDUCE_FLICKER, KEY_SHOW_STATUS_BAR, KEY_SEND_CODE_WHEN_IDLE,
                         KEY_IDLE_CODE, KEY_IDLE_PERIOD, KEY_OPTION_KEY_SENDS,
                         KEY_RIGHT_OPTION_KEY_SENDS, KEY_APPLICATION_KEYPAD_ALLOWED,
                         KEY_PLACE_PROMPT_AT_FIRST_COLUMN, KEY_SHOW_MARK_INDICATORS,
                         KEY_POWERLINE, KEY_TRIGGERS_USE_INTERPOLATED_STRINGS
                       ];
    NSArray *dict = @[ KEY_STATUS_BAR_LAYOUT ];
    if ([string containsObject:key]) {
        return [value isKindOfClass:[NSString class]];
    } else if ([color containsObject:key]) {
        return [value isKindOfClass:[NSDictionary class]] && [(NSDictionary *)value isColorValue];
    } else if ([number containsObject:key]) {
        return [value isKindOfClass:[NSNumber class]];
    } else if ([dict containsObject:key]) {
        return [value isKindOfClass:[NSDictionary class]];
    } else {
        return NO;
    }
}

+ (NSDictionary *)defaultValueMap {
    static NSDictionary *dict;
    if (!dict) {
        dict = @{ KEY_NAME: @"Default",
                  KEY_SHORTCUT: [NSNull null],
                  KEY_ICON: @(iTermProfileIconNone),
                  KEY_ICON_PATH: @"",
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
                  KEY_UNDERLINE_COLOR: [NSNull null],
                  KEY_USE_UNDERLINE_COLOR: @NO,
                  KEY_SMART_CURSOR_COLOR: @NO,
                  KEY_MINIMUM_CONTRAST: @0.0,
                  KEY_CURSOR_BOOST: @0.0,
                  KEY_CURSOR_TYPE: @(CURSOR_BOX),
                  KEY_BLINKING_CURSOR: @NO,
                  KEY_USE_BOLD_FONT: @YES,
                  KEY_THIN_STROKES: @(iTermThinStrokesSettingRetinaOnly),
                  KEY_ASCII_LIGATURES: @NO,
                  KEY_NON_ASCII_LIGATURES: @NO,
                  KEY_USE_BOLD_COLOR: @YES,
                  KEY_BLINK_ALLOWED: @NO,
                  KEY_USE_ITALIC_FONT: @YES,
                  KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO,
                  KEY_USE_HFS_PLUS_MAPPING: @NO,
                  KEY_UNICODE_NORMALIZATION: @(iTermUnicodeNormalizationNone),
                  KEY_HORIZONTAL_SPACING: @1.0,
                  KEY_VERTICAL_SPACING: @1.0,
                  KEY_USE_NONASCII_FONT: @YES,
                  KEY_TRANSPARENCY: @0.0,
                  KEY_INITIAL_USE_TRANSPARENCY: @YES,
                  KEY_BLUR: @NO,
                  KEY_BLUR_RADIUS: @2.0,
                  KEY_BACKGROUND_IMAGE_TILED_DEPRECATED: @NO,
                  KEY_BACKGROUND_IMAGE_MODE: @(iTermBackgroundImageModeStretch),
                  KEY_BLEND: @0.5,
                  KEY_COLUMNS: @80,
                  KEY_ROWS: @25,
                  KEY_HIDE_AFTER_OPENING: @NO,
                  KEY_WINDOW_TYPE: @(WINDOW_TYPE_NORMAL),
                  KEY_USE_CUSTOM_WINDOW_TITLE: @NO,
                  KEY_CUSTOM_WINDOW_TITLE: @"",
                  KEY_SCREEN: @-1,
                  KEY_SPACE: @(iTermProfileOpenInCurrentSpace),
                  KEY_SYNC_TITLE_DEPRECATED: @NO,
                  KEY_DISABLE_WINDOW_RESIZING: @NO,
                  KEY_PREVENT_TAB: @NO,
                  KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR: @NO,
                  KEY_OPEN_TOOLBELT: @NO,
                  KEY_ASCII_ANTI_ALIASED: @NO,
                  KEY_NONASCII_ANTI_ALIASED: @NO,
                  KEY_POWERLINE: @NO,
                  KEY_SCROLLBACK_LINES: @1000,
                  KEY_UNLIMITED_SCROLLBACK: @NO,
                  KEY_SCROLLBACK_WITH_STATUS_BAR: @NO,
                  KEY_SCROLLBACK_IN_ALTERNATE_SCREEN: @YES,
                  KEY_CHARACTER_ENCODING: @(NSUTF8StringEncoding),
                  KEY_TERMINAL_TYPE: @"xterm",
                  KEY_ANSWERBACK_STRING: @"",
                  KEY_XTERM_MOUSE_REPORTING: @NO,
                  KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL: @YES,
                  KEY_UNICODE_VERSION: @8,
                  KEY_ALLOW_TITLE_REPORTING: @NO,
                  KEY_ALLOW_TITLE_SETTING: @YES,
                  KEY_DISABLE_PRINTING: @NO,
                  KEY_DISABLE_SMCUP_RMCUP: @NO,
                  KEY_SILENCE_BELL: @NO,
                  KEY_BOOKMARK_USER_NOTIFICATIONS: @NO,
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
                  KEY_USE_LIBTICKIT_PROTOCOL: @NO,
                  KEY_PLACE_PROMPT_AT_FIRST_COLUMN: @YES,
                  KEY_SHOW_MARK_INDICATORS: @YES,
                  KEY_HAS_HOTKEY: @NO,
                  KEY_HOTKEY_MODIFIER_FLAGS: @0,
                  KEY_HOTKEY_CHARACTERS: @"",
                  KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS: @"",
                  KEY_HOTKEY_KEY_CODE: @0,
                  KEY_HOTKEY_AUTOHIDE: @YES,
                  KEY_HOTKEY_REOPEN_ON_ACTIVATION: @NO,
                  KEY_HOTKEY_ANIMATE: @YES,
                  KEY_HOTKEY_FLOAT: @YES,
                  KEY_HOTKEY_DOCK_CLICK_ACTION: @(iTermHotKeyDockPreferenceDoNotShow),
                  KEY_HOTKEY_MODIFIER_ACTIVATION: @0,
                  KEY_HOTKEY_ACTIVATE_WITH_MODIFIER: @NO,
                  KEY_HOTKEY_ALTERNATE_SHORTCUTS: @[],
                  KEY_SESSION_HOTKEY: @{},
                  KEY_TITLE_COMPONENTS : @(iTermTitleComponentsSessionName),
                  KEY_TITLE_FUNC: [NSNull null],
                  KEY_SHOW_STATUS_BAR: @NO,
                  KEY_STATUS_BAR_LAYOUT: @{},
                  KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: @NO
                  // Remember to update valueIsLegal:forKey: and the websocket
                  // README.md when adding a new value that should be
                  // API-settable.
                };
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
    [self setObject:object forKey:key inProfile:profile model:model withSideEffects:YES];
}

+ (void)setObject:(id)object
           forKey:(NSString *)key
        inProfile:(Profile *)profile
            model:(ProfileModel *)model
  withSideEffects:(BOOL)withSideEffects {
    [model setObject:object forKey:key inBookmark:profile];
    if (withSideEffects) {
        [model flush];
        [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                            object:nil
                                                          userInfo:nil];
    }
}

+ (void)setObjectsFromDictionary:(NSDictionary *)dictionary
                       inProfile:(Profile *)profile
                           model:(ProfileModel *)model {
    [model setObjectsFromDictionary:dictionary inProfile:profile];
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
        dict = @{ KEY_IDLE_PERIOD: PROFILE_BLOCK(antiIdlePeriodWithLegacyDefaultInProfile),
                  KEY_UNICODE_NORMALIZATION: PROFILE_BLOCK(unicodeNormalizationForm),
                  KEY_UNICODE_VERSION: PROFILE_BLOCK(unicodeVersion),
                  KEY_TITLE_COMPONENTS: PROFILE_BLOCK(titleComponents),
                  KEY_BACKGROUND_IMAGE_MODE: PROFILE_BLOCK(backgroundImageMode),
                  KEY_STATUS_BAR_LAYOUT: PROFILE_BLOCK(statusBarLayout),
                  KEY_BADGE_TOP_MARGIN: PROFILE_BLOCK(badgeTopMargin),
                  KEY_BADGE_RIGHT_MARGIN: PROFILE_BLOCK(badgeRightMargin),
                  KEY_BADGE_MAX_WIDTH: PROFILE_BLOCK(badgeMaxWidth),
                  KEY_BADGE_MAX_HEIGHT: PROFILE_BLOCK(badgeMaxHeight),
                  KEY_BADGE_FONT: PROFILE_BLOCK(badgeFont),
                  KEY_WINDOW_TYPE: PROFILE_BLOCK(windowType)
                };
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

+ (id)unicodeNormalizationForm:(Profile *)profile {
    NSString *const key = KEY_UNICODE_NORMALIZATION;

    // If the profile has a value.
    NSNumber *value = profile[key];
    if (value) {
        return value;
    }

    // If the deprecated boolean was set, use it
    value = profile[KEY_USE_HFS_PLUS_MAPPING];
    if (value) {
        return value.boolValue ? @(iTermUnicodeNormalizationHFSPlus) : @(iTermUnicodeNormalizationNone);
    }

    // Fall back to the default from the dictionary.
    return [self defaultObjectForKey:key];
}

+ (id)unicodeVersion:(Profile *)profile {
    NSString *const key = KEY_UNICODE_VERSION;

    // If the profile has a value.
    NSNumber *value = profile[key];
    if (value) {
        return value;
    }

    if (@available(macOS 10.13, *)) {
        // macOS 10.13 has switched to unicode 9 widths. If you're sshing somewhere then you're
        // going to have a bad time. My hope is that this makes people happier on balance.
        return @9;
    } else {
        // Fall back to the default from the dictionary.
        return [self defaultObjectForKey:key];
    }
}

+ (id)backgroundImageMode:(Profile *)profile {
    if (profile[KEY_BACKGROUND_IMAGE_MODE] != nil) {
        return profile[KEY_BACKGROUND_IMAGE_MODE];
    }
    NSNumber *tiled = profile[KEY_BACKGROUND_IMAGE_TILED_DEPRECATED];
    if (tiled.boolValue) {
        return @(iTermBackgroundImageModeTile);
    }
    
    return @(iTermBackgroundImageModeStretch);
}

+ (id)statusBarLayout:(Profile *)profile {
    if (profile[KEY_STATUS_BAR_LAYOUT]) {
        return profile[KEY_STATUS_BAR_LAYOUT];
    }
    static NSDictionary *defaultValue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iTermStatusBarLayout *layout;
        layout = [[iTermStatusBarLayout alloc] initWithScope:nil];
        defaultValue = layout.dictionaryValue;
    });
    return defaultValue;
}

+ (id)badgeTopMargin:(Profile *)profile {
    id value = profile[KEY_BADGE_TOP_MARGIN];
    if (value) {
        return value;
    }
    return @([iTermAdvancedSettingsModel badgeTopMargin]);
}

+ (id)badgeRightMargin:(Profile *)profile {
    id value = profile[KEY_BADGE_RIGHT_MARGIN];
    if (value) {
        return value;
    }
    return @([iTermAdvancedSettingsModel badgeRightMargin]);
}

+ (id)badgeMaxWidth:(Profile *)profile {
    id value = profile[KEY_BADGE_MAX_WIDTH];
    if (value) {
        return value;
    }
    return @([iTermAdvancedSettingsModel badgeMaxWidthFraction]);
}

+ (id)badgeMaxHeight:(Profile *)profile {
    id value = profile[KEY_BADGE_MAX_HEIGHT];
    if (value) {
        return value;
    }
    return @([iTermAdvancedSettingsModel badgeMaxHeightFraction]);
}

+ (id)windowType:(Profile *)profile {
    NSNumber *number = profile[KEY_WINDOW_TYPE];
    if (!number) {
        return nil;
    }
    return @(iTermSanitizedWindowType(number.intValue));
}

+ (id)badgeFont:(Profile *)profile {
    id value = profile[KEY_BADGE_FONT];
    if (value) {
        return value;
    }

    NSString *baseFontName = [iTermAdvancedSettingsModel badgeFont];
    if ([iTermAdvancedSettingsModel badgeFontIsBold]) {
        NSFont *font = [NSFont fontWithName:baseFontName size:12] ?: [NSFont fontWithName:@"Helvetica" size:12] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
        NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
        if (boldFont) {
            return boldFont.fontName;
        }
        return font.fontName;
    }

    return baseFontName;
}

+ (id)titleComponents:(Profile *)profile {
    NSString *const key = KEY_TITLE_COMPONENTS;
    if (profile[key]) {
        // A value is explicitly set. No migration needed.
        return profile[key];
    }

    // Respect any existing now-deprecated settings.
    NSNumber *stickyNumber = [[NSUserDefaults standardUserDefaults] objectForKey:KEY_SYNC_TITLE_DEPRECATED];
    NSNumber *showJobNumber = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyShowJobName_Deprecated];
    NSNumber *showProfileNameNumber = [[NSUserDefaults standardUserDefaults] objectForKey:kPreferenceKeyShowProfileName_Deprecated];

    if (!stickyNumber && !showJobNumber && !showProfileNameNumber) {
        // No deprecated settings; use the modern default.
        return nil;
    }

    if (!stickyNumber) {
        stickyNumber = @NO;
    }
    if (!showJobNumber) {
        showJobNumber = @YES;
    }
    if (!showProfileNameNumber) {
        showProfileNameNumber = @NO;
    }

    const BOOL sticky = stickyNumber.boolValue;
    const BOOL showJob = showJobNumber.boolValue;
    const BOOL showProfileName = showProfileNameNumber.boolValue;
    NSUInteger titleComponents = 0;
    if (showJob) {
        titleComponents |= iTermTitleComponentsJob;
    }
    if (showProfileName) {
        if (sticky) {
            titleComponents |= iTermTitleComponentsProfileAndSessionName;
        } else {
            titleComponents |= iTermTitleComponentsSessionName;
        }
    } else {
        titleComponents |= iTermTitleComponentsSessionName;
    }

    return @(titleComponents);
}

@end
