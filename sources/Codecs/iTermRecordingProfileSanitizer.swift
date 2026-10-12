//
//  iTermRecordingProfileSanitizer.swift
//  iTerm2SharedARC
//
//  An Instant Replay (.itr) file embeds a profile, and the file may come from
//  anyone. Keep only the settings that affect how the recording is drawn. Every
//  other key is dropped, so that triggers, key bindings, smart selection actions,
//  semantic history, interpolated strings, logging, and any key added in the
//  future can never be supplied by a recording.
//

import Foundation

@objc(iTermRecordingProfileSanitizer)
class iTermRecordingProfileSanitizer: NSObject {
    // Keys that may also have Light and Dark variants are listed by base name.
    // Color keys are always allowed and are not listed. When you add a profile
    // key, put it here only if it affects drawing and can't run anything, read
    // or write files, or reach the network. Otherwise add it to deniedBaseKeys.
    static let allowedBaseKeys: Set<String> = [
        // Colors and how they are applied
        KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE,
        KEY_USE_BOLD_COLOR,
        KEY_BRIGHTEN_BOLD_TEXT,
        KEY_HARMONIZE_256_COLORS,
        KEY_USE_SELECTED_TEXT_COLOR,
        KEY_USE_UNDERLINE_COLOR,
        KEY_USE_CURSOR_GUIDE,
        KEY_USE_TAB_COLOR,
        KEY_SMART_CURSOR_COLOR,
        KEY_MINIMUM_CONTRAST,
        KEY_FAINT_TEXT_ALPHA,
        KEY_CURSOR_BOOST,
        KEY_HDR_CURSOR,
        KEY_HDR_CURSOR_BRIGHTNESS,
        KEY_USE_ACTIVE_PANE_BORDER,

        // Fonts
        KEY_NORMAL_FONT,
        KEY_NON_ASCII_FONT,
        KEY_USE_NONASCII_FONT,
        KEY_FONT_CONFIG,
        KEY_HORIZONTAL_SPACING,
        KEY_VERTICAL_SPACING,
        KEY_USE_BOLD_FONT,
        KEY_USE_ITALIC_FONT,
        KEY_THIN_STROKES,
        KEY_ASCII_ANTI_ALIASED,
        KEY_NONASCII_ANTI_ALIASED,
        KEY_ASCII_LIGATURES,
        KEY_NON_ASCII_LIGATURES,
        KEY_POWERLINE,

        // Cursor
        KEY_CURSOR_TYPE,
        KEY_BLINKING_CURSOR,
        KEY_CURSOR_SHADOW,
        KEY_CURSOR_HIDDEN_WITHOUT_FOCUS,
        KEY_BLINK_ALLOWED,
        KEY_CURSOR_SMOOTH_SLIDE,
        KEY_CURSOR_SMOOTH_BLINK,
        KEY_CURSOR_BLINK_FADE_IN_DURATION,
        KEY_CURSOR_BLINK_FADE_OUT_DURATION,
        KEY_CURSOR_BLINK_FADE_IN_CURVE,
        KEY_CURSOR_BLINK_FADE_OUT_CURVE,
        KEY_CURSOR_BLINK_VISIBLE_DWELL,
        KEY_CURSOR_BLINK_HIDDEN_DWELL,
        KEY_ANIMATE_MOVEMENT,
        KEY_ANIMATE_MOVEMENT_ONLY_IN_INTERACTIVE_APPS,

        // Transparency
        KEY_TRANSPARENCY,
        KEY_INITIAL_USE_TRANSPARENCY,
        KEY_BLUR,
        KEY_BLUR_RADIUS,
        KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR,

        // Character width and normalization
        KEY_AMBIGUOUS_DOUBLE_WIDTH,
        KEY_UNICODE_NORMALIZATION,
        KEY_UNICODE_VERSION,

        // Marks, timestamps, and other drawing aids
        KEY_SHOW_MARK_INDICATORS,
        KEY_USE_THEME_MARK_COLORS,
        KEY_TIMESTAMPS_STYLE,
        KEY_TIMESTAMPS_VISIBLE,
        KEY_SHOW_OFFSCREEN_COMMANDLINE,
        KEY_SHOW_OFFSCREEN_COMMANDLINE_FOR_CURRENT_COMMAND,
        KEY_ENABLE_PROGRESS_BARS,
        KEY_PROGRESS_BAR_HEIGHT,
        KEY_PROGRESS_BAR_COLOR_SCHEME,
        KEY_REDUCE_FLICKER,

        // Size
        KEY_ROWS,
        KEY_COLUMNS,
        KEY_SCROLLBACK_LINES,
        KEY_UNLIMITED_SCROLLBACK,
    ]

