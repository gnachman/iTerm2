#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import argparse
import dispatchq
import logging
import os
import select
import six
import sys
import thread
import threading
import time
import traceback
import websocket

class AsyncWebsocketApp(websocket.WebSocketApp):
  def __init__(self, url, on_message=None, on_error=None, on_close=None, subprotocols=None):
    websocket.WebSocketApp.__init__(self, url, on_message=on_message, on_error=on_error,
        on_close=on_close, subprotocols=subprotocols)
    self.dispatch_queue = dispatchq.IODispatchQueue()

  def run_async(self, sockopt=None, sslopt=None,
                ping_interval=0, ping_timeout=None,
                http_proxy_host=None, http_proxy_port=None,
                http_no_proxy=None, http_proxy_auth=None,
                skip_utf8_validation=False,
                host=None, origin=None):
      """
      run event loop for WebSocket framework.
      This loop is infinite loop and is alive during websocket is available.
      sockopt: values for socket.setsockopt.
          sockopt must be tuple
          and each element is argument of sock.setsockopt.
      sslopt: ssl socket optional dict.
      ping_interval: automatically send "ping" command
          every specified period(second)
          if set to 0, not send automatically.
      ping_timeout: timeout(second) if the pong message is not received.
      http_proxy_host: http proxy host name.
      http_proxy_port: http proxy port. If not set, set to 80.
      http_no_proxy: host names, which doesn't use proxy.
      skip_utf8_validation: skip utf8 validation.
      host: update host header.
      origin: update origin header.
      """

      if not ping_timeout or ping_timeout <= 0:
          ping_timeout = None
      if ping_timeout and ping_interval and ping_interval <= ping_timeout:
          raise WebSocketException("Ensure ping_interval > ping_timeout")
      if sockopt is None:
          sockopt = []
      if sslopt is None:
          sslopt = {}
      if self.sock:
          raise WebSocketException("socket is already opened")
      thread = None
      close_frame = None

      try:
          logging.debug("Starting")
          self.sock = websocket.WebSocket(
              self.get_mask_key, sockopt=sockopt, sslopt=sslopt,
              fire_cont_frame=self.on_cont_message and True or False,
              skip_utf8_validation=skip_utf8_validation)
          logging.debug("Created socket")
          self.sock.settimeout(websocket.getdefaulttimeout())
          logging.debug("Connecting")
          self.sock.connect(
              self.url, header=self.header, cookie=self.cookie,
              http_proxy_host=http_proxy_host,
              http_proxy_port=http_proxy_port, http_no_proxy=http_no_proxy,
              http_proxy_auth=http_proxy_auth, subprotocols=self.subprotocols,
              host=host, origin=origin)
          logging.debug("Calling on open")
          self._callback(self.on_open)

          if ping_interval:
              event = threading.Event()
              thread = threading.Thread(
                  target=self._send_ping, args=(ping_interval, event))
              thread.setDaemon(True)
              thread.start()

          logging.debug("Entering mainloop")
          while self.sock.connected:
              logging.debug("Background websocket client calling select")
              r, w, e = select.select(
                  (self.sock.sock, self.dispatch_queue.read_pipe), (), (), ping_timeout)
              if not self.keep_running:
                  break

              if r and self.dispatch_queue.read_pipe in r:
                logging.debug("Background websocket client running queued jobs")
                n = self.dispatch_queue.run_jobs()

              if r and self.sock.sock in r:
                  op_code, frame = self.sock.recv_data_frame(True)
                  if op_code == websocket.ABNF.OPCODE_CLOSE:
                      close_frame = frame
                      break
                  elif op_code == websocket.ABNF.OPCODE_PING:
                      self._callback(self.on_ping, frame.data)
                  elif op_code == websocket.ABNF.OPCODE_PONG:
                      self.last_pong_tm = time.time()
                      self._callback(self.on_pong, frame.data)
                  elif op_code == websocket.ABNF.OPCODE_CONT and self.on_cont_message:
                      self._callback(self.on_data, data,
                                     frame.opcode, frame.fin)
                      self._callback(self.on_cont_message,
                                     frame.data, frame.fin)
                  else:
                      data = frame.data
                      if six.PY3 and op_code == websocket.ABNF.OPCODE_TEXT:
                          data = data.decode("utf-8")
                      self._callback(self.on_data, data, frame.opcode, True)
                      self._callback(self.on_message, data)

              if ping_timeout and self.last_ping_tm \
                      and time.time() - self.last_ping_tm > ping_timeout \
                      and self.last_ping_tm - self.last_pong_tm > ping_timeout:
                  raise WebSocketTimeoutException("ping/pong timed out")
          logging.debug("While loop exited")
      except (Exception, KeyboardInterrupt, SystemExit) as e:
          traceback.print_exc()
          self._callback(self.on_error, e)
          if isinstance(e, SystemExit):
              # propagate SystemExit further
              raise
      finally:
          logging.debug("Everything has gone to shit")
          if thread and thread.isAlive():
              event.set()
              thread.join()
              self.keep_running = False
          if self.sock is not None:
              self.sock.close()
          close_args = self._get_close_args(
              close_frame.data if close_frame else None)
          self._callback(self.on_close, *close_args)
          self.sock = None

