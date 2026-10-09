import enum
from collections.abc import Awaitable, Callable
from typing import Any

from . import api_pb2
from .connection import Connection
from .util import CoordRange, WindowedCoordRange

class SelectionMode(enum.Enum):
    CHARACTER = 0
    WORD = 1
    LINE = 2
    SMART = 3
    BOX = 4
    WHOLE_LINE = 5
    @staticmethod
    def from_proto_value(value: api_pb2.SelectionMode.ValueType) -> SelectionMode: ...
    @staticmethod
    def to_proto_value(value: SelectionMode) -> api_pb2.SelectionMode.ValueType: ...

class SubSelection:
    def __init__(
        self,
        windowed_coord_range: WindowedCoordRange,
        mode: SelectionMode,
        connected: bool,
    ) -> None: ...
    @property
    def windowedCoordRange(self) -> WindowedCoordRange: ...
    @property
    def windowed_coord_range(self) -> WindowedCoordRange: ...
    @property
    def mode(self) -> SelectionMode: ...
    @property
    def proto(self) -> api_pb2.SubSelection: ...
    @property
    def connected(self) -> bool: ...
    async def async_get_string(self, connection: Connection, session_id: str) -> str: ...
    def enumerate_ranges(self, callback: Callable[[CoordRange], Any]) -> None: ...

class Selection:
    def __init__(self, sub_selections: list[SubSelection]) -> None: ...
    @property
    def subSelections(self) -> list[SubSelection]: ...
    @property
    def sub_selections(self) -> list[SubSelection]: ...
    async def async_get_string(
        self, connection: Connection, session_id: str, width: int
    ) -> str: ...
    async def async_enumerate_ranges(
        self,
        width: int,
        callback: Callable[[WindowedCoordRange, bool], Awaitable[bool | None]],
    ) -> None: ...

MODE_MAP: dict[api_pb2.SelectionMode.ValueType, SelectionMode]
INVERSE_MODE_MAP: dict[SelectionMode, api_pb2.SelectionMode.ValueType]
