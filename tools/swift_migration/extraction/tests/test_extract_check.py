#!/usr/bin/env python3
"""Tests for extract_check.py and extraction_facts.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/extraction/tests -p 'test_*.py'

They need only Homebrew LLVM 22 and the SDK. The fixtures under fixtures/ are
compiled from fixed command lines below, with no dependence on the app's
build. A range to analyze is the lines between a "// NAME{" line and the
matching "// NAME}" line, so no test hard-codes a line number of a fixture.
The binary is built into tmp/extraction/test-bin/ (or set
EXTRACTION_TEST_BINARY to use another).
"""

import difflib
import json
import os
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
sys.path.insert(0, TOOL_DIR)

import extract_check  # noqa: E402

REPO = os.path.realpath(os.path.join(TOOL_DIR, '..', '..', '..'))
FIX = os.path.join(HERE, 'fixtures')
BINARY = os.environ.get('EXTRACTION_TEST_BINARY') or os.path.join(REPO, 'tmp', 'extraction', 'test-bin',
                                                                  'extraction_facts')
SCRIPT = os.path.join(TOOL_DIR, 'extract_check.py')
SDK = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True).stdout.strip()
BASE = ['--target=arm64-apple-macos13', '-isysroot', SDK]


def lang_args(path):
    if os.path.basename(path).startswith('mrr_'):
        return ['-x', 'objective-c', '-fobjc-exceptions', '-fblocks', '-Wno-objc-root-class']
    if path.endswith('.mm'):
        return ['-x', 'objective-c++', '-std=c++17', '-fobjc-arc', '-fexceptions', '-fcxx-exceptions']
    if path.endswith('.m'):
        return ['-x', 'objective-c', '-fobjc-arc', '-fobjc-exceptions', '-fblocks']
    return ['-x', 'c', '-std=gnu11', '-fblocks']


def clang_args(path, extra=()):
    return lang_args(path) + BASE + list(extra) + [path]


def setUpModule():
    if not os.environ.get('EXTRACTION_TEST_BINARY'):
        extract_check.ensure_binary(BINARY)


def marked(path, name):
    """(first, last): the lines between "// name{" and "// name}"."""
    first = last = None
    with open(path) as f:
        for n, line in enumerate(f, 1):
            s = line.strip()
            if s == '// %s{' % name:
                first = n + 1
            elif s == '// %s}' % name:
                last = n - 1
    assert first and last, 'no markers for %s in %s' % (name, path)
    return first, last


def run_tool(argv):
    r = subprocess.run([sys.executable, '-B', SCRIPT] + argv, capture_output=True, text=True, cwd=REPO)
    return r.returncode, r.stdout, r.stderr


def range_report(fixture, name, extra=(), text=False):
    path = os.path.join(FIX, fixture)
    first, last = marked(path, name)
    argv = ['range', '%s:%d-%d' % (path, first, last), '--binary', BINARY, '--no-build', '--repo', REPO]
    if not text:
        argv.append('--json')
    code, out, err = run_tool(argv + ['--'] + clang_args(path, extra))
    if text:
        return code, out, err
    if code == 2:
        raise AssertionError('tool error: %s' % err)
    return code, json.loads(out)


