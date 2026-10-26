#!/usr/bin/env python3
"""The cc-status shim execs `it2 handle-agent-hook` beside it, forwarding its arguments and its
stdin untouched. This drives the built binary with a fake sibling it2 that records both.

    swift build -c release && python3 tests/shim_test.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE_IT2 = r'''#!/bin/sh
printf '%s\n' "$@" > "$SHIM_TEST_ARGS"
cat > "$SHIM_TEST_STDIN"
exit 7
'''


def build_binary():
    subprocess.run(["swift", "build", "-c", "release"], cwd=ROOT, check=True,
                   stdout=subprocess.DEVNULL)
    return os.path.join(ROOT, ".build", "release", "cc-status")


def main():
    binary = os.environ.get("CC_STATUS_BIN") or build_binary()
    workdir = tempfile.mkdtemp(prefix="cc-status-shim-")
    try:
        shim = os.path.join(workdir, "cc-status")
        shutil.copy(binary, shim)
        fake = os.path.join(workdir, "it2")
        with open(fake, "w") as f:
            f.write(FAKE_IT2)
        os.chmod(fake, 0o755)
        args_path = os.path.join(workdir, "args")
        stdin_path = os.path.join(workdir, "stdin")
        payload = b'{"hook_event_name":"Stop"}\n'
        result = subprocess.run([shim, "--agent", "codex"], input=payload,
                                env={"PATH": "/usr/bin:/bin", "SHIM_TEST_ARGS": args_path,
                                     "SHIM_TEST_STDIN": stdin_path},
                                capture_output=True)
        ok = True
        with open(args_path) as f:
            args = f.read().split("\n")[:-1]
        if args != ["handle-agent-hook", "--agent", "codex"]:
            print("FAIL: arguments: %r" % args)
            ok = False
        with open(stdin_path, "rb") as f:
            seen = f.read()
        if seen != payload:
            print("FAIL: stdin: %r" % seen)
            ok = False
        if result.returncode != 7:
            print("FAIL: exit status %d is not it2's" % result.returncode)
            ok = False
        if result.stdout or result.stderr:
            print("FAIL: output: %r %r" % (result.stdout, result.stderr))
            ok = False
        print("PASS" if ok else "FAILED")
        return 0 if ok else 1
    finally:
        shutil.rmtree(workdir)


if __name__ == "__main__":
    sys.exit(main())
