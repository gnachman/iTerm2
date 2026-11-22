#!/usr/bin/env python3
"""Tests for entry_points.py, the entry-point census.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_entry_points.py'

The database-backed tests build a code database of the fixture repository
(tests/fixtures/entry_points) with the real extractor and Swift reader; see
entry_points_harness.py for the binaries and the environment variables. No
xcodebuild, no app build, nothing written to tmp/codedb. Expected rows are
written out by hand from the fixture files.
"""

import io
import json
import os
import re
import sqlite3
import sys
import unittest
from unittest import mock

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import entry_points_harness as harness  # noqa: E402  (imports codedb and swiftdb first)
import entry_points as ep  # noqa: E402

FIXTURE = harness.FIXTURE
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
REG = 'docs/swift-migration/reflective-sites.md'
OPEN_SITE = (REG + ':36', 'cannot be ruled out: OPEN-INTERNAL site that can reach names the registry does not list: '
             'Performs any selector named by its caller on any object.  site: ThirdParty/PSMTabBarControl/PSM.m:8 in '
             'PSMDynamic')


def tearDownModule():
    harness.cleanup()


def read(path):
    with open(os.path.join(FIXTURE, path), 'r', encoding='utf-8') as f:
        return f.read()


# --- The registry -------------------------------------------------------------

class RegistryParserTest(unittest.TestCase):
    def setUp(self):
        self.text = read(REG)

    def test_names_table_of_the_fixture_copy(self):
        reg = ep.parse_registry(self.text)
        self.assertEqual([(n.name, n.resolves, n.runtime, n.note, n.sites, n.line) for n in reg.names], [
            ('contextMenuAction*', '1 selectors with prefix', None, 'selector prefix pattern (Widget.m:1)',
             ['sources/Widget.m:1'], 17),
            ('iTermThingMO', 'class', 'iTermThingMO', 'persisted by name', ['sources/Widget.m:70'], 18),
            ('iTermWidget +load_*', '0 class methods with prefix', None, '', ['sources/Widget.m:2'], 19),
            ('iTermWidget.fooBar', 'property', None, '', ['sources/Widget.m:26'], 20),
            ('stringPerformed', 'selector', None, '', ['sources/Widget.m:23'], 21),
        ])

    def test_entries_of_the_fixture_copy(self):
        reg = ep.parse_registry(self.text)
        self.assertEqual([(e.section, e.heading, [tuple(s) for s in e.sites], e.classification, e.names, e.line)
                          for e in reg.entries], [
            (3, 'ThirdParty/PSMTabBarControl/PSM.m', [('ThirdParty/PSMTabBarControl/PSM.m', 8, 'PSMDynamic',
                                                       ((None, 8),)),
                                                      ('ThirdParty/PSMTabBarControl/PSM.m', 8, 'PSMDynamic',
                                                       ((None, 8),))],
             'OPEN-INTERNAL', [], 36),
            (3, 'sources/Widget.m', [('sources/Widget.m', 23, '-[iTermWidget go]', ((None, 23),))], 'CLOSED',
             ['stringPerformed'], 44),
            (5, None, [('sources/Widget.m', 1, '-[iTermWidget validateMenuItem:]', ((None, 1),))], 'CLOSED',
             ['contextMenuAction*'], 56),
            (5, None, [('sources/Widget.m', 26, '-[iTermWidget go]', ((None, 26),))], 'CLOSED',
             ['iTermWidget.fooBar', 'iTermWidget +load_*'], 62),
            (6, None, [('sources/Widget.m', 70, None, ((None, 70),))], 'OPEN-EXTERNAL', ['iTermThingMO'], 72),
            (9, 'sources/SDKUsers.m', [('sources/SDKUsers.m', 71, '-[iTermScriptingWindow methodSignatureForSelector:]',
                                        ((None, 71),))], 'GENERIC', [], 88),
        ])
        self.assertEqual(reg.unparsed, [])

    def test_the_real_registry_parses(self):
        with open(os.path.join(REPO, REG), 'r', encoding='utf-8') as f:
            reg = ep.parse_registry(f.read())
        self.assertGreater(len(reg.names), 400)
        self.assertGreater(len(reg.entries), 100)
        self.assertIn('contextMenuAction*', [n.name for n in reg.names])

    def assert_shape_error(self, old, new, message):
        self.assertIn(old, self.text)
        with self.assertRaisesRegex(ep.RegistryError, message):
            ep.parse_registry(self.text.replace(old, new, 1))

    def test_a_changed_header_fails(self):
        self.assert_shape_error('| Name | Resolves |', '| Name | Resolution |', "header is not")

    def test_a_missing_heading_fails(self):
        self.assert_shape_error('### Names that must be preserved', '### Names', 'no line')

    def test_a_row_with_four_cells_fails(self):
        self.assert_shape_error('| `stringPerformed` | selector |  |  |', '| `stringPerformed` | selector |  |',
                                'with 4 cells, not 5')

    def test_a_name_cell_that_is_not_one_backticked_name_fails(self):
        self.assert_shape_error('| `stringPerformed` |', '| stringPerformed |', 'is not one backticked name')

    def test_a_classification_without_names_fails(self):
        self.assert_shape_error('  Names: `stringPerformed`.', '  Reach: `stringPerformed`.',
                                'classification with no Names line')

    def test_names_without_a_classification_fails(self):
        self.assert_shape_error('  **CLOSED.** A literal.', '  A literal.', 'Names line with no classification')

    def test_an_unknown_classification_fails(self):
        self.assert_shape_error('**CLOSED.** A literal.', '**SHUT.** A literal.', 'unknown classification SHUT')

    def test_a_names_line_with_nothing_backticked_fails(self):
        self.assert_shape_error('  Names: `iTermThingMO`.', '  Names: iTermThingMO.', 'neither')


class NameMatchTest(unittest.TestCase):
    def test_method_forms(self):
        m = ep.name_matches_method
        self.assertEqual(m('stringPerformed', 'C', 'stringPerformed'), 'exact name')
        self.assertIsNone(m('stringPerformed', 'C', 'stringPerformedLater'))
        self.assertEqual(m('contextMenuAction*', 'C', 'contextMenuActionOpen:'),
                         'selector prefix pattern contextMenuAction*')
        self.assertIsNone(m('contextMenuAction*', 'C', 'openContextMenuAction:'))
        self.assertEqual(m('iTermWidget +load_*', 'iTermWidget', 'load_x'),
                         'class method prefix pattern iTermWidget +load_*')
        self.assertIsNone(m('iTermWidget +load_*', 'Other', 'load_x'))
        self.assertEqual(m('iTermWidget.fooBar', 'iTermWidget', 'setFooBar:'),
                         'key-value coding key iTermWidget.fooBar')
        self.assertEqual(m('iTermWidget.fooBar', 'iTermWidget', 'fooBar'), 'key-value coding key iTermWidget.fooBar')
        self.assertIsNone(m('iTermWidget.fooBar', 'Other', 'fooBar'))
        self.assertIsNone(m('iTermWidget.fooBar', 'iTermWidget', 'barFoo'))

    def test_class_forms(self):
        self.assertEqual(ep.name_matches_class('iTermThingMO', 'iTermThingMO'), 'exact name')
        self.assertEqual(ep.name_matches_class('iTermWidget.fooBar', 'iTermWidget'),
                         'names a member of the class: iTermWidget.fooBar')
        self.assertEqual(ep.name_matches_class('iTermWidget +load_*', 'iTermWidget'),
                         'names a member of the class: iTermWidget +load_*')
        self.assertIsNone(ep.name_matches_class('iTermWidgetX', 'iTermWidget'))


# --- Files the compiler does not see --------------------------------------------

class InterfaceBuilderTest(unittest.TestCase):
    def test_xib(self):
        actions, outlets, classes, keyed = ep.parse_ib('sources/Main.xib', read('sources/Main.xib'))
        self.assertEqual([(a.line, a.col, a.selector, tuple(a.target)) for a in actions], [
            (14, 17, 'biggerFont:', ('first-responder', None, 'First Responder')),
            (19, 17, 'biggerFont:', ('files-owner', 'iTermWidget', "File's Owner (iTermWidget)")),
            (31, 17, 'go', ('object', 'iTermWidget', 'customView id=9 (iTerm2SharedARC.iTermWidget)')),
        ])
        self.assertEqual([(o.line, o.property, o.owner.cls, o.destination, o.collection) for o in outlets], [
            (6, 'button', 'iTermWidget', 'button id=7 (NSButton, from the element)', False),
            (7, 'delegate', 'iTermWidget', 'customView id=9 (iTerm2SharedARC.iTermWidget)', False),
            (32, 'delegate', 'NSTextField', 'customView id=9 (iTerm2SharedARC.iTermWidget)', False),
        ])
        self.assertEqual([(c.line, c.cls, c.module, c.desc) for c in classes], [
            (4, 'iTermWidget', None, "File's Owner (iTermWidget)"),
            (11, 'NSObject', None, 'Application (NSApp, of the principal class)'),
            (24, 'iTermWidget', 'iTerm2SharedARC', 'customView id=9 (iTerm2SharedARC.iTermWidget)'),
        ])
        self.assertEqual([(k.line, k.kind, k.key_path, k.name, k.target.cls) for k in keyed], [
            (20, 'binding', 'fooBar', 'value', 'iTermWidget'),
            (21, 'binding', 'model.fooBar', 'enabled', 'iTermWidget'),
            (26, 'runtime attribute', 'fooBar', None, 'iTermWidget'),
        ])

    def test_storyboard_first_responder_placeholder(self):
        actions, outlets, classes, keyed = ep.parse_ib('sources/Board.storyboard', read('sources/Board.storyboard'))
        self.assertEqual([(a.line, a.selector, a.target.kind) for a in actions],
                         [(8, 'contextMenuActionOpen:', 'first-responder')])
        self.assertEqual([(c.line, c.cls) for c in classes], [(6, 'iTermSubWidget'), (11, 'NSResponder')])

    def test_malformed_xml_raises(self):
        with self.assertRaises(ValueError):
            ep.parse_ib('x.xib', '<document><objects></document>')


class ScriptingAndPlistTest(unittest.TestCase):
    def test_sdef(self):
        items = ep.parse_sdef('iTerm2.sdef', read('iTerm2.sdef'))
        self.assertEqual([tuple(i)[1:] for i in items], [
            (5, 'class', 'widget', 'iTermWidget', 'widget', None, None),
            (7, 'property', 'widget', 'iTermWidget', 'foo bar', 'fooBar', 'rw'),
            (8, 'property', 'widget', 'iTermWidget', 'tty', 'button', 'r'),
            (11, 'element', 'widget', 'iTermWidget', 'widget', 'subWidgets', 'rw'),
            (14, 'responds-to', 'widget', 'iTermWidget', 'enlarge', 'biggerFont:', None),
            (18, 'command', None, 'iTermSubWidget', 'enlarge', None, None),
            (21, 'class', 'window', 'iTermScriptingWindow', 'window', None, None),
            (23, 'property', 'window', 'iTermScriptingWindow', 'frontmost', 'scriptFrontmost', 'r'),
            (26, 'responds-to', 'window', 'iTermScriptingWindow', 'select', 'handleSelectCommand:', None),
        ])

    def test_sdef_accessors(self):
        items = ep.parse_sdef('iTerm2.sdef', read('iTerm2.sdef'))
        self.assertEqual(ep.sdef_accessors(items[1]), ['fooBar', 'setFooBar:'])
        self.assertEqual(ep.sdef_accessors(items[2]), ['button'])
        self.assertIn('insertObject:inSubWidgetsAtIndex:', ep.sdef_accessors(items[3]))
        self.assertIn('valueInSubWidgetsWithUniqueID:', ep.sdef_accessors(items[3]))

    def test_a_read_only_element_reaches_every_scripting_accessor(self):
        items = ep.parse_sdef('x.sdef', '<dictionary><suite><class name="window" code="w"><cocoa class="W"/>'
                              '<element type="tab" access="r"><cocoa key="tabs"/></element></class></suite>'
                              '</dictionary>')
        accessors = ep.sdef_accessors(items[1])
        for sel in ('tabs', 'countOfTabs', 'valueInTabsAtIndex:', 'objectInTabsAtIndex:', 'setTabs:',
                    'removeFromTabsAtIndex:', 'replaceInTabs:atIndex:', 'insertInTabs:atIndex:', 'insertInTabs:'):
            self.assertIn(sel, accessors)

    def test_class_name_defaults_to_the_capitalized_sdef_name(self):
        items = ep.parse_sdef('x.sdef', '<dictionary><suite><class name="tab session" code="x"/></suite></dictionary>')
        self.assertEqual(items[0].cocoa_class, 'TabSession')

    def test_xml_and_binary_plists(self):
        data = read('plists/Info.plist').encode('utf-8')
        expected = [('principal class', 'iTermWidget', 5), ('services message', 'openThing:userData:error:', 11),
                    ('document class', 'iTermSubWidget', 18)]
        self.assertEqual([(p.kind, p.value, p.line) for p in ep.parse_plist('plists/Info.plist', data)], expected)
        import plistlib
        binary = plistlib.dumps(plistlib.loads(data), fmt=plistlib.FMT_BINARY)
        self.assertEqual([(p.kind, p.value, p.line) for p in ep.parse_plist('b.plist', binary)],
                         [(k, v, 0) for k, v, _ in expected])
        with self.assertRaises(ValueError):
            ep.parse_plist('bad.plist', b'<plist><dict><key>x</key></plist>')

    def test_pbxproj_principal_class(self):
        self.assertEqual([tuple(p) for p in ep.parse_pbxproj('App.xcodeproj/project.pbxproj',
                                                              read('App.xcodeproj/project.pbxproj'))],
                         [('App.xcodeproj/project.pbxproj', 4, 'Info.plist build setting', 'iTermWidget')])

    def test_core_data(self):
        path = 'Model.xcdatamodeld/Model.xcdatamodel/contents'
        self.assertEqual([tuple(c)[1:] for c in ep.parse_coredata(path, read(path))], [
            (3, 'entity', 'Thing', 'iTermThingMO', 'Thing'),
            (4, 'attribute', 'Thing', 'iTermThingMO', 'thingName'),
        ])


