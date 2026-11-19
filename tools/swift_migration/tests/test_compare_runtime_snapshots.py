"""Tests for tools/swift_migration/compare_runtime_snapshots.sh comparing a
class before and after it moves from Objective-C to Swift, by the rule
"identical in meaning" (docs/swift-migration/phase0.md section 9).

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_compare_runtime_snapshots.py'

The pairs in fixtures/runtime_snapshot_compare/ are real snapshots that
tools/swift_migration/runtime_snapshot.sh took of the fixture classes in
ModernTests/RuntimeSnapshotFixtures/RuntimeSnapshotPortFixtures.*, made by
make_runtime_snapshot_compare_fixtures.sh (which says how the Swift class's
section is renamed). The first run compiles the comparison tool into tmp/,
which takes several seconds.
"""

import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
TOOL = os.path.join(ROOT, 'tools', 'swift_migration', 'compare_runtime_snapshots.sh')
PAIRS = os.path.join(HERE, 'fixtures', 'runtime_snapshot_compare')
CLASS = 'class RuntimeSnapshotPortObjCFixture: '
ATOMIC_CLASS = 'class RuntimeSnapshotPortAtomicObjCFixture: '


def compare(pair, before=None, after=None):
    result = subprocess.run([TOOL, before or os.path.join(PAIRS, pair, 'before.txt'),
                             after or os.path.join(PAIRS, pair, 'after.txt')],
                            capture_output=True, text=True, timeout=600)
    return result.returncode, result.stdout, result.stderr


def section(report, title):
    """The indented lines under a report heading that starts with title."""
    lines = report.split('\n')
    for i, line in enumerate(lines):
        if line.startswith(title):
            body = []
            for following in lines[i + 1:]:
                if not following.startswith('  '):
                    break
                body.append(following)
            return '\n'.join(body)
    return ''


class FaithfulPortTest(unittest.TestCase):
    """The stage-one port passes, with every systematic difference
    classified and what the runtime cannot judge listed as a check."""

    @classmethod
    def setUpClass(cls):
        cls.status, cls.report, cls.error = compare('faithful')

    def test_passes(self):
        self.assertEqual(self.status, 0, self.report + self.error)
        self.assertIn('PASS: the snapshots match, and the classes that moved to Swift are identical in meaning apart '
                      'from the expected differences, with 14 items to check against the source', self.report)
        self.assertNotIn('DIFFERENCES:', self.report)
        self.assertNotIn('NO VERDICT', self.report)

    def test_vanished_ivars_are_checks(self):
        checks = section(self.report, 'CHECK AGAINST THE SOURCE')
        for ivar in ['_copiedString', '_count', '_enabled', '_frame', '_handler', '_privateCounter',
                     '_readonlyString', '_strongObject', '_visible', '_weakObject']:
            self.assertIn(CLASS + 'Objective-C ivar %s (' % ivar, checks)
        self.assertIn('key-value coding falling back to the ivar (accessInstanceVariablesDirectly)', checks)
        self.assertIn('obj->_privateCounter', checks)

    def test_initializers_and_dynamic_dispatch_are_checks(self):
        checks = section(self.report, 'CHECK AGAINST THE SOURCE')
        self.assertIn(CLASS + 'initializer instance-method -init is in the Swift class', checks)
        self.assertIn(CLASS + 'initializer instance-method -initWithCount: is in the Swift class', checks)
        self.assertIn(CLASS + 'Swift callers bypass key-value observing and swizzling for members not marked dynamic', checks)

    def test_weak_versus_unowned_is_a_check(self):
        checks = section(self.report, 'CHECK AGAINST THE SOURCE')
        self.assertIn(CLASS + 'changed instance-property weakObject\n', checks)
        self.assertIn("check: weak became weak-or-unowned: the runtime cannot tell Swift's weak from unowned", checks)

    def test_classified_differences(self):
        expected = section(self.report, 'Expected differences of a move to Swift')
        for text in [
            'changed instance-method -copyWithZone: types from @24@0:8^{_NSZone=}16 to @24@0:8^v16',
            'removed instance-property debugDescription',
            'removed instance-property description',
            'removed instance-property hash',
            'removed instance-property superclass',
            'changed strong-ivar-layout from 21111200 to (no value)',
            'changed weak-ivar-layout from 3100 to (no value)',
            'Swift storage privateCounter (types= ownership=swift layout=)',
            'Swift storage visibleStorage (types= ownership=swift layout=)',
        ]:
            self.assertIn(CLASS + text, expected)
        self.assertIn('getter=isVisible is not written: Swift writes no G or S code for a custom accessor name, and '
                      'the method isVisible is there', expected)
        self.assertIn('backing ivar _count became count', expected)
        self.assertIn('Swift writes the attribute codes in another order', expected)

    def test_bool_and_bridged_types_have_the_same_encoding(self):
        # -isReady returns BOOL in Objective-C and Bool in Swift; the
        # describeWithPrefix:count: arguments are NSString * in both. On this
        # architecture (arm64) both encode alike, so neither is reported.
        self.assertNotIn('-isReady', self.report)
        self.assertNotIn('-describeWithPrefix:count:', self.report)
        self.assertNotIn('-takeBlock:', self.report)
        self.assertNotIn('-rectByInsetting:', self.report)
        self.assertNotIn('-categoryMethod', self.report)


