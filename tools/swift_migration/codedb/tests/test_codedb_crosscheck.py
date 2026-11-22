#!/usr/bin/env python3
"""Tests for the cross-check of the code database against object files
(crosscheck.py, codedb.py crosscheck).

The fixtures under crosscheck_fixtures/ are compiled in the test with
`xcrun clang -c` (the compiler that builds the app) into object files, one
with ARC and one with manual reference counting, and extracted into a
database with the extractor; the expected comparison is written out by
hand. Needs Xcode's command line tools; the tests are skipped without
xcrun.
"""

import collections
import io
import json
import os
import shutil
import sqlite3
import struct
import subprocess
import sys
import time
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import codedb  # noqa: E402
import crosscheck  # noqa: E402
import test_codedb as base  # noqa: E402

ARC_M = 'sources/arc.m'
MRC_M = 'sources/mrc.m'
BUG_M = 'sources/bug.m'
CLANG_FLAGS = ['-arch', 'arm64', '-mmacosx-version-min=13.0']


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def have_xcrun():
    try:
        return subprocess.run(['xcrun', '--find', 'clang'], capture_output=True).returncode == 0
    except OSError:
        return False


def compile_object(root, main, out, arc):
    cmd = ['xcrun', 'clang', '-c'] + CLANG_FLAGS + (['-fobjc-arc'] if arc else []) + [
        '-I', os.path.join(root, 'sources'), os.path.join(root, main), '-o', out]
    subprocess.run(cmd, check=True, capture_output=True)


def setup_tree(test, mains=((ARC_M, ['-fobjc-arc']), (MRC_M, [])), project_extra=()):
    """A fixture repository, its object files and an up-to-date database.
    project_extra: files the project compiles that the compile database
    has no unit for."""
    d = base.make_temp('codedb-crosscheck-')
    test.work = d
    test.root = os.path.join(d, 'repo')
    shutil.copytree(os.path.join(HERE, 'crosscheck_fixtures'), test.root)
    os.makedirs(os.path.join(d, 'outside'))
    test.objdir = os.path.join(d, 'Build', 'Intermediates.noindex', 'T.build', 'Objects-normal', 'arm64')
    os.makedirs(test.objdir)
    test.objects = dict((m, os.path.join(test.objdir, os.path.splitext(os.path.basename(m))[0] + '.o'))
                        for m, _ in mains)
    test.paths = base.make_paths(test.root)
    # Only the fixtures this tree compiles.
    for f in os.listdir(os.path.join(test.root, 'sources')):
        if f.endswith('.m') and 'sources/' + f not in [m for m, _ in mains]:
            os.remove(os.path.join(test.root, 'sources', f))
    for f in project_extra:
        with open(os.path.join(test.root, f), 'w') as fh:
            fh.write('// Compiled by the project; the compile database has no unit for it.\n')
    base.write_project(test.root, {'T': [m for m, _ in mains] + list(project_extra)})
    meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(test.root)}
    with open(test.paths.cdb, 'w') as f:
        f.write(json.dumps(meta) + '\n')
        for m, extra in mains:
            # The capture's output path names a variant directory that the
            # build no longer has, as the real capture's does.
            output = test.objects[m].replace('/Intermediates.noindex/', '/Intermediates.noindex/Variant-NoSanitizers/')
            f.write(json.dumps({'target': 'T', 'file': m, 'directory': test.root, 'output': output,
                                'arguments': base.clang_args(test.root, m, extra)}) + '\n')
    status = codedb.update(test.paths, log=lambda m: None)
    # The objects are built after the sources were last written.
    time.sleep(0.01)
    for m, extra in mains:
        compile_object(test.root, m, test.objects[m], '-fobjc-arc' in extra)
    return status


def run(test, **kwargs):
    out = io.StringIO()
    status = crosscheck.crosscheck(codedb, test.paths, out=out, list_explained=True, **kwargs)
    return status, out.getvalue()


def section(text, heading):
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(heading))
    n = int(lines[start].rsplit(' ', 1)[1])
    return lines[start + 1:start + 1 + n]


