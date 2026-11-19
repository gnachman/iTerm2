"""Tests for tools/check_nonnil_locks.py and its use in tools/git-hooks/pre-commit.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_check_nonnil_locks.py'

The checker rejects a commit that adds an @synchronized whose lock is not
self, a class object or ITNonnilLock(...) (docs/swift-migration/concurrency.md,
section 2). Every case builds a temporary git repository with a staged
change and runs the checker in it as the hook does. The hook tests copy the
hooks directory into a temporary repository, point core.hooksPath at the
copy, and run git commit. The catalog check is replaced by a stub there, so
nothing parses the real string catalog. One test reads the real
iTerm2.xcodeproj to check the list of files the checker skips because they
are also compiled into helper targets.

These tests live here, beside the migration's other tool tests, because the
existing hook check (tools/check_untranslated_strings.py) has no tests and
tools/ has no test directory; tools/swift_migration/tests already holds the
tests of tools/sanitize_iterm2_plist.py, another script outside this folder.
"""

import importlib.util
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TOOL = os.path.join(REPO, "tools", "check_nonnil_locks.py")
HOOK = os.path.join(REPO, "tools", "git-hooks", "pre-commit")

spec = importlib.util.spec_from_file_location("check_nonnil_locks", TOOL)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def git_env(extra=None):
    env = dict(os.environ)
    for k in list(env):
        if k.startswith("GIT_"):
            del env[k]
    env.update({
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.com",
    })
    if extra:
        env.update(extra)
    return env


class RepoCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="nonnil-lock-test-")
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.git("init", "-q", "-b", "master")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *args, check=True):
        r = subprocess.run(["git"] + list(args), cwd=self.dir, env=git_env(),
                           capture_output=True, text=True)
        if check and r.returncode != 0:
            self.fail("git %s failed: %s" % (" ".join(args), r.stderr))
        return r

    def write(self, path, text):
        full = os.path.join(self.dir, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)

    def stage(self, path, text):
        self.write(path, text)
        self.git("add", "--", path)

    def commit_all(self, message="base"):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)

    def check(self, *args, env=None):
        r = subprocess.run([sys.executable, "-B", TOOL] + list(args), cwd=self.dir,
                           env=git_env(env), capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr


def method(body):
    return ('#import "DebugLogging.h"\n'
            "@implementation Foo\n"
            "- (void)m {\n"
            + body +
            "}\n"
            "@end\n")


class LockFormTests(RepoCase):
    """One staged new file per lock form."""

    def assertClean(self, body, path="sources/Foo.m"):
        self.stage(path, method(body))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)
        return out

    def assertReported(self, body, expr, path="sources/Foo.m"):
        self.stage(path, method(body))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("@synchronized(%s) locks on something" % expr, out)
        self.assertIn("Fix: @synchronized(ITNonnilLock(%s))" % expr, out)
        return out

    def test_self(self):
        self.assertClean("    @synchronized(self) { x(); }\n")
        self.assertClean("    @synchronized (self) {\n    }\n")
        self.assertClean("    @synchronized((self)) {\n    }\n")

    def test_class_object_forms(self):
        for expr in ("[Foo class]", "Foo.class", "self.class", "[self class]", "[Foo self]",
                     "[iTermFoo class]", "NSHost.class", "[ Foo  class ]"):
            with self.subTest(expr=expr):
                self.assertClean("    @synchronized(%s) {\n    }\n" % expr)

    def test_not_class_object_forms(self):
        for expr in ("object_getClass(self)", "[obj class]", "[super class]", "[_foo class]",
                     "[self classForCoder]"):
            with self.subTest(expr=expr):
                self.assertReported("    @synchronized(%s) {\n    }\n" % expr, expr)

    def test_ivar_unwrapped_and_wrapped(self):
        self.assertReported("    @synchronized(_lock) {\n    }\n", "_lock")
        self.assertClean("    @synchronized(ITNonnilLock(_lock)) {\n    }\n")
        self.assertClean("    @synchronized (ITNonnilLock (self->_lock)) {\n    }\n")

    def test_wrapping_must_cover_whole_expression(self):
        self.assertReported("    @synchronized(ITNonnilLock(a) ?: b) {\n    }\n",
                            "ITNonnilLock(a) ?: b")
        self.assertReported("    @synchronized(ITNonnilLock()) {\n    }\n", "ITNonnilLock()")

    def test_call_result(self):
        self.assertReported("    @synchronized([self lockObject]) {\n    }\n", "[self lockObject]")
        self.assertReported("    @synchronized(LockFor(self)) {\n    }\n", "LockFor(self)")

    def test_static_and_local_and_parameter(self):
        out = self.assertReported("    static id sLock;\n    @synchronized(sLock) {\n    }\n", "sLock")
        self.assertIn("statics, globals, locals and parameters", out)
        self.assertReported("    id lock = [self make];\n    @synchronized(lock) {\n    }\n", "lock")

    def test_property_access(self):
        self.assertReported("    @synchronized(self.lock) {\n    }\n", "self.lock")

    def test_multi_line_expression(self):
        self.assertClean("    @synchronized\n    (\n        ITNonnilLock(\n            _lock)\n    ) {\n    }\n")
        out = self.assertReported("    @synchronized (\n        [self\n          lockFor:1]) {\n    }\n",
                                  "[self lockFor:1]")
        self.assertIn("sources/Foo.m:4:", out)

    def test_parentheses_brackets_and_string_with_paren(self):
        self.assertClean('    @synchronized(ITNonnilLock([self lockFor:@")" at:(a[1])])) {\n    }\n')
        self.assertReported('    @synchronized([d objectForKey:@")("]) {\n    }\n',
                            '[d objectForKey:@")("]')
        self.assertReported("    @synchronized(table[')']) {\n    }\n", "table[')']")

    def test_comment_inside_expression_is_dropped_from_message(self):
        self.assertReported("    @synchronized(_lock /* the lock */) {\n    }\n", "_lock")

    def test_synchronized_in_comments_and_strings(self):
        self.assertClean("    // @synchronized(_lock) {\n"
                         "    /* @synchronized(_lock) */\n"
                         "    /*\n     @synchronized(_lock)\n     */\n"
                         '    NSLog(@"@synchronized(_lock)");\n'
                         '    puts("say \\"@synchronized(_lock)\\"");\n')

    def test_escape_hatch(self):
        self.assertClean("    @synchronized(object) {  // nonnil-lock-ok: tests the nil path\n    }\n")
        out = self.assertClean("    @synchronized(object) {  //nonnil-lock-ok:reason\n    }\n")
        self.assertEqual(out, "")
        self.assertClean("    @synchronized(  // nonnil-lock-ok: expression continues below\n"
                         "        object) {\n    }\n")

    def test_escape_hatch_without_reason(self):
        self.stage("sources/Foo.m", method("    @synchronized(object) {  // nonnil-lock-ok:   \n    }\n"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("needs a reason", out)
        self.assertIn("Fix: @synchronized(ITNonnilLock(object))", out)

    def test_escape_hatch_must_be_on_the_keyword_line(self):
        self.assertReported("    // nonnil-lock-ok: wrong line\n    @synchronized(object) {\n    }\n",
                            "object")

    def test_files_outside_covered_directories(self):
        body = "    @synchronized(_lock) {\n    }\n"
        for path in ("pidinfo/pidinfo.m", "SignedArchive/SIGIdentity.m", "ThirdParty/Other/X.m",
                     "tools/fixture/sources/X.m", "submodules/x/X.m", "ColorPicker/X.m",
                     "sources/XPC/iTermSandboxedWorkerClient.m", "sources/Foo.c", "sources/Foo.cpp"):
            with self.subTest(path=path):
                self.git("rm", "-q", "-r", "--cached", "--ignore-unmatch", ".")
                self.assertClean(body, path=path)

    def test_covered_directories_and_suffixes(self):
        body = "    @synchronized(_lock) {\n    }\n"
        for path in ("sources/A/B.mm", "sources/B.h", "ThirdParty/PSMTabBarControl/source/P.m",
                     "ModernTests/T.m"):
            with self.subTest(path=path):
                self.git("rm", "-q", "-r", "--cached", "--ignore-unmatch", ".")
                self.assertReported(body, "_lock", path=path)

    def test_swift_file_ignored(self):
        self.stage("sources/Foo.swift", "// @synchronized(_lock)\nlet s = \"@synchronized(_lock) {\"\n")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_import_hint(self):
        self.stage("sources/NoImport.m", "@implementation X\n- (void)m {\n    @synchronized(_a) {\n    }\n}\n@end\n")
        self.stage("sources/CommentedImport.m", "// #import \"DebugLogging.h\"\n- (void)m {\n    @synchronized(_a) {}\n}\n")
        self.stage("sources/Import.m", method("    @synchronized(_a) {\n    }\n"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/NoImport.m does not import DebugLogging.h directly", out)
        self.assertIn("sources/CommentedImport.m does not import DebugLogging.h directly", out)
        self.assertNotIn("sources/Import.m does not import", out)
        self.assertIn("3 @synchronized sites need ITNonnilLock", out)

    def test_objcxx_raw_string_and_digit_separator(self):
        self.assertClean('    auto s = R"x(@synchronized(_lock) ")x";\n'
                         "    int n = 1'000;\n"
                         "    @synchronized(self) {\n    }\n", path="sources/Foo.mm")
        self.assertReported("    int n = 1'000;\n    @synchronized(_lock) {\n    }\n", "_lock",
                            path="sources/Bar.mm")

    def test_top_level_comma_gets_extra_parentheses(self):
        # The preprocessor splits macro arguments at commas outside
        # parentheses, so ITNonnilLock([NSArray arrayWithObjects:a, b, nil])
        # would not compile.
        for expr in ("[NSArray arrayWithObjects:a, b, nil]", "@{a: b, c: d}[k]"):
            with self.subTest(expr=expr):
                self.stage("sources/Foo.m", method("    @synchronized(%s) {\n    }\n" % expr))
                rc, out = self.check()
                self.assertEqual(rc, 1, out)
                self.assertIn("@synchronized(%s) locks on something" % expr, out)
                self.assertIn("Fix: @synchronized(ITNonnilLock((%s)))\n" % expr, out)
        out = self.assertReported("    @synchronized(lock(a, b)) {\n    }\n", "lock(a, b)")
        self.assertClean("    @synchronized(ITNonnilLock(([NSArray arrayWithObjects:a, b, nil]))) {\n    }\n")

    def test_unusual_file_names(self):
        body = "    @synchronized(_lock) {\n    }\n"
        for path in ("sources/With Space.m", 'sources/Quo"te.m', "sources/Caf\u00e9 \u00fc.m",
                     "sources/Star*.m", "sources/Tab\tName.m"):
            with self.subTest(path=path):
                self.git("rm", "-q", "-r", "--cached", "--ignore-unmatch", ".")
                out = self.assertReported(body, "_lock", path=path)
                self.assertIn(path + ":4:", out)

    def test_gitlink_named_like_a_source_file_is_skipped(self):
        self.stage("sources/Real.m", method("    @synchronized(self) {\n    }\n"))
        self.git("update-index", "--add", "--cacheinfo",
                 "160000,1234567890123456789012345678901234567890,sources/Sub.m")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)
        rc, out = self.check("--all")
        self.assertEqual(rc, 0, out)
        self.git("commit", "-q", "-m", "with gitlink")
        rc, out = self.check("--range", "HEAD..HEAD")
        self.assertEqual(rc, 0, out)

    def test_unbalanced_expression_is_reported(self):
        self.stage("sources/Foo.m", method("    @synchronized(_lock {\n    }\n"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("cannot read the lock expression", out)

    def test_new_file_every_site_checked(self):
        out = self.assertReported("    @synchronized(_a) {\n    }\n    @synchronized(_b) {\n    }\n"
                                  "    @synchronized(self) {\n    }\n", "_a")
        self.assertIn("@synchronized(_b) locks on something", out)
        self.assertIn("2 @synchronized sites need ITNonnilLock", out)


ORIGINAL = method("    @synchronized(_old) { a(); }\n"
                  "    int keep = 1;\n"
                  "    @synchronized (\n"
                  "        _multi) {\n"
                  "    }\n")


class ChangedLineTests(RepoCase):
    """Only added or changed lines are checked."""

    def setUp(self):
        super().setUp()
        self.write("sources/Old.m", ORIGINAL)
        self.commit_all()

    def test_user_diff_configuration_is_ignored(self):
        config = os.path.join(self.dir, "hostile.gitconfig")
        with open(config, "w") as f:
            f.write("[diff]\n"
                    "\tinterHunkContext = 10\n"
                    "\tcontext = 5\n"
                    "\talgorithm = patience\n"
                    "\trenames = false\n"
                    "\trenameLimit = 1\n"
                    "\tnoprefix = true\n"
                    "\tmnemonicPrefix = true\n"
                    "\trelative = true\n"
                    "\texternal = false\n"
                    "\torderFile = /nonexistent/order\n"
                    "\tignoreSubmodules = all\n"
                    "[diff \"tc\"]\n\ttextconv = false\n"
                    "[color]\n\tui = always\n\tdiff = always\n"
                    "[core]\n\tquotePath = true\n")
        with open(os.path.join(self.dir, ".git", "info", "attributes"), "w") as f:
            f.write("*.m diff=tc\nsources/Bin*.m -diff\n")
        env = {"GIT_CONFIG_GLOBAL": config}
        # Two edits around an untouched site, within interHunkContext.
        edited = ORIGINAL.replace("@implementation Foo", "@implementation Foo2").replace(
            "int keep = 1;", "int keep = 2;")
        self.stage("sources/Old.m", edited)
        rc, out = self.check(env=env)
        self.assertEqual(rc, 0, out)
        # A real addition is still found, in a renamed file and in a file
        # the attributes call binary.
        self.git("mv", "sources/Old.m", "sources/Moved Old.m")
        self.stage("sources/Moved Old.m", edited.replace("{ a(); }", "{ b(); }"))
        self.stage("sources/Binary.m", method("    @synchronized(_bin) {\n    }\n"))
        rc, out = self.check(env=env)
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Moved Old.m:4: @synchronized(_old)", out)
        self.assertIn("sources/Binary.m:4: @synchronized(_bin)", out)
        self.assertNotIn("_multi", out)

    def test_glob_characters_in_a_name_are_literal(self):
        # Read as a glob, the pathspec sources/Glob*.m would also take in
        # GlobX.m's hunks and count Glob*.m's untouched site as added.
        self.write("sources/Glob*.m", ORIGINAL)
        self.commit_all("glob")
        self.stage("sources/Glob*.m", ORIGINAL.replace("int keep = 1;", "int keep = 2;"))
        self.stage("sources/GlobX.m", method("    @synchronized(self) {\n    }\n" * 4))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_unchanged_site_in_changed_file(self):
        self.stage("sources/Old.m", ORIGINAL.replace("int keep = 1;", "int keep = 2;"))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_own_line_edited(self):
        self.stage("sources/Old.m", ORIGINAL.replace("{ a(); }", "{ b(); }"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Old.m:4: @synchronized(_old)", out)
        self.assertNotIn("_multi", out)

    def test_whitespace_only_edit_not_counted(self):
        self.stage("sources/Old.m", ORIGINAL.replace("    @synchronized(_old) { a(); }",
                                                     "        @synchronized (_old)  { a(); }"))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_later_line_of_expression_edited(self):
        self.stage("sources/Old.m", ORIGINAL.replace("        _multi) {", "        _multi2) {"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Old.m:6: @synchronized(_multi2)", out)

    def test_line_after_expression_not_counted(self):
        self.stage("sources/Old.m", ORIGINAL.replace("        _multi) {\n    }\n",
                                                     "        _multi) {\n        c();\n    }\n"))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_moved_line_counts(self):
        moved = ORIGINAL.replace("    @synchronized(_old) { a(); }\n    int keep = 1;\n",
                                 "    int keep = 1;\n    @synchronized(_old) { a(); }\n")
        self.stage("sources/Old.m", moved)
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("@synchronized(_old)", out)

    def test_wrapping_an_existing_site(self):
        self.stage("sources/Old.m", ORIGINAL.replace("@synchronized(_old)",
                                                     "@synchronized(ITNonnilLock(_old))"))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_deletion_only(self):
        self.stage("sources/Old.m", ORIGINAL.replace("    @synchronized(_old) { a(); }\n", ""))
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_rename_without_content_change(self):
        os.makedirs(os.path.join(self.dir, "sources", "New"))
        self.git("mv", "sources/Old.m", "sources/New/Renamed.m")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_rename_between_covered_directories_without_change(self):
        os.makedirs(os.path.join(self.dir, "ModernTests"))
        self.git("mv", "sources/Old.m", "ModernTests/Old.m")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_rename_with_edit_of_site(self):
        self.git("mv", "sources/Old.m", "sources/Renamed.m")
        self.stage("sources/Renamed.m", ORIGINAL.replace("{ a(); }", "{ b(); }"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Renamed.m:4: @synchronized(_old)", out)

    def test_copy_is_a_new_file(self):
        self.stage("sources/Copy.m", ORIGINAL)
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Copy.m:4:", out)
        self.assertIn("sources/Copy.m:6:", out)
        self.assertNotIn("sources/Old.m", out)

    def test_staged_copy_is_read_not_working_tree(self):
        self.stage("sources/Old.m", ORIGINAL.replace("{ a(); }", "{ b(); }"))
        self.write("sources/Old.m", ORIGINAL.replace("@synchronized(_old) { a(); }",
                                                     "@synchronized(ITNonnilLock(_old)) { b(); }"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)


class ModeTests(RepoCase):
    def setUp(self):
        super().setUp()
        self.write("sources/Old.m", ORIGINAL)
        self.write("sources/Fine.m", method("    @synchronized(self) {\n    }\n"))
        self.write("pidinfo/p.m", method("    @synchronized(_x) {\n    }\n"))
        self.commit_all()

    def test_all(self):
        rc, out = self.check("--all", "--summary")
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Old.m:4:", out)
        self.assertIn("sources/Old.m:6:", out)
        self.assertNotIn("pidinfo", out)
        self.assertIn("sites checked: 3", out)
        self.assertRegex(out, r"self\s+1")
        self.assertRegex(out, r"unwrapped\s+2")

    def test_every_mode_works_from_a_subdirectory(self):
        base = self.git("rev-parse", "HEAD").stdout.strip()
        self.stage("sources/sub/B.m", method("    @synchronized(_n) {\n    }\n"))
        sub = os.path.join(self.dir, "sources", "sub")

        def check_in_sub(*args):
            r = subprocess.run([sys.executable, "-B", TOOL] + list(args), cwd=sub,
                               env=git_env(), capture_output=True, text=True)
            return r.returncode, r.stdout + r.stderr

        rc, out = check_in_sub()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/sub/B.m:4:", out)
        rc, out = check_in_sub("--all")
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/sub/B.m:4:", out)
        self.assertIn("sources/Old.m:4:", out)
        self.git("commit", "-q", "-m", "second")
        rc, out = check_in_sub("--range", base + "..HEAD")
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/sub/B.m:4:", out)

    def test_symlink_replaced_by_a_file_is_checked(self):
        os.symlink("Fine.m", os.path.join(self.dir, "sources", "S.m"))
        self.commit_all("link")
        os.unlink(os.path.join(self.dir, "sources", "S.m"))
        self.stage("sources/S.m", method("    @synchronized(_s) {\n    }\n"))
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/S.m:4:", out)

    def test_all_reads_index(self):
        self.stage("sources/Old.m", method("    @synchronized(self) {\n    }\n"))
        rc, out = self.check("--all")
        self.assertEqual(rc, 0, out)

    def test_range(self):
        base = self.git("rev-parse", "HEAD").stdout.strip()
        self.write("sources/Old.m", ORIGINAL.replace("{ a(); }", "{ b(); }"))
        self.write("sources/Added.m", method("    @synchronized([Foo class]) {\n    }\n"))
        self.commit_all("second")
        rc, out = self.check("--range", base + "..HEAD")
        self.assertEqual(rc, 1, out)
        self.assertIn("sources/Old.m:4:", out)
        self.assertNotIn("sources/Old.m:6:", out)
        rc, out = self.check("--range", base + "..")
        self.assertEqual(rc, 1, out)
        rc, out = self.check("--range", "HEAD..HEAD")
        self.assertEqual(rc, 0, out)
        # Reads files at the tip, not in the working tree.
        self.write("sources/Old.m", ORIGINAL.replace("@synchronized(_old) { a(); }",
                                                     "@synchronized(ITNonnilLock(_old)) { b(); }"))
        rc, out = self.check("--range", base + "..HEAD")
        self.assertEqual(rc, 1, out)

    def test_bad_range_is_an_error(self):
        for rng in ("nosuchref..HEAD", "HEAD", "HEAD...HEAD"):
            with self.subTest(rng=rng):
                rc, out = self.check("--range", rng)
                self.assertEqual(rc, 2, out)
                self.assertIn("error", out)

    def test_git_failure_outside_a_repository(self):
        outside = tempfile.mkdtemp(prefix="nonnil-lock-norepo-")
        self.addCleanup(shutil.rmtree, outside, True)
        for args in ([], ["--all"]):
            with self.subTest(args=args):
                r = subprocess.run([sys.executable, "-B", TOOL] + args, cwd=outside,
                                   env=git_env({"GIT_CEILING_DIRECTORIES": os.path.dirname(outside)}),
                                   capture_output=True, text=True)
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                self.assertIn("--no-verify", r.stderr)

    def test_unreadable_blob_is_an_error(self):
        self.stage("sources/Old.m", ORIGINAL.replace("{ a(); }", "{ b(); }"))
        sha = self.git("rev-parse", ":sources/Old.m").stdout.strip()
        os.remove(os.path.join(self.dir, ".git", "objects", sha[:2], sha[2:]))
        rc, out = self.check()
        self.assertEqual(rc, 2, out)
        rc, out = self.check("--all")
        self.assertEqual(rc, 2, out)


STUB_CATALOG_CHECK = """\
import os, sys
print("STUB CATALOG CHECK RAN", file=sys.stderr)
sys.exit(int(os.environ.get("STUB_CATALOG_EXIT", "0")))
"""


class HookTests(RepoCase):
    def setUp(self):
        super().setUp()
        hooks = os.path.join(self.dir, "hooks-copy")
        os.makedirs(hooks)
        shutil.copy2(HOOK, os.path.join(hooks, "pre-commit"))
        os.chmod(os.path.join(hooks, "pre-commit"),
                 os.stat(HOOK).st_mode | stat.S_IXUSR)
        os.makedirs(os.path.join(self.dir, "tools"))
        shutil.copy2(TOOL, os.path.join(self.dir, "tools", "check_nonnil_locks.py"))
        self.write("tools/check_untranslated_strings.py", STUB_CATALOG_CHECK)
        self.write("sources/Old.m", ORIGINAL)
        self.write("xcstrings/Localizable.xcstrings", "{}\n")
        self.commit_all()
        self.git("config", "core.hooksPath", "hooks-copy")

    def commit(self, env=None, args=(), split=False):
        r = subprocess.run(["git", "commit", "-q", "-m", "change"] + list(args), cwd=self.dir,
                           env=git_env(env), capture_output=True, text=True)
        if split:
            return r.returncode, r.stdout, r.stderr
        return r.returncode, r.stdout + r.stderr

    def head(self):
        return self.git("rev-parse", "HEAD").stdout.strip()

    def test_unwrapped_lock_rejected(self):
        before = self.head()
        self.stage("sources/Deep/Er/New.m", method("    @synchronized(_lock) {\n    }\n"))
        rc, out = self.commit()
        self.assertNotEqual(rc, 0, out)
        self.assertIn("sources/Deep/Er/New.m:4: @synchronized(_lock)", out)
        self.assertIn("Fix: @synchronized(ITNonnilLock(_lock))", out)
        self.assertNotIn("STUB CATALOG CHECK RAN", out)
        self.assertEqual(self.head(), before)

    def test_clean_commits_succeed(self):
        self.stage("README.txt", "no objective-c here\n")
        rc, out = self.commit()
        self.assertEqual(rc, 0, out)
        self.stage("sources/New.m", method("    @synchronized(ITNonnilLock(_lock)) {\n    }\n"))
        rc, out = self.commit()
        self.assertEqual(rc, 0, out)
        self.stage("sources/Old.m", ORIGINAL.replace("int keep = 1;", "int keep = 2;"))
        rc, out = self.commit()
        self.assertEqual(rc, 0, out)

    def test_catalog_check_still_runs(self):
        self.stage("xcstrings/Localizable.xcstrings", "{\"a\": 1}\n")
        rc, out = self.commit()
        self.assertEqual(rc, 0, out)
        self.assertIn("STUB CATALOG CHECK RAN", out)
        self.stage("xcstrings/Localizable.xcstrings", "{\"a\": 2}\n")
        rc, out = self.commit({"STUB_CATALOG_EXIT": "1"})
        self.assertNotEqual(rc, 0, out)
        self.assertIn("STUB CATALOG CHECK RAN", out)

    def test_catalog_and_lock_checks_both_run_when_both_staged(self):
        before = self.head()
        self.stage("xcstrings/Localizable.xcstrings", "{\"a\": 1}\n")
        self.stage("sources/New.m", method("    @synchronized(_lock) {\n    }\n"))
        rc, out = self.commit({"STUB_CATALOG_EXIT": "1"})
        self.assertNotEqual(rc, 0, out)
        self.assertIn("STUB CATALOG CHECK RAN", out)
        self.assertIn("Fix: @synchronized(ITNonnilLock(_lock))", out)
        self.assertEqual(self.head(), before)

    def test_temporary_index_commits_are_checked(self):
        bad = ORIGINAL.replace("int keep = 1;", "int keep = 1;\n    @synchronized(_tmp) {\n    }")
        self.write("sources/Old.m", bad)  # working tree only
        before = self.head()
        for args in (["-a"], ["sources/Old.m"], ["--only", "sources/Old.m"]):
            with self.subTest(args=args):
                rc, out = self.commit(args=args)
                self.assertNotEqual(rc, 0, out)
                self.assertIn("@synchronized(_tmp)", out)
                self.assertEqual(self.head(), before)

    def test_only_commit_ignores_bad_file_staged_in_default_index(self):
        self.stage("sources/Bad.m", method("    @synchronized(_bad) {\n    }\n"))
        self.write("sources/Old.m", ORIGINAL.replace("int keep = 1;", "int keep = 4;"))
        before = self.head()
        rc, out = self.commit(args=["--only", "sources/Old.m"])
        self.assertEqual(rc, 0, out)
        self.assertNotEqual(self.head(), before)
        self.assertEqual(self.git("diff", "--cached", "--name-only").stdout.split(), ["sources/Bad.m"])

    def test_many_files_with_synchronized_pass_quietly(self):
        for i in range(20):
            self.write("sources/Many%02d.m" % i, ORIGINAL)
        self.git("add", "-A")
        self.git("commit", "-q", "--no-verify", "-m", "many")
        for i in range(20):
            self.stage("sources/Many%02d.m" % i, ORIGINAL.replace("int keep = 1;", "int keep = 5;"))
        rc, out, err = self.commit(split=True)
        self.assertEqual(rc, 0, out + err)
        self.assertEqual(err, "")

    def test_silent_checker_failure_is_not_silent(self):
        self.write("tools/check_nonnil_locks.py", "import sys\nsys.exit(1)\n")
        self.git("add", "tools/check_nonnil_locks.py")
        self.stage("sources/New.m", method("    @synchronized(self) {\n    }\n"))
        before = self.head()
        rc, out = self.commit()
        self.assertNotEqual(rc, 0, out)
        self.assertIn("pre-commit: the @synchronized lock check", out)
        self.assertIn("git commit --no-verify", out)
        self.assertEqual(self.head(), before)

    def test_checker_error_blocks_with_bypass_message(self):
        self.write("tools/check_nonnil_locks.py", "import sys\nsys.exit(2)\n")
        self.git("add", "tools/check_nonnil_locks.py")
        self.stage("sources/New.m", method("    @synchronized(self) {\n    }\n"))
        before = self.head()
        rc, out = self.commit()
        self.assertNotEqual(rc, 0, out)
        self.assertIn("checked nothing", out)
        self.assertIn("git commit --no-verify", out)
        self.assertEqual(self.head(), before)

    def test_fast_path_skips_python_without_synchronized(self):
        # A checker that always fails shows whether it was started.
        self.write("tools/check_nonnil_locks.py", "import sys\nprint('CHECKER RAN')\nsys.exit(1)\n")
        self.git("add", "tools/check_nonnil_locks.py")
        self.stage("sources/Plain.m", "@implementation P\n@end\n")
        self.stage("pidinfo/p.m", method("    @synchronized(_x) {\n    }\n"))
        rc, out = self.commit()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("CHECKER RAN", out)
        # A file whose staged copy has @synchronized anywhere starts it.
        self.stage("sources/Old.m", ORIGINAL.replace("int keep = 1;", "int keep = 3;"))
        rc, out = self.commit()
        self.assertNotEqual(rc, 0, out)
        self.assertIn("CHECKER RAN", out)

    def test_hook_is_posix_sh(self):
        with open(HOOK) as f:
            self.assertEqual(f.readline().strip(), "#!/bin/sh")
        r = subprocess.run(["sh", "-n", HOOK], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


class RealTreeTests(unittest.TestCase):
    """HELPER_SHARED_FILES must match iTerm2.xcodeproj."""

    # Targets that compile DebugLogging.m or link the code that does.
    WITH_DEBUG_LOGGING = {"iTerm2SharedARC", "iTerm2Shared", "iTerm2",
                          "iTerm2ForApplescriptTesting", "ModernTests", "PerformanceTests",
                          "iTermSwiftPackages"}
    # Helper targets that do not.
    WITHOUT_DEBUG_LOGGING = {"pidinfo", "iTerm2SandboxedWorker", "iTermServer", "ShellLauncher",
                             "it2core", "iTerm2ImportStatus", "SSKeychain"}

    def project_targets(self):
        with open(os.path.join(REPO, "iTerm2.xcodeproj", "project.pbxproj")) as f:
            text = f.read()
        objs = {m.group(1): m.group(2) for m in re.finditer(
            r'^\t\t([0-9A-F]{24}) (?:/\*.*?\*/ )?= \{(.*?)\};$', text, re.S | re.M)}

        def attr(body, key):
            m = re.search(r'(?:^|[\s;{])' + key + r' = ("(?:[^"\\]|\\.)*"|[^;]+);', body)
            if not m:
                return None
            v = m.group(1)
            return v[1:-1] if v.startswith('"') else v

        def ids(body, key):
            m = re.search(key + r' = \((.*?)\);', body, re.S)
            return re.findall(r'([0-9A-F]{24})', m.group(1)) if m else []

        parent = {}
        for oid, body in objs.items():
            if attr(body, "isa") in ("PBXGroup", "PBXVariantGroup"):
                for child in ids(body, "children"):
                    parent[child] = oid

        def full_path(oid):
            parts = []
            while True:
                body = objs[oid]
                if attr(body, "path"):
                    parts.append(attr(body, "path"))
                if attr(body, "sourceTree") != "<group>" or oid not in parent:
                    return os.path.normpath("/".join(reversed(parts)))
                oid = parent[oid]

        targets = {}
        for oid, body in objs.items():
            if attr(body, "isa") != "PBXNativeTarget":
                continue
            files = set()
            for phase in ids(body, "buildPhases"):
                if attr(objs.get(phase, ""), "isa") != "PBXSourcesBuildPhase":
                    continue
                for build_file in ids(objs[phase], "files"):
                    ref = attr(objs[build_file], "fileRef")
                    if ref:
                        files.add(full_path(ref.split()[0]))
            targets[attr(body, "name")] = files
        return targets

    def test_helper_shared_files_match_project(self):
        targets = self.project_targets()
        self.assertEqual(set(targets), self.WITH_DEBUG_LOGGING | self.WITHOUT_DEBUG_LOGGING,
                         "a target was added or removed: decide whether it links DebugLogging.m")
        self.assertIn("sources/Logging/DebugLogging.m", targets["iTerm2SharedARC"])
        for name in self.WITHOUT_DEBUG_LOGGING:
            self.assertNotIn("sources/Logging/DebugLogging.m", targets[name], name)
        shared = set()
        for name in self.WITHOUT_DEBUG_LOGGING:
            shared |= {p for p in targets[name]
                       if p.startswith(checker.COVERED_PREFIXES) and p.endswith(checker.OBJC_SUFFIXES)}
        self.assertEqual(shared, set(checker.HELPER_SHARED_FILES))


if __name__ == "__main__":
    unittest.main()
