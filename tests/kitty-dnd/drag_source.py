#!/usr/bin/env python3
"""
Kitty drag-and-drop (OSC 72) test client: a DRAG SOURCE (it vends data).

Run it inside an iTerm2 session, then start a drag over the terminal window (the
gesture that iTerm2 uses to trigger a drag-out). This program offers some text, a
file, and a directory tree, and logs the drag lifecycle. Drop onto Finder,
TextEdit, another terminal, etc.

    python3 tests/kitty-dnd/drag_source.py [--machine-id] [-v]

It offers two MIME types:
  0: text/plain     "Dragged out of iTerm2 via OSC 72\n"
  1: text/uri-list  file:// URIs for a temp file and a temp directory tree

Data is pre-sent with t=p, so the lazy t=e:x=5 request path is usually not
exercised; it is still handled if the terminal asks.

When the terminal is on a different machine than this program (the remote
drag-out case), the terminal fetches each uri-list entry with t=k:x=idx. For a
directory entry this program PUSHES the directory listing (X=handle) and then
every descendant unsolicited via Y=parent-handle:y=num, as the protocol requires
(the terminal must not request children). Ctrl-C to quit.
"""

import argparse
import os
import select
import shutil
import sys
import tempfile
import termios
import tty

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kittydnd import build, chunked, OSC72Reader, machine_id  # noqa: E402

TEXT = b"Dragged out of iTerm2 via OSC 72\n"

# Enable button-event (drag) mouse reporting so the terminal treats a drag as
# reportable, which is what gates the drag-out gesture. SGR (1006) is included
# for completeness; this program ignores the mouse reports themselves.
MOUSE_REPORTING_ON = "\x1b[?1002h\x1b[?1006h"
MOUSE_REPORTING_OFF = "\x1b[?1002l\x1b[?1006l"


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
        self.tmp_root = tempfile.mkdtemp(prefix="kittydnd-")
        # The uri-list entries, in order: a plain file and a directory tree.
        self.entry_paths = self._make_tree()
        uri_list = "\r\n".join(self._uri(p) for p in self.entry_paths)
        self.data = [TEXT, uri_list.encode()]
        # Directory handles allocated while pushing (0 and 1 are reserved for the
        # file / symlink type indicators, so start at 2).
        self._next_handle = 2

    def _uri(self, path):
        # file:// URLs that point to a directory must end with a slash.
        return "file://" + path + ("/" if os.path.isdir(path) else "")

    def _make_tree(self):
        a_file = os.path.join(self.tmp_root, "note.txt")
        with open(a_file, "wb") as f:
            f.write(b"This file was dragged out of iTerm2.\n")

        a_dir = os.path.join(self.tmp_root, "folder")
        os.makedirs(os.path.join(a_dir, "sub"))
        with open(os.path.join(a_dir, "top.txt"), "wb") as f:
            f.write(b"top-level file inside the dragged folder\n")
        with open(os.path.join(a_dir, "sub", "deep.txt"), "wb") as f:
            f.write(b"a nested file\n")
        # A symlink the terminal must skip (its target is meaningless off-host).
        os.symlink("/etc/hosts", os.path.join(a_dir, "link"))
        return [a_file, a_dir]

    def start(self):
        os.write(1, MOUSE_REPORTING_ON.encode())
        # Send our machine id by default so a drag-out over plain ssh is detected
        # as cross-machine and fetched in-band (matching drop_target.py).
        payload = None if self.args.no_machine_id else machine_id()
        os.write(1, build({"t": "o", "x": "1"}, text_payload=payload).encode())
        log("[drag_source] offering enabled, mouse reporting on. Drag over the window.")
        log("[drag_source] offering: %s" % [os.path.basename(p) for p in self.entry_paths])
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
            self.begin_offer(md)
        elif t == "k":
            # The terminal is fetching our offered file(s) because we are on a
            # different machine (remote drag-out). It only ever requests a
            # top-level uri-list entry (t=k:x=idx); we push directory children.
            self.serve_entry(md)
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
                idx = int(md.get("y", "0"))
                data = self.data[idx] if 0 <= idx < len(self.data) else b""
                os.write(1, build({"t": "e", "y": str(idx), "m": "0"},
                                  data_payload=data).encode())

    def serve_entry(self, md):
        # The terminal must only request top-level entries (t=k:x=idx). A Y-keyed
        # request would be a protocol violation on its part.
        if md.get("Y") is not None:
            os.write(1, build({"t": "R", "Y": md["Y"], "y": md.get("y", "")},
                              text_payload="EINVAL").encode())
            log("[drag_source] unexpected child request; terminals must not send these")
            return
        idx = md.get("x")
        try:
            entry = int(idx) - 1
        except (TypeError, ValueError):
            entry = -1
        if not (0 <= entry < len(self.entry_paths)):
            os.write(1, build({"t": "R", "x": idx or ""}, text_payload="ENOENT").encode())
            return
        self._push(self.entry_paths[entry], {"x": idx})

    def _push(self, path, addressing):
        """Push one filesystem entry and, if it is a directory, all of its
        descendants (unsolicited), using Y=handle:y=num addressing."""
        if os.path.islink(path):
            target = os.readlink(path)
            for m in chunked(dict(addressing, t="k", X="1"), target.encode()):
                os.write(1, m.encode())
            log("[drag_source] served symlink %s" % os.path.basename(path))
            return
        if os.path.isdir(path):
            handle = self._next_handle
            self._next_handle += 1
            names = sorted(os.listdir(path))
            payload = "\0".join(names).encode()
            for m in chunked(dict(addressing, t="k", X=str(handle)), payload):
                os.write(1, m.encode())
            log("[drag_source] served dir %s (handle %d, %d entries)" %
                (os.path.basename(path), handle, len(names)))
            for i, name in enumerate(names):
                self._push(os.path.join(path, name),
                           {"Y": str(handle), "y": str(i + 1)})
            return
        with open(path, "rb") as f:
            data = f.read()
        for m in chunked(dict(addressing, t="k"), data):
            os.write(1, m.encode())
        log("[drag_source] served file %s (%d bytes)" % (os.path.basename(path), len(data)))

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
    # The machine id is sent by default; --machine-id is kept as a no-op.
    ap.add_argument("--machine-id", action="store_true", help="(default; kept for compatibility)")
    ap.add_argument("--no-machine-id", action="store_true",
                    help="do not send our machine id (treat drag-out as local)")
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
        # Stop offering drags on exit (spec: "On exit ... send t=o:x=2").
        os.write(1, build({"t": "o", "x": "2"}).encode())
        os.write(1, MOUSE_REPORTING_OFF.encode())
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        shutil.rmtree(source.tmp_root, ignore_errors=True)
    log("\n[drag_source] bye")
    return 0


if __name__ == "__main__":
    sys.exit(main())