EXPLAINED = sorted([
    'T sources/arc.m: selector only in the object: arrayWithObjects:count: (array-literal)',
    'T sources/arc.m: selector only in the object: countByEnumeratingWithState:objects:count: (fast-enumeration)',
    'T sources/arc.m: selector only in the object: dealloc (arc-super-dealloc)',
    'T sources/arc.m: selector only in the database: alloc (runtime-alloc)',
    'T sources/arc.m: selector only in the database: catDirect (direct-method)',
    'T sources/arc.m: selector only in the database: class (runtime-class)',
    'T sources/arc.m: selector only in the database: direct (direct-method)',
    'T sources/arc.m: selector only in the database: init (runtime-alloc-init)',
    'T sources/arc.m: selector only in the database: unusedHelperSelector (not-emitted)',
    'T sources/arc.m: method only in the object: -[Thing .cxx_destruct] (cxx-destruct)',
    'T sources/mrc.m: selector only in the database: autorelease (runtime-autorelease)',
    'T sources/mrc.m: selector only in the database: new (runtime-new)',
    'T sources/mrc.m: selector only in the database: release (runtime-release)',
    'T sources/mrc.m: selector only in the database: retain (runtime-retain)',
    'T sources/mrc.m: selector only in the database: unusedHelperSelector (not-emitted)',
])


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class CrossCheckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.status = setup_tree(cls)

    def test_update(self):
        self.assertEqual(self.status, 0)

    def test_object_facts(self):
        with open(self.objects[ARC_M], 'rb') as f:
            facts = crosscheck.read_object(f.read())
        self.assertEqual(sorted(facts.stubs), ['arrayWithObjects:count:', 'countByEnumeratingWithState:objects:count:',
                                               'isKindOfClass:', 'poke', 'respondsToSelector:', 'run', 'setItem:'])
        # The super sends and the @selector: __objc_selrefs.
        self.assertEqual(sorted(facts.selrefs), ['dealloc', 'poke', 'run'])
        self.assertEqual(sorted(facts.methods), ['-[Thing .cxx_destruct]', '-[Thing catDirect]', '-[Thing dealloc]',
                                                 '-[Thing direct]', '-[Thing item]', '-[Thing run]', '-[Thing setItem:]',
                                                 '-[Thing(Extra) extra]'])
        self.assertEqual(sorted(facts.ivars), ['Thing._count', 'Thing._item', 'Thing._strong'])
        # One branch relocation per call site of a stub; the super send has
        # none (objc_msgSendSuper2); for (x in a) calls its stub twice.
        self.assertEqual(dict(facts.call_sites), {
            'arrayWithObjects:count:': 1, 'countByEnumeratingWithState:objects:count:': 2, 'isKindOfClass:': 1,
            'poke': 2, 'respondsToSelector:': 1, 'run': 1, 'setItem:': 1})
        self.assertIsNone(facts.fat)

    def test_every_difference_is_explained(self):
        status, text = run(self)
        self.assertEqual(status, 0, text)
        self.assertEqual(section(text, 'UNEXPLAINED:'), [])
        self.assertEqual(sorted(line.strip() for line in section(text, 'explained:')), EXPLAINED)
        self.assertIn('units: 2 Objective-C units; compared 2; not compared 0', text)
        self.assertIn('  selector only in the database, runtime-retain: 1', text)

    def test_unit_rows_match_the_object_where_they_agree(self):
        con = sqlite3.connect(self.paths.db)
        try:
            tu = con.execute('SELECT id FROM tu WHERE main_file = ?', (ARC_M,)).fetchone()[0]
            rows = crosscheck.unit_rows(con, tu)
        finally:
            con.close()
        self.assertEqual(sorted(rows['methods']), ['-[Thing dealloc]', '-[Thing direct]', '-[Thing item]', '-[Thing run]',
                                                   '-[Thing setItem:]', '-[Thing(Direct) catDirect]',
                                                   '-[Thing(Extra) extra]'])
        self.assertTrue(rows['arc'])
        self.assertEqual(sorted(rows['ivars']), ['Thing._count', 'Thing._item', 'Thing._strong'])

    def test_filters(self):
        status, text = run(self, file=MRC_M)
        self.assertEqual(status, 0)
        self.assertIn('units: 1 Objective-C units; compared 1', text)
        status, text = run(self, target='Other')
        self.assertIn('units: 0 Objective-C units of target Other; compared 0', text)

    def test_rules_are_printed(self):
        _, text = run(self)
        for rule in crosscheck.RULES:
            self.assertIn('  %s (' % rule.name, text)
        for name, _, _ in crosscheck.COUNT_RULES:
            self.assertIn('  %s (' % name, text)
        self.assertIn(crosscheck.SET_LIMIT_TEXT, text)
        self.assertIn(crosscheck.COUNT_RULE_TEXT, text)

    def test_call_site_counts_agree(self):
        status, text = run(self)
        self.assertNotIn('call sites:', text.split('explained:')[0].split('differences by kind and rule:')[1])

    def test_direct_method_of_a_category_matches(self):
        _, text = run(self)
        self.assertNotIn('catDirect]', text)
        self.assertIn('the captured location', text)

    def test_every_source_file_has_a_unit(self):
        _, text = run(self)
        self.assertIn('0 source files in scope have no captured unit\n', text)


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class CrossCheckProblemsTest(unittest.TestCase):
    def setUp(self):
        self.assertEqual(setup_tree(self), 0)

    def test_unexplained_difference(self):
        con = sqlite3.connect(self.paths.db)
        try:
            with con:
                tu = con.execute('SELECT id FROM tu WHERE main_file = ?', (MRC_M,)).fetchone()[0]
                con.execute("INSERT INTO send(tu, selector, receiver_kind, file, line, col, enclosing_name, in_block, "
                            "implicit_accessor, in_migration_scope) VALUES(?, 'phantom:', 'instance', ?, 1, 1, "
                            "'-[Manual keep:]', 0, 0, 1)", (tu, MRC_M))
                con.execute("DELETE FROM objc_ivar WHERE name = '_count'")
        finally:
            con.close()
        status, text = run(self)
        self.assertEqual(status, 1)
        self.assertEqual(section(text, 'UNEXPLAINED:'), [
            '  T sources/arc.m: ivar only in the object: Thing._count',
            '  T sources/mrc.m: selector only in the database: phantom:'])

    def test_missing_object(self):
        os.remove(self.objects[MRC_M])
        status, text = run(self)
        self.assertEqual(status, 3)
        self.assertIn('  T sources/mrc.m: no object file at ', text)

    def test_stale_build(self):
        future = time.time() + 100
        os.utime(os.path.join(self.root, 'sources', 'cbase.h'), (future, future))
        status, text = run(self)
        self.assertEqual(status, 3)
        self.assertIn('  T sources/arc.m: stale build: sources/cbase.h is newer than the object file', text)

    def test_unreadable_object(self):
        with open(self.objects[ARC_M], 'wb') as f:
            f.write(b'not an object file at all, long enough for a header')
        status, text = run(self)
        self.assertEqual(status, 3)
        self.assertIn('is not readable: not a 64-bit little-endian Mach-O file', text)

    def test_changed_while_read(self):
        real = os.stat
        calls = []

        def changing_stat(path, *args, **kwargs):
            st = real(path, *args, **kwargs)
            if path == self.objects[MRC_M]:
                calls.append(path)
                if len(calls) % 2 == 0:
                    return os.stat_result((st.st_mode, st.st_ino, st.st_dev, st.st_nlink, st.st_uid, st.st_gid,
                                           st.st_size, st.st_atime, st.st_mtime + 1, st.st_ctime))
            return st
        with mock.patch.object(crosscheck.os, 'stat', changing_stat):
            status, text = run(self)
        self.assertEqual(status, 3, text)
        self.assertIn('  T sources/mrc.m: object file %s could not be read: changed while it was read'
                      % self.objects[MRC_M], text)

    def test_build_root(self):
        # The objects of another build of the same sources (a sanitizer
        # build) under another root, in place of the captured location.
        other = os.path.join(self.work, 'other', 'Build')
        objdir = self.objdir.replace(os.path.join(self.work, 'Build'), other)
        os.makedirs(objdir)
        for m, obj in self.objects.items():
            shutil.move(obj, os.path.join(objdir, os.path.basename(obj)))
        status, text = run(self)
        self.assertEqual(status, 3)
        status, text = run(self, build_roots=[other])
        self.assertEqual(status, 0, text)
        self.assertIn('units: 2 Objective-C units; compared 2; not compared 0', text)
        self.assertIn('object files looked up under: %s (in that order' % other, text)
        self.assertIn('units compared per root: %s 2' % other, text)
        self.assertIn('Objects built with other flags (sanitizers) are expected to send the same selectors', text)

    def test_build_root_of_a_thread_sanitizer_build(self):
        other = os.path.join(self.work, 'tsan', 'Build')
        objdir = self.objdir.replace(os.path.join(self.work, 'Build'), other).replace(
            '/Objects-normal/', '/Objects-normal-tsan/')
        os.makedirs(objdir)
        for obj in self.objects.values():
            shutil.move(obj, os.path.join(objdir, os.path.basename(obj)))
        status, text = run(self, build_roots=[os.path.join(self.work, 'missing'), other])
        self.assertEqual(status, 0, text)

    def test_fat_object(self):
        with open(self.objects[ARC_M], 'rb') as f:
            thin = f.read()
        with open(self.objects[ARC_M], 'wb') as f:
            f.write(fat_file([(crosscheck.CPU_TYPE_ARM64, thin)]))
        status, text = run(self)
        self.assertEqual(status, 0, text)
        self.assertIn('note: T sources/arc.m: fat file, arm64 slice read (1 architectures)', text)

    def test_fat_object_without_arm64(self):
        with open(self.objects[ARC_M], 'rb') as f:
            thin = f.read()
        with open(self.objects[ARC_M], 'wb') as f:
            f.write(fat_file([(0x01000007, thin)]))
        status, text = run(self)
        self.assertEqual(status, 3)
        self.assertIn('  T sources/arc.m: fat file: fat file without an arm64 slice (1 architectures)', text)
        self.assertIn('  not compared, fat file: 1', text)

    def test_selector_reference_without_relocation_is_unreadable(self):
        with open(self.objects[ARC_M], 'rb') as f:
            data = bytearray(f.read())
        clear_selrefs(data)
        with open(self.objects[ARC_M], 'wb') as f:
            f.write(bytes(data))
        with self.assertRaises(crosscheck.MachOError):
            crosscheck.read_object(bytes(data))
        status, text = run(self)
        self.assertEqual(status, 3)
        self.assertIn('has no relocation and the value 0', text)

    def test_database_not_current(self):
        with open(os.path.join(self.root, MRC_M), 'a') as f:
            f.write('\n')
        compile_object(self.root, MRC_M, self.objects[MRC_M], False)
        status, text = run(self)
        self.assertEqual(status, 3)
        self.assertIn('  T sources/mrc.m: database rows not current (input changed: sources/mrc.m)', text)


