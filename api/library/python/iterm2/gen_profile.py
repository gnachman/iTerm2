#!/usr/bin/env python3

# These have light/dark variants
base_colors_schema = [
    ("foreground_color",
     "Color",
     "the foreground color.",
     None,
     "Foreground Color"),

    ("background_color",
     "Color",
     "the background color.",
     None,
     "Background Color"),

    ("bold_color",
     "Color",
     "the bold text color.",
     None,
     "Bold Color"),

    ("use_bright_bold",
     "bool",
     " how bold text is rendered.",
     """
     This function is deprecated because its behavior changed in
     iTerm2 version 3.3.7.

     Pre-3.3.7, when enabled:
     * Use the profile-specified bold color for default-colored
       bold text.
     * Dark ANSI colors get replaced with their light counterparts
       for bold text.

     In 3.3.7 and later:
     * Use the profile-specified bold color for default-colored
       bold text.

     Use `use_bold_color` and `brighten_bold_text` in 3.3.7 and
     later instead of this method.
     """,
     "Use Bright Bold"),

    ("use_bold_color",
     "bool",
     "whether the profile-specified bold color is used for default-colored bold text.",
     """
     Note: In versions of iTerm2 prior to 3.3.7, this behaves like
     {{accessor}}use_bright_bold().""",
     "Use Bright Bold"),

    ("brighten_bold_text",
     "bool",
     "whether Dark ANSI colors get replaced with their light counterparts for bold text.",
     "This is only supported in iTerm2 version 3.3.7 and later.",
     "Brighten Bold Text"),

    ("link_color",
     "Color",
     "the link color.",
     None,
     "Link Color"),

    ("selection_color",
     "Color",
     "the selection background color.",
     None,
     "Selection Color"),

    ("selected_text_color",
     "Color",
     "the selection text color.",
     None,
     "Selected Text Color"),

    ("cursor_color",
     "Color",
     "the cursor color.",
     None,
     "Cursor Color"),

    ("cursor_text_color",
     "Color",
     "the cursor text color.",
     None,
     "Cursor Text Color"),

    ("ansi_0_color",
     "Color",
     "the ANSI 0 color.",
     None,
     "Ansi 0 Color"),

    ("ansi_1_color",
     "Color",
     "the ANSI 1 color.",
     None,
     "Ansi 1 Color"),

    ("ansi_2_color",
     "Color",
     "the ANSI 2 color.",
     None,
     "Ansi 2 Color"),

    ("ansi_3_color",
     "Color",
     "the ANSI 3 color.",
     None,
     "Ansi 3 Color"),

    ("ansi_4_color",
     "Color",
     "the ANSI 4 color.",
     None,
     "Ansi 4 Color"),

    ("ansi_5_color",
     "Color",
     "the ANSI 5 color.",
     None,
     "Ansi 5 Color"),

    ("ansi_6_color",
     "Color",
     "the ANSI 6 color.",
     None,
     "Ansi 6 Color"),

    ("ansi_7_color",
     "Color",
     "the ANSI 7 color.",
     None,
     "Ansi 7 Color"),

    ("ansi_8_color",
     "Color",
     "the ANSI 8 color.",
     None,
     "Ansi 8 Color"),

    ("ansi_9_color",
     "Color",
     "the ANSI 9 color.",
     None,
     "Ansi 9 Color"),

    ("ansi_10_color",
     "Color",
     "the ANSI 10 color.",
     None,
     "Ansi 10 Color"),

    ("ansi_11_color",
     "Color",
     "the ANSI 11 color.",
     None,
     "Ansi 11 Color"),

    ("ansi_12_color",
     "Color",
     "the ANSI 12 color.",
     None,
     "Ansi 12 Color"),

    ("ansi_13_color",
     "Color",
     "the ANSI 13 color.",
     None,
     "Ansi 13 Color"),

    ("ansi_14_color",
     "Color",
     "the ANSI 14 color.",
     None,
     "Ansi 14 Color"),

    ("ansi_15_color",
     "Color",
     "the ANSI 15 color.",
     None,
     "Ansi 15 Color"),

    ("smart_cursor_color",
     "bool",
     "whether to use smart cursor color. This only applies to box cursors.",
     None,
     "Smart Cursor Color"),

    ("minimum_contrast",
     "float",
     "the minimum contrast, in 0 to 1.",
     None,
     "Minimum Contrast"),

    ("tab_color",
     "Color",
     "the tab color.",
     None,
     "Tab Color"),

    ("use_tab_color",
     "bool",
     "whether the tab color should be used.",
     None,
     "Use Tab Color"),

    ("underline_color",
     "Color | None",
     "the underline color.",
     None,
     "Underline Color"),

    ("use_underline_color",
     "bool",
     "whether to use the specified underline color.",
     None,
     "Use Underline Color"),

    ("cursor_boost",
     "float",
     "the cursor boost level, in 0 to 1.",
     None,
     "Cursor Boost"),

    ("use_cursor_guide",
     "bool",
     "whether the cursor guide should be used.",
     None,
     "Use Cursor Guide"),

    ("cursor_guide_color",
     "Color",
     "the cursor guide color. The alpha value is respected.",
     None,
     "Cursor Guide Color"),

    ("badge_color",
     "Color",
     "the badge color. The alpha value is respected.",
     None,
     "Badge Color"),

    ("match_color",
     "Color",
     "the highlight color for search matches.",
     None,
     "Match Background Color"),

    ("ime_cursor_color",
     "Color",
     "the cursor color while composing text with an input method.",
     None,
     "IME Cursor Color"),

    ("use_selected_text_color",
     "bool",
     "whether selected text is drawn in the selected text color.",
     None,
     "Use Selected Text Color"),

    ("active_pane_border_color",
     "Color",
     "the color of the border around the active pane.",
     "This is used only when use_active_pane_border is True.",
     "Active Pane Border Color"),

    ("use_active_pane_border",
     "bool",
     "whether to draw a border around the active pane.",
     None,
     "Use Active Pane Border"),

    ("faint_text_alpha",
     "float",
     "the opacity of faint text.",
     "The value is between 0 and 1.",
     "Faint Text Alpha"),

    ("harmonize_256_colors",
     "bool",
     "whether the 256-color palette is adjusted to match the ANSI colors.",
     None,
     "Harmonize 256 Colors"),

    ("hdr_cursor",
     "bool",
     "whether the cursor is drawn brighter than white on HDR displays.",
     None,
     "HDR Cursor"),

    ("hdr_cursor_brightness",
     "float",
     "the brightness of the HDR cursor.",
     "The value is a multiple of reference white, at most 16.",
     "HDR Cursor Brightness"),

    ("hdr_text",
     "bool",
     "whether the focused pane's text is drawn brighter than white on HDR displays.",
     None,
     "HDR Text"),

    ("hdr_text_brightness",
     "float",
     "the brightness of HDR text.",
     "The value is a multiple of reference white, from 1.5 to 16.",
     "HDR Text Brightness"),
]

