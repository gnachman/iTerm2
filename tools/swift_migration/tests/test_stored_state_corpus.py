"""Tests for the stored-state corpus tools in tools/swift_migration:
stored_state_sanitize.py (same-length, in-place sanitizing),
stored_state_scan.py (independent raw-byte scan) and
stored_state_digest.py (structural digest).

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_stored_state*.py'

Every input is built here. The private values are "secretuser" and
"secrethost"; their placeholders are "vmuser0001" and "vmhost0001". A
binary plist with a 4-byte real and a 2-byte integer is assembled by hand,
because plistlib always writes 8-byte reals and minimal integers, and
keeping such widths is the point of patching in place.
"""

import collections
import contextlib
import io
import json
import os
import plistlib
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
sys.path.insert(0, TOOL_DIR)

import stored_state_digest as digest  # noqa: E402
import stored_state_sanitize as san  # noqa: E402
import stored_state_scan as scan  # noqa: E402

VALUES = {"literals": [
    {"kind": "vm-user", "value": "secretuser", "placeholder": "vmuser0001",
     "fragments": True},
    {"kind": "vm-host", "value": "secrethost", "placeholder": "vmhost0001",
     "fragments": True},
]}


def ascii_obj(s):
    b = s.encode("ascii")
    if len(b) < 15:
        return bytes([0x50 | len(b)]) + b
    return bytes([0x5F, 0x10, len(b)]) + b


def utf16_obj(s):
    b = s.encode("utf-16-be")
    n = len(b) // 2
    assert n < 15
    return bytes([0x60 | n]) + b


def build_bplist(objs, top=0):
    body = b"bplist00"
    offsets = []
    for o in objs:
        offsets.append(len(body))
        body += o
    table = len(body)
    size = 1 if table < 256 else 2
    body += b"".join(x.to_bytes(size, "big") for x in offsets)
    body += struct.pack(">6xBBQQQ", size, 1, len(objs), top, table)
    return body


def handmade_bplist():
    """{"n": int16 300, "f": float32 1.5, "s": "secretuser@secrethost",
    "u": "Ü secretuser" (UTF-16)}"""
    keys = ["n", "f", "s", "u"]
    objs = [bytes([0xD4]) + bytes([1, 2, 3, 4]) + bytes([5, 6, 7, 8])]
    objs += [ascii_obj(k) for k in keys]
    objs += [b"\x11" + (300).to_bytes(2, "big"),
             b"\x22" + struct.pack(">f", 1.5),
             ascii_obj("secretuser@secrethost"),
             utf16_obj("Ü secretuser")]
    return build_bplist(objs)


def cell(ch, attrs=b"\x07\x01\x02\x03\x04\x05\x06\x07\x08\x09"):
    return ord(ch).to_bytes(2, "little") + attrs


def screen(text):
    return b"".join(cell(c) for c in text)


def keyed_archive():
    objs = ["$null",
            {"NS.keys": [plistlib.UID(2)], "NS.objects": [plistlib.UID(3)],
             "$class": plistlib.UID(5)},
            "secretuser@secrethost.local",
            {"NS.data": screen("secretuser@secrethost ~ % ls"),
             "$class": plistlib.UID(4)},
            {"$classname": "NSMutableData",
             "$classes": ["NSMutableData", "NSData", "NSObject"]},
            {"$classname": "NSMutableDictionary",
             "$classes": ["NSMutableDictionary", "NSDictionary", "NSObject"]}]
    return plistlib.dumps({"$archiver": "NSKeyedArchiver", "$version": 100000,
                           "$top": {"root": plistlib.UID(1)}, "$objects": objs},
                          fmt=plistlib.FMT_BINARY)


def engine():
    lits = [san.Literal(e["kind"], e["value"], e["placeholder"])
            for e in VALUES["literals"]]
    lits.sort(key=lambda lit: -len(lit.value))
    return san.Engine(lits, sanitize=True)


class TempDirTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="stored-state-test-")
        self.values = os.path.join(self.dir, "values.json")
        with open(self.values, "w") as f:
            json.dump(VALUES, f)

    def tearDown(self):
        shutil.rmtree(self.dir)

    def path(self, *parts):
        p = os.path.join(self.dir, *parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        return p

    def scan_dir(self, root):
        needles, ph = scan.load_needles(self.values)
        sc = scan.Scanner(needles, ph)
        found = {}
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                full = os.path.join(dirpath, name)
                found.update(scan.scan_file(sc, full, os.path.relpath(full, root)))
        return found


class LiteralTests(unittest.TestCase):
    def test_placeholder_must_have_the_same_length(self):
        with self.assertRaises(ValueError):
            san.Literal("vm-user", "secretuser", "short")

    def test_literal_must_not_hold_xml_syntax(self):
        with self.assertRaises(ValueError):
            san.Literal("x", "a<b", "a-b")

    def test_placeholder_must_not_hold_a_value(self):
        d = tempfile.mkdtemp()
        try:
            p = os.path.join(d, "v.json")
            with open(p, "w") as f:
                json.dump({"literals": [
                    {"kind": "a", "value": "abc", "placeholder": "xyz"},
                    {"kind": "b", "value": "qqqqqq", "placeholder": "abcabc"}]}, f)
            with self.assertRaises(ValueError):
                san.load_values(p)
        finally:
            shutil.rmtree(d)


class BinaryPlistTests(unittest.TestCase):
    def test_patched_in_place_keeping_widths(self):
        raw = handmade_bplist()
        self.assertEqual(plistlib.loads(raw)["f"], 1.5)
        out = engine().patch_blob(raw, ["t"])
        self.assertEqual(len(out), len(raw))
        changed = [i for i in range(len(raw)) if raw[i] != out[i]]
        self.assertTrue(changed)
        # Only string payload bytes changed: markers, the 0x22 real, the
        # 0x11 integer, the offset table and the trailer are identical.
        self.assertEqual(out[-32:], raw[-32:])
        bp_in, bp_out = san.BPlist(raw), san.BPlist(out)
        for a, b in zip(bp_in.offsets, bp_out.offsets):
            self.assertEqual(raw[a], out[b])
        d = plistlib.loads(out)
        self.assertEqual(d["s"], "vmuser0001@vmhost0001")
        self.assertEqual(d["u"], "Ü vmuser0001")
        self.assertEqual(d["n"], 300)
        self.assertEqual(d["f"], 1.5)
        self.assertIn(b"\x22" + struct.pack(">f", 1.5), out)
        self.assertIn(b"\x11" + (300).to_bytes(2, "big"), out)

    def test_keyed_archive_keeps_class_table_and_patches_screen_cells(self):
        raw = keyed_archive()
        out = engine().patch_blob(raw, ["t"])
        self.assertEqual(len(out), len(raw))
        a, b = plistlib.loads(raw), plistlib.loads(out)
        classes = [o for o in a["$objects"] if isinstance(o, dict) and "$classname" in o]
        self.assertEqual(classes, [o for o in b["$objects"]
                                   if isinstance(o, dict) and "$classname" in o])
        self.assertEqual(b["$objects"][2], "vmuser0001@vmhost0001.local")
        cells = b["$objects"][3]["NS.data"]
        self.assertEqual(cells, screen("vmuser0001@vmhost0001 ~ % ls"))
        # Attributes of every cell are untouched.
        old = a["$objects"][3]["NS.data"]
        for i in range(0, len(old), 12):
            self.assertEqual(old[i + 2:i + 12], cells[i + 2:i + 12])


class XmlAndTextTests(unittest.TestCase):
    def test_xml_plist_with_control_character_and_nested_data(self):
        nested = handmade_bplist()
        xml = plistlib.dumps({"HotKey Characters": "@@", "Path": "/Users/secretuser/x",
                              "Blob": nested, "secretuser@secrethost": True},
                             fmt=plistlib.FMT_XML)
        xml = xml.replace(b"<string>@@</string>", b"<string>\x08</string>")
        e = engine()
        out = e.patch_blob(xml, ["t"])
        self.assertEqual(len(out), len(xml))
        self.assertIn(b"<string>\x08</string>", out)
        self.assertNotIn(b"secret", out)
        self.assertEqual(e.renamed_keys, 1)
        parsed = digest.load_xml_plist(out)
        self.assertEqual(parsed["Path"], "/Users/vmuser0001/x")
        self.assertEqual(plistlib.loads(parsed["Blob"])["s"], "vmuser0001@vmhost0001")
        # base64 line layout is unchanged.
        strip = lambda b: [len(line) for line in b.split(b"\n")]  # noqa: E731
        self.assertEqual(strip(xml), strip(out))

    def test_json_with_escaped_slashes(self):
        raw = b'{"a":"\\/Users\\/secretuser\\/x","secrethost":1}'
        out = engine().patch_blob(raw, ["t"])
        self.assertEqual(out, b'{"a":"\\/Users\\/vmuser0001\\/x","vmhost0001":1}')


class FileTests(TempDirTest):
    def make_sqlite(self, path):
        con = sqlite3.connect(path)
        con.execute("PRAGMA journal_mode=WAL")
        con.execute("PRAGMA wal_autocheckpoint=0")
        con.execute("create table Node (key text not null, identifier text not null, "
                    "parent integer not null, data blob)")
        con.execute("insert into Node values ('root', '', 0, ?)", (keyed_archive(),))
        con.execute("insert into Node values ('gone', 'secretuser', 1, x'00')")
        con.execute("insert into Node values ('child', 'secrethost', 1, ?)",
                    (screen("secretuser"),))
        con.commit()
        con.execute("delete from Node where key='gone'")
        con.commit()
        # Copy while the connection is open so the WAL is not checkpointed.
        snap = path + ".snap"
        shutil.copyfile(path, snap)
        shutil.copyfile(path + "-wal", snap + "-wal")
        con.close()
        os.replace(snap, path)
        os.replace(snap + "-wal", path + "-wal")

    def build_corpus(self):
        root = os.path.join(self.dir, "raw")
        with open(self.path("raw", "s", "prefs.plist"), "wb") as f:
            f.write(handmade_bplist())
        self.make_sqlite(self.path("raw", "s", "state.sqlite"))
        with open(self.path("raw", "s", "notes.txt"), "w") as f:
            f.write("ssh secretuser@secrethost\n")
        os.symlink("/Users/secretuser/app", self.path("raw", "s", "link"))
        return root

    def sanitize(self, root):
        out = os.path.join(self.dir, "out")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = san.main(["sanitize", "--values", self.values, root, out])
        self.assertEqual(rc, 0)
        return out, json.loads(buf.getvalue())

    def test_raw_corpus_is_found_by_the_scan(self):
        root = self.build_corpus()
        found = self.scan_dir(root)
        kinds = {k for (_label, k, _enc) in found}
        self.assertIn("vm-user", kinds)
        self.assertIn("vm-host", kinds)

    def test_sanitized_corpus_scans_clean_and_digests_match(self):
        root = self.build_corpus()
        out, results = self.sanitize(root)
        self.assertEqual(self.scan_dir(out), {})
        self.assertFalse(os.path.exists(os.path.join(out, "s", "state.sqlite-wal")))
        self.assertIn("merged into the database, not written",
                      results["s/state.sqlite-wal"]["notes"])
        self.assertEqual(os.readlink(os.path.join(out, "s", "link")),
                         "/Users/vmuser0001/app")
        km = digest.load_key_map(self.values)
        for rel in ["s/prefs.plist", "s/state.sqlite", "s/notes.txt", "s/link"]:
            a = digest.Digester(km).file(os.path.join(root, rel))
            b = digest.Digester().file(os.path.join(out, rel))
            self.assertEqual(a, b, rel)
        # The deleted row's value is gone from the file, not just the table.
        with open(os.path.join(out, "s", "state.sqlite"), "rb") as f:
            self.assertNotIn(b"secret", f.read())

    def test_audit_never_prints_values(self):
        root = self.build_corpus()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = san.main(["audit", "--values", self.values, root])
        self.assertEqual(rc, 0)
        text = buf.getvalue()
        self.assertNotIn("secret", text)
        report = json.loads(text)
        self.assertGreater(sum(report["s/state.sqlite"]["hits"]["vm-user"].values()), 0)

    def test_scan_cli_exit_status(self):
        root = self.build_corpus()
        r = subprocess.run([sys.executable, "-I", os.path.join(TOOL_DIR, "stored_state_scan.py"),
                            "--values", self.values, root],
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 1)
        self.assertNotIn("secret", r.stdout + r.stderr)
        out, _ = self.sanitize(root)
        r = subprocess.run([sys.executable, "-I", os.path.join(TOOL_DIR, "stored_state_scan.py"),
                            "--values", self.values, out],
                           capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout)


class ScannerTests(unittest.TestCase):
    def scanner(self):
        d = tempfile.mkdtemp()
        try:
            p = os.path.join(d, "v.json")
            with open(p, "w") as f:
                json.dump(VALUES, f)
            return scan.Scanner(*scan.load_needles(p))
        finally:
            shutil.rmtree(d)

    def found(self, data):
        f = collections.Counter()
        self.scanner().scan_bytes(data, 0, "x", f, 0, set())
        return {k for (_l, k, _e) in f}

    def test_self_test(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(scan.self_test(), 0)

    def test_wrapped_screen_line_is_found_by_fragments(self):
        data = screen("ab secre") + b"\x01" * 12 + screen("tuser ~")
        self.assertIn("fragment-of:vm-user", self.found(data))

    def test_utf16_email_is_detected(self):
        kinds = self.found("mail someone@private.org".encode("utf-16-le"))
        self.assertTrue(any(k.startswith("detector:email") for k in kinds))

    def test_every_other_byte_of_utf8_is_not_an_email(self):
        # At stride 2 this reads "kyvue0@opsv-otae00.oa".
        self.assertEqual(self.found(b"<key>vmuser0001@corpus-vm-hostname-0001.local"), set())

    def test_documentation_ip_and_placeholders_are_allowed(self):
        self.assertEqual(self.found(b"Last login: Thu Nov 19 21:03:07 from 203.0.113.10 "
                                    b"/Users/vmuser0001 a@b.example 127.0.0.1"), set())

    def test_real_ip_and_home_are_flagged(self):
        kinds = self.found(b"Last login: Thu Nov 19 21:03:07 from 192.168.1.20 /Users/bob")
        self.assertTrue(any(k.startswith("detector:ipv4") for k in kinds))
        self.assertTrue(any(k.startswith("detector:home-path") for k in kinds))
        self.assertTrue(any(k.startswith("detector:last-login-from") for k in kinds))


class DigestTests(TempDirTest):
    def digest_of(self, data, name="f.plist"):
        p = self.path(name)
        with open(p, "wb") as f:
            f.write(data)
        return digest.Digester().file(p)

    def test_detects_number_type_change(self):
        a = self.digest_of(plistlib.dumps({"x": 1}))
        b = self.digest_of(plistlib.dumps({"x": 1.0}))
        self.assertNotEqual(a, b)

    def test_detects_real_width_change(self):
        raw = handmade_bplist()
        widened = raw.replace(b"\x22" + struct.pack(">f", 1.5), b"\x23" + b"\x00" * 3 +
                              struct.pack(">f", 1.5)[:1])
        self.assertNotEqual(self.digest_of(raw), self.digest_of(widened))

    def test_detects_string_length_change(self):
        a = self.digest_of(plistlib.dumps({"x": "abc"}))
        b = self.digest_of(plistlib.dumps({"x": "abcd"}))
        self.assertNotEqual(a, b)

    def test_detects_class_name_change(self):
        raw = keyed_archive()
        b = raw.replace(b"NSMutableData", b"NSMutableDat_")
        self.assertNotEqual(self.digest_of(raw), self.digest_of(b))

    def test_ignores_values_of_the_same_shape(self):
        a = self.digest_of(plistlib.dumps({"x": "abc", "n": 1}))
        b = self.digest_of(plistlib.dumps({"x": "xyz", "n": 2}))
        self.assertEqual(a, b)

    def test_detects_rowid_change(self):
        def db(name, rowid):
            p = self.path(name)
            con = sqlite3.connect(p)
            con.execute("create table t (a text)")
            con.execute("insert into t (rowid, a) values (?, 'x')", (rowid,))
            con.commit()
            con.close()
            return digest.Digester().file(p)
        self.assertNotEqual(db("a.sqlite", 1), db("b.sqlite", 2))

    def test_xml_with_control_characters(self):
        xml = plistlib.dumps({"k": "@@"}, fmt=plistlib.FMT_XML).replace(b"@@", b"\x08")
        self.assertIn("<root>/k string 1", self.digest_of(xml))


if __name__ == "__main__":
    unittest.main()
