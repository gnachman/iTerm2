"""Provides methods that build and send RPCs to iTerm2."""
import json

import iterm2.api_pb2
import iterm2.connection

ACTIVATE_RAISE_ALL_WINDOWS = 1
ACTIVATE_IGNORING_OTHER_APPS = 2

class RPCException(Exception):
    """Raised when a response contains an error signaling a malformed request."""
    pass

## APIs -----------------------------------------------------------------------

async def async_list_sessions(connection):
    """
    Requests a list of sessions.

    connection: A connected iterm2.Connection

    Returns: iterm2.api_pb2.ListSessionsResponse
    """
    request = _alloc_request()
    request.list_sessions_request.SetInParent()
    return await _async_call(connection, request)

async def async_notification_request(connection, subscribe, notification_type, session=None, rpc_registration_request=None, keystroke_monitor_request=None, variable_monitor_request=None):
    """
    Requests a change to a notification subscription.

    connection: A connected iterm2.Connection
    subscribe: True to subscribe, False to unsubscribe
    notification_type: iterm2.api_pb2.NotificationType
    session: The unique ID of the session or None.
    rpc_registration_request: The RPC registration request (only for registering an RPC handler) or None.
    keystroke_monitor_request: The keyboard monitor request (only for registering a keystroke handler) or None.
    variable_monitor_request: The variable monitor request (only for registering a variable monitor) or None.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()

    request.notification_request.SetInParent()
    if session is not None:
        request.notification_request.session = session
    if rpc_registration_request is not None:
        request.notification_request.rpc_registration_request.CopyFrom(rpc_registration_request)
    if keystroke_monitor_request:
        request.notification_request.keystroke_monitor_request.CopyFrom(keystroke_monitor_request)
    if variable_monitor_request:
        request.notification_request.variable_monitor_request.CopyFrom(variable_monitor_request)
    request.notification_request.subscribe = subscribe
    request.notification_request.notification_type = notification_type
    return await _async_call(connection, request)

async def async_send_text(connection, session, text, suppress_broadcast):
    """
    Sends text to a session, as though it had been typed.

    connection: A connected iterm2.Connection.
    session: A session ID.
    text: String to send although it had been typed by the user.
    suppress_broadcast: If True, input goes only to the specified session even if broadcasting is on.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.send_text_request.session = session
    request.send_text_request.text = text
    request.send_text_request.suppress_broadcast = suppress_broadcast
    return await _async_call(connection, request)

async def async_split_pane(connection, session, vertical, before, profile=None, profile_customizations=None):
    """
    Splits a session into two.

    connection: A connected iterm2.Connection.
    session: Session ID to split
    vertical: Bool, whether the divider should be vertical
    before: Bool, whether the new session should be left/above the existing one.
    profile: The profile name to use. None for the default profile.
    profile_customizations: None, or a dictionary of overrides.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.split_pane_request.SetInParent()
    if session is not None:
        request.split_pane_request.session = session
    if vertical:
        request.split_pane_request.split_direction = iterm2.api_pb2.SplitPaneRequest.VERTICAL
    else:
        request.split_pane_request.split_direction = iterm2.api_pb2.SplitPaneRequest.HORIZONTAL
    request.split_pane_request.before = before
    if profile is not None:
        request.split_pane_request.profile_name = profile
    if profile_customizations is not None:
        request.split_pane_request.custom_profile_properties.extend(_profile_properties_from_dict(profile_customizations))

    return await _async_call(connection, request)

def _profile_properties_from_dict(profile_customizations):
    l = []
    for key in profile_customizations:
        value = profile_customizations[key]
        entry = iterm2.api_pb2.ProfileProperty()
        entry.key = key
        entry.json_value = value
        l.append(entry)
    return l

async def async_create_tab(connection, profile=None, window=None, index=None, command=None, profile_customizations=None):
    """
    Creates a new tab or window.

    connection: A connected iterm2.Connection.
    profile: The profile name to use. None for the default profile.
    window: The window ID in which to add a tab, or None to create a new window.
    index: The index within the window, from 0 to (num tabs)-1
    command: The command to run in the new session, or None for its default behavior.
    profile_customizations: None, or a dictionary of overrides.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.create_tab_request.SetInParent()
    if profile is not None:
        request.create_tab_request.profile_name = profile
    if window is not None:
        request.create_tab_request.window_id = window
    if index is not None:
        request.create_tab_request.tab_index = index
    if command is not None:
        profile_customizations = iterm2.LocalWriteOnlyProfile()
        profile_customizations.set_use_custom_command("Yes")
        profile_customizations.set_command(command)
    if profile_customizations is not None:
        request.create_tab_request.custom_profile_properties.extend(_profile_properties_from_dict(profile_customizations))
    return await _async_call(connection, request)

