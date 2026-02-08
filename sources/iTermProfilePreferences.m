//
//  iTermProfilePreferences.m
//  iTerm
//
//  Created by George Nachman on 4/10/14.
//
//

#import "iTermProfilePreferences.h"
#import "iTermUserDefaults.h"

#define ENABLE_DEPRECATED_ADVANCED_SETTINGS

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSJSONSerialization+iTerm.h"
#import "PreferencePanel.h"
#import "Trigger.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCursor.h"
#import "iTermPreferences.h"
#import "iTermScriptHistory.h"
#import "iTermStatusBarLayout.h"

#define PROFILE_BLOCK(x) [^id(Profile *profile) { return [self x:profile]; } copy]

NSString *const kProfilePreferenceInitialDirectoryCustomValue = @"Yes";
NSString *const kProfilePreferenceInitialDirectoryHomeValue = @"No";
NSString *const kProfilePreferenceInitialDirectoryRecycleValue = @"Recycle";
NSString *const kProfilePreferenceInitialDirectoryAdvancedValue = @"Advanced";

typedef struct {
    NSDictionary<NSString *, BOOL (^)(id)> *validationBlocks;
    NSDictionary<NSString *, id (^)(id)> *conversionBlocks;
    NSDictionary<NSString *, NSString *> *typeHelp;
} iTermProfilePreferencesKeyFuncs;

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
    id obj = [self objectForKey:key inProfile:profile];
    if (![obj respondsToSelector:@selector(unsignedIntegerValue)]) {
        return 0;
    }
    return [obj unsignedIntegerValue];
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
        case kPreferenceInfoTypeSegmentedControl:
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
        case kPreferenceInfoTypeStringPopup:
        case kPreferenceInfoTypePasswordTextField:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeStringTextField:
            return ([defaultValue isKindOfClass:[NSString class]] ||
                    [defaultValue isKindOfClass:[NSNull class]]);
        case kPreferenceInfoTypeTokenField:
            return ([defaultValue isKindOfClass:[NSNull class]] ||
                    [defaultValue isKindOfClass:[NSArray class]]);
        case kPreferenceInfoTypeStringTextView:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeMatrix:
            return [defaultValue isKindOfClass:[NSString class]];
        case kPreferenceInfoTypeRadioButton:
            return [defaultValue isKindOfClass:[NSNumber class]];
        case kPreferenceInfoTypeColorWell:
            return ([defaultValue isKindOfClass:[NSNull class]] ||
                    [defaultValue isKindOfClass:[NSDictionary class]]);
    }

    return NO;
}

+ (BOOL)valueIsExplicitlySetForKey:(NSString *)key inProfile:(Profile *)profile {
    return profile[key] != nil;
}

+ (NSArray<NSString *> *)keysWithoutDefaultValues {
    return @[ KEY_GUID, KEY_TRIGGERS, KEY_SMART_SELECTION_RULES, KEY_SEMANTIC_HISTORY, KEY_BOUND_HOSTS,
              KEY_ORIGINAL_GUID, KEY_AWDS_WIN_OPTION, KEY_AWDS_WIN_DIRECTORY, KEY_AWDS_TAB_OPTION,
              KEY_AWDS_TAB_DIRECTORY, KEY_AWDS_PANE_OPTION, KEY_AWDS_PANE_DIRECTORY,
              KEY_NORMAL_FONT, KEY_NON_ASCII_FONT, KEY_FONT_CONFIG, KEY_KEYBOARD_MAP,
              KEY_TOUCHBAR_MAP, KEY_DYNAMIC_PROFILE_PARENT_NAME, KEY_DYNAMIC_PROFILE_PARENT_GUID,
              KEY_DYNAMIC_PROFILE_FILENAME, KEY_DYNAMIC_PROFILE_REWRITABLE, KEY_DYNAMIC_PROFILE ];
}
+ (NSArray<NSString *> *)allKeys {
    return [self.defaultValueMap.allKeys arrayByAddingObjectsFromArray:self.keysWithoutDefaultValues];
}

+ (NSString *)jsonEncodedValueForKey:(NSString *)key inProfile:(Profile *)profile {
    id value = [self objectForKey:key inProfile:profile];
    if (!value) {
        return nil;
    }
    if ([key isEqual:KEY_TRIGGERS] && [value isKindOfClass:[NSArray class]]) {
        NSArray<NSDictionary *> *dicts = value;
        value = [dicts mapWithBlock:^NSDictionary *_Nonnull(NSDictionary *_Nonnull dict) {
            return [Trigger sanitizedTriggerDictionary:dict];
        }];
    }
    return [NSJSONSerialization it_jsonStringForObject:value];
}

+ (id _Nullable)plistValueFromBoundVariableValue:(id)value forKey:(NSString *)key {
    // You can bind a setting to a Variable, typically a user-defined variable. This method takes
    // the value of the user-defined variable and converts it to a plist-friendly value that the
    // profile setting `key` can safely be set to.
    NSDictionary<NSString *, id (^)(id)> *conversionBlocks = self.keyFuncs.conversionBlocks;
    id (^block)(id) = conversionBlocks[key];
    if (!block) {
        return nil;
    }
    return block(value);
}

+ (NSString * _Nullable)typeHelpForKey:(NSString *)key {
    return self.keyFuncs.typeHelp[key];
}

#pragma mark - Private