def fat_file(slices):
    """A fat (universal) file of [(cputype, bytes)], slices aligned to 4096."""
    header = struct.pack('>II', crosscheck.FAT_MAGIC, len(slices))
    offset = 4096
    archs, body = b'', b''
    for cputype, data in slices:
        archs += struct.pack('>iiIII', cputype, 0, offset + len(body), len(data), 12)
        body += data + b'\0' * (-len(data) % 4096)
    head = header + archs
    return head + b'\0' * (offset - len(head)) + body


def clear_selrefs(data):
    """Removes the relocations of __objc_selrefs and zeroes its slots."""
    ncmds = struct.unpack_from('<I', data, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, off)
        if cmd == crosscheck.LC_SEGMENT_64:
            nsects = struct.unpack_from('<I', data, off + 64)[0]
            s = off + 72
            for _ in range(nsects):
                if data[s:s + 16].rstrip(b'\0') == b'__objc_selrefs':
                    _, sz, offset = struct.unpack_from('<QQI', data, s + 32)
                    struct.pack_into('<I', data, s + 32 + 28, 0)
                    data[offset:offset + sz] = b'\0' * sz
                s += 80
        off += size


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class UncapturedSourceTest(unittest.TestCase):
    def test_source_files_without_a_unit_are_stated(self):
        setup_tree(self, project_extra=['sources/extra.m'])
        _, text = run(self)
        self.assertIn('1 source files in scope have no captured unit:\n  sources/extra.m (compiled by a target of the '
                      'project, in no unit)\n', text)


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class ExtractorBugTest(unittest.TestCase):
    """The extractor bug the cross-check found on its first whole-tree run:
    a dot-syntax getter of struct type directly under a designated
    initializer was not recorded as a send (bug.m). Fixed (the semantic form
    of an initializer list is traversed): the cross-check finds nothing."""
    EXTRACTOR_BUG_FIXED = True

    @classmethod
    def setUpClass(cls):
        cls.status = setup_tree(cls, mains=((BUG_M, ['-fobjc-arc']),))

    def test_detected_by_set_and_by_count(self):
        self.assertEqual(self.status, 0)
        status, text = run(self)
        expected = [] if self.EXTRACTOR_BUG_FIXED else [
            '  T sources/bug.m: selector only in the object: origin',
            '  T sources/bug.m: %s: size (object 2, database 1)' % crosscheck.COUNT_MORE]
        self.assertEqual(section(text, 'UNEXPLAINED:'), expected, text)
        self.assertEqual(status, 0 if self.EXTRACTOR_BUG_FIXED else 1)


CONST_M = 'sources/constant.m'


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class ConstantFalseTest(unittest.TestCase):
    """Sends in a branch that a constant condition skips: the extractor marks
    them (in_constant_false_branch, from Clang's constant folding) and the
    cross-check explains the selectors and counts they account for, and
    nothing else (constant.m)."""

    @classmethod
    def setUpClass(cls):
        cls.status = setup_tree(cls, mains=((CONST_M, ['-fobjc-arc']),))

    def test_marked_rows(self):
        self.assertEqual(self.status, 0)
        con = sqlite3.connect(self.paths.db)
        try:
            sends = con.execute('SELECT selector, line, in_constant_false_branch, constant_condition_file, '
                                'constant_condition_line FROM send WHERE file = ? ORDER BY line', (CONST_M,)).fetchall()
            refs = con.execute('SELECT ivar_name, access, in_constant_false_branch, constant_condition_line FROM '
                               "ivar_ref WHERE kind = 'direct'").fetchall()
            statics = con.execute('SELECT name, access, in_constant_false_branch, constant_condition_line FROM '
                                  'static_ref ORDER BY line').fetchall()
        finally:
            con.close()
        self.assertEqual(sends, [('onlyDead', 22, 1, CONST_M, 21),
                                 ('alsoLive', 26, 1, CONST_M, 26),
                                 ('alsoLive', 27, 0, None, None),
                                 ('shortCircuit', 28, 1, CONST_M, 28),
                                 ('ternaryDead', 29, 1, CONST_M, 29),
                                 # while (0): the compiler emits the body.
                                 ('whileBody', 31, 0, None, None)])
        self.assertEqual(refs, [('_hits', 'rmw', 1, 21)])
        self.assertEqual(statics, [('gCounter', 'rmw', 1, 21), ('kDebug', 'read', 0, None)])

    def test_explained_by_the_marks(self):
        status, text = run(self)
        self.assertEqual(section(text, 'UNEXPLAINED:'), [], text)
        self.assertEqual(status, 0, text)
        explained = [line.strip() for line in section(text, 'explained:') if 'constant-false-branch' in line]
        self.assertEqual(explained, [
            'T sources/constant.m: selector only in the database: onlyDead (constant-false-branch)',
            'T sources/constant.m: selector only in the database: shortCircuit (constant-false-branch)',
            'T sources/constant.m: selector only in the database: ternaryDead (constant-false-branch)'])
        # alsoLive: one live row, one marked, one call site: the counts agree.
        self.assertNotIn('alsoLive', text)



