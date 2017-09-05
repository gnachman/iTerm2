#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import api_pb2
import _depfuture as depfuture
import _future as future
from _sharedstate import get_socket, wait as sharedstate 
import _socket as socket
import logging
import notifications

class TextSender(object):
  def __init__(self, future):
    self.future = future
    self.status = None

  def get_status(self):
    if self.future is not None:
      logging.debug("Getting future %s" % str(self.future))
      self.parse(self.future.get())
      self.future = None
    return self.status

  def parse(self, response):
    self.status = response.status


class AbstractSession(object):
  def __repr__(self):
    raise NotImplementedError("unimplemented")

  def get_session_id(self):
    raise NotImplementedError("unimplemented")

  def pretty_str(self, indent=""):
    return indent + "Session id=%s\n" % self.get_session_id()


class FutureSession(AbstractSession):
  def __init__(self, future):
    self.future = future
    self.session = None

  def __repr__(self):
    return "<FutureSession status=%s session=%s>" % (str(self.get_status()), repr(self._get_session()))

  def get_session_id(self):
    return self._get_session().get_session_id()

  def send_text(self, text):
    if self.future is None:
      return self._get_session().send_text(text)

    def create_inner(response):
      return get_socket().request_send_text(self.get_session_id(), text)
    sendTextFuture = depfuture.DependentFuture(self.future, create_inner)
    return TextSender(sendTextFuture)

  def split_pane(self, vertical=False, before=False, profile=None):
    if self.future is None:
      return self._get_session().split_pane(vertical=vertical, before=before, profile=profile)

    def create_inner(response):
      return get_socket().request_split_pane(
          session=self.get_session_id(), vertical=vertical, before=before, profile=profile)
    createSessionFuture = depfuture.DependentFuture(self.future, create_inner)
    return FutureSession(createSessionFuture);

  def _get_session(self):
    self._parse_if_needed()
    return self.session

  def _parse_if_needed(self):
    if self.future is not None:
      self._parse(self.future.get())
      self.future = None

  def _parse(self, response):
    self.status = response.status
    if self.status == api_pb2.SplitPaneResponse.OK:
       self.session = Session(response.session_id)

class Session(AbstractSession):
  def __init__(self, session_id=None):
    self.session_id = session_id

  def __repr__(self):
    return "<Session id=%s>" % self.session_id

  def get_session_id(self):
    return self.session_id

  def send_text(self, text):
    return TextSender(get_socket().request_send_text(self.session_id, text))

  def split_pane(self, vertical=False, before=False, profile=None):
    return FutureSession(get_socket().request_split_pane(
      session=self.session_id, vertical=vertical, before=before, profile=profile))

  def read_keystroke(self):
    """Blocks until a keystroke is received. Returns a KeystrokeNotification."""
    f = future.Future()
    def callback(keystroke_notification):
      f.callback(keystroke_notification)
    subscription = notifications.KeystrokeSubscription(self.session_id, callback)
    # Can't do f.get() here because we need to keep dispatching notifications on the main thread
    # until we get the notification we care about.
    while not f.realized():
      notifications.wait()
    return f.get()