+ (iTermProfilePreferencesKeyFuncs)keyFuncs {
    static iTermProfilePreferencesKeyFuncs funcs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        funcs.validationBlocks = [NSMutableDictionary dictionary];
        NSArray *string = @[ KEY_NAME, KEY_BADGE_FORMAT, KEY_ANSWERBACK_STRING, KEY_NORMAL_FONT,
                             KEY_NON_ASCII_FONT, KEY_FONT_CONFIG, KEY_AWDS_TAB_OPTION, KEY_AWDS_PANE_OPTION, KEY_AWDS_WIN_OPTION,
                             KEY_SHORTCUT, KEY_ICON_PATH, KEY_CUSTOM_COMMAND, KEY_COMMAND_LINE,
                             KEY_INITIAL_TEXT, KEY_CUSTOM_DIRECTORY, KEY_WORKING_DIRECTORY,
                             KEY_CUSTOM_WINDOW_TITLE, KEY_CUSTOM_TAB_TITLE,
                             KEY_HOTKEY_CHARACTERS, KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS,
                             KEY_LOGDIR, KEY_LOG_FILENAME_FORMAT, KEY_TERMINAL_TYPE, KEY_TITLE_FUNC, KEY_GUID,
                             KEY_ARCHIVEDIR,
                             KEY_ORIGINAL_GUID, KEY_AWDS_WIN_DIRECTORY, KEY_AWDS_TAB_OPTION,
                             KEY_AWDS_TAB_DIRECTORY, KEY_AWDS_PANE_OPTION, KEY_AWDS_PANE_DIRECTORY,
                             KEY_BACKGROUND_IMAGE_LOCATION, KEY_DYNAMIC_PROFILE_PARENT_NAME,
                             KEY_DYNAMIC_PROFILE_PARENT_GUID,
                             KEY_DYNAMIC_PROFILE_FILENAME, KEY_TMUX_PANE_TITLE,
                             KEY_SUBTITLE, KEY_CUSTOM_LOCALE, KEY_INITIAL_URL,
                             KEY_BROWSER_EXTENSIONS_ROOT, KEY_BROWSER_EXTENSION_ACTIVE_IDS,
                             KEY_PROGRESS_BAR_COLOR_SCHEME];

        NSArray *color = @[ KEY_FOREGROUND_COLOR, KEY_BACKGROUND_COLOR, KEY_BOLD_COLOR,
                            KEY_LINK_COLOR, KEY_MATCH_COLOR, KEY_SELECTION_COLOR, KEY_SELECTED_TEXT_COLOR,
                            KEY_CURSOR_COLOR, KEY_CURSOR_TEXT_COLOR, KEY_ANSI_0_COLOR,
                            KEY_ANSI_1_COLOR, KEY_ANSI_2_COLOR, KEY_ANSI_3_COLOR, KEY_ANSI_4_COLOR,
                            KEY_ANSI_5_COLOR, KEY_ANSI_6_COLOR, KEY_ANSI_7_COLOR, KEY_ANSI_8_COLOR,
                            KEY_ANSI_9_COLOR, KEY_ANSI_10_COLOR, KEY_ANSI_11_COLOR, KEY_ANSI_12_COLOR,
                            KEY_ANSI_13_COLOR, KEY_ANSI_14_COLOR, KEY_ANSI_15_COLOR,
                            KEY_CURSOR_GUIDE_COLOR, KEY_BADGE_COLOR, KEY_TAB_COLOR,
                            KEY_UNDERLINE_COLOR, KEY_ACTIVE_PANE_BORDER_COLOR ];
        color = [color flatMapWithBlock:^NSArray *(NSString *key) {
            return @[ key,
                      [key stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX],
                      [key stringByAppendingString:COLORS_DARK_MODE_SUFFIX]];
        }];

        NSArray *booleans = @[
            KEY_USE_CURSOR_GUIDE COLORS_LIGHT_MODE_SUFFIX,
            KEY_USE_CURSOR_GUIDE COLORS_DARK_MODE_SUFFIX,
            KEY_USE_CURSOR_GUIDE,

            KEY_USE_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX,
            KEY_USE_TAB_COLOR COLORS_DARK_MODE_SUFFIX,
            KEY_USE_TAB_COLOR,

            KEY_USE_SELECTED_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX,
            KEY_USE_SELECTED_TEXT_COLOR COLORS_DARK_MODE_SUFFIX,
            KEY_USE_SELECTED_TEXT_COLOR,

            KEY_USE_UNDERLINE_COLOR COLORS_LIGHT_MODE_SUFFIX,
            KEY_USE_UNDERLINE_COLOR COLORS_DARK_MODE_SUFFIX,
            KEY_USE_UNDERLINE_COLOR,

            KEY_USE_ACTIVE_PANE_BORDER COLORS_LIGHT_MODE_SUFFIX,
            KEY_USE_ACTIVE_PANE_BORDER COLORS_DARK_MODE_SUFFIX,
            KEY_USE_ACTIVE_PANE_BORDER,

            KEY_SMART_CURSOR_COLOR COLORS_LIGHT_MODE_SUFFIX,
            KEY_SMART_CURSOR_COLOR COLORS_DARK_MODE_SUFFIX,
            KEY_SMART_CURSOR_COLOR,

            KEY_USE_BOLD_COLOR,
            KEY_USE_BOLD_COLOR COLORS_LIGHT_MODE_SUFFIX,
            KEY_USE_BOLD_COLOR COLORS_DARK_MODE_SUFFIX,

            KEY_BLINKING_CURSOR, KEY_USE_BOLD_FONT,
            KEY_ASCII_LIGATURES, KEY_NON_ASCII_LIGATURES, KEY_CURSOR_SHADOW,
            KEY_ANIMATE_MOVEMENT, KEY_CURSOR_HIDDEN_WITHOUT_FOCUS,
            KEY_ANIMATE_MOVEMENT_ONLY_IN_INTERACTIVE_APPS,

            KEY_BRIGHTEN_BOLD_TEXT,
            KEY_BRIGHTEN_BOLD_TEXT COLORS_LIGHT_MODE_SUFFIX,
            KEY_BRIGHTEN_BOLD_TEXT COLORS_DARK_MODE_SUFFIX,

            KEY_BLINK_ALLOWED, KEY_USE_ITALIC_FONT, KEY_AMBIGUOUS_DOUBLE_WIDTH,
            KEY_USE_NONASCII_FONT, KEY_INITIAL_USE_TRANSPARENCY, KEY_BLUR,
            KEY_DISABLE_WINDOW_RESIZING, KEY_DISABLE_UNFOCUSED_WINDOW_RESIZING,
            KEY_ALLOW_CHANGE_CURSOR_BLINK,
            KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR,
            KEY_ASCII_ANTI_ALIASED, KEY_NONASCII_ANTI_ALIASED,

            KEY_UNLIMITED_SCROLLBACK, KEY_SCROLLBACK_WITH_STATUS_BAR,
            KEY_SCROLLBACK_IN_ALTERNATE_SCREEN,

            KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED,
            KEY_AUTOMATICALLY_ENABLE_ALTERNATE_MOUSE_SCROLL,
            KEY_RESTRICT_ALTERNATE_MOUSE_SCROLL_TO_VERTICAL,
            KEY_XTERM_MOUSE_REPORTING, KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL,
            KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS,
            KEY_ALLOW_TITLE_REPORTING, KEY_ALLOW_ALTERNATE_MOUSE_SCROLL,
            KEY_RESTRICT_MOUSE_REPORTING_TO_ALTERNATE_SCREEN_MODE,
            KEY_ALLOW_TITLE_SETTING,
            KEY_DISABLE_PRINTING, KEY_DISABLE_SMCUP_RMCUP, KEY_SILENCE_BELL,
            KEY_DEFAULT_PANE_LOCKED,

            KEY_BOOKMARK_USER_NOTIFICATIONS, KEY_SEND_BELL_ALERT, KEY_SEND_IDLE_ALERT,
            KEY_SEND_NEW_OUTPUT_ALERT, KEY_SEND_SESSION_ENDED_ALERT,
            KEY_SEND_TERMINAL_GENERATED_ALERT, KEY_FLASHING_BELL, KEY_VISUAL_BELL,
            KEY_SUPPRESS_ALERTS_IN_ACTIVE_SESSION,

            KEY_REDUCE_FLICKER, KEY_SHOW_STATUS_BAR, KEY_SEND_CODE_WHEN_IDLE,
            KEY_APPLICATION_KEYPAD_ALLOWED, KEY_ALLOW_MODIFY_OTHER_KEYS,
            KEY_LEFT_OPTION_KEY_CHANGEABLE, KEY_RIGHT_OPTION_KEY_CHANGEABLE,
            KEY_PLACE_PROMPT_AT_FIRST_COLUMN, KEY_SHOW_MARK_INDICATORS, KEY_SHOW_OFFSCREEN_COMMANDLINE,
            KEY_SHOW_OFFSCREEN_COMMANDLINE_FOR_CURRENT_COMMAND,

            KEY_TMUX_NEWLINE, KEY_PROMPT_PATH_CLICK_OPENS_NAVIGATOR,
            KEY_POWERLINE, KEY_TRIGGERS_USE_INTERPOLATED_STRINGS,
            KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS,
            KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS,

            KEY_AUTOLOG, KEY_ARCHIVE, KEY_HAS_HOTKEY,
            KEY_HIDE_AFTER_OPENING, KEY_LOCK_WINDOW_SIZE_AUTOMATICALLY,
            KEY_HOTKEY_AUTOHIDE, KEY_HOTKEY_REOPEN_ON_ACTIVATION, KEY_HOTKEY_ANIMATE,
            KEY_HOTKEY_FLOAT, KEY_OPEN_TOOLBELT, KEY_PREVENT_TAB,
            KEY_HOTKEY_ACTIVATE_WITH_MODIFIER,

            KEY_USE_CUSTOM_WINDOW_TITLE, KEY_USE_CUSTOM_TAB_TITLE,
            KEY_USE_LIBTICKIT_PROTOCOL,

            KEY_ALLOW_PASTE_BRACKETING, KEY_ENABLE_PROGRESS_BARS,
            KEY_PREVENT_APS, KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS,
            KEY_TREAT_OPTION_AS_ALT,
            KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY,

            KEY_TIMESTAMPS_VISIBLE,
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE,
            KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY,
            KEY_DYNAMIC_PROFILE_REWRITABLE,
            KEY_DYNAMIC_PROFILE,
            KEY_BROWSER_DEV_NULL,
            KEY_INSTANT_REPLAY,
        ];
        NSArray *number = @[
            KEY_MINIMUM_CONTRAST COLORS_LIGHT_MODE_SUFFIX,
            KEY_MINIMUM_CONTRAST COLORS_DARK_MODE_SUFFIX,
            KEY_MINIMUM_CONTRAST,

            KEY_FAINT_TEXT_ALPHA COLORS_LIGHT_MODE_SUFFIX,
            KEY_FAINT_TEXT_ALPHA COLORS_DARK_MODE_SUFFIX,
            KEY_FAINT_TEXT_ALPHA,

            KEY_CURSOR_BOOST COLORS_LIGHT_MODE_SUFFIX,
            KEY_CURSOR_BOOST COLORS_DARK_MODE_SUFFIX,
            KEY_CURSOR_BOOST,

            KEY_CURSOR_TYPE, KEY_THIN_STROKES,

            KEY_UNICODE_NORMALIZATION, KEY_HORIZONTAL_SPACING, KEY_VERTICAL_SPACING,
            KEY_TRANSPARENCY,
            KEY_BLUR_RADIUS,
            KEY_BACKGROUND_IMAGE_MODE, KEY_BLEND,
            KEY_SCROLLBACK_LINES,
            KEY_CHARACTER_ENCODING,

            KEY_UNICODE_VERSION,

            KEY_SESSION_END_ACTION, KEY_PROMPT_CLOSE,
            KEY_UNDO_TIMEOUT,
            KEY_IDLE_CODE, KEY_IDLE_PERIOD, KEY_OPTION_KEY_SENDS,
            KEY_RIGHT_OPTION_KEY_SENDS,

            KEY_COLUMNS, KEY_ROWS, KEY_ICON,
            KEY_LOGGING_STYLE,
            KEY_WIDTH_PERCENTAGE, KEY_HEIGHT_PERCENTAGE,
            KEY_HOTKEY_MODIFIER_FLAGS, KEY_HOTKEY_KEY_CODE,
            KEY_HOTKEY_DOCK_CLICK_ACTION,
            KEY_HOTKEY_MODIFIER_ACTIVATION,

            KEY_SCREEN, KEY_SET_LOCALE_VARS, KEY_SPACE,
            KEY_TITLE_COMPONENTS,
            KEY_WINDOW_TYPE,
            KEY_PROGRESS_BAR_HEIGHT,
            KEY_TIMESTAMPS_STYLE,

            KEY_COMPOSER_TOP_OFFSET,
            KEY_LEFT_CONTROL,
            KEY_RIGHT_CONTROL,
            KEY_LEFT_COMMAND,
            KEY_RIGHT_COMMAND,
            KEY_FUNCTION,

            KEY_BROWSER_ZOOM,
            KEY_WIDTH, KEY_HEIGHT,

            KEY_PROFILE_TYPE_PHONY
        ];
        NSArray *stringArrays = @[ KEY_TAGS, KEY_JOBS, KEY_BOUND_HOSTS, KEY_SNIPPETS_FILTER ];
        NSArray *dictArrays = @[ KEY_HOTKEY_ALTERNATE_SHORTCUTS, KEY_TRIGGERS, KEY_SMART_SELECTION_RULES,
                                 ];
        NSArray *dict = @[ KEY_STATUS_BAR_LAYOUT, KEY_SESSION_HOTKEY, KEY_SEMANTIC_HISTORY,
                           KEY_KEYBOARD_MAP, KEY_TOUCHBAR_MAP, KEY_SSH_CONFIG, KEY_BINDINGS];

        NSMutableDictionary *validationBlocks = [NSMutableDictionary dictionary];
        NSMutableDictionary *conversionBlocks = [NSMutableDictionary dictionary];
        NSMutableDictionary *typeHelp = [NSMutableDictionary dictionary];
        for (NSString *key in string) {
            validationBlocks[key] = ^BOOL(id value) { return [value isKindOfClass:[NSString class]]; };
        }
        for (NSString *key in color) {
            typeHelp[key] = @"Colors can be specified as 3- or 6-digit hex strings such as \"#f8a\" like in HTML. By default it uses the sRGB color space. To use P3 instead, place p3 before the # as in: \"p3#f8a\". While you can use a string literal here, typically this would come from a string-valued variable or function.";
            validationBlocks[key] = ^BOOL(id value) {
                return ([value isKindOfClass:[NSDictionary class]] &&
                        [value isColorValue]);
            };
            conversionBlocks[key] = ^id(id value) {
                NSString *string = [NSString castFrom:value];
                if (!string) {
                    if (value) {
                        NSString *keyDescription = [iTermProfilePreferences descriptionForKey:key] ?: key;
                        NSString *valueTypeDescription = [value it_classDescription];
                        NSString *logMessage = [NSString stringWithFormat:@"❗️ The bound expression for %@ is a color. It expected a string like #ff8844 but got the value “%@” of type “%@” instead.\n",
                                                keyDescription,
                                                value,
                                                valueTypeDescription];
                        [[iTermScriptHistoryEntry globalEntry] addOutput:logMessage completion:^{}];
                    }
                    return nil;
                }
                return [[NSColor colorFromHexString:string] dictionaryValue];
            };
        }
        for (NSString *key in number) {
            validationBlocks[key] = ^BOOL(id value) { return [value isKindOfClass:[NSNumber class]]; };
        }
        for (NSString *key in booleans) {
            validationBlocks[key] = ^BOOL(id value) { return [value isKindOfClass:[NSNumber class]]; };
            conversionBlocks[key] = ^id(id value) {
                NSNumber *number = [NSNumber castFrom:value];
                if (number) {
                    return @(number.boolValue);
                }
                NSString *string = [NSString castFrom:value];
                if (string) {
                    return @(string.boolValue);
                }
                return nil;
            };
            typeHelp[key] = @"Checkboxes accept numbers (0 is false and any other number is true), strings containing a number, or strings like \"true\" and \"false\". While you can use a numeric literal here, typically this would come from a number-valued variable or function.";
        }
        for (NSString *key in stringArrays) {
            validationBlocks[key] = ^BOOL(id value) {
                if (![value isKindOfClass:[NSArray class]]) {
                    return NO;
                }
                for (id obj in value) {
                    if (![obj isKindOfClass:[NSString class]]) {
                        return NO;
                    }
                }
                return YES;
            };
        }
        for (NSString *key in dictArrays) {
            validationBlocks[key] = ^BOOL(id value) {
                if (![value isKindOfClass:[NSArray class]]) {
                    return NO;
                }
                for (id obj in value) {
                    if (![obj isKindOfClass:[NSDictionary class]]) {
                        return NO;
                    }
                }
                return YES;
            };
        }
        for (NSString *key in dict) {
            validationBlocks[key] = ^BOOL(id value) { return [value isKindOfClass:[NSDictionary class]]; };
        }
        funcs.validationBlocks = validationBlocks;
        funcs.conversionBlocks = conversionBlocks;
        funcs.typeHelp = typeHelp;
    });
    return funcs;
}

