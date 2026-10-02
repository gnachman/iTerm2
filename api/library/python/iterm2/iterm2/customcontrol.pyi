from re import Match
from types import TracebackType
from typing_extensions import Self

from .connection import Connection

class CustomControlSequenceMonitor:
    def __init__(
        self,
        connection: Connection,
        identity: str,
        regex: str,
        session_id: str | None = None,
    ) -> None: ...
    async def __aenter__(self) -> Self: ...
    async def async_get(self) -> Match[str]: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None: ...
