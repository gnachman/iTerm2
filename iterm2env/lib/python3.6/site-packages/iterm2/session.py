import asyncio

import iterm2.connection
import iterm2.hierarchy
import iterm2.notifications
import iterm2.profile
import iterm2.rpc
import iterm2.util

class SplitPaneException(Exception):
  """Something went wrong when trying to split a pane."""
  pass

class Splitter:
  """A container of split pane sessions where the dividers are all aligned the same way."""
  def __init__(self, vertical=False):
    """
    vertical: Bool. If true, the divider is vertical, else horizontal.
    """
    self.vertical = vertical
    self.children = []
    self.sessions = []

  @staticmethod
  def from_node(node, connection):
    """Creates a new Splitter from a node.

    node: iterm2.api_pb2.ListSessionsResponse.SplitTreeNode
    connection: iterm2.connection.Connection

    Returns: A new Splitter.
    """
    splitter = Splitter(node.vertical)
    for link in node.links:
      if link.HasField("session"):
        session = Session(connection, link)
        splitter.add_child(session)
      else:
        subsplit = Splitter.from_node(link.node, connection)
        splitter.add_child(subsplit)
    return splitter

  def add_child(self, child):
    """
    Adds one or more new sessions to a splitter.

    child: A Session or a Splitter.
    """
    self.children.append(child)
    if type(child) is Session:
      self.sessions.append(child)
    else:
      self.sessions.extend(child.all_sessions())

  def get_children(self):
    """
    Returns: this splitter's children. A list of Session's.
    """
    return self.children

  def all_sessions(self):
    """
    Returns: All sessions in this splitter and all nested splitters. A list of Session's.
    """
    return self.sessions

  def pretty_str(self, indent=""):
    """
    Returns: A string describing this splitter. Has newlines.
    """
    s = indent + "Splitter %s\n" % (
        "|" if self.vertical else "-")
    for child in self.children:
      s += child.pretty_str("  " + indent)
    return s

