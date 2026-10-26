#!/usr/bin/env python3
"""Exercises framer.py's `file` command, which backs iTerm2's remote file browser, file
panel, drag-and-drop transfers and path completion. Every subcommand (ls fetch stat suggest
rm ln mv mkdir create append utime chmod-u zip search) is covered on success and on its
error paths: missing paths, permission denied, symlinks, non-UTF-8 names, and directories
where files are expected and vice versa.

Commands go through framer.handle() in-process, with arguments as mainloop passes them
(paths base64-encoded as Conductor.swift sends them), and replies are read back with the
harness's port of iTerm2's parser. Work happens in a fresh temporary directory per test
(under $FRAMER_TEST_TMPDIR if set).

Error statuses: file_error() maps EPERM and EACCES to 1, ENOENT to 2, ENOTDIR to 3, ELOOP to 4 and
any other OSError to 100. iTerm2 treats every nonzero status as failure.

Run: python3 tests/framer_file_test.py
"""
import asyncio
import base64
import contextlib
import errno
import json
import os
import stat
import sys
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import framer_harness as H  # noqa: E402

# 2001-01-01, the reference date of NSDate. remotefile() reports times relative to it.
NSDATE_EPOCH = 978307200
ENOENT, ENOTDIR, ELOOP, OTHER = 2, 3, 4, 100

is_root = os.geteuid() == 0