UNREACHABLE_M = 'sources/unreachable.m'


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class UnreachableCodeTest(unittest.TestCase):
    """Sends in code that no path from the function's entry reaches: the
    extractor marks them (in_unreachable_code, from Clang's CFG) and the
    cross-check explains the selectors and call sites they account for, and
    nothing else (unreachable.m)."""

    @classmethod
    def setUpClass(cls):
        cls.status = setup_tree(cls, mains=((UNREACHABLE_M, ['-fobjc-arc']),))

    def test_marked_rows(self):
        self.assertEqual(self.status, 0)
        con = sqlite3.connect(self.paths.db)
        try:
            sends = con.execute('SELECT selector, line, in_unreachable_code FROM send WHERE file = ? ORDER BY line',
                                (UNREACHABLE_M,)).fetchall()
        finally:
            con.close()
        self.assertEqual(sends, [('alsoLive', 16, 0), ('alsoLive', 17, 1), ('onlyUnreachable', 20, 1),
                                 ('afterAssert', 24, 1)])

    def test_explained_by_the_marks(self):
        status, text = run(self)
        self.assertEqual(section(text, 'UNEXPLAINED:'), [], text)
        self.assertEqual(status, 0, text)
        explained = [line.strip() for line in section(text, 'explained:') if 'unreachable-code' in line]
        self.assertEqual(explained, [
            'T sources/unreachable.m: selector only in the database: afterAssert (unreachable-code)',
            'T sources/unreachable.m: selector only in the database: onlyUnreachable (unreachable-code)',
            'T sources/unreachable.m: %s: alsoLive (object 1, database 2, 1 unreachable) (unreachable-code)' %
            crosscheck.COUNT_FEWER])
        self.assertIn("unreachable-code (selector only in the database): every send of it in the unit is in code "
                      "that no path from its function's entry reaches in the unit's configuration", text)


INLINED_M = 'sources/inlined.m'


@unittest.skipUnless(have_xcrun(), 'needs xcrun clang')
class InlinedFunctionTest(unittest.TestCase):
    """always_inline functions: the object has one call site per inlined
    copy. The excess is explained only up to the number of copies that the
    references to the function allow (function_ref), and a row the marks
    leave out never cancels a call site (inlined.m)."""

    @classmethod
    def setUpClass(cls):
        cls.status = setup_tree(cls, mains=((INLINED_M, ['-fobjc-arc']),))

    def test_references_recorded(self):
        self.assertEqual(self.status, 0)
        con = sqlite3.connect(self.paths.db)
        try:
            refs = con.execute('SELECT callee, enclosing_name, refs FROM function_ref ORDER BY callee, '
                               'enclosing_name').fetchall()
        finally:
            con.close()
        self.assertEqual(refs, [('Outer', '-[Inliner run]', 1), ('Twice', '-[Inliner run]', 2),
                                ('Twice', 'Outer', 2)])

    def test_explained_within_the_bound(self):
        status, text = run(self)
        self.assertEqual(section(text, 'UNEXPLAINED:'), [], text)
        self.assertEqual(status, 0, text)
        explained = sorted(line.strip() for line in section(text, 'explained:') if 'inlined-function' in line)
        # Twice is emitted 2 + 1 x 2 = 4 times; the dead row in -[Inliner run]
        # is left out of the database's count.
        self.assertEqual(explained, [
            'T sources/inlined.m: %s: deadAndInline (object 4, database 0, 1 marked) (inlined-function)' %
            crosscheck.COUNT_MORE,
            'T sources/inlined.m: %s: inInline (object 4, database 0) (inlined-function)' % crosscheck.COUNT_MORE])


def facts(stubs=(), selrefs=(), methods=(), undefined=(), defined=(), call_sites=None):
    return crosscheck.ObjectFacts(set(stubs), set(selrefs), set(methods), set(), set(undefined), set(defined),
                                  collections.Counter(call_sites or {}))


def unit(selectors=(), defined=(), places=None, arc=True, sites=None):
    return {'selectors': set(selectors), 'send_places': places or {}, 'selref_selectors': set(),
            'methods': set(), 'defined_selectors': set(defined), 'ivars': set(), 'arc': arc, 'send_sites': sites or {}}


def site(enclosing='-[A b]', kind='instance', line=1, col=1, macro_file=None, role=None):
    return (kind, enclosing, 'sources/a.m', line, col, macro_file, role)


class RuleEvidenceTest(unittest.TestCase):
    def rules(self, f, u):
        return [(d.kind, d.name, d.rule) for d in crosscheck.compare_unit(f, u)]

    def test_runtime_rule_needs_the_runtime_function(self):
        self.assertEqual(self.rules(facts(undefined={'_objc_retain'}), unit({'retain'})),
                         [('selector only in the database', 'retain', 'runtime-retain')])
        # Without objc_retain in the object, a missing -retain is unexplained.
        self.assertEqual(self.rules(facts(), unit({'retain'})),
                         [('selector only in the database', 'retain', None)])

    def test_super_dealloc_needs_a_dealloc(self):
        self.assertEqual(self.rules(facts(selrefs={'dealloc'}), unit(defined={'dealloc'})),
                         [('selector only in the object', 'dealloc', 'arc-super-dealloc')])
        self.assertEqual(self.rules(facts(selrefs={'dealloc'}), unit()),
                         [('selector only in the object', 'dealloc', None)])

    def test_super_dealloc_needs_arc(self):
        # Under manual reference counting [super dealloc] is written by hand
        # and is a row; one that is not is unexplained.
        self.assertEqual(self.rules(facts(selrefs={'dealloc'}), unit(defined={'dealloc'}, arc=False)),
                         [('selector only in the object', 'dealloc', None)])

    def test_direct_method_of_a_category(self):
        f = facts(methods={'-[A d]'})
        u = unit()
        u['methods'] = {'-[A(Cat) d]'}
        self.assertEqual(self.rules(f, u), [])
        u['methods'] = {'-[B(Cat) d]'}
        self.assertEqual(self.rules(f, u), [('method only in the object', '-[A d]', None),
                                            ('method only in the database', '-[B(Cat) d]', None)])


    def test_not_emitted_needs_every_function_absent(self):
        places = {'foo': {'Helper', '-[A b]'}}
        self.assertEqual(self.rules(facts(defined={'-[A b]'}), unit({'foo'}, places=places)),
                         [('selector only in the database', 'foo', None)])
        self.assertEqual(self.rules(facts(), unit({'foo'}, places=places)),
                         [('selector only in the database', 'foo', 'not-emitted')])


