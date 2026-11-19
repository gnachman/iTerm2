#!/usr/bin/env python3
"""Tests for the code database: the extractor, the compile database, the
driver, the watchdog, the capture script and the query helper.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_*.py'

No xcodebuild: the extractor is built with extractor/build.sh (upstream LLVM
and the SDK only) and run on the fixtures with plain clang command lines, and
the capture script is run against a stub xcodebuild in a scratch tree.
Expected rows are written out by hand. Set CODEDB_TEST_EXTRACTOR to use a
prebuilt extractor instead of tmp/codedb/test-bin/extract_sends.
"""

import io
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.path.dirname(HERE)
sys.path.insert(0, CODEDB_DIR)

import codedb  # noqa: E402

FIXTURES = os.path.join(HERE, 'fixtures')
REPO = codedb.REPO_ROOT
EXTRACTOR = os.environ.get('CODEDB_TEST_EXTRACTOR') or os.path.join(REPO, 'tmp', 'codedb', 'test-bin', 'extract_sends')
GUARD = os.path.join(CODEDB_DIR, 'guard.sh')
CAPTURE = os.path.join(CODEDB_DIR, 'capture_compile_commands.sh')
TEMP_DIRS = []


def setUpModule():
    if not os.environ.get('CODEDB_TEST_EXTRACTOR'):
        codedb.ensure_extractor(codedb.Paths(REPO, extractor=EXTRACTOR), log=lambda m: None)


def tearDownModule():
    for d in TEMP_DIRS:
        shutil.rmtree(d, ignore_errors=True)


def make_temp(prefix='codedb-test-'):
    d = os.path.realpath(tempfile.mkdtemp(prefix=prefix))
    TEMP_DIRS.append(d)
    return d


def make_root():
    d = make_temp()
    root = os.path.join(d, 'repo')
    shutil.copytree(FIXTURES, root)
    shutil.copytree(os.path.join(HERE, 'outside_fixture'), os.path.join(d, 'outside'))
    return root


def clang_args(root, main, extra=()):
    lang = 'objective-c++' if main.endswith('.mm') else 'c' if main.endswith('.c') else 'objective-c'
    outside = os.path.join(os.path.dirname(root), 'outside')
    return ['-x', lang, '--target=arm64-apple-macos13'] + list(extra) + ['-I', root, '-I', os.path.join(root, 'sources'),
                                                                          '-I', outside, os.path.join(root, main)]


def extract(root, main, db, target='T', extra=()):
    args = clang_args(root, main, extra)
    r = subprocess.run([EXTRACTOR, '--db', db, '--root', root, '--target', target,
                        '--main', os.path.join(root, main)] + scope_args() + ['--'] + args,
                       capture_output=True, text=True)
    return r.returncode, r.stderr, args


def scope_args():
    out = []
    for d in codedb.MIGRATION_SCOPE_DIRS:
        out += ['--migration-scope', d]
    return out


SEND_COLUMNS = ('selector, receiver_kind, receiver_type, target_usr, file, line, col, enclosing_usr, '
                'enclosing_name, in_block, implicit_accessor, macro_name, macro_file, macro_line, '
                'macro_role, expansion_line, expansion_col')


def send_rows(db, where='1'):
    con = sqlite3.connect(db)
    rows = con.execute('SELECT %s FROM send WHERE %s ORDER BY file, line, col, selector' % (SEND_COLUMNS, where)).fetchall()
    con.close()
    return rows


RUN_USR = 'c:objc(cs)Widget(im)run'
RUN = '-[Widget run]'
NO_MACRO = (None, None, None, None, None, None)


def usr(sel, kind='im'):
    return 'c:objc(cs)Widget(%s)%s' % (kind, sel)


# Every send in sources/sends.m and the header it includes, by hand from the fixture.
EXPECTED_SENDS = sorted([
    ('helperSend', 'instance', 'Widget *', usr('helperSend'), 'sources/helpers.h', 4, 8,
     'c:helpers.h@F@Helper', 'Helper', 0, 0) + NO_MACRO,
    ('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/sends.m', 19, 11, RUN_USR, RUN, 0, 0) + NO_MACRO,
    ('doThing', 'instance', 'id', usr('doThing'), 'sources/sends.m', 21, 15, RUN_USR, RUN, 0, 0) + NO_MACRO,
    ('make', 'class', 'Widget', usr('make', 'cm'), 'sources/sends.m', 22, 13, RUN_USR, RUN, 0, 0) + NO_MACRO,
    ('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/sends.m', 23, 32, RUN_USR, RUN, 1, 0) + NO_MACRO,
    # BLOCK(makeThing): the selector is the macro's argument, written at 25:11;
    # the receiver `self` and the brackets come from the body.
    ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/sends.m', 25, 11, RUN_USR, RUN, 1, 0,
     'BLOCK', 'sources/sends.m', 3, 'argument', 25, 5),
    # The `copy` send is in BLOCK's body: recorded where BLOCK is used.
    ('copy', 'instance', 'id (^)(void)', usr('copy'), 'sources/sends.m', 25, 5, RUN_USR, RUN, 0, 0,
     'BLOCK', 'sources/sends.m', 3, 'body', 25, 5),
    ('load_alpha', 'instance', 'Widget *', usr('load_alpha'), 'sources/sends.m', 26, 5, RUN_USR, RUN, 0, 0,
     'LOAD', 'sources/sends.m', 4, 'pasted', 26, 5),
    ('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/sends.m', 27, 11, RUN_USR, RUN, 0, 0,
     'TWICE', 'sources/sends.m', 5, 'argument', 27, 5),
    ('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/sends.m', 27, 11, RUN_USR, RUN, 0, 0,
     'TWICE', 'sources/sends.m', 5, 'argument', 27, 5),
    ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/sends.m', 28, 19, RUN_USR, RUN, 0, 0) + NO_MACRO,
    ('title', 'instance', 'Widget *', usr('title'), 'sources/sends.m', 28, 30, RUN_USR, RUN, 0, 1) + NO_MACRO,
    ('setTitle:', 'instance', 'Widget *', usr('setTitle:'), 'sources/sends.m', 29, 10, RUN_USR, RUN, 0, 1) + NO_MACRO,
    ('objectAtIndexedSubscript:', 'instance', 'Widget *', usr('objectAtIndexedSubscript:'), 'sources/sends.m', 30, 11,
     RUN_USR, RUN, 0, 2) + NO_MACRO,
], key=lambda r: (r[4], r[5], r[6], r[0]))

MACROS_USR = 'c:@F@Macros'
# Every send in sources/macros.m, by hand from the fixture.
EXPECTED_MACRO_SENDS = [
    # LOG(1,\n [w makeThing], 2): the send is written in the argument, on the
    # line after the macro's name.
    ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/macros.m', 12, 12, MACROS_USR, 'Macros', 0, 0,
     'LOG', 'sources/macros.m', 4, 'argument', 11, 5),
    # OUTER(doThing) passes its argument to INNER: still an argument, written
    # at 13:11; the outermost macro is OUTER.
    ('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/macros.m', 13, 11, MACROS_USR, 'Macros', 0, 0,
     'OUTER', 'sources/macros.m', 5, 'argument', 13, 5),
    # MAKE()'s body inside LOG's argument: recorded where MAKE is written
    # (15:9); the outermost macro, LOG, is used at 14:5.
    ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/macros.m', 15, 9, MACROS_USR, 'Macros', 0, 0,
     'LOG', 'sources/macros.m', 4, 'body', 14, 5),
    # The selector is made by token pasting: recorded at the macro's use.
    ('load_alpha', 'instance', 'Widget *', usr('load_alpha'), 'sources/macros.m', 16, 8, MACROS_USR, 'Macros', 0, 0,
     'CAT', 'sources/macros.m', 8, 'pasted', 16, 8),
]


def sha(path):
    return codedb.sha256_file(path)


def read_text(path):
    with open(path) as f:
        return f.read()


def write_executable(path, text):
    with open(path, 'w') as f:
        f.write(text)
    os.chmod(path, 0o755)
    return path


_REAL_COMPILER = []


def real_compiler():
    """The compiler version the real extractor reports, for example
    'Homebrew clang version 22.1.8'."""
    if not _REAL_COMPILER:
        out = subprocess.run([EXTRACTOR, '--version'], capture_output=True, text=True, check=True).stdout
        _REAL_COMPILER.append(out.split(None, 2)[2].strip())
    return _REAL_COMPILER[0]


def fake_extractor(path, body):
    """A stand-in extractor whose --version reports the real source digest and
    compiler, so the driver does not try to rebuild it and units extracted by
    the real one stay current."""
    return write_executable(path, '#!/bin/sh\nif [ "$1" = --version ]; then echo "extract_sends %s %s"; exit 0; fi\n%s\n'
                            % (codedb.extractor_source_digest(), real_compiler(), body))


def processes_matching(marker):
    out = subprocess.run(['pgrep', '-f', marker], capture_output=True, text=True).stdout
    return [int(p) for p in out.split()]


