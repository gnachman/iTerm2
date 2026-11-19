"""Tests for tools/sanitize_iterm2_plist.py, the user-defaults sanitizer.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_sanitize_iterm2_plist.py'

The first group pins behavior the tool already had; the second covers what
the stored-state corpus work added: XML plists with raw control characters
(written by a custom settings folder and by Export All Settings), the AppKit
open panel bookmark, the save panel's "Initial Directory", and the custom
settings folder dictionaries keyed by folder path. Every input is built in
the test; nothing here reads the corpus.
"""

import importlib.util
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TOOL = os.path.join(REPO, "tools", "sanitize_iterm2_plist.py")

spec = importlib.util.spec_from_file_location("sanitize_iterm2_plist", TOOL)
sanitizer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sanitizer)

REDACT = sanitizer.REDACT


def xml_profile(**extra):
    """profile() without the trigger whose parameter holds U+0001, which
    plistlib cannot write as XML."""
    p = profile(**extra)
    del p["Triggers"][1]
    return p


def profile(**extra):
    p = {"Name": "Fake Profile", "Guid": "11111111-2222-3333-4444-555555555555",
         "Command": "ssh someone@somewhere", "Working Directory": "/Users/someone/x",
         "Columns": 80, "Transparency": 0.25, "Use Bold Font": True,
         "Triggers": [{"action": "HighlightTrigger", "regex": "secret.*",
                       "parameter": "{#ff0000,#00ff00}"},
                      {"action": "iTermSetProfileBooleanTrigger", "regex": "x",
                       "parameter": "Blink\x011"},
                      {"action": "BounceTrigger", "regex": "y",
                       "parameter": "private text"}]}
    p.update(extra)
    return p


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="sanitize-test-")

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, data, fmt=plistlib.FMT_BINARY, name="com.googlecode.iterm2.plist"):
        path = os.path.join(self.dir, name)
        with open(path, "wb") as f:
            plistlib.dump(data, f, fmt=fmt)
        return path

    def run_tool(self, *args):
        return subprocess.run([sys.executable, "-I", TOOL, *args],
                              capture_output=True, text=True, timeout=60)