class Session:
  """
  Represents an iTerm2 session.
  """

  @staticmethod
  def active_proxy(connection):
    """
    Returns: A proxy for the currently active session.
    """
    return ProxySession(connection, "active")

  def all_proxy(connection):
    """
    Returns: A proxy for all sessions.
    """
    return ProxySession(connection, "all")

  def __init__(self, connection, link):
    """
    connection: iterm2.connection.Connection
    link: iterm2.api_pb2.ListSessionsResponse.SplitTreeNode.SplitTreeLink
    """
    self.connection = connection

    self.session_id = link.session.unique_identifier
    self.frame = link.session.frame
    self.grid_size = link.session.grid_size
    self.name = link.session.title

  def __repr__(self):
    return "<Session name=%s id=%s>" % (self.name, self.session_id)

  def pretty_str(self, indent=""):
    """
    Returns: A string describing the session.
    """
    return indent + "Session \"%s\" id=%s %s frame=%s\n" % (
        self.name,
        self.session_id,
        iterm2.util.size_str(self.grid_size),
        iterm2.util.frame_str(self.frame))

  def get_session_id(self):
    """
    Returns: the globally unique identifier for this session.
    """
    return self.session_id

  def get_keystroke_reader(self):
    """
    Returns: a keystroke reader.

    Usage:

      async with session.get_keystroke_reader() as reader:
        while condition():
          handle_keystrokes(reader.get())

      Each call to reader.get() returns an array of new keystrokes.
    """
    return self.KeystrokeReader(self.connection, self.session_id)

  def get_screen_streamer(self, want_contents=True):
    return self.ScreenStreamer(self.connection, self.session_id, want_contents=want_contents)

  async def send_text(self, text):
    """
    Send text as though the user had typed it.

    text: The text to send.
    """
    await iterm2.rpc.send_text(self.connection, self.session_id, text)

  async def split_pane(self, vertical=False, before=False, profile=None):
    """
    Splits the pane, creating a new session.

    vertical: Bool. If true, the divider is vertical, else horizontal.
    before: Bool, whether the new session should be left/above the existing one.
    profile: The profile name to use. None for the default profile.

    Returns: New session ID.

    Raises: SplitPaneException if something goes wrong.
    """
    result = await iterm2.rpc.split_pane(self.connection, self.session_id, vertical, before, profile)
    if result.split_pane_response.status == iterm2.api_pb2.SplitPaneResponse.Status.Value("OK"):
      return result.split_pane_response.session_id

    else:
      raise SplitPaneException(iterm2.api_pb2.SplitPaneResponse.Status.Name(result.split_pane_response.status))

  async def read_keystroke(self):
    """
    Blocks until a keystroke is received. Returns a KeystrokeNotification.

    See also get_keystroke_reader().

    Returns: iterm2.api_pb2.KeystrokeNotification
    """
    future = asyncio.Future()
    async def on_keystroke(connection, message):
      future.set_result(message)

    token = await iterm2.notifications.subscribe_to_keystroke_notification(self.connection, on_keystroke, self.session_id)
    await self.connection.dispatch_until_future(future)
    await iterm2.notifications.unsubscribe(self.connection, token)
    return future.result()

  async def wait_for_screen_update(self):
    """
    Blocks until the screen contents change.

    Returns: iterm2.api_pb2.ScreenUpdateNotification
    """
    future = asyncio.Future()
    async def on_update(connection, message):
      future.set_result(message)

    token = await iterm2.notifications.subscribe_to_screen_update_notification(self.connection, on_update, self.session_id)
    await self.connection.dispatch_until_future(future)
    await iterm2.notifications.unsubscribe(self.connection, token)
    return future.result

  async def get_screen_contents(self):
    """
    Returns: The screen contents, an iterm2.api_pb2.GetBufferResponse

    Raises: iterm2.rpc.RPCException if something goes wrong.
    """
    response = await iterm2.rpc.get_buffer_with_screen_contents(self.connection, self.session_id)
    status = response.get_buffer_response.status
    if status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
      return response.get_buffer_response
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetBufferResponse.Status.Name(status))

  async def get_buffer_lines(self, trailing_lines):
    """
    Fetches the last lines of the session, reaching into history if needed.

    trailing_lines: The number of lines to fetch.

    Returns: The buffer contents, an iterm2.api_pb2.GetBufferResponse

    Raises: iterm2.rpc.RPCException if something goes wrong.
    """
    response = await iterm2.rpc.get_buffer_lines(self.connection, trailing_lines, self.session_id)
    status = response.get_buffer_response.status
    if status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
      return response.get_buffer_response
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetBufferResponse.Status.Name(status))

  async def get_prompt(self):
    """
    Fetches info about the last prompt in this session.

    Returns: iterm2.api_pb2.GetPromptResponse

    Raises: iterm2.rpc.RPCException if something goes wrong.
    """
    response = await iterm2.rpc.get_prompt(self.connection, self.session_id)
    status = response.get_prompt_response.status
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value("OK"):
      return response.get_prompt_response
    elif status == iterm2.api_pb2.GetPromptResponse.Status.Value("PROMPT_UNAVAILABLE"):
      return None
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetPromptResponse.Status.Name(status))

  async def set_profile_property(self, key, json_value):
    """
    Sets the value of a property in this session.

    key: The name of the property
    json_value: The json-encoded value to set

    Returns: iterm2.api_pb2.SetProfilePropertyResponse

    Raises: iterm2.rpc.RPCException if something goes wrong.
    """
    response = await iterm2.rpc.set_profile_property(self.connection, key, json_value)
    status = response.set_profile_property_response.status
    if status == iterm2.api_pb2.SetProfilePropertyResponse.Status.Value("OK"):
      return response.set_profile_property_response
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetPromptResponse.Status.Name(status))

  async def get_profile(self):
    """
    Fetches the profile of this session

    Returns: iterm2.profile.Profile

    Raises: iterm2.rpc.RPCException if something goes wrong.
    """
    response = await iterm2.rpc.get_profile(self.connection, self.session_id)
    status = response.get_profile_property_response.status
    if status == iterm2.api_pb2.GetProfilePropertyResponse.Status.Value("OK"):
      return iterm2.profile.Profile(self.session_id, self.connection, response.get_profile_property_response)
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetProfilePropertyResponse.Status.Name(status))

  async def inject(self, data):
    """
    Injects data as though it were program output.

    data: bytes
    """
    response = await iterm2.rpc.inject(self.connection, data, [self.session_id])
    status = response.inject_response.status[0]
    if status != iterm2.api_pb2.InjectResponse.Status.Value("OK"):
      raise iterm2.rpc.RPCException(iterm2.api_pb2.InjectResponse.Status.Name(status))

  class KeystrokeReader:
    """An asyncio context manager for reading keystrokes.

    Don't create this yourself. Use Session.get_keystroke_reader() instead. See
    its docstring for more info."""
    def __init__(self, connection, session_id):
      self.connection = connection
      self.session_id = session_id
      self.buffer = []

    async def __aenter__(self):
      async def on_keystroke(connection, message):
        self.buffer.append(message)
        if self.future is not None:
          temp = self.buffer
          self.buffer = []
          self.future.set_result(temp)

      self.token = await iterm2.notifications.subscribe_to_keystroke_notification(self.connection, on_keystroke, self.session_id)
      return self

    async def get(self):
      self.future = asyncio.Future()
      await self.connection.dispatch_until_future(self.future)
      result = self.future.result()
      self.future = None
      return result

    async def __aexit__(self, exc_type, exc, tb):
      await iterm2.notifications.unsubscribe(self.connection, self.token)
      return self.buffer

  class ScreenStreamer:
    """An asyncio context manager for monitoring the screen contents.

    Don't create this yourself. Use Session.get_screen_streamer() instead. See
    its docstring for more info."""
    def __init__(self, connection, session_id, want_contents=True):
      self.connection = connection
      self.session_id = session_id
      self.want_contents = want_contents

    async def __aenter__(self):
      async def on_update(connection, message):
        future = self.future
        if future is None:
          # Ignore reentrant calls
          return

        self.future = None
        if future is not None and not future.done():
          future.set_result(message)

      self.token = await iterm2.notifications.subscribe_to_screen_update_notification(self.connection, on_update, self.session_id)
      return self

    async def __aexit__(self, exc_type, exc, tb):
      await iterm2.notifications.unsubscribe(self.connection, self.token)

    async def get(self):
      future = asyncio.Future()
      self.future = future
      await self.connection.dispatch_until_future(self.future)
      self.future = None

      if self.want_contents:
        result = await iterm2.rpc.get_buffer_with_screen_contents(self.connection, self.session_id)
        return result

