#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import api_pb2
from sharedstate import get_socket, wait, register_notification_handler
import dispatchq
import session
import socket
import tab
import logging
import threading
import time

_subscriptions = {}
_dispatch_queue = dispatchq.IdleDispatchQueue()
_cond = threading.Condition()

class Subscription(object):
  def __init__(self, notification_type, session_id, handler):
    self.notification_type = notification_type
    self.session_id = session_id
    self.handler = handler
    self.key = (session_id, notification_type)

    global _subscriptions
    if self.key not in _subscriptions:
      _subscriptions[self.key] = []
    _subscriptions[self.key].append(self)

    self.future = get_socket().request_subscribe(True, notification_type, session_id)

  def unsubscribe(self):
    _subscriptions[self.key].remove(self)
    get_socket().request_subscribe(False, self.notification_type, self.session_id)

  def handle(self, notification):
    self.handler(notification)

class NewSessionSubscription(Subscription):
  def __init__(self, handler):
    Subscription.__init__(self, api_pb2.NOTIFY_ON_NEW_SESSION, None, handler)

class TerminateSessionSubscription(Subscription):
  def __init__(self, handler):
    Subscription.__init__(self, api_pb2.NOTIFY_ON_TERMINATE_SESSION, None, handler)

class KeystrokeSubscription(Subscription):
  def __init__(self, session_id, handler):
    Subscription.__init__(self, api_pb2.NOTIFY_ON_KEYSTROKE, session_id, handler)

class LayoutChangeSubscription(Subscription):
  def __init__(self, handler):
    Subscription.__init__(self, api_pb2.NOTIFY_ON_LAYOUT_CHANGE, None, handler)


def _extract(notification):
  key = None

  if notification.HasField('keystroke_notification'):
    key = (notification.keystroke_notification.session, api_pb2.NOTIFY_ON_KEYSTROKE)
    notification=notification.keystroke_notification
  elif notification.HasField('screen_update_notification'):
    key = (notification.screen_update_notification.session, api_pb2.NOTIFY_ON_SCREEN_UPDATE)
    notification = notification.screen_update_notification
  elif notification.HasField('prompt_notification'):
    key = (notification.prompt_notification.session, api_pb2.NOTIFY_ON_PROMPT)
    notification = notification.prompt_notification
  elif notification.HasField('location_change_notification'):
    key = (notification.location_change_notification.session, api_pb2.NOTIFY_ON_LOCATION_CHANGE)
    notification = notification.location_change_notification
  elif notification.HasField('custom_escape_sequence_notification'):
    key = (notification.custom_escape_sequence_notification.session,
        api_pb2.NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE)
    notification = notification.custom_escape_sequence_notification
  elif notification.HasField('new_session_notification'):
    key = (None, api_pb2.NOTIFY_ON_NEW_SESSION)
    notification = notification.new_session_notification
  elif notification.HasField('terminate_session_notification'):
    key = (None, api_pb2.NOTIFY_ON_TERMINATE_SESSION)
    notification = notification.terminate_session_notification
  elif notification.HasField('layout_changed_notification'):
    key = (None, api_pb2.NOTIFY_ON_LAYOUT_CHANGE)
    notification = notification.layout_changed_notification

  return key, notification

def _dispatch_handle_notification(notification):
  def _run_handlers():
    key, sub_notification = _extract(notification)
    logging.debug("Got a notification to dispatch. key=" + str(key) +", notification=\n" + str(notification))
    if key in _subscriptions:
      handlers = _subscriptions[key]
      if handlers is not None:
        for handler in handlers:
          handler.handle(sub_notification)
  _dispatch_queue.dispatch_async(_run_handlers)

def wait(timeout=None):
  n = _dispatch_queue.wait(timeout)
  return n

def quick_wait():
  n = _dispatch_queue.wait(0)

register_notification_handler(_dispatch_handle_notification)
socket.add_idle_observer(quick_wait)


