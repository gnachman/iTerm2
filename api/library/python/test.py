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

debug = False

def create_windows_and_tabs():
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

def read_keystrokes():
  def handle_keystroke(notification):
    print("Keypress\n" + str(notification))

  it2notifications.KeystrokeSubscription(s2.get_session_id(), handle_keystroke)
  while True:
    it2notifications.wait(1)

def watch_hierarchy():
  hierarchy = it2hierarchy.Hierarchy()
  while True:
    print(hierarchy.pretty_str())
    it2notifications.wait(1)

def main():
  if debug:
    logging.basicConfig(level=logging.DEBUG)
  else:
    logging.basicConfig()

  watch_hierarchy()

if __name__ == "__main__":
    main()

