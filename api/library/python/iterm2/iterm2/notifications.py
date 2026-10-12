"""Subscribe/unsubscribe from async notifications.

This module provides functions that let you subscribe and unsubscribe from
notifications. iTerm2 posts notifications when some event of interest (for
example, a keystroke) occurs. By subscribing to a notifications your async
callback will be run when the event occurs.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, TypeVar

from . import api_pb2
from .connection import Connection
from .rpc import async_notification_request, async_send_rpc_result

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable, Collection, Iterable, Mapping
    from typing import TypeAlias

    from google.protobuf.message import Message

    from .keyboard import KeystrokePattern
    from .statusbar import StatusBarComponent

    _N = TypeVar("_N")

    NotificationCallback: TypeAlias = Callable[[Connection, _N], Awaitable[Any]]
    NotificationKey: TypeAlias = tuple[Any, ...]
    NotificationToken: TypeAlias = tuple[NotificationKey, NotificationCallback[Any]]

# pylint: disable=no-member
RPC_ROLE_GENERIC: api_pb2.RPCRegistrationRequest.Role.ValueType = (
    api_pb2.RPCRegistrationRequest.Role.Value("GENERIC")
)
RPC_ROLE_SESSION_TITLE: api_pb2.RPCRegistrationRequest.Role.ValueType = (
    api_pb2.RPCRegistrationRequest.Role.Value("SESSION_TITLE")
)
RPC_ROLE_STATUS_BAR_COMPONENT: api_pb2.RPCRegistrationRequest.Role.ValueType = (
    api_pb2.RPCRegistrationRequest.Role.Value("STATUS_BAR_COMPONENT")
)
RPC_ROLE_CONTEXT_MENU: api_pb2.RPCRegistrationRequest.Role.ValueType = (
    api_pb2.RPCRegistrationRequest.Role.Value("CONTEXT_MENU")
)

# pylint: enable=no-member


# The registered notification handlers.
# (session, notification_type[, rpc_registration_request]) -> [coroutine, ...]
_handlers: dict[NotificationKey, list[NotificationCallback[Any]]] = {}
_have_registered_helper = False


# APIs -----------------------------------------------------------------------


class SubscriptionException(Exception):
    """Raised when a subscription attempt fails."""


async def async_unsubscribe(connection: Connection, token: NotificationToken) -> None:
    """
    Unsubscribes from a notification.

    :param connection: A connected :class:`Connection`.
    :param token: The result of a previous subscribe call.
    """
    key, coro = token
    coros = _handlers[key]
    coros.remove(coro)
    if not coros:
        del _handlers[key]
        if len(key) == 2:
            session, notification_type = key
            await _async_subscribe(
                connection, False, notification_type, coro, session=session
            )
        else:
            if key[-1] == api_pb2.NOTIFY_ON_VARIABLE_CHANGE:
                scope, identifier, name, notification_type = key
                request = api_pb2.VariableMonitorRequest()
                request.name = name
                request.scope = scope
                request.identifier = identifier
                await _async_subscribe(
                    connection,
                    False,
                    notification_type,
                    coro,
                    key=key,
                    variable_monitor_request=request,
                )
            else:
                # The key is custom and there should be code to handle
                # unsubscribing as an elif clause here.
                assert False


async def async_subscribe_to_new_session_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.NewSessionNotification],
) -> NotificationToken:
    """
    Registers a callback to be run when a new session is created.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an
      :class:`Connection` and iterm2.api_pb2.NewSessionNotification.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection, True, api_pb2.NOTIFY_ON_NEW_SESSION, callback
    )


async def async_subscribe_to_keystroke_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.KeystrokeNotification],
    session: str | None = None,
    advanced: bool = False,
) -> NotificationToken:
    """
    Registers a callback to be run when a key is pressed.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.KeystrokeNotification.
    :param session: The session to monitor, or None.
    :param advanced: Use "advanced" reporting (key up, flags changed)?

    Returns: A token that can be passed to unsubscribe.
    """
    kmr = api_pb2.KeystrokeMonitorRequest()
    kmr.advanced = advanced
    return await _async_subscribe(
        connection,
        True,
        api_pb2.NOTIFY_ON_KEYSTROKE,
        callback,
        session=session,
        keystroke_monitor_request=kmr,
    )


