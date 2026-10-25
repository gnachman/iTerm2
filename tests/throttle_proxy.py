#!/usr/bin/env python3
"""An ssh ProxyCommand that slows the server-to-client direction, to make a slow link out of
localhost. Used by the flow control live tests in SSHIntegrationLiveHarness.

Usage: ssh -o ProxyCommand='python3 tests/throttle_proxy.py %h %p 20480' localhost

The rate is in bytes per second. Options:
  --rate-file PATH  Read the rate from PATH instead, whenever it changes, so a test can slow the
                    link down or speed it up mid-session, as Network Link Conditioner does. 0, or
                    a missing or unreadable file, means unlimited.
  --delay SECONDS   Hold each piece for this long first, in both directions, for a path with a
                    real round trip.
"""
import argparse
import collections
import os
import socket
import threading
import time


def read_rate(path, default):
    if path is None:
        return default
    try:
        with open(path) as f:
            return float(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def delayed_pipe(read, write, delay):
    """Copies from `read` to `write`, each piece `delay` seconds after it was read."""
    if delay <= 0:
        while True:
            data = read()
            if not data:
                return
            write(data)
    pending = collections.deque()
    ready = threading.Condition()
    done = []

    def reader():
        while True:
            data = read()
            with ready:
                pending.append((time.monotonic() + delay, data))
                ready.notify()
            if not data:
                return

    threading.Thread(target=reader, daemon=True).start()
    while True:
        with ready:
            while not pending:
                ready.wait()
            due, data = pending.popleft()
        wait = due - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        if not data:
            return
        write(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("port", type=int)
    parser.add_argument("rate", type=float)
    parser.add_argument("--rate-file")
    parser.add_argument("--delay", type=float, default=0)
    args = parser.parse_args()
    conn = socket.create_connection((args.host, args.port))

    def upstream():
        delayed_pipe(lambda: os.read(0, 65536), conn.sendall, args.delay)
        conn.shutdown(socket.SHUT_WR)

    threading.Thread(target=upstream, daemon=True).start()

    # Downstream: pieces leave no faster than the rate, after the delay.
    state = {"rate": read_rate(args.rate_file, args.rate), "checked": time.monotonic(),
             "started": time.monotonic(), "sent": 0}

    def paced_write(data):
        now = time.monotonic()
        if args.rate_file is not None and now - state["checked"] >= 0.1:
            state["checked"] = now
            rate = read_rate(args.rate_file, args.rate)
            if rate != state["rate"]:
                state.update(rate=rate, started=now, sent=0)
        os.write(1, data)
        rate = state["rate"]
        if rate <= 0:
            return
        state["sent"] += len(data)
        ahead = state["sent"] / rate - (time.monotonic() - state["started"])
        if ahead > 0:
            time.sleep(ahead)

    def receive():
        rate = state["rate"]
        return conn.recv(65536 if rate <= 0 else max(1, int(rate / 50)))

    delayed_pipe(receive, paced_write, args.delay)


if __name__ == "__main__":
    main()
