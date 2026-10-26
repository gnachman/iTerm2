#!/usr/bin/env python3
"""Exercises the exit codes framer.py's file commands report on failure. iTerm2 reads
them in Conductor+SSHEndpoint.swift: 1 is permission denied (EPERM or EACCES), 2 is
ENOENT, 3 is ENOTDIR, 4 is ELOOP, and anything else is a generic failure.

Run: python3 tests/framer_commands_test.py
"""
import asyncio
import base64
import errno
import importlib.util
import json
import os
import shutil
import stat
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
FRAMER_PATH = os.path.join(HERE, "..", "OtherResources", "framer.py")

_spec = importlib.util.spec_from_file_location("framer_under_test", FRAMER_PATH)
framer = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(framer)
framer.DEPTH = 0

# Capture frames instead of writing them to stdout.
_frames = []
framer.unlock = lambda writes: _frames.extend(
    w if isinstance(w, str) else w.decode("latin-1") for w in writes
)

PERMISSION_DENIED = 1
NOT_FOUND = 2
NOT_A_DIRECTORY = 3
GENERIC = 100

# zip writes its archive into the home folder. Use a scratch one.
_SCRATCH_HOME = tempfile.mkdtemp()
os.environ["HOME"] = _SCRATCH_HOME

# Permission checks do not apply to root.
IS_ROOT = os.geteuid() == 0


def end_status(identifier):
    """Return the integer status a handler reported via end(...) for identifier."""
    for f in _frames:
        if not (f.startswith("\033]134;:") and f.endswith("\033\\")):
            continue
        parts = f[len("\033]134;:"):-2].split()
        if len(parts) >= 3 and parts[0] == "end" and parts[1] == identifier:
            return int(parts[2])
    return None


def payload(identifier):
    """Return the concatenated non-begin/end lines a handler sent, as iTerm2 joins them."""
    out = []
    for f in _frames:
        if not (f.startswith("\033]134;:") and f.endswith("\033\\")):
            continue
        text = f[len("\033]134;:"):-2]
        parts = text.split()
        if parts and parts[0] in ("begin", "end") and len(parts) >= 2 and parts[1] == identifier:
            continue
        out.append(text)
    return "".join(out)


def b64(path):
    return base64.b64encode(path.encode("utf-8")).decode("ascii")


async def run_file_command(identifier, args):
    _frames.clear()
    try:
        await framer.handle_file(identifier, args)
    except Exception as e:
        print(f"  handler for {args[0]} threw {e!r}")
        return None
    return end_status(identifier)


class Checker:
    def __init__(self):
        self.ok = True

    def check(self, cond, msg):
        if not cond:
            self.ok = False
            print("  FAIL:", msg)


