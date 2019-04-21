"""Provides classes for representing, querying, and modifying iTerm2 profiles."""
import asyncio
import iterm2.color
import iterm2.colorpresets
import enum
import iterm2.rpc
import json
import typing

class BackgroundImageMode(enum.Enum):
    """Describes how the background image should be accommodated to fit the window."""
    STRETCH = 0  #: Stretch to fit
    TILE = 1  #: Full size, undistorted, and tessellated if needed.
    ASPECT_FILL = 2  #: Scale to fill the space, cropping if needed. Does not distort.
    ASPECT_FIT = 3  #: Scale to fit the space, adding letterboxes or pillarboxes if needed. Does not distort.

class BadGUIDException(Exception):
    """Raised when a profile does not have a GUID or the GUID is unknown."""

class CursorType(enum.Enum):
    """Describes the type of the cursor."""
    CURSOR_TYPE_UNDERLINE = 0  #: Underline cursor
    CURSOR_TYPE_VERTICAL = 1  #: Vertical bar cursor
    CURSOR_TYPE_BOX = 2  #: Box cursor

class ThinStrokes(enum.Enum):
    """When thin strokes should be used."""
    THIN_STROKES_SETTING_NEVER = 0  #: NEver
    THIN_STROKES_SETTING_RETINA_DARK_BACKGROUNDS_ONLY = 1  #: When the background is dark and the display is a retina display.
    THIN_STROKES_SETTING_DARK_BACKGROUNDS_ONLY = 2  #: When the background is dark.
    THIN_STROKES_SETTING_ALWAYS = 3  #: Always.
    THIN_STROKES_SETTING_RETINA_ONLY = 4  #: When the display is a retina display.

class UnicodeNormalization(enum.Enum):
    """How to perform Unicode normalization."""
    UNICODE_NORMALIZATION_NONE = 0  #: Do not modify input
    UNICODE_NORMALIZATION_NFC = 1  #: Normalization form C
    UNICODE_NORMALIZATION_NFD = 2  #: Normalization form D
    UNICODE_NORMALIZATION_HFSPLUS = 3  #: Apple's HFS+ normalization form

class CharacterEncoding(enum.Enum):
    """String encodings."""
    CHARACTER_ENCODING_UTF_8 = 4

class OptionKeySends(enum.Enum):
    """How should the option key behave?"""
    OPTION_KEY_NORMAL = 0  #: Standard behavior
    OPTION_KEY_META = 1  #: Acts like Meta. Not recommended.
    OPTION_KEY_ESC = 2  #: Adds ESC prefix.

class InitialWorkingDirectory(enum.Enum):
    """How should the initial working directory of a session be set?"""
    INITIAL_WORKING_DIRECTORY_CUSTOM = "Yes"  #: Custom directory, specified elsewhere
    INITIAL_WORKING_DIRECTORY_HOME = "No"  #: Use default of home directory
    INITIAL_WORKING_DIRECTORY_RECYCLE = "Recycle"  #: Reuse the "current" directory, or home if there is no current.
    INITIAL_WORKING_DIRECTORY_ADVANCED = "Advanced"  #: Use advanced settings, which specify more granular behavior depending on whether the new session is a new window, tab, or split pane.

class IconMode(enum.Enum):
    """How should session icons be selected?"""
    NONE = 0
    AUTOMATIC = 1
    CUSTOM = 2

class TitleComponents(enum.Enum):
    """Which title components should be present?"""
    SESSION_NAME = (1 << 0)
    JOB = (1 << 1)
    WORKING_DIRECTORy = (1 << 2)
    TTY = (1 << 3)
    CUSTOM = (1 << 4)  #: Mutually exclusive with all other options.
    PROFILE_NAME = (1 << 5)
    PROFILE_AND_SESSION_NAME = (1 << 6)
    USER = (1 << 7)
    HOST = (1 << 8)

