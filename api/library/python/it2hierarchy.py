#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function
import api_pb2
from it2global import get_socket, wait
import it2notifications
import it2session
import it2socket
import it2tab
import it2window
import logging

class Synchronizer(object):
  def __init__(self):
    it2notifications.NewSessionSubscription(lambda notification: self._refresh())
    it2notifications.TerminateSessionSubscription(lambda notification: self._refresh())
    it2notifications.LayoutChangeSubscription(self._layoutDidChange)

    self.value = None
    self._refresh()

  def _refresh(self):
    logging.debug("Refreshing hierarchy")
    self.future = get_socket().request_hierarchy()

  def _layoutDidChange(self, notification):
    logging.debug("Layout did change")
    self.future = it2socket.Future()
    self.future.callback(notification.list_sessions_response)

  def get(self):
    if self.future is not None:
      return self.future.get()
    return None

class Hierarchy(object):
  def __init__(self):
    self.synchronizer = Synchronizer()
    self.windows = None

  def pretty_str(self):
    s = ""
    for w in self.get_windows():
      if len(s) > 0:
        s += "\n"
      s += w.pretty_str(indent="")
    return s

  def get_windows(self):
    newValue = self.synchronizer.get()
    if newValue is not None:
      self.parse(newValue)
    return self.windows

  def parse(self, response):
    windows = []
    for window in response.windows:
      tabs = []
      for tab in window.tabs:
        sessions = []
        for session in tab.sessions:
          sessions.append(it2session.Session(session.uniqueIdentifier))
        tabs.append(it2tab.Tab(tab.tab_id, sessions))
      windows.append(it2window.Window(window.window_id, tabs))
    self.windows = windows

  def create_window(self, profile=None, command=None):
    return it2window.FutureWindow(get_socket().request_create_tab(
      profile=profile, window=None, index=None, command=command))

  def __repr__(self):
    return "<Hierarchy windows=%s>" % self.get_windows()

