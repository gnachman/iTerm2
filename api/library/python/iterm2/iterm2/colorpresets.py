"""Provides access to color presets."""

import iterm2.connection
import iterm2.color
import iterm2.rpc
import typing

class ListPresetsException(Exception):
    """Something went wrong listing presets."""
    pass

class GetPresetException(Exception):
    """Something went wrong fetching a color preset."""
    pass

class ColorPreset:
    class Color(iterm2.color.Color):
        """Derives from :class:`~iterm2.Color`.

        Note this is is an inner class of `ColorPreset`."""
        def __init__(self, r, g, b, a, color_space, key):
            super().__init__(r, g, b, a, color_space)
            self.__key = key

        @property
        def key(self) -> str:
            """Describes which property this color affects."""
            return self.__key

        def __repr__(self):
            return "({},{},{},{},{} {})".format(
                self.__key,
                round(self.red),
                round(self.green),
                round(self.blue),
                round(self.alpha),
                self.color_space)

    @staticmethod
    async def async_get_list(connection: iterm2.connection.Connection) -> typing.List[str]:
        """Fetches a list of color presets.

        :param connection: An :class:`~iterm2.Connection`.

        :returns: Names of the color presets.

        .. seealso::
            * Example ":ref:`current_preset_example`"
            * Example ":ref:`random_color_example`"
        """
        result = await iterm2.rpc.async_list_color_presets(connection)
        if result.color_preset_response.status == iterm2.api_pb2.ColorPresetResponse.Status.Value("OK"):
            return list(result.color_preset_response.list_presets.name)
        else:
            raise GetPresetException(iterm2.api_pb2.ColorPresetResponse.Status.Name(result.color_preset_response.status))

    @staticmethod
    async def async_get(connection: iterm2.connection.Connection, name: str) -> typing.Union[None, 'ColorPreset']:
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
        result = await iterm2.rpc.async_get_color_preset(connection, name)
        if result.color_preset_response.status == iterm2.api_pb2.ColorPresetResponse.Status.Value("OK"):
            return ColorPreset(result.color_preset_response.get_preset.color_settings)
        else:
            raise ListPresetsException(iterm2.api_pb2.ColorPresetResponse.Status.Name(result.color_preset_response.status))

    def __init__(self, proto):
        """Do not call this directly. Use :meth:async_get instead."""
        self.__values = []
        for setting in proto:
            self.__values.append(ColorPreset.Color(
                setting.red * 255,
                setting.green * 255,
                setting.blue * 255,
                setting.alpha * 255,
                iterm2.color.ColorSpace(setting.color_space),
                setting.key))

    @property
    def values(self) -> typing.List['ColorPreset.Color']:
        """Returns a list of color settings.

        :returns: The colors belonging to the preset.
        """
        return self.__values