def declarations(before, after, a, b, c, d):
    """--allow-removed and --allow-added for every line outside the block and
    its destination that differs, so that pure_move judges only the block."""
    old = open(before).read().split('\n')
    new = open(after).read().split('\n')
    # As pure_move.split_lines: no element after a final newline.
    if old and old[-1] == '':
        old.pop()
    if new and new[-1] == '':
        new.pop()
    old_keep = [(n, t) for n, t in enumerate(old, 1) if not a <= n <= b]
    new_keep = [(n, t) for n, t in enumerate(new, 1) if not c <= n <= d]
    out = []
    # The scenario markers move from the caller into the helper; they must not
    # anchor the alignment.
    def marker(t):
        t = t.strip()
        return t in ('}', '{', '') or (t.startswith('// ') and t.endswith(('{', '}')) and ' ' not in t[3:])
    sm = difflib.SequenceMatcher(None, [t for _, t in old_keep], [t for _, t in new_keep], autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        for k in range(i1, i2):
            out += ['--allow-removed', '%s:%d' % (before, old_keep[k][0])]
        for k in range(j1, j2):
            out += ['--allow-added', '%s:%d' % (before, new_keep[k][0])]
    return out


TEMP_DIRS = []
ISOLATED_DECLS = {}


def tearDownModule():
    import shutil
    for d in TEMP_DIRS:
        shutil.rmtree(d, ignore_errors=True)


def isolate(before, after, name, extra=()):
    """An after file for one scenario: the before file with the caller replaced
    by the after file's helper and caller, which must be adjacent there (only
    blank and comment lines between them). The fixtures hold many scenarios per
    file; a real extract commit changes one function and adds one helper."""
    import tempfile
    a, _ = marked(before, name)
    c, _ = marked(after, name)
    args = clang_args(before, extra)
    fb = extract_check.run_facts(BINARY, before, args, ['--function-at', str(a)])['function']
    fh = extract_check.run_facts(BINARY, before, args, ['--function-at', str(c)], contents=after)['function']
    fc = extract_check.run_facts(BINARY, before, args, ['--function-named', fb['name']], contents=after)['function']
    old = open(before).read().split('\n')
    new = open(after).read().split('\n')
    first, second = sorted([(fh['line'], fh['end_line']), (fc['line'], fc['end_line'])])
    for line in new[first[1]:second[0] - 1]:
        if line.strip() and not line.strip().startswith('//'):
            raise AssertionError('helper and caller are not adjacent in %s: %r' % (after, line))
    region = new[first[0] - 1:second[1]]
    out = old[:fb['line'] - 1] + region + old[fb['end_line']:]
    d = tempfile.mkdtemp(prefix='extraction-test-')
    TEMP_DIRS.append(d)
    path = os.path.join(d, os.path.basename(after))
    with open(path, 'w') as f:
        f.write('\n'.join(out))
    # The declarations: every line of the region that is not the caller and not
    # the moved lines is added; the before and after callers are diffed.
    shift = fb['line'] - first[0]
    b0, b1 = marked(before, name)
    c0, c1 = marked(path, name)
    ca, cb = fc['line'] + shift, fc['end_line'] + shift
    decl = []
    for n in range(fb['line'], fb['line'] + len(region)):
        if ca <= n <= cb or c0 <= n <= c1:
            continue
        decl += ['--allow-added', '%s:%d' % (before, n)]
    old_c = [(n, old[n - 1]) for n in range(fb['line'], fb['end_line'] + 1) if not b0 <= n <= b1]
    newl = out
    new_c = [(n, newl[n - 1]) for n in range(ca, cb + 1)]
    sm = difflib.SequenceMatcher(None, [t for _, t in old_c], [t for _, t in new_c], autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        decl += [x for k in range(i1, i2) for x in ('--allow-removed', '%s:%d' % (before, old_c[k][0]))]
        decl += [x for k in range(j1, j2) for x in ('--allow-added', '%s:%d' % (before, new_c[k][0]))]
    ISOLATED_DECLS[path] = decl
    return path


def after_report(mode, ext, base, version, name, extra=(), isolated=None, after_path=None):
    before = os.path.join(FIX, 'extract', base + ext)
    after = after_path or os.path.join(FIX, 'extract', version + ext)
    if isolated is None:
        isolated = mode == 'after' and not after_path
    if isolated:
        after = isolate(before, after, name, extra)
    a, b = marked(before, name)
    c, d = marked(after, name)
    decl = ISOLATED_DECLS.get(after) or declarations(before, after, a, b, c, d)
    argv = [mode, '--before-file', before, '--after-file', after,
            '--extract', '%s:%d-%d=%s:%d-%d' % (before, a, b, before, c, d)] + decl + [
            '--binary', BINARY, '--no-build', '--repo', REPO, '--json', '--'] + clang_args(before, extra)
    code, out, err = run_tool(argv)
    if code == 2:
        raise AssertionError('tool error: %s' % err)
    return code, json.loads(out)


def cat(rep, key):
    return rep['categories'][key]


def joined(c):
    return '\n'.join(c['items'])


class ControlFlow(unittest.TestCase):
    def test_return_external_is_listed(self):
        code, rep = range_report('flow.c', 'return_external')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'list')
        self.assertEqual(len(c['items']), 1)
        self.assertIn('return', c['items'][0])
        self.assertIn('leaves the function', c['items'][0])
        self.assertEqual(code, 0)

    def test_return_hidden_in_macro_is_found(self):
        _, rep = range_report('flow.c', 'return_in_macro')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'list')
        self.assertIn('in the body of macro CHECK', c['items'][0])
        self.assertIn('CHECK', joined(cat(rep, 'macros')))
        self.assertIn('contains return (leaves the range)', joined(cat(rep, 'macros')))

    def test_macro_with_do_while_has_no_exit(self):
        _, rep = range_report('flow.c', 'macro_without_exit')
        self.assertEqual(cat(rep, 'exits')['verdict'], 'none')
        self.assertIn('SAFE_LOG', joined(cat(rep, 'macros')))

    def test_break_out_of_switch_inside_range_is_internal(self):
        _, rep = range_report('flow.c', 'switch_break_internal')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'none')
        self.assertEqual(len(c['internal']), 2)
        self.assertIn('switch', c['internal'][0])

    def test_break_binding_to_outer_loop_is_listed(self):
        _, rep = range_report('flow.c', 'break_outer_loop')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'list')
        self.assertIn('break binds to the loop', c['items'][0])

    def test_continue_binding_to_outer_loop_is_listed(self):
        _, rep = range_report('flow.c', 'continue_outer_loop')
        self.assertIn('continue binds to the loop', joined(cat(rep, 'exits')))

    def test_loop_inside_range_is_internal(self):
        _, rep = range_report('flow.c', 'loop_inside_range')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'none')
        self.assertEqual(len(c['internal']), 2)

    def test_goto_fail_out_of_range_is_listed(self):
        _, rep = range_report('flow.c', 'goto_fail')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'list')
        self.assertIn('goto jumps to label fail', c['items'][0])

    def test_goto_inside_range_is_internal(self):
        _, rep = range_report('flow.c', 'goto_internal')
        self.assertEqual(cat(rep, 'exits')['verdict'], 'none')
        self.assertEqual(cat(rep, 'entries')['verdict'], 'none')

    def test_goto_into_range_is_an_entry(self):
        _, rep = range_report('flow.c', 'goto_into')
        c = cat(rep, 'entries')
        self.assertEqual(c['verdict'], 'list')
        self.assertIn('label again', c['items'][0])

    def test_return_in_statement_expression(self):
        _, rep = range_report('flow.c', 'statement_expression')
        self.assertIn('return', joined(cat(rep, 'exits')))
        self.assertIn('statement-expression', joined(cat(rep, 'scopes')))

    def test_noreturn_call_is_listed_as_unchanged(self):
        _, rep = range_report('flow.c', 'noreturn_call')
        c = cat(rep, 'exits')
        self.assertIn('abort, which does not return', joined(c))
        self.assertIn('unchanged by extraction', joined(c))

    def test_case_label_of_outer_switch_is_an_entry(self):
        _, rep = range_report('flow.c', 'case_label_entry')
        self.assertIn('case label of the switch', joined(cat(rep, 'entries')))
        self.assertIn('break binds to the switch', joined(cat(rep, 'exits')))

    def test_case_body_without_label_aligns(self):
        _, rep = range_report('flow.c', 'case_body_only')
        self.assertTrue(rep['selection']['aligned'])
        self.assertEqual(cat(rep, 'entries')['verdict'], 'none')
        self.assertEqual(cat(rep, 'exits')['verdict'], 'none')

    def test_misaligned_range_is_unknown(self):
        code, rep = range_report('flow.c', 'misaligned')
        self.assertEqual(code, 3)
        for key, _ in extract_check.CATEGORIES:
            self.assertEqual(cat(rep, key)['verdict'], 'unknown', key)
        self.assertIn('does not align', cat(rep, 'exits')['unknown'][0])

    def test_code_not_compiled_in_range_is_unknown(self):
        code, rep = range_report('flow.c', 'not_compiled')
        self.assertEqual(code, 3)
        self.assertEqual(cat(rep, 'exits')['verdict'], 'unknown')
        self.assertIn('not compiled in this configuration', cat(rep, 'exits')['unknown'][0])
        self.assertIn('arm64-apple-macos', cat(rep, 'exits')['unknown'][0])

    def test_code_not_compiled_after_range_makes_outputs_unknown(self):
        code, rep = range_report('flow.c', 'not_compiled_after')
        self.assertEqual(code, 3)
        self.assertEqual(cat(rep, 'outputs')['verdict'], 'unknown')
        self.assertEqual(cat(rep, 'exits')['verdict'], 'none')

    def test_clang_errors_are_shown(self):
        code, out, err = range_report('flow.c', 'return_external', extra=['-DTRIGGER_ERROR=1', '-include',
                                                                            os.path.join(FIX, 'error.h')], text=True)
        self.assertEqual(code, 3)
        self.assertIn('undefined_thing', out)
        self.assertIn('deliberate_error_identifier', out)

    def test_comment_only_range_is_an_error(self):
        code, out, err = range_report('flow.c', 'only_comments', text=True)
        self.assertEqual(code, 2)
        self.assertIn('holds no code', err)


