import iterm2.notifications
import iterm2.rpc
import iterm2.session
import iterm2.tab
import iterm2.window

_app = None
async def get_app(connection):
  """Returns the app singleton, creating it if needed."""
  global _app
  if _app is None:
    _app = await App.construct(connection)
  return _app

class CreateWindowException(Exception):
  """A problem was encountered while creating a window."""
  pass

class SavedArrangementException(Exception):
  """A problem was encountered while saving or restoring an arrangement."""
  pass

class App:
  """Represents the application.
  
  Stores and provides access to app-global state. Holds a collection of
  terminal windows and provides utilities for them.

  This object keeps itself up to date by getting notifications when sessions,
  tabs, or windows change.
  """
  @staticmethod
  async def construct(connection):
    """Don't use this directly. Use iterm2.app.get_app().
    
    Use this to construct a new hierarchy instead of __init__.
    This exists only because __init__ can't be async.
    """
    response = await iterm2.rpc.list_sessions(connection)
    list_sessions_response = response.list_sessions_response
    windows = App._windows_from_list_sessions_response(connection, list_sessions_response)
    h = App(connection, windows)
    await h._listen()
    await h._refresh_focus()
    return h

  def __init__(self, connection):
    """Don't call this directly. Use construct."""
    self.connection = connection

  async def activate(self, raise_all_windows=True, ignoring_other_apps=False):
    """Activate the app, giving it keyboard focus.
    
    :param raise_all_windows: Raise all windows if True, or only the key window. Defaults to True.
    :param ignoring_other_apps: If True, activate even if the user interacts with another app after the call.
    """
    opts = []
    if raise_all_windows:
      opts.append(iterm2.rpc.ACTIVATE_RAISE_ALL_WINDOWS)
    if ignoring_other_apps:
      opts.append(iterm2.rpc.ACTIVATE_IGNORING_OTHER_APPS)
    await iterm2.rpc.activate(self.connection, False, False, False, activate_app_opts=opts)

  async def save_window_arrangement(self, name):
    """Save all windows as a new arrangement.
    
    Replaces the arrangement with the given name if it already exists.

    :param name: The name of the arrangement.
    
    :throws: SavedArrangementException
    """
    result = await iterm2.rpc.save_arrangement(self.connection, name)
    if result.create_tab_response.status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      raise SavedArrangementException(iterm2.api_pb2.SavedArrangementResponse.Status.Name(result.saved_arrangement_response.status))

  async def restore_window_arrangement(self, name):
    """Restore a saved window arrangement.
    
    :param name: The name of the arrangement to restore.

    :throws: SavedArrangementException
    """
    result = await iterm2.rpc.restore_arrangement(self.connection, name)
    if result.create_tab_response.status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      raise SavedArrangementException(iterm2.api_pb2.SavedArrangementResponse.Status.Name(result.saved_arrangement_response.status))

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
    """Do not call this directly. Use App.construct() instead."""
    self.connection = connection
    self.windows = windows
    self.tokens = []

    # None in these fields means unknown. Notifications will update them.
    self.app_active = None
    self.key_window_id = None

  def pretty_str(self):
    """Returns the hierarchy as a human-readable string"""
    s = ""
    for w in self.windows:
      if len(s) > 0:
        s += "\n"
      s += w.pretty_str(indent="")
    return s

  def _search_for_session_id(self, session_id):
    if session_id == "active":
      return iterm2.session.Session.active_proxy(self.connection)
    if session_id == "all":
      return iterm2.session.Session.all_proxy(self.connection)

    for w in self.windows:
      for t in w.tabs:
        sessions = t.get_sessions()
        for s in sessions:
          if s.get_session_id() == session_id:
            return s
    return None

  def _search_for_tab_id(self, tab_id):
    for w in self.windows:
      for t in w.tabs:
        if tab_id == t.tab_id:
          return t
    return None

  def _search_for_window_id(self, window_id):
    for w in self.windows:
      if window_id == w.window_id:
        return w
    return None

  async def _refresh_focus(self):
    focus_info = await iterm2.rpc.get_focus_info(self.connection)
    for notif in focus_info.focus_response.notifications:
      await self._focus_change(self.connection, notif)

  async def get_session_by_id(self, session_id):
    """Finds a session exactly matching the passed-in id.

    :param session_id: The session ID to search for.

    :returns: An iterm2.session.Session or None.
    """
    s = self._search_for_session_id(session_id)
    if s is None:
      await self.refresh()
      return self._search_for_session_id(session_id)
    else:
      return s

  async def get_tab_by_id(self, tab_id):
    """Finds a tab exactly matching the passed-in id.

    :param tab_id: The tab ID to search for.

    :returns: An iterm2.tab.Tab or None.
    """
    t = self._search_for_tab_id(tab_id)
    if t is None:
      await self.refresh()
      return self._search_for_tab_id(tab_id)
    else:
      return t

  async def get_window_by_id(self, window_id):
    """Finds a window exactly matching the passed-in id.

    :param window_id: The window ID to search for.

    :returns: An iterm2.window.Window or None
    """
    w = self._search_for_window_id(window_id)
    if w is None:
      await self.refresh()
      return self._search_for_window_id(window_id)
    else:
      return w

  async def get_window_for_tab(self, tab_id):
    """Finds the window that contains the passed-in tab id.

    :param tab_id: The tab ID to search for.

    :returns: An iterm2.window.Window or None
    """
    w = self._search_for_window_with_tab(tab_id)
    if w is None:
      await self.refresh()
      return self._search_for_window_with_tab(tab_id)
    else:
      return w

  def _search_for_window_with_tab(self, tab_id):
    for w in self.windows:
      for t in w.tabs:
        if t.tab_id == tab_id:
          return w
    return None

  async def refresh(self, connection=None, sub_notif=None):
    """Reloads the hierarchy.

    You shouldn't need to call this explicitly. It will update itself from notifications.
    """
    response = await iterm2.rpc.list_sessions(self.connection)
    # TODO: Calculate diffs so sessions don't get invalidated.
    self.windows = App._windows_from_list_sessions_response(self.connection, response.list_sessions_response)

  async def _focus_change(self, connection, sub_notif):
    """Updates the record of what is in focus."""
    if sub_notif.HasField("application_active"):
      self.app_active = sub_notif.application_active
    elif sub_notif.HasField("window_key"):
      self.key_window_id = sub_notif.window_id
    elif sub_notif.HasField("selected_tab"):
      window = await self.get_window_for_tab(sub_notif.selected_tab)
      window.selected_tab_id = sub_notif.selected_tab
    elif sub_notif.HasField("session"):
      s = await self.get_session_by_id(sub_notif.session)
      w, t = self.get_tab_and_window_for_session(s)
      t.active_session_id = sub_notif.session

  async def get_key_window(self):
    """Gets the key window.

    The key window is the window that receives keyboard input when iTerm2 is
    the active application.

    :returns: iterm2.window.Window or None
    """
    if self.key_window_id is None:
      await self._refresh_focus()
    if self.key_window_id is None:
      return None
    else:
      return await self.get_window_by_id(self.key_window_id)

  def get_tab_and_window_for_session(self, session):
    """Finds the tab and window that own a session.

    :param session: An iterm2.Session object.

    :returns: A tuple of (iterm2.window.Window, iterm2.tab.Tab).
    """
    session_id = session.get_session_id()
    for w in self.windows:
      for t in w.tabs:
        if session in t.get_sessions():
          return w, t
    return None, None

  async def create_window(self, profile=None, command=None):
    """Creates a new window.

    :param profile: The name of the profile to use for the new window.
    :param command: A command to run in lieu of the shell in the new session.

    :throws: CreateWindowException if something went wrong.
    """
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
    self.tokens.append(await iterm2.notifications.subscribe_to_focus_change_notification(connection, self._focus_change))

