#!/usr/bin/env python3
"""
stored_state_digest.py

Structural digest of stored-state files, with every value removed, so that
a sanitized corpus can be compared with the original: if the digests are
identical, sanitizing changed no key name (except the expected renames,
below), no type, no number width, no array or dictionary size, no string
or data length, no keyed-archive class name and no SQLite row identity.

Shares no code with stored_state_sanitize.py. Uses plistlib, json and
sqlite3 from the standard library.

What a digest records, per file:
  * plists (binary or XML) and JSON: one line per node with its key path
    and type: dict (key count), array (length), string (length in UTF-16
    code units), data (length, plus the nested digest when the data is
    itself a plist or JSON), integer, real, bool, date, UID; XML plists
    with raw control characters (Apple writes U+0008 raw) are parsed after
    mapping each control character to a private-use character;
  * binary plists additionally: the marker byte of every object in offset
    table order (type and width: a 4-byte real or a 2-byte integer stays
    one), the trailer's offset and reference sizes and object count;
  * NSKeyedArchiver archives additionally: the class table, every
    $classname and $classes chain in $objects order;
  * SQLite: page size, encoding, user_version, application_id, journal
    mode, the schema SQL, and for each table every row in rowid order with
    the rowid and each cell's type and length (and nested digest for
    blobs);
  * text files: length; symbolic links: target length.

Key renames: a dictionary KEY that holds a private value (for example
"Hostname to Shell" keys are user@host) is renamed by the sanitizer. Pass
--key-map VALUES.json and the digest of the ORIGINAL applies the values
file's substitutions to dictionary keys only, never to values, so the
comparison still checks every other key exactly.

USAGE
  stored_state_digest.py compare ORIG_ROOT SAN_ROOT RELPATH... [--key-map V]
  stored_state_digest.py show FILE

`compare` exits 0 when every listed file's digest matches, 1 otherwise.
"""

import argparse
import json
import os
import plistlib
import re
import shutil
import sqlite3
import struct
import sys
import tempfile

CONTROL = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def load_xml_plist(raw):
    def sub(m):
        return chr(0xE000 + m.group(0)[0]).encode("utf-8")
    return plistlib.loads(CONTROL.sub(sub, raw), fmt=plistlib.FMT_XML)


def utf16_len(s):
    return len(s.encode("utf-16-le")) // 2