def wait_until(predicate, timeout=60.0):
    """Poll a condition until it holds or the deadline passes. Used to wait for
    a process to appear or disappear, never to order work."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def fake_sdk(test, path, version):
    """Make codedb see (path, version) as the SDK xcrun reports, for the
    rest of the test."""
    real = codedb.current_sdk
    codedb.current_sdk = lambda: (path, version)
    test.addCleanup(setattr, codedb, 'current_sdk', real)


def kill_matching(marker):
    for p in processes_matching(marker):
        try:
            os.kill(p, signal.SIGKILL)
        except ProcessLookupError:
            pass


class ExtractorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db = os.path.join(os.path.dirname(cls.root), 'x.sqlite')
        cls.status, cls.stderr, cls.args = extract(cls.root, 'sources/sends.m', cls.db)

    def test_clean_status(self):
        self.assertEqual(self.status, 0, self.stderr)

    def test_every_send_exactly(self):
        self.assertEqual(send_rows(self.db), EXPECTED_SENDS)

    def test_plain_send(self):
        self.assertEqual(send_rows(self.db, 'line=19'), [EXPECTED_SENDS[1]])

    def test_send_to_id(self):
        self.assertEqual(send_rows(self.db, "receiver_type='id'"),
                         [('doThing', 'instance', 'id', usr('doThing'), 'sources/sends.m', 21, 15, RUN_USR, RUN,
                           0, 0) + NO_MACRO])

    def test_class_method_send(self):
        self.assertEqual(send_rows(self.db, "receiver_kind='class'"),
                         [('make', 'class', 'Widget', usr('make', 'cm'), 'sources/sends.m', 22, 13, RUN_USR, RUN,
                           0, 0) + NO_MACRO])

    def test_send_in_block(self):
        self.assertEqual([(r[0], r[5], r[6]) for r in send_rows(self.db, 'in_block=1')],
                         [('doThing', 23, 32), ('makeThing', 25, 11)])

    def test_macro_using_parameter_as_selector(self):
        # The selector's first token decides the role: `makeThing` is spelled
        # in BLOCK's argument, although `self` and the brackets are its body.
        self.assertEqual(send_rows(self.db, "macro_name='BLOCK'"),
                         [('copy', 'instance', 'id (^)(void)', usr('copy'), 'sources/sends.m', 25, 5, RUN_USR, RUN,
                           0, 0, 'BLOCK', 'sources/sends.m', 3, 'body', 25, 5),
                          ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/sends.m', 25, 11, RUN_USR, RUN,
                           1, 0, 'BLOCK', 'sources/sends.m', 3, 'argument', 25, 5)])

    def test_token_pasted_selector(self):
        self.assertEqual(send_rows(self.db, "selector='load_alpha'"),
                         [('load_alpha', 'instance', 'Widget *', usr('load_alpha'), 'sources/sends.m', 26, 5, RUN_USR, RUN,
                           0, 0, 'LOAD', 'sources/sends.m', 4, 'pasted', 26, 5)])

    def test_send_in_included_header(self):
        self.assertEqual(send_rows(self.db, "file='sources/helpers.h'"), [EXPECTED_SENDS[0]])

    def test_no_duplicates(self):
        # The base of `[self makeThing].title` is visited twice by the AST
        # visitor; it must be recorded once. TWICE really sends twice.
        con = sqlite3.connect(self.db)
        dups = con.execute('SELECT selector, line, count(*) FROM send GROUP BY %s HAVING count(*) > 1'
                           % SEND_COLUMNS).fetchall()
        con.close()
        self.assertEqual(dups, [('doThing', 27, 2)])
        self.assertEqual(len(send_rows(self.db, 'line=28 AND selector=\'makeThing\'')), 1)

    def test_dot_syntax_and_subscript(self):
        self.assertEqual([(r[0], r[5], r[6], r[10]) for r in send_rows(self.db, 'implicit_accessor > 0')],
                         [('title', 28, 30, 1), ('setTitle:', 29, 10, 1), ('objectAtIndexedSubscript:', 30, 11, 2)])

    def test_tu_row(self):
        con = sqlite3.connect(self.db)
        row = con.execute('SELECT target, main_file, cmd_digest, diagnostics_errors, clang_version, '
                          'extractor_version, arguments, sdk_path, configuration FROM tu').fetchall()
        user_version = con.execute('PRAGMA user_version').fetchone()[0]
        con.close()
        self.assertEqual(len(row), 1)
        target, main, digest, errors, version, ev, arguments, sdk, config = row[0]
        self.assertEqual((target, main, errors, sdk, config), ('T', 'sources/sends.m', 0, None, None))
        self.assertEqual(ev, codedb.extractor_source_digest())
        self.assertEqual(user_version, codedb.SCHEMA_VERSION)
        self.assertEqual(digest, codedb.command_digest(self.args))
        self.assertEqual(json.loads(arguments), self.args)
        self.assertTrue(version.startswith('Homebrew clang version 22.'), version)

    def test_tu_inputs(self):
        con = sqlite3.connect(self.db)
        rows = sorted(con.execute('SELECT path, digest FROM tu_input').fetchall())
        con.close()
        self.assertEqual(rows, [('sources/helpers.h', sha(os.path.join(self.root, 'sources/helpers.h'))),
                                ('sources/sends.m', sha(os.path.join(self.root, 'sources/sends.m'))),
                                ('sources/widget.h', sha(os.path.join(self.root, 'sources/widget.h')))])

    def test_reextraction_replaces_rows(self):
        db = os.path.join(os.path.dirname(self.root), 'again.sqlite')
        extract(self.root, 'sources/sends.m', db)
        extract(self.root, 'sources/sends.m', db)
        con = sqlite3.connect(db)
        counts = con.execute('SELECT (SELECT count(*) FROM tu), (SELECT count(*) FROM send), '
                             '(SELECT count(*) FROM tu_input)').fetchone()
        con.close()
        self.assertEqual(counts, (1, len(EXPECTED_SENDS), 3))


class MacroRoleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.db = os.path.join(os.path.dirname(cls.root), 'm.sqlite')
        cls.status, cls.stderr, _ = extract(cls.root, 'sources/macros.m', cls.db)

    def test_clean_status(self):
        self.assertEqual(self.status, 0, self.stderr)

    def test_every_send_exactly(self):
        self.assertEqual(send_rows(self.db), EXPECTED_MACRO_SENDS)

    def test_argument_on_a_later_line_than_the_macro_name(self):
        self.assertEqual(send_rows(self.db, 'line=12'), [EXPECTED_MACRO_SENDS[0]])

    def test_nested_macro_argument(self):
        self.assertEqual(send_rows(self.db, "macro_name='OUTER'"), [EXPECTED_MACRO_SENDS[1]])

    def test_body_inside_another_macros_argument(self):
        self.assertEqual(send_rows(self.db, "macro_role='body'"), [EXPECTED_MACRO_SENDS[2]])

    def test_pasted_selector(self):
        self.assertEqual(send_rows(self.db, "macro_role='pasted'"), [EXPECTED_MACRO_SENDS[3]])


class MoreShapesTest(unittest.TestCase):
    def test_lambda_in_objective_cxx(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'l.sqlite')
        status, stderr, _ = extract(root, 'sources/lambda.mm', db)
        self.assertEqual(status, 0, stderr)
        # The lambda's call operator is not an enclosing declaration; the
        # function that contains the lambda is.
        self.assertEqual(send_rows(db, "selector='doThing'"),
                         [('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/lambda.mm', 4, 25,
                           'c:@F@WithLambda#*$objc(cs)Widget#', 'WithLambda', 0, 0) + NO_MACRO])
        # A method of a class declared inside a block is its own enclosing
        # declaration and is not itself in a block.
        self.assertEqual([(r[0], r[5], r[6], r[8], r[9]) for r in send_rows(db, "selector='makeThing'")],
                         [('makeThing', 8, 67, 'Local(Widget *)::L::f', 0)])

    def test_file_scope_block_and_outside_header(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'g.sqlite')
        status, stderr, _ = extract(root, 'sources/globals.m', db)
        self.assertEqual(status, 0, stderr)
        # Outside.h's send is not recorded: the header is outside the root.
        self.assertEqual(send_rows(db), [('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/globals.m', 5, 43,
                                          'c:globals.m@gBlock', 'gBlock', 1, 0) + NO_MACRO])
        outside = os.path.join(os.path.dirname(root), 'outside', 'outside.h')
        con = sqlite3.connect(db)
        paths = sorted(r[0] for r in con.execute('SELECT path FROM tu_input'))
        con.close()
        self.assertEqual(paths, sorted(['sources/globals.m', 'sources/widget.h', outside]))


class UnevaluatedOperandTest(unittest.TestCase):
    """A send that appears only in an unevaluated operand (typeof, sizeof,
    alignof, @encode, decltype, noexcept) is not a send, and MAX-style macros
    that repeat their argument inside __typeof__ record it once."""

    def test_objective_c(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'u.sqlite')
        status, stderr, _ = extract(root, 'sources/unevaluated.m', db)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(send_rows(db), [
            ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/unevaluated.m', 5, 38,
             'c:@F@Unevaluated', 'Unevaluated', 0, 0) + NO_MACRO,
            ('title', 'instance', 'Widget *', usr('title'), 'sources/unevaluated.m', 10, 21,
             'c:@F@Unevaluated', 'Unevaluated', 0, 0, 'MAXW', 'sources/unevaluated.m', 3, 'argument', 10, 13),
            # An operand of variably modified type is evaluated: the size of
            # a variable-length array type in sizeof, in a typeof of a
            # variably modified expression, and in a declaration inside a
            # statement expression inside typeof. Each once.
            ('other', 'instance', 'Widget *', usr('other'), 'sources/unevaluated.m', 12, 25,
             'c:@F@Unevaluated', 'Unevaluated', 0, 0) + NO_MACRO,
            ('vm', 'instance', 'Widget *', usr('vm'), 'sources/unevaluated.m', 13, 28,
             'c:@F@Unevaluated', 'Unevaluated', 0, 0) + NO_MACRO,
            ('gen', 'instance', 'Widget *', usr('gen'), 'sources/unevaluated.m', 14, 31,
             'c:@F@Unevaluated', 'Unevaluated', 0, 0) + NO_MACRO,
        ])

    def test_objective_cxx(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'ux.sqlite')
        status, stderr, _ = extract(root, 'sources/unevaluated_cxx.mm', db)
        self.assertEqual(status, 0, stderr)
        self.assertEqual(send_rows(db), [
            ('makeThing', 'instance', 'Widget *', usr('makeThing'), 'sources/unevaluated_cxx.mm', 4, 36,
             'c:@F@UnevaluatedCXX#*$objc(cs)Widget#', 'UnevaluatedCXX', 0, 0) + NO_MACRO,
        ])


SCOPE_HEADER = '#import "widget.h"\nstatic inline void %s(Widget *w) { [w doThing]; }\n'


def scope_rows(db):
    con = sqlite3.connect(db)
    rows = con.execute('SELECT file, line, col, selector, enclosing_name, in_migration_scope FROM send '
                       'ORDER BY file, line, col').fetchall()
    con.close()
    return rows


class ScopeTest(unittest.TestCase):
    """Every evaluated send written in a file inside the repository is
    recorded, wherever it is (submodules/, all of ThirdParty/, other
    directories); in_migration_scope is 1 only under the directories of
    codedb.MIGRATION_SCOPE_DIRS (sources/, ThirdParty/PSMTabBarControl/,
    SignedArchive/ and others; not ModernTests/, which is test code). Sends
    in files outside
    the repository (the SDK, the compiler, Homebrew) are not recorded."""

    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        for path, name in (('ThirdParty/Other/other.h', 'TP'), ('ThirdParty/PSMTabBarControl/psm.h', 'PS'),
                           ('submodules/sub/sub.h', 'SB'), ('ModernTests/mt.h', 'MT'), ('misc/misc.h', 'MS'),
                           ('SignedArchive/SignedArchive/sig.h', 'SG')):
            os.makedirs(os.path.dirname(os.path.join(cls.root, path)), exist_ok=True)
            with open(os.path.join(cls.root, path), 'w') as f:
                f.write(SCOPE_HEADER % name)
        with open(os.path.join(cls.root, 'sources', 'scope.m'), 'w') as f:
            f.write('// Fixture: one send in each kind of place.\n#import "widget.h"\n'
                    '#import "../ThirdParty/Other/other.h"\n#import "../ThirdParty/PSMTabBarControl/psm.h"\n'
                    '#import "../submodules/sub/sub.h"\n#import "../ModernTests/mt.h"\n#import "../misc/misc.h"\n'
                    'void Scope(Widget *w) { TP(w); PS(w); SB(w); MT(w); MS(w); [w makeThing]; }\n'
                    '#import "../SignedArchive/SignedArchive/sig.h"\n#import "outside.h"\n'
                    'void Scope2(Widget *w) { SG(w); Outside(w); }\n')
        with open(os.path.join(cls.root, 'misc', 'main.m'), 'w') as f:
            f.write('#import "misc.h"\nvoid Main(Widget *w) { MS(w); [w makeThing]; }\n')

    def test_sends_anywhere_in_the_repository(self):
        db = os.path.join(os.path.dirname(self.root), 's.sqlite')
        status, stderr, _ = extract(self.root, 'sources/scope.m', db)
        self.assertEqual(status, 0, stderr)
        # outside.h is outside the repository root: its send is not recorded.
        self.assertEqual(scope_rows(db), [
            ('ModernTests/mt.h', 2, 39, 'doThing', 'MT', 0),
            ('SignedArchive/SignedArchive/sig.h', 2, 39, 'doThing', 'SG', 1),
            ('ThirdParty/Other/other.h', 2, 39, 'doThing', 'TP', 0),
            ('ThirdParty/PSMTabBarControl/psm.h', 2, 39, 'doThing', 'PS', 1),
            ('misc/misc.h', 2, 39, 'doThing', 'MS', 0),
            ('sources/scope.m', 8, 63, 'makeThing', 'Scope', 1),
            ('submodules/sub/sub.h', 2, 39, 'doThing', 'SB', 0),
        ])

    def test_main_file_outside_the_migration_scope_and_its_headers(self):
        db = os.path.join(os.path.dirname(self.root), 'sm.sqlite')
        status, stderr, _ = extract(self.root, 'misc/main.m', db, target='pidinfo')
        self.assertEqual(status, 0, stderr)
        self.assertEqual(scope_rows(db), [
            ('misc/main.m', 2, 34, 'makeThing', 'Main', 0),
            ('misc/misc.h', 2, 39, 'doThing', 'MS', 0),
        ])


class CanonicalPathTest(unittest.TestCase):
    """Each input is stored under its real path: through symlinked
    directories, and through a VFS overlay's virtual paths."""

    def test_module_map_through_symlinked_directory(self):
        root = make_root()
        os.mkdir(os.path.join(root, 'realdir'))
        with open(os.path.join(root, 'realdir', 'm.h'), 'w') as f:
            f.write('#import "sources/widget.h"\nstatic inline void MH(Widget *w) { [w doThing]; }\n')
        with open(os.path.join(root, 'realdir', 'module.modulemap'), 'w') as f:
            f.write('module M { header "m.h" export * }\n')
        os.symlink('realdir', os.path.join(root, 'linkdir'))
        with open(os.path.join(root, 'sources/usemodule.m'), 'w') as f:
            f.write('@import M;\nvoid F(Widget *w) { [w doThing]; }\n')
        cache = make_temp('codedb-mc-')
        db = os.path.join(os.path.dirname(root), 'c.sqlite')
        status, stderr, _ = extract(root, 'sources/usemodule.m', db,
                                    extra=['-fmodules', '-fmodules-cache-path=' + cache,
                                           '-I', os.path.join(root, 'linkdir')])
        self.assertEqual(status, 0, stderr)
        con = sqlite3.connect(db)
        paths = sorted(r[0] for r in con.execute('SELECT path FROM tu_input'))
        con.close()
        self.assertIn('realdir/module.modulemap', paths)
        self.assertEqual([p for p in paths if 'linkdir' in p], [])

    def test_headers_of_an_imported_module_are_inputs(self):
        # A module's headers are read from its module file, not from the
        # unit's own source locations; a project module's headers are inputs
        # all the same, and editing one makes the unit stale. Headers of
        # modules in the SDK are not recorded (the SDK path and version
        # stand for them).
        root = make_root()
        for d, name, text in (('realdir', 'm.h', '#import "widget.h"\nstatic inline void MH(Widget *w) { [w doThing]; }\n'),
                              ('fakesdk', 'f.h', 'static inline int FH(void) { return 1; }\n')):
            os.mkdir(os.path.join(root, d))
            with open(os.path.join(root, d, name), 'w') as f:
                f.write(text)
            with open(os.path.join(root, d, 'module.modulemap'), 'w') as f:
                f.write('module %s { header "%s" export * }\n' % (name[0].upper(), name))
        with open(os.path.join(root, 'sources', 'usemodule.m'), 'w') as f:
            f.write('@import M;\n@import F;\nvoid F(Widget *w) { [w doThing]; (void)FH(); }\n')
        cache = make_temp('codedb-mc-')
        db = os.path.join(os.path.dirname(root), 'c.sqlite')
        args = clang_args(root, 'sources/usemodule.m', ['-fmodules', '-fmodules-cache-path=' + cache,
                                                        '-I', os.path.join(root, 'realdir'),
                                                        '-I', os.path.join(root, 'fakesdk')])
        r = subprocess.run([EXTRACTOR, '--db', db, '--root', root, '--target', 'T',
                            '--main', os.path.join(root, 'sources/usemodule.m'),
                            '--sdk-path', os.path.join(root, 'fakesdk'), '--sdk-version', '1'] + scope_args() + ['--'] + args,
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        con = sqlite3.connect(db)
        inputs = dict(con.execute('SELECT path, digest FROM tu_input'))
        self.assertEqual(inputs.get('realdir/m.h'), sha(os.path.join(root, 'realdir', 'm.h')))
        self.assertIn('sources/widget.h', inputs)
        self.assertNotIn('fakesdk/f.h', inputs)
        with open(os.path.join(root, 'realdir', 'm.h'), 'a') as f:
            f.write('// edited\n')
        tu = con.execute('SELECT id FROM tu').fetchone()[0]
        self.assertEqual(codedb.first_stale_inputs(con, codedb.DigestCache(root)), {tu: 'input changed: realdir/m.h'})
        con.close()

    def test_vfs_overlay_virtual_path(self):
        root = make_root()
        os.mkdir(os.path.join(root, 'sources', 'realdir'))
        os.mkdir(os.path.join(root, 'virtual'))
        with open(os.path.join(root, 'sources', 'realdir', 'vreal.h'), 'w') as f:
            f.write('#import "sources/widget.h"\nstatic inline void VH(Widget *w) { [w makeThing]; }\n')
        overlay = os.path.join(root, 'overlay.yaml')
        with open(overlay, 'w') as f:
            json.dump({'version': 0, 'case-sensitive': 'false', 'roots': [{
                'type': 'directory', 'name': os.path.join(root, 'virtual'),
                'contents': [{'type': 'file', 'name': 'vh.h',
                              'external-contents': os.path.join(root, 'sources', 'realdir', 'vreal.h')}]}]}, f)
        with open(os.path.join(root, 'sources/usevfs.m'), 'w') as f:
            f.write('#import "vh.h"\nvoid F(Widget *w) { VH(w); }\n')
        db = os.path.join(os.path.dirname(root), 'v.sqlite')
        status, stderr, _ = extract(root, 'sources/usevfs.m', db,
                                    extra=['-ivfsoverlay', overlay, '-I', os.path.join(root, 'virtual')])
        self.assertEqual(status, 0, stderr)
        con = sqlite3.connect(db)
        paths = sorted(r[0] for r in con.execute('SELECT path FROM tu_input'))
        con.close()
        self.assertEqual(paths, ['sources/realdir/vreal.h', 'sources/usevfs.m', 'sources/widget.h'])
        self.assertEqual([(r[0], r[4], r[5], r[6]) for r in send_rows(db)], [('makeThing', 'sources/realdir/vreal.h', 2, 39)])


class ParseErrorTest(unittest.TestCase):
    def test_unit_with_parse_error_is_recorded_and_flagged(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'b.sqlite')
        status, stderr, _ = extract(root, 'sources/broken.m', db)
        self.assertEqual(status, 3)
        self.assertIn('sources/broken.m:6:13: error: expected expression', stderr)
        self.assertIn('sources/broken.m:7:13: error: expected expression', stderr)
        self.assertIn('recorded with 2 error(s)', stderr)
        con = sqlite3.connect(db)
        self.assertEqual(con.execute('SELECT main_file, diagnostics_errors FROM tu').fetchall(), [('sources/broken.m', 2)])
        con.close()
        self.assertEqual(send_rows(db), [('doThing', 'instance', 'Widget *', usr('doThing'), 'sources/broken.m', 5, 11,
                                          usr('broken'), '-[Widget(Broken) broken]', 0, 0) + NO_MACRO])

    def test_usage_error(self):
        r = subprocess.run([EXTRACTOR, '--db', 'x'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)

    def test_version_reports_the_source_digest(self):
        out = subprocess.run([EXTRACTOR, '--version'], capture_output=True, text=True).stdout
        self.assertRegex(out, r'^extract_sends [0-9a-f]{64} Homebrew clang version 22\.')
        self.assertEqual(out.split()[1], codedb.extractor_source_digest())


class AtomicWriteTest(unittest.TestCase):
    def test_failure_midway_leaves_the_previous_rows(self):
        root = make_root()
        db = os.path.join(os.path.dirname(root), 'a.sqlite')
        self.assertEqual(extract(root, 'sources/sends.m', db)[0], 0)
        before = send_rows(db)
        con = sqlite3.connect(db)
        # Fails the unit's write after its tu row, its inputs and some of its
        # sends have been inserted.
        con.execute("CREATE TRIGGER fail_midway BEFORE INSERT ON send WHEN NEW.selector = 'title' "
                    "BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        con.commit()
        con.close()
        status, stderr, _ = extract(root, 'sources/sends.m', db)
        self.assertEqual(status, 2, stderr)
        self.assertIn('injected failure', stderr)
        self.assertEqual(send_rows(db), before)
        con = sqlite3.connect(db)
        self.assertEqual(con.execute('SELECT count(*) FROM tu').fetchone(), (1,))
        self.assertEqual(con.execute('SELECT count(*) FROM tu_input').fetchone(), (3,))
        con.close()


SDK = '/SDKs/MacOSX.sdk'
PCH_COPY = '/r/Build/Intermediates.noindex/PrecompiledHeaders/SharedPrecompiledHeaders/1/iTerm2.pch'


class TranslateTest(unittest.TestCase):
    def test_apple_command_translated(self):
        captured = [
            '/Xcode/clang', '-xobjective-c', '/r/sources/A.m', '-o', '/r/Build/A.o',
            '-ivfsstatcache', '/DerivedData/SDKStatCaches.noindex/x.sdkstatcache',
            '--target=arm64-apple-macos13.0', '-fmodules-prune-interval=86400', '-fmodules-prune-after=345600',
            '-fbuild-session-file=/DerivedData/ModuleCache.noindex/Session.modulevalidation',
            '-fmodules-validate-once-per-build-session', '-Wno-trigraphs', '-Werror', '-Werror=return-type',
            '-isysroot', '/Xcode/MacOSX27.0.sdk', '-fobjc-arc', '-fmodules',
            '-fmodules-cache-path=/DerivedData/ModuleCache.noindex', '-D', 'DEBUG=1', '-Wl,-x', '-g', '-gmodules',
            '-index-store-path', '/DerivedData/Index.noindex/DataStore',
            '-include', PCH_COPY, '-MMD', '-MT', 'dependencies', '-MF', '/r/Build/A.d',
            '--serialize-diagnostics', '/r/Build/A.dia', '-c',
            '-Xclang', '-clang-vendor-feature=+thisNoNullAttr', '-Xclang', '-fno-odr-hash-protocols',
            '-Xclang', '-Wno-error=allocator-wrappers', '-Xclang', '-fkeep-me',
            '-index-unit-output-path', '/iTerm2.build/A.o', '-mlinker-version=1166.2',
            '--target=arm64-apple-macosx13.0.0']
        args, dropped = codedb.translate_command(captured, {PCH_COPY: '/r/sources/iTerm2.pch'}, '/r/tmp/mc', SDK)
        self.assertEqual(args, [
            '-xobjective-c', '/r/sources/A.m', '--target=arm64-apple-macos13.0', '-isysroot', SDK,
            '-fobjc-arc', '-fmodules', '-D', 'DEBUG=1', '-Wl,-x', '-g', '-include', '/r/sources/iTerm2.pch',
            '-Xclang', '-fkeep-me', '-mlinker-version=1166.2', '--target=arm64-apple-macosx13.0.0',
            '-fmodules-cache-path=/r/tmp/mc', '-w'])
        self.assertEqual(dropped, [
            '-o', '/r/Build/A.o', '-ivfsstatcache', '/DerivedData/SDKStatCaches.noindex/x.sdkstatcache',
            '-fmodules-prune-interval=86400', '-fmodules-prune-after=345600',
            '-fbuild-session-file=/DerivedData/ModuleCache.noindex/Session.modulevalidation',
            '-fmodules-validate-once-per-build-session', '-Wno-trigraphs', '-Werror', '-Werror=return-type',
            '-fmodules-cache-path=/DerivedData/ModuleCache.noindex', '-gmodules',
            '-index-store-path', '/DerivedData/Index.noindex/DataStore',
            '-MMD', '-MT', 'dependencies', '-MF', '/r/Build/A.d', '--serialize-diagnostics', '/r/Build/A.dia', '-c',
            '-Xclang', '-clang-vendor-feature=+thisNoNullAttr', '-Xclang', '-fno-odr-hash-protocols',
            '-Xclang', '-Wno-error=allocator-wrappers', '-index-unit-output-path', '/iTerm2.build/A.o'])
        for flag in ('-index-store-path', '-index-unit-output-path', '-o', '-ivfsstatcache', '-MMD', '-MF', '-MT',
                     '--serialize-diagnostics', '-c'):
            self.assertNotIn(flag, args)

    def test_unknown_precompiled_header_is_an_error(self):
        with self.assertRaises(codedb.CodeDBError):
            codedb.translate_command(['cc', '-include', '/nonexistent/x/iTerm2.pch', 'a.m'], {}, '/mc', SDK)

    def test_existing_include_is_kept(self):
        args, _ = codedb.translate_command(['cc', '-include', __file__, 'a.m'], {}, '/mc', SDK)
        self.assertEqual(args, ['-include', __file__, 'a.m', '-fmodules-cache-path=/mc', '-w'])

    def test_output_facts(self):
        self.assertEqual(codedb.output_facts(
            '/r/Build/Intermediates.noindex/Variant-NoSanitizers/iTerm2.build/Development/iTerm2SharedARC.build/'
            'Objects-normal/arm64/PTYSession.o'),
            ('iTerm2SharedARC', 'Development', 'arm64', 'Variant-NoSanitizers'))
        self.assertIsNone(codedb.output_facts('/r/x.o'))

    def test_repository_sources_and_migration_scope(self):
        # Every C-family file in the repository is a unit of the compile
        # database, except generated files under Build/.
        for p in ('sources/A.m', 'ThirdParty/PSMTabBarControl/source/P.m', 'ModernTests/T.m',
                  'ThirdParty/libsixel/s.c', 'submodules/x/y.m', 'SignedArchive/SignedArchive/S.m',
                  'pidinfo/iTermDirectoryEntry.m', 'ShellLauncher/main.c'):
            self.assertTrue(codedb.in_repo_source(p), p)
        for p in ('sources/A.swift', '/abs/sources/A.m', 'Build/Intermediates.noindex/x.c'):
            self.assertFalse(codedb.in_repo_source(p), p)
        for p in ('sources/A.m', 'ThirdParty/PSMTabBarControl/source/P.m',
                  'SignedArchive/SignedArchive/S.m', 'pidinfo/iTermGitClient.m', 'iTerm2SandboxedWorker/main.m',
                  'ShellLauncher/main.c', 'ColorPicker/ColorPicker/C.m', 'SearchableComboListView/S.m',
                  'BetterFontPicker/BetterFontPicker/B.m'):
            self.assertTrue(codedb.in_migration_scope(p), p)
        # Test code is not migrated (docs/swift-migration/README.md section 2).
        for p in ('ModernTests/T.m', 'ThirdParty/libsixel/s.c', 'submodules/x/y.m', 'misc/x.h', 'ThirdParty/fmdb/FMDatabase.m',
                  '/abs/sources/A.m', 'sourcesX/A.m', 'pidinfoX/A.m'):
            self.assertFalse(codedb.in_migration_scope(p), p)


def write_fragment(d, name, file, output, extra=(), lang='-xobjective-c'):
    frag = {'directory': ROOT_FOR_FRAGMENTS, 'file': file, 'output': output,
            'arguments': ['/Xcode/clang', lang, file, '-o', output, '-isysroot', '/Xcode/sdk', '-c'] + list(extra)}
    with open(os.path.join(d, name), 'w') as f:
        f.write(json.dumps(frag) + ',\n')


def write_capture_record(d, root, captured_at='2026-11-19T00:00:00Z'):
    """The record capture_compile_commands.sh writes next to the .captured
    stamp: the project's build settings digest, the SDK and the date, as of
    the capture. Written out by hand here, from the project as it is now."""
    sdk_path, sdk_version = codedb.current_sdk()
    with open(os.path.join(d, '.capture-record'), 'w') as f:
        json.dump({'build_settings_sha256': codedb.build_settings_digest(root), 'sdk_path': sdk_path,
                   'sdk_version': sdk_version, 'captured_at': captured_at}, f)


def mark_captured(d, root=None):
    with open(os.path.join(d, '.captured'), 'w') as f:
        f.write('2026-11-19T00:00:00Z\n')
    write_capture_record(d, root or ROOT_FOR_FRAGMENTS)


ROOT_FOR_FRAGMENTS = '/r'
OBJ = '/r/Build/Intermediates.noindex/Variant-NoSanitizers/iTerm2.build/Development/%s.build/Objects-normal/arm64/%s'
ASAN = '/r/Build/Intermediates.noindex/Variant-ASan/iTerm2.build/Development/%s.build/Objects-normal-asan/arm64/%s'
PCHOUT = '/r/Build/Intermediates.noindex/PrecompiledHeaders/SharedPrecompiledHeaders/7/iTerm2.pch'


class CompileDatabaseTest(unittest.TestCase):
    def test_build_from_fragments(self):
        d = make_temp('codedb-frag-')
        frags = os.path.join(d, 'f')
        os.mkdir(frags)
        write_fragment(frags, 'pch.json', '/r/sources/iTerm2.pch', PCHOUT + '.gch', lang='-xobjective-c-header')
        write_fragment(frags, 'a.json', '/r/sources/A.m', OBJ % ('iTerm2SharedARC', 'A.o'),
                       ['-include', PCHOUT, '-Wall'])
        write_fragment(frags, 'a-asan.json', '/r/sources/A.m', ASAN % ('iTerm2SharedARC', 'A.o'),
                       ['-fsanitize=address'])
        write_fragment(frags, 't.json', '/r/ModernTests/T.m', OBJ % ('ModernTests', 'T.o'))
        write_fragment(frags, 'six.json', '/r/ThirdParty/libsixel/s.c', OBJ % ('iTerm2Shared', 's.o'), lang='-xc')
        write_fragment(frags, 'odd.json', '/r/sources/B.m', '/r/elsewhere/B.o')
        mark_captured(frags)
        out = os.path.join(d, 'cdb.jsonl')
        meta = codedb.build_cdb('/r', frags, out, '/r/tmp/mc', sdk=(SDK, '27.0'), log=lambda m: None)
        lines = list(codedb.read_cdb(out))
        self.assertTrue(lines[0]['meta'])
        self.assertEqual(meta['skipped'], {'header': 1, 'sanitizer variant': 1, 'outside the repository': 0,
                                           'generated under Build/': 0, 'unknown output': 1})
        self.assertEqual(meta['dropped'], {'-o': 3, '-c': 3, '-W... (warning flags)': 1})
        self.assertEqual(lines[1:], [
            {'target': 'ModernTests', 'file': 'ModernTests/T.m', 'directory': '/r', 'configuration': 'Development',
             'arch': 'arm64', 'variant': 'Variant-NoSanitizers', 'output': OBJ % ('ModernTests', 'T.o'),
             'arguments': ['-xobjective-c', '/r/ModernTests/T.m', '-isysroot', SDK,
                           '-fmodules-cache-path=/r/tmp/mc', '-w']},
            {'target': 'iTerm2Shared', 'file': 'ThirdParty/libsixel/s.c', 'directory': '/r',
             'configuration': 'Development', 'arch': 'arm64', 'variant': 'Variant-NoSanitizers',
             'output': OBJ % ('iTerm2Shared', 's.o'),
             'arguments': ['-xc', '/r/ThirdParty/libsixel/s.c', '-isysroot', SDK, '-fmodules-cache-path=/r/tmp/mc',
                           '-w']},
            {'target': 'iTerm2SharedARC', 'file': 'sources/A.m', 'directory': '/r', 'configuration': 'Development',
             'arch': 'arm64', 'variant': 'Variant-NoSanitizers', 'output': OBJ % ('iTerm2SharedARC', 'A.o'),
             'arguments': ['-xobjective-c', '/r/sources/A.m', '-isysroot', SDK, '-include', '/r/sources/iTerm2.pch',
                           '-fmodules-cache-path=/r/tmp/mc', '-w']},
        ])

    def test_units_anywhere_in_the_repository_are_included(self):
        # Helper targets' own files and code compiled into the app from other
        # directories are units; files outside the repository (a Swift
        # package checkout) and generated files under Build/ are not.
        d = make_temp('codedb-frag-')
        frags = os.path.join(d, 'f')
        os.mkdir(frags)
        write_fragment(frags, 'sig.json', '/r/SignedArchive/SignedArchive/SIGTrust.m',
                       OBJ % ('iTerm2SharedARC', 'SIGTrust.o'))
        write_fragment(frags, 'de.json', '/r/pidinfo/iTermDirectoryEntry.m', OBJ % ('pidinfo', 'D.o'))
        write_fragment(frags, 'sl.json', '/r/ShellLauncher/main.c', OBJ % ('ShellLauncher', 'main.o'), lang='-xc')
        write_fragment(frags, 'sw.json', '/r/iTerm2SandboxedWorker/iTerm2SandboxedWorker.m',
                       OBJ % ('iTerm2SandboxedWorker', 'W.o'))
        write_fragment(frags, 'sub.json', '/r/submodules/x/y.m', OBJ % ('iTerm2Shared', 'y.o'))
        write_fragment(frags, 'yams.json', '/DerivedData/SourcePackages/checkouts/Yams/Sources/CYaml/src/scanner.c',
                       OBJ % ('CYaml-t', 'scanner.o'), lang='-xc')
        write_fragment(frags, 'vers.json', '/r/Build/Intermediates.noindex/DerivedSources/vers.c',
                       OBJ % ('iTermSwiftPackages', 'vers.o'), lang='-xc')
        mark_captured(frags)
        out = os.path.join(d, 'cdb.jsonl')
        meta = codedb.build_cdb('/r', frags, out, '/r/tmp/mc', sdk=(SDK, '27.0'), log=lambda m: None)
        self.assertEqual(sorted((e['target'], e['file']) for e in codedb.read_cdb(out) if not e.get('meta')), [
            ('ShellLauncher', 'ShellLauncher/main.c'),
            ('iTerm2SandboxedWorker', 'iTerm2SandboxedWorker/iTerm2SandboxedWorker.m'),
            ('iTerm2Shared', 'submodules/x/y.m'),
            ('iTerm2SharedARC', 'SignedArchive/SignedArchive/SIGTrust.m'),
            ('pidinfo', 'pidinfo/iTermDirectoryEntry.m'),
        ])
        self.assertEqual(meta['skipped'], {'header': 0, 'sanitizer variant': 0, 'outside the repository': 1,
                                           'generated under Build/': 1, 'unknown output': 0})

    def test_project_files_outside_the_migration_scope_must_be_covered(self):
        root = os.path.join(make_temp(), 'repo')
        for p in ('sources/A.m', 'pidinfo/main.m', 'pidinfo/New.m'):
            os.makedirs(os.path.dirname(os.path.join(root, p)), exist_ok=True)
            open(os.path.join(root, p), 'w').close()
        write_project(root, {'App': ['sources/A.m'], 'pidinfo': ['pidinfo/main.m', 'pidinfo/New.m']})
        cdb = os.path.join(root, 'cdb.jsonl')
        with open(cdb, 'w') as f:
            f.write(json.dumps({'meta': True}) + '\n')
            for target, p in (('App', 'sources/A.m'), ('pidinfo', 'pidinfo/main.m')):
                f.write(json.dumps({'target': target, 'file': p, 'arguments': []}) + '\n')
        log = []
        self.assertTrue(codedb.check_cdb_against_project(root, cdb, log=log.append))
        self.assertIn('  in the project, not in the compile database: pidinfo/New.m (pidinfo)', log)

    def test_uncaptured_target_outside_the_migration_scope_is_only_named(self):
        root = os.path.join(make_temp(), 'repo')
        for p in ('sources/A.m', 'Applescript Tests/T.m'):
            os.makedirs(os.path.dirname(os.path.join(root, p)), exist_ok=True)
            open(os.path.join(root, p), 'w').close()
        write_project(root, {'App': ['sources/A.m'], 'ScriptTesting': ['Applescript Tests/T.m', 'sources/A.m']})
        cdb = os.path.join(root, 'cdb.jsonl')
        with open(cdb, 'w') as f:
            f.write(json.dumps({'meta': True, 'build_settings_sha256': codedb.build_settings_digest(root)}) + '\n')
            f.write(json.dumps({'target': 'App', 'file': 'sources/A.m', 'arguments': []}) + '\n')
        log = []
        self.assertFalse(codedb.check_cdb_against_project(root, cdb, log=log.append), log)
        self.assertIn('project target ScriptTesting compiles 2 file(s) and is not in the compile database: '
                      'Applescript Tests/T.m, sources/A.m', log)

    def test_missing_fragments_is_an_error(self):
        with self.assertRaises(codedb.CodeDBError):
            codedb.build_cdb('/r', '/nonexistent-fragments', '/tmp/x.jsonl', '/mc', sdk=(SDK, '1'))

    def test_project_comparison(self):
        root = os.path.join(make_temp(), 'repo')
        os.makedirs(os.path.join(root, 'sources'))
        os.makedirs(os.path.join(root, 'ModernTests'))
        for p in ('sources/A.m', 'sources/New.m', 'sources/Dead.m', 'ModernTests/T.m'):
            open(os.path.join(root, p), 'w').close()
        os.makedirs(os.path.join(root, 'iTerm2.xcodeproj'))
        # The project file is in Xcode's own (OpenStep) property list format.
        with open(os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj'), 'w') as f:
            f.write(PROJECT_TEXT)
        cdb = os.path.join(root, 'cdb.jsonl')
        with open(cdb, 'w') as f:
            f.write(json.dumps({'meta': True}) + '\n')
            f.write(json.dumps({'target': 'App', 'file': 'sources/A.m', 'arguments': []}) + '\n')
            f.write(json.dumps({'target': 'App', 'file': 'sources/Gone.m', 'arguments': []}) + '\n')
            f.write(json.dumps({'target': 'ModernTests', 'file': 'ModernTests/T.m', 'arguments': []}) + '\n')
        log = []
        self.assertTrue(codedb.check_cdb_against_project(root, cdb, log=log.append))
        self.assertIn('  in the project, not in the compile database: sources/New.m (App)', log)
        self.assertIn('  in the compile database, not in the project: sources/Gone.m (App)', log)
        # New.m is compiled by a target, so it is not covered, not "compiled
        # by no target".
        self.assertIn("1 files on disk in the migration's scope are compiled by no target of iTerm2.xcodeproj (another "
                      'project may build them; every query lists the files that are not parsed):', log)
        self.assertIn('  sources/Dead.m', log)
        self.assertNotIn('  sources/New.m', log)
        # A project target that compiles in-scope files but that the capture
        # did not build is named.
        self.assertIn('project target AppleScriptTesting compiles 1 file(s) and is not in the compile '
                      'database: sources/A.m', log)


PROJECT_TEXT = r'''// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 77;
	objects = {
/* Begin PBXGroup section */
		ROOT /* root */ = {isa = PBXGroup; children = (SRC, MT, ); sourceTree = "<group>"; };
		SRC = {isa = PBXGroup; children = (FA /* A.m */, FN, ); path = sources; sourceTree = "<group>"; };
/* End PBXGroup section */
		FA /* A.m */ = {isa = PBXFileReference; path = A.m; sourceTree = "<group>"; };
		FN = {isa = PBXFileReference; path = "New.m"; sourceTree = "<group>"; };
		BA = {isa = PBXBuildFile; fileRef = FA /* A.m */; };
		BN = {isa = PBXBuildFile; fileRef = FN; };
		BA2 = {isa = PBXBuildFile; fileRef = FA; };
		PH = {isa = PBXSourcesBuildPhase; files = (BA, BN, ); };
		PH2 = {isa = PBXSourcesBuildPhase; files = (BA2); };
		TA = {isa = PBXNativeTarget; name = App; buildPhases = (PH, ); };
		TS = {isa = PBXNativeTarget; name = AppleScriptTesting; buildPhases = (PH2, ); };
		MT = {isa = PBXFileSystemSynchronizedRootGroup; path = ModernTests; sourceTree = "<group>"; exceptions = (); };
		TT = {isa = PBXNativeTarget; name = ModernTests; buildPhases = (); fileSystemSynchronizedGroups = (MT, ); };
	};
	rootObject = ROOT;
}
'''


class PbxprojTest(unittest.TestCase):
    def test_parse_openstep_plist(self):
        text = ('// !$*UTF8*$!\n{ a = 1; "b c" = ( x, "y z", ); /* comment */ d = { e = "q\\"uote\\n"; }; '
                'f = <0fA1>; g = (); h = $SRCROOT/x-y.m; i = "\\U00e9\\t"; }\n')
        self.assertEqual(codedb.parse_openstep_plist(text),
                         {'a': '1', 'b c': ['x', 'y z'], 'd': {'e': 'q"uote\n'}, 'f': b'\x0f\xa1', 'g': [],
                          'h': '$SRCROOT/x-y.m', 'i': '\u00e9\t'})

    def test_parse_errors(self):
        for bad in ('{ a = 1 }', '{ a = "x; }', '( a b )', '{ a = 1; } trailing'):
            with self.assertRaises(codedb.CodeDBError, msg=bad):
                codedb.parse_openstep_plist(bad)

    def write_plist(self, text):
        path = os.path.join(make_temp('codedb-plist-'), 'p.pbxproj')
        with open(path, 'wb') as f:
            f.write(text.encode('utf-8'))
        return path

    def plutil(self, path):
        r = subprocess.run(['/usr/bin/plutil', '-convert', 'json', '-o', '-', path], capture_output=True)
        return json.loads(r.stdout) if r.returncode == 0 else None

    def test_byte_order_mark(self):
        path = self.write_plist('\ufeff// !$*UTF8*$!\n{ a = 1; b = "x"; }\n')
        self.assertEqual(codedb.read_pbxproj(path), {'a': '1', 'b': 'x'})

    # Octal escapes name a character in the NeXTSTEP encoding, as plutil
    # reads them, not a byte of UTF-8 and not Latin-1.
    OCTAL = (r'{ a = "\303\251"; b = "\101\7x"; c = "\1234"; d = "\240\200"; e = "\0"; f = "\12"; '
             r'g = "\330\331\345\374"; }')

    def test_octal_escapes(self):
        self.assertEqual(codedb.parse_openstep_plist(self.OCTAL),
                         {'a': '\u02c6\u2019', 'b': 'A\x07x', 'c': 'S4', 'd': '\u00a9\u00a0', 'e': '\x00', 'f': '\n',
                          'g': '\u00e3\u00e4\u00ef\u00fe'})

    def test_octal_escape_with_no_nextstep_character_is_an_error(self):
        for bad in (r'{ a = "\376"; }', r'{ a = "\377"; }'):
            with self.assertRaises(codedb.CodeDBError, msg=bad):
                codedb.parse_openstep_plist(bad)

    @unittest.skipUnless(os.path.exists('/usr/bin/plutil'), 'needs plutil as an oracle')
    def test_byte_order_mark_and_octal_escapes_match_plutil(self):
        for text in ('\ufeff// !$*UTF8*$!\n{ a = 1; b = "x"; }\n', self.OCTAL,
                     '{ all = "%s"; }' % ''.join('\\%03o' % b for b in range(0o200, 0o376))):
            path = self.write_plist(text)
            oracle = self.plutil(path)
            self.assertIsNotNone(oracle, text)
            self.assertEqual(codedb.read_pbxproj(path), oracle, text)
        for bad in (r'{ a = "\376"; }', r'{ a = "\377"; }'):
            self.assertIsNone(self.plutil(self.write_plist(bad)), bad)

    @unittest.skipUnless(os.path.exists('/usr/bin/plutil') and
                         os.path.exists(os.path.join(REPO, 'iTerm2.xcodeproj', 'project.pbxproj')),
                         'needs plutil and the real project as an oracle')
    def test_real_project_matches_plutil(self):
        pbx = os.path.join(REPO, 'iTerm2.xcodeproj', 'project.pbxproj')
        oracle = json.loads(subprocess.run(['/usr/bin/plutil', '-convert', 'json', '-o', '-', pbx],
                                           capture_output=True, check=True).stdout)
        with open(pbx, encoding='utf-8') as f:
            mine = codedb.parse_openstep_plist(f.read())
        self.assertEqual(mine, oracle)


def fragments_for_removal_tests(d):
    frags = os.path.join(d, 'f')
    os.mkdir(frags)
    write_fragment(frags, 'a.json', '/r/sources/A.m', OBJ % ('iTerm2SharedARC', 'A.o'))
    write_fragment(frags, 'b.json', '/r/sources/B.m', OBJ % ('iTerm2SharedARC', 'B.o'))
    write_fragment(frags, 't.json', '/r/ModernTests/T.m', OBJ % ('ModernTests', 'T.o'))
    mark_captured(frags)
    return frags


class CompileDatabaseRemovalTest(unittest.TestCase):
    def setUp(self):
        d = make_temp('codedb-rm-')
        self.frags = fragments_for_removal_tests(d)
        self.out = os.path.join(d, 'cdb.jsonl')
        codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        with open(self.out) as f:
            self.before = f.read()

    def assert_unchanged(self):
        with open(self.out) as f:
            self.assertEqual(f.read(), self.before)

    def test_fewer_entries_for_a_target_is_refused(self):
        os.remove(os.path.join(self.frags, 'b.json'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        self.assertIn('sources/B.m (iTerm2SharedARC)', str(cm.exception))
        self.assertIn('--accept-removals', str(cm.exception))
        self.assert_unchanged()

    def test_dropped_target_is_refused(self):
        os.remove(os.path.join(self.frags, 't.json'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        self.assertIn('ModernTests/T.m (ModernTests)', str(cm.exception))
        self.assertIn('target ModernTests', str(cm.exception))
        self.assert_unchanged()

    def test_accept_removals(self):
        os.remove(os.path.join(self.frags, 'b.json'))
        log = []
        codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=log.append, accept_removals=True)
        self.assertEqual([e['file'] for e in codedb.read_cdb(self.out) if not e.get('meta')],
                         ['ModernTests/T.m', 'sources/A.m'])
        self.assertIn('  removed: sources/B.m (iTerm2SharedARC)', log)

    def test_capture_from_an_incremental_build_says_a_clean_build_is_needed(self):
        d = make_temp('codedb-inc-')
        frags = os.path.join(d, 'f')
        os.mkdir(frags)
        for i in range(10):
            write_fragment(frags, 'u%d.json' % i, '/r/sources/U%d.m' % i, OBJ % ('iTerm2SharedARC', 'U%d.o' % i))
        mark_captured(frags)
        out = os.path.join(d, 'cdb.jsonl')
        codedb.build_cdb('/r', frags, out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        # An incremental build recompiled two files.
        for i in range(2, 10):
            os.remove(os.path.join(frags, 'u%d.json' % i))
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.build_cdb('/r', frags, out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        message = str(cm.exception)
        self.assertIn('the capture compiled 2 files, but the compile database has 10: an incremental build writes '
                      'fragments only for the files it recompiles. A capture needs a clean build of the test '
                      "scheme's products; capture_compile_commands.sh cleans them itself (xcodebuild clean "
                      'build-for-testing), so run it again, and do not build in Build/ while it runs.', message)
        self.assertNotIn('--accept-removals', message)

    def test_fragments_without_a_capture_record_are_refused(self):
        os.remove(os.path.join(self.frags, '.capture-record'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        self.assertIn('%s has no capture record (.capture-record): the build settings the capture was made with are '
                      'unknown. Capture again with capture_compile_commands.sh.' % self.frags, str(cm.exception))
        self.assert_unchanged()

    def test_build_settings_and_capture_facts_come_from_the_capture_record(self):
        with open(os.path.join(self.frags, '.capture-record'), 'w') as f:
            json.dump({'build_settings_sha256': 'digest-at-capture', 'sdk_path': '/captured.sdk',
                       'sdk_version': '26.0 build 25A1', 'captured_at': '2026-11-01T00:00:00Z'}, f)
        meta = codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        self.assertEqual((meta['build_settings_sha256'], meta['captured_sdk_path'], meta['captured_sdk_version'],
                          meta['captured_at']),
                         ('digest-at-capture', '/captured.sdk', '26.0 build 25A1', '2026-11-01T00:00:00Z'))
        # The commands use the SDK xcrun reports now, as before.
        self.assertEqual((meta['sdk_path'], meta['sdk_version']), (SDK, '1'))

    def test_unfinished_capture_is_refused(self):
        os.remove(os.path.join(self.frags, '.captured'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.build_cdb('/r', self.frags, self.out, '/mc', sdk=(SDK, '1'), log=lambda m: None)
        self.assertIn('did not finish', str(cm.exception))
        self.assert_unchanged()

    def test_cdb_command_exits_2_and_names_the_files(self):
        os.remove(os.path.join(self.frags, 'b.json'))
        err = io.StringIO()
        sys_stderr, sys_stdout = sys.stderr, sys.stdout
        sys.stderr, sys.stdout = err, io.StringIO()
        try:
            status = codedb.main(['--root', '/r', '--fragments', self.frags, '--cdb', self.out,
                                  '--db', self.out + '.sqlite', 'cdb'])
        finally:
            sys.stderr, sys.stdout = sys_stderr, sys_stdout
        self.assertEqual(status, 2)
        self.assertIn('sources/B.m (iTerm2SharedARC)', err.getvalue())
        self.assert_unchanged()


class AdoptCaptureTest(unittest.TestCase):
    """codedb.py adopt-capture: the one-time way to give a record to fragments
    captured before captures wrote one."""

    def setUp(self):
        work = make_temp('codedb-adopt-')
        self.root = os.path.join(work, 'repo')
        write_project(self.root, {'App': ['sources/A.m']})
        self.frags = os.path.join(work, 'frags')
        os.mkdir(self.frags)
        with open(os.path.join(self.frags, '.captured'), 'w') as f:
            f.write('2026-11-19T20:48:15Z\n')
        self.cdb = os.path.join(work, 'cdb.jsonl')
        self.record = os.path.join(self.frags, '.capture-record')

    def main(self, *args):
        out, err = io.StringIO(), io.StringIO()
        sys_stdout, sys_stderr = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            status = codedb.main(['--root', self.root, '--fragments', self.frags, '--cdb', self.cdb] + list(args))
        except SystemExit as e:
            status = e.code
        finally:
            sys.stdout, sys.stderr = sys_stdout, sys_stderr
        return status, out.getvalue(), err.getvalue()

    def test_adopt_capture_requires_the_assertion(self):
        status, out, err = self.main('adopt-capture')
        self.assertEqual(status, 2)
        self.assertIn('--i-know-the-project-is-unchanged-since', err)
        self.assertFalse(os.path.exists(self.record))

    def test_adopt_capture_writes_the_record_and_says_what_it_asserts(self):
        status, out, err = self.main('adopt-capture', '--i-know-the-project-is-unchanged-since')
        self.assertEqual(status, 0, err)
        with open(self.record) as f:
            record = json.load(f)
        digest = codedb.build_settings_digest(self.root)
        sdk_path, sdk_version = codedb.current_sdk()
        self.assertEqual(record, {'build_settings_sha256': digest, 'sdk_path': sdk_path, 'sdk_version': sdk_version,
                                  'captured_at': '2026-11-19T20:48:15Z', 'adopted': True})
        self.assertEqual(out, (
            'adopt-capture: you assert that the build settings of %s are the same now as when the capture in %s '
            'was made (it finished at 2026-11-19T20:48:15Z).\n'
            'adopt-capture: on that assertion alone, %s now records, as the capture\'s: build settings digest %s '
            '(computed from the project as it is now), SDK %s (%s) (the one xcrun reports now), date '
            '2026-11-19T20:48:15Z (from the .captured stamp).\n'
            'adopt-capture: if the assertion is false, queries can exit 0 or 1 with sends missing. Use this only for '
            'fragments captured before captures recorded their build settings; capture again with '
            'capture_compile_commands.sh otherwise.\n') % (
                codedb.project_file(self.root), self.frags, self.record, digest, sdk_path, sdk_version))

    def test_adopt_capture_refuses_a_capture_that_has_a_record(self):
        write_capture_record(self.frags, self.root, captured_at='then')
        with open(self.record) as f:
            before = f.read()
        status, out, err = self.main('adopt-capture', '--i-know-the-project-is-unchanged-since')
        self.assertEqual(status, 2)
        self.assertIn('already has a capture record', err)
        with open(self.record) as f:
            self.assertEqual(f.read(), before)

    def test_adopt_capture_refuses_an_unfinished_capture(self):
        os.remove(os.path.join(self.frags, '.captured'))
        status, out, err = self.main('adopt-capture', '--i-know-the-project-is-unchanged-since')
        self.assertEqual(status, 2)
        self.assertFalse(os.path.exists(self.record))


def write_project(root, files_by_target, product_types=None):
    """A project.pbxproj in which each target compiles the given files
    (paths relative to the root), with the product type product_types gives
    it, if any."""
    objects = ['ROOT = {isa = PBXGroup; children = (); sourceTree = "<group>"; };']
    n = 0
    for target in sorted(files_by_target):
        build_files = []
        for f in sorted(files_by_target[target]):
            n += 1
            objects.append('F%d = {isa = PBXFileReference; path = "%s"; sourceTree = SOURCE_ROOT; };' % (n, f))
            objects.append('B%d = {isa = PBXBuildFile; fileRef = F%d; };' % (n, n))
            build_files.append('B%d' % n)
        objects.append('P_%s = {isa = PBXSourcesBuildPhase; files = (%s); };' % (target, ', '.join(build_files)))
        product = (product_types or {}).get(target)
        objects.append('T_%s = {isa = PBXNativeTarget; name = %s; buildPhases = (P_%s);%s };' % (
            target, target, target, ' productType = "%s";' % product if product else ''))
    os.makedirs(os.path.join(root, 'iTerm2.xcodeproj'), exist_ok=True)
    with open(os.path.join(root, 'iTerm2.xcodeproj', 'project.pbxproj'), 'w') as f:
        f.write('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjects = {\n\t\t%s\n\t};\n\trootObject = ROOT;\n}\n'
                % '\n\t\t'.join(objects))


def write_cdb(root, path, mains=('sources/sends.m', 'sources/other.m'), extra_for=None, meta=None, targets=None,
              project=True, product_types=None):
    """A compile database for the mains, and (with project) a project file in
    which their targets compile exactly them."""
    if project:
        by_target = {}
        for m in mains:
            by_target.setdefault((targets or {}).get(m, 'T'), []).append(m)
        write_project(root, by_target, product_types)
    meta = dict(meta or {})
    if os.path.exists(codedb.project_file(root)):
        # As build_cdb records it from the project file.
        meta.setdefault('build_settings_sha256', codedb.build_settings_digest(root))
    with open(path, 'w') as f:
        f.write(json.dumps(dict({'meta': True}, **meta)) + '\n')
        for m in mains:
            args = clang_args(root, m)
            if extra_for == m:
                args = args + ['-DCHANGED=1']
            target = (targets or {}).get(m, 'T')
            f.write(json.dumps({'target': target, 'file': m, 'directory': root, 'arguments': args}) + '\n')


SUMMARY = re.compile(r'^extracted (\d+) \((\d+) with parse errors\), skipped as current (\d+), failed (\d+), '
                     r'removed (\d+);')


def make_paths(root):
    work = os.path.dirname(root)
    return codedb.Paths(root, db=os.path.join(work, 'db.sqlite'), cdb=os.path.join(work, 'cdb.jsonl'),
                        extractor=EXTRACTOR)


class DriverTest(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.paths = make_paths(self.root)
        write_cdb(self.root, self.paths.cdb)

    def run_update(self, **kw):
        log = []
        status = codedb.update(self.paths, log=log.append, **kw)
        summary = [m for m in log if SUMMARY.match(m)]
        self.assertEqual(len(summary), 1, log)
        counts = tuple(int(x) for x in SUMMARY.match(summary[0]).groups())
        return status, counts, log

    def edit(self, name, old, new):
        p = os.path.join(self.root, name) if not os.path.isabs(name) else name
        with open(p) as f:
            text = f.read()
        self.assertIn(old, text)
        with open(p, 'w') as f:
            f.write(text.replace(old, new))

    def test_first_run_then_current(self):
        self.assertEqual(self.run_update()[:2], (0, (2, 0, 0, 0, 0)))
        self.assertEqual(self.run_update()[:2], (0, (0, 0, 2, 0, 0)))

    def test_editing_included_header_makes_both_stale(self):
        self.run_update()
        self.edit('sources/helpers.h', '[w helperSend];', '[w helperSend]; [w doThing];')
        status, counts, log = self.run_update()
        self.assertEqual(counts, (2, 0, 0, 0, 0))
        self.assertTrue(any('(input changed: sources/helpers.h): ok' in m for m in log), log)

    def test_comment_only_edit_is_stale(self):
        self.run_update()
        self.edit('sources/widget.h', '// Fixture: a root class', '// Fixture (edited): a root class')
        self.assertEqual(self.run_update()[1], (2, 0, 0, 0, 0))

    def test_touch_without_change_is_current(self):
        self.run_update()
        later = time.time() + 100
        for n in ('sources/sends.m', 'sources/helpers.h', 'sources/widget.h', 'sources/other.m'):
            os.utime(os.path.join(self.root, n), (later, later))
        self.assertEqual(self.run_update()[1], (0, 0, 2, 0, 0))

    def test_editing_one_main_file(self):
        self.run_update()
        self.edit('sources/other.m', '[w doThing];', '[w doThing]; [w makeThing];')
        status, counts, log = self.run_update()
        self.assertEqual(counts, (1, 0, 1, 0, 0))
        self.assertTrue(any('T sources/other.m (input changed: sources/other.m): ok' in m for m in log), log)

    def test_editing_a_header_outside_the_repository_is_stale(self):
        # SDK and compiler resource headers are inputs with absolute paths.
        write_cdb(self.root, self.paths.cdb, mains=('sources/globals.m',))
        self.run_update()
        outside = os.path.join(os.path.dirname(self.root), 'outside', 'outside.h')
        self.edit(outside, '[w makeThing];', '[w makeThing]; [w doThing];')
        status, counts, log = self.run_update()
        self.assertEqual(counts, (1, 0, 0, 0, 0))
        self.assertTrue(any('T sources/globals.m (input changed: %s): ok' % outside in m for m in log), log)

    def test_command_change(self):
        self.run_update()
        write_cdb(self.root, self.paths.cdb, extra_for='sources/sends.m')
        status, counts, log = self.run_update()
        self.assertEqual(counts, (1, 0, 1, 0, 0))
        self.assertTrue(any('T sources/sends.m (command changed): ok' in m for m in log), log)

    def test_force_and_single_file(self):
        self.run_update()
        self.assertEqual(self.run_update(force=True)[1], (2, 0, 0, 0, 0))
        self.assertEqual(self.run_update(only_file=os.path.join(self.root, 'sources/other.m'), force=True)[1],
                         (1, 0, 0, 0, 0))
        self.assertEqual(self.run_update(only_file=os.path.join(self.root, 'sources/other.m'))[1], (0, 0, 1, 0, 0))

    def test_missing_input(self):
        self.run_update()
        os.remove(os.path.join(self.root, 'sources/helpers.h'))
        status, counts, log = self.run_update()
        self.assertEqual((status, counts), (1, (2, 2, 0, 0, 0)))
        self.assertTrue(any('T sources/sends.m (input missing: sources/helpers.h): RECORDED WITH ERRORS' in m for m in log), log)

    def test_extractor_and_sdk_changes_are_stale(self):
        fake_sdk(self, '/sdk', '1')
        write_cdb(self.root, self.paths.cdb, meta={'sdk_path': '/sdk', 'sdk_version': '1'})
        self.run_update()
        con = sqlite3.connect(self.paths.db)
        con.execute("UPDATE tu SET extractor_version='0' WHERE main_file='sources/sends.m'")
        con.execute("UPDATE tu SET sdk_version='0' WHERE main_file='sources/other.m'")
        con.commit()
        con.close()
        status, counts, log = self.run_update()
        self.assertEqual(counts, (2, 0, 0, 0, 0))
        self.assertTrue(any('T sources/sends.m (extractor changed): ok' in m for m in log), log)
        self.assertTrue(any('T sources/other.m (SDK changed): ok' in m for m in log), log)

    def test_sdk_update_at_the_same_path_makes_every_unit_stale(self):
        # The SDK xcrun reports now is compared with the one each unit was
        # extracted with, not only with the compile database's record.
        fake_sdk(self, '/sdk', '1')
        write_cdb(self.root, self.paths.cdb, meta={'sdk_path': '/sdk', 'sdk_version': '1'})
        self.assertEqual(self.run_update()[1], (2, 0, 0, 0, 0))
        fake_sdk(self, '/sdk', '2')
        status, counts, log = self.run_update()
        self.assertEqual(counts, (2, 0, 0, 0, 0))
        self.assertTrue(any('T sources/sends.m (SDK changed): ok' in m for m in log), log)
        self.assertTrue(any('T sources/other.m (SDK changed): ok' in m for m in log), log)
        con = sqlite3.connect(self.paths.db)
        self.assertEqual(con.execute('SELECT DISTINCT sdk_path, sdk_version FROM tu').fetchall(), [('/sdk', '2')])
        con.close()

    def test_any_change_to_the_extractor_sources_changes_the_version(self):
        d = make_temp('codedb-src-')
        shutil.copytree(os.path.join(CODEDB_DIR, 'extractor'), os.path.join(d, 'extractor'))
        digests = [codedb.extractor_source_digest(os.path.join(d, 'extractor'))]
        for name in ('build.sh', 'extract_sends.cpp', 'reflective_table.h'):
            with open(os.path.join(d, 'extractor', name), 'a') as f:
                f.write('\n')
            digests.append(codedb.extractor_source_digest(os.path.join(d, 'extractor')))
        self.assertEqual(digests[0], codedb.extractor_source_digest())
        self.assertEqual(len(set(digests)), 4)

    def test_ensure_extractor_rebuilds_when_the_digest_differs(self):
        d = make_temp('codedb-ens-')
        exe = write_executable(os.path.join(d, 'extract_sends'),
                               '#!/bin/sh\necho "extract_sends %s fake"\n' % ('0' * 64))
        later = time.time() + 1000
        os.utime(exe, (later, later))
        builder = write_executable(os.path.join(d, 'build.sh'),
                                   '#!/bin/sh\nprintf \'#!/bin/sh\\necho "extract_sends %s rebuilt"\\n\' > "$1"\n'
                                   'chmod +x "$1"\n' % codedb.extractor_source_digest())
        paths = codedb.Paths(self.root, extractor=exe)
        codedb.ensure_extractor(paths, log=lambda m: None, builder=builder)
        out = subprocess.run([exe, '--version'], capture_output=True, text=True).stdout
        self.assertEqual(out, 'extract_sends %s rebuilt\n' % codedb.extractor_source_digest())
        # Current: the builder is not run again.
        os.chmod(builder, 0o644)
        codedb.ensure_extractor(paths, log=lambda m: None, builder=builder)

    def test_single_file_not_in_database(self):
        with self.assertRaises(codedb.CodeDBError):
            codedb.update(self.paths, only_file=os.path.join(self.root, 'sources/widget.h'), log=lambda m: None)

    def test_removed_unit(self):
        self.run_update()
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',))
        status, counts, log = self.run_update()
        self.assertEqual(counts, (0, 0, 1, 0, 1))
        self.assertIn('removing T sources/other.m from the database: it is not in the compile database', log)
        con = sqlite3.connect(self.paths.db)
        self.assertEqual(con.execute('SELECT main_file FROM tu').fetchall(), [('sources/sends.m',)])
        self.assertEqual(con.execute('SELECT count(*) FROM send WHERE file=\'sources/other.m\'').fetchone(), (0,))
        con.close()

    def test_parse_error_unit_reported(self):
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m', 'sources/broken.m'))
        status, counts, log = self.run_update()
        self.assertEqual((status, counts), (1, (2, 1, 0, 0, 0)))
        self.assertTrue(any('T sources/broken.m (missing from the database): RECORDED WITH ERRORS' in m
                            and 'expected expression' in m for m in log), log)
        status, counts, log = self.run_update()
        self.assertEqual((status, counts), (1, (0, 0, 2, 0, 0)))
        self.assertIn('1 units in the database have parse errors; their rows are incomplete', log)

    def test_failed_extraction_counted(self):
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',))
        self.paths.extractor = fake_extractor(os.path.join(os.path.dirname(self.root), 'bad-extractor'),
                                              'echo boom >&2; exit 5')
        status, counts, log = self.run_update()
        self.assertEqual((status, counts), (1, (0, 0, 0, 1, 0)))
        self.assertTrue(any('FAILED (status 5)' in m and 'boom' in m for m in log), log)

    def test_killed_extraction_is_a_failure_not_a_parse_error(self):
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',))
        self.paths.extractor = fake_extractor(os.path.join(os.path.dirname(self.root), 'killed-extractor'),
                                              'exit 137')
        status, counts, log = self.run_update()
        self.assertEqual((status, counts), (1, (0, 0, 0, 1, 0)))
        self.assertTrue(any('FAILED (killed by the memory watchdog)' in m for m in log), log)

    def test_failed_unit_is_retried(self):
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',))
        real = self.paths.extractor
        self.paths.extractor = fake_extractor(os.path.join(os.path.dirname(self.root), 'bad-extractor'), 'exit 5')
        self.run_update()
        self.paths.extractor = real
        status, counts, log = self.run_update()
        self.assertEqual((status, counts), (0, (1, 0, 0, 0, 0)))
        self.assertTrue(any('T sources/sends.m (last extraction failed: status 5): ok' in m for m in log), log)

    def test_peak_memory_is_not_carried_over_from_the_previous_unit(self):
        counter = os.path.join(os.path.dirname(self.root), 'guard-ran-once')
        # A guard that reports a peak for the first unit only, as when a guard
        # is killed before it writes one.
        self.paths.guard = write_executable(
            os.path.join(os.path.dirname(self.root), 'fake-guard'),
            '#!/bin/sh\npeak="$2"; shift 3\n'
            'if [ ! -e "%s" ]; then echo 512000 > "$peak"; touch "%s"; fi\nexec "$@"\n' % (counter, counter))
        status, counts, log = self.run_update()
        self.assertEqual(counts, (2, 0, 0, 0, 0))
        units = [m for m in log if m.startswith('[')]
        self.assertTrue(units[0].endswith(' 500 MB'), units)
        self.assertTrue(units[1].endswith(' peak unknown'), units)

    def test_old_schema_is_replaced(self):
        self.run_update()
        con = sqlite3.connect(self.paths.db)
        con.execute('PRAGMA user_version=1')
        con.commit()
        con.close()
        status, counts, log = self.run_update()
        self.assertEqual(counts, (2, 0, 0, 0, 0))
        self.assertTrue(any('schema version 1' in m for m in log), log)


TEXT_SEARCH_FORMS = ('  searched: the first keyword of the selector as a message send (followed by : or ]), and, for a '
                     'setter-shaped (setFoo:), is-prefixed (isFoo) or unary (foo) selector, the property it stands for '
                     'accessed with dot syntax, whether or not an assignment follows (.foo and .Foo for setFoo:, .foo and '
                     '.isFoo for isFoo, .foo for foo); not searched: later keywords alone, selectors built by macros or '
                     'strings, @selector of a unary selector, and properties whose accessor names were customized with '
                     'getter= or setter= other than the is form\n')
TOOLS_NOT_LISTED = ("  files under tools/swift_migration/ are the migration's own tools and fixtures and are not "
                    "listed\n")


class QueryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = make_root()
        cls.paths = make_paths(cls.root)
        write_cdb(cls.root, cls.paths.cdb, mains=('sources/sends.m', 'sources/other.m', 'sources/macros.m', 'pidinfo/gitclient.m',
                                                  'ThirdParty/Other/tpclient.m'),
                  targets={'pidinfo/gitclient.m': 'ModernTests', 'ThirdParty/Other/tpclient.m': 'iTerm2Shared'},
                  product_types={'ModernTests': 'com.apple.product-type.bundle.unit-test'})
        codedb.update(cls.paths, log=lambda m: None)

    def query(self, selector, paths=None):
        out = io.StringIO()
        status = codedb.sends(paths or self.paths, selector, out=out)
        rows, _, status_block = out.getvalue().partition('\n--- status ---\n')
        return status, rows.splitlines(), status_block

    def test_rows(self):
        status, rows, block = self.query('makeThing')
        self.assertEqual(status, 0)
        self.assertEqual(rows, [
            'sources/macros.m:12:12  Macros  receiver Widget *  macro LOG argument (defined sources/macros.m:4, used at 11:5)  '
            'targets T',
            'sources/macros.m:15:9  Macros  receiver Widget *  macro LOG body (defined sources/macros.m:4, used at 14:5)  targets T',
            'sources/sends.m:25:11  -[Widget run]  receiver Widget *  macro BLOCK argument (defined sources/sends.m:3, used at 25:5)  '
            'in block  targets T',
            'sources/sends.m:28:19  -[Widget run]  receiver Widget *  targets T',
        ])

    def test_pasted_role_shown(self):
        self.assertEqual(self.query('load_alpha')[1], [
            'sources/macros.m:16:8  Macros  receiver Widget *  macro CAT pasted (defined sources/macros.m:8, used at 16:8)  targets T',
            'sources/sends.m:26:5  -[Widget run]  receiver Widget *  macro LOAD pasted (defined sources/sends.m:4, used at 26:5)  '
            'targets T',
        ])

    def test_class_receiver_and_accessor_and_multiplicity(self):
        self.assertEqual(self.query('make')[1], ['sources/sends.m:22:13  -[Widget run]  receiver Widget (class)  targets T'])
        self.assertEqual(self.query('title')[1],
                         ['sources/sends.m:28:30  -[Widget run]  receiver Widget *  dot-syntax accessor  targets T'])
        self.assertIn('sources/sends.m:27:11  -[Widget run]  receiver Widget *  macro TWICE argument (defined sources/sends.m:5, '
                      'used at 27:5)  2 sends at this location  targets T', self.query('doThing')[1])

    def test_header_send_from_two_units_is_one_row(self):
        self.assertEqual(self.query('helperSend')[1], ['sources/helpers.h:4:8  Helper  receiver Widget *  targets T'])

    def test_file_outside_the_migration_scope_is_labeled(self):
        rows = self.query('doThing')[1]
        self.assertIn("ThirdParty/Other/tpclient.m:4:8  TPClient  receiver Widget *  targets iTerm2Shared  "
                      "outside the migration's scope", rows)
        # pidinfo/ is in the migration's scope; only a test target compiles
        # this file, so the row is test code.
        self.assertIn('pidinfo/gitclient.m:4:8  GitClient  receiver Widget *  targets ModernTests  test code', rows)
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T', rows)
        block = self.query('doThing')[2]
        self.assertIn("rows outside the migration's scope (marked): 1\n", block)
        self.assertIn(codedb.SCOPE_STATEMENT + '\n', block)

    def test_status_block(self):
        status, rows, block = self.query('makeThing')
        expected = ('database: %s\n'
                    'compile database: %s (5 units)\n'
                    'units: 5 in the compile database, 5 in the database\n'
                    '  current: 5\n'
                    '  stale: 0\n'
                    '  missing from the database: 0\n'
                    '  last extraction failed: 0\n'
                    '  in the database, not in the compile database: 0\n'
                    '  recorded with parse errors: 0\n'
                    'compile database coverage: complete\n'
                    'Not parsed: callers in these files are NOT in this database\n'
                    '  5 implementation files (.c, .m, .mm, .cpp, .cc, .cxx) in the repository are in no unit of the '
                    'compile database:\n'
                    '  (a) built by another Xcode project or Swift package: 0\n'
                    '  (b) under submodules/: 0\n'
                    '  (c) compiled by a target of iTerm2.xcodeproj, but in no unit: 0\n'
                    '  (d) compiled by no target of any project found: 5\n'
                    '    sources/broken.m\n    sources/globals.m\n    sources/lambda.mm\n'
                    '    sources/unevaluated.m\n    sources/unevaluated_cxx.mm\n' + TOOLS_NOT_LISTED +
                    'Possible callers in files that are not parsed (text search, unverified): 8\n' + TEXT_SEARCH_FORMS +
                    '    sources/lambda.mm:8 (message send): void (^b)(void) = ^{ struct L { static void f(Widget *x) { [x makeThing]; } '
                    '}; L::f(w); };\n'
                    '    sources/unevaluated.m:5 (message send): __typeof__([w makeThing]) x = [w makeThing];\n'
                    '    sources/unevaluated.m:6 (message send): (void)sizeof([w makeThing]);\n'
                    '    sources/unevaluated.m:7 (message send): (void)__alignof__([w makeThing]);\n'
                    '    sources/unevaluated.m:8 (message send): (void)_Alignof(__typeof__([w makeThing]));\n'
                    '    sources/unevaluated.m:9 (message send): (void)@encode(__typeof__([w makeThing]));\n'
                    '    sources/unevaluated_cxx.mm:4 (message send): decltype([w makeThing]) x = [w makeThing];\n'
                    '    sources/unevaluated_cxx.mm:5 (message send): bool n = noexcept([w makeThing]);\n'
                    'rows printed: 4; from units that are not current: 0\n') % (self.paths.db, self.paths.cdb)
        self.assertTrue(block.startswith(expected), block)
        self.assertNotIn('INCOMPLETE', block)
        self.assertNotIn('are compiled by no target', block)
        self.assertNotIn('No rows does not mean no callers', block)
        self.assertIn('extracted: configuration ?, architecture ?, SDK %s (%s), Homebrew clang version 22.'
                      % codedb.current_sdk(), block)
        self.assertIn('note: the SDK is the one xcrun reports now. A change of its path, version or build version '
                      'since a unit was extracted, or since the compile database was built, is detected and makes the '
                      'units stale. Every file a unit reads itself is recorded and compared, SDK module maps and headers '
                      'included. A header in the SDK or the compiler resource directory that a unit reads only through '
                      'a compiled module is not recorded: the SDK path, version and build version stand for it, so an '
                      'edit to it that keeps them is not detected.\n', block)
        self.assertIn('rows can be listed for sends the binary never makes', block)
        self.assertIn('Not in this database:\n', block)
        for item in codedb.NOT_IN_DATABASE:
            self.assertIn('  - %s\n' % item, block)
        not_in = block.split('Not in this database:\n')[1]
        for phrase in ('@selector', 'reflective', 'Swift', 'xib', 'sdef', 'plists', 'inactive #if',
                       'other build configurations', 'other architecture'):
            self.assertIn(phrase, not_in)
        self.assertNotIn('dot-syntax', not_in)
        self.assertIn('exit status: 0 sends printed, 1 none (0 and 1 only when every unit is current, the compile '
                      'database covers the project, the build settings are unchanged and, with no rows, the text '
                      'search finds none of the forms it searches in a file that is not parsed: the first keyword as a '
                      'message send, and the property of a setter-shaped, is-prefixed or unary selector with dot '
                      'syntax), 3 answered but incomplete, 2 error\n', block)
        self.assertIn('  - code built by other Xcode projects and Swift packages, which is not parsed, and code under '
                      'submodules/ (see Not parsed): none in this repository\n', block)

    def test_no_rows_exit_1(self):
        status, rows, block = self.query('noSuchSelector')
        self.assertEqual((status, rows), (1, []))
        self.assertIn('rows printed: 0;', block)
        self.assertEqual(block.splitlines()[0], 'No rows does not mean no callers: 5 implementation files in the '
                                                'repository are not parsed (see Not parsed)')
        self.assertNotIn('Possible callers', block)

    def test_missing_database_exit_2(self):
        sys_stderr = sys.stderr
        sys.stderr = io.StringIO()
        try:
            status = codedb.main(['--root', self.root, '--db', '/nonexistent/codedb.sqlite', 'sends', 'x'])
        finally:
            sys.stderr = sys_stderr
        self.assertEqual(status, 2)

    def test_database_without_schema_exit_2(self):
        empty = os.path.join(os.path.dirname(self.root), 'empty.sqlite')
        sqlite3.connect(empty).close()
        sys_stderr = sys.stderr
        sys.stderr = io.StringIO()
        try:
            status = codedb.main(['--root', self.root, '--db', empty, 'sends', 'x'])
        finally:
            sys.stderr = sys_stderr
        self.assertEqual(status, 2)

    def test_main_exit_codes(self):
        sys_stdout = sys.stdout
        sys.stdout = io.StringIO()
        try:
            found = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                 '--extractor', EXTRACTOR, 'sends', 'make'])
            none = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                '--extractor', EXTRACTOR, 'sends', 'nothing'])
            # With no extractor to report its compiler, no unit is known to
            # be current.
            unknown = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                   '--extractor', os.path.join(self.root, 'no-such-extractor'), 'sends', 'make'])
            output = sys.stdout.getvalue()
        finally:
            sys.stdout = sys_stdout
        self.assertEqual((found, none, unknown), (0, 1, 3))
        self.assertIn('  stale: 5 (compiler unknown 5)\n', output)
        self.assertIn(': compiler unknown: the extractor at %s cannot report its version; run codedb.py update, which '
                      'builds it\n' % os.path.join(self.root, 'no-such-extractor'), output)


class QueryCompletenessTest(unittest.TestCase):
    """Every unit's state is reported by every query; missing or failed units
    make the answer incomplete (exit 3)."""

    def setUp(self):
        self.root = make_root()
        self.paths = make_paths(self.root)
        fake_sdk(self, '/sdk', '1')
        write_cdb(self.root, self.paths.cdb, meta={'sdk_path': '/sdk', 'sdk_version': '1'})
        codedb.update(self.paths, log=lambda m: None)

    def query(self, selector):
        out = io.StringIO()
        status = codedb.sends(self.paths, selector, out=out)
        rows, _, block = out.getvalue().partition('\n--- status ---\n')
        return status, rows.splitlines(), block

    def sql(self, *statements):
        con = sqlite3.connect(self.paths.db)
        for s in statements:
            con.execute(s)
        con.commit()
        con.close()

    def delete_unit(self, main):
        self.sql("DELETE FROM send WHERE tu IN (SELECT id FROM tu WHERE main_file='%s')" % main,
                 "DELETE FROM tu_input WHERE tu IN (SELECT id FROM tu WHERE main_file='%s')" % main,
                 "DELETE FROM tu WHERE main_file='%s'" % main)

    def test_missing_unit_makes_the_answer_incomplete(self):
        self.delete_unit('sources/other.m')
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertNotIn('sources/other.m:4:8', '\n'.join(rows))
        lines = block.splitlines()
        self.assertEqual(lines[0], 'INCOMPLETE: 1 of 2 units are not current (stale 0, missing 1, failed 0, not in the '
                                   'compile database 0, recorded with parse errors 0); sends in them may be missing '
                                   'or wrong. Run codedb.py update, or ask with sends --update.')
        self.assertEqual(lines[-1], lines[0])
        self.assertIn('  missing from the database: 1\n', block)
        self.assertIn('  missing from the database, first 5 of 1:\n    T sources/other.m\n', block)

    def test_missing_unit_exit_3_with_no_rows(self):
        self.delete_unit('sources/other.m')
        status, rows, block = self.query('noSuchSelector')
        self.assertEqual((status, rows), (3, []))
        self.assertIn('INCOMPLETE', block)

    def test_command_and_extractor_change_are_marked(self):
        self.sql("UPDATE tu SET cmd_digest='changed', extractor_version='0' WHERE main_file='sources/sends.m'")
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('sources/sends.m:19:11  -[Widget run]  receiver Widget *  targets T  STALE (command changed)', rows)
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T', rows)
        self.assertIn('  stale: 1 (command changed 1)\n', block)
        self.assertIn('  stale, first 5 of 1:\n    T sources/sends.m: command changed\n', block)
        self.assertIn('INCOMPLETE: 1 of 2 units are not current (stale 1, missing 0, failed 0, not in the compile '
                      'database 0, recorded with parse errors 0)', block)

    def test_extractor_change_is_marked(self):
        self.sql("UPDATE tu SET extractor_version='0' WHERE main_file='sources/other.m'")
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  STALE (extractor changed)',
                      self.query('doThing')[1])

    def test_sdk_change_is_marked(self):
        self.sql("UPDATE tu SET sdk_version='0' WHERE main_file='sources/other.m'")
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  STALE (SDK changed)',
                      self.query('doThing')[1])

    def test_compiler_change_is_marked(self):
        # The unit was extracted with another Homebrew LLVM than the one the
        # extractor runs on now.
        self.sql("UPDATE tu SET clang_version='Homebrew clang version 22.1.7' WHERE main_file='sources/other.m'")
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  STALE (compiler changed)', rows)
        self.assertIn('sources/sends.m:19:11  -[Widget run]  receiver Widget *  targets T', rows)
        self.assertIn('  stale: 1 (compiler changed 1)\n', block)

    def test_update_extracts_again_a_unit_extracted_with_another_compiler(self):
        self.sql("UPDATE tu SET clang_version='Homebrew clang version 22.1.7' WHERE main_file='sources/other.m'")
        log = []
        self.assertEqual(codedb.update(self.paths, log=log.append), 0, log)
        self.assertTrue(any(m.startswith('[1/1] T sources/other.m (compiler changed): ok') for m in log), log)
        self.assertEqual(self.query('doThing')[0], 0)

    def test_sdk_update_at_the_same_path_makes_the_answer_incomplete(self):
        self.assertEqual(self.query('doThing')[0], 0)
        fake_sdk(self, '/sdk', '2')
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  STALE (SDK changed)', rows)
        self.assertIn('sources/sends.m:19:11  -[Widget run]  receiver Widget *  targets T  STALE (SDK changed)', rows)
        self.assertIn('  stale: 2 (SDK changed 2)\n', block)
        self.assertIn('INCOMPLETE: 2 of 2 units are not current (stale 2,', block)

    def test_changed_input_is_marked_with_its_path(self):
        with open(os.path.join(self.root, 'sources/other.m'), 'a') as f:
            f.write('// edited after extraction\n')
        status, rows, block = self.query('doThing')
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  STALE (input changed: sources/other.m)', rows)
        self.assertIn('sources/sends.m:19:11  -[Widget run]  receiver Widget *  targets T', rows)
        self.assertEqual(sum('STALE' in r for r in rows), 1)
        self.assertIn('rows printed: 5; from units that are not current: 1 (marked)\n', block)
        # The header row comes from both units; one of them is stale.
        self.assertIn('sources/helpers.h:4:8  Helper  receiver Widget *  targets T  STALE (input changed: sources/other.m)',
                      self.query('helperSend')[1])

    def test_unit_not_in_the_compile_database_is_marked(self):
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',), meta={'sdk_path': '/sdk', 'sdk_version': '1'})
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('INCOMPLETE: 1 of 2 units are not current (stale 0, missing 0, failed 0, not in the compile '
                      'database 1, recorded with parse errors 0)', block)
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  NOT IN THE COMPILE DATABASE', rows)
        self.assertIn('  in the database, not in the compile database: 1\n', block)

    def test_failed_unit_makes_the_answer_incomplete(self):
        with open(os.path.join(self.root, 'sources/other.m'), 'a') as f:
            f.write('// edited\n')
        self.paths.extractor = fake_extractor(os.path.join(os.path.dirname(self.root), 'bad'), 'exit 5')
        codedb.update(self.paths, log=lambda m: None)
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('sources/other.m:4:8  Other  receiver Widget *  targets T  FAILED (last extraction failed: status 5; '
                      'these rows are from an earlier extraction)', rows)
        self.assertIn('  last extraction failed: 1\n', block)
        self.assertIn('INCOMPLETE: 1 of 2 units', block)

    def test_parse_errors_make_the_answer_incomplete(self):
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m', 'sources/broken.m'),
                  meta={'sdk_path': '/sdk', 'sdk_version': '1'})
        codedb.update(self.paths, log=lambda m: None)
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('sources/broken.m:5:11  -[Widget(Broken) broken]  receiver Widget *  targets T  UNIT HAS PARSE ERRORS',
                      rows)
        self.assertIn('  recorded with parse errors: 1\n', block)

    def test_send_added_to_a_stale_unit_makes_the_answer_incomplete(self):
        # The new send has no row to mark; only the INCOMPLETE line tells.
        with open(os.path.join(self.root, 'sources/other.m'), 'a') as f:
            f.write('void Added(Widget *w) { [w makeThing]; }\n')
        status, rows, block = self.query('makeThing')
        self.assertEqual(status, 3)
        self.assertNotIn('other.m', '\n'.join(rows))
        lines = block.splitlines()
        self.assertEqual(lines[0], 'INCOMPLETE: 1 of 2 units are not current (stale 1, missing 0, failed 0, not in the '
                                   'compile database 0, recorded with parse errors 0); sends in them may be missing '
                                   'or wrong. Run codedb.py update, or ask with sends --update.')
        self.assertEqual(lines[-1], lines[0])

    def test_stale_unit_with_no_rows_exits_3(self):
        with open(os.path.join(self.root, 'sources/other.m'), 'a') as f:
            f.write('// edited\n')
        status, rows, block = self.query('noSuchSelector')
        self.assertEqual((status, rows), (3, []))

    def test_sends_with_update_extracts_first_then_answers(self):
        with open(os.path.join(self.root, 'sources/other.m'), 'a') as f:
            f.write('void Added(Widget *w) { [w makeThing]; }\n')
        out, err = io.StringIO(), io.StringIO()
        sys_stdout, sys_stderr = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            status = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                  '--extractor', EXTRACTOR, 'sends', '--update', 'makeThing'])
        finally:
            sys.stdout, sys.stderr = sys_stdout, sys_stderr
        self.assertEqual(status, 0, out.getvalue() + err.getvalue())
        self.assertIn('sources/other.m:6:28  Added  receiver Widget *  targets T\n', out.getvalue())
        self.assertNotIn('INCOMPLETE', out.getvalue())
        # The update's progress goes to stderr, so stdout is only the answer.
        self.assertIn('T sources/other.m (input changed: sources/other.m): ok', err.getvalue())
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(self.paths.cdb), 'codedb.lock')))

    def test_no_compile_database_is_incomplete(self):
        os.remove(self.paths.cdb)
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('no compile database at %s' % self.paths.cdb, block)


