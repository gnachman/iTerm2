#!/usr/bin/env python3
"""Tests for the other Xcode projects in the code database: the capture of
the in-repository projects whose frameworks or tools the app's build does not
compile (capture_compile_commands.sh --other-projects, other_projects.json),
the merge of their fragments into the compile database (codedb.py cdb), and
the out-of-date checks for them.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_codedb_projects.py'

No xcodebuild and no extractor: fragments are written by hand, and the
capture script runs against a stub xcodebuild in a scratch tree.
"""

import json
import os
import shutil
import subprocess
import sys
import time
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.path.dirname(HERE)
sys.path.insert(0, CODEDB_DIR)
sys.path.insert(0, HERE)

import codedb  # noqa: E402
import test_codedb as base  # noqa: E402

SDK = base.SDK
OBJ = base.OBJ
CP_OBJ = ('/r/tmp/codedb/other-build/ColorPicker/obj/ColorPicker.build/Debug/%s.build/Objects-normal/arm64/%s')
SA_OBJ = ('/r/tmp/codedb/other-build/SignedArchive/obj/SignedArchive.build/Debug/%s.build/Objects-normal/arm64/%s')

SPEC = [
    {'name': 'ColorPicker', 'project': 'ColorPicker/ColorPicker.xcodeproj', 'targets': ['ColorPicker'],
     'configuration': 'Debug', 'settings': []},
    {'name': 'SignedArchive', 'project': 'SignedArchive/SignedArchive.xcodeproj', 'targets': ['sign', 'verify'],
     'configuration': 'Debug', 'settings': ['MACOSX_DEPLOYMENT_TARGET=13.0']},
]


def tearDownModule():
    base.tearDownModule()


def projects(spec=None):
    return codedb.parse_other_projects(json.dumps(SPEC if spec is None else spec))


def project_named(name, spec=None):
    return [p for p in projects(spec) if p.name == name][0]


def mark_other_captured(d, root, p, captured_at='2026-11-21T00:00:00Z'):
    """What capture_compile_commands.sh --other-projects writes next to an
    other project's fragments when its build succeeds."""
    with open(os.path.join(d, '.captured'), 'w') as f:
        f.write(captured_at + '\n')
    record = codedb.other_capture_record(root, p)
    record['captured_at'] = captured_at
    with open(os.path.join(d, '.capture-record'), 'w') as f:
        json.dump(record, f)


def main_fragments(d):
    frags = os.path.join(d, 'f')
    os.makedirs(frags)
    base.write_fragment(frags, 'a.json', '/r/sources/A.m', OBJ % ('iTerm2SharedARC', 'A.o'))
    base.mark_captured(frags)
    return frags


def other_fragments(d, root='/r'):
    """Fragments of the two spec projects as their builds write them."""
    other = os.path.join(d, 'other')
    cp = os.path.join(other, 'ColorPicker')
    sa = os.path.join(other, 'SignedArchive')
    os.makedirs(cp)
    os.makedirs(sa)
    base.write_fragment(cp, 'color.json', '/r/ColorPicker/ColorPicker/CPKColor.m', CP_OBJ % ('ColorPicker', 'CPKColor.o'))
    # The version file Xcode generates in the capture's build directory.
    base.write_fragment(cp, 'vers.json', '/r/tmp/codedb/other-build/ColorPicker/obj/ColorPicker.build/Debug/'
                        'ColorPicker.build/DerivedSources/ColorPicker_vers.c',
                        CP_OBJ % ('ColorPicker', 'ColorPicker_vers.o'), lang='-xc')
    # A target the spec does not keep.
    base.write_fragment(cp, 'tests.json', '/r/ColorPicker/ColorPickerTests/T.m', CP_OBJ % ('ColorPickerTests', 'T.o'))
    base.write_fragment(cp, 'hdr.json', '/r/ColorPicker/ColorPicker/P.pch', CP_OBJ % ('ColorPicker', 'P.pch.gch'),
                        lang='-xobjective-c-header')
    mark_other_captured(cp, root, project_named('ColorPicker'))
    base.write_fragment(sa, 'sign.json', '/r/SignedArchive/sign/main.m', SA_OBJ % ('sign', 'main.o'))
    base.write_fragment(sa, 'verify.json', '/r/SignedArchive/verify/main.m', SA_OBJ % ('verify', 'main.o'))
    # The framework target the tools link: the app's build already compiles
    # these files, and the spec does not keep it.
    base.write_fragment(sa, 'trust.json', '/r/SignedArchive/SignedArchive/SIGTrust.m',
                        SA_OBJ % ('SignedArchive', 'SIGTrust.o'))
    mark_other_captured(sa, root, project_named('SignedArchive'))
    return other