class Digester:
    def __init__(self, key_map=None):
        self.key_map = key_map or []
        self.renamed = 0

    def key(self, k):
        if not isinstance(k, str):
            return repr(k)
        out = k
        for v, p in self.key_map:
            out = out.replace(v, p)
        if out != k:
            self.renamed += 1
        return out

    def node(self, obj, path, out):
        p = "/".join(path)
        if isinstance(obj, dict):
            out.append(f"{p} dict {len(obj)}")
            for k in sorted(obj, key=lambda x: self.key(x)):
                self.node(obj[k], path + [self.key(k)], out)
        elif isinstance(obj, list):
            out.append(f"{p} array {len(obj)}")
            for i, v in enumerate(obj):
                self.node(v, path + [str(i)], out)
        elif isinstance(obj, bool):
            out.append(f"{p} bool")
        elif isinstance(obj, int):
            out.append(f"{p} integer")
        elif isinstance(obj, float):
            out.append(f"{p} real")
        elif isinstance(obj, str):
            out.append(f"{p} string {utf16_len(obj)}")
        elif isinstance(obj, (bytes, bytearray)):
            out.append(f"{p} data {len(obj)}")
            self.blob(bytes(obj), path + ["<data>"], out)
        elif isinstance(obj, plistlib.UID):
            out.append(f"{p} uid {obj.data}")
        elif obj is None:
            out.append(f"{p} null")
        else:
            out.append(f"{p} {type(obj).__name__}")

    def blob(self, raw, path, out):
        """Nested content: plist or JSON gets a full digest, else nothing."""
        if raw[:8] == b"bplist00":
            self.bplist(raw, path, out)
        elif raw.lstrip()[:5] == b"<?xml" and b"<plist" in raw[:400]:
            self.node(load_xml_plist(raw), path, out)
        elif raw[:1] in (b"{", b"["):
            try:
                obj = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                return
            self.node(obj, path + ["<json>"], out)

    def bplist(self, raw, path, out):
        obj = plistlib.loads(raw, fmt=plistlib.FMT_BINARY)
        self.node(obj, path, out)
        off_size, ref_size, n, top, table = struct.unpack(">6xBBQQQ", raw[-32:])
        p = "/".join(path)
        out.append(f"{p} <trailer> offsets={off_size} refs={ref_size} "
                   f"objects={n} top={top} length={len(raw)}")
        markers = []
        for i in range(n):
            o = int.from_bytes(raw[table + i * off_size:table + (i + 1) * off_size],
                               "big")
            m = raw[o]
            if m >> 4 in (0x4, 0x5, 0x6, 0x7, 0xA, 0xB, 0xC, 0xD) and m & 0xF == 0xF:
                markers.append(f"{m:02x}{raw[o + 1]:02x}")
            else:
                markers.append(f"{m:02x}")
        out.append(f"{p} <markers> {' '.join(markers)}")
        if isinstance(obj, dict) and obj.get("$archiver") == "NSKeyedArchiver":
            for i, o in enumerate(obj.get("$objects", [])):
                if isinstance(o, dict) and "$classname" in o:
                    chain = ">".join(o.get("$classes", []))
                    out.append(f"{p} <class> {i} {o['$classname']} {chain}")

    def file(self, path):
        out = []
        if os.path.islink(path):
            return [f"symlink {len(os.readlink(path))}"]
        with open(path, "rb") as f:
            head = f.read(16)
        if head == b"SQLite format 3\x00":
            return self.sqlite(path)
        with open(path, "rb") as f:
            raw = f.read()
        if raw[:8] == b"bplist00":
            self.bplist(raw, ["<root>"], out)
        elif raw.lstrip()[:5] == b"<?xml" and b"<plist" in raw[:400]:
            self.node(load_xml_plist(raw), ["<root>"], out)
            out.append(f"<xml> length={len(raw)}")
        elif raw[:1] in (b"{", b"["):
            self.node(json.loads(raw.decode("utf-8")), ["<root>"], out)
            out.append(f"<json> length={len(raw)}")
        else:
            out.append(f"bytes {len(raw)}")
        return out

    def sqlite(self, path):
        out = []
        tmp = tempfile.mkdtemp(prefix="ssd-")
        try:
            work = os.path.join(tmp, "db")
            shutil.copyfile(path, work)
            if os.path.exists(path + "-wal"):
                shutil.copyfile(path + "-wal", work + "-wal")
            con = sqlite3.connect(work)
            # Page 1 may live only in the WAL; checkpoint the copy first.
            con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            with open(work, "rb") as f:
                h = f.read(100)
            # File header fields that are format, not writer bookkeeping:
            # write and read versions (2 = WAL), reserved bytes per page,
            # schema format.
            out.append(f"header write={h[18]} read={h[19]} reserved={h[20]} "
                       f"schema_format={int.from_bytes(h[44:48], 'big')}")
            for pragma in ("page_size", "encoding", "user_version",
                           "application_id", "journal_mode", "auto_vacuum"):
                out.append(f"pragma {pragma}={con.execute(f'PRAGMA {pragma}').fetchone()[0]}")
            tables = []
            for typ, name, sql in con.execute(
                    "select type, name, sql from sqlite_master order by type, name"):
                out.append(f"schema {typ} {name} {sql}")
                if typ == "table":
                    tables.append(name)
            for t in tables:
                rows = con.execute(f'select rowid, * from "{t}" order by rowid').fetchall()
                cols = [r[1] for r in con.execute(f'PRAGMA table_info("{t}")')]
                out.append(f"table {t} rows={len(rows)}")
                for row in rows:
                    cells = []
                    for col, v in zip(cols, row[1:]):
                        if v is None:
                            cells.append(f"{col}:null")
                        elif isinstance(v, int):
                            cells.append(f"{col}:integer")
                        elif isinstance(v, float):
                            cells.append(f"{col}:real")
                        elif isinstance(v, str):
                            cells.append(f"{col}:text{len(v.encode('utf-8'))}")
                        else:
                            cells.append(f"{col}:blob{len(v)}")
                    out.append(f"row {t} {row[0]} {' '.join(cells)}")
                    for col, v in zip(cols, row[1:]):
                        if isinstance(v, bytes):
                            self.blob(v, [t, str(row[0]), col], out)
            con.close()
        finally:
            shutil.rmtree(tmp)
        return out


def load_key_map(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    pairs = [(e["value"], e["placeholder"]) for e in spec["literals"]
             if e.get("placeholder")]
    pairs.sort(key=lambda vp: -len(vp[0]))
    return pairs


def main(argv):
    ap = argparse.ArgumentParser(description="Structural digest of stored state.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compare")
    c.add_argument("orig_root")
    c.add_argument("san_root")
    c.add_argument("relpaths", nargs="+")
    c.add_argument("--key-map")
    c.add_argument("--json", action="store_true")
    s = sub.add_parser("show")
    s.add_argument("file")
    args = ap.parse_args(argv)
    if args.cmd == "show":
        for line in Digester().file(args.file):
            print(line)
        return 0
    key_map = load_key_map(args.key_map) if args.key_map else []
    failures = 0
    results = {}
    for rel in args.relpaths:
        d_orig = Digester(key_map)
        a = d_orig.file(os.path.join(args.orig_root, rel))
        b = Digester().file(os.path.join(args.san_root, rel))
        same = a == b
        classes = sum(1 for line in b if " <class> " in line)
        results[rel] = {"identical": same, "lines": len(b),
                        "renamed_keys": d_orig.renamed, "archive_classes": classes}
        if not same:
            failures += 1
            for i, (x, y) in enumerate(zip(a, b)):
                if x != y:
                    results[rel]["first_difference_line"] = i
                    break
            else:
                results[rel]["first_difference_line"] = min(len(a), len(b))
        if not args.json:
            print(f"{'OK  ' if same else 'DIFF'} lines={len(b):6d} "
                  f"renamed_keys={d_orig.renamed:3d} classes={classes:4d} {rel}")
    if args.json:
        json.dump(results, sys.stdout, indent=1, sort_keys=True)
        print()
    print(f"{len(args.relpaths) - failures} identical, {failures} different",
          file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