COVERAGE_PROJECT = r'''// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 77;
	objects = {
		ROOT = {isa = PBXGroup; children = (SRC, MT, ); sourceTree = "<group>"; };
		SRC = {isa = PBXGroup; children = (FS, FO, ); path = sources; sourceTree = "<group>"; };
		FS = {isa = PBXFileReference; path = sends.m; sourceTree = "<group>"; };
		FO = {isa = PBXFileReference; path = other.m; sourceTree = "<group>"; };
		BS = {isa = PBXBuildFile; fileRef = FS; };
		BO = {isa = PBXBuildFile; fileRef = FO; };
		PH = {isa = PBXSourcesBuildPhase; files = (BS, BO, ); };
		TA = {isa = PBXNativeTarget; name = T; buildPhases = (PH, ); fileSystemSynchronizedGroups = (MT, ); };
		MT = {isa = PBXFileSystemSynchronizedRootGroup; path = ModernTests; sourceTree = "<group>"; exceptions = (); };
	};
	rootObject = ROOT;
}
'''

KNOWN_NOT_PARSED = ('Not parsed: callers in these files are NOT in this database\n'
                    '  8 implementation files (.c, .m, .mm, .cpp, .cc, .cxx) in the repository are in no unit of the '
                    'compile database:\n'
                    '  (a) built by another Xcode project or Swift package: 0\n'
                    '  (b) under submodules/: 0\n'
                    '  (c) compiled by a target of iTerm2.xcodeproj, but in no unit: 0\n'
                    '  (d) compiled by no target of any project found: 8\n'
                    '    ThirdParty/Other/tpclient.m\n    pidinfo/gitclient.m\n    sources/broken.m\n    sources/globals.m\n'
                    '    sources/lambda.mm\n    sources/macros.m\n    sources/unevaluated.m\n    sources/unevaluated_cxx.mm\n' +
    TOOLS_NOT_LISTED)


