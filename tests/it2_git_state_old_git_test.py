#!/usr/bin/env python3
# it2_git_state.py on a host with old git. Each case builds a repository and runs collect()
# twice: with the real git, and with a shim in front of it that rejects what git before 2.28
# (or 2.13, or 2.11) does not know, as git 1.8 would. Both must report the same.
#
#   python3 tests/it2_git_state_old_git_test.py

import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "OtherResources", "it2_git_state.py")
spec = importlib.util.spec_from_file_location("it2_git_state", SCRIPT)
gs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gs)

REAL_GIT = shutil.which("git")
# rev-parse echoes an option it doesn't know and succeeds, as git 1.8 does; the others fail.
SHIM = """#!/bin/sh
for arg in "$@"; do
  case "$arg" in
    --absolute-git-dir)
      echo "$arg"
      exit 0;;
    --porcelain=v2|--no-relative)
      echo "error: unknown option $arg" >&2
      exit 129;;
  esac
done
exec "%s" "$@"
""" % REAL_GIT


class OldGitTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.shim_dir = os.path.join(self.tmp, "shim")
        os.mkdir(self.shim_dir)
        shim = os.path.join(self.shim_dir, "git")
        with open(shim, "w") as f:
            f.write(SHIM)
        os.chmod(shim, os.stat(shim).st_mode | stat.S_IEXEC)
        self.path = os.environ["PATH"]
        self.repo = os.path.join(self.tmp, "repo")
        os.mkdir(self.repo)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "T")

    def tearDown(self):
        os.environ["PATH"] = self.path
        shutil.rmtree(self.tmp)

    def git(self, *args, cwd=None):
        subprocess.run([REAL_GIT] + list(args), cwd=cwd or self.repo, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def write(self, name, text):
        path = os.path.join(self.repo, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def commit(self, message="c"):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def both(self, path=None, base=""):
        request = {"path": path or self.repo, "stats": True, "base": base}
        os.environ["PATH"] = self.path
        modern = gs.collect(request, time.monotonic() + 10)
        os.environ["PATH"] = self.shim_dir + os.pathsep + self.path
        old = gs.collect(request, time.monotonic() + 10)
        os.environ["PATH"] = self.path
        return modern, old

    def assertSame(self, path=None, base=""):
        modern, old = self.both(path, base)
        self.assertNotEqual(modern, {"repo": False})
        self.assertEqual(old, modern)
        return modern

    def test_shim_rejects_what_old_git_lacks(self):
        os.environ["PATH"] = self.shim_dir + os.pathsep + self.path
        git = gs.Git(self.repo, time.monotonic() + 10)
        self.assertEqual(git("rev-parse", "--absolute-git-dir"), b"--absolute-git-dir\n")
        self.assertIsNotNone(git("rev-parse", "--git-dir"))
        self.assertEqual(gs.find_git_dir(git), os.path.join(self.repo, ".git"))

    def test_changes_from_a_subdirectory_with_diff_relative_set(self):
        self.write("a.txt", "1\n2\n")
        self.write("sub/b.txt", "x\n")
        self.write("gone.txt", "bye\n")
        self.commit()
        self.git("config", "diff.relative", "true")
        self.write("a.txt", "1\n2\n3\n")
        self.write("sub/b.txt", "y\n")
        self.write("new.txt", "n\n")
        self.git("add", "new.txt")
        self.write("untracked.txt", "u\n")
        os.remove(os.path.join(self.repo, "gone.txt"))
        result = self.assertSame(path=os.path.join(self.repo, "sub"))
        self.assertEqual(result["stats"]["filesModified"], 2, "changes outside the subdirectory count")
        self.assertEqual(result["stats"]["linesInserted"], 2)
        self.assertEqual(result["deletes"], 1)

    def test_a_rename_without_changes(self):
        self.write("old.txt", "same\n")
        self.commit()
        self.git("mv", "old.txt", "new.txt")
        self.assertSame()

    def test_intent_to_add_and_its_rename_in_the_work_tree(self):
        self.write("old.txt", "same\n")
        self.commit()
        self.write("later.txt", "l\n")
        os.rename(os.path.join(self.repo, "old.txt"), os.path.join(self.repo, "moved.txt"))
        self.git("add", "-N", "later.txt", "moved.txt")
        result = self.assertSame()
        self.assertEqual(result["deletes"], 1)

    def test_ahead_and_behind_and_a_gone_upstream(self):
        self.write("a.txt", "1\n")
        self.commit()
        remote = os.path.join(self.tmp, "remote.git")
        self.git("clone", "-q", "--bare", self.repo, remote, cwd=self.tmp)
        self.git("remote", "add", "origin", remote)
        self.git("fetch", "-q", "origin")
        self.git("branch", "-q", "-u", "origin/main")
        self.write("a.txt", "2\n")
        self.commit()
        self.assertEqual(self.assertSame()["ahead"], "1")
        self.git("checkout", "-q", "-b", "topic")
        self.git("push", "-q", "-u", "origin", "topic")
        self.git("push", "-q", "origin", "--delete", "topic")
        self.git("fetch", "-q", "--prune", "origin")
        self.assertEqual(self.assertSame()["ahead"], "")

    def test_detached_head(self):
        self.write("a.txt", "1\n")
        self.commit()
        self.write("a.txt", "2\n")
        self.commit()
        self.git("checkout", "-q", "HEAD~1")
        self.assertSame()

    def test_a_conflict(self):
        self.write("a.txt", "base\n")
        self.commit()
        self.git("checkout", "-q", "-b", "other")
        self.write("a.txt", "other\n")
        self.commit()
        self.git("checkout", "-q", "main")
        self.write("a.txt", "main\n")
        self.commit()
        subprocess.run([REAL_GIT, "merge", "-q", "other"], cwd=self.repo,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        result = self.assertSame()
        self.assertEqual(result["repoState"], "merge")

    def test_against_a_base(self):
        self.write("a.txt", "1\n")
        self.commit()
        self.git("branch", "base")
        self.write("b.txt", "2\n")
        self.commit()
        self.assertSame(base="base")

    def test_a_rename_to_a_path_that_is_not_utf8(self):
        # It counts toward dirty, and its original path is not read as an entry of its own.
        output = b"## main\0R  \xff.txt\0old.txt\0?? u.txt\0"
        info, entries, count, untracked, deleted = gs.parse_status_v1(output, "abc")
        self.assertEqual((count, untracked, entries), (2, 1, []))

    def test_unborn_head_and_no_repository(self):
        modern, old = self.both()
        self.assertEqual(modern, {"repo": False})
        self.assertEqual(old, {"repo": False})
        elsewhere = os.path.join(self.tmp, "plain")
        os.mkdir(elsewhere)
        modern, old = self.both(path=elsewhere)
        self.assertEqual((modern, old), ({"repo": False}, {"repo": False}))


if __name__ == "__main__":
    unittest.main()
