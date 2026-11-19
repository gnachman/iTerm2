#!/usr/bin/env python3
"""Tests for what Swift imports through a bridging header, in the code
database: `codedb.py update --imports-only` (the swift_import tables of
swift_interface.py, filled by codedb.py for each captured module that has a
bridging header) and the query `codedb.py swiftimports`, which joins them
to the Objective-C declarations of the database by USR and gives the reason
for each declaration Swift does not import.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_codedb_swiftimports.py'

The fixture is swiftimports_fixture/module: Probe.h holds one declaration of
each kind the database records and one of each reason; Probe.m reads it and
Hidden.h, which the bridging header Bridge.h does not reach. The extractor
reads Probe.m; the compiler xcrun finds compiles the module SIF (Use.swift
with Bridge.h) through swift_interface.py's own steps. The classes that need
the compiler are skipped when it is not the one the expectations were
written for. Expected lines are written out by hand; each NOT IMPORTED one
is confirmed by a swiftc probe that fails to type-check (SwiftcAgreementTest).
"""

import io
import json
import os
import shlex
import shutil
import sqlite3
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.path.dirname(HERE)
sys.path.insert(0, CODEDB_DIR)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(CODEDB_DIR))

import codedb  # noqa: E402
import swiftdb  # noqa: E402
import swiftimports  # noqa: E402
import swift_interface as si  # noqa: E402
import test_codedb as base  # noqa: E402

