"""Tests for tools/swift_migration/pbxproj_swap.py, which replaces a .m and
.h with a .swift in an Xcode project file, or moves a .m from one target's
Sources phase to another's.

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


FOO_H_BUILD_FILE = ('\t\t111111111111111111111111 /* Foo.h in Headers */ = {isa = PBXBuildFile; '
                    'fileRef = 222222222222222222222222 /* Foo.h */; };')
FOO_H_ENTRY = '\t\t\t\t111111111111111111111111 /* Foo.h in Headers */,'
FOO_H_SOURCES_ENTRY = '\t\t\t\t111111111111111111111111 /* Foo.h in Sources */,'


def with_h_in_sources(text=FIXTURE, phase='DDDDDDDDDDDDDDDDDDDDDDDD'):
    """The fixture with Foo.h's build file listed in the Sources phase called phase
    instead of the Headers phase, as Xcode does when a header is added to a target's
    sources by mistake."""
    text = text.replace(FOO_H_BUILD_FILE, FOO_H_BUILD_FILE.replace('Foo.h in Headers', 'Foo.h in Sources'))
    text = text.replace(FOO_H_ENTRY + '\n', '')
    opening = '\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n' \
              '\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n' % phase
    assert opening in text
    return text.replace(opening, opening + FOO_H_SOURCES_ENTRY + '\n')


class HeaderInSourcesTests(unittest.TestCase):
    """A header whose build file is listed in a Sources phase compiles nothing there;
    the swap removes it as it removes a header's build file from a Headers phase."""

    def swap(self, text, notes=None, **kw):
        if notes is not None:
            kw['notes'] = notes
        return pbxproj_swap.swap(text, 'Things/Foo.m', 'Things/Foo.h', 'Things/Foo.swift',
                                 rng=random.Random(1), **kw)

    def refusal(self, text, **kw):
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.swap(text, **kw)
        return str(cm.exception)

    def test_removes_the_header_and_reports_it(self):
        text = with_h_in_sources()
        notes = []
        new = self.swap(text, notes=notes)
        for gone in ('Foo.h', 'Foo.m', '111111111111111111111111', '222222222222222222222222',
                     '333333333333333333333333', '444444444444444444444444'):
            self.assertNotIn(gone, new)
        removed, added = changed_lines(text, new)
        # 4 lines of the .m replaced; the .h's file reference, group child, build file and
        # Sources phase entry removed.
        self.assertEqual(len(removed), 8)
        self.assertEqual(len(added), 4)
        for line in removed:
            self.assertTrue('Foo.m' in line or 'Foo.h' in line, line)
        for line in added:
            self.assertIn('Foo.swift', line)
        self.assertRegex(new, r'\t\t\tfiles = \(\n\t\t\t\t555555555555555555555555 /\* Bar.swift in Sources \*/,\n'
                              r'\t\t\t\t[0-9A-F]{24} /\* Foo.swift in Sources \*/,\n'
                              r'\t\t\t\t777777777777777777777777 /\* Baz.m in Sources \*/,\n\t\t\t\);')
        # The Headers phase is left as it was, now with no entry removed from it.
        self.assertIn('\t\t\tisa = PBXHeadersBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
                      '\t\t\tfiles = (\n\t\t\t);', new)
        self.assertEqual(len(notes), 1)
        self.assertIn('Foo.h', notes[0])
        self.assertIn('Sources phase', notes[0])
        self.assertIn('App', notes[0])
        self.assertIn('this swap removes its build file and phase entry', notes[0])

    def test_notes_are_optional(self):
        new = self.swap(with_h_in_sources())
        self.assertNotIn('Foo.h', new)

    def test_header_in_a_headers_phase_gives_no_note(self):
        notes = []
        self.swap(FIXTURE, notes=notes)
        self.assertEqual(notes, [])

    def test_removes_the_header_from_every_target_the_swap_covers(self):
        # The Other target's files are added first: once Foo.h leaves the Headers phase, its
        # empty files list looks the same as the Other target's.
        text = with_h_in_sources(with_other_files(FIXTURE,
                                                  '\t\t\t\t123412341234123412341234 /* Foo.m in Sources */,',
                                                  '\t\t\t\t565656565656565656565656 /* Foo.h in Sources */,'))
        text = with_build_file(text, '\t\t123412341234123412341234 /* Foo.m in Sources */ = {isa = PBXBuildFile; '
                                     'fileRef = 444444444444444444444444 /* Foo.m */; };')
        text = with_build_file(text, '\t\t565656565656565656565656 /* Foo.h in Sources */ = {isa = PBXBuildFile; '
                                     'fileRef = 222222222222222222222222 /* Foo.h */; };')
        notes = []
        new = self.swap(text, notes=notes, all_targets=True)
        self.assertNotIn('Foo.h', new)
        self.assertNotIn('Foo.m', new)
        self.assertEqual(len(re.findall(r'/\* Foo.swift in Sources \*/,', new)), 2)
        self.assertEqual(len(notes), 2)
        self.assertTrue(any('App' in n for n in notes))
        self.assertTrue(any('Other' in n for n in notes))

    def test_refuses_header_in_sources_phase_of_a_target_without_the_m(self):
        message = self.refusal(with_h_in_sources(phase='FFFFFFFFFFFFFFFFFFFFFFFF'))
        self.assertIn('Foo.h', message)
        self.assertIn('Other', message)

    def test_refuses_sources_build_file_listed_in_a_headers_phase(self):
        # The build file says Sources but its entry is in the Headers phase.
        text = FIXTURE.replace(FOO_H_BUILD_FILE, FOO_H_BUILD_FILE.replace('Foo.h in Headers', 'Foo.h in Sources'))
        text = text.replace(FOO_H_ENTRY, FOO_H_SOURCES_ENTRY)
        self.assertIn('PBXHeadersBuildPhase', self.refusal(text))

    def test_refuses_header_in_a_phase_other_than_headers_or_sources(self):
        text = FIXTURE.replace(FOO_H_BUILD_FILE, FOO_H_BUILD_FILE.replace('Foo.h in Headers', 'Foo.h in Resources'))
        text = text.replace(FOO_H_ENTRY, '\t\t\t\t111111111111111111111111 /* Foo.h in Resources */,')
        self.assertIn('expected Headers', self.refusal(text))

    def test_refuses_public_or_private_header(self):
        for attribute in ('Public', 'Private'):
            text = FIXTURE.replace(FOO_H_BUILD_FILE, FOO_H_BUILD_FILE.replace(
                '/* Foo.h */; };', '/* Foo.h */; settings = {ATTRIBUTES = (%s, ); }; };' % attribute))
            message = self.refusal(text)
            self.assertIn('Foo.h', message)
            self.assertIn(attribute, message)
            self.assertIn('does not remove a header with settings', message)

    def test_refuses_header_in_sources_with_settings(self):
        text = with_h_in_sources()
        text = text.replace('fileRef = 222222222222222222222222 /* Foo.h */; };',
                            'fileRef = 222222222222222222222222 /* Foo.h */; settings = {COMPILER_FLAGS = "-w"; }; };')
        message = self.refusal(text)
        self.assertIn('-w', message)
        self.assertIn('does not remove a header with settings', message)

    def test_refuses_unexplained_header_build_file_reference(self):
        text = with_h_in_sources().replace('\trootObject', '\tstray = 111111111111111111111111;\n\trootObject')
        self.assertIn('occurs', self.refusal(text))

    def test_refuses_header_entry_listed_twice(self):
        text = with_h_in_sources().replace(FOO_H_SOURCES_ENTRY + '\n', (FOO_H_SOURCES_ENTRY + '\n') * 2)
        self.assertIn('exactly one', self.refusal(text))


