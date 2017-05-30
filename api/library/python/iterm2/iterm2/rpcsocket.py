from .asyncws import AsyncWebsocketApp

import api_pb2
import logging
import threading
import websocket

class SynchronousCallback(object):
  def __init__(self):
    self.cond = threading.Condition()
    self.response = None

  def callback(self, r):
    logging.debug("Callback invoked")
    self.cond.acquire()
    self.response = r
    self.cond.notify_all()
    self.cond.release()

  def wait(self):
    logging.debug("Waiting for callback to be invoked")
    self.cond.acquire()
    while self.response is None:
      self.cond.wait()
    logging.debug("Callback was invoked")
    self.cond.release()

class RPCSocket(AsyncWebsocketApp):
  def __init__(self, handler, url, subprotocols):
    AsyncWebsocketApp.__init__(self, url, on_message=self._on_rpc_message, subprotocols=subprotocols)
    self.callbacks = []
    self.callbacks_lock = threading.Lock()
    self.handler = handler
    thread = threading.Thread(target=self.run_async)
    thread.setDaemon(True)
    logging.debug("Kick off background websocket client")
    thread.start()

  def sync_send_rpc(self, message):
    callback = SynchronousCallback()
    def f():
      logging.debug("Send request")
      self.send(message, opcode=websocket.ABNF.OPCODE_BINARY)
    self.dispatch_async(f)
    self._append_callback(callback.callback)
    logging.debug("Wait for callback")
    callback.wait()
    logging.debug("Done waiting")
    return callback.response

  def async_send_rpc(self, message, callback):
    def f():
      request = api_pb2.Request()
      request.ParseFromString(message)
      logging.debug("SEND:\n" + str(request))
      self.send(message, opcode=websocket.ABNF.OPCODE_BINARY)
    self.dispatch_queue.dispatch_async(f)
    self._append_callback(callback)

  def _append_callback(self, callback):
    self.callbacks_lock.acquire()
    self.callbacks.append(callback)
    self.callbacks_lock.release()

  def _on_rpc_message(self, ws, message):
    parsed = self.handler(message)
    if parsed is not None:
      logging.debug("Running the next callback")
      self.callbacks_lock.acquire()
      callback = self.callbacks[0]
      del self.callbacks[0]
      self.callbacks_lock.release()
      callback(parsed)
