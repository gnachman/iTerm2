#!/usr/bin/env python3
"""Tests for codedb.py classstate (classstate.py) and verifyinventory
(verify_inventory.py), and for the extractor facts they read:
objc_ivar.import_facts and type_encoding, c_static.import_facts and
static_ref.sync_lock.

Run with the other code database tests:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_*.py'

Like test_codedb_state.py, it needs only Homebrew LLVM and the SDK: the
fixtures under classstate_fixtures/ declare their own root class. Expected
values are written out by hand from the fixtures. owner.m, owner_cat.m,
peer.m and cxx.mm are compiled with ARC and legacy.m with manual reference
counting; orphan.m is compiled by no unit. The importability rules are
checked against the verdicts swiftc gave for a test header (see
classstate.importability).
"""

import collections
import io
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import classstate  # noqa: E402
import codedb  # noqa: E402
import test_codedb as base  # noqa: E402
import test_codedb_state as state  # noqa: E402
import verify_inventory  # noqa: E402

FIXTURES = os.path.join(HERE, 'classstate_fixtures')
S = 'sources/'
ARC = ['-fobjc-arc']
MAINS = ((S + 'owner.m', ARC), (S + 'owner_cat.m', ARC), (S + 'peer.m', ARC), (S + 'legacy.m', []), (S + 'legacy_arc.m', ARC), (S + 'owner_mrr.m', []),
         (S + 'cxx.mm', ARC + ['-std=c++17']), (S + 'windows.m', ARC))


def setUpModule():
    base.setUpModule()


def tearDownModule():
    base.tearDownModule()


def make_fixture_root():
    """A copy of the fixtures, extracted, and a git repository (the
    inventory lists its files with git ls-files)."""
    d = base.make_temp('codedb-classstate-')
    root = os.path.join(d, 'repo')
    shutil.copytree(FIXTURES, root)
    paths = base.make_paths(root)
    state.write_cdb(root, paths.cdb, MAINS)
    status = codedb.update(paths, log=lambda m: None)
    subprocess.run(['git', 'init', '-q', root], check=True)
    subprocess.run(['git', '-C', root, 'add', '-A'], check=True)
    return root, paths, status


def rows(db, sql, args=()):
    con = sqlite3.connect(db)
    try:
        return con.execute(sql, args).fetchall()
    finally:
        con.close()


class ImportabilityRulesTest(unittest.TestCase):
    """Each rule of classstate.importability. The cases marked swiftc are
    what swiftc -typecheck reported for a property of that type in a test
    header."""

    def verdict(self, type_class, facts=''):
        return classstate.importability(type_class, facts)[0]

    def test_scalars(self):
        self.assertEqual(self.verdict('scalar'), 'yes')
        self.assertEqual(self.verdict('scalar', 'enum-plain'), 'degraded')  # swiftc: struct PlainEnum
        self.assertEqual(self.verdict('scalar', 'enum-ns'), 'yes')
        self.assertEqual(self.verdict('scalar', 'enum-options'), 'yes')
        self.assertEqual(self.verdict('scalar', 'int128'), 'no')  # swiftc: no member
        self.assertEqual(self.verdict('scalar', 'long-double'), 'degraded')  # swiftc: Double
        self.assertEqual(self.verdict('scalar', 'float16'), 'degraded')
        self.assertEqual(self.verdict('scalar', 'complex'), 'no')  # swiftc: no member
        self.assertEqual(self.verdict('scalar', 'unusual-builtin'), 'unknown')
        self.assertEqual(self.verdict('atomic', 'atomic'), 'no')  # swiftc: no member

    def test_records(self):
        self.assertEqual(self.verdict('struct'), 'yes')
        self.assertEqual(self.verdict('struct', 'object-member-strong'), 'no')  # swiftc: no member
        self.assertEqual(self.verdict('struct', 'object-member-weak'), 'no')  # swiftc: no member
        self.assertEqual(self.verdict('struct', 'object-member-unsafe_unretained'), 'degraded')  # swiftc: Unmanaged
        self.assertEqual(self.verdict('struct', 'object-member-unqualified'), 'unknown')
        self.assertEqual(self.verdict('struct', 'flexible-array-member in-incomplete-array'), 'degraded')
        self.assertEqual(self.verdict('struct', 'in-int128'), 'degraded')  # swiftc: member dropped
        self.assertEqual(self.verdict('struct', 'in-atomic'), 'unknown')
        self.assertEqual(self.verdict('struct', 'bit-field-member'), 'yes')  # swiftc: imported
        # N2: a member whose own import is degraded makes the struct degraded.
        self.assertEqual(self.verdict('struct', 'in-enum-plain'), 'degraded')
        self.assertEqual(self.verdict('struct', 'in-long-double'), 'degraded')  # swiftc: Double member
        self.assertEqual(self.verdict('struct', 'in-object-member-strong'), 'degraded')  # swiftc: OpaquePointer member
        self.assertEqual(self.verdict('struct', 'array-member'), 'degraded')  # swiftc: tuple member
        self.assertEqual(self.verdict('struct', 'in-cxx-template'), 'no')
        self.assertEqual(self.verdict('union', 'union'), 'yes')  # swiftc: imported
        self.assertEqual(self.verdict('struct', 'incomplete-record'), 'unknown')

    def test_cxx(self):
        self.assertEqual(self.verdict('cxx-object', 'cxx-record'), 'no')
        self.assertEqual(self.verdict('c-pointer', 'in-cxx-record'), 'no')
        self.assertEqual(self.verdict('c-pointer', 'cxx-reference'), 'no')
        self.assertEqual(self.verdict('c-pointer', 'member-pointer'), 'no')

    def test_pointers_and_blocks(self):
        self.assertEqual(self.verdict('c-pointer'), 'yes')  # swiftc: UnsafeMutablePointer<Int32>
        self.assertEqual(self.verdict('c-pointer', 'function-pointer'), 'yes')  # swiftc: @convention(c)
        self.assertEqual(self.verdict('c-pointer', 'function-pointer variadic-function'), 'degraded')  # OpaquePointer
        self.assertEqual(self.verdict('c-pointer', 'in-incomplete-record opaque-pointee'), 'degraded')  # OpaquePointer
        self.assertEqual(self.verdict('c-pointer', 'cf-bridged in-incomplete-record opaque-pointee'), 'yes')  # class
        self.assertEqual(self.verdict('c-pointer', 'in-object-member-strong'), 'degraded')  # swiftc: OpaquePointer
        self.assertEqual(self.verdict('c-pointer', 'in-int128'), 'unknown')
        self.assertEqual(self.verdict('block'), 'yes')
        self.assertEqual(self.verdict('block', 'in-enum-plain'), 'yes')  # swiftc: ((PlainEnum) -> Void)
        self.assertEqual(self.verdict('block', 'in-object-member-strong'), 'unknown')
        self.assertEqual(self.verdict('object'), 'yes')
        self.assertEqual(self.verdict('selector'), 'yes')

    def test_arrays_vectors_bitfields_and_the_rest(self):
        self.assertEqual(self.verdict('array'), 'degraded')
        self.assertEqual(self.verdict('array', 'in-int128'), 'unknown')
        self.assertEqual(self.verdict('vector', 'vector-element-float vector-elements-4'), 'yes')  # swiftc: SIMD4
        self.assertEqual(self.verdict('vector', 'vector-element-char vector-elements-16'), 'yes')  # swiftc: SIMD16
        self.assertEqual(self.verdict('vector', 'vector-element-float vector-elements-5'), 'unknown')
        self.assertEqual(self.verdict('vector', 'vector-element-_Float16 vector-elements-4'), 'degraded')
        self.assertEqual(self.verdict('vector', 'vector-element-other vector-elements-4'), 'unknown')
        self.assertEqual(self.verdict('bit-field'), 'degraded')
        self.assertEqual(self.verdict('bit-field', 'enum-plain'), 'degraded')
        self.assertEqual(self.verdict('bit-field', 'int128'), 'no')
        self.assertEqual(self.verdict('other', 'other-type'), 'unknown')
        self.assertEqual(self.verdict('struct', 'too-deep'), 'unknown')
        self.assertEqual(self.verdict('struct', 'in-dependent-type'), 'unknown')


# Each property of classstate_fixtures/swiftcheck/Probe.h: the verdict
# classstate.importability gives from the facts of its synthesized ivar, and
# Swift statements about it with what swiftc must say of each: 'ok' (no
# error) or a text its error contains. The statements show the import the
# verdict claims: yes as the natural type, degraded as the degraded form,
# no as no member at all.
SWIFTC_CASES = (
    ('plain', 'degraded', (('let _: PlainEnum = PlainEnum(rawValue: 0)', 'ok'), ('_ = p.plain', 'ok'))),
    ('nice', 'yes', (('let _: NiceEnum? = NiceEnum(rawValue: 0)', 'ok'), ('_ = p.nice', 'ok'))),
    ('big', 'no', (('_ = p.big', "has no member 'big'"),)),
    ('ld', 'degraded', (('let _: Double = p.ld', 'ok'),)),
    ('atom', 'no', (('_ = p.atom', "has no member 'atom'"),)),
    ('cplx', 'no', (('_ = p.cplx', "has no member 'cplx'"),)),
    ('half', 'degraded', (('let _: Float16 = p.half', 'ok'),)),
    ('strongS', 'no', (('_ = p.strongS', "has no member 'strongS'"),)),
    ('weakS', 'no', (('_ = p.weakS', "has no member 'weakS'"),)),
    ('unretS', 'degraded', (('let _: Unmanaged<AnyObject>? = p.unretS.obj', 'ok'),)),
    ('flexS', 'degraded', (('_ = p.flexS.n', 'ok'), ('_ = p.flexS.tail', "has no member 'tail'"))),
    ('u', 'yes', (('let _: Int32 = p.u.i', 'ok'),)),
    ('bitS', 'yes', (('let _: UInt32 = p.bitS.a', 'ok'),)),
    ('i128S', 'degraded', (('_ = p.i128S.x', 'ok'), ('_ = p.i128S.big', "has no member 'big'"))),
    ('opaque', 'degraded', (('let _: OpaquePointer? = p.opaque', 'ok'),)),
    ('bridged', 'yes', (('let _: BridgedThing? = p.bridged', 'ok'),)),
    ('fn', 'yes', (('let _: (@convention(c) (Int32) -> Int32)? = p.fn', 'ok'),)),
    ('varFn', 'degraded', (('let _: OpaquePointer? = p.varFn', 'ok'),)),
    ('vec', 'yes', (('let _: SIMD4<Float> = p.vec', 'ok'),)),
    ('plainBlock', 'yes', (('let _: ((PlainEnum) -> Void)? = p.plainBlock', 'ok'),)),
    # The facts do not say whether the struct is a parameter by value or
    # through a pointer, so the verdict is unknown; swiftc drops this one.
    ('strongSBlock', 'unknown', (('_ = p.strongSBlock', "has no member 'strongSBlock'"),)),
    ('intPtr', 'yes', (('let _: UnsafeMutablePointer<Int32>? = p.intPtr', 'ok'),)),
    ('strongSPtr', 'degraded', (('let _: OpaquePointer? = p.strongSPtr', 'ok'),)),
    ('sel', 'yes', (('let _: Selector? = p.sel', 'ok'),)),
    ('object', 'yes', (('let _: Any? = p.object', 'ok'),)),
)