class ConstantFalseRuleTest(unittest.TestCase):
    def test_set_rule_needs_every_row_marked(self):
        u = unit({'foo'}, places={'foo': {'-[A b]'}})
        u['constant_false'] = {'foo': [('-[A b]', 1), ('-[A b]', 1)]}
        f = facts(defined={'-[A b]'})
        self.assertEqual(crosscheck.compare_unit(f, u)[0].rule, 'constant-false-branch')
        # One row not marked, in a function the object defines: unexplained.
        u['constant_false'] = {'foo': [('-[A b]', 1), ('-[A b]', 0)]}
        self.assertIsNone(crosscheck.compare_unit(f, u)[0].rule)
        # A selector_ref row is never marked.
        u['constant_false'] = {'foo': [('-[A b]', 0)]}
        self.assertIsNone(crosscheck.compare_unit(f, u)[0].rule)

    def test_count_leaves_the_marked_rows_out(self):
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        marked = site(line=2) + (1,)
        sites = {'foo': [site(line=1) + (0,), marked]}
        self.assertEqual(crosscheck.compare_counts(f, unit({'foo'}, sites=sites)), [])
        # Two fewer, one marked: one fewer, unexplained.
        sites = {'foo': [site(line=1) + (0,), site(line=3) + (0,), marked]}
        self.assertEqual([(d.name, d.rule) for d in crosscheck.compare_counts(f, unit({'foo'}, sites=sites))],
                         [('foo (object 1, database 2, 1 marked)', None)])
        # MORE in the object is never explained by the marks.
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 3})
        sites = {'foo': [site(line=1) + (0,), marked]}
        self.assertEqual([d.rule for d in crosscheck.compare_counts(f, unit({'foo'}, sites=sites))], [None])

    def test_a_marked_row_does_not_cancel_a_missed_send(self):
        # The database's only row is dead code; the object's call is a send
        # the database does not have: object MORE, unexplained.
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        sites = {'foo': [site(line=2) + (1,)]}
        self.assertEqual([(d.kind, d.name, d.rule) for d in crosscheck.compare_counts(f, unit({'foo'}, sites=sites))],
                         [(crosscheck.COUNT_MORE, 'foo (object 1, database 0, 1 marked)', None)])


class UnreachableRuleTest(unittest.TestCase):
    """Rows of a send in unreachable code carry a ninth element, 1
    (in_unreachable_code); the constant-false mark is the eighth."""

    def test_set_rule_needs_every_row_marked(self):
        u = unit({'foo'}, places={'foo': {'-[A b]'}})
        f = facts(defined={'-[A b]'})
        u['constant_false'] = {'foo': [('-[A b]', 0, 1), ('-[A b]', 0, 1)]}
        self.assertEqual(crosscheck.compare_unit(f, u)[0].rule, 'unreachable-code')
        # A row in a constant-false branch and one in unreachable code.
        u['constant_false'] = {'foo': [('-[A b]', 1, 0), ('-[A b]', 0, 1)]}
        self.assertEqual(crosscheck.compare_unit(f, u)[0].rule, 'unreachable-code')
        # One row not marked, in a function the object defines: unexplained.
        u['constant_false'] = {'foo': [('-[A b]', 0, 1), ('-[A b]', 0, 0)]}
        self.assertIsNone(crosscheck.compare_unit(f, u)[0].rule)
        # A row in a function the object does not define needs no mark.
        u['constant_false'] = {'foo': [('-[A b]', 0, 1), ('Gone', 0, 0)]}
        self.assertEqual(crosscheck.compare_unit(f, u)[0].rule, 'unreachable-code')
        # Only constant-false marks: that rule, not this one.
        u['constant_false'] = {'foo': [('-[A b]', 1, 0)]}
        self.assertEqual(crosscheck.compare_unit(f, u)[0].rule, 'constant-false-branch')

    def test_count_explained_when_the_marked_rows_account_for_it(self):
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        sites = {'foo': [site(line=1) + (0, 0), site(line=2) + (0, 1)]}
        self.assertEqual([(d.kind, d.name, d.rule) for d in crosscheck.compare_counts(f, unit({'foo'}, sites=sites))],
                         [(crosscheck.COUNT_FEWER, 'foo (object 1, database 2, 1 unreachable)', 'unreachable-code')])
        # Two fewer, one marked: one fewer, unexplained.
        sites = {'foo': [site(line=1) + (0, 0), site(line=3) + (0, 0), site(line=2) + (0, 1)]}
        self.assertEqual([(d.name, d.rule) for d in crosscheck.compare_counts(f, unit({'foo'}, sites=sites))],
                         [('foo (object 1, database 3, 1 unreachable)', None)])

    def test_a_marked_row_does_not_cancel_a_missed_send(self):
        # The database's only row is unreachable; the object's call is a
        # send the database does not have: object MORE, unexplained.
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        sites = {'foo': [site(line=2) + (0, 1)]}
        self.assertEqual([(d.kind, d.name, d.rule) for d in crosscheck.compare_counts(f, unit({'foo'}, sites=sites))],
                         [(crosscheck.COUNT_MORE, 'foo (object 1, database 1, 1 unreachable)', None)])

    def test_a_marked_row_in_an_inlined_function_is_not_a_copy(self):
        sites = {'foo': [site(enclosing='InlineHelper', line=2) + (0, 1)]}
        u = unit({'foo'}, sites=sites)
        u['function_refs'] = {'InlineHelper': {'-[A b]': 2}}
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        self.assertEqual([d.rule for d in crosscheck.compare_counts(f, u)], [None])