class DataFlow(unittest.TestCase):
    def test_read_written_and_used_after(self):
        _, rep = range_report('data.c', 'read_write')
        outs = joined(cat(rep, 'outputs'))
        self.assertIn('used_after', outs)
        self.assertNotIn('dead_after (', outs)
        self.assertIn('dead_after', '\n'.join(cat(rep, 'outputs')['not_needed']))
        ins = joined(cat(rep, 'inputs'))
        self.assertIn('only_read', ins)
        self.assertNotIn('dead_after', ins)  # overwritten before work(dead_after) reads it
        self.assertNotIn('used_after (', ins)  # overwritten before it is read
        self.assertIn('used_after', '\n'.join(cat(rep, 'inputs')['not_needed']))

    def test_later_write_only_is_flagged_for_review(self):
        _, rep = range_report('data.c', 'later_write_only')
        self.assertIn('every later use is a write', joined(cat(rep, 'outputs')))

    def test_address_taken_in_range(self):
        _, rep = range_report('data.c', 'address_taken')
        self.assertIn('x: address taken', joined(cat(rep, 'captures')))
        self.assertIn('x (', joined(cat(rep, 'outputs')))

    def test_address_taken_outside_range(self):
        _, rep = range_report('data.c', 'address_taken_elsewhere')
        self.assertIn('address taken outside the range', joined(cat(rep, 'captures')))

    def test_loop_carried_write_must_come_back(self):
        _, rep = range_report('data.c', 'loop_carried')
        outs = joined(cat(rep, 'outputs'))
        self.assertIn('count', outs)
        self.assertIn('next iteration of the loop', outs)

    def test_variable_declared_in_loop_body_is_not_loop_carried(self):
        _, rep = range_report('data.c', 'loop_local')
        outs = joined(cat(rep, 'outputs'))
        self.assertIn('t (', outs)  # used after, by work(t)
        self.assertNotIn('next iteration', outs)

    def test_declared_inside_used_after(self):
        _, rep = range_report('data.c', 'declared_inside')
        self.assertIn('fresh', joined(cat(rep, 'declared')))

    def test_struct_member_write_is_read_write(self):
        _, rep = range_report('data.c', 'struct_member')
        self.assertIn('read-write at', joined(cat(rep, 'inputs')))
        self.assertIn('s (', joined(cat(rep, 'outputs')))

    def test_array_element_write_is_read_write(self):
        _, rep = range_report('data.c', 'array_element')
        self.assertIn('arr (', joined(cat(rep, 'outputs')))

    def test_array_decay_is_address_taken(self):
        _, rep = range_report('data.c', 'array_decay')
        self.assertIn('array decays to a pointer', joined(cat(rep, 'captures')))

    def test_sizeof_is_unevaluated(self):
        _, rep = range_report('data.c', 'unevaluated')
        self.assertEqual(cat(rep, 'inputs')['verdict'], 'none')

    def test_backward_goto_makes_write_live(self):
        _, rep = range_report('data.c', 'backward_goto')
        self.assertIn('backward goto', joined(cat(rep, 'outputs')))

    def test_compound_assignment_reads(self):
        _, rep = range_report('data.c', 'compound_only')
        self.assertIn('acc (', joined(cat(rep, 'inputs')))
        self.assertIn('acc (', joined(cat(rep, 'outputs')))

    def test_globals_and_file_statics(self):
        _, rep = range_report('data.c', 'globals')
        g = joined(cat(rep, 'globals'))
        self.assertIn('s_counter (', g)
        self.assertIn('file static', g)
        self.assertIn('g_file (', g)

    def test_write_through_pointer(self):
        _, rep = range_report('data.c', 'ptr_through')
        self.assertIn('writes through the pointer p', joined(cat(rep, 'captures')))

    def test_write_through_reference_variable(self):
        _, rep = range_report('cxx.mm', 'ref_write')
        o = joined(cat(rep, 'outputs'))
        self.assertIn('r (', o)
        self.assertIn('through a reference', o)

    def test_address_of_block_local_escapes(self):
        for name in ('escape_local', 'escape_literal'):
            _, rep = range_report('data.c', name)
            self.assertIn('block-local-address', joined(cat(rep, 'hazards')), name)

    def test_structured_binding_is_unknown(self):
        code, rep = range_report('cxx.mm', 'bindings')
        self.assertEqual(code, 3)
        self.assertEqual(cat(rep, 'inputs')['verdict'], 'unknown')

    def test_alias_taken_before_block(self):
        _, rep = range_report('data.c', 'alias_before')
        self.assertIn('through a pointer taken at line', joined(cat(rep, 'outputs')))

    def test_block_variable_in_c(self):
        _, rep = range_report('data.c', 'c_block')
        o = joined(cat(rep, 'ownership'))
        self.assertNotIn('manual reference counting', o)
        self.assertIn('Block_copy', o)

    def test_simd_component(self):
        code, rep = range_report('data.c', 'simd')
        self.assertEqual(cat(rep, 'inputs')['verdict'], 'list')
        self.assertIn('v (', joined(cat(rep, 'outputs')))

    def test_static_local_is_a_hazard(self):
        _, rep = range_report('data.c', 'static_local')
        self.assertIn('static local', joined(cat(rep, 'hazards')))


