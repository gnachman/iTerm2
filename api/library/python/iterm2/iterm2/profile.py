"""
Provides classes for representing, querying, and modifying iTerm2 profiles.
"""

from __future__ import annotations

import asyncio
import enum
import json
from typing import TYPE_CHECKING, Any

from .capabilities import check_supports_get_default_profile
from .color import Color
from .rpc import (
    async_get_default_profile,
    async_list_profiles,
    async_set_default_profile,
    async_set_profile_property,
)

if TYPE_CHECKING:
    from collections.abc import Coroutine, Iterable, Mapping

    from .api_pb2 import ProfileProperty
    from .colorpresets import ColorPreset
    from .connection import Connection


# pylint: disable=too-many-public-methods
# pylint: disable=too-many-lines
# pylint: disable=line-too-long
class BackgroundImageMode(enum.Enum):
    """Describes how the background image should be accommodated to fit the window."""

    STRETCH = 0  #: Stretch to fit
    TILE = 1  #: Full size, undistorted, and tessellated if needed.
    ASPECT_FILL = 2  #: Scale to fill the space, cropping if needed. Does not distort.
    ASPECT_FIT = 3  #: Scale to fit the space, adding letterboxes or pillarboxes if needed. Does not distort.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class BadGUIDException(Exception):
    """Raised when a profile does not have a GUID or the GUID is unknown."""


class CursorType(enum.Enum):
    """Describes the type of the cursor."""

    CURSOR_TYPE_UNDERLINE = 0  #: Underline cursor
    CURSOR_TYPE_VERTICAL = 1  #: Vertical bar cursor
    CURSOR_TYPE_BOX = 2  #: Box cursor

    def toJSON(self) -> str:
        return json.dumps(self.value)


class ThinStrokes(enum.Enum):
    """When thin strokes should be used."""

    THIN_STROKES_SETTING_NEVER = 0  #: NEver
    #: When the background is dark and the display is a retina display.
    THIN_STROKES_SETTING_RETINA_DARK_BACKGROUNDS_ONLY = 1
    THIN_STROKES_SETTING_DARK_BACKGROUNDS_ONLY = 2  #: When the background is dark.
    THIN_STROKES_SETTING_ALWAYS = 3  #: Always.
    THIN_STROKES_SETTING_RETINA_ONLY = 4  #: When the display is a retina display.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class UnicodeNormalization(enum.Enum):
    """How to perform Unicode normalization."""

    UNICODE_NORMALIZATION_NONE = 0  #: Do not modify input
    UNICODE_NORMALIZATION_NFC = 1  #: Normalization form C
    UNICODE_NORMALIZATION_NFD = 2  #: Normalization form D
    UNICODE_NORMALIZATION_HFSPLUS = 3  #: Apple's HFS+ normalization form

    def toJSON(self) -> str:
        return json.dumps(self.value)


class CharacterEncoding(enum.Enum):
    """String encodings."""

    CHARACTER_ENCODING_UTF_8 = 4

    def toJSON(self) -> str:
        return json.dumps(self.value)


class OptionKeySends(enum.Enum):
    """How should the option key behave?"""

    OPTION_KEY_NORMAL = 0  #: Standard behavior
    OPTION_KEY_META = 1  #: Acts like Meta. Not recommended.
    OPTION_KEY_ESC = 2  #: Adds ESC prefix.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class InitialWorkingDirectory(enum.Enum):
    """How should the initial working directory of a session be set?"""

    INITIAL_WORKING_DIRECTORY_CUSTOM = "Yes"  #: Custom directory, specified elsewhere
    INITIAL_WORKING_DIRECTORY_HOME = "No"  #: Use default of home directory
    #: Reuse the "current" directory, or home if there is no current.
    INITIAL_WORKING_DIRECTORY_RECYCLE = "Recycle"
    INITIAL_WORKING_DIRECTORY_ADVANCED = "Advanced"  #: Use advanced settings, which specify more granular behavior depending on whether the new session is a new window, tab, or split pane.

    def toJSON(self) -> str:
        return json.dumps(self.value)


# pylint: enable=line-too-long


class IconMode(enum.Enum):
    """How should session icons be selected?"""

    NONE = 0
    AUTOMATIC = 1
    CUSTOM = 2

    def toJSON(self) -> str:
        return json.dumps(self.value)


class TitleComponents(enum.Enum):
    """Which title components should be present?"""

    SESSION_NAME = 1 << 0
    JOB = 1 << 1
    WORKING_DIRECTORY = 1 << 2
    TTY = 1 << 3
    CUSTOM = 1 << 4  #: Mutually exclusive with all other options.
    PROFILE_NAME = 1 << 5
    PROFILE_AND_SESSION_NAME = 1 << 6
    USER = 1 << 7
    HOST = 1 << 8
    COMMAND_LINE = 1 << 9
    SIZE = 1 << 10

    def toJSON(self) -> str:
        return json.dumps(self.value)


class BackgroundImageSourceMode(enum.Enum):
    """Where the background image comes from."""

    SINGLE_IMAGE = 0  #: Use the image at the background image location.
    FOLDER_ROTATION = 1  #: Rotate through the images in a folder.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class CursorBlinkFadeCurve(enum.Enum):
    """The easing curve for a smoothly blinking cursor's fade."""

    LINEAR = 0  #: Constant speed.
    EASE_IN = 1  #: Slow start, fast finish.
    EASE_OUT = 2  #: Fast start, slow finish.
    EASE_IN_OUT = 3  #: Slow start and finish.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class WindowType(enum.Enum):
    """The style of window a profile opens."""

    NORMAL = 0  #: A regular window. May become compact depending on the theme.
    TRADITIONAL_FULL_SCREEN = 1  #: Non-native full screen.
    TOP_PERCENTAGE = (
        2  #: Attached to the top of the screen, sized as a percentage of the screen.
    )
    NATIVE_FULL_SCREEN = 4  #: Native full screen.
    BOTTOM_PERCENTAGE = (
        5  #: Attached to the bottom of the screen, sized as a percentage of the screen.
    )
    LEFT_PERCENTAGE = (
        6  #: Attached to the left of the screen, sized as a percentage of the screen.
    )
    RIGHT_PERCENTAGE = (
        7  #: Attached to the right of the screen, sized as a percentage of the screen.
    )
    BOTTOM_CELLS = 8  #: Attached to the bottom of the screen, sized in cells.
    TOP_CELLS = 9  #: Attached to the top of the screen, sized in cells.
    LEFT_CELLS = 10  #: Attached to the left of the screen, sized in cells.
    RIGHT_CELLS = 11  #: Attached to the right of the screen, sized in cells.
    NO_TITLE_BAR = 12  #: A window with no title bar.
    COMPACT = 13  #: A compact window. May become normal depending on the theme.
    ACCESSORY = 14  #: An accessory window.
    MAXIMIZED = 15  #: A maximized window.
    COMPACT_MAXIMIZED = 16  #: A maximized compact window.
    CENTERED = 17  #: A window centered on the screen.
    COMPACT_CENTERED = 18  #: A compact window centered on the screen.
    CENTERED_NO_TITLE_BAR = 19  #: A window with no title bar centered on the screen.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class LocaleVariablesMode(enum.Enum):
    """How the locale environment variables are set."""

    DO_NOT_SET = 0  #: Do not set locale variables.
    SET_AUTOMATICALLY = 1  #: Set them automatically from the system locale.
    CUSTOM = 2  #: Use the profile's custom locale.
    MINIMAL = (
        3  #: Use the POSIX locale, setting only LC_CTYPE to the character encoding.
    )

    def toJSON(self) -> str:
        return json.dumps(self.value)


class LoggingStyle(enum.Enum):
    """The format of automatic session logs."""

    RAW = 0  #: Raw output, including control sequences.
    PLAIN_TEXT = 1  #: Plain text.
    HTML = 2  #: HTML, preserving colors and styles.
    ASCIICAST = 3  #: asciinema's asciicast format.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class ModifierKeyBehavior(enum.Enum):
    """How a modifier key is reported to terminal apps."""

    REGULAR = 0  #: Report it as itself.
    HYPER = 1  #: Report it as Hyper.
    META = 2  #: Report it as Meta.
    SUPER = 3  #: Report it as Super.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class HotkeyWindowDockClickAction(enum.Enum):
    """Whether clicking iTerm2's Dock icon shows a profile's hotkey window."""

    DO_NOT_SHOW = 0  #: Never show it.
    ALWAYS_SHOW = 1  #: Always show it.
    SHOW_IF_NO_OTHER_WINDOWS_OPEN = 2  #: Show it only if no other windows are open.

    def toJSON(self) -> str:
        return json.dumps(self.value)


class HotkeyModifierActivation(enum.Enum):
    """The modifier key to double-tap to toggle a hotkey window."""

    CONTROL = 0  #: Control
    SHIFT = 1  #: Shift
    OPTION = 2  #: Option
    COMMAND = 3  #: Command

    def toJSON(self) -> str:
        return json.dumps(self.value)


