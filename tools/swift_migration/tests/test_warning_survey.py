"""Tests for tools/swift_migration/warning_survey.py and sources/Infrastructure/iTermStrictWarnings.h.

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_warning_survey.py

The parser, deduplication, command and comparison tests need no compiler. The
tests of the header and the end-to-end survey compile the small sources in
fixtures/warning_survey with xcrun clang and are skipped, with a message
saying so, when it is not available:

- bad/<flag>.m: one file per flag of iTermStrictWarnings.h (named after the
  flag without -W). Its first line names the diagnostic flag it must produce
  ("// expect: -Wfoo"); "// arch: x86_64" names the architecture it needs,
  "// arc" asks for ARC, and "// clean-on: arm64" says it must compile on
  that architecture even with the header. Each must fail with the header and
  compile without it.
- clean.c, clean.m, clean.mm: import the header and must compile with
  -Werror, so that every flag in it is known to this compiler, in C,
  Objective-C and Objective-C++.
- via_header.m: imports a header that imports iTermStrictWarnings.h, which the
  header's own check turns into an error.
- scope/: how the pragmas interact with headers imported before and after,
  and with a macro defined before the import and expanded after it.
- units/: two C files that include one header with a warning in it, for the
  end-to-end survey's deduplication.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(TOOL_DIR))
FIXTURES = os.path.join(HERE, 'fixtures', 'warning_survey')
HEADER_DIR = os.path.join(ROOT, 'sources', 'Infrastructure')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import warning_survey as ws  # noqa: E402


def have_clang():
    try:
        return subprocess.run(['xcrun', '--find', 'clang'], capture_output=True).returncode == 0
    except OSError:
        return False


HAVE_CLANG = have_clang()
if not HAVE_CLANG:
    print('test_warning_survey: xcrun clang not found; the compiler tests are SKIPPED', file=sys.stderr)
needs_clang = unittest.skipUnless(HAVE_CLANG, 'xcrun clang is not available')


def parse(text, directory='/repo'):
    return ws.parse_lines(io.StringIO(text), directory, root='/repo')


class ParserTests(unittest.TestCase):
    def test_warning_error_and_flag(self):
        p = parse('/repo/sources/A.m:10:5: warning: implicit conversion loses integer precision: '
                  "'long' to 'int' [-Wshorten-64-to-32]\n"
                  "/repo/sources/A.m:11:6: error: changes signedness: 'int' to 'unsigned int' "
                  '[-Werror,-Wsign-conversion]\n')
        self.assertEqual(list(p.diags), [('sources/A.m', 10, 5, '-Wshorten-64-to-32'),
                                         ('sources/A.m', 11, 6, '-Wsign-conversion')])
        self.assertEqual(p.diags[('sources/A.m', 11, 6, '-Wsign-conversion')][0], 'error')
        self.assertEqual(p.errors, 0, 'an error that is a promoted warning is not a hard error')
        self.assertEqual(p.unparsed, [])

    def test_hard_error_notes_include_stack_and_totals(self):
        p = parse('In file included from /repo/sources/A.m:3:\n'
                  "                 from /repo/sources/B.h:2:\n"
                  "In module 'Foundation' imported from /repo/sources/C.h:9:\n"
                  "/repo/sources/B.h:4:1: error: unknown type name 'Foo'\n"
                  "/repo/sources/B.h:2:1: note: expanded from macro 'X'\n"
                  '1 warning and 1 error generated.\n'
                  '3 warnings generated.\n')
        self.assertEqual(list(p.diags), [('sources/B.h', 4, 1, 'error')])
        self.assertEqual(p.errors, 1)
        self.assertEqual(p.first_error, "sources/B.h:4:1: error: unknown type name 'Foo'")
        self.assertEqual(p.notes, 1)
        self.assertEqual(p.unparsed, [])

    def test_relative_paths_resolve_against_the_unit_directory(self):
        p = parse("ThirdParty/x/y.h:1:2: warning: shadows [-Wshadow]\n", directory='/repo')
        self.assertEqual(list(p.diags), [('ThirdParty/x/y.h', 1, 2, '-Wshadow')])

    def test_file_outside_the_repository_keeps_its_absolute_path(self):
        p = parse("/sdk/usr/include/x.h:1:2: warning: w [-Wfoo]\n")
        self.assertEqual(list(p.diags), [('/sdk/usr/include/x.h', 1, 2, '-Wfoo')])

    def test_driver_diagnostic_without_location(self):
        p = parse("clang: warning: no such include directory: '/x' [-Wmissing-include-dirs]\n"
                  "error: unknown argument: '-bogus'\n")
        self.assertEqual(list(p.diags), [('<command line>', 0, 0, '-Wmissing-include-dirs'),
                                         ('<command line>', 0, 0, 'error')])
        self.assertEqual(p.errors, 1)

    def test_unrecognized_lines_are_counted(self):
        p = parse('/repo/a.m:1:1: warning: fine [-Wfoo]\nsomething clang never prints\n')
        self.assertEqual(p.unparsed, ['something clang never prints'])

    def test_message_spanning_lines_keeps_its_flag(self):
        # A MIN() statement expression printed as a type, verbatim, with the flag on the last line.
        p = parse("/repo/a.m:5:9: warning: implicit conversion loses floating-point precision: 'typeof (({\n"
                  '    typeof (x) __a = (x);\n'
                  "}))' (aka 'double') to 'float' [-Wimplicit-float-conversion]\n"
                  "/repo/a.m:6:1: note: expanded from macro '\\\n"
                  "DEFINE_BOILERPLATE'\n")
        self.assertEqual(list(p.diags), [('a.m', 5, 9, '-Wimplicit-float-conversion')])
        self.assertIn('typeof (x) __a', p.diags[('a.m', 5, 9, '-Wimplicit-float-conversion')][1])
        self.assertEqual(p.notes, 1)
        self.assertEqual(p.unparsed, [])

    def test_continuation_never_swallows_a_diagnostic(self):
        p = parse("/repo/a.m:1:1: warning: can't be [-Wfoo]\n"
                  "/repo/a.m:2:1: warning: it's open\n"
                  '/repo/a.m:3:1: warning: next [-Wbar]\n'
                  'stray\n')
        self.assertEqual(list(p.diags), [('a.m', 1, 1, '-Wfoo'), ('a.m', 2, 1, ''), ('a.m', 3, 1, '-Wbar')])
        self.assertEqual(p.unparsed, ['stray'], 'a closed message takes no continuation')
        p = parse('/repo/a.m:4:1: warning: no flag and no open quote\nstray2\n')
        self.assertEqual(p.unparsed, ['stray2'], 'a message with its quotes closed takes no continuation')

    def test_same_location_two_flags_are_two_diagnostics(self):
        p = parse('/repo/a.m:1:1: warning: x [-Wfoo]\n/repo/a.m:1:1: warning: y [-Wbar]\n'
                  '/repo/a.m:1:1: warning: x again [-Wfoo]\n')
        self.assertEqual(len(p.diags), 2)
        p = parse('/repo/a.m:1:1: warning: x [-Wfoo]\n/repo/a.m:1:9: warning: x [-Wfoo]\n')
        self.assertEqual(list(p.diags), [('a.m', 1, 1, '-Wfoo'), ('a.m', 1, 9, '-Wfoo')],
                         'the column is part of the key')

    def test_flag_of(self):
        self.assertEqual(ws.flag_of('-Werror,-Wshadow', 'error'), '-Wshadow')
        self.assertEqual(ws.flag_of(None, 'error'), 'error')
        self.assertEqual(ws.flag_of(None, 'warning'), '')
        self.assertEqual(ws.flag_of('-Werror=return-type', 'error'), 'error')


def write_unit(out_dir, unit, target, file, diags, exit_code=0):
    units = os.path.join(out_dir, 'units')
    os.makedirs(units, exist_ok=True)
    with open(os.path.join(units, unit + '.jsonl'), 'w') as f:
        f.write(json.dumps({'unit': unit, 'target': target, 'file': file, 'exit': exit_code, 'timed_out': False,
                            'seconds': 1, 'max_rss_mb': 1, 'errors': 0, 'first_error': None, 'notes': 0,
                            'unparsed': 0, 'unparsed_examples': [], 'diagnostics': len(diags)}) + '\n')
        for d in diags:
            f.write(json.dumps(d) + '\n')


class DeduplicationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def test_header_diagnostic_counted_once_under_the_header(self):
        d = os.path.join(self.tmp, 'arm64', 'strict')
        shared = ['sources/Shared.h', 3, 4, '-Wshorten-64-to-32', 'warning', 'loses precision']
        write_unit(d, 'u1', 'iTerm2SharedARC', 'sources/One.m',
                   [shared, ['sources/One.m', 9, 1, '-Wsign-conversion', 'warning', 'sign']])
        write_unit(d, 'u2', 'iTerm2SharedARC', 'sources/Two.m',
                   [shared, ['sources/Two.m', 2, 1, '-Wsign-conversion', 'warning', 'sign'],
                    ['sources/Two.m', 2, 1, '-Wshadow', 'warning', 'other flag, same place'],
                    ['ThirdParty/fmdb/x.h', 1, 1, '-Wsign-conversion', 'warning', 'third party']])
        records, diags = ws.read_results(d)
        self.assertEqual(len(records), 2)
        self.assertEqual(diags[('sources/Shared.h', 3, 4, '-Wshorten-64-to-32')][2], 2)
        self.assertEqual(len(diags), 5)
        s = ws.summarize(self.tmp, 'arm64', 'strict', None, 10, fragments=os.path.join(self.tmp, 'none'))
        flags = {f['flag']: (f['in_scope'], f['outside_scope']) for f in s['per_flag']}
        self.assertEqual(flags, {'-Wsign-conversion': (2, 1), '-Wshorten-64-to-32': (1, 0), '-Wshadow': (1, 0)})
        files = {f['file']: f['count'] for f in s['top_files']}
        self.assertEqual(files, {'sources/Two.m': 2, 'sources/One.m': 1, 'sources/Shared.h': 1})
        self.assertEqual(s['by_category'], {'in scope': 4, 'outside scope: ThirdParty/fmdb/': 1})

    def test_scope_categories(self):
        scope = ws.Scope([{'file': 'sources/T.m', 'target': 'ModernTests'},
                          {'file': 'sources/P.m', 'target': 'iTerm2SharedARC'},
                          {'file': 'sources/P.m', 'target': 'ModernTests'}])
        self.assertEqual(scope.category('sources/T.m'), 'test code')
        self.assertEqual(scope.category('sources/T.h'), 'test code')
        self.assertEqual(scope.category('sources/P.m'), 'in scope')
        self.assertEqual(scope.category('ModernTests/X.m'), 'test code')
        self.assertEqual(scope.category('sources/proto/Api.pbobjc.h'), 'generated (protobuf)')
        self.assertEqual(scope.category('ThirdParty/PSMTabBarControl/source/X.m'), 'in scope')
        self.assertEqual(scope.category('ThirdParty/fmdb/FMDatabase.h'), 'outside scope: ThirdParty/fmdb/')
        self.assertEqual(scope.category('/Applications/Xcode.app/x.h'), 'outside the repository (SDK)')
        self.assertEqual(scope.category('Build/Intermediates.noindex/x-Swift.h'), 'generated under Build/')

    def test_compare_finds_one_architecture_only(self):
        both = ['sources/A.m', 1, 1, '-Wsign-conversion', 'warning', 'both']
        write_unit(os.path.join(self.tmp, 'arm64', 'strict'), 'u', 'iTerm2SharedARC', 'sources/A.m',
                   [both, ['sources/A.m', 5, 2, '-Wfloat-conversion', 'warning', 'double to bool']])
        write_unit(os.path.join(self.tmp, 'x86_64', 'strict'), 'u', 'iTerm2SharedARC', 'sources/A.m',
                   [both, ['sources/A.m', 7, 3, '-Wobjc-signed-char-bool-implicit-int-conversion', 'warning',
                           'int to BOOL'],
                    ['ThirdParty/fmdb/x.m', 1, 1, '-Wcast-align', 'warning', 'third party']])
        c = ws.compare(self.tmp, 'strict', 5)['one_architecture_only']
        self.assertEqual(list(c['arm64 only']), ['-Wfloat-conversion'])
        self.assertEqual(c['arm64 only']['-Wfloat-conversion']['examples'],
                         ['sources/A.m:5:2: double to bool'])
        x = c['x86_64 only']
        self.assertEqual(x['-Wobjc-signed-char-bool-implicit-int-conversion']['in_scope'], 1)
        self.assertEqual(x['-Wcast-align'], {'in_scope': 0, 'outside_scope': 1, 'examples': []})

    def test_file_report_merges_architectures(self):
        for arch in ws.ARCHES:
            diags = [['sources/A.m', 3, 1, '-Wsign-conversion', 'warning', 'sign'],
                     ['sources/A.h', 1, 1, '-Wshadow', 'warning', 'in the header, not listed']]
            if arch == 'x86_64':
                diags.append(['sources/A.m', 4, 2, '-Wobjc-signed-char-bool-implicit-int-conversion', 'warning',
                              'int to BOOL'])
            write_unit(os.path.join(self.tmp, arch, 'strict'), 'u', 'iTerm2SharedARC', 'sources/A.m', diags)
            write_unit(os.path.join(self.tmp, arch, 'baseline'), 'u', 'iTerm2SharedARC', 'sources/A.m', [])
        r = ws.file_report(self.tmp, 'sources/A.m', None)
        self.assertEqual([(e['line'], e['flag'], e['arches']) for e in r['strict']],
                         [(3, '-Wsign-conversion', ['arm64', 'x86_64']),
                          (4, '-Wobjc-signed-char-bool-implicit-int-conversion', ['x86_64'])])
        self.assertEqual(r['missing_runs'], [])
        self.assertEqual(r['units'], 2)


class CommandTests(unittest.TestCase):
    UNIT = {'id': 'T__a.m', 'target': 'T', 'file': 'a.m', 'directory': '/repo', 'arguments': [
        '/x/clang', '-xobjective-c', '/repo/a.m', '-o', '/b/T.build/Objects-normal/arm64/a.o',
        '-ivfsstatcache', '/c/stat', '--target=arm64-apple-macos13.0', '-fmodules-prune-interval=86400',
        '-fbuild-session-file=/s', '-fmodules-validate-once-per-build-session', '-Werror', '-Wall',
        '-Wno-shorten-64-to-32', '-fmodules-cache-path=/dd/ModuleCache', '-I',
        '/b/T.build/DerivedSources-normal/arm64', '-include', '/b/PrecompiledHeaders/1/iTerm2.pch',
        '--serialize-diagnostics', '/b/a.dia', '-c', '-Xclang', '-clang-vendor-feature=+x', '-Xclang',
        '-Wno-error=allocator-wrappers', '-mlinker-version=1166.2', '-Wl,-foo', '-index-store-path', '/i']}
    PCH = {'/b/PrecompiledHeaders/1/iTerm2.pch': '/repo/sources/iTerm2.pch'}

    def cmd(self, mode, arch='arm64', overlay=None):
        return ws.survey_command(self.UNIT, mode, arch, self.PCH, '/mc', overlay, compiler=('cc',))

    def test_baseline_keeps_the_warning_flags(self):
        c = self.cmd('baseline')
        for kept in ('-Werror', '-Wall', '-Wno-shorten-64-to-32', '-mlinker-version=1166.2', '-Wl,-foo'):
            self.assertIn(kept, c)
        for gone in ('-o', '-c', '-ivfsstatcache', '--serialize-diagnostics', '-index-store-path',
                     '-fmodules-validate-once-per-build-session', '/b/a.dia', '/i'):
            self.assertNotIn(gone, c)
        self.assertNotIn('-fmodules-cache-path=/dd/ModuleCache', c)
        self.assertEqual(c[0], 'cc')
        self.assertEqual(c[-len(ws.ADDED) - 1:], ws.ADDED + ['-fmodules-cache-path=/mc'])
        i = c.index('-include')
        self.assertEqual(c[i + 1], '/repo/sources/iTerm2.pch')
        self.assertIn('-Wno-error=allocator-wrappers', c)

    def test_strict_replaces_the_warning_flags_with_the_header_flags(self):
        c = self.cmd('strict')
        for gone in ('-Werror', '-Wall', '-Wno-shorten-64-to-32', '-Wno-error=allocator-wrappers'):
            self.assertNotIn(gone, c)
        self.assertEqual(c[-len(ws.strict_flags()) - 1:], ['-Wno-everything'] + ws.strict_flags())
        # The Xclang pair goes as a pair: dropping only its value would hand -mlinker-version to the frontend.
        i = c.index('-mlinker-version=1166.2')
        self.assertNotEqual(c[i - 1], '-Xclang')
        j = c.index('-clang-vendor-feature=+x')
        self.assertEqual(c[j - 1], '-Xclang')
        self.assertIn('-Wl,-foo', c)

    def test_everything(self):
        c = self.cmd('everything')
        self.assertEqual(c[-1], '-Weverything')
        self.assertNotIn('-Werror', c)

    def test_x86_64(self):
        c = self.cmd('baseline', 'x86_64', overlay='/o.json')
        self.assertIn('--target=x86_64-apple-macos13.0', c)
        self.assertIn('/b/T.build/DerivedSources-normal/x86_64', c)
        self.assertEqual(c[1:3], ['-ivfsoverlay', '/o.json'])
        self.assertFalse([a for a in c if 'arm64' in a and a != '-o'], c)

    def test_missing_precompiled_header_source_is_an_error(self):
        with self.assertRaises(ws.SurveyError):
            ws.survey_command(self.UNIT, 'baseline', 'arm64', {}, '/mc', compiler=('cc',))

    def test_strict_flags_come_from_the_header(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        h = os.path.join(tmp, 'h.h')
        with open(h, 'w') as f:
            f.write('// #pragma clang diagnostic error "-Wcommented"\n#pragma clang diagnostic error "-Wa"\n'
                    '  #  pragma  clang diagnostic error "-Wb-c"\n#pragma clang diagnostic ignored "-Wd"\n')
        self.assertEqual(ws.strict_flags(h), ['-Wa', '-Wb-c'])
        flags = ws.strict_flags()
        self.assertIn('-Wsign-compare', flags)
        self.assertEqual(len(flags), len(set(flags)))

    def test_load_units_skips_sanitizer_variants_headers_and_build(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)

        def frag(name, file, output, extra=()):
            with open(os.path.join(tmp, name), 'w') as f:
                f.write(json.dumps({'directory': ROOT, 'file': file, 'output': output,
                                    'arguments': ['clang'] + list(extra) + [file]}) + ',\n')
        frag('a.json', ROOT + '/sources/A.m', '/b/Variant-NoSanitizers/T.build/Objects-normal/arm64/A.o')
        frag('b.json', ROOT + '/sources/A.m', '/b/Variant-ASan/T.build/Objects-normal-asan/arm64/A.o')
        frag('c.json', ROOT + '/sources/iTerm2.pch', '/b/PrecompiledHeaders/9/iTerm2.pch.gch',
             ['-xobjective-c-header'])
        frag('d.json', ROOT + '/Build/gen.m', '/b/Variant-NoSanitizers/T.build/Objects-normal/arm64/gen.o')
        frag('e.json', '/elsewhere/x.c', '/b/Variant-NoSanitizers/T.build/Objects-normal/arm64/x.o')
        units, pch, skipped = ws.load_units(tmp)
        self.assertEqual([(u['target'], u['file']) for u in units], [('T', 'sources/A.m')])
        self.assertEqual(pch, {'/b/PrecompiledHeaders/9/iTerm2.pch': ROOT + '/sources/iTerm2.pch'})
        self.assertEqual(dict(skipped), {'sanitizer variant': 1, 'precompiled header': 1,
                                         'generated under Build/': 1, 'outside the repository': 1})

    def test_overlay_widens_only_the_architecture_guard(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        h = os.path.join(tmp, 'M-Swift.h')
        with open(h, 'w') as f:
            f.write('#if 0\n#elif defined(__arm64__) && __arm64__\nint m;\n#else\n'
                    '#error unsupported Swift architecture\n#endif\n')
        overlay = ws.write_overlay(tmp, [h])
        with open(overlay) as f:
            roots = json.load(f)['roots']
        self.assertEqual([r['name'] for r in roots], [h])
        with open(roots[0]['external-contents']) as f:
            text = f.read()
        self.assertIn('(defined(__x86_64__) && __x86_64__)', text)
        self.assertIn('#error unsupported Swift architecture', text)
        self.assertIsNone(ws.write_overlay(tmp, []))


class AdoptionTests(unittest.TestCase):
    def check(self, name, text):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        p = os.path.join(tmp, name)
        with open(p, 'w') as f:
            f.write(text)
        return ws.adoption_problem(p)

    def test_last_import_is_fine(self):
        self.assertIsNone(self.check('a.m', '#import "a.h"\n#import "iTermStrictWarnings.h"\n\nint x;\n'))
        self.assertIsNone(self.check('a.m', '#import "a.h"\n'))

    def test_import_after_it(self):
        self.assertIn('line 3 imports b.h', self.check('a.m', '#import "a.h"\n#import "iTermStrictWarnings.h"\n'
                                                              '#include <b.h>\n'))
        self.assertIn('line 2 imports @import AppKit;',
                      self.check('a.m', '#import "iTermStrictWarnings.h"\n@import AppKit;\n'))

    def test_header_importing_it(self):
        self.assertIn('a header imports', self.check('a.h', '#import "iTermStrictWarnings.h"\n'))


def clang(args, cwd=None):
    return subprocess.run(['xcrun', 'clang', '-fsyntax-only', '-fno-caret-diagnostics',
                           '-fno-color-diagnostics'] + args, capture_output=True, text=True, cwd=cwd)


@needs_clang
class HeaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.mc = '-fmodules-cache-path=' + os.path.join(cls.tmp, 'mc')

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_clean_files_compile_with_every_flag_known(self):
        for name, extra in (('clean.c', []), ('clean.m', ['-fmodules', '-fobjc-arc']),
                            ('clean.mm', ['-fmodules', '-std=c++17'])):
            for arch in ws.ARCHES:
                r = clang(['-target', arch + '-apple-macos13.0', '-Werror', '-Wall', '-Wunknown-warning-option',
                           '-I', HEADER_DIR, self.mc] + extra + [os.path.join(FIXTURES, name)])
                self.assertEqual(r.returncode, 0, '%s %s: %s' % (name, arch, r.stderr))
                self.assertEqual(r.stderr, '')

    def test_importing_it_from_a_header_is_an_error(self):
        r = clang(['-I', HEADER_DIR, os.path.join(FIXTURES, 'via_header.m')])
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('must be imported directly by an implementation file', r.stderr)

    def test_every_flag_has_a_bad_fixture(self):
        names = sorted(f[:-2] for f in os.listdir(os.path.join(FIXTURES, 'bad')) if f.endswith('.m'))
        self.assertEqual(names, sorted(f[2:] for f in ws.strict_flags()))

    def test_each_bad_fixture_fails_with_its_flag_and_only_with_the_header(self):
        bad = os.path.join(FIXTURES, 'bad')
        for name in sorted(os.listdir(bad)):
            with open(os.path.join(bad, name)) as f:
                text = f.read()
            meta = dict(line[3:].split(': ', 1) for line in text.splitlines()
                        if line.startswith('// ') and ': ' in line)
            expect = meta['expect'].split()[0]
            arch = meta.get('arch', 'arm64')
            extra = ['-fobjc-arc'] if '\n// arc\n' in text else []
            base = ['-target', arch + '-apple-macos13.0', self.mc] + extra
            with self.subTest(fixture=name):
                r = clang(base + ['-I', HEADER_DIR, os.path.join(bad, name)])
                self.assertNotEqual(r.returncode, 0, r.stderr)
                self.assertIn('error: ', r.stderr)
                self.assertIn('[-Werror,%s]' % expect, r.stderr)
                plain = os.path.join(self.tmp, name)
                with open(plain, 'w') as f:
                    f.write(''.join(l for l in text.splitlines(True) if ws.STRICT_HEADER_NAME not in l))
                r = clang(base + [plain])
                self.assertEqual(r.returncode, 0, 'without the header %s must compile: %s' % (name, r.stderr))
                if 'clean-on' in meta:
                    other = meta['clean-on'].split()[0]
                    r = clang(['-target', other + '-apple-macos13.0', self.mc, '-I', HEADER_DIR] + extra +
                              [os.path.join(bad, name)])
                    self.assertEqual(r.returncode, 0, '%s on %s: %s' % (name, other, r.stderr))

    def test_pragmas_apply_after_the_import_and_to_macro_expansions(self):
        scope = os.path.join(FIXTURES, 'scope')
        r = clang(['-I', HEADER_DIR, 'main.m'], cwd=scope)
        self.assertNotEqual(r.returncode, 0)
        errors = sorted(l.split(': error:')[0].replace('./', '') for l in r.stderr.splitlines() if ': error:' in l)
        # after.h line 3 (imported after), main.m line 5 (macro from before.h expanded after the import),
        # main.m line 6; not before.h's inline function. Columns counted by hand: the `v` of `return v`,
        # the `x` passed to ASSIGN_NARROW (clang reports the macro argument where it is written).
        self.assertEqual(errors, ['after.h:3:49', 'main.m:5:48', 'main.m:6:29'])
        self.assertNotIn('before.h:4', r.stderr.replace('note: expanded from macro', ''))


@needs_clang
class EndToEndTests(unittest.TestCase):
    """The survey run on two small C units that share a header with a warning in it."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.frags = os.path.join(self.tmp, 'frags')
        os.makedirs(self.frags)
        units = os.path.join(FIXTURES, 'units')
        for name in ('a.c', 'b.c'):
            src = os.path.join(units, name)
            with open(os.path.join(self.frags, name + '.json'), 'w') as f:
                f.write(json.dumps({
                    'directory': units, 'file': src,
                    'output': '/b/Variant-NoSanitizers/iTerm2SharedARC.build/Objects-normal/arm64/%s.o' % name,
                    'arguments': ['clang', '-xc', src, '-o', '/nonexistent/%s.o' % name,
                                  '--target=arm64-apple-macos13.0', '-Wall', '-Werror', '-c']}) + ',\n')

    def run_main(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = ws.main(['--out', os.path.join(self.tmp, 'out')] + argv)
        return code, out.getvalue(), err.getvalue()

    def test_survey_strict_and_baseline_on_both_architectures(self):
        for arch in ws.ARCHES:
            for mode in ('baseline', 'strict'):
                code, out, err = self.run_main(['run', '--arch', arch, '--mode', mode, '--jobs', '2',
                                                '--fragments', self.frags])
                self.assertEqual(code, 0, out + err)
        records, diags = ws.read_results(os.path.join(self.tmp, 'out', 'arm64', 'strict'))
        rel = os.path.relpath(os.path.join(FIXTURES, 'units'), ROOT)
        keys = sorted((os.path.basename(k[0]), k[1], k[3], v[2]) for k, v in diags.items())
        self.assertEqual(keys, [('a.c', 2, '-Wshorten-64-to-32', 1),
                                ('b.c', 2, '-Wsign-conversion', 1),
                                ('shared.h', 1, '-Wshorten-64-to-32', 2)])
        self.assertTrue(all(k[0].startswith(rel) for k in diags))
        records, diags = ws.read_results(os.path.join(self.tmp, 'out', 'arm64', 'baseline'))
        self.assertEqual(diags, {})
        self.assertTrue(all(r['exit'] == 0 and r['unparsed'] == 0 for r in records))
        code, out, err = self.run_main(['summary', '--arch', 'arm64', '--mode', 'strict', '--fragments', self.frags])
        self.assertEqual(code, 0, err)
        self.assertRegex(out, r'-Wshorten-64-to-32\s+0\s+2')   # tools/ is outside the scope directories
        code, out, err = self.run_main(['compare', '--mode', 'strict'])
        self.assertIn('arm64 only: 0 in scope, 0 outside scope', out)
        self.assertIn('x86_64 only: 0 in scope, 0 outside scope', out)

    def test_failed_unit_is_reported(self):
        units = os.path.join(FIXTURES, 'units')
        src = os.path.join(units, 'broken.c')
        with open(os.path.join(self.frags, 'broken.json'), 'w') as f:
            f.write(json.dumps({'directory': units, 'file': src,
                                'output': '/b/iTerm2SharedARC.build/Objects-normal/arm64/broken.o',
                                'arguments': ['clang', '-xc', src, '-c']}))
        code, out, err = self.run_main(['run', '--mode', 'baseline', '--jobs', '1', '--fragments', self.frags])
        self.assertEqual(code, 1, out + err)
        self.assertIn('broken.c: exit 1', out)
        raw = os.path.join(self.tmp, 'out', 'arm64', 'baseline', 'raw')
        self.assertEqual(os.listdir(raw), ['iTerm2SharedARC__%s.txt' % os.path.relpath(src, ROOT).replace('/', '__')],
                         'raw output is kept only for the unit that failed')
        code, out, err = self.run_main(['summary', '--mode', 'baseline', '--fragments', self.frags])
        self.assertEqual(code, 1)
        self.assertRegex(out, r"FAILED .*broken.c \[iTerm2SharedARC\] exit 1: .*broken.c:2:22: error: "
                              r"use of undeclared identifier 'undeclared'")

if __name__ == '__main__':
    unittest.main()