class AtomicPortTest(unittest.TestCase):
    """The port of a class with atomic properties, each stored in a
    MutableAtomicObject with an @objc computed property over its value
    (docs/swift-migration/concurrency.md section 3), passes. Each property's
    loss of atomicity is a check, because the runtime cannot see the
    MutableAtomicObject."""

    PROPERTIES = ['atomicCount', 'atomicObject', 'atomicRect']

    @classmethod
    def setUpClass(cls):
        cls.status, cls.report, cls.error = compare('atomic')

    def test_passes(self):
        self.assertEqual(self.status, 0, self.report + self.error)
        # One per atomic property, one per vanished Objective-C ivar, the
        # -init Swift lists, and the class-level check about dynamic.
        self.assertIn('PASS: the snapshots match, and the classes that moved to Swift are identical in meaning apart '
                      'from the expected differences, with 8 items to check against the source', self.report)
        self.assertNotIn('DIFFERENCES:', self.report)

    def test_each_atomic_property_is_a_check(self):
        checks = section(self.report, 'CHECK AGAINST THE SOURCE')
        for name in self.PROPERTIES:
            self.assertIn(ATOMIC_CLASS + 'changed instance-property %s\n' % name, checks)
            self.assertIn('check: property %s was atomic: Swift properties are not; check that the port stores it in a '
                          'MutableAtomicObject and reads and writes it through its value (concurrency.md section 3), '
                          'or that the dossier shows it was atomic by accident' % name, checks)
            self.assertIn(ATOMIC_CLASS + 'Objective-C ivar _%s (' % name, checks)
        self.assertEqual(checks.count('was atomic: Swift properties are not'), 3, checks)

    def test_storage_and_backing_ivars_are_classified(self):
        expected = section(self.report, 'Expected differences of a move to Swift')
        for name in self.PROPERTIES:
            self.assertIn(ATOMIC_CLASS + 'Swift storage %sStorage (' % name, expected)
            self.assertIn('backing ivar _%s became (none)' % name, expected)
        self.assertEqual(expected.count('it gains N, for nonatomic, which is listed as a check'), 3, expected)
        self.assertIn(ATOMIC_CLASS + 'changed strong-ivar-layout from 0100 to (no value)', expected)

    def test_accessor_encodings_are_unchanged(self):
        for selector in ['-atomicObject', '-setAtomicObject:', '-atomicRect', '-setAtomicRect:',
                         '-atomicCount', '-setAtomicCount:']:
            self.assertNotIn('instance-method %s ' % selector, self.report)


    def test_same_language_atomic_change_still_fails(self):
        # Between two Objective-C snapshots, atomic becoming nonatomic is a
        # failure and never a check: the check is only for a port to Swift.
        before = os.path.join(PAIRS, 'atomic', 'before.txt')
        with open(before) as f:
            text = f.read()
        changed = text.replace('ownership=strong atomic ivar=_atomicObject raw=T@"NSObject",&,V_atomicObject',
                               'ownership=strong nonatomic ivar=_atomicObject raw=T@"NSObject",&,N,V_atomicObject')
        self.assertNotEqual(text, changed)
        with tempfile.TemporaryDirectory(dir=os.path.join(ROOT, 'tmp')) as scratch:
            after = os.path.join(scratch, 'after.txt')
            with open(after, 'w') as f:
                f.write(changed)
            status, report, error = compare(None, before=before, after=after)
        self.assertEqual(status, 1, report + error)
        self.assertIn(ATOMIC_CLASS + 'changed instance-property atomicObject', section(report, 'DIFFERENCES:'))
        self.assertNotIn('CHECK AGAINST THE SOURCE', report)
        self.assertNotIn('was atomic', report)


