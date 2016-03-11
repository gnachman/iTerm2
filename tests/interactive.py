#!/usr/bin/python2.7

import base64
import sys

def OSC():
  return chr(27) + "]1337;"

def ST():
  return str(chr(7))

def SendCommand(key, value):
  sys.stdout.write(OSC() + key + "=" + value + ST())
  sys.stdout.flush()

def ReadOSC():
  osc = sys.stdin.read(7)
  b = sys.stdin.read(1)
  data = ""
  while b != chr(7):
    data = data + b
    b = sys.stdin.read(1)
  return data

def SendDisconnectCommand():
  SendCommand("DisconnectFromNativeView", identifier)

def SendAcceptHeightCommand(height):
  SendCommand("NativeViewHeightAccepted", "%s;%s" % (identifier, str(height)))

def SendLoadCommand(name, args):
  SendCommand("NativeView", base64.b64encode(args))

SendLoadCommand("NativeView",
                """
                { "app": "WebView",
                  "arguments": {
                    "url": "%s"
                  }
                }""" % sys.argv[1])

try:
  while True:
    data = ReadOSC()
    key, value = data.split("=")
    identifier, proposed = value.split(";")
    SendCommand("NativeViewHeightAccepted", "%s;%s" % (identifier, proposed))
except KeyboardInterrupt:
  print "^C"