FOO_M_ENTRY = '\t\t\t\t333333333333333333333333 /* Foo.m in Sources */,'
FOO_M_BUILD_FILE = ('\t\t333333333333333333333333 /* Foo.m in Sources */ = {isa = PBXBuildFile; '
                    'fileRef = 444444444444444444444444 /* Foo.m */; };')
EMPTY_OTHER_FILES = '\t\t\tfiles = (\n\t\t\t);'


def with_other_files(text, *entries):
    """The fixture with entries listed in the Other target's Sources phase."""
    return text.replace(EMPTY_OTHER_FILES, '\t\t\tfiles = (\n' + ''.join(e + '\n' for e in entries) + '\t\t\t);')


def with_build_file(text, line):
    return text.replace('/* End PBXBuildFile section */', line + '\n/* End PBXBuildFile section */')


class MoveTests(unittest.TestCase):
    def move(self, text=FIXTURE, m='Things/Foo.m', from_target='App', to_target='Other'):
        return pbxproj_swap.move_to_target(text, m, from_target, to_target)

    def refusal(self, text=FIXTURE, **kw):
        with self.assertRaises(pbxproj_swap.Refusal) as cm:
            self.move(text, **kw)
        return str(cm.exception)

    def test_moves_the_sources_entry_and_nothing_else(self):
        new = self.move()
        removed, added = changed_lines(FIXTURE, new)
        self.assertEqual(removed, [FOO_M_ENTRY])
        self.assertEqual(added, [FOO_M_ENTRY])
        # The PBXBuildFile is kept: it now belongs to the Other target's phase.
        self.assertIn(FOO_M_BUILD_FILE, new)
        self.assertIn('\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n'
                      '\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n' + FOO_M_ENTRY + '\n\t\t\t);', new)
        self.assertIn('555555555555555555555555 /* Bar.swift in Sources */,\n'
                      '\t\t\t\t777777777777777777777777 /* Baz.m in Sources */,\n\t\t\t);', new)
        # The .h is left alone.
        self.assertIn('111111111111111111111111 /* Foo.h in Headers */,', new)
        self.assertTrue(new.endswith('}\n'))

    def test_appends_after_existing_entries(self):
        text = with_other_files(FIXTURE, '\t\t\t\t121212121212121212121212 /* Qux.m in Sources */,')
        new = self.move(text)
        self.assertIn('\t\t\t\t121212121212121212121212 /* Qux.m in Sources */,\n' + FOO_M_ENTRY + '\n\t\t\t);', new)

    def test_moves_from_a_phase_later_in_the_file(self):
        # Other's Sources phase comes after App's, as iTerm2Shared's comes after iTerm2SharedARC's.
        text = with_other_files(FIXTURE.replace(FOO_M_ENTRY + '\n', ''), FOO_M_ENTRY,
                                '\t\t\t\t121212121212121212121212 /* Qux.m in Sources */,')
        new = self.move(text, from_target='Other', to_target='App')
        self.assertEqual(changed_lines(text, new), ([FOO_M_ENTRY], [FOO_M_ENTRY]))
        self.assertIn('\t\t\t\t555555555555555555555555 /* Bar.swift in Sources */,\n'
                      '\t\t\t\t777777777777777777777777 /* Baz.m in Sources */,\n' + FOO_M_ENTRY + '\n\t\t\t);', new)
        self.assertIn('\t\t\tfiles = (\n\t\t\t\t121212121212121212121212 /* Qux.m in Sources */,\n\t\t\t);', new)
        self.assertEqual(new.count('333333333333333333333333'), 2)

    def test_refuses_to_phase_without_files_list(self):
        text = FIXTURE.replace(EMPTY_OTHER_FILES + '\n', '')
        self.assertIn('no files list', self.refusal(text))

    def test_refuses_unclosed_files_list(self):
        text = FIXTURE.replace(EMPTY_OTHER_FILES, '\t\t\tfiles = (')
        self.assertIn('not closed', self.refusal(text))

    def test_refuses_missing_group_child(self):
        # The group lists the reference under another name, so the counts still add up.
        text = FIXTURE.replace('\t\t\t\t444444444444444444444444 /* Foo.m */,',
                               '\t\t\t\t444444444444444444444444 /* Renamed.m */,')
        self.assertIn('group child', self.refusal(text))

    def test_refuses_build_file_in_a_phase_other_than_sources(self):
        text = with_build_file(FIXTURE, '\t\t565656565656565656565656 /* Foo.m in Headers */ = {isa = PBXBuildFile; '
                                        'fileRef = 444444444444444444444444 /* Foo.m */; };')
        text = text.replace('\t\t\t\t111111111111111111111111 /* Foo.h in Headers */,\n',
                            '\t\t\t\t111111111111111111111111 /* Foo.h in Headers */,\n'
                            '\t\t\t\t565656565656565656565656 /* Foo.m in Headers */,\n')
        self.assertIn('expected Sources', self.refusal(text))

    def test_refuses_two_file_references_of_the_same_name(self):
        text = FIXTURE.replace('/* End PBXFileReference section */',
                               '\t\t787878787878787878787878 /* Foo.m */ = {isa = PBXFileReference; '
                               'lastKnownFileType = sourcecode.c.objc; path = Foo.m; sourceTree = "<group>"; };\n'
                               '/* End PBXFileReference section */')
        self.assertIn('PBXFileReference of Foo.m', self.refusal(text))

    def test_quoted_target_name_with_escaped_quotes(self):
        text = FIXTURE.replace('\t\t\tname = Other;', '\t\t\tname = "Other \\"X\\"";')
        new = self.move(text, to_target='Other "X"')
        self.assertEqual(changed_lines(text, new), ([FOO_M_ENTRY], [FOO_M_ENTRY]))

    def test_composes_with_swap(self):
        new = pbxproj_swap.swap(self.move(), 'Things/Foo.m', 'Things/Foo.h', 'Things/Foo.swift', rng=random.Random(1))
        self.assertRegex(new, r'FFFFFFFFFFFFFFFFFFFFFFFF /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n'
                              r'\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n'
                              r'\t\t\t\t[0-9A-F]{24} /\* Foo.swift in Sources \*/,\n\t\t\t\);')

    def test_refuses_m_not_in_from_target(self):
        # A third target, so that Baz.m (in App) is in neither the from- nor the to-target.
        text = FIXTURE.replace('/* End PBXNativeTarget section */',
                               '\t\tABABABABABABABABABABABAB /* Third */ = {\n\t\t\tisa = PBXNativeTarget;\n'
                               '\t\t\tbuildPhases = (\n\t\t\t\tCDCDCDCDCDCDCDCDCDCDCDCD /* Sources */,\n\t\t\t);\n'
                               '\t\t\tname = Third;\n\t\t};\n/* End PBXNativeTarget section */')
        text = text.replace('/* End PBXSourcesBuildPhase section */',
                            '\t\tCDCDCDCDCDCDCDCDCDCDCDCD /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n'
                            '\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n'
                            '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
                            '/* End PBXSourcesBuildPhase section */')
        self.move(text, m='Things/Baz.m', from_target='App', to_target='Third')  # the fixture is sound
        message = self.refusal(text, m='Things/Baz.m', from_target='Other', to_target='Third')
        self.assertIn('not in', message)
        self.assertIn('Other', message)

    def test_refuses_m_in_no_target(self):
        text = FIXTURE.replace(FOO_M_ENTRY + '\n', '').replace(FOO_M_BUILD_FILE + '\n', '')
        self.assertIn('not in', self.refusal(text))

    def test_refuses_m_already_in_to_target(self):
        text = with_other_files(FIXTURE, '\t\t\t\t123412341234123412341234 /* Foo.m in Sources */,')
        text = with_build_file(text, '\t\t123412341234123412341234 /* Foo.m in Sources */ = {isa = PBXBuildFile; '
                                     'fileRef = 444444444444444444444444 /* Foo.m */; };')
        message = self.refusal(text)
        self.assertIn('already', message)
        self.assertIn('Other', message)

    def test_refuses_m_twice_in_from_target(self):
        text = FIXTURE.replace(FOO_M_ENTRY + '\n', FOO_M_ENTRY + '\n'
                               '\t\t\t\t123412341234123412341234 /* Foo.m in Sources */,\n')
        text = with_build_file(text, '\t\t123412341234123412341234 /* Foo.m in Sources */ = {isa = PBXBuildFile; '
                                     'fileRef = 444444444444444444444444 /* Foo.m */; };')
        message = self.refusal(text)
        self.assertIn('2 times', message)
        self.assertIn('App', message)

    def test_refuses_target_with_two_sources_phases(self):
        text = FIXTURE.replace('\t\t\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Sources */,\n',
                               '\t\t\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Sources */,\n'
                               '\t\t\t\tABABABABABABABABABABABAB /* Sources */,\n')
        text = text.replace('/* End PBXSourcesBuildPhase section */',
                            '\t\tABABABABABABABABABABABAB /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n'
                            '\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n'
                            '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n'
                            '/* End PBXSourcesBuildPhase section */')
        message = self.refusal(text)
        self.assertIn('2 Sources phases', message)
        self.assertIn('Other', message)

    def test_refuses_build_settings_and_names_them(self):
        for flag in ('-fno-objc-arc', '-fobjc-arc'):
            text = FIXTURE.replace(FOO_M_BUILD_FILE, FOO_M_BUILD_FILE.replace(
                '/* Foo.m */; };', '/* Foo.m */; settings = {COMPILER_FLAGS = "%s"; }; };' % flag))
            message = self.refusal(text)
            self.assertIn('settings', message)
            self.assertIn(flag, message)

    def test_refuses_unknown_target(self):
        self.assertIn('Nope', self.refusal(to_target='Nope'))
        self.assertIn('Nope', self.refusal(from_target='Nope'))

    def test_refuses_ambiguous_target(self):
        text = FIXTURE.replace('\t\t\tname = Other;', '\t\t\tname = App;')
        message = self.refusal(text, from_target='App', to_target='Other')
        self.assertIn('2 native targets', message)

    def test_refuses_same_target(self):
        self.assertIn('same', self.refusal(to_target='App'))

    def test_refuses_unexplained_build_file_reference(self):
        text = FIXTURE.replace('\trootObject', '\tstray = 333333333333333333333333;\n\trootObject')
        self.assertIn('occurs', self.refusal(text))

    def test_refuses_unexplained_file_reference(self):
        text = FIXTURE.replace('\trootObject', '\tstray = 444444444444444444444444;\n\trootObject')
        self.assertIn('occurs', self.refusal(text))

    def test_refuses_shared_sources_phase(self):
        # The Other target lists the App target's Sources phase too.
        text = FIXTURE.replace('\t\t\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Sources */,\n',
                               '\t\t\t\tDDDDDDDDDDDDDDDDDDDDDDDD /* Sources */,\n')
        self.assertIn('occurs', self.refusal(text))

    def test_refuses_not_a_dot_m(self):
        self.refusal(m='Things/Bar.swift')

    def test_quoted_target_name(self):
        text = FIXTURE.replace('\t\t\tname = Other;', '\t\t\tname = "Other Thing";')
        new = self.move(text, to_target='Other Thing')
        self.assertEqual(changed_lines(text, new), ([FOO_M_ENTRY], [FOO_M_ENTRY]))


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

    def test_reports_a_header_listed_in_sources(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'project.pbxproj')
            text = with_h_in_sources()
            with open(path, 'w') as f:
                f.write(text)
            status, out, err = self.run_main(['--project', path, '--m', 'Things/Foo.m', '--h', 'Things/Foo.h',
                                              '--swift', 'Things/Foo.swift', '--check'])
            self.assertEqual(status, 0)
            self.assertIn('-' + FOO_H_SOURCES_ENTRY, out)
            self.assertIn('Foo.h', err)
            self.assertIn('Sources phase', err)
            self.assertIn('App', err)
            with open(path) as f:
                self.assertEqual(f.read(), text)

    def test_move_check_writes_nothing_and_apply_writes(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'project.pbxproj')
            with open(path, 'w') as f:
                f.write(FIXTURE)
            args = ['--project', path, '--m', 'Things/Foo.m', '--from-target', 'App', '--to-target', 'Other']
            status, out, _ = self.run_main(args + ['--check'])
            self.assertEqual(status, 0)
            self.assertIn('-' + FOO_M_ENTRY, out)
            self.assertIn('+' + FOO_M_ENTRY, out)
            with open(path) as f:
                self.assertEqual(f.read(), FIXTURE)
            status, _, _ = self.run_main(['--project', path, '--m', 'Things/Foo.m', '--from-target', 'App',
                                          '--move-to-target', 'Other'])
            self.assertEqual(status, 0)
            with open(path) as f:
                self.assertEqual(f.read(), pbxproj_swap.move_to_target(FIXTURE, 'Things/Foo.m', 'App', 'Other'))

    def test_move_refusal_exit_status(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'project.pbxproj')
            with open(path, 'w') as f:
                f.write(FIXTURE)
            status, _, err = self.run_main(['--project', path, '--m', 'Things/Foo.m', '--from-target', 'App',
                                            '--to-target', 'Nope'])
            self.assertEqual(status, 1)
            self.assertIn('refused', err)
            with open(path) as f:
                self.assertEqual(f.read(), FIXTURE)

    def test_move_usage_errors(self):
        base = ['--project', '/nonexistent/project.pbxproj', '--m', 'Things/Foo.m']
        for extra in (['--to-target', 'Other'],
                      ['--from-target', 'App'],
                      ['--from-target', 'App', '--to-target', 'Other', '--swift', 'Things/Foo.swift'],
                      ['--from-target', 'App', '--to-target', 'Other', '--h', 'Things/Foo.h'],
                      ['--from-target', 'App', '--to-target', 'Other', '--all-targets'],
                      []):
            with self.assertRaises(SystemExit) as cm:
                self.run_main(base + extra)
            self.assertEqual(cm.exception.code, 2, extra)


if __name__ == '__main__':
    unittest.main()