def set_mode(tuple, mode):
    temp = list(tuple)
    if mode:
        temp[0] = temp[0] + "_" + mode.lower()
        temp[2] = temp[2] + f' This affects the {mode.lower()}-mode variant when separate light/dark mode colors are enabled.'
        temp[4] = temp[4] + f' ({mode})'
    else:
        temp[2] = temp[2] + " This is used only when separate light/dark mode colors are not enabled."
    return temp

def flatmap(f, l):
    result = []
    for item in l:
        result.extend(f(item))
    return result

colors_schema = flatmap(lambda x: [set_mode(x, None), set_mode(x, "Light"), set_mode(x, "Dark")], base_colors_schema)

# (name, type, summary, detailed description, key)
schema = [
    ("use_separate_colors_for_light_and_dark_mode",
     "bool",
     "whether to use separate colors for light and dark mode.",
     """
     When this is enabled, use [set_]xxx_color_light and
     set_[xxx_]color_dark instead of [set_]xxx_color.

     :param value: Whether to use separate colors for light and dark mode.
     """,
    "Use Separate Colors for Light and Dark Mode"),
] + colors_schema + [
    ("name",
     "str",
     "the name.",
     None,
     "Name"),

    ("badge_text",
     "str",
     "the badge text.",
     None,
     "Badge Text"),

    ("subtitle",
     "str",
     "the subtitle, an interpolated string.",
     None,
     "Subtitle"),

    ("answerback_string",
     "str",
     "the answerback string.",
     None,
     "Answerback String"),

    ("blinking_cursor",
     "bool",
     "whether the cursor blinks.",
     None,
     "Blinking Cursor"),

    ("cursor_shadow",
     "bool",
     "whether the vertical bar and horizontal line cursor have a shadow.",
     None,
     "Cursor Shadow"),

    ("use_bold_font",
     "bool",
     "whether to use the bold variant of the font for bold text.",
     None,
     "Use Bold Font"),

    ("ascii_ligatures",
     "bool",
     "whether ligatures should be used for ASCII text.",
     None,
     "ASCII Ligatures"),

    ("non_ascii_ligatures",
     "bool",
     "whether ligatures should be used for non-ASCII text.",
     None,
     "Non-ASCII Ligatures"),

    ("blink_allowed",
     "bool",
     "whether blinking text is allowed.",
     None,
     "Blink Allowed"),

    ("use_italic_font",
     "bool",
     "whether italic text is allowed.",
     None,
     "Use Italic Font"),

    ("ambiguous_double_width",
     "bool",
     "whether ambiguous-width text should be treated as double-width.",
     None,
     "Ambiguous Double Width"),

    ("horizontal_spacing",
     "float",
     "the fraction of horizontal spacing. Must be non-negative.",
     None,
     "Horizontal Spacing"),

    ("vertical_spacing",
     "float",
     "the fraction of vertical spacing. Must be non-negative.",
     None,
     "Vertical Spacing"),

    ("use_non_ascii_font",
     "bool",
     "whether to use a different font for non-ASCII text.",
     None,
     "Use Non-ASCII Font"),

    ("transparency",
     "float",
     "the level of transparency.",
     "The value is between 0 and 1.",
     "Transparency"),

    ("blur",
     "bool",
     "whether background blur should be enabled.",
     None,
     "Blur"),

    ("blur_radius",
     "float",
     "the blur radius (how blurry). Requires blur to be enabled.",
     "The value is between 0 and 30.",
     "Blur Radius"),

    ("background_image_mode",
     "BackgroundImageMode",
     "how the background image is drawn.",
     None,
     "Background Image Mode"),

    ("blend",
     "float",
     "how much the default background color gets blended with the background image.",
     """The value is in 0 to 1.

     .. seealso:: Example ":ref:`blending_example`""",
     "Blend"),

    ("sync_title",
     "bool",
     "whether the profile name stays in the tab title, even if changed by an escape sequence.",
     None,
     "Sync Title"),

    ("use_built_in_powerline_glyphs",
     "bool",
     "whether powerline glyphs should be drawn by iTerm2 or left to the font.",
     None,
     "Draw Powerline Glyphs"),

    ("disable_window_resizing",
     "bool",
     "whether the terminal can resize the window with an escape sequence.",
     None,
     "Disable Window Resizing"),

    ("allow_change_cursor_blink",
     "bool",
     "whether the terminal can change the cursor blink setting with an escape sequence.",
     None,
     "Allow Change Cursor Blink"),

    ("only_the_default_bg_color_uses_transparency",
     "bool",
     "whether window transparency shows through non-default background colors.",
      None,
     "Only The Default BG Color Uses Transparency"),

    ("ascii_anti_aliased",
     "bool",
     "whether ASCII text is anti-aliased.",
     None,
     "ASCII Anti Aliased"),

    ("non_ascii_anti_aliased",
     "bool",
     "whether non-ASCII text is anti-aliased.",
     None,
     "Non-ASCII Anti Aliased"),

    ("scrollback_lines",
     "int",
     "the number of scrollback lines.",
     "Value must be at least 0.",
     "Scrollback Lines"),

    ("unlimited_scrollback",
     "bool",
     "whether the scrollback buffer's length is unlimited.",
     None,
     "Unlimited Scrollback"),

    ("scrollback_with_status_bar",
     "bool",
     "whether text gets appended to scrollback when there is an app status bar",
     None,
     "Scrollback With Status Bar"),

    ("scrollback_in_alternate_screen",
     "bool",
     "whether text gets appended to scrollback in alternate screen mode.",
     None,
     "Scrollback in Alternate Screen"),

    ("mouse_reporting",
     "bool",
     "whether mouse reporting is allowed",
     None,
     "Mouse Reporting"),

    ("mouse_reporting_allow_mouse_wheel",
     "bool",
     "whether mouse reporting reports the mouse wheel's movements.",
     None,
     "Mouse Reporting allow mouse wheel"),

    ("allow_title_reporting",
     "bool",
     "whether the session title can be reported",
     None,
     "Allow Title Reporting"),

    ("allow_title_setting",
     "bool",
     "whether the session title can be changed by escape sequence",
     None,
     "Allow Title Setting"),

    ("disable_printing",
     "bool",
     "whether printing by escape sequence is disabled.",
     None,
     "Disable Printing"),

    ("disable_smcup_rmcup",
     "bool",
     "whether alternate screen mode is disabled",
     None,
     "Disable Smcup Rmcup"),

    ("silence_bell",
     "bool",
     "whether the bell makes noise.",
     None,
     "Silence Bell"),

    ("bm_growl",
     "bool",
     "whether notifications should be shown.",
     None,
     "BM Growl"),

    ("send_bell_alert",
     "bool",
     "whether notifications should be shown for the bell ringing",
     None,
     "Send Bell Alert"),

    ("send_idle_alert",
     "bool",
     "whether notifications should be shown for becoming idle",
     None,
     "Send Idle Alert"),

    ("send_new_output_alert",
     "bool",
     "whether notifications should be shown for new output",
     None,
     "Send New Output Alert"),

    ("send_session_ended_alert",
     "bool",
     "whether notifications should be shown for a session ending",
     None,
     "Send Session Ended Alert"),

    ("send_terminal_generated_alerts",
     "bool",
     "whether notifications should be shown for escape-sequence originated notifications",
     None,
     "Send Terminal Generated Alerts"),

    ("flashing_bell",
     "bool",
     "whether the bell should flash the screen",
     None,
     "Flashing Bell"),

    ("visual_bell",
     "bool",
     "whether a bell should be shown when the bell rings",
     None,
     "Visual Bell"),

    ("close_sessions_on_end",
     "bool",
     "whether the session should close when it ends.",
     None,
     "Close Sessions On End"),

    ("prompt_before_closing",
     "bool",
     "whether the session should prompt before closing.",
     None,
     "Prompt Before Closing 2"),

    ("session_close_undo_timeout",
     "float",
     "the amount of time you can undo closing a session",
     "The value is at least 0.",
     "Session Close Undo Timeout"),

    ("reduce_flicker",
     "bool",
     "whether the flicker fixer is on.",
     None,
     "Reduce Flicker"),

    ("send_code_when_idle",
     "bool",
     "whether to send a code when idle",
     None,
     "Send Code When Idle"),

    ("application_keypad_allowed",
     "bool",
     "whether the terminal may be placed in application keypad mode",
     None,
     "Application Keypad Allowed"),

    ("place_prompt_at_first_column",
     "bool",
     "whether the prompt should always begin at the first column (requires shell integration)",
     None,
     "Place Prompt at First Column"),

    ("show_mark_indicators",
     "bool",
     "whether mark indicators should be visible",
     None,
     "Show Mark Indicators"),

    ("idle_code",
     "int",
     "the ASCII code to send on idle",
     "Value is an int in 0 through 255.",
     "Idle Code"),

    ("idle_period",
     "float",
     "how often to send a code when idle",
     "Value is a float at least 0",
     "Idle Period"),

    ("unicode_version",
     "bool",
     "the unicode version for wcwidth",
     None,
     "Unicode Version"),

    ("cursor_type",
     "CursorType",
     "the cursor type",
     None,
     "Cursor Type"),

    ("thin_strokes",
     "ThinStrokes",
     "whether thin strokes are used.",
     None,
     "Thin Strokes"),

    ("unicode_normalization",
     "UnicodeNormalization",
     "the unicode normalization form to use",
     None,
     "Unicode Normalization"),

    ("character_encoding",
     "CharacterEncoding",
     "the character encoding",
     None,
     "Character Encoding"),

    ("left_option_key_sends",
     "OptionKeySends",
     "the behavior of the left option key.",
     None,
     "Option Key Sends"),

    ("right_option_key_sends",
     "OptionKeySends",
     "the behavior of the right option key.",
     None,
     "Right Option Key Sends"),

    ("triggers",
     "list[dict[str, Any]]",
     "the triggers.",
     "Value is an encoded trigger. Use iterm2.decode_trigger to convert from an encoded trigger to an object. Trigger objects can be encoded using the encode property.",
     "Triggers"),

    ("smart_selection_rules",
     "list[dict[str, Any]]",
     "the smart selection rules.",
     "The value is a list of dicts of smart selection rules (currently undocumented)",
     "Smart Selection Rules"),

    ("smart_selection_actions_use_interpolated_strings",
     "bool",
     "whether smart selection action parameters are interpolated strings.",
     "Should smart selection actions' parameters be treated as interpolated strings? If false, use the backward-compatibility syntax.",
     "Smart Selection Actions Use Interpolated Strings"),

    ("semantic_history",
     "dict[str, Any]",
     "the semantic history prefs.",
     None,
     "Semantic History"),

    ("automatic_profile_switching_rules",
     "list[str]",
     "the automatic profile switching rules.",
     "Value is a list of strings, each giving a rule.",
     "Bound Hosts"),

    ("advanced_working_directory_window_setting",
     "InitialWorkingDirectory",
     "the advanced working directory window setting.",
     "Value excludes Advanced.",
     "AWDS Window Option"),

    ("advanced_working_directory_window_directory",
     "str",
     "the advanced working directory window directory.",
     None,
     "AWDS Window Directory"),

    ("advanced_working_directory_tab_setting",
     "InitialWorkingDirectory",
     "the advanced working directory tab setting.",
     "Value excludes Advanced.",
     "AWDS Tab Option"),

    ("advanced_working_directory_tab_directory",
     "str",
     "the advanced working directory tab directory.",
     None,
     "AWDS Tab Directory"),

    ("advanced_working_directory_pane_setting",
     "InitialWorkingDirectory",
     "the advanced working directory pane setting.",
     "Value excludes Advanced.",
     "AWDS Pane Option"),

    ("advanced_working_directory_pane_directory",
     "str",
     "the advanced working directory pane directory.",
     None,
     "AWDS Pane Directory"),

    ("normal_font",
     "str",
     "the normal font.",
     """
     The normal font is used for either ASCII or all characters depending on
     whether a separate font is used for non-ascii. The value is a font's
     name and size as a string.

     .. seealso::
       * Example ":ref:`increase_font_size_example`"
     """,
     "Normal Font"),

    ("non_ascii_font",
     "str",
     "the non-ASCII font.",
     """
     This is used for non-ASCII characters if use_non_ascii_font is enabled.
     The value is the font name and size as a string.
     """,
     "Non Ascii Font"),

    ("background_image_location",
     "str",
     "the path to the background image.",
     None,
     "Background Image Location"),


    ("key_mappings",
     "dict[str, Any]",
     "the keyboard shortcuts.",
     "The value is a Dictionary mapping keystroke to action. You can convert between the values in this dictionary and a :class:`~iterm2.KeyBinding` using `iterm2.decode_key_binding`",
     "Keyboard Map"),

    ("touchbar_mappings",
     "dict[str, Any]",
     "the touchbar actions.",
     "The value is a Dictionary mapping touch bar item to action",
     "Touch Bar Map"),

    ("use_custom_command",
     "str",
     "whether to use a custom command when the session is created.",
     "The value is the string Yes or No",
     "Custom Command"),

    ("command",
     "str",
     "the command to run when the session starts.",
     "The value is a string giving the command to run",
     "Command"),

    ("initial_directory_mode",
     "InitialWorkingDirectory",
     "whether to use a custom (not home) initial working directory.",
     None,
     "Custom Directory"),

    ("custom_directory",
     "str",
     "the initial working directory.",
     """
     The initial_directory_mode must be set to
     `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
     take effect.
     """,
     "Working Directory"),

    ("icon_mode",
     "IconMode",
     "the icon mode.",
     None,
     "Icon"),

    ("custom_icon_path",
     "str",
     "the path of the custom icon.",
     "The `icon_mode` must be set to `CUSTOM`.",
     "Custom Icon Path"),

    ("badge_top_margin",
     "int",
     "the top margin of the badge.",
     "The value is in points.",
     "Badge Top Margin"),

    ("badge_right_margin",
     "int",
     "the right margin of the badge.",
     "The value is in points.",
     "Badge Right Margin"),

    ("badge_max_width",
     "int",
     "the max width of the badge.",
     "The value is in points.",
     "Badge Max Width"),

    ("badge_max_height",
     "int",
     "the max height of the badge.",
     "The value is in points.",
     "Badge Max Height"),

    ("badge_font",
     "str",
     "the font of the badge.",
     """The font name is a string like "Helvetica".""",
     "Badge Font"),

    ("use_custom_window_title",
     "bool",
     "whether the custom window title is used.",
     "Should the custom window title in the profile be used?",
     "Use Custom Window Title"),

    # title_components and title_function are special

    ("custom_window_title",
     "str | None",
     "the custom window title.",
     """
     This will only be used if use_custom_window_title is True.
     The value is an interpolated string.
     """,
     "Custom Window Title"),

    ("use_transparency_initially",
     "bool",
     "whether a window created with this profile respect the transparency setting.",
     """
     If True, use transparency; if False, force the window to
     be opaque (but it can be toggled with View > Use Transparency).
     """,
     "Initial Use Transparency"),

    ("status_bar_enabled",
     "bool",
     "whether the status bar be enabled.",
     "If True, the status bar will be shown.",
     "Show Status Bar"),

    ("use_csi_u",
     "bool",
     "whether to report keystrokes with CSI u protocol.",
     "If True, CSI u will be enabled.",
     "Use libtickit protocol"),

    ("triggers_use_interpolated_strings",
     "bool",
     "whether trigger parameters should be interpreted as interpolated strings.",
     None,
     "Triggers Use Interpolated Strings"),

    ("left_option_key_changeable",
     "bool",
     "whether apps should be able to change the left option key to send esc+.",
     "The values gives whether it should be allowed.",
     "Left Option Key Changeable"),

    ("right_option_key_changeable",
     "bool",
     "whether apps should be able to change the right option key to send esc+.",
     "The values gives whether it should be allowed.",
     "Right Option Key Changeable"),

    ("open_password_manager_automatically",
     "bool",
     "if the password manager should open automatically.",
     "The values gives whether it should open automatically.",
     "Open Password Manager Automatically"),

    ("tags",
     "list[str]",
     "the tags used to organize profiles.",
     "Set it to an empty list to remove all tags. The getter returns None or an empty list when the profile has no tags.",
     "Tags"),

    ("shortcut",
     "str",
     "the keyboard shortcut that opens this profile.",
     "The value is a single uppercase letter or digit that opens the profile when pressed with Control and Command. Set it to an empty string to remove the shortcut. The getter returns None or an empty string when there is no shortcut. Give each shortcut to at most one profile.",
     "Shortcut"),

    ("initial_text",
     "str",
     "the text to send to the session after it starts.",
     "The value is an interpolated string.",
     "Initial Text"),

    ("run_command_in_login_shell",
     "bool",
     "whether a custom command runs inside the user's login shell.",
     None,
     "Run Command In Login Shell"),

    ("load_shell_integration_automatically",
     "bool",
     "whether shell integration is loaded automatically.",
     None,
     "Load Shell Integration Automatically"),

    ("snippets_filter",
     "list[str]",
     "the snippet tags available to sessions with this profile.",
     "An empty list makes all snippets available.",
     "Snippets Filter"),

    ("cursor_hidden_without_focus",
     "bool",
     "whether the cursor is hidden when the session does not have keyboard focus.",
     None,
     "Cursor Hidden When Unfocused"),

    ("animate_movement",
     "bool",
     "whether cursor movement is animated.",
     None,
     "Animate Movement"),

    ("animate_movement_only_in_interactive_apps",
     "bool",
     "whether cursor movement is animated only in interactive apps.",
     "This is used only when animate_movement is True.",
     "Animate Movement Only in Interactive Apps"),

    ("cursor_smooth_slide",
     "bool",
     "whether the cursor slides smoothly between positions.",
     None,
     "Cursor Smooth Slide"),

    ("cursor_smooth_blink",
     "bool",
     "whether a blinking cursor fades smoothly instead of switching on and off.",
     None,
     "Cursor Smooth Blink"),

    ("cursor_blink_fade_in_duration",
     "float",
     "how long, in seconds, a smoothly blinking cursor takes to fade in.",
     None,
     "Cursor Blink Fade In Duration"),

    ("cursor_blink_fade_out_duration",
     "float",
     "how long, in seconds, a smoothly blinking cursor takes to fade out.",
     None,
     "Cursor Blink Fade Out Duration"),

    ("cursor_blink_fade_in_curve",
     "CursorBlinkFadeCurve",
     "the easing curve for a smoothly blinking cursor fading in.",
     None,
     "Cursor Blink Fade In Curve"),

    ("cursor_blink_fade_out_curve",
     "CursorBlinkFadeCurve",
     "the easing curve for a smoothly blinking cursor fading out.",
     None,
     "Cursor Blink Fade Out Curve"),

    ("cursor_blink_visible_dwell",
     "float",
     "how long, in seconds, a smoothly blinking cursor stays fully visible.",
     None,
     "Cursor Blink Visible Dwell"),

    ("cursor_blink_hidden_dwell",
     "float",
     "how long, in seconds, a smoothly blinking cursor stays fully hidden.",
     None,
     "Cursor Blink Hidden Dwell"),

    ("use_theme_mark_colors",
     "bool",
     "whether mark indicators use colors from the ANSI palette.",
     None,
     "Use Theme Mark Colors"),

    ("background_image_source_mode",
     "BackgroundImageSourceMode",
     "where the background image comes from.",
     None,
     "Background Image Source Mode"),

    ("background_image_folder_location",
     "str",
     "the folder of background images to rotate through.",
     "This is used only when background_image_source_mode is FOLDER_ROTATION.",
     "Background Image Folder Location"),

    ("background_image_folder_interval",
     "float",
     "how often, in seconds, to change the background image when rotating through a folder.",
     None,
     "Background Image Folder Interval"),

    ("window_type",
     "WindowType",
     "the style of window to open.",
     None,
     "Window Type"),

    ("columns",
     "int",
     "the initial number of columns.",
     None,
     "Columns"),

    ("rows",
     "int",
     "the initial number of rows.",
     None,
     "Rows"),

    ("width_percentage",
     "float",
     "the window's width as a percentage of the screen width.",
     "Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR, COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR, TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a non-negative value switches the window from cell-based to screen-percentage sizing, even for a normal window. A negative value means size by columns instead. If the profile has no value, the window is sized by columns, except that top and bottom percentage windows span the full screen width. The getter still returns the default of 100 in that case.",
     "Width Percentage"),

    ("height_percentage",
     "float",
     "the window's height as a percentage of the screen height.",
     "Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR, COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR, TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a non-negative value switches the window from cell-based to screen-percentage sizing, even for a normal window. A negative value means size by rows instead. If the profile has no value, the window is sized by rows, except that left and right percentage windows span the full screen height. The getter still returns the default of 100 in that case.",
     "Height Percentage"),

    ("screen",
     "int",
     "the screen on which new windows open.",
     "-1 means no preference, -2 means the screen with the pointer, 0 is the main screen, and higher numbers are other screens.",
     "Screen"),

    ("space",
     "int",
     "the Space in which new windows open.",
     "0 means the current Space, -1 means all Spaces, and 1 through 9 are specific Spaces.",
     "Space"),

    ("use_custom_tab_title",
     "bool",
     "whether the custom tab title is used.",
     None,
     "Use Custom Tab Title"),

    ("custom_tab_title",
     "str",
     "the custom tab title.",
     "This is used only when use_custom_tab_title is True. The value is an interpolated string.",
     "Custom Tab Title"),

    ("hide_after_opening",
     "bool",
     "whether a new window is hidden right after it opens.",
     None,
     "Hide After Opening"),

    ("lock_window_size_automatically",
     "bool",
     "whether a new window's size is locked right after it opens.",
     None,
     "Lock Window Size Automatically"),

    ("disable_unfocused_window_resizing",
     "bool",
     "whether sessions without keyboard focus are prevented from resizing the window with an escape sequence.",
     None,
     "Disable Window Resizing by Unfocused Sessions"),

    ("prevent_tab",
     "bool",
     "whether this profile always opens in a new window, never in a tab.",
     None,
     "Prevent Opening in a Tab"),

    ("open_toolbelt",
     "bool",
     "whether new windows open with the toolbelt visible.",
     None,
     "Open Toolbelt"),

    ("show_rich_tab_content",
     "bool",
     "whether tabs in windows created with this profile show rich content.",
     None,
     "Show Rich Tab Content"),

    ("tab_content_maximum_lines",
     "int",
     "the most lines of rich content a tab shows.",
     "0 means no limit.",
     "Tab Content Maximum Lines"),

    ("terminal_type",
     "str",
     "the terminal type reported to apps.",
     "The value is the TERM environment variable, such as xterm-256color.",
     "Terminal Type"),

    ("locale_variables_mode",
     "LocaleVariablesMode",
     "how the locale environment variables are set.",
     None,
     "Set Local Environment Vars"),

    ("custom_locale",
     "str",
     "the custom locale.",
     "This is used only when locale_variables_mode is CUSTOM.",
     "Custom Locale"),

    ("jobs_to_ignore",
     "list[str]",
     "the names of jobs that don't cause a prompt before closing.",
     None,
     "Jobs to Ignore"),

    ("bell_sound",
     "str",
     "the sound the bell plays.",
     "The value is the name of a sound installed in a Sounds folder, the path to an audio file, or an empty string for the system alert sound.",
     "Bell Sound"),

    ("prevent_sleep",
     "bool",
     "whether the computer is kept from idle sleep while a session with this profile exists.",
     None,
     "Prevent Sleep"),

    ("allow_paste_bracketing",
     "bool",
     "whether apps may turn on bracketed paste mode.",
     None,
     "Allow Paste Bracketing"),

    ("enable_triggers_in_interactive_apps",
     "bool",
     "whether triggers fire in interactive apps.",
     None,
     "Enable Triggers in Interactive Apps"),

    ("tmux_newline",
     "bool",
     "whether pressing return in a tmux session sends a newline instead of a carriage return.",
     None,
     "Tmux Newline"),

    ("show_offscreen_command_line",
     "bool",
     "whether the command that produced the output at the top of the screen is shown when scrolled back.",
     None,
     "Show Offscreen Command line"),

    ("show_offscreen_command_line_for_current_command",
     "bool",
     "whether the offscreen command line is also shown for the command that is still running.",
     None,
     "Show Offscreen Command line for Current Command"),

    ("prompt_path_click_opens_navigator",
     "bool",
     "whether clicking the path in a prompt opens a file navigator.",
     None,
     "Prompt Path Click Opens Navigator"),

    ("composer_top_offset",
     "float",
     "the composer's vertical offset from the top of the session.",
     None,
     "Composer Top Offset"),

    ("default_pane_locked",
     "bool",
     "whether new panes are locked by default.",
     None,
     "Default Pane Locked"),

    ("buffer_input_by_default",
     "bool",
     "whether keyboard input is buffered by default in new sessions.",
     None,
     "Buffer Input by Default"),

    ("timestamps_visible",
     "bool",
     "whether timestamps are visible.",
     None,
     "Timestamps Visible"),

    ("timestamps_style",
     "TimestampsStyle",
     "how timestamps are drawn when visible.",
     None,
     "Timestamps Style"),

    ("enable_progress_bars",
     "bool",
     "whether progress bars reported by apps are shown.",
     None,
     "Enable Progress Bars"),

    ("progress_bar_height",
     "float",
     "the height of progress bars, in points.",
     None,
     "Progress Bar Height"),

    ("progress_bar_color_scheme",
     "str",
     "the color scheme for progress bars.",
     "The value is one of default, rainbow, red, green, blue, yellow, purple, cyan, or orange.",
     "Progress Bar Color Scheme"),

    ("send_alerts_to_companion",
     "bool",
     "whether this profile's notifications are also sent to the paired iTerm2 Buddy iPhone app.",
     None,
     "Send Alerts To Companion"),

    ("suppress_alerts_in_active_session",
     "bool",
     "whether notifications from the active session are suppressed.",
     None,
     "Suppress Alerts in Active Session"),

    ("mouse_reporting_allow_clicks_and_drags",
     "bool",
     "whether mouse reporting reports clicks and drags.",
     None,
     "Mouse Reporting allow clicks and drags"),

    ("restrict_mouse_reporting_to_alternate_screen_mode",
     "bool",
     "whether mouse reporting is allowed only in alternate screen mode.",
     None,
     "Restrict Mouse Reporting to Alternate Screen Mode"),

    ("allow_alternate_mouse_scroll",
     "bool",
     "whether scrolling in alternate screen mode sends arrow keys.",
     None,
     "Allow Alternate Mouse Scroll"),

    ("automatically_enable_alternate_mouse_scroll",
     "bool",
     "whether scrolling sends arrow keys automatically in alternate screen mode.",
     None,
     "Automatically Enable Alternate Mouse Scroll"),

    ("restrict_alternate_mouse_scroll_to_vertical",
     "bool",
     "whether only vertical scrolling sends arrow keys in alternate screen mode.",
     None,
     "Restrict Alternate Mouse Scroll to Vertical"),

    ("drag_to_scroll_in_alternate_screen_mode_disabled",
     "bool",
     "whether dragging a selection past the edge stops scrolling in alternate screen mode.",
     None,
     "Drag to Scroll in Alternate Screen Mode Disabled"),

    ("left_control_key_behavior",
     "ModifierKeyBehavior",
     "how the left control key is reported to apps.",
     None,
     "Left Control Key"),

    ("right_control_key_behavior",
     "ModifierKeyBehavior",
     "how the right control key is reported to apps.",
     None,
     "Right Control Key"),

    ("left_command_key_behavior",
     "ModifierKeyBehavior",
     "how the left command key is reported to apps.",
     None,
     "Left Command Key"),

    ("right_command_key_behavior",
     "ModifierKeyBehavior",
     "how the right command key is reported to apps.",
     None,
     "Right Command Key"),

    ("function_key_behavior",
     "ModifierKeyBehavior",
     "how the fn key is reported to apps.",
     None,
     "Function Key"),

    ("treat_option_as_alt",
     "bool",
     "whether option is reported as alt in modifier flags.",
     None,
     "Treat Option as Alt"),

    ("allow_modify_other_keys",
     "bool",
     "whether apps may turn on xterm's modifyOtherKeys mode.",
     None,
     "Allow modifyOtherKeys"),

    ("movement_keys_scroll_outside_interactive_apps",
     "bool",
     "whether arrow and page keys scroll when not in an interactive app.",
     None,
     "Movement Keys Scroll Outside Interactive Apps"),

    ("has_hotkey",
     "bool",
     "whether this profile has a dedicated hotkey window.",
     "To assign a hotkey without a key code, also set hotkey_activated_by_modifier and hotkey_modifier_activation.",
     "Has Hotkey"),

    ("hotkey_activated_by_modifier",
     "bool",
     "whether double-tapping a modifier key toggles the hotkey window.",
     None,
     "HotKey Activated By Modifier"),

    ("hotkey_modifier_activation",
     "HotkeyModifierActivation",
     "which modifier key to double-tap to toggle the hotkey window.",
     None,
     "HotKey Modifier Activation"),

    ("hotkey_auto_hides",
     "bool",
     "whether the hotkey window hides when it loses focus.",
     None,
     "HotKey Window AutoHides"),

    ("hotkey_reopens_on_activation",
     "bool",
     "whether an auto-hidden hotkey window reappears when iTerm2 is activated.",
     None,
     "HotKey Window Reopens On Activation"),

    ("hotkey_animates",
     "bool",
     "whether the hotkey window animates when it shows and hides.",
     None,
     "HotKey Window Animates"),

    ("hotkey_floats",
     "bool",
     "whether the hotkey window floats above other windows.",
     None,
     "HotKey Window Floats"),

    ("hotkey_dock_click_action",
     "HotkeyWindowDockClickAction",
     "whether clicking iTerm2's Dock icon shows the hotkey window.",
     None,
     "HotKey Window Dock Click Action"),

    ("automatically_log",
     "bool",
     "whether session output is logged automatically.",
     None,
     "Automatically Log"),

    ("log_directory",
     "str",
     "the directory for automatic logs.",
     None,
     "Log Directory"),

    ("log_filename_format",
     "str",
     "the format of automatic log file names.",
     "The value is an interpolated string.",
     "Log Filename Format"),

    ("logging_style",
     "LoggingStyle",
     "the format of automatic logs.",
     None,
     "Plain Text Logging"),

    ("archive_on_closure",
     "bool",
     "whether sessions are archived when they close.",
     None,
     "Archive On Closure"),

    ("archive_directory",
     "str",
     "the directory for archived sessions.",
     None,
     "Archive Directory"),

    ("initial_url",
     "str",
     "the URL a web browser profile opens.",
     None,
     "Initial URL"),

    ("browser_zoom",
     "float",
     "the zoom level of a web browser profile.",
     "100 means 100%.",
     "Browser Zoom"),

    ("browser_dev_null",
     "bool",
     "whether a web browser profile uses a private data store that is not shared with other browser profiles.",
     None,
     "Dev Null Mode"),

    ("browser_width",
     "float",
     "the initial width of a web browser profile's window, in points.",
     None,
     "Width in Points"),

    ("browser_height",
     "float",
     "the initial height of a web browser profile's window, in points.",
     None,
     "Height in Points"),

    ("browser_instant_replay",
     "bool",
     "whether instant replay is enabled for a web browser profile.",
     None,
     "Instant Replay"),
    ]


