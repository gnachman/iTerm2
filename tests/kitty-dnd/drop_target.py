#!/usr/bin/env python3
"""
Kitty drag-and-drop (OSC 72) test client: a DROP TARGET.

Run it inside an iTerm2 session, then drag files/text/images from Finder (or any
app) onto the terminal window. It announces which MIME types it accepts, logs the
hover and drop events, requests the dropped data, and prints (or saves) it.

    python3 tests/kitty-dnd/drop_target.py [--machine-id] [--outdir DIR] [-v]

  --machine-id  Also send our hashed machine id (so a same-machine drop is
                treated as local; omit to keep it simple).
  --outdir DIR  Save each received payload to a file in DIR instead of printing.
  -v            Verbose: also log every hover (t=m) event.

Ctrl-C to quit.
"""

import argparse
import base64
import os
import select
import sys
import termios
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kittydnd import build, OSC72Reader, machine_id  # noqa: E402

ACCEPTED = "text/uri-list text/plain image/png application/octet-stream"


def log(msg):
    sys.stderr.write(msg + "\r\n")
    sys.stderr.flush()


class DropTarget:
    def __init__(self, args):
        self.args = args
        self.reader = OSC72Reader()
        self.offered = []          # MIME list from the last t=M
        self.queue = []            # 1-based indices still to request
        self.accum = bytearray()   # reassembly buffer for the in-flight request

    def start(self):
        payload = ACCEPTED
        if self.args.machine_id:
            mid = machine_id()
            if mid:
                payload = ACCEPTED + " " + mid
        os.write(1, build({"t": "a", "x": "1"}, text_payload=payload).encode())
        log("[drop_target] announced accept: %s" % ACCEPTED)
        log("[drop_target] drag something onto the window. Ctrl-C to quit.")

    def request_next(self):
        if not self.queue:
            return
        idx = self.queue[0]
        self.accum = bytearray()
        mime = self.offered[idx - 1] if idx - 1 < len(self.offered) else "?"
        log("[drop_target] requesting #%d (%s)" % (idx, mime))
        os.write(1, build({"t": "r", "x": str(idx)}).encode())

    def finish_current(self, remote):
        idx = self.queue.pop(0)
        mime = self.offered[idx - 1] if idx - 1 < len(self.offered) else "?"
        data = bytes(self.accum)
        tag = " [X=1 remote]" if remote else ""
        if self.args.outdir:
            os.makedirs(self.args.outdir, exist_ok=True)
            path = os.path.join(self.args.outdir, "drop-%d.bin" % idx)
            with open(path, "wb") as f:
                f.write(data)
            log("[drop_target] #%d (%s)%s -> %s (%d bytes)" %
                (idx, mime, tag, path, len(data)))
        else:
            preview = data[:200].decode("utf-8", "replace")
            log("[drop_target] #%d (%s)%s %d bytes: %r" %
                (idx, mime, tag, len(data), preview))
        self.request_next()

    def handle(self, md, payload):
        t = md.get("t")
        if t == "m":
            if self.args.verbose:
                log("[drop_target] hover cell (%s,%s) ops=%s" %
                    (md.get("x"), md.get("y"), md.get("o")))
            # Indicate we accept a copy of whatever is offered.
            if payload:
                os.write(1, build({"t": "m", "o": "1"}, text_payload=payload).encode())
        elif t == "M":
            self.offered = (payload or "").split()
            log("[drop_target] DROP at cell (%s,%s) offering: %s" %
                (md.get("x"), md.get("y"), self.offered))
            self.queue = list(range(1, len(self.offered) + 1))
            self.request_next()
        elif t == "r":
            if payload:
                self.accum += base64.b64decode(payload)
            if md.get("m") != "1":
                self.finish_current(remote=md.get("X") == "1")
        elif t == "R":
            log("[drop_target] ERROR for #%s: %s" % (md.get("x"), payload))
            if self.queue:
                self.queue.pop(0)
            self.request_next()

    def run(self):
        fd = sys.stdin.fileno()
        while True:
            select.select([fd], [], [], None)
            data = os.read(fd, 4096)
            if not data or b"\x03" in data:  # EOF or Ctrl-C
                break
            for md, payload in self.reader.feed(data):
                self.handle(md, payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--machine-id", action="store_true")
    ap.add_argument("--outdir", default=None)
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if not sys.stdin.isatty():
        log("Run this in an interactive iTerm2 session.")
        return 2

    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        target = DropTarget(args)
        target.start()
        target.run()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    log("\n[drop_target] bye")
    return 0


if __name__ == "__main__":
    sys.exit(main())
