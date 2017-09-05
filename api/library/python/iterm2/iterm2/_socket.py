#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import api_pb2
import _future as future
import _rpcsocket as rpcsocket
import logging

class Connection(object):
  def __init__(self):
    self.last_future = None

  def wait(self):
    if self.last_future is not None:
      self.last_future.get()
      self.last_future = None

  def finish(self):
    self.ws.finish()

  def connect(self, notification_handler):
    self.notification_handler = notification_handler;
    self.ws = rpcsocket.RPCSocket(
        self._handler,
        "ws://localhost:1912/",
        subprotocols = [ 'api.iterm2.com' ])

  def request_hierarchy(self):
    return self._send_async(self._list_sessions_request(),
        lambda response: response.list_sessions_response)

  def _list_sessions_request(self):
    request = api_pb2.Request()
    request.list_sessions_request.SetInParent()
    return request

  def request_send_text(self, session_id, text):
      return self._send_async(self._send_text_request(session_id, text),
          lambda response: response.send_text_response)

  def _send_text_request(self, session_id, text):
    request = api_pb2.Request()
    if session_id is not None:
      request.send_text_request.session = session_id
    request.send_text_request.text = text
    return request

  def request_create_tab(self, profile=None, window=None, index=None, command=None):
    return self._send_async(
        self._create_tab_request(profile=profile, window=window, index=index, command=command),
        lambda response: response.create_tab_response)

  def _create_tab_request(self, profile=None, window=None, index=None, command=None):
    request = api_pb2.Request()
    request.create_tab_request.SetInParent()
    if profile is not None:
      request.create_tab_request.profile_name = profile
    if window is not None:
      request.create_tab_request.window_id = window
    if index is not None:
      request.create_tab_request.tab_index = index
    if command is not None:
      request.create_tab_request.command = command
    return request

  def request_split_pane(self, session=None, vertical=False, before=False, profile=None):
    return self._send_async(
        self._split_pane_request(session=session, vertical=vertical, before=before, profile=profile),
        lambda response: response.split_pane_response)

  def _split_pane_request(self, session=None, vertical=False, before=False, profile=None):
    request = api_pb2.Request()
    request.split_pane_request.SetInParent()
    if session is not None:
      request.split_pane_request.session = session
    if vertical:
      request.split_pane_request.split_direction = api_pb2.SplitPaneRequest.VERTICAL
    else:
      request.split_pane_request.split_direction = api_pb2.SplitPaneRequest.HORIZONTAL;
    request.split_pane_request.before = False
    if profile is not None:
      request.split_pane_request.profile_name = profile
    return request;

  def request_subscribe(self, subscribe, notification_type, session=None):
    return self._send_async(
        self._subscribe_request(subscribe, notification_type, session=session),
        lambda response: response.notification_response)

  def _subscribe_request(self, subscribe, notification_type, session=None):
    request = api_pb2.Request()
    if session is not None:
      request.notification_request.session = session
    request.notification_request.subscribe = subscribe
    request.notification_request.notification_type = notification_type
    return request

  def _send_sync(self, request):
    return self.ws.sync_send_rpc(request.SerializeToString())

  def _send_async(self, request, transform):
    f = future.Future(transform)
    self.ws.async_send_rpc(request.SerializeToString(), f.callback)
    self.last_future = f
    return f

  def _handler(self, message):
    response = api_pb2.Response()
    response.ParseFromString(message)
    if response.HasField('notification'):
      self.notification_handler(response.notification)
      return None
    else:
      logging.debug("Got a non-notification message" + str(response))
      return response