class ResourcesTest(unittest.TestCase):
    def setUp(self):
        files = []
        for d, _, names in os.walk(FIXTURE):
            files += [os.path.relpath(os.path.join(d, n), FIXTURE) for n in names]
        self.res = ep.Resources(FIXTURE, sorted(files))

    def test_files_read(self):
        self.assertEqual(dict(self.res.counts), {'ib': 4, 'sdef': 1, 'plist': 1, 'coredata': 1, 'pbxproj': 2})
        self.assertEqual(self.res.problems, [])
        self.assertEqual(sorted(self.res.text_files), ['OtherResources/actions.json', 'api/script.py',
                                                       'plists/Info.plist'])

    def test_text_search_is_by_whole_token(self):
        hits = self.res.text_search(['biggerFont:', 'stringPerformed', 'macroCalled', 'iTermWidget'])
        self.assertEqual(sorted((k, [(h.file, h.line) for h in v]) for k, v in hits.items()), [
            ('biggerFont:', [('api/script.py', 1), ('api/script.py', 2)]),
            ('iTermWidget', [('OtherResources/actions.json', 1), ('plists/Info.plist', 5)]),
            ('stringPerformed', [('OtherResources/actions.json', 1)]),
        ])

    def test_a_plist_that_cannot_be_parsed_is_a_note_and_still_searched_as_text(self):
        d = harness.make_temp()
        with open(os.path.join(d, 'Bad.plist'), 'w') as f:
            f.write('<plist><dict><key>x</key><string>stringPerformed\x01</string></dict></plist>\n')
        res = ep.Resources(d, ['Bad.plist'])
        self.assertEqual(res.problems, [])
        self.assertEqual(len(res.notes), 1)
        self.assertTrue(res.notes[0][1].startswith('not a property list Python can read ('))
        self.assertEqual([(h.file, h.line) for h in res.text_search(['stringPerformed'])['stringPerformed']],
                         [('Bad.plist', 1)])

    def test_a_malformed_file_is_a_problem(self):
        d = harness.make_temp()
        os.makedirs(os.path.join(d, 'sources'))
        with open(os.path.join(d, 'sources', 'Bad.xib'), 'w') as f:
            f.write('<document>')
        res = ep.Resources(d, ['sources/Bad.xib'])
        self.assertEqual(len(res.problems), 1)
        self.assertTrue(res.problems[0][1].startswith('not well-formed XML'))


# --- The database-backed census ------------------------------------------------

def census_args(root, paths):
    return ['--root', root, '--db', paths.db, '--cdb', paths.cdb, '--fragments', paths.fragments, '--swift-work',
            paths.swift_work, '--swift-reader', paths.swift_reader, '--extractor', paths.extractor]


def section(d, n):
    return next(s for s in d['sections'] if s['number'] == n)


def rows(d, n, informational=False):
    """(location, what, marks) of section n's rows, without the informational
    ones unless asked."""
    return [(ep.loc(r), r['what']) + ((tuple(r['marks']),) if r['marks'] else ())
            for r in section(d, n)['rows'] if informational or not r.get('informational')]


def groups(d, n):
    return [r.get('group') for r in section(d, n)['rows']]


class DatabaseTest(unittest.TestCase):
    """One fixture database for the class; subclasses that change it build
    their own."""
    edit = None
    swift = True
    sdk_table = True
    pp_skipped = True

    @classmethod
    def setUpClass(cls):
        cls.root, cls.paths = harness.build(swift=cls.swift, edit=cls.edit, sdk_table=cls.sdk_table,
                                            pp_skipped=cls.pp_skipped)

    def run_json(self, *argv):
        out = io.StringIO()
        status = ep.main(census_args(self.root, self.paths) + ['--json'] + list(argv), out=out)
        return status, json.loads(out.getvalue())

    def run_text(self, *argv):
        out = io.StringIO()
        status = ep.main(census_args(self.root, self.paths) + list(argv), out=out)
        return status, out.getvalue()

    def method(self, selector, cls='iTermWidget'):
        status, d = self.run_json('method', cls, selector)
        self.assertEqual(status, d['exit_status'])
        return status, d


class MethodTest(DatabaseTest):
    def test_ib_action_to_first_responder_and_files_owner_with_objc_callers(self):
        status, d = self.method('biggerFont:')
        self.assertEqual((status, d['complete'], d['subject']), (0, True, '-[iTermWidget biggerFont:]'))
        self.assertEqual(rows(d, 1), [
            ('ThirdParty/Other/Other.m:4:13', 'OtherCaller  receiver iTermWidget *  targets App',
             ("outside the migration's scope",)),
            ('ThirdParty/PSMTabBarControl/PSM.m:4:12', 'PSMCaller  receiver id  targets App'),
            ('sources/Widget.m:18:11', '-[iTermWidget go]  receiver iTermWidget *  targets App'),
            ('sources/Widget.m:65:12', '-[iTermSubWidget biggerFont:]  super send (receiver iTermWidget *)  targets '
             'App'),
        ])
        self.assertIn('Message sends are matched by selector, not by receiver type', section(d, 1)['notes'][0])
        self.assertEqual(section(d, 1)['notes'][1],
                         'static receiver type iTermWidget: 3; another type, id, or a protocol: 1')
        self.assertEqual(rows(d, 5), [
            ('Demo/MainMenu.xib:7:17', 'action biggerFont:, target First Responder: any object in the responder '
             'chain that implements biggerFont: can receive it, not only iTermWidget',
             ('in a directory built by another Xcode project (Demo/Demo.xcodeproj)',)),
            ('sources/Main.xib:14:17', 'action biggerFont:, target First Responder: any object in the responder '
             'chain that implements biggerFont: can receive it, not only iTermWidget'),
            ('sources/Main.xib:19:17', "action biggerFont:, target File's Owner (iTermWidget): target is this class"),
        ])
        self.assertEqual(rows(d, 6), [
            ('iTerm2.sdef:14', 'sdef responds-to command "enlarge" of class "widget": method biggerFont:'),
            ('api/script.py:1', 'text: the token biggerFont:'),
            ('api/script.py:2', 'text: the token biggerFont:'),
        ])
        self.assertEqual(groups(d, 6), ['sdef', 'other resources (text search, unverified)',
                                        'other resources (text search, unverified)'])
        self.assertEqual(rows(d, 7, informational=True), [
            ('sources/Widget.m:14', '-[iTermWidget biggerFont:] implemented here (implementation)'),
            ('sources/Widget.m:64:13', '-[iTermSubWidget biggerFont:] overrides it'),
        ])
        self.assertEqual(rows(d, 4, informational=True), [OPEN_SITE])
        self.assertEqual(rows(d, 9), [
            ('ModernTests/WidgetTests.swift:2', 'the selector as a string literal "biggerFont:" (text search, '
             'unverified)')])
        self.assertEqual(groups(d, 9), ['3. Selector references that are not calls: string literals naming the '
                                        'selector (text search)'])
        self.assertEqual((rows(d, 2), rows(d, 3), rows(d, 8), rows(d, 10)), ([], [], [], []))

    def test_every_section_is_present_and_complete(self):
        status, d = self.method('biggerFont:')
        self.assertEqual([(s['number'], s['title'], s['complete']) for s in d['sections']],
                         [(n, t, True) for n, t in ep.SECTION_TITLES.items()])
        self.assertEqual(d['incomplete'], [])

    def test_not_covered_is_stated(self):
        status, d = self.method('biggerFont:')
        notes = section(d, 10)['notes']
        self.assertIn('Not parsed: callers in these files are NOT in this database', notes)
        self.assertIn('  (b) under submodules/: 1', notes)
        self.assertIn('Swift files in the repository that no captured module compiles (not in this database): 1 '
                      '(ModernTests 1)', notes)
        for item in ep.NOT_COVERED_ALWAYS:
            self.assertIn('not covered: ' + item, notes)

    def test_wired_to_an_object_called_only_from_tests_and_by_selector_from_swift(self):
        status, d = self.method('go')
        self.assertEqual(status, 0)
        self.assertEqual(rows(d, 1), [])
        self.assertEqual([n for n in section(d, 1)['notes'][1:] if not n.startswith('Objective-C code that is not '
                                                                                   'compiled')], [])
        self.assertEqual(rows(d, 9), [
            ('ModernTests/WidgetTests.m:4:13', 'WidgetTest  receiver iTermWidget *  targets ModernTests',
             ("outside the migration's scope",))])
        self.assertEqual(groups(d, 9), ['1. Objective-C callers'])
        self.assertEqual(rows(d, 3), [
            ('sources/Widget.m:81:36', 'Registrar  @selector(go)  probably passed to sendAction:to: (a send that '
             'takes a selector, in the same function, starting on this line or up to 20 lines above; the database '
             'records no argument link): target-action  targets App'),
            ('sources/Panel.swift:8:52', 'iTermPanel.show(_:)  #selector (method) -[iTermWidget go]  module Fix  '
             'passed to initWithTitle:action:keyEquivalent:: menu item creation')])
        self.assertEqual(rows(d, 2), [
            ('sources/Panel.swift:11', 'text match go in a #if clause at lines 11-11 that is not compiled')])
        self.assertEqual(rows(d, 5), [
            ('sources/Main.xib:31:17', 'action go, target customView id=9 (iTerm2SharedARC.iTermWidget): target is '
             'this class')])
        self.assertEqual([r for r in rows(d, 7, informational=True) if 'PSMThing' in r[1]], [
            ('ThirdParty/PSMTabBarControl/PSM.m:16', '-[PSMThing go] also implements the selector: a send, '
             '#selector or xib action matched by selector may reach it instead')])
        self.assertEqual(groups(d, 7), ['where it is defined', 'other implementers of the selector'])

    def test_called_only_from_swift_under_a_renamed_import(self):
        status, d = self.method('swiftOnlyCalled')
        self.assertEqual(status, 0)
        self.assertEqual(rows(d, 1), [])
        self.assertEqual(rows(d, 2), [
            ('sources/Panel.swift:6:16', 'iTermPanel.show(_:)  call -[iTermWidget swiftOnlyCalled]  receiver '
             'iTermWidget  module Fix')])

    def test_property_setter_written_from_swift_objc_kvc_ib_and_sdef(self):
        status, d = self.method('setFooBar:')
        self.assertEqual(rows(d, 1), [
            ('sources/Widget.m:24:10', '-[iTermWidget go]  receiver iTermWidget *  dot-syntax accessor  targets App')])
        self.assertEqual(rows(d, 2), [
            ('sources/Panel.swift:7:16', 'iTermPanel.show(_:)  property reference property iTermWidget.fooBar, '
             'access set  module Fix')])
        self.assertEqual(rows(d, 3), [
            ('sources/Widget.m:25:11', '-[iTermWidget go]  setValue:forKey: argument 1 (key): string-literal '
             '"fooBar"  receiver iTermWidget *  targets App')])
        self.assertEqual(rows(d, 5), [
            ('sources/Main.xib:20:17', "binding fooBar (binding value) on File's Owner (iTermWidget)"),
            ('sources/Main.xib:21:17', 'possible: binding model.fooBar names the key fooBar past its first '
             "component, on an object whose class is not known; on File's Owner (iTermWidget)"),
            ('sources/Main.xib:26:17', 'runtime attribute fooBar on customView id=9 (iTerm2SharedARC.iTermWidget)'),
        ])
        self.assertEqual(rows(d, 6), [
            ('iTerm2.sdef:7', 'sdef property "foo bar" of class "widget", key fooBar (access rw): scripting reaches '
             'setFooBar: through key-value coding')])
        self.assertEqual(rows(d, 4), [
            (REG + ':20', 'names table: iTermWidget.fooBar (key-value coding key iTermWidget.fooBar)  resolves: '
             'property  sites: sources/Widget.m:26'),
            (REG + ':62', 'section 5 entry CLOSED: A key. (key-value coding key iTermWidget.fooBar)  site: '
             'sources/Widget.m:26 in -[iTermWidget go]'),
        ])

    def test_read_only_sdef_property_reaches_only_the_getter(self):
        self.assertEqual(rows(self.method('button')[1], 6), [
            ('iTerm2.sdef:8', 'sdef property "tty" of class "widget", key button (access r): scripting reaches '
             'button through key-value coding')])
        self.assertEqual(rows(self.method('setButton:')[1], 6), [])
        self.assertEqual(rows(self.method('setButton:')[1], 5), [
            ('sources/Main.xib:6:17', "outlet button on File's Owner (iTermWidget), destination button id=7 "
             '(NSButton, from the element): set with key-value coding when the nib loads; keep a settable property '
             'of that name')])

    def test_selector_in_a_timer_and_a_notification_registration(self):
        self.assertEqual(rows(self.method('timerFired:')[1], 3), [
            ('sources/Widget.m:19:78', '-[iTermWidget go]  @selector(timerFired:)  passed to '
             'scheduledTimerWithTimeInterval:target:selector:userInfo:repeats: (argument 2): timer  targets App')])
        self.assertEqual(rows(self.method('noteChanged:')[1], 3), [
            ('sources/Widget.m:20:79', '-[iTermWidget go]  @selector(noteChanged:)  passed to '
             'addObserver:selector:name:object: (argument 1): notification registration  targets App')])

    def test_perform_selector_with_a_literal_and_by_name(self):
        status, d = self.method('performedOnly')
        self.assertEqual(rows(d, 3), [
            ('sources/Widget.m:21:37', '-[iTermWidget go]  @selector(performedOnly)  passed to performSelector: '
             '(argument 0): performSelector family  targets App')])
        self.assertEqual(rows(d, 10), [
            ('submodules/sub/Sub.m:2', 'text match (message send) in a file that is not parsed: void SubCaller(id '
             'widget) { [widget performedOnly]; }')])
        status, d = self.method('stringPerformed')
        # A send in a header that an app unit and a test unit both read is an app caller, not a test.
        self.assertEqual(rows(d, 1), [
            ('sources/Widget.h:35:8', 'WidgetInline  receiver iTermWidget *  targets App,ModernTests')])
        self.assertEqual(rows(d, 9), [])
        self.assertEqual(rows(d, 3), [
            ('sources/Widget.m:22:11', '-[iTermWidget go]  performSelector: argument 0 (selector): string-literal '
             '"stringPerformed"  receiver iTermWidget *  performSelector family  targets App'),
            ('sources/Widget.m:22:27', '-[iTermWidget go]  NSSelectorFromString argument 0 (selector): '
             'string-literal "stringPerformed"  targets App'),
        ])
        self.assertEqual(rows(d, 4), [
            (REG + ':21', 'names table: stringPerformed (exact name)  resolves: selector  sites: sources/Widget.m:23'),
            (REG + ':44', 'section 3 entry CLOSED: A literal. (exact name)  site: sources/Widget.m:23 in '
             '-[iTermWidget go]'),
        ])
        self.assertEqual(rows(d, 6), [('OtherResources/actions.json:1', 'text: the token stringPerformed')])
        self.assertNotIn('string literals naming the selector (text search)', groups(d, 3))

    def test_called_inside_a_macro(self):
        status, d = self.method('macroCalled')
        self.assertEqual(rows(d, 1), [
            ('sources/Widget.m:23:5', '-[iTermWidget go]  receiver iTermWidget *  macro CALL_IT body (defined '
             'sources/Widget.m:3, used at 23:5)  targets App')])
        self.assertEqual(rows(d, 6), [])
        self.assertEqual(rows(d, 9), [
            ('ModernTests/WidgetTests.m:8', 'the selector as a string literal "macroCalled" (text search, '
             'unverified)')])

    def test_registry_prefix_pattern_and_a_storyboard_first_responder_action(self):
        status, d = self.method('contextMenuActionOpen:')
        self.assertEqual(rows(d, 4), [
            (REG + ':17', 'names table: contextMenuAction* (selector prefix pattern contextMenuAction*)  resolves: 1 '
             'selectors with prefix  note: selector prefix pattern (Widget.m:1)  sites: sources/Widget.m:1'),
            (REG + ':56', 'section 5 entry CLOSED: Enabled by prefix. (selector prefix pattern contextMenuAction*)  '
             'site: sources/Widget.m:1 in -[iTermWidget validateMenuItem:]'),
        ])
        self.assertEqual(rows(d, 3), [
            ('sources/Widget.m:76:38', 'MenuMaker  @selector(contextMenuActionOpen:)  passed to '
             'addItemWithTitle:action:keyEquivalent: (argument 1): menu item creation  targets App')])
        self.assertEqual(rows(d, 5), [
            ('sources/Board.storyboard:8:25', 'action contextMenuActionOpen:, target First Responder: any object in '
             'the responder chain that implements contextMenuActionOpen: can receive it, not only iTermWidget')])

    def test_delegate_method_called_by_appkit_only(self):
        status, d = self.method('windowDidResize:')
        self.assertEqual(status, 0)
        self.assertEqual([r for n in range(1, 7) for r in rows(d, n)], [])
        self.assertEqual(rows(d, 7), [
            ('sources/Widget.m:11:9', 'satisfies NSWindowDelegate -windowDidResize: (optional), declared in the SDK '
             '(System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWindow.h): code outside this database '
             '(AppKit, Foundation) calls it'),
            ('sources/Widget.m:11', 'selector declared by the SDK: NSWindowDelegate (protocol, AppKit, optional); '
             'overrides or implements an inherited SDK member: the system may call it')])
        self.assertEqual(groups(d, 7), ['where it is defined', 'outside the repository',
                                        'other implementers of the selector', 'declared by the SDK'])

    def test_awake_from_nib_and_its_super_send(self):
        status, d = self.method('awakeFromNib')
        self.assertEqual(rows(d, 1), [
            ('sources/Widget.m:8:12', '-[iTermWidget awakeFromNib]  super send (receiver NSView *)  targets App')])
        self.assertEqual(rows(d, 7)[0][1].split(':')[0],
                         'overrides NSObject(NSNibAwaking) -awakeFromNib, declared in the SDK '
                         '(System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSNibLoading.h)')

    def test_informal_protocol_method(self):
        status, d = self.method('widgetDidChange:')
        self.assertEqual(rows(d, 1), [
            ('sources/Widget.m:27:15', '-[iTermWidget go]  receiver id<iTermWidgetDelegate>  targets App')])
        self.assertEqual(rows(d, 7), [
            ('sources/Widget.h:5', 'protocol iTermWidgetDelegate declares widgetDidChange:: a holder of a '
             'iTermWidgetDelegate reference calls it through the protocol, whether or not iTermWidget declares '
             'conformance')])

    def test_appkit_protocol_method_of_a_class_that_does_not_declare_the_protocol(self):
        status, d = self.method('windowDidResize:', cls='PSMThing')
        self.assertEqual(status, 0)
        self.assertEqual(rows(d, 7), [
            ('ThirdParty/PSMTabBarControl/PSM.m:18', 'windowDidResize: is a requirement of NSWindowDelegate, a '
             'protocol declared outside the repository that other classes here adopt (first: iTermWidget at '
             'sources/Widget.m:11): AppKit calls it on an object it uses as a NSWindowDelegate, even if PSMThing '
             'does not declare the protocol'),
            ('ThirdParty/PSMTabBarControl/PSM.m:18', 'selector declared by the SDK: NSWindowDelegate (protocol, '
             'AppKit, optional); declared by an SDK protocol the class does not formally adopt: the system may '
             'call it')])

    def test_possible_appkit_delegate_method(self):
        status, d = self.method('comboBoxSelectionDidChange:', cls='PSMThing')
        self.assertEqual(status, 0)
        self.assertEqual(rows(d, 7), [
            ('ThirdParty/PSMTabBarControl/PSM.m:21:9', 'possible: -[PSMThing setUp:] makes this object the delegate '
             'of a NSComboBox (setDelegate:), and comboBoxSelectionDidChange: begins with comboBox, as that '
             "class's delegate methods do: AppKit may call it"),
            ('ThirdParty/PSMTabBarControl/PSM.m:23', 'selector declared by the SDK: NSComboBoxDelegate (protocol, '
             'AppKit, optional); declared by an SDK protocol the class does not formally adopt: the system may '
             'call it')])

    def test_services_message(self):
        self.assertEqual(rows(self.method('openThing:userData:error:')[1], 6), [
            ('plists/Info.plist:11', 'NSServices message openThing:userData:error:: sent to the services provider '
             '(the object passed to setServicesProvider: in code)')])

    def test_no_callers_at_all_exits_1_and_complete(self):
        status, d = self.method('neverCalled')
        self.assertEqual((status, d['complete'], d['found']), (1, True, 0))
        self.assertEqual(rows(d, 4, informational=True), [OPEN_SITE])

    def test_class_method_choice_and_an_unknown_selector(self):
        status, d = self.method('+go')
        self.assertEqual(d['subject'], '+[iTermWidget go]')
        self.assertEqual(rows(d, 7, informational=True), [])
        self.assertIn('iTermWidget has no recorded declaration or definition of go', section(d, 7)['notes'][0])

    def test_bad_arguments_exit_2(self):
        out = io.StringIO()
        self.assertEqual(ep.main(census_args(self.root, self.paths) + ['method', 'iTermWidget', 'not a selector'],
                                 out=out), 2)
        self.assertEqual(ep.main(census_args(self.root, self.paths) + ['method', 'iTerm-Widget', 'go'], out=out), 2)

    def test_text_output_has_every_section_and_the_exit_rule(self):
        status, text = self.run_text('method', 'iTermWidget', 'biggerFont:')
        self.assertEqual(status, 0)
        self.assertTrue(text.startswith('Entry points of -[iTermWidget biggerFont:]\n'))
        for n, title in ep.SECTION_TITLES.items():
            self.assertIn('\n%d. %s: ' % (n, title), text)
        self.assertIn('\n5. Interface Builder: 3 (xibs and storyboards, parsed as XML (4 files); complete)\n', text)
        self.assertIn('\n4. Reflective reach (the registry): 0 and 1 informational (', text)
        self.assertIn('exit status 0: 0 found and complete, 1 nothing found and complete', text)