class LocalWriteOnlyProfile:
    """A profile that can be modified but not read and does not send changes on each write.

    You can safely create this with `LocalWriteOnlyProfile()`. Use
    :meth:`~iterm2.Session.async_set_profile_properties` to update a session
    without modifying the underlying profile.

    .. seealso::
      * Example ":ref:`copycolor_example`"
      * Example ":ref:`settabcolor_example`"
      * Example ":ref:`increase_font_size_example`"
    """
    def __init__(self):
      self.__values = {}

    @property
    def values(self):
        return self.__values

    def _simple_set(self, key, value):
        """value is a json type"""
        if key is None:
            self.__values[key] = None
        else:
            self.__values[key] = json.dumps(value)

    def _color_set(self, key, value):
        if value is None:
            self.__values[key] = "null"
        else:
            self.__values[key] = json.dumps(value.get_dict())

    def _guids_for_set(self):
        if self.session_id is None:
            assert self.__guid is not None
            return [self.__guid]
        else:
            return self.session_id

    def set_foreground_color(self, value: 'iterm2.color.Color'):
        """Sets the foreground color.

        :param value: A :class:`Color`"""
        return self._color_set("Foreground Color", value)

    def set_background_color(self, value: 'iterm2.color.Color'):
        """Sets the background color.

        :param value: A :class:`Color`"""
        return self._color_set("Background Color", value)

    def set_bold_color(self, value: 'iterm2.color.Color'):
        """Sets the bold text color.

        :param value: A :class:`Color`"""
        return self._color_set("Bold Color", value)

    def set_link_color(self, value: 'iterm2.color.Color'):
        """Sets the link color.

        :param value: A :class:`Color`"""
        return self._color_set("Link Color", value)

    def set_selection_color(self, value: 'iterm2.color.Color'):
        """Sets the selection background color.

        :param value: A :class:`Color`"""
        return self._color_set("Selection Color", value)

    def set_selected_text_color(self, value: 'iterm2.color.Color'):
        """Sets the selection text color.

        :param value: A :class:`Color`"""
        return self._color_set("Selected Text Color", value)

    def set_cursor_color(self, value: 'iterm2.color.Color'):
        """Sets the cursor color.

        :param value: A :class:`Color`"""
        return self._color_set("Cursor Color", value)

    def set_cursor_text_color(self, value: 'iterm2.color.Color'):
        """Sets the cursor text color.

        :param value: A :class:`Color`"""
        return self._color_set("Cursor Text Color", value)

    def set_ansi_0_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 0 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 0 Color", value)

    def set_ansi_1_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 1 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 1 Color", value)

    def set_ansi_2_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 2 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 2 Color", value)

    def set_ansi_3_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 3 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 3 Color", value)

    def set_ansi_4_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 4 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 4 Color", value)

    def set_ansi_5_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 5 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 5 Color", value)

    def set_ansi_6_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 6 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 6 Color", value)

    def set_ansi_7_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 7 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 7 Color", value)

    def set_ansi_8_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 8 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 8 Color", value)

    def set_ansi_9_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 9 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 9 Color", value)

    def set_ansi_10_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 10 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 10 Color", value)

    def set_ansi_11_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 11 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 11 Color", value)

    def set_ansi_12_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 12 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 12 Color", value)

    def set_ansi_13_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 13 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 13 Color", value)

    def set_ansi_14_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 14 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 14 Color", value)

    def set_ansi_15_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 15 color.

        :param value: A :class:`Color`"""
        return self._color_set("Ansi 15 Color", value)

    def set_smart_cursor_color(self, value: 'iterm2.color.Color'):
        """Sets the smart cursor color.

        :param value: A :class:`Color`"""
        return self._simple_set("Smart Cursor Color", value)

    def set_tab_color(self, value: 'iterm2.color.Color'):
        """Sets the tab color.

        :param value: A :class:`Color`"""
        return self._color_set("Tab Color", value)

    def set_underline_color(self, value: 'iterm2.color.Color'):
        """Sets the underline color.

        :param value: A :class:`Color` or None"""
        return self._color_set("Underline Color", value)

    def set_cursor_guide_color(self, value: 'iterm2.color.Color'):
        """Sets the cursor guide color. The alpha value is respected.

        :param value: A :class:`Color`"""
        return self._color_set("Cursor Guide Color", value)

    def set_badge_color(self, value: 'iterm2.color.Color'):
        """Sets the badge color. The alpha value is respected.

        :param value: A :class:`Color`"""
        return self._color_set("Badge Color", value)

    def set_name(self, value: str):
        """Sets the name.

        :param value: A string"""
        return self._simple_set("Name", value)

    def set_badge_text(self, value: str):
        """Sets the badge text.

        :param value: A :class:`Color`"""
        return self._simple_set("Badge Text", value)

    def set_answerback_string(self, value: str):
        """Sets the answerback string.

        :param value: A string"""
        return self._simple_set("Answerback String", value)

    def set_use_cursor_guide(self, value: bool):
        """Sets whether the cursor guide should be used.

        :param value: A boolean"""
        return self._simple_set("Use Cursor Guide", value)

    def set_use_tab_color(self, value: bool):
        """Sets whether the tab color should be used.

        :param value: A boolean"""
        return self._simple_set("Use Tab Color", value)

    def set_use_underline_color(self, value: 'iterm2.color.Color'):
        """Sets the underline color.

        :param value: A :class:`Color`"""
        return self._simple_set("Use Underline Color", value)

    def set_minimum_contrast(self, value: float):
        """Sets the minimum contrast.

        :param value: A float in 0 to 1"""
        return self._simple_set("Minimum Contrast", value)

    def set_cursor_boost(self, value: float):
        """Sets the cursor boost level.

        :param value: A float in 0 to 1"""
        return self._simple_set("Cursor Boost", value)

    def set_blinking_cursor(self, value: bool):
        """Sets whether the cursor blinks.

        :param value: A bool"""
        return self._simple_set("Blinking Cursor", value)

    def set_use_bold_font(self, value: bool):
        """Sets whether to use the bold variant of the font for bold text.

        :param value: A bool"""
        return self._simple_set("Use Bold Font", value)

    def set_ascii_ligatures(self, value: bool):
        """Sets whether ligatures should be used for ASCII text.

        :param value: A bool"""
        return self._simple_set("ASCII Ligatures", value)

    def set_non_ascii_ligatures(self, value: bool):
        """Sets whether ligatures should be used for non-ASCII text.

        :param value: A bool"""
        return self._simple_set("Non-ASCII Ligatures", value)

    def set_use_bright_bold(self, value: bool):
        """Sets whether bright colors should be used for bold text.

        :param value: A bool"""
        return self._simple_set("Use Bright Bold", value)

    def set_blink_allowed(self, value: bool):
        """Sets whether blinking text is allowed.

        :param value: A bool"""
        return self._simple_set("Blink Allowed", value)

    def set_use_italic_font(self, value: bool):
        """Sets whether italic text is allowed.

        :param value: A bool"""
        return self._simple_set("Use Italic Font", value)

    def set_ambiguous_double_width(self, value: bool):
        """Sets whether ambiguous-width text should be treated as double-width.

        :param value: A bool"""
        return self._simple_set("Ambiguous Double Width", value)

    def set_horizontal_spacing(self, value: float):
        """Sets the fraction of horizontal spacing.

        :param value: A float at least 0"""
        return self._simple_set("Horizontal Spacing", value)

    def set_vertical_spacing(self, value: float):
        """Sets the fraction of vertical spacing.

        :param value: A float at least 0"""
        return self._simple_set("Vertical Spacing", value)

    def set_use_non_ascii_font(self, value: bool):
        """Sets whether to use a different font for non-ASCII text.

        :param value: A bool"""
        return self._simple_set("Use Non-ASCII Font", value)

    def set_transparency(self, value: float):
        """Sets the level of transparency.

        :param value: A float between 0 and 1"""
        return self._simple_set("Transparency", value)

    def set_blur(self, value: bool):
        """Sets whether background blur should be enabled.

        :param value: A bool"""
        return self._simple_set("Blur", value)

    def set_blur_radius(self, value: float):
        """Sets the blur radius (how blurry). Requires blur to be enabled.

        :param value: A float between 0 and 30"""
        return self._simple_set("Blur Radius", value)

    def set_background_image_mode(self, value: BackgroundImageMode):
        """Sets how the background image is drawn.

        :param value: A `BackgroundImageMode`"""
        return self._simple_set("Background Image Mode", value)

    def set_blend(self, value: float):
        """Sets how much the default background color gets blended with the background image.

        :param value: A float in 0 to 1"""
        return self._simple_set("Blend", value)

    def set_sync_title(self, value: bool):
        """Sets whether the profile name stays in the tab title, even if changed by an escape
        sequence.

        :param value: A bool"""
        return self._simple_set("Sync Title", value)

    def set_disable_window_resizing(self, value: bool):
        """Sets whether the terminal can resize the window with an escape sequence.

        :param value: A bool"""
        return self._simple_set("Disable Window Resizing", value)

    def set_only_the_default_bg_color_uses_transparency(self, value: bool):
        """Sets whether window transparency shows through non-default background colors.

        :param value: A bool"""
        return self._simple_set("Only The Default BG Color Uses Transparency", value)

    def set_ascii_anti_aliased(self, value: bool):
        """Sets whether ASCII text is anti-aliased.

        :param value: A bool"""
        return self._simple_set("ASCII Anti Aliased", value)

    def set_non_ascii_anti_aliased(self, value: bool):
        """Sets whether non-ASCII text is anti-aliased.

        :param value: A bool"""
        return self._simple_set("Non-ASCII Anti Aliased", value)

    def set_scrollback_lines(self, value: int):
        """Sets the number of scrollback lines.

        :param value: An int at least 0"""
        return self._simple_set("Scrollback Lines", value)

    def set_unlimited_scrollback(self, value: bool):
        """Sets whether the scrollback buffer's length is unlimited.

        :param value: A bool"""
        return self._simple_set("Unlimited Scrollback", value)

    def set_scrollback_with_status_bar(self, value: bool):
        """Sets whether text gets appended to scrollback when there is an app status bar

        :param value: A bool"""
        return self._simple_set("Scrollback With Status Bar", value)

    def set_scrollback_in_alternate_screen(self, value: bool):
        """Sets whether text gets appended to scrollback in alternate screen mode

        :param value: A bool"""
        return self._simple_set("Scrollback in Alternate Screen", value)

    def set_mouse_reporting(self, value: bool):
        """Sets whether mouse reporting is allowed

        :param value: A bool"""
        return self._simple_set("Mouse Reporting", value)

    def set_mouse_reporting_allow_mouse_wheel(self, value: bool):
        """Sets whether mouse reporting reports the mouse wheel's movements.

        :param value: A bool"""
        return self._simple_set("Mouse Reporting allow mouse wheel", value)

    def set_allow_title_reporting(self, value: bool):
        """Sets whether the session title can be reported

        :param value: A bool"""
        return self._simple_set("Allow Title Reporting", value)

    def set_allow_title_setting(self, value: bool):
        """Sets whether the session title can be changed by escape sequence

        :param value: A bool"""
        return self._simple_set("Allow Title Setting", value)

    def set_disable_printing(self, value: bool):
        """Sets whether printing by escape sequence is disabled.

        :param value: A bool"""
        return self._simple_set("Disable Printing", value)

    def set_disable_smcup_rmcup(self, value: bool):
        """Sets whether alternate screen mode is disabled

        :param value: A bool"""
        return self._simple_set("Disable Smcup Rmcup", value)

    def set_silence_bell(self, value: bool):
        """Sets whether the bell makes noise.

        :param value: A bool"""
        return self._simple_set("Silence Bell", value)

    def set_bm_growl(self, value: bool):
        """Sets whether notifications should be shown.

        :param value: A bool"""
        return self._simple_set("BM Growl", value)

    def set_send_bell_alert(self, value: bool):
        """Sets whether notifications should be shown for the bell ringing

        :param value: A bool"""
        return self._simple_set("Send Bell Alert", value)

    def set_send_idle_alert(self, value: bool):
        """Sets whether notifications should be shown for becoming idle

        :param value: A bool"""
        return self._simple_set("Send Idle Alert", value)

    def set_send_new_output_alert(self, value: bool):
        """Sets whether notifications should be shown for new output

        :param value: A bool"""
        return self._simple_set("Send New Output Alert", value)

    def set_send_session_ended_alert(self, value: bool):
        """Sets whether notifications should be shown for a session ending

        :param value: A bool"""
        return self._simple_set("Send Session Ended Alert", value)

    def set_send_terminal_generated_alerts(self, value: bool):
        """Sets whether notifications should be shown for escape-sequence originated notifications

        :param value: A bool"""
        return self._simple_set("Send Terminal Generated Alerts", value)

    def set_flashing_bell(self, value: bool):
        """Sets whether the bell should flash the screen

        :param value: A bool"""
        return self._simple_set("Flashing Bell", value)

    def set_visual_bell(self, value: bool):
        """Sets whether a bell should be shown when the bell rings

        :param value: A bool"""
        return self._simple_set("Visual Bell", value)

    def set_close_sessions_on_end(self, value: bool):
        """Sets whether the session should close when it ends.

        :param value: A bool"""
        return self._simple_set("Close Sessions On End", value)

    def set_prompt_before_closing(self, value: bool):
        """Sets whether the session should prompt before closign

        :param value: A bool"""
        return self._simple_set("Prompt Before Closing 2", value)

    def set_session_close_undo_timeout(self, value: float):
        """Sets amount of time you can undo closing a session

        :param value: A float at least 0"""
        return self._simple_set("Session Close Undo Timeout", value)

    def set_reduce_flicker(self, value: bool):
        """Sets whether the flicker fixer is on.

        :param value: A bool"""
        return self._simple_set("Reduce Flicker", value)

    def set_send_code_when_idle(self, value: bool):
        """Sets whether to send a code when idle

        :param value: A bool"""
        return self._simple_set("Send Code When Idle", value)

    def set_application_keypad_allowed(self, value: bool):
        """Sets whether the terminal may be placed in application keypad mode

        :param value: A bool"""
        return self._simple_set("Application Keypad Allowed", value)

    def set_place_prompt_at_first_column(self, value: bool):
        """Sets whether the prompt should always begin at the first column (requires shell
        integration)

        :param value: A bool"""
        return self._simple_set("Place Prompt at First Column", value)

    def set_show_mark_indicators(self, value: bool):
        """Sets whether mark indicators should be visible

        :param value: A bool"""
        return self._simple_set("Show Mark Indicators", value)

    def set_idle_code(self, value: int):
        """Sets the ASCII code to send on idle

        :param value: An int in 0...255"""
        return self._simple_set("Idle Code", value)

    def set_idle_period(self, value: float):
        """Sets how often to send a code when idle

        :param value: A float at least 0"""
        return self._simple_set("Idle Period", value)

    def set_unicode_version(self, value: bool):
        """Sets the unicode version for wcwidth

        :param value: A bool"""
        return self._simple_set("Unicode Version", value)

    def set_cursor_type(self, value: CursorType):
        """Sets the cursor type

        :param value: The new value"""
        return self._simple_set("Cursor Type", value)

    def set_thin_strokes(self, value: ThinStrokes):
        """Sets whether thin strokes are used.

        :param value: The new value."""
        return self._simple_set("Thin Strokes", value)

    def set_unicode_normalization(self, value: UnicodeNormalization):
        """Sets the unicode normalization form to use

        :param value: the new value"""
        return self._simple_set("Unicode Normalization", value)

    def set_character_encoding(self, value: CharacterEncoding):
        """Sets the character encoding

        :param value: The new value."""
        return self._simple_set("Character Encoding", value)

    def set_left_option_key_sends(self, value: OptionKeySends):
        """Sets the behavior of the left option key.

        :param value: The new value."""
        return self._simple_set("Option Key Sends", value)

    def set_right_option_key_sends(self, value: OptionKeySends):
        """Sets the behavior of the right option key.

        :param value: The new value."""
        return self._simple_set("Right Option Key Sends", value)

    def set_triggers(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """Sets the triggers.

        :param value: A list of dicts of trigger definitions."""
        return self._simple_set("Triggers", value)

    def set_smart_selection_rules(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """Sets the smart selection rules.

        :param value: A list of dicts of smart selection rules"""
        return self._simple_set("Smart Selection Rules", value)

    def set_semantic_history(self, value: typing.Dict[str, typing.Any]):
        """Sets the semantic history prefs.

        :param value: Semantic history settings dict."""
        return self._simple_set("Semantic History", value)

    def set_automatic_profile_switching_rules(self, value: typing.List[str]):
        """Sets the automatic profile switching rules.

        :param value: A list of rules (strings)."""
        return self._simple_set("Bound Hosts", value)

    def set_advanced_working_directory_window_setting(self, value: InitialWorkingDirectory):
        """Sets the advanced working directory window setting.

        :param value: The new value. Excludes Advanced."""
        return self._simple_set("AWDS Window Option", value)

    def set_advanced_working_directory_window_directory(self, value: str):
        """Sets the advanced working directory window directory.

        :param value: Path."""
        return self._simple_set("AWDS Window Directory", value)

    def set_advanced_working_directory_tab_setting(self, value: InitialWorkingDirectory):
        """Sets the advanced working directory tab setting.

        :param value: The new value. Excludes Advanced."""
        return self._simple_set("AWDS Tab Option", value)

    def set_advanced_working_directory_tab_directory(self, value: str):
        """Sets the advanced working directory tab directory.

        :param value: Path."""
        return self._simple_set("AWDS Tab Directory", value)

    def set_advanced_working_directory_pane_setting(self, value: InitialWorkingDirectory):
        """Sets the advanced working directory pane setting.

        :param value: The new value. Excludes Advanced."""
        return self._simple_set("AWDS Pane Option", value)

    def set_advanced_working_directory_pane_directory(self, value: str):
        """Sets the advanced working directory pane directory.

        :param value: Path."""
        return self._simple_set("AWDS Pane Directory", value)

    def set_normal_font(self, value: str):
        """Sets the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii.

        :param value: Font name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"
        """
        return self._simple_set("Normal Font", value)

    def set_non_ascii_font(self, value: str):
        """Sets the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.

        :param value: Font name and size as a string."""
        return self._simple_set("Non Ascii Font", value)

    def set_background_image_location(self, value: str):
        """Sets path to the background image.

        :param value: Path."""
        return self._simple_set("Background Image Location", value)

    def set_key_mappings(self, value: typing.Dict[str, str]):
        """Sets the keyboard shortcuts.

        :param value: Dictionary mapping keystroke to action."""
        return self._simple_set("Keyboard Map", value)

    def set_touchbar_mappings(self, value: typing.Dict[str, str]):
        """Sets the touchbar actions.

        :param value: Dictionary mapping touch bar item to action."""
        return self._simple_set("Touch Bar Map", value)

    def set_use_custom_command(self, value: str):
        """"Sets whether to use a custom command when the session is created.

        :param value: The string "Yes" or "No".
        """
        return self._simple_set("Custom Command", value)

    def set_command(self, value: str):
        """"The command to run when the session starts.

        custom_command must be set to "Yes" or this will be ignored.

        :param value: A string giving the command to run.
        """
        return self._simple_set("Command", value)

    def set_initial_directory_mode(self, value: InitialWorkingDirectory):
        """Sets whether to use a custom (not home) initial working directory.

        :param value: The new value.
        """
        return self._simple_set("Custom Directory", value.value)

    def set_custom_directory(self, value: str):
        """Sets the initial working directory.

        The initial_directory_mode must be set to "Yes" for this to take effect.
        """
        return self._simple_set("Working Directory", value)

    def set_icon_mode(self, value: IconMode):
        """Sets the icon mode.

        :param value: The icon mode.
        """
        return self._simple_set("Icon", value.value)

    def set_custom_icon_path(self, value: str):
        """Sets the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.
        """
        return self._simple_set("Custom Icon Path", value)

    def set_title_components(self, value: typing.List[TitleComponents]):
        """Sets which components are visible in the session's title, or selects a custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        n = 0
        for c in value:
            n += c.value
        return self._simple_set("Title Components", n)

    def set_title_function(self, display_name: str, identifier: str):
        """Sets the function call for the session title provider and its display name for the UI.

        :param display_name: This is shown in the Title Components menu in the UI.
        :identifier: The unique identifier, typically a backwards domain name.

        This takes effect only when the title_components property is set to `CUSTOM`.
        """
        return self._simple_set("Title Function", [display_name, identifier])

    def set_badge_top_margin(self, value: int):
        """Sets the top margin of the badge.

        :param value: The new value in points.
        """
        return self._simple_set("Badge Top Margin", value)

    def set_badge_right_margin(self, value: int):
        """Sets the right margin of the badge.

        :param value: The new value in points.
        """
        return self._simple_set("Badge Right Margin", value)

    def set_badge_max_width(self, value: int):
        """Sets the max width of the badge.

        :param value: The new value in points.
        """
        return self._simple_set("Badge Max Width", value)

    def set_badge_max_height(self, value: int):
        """Sets the max height of the badge.

        :param value: The new value in points.
        """
        return self._simple_set("Badge Max Height", value)


    def set_badge_font(self, value: str):
        """Sets the font of the badge.

        :param value: The new font name, like "Helvetica"
        """
        return self._simple_set("Badge Font", value)

    def set_use_custom_window_title(self, value: bool):
        """Sets whether the custom window title is used.

        :param value: Should the custom window title in the profile be used?
        """
        return self._simple_set("Use Custom Window Title", value)

    def set_custom_window_title(self, value: str):
        """Sets the custom window title.

        This will only be used if use_custom_window_title is True.

        :param value: The new value. An interpolated string.
        """
        return self._simple_set("Custom Window Title", value)

    def set_use_transparency_initially(self, value: bool):
        """Should a window created with this profile respect the transparency setting?

        :param value: If True, use transparency; if False, force the window to be opaque (but it can be toggled with View > Use Transparency).
        """
        return self._simple_set("Initial Use Transparency", value)

    def set_status_bar_enabled(self, value: bool):
        """Should the status bar be enabled?

        :param value: If True, the status bar will be shown.
        """
        return self._simple_set("Show Status Bar", value)

    def set_use_csi_u(self, value: bool):
        """Report keystrokes with CSI u protocol?

        :param value: If True, CSI u will be enabled.
        """
        return self._simple_set("Use libtickit protocol", value)

    def set_triggers_use_interpolated_strings(self, value: bool):
        """Should trigger parameters be interpreted as interpolated strings?
        """
        return self._simple_set("Triggers Use Interpolated Strings", value)


