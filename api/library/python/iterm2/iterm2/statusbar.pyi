import enum
from collections.abc import Awaitable, Callable, Sequence
from typing import Any

from . import api_pb2
from .color import Color
from .connection import Connection
from .registration import StatusBarRPCFunction
from .util import Size

class BaseKnob:
    def __init__(
        self,
        knob_type: api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob.Type.ValueType,
        name: str,
        placeholder: str,
        json_default_value: str,
        key: str,
    ) -> None: ...
    def to_proto(
        self,
    ) -> api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob: ...

class Knob:
    def __init__(
        self,
        knob_type: api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob.Type.ValueType,
        name: str,
        placeholder: str,
        json_default_value: str,
        key: str,
    ) -> None: ...
    def to_proto(
        self,
    ) -> api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Knob: ...

class CheckboxKnob(Knob):
    def __init__(self, name: str, default_value: bool, key: str) -> None: ...

class StringKnob(Knob):
    def __init__(
        self, name: str, placeholder: str, default_value: str, key: str
    ) -> None: ...

class PositiveFloatingPointKnob(Knob):
    def __init__(self, name: str, default_value: float, key: str) -> None: ...

class ColorKnob(Knob):
    def __init__(self, name: str, default_value: Color, key: str) -> None: ...

class StatusBarComponent:
    class Format(enum.Enum):
        PLAIN_TEXT = 0
        HTML = 1

    class Icon:
        def __init__(self, scale: float, base64_data: str) -> None: ...
        def to_status_bar_icon(
            self,
        ) -> api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes.Icon: ...

    def __init__(
        self,
        short_description: str,
        detailed_description: str,
        knobs: Sequence[Knob],
        exemplar: str,
        update_cadence: float | None,
        identifier: str,
        icons: Sequence[Icon] = ...,
        format: Format = ...,
    ) -> None: ...
    def set_fields_in_proto(
        self, proto: api_pb2.RPCRegistrationRequest.StatusBarComponentAttributes
    ) -> None: ...
    async def async_open_popover(
        self, session_id: str, html: str, size: Size
    ) -> None: ...
    async def async_set_unread_count(
        self, session_id: str | None, count: int
    ) -> None: ...
    async def async_register(
        self,
        connection: Connection,
        coro: StatusBarRPCFunction[..., Any],
        timeout: float | None = None,
        onclick: Callable[[str], Awaitable[Any]] | None = None,
    ) -> None: ...
