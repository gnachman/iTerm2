#!/usr/bin/env python3
"""
stored_state_sanitize.py

Sanitize a stored-state corpus (files written by released iTerm2 versions)
so it can be committed as test input, WITHOUT changing the structure the
decoders see.

tools/sanitize_iterm2_plist.py is for sharing a user-defaults plist for
debugging: it replaces whole values with "[redacted]" and removes keys such
as session Contents, which changes key sets, string lengths and Data
lengths. A corpus that proves old formats still decode must keep all of
that. This tool instead replaces only known private literals (the account
name, host name, and so on, given in a values file that is NOT committed),
in place, with placeholders of the SAME length in the same encoding:

  * Binary plists (including NSKeyedArchiver archives) are patched in place:
    only the bytes of string objects change. Object order, integer and real
    widths, object references, the offset table and the trailer are
    byte-identical, so every NSNumber keeps its flavor.
  * XML plists are patched as text inside <key>/<string> content; <data> is
    base64-decoded, patched recursively, and re-encoded into the same
    character positions. Raw control characters (Apple writes U+0008 raw)
    are left as they are.
  * Data values are sniffed and patched recursively: nested binary or XML
    plists, JSON, and otherwise raw binary. Raw binary gets UTF-8, UTF-16
    (both byte orders) and screen_char_t substitution (a 2-byte little-endian
    code unit every 12 bytes, the layout in sources/ScreenChar/ScreenChar.h),
    which is how terminal contents are stored in restorable state.
  * SQLite databases are opened on a copy (which applies any WAL), every
    TEXT and BLOB cell is patched with the rules above and written back by
    rowid; then every table is copied into a fresh file with its rowids
    (not VACUUM, which renumbers rowids of tables without an INTEGER
    PRIMARY KEY after deletions, and the restorable-state Node table is one,
    with rowids in its parent column), so freed pages keep no old values.
    Page size, encoding, user_version, application_id and journal mode are
    carried over; stored_state_digest.py compares them and every rowid.
    The -wal and -shm files are not written.
  * JSON and text files get literal substitution (JSON also with the "\\/"
    escaped form). Symbolic links get their target patched.

Same length was chosen everywhere, not only where a decoder is known to
care: screen_char_t lines and bplist strings are patched in place and must
not move, and keeping it uniform means no file changes size.

The values file is JSON:
  {"literals": [{"kind": "vm-user", "value": "...", "placeholder": "..."},
                ...]}
Each placeholder must be ASCII-only when the value is, the same length in
characters (UTF-16 code units for non-ASCII values) and in UTF-8 bytes, and
must not contain any value. Literals must not contain & < > " or '.

USAGE
  stored_state_sanitize.py audit   --values V.json DIR [--terminal-dump OUT]
  stored_state_sanitize.py sanitize --values V.json SRC_DIR DST_DIR
      [--include RELPATH_REGEX ...]

`audit` reports, per file, the format, size, and counts of literal hits and
detector hits (IPv4, MAC, e-mail, UUID, home paths, user@host, token-shaped
strings, "Last login") by normalized key path. It never prints values,
except that --terminal-dump writes the decoded screen_char_t text to a
file for a person to read (keep that file out of the repository).

Python 3 standard library only.
"""

import argparse
import base64
import collections
import json
import os
import re
import shutil
import sqlite3
import struct
import sys
import tempfile

SCREEN_CHAR_SIZE = 12

DETECTORS = [
    ("ipv4", re.compile(r"(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}"
                        r"(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])")),
    ("mac", re.compile(r"(?i)(?<![0-9a-f:])[0-9a-f]{2}(?::[0-9a-f]{2}){5}"
                       r"(?![0-9a-f:])")),
    ("email", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*"
                         r"\.[A-Za-z]{2,}")),
    ("user@host", re.compile(r"(?<![\w.@-])[A-Za-z_][\w.-]*@[A-Za-z][\w-]*"
                             r"(?![\w@])")),
    ("uuid", re.compile(r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
                        r"[0-9a-f]{4}-[0-9a-f]{12}\b")),
    ("home-path", re.compile(r"/Users/[^/\s\"'<>:]+")),
    ("token", re.compile(r"(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}"
                         r"|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}"
                         r"|-----BEGIN [A-Z ]*PRIVATE KEY-----)")),
    ("last-login", re.compile(r"Last login")),
]