def strip_up_to(s, limit):
    count = 0
    while count < limit and s.startswith(" "):
        s = s[1:]
        count += 1
    s.rstrip()
    return s.rstrip()

def p(message, indent, subs):
    for orig in subs:
        message = message.replace("{{" + orig + "}}", subs[orig])

    lines = list(map(lambda s: strip_up_to(s, 5), message.split("\n")))
    prefix = " " * indent
    while lines and not lines[0]:
        del lines[0]
    while lines and not lines[len(lines) - 1]:
        del lines[len(lines) - 1]
    for line in lines:
        if len(line) == 0:
            print("")
        elif len(line) < 80 - indent:
            print(f'{prefix}{line}')
        else:
            if len(line) >= 80 - indent:
                tokens = line.strip().split(" ")
                if tokens:
                    leading_space_count = len(line) - len(line.lstrip())
                    leader = " " * leading_space_count
                    tokens[0] = leader + tokens[0]

                selected = []
                while True and tokens:
                    candidate = " ".join(selected + [tokens[0]])
                    if len(candidate) >= 80 - indent and selected:
                        print(f'{prefix}{" ".join(selected)}')
                        selected = []
                        continue
                    selected.append(tokens[0])
                    del tokens[0]
                if selected:
                    candidate = " ".join(selected)
                    print(f'{prefix}{candidate}')