class ClassTest(DatabaseTest):
    def table(self, d):
        return dict((m['method'], m) for m in d['methods'])

    def test_class_facts(self):
        status, d = self.run_json('class', 'iTermWidget')
        # An NSView subclass with a candidate (-neverCalled), and no runtime method list.
        self.assertEqual(status, 3)
        self.assertEqual(d['incomplete'], [ep.NO_RUNTIME_INCOMPLETE % 1])
        facts = d['sections'][0]
        got = [(r.get('group'), ep.loc(r), r['what']) for r in facts['rows']]
        self.assertEqual(got, [
            ('declared and defined in Objective-C', 'sources/Widget.h', 'category iTermWidget(Declared)'),
            ('declared and defined in Objective-C', 'sources/Widget.h', 'implementation iTermWidget'),
            ('declared and defined in Objective-C', 'sources/Widget.h', 'interface iTermWidget'),
            ('declared and defined in Objective-C', 'sources/Widget.m', 'implementation iTermWidget'),
            ('Interface Builder custom class', 'sources/Main.xib:4:9', "customClass on File's Owner (iTermWidget)"),
            ('Interface Builder custom class', 'sources/Main.xib:24:9', 'customClass on customView id=9 '
             '(iTerm2SharedARC.iTermWidget), customModule iTerm2SharedARC'),
            ('Interface Builder outlets owned by this class', 'sources/Main.xib:6:17', "outlet button on File's Owner "
             '(iTermWidget), destination button id=7 (NSButton, from the element)'),
            ('Interface Builder outlets owned by this class', 'sources/Main.xib:7:17', "outlet delegate on File's "
             'Owner (iTermWidget), destination customView id=9 (iTerm2SharedARC.iTermWidget)'),
            ('Interface Builder actions targeting this class', 'sources/Main.xib:19:17', "action biggerFont:, target "
             "File's Owner (iTermWidget)"),
            ('Interface Builder actions targeting this class', 'sources/Main.xib:31:17', 'action go, target '
             'customView id=9 (iTerm2SharedARC.iTermWidget)'),
            ('Interface Builder bindings and runtime attributes', 'sources/Main.xib:20:17', "binding fooBar on File's "
             'Owner (iTermWidget)'),
            ('Interface Builder bindings and runtime attributes', 'sources/Main.xib:21:17', 'binding model.fooBar on '
             "File's Owner (iTermWidget)"),
            ('Interface Builder bindings and runtime attributes', 'sources/Main.xib:26:17', 'runtime attribute fooBar '
             'on customView id=9 (iTerm2SharedARC.iTermWidget)'),
            ('Interface Builder delegate and data source connections', 'sources/Main.xib:7:17', "delegate of File's "
             'Owner (iTermWidget)'),
            ('Interface Builder delegate and data source connections', 'sources/Main.xib:32:17', 'delegate of '
             'textField id=11 (NSTextField, from the element)'),
            ('sdef', 'iTerm2.sdef:5', 'sdef class "widget"'),
            ('property lists', 'App.xcodeproj/project.pbxproj:4', 'Info.plist build setting (text search)'),
            ('property lists', 'plists/Info.plist:5', 'principal class'),
            ('registry', REG + ':19', 'names table: iTermWidget +load_* (names a member of the class: iTermWidget '
             '+load_*)  sites: sources/Widget.m:2'),
            ('registry', REG + ':20', 'names table: iTermWidget.fooBar (names a member of the class: '
             'iTermWidget.fooBar)  sites: sources/Widget.m:26'),
            ('registry', REG + ':62', 'section 5 entry CLOSED: A key.  site: sources/Widget.m:26 in -[iTermWidget '
             'go]'),
            ('subclasses in the repository', 'sources/Widget.m', 'subclass iTermSubWidget, direct or indirect '
             '(overrides at least one method)'),
            ('other resources (text search, unverified)', 'OtherResources/actions.json:1', 'text: the token '
             'iTermWidget'),
            ('other resources (text search, unverified)', 'plists/Info.plist:5', 'text: the token iTermWidget'),
        ])

    def test_subclass_and_command_class_and_document_class(self):
        status, d = self.run_json('class', 'iTermSubWidget')
        got = [(r.get('group'), ep.loc(r), r['what']) for r in d['sections'][0]['rows']]
        self.assertIn(('Interface Builder custom class', 'sources/Board.storyboard:6:17',
                       'customClass on viewController id=vc1 (iTermSubWidget)'), got)
        self.assertIn(('sdef', 'iTerm2.sdef:18', 'sdef command "enlarge"'), got)
        self.assertIn(('property lists', 'plists/Info.plist:18', 'document class'), got)
        status, d = self.run_json('class', 'iTermWidget')
        self.assertIn(('subclasses in the repository', 'sources/Widget.m',
                       'subclass iTermSubWidget, direct or indirect (overrides at least one method)'),
                      [(r.get('group'), ep.loc(r), r['what']) for r in d['sections'][0]['rows']])
        status, d = self.run_json('class', 'NSObject')
        self.assertIn(('subclasses in the repository', 'sources/Widget.m',
                       'subclass iTermWidget, direct or indirect (overrides at least one method)'),
                      [(r.get('group'), ep.loc(r), r['what']) for r in d['sections'][0]['rows']])

    def test_method_table(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermWidget')
        t = self.table(d)
        self.assertEqual(sorted(t), ['-awakeFromNib', '-biggerFont:', '-button', '-contextMenuActionOpen:',
                                     '-declaredOnly', '-fooBar',
                                     '-go', '-macroCalled', '-neverCalled', '-noteChanged:',
                                     '-openThing:userData:error:', '-performedOnly', '-setButton:', '-setFooBar:',
                                     '-stringPerformed', '-swiftOnlyCalled', '-timerFired:', '-widgetDidChange:',
                                     '-windowDidResize:'])

        def summary(name):
            m = t[name]
            return (m['objc'], m['swift'], m['selector_refs'], m['by_name'], m['kvc'], m['registry'], m['ib'],
                    m['scripting'], m['text'], m['tests'], m['flags'])
        self.assertEqual(summary('-biggerFont:'), (4, 0, 0, 0, 0, 0, 2, 1, 2, 0, ['IB', 'scripting']))
        self.assertEqual(summary('-go'), (0, 0, 2, 0, 0, 0, 1, 0, 2, 1, ['IB', 'selector referenced without a call']))
        self.assertEqual(summary('-setFooBar:'), (1, 1, 0, 0, 1, 1, 2, 1, 0, 0,
                                                  ['IB', 'scripting', 'registry', 'property accessor']))
        self.assertEqual(summary('-swiftOnlyCalled'), (0, 1, 0, 0, 0, 0, 0, 0, 0, 0, []))
        self.assertEqual(summary('-stringPerformed'), (1, 0, 0, 1, 0, 1, 0, 0, 1, 0, ['registry']))
        self.assertEqual(summary('-windowDidResize:'), (0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                                        ['outside-repository override',
                                                         'selector declared by the SDK']))
        self.assertEqual(summary('-openThing:userData:error:'), (0, 0, 0, 0, 0, 0, 0, 1, 0, 0, ['scripting']))
        self.assertEqual(summary('-neverCalled'), (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ['no caller found']))
        self.assertEqual(summary('-declaredOnly'), (0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
                                                    ['declared only (no definition recorded)',
                                                     'called only from tests']))

    def test_informal_appkit_delegate_methods_are_reached(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'PSMThing')
        flags = dict((m['method'], (m['no_caller'], m['flags'])) for m in d['methods'])
        self.assertEqual(flags, {
            '-go': (False, ['selector referenced without a call']),
            '-windowDidResize:': (False, ['requirement of an outside-repository protocol (not declared by this '
                                          'class)', 'selector declared by the SDK']),
            '-comboBoxSelectionDidChange:': (False, ['possible AppKit delegate method',
                                                     'selector declared by the SDK']),
            '-setUp:': (True, ['no caller found']),
        })

    def test_unreached(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermWidget', '--unreached')
        self.assertEqual(status, 3)
        self.assertEqual(d['incomplete'], [rt_reason(harness.RUNTIME_FIXTURE)])
        self.assertEqual([m['method'] for m in d['methods']], ['-neverCalled'])
        self.assertEqual([m['method'] for m in d['tests']], ['-declaredOnly'])
        self.assertEqual(d['label'], 'no caller found (not "dead": see Not covered)')
        self.assertIn('not covered: ' + ep.NOT_COVERED_ALWAYS[0], d['sections'][1]['notes'])
        status, text = self.run_text('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermWidget', '--unreached')
        self.assertIn('Methods with no caller found (not "dead": see Not covered): 1\n', text)
        self.assertNotIn(' dead', text.replace('"dead"', ''))

    def test_swift_class_and_file_mode(self):
        # decisions.md 2026-11-20: "no caller found" needs a runtime method list.
        status, docs = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'file', 'sources/Panel.swift')
        self.assertEqual([x['subject'] for x in docs], ['Inner', 'iTermPanel', 'iTermPanelHost', 'iTermSwiftCaller',
                                                        'iTermSwiftWobbler'])
        d = docs[1]
        got = [(r.get('group'), ep.loc(r), r['what']) for r in d['sections'][0]['rows']]
        self.assertEqual(got, [
            ('declared in Swift (Swift class, or a Swift extension of an Objective-C class)', 'sources/Panel.swift',
             'Swift declarations visible to Objective-C: 3 (module Fix)'),
            ('Swift @objc name (text search of the declaring file)', 'sources/Panel.swift:3',
             'Swift class Panel with runtime name iTermPanel (@objc(iTermPanel))'),
            # The real forwarding table names iTermPanel, the runtime name of this fixture class too.
            ('sdef', 'iTerm2.sdef:21', 'sdef class "window", through its cocoa class iTermScriptingWindow, which '
             'forwards to this class'),
        ])
        self.assertEqual([(m['method'], m['flags']) for m in d['methods']], [
            ('-init', ['outside-repository override', 'selector declared by the SDK']),
            ('-show:', ['no caller found']), ('-unusedPanelMethod', ['no caller found'])])
        status, docs = self.run_json('file', 'sources/Widget.m')
        # iTermThingMO's @implementation is empty: the database records methods, not classes, so a class with no
        # method is not found in its file (a known limit).
        self.assertEqual([x['subject'] for x in docs], ['iTermSubWidget', 'iTermWidget'])

    def test_core_data_class_and_registry_section_6(self):
        status, d = self.run_json('class', 'iTermThingMO')
        got = [(r.get('group'), ep.loc(r), r['what']) for r in d['sections'][0]['rows']]
        self.assertEqual(got, [
            ('Core Data', 'Model.xcdatamodeld/Model.xcdatamodel/contents:3', 'Core Data entity Thing'),
            ('registry', REG + ':18', 'names table: iTermThingMO (exact name)  runtime name iTermThingMO  sites: '
             'sources/Widget.m:70'),
            ('registry', REG + ':72', 'section 6 entry OPEN-EXTERNAL: Saved by name.  site: sources/Widget.m:70'),
        ])

    def test_unknown_file_is_an_error(self):
        status, text = self.run_text('file', 'sources/Nothing.m')
        self.assertEqual(status, 2)


# --- Completeness ------------------------------------------------------------------

class StaleUnitTest(DatabaseTest):
    def test_a_changed_source_makes_every_answer_incomplete(self):
        with open(os.path.join(self.root, 'sources', 'Widget.m'), 'a') as f:
            f.write('// edited after extraction\n')
        status, d = self.method('biggerFont:')
        self.assertEqual((status, d['complete']), (3, False))
        self.assertTrue(any(line.startswith('INCOMPLETE: 1 of 6 units are not current') for line in d['incomplete']))
        self.assertFalse(section(d, 1)['complete'])
        self.assertIn('STALE (input changed: sources/Widget.m)', rows(d, 1)[2][2])
        status, d = self.method('neverCalled')
        self.assertEqual(status, 3)
        status, text = self.run_text('method', 'iTermWidget', 'neverCalled')
        self.assertTrue(text.startswith('INCOMPLETE: '))
        self.assertTrue(text.rstrip('\n').split('\n')[-1].startswith('INCOMPLETE: '))
        status, d = self.run_json('class', 'iTermWidget', '--unreached')
        self.assertEqual(status, 3)


class RegistryBehindTest(DatabaseTest):
    @staticmethod
    def edit(root):
        path = os.path.join(root, REG)
        with open(path) as f:
            text = f.read()
        start = text.index('#### `ThirdParty/PSMTabBarControl/PSM.m`')
        end = text.index('#### `sources/Widget.m`')
        with open(path, 'w') as f:
            f.write(text[:start] + text[end:])

    def test_a_dynamic_site_missing_from_the_registry_makes_sections_4_and_8_incomplete(self):
        status, d = self.method('stringPerformed')
        self.assertEqual(status, 3)
        expected = ('INCOMPLETE: 2 dynamic reflective call sites in the migration\'s scope are in the database but '
                    'not in the registry (first: ThirdParty/PSMTabBarControl/PSM.m:8 in PSMDynamic, '
                    'performSelector:); the registry is behind the code.')
        self.assertEqual(section(d, 4)['incomplete'], [expected])
        self.assertEqual(section(d, 8)['incomplete'], [expected])
        self.assertTrue(section(d, 1)['complete'])


class UnreachableCallerTest(DatabaseTest):
    """A method whose only callers are sends in unreachable code
    (send.in_unreachable_code) is never "no caller found", nor silently
    "called": it has its own heading and flag."""

    @staticmethod
    def edit(root):
        with open(os.path.join(root, 'sources', 'Widget.m'), 'a') as f:
            f.write('@interface iTermWidget (Unreachable)\n- (void)deadOnly;\n- (void)halfDead;\n@end\n'
                    '@implementation iTermWidget (Unreachable)\n- (void)deadOnly {}\n- (void)halfDead {}\n'
                    '- (void)callsDead { return; [self deadOnly]; [self halfDead]; }\n'
                    '- (void)callsLive { [self halfDead]; }\n@end\n')

    def test_only_unreachable_callers(self):
        # The flag names the configuration of the units (the capture's is
        # Development; this fixture records none).
        con = sqlite3.connect(self.paths.db)
        config = con.execute("SELECT coalesce(configuration, 'not recorded') FROM tu WHERE main_file = "
                             "'sources/Widget.m'").fetchone()[0]
        con.close()
        flag = 'called only from unreachable code (%s)' % config
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermWidget', '--unreached')
        self.assertNotIn('-deadOnly', by_method(d['methods']))
        m = by_method(d['unreachable'])['-deadOnly']
        self.assertIn(flag, m['flags'])
        self.assertEqual(d['counts']['unreachable'], 1)
        status, d = self.run_json('class', 'iTermWidget')
        t = by_method(d['methods'])
        self.assertEqual(t['-deadOnly']['reach'], 'unreachable')
        self.assertIn(flag, t['-deadOnly']['flags'])
        # A live caller as well: called, no flag.
        self.assertEqual(t['-halfDead']['reach'], 'called')
        self.assertFalse(any('unreachable' in f for f in t['-halfDead']['flags']))
        status, text = self.run_text('class', 'iTermWidget', '--unreached')
        self.assertIn('\n' + ep.UNREACHABLE_HEADING + ': 1\n', text)


class UnreadableRegistryTest(DatabaseTest):
    @staticmethod
    def edit(root):
        os.remove(os.path.join(root, REG))

    def test_a_missing_registry_is_incomplete_not_empty(self):
        status, d = self.method('stringPerformed')
        self.assertEqual(status, 3)
        self.assertTrue(section(d, 4)['incomplete'][0].startswith('INCOMPLETE: the registry '))
        self.assertEqual(rows(d, 4), [])


class NoSwiftTest(DatabaseTest):
    swift = False

    def test_without_the_swift_side_the_answer_is_incomplete(self):
        status, d = self.method('swiftOnlyCalled')
        self.assertEqual(status, 3)
        self.assertFalse(section(d, 2)['complete'])
        self.assertIn('INCOMPLETE: the capture kept no Swift inputs, so Swift references are not in this database.',
                      section(d, 2)['incomplete'])
        self.assertTrue(section(d, 1)['complete'])


class OldSwiftSchemaTest(DatabaseTest):
    def test_swift_tables_of_another_schema_are_read_and_marked(self):
        con = sqlite3.connect(self.paths.db)
        con.execute("UPDATE swift_meta SET value = '1' WHERE key = 'schema_version'")
        con.execute('DROP TABLE swift_protocol')
        con.execute('DROP TABLE swift_inactive')
        con.commit()
        con.close()
        status, d = self.method('swiftOnlyCalled')
        self.assertEqual(status, 3)
        self.assertEqual(rows(d, 2), [
            ('sources/Panel.swift:6:16', 'iTermPanel.show(_:)  call -[iTermWidget swiftOnlyCalled]  receiver '
             'iTermWidget  module Fix', ('FROM SWIFT TABLES OF SCHEMA 1',))])
        reasons = section(d, 2)['incomplete']
        self.assertIn('INCOMPLETE: the Swift tables have schema version 1, not %d; their rows are read as they are, '
                      'and what the newer schema adds is missing.' % harness.swiftdb.SWIFT_SCHEMA_VERSION, reasons)
        self.assertTrue(any('no swift_protocol table' in r for r in reasons))
        self.assertTrue(any('no swift_inactive table' in r for r in reasons))


class MalformedXibTest(DatabaseTest):
    @staticmethod
    def edit(root):
        with open(os.path.join(root, 'sources', 'Broken.xib'), 'w') as f:
            f.write('<document><objects>\n')

    def test_a_xib_that_cannot_be_parsed_makes_section_5_incomplete(self):
        status, d = self.method('biggerFont:')
        self.assertEqual(status, 3)
        self.assertFalse(section(d, 5)['complete'])
        self.assertTrue(section(d, 5)['incomplete'][0].startswith('INCOMPLETE: sources/Broken.xib: not well-formed '
                                                                  'XML'))
        self.assertTrue(section(d, 6)['complete'])


class UnparsedMentionTest(DatabaseTest):
    def test_no_rows_and_a_mention_in_a_file_that_is_not_parsed_is_incomplete(self):
        with open(os.path.join(self.root, 'submodules', 'sub', 'Sub.m'), 'a') as f:
            f.write('void Later(id w) { [w neverCalled]; }\n')
        status, d = self.method('neverCalled')
        self.assertEqual(status, 3)
        self.assertTrue(any(r.startswith('INCOMPLETE: no rows, but files that are not parsed mention the selector')
                            for r in d['incomplete']), d['incomplete'])
        self.assertFalse(section(d, 10)['complete'])
        self.assertEqual(rows(d, 10), [
            ('submodules/sub/Sub.m:3', 'text match (message send) in a file that is not parsed: void Later(id w) { [w '
             'neverCalled]; }')])


# --- Methods the system calls ---------------------------------------------------------

def by_method(entries):
    return dict((m['method'], m) for m in entries)


class SystemReachTest(DatabaseTest):
    """With an sdk_method table: a method whose selector the SDK declares is
    never "no caller found"."""

    def unreached(self, cls, *extra):
        status, d = self.run_json(*(list(extra) + ['class', cls, '--unreached']))
        self.assertEqual(status, d['exit_status'])
        return status, d

    def test_informal_delegate_whose_delegate_another_class_sets(self):
        status, d = self.unreached('iTermPicker', '--runtime-methods', harness.RUNTIME_FIXTURE)
        self.assertEqual((status, d['complete']), (3, False))
        self.assertEqual(d['incomplete'], [rt_reason(harness.RUNTIME_FIXTURE)])
        self.assertEqual([m['method'] for m in d['methods']], ['-unusedPickerMethod'])
        system = by_method(d['system'])
        self.assertEqual(sorted(system), ['-comboBoxSelectionDidChange:'])
        self.assertEqual(system['-comboBoxSelectionDidChange:']['reasons'], [
            'selector declared by the SDK: NSComboBoxDelegate (protocol, AppKit, optional); declared by an SDK '
            'protocol the class does not formally adopt'])
        self.assertEqual(d['undecided'], [])

    def test_services_method(self):
        status, d = self.unreached('iTermReader')
        self.assertEqual([m['method'] for m in d['methods']], [])
        self.assertEqual(by_method(d['system'])['-readSelectionFromPasteboard:']['reasons'], [
            'selector declared by the SDK: NSServicesMenuRequestor (protocol, AppKit, optional); declared by an SDK '
            'protocol the class does not formally adopt'])
        self.assertEqual(status, 1)

    def test_sdk_action_on_a_class_that_does_not_inherit_it(self):
        status, d = self.unreached('iTermTabsController')
        self.assertEqual(by_method(d['system'])['-selectNextTab:']['reasons'], [
            'selector declared by the SDK: NSWindow (class, AppKit, IBAction: menus and the responder chain send '
            'it); same selector as an action of an SDK class (NSWindow): menus and the responder chain send it to '
            'whatever object implements it'])

    def test_swift_overrides_of_sdk_members(self):
        # The Swift class's superclass comes from its declaration (class SwiftWindow: NSWindow).
        status, d = self.unreached('iTermSwiftWindow', '--runtime-methods', harness.RUNTIME_FIXTURE)
        self.assertEqual([m['method'] for m in d['methods']], ['-swiftUnusedWindowMethod'])
        system = by_method(d['system'])
        self.assertEqual(system['-canBecomeMainWindow']['reasons'], [
            'overrides a member declared outside the repository (c:objc(cs)NSWindow(im)canBecomeMainWindow)',
            'selector declared by the SDK: NSWindow (class, AppKit); overrides or implements an inherited SDK '
            'member'])
        self.assertEqual(system['-cursorUpdate:']['reasons'][0],
                         'overrides a member declared outside the repository (c:objc(cs)NSWindow(im)cursorUpdate:)')

    def test_swift_witness_of_an_adopted_sdk_protocol(self):
        status, d = self.unreached('iTermOutlineSource')
        self.assertEqual([m['method'] for m in d['methods']], [])
        self.assertEqual(by_method(d['system'])['-outlineView:numberOfChildrenOfItem:']['reasons'], [
            'selector declared by the SDK: NSOutlineViewDataSource (protocol, AppKit, optional); not narrowed: the '
            'database does not record the conformances of Swift classes to Objective-C protocols'])

    def test_objc_override_of_an_sdk_member_is_inherited(self):
        status, d = self.run_json('class', 'iTermWidget')
        t = by_method(d['methods'])
        # Called (a super send), so not listed by --unreached; the reason is kept.
        self.assertEqual(t['-awakeFromNib']['reach'], 'called')
        self.assertIn('selector declared by the SDK: NSObject(NSNibAwaking) (category, AppKit); overrides or '
                      'implements an inherited SDK member', t['-awakeFromNib']['reasons'])

    def test_a_delegate_wired_in_a_xib_is_flagged(self):
        status, d = self.unreached('iTermXibComboOwner')
        system = by_method(d['system'])
        self.assertEqual(system['-comboBoxWillWobble:']['reasons'], [
            'possible AppKit delegate method: this object is the delegate of comboBox id=6 (NSComboBox, from the '
            'element) in a xib (sources/Picker.xib:8)'])

    def test_method_mode_lists_the_sdk_declaration(self):
        status, d = self.method('selectNextTab:', cls='iTermTabsController')
        self.assertEqual((status, d['complete']), (0, True))
        self.assertEqual([r for r in rows(d, 7) if 'SDK' in r[1]], [
            ('sources/SDKUsers.m:43', 'selector declared by the SDK: NSWindow (class, AppKit, IBAction: menus and '
             'the responder chain send it); same selector as an action of an SDK class (NSWindow): menus and the '
             'responder chain send it to whatever object implements it: the system may call it')])

    def test_a_table_wins_over_the_interim_file(self):
        status, d = self.run_json('--sdk-selectors', harness.SDK_FIXTURE, 'class', 'iTermPickerOwner', '--unreached')
        # Its one candidate needs a runtime method list (decisions.md
        # 2026-11-20); nothing else is incomplete, the interim file least.
        self.assertEqual(status, 3)
        self.assertEqual(d['incomplete'], [ep.NO_RUNTIME_INCOMPLETE % 1])

    def test_text_output_has_the_three_headings_and_says_what_the_status_means(self):
        status, text = self.run_text('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermPicker', '--unreached')
        self.assertIn('\nMethods with no caller found (not "dead": see Not covered): 1\n', text)
        self.assertIn('\nselector declared by the SDK: the system may call it: 1\n', text)
        self.assertIn('\ncandidates, not decided: 0\n', text)
        self.assertTrue(text.rstrip('\n').split('\n')[-1].startswith('This run: exit status 3: the answer is '
                                                                    'INCOMPLETE'))
        # A method under no caller found needs a runtime method list, which
        # always makes the run incomplete, so status 0 is reached only
        # through the words for it.
        status, text = self.run_text('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermPickerOwner',
                                     '--unreached')
        self.assertIn('\nMethods with no caller found (not "dead": see Not covered): 1\n', text)
        self.assertTrue(text.rstrip('\n').split('\n')[-1].startswith('This run: exit status 3: the answer is '
                                                                    'INCOMPLETE'))
        counts = dict((k, 0) for k in ('no_caller',) + ep.REACH_KEYS)
        counts['no_caller'] = 1
        self.assertTrue(ep.unreached_status_words({'exit_status': 0, 'counts': counts, 'generated_excluded': 0,
                                                   'subject': 'iTermPickerOwner'}).startswith(
            'This run: exit status 0: methods with no caller found are listed above, and every source was '
            'consulted and is complete. Methods listed: 1 with no caller found, 0 as possibly called by the system, '
            '0 as weak'))


class NoSDKTest(DatabaseTest):
    """No sdk_method table and no interim file: nothing is "no caller found"."""
    sdk_table = False

    def test_without_sdk_declarations_candidates_are_not_decided(self):
        status, d = self.run_json('class', 'iTermPicker', '--unreached')
        self.assertEqual(status, 3)
        self.assertEqual(d['methods'], [])
        self.assertEqual(sorted(m['method'] for m in d['undecided']),
                         ['-comboBoxSelectionDidChange:', '-unusedPickerMethod'])
        self.assertIn(ep.NO_SDK_REASON, d['incomplete'])
        status, text = self.run_text('class', 'iTermPicker', '--unreached')
        self.assertIn('\ncandidates, not decided: the database has no SDK declarations (sdk_method table): 2\n', text)
        self.assertIn('This run: exit status 3: ', text.rstrip('\n').split('\n')[-1])

    def test_swift_overrides_are_system_reached_without_the_sdk(self):
        status, d = self.run_json('class', 'iTermSwiftWindow', '--unreached')
        self.assertEqual(d['methods'], [])
        self.assertIn('-canBecomeMainWindow', by_method(d['system']))
        self.assertIn('-cursorUpdate:', by_method(d['system']))
        self.assertEqual([m['method'] for m in d['undecided']], ['-swiftUnusedWindowMethod'])

    def test_method_mode_section_7_is_incomplete(self):
        status, d = self.method('neverCalled')
        self.assertEqual(status, 3)
        self.assertIn(ep.NO_SDK_REASON, section(d, 7)['incomplete'])


class InterimSDKFileTest(DatabaseTest):
    sdk_table = False

    def test_the_interim_file_decides_but_is_incomplete(self):
        status, d = self.run_json('--sdk-selectors', harness.SDK_FIXTURE, '--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermPicker',
                                  '--unreached')
        self.assertEqual(status, 3)
        self.assertEqual([m['method'] for m in d['methods']], ['-unusedPickerMethod'])
        self.assertEqual(sorted(by_method(d['system'])), ['-comboBoxSelectionDidChange:'])
        self.assertEqual(d['undecided'], [])
        interim = [r for r in d['incomplete'] if 'interim' in r]
        self.assertEqual(interim, [ep.interim_reason(harness.SDK_FIXTURE)])
        self.assertIn('from a text scan of SDK headers, interim until the code database records SDK declarations',
                      interim[0])

    def test_a_malformed_interim_file_is_an_error(self):
        d = harness.make_temp()
        bad = os.path.join(d, 'bad.tsv')
        with open(bad, 'w') as f:
            f.write('protocol\tNSFoo\t-\n')
        out = io.StringIO()
        self.assertEqual(ep.main(census_args(self.root, self.paths) + ['--sdk-selectors', bad, 'class', 'iTermPicker',
                                                                       '--unreached'], out=out), 2)


# --- Scripting through a forwarding proxy -----------------------------------------------

class ScriptingForwardingTest(DatabaseTest):
    def test_window_keys_and_commands_reach_the_forwarded_classes(self):
        status, d = self.method('scriptFrontmost', cls='iTermWindow')
        self.assertEqual(rows(d, 6), [
            ('iTerm2.sdef:23', 'sdef property "frontmost" of class "window", key scriptFrontmost (access r): '
             'scripting reaches scriptFrontmost through key-value coding; the cocoa class iTermScriptingWindow '
             'forwards to iTermWindow')])
        self.assertTrue(section(d, 6)['complete'])
        status, d = self.method('handleSelectCommand:', cls='iTermWindow')
        self.assertEqual(rows(d, 6)[0][1], 'sdef responds-to command "select" of class "window": method '
                         'handleSelectCommand:; the cocoa class iTermScriptingWindow forwards to iTermWindow')
        for cls in ('iTermWindow', 'iTermCompactPanel'):
            status, d = self.run_json('class', cls, '--unreached')
            self.assertEqual([m['method'] for m in d['methods'] + d['system'] + d['undecided']], [], cls)

    def test_the_forwarding_table_matches_the_binding_tests(self):
        with open(os.path.join(REPO, 'ModernTests', 'BindingTestTables.swift'), 'r', encoding='utf-8') as f:
            text = f.read()
        body = text[text.index('static let sdefForwardingProtocols'):]
        body = body[:body.index(']\n')]
        swift = dict(re.findall(r'"(\w+)": "(\w+)"', body))
        self.assertEqual(swift, dict((k, v['protocol']) for k, v in ep.SDEF_FORWARDING.items()))
        # The classes are the ones that conform to the protocol in its header.
        with open(os.path.join(REPO, 'sources', 'TerminalView', 'PTYWindow.h'), 'r', encoding='utf-8') as f:
            header = f.read()
        conformers = sorted(re.findall(r'^@interface (\w+) : \w+<[^>]*\bPTYWindow\b[^>]*>', header, re.M))
        self.assertEqual(conformers, sorted(ep.SDEF_FORWARDING['iTermScriptingWindow']['classes']))

    def test_an_unforwarded_proxy_makes_scripting_incomplete_for_every_class(self):
        with mock.patch.dict(ep.SDEF_FORWARDING, clear=True):
            status, d = self.method('biggerFont:')
        self.assertEqual(status, 3)
        self.assertEqual(section(d, 6)['incomplete'], [
            'INCOMPLETE: the sdef class "window" has cocoa class iTermScriptingWindow, which forwards messages '
            '(implements forwardInvocation:, methodSignatureForSelector:) and has no entry in this tool\'s '
            'forwarding table, so the classes that receive its keys and commands are not known.'])


# --- The registry's bullets ---------------------------------------------------------------

class RegistryBulletTest(unittest.TestCase):
    def test_every_bullet_shape(self):
        p = ep.parse_bullet
        self.assertEqual(p('- `a/B.m:12` in `-[B go]`: `x`'), ep.Site('a/B.m', 12, '-[B go]', ((None, 12),)))
        self.assertEqual(p('- `a/B.m:913 (also C.h:26, C.m:135)`: in `-[B go]`: `x`'),
                         ep.Site('a/B.m', 913, '-[B go]', ((None, 913), ('C.h', 26), ('C.m', 135))))
        self.assertEqual(p('- `a/B.m:90, 158 (also D.m:23)`: XPC service `x`: `y`'),
                         ep.Site('a/B.m', 90, None, ((None, 90), (None, 158), ('D.m', 23))))
        self.assertEqual(p('- `a/B.swift:280, 281`: `x`, then `y`'),
                         ep.Site('a/B.swift', 280, None, ((None, 280), (None, 281))))
        self.assertIsNone(p('- `a/B.m:12` near `-[B go]`'))
        self.assertIsNone(p('- `ColorPicker/` (26 files)'))

    def test_an_unparseable_bullet_of_an_entry_is_recorded(self):
        text = read(REG).replace('- `sources/Widget.m:23` in `-[iTermWidget go]`:',
                                 '- `sources/Widget.m:23` near `-[iTermWidget go]`:')
        reg = ep.parse_registry(text)
        self.assertEqual(reg.unparsed, [(42, '- `sources/Widget.m:23` near `-[iTermWidget go]`: `NSSelectorFromString` '
                                             'on `@"stringPerformed"`')])

    def test_every_bullet_of_an_entry_in_the_real_registry_parses(self):
        with open(os.path.join(REPO, REG), 'r', encoding='utf-8') as f:
            reg = ep.parse_registry(f.read())
        self.assertEqual(reg.unparsed, [])

    def test_coverage_is_by_function_or_by_line_never_by_file(self):
        reg = ep.parse_registry(read(REG).replace(
            '- `sources/Widget.m:70`: archived thing', '- `sources/Widget.m:70, 72 (also Other.m:4)`: archived thing'))
        self.assertTrue(reg.covers('sources/Widget.m', 23, '-[iTermWidget go]'))
        self.assertTrue(reg.covers('sources/Widget.m', 72, 'Elsewhere'))
        self.assertTrue(reg.covers('ThirdParty/Other/Other.m', 4, 'OtherCaller'))
        self.assertFalse(reg.covers('sources/Widget.m', 71, 'Elsewhere'))


class RegistryAlsoFormTest(DatabaseTest):
    """The reviewer's reproduction: an entry whose bullet has the form
    `file:line (also ...)`: in `fn`, and a new dynamic call in another
    function of that file."""

    @staticmethod
    def edit(root):
        path = os.path.join(root, REG)
        with open(path) as f:
            text = f.read()
        text = text.replace('- `ThirdParty/PSMTabBarControl/PSM.m:8` in `PSMDynamic`:',
                            '- `ThirdParty/PSMTabBarControl/PSM.m:8 (also Widget.m:22)`: in `PSMDynamic`:')
        with open(path, 'w') as f:
            f.write(text)
        with open(os.path.join(root, 'ThirdParty', 'PSMTabBarControl', 'PSM.m'), 'a') as f:
            f.write('void PSMDynamic2(NSString *name, id target) {\n    [target performSelector:NSSelectorFromString('
                    'name)];\n}\n')

    def test_a_new_dynamic_site_in_a_file_listed_with_that_form_is_reported(self):
        status, d = self.method('stringPerformed')
        self.assertEqual(status, 3)
        self.assertEqual(len(section(d, 4)['incomplete']), 1)
        self.assertIn('(first: ThirdParty/PSMTabBarControl/PSM.m:27 in PSMDynamic2, ', section(d, 4)['incomplete'][0])


class RegistryUnparsedBulletTest(DatabaseTest):
    @staticmethod
    def edit(root):
        path = os.path.join(root, REG)
        with open(path) as f:
            text = f.read()
        with open(path, 'w') as f:
            f.write(text.replace('- `sources/Widget.m:23` in `-[iTermWidget go]`:',
                                 '- `sources/Widget.m:23` near `-[iTermWidget go]`:'))

    def test_an_unparseable_bullet_makes_the_registry_sections_incomplete(self):
        status, d = self.method('stringPerformed')
        self.assertEqual(status, 3)
        self.assertIn('INCOMPLETE: the registry\'s bullet at docs/swift-migration/reflective-sites.md:42 is not in a '
                      'form this tool reads, so the sites it lists are not known: "- `sources/Widget.m:23` near '
                      '`-[iTermWidget go]`: `NSSelectorFromString` on `@"stringPerformed"`"',
                      section(d, 4)['incomplete'])


# --- Smaller items -----------------------------------------------------------------------

class SmallerItemsTest(DatabaseTest):
    def test_a_selector_with_a_leading_minus_needs_no_double_dash(self):
        status, d = self.method('-go')
        self.assertEqual(d['subject'], '-[iTermWidget go]')
        status, d = self.run_json('method', 'iTermWidget', '-go')
        self.assertEqual(d['subject'], '-[iTermWidget go]')

    def test_a_binding_key_path_beginning_with_self_is_on_the_target(self):
        status, d = self.method('wobbleKey', cls='iTermXibComboOwner')
        self.assertEqual(rows(d, 5), [
            ('sources/Picker.xib:9:17',
             'binding self.wobbleKey (binding value) on customObject id=5 (iTermXibComboOwner)')])
        status, d = self.run_json('class', 'iTermXibComboOwner')
        self.assertEqual(by_method(d['methods'])['-wobbleKey']['ib'], 1)

    def test_short_or_common_names_are_counted_per_file(self):
        status, d = self.method('go')
        self.assertEqual(rows(d, 6), [
            ('OtherResources/actions.json', 'text: the token go, 2 matches in this file (a name shorter than 6 '
             'characters or a common word: the lines are not listed)')])


# --- Sources the method table must consult before "no caller found" ----------------

class ProbeTest(DatabaseTest):
    """Swift calls of Swift declarations, property accesses and calls through
    a protocol type, calls through a Swift protocol requirement, code that is
    not compiled, test-only callers, generated files, and the SDK labels."""

    def unreached(self, cls, *extra):
        status, d = self.run_json(*(['class', cls, '--unreached'] + list(extra)))
        self.assertEqual(status, d['exit_status'])
        return status, d

    def test_swift_calls_of_swift_declarations_are_recorded_only_for_objective_c_usrs(self):
        con = sqlite3.connect(self.paths.db)
        decls = dict(con.execute("SELECT selector, usr FROM swift_objc_decl WHERE file = 'sources/Panel.swift' AND "
                                 "selector IN ('publicCallee', 'privateCallee', 'innerCallee')"))
        refs = set(s for (s,) in con.execute("SELECT selector FROM swift_ref WHERE kind = 'call'"))
        con.close()
        # The rule, from the reader (it records a reference only when the USR
        # it names is an Objective-C one) and this fixture: a Swift call of a
        # Swift @objc member with an Objective-C USR is recorded; of one with
        # a Swift USR (private, a nested class) it is not.
        self.assertTrue(decls['publicCallee'].startswith('c:'))
        self.assertTrue(decls['privateCallee'].startswith('s:'))
        self.assertTrue(decls['innerCallee'].startswith('s:'))
        self.assertIn('publicCallee', refs)
        self.assertNotIn('privateCallee', refs)
        self.assertNotIn('innerCallee', refs)

    def test_a_swift_member_with_a_swift_usr_is_never_no_caller_found(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermSwiftCaller',
                                  '--unreached')
        self.assertEqual(sorted(m['method'] for m in d['methods']), ['-publicNeverCalled', '-run'])
        self.assertEqual([m['method'] for m in d['swift_defined']], ['-privateCallee'])
        self.assertIn('Swift USR', d['swift_defined'][0]['reasons'][0])
        self.assertEqual(d['counts']['swift_defined'], 1)
        status, d = self.unreached('Inner')
        self.assertEqual(d['methods'], [])
        self.assertEqual([m['method'] for m in d['swift_defined']], ['-innerCallee'])
        self.assertEqual(status, 3)
        self.assertIn('INCOMPLETE: 1 methods are defined in Swift with a Swift USR, and Swift callers of them are not '
                      'in the database (listed under "%s").' % ep.SWIFT_DEFINED_HEADING, d['incomplete'])
        status, text = self.run_text('class', 'iTermSwiftCaller', '--unreached')
        self.assertIn('\n' + ep.SWIFT_DEFINED_HEADING + ': 1\n', text)
        self.assertIn('1 as defined in Swift', text.rstrip('\n').split('\n')[-1])

    def test_method_mode_says_swift_callers_of_a_swift_declaration_are_not_recorded(self):
        status, d = self.method('privateCallee', cls='iTermSwiftCaller')
        self.assertEqual(status, 3)
        self.assertFalse(section(d, 2)['complete'])
        self.assertTrue(any('Swift callers of this Swift declaration are not recorded' in line
                            for line in section(d, 2)['incomplete']))
        status, d = self.method('publicCallee', cls='iTermSwiftCaller')
        self.assertEqual([r[0] for r in rows(d, 2)], ['sources/Panel.swift:36:9'])
        self.assertFalse(any('not recorded' in line for line in section(d, 2)['incomplete']))

    def test_property_accesses_through_a_protocol_type_reach_every_implementer(self):
        for cls in ('iTermProbe', 'iTermPanelHost'):
            status, d = self.run_json('class', cls)
            t = by_method(d['methods'])
            self.assertEqual((t['-panelDelegate']['reach'], t['-panelDelegate']['swift']), ('called', 1), cls)
            self.assertEqual((t['-setPanelDelegate:']['reach'], t['-setPanelDelegate:']['swift']), ('called', 1), cls)
        status, d = self.method('panelDelegate', cls='iTermProbe')
        self.assertEqual(rows(d, 2), [
            ('sources/Panel.swift:58:14', 'readPanelOwner(_:)  property reference property '
             'iTermPanelOwnerProtocol.panelDelegate (protocol requirement), access get  module Fix')])
        status, d = self.method('setPanelDelegate:', cls='iTermProbe')
        self.assertEqual([r[0] for r in rows(d, 2)], ['sources/Panel.swift:53:7'])

    def test_a_swift_call_through_a_protocol_type_is_matched_by_selector(self):
        status, d = self.run_json('class', 'iTermProbe')
        self.assertEqual(by_method(d['methods'])['-ownerPing']['reach'], 'called')

    def test_a_witness_of_a_swift_protocol_requirement(self):
        status, d = self.unreached('iTermProbe')
        self.assertNotIn('-wobble', by_method(d['methods']))
        m = by_method(d['swift_protocol'])['-wobble']
        self.assertEqual(m['reasons'], ['possibly called through the Swift protocol requirement Wobbler.wobble: '
                                        'iTermProbe conforms to Wobbler (sources/Panel.swift:66)'])

    def test_a_swift_class_member_named_like_a_swift_requirement_is_not_decided(self):
        status, d = self.unreached('iTermSwiftWobbler')
        self.assertEqual(d['methods'], [])
        self.assertIn('possibly called through the Swift protocol requirement Wobbler.wobble (sources/Panel.swift:63): '
                      'the database does not record which Swift protocols a Swift class conforms to',
                      by_method(d['swift_protocol'])['-wobble']['reasons'])

    def test_code_that_is_not_compiled(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermProbe', '--unreached')
        inactive = by_method(d['inactive'])
        self.assertEqual(inactive['-swiftInactiveOnly']['reasons'], [
            'swiftInactiveOnly at sources/Panel.swift:75, in a Swift #if clause that is not compiled (lines 75-75)'])
        self.assertEqual(inactive['-objcInactiveOnly']['reasons'], [
            'objcInactiveOnly at sources/SDKUsers.m:123, in an Objective-C range no unit compiles (lines 123-123)'])
        self.assertEqual(inactive['-uncapturedOnly']['reasons'], [
            'uncapturedOnly at ModernTests/WidgetTests.swift:4, in a Swift file no captured module compiles'])
        self.assertEqual([m['method'] for m in d['methods']], ['-probeNeverCalled'])

    def test_called_only_from_tests_has_its_own_heading(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermWidget', '--unreached')
        self.assertEqual([m['method'] for m in d['methods']], ['-neverCalled'])
        self.assertEqual([m['method'] for m in d['tests']], ['-declaredOnly'])
        status, text = self.run_text('class', 'iTermWidget', '--unreached')
        self.assertIn('\n' + ep.TESTS_HEADING + ': 1\n', text)

    def test_generated_files_are_left_out_of_unreached(self):
        status, d = self.unreached('iTermGenMessage')
        self.assertEqual(d['methods'], [])
        self.assertEqual(d['generated_excluded'], 2)
        status, text = self.run_text('class', 'iTermGenMessage', '--unreached')
        self.assertIn('methods in generated files left out (--no-exclude-generated lists them): 2', text)
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermGenMessage',
                                  '--unreached', '--no-exclude-generated')
        self.assertEqual(sorted(m['method'] for m in d['methods']), ['-genField', '-setGenField:'])

    def test_an_sdk_class_outside_the_superclass_chain_is_its_own_subgroup(self):
        status, d = self.unreached('iTermProbe')
        m = by_method(d['system'])['-setFiles:']
        self.assertEqual(m['reasons'], [
            'selector declared by the SDK: DOMHTMLInputElement (class, WebKit); same selector as a method of an '
            'unrelated SDK class (DOMHTMLInputElement): the system calls that class\'s method, not necessarily this '
            'one'])
        self.assertEqual(m['system_group'], ep.SDK_UNRELATED_GROUP)
        status, text = self.run_text('class', 'iTermProbe', '--unreached')
        self.assertIn('  ' + ep.SDK_UNRELATED_GROUP + ': 1\n', text)


class NoSkippedRangesTest(DatabaseTest):
    pp_skipped = False

    def test_without_skipped_ranges_nothing_is_decided(self):
        status, d = self.run_json('class', 'iTermProbe', '--unreached')
        self.assertEqual(d['methods'], [])
        m = by_method(d['undecided'])['-probeNeverCalled']
        self.assertIn(ep.NO_PP_SKIPPED_REASON, m['reasons'])


class NoSwiftProtocolTableTest(DatabaseTest):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        con = sqlite3.connect(cls.paths.db)
        con.execute('DROP TABLE swift_protocol')
        con.commit()
        con.close()

    def test_without_the_swift_protocol_table_every_method_is_undecided_and_it_is_said_once(self):
        status, d = self.run_json('class', 'iTermProbe', '--unreached')
        self.assertEqual(d['methods'], [])
        self.assertIn('-probeNeverCalled', by_method(d['undecided']))
        self.assertEqual(sum(1 for line in d['incomplete'] if 'swift_protocol' in line), 1)


# --- Overrides of private framework methods, and declarations defined elsewhere --------

RUNTIME_OS = 'macOS 99.1 (99A123)'
# How the census names the fixture's live list and its dump-derived one.
RUNTIME_LABEL = RUNTIME_OS + ' [live runtime, 2 frameworks]'
OLDER_LABEL = 'macOS 98.0 (98A1) [dumped headers: no methods added through categories by other images]'
RUNTIME_MARK = ('; not declared in the SDK headers (private); from the runtime method list of %s, specific to that OS '
                'version' % RUNTIME_LABEL)


def rt_reason(*paths):
    return ep.runtime_reason([ep.load_runtime_methods(p) for p in paths])


def write_list(d, name, body, kind='live', frameworks='AppKit, Foundation', os_line='macOS 1.0 (1A1)', trailer=True):
    """A runtime method list in d with header and trailer lines."""
    lines = ['# os: ' + os_line]
    if kind:
        lines.append('# kind: ' + kind)
    if frameworks is not None:
        lines.append('# frameworks: ' + frameworks)
    rows = [row for row in body.split('\n') if row]
    lines += rows
    if trailer:
        lines.append('# end: C=%d M=%d' % (sum(1 for row in rows if row.startswith('C\t')),
                                           sum(1 for row in rows if row.startswith('M\t'))))
    path = os.path.join(d, name)
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    return path


GRAPH = ('C\tNSObject\t\nC\tNSResponder\tNSObject\nC\tNSView\tNSResponder\nC\tNSScrollView\tNSView\n'
         'C\tNSUnrelated\tNSObject\n')


class RuntimeListFormatTest(unittest.TestCase):
    """The header and trailer lines of a runtime method list, and what the
    census says about each kind of list."""

    def setUp(self):
        self.d = harness.make_temp()

    def test_the_kind_of_each_list_is_read_and_named(self):
        live = ep.load_runtime_methods(harness.RUNTIME_FIXTURE)
        self.assertEqual((live.kind, live.label()), ('live', RUNTIME_LABEL))
        dump = ep.load_runtime_methods(harness.RUNTIME_FIXTURE_OLDER)
        self.assertEqual((dump.kind, dump.label()), ('dumped-headers', OLDER_LABEL))
        partial = ep.load_runtime_methods(write_list(self.d, 'p.tsv', GRAPH, frameworks='AppKit, Charts (not loaded), '
                                                     'Foundation'))
        self.assertEqual(partial.label(), 'macOS 1.0 (1A1) [live runtime, 2 of 3 frameworks; not loaded: Charts]')

    def test_a_list_without_a_kind_is_live_only_with_a_frameworks_line(self):
        legacy = ep.load_runtime_methods(write_list(self.d, 'l.tsv', GRAPH, kind=None))
        self.assertEqual(legacy.kind, 'live')
        for name, kwargs in (('neither.tsv', dict(kind=None, frameworks=None)),
                             ('unknown.tsv', dict(kind='guessed'))):
            with self.assertRaises(ep.CensusError, msg=name):
                ep.load_runtime_methods(write_list(self.d, name, GRAPH, **kwargs))

    def test_a_list_must_end_with_a_trailer_that_matches_its_counts(self):
        body = GRAPH + 'M\tNSView\t-\tfoo\n'
        good = write_list(self.d, 'good.tsv', body)
        ep.load_runtime_methods(good)
        with open(good) as f:
            lines = f.readlines()
        cases = {
            'no trailer': ''.join(lines[:-1]),
            'truncated at a line boundary': ''.join(lines[:-3]),
            'C lines and no M lines': ''.join(x for x in lines if not x.startswith(('M\t', '# end'))) +
            '# end: C=5 M=1\n',
            'wrong counts': ''.join(lines[:-1]) + '# end: C=5 M=2\n',
            'a line after the trailer': ''.join(lines) + 'M\tNSView\t-\tbar\n',
            'a malformed trailer': ''.join(lines[:-1]) + '# end: five\n',
        }
        for name, text in cases.items():
            path = os.path.join(self.d, 'bad.tsv')
            with open(path, 'w') as f:
                f.write(text)
            with self.assertRaises(ep.CensusError, msg=name):
                ep.load_runtime_methods(path)

    def test_the_old_list_without_a_trailer_is_refused(self):
        old = os.path.join(REPO, 'tmp', 'delete-unused-reflective-helpers', 'runtime-methods.tsv')
        if not os.path.exists(old):
            self.skipTest('no %s' % old)
        with self.assertRaises(ep.CensusError):
            ep.load_runtime_methods(old)

    def test_a_keyword_selector_is_matched_whole(self):
        rt = ep.load_runtime_methods(write_list(self.d, 'k.tsv', GRAPH + 'M\tNSUnrelated\t-\tfoo:bar:\n'
                                                'M\tNSView\t-\tfoo:\n'))
        rt.prefetch(['foo:bar:', 'foo:', 'foo:baz:', 'foo'])
        self.assertEqual(rt.implementers('foo:bar:'), frozenset([('NSUnrelated', False)]))
        self.assertEqual(rt.implementers('foo:'), frozenset([('NSView', False)]))
        self.assertEqual(rt.implementers('foo:baz:'), frozenset())
        self.assertEqual(rt.implementers('foo'), frozenset())
        self.assertEqual(ep.runtime_verdict([rt], 'iTermApp', 'NSResponder', False, 'foo:bar:')[0], 'weak')
        self.assertEqual(ep.runtime_verdict([rt], 'iTermApp', 'NSResponder', False, 'foo:baz:')[0], 'none')
        fixture = ep.load_runtime_methods(harness.RUNTIME_FIXTURE)
        self.assertEqual(fixture.implementers('fixtureKeyword:'), frozenset())
        self.assertEqual(fixture.implementers('fixtureKeyword:selector:'), frozenset([('NSFixtureUnrelated2', False)]))

    def test_each_rule_takes_the_union_of_the_lists(self):
        empty = ep.load_runtime_methods(write_list(self.d, 'a.tsv', GRAPH, os_line='macOS 1.0 (1A1)'))
        cases = (
            ('override', 'iTermApp', 'NSView', 'M\tNSResponder\t-\tsel\n', 'system'),
            ('category subtree', 'NSView', 'NSView', 'M\tNSScrollView\t-\tsel\n', 'system'),
            ('weak', 'iTermApp', 'NSView', 'M\tNSUnrelated\t-\tsel\n', 'weak'),
        )
        for name, cls, fw, line, expected in cases:
            other = ep.load_runtime_methods(write_list(self.d, name + '.tsv', GRAPH + line, kind='dumped-headers',
                                                       frameworks=None, os_line='macOS 2.0'))
            self.assertEqual(ep.runtime_verdict([empty], cls, fw, False, 'sel')[0], 'none', name)
            for order in ([empty, other], [other, empty]):
                reach, why, flag, later = ep.runtime_verdict(order, cls, fw, False, 'sel')
                self.assertEqual(reach, expected, name)
                text = why or later[0]
                self.assertIn('macOS 2.0 [dumped headers: no methods added through categories by other images]',
                              text, name)
                self.assertNotIn('macOS 1.0', text, name)

    def test_the_incomplete_line_says_which_releases_had_live_lists(self):
        line = rt_reason(harness.RUNTIME_FIXTURE, harness.RUNTIME_FIXTURE_OLDER)
        self.assertIn('releases consulted: %s; %s;' % (RUNTIME_LABEL, OLDER_LABEL), line)
        self.assertIn('Checked with a live runtime list: %s; checked only with lists derived from dumped headers: '
                      'macOS 98.0 (98A1), which cannot show methods that other images add to a class through '
                      'categories.' % RUNTIME_OS, line)
        self.assertIn('Checked with a live runtime list: none;', rt_reason(harness.RUNTIME_FIXTURE_OLDER))
        self.assertIn('checked only with lists derived from dumped headers: none.', rt_reason(harness.RUNTIME_FIXTURE))
        self.assertNotIn('\n', line)


class RuntimeMethodsParserTest(unittest.TestCase):
    def test_the_fixture_file_and_the_lookup(self):
        rt = ep.load_runtime_methods(harness.RUNTIME_FIXTURE)
        self.assertEqual(rt.os_version, RUNTIME_OS)
        self.assertEqual(rt.superclass('NSScrollView'), 'NSView')
        self.assertTrue(rt.has_class('NSObject'))
        self.assertFalse(rt.has_class('iTermWindow'))
        self.assertEqual(rt.implementer('NSScrollView', False, 'allowedPocketEdges'), 'NSScrollView')
        self.assertEqual(rt.implementer('NSPanel', False, '_usesCustomDrawing'), 'NSResponder')
        # The class-or-instance kind must match.
        self.assertIsNone(rt.implementer('NSPanel', True, '_usesCustomDrawing'))
        self.assertIsNone(rt.implementer('NSView', False, 'plainUnusedMethod'))
        self.assertEqual(rt.implementer('NSView', True, 'plainUnusedMethod'), 'NSObject')
        # A class method lookup ends in the root class's instance methods (the
        # root metaclass's superclass is the root class); not the reverse.
        self.assertEqual(rt.implementer('NSWindow', True, 'description'), 'NSObject')
        self.assertIsNone(rt.implementer('NSWindow', False, 'alloc'))
        self.assertIsNone(rt.implementer('NSNotThere', False, 'description'))

    def test_methods_are_read_only_for_the_selectors_asked_about(self):
        # Only the class graph is kept after loading; methods are streamed
        # from the file for the selectors a run asks about, and only those
        # are kept.
        rt = ep.load_runtime_methods(harness.RUNTIME_FIXTURE)
        self.assertEqual(rt.selectors_held(), 0)
        rt.prefetch(['fixtureSubclassHook', 'notInTheList'])
        self.assertEqual(rt.selectors_held(), 2)
        self.assertEqual(rt.implementers('fixtureSubclassHook'), frozenset([('NSScrollView', False)]))
        self.assertEqual(rt.implementers('notInTheList'), frozenset())
        self.assertEqual(rt.implementers('fixtureClassKindHook'), frozenset([('NSScrollView', True)]))
        self.assertEqual(rt.selectors_held(), 3)
        self.assertEqual(rt.subclass_implementers('NSView', False, 'fixtureSubclassHook'), ['NSScrollView'])
        self.assertEqual(rt.subclass_implementers('NSView', False, 'fixtureClassKindHook'), [])
        self.assertEqual(rt.subclass_implementers('NSObject', False, 'fixtureRootHook'), ['NSView'])
        self.assertEqual(rt.subclass_implementers('NSResponder', True, 'fixtureRootHook'), ['NSView'])
        self.assertEqual(rt.subclass_implementers('NSResponder', False, 'fixtureRootHook'), [])

    def test_malformed_files_are_errors(self):
        d = harness.make_temp()
        header = '# os: macOS 1.0 (1A1)\n# kind: live\n'
        for text in (header + 'C\tNSObject\n', header + 'M\tNSObject\t*\tfoo\n', header + 'X\ta\tb\n',
                     header + 'M\tNSObject\t-\t\n', '# kind: live\nC\tNSObject\t\n# end: C=1 M=0\n'):
            path = os.path.join(d, 'bad.tsv')
            with open(path, 'w') as f:
                f.write(text)
            with self.assertRaises(ep.CensusError, msg=text):
                ep.load_runtime_methods(path)
        with self.assertRaises(ep.CensusError):
            ep.load_runtime_methods(os.path.join(d, 'missing.tsv'))


class PrivateOverrideTest(DatabaseTest):
    def unreached(self, cls, *top):
        status, d = self.run_json(*(list(top) + ['class', cls, '--unreached']))
        self.assertEqual(status, d['exit_status'])
        return status, d

    def with_runtime(self, cls):
        return self.unreached(cls, '--runtime-methods', harness.RUNTIME_FIXTURE)

    def test_an_override_of_a_method_the_framework_class_implements_at_run_time(self):
        status, d = self.with_runtime('iTermScroller')
        self.assertEqual(d['methods'], [])
        self.assertEqual(by_method(d['system'])['-allowedPocketEdges']['reasons'], [
            "overrides a method that the framework's NSScrollView implements at run time" + RUNTIME_MARK])
        self.assertEqual(status, 3)
        self.assertEqual([r for r in d['incomplete'] if 'framework methods are read from' in r],
                         [rt_reason(harness.RUNTIME_FIXTURE)])

    def test_through_a_repository_superclass_to_an_ancestor_of_the_framework_class(self):
        status, d = self.with_runtime('iTermFancyWindow')
        self.assertEqual(d['methods'], [])
        self.assertEqual(by_method(d['system'])['-_usesCustomDrawing']['reasons'], [
            "overrides a method that the framework's NSWindow (through its ancestor NSResponder) implements at run "
            "time" + RUNTIME_MARK])

    def test_without_a_runtime_list_an_override_of_a_framework_subclass_is_not_decided(self):
        status, d = self.unreached('iTermScroller')
        self.assertEqual(d['methods'], [])
        self.assertEqual(by_method(d['undecided'])['-allowedPocketEdges']['reasons'], [ep.NO_RUNTIME_REASON])
        self.assertEqual(status, 3)
        self.assertEqual(sum(1 for r in d['incomplete'] if '--runtime-methods' in r), 1)

    def test_without_a_runtime_list_no_candidate_is_no_caller_found_whatever_its_name(self):
        # decisions.md 2026-11-20: neither an NSObject framework ancestor nor
        # the absence of a leading underscore lets a candidate through.
        status, d = self.unreached('iTermPlainObject')
        self.assertEqual(d['methods'], [])
        undecided = by_method(d['undecided'])
        self.assertEqual(sorted(undecided), ['-_underscoredUnusedMethod', '-plainUnusedMethod'])
        for m in undecided.values():
            self.assertEqual(m['reasons'], [ep.NO_RUNTIME_REASON])
        self.assertEqual(status, 3)
        self.assertIn(ep.NO_RUNTIME_INCOMPLETE % 2, d['incomplete'])
        self.assertIn('sdk_selectors.py --runtime-methods', ep.NO_RUNTIME_INCOMPLETE)

    def test_an_nsobject_subclass_with_one_candidate_needs_the_list(self):
        status, d = self.unreached('iTermPickerOwner')
        self.assertEqual(d['methods'], [])
        self.assertEqual([m['method'] for m in d['undecided']], ['-attachBox:picker:'])
        self.assertEqual((status, d['complete']), (3, False))
        self.assertFalse(any('unlikely' in n for n in d['sections'][1]['notes']))
        status, d = self.with_runtime('iTermPickerOwner')
        self.assertEqual([m['method'] for m in d['methods']], ['-attachBox:picker:'])
        self.assertEqual(status, 3)

    def test_with_a_runtime_list_the_kind_must_match_for_an_override(self):
        # The list has +[NSObject plainUnusedMethod] and nothing named
        # _underscoredUnusedMethod: the underscore is no evidence either way.
        status, d = self.with_runtime('iTermPlainObject')
        self.assertEqual([m['method'] for m in d['methods']], ['-_underscoredUnusedMethod'])
        self.assertEqual(d['system'], [])
        weak = by_method(d['weak'])
        self.assertEqual(sorted(weak), ['-plainUnusedMethod'])
        self.assertEqual(weak['-plainUnusedMethod']['reasons'], [
            'weak: no caller found, but a framework class implements a method with this selector: NSObject (class '
            'method); ' + ep.WEAK_WHY + '; from the runtime method list of ' + RUNTIME_LABEL])
        self.assertEqual(d['counts']['weak'], 1)
        self.assertEqual(d['counts']['no_caller'], 1)

    def test_the_weak_heading_in_text(self):
        status, text = self.run_text('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermPlainObject',
                                     '--unreached')
        self.assertIn('\n' + ep.WEAK_HEADING + ': 1\n', text)
        self.assertEqual(ep.WEAK_HEADING, 'weak: no caller found, but a framework class implements a method with this '
                                          'selector')
        self.assertIn('1 as weak (', text.rstrip('\n').split('\n')[-1])

    def test_several_runtime_lists_each_count_and_every_release_is_named(self):
        top = ('--runtime-methods', harness.RUNTIME_FIXTURE, '--runtime-methods', harness.RUNTIME_FIXTURE_OLDER)
        status, d = self.unreached('iTermPlainObject', *top)
        self.assertEqual(d['methods'], [])
        self.assertEqual(by_method(d['system'])['-_underscoredUnusedMethod']['reasons'], [
            "overrides a method that the framework's NSObject implements at run time; not declared in the SDK headers "
            "(private); from the runtime method list of %s, specific to that OS version" % OLDER_LABEL])
        self.assertEqual(status, 3)
        lines = [r for r in d['incomplete'] if 'runtime method list' in r]
        self.assertEqual(lines, [rt_reason(harness.RUNTIME_FIXTURE, harness.RUNTIME_FIXTURE_OLDER)])
        self.assertIn('releases consulted: %s; %s;' % (RUNTIME_LABEL, OLDER_LABEL), lines[0])
        self.assertIn('releases not consulted', lines[0])
        self.assertNotIn('\n', lines[0])

    def test_the_same_list_given_twice_counts_once_and_is_said_once(self):
        status, d = self.unreached('iTermPlainObject', '--runtime-methods', harness.RUNTIME_FIXTURE,
                                   '--runtime-methods', harness.RUNTIME_FIXTURE)
        lines = [r for r in d['incomplete'] if 'releases consulted' in r]
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0].count(RUNTIME_LABEL), 1)
        self.assertIn('releases consulted: %s; releases not consulted' % RUNTIME_LABEL, lines[0])
        self.assertEqual(lines[0].count('given more than once'), 1)
        self.assertEqual(d['weak'][0]['reasons'][0].count('macOS 99.1'), 1)

    def test_not_covered_names_what_each_kind_of_list_cannot_show(self):
        status, d = self.with_runtime('iTermPlainObject')
        notes = d['sections'][1]['notes']
        self.assertIn('not covered: ' + ep.RUNTIME_NOT_COVERED_LIVE, notes)
        self.assertIn('not covered: ' + ep.APP_FRAMEWORKS_NOT_COVERED, notes)
        self.assertNotIn('not covered: ' + ep.RUNTIME_NOT_COVERED_DUMP, notes)
        self.assertIn('Sparkle', ep.APP_FRAMEWORKS_NOT_COVERED)
        status, d = self.unreached('iTermPlainObject', '--runtime-methods', harness.RUNTIME_FIXTURE_OLDER)
        notes = d['sections'][1]['notes']
        self.assertIn('not covered: ' + ep.RUNTIME_NOT_COVERED_DUMP, notes)
        self.assertNotIn('not covered: ' + ep.RUNTIME_NOT_COVERED_LIVE, notes)
        self.assertFalse(any('# frameworks:' in n for n in notes))

    def test_a_category_on_a_framework_class(self):
        status, d = self.with_runtime('NSView')
        mark = '; not declared in the SDK headers (private); from the runtime method list of %s, specific to that OS ' \
               'version' % RUNTIME_LABEL
        system = by_method(d['system'])
        self.assertEqual(system['-fixtureOwnHook']['reasons'], [
            'category method on the framework class NSView, which implements this selector itself at run time: the '
            'category replaces that implementation' + mark])
        self.assertEqual(system['-fixtureAncestorHook']['reasons'], [
            'category method on the framework class NSView, whose ancestor NSResponder implements this selector at run '
            'time: the category overrides it for NSView and its subclasses' + mark])
        self.assertEqual(system['-fixtureSubclassHook']['reasons'], [
            'category method on the framework class NSView with the same selector as a method its framework subclass '
            'NSScrollView implements at run time (1 in all): that implementation shadows the category\'s for its '
            'instances and may reach it through super' + mark])
        for name in ('-fixtureOwnHook', '-fixtureAncestorHook', '-fixtureSubclassHook'):
            self.assertEqual(system[name]['system_group'], ep.CATEGORY_GROUP, name)
        weak = by_method(d['weak'])
        # +[NSScrollView fixtureClassKindHook] is a class method: no collision
        # with the instance method, but a method with the selector.
        self.assertEqual(sorted(weak), ['-fixtureClassKindHook', '-fixtureInformalSelector'])
        self.assertIn('NSFixtureUnrelated (instance method)', weak['-fixtureInformalSelector']['reasons'][0])
        self.assertEqual([m['method'] for m in d['methods']], ['-fixtureNowhereView'])
        status, text = self.run_text('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'NSView', '--unreached')
        self.assertIn('  ' + ep.CATEGORY_GROUP + ': 3\n', text)

    def test_a_category_on_the_root_class_collides_with_class_methods_below_it(self):
        status, d = self.with_runtime('NSObject')
        self.assertIn('-fixtureRootHook', by_method(d['system']))
        self.assertIn('NSView', by_method(d['system'])['-fixtureRootHook']['reasons'][0])
        self.assertIn('-fixtureRootUnused', [m['method'] for m in d['methods']])
        status, d = self.unreached('NSObject')
        self.assertNotIn('-fixtureRootUnused', [m['method'] for m in d['methods']])
        self.assertIn('-fixtureRootUnused', by_method(d['undecided']))

    def test_a_superclass_chain_that_cannot_be_followed_is_not_decided(self):
        for top in ((), ('--runtime-methods', harness.RUNTIME_FIXTURE)):
            status, d = self.unreached('iTermMacroDeclared', *top)
            self.assertEqual(d['methods'], [], top)
            reasons = by_method(d['undecided'])['-macroDeclaredUnusedMethod']['reasons']
            self.assertEqual(reasons, ['not decided: the superclass chain could not be followed to a framework class: '
                                       'no @interface line or Swift class declaration naming a superclass of '
                                       'iTermMacroDeclared was found (text fallback)'], top)
            self.assertEqual(status, 3)
            self.assertEqual(sum(1 for r in d['incomplete'] if 'superclass chain' in r), 1)

    def test_a_framework_class_missing_from_the_runtime_list_is_not_decided(self):
        # The fixture list has no NSWindowController, iTermTabsController's superclass.
        status, d = self.with_runtime('iTermTabsController')
        self.assertEqual(d['methods'], [])
        self.assertEqual(by_method(d['undecided'])['-tabsUnusedMethod']['reasons'], [
            'not decided: the superclass chain could not be followed to a framework class: NSWindowController, the '
            'first class outside the repository, is not in the runtime method list'])
        self.assertEqual(status, 3)

    def test_a_declaration_of_a_class_not_defined_in_the_repository(self):
        status, d = self.unreached('NSWindow')
        self.assertEqual(d['methods'], [])
        self.assertEqual([m['method'] for m in d['elsewhere']], ['-_setFixtureContentHasShadow:'])
        self.assertEqual(d['counts']['elsewhere'], 1)
        self.assertEqual(d['counts']['no_caller'], 0)
        status, text = self.run_text('class', 'NSWindow', '--unreached')
        self.assertIn('\n' + ep.ELSEWHERE_HEADING + ': 1\n', text)
        self.assertEqual(ep.ELSEWHERE_HEADING, 'declared here, defined elsewhere (a prebuilt framework or private '
                                               'framework API)')
        self.assertIn('1 as declared here and defined elsewhere', text.rstrip('\n').split('\n')[-1])

    def test_not_covered_names_private_protocols(self):
        status, d = self.unreached('iTermPlainObject')
        self.assertIn('not covered: requirements of private framework protocols and callbacks registered by name in '
                      'private API are not detectable', d['sections'][1]['notes'])


class ClassTableTest(DatabaseTest):
    """The code database's objc_class table, when it has one, is consulted
    before the text fallback."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        harness.add_objc_class_rows(cls.paths.db, [('iTermMacroDeclared', 'NSObject'),
                                                   ('iTermPlainObject', 'NSWindow')])

    def test_the_table_names_the_superclass(self):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', 'iTermMacroDeclared',
                                  '--unreached')
        self.assertEqual([m['method'] for m in d['methods']], ['-macroDeclaredUnusedMethod'])
        self.assertEqual(d['undecided'], [])

    def test_the_table_wins_over_the_text(self):
        status, d = self.run_json('class', 'iTermPlainObject', '--unreached')
        self.assertEqual(d['methods'], [])
        self.assertEqual(sorted(m['method'] for m in d['undecided']), ['-_underscoredUnusedMethod',
                                                                       '-plainUnusedMethod'])


def add_prebuilt_frameworks(root):
    """Prebuilt framework bundles in the fixture: Kit.framework, whose
    header no unit reads (found by reading the header), declaring the
    selector of -[iTermWidget neverCalled] in a delegate protocol; a Swift
    framework's generated header declaring -publicNeverCalled (a Swift
    class's method); and Kit2.framework, whose header Widget.m imports (so
    the code database records its declarations), declaring
    -probeNeverCalled."""
    def write(rel, text):
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(text)
    write('ThirdParty/Kit.framework/Versions/A/Headers/KitDelegate.h',
          '#import <Foundation/Foundation.h>\n@protocol KitDelegate <NSObject>\n@optional\n'
          '- (void)kit:(id)kit\n    didFinish:(BOOL)finished;\n- (void)neverCalled;\n'
          '@property (nonatomic, readonly) BOOL kitIsReady;\n@end\n')
    write('ThirdParty/Swifty.framework/Versions/A/Headers/Swifty-Swift.h',
          '@protocol SwiftyDelegate\n- (void)publicNeverCalled SWIFT_WARN_UNUSED_RESULT;\n@end\n')
    write('ThirdParty/Kit2.framework/Versions/A/Headers/Kit2.h',
          '#import <Foundation/Foundation.h>\n@protocol Kit2Delegate <NSObject>\n- (void)probeNeverCalled;\n@end\n')
    with open(os.path.join(root, 'sources', 'Widget.m'), 'a') as f:
        f.write('\n#import "../ThirdParty/Kit2.framework/Versions/A/Headers/Kit2.h"\n')


class PrebuiltFrameworkTest(DatabaseTest):
    """A selector declared in a header of a prebuilt framework in the
    repository (ThirdParty/Sparkle.framework, CoreParse.framework and the
    others) can be sent by that framework: SPUUpdaterDelegate's methods
    implemented by the Swift iTermSoftwareUpdater, CPTokenRecogniser's by
    iTermOptionalPathRecognizer. Such a method is never "no caller found"."""
    edit = staticmethod(add_prebuilt_frameworks)

    def unreached(self, cls):
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', cls, '--unreached')
        return d

    def test_objective_c_method_declared_by_a_framework_header_no_unit_reads(self):
        d = self.unreached('iTermWidget')
        self.assertEqual([m['method'] for m in d['methods']], [])
        m = by_method(d['system'])['-neverCalled']
        self.assertEqual(m['system_group'], ep.PREBUILT_GROUP)
        self.assertIn('selector declared by a prebuilt framework in the repository: KitDelegate in '
                      'ThirdParty/Kit.framework (header text)', m['reasons'])

    def test_swift_method_declared_by_a_framework_header(self):
        d = self.unreached('iTermSwiftCaller')
        self.assertEqual([m['method'] for m in d['methods']], ['-run'])
        self.assertIn('-publicNeverCalled', by_method(d['system']))

    def test_declaration_the_code_database_records(self):
        d = self.unreached('iTermProbe')
        self.assertEqual([m['method'] for m in d['methods']], [])
        m = by_method(d['system'])['-probeNeverCalled']
        self.assertIn('selector declared by a prebuilt framework in the repository: Kit2Delegate in '
                      'ThirdParty/Kit2.framework (code database)', m['reasons'])

    def test_header_parser(self):
        found = ep.prebuilt_framework_selectors_from_text(self.root)
        self.assertEqual(found['kit:didFinish:'], {('KitDelegate', 'ThirdParty/Kit.framework')})
        self.assertIn('kitIsReady', found)
        self.assertNotIn('setKitIsReady:', found)
        self.assertIn('publicNeverCalled', found)


def add_outside_class(root):
    """A class outside the migration's scope (ThirdParty/Other) with a method
    nothing calls, for the split of "no caller found" by scope."""
    with open(os.path.join(root, 'ThirdParty', 'Other', 'Other.m'), 'a') as f:
        f.write('\n@interface iTermOutsideThing : NSObject\n- (void)outsideNeverCalled;\n@end\n\n'
                '@implementation iTermOutsideThing\n- (void)outsideNeverCalled {\n}\n@end\n')


def read_tsv(path):
    """[dict] of a TSV file written by all-classes, keyed by its header."""
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.read().rstrip('\n').split('\n')
    header = lines[0].split('\t')
    return [dict(zip(header, line.split('\t'))) for line in lines[1:] if line]


def read_line_of(root, rel, needle):
    with open(os.path.join(root, rel), 'r', encoding='utf-8') as f:
        for n, line in enumerate(f, 1):
            if needle in line:
                return n
    raise AssertionError('%s not in %s' % (needle, rel))


class WholeTreeTest(DatabaseTest):
    """all-classes: every class in one process, the same answer per class as
    class CLASS --unreached."""
    edit = staticmethod(add_outside_class)

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.out_dir = harness.make_temp()
        err = io.StringIO()
        out = io.StringIO()
        with mock.patch('sys.stderr', err):
            cls.status = ep.main(census_args(cls.root, cls.paths) + [
                '--runtime-methods', harness.RUNTIME_FIXTURE, 'all-classes', '--out', cls.out_dir], out=out)
        cls.stdout, cls.stderr = out.getvalue(), err.getvalue()
        cls.table = read_tsv(os.path.join(cls.out_dir, 'methods.tsv'))
        with open(os.path.join(cls.out_dir, 'summary.json'), 'r', encoding='utf-8') as f:
            cls.summary = json.load(f)

    def per_class(self, cls_name):
        """({method: heading}, dossier) from class CLASS --unreached, with the
        runtime list, in the whole-tree mode's heading names."""
        status, d = self.run_json('--runtime-methods', harness.RUNTIME_FIXTURE, 'class', cls_name, '--unreached')
        out = dict((m['method'], 'none') for m in d['methods'])
        for k in ep.REACH_KEYS:
            for m in d[k]:
                out[m['method']] = k
        return out, d

    def test_same_heading_per_method_as_the_class_mode(self):
        classes = sorted(set(r['class'] for r in self.table))
        self.assertIn('iTermWidget', classes)
        self.assertIn('iTermOutsideThing', classes)
        for c in classes:
            expected, d = self.per_class(c)
            got = dict((r['method'], r['heading']) for r in self.table if r['class'] == c and
                       r['heading'] not in ('generated', 'called'))
            self.assertEqual(got, expected, c)
            generated = sum(1 for r in self.table if r['class'] == c and r['heading'] == 'generated')
            self.assertEqual(generated, d['generated_excluded'], c)

    def test_every_class_with_a_definition_outside_tests_and_submodules(self):
        classes = set(r['class'] for r in self.table)
        self.assertIn('iTermGenMessage', classes)  # generated: its methods are counted as such
        self.assertIn('PSMThing', classes)
        self.assertFalse(any(c.endswith('Tests') for c in classes), classes)
        self.assertNotIn('Sub', classes)

    def test_generated_methods_are_listed_and_counted_but_not_under_a_heading(self):
        gen = [r for r in self.table if r['class'] == 'iTermGenMessage']
        self.assertTrue(gen)
        self.assertEqual(set(r['heading'] for r in gen), {'generated'})
        self.assertEqual(self.summary['generated_excluded'], sum(1 for r in self.table if r['heading'] ==
                                                                 'generated'))

    def test_no_caller_found_split_by_scope(self):
        inside = read_tsv(os.path.join(self.out_dir, 'no_caller_in_scope.tsv'))
        outside = read_tsv(os.path.join(self.out_dir, 'no_caller_out_of_scope.tsv'))
        self.assertIn(('iTermOutsideThing', '-outsideNeverCalled'), [(r['class'], r['method']) for r in outside])
        self.assertEqual(set(r['scope'] for r in outside), {'out of scope: ThirdParty'})
        self.assertTrue(inside)
        self.assertEqual(set(r['scope'] for r in inside), {'in scope'})
        none = [(r['class'], r['method']) for r in self.table if r['heading'] == 'none']
        self.assertEqual(sorted(none), sorted([(r['class'], r['method']) for r in inside + outside]))
        self.assertEqual(self.summary['no_caller_in_scope'], len(inside))
        self.assertEqual(self.summary['no_caller_out_of_scope'], len(outside))

    def test_definition_and_counts_columns(self):
        r = next(x for x in self.table if (x['class'], x['method']) == ('iTermOutsideThing', '-outsideNeverCalled'))
        self.assertEqual(r['defined'], 'ThirdParty/Other/Other.m:%d' % (
            read_line_of(self.root, 'ThirdParty/Other/Other.m', '- (void)outsideNeverCalled {')))
        self.assertEqual(r['objc'], '0')
        self.assertIn('no caller found', r['flags'])

    def test_summary_counts_per_heading(self):
        counts = self.summary['counts']
        for k in ('none',) + ep.REACH_KEYS + ('called', 'generated'):
            self.assertEqual(counts.get(k, 0), sum(1 for r in self.table if r['heading'] == k), k)
            self.assertEqual(self.summary['counts_in_scope'][k], sum(1 for r in self.table if r['heading'] == k and
                                                                     r['scope'] == 'in scope'), k)
        self.assertEqual(self.summary['methods'], len(self.table))
        self.assertEqual(self.summary['classes'], len(set(r['class'] for r in self.table)))
        self.assertEqual(self.summary['errors'], [])
        self.assertIn('peak_memory_mb', self.summary)
        self.assertIn('seconds', self.summary)
        with open(os.path.join(self.out_dir, 'summary.txt'), 'r', encoding='utf-8') as f:
            text = f.read()
        self.assertIn('no caller found, in scope: %d' % self.summary['no_caller_in_scope'], text)
        self.assertIn(ep.SDK_HEADING, text)

    def test_status_and_progress(self):
        # A runtime method list always leaves the answer incomplete.
        self.assertEqual(self.status, 3)
        self.assertEqual(self.summary['exit_status'], 3)
        self.assertTrue(any('framework methods are read from' in r for r in self.summary['incomplete']))
        self.assertRegex(self.stderr, r'classes: \d+/\d+')
        self.assertIn('peak memory', self.stderr)

    def test_memory_limit_stops_the_run(self):
        out_dir = harness.make_temp()
        err = io.StringIO()
        with mock.patch('sys.stderr', err):
            status = ep.main(census_args(self.root, self.paths) + [
                '--runtime-methods', harness.RUNTIME_FIXTURE, 'all-classes', '--out', out_dir, '--memory-limit',
                '1'], out=io.StringIO())
        self.assertEqual(status, 2)
        self.assertIn('memory limit', err.getvalue())

    def test_whole_tree_preparation_does_not_change_the_database_file(self):
        before = os.stat(self.paths.db).st_mtime_ns, os.path.getsize(self.paths.db)
        out_dir = harness.make_temp()
        with mock.patch('sys.stderr', io.StringIO()):
            ep.main(census_args(self.root, self.paths) + ['all-classes', '--out', out_dir], out=io.StringIO())
        self.assertEqual((os.stat(self.paths.db).st_mtime_ns, os.path.getsize(self.paths.db)), before)

    def test_primed_text_search_answers_as_the_unprimed_one(self):
        res = ep.Resources(self.root, harness.codedb.repository_files(self.root))
        want = ['biggerFont:', 'openPanel:', 'nothingByThisName:']
        plain = res.text_search(want)
        res.prime_text_search(want + ['other:'])
        self.assertEqual(dict(res.text_search(want)), dict(plain))
        self.assertEqual(dict(res.text_search(['biggerFont:'])), dict((k, v) for k, v in plain.items()
                                                                      if k == 'biggerFont:'))