class Hazards(unittest.TestCase):
    def test_vla(self):
        _, rep = range_report('data.c', 'vla')
        self.assertIn('variable-length array', joined(cat(rep, 'hazards')))

    def test_alloca(self):
        _, rep = range_report('data.c', 'uses_alloca')
        self.assertIn('alloca', joined(cat(rep, 'hazards')))

    def test_va_list(self):
        _, rep = range_report('data.c', 'uses_va')
        h = joined(cat(rep, 'hazards'))
        self.assertIn('va_list', h)
        self.assertIn('va_arg', h)

    def test_setjmp(self):
        _, rep = range_report('data.c', 'uses_setjmp')
        self.assertIn('setjmp', joined(cat(rep, 'hazards')))

    def test_cleanup_attribute(self):
        _, rep = range_report('data.c', 'cleanup_attr')
        self.assertIn('cleanup', joined(cat(rep, 'hazards')))

    def test_counter_note(self):
        _, rep = range_report('data.c', 'counter')
        self.assertIn('unique names', joined(cat(rep, 'positional')))

    def test_char_pointer_is_not_va_list(self):
        _, rep = range_report('data.c', 'charptr')
        self.assertNotIn('va_list', joined(cat(rep, 'hazards')))

    def test_sizeof_outer_array(self):
        _, rep = range_report('data.c', 'sizeof_outer')
        self.assertIn('sizeof-array', joined(cat(rep, 'hazards')))

    def test_frame_address(self):
        _, rep = range_report('data.c', 'frame_address')
        self.assertIn('frame-address', joined(cat(rep, 'hazards')))


class ObjectiveC(unittest.TestCase):
    def test_self_super_ivar_cmd_and_function_name(self):
        _, rep = range_report('objc.m', 'self_uses')
        s = joined(cat(rep, 'self'))
        self.assertIn('super', s)
        self.assertIn('ivar _count (write)', s)
        self.assertIn('self (read)', s)
        self.assertIn('_cmd', s)
        p = joined(cat(rep, 'positional'))
        self.assertIn('__FUNCTION__ via macro DLOG', p)
        self.assertIn('__LINE__ via macro DLOG', p)
        self.assertIn('a note, not a failure', p)

    def test_return_inside_synchronized_crosses_it(self):
        _, rep = range_report('objc.m', 'return_in_synchronized')
        e = joined(cat(rep, 'exits'))
        self.assertIn('leaves the function', e)
        self.assertIn('@synchronized', e)
        self.assertIn('@synchronized', joined(cat(rep, 'scopes')))

    def test_autoreleasepool_inside_range(self):
        _, rep = range_report('objc.m', 'pool_inside')
        self.assertIn('inside the range: @autoreleasepool', joined(cat(rep, 'scopes')))
        self.assertEqual(cat(rep, 'exits')['verdict'], 'none')

    def test_return_in_try_with_finally(self):
        _, rep = range_report('objc.m', 'return_in_try')
        self.assertIn('@try', joined(cat(rep, 'exits')))

    def test_rethrow_outside_its_catch(self):
        _, rep = range_report('objc.m', 'rethrow')
        e = joined(cat(rep, 'exits'))
        self.assertIn('rethrow', e)
        self.assertIn('@catch', e)

    def test_block_capturing_written_local_by_copy(self):
        _, rep = range_report('objc.m', 'block_copy')
        self.assertIn('captured by copy', joined(cat(rep, 'captures')))
        self.assertIn('x (', joined(cat(rep, 'outputs')))

    def test_block_capturing_by_reference(self):
        _, rep = range_report('objc.m', 'block_byref')
        c = joined(cat(rep, 'captures'))
        self.assertIn('captured by reference by the block', c)
        self.assertIn('__block variable', c)
        self.assertIn('x (', joined(cat(rep, 'outputs')))

    def test_return_inside_block_literal_is_internal(self):
        _, rep = range_report('objc.m', 'return_in_block')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'none')
        self.assertIn('block', c['internal'][0])

    def test_ownership_qualifiers(self):
        _, rep = range_report('objc.m', 'objects')
        o = joined(cat(rep, 'ownership'))
        self.assertIn('strongThing: __strong (the default, not written)', o)
        self.assertIn('weakThing: __weak', o)
        self.assertIn('arThing: __autoreleasing', o)
        self.assertIn('loaded once', o)

    def test_manual_reference_counting(self):
        _, rep = range_report('objc.m', 'objects', extra=['-fno-objc-arc', '-Wno-objc-root-class'])
        self.assertIn('manual reference counting', joined(cat(rep, 'ownership')))

    def test_range_inside_block_literal(self):
        _, rep = range_report('objc.m', 'inside_block')
        self.assertIn('inside the block', joined(cat(rep, 'scopes')))
        self.assertEqual(rep['function']['closure']['kind'], 'block')
        self.assertIn('inner', joined(cat(rep, 'inputs')))

    def test_property_setter_reads_value(self):
        code, rep = range_report('objc.m', 'setter')
        self.assertEqual(cat(rep, 'inputs')['verdict'], 'list', json.dumps(rep['categories']['inputs']))
        self.assertIn('v (', joined(cat(rep, 'inputs')))

    def test_for_in_element_is_written(self):
        _, rep = range_report('objc.m', 'for_in')
        self.assertIn('last (', joined(cat(rep, 'outputs')))