# Setters whose docs differ from the getter's: name -> (first line, detailed).
SETTER_DOCS = {
    "background_image_location": (
        "Sets or clears the path to a background image.",
        """The value is a string with the path to the image file,
     or an empty string to clear the setting.

     :param value: A str"""),
}

def setter_docs(name, summary, detailed):
    return SETTER_DOCS.get(name, (f'Sets {summary}', detailed))

# Enums whose values are ints. Getters return the raw int.
INT_ENUMS = ['BackgroundImageSourceMode', 'CursorBlinkFadeCurve', 'WindowType', 'LocaleVariablesMode', 'LoggingStyle', 'ModifierKeyBehavior', 'HotkeyWindowDockClickAction', 'HotkeyModifierActivation', 'TimestampsStyle']
POD = ["str", "bool", "float", "int", "BackgroundImageMode", "CursorType", "ThinStrokes", "UnicodeNormalization", "CharacterEncoding", "OptionKeySends", "InitialWorkingDirectory", "IconMode", "str | None"] + INT_ENUMS
def generate_local_write_only_profile():
    for (name, type, summary, detailed, key) in schema:
        if type in ["Color", "Color | None"]:
            setter = "_color_set"
        elif type in POD or type.startswith("list[") or type.startswith("dict["):
            setter = "_simple_set"
        else:
            print("Unrecognized type " + type)
            assert(False)
        print(f'    def set_{name}(self, value: {type}) -> None:')
        print(f'        """')
        subs = {"accessor": "set_"}
        first_line, detailed = setter_docs(name, summary, detailed)
        p(first_line, 8, subs)
        if detailed:
            print("")
            p(f'{detailed}', 8, subs)
        if not detailed or ":param" not in detailed:
            print("")
            type_link = type
            if type == "Color":
                type_link = ":class:`Color`"
            elif type == "Color | None":
                type_link = ":class:`Color` or `None`"
            elif type == "BackgroundImageMode":
                type_link = "`BackgroundImageMode`"
            if type_link[0] in "AEIOUaeiou":
                article = "An"
            else:
                article = "A"
            print(f'        :param value: {article} {type_link}')
        print(f'        """')
        if key in ["Custom Directory", "Icon" ]:
            getter = ".value"
        else:
            getter = ""
        print(f'        return self.{setter}("{key}", value{getter})')
        print("")

