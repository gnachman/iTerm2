from collections.abc import Iterable

from .api_pb2 import ColorPresetResponse
from .color import Color as ColorColor
from .color import ColorSpace
from .connection import Connection

class ListPresetsException(Exception): ...
class GetPresetException(Exception): ...

class ColorPreset:
    class Color(ColorColor):
        def __init__(
            self,
            r: float,
            g: float,
            b: float,
            a: float,
            color_space: ColorSpace,
            key: str,
        ) -> None: ...
        @property
        def key(self) -> str: ...

    @staticmethod
    async def async_get_list(connection: Connection) -> list[str]: ...
    @staticmethod
    async def async_get(connection: Connection, name: str) -> ColorPreset | None: ...
    def __init__(
        self, proto: Iterable[ColorPresetResponse.GetPreset.ColorSetting]
    ) -> None: ...
    @property
    def values(self) -> list[ColorPreset.Color]: ...