class GeneratedFilesTest(unittest.TestCase):
    """Core Data's generated files (sources/CoreDataGeneratedFiles/) are
    generated code, out of the migration's scope (README.md section 2), like
    the protocol buffer compiler's: their accessors, which Core Data
    implements at run time, are left out of "no caller found"."""

    def test_core_data_generated_files_are_generated(self):
        import shutil
        import tempfile
        import types
        root = tempfile.mkdtemp(prefix='entry-points-generated-')
        self.addCleanup(shutil.rmtree, root, True)
        os.makedirs(os.path.join(root, 'sources', 'CoreDataGeneratedFiles'))
        os.makedirs(os.path.join(root, 'sources', 'Other'))
        for f in ('sources/CoreDataGeneratedFiles/FooMO+CoreDataProperties.h', 'sources/Other/Foo.h'):
            with open(os.path.join(root, f), 'w') as fh:
                fh.write('//\n//  %s\n' % os.path.basename(f))
        census = types.SimpleNamespace(root=root, _generated={})
        self.assertTrue(ep.Census.is_generated(census, 'sources/CoreDataGeneratedFiles/FooMO+CoreDataProperties.h'))
        self.assertFalse(ep.Census.is_generated(census, 'sources/Other/Foo.h'))
        self.assertTrue(ep.Census.is_generated(census, 'sources/proto/Api.pbobjc.h'))


if __name__ == '__main__':
    unittest.main()
