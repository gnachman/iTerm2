import iterm2.rpc

class SavedArrangementException(Exception):
  pass

class App:
  """Represents the application."""
  def __init__(self, connection):
    self.connection = connection

  async def activate(self, raise_all_windows=True, ignoring_other_apps=False):
    """Activate the app, giving it keyboard focus."""
    opts = []
    if raise_all_windows:
      opts.append(iterm2.rpc.ACTIVATE_RAISE_ALL_WINDOWS)
    if ignoring_other_apps:
      opts.append(iterm2.rpc.ACTIVATE_IGNORING_OTHER_APPS)
    await iterm2.rpc.activate(self.connection, False, False, False, activate_app_opts=opts)

  async def save_window_arrangement(self, name):
    """Save all windows as a new arrangement."""
    result = await iterm2.rpc.save_arrangement(self.connection, name)
    if result.create_tab_response.status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      raise SavedArrangementException(iterm2.api_pb2.SavedArrangementResponse.Status.Name(result.saved_arrangement_response.status))

  async def restore_window_arrangement(self, name):
    """Restore a saved window arrangement."""
    result = await iterm2.rpc.restore_arrangement(self.connection, name)
    if result.create_tab_response.status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
      raise SavedArrangementException(iterm2.api_pb2.SavedArrangementResponse.Status.Name(result.saved_arrangement_response.status))
