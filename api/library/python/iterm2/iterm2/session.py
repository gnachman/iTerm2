import asyncio

import iterm2.connection
import iterm2.hierarchy
import iterm2.notifications
import iterm2.profile
import iterm2.rpc
import iterm2.util

class SplitPaneException(Exception):
  pass

class Splitter:
  def __init__(self, vertical=False):
    self.vertical = vertical
    self.children = []
    self.sessions = []

  @staticmethod
  def from_node(node, connection):
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
    self.children.append(child)
    if type(child) is Session:
      self.sessions.append(child)
    else:
      self.sessions.extend(child.all_sessions())

  def get_children(self):
    return self.children

  def all_sessions(self):
    return self.sessions

  def pretty_str(self, indent=""):
    s = indent + "Splitter %s\n" % (
        "|" if self.vertical else "-")
    for child in self.children:
      s += child.pretty_str("  " + indent)
    return s

class Session:
  def __init__(self, connection, link):
    self.connection = connection

    self.session_id = link.session.unique_identifier
    self.frame = link.session.frame
    self.grid_size = link.session.grid_size
    self.name = link.session.title

  def __repr__(self):
    return "<Session name=%s id=%s>" % (self.name, self.session_id)

  def pretty_str(self, indent=""):
    return indent + "Session \"%s\" id=%s %s frame=%s\n" % (
        self.name,
        self.session_id,
        iterm2.util.size_str(self.grid_size),
        iterm2.util.frame_str(self.frame))

  def get_session_id(self):
    """
    Returns the globally unique identifier for this session.
    """
    return self.session_id

  def get_keystroke_reader(self):
    """
    Returns a keystroke reader.

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
    """
    await iterm2.rpc.send_text(self.connection, self.session_id, text)

  async def split_pane(self, vertical=False, before=False, profile=None):
    result = await iterm2.rpc.split_pane(self.connection, self.session_id, vertical, before, profile)
    if result.split_pane_response.status == iterm2.api_pb2.SplitPaneResponse.Status.Value("OK"):
      return result.split_pane_response.session_id

    else:
      raise SplitPaneException(iterm2.api_pb2.SplitPaneResponse.Status.Name(result.split_pane_response.status))

  async def read_keystroke(self):
    """
    Blocks until a keystroke is received. Returns a KeystrokeNotification.

    See also get_keystroke_reader().
    """
    future = asyncio.Future()
    async def on_keystroke(connection, message):
      future.set_result(message)

    token = await iterm2.notifications.subscribe_to_keystroke_notification(self.connection, on_keystroke, self.session_id)
    await self.connection.dispatch_until_future(future)
    await iterm2.notifications.unsubscribe(self.connection, token)
    return future.result()

  async def wait_for_screen_update(self):
    future = asyncio.Future()
    async def on_update(connection, message):
      future.set_result(message)

    token = await iterm2.notifications.subscribe_to_screen_update_notification(self.connection, on_update, self.session_id)
    await self.connection.dispatch_until_future(future)
    await iterm2.notifications.unsubscribe(self.connection, token)
    return future.result

  async def get_screen_contents(self):
    response = await iterm2.rpc.get_buffer_with_screen_contents(self.connection, self.session_id)
    status = response.get_buffer_response.status
    if status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
      return response.get_buffer_response
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetBufferResponse.Status.Name(status))

  async def get_buffer_lines(self, trailing_lines):
    response = await iterm2.rpc.get_buffer_lines(self.connection, trailing_lines, self.session_id)
    status = response.get_buffer_response.status
    if status == iterm2.api_pb2.GetBufferResponse.Status.Value("OK"):
      return response.get_buffer_response
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetBufferResponse.Status.Name(status))

  async def get_prompt(self):
    response = await iterm2.rpc.get_prompt(self.connection, self.session_id)
    status = response.get_prompt_response.status
    if status == iterm2.api_pb2.GetPromptResponse.Status.Value("OK"):
      return response.get_prompt_response
    elif status == iterm2.api_pb2.GetPromptResponse.Status.Value("PROMPT_UNAVAILABLE"):
      return None
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetPromptResponse.Status.Name(status))

  async def set_profile_property(self, key, json_value):
    response = await iterm2.rpc.set_profile_property(self.connection, key, json_value)
    status = response.set_profile_property_response.status
    if status == iterm2.api_pb2.SetProfilePropertyResponse.Status.Value("OK"):
      return response.set_profile_property_response
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetPromptResponse.Status.Name(status))

  async def get_profile(self):
    response = await iterm2.rpc.get_profile(self.connection, self.session_id)
    status = response.get_profile_property_response.status
    if status == iterm2.api_pb2.GetProfilePropertyResponse.Status.Value("OK"):
      return iterm2.profile.Profile(self.session_id, self.connection, response.get_profile_property_response)
    else:
      raise iterm2.rpc.RPCException(iterm2.api_pb2.GetProfilePropertyResponse.Status.Name(status))

  class KeystrokeReader:
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
