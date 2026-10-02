import enum
from types import TracebackType
from typing import Any

from typing_extensions import Self

from .connection import Connection

class VariableScopes(enum.Enum):
    SESSION = 1
    TAB = 2
    WINDOW = 3
    APP = 4

class VariableMonitor:
    def __init__(
        self,
        connection: Connection,
        scope: VariableScopes,
        name: str,
        identifier: str | None,
    ) -> None: ...
    async def __aenter__(self) -> Self: ...
    async def async_get(self) -> Any: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None: ...