FIXTURE = os.path.join(HERE, 'swiftimports_fixture')
FIXTURE_COMPILER = 'Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)'
MODULE_CACHE = os.path.join(codedb.REPO_ROOT, 'tmp', 'codedb', 'test-swiftimports-modcache')


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def real_compiler():
    try:
        swiftc = subprocess.run(['xcrun', '--find', 'swiftc'], capture_output=True, text=True,
                                check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        return None, 'no Swift compiler (%s)' % e
    version = swiftdb.compiler_version(swiftc)
    if version != FIXTURE_COMPILER:
        return None, 'the compiler is %r; the expectations were written for %r' % (version, FIXTURE_COMPILER)
    return swiftc, None


def skip_unless_compiler(test):
    swiftc, why = real_compiler()
    if swiftc is None:
        sys.stderr.write('\nSKIPPED %s: %s\n' % (test.id(), why))
        test.skipTest(why)
    return swiftc


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def objc_args(root, modules=True):
    return ['-fobjc-arc'] + (['-fmodules'] if modules else []) + ['-F', os.path.join(root, 'module'), '-isysroot',
                                                                    codedb.current_sdk()[0]]


def make_root(swiftc):
    """A scratch repository with the fixture, a project (target T compiles
    module/Probe.m, SIF compiles module/Use.swift), a compile database for
    T, the extracted unit, and a capture of SIF's driver command with the
    bridging header, as capture_compile_commands.sh writes it. Returns
    (root, paths)."""
    d = base.make_temp('codedb-swiftimports-')
    root = os.path.join(d, 'repo')
    shutil.copytree(FIXTURE, root)
    # The Objective-C units of SIF are compiled as the Swift module's
    # configuration is; OtherUser.m, of another target, defines PROBE_EXTRA.
    base.write_project(root, {'SIF': ['module/KitUser.m', 'module/Probe.m', 'module/Use.swift'],
                              'Other': ['module/OtherUser.m']})
    cdb = os.path.join(d, 'cdb.jsonl')
    with open(cdb, 'w') as f:
        f.write(json.dumps({'meta': True, 'build_settings_sha256': codedb.build_settings_digest(root)}) + '\n')
        for target, main, modules, extra in (('Other', 'module/OtherUser.m', True, ['-DPROBE_EXTRA=1']),
                                             ('SIF', 'module/KitUser.m', False, []),
                                             ('SIF', 'module/Probe.m', True, [])):
            args = base.clang_args(root, main, objc_args(root, modules) + extra)
            f.write(json.dumps({'target': target, 'file': main, 'directory': root, 'arguments': args}) + '\n')
    file_list = os.path.join(root, 'Build', 'Variant-NoSanitizers', 'SIF.SwiftFileList')
    write(file_list, os.path.join(root, 'module', 'Use.swift') + '\n')
    sdk = codedb.current_sdk()[0]
    driver = [swiftc, '-module-name', 'SIF', '-Onone', '@' + file_list, '-swift-version', '5', '-import-objc-header',
              os.path.join(root, 'module', 'Bridge.h'), '-F', os.path.join(root, 'module'), '-sdk', sdk, '-target',
              'arm64-apple-macos13.0', '-g', '-c',
              '-j8', '-enable-batch-mode', '-incremental', '-emit-module', '-emit-module-path',
              os.path.join(root, 'Build', 'SIF.swiftmodule'), '-module-cache-path', '/nonexistent/ModuleCache.noindex',
              '-experimental-emit-module-separately', '-working-directory', root]
    log = os.path.join(d, 'build.log')
    write(log, "SwiftDriver SIF normal arm64 com.apple.xcode.tools.swift.compiler (in target 'SIF')\n    cd %s\n"
               "    builtin-SwiftDriver -- %s\n\n" % (root, ' '.join(shlex.quote(a) for a in driver)))
    fragments = os.path.join(d, 'fragments')
    swiftdb.write_swift_capture(log, os.path.join(fragments, 'swift'), log=lambda m: None)
    paths = codedb.Paths(root, db=os.path.join(d, 'db.sqlite'), cdb=cdb, fragments=fragments,
                         extractor=base.EXTRACTOR, swift_work=os.path.join(d, 'swift-work'),
                         module_cache=os.path.join(d, 'modcache'))
    paths.swift_module_cache = MODULE_CACHE
    log = []
    status = codedb.update(paths, objc=True, swift=False, imports=False, log=log.append)
    if status != 0:
        raise AssertionError('the extraction of the fixture failed: %s' % '\n'.join(log))
    return root, paths


def run_main(paths, *argv):
    out, err = io.StringIO(), io.StringIO()
    old = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = out, err
    try:
        status = codedb.main(['--root', paths.root, '--db', paths.db, '--cdb', paths.cdb, '--fragments',
                              paths.fragments, '--extractor', paths.extractor, '--swift-work', paths.swift_work,
                              '--module-cache', paths.module_cache] + list(argv))
    finally:
        sys.stdout, sys.stderr = old
    return status, out.getvalue(), err.getvalue()


def update_imports(paths, **kw):
    log = []
    status = swiftimports.update_imports(paths, log=log.append, module_cache=MODULE_CACHE, **kw)
    return status, log


def query(paths, **kw):
    out = io.StringIO()
    status = codedb.swiftimports(paths, out=out, **kw)
    text = out.getvalue()
    return status, text.partition('\n--- status ---\n')[0], text


H = 'module/Probe.h'
HINT = (' (module/Probe.h uses NS_REFINED_FOR_SWIFT 1 time, NS_SWIFT_NAME 1 time, NS_SWIFT_UNAVAILABLE 2 times, '
        'NS_UNAVAILABLE 1 time; no rule explains the absence: the declaration\'s text carries no mark this tool '
        'reads, and the database does not record the types of parameters)')
UNKNOWN = 'ABSENT FROM THE SYMBOL GRAPH: reason unknown; it may still be usable from Swift (see below)' + HINT
HIDDEN_TYPE = ('names the class ProbeHidden, whose header module/Hidden.h the bridging header of SIF does not read '
               '(Swift drops a member whose type it cannot see) (checked)')
EXTRA = ('NOT IMPORTED: inside #if PROBE_EXTRA (module/Probe.h lines 78-82), which the units of target SIF, compiled '
         'as the module is, skip (checked)')

# Every declaration the database has for Probe.h, as the header form prints
# it. Checked by hand against the fixture and the compiler's symbol graph;
# the NOT IMPORTED reasons other than "reason unknown" are confirmed by
# SwiftcAgreementTest.
EXPECTED_HEADER = [
    H + ':6  PROBE_LIMIT  macro  imported as PROBE_LIMIT: var PROBE_LIMIT: Int32 { get }',
    H + ':7  PROBE_NAME  macro  imported as PROBE_NAME: var PROBE_NAME: String { get }',
    H + ':8  PROBE_EMPTY  macro  NOT IMPORTED: an empty macro (checked)',
    H + ':9  PROBE_TWICE  function-like macro  NOT IMPORTED: a function-like macro; Swift imports none (checked)',
    H + ':10  PROBE_CLASS  macro  NOT IMPORTED: its body is not a constant (it holds a message send) (checked)',
    H + ':12  ProbeTitleKey  global  imported as ProbeTitleKey: let ProbeTitleKey: String',
    H + ':13  ProbeAtomicCounter  global  IMPORTED WITHOUT A USABLE TYPE as ProbeAtomicCounter: var ProbeAtomicCounter: _ '
        '(_ is how the compiler prints a type it cannot import; the type: _Atomic: not imported (objc-state.md section '
        '1; checked))',
    H + ':18  -[ProbeDelegate probeDidChange:]  method  imported as ProbeDelegate.probeDidChange(_:): '
        'func probeDidChange(_ probe: Any)',
    H + ':20  -[ProbeDelegate probeWillChange:]  method  imported as ProbeDelegate.probeWillChange(_:): '
        'optional func probeWillChange(_ probe: Any)',
    H + ':23  Probe  class  imported as Probe: class Probe',
    H + ':24  -[Probe setTitle:]  method  imported through the property Probe.title (Swift imports the property, '
        'not its accessor methods)',
    H + ':24  -[Probe title]  method  imported through the property Probe.title (Swift imports the property, not its '
        'accessor methods)',
    H + ':24  Probe.title  property  imported as Probe.title: var title: String { get set }',
    H + ':25  Probe.count  property  imported as Probe.count: var count: Int { get }',
    H + ':26  -[Probe delegate]  method  imported through the property Probe.delegate (Swift imports the property, '
        'not its accessor methods)',
    H + ':26  -[Probe setDelegate:]  method  imported through the property Probe.delegate (Swift imports the '
        'property, not its accessor methods)',
    H + ':26  Probe.delegate  property  imported as Probe.delegate: weak var delegate: (any ProbeDelegate)? { get set }',
    H + ':27  -[Probe count]  method  imported through the property Probe.count (Swift imports the property, not its '
        'accessor methods)',
    H + ':28  -[Probe initWithTitle:]  method  imported as Probe.init(title:): init(title: String)',
    H + ':29  +[Probe probeWithTitle:]  class method  ' + UNKNOWN,
    H + ':30  -[Probe logFormat:]  method  NOT IMPORTED: a variadic method; Swift imports none (by the declaration\'s '
        'text) (checked)',
    H + ':31  -[Probe hiddenFromSwift]  method  NOT IMPORTED: marked NS_SWIFT_UNAVAILABLE (by the declaration\'s '
        'text) (checked)',
    H + ':32  -[Probe init]  method  NOT IMPORTED: marked NS_UNAVAILABLE (by the declaration\'s text) (checked)',
    H + ':33  -[Probe refinedValue]  method  imported as Probe.__refinedValue(): func __refinedValue() -> Int '
        '[NS_REFINED_FOR_SWIFT]',
    H + ':34  -[Probe setTags:]  method  imported as Probe.setTags(_:): func setTags(_ tags: [String])',
    H + ':38  -[Probe(Extras) extraThing]  method  imported as Probe.extraThing(): func extraThing()',
    H + ':41  ProbeAtomicHolder  class  imported as ProbeAtomicHolder: class ProbeAtomicHolder',
    H + ':42  -[ProbeAtomicHolder atomicValue]  method  NOT IMPORTED: its property ProbeAtomicHolder.atomicValue is '
        'not imported: its type: _Atomic: not imported (objc-state.md section 1; checked) (from the import facts of '
        'its backing ivar)',
    H + ':42  -[ProbeAtomicHolder setAtomicValue:]  method  NOT IMPORTED: its property ProbeAtomicHolder.atomicValue '
        'is not imported: its type: _Atomic: not imported (objc-state.md section 1; checked) (from the import facts '
        'of its backing ivar)',
    H + ':42  ProbeAtomicHolder.atomicValue  property  NOT IMPORTED: its type: _Atomic: not imported (objc-state.md '
        'section 1; checked) (from the import facts of its backing ivar)',
    H + ':43  -[ProbeAtomicHolder plainValue]  method  imported through the property ProbeAtomicHolder.plainValue '
        '(Swift imports the property, not its accessor methods)',
    H + ':43  -[ProbeAtomicHolder setPlainValue:]  method  imported through the property ProbeAtomicHolder.plainValue '
        '(Swift imports the property, not its accessor methods)',
    H + ':43  ProbeAtomicHolder.plainValue  property  imported as ProbeAtomicHolder.plainValue: var plainValue: Int32 '
        '{ get set }',
    H + ':47  ProbeGone  class  NOT IMPORTED: marked NS_SWIFT_UNAVAILABLE (by the declaration\'s text) (checked)',
    H + ':48  -[ProbeGone goneMethod]  method  NOT IMPORTED: its class ProbeGone is not imported',
    H + ':66  ProbeFileBase  class  imported as ProbeFileBase: class ProbeFileBase',
    H + ':67  -[ProbeFileBase localPath]  method  imported as ProbeFileBase.localPath(): func localPath() -> String!',
    H + ':70  ProbeFile  class  imported as ProbeFile: class ProbeFile',
    H + ':71  -[ProbeFile localPath]  method  imported as ProbeFile.localPath(): func localPath() -> String!',
    H + ':71  ProbeFile.localPath  property  ABSENT FROM THE SYMBOL GRAPH: probably usable through -[ProbeFile '
        'localPath] (ProbeFile.localPath()): a member whose Swift name collides with another member\'s is left out of '
        'the symbol graph although Swift can use it (checked)',
    H + ':72  -[ProbeFile hiddenThing]  method  NOT IMPORTED: its property ProbeFile.hiddenThing is not imported: its '
        'type ' + HIDDEN_TYPE,
    H + ':72  -[ProbeFile setHiddenThing:]  method  NOT IMPORTED: its property ProbeFile.hiddenThing is not imported: '
        'its type ' + HIDDEN_TYPE,
    H + ':72  ProbeFile.hiddenThing  property  NOT IMPORTED: its type ' + HIDDEN_TYPE,
    H + ':73  -[ProbeFile makeHidden]  method  NOT IMPORTED: its result type ' + HIDDEN_TYPE,
    H + ':79  ProbeExtra  class  ' + EXTRA,
    H + ':80  -[ProbeExtra extraOnly]  method  ' + EXTRA,
]

KIT = 'module/Kit.framework/Headers/Kit.h'
KIT_REASON = ('NOT IN THIS TABLE: %s belongs to the Clang module of module/Kit.framework, which Swift imports as a '
              'module, not through the bridging header; this table holds only what the bridging header itself '
              'declares' % KIT)

HIDDEN_REASON = ('NOT IMPORTED: module/Hidden.h is not read by the bridging header of SIF (directly or through the '
                 'headers it includes)')


class ImportsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.swiftc, _ = real_compiler()
        if cls.swiftc is None:
            return
        cls.root, cls.paths = make_root(cls.swiftc)
        cls.status, cls.log = update_imports(cls.paths)

    def setUp(self):
        skip_unless_compiler(self)
        self.assertEqual(self.status, 0, self.log)

    def test_update_fills_the_tables_for_the_module_with_a_bridging_header(self):
        con = sqlite3.connect(self.paths.db)
        try:
            units = con.execute('SELECT module, compiler, incomplete FROM swift_import_unit').fetchall()
            inputs = [r[0] for r in con.execute("SELECT path FROM swift_import_input WHERE path NOT LIKE '/%' "
                                                'ORDER BY path')]
        finally:
            con.close()
        self.assertEqual(units, [('SIF', FIXTURE_COMPILER, '')])
        # The headers it read; not its Swift files, whose edits do not change
        # what it imports.
        self.assertEqual(inputs, ['module/Bridge.h', 'module/Kit.framework/Headers/Kit.h',
                                  'module/Kit.framework/Modules/module.modulemap', 'module/Probe.h'])

    def test_the_header_form_lists_every_declaration_with_its_import(self):
        status, rows, text = query(self.paths, header=H)
        self.assertEqual(rows.splitlines()[1:], EXPECTED_HEADER, text)
        self.assertEqual(rows.splitlines()[0], '%s: the declarations the code database has for this header, and how '
                                               'Swift imports them through the bridging header of SIF' % H)
        self.assertEqual(status, 0, text)

    def test_a_header_the_bridging_header_does_not_read(self):
        status, rows, text = query(self.paths, header='module/Hidden.h')
        self.assertEqual(rows.splitlines()[1:], [
            'module/Hidden.h:4  ProbeHidden  class  ' + HIDDEN_REASON,
            'module/Hidden.h:5  -[ProbeHidden secret]  method  ' + HIDDEN_REASON,
        ], text)

    def test_a_header_of_a_framework_module_is_not_judged(self):
        # KitThing is usable from Swift (SwiftcAgreementTest's control uses
        # it), but it is in the module Kit's symbol graph, not the bridging
        # header's.
        status, rows, text = query(self.paths, header=KIT)
        self.assertEqual(rows.splitlines()[1:], [
            KIT + ':6  KitThing  class  ' + KIT_REASON,
            KIT + ':7  -[KitThing kitMethod]  method  ' + KIT_REASON,
        ], text)
        status, rows, text = query(self.paths, not_importable='KitThing')
        self.assertEqual(rows.splitlines()[1:], [], text)

    def test_by_selector_objc_name_and_usr(self):
        for name in ('initWithTitle:', '-[Probe initWithTitle:]', 'c:objc(cs)Probe(im)initWithTitle:',
                     'Probe.init(title:)'):
            status, rows, text = query(self.paths, name=name)
            self.assertEqual(status, 0, text)
            self.assertEqual(rows.splitlines(), [H + ':28  -[Probe initWithTitle:]  method  imported as '
                                                     'Probe.init(title:): init(title: String)'], name)

    def test_by_name_of_a_declaration_that_is_not_imported(self):
        status, rows, text = query(self.paths, name='logFormat:')
        self.assertEqual(status, 0, text)
        self.assertEqual(rows.splitlines(), [EXPECTED_HEADER[20]])
        self.assertIn('logFormat:', EXPECTED_HEADER[20])
        status, rows, text = query(self.paths, name='probeWithTitle:')
        self.assertEqual(rows.splitlines(), [H + ':29  +[Probe probeWithTitle:]  class method  ' + UNKNOWN])
        # The status block says what "may still be usable" means.
        self.assertIn('ABSENT FROM THE SYMBOL GRAPH: no rule explains', text)
        status, rows, text = query(self.paths, name='PROBE_TWICE')
        self.assertEqual(rows.splitlines(), [H + ':9  PROBE_TWICE  function-like macro  NOT IMPORTED: a '
                                                 'function-like macro; Swift imports none (checked)'])

    def test_by_name_of_a_property_and_a_class(self):
        status, rows, text = query(self.paths, name='Probe.title')
        self.assertEqual(rows.splitlines(), [
            H + ':24  Probe.title  property  imported as Probe.title: var title: String { get set }'], text)
        status, rows, text = query(self.paths, name='ProbeGone')
        self.assertEqual(rows.splitlines(), [H + ':47  ProbeGone  class  NOT IMPORTED: marked NS_SWIFT_UNAVAILABLE (by '
                                                 'the declaration\'s text) (checked)'], text)

    def test_a_name_nothing_declares_says_so_and_exits_1(self):
        status, rows, text = query(self.paths, name='noSuchSelector:')
        self.assertEqual(status, 1, text)
        self.assertEqual(rows.splitlines(), ['noSuchSelector:: no declaration by this name in the swift_import table '
                                             'of SIF or in the database'])

    def test_functions_and_types_by_their_objective_c_name(self):
        none = '(no declaration in the database)  '
        for name, line in (
                ('ProbeInlineDouble', 'ProbeInlineDouble()  function  imported as ProbeInlineDouble(_:): func '
                                      'ProbeInlineDouble(_ x: Int) -> Int'),
                ('ProbePlainFunction', 'ProbePlainFunction()  function  imported as ProbePlainFunction(_:): func '
                                       'ProbePlainFunction(_ x: Int) -> Int'),
                ('ProbeRenamedFunction', 'ProbeRenamedFunction()  function  imported as probeRenamed(): func '
                                         'probeRenamed() -> Int'),
                ('ProbeMode', 'ProbeMode  enum  imported as ProbeMode: enum ProbeMode'),
                ('ProbeModeOn', 'ProbeMode.ProbeModeOn  enum-case  imported as ProbeMode.on: case on'),
                ('ProbeFlags', 'ProbeFlags  struct  imported as ProbeFlags: struct ProbeFlags'),
                ('ProbeFlagsBold', 'ProbeFlags.ProbeFlagsBold  class-property  imported as ProbeFlags.bold: static var '
                                   'bold: ProbeFlags { get }'),
                ('ProbeHandler', 'ProbeHandler  typealias  imported as ProbeHandler: typealias ProbeHandler = (Int) -> '
                                 'Void'),
                ('ProbePoint', 'ProbePoint  struct  imported as ProbePoint: struct ProbePoint')):
            status, rows, text = query(self.paths, name=name)
            self.assertEqual(status, 0, text)
            self.assertEqual(rows.splitlines(), [none + line], name)

    def test_not_importable_members_of_a_class(self):
        status, rows, text = query(self.paths, not_importable='Probe')
        self.assertEqual(status, 0, text)
        self.assertEqual(rows.splitlines(), [
            'Probe: its declarations that Swift does not import through the bridging header of SIF',
            EXPECTED_HEADER[19], EXPECTED_HEADER[20], EXPECTED_HEADER[21], EXPECTED_HEADER[22],
            'module/Probe.m:8  -[Probe() privateHelper]  method  NOT IMPORTED: declared in an implementation file; '
            'Swift sees only the headers the bridging header reads',
        ], text)

    def test_status_block_names_the_module_and_its_state(self):
        status, rows, text = query(self.paths, header=H)
        block = text.partition('\n--- status ---\n')[2]
        self.assertIn('swift imports: module SIF (bridging header module/Bridge.h): current, compiler %s'
                      % FIXTURE_COMPILER, block)
        self.assertNotIn('INCOMPLETE', block)

    def test_usr_forms_match_the_database(self):
        # Every Objective-C declaration of the symbol graph that the
        # database records is found by its USR (macros by the USR computed
        # from their location).
        con = sqlite3.connect(self.paths.db)
        try:
            # The kinds the database has tables of: Objective-C classes,
            # protocols and members, and macros.
            imported = set(r[0] for r in con.execute("SELECT usr FROM swift_import WHERE usr LIKE 'c:objc%' OR usr "
                                                     "LIKE '%@macro@%'"))
        finally:
            con.close()
        known = swiftimports.database_usrs(self.paths.db, self.root)
        self.assertEqual(sorted(imported - known), [])
        self.assertIn('c:Probe.h@204@macro@PROBE_LIMIT', known)


class IncrementalTest(unittest.TestCase):
    def setUp(self):
        self.swiftc = skip_unless_compiler(self)
        self.root, self.paths = make_root(self.swiftc)
        status, log = update_imports(self.paths)
        self.assertEqual(status, 0, log)

    def test_a_second_update_skips_the_current_module(self):
        status, log = update_imports(self.paths)
        self.assertEqual(status, 0, log)
        self.assertIn('swift imports: extracted 0, failed 0, skipped as current 1', log[-1])

    def test_a_header_edit_makes_it_stale_and_a_swift_edit_does_not(self):
        with open(os.path.join(self.root, 'module', 'Use.swift'), 'a') as f:
            f.write('\n// edited\n')
        status, block = self.status_block()
        self.assertEqual(status, 0, block)
        with open(os.path.join(self.root, 'module', 'Probe.h'), 'a') as f:
            f.write('\n// edited\n')
        status, block = self.status_block()
        self.assertEqual(status, 3, block)
        self.assertIn('swift imports: module SIF (bridging header module/Bridge.h): STALE (input changed: '
                      'module/Probe.h)', block)
        self.assertIn('INCOMPLETE: the swift_import table of 1 module is not current', block)
        status, log = update_imports(self.paths)
        self.assertEqual(status, 0, log)
        self.assertIn('swift imports: extracted 1, failed 0, skipped as current 0', log[-1])
        # The header edit made the Objective-C unit that reads it stale too.
        status, block = self.status_block()
        self.assertEqual(status, 3, block)
        self.assertNotIn('swift_import', block.split('swift imports:')[0])
        self.assertEqual(codedb.update(self.paths, objc=True, swift=False, imports=False, log=lambda m: None), 0)
        self.assertEqual(self.status_block()[0], 0)

    def test_a_failed_compile_is_recorded_and_the_earlier_rows_kept(self):
        with open(os.path.join(self.root, 'module', 'Probe.h'), 'a') as f:
            f.write('\n@interface Broken : NSObject\n')
        status, log = update_imports(self.paths)
        self.assertEqual(status, 1, log)
        status, rows, text = query(self.paths, name='initWithTitle:')
        self.assertEqual(status, 3, text)
        self.assertIn('imported as Probe.init(title:)', rows)
        self.assertIn('swift imports: module SIF (bridging header module/Bridge.h): FAILED (', text)

    def test_imports_only_through_the_command_line(self):
        with open(os.path.join(self.root, 'module', 'Probe.h'), 'a') as f:
            f.write('\n// edited\n')
        status, out, err = run_main(self.paths, 'update', '--imports-only')
        self.assertEqual(status, 0, out + err)
        self.assertIn('swift imports: extracted 1, failed 0, skipped as current 0', out)
        # The Objective-C units and the Swift side were not touched.
        self.assertNotIn('extracted 0 (0 with parse errors)', out)
        self.assertNotIn('swift: extracted', out)
        status, out, err = run_main(self.paths, 'update', '--objc-only')
        self.assertEqual(status, 0, out + err)
        self.assertNotIn('swift imports:', out)
        status, out, err = run_main(self.paths, 'swiftimports', 'initWithTitle:')
        self.assertEqual(status, 0, out + err)
        self.assertIn('imported as Probe.init(title:)', out)

    def status_block(self):
        status, rows, text = query(self.paths, header=H)
        return status, text.partition('\n--- status ---\n')[2]


class SchemaTest(unittest.TestCase):
    def test_an_old_import_schema_is_refused_with_what_to_run(self):
        root = os.path.join(base.make_temp('codedb-swiftimports-schema-'), 'repo')
        os.makedirs(root)
        db = os.path.join(root, 'db.sqlite')
        con = sqlite3.connect(db)
        con.executescript('PRAGMA user_version = %d; CREATE TABLE tu(id INTEGER PRIMARY KEY); '
                          'CREATE TABLE tu_input(tu INTEGER); CREATE TABLE send(tu INTEGER); '
                          'CREATE TABLE swift_import_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL); '
                          "INSERT INTO swift_import_meta VALUES('schema_version', '1'); "
                          'CREATE TABLE swift_import(module TEXT, usr TEXT);' % codedb.SCHEMA_VERSION)
        con.close()
        paths = codedb.Paths(root, db=db, cdb=os.path.join(root, 'none.jsonl'))
        out = io.StringIO()
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.swiftimports(paths, name='x', out=out)
        self.assertIn('the swift_import tables in %s have schema version 1, not %d; run codedb.py update '
                      '--imports-only' % (db, si.IMPORT_SCHEMA_VERSION), str(cm.exception))

    def test_no_import_tables_is_refused_with_what_to_run(self):
        root = os.path.join(base.make_temp('codedb-swiftimports-schema-'), 'repo')
        os.makedirs(root)
        db = os.path.join(root, 'db.sqlite')
        con = sqlite3.connect(db)
        con.executescript('PRAGMA user_version = %d; CREATE TABLE tu(id INTEGER PRIMARY KEY); '
                          'CREATE TABLE tu_input(tu INTEGER); CREATE TABLE send(tu INTEGER);' % codedb.SCHEMA_VERSION)
        con.close()
        paths = codedb.Paths(root, db=db, cdb=os.path.join(root, 'none.jsonl'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            codedb.swiftimports(paths, name='x', out=io.StringIO())
        self.assertIn('has no swift_import tables; run codedb.py update --imports-only', str(cm.exception))

    def test_writing_replaces_tables_of_another_version(self):
        root = base.make_temp('codedb-swiftimports-schema-')
        db = os.path.join(root, 'db.sqlite')
        con = sqlite3.connect(db)
        con.executescript('CREATE TABLE swift_import_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL); '
                          "INSERT INTO swift_import_meta VALUES('schema_version', '1'); "
                          'CREATE TABLE swift_import_unit(module TEXT PRIMARY KEY, compiler TEXT, created_at TEXT, '
                          'incomplete TEXT);')
        con.close()
        sg = os.path.join(root, 'sg')
        write(os.path.join(sg, 'M.symbols.json'), json.dumps({'symbols': [], 'relationships': []}))
        si.write_imports(db, 'M', sg, {'h.h': 'd'}, 'compiler', cmd_digest='c', tool_digest='t', bridging_header='h.h')
        con = sqlite3.connect(db)
        try:
            self.assertEqual(con.execute("SELECT value FROM swift_import_meta WHERE key='schema_version'").fetchone(),
                             (str(si.IMPORT_SCHEMA_VERSION),))
            self.assertEqual(con.execute('SELECT module, cmd_digest, tool_digest, bridging_header FROM '
                                         'swift_import_unit').fetchall(), [('M', 'c', 't', 'h.h')])
        finally:
            con.close()


# A Swift probe per declaration the header form says is not imported (other
# than for a reason unknown): each must fail to type-check against the
# fixture's bridging header, and the control must pass.
PROBES = {
    'PROBE_EMPTY': 'let _ = PROBE_EMPTY',
    'PROBE_TWICE': 'let _ = PROBE_TWICE(1)',
    'PROBE_CLASS': 'let _ = PROBE_CLASS',
    'ProbeAtomicCounter': 'let _ = ProbeAtomicCounter',
    'ProbeAtomicHolder.atomicValue': 'let _ = ProbeAtomicHolder().atomicValue',
    '-[ProbeAtomicHolder atomicValue]': 'let _ = ProbeAtomicHolder().atomicValue()',
    '-[ProbeAtomicHolder setAtomicValue:]': 'ProbeAtomicHolder().setAtomicValue(1)',
    '-[ProbeGone goneMethod]': 'func f(_ g: ProbeGone) { g.goneMethod() }',
    'ProbeHidden': 'let _ = ProbeHidden()',
    '-[Probe logFormat:]': 'Probe(title: "").logFormat("x")',
    '-[Probe hiddenFromSwift]': 'Probe(title: "").hiddenFromSwift()',
    '-[Probe init]': 'let _ = Probe()',
    'ProbeGone': 'let _ = ProbeGone()',
    'ProbeFile.hiddenThing': 'func f(_ p: ProbeFile) { _ = p.hiddenThing }',
    '-[ProbeFile hiddenThing]': 'func f(_ p: ProbeFile) { _ = p.hiddenThing() }',
    '-[ProbeFile setHiddenThing:]': 'func f(_ p: ProbeFile) { p.setHiddenThing(nil) }',
    '-[ProbeFile makeHidden]': 'func f(_ p: ProbeFile) { _ = p.makeHidden() }',
    'ProbeExtra': 'let _ = ProbeExtra()',
    '-[ProbeExtra extraOnly]': 'func f(_ p: NSObject) { (p as! ProbeExtra).extraOnly() }',
}
CONTROL = ('let _ = PROBE_LIMIT; let _ = PROBE_NAME; let _ = ProbeTitleKey; let _ = ProbeAtomicHolder().plainValue; '
           'let p = Probe(title: ""); let _ = p.count; p.title = "x"; KitThing().kitMethod(); '
           # Usable although absent: ProbeFile.localPath, through the getter
           # (the collision rule's "probably usable through").
           'let _: String = ProbeFile().localPath(); '
           'let _ = ProbeInlineDouble(1); let _ = ProbePlainFunction(1); let _ = probeRenamed(); '
           'let _ = ProbeMode.on; let _ = ProbeFlags.bold; let _: ProbeHandler = { _ in }; '
           'let _ = ProbePoint(x: 1, y: 2)')


class SwiftcAgreementTest(unittest.TestCase):
    def setUp(self):
        self.swiftc = skip_unless_compiler(self)
        self.d = base.make_temp('codedb-swiftimports-probe-')

    def typecheck(self, name, text):
        path = os.path.join(self.d, name.replace('/', '_').replace(':', '_').replace('[', '').replace(']', '')
                            .replace(' ', '_') + '.swift')
        write(path, 'import Foundation\n' + text + '\n')
        r = subprocess.run([self.swiftc, '-typecheck', '-sdk', codedb.current_sdk()[0], '-target',
                            'arm64-apple-macos13.0', '-import-objc-header',
                            os.path.join(FIXTURE, 'module', 'Bridge.h'), '-F', os.path.join(FIXTURE, 'module'),
                            '-module-cache-path', MODULE_CACHE, path],
                           capture_output=True, text=True, timeout=300)
        return r.returncode, r.stderr

    def test_the_control_type_checks(self):
        status, err = self.typecheck('control', CONTROL)
        self.assertEqual(status, 0, err)

    def test_each_declaration_said_not_to_be_imported_fails_to_type_check(self):
        for name, text in sorted(PROBES.items()):
            status, err = self.typecheck(name, text)
            self.assertNotEqual(status, 0, '%s type-checks: %s' % (name, text))
            self.assertIn('error:', err, name)

    def test_every_not_imported_line_of_the_fixture_has_a_probe_or_says_unknown(self):
        for line in EXPECTED_HEADER:
            if 'NOT IMPORTED' in line and 'IMPORTED WITHOUT' not in line:
                name = line.split('  ')[1]
                self.assertIn(name, PROBES, line)


if __name__ == '__main__':
    unittest.main()