class QueryCoverageTest(unittest.TestCase):
    """Every query checks that the compile database covers the project's
    sources and the in-scope files on disk."""

    def setUp(self):
        self.root = make_root()
        self.paths = make_paths(self.root)
        os.mkdir(os.path.join(self.root, 'ModernTests'))
        self.pbx = os.path.join(self.root, 'iTerm2.xcodeproj', 'project.pbxproj')
        os.makedirs(os.path.dirname(self.pbx))
        with open(self.pbx, 'w') as f:
            f.write(COVERAGE_PROJECT)
        write_cdb(self.root, self.paths.cdb, project=False)
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)

    def query(self, selector):
        out = io.StringIO()
        status = codedb.sends(self.paths, selector, out=out)
        rows, _, block = out.getvalue().partition('\n--- status ---\n')
        return status, rows.splitlines(), block

    def test_covered_project_lists_the_files_that_are_not_parsed(self):
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 0, block)
        self.assertNotIn('INCOMPLETE', block)
        self.assertIn('compile database coverage: complete\n' + KNOWN_NOT_PARSED, block)

    def test_file_added_to_a_synchronized_folder_makes_the_answer_incomplete(self):
        self.assertEqual(self.query('doThing')[0], 0)
        with open(os.path.join(self.root, 'ModernTests', 'New.m'), 'w') as f:
            f.write('#import "widget.h"\nvoid N(Widget *w) { [w doThing]; }\n')
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        lines = block.splitlines()
        self.assertEqual(lines[0], 'INCOMPLETE: the compile database does not cover the project (not covered 1, no '
                                   'longer in the project 0); sends in those files may be missing or wrong. Run '
                                   'capture_compile_commands.sh, then codedb.py update.')
        self.assertEqual(lines[-1], lines[0])
        self.assertIn('compile database coverage: DOES NOT COVER THE PROJECT\n'
                      '  not covered by the compile database, first 5 of 1:\n'
                      '    ModernTests/New.m (T)\n' + KNOWN_NOT_PARSED.replace(
                          '  8 implementation', '  9 implementation').replace(
                          '(c) compiled by a target of iTerm2.xcodeproj, but in no unit: 0\n',
                          '(c) compiled by a target of iTerm2.xcodeproj, but in no unit: 1\n'
                          '    T: 1 (captured; such files are listed as not covered above)\n'), block)

    def test_file_added_to_a_target_makes_the_answer_incomplete(self):
        self.assertEqual(self.query('doThing')[0], 0)
        with open(self.pbx) as f:
            text = f.read()
        with open(self.pbx, 'w') as f:
            f.write(text.replace('children = (FS, FO, );', 'children = (FS, FO, FM, );')
                    .replace('files = (BS, BO, );', 'files = (BS, BO, BM, );')
                    .replace('\t\tPH = ', '\t\tFM = {isa = PBXFileReference; path = macros.m; sourceTree = "<group>"; };\n'
                             '\t\tBM = {isa = PBXBuildFile; fileRef = FM; };\n\t\tPH = '))
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('  not covered by the compile database, first 5 of 1:\n    sources/macros.m (T)\n'
                      'Not parsed: callers in these files are NOT in this database\n', block)
        self.assertIn('  (c) compiled by a target of iTerm2.xcodeproj, but in no unit: 1\n'
                      '    T: 1 (captured; such files are listed as not covered above)\n'
                      '  (d) compiled by no target of any project found: 7\n', block)

    def test_unit_dropped_from_the_compile_database_is_not_covered(self):
        self.assertEqual(self.query('doThing')[0], 0)
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',), project=False)
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('  not covered by the compile database, first 5 of 1:\n    sources/other.m (T)\n', block)

    def test_no_project_file_makes_the_answer_incomplete(self):
        os.remove(self.pbx)
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 3)
        self.assertIn('INCOMPLETE: there is no project file at %s, so the compile database cannot be checked against '
                      'the project.' % self.pbx, block)

    def test_coverage_is_cached(self):
        first = self.query('doThing')
        real = codedb.project_sources

        def refuse(*a, **k):
            raise AssertionError('the coverage was computed again')
        codedb.project_sources = refuse
        try:
            self.assertEqual(self.query('doThing'), first)
        finally:
            codedb.project_sources = real


