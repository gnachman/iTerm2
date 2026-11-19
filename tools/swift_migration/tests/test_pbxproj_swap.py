"""Tests for tools/swift_migration/pbxproj_swap.py, which replaces a .m and
.h with a .swift in an Xcode project file.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_pbxproj_swap.py'

The fixture is a small project file in the shape Xcode writes: one group,
two targets, a Swift file to model the new entries on, and the .m and .h
being replaced.
"""

import io
import os
import random
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)

import pbxproj_swap  # noqa: E402

FIXTURE = '''// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tobjects = {

/* Begin PBXBuildFile section */
\t\t111111111111111111111111 /* Foo.h in Headers */ = {isa = PBXBuildFile; fileRef = 222222222222222222222222 /* Foo.h */; };
\t\t333333333333333333333333 /* Foo.m in Sources */ = {isa = PBXBuildFile; fileRef = 444444444444444444444444 /* Foo.m */; };
\t\t555555555555555555555555 /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = 666666666666666666666666 /* Bar.swift */; };
\t\t777777777777777777777777 /* Baz.m in Sources */ = {isa = PBXBuildFile; fileRef = 888888888888888888888888 /* Baz.m */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t222222222222222222222222 /* Foo.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = Foo.h; sourceTree = "<group>"; };
\t\t444444444444444444444444 /* Foo.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = Foo.m; sourceTree = "<group>"; };
\t\t666666666666666666666666 /* Bar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Bar.swift; sourceTree = "<group>"; };
\t\t888888888888888888888888 /* Baz.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = Baz.m; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
\t\tAAAAAAAAAAAAAAAAAAAAAAAA /* Things */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t222222222222222222222222 /* Foo.h */,
\t\t\t\t444444444444444444444444 /* Foo.m */,
\t\t\t\t666666666666666666666666 /* Bar.swift */,
\t\t\t\t888888888888888888888888 /* Baz.m */,
\t\t\t);
\t\t\tpath = Things;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */

/* Begin PBXHeadersBuildPhase section */
\t\tBBBBBBBBBBBBBBBBBBBBBBBB /* Headers */ = {
\t\t\tisa = PBXHeadersBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t111111111111111111111111 /* Foo.h in Headers */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXHeadersBuildPhase section */

/* Begin PBXNativeTarget section */
\t\tCCCCCCCCCCCCCCCCCCCCCCCC /* App */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildPhases = (
\t\t\t\tBBBBBBBBBBBBBBBBBBBBBBBB /* Headers */,
\t\t\t\tDDDDDDDDDDDDDDDDDDDDDDDD /* Sources */,
\t\t\t);
\t\t\tname = App;
\t\t};
\t\tEEEEEEEEEEEEEEEEEEEEEEEE /* Other */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildPhases = (
\t\t\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Sources */,
\t\t\t);
\t\t\tname = Other;
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXSourcesBuildPhase section */
\t\tDDDDDDDDDDDDDDDDDDDDDDDD /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t555555555555555555555555 /* Bar.swift in Sources */,
\t\t\t\t333333333333333333333333 /* Foo.m in Sources */,
\t\t\t\t777777777777777777777777 /* Baz.m in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */
\t};
\trootObject = 999999999999999999999999 /* Project object */;
}
'''


def changed_lines(old, new):
    """(removed, added) lines of a line diff, in order."""
    import difflib
    removed, added = [], []
    for line in difflib.ndiff(old.split('\n'), new.split('\n')):
        if line.startswith('- '):
            removed.append(line[2:])
        elif line.startswith('+ '):
            added.append(line[2:])
    return removed, added