async def async_filter_keystrokes(
    connection: Connection,
    patterns_to_ignore: Iterable[KeystrokePattern],
    session: str | None = None,
) -> NotificationToken:
    """
    Subscribe to a pseudo-notification that causes keystrokes matching patterns
    to be ignored.

    :param connection: A connected :class:`Connection`.
    :param patterns_to_ignore: A list of keystroke patterns that iTerm2 should
        not handle, expecting the script will handle it alone. Objects are
        class :class:`KeystrokePattern`.
    :param session: The session to monitor, or None.

    Returns: A token that can be passed to unsubscribe.
    """
    # pylint: disable=no-member
    kfr = api_pb2.KeystrokeFilterRequest()
    kfr.patterns_to_ignore.extend([x.to_proto() for x in patterns_to_ignore])

    async def callback(connection: Connection, notif: api_pb2.Notification):  # pylint: disable=unused-argument
        pass

    return await _async_subscribe(
        connection,
        True,
        api_pb2.KEYSTROKE_FILTER,
        callback,
        session=session,
        keystroke_filter_request=kfr,
    )


async def async_subscribe_to_screen_update_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.ScreenUpdateNotification],
    session: str | None = None,
) -> NotificationToken:
    """
    Registers a callback to be run when the screen contents change.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.ScreenUpdateNotification..
    :param session: The session to monitor, or None.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection, True, api_pb2.NOTIFY_ON_SCREEN_UPDATE, callback, session=session
    )


async def async_subscribe_to_prompt_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.PromptNotification],
    session: str | None,
    modes: Iterable[api_pb2.PromptMonitorMode.ValueType],
) -> NotificationToken:
    """
    Registers a callback to be run when a shell prompt is received.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.PromptNotification.
    :param session: The session to monitor, or None.
    :param modes: The modes to subscribe to.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection,
        True,
        api_pb2.NOTIFY_ON_PROMPT,
        callback,
        session=session,
        prompt_monitor_modes=modes,
    )


async def async_subscribe_to_custom_escape_sequence_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.CustomEscapeSequenceNotification],
    session: str | None = None,
) -> NotificationToken:
    """
    Registers a callback to be run when a custom escape sequence is received.

    The escape sequence is OSC 1337 ; Custom=id=<identity>:<payload> ST

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.CustomEscapeSequenceNotification.
    :param session: The session to monitor, or None.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection,
        True,
        api_pb2.NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE,
        callback,
        session=session,
    )


async def async_subscribe_to_terminate_session_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.TerminateSessionNotification],
) -> NotificationToken:
    """
    Registers a callback to be run when a session terminates.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.TerminateSessionNotification.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection, True, api_pb2.NOTIFY_ON_TERMINATE_SESSION, callback, session=None
    )