async def test_file_error_maps_errnos():
    print("test_file_error_maps_errnos")
    c = Checker()
    cases = [
        (PermissionError(errno.EACCES, "Permission denied"), PERMISSION_DENIED),
        (PermissionError(errno.EPERM, "Operation not permitted"), PERMISSION_DENIED),
        (FileNotFoundError(errno.ENOENT, "No such file"), NOT_FOUND),
        (NotADirectoryError(errno.ENOTDIR, "Not a directory"), NOT_A_DIRECTORY),
        (OSError(errno.ELOOP, "Too many levels of symbolic links"), 4),
        (OSError(errno.EIO, "Input/output error"), GENERIC),
        (None, GENERIC),
        (ValueError("bad"), 255),
    ]
    for i, (exc, expected) in enumerate(cases):
        _frames.clear()
        identifier = f"id-map-{i}"
        q = framer.begin(identifier)
        framer.file_error(q, identifier, exc, "/some/path")
        got = end_status(identifier)
        c.check(got == expected, f"{exc!r} -> {got}, expected {expected}")
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_fetch_unreadable_file_is_permission_denied():
    print("test_fetch_unreadable_file_is_permission_denied")
    if IS_ROOT:
        print("  SKIP (running as root)")
        return True
    c = Checker()
    d = tempfile.mkdtemp()
    path = os.path.join(d, "secret")
    try:
        with open(path, "wb") as f:
            f.write(b"hello")
        os.chmod(path, 0)
        got = await run_file_command("id-fetch", ["fetch", b64(path), "0", "100"])
        c.check(got == PERMISSION_DENIED, f"fetch of chmod 000 file -> {got}")
    finally:
        os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_create_in_read_only_folder_is_permission_denied():
    print("test_create_in_read_only_folder_is_permission_denied")
    if IS_ROOT:
        print("  SKIP (running as root)")
        return True
    c = Checker()
    d = tempfile.mkdtemp()
    folder = os.path.join(d, "readonly")
    os.mkdir(folder)
    try:
        os.chmod(folder, 0o555)
        target = os.path.join(folder, "upload.uploading")
        # create used to call file_error with the wrong arguments, so it never ended.
        got = await run_file_command("id-create", ["create", b64(target), ""])
        c.check(got == PERMISSION_DENIED, f"create in chmod 555 folder -> {got}")
    finally:
        os.chmod(folder, 0o755)
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_missing_and_not_a_directory():
    print("test_missing_and_not_a_directory")
    c = Checker()
    d = tempfile.mkdtemp()
    try:
        missing = os.path.join(d, "missing")
        got = await run_file_command("id-stat", ["stat", b64(missing)])
        c.check(got == NOT_FOUND, f"stat of missing file -> {got}")

        regular = os.path.join(d, "regular")
        with open(regular, "wb") as f:
            f.write(b"x")
        got = await run_file_command("id-ls", ["ls", b64(regular), "n"])
        c.check(got == NOT_A_DIRECTORY, f"ls of a regular file -> {got}")

        got = await run_file_command("id-zip-file", ["zip", b64(regular)])
        c.check(got == NOT_A_DIRECTORY, f"zip of a regular file -> {got}")

        got = await run_file_command("id-zip-missing", ["zip", b64(missing)])
        c.check(got == NOT_FOUND, f"zip of a missing path -> {got}")
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_malformed_commands_are_not_permission_denied():
    print("test_malformed_commands_are_not_permission_denied")
    c = Checker()
    got = await run_file_command("id-short", ["stat"])
    c.check(got == GENERIC, f"too few arguments -> {got}")
    got = await run_file_command("id-unknown", ["bogus", "x"])
    c.check(got == GENERIC, f"unrecognized subcommand -> {got}")
    got = await run_file_command("id-rm", ["rm", "-r"])
    c.check(got == GENERIC, f"rm without a path -> {got}")
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


def _make_folder_with_unreadable_files():
    """Make d/top with a readable file, two unreadable files, and an unreadable subfolder."""
    d = tempfile.mkdtemp()
    top = os.path.join(d, "top")
    os.mkdir(top)
    with open(os.path.join(top, "ok.txt"), "wb") as f:
        f.write(b"ok")
    for name in ("secret1", "secret2"):
        p = os.path.join(top, name)
        with open(p, "wb") as f:
            f.write(b"x")
        os.chmod(p, 0)
    locked = os.path.join(top, "locked")
    os.mkdir(locked)
    with open(os.path.join(locked, "inner"), "wb") as f:
        f.write(b"x")
    os.chmod(locked, 0)
    return d, top


def _restore_permissions(top):
    os.chmod(os.path.join(top, "locked"), 0o755)
    for name in ("secret1", "secret2"):
        os.chmod(os.path.join(top, name), stat.S_IRUSR | stat.S_IWUSR)


def _archive_names(path):
    with zipfile.ZipFile(path) as z:
        return sorted(z.namelist())


