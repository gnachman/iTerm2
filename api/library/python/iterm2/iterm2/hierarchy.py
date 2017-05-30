#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function
import api_pb2
from sharedstate import get_socket, wait
import notifications
import session
import socket
import tab
import window
import logging

class Synchronizer(object):
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
    self.future = socket.Future()
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
    for w in response.windows:
      tabs = []
      for t in w.tabs:
        sessions = []
        for s in t.sessions:
          sessions.append(session.Session(s.uniqueIdentifier))
        tabs.append(tab.Tab(t.tab_id, sessions))
      windows.append(window.Window(w.window_id, tabs))
    self.windows = windows

  def create_window(self, profile=None, command=None):
    return window.FutureWindow(get_socket().request_create_tab(
      profile=profile, window=None, index=None, command=command))

  def __repr__(self):
    return "<Hierarchy windows=%s>" % self.get_windows()

