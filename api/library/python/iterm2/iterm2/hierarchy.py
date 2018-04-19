import iterm2.notifications
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.window

class CreateWindowException(Exception):
  pass

class Hierarchy:
  @staticmethod
  async def construct(connection):
    response = await iterm2.rpc.list_sessions(connection)
    list_sessions_response = response.list_sessions_response
    windows = Hierarchy._windows_from_list_sessions_response(connection, list_sessions_response)
    h = Hierarchy(connection, windows)
    await h._listen()
    return h

  @staticmethod
  def _windows_from_list_sessions_response(connection, response):
    windows = []
    for w in response.windows:
      tabs = []
      for t in w.tabs:
        root = iterm2.session.Splitter.from_node(t.root, connection)
        tabs.append(iterm2.tab.Tab(connection, t.tab_id, root))
      windows.append(iterm2.window.Window(connection, w.window_id, tabs, w.frame))
    return windows

  def __init__(self, connection, windows):
    self.connection = connection
    self.windows = windows
    self.tokens = []

  def pretty_str(self):
    """Returns the hierarchy as a human-readable string"""
    s = ""
    for w in self.windows:
      if len(s) > 0:
        s += "\n"
      s += w.pretty_str(indent="")
    return s

  def _search_for_session_id(self, session_id):
    for w in self.windows:
      for t in w.tabs:
        sessions = t.get_sessions()
        for s in sessions:
          if s.get_session_id() == session_id:
            return s
    return None

  async def get_session_by_id(self, session_id):
    s = self._search_for_session_id(session_id)
    if s is None:
      await self.refresh()
      return self._search_for_session_id(session_id)
    else:
      return s

  async def refresh(self):
    response = await iterm2.rpc.list_sessions(self.connection)
    # TODO: Calculate diffs so sessions don't get invalidated.
    self.windows = Hierarchy._windows_from_list_sessions_response(self.connection, response.list_sessions_response)

  def get_tab_and_window_for_session(self, session):
    session_id = session.get_session_id()
    for w in self.windows:
      for t in w.tabs:
        if session in t.get_sessions():
          return w, t
    return None, None

  async def create_window(self, profile=None, command=None):
    result = await iterm2.rpc.create_tab(self.connection, profile=profile, window=None, command=command)
    ctr = result.create_tab_response
    if ctr.status == iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      session = await self.get_session_by_id(ctr.session_id)
      window, tab = self.get_tab_and_window_for_session(session)
      return window
    else:
      raise CreateWindowException(iterm2.api_pb2.CreateTabResponse.Status.Name(result.create_tab_response.status))

  async def _listen(self):
    connection = self.connection
    self.tokens.append(await iterm2.notifications.subscribe_to_new_session_notification(connection, self.refresh))
    self.tokens.append(await iterm2.notifications.subscribe_to_terminate_session_notification(connection, self.refresh))
    self.tokens.append(await iterm2.notifications.subscribe_to_layout_change_notification(connection, self.refresh))