class CallSiteCountTest(unittest.TestCase):
    def counts(self, f, u):
        return [(d.kind, d.name, d.rule) for d in crosscheck.compare_counts(f, u)]

    def test_equal_counts(self):
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 2})
        self.assertEqual(self.counts(f, unit({'foo'}, sites={'foo': [site(line=1), site(line=2)]})), [])

    def test_macro_expansion_with_two_sends_at_one_location(self):
        # Two sends in one expansion of a repository macro: two rows at the
        # expansion site, two call sites.
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 2})
        self.assertEqual(self.counts(f, unit({'foo'}, sites={'foo': [site(role='body'), site(role='body')]})), [])

    def test_more_in_the_object_is_unexplained(self):
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 3})
        self.assertEqual(self.counts(f, unit({'foo'}, sites={'foo': [site(line=1), site(line=2)]})),
                         [(crosscheck.COUNT_MORE, 'foo (object 3, database 2)', None)])

    def test_super_sends_and_functions_not_emitted_are_left_out(self):
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        sites = {'foo': [site(), site(kind='super', line=2), site(enclosing='-[A gone]', line=3)]}
        self.assertEqual(self.counts(f, unit({'foo'}, sites=sites)), [])

    def test_fewer_explained_by_a_runtime_function(self):
        f = facts(stubs={'alloc'}, defined={'-[A b]'}, undefined={'_objc_alloc'}, call_sites={'alloc': 1})
        self.assertEqual(self.counts(f, unit({'alloc'}, sites={'alloc': [site(line=1), site(line=2)]})),
                         [(crosscheck.COUNT_FEWER, 'alloc (object 1, database 2)', 'runtime-alloc')])

    def test_fewer_otherwise_unexplained(self):
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        self.assertEqual(self.counts(f, unit({'foo'}, sites={'foo': [site(line=1), site(line=2)]})),
                         [(crosscheck.COUNT_FEWER, 'foo (object 1, database 2)', None)])

    def test_more_explained_by_boxing(self):
        f = facts(stubs={'numberWithInt:'}, defined={'-[A b]'}, call_sites={'numberWithInt:': 3})
        self.assertEqual(self.counts(f, unit({'numberWithInt:'}, sites={'numberWithInt:': [site()]})),
                         [(crosscheck.COUNT_MORE, 'numberWithInt: (object 3, database 1)', 'boxed-number')])

    def test_unevaluated_macro_argument(self):
        sdk = '/SDK/usr/include/secure/_string.h'
        f = facts(stubs={'bytes'}, defined={'-[A b]'}, call_sites={'bytes': 1})
        twice = [site(macro_file=sdk, role='argument'), site(macro_file=sdk, role='argument')]
        self.assertEqual(self.counts(f, unit({'bytes'}, sites={'bytes': twice})),
                         [(crosscheck.COUNT_FEWER, 'bytes (object 1, database 2)', 'unevaluated-macro-argument')])
        # A row marked as dead code is left out once, not also as an extra
        # row (htons(x.length): the argument is written in an unevaluated
        # operand, a skipped arm and the emitted one).
        three = [site(macro_file=sdk, role='argument') + (0,), site(macro_file=sdk, role='argument') + (1,),
                 site(macro_file=sdk, role='argument') + (0,)]
        self.assertEqual(self.counts(f, unit({'bytes'}, sites={'bytes': three})),
                         [(crosscheck.COUNT_FEWER, 'bytes (object 1, database 2, 1 marked)',
                           'unevaluated-macro-argument')])
        # A repository macro's argument written twice is two call sites.
        twice = [site(macro_file='sources/m.h', role='argument'), site(macro_file='sources/m.h', role='argument')]
        self.assertEqual(self.counts(f, unit({'bytes'}, sites={'bytes': twice})),
                         [(crosscheck.COUNT_FEWER, 'bytes (object 1, database 2)', None)])

    def test_inlined_function(self):
        # InlineHelper is referenced three times from -[A b]: its send is
        # emitted at most three times.
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 4})
        sites = {'foo': [site(), site(enclosing='InlineHelper', line=2)]}
        u = unit({'foo'}, sites=sites)
        u['function_refs'] = {'InlineHelper': {'-[A b]': 3}}
        self.assertEqual(self.counts(f, u),
                         [(crosscheck.COUNT_MORE, 'foo (object 4, database 1)', 'inlined-function')])

    def test_inlined_function_is_bounded(self):
        sites = {'foo': [site(), site(enclosing='InlineHelper', line=2)]}
        u = unit({'foo'}, sites=sites)
        u['function_refs'] = {'InlineHelper': {'-[A b]': 2}}
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 4})
        self.assertEqual(self.counts(f, u), [(crosscheck.COUNT_MORE, 'foo (object 4, database 1)', None)])
        # No reference recorded: no copy, nothing explained.
        u['function_refs'] = {}
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 2})
        self.assertEqual(self.counts(f, u), [(crosscheck.COUNT_MORE, 'foo (object 2, database 1)', None)])

    def test_inlined_function_inside_an_inlined_function(self):
        # Inner is referenced twice from Outer, which has no symbol and is
        # referenced three times from -[A b]: six copies.
        sites = {'foo': [site(enclosing='Inner', line=2)]}
        u = unit({'foo'}, sites=sites)
        u['function_refs'] = {'Inner': {'Outer': 2}, 'Outer': {'-[A b]': 3}}
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 6})
        self.assertEqual(self.counts(f, u), [(crosscheck.COUNT_MORE, 'foo (object 6, database 0)', 'inlined-function')])
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 7})
        self.assertEqual(self.counts(f, u), [(crosscheck.COUNT_MORE, 'foo (object 7, database 0)', None)])

    def test_marked_row_in_an_inlined_function_is_not_a_copy(self):
        sites = {'foo': [site(enclosing='InlineHelper', line=2) + (1,)]}
        u = unit({'foo'}, sites=sites)
        u['function_refs'] = {'InlineHelper': {'-[A b]': 2}}
        f = facts(stubs={'foo'}, defined={'-[A b]'}, call_sites={'foo': 1})
        self.assertEqual(self.counts(f, u), [(crosscheck.COUNT_MORE, 'foo (object 1, database 0)', None)])

    def test_direct_method_of_a_category_is_emitted(self):
        f = facts(stubs={'foo'}, defined={'-[A d]'}, call_sites={'foo': 1})
        self.assertEqual(self.counts(f, unit({'foo'}, sites={'foo': [site(enclosing='-[A(Cat) d]')]})), [])