INT_RE = re.compile(r"\[\d+\]")


def normalize_path(path):
    return INT_RE.sub("[*]", "/".join(path))


class Literal:
    def __init__(self, kind, value, placeholder):
        if any(c in value for c in "&<>\"'"):
            raise ValueError(f"literal of kind {kind} contains XML syntax")
        if len(value) != len(placeholder):
            raise ValueError(f"placeholder for {kind} differs in length")
        if len(value.encode("utf-8")) != len(placeholder.encode("utf-8")) and \
                not placeholder.isascii():
            raise ValueError(f"placeholder for {kind} is not ASCII")
        if len(value.encode("utf-16-le")) != len(placeholder.encode("utf-16-le")):
            raise ValueError(f"placeholder for {kind} differs in UTF-16 length")
        self.kind = kind
        self.value = value
        self.placeholder = placeholder

    def byte_pairs(self):
        """(original, replacement) byte strings of equal length."""
        pairs = []
        v8, p8 = self.value.encode("utf-8"), self.placeholder.encode("utf-8")
        if len(v8) == len(p8):
            pairs.append((v8, p8))
        for codec in ("utf-16-le", "utf-16-be"):
            pairs.append((self.value.encode(codec), self.placeholder.encode(codec)))
        return pairs


def load_values(path, include_scan_only=False):
    """Entries without a placeholder are scan-only: values that must not
    occur at all. With include_scan_only they are counted (replaced by
    themselves), which is what `audit` wants; `sanitize` ignores them and
    stored_state_scan.py fails if they occur."""
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    lits = []
    for e in spec["literals"]:
        if e.get("placeholder") is not None:
            lits.append(Literal(e["kind"], e["value"], e["placeholder"]))
        elif include_scan_only:
            lits.append(Literal(e["kind"], e["value"], e["value"]))
    for a in lits:
        for b in lits:
            if b.placeholder != b.value and a.value in b.placeholder:
                raise ValueError(f"placeholder for {b.kind} contains a value")
    # Longest first so that "x.local" style values win over their prefixes.
    lits.sort(key=lambda l: -len(l.value))
    return lits