class WriteOnlyProfile:
    """A profile that can be modified but not read. Useful for changing many
    sessions' profiles at once without knowing what they are."""
    def __init__(self, session_id, connection, guid=None):
        assert session_id != "all"
        self.connection = connection
        self.session_id = session_id
        self.__guid = guid

    async def _async_simple_set(self, key: str, value: typing.Any):
        """value is a json type"""
        await iterm2.rpc.async_set_profile_property(
                self.connection,
                self.session_id,
                key,
                value,
                self._guids_for_set())

    async def _async_color_set(self, key, value):
        if value is None:
            await iterm2.rpc.async_set_profile_property(
                self.connection,
                self.session_id,
                key,
                "null",
                self._guids_for_set())
        else:
            await iterm2.rpc.async_set_profile_property(
                self.connection,
                self.session_id,
                key,
                value.get_dict(),
                self._guids_for_set())

    def _guids_for_set(self):
        if self.session_id is None:
            assert self.__guid is not None
            return [self.__guid]
        else:
            return self.session_id

    async def async_set_color_preset(self, preset: iterm2.colorpresets.ColorPreset):
        """Sets the color preset.

        :param preset: The new value.

        .. seealso::
            * Example ":ref:`colorhost_example`"
            * Example ":ref:`random_color_example`"
            * Example ":ref:`theme_example`"
            * Example ":ref:`darknight_example`"
        """
        coros = []
        for value in preset.values:
            coro = self._async_color_set(
                    value.key,
                    iterm2.color.Color(
                        value.red,
                        value.green,
                        value.blue,
                        value.alpha,
                        value.color_space))
            coros.append(coro)
        await asyncio.gather(*coros)


    async def async_set_foreground_color(self, value: 'iterm2.color.Color'):
        """Sets the foreground color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Foreground Color", value)

    async def async_set_background_color(self, value: 'iterm2.color.Color'):
        """Sets the background color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Background Color", value)

    async def async_set_bold_color(self, value: 'iterm2.color.Color'):
        """Sets the bold text color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Bold Color", value)

    async def async_set_link_color(self, value: 'iterm2.color.Color'):
        """Sets the link color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Link Color", value)

    async def async_set_selection_color(self, value: 'iterm2.color.Color'):
        """Sets the selection background color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Selection Color", value)

    async def async_set_selected_text_color(self, value: 'iterm2.color.Color'):
        """Sets the selection text color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Selected Text Color", value)

    async def async_set_cursor_color(self, value: 'iterm2.color.Color'):
        """Sets the cursor color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Cursor Color", value)

    async def async_set_cursor_text_color(self, value: 'iterm2.color.Color'):
        """Sets the cursor text color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Cursor Text Color", value)

    async def async_set_ansi_0_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 0 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 0 Color", value)

    async def async_set_ansi_1_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 1 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 1 Color", value)

    async def async_set_ansi_2_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 2 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 2 Color", value)

    async def async_set_ansi_3_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 3 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 3 Color", value)

    async def async_set_ansi_4_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 4 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 4 Color", value)

    async def async_set_ansi_5_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 5 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 5 Color", value)

    async def async_set_ansi_6_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 6 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 6 Color", value)

    async def async_set_ansi_7_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 7 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 7 Color", value)

    async def async_set_ansi_8_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 8 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 8 Color", value)

    async def async_set_ansi_9_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 9 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 9 Color", value)

    async def async_set_ansi_10_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 10 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 10 Color", value)

    async def async_set_ansi_11_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 11 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 11 Color", value)

    async def async_set_ansi_12_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 12 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 12 Color", value)

    async def async_set_ansi_13_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 13 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 13 Color", value)

    async def async_set_ansi_14_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 14 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 14 Color", value)

    async def async_set_ansi_15_color(self, value: 'iterm2.color.Color'):
        """Sets the ANSI 15 color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Ansi 15 Color", value)

    async def async_set_smart_cursor_color(self, value: 'iterm2.color.Color'):
        """Sets the smart cursor color.

        :param value: A :class:`Color`"""
        return await self._async_simple_set("Smart Cursor Color", value)

    async def async_set_tab_color(self, value: 'iterm2.color.Color'):
        """Sets the tab color.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Tab Color", value)

    async def async_set_underline_color(self, value: 'iterm2.color.Color'):
        """Sets the underline color.

        :param value: A :class:`Color` or None"""
        return await self._async_color_set("Underline Color", value)

    async def async_set_cursor_guide_color(self, value: 'iterm2.color.Color'):
        """Sets the cursor guide color. The alpha value is respected.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Cursor Guide Color", value)

    async def async_set_badge_color(self, value: 'iterm2.color.Color'):
        """Sets the badge color. The alpha value is respected.

        :param value: A :class:`Color`"""
        return await self._async_color_set("Badge Color", value)

    async def async_set_name(self, value: str):
        """Sets the name.

        :param value: A string"""
        return await self._async_simple_set("Name", value)

    async def async_set_badge_text(self, value: 'iterm2.color.Color'):
        """Sets the badge text.

        :param value: A :class:`Color`"""
        return await self._async_simple_set("Badge Text", value)

    async def async_set_answerback_string(self, value: str):
        """Sets the answerback string.

        :param value: A string"""
        return await self._async_simple_set("Answerback String", value)

    async def async_set_use_cursor_guide(self, value: bool):
        """Sets whether the cursor guide should be used.

        :param value: A boolean"""
        return await self._async_simple_set("Use Cursor Guide", value)

    async def async_set_use_tab_color(self, value: str):
        """Sets whether the tab color should be used.

        :param value: A string"""
        return await self._async_simple_set("Use Tab Color", value)

    async def async_set_use_underline_color(self, value: 'iterm2.color.Color'):
        """Sets the underline color.

        :param value: A :class:`Color`"""
        return await self._async_simple_set("Use Underline Color", value)

    async def async_set_minimum_contrast(self, value: float):
        """Sets the minimum contrast.

        :param value: A float in 0 to 1"""
        return await self._async_simple_set("Minimum Contrast", value)

    async def async_set_cursor_boost(self, value: float):
        """Sets the cursor boost level.

        :param value: A float in 0 to 1"""
        return await self._async_simple_set("Cursor Boost", value)

    async def async_set_blinking_cursor(self, value: bool):
        """Sets whether the cursor blinks.

        :param value: A bool"""
        return await self._async_simple_set("Blinking Cursor", value)

    async def async_set_use_bold_font(self, value: bool):
        """Sets whether to use the bold variant of the font for bold text.

        :param value: A bool"""
        return await self._async_simple_set("Use Bold Font", value)

    async def async_set_ascii_ligatures(self, value: bool):
        """Sets whether ligatures should be used for ASCII text.

        :param value: A bool"""
        return await self._async_simple_set("ASCII Ligatures", value)

    async def async_set_non_ascii_ligatures(self, value: bool):
        """Sets whether ligatures should be used for non-ASCII text.

        :param value: A bool"""
        return await self._async_simple_set("Non-ASCII Ligatures", value)

    async def async_set_use_bright_bold(self, value: bool):
        """Sets whether bright colors should be used for bold text.

        :param value: A bool"""
        return await self._async_simple_set("Use Bright Bold", value)

    async def async_set_blink_allowed(self, value: bool):
        """Sets whether blinking text is allowed.

        :param value: A bool"""
        return await self._async_simple_set("Blink Allowed", value)

    async def async_set_use_italic_font(self, value: bool):
        """Sets whether italic text is allowed.

        :param value: A bool"""
        return await self._async_simple_set("Use Italic Font", value)

    async def async_set_ambiguous_double_width(self, value: bool):
        """Sets whether ambiguous-width text should be treated as double-width.

        :param value: A bool"""
        return await self._async_simple_set("Ambiguous Double Width", value)

    async def async_set_horizontal_spacing(self, value: float):
        """Sets the fraction of horizontal spacing.

        :param value: A float at least 0"""
        return await self._async_simple_set("Horizontal Spacing", value)

    async def async_set_vertical_spacing(self, value: float):
        """Sets the fraction of vertical spacing.

        :param value: A float at least 0"""
        return await self._async_simple_set("Vertical Spacing", value)

    async def async_set_use_non_ascii_font(self, value: bool):
        """Sets whether to use a different font for non-ASCII text.

        :param value: A bool"""
        return await self._async_simple_set("Use Non-ASCII Font", value)

    async def async_set_transparency(self, value: float):
        """Sets the level of transparency.

        :param value: A float between 0 and 1"""
        return await self._async_simple_set("Transparency", value)

    async def async_set_blur(self, value: bool):
        """Sets whether background blur should be enabled.

        :param value: A bool"""
        return await self._async_simple_set("Blur", value)

    async def async_set_blur_radius(self, value: float):
        """Sets the blur radius (how blurry). Requires blur to be enabled.

        :param value: A float between 0 and 30"""
        return await self._async_simple_set("Blur Radius", value)

    async def async_set_background_image_mode(self, value: BackgroundImageMode):
        """Sets how the background image is draw.

        :param value: The new value."""
        return await self._async_simple_set("Background Image Mode", value)

    async def async_set_blend(self, value: float):
        """Sets how much the default background color gets blended with the background image.

        .. seealso:: Example ":ref:`blending_example`"

        :param value: A float in 0 to 1"""
        return await self._async_simple_set("Blend", value)

    async def async_set_sync_title(self, value: bool):
        """Sets whether the profile name stays in the tab title, even if changed by an escape
        sequence.

        :param value: A bool"""
        return await self._async_simple_set("Sync Title", value)

    async def async_set_disable_window_resizing(self, value: bool):
        """Sets whether the terminal can resize the window with an escape sequence.

        :param value: A bool"""
        return await self._async_simple_set("Disable Window Resizing", value)

    async def async_set_only_the_default_bg_color_uses_transparency(self, value: bool):
        """Sets whether window transparency shows through non-default background colors.

        :param value: A bool"""
        return await self._async_simple_set("Only The Default BG Color Uses Transparency", value)

    async def async_set_ascii_anti_aliased(self, value: bool):
        """Sets whether ASCII text is anti-aliased.

        :param value: A bool"""
        return await self._async_simple_set("ASCII Anti Aliased", value)

    async def async_set_non_ascii_anti_aliased(self, value: bool):
        """Sets whether non-ASCII text is anti-aliased.

        :param value: A bool"""
        return await self._async_simple_set("Non-ASCII Anti Aliased", value)

    async def async_set_scrollback_lines(self, value: int):
        """Sets the number of scrollback lines.

        :param value: An int at least 0"""
        return await self._async_simple_set("Scrollback Lines", value)

    async def async_set_unlimited_scrollback(self, value: bool):
        """Sets whether the scrollback buffer's length is unlimited.

        :param value: A bool"""
        return await self._async_simple_set("Unlimited Scrollback", value)

    async def async_set_scrollback_with_status_bar(self, value: bool):
        """Sets whether text gets appended to scrollback when there is an app status bar

        :param value: A bool"""
        return await self._async_simple_set("Scrollback With Status Bar", value)

    async def async_set_scrollback_in_alternate_screen(self, value: bool):
        """Sets whether text gets appended to scrollback in alternate screen mode

        :param value: A bool"""
        return await self._async_simple_set("Scrollback in Alternate Screen", value)

    async def async_set_mouse_reporting(self, value: bool):
        """Sets whether mouse reporting is allowed

        :param value: A bool"""
        return await self._async_simple_set("Mouse Reporting", value)

    async def async_set_mouse_reporting_allow_mouse_wheel(self, value: bool):
        """Sets whether mouse reporting reports the mouse wheel's movements.

        :param value: A bool"""
        return await self._async_simple_set("Mouse Reporting allow mouse wheel", value)

    async def async_set_allow_title_reporting(self, value: bool):
        """Sets whether the session title can be reported

        :param value: A bool"""
        return await self._async_simple_set("Allow Title Reporting", value)

    async def async_set_allow_title_setting(self, value: bool):
        """Sets whether the session title can be changed by escape sequence

        :param value: A bool"""
        return await self._async_simple_set("Allow Title Setting", value)

    async def async_set_disable_printing(self, value: bool):
        """Sets whether printing by escape sequence is disabled.

        :param value: A bool"""
        return await self._async_simple_set("Disable Printing", value)

    async def async_set_disable_smcup_rmcup(self, value: bool):
        """Sets whether alternate screen mode is disabled

        :param value: A bool"""
        return await self._async_simple_set("Disable Smcup Rmcup", value)

    async def async_set_silence_bell(self, value: bool):
        """Sets whether the bell makes noise.

        :param value: A bool"""
        return await self._async_simple_set("Silence Bell", value)

    async def async_set_bm_growl(self, value: bool):
        """Sets whether notifications should be shown.

        :param value: A bool"""
        return await self._async_simple_set("BM Growl", value)

    async def async_set_send_bell_alert(self, value: bool):
        """Sets whether notifications should be shown for the bell ringing

        :param value: A bool"""
        return await self._async_simple_set("Send Bell Alert", value)

    async def async_set_send_idle_alert(self, value: bool):
        """Sets whether notifications should be shown for becoming idle

        :param value: A bool"""
        return await self._async_simple_set("Send Idle Alert", value)

    async def async_set_send_new_output_alert(self, value: bool):
        """Sets whether notifications should be shown for new output

        :param value: A bool"""
        return await self._async_simple_set("Send New Output Alert", value)

    async def async_set_send_session_ended_alert(self, value: bool):
        """Sets whether notifications should be shown for a session ending

        :param value: A bool"""
        return await self._async_simple_set("Send Session Ended Alert", value)

    async def async_set_send_terminal_generated_alerts(self, value: bool):
        """Sets whether notifications should be shown for escape-sequence originated notifications

        :param value: A bool"""
        return await self._async_simple_set("Send Terminal Generated Alerts", value)

    async def async_set_flashing_bell(self, value: bool):
        """Sets whether the bell should flash the screen

        :param value: A bool"""
        return await self._async_simple_set("Flashing Bell", value)

    async def async_set_visual_bell(self, value: bool):
        """Sets whether a bell should be shown when the bell rings

        :param value: A bool"""
        return await self._async_simple_set("Visual Bell", value)

    async def async_set_close_sessions_on_end(self, value: bool):
        """Sets whether the session should close when it ends.

        :param value: A bool"""
        return await self._async_simple_set("Close Sessions On End", value)

    async def async_set_prompt_before_closing(self, value: bool):
        """Sets whether the session should prompt before closign

        :param value: A bool"""
        return await self._async_simple_set("Prompt Before Closing 2", value)

    async def async_set_session_close_undo_timeout(self, value: float):
        """Sets amount of time you can undo closing a session

        :param value: A float at least 0"""
        return await self._async_simple_set("Session Close Undo Timeout", value)

    async def async_set_reduce_flicker(self, value: bool):
        """Sets whether the flicker fixer is on.

        :param value: A bool"""
        return await self._async_simple_set("Reduce Flicker", value)

    async def async_set_send_code_when_idle(self, value: bool):
        """Sets whether to send a code when idle

        :param value: A bool"""
        return await self._async_simple_set("Send Code When Idle", value)

    async def async_set_application_keypad_allowed(self, value: bool):
        """Sets whether the terminal may be placed in application keypad mode

        :param value: A bool"""
        return await self._async_simple_set("Application Keypad Allowed", value)

    async def async_set_place_prompt_at_first_column(self, value: bool):
        """Sets whether the prompt should always begin at the first column (requires shell
        integration)

        :param value: A bool"""
        return await self._async_simple_set("Place Prompt at First Column", value)

    async def async_set_show_mark_indicators(self, value: bool):
        """Sets whether mark indicators should be visible

        :param value: A bool"""
        return await self._async_simple_set("Show Mark Indicators", value)

    async def async_set_idle_code(self, value: int):
        """Sets the ASCII code to send on idle

        :param value: An int in 0...255"""
        return await self._async_simple_set("Idle Code", value)

    async def async_set_idle_period(self, value: float):
        """Sets how often to send a code when idle

        :param value: A float at least 0"""
        return await self._async_simple_set("Idle Period", value)

    async def async_set_unicode_version(self, value: bool):
        """Sets the unicode version for wcwidth

        :param value: A bool"""
        return await self._async_simple_set("Unicode Version", value)

    async def async_set_cursor_type(self, value: CursorType):
        """Sets the cursor type

        :param value: The new value."""
        return await self._async_simple_set("Cursor Type", value)

    async def async_set_thin_strokes(self, value: ThinStrokes):
        """Sets whether thin strokes are used.

        :param value: The new value."""
        return await self._async_simple_set("Thin Strokes", value)

    async def async_set_unicode_normalization(self, value: UnicodeNormalization):
        """Sets the unicode normalization form to use

        :param value: The new value."""
        return await self._async_simple_set("Unicode Normalization", value)

    async def async_set_character_encoding(self, value: CharacterEncoding):
        """Sets the character encoding

        :param value: The new value."""
        return await self._async_simple_set("Character Encoding", value)

    async def async_set_left_option_key_sends(self, value: OptionKeySends):
        """Sets the behavior of the left option key.

        :param value: The new value."""
        return await self._async_simple_set("Option Key Sends", value)

    async def async_set_right_option_key_sends(self, value: OptionKeySends):
        """Sets the behavior of the right option key.

        :param value: The new value."""
        return await self._async_simple_set("Right Option Key Sends", value)

    async def async_set_triggers(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """Sets the triggers.

        :param value: A list of dicts of trigger definitions."""
        return await self._async_simple_set("Triggers", value)

    async def async_set_smart_selection_rules(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """Sets the smart selection rules.

        :param value: A list of dicts of smart selection rules"""
        return await self._async_simple_set("Smart Selection Rules", value)

    async def async_set_semantic_history(self, value: typing.Dict[str, typing.Any]):
        """Sets the semantic history prefs.

        :param value: Semantic history settings dict."""
        return await self._async_simple_set("Semantic History", value)

    async def async_set_automatic_profile_switching_rules(self, value: typing.List[str]):
        """Sets the automatic profile switching rules.

        :param value: A list of rules (strings)."""
        return await self._async_simple_set("Bound Hosts", value)

    async def async_set_advanced_working_directory_window_setting(self, value: InitialWorkingDirectory):
        """Sets the advanced working directory window setting.

        :param value: New value. Excludes Advanced."""
        return await self._async_simple_set("AWDS Window Option", value)

    async def async_set_advanced_working_directory_window_directory(self, value: str):
        """Sets the advanced working directory window directory.

        :param value: Path."""
        return await self._async_simple_set("AWDS Window Directory", value)

    async def async_set_advanced_working_directory_tab_setting(self, value: InitialWorkingDirectory):
        """Sets the advanced working directory tab setting.

        :param value: New value. Excludes Advanced."""
        return await self._async_simple_set("AWDS Tab Option", value)

    async def async_set_advanced_working_directory_tab_directory(self, value: str):
        """Sets the advanced working directory tab directory.

        :param value: Path."""
        return await self._async_simple_set("AWDS Tab Directory", value)

    async def async_set_advanced_working_directory_pane_setting(self, value: InitialWorkingDirectory):
        """Sets the advanced working directory pane setting.

        :param value: New value. Excludes Advanced."""
        return await self._async_simple_set("AWDS Pane Option", value)

    async def async_set_advanced_working_directory_pane_directory(self, value: str):
        """Sets the advanced working directory pane directory.

        :param value: Path."""
        return await self._async_simple_set("AWDS Pane Directory", value)

    async def async_set_normal_font(self, value: str):
        """Sets the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii.

        :param value: Font name and size as a string."""
        return await self._async_simple_set("Normal Font", value)

    async def async_set_non_ascii_font(self, value: str):
        """Sets the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.

        :param value: Font name and size as a string."""
        return await self._async_simple_set("Non Ascii Font", value)

    async def async_set_background_image_location(self, value: str):
        """Sets path to the background image.

        :param value: Path."""
        return await self._async_simple_set("Background Image Location", value)

    async def async_set_key_mappings(self, value: typing.Dict[str, typing.Any]):
        """Sets the keyboard shortcuts.

        :param value: Dictionary mapping keystroke to action."""
        return await self._async_simple_set("Keyboard Map", value)

    async def async_set_touchbar_mappings(self, value: typing.Dict[str, typing.Any]):
        """Sets the touchbar actions.

        :param value: Dictionary mapping touch bar item to action."""
        return await self._async_simple_set("Touch Bar Map", value)

    async def async_set_use_custom_command(self, value: str):
        """"Sets whether to use a custom command when the session is created.

        :param value: The string "Yes" or "No".
        """
        return await self._async_simple_set("Custom Command", value)

    async def async_set_command(self, value: str):
        """"The command to run when the session starts.

        custom_command must be set to "Yes" or this will be ignored.

        :param value: A string giving the command to run.
        """
        return await self._async_simple_set("Command", value)

    async def async_set_initial_directory_mode(self, value: InitialWorkingDirectory):
        """Sets whether to use a custom (not home) initial working directory.

        :param value: The new value.
        """
        return await self._async_simple_set("Custom Directory", value.value)

    async def async_set_custom_directory(self, value: str):
        """Sets the initial working directory.

        The initial_directory_mode must be set to "Yes" for this to take effect.

        :param value: The path to use.
        """
        return await self._async_simple_set("Working Directory", value)

    async def async_set_icon_mode(self, value: IconMode):
        """Sets the icon mode.

        :param value: The icon mode.
        """
        return await self._async_simple_set("Icon", value.value)

    async def async_set_custom_icon_path(self, value: str):
        """Sets the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.
        """
        return await self._async_simple_set("Custom Icon Path", value)

    async def async_set_title_components(self, value: typing.List[TitleComponents]):
        """Sets which components are visible in the session's title, or selects a custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        n = 0
        for c in value:
            n += c.value
        return await self._async_simple_set("Title Components", n)

    async def async_set_title_function(self, display_name: str, identifier: str):
        """Sets the function call for the session title provider and its display name for the UI.

        :param display_name: This is shown in the Title Components menu in the UI.
        :identifier: The unique identifier, typically a backwards domain name.

        This takes effect only when the title_components property is set to `CUSTOM`.
        """
        return await self._async_simple_set("Title Function", [display_name, identifier])

    async def async_set_badge_top_margin(self, value: int):
        """Sets the top margin of the badge.

        :param value: The new value in points.
        """
        return await self._async_simple_set("Badge Top Margin", value)

    async def async_set_badge_right_margin(self, value: int):
        """Sets the right margin of the badge.

        :param value: The new value in points.
        """
        return await self._async_simple_set("Badge Right Margin", value)

    async def async_set_badge_max_width(self, value: int):
        """Sets the max width of the badge.

        :param value: The new value in points.
        """
        return await self._async_simple_set("Badge Max Width", value)

    async def async_set_badge_max_height(self, value: int):
        """Sets the max height of the badge.

        :param value: The new value in points.
        """
        return await self._async_simple_set("Badge Max Height", value)


    async def async_set_badge_font(self, value: str):
        """Sets the font of the badge.

        :param value: The new font name, like "Helvetica"
        """
        return await self._async_simple_set("Badge Font", value)

    async def async_set_use_custom_window_title(self, value: bool):
        """Sets whether the custom window title is used.

        :param value: Should the custom window title in the profile be used?
        """
        return await self._async_simple_set("Use Custom Window Title", value)

    async def async_set_custom_window_title(self, value: str):
        """Sets the custom window title.

        This will only be used if use_custom_window_title is True.

        :param value: The new value. An interpolated string.
        """
        return await self._async_simple_set("Custom Window Title", value)

    async def async_set_use_transparency_initially(self, value: bool):
        """Should a window created with this profile respect the transparency setting?

        :param value: If True, use transparency; if False, force the window to be opaque (but it can be toggled with View > Use Transparency).
        """
        return await self._async_simple_set("Initial Use Transparency", value)

    async def async_set_status_bar_enabled(self, value: bool):
        """Should the status bar be enabled?

        :param value: If True, the status bar will be shown.
        """
        return await self._async_simple_set("Show Status Bar", value)

    async def async_set_use_csi_u(self, value: bool):
        """Report keystrokes with CSI u protocol?

        :param value: If True, CSI u will be enabled.
        """
        return await self._async_simple_set("Use libtickit protocol", value)

    async def async_set_triggers_use_interpolated_strings(self, value: bool):
        """Should trigger parameters be interpreted as interpolated strings?
        """
        return await self._async_simple_set("Triggers Use Interpolated Strings", value)