def build(frags, out, other=None, spec=None, **kw):
    return codedb.build_cdb('/r', frags, out, '/mc', sdk=(SDK, '1'), log=lambda m: None, other_fragments=other,
                            other_projects=projects(spec), **kw)


class SpecTest(unittest.TestCase):
    def test_checked_in_spec_names_the_projects(self):
        names = [(p.name, p.project, p.targets) for p in codedb.read_other_projects()]
        self.assertEqual(names, [
            ('ColorPicker', 'ColorPicker/ColorPicker.xcodeproj', ('ColorPicker',)),
            ('CoreParse', 'submodules/CoreParse/CoreParse.xcodeproj', ('CoreParse',)),
            ('SignedArchive', 'SignedArchive/SignedArchive.xcodeproj', ('sign', 'verify', 'extract', 'resign')),
        ])

    def test_bad_specs_are_refused(self):
        for bad in ('[{"name": "X"}]', '{}', '[{"name": "A B", "project": "a.xcodeproj", "targets": ["t"], '
                    '"configuration": "Debug", "settings": []}]',
                    '[{"name": "A", "project": "/abs/a.xcodeproj", "targets": ["t"], "configuration": "Debug", '
                    '"settings": []}]',
                    '[{"name": "A", "project": "a.xcodeproj", "targets": [], "configuration": "Debug", '
                    '"settings": []}]',
                    '[{"name": ".A", "project": "a.xcodeproj", "targets": ["t"], "configuration": "Debug", '
                    '"settings": []}]',
                    '[{"name": "A", "project": "a.xcodeproj", "targets": ["t"], "configuration": "Debug", '
                    '"settings": ["X=$(echo hi)"]}]',
                    '[{"name": "A", "project": "a.xcodeproj", "targets": ["t"], "configuration": "Debug", '
                    '"settings": ["X=$HOME"]}]'):
            with self.assertRaises(codedb.CodeDBError, msg=bad):
                codedb.parse_other_projects(bad)

    def test_a_build_setting_reference_is_allowed(self):
        p = codedb.parse_other_projects('[{"name": "A", "project": "a.xcodeproj", "targets": ["t"], '
                                        '"configuration": "Debug", "settings": ["VALID_ARCHS=$(ARCHS)"]}]')[0]
        self.assertEqual(p.settings, ('VALID_ARCHS=$(ARCHS)',))

    def test_coreparse_is_captured_from_the_submodule_the_app_embeds(self):
        p = [x for x in codedb.read_other_projects() if x.name == 'CoreParse'][0]
        self.assertEqual(p.project, 'submodules/CoreParse/CoreParse.xcodeproj')
        self.assertEqual(p.settings, ('VALID_ARCHS=$(ARCHS)',))
        self.assertEqual(p.stale_copy, 'ThirdParty/CoreParse')

    def test_spec_digest_changes_with_the_spec(self):
        a = project_named('SignedArchive')
        changed = [dict(e) for e in SPEC]
        changed[1]['targets'] = ['sign']
        self.assertNotEqual(codedb.other_spec_digest(a), codedb.other_spec_digest(project_named('SignedArchive',
                                                                                                changed)))

    def test_target_names_say_the_project(self):
        self.assertEqual(codedb.other_target_name(project_named('SignedArchive'), 'sign'), 'SignedArchive:sign')


