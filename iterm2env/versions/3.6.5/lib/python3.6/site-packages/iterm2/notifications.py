import iterm2.api_pb2
import iterm2.connection
import iterm2.rpc

_haveRegisteredHelper = False

# (session, notification_type) -> [coroutine, ...]
_handlers = {}

## APIs -----------------------------------------------------------------------

class SubscriptionException(Exception):
  pass

async def unsubscribe(connection, token):
  """
  Unsubscribes from a notification.

  connection: A connected iterm2.Connection
  token: The result of a previous subscribe call
  """
  global _handlers
  key, coro = token
  coros = _handlers[key]
  coros.remove(coro)
  if len(coros) > 0:
    _handlers[key] = coros
  else:
    del _handlers[key]
    session, notification_type = key
    await _subscribe(connection, False, notification_type, None, session=session)

async def subscribe_to_new_session_notification(connection, callback):
  """
  Registers a callback to be run when a new session is created.

  connection: A connected iterm2.Connection.
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.NewSessionNotification.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_NEW_SESSION, callback)

async def subscribe_to_keystroke_notification(connection, callback, session=None):
  """
  Registers a callback to be run when a key is pressed.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.KeystrokeNotification.
  session: The session to monitor, or None.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_KEYSTROKE, callback, session=session)

async def subscribe_to_screen_update_notification(connection, callback, session=None):
  """
  Registers a callback to be run when the screen contents change.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.ScreenUpdateNotification..
  session: The session to monitor, or None.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_SCREEN_UPDATE, callback, session=session)

async def subscribe_to_prompt_notification(connection, callback, session=None):
  """
  Registers a callback to be run when a shell prompt is received.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.PromptNotification.
  session: The session to monitor, or None.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_PROMPT, callback, session=session)

async def subscribe_to_location_change_notification(connection, callback, session=None):
  """
  Registers a callback to be run when the host or current directory changes.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.LocationChangeNotification.
  session: The session to monitor, or None.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_LOCATION_CHANGE, callback, session=session)

async def subscribe_to_custom_escape_sequence_notification(connection, callback, session=None):
  """
  Registers a callback to be run when a custom escape sequence is received.

  The escape sequence is OSC 1337 ; Custom=id=<identity>:<payload> ST

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.CustomEscapeSequenceNotification.
  session: The session to monitor, or None.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE, callback, session=session)

async def subscribe_to_terminate_session_notification(connection, callback):
  """
  Registers a callback to be run when a session terminates.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.TerminateSessionNotification.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_TERMINATE_SESSION, callback, session=None)

async def subscribe_to_layout_change_notification(connection, callback):
  """
  Registers a callback to be run when the relationship between sessions, tabs,
  and windows changes.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.LayoutChangedNotification.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_LAYOUT_CHANGE, callback, session=None)

async def subscribe_to_focus_change_notification(connection, callback):
  """
  Registers a callback to be run when focus changes.

  connection: A connected iterm2.Connection
  callback: A coroutine taking two arguments: an iterm2.Connection and
    iterm2.api_pb2.FocusChangedNotification.

  Returns: A token that can be passed to unsubscribe.
  """
  return await _subscribe(connection, True, iterm2.api_pb2.NOTIFY_ON_FOCUS_CHANGE, callback, session=None)

## Private --------------------------------------------------------------------

async def _subscribe(connection, subscribe, notification_type, callback, session=None):
  _register_helper_if_needed()
  response = await iterm2.rpc.notification_request(connection, subscribe, notification_type, session)
  status = response.notification_response.status
  status_ok = (status == iterm2.api_pb2.NotificationResponse.Status.Value("OK"))

  if subscribe:
    already = (status == iterm2.api_pb2.NotificationResponse.Status.Value("ALREADY_SUBSCRIBED"))
    if status_ok or already:
      _register_notification_handler(session, notification_type, callback)
      return ((session, notification_type), callback)
  else:
    # Unsubscribe
    if status_ok:
      return

  raise SubscriptionException(iterm2.api_pb2.NotificationResponse.Status.Name(status))

def _register_helper_if_needed():
  global _haveRegisteredHelper
  if not _haveRegisteredHelper:
    _haveRegisteredHelper = True
    iterm2.connection.Connection.register_helper(_dispatch_helper)

async def _dispatch_helper(connection, message):
  handlers, sub_notification = _get_notification_handlers(message)
  for handler in handlers:
    assert handler is not None
    await handler(connection, sub_notification)
  return len(handlers) > 0

def _get_handler_key_from_notification(notification):
  key = None

  if notification.HasField('keystroke_notification'):
    key = (notification.keystroke_notification.session, iterm2.api_pb2.NOTIFY_ON_KEYSTROKE)
    notification=notification.keystroke_notification
  elif notification.HasField('screen_update_notification'):
    key = (notification.screen_update_notification.session, iterm2.api_pb2.NOTIFY_ON_SCREEN_UPDATE)
    notification = notification.screen_update_notification
  elif notification.HasField('prompt_notification'):
    key = (notification.prompt_notification.session, iterm2.api_pb2.NOTIFY_ON_PROMPT)
    notification = notification.prompt_notification
  elif notification.HasField('location_change_notification'):
    key = (notification.location_change_notification.session, iterm2.api_pb2.NOTIFY_ON_LOCATION_CHANGE)
    notification = notification.location_change_notification
  elif notification.HasField('custom_escape_sequence_notification'):
    key = (notification.custom_escape_sequence_notification.session,
        iterm2.api_pb2.NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE)
    notification = notification.custom_escape_sequence_notification
  elif notification.HasField('new_session_notification'):
    key = (None, iterm2.api_pb2.NOTIFY_ON_NEW_SESSION)
    notification = notification.new_session_notification
  elif notification.HasField('terminate_session_notification'):
    key = (None, iterm2.api_pb2.NOTIFY_ON_TERMINATE_SESSION)
    notification = notification.terminate_session_notification
  elif notification.HasField('layout_changed_notification'):
    key = (None, iterm2.api_pb2.NOTIFY_ON_LAYOUT_CHANGE)
    notification = notification.layout_changed_notification
  elif notification.HasField('focus_changed_notification'):
    key = (None, iterm2.api_pb2.NOTIFY_ON_FOCUS_CHANGE)
    notification = notification.focus_changed_notification

  return key, notification

def _get_notification_handlers(message):
  key, sub_notification = _get_handler_key_from_notification(message.notification)
  if key is None:
    return ([], None)

  fallback = (None, key[1])

  if key in _handlers:
    return (_handlers[key], sub_notification)
  elif fallback in _handlers:
    return (_handlers[fallback], sub_notification)
  else:
    return ([], None)

def _register_notification_handler(session, notification_type, coro):
  global _handlers
  assert coro is not None
  key = (session, notification_type)
  if key in _handlers:
    _handlers[key].append(coro)
  else:
    _handlers[key] = [coro]

