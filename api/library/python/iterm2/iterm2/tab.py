#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

from sharedstate import get_socket, wait
import api_pb2
import session
import _socket as socket
import logging

class AbstractTab(object):
  def __repr__(self):
    raise NotImplementedError("unimplemented")

  def get_tab_id(self):
    raise NotImplementedError("unimplemented")

  def get_sessions(self):
    raise NotImplementedError("unimplemented")

  def pretty_str(self, indent=""):
    s = indent + "Tab id=%s\n" % self.get_tab_id()
    for j in self.get_sessions():
      s += j.pretty_str(indent=indent + "  ")
    return s

class FutureTab(AbstractTab):
  def __init__(self, future):
    self.future = future
    self.tab = None
    self.status = None

  def __repr__(self):
    return "<FutureTab status=%s tab=%s>" % (str(self.get_status()), repr(self._get_tab()))

  def get_tab_id(self):
    return self._get_tab().get_tab_id()

  def get_sessions(self):
    return self._get_tab().get_sessions()

  def get_status(self):
    self.parse_if_needed()
    return self.status

  def _get_tab(self):
    self._parse_if_needed()
    return self.tab

  def _parse_if_needed(self):
    if self.future is not None:
      self._parse(self.future.get())
      self.future = None

  def _parse(self, response):
    self.status = response.status
    if self.status == api_pb2.CreateTabResponse.OK:
       self.tab = Tab(response.tab_id, [ session.Session(response.session_id) ])

class Tab(AbstractTab):
  def __init__(self, tab_id, sessions):
    self.tab_id = tab_id
    self.sessions = sessions

  def __repr__(self):
    return "<Tab id=%s sessions=%s>" % (self.tab_id, self.sessions)

  def get_tab_id(self):
    return self.tab_id

  def get_sessions(self):
    return self.sessions

