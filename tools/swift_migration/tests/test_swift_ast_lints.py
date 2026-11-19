"""Tests for tools/swift_migration/swift_ast_lints.py and its reader,
tools/swift_migration/codedb/swiftreader/swift_ast_facts.cpp.

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_swift_ast_lints.py

The fixtures in fixtures/swift_ast_lints/ are compiled with the Swift
compiler xcrun finds (one compiler process at a time: the tests run
serially). Expectations are literal: line and column numbers are written by
hand. The tests are skipped when the compiler is not the version the reader
was written against (swift_ast_lints.WRITTEN_AGAINST), since the dump format
is not stable across versions. The reader is built once per run into a
temporary directory; the compiler's module cache is kept under
tmp/swift_ast_lints/test-modcache so that later runs are fast.

The command-line tests build temporary git repositories and a capture of
compile commands in the shape codedb.py keeps (drivers.jsonl and a file
list), so they never depend on the real tree or its capture.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOL_DIR))
FIXTURES = os.path.join(HERE, 'fixtures', 'swift_ast_lints')
SCRIPT = os.path.join(TOOL_DIR, 'swift_ast_lints.py')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import swift_ast_lints as al  # noqa: E402
import swift_lints as sl  # noqa: E402

TEMP_DIRS = []
READER = None
MODULE_CACHE = os.path.join(REPO, 'tmp', 'swift_ast_lints', 'test-modcache')
SKIP_REASON = None


def setUpModule():
    global READER, SKIP_REASON
    version = al.compiler_version()
    if version is None or al.major_minor(version) != al.WRITTEN_AGAINST:
        SKIP_REASON = 'the Swift compiler is %r, not Swift %s' % (version, al.WRITTEN_AGAINST)
        return
    d = make_temp()
    READER = al.ensure_reader(os.path.join(d, 'swift_ast_facts'), log=lambda m: None)
    os.makedirs(MODULE_CACHE, exist_ok=True)


def tearDownModule():
    for d in TEMP_DIRS:
        shutil.rmtree(d, ignore_errors=True)


def make_temp():
    d = os.path.realpath(tempfile.mkdtemp(prefix='swift-ast-lints-test-'))
    TEMP_DIRS.append(d)
    return d


def fixture(name):
    return os.path.join(FIXTURES, name)


def standalone(names, header=None):
    """Lints fixture files compiled together as one module. Returns the result of lint_standalone."""
    files = [fixture(n) for n in names]
    return al.lint_standalone(READER, files, header=fixture(header) if header else None,
                              module_cache=MODULE_CACHE)


def triples(result, name):
    findings, _ = result.files[fixture(name)]
    return [(f.line, f.col, f.lint) for f in findings]


class CompilerTestCase(unittest.TestCase):
    def setUp(self):
        if SKIP_REASON:
            self.skipTest(SKIP_REASON)


# ---------------------------------------------------------------------------
# The lints, on fixtures compiled with the compiler

class PointerConversionTests(CompilerTestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = None if SKIP_REASON else standalone(['Pointers.swift'], header='Pointers.h')

    def test_exact_findings(self):
        # Line 11 passes &x to an inout parameter: no conversion. Lines 23, 25 and 30 carry a marker on the line
        # above. Line 28's marker is two lines up; line 29's trailing marker covers line 30, not line 29, as in
        # swift_lints.py.
        self.assertEqual(triples(self.result, 'Pointers.swift'), [
            (10, 18, 'unsafe-pointer-arg-unmarked'),
            (13, 16, 'unsafe-pointer-arg-unmarked'),
            (15, 18, 'unsafe-pointer-arg-unmarked'),
            (16, 14, 'unsafe-pointer-arg-unmarked'),
            (17, 24, 'unsafe-pointer-arg-unmarked'),
            (18, 21, 'unsafe-pointer-arg-unmarked'),
            (19, 25, 'unsafe-pointer-arg-unmarked'),
            (21, 18, 'unsafe-pointer-arg-unmarked'),
            (28, 18, 'unsafe-pointer-arg-unmarked'),
            (29, 18, 'unsafe-pointer-arg-unmarked'),
            (32, 21, 'unsafe-pointer-arg-unmarked'),
        ])

    def test_messages_name_the_conversion_and_pointer_type(self):
        findings, _ = self.result.files[fixture('Pointers.swift')]
        by_line = dict((f.line, f.message) for f in findings)
        self.assertIn('&x converted to UnsafeMutablePointer<Int32>', by_line[10])
        self.assertIn('array converted to UnsafePointer<Int32>', by_line[13])
        self.assertIn('&array converted to UnsafeMutablePointer<Int32>', by_line[15])
        self.assertIn('&x converted to UnsafeRawPointer', by_line[16])
        self.assertIn('string converted to UnsafePointer<Int8>', by_line[18])
        self.assertIn('&x converted to AutoreleasingUnsafeMutablePointer<NSError?>', by_line[21])

    def test_marked_sites_are_listed(self):
        _, notes = self.result.files[fixture('Pointers.swift')]
        marked = [(n['line'], n['marker']) for n in notes if n['kind'] == 'marked-pointer-arg']
        self.assertEqual(marked, [(23, 'SWIFT-MIGRATION-UNSAFE(hot)'), (25, 'SWIFT-MIGRATION-SHIM'),
                                  (30, 'SWIFT-MIGRATION-SHIM')])

    def test_complete(self):
        self.assertEqual(self.result.incomplete, [])


class ArithmeticTests(CompilerTestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = None if SKIP_REASON else standalone(['Arithmetic.swift'])

    def test_exact_findings(self):
        # Not reported: Double, CGFloat, String and Array operators (19 to 22), &+ (23), two literals (24), a
        # helper call (25), a bounded-by-type comment at the end of the line (26) or alone on the line above
        # (28), division, comparison and floating-point negation (32 to 34), and an operator this module
        # declares (36).
        self.assertEqual(triples(self.result, 'Arithmetic.swift'), [
            (8, 11, 'integer-arithmetic'),
            (9, 11, 'integer-arithmetic'),
            (10, 11, 'integer-arithmetic'),
            (11, 9, 'integer-arithmetic'),
            (12, 11, 'integer-arithmetic'),
            (13, 11, 'integer-arithmetic'),
            (15, 7, 'integer-arithmetic'),
            (16, 7, 'integer-arithmetic'),
            (17, 7, 'integer-arithmetic'),
            (18, 7, 'integer-arithmetic'),
            (31, 11, 'integer-arithmetic'),
        ])

    def test_messages_name_operator_and_type(self):
        findings, _ = self.result.files[fixture('Arithmetic.swift')]
        by_line = dict((f.line, f.message) for f in findings)
        self.assertIn('"+" on Int32', by_line[8])
        self.assertIn('"-" on Int', by_line[9])  # NSInteger is Int
        self.assertIn('"*" on Int32', by_line[10])  # a typealias of Int32
        self.assertIn('unary "-" on Int32', by_line[11])
        self.assertIn('"<<" on Int32', by_line[12])
        self.assertIn('"+" on UInt8', by_line[13])
        self.assertIn('"+=" on Int32', by_line[15])


class ConversionTests(CompilerTestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = None if SKIP_REASON else standalone(['Conversions.swift'])

    def test_exact_findings(self):
        # Not reported: labeled initializers (11 to 14), Int(String) (15), literal arguments (16, 20),
        # floating-point results (17, 18), numericCast (19).
        self.assertEqual(triples(self.result, 'Conversions.swift'), [
            (4, 9, 'integer-init-nonliteral'),
            (5, 9, 'integer-init-nonliteral'),
            (6, 9, 'integer-init-nonliteral'),
            (7, 9, 'integer-init-nonliteral'),
            (8, 9, 'integer-init-nonliteral'),
            (9, 9, 'integer-init-nonliteral'),
            (10, 20, 'integer-init-nonliteral'),
        ])

    def test_messages_name_source_and_result_types(self):
        findings, _ = self.result.files[fixture('Conversions.swift')]
        by_line = dict((f.line, f.message) for f in findings)
        self.assertIn('Int(Double)', by_line[4])
        self.assertIn('Int32(Int)', by_line[5])
        self.assertIn('Int(CGFloat)', by_line[8])
        self.assertIn('Int16(Int)', by_line[10])


class ImplicitUnwrapTests(CompilerTestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = None if SKIP_REASON else standalone(['IUO.swift'], header='IUO.h')

    def test_exact_findings(self):
        # Each is reported at the name of the declaration whose value is unwrapped, so that the two unwraps of
        # the chain on lines 16 to 19 are two findings on their own lines. Not reported: if let (12), an optional
        # chain (13), an assignment to an optional (14), and the implicitly unwrapped Swift properties on lines 15
        # and 20, which are notes (the one on line 20 is @objc, with a Clang-style USR), and the explicit force
        # unwrap on line 21, which is the token lint force-unwrap's.
        self.assertEqual(triples(self.result, 'IUO.swift'), [
            (8, 21, 'iuo-objc-implicit-unwrap'),
            (9, 33, 'iuo-objc-implicit-unwrap'),
            (10, 27, 'iuo-objc-implicit-unwrap'),
            (11, 23, 'iuo-objc-implicit-unwrap'),
            (17, 10, 'iuo-objc-implicit-unwrap'),
            (18, 10, 'iuo-objc-implicit-unwrap'),
        ])

    def test_messages_name_the_declaration(self):
        findings, _ = self.result.files[fixture('IUO.swift')]
        by_line = dict((f.line, f.message) for f in findings)
        self.assertIn('name', by_line[8])
        self.assertIn('c:objc(cs)FixOld(py)name', by_line[8])
        self.assertIn('describe', by_line[9])
        self.assertIn('shared', by_line[10])
        self.assertIn('FixOldFunction', by_line[11])
        self.assertIn('items', by_line[18])

    def test_swift_declared_unwrap_is_a_note(self):
        _, notes = self.result.files[fixture('IUO.swift')]
        swift = [(n['line'], n['column'], n['name']) for n in notes if n['kind'] == 'implicit-unwrap-swift']
        self.assertEqual(swift, [(15, 26, 'prop'), (20, 31, 'outlet')])


class MarkerPlacementSharedWithTokenToolTests(CompilerTestCase):
    def test_same_lines_as_swift_lints(self):
        path = fixture('Markers.swift')
        with open(path, encoding='utf-8') as f:
            text = f.read()
        token_findings, _ = sl.lint_source(path, text)
        token_lines = sorted(set(f.line for f in token_findings if f.lint == 'unsafe-pointer-unmarked'))
        result = standalone(['Markers.swift'])
        ast_lines = sorted(set(f.line for f in result.files[path][0]))
        # The function on line 3 names UnsafeMutablePointer in its signature; it has no conversion.
        self.assertEqual(token_lines, [3, 9, 14, 15, 18, 20])
        self.assertEqual(ast_lines, [9, 14, 15, 18, 20])
        # Line 16 is covered by the trailing marker on line 15; line 20's marker has no reason, which the token
        # tool reports as marker-format, and it covers nothing.
        self.assertIn((19, 'marker-format'), [(f.line, f.lint) for f in token_findings])


class IncompleteTests(CompilerTestCase):
    def test_compiler_error_makes_the_file_incomplete(self):
        result = standalone(['Broken.swift'])
        self.assertEqual([p for p, _ in result.incomplete], [fixture('Broken.swift')])
        self.assertIn('compiler', result.incomplete[0][1])
        self.assertNotIn(fixture('Broken.swift'), result.files)

    def test_one_broken_file_spoils_the_module(self):
        # The compiler writes no trustworthy AST for a module with an error, so every file of the job is
        # incomplete, not only the broken one.
        result = standalone(['Arithmetic.swift', 'Broken.swift'])
        self.assertEqual(sorted(p for p, _ in result.incomplete),
                         sorted([fixture('Arithmetic.swift'), fixture('Broken.swift')]))
        self.assertEqual(result.files, {})


# ---------------------------------------------------------------------------
# The reader, without the compiler

def document(filename, items_json):
    return ('{"_kind":"source_file","filename":%s,"compiler_version":{"_kind":"compiler_version","major":"6",'
            '"minor":"4","full":"Apple Swift version 6.4 (test)"},"items":[%s]}' % (json.dumps(filename), items_json))


POINTER_NODE = ('{"_kind":"inout_to_pointer","implicit":true,"type":"$sSpys5Int32VGD","range":{"start":%d,"end":%d},'
                '"sub_expr":{"_kind":"inout_expr","type":"$ss5Int32VzD","range":{"start":%d,"end":%d}}}')


class ReaderTests(CompilerTestCase):
    def run_reader(self, data, extra=()):
        p = subprocess.run([READER] + list(extra), input=data.encode('utf-8'), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=60)
        return p.returncode, p.stdout.decode('utf-8'), p.stderr.decode('utf-8')

    def test_two_documents(self):
        data = document('/a/One.swift', POINTER_NODE % (5, 6, 5, 6)) + '\n' + document('/a/Two.swift', '')
        status, out, err = self.run_reader(data)
        self.assertEqual(status, 0, err)
        docs, summary = al.read_facts(out.splitlines())
        self.assertEqual(sorted(docs), ['/a/One.swift', '/a/Two.swift'])
        self.assertEqual([(f.kind, f.start) for f in docs['/a/One.swift']], [('P', 5)])
        self.assertEqual(summary['documents'], 2)

    def test_truncated_dump_fails(self):
        data = document('/a/One.swift', POINTER_NODE % (5, 6, 5, 6))[:-10]
        status, _, err = self.run_reader(data)
        self.assertEqual(status, 1)
        self.assertIn('truncated', err)

    def test_other_compiler_version_is_refused(self):
        data = document('/a/One.swift', '').replace('"minor":"4"', '"minor":"9"')
        status, _, err = self.run_reader(data)
        self.assertEqual(status, 1)
        self.assertIn('6.9', err)

    def test_skipped_subtree_is_not_reported(self):
        # original_init holds a copy made before type checking (dump_format.h kSkipKeys).
        node = '{"_kind":"pattern_entry","original_init":%s}' % (POINTER_NODE % (5, 6, 5, 6))
        status, out, err = self.run_reader(document('/a/One.swift', node))
        self.assertEqual(status, 0, err)
        docs, _ = al.read_facts(out.splitlines())
        self.assertEqual(docs['/a/One.swift'], [])

    def test_macro_expansion_is_flagged(self):
        node = ('{"_kind":"macro_expansion_expr","range":{"start":40,"end":50},"rewritten":%s}'
                % (POINTER_NODE % (900, 901, 900, 901)))
        status, out, err = self.run_reader(document('/a/One.swift', node))
        self.assertEqual(status, 0, err)
        docs, _ = al.read_facts(out.splitlines())
        self.assertEqual([(f.kind, f.start, f.in_macro) for f in docs['/a/One.swift']], [('P', 40, True)])

    def test_missing_document_makes_its_file_incomplete(self):
        # A "compiler" that writes the document of one of the two primary files.
        d = make_temp()
        dump = os.path.join(d, 'dump.json')
        with open(dump, 'w') as f:
            f.write(document('/a/One.swift', POINTER_NODE % (5, 6, 5, 6)))
        docs, incomplete, info = al.run_job(READER, ['/bin/cat', dump], ['/a/One.swift', '/a/Two.swift'], d,
                                            al.DEFAULT_LIMIT_KB, 60)
        self.assertEqual(list(docs), ['/a/One.swift'])
        self.assertEqual([p for p, _ in incomplete], ['/a/Two.swift'])
        self.assertIn('no complete document', incomplete[0][1])

    def test_large_dump_streams_in_bounded_memory(self):
        # About 200 MB of dump, generated as it is written, with one conversion at the end: the reader's peak
        # resident memory stays far below the size of the dump.
        filler = ('{"_kind":"call_expr","type":"$sytD","range":{"start":1,"end":2},"args":{"_kind":"argument_list",'
                  '"args":[{"_kind":"argument","expr":{"_kind":"string_literal_expr","type":"$sSSD","value":"%s"}}]}}'
                  % ('x' * 400))
        chunk = ','.join([filler] * 1000)
        repeats = 400
        head, tail = document('/a/Big.swift', '@@').split('@@')
        p = subprocess.Popen([READER], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        written = 0
        p.stdin.write(head.encode())
        for _ in range(repeats):
            data = (chunk + ',').encode()
            p.stdin.write(data)
            written += len(data)
        p.stdin.write((POINTER_NODE % (7, 8, 7, 8) + tail).encode())
        p.stdin.close()
        out = p.stdout.read().decode()
        err = p.stderr.read().decode()
        p.stdout.close()
        p.stderr.close()
        self.assertEqual(p.wait(), 0, err)
        self.assertGreater(written, 180 * 1024 * 1024)
        docs, summary = al.read_facts(out.splitlines())
        self.assertEqual([(f.kind, f.start) for f in docs['/a/Big.swift']], [('P', 7)])
        self.assertLess(summary['reader_peak_kb'], 32 * 1024)

    def test_deep_nesting(self):
        depth = 5000
        node = POINTER_NODE % (3, 4, 3, 4)
        for _ in range(depth):
            node = '{"_kind":"paren_expr","sub_expr":%s}' % node
        status, out, err = self.run_reader(document('/a/Deep.swift', node))
        self.assertEqual(status, 0, err)
        docs, _ = al.read_facts(out.splitlines())
        self.assertEqual([(f.kind, f.start) for f in docs['/a/Deep.swift']], [('P', 3)])


# ---------------------------------------------------------------------------
# Offsets, markers and comments, without the compiler

class OffsetTests(unittest.TestCase):
    def test_columns_count_code_points(self):
        text = 'let é = 1\nlet x = é + 1\n'
        data = text.encode('utf-8')
        off = data.index(b'+')
        self.assertEqual(al.LineIndex(data).line_col(off), (2, 11))

    def test_bounded_by_type_comment_placement(self):
        text = ('a + b // bounded-by-type: why\n'
                '// bounded-by-type: why\n'
                'a + b\n'
                '// bounded-by-type:\n'
                'a + b\n'
                '/* bounded-by-type: why */\n'
                'a + b\n')
        self.assertEqual(sorted(al.bounded_by_type_lines(sl.lex(text))), [1, 3])


class PrintJobsTests(unittest.TestCase):
    def test_fast_parse_gives_the_same_job_as_swiftdb(self):
        files = ['/r/A.swift', '/r/with space/B.swift', '/r/C.swift']
        common = ' '.join(shlex.quote(f) for f in files)
        # The real driver passes -dump-ast-format to the precompiled-header job too.
        lines = ['/bin/swift-frontend -frontend -emit-pch -dump-ast-format json -o /tmp/h.pch /r/Bridge.h']
        for f in files:
            lines.append('/bin/swift-frontend -frontend -dump-ast %s -primary-file %s -import-objc-header /tmp/h.pch '
                         '-dump-ast-format json -o %s' % (common, shlex.quote(f), shlex.quote(f + '.ast')))
        text = '\n'.join(lines) + '\n'
        slow = al.swiftdb.frontend_dump_job(al.swiftdb.parse_print_jobs(text), files, '/tmp/list')
        fast = al.swiftdb.frontend_dump_job(al.parse_print_jobs_fast(text), files, '/tmp/list')
        self.assertEqual(fast, slow)
        self.assertIn('/r/Bridge.h', fast)

    def test_restrict_primaries(self):
        job = ['fe', '-filelist', 'L', '-primary-file', 'a', '-primary-file', 'b', '-primary-file', 'c',
               '-o', '-', '-o', '-', '-o', '-', '-Xllvm', '-assert-continue']
        out, kept = al.restrict_primaries(job, {'c', 'a'})
        self.assertEqual(kept, ['a', 'c'])
        self.assertEqual(out, ['fe', '-filelist', 'L', '-primary-file', 'a', '-primary-file', 'c', '-Xllvm',
                               '-assert-continue', '-o', '-', '-o', '-'])


# ---------------------------------------------------------------------------
# The command line, on temporary repositories with a capture

def git(repo, *args):
    subprocess.run(['git', '-c', 'user.name=T', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false']
                   + list(args), cwd=repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def make_repo(files, message='Add\n\nSwift-Port: Fix kind=port\n'):
    repo = make_temp()
    git(repo, 'init', '-q', '-b', 'main')
    for rel, src in files.items():
        dest = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(src, dest)
    git(repo, 'add', '-A')
    git(repo, 'commit', '-q', '-m', message)
    return repo


def make_capture(repo, module_files, outside=()):
    """A capture in codedb.py's shape for one module, Fix, holding module_files (paths relative to repo) and the
    absolute paths outside."""
    fragments = os.path.join(repo, 'tmp', 'capture')
    os.makedirs(os.path.join(fragments, 'swift', 'filelists'))
    file_list = os.path.join(fragments, 'swift', 'filelists', 'Fix.SwiftFileList')
    with open(file_list, 'w') as f:
        for rel in module_files:
            f.write(os.path.join(repo, rel) + '\n')
        for path in outside:
            f.write(path + '\n')
    swiftc = al.find_tool('swiftc')
    sdk = al.sdk_path()
    command = ('builtin-SwiftDriver -- %s -module-name Fix -Onone -sdk %s -target arm64-apple-macos13.0 @%s'
               % (swiftc, sdk, file_list))
    with open(os.path.join(fragments, 'swift', 'drivers.jsonl'), 'w') as f:
        f.write(json.dumps({'target': 'Fix', 'header': 'SwiftDriver Fix normal arm64', 'command': command,
                            'file_list': file_list}) + '\n')
    return fragments


def run_cli(repo, fragments, *args):
    work = os.path.join(repo, 'tmp', 'work')
    p = subprocess.run([sys.executable, '-B', SCRIPT, '--repo', repo, '--fragments', fragments, '--work', work,
                        '--reader', READER, '--module-cache', MODULE_CACHE, '--json'] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)
    out = p.stdout.decode('utf-8')
    return p.returncode, (json.loads(out) if out.strip().startswith('{') else out), p.stderr.decode('utf-8')


class CommandLineTests(CompilerTestCase):
    def test_tree_mode_reports_findings(self):
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift')})
        fragments = make_capture(repo, ['sources/Arithmetic.swift'])
        status, report, err = run_cli(repo, fragments)
        self.assertEqual(status, 1, err)
        self.assertEqual(report['incomplete'], [])
        lines = [(f['path'], f['line'], f['lint']) for f in report['findings']]
        self.assertEqual(len(lines), 11)
        self.assertIn(('sources/Arithmetic.swift', 8, 'integer-arithmetic'), lines)
        self.assertEqual(report['counts']['integer-arithmetic'], 11)

    def test_file_missing_from_capture_is_incomplete(self):
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift'),
                          'sources/Conversions.swift': fixture('Conversions.swift')})
        fragments = make_capture(repo, ['sources/Arithmetic.swift'])
        status, report, err = run_cli(repo, fragments)
        self.assertEqual(status, al.EXIT_INCOMPLETE, err)
        self.assertEqual([i['path'] for i in report['incomplete']], ['sources/Conversions.swift'])
        self.assertIn('not in the file list of any captured module', report['incomplete'][0]['reason'])
        # The file that was captured is still linted.
        self.assertIn('sources/Arithmetic.swift', [f['path'] for f in report['findings']])

    def test_module_with_a_file_outside_the_repository_is_used(self):
        # The code database excludes such a module (a Swift package checkout); its files are still linted here.
        elsewhere = make_temp()
        outside = os.path.join(elsewhere, 'Package.swift')
        with open(outside, 'w') as f:
            f.write('public let fixPackageValue: Int32 = 1\n')
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift')})
        fragments = make_capture(repo, ['sources/Arithmetic.swift'], outside=[outside])
        status, report, err = run_cli(repo, fragments)
        self.assertEqual(status, 1, err)
        self.assertEqual(report['incomplete'], [])
        self.assertEqual(report['counts']['integer-arithmetic'], 11)

    def test_no_capture_is_incomplete(self):
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift')})
        status, report, err = run_cli(repo, os.path.join(repo, 'no-such-capture'))
        self.assertEqual(status, al.EXIT_INCOMPLETE, err)
        self.assertEqual([i['path'] for i in report['incomplete']], ['sources/Arithmetic.swift'])

    def test_no_migration_files_is_clean_without_a_compiler(self):
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift')}, message='Add\n')
        status, report, err = run_cli(repo, os.path.join(repo, 'no-such-capture'))
        self.assertEqual(status, 0, err)
        self.assertEqual(report['selection']['files_linted'], 0)
        self.assertEqual(report['modules'], [])

    def test_staged_content_that_differs_from_the_working_tree_is_incomplete(self):
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift')})
        fragments = make_capture(repo, ['sources/Arithmetic.swift'])
        path = os.path.join(repo, 'sources', 'Arithmetic.swift')
        with open(path, 'a') as f:
            f.write('// staged\n')
        git(repo, 'add', 'sources/Arithmetic.swift')
        with open(path, 'a') as f:
            f.write('// not staged\n')
        status, report, err = run_cli(repo, fragments, '--staged', '--not-a-port')
        self.assertEqual(status, al.EXIT_INCOMPLETE, err)
        self.assertEqual([i['path'] for i in report['incomplete']], ['sources/Arithmetic.swift'])
        self.assertIn('working tree', report['incomplete'][0]['reason'])

    def test_ported_lines_only(self):
        # A port commit that adds lines to a Swift file that is not a migration file: only its lines count.
        repo = make_repo({'sources/Arithmetic.swift': fixture('Arithmetic.swift')}, message='Add\n')
        fragments = make_capture(repo, ['sources/Arithmetic.swift'])
        path = os.path.join(repo, 'sources', 'Arithmetic.swift')
        with open(path) as f:
            lines = f.read().split('\n')
        lines.insert(35, '    _ = b * b')  # becomes line 36, inside the function
        with open(path, 'w') as f:
            f.write('\n'.join(lines))
        git(repo, 'add', '-A')
        git(repo, 'commit', '-q', '-m', 'Port\n\nSwift-Port: Fix kind=port\n')
        status, report, err = run_cli(repo, fragments, 'HEAD')
        self.assertEqual(status, 1, err)
        self.assertEqual(report['findings'], [])
        self.assertEqual([(f['line'], f['lint']) for e in report['ported_lines'] for f in e['findings']],
                         [(36, 'integer-arithmetic')])

    def test_help_names_every_lint(self):
        p = subprocess.run([sys.executable, '-B', SCRIPT, '--help'], stdout=subprocess.PIPE, timeout=60)
        out = p.stdout.decode()
        for lint in al.LINTS:
            self.assertIn(lint, out)


if __name__ == '__main__':
    unittest.main()