def generate_write_only_profile():
    for (name, type, summary, detailed, key) in schema:
        if type in ["Color", "Color | None"]:
            setter = "_async_color_set"
        elif type in POD or type.startswith("list[") or type.startswith("dict["):
            setter = "_async_simple_set"
        else:
            print("Unrecognized type " + type)
            assert(False)
        print(f'    async def async_set_{name}(self, value: {type}) -> None:')
        subs = {"accessor": "async_set_"}
        print(f'        """')
        first_line, detailed = setter_docs(name, summary, detailed)
        p(first_line, 8, subs)
        if detailed:
            print("")
            p(f'{detailed}', 8, subs)
        else:
            print("")
            type_link = type
            if type == "Color":
                type_link = ":class:`Color`"
            elif type == "Color | None":
                type_link = ":class:`Color` or `None`"
            elif type == "BackgroundImageMode":
                type_link = "`BackgroundImageMode`"
            if type_link[0] in "AEIOUaeiou":
                article = "An"
            else:
                article = "A"
            print(f'        :param value: {article} {type_link}')
        print(f'        """')
        if key in ["Custom Directory", "Icon" ]:
            getter = ".value"
        else:
            getter = ""
        print(f'        return await self.{setter}("{key}", value{getter})')
        print("")

def remove_params(string):
    return "\n".join(filter(lambda x: ":param" not in x, string.split("\n")))