class Engine:
    """Walks nested formats; in sanitize mode patches, in audit mode counts."""

    def __init__(self, literals, sanitize, terminal_dump=None):
        self.literals = literals
        self.sanitize = sanitize
        self.terminal_dump = terminal_dump
        self.hits = collections.Counter()      # (kind, normalized path) -> n
        self.formats = collections.Counter()   # nested format -> n
        self.notes = []
        self.renamed_keys = 0

    def norm(self, path, suffix=""):
        """Normalized key path with private values masked, for reports."""
        out = normalize_path(path) + suffix
        for lit in self.literals:
            out = out.replace(lit.value, f"<{lit.kind}>")
        return out

    # ---- strings -------------------------------------------------------
    def patch_str(self, s, path, is_key=False):
        if not self.sanitize:
            self.detect(s, path)
        out = s
        for lit in self.literals:
            n = out.count(lit.value)
            if n:
                self.hits[(lit.kind, self.norm(path))] += n
                out = out.replace(lit.value, lit.placeholder)
        if is_key and out != s:
            self.renamed_keys += 1
        return out

    def detect(self, s, path):
        for name, rx in DETECTORS:
            n = len(rx.findall(s))
            if n:
                self.hits[("detector:" + name, self.norm(path))] += n

    # ---- raw bytes -----------------------------------------------------
    def patch_raw(self, data, path):
        """Unknown binary: byte-level, UTF-16 and screen_char_t patching."""
        buf = bytearray(data)
        if not self.sanitize:
            self.audit_raw(bytes(buf), path)
        for lit in self.literals:
            for orig, repl in lit.byte_pairs():
                n = buf.count(orig)
                if n:
                    self.hits[(lit.kind, self.norm(path, "<bytes>"))] += n
                    buf = bytearray(bytes(buf).replace(orig, repl))
            n = patch_strided(buf, lit.value, lit.placeholder, SCREEN_CHAR_SIZE)
            if n:
                self.hits[(lit.kind, self.norm(path, "<screen_char_t>"))] += n
        return bytes(buf)

    def audit_raw(self, data, path):
        text = data.decode("latin-1")
        self.detect(text, path + ["<bytes>"])
        if len(data) >= SCREEN_CHAR_SIZE * 4:
            screen = decode_screen_chars(data)
            if screen is not None:
                self.formats["screen_char_t array"] += 1
                self.detect(screen, path + ["<screen_char_t>"])
                if self.terminal_dump is not None:
                    self.terminal_dump.write(
                        "=== " + "/".join(path) + "\n" + screen + "\n")

    # ---- dispatch ------------------------------------------------------
    def patch_blob(self, data, path):
        kind = sniff(data)
        self.formats[kind] += 1
        if kind == "binary plist":
            return self.patch_bplist(data, path)
        if kind == "xml plist":
            return self.patch_xml_plist(data, path)
        if kind == "json":
            return self.patch_json(data, path)
        if kind == "empty":
            return data
        return self.patch_raw(data, path)

    # ---- JSON ----------------------------------------------------------
    def patch_json(self, data, path):
        text = data.decode("utf-8")
        if not self.sanitize:
            try:
                walk_json(json.loads(text), path, self.detect)
            except ValueError:
                self.detect(text, path)
        out = text
        for lit in self.literals:
            for v, p in ((lit.value, lit.placeholder),
                         (lit.value.replace("/", "\\/"),
                          lit.placeholder.replace("/", "\\/"))):
                n = out.count(v)
                if n:
                    self.hits[(lit.kind, self.norm(path, "<json>"))] += n
                    out = out.replace(v, p)
        res = out.encode("utf-8")
        assert len(res) == len(data)
        return res

    # ---- XML plist -----------------------------------------------------
    def patch_xml_plist(self, data, path):
        text = data.decode("utf-8")
        out = []
        pos = 0
        stack = []   # entries: ["dict", pending_key] or ["array", index]
        tag_rx = re.compile(r"<(/?)([A-Za-z]+)([^>]*?)(/?)>")
        pending_text_tag = None
        key_buf = None

        def cur_path():
            p = list(path)
            for frame in stack:
                if frame[0] == "dict":
                    p.append(frame[1] if frame[1] is not None else "?")
                else:
                    p.append(f"[{frame[1]}]")
            return p

        def value_done():
            if stack:
                if stack[-1][0] == "array":
                    stack[-1][1] += 1
                else:
                    stack[-1][1] = None

        for m in tag_rx.finditer(text):
            between = text[pos:m.start()]
            closing, name, _attrs, selfclose = m.groups()
            if pending_text_tag and closing and name == pending_text_tag:
                if name == "key":
                    key_buf = between
                    kp = cur_path()
                    if stack and stack[-1][0] == "dict":
                        kp[-1] = between
                    out.append(self.patch_str(between, kp, True))
                elif name == "string":
                    out.append(self.patch_str(between, cur_path()))
                elif name == "data":
                    out.append(self.patch_b64(between, cur_path()))
                else:
                    out.append(between)
                pending_text_tag = None
            else:
                out.append(between)
            out.append(m.group(0))
            pos = m.end()
            if name in ("plist",) or m.group(0).startswith("<?") or \
                    m.group(0).startswith("<!"):
                continue
            if closing:
                if name in ("dict", "array"):
                    stack.pop()
                    value_done()
                elif name == "key":
                    stack[-1][1] = key_buf
                elif name in ("string", "data", "integer", "real", "date"):
                    value_done()
                continue
            if selfclose:
                value_done()
                continue
            if name == "dict":
                stack.append(["dict", None])
            elif name == "array":
                stack.append(["array", 0])
            elif name in ("key", "string", "data", "integer", "real", "date"):
                pending_text_tag = name
            elif name in ("true", "false"):
                pass
        out.append(text[pos:])
        res = "".join(out).encode("utf-8")
        assert len(res) == len(data), "XML plist changed length"
        return res

    def patch_b64(self, text, path):
        compact = "".join(text.split())
        if not compact:
            return text
        raw = base64.b64decode(compact)
        new = self.patch_blob(raw, path)
        assert len(new) == len(raw)
        if new == raw:
            return text
        enc = base64.b64encode(new).decode("ascii")
        assert len(enc) == len(compact)
        it = iter(enc)
        return "".join(c if c.isspace() else next(it) for c in text)

    # ---- binary plist --------------------------------------------------
    def patch_bplist(self, data, path):
        bp = BPlist(data)
        buf = bytearray(data)
        archive = bp.keyed_archive_info()
        done = set()

        def visit(ref, p, depth):
            if depth > 200:
                return
            obj = bp.objects[ref]
            t = obj[0]
            if t in ("ascii", "utf16", "utf8"):
                if ref in done:
                    return
                done.add(ref)
                _, off, nbytes, codec = obj
                s = bytes(buf[off:off + nbytes]).decode(codec)
                is_key = p and p[-1] == "<key>"
                new = self.patch_str(s, p[:-1] if is_key else p, is_key)
                if new != s:
                    enc = new.encode(codec)
                    assert len(enc) == nbytes
                    buf[off:off + nbytes] = enc
            elif t == "data":
                if ref in done:
                    return
                done.add(ref)
                _, off, nbytes = obj
                old = bytes(buf[off:off + nbytes])
                new = self.patch_blob(old, p)
                assert len(new) == nbytes, "nested blob changed length"
                buf[off:off + nbytes] = new
            elif t in ("array", "set"):
                if (ref, "c") in done:
                    return
                done.add((ref, "c"))
                for i, r in enumerate(obj[1]):
                    visit(r, p + [f"[{i}]"], depth + 1)
            elif t == "dict":
                if (ref, "c") in done:
                    return
                done.add((ref, "c"))
                for kr, vr in zip(obj[1], obj[2]):
                    kname = bp.string_value(kr)
                    visit(kr, p + [str(kname), "<key>"], depth + 1)
                    if archive and kname == "$objects":
                        for i, r in enumerate(bp.objects[vr][1]):
                            visit(r, p + ["$objects", archive.get(i, "?")],
                                  depth + 1)
                        done.add((vr, "c"))
                    else:
                        visit(vr, p + [str(kname)], depth + 1)
            elif t == "uid" and archive is not None:
                pass  # $objects is visited once, in order, above.

        visit(bp.top, list(path), 0)
        res = bytes(buf)
        assert len(res) == len(data)
        return res


