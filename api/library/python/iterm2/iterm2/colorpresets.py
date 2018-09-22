"""Provides access to color presets."""

import iterm2.rpc

class ListPresetsException(Exception):
    """Something went wrong listing presets."""
    pass

class GetPresetException(Exception):
    """Something went wrong fetching a color preset."""
    pass

class ColorPreset:
    class Color:
        def __init__(self, key, red, green, blue, alpha, colorSpace):
            self.__key = key
            self.__red = red
            self.__green = green
            self.__blue = blue
            self.__alpha = alpha
            self.__colorSpace = colorSpace

        @property
        def key(self):
            return self.__key

        @property
        def red(self):
            return self.__red

        @property
        def green(self):
            return self.__green

        @property
        def blue(self):
            return self.__blue

        @property
        def alpha(self):
            return self.__alpha

        @property
        def colorSpace(self):
            return self.__colorSpace

    @staticmethod
    async def async_get_list(connection):
        """Fetches a list of color presets.

        :param connection: A :class:`iterm2.Connection`.

        :returns: A list of names as strings.
        """
        result = await iterm2.rpc.async_list_color_presets(connection)
        if result.color_preset_response.status == iterm2.api_pb2.ColorPresetResponse.Status.Value("OK"):
            return list(result.color_preset_response.list_presets.name)
        else:
            raise GetPresetException(iterm2.api_pb2.ColorPresetResponse.Status.Name(result.color_preset_response.status))

    @staticmethod
    async def async_get(connection, name):
        """Fetches a color preset with the given name.

        :param connection: A :class:`iterm2.Connection`.
        :param name: The name of the preset to fetch.

        :returns: Either a new :class:`ColorPreset` or None."""
        result = await iterm2.rpc.async_get_color_preset(connection, name)
        if result.color_preset_response.status == iterm2.api_pb2.ColorPresetResponse.Status.Value("OK"):
            return ColorPreset(result.color_preset_response.get_preset.color_settings)
        else:
            raise ListPresetsException(iterm2.api_pb2.ColorPresetResponse.Status.Name(result.color_preset_response.status))

    def __init__(self, proto):
        """Do not call this directly. Use :meth:async_get instead."""
        self.__values = []
        for setting in proto:
            self.__values.append(ColorPreset.Color(setting.key, setting.red, setting.green, setting.blue, setting.alpha, setting.color_space))

    @property
    def values(self):
        """Returns a list of color settings.

        :returns: A list of :class:`Color` objects.
        """
        return self.__values

