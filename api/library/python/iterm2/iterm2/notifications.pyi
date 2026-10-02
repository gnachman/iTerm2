from collections.abc import Awaitable, Callable, Collection, Iterable, Mapping
from typing import Any, TypeAlias

from . import api_pb2
from .connection import Connection
from .keyboard import KeystrokePattern
from .statusbar import StatusBarComponent

type NotificationCallback[N] = Callable[[Connection, N], Awaitable[Any]]
NotificationToken: TypeAlias = tuple[tuple[Any, ...], Callable[..., Any]]

RPC_ROLE_GENERIC: api_pb2.RPCRegistrationRequest.Role.ValueType
RPC_ROLE_SESSION_TITLE: api_pb2.RPCRegistrationRequest.Role.ValueType
RPC_ROLE_STATUS_BAR_COMPONENT: api_pb2.RPCRegistrationRequest.Role.ValueType
RPC_ROLE_CONTEXT_MENU: api_pb2.RPCRegistrationRequest.Role.ValueType

class SubscriptionException(Exception): ...

async def async_unsubscribe(
    connection: Connection, token: NotificationToken
) -> None: ...
async def async_subscribe_to_new_session_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.NewSessionNotification],
) -> NotificationToken: ...
async def async_subscribe_to_keystroke_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.KeystrokeNotification],
    session: str | None = None,
    advanced: bool = False,
) -> NotificationToken: ...
async def async_filter_keystrokes(
    connection: Connection,
    patterns_to_ignore: Iterable[KeystrokePattern],
    session: str | None = None,
) -> NotificationToken: ...
async def async_subscribe_to_screen_update_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.ScreenUpdateNotification],
    session: str | None = None,
) -> NotificationToken: ...
async def async_subscribe_to_prompt_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.PromptNotification],
    session: str | None,
    modes: Iterable[api_pb2.PromptMonitorMode.ValueType],
) -> NotificationToken: ...
async def async_subscribe_to_custom_escape_sequence_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.CustomEscapeSequenceNotification],
    session: str | None = None,
) -> NotificationToken: ...
async def async_subscribe_to_terminate_session_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.TerminateSessionNotification],
) -> NotificationToken: ...
async def async_subscribe_to_layout_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.LayoutChangedNotification],
) -> NotificationToken: ...
async def async_subscribe_to_focus_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.FocusChangedNotification],
) -> NotificationToken: ...
async def async_subscribe_to_broadcast_domains_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.Notification],
) -> NotificationToken: ...
async def async_subscribe_to_server_originated_rpc_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.Notification],
    name: str,
    arguments: Collection[str] = ...,
    timeout_seconds: float | None = 5,
    defaults: Mapping[str, str] = ...,
    role: api_pb2.RPCRegistrationRequest.Role.ValueType = ...,
    session_title_display_name: str | None = None,
    session_title_unique_id: str | None = None,
    status_bar_component: StatusBarComponent | None = None,
    context_menu_display_name: str | None = None,
    context_menu_unique_id: str | None = None,
) -> NotificationToken: ...
async def async_subscribe_to_variable_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.VariableChangedNotification],
    scope: api_pb2.VariableScope.ValueType,
    name: str,
    identifier: str | None,
) -> NotificationToken: ...
async def async_subscribe_to_profile_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.Notification],
    guid: str,
) -> NotificationToken: ...
