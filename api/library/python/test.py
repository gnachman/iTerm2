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

def main():
  #  logging.basicConfig(level=logging.DEBUG)
  logging.basicConfig()
  hierarchy = it2hierarchy.Hierarchy()

  window = hierarchy.create_window()
  tab = window.create_tab()
  session = tab.get_sessions()[0]
  s2 = session.split_pane(vertical=True).split_pane()
  s2.send_text("Hello world").get_status()

  def handle_keystroke(notification):
    print("YOU PRESSED A DAMN KEY")

  it2notifications.KeystrokeSubscription(s2.get_session_id(), handle_keystroke)
  it2notifications.wait(5)

if __name__ == "__main__":
    main()

