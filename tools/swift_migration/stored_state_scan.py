#!/usr/bin/env python3
"""
stored_state_scan.py

Independent check that a sanitized stored-state corpus holds no private
values. It deliberately shares no code with stored_state_sanitize.py and
knows nothing about plists, archives or SQLite: it reads every file as raw
bytes (in chunks, never a whole large file) and searches

  * every byte stride from 1 to 16 at every alignment, case-insensitively,
    which covers UTF-8, UTF-16 in both byte orders, the 12-byte
    screen_char_t cells of terminal contents, and any other fixed-width
    record that stores one character per cell;
  * inside every zlib or gzip stream found at any offset, every raw DEFLATE
    stream that inflates completely from any offset of a file (Core Data's
    Z_MODELCACHE is raw DEFLATE), and every base64 run of 32 or more
    characters (XML plist <data>, JSON), recursively.

What it looks for, given a values file (same format as the sanitizer's;
entries without a placeholder are included):

  * each value at every stride; for entries marked "fragments": true, also
    every substring of FRAGMENT_LEN characters at the strides in
    TEXT_STRIDES (a wrapped terminal line splits a host name across rows,
    and an app may truncate a title);
  * detector patterns that need no list: IPv4 addresses outside the
    loopback, unspecified and documentation ranges; MAC addresses; e-mail
    addresses outside example domains; /Users/<name> for names other than
    the placeholders and "Shared"; "Last login ... from"; and token-shaped
    strings (OpenAI, GitHub, Slack, AWS keys, PEM private keys).

It prints counts per file, kind and stride, never the values (a detector
hit is identified by the first 10 hex digits of the SHA-256 of the match).
Exit status is 1 if anything is found, 0 if not, 2 on error. Files listed
with --allow-fragment-file are lines of "<relpath>\t<fragment kind>"
that a person checked; none are needed for the committed corpus.

Also: `stored_state_scan.py --self-test` checks that it finds planted
values in each encoding.

Python 3 standard library only.
"""

import argparse
import base64
import binascii
import collections
import hashlib
import json
import os
import re
import sys
import zlib

MAX_STRIDE = 16
FRAGMENT_LEN = 5
CHUNK = 4 * 1024 * 1024
OVERLAP = 4096
MAX_NESTED = 64 * 1024 * 1024
MAX_DEPTH = 4
TEXT_STRIDES = (1, 2, 4, 12)
RAW_DEFLATE_WINDOW = 65536
# Detector patterns are short and generic, so they run only on the layouts
# text is actually stored in (UTF-8, UTF-16, screen_char_t); elsewhere every
# other character of a UTF-16 "user@host.local" forms a fake e-mail address.
DETECT_STRIDES = (1, 2, 12)

ALLOWED_IPV4 = re.compile(rb"^(?:127\.|0\.0\.0\.0$|255\.255\.255\.255$|"
                          rb"192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)")
ALLOWED_EMAIL_DOMAIN = re.compile(rb"(?i)(?:^|\.)(?:example(?:\.com|\.org|"
                                  rb"\.net)?|invalid|test|localhost)$")

DETECTORS = [
    ("ipv4", re.compile(rb"(?<![0-9.])(?:(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])"
                        rb"\.){3}(?:25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])"
                        rb"(?![0-9.])")),
    ("mac", re.compile(rb"(?<![0-9a-f:])[0-9a-f]{2}(?::[0-9a-f]{2}){5}"
                       rb"(?![0-9a-f:])")),
    ("email", re.compile(rb"[a-z0-9._%+-]{2,64}@([a-z0-9-]{2,63}"
                         rb"(?:\.[a-z0-9-]{1,63})*\.[a-z]{2,})")),
    ("home-path", re.compile(rb"/users/([a-z0-9._-]{1,64})")),
    ("last-login-from", re.compile(rb"last login: [^\n]{0,40} from "
                                   rb"([0-9a-f.:]+)")),
    ("token", re.compile(rb"(?:sk-[a-z0-9_-]{20,}|gh[pousr]_[a-z0-9]{30,}|"
                         rb"xox[abpr]-[a-z0-9-]{10,}|akia[0-9a-z]{16}|"
                         rb"-----begin [a-z ]*private key-----)")),
]
ALLOWED_HOME_NAMES = {b"shared"}