async def async_get_buffer_with_screen_contents(connection, session=None):
    """
    Gets the contents of a session's mutable area.

    connection: A connected iterm2.Connection.
    session: Session ID to split

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    if session is not None:
        request.get_buffer_request.session = session
    request.get_buffer_request.line_range.screen_contents_only = True
    return await _async_call(connection, request)

async def async_get_buffer_lines(connection, trailing_lines, session=None):
    """
    Gets the last lines of text from a session

    connection: A connected iterm2.Connection.
    trailing_lines: The number of lines to fetch (Int)
    session: Session ID

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    if session is not None:
        request.get_buffer_request.session = session
    request.get_buffer_request.line_range.trailing_lines = trailing_lines
    return await _async_call(connection, request)

async def async_get_prompt(connection, session=None):
    """
    Gets info about the last prompt in a session

    connection: A connected iterm2.Connection.
    session: Session ID

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.get_prompt_request.SetInParent()
    if session is not None:
        request.get_prompt_request.session = session
    return await _async_call(connection, request)

async def async_start_transaction(connection):
    """
    Begins a transaction, locking iTerm2 until the transaction ends. Be careful with this.

    connection: A connected iterm2.Connection.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.transaction_request.begin = True
    return await _async_call(connection, request)
async def async_end_transaction(connection):
    """
    Ends a transaction begun with start_transaction()

    connection: A connected iterm2.Connection.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.transaction_request.begin = False
    return await _async_call(connection, request)

async def async_register_web_view_tool(connection,
                                       display_name,
                                       identifier,
                                       reveal_if_already_registered,
                                       url):
    """
    Registers a toolbelt tool showing a webview.

    connection: A connected iterm2.Connection.
    display_name: The name of the tool. User-visible.
    identifier: A unique ID that prevents duplicate registration.
    reveal_if_already_registered: Bool. If true, shows the tool on a duplicate registration attempt.
    url: The URL to show in the webview.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    request.register_tool_request.name = display_name
    request.register_tool_request.identifier = identifier
    request.register_tool_request.reveal_if_already_registered = reveal_if_already_registered
    request.register_tool_request.tool_type = iterm2.api_pb2.RegisterToolRequest.ToolType.Value(
        "WEB_VIEW_TOOL")
    request.register_tool_request.URL = url
    return await _async_call(connection, request)

async def async_set_profile_property(connection, session_id, key, value, guids=None):
    """
    Sets a property of a session's profile.

    :param connection: A connected iterm2.Connection.
    :param session_id: Session ID to modify or None. If None, guids must be set.
    :param key: The key to set
    :param value: a Python object, whose type depends on the key
    :param guids: List of GUIDs of the profile to modify or None. If None, session_id must be set.

    Returns: iterm2.api_pb2.ServerOriginatedMessage
    """
    request = _alloc_request()
    if session_id is None:
        request.set_profile_property_request.guid_list.guids.extend(guids);
    else:
        request.set_profile_property_request.session = session_id
    request.set_profile_property_request.key = key
    request.set_profile_property_request.json_value = json.dumps(value)
    return await _async_call(connection, request)

async def async_get_profile(connection, session=None, keys=None):
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

async def async_set_property(connection, name, json_value, window_id=None, session_id=None):
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

async def async_get_property(connection, name, window_id=None):
    """
    Gets a property of an object (currently only of a window).
    """
    request = _alloc_request()
    request.get_property_request.SetInParent()
    request.get_property_request.window_id = window_id
    request.get_property_request.name = name
    return await _async_call(connection, request)

