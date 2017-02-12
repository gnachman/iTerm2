#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

import api_pb2
import thread
import time
import websocket

callbacks = []

def handle_location_change_notification(location_change_notification):
    print "Location changed"
    print str(location_change_notification)

def SendRPC(ws, message, callback):
    ws.send(message.SerializeToString(), opcode=websocket.ABNF.OPCODE_BINARY)
    callbacks.append(callback)

def handle_notification(notification):
    if notification.HasField('location_change_notification'):
      handle_location_change_notification(notification.location_change_notification)

def handle_notification_response(response):
  if not response.HasField('notification_response'):
    print "Malformed notification response"
    print str(response)
    return
  if response.notification_response.status != api_pb2.NotificationResponse.OK:
    print "Bad status in notification response"
    print str(response)
    return
  print "Notifcation response ok"

def on_message(ws, message):
    response = api_pb2.Response()
    response.ParseFromString(message)
    if response.HasField('notification'):
      handle_notification(response.notification)
    else:
      global callbacks
      callback = callbacks[0]
      del callbacks[0]
      callback(response)

def on_error(ws, error):
    print "Error: " + str(error)

def on_close(ws):
    print "Connection closed"

def on_open(ws):
    print "Connection opened"
    request = api_pb2.Request()
    request.notification_request.subscribe = True
    request.notification_request.notification_type = api_pb2.NOTIFY_ON_LOCATION_CHANGE
    SendRPC(ws, request, handle_notification_response)

if __name__ == "__main__":
    websocket.enableTrace(True)
    ws = websocket.WebSocketApp("ws://localhost:1912/",
                              on_message = on_message,
                              on_error = on_error,
                              on_close = on_close,
                              subprotocols = [ 'api.iterm2.com' ])
    ws.on_open = on_open
    ws.run_forever()