    // Every other profile key, each deliberately excluded. This list is not used
    // to filter (anything not allowed is dropped); it exists so a test can fail
    // when a new profile key is added without deciding whether a recording may
    // set it.
    static let deniedBaseKeys: Set<String> = [
        // Run commands, send text, or evaluate expressions
        KEY_TRIGGERS,
        KEY_TRIGGERS_USE_INTERPOLATED_STRINGS,
        KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS,
        KEY_BINDINGS,
        KEY_KEYBOARD_MAP,
        KEY_TOUCHBAR_MAP,
        KEY_SMART_SELECTION_RULES,
        KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS,
        KEY_SEMANTIC_HISTORY,
        KEY_CUSTOM_COMMAND,
        KEY_COMMAND_LINE,
        KEY_RUN_COMMAND_IN_LOGIN_SHELL,
        KEY_INITIAL_TEXT,
        KEY_INITIAL_URL,
        KEY_SEND_CODE_WHEN_IDLE,
        KEY_IDLE_CODE,
        KEY_IDLE_PERIOD,
        KEY_ANSWERBACK_STRING,
        KEY_BADGE_FORMAT,
        KEY_SUBTITLE,
        KEY_TITLE_COMPONENTS,
        KEY_TITLE_FUNC,
        KEY_USE_CUSTOM_TAB_TITLE,
        KEY_CUSTOM_TAB_TITLE,
        KEY_USE_CUSTOM_WINDOW_TITLE,
        KEY_CUSTOM_WINDOW_TITLE,
        KEY_SHOW_STATUS_BAR,
        KEY_STATUS_BAR_LAYOUT,
        KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY,
        KEY_SSH_CONFIG,
        KEY_BOUND_HOSTS,
        KEY_PREVENT_APS,
        KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY,


        // Read or write files, or touch the network
        KEY_AUTOLOG,
        KEY_LOGDIR,
        KEY_LOG_FILENAME_FORMAT,
        KEY_LOGGING_STYLE,
        KEY_ARCHIVE,
        KEY_ARCHIVEDIR,
        KEY_CUSTOM_DIRECTORY,
        KEY_WORKING_DIRECTORY,
        KEY_AWDS_WIN_OPTION,
        KEY_AWDS_WIN_DIRECTORY,
        KEY_AWDS_TAB_OPTION,
        KEY_AWDS_TAB_DIRECTORY,
        KEY_AWDS_PANE_OPTION,
        KEY_AWDS_PANE_DIRECTORY,
        KEY_BACKGROUND_IMAGE_LOCATION,
        KEY_BACKGROUND_IMAGE_FOLDER_LOCATION,
        KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL,
        KEY_BACKGROUND_IMAGE_MODE,
        KEY_BACKGROUND_IMAGE_SOURCE_MODE,
        KEY_BLEND,
        KEY_ICON,
        KEY_ICON_PATH,
        KEY_BELL_SOUND,
        KEY_BROWSER_ZOOM,
        KEY_BROWSER_DEV_NULL,
        KEY_BROWSER_EXTENSIONS_ROOT,
        KEY_BROWSER_EXTENSION_ACTIVE_IDS,


        // Identity of the profile
        KEY_GUID,
        KEY_ORIGINAL_GUID,
        KEY_NAME,
        KEY_TAGS,
        KEY_SHORTCUT,
        KEY_PROFILE_TYPE_PHONY,
        KEY_DYNAMIC_PROFILE,
        KEY_DYNAMIC_PROFILE_FILENAME,
        KEY_DYNAMIC_PROFILE_PARENT_GUID,
        KEY_DYNAMIC_PROFILE_PARENT_NAME,
        KEY_DYNAMIC_PROFILE_REWRITABLE,


        // Window placement and behavior
        KEY_WINDOW_TYPE,
        KEY_SCREEN,
        KEY_SPACE,
        KEY_WIDTH,
        KEY_HEIGHT,
        KEY_WIDTH_PERCENTAGE,
        KEY_HEIGHT_PERCENTAGE,
        KEY_DISABLE_WINDOW_RESIZING,
        KEY_DISABLE_UNFOCUSED_WINDOW_RESIZING,
        KEY_LOCK_WINDOW_SIZE_AUTOMATICALLY,
        KEY_HIDE_AFTER_OPENING,
        KEY_OPEN_TOOLBELT,
        KEY_PREVENT_TAB,
        KEY_DEFAULT_PANE_LOCKED,
        KEY_COMPOSER_TOP_OFFSET,
        KEY_SCROLLBACK_WITH_STATUS_BAR,
        KEY_HAS_HOTKEY,
        KEY_HOTKEY_KEY_CODE,
        KEY_HOTKEY_CHARACTERS,
        KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS,
        KEY_HOTKEY_MODIFIER_FLAGS,
        KEY_HOTKEY_AUTOHIDE,
        KEY_HOTKEY_REOPEN_ON_ACTIVATION,
        KEY_HOTKEY_ANIMATE,
        KEY_HOTKEY_FLOAT,
        KEY_HOTKEY_DOCK_CLICK_ACTION,
        KEY_HOTKEY_ACTIVATE_WITH_MODIFIER,
        KEY_HOTKEY_MODIFIER_ACTIVATION,
        KEY_HOTKEY_ALTERNATE_SHORTCUTS,
        KEY_SESSION_HOTKEY,


        // Only matter for a live session with a running program
        KEY_CHARACTER_ENCODING,
        KEY_TERMINAL_TYPE,
        KEY_SET_LOCALE_VARS,
        KEY_CUSTOM_LOCALE,
        KEY_XTERM_MOUSE_REPORTING,
        KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL,
        KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS,
        KEY_RESTRICT_MOUSE_REPORTING_TO_ALTERNATE_SCREEN_MODE,
        KEY_ALLOW_ALTERNATE_MOUSE_SCROLL,
        KEY_AUTOMATICALLY_ENABLE_ALTERNATE_MOUSE_SCROLL,
        KEY_RESTRICT_ALTERNATE_MOUSE_SCROLL_TO_VERTICAL,
        KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED,
        KEY_ALLOW_TITLE_REPORTING,
        KEY_ALLOW_TITLE_SETTING,
        KEY_ALLOW_PASTE_BRACKETING,
        KEY_ALLOW_CHANGE_CURSOR_BLINK,
        KEY_ALLOW_MODIFY_OTHER_KEYS,
        KEY_APPLICATION_KEYPAD_ALLOWED,
        KEY_USE_LIBTICKIT_PROTOCOL,
        KEY_DISABLE_SMCUP_RMCUP,
        KEY_DISABLE_PRINTING,
        KEY_SCROLLBACK_IN_ALTERNATE_SCREEN,
        KEY_TMUX_NEWLINE,
        KEY_TMUX_PANE_TITLE,
        KEY_PLACE_PROMPT_AT_FIRST_COLUMN,
        KEY_PROMPT_PATH_CLICK_OPENS_NAVIGATOR,
        KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS,
        KEY_BUFFER_BY_DEFAULT,
        KEY_SNIPPETS_FILTER,
        KEY_OPTION_KEY_SENDS,
        KEY_RIGHT_OPTION_KEY_SENDS,
        KEY_LEFT_OPTION_KEY_CHANGEABLE,
        KEY_RIGHT_OPTION_KEY_CHANGEABLE,
        KEY_TREAT_OPTION_AS_ALT,
        KEY_LEFT_CONTROL,
        KEY_RIGHT_CONTROL,
        KEY_LEFT_COMMAND,
        KEY_RIGHT_COMMAND,
        KEY_FUNCTION,
        KEY_SESSION_END_ACTION,
        KEY_PROMPT_CLOSE,
        KEY_JOBS,
        KEY_UNDO_TIMEOUT,
        KEY_PREVENT_SLEEP,
        KEY_INSTANT_REPLAY,
        KEY_SILENCE_BELL,
        KEY_VISUAL_BELL,
        KEY_FLASHING_BELL,
        KEY_BOOKMARK_USER_NOTIFICATIONS,
        KEY_SEND_BELL_ALERT,
        KEY_SEND_IDLE_ALERT,
        KEY_SEND_NEW_OUTPUT_ALERT,
        KEY_SEND_SESSION_ENDED_ALERT,
        KEY_SEND_TERMINAL_GENERATED_ALERT,
        KEY_SEND_ALERTS_TO_COMPANION,
        KEY_SUPPRESS_ALERTS_IN_ACTIVE_SESSION,
    ]