SETTINGS_PROJECT = r'''// !$*UTF8*$!
{
	archiveVersion = 1;
	objectVersion = 77;
	objects = {
		ROOT = {isa = PBXGroup; children = (SRC, LOC, ); sourceTree = "<group>"; };
		SRC = {isa = PBXGroup; children = (FS, FO, ); path = sources; sourceTree = "<group>"; };
		FS = {isa = PBXFileReference; path = sends.m; sourceTree = "<group>"; };
		FO = {isa = PBXFileReference; path = other.m; sourceTree = "<group>"; };
		LOC = {isa = PBXVariantGroup; children = (LEN, ); name = Localizable.strings; sourceTree = "<group>"; };
		LEN = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = en; path = en.lproj/Localizable.strings; sourceTree = "<group>"; };
		BS = {isa = PBXBuildFile; fileRef = FS; };
		BO = {isa = PBXBuildFile; fileRef = FO; settings = {COMPILER_FLAGS = "-fno-objc-arc"; }; };
		PH = {isa = PBXSourcesBuildPhase; files = (BS, BO, ); };
		CT = {isa = XCBuildConfiguration; buildSettings = {OTHER_CFLAGS = "-DITERM2_SHARED_ARC=1"; HEADER_SEARCH_PATHS = (x, ); }; name = Development; };
		CL = {isa = XCConfigurationList; buildConfigurations = (CT, ); defaultConfigurationName = Development; };
		CP = {isa = XCBuildConfiguration; buildSettings = {GCC_PREPROCESSOR_DEFINITIONS = "DEBUG=1"; }; name = Development; };
		CPL = {isa = XCConfigurationList; buildConfigurations = (CP, ); defaultConfigurationName = Development; };
		TA = {isa = PBXNativeTarget; name = T; buildConfigurationList = CL; buildPhases = (PH, ); };
		PRJ = {isa = PBXProject; buildConfigurationList = CPL; mainGroup = ROOT; targets = (TA, ); };
	};
	rootObject = PRJ;
}
'''