class Profile(WriteOnlyProfile):
    """Represents a profile.

    If a session_id is set then this is the profile attached to a session.
    Otherwise, it is a shared profile."""

    USE_CUSTOM_COMMAND_ENABLED = "Yes"
    USE_CUSTOM_COMMAND_DISABLED = "No"

    @staticmethod
    async def async_get(connection, guids=None) -> typing.List['Profile']:
        """Fetches all profiles with the specified GUIDs.

        :param guids: The profiles to get, or if `None` then all will be returned.

        :returns: A list of :class:`Profile` objects.
        """
        response = await iterm2.rpc.async_list_profiles(connection, guids, None)
        profiles = []
        for responseProfile in response.list_profiles_response.profiles:
            profile = Profile(None, connection, responseProfile.properties)
            profiles.append(profile)
        return profiles


    def __init__(self, session_id, connection, profile_property_list):
        props = {}
        for prop in profile_property_list:
            props[prop.key] = json.loads(prop.json_value)

        guid_key = "Guid"
        if guid_key in props:
            guid = props[guid_key]
        else:
            guid = None

        super().__init__(session_id, connection, guid)

        self.connection = connection
        self.session_id = session_id
        self.__props = props

    def _simple_get(self, key):
        if key in self.__props:
            return self.__props[key]
        else:
            return None

    def _get_optional_bool(self, key):
        if key not in self.__props:
            return None
        return bool(self.__props[key])

    def get_color_with_key(self, key):
        """Returns the color for the request key, or None.

        :param key: A string describing the color. Corresponds to the keys in :class:`~iterm2.ColorPreset.Color`.

        :returns: Either a :class:`~iterm2.color.Color` or `None`.
        """
        try:
            color = iterm2.color.Color()
            color.from_dict(self.__props[key])
            return color
        except ValueError:
            return None
        except KeyError:
            return None

    @property
    def all_properties(self):
        return dict(self.__props)

    @property
    def foreground_color(self):
        """Returns the foreground color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Foreground Color")

    @property
    def background_color(self):
        """Returns the background color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Background Color")

    @property
    def bold_color(self):
        """Returns the bold text color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Bold Color")

    @property
    def link_color(self):
        """Returns the link color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Link Color")

    @property
    def selection_color(self):
        """Returns the selection background color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Selection Color")

    @property
    def selected_text_color(self):
        """Returns the selection text color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Selected Text Color")

    @property
    def cursor_color(self):
        """Returns the cursor color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Cursor Color")

    @property
    def cursor_text_color(self):
        """Returns the cursor text color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Cursor Text Color")

    @property
    def ansi_0_color(self):
        """Returns the ANSI 0 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 0 Color")

    @property
    def ansi_1_color(self):
        """Returns the ANSI 1 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 1 Color")

    @property
    def ansi_2_color(self):
        """Returns the ANSI 2 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 2 Color")

    @property
    def ansi_3_color(self):
        """Returns the ANSI 3 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 3 Color")

    @property
    def ansi_4_color(self):
        """Returns the ANSI 4 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 4 Color")

    @property
    def ansi_5_color(self):
        """Returns the ANSI 5 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 5 Color")

    @property
    def ansi_6_color(self):
        """Returns the ANSI 6 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 6 Color")

    @property
    def ansi_7_color(self):
        """Returns the ANSI 7 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 7 Color")

    @property
    def ansi_8_color(self):
        """Returns the ANSI 8 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 8 Color")

    @property
    def ansi_9_color(self):
        """Returns the ANSI 9 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 9 Color")

    @property
    def ansi_10_color(self):
        """Returns the ANSI 10 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 10 Color")

    @property
    def ansi_11_color(self):
        """Returns the ANSI 11 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 11 Color")

    @property
    def ansi_12_color(self):
        """Returns the ANSI 12 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 12 Color")

    @property
    def ansi_13_color(self):
        """Returns the ANSI 13 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 13 Color")

    @property
    def ansi_14_color(self):
        """Returns the ANSI 14 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 14 Color")

    @property
    def ansi_15_color(self):
        """Returns the ANSI 15 color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Ansi 15 Color")

    @property
    def smart_cursor_color(self):
        """Returns whether smart cursor color is in use for box cursors.

        :returns: A :class:`Color`"""
        return self._simple_get("Smart Cursor Color")

    @property
    def tab_color(self):
        """Returns the tab color.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Tab Color")

    @property
    def underline_color(self):
        """Returns the underline color.

        :returns: A :class:`Color` or None"""
        return self.get_color_with_key("Underline Color")

    @property
    def cursor_guide_color(self):
        """Returns the cursor guide color. The alpha value is respected.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Cursor Guide Color")

    @property
    def badge_color(self):
        """Returns the badge color. The alpha value is respected.

        :returns: A :class:`Color`"""
        return self.get_color_with_key("Badge Color")

    @property
    def name(self):
        """Returns the name.

        :returns: A string"""
        return self._simple_get("Name")

    @property
    def badge_text(self):
        """Returns the badge text.

        :returns: A :class:`Color`"""
        return self._simple_get("Badge Text")

    @property
    def answerback_string(self):
        """Returns the answerback string.

        :returns: A string"""
        return self._simple_get("Answerback String")

    @property
    def use_cursor_guide(self):
        """Returns whether the cursor guide should be used.

        :returns: A boolean"""
        return self._simple_get("Use Cursor Guide")

    @property
    def use_tab_color(self):
        """Returns whether the tab color should be used.

        :returns: A string"""
        return self._simple_get("Use Tab Color")

    @property
    def use_underline_color(self):
        """Returns the underline color.

        :returns: A :class:`Color`"""
        return self._simple_get("Use Underline Color")

    @property
    def minimum_contrast(self):
        """Returns the minimum contrast.

        :returns: A float in 0 to 1"""
        return self._simple_get("Minimum Contrast")

    @property
    def cursor_boost(self):
        """Returns the cursor boost level.

        :returns: A float in 0 to 1"""
        return self._simple_get("Cursor Boost")

    @property
    def blinking_cursor(self):
        """Returns whether the cursor blinks.

        :returns: A bool"""
        return self._simple_get("Blinking Cursor")

    @property
    def use_bold_font(self):
        """Returns whether to use the bold variant of the font for bold text.

        :returns: A bool"""
        return self._simple_get("Use Bold Font")

    @property
    def ascii_ligatures(self):
        """Returns whether ligatures should be used for ASCII text.

        :returns: A bool"""
        return self._simple_get("ASCII Ligatures")

    @property
    def non_ascii_ligatures(self):
        """Returns whether ligatures should be used for non-ASCII text.

        :returns: A bool"""
        return self._simple_get("Non-ASCII Ligatures")

    @property
    def use_bright_bold(self):
        """Returns whether bright colors should be used for bold text.

        :returns: A bool"""
        return self._simple_get("Use Bright Bold")

    @property
    def blink_allowed(self):
        """Returns whether blinking text is allowed.

        :returns: A bool"""
        return self._simple_get("Blink Allowed")

    @property
    def use_italic_font(self):
        """Returns whether italic text is allowed.

        :returns: A bool"""
        return self._simple_get("Use Italic Font")

    @property
    def ambiguous_double_width(self):
        """Returns whether ambiguous-width text should be treated as double-width.

        :returns: A bool"""
        return self._simple_get("Ambiguous Double Width")

    @property
    def horizontal_spacing(self):
        """Returns the fraction of horizontal spacing.

        :returns: A float at least 0"""
        return self._simple_get("Horizontal Spacing")

    @property
    def vertical_spacing(self):
        """Returns the fraction of vertical spacing.

        :returns: A float at least 0"""
        return self._simple_get("Vertical Spacing")

    @property
    def use_non_ascii_font(self):
        """Returns whether to use a different font for non-ASCII text.

        :returns: A bool"""
        return self._simple_get("Use Non-ASCII Font")

    @property
    def transparency(self):
        """Returns the level of transparency.

        :returns: A float between 0 and 1"""
        return self._simple_get("Transparency")

    @property
    def blur(self):
        """Returns whether background blur should be enabled.

        :returns: A bool"""
        return self._simple_get("Blur")

    @property
    def blur_radius(self):
        """Returns the blur radius (how blurry). Requires blur to be enabled.

        :returns: A float between 0 and 30"""
        return self._simple_get("Blur Radius")

    @property
    def background_image_mode(self):
        """Returns how the background image is drawn

        :returns: A `BackgroundImageMode`"""
        return BackgroundImageMode(self._simple_get("Background Image Mode"))

    @property
    def blend(self):
        """Returns tow much the default background color gets blended with the background image.

        :returns: A float in 0 to 1"""
        return self._simple_get("Blend")

    @property
    def sync_title(self):
        """Returns whether the profile name stays in the tab title, even if changed by an escape
        sequence.

        :returns: A bool"""
        return self._simple_get("Sync Title")

    @property
    def disable_window_resizing(self):
        """Returns whether the terminal can resize the window with an escape sequence.

        :returns: A bool"""
        return self._simple_get("Disable Window Resizing")

    @property
    def only_the_default_bg_color_uses_transparency(self):
        """Returns whether window transparency shows through non-default background colors.

        :returns: A bool"""
        return self._simple_get("Only The Default BG Color Uses Transparency")

    @property
    def ascii_anti_aliased(self):
        """Returns whether ASCII text is anti-aliased.

        :returns: A bool"""
        return self._simple_get("ASCII Anti Aliased")

    @property
    def non_ascii_anti_aliased(self):
        """Returns whether non-ASCII text is anti-aliased.

        :returns: A bool"""
        return self._simple_get("Non-ASCII Anti Aliased")

    @property
    def scrollback_lines(self):
        """Returns the number of scrollback lines.

        :returns: An int at least 0"""
        return self._simple_get("Scrollback Lines")

    @property
    def unlimited_scrollback(self):
        """Returns whether the scrollback buffer's length is unlimited.

        :returns: A bool"""
        return self._simple_get("Unlimited Scrollback")

    @property
    def scrollback_with_status_bar(self):
        """Returns whether text gets appended to scrollback when there is an app status bar

        :returns: A bool"""
        return self._simple_get("Scrollback With Status Bar")

    @property
    def scrollback_in_alternate_screen(self):
        """Returns whether text gets appended to scrollback in alternate screen mode

        :returns: A bool"""
        return self._simple_get("Scrollback in Alternate Screen")

    @property
    def mouse_reporting(self):
        """Returns whether mouse reporting is allowed

        :returns: A bool"""
        return self._simple_get("Mouse Reporting")

    @property
    def mouse_reporting_allow_mouse_wheel(self):
        """Returns whether mouse reporting reports the mouse wheel's movements.

        :returns: A bool"""
        return self._simple_get("Mouse Reporting allow mouse wheel")

    @property
    def allow_title_reporting(self):
        """Returns whether the session title can be reported

        :returns: A bool"""
        return self._simple_get("Allow Title Reporting")

    @property
    def allow_title_setting(self):
        """Returns whether the session title can be changed by escape sequence

        :returns: A bool"""
        return self._simple_get("Allow Title Setting")

    @property
    def disable_printing(self):
        """Returns whether printing by escape sequence is disabled.

        :returns: A bool"""
        return self._simple_get("Disable Printing")

    @property
    def disable_smcup_rmcup(self):
        """Returns whether alternate screen mode is disabled

        :returns: A bool"""
        return self._simple_get("Disable Smcup Rmcup")

    @property
    def silence_bell(self):
        """Returns whether the bell makes noise.

        :returns: A bool"""
        return self._simple_get("Silence Bell")

    @property
    def bm_growl(self):
        """Returns whether notifications should be shown.

        :returns: A bool"""
        return self._simple_get("BM Growl")

    @property
    def send_bell_alert(self):
        """Returns whether notifications should be shown for the bell ringing

        :returns: A bool"""
        return self._simple_get("Send Bell Alert")

    @property
    def send_idle_alert(self):
        """Returns whether notifications should be shown for becoming idle

        :returns: A bool"""
        return self._simple_get("Send Idle Alert")

    @property
    def send_new_output_alert(self):
        """Returns whether notifications should be shown for new output

        :returns: A bool"""
        return self._simple_get("Send New Output Alert")

    @property
    def send_session_ended_alert(self):
        """Returns whether notifications should be shown for a session ending

        :returns: A bool"""
        return self._simple_get("Send Session Ended Alert")

    @property
    def send_terminal_generated_alerts(self):
        """Returns whether notifications should be shown for escape-sequence originated
        notifications

        :returns: A bool"""
        return self._simple_get("Send Terminal Generated Alerts")

    @property
    def flashing_bell(self):
        """Returns whether the bell should flash the screen

        :returns: A bool"""
        return self._simple_get("Flashing Bell")

    @property
    def visual_bell(self):
        """Returns whether a bell should be shown when the bell rings

        :returns: A bool"""
        return self._simple_get("Visual Bell")

    @property
    def close_sessions_on_end(self):
        """Returns whether the session should close when it ends.

        :returns: A bool"""
        return self._simple_get("Close Sessions On End")

    @property
    def prompt_before_closing(self):
        """Returns whether the session should prompt before closign

        :returns: A bool"""
        return self._simple_get("Prompt Before Closing 2")

    @property
    def session_close_undo_timeout(self):
        """Returns tmount of time you can undo closing a session

        :returns: A float at least 0"""
        return self._simple_get("Session Close Undo Timeout")

    @property
    def reduce_flicker(self):
        """Returns whether the flicker fixer is on.

        :returns: A bool"""
        return self._simple_get("Reduce Flicker")

    @property
    def send_code_when_idle(self):
        """Returns whether to send a code when idle

        :returns: A bool"""
        return self._simple_get("Send Code When Idle")

    @property
    def application_keypad_allowed(self):
        """Returns whether the terminal may be placed in application keypad mode

        :returns: A bool"""
        return self._simple_get("Application Keypad Allowed")

    @property
    def place_prompt_at_first_column(self):
        """Returns whether the prompt should always begin at the first column (requires shell
        integration)

        :returns: A bool"""
        return self._simple_get("Place Prompt at First Column")

    @property
    def show_mark_indicators(self):
        """Returns whether mark indicators should be visible

        :returns: A bool"""
        return self._simple_get("Show Mark Indicators")

    @property
    def idle_code(self):
        """Returns the ASCII code to send on idle

        :returns: An int in 0...255"""
        return self._simple_get("Idle Code")

    @property
    def idle_period(self):
        """Returns how often to send a code when idle

        :returns: A float at least 0"""
        return self._simple_get("Idle Period")

    @property
    def unicode_version(self):
        """Returns the unicode version for wcwidth

        :returns: A bool"""
        return self._simple_get("Unicode Version")

    @property
    def cursor_type(self) -> CursorType:
        """Returns the cursor type."""
        return self._simple_get("Cursor Type")

    @property
    def thin_strokes(self) -> ThinStrokes:
        """Returns whether thin strokes are used.

        :returns: THIN_STROKES_SETTING_xxx"""
        return self._simple_get("Thin Strokes")

    @property
    def unicode_normalization(self):
        """Returns the unicode normalization form to use

        :returns: UNICODE_NORMALIZATION_xxx"""
        return self._simple_get("Unicode Normalization")

    @property
    def character_encoding(self):
        """Returns the character encoding

        :returns: CHARACTER_ENCODING_xxx"""
        return self._simple_get("Character Encoding")

    @property
    def left_option_key_sends(self):
        """Returns the behavior of the left option key.

        :returns: OPTION_KEY_xxx"""
        return self._simple_get("Option Key Sends")

    @property
    def right_option_key_sends(self):
        """Returns the behavior of the right option key.

        :returns: OPTION_KEY_xxx"""
        return self._simple_get("Right Option Key Sends")

    @property
    def guid(self):
        """Returns globally unique ID for this profile.

        :returns: A string identifying this profile"""
        return self._simple_get("Guid")

    @property
    def triggers(self) -> typing.List[typing.Dict[str, typing.Any]]:
        """The triggers.

        :returns: A list of dicts of trigger definitions."""
        return self._simple_get("Triggers")

    @property
    def smart_selection_rules(self) -> typing.List[typing.Dict[str, typing.Any]]:
        """The smart selection rules.

        :returns: A list of dicts of smart selection rules"""
        return self._simple_get("Smart Selection Rules")

    @property
    def semantic_history(self) -> typing.Dict[str, typing.Any]:
        """The semantic history prefs.

        :returns: Semantic history settings dict."""
        return self._simple_get("Semantic History")

    @property
    def automatic_profile_switching_rules(self) -> typing.List[str]:
        """The automatic profile switching rules.

        :returns: A list of rules (strings)."""
        return self._simple_get("Bound Hosts")

    @property
    def advanced_working_directory_window_setting(self):
        """The advanced working directory window setting.

        :returns: INITIAL_WORKING_DIRECTORY_xxx, excluding ADVANCED."""
        return self._simple_get("AWDS Window Option")

    @property
    def advanced_working_directory_window_directory(self):
        """The advanced working directory window directory.

        :returns: Path."""
        return self._simple_get("AWDS Window Directory")

    @property
    def advanced_working_directory_tab_setting(self):
        """The advanced working directory tab setting.

        :returns: INITIAL_WORKING_DIRECTORY_xxx, excluding ADVANCED."""
        return self._simple_get("AWDS Tab Option")

    @property
    def advanced_working_directory_tab_directory(self):
        """The advanced working directory tab directory.

        :returns: Path."""
        return self._simple_get("AWDS Tab Directory")

    @property
    def advanced_working_directory_pane_setting(self):
        """The advanced working directory pane setting.

        :returns: INITIAL_WORKING_DIRECTORY_xxx, excluding ADVANCED."""
        return self._simple_get("AWDS Pane Option")

    @property
    def advanced_working_directory_pane_directory(self):
        """The advanced working directory pane directory.

        :returns: Path."""
        return self._simple_get("AWDS Pane Directory")

    @property
    def normal_font(self):
        """The normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii.

        :returns: Font name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"
        """
        return self._simple_get("Normal Font")

    @property
    def non_ascii_font(self):
        """The non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.

        :returns: Font name and size as a string."""
        return self._simple_get("Non Ascii Font")

    @property
    def background_image_location(self):
        """Gets path to the background image.

        :returns: Path."""
        return self._simple_get("Background Image Location")

    @property
    def key_mappings(self):
        """The keyboard shortcuts.

        :returns: Dictionary mapping keystroke to action."""
        return self._simple_get("Keyboard Map")

    @property
    def touchbar_mappings(self):
        """The touchbar actions.

        :returns: Dictionary mapping touch bar item to action."""
        return self._simple_get("Touch Bar Map")

    @property
    def original_guid(self):
        """The GUID of the original profile from which this one was derived.

        Used for sessions whose profile has been modified from the underlying
        profile. Otherwise not set.

        :returns: Guid"""
        return self._simple_get("Original Guid")

    @property
    def dynamic_profile_parent_name(self):
        """If the profile is a dynamic profile, returns the name of the parent profile.

        :returns: String name"""
        return self._simple_get("Dynamic Profile Parent Name")

    @property
    def dynamic_profile_file_name(self):
        """If the profile is a dynamic profile, returns the path to the file
        from which it came.

        :returns: String file name"""
        return self._simple_get("Dynamic Profile Filename")

    @property
    def use_custom_command(self):
        """"Returns whether to use a custom command when the session is created.

        :returns: Boolean, whether to use a custom command.
        """
        return self._simple_get("Custom Command")

    @property
    def command(self):
        """"The command to run when the session starts.

        :returns: The command to run, provided `use_custom_command` is `True`.
        """
        return self._simple_get("Command")

    @property
    def initial_directory_mode(self):
        """Returns wether to use a custom (not home) initial working directory.

        :returns: "Yes" to use the `custom_directory`. "No" to use the home directory. "Recycle" to reuse the current directory. "Advanced" to respect advanced working directory settings.
        """
        return self._simple_get("Custom Directory")

    @property
    def custom_directory(self):
        """Returns the initial working directory.

        The initial_directory_mode must be set to "Yes" for this to take effect.

        :returns: The specific directory this profile has been set to start in.
        """
        return self._simple_get("Working Directory")

    @property
    def icon_mode(self) -> IconMode:
        """Returns what kind of icon the session shows.

        :returns: The icon mode.
        """
        return self._simple_get("Icon")

    @property
    def custom_icon_path(self) -> typing.Optional[str]:
        """Returns the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.
        """
        return self._simple_get("Custom Icon Path")

    @property
    def title_components(self) -> typing.Optional[typing.List[TitleComponents]]:
        """Returns which components are visible in the session's title, or selects a custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        l = []
        n = 1
        value = self._simple_get("Title Components")
        while n <= value:
            if (n & value):
                l.append(TitleComponents(n))
            n *= 2
        return l

    @property
    def title_function(self) -> typing.Optional[typing.Tuple[str, str]]:
        """Returns the function call for the session title provider and its display name for the UI.

        :returns: (display name, unique identifier)
        """
        list = self._simple_get("Title Function")
        return (list[0], list[1])

    @property
    def badge_top_margin(self) -> typing.Optional[int]:
        """Returns the top margin of the badge.

        :returns: The new value in points.
        """
        return self._simple_get("Badge Top Margin")

    @property
    def badge_right_margin(self) -> typing.Optional[int]:
        """Returns the right margin of the badge.

        :returns: The new value in points.
        """
        return self._simple_get("Badge Right Margin")

    @property
    def badge_max_width(self) -> typing.Optional[int]:
        """Returns the max width of the badge.

        :returns: The new value in points.
        """
        return self._simple_get("Badge Max Width")

    @property
    def badge_max_height(self) -> typing.Optional[int]:
        """Returns the max height of the badge.

        :returns: The new value in points.
        """
        return self._simple_get("Badge Max Height")


    @property
    def badge_font(self) -> typing.Optional[str]:
        """Returns the font of the badge.

        :returns: The new font name, like "Helvetica"
        """
        return self._simple_get("Badge Font")

    @property
    def use_custom_window_title(self) -> typing.Optional[bool]:
        """Returns whether the custom window title is used.

        :returns: Should the custom window title in the profile be used?
        """
        return self._get_optional_bool("Use Custom Window Title")

    @property
    def custom_window_title(self) -> typing.Optional[str]:
        """Returns the custom window title.

        This will only be used if use_custom_window_title is True.

        :returns: The new value. An interpolated string.
        """
        return self._simple_get("Custom Window Title")

    @property
    def use_transparency_initially(self) -> typing.Optional[bool]:
        """Returns whether a window created with this profile should respect the transparency setting?

        :returns: If True, use transparency; if False, force the window to be opaque (but it can be toggled with View > Use Transparency).
        """
        return self._get_optional_bool("Initial Use Transparency")

    @property
    def status_bar_enabled(self) -> typing.Optional[bool]:
        """Returns whether the status bar should be enabled?

        :returns: If True, the status bar will be shown.
        """
        return self._get_optional_bool("Show Status Bar")

    @property
    def use_csi_u(self) -> typing.Optional[bool]:
        """Returns wehtehr keystrokes will be reported with CSI u protocol

        :returns: If True, CSI u will be enabled.
        """
        return self._get_optional_bool("Use libtickit protocol")

    @property
    def triggers_use_interpolated_strings(self) -> typing.Optional[bool]:
        """Returns whether trigger parameters are interpreted as interpolated strings?
        """
        return self._get_optional_bool("Triggers Use Interpolated Strings")

    async def async_make_default(self):
        """Makes this profile the default profile."""
        await iterm2.rpc.async_set_default_profile(self.connection, self.guid)

class PartialProfile(Profile):
    """Represents a profile that has only a subset of fields available for reading."""

    @staticmethod
    async def async_query(
            connection: iterm2.connection.Connection,
            guids: typing.Optional[typing.List[str]]=None,
            properties: typing.List[str]=["Guid", "Name"]) -> typing.List['PartialProfile']:
        """Fetches a list of profiles by guid, populating the requested properties.

        :param connection: The connection to send the query to.
        :param properties: Lists the properties to fetch. Pass None for all. If you wish to fetch the full profile later, you must ensure the 'Guid' property is fetched.
        :param guids: Lists GUIDs to list. Pass None for all profiles.

        :returns: A list of :class:`PartialProfile` objects with only the specified properties set.

        .. seealso::
            * Example ":ref:`theme_example`"
            * Example ":ref:`darknight_example`"
        """
        response = await iterm2.rpc.async_list_profiles(connection, guids, properties)
        profiles = []
        for responseProfile in response.list_profiles_response.profiles:
            profile = PartialProfile(None, connection, responseProfile.properties)
            profiles.append(profile)
        return profiles

    def __init__(self, session_id, connection, profile_property_list):
        """Initializes a PartialProfile from a profile_property_list protobuf."""
        super().__init__(session_id, connection, profile_property_list)

    async def async_get_full_profile(self) -> Profile:
        """Requests a full profile and returns it.

        Raises BadGUIDException if the Guid is not set or does not match a profile.

        :returns: A :class:`Profile`.

        .. seealso:: Example ":ref:`theme_example`"
        """
        if not self.guid:
            raise BadGUIDException()
        response = await iterm2.rpc.async_list_profiles(self.connection, [self.guid], None)
        if len(response.list_profiles_response.profiles) != 1:
            raise BadGUIDException()
        return Profile(None, self.connection, response.list_profiles_response.profiles[0].properties)

    async def async_make_default(self):
        """Makes this profile the default profile."""
        await iterm2.rpc.async_set_default_profile(self.connection, self.guid)

