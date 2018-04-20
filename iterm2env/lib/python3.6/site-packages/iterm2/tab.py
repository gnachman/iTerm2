class Tab:
  def __init__(self, connection, tab_id, root):
    self.connection = connection
    self.tab_id = tab_id
    self.root = root

  def __repr__(self):
    return "<Tab id=%s sessions=%s>" % (self.tab_id, self.sessions)

  def pretty_str(self, indent=""):
    s = indent + "Tab id=%s\n" % self.tab_id
    for j in self.sessions:
      s += j.pretty_str(indent=indent + "  ")
    return s

  def get_tab_id(self):
    return self.tab_id

  def get_sessions(self):
    return self.root.all_sessions()

  def get_root(self):
    return self.root

  def pretty_str(self, indent=""):
    s = indent + "Tab id=%s\n" % self.get_tab_id()
    s += self.root.pretty_str(indent=indent + "  ")
    return s