# The same for classstate_fixtures/swiftcheck/ProbeFoundation.h, which needs
# the SDK and its API notes.
SWIFTC_SDK_CASES = (
    ('strArr', 'yes', (('let _: [String]? = p.strArr', 'ok'),)),
    ('mutArr', 'degraded', (('let _: NSMutableArray? = p.mutArr', 'ok'), ('let _: [String]? = p.mutArr', 'cannot'))),
    ('nestedArr', 'degraded', (('let _: [NSMutableArray]? = p.nestedArr', 'ok'),)),
    ('dictOfArr', 'yes', (('let _: [String: [String]]? = p.dictOfArr', 'ok'),)),
    ('generic', 'degraded', (('let _: FGen<NSString>? = p.generic', 'ok'),
                             ('let _: FGen<String>? = p.generic', 'requires that'))),
    ('kindof', 'degraded', (('let _: NSObject? = p.kindof', 'ok'),)),
    ('protoObj', 'yes', (('let _: (any NSCopying)? = p.protoObj', 'ok'),)),
    ('cfType', 'yes', (('let _: AnyObject? = p.cfType', 'ok'),)),
    ('vaList', 'yes', (('let _: CVaListPointer = p.vaList', 'ok'),)),
    ('unretIdPtr', 'yes', (('let _: AutoreleasingUnsafeMutablePointer<AnyObject?>? = p.unretIdPtr', 'ok'),)),
    ('unfair', 'yes', (('let _: os_unfair_lock = p.unfair', 'ok'),)),
    ('arrS', 'degraded', (('let _: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = p.arrS.buf', 'ok'),)),
    ('h4', 'degraded', (('let _: SIMD4<Float16> = p.h4', 'ok'),)),
    ('variadicBlock', 'no', (('_ = p.variadicBlock', "has no member 'variadicBlock'"),)),
    ('ldFieldS', 'degraded', (('let _: Double = p.ldFieldS.ld', 'ok'),)),
    ('ptrToStrongS', 'degraded', (('let _: OpaquePointer? = p.ptrToStrongS.p', 'ok'),)),
    # F1: a part that loses its type arguments degrades the block, function
    # pointer or pointer.
    ('mutArrBlock', 'degraded', (('let _: ((NSMutableArray?) -> Void)? = p.mutArrBlock', 'ok'),)),
    ('mutArrBlockTypedef', 'degraded', (('let _: ((NSMutableArray?) -> Void)? = p.mutArrBlockTypedef', 'ok'),)),
    ('mutArrFunction', 'degraded', (('let _: (@convention(c) (NSMutableArray?) -> Void)? = p.mutArrFunction', 'ok'),)),
    ('genericBlock', 'degraded', (('let _: ((FGen<NSString>?) -> Void)? = p.genericBlock', 'ok'),)),
    ('kindofBlock', 'degraded', (('let _: ((NSView?) -> Void)? = p.kindofBlock', 'ok'),)),
    ('mutArrPtr', 'degraded', (('let _: AutoreleasingUnsafeMutablePointer<NSMutableArray?>? = p.mutArrPtr', 'ok'),)),
    # N1 and N3.
    ('nsobjectProto', 'degraded', (('let _: (any FProto)? = p.nsobjectProto', 'ok'),)),
    ('protoSet', 'degraded', (('let _: Set<AnyHashable>? = p.protoSet', 'ok'),)),
    ('protoKeyDict', 'degraded', (('let _: [AnyHashable: String]? = p.protoKeyDict', 'ok'),)),
    ('arrayPointer', 'degraded', (('let _: UnsafeMutablePointer<(Int32, Int32, Int32, Int32)>? = p.arrayPointer', 'ok'),)),
    ('arrayStructPointer', 'degraded', (('let _: UnsafeMutablePointer<ArrayStruct>? = p.arrayStructPointer', 'ok'),)),
    # F5: an array member two records deep, and inside a union.
    ('nested2', 'degraded', (('let _: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = p.nested2.inner.buf',
                              'ok'),)),
    ('unionArr', 'degraded', (('let _: (Int32, Int32) = p.unionArr.u.a', 'ok'),)),
    # Third review: IMP is variadic where Swift reads the SDK
    # (OBJC_OLD_DISPATCH_PROTOTYPES=1); char * is not va_list; dispatch and
    # os objects are Swift classes; forward declarations are dropped.
    ('imp', 'degraded', (('let _: OpaquePointer? = p.imp', 'ok'),)),
    ('mcstr', 'yes', (('let _: UnsafeMutablePointer<CChar>? = p.mcstr', 'ok'),
                      ('let _: CVaListPointer = p.mcstr', 'cannot'))),
    ('queue', 'yes', (('let _: DispatchQueue? = p.queue', 'ok'),)),
    ('group', 'yes', (('let _: DispatchGroup? = p.group', 'ok'),)),
    ('semaphore', 'yes', (('let _: DispatchSemaphore? = p.semaphore', 'ok'),)),
    ('source', 'yes', (('let _: DispatchSource? = p.source', 'ok'),)),
    ('io', 'yes', (('let _: DispatchIO? = p.io', 'ok'),)),
    ('log', 'yes', (('let _: OSLog? = p.log', 'ok'),)),
    ('forwardClass', 'unknown', (('_ = p.forwardClass', "has no member 'forwardClass'"),)),
    ('forwardProto', 'unknown', (('_ = p.forwardProto', "has no member 'forwardProto'"),)),
)


def sdk_args(cache):
    sdk = subprocess.run(['xcrun', '--show-sdk-path'], check=True, capture_output=True, text=True).stdout.strip()
    return ARC + ['-fmodules', '-fmodules-cache-path=' + cache, '-isysroot', sdk]