class CPlusPlus(unittest.TestCase):
    def test_lambda_capturing_by_reference(self):
        _, rep = range_report('cxx.mm', 'lambda_byref')
        self.assertIn('captured by reference by the lambda', joined(cat(rep, 'captures')))
        self.assertIn('total (', joined(cat(rep, 'outputs')))

    def test_lambda_capturing_by_copy(self):
        _, rep = range_report('cxx.mm', 'lambda_copy')
        c = joined(cat(rep, 'captures'))
        self.assertIn('captured by copy by the lambda', c)
        self.assertNotIn('by reference', c)

    def test_destructor_inside_range(self):
        _, rep = range_report('cxx.mm', 'destructor_inside')
        self.assertIn('destructor runs when the helper returns', joined(cat(rep, 'hazards')))

    def test_member_calls(self):
        _, rep = range_report('cxx.mm', 'member_calls')
        ins = joined(cat(rep, 'inputs'))
        self.assertIn('const member function', ins)
        self.assertIn('non-const member function poke', ins)

    def test_reference_parameters(self):
        _, rep = range_report('cxx.mm', 'references')
        self.assertIn('a: bound to a reference', joined(cat(rep, 'captures')))
        self.assertIn('a (', joined(cat(rep, 'outputs')))
        self.assertNotIn('b (', joined(cat(rep, 'outputs')))

    def test_throw_caught_inside_range(self):
        _, rep = range_report('cxx.mm', 'throw_internal')
        c = cat(rep, 'exits')
        self.assertEqual(c['verdict'], 'none')
        self.assertIn('try', c['internal'][0])

    def test_throw_leaving_range(self):
        _, rep = range_report('cxx.mm', 'throw_external')
        self.assertIn('passes through the helper to the same handlers', joined(cat(rep, 'exits')))

    def test_copy_constructor(self):
        _, rep = range_report('cxx.mm', 'copy_by_value')
        self.assertIn('copy constructor', joined(cat(rep, 'hazards')))

    def test_range_for_writes_elements(self):
        _, rep = range_report('cxx.mm', 'range_for')
        self.assertIn('values (', joined(cat(rep, 'outputs')))

    def test_operator_and_lambda_calls_do_not_crash(self):
        code, rep = range_report('cxx.mm', 'operators')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertIn('total (', joined(cat(rep, 'outputs')))
        self.assertIn('n (', joined(cat(rep, 'inputs')))

    def test_lifetime_extended_temporary(self):
        _, rep = range_report('cxx.mm', 'lifetime_extended')
        self.assertIn('lifetime-extended-temporary', joined(cat(rep, 'hazards')))


def only_pure_move_blocks(test, code, rep):
    """Every pairing matches, and the only reason for review is that pure_move
    cannot confirm the block's lines (they were rewritten, z to *z)."""
    test.assertEqual(code, 1, json.dumps(rep, indent=1))
    test.assertFalse(rep['pure_move']['pure_move'])
    bad = [x for x in rep['data'] + rep['exits'] + rep['other']
           if x['status'] not in ('matches a known safe pattern', 'note')]
    test.assertEqual(len(bad), 1, json.dumps(bad, indent=1))
    test.assertIn('pure_move', bad[0]['text'])


def statuses(rep, key):
    return [(x.get('subject', x.get('kind')), x['status']) for x in rep[key]]


