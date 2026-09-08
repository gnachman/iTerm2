#!/usr/bin/env python3
"""Compare sequential upload chunks over the real framer and an SSH PTY.

Usage: python3 tests/benchmark_conductor_upload.py ai
Creates and removes an isolated remote temporary directory. Uses synthetic data;
never reads the clipboard or touches existing sessions. Excludes SSH setup time.
"""
import base64
import hashlib
import os
from pathlib import Path
import re
import select
import shlex
import subprocess
import sys
import time


def b64(value):
    if isinstance(value, str):
        value = value.encode()
    return base64.b64encode(value).decode() or "="


def main():
    host = sys.argv[1]
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host]
    root = subprocess.check_output(ssh + ["mktemp -d /tmp/iterm2-upload-bench.XXXXXXXX"], text=True).strip()
    if not re.fullmatch(r"/tmp/iterm2-upload-bench\.[A-Za-z0-9]+", root):
        raise RuntimeError("Unexpected temporary directory")
    proc = None
    try:
        source = (Path(__file__).resolve().parents[1] / "OtherResources/framer.py").read_text()
        source = source.replace("#{SUB}", "DEPTH=0")
        subprocess.run(ssh + [f"cat > {shlex.quote(root + '/framer.py')}"], input=source, text=True, check=True)
        proc = subprocess.Popen(ssh[:-1] + ["-tt", host, f"stty -echo; python3 -u {root}/framer.py"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def request(verb, *args):
            command = "\n".join(b64(arg) for arg in ["file", verb, *args])
            wire = "\n".join(command[i:i+128] + ("\\" if i+128 < len(command) else "") for i in range(0, len(command), 128)) + "\n\n"
            proc.stdin.write(wire.encode())
            proc.stdin.flush()
            response = b""
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if select.select([proc.stdout], [], [], max(0, deadline-time.monotonic()))[0]:
                    part = os.read(proc.stdout.fileno(), 65536)
                    if not part:
                        raise RuntimeError("SSH closed: " + proc.stderr.read().decode())
                    response += part
                    match = re.search(rb"\x1b\]134;:end \S+ (\d+) [rf]\x1b\\", response)
                    if match:
                        if match[1] != b"0":
                            raise RuntimeError(repr(response))
                        return
            raise TimeoutError(repr(response[-1000:]))

        request("stat", b64(root))
        data = os.urandom(490 * 1024)
        for size in (1024, 4096, 8192, 16384, 32768, 65536):
            path = f"{root}/upload-{size}"
            start = time.monotonic()
            request("create", b64(path), b64(b""))
            for offset in range(0, len(data), size):
                request("append", b64(path), b64(data[offset:offset+size]))
            request("mv", b64(path), b64(path + ".done"))
            elapsed = time.monotonic() - start
            digest = subprocess.check_output(ssh + [f"sha256sum {path}.done"], text=True).split()[0]
            if digest != hashlib.sha256(data).hexdigest():
                raise RuntimeError("Upload checksum mismatch")
            print(f"{size//1024:2} KiB chunks: {elapsed:.3f}s; {(len(data)+size-1)//size} appends; SHA-256 verified", flush=True)
    finally:
        if proc:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        subprocess.run(ssh + [f"rm -rf -- {shlex.quote(root)}"], check=True)


if __name__ == "__main__":
    main()
