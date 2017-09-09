#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function
import api_pb2
import _future as future
import notifications
import session
from _sharedstate import get_socket, wait
import socket
import tab
import window
import logging

class _Synchronizer(object):
  def __init__(self):
    notifications.NewSessionSubscription(lambda notification: self._refresh())
    notifications.TerminateSessionSubscription(lambda notification: self._refresh())
    notifications.LayoutChangeSubscription(self._layoutDidChange)

    self.value = None
    self._refresh()

  def _refresh(self):
    logging.debug("Refreshing hierarchy")
    self.future = get_socket().request_hierarchy()

  def _layoutDidChange(self, notification):
    logging.debug("Layout did change")
    self.future = future.Future()
    self.future.callback(notification.list_sessions_response)

  def get(self):
    if self.future is not None:
      return self.future.get()
    return None

class Hierarchy(object):
  """Stores a representation of iTerm2's window-tab-session hierarchy. Also used to create new windows."""
  def __init__(self):
    self.synchronizer = _Synchronizer()
    self.windows = None

  def pretty_str(self):
    """Returns the hierarchy as a human-readable string"""
    s = ""
    for w in self.get_windows():
      if len(s) > 0:
        s += "\n"
      s += w.pretty_str(indent="")
    return s

  def get_windows(self):
    """Gets the current windows.

    Returns:
      An array of Window objects."""
    newValue = self.synchronizer.get()
    if newValue is not None:
      self._parse(newValue)
    return self.windows

  def create_window(self, profile=None, command=None):
    """Creates a new window.

    Arguments;
      profile: The name of the profile to use for the window's first session. If None, the default profile will be used.
      command: A command to run in lieu of the default command or login shell, if not None.
    """
    return window.FutureWindow(get_socket().request_create_tab(
      profile=profile, window=None, index=None, command=command))

  def _parse(self, response):
    windows = []
    for w in response.windows:
      tabs = []
      for t in w.tabs:
        sessions = []
        for s in t.sessions:
          sessions.append(session.Session(s.uniqueIdentifier))
        tabs.append(tab.Tab(t.tab_id, sessions))
      windows.append(window.Window(w.window_id, tabs))
    self.windows = windows

  def __repr__(self):
    return "<Hierarchy windows=%s>" % self.get_windows()