+ (NSDictionary<NSString *, BOOL (^)(id)> *)validationBlocks {
    return self.keyFuncs.validationBlocks;
}

+ (BOOL)valueIsLegal:(id)value forKey:(NSString *)key {
    BOOL (^block)(id) = [[self validationBlocks] objectForKey:key];
    if (!block) {
        return NO;
    }
    if (!value) {
        return YES;
    }
    return block(value);
}

+ (NSString *)descriptionForKey:(NSString *)key {
    static NSDictionary<NSString *, NSString *> *dict;
    if (!dict) {
        dict = @{
            KEY_FOREGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX:          @"Default text color in light mode",
            KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX:          @"Terminal background color in light mode",
            KEY_BOLD_COLOR COLORS_LIGHT_MODE_SUFFIX:                @"Color for bold text in light mode",
            KEY_LINK_COLOR COLORS_LIGHT_MODE_SUFFIX:                @"Color for clickable links in light mode",
            KEY_MATCH_COLOR COLORS_LIGHT_MODE_SUFFIX:               @"Highlight color for search matches in light mode",
            KEY_SELECTION_COLOR COLORS_LIGHT_MODE_SUFFIX:           @"Background color of selected text in light mode",
            KEY_SELECTED_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX:       @"Text color of selected text in light mode",
            KEY_CURSOR_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"Cursor fill color in light mode",
            KEY_CURSOR_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX:         @"Color of text under the cursor in light mode",
            KEY_ANSI_0_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI black color in light mode",
            KEY_ANSI_1_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI red color in light mode",
            KEY_ANSI_2_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI green color in light mode",
            KEY_ANSI_3_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI yellow color in light mode",
            KEY_ANSI_4_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI blue color in light mode",
            KEY_ANSI_5_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI magenta color in light mode",
            KEY_ANSI_6_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI cyan color in light mode",
            KEY_ANSI_7_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI white color in light mode",
            KEY_ANSI_8_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI bright black color in light mode",
            KEY_ANSI_9_COLOR COLORS_LIGHT_MODE_SUFFIX:              @"ANSI bright red color in light mode",
            KEY_ANSI_10_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"ANSI bright green color in light mode",
            KEY_ANSI_11_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"ANSI bright yellow color in light mode",
            KEY_ANSI_12_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"ANSI bright blue color in light mode",
            KEY_ANSI_13_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"ANSI bright magenta color in light mode",
            KEY_ANSI_14_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"ANSI bright cyan color in light mode",
            KEY_ANSI_15_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"ANSI bright white color in light mode",
            KEY_CURSOR_GUIDE_COLOR COLORS_LIGHT_MODE_SUFFIX:        @"Cursor Guide color in light mode",
            KEY_BADGE_COLOR COLORS_LIGHT_MODE_SUFFIX:               @"Color of the badge overlay in light mode",
            KEY_ACTIVE_PANE_BORDER_COLOR COLORS_LIGHT_MODE_SUFFIX:  @"Border color for active pane in light mode",
            KEY_FOREGROUND_COLOR COLORS_DARK_MODE_SUFFIX:           @"Default text color in dark mode",
            KEY_BACKGROUND_COLOR COLORS_DARK_MODE_SUFFIX:           @"Terminal background color in dark mode",
            KEY_BOLD_COLOR COLORS_DARK_MODE_SUFFIX:                 @"Color for bold text in dark mode",
            KEY_LINK_COLOR COLORS_DARK_MODE_SUFFIX:                 @"Color for clickable links in dark mode",
            KEY_MATCH_COLOR COLORS_DARK_MODE_SUFFIX:                @"Highlight color for search matches in dark mode",
            KEY_SELECTION_COLOR COLORS_DARK_MODE_SUFFIX:            @"Background color of selected text in dark mode",
            KEY_SELECTED_TEXT_COLOR COLORS_DARK_MODE_SUFFIX:        @"Text color of selected text in dark mode",
            KEY_CURSOR_COLOR COLORS_DARK_MODE_SUFFIX:               @"Cursor fill color in dark mode",
            KEY_CURSOR_TEXT_COLOR COLORS_DARK_MODE_SUFFIX:          @"Color of text under the cursor in dark mode",
            KEY_ANSI_0_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI black color in dark mode",
            KEY_ANSI_1_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI red color in dark mode",
            KEY_ANSI_2_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI green color in dark mode",
            KEY_ANSI_3_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI yellow color in dark mode",
            KEY_ANSI_4_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI blue color in dark mode",
            KEY_ANSI_5_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI magenta color in dark mode",
            KEY_ANSI_6_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI cyan color in dark mode",
            KEY_ANSI_7_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI white color in dark mode",
            KEY_ANSI_8_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI bright black color in dark mode",
            KEY_ANSI_9_COLOR COLORS_DARK_MODE_SUFFIX:               @"ANSI bright red color in dark mode",
            KEY_ANSI_10_COLOR COLORS_DARK_MODE_SUFFIX:              @"ANSI bright green color in dark mode",
            KEY_ANSI_11_COLOR COLORS_DARK_MODE_SUFFIX:              @"ANSI bright yellow color in dark mode",
            KEY_ANSI_12_COLOR COLORS_DARK_MODE_SUFFIX:              @"ANSI bright blue color in dark mode",
            KEY_ANSI_13_COLOR COLORS_DARK_MODE_SUFFIX:              @"ANSI bright magenta color in dark mode",
            KEY_ANSI_14_COLOR COLORS_DARK_MODE_SUFFIX:              @"ANSI bright cyan color in dark mode",
            KEY_ANSI_15_COLOR COLORS_DARK_MODE_SUFFIX:              @"ANSI bright white color in dark mode",
            KEY_CURSOR_GUIDE_COLOR COLORS_DARK_MODE_SUFFIX:         @"Cursor Guide color in dark mode",
            KEY_BADGE_COLOR COLORS_DARK_MODE_SUFFIX:                @"Color of the badge overlay in dark mode",
            KEY_ACTIVE_PANE_BORDER_COLOR COLORS_DARK_MODE_SUFFIX:   @"Border color for active pane in dark mode",
            KEY_USE_CURSOR_GUIDE COLORS_LIGHT_MODE_SUFFIX:          @"Whether to show the Cursor Guide in light mode",
            KEY_USE_CURSOR_GUIDE COLORS_DARK_MODE_SUFFIX:           @"Whether to show the Cursor Guide in dark mode",
            KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX:                 @"Tab Color in light mode",
            KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX:                  @"Tab Color in dark mode",
            KEY_USE_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX:             @"Whether to use a custom Tab Color in light mode",
            KEY_USE_TAB_COLOR COLORS_DARK_MODE_SUFFIX:              @"Whether to use a custom Tab Color in dark mode",
            KEY_USE_SELECTED_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX:   @"Whether to use a custom color for selected text in light mode",
            KEY_USE_SELECTED_TEXT_COLOR COLORS_DARK_MODE_SUFFIX:    @"Whether to use a custom color for selected text in dark mode",
            KEY_UNDERLINE_COLOR COLORS_LIGHT_MODE_SUFFIX:           @"Color for underlined text in light mode",
            KEY_UNDERLINE_COLOR COLORS_DARK_MODE_SUFFIX:            @"Color for underlined text in dark mode",
            KEY_USE_UNDERLINE_COLOR COLORS_LIGHT_MODE_SUFFIX:       @"Whether to use a custom underline color in light mode",
            KEY_USE_UNDERLINE_COLOR COLORS_DARK_MODE_SUFFIX:        @"Whether to use a custom underline color in dark mode",
            KEY_USE_ACTIVE_PANE_BORDER COLORS_LIGHT_MODE_SUFFIX:    @"Whether to show a border around the active pane in light mode",
            KEY_USE_ACTIVE_PANE_BORDER COLORS_DARK_MODE_SUFFIX:     @"Whether to show a border around the active pane in dark mode",
            KEY_SMART_CURSOR_COLOR COLORS_LIGHT_MODE_SUFFIX:        @"Whether cursor color is based on underlying text in light mode",
            KEY_SMART_CURSOR_COLOR COLORS_DARK_MODE_SUFFIX:         @"Whether cursor color is based on underlying text in dark mode",
            KEY_MINIMUM_CONTRAST COLORS_LIGHT_MODE_SUFFIX:          @"Minimum contrast ratio between text and background in light mode",
            KEY_MINIMUM_CONTRAST COLORS_DARK_MODE_SUFFIX:           @"Minimum contrast ratio between text and background in dark mode",
            KEY_FAINT_TEXT_ALPHA COLORS_LIGHT_MODE_SUFFIX:          @"Opacity of faint (dim) text in light mode",
            KEY_FAINT_TEXT_ALPHA COLORS_DARK_MODE_SUFFIX:           @"Opacity of faint (dim) text in dark mode",
            KEY_CURSOR_BOOST COLORS_LIGHT_MODE_SUFFIX:              @"Amount to dim non-cursor text to highlight cursor in light mode",
            KEY_CURSOR_BOOST COLORS_DARK_MODE_SUFFIX:               @"Amount to dim non-cursor text to highlight cursor in dark mode",
            KEY_USE_BOLD_COLOR COLORS_LIGHT_MODE_SUFFIX:            @"Whether to use a separate color for bold text in light mode",
            KEY_USE_BOLD_COLOR COLORS_DARK_MODE_SUFFIX:             @"Whether to use a separate color for bold text in dark mode",
            KEY_BRIGHTEN_BOLD_TEXT COLORS_LIGHT_MODE_SUFFIX:        @"Whether to brighten bold text in light mode",
            KEY_BRIGHTEN_BOLD_TEXT COLORS_DARK_MODE_SUFFIX:         @"Whether to brighten bold text in dark mode",

            KEY_NAME:                                               @"Profile name",
            KEY_SHORTCUT:                                           @"Keyboard shortcut character for ⌃⌘ profile access",
            KEY_ICON:                                               @"Type of icon to display for this profile",
            KEY_ICON_PATH:                                          @"Path to custom icon image file",
            KEY_TAGS:                                               @"Tags for organizing and filtering profiles",
            KEY_CUSTOM_COMMAND:                                     @"Command type: Login Shell, Custom Command, Custom Shell, SSH, or Browser",
            KEY_PROFILE_TYPE_PHONY:                                 @"Profile type for UI display",
            KEY_COMMAND_LINE:                                       @"Command to run when session starts",
            KEY_INITIAL_TEXT:                                       @"Text to send to session after shell starts",
            KEY_CUSTOM_DIRECTORY:                                   @"Initial directory type: Home, Custom, Recycle, or Advanced",
            KEY_WORKING_DIRECTORY:                                  @"Custom initial working directory path",
            KEY_BADGE_FORMAT:                                       @"Text template for the badge overlay",
            KEY_SUBTITLE:                                           @"Subtitle shown below profile name in Open Quickly",
            KEY_INITIAL_URL:                                        @"Initial URL for Browser profile type",
            KEY_SSH_CONFIG:                                         @"SSH connection configuration dictionary",
            KEY_FOREGROUND_COLOR:                                   @"Default text color",
            KEY_BACKGROUND_COLOR:                                   @"Terminal background color",
            KEY_BOLD_COLOR:                                         @"Color for bold text",
            KEY_LINK_COLOR:                                         @"Color for clickable links",
            KEY_MATCH_COLOR:                                        @"Highlight color for search matches",
            KEY_SELECTION_COLOR:                                    @"Background color of selected text",
            KEY_SELECTED_TEXT_COLOR:                                @"Text color of selected text",
            KEY_CURSOR_COLOR:                                       @"Cursor fill color",
            KEY_CURSOR_TEXT_COLOR:                                  @"Color of text under the cursor",
            KEY_ANSI_0_COLOR:                                       @"ANSI black color",
            KEY_ANSI_1_COLOR:                                       @"ANSI red color",
            KEY_ANSI_2_COLOR:                                       @"ANSI green color",
            KEY_ANSI_3_COLOR:                                       @"ANSI yellow color",
            KEY_ANSI_4_COLOR:                                       @"ANSI blue color",
            KEY_ANSI_5_COLOR:                                       @"ANSI magenta color",
            KEY_ANSI_6_COLOR:                                       @"ANSI cyan color",
            KEY_ANSI_7_COLOR:                                       @"ANSI white color",
            KEY_ANSI_8_COLOR:                                       @"ANSI bright black color",
            KEY_ANSI_9_COLOR:                                       @"ANSI bright red color",
            KEY_ANSI_10_COLOR:                                      @"ANSI bright green color",
            KEY_ANSI_11_COLOR:                                      @"ANSI bright yellow color",
            KEY_ANSI_12_COLOR:                                      @"ANSI bright blue color",
            KEY_ANSI_13_COLOR:                                      @"ANSI bright magenta color",
            KEY_ANSI_14_COLOR:                                      @"ANSI bright cyan color",
            KEY_ANSI_15_COLOR:                                      @"ANSI bright white color",
            KEY_CURSOR_GUIDE_COLOR:                                 @"Cursor Guide color",
            KEY_BADGE_COLOR:                                        @"Color of the badge overlay",
            KEY_USE_CURSOR_GUIDE:                                   @"Whether to show the Cursor Guide",
            KEY_TAB_COLOR:                                          @"Tab Color",
            KEY_USE_TAB_COLOR:                                      @"Whether to use a custom Tab Color",
            KEY_USE_SELECTED_TEXT_COLOR:                            @"Whether to use a custom color for selected text",
            KEY_UNDERLINE_COLOR:                                    @"Color for underlined text",
            KEY_USE_UNDERLINE_COLOR:                                @"Whether to use a custom underline color",
            KEY_ACTIVE_PANE_BORDER_COLOR:                           @"Border color for active pane",
            KEY_USE_ACTIVE_PANE_BORDER:                             @"Whether to show a border around the active pane",
            KEY_SMART_CURSOR_COLOR:                                 @"Whether cursor color is based on underlying text",
            KEY_MINIMUM_CONTRAST:                                   @"Minimum contrast ratio between text and background",
            KEY_FAINT_TEXT_ALPHA:                                   @"Opacity of faint (dim) text",
            KEY_CURSOR_BOOST:                                       @"Amount to dim non-cursor text to highlight cursor",
            KEY_CURSOR_TYPE:                                        @"Cursor style: box, vertical bar, or underline",
            KEY_BLINKING_CURSOR:                                    @"Whether the cursor blinks",
            KEY_CURSOR_SHADOW:                                      @"Whether the cursor has a shadow",
            KEY_CURSOR_HIDDEN_WITHOUT_FOCUS:                        @"Whether to hide cursor when window loses focus",
            KEY_ANIMATE_MOVEMENT:                                   @"Whether to animate cursor movement",
            KEY_ANIMATE_MOVEMENT_ONLY_IN_INTERACTIVE_APPS:          @"Whether to animate cursor movement only in interactive apps",
            KEY_USE_BOLD_FONT:                                      @"Whether to use bold font for bold text",
            KEY_THIN_STROKES:                                       @"Anti-aliased text stroke thickness setting",
            KEY_ASCII_LIGATURES:                                    @"Whether to render ligatures in ASCII text",
            KEY_NON_ASCII_LIGATURES:                                @"Whether to render ligatures in non-ASCII text",
            KEY_USE_BOLD_COLOR:                                     @"Whether to use a separate color for bold text",
            KEY_BRIGHTEN_BOLD_TEXT:                                 @"Whether to brighten bold text",
            KEY_BLINK_ALLOWED:                                      @"Whether blinking text is allowed",
            KEY_USE_ITALIC_FONT:                                    @"Whether to use italic font for italic text",
            KEY_AMBIGUOUS_DOUBLE_WIDTH:                             @"Whether to treat ambiguous-width characters as double-width",
            KEY_UNICODE_NORMALIZATION:                              @"Unicode normalization form to apply",
            KEY_HORIZONTAL_SPACING:                                 @"Horizontal spacing multiplier between characters",
            KEY_VERTICAL_SPACING:                                   @"Vertical spacing multiplier between lines",
            KEY_USE_NONASCII_FONT:                                  @"Whether to use a separate font for non-ASCII characters",
            KEY_TRANSPARENCY:                                       @"Window transparency level (0=opaque, 1=fully transparent)",
            KEY_INITIAL_USE_TRANSPARENCY:                           @"Whether new sessions start with transparency enabled",
            KEY_BLUR:                                               @"Whether to blur the background behind transparent windows",
            KEY_BLUR_RADIUS:                                        @"Radius of background blur effect",
            KEY_BACKGROUND_IMAGE_MODE:                              @"How background image is displayed: stretch, tile, scale, or fill",
            KEY_BACKGROUND_IMAGE_LOCATION:                          @"Path to background image file",
            KEY_BLEND:                                              @"Blend level between background image and background color",
            KEY_COLUMNS:                                            @"Initial number of columns in terminal",
            KEY_ROWS:                                               @"Initial number of rows in terminal",
            KEY_HIDE_AFTER_OPENING:                                 @"Whether to hide window immediately after opening",
            KEY_LOCK_WINDOW_SIZE_AUTOMATICALLY:                     @"Whether to lock window size immediately after opening",
            KEY_WINDOW_TYPE:                                        @"Window style: normal, fullscreen, maximized, etc.",
            KEY_USE_CUSTOM_WINDOW_TITLE:                            @"Whether to use a custom window title",
            KEY_CUSTOM_WINDOW_TITLE:                                @"Custom window title template",
            KEY_USE_CUSTOM_TAB_TITLE:                               @"Whether to use a custom tab title",
            KEY_CUSTOM_TAB_TITLE:                                   @"Custom tab title template",
            KEY_SCREEN:                                             @"Which screen to open new windows on",
            KEY_SPACE:                                              @"Which Space to open new windows on",
            KEY_DISABLE_WINDOW_RESIZING:                            @"Whether to prevent window resizing by escape sequences",
            KEY_DISABLE_UNFOCUSED_WINDOW_RESIZING:                  @"Whether to prevent resize by unfocused sessions",
            KEY_ALLOW_CHANGE_CURSOR_BLINK:                          @"Whether escape sequences can change cursor blink",
            KEY_PREVENT_TAB:                                        @"Whether to prevent opening this profile in a tab",
            KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR: @"Whether transparency applies only to default background",
            KEY_OPEN_TOOLBELT:                                      @"Whether to open toolbelt when session starts",
            KEY_ASCII_ANTI_ALIASED:                                 @"Whether to anti-alias ASCII text",
            KEY_NONASCII_ANTI_ALIASED:                              @"Whether to anti-alias non-ASCII text",
            KEY_POWERLINE:                                          @"Whether to draw Powerline glyphs",
            KEY_SCROLLBACK_LINES:                                   @"Number of lines to keep in scrollback buffer",
            KEY_UNLIMITED_SCROLLBACK:                               @"Whether to allow unlimited scrollback",
            KEY_SCROLLBACK_WITH_STATUS_BAR:                         @"Whether to include status bar content in scrollback",
            KEY_SCROLLBACK_IN_ALTERNATE_SCREEN:                     @"Whether to save scrollback in alternate screen mode",
            KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED:   @"Whether to disable drag-to-scroll in alternate screen mode",
            KEY_AUTOMATICALLY_ENABLE_ALTERNATE_MOUSE_SCROLL:        @"Whether to automatically enable mouse scroll in alternate screen",
            KEY_RESTRICT_ALTERNATE_MOUSE_SCROLL_TO_VERTICAL:        @"Whether to restrict alternate mouse scroll to vertical only",
            KEY_CHARACTER_ENCODING:                                 @"Character encoding for the terminal (e.g., UTF-8)",
            KEY_TERMINAL_TYPE:                                      @"Terminal type string reported to applications (e.g., xterm-256color)",
            KEY_ANSWERBACK_STRING:                                  @"String sent in response to ENQ character",
            KEY_XTERM_MOUSE_REPORTING:                              @"Whether to enable xterm mouse reporting",
            KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL:            @"Whether mouse wheel events are reported",
            KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS:       @"Whether mouse clicks and drags are reported",
            KEY_UNICODE_VERSION:                                    @"Unicode version for character width calculations",
            KEY_ALLOW_TITLE_REPORTING:                              @"Whether applications can query window title",
            KEY_ALLOW_ALTERNATE_MOUSE_SCROLL:                       @"Whether to convert scroll wheel to arrow keys in alternate screen",
            KEY_RESTRICT_MOUSE_REPORTING_TO_ALTERNATE_SCREEN_MODE:  @"Whether mouse reporting is only enabled in alternate screen mode",
            KEY_ALLOW_TITLE_SETTING:                                @"Whether applications can set window/tab title",
            KEY_COMPOSER_TOP_OFFSET:                                @"Vertical offset of the Composer from the top of the session",
            KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY:               @"Whether to inject shell integration automatically",
            KEY_DISABLE_PRINTING:                                   @"Whether to disable printing via escape sequences",
            KEY_DISABLE_SMCUP_RMCUP:                                @"Whether to disable alternate screen mode switching",
            KEY_SILENCE_BELL:                                       @"Whether to silence the terminal bell",
            KEY_DEFAULT_PANE_LOCKED:                                @"Whether new panes are locked by default",
            KEY_BOOKMARK_USER_NOTIFICATIONS:                        @"Whether to post user notifications for this profile",
            KEY_SEND_BELL_ALERT:                                    @"Whether to send notification when bell rings",
            KEY_SEND_IDLE_ALERT:                                    @"Whether to send notification when session becomes idle",
            KEY_SEND_NEW_OUTPUT_ALERT:                              @"Whether to send notification on new output",
            KEY_SEND_SESSION_ENDED_ALERT:                           @"Whether to send notification when session ends",
            KEY_SEND_TERMINAL_GENERATED_ALERT:                      @"Whether to send notifications triggered by escape sequences",
            KEY_SUPPRESS_ALERTS_IN_ACTIVE_SESSION:                  @"Whether to suppress alerts sent by the active session",
            KEY_FLASHING_BELL:                                      @"Whether to flash the screen on bell",
            KEY_VISUAL_BELL:                                        @"Whether to show visual indicator on bell",
            KEY_SET_LOCALE_VARS:                                    @"How to set locale environment variables",
            KEY_CUSTOM_LOCALE:                                      @"Custom locale string to use",
            KEY_SESSION_END_ACTION:                                 @"Action when session ends: default, close, or restart",
            KEY_PROMPT_CLOSE:                                       @"When to prompt before closing session",
            KEY_UNDO_TIMEOUT:                                       @"Seconds to allow undoing session close",
            KEY_JOBS:                                               @"Job names to ignore when prompting before close",
            KEY_REDUCE_FLICKER:                                     @"Whether to reduce flicker with extra synchronization",
            KEY_AUTOLOG:                                            @"Whether to automatically log session output",
            KEY_ARCHIVE:                                            @"Whether to archive session on closure",
            KEY_LOGGING_STYLE:                                      @"Logging format: raw, plain text, HTML, or asciicast",
            KEY_LOGDIR:                                             @"Directory for automatic logging files",
            KEY_ARCHIVEDIR:                                         @"Directory for archived sessions",
            KEY_LOG_FILENAME_FORMAT:                                @"Template for log filename",
            KEY_SEND_CODE_WHEN_IDLE:                                @"Whether to send anti-idle code periodically",
            KEY_IDLE_CODE:                                          @"Character code to send when idle",
            KEY_IDLE_PERIOD:                                        @"Seconds between anti-idle codes",
            KEY_OPTION_KEY_SENDS:                                   @"What left Option key sends: Normal, Meta, or Esc+",
            KEY_RIGHT_OPTION_KEY_SENDS:                             @"What right Option key sends: Normal, Meta, or Esc+",
            KEY_LEFT_CONTROL:                                       @"Left Control key behavior: Regular, Hyper, Meta, or Super",
            KEY_RIGHT_CONTROL:                                      @"Right Control key behavior: Regular, Hyper, Meta, or Super",
            KEY_LEFT_COMMAND:                                       @"Left Command key behavior: Regular, Hyper, Meta, or Super",
            KEY_RIGHT_COMMAND:                                      @"Right Command key behavior: Regular, Hyper, Meta, or Super",
            KEY_FUNCTION:                                           @"Function key behavior: Regular, Hyper, Meta, or Super",
            KEY_LEFT_OPTION_KEY_CHANGEABLE:                         @"Whether left Option key mode can be toggled at runtime",
            KEY_RIGHT_OPTION_KEY_CHANGEABLE:                        @"Whether right Option key mode can be toggled at runtime",
            KEY_APPLICATION_KEYPAD_ALLOWED:                         @"Whether to allow application keypad mode",
            KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS:      @"Whether arrow keys scroll when not in interactive app",
            KEY_TREAT_OPTION_AS_ALT:                                @"Whether to report Option as Alt in modifier flags",
            KEY_ALLOW_MODIFY_OTHER_KEYS:                            @"Whether to enable modifyOtherKeys mode",
            KEY_USE_LIBTICKIT_PROTOCOL:                             @"Whether to use libtickit keyboard protocol",
            KEY_PLACE_PROMPT_AT_FIRST_COLUMN:                       @"Whether shell integration places prompt at column 1",
            KEY_SHOW_MARK_INDICATORS:                               @"Whether to show shell integration mark indicators",
            KEY_PROMPT_PATH_CLICK_OPENS_NAVIGATOR:                  @"Whether clicking path in prompt opens file navigator",
            KEY_SHOW_OFFSCREEN_COMMANDLINE:                         @"Whether to show command line when scrolled up",
            KEY_SHOW_OFFSCREEN_COMMANDLINE_FOR_CURRENT_COMMAND:     @"Whether to show command line over the top of the screen for the running command",
            KEY_TMUX_NEWLINE:                                       @"Whether to send newline instead of carriage return in tmux",
            KEY_HAS_HOTKEY:                                         @"Whether this profile has a dedicated hotkey window",
            KEY_HOTKEY_MODIFIER_FLAGS:                              @"Modifier flags for the hotkey",
            KEY_HOTKEY_CHARACTERS:                                  @"Character(s) produced by the hotkey",
            KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS:               @"Character(s) of hotkey ignoring modifiers",
            KEY_HOTKEY_KEY_CODE:                                    @"Virtual key code of the hotkey",
            KEY_HOTKEY_AUTOHIDE:                                    @"Whether hotkey window hides when focus is lost",
            KEY_HOTKEY_REOPEN_ON_ACTIVATION:                        @"Whether to reopen hotkey window on app activation",
            KEY_HOTKEY_ANIMATE:                                     @"Whether to animate hotkey window appearance",
            KEY_HOTKEY_FLOAT:                                       @"Whether hotkey window floats above other windows",
            KEY_HOTKEY_DOCK_CLICK_ACTION:                           @"Action when clicking dock icon for hotkey window",
            KEY_HOTKEY_MODIFIER_ACTIVATION:                         @"Modifier key combination for double-tap activation",
            KEY_HOTKEY_ACTIVATE_WITH_MODIFIER:                      @"Whether double-tap modifier activates hotkey window",
            KEY_HOTKEY_ALTERNATE_SHORTCUTS:                         @"Additional keyboard shortcuts for hotkey window",
            KEY_SESSION_HOTKEY:                                     @"Keyboard shortcut to switch to this session",
            KEY_TITLE_COMPONENTS:                                   @"Bitmask of components to include in session title",
            KEY_TITLE_FUNC:                                         @"Custom function for generating session title",
            KEY_SHOW_STATUS_BAR:                                    @"Whether to show the status bar",
            KEY_STATUS_BAR_LAYOUT:                                  @"Configuration for status bar components and layout",
            KEY_TRIGGERS_USE_INTERPOLATED_STRINGS:                  @"Whether trigger parameters use interpolated strings",
            KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS:                @"Whether triggers fire in interactive applications",
            KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS:   @"Whether smart selection actions use interpolated strings",
            KEY_AWDS_TAB_OPTION:                                    @"Working directory option for new tabs",
            KEY_AWDS_PANE_OPTION:                                   @"Working directory option for new split panes",
            KEY_AWDS_WIN_OPTION:                                    @"Working directory option for new windows",
            KEY_TMUX_PANE_TITLE:                                    @"Title of tmux pane for edit session dialog",
            KEY_ALLOW_PASTE_BRACKETING:                             @"Whether to enable bracketed paste mode",
            KEY_ENABLE_PROGRESS_BARS:                               @"Whether to show progress bars for file transfers",
            KEY_PROGRESS_BAR_HEIGHT:                                @"Height of progress bars in points",
            KEY_PROGRESS_BAR_COLOR_SCHEME:                          @"Color scheme for progress bars",
            KEY_PREVENT_APS:                                        @"Whether to prevent automatic profile switching",
            KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY:                @"Whether to open password manager on password prompt",
            KEY_TIMESTAMPS_STYLE:                                   @"Style of timestamp display",
            KEY_TIMESTAMPS_VISIBLE:                                 @"Whether timestamps are visible",
            KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE:        @"Whether to use different colors for light and dark mode",
            KEY_SNIPPETS_FILTER:                                    @"Tags to filter available snippets",
            KEY_BROWSER_ZOOM:                                       @"Zoom level for Browser profile (100=100%)",
            KEY_BROWSER_DEV_NULL:                                   @"Whether Browser profile discards output",
            KEY_BROWSER_EXTENSIONS_ROOT:                            @"Root directory for browser extensions",
            KEY_BROWSER_EXTENSION_ACTIVE_IDS:                       @"List of active browser extension IDs",
            KEY_WIDTH:                                              @"Initial width in points for Browser profile",
            KEY_HEIGHT:                                             @"Initial height in points for Browser profile",
            KEY_INSTANT_REPLAY:                                     @"Whether instant replay is enabled for Browser profile",

            KEY_BINDINGS:                                           @"Variable bindings"
        };
    }
    return dict[key];
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
                  KEY_PROFILE_TYPE_PHONY: @0,
                  KEY_COMMAND_LINE: @"",
                  KEY_INITIAL_TEXT: @"",
                  KEY_CUSTOM_DIRECTORY: kProfilePreferenceInitialDirectoryHomeValue,
                  KEY_WORKING_DIRECTORY: @"",
                  KEY_BADGE_FORMAT: @"",
                  KEY_SUBTITLE: @"",
                  KEY_INITIAL_URL: @"iterm2-about:welcome",
                  KEY_SSH_CONFIG: @{},

                  // Note: these defaults aren't used, except for link color, cursor guide color, and match color, because they are always specified.
                  KEY_FOREGROUND_COLOR:    [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_BACKGROUND_COLOR:    [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_BOLD_COLOR:          [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_LINK_COLOR:          [[NSColor colorWithCalibratedRed:0.023 green:0.270 blue:0.678 alpha:1] dictionaryValue],
                  KEY_MATCH_COLOR:         [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:0.000 alpha:1] dictionaryValue],
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
                  KEY_ACTIVE_PANE_BORDER_COLOR: [[NSColor colorWithCalibratedRed:0.0 green:0.5 blue:1.0 alpha:1.0] dictionaryValue],

                  // The light and dark variants are used.
                  KEY_FOREGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX:    [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX:    [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_BOLD_COLOR COLORS_LIGHT_MODE_SUFFIX:          [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_LINK_COLOR COLORS_LIGHT_MODE_SUFFIX:          [[NSColor colorWithCalibratedRed:0.023 green:0.270 blue:0.678 alpha:1] dictionaryValue],
                  KEY_MATCH_COLOR COLORS_LIGHT_MODE_SUFFIX:         [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_SELECTION_COLOR COLORS_LIGHT_MODE_SUFFIX:     [[NSColor colorWithCalibratedRed:0.709 green:0.835 blue:1.000 alpha:1] dictionaryValue],
                  KEY_SELECTED_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX: [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_CURSOR_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_CURSOR_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX:   [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_0_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_1_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_2_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.733 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_3_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_4_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_5_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_6_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_7_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_8_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.333 green:0.333 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_9_COLOR COLORS_LIGHT_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:1.000 green:0.333 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_10_COLOR COLORS_LIGHT_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.333 green:1.000 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_11_COLOR COLORS_LIGHT_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_12_COLOR COLORS_LIGHT_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.333 green:0.333 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_13_COLOR COLORS_LIGHT_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_14_COLOR COLORS_LIGHT_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.333 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_15_COLOR COLORS_LIGHT_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_CURSOR_GUIDE_COLOR COLORS_LIGHT_MODE_SUFFIX:  [[NSColor colorWithCalibratedRed:0.650 green:0.910 blue:1.000 alpha:0.25] dictionaryValue],
                  KEY_BADGE_COLOR COLORS_LIGHT_MODE_SUFFIX:         [[NSColor colorWithCalibratedRed:1.0 green:0.000 blue:0.000 alpha:0.5] dictionaryValue],
                  KEY_ACTIVE_PANE_BORDER_COLOR COLORS_LIGHT_MODE_SUFFIX: [[NSColor colorWithCalibratedRed:0.0 green:0.5 blue:1.0 alpha:1.0] dictionaryValue],

                  KEY_FOREGROUND_COLOR COLORS_DARK_MODE_SUFFIX:    [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_BACKGROUND_COLOR COLORS_DARK_MODE_SUFFIX:    [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_BOLD_COLOR COLORS_DARK_MODE_SUFFIX:          [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_LINK_COLOR COLORS_DARK_MODE_SUFFIX:          [[NSColor colorWithCalibratedRed:0.023 green:0.270 blue:0.678 alpha:1] dictionaryValue],
                  KEY_MATCH_COLOR COLORS_DARK_MODE_SUFFIX:         [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_SELECTION_COLOR COLORS_DARK_MODE_SUFFIX:     [[NSColor colorWithCalibratedRed:0.709 green:0.835 blue:1.000 alpha:1] dictionaryValue],
                  KEY_SELECTED_TEXT_COLOR COLORS_DARK_MODE_SUFFIX: [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_CURSOR_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_CURSOR_TEXT_COLOR COLORS_DARK_MODE_SUFFIX:   [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_0_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_1_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.000 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_2_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.733 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_3_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.000 alpha:1] dictionaryValue],
                  KEY_ANSI_4_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_5_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_6_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.000 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_7_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.733 green:0.733 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_8_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:0.333 green:0.333 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_9_COLOR COLORS_DARK_MODE_SUFFIX:        [[NSColor colorWithCalibratedRed:1.000 green:0.333 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_10_COLOR COLORS_DARK_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.333 green:1.000 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_11_COLOR COLORS_DARK_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:0.333 alpha:1] dictionaryValue],
                  KEY_ANSI_12_COLOR COLORS_DARK_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.333 green:0.333 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_13_COLOR COLORS_DARK_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.000 green:0.000 blue:0.733 alpha:1] dictionaryValue],
                  KEY_ANSI_14_COLOR COLORS_DARK_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:0.333 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_ANSI_15_COLOR COLORS_DARK_MODE_SUFFIX:       [[NSColor colorWithCalibratedRed:1.000 green:1.000 blue:1.000 alpha:1] dictionaryValue],
                  KEY_CURSOR_GUIDE_COLOR COLORS_DARK_MODE_SUFFIX:  [[NSColor colorWithCalibratedRed:0.650 green:0.910 blue:1.000 alpha:0.25] dictionaryValue],
                  KEY_BADGE_COLOR COLORS_DARK_MODE_SUFFIX:         [[NSColor colorWithCalibratedRed:1.0 green:0.000 blue:0.000 alpha:0.5] dictionaryValue],
                  KEY_ACTIVE_PANE_BORDER_COLOR COLORS_DARK_MODE_SUFFIX: [[NSColor colorWithCalibratedRed:0.0 green:0.5 blue:1.0 alpha:1.0] dictionaryValue],


                  KEY_USE_CURSOR_GUIDE: @NO,
                  KEY_USE_CURSOR_GUIDE COLORS_LIGHT_MODE_SUFFIX: @NO,
                  KEY_USE_CURSOR_GUIDE COLORS_DARK_MODE_SUFFIX: @NO,

                  KEY_TAB_COLOR: [NSNull null],
                  KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: [NSNull null],
                  KEY_TAB_COLOR COLORS_DARK_MODE_SUFFIX: [NSNull null],

                  KEY_USE_TAB_COLOR: @NO,
                  KEY_USE_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX: @NO,
                  KEY_USE_TAB_COLOR COLORS_DARK_MODE_SUFFIX: @NO,

                  KEY_USE_SELECTED_TEXT_COLOR: @YES,
                  KEY_USE_SELECTED_TEXT_COLOR COLORS_LIGHT_MODE_SUFFIX: @YES,
                  KEY_USE_SELECTED_TEXT_COLOR COLORS_DARK_MODE_SUFFIX: @YES,

                  KEY_UNDERLINE_COLOR: [NSNull null],
                  KEY_UNDERLINE_COLOR COLORS_LIGHT_MODE_SUFFIX: [NSNull null],
                  KEY_UNDERLINE_COLOR COLORS_DARK_MODE_SUFFIX: [NSNull null],

                  KEY_USE_UNDERLINE_COLOR: @NO,
                  KEY_USE_UNDERLINE_COLOR COLORS_LIGHT_MODE_SUFFIX: @NO,
                  KEY_USE_UNDERLINE_COLOR COLORS_DARK_MODE_SUFFIX: @NO,

                  KEY_USE_ACTIVE_PANE_BORDER: @NO,
                  KEY_USE_ACTIVE_PANE_BORDER COLORS_LIGHT_MODE_SUFFIX: @NO,
                  KEY_USE_ACTIVE_PANE_BORDER COLORS_DARK_MODE_SUFFIX: @NO,

                  KEY_SMART_CURSOR_COLOR: @NO,
                  KEY_SMART_CURSOR_COLOR COLORS_LIGHT_MODE_SUFFIX: @NO,
                  KEY_SMART_CURSOR_COLOR COLORS_DARK_MODE_SUFFIX: @NO,

                  KEY_MINIMUM_CONTRAST: @0.0,
                  KEY_MINIMUM_CONTRAST COLORS_LIGHT_MODE_SUFFIX: @0.0,
                  KEY_MINIMUM_CONTRAST COLORS_DARK_MODE_SUFFIX: @0.0,

                  KEY_FAINT_TEXT_ALPHA: @0.5,
                  KEY_FAINT_TEXT_ALPHA COLORS_LIGHT_MODE_SUFFIX: @0.5,
                  KEY_FAINT_TEXT_ALPHA COLORS_DARK_MODE_SUFFIX: @0.5,

                  KEY_CURSOR_BOOST: @0.0,
                  KEY_CURSOR_BOOST COLORS_LIGHT_MODE_SUFFIX: @0.0,
                  KEY_CURSOR_BOOST COLORS_DARK_MODE_SUFFIX: @0.0,

                  KEY_CURSOR_TYPE: @(CURSOR_BOX),
                  KEY_BLINKING_CURSOR: @NO,
                  KEY_CURSOR_SHADOW: @NO,
                  KEY_CURSOR_HIDDEN_WITHOUT_FOCUS: @NO,
                  KEY_ANIMATE_MOVEMENT: @NO,
                  KEY_ANIMATE_MOVEMENT_ONLY_IN_INTERACTIVE_APPS: @YES,
                  KEY_USE_BOLD_FONT: @YES,
                  KEY_THIN_STROKES: @(iTermThinStrokesSettingRetinaOnly),
                  KEY_ASCII_LIGATURES: @NO,
                  KEY_NON_ASCII_LIGATURES: @NO,

                  KEY_USE_BOLD_COLOR: @YES,
                  KEY_USE_BOLD_COLOR COLORS_LIGHT_MODE_SUFFIX: @YES,
                  KEY_USE_BOLD_COLOR COLORS_DARK_MODE_SUFFIX: @YES,

                  KEY_BRIGHTEN_BOLD_TEXT: @YES,
                  KEY_BRIGHTEN_BOLD_TEXT COLORS_LIGHT_MODE_SUFFIX: @YES,
                  KEY_BRIGHTEN_BOLD_TEXT COLORS_DARK_MODE_SUFFIX: @YES,
                  
                  KEY_BLINK_ALLOWED: @NO,
                  KEY_USE_ITALIC_FONT: @YES,
                  KEY_AMBIGUOUS_DOUBLE_WIDTH: @NO,
                  KEY_UNICODE_NORMALIZATION: @(iTermUnicodeNormalizationNone),
                  KEY_HORIZONTAL_SPACING: @1.0,
                  KEY_VERTICAL_SPACING: @1.0,
                  KEY_USE_NONASCII_FONT: @YES,
                  KEY_TRANSPARENCY: @0.0,
                  KEY_INITIAL_USE_TRANSPARENCY: @YES,
                  KEY_BLUR: @NO,
                  KEY_BLUR_RADIUS: @2.0,
                  KEY_BACKGROUND_IMAGE_MODE: @(iTermBackgroundImageModeStretch),
                  KEY_BACKGROUND_IMAGE_LOCATION: [NSNull null],
                  KEY_BLEND: @0.5,
                  KEY_COLUMNS: @80,
                  KEY_ROWS: @25,
                  KEY_WIDTH_PERCENTAGE: @100,
                  KEY_HEIGHT_PERCENTAGE: @100,
                  KEY_HIDE_AFTER_OPENING: @NO,
                  KEY_LOCK_WINDOW_SIZE_AUTOMATICALLY: @NO,
                  KEY_WINDOW_TYPE: @(WINDOW_TYPE_NORMAL),
                  KEY_USE_CUSTOM_WINDOW_TITLE: @NO,
                  KEY_CUSTOM_WINDOW_TITLE: @"",
                  KEY_USE_CUSTOM_TAB_TITLE: @NO,
                  KEY_CUSTOM_TAB_TITLE: @"",
                  KEY_SCREEN: @-1,
                  KEY_SPACE: @(iTermProfileOpenInCurrentSpace),
                  KEY_DISABLE_WINDOW_RESIZING: @NO,
                  KEY_DISABLE_UNFOCUSED_WINDOW_RESIZING: @YES,
                  KEY_ALLOW_CHANGE_CURSOR_BLINK: @NO,
                  KEY_PREVENT_TAB: @NO,
                  KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR: @NO,
                  KEY_OPEN_TOOLBELT: @NO,
                  KEY_ASCII_ANTI_ALIASED: @NO,
                  KEY_NONASCII_ANTI_ALIASED: @NO,
                  KEY_POWERLINE: @NO,
                  KEY_SCROLLBACK_LINES: @1000,
                  KEY_UNLIMITED_SCROLLBACK: @NO,
                  KEY_SCROLLBACK_WITH_STATUS_BAR: @YES,
                  KEY_SCROLLBACK_IN_ALTERNATE_SCREEN: @YES,
                  KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED: @NO,
                  KEY_AUTOMATICALLY_ENABLE_ALTERNATE_MOUSE_SCROLL: @NO,
                  KEY_RESTRICT_ALTERNATE_MOUSE_SCROLL_TO_VERTICAL: @NO,
                  KEY_CHARACTER_ENCODING: @(NSUTF8StringEncoding),
                  KEY_TERMINAL_TYPE: @"xterm",
                  KEY_ANSWERBACK_STRING: @"",
                  KEY_XTERM_MOUSE_REPORTING: @NO,
                  KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL: @YES,
                  KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS: @YES,
                  KEY_UNICODE_VERSION: @8,
                  KEY_ALLOW_TITLE_REPORTING: @NO,
                  KEY_ALLOW_ALTERNATE_MOUSE_SCROLL: @YES,
                  KEY_RESTRICT_MOUSE_REPORTING_TO_ALTERNATE_SCREEN_MODE: @NO,
                  KEY_ALLOW_TITLE_SETTING: @YES,
                  KEY_COMPOSER_TOP_OFFSET: @0,
                  KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY: @NO,
                  KEY_DISABLE_PRINTING: @NO,
                  KEY_DISABLE_SMCUP_RMCUP: @NO,
                  KEY_SILENCE_BELL: @NO,
                  KEY_DEFAULT_PANE_LOCKED: @NO,
                  KEY_BOOKMARK_USER_NOTIFICATIONS: @NO,
                  KEY_SEND_BELL_ALERT: @YES,
                  KEY_SEND_IDLE_ALERT: @NO,
                  KEY_SEND_NEW_OUTPUT_ALERT: @NO,
                  KEY_SEND_SESSION_ENDED_ALERT: @YES,
                  KEY_SEND_TERMINAL_GENERATED_ALERT: @YES,
                  KEY_SUPPRESS_ALERTS_IN_ACTIVE_SESSION: @NO,
                  KEY_FLASHING_BELL: @NO,
                  KEY_VISUAL_BELL: @NO,
                  KEY_SET_LOCALE_VARS: @(iTermSetLocalVarsModeSetAutomatically),
                  KEY_CUSTOM_LOCALE: @"",
                  KEY_SESSION_END_ACTION: @(iTermSessionEndActionDefault),
                  KEY_PROMPT_CLOSE: @(PROMPT_NEVER),
                  KEY_UNDO_TIMEOUT: @(5),
                  KEY_JOBS: @[],
                  KEY_REDUCE_FLICKER: @NO,
                  KEY_AUTOLOG: @NO,
                  KEY_ARCHIVE: @NO,
                  KEY_LOGGING_STYLE: @(iTermLoggingStyleRaw),
                  KEY_LOGDIR: @"",
                  KEY_ARCHIVEDIR: @"",
                  KEY_LOG_FILENAME_FORMAT: [iTermAdvancedSettingsModel autoLogFormat],
                  KEY_SEND_CODE_WHEN_IDLE: @NO,
                  KEY_IDLE_CODE: @0,
                  KEY_IDLE_PERIOD: @60,
                  KEY_OPTION_KEY_SENDS: @(OPT_NORMAL),
                  KEY_RIGHT_OPTION_KEY_SENDS: @(OPT_NORMAL),
                  KEY_LEFT_CONTROL: @(iTermBuckyBitRegular),
                  KEY_RIGHT_CONTROL: @(iTermBuckyBitRegular),
                  KEY_LEFT_COMMAND: @(iTermBuckyBitRegular),
                  KEY_RIGHT_COMMAND: @(iTermBuckyBitRegular),
                  KEY_FUNCTION: @(iTermBuckyBitRegular),
                  KEY_LEFT_OPTION_KEY_CHANGEABLE: @YES,
                  KEY_RIGHT_OPTION_KEY_CHANGEABLE: @NO,
                  KEY_APPLICATION_KEYPAD_ALLOWED: @NO,
                  KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS: @NO,
                  KEY_TREAT_OPTION_AS_ALT: @YES,
                  KEY_ALLOW_MODIFY_OTHER_KEYS: @YES,
                  KEY_USE_LIBTICKIT_PROTOCOL: @NO,
                  KEY_PLACE_PROMPT_AT_FIRST_COLUMN: @YES,
                  KEY_SHOW_MARK_INDICATORS: @YES,
                  KEY_PROMPT_PATH_CLICK_OPENS_NAVIGATOR: @NO,
                  KEY_SHOW_OFFSCREEN_COMMANDLINE: @YES,
                  KEY_SHOW_OFFSCREEN_COMMANDLINE_FOR_CURRENT_COMMAND: @NO,
                  KEY_TMUX_NEWLINE: @NO,
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
                  KEY_TITLE_COMPONENTS : @(iTermTitleComponentsJob),
                  KEY_TITLE_FUNC: [NSNull null],
                  KEY_SHOW_STATUS_BAR: @NO,
                  KEY_STATUS_BAR_LAYOUT: @{},
                  KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: @NO,
                  KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS: @YES,
                  KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS: @NO,
                  KEY_AWDS_TAB_OPTION: kProfilePreferenceInitialDirectoryHomeValue,
                  KEY_AWDS_PANE_OPTION: kProfilePreferenceInitialDirectoryHomeValue,
                  KEY_AWDS_WIN_OPTION: kProfilePreferenceInitialDirectoryHomeValue,
                  KEY_TMUX_PANE_TITLE: [NSNull null],
                  KEY_ALLOW_PASTE_BRACKETING: @YES,
                  KEY_ENABLE_PROGRESS_BARS: @YES,
                  KEY_PROGRESS_BAR_HEIGHT: @2.0,
                  KEY_PROGRESS_BAR_COLOR_SCHEME: iTermProgressBarColorSchemeDefault,
                  KEY_PREVENT_APS: @NO,
                  KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY: @NO,
                  KEY_TIMESTAMPS_STYLE: @(iTermTimestampsModeOverlap),
                  // Migration path for former advanced setting
                  KEY_TIMESTAMPS_VISIBLE: [[iTermUserDefaults userDefaults] objectForKey:@"ShowTimestampsByDefault"] ?: @NO,
                  KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @NO,
                  KEY_SNIPPETS_FILTER: @[],

                  KEY_BROWSER_ZOOM: @100,
                  KEY_BROWSER_DEV_NULL: @NO,
                  KEY_BROWSER_EXTENSIONS_ROOT: [NSNull null],
                  KEY_BROWSER_EXTENSION_ACTIVE_IDS: @[],
                  KEY_WIDTH: @1000,
                  KEY_HEIGHT: @800,
                  KEY_INSTANT_REPLAY: @NO,

                  KEY_BINDINGS: @{},

                  // NOTES:
                  //   * Remove deprecated values from this list.
                  //   * Update validation blocks in preceding method.
                };
        NSSet<NSString *> *validatedKeys = [NSSet setWithArray:[[iTermProfilePreferences validationBlocks] allKeys]];
        NSSet<NSString *> *allKnownKeys = [NSSet setWithArray:[dict.allKeys arrayByAddingObjectsFromArray:[iTermProfilePreferences keysWithoutDefaultValues]]];
        if (![validatedKeys isEqualToSet:allKnownKeys]) {
            NSLog(@"validated keys not equal to all known keys");
            NSMutableSet *difference = [validatedKeys mutableCopy];
            [difference minusSet:allKnownKeys];
            if (difference.count) {
                NSLog(@"validated contains extra entries: %@", difference);
            }
            difference = [allKnownKeys mutableCopy];
            [difference minusSet:validatedKeys];
            if (difference.count) {
                NSLog(@"validated missing: %@", difference);
            }
            // If you hit this assertion you may have a default value for a
            // deprecated key, a default without a validation block, or a
            // validation block without a default.
            assert(false);
        }
    }
    return dict;
}

+ (NSArray<NSString *> *)nonDeprecatedKeys {
    return [[iTermProfilePreferences validationBlocks] allKeys];
}

+ (NSFont *)fontForKey:(NSString *)key
             inProfile:(Profile *)profile
      ligaturesEnabled:(BOOL)ligaturesEnabled {
    return [ITAddressBookMgr fontWithDesc:[self objectForKey:key inProfile:profile]
                         ligaturesEnabled:ligaturesEnabled];
}

+ (id)objectForColorKey:(NSString *)baseKey
                   dark:(BOOL)dark
                profile:(Profile *)profile {
    NSString *key = [self amendedColorKey:baseKey dark:dark profile:profile];
    return [self objectForKey:key inProfile:profile];
}

+ (NSColor *)colorForKey:(NSString *)baseKey
                    dark:(BOOL)dark
                 profile:(Profile *)profile {
    NSDictionary *dict = [NSDictionary castFrom:[self objectForColorKey:baseKey dark:dark profile:profile]];
    return [dict colorValue];
}

+ (BOOL)boolForColorKey:(NSString *)baseKey dark:(BOOL)dark profile:(NSDictionary *)profile {
    NSString *key = [self amendedColorKey:baseKey dark:dark profile:profile];
    return [self boolForKey:key inProfile:profile];
}

+ (double)floatForColorKey:(NSString *)baseKey
                      dark:(BOOL)dark
                   profile:(Profile *)profile {
    NSString *key = [self amendedColorKey:baseKey dark:dark profile:profile];
    return [self floatForKey:key inProfile:profile];
}

+ (NSString *)amendedColorKey:(NSString *)baseKey
                         dark:(BOOL)dark
                      profile:(Profile *)profile  {
    const BOOL modes = [self boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE inProfile:profile];
    NSString *key = nil;
    if (!modes) {
        key = baseKey;
    } else if (dark) {
        key = [baseKey stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
    } else {
        key = [baseKey stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
    }
    if (!profile[key]) {
        key = baseKey;
    }
    return key;
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
        [self commitModel:model];
    }
}

+ (void)setObjectsFromDictionary:(NSDictionary *)dictionary
                       inProfile:(Profile *)profile
                           model:(ProfileModel *)model {
    [model setObjectsFromDictionary:dictionary inProfile:profile];
    [self commitModel:model];
}

+ (void)commitModel:(ProfileModel *)model {
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
                  KEY_WINDOW_TYPE: PROFILE_BLOCK(windowType),
                  KEY_BRIGHTEN_BOLD_TEXT: PROFILE_BLOCK(brightenBoldText),
                  KEY_BRIGHTEN_BOLD_TEXT COLORS_LIGHT_MODE_SUFFIX: PROFILE_BLOCK(brightenBoldTextLight),
                  KEY_BRIGHTEN_BOLD_TEXT COLORS_DARK_MODE_SUFFIX: PROFILE_BLOCK(brightenBoldTextDark),
                  KEY_TREAT_OPTION_AS_ALT: PROFILE_BLOCK(treatOptionAsAlt),
                  KEY_TIMESTAMPS_STYLE: PROFILE_BLOCK(timestampsStyle),
                  KEY_TIMESTAMPS_VISIBLE: PROFILE_BLOCK(timestampsVisible),
                  KEY_BROWSER_EXTENSIONS_ROOT: PROFILE_BLOCK(browserExtensionsRoot)
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
    NSNumber *legacyDefault = [[iTermUserDefaults userDefaults] objectForKey:@"AntiIdleTimerPeriod"];
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

    // macOS 10.13 has switched to unicode 9 widths. If you're sshing somewhere then you're
    // going to have a bad time. My hope is that this makes people happier on balance.
    // NOTE: IF YOU CHANGE THIS ALSO UPDATE ProfilesTextPreferencseViewController.m's hasDefaultValue closure.
    return @9;
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
    return @(iTermThemedWindowType(number.intValue));
}

+ (id)brightenBoldTextLight:(Profile *)profile {
    NSNumber *number = profile[KEY_BRIGHTEN_BOLD_TEXT COLORS_LIGHT_MODE_SUFFIX];
    if (number) {
        return number;
    }
    // Migration path. This used to be one and the same as "use bold color". If you've never tweaked
    // this setting directly, fall back to the "use bold color" setting.
    return [self objectForKey:KEY_USE_BOLD_COLOR
                    inProfile:profile];
}

+ (id)timestampsStyle:(Profile *)profile {
    id actual = profile[KEY_TIMESTAMPS_STYLE];
    if (actual) {
        return actual;
    }
    NSNumber *fallback = [NSNumber castFrom:profile[KEY_SHOW_TIMESTAMPS]];
    if (!fallback || fallback.unsignedIntegerValue == iTermTimestampsModeOff) {
        return @(iTermTimestampsModeOverlap);
    }
    return fallback;
}

+ (id)browserExtensionsRoot:(Profile *)profile {
    NSString *string = [NSString castFrom:profile[KEY_BROWSER_EXTENSIONS_ROOT]];
    if (string) {
        return string;
    }
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectoryWithoutCreating];
    if (!appSupport) {
        return nil;
    }
    return [appSupport stringByAppendingPathComponent:@"BrowserExtensions"];
}

+ (id)timestampsVisible:(Profile *)profile {
    NSNumber *visibleSetting = [NSNumber castFrom:profile[KEY_TIMESTAMPS_VISIBLE]];
    NSNumber *legacySetting = [NSNumber castFrom:profile[KEY_SHOW_TIMESTAMPS]];

    if (visibleSetting) {
        // Modern code path
        return visibleSetting;
    }
    if (legacySetting) {
        // Migreate legacy setting
        return @(((iTermTimestampsMode)legacySetting.unsignedIntegerValue) != iTermTimestampsModeOff);
    }
    // Default code path
    return @NO;
}

+ (id)treatOptionAsAlt:(Profile *)profile {
    // If the profile has a non-default value, use it.
    if ([NSNumber castFrom:profile[KEY_TREAT_OPTION_AS_ALT]]) {
        return profile[KEY_TREAT_OPTION_AS_ALT];
    }

    // If there was an old setting in advanced prefs, use that. Fall back to the default value.
    NSNumber *number = [NSNumber castFrom:[[iTermUserDefaults userDefaults] objectForKey:@"OptionIsMetaForSpecialChars"]];
    if (number){
        return @(!number.boolValue);
    }

    // Fall back to the default value.
    return [self defaultValueMap][KEY_TREAT_OPTION_AS_ALT];
}

+ (id)brightenBoldTextDark:(Profile *)profile {
    NSNumber *number = profile[KEY_BRIGHTEN_BOLD_TEXT COLORS_DARK_MODE_SUFFIX];
    if (number) {
        return number;
    }
    // Migration path. This used to be one and the same as "use bold color". If you've never tweaked
    // this setting directly, fall back to the "use bold color" setting.
    return [self objectForKey:KEY_USE_BOLD_COLOR inProfile:profile];
}

+ (id)brightenBoldText:(Profile *)profile {
    NSNumber *number = profile[KEY_BRIGHTEN_BOLD_TEXT];
    if (number) {
        return number;
    }
    // Migration path. This used to be one and the same as "use bold color". If you've never tweaked
    // this setting directly, fall back to the "use bold color" setting.
    return [self objectForKey:KEY_USE_BOLD_COLOR inProfile:profile];
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

    // Default to showing session name in tmux profile for backward compatibility with 3.3.0-3.3.2 and
    // earlier (issue 8255).
    NSString *name = profile[KEY_NAME];
    if ([name isEqualToString:@"tmux"]) {
        return @(iTermTitleComponentsSessionName);
    }

    // Respect any existing now-deprecated settings.
    NSNumber *stickyNumber = [[iTermUserDefaults userDefaults] objectForKey:KEY_SYNC_TITLE_DEPRECATED];
    NSNumber *showJobNumber = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyShowJobName_Deprecated];
    NSNumber *showProfileNameNumber = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyShowProfileName_Deprecated];

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

NSString *iTermAmendedColorKey(NSString *baseKey, Profile *profile, BOOL dark) {
    return iTermAmendedColorKey2(baseKey,
                                 [iTermProfilePreferences boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE inProfile:profile],
                                 dark);
}

NSString *iTermAmendedColorKey2(NSString *baseKey, BOOL separate, BOOL dark) {
    if (!separate) {
        return baseKey;
    }
    if (dark) {
        return [baseKey stringByAppendingString:COLORS_DARK_MODE_SUFFIX];
    }
    return [baseKey stringByAppendingString:COLORS_LIGHT_MODE_SUFFIX];
}

