
"""
Provides classes for representing, querying, and modifying iTerm2 profiles.
"""
import asyncio
import enum
import json
import typing

import iterm2.capabilities
import iterm2.color
import iterm2.colorpresets
import iterm2.rpc


# pylint: disable=too-many-public-methods
# pylint: disable=too-many-lines
# pylint: disable=line-too-long
class BackgroundImageMode(enum.Enum):
    """Describes how the background image should be accommodated to fit the window."""
    STRETCH = 0  #: Stretch to fit
    TILE = 1  #: Full size, undistorted, and tessellated if needed.
    ASPECT_FILL = 2  #: Scale to fill the space, cropping if needed. Does not distort.
    ASPECT_FIT = 3  #: Scale to fit the space, adding letterboxes or pillarboxes if needed. Does not distort.

    def toJSON(self):
        return json.dumps(self.value)


class BadGUIDException(Exception):
    """Raised when a profile does not have a GUID or the GUID is unknown."""


class CursorType(enum.Enum):
    """Describes the type of the cursor."""
    CURSOR_TYPE_UNDERLINE = 0  #: Underline cursor
    CURSOR_TYPE_VERTICAL = 1  #: Vertical bar cursor
    CURSOR_TYPE_BOX = 2  #: Box cursor

    def toJSON(self):
        return json.dumps(self.value)


class ThinStrokes(enum.Enum):
    """When thin strokes should be used."""
    THIN_STROKES_SETTING_NEVER = 0  #: NEver
    THIN_STROKES_SETTING_RETINA_DARK_BACKGROUNDS_ONLY = 1  #: When the background is dark and the display is a retina display.
    THIN_STROKES_SETTING_DARK_BACKGROUNDS_ONLY = 2  #: When the background is dark.
    THIN_STROKES_SETTING_ALWAYS = 3  #: Always.
    THIN_STROKES_SETTING_RETINA_ONLY = 4  #: When the display is a retina display.

    def toJSON(self):
        return json.dumps(self.value)


class UnicodeNormalization(enum.Enum):
    """How to perform Unicode normalization."""
    UNICODE_NORMALIZATION_NONE = 0  #: Do not modify input
    UNICODE_NORMALIZATION_NFC = 1  #: Normalization form C
    UNICODE_NORMALIZATION_NFD = 2  #: Normalization form D
    UNICODE_NORMALIZATION_HFSPLUS = 3  #: Apple's HFS+ normalization form

    def toJSON(self):
        return json.dumps(self.value)


class CharacterEncoding(enum.Enum):
    """String encodings."""
    CHARACTER_ENCODING_UTF_8 = 4

    def toJSON(self):
        return json.dumps(self.value)


class OptionKeySends(enum.Enum):
    """How should the option key behave?"""
    OPTION_KEY_NORMAL = 0  #: Standard behavior
    OPTION_KEY_META = 1  #: Acts like Meta. Not recommended.
    OPTION_KEY_ESC = 2  #: Adds ESC prefix.

    def toJSON(self):
        return json.dumps(self.value)


class InitialWorkingDirectory(enum.Enum):
    """How should the initial working directory of a session be set?"""
    INITIAL_WORKING_DIRECTORY_CUSTOM = "Yes"  #: Custom directory, specified elsewhere
    INITIAL_WORKING_DIRECTORY_HOME = "No"  #: Use default of home directory
    INITIAL_WORKING_DIRECTORY_RECYCLE = "Recycle"  #: Reuse the "current" directory, or home if there is no current.
    INITIAL_WORKING_DIRECTORY_ADVANCED = "Advanced"  #: Use advanced settings, which specify more granular behavior depending on whether the new session is a new window, tab, or split pane.

    def toJSON(self):
        return json.dumps(self.value)


# pylint: enable=line-too-long

class IconMode(enum.Enum):
    """How should session icons be selected?"""
    NONE = 0
    AUTOMATIC = 1
    CUSTOM = 2

    def toJSON(self):
        return json.dumps(self.value)


class TitleComponents(enum.Enum):
    """Which title components should be present?"""
    SESSION_NAME = (1 << 0)
    JOB = (1 << 1)
    WORKING_DIRECTORY = (1 << 2)
    TTY = (1 << 3)
    CUSTOM = (1 << 4)  #: Mutually exclusive with all other options.
    PROFILE_NAME = (1 << 5)
    PROFILE_AND_SESSION_NAME = (1 << 6)
    USER = (1 << 7)
    HOST = (1 << 8)
    COMMAND_LINE = (1 << 9)
    SIZE = (1 << 10)

    def toJSON(self):
        return json.dumps(self.value)


