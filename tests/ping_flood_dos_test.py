#!/usr/bin/env python3
"""Reproduce and verify the fix for the WebSocket ping-flood memory-exhaustion
issue in iTerm2's Python API server.

Background
----------
The API server speaks WebSocket over a Unix domain socket. A client that floods
PING frames but never reads the PONGs the server sends back used to make the
server buffer pongs without limit, so iTerm2's memory climbed quickly (the
original report). The fix bounds the number of outstanding (not-yet-flushed)
pongs; once a misbehaving peer that stops reading exceeds that bound, the server
disconnects it instead of buffering.

What this script does
---------------------
1. Connects to the API server's Unix socket.
2. Performs the WebSocket upgrade handshake (authenticating with a cookie/key).
3. Floods masked PING frames and deliberately never reads the PONGs, modelling
   the malicious "never drains" peer.
4. Watches for the server to disconnect us, and (optionally) samples iTerm2's
   resident memory throughout.

Interpreting the result
-----------------------
* FIXED   -> the server closes the connection after a bounded amount of data,
             and iTerm2's RSS stays roughly flat.
* VULNERABLE -> the connection stays open indefinitely while iTerm2's RSS climbs.

The Python API must be enabled (Settings > General > Magic > Enable Python API).

Prefer running via run_ping_flood_dos_test.sh, which builds a venv with the one
dependency (psutil) used for memory sampling.
"""

import argparse
import os
import socket
import subprocess
import sys
import threading
import time

# The library version we advertise. Must be >= the server's minimum; a large
# number keeps this working across future minimum bumps.
LIBRARY_VERSION = "python 1000.0"


def app_support_name(suite):
    """The Application Support subdirectory the target iTerm2 uses.

    iTerm2 keys it on its -suite name (falling back to the bundle name "iTerm2").
    A dev build launched by `make run` uses -suite <repo dir name> and sets
    IT2_APP_PATH to "<repo>/Build/<config>/iTerm2.app", so the suite is the path
    component just before "/Build/". An explicit --suite always wins."""
    if suite:
        return suite
    env = os.environ.get("IT2_APP_PATH", "")
    if "/Build/" in env:
        repo = env.split("/Build/", 1)[0]
        return os.path.basename(repo.rstrip("/"))
    return "iTerm2"


def default_socket_path(suite):
    return os.path.expanduser(
        "~/Library/Application Support/%s/private/socket" % app_support_name(suite)
    )


def applescript_target():
    """Mirror the it2 CLI: target the instance named by IT2_APP_PATH (an app name
    or a bundle path both work as an AppleScript specifier), else "iTerm2". This
    disambiguates when several same-bundle-id iTerm2 builds are running."""
    env = os.environ.get("IT2_APP_PATH")
    if env:
        return 'application "%s"' % env
    return 'application "iTerm2"'


