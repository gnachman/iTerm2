from enum import Enum
from types import TracebackType
from typing import Any, Literal, overload

from typing_extensions import Self

from google.protobuf.internal.containers import RepeatedScalarFieldContainer

from . import api_pb2
from .connection import Connection
from .util import CoordRange

class PromptState(Enum):
    UNKNOWN = -1
    EDITING = 0
    RUNNING = 1
    FINISHED = 2

class Prompt:
    def __init__(self, proto: api_pb2.GetPromptResponse) -> None: ...
    @property
    def prompt_range(self) -> CoordRange: ...
    @property
    def command_range(self) -> CoordRange: ...
    @property
    def output_range(self) -> CoordRange: ...
    @property
    def working_directory(self) -> str | None: ...
    @property
    def command(self) -> str | None: ...
    @property
    def excluded_subranges(self) -> list[CoordRange]: ...
    @property
    def state(self) -> PromptState: ...
    @property
    def unique_id(self) -> str | None: ...

async def async_get_last_prompt(
    connection: Connection, session_id: str
) -> Prompt | None: ...
async def async_get_prompt_by_id(
    connection: Connection, session_id: str, prompt_unique_id: str
) -> Prompt | None: ...
async def async_list_prompts(
    connection: Connection,
    session_id: str,
    first: str | None = None,
    last: str | None = None,
) -> RepeatedScalarFieldContainer[str]: ...

class PromptMonitor:
    class Mode(Enum):
        PROMPT = 1
        COMMAND_START = 2
        COMMAND_END = 3

    connection: Connection
    session_id: str
    def __init__(
        self,
        connection: Connection,
        session_id: str,
        modes: list[PromptMonitor.Mode] | None = None,
    ) -> None: ...
    async def __aenter__(self) -> Self: ...
    @overload
    async def async_get(
        self, include_id: Literal[False] = False
    ) -> tuple[PromptMonitor.Mode, Any]: ...
    @overload
    async def async_get(
        self, include_id: Literal[True]
    ) -> tuple[PromptMonitor.Mode, Any, str | None]: ...
    @overload
    async def async_get(
        self, include_id: bool
    ) -> (
        tuple[PromptMonitor.Mode, Any] | tuple[PromptMonitor.Mode, Any, str | None]
    ): ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        _tb: TracebackType | None,
    ) -> None: ...