def swiftc_errors(header, lines, d, name):
    """{line: [error]} of swiftc -typecheck of lines against header."""
    swift = os.path.join(d, name)
    with open(swift, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    r = subprocess.run(['xcrun', 'swiftc', '-typecheck', '-target', 'arm64-apple-macos13', '-import-objc-header', header,
                        swift], capture_output=True, text=True)
    errors = collections.defaultdict(list)
    prefix = swift + ':'
    for line in r.stderr.splitlines():
        if line.startswith(prefix) and ': error: ' in line:
            errors[int(line[len(prefix):].split(':')[0])].append(line.split(': error: ', 1)[1])
    return errors


def probe_lines(cases, cls):
    lines = ['import Foundation', 'import simd', 'import os', 'func probe(_ p: %s) {' % cls]
    where = {}
    for prop, _, statements in cases:
        for statement, want in statements:
            lines.append('    ' + statement)
            where[len(lines)] = (prop, statement, want)
    lines.append('}')
    return lines, where


class SwiftcSDKAgreementTest(unittest.TestCase):
    """SwiftcAgreementTest for the types that need the SDK, and the
    inherited accessor of an SDK superclass."""

    @classmethod
    def setUpClass(cls):
        try:
            subprocess.run(['xcrun', '--find', 'swiftc'], check=True, capture_output=True)
        except (OSError, subprocess.CalledProcessError):
            raise unittest.SkipTest('swiftc is not available')
        d = base.make_temp('codedb-swiftc-sdk-')
        cls.root = os.path.join(d, 'repo')
        shutil.copytree(os.path.join(FIXTURES, 'swiftcheck'), os.path.join(cls.root, 'swiftcheck'))
        cls.db = os.path.join(d, 'probe.sqlite')
        status, err, _ = base.extract(cls.root, 'swiftcheck/ProbeFoundation.m', cls.db,
                                      extra=sdk_args(os.path.join(d, 'modcache')))
        if status != 0:
            raise AssertionError('extraction failed: %s' % err)
        cls.facts = dict((name[1:], (tclass, facts)) for name, tclass, facts in rows(
            cls.db, "SELECT name, type_class, import_facts FROM objc_ivar WHERE class_name = 'FProbe'"))
        lines, cls.where = probe_lines(SWIFTC_SDK_CASES, 'FProbe')
        cls.errors = swiftc_errors(os.path.join(cls.root, 'swiftcheck', 'ProbeFoundation.h'), lines, d, 'probe.swift')

    def test_verdicts(self):
        got = dict((p, classstate.importability(*self.facts[p])[0]) for p, _, _ in SWIFTC_SDK_CASES)
        self.assertEqual(got, dict((p, v) for p, v, _ in SWIFTC_SDK_CASES))

    def test_swiftc_agrees(self):
        for n, (prop, statement, want) in sorted(self.where.items()):
            errors = self.errors.get(n, [])
            if want == 'ok':
                self.assertEqual(errors, [], statement)
            else:
                self.assertTrue(any(want in e for e in errors), '%s: %s' % (statement, errors))

    def test_reasons(self):
        self.assertIn('AnyObject', classstate.importability(*self.facts['cfType'])[1])
        self.assertIn('CVaListPointer', classstate.importability(*self.facts['vaList'])[1])
        # On arm64 va_list is char *: a plain char * must not read as va_list.
        self.assertNotIn('va-list', self.facts['mcstr'][1])
        self.assertNotIn('CVaListPointer', classstate.importability(*self.facts['mcstr'])[1])
        self.assertIn('OBJC_OLD_DISPATCH_PROTOTYPES', classstate.importability(*self.facts['imp'])[1])
        self.assertIn('AutoreleasingUnsafeMutablePointer', classstate.importability(*self.facts['unretIdPtr'])[1])
        self.assertIn('must not be copied', classstate.importability(*self.facts['unfair'])[1])

    def test_inherited_accessor_from_the_sdk(self):
        con = sqlite3.connect(self.db)
        try:
            chain = codedb.class_chain(con, 'FProbe')
            # NSView declares identifier through NSUserInterfaceItemIdentification.
            self.assertEqual(classstate.inherited_accessor(codedb, con, chain, 'identifier'),
                             'inherited from NSView (SDK, declared by its protocol '
                             'NSUserInterfaceItemIdentification)')
            self.assertEqual(classstate.inherited_accessor(codedb, con, chain, 'layer'),
                             'inherited from NSView (SDK)')
            self.assertIsNone(classstate.inherited_accessor(codedb, con, chain, 'noSuchAccessorAnywhere'))
            # F5: two superclasses up, through the repository class FProbe.
            self.assertEqual(classstate.inherited_accessor(codedb, con, codedb.class_chain(con, 'FDeep'), 'layer'),
                             'inherited from NSView (SDK)')
            # N4: a repository category on an SDK class (CoreParse's on NSObject).
            self.assertEqual(classstate.inherited_accessor(codedb, con, codedb.class_chain(con, 'FDeep'), 'isFancy'),
                             'inherited from NSObject (a repository category on that SDK class)')
            broken = [('X', 'repository x.h:1', {'Y'}), ('Y', 'not recorded', set())]
            self.assertEqual(classstate.inherited_accessor(codedb, con, broken, 'identifier'),
                             'unknown: superclass chain not followed past X (its superclass Y is not recorded)')
        finally:
            con.close()


class SwiftcAgreementTest(unittest.TestCase):
    """The importability rules against swiftc: each verdict is what Swift
    really imports of a property of that type."""

    @classmethod
    def setUpClass(cls):
        try:
            subprocess.run(['xcrun', '--find', 'swiftc'], check=True, capture_output=True)
        except (OSError, subprocess.CalledProcessError):
            raise unittest.SkipTest('swiftc is not available')
        d = base.make_temp('codedb-swiftc-')
        cls.root = os.path.join(d, 'repo')
        shutil.copytree(os.path.join(FIXTURES, 'swiftcheck'), os.path.join(cls.root, 'swiftcheck'))
        db = os.path.join(d, 'probe.sqlite')
        status, err, _ = base.extract(cls.root, 'swiftcheck/Probe.m', db, extra=ARC)
        if status != 0:
            raise AssertionError('extraction failed: %s' % err)
        cls.facts = dict((name[1:], (tclass, facts)) for name, tclass, facts in rows(
            db, "SELECT name, type_class, import_facts FROM objc_ivar WHERE class_name = 'Probe'"))
        cls.facts.update((name, (tclass, facts)) for name, tclass, facts in rows(
            db, "SELECT name, type_class, import_facts FROM c_static WHERE file = 'swiftcheck/Probe.m'"))
        lines = ['import ObjectiveC', 'func probe(_ p: Probe) {']
        cls.where = {}
        for prop, _, statements in SWIFTC_CASES:
            for statement, _ in statements:
                lines.append('    ' + statement)
                cls.where[len(lines)] = (prop, statement)
        lines.append('}')
        swift = os.path.join(d, 'probe.swift')
        with open(swift, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        r = subprocess.run(['xcrun', 'swiftc', '-typecheck', '-target', 'arm64-apple-macos13', '-import-objc-header',
                            os.path.join(cls.root, 'swiftcheck', 'Probe.h'), swift], capture_output=True, text=True)
        cls.errors = collections.defaultdict(list)
        prefix = swift + ':'
        for line in r.stderr.splitlines():
            if line.startswith(prefix) and ': error: ' in line:
                cls.errors[int(line[len(prefix):].split(':')[0])].append(line.split(': error: ', 1)[1])

    def test_every_property_has_facts(self):
        self.assertEqual(sorted(self.facts), sorted(p for p, _, _ in SWIFTC_CASES))

    def test_verdicts(self):
        got = dict((p, classstate.importability(*self.facts[p])[0]) for p, _, _ in SWIFTC_CASES)
        self.assertEqual(got, dict((p, v) for p, v, _ in SWIFTC_CASES))

    def test_swiftc_agrees(self):
        for n, (prop, statement) in sorted(self.where.items()):
            want = [w for p, _, statements in SWIFTC_CASES if p == prop for s, w in statements if s == statement][0]
            errors = self.errors.get(n, [])
            if want == 'ok':
                self.assertEqual(errors, [], statement)
            else:
                self.assertTrue(any(want in e for e in errors), '%s: %s' % (statement, errors))


# Owner's ivars: (type class, import facts, type encoding), by hand from
# owner.h and owner.m.
OWNER_IVAR_FACTS = {
    '_pub': ('scalar', '', 'i'),
    '_pkg': ('scalar', '', 'i'),
    '_count': ('scalar', '', 'i'),
    '_total': ('scalar', '', 'i'),
    '_plain': ('scalar', 'enum-plain', 'i'),
    '_nice': ('scalar', 'enum-ns', 'q'),
    '_big': ('scalar', 'int128', 't'),
    '_atom': ('atomic', 'atomic', 'Ai'),
    '_strongBox': ('struct', 'object-member-strong', '{?="obj"@"n"i}'),
    '_unretainedBox': ('struct', 'object-member-unsafe_unretained', '{?="obj"@"n"i}'),
    '_flex': ('c-pointer', 'in-flexible-array-member in-incomplete-array', '^{?=i[0c]}'),
    '_number': ('union', 'union', '(?="i"i"f"f)'),
    '_flag': ('bit-field', '', 'b1'),
    '_buf': ('array', '', '[8c]'),
    '_callback': ('c-pointer', 'function-pointer', '^?'),
    '_varCallback': ('c-pointer', 'function-pointer variadic-function', '^?'),
    '_plainBlock': ('block', 'in-enum-plain', '@?'),
    '_boxBlock': ('block', 'in-object-member-strong', '@?'),
    # The compiler gives a vector no encoding; an empty text is stored as NULL.
    '_vec': ('vector', 'vector-element-float vector-elements-4', None),
    '_ld': ('scalar', 'long-double', 'D'),
    '_sel': ('selector', '', ':'),
    '_drawer': ('object', '', '@"<Drawing>"'),
    '_opaque': ('c-pointer', 'in-incomplete-record opaque-pointee', '^{Opaque=}'),
    '_weakThing': ('object', '', '@"Thing"'),
    '_other': ('object', '', '@"Thing"'),
    '_name': ('object', '', '@"Thing"'),
}
OWNER_VERDICTS = {
    '_pub': 'yes', '_pkg': 'yes', '_count': 'yes', '_total': 'yes', '_plain': 'degraded', '_nice': 'yes', '_big': 'no',
    '_atom': 'no', '_strongBox': 'no', '_unretainedBox': 'degraded', '_flex': 'degraded', '_number': 'yes',
    '_flag': 'degraded', '_buf': 'degraded', '_callback': 'yes', '_varCallback': 'degraded', '_plainBlock': 'yes',
    '_boxBlock': 'unknown', '_vec': 'yes', '_ld': 'degraded', '_sel': 'yes', '_drawer': 'yes', '_opaque': 'degraded',
    '_weakThing': 'yes', '_other': 'yes', '_name': 'yes',
}


class FactsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths, cls.status = make_fixture_root()

    def test_clean_update_and_schema_version(self):
        self.assertEqual(self.status, 0)
        self.assertEqual(rows(self.paths.db, 'PRAGMA user_version'), [(codedb.SCHEMA_VERSION,)])
        self.assertEqual(codedb.SCHEMA_VERSION, 13)

    def test_ivar_import_facts_and_encodings(self):
        got = dict((n, (c, f, e)) for n, c, f, e in rows(
            self.paths.db, "SELECT DISTINCT name, type_class, import_facts, type_encoding FROM objc_ivar WHERE "
                           "class_name = 'Owner'"))
        self.assertEqual(got, OWNER_IVAR_FACTS)

    def test_manual_reference_counting_struct_member(self):
        self.assertEqual(rows(self.paths.db, "SELECT import_facts, ownership FROM objc_ivar WHERE class_name = "
                                             "'Legacy' AND name = '_box'"),
                         [('object-member-unqualified', 'none')])

    def test_cxx_member(self):
        self.assertEqual(rows(self.paths.db, "SELECT type_class, import_facts FROM objc_ivar WHERE class_name = 'Cxx' "
                                             "AND name = '_counter'"), [('cxx-object', 'cxx-record type-in-main-file')])

    def test_static_import_facts(self):
        self.assertEqual(rows(self.paths.db, "SELECT DISTINCT name, import_facts FROM c_static WHERE file = "
                                             "'sources/owner.m' ORDER BY name"),
                         [('gOwnerTotal', ''), ('sHits', ''), ('sLocal', ''), ('sShared', '')])

    def test_static_ref_lock(self):
        self.assertEqual(rows(self.paths.db, "SELECT line, sync_lock FROM static_ref WHERE name = 'sHits' ORDER BY "
                                             "line"), [(39, None), (45, 'self')])


def by_name(items):
    return dict((i['name'], i) for i in items)


class ClassStateQueryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths, _ = make_fixture_root()

    def ask(self, cls, as_json=False):
        out = io.StringIO()
        status = classstate.classstate(codedb, self.paths, cls, as_json=as_json, out=out)
        return status, out.getvalue()

    def owner(self):
        status, text = self.ask('Owner', as_json=True)
        self.assertEqual(status, 0, text)
        return json.loads(text)

    def test_every_ivar_and_its_verdict(self):
        doc = self.owner()
        self.assertEqual(doc['incomplete'], [])
        self.assertEqual(doc['implementations'], [
            {'file': 'sources/owner.m', 'category': None, 'mode': 'ARC'},
            {'file': 'sources/owner_cat.m', 'category': 'Cat', 'mode': 'ARC'},
            {'file': 'sources/owner_mrr.m', 'category': 'MRR', 'mode': 'manual reference counting'}])
        ivars = by_name(doc['ivars'])
        self.assertEqual(dict((n, i['importable']['verdict']) for n, i in ivars.items()), OWNER_VERDICTS)
        self.assertEqual(dict((n, i['type_encoding']) for n, i in ivars.items()),
                         dict((n, v[2]) for n, v in OWNER_IVAR_FACTS.items()))

    def test_declared(self):
        ivars = by_name(self.owner()['ivars'])
        self.assertEqual((ivars['_pub']['declared']['where'], ivars['_pub']['declared']['access']),
                         ('header @interface', 'public'))
        self.assertEqual(ivars['_pkg']['declared']['access'], 'package')
        self.assertEqual(ivars['_plain']['declared']['where'], 'class extension in a header')
        self.assertEqual(ivars['_nice']['declared']['where'], '@implementation block')
        self.assertEqual(ivars['_count']['declared']['where'], 'synthesized automatically for property count')
        self.assertEqual(ivars['_count']['declared']['backs_properties'],
                         [{'name': 'count', 'attributes': 'nonatomic', 'synthesize_attributes': 'nonatomic',
                           'synthesized': 'automatically'}])
        self.assertEqual([p['name'] for p in ivars['_other']['declared']['backs_properties']], ['name'])
        self.assertEqual(ivars['_other']['declared']['backs_properties'][0]['synthesized'], 'by @synthesize')

    def test_mode_and_ownership(self):
        ivars = by_name(self.owner()['ivars'])
        # The class's @implementation is compiled with ARC; a category of
        # it is not, and the mode says so.
        self.assertEqual((ivars['_weakThing']['mode'], ivars['_weakThing']['ownership'],
                          ivars['_weakThing']['ownership_written']),
                         ('ARC (the @implementation); manual reference counting in sources/owner_mrr.m (category MRR)',
                          'weak', 'weak'))
        self.assertEqual((ivars['_other']['ownership'], ivars['_other']['ownership_written']), ('strong', None))
        self.assertEqual(ivars['_pub']['ownership'], 'none')

    def test_accessors(self):
        ivars = by_name(self.owner()['ivars'])
        no_swift = 'Swift overrides not known (the Swift side is not in this database)'
        self.assertEqual(ivars['_count']['accessor'], [
            {'selector': 'count', 'form': 'getter, without the leading underscore',
             'state': 'synthesized (property count, nonatomic)', 'overridden_by': [],
             'private_methods_consulted': False, 'swift_overrides': no_swift},
            {'selector': 'setCount:', 'form': 'setter, without the leading underscore',
             'state': 'synthesized (property count, nonatomic)', 'overridden_by': [],
             'private_methods_consulted': False, 'swift_overrides': no_swift}])
        self.assertIn('atomic, so not trivial', ivars['_total']['accessor'][0]['state'])
        self.assertEqual(ivars['_flag']['accessor'][0], {
            'selector': 'flag', 'form': 'getter, without the leading underscore',
            'state': 'written by hand at sources/owner.m:31 (not proven trivial)',
            'overridden_by': ['SubOwner (sources/peer.m:20)'], 'private_methods_consulted': False,
            'swift_overrides': no_swift})
        self.assertEqual(ivars['_name']['accessor'][0]['state'],
                         'synthesized for property name, which is backed by _other, not this ivar')
        # cs_base.h declares -[Root pub]: Owner inherits a method named like
        # the ivar (objc-state.md section 2's trap).
        self.assertEqual(ivars['_pub']['accessor'], [
            {'selector': 'pub', 'form': 'getter, without the leading underscore',
             'state': 'inherited from Root (repository)', 'private_methods_consulted': False},
            {'selector': 'setPub:', 'form': 'setter, without the leading underscore', 'state': classstate.NONE_TEXT,
             'private_methods_consulted': False}])
        # B5: the text says so, not only the symbol.
        self.assertIn('not consulted', ivars['_pub']['accessor'][1]['state'])

    def test_swift_overrides_of_an_accessor(self):
        # Third review B1: a Swift subclass that overrides the getter and the
        # setter (a Swift override var) is listed with where it is. The
        # fixtures have no Swift capture, so a copy of the database gets the
        # rows a Swift module would record.
        d = base.make_temp('codedb-classstate-swift-')
        db = os.path.join(d, 'copy.sqlite')
        shutil.copy(self.paths.db, db)
        con = sqlite3.connect(db)
        con.execute('CREATE TABLE IF NOT EXISTS swift_objc_decl(class_name TEXT, selector TEXT, is_override INTEGER, '
                    'overrides_usr TEXT, file TEXT, line INTEGER, is_class_member INTEGER)')
        con.executemany('INSERT INTO swift_objc_decl VALUES (?, ?, 1, ?, ?, ?, 0)', [
            ('SwiftOwner', 'flag', 'c:objc(cs)Owner(im)flag', 'sources/SwiftOwner.swift', 3),
            ('SwiftOwner', 'count', 'c:objc(cs)Owner(im)count', 'sources/SwiftOwner.swift', 5),
            ('SwiftOwner', 'setCount:', 'c:objc(cs)Owner(im)setCount:', 'sources/SwiftOwner.swift', 5)])
        con.commit()
        try:
            chain = codedb.class_chain(con, 'Owner')
            usr = con.execute("SELECT usr FROM objc_ivar WHERE class_name = 'Owner' AND name = '_flag'").fetchone()[0]
            flag = classstate.accessor_info(con, 'Owner', '_flag', usr, codedb, chain)
            self.assertEqual(flag[0]['overridden_by'], ['SubOwner (sources/peer.m:20)',
                                                        'SwiftOwner (Swift, sources/SwiftOwner.swift:3)'])
            usr = con.execute("SELECT usr FROM objc_ivar WHERE class_name = 'Owner' AND name = '_count'").fetchone()[0]
            count = classstate.accessor_info(con, 'Owner', '_count', usr, codedb, chain)
            self.assertEqual([e['overridden_by'] for e in count],
                             [['SwiftOwner (Swift, sources/SwiftOwner.swift:5)'],
                              ['SwiftOwner (Swift, sources/SwiftOwner.swift:5)']])
        finally:
            con.close()

    def test_text_says_private_methods_were_not_consulted(self):
        status, text = self.ask('LegacyHolder')
        self.assertIn('private framework methods not consulted (give --runtime-methods)', text)
        status, text = self.ask('LegacyHolder', as_json=True)
        self.assertIs(json.loads(text)['private_methods_consulted'], False)

    def test_accessor_names_beyond_the_leading_underscore(self):
        # F2: capacity_ (a trailing underscore) has -capacity written by
        # hand; _lit and _depth inherit Root's getter= names isLit and
        # currentDepth.
        status, text = self.ask('LegacyHolder', as_json=True)
        ivars = by_name(json.loads(text)['ivars'])
        capacity = ivars['capacity_']['accessor'][0]
        self.assertEqual((capacity['selector'], capacity['form'], capacity['state'], capacity['overridden_by']), (
            'capacity', 'getter, without the trailing underscore',
            'written by hand at sources/legacy_arc.m:17 (not proven trivial)', []))
        self.assertIn({'selector': 'isLit', 'form': 'is-prefixed getter, without the leading underscore',
                       'state': 'inherited from Root (repository)', 'private_methods_consulted': False},
                      ivars['_lit']['accessor'])
        self.assertIn({'selector': 'currentDepth', 'form': 'getter= of property depth of Root',
                       'state': 'inherited from Root (repository)', 'private_methods_consulted': False},
                      ivars['_depth']['accessor'])

    def test_accessors_from_a_run_time_list(self):
        # F3: without a list, a missing name says private framework methods
        # were not consulted; with one, the list's implementer is named.
        status, text = self.ask('LegacyHolder', as_json=True)
        pair = by_name(json.loads(text)['ivars'])['_pair']['accessor']
        self.assertEqual(pair[1]['state'], classstate.NONE_TEXT)
        out = io.StringIO()
        status = classstate.classstate(codedb, self.paths, 'LegacyHolder', as_json=True, out=out,
                                       runtime_methods=[os.path.join(FIXTURES, 'runtime',
                                                                     'runtime-methods-fixture.tsv')])
        doc = json.loads(out.getvalue())
        self.assertIs(doc['private_methods_consulted'], True)
        pair = by_name(doc['ivars'])['_pair']['accessor']
        self.assertEqual(pair[1], {'selector': 'setPair:', 'form': 'setter, without the leading underscore',
                                   'state': 'inherited from Root (framework, private or public; from the run-time '
                                            'list of macOS 99.0 (FIXTURE) [live runtime, 0 frameworks])',
                                   'private_methods_consulted': True})
        # N7: LegacyHolder's own -capacity overrides the list's -[Root capacity].
        capacity = by_name(doc['ivars'])['capacity_']['accessor'][0]['state']
        self.assertTrue(capacity.startswith('written by hand at sources/legacy_arc.m:17 (not proven trivial); '
                                            'overrides a framework method: inherited from Root'), capacity)
        self.assertEqual(pair[0]['state'], 'none in the repository, the SDK headers and the run-time list of macOS '
                                           '99.0 (FIXTURE) [live runtime, 0 frameworks]')

    def test_a_run_time_list_cut_short_is_refused(self):
        bad = os.path.join(base.make_temp('codedb-rt-'), 'short.tsv')
        with open(bad, 'w') as f:
            f.write('# os: macOS 99.0\n# kind: live\nC\tRoot\t\n')
        with self.assertRaises(codedb.CodeDBError):
            classstate.classstate(codedb, self.paths, 'LegacyHolder', out=io.StringIO(), runtime_methods=[bad])

    def test_users_and_references_from_outside(self):
        ivars = by_name(self.owner()['ivars'])
        pub = ivars['_pub']
        self.assertEqual(pub['summary']['references'], 7)
        self.assertEqual([(r['line'], r['outside_own_code']) for r in ivars['_pkg']['references']
                          if r['file'] == S + 'owner_mrr.m'],
                         [(5, ['from a category\'s file, not the file of the @implementation (sources/owner_mrr.m)'])])
        self.assertEqual(pub['summary']['by_access'], {'read': 1, 'write': 6})
        outside = [(r['file'], r['line'], r['outside_own_code']) for r in pub['references'] if r['outside_own_code']]
        self.assertEqual(outside, [
            ('sources/owner.m', 38, ['through another object (parameter)']),
            ('sources/owner_cat.m', 5, ['from a category\'s file, not the file of the @implementation '
                                        '(sources/owner_cat.m)']),
            ('sources/owner_cat.m', 9, ['from a category\'s file, not the file of the @implementation '
                                        '(sources/owner_cat.m)', 'through another object (local)']),
            ('sources/peer.m', 10, ['from another translation unit (sources/peer.m)', 'from a method of class Peer',
                                   'through another object (parameter)'])])
        pkg = [(r['line'], r['outside_own_code']) for r in ivars['_pkg']['references'] if r['outside_own_code']]
        self.assertEqual(pkg, [(5, ['from a category\'s file, not the file of the @implementation '
                                    '(sources/owner_mrr.m)']),
                               (15, ['from another translation unit (sources/peer.m)', 'from a C function',
                                     'through another object (parameter)'])])
        byref = [(r['line'], r['access']) for r in ivars['_pkg']['references']]
        self.assertEqual(byref, [(36, 'rmw'), (37, 'byref'), (44, 'write'), (5, 'read'), (15, 'read')])

    def test_blocks_lambdas_and_locks(self):
        ivars = by_name(self.owner()['ivars'])
        self.assertEqual([(r['line'], r['in_block']) for r in ivars['_pub']['references'] if r['in_block']],
                         [(41, True)])
        self.assertEqual([(r['line'], r['synchronized_on']) for r in ivars['_pkg']['references']
                          if r['synchronized_on']], [(44, 'self')])
        status, text = self.ask('Cxx', as_json=True)
        cxx = by_name(json.loads(text)['ivars'])
        self.assertEqual([(r['line'], r['in_lambda']) for r in cxx['_plainInt']['references']],
                         [(14, 'self by copy')])
        self.assertEqual(cxx['_counter']['importable']['verdict'], 'no')

    def test_statics(self):
        statics = by_name(self.owner()['statics'])
        self.assertEqual(dict((n, s['kind']) for n, s in statics.items()),
                         {'gOwnerTotal': 'global', 'sHits': 'file-static', 'sShared': 'file-static',
                          'sLocal': 'local-static'})
        self.assertEqual(statics['sLocal']['enclosing'], '+[Owner shared]')
        self.assertEqual([(r['file'], r['line'], r['outside_own_code']) for r in statics['gOwnerTotal']['references']
                          if r['outside_own_code']],
                         [('sources/peer.m', 11, ['from another translation unit (sources/peer.m)',
                                                  'from a method of class Peer'])])
        self.assertEqual([(r['line'], r['synchronized_on']) for r in statics['sHits']['references']],
                         [(39, None), (45, 'self')])
        self.assertEqual(statics['sShared']['ownership'], 'strong')

    def test_the_class_s_own_mode_governs(self):
        # legacy.h is read by legacy.m (manual reference counting, the
        # class's @implementation) and by peer.m and legacy_arc.m (ARC, an
        # ARC category): the manual row governs, and the ARC one is listed as
        # a conflict.
        status, text = self.ask('Legacy', as_json=True)
        shared = by_name(json.loads(text)['ivars'])['_shared']
        self.assertEqual(shared['mode'], 'manual reference counting (the @implementation); ARC in '
                                         'sources/legacy_arc.m (category ARCCat)')
        self.assertEqual((shared['type'], shared['ownership']), ('id', 'manual'))
        self.assertEqual(shared['views_conflict'], [
            'ARC: __strong id, strong (recorded by sources/peer.m)',
            'manual reference counting: id, manual (recorded by sources/legacy.m)'])

    def test_type_private_to_the_implementation_file(self):
        status, text = self.ask('LegacyHolder', as_json=True)
        pair = by_name(json.loads(text)['ivars'])['_pair']
        self.assertEqual(pair['importable']['verdict'], 'yes')
        self.assertIn('the type is declared in the implementation file itself, so it is private to that file',
                      pair['importable']['reason'])

    def test_manual_reference_counting(self):
        status, text = self.ask('Legacy', as_json=True)
        self.assertEqual(status, 0)
        ivars = by_name(json.loads(text)['ivars'])
        self.assertTrue(ivars['_obj']['mode'].startswith('manual reference counting (the @implementation)'))
        self.assertEqual(ivars['_obj']['ownership'], 'manual')
        self.assertEqual(ivars['_box']['importable']['verdict'], 'unknown')
        self.assertIn('needs the type as an ARC unit records it', ivars['_box']['importable']['reason'])

    def test_table(self):
        status, text = self.ask('Owner')
        self.assertEqual(status, 0)
        lines = text.splitlines()
        self.assertEqual(lines[0], 'Class state of Owner: 26 ivars, 4 statics in its implementation files')
        self.assertEqual(lines[1], 'implemented in: sources/owner.m (ARC), sources/owner_cat.m (category Cat, ARC), '
                                   'sources/owner_mrr.m (category MRR, manual reference counting)')
        self.assertEqual(lines[2], 'importable: yes 18, degraded 8, no 3, unknown 1')
        self.assertIn('ivar _pub  int', lines)
        self.assertIn('    declared     header @interface, sources/owner.h:5:9, public', lines)
        self.assertIn('    importable   degraded: plain C enum: imported as a struct with a raw value, no exhaustive '
                      'switch (objc-state.md section 1; checked); visibility: not checked (the type and the classes, '
                      'protocols and typedefs it names must be visible to the bridging header)', lines)
        self.assertIn('      sources/peer.m:10:12  -[Peer reach:]  write  from another translation unit '
                      '(sources/peer.m)'
                      '  from a method of class Peer  through another object (parameter)', lines)
        self.assertIn('      -[Owner work:]  sources/owner.m: rmw 1 (lines 36); byref 1 (lines 37); write 1 (lines 44)',
                      lines)
        self.assertIn('      sources/owner.m:44:9  -[Owner work:]  write  under @synchronized (self)', lines)
        self.assertIn('file-static sHits  int', lines)

    def test_unknown_class(self):
        status, text = self.ask('Nobody')
        self.assertEqual(status, 1)
        self.assertTrue(text.startswith('Class state of Nobody: 0 ivars, 0 statics'))

    def test_old_schema_is_refused(self):
        db = os.path.join(os.path.dirname(self.root), 'old.sqlite')
        shutil.copy(self.paths.db, db)
        con = sqlite3.connect(db)
        con.execute('PRAGMA user_version=11')
        con.commit()
        con.close()
        err = io.StringIO()
        saved = sys.stderr
        sys.stderr = err
        try:
            status = codedb.main(['--root', self.root, '--db', db, '--cdb', self.paths.cdb, '--extractor',
                                  base.EXTRACTOR, 'classstate', 'Owner'])
        finally:
            sys.stderr = saved
        self.assertEqual(status, 2)
        self.assertIn('schema version 11, not 13', err.getvalue())


class ClassStateIncompleteTest(unittest.TestCase):
    def test_stale_unit(self):
        root, paths, _ = make_fixture_root()
        with open(os.path.join(root, S + 'owner_cat.m'), 'a') as f:
            f.write('// edited after the extraction\n')
        out = io.StringIO()
        status = classstate.classstate(codedb, paths, 'Owner', as_json=True, out=out)
        doc = json.loads(out.getvalue())
        self.assertEqual(status, 3)
        self.assertTrue(any(line.startswith('INCOMPLETE: 1 of 8 units are not current') for line in doc['incomplete']))
        cat = [r for r in by_name(doc['ivars'])['_pub']['references'] if r['file'] == S + 'owner_cat.m']
        self.assertEqual(cat[0]['marks'], ['STALE (input changed: sources/owner_cat.m)'])


SNAPSHOT_HEADER = ('# Objective-C runtime snapshot, format 2\narchitecture arm64\nbuild-configuration Development\n'
                   'build-variant ASan\n')
# A snapshot of Owner as the runtime would list it, with one difference of
# each kind: _ld's encoding (d, not D), _name missing, _ghost added,
# -setTotal: missing, -mystery added; and the expected ones: .cxx_destruct,
# a method from another image, a class defined in Swift.
OWNER_SNAPSHOT = SNAPSHOT_HEADER + '''class Owner
  language objc
  superclass Root
  image iTerm2.debug.dylib
  protocol Drawing
  ivar _atom types=Ai
  ivar _big types=t
  ivar _boxBlock types=@?
  ivar _buf types=[8c]
  ivar _callback types=^?
  ivar _count types=i
  ivar _drawer types=@"<Drawing>"
  ivar _flag types=b1
  ivar _flex types=^{?=i[0c]}
  ivar _ghost types=i
  ivar _ld types=d
  ivar _nice types=q
  ivar _number types=(?="i"i"f"f)
  ivar _opaque types=^{Opaque=}
  ivar _other types=@"Thing"
  ivar _pkg types=i
  ivar _plain types=i
  ivar _plainBlock types=@?
  ivar _pub types=i
  ivar _sel types=:
  ivar _strongBox types={?="obj"@"n"i}
  ivar _total types=i
  ivar _unretainedBox types={?="obj"@"n"i}
  ivar _varCallback types=^?
  ivar _vec types=
  ivar _weakThing types=@"Thing"
  class-method +shared types=@16@0:8
  instance-method -.cxx_destruct types=v16@0:8
  instance-method -count types=i16@0:8
  instance-method -description types=@16@0:8 image=Foundation
  instance-method -draw types=v16@0:8
  instance-method -flag types=i16@0:8
  instance-method -made types=i16@0:8
  instance-method -mystery types=v16@0:8
  instance-method -peek types=i16@0:8
  instance-method -name types=@16@0:8
  instance-method -poke types=v16@0:8
  instance-method -setCount: types=v20@0:8i16
  instance-method -total types=i16@0:8
  instance-method -viaLocal: types=v24@0:8@16
  instance-method -work: types=v24@0:8@16
  instance-property count type=i ownership=unrecorded nonatomic ivar=_count raw=Ti,N,V_count
end class Owner
class Swifty
  language swift
  superclass Root
  image iTerm2.debug.dylib
end class Swifty
'''


class VerifyInventoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths, _ = make_fixture_root()

    def ask(self, *classes, **kw):
        out = io.StringIO()
        paths = kw.pop('paths', self.paths)
        status = verify_inventory.verifyinventory(codedb, paths, classes=classes, out=out, **kw)
        return status, out.getvalue().splitlines()

    def copy_db(self):
        d = base.make_temp('codedb-classstate-db-')
        db = os.path.join(d, 'copy.sqlite')
        shutil.copy(self.paths.db, db)
        return db

    def paths_for(self, db):
        return codedb.Paths(self.root, db=db, cdb=self.paths.cdb, extractor=base.EXTRACTOR)

    def write(self, name, text):
        path = os.path.join(os.path.dirname(self.root), name)
        with open(path, 'w') as f:
            f.write(text)
        return path

    def test_inventory_against_the_database(self):
        status, lines = self.ask()
        self.assertEqual(status, 1, '\n'.join(lines))
        disagreements = [line for line in lines if line.startswith('  ') and ': ' in line and not line.startswith(
            '  unexplained')]
        self.assertEqual(disagreements[:7], [
            '  class inventory only: declared or implemented in sources/windows.m  [explained: not compiled]',
            '  property differs: level of Legacy in sources/legacy.h:8: attributes inventory (), database (nonatomic)',
            '  class inventory only: declared or implemented in sources/orphan.m  [explained: not parsed]',
            '  protocol inventory only: Orphan() lists Drawing in sources/orphan.m:5  [explained: not parsed]',
            '  method inventory only: -[Orphan lonely] in sources/orphan.m:8  [explained: not parsed]',
            '  method inventory only: -[Owner neverCompiled] in sources/owner.m:57  [explained: not compiled]',
            '  method database only: -[Owner made] in sources/owner.m:55 (macro MAKE_GETTER, argument)  [explained: '
            'made by a macro]'])
        # Legacy's NONATOMIC attribute, the database's side of Thing (Mood),
        # and WindowB's -special, skipped for WindowB in one inclusion of
        # window_impl.m and compiled for WindowA in the other (F4: not
        # excused).
        # Every branch of a chain whose #elif differs between inclusions is
        # partly compiled too, though its #if alone does not differ: -never
        # (skipped in both, still not excused), -alsoSpecial for WindowB and
        # -alsoOrdinary for WindowA.
        self.assertIn('  unexplained: 8', lines)
        for line in ('  method inventory only: -[WindowB special] in sources/window_impl.m:17',
                     '  method inventory only: -[WindowA ordinary] in sources/window_impl.m:20',
                     '  method inventory only: -[WindowA never] in sources/window_impl.m:24',
                     '  method inventory only: -[WindowB never] in sources/window_impl.m:24',
                     '  method inventory only: -[WindowB alsoSpecial] in sources/window_impl.m:27',
                     '  method inventory only: -[WindowA alsoOrdinary] in sources/window_impl.m:30'):
            self.assertIn(line, lines)
        self.assertEqual([line for line in lines if not line.startswith(' ') and line], [
            'Hidden', 'Legacy', 'Orphan', 'Owner', 'Thing', 'WindowA', 'WindowB',
            'Inventory against the database: 17 classes compared, 14 files parsed (the inventory\'s parser warned 1 '
            'times)'])

    def test_named_classes_only(self):
        status, lines = self.ask('Owner', 'Peer')
        self.assertEqual(status, 0, '\n'.join(lines))
        self.assertIn('Inventory against the database: 2 classes compared, 14 files parsed (the inventory\'s parser '
                      'warned 1 times)', lines)

    def test_class_named_by_a_macro_is_resolved(self):
        # window_impl.m declares THE_CLASS, which windows.m defines as
        # WindowA before including it: the database records the class under
        # WindowA at that place, so THE_CLASS is read as WindowA and its
        # members compared, with nothing to explain.
        # window_impl.m also declares THE_CLASS : Thing for editors, in code
        # no unit compiles; that superclass is not compared. -special is
        # compiled for WindowA (SPECIAL 1) and not for WindowB, -ordinary the
        # reverse: WindowA's line for -ordinary is the one disagreement, not
        # excused (the database cannot tell which inclusion skipped it).
        status, lines = self.ask('THE_CLASS', 'WindowA')
        self.assertEqual(status, 1, '\n'.join(lines))
        self.assertEqual(lines[1], '  method inventory only: -[WindowA alsoOrdinary] in sources/window_impl.m:30')
        self.assertEqual(lines[3], '  method inventory only: -[WindowA never] in sources/window_impl.m:24')
        self.assertEqual(lines[5], '  method inventory only: -[WindowA ordinary] in sources/window_impl.m:20')
        lines = lines[lines.index('') :]
        self.assertEqual(lines[:2], ['', 'Inventory against the database: 1 classes compared, 14 files parsed (the '
                                     'inventory\'s parser warned 1 times)'])

    def test_every_class_a_macro_resolves_to_is_compared(self):
        # F5 (m4): windows.m includes window_impl.m for WindowA and WindowB;
        # a member WindowB loses is found too.
        db = self.copy_db()
        con = sqlite3.connect(db)
        self.assertGreater(con.execute("DELETE FROM objc_method WHERE class_name = 'WindowB' AND selector = "
                                       "'wave'").rowcount, 0)
        con.commit()
        con.close()
        status, lines = self.ask('WindowA', 'WindowB', paths=self.paths_for(db))
        self.assertEqual(status, 1, '\n'.join(lines))
        self.assertIn('  method inventory only: -[WindowB wave] in sources/window_impl.m:13', lines)
        self.assertFalse([line for line in lines if '-[WindowA wave]' in line])

    def test_method_under_if_compiled_for_one_inclusion_is_lost(self):
        # F4 (the second reviewer's demonstration): -special is compiled for
        # WindowA and skipped for WindowB in the same unit, so a -special the
        # database lost is not explained as "not compiled".
        db = self.copy_db()
        con = sqlite3.connect(db)
        self.assertGreater(con.execute("DELETE FROM objc_method WHERE class_name = 'WindowA' AND selector = "
                                       "'special'").rowcount, 0)
        con.commit()
        con.close()
        status, lines = self.ask('WindowA', paths=self.paths_for(db))
        self.assertEqual(status, 1, '\n'.join(lines))
        self.assertIn('  method inventory only: -[WindowA special] in sources/window_impl.m:17', lines)
        self.assertIn('    note: not explained: the line is skipped in some inclusions of its file and compiled in '
                      'others, and the database does not record which inclusion defines this class', lines)

    def test_lost_else_method_is_not_excused(self):
        # Third review B4 (the reviewer's demonstration): -ordinary is in the
        # #else branch of #if SPECIAL, compiled for WindowB and skipped for
        # WindowA; the #else row's own value is not mixed, but its chain's is.
        db = self.copy_db()
        con = sqlite3.connect(db)
        self.assertGreater(con.execute("DELETE FROM objc_method WHERE class_name = 'WindowB' AND selector = "
                                       "'ordinary'").rowcount, 0)
        con.commit()
        con.close()
        status, lines = self.ask('WindowB', paths=self.paths_for(db))
        self.assertEqual(status, 1, '\n'.join(lines))
        hit = [line for line in lines if '-[WindowB ordinary]' in line]
        self.assertEqual(hit, ['  method inventory only: -[WindowB ordinary] in sources/window_impl.m:20'])

    def test_lost_member_of_a_resolved_class_is_unexplained(self):
        db = self.copy_db()
        con = sqlite3.connect(db)
        self.assertGreater(con.execute("DELETE FROM objc_method WHERE class_name = 'WindowA' AND selector = "
                                       "'wave'").rowcount, 0)
        con.commit()
        con.close()
        status, lines = self.ask('WindowA', paths=self.paths_for(db))
        self.assertEqual(status, 1)
        self.assertIn('  method inventory only: -[WindowA wave] in sources/window_impl.m:13', lines)

    def test_unrelated_class_in_a_file_with_a_macro_is_not_excused(self):
        # The reviewer's demonstration: a method the database lost, of a
        # class in a file that also names classes with macros (windows.m).
        db = self.copy_db()
        con = sqlite3.connect(db)
        self.assertGreater(con.execute("DELETE FROM objc_method WHERE class_name = 'Gadget' AND selector = "
                                       "'spin'").rowcount, 0)
        con.commit()
        con.close()
        status, lines = self.ask('Gadget', paths=self.paths_for(db))
        self.assertEqual(status, 1)
        self.assertIn('  method inventory only: -[Gadget spin] in sources/windows.m:33', lines)

    def test_unresolved_macro_is_explained_only_for_its_container(self):
        # Mood has two definitions, so Thing (Mood) cannot be resolved: the
        # inventory's side is explained, the database's (Thing(Root)) is not.
        status, lines = self.ask('Thing')
        self.assertEqual(status, 1, '\n'.join(lines))
        self.assertEqual(lines[:3], [
            'Thing',
            '  property inventory only: mood of Thing(Mood) in sources/windows.m:27  [explained: class named by a '
            'macro]',
            '  property database only: mood of Thing(Root) in sources/windows.m:27'])

    def test_category_named_by_a_macro_and_a_class_no_unit_compiles(self):
        # Flavor is defined once, as Thing, so Thing (Flavor) is read as
        # Thing (Thing), as the compiler reads it: flavor agrees.
        status, lines = self.ask('Hidden')
        self.assertEqual(status, 0, '\n'.join(lines))
        self.assertEqual(lines[:2], [
            'Hidden',
            '  class inventory only: declared or implemented in sources/windows.m  [explained: not compiled]'])
        status, lines = self.ask('Thing')
        self.assertFalse([line for line in lines if 'flavor' in line], '\n'.join(lines))

    def test_superclass_type_arguments_are_not_protocols(self):
        # generic.h: Box<Thing *> and Box<A> are type arguments of the
        # superclass; <Drawing> after them is a protocol list.
        status, lines = self.ask('Box', 'BoxOfThings', 'Pair', 'Drawn')
        self.assertEqual(status, 0, '\n'.join(lines))

    def test_protocols_and_ivars_agree(self):
        # The inventory's view of Owner's protocols, superclass and ivars
        # matches the compiler's: no line about them.
        status, lines = self.ask('Owner')
        self.assertFalse([line for line in lines if 'protocol' in line or 'ivar' in line or 'superclass' in line])

    def test_snapshot(self):
        snap = self.write('owner.snapshot', OWNER_SNAPSHOT)
        status, lines = self.ask(snapshot=snap, only_snapshot=True)
        self.assertEqual(status, 1, '\n'.join(lines))
        self.assertEqual(lines[:12], [
            'Owner',
            '  runtime ivar runtime only: _ghost types=i',
            '  runtime ivar database only: _name',
            '  runtime ivar encoding differs: _ld: runtime d, database D',
            '  runtime method runtime only: -[Owner .cxx_destruct] types=v16@0:8  [explained: synthesized by the '
            'compiler]',
            '  runtime method runtime only: -[Owner description] types=@16@0:8  [explained: implemented in another '
            'image (Foundation)]',
            '  runtime method runtime only: -[Owner mystery] types=v16@0:8',
            '  runtime method database only: -[Owner setTotal:]',
            'Swifty',
            '  runtime not compared: the snapshot says the class is defined in swift  [explained: not an Objective-C '
            'class]',
            '',
            'Runtime snapshot against the database: 2 classes (architecture arm64, build-configuration Development, '
            'build-variant ASan)'])
        self.assertIn('  unexplained: 5', lines)

    def test_snapshot_in_format_3(self):
        # runtime_snapshot.sh writes format 3 (ivar ownership, the ivar
        # layouts and the ARC flag); verifyinventory refused it, so no
        # snapshot the tool writes today could be compared.
        import re
        text = OWNER_SNAPSHOT.replace('format 2', 'format 3')
        text = re.sub(r'^(  ivar \S+ types=\S*)$', r'\1 ownership=scalar layout=', text, flags=re.M)
        text = text.replace('  image iTerm2.debug.dylib\n  protocol Drawing\n',
                            '  image iTerm2.debug.dylib\n  ivar-arc-flag set\n  strong-ivar-layout 0200\n'
                            '  weak-ivar-layout\n  protocol Drawing\n')
        self.assertIn('ownership=scalar layout=\n', text)
        status, lines = self.ask(snapshot=self.write('owner3.snapshot', text), only_snapshot=True)
        _, want = self.ask(snapshot=self.write('owner2b.snapshot', OWNER_SNAPSHOT), only_snapshot=True)
        self.assertEqual(status, 1, '\n'.join(lines))
        self.assertEqual(lines, want)

    def test_snapshot_method_defined_in_swift(self):
        # A method the Swift tables say a Swift extension of the class
        # defines is explained. The fixtures have no Swift capture, so a copy
        # of the database gets the one row it needs.
        d = os.path.dirname(self.root)
        db = os.path.join(d, 'swift.sqlite')
        shutil.copy(self.paths.db, db)
        con = sqlite3.connect(db)
        con.execute('CREATE TABLE IF NOT EXISTS swift_objc_decl(class_name TEXT, is_class_member INTEGER, '
                    'selector TEXT)')
        con.execute("INSERT INTO swift_objc_decl(class_name, is_class_member, selector) VALUES ('Owner', 0, "
                    "'mystery')")
        con.commit()
        con.close()
        paths = codedb.Paths(self.root, db=db, cdb=self.paths.cdb, extractor=base.EXTRACTOR)
        out = io.StringIO()
        status = verify_inventory.verifyinventory(codedb, paths, classes=('Owner',), out=out,
                                                  snapshot=self.write('swift.snapshot', OWNER_SNAPSHOT),
                                                  only_snapshot=True)
        self.assertEqual(status, 1)
        self.assertIn('  runtime method runtime only: -[Owner mystery] types=v16@0:8  [explained: defined in Swift]',
                      out.getvalue().splitlines())

    def test_snapshot_with_named_class(self):
        snap = self.write('owner2.snapshot', OWNER_SNAPSHOT)
        status, lines = self.ask('Swifty', snapshot=snap, only_snapshot=True)
        self.assertEqual(status, 0, '\n'.join(lines))

    def test_snapshot_class_not_in_database(self):
        snap = self.write('nobody.snapshot', SNAPSHOT_HEADER + 'class Nobody\n  language objc\n  superclass Root\n'
                                                               'end class Nobody\n')
        status, lines = self.ask(snapshot=snap, only_snapshot=True)
        self.assertEqual(status, 1)
        self.assertIn('  runtime class not in database: no objc_class, objc_ivar or objc_method row', lines)

    def test_bad_snapshots_are_errors(self):
        for name, text in (('format1.snapshot', '# Objective-C runtime snapshot, format 1\nclass Owner\n'),
                           ('garbage.snapshot', SNAPSHOT_HEADER + 'what is this\n'),
                           ('unended.snapshot', SNAPSHOT_HEADER + 'class Owner\n  language objc\n')):
            snap = self.write(name, text)
            err = io.StringIO()
            saved = sys.stderr
            sys.stderr = err
            try:
                status = codedb.main(['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb,
                                      '--extractor', base.EXTRACTOR, 'verifyinventory', '--snapshot', snap,
                                      '--only-snapshot'])
            finally:
                sys.stderr = saved
            self.assertEqual(status, 2, name)
            self.assertIn('cannot read the snapshot', err.getvalue(), name)

    def test_unescape(self):
        self.assertEqual(verify_inventory.unescape('a%20b%25c'), 'a b%c')
        self.assertEqual(verify_inventory.unescape('plain'), 'plain')


if __name__ == '__main__':
    unittest.main()


# A runtime snapshot of Owner in format 3: _weakThing and _other agree with
# the compiler, _count (an int) is labelled strong, which contradicts it,
# _sel is a scalar the runtime calls a selector, _strongBox a struct the
# runtime cannot tell from a C++ object, and _phantom exists only at run
# time.
OWNER_SNAPSHOT_3 = '''# Objective-C runtime snapshot, format 3
architecture arm64
build-configuration Development
build-variant ASan
class Owner
  language objc
  superclass Root
  image iTerm2.debug.dylib
  ivar-arc-flag set
  strong-ivar-layout 0200
  weak-ivar-layout
  ivar _count types=i ownership=strong layout=s
  ivar _other types=@"Thing" ownership=strong layout=s
  ivar _phantom types=i ownership=scalar layout=
  ivar _sel types=: ownership=selector layout=
  ivar _strongBox types={?="obj"@"n"i} ownership=struct-or-cxx-object layout=
  ivar _weakThing types=@"Thing" ownership=weak layout=w
end class Owner
class Swifty
  language swift
  superclass Root
  image iTerm2.debug.dylib
  ivar value types= ownership=swift layout=
end class Swifty
'''


class StubTable:
    """An ImportTable with fixed answers, for refine_visibility alone."""

    def __init__(self, answers, module='App', module_ok=True, note=''):
        self.answers, self.module, self.module_ok, self.note = answers, module, module_ok, note

    def is_repository(self, kind, name):
        return (kind, name) in self.answers

    def judge_class(self, name):
        return self.answers[('class', name)]

    def judge_protocol(self, name):
        return self.answers[('protocol', name)]

    def judge_record(self, name):
        return self.answers[('record', name)]


U_MISSING = ('not-imported', 'class U is declared in the repository and absent from the import table of App')
P_MISSING = ('not-imported', 'protocol P is declared in the repository and absent from the import table of App')
SEEN = ('visible', 'class NSArray is an SDK class, imported as its framework module')


class NestedVisibilityTest(unittest.TestCase):
    """Review round 1, B1: a class or protocol Swift does not import, inside
    a block, type arguments, a C array or a pointee. The verdict for each
    position is what swiftc did with a property (or, for a C array, a
    global) of that type whose class is only forward-declared to the
    bridging header (tmp/p0state/probe in the unit's lane, 2026-11-21)."""

    def table(self):
        answers = {('class', 'U'): U_MISSING, ('protocol', 'P'): P_MISSING}
        for c in ('NSArray', 'NSDictionary', 'NSMutableArray', 'NSCache', 'NSPointerArray', 'NSString', 'Gen'):
            answers[('class', c)] = ('visible', 'class %s is visible' % c)
        return StubTable(answers)

    def refine(self, type_class, facts, typ, object_class=None, protocols=None):
        row = {'type_class': type_class, 'import_facts': facts, 'type': typ, 'object_class': object_class,
               'object_protocols': protocols}
        return classstate.refine_visibility(self.table(), row, *classstate.importability(type_class, facts))

    def test_block_parameter_and_result(self):
        # iTermBackgroundCommandRunnerPromise._terminationBlock.
        v, why = self.refine('block', '', 'void (^__strong)(U *, int)')
        self.assertEqual(v, 'no', why)
        self.assertIn('class U', why)
        self.assertEqual(self.refine('block', '', 'U *(^__strong)(void)')[0], 'no')
        self.assertEqual(self.refine('block', '', 'void (^__strong)(id<P>)')[0], 'no')

    def test_bridged_collection_and_repository_generic(self):
        # iTermToolActions._actions.
        v, why = self.refine('object', 'generic-bridged type-args', 'NSArray<U *> *__strong', 'NSArray')
        self.assertEqual(v, 'no', why)
        self.assertEqual(self.refine('object', 'generic-bridged type-args', 'NSDictionary<NSString *,U *> *',
                                     'NSDictionary')[0], 'no')
        self.assertEqual(self.refine('object', 'generic-bridged type-args', 'NSArray<id<P>> *', 'NSArray')[0], 'no')
        self.assertEqual(self.refine('object', 'generic-repository type-args', 'Gen<U *> *', 'Gen')[0], 'no')

    def test_sdk_generics_by_their_api_notes(self):
        v, why = self.refine('object', 'generic-sdk type-args', 'NSMutableArray<U *> *__strong', 'NSMutableArray')
        self.assertEqual(v, 'degraded', why)
        self.assertIn('erased', why)
        self.assertEqual(self.refine('object', 'generic-sdk type-args', 'NSCache<NSString *,U *> *', 'NSCache')[0],
                         'no')
        v, why = self.refine('object', 'generic-sdk type-args', 'NSPointerArray<U *> *', 'NSPointerArray')
        self.assertEqual(v, 'unknown', why)
        self.assertIn('visibility: not checked for the parts of this type', why)

    def test_array_pointee_and_function_pointer(self):
        # iTermASCIITextureGroup._textures.
        self.assertEqual(self.refine('array', '', 'U *__strong[8]')[0], 'no')
        v, why = self.refine('c-pointer', 'object-pointee', 'U *__autoreleasing *')
        self.assertEqual(v, 'degraded', why)
        self.assertIn('OpaquePointer', why)
        self.assertEqual(self.refine('c-pointer', 'function-pointer', 'void (*)(U *)')[0], 'degraded')

    def test_deeper_nesting_is_not_claimed(self):
        v, why = self.refine('object', 'generic-bridged in-generic-bridged in-type-args type-args',
                             'NSArray<NSArray<U *> *> *', 'NSArray')
        self.assertEqual(v, 'unknown', why)
        self.assertIn('visibility: not checked for the parts of this type', why)

    def test_nothing_unimported_inside(self):
        v, why = self.refine('object', 'generic-bridged type-args', 'NSArray<NSString *> *', 'NSArray')
        self.assertEqual(v, 'yes', why)
        self.assertNotIn('names no class, protocol or record', why)

    def test_names_by_their_place_in_the_type(self):
        # A protocol and a class of one name (iTermPromiseSeal), a record's
        # path note, and a struct tag are not read as classes.
        self.assertEqual(classstate.type_names('__strong id<S>'), [('protocol', 'S')])
        self.assertEqual(classstate.type_names('NSArray<id<P>> *'), [('protocol', 'P'), ('class', 'NSArray')])
        self.assertEqual(classstate.type_names('void (^)(U * _Nonnull __strong, int)'), [('class', 'U')])
        self.assertEqual(classstate.type_names('struct (unnamed at /x/Owner.m:3:8)[5]'), [])
        self.assertEqual(classstate.type_names('struct Owner *'), [])
        v, why = self.refine('object', '', '__strong id<P>', 'id', 'P')
        self.assertEqual(v, 'no', why)
        self.assertNotIn('class P', why)

    def test_framework_protocol_at_the_top_is_unknown(self):
        table = StubTable({('protocol', 'CPKDelegate'): ('unknown', 'protocol CPKDelegate is declared in the '
                                                         'framework target ColorPicker:ColorPicker')})
        row = {'type_class': 'object', 'import_facts': '', 'type': 'id<CPKDelegate>', 'object_class': 'id',
               'object_protocols': 'CPKDelegate'}
        v, why = classstate.refine_visibility(table, row, *classstate.importability('object', ''))
        self.assertEqual(v, 'unknown', why)
        self.assertIn('ColorPicker:ColorPicker', why)

    def test_framework_protocol_is_not_judged_by_the_bridging_header(self):
        # N1: CPKColorWellViewDelegate is declared only by the ColorPicker
        # framework target.
        con = sqlite3.connect(':memory:')
        con.executescript("""
            CREATE TABLE tu(id INTEGER PRIMARY KEY, target TEXT);
            CREATE TABLE objc_method(container_kind TEXT, container_name TEXT, tu INTEGER);
            CREATE TABLE objc_adoption(container_kind TEXT, class_or_category TEXT, tu INTEGER);
            CREATE TABLE swift_import(module TEXT, usr TEXT);
            INSERT INTO tu VALUES (1, 'ColorPicker:ColorPicker'), (2, 'iTerm2SharedARC');
            INSERT INTO objc_method VALUES ('protocol', 'CPKDelegate', 1), ('protocol', 'AppProto', 2);
        """)
        table = classstate.ImportTable.__new__(classstate.ImportTable)
        table.con, table.module, table.cache, table.sdk_protocols = con, 'App', {}, set()
        table.swift_classes = {'SwiftProto'}
        # A protocol declared in Swift (FontProviderProtocol) has members in
        # the Swift tables and is seen by Swift as it is.
        self.assertEqual(table.judge_protocol('SwiftProto'), ('visible', 'protocol SwiftProto is declared in Swift'))
        state, text = table.judge_protocol('CPKDelegate')
        self.assertEqual(state, 'unknown', text)
        self.assertIn('ColorPicker:ColorPicker', text)
        self.assertEqual(table.judge_protocol('AppProto')[0], 'not-imported')


class StaticWrittenTest(unittest.TestCase):
    """Review round 1, B2 and N2."""

    def test_cxx_object(self):
        # iTermLegacyAtomicMutableArrayOfWeakObjectsLockCount += 1 is
        # recorded as a read.
        row = {'type': 'std::atomic<int>', 'type_class': 'cxx-object', 'import_facts': 'cxx-record cxx-template',
               'is_const': False}
        refs = [{'access': 'read', 'in_constant_false_branch': False, 'in_once_block': False, 'function': 'f'}]
        self.assertEqual(classstate.static_written(codedb, refs, row),
                         'not decided: C++ object; operator and member calls are recorded as reads')

    def test_once_token(self):
        row = {'type': 'dispatch_once_t', 'type_class': 'scalar', 'import_facts': '', 'is_const': False}
        refs = [{'access': 'once-token', 'in_constant_false_branch': False, 'in_once_block': False, 'function': 'f'}]
        self.assertTrue(classstate.static_written(codedb, refs, row).startswith('once token'))


class ClassStateAdditionsTest(unittest.TestCase):
    """The import table's verdict on visibility, the runtime snapshot's
    ownership, how a static is written, statics used but defined elsewhere,
    and --all."""

    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths, _ = make_fixture_root()

    def ask(self, cls, paths=None, **kw):
        out = io.StringIO()
        status = classstate.classstate(codedb, paths or self.paths, cls, as_json=True, out=out, **kw)
        return status, json.loads(out.getvalue())

    def with_import_table(self, usrs):
        """A copy of the database whose import table, for one module, holds
        these USRs."""
        d = base.make_temp('codedb-classstate-imports-')
        db = os.path.join(d, 'copy.sqlite')
        shutil.copy(self.paths.db, db)
        con = sqlite3.connect(db)
        sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
        import swift_interface
        swift_interface.ensure_import_schema(con)
        con.execute("INSERT INTO swift_import_unit(module, compiler, created_at, incomplete) VALUES ('App', 'swiftc', "
                    "'2026-11-21T00:00:00Z', '')")
        for usr in usrs:
            name, _, _ = swift_interface.objc_name_of(usr)
            con.execute("INSERT INTO swift_import(module, usr, objc_name, swift_name, kind, access, declaration, "
                        "throws, async, refined, availability) VALUES ('App', ?, ?, ?, 'class', 'open', '', 0, 0, 0, "
                        "'')", (usr, name, name))
        con.commit()
        con.close()
        return codedb.Paths(self.root, db=db, cdb=self.paths.cdb, extractor=base.EXTRACTOR)

    def test_visibility_from_the_import_table(self):
        # Thing is imported; the protocol Drawing is not, so id<Drawing> is
        # dropped by Swift whatever its type facts say.
        status, doc = self.ask('Owner', paths=self.with_import_table(['c:objc(cs)Thing']))
        self.assertEqual(status, 0)
        ivars = by_name(doc['ivars'])
        other = ivars['_other']['importable']
        self.assertEqual(other['verdict'], 'yes')
        # The fixtures have no Swift capture, so the rows' staleness cannot be
        # checked, and the reason says so.
        self.assertEqual(other['reason'], 'object; visibility (import table of App, whose rows could not be checked '
                                          'for staleness): class Thing is imported through the bridging header')
        drawer = ivars['_drawer']['importable']
        self.assertEqual(drawer['verdict'], 'no')
        self.assertTrue(drawer['reason'].startswith('protocol Drawing is declared in the repository and absent from '
                                                    'the import table of App: Swift drops a member of this type'),
                        drawer['reason'])
        # A scalar names nothing.
        self.assertEqual(ivars['_pub']['importable']['reason'], 'C scalar; visibility (import table of App, whose rows '
                                                                'could not be checked for staleness): the type names '
                                                                'no class or protocol of the repository (classes and '
                                                                'protocols are looked for anywhere in the type; '
                                                                'records, typedefs and enums inside it are not '
                                                                'judged)')

    def test_visibility_with_the_class_not_imported(self):
        status, doc = self.ask('Owner', paths=self.with_import_table(['c:objc(pl)Drawing']))
        ivars = by_name(doc['ivars'])
        self.assertEqual(ivars['_other']['importable']['verdict'], 'no')
        self.assertIn('class Thing is declared in the repository and absent from the import table of App',
                      ivars['_other']['importable']['reason'])
        self.assertEqual(ivars['_drawer']['importable']['verdict'], 'yes')

    def test_refine_visibility_rules(self):
        forward = classstate.importability('object', 'forward-declared-class')
        self.assertEqual(forward[0], 'unknown')
        row = {'type_class': 'object', 'object_class': 'Fwd', 'import_facts': 'forward-declared-class'}
        seen = StubTable({('class', 'Fwd'): ('visible', 'class Fwd is imported through the bridging header')})
        self.assertEqual(classstate.refine_visibility(seen, row, *forward),
                         ('yes', 'the class or protocol is only forward-declared in this unit, but Swift sees it: '
                                 'visibility (import table of App): class Fwd is imported through the bridging header'))
        unseen = StubTable({('class', 'Fwd'): ('not-imported', 'class Fwd is absent')})
        self.assertEqual(classstate.refine_visibility(unseen, row, *forward)[0], 'no')
        stale = StubTable({}, module_ok=False, note='visibility: not decided (stale)')
        self.assertEqual(classstate.refine_visibility(stale, {'type_class': 'scalar'}, *classstate.importability(
            'scalar', '')), ('yes', 'C scalar; visibility: not decided (stale)'))
        record = {'type_class': 'struct', 'record_name': 'CGRect', 'import_facts': ''}
        unknown = StubTable({('record', 'CGRect'): ('unknown', 'record CGRect is absent from the import table')})
        self.assertEqual(classstate.refine_visibility(unknown, record, *classstate.importability('struct', '')),
                         ('yes', 'C struct; visibility (import table of App): record CGRect is absent from the import '
                                 'table'))
        # A lock note after the visibility clause stays.
        lock = classstate.importability('struct', 'lock-type')
        self.assertTrue(classstate.refine_visibility(unknown, record, *lock)[1].endswith(classstate.LOCK_NOTE))

    def test_runtime_ownership(self):
        snap = os.path.join(os.path.dirname(self.root), 'owner3.snapshot')
        with open(snap, 'w') as f:
            f.write(OWNER_SNAPSHOT_3)
        status, doc = self.ask('Owner', snapshot=snap)
        ivars = by_name(doc['ivars'])
        self.assertEqual(ivars['_weakThing']['runtime']['verdict'], 'agrees')
        self.assertEqual(ivars['_other']['runtime']['verdict'], 'agrees')
        self.assertEqual(ivars['_count']['runtime']['verdict'], 'DISAGREES')
        self.assertEqual(ivars['_strongBox']['runtime']['verdict'], 'compiler')
        self.assertEqual(ivars['_pub']['runtime'], {'verdict': 'not in the snapshot', 'text': 'the snapshot lists no '
                         'ivar _pub (a conditional ivar, or a snapshot older than the database)'})
        self.assertEqual(doc['runtime'], [{'disagrees': False, 'text': 'ivar _phantom is in the snapshot (scalar) and '
                                                                       'not in the database'}])
        self.assertEqual(doc['ownership_disagreements'], 1)
        out = io.StringIO()
        classstate.classstate(codedb, self.paths, 'Owner', out=out, snapshot=snap)
        lines = out.getvalue().splitlines()
        self.assertIn('ownership against the runtime snapshot %s: 1 disagreement' % snap, lines)
        self.assertIn('    runtime      strong layout=s [strong (runtime layout)]: OWNERSHIP DISAGREES; compiler: int '
                      '(scalar, ARC)', lines)
        # Without a snapshot no row has a runtime answer, and the text says so.
        status, doc = self.ask('Owner')
        self.assertFalse([r for r in doc['ivars'] if r['runtime'] is not None])
        out = io.StringIO()
        classstate.classstate(codedb, self.paths, 'Owner', out=out)
        self.assertIn('ownership against the runtime: not cross-checked (give --snapshot)', out.getvalue().splitlines())

    def test_a_snapshot_without_ownership_is_refused(self):
        snap = os.path.join(os.path.dirname(self.root), 'format2.snapshot')
        with open(snap, 'w') as f:
            f.write(SNAPSHOT_HEADER + 'class Owner\n  language objc\nend class Owner\n')
        with self.assertRaises(codedb.CodeDBError):
            classstate.classstate(codedb, self.paths, 'Owner', out=io.StringIO(), snapshot=snap)

    def test_static_written_after_initialization(self):
        status, doc = self.ask('Owner')
        statics = by_name(doc['statics'])
        self.assertEqual(statics['sHits']['written'], 'after initialization (counting address-of and by-reference '
                                                      'uses), from 1 function: -[Owner work:]')
        self.assertEqual(statics['sShared']['written'], 'no write, address-of or by-reference use recorded after its '
                                                        'initialization')
        self.assertEqual(statics['gOwnerTotal']['written'], 'after initialization (counting address-of and '
                                                            'by-reference uses), from 2 functions: -[Owner work:], '
                                                            '-[Peer reach:]')
        refs = [{'access': 'write', 'in_constant_false_branch': False, 'in_once_block': True, 'function': 'f'}]
        self.assertEqual(classstate.static_written(codedb, refs), 'only in a dispatch_once block (every write, '
                                                                  'address-of or by-reference use recorded)')
        refs[0]['in_constant_false_branch'] = True
        self.assertTrue(classstate.static_written(codedb, refs).startswith('no write'))

    def test_statics_used_but_defined_elsewhere(self):
        # peer.m defines no static but writes Owner's global gOwnerTotal.
        status, doc = self.ask('Peer')
        used = doc['used_elsewhere']
        self.assertEqual([(u['kind'], u['name'], u['type'], u['declared']) for u in used],
                         [('global', 'gOwnerTotal', 'int', {'kind': 'global', 'file': 'sources/owner.m', 'line': 4})])
        self.assertEqual([(r['function'], r['access'], r['line']) for r in used[0]['references']],
                         [('-[Peer reach:]', 'rmw', 11)])
        self.assertTrue(used[0]['written_anywhere'].startswith('after initialization'))
        status, doc = self.ask('Owner')
        self.assertEqual(doc['used_elsewhere'], [])

    def test_all(self):
        out = io.StringIO()
        status = classstate.classstate_all(codedb, self.paths, as_json=True, out=out)
        self.assertEqual(status, 0)
        docs = [json.loads(line) for line in out.getvalue().splitlines()]
        classes = [d['class'] for d in docs[:-1]]
        want = sorted(set(r[0] for r in rows(self.paths.db, 'SELECT class_name FROM objc_impl WHERE category IS NULL '
                                                            'AND in_migration_scope = 1')))
        self.assertEqual(classes, want)
        self.assertIn('Owner', classes)
        owner = docs[classes.index('Owner')]
        _, single = self.ask('Owner')
        self.assertEqual(owner['ivars'], single['ivars'])
        summary = docs[-1]['summary']
        self.assertEqual(summary['classes'], len(want))
        self.assertEqual(summary['ivars'], sum(len(d['ivars']) for d in docs[:-1]))
        self.assertIn('not made by --all', summary['not_made'])
        out = io.StringIO()
        classstate.classstate_all(codedb, self.paths, out=out)
        text = out.getvalue().splitlines()
        self.assertEqual(text[0], 'Class state of every class with an @implementation in the migration\'s scope: %d '
                                  'classes' % len(want))
        self.assertIn('Class state of Owner: 26 ivars, 4 statics in its implementation files', text)
        # N3: every class's header repeats that the text searches were not made.
        owner = text.index('Class state of Owner: 26 ivars, 4 statics in its implementation files')
        self.assertIn('not made: ' + classstate.ALL_NOT_SEARCHED, text[owner:owner + 6])
        self.assertIn('%d classes, %d ivars, %d statics defined in their files (%d distinct: a file with several '
                      'classes lists its statics under each), %d uses of statics defined elsewhere' %
                      (len(want), summary['ivars'], summary['statics'], summary['distinct_statics'],
                       summary['used_elsewhere']), text)

    def test_all_leaves_out_generated_code(self):
        # The whole-tree run listed some 500 protobuf statics under each of
        # the 170 classes of Api.pbobjc.m, which README.md section 2 puts out
        # of scope.
        con = sqlite3.connect(':memory:')
        con.execute('CREATE TABLE objc_impl(class_name TEXT, category TEXT, file TEXT, in_migration_scope INTEGER)')
        con.executemany('INSERT INTO objc_impl VALUES (?, ?, ?, 1)', [
            ('ITMRequest', None, 'sources/proto/Api.pbobjc.m'), ('Mine', None, 'sources/Mine.m'),
            ('Mine', 'Cat', 'sources/proto/Api.pbobjc.m')])
        self.assertEqual(classstate.all_classes(con), (['Mine'], collections.Counter({'generated (protobuf)': 1})))

    def test_command_line(self):
        err = io.StringIO()
        saved = sys.stderr
        sys.stderr = err
        try:
            common = ['--root', self.root, '--db', self.paths.db, '--cdb', self.paths.cdb, '--extractor',
                      base.EXTRACTOR, 'classstate']
            self.assertEqual(codedb.main(common), 2)
            self.assertEqual(codedb.main(common + ['--all', 'Owner']), 2)
        finally:
            sys.stderr = saved
        self.assertIn('a CLASS or --all', err.getvalue())