class ExistingBehaviorTests(Base):
    def test_redacts_content_and_keeps_structure_values(self):
        path = self.write({"New Bookmarks": [profile()],
                           "Window Arrangements": {"A": [{"Tabs": [{"Root": {
                               "Session": {"Contents": b"screen", "Columns": 80,
                                           "Working Directory": "/Users/someone"}}}]}]}})
        r = self.run_tool(path, "--in-place")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(path, "rb") as f:
            raw = f.read()
        self.assertTrue(raw.startswith(b"bplist00"))
        out = plistlib.loads(raw)
        p = out["New Bookmarks"][0]
        self.assertEqual(p["Command"], REDACT)
        self.assertEqual(p["Working Directory"], REDACT)
        self.assertEqual(p["Name"], "Fake Profile")
        self.assertEqual(p["Columns"], 80)
        self.assertEqual(p["Transparency"], 0.25)
        self.assertIs(p["Use Bold Font"], True)
        self.assertEqual(p["Triggers"][0]["parameter"], "{#ff0000,#00ff00}")
        self.assertEqual(p["Triggers"][0]["regex"], REDACT)
        self.assertEqual(p["Triggers"][1]["parameter"], "Blink\x011")
        self.assertEqual(p["Triggers"][2]["parameter"], REDACT)
        session = out["Window Arrangements"]["A"][0]["Tabs"][0]["Root"]["Session"]
        self.assertNotIn("Contents", session)
        self.assertEqual(session["Columns"], 80)

    def test_aggressive_redacts_labels(self):
        path = self.write({"New Bookmarks": [profile()]})
        r = self.run_tool(path, "--in-place", "--aggressive")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(path, "rb") as f:
            out = plistlib.load(f)
        self.assertEqual(out["New Bookmarks"][0]["Name"], REDACT)

    def test_dry_run_writes_nothing(self):
        path = self.write({"New Bookmarks": [profile()]})
        with open(path, "rb") as f:
            before = f.read()
        r = self.run_tool(path, "--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("total redactions", r.stdout)
        with open(path, "rb") as f:
            self.assertEqual(f.read(), before)
        self.assertEqual(sorted(os.listdir(self.dir)), ["com.googlecode.iterm2.plist"])

    def test_private_sibling_is_sanitized(self):
        path = self.write({"New Bookmarks": [profile()]})
        self.write({"NoSyncSearchHistory2": ["find me"]},
                   name="com.googlecode.iterm2.private.plist")
        r = self.run_tool(path)
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(os.path.join(self.dir, "com.googlecode.iterm2.private.sanitized.plist"),
                  "rb") as f:
            self.assertEqual(plistlib.load(f)["NoSyncSearchHistory2"], [REDACT])

    def test_xml_without_control_characters_stays_xml(self):
        path = self.write({"New Bookmarks": [xml_profile()]}, fmt=plistlib.FMT_XML)
        r = self.run_tool(path, "--in-place")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(path, "rb") as f:
            raw = f.read()
        self.assertTrue(raw.lstrip().startswith(b"<?xml"))
        self.assertEqual(plistlib.loads(raw)["New Bookmarks"][0]["Command"], REDACT)


class ControlCharacterTests(Base):
    """Apple writes U+0008 raw into XML plists; Python cannot parse that."""

    def xml_with_backspace(self):
        good = plistlib.dumps({"New Bookmarks": [xml_profile(**{"HotKey Characters": "@@"})]},
                              fmt=plistlib.FMT_XML)
        # Replace the stand-in with the raw control character, as Apple writes it.
        return good.replace(b"<string>@@</string>", b"<string>\x08</string>")

    def test_plistlib_alone_rejects_it(self):
        with self.assertRaises(Exception):
            plistlib.loads(self.xml_with_backspace())

    def test_sanitizes_and_writes_the_control_character_back_raw(self):
        path = os.path.join(self.dir, "com.googlecode.iterm2.plist")
        with open(path, "wb") as f:
            f.write(self.xml_with_backspace())
        r = self.run_tool(path, "--in-place")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(path, "rb") as f:
            raw = f.read()
        self.assertIn(b"<string>\x08</string>", raw)
        self.assertNotIn("".encode("utf-8"), raw)
        data, fmt, mapped = sanitizer.load_plist(path)
        self.assertTrue(mapped)
        self.assertEqual(fmt, plistlib.FMT_XML)
        p = data["New Bookmarks"][0]
        self.assertEqual(p["Command"], REDACT)
        self.assertEqual(p["HotKey Characters"], "")
        if shutil.which("plutil"):
            lint = subprocess.run(["plutil", "-lint", path], capture_output=True,
                                  timeout=30)
            self.assertEqual(lint.returncode, 0, lint.stdout)

    def test_dry_run_reports_instead_of_failing(self):
        path = os.path.join(self.dir, "com.googlecode.iterm2.plist")
        with open(path, "wb") as f:
            f.write(self.xml_with_backspace())
        r = self.run_tool(path, "--dry-run")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("format: xml", r.stdout)

    def test_refuses_ambiguous_input(self):
        raw = self.xml_with_backspace().replace(
            b"<string>Fake Profile</string>",
            b"<string>" + "".encode("utf-8") + b"</string>")
        with self.assertRaises(ValueError):
            sanitizer.map_control_chars(raw)

    def test_round_trip_is_identity_for_every_control_character(self):
        raw = bytes(range(0x20)) + b"abc"
        self.assertEqual(sanitizer.unmap_control_chars(
            sanitizer.map_control_chars(raw)), raw)


class NewKeyTests(Base):
    def sanitized(self, data):
        path = self.write(data)
        r = self.run_tool(path, "--in-place")
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(path, "rb") as f:
            return plistlib.load(f)

    def test_open_panel_bookmark_is_emptied(self):
        out = self.sanitized({"NSOSPLastRootDirectory": b"book\x00Users\x00someone"})
        self.assertEqual(out["NSOSPLastRootDirectory"], b"")

    def test_save_panel_initial_directory_with_space(self):
        out = self.sanitized({"NoSyncSavePanelSavedSettings_SaveProfile": {
            "Initial Directory": "/Users/someone/Desktop", "Other": 3}})
        d = out["NoSyncSavePanelSavedSettings_SaveProfile"]
        self.assertEqual(d["Initial Directory"], REDACT)
        self.assertEqual(d["Other"], 3)

    def test_folder_keyed_dictionaries_are_removed(self):
        keys = ["NoSyncRemoteDataFileSyncBaselineSignatures",
                "NoSyncSyncDataFilesWithCustomFolder",
                "NoSyncRemoteDataFileSyncDiscardPending",
                "NoSyncRemoteDataFileSyncLastPushedLocal"]
        data = {k: {"/Users/someone/prefs": "x"} for k in keys}
        data["PrefsCustomFolder"] = "/Users/someone/prefs"
        out = self.sanitized(data)
        for k in keys:
            self.assertNotIn(k, out)
        self.assertEqual(out["PrefsCustomFolder"], REDACT)

    def test_audit_comment_lists_the_new_keys(self):
        doc = sanitizer.__doc__
        for k in ["NSOSPLastRootDirectory", "Initial Directory",
                  "NoSyncRemoteDataFileSyncBaselineSignatures",
                  "NoSyncSyncDataFilesWithCustomFolder",
                  "NoSyncRemoteDataFileSyncDiscardPending",
                  "NoSyncRemoteDataFileSyncLastPushedLocal"]:
            self.assertIn(k, doc)


if __name__ == "__main__":
    unittest.main()
