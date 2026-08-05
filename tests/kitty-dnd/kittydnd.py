"""
Shared helpers for the Kitty drag-and-drop protocol (OSC 72) test clients.

See docs/kitty-dnd-design.md for the protocol. These helpers build and parse the
OSC 72 messages the terminal exchanges with a program running inside it.
"""

import base64
import hashlib
import hmac
import subprocess

OSC = "\x1b]"
ST = "\x1b\\"

# MIME lists / machine ids / error strings are plain text; file/image data is
# base64. See the design doc.
_HMAC_KEY = b"tty-dnd-protocol-machine-id"


def build(metadata, text_payload=None, data_payload=None):
    """Build one OSC 72 sequence.

    metadata: dict of key -> str. text_payload: a plain string (MIME lists etc).
    data_payload: bytes, base64-encoded on the wire. Pass at most one payload.
    """
    parts = []
    if "t" in metadata:
        parts.append("t=%s" % metadata["t"])
    for key in sorted(k for k in metadata if k != "t"):
        parts.append("%s=%s" % (key, metadata[key]))
    body = ":".join(parts)
    if data_payload is not None:
        body += ";" + base64.b64encode(data_payload).decode("ascii")
    elif text_payload is not None:
        body += ";" + text_payload
    return "%s72;%s%s" % (OSC, body, ST)


def parse(content):
    """Parse the content after '72;' into (metadata dict, raw_payload_or_None)."""
    if ";" in content:
        meta_s, payload = content.split(";", 1)
    else:
        meta_s, payload = content, None
    md = {}
    for token in meta_s.split(":"):
        if "=" in token:
            key, value = token.split("=", 1)
            md[key] = value
    return md, payload


class OSC72Reader:
    """Scans a byte stream and yields (metadata, raw_payload) for each OSC 72."""

    def __init__(self):
        self._buf = b""

    def feed(self, data):
        self._buf += data
        events = []
        while True:
            start = self._buf.find(b"\x1b]72;")
            if start < 0:
                # Keep a short tail in case a new introducer is split across reads.
                if len(self._buf) > 5:
                    self._buf = self._buf[-5:]
                break
            rest = self._buf[start + 5:]
            st = rest.find(b"\x1b\\")
            bel = rest.find(b"\x07")
            ends = [e for e in (st, bel) if e >= 0]
            if not ends:
                # Incomplete sequence; keep from the introducer for the next read.
                self._buf = self._buf[start:]
                break
            end = min(ends)
            content = rest[:end].decode("utf-8", "replace")
            term_len = 2 if end == st else 1
            self._buf = rest[end + term_len:]
            events.append(parse(content))
        return events


def _base_machine_id():
    """The platform machine identity: IOPlatformUUID on macOS, /etc/machine-id on
    Linux. The client is usually on a different host than the terminal (e.g. over
    ssh), so this must work on whatever OS the client runs on, not just macOS."""
    try:
        out = subprocess.check_output(
            ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
            stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            if "IOPlatformUUID" in line and '"' in line:
                return line.split('"')[-2]
    except Exception:
        pass
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            with open(path) as f:
                value = f.read().strip()
            if value:
                return value
        except OSError:
            pass
    return None


def machine_id():
    """Our hashed machine id ("1:<hex>"), or None if it can't be determined.

    The hash is HMAC-SHA256 of the platform machine id with the protocol key.
    Two hosts hash their own (different) base ids, so the terminal sees a
    mismatch and treats the drop as cross-machine; on the same host they match."""
    base = _base_machine_id()
    if base is None:
        return None
    digest = hmac.new(_HMAC_KEY, base.encode(), hashlib.sha256).hexdigest()
    return "1:" + digest
