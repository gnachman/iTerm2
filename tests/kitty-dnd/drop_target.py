#!/usr/bin/env python3
"""
Kitty drag-and-drop (OSC 72) test client: a DROP TARGET.

Run it inside an iTerm2 session, then drag files/text/images from Finder (or any
app) onto the terminal window. It announces which MIME types it accepts, logs the
hover and drop events, requests the dropped data, and prints (or saves) it.

    python3 tests/kitty-dnd/drop_target.py [--machine-id] [--outdir DIR] [-v]

  --machine-id  Also send our hashed machine id, so a same-machine drop is
                treated as local and a drop from another machine (plain ssh) is
                treated as remote (X=1) and transferred in-band. Required to test
                the cross-machine path over plain ssh.
  --outdir DIR  Directory to save received/cross-machine files into
                (default: a temp dir).
  -v            Verbose: also log every hover (t=m) event.

Cross-machine drops: when the uri-list comes back flagged X=1, the files live on
another machine, so we pull each one by sub-index (t=r:x=1:y=idx), recreating
regular files, symlinks, and directories (recursively, via handles) under
--outdir. Ctrl-C to quit.
"""

import argparse
import base64
import os
import select
import sys
import tempfile
import termios
import tty
from collections import deque

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
        self.outdir = args.outdir or tempfile.mkdtemp(prefix="kittydnd-drop-")
        # Sequential request/response state.
        self.accum = bytearray()
        self.current = None          # the in-flight request's handler context
        self.pending = deque()       # queued requests: (metadata, context)
        self.uri_mime_index = None   # 1-based index of text/uri-list in t=M
        self.handle_remaining = {}   # dir handle -> children still outstanding

    # MARK: - Lifecycle

    def start(self):
        payload = ACCEPTED
        if self.args.machine_id:
            mid = machine_id()
            if mid:
                payload = ACCEPTED + " " + mid
        os.write(1, build({"t": "a", "x": "1"}, text_payload=payload).encode())
        log("[drop_target] announced accept: %s" % ACCEPTED)
        log("[drop_target] saving cross-machine files under: %s" % self.outdir)
        log("[drop_target] drag something onto the window. Ctrl-C to quit.")

    # MARK: - Request queue (sequential)

    def enqueue(self, metadata, context):
        self.pending.append((metadata, context))
        if self.current is None:
            self.dispatch_next()

    def dispatch_next(self):
        if self.current is not None or not self.pending:
            return
        metadata, context = self.pending.popleft()
        self.current = context
        self.accum = bytearray()
        os.write(1, build(metadata).encode())

    def on_complete_response(self, md):
        context = self.current
        self.current = None
        data = bytes(self.accum)
        if context is not None:
            context["handler"](md, data, context)
        self.dispatch_next()

    def on_error(self, md, payload):
        log("[drop_target] ERROR %s: %s" % (dict(md), payload))
        self.current = None
        self.dispatch_next()

    # MARK: - Drop handling

    def handle(self, md, payload):
        t = md.get("t")
        if t == "m":
            if self.args.verbose:
                log("[drop_target] hover cell (%s,%s) ops=%s" %
                    (md.get("x"), md.get("y"), md.get("o")))
            if payload:
                os.write(1, build({"t": "m", "o": "1"}, text_payload=payload).encode())
        elif t == "M":
            offered = (payload or "").split()
            log("[drop_target] DROP at cell (%s,%s) offering: %s" %
                (md.get("x"), md.get("y"), offered))
            if "text/uri-list" in offered:
                self.uri_mime_index = offered.index("text/uri-list") + 1
                self.enqueue({"t": "r", "x": str(self.uri_mime_index)},
                             {"handler": self.on_uri_list})
            else:
                # Just fetch and print the first offered type.
                self.enqueue({"t": "r", "x": "1"}, {"handler": self.on_plain_data})
        elif t == "r":
            if payload:
                self.accum += base64.b64decode(payload)
            if md.get("m") != "1":
                self.on_complete_response(md)
        elif t == "R":
            self.on_error(md, payload)

    def on_plain_data(self, md, data, context):
        preview = data[:200].decode("utf-8", "replace")
        log("[drop_target] data (%d bytes): %r" % (len(data), preview))

    def on_uri_list(self, md, data, context):
        uris = data.decode("utf-8", "replace").split("\r\n")
        uris = [u for u in (u.strip() for u in uris) if u and not u.startswith("#")]
        if md.get("X") == "1":
            log("[drop_target] cross-machine drop; pulling %d item(s) in-band" % len(uris))
            for subidx, uri in enumerate(uris, start=1):
                name = os.path.basename(uri.rstrip("/")) or "item-%d" % subidx
                self.enqueue({"t": "r", "x": str(self.uri_mime_index), "y": str(subidx)},
                             {"handler": self.on_entry,
                              "dest": os.path.join(self.outdir, name),
                              "parent": None})
        else:
            log("[drop_target] local drop; usable paths: %s" % uris)

    def on_entry(self, md, data, context):
        dest = context["dest"]
        x = md.get("X")
        if x is None:
            # Regular file.
            self._write_file(dest, data)
            log("[drop_target] saved file: %s (%d bytes)" % (dest, len(data)))
        elif x == "1":
            # Symlink; payload is the link target.
            self._make_symlink(dest, data.decode("utf-8", "replace"))
            log("[drop_target] recreated symlink: %s" % dest)
        else:
            # Directory; payload is a null-separated list of names, X is a handle.
            handle = int(x)
            names = [n for n in data.split(b"\x00") if n]
            os.makedirs(dest, exist_ok=True)
            log("[drop_target] directory %s (%d entries)" % (dest, len(names)))
            self.handle_remaining[handle] = len(names)
            if not names:
                self._free_handle(handle)
            for num, raw in enumerate(names, start=1):
                child = os.path.join(dest, raw.decode("utf-8", "replace"))
                self.enqueue({"t": "r", "Y": str(handle), "x": str(num)},
                             {"handler": self.on_entry, "dest": child, "parent": handle})
        parent = context.get("parent")
        if parent is not None:
            self.handle_remaining[parent] -= 1
            if self.handle_remaining[parent] == 0:
                self._free_handle(parent)

    def _free_handle(self, handle):
        self.handle_remaining.pop(handle, None)
        os.write(1, build({"t": "r", "Y": str(handle)}).encode())

    def _write_file(self, dest, data):
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data)

    def _make_symlink(self, dest, target):
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        try:
            if os.path.lexists(dest):
                os.remove(dest)
            os.symlink(target, dest)
        except OSError as e:
            log("[drop_target] symlink failed: %s" % e)

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
