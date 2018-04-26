import asyncio
import iterm2.api_pb2
import iterm2.connection
import json

ACTIVATE_RAISE_ALL_WINDOWS = 1
ACTIVATE_IGNORING_OTHER_APPS = 2

class RPCException(Exception):
  pass

## APIs -----------------------------------------------------------------------

async def list_sessions(connection):
  """
  Requests a list of sessions.

  connection: A connected iterm2.Connection

  Returns: iterm2.api_pb2.ListSessionsResponse
  """
  request = _alloc_request()
  request.list_sessions_request.SetInParent()
  return await _call(connection, request)

async def notification_request(connection, subscribe, notification_type, session=None):
  """
  Requests a change to a notification subscription.

  connection: A connected iterm2.Connection
  subscribe: True to subscribe, False to unsubscribe
  notification_type: iterm2.api_pb2.NotificationType
  session: The unique ID of the session or None.

  Returns: iterm2.api_pb2.ServerOriginatedMessage
  """
  request = _alloc_request()
  if session is not None:
    request.notification_request.session = session
  request.notification_request.subscribe = subscribe
  request.notification_request.notification_type = notification_type
  return await _call(connection, request)

async def send_text(connection, session, text):
  """
  Sends text to a session, as though it had been typed.

  connection: A connected iterm2.Connection.
  session: A session ID.
  text: String to send although it had been typed by the user.

  Returns: iterm2.api_pb2.ServerOriginatedMessage
  """
  request = _alloc_request()
  request.send_text_request.session = session
  request.send_text_request.text = text
  return await _call(connection, request)

async def split_pane(connection, session, vertical, before, profile=None):
  """
  Splits a session into two.

  connection: A connected iterm2.Connection.
  session: Session ID to split
  vertical: Bool, whether the divider should be vertical
  before: Bool, whether the new session should be left/above the existing one.
  profile: The profile name to use. None for the default profile.

  Returns: iterm2.api_pb2.ServerOriginatedMessage
  """
  request = _alloc_request()
  request.split_pane_request.SetInParent()
  if session is not None:
    request.split_pane_request.session = session
  if vertical:
    request.split_pane_request.split_direction = iterm2.api_pb2.SplitPaneRequest.VERTICAL
  else:
    request.split_pane_request.split_direction = iterm2.api_pb2.SplitPaneRequest.HORIZONTAL;
  request.split_pane_request.before = before
  if profile is not None:
    request.split_pane_request.profile_name = profile
  return await _call(connection, request)

