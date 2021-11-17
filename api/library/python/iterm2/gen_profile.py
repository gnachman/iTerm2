#!/usr/bin/env python3

# These have light/dark variants
base_colors_schema = [
    ("foreground_color",
     "'iterm2.color.Color'",
     "the foreground color.",
     None,
     "Foreground Color"),

    ("background_color",
     "'iterm2.color.Color'",
     "the background color.",
     None,
     "Background Color"),

    ("bold_color",
     "'iterm2.color.Color'",
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
     "'iterm2.color.Color'",
     "the link color.",
     None,
     "Link Color"),

    ("selection_color",
     "'iterm2.color.Color'",
     "the selection background color.",
     None,
     "Selection Color"),

    ("selected_text_color",
     "'iterm2.color.Color'",
     "the selection text color.",
     None,
     "Selected Text Color"),

    ("cursor_color",
     "'iterm2.color.Color'",
     "the cursor color.",
     None,
     "Cursor Color"),

    ("cursor_text_color",
     "'iterm2.color.Color'",
     "the cursor text color.",
     None,
     "Cursor Text Color"),

    ("ansi_0_color",
     "'iterm2.color.Color'",
     "the ANSI 0 color.",
     None,
     "Ansi 0 Color"),

    ("ansi_1_color",
     "'iterm2.color.Color'",
     "the ANSI 1 color.",
     None,
     "Ansi 1 Color"),

    ("ansi_2_color",
     "'iterm2.color.Color'",
     "the ANSI 2 color.",
     None,
     "Ansi 2 Color"),

    ("ansi_3_color",
     "'iterm2.color.Color'",
     "the ANSI 3 color.",
     None,
     "Ansi 3 Color"),

    ("ansi_4_color",
     "'iterm2.color.Color'",
     "the ANSI 4 color.",
     None,
     "Ansi 4 Color"),

    ("ansi_5_color",
     "'iterm2.color.Color'",
     "the ANSI 5 color.",
     None,
     "Ansi 5 Color"),

    ("ansi_6_color",
     "'iterm2.color.Color'",
     "the ANSI 6 color.",
     None,
     "Ansi 6 Color"),

    ("ansi_7_color",
     "'iterm2.color.Color'",
     "the ANSI 7 color.",
     None,
     "Ansi 7 Color"),

    ("ansi_8_color",
     "'iterm2.color.Color'",
     "the ANSI 8 color.",
     None,
     "Ansi 8 Color"),

    ("ansi_9_color",
     "'iterm2.color.Color'",
     "the ANSI 9 color.",
     None,
     "Ansi 9 Color"),

    ("ansi_10_color",
     "'iterm2.color.Color'",
     "the ANSI 10 color.",
     None,
     "Ansi 10 Color"),

    ("ansi_11_color",
     "'iterm2.color.Color'",
     "the ANSI 11 color.",
     None,
     "Ansi 11 Color"),

    ("ansi_12_color",
     "'iterm2.color.Color'",
     "the ANSI 12 color.",
     None,
     "Ansi 12 Color"),

    ("ansi_13_color",
     "'iterm2.color.Color'",
     "the ANSI 13 color.",
     None,
     "Ansi 13 Color"),

    ("ansi_14_color",
     "'iterm2.color.Color'",
     "the ANSI 14 color.",
     None,
     "Ansi 14 Color"),

    ("ansi_15_color",
     "'iterm2.color.Color'",
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
     "'iterm2.color.Color'",
     "the tab color.",
     None,
     "Tab Color"),

    ("use_tab_color",
     "bool",
     "whether the tab color should be used.",
     None,
     "Use Tab Color"),

    ("underline_color",
     "typing.Optional['iterm2.color.Color']",
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
     "'iterm2.color.Color'",
     "the cursor guide color. The alpha value is respected.",
     None,
     "Cursor Guide Color"),

    ("badge_color",
     "'iterm2.color.Color'",
     "the badge color. The alpha value is respected.",
     None,
     "Badge Color"),
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
     "typing.List[typing.Dict[str, typing.Any]]",
     "the triggers.",
     "Value is an encoded trigger. Use iterm2.decode_trigger to convert from an encoded trigger to an object. Trigger objects can be encoded using the encode property.",
     "Triggers"),

    ("smart_selection_rules",
     "typing.List[typing.Dict[str, typing.Any]]",
     "the smart selection rules.",
     "The value is a list of dicts of smart selection rules (currently undocumented)",
     "Smart Selection Rules"),

    ("smart_selection_actions_use_interpolated_strings",
     "bool",
     "whether smart selection action parameters are interpolated strings.",
     "Should smart selection actions' parameters be treated as interpolated strings? If false, use the backward-compatibility syntax.",
     "Smart Selection Actions Use Interpolated Strings"),

    ("semantic_history",
     "typing.Dict[str, typing.Any]",
     "the semantic history prefs.",
     None,
     "Semantic History"),

    ("automatic_profile_switching_rules",
     "typing.List[str]",
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
     "The value is a Path.",
     "Background Image Location"),


    ("key_mappings",
     "typing.Dict[str, typing.Any]",
     "the keyboard shortcuts.",
     "The value is a Dictionary mapping keystroke to action. You can convert between the values in this dictionary and a :class:`~iterm2.KeyBinding` using `iterm2.decode_key_binding`",
     "Keyboard Map"),

    ("touchbar_mappings",
     "typing.Dict[str, typing.Any]",
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
     "typing.Optional[str]",
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
     "Open Password Manager Automatically")
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