class CxxFunctionTest(unittest.TestCase):
    """Functions of Objective-C++ units: a C++ member or namespace function,
    and a C function compiled as C++, have mangled symbols (Itanium ABI),
    so whether the object emitted one is decided from the mangled names."""

    def test_not_emitted_cxx_member_functions(self):
        # Sends in inline member functions of a C++ class in a header that
        # the unit never calls (iTermTexturePageCollection.h read by
        # iTermTextRenderer.mm): no code, nothing to explain otherwise.
        places = {'atlasSize': {'iTerm2::TexturePage::TexturePage'},
                  'intValue': {'iTerm2::TexturePageCollection::add'},
                  'count': {'iTermTaskArray::~iTermTaskArray'}}
        f = facts(defined={'-[A b]', '__ZN6iTerm25OtherC2Ev'})
        self.assertEqual([(d.name, d.rule) for d in crosscheck.compare_unit(f, unit(set(places), places=places))],
                         [('atlasSize', 'not-emitted'), ('count', 'not-emitted'), ('intValue', 'not-emitted')])

    def test_emitted_cxx_member_function_is_not_excused(self):
        places = {'atlasSize': {'iTerm2::TexturePage::TexturePage'}}
        # The constructor (C2) of iTerm2::TexturePage is in the object.
        f = facts(defined={'__ZN6iTerm211TexturePageC2EP8NSStringi'})
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'atlasSize'}, places=places))], [None])
        # A block in the function counts as its code.
        f = facts(defined={'___ZN6iTerm221TexturePageCollection3addEv_block_invoke'})
        places = {'intValue': {'iTerm2::TexturePageCollection::add'}}
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'intValue'}, places=places))], [None])
        # A destructor: any symbol of its class.
        f = facts(defined={'__ZN14iTermTaskArrayD1Ev'})
        places = {'count': {'iTermTaskArray::~iTermTaskArray'}}
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'count'}, places=places))], [None])

    def test_other_members_of_the_class_do_not_make_a_constructor_emitted(self):
        # iTermTextRenderer.o defines TexturePage::release but not the
        # constructor TexturePage::TexturePage, whose sends it lacks.
        places = {'atlasSize': {'iTerm2::TexturePage::TexturePage'}}
        f = facts(defined={'__ZN6iTerm211TexturePage7releaseEPNS_16TexturePageOwnerE'})
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'atlasSize'}, places=places))],
                         ['not-emitted'])
        places = {'count': {'iTermTaskArray::~iTermTaskArray'}}
        f = facts(defined={'__ZN14iTermTaskArray7enqueueEv', '__ZN14iTermTaskArrayC1Ev'})
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'count'}, places=places))],
                         ['not-emitted'])
        # A member function needs its own name.
        places = {'intValue': {'iTerm2::TexturePageCollection::add'}}
        f = facts(defined={'__ZN6iTerm221TexturePageCollection12internal_addEv'})
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'intValue'}, places=places))],
                         ['not-emitted'])

    def test_class_template_constructor_and_destructor(self):
        # template <typename T> struct X { X(id o) { ... } ~X() {} }; X<int> x(o);
        # The template arguments come between the class and C1 or D1.
        f = facts(defined={'__ZN1XIiEC1EP11objc_object', '__ZN1XIiED1Ev'})
        self.assertIsNot(crosscheck.emitted('X::X', f), False)
        self.assertIsNot(crosscheck.emitted('X::~X', f), False)
        # Another member of X<int> does not make the constructor emitted.
        f = facts(defined={'__ZN1XIiE1mEP11objc_object'})
        self.assertIs(crosscheck.emitted('X::X', f), False)

    def test_extern_c_function_in_a_namespace(self):
        # extern "C" { namespace cx { void CLinked(id o) { ... } } } has the
        # C symbol _CLinked.
        self.assertIs(crosscheck.emitted('cx::CLinked', facts(defined={'_CLinked'})), True)

    def test_std_names(self):
        # std:: is written St in a mangled name, not 3std.
        self.assertIs(crosscheck.emitted('std::foostd', facts(defined={'__ZSt6foostdP11objc_object'})), True)
        self.assertIs(crosscheck.emitted('std::foostd', facts(defined={'__ZN2ns5otherEv'})), False)

    def test_operator_cannot_be_told(self):
        places = {'foo': {'iTerm2::GlyphKey::operator=='}}
        self.assertEqual([d.rule for d in crosscheck.compare_unit(facts(), unit({'foo'}, places=places))], [None])

    def test_c_function_compiled_as_cxx_is_emitted(self):
        # A static function of a header read by an Objective-C++ unit has
        # the symbol __ZL6Helperv, not _Helper.
        places = {'foo': {'Helper'}}
        f = facts(defined={'__ZL6Helperv'})
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'foo'}, places=places))], [None])
        # A longer name that ends the same way is another function.
        f = facts(defined={'__ZL11OtherHelperv'})
        self.assertEqual([d.rule for d in crosscheck.compare_unit(f, unit({'foo'}, places=places))],
                         ['not-emitted'])

    def test_a_name_inside_a_longer_name_is_another_function(self):
        # 6Helper is written inside 16HelperXxxxxxxxxx: not Helper.
        self.assertIs(crosscheck.emitted('Helper', facts(defined={'__ZL16HelperXxxxxxxxxxv'})), False)
        self.assertIs(crosscheck.emitted('ns::foo', facts(defined={'__ZN2ns6foobarEv'})), False)
        # An identifier that ends in a digit is followed by the next one.
        self.assertIs(crosscheck.emitted('iTerm2::TexturePage::TexturePage',
                                         facts(defined={'__ZN6iTerm211TexturePageC2EP8NSStringi'})), True)

    def test_a_static_function_is_not_a_member_of_the_same_name(self):
        # Helper compiled as C++ is __ZL6Helperv: a database name Foo::Helper
        # does not match it. The reverse (database name Helper, symbol
        # Foo::Helper) cannot be told from a leading inline namespace and is
        # taken as emitted (test_leading_inline_namespace).
        self.assertIs(crosscheck.emitted('Foo::Helper', facts(defined={'__ZL6Helperv'})), False)
        self.assertIs(crosscheck.emitted('Bar::Helper', facts(defined={'__ZN3Foo6HelperEv'})), False)
        self.assertIs(crosscheck.emitted('Foo::Helper', facts(defined={'__ZN3Foo6HelperEv'})), True)

    def test_parameter_types_are_not_names(self):
        # The parameter type 6Helper is not the function's name.
        self.assertIs(crosscheck.emitted('Helper', facts(defined={'__Z3use6Helper'})), False)
        self.assertIs(crosscheck.emitted('use', facts(defined={'__Z3use6Helper'})), True)

    def test_inline_namespace(self):
        # The database's name leaves out an inline namespace that the
        # mangled name has (ankerl::unordered_dense::v4_11_0::detail).
        self.assertIs(crosscheck.emitted('ankerl::unordered_dense::detail::wyhash::mix',
                                         facts(defined={'__ZN6ankerl15unordered_dense7v4_11_06detail6wyhash3mixEyy'})),
                      True)
        self.assertIs(crosscheck.emitted('ankerl::unordered_dense::detail::wyhash::mix',
                                         facts(defined={'__ZN6ankerl15unordered_dense7v4_11_06detail6wyhash3mumEyy'})),
                      False)

    def test_leading_inline_namespace(self):
        # inline namespace v1 { int InNs(U *); }: the database names it InNs.
        self.assertIs(crosscheck.emitted('InNs', facts(defined={'__ZN2v14InNsEP1U'})), True)
        self.assertIs(crosscheck.emitted('ns::InNs', facts(defined={'__ZN2v12ns4InNsEP1U'})), True)
        # Still not a different last name.
        self.assertIs(crosscheck.emitted('InNs', facts(defined={'__ZN2v15InNsXEP1U'})), False)

    def test_class_template_constructor_detected(self):
        # ns::Tm<int>::Tm, the constructor of a class template, as the
        # database names it: C1 or C2 after the template arguments.
        self.assertIs(crosscheck.emitted('ns::Tm<int>::Tm', facts(defined={'__ZN2ns2TmIiEC2Ev'})), True)
        self.assertIs(crosscheck.emitted('ns::Tm<int>::Tm', facts(defined={'__ZN2ns2TmIiE1fEv'})), False)

    def test_local_entity_names_its_function(self):
        # A lambda in Helper (a local entity, Z...E) is code of Helper.
        self.assertIs(crosscheck.emitted('Helper', facts(defined={'__ZZL6HelpervENK3$_0clEv'})), True)

    def test_unparsed_symbol_is_matched_as_before(self):
        # An ABI tag (B5cxx11) is not parsed: the identifiers are matched in
        # order, as before, so the function is taken as emitted.
        self.assertIs(crosscheck.emitted('Foo::bar', facts(defined={'__ZN3Foo3barB5cxx11Ev'})), True)

    def test_counts_leave_out_cxx_functions_not_emitted(self):
        # iTermTextRenderer.mm: two sends in its own methods, seven in C++
        # member functions it never calls.
        f = facts(stubs={'texture'}, defined={'-[A b]'}, call_sites={'texture': 1})
        sites = {'texture': [site(), site(enclosing='iTerm2::TexturePage::get_texture', line=2)]}
        self.assertEqual(crosscheck.compare_counts(f, unit({'texture'}, sites=sites)), [])
        # Emitted, its send is a call site.
        f = facts(stubs={'texture'}, defined={'-[A b]', '__ZN6iTerm211TexturePage11get_textureEv'},
                  call_sites={'texture': 1})
        self.assertEqual([(d.name, d.rule) for d in crosscheck.compare_counts(f, unit({'texture'}, sites=sites))],
                         [('texture (object 1, database 2)', None)])

    def test_counts_count_a_c_function_compiled_as_cxx(self):
        # Before, the function was taken as not emitted because _Helper is
        # not in the object; the count then left its row out.
        f = facts(stubs={'foo'}, defined={'-[A b]', '__ZL6Helperv'}, call_sites={'foo': 2})
        sites = {'foo': [site(), site(enclosing='Helper', line=2)]}
        self.assertEqual(crosscheck.compare_counts(f, unit({'foo'}, sites=sites)), [])