@contextlib.contextmanager
def env(**values):
    saved = {k: os.environ.get(k) for k in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def make_non_utf8_file(test, content):
    """Creates <tmp>/caf\\xe9, or skips where the filesystem only allows UTF-8 names."""
    raw = os.fsencode(test.tmp) + b"/caf\xe9"
    try:
        with open(raw, "wb") as f:
            f.write(content)
    except OSError as e:
        if e.errno == errno.EILSEQ:
            test.skipTest("this filesystem does not allow non-UTF-8 names")
        raise
    return raw


class FileTestCase(H.FramerTestCase):
    def path(self, *parts):
        return os.path.join(self.tmp, *parts)

    def write(self, name, content=b""):
        p = self.path(name)
        with open(p, "wb") as f:
            f.write(content)
        return p

    def file(self, *args):
        """Runs `file <args>` synchronously and returns the reply."""
        result = []

        async def body():
            result.append(await self.h.command("file", *args))
        self.run_async(body)
        self.assertNoParseErrors()
        return result[0]

    def ok(self, *args):
        reply = self.file(*args)
        self.assertIsNotNone(reply, "no reply to %r" % (args,))
        self.assertEqual(reply.status, 0, reply)
        return reply

    def ok_json(self, *args):
        return json.loads("".join(self.ok(*args).lines))

    def status(self, *args):
        reply = self.file(*args)
        self.assertIsNotNone(reply, "no reply to %r" % (args,))
        return reply.status


class DispatchTests(FileTestCase):
    def test_too_few_arguments_fail(self):
        self.assertEqual(self.status("ls"), OTHER)

    def test_unknown_subcommand_fails(self):
        self.assertEqual(self.status("frobnicate", H.b64(self.tmp)), OTHER)

    # The handler raises IndexError for the missing sort argument. Whatever it queued is
    # lost, so handle() must send a failure reply or iTerm2 waits forever.
    def test_malformed_arguments_still_get_a_reply(self):
        self.assertEqual(self.status("ls", H.b64(self.tmp)), 1)

    def test_tilde_expands_to_home(self):
        self.write("in-home.txt", b"x")
        with env(HOME=self.tmp):
            obj = self.ok_json("stat", H.b64("~/in-home.txt"))
        self.assertEqual(obj["absolutePath"], self.path("in-home.txt"))


class LsTests(FileTestCase):
    def test_lists_files_folders_and_symlinks_by_name(self):
        self.write("b.txt", b"12345")
        os.mkdir(self.path("a-dir"))
        os.symlink("b.txt", self.path("c-link"))
        os.mkfifo(self.path("d-fifo"))  # neither file, folder nor symlink: left out
        entries = self.ok_json("ls", H.b64(self.tmp), "n")
        self.assertEqual([e["absolutePath"] for e in entries],
                         [self.path("a-dir"), self.path("b.txt"), self.path("c-link")])
        kinds = [e["kind"] for e in entries]
        self.assertEqual(kinds[0], {"folder": {}})
        self.assertEqual(kinds[1], {"file": {"_0": {"size": 5}}})
        self.assertEqual(kinds[2], {"symlink": {"_0": "b.txt"}})
        st = os.lstat(self.path("b.txt"))
        self.assertEqual(entries[1]["mtime"], int(st.st_mtime) - NSDATE_EPOCH)
        self.assertEqual(entries[1]["ctime"], int(st.st_ctime) - NSDATE_EPOCH)
        self.assertEqual(entries[1]["permissions"], {"r": True, "w": True, "x": False})
        self.assertEqual(entries[1]["parentPermissions"], {"r": True, "w": True, "x": True})

    def test_sorts_by_date(self):
        for name, when in (("old", 1000000000), ("new", 1600000000), ("mid", 1300000000)):
            os.utime(self.write(name), (when, when))
        entries = self.ok_json("ls", H.b64(self.tmp), "d")
        self.assertEqual([os.path.basename(e["absolutePath"]) for e in entries],
                         ["old", "mid", "new"])

    def test_empty_directory(self):
        reply = self.ok("ls", H.b64(self.tmp), "n")
        self.assertEqual(reply.lines, ["[", "]"])

    def test_each_entry_is_its_own_line(self):
        self.write("one")
        self.write("two")
        lines = self.ok("ls", H.b64(self.tmp), "n").lines
        self.assertEqual(lines[0], "[")
        self.assertEqual(lines[2], ",")
        self.assertEqual(lines[-1], "]")
        self.assertEqual(len(lines), 5)

    def test_missing_directory(self):
        self.assertEqual(self.status("ls", H.b64(self.path("nope")), "n"), ENOENT)

    def test_a_file_is_not_a_directory(self):
        self.assertEqual(self.status("ls", H.b64(self.write("f")), "n"), ENOTDIR)

    def test_symlink_loop(self):
        os.symlink("loop", self.path("loop"))
        self.assertEqual(self.status("ls", H.b64(self.path("loop")), "n"), ELOOP)

    def test_symlink_to_a_directory_lists_its_target(self):
        os.mkdir(self.path("real"))
        self.write(os.path.join("real", "inside"))
        os.symlink("real", self.path("alias"))
        entries = self.ok_json("ls", H.b64(self.path("alias")), "n")
        self.assertEqual([e["absolutePath"] for e in entries], [self.path("alias", "inside")])

    @unittest.skipIf(is_root, "root ignores permissions")
    def test_unreadable_directory_fails(self):
        os.mkdir(self.path("locked"), 0)
        self.assertNotEqual(self.status("ls", H.b64(self.path("locked")), "n"), 0)

    @unittest.skipIf(is_root, "root ignores permissions")
    def test_permission_denied_reports_status_1(self):
        os.mkdir(self.path("locked"), 0)
        self.assertEqual(self.status("ls", H.b64(self.path("locked")), "n"), 1)

    def test_non_utf8_names_are_listed(self):
        raw = make_non_utf8_file(self, b"")
        entries = self.ok_json("ls", H.b64(self.tmp), "n")
        self.assertEqual(len(entries), 1)
        self.assertEqual(os.fsencode(entries[0]["absolutePath"]), raw)


class NonAsciiPathTests(FileTestCase):
    # iTerm2 sends a path's bytes (Conductor+SSHEndpoint.swift uses path.data(using: .utf8)),
    # and they must reach the filesystem unchanged.
    def test_utf8_path(self):
        p = self.write("café.txt", b"hello")
        obj = self.ok_json("stat", H.b64(p))
        self.assertEqual(obj["absolutePath"], p)

    # A name that is not UTF-8 at all, as ls reports it (decoded with surrogateescape), can be
    # sent back.
    def test_non_utf8_path_from_ls_can_be_fetched(self):
        raw = make_non_utf8_file(self, b"data")
        reply = self.ok("fetch", H.b64(raw))
        self.assertEqual(base64.b64decode("".join(reply.lines)), b"data")

    # The same at the unit level, so it is checked even where the filesystem (APFS, for one)
    # refuses names that are not UTF-8.
    def test_make_path_round_trips_raw_bytes(self):
        for raw in (b"/tmp/caf\xc3\xa9", b"/tmp/caf\xe9"):
            self.assertEqual(os.fsencode(self.framer.make_path(H.b64(raw))), raw)

    def test_ascii_paths_with_spaces_and_newlines(self):
        p = self.write("a b\nc", b"z")
        obj = self.ok_json("stat", H.b64(p))
        self.assertEqual(obj["absolutePath"], p)


class FetchTests(FileTestCase):
    def fetch(self, *args):
        return base64.b64decode("".join(self.ok("fetch", *args).lines))

    def test_whole_binary_file(self):
        content = bytes(range(256)) * 40 + b"\x1b]134;:end x 0 r\x1b\\"
        self.assertEqual(self.fetch(H.b64(self.write("bin", content))), content)

    def test_lines_are_short_base64(self):
        lines = self.ok("fetch", H.b64(self.write("bin", b"x" * 1000))).lines
        self.assertTrue(all(len(line) <= 76 for line in lines), lines)
        self.assertEqual(lines[-1], "")

    def test_a_chunk(self):
        p = self.write("chunk", b"0123456789")
        self.assertEqual(self.fetch(H.b64(p), "3", "4"), b"3456")

    def test_a_chunk_past_the_end(self):
        p = self.write("chunk", b"0123456789")
        self.assertEqual(self.fetch(H.b64(p), "8", "100"), b"89")
        self.assertEqual(self.fetch(H.b64(p), "50", "4"), b"")

    def test_empty_file(self):
        self.assertEqual(self.fetch(H.b64(self.write("empty"))), b"")

    def test_missing_file(self):
        self.assertEqual(self.status("fetch", H.b64(self.path("nope"))), ENOENT)

    def test_directory(self):
        self.assertEqual(self.status("fetch", H.b64(self.tmp)), OTHER)

    @unittest.skipIf(is_root, "root ignores permissions")
    def test_unreadable_file(self):
        p = self.write("secret", b"x")
        os.chmod(p, 0)
        self.assertNotEqual(self.status("fetch", H.b64(p)), 0)

    def test_follows_symlinks(self):
        self.write("target", b"through the link")
        os.symlink("target", self.path("link"))
        self.assertEqual(self.fetch(H.b64(self.path("link"))), b"through the link")


class StatTests(FileTestCase):
    def test_file(self):
        p = self.write("f", b"abc")
        obj = self.ok_json("stat", H.b64(p))
        self.assertEqual(obj["absolutePath"], p)
        self.assertEqual(obj["kind"], {"file": {"_0": {"size": 3}}})
        self.assertEqual(obj["parentPermissions"], {"r": True, "w": True, "x": True})

    def test_directory(self):
        self.assertEqual(self.ok_json("stat", H.b64(self.tmp))["kind"], {"folder": {}})

    def test_symlink_is_not_followed(self):
        os.symlink("/nonexistent/target", self.path("dangling"))
        obj = self.ok_json("stat", H.b64(self.path("dangling")))
        self.assertEqual(obj["kind"], {"symlink": {"_0": "/nonexistent/target"}})

    def test_missing(self):
        self.assertEqual(self.status("stat", H.b64(self.path("nope"))), ENOENT)

    def test_through_a_file(self):
        p = self.write("f")
        self.assertEqual(self.status("stat", H.b64(os.path.join(p, "x"))), ENOTDIR)

    def test_a_path_that_is_not_a_path(self):
        # Not an OSError at all (embedded NUL): the catch-all status.
        self.assertEqual(self.status("stat", H.b64(b"/tmp/a\0b")), 255)

    def test_special_file_is_null(self):
        # Neither file, folder nor symlink: the reply succeeds with JSON null.
        os.mkfifo(self.path("fifo"))
        self.assertIsNone(self.ok_json("stat", H.b64(self.path("fifo"))))


class SuggestTests(FileTestCase):
    def suggest(self, prefix, directories, pwd, permissions="r", limit=100):
        dirs = " ".join(H.b64(d) for d in directories) or " "
        return self.ok_json("suggest", H.b64(prefix), dirs, H.b64(pwd), permissions, str(limit))

    def setUp(self):
        super().setUp()
        for name in ("foo.txt", "food", "bar"):
            self.write(name)
        os.mkdir(self.path("folder"))
        os.chmod(self.path("food"), 0o755)

    def test_relative_prefix_in_an_absolute_directory(self):
        self.assertEqual(self.suggest("fo", [self.tmp], ""), ["lder", "o.txt", "od"])

    def test_relative_directory_uses_the_working_directory(self):
        parent, name = os.path.split(self.tmp)
        self.assertEqual(self.suggest("ba", [name], parent), ["r"])

    def test_relative_directory_without_a_working_directory_is_skipped(self):
        self.assertEqual(self.suggest("ba", ["relative"], ""), [])

    def test_executables_only(self):
        self.assertEqual(self.suggest("fo", [self.tmp], "", permissions="rx"),
                         ["lder", "od"])

    def test_prefix_naming_a_directory_offers_its_slash(self):
        self.assertIn("/", self.suggest("folder", [self.tmp], ""))

    def test_prefix_ending_in_a_slash_lists_the_directory(self):
        self.write(os.path.join("folder", "inner"))
        self.assertEqual(self.suggest("folder/", [self.tmp], ""), ["inner"])

    def test_absolute_prefix(self):
        result = self.suggest(self.path("ba"), ["/"], "")
        self.assertEqual(result, ["r"])

    def test_limit(self):
        self.assertEqual(len(self.suggest("", [self.tmp], "", limit=2)), 2)

    # Each directory can contribute up to the limit, so the combined result must be cut.
    def test_never_returns_more_than_the_limit(self):
        other = H.scratch_dir()
        try:
            with open(os.path.join(other, "fox"), "w"):
                pass
            result = self.suggest("fo", [self.tmp, other], "", limit=2)
            self.assertLessEqual(len(result), 2, result)
        finally:
            os.unlink(os.path.join(other, "fox"))
            os.rmdir(other)

    def test_relative_working_directory(self):
        # Neither prefix nor directory is absolute, so only the prefix itself is considered.
        self.assertEqual(self.suggest("fo", ["."], "relative"), [])

    def test_missing_directory_has_no_suggestions(self):
        self.assertEqual(self.suggest("fo", [self.path("nope")], ""), [])

    def test_no_directories(self):
        self.assertEqual(self.suggest("fo", [], ""), [])


class RmTests(FileTestCase):
    def test_file(self):
        p = self.write("f")
        self.ok("rm", H.b64(p))
        self.assertFalse(os.path.exists(p))

    def test_empty_directory(self):
        os.mkdir(self.path("d"))
        self.ok("rm", H.b64(self.path("d")))
        self.assertFalse(os.path.exists(self.path("d")))

    def test_non_empty_directory_needs_r(self):
        os.mkdir(self.path("d"))
        self.write(os.path.join("d", "f"))
        self.assertEqual(self.status("rm", H.b64(self.path("d"))), OTHER)
        self.assertTrue(os.path.exists(self.path("d", "f")))
        self.ok("rm", "-r", H.b64(self.path("d")))
        self.assertFalse(os.path.exists(self.path("d")))

    def test_unknown_flags_are_ignored(self):
        p = self.write("f")
        self.ok("rm", "-f", H.b64(p))
        self.assertFalse(os.path.exists(p))

    def test_flags_without_a_path_fail(self):
        self.assertEqual(self.status("rm", "-r"), OTHER)

    def test_missing(self):
        self.assertEqual(self.status("rm", H.b64(self.path("nope"))), ENOENT)

    def test_symlink_to_a_file_removes_only_the_link(self):
        target = self.write("target")
        os.symlink("target", self.path("link"))
        self.ok("rm", H.b64(self.path("link")))
        self.assertFalse(os.path.lexists(self.path("link")))
        self.assertTrue(os.path.exists(target))

    def test_dangling_symlink(self):
        os.symlink("nowhere", self.path("link"))
        self.ok("rm", H.b64(self.path("link")))
        self.assertFalse(os.path.lexists(self.path("link")))

    def test_symlink_to_a_directory_removes_the_link(self):
        os.mkdir(self.path("real"))
        os.symlink("real", self.path("link"))
        self.ok("rm", H.b64(self.path("link")))
        self.assertFalse(os.path.lexists(self.path("link")))
        self.assertTrue(os.path.isdir(self.path("real")))

    def test_recursive_removal_of_a_symlinked_directory_leaves_the_target_alone(self):
        os.mkdir(self.path("real"))
        keep = self.write(os.path.join("real", "keep"))
        os.symlink("real", self.path("link"))
        self.ok("rm", "-r", H.b64(self.path("link")))
        self.assertFalse(os.path.lexists(self.path("link")))
        self.assertTrue(os.path.exists(keep), "never deletes through the link")

    @unittest.skipIf(is_root, "root ignores permissions")
    def test_permission_denied(self):
        os.mkdir(self.path("ro"))
        p = self.write(os.path.join("ro", "f"))
        os.chmod(self.path("ro"), 0o500)
        self.assertNotEqual(self.status("rm", H.b64(p)), 0)
        self.assertTrue(os.path.exists(p))


class LnTests(FileTestCase):
    def test_creates_a_symlink_and_describes_it(self):
        obj = self.ok_json("ln", H.b64("some/target"), H.b64(self.path("link")))
        self.assertEqual(os.readlink(self.path("link")), "some/target")
        self.assertEqual(obj["kind"], {"symlink": {"_0": "some/target"}})
        self.assertEqual(obj["absolutePath"], self.path("link"))

    def test_existing_name(self):
        self.write("taken")
        self.assertEqual(self.status("ln", H.b64("x"), H.b64(self.path("taken"))), OTHER)

    def test_missing_parent(self):
        self.assertEqual(self.status("ln", H.b64("x"), H.b64(self.path("no", "link"))), ENOENT)


class MvTests(FileTestCase):
    def test_rename(self):
        src = self.write("a", b"abc")
        obj = self.ok_json("mv", H.b64(src), H.b64(self.path("b")))
        self.assertFalse(os.path.exists(src))
        self.assertEqual(obj["absolutePath"], self.path("b"))
        self.assertEqual(obj["kind"], {"file": {"_0": {"size": 3}}})

    def test_directory(self):
        os.mkdir(self.path("d1"))
        self.write(os.path.join("d1", "f"))
        self.assertEqual(self.ok_json("mv", H.b64(self.path("d1")),
                                      H.b64(self.path("d2")))["kind"], {"folder": {}})
        self.assertTrue(os.path.exists(self.path("d2", "f")))

    def test_symlink_moves_the_link(self):
        os.symlink("target", self.path("l1"))
        self.ok("mv", H.b64(self.path("l1")), H.b64(self.path("l2")))
        self.assertEqual(os.readlink(self.path("l2")), "target")

    def test_missing_source(self):
        self.assertEqual(self.status("mv", H.b64(self.path("nope")), H.b64(self.path("b"))),
                         ENOENT)

    def test_missing_destination_directory(self):
        src = self.write("a")
        self.assertNotEqual(self.status("mv", H.b64(src), H.b64(self.path("no", "b"))), 0)
        self.assertTrue(os.path.exists(src))


class MkdirTests(FileTestCase):
    def test_creates(self):
        self.ok("mkdir", H.b64(self.path("new")))
        self.assertTrue(os.path.isdir(self.path("new")))

    def test_exists(self):
        os.mkdir(self.path("new"))
        self.assertEqual(self.status("mkdir", H.b64(self.path("new"))), OTHER)

    def test_missing_parent(self):
        self.assertEqual(self.status("mkdir", H.b64(self.path("a", "b"))), ENOENT)

    def test_through_a_file(self):
        self.write("f")
        self.assertEqual(self.status("mkdir", H.b64(self.path("f", "b"))), ENOTDIR)


class CreateAndAppendTests(FileTestCase):
    def test_create(self):
        content = bytes(range(256))
        obj = self.ok_json("create", H.b64(self.path("new")), H.b64(content))
        with open(self.path("new"), "rb") as f:
            self.assertEqual(f.read(), content)
        self.assertEqual(obj["kind"], {"file": {"_0": {"size": 256}}})

    def test_create_with_content_split_across_arguments(self):
        encoded = H.b64(b"0123456789" * 10)
        self.ok("create", H.b64(self.path("new")), encoded[:40], encoded[40:])
        with open(self.path("new"), "rb") as f:
            self.assertEqual(f.read(), b"0123456789" * 10)

    def test_create_empty_file(self):
        # Conductor sends "=" for empty content (nonEmptyBase64EncodedString).
        self.ok("create", H.b64(self.path("empty")), "=")
        self.assertEqual(os.path.getsize(self.path("empty")), 0)

    def test_create_replaces(self):
        p = self.write("f", b"old contents")
        self.ok("create", H.b64(p), H.b64(b"new"))
        with open(p, "rb") as f:
            self.assertEqual(f.read(), b"new")

    def test_create_in_a_missing_directory_fails(self):
        self.assertEqual(self.status("create", H.b64(self.path("no", "f")), H.b64(b"x")),
                         ENOENT)

    def test_append(self):
        p = self.write("f", b"abc")
        obj = self.ok_json("append", H.b64(p), H.b64(b"def"))
        with open(p, "rb") as f:
            self.assertEqual(f.read(), b"abcdef")
        self.assertEqual(obj["kind"], {"file": {"_0": {"size": 6}}})

    def test_append_creates(self):
        self.ok("append", H.b64(self.path("new")), H.b64(b"x"))
        self.assertTrue(os.path.exists(self.path("new")))

    def test_append_in_a_missing_directory(self):
        self.assertEqual(self.status("append", H.b64(self.path("no", "f")), H.b64(b"x")),
                         ENOENT)

    def test_append_to_a_directory(self):
        self.assertEqual(self.status("append", H.b64(self.tmp), H.b64(b"x")), OTHER)


class UtimeAndChmodTests(FileTestCase):
    def test_utime(self):
        p = self.write("f")
        obj = self.ok_json("utime", H.b64(p), "1600000000.75")
        self.assertEqual(int(os.stat(p).st_mtime), 1600000000)
        self.assertEqual(obj["mtime"], 1600000000 - NSDATE_EPOCH)

    def test_utime_missing(self):
        self.assertEqual(self.status("utime", H.b64(self.path("nope")), "0"), ENOENT)

    def test_chmod_sets_only_the_user_bits(self):
        p = self.write("f")
        os.chmod(p, 0o640)
        obj = self.ok_json("chmod-u", H.b64(p), "r-x")
        self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o540)
        self.assertEqual(obj["permissions"], {"r": True, "w": False, "x": True})
        self.ok("chmod-u", H.b64(p), "rw-")
        self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o640)

    def test_chmod_missing(self):
        self.assertEqual(self.status("chmod-u", H.b64(self.path("nope")), "rwx"), ENOENT)


