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


OVERRIDE_PAIR = os.path.join(HERE, 'fixtures', 'runtime_snapshot_compare_handwritten', 'swift-override-property')
PANEL = 'class iTermFocusablePanel: '
OVERRIDE_HEADING = 'readonly property listed over an existing getter'
KEY_PROPERTY = ('  instance-property canBecomeKeyWindow type=B ownership=assign nonatomic readonly ivar= '
                'raw=TB,N,R\n')
KEY_GETTER = '  instance-method -canBecomeKeyWindow types=B16@0:8\n'


class SwiftOverridePropertyTest(unittest.TestCase):
    """A Swift class that overrides inherited getters, which the SDK imports
    as properties, with `override var` lists readonly property entries the
    Objective-C class did not (the port of iTermFocusablePanel). Such an
    entry is expected when the getter is the same method in both snapshots;
    the orchestrator's decision of 2026-11-26, open to the owner. The pair
    is written by hand in the shape of that port's snapshots."""

    def setUp(self):
        os.makedirs(os.path.join(ROOT, 'tmp'), exist_ok=True)
        self.scratch = tempfile.TemporaryDirectory(dir=os.path.join(ROOT, 'tmp'))
        with open(os.path.join(OVERRIDE_PAIR, 'before.txt')) as f:
            self.before = f.read()
        with open(os.path.join(OVERRIDE_PAIR, 'after.txt')) as f:
            self.after = f.read()

    def tearDown(self):
        self.scratch.cleanup()

    def run_pair(self, before, after):
        paths = []
        for label, text in (('before', before), ('after', after)):
            path = os.path.join(self.scratch.name, label + '.txt')
            with open(path, 'w') as f:
                f.write(text)
            paths.append(path)
        return compare(None, before=paths[0], after=paths[1])

    def assert_key_property_fails(self, before, after):
        self.assertNotEqual(before + after, self.before + self.after)
        status, report, error = self.run_pair(before, after)
        self.assertEqual(status, 1, report + error)
        self.assertIn(PANEL + 'added instance-property canBecomeKeyWindow', section(report, 'DIFFERENCES:'))
        return report

    def test_real_shape_passes_with_the_properties_expected(self):
        status, report, error = self.run_pair(self.before, self.after)
        self.assertEqual(status, 0, report + error)
        self.assertNotIn('DIFFERENCES:', report)
        expected = section(report, 'Expected differences of a move to Swift')
        for name in ['acceptsFirstResponder', 'canBecomeKeyWindow', 'canBecomeMainWindow']:
            self.assertIn(PANEL + 'added instance-property %s type=B ' % name, expected)
        self.assertEqual(expected.count(OVERRIDE_HEADING), 3, expected)

    def test_already_swift_passes(self):
        before = self.before.replace('language objc', 'language swift')
        status, report, error = self.run_pair(before, self.after)
        self.assertEqual(status, 0, report + error)
        self.assertEqual(report.count(OVERRIDE_HEADING), 3, report)

    def test_readwrite_property_fails(self):
        after = self.after.replace(KEY_PROPERTY, KEY_PROPERTY.replace(' readonly', '').replace(',R', ''))
        self.assert_key_property_fails(self.before, after)

    def test_custom_setter_fails(self):
        after = self.after.replace(KEY_PROPERTY, KEY_PROPERTY.replace(' ivar=', ' setter=setKey: ivar='))
        self.assert_key_property_fails(self.before, after)

    def test_getter_new_in_after_fails(self):
        report = self.assert_key_property_fails(self.before.replace(KEY_GETTER, ''), self.after)
        self.assertIn(PANEL + 'added instance-method -canBecomeKeyWindow', section(report, 'DIFFERENCES:'))

    def test_getter_with_another_encoding_before_fails(self):
        before = self.before.replace(KEY_GETTER, KEY_GETTER.replace('B16', 'c16'))
        report = self.assert_key_property_fails(before, self.after)
        self.assertIn(PANEL + 'changed instance-method -canBecomeKeyWindow', section(report, 'DIFFERENCES:'))

    def test_type_that_is_not_the_getters_return_fails(self):
        after = self.after.replace(KEY_PROPERTY, KEY_PROPERTY.replace('type=B', 'type=q').replace('TB', 'Tq'))
        self.assert_key_property_fails(self.before, after)

    def test_class_still_objc_fails(self):
        after = self.after.replace('language swift', 'language objc')
        report = self.assert_key_property_fails(self.before, after)
        self.assertNotIn(OVERRIDE_HEADING, report)

    def test_removed_property_fails(self):
        before = self.after.replace('language swift', 'language objc')
        after = self.after.replace(KEY_PROPERTY, '')
        self.assertNotEqual(after, self.after)
        status, report, error = self.run_pair(before, after)
        self.assertEqual(status, 1, report + error)
        self.assertIn(PANEL + 'removed instance-property canBecomeKeyWindow', section(report, 'DIFFERENCES:'))


