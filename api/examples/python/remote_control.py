#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import api_pb2
import sys
import thread
import time
import websocket

callbacks = []
DEBUG=0

def SendRPC(ws, message, callback):
    if DEBUG > 0:
      print(">>> " + str(message))
    ws.send(message.SerializeToString(), opcode=websocket.ABNF.OPCODE_BINARY)
    callbacks.append(callback)

def handle_notification(ws, notification):
    def handle_custom_escape_sequence_notification(custom_escape_sequence_notification):
        # -- Your logic goes here --
        print(custom_escape_sequence_notification.sender_identity + " sends message " + custom_escape_sequence_notification.payload)

    def handle_new_session_notification(new_session_notification):
        subscribe_to_custom_escape_sequence(ws, new_session_notification.uniqueIdentifier)

    if notification.HasField('custom_escape_sequence_notification'):
      handle_custom_escape_sequence_notification(notification.custom_escape_sequence_notification)
    elif notification.HasField('new_session_notification'):
      handle_new_session_notification(notification.new_session_notification)

def handle_notification_response(response):
  if not response.HasField('notification_response'):
    print("Malformed notification response")
    print(str(response))
    return
  if response.notification_response.status != api_pb2.NotificationResponse.OK:
    print("Bad status in notification response")
    print(str(response))
    return

def subscribe_to_new_sessions(ws):
    request = api_pb2.Request()
    request.notification_request.subscribe = True
    request.notification_request.notification_type = api_pb2.NOTIFY_ON_NEW_SESSION
    SendRPC(ws, request, handle_notification_response)

def subscribe_to_custom_escape_sequence(ws, session):
    request = api_pb2.Request()
    request.notification_request.subscribe = True
    request.notification_request.session = session
    request.notification_request.notification_type = api_pb2.NOTIFY_ON_CUSTOM_ESCAPE_SEQUENCE
    SendRPC(ws, request, handle_notification_response)

def main(argv):
    def on_message(ws, message):
        response = api_pb2.Response()
        response.ParseFromString(message)
        if DEBUG > 0:
          print("<<< " + str(response))
        if response.HasField('notification'):
          handle_notification(ws, response.notification)
        else:
          global callbacks
          callback = callbacks[0]
          del callbacks[0]
          callback(response)

    def on_error(ws, error):
        print("Error: " + str(error))

    def on_close(ws):
        print("Connection closed")

    def on_open(ws):
        def list_sessions(ws):
            def callback(response):
              for window in response.list_sessions_response.windows:
                  for tab in window.tabs:
                      for session in tab.sessions:
                          subscribe_to_custom_escape_sequence(ws, session.uniqueIdentifier)
            request = api_pb2.Request()
            request.list_sessions_request.SetInParent()
            SendRPC(ws, request, callback)

        subscribe_to_new_sessions(ws)
        list_sessions(ws)

    #websocket.enableTrace(True)
    ws = websocket.WebSocketApp("ws://localhost:1912/",
                              on_message = on_message,
                              on_error = on_error,
                              on_close = on_close,
                              subprotocols = [ 'api.iterm2.com' ])
    ws.on_open = on_open
    ws.run_forever()

if __name__ == "__main__":
    main(sys.argv)


