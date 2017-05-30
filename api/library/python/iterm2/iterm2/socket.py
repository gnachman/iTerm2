#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import api_pb2
import rpcsocket
import logging

_idle_observers = []

def add_idle_observer(observer):
  _idle_observers.append(observer)

class Future(rpcsocket.SynchronousCallback):
  def __init__(self, transform=None):
    rpcsocket.SynchronousCallback.__init__(self)
    if transform is None:
      self.transform = lambda x: x
    else:
      self.transform = transform
    self.transformed_response = None
    self.watches = []

  def get(self):
    if self.transformed_response is None:
      logging.debug("Waiting on future")
      self.wait()
      logging.debug("REALIZING %s" % str(self))
      self.transformed_response = self.transform(self.response)
      assert self.transformed_response is not None
      self._invoke_watches(self.transformed_response)
    return self.transformed_response

  def _invoke_watches(self, response):
    watches = self.watches
    self.watches = None
    for watch in watches:
      watch(response)

  def watch(self, callback):
    if self.watches is not None:
      logging.debug("Add watch to %s", str(self))
      self.watches.append(callback)
    else:
      logging.debug("Immediately run callback for watch for %s" % str(self))
      callback(self.get())

  def wait(self):
    for o in _idle_observers:
      o()
    rpcsocket.SynchronousCallback.wait(self)

class DependentFuture(Future):
  """If you have a future A and you want to create future B, but B can't be
  created yet because the information needed to make it doesn't exist yet, use
  this. This provides a future C that creates B when A is realized. Its get()
  blocks until A and B are both realized."""
  def __init__(self, parent, create_inner):
    Future.__init__(self)
    self.parent = parent
    self.innerFuture = None
    self.create_inner = create_inner
    parent.watch(self._parent_did_realize)

  def _parent_did_realize(self, response):
    logging.debug("PARENT REALIZED FOR %s" % str(self.parent))
    self.innerFuture = self.create_inner(response)
    for watch in self.watches:
      self.innerFuture.watch(watch)
    self.watches = None

  def get(self):
    logging.debug("Dependent future %s getting parent future %s" % (str(self), str(self.parent)))
    parent = self.parent.get()
    logging.debug("Dependent future %s got parent from future %s, produced inner future %s" % (str(self), str(self.parent), str(self.innerFuture)))
    return self.innerFuture.get()

class Connection(object):
  def __init__(self):
    self.last_future = None

  def wait(self):
    if self.last_future is not None:
      self.last_future.get()
      self.last_future = None

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
    future = Future(transform)
    self.ws.async_send_rpc(request.SerializeToString(), future.callback)
    self.last_future = future
    return future

  def _handler(self, message):
    response = api_pb2.Response()
    response.ParseFromString(message)
    if response.HasField('notification'):
      self.notification_handler(response.notification)
      return None
    else:
      logging.debug("Got a non-notification message" + str(response))
      return response