class ZipTests(FileTestCase):
    def setUp(self):
        super().setUp()
        self.home = self.path("home")
        os.mkdir(self.home)

    def zip(self, target):
        with env(HOME=self.home):
            return self.file("zip", H.b64(target))

    def test_zips_a_directory_into_home(self):
        os.makedirs(self.path("tree", "sub"))
        self.write(os.path.join("tree", "a"), b"A")
        self.write(os.path.join("tree", "sub", "b"), b"B")
        reply = self.zip(self.path("tree"))
        self.assertEqual(reply.status, 0, reply)
        archive = reply.lines[0]
        self.assertEqual(os.path.dirname(archive), self.home)
        self.assertTrue(os.path.basename(archive).startswith("."))
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(sorted(z.namelist()), ["tree/a", "tree/sub/b"])
            self.assertEqual(z.read("tree/sub/b"), b"B")

    @unittest.skipIf(is_root, "root ignores permissions")
    def test_unreadable_files_are_left_out(self):
        os.mkdir(self.path("tree"))
        self.write(os.path.join("tree", "ok"), b"x")
        os.chmod(self.write(os.path.join("tree", "secret"), b"y"), 0)
        reply = self.zip(self.path("tree"))
        self.assertEqual(reply.status, 0)
        with zipfile.ZipFile(reply.lines[0]) as z:
            self.assertEqual(z.namelist(), ["tree/ok"])

    def test_not_a_directory(self):
        self.assertEqual(self.zip(self.write("f")).status, ENOTDIR)

    def test_missing(self):
        self.assertEqual(self.zip(self.path("nope")).status, ENOENT)

    @unittest.skipIf(is_root, "root ignores permissions")
    def test_unwritable_home(self):
        os.mkdir(self.path("tree"))
        os.chmod(self.home, 0o500)
        self.assertNotEqual(self.zip(self.path("tree")).status, 0)