SYSTEM_DUPLICATES = os.path.join(HERE, 'fixtures', 'runtime_snapshot_system_duplicates')
IGNORED_HEADING = 'Duplicates present in both snapshots, not from this app: ignored'
ENCODE_SYSTEM = '  instance-method -encodeWithCoder: types=v24@0:8@16 image=Foundation\n'
ENCODE_OWN = '  instance-method -encodeWithCoder: types=v24@0:8@16\n'
ENCODE_DUP = '  DUPLICATE instance-method -encodeWithCoder: count=2\n'
HEADER = ('# Objective-C runtime snapshot, format 3\narchitecture arm64\n'
          'build-configuration Development\nbuild-variant ASan\n')


def minimal_section(name, image, *members):
    body = ['language objc', 'superclass NSObject', 'image ' + image, 'ivar-arc-flag unknown',
            'strong-ivar-layout', 'weak-ivar-layout'] + list(members)
    return 'class %s\n' % name + ''.join('  %s\n' % line for line in body) + 'end class %s\n' % name


class SystemDuplicatesTest(unittest.TestCase):
    """A duplicate fails only when it is new or changed between the snapshots
    or has an entry from the app's own image (the owner, 2026-11-25:
    “Yes, of course”). The real pair is NSLocale's snapshot from a parked
    port, whose method list holds -initWithCoder: and -encodeWithCoder:
    twice (once image=Foundation, once in the class's own image,
    CoreFoundation), byte-identical before and after."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        with open(os.path.join(SYSTEM_DUPLICATES, 'before.txt')) as f:
            self.real = f.read()

    def tearDown(self):
        self.scratch.cleanup()

    def run_pair(self, before, after):
        paths = []
        for label, text in (('before', before), ('after', after)):
            path = os.path.join(self.scratch.name, label + '.txt')
            with open(path, 'w') as f:
                f.write(text)
            paths.append(path)
        return compare(None, before=paths[0], after=paths[1])

    def test_real_pair_passes_and_reports_the_ignored_duplicates(self):
        status, report, error = compare(None, before=os.path.join(SYSTEM_DUPLICATES, 'before.txt'),
                                        after=os.path.join(SYSTEM_DUPLICATES, 'after.txt'))
        self.assertEqual(status, 0, report + error)
        self.assertIn('PASS: the snapshots match.', report)
        self.assertNotIn('DUPLICATES (', report)
        ignored = section(report, IGNORED_HEADING)
        self.assertIn('class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=2', ignored)
        self.assertIn('class NSLocale: DUPLICATE instance-method -initWithCoder: count=2', ignored)
        self.assertIn('images CoreFoundation, Foundation', ignored)

    def test_self_comparison_passes(self):
        status, report, _ = self.run_pair(self.real, self.real)
        self.assertEqual(status, 0, report)

    def test_duplicate_only_in_after_fails(self):
        before = self.real.replace(ENCODE_DUP, '').replace(ENCODE_OWN, '')
        status, report, _ = self.run_pair(before, self.real)
        self.assertEqual(status, 1, report)
        self.assertIn('after: class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=2',
                      section(report, 'DUPLICATES ('))
        self.assertNotIn('before: class NSLocale: DUPLICATE instance-method -encodeWithCoder:', report)
        # The other, unchanged duplicate is still only reported.
        self.assertIn('-initWithCoder:', section(report, IGNORED_HEADING))

    def test_duplicate_only_in_before_fails(self):
        after = self.real.replace(ENCODE_DUP, '').replace(ENCODE_OWN, '')
        status, report, _ = self.run_pair(self.real, after)
        self.assertEqual(status, 1, report)
        self.assertIn('before: class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=2',
                      section(report, 'DUPLICATES ('))

    def test_count_change_fails(self):
        after = self.real.replace(ENCODE_DUP, ENCODE_DUP.replace('count=2', 'count=3')).replace(
            ENCODE_OWN, ENCODE_OWN + '  instance-method -encodeWithCoder: types=v24@0:8@16 image=Translation\n')
        status, report, _ = self.run_pair(self.real, after)
        self.assertEqual(status, 1, report)
        duplicates = section(report, 'DUPLICATES (')
        self.assertIn('before: class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=2', duplicates)
        self.assertIn('after: class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=3', duplicates)

    def test_changed_image_fails(self):
        after = self.real.replace(ENCODE_SYSTEM, ENCODE_SYSTEM.replace('Foundation', 'Translation'))
        status, report, _ = self.run_pair(self.real, after)
        self.assertEqual(status, 1, report)
        self.assertIn('DUPLICATE instance-method -encodeWithCoder: count=2', section(report, 'DUPLICATES ('))

    def test_app_image_entry_identical_in_both_still_fails(self):
        # A category of the app colliding with a system method: identical in
        # both snapshots, but one entry is the app's own code.
        own = self.real.replace(ENCODE_SYSTEM, ENCODE_SYSTEM.replace('image=Foundation', 'image=iTerm2.debug.dylib'))
        status, report, _ = self.run_pair(own, own)
        self.assertEqual(status, 1, report)
        duplicates = section(report, 'DUPLICATES (')
        self.assertIn('before: class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=2', duplicates)
        self.assertIn('after: class NSLocale: DUPLICATE instance-method -encodeWithCoder: count=2', duplicates)
        self.assertNotIn('-encodeWithCoder:', section(report, IGNORED_HEADING))

    def test_app_class_duplicate_identical_in_both_still_fails(self):
        # A port that defines a method twice: the entries carry no image=, so
        # they are in the class's own image, the app's.
        for image in ['iTerm2.debug.dylib', 'iTerm2', 'ModernTests', 'BetterFontPicker']:
            text = HEADER + minimal_section('C', image, 'DUPLICATE instance-method -foo count=2',
                                            'instance-method -foo types=v16@0:8',
                                            'instance-method -foo types=v16@0:8')
            status, report, _ = self.run_pair(text, text)
            self.assertEqual(status, 1, image + '\n' + report)
            self.assertIn('before: class C: DUPLICATE instance-method -foo count=2', section(report, 'DUPLICATES ('))

    def test_entry_in_no_binary_is_treated_as_the_apps(self):
        text = HEADER + minimal_section('C', 'Foundation', 'DUPLICATE instance-method -foo count=2',
                                        'instance-method -foo types=v16@0:8',
                                        'instance-method -foo types=v16@0:8 image=')
        status, report, _ = self.run_pair(text, text)
        self.assertEqual(status, 1, report)

    def test_system_class_duplicate_identical_in_both_passes(self):
        text = HEADER + minimal_section('C', 'Foundation', 'DUPLICATE class-method +foo count=2',
                                        'class-method +foo types=v16@0:8',
                                        'class-method +foo types=v16@0:8 image=AppKit')
        status, report, _ = self.run_pair(text, text)
        self.assertEqual(status, 0, report)
        self.assertIn('class C: DUPLICATE class-method +foo count=2', section(report, IGNORED_HEADING))

    def test_undeclared_repeat_still_fails(self):
        # A repeated method with no DUPLICATE line is a malformed snapshot.
        text = HEADER + minimal_section('C', 'Foundation', 'instance-method -foo types=v16@0:8',
                                        'instance-method -foo types=v16@0:8 image=AppKit')
        status, report, _ = self.run_pair(text, text)
        self.assertEqual(status, 1, report)
        self.assertIn('appears 2 times with no DUPLICATE line', section(report, 'DUPLICATES ('))

    PROPERTY_A = 'instance-property p type=@"NSString" ownership=copy nonatomic ivar= raw=T@"NSString",C,N'
    PROPERTY_B = 'instance-property p type=@"NSString" ownership=strong nonatomic ivar= raw=T@"NSString",&,N'

    def test_property_duplicate_in_system_class_identical_in_both_passes(self):
        text = HEADER + minimal_section('C', 'Foundation', 'DUPLICATE instance-property p count=2',
                                        self.PROPERTY_A, self.PROPERTY_B)
        status, report, _ = self.run_pair(text, text)
        self.assertEqual(status, 0, report)
        self.assertIn('class C: DUPLICATE instance-property p count=2', section(report, IGNORED_HEADING))

    def test_property_duplicate_only_in_after_fails(self):
        before = HEADER + minimal_section('C', 'Foundation', self.PROPERTY_A)
        after = HEADER + minimal_section('C', 'Foundation', 'DUPLICATE instance-property p count=2',
                                         self.PROPERTY_A, self.PROPERTY_B)
        status, report, _ = self.run_pair(before, after)
        self.assertEqual(status, 1, report)
        self.assertIn('after: class C: DUPLICATE instance-property p count=2', section(report, 'DUPLICATES ('))

    def test_property_duplicate_in_app_class_identical_in_both_fails(self):
        text = HEADER + minimal_section('C', 'iTerm2.debug.dylib', 'DUPLICATE instance-property p count=2',
                                        self.PROPERTY_A, self.PROPERTY_B)
        status, report, _ = self.run_pair(text, text)
        self.assertEqual(status, 1, report)


if __name__ == '__main__':
    unittest.main()