class InvalidSessionId(Exception):
  """The specified session ID is not allowed in this method."""
  pass

class ProxySession(Session):
  """A proxy for a Session.

  This is used when you specify an abstract session ID like "all" or "active".
  Since the session or set of sessions that refers to is ever-changing, this
  proxy stands in for the real thing. It may limit functionality since it
  doesn't make sense to, for example, get the screen contents of "all"
  sessions.
  """
  def __init__(self, connection, session_id):
    self.connection = connection
    self.session_id = session_id

  def __repr__(self):
    return "<ProxySession %s>" % self.session_id

  def pretty_str(self, indent=""):
    return indent + "ProxySession %s" % self.session_id

  async def get_screen_contents(self):
    if self.session_id == "all":
      raise InvalidSessionId()
    return await super(ProxySession, self).get_screen_contents()

  async def get_buffer_lines(self, trailing_lines):
    if self.session_id == "all":
      raise InvalidSessionId()
    return await super(ProxySession, self).get_buffer_lines(trailing_lines)

  async def get_prompt(self):
    if self.session_id == "all":
      raise InvalidSessionId()
    return await super(ProxySession, self).get_prompt()

  async def get_profile(self):
    if self.session_id == "all":
      return iterm2.profile.WriteOnlyProfile(self.session_id, self.connection)
    else:
      return await super(ProxySession, self).get_profile()