def walk_json(obj, path, fn):
    if isinstance(obj, dict):
        for k, v in obj.items():
            fn(str(k), path + [str(k), "<key>"])
            walk_json(v, path + [str(k)], fn)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk_json(v, path + [f"[{i}]"], fn)
    elif isinstance(obj, str):
        fn(obj, path)


def patch_strided(buf, value, placeholder, stride):
    """Replace value stored as one LE 16-bit code unit every `stride` bytes."""
    units = value.encode("utf-16-le")
    repl = placeholder.encode("utf-16-le")
    n_units = len(units) // 2
    first = units[0:2]
    count = 0
    start = 0
    span = (n_units - 1) * stride + 2
    while True:
        i = buf.find(first, start)
        if i < 0 or i + span > len(buf):
            break
        if all(buf[i + k * stride:i + k * stride + 2] == units[2 * k:2 * k + 2]
               for k in range(1, n_units)):
            for k in range(n_units):
                buf[i + k * stride:i + k * stride + 2] = repl[2 * k:2 * k + 2]
            count += 1
            start = i + span
        else:
            start = i + 1
    return count


def decode_screen_chars(data):
    """Heuristic: text of a screen_char_t array, or None if it is not one."""
    usable = len(data) - len(data) % SCREEN_CHAR_SIZE
    n = usable // SCREEN_CHAR_SIZE
    if n < 4:
        return None
    printable = 0
    chars = []
    for i in range(n):
        code = data[i * SCREEN_CHAR_SIZE] | (data[i * SCREEN_CHAR_SIZE + 1] << 8)
        if code == 0:
            chars.append(" ")
        elif 32 <= code < 0xD800 and code != 0x7F:
            printable += 1
            chars.append(chr(code))
        else:
            chars.append("�")
    if printable < max(4, n // 20):
        return None
    text = "".join(chars)
    if text.count("�") > n // 4:
        return None
    return text


def sniff(data):
    if not data:
        return "empty"
    if data[:8] == b"bplist00":
        return "binary plist"
    head = data[:200].lstrip()
    if head.startswith(b"<?xml") and b"<plist" in data[:400]:
        return "xml plist"
    if head[:1] in (b"{", b"[") :
        try:
            json.loads(data.decode("utf-8"))
            return "json"
        except (UnicodeDecodeError, ValueError):
            pass
    if data[:16] == b"SQLite format 3\x00":
        return "sqlite"
    if data[:2] == b"\x1f\x8b":
        return "gzip"
    return "raw"


class BPlist:
    """Minimal binary plist reader that records string and data offsets."""

    def __init__(self, data):
        self.data = data
        if len(data) < 40:
            raise ValueError("binary plist too short")
        (self.offset_size, self.ref_size, self.num_objects, self.top,
         self.table_offset) = struct.unpack(">6xBBQQQ", data[-32:])
        self.offsets = [self._uint(self.table_offset + i * self.offset_size,
                                   self.offset_size)
                        for i in range(self.num_objects)]
        self.objects = [self._parse(o) for o in self.offsets]

    def _uint(self, off, size):
        return int.from_bytes(self.data[off:off + size], "big")

    def _count(self, off, low):
        if low != 0xF:
            return low, off + 1
        marker = self.data[off + 1]
        size = 1 << (marker & 0xF)
        return self._uint(off + 2, size), off + 2 + size

    def _refs(self, off, n):
        return [self._uint(off + i * self.ref_size, self.ref_size)
                for i in range(n)]

    def _parse(self, off):
        marker = self.data[off]
        hi, lo = marker >> 4, marker & 0xF
        if hi == 0x0:
            return ("scalar",)
        if hi in (0x1, 0x2):
            return ("number", 1 << lo)
        if hi == 0x3:
            return ("date",)
        if hi == 0x4:
            n, start = self._count(off, lo)
            return ("data", start, n)
        if hi == 0x5:
            n, start = self._count(off, lo)
            return ("ascii", start, n, "ascii")
        if hi == 0x6:
            n, start = self._count(off, lo)
            return ("utf16", start, 2 * n, "utf-16-be")
        if hi == 0x7:
            n, start = self._count(off, lo)
            return ("utf8", start, n, "utf-8")
        if hi == 0x8:
            return ("uid", self._uint(off + 1, lo + 1))
        if hi in (0xA, 0xB, 0xC):
            n, start = self._count(off, lo)
            return ("array" if hi == 0xA else "set", self._refs(start, n))
        if hi == 0xD:
            n, start = self._count(off, lo)
            return ("dict", self._refs(start, n),
                    self._refs(start + n * self.ref_size, n))
        raise ValueError(f"unknown binary plist marker 0x{marker:02x}")

    def string_value(self, ref):
        obj = self.objects[ref]
        if obj[0] in ("ascii", "utf16", "utf8"):
            return self.data[obj[1]:obj[1] + obj[2]].decode(obj[3])
        return f"<{obj[0]}>"

    def lookup(self, dict_ref, key):
        obj = self.objects[dict_ref]
        if obj[0] != "dict":
            return None
        for kr, vr in zip(obj[1], obj[2]):
            if self.string_value(kr) == key:
                return vr
        return None

    def keyed_archive_info(self):
        """For an NSKeyedArchiver archive, map $objects index to a label."""
        if self.lookup(self.top, "$archiver") is None:
            return None
        objs_ref = self.lookup(self.top, "$objects")
        if objs_ref is None or self.objects[objs_ref][0] != "array":
            return None
        refs = self.objects[objs_ref][1]
        labels = {}
        # Label each object by the archive key that points at it.
        for i, r in enumerate(refs):
            obj = self.objects[r]
            if obj[0] != "dict":
                continue
            for kr, vr in zip(obj[1], obj[2]):
                k = self.string_value(kr)
                v = self.objects[vr]
                targets = []
                if v[0] == "uid":
                    targets = [v[1]]
                elif v[0] == "array":
                    targets = [self.objects[x][1] for x in v[1]
                               if self.objects[x][0] == "uid"]
                for t in targets:
                    labels.setdefault(t, k)
        return {i: f"[{labels.get(i, i)}]" for i in range(len(refs))}


# ---- files ------------------------------------------------------------

def patch_sqlite_file(engine, src, dst, path):
    """Copy src (plus -wal) into a temp dir, patch every cell, rebuild, and
    write the result to dst. Returns a list of notes."""
    notes = []
    tmp = tempfile.mkdtemp(prefix="sss-")
    try:
        work = os.path.join(tmp, "db.sqlite")
        shutil.copyfile(src, work)
        if os.path.exists(src + "-wal") and os.path.getsize(src + "-wal"):
            shutil.copyfile(src + "-wal", work + "-wal")
            notes.append("WAL applied")
        con = sqlite3.connect(work)
        con.execute("PRAGMA secure_delete=ON")
        tables = [r[0] for r in con.execute(
            "select name from sqlite_master where type='table'")]
        for t in tables:
            cols = [r[1] for r in con.execute(f'PRAGMA table_info("{t}")')]
            cur = con.execute(f'select rowid, * from "{t}"')
            for row in cur.fetchall():
                rowid = row[0]
                for col, val in zip(cols, row[1:]):
                    cpath = path + [t, col]
                    if isinstance(val, str):
                        new = engine.patch_str(val, cpath)
                    elif isinstance(val, bytes):
                        new = engine.patch_blob(val, cpath)
                    else:
                        continue
                    if engine.sanitize and new != val:
                        con.execute(f'update "{t}" set "{col}"=? where rowid=?',
                                    (new, rowid))
        con.commit()
        if engine.sanitize:
            fresh = os.path.join(tmp, "fresh.sqlite")
            rebuild_sqlite(con, fresh)
            con.close()
            for ext in ("-wal", "-shm"):
                if os.path.exists(fresh + ext):
                    if os.path.getsize(fresh + ext) and ext == "-wal":
                        raise RuntimeError("WAL not checkpointed")
                    os.remove(fresh + ext)
            shutil.copyfile(fresh, dst)
            notes.append("rebuilt with rowids kept")
        else:
            con.close()
    finally:
        shutil.rmtree(tmp)
    return notes


def rebuild_sqlite(src, path):
    """Copy every table of src into a new database at path, keeping rowids.

    This replaces VACUUM, which renumbers the rowids of a table without an
    INTEGER PRIMARY KEY when rows have been deleted; restorable state's Node
    table is such a table and its parent column holds rowids. A fresh file
    also holds no freed pages, so no old value survives in free space.
    """
    def pragma(name):
        return src.execute(f"PRAGMA {name}").fetchone()[0]

    page_size, auto_vacuum = pragma("page_size"), pragma("auto_vacuum")
    encoding, journal = pragma("encoding"), pragma("journal_mode")
    user_version, app_id = pragma("user_version"), pragma("application_id")
    dst = sqlite3.connect(path)
    dst.execute(f"PRAGMA page_size={int(page_size)}")
    dst.execute(f"PRAGMA auto_vacuum={int(auto_vacuum)}")
    dst.execute(f"PRAGMA encoding='{encoding}'")
    objects = src.execute("select type, name, sql from sqlite_master "
                          "where sql is not null order by rowid").fetchall()
    internal = [n for t, n, _ in objects if t == "table" and n.startswith("sqlite_")
                and n != "sqlite_sequence"]
    if internal:
        raise RuntimeError(f"cannot rebuild internal tables {internal}")
    tables = [(n, sql) for t, n, sql in objects
              if t == "table" and not n.startswith("sqlite_")]
    for _name, sql in tables:
        dst.execute(sql)
    for name, sql in tables:
        cols = [r[1] for r in src.execute(f'PRAGMA table_info("{name}")')]
        collist = ", ".join(f'"{c}"' for c in cols)
        if "WITHOUT ROWID" in sql.upper():
            rows = src.execute(f'select {collist} from "{name}"')
            marks = ", ".join("?" * len(cols))
            dst.executemany(f'insert into "{name}" ({collist}) values ({marks})', rows)
        else:
            rows = src.execute(f'select rowid, {collist} from "{name}"')
            marks = ", ".join("?" * (len(cols) + 1))
            dst.executemany(f'insert into "{name}" (rowid, {collist}) '
                            f'values ({marks})', rows)
    if any(n == "sqlite_sequence" for _t, n, _s in objects):
        dst.execute("delete from sqlite_sequence")
        dst.executemany("insert into sqlite_sequence (name, seq) values (?, ?)",
                        src.execute("select name, seq from sqlite_sequence"))
    for t, _n, sql in objects:
        if t in ("index", "trigger", "view"):
            dst.execute(sql)
    dst.execute(f"PRAGMA user_version={int(user_version)}")
    dst.execute(f"PRAGMA application_id={int(app_id)}")
    dst.commit()
    dst.execute(f"PRAGMA journal_mode={journal}")
    dst.close()


def process_file(engine, src, dst, rel):
    """Process one file. Returns (format, notes)."""
    path = [rel]
    if os.path.islink(src):
        target = os.readlink(src)
        new = engine.patch_str(target, path + ["<symlink>"])
        if engine.sanitize:
            os.symlink(new, dst)
        return "symlink", []
    with open(src, "rb") as f:
        head = f.read(16)
    if head == b"SQLite format 3\x00":
        return "sqlite", patch_sqlite_file(engine, src, dst, path)
    with open(src, "rb") as f:
        data = f.read()
    kind = sniff(data)
    if kind == "raw":
        try:
            text = data.decode("utf-8")
            kind = "text"
        except UnicodeDecodeError:
            pass
    if kind == "text":
        if not engine.sanitize:
            engine.detect(text, path)
        new_text = engine.patch_str(text, path)
        new = new_text.encode("utf-8")
    elif kind == "gzip":
        raise RuntimeError(f"{rel}: gzip containers are not handled")
    else:
        engine.formats[kind] -= 1  # counted again by patch_blob
        new = engine.patch_blob(data, path)
    assert len(new) == len(data)
    if engine.sanitize:
        with open(dst, "wb") as f:
            f.write(new)
    return kind, []


def strip_rel(path, rel):
    """A reported key path without the file's own path in front."""
    for prefix in (rel + "/", rel):
        if path.startswith(prefix):
            return path[len(prefix):] or "<file>"
    return path


def iter_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames + [d for d in dirnames
                                        if os.path.islink(os.path.join(dirpath, d))]):
            full = os.path.join(dirpath, name)
            yield os.path.relpath(full, root), full


