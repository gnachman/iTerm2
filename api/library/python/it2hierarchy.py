#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function
from it2global import get_socket, wait
import it2socket
import it2tab
import it2window
import api_pb2

class Hierarchy(object):
  def __init__(self):
    self.windows = None
    self.future = get_socket().request_hierarchy()

  def get_windows(self):
    if self.future is not None:
      self.parse(self.future.get())
      self.future = None
    return self.windows

  def parse(self, response):
    windows = []
    for window in response.windows:
      tabs = []
      for tab in window.tabs:
        sessions = []
        for session in tab.sessions:
          sessions.append(Session(session.uniqueIdentifier))
        tabs.append(it2tab.Tab(None, sessions))
      windows.append(it2window.Window(None, tabs))
    self.windows = windows

  def create_window(self, profile=None, command=None):
    return it2window.FutureWindow(get_socket().request_create_tab(
      profile=profile, window=None, index=None, command=command))

  def __repr__(self):
    return "<Hierarchy windows=%s>" % self.get_windows()