class MachOReaderTest(unittest.TestCase):
    def test_short_file(self):
        with self.assertRaises(crosscheck.MachOError):
            crosscheck.read_object(b'\0' * 8)

    def test_function_symbols(self):
        self.assertEqual(crosscheck.function_symbols('-[A b:]'), {'-[A b:]'})
        self.assertEqual(crosscheck.function_symbols('Helper'), {'_Helper'})
        self.assertIsNone(crosscheck.function_symbols('ns::Helper'))
        self.assertIsNone(crosscheck.function_symbols(None))

    def test_fat_slice(self):
        thin = b'\xcf\xfa\xed\xfe' + b'\0' * 60
        data, note = crosscheck.thin_slice(fat_file([(0x01000007, b'x' * 64), (crosscheck.CPU_TYPE_ARM64, thin)]))
        self.assertEqual(data, thin)
        self.assertEqual(note, 'fat file, arm64 slice read (2 architectures)')
        self.assertEqual(crosscheck.thin_slice(thin), (thin, None))

    def test_object_path_under_a_build_root(self):
        d = base.make_temp('codedb-objpath-')
        real = os.path.join(d, 'other', 'Intermediates.noindex', 'T.build', 'Objects-normal', 'x.o')
        os.makedirs(os.path.dirname(real))
        open(real, 'w').close()
        captured = os.path.join(d, 'Build', 'Intermediates.noindex', 'Variant-X', 'T.build', 'Objects-normal', 'x.o')
        self.assertIsNone(crosscheck.object_path(captured, d))
        self.assertEqual(crosscheck.object_path(captured, d, [os.path.join(d, 'other')]), real)
        self.assertIsNone(crosscheck.object_path('/elsewhere/x.o', d, [os.path.join(d, 'other')]))

    def test_object_path_without_variant(self):
        d = base.make_temp('codedb-objpath-')
        real = os.path.join(d, 'Build', 'x.o')
        os.makedirs(os.path.dirname(real))
        open(real, 'w').close()
        self.assertEqual(crosscheck.object_path(os.path.join(d, 'Build', 'Variant-X', 'x.o'), d), real)
        self.assertIsNone(crosscheck.object_path(os.path.join(d, 'Build', 'y.o'), d))


if __name__ == '__main__':
    unittest.main()
