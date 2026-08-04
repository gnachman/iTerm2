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


def machine_id():
    """Our hashed machine id, matching iTerm2's derivation, or None."""
    try:
        out = subprocess.check_output(
            ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"]).decode()
    except Exception:
        return None
    for line in out.splitlines():
        if "IOPlatformUUID" in line and '"' in line:
            uuid = line.split('"')[-2]
            digest = hmac.new(_HMAC_KEY, uuid.encode(), hashlib.sha256).hexdigest()
            return "1:" + digest
    return None
