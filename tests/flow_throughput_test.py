#!/usr/bin/env python3
# How fast a flood comes through SSH Integration, with flow control on or off, over a path that
# can be throttled (such as Network Link Conditioner on the machine running iTerm2, which does not
# shape loopback, so the far host has to be reached over a real interface).
#
# Launches a built iTerm2 under its own suite, opens `it2ssh HOST` (and with --hops 2, `it2ssh
# INNER` inside it), times `head -c BYTES /dev/zero | tr '\0' y` in the innermost shell, and
# prints the time and rate. Ctrl-C afterwards is timed too: how long the prompt takes to answer.
#
# Requirements: as for nested_ssh_restart_test.py (the iterm2 Python package and the suite's
# disable-automation-auth file), key-based ssh to HOST, and with --hops 2, ~/.iterm2/it2ssh and
# key-based ssh to INNER on HOST.
#
# Run it on a test VM, e.g.:
#   tools/run_tests_vm.sh --host vm2 -- python3 tests/flow_throughput_test.py --host nlc-far --pacing on
# Pass --app when the VM has builds from other checkouts: the default is the newest Development
# build in DerivedData, which may not be this tree's.

import argparse
import asyncio
import os
import re
import subprocess
import sys
import time

import iterm2

from nested_ssh_restart_test import IT2SSH, Instance, connect, find_app, screen, wait_for


async def answers(session, tag, timeout):
    await session.async_send_text(f'echo "{tag}-$((6*7))"\n')
    return await wait_for(session, rf"^{tag}-42", timeout) is not None


async def wait_with_progress(session, pattern, timeout, what):
    """Like wait_for, printing now and then so a quiet run is not taken for a hung one."""
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        match = await wait_for(session, pattern, 30)
        if match:
            return match
        print(f"  still waiting for {what} after {time.monotonic() - start:.0f} s", flush=True)
    return None


async def run(options):
    connection = await connect()
    window = await iterm2.Window.async_create(connection)
    session = window.current_tab.current_session
    if not await answers(session, "local", 30):
        return "FAIL the local shell does not answer"
    hops = [options.host] + ([options.inner] if options.hops == 2 else [])
    for depth, host in enumerate(hops):
        it2ssh = IT2SSH if depth == 0 else "~/.iterm2/it2ssh"
        await session.async_send_text(f"{it2ssh} {host}\n")
        await asyncio.sleep(5)
        if not await answers(session, f"hop{depth}", 120):
            return f"FAIL no shell at depth {depth} ({host})"
        level = await session.async_get_variable("sshIntegrationLevel")
        if int(level or 0) != 2:
            return f"FAIL depth {depth} ({host}) is not framed (sshIntegrationLevel {level})"
    print(f"connected through {' -> '.join(hops)}; flooding {options.bytes} bytes", flush=True)
    await session.async_send_text(
        f"clear; time (head -c {options.bytes} /dev/zero | tr '\\0' y); echo; echo \"flood-done-$((6*7))\"\n")
    match = await wait_with_progress(session, r"^real\s+(?:(\d+)m)?([\d.]+)s", options.timeout, "the flood")
    if not match:
        return "FAIL the flood did not finish"
    seconds = int(match.group(1) or 0) * 60 + float(match.group(2))
    # Ctrl-C at the prompt after a second flood starts: how long it takes to answer.
    await session.async_send_text("yes interrupt-me\n")
    await asyncio.sleep(10)
    start = time.monotonic()
    await session.async_send_text("\x03")
    answered = await answers(session, "after-interrupt", 120)
    interrupt = time.monotonic() - start
    for depth in reversed(range(len(hops))):
        await session.async_send_text("exit\n")
        await asyncio.sleep(2)
    return (f"RESULT hops={options.hops} pacing={options.pacing} bytes={options.bytes} "
            f"seconds={seconds:.1f} rate={options.bytes / seconds / 1024:.1f}KB/s "
            f"ctrl-c={'%.1fs' % interrupt if answered else 'no answer'}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=None)
    parser.add_argument("--suite", default="iterm2-restart-test")
    parser.add_argument("--host", required=True)
    parser.add_argument("--hops", type=int, choices=(1, 2), default=1)
    parser.add_argument("--inner", default="localhost")
    parser.add_argument("--pacing", choices=("on", "off"), required=True)
    parser.add_argument("--bytes", type=int, default=20_000_000)
    parser.add_argument("--timeout", type=float, default=1800)
    options = parser.parse_args()
    # The iterm2 module finds the suite's API socket by this.
    os.environ["IT2_SUITE"] = options.suite
    with open("/tmp/flow_throughput_test.log", "w") as log:
        instance = Instance(options.app or find_app(), options.suite, log)
        print(f"app: {instance.app}", flush=True)
        instance.configure()
        subprocess.run(["defaults", "write", options.suite, "SshFlowControl", "-bool",
                        "true" if options.pacing == "on" else "false"], check=True)
        try:
            instance.launch()
            result = asyncio.run(run(options))
            print(result, flush=True)
            return 0 if result.startswith("RESULT") else 1
        finally:
            instance.kill()
            instance.clean()
            subprocess.run(["defaults", "delete", options.suite, "SshFlowControl"])


if __name__ == "__main__":
    sys.exit(main())