POD = ["str", "bool", "float", "int", "BackgroundImageMode", "CursorType", "ThinStrokes", "UnicodeNormalization", "CharacterEncoding", "OptionKeySends", "InitialWorkingDirectory", "IconMode", "typing.Optional[str]"]
def generate_local_write_only_profile():
    for (name, type, summary, detailed, key) in schema:
        if type in ["'iterm2.color.Color'", "typing.Optional['iterm2.color.Color']"]:
            setter = "_color_set"
        elif type in POD or type.startswith("typing.List[") or type.startswith("typing.Dict["):
            setter = "_simple_set"
        else:
            print("Unrecognized type " + type)
            assert(False)
        print(f'    def set_{name}(self, value: {type}):')
        print(f'        """')
        subs = {"accessor": "set_"}
        if detailed:
            p(f'Sets {summary}', 8, subs)
            print("")
            p(f'{detailed}', 8, subs)
        else:
            p(f'Sets {summary}', 8, subs)
        if not detailed or ":param" not in detailed:
            print("")
            type_link = type
            if type == "'iterm2.color.Color'":
                type_link = ":class:`Color`"
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
        if type in ["'iterm2.color.Color'", "typing.Optional['iterm2.color.Color']"]:
            setter = "_async_color_set"
        elif type in POD or type.startswith("typing.List[") or type.startswith("typing.Dict["):
            setter = "_async_simple_set"
        else:
            print("Unrecognized type " + type)
            assert(False)
        print(f'    async def async_set_{name}(self, value: {type}):')
        subs = {"accessor": "async_set_"}
        print(f'        """')
        if detailed:
            p(f'Sets {summary}', 8, subs)
            print("")
            p(f'{detailed}', 8, subs)
        else:
            p(f'Sets {summary}', 8, subs)
            print("")
            type_link = type
            if type == "'iterm2.color.Color'":
                type_link = ":class:`Color`"
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

def generate_profile():
    for (name, type, summary, detailed, key) in schema:
        # These keys are optional booleans but only for getters. I don't know why but I don't want
        # to change it until I understand it.
        if key in ["Initial Use Transparency", "Show Status Bar", "Use libtickit protocol", "Triggers Use Interpolated Strings", "Left Option Key Changeable", "Right Option Key Changeable", "Open Password Manager Automatically"]:
            type = "typing.Optional[bool]"

        if type in ["'iterm2.color.Color'", "typing.Optional['iterm2.color.Color']"]:
            getter = "get_color_with_key"
        elif type == "typing.Optional[bool]":
            # I don't know why this is necessary
            getter = "_get_optional_bool"
        elif type in POD or type.startswith("typing.List[") or type.startswith("typing.Dict["):
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
        print(f'    @property')
        print(f'    def {name}(self) -> {type}:')
        subs = {"accessor": ""}
        print(f'        """')
        p(f'Returns {summary}', 8, subs)
        print("")
        if detailed:
            p(f'{remove_params(detailed)}', 8, subs)
            print("")

        type_link = type
        if type == "'iterm2.color.Color'":
            type_link = ":class:`Color`"
        elif type == "BackgroundImageMode":
            type_link = "`BackgroundImageMode`"
        if type_link[0] in "AEIOUaeiou":
            article = "An"
        else:
            article = "A"
        print(f'        :returns: {article} {type_link}')
        print(f'        """')
        if wrapper:
            print(f'        return {wrapper}(self.{getter}("{key}"))')
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