async def async_inject(connection, data, sessions):
    """
    Injects bytes/string into sessions, as though it was program output.
    """
    request = _alloc_request()
    request.inject_request.SetInParent()
    request.inject_request.session_id.extend(sessions)
    request.inject_request.data = data
    return await _async_call(connection, request)

async def async_activate(connection,
                         select_session,
                         select_tab,
                         order_window_front,
                         session_id=None,
                         tab_id=None,
                         window_id=None,
                         activate_app_opts=None):
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

async def async_variable(connection, session_id=None, sets=[], gets=[], tab_id=None):
    """
    Gets or sets session variables.

    `sets` are JSON encoded. The resulting gets will be JSON encoded.
    """
    request = _alloc_request()
    if session_id:
        request.variable_request.session_id = session_id
    elif tab_id:
        request.variable_request.tab_id = tab_id
    else:
        request.variable_request.app = True

    request.variable_request.get.extend(gets)
    for (name, value) in sets:
        kvp = iterm2.api_pb2.VariableRequest.Set()
        kvp.name = name
        kvp.value = value
        request.variable_request.set.extend([kvp])
    return await _async_call(connection, request)

async def async_save_arrangement(connection, name, window_id=None):
    """
    Save a window arrangement.
    """
    request = _alloc_request()
    request.saved_arrangement_request.name = name
    request.saved_arrangement_request.action = iterm2.api_pb2.SavedArrangementRequest.Action.Value(
        "SAVE")
    if window_id is not None:
        request.saved_arrangement_request.window_id = window_id
    return await _async_call(connection, request)

async def async_restore_arrangement(connection, name, window_id=None):
    """
    Restore a window arrangement.
    """
    request = _alloc_request()
    request.saved_arrangement_request.name = name
    request.saved_arrangement_request.action = iterm2.api_pb2.SavedArrangementRequest.Action.Value(
        "RESTORE")
    if window_id is not None:
        request.saved_arrangement_request.window_id = window_id
    return await _async_call(connection, request)

async def async_get_focus_info(connection):
    """
    Fetches the focused state of everything.
    """
    request = _alloc_request()
    request.focus_request.SetInParent()
    return await _async_call(connection, request)

async def async_list_profiles(connection, guids, properties):
    """
    Gets a list of all profiles.

    :param guid: If None, get all profiles. Otherwise, a list of GUIDs (strings) to fetch.
    "param properties: If None, get all properties. Otherwise, a list of strings giving property keys to fetch.
    """
    request = _alloc_request()
    request.list_profiles_request.SetInParent()
    if guids is not None:
        request.list_profiles_request.guids.extend(guids)
    if properties is not None:
        request.list_profiles_request.properties.extend(properties)
    return await _async_call(connection, request)

async def async_send_rpc_result(connection, request_id, is_exception, value):
    """Sends an RPC response."""
    request = _alloc_request()
    request.server_originated_rpc_result_request.request_id = request_id
    if is_exception:
        request.server_originated_rpc_result_request.json_exception = json.dumps(value)
    else:
        request.server_originated_rpc_result_request.json_value = json.dumps(value)
    return await _async_call(connection, request)

async def async_restart_session(connection, session_id, only_if_exited):
    """Restarts a session."""
    request = _alloc_request()
    request.restart_session_request.SetInParent()
    request.restart_session_request.session_id = session_id
    request.restart_session_request.only_if_exited = only_if_exited
    return await _async_call(connection, request)

async def async_menu_item(connection, identifier, query_only):
    """Selects or queries a menu item."""
    request = _alloc_request()
    request.menu_item_request.SetInParent()
    request.menu_item_request.identifier = identifier;
    request.menu_item_request.query_only = query_only;
    return await _async_call(connection, request)

async def async_set_tab_layout(connection, tab_id, tree):
    """Adjusts the layout of split panes in a tab.

    :param tree: a `iterm2.api_pb2.SplitTreeNode` forming the root of the tree.
    """
    request = _alloc_request()
    request.set_tab_layout_request.SetInParent()
    request.set_tab_layout_request.tab_id = tab_id
    request.set_tab_layout_request.root.CopyFrom(tree)
    return await _async_call(connection, request)