class SearchTests(FileTestCase):
    """search start answers with an id and then reports matches as %notif search frames,
    at most 16 ahead of iTerm2's acks."""

    def notifs(self, search_id):
        prefix = "search %s " % search_id
        return [json.loads(e.text[len(prefix):]) for e in self.h.parser.notifications("notif")
                if e.text.startswith(prefix)]

    async def results(self, search_id, count):
        """Waits for count notifications and returns them. The scan thread hands each match
        to the event loop separately, so the search's task can finish before they are
        written."""
        self.assertTrue(await self.h.wait_for(lambda: len(self.notifs(search_id)) >= count))
        return self.notifs(search_id)

    async def start(self, query, base):
        reply = await self.h.command("file", "search", "start", H.b64(query), H.b64(base))
        self.assertEqual(reply.status, 0)
        return reply.lines[0]

    def test_finds_files_by_name_and_skips_directories_and_symlinks(self):
        os.makedirs(self.path("a", "match-dir"))
        self.write(os.path.join("a", "match-1"))
        self.write(os.path.join("a", "match-dir", "match-2"))
        self.write("other")
        os.symlink("other", self.path("match-link"))

        async def body():
            search_id = await self.start("match", self.tmp)
            await asyncio.wait_for(self.framer.SEARCH_TASK.task, H.TIMEOUT)
            found = sorted(o["absolutePath"] for o in await self.results(search_id, 2))
            self.assertEqual(found, [self.path("a", "match-1"),
                                     self.path("a", "match-dir", "match-2")])
        self.run_async(body)

    def test_waits_for_acks_after_sixteen(self):
        for i in range(20):
            self.write("m%02d" % i)

        async def body():
            search_id = await self.start("m", self.tmp)
            self.assertTrue(await self.h.wait_for(lambda: len(self.notifs(search_id)) >= 16))
            self.assertEqual(len(self.notifs(search_id)), 16)
            self.assertFalse(self.framer.SEARCH_TASK.task.done())
            # An ack for some other search changes nothing.
            await self.h.command("file", "search", "ack", "bogus", "4")
            ack = await self.h.command("file", "search", "ack", search_id, "4")
            self.assertEqual(ack.status, 0)
            await asyncio.wait_for(self.framer.SEARCH_TASK.task, H.TIMEOUT)
            self.assertEqual(len(await self.results(search_id, 20)), 20)
        self.run_async(body)

    def test_stop_while_waiting_for_acks(self):
        for i in range(20):
            self.write("m%02d" % i)

        async def body():
            search_id = await self.start("m", self.tmp)
            task = self.framer.SEARCH_TASK.task
            self.assertTrue(await self.h.wait_for(lambda: len(self.notifs(search_id)) >= 16))
            # Acks beyond the window are capped rather than raising.
            self.framer.SEARCH_TASK.ack(100)
            await self.h.command("file", "search", "stop", search_id)
            await asyncio.wait_for(task, H.TIMEOUT)
            self.assertLessEqual(len(self.notifs(search_id)), 20)
        self.run_async(body)

    def test_stop_and_restart(self):
        for i in range(20):
            self.write("m%02d" % i)

        async def body():
            first = await self.start("m", self.tmp)
            task = self.framer.SEARCH_TASK.task
            await self.h.command("file", "search", "stop", "not-the-id")
            self.assertIsNotNone(self.framer.SEARCH_TASK)
            stop = await self.h.command("file", "search", "stop", first)
            self.assertEqual(stop.status, 0)
            self.assertIsNone(self.framer.SEARCH_TASK)
            await asyncio.wait_for(task, H.TIMEOUT)
            self.assertLessEqual(len(self.notifs(first)), 16)

            # Starting a search cancels the one in progress.
            second = await self.start("m0", self.tmp)
            task = self.framer.SEARCH_TASK.task
            third = await self.start("m1", self.tmp)
            self.assertNotEqual(second, third)
            await asyncio.wait_for(task, H.TIMEOUT)
            await asyncio.wait_for(self.framer.SEARCH_TASK.task, H.TIMEOUT)
            self.assertEqual(len(await self.results(third, 10)), 10)
        self.run_async(body)

    def test_missing_base_directory_finds_nothing(self):
        async def body():
            search_id = await self.start("x", self.path("nope"))
            await asyncio.wait_for(self.framer.SEARCH_TASK.task, H.TIMEOUT)
            self.assertEqual(self.notifs(search_id), [])
        self.run_async(body)

    def test_unknown_operation_is_ignored(self):
        self.assertEqual(self.status("search", "sideways"), 0)


if __name__ == "__main__":
    unittest.main()
