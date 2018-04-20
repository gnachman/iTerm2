import iterm2.api_pb2
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.util

class CreateTabException(Exception):
  pass

class Window:
  def __init__(self, connection, window_id, tabs, frame):
    self.connection = connection
    self.window_id = window_id
    self.tabs = tabs
    self.frame = frame

  def __repr__(self):
    return "<Window id=%s tabs=%s frame=%s>" % (self.window_id, self.tabs, iterm2.util.frame_str(self.frame))

  def pretty_str(self, indent=""):
    s = indent + "Window id=%s frame=%s\n" % (self.get_window_id(), iterm2.util.frame_str(self.frame))
    for t in self.tabs:
      s += t.pretty_str(indent=indent + "  ")
    return s

  @staticmethod
  async def create(connection, profile=None, command=None):
    result = await iterm2.rpc.create_tab(connection, profile=profile, command=command)
    if result.create_tab_response.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      session = iterm2.session.Session(connection, result.create_tab_response.session_id)
      tab = iterm2.tab.Tab(connection, result.create_tab_response.tab_id, [session])
      window = Window(connection, result.create_tab_response.window_id, [tab])
      return window
    else:
      raise CreateTabException(iterm2.api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status))

  def get_window_id(self):
    return self.window_id

  def get_tabs(self):
    return self.tabs

  async def create_tab(self, profile=None, command=None, index=None):
    result = await iterm2.rpc.create_tab(self.connection, profile=profile, window=self.window_id, index=index, command=command)
    if result.create_tab_response.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      session = iterm2.session.Session(self.connection, result.create_tab_response.session_id)
      return Tab(self.connection, result.create_tab_response.tab_index, [session])
    else:
      raise CreateTabException(iterm2.api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status))