    static func keyIsAllowed(_ key: String) -> Bool {
        if iTermProfilePreferences.keyIsColor(key) {
            return true
        }
        return allowedBaseKeys.contains(iTermProfilePreferences.baseColorKey(forKey: key))
    }

    // Deprecated keys that still affect drawing have no validators, so convert
    // them to their replacements instead of allowing them.
    private static func migrateDeprecatedKeys(from untrusted: [AnyHashable: Any],
                                              into result: inout [String: Any]) {
        if result[KEY_UNICODE_NORMALIZATION] == nil,
           let hfsPlus = untrusted[KEY_USE_HFS_PLUS_MAPPING] as? NSNumber {
            let form: iTermUnicodeNormalization = hfsPlus.boolValue ? .hfsPlus : .none
            result[KEY_UNICODE_NORMALIZATION] = Int(form.rawValue)
        }
        if result[KEY_USE_BOLD_FONT] == nil,
           let disableBold = untrusted[KEY_DISABLE_BOLD] as? NSNumber {
            result[KEY_USE_BOLD_FONT] = !disableBold.boolValue
        }
    }

    @objc(sanitizedProfile:)
    static func sanitizedProfile(_ untrusted: [AnyHashable: Any]) -> [String: Any] {
        var result = [String: Any]()
        for (anyKey, value) in untrusted {
            guard let key = anyKey as? String else {
                continue
            }
            guard keyIsAllowed(key) else {
                DLog("Drop key \(key) from recording profile")
                continue
            }
            guard iTermProfilePreferences.valueIsLegal(value, forKey: key) else {
                DLog("Drop key \(key) from recording profile because its value \(value) is illegal")
                continue
            }
            result[key] = value
        }
        migrateDeprecatedKeys(from: untrusted, into: &result)
        // Make sure the GUID doesn't match an existing one.
        result[KEY_GUID] = UUID().uuidString
        return result
    }
}