async def test_zip_reply_is_a_bare_path_without_report_flag():
    # An iTerm2 that predates skipped-file reporting reads the whole reply as the path.
    print("test_zip_reply_is_a_bare_path_without_report_flag")
    if IS_ROOT:
        print("  SKIP (running as root)")
        return True
    c = Checker()
    d, top = _make_folder_with_unreadable_files()
    archive = None
    try:
        got = await run_file_command("id-zip-old", ["zip", b64(top)])
        c.check(got == 0, f"zip with unreadable files -> {got}")
        archive = payload("id-zip-old")
        c.check(os.path.isfile(archive), f"reply {archive!r} is not a file")
        if os.path.isfile(archive):
            c.check(_archive_names(archive) == ["top/ok.txt"], f"archive has {_archive_names(archive)}")
    finally:
        _restore_permissions(top)
        shutil.rmtree(d, ignore_errors=True)
        if archive and os.path.isfile(archive):
            os.unlink(archive)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_zip_reports_skipped_files_when_asked():
    print("test_zip_reports_skipped_files_when_asked")
    if IS_ROOT:
        print("  SKIP (running as root)")
        return True
    c = Checker()
    d, top = _make_folder_with_unreadable_files()
    archive = None
    try:
        got = await run_file_command("id-zip-new", ["zip", b64(top), "report-skipped"])
        c.check(got == 0, f"zip with unreadable files -> {got}")
        try:
            reply = json.loads(payload("id-zip-new"))
        except ValueError:
            c.check(False, f"reply is not JSON: {payload('id-zip-new')!r}")
            reply = {}
        archive = reply.get("path")
        c.check(archive and os.path.isfile(archive), f"path {archive!r} is not a file")
        if archive and os.path.isfile(archive):
            c.check(_archive_names(archive) == ["top/ok.txt"], f"archive has {_archive_names(archive)}")
        c.check(reply.get("skipped") == 3, f"skipped is {reply.get('skipped')}")
        c.check(sorted(reply.get("examples", [])) == ["locked/", "secret1", "secret2"],
                f"examples are {reply.get('examples')}")
    finally:
        _restore_permissions(top)
        shutil.rmtree(d, ignore_errors=True)
        if archive and os.path.isfile(archive):
            os.unlink(archive)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_zip_reports_nothing_skipped():
    print("test_zip_reports_nothing_skipped")
    c = Checker()
    d = tempfile.mkdtemp()
    top = os.path.join(d, "top")
    os.mkdir(top)
    with open(os.path.join(top, "ok.txt"), "wb") as f:
        f.write(b"ok")
    archive = None
    try:
        got = await run_file_command("id-zip-clean", ["zip", b64(top), "report-skipped"])
        c.check(got == 0, f"zip -> {got}")
        try:
            reply = json.loads(payload("id-zip-clean"))
        except ValueError:
            c.check(False, f"reply is not JSON: {payload('id-zip-clean')!r}")
            reply = {}
        archive = reply.get("path")
        c.check(reply.get("skipped") == 0, f"skipped is {reply.get('skipped')}")
        c.check(reply.get("examples") == [], f"examples are {reply.get('examples')}")
    finally:
        shutil.rmtree(d, ignore_errors=True)
        if archive and os.path.isfile(archive):
            os.unlink(archive)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def test_zip_of_unreadable_folder_is_permission_denied():
    print("test_zip_of_unreadable_folder_is_permission_denied")
    if IS_ROOT:
        print("  SKIP (running as root)")
        return True
    c = Checker()
    d = tempfile.mkdtemp()
    top = os.path.join(d, "top")
    os.mkdir(top)
    home_before = set(os.listdir(os.path.expanduser("~")))
    try:
        os.chmod(top, 0)
        got = await run_file_command("id-zip-locked", ["zip", b64(top), "report-skipped"])
        c.check(got == PERMISSION_DENIED, f"zip of chmod 000 folder -> {got}")
        leftover = set(os.listdir(os.path.expanduser("~"))) - home_before
        c.check(not leftover, f"left behind {leftover}")
    finally:
        os.chmod(top, 0o755)
        shutil.rmtree(d, ignore_errors=True)
    print("  PASS" if c.ok else "  FAILED")
    return c.ok


async def run():
    results = []
    for test in (
        test_file_error_maps_errnos,
        test_fetch_unreadable_file_is_permission_denied,
        test_create_in_read_only_folder_is_permission_denied,
        test_missing_and_not_a_directory,
        test_malformed_commands_are_not_permission_denied,
        test_zip_reply_is_a_bare_path_without_report_flag,
        test_zip_reports_skipped_files_when_asked,
        test_zip_reports_nothing_skipped,
        test_zip_of_unreadable_folder_is_permission_denied,
    ):
        results.append(await test())
    ok = all(results)
    shutil.rmtree(_SCRATCH_HOME, ignore_errors=True)
    print("PASS" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
