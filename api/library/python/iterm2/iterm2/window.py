import iterm2.api_pb2
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.util

class CreateTabException(Exception):
  pass

class Window:
  """Represents an iTerm2 window."""
  def __init__(self, connection, window_id, tabs, frame):
    self.connection = connection
    self.window_id = window_id
    self.tabs = tabs
    self.frame = frame

  def __repr__(self):
    return "<Window id=%s tabs=%s frame=%s>" % (self.window_id, self.tabs, iterm2.util.frame_str(self.frame))

  def pretty_str(self, indent=""):
    """
    Returns: A nicely formatted string describing the window, its tabs, and their sessions.
    """
    s = indent + "Window id=%s frame=%s\n" % (self.get_window_id(), iterm2.util.frame_str(self.frame))
    for t in self.tabs:
      s += t.pretty_str(indent=indent + "  ")
    return s

  @staticmethod
  async def create(connection, profile=None, command=None):
    """
    Creates a new window.

    profile: The profile name to use or None for the default profile.
    command: The command to run in the new session, or None for the default for the profile.

    Returns: A session_id

    Raises: CreateTabException if something goes wrong.
    """
    result = await iterm2.rpc.create_tab(connection, profile=profile, command=command)
    if result.create_tab_response.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      return result.create_tab_response.session_id
    else:
      raise CreateTabException(iterm2.api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status))

  def get_window_id(self):
    """
    Returns: the window's unique identifier.
    """
    return self.window_id

  def get_tabs(self):
    """
    Returns: a list of iterm2.tab.Tab objects.
    """
    return self.tabs

  async def create_tab(self, profile=None, command=None, index=None):
    """
    Creates a new tab in this window.

    profile: The profile name to use or None for the default profile.
    command: The command to run in the new session, or None for the default for the profile.
    index: The index in the window where the new tab should go (0=first position, etc.)

    Returns: A session_id

    Raises: CreateTabException if something goes wrong.
    """
    result = await iterm2.rpc.create_tab(self.connection, profile=profile, window=self.window_id, index=index, command=command)
    if result.create_tab_response.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      return result.create_tab_response.session_id
    else:
      raise CreateTabException(iterm2.api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status))

