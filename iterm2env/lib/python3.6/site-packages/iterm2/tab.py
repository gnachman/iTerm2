import iterm2.rpc

class Tab:
  """Represents a tab."""
  def __init__(self, connection, tab_id, root):
    self.connection = connection
    self.tab_id = tab_id
    self.root = root

  def __repr__(self):
    return "<Tab id=%s sessions=%s>" % (self.tab_id, self.get_sessions())

  def get_tab_id(self):
    """
    Returns: The tab's identifier
    """
    return self.tab_id

  def get_sessions(self):
    """
    Returns: A list of iterm2.session.Session objects belonging to this tab.
    """
    return self.root.all_sessions()

  def get_root(self):
    """
    Returns: An iterm2.session.Splitter forming the root of this tab's session tree.
    """
    return self.root

  def pretty_str(self, indent=""):
    """
    Returns: A human readable description of the tab and its sessions.
    """
    s = indent + "Tab id=%s\n" % self.get_tab_id()
    s += self.root.pretty_str(indent=indent + "  ")
    return s

  async def select(self, order_window_front=True):
    """
    Selects this tab.

    order_window_front: Whether the window this session is in should be
      brought to the front and given keyboard focus.
    """
    await iterm2.rpc.activate(self.connection, False, True, order_window_front, tab_id=self.tab_id)