class TimestampsStyle(enum.Enum):
    """How timestamps are drawn when they are visible."""

    OVERLAP = 1  #: Drawn over the right side of the terminal.
    HOVER = 2  #: Shown when the pointer hovers over a line.
    ADJACENT = 3  #: Drawn beside the terminal, without covering it.

    def toJSON(self) -> str:
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

    def __init__(self, values: Mapping[str, str | None] | None = None) -> None:
        if not values:
            values = {}
        self.__values: dict[str, str] = {}
        for key, value in values.items():
            self.__values[key] = json.dumps(value)

    @property
    def values(self) -> dict[str, str]:
        """Returns the internal values dict."""
        return self.__values

    def _simple_set(self, key: str, value: Any):
        """value is a json type"""
        if value is None:
            self.__values[key] = "null"
        else:
            if hasattr(value, "toJSON"):
                self.__values[key] = value.toJSON()
            else:
                self.__values[key] = json.dumps(value)

    def _color_set(self, key: str, value: Color | None):
        if value is None:
            self.__values[key] = "null"
        else:
            self.__values[key] = json.dumps(value.get_dict())

    def set_title_components(self, value: Iterable[TitleComponents]) -> None:
        """
        Sets which components are visible in the session's title, or selects a
        custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.
        """
        bitmask = 0
        for component in value:
            bitmask += component.value
        return self._simple_set("Title Components", bitmask)

    def set_title_function(self, display_name: str, identifier: str) -> None:
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

    def set_use_separate_colors_for_light_and_dark_mode(self, value: bool) -> None:
        """
        Sets whether to use separate colors for light and dark mode.

        When this is enabled, use [set_]xxx_color_light and
        set_[xxx_]color_dark instead of [set_]xxx_color.

        :param value: Whether to use separate colors for light and dark mode.
        """
        return self._simple_set("Use Separate Colors for Light and Dark Mode", value)

    def set_foreground_color(self, value: Color) -> None:
        """
        Sets the foreground color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Foreground Color", value)

    def set_foreground_color_light(self, value: Color) -> None:
        """
        Sets the foreground color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Foreground Color (Light)", value)

    def set_foreground_color_dark(self, value: Color) -> None:
        """
        Sets the foreground color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Foreground Color (Dark)", value)

    def set_background_color(self, value: Color) -> None:
        """
        Sets the background color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Background Color", value)

    def set_background_color_light(self, value: Color) -> None:
        """
        Sets the background color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Background Color (Light)", value)

    def set_background_color_dark(self, value: Color) -> None:
        """
        Sets the background color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Background Color (Dark)", value)

    def set_bold_color(self, value: Color) -> None:
        """
        Sets the bold text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Bold Color", value)

    def set_bold_color_light(self, value: Color) -> None:
        """
        Sets the bold text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Bold Color (Light)", value)

    def set_bold_color_dark(self, value: Color) -> None:
        """
        Sets the bold text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Bold Color (Dark)", value)

    def set_use_bright_bold(self, value: bool) -> None:
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

    def set_use_bright_bold_light(self, value: bool) -> None:
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

    def set_use_bright_bold_dark(self, value: bool) -> None:
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

    def set_use_bold_color(self, value: bool) -> None:
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This is used only when separate light/dark
        mode colors are not enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        set_use_bright_bold().

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold", value)

    def set_use_bold_color_light(self, value: bool) -> None:
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        set_use_bright_bold().

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold (Light)", value)

    def set_use_bold_color_dark(self, value: bool) -> None:
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        set_use_bright_bold().

        :param value: A bool
        """
        return self._simple_set("Use Bright Bold (Dark)", value)

    def set_brighten_bold_text(self, value: bool) -> None:
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This is used only when separate light/dark
        mode colors are not enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :param value: A bool
        """
        return self._simple_set("Brighten Bold Text", value)

    def set_brighten_bold_text_light(self, value: bool) -> None:
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :param value: A bool
        """
        return self._simple_set("Brighten Bold Text (Light)", value)

    def set_brighten_bold_text_dark(self, value: bool) -> None:
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :param value: A bool
        """
        return self._simple_set("Brighten Bold Text (Dark)", value)

    def set_link_color(self, value: Color) -> None:
        """
        Sets the link color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Link Color", value)

    def set_link_color_light(self, value: Color) -> None:
        """
        Sets the link color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Link Color (Light)", value)

    def set_link_color_dark(self, value: Color) -> None:
        """
        Sets the link color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Link Color (Dark)", value)

    def set_selection_color(self, value: Color) -> None:
        """
        Sets the selection background color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selection Color", value)

    def set_selection_color_light(self, value: Color) -> None:
        """
        Sets the selection background color. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selection Color (Light)", value)

    def set_selection_color_dark(self, value: Color) -> None:
        """
        Sets the selection background color. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selection Color (Dark)", value)

    def set_selected_text_color(self, value: Color) -> None:
        """
        Sets the selection text color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selected Text Color", value)

    def set_selected_text_color_light(self, value: Color) -> None:
        """
        Sets the selection text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selected Text Color (Light)", value)

    def set_selected_text_color_dark(self, value: Color) -> None:
        """
        Sets the selection text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Selected Text Color (Dark)", value)

    def set_cursor_color(self, value: Color) -> None:
        """
        Sets the cursor color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Color", value)

    def set_cursor_color_light(self, value: Color) -> None:
        """
        Sets the cursor color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Color (Light)", value)

    def set_cursor_color_dark(self, value: Color) -> None:
        """
        Sets the cursor color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Color (Dark)", value)

    def set_cursor_text_color(self, value: Color) -> None:
        """
        Sets the cursor text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Text Color", value)

    def set_cursor_text_color_light(self, value: Color) -> None:
        """
        Sets the cursor text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Text Color (Light)", value)

    def set_cursor_text_color_dark(self, value: Color) -> None:
        """
        Sets the cursor text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Text Color (Dark)", value)

    def set_ansi_0_color(self, value: Color) -> None:
        """
        Sets the ANSI 0 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 0 Color", value)

    def set_ansi_0_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 0 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 0 Color (Light)", value)

    def set_ansi_0_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 0 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 0 Color (Dark)", value)

    def set_ansi_1_color(self, value: Color) -> None:
        """
        Sets the ANSI 1 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 1 Color", value)

    def set_ansi_1_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 1 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 1 Color (Light)", value)

    def set_ansi_1_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 1 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 1 Color (Dark)", value)

    def set_ansi_2_color(self, value: Color) -> None:
        """
        Sets the ANSI 2 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 2 Color", value)

    def set_ansi_2_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 2 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 2 Color (Light)", value)

    def set_ansi_2_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 2 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 2 Color (Dark)", value)

    def set_ansi_3_color(self, value: Color) -> None:
        """
        Sets the ANSI 3 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 3 Color", value)

    def set_ansi_3_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 3 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 3 Color (Light)", value)

    def set_ansi_3_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 3 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 3 Color (Dark)", value)

    def set_ansi_4_color(self, value: Color) -> None:
        """
        Sets the ANSI 4 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 4 Color", value)

    def set_ansi_4_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 4 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 4 Color (Light)", value)

    def set_ansi_4_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 4 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 4 Color (Dark)", value)

    def set_ansi_5_color(self, value: Color) -> None:
        """
        Sets the ANSI 5 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 5 Color", value)

    def set_ansi_5_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 5 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 5 Color (Light)", value)

    def set_ansi_5_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 5 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 5 Color (Dark)", value)

    def set_ansi_6_color(self, value: Color) -> None:
        """
        Sets the ANSI 6 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 6 Color", value)

    def set_ansi_6_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 6 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 6 Color (Light)", value)

    def set_ansi_6_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 6 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 6 Color (Dark)", value)

    def set_ansi_7_color(self, value: Color) -> None:
        """
        Sets the ANSI 7 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 7 Color", value)

    def set_ansi_7_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 7 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 7 Color (Light)", value)

    def set_ansi_7_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 7 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 7 Color (Dark)", value)

    def set_ansi_8_color(self, value: Color) -> None:
        """
        Sets the ANSI 8 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 8 Color", value)

    def set_ansi_8_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 8 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 8 Color (Light)", value)

    def set_ansi_8_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 8 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 8 Color (Dark)", value)

    def set_ansi_9_color(self, value: Color) -> None:
        """
        Sets the ANSI 9 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 9 Color", value)

    def set_ansi_9_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 9 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 9 Color (Light)", value)

    def set_ansi_9_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 9 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 9 Color (Dark)", value)

    def set_ansi_10_color(self, value: Color) -> None:
        """
        Sets the ANSI 10 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 10 Color", value)

    def set_ansi_10_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 10 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 10 Color (Light)", value)

    def set_ansi_10_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 10 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 10 Color (Dark)", value)

    def set_ansi_11_color(self, value: Color) -> None:
        """
        Sets the ANSI 11 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 11 Color", value)

    def set_ansi_11_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 11 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 11 Color (Light)", value)

    def set_ansi_11_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 11 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 11 Color (Dark)", value)

    def set_ansi_12_color(self, value: Color) -> None:
        """
        Sets the ANSI 12 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 12 Color", value)

    def set_ansi_12_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 12 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 12 Color (Light)", value)

    def set_ansi_12_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 12 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 12 Color (Dark)", value)

    def set_ansi_13_color(self, value: Color) -> None:
        """
        Sets the ANSI 13 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 13 Color", value)

    def set_ansi_13_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 13 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 13 Color (Light)", value)

    def set_ansi_13_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 13 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 13 Color (Dark)", value)

    def set_ansi_14_color(self, value: Color) -> None:
        """
        Sets the ANSI 14 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 14 Color", value)

    def set_ansi_14_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 14 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 14 Color (Light)", value)

    def set_ansi_14_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 14 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 14 Color (Dark)", value)

    def set_ansi_15_color(self, value: Color) -> None:
        """
        Sets the ANSI 15 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 15 Color", value)

    def set_ansi_15_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 15 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 15 Color (Light)", value)

    def set_ansi_15_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 15 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Ansi 15 Color (Dark)", value)

    def set_smart_cursor_color(self, value: bool) -> None:
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This is used only when separate light/dark mode colors are not
        enabled.

        :param value: A bool
        """
        return self._simple_set("Smart Cursor Color", value)

    def set_smart_cursor_color_light(self, value: bool) -> None:
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Smart Cursor Color (Light)", value)

    def set_smart_cursor_color_dark(self, value: bool) -> None:
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Smart Cursor Color (Dark)", value)

    def set_minimum_contrast(self, value: float) -> None:
        """
        Sets the minimum contrast, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return self._simple_set("Minimum Contrast", value)

    def set_minimum_contrast_light(self, value: float) -> None:
        """
        Sets the minimum contrast, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Minimum Contrast (Light)", value)

    def set_minimum_contrast_dark(self, value: float) -> None:
        """
        Sets the minimum contrast, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Minimum Contrast (Dark)", value)

    def set_tab_color(self, value: Color) -> None:
        """
        Sets the tab color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Tab Color", value)

    def set_tab_color_light(self, value: Color) -> None:
        """
        Sets the tab color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Tab Color (Light)", value)

    def set_tab_color_dark(self, value: Color) -> None:
        """
        Sets the tab color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Tab Color (Dark)", value)

    def set_use_tab_color(self, value: bool) -> None:
        """
        Sets whether the tab color should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Tab Color", value)

    def set_use_tab_color_light(self, value: bool) -> None:
        """
        Sets whether the tab color should be used. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Tab Color (Light)", value)

    def set_use_tab_color_dark(self, value: bool) -> None:
        """
        Sets whether the tab color should be used. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Tab Color (Dark)", value)

    def set_underline_color(self, value: Color | None) -> None:
        """
        Sets the underline color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color` or `None`
        """
        return self._color_set("Underline Color", value)

    def set_underline_color_light(self, value: Color | None) -> None:
        """
        Sets the underline color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color` or `None`
        """
        return self._color_set("Underline Color (Light)", value)

    def set_underline_color_dark(self, value: Color | None) -> None:
        """
        Sets the underline color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color` or `None`
        """
        return self._color_set("Underline Color (Dark)", value)

    def set_use_underline_color(self, value: bool) -> None:
        """
        Sets whether to use the specified underline color. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Underline Color", value)

    def set_use_underline_color_light(self, value: bool) -> None:
        """
        Sets whether to use the specified underline color. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Underline Color (Light)", value)

    def set_use_underline_color_dark(self, value: bool) -> None:
        """
        Sets whether to use the specified underline color. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Underline Color (Dark)", value)

    def set_cursor_boost(self, value: float) -> None:
        """
        Sets the cursor boost level, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return self._simple_set("Cursor Boost", value)

    def set_cursor_boost_light(self, value: float) -> None:
        """
        Sets the cursor boost level, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Cursor Boost (Light)", value)

    def set_cursor_boost_dark(self, value: float) -> None:
        """
        Sets the cursor boost level, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return self._simple_set("Cursor Boost (Dark)", value)

    def set_use_cursor_guide(self, value: bool) -> None:
        """
        Sets whether the cursor guide should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Cursor Guide", value)

    def set_use_cursor_guide_light(self, value: bool) -> None:
        """
        Sets whether the cursor guide should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Cursor Guide (Light)", value)

    def set_use_cursor_guide_dark(self, value: bool) -> None:
        """
        Sets whether the cursor guide should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Cursor Guide (Dark)", value)

    def set_cursor_guide_color(self, value: Color) -> None:
        """
        Sets the cursor guide color. The alpha value is respected. This is used
        only when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Guide Color", value)

    def set_cursor_guide_color_light(self, value: Color) -> None:
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Guide Color (Light)", value)

    def set_cursor_guide_color_dark(self, value: Color) -> None:
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Cursor Guide Color (Dark)", value)

    def set_badge_color(self, value: Color) -> None:
        """
        Sets the badge color. The alpha value is respected. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Badge Color", value)

    def set_badge_color_light(self, value: Color) -> None:
        """
        Sets the badge color. The alpha value is respected. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Badge Color (Light)", value)

    def set_badge_color_dark(self, value: Color) -> None:
        """
        Sets the badge color. The alpha value is respected. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Badge Color (Dark)", value)

    def set_match_color(self, value: Color) -> None:
        """
        Sets the highlight color for search matches. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Match Background Color", value)

    def set_match_color_light(self, value: Color) -> None:
        """
        Sets the highlight color for search matches. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Match Background Color (Light)", value)

    def set_match_color_dark(self, value: Color) -> None:
        """
        Sets the highlight color for search matches. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("Match Background Color (Dark)", value)

    def set_ime_cursor_color(self, value: Color) -> None:
        """
        Sets the cursor color while composing text with an input method. This
        is used only when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("IME Cursor Color", value)

    def set_ime_cursor_color_light(self, value: Color) -> None:
        """
        Sets the cursor color while composing text with an input method. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("IME Cursor Color (Light)", value)

    def set_ime_cursor_color_dark(self, value: Color) -> None:
        """
        Sets the cursor color while composing text with an input method. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return self._color_set("IME Cursor Color (Dark)", value)

    def set_use_selected_text_color(self, value: bool) -> None:
        """
        Sets whether selected text is drawn in the selected text color. This is
        used only when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Selected Text Color", value)

    def set_use_selected_text_color_light(self, value: bool) -> None:
        """
        Sets whether selected text is drawn in the selected text color. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A bool
        """
        return self._simple_set("Use Selected Text Color (Light)", value)

    def set_use_selected_text_color_dark(self, value: bool) -> None:
        """
        Sets whether selected text is drawn in the selected text color. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A bool
        """
        return self._simple_set("Use Selected Text Color (Dark)", value)

    def set_active_pane_border_color(self, value: Color) -> None:
        """
        Sets the color of the border around the active pane. This is used only
        when separate light/dark mode colors are not enabled.

        This is used only when use_active_pane_border is True.

        :param value: A :class:`Color`
        """
        return self._color_set("Active Pane Border Color", value)

    def set_active_pane_border_color_light(self, value: Color) -> None:
        """
        Sets the color of the border around the active pane. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        This is used only when use_active_pane_border is True.

        :param value: A :class:`Color`
        """
        return self._color_set("Active Pane Border Color (Light)", value)

    def set_active_pane_border_color_dark(self, value: Color) -> None:
        """
        Sets the color of the border around the active pane. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        This is used only when use_active_pane_border is True.

        :param value: A :class:`Color`
        """
        return self._color_set("Active Pane Border Color (Dark)", value)

    def set_use_active_pane_border(self, value: bool) -> None:
        """
        Sets whether to draw a border around the active pane. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("Use Active Pane Border", value)

    def set_use_active_pane_border_light(self, value: bool) -> None:
        """
        Sets whether to draw a border around the active pane. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Active Pane Border (Light)", value)

    def set_use_active_pane_border_dark(self, value: bool) -> None:
        """
        Sets whether to draw a border around the active pane. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Use Active Pane Border (Dark)", value)

    def set_faint_text_alpha(self, value: float) -> None:
        """
        Sets the opacity of faint text. This is used only when separate
        light/dark mode colors are not enabled.

        The value is between 0 and 1.

        :param value: A float
        """
        return self._simple_set("Faint Text Alpha", value)

    def set_faint_text_alpha_light(self, value: float) -> None:
        """
        Sets the opacity of faint text. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        The value is between 0 and 1.

        :param value: A float
        """
        return self._simple_set("Faint Text Alpha (Light)", value)

    def set_faint_text_alpha_dark(self, value: float) -> None:
        """
        Sets the opacity of faint text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        The value is between 0 and 1.

        :param value: A float
        """
        return self._simple_set("Faint Text Alpha (Dark)", value)

    def set_harmonize_256_colors(self, value: bool) -> None:
        """
        Sets whether the 256-color palette is adjusted to match the ANSI
        colors. This is used only when separate light/dark mode colors are not
        enabled.

        :param value: A bool
        """
        return self._simple_set("Harmonize 256 Colors", value)

    def set_harmonize_256_colors_light(self, value: bool) -> None:
        """
        Sets whether the 256-color palette is adjusted to match the ANSI
        colors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Harmonize 256 Colors (Light)", value)

    def set_harmonize_256_colors_dark(self, value: bool) -> None:
        """
        Sets whether the 256-color palette is adjusted to match the ANSI
        colors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("Harmonize 256 Colors (Dark)", value)

    def set_hdr_cursor(self, value: bool) -> None:
        """
        Sets whether the cursor is drawn brighter than white on HDR displays.
        This is used only when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return self._simple_set("HDR Cursor", value)

    def set_hdr_cursor_light(self, value: bool) -> None:
        """
        Sets whether the cursor is drawn brighter than white on HDR displays.
        This affects the light-mode variant when separate light/dark mode
        colors are enabled.

        :param value: A bool
        """
        return self._simple_set("HDR Cursor (Light)", value)

    def set_hdr_cursor_dark(self, value: bool) -> None:
        """
        Sets whether the cursor is drawn brighter than white on HDR displays.
        This affects the dark-mode variant when separate light/dark mode colors
        are enabled.

        :param value: A bool
        """
        return self._simple_set("HDR Cursor (Dark)", value)

    def set_hdr_cursor_brightness(self, value: float) -> None:
        """
        Sets the brightness of the HDR cursor. This is used only when separate
        light/dark mode colors are not enabled.

        The value is a multiple of reference white, at most 16.

        :param value: A float
        """
        return self._simple_set("HDR Cursor Brightness", value)

    def set_hdr_cursor_brightness_light(self, value: float) -> None:
        """
        Sets the brightness of the HDR cursor. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, at most 16.

        :param value: A float
        """
        return self._simple_set("HDR Cursor Brightness (Light)", value)

    def set_hdr_cursor_brightness_dark(self, value: float) -> None:
        """
        Sets the brightness of the HDR cursor. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, at most 16.

        :param value: A float
        """
        return self._simple_set("HDR Cursor Brightness (Dark)", value)

    def set_hdr_text(self, value: bool) -> None:
        """
        Sets whether the focused pane's text is drawn brighter than white on
        HDR displays. This is used only when separate light/dark mode colors
        are not enabled.

        :param value: A bool
        """
        return self._simple_set("HDR Text", value)

    def set_hdr_text_light(self, value: bool) -> None:
        """
        Sets whether the focused pane's text is drawn brighter than white on
        HDR displays. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("HDR Text (Light)", value)

    def set_hdr_text_dark(self, value: bool) -> None:
        """
        Sets whether the focused pane's text is drawn brighter than white on
        HDR displays. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A bool
        """
        return self._simple_set("HDR Text (Dark)", value)

    def set_hdr_text_brightness(self, value: float) -> None:
        """
        Sets the brightness of HDR text. This is used only when separate
        light/dark mode colors are not enabled.

        The value is a multiple of reference white, from 1.5 to 16.

        :param value: A float
        """
        return self._simple_set("HDR Text Brightness", value)

    def set_hdr_text_brightness_light(self, value: float) -> None:
        """
        Sets the brightness of HDR text. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, from 1.5 to 16.

        :param value: A float
        """
        return self._simple_set("HDR Text Brightness (Light)", value)

    def set_hdr_text_brightness_dark(self, value: float) -> None:
        """
        Sets the brightness of HDR text. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, from 1.5 to 16.

        :param value: A float
        """
        return self._simple_set("HDR Text Brightness (Dark)", value)

    def set_name(self, value: str) -> None:
        """
        Sets the name.

        :param value: A str
        """
        return self._simple_set("Name", value)

    def set_badge_text(self, value: str) -> None:
        """
        Sets the badge text.

        :param value: A str
        """
        return self._simple_set("Badge Text", value)

    def set_subtitle(self, value: str) -> None:
        """
        Sets the subtitle, an interpolated string.

        :param value: A str
        """
        return self._simple_set("Subtitle", value)

    def set_answerback_string(self, value: str) -> None:
        """
        Sets the answerback string.

        :param value: A str
        """
        return self._simple_set("Answerback String", value)

    def set_blinking_cursor(self, value: bool) -> None:
        """
        Sets whether the cursor blinks.

        :param value: A bool
        """
        return self._simple_set("Blinking Cursor", value)

    def set_cursor_shadow(self, value: bool) -> None:
        """
        Sets whether the vertical bar and horizontal line cursor have a shadow.

        :param value: A bool
        """
        return self._simple_set("Cursor Shadow", value)

    def set_use_bold_font(self, value: bool) -> None:
        """
        Sets whether to use the bold variant of the font for bold text.

        :param value: A bool
        """
        return self._simple_set("Use Bold Font", value)

    def set_ascii_ligatures(self, value: bool) -> None:
        """
        Sets whether ligatures should be used for ASCII text.

        :param value: A bool
        """
        return self._simple_set("ASCII Ligatures", value)

    def set_non_ascii_ligatures(self, value: bool) -> None:
        """
        Sets whether ligatures should be used for non-ASCII text.

        :param value: A bool
        """
        return self._simple_set("Non-ASCII Ligatures", value)

    def set_blink_allowed(self, value: bool) -> None:
        """
        Sets whether blinking text is allowed.

        :param value: A bool
        """
        return self._simple_set("Blink Allowed", value)

    def set_use_italic_font(self, value: bool) -> None:
        """
        Sets whether italic text is allowed.

        :param value: A bool
        """
        return self._simple_set("Use Italic Font", value)

    def set_ambiguous_double_width(self, value: bool) -> None:
        """
        Sets whether ambiguous-width text should be treated as double-width.

        :param value: A bool
        """
        return self._simple_set("Ambiguous Double Width", value)

    def set_horizontal_spacing(self, value: float) -> None:
        """
        Sets the fraction of horizontal spacing. Must be non-negative.

        :param value: A float
        """
        return self._simple_set("Horizontal Spacing", value)

    def set_vertical_spacing(self, value: float) -> None:
        """
        Sets the fraction of vertical spacing. Must be non-negative.

        :param value: A float
        """
        return self._simple_set("Vertical Spacing", value)

    def set_use_non_ascii_font(self, value: bool) -> None:
        """
        Sets whether to use a different font for non-ASCII text.

        :param value: A bool
        """
        return self._simple_set("Use Non-ASCII Font", value)

    def set_transparency(self, value: float) -> None:
        """
        Sets the level of transparency.

        The value is between 0 and 1.

        :param value: A float
        """
        return self._simple_set("Transparency", value)

    def set_blur(self, value: bool) -> None:
        """
        Sets whether background blur should be enabled.

        :param value: A bool
        """
        return self._simple_set("Blur", value)

    def set_blur_radius(self, value: float) -> None:
        """
        Sets the blur radius (how blurry). Requires blur to be enabled.

        The value is between 0 and 30.

        :param value: A float
        """
        return self._simple_set("Blur Radius", value)

    def set_background_image_mode(self, value: BackgroundImageMode) -> None:
        """
        Sets how the background image is drawn.

        :param value: A `BackgroundImageMode`
        """
        return self._simple_set("Background Image Mode", value)

    def set_blend(self, value: float) -> None:
        """
        Sets how much the default background color gets blended with the
        background image.

        The value is in 0 to 1.

        .. seealso:: Example ":ref:`blending_example`

        :param value: A float
        """
        return self._simple_set("Blend", value)

    def set_sync_title(self, value: bool) -> None:
        """
        Sets whether the profile name stays in the tab title, even if changed
        by an escape sequence.

        :param value: A bool
        """
        return self._simple_set("Sync Title", value)

    def set_use_built_in_powerline_glyphs(self, value: bool) -> None:
        """
        Sets whether powerline glyphs should be drawn by iTerm2 or left to the
        font.

        :param value: A bool
        """
        return self._simple_set("Draw Powerline Glyphs", value)

    def set_disable_window_resizing(self, value: bool) -> None:
        """
        Sets whether the terminal can resize the window with an escape
        sequence.

        :param value: A bool
        """
        return self._simple_set("Disable Window Resizing", value)

    def set_allow_change_cursor_blink(self, value: bool) -> None:
        """
        Sets whether the terminal can change the cursor blink setting with an
        escape sequence.

        :param value: A bool
        """
        return self._simple_set("Allow Change Cursor Blink", value)

    def set_only_the_default_bg_color_uses_transparency(self, value: bool) -> None:
        """
        Sets whether window transparency shows through non-default background
        colors.

        :param value: A bool
        """
        return self._simple_set("Only The Default BG Color Uses Transparency", value)

    def set_ascii_anti_aliased(self, value: bool) -> None:
        """
        Sets whether ASCII text is anti-aliased.

        :param value: A bool
        """
        return self._simple_set("ASCII Anti Aliased", value)

    def set_non_ascii_anti_aliased(self, value: bool) -> None:
        """
        Sets whether non-ASCII text is anti-aliased.

        :param value: A bool
        """
        return self._simple_set("Non-ASCII Anti Aliased", value)

    def set_scrollback_lines(self, value: int) -> None:
        """
        Sets the number of scrollback lines.

        Value must be at least 0.

        :param value: An int
        """
        return self._simple_set("Scrollback Lines", value)

    def set_unlimited_scrollback(self, value: bool) -> None:
        """
        Sets whether the scrollback buffer's length is unlimited.

        :param value: A bool
        """
        return self._simple_set("Unlimited Scrollback", value)

    def set_scrollback_with_status_bar(self, value: bool) -> None:
        """
        Sets whether text gets appended to scrollback when there is an app
        status bar

        :param value: A bool
        """
        return self._simple_set("Scrollback With Status Bar", value)

    def set_scrollback_in_alternate_screen(self, value: bool) -> None:
        """
        Sets whether text gets appended to scrollback in alternate screen mode.

        :param value: A bool
        """
        return self._simple_set("Scrollback in Alternate Screen", value)

    def set_mouse_reporting(self, value: bool) -> None:
        """
        Sets whether mouse reporting is allowed

        :param value: A bool
        """
        return self._simple_set("Mouse Reporting", value)

    def set_mouse_reporting_allow_mouse_wheel(self, value: bool) -> None:
        """
        Sets whether mouse reporting reports the mouse wheel's movements.

        :param value: A bool
        """
        return self._simple_set("Mouse Reporting allow mouse wheel", value)

    def set_allow_title_reporting(self, value: bool) -> None:
        """
        Sets whether the session title can be reported

        :param value: A bool
        """
        return self._simple_set("Allow Title Reporting", value)

    def set_allow_title_setting(self, value: bool) -> None:
        """
        Sets whether the session title can be changed by escape sequence

        :param value: A bool
        """
        return self._simple_set("Allow Title Setting", value)

    def set_disable_printing(self, value: bool) -> None:
        """
        Sets whether printing by escape sequence is disabled.

        :param value: A bool
        """
        return self._simple_set("Disable Printing", value)

    def set_disable_smcup_rmcup(self, value: bool) -> None:
        """
        Sets whether alternate screen mode is disabled

        :param value: A bool
        """
        return self._simple_set("Disable Smcup Rmcup", value)

    def set_silence_bell(self, value: bool) -> None:
        """
        Sets whether the bell makes noise.

        :param value: A bool
        """
        return self._simple_set("Silence Bell", value)

    def set_bm_growl(self, value: bool) -> None:
        """
        Sets whether notifications should be shown.

        :param value: A bool
        """
        return self._simple_set("BM Growl", value)

    def set_send_bell_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for the bell ringing

        :param value: A bool
        """
        return self._simple_set("Send Bell Alert", value)

    def set_send_idle_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for becoming idle

        :param value: A bool
        """
        return self._simple_set("Send Idle Alert", value)

    def set_send_new_output_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for new output

        :param value: A bool
        """
        return self._simple_set("Send New Output Alert", value)

    def set_send_session_ended_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for a session ending

        :param value: A bool
        """
        return self._simple_set("Send Session Ended Alert", value)

    def set_send_terminal_generated_alerts(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for escape-sequence
        originated notifications

        :param value: A bool
        """
        return self._simple_set("Send Terminal Generated Alerts", value)

    def set_flashing_bell(self, value: bool) -> None:
        """
        Sets whether the bell should flash the screen

        :param value: A bool
        """
        return self._simple_set("Flashing Bell", value)

    def set_visual_bell(self, value: bool) -> None:
        """
        Sets whether a bell should be shown when the bell rings

        :param value: A bool
        """
        return self._simple_set("Visual Bell", value)

    def set_close_sessions_on_end(self, value: bool) -> None:
        """
        Sets whether the session should close when it ends.

        :param value: A bool
        """
        return self._simple_set("Close Sessions On End", value)

    def set_prompt_before_closing(self, value: bool) -> None:
        """
        Sets whether the session should prompt before closing.

        :param value: A bool
        """
        return self._simple_set("Prompt Before Closing 2", value)

    def set_session_close_undo_timeout(self, value: float) -> None:
        """
        Sets the amount of time you can undo closing a session

        The value is at least 0.

        :param value: A float
        """
        return self._simple_set("Session Close Undo Timeout", value)

    def set_reduce_flicker(self, value: bool) -> None:
        """
        Sets whether the flicker fixer is on.

        :param value: A bool
        """
        return self._simple_set("Reduce Flicker", value)

    def set_send_code_when_idle(self, value: bool) -> None:
        """
        Sets whether to send a code when idle

        :param value: A bool
        """
        return self._simple_set("Send Code When Idle", value)

    def set_application_keypad_allowed(self, value: bool) -> None:
        """
        Sets whether the terminal may be placed in application keypad mode

        :param value: A bool
        """
        return self._simple_set("Application Keypad Allowed", value)

    def set_place_prompt_at_first_column(self, value: bool) -> None:
        """
        Sets whether the prompt should always begin at the first column
        (requires shell integration)

        :param value: A bool
        """
        return self._simple_set("Place Prompt at First Column", value)

    def set_show_mark_indicators(self, value: bool) -> None:
        """
        Sets whether mark indicators should be visible

        :param value: A bool
        """
        return self._simple_set("Show Mark Indicators", value)

    def set_idle_code(self, value: int) -> None:
        """
        Sets the ASCII code to send on idle

        Value is an int in 0 through 255.

        :param value: An int
        """
        return self._simple_set("Idle Code", value)

    def set_idle_period(self, value: float) -> None:
        """
        Sets how often to send a code when idle

        Value is a float at least 0

        :param value: A float
        """
        return self._simple_set("Idle Period", value)

    def set_unicode_version(self, value: bool) -> None:
        """
        Sets the unicode version for wcwidth

        :param value: A bool
        """
        return self._simple_set("Unicode Version", value)

    def set_cursor_type(self, value: CursorType) -> None:
        """
        Sets the cursor type

        :param value: A CursorType
        """
        return self._simple_set("Cursor Type", value)

    def set_thin_strokes(self, value: ThinStrokes) -> None:
        """
        Sets whether thin strokes are used.

        :param value: A ThinStrokes
        """
        return self._simple_set("Thin Strokes", value)

    def set_unicode_normalization(self, value: UnicodeNormalization) -> None:
        """
        Sets the unicode normalization form to use

        :param value: An UnicodeNormalization
        """
        return self._simple_set("Unicode Normalization", value)

    def set_character_encoding(self, value: CharacterEncoding) -> None:
        """
        Sets the character encoding

        :param value: A CharacterEncoding
        """
        return self._simple_set("Character Encoding", value)

    def set_left_option_key_sends(self, value: OptionKeySends) -> None:
        """
        Sets the behavior of the left option key.

        :param value: An OptionKeySends
        """
        return self._simple_set("Option Key Sends", value)

    def set_right_option_key_sends(self, value: OptionKeySends) -> None:
        """
        Sets the behavior of the right option key.

        :param value: An OptionKeySends
        """
        return self._simple_set("Right Option Key Sends", value)

    def set_triggers(self, value: list[dict[str, Any]]) -> None:
        """
        Sets the triggers.

        Value is an encoded trigger. Use iterm2.decode_trigger to convert from
        an encoded trigger to an object. Trigger objects can be encoded using
        the encode property.

        :param value: A list[dict[str, Any]]
        """
        return self._simple_set("Triggers", value)

    def set_smart_selection_rules(self, value: list[dict[str, Any]]) -> None:
        """
        Sets the smart selection rules.

        The value is a list of dicts of smart selection rules (currently
        undocumented)

        :param value: A list[dict[str, Any]]
        """
        return self._simple_set("Smart Selection Rules", value)

    def set_smart_selection_actions_use_interpolated_strings(self, value: bool) -> None:
        """
        Sets whether smart selection action parameters are interpolated
        strings.

        Should smart selection actions' parameters be treated as interpolated
        strings? If false, use the backward-compatibility syntax.

        :param value: A bool
        """
        return self._simple_set(
            "Smart Selection Actions Use Interpolated Strings", value
        )

    def set_semantic_history(self, value: dict[str, Any]) -> None:
        """
        Sets the semantic history prefs.

        :param value: A dict[str, Any]
        """
        return self._simple_set("Semantic History", value)

    def set_automatic_profile_switching_rules(self, value: list[str]) -> None:
        """
        Sets the automatic profile switching rules.

        Value is a list of strings, each giving a rule.

        :param value: A list[str]
        """
        return self._simple_set("Bound Hosts", value)

    def set_advanced_working_directory_window_setting(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets the advanced working directory window setting.

        Value excludes Advanced.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("AWDS Window Option", value)

    def set_advanced_working_directory_window_directory(self, value: str) -> None:
        """
        Sets the advanced working directory window directory.

        :param value: A str
        """
        return self._simple_set("AWDS Window Directory", value)

    def set_advanced_working_directory_tab_setting(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets the advanced working directory tab setting.

        Value excludes Advanced.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("AWDS Tab Option", value)

    def set_advanced_working_directory_tab_directory(self, value: str) -> None:
        """
        Sets the advanced working directory tab directory.

        :param value: A str
        """
        return self._simple_set("AWDS Tab Directory", value)

    def set_advanced_working_directory_pane_setting(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets the advanced working directory pane setting.

        Value excludes Advanced.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("AWDS Pane Option", value)

    def set_advanced_working_directory_pane_directory(self, value: str) -> None:
        """
        Sets the advanced working directory pane directory.

        :param value: A str
        """
        return self._simple_set("AWDS Pane Directory", value)

    def set_normal_font(self, value: str) -> None:
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

    def set_non_ascii_font(self, value: str) -> None:
        """
        Sets the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.
        The value is the font name and size as a string.

        :param value: A str
        """
        return self._simple_set("Non Ascii Font", value)

    def set_background_image_location(self, value: str) -> None:
        """
        Sets or clears the path to a background image.

        The value is a string with the path to the image file,
        or an empty string to clear the setting.

        :param value: A str
        """
        return self._simple_set("Background Image Location", value)

    def set_key_mappings(self, value: dict[str, Any]) -> None:
        """
        Sets the keyboard shortcuts.

        The value is a Dictionary mapping keystroke to action. You can convert
        between the values in this dictionary and a :class:`~iterm2.KeyBinding`
        using `iterm2.decode_key_binding`

        :param value: A dict[str, Any]
        """
        return self._simple_set("Keyboard Map", value)

    def set_touchbar_mappings(self, value: dict[str, Any]) -> None:
        """
        Sets the touchbar actions.

        The value is a Dictionary mapping touch bar item to action

        :param value: A dict[str, Any]
        """
        return self._simple_set("Touch Bar Map", value)

    def set_use_custom_command(self, value: str) -> None:
        """
        Sets whether to use a custom command when the session is created.

        The value is the string Yes or No

        :param value: A str
        """
        return self._simple_set("Custom Command", value)

    def set_command(self, value: str) -> None:
        """
        Sets the command to run when the session starts.

        The value is a string giving the command to run

        :param value: A str
        """
        return self._simple_set("Command", value)

    def set_initial_directory_mode(self, value: InitialWorkingDirectory) -> None:
        """
        Sets whether to use a custom (not home) initial working directory.

        :param value: An InitialWorkingDirectory
        """
        return self._simple_set("Custom Directory", value.value)

    def set_custom_directory(self, value: str) -> None:
        """
        Sets the initial working directory.

        The initial_directory_mode must be set to
        `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
        take effect.

        :param value: A str
        """
        return self._simple_set("Working Directory", value)

    def set_icon_mode(self, value: IconMode) -> None:
        """
        Sets the icon mode.

        :param value: An IconMode
        """
        return self._simple_set("Icon", value.value)

    def set_custom_icon_path(self, value: str) -> None:
        """
        Sets the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.

        :param value: A str
        """
        return self._simple_set("Custom Icon Path", value)

    def set_badge_top_margin(self, value: int) -> None:
        """
        Sets the top margin of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Top Margin", value)

    def set_badge_right_margin(self, value: int) -> None:
        """
        Sets the right margin of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Right Margin", value)

    def set_badge_max_width(self, value: int) -> None:
        """
        Sets the max width of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Max Width", value)

    def set_badge_max_height(self, value: int) -> None:
        """
        Sets the max height of the badge.

        The value is in points.

        :param value: An int
        """
        return self._simple_set("Badge Max Height", value)

    def set_badge_font(self, value: str) -> None:
        """
        Sets the font of the badge.

        The font name is a string like "Helvetica".

        :param value: A str
        """
        return self._simple_set("Badge Font", value)

    def set_use_custom_window_title(self, value: bool) -> None:
        """
        Sets whether the custom window title is used.

        Should the custom window title in the profile be used?

        :param value: A bool
        """
        return self._simple_set("Use Custom Window Title", value)

    def set_custom_window_title(self, value: str | None) -> None:
        """
        Sets the custom window title.

        This will only be used if use_custom_window_title is True.
        The value is an interpolated string.

        :param value: A str | None
        """
        return self._simple_set("Custom Window Title", value)

    def set_use_transparency_initially(self, value: bool) -> None:
        """
        Sets whether a window created with this profile respect the
        transparency setting.

        If True, use transparency; if False, force the window to
        be opaque (but it can be toggled with View > Use Transparency).

        :param value: A bool
        """
        return self._simple_set("Initial Use Transparency", value)

    def set_status_bar_enabled(self, value: bool) -> None:
        """
        Sets whether the status bar be enabled.

        If True, the status bar will be shown.

        :param value: A bool
        """
        return self._simple_set("Show Status Bar", value)

    def set_use_csi_u(self, value: bool) -> None:
        """
        Sets whether to report keystrokes with CSI u protocol.

        If True, CSI u will be enabled.

        :param value: A bool
        """
        return self._simple_set("Use libtickit protocol", value)

    def set_triggers_use_interpolated_strings(self, value: bool) -> None:
        """
        Sets whether trigger parameters should be interpreted as interpolated
        strings.

        :param value: A bool
        """
        return self._simple_set("Triggers Use Interpolated Strings", value)

    def set_left_option_key_changeable(self, value: bool) -> None:
        """
        Sets whether apps should be able to change the left option key to send
        esc+.

        The values gives whether it should be allowed.

        :param value: A bool
        """
        return self._simple_set("Left Option Key Changeable", value)

    def set_right_option_key_changeable(self, value: bool) -> None:
        """
        Sets whether apps should be able to change the right option key to send
        esc+.

        The values gives whether it should be allowed.

        :param value: A bool
        """
        return self._simple_set("Right Option Key Changeable", value)

    def set_open_password_manager_automatically(self, value: bool) -> None:
        """
        Sets if the password manager should open automatically.

        The values gives whether it should open automatically.

        :param value: A bool
        """
        return self._simple_set("Open Password Manager Automatically", value)

    def set_tags(self, value: list[str]) -> None:
        """
        Sets the tags used to organize profiles.

        Set it to an empty list to remove all tags. The getter returns None or
        an empty list when the profile has no tags.

        :param value: A list[str]
        """
        return self._simple_set("Tags", value)

    def set_shortcut(self, value: str) -> None:
        """
        Sets the keyboard shortcut that opens this profile.

        The value is a single uppercase letter or digit that opens the profile
        when pressed with Control and Command. Set it to an empty string to
        remove the shortcut. The getter returns None or an empty string when
        there is no shortcut. Give each shortcut to at most one profile.

        :param value: A str
        """
        return self._simple_set("Shortcut", value)

    def set_initial_text(self, value: str) -> None:
        """
        Sets the text to send to the session after it starts.

        The value is an interpolated string.

        :param value: A str
        """
        return self._simple_set("Initial Text", value)

    def set_run_command_in_login_shell(self, value: bool) -> None:
        """
        Sets whether a custom command runs inside the user's login shell.

        :param value: A bool
        """
        return self._simple_set("Run Command In Login Shell", value)

    def set_load_shell_integration_automatically(self, value: bool) -> None:
        """
        Sets whether shell integration is loaded automatically.

        :param value: A bool
        """
        return self._simple_set("Load Shell Integration Automatically", value)

    def set_snippets_filter(self, value: list[str]) -> None:
        """
        Sets the snippet tags available to sessions with this profile.

        An empty list makes all snippets available.

        :param value: A list[str]
        """
        return self._simple_set("Snippets Filter", value)

    def set_cursor_hidden_without_focus(self, value: bool) -> None:
        """
        Sets whether the cursor is hidden when the session does not have
        keyboard focus.

        :param value: A bool
        """
        return self._simple_set("Cursor Hidden When Unfocused", value)

    def set_animate_movement(self, value: bool) -> None:
        """
        Sets whether cursor movement is animated.

        :param value: A bool
        """
        return self._simple_set("Animate Movement", value)

    def set_animate_movement_only_in_interactive_apps(self, value: bool) -> None:
        """
        Sets whether cursor movement is animated only in interactive apps.

        This is used only when animate_movement is True.

        :param value: A bool
        """
        return self._simple_set("Animate Movement Only in Interactive Apps", value)

    def set_cursor_smooth_slide(self, value: bool) -> None:
        """
        Sets whether the cursor slides smoothly between positions.

        :param value: A bool
        """
        return self._simple_set("Cursor Smooth Slide", value)

    def set_cursor_smooth_blink(self, value: bool) -> None:
        """
        Sets whether a blinking cursor fades smoothly instead of switching on
        and off.

        :param value: A bool
        """
        return self._simple_set("Cursor Smooth Blink", value)

    def set_cursor_blink_fade_in_duration(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor takes to fade in.

        :param value: A float
        """
        return self._simple_set("Cursor Blink Fade In Duration", value)

    def set_cursor_blink_fade_out_duration(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor takes to fade
        out.

        :param value: A float
        """
        return self._simple_set("Cursor Blink Fade Out Duration", value)

    def set_cursor_blink_fade_in_curve(self, value: CursorBlinkFadeCurve) -> None:
        """
        Sets the easing curve for a smoothly blinking cursor fading in.

        :param value: A CursorBlinkFadeCurve
        """
        return self._simple_set("Cursor Blink Fade In Curve", value)

    def set_cursor_blink_fade_out_curve(self, value: CursorBlinkFadeCurve) -> None:
        """
        Sets the easing curve for a smoothly blinking cursor fading out.

        :param value: A CursorBlinkFadeCurve
        """
        return self._simple_set("Cursor Blink Fade Out Curve", value)

    def set_cursor_blink_visible_dwell(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor stays fully
        visible.

        :param value: A float
        """
        return self._simple_set("Cursor Blink Visible Dwell", value)

    def set_cursor_blink_hidden_dwell(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor stays fully
        hidden.

        :param value: A float
        """
        return self._simple_set("Cursor Blink Hidden Dwell", value)

    def set_use_theme_mark_colors(self, value: bool) -> None:
        """
        Sets whether mark indicators use colors from the ANSI palette.

        :param value: A bool
        """
        return self._simple_set("Use Theme Mark Colors", value)

    def set_background_image_source_mode(
        self, value: BackgroundImageSourceMode
    ) -> None:
        """
        Sets where the background image comes from.

        :param value: A BackgroundImageSourceMode
        """
        return self._simple_set("Background Image Source Mode", value)

    def set_background_image_folder_location(self, value: str) -> None:
        """
        Sets the folder of background images to rotate through.

        This is used only when background_image_source_mode is FOLDER_ROTATION.

        :param value: A str
        """
        return self._simple_set("Background Image Folder Location", value)

    def set_background_image_folder_interval(self, value: float) -> None:
        """
        Sets how often, in seconds, to change the background image when
        rotating through a folder.

        :param value: A float
        """
        return self._simple_set("Background Image Folder Interval", value)

    def set_window_type(self, value: WindowType) -> None:
        """
        Sets the style of window to open.

        :param value: A WindowType
        """
        return self._simple_set("Window Type", value)

    def set_columns(self, value: int) -> None:
        """
        Sets the initial number of columns.

        :param value: An int
        """
        return self._simple_set("Columns", value)

    def set_rows(self, value: int) -> None:
        """
        Sets the initial number of rows.

        :param value: An int
        """
        return self._simple_set("Rows", value)

    def set_width_percentage(self, value: float) -> None:
        """
        Sets the window's width as a percentage of the screen width.

        Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR,
        COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR,
        TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or
        RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a
        non-negative value switches the window from cell-based to
        screen-percentage sizing, even for a normal window. A negative value
        means size by columns instead. If the profile has no value, the window
        is sized by columns, except that top and bottom percentage windows span
        the full screen width. The getter still returns the default of 100 in
        that case.

        :param value: A float
        """
        return self._simple_set("Width Percentage", value)

    def set_height_percentage(self, value: float) -> None:
        """
        Sets the window's height as a percentage of the screen height.

        Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR,
        COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR,
        TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or
        RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a
        non-negative value switches the window from cell-based to
        screen-percentage sizing, even for a normal window. A negative value
        means size by rows instead. If the profile has no value, the window is
        sized by rows, except that left and right percentage windows span the
        full screen height. The getter still returns the default of 100 in that
        case.

        :param value: A float
        """
        return self._simple_set("Height Percentage", value)

    def set_screen(self, value: int) -> None:
        """
        Sets the screen on which new windows open.

        -1 means no preference, -2 means the screen with the pointer, 0 is the
        main screen, and higher numbers are other screens.

        :param value: An int
        """
        return self._simple_set("Screen", value)

    def set_space(self, value: int) -> None:
        """
        Sets the Space in which new windows open.

        0 means the current Space, -1 means all Spaces, and 1 through 9 are
        specific Spaces.

        :param value: An int
        """
        return self._simple_set("Space", value)

    def set_use_custom_tab_title(self, value: bool) -> None:
        """
        Sets whether the custom tab title is used.

        :param value: A bool
        """
        return self._simple_set("Use Custom Tab Title", value)

    def set_custom_tab_title(self, value: str) -> None:
        """
        Sets the custom tab title.

        This is used only when use_custom_tab_title is True. The value is an
        interpolated string.

        :param value: A str
        """
        return self._simple_set("Custom Tab Title", value)

    def set_hide_after_opening(self, value: bool) -> None:
        """
        Sets whether a new window is hidden right after it opens.

        :param value: A bool
        """
        return self._simple_set("Hide After Opening", value)

    def set_lock_window_size_automatically(self, value: bool) -> None:
        """
        Sets whether a new window's size is locked right after it opens.

        :param value: A bool
        """
        return self._simple_set("Lock Window Size Automatically", value)

    def set_disable_unfocused_window_resizing(self, value: bool) -> None:
        """
        Sets whether sessions without keyboard focus are prevented from
        resizing the window with an escape sequence.

        :param value: A bool
        """
        return self._simple_set("Disable Window Resizing by Unfocused Sessions", value)

    def set_prevent_tab(self, value: bool) -> None:
        """
        Sets whether this profile always opens in a new window, never in a tab.

        :param value: A bool
        """
        return self._simple_set("Prevent Opening in a Tab", value)

    def set_open_toolbelt(self, value: bool) -> None:
        """
        Sets whether new windows open with the toolbelt visible.

        :param value: A bool
        """
        return self._simple_set("Open Toolbelt", value)

    def set_show_rich_tab_content(self, value: bool) -> None:
        """
        Sets whether tabs in windows created with this profile show rich
        content.

        :param value: A bool
        """
        return self._simple_set("Show Rich Tab Content", value)

    def set_tab_content_maximum_lines(self, value: int) -> None:
        """
        Sets the most lines of rich content a tab shows.

        0 means no limit.

        :param value: An int
        """
        return self._simple_set("Tab Content Maximum Lines", value)

    def set_terminal_type(self, value: str) -> None:
        """
        Sets the terminal type reported to apps.

        The value is the TERM environment variable, such as xterm-256color.

        :param value: A str
        """
        return self._simple_set("Terminal Type", value)

    def set_locale_variables_mode(self, value: LocaleVariablesMode) -> None:
        """
        Sets how the locale environment variables are set.

        :param value: A LocaleVariablesMode
        """
        return self._simple_set("Set Local Environment Vars", value)

    def set_custom_locale(self, value: str) -> None:
        """
        Sets the custom locale.

        This is used only when locale_variables_mode is CUSTOM.

        :param value: A str
        """
        return self._simple_set("Custom Locale", value)

    def set_jobs_to_ignore(self, value: list[str]) -> None:
        """
        Sets the names of jobs that don't cause a prompt before closing.

        :param value: A list[str]
        """
        return self._simple_set("Jobs to Ignore", value)

    def set_bell_sound(self, value: str) -> None:
        """
        Sets the sound the bell plays.

        The value is the name of a sound installed in a Sounds folder, the path
        to an audio file, or an empty string for the system alert sound.

        :param value: A str
        """
        return self._simple_set("Bell Sound", value)

    def set_prevent_sleep(self, value: bool) -> None:
        """
        Sets whether the computer is kept from idle sleep while a session with
        this profile exists.

        :param value: A bool
        """
        return self._simple_set("Prevent Sleep", value)

    def set_allow_paste_bracketing(self, value: bool) -> None:
        """
        Sets whether apps may turn on bracketed paste mode.

        :param value: A bool
        """
        return self._simple_set("Allow Paste Bracketing", value)

    def set_enable_triggers_in_interactive_apps(self, value: bool) -> None:
        """
        Sets whether triggers fire in interactive apps.

        :param value: A bool
        """
        return self._simple_set("Enable Triggers in Interactive Apps", value)

    def set_tmux_newline(self, value: bool) -> None:
        """
        Sets whether pressing return in a tmux session sends a newline instead
        of a carriage return.

        :param value: A bool
        """
        return self._simple_set("Tmux Newline", value)

    def set_show_offscreen_command_line(self, value: bool) -> None:
        """
        Sets whether the command that produced the output at the top of the
        screen is shown when scrolled back.

        :param value: A bool
        """
        return self._simple_set("Show Offscreen Command line", value)

    def set_show_offscreen_command_line_for_current_command(self, value: bool) -> None:
        """
        Sets whether the offscreen command line is also shown for the command
        that is still running.

        :param value: A bool
        """
        return self._simple_set(
            "Show Offscreen Command line for Current Command", value
        )

    def set_prompt_path_click_opens_navigator(self, value: bool) -> None:
        """
        Sets whether clicking the path in a prompt opens a file navigator.

        :param value: A bool
        """
        return self._simple_set("Prompt Path Click Opens Navigator", value)

    def set_composer_top_offset(self, value: float) -> None:
        """
        Sets the composer's vertical offset from the top of the session.

        :param value: A float
        """
        return self._simple_set("Composer Top Offset", value)

    def set_default_pane_locked(self, value: bool) -> None:
        """
        Sets whether new panes are locked by default.

        :param value: A bool
        """
        return self._simple_set("Default Pane Locked", value)

    def set_buffer_input_by_default(self, value: bool) -> None:
        """
        Sets whether keyboard input is buffered by default in new sessions.

        :param value: A bool
        """
        return self._simple_set("Buffer Input by Default", value)

    def set_timestamps_visible(self, value: bool) -> None:
        """
        Sets whether timestamps are visible.

        :param value: A bool
        """
        return self._simple_set("Timestamps Visible", value)

    def set_timestamps_style(self, value: TimestampsStyle) -> None:
        """
        Sets how timestamps are drawn when visible.

        :param value: A TimestampsStyle
        """
        return self._simple_set("Timestamps Style", value)

    def set_enable_progress_bars(self, value: bool) -> None:
        """
        Sets whether progress bars reported by apps are shown.

        :param value: A bool
        """
        return self._simple_set("Enable Progress Bars", value)

    def set_progress_bar_height(self, value: float) -> None:
        """
        Sets the height of progress bars, in points.

        :param value: A float
        """
        return self._simple_set("Progress Bar Height", value)

    def set_progress_bar_color_scheme(self, value: str) -> None:
        """
        Sets the color scheme for progress bars.

        The value is one of default, rainbow, red, green, blue, yellow, purple,
        cyan, or orange.

        :param value: A str
        """
        return self._simple_set("Progress Bar Color Scheme", value)

    def set_send_alerts_to_companion(self, value: bool) -> None:
        """
        Sets whether this profile's notifications are also sent to the paired
        iTerm2 Buddy iPhone app.

        :param value: A bool
        """
        return self._simple_set("Send Alerts To Companion", value)

    def set_suppress_alerts_in_active_session(self, value: bool) -> None:
        """
        Sets whether notifications from the active session are suppressed.

        :param value: A bool
        """
        return self._simple_set("Suppress Alerts in Active Session", value)

    def set_mouse_reporting_allow_clicks_and_drags(self, value: bool) -> None:
        """
        Sets whether mouse reporting reports clicks and drags.

        :param value: A bool
        """
        return self._simple_set("Mouse Reporting allow clicks and drags", value)

    def set_restrict_mouse_reporting_to_alternate_screen_mode(
        self, value: bool
    ) -> None:
        """
        Sets whether mouse reporting is allowed only in alternate screen mode.

        :param value: A bool
        """
        return self._simple_set(
            "Restrict Mouse Reporting to Alternate Screen Mode", value
        )

    def set_allow_alternate_mouse_scroll(self, value: bool) -> None:
        """
        Sets whether scrolling in alternate screen mode sends arrow keys.

        :param value: A bool
        """
        return self._simple_set("Allow Alternate Mouse Scroll", value)

    def set_automatically_enable_alternate_mouse_scroll(self, value: bool) -> None:
        """
        Sets whether scrolling sends arrow keys automatically in alternate
        screen mode.

        :param value: A bool
        """
        return self._simple_set("Automatically Enable Alternate Mouse Scroll", value)

    def set_restrict_alternate_mouse_scroll_to_vertical(self, value: bool) -> None:
        """
        Sets whether only vertical scrolling sends arrow keys in alternate
        screen mode.

        :param value: A bool
        """
        return self._simple_set("Restrict Alternate Mouse Scroll to Vertical", value)

    def set_drag_to_scroll_in_alternate_screen_mode_disabled(self, value: bool) -> None:
        """
        Sets whether dragging a selection past the edge stops scrolling in
        alternate screen mode.

        :param value: A bool
        """
        return self._simple_set(
            "Drag to Scroll in Alternate Screen Mode Disabled", value
        )

    def set_left_control_key_behavior(self, value: ModifierKeyBehavior) -> None:
        """
        Sets how the left control key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return self._simple_set("Left Control Key", value)

    def set_right_control_key_behavior(self, value: ModifierKeyBehavior) -> None:
        """
        Sets how the right control key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return self._simple_set("Right Control Key", value)

    def set_left_command_key_behavior(self, value: ModifierKeyBehavior) -> None:
        """
        Sets how the left command key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return self._simple_set("Left Command Key", value)

    def set_right_command_key_behavior(self, value: ModifierKeyBehavior) -> None:
        """
        Sets how the right command key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return self._simple_set("Right Command Key", value)

    def set_function_key_behavior(self, value: ModifierKeyBehavior) -> None:
        """
        Sets how the fn key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return self._simple_set("Function Key", value)

    def set_treat_option_as_alt(self, value: bool) -> None:
        """
        Sets whether option is reported as alt in modifier flags.

        :param value: A bool
        """
        return self._simple_set("Treat Option as Alt", value)

    def set_allow_modify_other_keys(self, value: bool) -> None:
        """
        Sets whether apps may turn on xterm's modifyOtherKeys mode.

        :param value: A bool
        """
        return self._simple_set("Allow modifyOtherKeys", value)

    def set_movement_keys_scroll_outside_interactive_apps(self, value: bool) -> None:
        """
        Sets whether arrow and page keys scroll when not in an interactive app.

        :param value: A bool
        """
        return self._simple_set("Movement Keys Scroll Outside Interactive Apps", value)

    def set_has_hotkey(self, value: bool) -> None:
        """
        Sets whether this profile has a dedicated hotkey window.

        To assign a hotkey without a key code, also set
        hotkey_activated_by_modifier and hotkey_modifier_activation.

        :param value: A bool
        """
        return self._simple_set("Has Hotkey", value)

    def set_hotkey_activated_by_modifier(self, value: bool) -> None:
        """
        Sets whether double-tapping a modifier key toggles the hotkey window.

        :param value: A bool
        """
        return self._simple_set("HotKey Activated By Modifier", value)

    def set_hotkey_modifier_activation(self, value: HotkeyModifierActivation) -> None:
        """
        Sets which modifier key to double-tap to toggle the hotkey window.

        :param value: A HotkeyModifierActivation
        """
        return self._simple_set("HotKey Modifier Activation", value)

    def set_hotkey_auto_hides(self, value: bool) -> None:
        """
        Sets whether the hotkey window hides when it loses focus.

        :param value: A bool
        """
        return self._simple_set("HotKey Window AutoHides", value)

    def set_hotkey_reopens_on_activation(self, value: bool) -> None:
        """
        Sets whether an auto-hidden hotkey window reappears when iTerm2 is
        activated.

        :param value: A bool
        """
        return self._simple_set("HotKey Window Reopens On Activation", value)

    def set_hotkey_animates(self, value: bool) -> None:
        """
        Sets whether the hotkey window animates when it shows and hides.

        :param value: A bool
        """
        return self._simple_set("HotKey Window Animates", value)

    def set_hotkey_floats(self, value: bool) -> None:
        """
        Sets whether the hotkey window floats above other windows.

        :param value: A bool
        """
        return self._simple_set("HotKey Window Floats", value)

    def set_hotkey_dock_click_action(self, value: HotkeyWindowDockClickAction) -> None:
        """
        Sets whether clicking iTerm2's Dock icon shows the hotkey window.

        :param value: A HotkeyWindowDockClickAction
        """
        return self._simple_set("HotKey Window Dock Click Action", value)

    def set_automatically_log(self, value: bool) -> None:
        """
        Sets whether session output is logged automatically.

        :param value: A bool
        """
        return self._simple_set("Automatically Log", value)

    def set_log_directory(self, value: str) -> None:
        """
        Sets the directory for automatic logs.

        :param value: A str
        """
        return self._simple_set("Log Directory", value)

    def set_log_filename_format(self, value: str) -> None:
        """
        Sets the format of automatic log file names.

        The value is an interpolated string.

        :param value: A str
        """
        return self._simple_set("Log Filename Format", value)

    def set_logging_style(self, value: LoggingStyle) -> None:
        """
        Sets the format of automatic logs.

        :param value: A LoggingStyle
        """
        return self._simple_set("Plain Text Logging", value)

    def set_archive_on_closure(self, value: bool) -> None:
        """
        Sets whether sessions are archived when they close.

        :param value: A bool
        """
        return self._simple_set("Archive On Closure", value)

    def set_archive_directory(self, value: str) -> None:
        """
        Sets the directory for archived sessions.

        :param value: A str
        """
        return self._simple_set("Archive Directory", value)

    def set_initial_url(self, value: str) -> None:
        """
        Sets the URL a web browser profile opens.

        :param value: A str
        """
        return self._simple_set("Initial URL", value)

    def set_browser_zoom(self, value: float) -> None:
        """
        Sets the zoom level of a web browser profile.

        100 means 100%.

        :param value: A float
        """
        return self._simple_set("Browser Zoom", value)

    def set_browser_dev_null(self, value: bool) -> None:
        """
        Sets whether a web browser profile uses a private data store that is
        not shared with other browser profiles.

        :param value: A bool
        """
        return self._simple_set("Dev Null Mode", value)

    def set_browser_width(self, value: float) -> None:
        """
        Sets the initial width of a web browser profile's window, in points.

        :param value: A float
        """
        return self._simple_set("Width in Points", value)

    def set_browser_height(self, value: float) -> None:
        """
        Sets the initial height of a web browser profile's window, in points.

        :param value: A float
        """
        return self._simple_set("Height in Points", value)

    def set_browser_instant_replay(self, value: bool) -> None:
        """
        Sets whether instant replay is enabled for a web browser profile.

        :param value: A bool
        """
        return self._simple_set("Instant Replay", value)


class WriteOnlyProfile:
    """
    A profile that can be modified but not read. Useful for changing many
    sessions' profiles at once without knowing what they are.
    """

    def __init__(
        self, session_id: str | None, connection: Connection, guid: str | None = None
    ) -> None:
        assert session_id != "all"
        self.connection: Connection = connection
        self.session_id: str | None = session_id
        self.__guid = guid

    async def _async_simple_set(self, key: str, value: Any):
        """
        :param value: a json type
        """
        if hasattr(value, "toJSON"):
            # Enums can't be passed to json.dumps directly.
            value = json.loads(value.toJSON())
        await async_set_profile_property(
            self.connection, self.session_id, key, value, self._guids_for_set()
        )

    async def _async_color_set(self, key: str, value: Color | None):
        if value is None:
            await async_set_profile_property(
                self.connection, self.session_id, key, "null", self._guids_for_set()
            )
        else:
            await async_set_profile_property(
                self.connection,
                self.session_id,
                key,
                value.get_dict(),
                self._guids_for_set(),
            )

    def _guids_for_set(self):
        if self.session_id is None:
            assert self.__guid is not None
            return [self.__guid]
        return self.session_id

    async def async_set_color_preset(self, preset: ColorPreset) -> None:
        """
        Sets the color preset.

        :param preset: The new value.

        .. seealso::
            * Example ":ref:`colorhost_example`"
            * Example ":ref:`random_color_example`"
            * Example ":ref:`theme_example`"
            * Example ":ref:`darknight_example`"
        """
        coros: list[Coroutine[Any, Any, Any]] = []
        for value in preset.values:
            coro = self._async_color_set(
                value.key,
                Color(
                    value.red, value.green, value.blue, value.alpha, value.color_space
                ),
            )
            coros.append(coro)
        await asyncio.gather(*coros)

    async def async_set_title_components(
        self, value: Iterable[TitleComponents]
    ) -> None:
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
        self, display_name: str, identifier: str
    ) -> None:
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
            "Title Function", [display_name, identifier]
        )

    async def async_set_use_separate_colors_for_light_and_dark_mode(
        self, value: bool
    ) -> None:
        """
        Sets whether to use separate colors for light and dark mode.

        When this is enabled, use [set_]xxx_color_light and
        set_[xxx_]color_dark instead of [set_]xxx_color.

        :param value: Whether to use separate colors for light and dark mode.
        """
        return await self._async_simple_set(
            "Use Separate Colors for Light and Dark Mode", value
        )

    async def async_set_foreground_color(self, value: Color) -> None:
        """
        Sets the foreground color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Foreground Color", value)

    async def async_set_foreground_color_light(self, value: Color) -> None:
        """
        Sets the foreground color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Foreground Color (Light)", value)

    async def async_set_foreground_color_dark(self, value: Color) -> None:
        """
        Sets the foreground color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Foreground Color (Dark)", value)

    async def async_set_background_color(self, value: Color) -> None:
        """
        Sets the background color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Background Color", value)

    async def async_set_background_color_light(self, value: Color) -> None:
        """
        Sets the background color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Background Color (Light)", value)

    async def async_set_background_color_dark(self, value: Color) -> None:
        """
        Sets the background color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Background Color (Dark)", value)

    async def async_set_bold_color(self, value: Color) -> None:
        """
        Sets the bold text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Bold Color", value)

    async def async_set_bold_color_light(self, value: Color) -> None:
        """
        Sets the bold text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Bold Color (Light)", value)

    async def async_set_bold_color_dark(self, value: Color) -> None:
        """
        Sets the bold text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Bold Color (Dark)", value)

    async def async_set_use_bright_bold(self, value: bool) -> None:
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

    async def async_set_use_bright_bold_light(self, value: bool) -> None:
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

    async def async_set_use_bright_bold_dark(self, value: bool) -> None:
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

    async def async_set_use_bold_color(self, value: bool) -> None:
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This is used only when separate light/dark
        mode colors are not enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        async_set_use_bright_bold().
        """
        return await self._async_simple_set("Use Bright Bold", value)

    async def async_set_use_bold_color_light(self, value: bool) -> None:
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        async_set_use_bright_bold().
        """
        return await self._async_simple_set("Use Bright Bold (Light)", value)

    async def async_set_use_bold_color_dark(self, value: bool) -> None:
        """
        Sets whether the profile-specified bold color is used for
        default-colored bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        async_set_use_bright_bold().
        """
        return await self._async_simple_set("Use Bright Bold (Dark)", value)

    async def async_set_brighten_bold_text(self, value: bool) -> None:
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This is used only when separate light/dark
        mode colors are not enabled.

        This is only supported in iTerm2 version 3.3.7 and later.
        """
        return await self._async_simple_set("Brighten Bold Text", value)

    async def async_set_brighten_bold_text_light(self, value: bool) -> None:
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.
        """
        return await self._async_simple_set("Brighten Bold Text (Light)", value)

    async def async_set_brighten_bold_text_dark(self, value: bool) -> None:
        """
        Sets whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.
        """
        return await self._async_simple_set("Brighten Bold Text (Dark)", value)

    async def async_set_link_color(self, value: Color) -> None:
        """
        Sets the link color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Link Color", value)

    async def async_set_link_color_light(self, value: Color) -> None:
        """
        Sets the link color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Link Color (Light)", value)

    async def async_set_link_color_dark(self, value: Color) -> None:
        """
        Sets the link color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Link Color (Dark)", value)

    async def async_set_selection_color(self, value: Color) -> None:
        """
        Sets the selection background color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selection Color", value)

    async def async_set_selection_color_light(self, value: Color) -> None:
        """
        Sets the selection background color. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selection Color (Light)", value)

    async def async_set_selection_color_dark(self, value: Color) -> None:
        """
        Sets the selection background color. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selection Color (Dark)", value)

    async def async_set_selected_text_color(self, value: Color) -> None:
        """
        Sets the selection text color. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selected Text Color", value)

    async def async_set_selected_text_color_light(self, value: Color) -> None:
        """
        Sets the selection text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selected Text Color (Light)", value)

    async def async_set_selected_text_color_dark(self, value: Color) -> None:
        """
        Sets the selection text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Selected Text Color (Dark)", value)

    async def async_set_cursor_color(self, value: Color) -> None:
        """
        Sets the cursor color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Color", value)

    async def async_set_cursor_color_light(self, value: Color) -> None:
        """
        Sets the cursor color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Color (Light)", value)

    async def async_set_cursor_color_dark(self, value: Color) -> None:
        """
        Sets the cursor color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Color (Dark)", value)

    async def async_set_cursor_text_color(self, value: Color) -> None:
        """
        Sets the cursor text color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Text Color", value)

    async def async_set_cursor_text_color_light(self, value: Color) -> None:
        """
        Sets the cursor text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Text Color (Light)", value)

    async def async_set_cursor_text_color_dark(self, value: Color) -> None:
        """
        Sets the cursor text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Text Color (Dark)", value)

    async def async_set_ansi_0_color(self, value: Color) -> None:
        """
        Sets the ANSI 0 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 0 Color", value)

    async def async_set_ansi_0_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 0 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 0 Color (Light)", value)

    async def async_set_ansi_0_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 0 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 0 Color (Dark)", value)

    async def async_set_ansi_1_color(self, value: Color) -> None:
        """
        Sets the ANSI 1 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 1 Color", value)

    async def async_set_ansi_1_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 1 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 1 Color (Light)", value)

    async def async_set_ansi_1_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 1 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 1 Color (Dark)", value)

    async def async_set_ansi_2_color(self, value: Color) -> None:
        """
        Sets the ANSI 2 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 2 Color", value)

    async def async_set_ansi_2_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 2 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 2 Color (Light)", value)

    async def async_set_ansi_2_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 2 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 2 Color (Dark)", value)

    async def async_set_ansi_3_color(self, value: Color) -> None:
        """
        Sets the ANSI 3 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 3 Color", value)

    async def async_set_ansi_3_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 3 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 3 Color (Light)", value)

    async def async_set_ansi_3_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 3 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 3 Color (Dark)", value)

    async def async_set_ansi_4_color(self, value: Color) -> None:
        """
        Sets the ANSI 4 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 4 Color", value)

    async def async_set_ansi_4_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 4 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 4 Color (Light)", value)

    async def async_set_ansi_4_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 4 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 4 Color (Dark)", value)

    async def async_set_ansi_5_color(self, value: Color) -> None:
        """
        Sets the ANSI 5 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 5 Color", value)

    async def async_set_ansi_5_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 5 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 5 Color (Light)", value)

    async def async_set_ansi_5_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 5 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 5 Color (Dark)", value)

    async def async_set_ansi_6_color(self, value: Color) -> None:
        """
        Sets the ANSI 6 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 6 Color", value)

    async def async_set_ansi_6_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 6 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 6 Color (Light)", value)

    async def async_set_ansi_6_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 6 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 6 Color (Dark)", value)

    async def async_set_ansi_7_color(self, value: Color) -> None:
        """
        Sets the ANSI 7 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 7 Color", value)

    async def async_set_ansi_7_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 7 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 7 Color (Light)", value)

    async def async_set_ansi_7_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 7 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 7 Color (Dark)", value)

    async def async_set_ansi_8_color(self, value: Color) -> None:
        """
        Sets the ANSI 8 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 8 Color", value)

    async def async_set_ansi_8_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 8 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 8 Color (Light)", value)

    async def async_set_ansi_8_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 8 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 8 Color (Dark)", value)

    async def async_set_ansi_9_color(self, value: Color) -> None:
        """
        Sets the ANSI 9 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 9 Color", value)

    async def async_set_ansi_9_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 9 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 9 Color (Light)", value)

    async def async_set_ansi_9_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 9 color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 9 Color (Dark)", value)

    async def async_set_ansi_10_color(self, value: Color) -> None:
        """
        Sets the ANSI 10 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 10 Color", value)

    async def async_set_ansi_10_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 10 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 10 Color (Light)", value)

    async def async_set_ansi_10_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 10 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 10 Color (Dark)", value)

    async def async_set_ansi_11_color(self, value: Color) -> None:
        """
        Sets the ANSI 11 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 11 Color", value)

    async def async_set_ansi_11_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 11 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 11 Color (Light)", value)

    async def async_set_ansi_11_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 11 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 11 Color (Dark)", value)

    async def async_set_ansi_12_color(self, value: Color) -> None:
        """
        Sets the ANSI 12 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 12 Color", value)

    async def async_set_ansi_12_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 12 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 12 Color (Light)", value)

    async def async_set_ansi_12_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 12 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 12 Color (Dark)", value)

    async def async_set_ansi_13_color(self, value: Color) -> None:
        """
        Sets the ANSI 13 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 13 Color", value)

    async def async_set_ansi_13_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 13 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 13 Color (Light)", value)

    async def async_set_ansi_13_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 13 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 13 Color (Dark)", value)

    async def async_set_ansi_14_color(self, value: Color) -> None:
        """
        Sets the ANSI 14 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 14 Color", value)

    async def async_set_ansi_14_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 14 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 14 Color (Light)", value)

    async def async_set_ansi_14_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 14 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 14 Color (Dark)", value)

    async def async_set_ansi_15_color(self, value: Color) -> None:
        """
        Sets the ANSI 15 color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 15 Color", value)

    async def async_set_ansi_15_color_light(self, value: Color) -> None:
        """
        Sets the ANSI 15 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 15 Color (Light)", value)

    async def async_set_ansi_15_color_dark(self, value: Color) -> None:
        """
        Sets the ANSI 15 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Ansi 15 Color (Dark)", value)

    async def async_set_smart_cursor_color(self, value: bool) -> None:
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This is used only when separate light/dark mode colors are not
        enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Smart Cursor Color", value)

    async def async_set_smart_cursor_color_light(self, value: bool) -> None:
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Smart Cursor Color (Light)", value)

    async def async_set_smart_cursor_color_dark(self, value: bool) -> None:
        """
        Sets whether to use smart cursor color. This only applies to box
        cursors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Smart Cursor Color (Dark)", value)

    async def async_set_minimum_contrast(self, value: float) -> None:
        """
        Sets the minimum contrast, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return await self._async_simple_set("Minimum Contrast", value)

    async def async_set_minimum_contrast_light(self, value: float) -> None:
        """
        Sets the minimum contrast, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Minimum Contrast (Light)", value)

    async def async_set_minimum_contrast_dark(self, value: float) -> None:
        """
        Sets the minimum contrast, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Minimum Contrast (Dark)", value)

    async def async_set_tab_color(self, value: Color) -> None:
        """
        Sets the tab color. This is used only when separate light/dark mode
        colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Tab Color", value)

    async def async_set_tab_color_light(self, value: Color) -> None:
        """
        Sets the tab color. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Tab Color (Light)", value)

    async def async_set_tab_color_dark(self, value: Color) -> None:
        """
        Sets the tab color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Tab Color (Dark)", value)

    async def async_set_use_tab_color(self, value: bool) -> None:
        """
        Sets whether the tab color should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Tab Color", value)

    async def async_set_use_tab_color_light(self, value: bool) -> None:
        """
        Sets whether the tab color should be used. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Tab Color (Light)", value)

    async def async_set_use_tab_color_dark(self, value: bool) -> None:
        """
        Sets whether the tab color should be used. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Tab Color (Dark)", value)

    async def async_set_underline_color(self, value: Color | None) -> None:
        """
        Sets the underline color. This is used only when separate light/dark
        mode colors are not enabled.

        :param value: A :class:`Color` or `None`
        """
        return await self._async_color_set("Underline Color", value)

    async def async_set_underline_color_light(self, value: Color | None) -> None:
        """
        Sets the underline color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color` or `None`
        """
        return await self._async_color_set("Underline Color (Light)", value)

    async def async_set_underline_color_dark(self, value: Color | None) -> None:
        """
        Sets the underline color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :param value: A :class:`Color` or `None`
        """
        return await self._async_color_set("Underline Color (Dark)", value)

    async def async_set_use_underline_color(self, value: bool) -> None:
        """
        Sets whether to use the specified underline color. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Underline Color", value)

    async def async_set_use_underline_color_light(self, value: bool) -> None:
        """
        Sets whether to use the specified underline color. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Underline Color (Light)", value)

    async def async_set_use_underline_color_dark(self, value: bool) -> None:
        """
        Sets whether to use the specified underline color. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Underline Color (Dark)", value)

    async def async_set_cursor_boost(self, value: float) -> None:
        """
        Sets the cursor boost level, in 0 to 1. This is used only when separate
        light/dark mode colors are not enabled.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Boost", value)

    async def async_set_cursor_boost_light(self, value: float) -> None:
        """
        Sets the cursor boost level, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Boost (Light)", value)

    async def async_set_cursor_boost_dark(self, value: float) -> None:
        """
        Sets the cursor boost level, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Boost (Dark)", value)

    async def async_set_use_cursor_guide(self, value: bool) -> None:
        """
        Sets whether the cursor guide should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Cursor Guide", value)

    async def async_set_use_cursor_guide_light(self, value: bool) -> None:
        """
        Sets whether the cursor guide should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Cursor Guide (Light)", value)

    async def async_set_use_cursor_guide_dark(self, value: bool) -> None:
        """
        Sets whether the cursor guide should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Cursor Guide (Dark)", value)

    async def async_set_cursor_guide_color(self, value: Color) -> None:
        """
        Sets the cursor guide color. The alpha value is respected. This is used
        only when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Guide Color", value)

    async def async_set_cursor_guide_color_light(self, value: Color) -> None:
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Guide Color (Light)", value)

    async def async_set_cursor_guide_color_dark(self, value: Color) -> None:
        """
        Sets the cursor guide color. The alpha value is respected. This affects
        the dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Cursor Guide Color (Dark)", value)

    async def async_set_badge_color(self, value: Color) -> None:
        """
        Sets the badge color. The alpha value is respected. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Badge Color", value)

    async def async_set_badge_color_light(self, value: Color) -> None:
        """
        Sets the badge color. The alpha value is respected. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Badge Color (Light)", value)

    async def async_set_badge_color_dark(self, value: Color) -> None:
        """
        Sets the badge color. The alpha value is respected. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Badge Color (Dark)", value)

    async def async_set_match_color(self, value: Color) -> None:
        """
        Sets the highlight color for search matches. This is used only when
        separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Match Background Color", value)

    async def async_set_match_color_light(self, value: Color) -> None:
        """
        Sets the highlight color for search matches. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Match Background Color (Light)", value)

    async def async_set_match_color_dark(self, value: Color) -> None:
        """
        Sets the highlight color for search matches. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("Match Background Color (Dark)", value)

    async def async_set_ime_cursor_color(self, value: Color) -> None:
        """
        Sets the cursor color while composing text with an input method. This
        is used only when separate light/dark mode colors are not enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("IME Cursor Color", value)

    async def async_set_ime_cursor_color_light(self, value: Color) -> None:
        """
        Sets the cursor color while composing text with an input method. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("IME Cursor Color (Light)", value)

    async def async_set_ime_cursor_color_dark(self, value: Color) -> None:
        """
        Sets the cursor color while composing text with an input method. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A :class:`Color`
        """
        return await self._async_color_set("IME Cursor Color (Dark)", value)

    async def async_set_use_selected_text_color(self, value: bool) -> None:
        """
        Sets whether selected text is drawn in the selected text color. This is
        used only when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Selected Text Color", value)

    async def async_set_use_selected_text_color_light(self, value: bool) -> None:
        """
        Sets whether selected text is drawn in the selected text color. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Selected Text Color (Light)", value)

    async def async_set_use_selected_text_color_dark(self, value: bool) -> None:
        """
        Sets whether selected text is drawn in the selected text color. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Selected Text Color (Dark)", value)

    async def async_set_active_pane_border_color(self, value: Color) -> None:
        """
        Sets the color of the border around the active pane. This is used only
        when separate light/dark mode colors are not enabled.

        This is used only when use_active_pane_border is True.
        """
        return await self._async_color_set("Active Pane Border Color", value)

    async def async_set_active_pane_border_color_light(self, value: Color) -> None:
        """
        Sets the color of the border around the active pane. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        This is used only when use_active_pane_border is True.
        """
        return await self._async_color_set("Active Pane Border Color (Light)", value)

    async def async_set_active_pane_border_color_dark(self, value: Color) -> None:
        """
        Sets the color of the border around the active pane. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        This is used only when use_active_pane_border is True.
        """
        return await self._async_color_set("Active Pane Border Color (Dark)", value)

    async def async_set_use_active_pane_border(self, value: bool) -> None:
        """
        Sets whether to draw a border around the active pane. This is used only
        when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Active Pane Border", value)

    async def async_set_use_active_pane_border_light(self, value: bool) -> None:
        """
        Sets whether to draw a border around the active pane. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Active Pane Border (Light)", value)

    async def async_set_use_active_pane_border_dark(self, value: bool) -> None:
        """
        Sets whether to draw a border around the active pane. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Use Active Pane Border (Dark)", value)

    async def async_set_faint_text_alpha(self, value: float) -> None:
        """
        Sets the opacity of faint text. This is used only when separate
        light/dark mode colors are not enabled.

        The value is between 0 and 1.
        """
        return await self._async_simple_set("Faint Text Alpha", value)

    async def async_set_faint_text_alpha_light(self, value: float) -> None:
        """
        Sets the opacity of faint text. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        The value is between 0 and 1.
        """
        return await self._async_simple_set("Faint Text Alpha (Light)", value)

    async def async_set_faint_text_alpha_dark(self, value: float) -> None:
        """
        Sets the opacity of faint text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        The value is between 0 and 1.
        """
        return await self._async_simple_set("Faint Text Alpha (Dark)", value)

    async def async_set_harmonize_256_colors(self, value: bool) -> None:
        """
        Sets whether the 256-color palette is adjusted to match the ANSI
        colors. This is used only when separate light/dark mode colors are not
        enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Harmonize 256 Colors", value)

    async def async_set_harmonize_256_colors_light(self, value: bool) -> None:
        """
        Sets whether the 256-color palette is adjusted to match the ANSI
        colors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Harmonize 256 Colors (Light)", value)

    async def async_set_harmonize_256_colors_dark(self, value: bool) -> None:
        """
        Sets whether the 256-color palette is adjusted to match the ANSI
        colors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Harmonize 256 Colors (Dark)", value)

    async def async_set_hdr_cursor(self, value: bool) -> None:
        """
        Sets whether the cursor is drawn brighter than white on HDR displays.
        This is used only when separate light/dark mode colors are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("HDR Cursor", value)

    async def async_set_hdr_cursor_light(self, value: bool) -> None:
        """
        Sets whether the cursor is drawn brighter than white on HDR displays.
        This affects the light-mode variant when separate light/dark mode
        colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("HDR Cursor (Light)", value)

    async def async_set_hdr_cursor_dark(self, value: bool) -> None:
        """
        Sets whether the cursor is drawn brighter than white on HDR displays.
        This affects the dark-mode variant when separate light/dark mode colors
        are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("HDR Cursor (Dark)", value)

    async def async_set_hdr_cursor_brightness(self, value: float) -> None:
        """
        Sets the brightness of the HDR cursor. This is used only when separate
        light/dark mode colors are not enabled.

        The value is a multiple of reference white, at most 16.
        """
        return await self._async_simple_set("HDR Cursor Brightness", value)

    async def async_set_hdr_cursor_brightness_light(self, value: float) -> None:
        """
        Sets the brightness of the HDR cursor. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, at most 16.
        """
        return await self._async_simple_set("HDR Cursor Brightness (Light)", value)

    async def async_set_hdr_cursor_brightness_dark(self, value: float) -> None:
        """
        Sets the brightness of the HDR cursor. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, at most 16.
        """
        return await self._async_simple_set("HDR Cursor Brightness (Dark)", value)

    async def async_set_hdr_text(self, value: bool) -> None:
        """
        Sets whether the focused pane's text is drawn brighter than white on
        HDR displays. This is used only when separate light/dark mode colors
        are not enabled.

        :param value: A bool
        """
        return await self._async_simple_set("HDR Text", value)

    async def async_set_hdr_text_light(self, value: bool) -> None:
        """
        Sets whether the focused pane's text is drawn brighter than white on
        HDR displays. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("HDR Text (Light)", value)

    async def async_set_hdr_text_dark(self, value: bool) -> None:
        """
        Sets whether the focused pane's text is drawn brighter than white on
        HDR displays. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :param value: A bool
        """
        return await self._async_simple_set("HDR Text (Dark)", value)

    async def async_set_hdr_text_brightness(self, value: float) -> None:
        """
        Sets the brightness of HDR text. This is used only when separate
        light/dark mode colors are not enabled.

        The value is a multiple of reference white, from 1.5 to 16.
        """
        return await self._async_simple_set("HDR Text Brightness", value)

    async def async_set_hdr_text_brightness_light(self, value: float) -> None:
        """
        Sets the brightness of HDR text. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, from 1.5 to 16.
        """
        return await self._async_simple_set("HDR Text Brightness (Light)", value)

    async def async_set_hdr_text_brightness_dark(self, value: float) -> None:
        """
        Sets the brightness of HDR text. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, from 1.5 to 16.
        """
        return await self._async_simple_set("HDR Text Brightness (Dark)", value)

    async def async_set_name(self, value: str) -> None:
        """
        Sets the name.

        :param value: A str
        """
        return await self._async_simple_set("Name", value)

    async def async_set_badge_text(self, value: str) -> None:
        """
        Sets the badge text.

        :param value: A str
        """
        return await self._async_simple_set("Badge Text", value)

    async def async_set_subtitle(self, value: str) -> None:
        """
        Sets the subtitle, an interpolated string.

        :param value: A str
        """
        return await self._async_simple_set("Subtitle", value)

    async def async_set_answerback_string(self, value: str) -> None:
        """
        Sets the answerback string.

        :param value: A str
        """
        return await self._async_simple_set("Answerback String", value)

    async def async_set_blinking_cursor(self, value: bool) -> None:
        """
        Sets whether the cursor blinks.

        :param value: A bool
        """
        return await self._async_simple_set("Blinking Cursor", value)

    async def async_set_cursor_shadow(self, value: bool) -> None:
        """
        Sets whether the vertical bar and horizontal line cursor have a shadow.

        :param value: A bool
        """
        return await self._async_simple_set("Cursor Shadow", value)

    async def async_set_use_bold_font(self, value: bool) -> None:
        """
        Sets whether to use the bold variant of the font for bold text.

        :param value: A bool
        """
        return await self._async_simple_set("Use Bold Font", value)

    async def async_set_ascii_ligatures(self, value: bool) -> None:
        """
        Sets whether ligatures should be used for ASCII text.

        :param value: A bool
        """
        return await self._async_simple_set("ASCII Ligatures", value)

    async def async_set_non_ascii_ligatures(self, value: bool) -> None:
        """
        Sets whether ligatures should be used for non-ASCII text.

        :param value: A bool
        """
        return await self._async_simple_set("Non-ASCII Ligatures", value)

    async def async_set_blink_allowed(self, value: bool) -> None:
        """
        Sets whether blinking text is allowed.

        :param value: A bool
        """
        return await self._async_simple_set("Blink Allowed", value)

    async def async_set_use_italic_font(self, value: bool) -> None:
        """
        Sets whether italic text is allowed.

        :param value: A bool
        """
        return await self._async_simple_set("Use Italic Font", value)

    async def async_set_ambiguous_double_width(self, value: bool) -> None:
        """
        Sets whether ambiguous-width text should be treated as double-width.

        :param value: A bool
        """
        return await self._async_simple_set("Ambiguous Double Width", value)

    async def async_set_horizontal_spacing(self, value: float) -> None:
        """
        Sets the fraction of horizontal spacing. Must be non-negative.

        :param value: A float
        """
        return await self._async_simple_set("Horizontal Spacing", value)

    async def async_set_vertical_spacing(self, value: float) -> None:
        """
        Sets the fraction of vertical spacing. Must be non-negative.

        :param value: A float
        """
        return await self._async_simple_set("Vertical Spacing", value)

    async def async_set_use_non_ascii_font(self, value: bool) -> None:
        """
        Sets whether to use a different font for non-ASCII text.

        :param value: A bool
        """
        return await self._async_simple_set("Use Non-ASCII Font", value)

    async def async_set_transparency(self, value: float) -> None:
        """
        Sets the level of transparency.

        The value is between 0 and 1.
        """
        return await self._async_simple_set("Transparency", value)

    async def async_set_blur(self, value: bool) -> None:
        """
        Sets whether background blur should be enabled.

        :param value: A bool
        """
        return await self._async_simple_set("Blur", value)

    async def async_set_blur_radius(self, value: float) -> None:
        """
        Sets the blur radius (how blurry). Requires blur to be enabled.

        The value is between 0 and 30.
        """
        return await self._async_simple_set("Blur Radius", value)

    async def async_set_background_image_mode(self, value: BackgroundImageMode) -> None:
        """
        Sets how the background image is drawn.

        :param value: A `BackgroundImageMode`
        """
        return await self._async_simple_set("Background Image Mode", value)

    async def async_set_blend(self, value: float) -> None:
        """
        Sets how much the default background color gets blended with the
        background image.

        The value is in 0 to 1.

        .. seealso:: Example ":ref:`blending_example`
        """
        return await self._async_simple_set("Blend", value)

    async def async_set_sync_title(self, value: bool) -> None:
        """
        Sets whether the profile name stays in the tab title, even if changed
        by an escape sequence.

        :param value: A bool
        """
        return await self._async_simple_set("Sync Title", value)

    async def async_set_use_built_in_powerline_glyphs(self, value: bool) -> None:
        """
        Sets whether powerline glyphs should be drawn by iTerm2 or left to the
        font.

        :param value: A bool
        """
        return await self._async_simple_set("Draw Powerline Glyphs", value)

    async def async_set_disable_window_resizing(self, value: bool) -> None:
        """
        Sets whether the terminal can resize the window with an escape
        sequence.

        :param value: A bool
        """
        return await self._async_simple_set("Disable Window Resizing", value)

    async def async_set_allow_change_cursor_blink(self, value: bool) -> None:
        """
        Sets whether the terminal can change the cursor blink setting with an
        escape sequence.

        :param value: A bool
        """
        return await self._async_simple_set("Allow Change Cursor Blink", value)

    async def async_set_only_the_default_bg_color_uses_transparency(
        self, value: bool
    ) -> None:
        """
        Sets whether window transparency shows through non-default background
        colors.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Only The Default BG Color Uses Transparency", value
        )

    async def async_set_ascii_anti_aliased(self, value: bool) -> None:
        """
        Sets whether ASCII text is anti-aliased.

        :param value: A bool
        """
        return await self._async_simple_set("ASCII Anti Aliased", value)

    async def async_set_non_ascii_anti_aliased(self, value: bool) -> None:
        """
        Sets whether non-ASCII text is anti-aliased.

        :param value: A bool
        """
        return await self._async_simple_set("Non-ASCII Anti Aliased", value)

    async def async_set_scrollback_lines(self, value: int) -> None:
        """
        Sets the number of scrollback lines.

        Value must be at least 0.
        """
        return await self._async_simple_set("Scrollback Lines", value)

    async def async_set_unlimited_scrollback(self, value: bool) -> None:
        """
        Sets whether the scrollback buffer's length is unlimited.

        :param value: A bool
        """
        return await self._async_simple_set("Unlimited Scrollback", value)

    async def async_set_scrollback_with_status_bar(self, value: bool) -> None:
        """
        Sets whether text gets appended to scrollback when there is an app
        status bar

        :param value: A bool
        """
        return await self._async_simple_set("Scrollback With Status Bar", value)

    async def async_set_scrollback_in_alternate_screen(self, value: bool) -> None:
        """
        Sets whether text gets appended to scrollback in alternate screen mode.

        :param value: A bool
        """
        return await self._async_simple_set("Scrollback in Alternate Screen", value)

    async def async_set_mouse_reporting(self, value: bool) -> None:
        """
        Sets whether mouse reporting is allowed

        :param value: A bool
        """
        return await self._async_simple_set("Mouse Reporting", value)

    async def async_set_mouse_reporting_allow_mouse_wheel(self, value: bool) -> None:
        """
        Sets whether mouse reporting reports the mouse wheel's movements.

        :param value: A bool
        """
        return await self._async_simple_set("Mouse Reporting allow mouse wheel", value)

    async def async_set_allow_title_reporting(self, value: bool) -> None:
        """
        Sets whether the session title can be reported

        :param value: A bool
        """
        return await self._async_simple_set("Allow Title Reporting", value)

    async def async_set_allow_title_setting(self, value: bool) -> None:
        """
        Sets whether the session title can be changed by escape sequence

        :param value: A bool
        """
        return await self._async_simple_set("Allow Title Setting", value)

    async def async_set_disable_printing(self, value: bool) -> None:
        """
        Sets whether printing by escape sequence is disabled.

        :param value: A bool
        """
        return await self._async_simple_set("Disable Printing", value)

    async def async_set_disable_smcup_rmcup(self, value: bool) -> None:
        """
        Sets whether alternate screen mode is disabled

        :param value: A bool
        """
        return await self._async_simple_set("Disable Smcup Rmcup", value)

    async def async_set_silence_bell(self, value: bool) -> None:
        """
        Sets whether the bell makes noise.

        :param value: A bool
        """
        return await self._async_simple_set("Silence Bell", value)

    async def async_set_bm_growl(self, value: bool) -> None:
        """
        Sets whether notifications should be shown.

        :param value: A bool
        """
        return await self._async_simple_set("BM Growl", value)

    async def async_set_send_bell_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for the bell ringing

        :param value: A bool
        """
        return await self._async_simple_set("Send Bell Alert", value)

    async def async_set_send_idle_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for becoming idle

        :param value: A bool
        """
        return await self._async_simple_set("Send Idle Alert", value)

    async def async_set_send_new_output_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for new output

        :param value: A bool
        """
        return await self._async_simple_set("Send New Output Alert", value)

    async def async_set_send_session_ended_alert(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for a session ending

        :param value: A bool
        """
        return await self._async_simple_set("Send Session Ended Alert", value)

    async def async_set_send_terminal_generated_alerts(self, value: bool) -> None:
        """
        Sets whether notifications should be shown for escape-sequence
        originated notifications

        :param value: A bool
        """
        return await self._async_simple_set("Send Terminal Generated Alerts", value)

    async def async_set_flashing_bell(self, value: bool) -> None:
        """
        Sets whether the bell should flash the screen

        :param value: A bool
        """
        return await self._async_simple_set("Flashing Bell", value)

    async def async_set_visual_bell(self, value: bool) -> None:
        """
        Sets whether a bell should be shown when the bell rings

        :param value: A bool
        """
        return await self._async_simple_set("Visual Bell", value)

    async def async_set_close_sessions_on_end(self, value: bool) -> None:
        """
        Sets whether the session should close when it ends.

        :param value: A bool
        """
        return await self._async_simple_set("Close Sessions On End", value)

    async def async_set_prompt_before_closing(self, value: bool) -> None:
        """
        Sets whether the session should prompt before closing.

        :param value: A bool
        """
        return await self._async_simple_set("Prompt Before Closing 2", value)

    async def async_set_session_close_undo_timeout(self, value: float) -> None:
        """
        Sets the amount of time you can undo closing a session

        The value is at least 0.
        """
        return await self._async_simple_set("Session Close Undo Timeout", value)

    async def async_set_reduce_flicker(self, value: bool) -> None:
        """
        Sets whether the flicker fixer is on.

        :param value: A bool
        """
        return await self._async_simple_set("Reduce Flicker", value)

    async def async_set_send_code_when_idle(self, value: bool) -> None:
        """
        Sets whether to send a code when idle

        :param value: A bool
        """
        return await self._async_simple_set("Send Code When Idle", value)

    async def async_set_application_keypad_allowed(self, value: bool) -> None:
        """
        Sets whether the terminal may be placed in application keypad mode

        :param value: A bool
        """
        return await self._async_simple_set("Application Keypad Allowed", value)

    async def async_set_place_prompt_at_first_column(self, value: bool) -> None:
        """
        Sets whether the prompt should always begin at the first column
        (requires shell integration)

        :param value: A bool
        """
        return await self._async_simple_set("Place Prompt at First Column", value)

    async def async_set_show_mark_indicators(self, value: bool) -> None:
        """
        Sets whether mark indicators should be visible

        :param value: A bool
        """
        return await self._async_simple_set("Show Mark Indicators", value)

    async def async_set_idle_code(self, value: int) -> None:
        """
        Sets the ASCII code to send on idle

        Value is an int in 0 through 255.
        """
        return await self._async_simple_set("Idle Code", value)

    async def async_set_idle_period(self, value: float) -> None:
        """
        Sets how often to send a code when idle

        Value is a float at least 0
        """
        return await self._async_simple_set("Idle Period", value)

    async def async_set_unicode_version(self, value: bool) -> None:
        """
        Sets the unicode version for wcwidth

        :param value: A bool
        """
        return await self._async_simple_set("Unicode Version", value)

    async def async_set_cursor_type(self, value: CursorType) -> None:
        """
        Sets the cursor type

        :param value: A CursorType
        """
        return await self._async_simple_set("Cursor Type", value)

    async def async_set_thin_strokes(self, value: ThinStrokes) -> None:
        """
        Sets whether thin strokes are used.

        :param value: A ThinStrokes
        """
        return await self._async_simple_set("Thin Strokes", value)

    async def async_set_unicode_normalization(
        self, value: UnicodeNormalization
    ) -> None:
        """
        Sets the unicode normalization form to use

        :param value: An UnicodeNormalization
        """
        return await self._async_simple_set("Unicode Normalization", value)

    async def async_set_character_encoding(self, value: CharacterEncoding) -> None:
        """
        Sets the character encoding

        :param value: A CharacterEncoding
        """
        return await self._async_simple_set("Character Encoding", value)

    async def async_set_left_option_key_sends(self, value: OptionKeySends) -> None:
        """
        Sets the behavior of the left option key.

        :param value: An OptionKeySends
        """
        return await self._async_simple_set("Option Key Sends", value)

    async def async_set_right_option_key_sends(self, value: OptionKeySends) -> None:
        """
        Sets the behavior of the right option key.

        :param value: An OptionKeySends
        """
        return await self._async_simple_set("Right Option Key Sends", value)

    async def async_set_triggers(self, value: list[dict[str, Any]]) -> None:
        """
        Sets the triggers.

        Value is an encoded trigger. Use iterm2.decode_trigger to convert from
        an encoded trigger to an object. Trigger objects can be encoded using
        the encode property.
        """
        return await self._async_simple_set("Triggers", value)

    async def async_set_smart_selection_rules(
        self, value: list[dict[str, Any]]
    ) -> None:
        """
        Sets the smart selection rules.

        The value is a list of dicts of smart selection rules (currently
        undocumented)
        """
        return await self._async_simple_set("Smart Selection Rules", value)

    async def async_set_smart_selection_actions_use_interpolated_strings(
        self, value: bool
    ) -> None:
        """
        Sets whether smart selection action parameters are interpolated
        strings.

        Should smart selection actions' parameters be treated as interpolated
        strings? If false, use the backward-compatibility syntax.
        """
        return await self._async_simple_set(
            "Smart Selection Actions Use Interpolated Strings", value
        )

    async def async_set_semantic_history(self, value: dict[str, Any]) -> None:
        """
        Sets the semantic history prefs.

        :param value: A dict[str, Any]
        """
        return await self._async_simple_set("Semantic History", value)

    async def async_set_automatic_profile_switching_rules(
        self, value: list[str]
    ) -> None:
        """
        Sets the automatic profile switching rules.

        Value is a list of strings, each giving a rule.
        """
        return await self._async_simple_set("Bound Hosts", value)

    async def async_set_advanced_working_directory_window_setting(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets the advanced working directory window setting.

        Value excludes Advanced.
        """
        return await self._async_simple_set("AWDS Window Option", value)

    async def async_set_advanced_working_directory_window_directory(
        self, value: str
    ) -> None:
        """
        Sets the advanced working directory window directory.

        :param value: A str
        """
        return await self._async_simple_set("AWDS Window Directory", value)

    async def async_set_advanced_working_directory_tab_setting(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets the advanced working directory tab setting.

        Value excludes Advanced.
        """
        return await self._async_simple_set("AWDS Tab Option", value)

    async def async_set_advanced_working_directory_tab_directory(
        self, value: str
    ) -> None:
        """
        Sets the advanced working directory tab directory.

        :param value: A str
        """
        return await self._async_simple_set("AWDS Tab Directory", value)

    async def async_set_advanced_working_directory_pane_setting(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets the advanced working directory pane setting.

        Value excludes Advanced.
        """
        return await self._async_simple_set("AWDS Pane Option", value)

    async def async_set_advanced_working_directory_pane_directory(
        self, value: str
    ) -> None:
        """
        Sets the advanced working directory pane directory.

        :param value: A str
        """
        return await self._async_simple_set("AWDS Pane Directory", value)

    async def async_set_normal_font(self, value: str) -> None:
        """
        Sets the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii. The value is a font's
        name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"
        """
        return await self._async_simple_set("Normal Font", value)

    async def async_set_non_ascii_font(self, value: str) -> None:
        """
        Sets the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.
        The value is the font name and size as a string.
        """
        return await self._async_simple_set("Non Ascii Font", value)

    async def async_set_background_image_location(self, value: str) -> None:
        """
        Sets or clears the path to a background image.

        The value is a string with the path to the image file,
        or an empty string to clear the setting.

        :param value: A str
        """
        return await self._async_simple_set("Background Image Location", value)

    async def async_set_key_mappings(self, value: dict[str, Any]) -> None:
        """
        Sets the keyboard shortcuts.

        The value is a Dictionary mapping keystroke to action. You can convert
        between the values in this dictionary and a :class:`~iterm2.KeyBinding`
        using `iterm2.decode_key_binding`
        """
        return await self._async_simple_set("Keyboard Map", value)

    async def async_set_touchbar_mappings(self, value: dict[str, Any]) -> None:
        """
        Sets the touchbar actions.

        The value is a Dictionary mapping touch bar item to action
        """
        return await self._async_simple_set("Touch Bar Map", value)

    async def async_set_use_custom_command(self, value: str) -> None:
        """
        Sets whether to use a custom command when the session is created.

        The value is the string Yes or No
        """
        return await self._async_simple_set("Custom Command", value)

    async def async_set_command(self, value: str) -> None:
        """
        Sets the command to run when the session starts.

        The value is a string giving the command to run
        """
        return await self._async_simple_set("Command", value)

    async def async_set_initial_directory_mode(
        self, value: InitialWorkingDirectory
    ) -> None:
        """
        Sets whether to use a custom (not home) initial working directory.

        :param value: An InitialWorkingDirectory
        """
        return await self._async_simple_set("Custom Directory", value.value)

    async def async_set_custom_directory(self, value: str) -> None:
        """
        Sets the initial working directory.

        The initial_directory_mode must be set to
        `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
        take effect.
        """
        return await self._async_simple_set("Working Directory", value)

    async def async_set_icon_mode(self, value: IconMode) -> None:
        """
        Sets the icon mode.

        :param value: An IconMode
        """
        return await self._async_simple_set("Icon", value.value)

    async def async_set_custom_icon_path(self, value: str) -> None:
        """
        Sets the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.
        """
        return await self._async_simple_set("Custom Icon Path", value)

    async def async_set_badge_top_margin(self, value: int) -> None:
        """
        Sets the top margin of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Top Margin", value)

    async def async_set_badge_right_margin(self, value: int) -> None:
        """
        Sets the right margin of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Right Margin", value)

    async def async_set_badge_max_width(self, value: int) -> None:
        """
        Sets the max width of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Max Width", value)

    async def async_set_badge_max_height(self, value: int) -> None:
        """
        Sets the max height of the badge.

        The value is in points.
        """
        return await self._async_simple_set("Badge Max Height", value)

    async def async_set_badge_font(self, value: str) -> None:
        """
        Sets the font of the badge.

        The font name is a string like "Helvetica".
        """
        return await self._async_simple_set("Badge Font", value)

    async def async_set_use_custom_window_title(self, value: bool) -> None:
        """
        Sets whether the custom window title is used.

        Should the custom window title in the profile be used?
        """
        return await self._async_simple_set("Use Custom Window Title", value)

    async def async_set_custom_window_title(self, value: str | None) -> None:
        """
        Sets the custom window title.

        This will only be used if use_custom_window_title is True.
        The value is an interpolated string.
        """
        return await self._async_simple_set("Custom Window Title", value)

    async def async_set_use_transparency_initially(self, value: bool) -> None:
        """
        Sets whether a window created with this profile respect the
        transparency setting.

        If True, use transparency; if False, force the window to
        be opaque (but it can be toggled with View > Use Transparency).
        """
        return await self._async_simple_set("Initial Use Transparency", value)

    async def async_set_status_bar_enabled(self, value: bool) -> None:
        """
        Sets whether the status bar be enabled.

        If True, the status bar will be shown.
        """
        return await self._async_simple_set("Show Status Bar", value)

    async def async_set_use_csi_u(self, value: bool) -> None:
        """
        Sets whether to report keystrokes with CSI u protocol.

        If True, CSI u will be enabled.
        """
        return await self._async_simple_set("Use libtickit protocol", value)

    async def async_set_triggers_use_interpolated_strings(self, value: bool) -> None:
        """
        Sets whether trigger parameters should be interpreted as interpolated
        strings.

        :param value: A bool
        """
        return await self._async_simple_set("Triggers Use Interpolated Strings", value)

    async def async_set_left_option_key_changeable(self, value: bool) -> None:
        """
        Sets whether apps should be able to change the left option key to send
        esc+.

        The values gives whether it should be allowed.
        """
        return await self._async_simple_set("Left Option Key Changeable", value)

    async def async_set_right_option_key_changeable(self, value: bool) -> None:
        """
        Sets whether apps should be able to change the right option key to send
        esc+.

        The values gives whether it should be allowed.
        """
        return await self._async_simple_set("Right Option Key Changeable", value)

    async def async_set_open_password_manager_automatically(self, value: bool) -> None:
        """
        Sets if the password manager should open automatically.

        The values gives whether it should open automatically.
        """
        return await self._async_simple_set(
            "Open Password Manager Automatically", value
        )

    async def async_set_tags(self, value: list[str]) -> None:
        """
        Sets the tags used to organize profiles.

        Set it to an empty list to remove all tags. The getter returns None or
        an empty list when the profile has no tags.
        """
        return await self._async_simple_set("Tags", value)

    async def async_set_shortcut(self, value: str) -> None:
        """
        Sets the keyboard shortcut that opens this profile.

        The value is a single uppercase letter or digit that opens the profile
        when pressed with Control and Command. Set it to an empty string to
        remove the shortcut. The getter returns None or an empty string when
        there is no shortcut. Give each shortcut to at most one profile.
        """
        return await self._async_simple_set("Shortcut", value)

    async def async_set_initial_text(self, value: str) -> None:
        """
        Sets the text to send to the session after it starts.

        The value is an interpolated string.
        """
        return await self._async_simple_set("Initial Text", value)

    async def async_set_run_command_in_login_shell(self, value: bool) -> None:
        """
        Sets whether a custom command runs inside the user's login shell.

        :param value: A bool
        """
        return await self._async_simple_set("Run Command In Login Shell", value)

    async def async_set_load_shell_integration_automatically(self, value: bool) -> None:
        """
        Sets whether shell integration is loaded automatically.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Load Shell Integration Automatically", value
        )

    async def async_set_snippets_filter(self, value: list[str]) -> None:
        """
        Sets the snippet tags available to sessions with this profile.

        An empty list makes all snippets available.
        """
        return await self._async_simple_set("Snippets Filter", value)

    async def async_set_cursor_hidden_without_focus(self, value: bool) -> None:
        """
        Sets whether the cursor is hidden when the session does not have
        keyboard focus.

        :param value: A bool
        """
        return await self._async_simple_set("Cursor Hidden When Unfocused", value)

    async def async_set_animate_movement(self, value: bool) -> None:
        """
        Sets whether cursor movement is animated.

        :param value: A bool
        """
        return await self._async_simple_set("Animate Movement", value)

    async def async_set_animate_movement_only_in_interactive_apps(
        self, value: bool
    ) -> None:
        """
        Sets whether cursor movement is animated only in interactive apps.

        This is used only when animate_movement is True.
        """
        return await self._async_simple_set(
            "Animate Movement Only in Interactive Apps", value
        )

    async def async_set_cursor_smooth_slide(self, value: bool) -> None:
        """
        Sets whether the cursor slides smoothly between positions.

        :param value: A bool
        """
        return await self._async_simple_set("Cursor Smooth Slide", value)

    async def async_set_cursor_smooth_blink(self, value: bool) -> None:
        """
        Sets whether a blinking cursor fades smoothly instead of switching on
        and off.

        :param value: A bool
        """
        return await self._async_simple_set("Cursor Smooth Blink", value)

    async def async_set_cursor_blink_fade_in_duration(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor takes to fade in.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Blink Fade In Duration", value)

    async def async_set_cursor_blink_fade_out_duration(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor takes to fade
        out.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Blink Fade Out Duration", value)

    async def async_set_cursor_blink_fade_in_curve(
        self, value: CursorBlinkFadeCurve
    ) -> None:
        """
        Sets the easing curve for a smoothly blinking cursor fading in.

        :param value: A CursorBlinkFadeCurve
        """
        return await self._async_simple_set("Cursor Blink Fade In Curve", value)

    async def async_set_cursor_blink_fade_out_curve(
        self, value: CursorBlinkFadeCurve
    ) -> None:
        """
        Sets the easing curve for a smoothly blinking cursor fading out.

        :param value: A CursorBlinkFadeCurve
        """
        return await self._async_simple_set("Cursor Blink Fade Out Curve", value)

    async def async_set_cursor_blink_visible_dwell(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor stays fully
        visible.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Blink Visible Dwell", value)

    async def async_set_cursor_blink_hidden_dwell(self, value: float) -> None:
        """
        Sets how long, in seconds, a smoothly blinking cursor stays fully
        hidden.

        :param value: A float
        """
        return await self._async_simple_set("Cursor Blink Hidden Dwell", value)

    async def async_set_use_theme_mark_colors(self, value: bool) -> None:
        """
        Sets whether mark indicators use colors from the ANSI palette.

        :param value: A bool
        """
        return await self._async_simple_set("Use Theme Mark Colors", value)

    async def async_set_background_image_source_mode(
        self, value: BackgroundImageSourceMode
    ) -> None:
        """
        Sets where the background image comes from.

        :param value: A BackgroundImageSourceMode
        """
        return await self._async_simple_set("Background Image Source Mode", value)

    async def async_set_background_image_folder_location(self, value: str) -> None:
        """
        Sets the folder of background images to rotate through.

        This is used only when background_image_source_mode is FOLDER_ROTATION.
        """
        return await self._async_simple_set("Background Image Folder Location", value)

    async def async_set_background_image_folder_interval(self, value: float) -> None:
        """
        Sets how often, in seconds, to change the background image when
        rotating through a folder.

        :param value: A float
        """
        return await self._async_simple_set("Background Image Folder Interval", value)

    async def async_set_window_type(self, value: WindowType) -> None:
        """
        Sets the style of window to open.

        :param value: A WindowType
        """
        return await self._async_simple_set("Window Type", value)

    async def async_set_columns(self, value: int) -> None:
        """
        Sets the initial number of columns.

        :param value: An int
        """
        return await self._async_simple_set("Columns", value)

    async def async_set_rows(self, value: int) -> None:
        """
        Sets the initial number of rows.

        :param value: An int
        """
        return await self._async_simple_set("Rows", value)

    async def async_set_width_percentage(self, value: float) -> None:
        """
        Sets the window's width as a percentage of the screen width.

        Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR,
        COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR,
        TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or
        RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a
        non-negative value switches the window from cell-based to
        screen-percentage sizing, even for a normal window. A negative value
        means size by columns instead. If the profile has no value, the window
        is sized by columns, except that top and bottom percentage windows span
        the full screen width. The getter still returns the default of 100 in
        that case.
        """
        return await self._async_simple_set("Width Percentage", value)

    async def async_set_height_percentage(self, value: float) -> None:
        """
        Sets the window's height as a percentage of the screen height.

        Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR,
        COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR,
        TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or
        RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a
        non-negative value switches the window from cell-based to
        screen-percentage sizing, even for a normal window. A negative value
        means size by rows instead. If the profile has no value, the window is
        sized by rows, except that left and right percentage windows span the
        full screen height. The getter still returns the default of 100 in that
        case.
        """
        return await self._async_simple_set("Height Percentage", value)

    async def async_set_screen(self, value: int) -> None:
        """
        Sets the screen on which new windows open.

        -1 means no preference, -2 means the screen with the pointer, 0 is the
        main screen, and higher numbers are other screens.
        """
        return await self._async_simple_set("Screen", value)

    async def async_set_space(self, value: int) -> None:
        """
        Sets the Space in which new windows open.

        0 means the current Space, -1 means all Spaces, and 1 through 9 are
        specific Spaces.
        """
        return await self._async_simple_set("Space", value)

    async def async_set_use_custom_tab_title(self, value: bool) -> None:
        """
        Sets whether the custom tab title is used.

        :param value: A bool
        """
        return await self._async_simple_set("Use Custom Tab Title", value)

    async def async_set_custom_tab_title(self, value: str) -> None:
        """
        Sets the custom tab title.

        This is used only when use_custom_tab_title is True. The value is an
        interpolated string.
        """
        return await self._async_simple_set("Custom Tab Title", value)

    async def async_set_hide_after_opening(self, value: bool) -> None:
        """
        Sets whether a new window is hidden right after it opens.

        :param value: A bool
        """
        return await self._async_simple_set("Hide After Opening", value)

    async def async_set_lock_window_size_automatically(self, value: bool) -> None:
        """
        Sets whether a new window's size is locked right after it opens.

        :param value: A bool
        """
        return await self._async_simple_set("Lock Window Size Automatically", value)

    async def async_set_disable_unfocused_window_resizing(self, value: bool) -> None:
        """
        Sets whether sessions without keyboard focus are prevented from
        resizing the window with an escape sequence.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Disable Window Resizing by Unfocused Sessions", value
        )

    async def async_set_prevent_tab(self, value: bool) -> None:
        """
        Sets whether this profile always opens in a new window, never in a tab.

        :param value: A bool
        """
        return await self._async_simple_set("Prevent Opening in a Tab", value)

    async def async_set_open_toolbelt(self, value: bool) -> None:
        """
        Sets whether new windows open with the toolbelt visible.

        :param value: A bool
        """
        return await self._async_simple_set("Open Toolbelt", value)

    async def async_set_show_rich_tab_content(self, value: bool) -> None:
        """
        Sets whether tabs in windows created with this profile show rich
        content.

        :param value: A bool
        """
        return await self._async_simple_set("Show Rich Tab Content", value)

    async def async_set_tab_content_maximum_lines(self, value: int) -> None:
        """
        Sets the most lines of rich content a tab shows.

        0 means no limit.
        """
        return await self._async_simple_set("Tab Content Maximum Lines", value)

    async def async_set_terminal_type(self, value: str) -> None:
        """
        Sets the terminal type reported to apps.

        The value is the TERM environment variable, such as xterm-256color.
        """
        return await self._async_simple_set("Terminal Type", value)

    async def async_set_locale_variables_mode(self, value: LocaleVariablesMode) -> None:
        """
        Sets how the locale environment variables are set.

        :param value: A LocaleVariablesMode
        """
        return await self._async_simple_set("Set Local Environment Vars", value)

    async def async_set_custom_locale(self, value: str) -> None:
        """
        Sets the custom locale.

        This is used only when locale_variables_mode is CUSTOM.
        """
        return await self._async_simple_set("Custom Locale", value)

    async def async_set_jobs_to_ignore(self, value: list[str]) -> None:
        """
        Sets the names of jobs that don't cause a prompt before closing.

        :param value: A list[str]
        """
        return await self._async_simple_set("Jobs to Ignore", value)

    async def async_set_bell_sound(self, value: str) -> None:
        """
        Sets the sound the bell plays.

        The value is the name of a sound installed in a Sounds folder, the path
        to an audio file, or an empty string for the system alert sound.
        """
        return await self._async_simple_set("Bell Sound", value)

    async def async_set_prevent_sleep(self, value: bool) -> None:
        """
        Sets whether the computer is kept from idle sleep while a session with
        this profile exists.

        :param value: A bool
        """
        return await self._async_simple_set("Prevent Sleep", value)

    async def async_set_allow_paste_bracketing(self, value: bool) -> None:
        """
        Sets whether apps may turn on bracketed paste mode.

        :param value: A bool
        """
        return await self._async_simple_set("Allow Paste Bracketing", value)

    async def async_set_enable_triggers_in_interactive_apps(self, value: bool) -> None:
        """
        Sets whether triggers fire in interactive apps.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Enable Triggers in Interactive Apps", value
        )

    async def async_set_tmux_newline(self, value: bool) -> None:
        """
        Sets whether pressing return in a tmux session sends a newline instead
        of a carriage return.

        :param value: A bool
        """
        return await self._async_simple_set("Tmux Newline", value)

    async def async_set_show_offscreen_command_line(self, value: bool) -> None:
        """
        Sets whether the command that produced the output at the top of the
        screen is shown when scrolled back.

        :param value: A bool
        """
        return await self._async_simple_set("Show Offscreen Command line", value)

    async def async_set_show_offscreen_command_line_for_current_command(
        self, value: bool
    ) -> None:
        """
        Sets whether the offscreen command line is also shown for the command
        that is still running.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Show Offscreen Command line for Current Command", value
        )

    async def async_set_prompt_path_click_opens_navigator(self, value: bool) -> None:
        """
        Sets whether clicking the path in a prompt opens a file navigator.

        :param value: A bool
        """
        return await self._async_simple_set("Prompt Path Click Opens Navigator", value)

    async def async_set_composer_top_offset(self, value: float) -> None:
        """
        Sets the composer's vertical offset from the top of the session.

        :param value: A float
        """
        return await self._async_simple_set("Composer Top Offset", value)

    async def async_set_default_pane_locked(self, value: bool) -> None:
        """
        Sets whether new panes are locked by default.

        :param value: A bool
        """
        return await self._async_simple_set("Default Pane Locked", value)

    async def async_set_buffer_input_by_default(self, value: bool) -> None:
        """
        Sets whether keyboard input is buffered by default in new sessions.

        :param value: A bool
        """
        return await self._async_simple_set("Buffer Input by Default", value)

    async def async_set_timestamps_visible(self, value: bool) -> None:
        """
        Sets whether timestamps are visible.

        :param value: A bool
        """
        return await self._async_simple_set("Timestamps Visible", value)

    async def async_set_timestamps_style(self, value: TimestampsStyle) -> None:
        """
        Sets how timestamps are drawn when visible.

        :param value: A TimestampsStyle
        """
        return await self._async_simple_set("Timestamps Style", value)

    async def async_set_enable_progress_bars(self, value: bool) -> None:
        """
        Sets whether progress bars reported by apps are shown.

        :param value: A bool
        """
        return await self._async_simple_set("Enable Progress Bars", value)

    async def async_set_progress_bar_height(self, value: float) -> None:
        """
        Sets the height of progress bars, in points.

        :param value: A float
        """
        return await self._async_simple_set("Progress Bar Height", value)

    async def async_set_progress_bar_color_scheme(self, value: str) -> None:
        """
        Sets the color scheme for progress bars.

        The value is one of default, rainbow, red, green, blue, yellow, purple,
        cyan, or orange.
        """
        return await self._async_simple_set("Progress Bar Color Scheme", value)

    async def async_set_send_alerts_to_companion(self, value: bool) -> None:
        """
        Sets whether this profile's notifications are also sent to the paired
        iTerm2 Buddy iPhone app.

        :param value: A bool
        """
        return await self._async_simple_set("Send Alerts To Companion", value)

    async def async_set_suppress_alerts_in_active_session(self, value: bool) -> None:
        """
        Sets whether notifications from the active session are suppressed.

        :param value: A bool
        """
        return await self._async_simple_set("Suppress Alerts in Active Session", value)

    async def async_set_mouse_reporting_allow_clicks_and_drags(
        self, value: bool
    ) -> None:
        """
        Sets whether mouse reporting reports clicks and drags.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Mouse Reporting allow clicks and drags", value
        )

    async def async_set_restrict_mouse_reporting_to_alternate_screen_mode(
        self, value: bool
    ) -> None:
        """
        Sets whether mouse reporting is allowed only in alternate screen mode.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Restrict Mouse Reporting to Alternate Screen Mode", value
        )

    async def async_set_allow_alternate_mouse_scroll(self, value: bool) -> None:
        """
        Sets whether scrolling in alternate screen mode sends arrow keys.

        :param value: A bool
        """
        return await self._async_simple_set("Allow Alternate Mouse Scroll", value)

    async def async_set_automatically_enable_alternate_mouse_scroll(
        self, value: bool
    ) -> None:
        """
        Sets whether scrolling sends arrow keys automatically in alternate
        screen mode.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Automatically Enable Alternate Mouse Scroll", value
        )

    async def async_set_restrict_alternate_mouse_scroll_to_vertical(
        self, value: bool
    ) -> None:
        """
        Sets whether only vertical scrolling sends arrow keys in alternate
        screen mode.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Restrict Alternate Mouse Scroll to Vertical", value
        )

    async def async_set_drag_to_scroll_in_alternate_screen_mode_disabled(
        self, value: bool
    ) -> None:
        """
        Sets whether dragging a selection past the edge stops scrolling in
        alternate screen mode.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Drag to Scroll in Alternate Screen Mode Disabled", value
        )

    async def async_set_left_control_key_behavior(
        self, value: ModifierKeyBehavior
    ) -> None:
        """
        Sets how the left control key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return await self._async_simple_set("Left Control Key", value)

    async def async_set_right_control_key_behavior(
        self, value: ModifierKeyBehavior
    ) -> None:
        """
        Sets how the right control key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return await self._async_simple_set("Right Control Key", value)

    async def async_set_left_command_key_behavior(
        self, value: ModifierKeyBehavior
    ) -> None:
        """
        Sets how the left command key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return await self._async_simple_set("Left Command Key", value)

    async def async_set_right_command_key_behavior(
        self, value: ModifierKeyBehavior
    ) -> None:
        """
        Sets how the right command key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return await self._async_simple_set("Right Command Key", value)

    async def async_set_function_key_behavior(self, value: ModifierKeyBehavior) -> None:
        """
        Sets how the fn key is reported to apps.

        :param value: A ModifierKeyBehavior
        """
        return await self._async_simple_set("Function Key", value)

    async def async_set_treat_option_as_alt(self, value: bool) -> None:
        """
        Sets whether option is reported as alt in modifier flags.

        :param value: A bool
        """
        return await self._async_simple_set("Treat Option as Alt", value)

    async def async_set_allow_modify_other_keys(self, value: bool) -> None:
        """
        Sets whether apps may turn on xterm's modifyOtherKeys mode.

        :param value: A bool
        """
        return await self._async_simple_set("Allow modifyOtherKeys", value)

    async def async_set_movement_keys_scroll_outside_interactive_apps(
        self, value: bool
    ) -> None:
        """
        Sets whether arrow and page keys scroll when not in an interactive app.

        :param value: A bool
        """
        return await self._async_simple_set(
            "Movement Keys Scroll Outside Interactive Apps", value
        )

    async def async_set_has_hotkey(self, value: bool) -> None:
        """
        Sets whether this profile has a dedicated hotkey window.

        To assign a hotkey without a key code, also set
        hotkey_activated_by_modifier and hotkey_modifier_activation.
        """
        return await self._async_simple_set("Has Hotkey", value)

    async def async_set_hotkey_activated_by_modifier(self, value: bool) -> None:
        """
        Sets whether double-tapping a modifier key toggles the hotkey window.

        :param value: A bool
        """
        return await self._async_simple_set("HotKey Activated By Modifier", value)

    async def async_set_hotkey_modifier_activation(
        self, value: HotkeyModifierActivation
    ) -> None:
        """
        Sets which modifier key to double-tap to toggle the hotkey window.

        :param value: A HotkeyModifierActivation
        """
        return await self._async_simple_set("HotKey Modifier Activation", value)

    async def async_set_hotkey_auto_hides(self, value: bool) -> None:
        """
        Sets whether the hotkey window hides when it loses focus.

        :param value: A bool
        """
        return await self._async_simple_set("HotKey Window AutoHides", value)

    async def async_set_hotkey_reopens_on_activation(self, value: bool) -> None:
        """
        Sets whether an auto-hidden hotkey window reappears when iTerm2 is
        activated.

        :param value: A bool
        """
        return await self._async_simple_set(
            "HotKey Window Reopens On Activation", value
        )

    async def async_set_hotkey_animates(self, value: bool) -> None:
        """
        Sets whether the hotkey window animates when it shows and hides.

        :param value: A bool
        """
        return await self._async_simple_set("HotKey Window Animates", value)

    async def async_set_hotkey_floats(self, value: bool) -> None:
        """
        Sets whether the hotkey window floats above other windows.

        :param value: A bool
        """
        return await self._async_simple_set("HotKey Window Floats", value)

    async def async_set_hotkey_dock_click_action(
        self, value: HotkeyWindowDockClickAction
    ) -> None:
        """
        Sets whether clicking iTerm2's Dock icon shows the hotkey window.

        :param value: A HotkeyWindowDockClickAction
        """
        return await self._async_simple_set("HotKey Window Dock Click Action", value)

    async def async_set_automatically_log(self, value: bool) -> None:
        """
        Sets whether session output is logged automatically.

        :param value: A bool
        """
        return await self._async_simple_set("Automatically Log", value)

    async def async_set_log_directory(self, value: str) -> None:
        """
        Sets the directory for automatic logs.

        :param value: A str
        """
        return await self._async_simple_set("Log Directory", value)

    async def async_set_log_filename_format(self, value: str) -> None:
        """
        Sets the format of automatic log file names.

        The value is an interpolated string.
        """
        return await self._async_simple_set("Log Filename Format", value)

    async def async_set_logging_style(self, value: LoggingStyle) -> None:
        """
        Sets the format of automatic logs.

        :param value: A LoggingStyle
        """
        return await self._async_simple_set("Plain Text Logging", value)

    async def async_set_archive_on_closure(self, value: bool) -> None:
        """
        Sets whether sessions are archived when they close.

        :param value: A bool
        """
        return await self._async_simple_set("Archive On Closure", value)

    async def async_set_archive_directory(self, value: str) -> None:
        """
        Sets the directory for archived sessions.

        :param value: A str
        """
        return await self._async_simple_set("Archive Directory", value)

    async def async_set_initial_url(self, value: str) -> None:
        """
        Sets the URL a web browser profile opens.

        :param value: A str
        """
        return await self._async_simple_set("Initial URL", value)

    async def async_set_browser_zoom(self, value: float) -> None:
        """
        Sets the zoom level of a web browser profile.

        100 means 100%.
        """
        return await self._async_simple_set("Browser Zoom", value)

    async def async_set_browser_dev_null(self, value: bool) -> None:
        """
        Sets whether a web browser profile uses a private data store that is
        not shared with other browser profiles.

        :param value: A bool
        """
        return await self._async_simple_set("Dev Null Mode", value)

    async def async_set_browser_width(self, value: float) -> None:
        """
        Sets the initial width of a web browser profile's window, in points.

        :param value: A float
        """
        return await self._async_simple_set("Width in Points", value)

    async def async_set_browser_height(self, value: float) -> None:
        """
        Sets the initial height of a web browser profile's window, in points.

        :param value: A float
        """
        return await self._async_simple_set("Height in Points", value)

    async def async_set_browser_instant_replay(self, value: bool) -> None:
        """
        Sets whether instant replay is enabled for a web browser profile.

        :param value: A bool
        """
        return await self._async_simple_set("Instant Replay", value)


class Profile(WriteOnlyProfile):
    """Represents a profile.

    If a session_id is set then this is the profile attached to a session.
    Otherwise, it is a shared profile."""

    USE_CUSTOM_COMMAND_ENABLED: str = "Yes"
    USE_CUSTOM_COMMAND_DISABLED: str = "No"

    @staticmethod
    async def async_get(
        connection: Connection, guids: Iterable[str] | None = None
    ) -> list[Profile]:
        """Fetches all profiles with the specified GUIDs.

        :param guids: The profiles to get, or if `None` then all will be
            returned.

        :returns: A list of :class:`Profile` objects.
        """
        response = await async_list_profiles(connection, guids, None)
        profiles: list[Profile] = []
        for response_profile in response.list_profiles_response.profiles:
            profile = Profile(None, connection, response_profile.properties)
            profiles.append(profile)
        return profiles

    @staticmethod
    async def async_get_default(connection: Connection) -> Profile:
        """Returns the default profile."""
        check_supports_get_default_profile(connection)
        result = await async_get_default_profile(connection)
        guid = result.preferences_response.results[0].get_default_profile_result.guid
        profiles = await Profile.async_get(connection, [guid])
        return profiles[0]

    def __init__(
        self,
        session_id: str | None,
        connection: Connection,
        profile_property_list: Iterable[ProfileProperty],
    ) -> None:
        props: dict[str, Any] = {}
        for prop in profile_property_list:
            props[prop.key] = json.loads(prop.json_value)

        guid_key = "Guid"
        guid = props.get(guid_key, None)

        super().__init__(session_id, connection, guid)

        self.connection: Connection = connection
        self.session_id: str | None = session_id
        self.__props = props

    def _simple_get(self, key: str) -> Any:
        """Returns the JSON-decoded value for key, or None if it is absent."""
        if key in self.__props:
            return self.__props[key]
        return None

    def _get_optional_bool(self, key: str) -> bool | None:
        if key not in self.__props:
            return None
        return bool(self.__props[key])

    def get_color_with_key(self, key: str) -> Color | None:
        """Returns the color for the request key, or None.

        :param key: A string describing the color. Corresponds to the keys in
            :class:`~iterm2.ColorPreset.Color`.

        :returns: Either a :class:`~iterm2.color.Color` or `None`.
        """
        try:
            color = Color()
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
    def all_properties(self) -> dict[str, Any]:
        """Returns the internal dictionary value."""
        return dict(self.__props)

    @property
    def title_components(self) -> list[TitleComponents] | None:
        """
        Returns which components are visible in the session's title, or selects
        a custom component.

        If it is set to `CUSTOM` then the title_function must be set properly.

        :returns: A list of :class:`TitleComponents`, or `None` if not set.
        """
        value = self._simple_get("Title Components")
        if value is None:
            return None
        parts: list[TitleComponents] = []
        bit = 1
        while bit <= value:
            if bit & value:
                parts.append(TitleComponents(bit))
            bit *= 2
        return parts

    @property
    def title_function(self) -> tuple[str, str] | None:
        """
        Returns the function call for the session title provider and its
        display name for the UI.

        :returns: (display name, unique identifier), or `None` if not set.
        """
        values = self._simple_get("Title Function")
        if values is None:
            return None
        return (values[0], values[1])

    async def async_make_default(self) -> None:
        """Makes this profile the default profile.

        Raises BadGUIDException if the Guid is not set.
        """
        guid = self.guid
        if guid is None:
            raise BadGUIDException()
        await async_set_default_profile(self.connection, guid)

    @property
    def guid(self) -> str | None:
        """Returns globally unique ID for this profile.

        :returns: A string identifying this profile, or `None` if not set (e.g.,
            a :class:`PartialProfile` that did not fetch it).
        """
        return self._simple_get("Guid")

    @property
    def original_guid(self) -> str | None:
        """The GUID of the original profile from which this one was derived.

        Used for sessions whose profile has been modified from the underlying
        profile. Otherwise not set.

        :returns: Guid, or `None` if not set.
        """
        return self._simple_get("Original Guid")

    @property
    def dynamic_profile_parent_name(self) -> str | None:
        """
        If the profile is a dynamic profile, returns the name of the parent
        profile.

        :returns: String name
        """
        return self._simple_get("Dynamic Profile Parent Name")

    @property
    def dynamic_profile_file_name(self) -> str | None:
        """If the profile is a dynamic profile, returns the path to the file
        from which it came.

        :returns: String file name
        """
        return self._simple_get("Dynamic Profile Filename")

    @property
    def use_separate_colors_for_light_and_dark_mode(self) -> bool | None:
        """
        Returns whether to use separate colors for light and dark mode.

        When this is enabled, use [set_]xxx_color_light and
        set_[xxx_]color_dark instead of [set_]xxx_color.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Separate Colors for Light and Dark Mode")

    @property
    def foreground_color(self) -> Color | None:
        """
        Returns the foreground color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Foreground Color")

    @property
    def foreground_color_light(self) -> Color | None:
        """
        Returns the foreground color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Foreground Color (Light)")

    @property
    def foreground_color_dark(self) -> Color | None:
        """
        Returns the foreground color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Foreground Color (Dark)")

    @property
    def background_color(self) -> Color | None:
        """
        Returns the background color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Background Color")

    @property
    def background_color_light(self) -> Color | None:
        """
        Returns the background color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Background Color (Light)")

    @property
    def background_color_dark(self) -> Color | None:
        """
        Returns the background color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Background Color (Dark)")

    @property
    def bold_color(self) -> Color | None:
        """
        Returns the bold text color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Bold Color")

    @property
    def bold_color_light(self) -> Color | None:
        """
        Returns the bold text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Bold Color (Light)")

    @property
    def bold_color_dark(self) -> Color | None:
        """
        Returns the bold text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Bold Color (Dark)")

    @property
    def use_bright_bold(self) -> bool | None:
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

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bright Bold")

    @property
    def use_bright_bold_light(self) -> bool | None:
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

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bright Bold (Light)")

    @property
    def use_bright_bold_dark(self) -> bool | None:
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

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bright Bold (Dark)")

    @property
    def use_bold_color(self) -> bool | None:
        """
        Returns whether the profile-specified bold color is used for
        default-colored bold text. This is used only when separate light/dark
        mode colors are not enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        use_bright_bold().

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bright Bold")

    @property
    def use_bold_color_light(self) -> bool | None:
        """
        Returns whether the profile-specified bold color is used for
        default-colored bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        use_bright_bold().

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bright Bold (Light)")

    @property
    def use_bold_color_dark(self) -> bool | None:
        """
        Returns whether the profile-specified bold color is used for
        default-colored bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        Note: In versions of iTerm2 prior to 3.3.7, this behaves like
        use_bright_bold().

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bright Bold (Dark)")

    @property
    def brighten_bold_text(self) -> bool | None:
        """
        Returns whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This is used only when separate light/dark
        mode colors are not enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :returns: A bool or `None`
        """
        return self._simple_get("Brighten Bold Text")

    @property
    def brighten_bold_text_light(self) -> bool | None:
        """
        Returns whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :returns: A bool or `None`
        """
        return self._simple_get("Brighten Bold Text (Light)")

    @property
    def brighten_bold_text_dark(self) -> bool | None:
        """
        Returns whether Dark ANSI colors get replaced with their light
        counterparts for bold text. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        This is only supported in iTerm2 version 3.3.7 and later.

        :returns: A bool or `None`
        """
        return self._simple_get("Brighten Bold Text (Dark)")

    @property
    def link_color(self) -> Color | None:
        """
        Returns the link color. This is used only when separate light/dark mode
        colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Link Color")

    @property
    def link_color_light(self) -> Color | None:
        """
        Returns the link color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Link Color (Light)")

    @property
    def link_color_dark(self) -> Color | None:
        """
        Returns the link color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Link Color (Dark)")

    @property
    def selection_color(self) -> Color | None:
        """
        Returns the selection background color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Selection Color")

    @property
    def selection_color_light(self) -> Color | None:
        """
        Returns the selection background color. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Selection Color (Light)")

    @property
    def selection_color_dark(self) -> Color | None:
        """
        Returns the selection background color. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Selection Color (Dark)")

    @property
    def selected_text_color(self) -> Color | None:
        """
        Returns the selection text color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Selected Text Color")

    @property
    def selected_text_color_light(self) -> Color | None:
        """
        Returns the selection text color. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Selected Text Color (Light)")

    @property
    def selected_text_color_dark(self) -> Color | None:
        """
        Returns the selection text color. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Selected Text Color (Dark)")

    @property
    def cursor_color(self) -> Color | None:
        """
        Returns the cursor color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Color")

    @property
    def cursor_color_light(self) -> Color | None:
        """
        Returns the cursor color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Color (Light)")

    @property
    def cursor_color_dark(self) -> Color | None:
        """
        Returns the cursor color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Color (Dark)")

    @property
    def cursor_text_color(self) -> Color | None:
        """
        Returns the cursor text color. This is used only when separate
        light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Text Color")

    @property
    def cursor_text_color_light(self) -> Color | None:
        """
        Returns the cursor text color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Text Color (Light)")

    @property
    def cursor_text_color_dark(self) -> Color | None:
        """
        Returns the cursor text color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Text Color (Dark)")

    @property
    def ansi_0_color(self) -> Color | None:
        """
        Returns the ANSI 0 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 0 Color")

    @property
    def ansi_0_color_light(self) -> Color | None:
        """
        Returns the ANSI 0 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 0 Color (Light)")

    @property
    def ansi_0_color_dark(self) -> Color | None:
        """
        Returns the ANSI 0 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 0 Color (Dark)")

    @property
    def ansi_1_color(self) -> Color | None:
        """
        Returns the ANSI 1 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 1 Color")

    @property
    def ansi_1_color_light(self) -> Color | None:
        """
        Returns the ANSI 1 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 1 Color (Light)")

    @property
    def ansi_1_color_dark(self) -> Color | None:
        """
        Returns the ANSI 1 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 1 Color (Dark)")

    @property
    def ansi_2_color(self) -> Color | None:
        """
        Returns the ANSI 2 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 2 Color")

    @property
    def ansi_2_color_light(self) -> Color | None:
        """
        Returns the ANSI 2 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 2 Color (Light)")

    @property
    def ansi_2_color_dark(self) -> Color | None:
        """
        Returns the ANSI 2 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 2 Color (Dark)")

    @property
    def ansi_3_color(self) -> Color | None:
        """
        Returns the ANSI 3 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 3 Color")

    @property
    def ansi_3_color_light(self) -> Color | None:
        """
        Returns the ANSI 3 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 3 Color (Light)")

    @property
    def ansi_3_color_dark(self) -> Color | None:
        """
        Returns the ANSI 3 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 3 Color (Dark)")

    @property
    def ansi_4_color(self) -> Color | None:
        """
        Returns the ANSI 4 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 4 Color")

    @property
    def ansi_4_color_light(self) -> Color | None:
        """
        Returns the ANSI 4 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 4 Color (Light)")

    @property
    def ansi_4_color_dark(self) -> Color | None:
        """
        Returns the ANSI 4 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 4 Color (Dark)")

    @property
    def ansi_5_color(self) -> Color | None:
        """
        Returns the ANSI 5 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 5 Color")

    @property
    def ansi_5_color_light(self) -> Color | None:
        """
        Returns the ANSI 5 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 5 Color (Light)")

    @property
    def ansi_5_color_dark(self) -> Color | None:
        """
        Returns the ANSI 5 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 5 Color (Dark)")

    @property
    def ansi_6_color(self) -> Color | None:
        """
        Returns the ANSI 6 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 6 Color")

    @property
    def ansi_6_color_light(self) -> Color | None:
        """
        Returns the ANSI 6 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 6 Color (Light)")

    @property
    def ansi_6_color_dark(self) -> Color | None:
        """
        Returns the ANSI 6 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 6 Color (Dark)")

    @property
    def ansi_7_color(self) -> Color | None:
        """
        Returns the ANSI 7 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 7 Color")

    @property
    def ansi_7_color_light(self) -> Color | None:
        """
        Returns the ANSI 7 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 7 Color (Light)")

    @property
    def ansi_7_color_dark(self) -> Color | None:
        """
        Returns the ANSI 7 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 7 Color (Dark)")

    @property
    def ansi_8_color(self) -> Color | None:
        """
        Returns the ANSI 8 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 8 Color")

    @property
    def ansi_8_color_light(self) -> Color | None:
        """
        Returns the ANSI 8 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 8 Color (Light)")

    @property
    def ansi_8_color_dark(self) -> Color | None:
        """
        Returns the ANSI 8 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 8 Color (Dark)")

    @property
    def ansi_9_color(self) -> Color | None:
        """
        Returns the ANSI 9 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 9 Color")

    @property
    def ansi_9_color_light(self) -> Color | None:
        """
        Returns the ANSI 9 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 9 Color (Light)")

    @property
    def ansi_9_color_dark(self) -> Color | None:
        """
        Returns the ANSI 9 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 9 Color (Dark)")

    @property
    def ansi_10_color(self) -> Color | None:
        """
        Returns the ANSI 10 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 10 Color")

    @property
    def ansi_10_color_light(self) -> Color | None:
        """
        Returns the ANSI 10 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 10 Color (Light)")

    @property
    def ansi_10_color_dark(self) -> Color | None:
        """
        Returns the ANSI 10 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 10 Color (Dark)")

    @property
    def ansi_11_color(self) -> Color | None:
        """
        Returns the ANSI 11 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 11 Color")

    @property
    def ansi_11_color_light(self) -> Color | None:
        """
        Returns the ANSI 11 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 11 Color (Light)")

    @property
    def ansi_11_color_dark(self) -> Color | None:
        """
        Returns the ANSI 11 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 11 Color (Dark)")

    @property
    def ansi_12_color(self) -> Color | None:
        """
        Returns the ANSI 12 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 12 Color")

    @property
    def ansi_12_color_light(self) -> Color | None:
        """
        Returns the ANSI 12 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 12 Color (Light)")

    @property
    def ansi_12_color_dark(self) -> Color | None:
        """
        Returns the ANSI 12 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 12 Color (Dark)")

    @property
    def ansi_13_color(self) -> Color | None:
        """
        Returns the ANSI 13 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 13 Color")

    @property
    def ansi_13_color_light(self) -> Color | None:
        """
        Returns the ANSI 13 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 13 Color (Light)")

    @property
    def ansi_13_color_dark(self) -> Color | None:
        """
        Returns the ANSI 13 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 13 Color (Dark)")

    @property
    def ansi_14_color(self) -> Color | None:
        """
        Returns the ANSI 14 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 14 Color")

    @property
    def ansi_14_color_light(self) -> Color | None:
        """
        Returns the ANSI 14 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 14 Color (Light)")

    @property
    def ansi_14_color_dark(self) -> Color | None:
        """
        Returns the ANSI 14 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 14 Color (Dark)")

    @property
    def ansi_15_color(self) -> Color | None:
        """
        Returns the ANSI 15 color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 15 Color")

    @property
    def ansi_15_color_light(self) -> Color | None:
        """
        Returns the ANSI 15 color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 15 Color (Light)")

    @property
    def ansi_15_color_dark(self) -> Color | None:
        """
        Returns the ANSI 15 color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Ansi 15 Color (Dark)")

    @property
    def smart_cursor_color(self) -> bool | None:
        """
        Returns whether to use smart cursor color. This only applies to box
        cursors. This is used only when separate light/dark mode colors are not
        enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Smart Cursor Color")

    @property
    def smart_cursor_color_light(self) -> bool | None:
        """
        Returns whether to use smart cursor color. This only applies to box
        cursors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Smart Cursor Color (Light)")

    @property
    def smart_cursor_color_dark(self) -> bool | None:
        """
        Returns whether to use smart cursor color. This only applies to box
        cursors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Smart Cursor Color (Dark)")

    @property
    def minimum_contrast(self) -> float | None:
        """
        Returns the minimum contrast, in 0 to 1. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A float or `None`
        """
        return self._simple_get("Minimum Contrast")

    @property
    def minimum_contrast_light(self) -> float | None:
        """
        Returns the minimum contrast, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float or `None`
        """
        return self._simple_get("Minimum Contrast (Light)")

    @property
    def minimum_contrast_dark(self) -> float | None:
        """
        Returns the minimum contrast, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float or `None`
        """
        return self._simple_get("Minimum Contrast (Dark)")

    @property
    def tab_color(self) -> Color | None:
        """
        Returns the tab color. This is used only when separate light/dark mode
        colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Tab Color")

    @property
    def tab_color_light(self) -> Color | None:
        """
        Returns the tab color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Tab Color (Light)")

    @property
    def tab_color_dark(self) -> Color | None:
        """
        Returns the tab color. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Tab Color (Dark)")

    @property
    def use_tab_color(self) -> bool | None:
        """
        Returns whether the tab color should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Tab Color")

    @property
    def use_tab_color_light(self) -> bool | None:
        """
        Returns whether the tab color should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Tab Color (Light)")

    @property
    def use_tab_color_dark(self) -> bool | None:
        """
        Returns whether the tab color should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Tab Color (Dark)")

    @property
    def underline_color(self) -> Color | None:
        """
        Returns the underline color. This is used only when separate light/dark
        mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Underline Color")

    @property
    def underline_color_light(self) -> Color | None:
        """
        Returns the underline color. This affects the light-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Underline Color (Light)")

    @property
    def underline_color_dark(self) -> Color | None:
        """
        Returns the underline color. This affects the dark-mode variant when
        separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Underline Color (Dark)")

    @property
    def use_underline_color(self) -> bool | None:
        """
        Returns whether to use the specified underline color. This is used only
        when separate light/dark mode colors are not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Underline Color")

    @property
    def use_underline_color_light(self) -> bool | None:
        """
        Returns whether to use the specified underline color. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Underline Color (Light)")

    @property
    def use_underline_color_dark(self) -> bool | None:
        """
        Returns whether to use the specified underline color. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Underline Color (Dark)")

    @property
    def cursor_boost(self) -> float | None:
        """
        Returns the cursor boost level, in 0 to 1. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Boost")

    @property
    def cursor_boost_light(self) -> float | None:
        """
        Returns the cursor boost level, in 0 to 1. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Boost (Light)")

    @property
    def cursor_boost_dark(self) -> float | None:
        """
        Returns the cursor boost level, in 0 to 1. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Boost (Dark)")

    @property
    def use_cursor_guide(self) -> bool | None:
        """
        Returns whether the cursor guide should be used. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Cursor Guide")

    @property
    def use_cursor_guide_light(self) -> bool | None:
        """
        Returns whether the cursor guide should be used. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Cursor Guide (Light)")

    @property
    def use_cursor_guide_dark(self) -> bool | None:
        """
        Returns whether the cursor guide should be used. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Cursor Guide (Dark)")

    @property
    def cursor_guide_color(self) -> Color | None:
        """
        Returns the cursor guide color. The alpha value is respected. This is
        used only when separate light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Guide Color")

    @property
    def cursor_guide_color_light(self) -> Color | None:
        """
        Returns the cursor guide color. The alpha value is respected. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Guide Color (Light)")

    @property
    def cursor_guide_color_dark(self) -> Color | None:
        """
        Returns the cursor guide color. The alpha value is respected. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Cursor Guide Color (Dark)")

    @property
    def badge_color(self) -> Color | None:
        """
        Returns the badge color. The alpha value is respected. This is used
        only when separate light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Badge Color")

    @property
    def badge_color_light(self) -> Color | None:
        """
        Returns the badge color. The alpha value is respected. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Badge Color (Light)")

    @property
    def badge_color_dark(self) -> Color | None:
        """
        Returns the badge color. The alpha value is respected. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Badge Color (Dark)")

    @property
    def match_color(self) -> Color | None:
        """
        Returns the highlight color for search matches. This is used only when
        separate light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Match Background Color")

    @property
    def match_color_light(self) -> Color | None:
        """
        Returns the highlight color for search matches. This affects the
        light-mode variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Match Background Color (Light)")

    @property
    def match_color_dark(self) -> Color | None:
        """
        Returns the highlight color for search matches. This affects the
        dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Match Background Color (Dark)")

    @property
    def ime_cursor_color(self) -> Color | None:
        """
        Returns the cursor color while composing text with an input method.
        This is used only when separate light/dark mode colors are not enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("IME Cursor Color")

    @property
    def ime_cursor_color_light(self) -> Color | None:
        """
        Returns the cursor color while composing text with an input method.
        This affects the light-mode variant when separate light/dark mode
        colors are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("IME Cursor Color (Light)")

    @property
    def ime_cursor_color_dark(self) -> Color | None:
        """
        Returns the cursor color while composing text with an input method.
        This affects the dark-mode variant when separate light/dark mode colors
        are enabled.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("IME Cursor Color (Dark)")

    @property
    def use_selected_text_color(self) -> bool | None:
        """
        Returns whether selected text is drawn in the selected text color. This
        is used only when separate light/dark mode colors are not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Selected Text Color")

    @property
    def use_selected_text_color_light(self) -> bool | None:
        """
        Returns whether selected text is drawn in the selected text color. This
        affects the light-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Selected Text Color (Light)")

    @property
    def use_selected_text_color_dark(self) -> bool | None:
        """
        Returns whether selected text is drawn in the selected text color. This
        affects the dark-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Selected Text Color (Dark)")

    @property
    def active_pane_border_color(self) -> Color | None:
        """
        Returns the color of the border around the active pane. This is used
        only when separate light/dark mode colors are not enabled.

        This is used only when use_active_pane_border is True.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Active Pane Border Color")

    @property
    def active_pane_border_color_light(self) -> Color | None:
        """
        Returns the color of the border around the active pane. This affects
        the light-mode variant when separate light/dark mode colors are
        enabled.

        This is used only when use_active_pane_border is True.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Active Pane Border Color (Light)")

    @property
    def active_pane_border_color_dark(self) -> Color | None:
        """
        Returns the color of the border around the active pane. This affects
        the dark-mode variant when separate light/dark mode colors are enabled.

        This is used only when use_active_pane_border is True.

        :returns: A :class:`Color` or `None`
        """
        return self.get_color_with_key("Active Pane Border Color (Dark)")

    @property
    def use_active_pane_border(self) -> bool | None:
        """
        Returns whether to draw a border around the active pane. This is used
        only when separate light/dark mode colors are not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Active Pane Border")

    @property
    def use_active_pane_border_light(self) -> bool | None:
        """
        Returns whether to draw a border around the active pane. This affects
        the light-mode variant when separate light/dark mode colors are
        enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Active Pane Border (Light)")

    @property
    def use_active_pane_border_dark(self) -> bool | None:
        """
        Returns whether to draw a border around the active pane. This affects
        the dark-mode variant when separate light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Active Pane Border (Dark)")

    @property
    def faint_text_alpha(self) -> float | None:
        """
        Returns the opacity of faint text. This is used only when separate
        light/dark mode colors are not enabled.

        The value is between 0 and 1.

        :returns: A float or `None`
        """
        return self._simple_get("Faint Text Alpha")

    @property
    def faint_text_alpha_light(self) -> float | None:
        """
        Returns the opacity of faint text. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        The value is between 0 and 1.

        :returns: A float or `None`
        """
        return self._simple_get("Faint Text Alpha (Light)")

    @property
    def faint_text_alpha_dark(self) -> float | None:
        """
        Returns the opacity of faint text. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        The value is between 0 and 1.

        :returns: A float or `None`
        """
        return self._simple_get("Faint Text Alpha (Dark)")

    @property
    def harmonize_256_colors(self) -> bool | None:
        """
        Returns whether the 256-color palette is adjusted to match the ANSI
        colors. This is used only when separate light/dark mode colors are not
        enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Harmonize 256 Colors")

    @property
    def harmonize_256_colors_light(self) -> bool | None:
        """
        Returns whether the 256-color palette is adjusted to match the ANSI
        colors. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Harmonize 256 Colors (Light)")

    @property
    def harmonize_256_colors_dark(self) -> bool | None:
        """
        Returns whether the 256-color palette is adjusted to match the ANSI
        colors. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Harmonize 256 Colors (Dark)")

    @property
    def hdr_cursor(self) -> bool | None:
        """
        Returns whether the cursor is drawn brighter than white on HDR
        displays. This is used only when separate light/dark mode colors are
        not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("HDR Cursor")

    @property
    def hdr_cursor_light(self) -> bool | None:
        """
        Returns whether the cursor is drawn brighter than white on HDR
        displays. This affects the light-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("HDR Cursor (Light)")

    @property
    def hdr_cursor_dark(self) -> bool | None:
        """
        Returns whether the cursor is drawn brighter than white on HDR
        displays. This affects the dark-mode variant when separate light/dark
        mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("HDR Cursor (Dark)")

    @property
    def hdr_cursor_brightness(self) -> float | None:
        """
        Returns the brightness of the HDR cursor. This is used only when
        separate light/dark mode colors are not enabled.

        The value is a multiple of reference white, at most 16.

        :returns: A float or `None`
        """
        return self._simple_get("HDR Cursor Brightness")

    @property
    def hdr_cursor_brightness_light(self) -> float | None:
        """
        Returns the brightness of the HDR cursor. This affects the light-mode
        variant when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, at most 16.

        :returns: A float or `None`
        """
        return self._simple_get("HDR Cursor Brightness (Light)")

    @property
    def hdr_cursor_brightness_dark(self) -> float | None:
        """
        Returns the brightness of the HDR cursor. This affects the dark-mode
        variant when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, at most 16.

        :returns: A float or `None`
        """
        return self._simple_get("HDR Cursor Brightness (Dark)")

    @property
    def hdr_text(self) -> bool | None:
        """
        Returns whether the focused pane's text is drawn brighter than white on
        HDR displays. This is used only when separate light/dark mode colors
        are not enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("HDR Text")

    @property
    def hdr_text_light(self) -> bool | None:
        """
        Returns whether the focused pane's text is drawn brighter than white on
        HDR displays. This affects the light-mode variant when separate
        light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("HDR Text (Light)")

    @property
    def hdr_text_dark(self) -> bool | None:
        """
        Returns whether the focused pane's text is drawn brighter than white on
        HDR displays. This affects the dark-mode variant when separate
        light/dark mode colors are enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("HDR Text (Dark)")

    @property
    def hdr_text_brightness(self) -> float | None:
        """
        Returns the brightness of HDR text. This is used only when separate
        light/dark mode colors are not enabled.

        The value is a multiple of reference white, from 1.5 to 16.

        :returns: A float or `None`
        """
        return self._simple_get("HDR Text Brightness")

    @property
    def hdr_text_brightness_light(self) -> float | None:
        """
        Returns the brightness of HDR text. This affects the light-mode variant
        when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, from 1.5 to 16.

        :returns: A float or `None`
        """
        return self._simple_get("HDR Text Brightness (Light)")

    @property
    def hdr_text_brightness_dark(self) -> float | None:
        """
        Returns the brightness of HDR text. This affects the dark-mode variant
        when separate light/dark mode colors are enabled.

        The value is a multiple of reference white, from 1.5 to 16.

        :returns: A float or `None`
        """
        return self._simple_get("HDR Text Brightness (Dark)")

    @property
    def name(self) -> str | None:
        """
        Returns the name.

        :returns: A str or `None`
        """
        return self._simple_get("Name")

    @property
    def badge_text(self) -> str | None:
        """
        Returns the badge text.

        :returns: A str or `None`
        """
        return self._simple_get("Badge Text")

    @property
    def subtitle(self) -> str | None:
        """
        Returns the subtitle, an interpolated string.

        :returns: A str or `None`
        """
        return self._simple_get("Subtitle")

    @property
    def answerback_string(self) -> str | None:
        """
        Returns the answerback string.

        :returns: A str or `None`
        """
        return self._simple_get("Answerback String")

    @property
    def blinking_cursor(self) -> bool | None:
        """
        Returns whether the cursor blinks.

        :returns: A bool or `None`
        """
        return self._simple_get("Blinking Cursor")

    @property
    def cursor_shadow(self) -> bool | None:
        """
        Returns whether the vertical bar and horizontal line cursor have a
        shadow.

        :returns: A bool or `None`
        """
        return self._simple_get("Cursor Shadow")

    @property
    def use_bold_font(self) -> bool | None:
        """
        Returns whether to use the bold variant of the font for bold text.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Bold Font")

    @property
    def ascii_ligatures(self) -> bool | None:
        """
        Returns whether ligatures should be used for ASCII text.

        :returns: A bool or `None`
        """
        return self._simple_get("ASCII Ligatures")

    @property
    def non_ascii_ligatures(self) -> bool | None:
        """
        Returns whether ligatures should be used for non-ASCII text.

        :returns: A bool or `None`
        """
        return self._simple_get("Non-ASCII Ligatures")

    @property
    def blink_allowed(self) -> bool | None:
        """
        Returns whether blinking text is allowed.

        :returns: A bool or `None`
        """
        return self._simple_get("Blink Allowed")

    @property
    def use_italic_font(self) -> bool | None:
        """
        Returns whether italic text is allowed.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Italic Font")

    @property
    def ambiguous_double_width(self) -> bool | None:
        """
        Returns whether ambiguous-width text should be treated as double-width.

        :returns: A bool or `None`
        """
        return self._simple_get("Ambiguous Double Width")

    @property
    def horizontal_spacing(self) -> float | None:
        """
        Returns the fraction of horizontal spacing. Must be non-negative.

        :returns: A float or `None`
        """
        return self._simple_get("Horizontal Spacing")

    @property
    def vertical_spacing(self) -> float | None:
        """
        Returns the fraction of vertical spacing. Must be non-negative.

        :returns: A float or `None`
        """
        return self._simple_get("Vertical Spacing")

    @property
    def use_non_ascii_font(self) -> bool | None:
        """
        Returns whether to use a different font for non-ASCII text.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Non-ASCII Font")

    @property
    def transparency(self) -> float | None:
        """
        Returns the level of transparency.

        The value is between 0 and 1.

        :returns: A float or `None`
        """
        return self._simple_get("Transparency")

    @property
    def blur(self) -> bool | None:
        """
        Returns whether background blur should be enabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Blur")

    @property
    def blur_radius(self) -> float | None:
        """
        Returns the blur radius (how blurry). Requires blur to be enabled.

        The value is between 0 and 30.

        :returns: A float or `None`
        """
        return self._simple_get("Blur Radius")

    @property
    def background_image_mode(self) -> BackgroundImageMode | None:
        """
        Returns how the background image is drawn.

        :returns: A `BackgroundImageMode` or `None`
        """
        value = self._simple_get("Background Image Mode")
        if value is None:
            return None
        return BackgroundImageMode(value)

    @property
    def blend(self) -> float | None:
        """
        Returns how much the default background color gets blended with the
        background image.

        The value is in 0 to 1.

        .. seealso:: Example ":ref:`blending_example`

        :returns: A float or `None`
        """
        return self._simple_get("Blend")

    @property
    def sync_title(self) -> bool | None:
        """
        Returns whether the profile name stays in the tab title, even if
        changed by an escape sequence.

        :returns: A bool or `None`
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
    def disable_window_resizing(self) -> bool | None:
        """
        Returns whether the terminal can resize the window with an escape
        sequence.

        :returns: A bool or `None`
        """
        return self._simple_get("Disable Window Resizing")

    @property
    def allow_change_cursor_blink(self) -> bool | None:
        """
        Returns whether the terminal can change the cursor blink setting with
        an escape sequence.

        :returns: A bool or `None`
        """
        return self._simple_get("Allow Change Cursor Blink")

    @property
    def only_the_default_bg_color_uses_transparency(self) -> bool | None:
        """
        Returns whether window transparency shows through non-default
        background colors.

        :returns: A bool or `None`
        """
        return self._simple_get("Only The Default BG Color Uses Transparency")

    @property
    def ascii_anti_aliased(self) -> bool | None:
        """
        Returns whether ASCII text is anti-aliased.

        :returns: A bool or `None`
        """
        return self._simple_get("ASCII Anti Aliased")

    @property
    def non_ascii_anti_aliased(self) -> bool | None:
        """
        Returns whether non-ASCII text is anti-aliased.

        :returns: A bool or `None`
        """
        return self._simple_get("Non-ASCII Anti Aliased")

    @property
    def scrollback_lines(self) -> int | None:
        """
        Returns the number of scrollback lines.

        Value must be at least 0.

        :returns: An int or `None`
        """
        return self._simple_get("Scrollback Lines")

    @property
    def unlimited_scrollback(self) -> bool | None:
        """
        Returns whether the scrollback buffer's length is unlimited.

        :returns: A bool or `None`
        """
        return self._simple_get("Unlimited Scrollback")

    @property
    def scrollback_with_status_bar(self) -> bool | None:
        """
        Returns whether text gets appended to scrollback when there is an app
        status bar

        :returns: A bool or `None`
        """
        return self._simple_get("Scrollback With Status Bar")

    @property
    def scrollback_in_alternate_screen(self) -> bool | None:
        """
        Returns whether text gets appended to scrollback in alternate screen
        mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Scrollback in Alternate Screen")

    @property
    def mouse_reporting(self) -> bool | None:
        """
        Returns whether mouse reporting is allowed

        :returns: A bool or `None`
        """
        return self._simple_get("Mouse Reporting")

    @property
    def mouse_reporting_allow_mouse_wheel(self) -> bool | None:
        """
        Returns whether mouse reporting reports the mouse wheel's movements.

        :returns: A bool or `None`
        """
        return self._simple_get("Mouse Reporting allow mouse wheel")

    @property
    def allow_title_reporting(self) -> bool | None:
        """
        Returns whether the session title can be reported

        :returns: A bool or `None`
        """
        return self._simple_get("Allow Title Reporting")

    @property
    def allow_title_setting(self) -> bool | None:
        """
        Returns whether the session title can be changed by escape sequence

        :returns: A bool or `None`
        """
        return self._simple_get("Allow Title Setting")

    @property
    def disable_printing(self) -> bool | None:
        """
        Returns whether printing by escape sequence is disabled.

        :returns: A bool or `None`
        """
        return self._simple_get("Disable Printing")

    @property
    def disable_smcup_rmcup(self) -> bool | None:
        """
        Returns whether alternate screen mode is disabled

        :returns: A bool or `None`
        """
        return self._simple_get("Disable Smcup Rmcup")

    @property
    def silence_bell(self) -> bool | None:
        """
        Returns whether the bell makes noise.

        :returns: A bool or `None`
        """
        return self._simple_get("Silence Bell")

    @property
    def bm_growl(self) -> bool | None:
        """
        Returns whether notifications should be shown.

        :returns: A bool or `None`
        """
        return self._simple_get("BM Growl")

    @property
    def send_bell_alert(self) -> bool | None:
        """
        Returns whether notifications should be shown for the bell ringing

        :returns: A bool or `None`
        """
        return self._simple_get("Send Bell Alert")

    @property
    def send_idle_alert(self) -> bool | None:
        """
        Returns whether notifications should be shown for becoming idle

        :returns: A bool or `None`
        """
        return self._simple_get("Send Idle Alert")

    @property
    def send_new_output_alert(self) -> bool | None:
        """
        Returns whether notifications should be shown for new output

        :returns: A bool or `None`
        """
        return self._simple_get("Send New Output Alert")

    @property
    def send_session_ended_alert(self) -> bool | None:
        """
        Returns whether notifications should be shown for a session ending

        :returns: A bool or `None`
        """
        return self._simple_get("Send Session Ended Alert")

    @property
    def send_terminal_generated_alerts(self) -> bool | None:
        """
        Returns whether notifications should be shown for escape-sequence
        originated notifications

        :returns: A bool or `None`
        """
        return self._simple_get("Send Terminal Generated Alerts")

    @property
    def flashing_bell(self) -> bool | None:
        """
        Returns whether the bell should flash the screen

        :returns: A bool or `None`
        """
        return self._simple_get("Flashing Bell")

    @property
    def visual_bell(self) -> bool | None:
        """
        Returns whether a bell should be shown when the bell rings

        :returns: A bool or `None`
        """
        return self._simple_get("Visual Bell")

    @property
    def close_sessions_on_end(self) -> bool | None:
        """
        Returns whether the session should close when it ends.

        :returns: A bool or `None`
        """
        return self._simple_get("Close Sessions On End")

    @property
    def prompt_before_closing(self) -> bool | None:
        """
        Returns whether the session should prompt before closing.

        :returns: A bool or `None`
        """
        return self._simple_get("Prompt Before Closing 2")

    @property
    def session_close_undo_timeout(self) -> float | None:
        """
        Returns the amount of time you can undo closing a session

        The value is at least 0.

        :returns: A float or `None`
        """
        return self._simple_get("Session Close Undo Timeout")

    @property
    def reduce_flicker(self) -> bool | None:
        """
        Returns whether the flicker fixer is on.

        :returns: A bool or `None`
        """
        return self._simple_get("Reduce Flicker")

    @property
    def send_code_when_idle(self) -> bool | None:
        """
        Returns whether to send a code when idle

        :returns: A bool or `None`
        """
        return self._simple_get("Send Code When Idle")

    @property
    def application_keypad_allowed(self) -> bool | None:
        """
        Returns whether the terminal may be placed in application keypad mode

        :returns: A bool or `None`
        """
        return self._simple_get("Application Keypad Allowed")

    @property
    def place_prompt_at_first_column(self) -> bool | None:
        """
        Returns whether the prompt should always begin at the first column
        (requires shell integration)

        :returns: A bool or `None`
        """
        return self._simple_get("Place Prompt at First Column")

    @property
    def show_mark_indicators(self) -> bool | None:
        """
        Returns whether mark indicators should be visible

        :returns: A bool or `None`
        """
        return self._simple_get("Show Mark Indicators")

    @property
    def idle_code(self) -> int | None:
        """
        Returns the ASCII code to send on idle

        Value is an int in 0 through 255.

        :returns: An int or `None`
        """
        return self._simple_get("Idle Code")

    @property
    def idle_period(self) -> float | None:
        """
        Returns how often to send a code when idle

        Value is a float at least 0

        :returns: A float or `None`
        """
        return self._simple_get("Idle Period")

    @property
    def unicode_version(self) -> bool | None:
        """
        Returns the unicode version for wcwidth

        :returns: A bool or `None`
        """
        return self._simple_get("Unicode Version")

    @property
    def cursor_type(self) -> int | None:
        """
        Returns the cursor type

        :returns: A CursorType or `None`
        """
        return self._simple_get("Cursor Type")

    @property
    def thin_strokes(self) -> int | None:
        """
        Returns whether thin strokes are used.

        :returns: A ThinStrokes or `None`
        """
        return self._simple_get("Thin Strokes")

    @property
    def unicode_normalization(self) -> int | None:
        """
        Returns the unicode normalization form to use

        :returns: An UnicodeNormalization or `None`
        """
        return self._simple_get("Unicode Normalization")

    @property
    def character_encoding(self) -> int | None:
        """
        Returns the character encoding

        :returns: A CharacterEncoding or `None`
        """
        return self._simple_get("Character Encoding")

    @property
    def left_option_key_sends(self) -> int | None:
        """
        Returns the behavior of the left option key.

        :returns: An OptionKeySends or `None`
        """
        return self._simple_get("Option Key Sends")

    @property
    def right_option_key_sends(self) -> int | None:
        """
        Returns the behavior of the right option key.

        :returns: An OptionKeySends or `None`
        """
        return self._simple_get("Right Option Key Sends")

    @property
    def triggers(self) -> list[dict[str, Any]] | None:
        """
        Returns the triggers.

        Value is an encoded trigger. Use iterm2.decode_trigger to convert from
        an encoded trigger to an object. Trigger objects can be encoded using
        the encode property.

        :returns: A list[dict[str, Any]] or `None`
        """
        return self._simple_get("Triggers")

    @property
    def smart_selection_rules(self) -> list[dict[str, Any]] | None:
        """
        Returns the smart selection rules.

        The value is a list of dicts of smart selection rules (currently
        undocumented)

        :returns: A list[dict[str, Any]] or `None`
        """
        return self._simple_get("Smart Selection Rules")

    @property
    def smart_selection_actions_use_interpolated_strings(self) -> bool | None:
        """
        Returns whether smart selection action parameters are interpolated
        strings.

        Should smart selection actions' parameters be treated as interpolated
        strings? If false, use the backward-compatibility syntax.

        :returns: A bool or `None`
        """
        return self._simple_get("Smart Selection Actions Use Interpolated Strings")

    @property
    def semantic_history(self) -> dict[str, Any] | None:
        """
        Returns the semantic history prefs.

        :returns: A dict[str, Any] or `None`
        """
        return self._simple_get("Semantic History")

    @property
    def automatic_profile_switching_rules(self) -> list[str] | None:
        """
        Returns the automatic profile switching rules.

        Value is a list of strings, each giving a rule.

        :returns: A list[str] or `None`
        """
        return self._simple_get("Bound Hosts")

    @property
    def advanced_working_directory_window_setting(self) -> str | None:
        """
        Returns the advanced working directory window setting.

        Value excludes Advanced.

        :returns: An InitialWorkingDirectory or `None`
        """
        return self._simple_get("AWDS Window Option")

    @property
    def advanced_working_directory_window_directory(self) -> str | None:
        """
        Returns the advanced working directory window directory.

        :returns: A str or `None`
        """
        return self._simple_get("AWDS Window Directory")

    @property
    def advanced_working_directory_tab_setting(self) -> str | None:
        """
        Returns the advanced working directory tab setting.

        Value excludes Advanced.

        :returns: An InitialWorkingDirectory or `None`
        """
        return self._simple_get("AWDS Tab Option")

    @property
    def advanced_working_directory_tab_directory(self) -> str | None:
        """
        Returns the advanced working directory tab directory.

        :returns: A str or `None`
        """
        return self._simple_get("AWDS Tab Directory")

    @property
    def advanced_working_directory_pane_setting(self) -> str | None:
        """
        Returns the advanced working directory pane setting.

        Value excludes Advanced.

        :returns: An InitialWorkingDirectory or `None`
        """
        return self._simple_get("AWDS Pane Option")

    @property
    def advanced_working_directory_pane_directory(self) -> str | None:
        """
        Returns the advanced working directory pane directory.

        :returns: A str or `None`
        """
        return self._simple_get("AWDS Pane Directory")

    @property
    def normal_font(self) -> str | None:
        """
        Returns the normal font.

        The normal font is used for either ASCII or all characters depending on
        whether a separate font is used for non-ascii. The value is a font's
        name and size as a string.

        .. seealso::
          * Example ":ref:`increase_font_size_example`"

        :returns: A str or `None`
        """
        return self._simple_get("Normal Font")

    @property
    def non_ascii_font(self) -> str | None:
        """
        Returns the non-ASCII font.

        This is used for non-ASCII characters if use_non_ascii_font is enabled.
        The value is the font name and size as a string.

        :returns: A str or `None`
        """
        return self._simple_get("Non Ascii Font")

    @property
    def background_image_location(self) -> str | None:
        """
        Returns the path to the background image.

        :returns: A str or `None`
        """
        return self._simple_get("Background Image Location")

    @property
    def key_mappings(self) -> dict[str, Any] | None:
        """
        Returns the keyboard shortcuts.

        The value is a Dictionary mapping keystroke to action. You can convert
        between the values in this dictionary and a :class:`~iterm2.KeyBinding`
        using `iterm2.decode_key_binding`

        :returns: A dict[str, Any] or `None`
        """
        return self._simple_get("Keyboard Map")

    @property
    def touchbar_mappings(self) -> dict[str, Any] | None:
        """
        Returns the touchbar actions.

        The value is a Dictionary mapping touch bar item to action

        :returns: A dict[str, Any] or `None`
        """
        return self._simple_get("Touch Bar Map")

    @property
    def use_custom_command(self) -> str | None:
        """
        Returns whether to use a custom command when the session is created.

        The value is the string Yes or No

        :returns: A str or `None`
        """
        return self._simple_get("Custom Command")

    @property
    def command(self) -> str | None:
        """
        Returns the command to run when the session starts.

        The value is a string giving the command to run

        :returns: A str or `None`
        """
        return self._simple_get("Command")

    @property
    def initial_directory_mode(self) -> str | None:
        """
        Returns whether to use a custom (not home) initial working directory.

        :returns: An InitialWorkingDirectory or `None`
        """
        return self._simple_get("Custom Directory")

    @property
    def custom_directory(self) -> str | None:
        """
        Returns the initial working directory.

        The initial_directory_mode must be set to
        `InitialWorkingDirectory.INITIAL_WORKING_DIRECTORY_CUSTOM` for this to
        take effect.

        :returns: A str or `None`
        """
        return self._simple_get("Working Directory")

    @property
    def icon_mode(self) -> int | None:
        """
        Returns the icon mode.

        :returns: An IconMode or `None`
        """
        return self._simple_get("Icon")

    @property
    def custom_icon_path(self) -> str | None:
        """
        Returns the path of the custom icon.

        The `icon_mode` must be set to `CUSTOM`.

        :returns: A str or `None`
        """
        return self._simple_get("Custom Icon Path")

    @property
    def badge_top_margin(self) -> int | None:
        """
        Returns the top margin of the badge.

        The value is in points.

        :returns: An int or `None`
        """
        return self._simple_get("Badge Top Margin")

    @property
    def badge_right_margin(self) -> int | None:
        """
        Returns the right margin of the badge.

        The value is in points.

        :returns: An int or `None`
        """
        return self._simple_get("Badge Right Margin")

    @property
    def badge_max_width(self) -> int | None:
        """
        Returns the max width of the badge.

        The value is in points.

        :returns: An int or `None`
        """
        return self._simple_get("Badge Max Width")

    @property
    def badge_max_height(self) -> int | None:
        """
        Returns the max height of the badge.

        The value is in points.

        :returns: An int or `None`
        """
        return self._simple_get("Badge Max Height")

    @property
    def badge_font(self) -> str | None:
        """
        Returns the font of the badge.

        The font name is a string like "Helvetica".

        :returns: A str or `None`
        """
        return self._simple_get("Badge Font")

    @property
    def use_custom_window_title(self) -> bool | None:
        """
        Returns whether the custom window title is used.

        Should the custom window title in the profile be used?

        :returns: A bool or `None`
        """
        return self._simple_get("Use Custom Window Title")

    @property
    def custom_window_title(self) -> str | None:
        """
        Returns the custom window title.

        This will only be used if use_custom_window_title is True.
        The value is an interpolated string.

        :returns: A str or `None`
        """
        return self._simple_get("Custom Window Title")

    @property
    def use_transparency_initially(self) -> bool | None:
        """
        Returns whether a window created with this profile respect the
        transparency setting.

        If True, use transparency; if False, force the window to
        be opaque (but it can be toggled with View > Use Transparency).

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Initial Use Transparency")

    @property
    def status_bar_enabled(self) -> bool | None:
        """
        Returns whether the status bar be enabled.

        If True, the status bar will be shown.

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Show Status Bar")

    @property
    def use_csi_u(self) -> bool | None:
        """
        Returns whether to report keystrokes with CSI u protocol.

        If True, CSI u will be enabled.

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Use libtickit protocol")

    @property
    def triggers_use_interpolated_strings(self) -> bool | None:
        """
        Returns whether trigger parameters should be interpreted as
        interpolated strings.

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Triggers Use Interpolated Strings")

    @property
    def left_option_key_changeable(self) -> bool | None:
        """
        Returns whether apps should be able to change the left option key to
        send esc+.

        The values gives whether it should be allowed.

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Left Option Key Changeable")

    @property
    def right_option_key_changeable(self) -> bool | None:
        """
        Returns whether apps should be able to change the right option key to
        send esc+.

        The values gives whether it should be allowed.

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Right Option Key Changeable")

    @property
    def open_password_manager_automatically(self) -> bool | None:
        """
        Returns if the password manager should open automatically.

        The values gives whether it should open automatically.

        :returns: A bool or `None`
        """
        return self._get_optional_bool("Open Password Manager Automatically")

    @property
    def tags(self) -> list[str] | None:
        """
        Returns the tags used to organize profiles.

        Set it to an empty list to remove all tags. The getter returns None or
        an empty list when the profile has no tags.

        :returns: A list[str] or `None`
        """
        return self._simple_get("Tags")

    @property
    def shortcut(self) -> str | None:
        """
        Returns the keyboard shortcut that opens this profile.

        The value is a single uppercase letter or digit that opens the profile
        when pressed with Control and Command. Set it to an empty string to
        remove the shortcut. The getter returns None or an empty string when
        there is no shortcut. Give each shortcut to at most one profile.

        :returns: A str or `None`
        """
        return self._simple_get("Shortcut")

    @property
    def initial_text(self) -> str | None:
        """
        Returns the text to send to the session after it starts.

        The value is an interpolated string.

        :returns: A str or `None`
        """
        return self._simple_get("Initial Text")

    @property
    def run_command_in_login_shell(self) -> bool | None:
        """
        Returns whether a custom command runs inside the user's login shell.

        :returns: A bool or `None`
        """
        return self._simple_get("Run Command In Login Shell")

    @property
    def load_shell_integration_automatically(self) -> bool | None:
        """
        Returns whether shell integration is loaded automatically.

        :returns: A bool or `None`
        """
        return self._simple_get("Load Shell Integration Automatically")

    @property
    def snippets_filter(self) -> list[str] | None:
        """
        Returns the snippet tags available to sessions with this profile.

        An empty list makes all snippets available.

        :returns: A list[str] or `None`
        """
        return self._simple_get("Snippets Filter")

    @property
    def cursor_hidden_without_focus(self) -> bool | None:
        """
        Returns whether the cursor is hidden when the session does not have
        keyboard focus.

        :returns: A bool or `None`
        """
        return self._simple_get("Cursor Hidden When Unfocused")

    @property
    def animate_movement(self) -> bool | None:
        """
        Returns whether cursor movement is animated.

        :returns: A bool or `None`
        """
        return self._simple_get("Animate Movement")

    @property
    def animate_movement_only_in_interactive_apps(self) -> bool | None:
        """
        Returns whether cursor movement is animated only in interactive apps.

        This is used only when animate_movement is True.

        :returns: A bool or `None`
        """
        return self._simple_get("Animate Movement Only in Interactive Apps")

    @property
    def cursor_smooth_slide(self) -> bool | None:
        """
        Returns whether the cursor slides smoothly between positions.

        :returns: A bool or `None`
        """
        return self._simple_get("Cursor Smooth Slide")

    @property
    def cursor_smooth_blink(self) -> bool | None:
        """
        Returns whether a blinking cursor fades smoothly instead of switching
        on and off.

        :returns: A bool or `None`
        """
        return self._simple_get("Cursor Smooth Blink")

    @property
    def cursor_blink_fade_in_duration(self) -> float | None:
        """
        Returns how long, in seconds, a smoothly blinking cursor takes to fade
        in.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Blink Fade In Duration")

    @property
    def cursor_blink_fade_out_duration(self) -> float | None:
        """
        Returns how long, in seconds, a smoothly blinking cursor takes to fade
        out.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Blink Fade Out Duration")

    @property
    def cursor_blink_fade_in_curve(self) -> int | None:
        """
        Returns the easing curve for a smoothly blinking cursor fading in.

        :returns: A CursorBlinkFadeCurve or `None`
        """
        return self._simple_get("Cursor Blink Fade In Curve")

    @property
    def cursor_blink_fade_out_curve(self) -> int | None:
        """
        Returns the easing curve for a smoothly blinking cursor fading out.

        :returns: A CursorBlinkFadeCurve or `None`
        """
        return self._simple_get("Cursor Blink Fade Out Curve")

    @property
    def cursor_blink_visible_dwell(self) -> float | None:
        """
        Returns how long, in seconds, a smoothly blinking cursor stays fully
        visible.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Blink Visible Dwell")

    @property
    def cursor_blink_hidden_dwell(self) -> float | None:
        """
        Returns how long, in seconds, a smoothly blinking cursor stays fully
        hidden.

        :returns: A float or `None`
        """
        return self._simple_get("Cursor Blink Hidden Dwell")

    @property
    def use_theme_mark_colors(self) -> bool | None:
        """
        Returns whether mark indicators use colors from the ANSI palette.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Theme Mark Colors")

    @property
    def background_image_source_mode(self) -> int | None:
        """
        Returns where the background image comes from.

        :returns: A BackgroundImageSourceMode or `None`
        """
        return self._simple_get("Background Image Source Mode")

    @property
    def background_image_folder_location(self) -> str | None:
        """
        Returns the folder of background images to rotate through.

        This is used only when background_image_source_mode is FOLDER_ROTATION.

        :returns: A str or `None`
        """
        return self._simple_get("Background Image Folder Location")

    @property
    def background_image_folder_interval(self) -> float | None:
        """
        Returns how often, in seconds, to change the background image when
        rotating through a folder.

        :returns: A float or `None`
        """
        return self._simple_get("Background Image Folder Interval")

    @property
    def window_type(self) -> int | None:
        """
        Returns the style of window to open.

        :returns: A WindowType or `None`
        """
        return self._simple_get("Window Type")

    @property
    def columns(self) -> int | None:
        """
        Returns the initial number of columns.

        :returns: An int or `None`
        """
        return self._simple_get("Columns")

    @property
    def rows(self) -> int | None:
        """
        Returns the initial number of rows.

        :returns: An int or `None`
        """
        return self._simple_get("Rows")

    @property
    def width_percentage(self) -> float | None:
        """
        Returns the window's width as a percentage of the screen width.

        Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR,
        COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR,
        TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or
        RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a
        non-negative value switches the window from cell-based to
        screen-percentage sizing, even for a normal window. A negative value
        means size by columns instead. If the profile has no value, the window
        is sized by columns, except that top and bottom percentage windows span
        the full screen width. The getter still returns the default of 100 in
        that case.

        :returns: A float or `None`
        """
        return self._simple_get("Width Percentage")

    @property
    def height_percentage(self) -> float | None:
        """
        Returns the window's height as a percentage of the screen height.

        Used only when window_type is a WindowType of NORMAL, NO_TITLE_BAR,
        COMPACT, CENTERED, COMPACT_CENTERED, CENTERED_NO_TITLE_BAR,
        TOP_PERCENTAGE, BOTTOM_PERCENTAGE, LEFT_PERCENTAGE, or
        RIGHT_PERCENTAGE. Other window types ignore it. Setting it to a
        non-negative value switches the window from cell-based to
        screen-percentage sizing, even for a normal window. A negative value
        means size by rows instead. If the profile has no value, the window is
        sized by rows, except that left and right percentage windows span the
        full screen height. The getter still returns the default of 100 in that
        case.

        :returns: A float or `None`
        """
        return self._simple_get("Height Percentage")

    @property
    def screen(self) -> int | None:
        """
        Returns the screen on which new windows open.

        -1 means no preference, -2 means the screen with the pointer, 0 is the
        main screen, and higher numbers are other screens.

        :returns: An int or `None`
        """
        return self._simple_get("Screen")

    @property
    def space(self) -> int | None:
        """
        Returns the Space in which new windows open.

        0 means the current Space, -1 means all Spaces, and 1 through 9 are
        specific Spaces.

        :returns: An int or `None`
        """
        return self._simple_get("Space")

    @property
    def use_custom_tab_title(self) -> bool | None:
        """
        Returns whether the custom tab title is used.

        :returns: A bool or `None`
        """
        return self._simple_get("Use Custom Tab Title")

    @property
    def custom_tab_title(self) -> str | None:
        """
        Returns the custom tab title.

        This is used only when use_custom_tab_title is True. The value is an
        interpolated string.

        :returns: A str or `None`
        """
        return self._simple_get("Custom Tab Title")

    @property
    def hide_after_opening(self) -> bool | None:
        """
        Returns whether a new window is hidden right after it opens.

        :returns: A bool or `None`
        """
        return self._simple_get("Hide After Opening")

    @property
    def lock_window_size_automatically(self) -> bool | None:
        """
        Returns whether a new window's size is locked right after it opens.

        :returns: A bool or `None`
        """
        return self._simple_get("Lock Window Size Automatically")

    @property
    def disable_unfocused_window_resizing(self) -> bool | None:
        """
        Returns whether sessions without keyboard focus are prevented from
        resizing the window with an escape sequence.

        :returns: A bool or `None`
        """
        return self._simple_get("Disable Window Resizing by Unfocused Sessions")

    @property
    def prevent_tab(self) -> bool | None:
        """
        Returns whether this profile always opens in a new window, never in a
        tab.

        :returns: A bool or `None`
        """
        return self._simple_get("Prevent Opening in a Tab")

    @property
    def open_toolbelt(self) -> bool | None:
        """
        Returns whether new windows open with the toolbelt visible.

        :returns: A bool or `None`
        """
        return self._simple_get("Open Toolbelt")

    @property
    def show_rich_tab_content(self) -> bool | None:
        """
        Returns whether tabs in windows created with this profile show rich
        content.

        :returns: A bool or `None`
        """
        return self._simple_get("Show Rich Tab Content")

    @property
    def tab_content_maximum_lines(self) -> int | None:
        """
        Returns the most lines of rich content a tab shows.

        0 means no limit.

        :returns: An int or `None`
        """
        return self._simple_get("Tab Content Maximum Lines")

    @property
    def terminal_type(self) -> str | None:
        """
        Returns the terminal type reported to apps.

        The value is the TERM environment variable, such as xterm-256color.

        :returns: A str or `None`
        """
        return self._simple_get("Terminal Type")

    @property
    def locale_variables_mode(self) -> int | None:
        """
        Returns how the locale environment variables are set.

        :returns: A LocaleVariablesMode or `None`
        """
        return self._simple_get("Set Local Environment Vars")

    @property
    def custom_locale(self) -> str | None:
        """
        Returns the custom locale.

        This is used only when locale_variables_mode is CUSTOM.

        :returns: A str or `None`
        """
        return self._simple_get("Custom Locale")

    @property
    def jobs_to_ignore(self) -> list[str] | None:
        """
        Returns the names of jobs that don't cause a prompt before closing.

        :returns: A list[str] or `None`
        """
        return self._simple_get("Jobs to Ignore")

    @property
    def bell_sound(self) -> str | None:
        """
        Returns the sound the bell plays.

        The value is the name of a sound installed in a Sounds folder, the path
        to an audio file, or an empty string for the system alert sound.

        :returns: A str or `None`
        """
        return self._simple_get("Bell Sound")

    @property
    def prevent_sleep(self) -> bool | None:
        """
        Returns whether the computer is kept from idle sleep while a session
        with this profile exists.

        :returns: A bool or `None`
        """
        return self._simple_get("Prevent Sleep")

    @property
    def allow_paste_bracketing(self) -> bool | None:
        """
        Returns whether apps may turn on bracketed paste mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Allow Paste Bracketing")

    @property
    def enable_triggers_in_interactive_apps(self) -> bool | None:
        """
        Returns whether triggers fire in interactive apps.

        :returns: A bool or `None`
        """
        return self._simple_get("Enable Triggers in Interactive Apps")

    @property
    def tmux_newline(self) -> bool | None:
        """
        Returns whether pressing return in a tmux session sends a newline
        instead of a carriage return.

        :returns: A bool or `None`
        """
        return self._simple_get("Tmux Newline")

    @property
    def show_offscreen_command_line(self) -> bool | None:
        """
        Returns whether the command that produced the output at the top of the
        screen is shown when scrolled back.

        :returns: A bool or `None`
        """
        return self._simple_get("Show Offscreen Command line")

    @property
    def show_offscreen_command_line_for_current_command(self) -> bool | None:
        """
        Returns whether the offscreen command line is also shown for the
        command that is still running.

        :returns: A bool or `None`
        """
        return self._simple_get("Show Offscreen Command line for Current Command")

    @property
    def prompt_path_click_opens_navigator(self) -> bool | None:
        """
        Returns whether clicking the path in a prompt opens a file navigator.

        :returns: A bool or `None`
        """
        return self._simple_get("Prompt Path Click Opens Navigator")

    @property
    def composer_top_offset(self) -> float | None:
        """
        Returns the composer's vertical offset from the top of the session.

        :returns: A float or `None`
        """
        return self._simple_get("Composer Top Offset")

    @property
    def default_pane_locked(self) -> bool | None:
        """
        Returns whether new panes are locked by default.

        :returns: A bool or `None`
        """
        return self._simple_get("Default Pane Locked")

    @property
    def buffer_input_by_default(self) -> bool | None:
        """
        Returns whether keyboard input is buffered by default in new sessions.

        :returns: A bool or `None`
        """
        return self._simple_get("Buffer Input by Default")

    @property
    def timestamps_visible(self) -> bool | None:
        """
        Returns whether timestamps are visible.

        :returns: A bool or `None`
        """
        return self._simple_get("Timestamps Visible")

    @property
    def timestamps_style(self) -> int | None:
        """
        Returns how timestamps are drawn when visible.

        :returns: A TimestampsStyle or `None`
        """
        return self._simple_get("Timestamps Style")

    @property
    def enable_progress_bars(self) -> bool | None:
        """
        Returns whether progress bars reported by apps are shown.

        :returns: A bool or `None`
        """
        return self._simple_get("Enable Progress Bars")

    @property
    def progress_bar_height(self) -> float | None:
        """
        Returns the height of progress bars, in points.

        :returns: A float or `None`
        """
        return self._simple_get("Progress Bar Height")

    @property
    def progress_bar_color_scheme(self) -> str | None:
        """
        Returns the color scheme for progress bars.

        The value is one of default, rainbow, red, green, blue, yellow, purple,
        cyan, or orange.

        :returns: A str or `None`
        """
        return self._simple_get("Progress Bar Color Scheme")

    @property
    def send_alerts_to_companion(self) -> bool | None:
        """
        Returns whether this profile's notifications are also sent to the
        paired iTerm2 Buddy iPhone app.

        :returns: A bool or `None`
        """
        return self._simple_get("Send Alerts To Companion")

    @property
    def suppress_alerts_in_active_session(self) -> bool | None:
        """
        Returns whether notifications from the active session are suppressed.

        :returns: A bool or `None`
        """
        return self._simple_get("Suppress Alerts in Active Session")

    @property
    def mouse_reporting_allow_clicks_and_drags(self) -> bool | None:
        """
        Returns whether mouse reporting reports clicks and drags.

        :returns: A bool or `None`
        """
        return self._simple_get("Mouse Reporting allow clicks and drags")

    @property
    def restrict_mouse_reporting_to_alternate_screen_mode(self) -> bool | None:
        """
        Returns whether mouse reporting is allowed only in alternate screen
        mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Restrict Mouse Reporting to Alternate Screen Mode")

    @property
    def allow_alternate_mouse_scroll(self) -> bool | None:
        """
        Returns whether scrolling in alternate screen mode sends arrow keys.

        :returns: A bool or `None`
        """
        return self._simple_get("Allow Alternate Mouse Scroll")

    @property
    def automatically_enable_alternate_mouse_scroll(self) -> bool | None:
        """
        Returns whether scrolling sends arrow keys automatically in alternate
        screen mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Automatically Enable Alternate Mouse Scroll")

    @property
    def restrict_alternate_mouse_scroll_to_vertical(self) -> bool | None:
        """
        Returns whether only vertical scrolling sends arrow keys in alternate
        screen mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Restrict Alternate Mouse Scroll to Vertical")

    @property
    def drag_to_scroll_in_alternate_screen_mode_disabled(self) -> bool | None:
        """
        Returns whether dragging a selection past the edge stops scrolling in
        alternate screen mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Drag to Scroll in Alternate Screen Mode Disabled")

    @property
    def left_control_key_behavior(self) -> int | None:
        """
        Returns how the left control key is reported to apps.

        :returns: A ModifierKeyBehavior or `None`
        """
        return self._simple_get("Left Control Key")

    @property
    def right_control_key_behavior(self) -> int | None:
        """
        Returns how the right control key is reported to apps.

        :returns: A ModifierKeyBehavior or `None`
        """
        return self._simple_get("Right Control Key")

    @property
    def left_command_key_behavior(self) -> int | None:
        """
        Returns how the left command key is reported to apps.

        :returns: A ModifierKeyBehavior or `None`
        """
        return self._simple_get("Left Command Key")

    @property
    def right_command_key_behavior(self) -> int | None:
        """
        Returns how the right command key is reported to apps.

        :returns: A ModifierKeyBehavior or `None`
        """
        return self._simple_get("Right Command Key")

    @property
    def function_key_behavior(self) -> int | None:
        """
        Returns how the fn key is reported to apps.

        :returns: A ModifierKeyBehavior or `None`
        """
        return self._simple_get("Function Key")

    @property
    def treat_option_as_alt(self) -> bool | None:
        """
        Returns whether option is reported as alt in modifier flags.

        :returns: A bool or `None`
        """
        return self._simple_get("Treat Option as Alt")

    @property
    def allow_modify_other_keys(self) -> bool | None:
        """
        Returns whether apps may turn on xterm's modifyOtherKeys mode.

        :returns: A bool or `None`
        """
        return self._simple_get("Allow modifyOtherKeys")

    @property
    def movement_keys_scroll_outside_interactive_apps(self) -> bool | None:
        """
        Returns whether arrow and page keys scroll when not in an interactive
        app.

        :returns: A bool or `None`
        """
        return self._simple_get("Movement Keys Scroll Outside Interactive Apps")

    @property
    def has_hotkey(self) -> bool | None:
        """
        Returns whether this profile has a dedicated hotkey window.

        To assign a hotkey without a key code, also set
        hotkey_activated_by_modifier and hotkey_modifier_activation.

        :returns: A bool or `None`
        """
        return self._simple_get("Has Hotkey")

    @property
    def hotkey_activated_by_modifier(self) -> bool | None:
        """
        Returns whether double-tapping a modifier key toggles the hotkey
        window.

        :returns: A bool or `None`
        """
        return self._simple_get("HotKey Activated By Modifier")

    @property
    def hotkey_modifier_activation(self) -> int | None:
        """
        Returns which modifier key to double-tap to toggle the hotkey window.

        :returns: A HotkeyModifierActivation or `None`
        """
        return self._simple_get("HotKey Modifier Activation")

    @property
    def hotkey_auto_hides(self) -> bool | None:
        """
        Returns whether the hotkey window hides when it loses focus.

        :returns: A bool or `None`
        """
        return self._simple_get("HotKey Window AutoHides")

    @property
    def hotkey_reopens_on_activation(self) -> bool | None:
        """
        Returns whether an auto-hidden hotkey window reappears when iTerm2 is
        activated.

        :returns: A bool or `None`
        """
        return self._simple_get("HotKey Window Reopens On Activation")

    @property
    def hotkey_animates(self) -> bool | None:
        """
        Returns whether the hotkey window animates when it shows and hides.

        :returns: A bool or `None`
        """
        return self._simple_get("HotKey Window Animates")

    @property
    def hotkey_floats(self) -> bool | None:
        """
        Returns whether the hotkey window floats above other windows.

        :returns: A bool or `None`
        """
        return self._simple_get("HotKey Window Floats")

    @property
    def hotkey_dock_click_action(self) -> int | None:
        """
        Returns whether clicking iTerm2's Dock icon shows the hotkey window.

        :returns: A HotkeyWindowDockClickAction or `None`
        """
        return self._simple_get("HotKey Window Dock Click Action")

    @property
    def automatically_log(self) -> bool | None:
        """
        Returns whether session output is logged automatically.

        :returns: A bool or `None`
        """
        return self._simple_get("Automatically Log")

    @property
    def log_directory(self) -> str | None:
        """
        Returns the directory for automatic logs.

        :returns: A str or `None`
        """
        return self._simple_get("Log Directory")

    @property
    def log_filename_format(self) -> str | None:
        """
        Returns the format of automatic log file names.

        The value is an interpolated string.

        :returns: A str or `None`
        """
        return self._simple_get("Log Filename Format")

    @property
    def logging_style(self) -> int | None:
        """
        Returns the format of automatic logs.

        :returns: A LoggingStyle or `None`
        """
        return self._simple_get("Plain Text Logging")

    @property
    def archive_on_closure(self) -> bool | None:
        """
        Returns whether sessions are archived when they close.

        :returns: A bool or `None`
        """
        return self._simple_get("Archive On Closure")

    @property
    def archive_directory(self) -> str | None:
        """
        Returns the directory for archived sessions.

        :returns: A str or `None`
        """
        return self._simple_get("Archive Directory")

    @property
    def initial_url(self) -> str | None:
        """
        Returns the URL a web browser profile opens.

        :returns: A str or `None`
        """
        return self._simple_get("Initial URL")

    @property
    def browser_zoom(self) -> float | None:
        """
        Returns the zoom level of a web browser profile.

        100 means 100%.

        :returns: A float or `None`
        """
        return self._simple_get("Browser Zoom")

    @property
    def browser_dev_null(self) -> bool | None:
        """
        Returns whether a web browser profile uses a private data store that is
        not shared with other browser profiles.

        :returns: A bool or `None`
        """
        return self._simple_get("Dev Null Mode")

    @property
    def browser_width(self) -> float | None:
        """
        Returns the initial width of a web browser profile's window, in points.

        :returns: A float or `None`
        """
        return self._simple_get("Width in Points")

    @property
    def browser_height(self) -> float | None:
        """
        Returns the initial height of a web browser profile's window, in
        points.

        :returns: A float or `None`
        """
        return self._simple_get("Height in Points")

    @property
    def browser_instant_replay(self) -> bool | None:
        """
        Returns whether instant replay is enabled for a web browser profile.

        :returns: A bool or `None`
        """
        return self._simple_get("Instant Replay")


class PartialProfile(Profile):
    """
    Represents a profile that has only a subset of fields available for
    reading.
    """

    # pylint: disable=dangerous-default-value
    @staticmethod
    async def async_query(
        connection: Connection,
        guids: Iterable[str] | None = None,
        properties: Iterable[str] | None = ["Guid", "Name"],
    ) -> list[PartialProfile]:
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
        response = await async_list_profiles(connection, guids, properties)
        profiles: list[PartialProfile] = []
        for response_profile in response.list_profiles_response.profiles:
            profile = PartialProfile(None, connection, response_profile.properties)
            profiles.append(profile)
        return profiles

    # Disable this because it's a public API and I'm stuck with it.
    # pylint: disable=arguments-differ
    @staticmethod
    async def async_get_default(
        connection: Connection, properties: Iterable[str] | None = ["Guid", "Name"]
    ) -> PartialProfile:
        """Returns the default profile."""
        check_supports_get_default_profile(connection)
        result = await async_get_default_profile(connection)
        guid = result.preferences_response.results[0].get_default_profile_result.guid
        profiles = await PartialProfile.async_query(connection, [guid], properties)
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
        response = await async_list_profiles(self.connection, [self.guid], None)
        if len(response.list_profiles_response.profiles) != 1:
            raise BadGUIDException()
        return Profile(
            None,
            self.connection,
            response.list_profiles_response.profiles[0].properties,
        )

    async def async_make_default(self) -> None:
        """Makes this profile the default profile.

        Raises BadGUIDException if the Guid is not set.
        """
        guid = self.guid
        if guid is None:
            raise BadGUIDException()
        await async_set_default_profile(self.connection, guid)
