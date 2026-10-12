"""Provides access to color presets."""

from __future__ import annotations

from collections.abc import Iterable
from typing import TYPE_CHECKING

from .api_pb2 import ColorPresetResponse
from .color import Color as _Color
from .color import ColorSpace
from .rpc import async_get_color_preset, async_list_color_presets

if TYPE_CHECKING:
    from .connection import Connection


class ListPresetsException(Exception):
    """Something went wrong listing presets."""


class GetPresetException(Exception):
    """Something went wrong fetching a color preset."""


class ColorPreset:
    """
    A color preset is a named collection of colors attached to terminal
    attributes (e.g., default background color).
    """

    class Color(_Color):
        """Derives from :class:`~iterm2.Color`.

        Note this is is an inner class of `ColorPreset`."""

        # pylint: disable=too-many-arguments
        def __init__(
            self,
            r: float,
            g: float,
            b: float,
            a: float,
            color_space: ColorSpace,
            key: str,
        ) -> None:
            super().__init__(r, g, b, a, color_space)
            self.__key = key

        @property
        def key(self) -> str:
            """Describes which property this color affects."""
            return self.__key

        def __repr__(self):
            return (
                f"({self.__key},{round(self.red)},{round(self.green)}"
                f",{round(self.blue)},{round(self.alpha)} {self.color_space})"
            )

    @staticmethod
    async def async_get_list(connection: Connection) -> list[str]:
        """Fetches a list of color presets.

        :param connection: An :class:`~iterm2.Connection`.

        :returns: Names of the color presets.

        .. seealso::
            * Example ":ref:`current_preset_example`"
            * Example ":ref:`random_color_example`"
        """
        # pylint: disable=no-member
        result = await async_list_color_presets(connection)
        if result.color_preset_response.status == ColorPresetResponse.Status.Value(
            "OK"
        ):
            return list(result.color_preset_response.list_presets.name)
        raise GetPresetException(
            ColorPresetResponse.Status.Name(result.color_preset_response.status)
        )

    @staticmethod
    async def async_get(connection: Connection, name: str) -> ColorPreset | None:
        """Fetches a color preset with the given name.

        :param connection: The connection to iTerm2.
        :param name: The name of the preset to fetch.

        :returns: Either a new preset or `None`.

        .. seealso::
            * Example ":ref:`colorhost_example`"
            * Example ":ref:`current_preset_example`"
            * Example ":ref:`theme_example`"
            * Example ":ref:`darknight_example`"
        """
        result = await async_get_color_preset(connection, name)
        # pylint: disable=no-member
        if result.color_preset_response.status == ColorPresetResponse.Status.Value(
            "OK"
        ):
            return ColorPreset(result.color_preset_response.get_preset.color_settings)
        raise ListPresetsException(
            ColorPresetResponse.Status.Name(result.color_preset_response.status)
        )

    def __init__(
        self, proto: Iterable[ColorPresetResponse.GetPreset.ColorSetting]
    ) -> None:
        """Do not call this directly. Use :meth:async_get instead."""
        self.__values: list[ColorPreset.Color] = []
        for setting in proto:
            self.__values.append(
                ColorPreset.Color(
                    setting.red * 255,
                    setting.green * 255,
                    setting.blue * 255,
                    setting.alpha * 255,
                    ColorSpace(setting.color_space),
                    setting.key,
                )
            )

    @property
    def values(self) -> list[ColorPreset.Color]:
        """Returns a list of color settings.

        :returns: The colors belonging to the preset.
        """
        return self.__values