class MergeTest(unittest.TestCase):
    def setUp(self):
        self.d = base.make_temp('codedb-other-')
        self.frags = main_fragments(self.d)
        self.other = other_fragments(self.d)
        self.out = os.path.join(self.d, 'cdb.jsonl')

    def entries(self):
        return [e for e in codedb.read_cdb(self.out) if not e.get('meta')]

    def test_other_projects_are_merged_with_their_target_and_project(self):
        meta = build(self.frags, self.out, self.other)
        got = sorted((e['target'], e['file'], e.get('project'), e['configuration'], e['variant'])
                     for e in self.entries())
        self.assertEqual(got, [
            ('ColorPicker:ColorPicker', 'ColorPicker/ColorPicker/CPKColor.m', 'ColorPicker/ColorPicker.xcodeproj',
             'Debug', ''),
            ('SignedArchive:sign', 'SignedArchive/sign/main.m', 'SignedArchive/SignedArchive.xcodeproj', 'Debug', ''),
            ('SignedArchive:verify', 'SignedArchive/verify/main.m', 'SignedArchive/SignedArchive.xcodeproj', 'Debug',
             ''),
            ('iTerm2SharedARC', 'sources/A.m', None, 'Development', 'Variant-NoSanitizers'),
        ])
        # The commands are translated as the main capture's are.
        cp = [e for e in self.entries() if e['target'] == 'ColorPicker:ColorPicker'][0]
        self.assertEqual(cp['arguments'], ['-xobjective-c', '/r/ColorPicker/ColorPicker/CPKColor.m', '-isysroot', SDK,
                                           '-fmodules-cache-path=/mc', '-w'])
        # The main capture's facts are unchanged.
        self.assertEqual(meta['skipped'], {'header': 0, 'sanitizer variant': 0, 'outside the repository': 0,
                                           'generated under Build/': 0, 'unknown output': 0})
        o = meta['other_projects']
        self.assertEqual(sorted(o), ['ColorPicker', 'SignedArchive'])
        self.assertEqual(o['ColorPicker']['units'], 1)
        self.assertEqual(o['ColorPicker']['project'], 'ColorPicker/ColorPicker.xcodeproj')
        self.assertTrue(o['ColorPicker']['captured'])
        self.assertEqual(o['ColorPicker']['captured_at'], '2026-11-21T00:00:00Z')
        self.assertEqual(o['ColorPicker']['skipped'], {'header': 1, 'generated in the build directory': 1,
                                                       'target not kept': 1, 'outside the repository': 0,
                                                       'sanitizer variant': 0, 'unknown output': 0})
        self.assertEqual(o['SignedArchive']['skipped']['target not kept'], 1)
        self.assertEqual(o['SignedArchive']['spec_sha256'], codedb.other_spec_digest(project_named('SignedArchive')))
        self.assertEqual(o['SignedArchive']['targets'], ['sign', 'verify'])

    def test_a_project_not_captured_contributes_nothing(self):
        shutil.rmtree(os.path.join(self.other, 'SignedArchive'))
        meta = build(self.frags, self.out, self.other)
        self.assertEqual(sorted(e['target'] for e in self.entries()), ['ColorPicker:ColorPicker', 'iTerm2SharedARC'])
        self.assertEqual(meta['other_projects']['SignedArchive'], {
            'project': 'SignedArchive/SignedArchive.xcodeproj', 'captured': False})

    def test_without_other_fragments_the_compile_database_is_as_before(self):
        meta = build(self.frags, self.out, None)
        self.assertEqual([e['target'] for e in self.entries()], ['iTerm2SharedARC'])
        self.assertNotIn('other_projects', meta)

    def test_an_unfinished_capture_is_refused(self):
        os.remove(os.path.join(self.other, 'ColorPicker', '.captured'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            build(self.frags, self.out, self.other)
        self.assertIn('ColorPicker', str(cm.exception))
        self.assertIn('did not finish', str(cm.exception))
        self.assertFalse(os.path.exists(self.out))

    def test_a_capture_without_a_record_is_refused(self):
        os.remove(os.path.join(self.other, 'ColorPicker', '.capture-record'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            build(self.frags, self.out, self.other)
        self.assertIn('no capture record', str(cm.exception))

    def test_a_capture_of_another_project_is_refused(self):
        path = os.path.join(self.other, 'ColorPicker', '.capture-record')
        with open(path) as f:
            record = json.load(f)
        record['project'] = 'Elsewhere/Elsewhere.xcodeproj'
        with open(path, 'w') as f:
            json.dump(record, f)
        with self.assertRaises(codedb.CodeDBError) as cm:
            build(self.frags, self.out, self.other)
        self.assertIn('Elsewhere/Elsewhere.xcodeproj', str(cm.exception))

    def test_losing_an_other_project_is_refused_like_a_target(self):
        build(self.frags, self.out, self.other)
        with open(self.out) as f:
            before = f.read()
        shutil.rmtree(os.path.join(self.other, 'ColorPicker'))
        with self.assertRaises(codedb.CodeDBError) as cm:
            build(self.frags, self.out, self.other)
        self.assertIn('ColorPicker/ColorPicker/CPKColor.m (ColorPicker:ColorPicker)', str(cm.exception))
        with open(self.out) as f:
            self.assertEqual(f.read(), before)
        build(self.frags, self.out, self.other, accept_removals=True)
        self.assertNotIn('ColorPicker:ColorPicker', [e['target'] for e in self.entries()])

    def test_ensure_cdb_rebuilds_when_an_other_project_is_captured_again(self):
        root = os.path.join(self.d, 'root')
        os.makedirs(root)
        paths = codedb.Paths(root, cdb=self.out, fragments=self.frags, other_fragments=self.other)
        built = []
        real = codedb.build_cdb
        codedb.build_cdb = lambda *a, **k: built.append(k.get('other_fragments'))
        self.addCleanup(setattr, codedb, 'build_cdb', real)
        with open(self.out, 'w') as f:
            f.write(json.dumps({'meta': True, 'sdk_path': codedb.current_sdk()[0],
                                'sdk_version': codedb.current_sdk()[1]}) + '\n')
        old = time.time() - 100
        for p in (os.path.join(self.frags, '.captured'), os.path.join(self.other, 'ColorPicker', '.captured'),
                  os.path.join(self.other, 'SignedArchive', '.captured')):
            os.utime(p, (old, old))
        # Built after every input, codedb.py and other_projects.json included.
        built_at = time.time() + 50
        os.utime(self.out, (built_at, built_at))
        codedb.ensure_cdb(paths, log=lambda m: None)
        self.assertEqual(built, [])
        os.utime(os.path.join(self.other, 'ColorPicker', '.captured'), (built_at + 10, built_at + 10))
        codedb.ensure_cdb(paths, log=lambda m: None)
        self.assertEqual(built, [self.other])


def write_other_project(root, project, files_by_target, settings=''):
    """An other project's project.pbxproj: each target compiles the given
    files (paths relative to the project's directory, as Xcode's SOURCE_ROOT
    is), and one build configuration with the given settings text."""
    objects = ['ROOT = {isa = PBXGroup; children = (); sourceTree = "<group>"; };',
               'CFG = {isa = XCBuildConfiguration; name = Debug; buildSettings = {%s}; };' % settings,
               'CL = {isa = XCConfigurationList; buildConfigurations = (CFG); };',
               'PRJ = {isa = PBXProject; buildConfigurationList = CL; mainGroup = ROOT; };']
    n = 0
    for target in sorted(files_by_target):
        build_files = []
        for f in sorted(files_by_target[target]):
            n += 1
            objects.append('F%d = {isa = PBXFileReference; path = "%s"; sourceTree = SOURCE_ROOT; };' % (n, f))
            objects.append('B%d = {isa = PBXBuildFile; fileRef = F%d; };' % (n, n))
            build_files.append('B%d' % n)
        objects.append('P_%s = {isa = PBXSourcesBuildPhase; files = (%s); };' % (target, ', '.join(build_files)))
        objects.append('T_%s = {isa = PBXNativeTarget; name = %s; buildPhases = (P_%s); };' % (target, target, target))
    d = os.path.join(root, project)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'project.pbxproj'), 'w') as f:
        f.write('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjects = {\n\t\t%s\n\t};\n\trootObject = PRJ;\n}\n'
                % '\n\t\t'.join(objects))
    for files in files_by_target.values():
        for rel in files:
            p = os.path.join(os.path.dirname(d), rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, 'a').close()


class CoverageTest(unittest.TestCase):
    """check_cdb_against_project and the coverage queries use, for the other
    projects: their file lists against their own project files, their build
    settings and their spec, as of their capture."""

    def setUp(self):
        self.root = os.path.join(base.make_temp('codedb-othercov-'), 'repo')
        os.makedirs(os.path.join(self.root, 'sources'))
        open(os.path.join(self.root, 'sources', 'A.m'), 'w').close()
        base.write_project(self.root, {'App': ['sources/A.m']})
        write_other_project(self.root, 'ColorPicker/ColorPicker.xcodeproj',
                            {'ColorPicker': ['ColorPicker/CPKColor.m', 'ColorPicker/CPKWell.m'],
                             'ColorPickerTests': ['ColorPickerTests/T.m']})
        self.spec = [SPEC[0]]
        self.cdb = os.path.join(self.root, 'cdb.jsonl')
        self.write_cdb()

    def write_cdb(self, files=('ColorPicker/ColorPicker/CPKColor.m', 'ColorPicker/ColorPicker/CPKWell.m'),
                  captured=True, spec=None):
        p = project_named('ColorPicker', spec or self.spec)
        record = codedb.other_capture_record(self.root, p)
        info = {'project': p.project, 'captured': True, 'targets': list(p.targets),
                'build_settings_sha256': record['build_settings_sha256'], 'spec_sha256': record['spec_sha256'],
                'captured_at': '2026-11-21T00:00:00Z', 'units': len(files), 'skipped': {}}
        meta = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(self.root),
                'other_projects': {'ColorPicker': info if captured else {'project': p.project, 'captured': False}}}
        with open(self.cdb, 'w') as f:
            f.write(json.dumps(meta) + '\n')
            f.write(json.dumps({'target': 'App', 'file': 'sources/A.m', 'arguments': []}) + '\n')
            if captured:
                for rel in files:
                    f.write(json.dumps({'target': 'ColorPicker:ColorPicker', 'file': rel, 'arguments': [],
                                        'project': p.project}) + '\n')

    def check(self):
        log = []
        out_of_date = codedb.check_cdb_against_project(self.root, self.cdb, log=log.append,
                                                       other_projects=projects(self.spec))
        return out_of_date, log

    def test_complete(self):
        out_of_date, log = self.check()
        self.assertFalse(out_of_date, log)
        self.assertFalse([line for line in log if 'Swift package' in line], log)
        c = codedb.compute_coverage(self.root, self.cdb, other_projects=projects(self.spec))[0]
        self.assertEqual(c.unchecked, [])
        # The test target the spec does not keep is not parsed; the kept
        # files are.
        self.assertEqual(codedb.not_parsed_files(c.not_parsed), ['ColorPicker/ColorPickerTests/T.m'])
        self.assertEqual(c.others['captured'], [('ColorPicker', 'ColorPicker/ColorPicker.xcodeproj', 2)])

    def test_a_file_added_to_the_other_project_is_not_covered(self):
        write_other_project(self.root, 'ColorPicker/ColorPicker.xcodeproj',
                            {'ColorPicker': ['ColorPicker/CPKColor.m', 'ColorPicker/CPKWell.m',
                                             'ColorPicker/CPKNew.m']})
        out_of_date, log = self.check()
        self.assertTrue(out_of_date)
        self.assertIn('  in the project, not in the compile database: ColorPicker/ColorPicker/CPKNew.m '
                      '(ColorPicker:ColorPicker)', log)

    def test_a_file_removed_from_the_other_project_is_extra(self):
        write_other_project(self.root, 'ColorPicker/ColorPicker.xcodeproj',
                            {'ColorPicker': ['ColorPicker/CPKColor.m']})
        out_of_date, log = self.check()
        self.assertTrue(out_of_date)
        self.assertIn('  in the compile database, not in the project: ColorPicker/ColorPicker/CPKWell.m '
                      '(ColorPicker:ColorPicker)', log)

    def test_changed_build_settings_of_the_other_project(self):
        write_other_project(self.root, 'ColorPicker/ColorPicker.xcodeproj',
                            {'ColorPicker': ['ColorPicker/CPKColor.m', 'ColorPicker/CPKWell.m'],
                             'ColorPickerTests': ['ColorPickerTests/T.m']}, settings='GCC_OPTIMIZATION_LEVEL = s;')
        out_of_date, log = self.check()
        self.assertTrue(out_of_date)
        self.assertIn('COMPILE DATABASE OUT OF DATE: the build settings of ColorPicker/ColorPicker.xcodeproj changed '
                      'since it was captured; run capture_compile_commands.sh --other-projects', log)

    def test_changed_spec(self):
        spec = [dict(SPEC[0], settings=['GCC_OPTIMIZATION_LEVEL=s'])]
        self.write_cdb(spec=spec)
        out_of_date, log = self.check()
        self.assertTrue(out_of_date)
        self.assertIn('COMPILE DATABASE OUT OF DATE: how ColorPicker is captured (other_projects.json) changed since '
                      'it was captured; run capture_compile_commands.sh --other-projects', log)

    def test_a_project_never_captured_is_named_and_stays_not_parsed(self):
        self.write_cdb(captured=False)
        out_of_date, log = self.check()
        self.assertFalse(out_of_date, log)
        self.assertIn('other project ColorPicker (ColorPicker/ColorPicker.xcodeproj) is not captured: its files are '
                      'not parsed; run capture_compile_commands.sh --other-projects', log)
        c = codedb.compute_coverage(self.root, self.cdb, other_projects=projects(self.spec))[0]
        self.assertEqual(c.others['not_captured'], [('ColorPicker', 'ColorPicker/ColorPicker.xcodeproj')])
        self.assertIn('ColorPicker/ColorPicker/CPKColor.m', codedb.not_parsed_files(c.not_parsed))

    def test_a_project_of_the_spec_that_is_not_in_the_tree_is_ignored(self):
        shutil.rmtree(os.path.join(self.root, 'ColorPicker'))
        meta_only = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(self.root)}
        with open(self.cdb, 'w') as f:
            f.write(json.dumps(meta_only) + '\n')
            f.write(json.dumps({'target': 'App', 'file': 'sources/A.m', 'arguments': []}) + '\n')
        out_of_date, log = self.check()
        self.assertFalse(out_of_date, log)
        self.assertFalse([line for line in log if 'ColorPicker' in line], log)

    def test_a_project_not_checked_out_is_named_as_never_captured(self):
        # A submodule's directory with no project file (a lane, or a
        # submodule not initialized): not an error.
        shutil.rmtree(os.path.join(self.root, 'ColorPicker', 'ColorPicker.xcodeproj'))
        meta_only = {'meta': True, 'build_settings_sha256': codedb.build_settings_digest(self.root)}
        with open(self.cdb, 'w') as f:
            f.write(json.dumps(meta_only) + '\n')
            f.write(json.dumps({'target': 'App', 'file': 'sources/A.m', 'arguments': []}) + '\n')
        out_of_date, log = self.check()
        self.assertFalse(out_of_date, log)
        self.assertIn('other project ColorPicker (ColorPicker/ColorPicker.xcodeproj) is not captured: ColorPicker is '
                      'not checked out here', log)
        c = codedb.compute_coverage(self.root, self.cdb, other_projects=projects(self.spec))[0]
        self.assertEqual(c.others['not_checked_out'], [('ColorPicker', 'ColorPicker/ColorPicker.xcodeproj')])

    def test_the_cache_sees_a_change_to_the_other_project(self):
        cache = os.path.join(self.root, 'cache.json')
        spec = projects(self.spec)
        c = codedb.coverage(self.root, self.cdb, cache_path=cache, other_projects=spec)
        self.assertEqual(c.not_covered, [])
        write_other_project(self.root, 'ColorPicker/ColorPicker.xcodeproj',
                            {'ColorPicker': ['ColorPicker/CPKColor.m', 'ColorPicker/CPKWell.m',
                                             'ColorPicker/CPKNew.m']})
        c = codedb.coverage(self.root, self.cdb, cache_path=cache, other_projects=spec)
        self.assertEqual(c.not_covered, [('ColorPicker/ColorPicker/CPKNew.m', ['ColorPicker:ColorPicker'])])