SETTINGS_INCOMPLETE = ('INCOMPLETE: the build settings changed since the compile commands were captured; capture again '
                       'with capture_compile_commands.sh, then run codedb.py update.')


def write_fixture_fragments(root, frags, mains, target='T'):
    """Clang fragments, as a capture writes them, for fixture files."""
    os.makedirs(frags, exist_ok=True)
    for i, m in enumerate(mains):
        out = os.path.join(root, 'Build/Intermediates.noindex/Variant-NoSanitizers/iTerm2.build/Development/'
                                 '%s.build/Objects-normal/arm64/u%d.o' % (target, i))
        frag = {'directory': root, 'file': os.path.join(root, m), 'output': out,
                'arguments': ['/Xcode/clang'] + clang_args(root, m) + ['-o', out, '-c']}
        with open(os.path.join(frags, 'u%d.json' % i), 'w') as f:
            f.write(json.dumps(frag) + ',\n')
    mark_captured(frags, root)


class BuildSettingsTest(unittest.TestCase):
    """A change to anything in the project file that can change what is
    compiled makes the answer incomplete; other project file changes do
    not. The real project uses no .xcconfig files (no
    baseConfigurationReference), so the xcconfig case is a fixture only."""

    def setUp(self):
        self.root = make_root()
        work = os.path.dirname(self.root)
        self.paths = codedb.Paths(self.root, db=os.path.join(work, 'db.sqlite'), cdb=os.path.join(work, 'cdb.jsonl'),
                                  fragments=os.path.join(work, 'frags'), extractor=EXTRACTOR)
        self.pbx = os.path.join(self.root, 'iTerm2.xcodeproj', 'project.pbxproj')
        os.makedirs(os.path.dirname(self.pbx))
        self.write_project(SETTINGS_PROJECT)
        write_fixture_fragments(self.root, self.paths.fragments, ('sources/sends.m', 'sources/other.m'))
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)

    def write_project(self, text):
        with open(self.pbx, 'w') as f:
            f.write(text)

    def edit_project(self, old, new):
        with open(self.pbx) as f:
            text = f.read()
        self.assertIn(old, text)
        self.write_project(text.replace(old, new))

    def query(self):
        out = io.StringIO()
        status = codedb.sends(self.paths, 'doThing', out=out)
        return status, out.getvalue().partition('\n--- status ---\n')[2]

    def assert_incomplete(self):
        status, block = self.query()
        self.assertEqual(status, 3, block)
        lines = block.splitlines()
        self.assertEqual(lines[0], SETTINGS_INCOMPLETE)
        self.assertEqual(lines[-1], SETTINGS_INCOMPLETE)

    def test_unchanged_is_complete(self):
        status, block = self.query()
        self.assertEqual(status, 0, block)

    def test_flag_change_makes_the_answer_incomplete(self):
        self.edit_project('OTHER_CFLAGS = "-DITERM2_SHARED_ARC=1";',
                          'OTHER_CFLAGS = "-DITERM2_SHARED_ARC=1 -DSOMETHING_NEW=1";')
        self.assert_incomplete()
        log = []
        self.assertEqual(codedb.update(self.paths, log=log.append), 1)
        self.assertIn('COMPILE DATABASE OUT OF DATE: the build settings changed since the compile commands were '
                      'captured; run capture_compile_commands.sh', log)

    def test_list_valued_setting_change_makes_the_answer_incomplete(self):
        self.edit_project('HEADER_SEARCH_PATHS = (x, );', 'HEADER_SEARCH_PATHS = (x, y, );')
        self.assert_incomplete()

    # A flag change made after the capture is remembered when the compile
    # database is built again from the same fragments, whatever rebuilds it.
    FLAG_EDIT = ('OTHER_CFLAGS = "-DITERM2_SHARED_ARC=1";', 'OTHER_CFLAGS = "-DITERM2_SHARED_ARC=1 -DSOMETHING_NEW=1";')

    def test_flag_change_survives_a_rebuild_because_the_tool_is_newer(self):
        self.edit_project(*self.FLAG_EDIT)
        self.assert_incomplete()
        # codedb.py is newer than the compile database (a pull that updates
        # the tool), so update builds it again from the fragments.
        os.utime(self.paths.cdb, (1, 1))
        log = []
        self.assertEqual(codedb.update(self.paths, log=log.append), 1, log)
        self.assertTrue(any(m.startswith('compile database: 2 units from 2 fragments') for m in log), log)
        self.assert_incomplete()

    def test_flag_change_survives_a_rebuild_for_a_new_sdk(self):
        self.edit_project(*self.FLAG_EDIT)
        self.assert_incomplete()
        sdk_path, _ = codedb.current_sdk()
        fake_sdk(self, sdk_path, '0.1')
        log = []
        self.assertEqual(codedb.update(self.paths, log=log.append), 1, log)
        self.assertEqual(next(codedb.read_cdb(self.paths.cdb))['sdk_version'], '0.1')
        self.assert_incomplete()

    def test_flag_change_survives_the_cdb_command(self):
        self.edit_project(*self.FLAG_EDIT)
        out = io.StringIO()
        sys_stdout = sys.stdout
        sys.stdout = out
        try:
            status = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb, '--fragments',
                                  self.paths.fragments, '--extractor', EXTRACTOR, 'cdb'])
        finally:
            sys.stdout = sys_stdout
        self.assertEqual(status, 1, out.getvalue())
        self.assert_incomplete()

    def test_per_file_flag_change_makes_the_answer_incomplete(self):
        self.edit_project('COMPILER_FLAGS = "-fno-objc-arc";', 'COMPILER_FLAGS = "-fno-objc-arc -DX=1";')
        self.assert_incomplete()

    def test_project_level_setting_change_makes_the_answer_incomplete(self):
        self.edit_project('GCC_PREPROCESSOR_DEFINITIONS = "DEBUG=1";', 'GCC_PREPROCESSOR_DEFINITIONS = "DEBUG=2";')
        self.assert_incomplete()

    def test_xcconfig_edit_makes_the_answer_incomplete(self):
        os.makedirs(os.path.join(self.root, 'config'))
        xcconfig = os.path.join(self.root, 'config', 'Base.xcconfig')
        with open(xcconfig, 'w') as f:
            f.write('OTHER_CFLAGS = -DA=1\n')
        self.edit_project('name = Development; };\n\t\tCL =',
                          'name = Development; baseConfigurationReference = XC; };\n'
                          '\t\tXC = {isa = PBXFileReference; path = config/Base.xcconfig; sourceTree = SOURCE_ROOT; };\n'
                          '\t\tCL =')
        # A capture made with this project.
        write_capture_record(self.paths.fragments, self.root)
        later = time.time() + 100
        os.utime(os.path.join(self.paths.fragments, '.captured'), (later, later))
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)
        self.assertEqual(self.query()[0], 0)
        with open(xcconfig, 'w') as f:
            f.write('OTHER_CFLAGS = -DA=2\n')
        self.assert_incomplete()

    def test_unrelated_project_change_keeps_the_answer_complete(self):
        self.edit_project('\t\tLEN = ', '\t\t/* a comment */\n\t\tLFR = {isa = PBXFileReference; lastKnownFileType = '
                          'text.plist.strings; name = fr; path = fr.lproj/Localizable.strings; sourceTree = "<group>"; };\n'
                          '\t\tLEN = ')
        self.edit_project('children = (LEN, );', 'children = (LEN, LFR, );')
        status, block = self.query()
        self.assertEqual(status, 0, block)
        self.assertNotIn('INCOMPLETE', block)

    def test_sdk_change_rebuilds_the_compile_database(self):
        # The commands name the SDK (-isysroot), so a new SDK rebuilds
        # the compile database from the fragments.
        sdk_path, _ = codedb.current_sdk()
        fake_sdk(self, sdk_path, '0.1')
        log = []
        self.assertEqual(codedb.update(self.paths, log=log.append), 0, log)
        meta = next(codedb.read_cdb(self.paths.cdb))
        self.assertEqual(meta['sdk_version'], '0.1')
        self.assertTrue(any('(SDK changed): ok' in m for m in log), log)


class SdkTest(unittest.TestCase):
    def xcrun_reports(self, path, version, build):
        d = make_temp('codedb-xcrun-')
        write_executable(os.path.join(d, 'xcrun'), '#!/bin/sh\ncase "$1" in\n  --show-sdk-path) echo %s;;\n'
                         '  --show-sdk-version) echo %s;;\n  --show-sdk-build-version) echo %s;;\n  *) exit 1;;\nesac\n'
                         % (path, version, build))
        old = os.environ['PATH']
        os.environ['PATH'] = d + os.pathsep + old
        self.addCleanup(os.environ.__setitem__, 'PATH', old)

    def test_an_sdk_rebuilt_under_the_same_version_is_another_sdk(self):
        self.xcrun_reports('/stub.sdk', '27.0', '26A425')
        self.assertEqual(codedb.sdk_info(), ('/stub.sdk', '27.0 build 26A425'))
        self.xcrun_reports('/stub.sdk', '27.0', '26A426')
        self.assertEqual(codedb.sdk_info(), ('/stub.sdk', '27.0 build 26A426'))


NOT_PARSED_FILES = {
    # Built by ColorPicker.xcodeproj into a framework the app links; it calls
    # the app back through a delegate.
    'ColorPicker/ColorPicker.xcodeproj/project.pbxproj': '// another project\n',
    'ColorPicker/ColorPicker/CPKColorWell.m': ('- (NSRect)presentationRect {\n    return NSZeroRect;\n}\n'
                                               '- (void)show {\n    NSRect r = _delegate.presentationRect;\n}\n'),
    'ThirdParty/CoreParse/CoreParse.xcodeproj/project.pbxproj': '// another project\n',
    'ThirdParty/CoreParse/CoreParse/Tokenisation/CPTokeniser.m': (
        '- (BOOL)tokeniser:(CPTokeniser *)t shouldConsumeToken:(CPToken *)token {\n    return YES;\n}\n'
        '- (void)run {\n    if ([delegate tokeniser:self shouldConsumeToken:token]) {\n    }\n}\n'),
    'Pkg/Package.swift': '// swift-tools-version:5.9\n',
    'Pkg/Sources/C/c.c': 'int c(void) { return 0; }\n',
    'submodules/lib/lib.m': 'void L(id x) { [x libCall]; }\n',
    'Applescript Tests/AppleScriptTest.m': 'void A(id x) { [x scriptCall]; }\n',
}