async def async_subscribe_to_layout_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.LayoutChangedNotification],
) -> NotificationToken:
    """
    Registers a callback to be run when the relationship between sessions,
    tabs, and windows changes.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.LayoutChangedNotification.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection, True, api_pb2.NOTIFY_ON_LAYOUT_CHANGE, callback, session=None
    )


async def async_subscribe_to_focus_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.FocusChangedNotification],
) -> NotificationToken:
    """
    Registers a callback to be run when focus changes.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.FocusChangedNotification.

    :returns: A token that can be passed to unsubscribe.
    """
    return await _async_subscribe(
        connection, True, api_pb2.NOTIFY_ON_FOCUS_CHANGE, callback, session=None
    )


async def async_subscribe_to_broadcast_domains_change_notification(
    connection: Connection, callback: NotificationCallback[api_pb2.Notification]
) -> NotificationToken:
    """
    Registers a callback to be run when the current broadcast domains change.

    See also: :meth:`~iTerm2.App.parse_broadcast_domains`. Pass it
        `notification.broadcast_domains`.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.BroadcastDomainsChangedNotification.
    """
    return await _async_subscribe(
        connection, True, api_pb2.NOTIFY_ON_BROADCAST_CHANGE, callback, session=None
    )


# pylint: disable=dangerous-default-value
# pylint: disable=too-many-arguments
# pylint: disable=too-many-locals
async def async_subscribe_to_server_originated_rpc_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.Notification],
    name: str,
    arguments: Collection[str] = [],
    timeout_seconds: float | None = 5,
    defaults: Mapping[str, str] = {},
    role: api_pb2.RPCRegistrationRequest.Role.ValueType = RPC_ROLE_GENERIC,
    session_title_display_name: str | None = None,
    session_title_unique_id: str | None = None,
    status_bar_component: StatusBarComponent | None = None,
    context_menu_display_name: str | None = None,
    context_menu_unique_id: str | None = None,
    context_menu_submenu: str | None = None,
    context_menu_visible_when: str | None = None,
) -> NotificationToken:
    """
    Registers a callback to be run when the server wants to invoke an RPC.

    You probably want to use
    :meth:`~iterm2.Registration.async_register_rpc_handler` instead of this.
    It's a much higher level API.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.ServerOriginatedRPCNotification.
    :param timeout_seconds: How long iTerm2 should wait for this function to
        return or `None` to use the default timeout.
    :param defaults: Gives default values. Names correspond to argument names
        in `arguments`. Values are in-scope variables at the callsite.
    :param role: Defines the special purpose of this RPC. If none, use
        `RPC_ROLE_GENERIC`.
    :param session_title_display_name: Used by the `RPC_ROLE_SESSION_TITLE`
        role to give the name of the function to show in preferences.
    :param context_menu_display_name: Used by the `RPC_ROLE_CONTEXT_MENU`
        role to give the name of the menu item.
    :param context_menu_unique_id: Unique ID for the context menu provider.
    :param context_menu_submenu: Used by the `RPC_ROLE_CONTEXT_MENU` role to
        put the item in a submenu with this title.
    :param context_menu_visible_when: Used by the `RPC_ROLE_CONTEXT_MENU` role
        to give an expression that controls whether the item is shown.

    :returns: A token that can be passed to unsubscribe.
    """
    # pylint: disable=no-member
    rpc_registration_request = api_pb2.RPCRegistrationRequest()
    rpc_registration_request.name = name
    if timeout_seconds is not None:
        rpc_registration_request.timeout = timeout_seconds
    args: list[api_pb2.RPCRegistrationRequest.RPCArgumentSignature] = []
    for arg_name in arguments:
        arg = api_pb2.RPCRegistrationRequest.RPCArgumentSignature()
        arg.name = arg_name
        args.append(arg)
    rpc_registration_request.arguments.extend(args)
    rpc_registration_request.role = role

    if len(defaults) > 0:
        protos: list[api_pb2.RPCRegistrationRequest.RPCArgument] = []
        for default_name in defaults:
            assert default_name in arguments, (
                f"Name for default '{default_name}' not in arguments {arguments}"
            )
            path = defaults[default_name]
            argd = api_pb2.RPCRegistrationRequest.RPCArgument()
            argd.name = default_name
            argd.path = path
            protos.append(argd)

        rpc_registration_request.defaults.extend(protos)

    if session_title_display_name is not None:
        (
            rpc_registration_request.session_title_attributes.display_name
        ) = session_title_display_name
        assert session_title_unique_id
        rpc_registration_request.session_title_attributes.unique_identifier = (
            session_title_unique_id
        )
    elif status_bar_component is not None:
        status_bar_component.set_fields_in_proto(
            rpc_registration_request.status_bar_component_attributes
        )
    elif context_menu_display_name is not None:
        (
            rpc_registration_request.context_menu_attributes.display_name
        ) = context_menu_display_name
        assert context_menu_unique_id
        (
            rpc_registration_request.context_menu_attributes.unique_identifier
        ) = context_menu_unique_id
        if context_menu_submenu:
            rpc_registration_request.context_menu_attributes.submenu = (
                context_menu_submenu
            )
        if context_menu_visible_when:
            rpc_registration_request.context_menu_attributes.visible_when = (
                context_menu_visible_when
            )

    return await _async_subscribe(
        connection,
        True,
        api_pb2.NOTIFY_ON_SERVER_ORIGINATED_RPC,
        callback,
        rpc_registration_request=rpc_registration_request,
    )


# pylint: enable=dangerous-default-value
# pylint: enable=too-many-arguments
# pylint: enable=too-many-locals


async def async_subscribe_to_variable_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.VariableChangedNotification],
    scope: api_pb2.VariableScope.ValueType,
    name: str,
    identifier: str | None,
) -> NotificationToken:
    """
    Registers a callback to be invoked when a variable changes.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: an :class:`Connection`
        and iterm2.api_pb2.VariableChangedNotification.
    :param scope: A :class:`VariableScopes` enumerated value.
    :param name: The name of the variable, a string.
    :param identifier: The identifier of the object (window, tab, or session)
        being monitored, or None for app. Sometimes this will be "all" or
        "active".
    """
    # pylint: disable=no-member
    request = api_pb2.VariableMonitorRequest()
    request.name = name
    request.scope = scope
    if identifier is not None:
        request.identifier = identifier
    else:
        request.identifier = ""
    key = (
        request.scope,
        request.identifier,
        request.name,
        api_pb2.NOTIFY_ON_VARIABLE_CHANGE,
    )
    return await _async_subscribe(
        connection,
        True,
        api_pb2.NOTIFY_ON_VARIABLE_CHANGE,
        callback,
        session=None,
        variable_monitor_request=request,
        key=key,
    )


async def async_subscribe_to_profile_change_notification(
    connection: Connection,
    callback: NotificationCallback[api_pb2.Notification],
    guid: str,
) -> NotificationToken:
    """
    Register a callback to be invoked when a profile changes.

    :param connection: A connected :class:`Connection`.
    :param callback: A coroutine taking two arguments: a :class:`Connection`
        and iterm2.api_pb2.ProfileChangedNotification.
    :parm guid: The guid to monitor. A string.
    """
    request = api_pb2.ProfileChangeRequest()
    request.guid = guid
    key = (guid, api_PB2.NOTIFY_ON_PROFILE_CHANGE)  # type: ignore[name-defined]  # noqa: F821
    return await _async_subscribe(
        connection,
        True,
        api_PB2.NOTIFY_ON_PROFILE_CHANGE,  # type: ignore[name-defined]  # noqa: F821
        callback,
        session=None,
        profile_change_request=request,
        key=key,
    )


# Private --------------------------------------------------------------------


def _string_rpc_registration_request(
    rpc: api_pb2.RPCRegistrationRequest | api_pb2.ServerOriginatedRPC | None,
) -> str | None:
    """Converts ServerOriginatedRPC or RPCSignature to a string."""
    if rpc is None:
        return None
    args = sorted(x.name for x in rpc.arguments)
    return rpc.name + "(" + ",".join(args) + ")"


# pylint: disable=too-many-arguments
# pylint: disable=too-many-locals
async def _async_subscribe(
    connection: Connection,
    subscribe: bool,
    notification_type: api_pb2.NotificationType.ValueType,
    callback: NotificationCallback[Any],
    session: str | None = None,
    rpc_registration_request: api_pb2.RPCRegistrationRequest | None = None,
    keystroke_monitor_request: api_pb2.KeystrokeMonitorRequest | None = None,
    variable_monitor_request: api_pb2.VariableMonitorRequest | None = None,
    key: NotificationKey | None = None,
    profile_change_request: api_pb2.ProfileChangeRequest | None = None,
    prompt_monitor_modes: Iterable[api_pb2.PromptMonitorMode.ValueType] | None = None,
    keystroke_filter_request: api_pb2.KeystrokeFilterRequest | None = None,
) -> NotificationToken:
    """Note: session argument is ignored for variable-change notifications."""
    _register_helper_if_needed()
    token = (key or (session, notification_type), callback)

    # Register locally in case iTerm2 responds with an RPC immediately.
    # That is typical when registering a session title provider when a session
    # is already open.
    if subscribe:
        if key:
            _register_notification_handler_impl(key, callback)
        else:
            _register_notification_handler(
                session,
                _string_rpc_registration_request(rpc_registration_request),
                notification_type,
                callback,
            )

    response = await async_notification_request(
        connection,
        subscribe,
        notification_type,
        session if session is not None else "all",
        rpc_registration_request,
        keystroke_monitor_request,
        variable_monitor_request,
        profile_change_request,
        prompt_monitor_modes,
        keystroke_filter_request,
    )
    status = response.notification_response.status
    # pylint: disable=no-member
    status_ok = status == api_pb2.NotificationResponse.Status.Value("OK")

    unregister = False
    if subscribe:
        already = status == api_pb2.NotificationResponse.Status.Value(
            "ALREADY_SUBSCRIBED"
        )
        if status_ok or already:
            return token
        # Uh oh, undo the registration.
        unregister = True
    else:
        # Unsubscribe
        if status_ok:
            unregister = True

    if unregister:
        if key:
            _unregister_notification_handler_impl(key, callback)
        else:
            _unregister_notification_handler(
                session,
                _string_rpc_registration_request(rpc_registration_request),
                notification_type,
                callback,
            )

        if not subscribe and status_ok:
            # Normal code path for unsubscribe
            return None  # type: ignore[return-value]

    # pylint: disable=no-member
    raise SubscriptionException(api_pb2.NotificationResponse.Status.Name(status))


# pylint: enable=too-many-arguments
# pylint: enable=too-many-locals


def _register_helper_if_needed():
    global _have_registered_helper  # pylint: disable=global-statement
    if not _have_registered_helper:
        _have_registered_helper = True
        Connection.register_helper(_async_dispatch_helper)


async def _async_dispatch_helper(
    connection: Connection, message: api_pb2.ServerOriginatedMessage
) -> bool:
    handlers, sub_notification = _get_notification_handlers(message)
    for handler in handlers:
        assert handler is not None
        await handler(connection, sub_notification)

    if not handlers and message.notification.HasField(
        "server_originated_rpc_notification"
    ):
        # If we get an RPC we haven't registered for handle the error because
        # otherwise it has to time out. If you get here there is probably a
        # bug.
        key, _sub_notification = _get_handler_key_from_notification(
            message.notification
        )
        exception = {
            "reason": "No such function: {} (key was {})".format(
                _string_rpc_registration_request(
                    message.notification.server_originated_rpc_notification.rpc
                ),
                key,
            )
        }
        await async_send_rpc_result(
            connection,
            (message.notification.server_originated_rpc_notification.request_id),
            True,
            exception,
        )

    return bool(handlers)


def _get_all_sessions_handler_keys_from_notification(
    notification: api_pb2.Notification, standard_key: NotificationKey
) -> list[NotificationKey]:
    """Returns keys into _handlers for a notification for the caller may
    have registered for all sessions/windows.

    :param standard_key: The key from _get_handler_key_from_notification.
    """
    if notification.HasField("variable_changed_notification"):
        return [
            (
                api_pb2.VariableScope.Value("SESSION"),
                "all",
                notification.variable_changed_notification.name,
                api_pb2.NOTIFY_ON_VARIABLE_CHANGE,
            ),
            (
                api_pb2.VariableScope.Value("WINDOW"),
                "all",
                notification.variable_changed_notification.name,
                api_pb2.NOTIFY_ON_VARIABLE_CHANGE,
            ),
        ]
    # Convert a session-specific key into an all-sessions key.
    return [(None, standard_key[1])]


# pylint: disable=too-many-branches
def _get_handler_key_from_notification(
    notification: api_pb2.Notification,
) -> tuple[NotificationKey | None, Message]:
    """Returns the handler key for a notification and the message to pass to
    its handlers, which is a sub-message for most notification types."""
    key: NotificationKey | None = None
    sub_notification: Message = notification

    if notification.HasField("keystroke_notification"):
        key = (notification.keystroke_notification.session, api_pb2.NOTIFY_ON_KEYSTROKE)
        sub_notification = notification.keystroke_notification
    elif notification.HasField("screen_update_notification"):
        key = (
            notification.screen_update_notification.session,
            api_pb2.NOTIFY_ON_SCREEN_UPDATE,
        )
        sub_notification = notification.screen_update_notification
    elif notification.HasField("prompt_notification"):
        key = (notification.prompt_notification.session, api_pb2.NOTIFY_ON_PROMPT)
        sub_notification = notification.prompt_notification
    elif notification.HasField("location_change_notification"):
        key = (
            notification.location_change_notification.session,  # pyright: ignore[reportDeprecated]
            api_pb2.NOTIFY_ON_LOCATION_CHANGE,
        )
        sub_notification = notification.location_change_notification  # pyright: ignore[reportDeprecated]
    elif notification.HasField("custom_escape_sequence_notification"):
        key = (
            notification.custom_escape_sequence_notification.session,
            api_pb2.NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE,
        )
        sub_notification = notification.custom_escape_sequence_notification
    elif notification.HasField("new_session_notification"):
        key = (None, api_pb2.NOTIFY_ON_NEW_SESSION)
        sub_notification = notification.new_session_notification
    elif notification.HasField("terminate_session_notification"):
        key = (None, api_pb2.NOTIFY_ON_TERMINATE_SESSION)
        sub_notification = notification.terminate_session_notification
    elif notification.HasField("layout_changed_notification"):
        key = (None, api_pb2.NOTIFY_ON_LAYOUT_CHANGE)
        sub_notification = notification.layout_changed_notification
    elif notification.HasField("focus_changed_notification"):
        key = (None, api_pb2.NOTIFY_ON_FOCUS_CHANGE)
        sub_notification = notification.focus_changed_notification
    elif notification.HasField("server_originated_rpc_notification"):
        key = (
            None,
            api_pb2.NOTIFY_ON_SERVER_ORIGINATED_RPC,
            _string_rpc_registration_request(
                notification.server_originated_rpc_notification.rpc
            ),
        )
    elif notification.HasField("broadcast_domains_changed"):
        key = (None, api_pb2.NOTIFY_ON_BROADCAST_CHANGE)
    elif notification.HasField("variable_changed_notification"):
        key = (
            notification.variable_changed_notification.scope,
            notification.variable_changed_notification.identifier,
            notification.variable_changed_notification.name,
            api_pb2.NOTIFY_ON_VARIABLE_CHANGE,
        )
        sub_notification = notification.variable_changed_notification
    elif notification.HasField("profile_changed_notification"):
        key = (
            notification.profile_changed_notification.guid,
            api_pb2.NOTIFY_ON_PROFILE_CHANGE,
        )
    return key, sub_notification


# pylint: enable=too-many-branches


def _get_notification_handlers(
    message: api_pb2.ServerOriginatedMessage,
) -> tuple[list[NotificationCallback[Any]], Message | None]:
    key, sub_notification = _get_handler_key_from_notification(message.notification)
    if key is None:
        return ([], None)

    # These keys catch "all"-style subscriptions.
    all_objects_keys = _get_all_sessions_handler_keys_from_notification(
        message.notification, key
    )

    if key in _handlers:
        return (_handlers[key], sub_notification)
    for all_objects_key in all_objects_keys:
        if all_objects_key in _handlers:
            return (_handlers[all_objects_key], sub_notification)
    return ([], None)


def _register_notification_handler(
    session: str | None,
    rpc_registration_request: str | None,
    notification_type: api_pb2.NotificationType.ValueType,
    coro: NotificationCallback[Any],
) -> None:
    assert coro is not None

    key: NotificationKey
    if rpc_registration_request is None:
        key = (session, notification_type)
    else:
        key = (session, notification_type, rpc_registration_request)
    _register_notification_handler_impl(key, coro)


def _register_notification_handler_impl(
    key: NotificationKey, coro: NotificationCallback[Any]
) -> None:
    _handlers.setdefault(key, []).append(coro)


def _unregister_notification_handler(
    session: str | None,
    rpc_registration_request: str | None,
    notification_type: api_pb2.NotificationType.ValueType,
    coro: NotificationCallback[Any],
) -> None:
    assert coro is not None

    key: NotificationKey
    if rpc_registration_request is None:
        key = (session, notification_type)
    else:
        key = (session, notification_type, rpc_registration_request)
    _unregister_notification_handler_impl(key, coro)


def _unregister_notification_handler_impl(
    key: NotificationKey, coro: NotificationCallback[Any]
) -> None:
    if coro in _handlers.get(key, ()):
        _handlers[key].remove(coro)
