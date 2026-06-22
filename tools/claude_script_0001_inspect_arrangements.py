#!/usr/bin/env python3
"""Inspect saved Window Projects arrangements (cold storage).

Decodes the base64-encoded window arrangements stored in
~/Library/Application Support/iTerm2/WindowProjects.json and reports, per
archived window:
  - decoded plist size (42 bytes == empty dict == capture produced nothing)
  - whether it carries a multiserver "Server Dict" (Socket + Child PID), which
    is what session restoration needs in order to re-attach to a live orphaned
    iTermServer child instead of spawning a fresh shell.
  - the actual Server Dict contents
  - whether the top-level "Archive" key is present (only affects window sizing
    on restore; NOT required for re-attachment).

Optionally cross-checks each Server Dict's Child PID against the live process
table so you can see whether the orphaned job is still running right now.

Usage:
    python3 tools/claude_script_0001_inspect_arrangements.py [path-to-json]
    python3 tools/claude_script_0001_inspect_arrangements.py --dump PROJECT_NAME
"""
import base64
import json
import os
import plistlib
import subprocess
import sys

DEFAULT = os.path.expanduser(
    "~/Library/Application Support/iTerm2/WindowProjects.json"
)


def iter_windows(projects, prefix=""):
    for proj in projects:
        name = proj.get("name", "?")
        for w in proj.get("windows", []):
            yield (prefix + name, w)
        yield from iter_windows(proj.get("children", []), prefix + name + "/")


def find_key(node, key, path="root"):
    """Yield (path, value) for every occurrence of `key` in a nested plist."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                yield (path, v)
            yield from find_key(v, key, f"{path}.{k}")
    elif isinstance(node, list):
        for i, x in enumerate(node):
            yield from find_key(x, key, f"{path}[{i}]")


def live_pids():
    out = subprocess.run(["ps", "-axo", "pid="], capture_output=True, text=True).stdout
    return {int(x) for x in out.split()}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dump = "--dump" in sys.argv
    path = args[0] if args and not dump else (args[1] if dump and len(args) > 1 else DEFAULT)

    if dump:
        target = args[0]
        d = json.load(open(DEFAULT))
        for name, w in iter_windows(d):
            if target in name:
                pl = plistlib.loads(base64.b64decode(w["arrangementBase64"]))
                print(json.dumps(pl, indent=2, default=str))
                return
        print(f"no window matching {target!r}")
        return

    d = json.load(open(path))
    alive = live_pids()
    rows = []
    for name, w in iter_windows(d):
        raw = base64.b64decode(w["arrangementBase64"])
        try:
            pl = plistlib.loads(raw)
        except Exception:
            pl = None
        sds = list(find_key(pl, "Server Dict")) if pl else []
        has_archive = bool(pl and "Archive" in pl)
        rows.append((name, w.get("name"), len(raw), sds, has_archive))

    rows.sort(key=lambda r: -r[2])
    print(f"{'project/window':40} {'bytes':>9} {'archive':>7}  server-dicts (Socket/ChildPID  alive?)")
    print("-" * 100)
    for name, wname, nbytes, sds, has_archive in rows:
        label = f"{name} [{wname}]"
        sd_str = ""
        for _, sd in sds:
            pid = sd.get("Child PID")
            sock = sd.get("Socket")
            sd_str += f"  sock{sock}/pid{pid}{'(ALIVE)' if pid in alive else '(dead)'}"
        if not sds and nbytes <= 64:
            sd_str = "  <EMPTY arrangement>"
        print(f"{label[:40]:40} {nbytes:>9} {str(has_archive):>7} {sd_str}")


if __name__ == "__main__":
    main()