def cmd_audit(args):
    lits = load_values(args.values, include_scan_only=True)
    dump = open(args.terminal_dump, "w", encoding="utf-8") if args.terminal_dump else None
    report = {}
    for rel, full in iter_files(args.dir):
        if args.include and not any(re.search(p, rel) for p in args.include):
            continue
        engine = Engine(lits, sanitize=False, terminal_dump=dump)
        try:
            kind, _ = process_file(engine, full, None, rel)
            err = None
        except Exception as e:  # noqa: BLE001 - reported per file
            kind, err = "error", f"{type(e).__name__}: {e}"
        size = os.lstat(full).st_size
        hits = {}
        for (k, p), n in engine.hits.items():
            hits.setdefault(k, collections.Counter())[strip_rel(p, rel)] += n
        report[rel] = {"format": kind, "size": size, "error": err,
                       "nested": dict(engine.formats),
                       "renamed_keys": engine.renamed_keys,
                       "hits": {k: dict(v) for k, v in hits.items()}}
    if dump:
        dump.close()
    json.dump(report, sys.stdout, indent=1, sort_keys=True)
    print()
    return 0


def cmd_sanitize(args):
    lits = load_values(args.values)
    if os.path.exists(args.dst) and os.listdir(args.dst):
        print(f"{args.dst} is not empty", file=sys.stderr)
        return 2
    results = {}
    for rel, full in iter_files(args.src):
        if args.include and not any(re.search(p, rel) for p in args.include):
            continue
        sidecar = re.match(r"(.*)-(wal|shm)$", full)
        if sidecar and os.path.exists(sidecar.group(1)):
            # The WAL is applied to the database copy and the index is
            # rebuilt by SQLite; byte-patching either would break the WAL's
            # checksums, so neither is written.
            results[rel] = {"format": "sqlite " + sidecar.group(2),
                            "notes": ["merged into the database, not written"]}
            continue
        dst = os.path.join(args.dst, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        engine = Engine(lits, sanitize=True)
        kind, notes = process_file(engine, full, dst, rel)
        replaced = collections.Counter()
        for (k, _p), n in engine.hits.items():
            replaced[k] += n
        results[rel] = {"format": kind, "notes": notes,
                        "renamed_keys": engine.renamed_keys,
                        "replaced": dict(replaced),
                        "replaced_paths": sorted({strip_rel(p, rel)
                                                  for (_k, p) in engine.hits})}
    json.dump(results, sys.stdout, indent=1, sort_keys=True)
    print()
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("audit")
    a.add_argument("--values", required=True)
    a.add_argument("--terminal-dump")
    a.add_argument("--include", action="append")
    a.add_argument("dir")
    s = sub.add_parser("sanitize")
    s.add_argument("--values", required=True)
    s.add_argument("--include", action="append")
    s.add_argument("src")
    s.add_argument("dst")
    args = ap.parse_args(argv)
    return cmd_audit(args) if args.cmd == "audit" else cmd_sanitize(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
