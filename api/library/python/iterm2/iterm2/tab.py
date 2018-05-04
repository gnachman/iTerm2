import iterm2.rpc

class Tab:
    """Represents a tab."""
    def __init__(self, connection, tab_id, root):
        self.connection = connection
        self.__tab_id = tab_id
        self.__root = root
        self.active_session_id = None

    def __repr__(self):
        return "<Tab id=%s sessions=%s>" % (self.__tab_id, self.get_sessions())

    def update_from(self, other):
        """Copies state from another tab into this one."""
        self.__root = other.root
        self.active_session_id = other.active_session_id

    def update_session(self, s):
        """Replaces references to a session."""
        self.__root.update_session(s)

    @property
    def tab_id(self):
        """
        Each tab has a globally unique identifier.

        :returns: The tab's identifier.
        """
        return self.__tab_id

    @property
    def sessions(self):
        """
        A tab contains a list of sessions, which are its split panes.

        :returns: A list of iterm2.session.Session objects belonging to this tab.
        """
        return self.__root.sessions

    @property
    def root(self):
        """
        A tab's sessions are stored in a tree. This returns the root.

        An interior node of the tree is a Splitter. That corresponds to a
        collection of adjacent sessions with split pane dividers that are all
        either vertical or horizontal.

        Leaf nodes are Sessions.

        :returns: An iterm2.session.Splitter forming the root of this tab's session tree.
        """
        return self.__root

    def pretty_str(self, indent=""):
        """
        :returns: A human readable description of the tab and its sessions.
        """
        s = indent + "Tab id=%s\n" % self.tab_id
        s += self.__root.pretty_str(indent=indent + "  ")
        return s

    async def async_select(self, order_window_front=True):
        """
        Selects this tab.

        :param order_window_front: Whether the window this session is in should be
          brought to the front and given keyboard focus.
        """
        await iterm2.rpc.async_activate(self.connection, False, True, order_window_front, tab_id=self.__tab_id)