async def create_tab(connection, profile=None, window=None, index=None, command=None):
  """
  Creates a new tab or window.

  connection: A connected iterm2.Connection.
  profile: The profile name to use. None for the default profile.
  window: The window ID in which to add a tab, or None to create a new window.
  index: The index within the window, from 0 to (num tabs)-1
  command: The command to run in the new session, or None for its default behavior.

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
    request.create_tab_request.command = command
  return await _call(connection, request)

async def get_buffer_with_screen_contents(connection, session=None):
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
  return await _call(connection, request)

async def get_buffer_lines(connection, trailing_lines, session=None):
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
  return await _call(connection, request)

async def get_prompt(connection, session=None):
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
  return await _call(connection, request)

async def start_transaction(connection):
  """
  Begins a transaction, locking iTerm2 until the transaction ends. Be careful with this.

  connection: A connected iterm2.Connection.

  Returns: iterm2.api_pb2.ServerOriginatedMessage
  """
  request = _alloc_request()
  request.transaction_request.begin = True
  return await _call(connection, request) 
async def end_transaction(connection):
  """
  Ends a transaction begun with start_transaction()

  connection: A connected iterm2.Connection.

  Returns: iterm2.api_pb2.ServerOriginatedMessage
  """
  request = _alloc_request()
  request.transaction_request.begin = False
  return await _call(connection, request)

async def register_web_view_tool(connection, display_name, identifier, reveal_if_already_registered, url):
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
  request.register_tool_request.tool_type = iterm2.api_pb2.RegisterToolRequest.ToolType.Value("WEB_VIEW_TOOL")
  request.register_tool_request.URL = url
  return await _call(connection, request)

async def set_profile_property(connection, session_id, key, value):
  """
  Sets a property of a session's profile.

  connection: A connected iterm2.Connection.
  session_id: Session ID
  key: The key to set
  value: a Python object, whose type depends on the key

  Returns: iterm2.api_pb2.ServerOriginatedMessage
  """
  request = _alloc_request()
  request.set_profile_property_request.session = session_id
  request.set_profile_property_request.key = key
  request.set_profile_property_request.json_value = json.dumps(value)
  return await _call(connection, request)

async def get_profile(connection, session=None, keys=None):
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
  return await _call(connection, request)

async def set_property(connection, name, json_value, window_id=None):
  """
  Sets a property of an object (currently only of a window).
  """
  assert window_id is not None
  request = _alloc_request()
  request.set_property_request.SetInParent()
  request.set_property_request.window_id = window_id
  request.set_property_request.name = name
  request.set_property_request.json_value = json_value
  return await _call(connection, request)

async def get_property(connection, name, window_id=None):
  """
  Gets a property of an object (currently only of a window).
  """
  request = _alloc_request()
  request.get_property_request.SetInParent()
  request.get_property_request.window_id = window_id
  request.get_property_request.name = name
  return await _call(connection, request)

async def inject(connection, data, sessions):
  """
  Injects bytes/string into sessions, as though it was program output.
  """
  request = _alloc_request()
  request.inject_request.SetInParent()
  request.inject_request.session_id.extend(sessions)
  request.inject_request.data = data
  return await _call(connection, request)

async def activate(connection, select_session, select_tab, order_window_front, session_id=None, tab_id=None, window_id=None, activate_app_opts=None):
  """
  Activates a session, tab, or window.
  """
  request = _alloc_request()
  if session_id is not None:
    request.activate_request.session_id = session_id;
  if tab_id is not None:
    request.activate_request.tab_id = tab_id;
  if window_id is not None:
    request.activate_request.window_id = window_id;
  if activate_app_opts is not None:
    request.activate_request.activate_app.SetInParent()
    if ACTIVATE_RAISE_ALL_WINDOWS in activate_app_opts:
      request.activate_request.activate_app.raise_all_windows = True
    if ACTIVATE_IGNORING_OTHER_APPS:
      request.activate_request.activate_app.ignoring_other_apps = True
  request.activate_request.order_window_front = order_window_front
  request.activate_request.select_tab = select_tab
  request.activate_request.select_session = select_session
  return await _call(connection, request)

async def variable(connection, session_id, sets, gets):
  """
  Gets or sets session variables.
  """
  request = _alloc_request()
  request.variable_request.session_id = session_id
  request.variable_request.get.extend(gets)
  for (name, value) in sets:
    s = iterm2.api_pb2.VariableRequest.Set()
    s.name = name
    s.value = value
    request.variable_request.set.extend([s])
  return await _call(connection, request)

async def save_arrangement(connection, name, window_id=None):
  """
  Save a window arrangement.
  """
  request = _alloc_request()
  request.saved_arrangement_request.name = name
  request.saved_arrangement_request.action = iterm2.api_pb2.SavedArrangementRequest.Action.Value("SAVE")
  if window_id is not None:
    request.saved_arrangement_request.window_id = window_id
  return await _call(connection, request)

async def restore_arrangement(connection, name, window_id=None):
  """
  Restore a window arrangement.
  """
  request = _alloc_request()
  request.saved_arrangement_request.name = name
  request.saved_arrangement_request.action = iterm2.api_pb2.SavedArrangementRequest.Action.Value("RESTORE")
  if window_id is not None:
    request.saved_arrangement_request.window_id = window_id
  return await _call(connection, request)

async def get_focus_info(connection):
  """
  Fetches the focused state of everything.
  """
  request = _alloc_request()
  request.focus_request.SetInParent()
  return await _call(connection, request)

## Private --------------------------------------------------------------------

_nextId = 0

def _alloc_id():
  global _nextId
  result = _nextId
  _nextId += 1
  return result

def _alloc_request():
  request = iterm2.api_pb2.ClientOriginatedMessage()
  request.id = _alloc_id()
  return request

async def _call(connection, request):
  future = asyncio.Future()
  await connection.send_message(request)
  response = await connection.dispatch_until_id(request.id)
  if response.HasField("error"):
    raise RPCException(response.error)
  else:
    return response