NOT_PARSED_SECTION = (
    'Not parsed: callers in these files are NOT in this database\n'
    '  13 implementation files (.c, .m, .mm, .cpp, .cc, .cxx) in the repository are in no unit of the compile '
    'database:\n'
    '  (a) built by another Xcode project or Swift package: 3\n'
    '    ColorPicker/ColorPicker.xcodeproj: 1\n'
    '    Pkg/Package.swift: 1\n'
    '    ThirdParty/CoreParse/CoreParse.xcodeproj: 1\n'
    '  (b) under submodules/: 1\n'
    '  (c) compiled by a target of iTerm2.xcodeproj, but in no unit: 1\n'
    '    iTerm2ForApplescriptTesting: 1 (not captured)\n'
    '  (d) compiled by no target of any project found: 8\n'
    '    ThirdParty/Other/tpclient.m\n    pidinfo/gitclient.m\n    sources/broken.m\n    sources/globals.m\n'
    '    sources/lambda.mm\n    sources/macros.m\n    sources/unevaluated.m\n    sources/unevaluated_cxx.mm\n' +
    TOOLS_NOT_LISTED)

TEXT_MATCH_INCOMPLETE = ('INCOMPLETE: no rows, but files that are not parsed mention the selector (text matches: %d, '
                         'listed under Possible callers); callers in them are not in this database.')


class NotParsedTest(unittest.TestCase):
    """C-family files in the repository that no unit covers: other Xcode
    projects and packages, submodules, uncaptured targets of the main
    project, and files in no project. Every query counts them, and searches
    them as text for the selector."""

    def setUp(self):
        self.root = make_root()
        self.paths = make_paths(self.root)
        for p, text in NOT_PARSED_FILES.items():
            os.makedirs(os.path.dirname(os.path.join(self.root, p)), exist_ok=True)
            with open(os.path.join(self.root, p), 'w') as f:
                f.write(text)
        write_project(self.root, {'T': ['sources/sends.m', 'sources/other.m'],
                                  'iTerm2ForApplescriptTesting': ['Applescript Tests/AppleScriptTest.m']})
        write_cdb(self.root, self.paths.cdb, project=False)
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)

    def query(self, selector):
        out = io.StringIO()
        status = codedb.sends(self.paths, selector, out=out)
        rows, _, block = out.getvalue().partition('\n--- status ---\n')
        return status, rows.splitlines(), block

    def test_every_query_counts_the_files_that_are_not_parsed(self):
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 0, block)
        self.assertIn(NOT_PARSED_SECTION, block)
        self.assertNotIn('are compiled by no target', block)
        self.assertIn('  - code built by other Xcode projects and Swift packages, which is not parsed, and code under '
                      'submodules/ (see Not parsed): ColorPicker/ColorPicker.xcodeproj, Pkg/Package.swift, '
                      'ThirdParty/CoreParse/CoreParse.xcodeproj\n', block)

    def test_uncaptured_target_note_is_true(self):
        # Applescript Tests/ is outside the migration's scope, so the file is
        # not listed as not covered; it is counted as not parsed.
        status, rows, block = self.query('doThing')
        self.assertIn('  note: project target iTerm2ForApplescriptTesting compiles 1 file(s) and was not captured; 1 '
                      'of them no captured target compiles, so they are not parsed (Not parsed, class c)\n', block)
        self.assertNotIn('listed as not covered\n', block)
        self.assertNotIn('not covered by the compile database', block)

    def test_rows_and_text_matches_exit_0(self):
        status, rows, block = self.query('doThing')
        self.assertEqual(status, 0, block)
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 5\n' + TEXT_SEARCH_FORMS +
                      '    ThirdParty/Other/tpclient.m:4 (message send): [w doThing];\n'
                      '    pidinfo/gitclient.m:4 (message send): [w doThing];\n'
                      '    sources/broken.m:5 (message send): [self doThing];\n'
                      '    sources/globals.m:5 (message send): static void (^gBlock)(void) = ^{ [gWidget doThing]; };\n'
                      '    sources/lambda.mm:4 (message send): auto f = [w]() { [w doThing]; };\n', block)
        self.assertNotIn('INCOMPLETE', block)

    def test_property_read_in_another_project_exits_3_with_the_call_site(self):
        status, rows, block = self.query('presentationRect')
        self.assertEqual((status, rows), (3, []), block)
        lines = block.splitlines()
        self.assertEqual(lines[0], TEXT_MATCH_INCOMPLETE % 1)
        self.assertEqual(lines[1], 'No rows does not mean no callers: 13 implementation files in the repository are '
                                   'not parsed (see Not parsed)')
        self.assertEqual(lines[-1], lines[0])
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 1\n' + TEXT_SEARCH_FORMS +
                      '    ColorPicker/ColorPicker/CPKColorWell.m:5 (dot syntax, property presentationRect): NSRect r = _delegate.presentationRect;\n', block)

    def test_keyword_send_in_another_project_exits_3_with_the_call_site(self):
        status, rows, block = self.query('tokeniser:shouldConsumeToken:')
        self.assertEqual((status, rows), (3, []), block)
        self.assertEqual(block.splitlines()[0], TEXT_MATCH_INCOMPLETE % 1)
        # The method's definition is not a match; the send is.
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 1\n' + TEXT_SEARCH_FORMS +
                      '    ThirdParty/CoreParse/CoreParse/Tokenisation/CPTokeniser.m:5 (message send): if ([delegate tokeniser:self '
                      'shouldConsumeToken:token]) {\n', block)

    def test_no_rows_and_no_text_match_exits_1_and_says_so(self):
        status, rows, block = self.query('noSuchSelectorAnywhere')
        self.assertEqual((status, rows), (1, []), block)
        self.assertEqual(block.splitlines()[0], 'No rows does not mean no callers: 13 implementation files in the '
                                                'repository are not parsed (see Not parsed)')
        self.assertNotIn('Possible callers', block)
        self.assertNotIn('INCOMPLETE', block)

    def test_text_search_stops_after_50_matches(self):
        with open(os.path.join(self.root, 'submodules', 'lib', 'many.m'), 'w') as f:
            f.write('    [x manyHits];\n' * 60)
        status, rows, block = self.query('manyHits')
        self.assertEqual(status, 3, block)
        self.assertEqual(block.splitlines()[0], TEXT_MATCH_INCOMPLETE % 50)
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 50 (the search stopped '
                      'at 50 matches)\n' + TEXT_SEARCH_FORMS, block)
        self.assertIn('    submodules/lib/many.m:50 (message send): [x manyHits];\n', block)
        self.assertNotIn('many.m:51:', block)

    def write(self, path, text):
        p = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(text)

    def test_setter_written_with_dot_syntax_exits_3_with_the_call_site(self):
        # ColorPicker's CPKSliderView sets its property as self.selectedValue = ...
        self.write('ColorPicker/ColorPicker/CPKSliderView.m',
                   '- (void)setSelectedValue:(CGFloat)v {\n}\n- (void)reset {\n    self.selectedValue = 0.5;\n}\n')
        status, rows, block = self.query('setSelectedValue:')
        self.assertEqual((status, rows), (3, []), block)
        self.assertEqual(block.splitlines()[0], TEXT_MATCH_INCOMPLETE % 1)
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 1\n' + TEXT_SEARCH_FORMS +
                      '    ColorPicker/ColorPicker/CPKSliderView.m:4 (dot syntax, property selectedValue): '
                      'self.selectedValue = 0.5;\n', block)

    def test_is_getter_read_with_dot_syntax_exits_3_with_the_call_site(self):
        self.write('submodules/lib/flag.m', '@property (getter=isFlagged) BOOL flagged;\nvoid F(Flag *x) {\n'
                                            '    if (x.flagged) {\n    }\n}\n')
        status, rows, block = self.query('isFlagged')
        self.assertEqual((status, rows), (3, []), block)
        self.assertEqual(block.splitlines()[0], TEXT_MATCH_INCOMPLETE % 1)
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 1\n' + TEXT_SEARCH_FORMS +
                      '    submodules/lib/flag.m:3 (dot syntax, property flagged): if (x.flagged) {\n', block)

    def test_setter_shaped_selector_whose_property_is_only_read_exits_3(self):
        self.write('submodules/lib/tint.m', 'NSColor *T(View *v, Old *o) {\n    o.Tint = nil;\n    return v.tint;\n}\n')
        status, rows, block = self.query('setTint:')
        self.assertEqual((status, rows), (3, []), block)
        self.assertEqual(block.splitlines()[0], TEXT_MATCH_INCOMPLETE % 2)
        self.assertIn('Possible callers in files that are not parsed (text search, unverified): 2\n' + TEXT_SEARCH_FORMS +
                      '    submodules/lib/tint.m:2 (dot syntax, property Tint): o.Tint = nil;\n'
                      '    submodules/lib/tint.m:3 (dot syntax, property tint): return v.tint;\n', block)

    def test_a_longer_property_name_is_not_a_match(self):
        self.write('submodules/lib/tint.m', 'void T(View *v) {\n    v.tintColor = nil;\n    v.foobar = 1;\n'
                                            '    [v setTintColor:nil];\n    v.isTint = 0;\n}\n')
        status, rows, block = self.query('setTint:')
        self.assertEqual((status, rows), (1, []), block)
        self.assertNotIn('Possible callers', block)
        self.assertEqual(self.query('setFoo:')[0], 1)
        self.assertEqual(self.query('foo')[0], 1)

    def test_implementation_file_that_a_compiled_file_includes_is_parsed(self):
        # As PTYWindow.m includes iTermWindowImpl.m.
        self.write('sources/window_impl.m', '#import "widget.h"\nvoid WindowImpl(Widget *w) { [w implCall]; }\n')
        self.write('sources/window.m', '#include "window_impl.m"\n')
        mains = ('sources/sends.m', 'sources/other.m', 'sources/window.m')
        write_project(self.root, {'T': list(mains),
                                  'iTerm2ForApplescriptTesting': ['Applescript Tests/AppleScriptTest.m']})
        write_cdb(self.root, self.paths.cdb, mains=mains, project=False)
        self.assertEqual(codedb.update(self.paths, log=lambda m: None), 0)
        status, rows, block = self.query('implCall')
        self.assertEqual(status, 0, block)
        self.assertEqual(rows, ['sources/window_impl.m:2:33  WindowImpl  receiver Widget *  targets T'])
        self.assertIn(NOT_PARSED_SECTION, block)
        self.assertNotIn('Possible callers', block)

    def test_the_migration_tools_and_fixtures_are_not_listed(self):
        self.write('tools/swift_migration/codedb/tests/fixtures/sources/tool.m', 'void X(id x) { [x toolCall]; }\n')
        self.write('tools/swift_migration/codedb/extractor/tool.cpp', 'void Y(id x) { [x toolCall]; }\n')
        self.write('tools/other/keep.m', 'void Z(id x) { [x keepCall]; }\n')
        status, rows, block = self.query('toolCall')
        self.assertEqual((status, rows), (1, []), block)
        self.assertNotIn('Possible callers', block)
        self.assertNotIn('tools/swift_migration/codedb/tests', block)
        self.assertIn(
            '  14 implementation files (.c, .m, .mm, .cpp, .cc, .cxx) in the repository are in no unit of the compile '
            'database:\n'
            '  (a) built by another Xcode project or Swift package: 3\n'
            '    ColorPicker/ColorPicker.xcodeproj: 1\n'
            '    Pkg/Package.swift: 1\n'
            '    ThirdParty/CoreParse/CoreParse.xcodeproj: 1\n'
            '  (b) under submodules/: 1\n'
            '  (c) compiled by a target of iTerm2.xcodeproj, but in no unit: 1\n'
            '    iTerm2ForApplescriptTesting: 1 (not captured)\n'
            '  (d) compiled by no target of any project found: 9\n'
            '    ThirdParty/Other/tpclient.m\n    pidinfo/gitclient.m\n    sources/broken.m\n    sources/globals.m\n'
            '    sources/lambda.mm\n    sources/macros.m\n    sources/unevaluated.m\n    sources/unevaluated_cxx.mm\n'
            '    tools/other/keep.m\n'
            "  files under tools/swift_migration/ are the migration's own tools and fixtures and are not listed\n",
            block)
        self.assertEqual(self.query('keepCall')[0], 3)



LOOP = 'import time\nwhile True: time.sleep(0.2)\n'


def start_time(pid):
    """The process's start time as ps prints it, whitespace collapsed, or ''."""
    out = subprocess.run(['ps', '-o', 'lstart=', '-p', str(pid)], capture_output=True, text=True).stdout
    return ' '.join(out.split())


def command_of(pid):
    out = subprocess.run(['ps', '-o', 'command=', '-p', str(pid)], capture_output=True, text=True).stdout
    return out.strip()


