#!/usr/bin/env python3
"""An ssh ProxyCommand that slows the server-to-client direction to a fixed rate, to make a
slow link out of localhost. Used by the flow control live test in SSHIntegrationLiveHarness.

Usage: ssh -o ProxyCommand='python3 tests/throttle_proxy.py %h %p 20480' localhost
"""
import os
import socket
import sys
import threading
import time


def main():
    host, port, rate = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
    conn = socket.create_connection((host, port))

    def upstream():
        while True:
            data = os.read(0, 65536)
            if not data:
                conn.shutdown(socket.SHUT_WR)
                return
            conn.sendall(data)

    threading.Thread(target=upstream, daemon=True).start()
    # Downstream: send in small pieces, sleeping so the average stays at `rate` bytes/second.
    started = time.monotonic()
    sent = 0
    chunk = max(1, int(rate / 50))
    while True:
        data = conn.recv(chunk)
        if not data:
            return
        os.write(1, data)
        sent += len(data)
        ahead = sent / rate - (time.monotonic() - started)
        if ahead > 0:
            time.sleep(ahead)


if __name__ == "__main__":
    main()