async def async_get_broadcast_domains(connection):
    """Fetches the current broadcast domains."""
    request = _alloc_request()
    request.get_broadcast_domains_request.SetInParent()
    return await _async_call(connection, request)

async def async_rpc_list_tmux_connections(connection):
    """Requests a list of tmux connections."""
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.list_connections.SetInParent()
    return await _async_call(connection, request)

async def async_rpc_send_tmux_command(connection, tmux_connection_id, command):
    """Sends a command to the tmux server."""
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.send_command.SetInParent()
    request.tmux_request.send_command.connection_id = tmux_connection_id;
    request.tmux_request.send_command.command = command
    return await _async_call(connection, request)

async def async_rpc_set_tmux_window_visible(connection, tmux_connection_id, window_id, visible):
    """Hides/shows a tmux window (which is an iTerm2 tab)"""
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.set_window_visible.SetInParent()
    request.tmux_request.set_window_visible.connection_id = tmux_connection_id
    request.tmux_request.set_window_visible.window_id = window_id
    request.tmux_request.set_window_visible.visible = visible
    return await _async_call(connection, request)

async def async_rpc_create_tmux_window(connection, tmux_connection_id, affinity=None):
    """Creates a new tmux window."""
    request = _alloc_request()
    request.tmux_request.SetInParent()
    request.tmux_request.create_window.SetInParent()
    request.tmux_request.create_window.connection_id = tmux_connection_id
    if affinity:
        request.tmux_request.create_window.affinity = affinity
    return await _async_call(connection, request)

async def async_reorder_tabs(connection, assignments):
    """Reassigns tabs to windows and specifies their orders.

    :param assignments: a list of tuples of (window_id, [tab_id, ...])
    """
    request = _alloc_request()
    request.reorder_tabs_request.SetInParent()

    def make_assignment(window_id, tab_ids):
        assignment = iterm2.api_pb2.ReorderTabsRequest.Assignment()
        assignment.window_id = window_id
        assignment.tab_ids.extend(tab_ids)
        return assignment

    protos = list(map(lambda a: make_assignment(a[0], a[1]), assignments))
    request.reorder_tabs_request.assignments.extend(protos)
    return await _async_call(connection, request)

async def async_set_default_profile(connection, guid):
    """Sets the default profile."""
    request = _alloc_request()
    request.preferences_request.SetInParent()
    my_request = iterm2.api_pb2.PreferencesRequest.Request()
    my_request.set_default_profile_request.SetInParent()
    my_request.set_default_profile_request.guid = guid
    request.preferences_request.requests.extend([my_request])
    return await _async_call(connection, request)

async def async_get_preference(connection, key):
    """Sets the default profile."""
    request = _alloc_request()
    request.preferences_request.SetInParent()
    my_request = iterm2.api_pb2.PreferencesRequest.Request()
    my_request.get_preference_request.SetInParent()
    my_request.get_preference_request.key = key
    request.preferences_request.requests.extend([my_request])
    return await _async_call(connection, request)

async def async_list_color_presets(connection):
    """Gets a list of color preset names."""
    request = _alloc_request()
    request.color_preset_request.SetInParent()
    request.color_preset_request.list_presets.SetInParent()
    return await _async_call(connection, request)

async def async_get_color_preset(connection, name):
    """Gets the content of a color preset by name."""
    request = _alloc_request()
    request.color_preset_request.SetInParent()
    request.color_preset_request.get_preset.SetInParent()
    request.color_preset_request.get_preset.name = name
    return await _async_call(connection, request)

## Private --------------------------------------------------------------------

def _alloc_id():
    if not hasattr(_alloc_id, 'next_id'):
        _alloc_id.next_id = 0
    result = _alloc_id.next_id
    _alloc_id.next_id += 1
    return result

def _alloc_request():
    request = iterm2.api_pb2.ClientOriginatedMessage()
    request.id = _alloc_id()
    return request

async def _async_call(connection, request):
    await connection.async_send_message(request)
    response = await connection.async_dispatch_until_id(request.id)
    if response.HasField("error"):
        raise RPCException(response.error)
    else:
        return response