def load_needles(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    needles = []
    placeholders = set()
    for e in spec["literals"]:
        v = e["value"]
        if not v.isascii():
            raise ValueError("non-ASCII values need a UTF-16 aware scan; "
                             "add one before using such a value")
        needles.append((e["kind"], v.lower().encode("ascii")))
        if e.get("placeholder"):
            placeholders.add(e["placeholder"].lower().encode("ascii"))
        if e.get("fragments") and len(v) > FRAGMENT_LEN:
            seen = set()
            for i in range(len(v) - FRAGMENT_LEN + 1):
                frag = v[i:i + FRAGMENT_LEN].lower().encode("ascii")
                if frag not in seen:
                    seen.add(frag)
                    needles.append(("fragment-of:" + e["kind"], frag))
    return needles, placeholders


class Scanner:
    def __init__(self, needles, placeholders):
        self.needles = needles
        full = sorted({n for k, n in needles if not k.startswith("fragment-of:")},
                      key=len, reverse=True)
        alts = sorted({n for _, n in needles}, key=len, reverse=True)
        self.full_rx = re.compile(b"|".join(re.escape(a) for a in full))
        self.needle_rx = re.compile(b"|".join(re.escape(a) for a in alts))
        self.kind_of = collections.defaultdict(set)
        for k, n in needles:
            self.kind_of[n].add(k)
        self.placeholders = placeholders
        self.allowed_home = ALLOWED_HOME_NAMES | {
            p for p in placeholders if re.fullmatch(rb"[a-z0-9._-]+", p)}

    def scan_bytes(self, data, base, label, found, depth, seen):
        """Scan one buffer whose first byte is at absolute offset `base`."""
        low = data.lower()
        for stride in range(1, MAX_STRIDE + 1):
            for align in range(stride):
                start = (align - base) % stride
                view = low[start::stride]
                if len(view) < 3:
                    continue
                # Fragments only where text plausibly lives: one character per
                # 1, 2 or 4 bytes, or per 12-byte screen_char_t. At other
                # strides ordinary text forms 5-letter fragments by chance
                # ("iTermStatusBar" holds "irtua" at stride 3).
                rx = self.needle_rx if stride in TEXT_STRIDES else self.full_rx
                for m in rx.finditer(view):
                    off = base + start + m.start() * stride
                    key = (label, off, stride, m.group(0))
                    if key in seen:
                        continue
                    seen.add(key)
                    # A fragment inside a full value hit at the same place
                    # is the same finding; record only the longest.
                    for kind in self.kind_of[m.group(0)]:
                        found[(label, kind, f"stride{stride}")] += 1
                if stride in DETECT_STRIDES:
                    self.detect(view, low, start, base, stride, label, found,
                                seen)
        if depth < MAX_DEPTH:
            self.nested(data, label, found, depth, seen)

    def detect(self, view, low, start, base, stride, label, found, seen):
        for name, rx in DETECTORS:
            for m in rx.finditer(view):
                text = m.group(0)
                if stride > 1 and not _wide_text(low, start + m.start() * stride,
                                                 len(text), stride):
                    continue
                if name == "last-login-from" and (
                        ALLOWED_IPV4.match(m.group(1)) or
                        m.group(1) in self.placeholders):
                    continue
                if any(p in text for p in self.placeholders):
                    continue
                if name == "ipv4" and ALLOWED_IPV4.match(text):
                    continue
                if name == "email" and ALLOWED_EMAIL_DOMAIN.search(m.group(1)):
                    continue
                if name == "home-path" and m.group(1) in self.allowed_home:
                    continue
                if name == "ipv4" and stride == 1 and _looks_like_version(view, m):
                    continue
                key = (label, base + start + m.start() * stride, name)
                if key in seen:
                    continue
                seen.add(key)
                digest = hashlib.sha256(text).hexdigest()[:10]
                found[(label, f"detector:{name}:{digest}", f"stride{stride}")] += 1

    def nested(self, data, label, found, depth, seen):
        # zlib streams (78 01 / 78 5e / 78 9c / 78 da) and gzip members.
        for m in re.finditer(rb"\x1f\x8b\x08|\x78[\x01\x5e\x9c\xda]", data):
            i = m.start()
            wbits = 31 if data[i] == 0x1f else 15
            try:
                d = zlib.decompressobj(wbits)
                out = d.decompress(data[i:i + MAX_NESTED], MAX_NESTED)
            except zlib.error:
                continue
            if len(out) < 16:
                continue
            if len(out) >= MAX_NESTED:
                found[(label, "error:nested stream too large", "zlib")] += 1
                continue
            self.scan_bytes(out, 0, f"{label}@zlib{i}", found, depth + 1, seen)
        for m in re.finditer(rb"(?:[A-Za-z0-9+/]{4}[ \t\r\n]*){8,}"
                             rb"(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?", data):
            raw = re.sub(rb"\s+", b"", m.group(0))
            raw = raw[:len(raw) - len(raw) % 4]
            try:
                out = base64.b64decode(raw, validate=True)
            except (binascii.Error, ValueError):
                continue
            if len(out) < 16:
                continue
            self.scan_bytes(out, 0, f"{label}@b64{m.start()}", found,
                            depth + 1, seen)
        for m in re.finditer(rb"bvx[2n\-$]", data):
            found[(label, "error:LZFSE/LZVN stream not scanned", "bvx")] += 1
        if depth == 0:
            self.raw_deflate(data, label, found, seen)

    def raw_deflate(self, data, label, found, seen):
        """Raw DEFLATE has no header to search for (Core Data stores its
        model cache that way), so try to inflate at every offset and keep
        streams that end properly and yield at least 64 bytes. Random bytes
        sometimes do; scanning their output is harmless."""
        for i in range(len(data)):
            d = zlib.decompressobj(-15)
            try:
                out = d.decompress(data[i:i + RAW_DEFLATE_WINDOW], MAX_NESTED)
            except zlib.error:
                continue
            if d.eof and len(out) >= 64:
                self.scan_bytes(out, 0, f"{label}@deflate{i}", found,
                                MAX_DEPTH - 1, seen)


def _wide_text(buf, off, n, stride):
    """True if the n characters at off (one per `stride` bytes) are stored
    as 16-bit code units with a zero high byte, little- or big-endian: real
    UTF-16 or screen_char_t text rather than every other byte of UTF-8."""
    le = all(off + i * stride + 1 < len(buf) and buf[off + i * stride + 1] == 0
             for i in range(n))
    be = all(off + i * stride - 1 >= 0 and buf[off + i * stride - 1] == 0
             for i in range(n))
    return le or be


def _looks_like_version(view, m):
    """A dotted quad inside a longer dotted run (1.2.3.4.5) is a version."""
    before = view[max(0, m.start() - 1):m.start()]
    return before.isalpha()


def scan_file(scanner, path, label):
    found = collections.Counter()
    seen = set()
    if os.path.islink(path):
        target = os.readlink(path).encode("utf-8", "surrogateescape")
        scanner.scan_bytes(target, 0, label + "<symlink>", found, 0, seen)
        return found
    with open(path, "rb") as f:
        base = 0
        carry = b""
        while True:
            chunk = f.read(CHUNK)
            if not chunk:
                break
            buf = carry + chunk
            scanner.scan_bytes(buf, base - len(carry), label, found, 0, seen)
            carry = buf[-OVERLAP:]
            base += len(chunk)
    return found


def self_test():
    needles, ph = [("vm-user", b"secretuser")], {b"vmuser"}
    # load_needles makes fragments only for entries marked "fragments".
    needles += [("fragment-of:vm-user", b"secretuser"[i:i + FRAGMENT_LEN])
                for i in range(len(b"secretuser") - FRAGMENT_LEN + 1)]
    sc = Scanner(needles, ph)
    cases = {
        "utf8": b"xx secretuser yy",
        "utf16le": "secretuser".encode("utf-16-le"),
        "utf16be": "SecretUser".encode("utf-16-be"),
        "screen": b"".join(struct_cell(c) for c in "abc secretuser def"),
        "wrapped": b"".join(struct_cell(c) for c in "secre") + b"\x01" * 12 +
                   b"".join(struct_cell(c) for c in "tuser"),
        "zlib": zlib.compress(b"..secretuser.." * 4),
        "deflate": b"\xa5junk" + _raw_deflate(b"..secretuser.." * 8) + b"tail",
        "b64": b"<data>" + base64.b64encode(b"0123456789 secretuser 0123456789")
               + b"</data>",
        "ip": b"from 10.20.30.40 ok",
        "home": b"/Users/someone/x",
    }
    ok = True
    for name, data in cases.items():
        found = collections.Counter()
        sc.scan_bytes(data, 0, name, found, 0, set())
        if not found:
            print(f"self-test FAILED: nothing found in {name}")
            ok = False
    clean = collections.Counter()
    sc.scan_bytes(b"/Users/vmuser/x 127.0.0.1 10.14.6.2.1 a@b.example",
                  0, "clean", clean, 0, set())
    if clean:
        print(f"self-test FAILED: false positives {dict(clean)}")
        ok = False
    print("self-test", "passed" if ok else "FAILED")
    return 0 if ok else 1


def _raw_deflate(data):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


def struct_cell(ch):
    return ord(ch).to_bytes(2, "little") + b"\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00"


def main(argv):
    ap = argparse.ArgumentParser(description="Scan a corpus for private values.")
    ap.add_argument("--values")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--json", action="store_true", help="print JSON results")
    ap.add_argument("root", nargs="?")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.values or not args.root:
        ap.error("--values and root are required")
    needles, ph = load_needles(args.values)
    scanner = Scanner(needles, ph)
    total = collections.Counter()
    nfiles = 0
    for dirpath, dirnames, filenames in os.walk(args.root):
        dirnames.sort()
        names = sorted(filenames) + sorted(d for d in dirnames if os.path.islink(
            os.path.join(dirpath, d)))
        for name in names:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, args.root)
            nfiles += 1
            total.update(scan_file(scanner, full, rel))
    if args.json:
        out = collections.defaultdict(dict)
        for (label, kind, enc), n in sorted(total.items()):
            out[label][f"{kind} {enc}"] = n
        json.dump(out, sys.stdout, indent=1)
        print()
    else:
        for (label, kind, enc), n in sorted(total.items()):
            print(f"{n:6d}  {kind:40s} {enc:9s} {label}")
    print(f"scanned {nfiles} files; {sum(total.values())} findings",
          file=sys.stderr)
    return 1 if total else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