class After(unittest.TestCase):
    def test_out_param_safe(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'out_param')
        only_pure_move_blocks(self, code, rep)
        self.assertIn(('z', 'matches a known safe pattern'), statuses(rep, 'data'))
        self.assertIn(('x', 'matches a known safe pattern'), statuses(rep, 'data'))

    def test_out_param_dropped_write_back(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'out_param')
        self.assertEqual(code, 1)
        self.assertIn(('z', 'needs review'), statuses(rep, 'data'))

    def test_return_flag_safe(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'return_flag')
        only_pure_move_blocks(self, code, rep)
        self.assertEqual([x['status'] for x in rep['exits']], ['matches a known safe pattern'])

    def test_return_became_helper_return(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'return_flag')
        self.assertEqual(code, 1)
        self.assertEqual([x['status'] for x in rep['exits']], ['needs review'])

    def test_break_flag_safe(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'break_flag')
        only_pure_move_blocks(self, code, rep)

    def test_break_became_helper_return(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'break_flag')
        self.assertEqual(code, 1)
        self.assertEqual([x['status'] for x in rep['exits']], ['needs review'])

    def test_tail_return_safe(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'tail_return')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertIn('last thing the caller does', rep['exits'][0]['text'])

    def test_tail_return_no_longer_tail(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'tail_return')
        self.assertEqual(code, 1)

    def test_switch_case_break_after_call(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'switch_case')
        only_pure_move_blocks(self, code, rep)
        self.assertIn('break', rep['exits'][0]['text'])

    def test_switch_case_without_break_after_call(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'switch_case')
        self.assertEqual(code, 1)
        self.assertEqual([x['status'] for x in rep['exits']], ['needs review'])

    def test_switch_case_ending_in_break(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'switch_case_with_break')
        only_pure_move_blocks(self, code, rep)
        self.assertEqual([x['status'] for x in rep['exits']], ['matches a known safe pattern'] * 2)

    def test_switch_case_ending_in_break_falls_through(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'switch_case_with_break')
        self.assertEqual(code, 1)

    def test_positional_values_are_notes(self):
        code, rep = after_report('after', '.m', 'before', 'safe', 'via_method')
        positional = [x for x in rep['other'] if '__' in x['text']]
        self.assertTrue(positional)
        self.assertEqual(set(x['status'] for x in positional), {'note'})

    def test_pointer_passed_by_value(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'pointer_param')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertIn(('p', 'matches a known safe pattern'), statuses(rep, 'data'))

    def test_address_taken_variable_passed_by_pointer(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'addr_param')
        only_pure_move_blocks(self, code, rep)

    def test_flag_tested_the_wrong_way(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'inverted_flag')
        self.assertEqual(code, 1)
        self.assertEqual([x['status'] for x in rep['exits']], ['needs review'])

    def test_flag_value_that_does_not_take_the_branch(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'flag_mismatch')
        self.assertEqual(code, 1)
        self.assertIn('not taken when the helper returns 2', rep['exits'][0]['text'])

    def test_break_after_call_needs_break_after_block(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'dropped_tail')
        self.assertEqual(code, 1)
        self.assertEqual([x['status'] for x in rep['exits']], ['needs review'])

    def test_narrower_parameter(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'narrowing')
        self.assertEqual(code, 1)
        self.assertIn(('x', 'needs review'), statuses(rep, 'data'))

    def test_value_return_with_code_after_block(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'valret')
        self.assertEqual(code, 1)
        self.assertEqual([x['status'] for x in rep['exits']], ['needs review'])

    def test_value_return_helper_falls_off(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'valret_falloff', extra=['-Wno-return-type'])
        self.assertEqual(code, 1)
        self.assertIn('code followed the block', rep['exits'][0]['text'])

    def test_value_return_block_at_tail(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'valret_tail')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertEqual([x['status'] for x in rep['exits']], ['matches a known safe pattern'] * 2)

    def test_value_return_changed_value(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'valret_tail')
        self.assertEqual(code, 1)
        self.assertEqual(rep['exits'][0]['status'], 'needs review')

    def test_unchanged_block_needs_no_review(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'tail_return')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertTrue(rep['pure_move']['pure_move'])

    def test_rewritten_block_needs_review(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'out_param')
        only_pure_move_blocks(self, code, rep)

    def test_self_assigned_in_helper_and_returned(self):
        code, rep = after_report('after', '.m', 'before', 'safe', 'init_self')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))

    def test_self_assigned_only_in_helper(self):
        code, rep = after_report('after', '.m', 'mrr_before', 'mrr_broken', 'init_self')
        self.assertEqual(code, 1)
        self.assertIn('self', ' '.join(x['text'] for x in rep['data'] + rep['other'] if x['status'] == 'needs review'))

    def test_super_from_same_category(self):
        code, rep = after_report('after', '.m', 'before', 'safe', 'super_poke')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))

    def test_super_from_other_category(self):
        code, rep = after_report('after', '.m', 'before', 'broken', 'super_poke', isolated=False)
        self.assertEqual(code, 1)
        self.assertIn('super', ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review'))

    def test_reference_passed_by_reference(self):
        for name in ('refw', 'setv'):
            code, rep = after_report('after', '.mm', 'before', 'safe', name)
            self.assertEqual(code, 0, json.dumps(rep, indent=1))

    def test_referent_passed_by_value(self):
        for name, var in (('refw', 'r'), ('setv', 'b')):
            code, rep = after_report('after', '.mm', 'before', 'broken', name)
            self.assertEqual(code, 1)
            self.assertIn((var, 'needs review'), statuses(rep, 'data'))

    def test_self_helper_returning_nil(self):
        code, rep = after_report('after', '.m', 'before', 'self_nil', 'init_self')
        self.assertEqual(code, 1)
        bad = ' '.join(x['text'] for x in rep['data'] + rep['other'] if x['status'] == 'needs review')
        self.assertIn('return nil', bad)
        self.assertIn(('self', 'needs review'), statuses(rep, 'data'))

    def test_statement_added_before_moved_lines(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'vpre')
        self.assertEqual(code, 1)
        bad = ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review')
        self.assertIn('a = 5', bad)

    def test_return_value_variable_accepted(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'retvar')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertTrue(rep['declared']['added'])

    def test_declared_lines_are_listed(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'tail_return')
        text = extract_check.format_after(rep)
        self.assertIn('Declared lines', text)
        self.assertIn('tail_return_helper(x)', text)

    def test_value_return_helper_with_extra_statement(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'valbody')
        self.assertEqual(code, 1)
        self.assertIn('statements outside the block', rep['exits'][0]['text'])

    def test_value_return_exact_helper(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'valbody')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))

    def test_value_return_other_type(self):
        for name in ('valbool', 'vallong'):
            code, rep = after_report('after', '.c', 'before', 'broken', name)
            self.assertEqual(code, 1, name)
            self.assertIn('return type', rep['exits'][0]['text'], name)

    def test_flag_other_return_takes_branch(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'flag_other')
        self.assertEqual(code, 1)
        self.assertIn('also takes the branch', rep['exits'][0]['text'])

    def test_flag_final_return_takes_branch(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'flag_final')
        self.assertEqual(code, 1)
        self.assertIn('final return also takes the branch', rep['exits'][0]['text'])

    def test_nested_compound_is_not_tail(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'nested_tail')
        self.assertEqual(code, 1)
        self.assertFalse(rep['range']['selection']['tail'])
        self.assertEqual(rep['exits'][0]['status'], 'needs review')

    def test_loop_body_is_not_tail(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'loop_tail')
        self.assertEqual(code, 1)
        self.assertFalse(rep['range']['selection']['tail'])
        self.assertEqual(rep['exits'][0]['status'], 'needs review')

    def test_errors_in_after_version_are_unknown(self):
        import tempfile
        src = isolate(os.path.join(FIX, 'extract', 'before.c'), os.path.join(FIX, 'extract', 'safe.c'), 'tail_return')
        with open(src) as f:
            text = f.read()
        d = tempfile.mkdtemp(prefix='extraction-test-')
        TEMP_DIRS.append(d)
        bad = os.path.join(d, 'safe.c')
        with open(bad, 'w') as f:
            f.write(text + '\nint broken_function(void) { return undefined_name; }\n')
        code, rep = after_report('after', '.c', 'before', 'safe', 'tail_return', after_path=bad)
        self.assertEqual(code, 3)
        self.assertIn('error', ' '.join(rep['unknown']))

    def test_void_self_helper_with_errors(self):
        import tempfile
        src = isolate(os.path.join(FIX, 'extract', 'mrr_before.m'), os.path.join(FIX, 'extract', 'mrr_broken.m'),
                      'init_self')
        with open(src) as f:
            text = f.read()
        assert '    [self commonHelper];' in text
        d = tempfile.mkdtemp(prefix='extraction-test-')
        TEMP_DIRS.append(d)
        bad = os.path.join(d, 'mrr_broken.m')
        # A void helper that ends with return self, assigned to self: neither
        # compiles, and the self pattern must still not match.
        helper_end = '    // init_self}\n}'
        assert helper_end in text
        text = text.replace(helper_end, '    // init_self}\n    return self;\n}', 1)
        with open(bad, 'w') as f:
            f.write(text.replace('    [self commonHelper];', '    self = [self commonHelper];'))
        code, rep = after_report('after', '.m', 'mrr_before', 'mrr_broken', 'init_self', after_path=bad)
        self.assertEqual(code, 3)
        self.assertIn(('self', 'needs review'), statuses(rep, 'data'))

    def test_missing_before_file(self):
        code, out, err = run_tool(['after', '--before-file', '/nonexistent/x.c', '--after-file', '/nonexistent/y.c',
                                   '--extract', '/nonexistent/x.c:1-2=/nonexistent/x.c:3-4', '--binary', BINARY,
                                   '--no-build', '--repo', REPO, '--', '-x', 'c', '/nonexistent/x.c'])
        self.assertEqual(code, 2)
        self.assertNotIn('Traceback', err)
        self.assertIn('x.c', err)

    def test_caller_gains_a_statement(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'caller_extra')
        self.assertEqual(code, 1)
        self.assertIn('gtail = 9', ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review'))

    def test_caller_loses_a_statement(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'removed_line')
        self.assertEqual(code, 1)
        self.assertIn('work(a)', ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review'))

    def test_conditional_write_returned_loses_earlier_value(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'condret')
        self.assertEqual(code, 1)
        self.assertIn(('changed', 'needs review'), statuses(rep, 'data'))
        self.assertIn('only on some paths', ' '.join(x['text'] for x in rep['data']))

    def test_assignment_after_a_possible_exit_is_not_definite(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'exit_before', extra=['-Wno-sometimes-uninitialized'])
        self.assertEqual(code, 1)
        self.assertIn(('x', 'needs review'), statuses(rep, 'data'))

    def test_call_moved_earlier(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'placement')
        self.assertEqual(code, 1)
        self.assertIn('not where the block was', ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review'))

    def test_call_after_a_case_label(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'case_call')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))

    def test_call_where_the_block_was(self):
        code, rep = after_report('after', '.c', 'before', 'safe', 'placement')
        self.assertEqual(code, 0, json.dumps(rep, indent=1))
        self.assertIn('where the block was', ' '.join(x['text'] for x in rep['other']))

    def test_return_self_without_self_pattern(self):
        code, rep = after_report('after', '.m', 'before', 'broken', 'self_any')
        self.assertEqual(code, 1)
        self.assertIn('return self', ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review'))

    def test_declaration_after_moved_lines(self):
        code, rep = after_report('after', '.c', 'before', 'broken', 'decl_after')
        self.assertEqual(code, 1)
        self.assertIn('int dshadow = 5', ' '.join(x['text'] for x in rep['other'] if x['status'] == 'needs review'))

    def test_arc_out_parameter_strong(self):
        code, rep = after_report('after', '.m', 'before', 'safe', 'out_object')
        only_pure_move_blocks(self, code, rep)
        self.assertIn(('result', 'matches a known safe pattern'),
                      [(x['subject'], x['status']) for x in rep['data'] if x['kind'] == 'ownership'])

    def test_arc_out_parameter_autoreleasing_default(self):
        code, rep = after_report('after', '.m', 'before', 'broken', 'out_object')
        self.assertEqual(code, 1)
        own = [x for x in rep['data'] if x['kind'] == 'ownership']
        self.assertEqual(own[0]['status'], 'needs review')
        self.assertIn('the ARC default', own[0]['text'])

    def test_method_helper_keeps_self(self):
        code, rep = after_report('after', '.m', 'before', 'safe', 'via_method')
        only_pure_move_blocks(self, code, rep)
        self.assertIn('method of the same class', '\n'.join(x['text'] for x in rep['other']))

    def test_c_function_helper_changes_self(self):
        code, rep = after_report('after', '.m', 'before', 'broken', 'via_method')
        self.assertEqual(code, 1)
        self.assertIn('needs review', [x['status'] for x in rep['other']])
        self.assertIn(('holder', 'needs review'), statuses(rep, 'data'))


class Compiled(unittest.TestCase):
    def check(self, ext, version, name, expected, code_expected, base='before'):
        code, rep = after_report('compiled', ext, base, version, name)
        self.assertEqual((rep['result'], code), (expected, code_expected), json.dumps(rep, indent=1))
        return rep

    def test_out_param_identical(self):
        self.check('.c', 'safe', 'out_param', 'identical', 0)

    def test_dropped_write_back_differs(self):
        self.check('.c', 'broken', 'out_param', 'different', 1)

    def test_return_flag_identical(self):
        self.check('.c', 'safe', 'return_flag', 'identical', 0)

    def test_return_from_helper_only_differs(self):
        self.check('.c', 'broken', 'return_flag', 'different', 1)

    def test_break_flag_identical(self):
        self.check('.c', 'safe', 'break_flag', 'identical', 0)

    def test_break_from_helper_only_differs(self):
        self.check('.c', 'broken', 'break_flag', 'different', 1)

    def test_switch_case_identical(self):
        self.check('.c', 'safe', 'switch_case', 'identical', 0)

    def test_switch_case_fall_through_differs(self):
        self.check('.c', 'broken', 'switch_case', 'different', 1)

    def test_enclosing_function_inlined_everywhere_compares_the_file(self):
        rep = self.check('.c', 'inline_safe', 'inlined_everywhere', 'identical', 0, base='inline_before')
        self.assertIn('every function', rep['scope'])

    def test_enclosing_function_inlined_everywhere_reordered_differs(self):
        rep = self.check('.c', 'inline_broken', 'inlined_everywhere', 'different', 1, base='inline_before')
        self.assertIn('calls_inlined', ' '.join(rep['differing_functions']))

    def test_same_static_identical(self):
        self.check('.c', 'statics_safe', 'touch', 'identical', 0, base='statics_before')

    def test_other_static_differs(self):
        self.check('.c', 'statics_broken', 'touch', 'different', 1, base='statics_before')

    def test_static_local_moved_with_block(self):
        self.check('.c', 'statics_safe', 'moved_static', 'identical', 0, base='statics_before')

    def test_static_local_not_renamed_back_differs(self):
        # Without the renaming, @counter_fn.calls and @counter_fn_helper.calls differ.
        saved = extract_check.rename_moved_statics
        try:
            lines = ['define void @counter_fn(i32 %0) {', '  store i32 %0, ptr @counter_fn_helper.calls', '}']
            before = {'declared_inside': [{'name': 'calls', 'static_local': True}]}
            out = saved(lines, before, {'ir_name': 'counter_fn'}, {'ir_name': 'counter_fn_helper'})
            self.assertIn('@counter_fn.calls', out[1])
            out = saved(lines, {'declared_inside': []}, {'ir_name': 'counter_fn'}, {'ir_name': 'counter_fn_helper'})
            self.assertIn('@counter_fn_helper.calls', out[1])
        finally:
            extract_check.rename_moved_statics = saved

    def check_glob(self, ext, version, name, expected, code_expected, extra=()):
        code, rep = after_report('compiled', ext, 'glob_before', version, name, extra=extra)
        self.assertEqual((rep['result'], code), (expected, code_expected), json.dumps(rep, indent=1))
        return rep

    def test_objc_globals(self):
        for extra in ((), ('-fno-objc-arc', '-Wno-objc-root-class')):
            for name in ('cfs', 'cls', 'sel'):
                self.check_glob('.m', 'glob_same', name, 'identical', 0, extra)
                self.check_glob('.m', 'glob_diff', name, 'different', 1, extra)

    def test_function_name_strings_differ_by_design(self):
        rep = self.check_glob('.m', 'glob_same', 'ffunc', 'different', 1)
        self.assertIn('function-name', rep['reason'])

    def test_c_globals(self):
        for name in ('table', 'ptrconst', 'blockmoved', 'sw'):
            self.check_glob('.c', 'glob_same', name, 'identical', 0)
            self.check_glob('.c', 'glob_diff', name, 'different', 1)

    def test_tail_return_identical(self):
        self.check('.c', 'safe', 'tail_return', 'identical', 0)

    def test_not_inlined_is_not_comparable(self):
        rep = self.check('.c', 'safe', 'not_inlined', 'not comparable', 3)
        self.assertIn('helper not inlined', rep['reason'])

    def test_objc_method_helper_is_not_comparable(self):
        rep = self.check('.m', 'safe', 'via_method', 'not comparable', 3)
        self.assertIn('message send', rep['reason'])

    def test_arc_strong_out_parameter_identical(self):
        self.check('.m', 'safe', 'out_object', 'identical', 0)

    def test_arc_autoreleasing_out_parameter_differs(self):
        self.check('.m', 'broken', 'out_object', 'different', 1)


class Normalization(unittest.TestCase):
    def test_renumbering_and_globals(self):
        globs = {'@.str': 'private unnamed_addr constant [2 x i8] c"a\\00", align 1',
                 '@.str.1': 'private unnamed_addr constant [2 x i8] c"a\\00", align 1'}
        a = ['define void @f(i32 noundef %0) #0 {', '  %2 = add i32 %0, 1, !dbg !7',
             '  call void @g(ptr @.str) #3', '  br label %3', '3:', '  ret void', '}']
        b = ['define void @f(i32 noundef %0) #1 {', '  %5 = add i32 %0, 1',
             '  call void @g(ptr @.str.1) #2', '  br label %9', '9:  ; preds = %1', '  ret void', '}']
        self.assertEqual(extract_check.normalize_ir(a, globs), extract_check.normalize_ir(b, globs))

    def test_phi_operand_order(self):
        def body(phi):
            return ['define i32 @f(i1 %0) {', '  br i1 %0, label %2, label %4', '2:', '  %3 = add i32 1, 2',
                    '  br label %4', '4:', '  %5 = phi i32 ' + phi, '  ret i32 %5', '}']
        a = body('[ 0, %1 ], [ %3, %2 ]')
        b = body('[ %3, %2 ], [ 0, %1 ]')
        c = body('[ 7, %1 ], [ %3, %2 ]')
        self.assertEqual(extract_check.normalize_ir(a, {}), extract_check.normalize_ir(b, {}))
        self.assertNotEqual(extract_check.normalize_ir(a, {}), extract_check.normalize_ir(c, {}))

    def test_named_types_are_not_renumbered(self):
        a = ['define void @f() {', '  %1 = alloca %struct.fd_set, align 4', '  ret void', '}']
        b = ['define void @f() {', '  %1 = alloca %struct.other, align 4', '  ret void', '}']
        self.assertIn('alloca %struct.fd_set', '\n'.join(extract_check.normalize_ir(a, {})))
        self.assertNotEqual(extract_check.normalize_ir(a, {}), extract_check.normalize_ir(b, {}))

    def test_semicolon_inside_string_is_kept(self):
        a = ['define void @f() {', '  call void asm sideeffect "nop; nop", ""() ; comment', '}']
        self.assertIn('"nop; nop"', '\n'.join(extract_check.normalize_ir(a, {})))

    def test_mutable_globals_compare_by_name(self):
        globs = {'@s_hits': 'internal global i32 0, align 4', '@s_misses': 'internal global i32 0, align 4'}
        a = ['define void @f() {', '  store i32 1, ptr @s_hits', '}']
        b = ['define void @f() {', '  store i32 1, ptr @s_misses', '}']
        self.assertNotEqual(extract_check.normalize_ir(a, globs), extract_check.normalize_ir(b, globs))

    def test_refers_to(self):
        self.assertTrue(extract_check.refers_to('@h', '  call void @h(i32 1)'))
        self.assertFalse(extract_check.refers_to('@h', '  store i32 1, ptr @h.calls'))
        self.assertFalse(extract_check.refers_to('@h', '  call void @h2()'))

    def test_different_constants_differ(self):
        a = ['define void @f() {', '  call void @g(i32 1)', '}']
        b = ['define void @f() {', '  call void @g(i32 2)', '}']
        self.assertNotEqual(extract_check.normalize_ir(a, {}), extract_check.normalize_ir(b, {}))


if __name__ == '__main__':
    unittest.main()


class CompileDatabase(unittest.TestCase):
    def test_case_insensitive_match(self):
        import tempfile
        d = tempfile.mkdtemp()
        try:
            cdb = os.path.join(d, 'cdb.jsonl')
            with open(cdb, 'w') as f:
                f.write(json.dumps({'meta': True}) + '\n')
                f.write(json.dumps({'target': 'T', 'file': 'sources/tmux/X.m', 'directory': '/root',
                                    'arguments': ['-x', 'objective-c', '/root/sources/tmux/X.m']}) + '\n')
            args, main, entry = extract_check.compile_command('/repo', 'sources/Tmux/X.m', cdb)
            self.assertEqual(main, '/root/sources/tmux/X.m')
            self.assertIn('case', entry['note'])
            self.assertEqual(entry['cdb'], cdb)
            self.assertIn(cdb, extract_check.configuration_text(args, 'arm64', entry))
        finally:
            import shutil
            shutil.rmtree(d)