class LockTest(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.paths = make_paths(self.root)
        write_cdb(self.root, self.paths.cdb)
        self.lock = os.path.join(os.path.dirname(self.paths.cdb), 'codedb.lock')

    def main(self, *args):
        err = io.StringIO()
        sys_stderr, sys_stdout = sys.stderr, sys.stdout
        sys.stderr, sys.stdout = err, io.StringIO()
        try:
            status = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                  '--extractor', EXTRACTOR] + list(args))
        finally:
            sys.stderr, sys.stdout = sys_stderr, sys_stdout
        return status, err.getvalue()

    def hold(self, command='capture_compile_commands.sh'):
        """Hold the lock in this process, as another operation would."""
        lock = codedb.Lock(self.lock, command, log=lambda m: None)
        lock.acquire()
        self.addCleanup(lock.release)
        return lock

    def test_update_exits_2_while_another_holds_the_lock(self):
        self.hold()
        status, err = self.main('update')
        self.assertEqual(status, 2)
        self.assertIn('pid %d: capture_compile_commands.sh' % os.getpid(), err)
        self.assertFalse(os.path.exists(self.paths.db))
        self.assertTrue(os.path.exists(self.lock))

    def test_cdb_exits_2_while_another_holds_the_lock(self):
        self.hold('codedb.py update')
        status, err = self.main('cdb')
        self.assertEqual(status, 2)
        self.assertIn('pid %d: codedb.py update' % os.getpid(), err)

    def test_stale_lock_is_replaced(self):
        p = subprocess.Popen(['true'])
        p.wait()
        with open(self.lock, 'w') as f:
            f.write('%d\ncodedb.py update\n' % p.pid)
        status, err = self.main('update')
        self.assertEqual(status, 0, err)
        self.assertFalse(os.path.exists(self.lock))

    def test_lock_released_after_update(self):
        self.assertEqual(self.main('update')[0], 0)
        self.assertFalse(os.path.exists(self.lock))

    def write_lock(self, text, age=0):
        with open(self.lock, 'w') as f:
            f.write(text)
        if age:
            then = time.time() - age
            os.utime(self.lock, (then, then))

    def test_lock_records_pid_command_and_start_time(self):
        lock = codedb.Lock(self.lock, 'codedb.py update', log=lambda m: None)
        lock.acquire()
        try:
            with open(self.lock) as f:
                lines = f.read().splitlines()
        finally:
            lock.release()
        self.assertEqual(lines, [str(os.getpid()), 'codedb.py update', start_time(os.getpid())])

    def test_live_pid_with_another_start_time_is_stale(self):
        # The pid was reused by a process started at another time.
        self.write_lock('%d\ncodedb.py update\nThu Jan 1 00:00:00 1970\n' % os.getpid())
        status, err = self.main('update')
        self.assertEqual(status, 0, err)
        self.assertFalse(os.path.exists(self.lock))

    def test_lock_file_naming_a_live_process_is_not_held(self):
        # Only the kernel's lock decides; the pid in the file (pid 1 is alive)
        # is for messages and for cleaning up a child group.
        self.write_lock('1\ncodedb.py update\n%s\n' % start_time(1))
        status, err = self.main('update')
        self.assertEqual(status, 0, err)
        self.assertFalse(os.path.exists(self.lock))

    def test_break_lock_is_gone(self):
        with self.assertRaises(SystemExit):
            self.main('update', '--break-lock')

    def test_empty_lock_file_is_not_held(self):
        self.write_lock('')
        status, err = self.main('update')
        self.assertEqual(status, 0, err)

    def test_old_empty_lock_is_stale(self):
        self.write_lock('', age=60)
        status, err = self.main('update')
        self.assertEqual(status, 0, err)

    def test_lock_is_released_when_its_holder_is_killed(self):
        code = ('import sys, time; sys.path.insert(0, %r); import codedb\n'
                'codedb.Lock(%r, "codedb.py update", log=lambda m: None).acquire()\n'
                'print("held", flush=True)\ntime.sleep(60)\n' % (CODEDB_DIR, self.lock))
        p = subprocess.Popen([sys.executable, '-B', '-c', code], stdout=subprocess.PIPE, text=True,
                             start_new_session=True)
        try:
            self.assertEqual(p.stdout.readline(), 'held\n')
            status, err = self.main('update')
            self.assertEqual(status, 2, err)
            self.assertIn('pid %d: codedb.py update' % p.pid, err)
            os.kill(p.pid, signal.SIGKILL)
            p.wait()
            status, err = self.main('update')
            self.assertEqual(status, 0, err)
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait()
            p.stdout.close()

    def test_two_takers_of_a_stale_lock_never_both_hold_it(self):
        # Two processes start together against a lock file left by a dead
        # holder. Each one that takes the lock creates a sentinel with
        # O_EXCL while it holds it; finding the sentinel there means two
        # holders at once.
        d = make_temp('codedb-race-')
        code = (
            'import os, sys, time\nsys.path.insert(0, sys.argv[1])\nimport codedb\n'
            'lock_path, go, sentinel, ready = sys.argv[2:6]\n'
            'open(ready, "w").close()\n'
            'while not os.path.exists(go): time.sleep(0.001)\n'
            'lock = codedb.Lock(lock_path, "codedb.py update", log=lambda m: None)\n'
            'try:\n    lock.acquire()\nexcept codedb.CodeDBLocked:\n    print("locked"); sys.exit(0)\n'
            'try:\n    fd = os.open(sentinel, os.O_CREAT | os.O_EXCL | os.O_WRONLY)\n'
            'except FileExistsError:\n    print("DOUBLE"); lock.release(); sys.exit(0)\n'
            'time.sleep(0.3)\nos.close(fd); os.remove(sentinel)\nlock.release()\nprint("held")\n')
        outcomes = []
        for trial in range(25):
            self.write_lock('999999\ncodedb.py update\nMon Jan  1 00:00:00 2024\n')
            go = os.path.join(d, 'go-%d' % trial)
            sentinel = os.path.join(d, 'sentinel-%d' % trial)
            ready = [os.path.join(d, 'ready-%d-%d' % (trial, i)) for i in range(2)]
            procs = [subprocess.Popen([sys.executable, '-B', '-c', code, CODEDB_DIR, self.lock, go, sentinel, r],
                                      stdout=subprocess.PIPE, text=True, start_new_session=True) for r in ready]
            try:
                self.assertTrue(wait_until(lambda: all(os.path.exists(r) for r in ready), timeout=30))
                open(go, 'w').close()
                for p in procs:
                    out, _ = p.communicate(timeout=30)
                    outcomes.append(out.strip())
            finally:
                for p in procs:
                    if p.poll() is None:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.wait()
        self.assertNotIn('DOUBLE', outcomes)
        self.assertEqual(len(outcomes), 50)

    def test_update_kills_the_group_left_by_a_killed_update(self):
        marker = 'codedb-test-marker-' + uuid.uuid4().hex
        slow = fake_extractor(os.path.join(os.path.dirname(self.root), 'slow-extractor'),
                              'exec %s -c %s %s' % (sys.executable, "'" + LOOP + "'", marker))
        p = subprocess.Popen([sys.executable, '-B', os.path.join(CODEDB_DIR, 'codedb.py'), '--root', self.root,
                              '--db', self.paths.db, '--cdb', self.paths.cdb, '--extractor', slow, 'update'],
                             start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertTrue(wait_until(lambda: processes_matching(marker)), 'the extraction never started')
            os.kill(p.pid, signal.SIGKILL)
            p.wait()
            # The guard and the extractor are in their own session and survive.
            self.assertTrue(processes_matching(marker))
            status, err = self.main('update')
            self.assertEqual(status, 0, err)
            self.assertTrue(wait_until(lambda: not processes_matching(marker), timeout=10),
                            'the group left by the killed update is still running')
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait()
            kill_matching(marker)

    def test_recorded_group_with_another_start_time_is_not_killed(self):
        marker = 'codedb-test-marker-' + uuid.uuid4().hex
        other = subprocess.Popen([sys.executable, '-c', LOOP, marker], start_new_session=True)
        dead = subprocess.Popen(['true'])
        dead.wait()
        try:
            self.write_lock('%d\ncodedb.py update\nThu Jan 1 00:00:00 1970\nchild %d Thu Jan 1 00:00:00 1970\n'
                            % (dead.pid, other.pid))
            status, err = self.main('update')
            self.assertEqual(status, 0, err)
            self.assertIsNone(other.poll())
        finally:
            os.killpg(other.pid, signal.SIGKILL)
            other.wait()


def skip_if_sigint_ignored(test):
    """A process started with SIGINT ignored (the suite run as a background
    job by a non-interactive shell) passes that on to its children, which
    then cannot be interrupted at all; a test of interruption says so and
    skips, so that the suite gives one result however it is launched."""
    if signal.getsignal(signal.SIGINT) == signal.SIG_IGN:
        test.skipTest('SIGINT is ignored in this process (the suite was started as a background job by a '
                      'non-interactive shell), so its children ignore it too and interruption cannot be tested; '
                      'run the suite in the foreground to test it')


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.marker = 'codedb-test-marker-' + uuid.uuid4().hex

    def tearDown(self):
        kill_matching(self.marker)

    def start_guarded_child(self):
        p = subprocess.Popen([GUARD, '--', sys.executable, '-c', LOOP, self.marker], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.assertTrue(wait_until(lambda: processes_matching(self.marker)), 'the child never started')
        return p

    def assert_child_gone(self, p):
        p.wait(timeout=60)
        self.assertTrue(wait_until(lambda: not processes_matching(self.marker), timeout=30),
                        'the child survived the guard: %s' % processes_matching(self.marker))

    def test_interrupt_to_the_process_group_kills_the_child(self):
        skip_if_sigint_ignored(self)
        p = self.start_guarded_child()
        os.killpg(p.pid, signal.SIGINT)  # what Ctrl-C does to the foreground group
        self.assert_child_gone(p)

    def test_terminate_kills_the_child(self):
        p = self.start_guarded_child()
        os.kill(p.pid, signal.SIGTERM)
        self.assert_child_gone(p)

    def test_hangup_kills_the_child(self):
        p = self.start_guarded_child()
        os.kill(p.pid, signal.SIGHUP)
        self.assert_child_gone(p)

    def test_watchdog_kills_a_tree_over_the_limit(self):
        hog = 'x = b"\\x01" * (400 << 20)\nimport time\ntime.sleep(20)\n'
        r = subprocess.run([GUARD, '--limit-kb', '100000', '--', sys.executable, '-c', hog, self.marker],
                           capture_output=True, text=True, timeout=110)
        self.assertEqual(r.returncode, 137, r.stderr)
        self.assertIn('exceeds 100000 KB', r.stderr)
        self.assertFalse(processes_matching(self.marker))

    def test_status_passed_through(self):
        r = subprocess.run([GUARD, '--', 'sh', '-c', 'exit 7'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 7)

    def spawner(self, grandchild_code):
        """Python code for a child that starts a grandchild running
        grandchild_code, then loops; both carry the marker."""
        # The grandchild does not hold the guard's output pipes, so a
        # surviving grandchild cannot make the guard's caller wait for it.
        return ('import subprocess, sys, time\n'
                'subprocess.Popen([sys.executable, "-c", %r, sys.argv[1]], stdin=subprocess.DEVNULL, '
                'stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n'
                'while True: time.sleep(0.2)\n' % grandchild_code)

    def test_terminate_kills_a_two_level_tree(self):
        p = subprocess.Popen([GUARD, '--', sys.executable, '-c', self.spawner(LOOP), self.marker],
                             start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # The guard, the child and the grandchild all carry the marker.
        self.assertTrue(wait_until(lambda: len(processes_matching(self.marker)) == 3, timeout=30),
                        'the tree never started: %s' % processes_matching(self.marker))
        os.kill(p.pid, signal.SIGTERM)
        p.wait(timeout=60)
        self.assertTrue(wait_until(lambda: not processes_matching(self.marker), timeout=10),
                        'part of the tree survived the guard: %s' % processes_matching(self.marker))

    def test_watchdog_kills_a_two_level_tree(self):
        hog = 'x = b"\\x01" * (400 << 20)\nimport time\nwhile True: time.sleep(0.2)\n'
        r = subprocess.run([GUARD, '--limit-kb', '100000', '--', sys.executable, '-c', self.spawner(hog),
                            self.marker], capture_output=True, text=True, timeout=110, start_new_session=True)
        self.assertEqual(r.returncode, 137, r.stderr)
        self.assertIn('exceeds 100000 KB', r.stderr)
        self.assertTrue(wait_until(lambda: not processes_matching(self.marker), timeout=10),
                        'part of the tree survived the watchdog: %s' % processes_matching(self.marker))


class RunInGroupTest(unittest.TestCase):
    def setUp(self):
        self.marker = 'codedb-test-marker-' + uuid.uuid4().hex

    def tearDown(self):
        kill_matching(self.marker)

    def test_a_process_left_behind_in_the_group_is_killed(self):
        # The command starts a background process that does not hold its
        # output pipes, and exits. run_in_group must kill it. The call runs in
        # its own session under a timeout, so that a broken run_in_group fails
        # the test instead of hanging it, and leaves nothing behind.
        code = ('import sys; sys.path.insert(0, %r); import codedb\n'
                'print(codedb.run_in_group(["sh", "-c", %r]))\n' % (
                    CODEDB_DIR, '"%s" -c "%s" %s >/dev/null 2>&1 </dev/null & echo started' % (
                        sys.executable, LOOP, self.marker)))
        p = subprocess.Popen([sys.executable, '-B', '-c', code], start_new_session=True, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
        try:
            out, err = p.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.communicate()
            self.fail('run_in_group did not return within 30 seconds')
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait()
        self.assertEqual(out, "(0, '')\n", err)
        self.assertTrue(wait_until(lambda: not processes_matching(self.marker), timeout=5),
                        'the background process survived: %s' % processes_matching(self.marker))


class DriverInterruptTest(unittest.TestCase):
    """An interrupted update leaves no extraction running."""

    def setUp(self):
        self.marker = 'codedb-test-marker-' + uuid.uuid4().hex
        self.root = make_root()
        self.paths = make_paths(self.root)
        write_cdb(self.root, self.paths.cdb, mains=('sources/sends.m',))
        self.extractor = fake_extractor(os.path.join(os.path.dirname(self.root), 'slow-extractor'),
                                        'exec %s -c %s %s' % (sys.executable, "'" + LOOP + "'", self.marker))

    def tearDown(self):
        kill_matching(self.marker)

    def run_and_signal(self, sig):
        p = subprocess.Popen([sys.executable, '-B', os.path.join(CODEDB_DIR, 'codedb.py'), '--root', self.root,
                              '--db', self.paths.db, '--cdb', self.paths.cdb, '--extractor', self.extractor,
                              'update'], start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            self.assertTrue(wait_until(lambda: processes_matching(self.marker)), 'the extraction never started')
            if sig == signal.SIGINT:
                os.killpg(p.pid, sig)  # Ctrl-C reaches the driver's foreground group only
            else:
                os.kill(p.pid, sig)
            p.communicate(timeout=60)
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait()
        self.assertNotEqual(p.returncode, 0)
        self.assertTrue(wait_until(lambda: not processes_matching(self.marker), timeout=30),
                        'the extraction survived: %s' % processes_matching(self.marker))
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(self.paths.cdb), 'codedb.lock')))

    def test_interrupt(self):
        skip_if_sigint_ignored(self)
        self.run_and_signal(signal.SIGINT)

    def test_terminate(self):
        self.run_and_signal(signal.SIGTERM)

    def test_hangup(self):
        self.run_and_signal(signal.SIGHUP)


class CaptureScriptTest(unittest.TestCase):
    """capture_compile_commands.sh, run in a scratch tree against a stub
    xcodebuild that writes one fragment and exits with $STUB_STATUS."""

    def setUp(self):
        d = make_temp('codedb-capture-')
        self.root = os.path.join(d, 'root')
        script_dir = os.path.join(self.root, 'tools', 'swift_migration', 'codedb')
        os.makedirs(script_dir)
        shutil.copy(CAPTURE, script_dir)
        shutil.copy(os.path.join(CODEDB_DIR, 'codedb.py'), script_dir)
        # codedb.py imports the Swift side, which the capture runs after the build.
        shutil.copy(os.path.join(CODEDB_DIR, 'swiftdb.py'), script_dir)
        self.script = os.path.join(script_dir, 'capture_compile_commands.sh')
        for p, text in (('xcstrings/Localizable.xcstrings', '{}'), ('plists/dev-iTerm2.plist', 'dev'),
                        ('sources/.keep', '')):
            os.makedirs(os.path.dirname(os.path.join(self.root, p)), exist_ok=True)
            with open(os.path.join(self.root, p), 'w') as f:
                f.write(text)
        self.work = os.path.join(self.root, 'tmp', 'codedb')
        self.frags = os.path.join(self.work, 'cdb-fragments')
        self.partial = os.path.join(self.work, 'cdb-fragments.partial')
        os.makedirs(self.frags)
        os.makedirs(self.partial)
        for path, text in ((os.path.join(self.frags, 'old.json'), '{}'),
                           (os.path.join(self.frags, '.captured'), 'then'),
                           (os.path.join(self.partial, 'stale.json'), '{}'),
                           (os.path.join(self.work, 'compile_commands.jsonl'), 'OLD')):
            with open(path, 'w') as f:
                f.write(text)
        stub = os.path.join(d, 'stub')
        os.mkdir(stub)
        write_executable(os.path.join(stub, 'xcodebuild'),
                         '#!/bin/sh\nfor a in "$@"; do case "$a" in OTHER_CFLAGS=*) dir="${a##* }";; esac; done\n'
                         'echo "$@" > "%s"\n'
                         'echo "{}" > "$dir/new1.json"\n'
                         # STUB_HANG=<marker>: a build that never ends, with a child process.
                         'if [ -n "$STUB_HANG" ]; then\n'
                         '  "%s" -c "%s" "$STUB_HANG" &\n'
                         '  exec "%s" -c "%s" "$STUB_HANG"\n'
                         'fi\n'
                         'echo "error: stub build failed" >&2\n'
                         'exit "${STUB_STATUS:-0}"\n' % (os.path.join(d, 'stub-args'), sys.executable, LOOP,
                                                          sys.executable, LOOP))
        self.stub_args = os.path.join(d, 'stub-args')
        self.lock = os.path.join(self.work, 'codedb.lock')
        self.env = dict(os.environ, PATH=stub + os.pathsep + os.environ['PATH'])

    def run_capture(self, status):
        return subprocess.run([self.script], env=dict(self.env, STUB_STATUS=str(status)), capture_output=True,
                              text=True, timeout=110)

    def test_failed_build_leaves_the_previous_capture(self):
        r = self.run_capture(65)
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sorted(os.listdir(self.frags)), ['.captured', 'old.json'])
        with open(os.path.join(self.work, 'compile_commands.jsonl')) as f:
            self.assertEqual(f.read(), 'OLD')
        # The partial directory was cleared before the build.
        self.assertEqual(sorted(os.listdir(self.partial)), ['new1.json'])
        self.assertFalse(os.path.exists(os.path.join(self.work, 'codedb.lock')))

    def test_successful_build_replaces_the_fragments(self):
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sorted(os.listdir(self.frags)), ['.capture-record', '.captured', 'new1.json'])
        self.assertFalse(os.path.exists(self.partial))
        self.assertFalse(os.path.exists(os.path.join(self.work, 'codedb.lock')))

    def test_successful_build_records_the_build_settings_as_they_were_when_it_started(self):
        write_project(self.root, {'App': ['sources/A.m']})
        at_start = codedb.build_settings_digest(self.root)
        # The stub build renames the target, a build settings change, while
        # it runs; the record keeps the settings the build started with.
        stub = os.path.join(os.path.dirname(self.root), 'stub', 'xcodebuild')
        with open(stub) as f:
            text = f.read()
        with open(stub, 'w') as f:
            f.write(text.replace('#!/bin/sh\n', "#!/bin/sh\nsed -i '' 's/name = App;/name = Renamed;/' '%s'\n"
                                 % codedb.project_file(self.root), 1))
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotEqual(codedb.build_settings_digest(self.root), at_start)
        with open(os.path.join(self.frags, '.capture-record')) as f:
            record = json.load(f)
        sdk_path, sdk_version = codedb.sdk_info()
        self.assertEqual(sorted(record), ['build_settings_sha256', 'captured_at', 'sdk_path', 'sdk_version'])
        self.assertEqual((record['build_settings_sha256'], record['sdk_path'], record['sdk_version']),
                         (at_start, sdk_path, sdk_version))
        self.assertRegex(record['captured_at'], r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')

    def test_failed_build_records_nothing(self):
        write_project(self.root, {'App': ['sources/A.m']})
        r = self.run_capture(65)
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('.capture-record', os.listdir(self.frags))
        self.assertNotIn('.capture-record', os.listdir(self.partial))

    def write_lock(self, text, age=0):
        lock = os.path.join(self.work, 'codedb.lock')
        with open(lock, 'w') as f:
            f.write(text)
        if age:
            then = time.time() - age
            os.utime(lock, (then, then))

    def test_lock_file_naming_a_live_process_is_not_held(self):
        # Only the kernel's lock decides, not the pid in the file.
        self.write_lock('1\ncodedb.py update\n%s\n' % start_time(1))
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_the_build_is_clean(self):
        # An incremental build writes fragments only for the files it
        # recompiles, so the capture cleans the scheme's products first.
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(self.stub_args) as f:
            args = f.read().split()
        self.assertEqual(args[:2], ['clean', 'build-for-testing'])

    def test_live_pid_with_another_start_time_is_stale(self):
        self.write_lock('%d\ncodedb.py update\nThu Jan 1 00:00:00 1970\n' % os.getpid())
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_empty_lock_file_is_not_held(self):
        self.write_lock('')
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_old_empty_lock_is_stale(self):
        self.write_lock('', age=60)
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_lock_records_the_start_time(self):
        lock = os.path.join(self.work, 'codedb.lock')
        stub = os.path.join(os.path.dirname(self.root), 'stub', 'xcodebuild')
        with open(stub) as f:
            text = f.read()
        with open(stub, 'w') as f:
            f.write(text.replace('#!/bin/sh\n', '#!/bin/sh\ncp "%s" "%s.seen"\n' % (lock, lock), 1))
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(lock + '.seen') as f:
            pid, command, start = f.read().splitlines()[:3]
        self.assertEqual(command, 'capture_compile_commands.sh')
        self.assertTrue(start, 'no start time')
        self.assertRegex(start, r'^\w{3} \w{3} +\d+ \d\d:\d\d:\d\d \d{4}$')

    def test_terminate_interrupts_the_build_promptly_and_kills_its_group(self):
        marker = 'codedb-test-marker-' + uuid.uuid4().hex
        p = subprocess.Popen([self.script], env=dict(self.env, STUB_HANG=marker), start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertTrue(wait_until(lambda: len(processes_matching(marker)) == 2, timeout=30),
                            'the stub build never started')
            os.kill(p.pid, signal.SIGTERM)
            try:
                status = p.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.fail('the capture script did not stop within 15 seconds of SIGTERM')
            self.assertEqual(status, 143)
            self.assertTrue(wait_until(lambda: not processes_matching(marker), timeout=10),
                            'the build survived: %s' % processes_matching(marker))
            self.assertFalse(os.path.exists(os.path.join(self.work, 'codedb.lock')))
            self.assertEqual(sorted(os.listdir(self.frags)), ['.captured', 'old.json'])
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
                p.wait()
            kill_matching(marker)

    def test_exits_2_while_another_holds_the_lock(self):
        lock = codedb.Lock(self.lock, 'codedb.py update', log=lambda m: None)
        lock.acquire()
        try:
            r = self.run_capture(0)
        finally:
            lock.release()
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn('pid %d: codedb.py update' % os.getpid(), r.stderr)
        self.assertEqual(sorted(os.listdir(self.frags)), ['.captured', 'old.json'])
        self.assertFalse(os.path.exists(self.stub_args), 'the build ran')

    def codedb_main(self, *args):
        return subprocess.run([sys.executable, '-B', os.path.join(CODEDB_DIR, 'codedb.py'), '--root', self.root,
                               '--extractor', EXTRACTOR] + list(args), capture_output=True, text=True, timeout=60)

    def start_hanging_capture(self, marker):
        p = subprocess.Popen([self.script], env=dict(self.env, STUB_HANG=marker), start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(kill_matching, marker)
        self.assertTrue(wait_until(lambda: len(processes_matching(marker)) == 2, timeout=30),
                        'the stub build never started')
        return p

    def test_update_exits_2_while_a_capture_runs(self):
        marker = 'codedb-test-marker-' + uuid.uuid4().hex
        p = self.start_hanging_capture(marker)
        try:
            r = self.codedb_main('update')
            self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
            self.assertIn('pid %d: capture_compile_commands.sh' % p.pid, r.stderr)
        finally:
            os.kill(p.pid, signal.SIGTERM)
            p.wait(timeout=30)

    def test_build_left_by_a_killed_capture_is_killed_by_the_next_lock_taker(self):
        marker = 'codedb-test-marker-' + uuid.uuid4().hex
        p = self.start_hanging_capture(marker)
        self.assertTrue(wait_until(lambda: 'child ' in read_text(self.lock), timeout=30),
                        'the capture never recorded its build')
        os.kill(p.pid, signal.SIGKILL)
        p.wait()
        # The build is in its own process group and survives.
        self.assertEqual(len(processes_matching(marker)), 2)
        r = self.codedb_main('cdb')
        self.assertIn('killing process group', r.stdout + r.stderr)
        self.assertTrue(wait_until(lambda: not processes_matching(marker), timeout=10),
                        'the build left by the killed capture is still running')

    def test_capture_kills_the_group_left_by_a_killed_update(self):
        marker = 'codedb-test-marker-' + uuid.uuid4().hex
        other = subprocess.Popen([sys.executable, '-c', LOOP, marker], start_new_session=True)
        self.addCleanup(kill_matching, marker)
        dead = subprocess.Popen(['true'])
        dead.wait()
        self.assertTrue(wait_until(lambda: start_time(other.pid)))
        self.write_lock('%d\ncodedb.py update\nThu Jan 1 00:00:00 1970\nchild %d %s\n'
                        % (dead.pid, other.pid, start_time(other.pid)))
        r = self.run_capture(0)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        other.wait(timeout=10)
        self.assertFalse(processes_matching(marker))


if __name__ == '__main__':
    unittest.main()
