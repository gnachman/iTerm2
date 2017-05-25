#!/usr/bin/python
# This is python 2.7 on macOS 10.12.

from __future__ import print_function

import it2hierarchy
import it2global
import it2notifications
import it2session
import it2socket
import logging
import time

import code, traceback, signal

def main():
  #logging.basicConfig(level=logging.DEBUG)
  logging.basicConfig()

  def handle_new_session(notification):
    print("New session created\n" + str(notification))

  logging.debug("Register for new sessions")
  it2notifications.NewSessionSubscription(handle_new_session)

  logging.debug("Get hierarchy")
  hierarchy = it2hierarchy.Hierarchy()

  logging.debug("Create window")
  window = hierarchy.create_window()
  logging.debug("Create tab")
  tab = window.create_tab()
  logging.debug("Get sessions")
  session = tab.get_sessions()[0]
  logging.debug("Splitting pane")
  s2 = session.split_pane(vertical=True).split_pane()
  s2.send_text("Hello world").get_status()

  def handle_keystroke(notification):
    print("Keypress\n" + str(notification))

  it2notifications.KeystrokeSubscription(s2.get_session_id(), handle_keystroke)
  while True:
    it2notifications.wait(1)

if __name__ == "__main__":
    main()

