import iterm2.rpc

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
