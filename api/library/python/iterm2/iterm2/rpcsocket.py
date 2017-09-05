from .asyncws import AsyncWebsocketApp

import api_pb2
import logging
import _synchronouscb as synchronouscb
import threading
import websocket

class RPCSocket(AsyncWebsocketApp):
  def __init__(self, handler, url, subprotocols):
    AsyncWebsocketApp.__init__(self, url, on_message=self._on_rpc_message, subprotocols=subprotocols)
    self.waiting = False
    self.callbacks = []
    self.callbacks_cond = threading.Condition()
    self.handler = handler
    thread = threading.Thread(target=self.run_async)
    thread.setDaemon(True)
    logging.debug("Kick off background websocket client")
    thread.start()

  def sync_send_rpc(self, message):
    callback = synchronouscb.SynchronousCallback()
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
    self.callbacks_cond.acquire()
    self.callbacks.append(callback)
    self.callbacks_cond.release()

  def _on_rpc_message(self, ws, message):
    logging.debug("Got an RPC message")
    parsed = self.handler(message)
    if parsed is not None:
      logging.debug("Running the next callback")
      self.callbacks_cond.acquire()
      callback = self.callbacks[0]
      del self.callbacks[0]
      self.callbacks_cond.notify_all()
      self.callbacks_cond.release()
      if not self.waiting:
        callback(parsed)
    else:
      logging.debug("Notifying unparsed message")
      self.callbacks_cond.acquire()
      self.callbacks_cond.notify_all()
      self.callbacks_cond.release()

  def finish(self):
    """Blocks until all outstanding RPCs have completed. Does not run callbacks."""
    logging.debug("Finish acquiring lock")
    self.callbacks_cond.acquire()
    logging.debug("Finish invoked with " + str(len(self.callbacks)) + " callbacks left")
    self.waiting = True
    while len(self.callbacks) > 0:
      future.idle_spin()
      logging.debug("Finish waiting...")
      self.callbacks_cond.wait()
    logging.debug("Finish done")
    self.callbacks_cond.release()