class FailingPairTest(unittest.TestCase):
    def assert_fails_with(self, pair, *texts):
        status, report, error = compare(pair)
        self.assertEqual(status, 1, report + error)
        self.assertIn('FAIL: the snapshots do not match.', report)
        differences = section(report, 'DIFFERENCES:')
        for text in texts:
            self.assertIn(text, differences)
        return differences

    def test_renamed_class(self):
        self.assert_fails_with('renamed', 'class RuntimeSnapshotPortObjCFixture: only in before',
                               'class RuntimeSnapshotPortSwiftFixture: only in after')

    def test_dropped_method(self):
        differences = self.assert_fails_with('dropped-method', CLASS + 'removed instance-method -charValue types=c16@0:8')
        self.assertEqual(differences.count(CLASS), 1, differences)

    def test_changed_selector_encoding_and_dropped_protocol(self):
        differences = self.assert_fails_with(
            'changed-selector-encoding-protocol',
            CLASS + 'removed instance-method -describeWithPrefix:count: types=@32@0:8@16q24',
            CLASS + 'added instance-method -describe:count: types=@32@0:8@16q24',
            CLASS + 'changed instance-method -intValue\n      before: types=i16@0:8\n      after:  types=q16@0:8',
            CLASS + 'removed protocol RuntimeSnapshotPortFixtureProtocol')
        self.assertEqual(differences.count(CLASS), 4, differences)

    def test_property_became_readonly(self):
        differences = self.assert_fails_with(
            'readonly',
            CLASS + 'removed instance-method -setCount: types=v24@0:8q16',
            CLASS + 'changed instance-property count: became readonly')
        self.assertEqual(differences.count(CLASS), 2, differences)

    def test_load_and_initialize(self):
        self.assert_fails_with(
            'load-initialize',
            'class RuntimeSnapshotPortLoadObjCFixture: removed class-method +initialize: a Swift class cannot implement +initialize',
            'class RuntimeSnapshotPortLoadObjCFixture: removed class-method +load: a Swift class cannot implement +load')
        _, report, _ = compare('load-initialize')
        self.assertIn('class RuntimeSnapshotPortLoadObjCFixture: initializer instance-method -init is in the Swift class', section(report, 'CHECK AGAINST THE SOURCE'))

    def test_atomic_property_that_also_became_readonly(self):
        # Atomic becoming nonatomic alone is a check (AtomicPortTest); with
        # another change to the property it fails, and the failure names
        # both.
        differences = self.assert_fails_with(
            'atomic-readonly',
            ATOMIC_CLASS + 'removed instance-method -setAtomicObject: types=v24@0:8@16',
            ATOMIC_CLASS + 'changed instance-property atomicObject: ')
        self.assertIn('became readonly', differences)
        self.assertIn('atomic became nonatomic', differences)
        self.assertEqual(differences.count(ATOMIC_CLASS), 2, differences)

    def test_renamed_without_objc_name(self):
        self.assert_fails_with('renamed-module', 'class RuntimeSnapshotPortObjCFixture: only in before',
                               'class ModernTests.RuntimeSnapshotPortObjCFixture: only in after')

    def test_kept_init_of_a_port_without_init_is_a_check(self):
        # RuntimeSnapshotPortInitSwiftFixture declares only init(count:), so
        # its -init traps, although the -init line is the same as the
        # Objective-C class's.
        status, report, error = compare('init-stub')
        self.assertEqual(status, 0, report + error)
        checks = section(report, 'CHECK AGAINST THE SOURCE')
        self.assertIn('class RuntimeSnapshotPortInitObjCFixture: initializer instance-method -init is in the Swift class', checks)
        self.assertIn('class RuntimeSnapshotPortInitObjCFixture: initializer instance-method -initWithCount: is in the Swift class', checks)
        self.assertIn("Use of unimplemented initializer", checks)

    def test_reviewers_hand_written_pair(self):
        # Written by hand by the first reviewer: an int * that became a
        # pointer to a 64-bit integer, and a kept -init and -initWithFrame:.
        pair = os.path.join(HERE, 'fixtures', 'runtime_snapshot_compare_handwritten', 'pointer-and-kept-init')
        status, report, error = compare(None, before=os.path.join(pair, 'before.txt'), after=os.path.join(pair, 'after.txt'))
        self.assertEqual(status, 1, report + error)
        self.assertIn('class C: changed instance-method -getCount:\n      before: types=v24@0:8^i16\n      after:  types=v24@0:8^q16',
                      section(report, 'DIFFERENCES:'))
        checks = section(report, 'CHECK AGAINST THE SOURCE')
        self.assertIn('class C: initializer instance-method -init is in the Swift class', checks)
        self.assertIn('class C: initializer instance-method -initWithFrame: is in the Swift class', checks)

    def test_swift_to_objective_c_gets_no_verdict(self):
        status, report, _ = compare('faithful', before=os.path.join(PAIRS, 'faithful', 'after.txt'),
                                    after=os.path.join(PAIRS, 'faithful', 'before.txt'))
        self.assertEqual(status, 1, report)
        self.assertIn('NO VERDICT for these classes:\n  class RuntimeSnapshotPortObjCFixture changed language from swift to objc', report)


if __name__ == '__main__':
    unittest.main()
