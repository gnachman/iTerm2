"""Provides methods that build and send RPCs to iTerm2."""

from __future__ import annotations

import itertools
import json
from collections.abc import Iterable, Mapping, Sequence
from typing import TYPE_CHECKING, Any

from . import api_pb2

if TYPE_CHECKING:
    from .connection import Connection
    from .selection import Selection
    from .util import Size, WindowedCoordRange

ACTIVATE_RAISE_ALL_WINDOWS: int = 1
ACTIVATE_IGNORING_OTHER_APPS: int = 2


# pylint and protobufs can't be friends so disable a bunch of stuff.
# pylint: disable=no-member
# pylint: disable=too-many-arguments


class RPCException(Exception):
    """
    Raised when a response contains an error signaling a malformed request."""


# APIs -----------------------------------------------------------------------


async def async_list_sessions(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """
    Requests a list of sessions.

    connection: A connected iterm2.Connection

    Returns: iterm2.api_pb2.ListSessionsResponse
    """
    request = _alloc_request()
    request.list_sessions_request.SetInParent()
    return await _async_call(connection, request)


async def async_notification_request(
    connection: Connection,
    subscribe: bool,
    notification_type: api_pb2.NotificationType.ValueType,
    session: str | None = None,
    rpc_registration_request: api_pb2.RPCRegistrationRequest | None = None,
    keystroke_monitor_request: api_pb2.KeystrokeMonitorRequest | None = None,
    variable_monitor_request: api_pb2.VariableMonitorRequest | None = None,
    profile_change_request: api_pb2.ProfileChangeRequest | None = None,
    prompt_monitor_modes: Iterable[api_pb2.PromptMonitorMode.ValueType] | None = None,
    keystroke_filter_request: api_pb2.KeystrokeFilterRequest | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Requests a change to a notification subscription.

    connection: A connected iterm2.Connection
    subscribe: True to subscribe, False to unsubscribe
    notification_type: iterm2.api_pb2.NotificationType
    session: The unique ID of the session or None.
    rpc_registration_request: The RPC registration request (only for
        registering an RPC handler) or None.
    keystroke_monitor_request: The keyboard monitor request (only for
        registering a keystroke handler) or None.
    variable_monitor_request: The variable monitor request (only for
        registering a variable monitor) or None.
    profile_change_request: The profile monitor request (only for registering a
        profile change monitor) or None.
    prompt_monitor_modes: The prompt monitor modes (only for registering a
        prompt monitor) or None.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()

    request.notification_request.SetInParent()
    if session is not None:
        request.notification_request.session = session
    if rpc_registration_request is not None:
        request.notification_request.rpc_registration_request.CopyFrom(
            rpc_registration_request
        )
    if keystroke_monitor_request:
        request.notification_request.keystroke_monitor_request.CopyFrom(
            keystroke_monitor_request
        )
    if keystroke_filter_request:
        request.notification_request.keystroke_filter_request.CopyFrom(
            keystroke_filter_request
        )
    if variable_monitor_request:
        request.notification_request.variable_monitor_request.CopyFrom(
            variable_monitor_request
        )
    if profile_change_request:
        request.notification_request.profile_change_request.CopyFrom(
            profile_change_request
        )
    if prompt_monitor_modes:
        for mode in prompt_monitor_modes:
            request.notification_request.prompt_monitor_request.modes.append(mode)
    request.notification_request.subscribe = subscribe
    request.notification_request.notification_type = notification_type
    return await _async_call(connection, request)


async def async_send_text(
    connection: Connection, session: str, text: str, suppress_broadcast: bool
) -> api_pb2.ServerOriginatedMessage:
    """
    Sends text to a session, as though it had been typed.

    connection: A connected iterm2.Connection.
    session: A session ID.
    text: String to send although it had been typed by the user.
    suppress_broadcast: If True, input goes only to the specified session even
        if broadcasting is on.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.send_text_request.session = session
    request.send_text_request.text = text
    request.send_text_request.suppress_broadcast = suppress_broadcast
    return await _async_call(connection, request)


async def async_screenshot(
    connection: Connection, session: str
) -> api_pb2.ServerOriginatedMessage:
    """
    Captures a PNG screenshot of a session's visible screen contents.

    connection: A connected iterm2.Connection.
    session: A session ID.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.screenshot_request.session = session
    return await _async_call(connection, request)


async def async_split_pane(
    connection: Connection,
    session: str | None,
    vertical: bool,
    before: bool,
    profile: str | None = None,
    profile_customizations: Mapping[str, str | None] | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Splits a session into two.

    connection: A connected iterm2.Connection.
    session: Session ID to split
    vertical: Bool, whether the divider should be vertical
    before: Bool, whether the new session should be left/above the existing
        one.
    profile: The profile name to use. None for the default profile.
    profile_customizations: None, or a dictionary of overrides.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.split_pane_request.SetInParent()
    if session is not None:
        request.split_pane_request.session = session
    if vertical:
        request.split_pane_request.split_direction = api_pb2.SplitPaneRequest.VERTICAL
    else:
        request.split_pane_request.split_direction = api_pb2.SplitPaneRequest.HORIZONTAL
    request.split_pane_request.before = before
    if profile is not None:
        request.split_pane_request.profile_name = profile
    if profile_customizations is not None:
        request.split_pane_request.custom_profile_properties.extend(
            _profile_properties_from_dict(profile_customizations)
        )

    return await _async_call(connection, request)


def _profile_properties_from_dict(profile_customizations: Mapping[str, str | None]):
    props: list[api_pb2.ProfileProperty] = []
    for key in profile_customizations:
        value = profile_customizations[key]
        entry = api_pb2.ProfileProperty()
        entry.key = key
        entry.json_value = value or "null"
        props.append(entry)
    return props


async def async_create_tab(
    connection: Connection,
    profile: str | None = None,
    window: str | None = None,
    index: int | None = None,
    command: str | None = None,
    profile_customizations: Mapping[str, str | None] | None = None,
    select: bool = True,
) -> api_pb2.ServerOriginatedMessage:
    """
    Creates a new tab or window.

    connection: A connected iterm2.Connection.
    profile: The profile name to use. None for the default profile.
    window: The window ID in which to add a tab, or None to create a new
        window.
    index: The index within the window, from 0 to (num tabs)-1
    command: The command to run in the new session, or None for its default
        behavior.
    profile_customizations: None, or a dictionary of overrides.
    select: If True (the default), select the new tab and order its window to
        the front. If False, create the tab in the background without moving
        keyboard focus. A brand-new window is always ordered front.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.create_tab_request.SetInParent()
    request.create_tab_request.select_tab = select
    if profile is not None:
        request.create_tab_request.profile_name = profile
    if window is not None:
        request.create_tab_request.window_id = window
    if index is not None:
        request.create_tab_request.tab_index = index
    if command is not None:
        # Layer the command on top of any other customizations so both apply.
        # Values are JSON-encoded, as in LocalWriteOnlyProfile.values (which
        # can't be used here because the profile module imports this one).
        profile_customizations = {
            **(profile_customizations or {}),
            "Custom Command": json.dumps("Yes"),
            "Command": json.dumps(command),
        }
    if profile_customizations is not None:
        request.create_tab_request.custom_profile_properties.extend(
            _profile_properties_from_dict(profile_customizations)
        )
    return await _async_call(connection, request)


async def async_get_screen_contents(
    connection: Connection,
    session: str | None,
    windowed_coord_range: WindowedCoordRange | None = None,
    style: bool = False,
) -> api_pb2.ServerOriginatedMessage:
    """
    Gets screen contents, including both the mutable area and history.

    connection: A connected iterm2.Connection.
    session: Session ID
    windowed_coord_range: The range of characters to fetch.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    if session is not None:
        request.get_buffer_request.session = session
    request.get_buffer_request.include_styles = style
    if windowed_coord_range:
        request.get_buffer_request.line_range.windowed_coord_range.CopyFrom(
            windowed_coord_range.proto
        )
    else:
        request.get_buffer_request.line_range.screen_contents_only = True
    return await _async_call(connection, request)


async def async_get_prompt(
    connection: Connection, session: str | None = None, prompt_id: str | None = None
) -> api_pb2.ServerOriginatedMessage:
    """
    Gets info about the last prompt in a session

    connection: A connected iterm2.Connection.
    session: Session ID
    prompt_id: Optional prompt ID

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.get_prompt_request.SetInParent()
    if session is not None:
        request.get_prompt_request.session = session
    if prompt_id:
        request.get_prompt_request.unique_prompt_id = prompt_id
    return await _async_call(connection, request)


async def async_list_prompts(
    connection: Connection, session: str, first: str | None, last: str | None
) -> api_pb2.ServerOriginatedMessage:
    """
    Fetches a list of prompts in a session.

    connection: A connected iterm2.Connection.
    session: Session ID
    first: First prompt ID or None
    lats: Last prompt ID or none

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.list_prompts_request.SetInParent()
    request.list_prompts_request.session = session
    if first:
        request.list_prompts_request.first_unique_id = first
    if last:
        request.list_prompts_request.last_unique_id = last
    return await _async_call(connection, request)


async def async_start_transaction(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """
    Begins a transaction, locking iTerm2 until the transaction ends. Be careful
    with this.

    connection: A connected iterm2.Connection.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.transaction_request.begin = True
    return await _async_call(connection, request)


async def async_end_transaction(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """
    Ends a transaction begun with start_transaction()

    connection: A connected iterm2.Connection.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.transaction_request.begin = False
    return await _async_call(connection, request)


async def async_register_web_view_tool(
    connection: Connection,
    display_name: str,
    identifier: str,
    reveal_if_already_registered: bool,
    url: str,
) -> api_pb2.ServerOriginatedMessage:
    """
    Registers a toolbelt tool showing a webview.

    connection: A connected iterm2.Connection.
    display_name: The name of the tool. User-visible.
    identifier: A unique ID that prevents duplicate registration.
    reveal_if_already_registered: Bool. If true, shows the tool on a duplicate
        registration attempt.
    url: The URL to show in the webview.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.register_tool_request.name = display_name
    request.register_tool_request.identifier = identifier
    request.register_tool_request.reveal_if_already_registered = (
        reveal_if_already_registered
    )
    request.register_tool_request.tool_type = (
        api_pb2.RegisterToolRequest.ToolType.Value("WEB_VIEW_TOOL")
    )
    request.register_tool_request.URL = url
    return await _async_call(connection, request)


async def async_set_profile_property(
    connection: Connection,
    session_id: str | None,
    key: str,
    value: Any,
    guids: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Sets a property of a session's profile.
    TODO: Add async_set_profile_properties and deprecate this.

    :param connection: A connected iterm2.Connection.
    :param session_id: Session ID to modify or None. If None, guids must be
        set.
    :param key: The key to set
    :param value: a Python object, whose type depends on the key
    :param guids: List of GUIDs of the profile to modify or None. If None,
        session_id must be set.

    :returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    return await async_set_profile_property_json(
        connection, session_id, key, json.dumps(value), guids
    )


async def async_set_profile_property_json(
    connection: Connection,
    session_id: str | None,
    key: str,
    json_value: str,
    guids: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """Like async_set_profile_property but takes a json-encoded value.
    DEPRECATED. Prefer async_set_profile_properties_json."""
    request = _alloc_request()
    if session_id is None:
        request.set_profile_property_request.guid_list.guids.extend(guids)
    else:
        request.set_profile_property_request.session = session_id
    request.set_profile_property_request.key = key
    request.set_profile_property_request.json_value = json_value
    return await _async_call(connection, request)


async def async_set_profile_properties_json(
    connection: Connection,
    session_id: str | None,
    assignments: Iterable[Sequence[str]],
    guids: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """Like async_set_profile_properties but takes a json-encoded value."""
    request = _alloc_request()
    if session_id is None:
        request.set_profile_property_request.guid_list.guids.extend(guids)
    else:
        request.set_profile_property_request.session = session_id
    protos: list[api_pb2.SetProfilePropertyRequest.Assignment] = []
    for assignment in assignments:
        value = api_pb2.SetProfilePropertyRequest.Assignment()
        value.key = assignment[0]
        value.json_value = assignment[1]
        protos.append(value)
    request.set_profile_property_request.assignments.extend(protos)
    return await _async_call(connection, request)


async def async_get_profile(
    connection: Connection,
    session: str | None = None,
    keys: Iterable[str] | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Fetches a session's profile

    connection: A connected iterm2.Connection.
    session: Session ID
    keys: The set of keys to fetch

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.get_profile_property_request.SetInParent()
    if session is not None:
        request.get_profile_property_request.session = session
    if keys is not None:
        for key in keys:
            request.get_profile_property_request.keys.append(key)
    return await _async_call(connection, request)


async def async_set_property(
    connection: Connection,
    name: str,
    json_value: str,
    window_id: str | None = None,
    session_id: str | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Sets a property of an object (currently only of a window).
    """
    assert (window_id is not None) or (session_id is not None)
    request = _alloc_request()
    request.set_property_request.SetInParent()
    if window_id is not None:
        request.set_property_request.window_id = window_id
    elif session_id is not None:
        request.set_property_request.session_id = session_id
    request.set_property_request.name = name
    request.set_property_request.json_value = json_value
    return await _async_call(connection, request)


async def async_get_property(
    connection: Connection,
    name: str,
    window_id: str | None = None,
    session_id: str | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Gets a property of a window or session.
    """
    request = _alloc_request()
    request.get_property_request.SetInParent()
    if window_id:
        request.get_property_request.window_id = window_id
    elif session_id:
        request.get_property_request.session_id = session_id
    request.get_property_request.name = name
    return await _async_call(connection, request)


async def async_inject(
    connection: Connection, data: bytes, sessions: Iterable[str]
) -> api_pb2.ServerOriginatedMessage:
    """
    Injects bytes/string into sessions, as though it was program output.
    """
    request = _alloc_request()
    request.inject_request.SetInParent()
    request.inject_request.session_id.extend(sessions)
    request.inject_request.data = data
    return await _async_call(connection, request)


async def async_activate(
    connection: Connection,
    select_session: bool,
    select_tab: bool,
    order_window_front: bool,
    session_id: str | None = None,
    tab_id: str | None = None,
    window_id: str | None = None,
    activate_app_opts: Sequence[int] | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Activates a session, tab, or window.
    """
    request = _alloc_request()
    if session_id is not None:
        request.activate_request.session_id = session_id
    if tab_id is not None:
        request.activate_request.tab_id = tab_id
    if window_id is not None:
        request.activate_request.window_id = window_id
    if activate_app_opts is not None:
        request.activate_request.activate_app.SetInParent()
        if ACTIVATE_RAISE_ALL_WINDOWS in activate_app_opts:
            request.activate_request.activate_app.raise_all_windows = True
        if ACTIVATE_IGNORING_OTHER_APPS:
            request.activate_request.activate_app.ignoring_other_apps = True
    request.activate_request.order_window_front = order_window_front
    request.activate_request.select_tab = select_tab
    request.activate_request.select_session = select_session
    return await _async_call(connection, request)


async def async_variable(
    connection: Connection,
    session_id: str | None = None,
    sets: Iterable[tuple[str, str]] | None = None,
    gets: Iterable[str] | None = None,
    tab_id: str | None = None,
    window_id: str | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Gets or sets session variables.

    `sets` are JSON encoded. The resulting gets will be JSON encoded.
    """
    if not sets:
        sets = []
    if not gets:
        gets = []
    request = _alloc_request()
    if session_id:
        request.variable_request.session_id = session_id
    elif tab_id:
        request.variable_request.tab_id = tab_id
    elif window_id:
        request.variable_request.window_id = window_id
    else:
        request.variable_request.app = True

    request.variable_request.get.extend(gets)
    for name, value in sets:
        kvp = api_pb2.VariableRequest.Set()
        kvp.name = name
        kvp.value = value
        request.variable_request.set.extend([kvp])
    return await _async_call(connection, request)


async def async_save_arrangement(
    connection: Connection, name: str, window_id: str | None = None
) -> api_pb2.ServerOriginatedMessage:
    """
    Save a window arrangement.
    """
    request = _alloc_request()
    request.saved_arrangement_request.name = name
    request.saved_arrangement_request.action = (
        api_pb2.SavedArrangementRequest.Action.Value("SAVE")
    )
    if window_id is not None:
        request.saved_arrangement_request.window_id = window_id
    return await _async_call(connection, request)


async def async_restore_arrangement(
    connection: Connection, name: str, window_id: str | None = None
) -> api_pb2.ServerOriginatedMessage:
    """
    Restore a window arrangement.
    """
    request = _alloc_request()
    request.saved_arrangement_request.name = name
    request.saved_arrangement_request.action = (
        api_pb2.SavedArrangementRequest.Action.Value("RESTORE")
    )
    if window_id is not None:
        request.saved_arrangement_request.window_id = window_id
    return await _async_call(connection, request)


async def async_list_arrangements(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """
    Fetch a list of window arrangement names.
    """
    request = _alloc_request()
    request.saved_arrangement_request.action = (
        api_pb2.SavedArrangementRequest.Action.Value("LIST")
    )
    return await _async_call(connection, request)


async def async_get_focus_info(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """
    Fetches the focused state of everything.
    """
    request = _alloc_request()
    request.focus_request.SetInParent()
    return await _async_call(connection, request)


async def async_list_profiles(
    connection: Connection,
    guids: Iterable[str] | None,
    properties: Iterable[str] | None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Gets a list of all profiles.

    :param guid: If None, get all profiles. Otherwise, a list of GUIDs
        (strings) to fetch.
    :param properties: If None, get all properties. Otherwise, a list of
        strings giving property keys to fetch.
    """
    request = _alloc_request()
    request.list_profiles_request.SetInParent()
    if guids is not None:
        request.list_profiles_request.guids.extend(guids)
    if properties is not None:
        request.list_profiles_request.properties.extend(properties)
    return await _async_call(connection, request)


async def async_send_rpc_result(
    connection: Connection, request_id: str, is_exception: bool, value: Any
) -> api_pb2.ServerOriginatedMessage:
    """Sends an RPC response."""
    request = _alloc_request()
    request.server_originated_rpc_result_request.request_id = request_id
    if is_exception:
        (request.server_originated_rpc_result_request.json_exception) = json.dumps(
            value
        )
    else:
        request.server_originated_rpc_result_request.json_value = json.dumps(value)
    return await _async_call(connection, request)


async def async_restart_session(
    connection: Connection, session_id: str, only_if_exited: bool
) -> api_pb2.ServerOriginatedMessage:
    """Restarts a session."""
    request = _alloc_request()
    request.restart_session_request.SetInParent()
    request.restart_session_request.session_id = session_id
    request.restart_session_request.only_if_exited = only_if_exited
    return await _async_call(connection, request)


async def async_menu_item(
    connection: Connection, identifier: str, query_only: bool
) -> api_pb2.ServerOriginatedMessage:
    """Selects or queries a menu item."""
    request = _alloc_request()
    request.menu_item_request.SetInParent()
    request.menu_item_request.identifier = identifier
    request.menu_item_request.query_only = query_only
    return await _async_call(connection, request)


async def async_set_tab_layout(
    connection: Connection, tab_id: str, tree: api_pb2.SplitTreeNode
) -> api_pb2.ServerOriginatedMessage:
    """Adjusts the layout of split panes in a tab.

    :param tree: a `iterm2.api_pb2.SplitTreeNode` forming the root of the tree.
    """
    request = _alloc_request()
    request.set_tab_layout_request.SetInParent()
    request.set_tab_layout_request.tab_id = tab_id
    request.set_tab_layout_request.root.CopyFrom(tree)
    return await _async_call(connection, request)


async def async_get_broadcast_domains(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """Fetches the current broadcast domains."""
    request = _alloc_request()
    request.get_broadcast_domains_request.SetInParent()
    return await _async_call(connection, request)


async def async_rpc_list_tmux_connections(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """Requests a list of tmux connections."""
    _assert_not_in_transaction()
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.list_connections.SetInParent()
    return await _async_call(connection, request)


async def async_rpc_send_tmux_command(
    connection: Connection, tmux_connection_id: str, command: str
) -> api_pb2.ServerOriginatedMessage:
    """Sends a command to the tmux server."""
    _assert_not_in_transaction()
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.send_command.SetInParent()
    request.tmux_request.send_command.connection_id = tmux_connection_id
    request.tmux_request.send_command.command = command
    return await _async_call(connection, request)


async def async_rpc_set_tmux_window_visible(
    connection: Connection, tmux_connection_id: str, window_id: str, visible: bool
) -> api_pb2.ServerOriginatedMessage:
    """Hides/shows a tmux window (which is an iTerm2 tab)"""
    _assert_not_in_transaction()
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.set_window_visible.SetInParent()
    request.tmux_request.set_window_visible.connection_id = tmux_connection_id
    request.tmux_request.set_window_visible.window_id = window_id
    request.tmux_request.set_window_visible.visible = visible
    return await _async_call(connection, request)


async def async_rpc_create_tmux_window(
    connection: Connection, tmux_connection_id: str, affinity: str | None = None
) -> api_pb2.ServerOriginatedMessage:
    """Creates a new tmux window."""
    _assert_not_in_transaction()
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.create_window.SetInParent()
    request.tmux_request.create_window.connection_id = tmux_connection_id
    if affinity:
        request.tmux_request.create_window.affinity = affinity
    return await _async_call(connection, request)


async def async_reorder_tabs(
    connection: Connection, assignments: Iterable[tuple[str, Iterable[str]]]
) -> api_pb2.ServerOriginatedMessage:
    """Reassigns tabs to windows and specifies their orders.

    :param assignments: a list of tuples of (window_id, [tab_id, ...])
    """
    request = _alloc_request()
    request.reorder_tabs_request.SetInParent()

    def make_assignment(window_id: str, tab_ids: Iterable[str]):
        assignment = api_pb2.ReorderTabsRequest.Assignment()
        assignment.window_id = window_id
        assignment.tab_ids.extend(tab_ids)
        return assignment

    protos = [make_assignment(a[0], a[1]) for a in assignments]
    request.reorder_tabs_request.assignments.extend(protos)
    return await _async_call(connection, request)


async def async_get_default_profile(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """Gets the default profile."""
    request = _alloc_request()
    request.preferences_request.SetInParent()
    my_request = api_pb2.PreferencesRequest.Request()
    my_request.get_default_profile_request.SetInParent()
    request.preferences_request.requests.extend([my_request])
    return await _async_call(connection, request)


async def async_set_default_profile(
    connection: Connection, guid: str
) -> api_pb2.ServerOriginatedMessage:
    """Sets the default profile."""
    request = _alloc_request()
    request.preferences_request.SetInParent()
    my_request = api_pb2.PreferencesRequest.Request()
    my_request.set_default_profile_request.SetInParent()
    my_request.set_default_profile_request.guid = guid
    request.preferences_request.requests.extend([my_request])
    return await _async_call(connection, request)


async def async_get_preference(
    connection: Connection, key: str
) -> api_pb2.ServerOriginatedMessage:
    """Gets a preference from user defaults."""
    request = _alloc_request()
    request.preferences_request.SetInParent()
    my_request = api_pb2.PreferencesRequest.Request()
    my_request.get_preference_request.SetInParent()
    my_request.get_preference_request.key = key
    request.preferences_request.requests.extend([my_request])
    return await _async_call(connection, request)


async def async_set_preference(
    connection: Connection, key: str, value: str
) -> api_pb2.ServerOriginatedMessage:
    """Sets a preference in user defaults."""
    request = _alloc_request()
    request.preferences_request.SetInParent()
    my_request = api_pb2.PreferencesRequest.Request()
    my_request.set_preference_request.SetInParent()
    my_request.set_preference_request.key = key
    my_request.set_preference_request.json_value = value
    request.preferences_request.requests.extend([my_request])
    return await _async_call(connection, request)


async def async_list_color_presets(
    connection: Connection,
) -> api_pb2.ServerOriginatedMessage:
    """Gets a list of color preset names."""
    request = _alloc_request()
    request.color_preset_request.SetInParent()
    request.color_preset_request.list_presets.SetInParent()
    return await _async_call(connection, request)


async def async_get_color_preset(
    connection: Connection, name: str
) -> api_pb2.ServerOriginatedMessage:
    """Gets the content of a color preset by name."""
    request = _alloc_request()
    request.color_preset_request.SetInParent()
    request.color_preset_request.get_preset.SetInParent()
    request.color_preset_request.get_preset.name = name
    return await _async_call(connection, request)


async def async_get_selection(
    connection: Connection, session_id: str
) -> api_pb2.ServerOriginatedMessage:
    """
    Return info about the current selected text.
    """
    request = _alloc_request()
    request.selection_request.get_selection_request.SetInParent()
    request.selection_request.get_selection_request.session_id = session_id
    return await _async_call(connection, request)


async def async_set_selection(
    connection: Connection, session_id: str, selection: Selection
) -> api_pb2.ServerOriginatedMessage:
    """
    Set the selected text ranges.
    """
    request = _alloc_request()
    request.selection_request.set_selection_request.SetInParent()
    request.selection_request.set_selection_request.session_id = session_id
    request.selection_request.set_selection_request.selection.SetInParent()
    for sub in selection.subSelections:
        (
            request.selection_request.set_selection_request.selection.sub_selections.extend(
                [sub.proto]
            )
        )
    return await _async_call(connection, request)


async def async_open_status_bar_component_popover(
    connection: Connection, identifier: str, session_id: str, html: str, size: Size
) -> api_pb2.ServerOriginatedMessage:
    """
    Send a request to open a popover.
    """
    request = _alloc_request()
    request.status_bar_component_request.SetInParent()
    request.status_bar_component_request.identifier = identifier
    request.status_bar_component_request.open_popover.session_id = session_id
    request.status_bar_component_request.open_popover.html = html
    request.status_bar_component_request.open_popover.size.CopyFrom(size.proto)
    return await _async_call(connection, request)


async def async_set_broadcast_domains(
    connection: Connection, list_of_list_of_session_ids: Iterable[Iterable[str]]
) -> api_pb2.ServerOriginatedMessage:
    """
    Send a request to set the current broadcast domains.
    """
    request = _alloc_request()
    request.set_broadcast_domains_request.SetInParent()
    domains_protos: list[api_pb2.BroadcastDomain] = []
    for list_of_session_ids in list_of_list_of_session_ids:
        proto = api_pb2.BroadcastDomain()
        proto.session_ids.extend(list_of_session_ids)
        domains_protos.append(proto)
    request.set_broadcast_domains_request.broadcast_domains.extend(domains_protos)
    return await _async_call(connection, request)


async def async_close(
    connection: Connection,
    sessions: Iterable[str] | None = None,
    tabs: Iterable[str] | None = None,
    windows: Iterable[str] | None = None,
    force: bool = False,
) -> api_pb2.ServerOriginatedMessage:
    """
    Send a close request.
    """
    request = _alloc_request()
    request.close_request.SetInParent()
    assert sessions or tabs or windows
    if sessions:
        assert not tabs and not windows
        request.close_request.sessions.session_ids.extend(sessions)
    elif tabs:
        assert not sessions and not windows
        request.close_request.tabs.tab_ids.extend(tabs)
    else:
        assert not sessions and not tabs
        request.close_request.windows.window_ids.extend(windows)
    request.close_request.force = force
    return await _async_call(connection, request)


async def async_invoke_function(
    connection: Connection,
    invocation: str,
    session_id: str | None = None,
    tab_id: str | None = None,
    window_id: str | None = None,
    timeout: float = -1,
    receiver: str | None = None,
) -> api_pb2.ServerOriginatedMessage:
    """
    Invoke a function in iTerm2, possibly as a method call on an object.
    """
    request = _alloc_request()
    request.invoke_function_request.SetInParent()
    request.invoke_function_request.invocation = invocation
    if receiver:
        request.invoke_function_request.method.receiver = receiver
    elif session_id:
        request.invoke_function_request.session.session_id = session_id
    elif tab_id:
        request.invoke_function_request.tab.tab_id = tab_id
    elif window_id:
        request.invoke_function_request.window.window_id = window_id
    else:
        request.invoke_function_request.app.SetInParent()
    request.invoke_function_request.timeout = timeout
    return await _async_call(connection, request)


def _invocation_result(response: api_pb2.ServerOriginatedMessage) -> Any:
    """Unwraps an invoke-function response, raising RPCException on error."""
    which = response.invoke_function_response.WhichOneof("disposition")
    if which == "error":
        if (
            response.invoke_function_response.error.status
            == api_pb2.InvokeFunctionResponse.Status.Value("TIMEOUT")
        ):
            raise RPCException("Timeout")
        raise RPCException(
            "{}: {}".format(
                api_pb2.InvokeFunctionResponse.Status.Name(
                    response.invoke_function_response.error.status
                ),
                response.invoke_function_response.error.error_reason,
            )
        )
    return json.loads(response.invoke_function_response.success.json_result)


async def async_invoke_method(
    connection: Connection, receiver: str, invocation: str, timeout: float
) -> Any:
    """Convenience wrapper around async_invoke_function for methods."""
    assert receiver
    response = await async_invoke_function(
        connection, invocation, receiver=receiver, timeout=timeout
    )
    return _invocation_result(response)


async def async_invoke_app_function(
    connection: Connection, invocation: str, timeout: float = -1
) -> Any:
    """Convenience wrapper for invoking an app-scope (receiver-less) function."""
    response = await async_invoke_function(connection, invocation, timeout=timeout)
    return _invocation_result(response)


# Private --------------------------------------------------------------------


_next_id = itertools.count()


def _alloc_id():
    return next(_next_id)


def _alloc_request():
    request = api_pb2.ClientOriginatedMessage()
    request.id = _alloc_id()
    return request


async def _async_call(
    connection: Connection, request: api_pb2.ClientOriginatedMessage
) -> api_pb2.ServerOriginatedMessage:
    await connection.async_send_message(request)
    response = await connection.async_dispatch_until_id(request.id)
    if response.HasField("error"):
        raise RPCException(response.error)
    return response


def _assert_not_in_transaction():
    # Imported here because the transaction module imports this one.
    from .transaction import Transaction

    assert not Transaction.current()