def obtain_cookie_and_key(app_name):
    """Ask the running iTerm2 for a single-use cookie and connection key via
    AppleScript. Returns (cookie, key)."""
    script = (
        "tell %s to request cookie and key for app named \"%s\""
        % (applescript_target(), app_name)
    )
    try:
        out = subprocess.check_output(
            ["osascript", "-e", script], stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        raise SystemExit(
            "Failed to get an API cookie via AppleScript. Is the Python API "
            "enabled and is exactly one iTerm2 running?\n" + e.output.decode()
        )
    parts = out.decode().strip().split()
    if len(parts) != 2:
        raise SystemExit(
            "Unexpected cookie/key response: %r (expected '<cookie> <key>')"
            % out
        )
    return parts[0], parts[1]


def handshake(sock, cookie, key):
    """Perform the RFC 6455 upgrade the API server requires. Raises on failure."""
    # A random 16-byte nonce, base64-encoded. We do not bother validating the
    # server's Sec-WebSocket-Accept; a 101 status is enough for this test.
    import base64

    nonce = base64.b64encode(os.urandom(16)).decode()
    headers = [
        "GET / HTTP/1.1",
        "Host: localhost",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Origin: ws://localhost/",
        "Sec-WebSocket-Version: 13",
        "Sec-WebSocket-Key: " + nonce,
        "Sec-WebSocket-Protocol: api.iterm2.com",
        "x-iterm2-library-version: " + LIBRARY_VERSION,
        "x-iterm2-advisory-name: ping-flood-dos-test",
        "x-iterm2-disable-auth-ui: true",
        "x-iterm2-cookie: " + cookie,
        "x-iterm2-key: " + key,
    ]
    sock.sendall(("\r\n".join(headers) + "\r\n\r\n").encode())

    # Read until the end of the response headers.
    response = b""
    while b"\r\n\r\n" not in response:
        chunk = sock.recv(4096)
        if not chunk:
            raise SystemExit("Server closed the connection during handshake.")
        response += chunk
        if len(response) > 65536:
            raise SystemExit("Handshake response too large; giving up.")
    status_line = response.split(b"\r\n", 1)[0].decode(errors="replace")
    if "101" not in status_line:
        raise SystemExit("Handshake was rejected: %s" % status_line)


def make_ping_batch(count):
    """A blob of `count` masked, zero-length PING frames.

    Client frames must be masked (RFC 6455). With an empty payload the mask is
    irrelevant, so a zero mask keeps each frame a tidy 6 bytes:
    0x89 (FIN+ping), 0x80 (masked, length 0), then the 4 mask-key bytes.
    """
    return b"\x89\x80\x00\x00\x00\x00" * count


class RSSMonitor:
    """Samples a process's resident set size on a background thread."""

    def __init__(self, pid):
        self.pid = pid
        self._stop = threading.Event()
        self._thread = None
        self.baseline = None
        self.peak = None

    def _run(self, proc):
        while not self._stop.is_set():
            try:
                rss = proc.memory_info().rss
            except Exception:
                break
            if self.baseline is None:
                self.baseline = rss
            self.peak = rss if self.peak is None else max(self.peak, rss)
            self._stop.wait(0.2)

    def start(self):
        import psutil

        proc = psutil.Process(self.pid)
        self.baseline = proc.memory_info().rss
        self.peak = self.baseline
        self._thread = threading.Thread(target=self._run, args=(proc,), daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=1)


def autodetect_pid():
    """Return the pid of iTerm2 if exactly one is running, else None."""
    try:
        import psutil
    except ImportError:
        return None
    matches = []
    for proc in psutil.process_iter(["pid", "name"]):
        name = (proc.info.get("name") or "")
        if name in ("iTerm2", "iTerm2.debug") or name.startswith("iTerm2"):
            matches.append(proc.info["pid"])
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        sys.stderr.write(
            "Multiple iTerm2 processes found (%s); pass --pid to monitor memory.\n"
            % ", ".join(map(str, matches))
        )
    return None


def human_bytes(n):
    if n is None:
        return "n/a"
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024:
            return "%.1f %s" % (n, unit)
        n /= 1024
    return "%.1f TB" % n


def flood(sock, monitor, max_pings, deadline, batch_pings):
    """Send pings without reading pongs until the server disconnects us, we hit
    the ping cap, or we run out of time. Returns (verdict, pings_sent, elapsed)."""
    batch = make_ping_batch(batch_pings)
    sent = 0
    start = time.time()
    # A per-send timeout keeps us from blocking forever if the server stops
    # reading without closing; a stalled send is itself a sign the peer is gone.
    sock.settimeout(5.0)
    while sent < max_pings and time.time() < deadline:
        try:
            sock.sendall(batch)
        except (BrokenPipeError, ConnectionResetError):
            return ("closed", sent, time.time() - start)
        except socket.timeout:
            # Our send buffer is full and the server is not draining it. With
            # the fix this happens right around when the server tears the
            # connection down. Probe once to distinguish a closed peer from mere
            # backpressure without draining pongs wholesale.
            try:
                sock.settimeout(2.0)
                if sock.recv(1) == b"":
                    return ("closed", sent, time.time() - start)
            except (BrokenPipeError, ConnectionResetError):
                return ("closed", sent, time.time() - start)
            except socket.timeout:
                pass
            finally:
                sock.settimeout(5.0)
            continue
        sent += batch_pings
        if monitor and sent % (batch_pings * 20) == 0:
            grew = (monitor.peak or 0) - (monitor.baseline or 0)
            sys.stdout.write(
                "\r  sent %d pings, iTerm2 RSS +%s   "
                % (sent, human_bytes(grew))
            )
            sys.stdout.flush()
    if sent >= max_pings:
        return ("max_pings", sent, time.time() - start)
    return ("timeout", sent, time.time() - start)


def main():
    parser = argparse.ArgumentParser(
        description="Verify the WebSocket ping-flood DoS fix in iTerm2's API server."
    )
    parser.add_argument(
        "--socket",
        help="Full path to the API Unix socket (overrides --suite).",
    )
    parser.add_argument(
        "--suite",
        help="iTerm2 -suite name whose socket to target (default: $IT2_APP_PATH "
        "or iTerm2). A dev build run by `make run` uses the repo dir name, e.g. "
        "iterm2-alt2.",
    )
    parser.add_argument("--cookie", help="API cookie (else obtained via AppleScript).")
    parser.add_argument("--key", help="API connection key (else via AppleScript).")
    parser.add_argument(
        "--app-name", default="ping-flood-dos-test", help="Name shown in the console."
    )
    parser.add_argument(
        "--pid", type=int, help="iTerm2 pid to monitor (else autodetected)."
    )
    parser.add_argument("--no-monitor", action="store_true", help="Skip RSS sampling.")
    parser.add_argument(
        "--max-pings",
        type=int,
        default=5_000_000,
        help="Safety cap on pings before declaring the server did not disconnect us.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="Overall wall-clock budget in seconds.",
    )
    parser.add_argument(
        "--batch-pings",
        type=int,
        default=10000,
        help="How many pings to send per socket write.",
    )
    args = parser.parse_args()

    socket_path = args.socket or default_socket_path(args.suite)
    print("Using API socket: %s" % socket_path)
    if not os.path.exists(socket_path):
        raise SystemExit(
            "API socket not found at %s. Is iTerm2 running with the Python API "
            "enabled? Pass --suite <name> or --socket <path> to override."
            % socket_path
        )

    if args.cookie and args.key:
        cookie, key = args.cookie, args.key
    else:
        cookie, key = obtain_cookie_and_key(args.app_name)

    monitor = None
    if not args.no_monitor:
        pid = args.pid or autodetect_pid()
        if pid:
            try:
                monitor = RSSMonitor(pid)
                monitor.start()
                print("Monitoring iTerm2 pid %d, baseline RSS %s"
                      % (pid, human_bytes(monitor.baseline)))
            except Exception as e:
                sys.stderr.write("Could not monitor pid %s: %s\n" % (pid, e))
                monitor = None
        else:
            sys.stderr.write(
                "No single iTerm2 pid to monitor; continuing without RSS "
                "sampling (pass --pid or --no-monitor to silence this).\n"
            )

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(socket_path)
    print("Connected to %s; performing handshake..." % socket_path)
    handshake(sock, cookie, key)
    print("Handshake OK (101). Flooding pings without reading pongs...")

    deadline = time.time() + args.timeout
    verdict, sent, elapsed = flood(
        sock, monitor, args.max_pings, deadline, args.batch_pings
    )
    if monitor:
        monitor.stop()

    print()  # end the progress line
    growth = None
    if monitor:
        growth = (monitor.peak or 0) - (monitor.baseline or 0)
        print("iTerm2 RSS grew by %s during the flood (peak %s)."
              % (human_bytes(growth), human_bytes(monitor.peak)))
    print("Sent ~%d pings in %.1fs." % (sent, elapsed))

    if verdict == "closed":
        print("\nRESULT: FIXED - the server disconnected the flooding client "
              "after a bounded amount of data.")
        return 0
    else:
        why = {
            "max_pings": "reached the ping cap",
            "timeout": "ran out of time",
        }.get(verdict, verdict)
        print("\nRESULT: VULNERABLE (or inconclusive) - the server never "
              "disconnected us (%s)." % why)
        if growth is not None and growth > 50 * 1024 * 1024:
            print("iTerm2's memory climbed by %s, consistent with the "
                  "unbounded-pong-buffering bug." % human_bytes(growth))
        return 1


if __name__ == "__main__":
    sys.exit(main())