# The getters return the raw stored value rather than an instance of the enum.
GETTER_RETURN_TYPES = {
    "CharacterEncoding": "int",
    "CursorType": "int",
    "IconMode": "int",
    "OptionKeySends": "int",
    "ThinStrokes": "int",
    "UnicodeNormalization": "int",
    "InitialWorkingDirectory": "str",
    **{name: "int" for name in INT_ENUMS},
}

def generate_profile():
    for (name, type, summary, detailed, key) in schema:
        # These keys are optional booleans but only for getters. I don't know why but I don't want
        # to change it until I understand it.
        if key in ["Initial Use Transparency", "Show Status Bar", "Use libtickit protocol", "Triggers Use Interpolated Strings", "Left Option Key Changeable", "Right Option Key Changeable", "Open Password Manager Automatically"]:
            type = "bool | None"

        if type in ["Color", "Color | None"]:
            getter = "get_color_with_key"
        elif type == "bool | None":
            # I don't know why this is necessary
            getter = "_get_optional_bool"
        elif type in POD or type.startswith("list[") or type.startswith("dict["):
            getter = "_simple_get"
        else:
            print("Unrecognized type " + type)
            assert(False)
        if type == "BackgroundImageMode":
            wrapper = "BackgroundImageMode"
        elif key == "Draw Powerline Glyphs":
            wrapper = "bool"
        else:
            wrapper = None
        base_type = type[:-len(" | None")] if type.endswith(" | None") else type
        return_type = GETTER_RETURN_TYPES.get(base_type, base_type)
        # bool(None) is False, so the Draw Powerline Glyphs getter never
        # returns None. Every other getter returns None when the key is absent.
        can_be_none = wrapper != "bool"
        if can_be_none:
            return_type += " | None"
        print(f'    @property')
        print(f'    def {name}(self) -> {return_type}:')
        subs = {"accessor": ""}
        print(f'        """')
        p(f'Returns {summary}', 8, subs)
        print("")
        if detailed:
            p(f'{remove_params(detailed)}', 8, subs)
            print("")

        type_link = base_type
        if base_type == "Color":
            type_link = ":class:`Color`"
        elif base_type == "BackgroundImageMode":
            type_link = "`BackgroundImageMode`"
        if type_link[0] in "AEIOUaeiou":
            article = "An"
        else:
            article = "A"
        if can_be_none:
            type_link += " or `None`"
        print(f'        :returns: {article} {type_link}')
        print(f'        """')
        if wrapper == "bool":
            print(f'        return bool(self.{getter}("{key}"))')
        elif wrapper:
            print(f'        value = self.{getter}("{key}")')
            print(f'        if value is None:')
            print(f'            return None')
            print(f'        return {wrapper}(value)')
        else:
            print(f'        return self.{getter}("{key}")')
        print("")

def print_file(filename):
    print(open(filename).read())

for tuple in schema:
    if len(tuple) != 5:
        print(len(tuple))
        for entry in tuple:
            print(entry)
        exit()
print_file("prologue.txt")
generate_local_write_only_profile()
print_file("write_only_profile_prologue.txt")
generate_write_only_profile()
print_file("profile_prologue.txt")
generate_profile()
print_file("partial_profile.txt")