class CaptureScriptTest(unittest.TestCase):
    """capture_compile_commands.sh --other-projects, in a scratch tree, with
    a stub xcodebuild that writes one fragment per run into the directory
    named by OTHER_CFLAGS, appends its arguments to stub-args, and fails for
    the project named by $STUB_FAIL."""

    def setUp(self):
        d = base.make_temp('codedb-othercap-')
        self.root = os.path.join(d, 'root')
        script_dir = os.path.join(self.root, 'tools', 'swift_migration', 'codedb')
        os.makedirs(script_dir)
        for n in ('capture_compile_commands.sh', 'codedb.py', 'swiftdb.py'):
            shutil.copy(os.path.join(CODEDB_DIR, n), script_dir)
        # A third project whose directory exists but whose project file does
        # not, as a submodule that is not checked out (a lane); and a stale
        # tracked copy of ColorPicker that differs from it.
        spec = [dict(SPEC[0], stale_copy='OldColorPicker'), SPEC[1],
                {'name': 'Sub', 'project': 'submodules/Sub/Sub.xcodeproj', 'targets': ['Sub'],
                 'configuration': 'Debug', 'settings': []}]
        with open(os.path.join(script_dir, 'other_projects.json'), 'w') as f:
            json.dump(spec, f)
        os.makedirs(os.path.join(self.root, 'submodules', 'Sub'))
        self.script = os.path.join(script_dir, 'capture_compile_commands.sh')
        base.write_project(self.root, {'App': ['sources/A.m']})
        write_other_project(self.root, 'ColorPicker/ColorPicker.xcodeproj', {'ColorPicker': ['ColorPicker/CPKColor.m']})
        write_other_project(self.root, 'OldColorPicker/ColorPicker.xcodeproj', {'ColorPicker': ['ColorPicker/Old.m']})
        write_other_project(self.root, 'SignedArchive/SignedArchive.xcodeproj', {'sign': ['sign/main.m']})
        self.work = os.path.join(self.root, 'tmp', 'codedb')
        self.main_frags = os.path.join(self.work, 'cdb-fragments')
        os.makedirs(self.main_frags)
        with open(os.path.join(self.main_frags, '.captured'), 'w') as f:
            f.write('then')
        # An earlier capture of ColorPicker, and a stale partial one.
        self.cp = os.path.join(self.work, 'other-fragments', 'ColorPicker')
        os.makedirs(self.cp)
        os.makedirs(self.cp + '.partial')
        for path in (os.path.join(self.cp, 'old.json'), os.path.join(self.cp, '.captured'),
                     os.path.join(self.cp + '.partial', 'stale.json')):
            with open(path, 'w') as f:
                f.write('{}')
        stub = os.path.join(d, 'stub')
        os.mkdir(stub)
        self.stub_args = os.path.join(d, 'stub-args')
        base.write_executable(os.path.join(stub, 'xcodebuild'),
                              '#!/bin/sh\nfor a in "$@"; do case "$a" in OTHER_CFLAGS=*) dir="${a##* }";; '
                              'SYMROOT=*) sym="${a#SYMROOT=}";; esac; done\n'
                              'echo "$@" >> "%s"\n'
                              'echo "{}" > "$dir/new.json"\n'
                              'mkdir -p "$sym" && echo built > "$sym/product"\n'
                              'case "$*" in *"$STUB_FAIL"*) if [ -n "$STUB_FAIL" ]; then echo "error: stub" >&2; '
                              'exit 65; fi;; esac\n'
                              'exit 0\n' % self.stub_args)
        self.env = dict(os.environ, PATH=stub + os.pathsep + os.environ['PATH'])

    def run_capture(self, fail=''):
        return subprocess.run([self.script, '--other-projects'], env=dict(self.env, STUB_FAIL=fail),
                              capture_output=True, text=True, timeout=110)

    def invocations(self):
        with open(self.stub_args) as f:
            return [line.split() for line in f.read().splitlines()]

    def test_each_project_is_built_into_its_own_directories(self):
        r = self.run_capture()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        runs = self.invocations()
        # One build per kept target, each through the scheme of that name
        # (xcodebuild takes -derivedDataPath only with -scheme).
        self.assertEqual(len(runs), 3)
        cp, sa, sa2 = runs
        self.assertEqual(cp[:8], ['-project', 'ColorPicker/ColorPicker.xcodeproj', '-scheme', 'ColorPicker',
                                  '-configuration', 'Debug', '-derivedDataPath',
                                  '%s/other-build/ColorPicker/dd' % self.work])
        self.assertIn('build', cp)
        self.assertNotIn('clean', cp)
        self.assertIn('SYMROOT=%s/other-build/ColorPicker' % self.work, cp)
        self.assertIn('OBJROOT=%s/other-build/ColorPicker/obj' % self.work, cp)
        # Xcode's precompiled headers go there too, not under the project.
        self.assertIn('SHARED_PRECOMPS_DIR=%s/other-build/ColorPicker/pch' % self.work, cp)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', cp)
        self.assertIn('COMPILER_INDEX_STORE_ENABLE=NO', cp)
        self.assertEqual(sa[:4], ['-project', 'SignedArchive/SignedArchive.xcodeproj', '-scheme', 'sign'])
        self.assertEqual(sa2[:4], ['-project', 'SignedArchive/SignedArchive.xcodeproj', '-scheme', 'verify'])
        self.assertIn('MACOSX_DEPLOYMENT_TARGET=13.0', sa)
        self.assertIn('MACOSX_DEPLOYMENT_TARGET=13.0', sa2)
        # The project not checked out is named and not built.
        self.assertIn('Sub: not captured: submodules/Sub is not checked out here', r.stderr)
        self.assertNotIn('Sub', ' '.join(' '.join(x) for x in runs))
        self.assertIn('-gen-cdb-fragment-path', ' '.join(sa))
        self.assertIn('%s/other-fragments/SignedArchive.partial' % self.work, ' '.join(sa))

    def test_success_replaces_each_capture_with_a_record(self):
        r = self.run_capture()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sorted(os.listdir(self.cp)), ['.capture-record', '.captured', 'new.json'])
        self.assertFalse(os.path.exists(self.cp + '.partial'))
        with open(os.path.join(self.cp, '.capture-record')) as f:
            record = json.load(f)
        p = project_named('ColorPicker')
        self.assertEqual(record['project'], 'ColorPicker/ColorPicker.xcodeproj')
        self.assertEqual(record['spec_sha256'], codedb.other_spec_digest(p))
        self.assertEqual(record['build_settings_sha256'], codedb.build_settings_digest(self.root, p.project))
        self.assertEqual(sorted(os.listdir(os.path.join(self.work, 'other-fragments', 'SignedArchive'))),
                         ['.capture-record', '.captured', 'new.json'])
        # The main capture is not touched.
        self.assertEqual(os.listdir(self.main_frags), ['.captured'])
        self.assertFalse(os.path.exists(os.path.join(self.work, 'codedb.lock')))

    def test_the_build_directory_is_emptied_first(self):
        old = os.path.join(self.work, 'other-build', 'ColorPicker', 'leftover.o')
        os.makedirs(os.path.dirname(old))
        open(old, 'w').close()
        r = self.run_capture()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(os.path.exists(old))
        self.assertTrue(os.path.exists(os.path.join(self.work, 'other-build', 'ColorPicker', 'product')))

    def test_a_failed_project_keeps_its_previous_capture_and_the_others_proceed(self):
        r = self.run_capture(fail='ColorPicker.xcodeproj')
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(sorted(os.listdir(self.cp)), ['.captured', 'old.json'])
        self.assertIn('ColorPicker', r.stderr)
        self.assertEqual(sorted(os.listdir(os.path.join(self.work, 'other-fragments', 'SignedArchive'))),
                         ['.capture-record', '.captured', 'new.json'])
        # The main capture is not touched either.
        self.assertEqual(os.listdir(self.main_frags), ['.captured'])

    def test_a_submodule_project_without_its_swiftpm_directory_is_not_built(self):
        # xcodebuild would create project.xcworkspace/xcshareddata/swiftpm in
        # it, and nothing may be written inside submodules/.
        write_other_project(self.root, 'submodules/Sub/Sub.xcodeproj', {'Sub': ['Sub.m']})
        r = self.run_capture()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('Sub: not captured: xcodebuild would create submodules/Sub/Sub.xcodeproj/project.xcworkspace/'
                      'xcshareddata/swiftpm inside the submodule', r.stderr)
        self.assertNotIn('-scheme Sub', ' '.join(' '.join(x) for x in self.invocations()))
        os.makedirs(os.path.join(self.root, 'submodules/Sub/Sub.xcodeproj/project.xcworkspace/xcshareddata/swiftpm'))
        os.remove(self.stub_args)
        r = self.run_capture()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('-scheme Sub', ' '.join(' '.join(x) for x in self.invocations()))

    def test_exits_2_while_another_holds_the_lock(self):
        lock = codedb.Lock(os.path.join(self.work, 'codedb.lock'), 'codedb.py update', log=lambda m: None)
        lock.acquire()
        try:
            r = self.run_capture()
        finally:
            lock.release()
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertFalse(os.path.exists(self.stub_args), 'a build ran')

    def test_other_projects_command_prints_the_spec_for_the_script(self):
        r = subprocess.run([sys.executable, '-B', os.path.join(self.root, 'tools', 'swift_migration', 'codedb',
                                                               'codedb.py'), '--root', self.root, 'other-projects'],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            'ColorPicker\tColorPicker/ColorPicker.xcodeproj\tDebug\tColorPicker\t',
            'SignedArchive\tSignedArchive/SignedArchive.xcodeproj\tDebug\tsign verify\tMACOSX_DEPLOYMENT_TARGET=13.0',
        ])
        self.assertIn('Sub: not captured: submodules/Sub is not checked out here', r.stderr)
        self.assertIn('warning: OldColorPicker differs from ColorPicker (the project captured for ColorPicker); it is '
                      'not what the app embeds', r.stderr)


if __name__ == '__main__':
    unittest.main()