class SwapTests(unittest.TestCase):
    def swap(self, text=FIXTURE, h='Things/Foo.h', **kw):
        return pbxproj_swap.swap(text, 'Things/Foo.m', h, 'Things/Foo.swift', rng=random.Random(1), **kw)

    def test_replaces_the_m_and_removes_the_h(self):
        new = self.swap()
        self.assertNotIn('Foo.m', new)
        self.assertNotIn('Foo.h', new)
        self.assertNotIn('444444444444444444444444', new)
        self.assertNotIn('333333333333333333333333', new)
        self.assertNotIn('111111111111111111111111', new)
        self.assertNotIn('222222222222222222222222', new)
        removed, added = changed_lines(FIXTURE, new)
        # 4 lines of the .m replaced, 4 lines of the .h removed.
        self.assertEqual(len(removed), 8)
        self.assertEqual(len(added), 4)
        ref = re.search(r'([0-9A-F]{24}) /\* Foo.swift \*/ = \{isa = PBXFileReference; '
                        r'lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; \};', new)
        self.assertIsNotNone(ref)
        bf = re.search(r'([0-9A-F]{24}) /\* Foo.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = '
                       + ref.group(1) + r' /\* Foo.swift \*/; \};', new)
        self.assertIsNotNone(bf)
        self.assertIn('\t\t\t\t%s /* Foo.swift */,\n\t\t\t\t666666666666666666666666' % ref.group(1), new)
        self.assertIn('555555555555555555555555 /* Bar.swift in Sources */,\n\t\t\t\t%s /* Foo.swift in Sources */,\n'
                      % bf.group(1), new)
        for ident in (ref.group(1), bf.group(1)):
            self.assertNotIn(ident, FIXTURE)
        self.assertNotEqual(ref.group(1), bf.group(1))

    def test_other_bytes_unchanged(self):
        new = self.swap()
        removed, added = changed_lines(FIXTURE, new)
        for line in removed:
            self.assertTrue('Foo.m' in line or 'Foo.h' in line, line)
        for line in added:
            self.assertIn('Foo.swift', line)
        self.assertTrue(new.endswith('}\n'))

    def test_without_h(self):
        new = self.swap(h=None)
        self.assertIn('Foo.h', new)
        self.assertNotIn('Foo.m', new)

    def test_refuses_m_in_two_targets_unless_told(self):
        text = FIXTURE.replace(
            '\t\t\tfiles = (\n\t\t\t);',
            '\t\t\tfiles = (\n\t\t\t\t123412341234123412341234 /* Foo.m in Sources */,\n\t\t\t);')
        text = text.replace(
            '/* End PBXBuildFile section */',
            '\t\t123412341234123412341234 /* Foo.m in Sources */ = {isa = PBXBuildFile; fileRef = '
            '444444444444444444444444 /* Foo.m */; };\n/* End PBXBuildFile section */')
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.swap(text)
        self.assertIn('2 targets', str(cm.exception))
        self.assertIn('App', str(cm.exception))
        self.assertIn('Other', str(cm.exception))
        new = self.swap(text, all_targets=True)
        self.assertNotIn('Foo.m', new)
        self.assertEqual(len(re.findall(r'/\* Foo.swift in Sources \*/ = ', new)), 2)

    def test_refuses_build_settings(self):
        text = FIXTURE.replace('fileRef = 444444444444444444444444 /* Foo.m */; };',
                               'fileRef = 444444444444444444444444 /* Foo.m */; settings = {COMPILER_FLAGS = "-fno-objc-arc"; }; };')
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.swap(text)
        self.assertIn('settings', str(cm.exception))

    def test_refuses_duplicate_group_child(self):
        text = FIXTURE.replace('\t\t\t\t444444444444444444444444 /* Foo.m */,\n',
                               '\t\t\t\t444444444444444444444444 /* Foo.m */,\n' * 2)
        with self.assertRaises(pbxproj_swap.Refusal):
            self.swap(text)

    def test_refuses_unexplained_reference(self):
        text = FIXTURE.replace('\trootObject', '\tstray = 444444444444444444444444;\n\trootObject')
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.swap(text)
        self.assertIn('occurs', str(cm.exception))

    def test_refuses_missing_file(self):
        with self.assertRaises(pbxproj_swap.Refusal):
            pbxproj_swap.swap(FIXTURE, 'Things/Nope.m', None, 'Things/Nope.swift')

    def test_refuses_existing_swift(self):
        with self.assertRaises(pbxproj_swap.Refusal):
            pbxproj_swap.swap(FIXTURE, 'Things/Baz.m', None, 'Things/Bar.swift')

    def test_refuses_other_directory(self):
        with self.assertRaises(pbxproj_swap.Refusal):
            pbxproj_swap.swap(FIXTURE, 'Things/Foo.m', None, 'Elsewhere/Foo.swift')

    def test_refuses_phase_of_wrong_kind(self):
        # The .m's build file listed in the Headers phase instead.
        text = FIXTURE.replace('\t\t\t\t333333333333333333333333 /* Foo.m in Sources */,\n', '')
        text = text.replace('\t\t\t\t111111111111111111111111 /* Foo.h in Headers */,\n',
                            '\t\t\t\t111111111111111111111111 /* Foo.h in Headers */,\n'
                            '\t\t\t\t333333333333333333333333 /* Foo.m in Sources */,\n')
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.swap(text)
        self.assertIn('PBXHeadersBuildPhase', str(cm.exception))

    def test_refuses_attribute_set_no_swift_file_has(self):
        text = FIXTURE.replace('lastKnownFileType = sourcecode.c.objc; path = Foo.m;',
                               'lastKnownFileType = sourcecode.c.objc; usesTabs = 1; path = Foo.m;')
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.swap(text)
        self.assertIn('attributes', str(cm.exception))

    def test_keeps_file_encoding_when_a_swift_file_has_it(self):
        text = FIXTURE.replace('lastKnownFileType = sourcecode.c.objc; path = Foo.m;',
                               'fileEncoding = 4; lastKnownFileType = sourcecode.c.objc; path = Foo.m;')
        text = text.replace('lastKnownFileType = sourcecode.swift; path = Bar.swift;',
                            'fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = Bar.swift;')
        new = self.swap(text)
        self.assertRegex(new, r'/\* Foo.swift \*/ = \{isa = PBXFileReference; fileEncoding = 4; '
                              r'lastKnownFileType = sourcecode.swift; path = Foo.swift;')


class MainTests(unittest.TestCase):
    def run_main(self, args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            status = pbxproj_swap.main(args)
        return status, out.getvalue(), err.getvalue()

    def test_check_writes_nothing_and_apply_writes(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'project.pbxproj')
            with open(path, 'w') as f:
                f.write(FIXTURE)
            args = ['--project', path, '--m', 'Things/Foo.m', '--h', 'Things/Foo.h', '--swift', 'Things/Foo.swift']
            status, out, _ = self.run_main(args + ['--check'])
            self.assertEqual(status, 0)
            self.assertIn('-\t\t444444444444444444444444 /* Foo.m */', out)
            with open(path) as f:
                self.assertEqual(f.read(), FIXTURE)
            status, _, _ = self.run_main(args)
            self.assertEqual(status, 0)
            with open(path) as f:
                self.assertNotIn('Foo.m', f.read())

    def test_refusal_exit_status(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'project.pbxproj')
            with open(path, 'w') as f:
                f.write(FIXTURE)
            status, _, err = self.run_main(['--project', path, '--m', 'Things/Nope.m', '--swift', 'Things/Nope.swift'])
            self.assertEqual(status, 1)
            self.assertIn('refused', err)
            with open(path) as f:
                self.assertEqual(f.read(), FIXTURE)


if __name__ == '__main__':
    unittest.main()
