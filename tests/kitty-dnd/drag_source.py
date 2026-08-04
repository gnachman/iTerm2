#!/usr/bin/env python3
"""
Kitty drag-and-drop (OSC 72) test client: a DRAG SOURCE (it vends data).

Run it inside an iTerm2 session, then start a drag over the terminal window (the
gesture that iTerm2 uses to trigger a drag-out). This program offers some text
and a file, and logs the drag lifecycle. Drop onto Finder, TextEdit, etc.

    python3 tests/kitty-dnd/drag_source.py [--machine-id] [-v]

It offers two MIME types:
  0: text/plain     "Dragged out of iTerm2 via OSC 72\n"
  1: text/uri-list  a file:// URI to a temp file it creates

Data is pre-sent with t=p, so the lazy t=e:x=5 request path is usually not
exercised; it is still handled if the terminal asks. Ctrl-C to quit.
"""

import argparse
import os
import select
import sys
import tempfile
import termios
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kittydnd import build, OSC72Reader, machine_id  # noqa: E402

TEXT = b"Dragged out of iTerm2 via OSC 72\n"


def log(msg):
    sys.stderr.write(msg + "\r\n")
    sys.stderr.flush()


_EVENT_NAMES = {"1": "accepted", "2": "action-changed", "3": "dropped",
                "4": "finished", "5": "request-data"}


class DragSource:
    def __init__(self, args):
        self.args = args
        self.reader = OSC72Reader()
        self.mimes = ["text/plain", "text/uri-list"]
        self.tmp_path = self._make_temp_file()
        self.data = [TEXT, ("file://" + self.tmp_path).encode()]

    def _make_temp_file(self):
        fd, path = tempfile.mkstemp(prefix="kittydnd-", suffix=".txt")
        os.write(fd, b"This file was dragged out of iTerm2.\n")
        os.close(fd)
        return path

    def start(self):
        payload = None
        if self.args.machine_id:
            payload = machine_id()
        os.write(1, build({"t": "o", "x": "1"}, text_payload=payload).encode())
        log("[drag_source] offering enabled. Start a drag over the window.")
        log("[drag_source] (requires mouse-reporting mode per the iTerm2 design.)")
        log("[drag_source] temp file: %s" % self.tmp_path)
        log("[drag_source] Ctrl-C to quit.")

    def begin_offer(self, md):
        log("[drag_source] gesture at cell (%s,%s); offering %s" %
            (md.get("x"), md.get("y"), self.mimes))
        os.write(1, build({"t": "o", "o": "1"},
                          text_payload=" ".join(self.mimes)).encode())
        for i, payload in enumerate(self.data):
            os.write(1, build({"t": "p", "x": str(i)}, data_payload=payload).encode())
        os.write(1, build({"t": "P", "x": "-1"}).encode())
        log("[drag_source] pre-sent data and started drag (t=P)")

    def handle(self, md, payload):
        t = md.get("t")
        if t == "o":
            # Terminal reports a drag gesture; make our offer.
            self.begin_offer(md)
        elif t == "E":
            if payload == "OK":
                log("[drag_source] drag started OK")
            else:
                log("[drag_source] status/error: %s" % payload)
        elif t == "e":
            sub = md.get("x")
            name = _EVENT_NAMES.get(sub, "?")
            log("[drag_source] event: %s %s" % (name, dict(md)))
            if sub == "5":
                # Lazy data request for MIME index y.
                idx = int(md.get("y", "0"))
                data = self.data[idx] if 0 <= idx < len(self.data) else b""
                os.write(1, build({"t": "e", "y": str(idx), "m": "0"},
                                  data_payload=data).encode())

    def run(self):
        fd = sys.stdin.fileno()
        while True:
            select.select([fd], [], [], None)
            data = os.read(fd, 4096)
            if not data or b"\x03" in data:
                break
            for md, payload in self.reader.feed(data):
                self.handle(md, payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--machine-id", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if not sys.stdin.isatty():
        log("Run this in an interactive iTerm2 session.")
        return 2

    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    source = DragSource(args)
    try:
        tty.setraw(fd)
        source.start()
        source.run()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        try:
            os.remove(source.tmp_path)
        except OSError:
            pass
    log("\n[drag_source] bye")
    return 0


if __name__ == "__main__":
    sys.exit(main())