class LocalWriteOnlyProfile:
    """
    A profile that can be modified but not read and does not send changes on
    each write.

    You can safely create this with `LocalWriteOnlyProfile()`. Use
    :meth:`~iterm2.Session.async_set_profile_properties` to update a session
    without modifying the underlying profile.

    .. seealso::
      * Example ":ref:`copycolor_example`"
      * Example ":ref:`settabcolor_example`"
      * Example ":ref:`increase_font_size_example`"
    """
    def __init__(self, values=None):
        if not values:
            values = {}
        self.__values = {}
        for key, value in values.items():
            self.__values[key] = json.dumps(value)

    @property
    def values(self):
        """Returns the internal values dict."""
        return self.__values

    def _simple_set(self, key, value):
        """value is a json type"""
        if key is None:
            self.__values[key] = None
        else:
            if hasattr(value, "toJSON"):
                self.__values[key] = value.toJSON()
            else:
                self.__values[key] = json.dumps(value)

    def _color_set(self, key, value):
        if value is None:
            self.__values[key] = "null"
        else:
            self.__values[key] = json.dumps(value.get_dict())

    def set_title_components(self, value: typing.List[TitleComponents]):
        """
        Sets which components are visible in the session's title, or selects a
        custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        bitmask = 0
        for component in value:
            bitmask += component.value
        return self._simple_set("Title Components", bitmask)

    def set_title_function(self, display_name: str, identifier: str):
        """
        Sets the function call for the session title provider and its display
        name for the UI.

        :param display_name: This is shown in the Title Components menu in the
            UI.
        :identifier: The unique identifier, typically a backwards domain name.

        This takes effect only when the title_components property is set to
        `CUSTOM`.
        """
        return self._simple_set("Title Function", [display_name, identifier])


    def set_use_separate_colors_for_light_and_dark_mode(self, value: bool):
        """
        Sets whether to use separate colors for light and dark mode.

        When this is enabled, use [set_]xxx_color_light and
        set_[xxx_]color_dark instead of [set_]xxx_color.

        :param value: Whether to use separate colors for light and dark mode.
        """
        return self._simple_set("Use Separate Colors for Light and Dark Mode", value)

    def set_foreground_color(self, value: 'iterm2.color.Color'):
        """
        Sets the foreground color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Foreground Color", value)

    def set_foreground_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the foreground color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Foreground Color (Light)", value)

    def set_foreground_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the foreground color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Foreground Color (Dark)", value)

    def set_background_color(self, value: 'iterm2.color.Color'):
        """
        Sets the background color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Background Color", value)

    def set_background_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the background color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Background Color (Light)", value)

    def set_background_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the background color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Background Color (Dark)", value)

    def set_bold_color(self, value: 'iterm2.color.Color'):
        """
        Sets the bold text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Bold Color", value)

    def set_bold_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the bold text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Bold Color (Light)", value)

    def set_bold_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the bold text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Bold Color (Dark)", value)

    def set_use_bright_bold(self, value: bool):
        """
        Sets  how bold text is rendered. This is used only when separate
        light/dark mode colors are not enabled.

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

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold", value)

    def set_use_bright_bold_light(self, value: bool):
        """
        Sets  how bold text is rendered. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

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

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold (Light)", value)

    def set_use_bright_bold_dark(self, value: bool):
        """
        Sets  how bold text is rendered. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

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

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold (Dark)", value)

    def set_use_bold_color(self, value: bool):
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This is used only when separate light/dark
        mode colors are not enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        set_use_bright_bold().

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold", value)

    def set_use_bold_color_light(self, value: bool):
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        set_use_bright_bold().

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold (Light)", value)

    def set_use_bold_color_dark(self, value: bool):
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        set_use_bright_bold().

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold (Dark)", value)

    def set_brighten_bold_text(self, value: bool):
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This is used only when separate light/dark
        mode colors are not enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :param value: A bool
        """
        return self._simple_set("Brighten Bold Text", value)

    def set_brighten_bold_text_light(self, value: bool):
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :param value: A bool
        """
        return self._simple_set("Brighten Bold Text (Light)", value)

    def set_brighten_bold_text_dark(self, value: bool):
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :param value: A bool
        """
        return self._simple_set("Brighten Bold Text (Dark)", value)

    def set_link_color(self, value: 'iterm2.color.Color'):
        """
        Sets the link color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Link Color", value)

    def set_link_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the link color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Link Color (Light)", value)

    def set_link_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the link color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Link Color (Dark)", value)

    def set_selection_color(self, value: 'iterm2.color.Color'):
        """
        Sets the selection background color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selection Color", value)

    def set_selection_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the selection background color. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selection Color (Light)", value)

    def set_selection_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the selection background color. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selection Color (Dark)", value)

    def set_selected_text_color(self, value: 'iterm2.color.Color'):
        """
        Sets the selection text color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selected Text Color", value)

    def set_selected_text_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the selection text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selected Text Color (Light)", value)

    def set_selected_text_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the selection text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selected Text Color (Dark)", value)

    def set_cursor_color(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Color", value)

    def set_cursor_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Color (Light)", value)

    def set_cursor_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Color (Dark)", value)

    def set_cursor_text_color(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Text Color", value)

    def set_cursor_text_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Text Color (Light)", value)

    def set_cursor_text_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Text Color (Dark)", value)

    def set_ansi_0_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 0 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 0 Color", value)

    def set_ansi_0_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 0 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 0 Color (Light)", value)

    def set_ansi_0_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 0 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 0 Color (Dark)", value)

    def set_ansi_1_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 1 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 1 Color", value)

    def set_ansi_1_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 1 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 1 Color (Light)", value)

    def set_ansi_1_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 1 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 1 Color (Dark)", value)

    def set_ansi_2_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 2 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 2 Color", value)

    def set_ansi_2_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 2 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 2 Color (Light)", value)

    def set_ansi_2_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 2 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 2 Color (Dark)", value)

    def set_ansi_3_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 3 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 3 Color", value)

    def set_ansi_3_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 3 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 3 Color (Light)", value)

    def set_ansi_3_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 3 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 3 Color (Dark)", value)

    def set_ansi_4_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 4 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 4 Color", value)

    def set_ansi_4_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 4 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 4 Color (Light)", value)

    def set_ansi_4_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 4 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 4 Color (Dark)", value)

    def set_ansi_5_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 5 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 5 Color", value)

    def set_ansi_5_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 5 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 5 Color (Light)", value)

    def set_ansi_5_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 5 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 5 Color (Dark)", value)

    def set_ansi_6_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 6 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 6 Color", value)

    def set_ansi_6_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 6 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 6 Color (Light)", value)

    def set_ansi_6_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 6 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 6 Color (Dark)", value)

    def set_ansi_7_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 7 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 7 Color", value)

    def set_ansi_7_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 7 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 7 Color (Light)", value)

    def set_ansi_7_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 7 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 7 Color (Dark)", value)

    def set_ansi_8_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 8 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 8 Color", value)

    def set_ansi_8_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 8 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 8 Color (Light)", value)

    def set_ansi_8_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 8 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 8 Color (Dark)", value)

    def set_ansi_9_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 9 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 9 Color", value)

    def set_ansi_9_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 9 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 9 Color (Light)", value)

    def set_ansi_9_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 9 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 9 Color (Dark)", value)

    def set_ansi_10_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 10 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 10 Color", value)

    def set_ansi_10_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 10 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 10 Color (Light)", value)

    def set_ansi_10_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 10 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 10 Color (Dark)", value)

    def set_ansi_11_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 11 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 11 Color", value)

    def set_ansi_11_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 11 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 11 Color (Light)", value)

    def set_ansi_11_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 11 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 11 Color (Dark)", value)

    def set_ansi_12_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 12 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 12 Color", value)

    def set_ansi_12_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 12 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 12 Color (Light)", value)

    def set_ansi_12_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 12 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 12 Color (Dark)", value)

    def set_ansi_13_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 13 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 13 Color", value)

    def set_ansi_13_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 13 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 13 Color (Light)", value)

    def set_ansi_13_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 13 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 13 Color (Dark)", value)

    def set_ansi_14_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 14 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 14 Color", value)

    def set_ansi_14_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 14 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 14 Color (Light)", value)

    def set_ansi_14_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 14 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 14 Color (Dark)", value)

    def set_ansi_15_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 15 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 15 Color", value)

    def set_ansi_15_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 15 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 15 Color (Light)", value)

    def set_ansi_15_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 15 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 15 Color (Dark)", value)

    def set_smart_cursor_color(self, value: bool):
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This is used only when separate light/dark mode colors are not
        enabled.

        :param value: A bool
        """
        return self._simple_set("Smart Cursor Color", value)

    def set_smart_cursor_color_light(self, value: bool):
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Smart Cursor Color (Light)", value)

    def set_smart_cursor_color_dark(self, value: bool):
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Smart Cursor Color (Dark)", value)

    def set_minimum_contrast(self, value: float):
        """
        Sets the minimum contrast, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return self._simple_set("Minimum Contrast", value)

    def set_minimum_contrast_light(self, value: float):
        """
        Sets the minimum contrast, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Minimum Contrast (Light)", value)

    def set_minimum_contrast_dark(self, value: float):
        """
        Sets the minimum contrast, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Minimum Contrast (Dark)", value)

    def set_tab_color(self, value: 'iterm2.color.Color'):
        """
        Sets the tab color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Tab Color", value)

    def set_tab_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the tab color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Tab Color (Light)", value)

    def set_tab_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the tab color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Tab Color (Dark)", value)

    def set_use_tab_color(self, value: bool):
        """
        Sets whether the tab color should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Tab Color", value)

    def set_use_tab_color_light(self, value: bool):
        """
        Sets whether the tab color should be used. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Tab Color (Light)", value)

    def set_use_tab_color_dark(self, value: bool):
        """
        Sets whether the tab color should be used. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Tab Color (Dark)", value)

    def set_underline_color(self, value: typing.Optional['iterm2.color.Color']):
        """
        Sets the underline color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A typing.Optional['iterm2.color.Color']
        """
        return self._color_set("Underline Color", value)

    def set_underline_color_light(self, value: typing.Optional['iterm2.color.Color']):
        """
        Sets the underline color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A typing.Optional['iterm2.color.Color']
        """
        return self._color_set("Underline Color (Light)", value)

    def set_underline_color_dark(self, value: typing.Optional['iterm2.color.Color']):
        """
        Sets the underline color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A typing.Optional['iterm2.color.Color']
        """
        return self._color_set("Underline Color (Dark)", value)

    def set_use_underline_color(self, value: bool):
        """
        Sets whether to use the specified underline color. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Underline Color", value)

    def set_use_underline_color_light(self, value: bool):
        """
        Sets whether to use the specified underline color. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Underline Color (Light)", value)

    def set_use_underline_color_dark(self, value: bool):
        """
        Sets whether to use the specified underline color. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Underline Color (Dark)", value)

    def set_cursor_boost(self, value: float):
        """
        Sets the cursor boost level, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return self._simple_set("Cursor Boost", value)

    def set_cursor_boost_light(self, value: float):
        """
        Sets the cursor boost level, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Cursor Boost (Light)", value)

    def set_cursor_boost_dark(self, value: float):
        """
        Sets the cursor boost level, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Cursor Boost (Dark)", value)

    def set_use_cursor_guide(self, value: bool):
        """
        Sets whether the cursor guide should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Cursor Guide", value)

    def set_use_cursor_guide_light(self, value: bool):
        """
        Sets whether the cursor guide should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Cursor Guide (Light)", value)

    def set_use_cursor_guide_dark(self, value: bool):
        """
        Sets whether the cursor guide should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Cursor Guide (Dark)", value)

    def set_cursor_guide_color(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor guide color. The alpha value is respected. This is used
        only when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Guide Color", value)

    def set_cursor_guide_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Guide Color (Light)", value)

    def set_cursor_guide_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Guide Color (Dark)", value)

    def set_badge_color(self, value: 'iterm2.color.Color'):
        """
        Sets the badge color. The alpha value is respected. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Badge Color", value)

    def set_badge_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the badge color. The alpha value is respected. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Badge Color (Light)", value)

    def set_badge_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the badge color. The alpha value is respected. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Badge Color (Dark)", value)

    def set_name(self, value: str):
        """
        Sets the name.

        :param value: A str
        """
        return self._simple_set("Name", value)

    def set_badge_text(self, value: str):
        """
        Sets the badge text.

        :param value: A str
        """
        return self._simple_set("Badge Text", value)

    def set_subtitle(self, value: str):
        """
        Sets the subtitle, an interpolated string.

        :param value: A str
        """
        return self._simple_set("Subtitle", value)

    def set_answerback_string(self, value: str):
        """
        Sets the answerback string.

        :param value: A str
        """
        return self._simple_set("Answerback String", value)

    def set_blinking_cursor(self, value: bool):
        """
        Sets whether the cursor blinks.

        :param value: A bool
        """
        return self._simple_set("Blinking Cursor", value)

    def set_use_bold_font(self, value: bool):
        """
        Sets whether to use the bold variant of the font for bold text.

        :param value: A bool
        """
        return self._simple_set("Use Bold Font", value)

    def set_ascii_ligatures(self, value: bool):
        """
        Sets whether ligatures should be used for ASCII text.

        :param value: A bool
        """
        return self._simple_set("ASCII Ligatures", value)

    def set_non_ascii_ligatures(self, value: bool):
        """
        Sets whether ligatures should be used for non-ASCII text.

        :param value: A bool
        """
        return self._simple_set("Non-ASCII Ligatures", value)

    def set_blink_allowed(self, value: bool):
        """
        Sets whether blinking text is allowed.

        :param value: A bool
        """
        return self._simple_set("Blink Allowed", value)

    def set_use_italic_font(self, value: bool):
        """
        Sets whether italic text is allowed.

        :param value: A bool
        """
        return self._simple_set("Use Italic Font", value)

    def set_ambiguous_double_width(self, value: bool):
        """
        Sets whether ambiguous-width text should be treated as double-width.

        :param value: A bool
        """
        return self._simple_set("Ambiguous Double Width", value)

    def set_horizontal_spacing(self, value: float):
        """
        Sets the fraction of horizontal spacing. Must be non-negative.

        :param value: A float
        """
        return self._simple_set("Horizontal Spacing", value)

    def set_vertical_spacing(self, value: float):
        """
        Sets the fraction of vertical spacing. Must be non-negative.

        :param value: A float
        """
        return self._simple_set("Vertical Spacing", value)

    def set_use_non_ascii_font(self, value: bool):
        """
        Sets whether to use a different font for non-ASCII text.

        :param value: A bool
        """
        return self._simple_set("Use Non-ASCII Font", value)

    def set_transparency(self, value: float):
        """
        Sets the level of transparency.

        The value is between 0 and 1.

        :param value: A float
        """
        return self._simple_set("Transparency", value)

    def set_blur(self, value: bool):
        """
        Sets whether background blur should be enabled.

        :param value: A bool
        """
        return self._simple_set("Blur", value)

    def set_blur_radius(self, value: float):
        """
        Sets the blur radius (how blurry). Requires blur to be enabled.

        The value is between 0 and 30.

        :param value: A float
        """
        return self._simple_set("Blur Radius", value)

    def set_background_image_mode(self, value: BackgroundImageMode):
        """
        Sets how the background image is drawn.

        :param value: A `BackgroundImageMode`
        """
        return self._simple_set("Background Image Mode", value)

    def set_blend(self, value: float):
        """
        Sets how much the default background color gets blended with the
        background image.

        The value is in 0 to 1.

        .. seealso:: Example ":ref:`blending_example`

        :param value: A float
        """
        return self._simple_set("Blend", value)

    def set_sync_title(self, value: bool):
        """
        Sets whether the profile name stays in the tab title, even if changed
        by an escape sequence.

        :param value: A bool
        """
        return self._simple_set("Sync Title", value)

    def set_use_built_in_powerline_glyphs(self, value: bool):
        """
        Sets whether powerline glyphs should be drawn by iTerm2 or left to the
        font.

        :param value: A bool
        """
        return self._simple_set("Draw Powerline Glyphs", value)

    def set_disable_window_resizing(self, value: bool):
        """
        Sets whether the terminal can resize the window with an escape
        sequence.

        :param value: A bool
        """
        return self._simple_set("Disable Window Resizing", value)

    def set_only_the_default_bg_color_uses_transparency(self, value: bool):
        """
        Sets whether window transparency shows through non-default background
        colors.

        :param value: A bool
        """
        return self._simple_set("Only The Default BG Color Uses Transparency", value)

    def set_ascii_anti_aliased(self, value: bool):
        """
        Sets whether ASCII text is anti-aliased.

        :param value: A bool
        """
        return self._simple_set("ASCII Anti Aliased", value)

    def set_non_ascii_anti_aliased(self, value: bool):
        """
        Sets whether non-ASCII text is anti-aliased.

        :param value: A bool
        """
        return self._simple_set("Non-ASCII Anti Aliased", value)

    def set_scrollback_lines(self, value: int):
        """
        Sets the number of scrollback lines.

        Value must be at least 0.

        :param value: An int
        """
        return self._simple_set("Scrollback Lines", value)

    def set_unlimited_scrollback(self, value: bool):
        """
        Sets whether the scrollback buffer's length is unlimited.

        :param value: A bool
        """
        return self._simple_set("Unlimited Scrollback", value)

    def set_scrollback_with_status_bar(self, value: bool):
        """
        Sets whether text gets appended to scrollback when there is an app
        status bar

        :param value: A bool
        """
        return self._simple_set("Scrollback With Status Bar", value)

    def set_scrollback_in_alternate_screen(self, value: bool):
        """
        Sets whether text gets appended to scrollback in alternate screen mode.

        :param value: A bool
        """
        return self._simple_set("Scrollback in Alternate Screen", value)

    def set_mouse_reporting(self, value: bool):
        """
        Sets whether mouse reporting is allowed

        :param value: A bool
        """
        return self._simple_set("Mouse Reporting", value)

    def set_mouse_reporting_allow_mouse_wheel(self, value: bool):
        """
        Sets whether mouse reporting reports the mouse wheel's movements.

        :param value: A bool
        """
        return self._simple_set("Mouse Reporting allow mouse wheel", value)

    def set_allow_title_reporting(self, value: bool):
        """
        Sets whether the session title can be reported

        :param value: A bool
        """
        return self._simple_set("Allow Title Reporting", value)

    def set_allow_title_setting(self, value: bool):
        """
        Sets whether the session title can be changed by escape sequence

        :param value: A bool
        """
        return self._simple_set("Allow Title Setting", value)

    def set_disable_printing(self, value: bool):
        """
        Sets whether printing by escape sequence is disabled.

        :param value: A bool
        """
        return self._simple_set("Disable Printing", value)

    def set_disable_smcup_rmcup(self, value: bool):
        """
        Sets whether alternate screen mode is disabled

        :param value: A bool
        """
        return self._simple_set("Disable Smcup Rmcup", value)

    def set_silence_bell(self, value: bool):
        """
        Sets whether the bell makes noise.

        :param value: A bool
        """
        return self._simple_set("Silence Bell", value)

    def set_bm_growl(self, value: bool):
        """
        Sets whether notifications should be shown.

        :param value: A bool
        """
        return self._simple_set("BM Growl", value)

    def set_send_bell_alert(self, value: bool):
        """
        Sets whether notifications should be shown for the bell ringing

        :param value: A bool
        """
        return self._simple_set("Send Bell Alert", value)

    def set_send_idle_alert(self, value: bool):
        """
        Sets whether notifications should be shown for becoming idle

        :param value: A bool
        """
        return self._simple_set("Send Idle Alert", value)

    def set_send_new_output_alert(self, value: bool):
        """
        Sets whether notifications should be shown for new output

        :param value: A bool
        """
        return self._simple_set("Send New Output Alert", value)

    def set_send_session_ended_alert(self, value: bool):
        """
        Sets whether notifications should be shown for a session ending

        :param value: A bool
        """
        return self._simple_set("Send Session Ended Alert", value)

    def set_send_terminal_generated_alerts(self, value: bool):
        """
        Sets whether notifications should be shown for escape-sequence
        originated notifications

        :param value: A bool
        """
        return self._simple_set("Send Terminal Generated Alerts", value)

    def set_flashing_bell(self, value: bool):
        """
        Sets whether the bell should flash the screen

        :param value: A bool
        """
        return self._simple_set("Flashing Bell", value)

    def set_visual_bell(self, value: bool):
        """
        Sets whether a bell should be shown when the bell rings

        :param value: A bool
        """
        return self._simple_set("Visual Bell", value)

    def set_close_sessions_on_end(self, value: bool):
        """
        Sets whether the session should close when it ends.

        :param value: A bool
        """
        return self._simple_set("Close Sessions On End", value)

    def set_prompt_before_closing(self, value: bool):
        """
        Sets whether the session should prompt before closing.

        :param value: A bool
        """
        return self._simple_set("Prompt Before Closing 2", value)

    def set_session_close_undo_timeout(self, value: float):
        """
        Sets the amount of time you can undo closing a session

        The value is at least 0.

        :param value: A float
        """
        return self._simple_set("Session Close Undo Timeout", value)

    def set_reduce_flicker(self, value: bool):
        """
        Sets whether the flicker fixer is on.

        :param value: A bool
        """
        return self._simple_set("Reduce Flicker", value)

    def set_send_code_when_idle(self, value: bool):
        """
        Sets whether to send a code when idle

        :param value: A bool
        """
        return self._simple_set("Send Code When Idle", value)

    def set_application_keypad_allowed(self, value: bool):
        """
        Sets whether the terminal may be placed in application keypad mode

        :param value: A bool
        """
        return self._simple_set("Application Keypad Allowed", value)

    def set_place_prompt_at_first_column(self, value: bool):
        """
        Sets whether the prompt should always begin at the first column
        (requires shell integration)

        :param value: A bool
        """
        return self._simple_set("Place Prompt at First Column", value)

    def set_show_mark_indicators(self, value: bool):
        """
        Sets whether mark indicators should be visible

        :param value: A bool
        """
        return self._simple_set("Show Mark Indicators", value)

    def set_idle_code(self, value: int):
        """
        Sets the ASCII code to send on idle

        Value is an int in 0 through 255.

        :param value: An int
        """
        return self._simple_set("Idle Code", value)

    def set_idle_period(self, value: float):
        """
        Sets how often to send a code when idle

        Value is a float at least 0

        :param value: A float
        """
        return self._simple_set("Idle Period", value)

    def set_unicode_version(self, value: bool):
        """
        Sets the unicode version for wcwidth

        :param value: A bool
        """
        return self._simple_set("Unicode Version", value)

    def set_cursor_type(self, value: CursorType):
        """
        Sets the cursor type

        :param value: A CursorType
        """
        return self._simple_set("Cursor Type", value)

    def set_thin_strokes(self, value: ThinStrokes):
        """
        Sets whether thin strokes are used.

        :param value: A ThinStrokes
        """
        return self._simple_set("Thin Strokes", value)

    def set_unicode_normalization(self, value: UnicodeNormalization):
        """
        Sets the unicode normalization form to use

        :param value: An UnicodeNormalization
        """
        return self._simple_set("Unicode Normalization", value)

    def set_character_encoding(self, value: CharacterEncoding):
        """
        Sets the character encoding

        :param value: A CharacterEncoding
        """
        return self._simple_set("Character Encoding", value)

    def set_left_option_key_sends(self, value: OptionKeySends):
        """
        Sets the behavior of the left option key.

        :param value: An OptionKeySends
        """
        return self._simple_set("Option Key Sends", value)

    def set_right_option_key_sends(self, value: OptionKeySends):
        """
        Sets the behavior of the right option key.

        :param value: An OptionKeySends
        """
        return self._simple_set("Right Option Key Sends", value)

    def set_triggers(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """
        Sets the triggers.

        Value is an encoded trigger. Use iterm2.decode_trigger to convert from
        an encoded trigger to an object. Trigger objects can be encoded using
        the encode property.

        :param value: A typing.List[typing.Dict[str, typing.Any]]
        """
        return self._simple_set("Triggers", value)

    def set_smart_selection_rules(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """
        Sets the smart selection rules.

        The value is a list of dicts of smart selection rules (currently
        undocumented)

        :param value: A typing.List[typing.Dict[str, typing.Any]]
        """
        return self._simple_set("Smart Selection Rules", value)

    def set_semantic_history(self, value: typing.Dict[str, typing.Any]):
        """
        Sets the semantic history prefs.

        :param value: A typing.Dict[str, typing.Any]
        """
        return self._simple_set("Semantic History", value)

    def set_automatic_profile_switching_rules(self, value: typing.List[str]):
        """
        Sets the automatic profile switching rules.

        Value is a list of strings, each giving a rule.

        :param value: A typing.List[str]
        """
        return self._simple_set("Bound Hosts", value)

    def set_advanced_working_directory_window_setting(self, value: InitialWorkingDirectory):
        """
        Sets the advanced working directory window setting.

        Value excludes Advanced.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("AWDS Window Option", value)

    def set_advanced_working_directory_window_directory(self, value: str):
        """
        Sets the advanced working directory window directory.

        :param value: A str
        """
        return self._simple_set("AWDS Window Directory", value)

    def set_advanced_working_directory_tab_setting(self, value: InitialWorkingDirectory):
        """
        Sets the advanced working directory tab setting.

        Value excludes Advanced.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("AWDS Tab Option", value)

    def set_advanced_working_directory_tab_directory(self, value: str):
        """
        Sets the advanced working directory tab directory.

        :param value: A str
        """
        return self._simple_set("AWDS Tab Directory", value)

    def set_advanced_working_directory_pane_setting(self, value: InitialWorkingDirectory):
        """
        Sets the advanced working directory pane setting.

        Value excludes Advanced.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("AWDS Pane Option", value)

    def set_advanced_working_directory_pane_directory(self, value: str):
        """
        Sets the advanced working directory pane directory.

        :param value: A str
        """
        return self._simple_set("AWDS Pane Directory", value)

    def set_normal_font(self, value: str):
        """
        Sets the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii. The value is a font's
        name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"

        :param value: A str
        """
        return self._simple_set("Normal Font", value)

    def set_non_ascii_font(self, value: str):
        """
        Sets the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.
        The value is the font name and size as a string.

        :param value: A str
        """
        return self._simple_set("Non Ascii Font", value)

    def set_background_image_location(self, value: str):
        """
        Sets the path to the background image.

        The value is a Path.

        :param value: A str
        """
        return self._simple_set("Background Image Location", value)

    def set_key_mappings(self, value: typing.Dict[str, typing.Any]):
        """
        Sets the keyboard shortcuts.

        The value is a Dictionary mapping keystroke to action. You can convert
        between the values in this dictionary and a :class:`~iterm2.KeyBinding`
        using `iterm2.decode_key_binding`

        :param value: A typing.Dict[str, typing.Any]
        """
        return self._simple_set("Keyboard Map", value)

    def set_touchbar_mappings(self, value: typing.Dict[str, typing.Any]):
        """
        Sets the touchbar actions.

        The value is a Dictionary mapping touch bar item to action

        :param value: A typing.Dict[str, typing.Any]
        """
        return self._simple_set("Touch Bar Map", value)

    def set_use_custom_command(self, value: str):
        """
        Sets whether to use a custom command when the session is created.

        The value is the string Yes or No

        :param value: A str
        """
        return self._simple_set("Custom Command", value)

    def set_command(self, value: str):
        """
        Sets the command to run when the session starts.

        The value is a string giving the command to run

        :param value: A str
        """
        return self._simple_set("Command", value)

    def set_initial_directory_mode(self, value: InitialWorkingDirectory):
        """
        Sets whether to use a custom (not home) initial working directory.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("Custom Directory", value.value)

    def set_custom_directory(self, value: str):
        """
        Sets the initial working directory.

        The initial_directory_mode must be set to
        `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
        take effect.

        :param value: A str
        """
        return self._simple_set("Working Directory", value)

    def set_icon_mode(self, value: IconMode):
        """
        Sets the icon mode.

        :param value: An IconMode
        """
        return self._simple_set("Icon", value.value)

    def set_custom_icon_path(self, value: str):
        """
        Sets the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.

        :param value: A str
        """
        return self._simple_set("Custom Icon Path", value)

    def set_badge_top_margin(self, value: int):
        """
        Sets the top margin of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Top Margin", value)

    def set_badge_right_margin(self, value: int):
        """
        Sets the right margin of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Right Margin", value)

    def set_badge_max_width(self, value: int):
        """
        Sets the max width of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Max Width", value)

    def set_badge_max_height(self, value: int):
        """
        Sets the max height of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Max Height", value)

    def set_badge_font(self, value: str):
        """
        Sets the font of the badge.

        The font name is a string like "Helvetica".

        :param value: A str
        """
        return self._simple_set("Badge Font", value)

    def set_use_custom_window_title(self, value: bool):
        """
        Sets whether the custom window title is used.

        Should the custom window title in the profile be used?

        :param value: A bool
        """
        return self._simple_set("Use Custom Window Title", value)

    def set_custom_window_title(self, value: typing.Optional[str]):
        """
        Sets the custom window title.

        This will only be used if use_custom_window_title is True.
        The value is an interpolated string.

        :param value: A typing.Optional[str]
        """
        return self._simple_set("Custom Window Title", value)

    def set_use_transparency_initially(self, value: bool):
        """
        Sets whether a window created with this profile respect the
        transparency setting.

        If True, use transparency; if False, force the window to
        be opaque (but it can be toggled with View > Use Transparency).

        :param value: A bool
        """
        return self._simple_set("Initial Use Transparency", value)

    def set_status_bar_enabled(self, value: bool):
        """
        Sets whether the status bar be enabled.

        If True, the status bar will be shown.

        :param value: A bool
        """
        return self._simple_set("Show Status Bar", value)

    def set_use_csi_u(self, value: bool):
        """
        Sets whether to report keystrokes with CSI u protocol.

        If True, CSI u will be enabled.

        :param value: A bool
        """
        return self._simple_set("Use libtickit protocol", value)

    def set_triggers_use_interpolated_strings(self, value: bool):
        """
        Sets whether trigger parameters should be interpreted as interpolated
        strings.

        :param value: A bool
        """
        return self._simple_set("Triggers Use Interpolated Strings", value)

    def set_left_option_key_changeable(self, value: bool):
        """
        Sets whether apps should be able to change the left option key to send
        esc+.

        The values gives whether it should be allowed.

        :param value: A bool
        """
        return self._simple_set("Left Option Key Changeable", value)

    def set_right_option_key_changeable(self, value: bool):
        """
        Sets whether apps should be able to change the right option key to send
        esc+.

        The values gives whether it should be allowed.

        :param value: A bool
        """
        return self._simple_set("Right Option Key Changeable", value)

    def set_open_password_manager_automatically(self, value: bool):
        """
        Sets if the password manager should open automatically.

        The values gives whether it should open automatically.

        :param value: A bool
        """
        return self._simple_set("Open Password Manager Automatically", value)

class WriteOnlyProfile:
    """
    A profile that can be modified but not read. Useful for changing many
    sessions' profiles at once without knowing what they are.
    """
    def __init__(self, session_id, connection, guid=None):
        assert session_id != "all"
        self.connection = connection
        self.session_id = session_id
        self.__guid = guid

    async def _async_simple_set(self, key: str, value: typing.Any):
        """
        :param value: a json type
        """
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
        return self.session_id

    async def async_set_color_preset(
            self, preset: iterm2.colorpresets.ColorPreset):
        """
        Sets the color preset.

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

    async def async_set_title_components(
            self, value: typing.List[TitleComponents]):
        """
        Sets which components are visible in the session's title, or selects a
        custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        bitmask = 0
        for component in value:
            bitmask += component.value
        return await self._async_simple_set("Title Components", bitmask)

    async def async_set_title_function(
            self, display_name: str, identifier: str):
        """
        Sets the function call for the session title provider and its display
        name for the UI.

        :param display_name: This is shown in the Title Components menu in the
            UI.
        :identifier: The unique identifier, typically a backwards domain name.

        This takes effect only when the title_components property is set to
        `CUSTOM`.
        """
        return await self._async_simple_set(
            "Title Function", [display_name, identifier])


    async def async_set_use_separate_colors_for_light_and_dark_mode(self, value: bool):
        """
        Sets whether to use separate colors for light and dark mode.

        When this is enabled, use [set_]xxx_color_light and
        set_[xxx_]color_dark instead of [set_]xxx_color.

        :param value: Whether to use separate colors for light and dark mode.
        """
        return await self._async_simple_set("Use Separate Colors for Light and Dark Mode", value)

    async def async_set_foreground_color(self, value: 'iterm2.color.Color'):
        """
        Sets the foreground color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Foreground Color", value)

    async def async_set_foreground_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the foreground color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Foreground Color (Light)", value)

    async def async_set_foreground_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the foreground color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Foreground Color (Dark)", value)

    async def async_set_background_color(self, value: 'iterm2.color.Color'):
        """
        Sets the background color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Background Color", value)

    async def async_set_background_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the background color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Background Color (Light)", value)

    async def async_set_background_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the background color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Background Color (Dark)", value)

    async def async_set_bold_color(self, value: 'iterm2.color.Color'):
        """
        Sets the bold text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Bold Color", value)

    async def async_set_bold_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the bold text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Bold Color (Light)", value)

    async def async_set_bold_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the bold text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Bold Color (Dark)", value)

    async def async_set_use_bright_bold(self, value: bool):
        """
        Sets  how bold text is rendered. This is used only when separate
        light/dark mode colors are not enabled.

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
        """
        return await self._async_simple_set("Use Bright Bold", value)

    async def async_set_use_bright_bold_light(self, value: bool):
        """
        Sets  how bold text is rendered. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

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
        """
        return await self._async_simple_set("Use Bright Bold (Light)", value)

    async def async_set_use_bright_bold_dark(self, value: bool):
        """
        Sets  how bold text is rendered. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

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
        """
        return await self._async_simple_set("Use Bright Bold (Dark)", value)

    async def async_set_use_bold_color(self, value: bool):
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This is used only when separate light/dark
        mode colors are not enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        async_set_use_bright_bold().
        """
        return await self._async_simple_set("Use Bright Bold", value)

    async def async_set_use_bold_color_light(self, value: bool):
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        async_set_use_bright_bold().
        """
        return await self._async_simple_set("Use Bright Bold (Light)", value)

    async def async_set_use_bold_color_dark(self, value: bool):
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        async_set_use_bright_bold().
        """
        return await self._async_simple_set("Use Bright Bold (Dark)", value)

    async def async_set_brighten_bold_text(self, value: bool):
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This is used only when separate light/dark
        mode colors are not enabled.

        This is only supported in iTerm2 version 3.3.7 and later.
        """
        return await self._async_simple_set("Brighten Bold Text", value)

    async def async_set_brighten_bold_text_light(self, value: bool):
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.
        """
        return await self._async_simple_set("Brighten Bold Text (Light)", value)

    async def async_set_brighten_bold_text_dark(self, value: bool):
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.
        """
        return await self._async_simple_set("Brighten Bold Text (Dark)", value)

    async def async_set_link_color(self, value: 'iterm2.color.Color'):
        """
        Sets the link color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Link Color", value)

    async def async_set_link_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the link color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Link Color (Light)", value)

    async def async_set_link_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the link color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Link Color (Dark)", value)

    async def async_set_selection_color(self, value: 'iterm2.color.Color'):
        """
        Sets the selection background color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selection Color", value)

    async def async_set_selection_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the selection background color. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selection Color (Light)", value)

    async def async_set_selection_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the selection background color. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selection Color (Dark)", value)

    async def async_set_selected_text_color(self, value: 'iterm2.color.Color'):
        """
        Sets the selection text color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selected Text Color", value)

    async def async_set_selected_text_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the selection text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selected Text Color (Light)", value)

    async def async_set_selected_text_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the selection text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selected Text Color (Dark)", value)

    async def async_set_cursor_color(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Color", value)

    async def async_set_cursor_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Color (Light)", value)

    async def async_set_cursor_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Color (Dark)", value)

    async def async_set_cursor_text_color(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Text Color", value)

    async def async_set_cursor_text_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Text Color (Light)", value)

    async def async_set_cursor_text_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Text Color (Dark)", value)

    async def async_set_ansi_0_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 0 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 0 Color", value)

    async def async_set_ansi_0_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 0 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 0 Color (Light)", value)

    async def async_set_ansi_0_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 0 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 0 Color (Dark)", value)

    async def async_set_ansi_1_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 1 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 1 Color", value)

    async def async_set_ansi_1_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 1 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 1 Color (Light)", value)

    async def async_set_ansi_1_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 1 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 1 Color (Dark)", value)

    async def async_set_ansi_2_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 2 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 2 Color", value)

    async def async_set_ansi_2_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 2 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 2 Color (Light)", value)

    async def async_set_ansi_2_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 2 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 2 Color (Dark)", value)

    async def async_set_ansi_3_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 3 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 3 Color", value)

    async def async_set_ansi_3_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 3 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 3 Color (Light)", value)

    async def async_set_ansi_3_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 3 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 3 Color (Dark)", value)

    async def async_set_ansi_4_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 4 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 4 Color", value)

    async def async_set_ansi_4_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 4 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 4 Color (Light)", value)

    async def async_set_ansi_4_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 4 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 4 Color (Dark)", value)

    async def async_set_ansi_5_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 5 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 5 Color", value)

    async def async_set_ansi_5_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 5 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 5 Color (Light)", value)

    async def async_set_ansi_5_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 5 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 5 Color (Dark)", value)

    async def async_set_ansi_6_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 6 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 6 Color", value)

    async def async_set_ansi_6_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 6 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 6 Color (Light)", value)

    async def async_set_ansi_6_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 6 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 6 Color (Dark)", value)

    async def async_set_ansi_7_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 7 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 7 Color", value)

    async def async_set_ansi_7_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 7 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 7 Color (Light)", value)

    async def async_set_ansi_7_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 7 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 7 Color (Dark)", value)

    async def async_set_ansi_8_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 8 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 8 Color", value)

    async def async_set_ansi_8_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 8 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 8 Color (Light)", value)

    async def async_set_ansi_8_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 8 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 8 Color (Dark)", value)

    async def async_set_ansi_9_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 9 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 9 Color", value)

    async def async_set_ansi_9_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 9 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 9 Color (Light)", value)

    async def async_set_ansi_9_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 9 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 9 Color (Dark)", value)

    async def async_set_ansi_10_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 10 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 10 Color", value)

    async def async_set_ansi_10_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 10 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 10 Color (Light)", value)

    async def async_set_ansi_10_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 10 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 10 Color (Dark)", value)

    async def async_set_ansi_11_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 11 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 11 Color", value)

    async def async_set_ansi_11_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 11 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 11 Color (Light)", value)

    async def async_set_ansi_11_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 11 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 11 Color (Dark)", value)

    async def async_set_ansi_12_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 12 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 12 Color", value)

    async def async_set_ansi_12_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 12 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 12 Color (Light)", value)

    async def async_set_ansi_12_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 12 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 12 Color (Dark)", value)

    async def async_set_ansi_13_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 13 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 13 Color", value)

    async def async_set_ansi_13_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 13 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 13 Color (Light)", value)

    async def async_set_ansi_13_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 13 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 13 Color (Dark)", value)

    async def async_set_ansi_14_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 14 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 14 Color", value)

    async def async_set_ansi_14_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 14 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 14 Color (Light)", value)

    async def async_set_ansi_14_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 14 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 14 Color (Dark)", value)

    async def async_set_ansi_15_color(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 15 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 15 Color", value)

    async def async_set_ansi_15_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 15 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 15 Color (Light)", value)

    async def async_set_ansi_15_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the ANSI 15 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 15 Color (Dark)", value)

    async def async_set_smart_cursor_color(self, value: bool):
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This is used only when separate light/dark mode colors are not
        enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Smart Cursor Color", value)

    async def async_set_smart_cursor_color_light(self, value: bool):
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Smart Cursor Color (Light)", value)

    async def async_set_smart_cursor_color_dark(self, value: bool):
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Smart Cursor Color (Dark)", value)

    async def async_set_minimum_contrast(self, value: float):
        """
        Sets the minimum contrast, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return await self._async_simple_set("Minimum Contrast", value)

    async def async_set_minimum_contrast_light(self, value: float):
        """
        Sets the minimum contrast, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Minimum Contrast (Light)", value)

    async def async_set_minimum_contrast_dark(self, value: float):
        """
        Sets the minimum contrast, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Minimum Contrast (Dark)", value)

    async def async_set_tab_color(self, value: 'iterm2.color.Color'):
        """
        Sets the tab color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Tab Color", value)

    async def async_set_tab_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the tab color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Tab Color (Light)", value)

    async def async_set_tab_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the tab color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Tab Color (Dark)", value)

    async def async_set_use_tab_color(self, value: bool):
        """
        Sets whether the tab color should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Tab Color", value)

    async def async_set_use_tab_color_light(self, value: bool):
        """
        Sets whether the tab color should be used. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Tab Color (Light)", value)

    async def async_set_use_tab_color_dark(self, value: bool):
        """
        Sets whether the tab color should be used. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Tab Color (Dark)", value)

    async def async_set_underline_color(self, value: typing.Optional['iterm2.color.Color']):
        """
        Sets the underline color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A typing.Optional['iterm2.color.Color']
        """
        return await self._async_color_set("Underline Color", value)

    async def async_set_underline_color_light(self, value: typing.Optional['iterm2.color.Color']):
        """
        Sets the underline color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A typing.Optional['iterm2.color.Color']
        """
        return await self._async_color_set("Underline Color (Light)", value)

    async def async_set_underline_color_dark(self, value: typing.Optional['iterm2.color.Color']):
        """
        Sets the underline color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A typing.Optional['iterm2.color.Color']
        """
        return await self._async_color_set("Underline Color (Dark)", value)

    async def async_set_use_underline_color(self, value: bool):
        """
        Sets whether to use the specified underline color. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Underline Color", value)

    async def async_set_use_underline_color_light(self, value: bool):
        """
        Sets whether to use the specified underline color. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Underline Color (Light)", value)

    async def async_set_use_underline_color_dark(self, value: bool):
        """
        Sets whether to use the specified underline color. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Underline Color (Dark)", value)

    async def async_set_cursor_boost(self, value: float):
        """
        Sets the cursor boost level, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Boost", value)

    async def async_set_cursor_boost_light(self, value: float):
        """
        Sets the cursor boost level, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Boost (Light)", value)

    async def async_set_cursor_boost_dark(self, value: float):
        """
        Sets the cursor boost level, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Boost (Dark)", value)

    async def async_set_use_cursor_guide(self, value: bool):
        """
        Sets whether the cursor guide should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Cursor Guide", value)

    async def async_set_use_cursor_guide_light(self, value: bool):
        """
        Sets whether the cursor guide should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Cursor Guide (Light)", value)

    async def async_set_use_cursor_guide_dark(self, value: bool):
        """
        Sets whether the cursor guide should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Cursor Guide (Dark)", value)

    async def async_set_cursor_guide_color(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor guide color. The alpha value is respected. This is used
        only when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Guide Color", value)

    async def async_set_cursor_guide_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Guide Color (Light)", value)

    async def async_set_cursor_guide_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Guide Color (Dark)", value)

    async def async_set_badge_color(self, value: 'iterm2.color.Color'):
        """
        Sets the badge color. The alpha value is respected. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Badge Color", value)

    async def async_set_badge_color_light(self, value: 'iterm2.color.Color'):
        """
        Sets the badge color. The alpha value is respected. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Badge Color (Light)", value)

    async def async_set_badge_color_dark(self, value: 'iterm2.color.Color'):
        """
        Sets the badge color. The alpha value is respected. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Badge Color (Dark)", value)

    async def async_set_name(self, value: str):
        """
        Sets the name.

        :param value: A str
        """
        return await self._async_simple_set("Name", value)

    async def async_set_badge_text(self, value: str):
        """
        Sets the badge text.

        :param value: A str
        """
        return await self._async_simple_set("Badge Text", value)

    async def async_set_subtitle(self, value: str):
        """
        Sets the subtitle, an interpolated string.

        :param value: A str
        """
        return await self._async_simple_set("Subtitle", value)

    async def async_set_answerback_string(self, value: str):
        """
        Sets the answerback string.

        :param value: A str
        """
        return await self._async_simple_set("Answerback String", value)

    async def async_set_blinking_cursor(self, value: bool):
        """
        Sets whether the cursor blinks.

        :param value: A bool
        """
        return await self._async_simple_set("Blinking Cursor", value)

    async def async_set_use_bold_font(self, value: bool):
        """
        Sets whether to use the bold variant of the font for bold text.

        :param value: A bool
        """
        return await self._async_simple_set("Use Bold Font", value)

    async def async_set_ascii_ligatures(self, value: bool):
        """
        Sets whether ligatures should be used for ASCII text.

        :param value: A bool
        """
        return await self._async_simple_set("ASCII Ligatures", value)

    async def async_set_non_ascii_ligatures(self, value: bool):
        """
        Sets whether ligatures should be used for non-ASCII text.

        :param value: A bool
        """
        return await self._async_simple_set("Non-ASCII Ligatures", value)

    async def async_set_blink_allowed(self, value: bool):
        """
        Sets whether blinking text is allowed.

        :param value: A bool
        """
        return await self._async_simple_set("Blink Allowed", value)

    async def async_set_use_italic_font(self, value: bool):
        """
        Sets whether italic text is allowed.

        :param value: A bool
        """
        return await self._async_simple_set("Use Italic Font", value)

    async def async_set_ambiguous_double_width(self, value: bool):
        """
        Sets whether ambiguous-width text should be treated as double-width.

        :param value: A bool
        """
        return await self._async_simple_set("Ambiguous Double Width", value)

    async def async_set_horizontal_spacing(self, value: float):
        """
        Sets the fraction of horizontal spacing. Must be non-negative.

        :param value: A float
        """
        return await self._async_simple_set("Horizontal Spacing", value)

    async def async_set_vertical_spacing(self, value: float):
        """
        Sets the fraction of vertical spacing. Must be non-negative.

        :param value: A float
        """
        return await self._async_simple_set("Vertical Spacing", value)

    async def async_set_use_non_ascii_font(self, value: bool):
        """
        Sets whether to use a different font for non-ASCII text.

        :param value: A bool
        """
        return await self._async_simple_set("Use Non-ASCII Font", value)

    async def async_set_transparency(self, value: float):
        """
        Sets the level of transparency.

        The value is between 0 and 1.
        """
        return await self._async_simple_set("Transparency", value)

    async def async_set_blur(self, value: bool):
        """
        Sets whether background blur should be enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Blur", value)

    async def async_set_blur_radius(self, value: float):
        """
        Sets the blur radius (how blurry). Requires blur to be enabled.

        The value is between 0 and 30.
        """
        return await self._async_simple_set("Blur Radius", value)

    async def async_set_background_image_mode(self, value: BackgroundImageMode):
        """
        Sets how the background image is drawn.

        :param value: A `BackgroundImageMode`
        """
        return await self._async_simple_set("Background Image Mode", value)

    async def async_set_blend(self, value: float):
        """
        Sets how much the default background color gets blended with the
        background image.

        The value is in 0 to 1.

        .. seealso:: Example ":ref:`blending_example`
        """
        return await self._async_simple_set("Blend", value)

    async def async_set_sync_title(self, value: bool):
        """
        Sets whether the profile name stays in the tab title, even if changed
        by an escape sequence.

        :param value: A bool
        """
        return await self._async_simple_set("Sync Title", value)

    async def async_set_use_built_in_powerline_glyphs(self, value: bool):
        """
        Sets whether powerline glyphs should be drawn by iTerm2 or left to the
        font.

        :param value: A bool
        """
        return await self._async_simple_set("Draw Powerline Glyphs", value)

    async def async_set_disable_window_resizing(self, value: bool):
        """
        Sets whether the terminal can resize the window with an escape
        sequence.

        :param value: A bool
        """
        return await self._async_simple_set("Disable Window Resizing", value)

    async def async_set_only_the_default_bg_color_uses_transparency(self, value: bool):
        """
        Sets whether window transparency shows through non-default background
        colors.

        :param value: A bool
        """
        return await self._async_simple_set("Only The Default BG Color Uses Transparency", value)

    async def async_set_ascii_anti_aliased(self, value: bool):
        """
        Sets whether ASCII text is anti-aliased.

        :param value: A bool
        """
        return await self._async_simple_set("ASCII Anti Aliased", value)

    async def async_set_non_ascii_anti_aliased(self, value: bool):
        """
        Sets whether non-ASCII text is anti-aliased.

        :param value: A bool
        """
        return await self._async_simple_set("Non-ASCII Anti Aliased", value)

    async def async_set_scrollback_lines(self, value: int):
        """
        Sets the number of scrollback lines.

        Value must be at least 0.
        """
        return await self._async_simple_set("Scrollback Lines", value)

    async def async_set_unlimited_scrollback(self, value: bool):
        """
        Sets whether the scrollback buffer's length is unlimited.

        :param value: A bool
        """
        return await self._async_simple_set("Unlimited Scrollback", value)

    async def async_set_scrollback_with_status_bar(self, value: bool):
        """
        Sets whether text gets appended to scrollback when there is an app
        status bar

        :param value: A bool
        """
        return await self._async_simple_set("Scrollback With Status Bar", value)

    async def async_set_scrollback_in_alternate_screen(self, value: bool):
        """
        Sets whether text gets appended to scrollback in alternate screen mode.

        :param value: A bool
        """
        return await self._async_simple_set("Scrollback in Alternate Screen", value)

    async def async_set_mouse_reporting(self, value: bool):
        """
        Sets whether mouse reporting is allowed

        :param value: A bool
        """
        return await self._async_simple_set("Mouse Reporting", value)

    async def async_set_mouse_reporting_allow_mouse_wheel(self, value: bool):
        """
        Sets whether mouse reporting reports the mouse wheel's movements.

        :param value: A bool
        """
        return await self._async_simple_set("Mouse Reporting allow mouse wheel", value)

    async def async_set_allow_title_reporting(self, value: bool):
        """
        Sets whether the session title can be reported

        :param value: A bool
        """
        return await self._async_simple_set("Allow Title Reporting", value)

    async def async_set_allow_title_setting(self, value: bool):
        """
        Sets whether the session title can be changed by escape sequence

        :param value: A bool
        """
        return await self._async_simple_set("Allow Title Setting", value)

    async def async_set_disable_printing(self, value: bool):
        """
        Sets whether printing by escape sequence is disabled.

        :param value: A bool
        """
        return await self._async_simple_set("Disable Printing", value)

    async def async_set_disable_smcup_rmcup(self, value: bool):
        """
        Sets whether alternate screen mode is disabled

        :param value: A bool
        """
        return await self._async_simple_set("Disable Smcup Rmcup", value)

    async def async_set_silence_bell(self, value: bool):
        """
        Sets whether the bell makes noise.

        :param value: A bool
        """
        return await self._async_simple_set("Silence Bell", value)

    async def async_set_bm_growl(self, value: bool):
        """
        Sets whether notifications should be shown.

        :param value: A bool
        """
        return await self._async_simple_set("BM Growl", value)

    async def async_set_send_bell_alert(self, value: bool):
        """
        Sets whether notifications should be shown for the bell ringing

        :param value: A bool
        """
        return await self._async_simple_set("Send Bell Alert", value)

    async def async_set_send_idle_alert(self, value: bool):
        """
        Sets whether notifications should be shown for becoming idle

        :param value: A bool
        """
        return await self._async_simple_set("Send Idle Alert", value)

    async def async_set_send_new_output_alert(self, value: bool):
        """
        Sets whether notifications should be shown for new output

        :param value: A bool
        """
        return await self._async_simple_set("Send New Output Alert", value)

    async def async_set_send_session_ended_alert(self, value: bool):
        """
        Sets whether notifications should be shown for a session ending

        :param value: A bool
        """
        return await self._async_simple_set("Send Session Ended Alert", value)

    async def async_set_send_terminal_generated_alerts(self, value: bool):
        """
        Sets whether notifications should be shown for escape-sequence
        originated notifications

        :param value: A bool
        """
        return await self._async_simple_set("Send Terminal Generated Alerts", value)

    async def async_set_flashing_bell(self, value: bool):
        """
        Sets whether the bell should flash the screen

        :param value: A bool
        """
        return await self._async_simple_set("Flashing Bell", value)

    async def async_set_visual_bell(self, value: bool):
        """
        Sets whether a bell should be shown when the bell rings

        :param value: A bool
        """
        return await self._async_simple_set("Visual Bell", value)

    async def async_set_close_sessions_on_end(self, value: bool):
        """
        Sets whether the session should close when it ends.

        :param value: A bool
        """
        return await self._async_simple_set("Close Sessions On End", value)

    async def async_set_prompt_before_closing(self, value: bool):
        """
        Sets whether the session should prompt before closing.

        :param value: A bool
        """
        return await self._async_simple_set("Prompt Before Closing 2", value)

    async def async_set_session_close_undo_timeout(self, value: float):
        """
        Sets the amount of time you can undo closing a session

        The value is at least 0.
        """
        return await self._async_simple_set("Session Close Undo Timeout", value)

    async def async_set_reduce_flicker(self, value: bool):
        """
        Sets whether the flicker fixer is on.

        :param value: A bool
        """
        return await self._async_simple_set("Reduce Flicker", value)

    async def async_set_send_code_when_idle(self, value: bool):
        """
        Sets whether to send a code when idle

        :param value: A bool
        """
        return await self._async_simple_set("Send Code When Idle", value)

    async def async_set_application_keypad_allowed(self, value: bool):
        """
        Sets whether the terminal may be placed in application keypad mode

        :param value: A bool
        """
        return await self._async_simple_set("Application Keypad Allowed", value)

    async def async_set_place_prompt_at_first_column(self, value: bool):
        """
        Sets whether the prompt should always begin at the first column
        (requires shell integration)

        :param value: A bool
        """
        return await self._async_simple_set("Place Prompt at First Column", value)

    async def async_set_show_mark_indicators(self, value: bool):
        """
        Sets whether mark indicators should be visible

        :param value: A bool
        """
        return await self._async_simple_set("Show Mark Indicators", value)

    async def async_set_idle_code(self, value: int):
        """
        Sets the ASCII code to send on idle

        Value is an int in 0 through 255.
        """
        return await self._async_simple_set("Idle Code", value)

    async def async_set_idle_period(self, value: float):
        """
        Sets how often to send a code when idle

        Value is a float at least 0
        """
        return await self._async_simple_set("Idle Period", value)

    async def async_set_unicode_version(self, value: bool):
        """
        Sets the unicode version for wcwidth

        :param value: A bool
        """
        return await self._async_simple_set("Unicode Version", value)

    async def async_set_cursor_type(self, value: CursorType):
        """
        Sets the cursor type

        :param value: A CursorType
        """
        return await self._async_simple_set("Cursor Type", value)

    async def async_set_thin_strokes(self, value: ThinStrokes):
        """
        Sets whether thin strokes are used.

        :param value: A ThinStrokes
        """
        return await self._async_simple_set("Thin Strokes", value)

    async def async_set_unicode_normalization(self, value: UnicodeNormalization):
        """
        Sets the unicode normalization form to use

        :param value: An UnicodeNormalization
        """
        return await self._async_simple_set("Unicode Normalization", value)

    async def async_set_character_encoding(self, value: CharacterEncoding):
        """
        Sets the character encoding

        :param value: A CharacterEncoding
        """
        return await self._async_simple_set("Character Encoding", value)

    async def async_set_left_option_key_sends(self, value: OptionKeySends):
        """
        Sets the behavior of the left option key.

        :param value: An OptionKeySends
        """
        return await self._async_simple_set("Option Key Sends", value)

    async def async_set_right_option_key_sends(self, value: OptionKeySends):
        """
        Sets the behavior of the right option key.

        :param value: An OptionKeySends
        """
        return await self._async_simple_set("Right Option Key Sends", value)

    async def async_set_triggers(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """
        Sets the triggers.

        Value is an encoded trigger. Use iterm2.decode_trigger to convert from
        an encoded trigger to an object. Trigger objects can be encoded using
        the encode property.
        """
        return await self._async_simple_set("Triggers", value)

    async def async_set_smart_selection_rules(self, value: typing.List[typing.Dict[str, typing.Any]]):
        """
        Sets the smart selection rules.

        The value is a list of dicts of smart selection rules (currently
        undocumented)
        """
        return await self._async_simple_set("Smart Selection Rules", value)

    async def async_set_semantic_history(self, value: typing.Dict[str, typing.Any]):
        """
        Sets the semantic history prefs.

        :param value: A typing.Dict[str, typing.Any]
        """
        return await self._async_simple_set("Semantic History", value)

    async def async_set_automatic_profile_switching_rules(self, value: typing.List[str]):
        """
        Sets the automatic profile switching rules.

        Value is a list of strings, each giving a rule.
        """
        return await self._async_simple_set("Bound Hosts", value)

    async def async_set_advanced_working_directory_window_setting(self, value: InitialWorkingDirectory):
        """
        Sets the advanced working directory window setting.

        Value excludes Advanced.
        """
        return await self._async_simple_set("AWDS Window Option", value)

    async def async_set_advanced_working_directory_window_directory(self, value: str):
        """
        Sets the advanced working directory window directory.

        :param value: A str
        """
        return await self._async_simple_set("AWDS Window Directory", value)

    async def async_set_advanced_working_directory_tab_setting(self, value: InitialWorkingDirectory):
        """
        Sets the advanced working directory tab setting.

        Value excludes Advanced.
        """
        return await self._async_simple_set("AWDS Tab Option", value)

    async def async_set_advanced_working_directory_tab_directory(self, value: str):
        """
        Sets the advanced working directory tab directory.

        :param value: A str
        """
        return await self._async_simple_set("AWDS Tab Directory", value)

    async def async_set_advanced_working_directory_pane_setting(self, value: InitialWorkingDirectory):
        """
        Sets the advanced working directory pane setting.

        Value excludes Advanced.
        """
        return await self._async_simple_set("AWDS Pane Option", value)

    async def async_set_advanced_working_directory_pane_directory(self, value: str):
        """
        Sets the advanced working directory pane directory.

        :param value: A str
        """
        return await self._async_simple_set("AWDS Pane Directory", value)

    async def async_set_normal_font(self, value: str):
        """
        Sets the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii. The value is a font's
        name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"
        """
        return await self._async_simple_set("Normal Font", value)

    async def async_set_non_ascii_font(self, value: str):
        """
        Sets the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.
        The value is the font name and size as a string.
        """
        return await self._async_simple_set("Non Ascii Font", value)

    async def async_set_background_image_location(self, value: str):
        """
        Sets the path to the background image.

        The value is a Path.
        """
        return await self._async_simple_set("Background Image Location", value)

    async def async_set_key_mappings(self, value: typing.Dict[str, typing.Any]):
        """
        Sets the keyboard shortcuts.

        The value is a Dictionary mapping keystroke to action. You can convert
        between the values in this dictionary and a :class:`~iterm2.KeyBinding`
        using `iterm2.decode_key_binding`
        """
        return await self._async_simple_set("Keyboard Map", value)

    async def async_set_touchbar_mappings(self, value: typing.Dict[str, typing.Any]):
        """
        Sets the touchbar actions.

        The value is a Dictionary mapping touch bar item to action
        """
        return await self._async_simple_set("Touch Bar Map", value)

    async def async_set_use_custom_command(self, value: str):
        """
        Sets whether to use a custom command when the session is created.

        The value is the string Yes or No
        """
        return await self._async_simple_set("Custom Command", value)

    async def async_set_command(self, value: str):
        """
        Sets the command to run when the session starts.

        The value is a string giving the command to run
        """
        return await self._async_simple_set("Command", value)

    async def async_set_initial_directory_mode(self, value: InitialWorkingDirectory):
        """
        Sets whether to use a custom (not home) initial working directory.

        :param value: An InitialWorkingDirectory
        """
        return await self._async_simple_set("Custom Directory", value.value)

    async def async_set_custom_directory(self, value: str):
        """
        Sets the initial working directory.

        The initial_directory_mode must be set to
        `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
        take effect.
        """
        return await self._async_simple_set("Working Directory", value)

    async def async_set_icon_mode(self, value: IconMode):
        """
        Sets the icon mode.

        :param value: An IconMode
        """
        return await self._async_simple_set("Icon", value.value)

    async def async_set_custom_icon_path(self, value: str):
        """
        Sets the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.
        """
        return await self._async_simple_set("Custom Icon Path", value)

    async def async_set_badge_top_margin(self, value: int):
        """
        Sets the top margin of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Top Margin", value)

    async def async_set_badge_right_margin(self, value: int):
        """
        Sets the right margin of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Right Margin", value)

    async def async_set_badge_max_width(self, value: int):
        """
        Sets the max width of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Max Width", value)

    async def async_set_badge_max_height(self, value: int):
        """
        Sets the max height of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Max Height", value)

    async def async_set_badge_font(self, value: str):
        """
        Sets the font of the badge.

        The font name is a string like "Helvetica".
        """
        return await self._async_simple_set("Badge Font", value)

    async def async_set_use_custom_window_title(self, value: bool):
        """
        Sets whether the custom window title is used.

        Should the custom window title in the profile be used?
        """
        return await self._async_simple_set("Use Custom Window Title", value)

    async def async_set_custom_window_title(self, value: typing.Optional[str]):
        """
        Sets the custom window title.

        This will only be used if use_custom_window_title is True.
        The value is an interpolated string.
        """
        return await self._async_simple_set("Custom Window Title", value)

    async def async_set_use_transparency_initially(self, value: bool):
        """
        Sets whether a window created with this profile respect the
        transparency setting.

        If True, use transparency; if False, force the window to
        be opaque (but it can be toggled with View > Use Transparency).
        """
        return await self._async_simple_set("Initial Use Transparency", value)

    async def async_set_status_bar_enabled(self, value: bool):
        """
        Sets whether the status bar be enabled.

        If True, the status bar will be shown.
        """
        return await self._async_simple_set("Show Status Bar", value)

    async def async_set_use_csi_u(self, value: bool):
        """
        Sets whether to report keystrokes with CSI u protocol.

        If True, CSI u will be enabled.
        """
        return await self._async_simple_set("Use libtickit protocol", value)

    async def async_set_triggers_use_interpolated_strings(self, value: bool):
        """
        Sets whether trigger parameters should be interpreted as interpolated
        strings.

        :param value: A bool
        """
        return await self._async_simple_set("Triggers Use Interpolated Strings", value)

    async def async_set_left_option_key_changeable(self, value: bool):
        """
        Sets whether apps should be able to change the left option key to send
        esc+.

        The values gives whether it should be allowed.
        """
        return await self._async_simple_set("Left Option Key Changeable", value)

    async def async_set_right_option_key_changeable(self, value: bool):
        """
        Sets whether apps should be able to change the right option key to send
        esc+.

        The values gives whether it should be allowed.
        """
        return await self._async_simple_set("Right Option Key Changeable", value)

    async def async_set_open_password_manager_automatically(self, value: bool):
        """
        Sets if the password manager should open automatically.

        The values gives whether it should open automatically.
        """
        return await self._async_simple_set("Open Password Manager Automatically", value)

class Profile(WriteOnlyProfile):
    """Represents a profile.

    If a session_id is set then this is the profile attached to a session.
    Otherwise, it is a shared profile."""

    USE_CUSTOM_COMMAND_ENABLED = "Yes"
    USE_CUSTOM_COMMAND_DISABLED = "No"

    @staticmethod
    async def async_get(connection, guids=None) -> typing.List['Profile']:
        """Fetches all profiles with the specified GUIDs.

        :param guids: The profiles to get, or if `None` then all will be
            returned.

        :returns: A list of :class:`Profile` objects.
        """
        response = await iterm2.rpc.async_list_profiles(
            connection, guids, None)
        profiles = []
        for response_profile in response.list_profiles_response.profiles:
            profile = Profile(None, connection, response_profile.properties)
            profiles.append(profile)
        return profiles

    @staticmethod
    async def async_get_default(connection) -> 'Profile':
        """Returns the default profile."""
        iterm2.capabilities.check_supports_get_default_profile(connection)
        result = await iterm2.rpc.async_get_default_profile(connection)
        guid = (result.preferences_response.results[0].
                get_default_profile_result.guid)
        profiles = await Profile.async_get(connection, [guid])
        return profiles[0]

    def __init__(self, session_id, connection, profile_property_list):
        props = {}
        for prop in profile_property_list:
            props[prop.key] = json.loads(prop.json_value)

        guid_key = "Guid"
        guid = props.get(guid_key, None)

        super().__init__(session_id, connection, guid)

        self.connection = connection
        self.session_id = session_id
        self.__props = props

    def _simple_get(self, key):
        if key in self.__props:
            return self.__props[key]
        return None

    def _get_optional_bool(self, key):
        if key not in self.__props:
            return None
        return bool(self.__props[key])

    def get_color_with_key(self, key):
        """Returns the color for the request key, or None.

        :param key: A string describing the color. Corresponds to the keys in
            :class:`~iterm2.ColorPreset.Color`.

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
    def local_write_only_copy(self) -> LocalWriteOnlyProfile:
        """
        Returns a :class:`~iterm2.profile.LocalWriteOnlyProfile` containing the
        properties in this profile.
        """
        return LocalWriteOnlyProfile(self.__props)

    @property
    def all_properties(self):
        """Returns the internal dictionary value."""
        return dict(self.__props)

    @property
    def title_components(
            self) -> typing.Optional[typing.List[TitleComponents]]:
        """
        Returns which components are visible in the session's title, or selects
        a custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        parts = []
        bit = 1
        value = self._simple_get("Title Components")
        while bit <= value:
            if bit & value:
                parts.append(TitleComponents(bit))
            bit *= 2
        return parts

    @property
    def title_function(self) -> typing.Optional[typing.Tuple[str, str]]:
        """
        Returns the function call for the session title provider and its
        display name for the UI.

        :returns: (display name, unique identifier)
        """
        values = self._simple_get("Title Function")
        return (values[0], values[1])

    async def async_make_default(self):
        """Makes this profile the default profile."""
        await iterm2.rpc.async_set_default_profile(self.connection, self.guid)

    @property
    def guid(self):
        """Returns globally unique ID for this profile.

        :returns: A string identifying this profile
        """
        return self._simple_get("Guid")

    @property
    def original_guid(self):
        """The GUID of the original profile from which this one was derived.

        Used for sessions whose profile has been modified from the underlying
        profile. Otherwise not set.

        :returns: Guid
        """
        return self._simple_get("Original Guid")

    @property
    def dynamic_profile_parent_name(self):
        """
        If the profile is a dynamic profile, returns the name of the parent
        profile.

        :returns: String name
        """
        return self._simple_get("Dynamic Profile Parent Name")

    @property
    def dynamic_profile_file_name(self):
        """If the profile is a dynamic profile, returns the path to the file
        from which it came.

        :returns: String file name
        """
        return self._simple_get("Dynamic Profile Filename")

    @property
    def use_separate_colors_for_light_and_dark_mode(self) -> bool:
        """
        Returns whether to use separate colors for light and dark mode.

        When this is enabled, use [set_]xxx_color_light and
        set_[xxx_]color_dark instead of [set_]xxx_color.

        :returns: A bool
        """
        return self._simple_get("Use Separate Colors for Light and Dark Mode")

    @property
    def foreground_color(self) -> 'iterm2.color.Color':
        """
        Returns the foreground color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Foreground Color")

    @property
    def foreground_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the foreground color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Foreground Color (Light)")

    @property
    def foreground_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the foreground color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Foreground Color (Dark)")

    @property
    def background_color(self) -> 'iterm2.color.Color':
        """
        Returns the background color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Background Color")

    @property
    def background_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the background color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Background Color (Light)")

    @property
    def background_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the background color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Background Color (Dark)")

    @property
    def bold_color(self) -> 'iterm2.color.Color':
        """
        Returns the bold text color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Bold Color")

    @property
    def bold_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the bold text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Bold Color (Light)")

    @property
    def bold_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the bold text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Bold Color (Dark)")

    @property
    def use_bright_bold(self) -> bool:
        """
        Returns  how bold text is rendered. This is used only when separate
        light/dark mode colors are not enabled.

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

        :returns: A bool
        """
        return self._simple_get("Use Bright Bold")

    @property
    def use_bright_bold_light(self) -> bool:
        """
        Returns  how bold text is rendered. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

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

        :returns: A bool
        """
        return self._simple_get("Use Bright Bold (Light)")

    @property
    def use_bright_bold_dark(self) -> bool:
        """
        Returns  how bold text is rendered. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

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

        :returns: A bool
        """
        return self._simple_get("Use Bright Bold (Dark)")

    @property
    def use_bold_color(self) -> bool:
        """
        Returns whether the profile-specified bold color is used for
        default-colored bold text. This is used only when separate light/dark
        mode colors are not enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        use_bright_bold().

        :returns: A bool
        """
        return self._simple_get("Use Bright Bold")

    @property
    def use_bold_color_light(self) -> bool:
        """
        Returns whether the profile-specified bold color is used for
        default-colored bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        use_bright_bold().

        :returns: A bool
        """
        return self._simple_get("Use Bright Bold (Light)")

    @property
    def use_bold_color_dark(self) -> bool:
        """
        Returns whether the profile-specified bold color is used for
        default-colored bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        use_bright_bold().

        :returns: A bool
        """
        return self._simple_get("Use Bright Bold (Dark)")

    @property
    def brighten_bold_text(self) -> bool:
        """
        Returns whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This is used only when separate light/dark
        mode colors are not enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :returns: A bool
        """
        return self._simple_get("Brighten Bold Text")

    @property
    def brighten_bold_text_light(self) -> bool:
        """
        Returns whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :returns: A bool
        """
        return self._simple_get("Brighten Bold Text (Light)")

    @property
    def brighten_bold_text_dark(self) -> bool:
        """
        Returns whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :returns: A bool
        """
        return self._simple_get("Brighten Bold Text (Dark)")

    @property
    def link_color(self) -> 'iterm2.color.Color':
        """
        Returns the link color. This is used only when separate light/dark mode
        colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Link Color")

    @property
    def link_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the link color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Link Color (Light)")

    @property
    def link_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the link color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Link Color (Dark)")

    @property
    def selection_color(self) -> 'iterm2.color.Color':
        """
        Returns the selection background color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Selection Color")

    @property
    def selection_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the selection background color. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Selection Color (Light)")

    @property
    def selection_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the selection background color. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Selection Color (Dark)")

    @property
    def selected_text_color(self) -> 'iterm2.color.Color':
        """
        Returns the selection text color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Selected Text Color")

    @property
    def selected_text_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the selection text color. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Selected Text Color (Light)")

    @property
    def selected_text_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the selection text color. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Selected Text Color (Dark)")

    @property
    def cursor_color(self) -> 'iterm2.color.Color':
        """
        Returns the cursor color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Color")

    @property
    def cursor_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the cursor color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Color (Light)")

    @property
    def cursor_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the cursor color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Color (Dark)")

    @property
    def cursor_text_color(self) -> 'iterm2.color.Color':
        """
        Returns the cursor text color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Text Color")

    @property
    def cursor_text_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the cursor text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Text Color (Light)")

    @property
    def cursor_text_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the cursor text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Text Color (Dark)")

    @property
    def ansi_0_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 0 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 0 Color")

    @property
    def ansi_0_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 0 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 0 Color (Light)")

    @property
    def ansi_0_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 0 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 0 Color (Dark)")

    @property
    def ansi_1_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 1 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 1 Color")

    @property
    def ansi_1_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 1 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 1 Color (Light)")

    @property
    def ansi_1_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 1 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 1 Color (Dark)")

    @property
    def ansi_2_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 2 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 2 Color")

    @property
    def ansi_2_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 2 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 2 Color (Light)")

    @property
    def ansi_2_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 2 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 2 Color (Dark)")

    @property
    def ansi_3_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 3 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 3 Color")

    @property
    def ansi_3_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 3 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 3 Color (Light)")

    @property
    def ansi_3_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 3 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 3 Color (Dark)")

    @property
    def ansi_4_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 4 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 4 Color")

    @property
    def ansi_4_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 4 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 4 Color (Light)")

    @property
    def ansi_4_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 4 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 4 Color (Dark)")

    @property
    def ansi_5_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 5 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 5 Color")

    @property
    def ansi_5_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 5 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 5 Color (Light)")

    @property
    def ansi_5_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 5 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 5 Color (Dark)")

    @property
    def ansi_6_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 6 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 6 Color")

    @property
    def ansi_6_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 6 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 6 Color (Light)")

    @property
    def ansi_6_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 6 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 6 Color (Dark)")

    @property
    def ansi_7_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 7 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 7 Color")

    @property
    def ansi_7_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 7 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 7 Color (Light)")

    @property
    def ansi_7_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 7 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 7 Color (Dark)")

    @property
    def ansi_8_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 8 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 8 Color")

    @property
    def ansi_8_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 8 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 8 Color (Light)")

    @property
    def ansi_8_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 8 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 8 Color (Dark)")

    @property
    def ansi_9_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 9 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 9 Color")

    @property
    def ansi_9_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 9 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 9 Color (Light)")

    @property
    def ansi_9_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 9 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 9 Color (Dark)")

    @property
    def ansi_10_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 10 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 10 Color")

    @property
    def ansi_10_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 10 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 10 Color (Light)")

    @property
    def ansi_10_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 10 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 10 Color (Dark)")

    @property
    def ansi_11_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 11 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 11 Color")

    @property
    def ansi_11_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 11 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 11 Color (Light)")

    @property
    def ansi_11_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 11 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 11 Color (Dark)")

    @property
    def ansi_12_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 12 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 12 Color")

    @property
    def ansi_12_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 12 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 12 Color (Light)")

    @property
    def ansi_12_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 12 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 12 Color (Dark)")

    @property
    def ansi_13_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 13 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 13 Color")

    @property
    def ansi_13_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 13 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 13 Color (Light)")

    @property
    def ansi_13_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 13 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 13 Color (Dark)")

    @property
    def ansi_14_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 14 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 14 Color")

    @property
    def ansi_14_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 14 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 14 Color (Light)")

    @property
    def ansi_14_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 14 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 14 Color (Dark)")

    @property
    def ansi_15_color(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 15 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 15 Color")

    @property
    def ansi_15_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 15 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 15 Color (Light)")

    @property
    def ansi_15_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the ANSI 15 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Ansi 15 Color (Dark)")

    @property
    def smart_cursor_color(self) -> bool:
        """
        Returns whether to use smart cursor color. This only applies to box
        cursors. This is used only when separate light/dark mode colors are not
        enabled.

        :returns: A bool
        """
        return self._simple_get("Smart Cursor Color")

    @property
    def smart_cursor_color_light(self) -> bool:
        """
        Returns whether to use smart cursor color. This only applies to box
        cursors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Smart Cursor Color (Light)")

    @property
    def smart_cursor_color_dark(self) -> bool:
        """
        Returns whether to use smart cursor color. This only applies to box
        cursors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Smart Cursor Color (Dark)")

    @property
    def minimum_contrast(self) -> float:
        """
        Returns the minimum contrast, in 0 to 1. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A float
        """
        return self._simple_get("Minimum Contrast")

    @property
    def minimum_contrast_light(self) -> float:
        """
        Returns the minimum contrast, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float
        """
        return self._simple_get("Minimum Contrast (Light)")

    @property
    def minimum_contrast_dark(self) -> float:
        """
        Returns the minimum contrast, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float
        """
        return self._simple_get("Minimum Contrast (Dark)")

    @property
    def tab_color(self) -> 'iterm2.color.Color':
        """
        Returns the tab color. This is used only when separate light/dark mode
        colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Tab Color")

    @property
    def tab_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the tab color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Tab Color (Light)")

    @property
    def tab_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the tab color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Tab Color (Dark)")

    @property
    def use_tab_color(self) -> bool:
        """
        Returns whether the tab color should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A bool
        """
        return self._simple_get("Use Tab Color")

    @property
    def use_tab_color_light(self) -> bool:
        """
        Returns whether the tab color should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Use Tab Color (Light)")

    @property
    def use_tab_color_dark(self) -> bool:
        """
        Returns whether the tab color should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Use Tab Color (Dark)")

    @property
    def underline_color(self) -> typing.Optional['iterm2.color.Color']:
        """
        Returns the underline color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A typing.Optional['iterm2.color.Color']
        """
        return self.get_color_with_key("Underline Color")

    @property
    def underline_color_light(self) -> typing.Optional['iterm2.color.Color']:
        """
        Returns the underline color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A typing.Optional['iterm2.color.Color']
        """
        return self.get_color_with_key("Underline Color (Light)")

    @property
    def underline_color_dark(self) -> typing.Optional['iterm2.color.Color']:
        """
        Returns the underline color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A typing.Optional['iterm2.color.Color']
        """
        return self.get_color_with_key("Underline Color (Dark)")

    @property
    def use_underline_color(self) -> bool:
        """
        Returns whether to use the specified underline color. This is used only
        when separate light/dark mode colors are not enabled.

        :returns: A bool
        """
        return self._simple_get("Use Underline Color")

    @property
    def use_underline_color_light(self) -> bool:
        """
        Returns whether to use the specified underline color. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Use Underline Color (Light)")

    @property
    def use_underline_color_dark(self) -> bool:
        """
        Returns whether to use the specified underline color. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Use Underline Color (Dark)")

    @property
    def cursor_boost(self) -> float:
        """
        Returns the cursor boost level, in 0 to 1. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A float
        """
        return self._simple_get("Cursor Boost")

    @property
    def cursor_boost_light(self) -> float:
        """
        Returns the cursor boost level, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float
        """
        return self._simple_get("Cursor Boost (Light)")

    @property
    def cursor_boost_dark(self) -> float:
        """
        Returns the cursor boost level, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float
        """
        return self._simple_get("Cursor Boost (Dark)")

    @property
    def use_cursor_guide(self) -> bool:
        """
        Returns whether the cursor guide should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A bool
        """
        return self._simple_get("Use Cursor Guide")

    @property
    def use_cursor_guide_light(self) -> bool:
        """
        Returns whether the cursor guide should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Use Cursor Guide (Light)")

    @property
    def use_cursor_guide_dark(self) -> bool:
        """
        Returns whether the cursor guide should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool
        """
        return self._simple_get("Use Cursor Guide (Dark)")

    @property
    def cursor_guide_color(self) -> 'iterm2.color.Color':
        """
        Returns the cursor guide color. The alpha value is respected. This is
        used only when separate light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Guide Color")

    @property
    def cursor_guide_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the cursor guide color. The alpha value is respected. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Guide Color (Light)")

    @property
    def cursor_guide_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the cursor guide color. The alpha value is respected. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Cursor Guide Color (Dark)")

    @property
    def badge_color(self) -> 'iterm2.color.Color':
        """
        Returns the badge color. The alpha value is respected. This is used
        only when separate light/dark mode colors are not enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Badge Color")

    @property
    def badge_color_light(self) -> 'iterm2.color.Color':
        """
        Returns the badge color. The alpha value is respected. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Badge Color (Light)")

    @property
    def badge_color_dark(self) -> 'iterm2.color.Color':
        """
        Returns the badge color. The alpha value is respected. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color`
        """
        return self.get_color_with_key("Badge Color (Dark)")

    @property
    def name(self) -> str:
        """
        Returns the name.

        :returns: A str
        """
        return self._simple_get("Name")

    @property
    def badge_text(self) -> str:
        """
        Returns the badge text.

        :returns: A str
        """
        return self._simple_get("Badge Text")

    @property
    def subtitle(self) -> str:
        """
        Returns the subtitle, an interpolated string.

        :returns: A str
        """
        return self._simple_get("Subtitle")

    @property
    def answerback_string(self) -> str:
        """
        Returns the answerback string.

        :returns: A str
        """
        return self._simple_get("Answerback String")

    @property
    def blinking_cursor(self) -> bool:
        """
        Returns whether the cursor blinks.

        :returns: A bool
        """
        return self._simple_get("Blinking Cursor")

    @property
    def use_bold_font(self) -> bool:
        """
        Returns whether to use the bold variant of the font for bold text.

        :returns: A bool
        """
        return self._simple_get("Use Bold Font")

    @property
    def ascii_ligatures(self) -> bool:
        """
        Returns whether ligatures should be used for ASCII text.

        :returns: A bool
        """
        return self._simple_get("ASCII Ligatures")

    @property
    def non_ascii_ligatures(self) -> bool:
        """
        Returns whether ligatures should be used for non-ASCII text.

        :returns: A bool
        """
        return self._simple_get("Non-ASCII Ligatures")

    @property
    def blink_allowed(self) -> bool:
        """
        Returns whether blinking text is allowed.

        :returns: A bool
        """
        return self._simple_get("Blink Allowed")

    @property
    def use_italic_font(self) -> bool:
        """
        Returns whether italic text is allowed.

        :returns: A bool
        """
        return self._simple_get("Use Italic Font")

    @property
    def ambiguous_double_width(self) -> bool:
        """
        Returns whether ambiguous-width text should be treated as double-width.

        :returns: A bool
        """
        return self._simple_get("Ambiguous Double Width")

    @property
    def horizontal_spacing(self) -> float:
        """
        Returns the fraction of horizontal spacing. Must be non-negative.

        :returns: A float
        """
        return self._simple_get("Horizontal Spacing")

    @property
    def vertical_spacing(self) -> float:
        """
        Returns the fraction of vertical spacing. Must be non-negative.

        :returns: A float
        """
        return self._simple_get("Vertical Spacing")

    @property
    def use_non_ascii_font(self) -> bool:
        """
        Returns whether to use a different font for non-ASCII text.

        :returns: A bool
        """
        return self._simple_get("Use Non-ASCII Font")

    @property
    def transparency(self) -> float:
        """
        Returns the level of transparency.

        The value is between 0 and 1.

        :returns: A float
        """
        return self._simple_get("Transparency")

    @property
    def blur(self) -> bool:
        """
        Returns whether background blur should be enabled.

        :returns: A bool
        """
        return self._simple_get("Blur")

    @property
    def blur_radius(self) -> float:
        """
        Returns the blur radius (how blurry). Requires blur to be enabled.

        The value is between 0 and 30.

        :returns: A float
        """
        return self._simple_get("Blur Radius")

    @property
    def background_image_mode(self) -> BackgroundImageMode:
        """
        Returns how the background image is drawn.

        :returns: A `BackgroundImageMode`
        """
        return BackgroundImageMode(self._simple_get("Background Image Mode"))

    @property
    def blend(self) -> float:
        """
        Returns how much the default background color gets blended with the
        background image.

        The value is in 0 to 1.

        .. seealso:: Example ":ref:`blending_example`

        :returns: A float
        """
        return self._simple_get("Blend")

    @property
    def sync_title(self) -> bool:
        """
        Returns whether the profile name stays in the tab title, even if
        changed by an escape sequence.

        :returns: A bool
        """
        return self._simple_get("Sync Title")

    @property
    def use_built_in_powerline_glyphs(self) -> bool:
        """
        Returns whether powerline glyphs should be drawn by iTerm2 or left to
        the font.

        :returns: A bool
        """
        return bool(self._simple_get("Draw Powerline Glyphs"))

    @property
    def disable_window_resizing(self) -> bool:
        """
        Returns whether the terminal can resize the window with an escape
        sequence.

        :returns: A bool
        """
        return self._simple_get("Disable Window Resizing")

    @property
    def only_the_default_bg_color_uses_transparency(self) -> bool:
        """
        Returns whether window transparency shows through non-default
        background colors.

        :returns: A bool
        """
        return self._simple_get("Only The Default BG Color Uses Transparency")

    @property
    def ascii_anti_aliased(self) -> bool:
        """
        Returns whether ASCII text is anti-aliased.

        :returns: A bool
        """
        return self._simple_get("ASCII Anti Aliased")

    @property
    def non_ascii_anti_aliased(self) -> bool:
        """
        Returns whether non-ASCII text is anti-aliased.

        :returns: A bool
        """
        return self._simple_get("Non-ASCII Anti Aliased")

    @property
    def scrollback_lines(self) -> int:
        """
        Returns the number of scrollback lines.

        Value must be at least 0.

        :returns: An int
        """
        return self._simple_get("Scrollback Lines")

    @property
    def unlimited_scrollback(self) -> bool:
        """
        Returns whether the scrollback buffer's length is unlimited.

        :returns: A bool
        """
        return self._simple_get("Unlimited Scrollback")

    @property
    def scrollback_with_status_bar(self) -> bool:
        """
        Returns whether text gets appended to scrollback when there is an app
        status bar

        :returns: A bool
        """
        return self._simple_get("Scrollback With Status Bar")

    @property
    def scrollback_in_alternate_screen(self) -> bool:
        """
        Returns whether text gets appended to scrollback in alternate screen
        mode.

        :returns: A bool
        """
        return self._simple_get("Scrollback in Alternate Screen")

    @property
    def mouse_reporting(self) -> bool:
        """
        Returns whether mouse reporting is allowed

        :returns: A bool
        """
        return self._simple_get("Mouse Reporting")

    @property
    def mouse_reporting_allow_mouse_wheel(self) -> bool:
        """
        Returns whether mouse reporting reports the mouse wheel's movements.

        :returns: A bool
        """
        return self._simple_get("Mouse Reporting allow mouse wheel")

    @property
    def allow_title_reporting(self) -> bool:
        """
        Returns whether the session title can be reported

        :returns: A bool
        """
        return self._simple_get("Allow Title Reporting")

    @property
    def allow_title_setting(self) -> bool:
        """
        Returns whether the session title can be changed by escape sequence

        :returns: A bool
        """
        return self._simple_get("Allow Title Setting")

    @property
    def disable_printing(self) -> bool:
        """
        Returns whether printing by escape sequence is disabled.

        :returns: A bool
        """
        return self._simple_get("Disable Printing")

    @property
    def disable_smcup_rmcup(self) -> bool:
        """
        Returns whether alternate screen mode is disabled

        :returns: A bool
        """
        return self._simple_get("Disable Smcup Rmcup")

    @property
    def silence_bell(self) -> bool:
        """
        Returns whether the bell makes noise.

        :returns: A bool
        """
        return self._simple_get("Silence Bell")

    @property
    def bm_growl(self) -> bool:
        """
        Returns whether notifications should be shown.

        :returns: A bool
        """
        return self._simple_get("BM Growl")

    @property
    def send_bell_alert(self) -> bool:
        """
        Returns whether notifications should be shown for the bell ringing

        :returns: A bool
        """
        return self._simple_get("Send Bell Alert")

    @property
    def send_idle_alert(self) -> bool:
        """
        Returns whether notifications should be shown for becoming idle

        :returns: A bool
        """
        return self._simple_get("Send Idle Alert")

    @property
    def send_new_output_alert(self) -> bool:
        """
        Returns whether notifications should be shown for new output

        :returns: A bool
        """
        return self._simple_get("Send New Output Alert")

    @property
    def send_session_ended_alert(self) -> bool:
        """
        Returns whether notifications should be shown for a session ending

        :returns: A bool
        """
        return self._simple_get("Send Session Ended Alert")

    @property
    def send_terminal_generated_alerts(self) -> bool:
        """
        Returns whether notifications should be shown for escape-sequence
        originated notifications

        :returns: A bool
        """
        return self._simple_get("Send Terminal Generated Alerts")

    @property
    def flashing_bell(self) -> bool:
        """
        Returns whether the bell should flash the screen

        :returns: A bool
        """
        return self._simple_get("Flashing Bell")

    @property
    def visual_bell(self) -> bool:
        """
        Returns whether a bell should be shown when the bell rings

        :returns: A bool
        """
        return self._simple_get("Visual Bell")

    @property
    def close_sessions_on_end(self) -> bool:
        """
        Returns whether the session should close when it ends.

        :returns: A bool
        """
        return self._simple_get("Close Sessions On End")

    @property
    def prompt_before_closing(self) -> bool:
        """
        Returns whether the session should prompt before closing.

        :returns: A bool
        """
        return self._simple_get("Prompt Before Closing 2")

    @property
    def session_close_undo_timeout(self) -> float:
        """
        Returns the amount of time you can undo closing a session

        The value is at least 0.

        :returns: A float
        """
        return self._simple_get("Session Close Undo Timeout")

    @property
    def reduce_flicker(self) -> bool:
        """
        Returns whether the flicker fixer is on.

        :returns: A bool
        """
        return self._simple_get("Reduce Flicker")

    @property
    def send_code_when_idle(self) -> bool:
        """
        Returns whether to send a code when idle

        :returns: A bool
        """
        return self._simple_get("Send Code When Idle")

    @property
    def application_keypad_allowed(self) -> bool:
        """
        Returns whether the terminal may be placed in application keypad mode

        :returns: A bool
        """
        return self._simple_get("Application Keypad Allowed")

    @property
    def place_prompt_at_first_column(self) -> bool:
        """
        Returns whether the prompt should always begin at the first column
        (requires shell integration)

        :returns: A bool
        """
        return self._simple_get("Place Prompt at First Column")

    @property
    def show_mark_indicators(self) -> bool:
        """
        Returns whether mark indicators should be visible

        :returns: A bool
        """
        return self._simple_get("Show Mark Indicators")

    @property
    def idle_code(self) -> int:
        """
        Returns the ASCII code to send on idle

        Value is an int in 0 through 255.

        :returns: An int
        """
        return self._simple_get("Idle Code")

    @property
    def idle_period(self) -> float:
        """
        Returns how often to send a code when idle

        Value is a float at least 0

        :returns: A float
        """
        return self._simple_get("Idle Period")

    @property
    def unicode_version(self) -> bool:
        """
        Returns the unicode version for wcwidth

        :returns: A bool
        """
        return self._simple_get("Unicode Version")

    @property
    def cursor_type(self) -> CursorType:
        """
        Returns the cursor type

        :returns: A CursorType
        """
        return self._simple_get("Cursor Type")

    @property
    def thin_strokes(self) -> ThinStrokes:
        """
        Returns whether thin strokes are used.

        :returns: A ThinStrokes
        """
        return self._simple_get("Thin Strokes")

    @property
    def unicode_normalization(self) -> UnicodeNormalization:
        """
        Returns the unicode normalization form to use

        :returns: An UnicodeNormalization
        """
        return self._simple_get("Unicode Normalization")

    @property
    def character_encoding(self) -> CharacterEncoding:
        """
        Returns the character encoding

        :returns: A CharacterEncoding
        """
        return self._simple_get("Character Encoding")

    @property
    def left_option_key_sends(self) -> OptionKeySends:
        """
        Returns the behavior of the left option key.

        :returns: An OptionKeySends
        """
        return self._simple_get("Option Key Sends")

    @property
    def right_option_key_sends(self) -> OptionKeySends:
        """
        Returns the behavior of the right option key.

        :returns: An OptionKeySends
        """
        return self._simple_get("Right Option Key Sends")

    @property
    def triggers(self) -> typing.List[typing.Dict[str, typing.Any]]:
        """
        Returns the triggers.

        Value is an encoded trigger. Use iterm2.decode_trigger to convert from
        an encoded trigger to an object. Trigger objects can be encoded using
        the encode property.

        :returns: A typing.List[typing.Dict[str, typing.Any]]
        """
        return self._simple_get("Triggers")

    @property
    def smart_selection_rules(self) -> typing.List[typing.Dict[str, typing.Any]]:
        """
        Returns the smart selection rules.

        The value is a list of dicts of smart selection rules (currently
        undocumented)

        :returns: A typing.List[typing.Dict[str, typing.Any]]
        """
        return self._simple_get("Smart Selection Rules")

    @property
    def semantic_history(self) -> typing.Dict[str, typing.Any]:
        """
        Returns the semantic history prefs.

        :returns: A typing.Dict[str, typing.Any]
        """
        return self._simple_get("Semantic History")

    @property
    def automatic_profile_switching_rules(self) -> typing.List[str]:
        """
        Returns the automatic profile switching rules.

        Value is a list of strings, each giving a rule.

        :returns: A typing.List[str]
        """
        return self._simple_get("Bound Hosts")

    @property
    def advanced_working_directory_window_setting(self) -> InitialWorkingDirectory:
        """
        Returns the advanced working directory window setting.

        Value excludes Advanced.

        :returns: An InitialWorkingDirectory
        """
        return self._simple_get("AWDS Window Option")

    @property
    def advanced_working_directory_window_directory(self) -> str:
        """
        Returns the advanced working directory window directory.

        :returns: A str
        """
        return self._simple_get("AWDS Window Directory")

    @property
    def advanced_working_directory_tab_setting(self) -> InitialWorkingDirectory:
        """
        Returns the advanced working directory tab setting.

        Value excludes Advanced.

        :returns: An InitialWorkingDirectory
        """
        return self._simple_get("AWDS Tab Option")

    @property
    def advanced_working_directory_tab_directory(self) -> str:
        """
        Returns the advanced working directory tab directory.

        :returns: A str
        """
        return self._simple_get("AWDS Tab Directory")

    @property
    def advanced_working_directory_pane_setting(self) -> InitialWorkingDirectory:
        """
        Returns the advanced working directory pane setting.

        Value excludes Advanced.

        :returns: An InitialWorkingDirectory
        """
        return self._simple_get("AWDS Pane Option")

    @property
    def advanced_working_directory_pane_directory(self) -> str:
        """
        Returns the advanced working directory pane directory.

        :returns: A str
        """
        return self._simple_get("AWDS Pane Directory")

    @property
    def normal_font(self) -> str:
        """
        Returns the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii. The value is a font's
        name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"

        :returns: A str
        """
        return self._simple_get("Normal Font")

    @property
    def non_ascii_font(self) -> str:
        """
        Returns the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.
        The value is the font name and size as a string.

        :returns: A str
        """
        return self._simple_get("Non Ascii Font")

    @property
    def background_image_location(self) -> str:
        """
        Returns the path to the background image.

        The value is a Path.

        :returns: A str
        """
        return self._simple_get("Background Image Location")

    @property
    def key_mappings(self) -> typing.Dict[str, typing.Any]:
        """
        Returns the keyboard shortcuts.

        The value is a Dictionary mapping keystroke to action. You can convert
        between the values in this dictionary and a :class:`~iterm2.KeyBinding`
        using `iterm2.decode_key_binding`

        :returns: A typing.Dict[str, typing.Any]
        """
        return self._simple_get("Keyboard Map")

    @property
    def touchbar_mappings(self) -> typing.Dict[str, typing.Any]:
        """
        Returns the touchbar actions.

        The value is a Dictionary mapping touch bar item to action

        :returns: A typing.Dict[str, typing.Any]
        """
        return self._simple_get("Touch Bar Map")

    @property
    def use_custom_command(self) -> str:
        """
        Returns whether to use a custom command when the session is created.

        The value is the string Yes or No

        :returns: A str
        """
        return self._simple_get("Custom Command")

    @property
    def command(self) -> str:
        """
        Returns the command to run when the session starts.

        The value is a string giving the command to run

        :returns: A str
        """
        return self._simple_get("Command")

    @property
    def initial_directory_mode(self) -> InitialWorkingDirectory:
        """
        Returns whether to use a custom (not home) initial working directory.

        :returns: An InitialWorkingDirectory
        """
        return self._simple_get("Custom Directory")

    @property
    def custom_directory(self) -> str:
        """
        Returns the initial working directory.

        The initial_directory_mode must be set to
        `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
        take effect.

        :returns: A str
        """
        return self._simple_get("Working Directory")

    @property
    def icon_mode(self) -> IconMode:
        """
        Returns the icon mode.

        :returns: An IconMode
        """
        return self._simple_get("Icon")

    @property
    def custom_icon_path(self) -> str:
        """
        Returns the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.

        :returns: A str
        """
        return self._simple_get("Custom Icon Path")

    @property
    def badge_top_margin(self) -> int:
        """
        Returns the top margin of the badge.

        The value is in points.

        :returns: An int
        """
        return self._simple_get("Badge Top Margin")

    @property
    def badge_right_margin(self) -> int:
        """
        Returns the right margin of the badge.

        The value is in points.

        :returns: An int
        """
        return self._simple_get("Badge Right Margin")

    @property
    def badge_max_width(self) -> int:
        """
        Returns the max width of the badge.

        The value is in points.

        :returns: An int
        """
        return self._simple_get("Badge Max Width")

    @property
    def badge_max_height(self) -> int:
        """
        Returns the max height of the badge.

        The value is in points.

        :returns: An int
        """
        return self._simple_get("Badge Max Height")

    @property
    def badge_font(self) -> str:
        """
        Returns the font of the badge.

        The font name is a string like "Helvetica".

        :returns: A str
        """
        return self._simple_get("Badge Font")

    @property
    def use_custom_window_title(self) -> bool:
        """
        Returns whether the custom window title is used.

        Should the custom window title in the profile be used?

        :returns: A bool
        """
        return self._simple_get("Use Custom Window Title")

    @property
    def custom_window_title(self) -> typing.Optional[str]:
        """
        Returns the custom window title.

        This will only be used if use_custom_window_title is True.
        The value is an interpolated string.

        :returns: A typing.Optional[str]
        """
        return self._simple_get("Custom Window Title")

    @property
    def use_transparency_initially(self) -> typing.Optional[bool]:
        """
        Returns whether a window created with this profile respect the
        transparency setting.

        If True, use transparency; if False, force the window to
        be opaque (but it can be toggled with View > Use Transparency).

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Initial Use Transparency")

    @property
    def status_bar_enabled(self) -> typing.Optional[bool]:
        """
        Returns whether the status bar be enabled.

        If True, the status bar will be shown.

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Show Status Bar")

    @property
    def use_csi_u(self) -> typing.Optional[bool]:
        """
        Returns whether to report keystrokes with CSI u protocol.

        If True, CSI u will be enabled.

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Use libtickit protocol")

    @property
    def triggers_use_interpolated_strings(self) -> typing.Optional[bool]:
        """
        Returns whether trigger parameters should be interpreted as
        interpolated strings.

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Triggers Use Interpolated Strings")

    @property
    def left_option_key_changeable(self) -> typing.Optional[bool]:
        """
        Returns whether apps should be able to change the left option key to
        send esc+.

        The values gives whether it should be allowed.

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Left Option Key Changeable")

    @property
    def right_option_key_changeable(self) -> typing.Optional[bool]:
        """
        Returns whether apps should be able to change the right option key to
        send esc+.

        The values gives whether it should be allowed.

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Right Option Key Changeable")

    @property
    def open_password_manager_automatically(self) -> typing.Optional[bool]:
        """
        Returns if the password manager should open automatically.

        The values gives whether it should open automatically.

        :returns: A typing.Optional[bool]
        """
        return self._get_optional_bool("Open Password Manager Automatically")


class PartialProfile(Profile):
    """
    Represents a profile that has only a subset of fields available for
    reading.
    """
    # pylint: disable=dangerous-default-value
    @staticmethod
    async def async_query(
            connection: iterm2.connection.Connection,
            guids: typing.Optional[typing.List[str]] = None,
            properties: typing.List[str] = [
                "Guid", "Name"]) -> typing.List['PartialProfile']:
        """
        Fetches a list of profiles by guid, populating the requested
        properties.

        :param connection: The connection to send the query to.
        :param properties: Lists the properties to fetch. Pass None for all. If
            you wish to fetch the full profile later, you must ensure the
            'Guid' property is fetched.
        :param guids: Lists GUIDs to list. Pass None for all profiles.

        :returns: A list of :class:`PartialProfile` objects with only the
            specified properties set.

        .. seealso::
            * Example ":ref:`theme_example`"
            * Example ":ref:`darknight_example`"
        """
        response = await iterm2.rpc.async_list_profiles(
            connection, guids, properties)
        profiles = []
        for response_profile in response.list_profiles_response.profiles:
            profile = PartialProfile(
                None, connection, response_profile.properties)
            profiles.append(profile)
        return profiles

    # Disable this because it's a public API and I'm stuck with it.
    # pylint: disable=arguments-differ
    @staticmethod
    async def async_get_default(
            connection: iterm2.connection.Connection,
            properties: typing.List[str] = [
                "Guid", "Name"]) -> 'PartialProfile':
        """Returns the default profile."""
        iterm2.capabilities.check_supports_get_default_profile(connection)
        result = await iterm2.rpc.async_get_default_profile(connection)
        guid = (result.preferences_response.results[0].
                get_default_profile_result.guid)
        profiles = await PartialProfile.async_query(
            connection, [guid], properties)
        return profiles[0]
    # pylint: enable=dangerous-default-value

    async def async_get_full_profile(self) -> Profile:
        """Requests a full profile and returns it.

        Raises BadGUIDException if the Guid is not set or does not match a
        profile.

        :returns: A :class:`Profile`.

        .. seealso:: Example ":ref:`theme_example`"
        """
        if not self.guid:
            raise BadGUIDException()
        response = await iterm2.rpc.async_list_profiles(
            self.connection, [self.guid], None)
        if len(response.list_profiles_response.profiles) != 1:
            raise BadGUIDException()
        return Profile(
            None,
            self.connection,
            response.list_profiles_response.profiles[0].properties)

    async def async_make_default(self):
        """Makes this profile the default profile."""
        await iterm2.rpc.async_set_default_profile(self.connection, self.guid)

