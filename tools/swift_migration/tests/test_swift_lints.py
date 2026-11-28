"""Tests for tools/swift_migration/swift_lints.py.

Run from the repository root:
    python3 -B -m unittest tools/swift_migration/tests/test_swift_lints.py

Expectations are literal: line and column numbers are written by hand. Tests
of the modes build temporary git repositories, so they never depend on the
real tree.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
FIXTURES = os.path.join(HERE, 'fixtures', 'swift_lints')
SCRIPT = os.path.join(TOOL_DIR, 'swift_lints.py')
if TOOL_DIR not in sys.path:
    sys.path.insert(0, TOOL_DIR)
sys.dont_write_bytecode = True

import swift_lints as sl  # noqa: E402


def lint(src):
    findings, _ = sl.lint_source('t.swift', src)
    return [(f.line, f.col, f.lint) for f in findings]


def marked(src):
    return sl.lint_source('t.swift', src)[1]


# ---------------------------------------------------------------------------
# Lexer

class LexerTests(unittest.TestCase):
    def kinds(self, src):
        return [(t.kind, t.text) for t in sl.lex(src).tokens]

    def test_nested_block_comment_then_code(self):
        self.assertEqual(lint('/* a /* b */ c */ x!'), [(1, 20, 'force-unwrap')])
        self.assertEqual(self.kinds('/* a /* b */ c */ x'),
                         [('block_comment', '/* a /* b */ c */'), ('ident', 'x')])

    def test_line_comment(self):
        self.assertEqual(self.kinds('a // b "c\nd'), [('ident', 'a'), ('line_comment', '// b "c'), ('ident', 'd')])

    def test_plain_string_with_escaped_quote_then_code(self):
        self.assertEqual(lint('let s = "a\\"b!"; x!'), [(1, 19, 'force-unwrap')])

    def test_escaped_backslash_ends_string(self):
        self.assertEqual(lint('let s = "\\\\"; x!'), [(1, 16, 'force-unwrap')])

    def test_raw_string_with_one_and_two_hashes(self):
        self.assertEqual(lint('let s = #"a"b\\"#; x!'), [(1, 20, 'force-unwrap')])
        self.assertEqual(lint('let s = ##"a"#b"##; x!'), [(1, 22, 'force-unwrap')])
        self.assertEqual(self.kinds('##"a"#b"##'), [('string', '##"a"#b"##')])

    def test_multiline_string_with_quotes_inside(self):
        src = 'let s = """\n"a" "" x!\n"""\ny!'
        self.assertEqual(lint(src), [(4, 2, 'force-unwrap')])

    def test_multiline_raw_string(self):
        src = 'let s = #"""\n"""\nx!\n"""#\ny!'
        self.assertEqual(lint(src), [(5, 2, 'force-unwrap')])

    def test_multiline_line_continuation(self):
        src = 'let s = """\nabc \\\ndef\n"""\nz!'
        self.assertEqual(lint(src), [(5, 2, 'force-unwrap')])

    def test_interpolation_code_is_linted(self):
        self.assertEqual(lint('let s = "a\\(x!)b"'), [(1, 14, 'force-unwrap')])

    def test_interpolation_with_nested_string_containing_paren(self):
        self.assertEqual(lint('let s = "\\(f(")"))" + y!'), [(1, 24, 'force-unwrap')])

    def test_interpolation_nested_two_deep(self):
        self.assertEqual(lint('let s = "\\("\\(z!)")"'), [(1, 16, 'force-unwrap')])

    def test_raw_string_interpolation_needs_hash(self):
        self.assertEqual(lint('let s = #"\\#(x!)"#'), [(1, 15, 'force-unwrap')])
        self.assertEqual(lint('let s = #"\\(x!)"#'), [])

    def test_interpolation_in_multiline_string(self):
        src = 'let s = """\n\\(a ? "x" : "y")\n"""\nq!'
        self.assertEqual(lint(src), [(4, 2, 'force-unwrap')])

    def test_extended_regex_literal(self):
        self.assertEqual(lint('let r = #/a"b(/#; x!'), [(1, 20, 'force-unwrap')])

    def test_tokens_for_operators(self):
        self.assertEqual(self.kinds('a!=b'), [('ident', 'a'), ('op', '!'), ('op', '='), ('ident', 'b')])
        self.assertEqual(self.kinds('a != b'), [('ident', 'a'), ('op', '!='), ('ident', 'b')])
        self.assertEqual(self.kinds('x as! T'), [('ident', 'x'), ('kw', 'as!'), ('ident', 'T')])
        self.assertEqual(self.kinds('a..<b'), [('ident', 'a'), ('op', '..<'), ('ident', 'b')])
        self.assertEqual(self.kinds('a+/*c*/b'), [('ident', 'a'), ('op', '+'), ('block_comment', '/*c*/'),
                                                  ('ident', 'b')])
        self.assertEqual(self.kinds('`var` $0 @objc #if 0x1F 1.5e-3'),
                         [('ident', 'var'), ('ident', '$0'), ('attr', '@objc'), ('pound', '#if'),
                          ('number', '0x1F'), ('number', '1.5e-3')])

    def test_literal_count(self):
        self.assertEqual(sl.lex('"a" + #"b"# + """\nc\n""" + "\\("d")"').literal_count, 5)

    def test_mask_keeps_length_lines_and_interpolated_code(self):
        src = 'a /* x\ny */ "s\\(b + "t")u" // c\n#"r"#'
        lx = sl.lex(src)
        m = sl.mask(lx)
        self.assertEqual(len(m), len(src))
        self.assertEqual(m, 'a     \n' + ' ' * 9 + 'b +' + ' ' * 12 + '\n     ')

    def test_errors(self):
        cases = [('let s = "abc', 'unterminated string literal'),
                 ('let s = "abc\n"', 'unterminated string literal'),
                 ('/* a /* b */', 'unterminated block comment'),
                 ('let s = """\nabc\n', 'unterminated string literal'),
                 ('let s = "\\(x', 'unterminated string interpolation'),
                 ('let r = #/abc', 'unterminated regex literal')]
        for src, msg in cases:
            with self.assertRaises(sl.LexError) as cm:
                sl.lex(src)
            self.assertEqual(cm.exception.message, msg, src)

    def test_tokens_cover_their_text(self):
        samples = ['let a = b as! C; try? d(); x!.y ?? z /* c /* d */ */ // e\n',
                   '"s\\(f("t"))u" + #"r"# + """\nm\n""" + #/a\\/#b/# + `var` + $0 + @objc + #if + 0x1F + 9',
                   'a as', 'a try', '9', 'x!', 'a #', 'a @', 'a `', 'a ..', 'a /', 'a.', '#a', '/**/ x', '`v`',
                   'a..<b', 'f(]', '"\\(a)"']
        for src in samples:
            last = 0
            for t in sl.lex(src).tokens:
                text = src[t.start + 1:t.end - 1] if src[t.start] == '`' and t.kind == 'ident' else src[t.start:t.end]
                self.assertEqual(t.text, text, (src, t))
                self.assertGreaterEqual(t.start, last, (src, t))
                self.assertGreater(t.end, t.start, (src, t))
                last = t.end

    def test_edge_tokens(self):
        self.assertEqual(self.kinds('#a'), [('pound', '#a')])
        self.assertEqual(self.kinds('#/a/#b'), [('regex', '#/a/#'), ('ident', 'b')])
        self.assertEqual(self.kinds('#/a\\/#b/#'), [('regex', '#/a\\/#b/#')])
        self.assertEqual(self.kinds('!=b'), [('op', '!='), ('ident', 'b')])
        self.assertEqual(self.kinds('a /*c*/!= b'), [('ident', 'a'), ('block_comment', '/*c*/'), ('op', '!='),
                                                     ('ident', 'b')])
        self.assertEqual(self.kinds('9 a as'), [('number', '9'), ('ident', 'a'), ('ident', 'as')])
        self.assertEqual(self.kinds('a # @ `'), [('ident', 'a'), ('punct', '#'), ('punct', '@'), ('punct', '`')])
        self.assertEqual(lint('/**/ x!'), [(1, 7, 'force-unwrap')])

    def test_unbalanced_brackets_are_a_lexer_failure(self):
        with self.assertRaises(sl.LexError) as cm:
            sl.lint_source('t.swift', 'func f() {\n')
        self.assertIn("unclosed '{'", cm.exception.message)
        with self.assertRaises(sl.LexError) as cm:
            sl.lint_source('t.swift', 'f(])')
        self.assertIn("unbalanced ']'", cm.exception.message)


# ---------------------------------------------------------------------------
# Each lint: a positive, and the same token in a comment, a nested block comment, a plain string, a raw
# string, a multi-line string and a literal nested in an interpolation, each followed by a positive on the
# next line that must still be found (so code after a literal is never missed).

CONTEXTS = [
    ('line comment', '// {s}', 2),
    ('nested block comment', '/* outer /* {s} */ still comment */', 2),
    ('plain string', 'let q = "{s}"', 2),
    ('raw string', 'let q = #"{s}"#', 2),
    ('multi-line string', 'let q = """\n{s}\n"""', 4),
    ('interpolation literal', 'let q = "a\\(f("{s}"))b"', 2),
]

# lint id: (snippet, [(column, lint)] for the snippet alone on a line)
POSITIVES = {
    'unsafe-pointer-unmarked': ('let p: UnsafePointer<Int>? = nil', [(8, 'unsafe-pointer-unmarked')]),
    'force-unwrap': ('let v = x!', [(10, 'force-unwrap')]),
    'forced-cast': ('let v = x as! Int', [(11, 'forced-cast')]),
    'forced-try': ('let v = try! f()', [(9, 'forced-try')]),
    'unowned': ('unowned let o: Foo', [(1, 'unowned')]),
    'trap-call': ('fatalError()', [(1, 'trap-call')]),
    'stage-one-concurrency': ('await f()', [(1, 'stage-one-concurrency')]),
    'sync-enter-argument': ('objc_sync_enter(a.b)', [(1, 'sync-enter-argument'), (1, 'sync-pairing')]),
    'sync-pairing': ('objc_sync_enter(lock)', [(1, 'sync-pairing')]),
    'lock-stored-property': ('class C { var l = os_unfair_lock() }', [(15, 'lock-stored-property')]),
    'iuo-outlet': ('class C { @IBOutlet var v: NSView! }', [(34, 'iuo-outlet')]),
    'iuo-unmarked': ('func f(a: Int!) { }', [(14, 'iuo-unmarked')]),
}


class ContextTests(unittest.TestCase):
    def test_positives_alone(self):
        for lint_id, (snippet, expected) in POSITIVES.items():
            self.assertEqual(lint(snippet), [(1, c, l) for c, l in expected], lint_id)

    def test_negatives_in_comments_and_literals(self):
        for lint_id, (snippet, expected) in POSITIVES.items():
            for name, template, next_line in CONTEXTS:
                src = template.format(s=snippet) + '\n' + snippet
                self.assertEqual(lint(src), [(next_line, c, l) for c, l in expected], '%s in %s' % (lint_id, name))

    def test_marker_format_in_literals_is_not_reported(self):
        bad = '// SWIFT-MIGRATION-SHIM:'
        for name, template, next_line in CONTEXTS[2:]:
            src = template.format(s=bad) + '\n' + bad
            self.assertEqual(lint(src), [(next_line, 4, 'marker-format')], name)

    def test_marker_format_in_block_comments_is_reported(self):
        self.assertEqual(lint('/* outer /* SWIFT-MIGRATION-SHIM: x */ y */'), [(1, 13, 'marker-format')])


# ---------------------------------------------------------------------------
# Lint by lint

class ForceUnwrapTests(unittest.TestCase):
    def test_not_force_unwraps(self):
        src = '\n'.join([
            'if !flag { }',
            'let a = b != c',
            'let d = e ?? f',
            'g(!h)',
            'var i: Int!',
            'func j(k: Int!, l m: [String: Int]!) -> String! { }',
            'var n: [String: Int]! = [:]',
            'var o: Dictionary<String, Int>!',
            'var p: Optional<Int>!',
            'init!(q: Int) { }',
            'let r: (() -> Void)! = nil',
            'let s = { (t: Int!) in t }',
            'subscript(u: Int) -> Int! { }',
            '#if !DEBUG',
            '#endif',
            'var w: Int! { get }',
        ])
        # None is a force unwrap. Each is an implicitly unwrapped type outside a property (file-scope variables,
        # parameters, results, init!), so each is iuo-unmarked (decisions.md, 2026-11-20). The file-scope vars are
        # also file-scope-var (decisions.md, 2026-11-20).
        self.assertEqual(lint(src), [
            (5, 1, 'file-scope-var'), (5, 11, 'iuo-unmarked'), (6, 14, 'iuo-unmarked'), (6, 35, 'iuo-unmarked'),
            (6, 47, 'iuo-unmarked'), (7, 1, 'file-scope-var'), (7, 21, 'iuo-unmarked'), (8, 1, 'file-scope-var'),
            (8, 31, 'iuo-unmarked'), (9, 1, 'file-scope-var'), (9, 21, 'iuo-unmarked'), (10, 5, 'iuo-unmarked'),
            (11, 20, 'iuo-unmarked'), (12, 18, 'iuo-unmarked'), (13, 25, 'iuo-unmarked'), (16, 1, 'file-scope-var'),
            (16, 11, 'iuo-unmarked')])

    def test_force_unwraps(self):
        src = '\n'.join([
            'x!.y',             # 1:2
            'a[0]!',            # 2:5
            'f()!',             # 3:4
            'z!!',              # 4:2 4:3
            'let v: Int = w!',  # 5:15
            'func g(a: Int = b!) { }',  # 6:18
            'let c = d ? e! : f!',  # 7:14 7:19
            'let m = [k: v!]',  # 8:14
            'h(x: y!)',         # 9:7
            'if q!=nil { }',    # 10:5
            'var r: Int! = s!',  # 11:16
            'let t = u /* c */!',  # not left-bound after a comment: prefix, not a force unwrap
        ])
        self.assertEqual(lint(src), [
            (1, 2, 'force-unwrap'), (2, 5, 'force-unwrap'), (3, 4, 'force-unwrap'), (4, 2, 'force-unwrap'),
            (4, 3, 'force-unwrap'), (5, 15, 'force-unwrap'), (6, 18, 'force-unwrap'), (7, 14, 'force-unwrap'),
            (7, 19, 'force-unwrap'), (8, 14, 'force-unwrap'), (9, 7, 'force-unwrap'), (10, 5, 'force-unwrap'),
            (11, 1, 'file-scope-var'), (11, 11, 'iuo-unmarked'), (11, 16, 'force-unwrap')])

    def test_type_context_ends_at_the_line_end(self):
        self.assertEqual(lint('var a: Int\nb!'), [(1, 1, 'file-scope-var'), (2, 2, 'force-unwrap')])
        self.assertEqual(lint('func f() -> Int\nx!'), [(2, 2, 'force-unwrap')])

    def test_nested_generic_closers_in_one_operator(self):
        self.assertEqual(lint('func f(a: P<Q<Int>?>) -> R? {\n    x!\n}'), [(2, 6, 'force-unwrap')])
        self.assertEqual(lint('@IBOutlet var f: A<B<C>>!'), [(1, 11, 'file-scope-var'), (1, 23, 'iuo-outlet')])
        self.assertEqual(lint('func g(a: A<B) {\n    y!\n}'), [(2, 6, 'force-unwrap')])

    def test_case_let_is_not_a_type_annotation(self):
        self.assertEqual(lint('switch v { case let x: y! }'), [(1, 25, 'force-unwrap')])


class StructureTests(unittest.TestCase):
    def test_comments_between_tokens_do_not_hide_anything(self):
        self.assertEqual(lint('assert /* c */ (x)'), [(1, 1, 'trap-call')])
        src = 'do {\n    objc_sync_enter(lock) // c\n    defer { objc_sync_exit(lock) } // d\n}'
        self.assertEqual(lint(src), [])

    def test_unowned_at_end_of_file(self):
        self.assertEqual(lint('let unowned'), [])

    def test_initializer_and_subscript_parameters(self):
        src = '\n'.join(['init(a: Int!) { }', 'init?(a: Int!) { }', 'init<T>(a: T!) { }',
                         'subscript(a: Int!) -> Int { }', 'init!<T>(a: T) { }', '{ [weak self] (a: Int!) in a }'])
        # Not force unwraps; implicitly unwrapped parameters and init! are iuo-unmarked.
        self.assertEqual(lint(src), [(1, 12, 'iuo-unmarked'), (2, 13, 'iuo-unmarked'), (3, 13, 'iuo-unmarked'),
                                     (4, 17, 'iuo-unmarked'), (5, 5, 'iuo-unmarked'), (6, 22, 'iuo-unmarked')])

    def test_type_bodies(self):
        self.assertEqual(lint('actor A { var l = os_unfair_lock() }'),
                         [(1, 1, 'stage-one-concurrency'), (1, 15, 'lock-stored-property')])
        self.assertEqual(lint('class C { let s = "\\(a)"; var l = os_unfair_lock() }'),
                         [(1, 31, 'lock-stored-property')])
        self.assertEqual(lint('class C { let a = [1]; var l = os_unfair_lock() }'),
                         [(1, 28, 'lock-stored-property')])


class SurvivorTests(unittest.TestCase):
    """Cases added after the mutation pass, each for a mutant that survived the first test set."""

    def test_short_and_edge_tokens(self):
        kinds = lambda src: [(t.kind, t.text) for t in sl.lex(src).tokens]
        self.assertEqual(kinds('@a'), [('attr', '@a')])
        self.assertEqual(kinds('a as!b'), [('ident', 'a'), ('kw', 'as!'), ('ident', 'b')])
        self.assertEqual(kinds('a..'), [('ident', 'a'), ('op', '..')])
        self.assertEqual(kinds('a+// c'), [('ident', 'a'), ('op', '+'), ('line_comment', '// c')])
        self.assertEqual(kinds('#/\\a/#'), [('regex', '#/\\a/#')])
        self.assertEqual(kinds('#/a/b/#'), [('regex', '#/a/b/#')])
        with self.assertRaises(sl.LexError):
            sl.lex('let s = "a\\')

    def test_tokens_at_the_start_and_end_of_a_file(self):
        for src in ('actor', 'Task', 'async', 'func', 'init', 'class', 'var', 'unowned', 'a\nactor', 'subscript'):
            self.assertIsInstance(lint(src), list, src)
        self.assertEqual(lint('case let x: y!'), [(1, 14, 'force-unwrap')])
        self.assertEqual(lint('{ (a: Int!) in a }'), [(1, 10, 'iuo-unmarked')])
        self.assertEqual(lint('{ [weak self] (a: Int!) in a }'), [(1, 22, 'iuo-unmarked')])
        self.assertEqual(lint('h(x: y!)'), [(1, 7, 'force-unwrap')])
        self.assertEqual(lint('func f() { var l = os_unfair_lock() }'), [])

    def test_parameter_clause_is_only_the_next_paren(self):
        self.assertEqual(lint('func f() {\n    g(x: y!)\n}'), [(2, 11, 'force-unwrap')])
        self.assertEqual(lint('init!(a: Int!) { }'), [(1, 5, 'iuo-unmarked'), (1, 13, 'iuo-unmarked')])
        self.assertEqual(lint('handler!(y)'), [(1, 8, 'force-unwrap')])

    def test_annotation_ends(self):
        self.assertEqual(lint('class C { var x: Int }; y!'), [(1, 26, 'force-unwrap')])
        self.assertEqual(lint('var a: Int; b!'), [(1, 1, 'file-scope-var'), (1, 14, 'force-unwrap')])
        self.assertEqual(lint('let f = { (a: Int) -> Int in a! }'), [(1, 31, 'force-unwrap')])
        self.assertEqual(lint('@IBOutlet var h: Foo<(Int) -> Int, Bar>!'),
                         [(1, 11, 'file-scope-var'), (1, 39, 'iuo-outlet')])
        self.assertEqual(lint('@IBOutlet @objc var x: NSView!'), [(1, 17, 'file-scope-var'), (1, 30, 'iuo-outlet')])

    def test_unowned_call_is_not_a_modifier(self):
        self.assertEqual(lint('let y = unowned(x)'), [])

    def test_bare_async_call(self):
        self.assertEqual(lint('async(execute: w)'), [])

    def test_lock_argument_with_nested_brackets(self):
        src = 'objc_sync_enter(a[0])\ndefer { objc_sync_exit(a[0]) }\n' \
              'objc_sync_enter(c.first { $0 })\ndefer { objc_sync_exit(c.first { $0 }) }\n' \
              'objc_sync_enter("\\(a)")\ndefer { objc_sync_exit("\\(a)") }'
        self.assertEqual(lint(src), [(1, 1, 'sync-enter-argument'), (3, 1, 'sync-enter-argument'),
                                     (5, 1, 'sync-enter-argument')])


class CastTryTests(unittest.TestCase):
    def test_forms(self):
        self.assertEqual(lint('a as? B\na as B\ntry? f()\ntry f()'), [])
        self.assertEqual(lint('a as! B\ntry! f()'), [(1, 3, 'forced-cast'), (2, 1, 'forced-try')])


class UnownedTests(unittest.TestCase):
    def test_not_unowned(self):
        self.assertEqual(lint('let unowned = 1\nx.unowned\nprint(unowned)\nlet y = unowned + 1'), [])

    def test_unowned(self):
        src = 'f { [unowned self] in }\nunowned(unsafe) let a: A\nunowned(safe) var b: B\nprivate unowned let c: C'
        self.assertEqual(lint(src), [(1, 6, 'unowned'), (2, 1, 'unowned'), (3, 1, 'unowned'), (3, 15, 'file-scope-var'),
                                     (4, 9, 'unowned')])


class TrapCallTests(unittest.TestCase):
    def test_not_trap_calls(self):
        src = '\n'.join(['it_fatalError("x")', 'it_assert(c)', 'func assert(_ c: Bool) { }',
                         'logger.fatalError("x")', 'dispatchPrecondition(condition: .onQueue(.main))',
                         'let precondition = 1'])
        self.assertEqual(lint(src), [])

    def test_trap_calls(self):
        self.assertEqual(lint('Swift.assert(x)\nprecondition(x)\nassert(x, "m")\nfatalError ("m")'),
                         [(1, 7, 'trap-call'), (2, 1, 'trap-call'), (3, 1, 'trap-call'), (4, 1, 'trap-call')])


class ConcurrencyTests(unittest.TestCase):
    def test_allowed(self):
        src = '\n'.join(['DispatchQueue.main.async { }', 'queue.async(execute: w)', 'let actor = 1', 'actor.run()',
                         'self.actor', 'nonisolated func f() { }', 'foo(async: true)', 'Foo.Task', 'MainActor.shared'])
        self.assertEqual(lint(src), [])

    def test_banned(self):
        src = '\n'.join(['func f() async { }', 'async let x = f()', 'Task { }', 'Task.detached { }', 'actor Foo { }',
                         '@MainActor func g() { }', 'MainActor.assumeIsolated { }', 'let h: () async -> Void'])
        self.assertEqual(lint(src), [(1, 10, 'stage-one-concurrency'), (2, 1, 'stage-one-concurrency'),
                                     (3, 1, 'stage-one-concurrency'), (4, 1, 'stage-one-concurrency'),
                                     (5, 1, 'stage-one-concurrency'), (6, 1, 'stage-one-concurrency'),
                                     (7, 1, 'stage-one-concurrency'), (8, 11, 'stage-one-concurrency')])


class SyncTests(unittest.TestCase):
    def test_standard_form(self):
        src = 'do {\n    let lock: AnyObject = self\n    objc_sync_enter(lock)\n    defer { objc_sync_exit(lock) }\n}'
        self.assertEqual(lint(src), [])

    def test_exit_not_on_the_next_line(self):
        src = 'objc_sync_enter(lock)\n\ndefer { objc_sync_exit(lock) }'
        self.assertEqual(lint(src), [(1, 1, 'sync-pairing'), (3, 9, 'sync-pairing')])

    def test_exit_on_another_constant(self):
        self.assertEqual(lint('objc_sync_enter(a)\ndefer { objc_sync_exit(b) }'),
                         [(1, 1, 'sync-pairing'), (2, 9, 'sync-pairing')])

    def test_exit_without_defer(self):
        self.assertEqual(lint('objc_sync_enter(a)\nobjc_sync_exit(a)'), [(1, 1, 'sync-pairing'), (2, 1, 'sync-pairing')])

    def test_stray_exit(self):
        self.assertEqual(lint('objc_sync_exit(a)'), [(1, 1, 'sync-pairing')])

    def test_argument_not_a_constant(self):
        self.assertEqual(lint('objc_sync_enter(x!)\ndefer { objc_sync_exit(x!) }'),
                         [(1, 1, 'sync-enter-argument'), (1, 18, 'force-unwrap'), (2, 25, 'force-unwrap')])
        self.assertEqual(lint('objc_sync_enter(self.foo)\ndefer { objc_sync_exit(self.foo) }'),
                         [(1, 1, 'sync-enter-argument')])
        self.assertEqual(lint('objc_sync_enter(a?.b)\ndefer { objc_sync_exit(a?.b) }'),
                         [(1, 1, 'sync-enter-argument')])


class LockPropertyTests(unittest.TestCase):
    def test_not_stored_properties(self):
        src = '\n'.join(['class C {', '    func f() { var l = os_unfair_lock() }',
                         '    var p: UnsafeMutablePointer<os_unfair_lock>', '    let a = OSAllocatedUnfairLock()',
                         '    var c: os_unfair_lock { os_unfair_lock() }', '}', 'var g = os_unfair_lock()'])
        self.assertEqual(lint(src), [(3, 12, 'unsafe-pointer-unmarked'), (7, 1, 'file-scope-var')])

    def test_stored_properties(self):
        src = '\n'.join(['final class C {', '    var a: os_unfair_lock', '    private var b = pthread_mutex_t()',
                         '    static var c = os_unfair_lock_s()', '    var d = os_unfair_lock() { didSet { } }',
                         '    var e = os_unfair_lock.init()', '}', 'struct S { var f: Darwin.os_unfair_lock? }',
                         'extension E { static var g = os_unfair_lock() }',
                         'enum N { class K { let h = os.os_unfair_lock() } }'])
        self.assertEqual(lint(src), [(2, 9, 'lock-stored-property'), (3, 17, 'lock-stored-property'),
                                     (4, 16, 'lock-stored-property'), (5, 9, 'lock-stored-property'),
                                     (6, 9, 'lock-stored-property'), (8, 16, 'lock-stored-property'),
                                     (9, 26, 'lock-stored-property'), (10, 24, 'lock-stored-property')])

    def test_declaration_ends(self):
        src = '\n'.join(['class C {', '    var a: os_unfair_lock; var x = 1', '    var b: os_unfair_lock, c: Int',
                         '    var d: os_unfair_lock { willSet { } }', '    var e: os_unfair_lock { didSet { } }',
                         '    var g: os_unfair_lock!', '    let h = os.os_unfair_lock.init()',
                         '    var i: os_unfair_lock = os_unfair_lock()', '}'])
        self.assertEqual(lint(src), [(2, 9, 'lock-stored-property'), (3, 9, 'lock-stored-property'),
                                     (4, 9, 'lock-stored-property'), (5, 9, 'lock-stored-property'),
                                     (6, 9, 'lock-stored-property'), (7, 9, 'lock-stored-property'),
                                     (8, 9, 'lock-stored-property')])

    def test_class_func_is_not_a_type_body(self):
        self.assertEqual(lint('class C {\n    class func f() { var l = os_unfair_lock() }\n}'), [])


class OutletTests(unittest.TestCase):
    def test_not_reported(self):
        src = '\n'.join(['@IBOutlet var a: NSView?', '@IBOutlet weak var b: NSView?', 'var c: NSView!',
                         '@IBAction func d(_ s: Any!) { }'])
        # Not outlets: a file-scope variable and a parameter, so iuo-unmarked instead. Every var here is at file
        # scope, so each is also file-scope-var.
        self.assertEqual(lint(src), [(1, 11, 'file-scope-var'), (2, 16, 'file-scope-var'), (3, 1, 'file-scope-var'),
                                     (3, 14, 'iuo-unmarked'), (4, 26, 'iuo-unmarked')])

    def test_reported(self):
        src = '\n'.join(['@IBOutlet weak var a: NSView!', '@IBOutlet private(set) var b: NSView! = nil',
                         '@objc @IBOutlet var c: NSTextField!', '@IBOutlet var d: Foo<Bar>!',
                         '@IBOutlet var e: Dictionary<String, Int>!'])
        # Every var here is at file scope, so each is also file-scope-var.
        self.assertEqual(lint(src), [(1, 16, 'file-scope-var'), (1, 29, 'iuo-outlet'), (2, 24, 'file-scope-var'),
                                     (2, 37, 'iuo-outlet'), (3, 17, 'file-scope-var'), (3, 35, 'iuo-outlet'),
                                     (4, 11, 'file-scope-var'), (4, 25, 'iuo-outlet'), (5, 11, 'file-scope-var'),
                                     (5, 40, 'iuo-outlet')])


class MarkerTests(unittest.TestCase):
    def test_valid_markers(self):
        src = '\n'.join(['// SWIFT-MIGRATION-SHIM: raw access to _foo',
                         '// SWIFT-MIGRATION-UNSAFE(hot): 12% of frame time in the perf harness',
                         '// SWIFT-MIGRATION-FROZEN-REFERENCE: VT100Terminal VT100Terminal.m:-[VT100Terminal '
                         'reallyExecuteToken:]'])
        self.assertEqual(lint(src), [])

    def test_malformed_markers(self):
        src = '\n'.join(['// SWIFT-MIGRATION-SHIM:', '// SWIFT-MIGRATION-SHIM reason', '// SWIFT-MIGRATION-UNSAFE: x',
                         '// SWIFT-MIGRATION-UNSAFE(cold): x', '/* SWIFT-MIGRATION-SHIM: x */',
                         '/// SWIFT-MIGRATION-SHIM: x', '// SWIFT-MIGRATION-FROZEN-REFERENCE: unit file.m',
                         'x() // see SWIFT-MIGRATION-SHIM above', '//SWIFT-MIGRATION-SHIM: x'])
        self.assertEqual(lint(src), [(1, 4, 'marker-format'), (2, 4, 'marker-format'), (3, 4, 'marker-format'),
                                     (4, 4, 'marker-format'), (5, 4, 'marker-format'), (6, 5, 'marker-format'),
                                     (7, 4, 'marker-format'), (8, 12, 'marker-format'), (9, 3, 'marker-format')])


class UnsafeTests(unittest.TestCase):
    def test_every_api(self):
        names = ['UnsafePointer', 'UnsafeMutablePointer', 'UnsafeRawPointer', 'UnsafeMutableRawPointer',
                 'UnsafeBufferPointer', 'UnsafeMutableBufferPointer', 'UnsafeRawBufferPointer',
                 'UnsafeMutableRawBufferPointer', 'assumingMemoryBound', 'bindMemory', 'unsafeBitCast', 'Unmanaged',
                 'OpaquePointer', 'withUnsafeBytes', 'withUnsafeMutablePointer']
        src = '\n'.join('x.%s' % n if n[0].islower() else n for n in names)
        expected = [(i + 1, 3 if n[0].islower() else 1, 'unsafe-pointer-unmarked') for i, n in enumerate(names)]
        self.assertEqual(lint(src), expected)

    def test_not_unsafe_apis(self):
        self.assertEqual(lint('UnsafePointerHelper()\nmyUnmanaged\nwithSafeBytes'), [])

    def test_marker_on_the_line_above(self):
        src = '// SWIFT-MIGRATION-SHIM: out-parameter\nf(UnsafeMutablePointer(&x))\n' \
              'g() // SWIFT-MIGRATION-UNSAFE(hot): 9% in perf run 3\nlet u = Unmanaged.passUnretained(self)'
        self.assertEqual(lint(src), [])
        self.assertEqual(marked(src), [
            {'path': 't.swift', 'line': 2, 'column': 3, 'api': 'UnsafeMutablePointer',
             'marker': 'SWIFT-MIGRATION-SHIM', 'reason': 'out-parameter'},
            {'path': 't.swift', 'line': 4, 'column': 9, 'api': 'Unmanaged', 'marker': 'SWIFT-MIGRATION-UNSAFE(hot)',
             'reason': '9% in perf run 3'}])

    def test_marker_not_directly_above(self):
        src = '// SWIFT-MIGRATION-SHIM: out-parameter\n\nf(UnsafeMutablePointer(&x))'
        self.assertEqual(lint(src), [(3, 3, 'unsafe-pointer-unmarked')])

    def test_malformed_marker_above(self):
        self.assertEqual(lint('/* SWIFT-MIGRATION-SHIM: x */\nUnmanaged'),
                         [(1, 4, 'marker-format'), (2, 1, 'unsafe-pointer-unmarked')])
        self.assertEqual(lint('// SWIFT-MIGRATION-SHIM:\nUnmanaged'),
                         [(1, 4, 'marker-format'), (2, 1, 'unsafe-pointer-unmarked')])

    def test_frozen_marker_does_not_mark_unsafe_use(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-FROZEN-REFERENCE: u f.m:g\nUnmanaged'),
                         [(2, 1, 'unsafe-pointer-unmarked')])


class OverrideSignatureTests(unittest.TestCase):
    """A pointer type in the parameter list or result of an override needs no marker; its body is linted."""

    FORMATTER = ('class F: NumberFormatter {\n'
                 '    %sfunc isPartialStringValid(\n'
                 '        _ partialString: String,\n'
                 '        newEditingString s: AutoreleasingUnsafeMutablePointer<NSString?>?, '
                 'errorDescription e: AutoreleasingUnsafeMutablePointer<NSString?>?\n'
                 '    ) -> Bool {\n'
                 '        return true\n'
                 '    }\n'
                 '}\n')

    def test_override_func_parameters_need_no_marker(self):
        self.assertEqual(lint(self.FORMATTER % 'override '), [])

    def test_the_same_without_override_is_reported(self):
        self.assertEqual(lint(self.FORMATTER % ''), [(4, 29, 'unsafe-pointer-unmarked'),
                                                     (4, 96, 'unsafe-pointer-unmarked')])

    def test_pointer_in_the_body_of_an_override_is_reported(self):
        src = ('override func f(_ p: UnsafeMutablePointer<Int32>) -> UnsafeRawPointer? {\n'
               '    let q = UnsafeMutablePointer<Int32>.allocate(capacity: 1)\n'
               '    p.pointee = 1\n'
               '    return nil\n'
               '}\n')
        self.assertEqual(lint(src), [(2, 13, 'unsafe-pointer-unmarked'), (3, 7, 'unsafe-pointer-unmarked')])

    def test_marked_use_still_passes(self):
        src = ('override func f(\n'
               '    // SWIFT-MIGRATION-SHIM: kept\n'
               '    _ p: UnsafeMutablePointer<Int32>) {\n'
               '    // SWIFT-MIGRATION-UNSAFE(hot): 9% in perf run 3\n'
               '    let q = Unmanaged.passUnretained(self)\n'
               '}\n')
        self.assertEqual(lint(src), [])
        self.assertEqual([(m['line'], m['api']) for m in marked(src)],
                         [(3, 'UnsafeMutablePointer'), (5, 'Unmanaged')])

    def test_override_var_type_needs_no_marker(self):
        src = ('class C: Base {\n'
               '    override var p: UnsafeMutableRawPointer? {\n'
               '        return UnsafeMutableRawPointer(bitPattern: 1)\n'
               '    }\n'
               '    override public var q: OpaquePointer? { get { nil } set { } }\n'
               '    var r: OpaquePointer? { nil }\n'
               '}\n')
        self.assertEqual(lint(src), [(3, 16, 'unsafe-pointer-unmarked'), (6, 12, 'unsafe-pointer-unmarked')])

    def test_override_init_and_subscript_and_modifiers(self):
        src = ('class C: Base {\n'
               '    required override init?(p: UnsafePointer<Int8>) throws { super.init() }\n'
               '    @objc public override final class func f<T>(_ p: UnsafePointer<T>) -> UnsafeRawPointer '
               'where T: AnyObject { nil }\n'
               '    override subscript(i: Int) -> UnsafePointer<Int8> { fatalError() }\n'
               '    override private(set) var v: Unmanaged<AnyObject>? { didSet { } }\n'
               '}\n')
        self.assertEqual([x for x in lint(src) if x[2] == 'unsafe-pointer-unmarked'], [])

    def test_override_as_a_value_before_a_declaration_exempts_nothing(self):
        # Each "override" here is the value of an expression, and the var on the next line is a new declaration.
        src = ('func f() {\n'
               '    let x = override\n'
               '    var y: UnsafePointer<Int8>? = nil\n'
               '    let z = a + override\n'
               '    var w: UnsafePointer<Int8>? = nil\n'
               '    g(a, override\n'
               '      )\n'
               '    var v: UnsafePointer<Int8>? = nil\n'
               '}\n')
        self.assertEqual([x for x in lint(src) if x[2] == 'unsafe-pointer-unmarked'],
                         [(3, 12, 'unsafe-pointer-unmarked'), (5, 12, 'unsafe-pointer-unmarked'),
                          (8, 12, 'unsafe-pointer-unmarked')])

    def test_override_that_declares_nothing_exempts_nothing(self):
        src = ('let override = 1\n'
               'let p: UnsafePointer<Int8>? = nil\n'
               'x.override(UnsafePointer<Int8>(bitPattern: 1))\n'
               'let `override`: UnsafePointer<Int8>? = nil\n')
        self.assertEqual(lint(src), [(2, 8, 'unsafe-pointer-unmarked'), (3, 12, 'unsafe-pointer-unmarked'),
                                     (4, 17, 'unsafe-pointer-unmarked')])

    def test_default_argument_and_nested_function_are_not_exempt(self):
        # A default argument value is code that runs, not part of the overridden declaration's type, and a
        # function declared inside the body is not an override.
        src = ('override func f(_ p: UnsafeRawPointer? = UnsafeRawPointer(bitPattern: 1)) {\n'
               '    func g(_ q: UnsafePointer<Int8>) {}\n'
               '}\n')
        self.assertEqual(lint(src), [(1, 42, 'unsafe-pointer-unmarked'), (2, 17, 'unsafe-pointer-unmarked')])

    def test_override_without_a_body_ends_at_the_next_declaration(self):
        src = ('protocol P: Q {\n'
               '    override func f() -> Int\n'
               '    func g(_ p: UnsafePointer<Int8>)\n'
               '    override var v: UnsafePointer<Int8> { get }\n'
               '    var w: UnsafePointer<Int8> { get }\n'
               '}\n')
        self.assertEqual(lint(src), [(3, 17, 'unsafe-pointer-unmarked'), (5, 12, 'unsafe-pointer-unmarked')])


# ---------------------------------------------------------------------------
# Modes, migration-file selection, exit status, output

BAD = 'let v = x!\n'
GOOD = 'let v = 1\n'
PORT = 'Port Foo\n\nSwift-Port: Foo kind=port\n'
TOOL = 'Add a tool\n\nSwift-Port: lints kind=tool\n'


class GitRepo(object):
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix='swift_lints_test_')
        self.git('init', '-q', '-b', 'master')

    def git(self, *args, **kw):
        env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@example.com', GIT_COMMITTER_NAME='t',
                   GIT_COMMITTER_EMAIL='t@example.com', GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        p = subprocess.run(['git'] + list(args), cwd=self.root, env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, **kw)
        if p.returncode != 0:
            raise RuntimeError('git %s: %s' % (args, p.stderr.decode()))
        return p.stdout.decode()

    def write(self, path, content, mode='w'):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, mode) as f:
            f.write(content)

    def commit(self, message, *paths):
        self.git('add', '--', *paths) if paths else self.git('add', '-A')
        self.git('commit', '-q', '--allow-empty', '-m', message)
        return self.git('rev-parse', 'HEAD').strip()

    def run(self, *args):
        p = subprocess.run([sys.executable, '-B', SCRIPT, '--repo', self.root] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return p.returncode, p.stdout.decode(), p.stderr.decode()

    def json(self, *args):
        code, out, err = self.run('--json', *args)
        return code, json.loads(out) if out else None, err

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


def finding_lines(report):
    return ['%s:%d:%d: %s' % (f['path'], f['line'], f['column'], f['lint']) for f in report['findings']]


class ModeTests(unittest.TestCase):
    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def test_empty_tree_says_there_are_no_migration_files(self):
        self.r.write('sources/Old.swift', BAD)
        self.r.commit('Old code', 'sources/Old.swift')
        code, out, err = self.r.run()
        self.assertEqual(code, 0, err)
        self.assertIn('Swift files considered: 1\n', out)
        self.assertIn('Migration files linted: 0, identified by the trailer history (0 port commits found): 0 created '
                      'by a port commit, 0 renamed from a migration file, 0 carried over, 0 re-added\n', out)
        self.assertIn('There are no migration files.\n', out)
        self.assertIn('Skipped: 1 (not a migration file)\n', out)
        self.assertIn('Not checked by this tool:\n', out)
        self.assertIn(': 0 files with the marker in 0 projects read;', out)

    def test_repository_without_commits(self):
        code, out, err = self.r.run()
        self.assertEqual(code, 0, err)
        self.assertIn('There are no migration files.', out)

    def test_tree_mode_selects_files_created_by_port_commits(self):
        self.r.write('sources/Old.swift', BAD)
        self.r.commit('Old code', 'sources/Old.swift')
        self.r.write('sources/Foo.swift', BAD)
        self.r.write('sources/Foo.m', '')
        port = self.r.commit(PORT)
        self.r.write('sources/Tool.swift', BAD)
        self.r.commit(TOOL)
        self.r.write('sources/Old.swift', BAD + BAD)  # modified by a later port commit: still not migration
        self.r.commit('Port more\n\nSwift-Port: Bar kind=port\n')
        code, rep, err = self.r.json()
        self.assertEqual(code, 1, err)
        self.assertEqual(finding_lines(rep), ['sources/Foo.swift:1:10: force-unwrap'])
        self.assertEqual(rep['selection']['swift_files_considered'], 3)
        self.assertEqual(rep['selection']['files_linted'], 1)
        self.assertEqual(rep['selection']['port_commits'], 2)
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/Foo.swift': {'commit': port, 'unit': 'Foo'}})

    def test_renames_are_followed_and_deletions_dropped(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.write('sources/Gone.swift', BAD)
        self.r.commit(PORT)
        os.makedirs(os.path.join(self.r.root, 'sources/Moved'))
        self.r.git('mv', 'sources/Foo.swift', 'sources/Moved/Foo2.swift')
        self.r.git('rm', '-q', 'sources/Gone.swift')
        self.r.commit('Move')
        code, rep, err = self.r.json()
        self.assertEqual(code, 1, err)
        self.assertEqual(finding_lines(rep), ['sources/Moved/Foo2.swift:1:10: force-unwrap'])

    def test_trailer_must_be_read_by_git(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.commit('Port Foo\nSwift-Port: Foo kind=port\n')  # not in the final paragraph's trailer block
        code, out, err = self.r.run()
        self.assertEqual(code, 0, err)
        self.assertIn('There are no migration files.', out)
        self.assertIn('Swift-Port trailer problems (not counted unless stated): 1', out)

    def test_commit_mode(self):
        self.r.write('sources/Foo.swift', BAD)
        first = self.r.commit(PORT)
        self.r.write('sources/Other.swift', BAD)
        self.r.write('sources/Foo.swift', BAD + BAD)
        second = self.r.commit('Change\n')
        self.r.write('sources/Other.swift', GOOD)
        third = self.r.commit('Clean\n')
        code, rep, err = self.r.json(first)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Foo.swift:1:10: force-unwrap']), err)
        # The second commit modifies a migration file and adds Other.swift, so Other.swift is carried over.
        code, rep, err = self.r.json(second)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Foo.swift:1:10: force-unwrap',
                                                          'sources/Foo.swift:2:10: force-unwrap',
                                                          'sources/Other.swift:1:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['swift_files_considered'], 2)
        self.assertEqual(rep['selection']['skipped'], {'not a migration file': 0})
        code, rep, err = self.r.json(third)
        self.assertEqual((code, rep['selection']['files_linted']), (0, 1), err)

    def test_commit_mode_reads_the_commit_not_the_worktree(self):
        self.r.write('sources/Foo.swift', BAD)
        rev = self.r.commit(PORT)
        self.r.write('sources/Foo.swift', GOOD)
        code, rep, err = self.r.json(rev)
        self.assertEqual(code, 1, err)
        code, rep, err = self.r.json()
        self.assertEqual(code, 0, err)

    def test_staged_mode(self):
        self.r.write('sources/Old.swift', GOOD)
        self.r.commit('Old code')
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.r.write('sources/Foo.swift', BAD)
        self.r.write('sources/Old.swift', BAD)
        self.r.write('sources/New.swift', BAD)
        self.r.git('add', '-A')
        self.r.write('sources/Foo.swift', GOOD)  # the working tree differs from the index
        # The change modifies the migration file Foo.swift, so New.swift is carried over whatever the message,
        # and the changed lines of Old.swift are linted.
        both = ['sources/Foo.swift:1:10: force-unwrap', 'sources/New.swift:1:10: force-unwrap']
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, finding_lines(rep)), (1, both), err)
        self.assertEqual(rep['selection']['skipped'],
                         {'not a migration file': 0,
                          'added by the staged change, which --not-a-port says is not a port commit': 0})
        self.assertEqual(rep['ported_lines'], [ported_with_reason(
            'sources/Old.swift', [[1, 1]], 'this change also touches migration file(s) sources/Foo.swift',
            (1, 10, 'force-unwrap', '"!" force unwrap'))])
        msg = os.path.join(self.r.root, '.git', 'MSG')
        with open(msg, 'w') as f:
            f.write('Port New\n\nSwift-Port: New kind=port\n')
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, both), err)
        self.assertEqual(rep['selection']['identified_by_message'], 1)
        with open(msg, 'w') as f:
            f.write('Tool\n\nSwift-Port: New kind=tool\n')
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual(finding_lines(rep), both)
        self.assertEqual(list(rep['selection']['carried_over']), ['sources/New.swift'])

    def test_staged_rename_of_a_migration_file(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.commit(PORT)
        self.r.git('mv', 'sources/Foo.swift', 'sources/Bar.swift')
        code, rep, err = self.r.json('--staged')
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Bar.swift:1:10: force-unwrap']), err)

    def test_staged_in_a_repository_without_commits(self):
        self.r.write('sources/New.swift', BAD)
        self.r.git('add', '-A')
        msg = os.path.join(self.r.root, '.git', 'MSG')
        with open(msg, 'w') as f:
            f.write('Port\n\nSwift-Port: New kind=port\n')
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/New.swift:1:10: force-unwrap']), err)

    def test_all_swift_mode(self):
        self.r.write('sources/A.swift', BAD)
        self.r.write('ThirdParty/PSMTabBarControl/B.swift', 'let b = try! f()\n')
        self.r.write('ThirdParty/Other/C.swift', BAD)
        self.r.write('ModernTests/D.swift', BAD)
        self.r.commit('Code')
        code, rep, err = self.r.json('--all-swift')
        self.assertEqual(code, 1, err)
        self.assertEqual(finding_lines(rep), ['ThirdParty/PSMTabBarControl/B.swift:1:9: forced-try',
                                              'sources/A.swift:1:10: force-unwrap'])
        self.assertEqual(rep['selection']['skipped'], {'outside the scope roots': 2})
        self.assertEqual(rep['counts']['force-unwrap'], 1)
        self.assertEqual(rep['counts']['forced-try'], 1)

    def test_text_output_format_and_determinism(self):
        self.r.write('sources/Foo.swift', 'let v = x!\nlet w = y as! Z\n')
        self.r.commit(PORT)
        code, out1, _ = self.r.run()
        code2, out2, _ = self.r.run()
        self.assertEqual((code, code2), (1, 1))
        self.assertEqual(out1, out2)
        self.assertIn('\nsources/Foo.swift:1:10: force-unwrap: "!" force unwrap\n'
                      'sources/Foo.swift:2:11: forced-cast: "as!" forced cast\n', out1)
        self.assertIn('  force-unwrap: phase0.md section 6: no "!" force unwrap\n', out1)
        self.assertIn('  sources/Foo.swift (created by ', out1)

    def test_writes_nothing(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.commit(PORT)
        before = self.r.git('status', '--porcelain', '--ignored', '-uall')
        self.r.run()
        self.r.run('--all-swift')
        self.r.run('--staged')
        self.assertEqual(self.r.git('status', '--porcelain', '--ignored', '-uall'), before)


class ExitStatusTests(unittest.TestCase):
    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def test_zero_one(self):
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.assertEqual(self.r.run()[0], 0)
        self.r.write('sources/Foo.swift', BAD)
        self.assertEqual(self.r.run()[0], 1)

    def test_usage_errors(self):
        self.r.commit('empty')
        self.assertEqual(self.r.run('--staged', '--all-swift')[0], 2)
        self.assertEqual(self.r.run('HEAD', '--staged')[0], 2)
        self.assertEqual(self.r.run('--message', 'x')[0], 2)
        self.assertEqual(self.r.run('--bogus')[0], 2)
        code, out, err = self.r.run('nosuchrev')
        self.assertEqual(code, 2)
        self.assertIn('not a commit: nosuchrev', err)
        code, out, err = self.r.run('--staged', '--message', '/nonexistent/msg')
        self.assertEqual(code, 2)
        self.assertIn('cannot read the message file', err)

    def test_help_states_the_rule(self):
        code, out, err = self.r.run('--help')
        self.assertEqual(code, 0)
        self.assertIn('A Swift file is a migration file when a commit reachable from the inspected revision',
                      out.replace('\n', ' ').replace('  ', ' '))

    def test_not_a_repository(self):
        d = tempfile.mkdtemp(prefix='swift_lints_norepo_')
        self.addCleanup(shutil.rmtree, d, True)
        p = subprocess.run([sys.executable, '-B', SCRIPT, '--repo', d], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=dict(os.environ, GIT_CEILING_DIRECTORIES=os.path.dirname(d)))
        self.assertEqual(p.returncode, 2)
        self.assertIn('not in a git repository', p.stderr.decode())

    def test_non_utf8_file(self):
        self.r.write('sources/Foo.swift', b'let s = "\xff"\n', mode='wb')
        self.r.write('sources/Bar.swift', BAD)
        self.r.commit(PORT)
        code, rep, err = self.r.json()
        self.assertEqual(code, 2)
        self.assertEqual(rep['errors'][0]['path'], 'sources/Foo.swift')
        self.assertTrue(rep['errors'][0]['error'].startswith('not UTF-8'))
        self.assertEqual(finding_lines(rep), ['sources/Bar.swift:1:10: force-unwrap'])

    def test_unreadable_file(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.commit(PORT)
        os.remove(os.path.join(self.r.root, 'sources/Foo.swift'))
        code, out, err = self.r.run()
        self.assertEqual(code, 2)
        self.assertIn('Errors (exit status 2): 1\n  sources/Foo.swift: cannot read:', out)

    def test_file_the_lexer_cannot_handle(self):
        self.r.write('sources/Foo.swift', 'let v = 1\nlet s = "abc\n')
        self.r.commit(PORT)
        code, out, err = self.r.run()
        self.assertEqual(code, 2)
        self.assertIn('  sources/Foo.swift:2:9: lexer cannot handle the file: unterminated string literal\n', out)
        self.r.write('sources/Foo.swift', 'func f() {\n')
        code, out, err = self.r.run()
        self.assertEqual(code, 2)
        self.assertIn('  sources/Foo.swift:1:10: lexer cannot handle the file: brackets do not balance', out)


class FrozenReferenceTests(unittest.TestCase):
    MARK = '// SWIFT-MIGRATION-FROZEN-REFERENCE: Unit Foo.m:-[Foo bar]\n'

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        with open(os.path.join(FIXTURES, 'project.pbxproj')) as f:
            self.r.write('Proj.xcodeproj/project.pbxproj', f.read())

    def test_membership(self):
        r = self.r
        r.write('sources/App.swift', 'x\n' + self.MARK)
        r.write('sources/Shared.swift', self.MARK)
        r.write('Tests/Frozen.swift', self.MARK)
        r.write('Tests/NotATest.swift', self.MARK)
        r.write('Helpers/AlsoInApp.swift', self.MARK)
        r.write('Helpers/TestOnly.m', '  ' + self.MARK)
        r.write('sources/Frozen.m', 'let s = "SWIFT-MIGRATION-FROZEN-REFERENCE"\n')
        r.write('sources/Nested/N.swift', self.MARK)
        r.write('other/Deep/D.swift', self.MARK)
        r.write('docs/swift-migration/notes.md', self.MARK)
        r.write('tools/swift_migration/tool.py', self.MARK)
        rev = r.commit('Frozen copies\n\nSwift-Port: Unit kind=test\n')
        code, rep, err = r.json()
        self.assertEqual(code, 1, err)
        self.assertEqual(finding_lines(rep), ['Helpers/AlsoInApp.swift:1:4: frozen-reference-target',
                                              'sources/App.swift:2:4: frozen-reference-target',
                                              'sources/Shared.swift:1:4: frozen-reference-target'])
        self.assertEqual(rep['findings'][0]['message'],
                         'file with the frozen-reference marker is a member of non-test target(s): App')
        self.assertEqual(rep['frozen_reference'], {'files_with_marker': 9,
                                                   'in_no_target': ['Tests/NotATest.swift', 'sources/Frozen.m'],
                                                   'test_targets_only': ['Helpers/TestOnly.m', 'Tests/Frozen.swift',
                                                                         'other/Deep/D.swift',
                                                                         'sources/Nested/N.swift'],
                                                   'projects': 1})
        for args in ([rev], ['--staged'], ['--all-swift']):
            code, rep2, err = r.json(*args)
            self.assertEqual(finding_lines(rep2), finding_lines(rep), args)

    def test_staged_contents_are_checked(self):
        self.r.commit('Project')
        self.r.write('sources/App.swift', self.MARK)
        self.r.git('add', '-A')
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/App.swift:1:4: frozen-reference-target']), err)
        os.remove(os.path.join(self.r.root, 'sources/App.swift'))
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual(code, 1, err)

    def test_unreadable_project_is_an_error(self):
        self.r.write('Proj.xcodeproj/project.pbxproj', '{ not a project')
        self.r.write('sources/App.swift', self.MARK)
        self.r.commit('Broken')
        code, out, err = self.r.run()
        self.assertEqual(code, 2)
        self.assertIn('cannot read project Proj.xcodeproj/project.pbxproj', err)


# ---------------------------------------------------------------------------
# Findings of the fourth review

# An Objective-C file and the Swift port that keeps its comments word for word, so that git's rename
# detection pairs them. The force unwrap is on line 31, column 10.
KEPT_COMMENTS = ''.join('// Comment line %d that the port keeps word for word.\n' % i for i in range(30))
OBJC = KEPT_COMMENTS + '@implementation iTermFoo\n@end\n'
SWIFT_PORT = KEPT_COMMENTS + 'let v = x!\n'


def write_message(repo, text):
    path = os.path.join(repo.root, '.git', 'MSG')
    with open(path, 'w') as f:
        f.write(text)
    return path


class RenameTests(unittest.TestCase):
    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def stage_objc_to_swift_port(self):
        self.r.write('sources/iTermFoo.m', OBJC)
        self.r.commit('Root')
        self.r.git('rm', '-q', 'sources/iTermFoo.m')
        self.r.write('sources/iTermFoo.swift', SWIFT_PORT)
        self.r.git('add', '-A')
        # The shape under test: git pairs the deletion and the addition as a rename.
        self.assertEqual(self.r.git('diff', '--cached', '-M', '--name-status').split('\t')[0][0], 'R')

    def test_port_that_git_sees_as_a_rename_from_objc_tree_mode(self):
        self.stage_objc_to_swift_port()
        port = self.r.commit(PORT)
        code, rep, err = self.r.json()
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/iTermFoo.swift:31:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/iTermFoo.swift': {'commit': port, 'unit': 'Foo'}})
        self.assertEqual(rep['selection']['skipped'], {'not a migration file': 0})

    def test_port_that_git_sees_as_a_rename_from_objc_commit_mode(self):
        self.stage_objc_to_swift_port()
        port = self.r.commit(PORT)
        code, rep, err = self.r.json(port)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/iTermFoo.swift:31:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['files_linted'], 1)
        self.assertEqual(rep['selection']['skipped'], {'not a migration file': 0})

    def test_port_that_git_sees_as_a_rename_from_objc_staged_mode(self):
        self.stage_objc_to_swift_port()
        msg = write_message(self.r, PORT)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/iTermFoo.swift:31:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['skipped'],
                         {'not a migration file': 0,
                          'added by the staged change without a kind=port trailer in --message': 0})
        self.assertEqual(rep['selection']['identified_by_message'], 1)

    def test_swift_rename_of_a_migration_file_in_a_later_commit(self):
        self.r.write('sources/Foo.swift', SWIFT_PORT)
        port = self.r.commit(PORT)
        self.r.git('mv', 'sources/Foo.swift', 'sources/Bar.swift')
        self.r.write('sources/Bar.swift', SWIFT_PORT + '// one more line\n')
        later = self.r.commit('Rename\n')
        for args in ([], [later]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, ['sources/Bar.swift:31:10: force-unwrap']), (args, err))
        self.assertEqual(rep['selection']['skipped'], {'not a migration file': 0})
        code, rep, err = self.r.json()
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/Bar.swift': {'commit': port, 'unit': 'Foo', 'created_as': 'sources/Foo.swift',
                                                'renames': [{'from': 'sources/Foo.swift', 'to': 'sources/Bar.swift',
                                                             'commit': later}]}})

    def test_swift_rename_of_a_non_migration_file_by_a_port_commit_creates_a_migration_file(self):
        # The port commit creates the path sources/New.swift, so it is a migration file, although git pairs
        # it with sources/Old.swift, which is not one.
        self.r.write('sources/Old.swift', SWIFT_PORT)
        self.r.commit('Old code\n')
        self.r.git('mv', 'sources/Old.swift', 'sources/New.swift')
        self.r.write('sources/New.swift', SWIFT_PORT + '// one more line\n')
        self.r.git('add', '-A')
        msg = write_message(self.r, PORT)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/New.swift:31:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['skipped'],
                         {'not a migration file': 0,
                          'added by the staged change without a kind=port trailer in --message': 0})
        self.assertEqual(rep['selection']['identified_by_message'], 1)
        port = self.r.commit(PORT)
        for args in ([], [port]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, ['sources/New.swift:31:10: force-unwrap']), (args, err))
            self.assertEqual(rep['selection']['skipped'], {'not a migration file': 0}, args)
        code, rep, err = self.r.json()
        self.assertEqual(rep['selection']['migration_files'], {'sources/New.swift': {'commit': port, 'unit': 'Foo'}})

    def test_swift_rename_of_a_non_migration_file_by_an_ordinary_commit(self):
        self.r.write('sources/Old.swift', SWIFT_PORT)
        self.r.commit('Old code\n')
        self.r.git('mv', 'sources/Old.swift', 'sources/New.swift')
        # Nothing decides whether the commit is a port commit, so --staged alone cannot tell.
        code, out, err = self.r.run('--staged')
        self.assertEqual((code, out), (2, ''))
        self.assertIn('the staged change adds Swift files (sources/New.swift)', err)
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, rep['selection']['files_linted']), (0, 0), err)
        later = self.r.commit('Rename\n')
        for args in ([], [later]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, rep['selection']['files_linted']), (0, 0), (args, err))
            self.assertEqual(rep['selection']['skipped'], {'not a migration file': 1}, args)

    def test_copy_made_by_a_port_commit_is_created_by_it(self):
        self.r.write('sources/Old.swift', SWIFT_PORT)
        self.r.commit('Old code\n')
        self.r.write('sources/Copy.swift', SWIFT_PORT + '// one more line\n')
        self.r.git('add', '-A')
        self.assertEqual(self.r.git('diff', '--cached', '-C', '--find-copies-harder',
                                    '--name-status').split('\t')[0][0], 'C')
        msg = write_message(self.r, PORT)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Copy.swift:31:10: force-unwrap']), err)
        port = self.r.commit(PORT)
        for args in ([], [port]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, ['sources/Copy.swift:31:10: force-unwrap']), (args, err))

    def test_walk_problem_names_the_walk(self):
        self.r.write('sources/A.swift', GOOD)
        root = self.r.commit('Root\n')
        self.r.git('checkout', '-q', '-b', 'side')
        self.r.write('sources/B.swift', GOOD)
        side = self.r.commit('Side\n')
        self.r.git('checkout', '-q', 'master')
        original = sl.port_commits
        self.addCleanup(setattr, sl, 'port_commits', original)
        sl.port_commits = lambda repo, rev: ({side: ['B'], root: ['A']}, [])
        with self.assertRaises(sl.EnvironmentProblem) as cm:
            sl.migration_files(sl.Repo(self.r.root), 'master')
        self.assertEqual(str(cm.exception),
                         'port commits not in the history walked from master (the commits reachable from it '
                         'and not from the parents of the oldest port commit, %s): %s' % (root, side))


class StagedTrailerTests(unittest.TestCase):
    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        # The staged change touches no migration file, so nothing but the message decides New.swift.
        self.r.write('sources/Old.swift', GOOD)
        self.r.commit('Old\n')
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.r.write('sources/Old.swift', BAD)
        self.r.write('sources/New.swift', BAD)
        self.r.git('add', '-A')

    def test_staged_adds_swift_without_message(self):
        code, out, err = self.r.run('--staged')
        self.assertEqual((code, out), (2, ''))
        self.assertEqual(err, 'swift_lints.py: the staged change adds Swift files (sources/New.swift) and modifies 1 '
                              'Swift file that is not a migration file (sources/Old.swift), and this tool cannot '
                              'tell whether the files it adds are migration files or whether the lines it changes '
                              'are ported lines without --message FILE holding the pending commit message; pass '
                              '--not-a-port if the commit is not a port commit\n')

    def test_staged_adds_swift_with_a_malformed_trailer(self):
        msg = write_message(self.r, 'Port New\n\nSwift-Port: New kind = port\n')
        code, out, err = self.r.run('--staged', '--message', msg)
        self.assertEqual((code, out), (2, ''))
        self.assertEqual(err, 'swift_lints.py: the staged change adds Swift files (sources/New.swift) and modifies 1 '
                              'Swift file that is not a migration file (sources/Old.swift), and the pending commit '
                              'message has no usable Swift-Port trailer (malformed trailer (not counted): Swift-Port: '
                              'New kind = port), so this tool cannot tell whether the files it adds are migration '
                              'files or whether the lines it changes are ported lines; the modified Swift files were '
                              'not checked; fix the trailer, or pass --not-a-port if the commit is not a port '
                              'commit\n')

    def test_staged_adds_swift_not_a_port(self):
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, finding_lines(rep)), (0, []), err)
        self.assertEqual(rep['selection']['skipped'],
                         {'not a migration file': 1,
                          'added by the staged change, which --not-a-port says is not a port commit': 1})
        self.r.write('sources/Foo.swift', BAD)
        self.r.git('add', '-A')
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Foo.swift:1:10: force-unwrap',
                                                          'sources/New.swift:1:10: force-unwrap']), err)

    def test_not_a_port_usage(self):
        msg = write_message(self.r, PORT)
        self.assertEqual(self.r.run('--staged', '--not-a-port', '--message', msg)[0], 2)
        self.assertEqual(self.r.run('--not-a-port')[0], 2)

    def test_summary_names_the_pending_message(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.git('add', '-A')
        msg = write_message(self.r, 'Port New\n\nSwift-Port: New kind=port\n')
        code, out, err = self.r.run('--staged', '--message', msg)
        self.assertEqual(code, 1, err)
        self.assertIn('\nMigration files linted: 2: 1 identified by the trailer history at HEAD (1 port commit '
                      'found), 1 that the staged change adds, identified by the kind=port trailer in the pending '
                      'commit message\n', out)


class FourthReviewLexTests(unittest.TestCase):
    ADDED_UNSAFE = [
        ('AutoreleasingUnsafeMutablePointer', 'func f(_ e: AutoreleasingUnsafeMutablePointer<NSError?>) { }', 13),
        ('CVaListPointer', 'func f(_ a: CVaListPointer) { }', 13),
        ('withVaList', 'withVaList(args) { f($0) }', 1),
        ('getVaList', 'let l = getVaList(args)', 9),
        ('unsafeDowncast', 'let v = unsafeDowncast(o, to: Foo.self)', 9),
        ('withMemoryRebound', 'p.withMemoryRebound(to: UInt8.self, capacity: 1) { _ in }', 3),
        ('unsafeUninitializedCapacity', 'let a = [UInt8](unsafeUninitializedCapacity: 4) { b, n in n = 0 }', 17),
        ('pointee', 'stop.pointee = true', 6),
        ('baseAddress', 'let b = buf.baseAddress', 13),
    ]

    def test_added_unsafe_names(self):
        for name, snippet, col in self.ADDED_UNSAFE:
            self.assertEqual(lint(snippet), [(1, col, 'unsafe-pointer-unmarked')], name)
            for template in ('// {s}', 'let q = "{s}"'):
                src = template.format(s=snippet) + '\n' + snippet
                self.assertEqual(lint(src), [(2, col, 'unsafe-pointer-unmarked')], (name, template))

    def test_pointee_and_base_address_only_as_members(self):
        self.assertEqual(lint('let pointee = 1\nlet baseAddress = 2\nf(pointee, baseAddress)'), [])
        self.assertEqual(lint('withExtendedLifetime(x) { }'), [])

    def test_concurrency_words_used_as_identifiers(self):
        src = '\n'.join([
            'private struct Task {',
            '    let description: String',
            '}',
            'var tasks = [Task?]()',
            'func add(async: Bool) {',
            '    DLog("async=\\(async)")',
            '    if async { }',
            '    let x = async ? 1 : 2',
            '}',
            'let async = true',
            'f(await: x)',
            'func g(await: Int) { }',
            'let await = 1',
            'x.await',
            'enum E { case async, await }',
            'for actor in actors { }',
            'typealias Task = Foo',
            'g()',
            'async(execute: w)',
            'h()',
            'async = false',
        ])
        self.assertEqual(lint(src), [(4, 1, 'file-scope-var')])

    def test_concurrency_keywords_still_reported(self):
        src = '\n'.join([
            'let t: Task<Void, Never>? = nil',  # 1:8
            'var u: Task?',                    # 2:8
            'Task(priority: .low) { }',        # 3:1
            'func g() async throws { }',       # 4:10
            'let h: (Int) async -> Void',      # 5:14
            'let c = { () async in }',         # 6:14
            'var v: Int { get async { 1 } }',  # 7:18
            'let w = await f()',               # 8:9
            'for await e in s { }',            # 9:5
        ])
        self.assertEqual(lint(src), [(1, 8, 'stage-one-concurrency'), (2, 1, 'file-scope-var'),
                                     (2, 8, 'stage-one-concurrency'),
                                     (3, 1, 'stage-one-concurrency'), (4, 10, 'stage-one-concurrency'),
                                     (5, 14, 'stage-one-concurrency'), (6, 14, 'stage-one-concurrency'),
                                     (7, 1, 'file-scope-var'), (7, 18, 'stage-one-concurrency'),
                                     (8, 9, 'stage-one-concurrency'),
                                     (9, 5, 'stage-one-concurrency')])

    def test_second_variable_in_one_declaration(self):
        # Each declaration is at file scope, so each is also one file-scope-var, at its var.
        self.assertEqual(lint('var x: Int!, y: Int!'),
                         [(1, 1, 'file-scope-var'), (1, 11, 'iuo-unmarked'), (1, 20, 'iuo-unmarked')])
        self.assertEqual(lint('var a = 1, b: Int!'), [(1, 1, 'file-scope-var'), (1, 18, 'iuo-unmarked')])
        self.assertEqual(lint('var x: Int!, y = z!'),
                         [(1, 1, 'file-scope-var'), (1, 11, 'iuo-unmarked'), (1, 19, 'force-unwrap')])
        self.assertEqual(lint('@IBOutlet var a: NSView!, b: NSView!'),
                         [(1, 11, 'file-scope-var'), (1, 24, 'iuo-outlet'), (1, 36, 'iuo-outlet')])
        self.assertEqual(lint('var a = 1,\n    b: Int!'), [(1, 1, 'file-scope-var'), (2, 11, 'iuo-unmarked')])
        self.assertEqual(lint('var a = 1\nf(b, c: d!)'), [(1, 1, 'file-scope-var'), (2, 10, 'force-unwrap')])

    def test_byte_order_mark(self):
        self.assertEqual(lint('﻿var x: Int!'), [(1, 2, 'file-scope-var'), (1, 12, 'iuo-unmarked')])
        self.assertEqual(lint('﻿x!'), [(1, 3, 'force-unwrap')])

    def test_assertion_failure_and_precondition_failure_are_checked_now(self):
        # They were listed as not checked until the owner banned them (decisions.md, 2026-11-20).
        self.assertEqual([r for r, _, _ in sl.NOT_CHECKED if 'assertionFailure' in r or 'preconditionFailure' in r],
                         [])
        self.assertIn('assertionFailure', sl.LINTS['trap-call'])
        self.assertIn('preconditionFailure', sl.LINTS['trap-call'])


# ---------------------------------------------------------------------------
# Findings of the fifth review

# A large extension that git pairs with SWIFT_PORT as a rename.
FOO_EXT = KEPT_COMMENTS + 'extension Foo { }\n'
# A rewrite too different from SWIFT_PORT for git to pair them. The force unwrap is on line 2, column 14.
REWRITE = 'func bar() {\n    let z = q!\n}\n'
PLAIN = 'Rename and rewrite\n\nNo trailer here.\n'


def carry_reason(*deleted):
    return ('treated as a migration file because this change deletes migration file(s) %s and adds this file'
            % ', '.join(deleted))


class FoldIntoPortTests(unittest.TestCase):
    """A port commit that folds an existing Swift file (not a migration file) into its new file."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/Foo.m', 'void Foo(void) { }\n')
        self.r.write('sources/FooExt.swift', FOO_EXT)
        self.r.commit('Before the port\n')
        self.r.git('rm', '-q', 'sources/Foo.m', 'sources/FooExt.swift')
        self.r.write('sources/Foo.swift', SWIFT_PORT)
        self.r.git('add', '-A')
        # The shape under test: git pairs the old extension and the new file as a rename.
        self.assertRegex(self.r.git('diff', '--cached', '-M', '--name-status'),
                         r'(?m)^R\d+\tsources/FooExt\.swift\tsources/Foo\.swift$')

    def test_staged(self):
        msg = write_message(self.r, PORT)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Foo.swift:31:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['identified_by_message'], 1)

    def test_tree_and_commit(self):
        port = self.r.commit(PORT)
        for args in ([], [port]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, ['sources/Foo.swift:31:10: force-unwrap']), (args, err))
            self.assertEqual(rep['selection']['skipped'], {'not a migration file': 0}, args)
        code, rep, err = self.r.json()
        self.assertEqual(rep['selection']['migration_files'], {'sources/Foo.swift': {'commit': port, 'unit': 'Foo'}})


class CarryOverTests(unittest.TestCase):
    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/Foo.swift', SWIFT_PORT)
        self.port = self.r.commit(PORT)

    def stage_unpaired_rename(self):
        self.r.git('mv', 'sources/Foo.swift', 'sources/Bar.swift')
        self.r.write('sources/Bar.swift', REWRITE)
        self.r.git('add', '-A')
        self.assertEqual(self.r.git('diff', '--cached', '-M', '--name-status'),
                         'A\tsources/Bar.swift\nD\tsources/Foo.swift\n')

    def test_unpaired_rename_staged(self):
        self.stage_unpaired_rename()
        msg = write_message(self.r, PLAIN)
        for args in (['--staged'], ['--staged', '--not-a-port'], ['--staged', '--message', msg]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, ['sources/Bar.swift:2:14: force-unwrap']), (args, err))
            self.assertEqual(rep['selection']['deleted_migration_files'], ['sources/Foo.swift'], args)
            self.assertEqual(rep['selection']['carried_over'], {'sources/Bar.swift': carry_reason('sources/Foo.swift')},
                             args)
            self.assertEqual(rep['selection']['files_linted'], 1, args)
        code, out, err = self.r.run('--staged')
        self.assertEqual(code, 1, err)
        self.assertIn('\nMigration files deleted by this change: 1\n  sources/Foo.swift\n', out)
        self.assertIn('\nCarried over: 1\n  sources/Bar.swift: ' + carry_reason('sources/Foo.swift') + '\n', out)

    def test_unpaired_rename_tree_and_commit(self):
        self.stage_unpaired_rename()
        later = self.r.commit(PLAIN)
        code, rep, err = self.r.json()
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Bar.swift:2:14: force-unwrap']), err)
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/Bar.swift': {'commit': later, 'unit': 'Foo',
                                                'carried_over_from': ['sources/Foo.swift']}})
        code, out, err = self.r.run()
        self.assertIn('\n  sources/Bar.swift (treated as a migration file because commit %s deletes migration '
                      'file(s) sources/Foo.swift and adds this file; unit Foo)\n' % later[:12], out)
        code, rep, err = self.r.json(later)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Bar.swift:2:14: force-unwrap']), err)
        self.assertEqual(rep['selection']['deleted_migration_files'], ['sources/Foo.swift'])
        self.assertEqual(rep['selection']['carried_over'], {'sources/Bar.swift': carry_reason('sources/Foo.swift')})
        code, out, err = self.r.run(later)
        self.assertIn('\nMigration files deleted by this change: 1\n  sources/Foo.swift\n', out)

    def test_deletion_without_addition(self):
        self.r.git('rm', '-q', 'sources/Foo.swift')
        code, rep, err = self.r.json('--staged')
        self.assertEqual((code, rep['selection']['files_linted']), (0, 0), err)
        self.assertEqual(rep['selection']['deleted_migration_files'], ['sources/Foo.swift'])
        self.assertEqual(rep['selection']['carried_over'], {})
        code, out, err = self.r.run('--staged')
        self.assertIn('\nMigration files deleted by this change: 1\n  sources/Foo.swift\n', out)
        later = self.r.commit('Delete\n')
        code, rep, err = self.r.json(later)
        self.assertEqual((code, rep['selection']['deleted_migration_files']), (0, ['sources/Foo.swift']), err)
        code, rep, err = self.r.json()
        self.assertEqual((code, rep['selection']['migration_files']), (0, {}), err)

    def test_deletion_with_two_additions(self):
        self.r.git('rm', '-q', 'sources/Foo.swift')
        self.r.write('sources/A.swift', BAD)
        self.r.write('sources/B.swift', BAD)
        self.r.git('add', '-A')
        expected = ['sources/A.swift:1:10: force-unwrap', 'sources/B.swift:1:10: force-unwrap']
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, finding_lines(rep)), (1, expected), err)
        self.assertEqual(rep['selection']['carried_over'], {'sources/A.swift': carry_reason('sources/Foo.swift'),
                                                            'sources/B.swift': carry_reason('sources/Foo.swift')})
        later = self.r.commit('Split\n')
        for args in ([], [later]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, expected), (args, err))

    def test_deleting_a_non_migration_file_carries_nothing(self):
        self.r.write('sources/Old.swift', SWIFT_PORT + '// old\n')
        self.r.commit('Old code\n')
        self.r.git('rm', '-q', 'sources/Old.swift')
        self.r.write('sources/New.swift', REWRITE)
        self.r.git('add', '-A')
        code, out, err = self.r.run('--staged')
        self.assertEqual((code, out), (2, ''))
        self.assertIn('the staged change adds Swift files (sources/New.swift)', err)
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, rep['selection']['files_linted']), (0, 0), err)
        self.assertEqual((rep['selection']['deleted_migration_files'], rep['selection']['carried_over']), ([], {}))
        later = self.r.commit('Replace\n')
        code, rep, err = self.r.json(later)
        self.assertEqual((code, rep['selection']['files_linted']), (0, 0), err)
        self.assertEqual((rep['selection']['deleted_migration_files'], rep['selection']['carried_over']), ([], {}))
        code, rep, err = self.r.json()
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Foo.swift:31:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/Foo.swift': {'commit': self.port, 'unit': 'Foo'}})

    def test_port_message_takes_precedence_over_carry_over(self):
        self.stage_unpaired_rename()
        msg = write_message(self.r, PORT)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Bar.swift:2:14: force-unwrap']), err)
        self.assertEqual((rep['selection']['identified_by_message'], rep['selection']['carried_over']), (1, {}))

    def test_carried_over_file_is_followed_through_a_later_rename(self):
        self.stage_unpaired_rename()
        carry = self.r.commit(PLAIN)
        self.r.write('sources/Bar.swift', SWIFT_PORT)
        self.r.commit('Restore\n')
        self.r.git('mv', 'sources/Bar.swift', 'sources/Baz.swift')
        code, rep, err = self.r.json('--staged')
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/Baz.swift:31:10: force-unwrap']), err)
        rename = self.r.commit('Move\n')
        for args in ([], [rename]):
            code, rep, err = self.r.json(*args)
            self.assertEqual((code, finding_lines(rep)), (1, ['sources/Baz.swift:31:10: force-unwrap']), (args, err))
        code, rep, err = self.r.json()
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/Baz.swift': {'commit': carry, 'unit': 'Foo',
                                                'carried_over_from': ['sources/Foo.swift'],
                                                'created_as': 'sources/Bar.swift',
                                                'renames': [{'from': 'sources/Bar.swift', 'to': 'sources/Baz.swift',
                                                             'commit': rename}]}})

    def test_help_states_the_carry_over_rule(self):
        code, out, err = self.r.run('--help')
        self.assertEqual(code, 0)
        flat = ' '.join(out.split())
        self.assertIn('Carry-over: when a commit that is not a port commit, whatever its kind (or the staged '
                      'change), modifies, renames or deletes at least one migration file', flat)
        self.assertIn('only when its source is a migration file', flat)
        self.assertIn('or their paths were migration files', flat)


class FifthReviewLintTests(unittest.TestCase):
    def test_await_before_a_parenthesized_expression(self):
        self.assertEqual(lint('let w = await (f())'), [(1, 9, 'stage-one-concurrency')])

    def test_await_before_an_implicit_member(self):
        self.assertEqual(lint('let v: Int? = await .some(x)'), [(1, 15, 'stage-one-concurrency')])
        self.assertEqual(lint('_ = await.foo'), [(1, 5, 'stage-one-concurrency')])
        self.assertEqual(lint('x.await\nf(await: 1)\nlet y = x.await.count\nfunc g(await: Int) { }'), [])

    def test_closure_parameter_named_async(self):
        self.assertEqual(lint('let c = { async in async + 1 }\nlet d = { [weak self] async in async }'), [])
        self.assertEqual(lint('let e = { (x) async in x }\nlet f = { x async in x }'),
                         [(1, 15, 'stage-one-concurrency'), (2, 13, 'stage-one-concurrency')])

    def test_actor_as_a_value(self):
        self.assertEqual(lint('let e = actor as Any\nlet f = actor is Foo'), [])
        self.assertEqual(lint('actor Foo { }'), [(1, 1, 'stage-one-concurrency')])


# ---------------------------------------------------------------------------
# Findings of the sixth review

IMPROVE = 'Split A\n\nSwift-Port: Foo kind=improve\n'
A_PORTED = 'func a() {\n    let v = 1\n}\n'
A_REFACTORED = 'func a() {\n    let v = 2\n}\n'


def touch_reason(modified=(), renamed=(), deleted=()):
    parts = []
    if modified:
        parts.append('modifies migration file(s) %s' % ', '.join(modified))
    if renamed:
        parts.append('renames migration file(s) %s' % ', '.join('%s to %s' % r for r in renamed))
    if deleted:
        parts.append('deletes migration file(s) %s' % ', '.join(deleted))
    return 'treated as a migration file because this change %s and adds this file' % ', '.join(parts)


class TouchCarryOverTests(unittest.TestCase):
    """Item 1: a Swift file added by a change that touches a migration file is a migration file."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/A.swift', A_PORTED)
        self.port = self.r.commit(PORT)

    def check_all_modes(self, message, expected, carried, origins, staged_args_list):
        for args in staged_args_list:
            code, rep, err = self.r.json('--staged', *args)
            self.assertEqual((code, finding_lines(rep)), (1, expected), (args, err))
            self.assertEqual(rep['selection']['carried_over'], carried, args)
        later = self.r.commit(message)
        code, rep, err = self.r.json(later)
        self.assertEqual((code, finding_lines(rep)), (1, expected), err)
        self.assertEqual(rep['selection']['carried_over'], carried)
        code, rep, err = self.r.json()
        self.assertEqual((code, finding_lines(rep)), (1, expected), err)
        for path in carried:
            self.assertEqual(rep['selection']['migration_files'][path],
                             {'commit': later, 'unit': 'Foo', 'carried_over_from': origins})
        return later

    def test_extract_into_a_new_file_by_an_improve_commit(self):
        self.r.write('sources/A.swift', A_REFACTORED)
        self.r.write('sources/AExtracted.swift', BAD)
        self.r.git('add', '-A')
        msg = write_message(self.r, IMPROVE)
        reason = touch_reason(modified=['sources/A.swift'])
        later = self.check_all_modes(IMPROVE, ['sources/AExtracted.swift:1:10: force-unwrap'],
                                     {'sources/AExtracted.swift': reason}, ['sources/A.swift'],
                                     [['--message', msg], [], ['--not-a-port']])
        code, out, err = self.r.run()
        self.assertIn('\n  sources/AExtracted.swift (treated as a migration file because commit %s modifies migration '
                      'file(s) sources/A.swift and adds this file; unit Foo)\n' % later[:12], out)
        code, out, err = self.r.run(later)
        self.assertIn('\nCarried over: 1\n  sources/AExtracted.swift: ' + reason + '\n', out)

    def test_split_that_keeps_the_old_name(self):
        self.r.write('sources/A.swift', A_REFACTORED)
        self.r.write('sources/A2.swift', BAD)
        self.r.git('add', '-A')
        self.check_all_modes(PLAIN, ['sources/A2.swift:1:10: force-unwrap'],
                             {'sources/A2.swift': touch_reason(modified=['sources/A.swift'])}, ['sources/A.swift'],
                             [[], ['--message', write_message(self.r, PLAIN)]])

    def test_split_where_git_pairs_the_old_file_with_one_new_file(self):
        self.r.write('sources/A.swift', SWIFT_PORT)
        self.port = self.r.commit('Grow A\n')
        self.r.git('rm', '-q', 'sources/A.swift')
        self.r.write('sources/A1.swift', SWIFT_PORT + '// one more line\n')
        self.r.write('sources/A2.swift', BAD)
        self.r.git('add', '-A')
        self.assertEqual(self.r.git('diff', '--cached', '-M', '--name-status').split('\n')[:2][0].split('\t'),
                         ['R098', 'sources/A.swift', 'sources/A1.swift'])
        self.check_all_modes(PLAIN, ['sources/A1.swift:31:10: force-unwrap', 'sources/A2.swift:1:10: force-unwrap'],
                             {'sources/A2.swift': touch_reason(renamed=[('sources/A.swift', 'sources/A1.swift')])},
                             ['sources/A.swift'], [[], ['--not-a-port']])

    def test_change_touching_no_migration_file_still_needs_an_option(self):
        self.r.write('sources/Old.swift', GOOD)
        self.r.commit('Old\n')
        self.r.write('sources/Old.swift', BAD)
        self.r.write('sources/New.swift', BAD)
        self.r.git('add', '-A')
        code, out, err = self.r.run('--staged')
        self.assertEqual((code, out), (2, ''))
        self.assertIn('the staged change adds Swift files (sources/New.swift)', err)

    def test_rule_states_the_over_linting(self):
        flat = ' '.join(sl.MIGRATION_RULE.split())
        self.assertIn('modifies, renames or deletes at least one migration file', flat)
        self.assertIn('whatever its kind', flat)
        self.assertIn('an unrelated new Swift file added in the same commit', flat)


P_EXT_BEFORE = 'extension P {\n    func old() { _ = z! }\n}\n'
P_EXT_PORTED = 'extension P {\n    func old() { _ = z! }\n    func new() { _ = y! }\n}\n'
P_EXT_PORTED_AGAIN = ('extension P {\n    func old() { _ = z! }\n    func new() { _ = y! }\n'
                      '    func newer() { _ = w! }\n}\n')
PORT_P = 'Port m\n\nSwift-Port: P kind=port\n'


def ported(path, ranges, *findings):
    return {'path': path, 'ranges': ranges,
            'findings': [{'path': path, 'line': ln, 'column': col, 'lint': lint_id, 'message': msg}
                         for ln, col, lint_id, msg in findings]}


Y_FINDING = (3, 23, 'force-unwrap', '"!" force unwrap')


class PortedLinesTests(unittest.TestCase):
    """Item 2: a port that adds code to an existing Swift file that is not a migration file."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/P.m', 'void m(void) { }\nvoid n(void) { }\n')
        self.r.write('sources/P+Ext.swift', P_EXT_BEFORE)
        self.before = self.r.commit('Before\n')

    def stage_port(self):
        self.r.write('sources/P.m', 'void n(void) { }\n')
        self.r.write('sources/P+Ext.swift', P_EXT_PORTED)
        self.r.git('add', '-A')

    def test_staged_and_commit(self):
        self.stage_port()
        msg = write_message(self.r, PORT_P)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, []), err)
        self.assertEqual(rep['ported_lines'], [ported('sources/P+Ext.swift', [[3, 3]], Y_FINDING)])
        self.assertEqual(rep['counts']['force-unwrap'], 1)
        code, out, err = self.r.run('--staged', '--message', msg)
        self.assertIn('\nPorted lines in files that are not migration files: 1 file, 1 finding\n'
                      '  sources/P+Ext.swift (lines linted: 3)\n'
                      '    sources/P+Ext.swift:3:23: force-unwrap: "!" force unwrap\n', out)
        port = self.r.commit(PORT_P)
        code, rep, err = self.r.json(port)
        self.assertEqual((code, finding_lines(rep)), (1, []), err)
        self.assertEqual(rep['ported_lines'], [ported('sources/P+Ext.swift', [[3, 3]], Y_FINDING)])

    def test_tree_mode_lists_and_does_not_lint(self):
        self.stage_port()
        port = self.r.commit(PORT_P)
        code, rep, err = self.r.json()
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), err)
        self.assertEqual(rep['selection']['ported_lines_not_linted'], {'sources/P+Ext.swift': [port]})
        code, out, err = self.r.run()
        self.assertEqual(code, 0, err)
        self.assertIn('\nPorted lines in files that are not migration files are linted only when their commit is '
                      'linted (with REV or --staged), not in tree mode: 1 file\n'
                      '  sources/P+Ext.swift (commit(s) %s)\n' % port[:12], out)

    def test_port_that_adds_a_file_and_modifies_another(self):
        self.stage_port()
        self.r.write('sources/PNew.swift', BAD)
        self.r.git('add', '-A')
        msg = write_message(self.r, PORT_P)
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/PNew.swift:1:10: force-unwrap']), err)
        self.assertEqual(rep['ported_lines'], [ported('sources/P+Ext.swift', [[3, 3]], Y_FINDING)])
        port = self.r.commit(PORT_P)
        code, rep, err = self.r.json(port)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/PNew.swift:1:10: force-unwrap']), err)
        self.assertEqual(rep['ported_lines'], [ported('sources/P+Ext.swift', [[3, 3]], Y_FINDING)])

    def test_non_port_commit_modifying_the_file(self):
        self.r.write('sources/P+Ext.swift', P_EXT_PORTED)
        self.r.git('add', '-A')
        code, rep, err = self.r.json('--staged', '--not-a-port')
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), err)
        code, rep, err = self.r.json('--staged', '--message', write_message(self.r, PLAIN))
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), err)
        later = self.r.commit(PLAIN)
        code, rep, err = self.r.json(later)
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), err)
        code, rep, err = self.r.json()
        self.assertEqual((code, rep['selection']['ported_lines_not_linted']), (0, {}), err)

    def test_later_port_modifying_the_file_again(self):
        self.stage_port()
        first = self.r.commit(PORT_P)
        self.r.write('sources/P+Ext.swift', P_EXT_PORTED_AGAIN)
        self.r.git('add', '-A')
        msg = write_message(self.r, PORT_P)
        expected = [ported('sources/P+Ext.swift', [[4, 4]], (4, 25, 'force-unwrap', '"!" force unwrap'))]
        code, rep, err = self.r.json('--staged', '--message', msg)
        self.assertEqual((code, rep['ported_lines']), (1, expected), err)
        second = self.r.commit(PORT_P)
        code, rep, err = self.r.json(second)
        self.assertEqual((code, rep['ported_lines']), (1, expected), err)
        code, rep, err = self.r.json()
        self.assertEqual((code, rep['selection']['ported_lines_not_linted']),
                         (0, {'sources/P+Ext.swift': [first, second]}), err)

    def test_paired_lints_count_either_line(self):
        self.r.write('sources/Q.swift', 'func q() {\n    objc_sync_enter(l)\n    defer { objc_sync_exit(l) }\n'
                                        '    // SWIFT-MIGRATION-SHIM: bridge\n    let p: UnsafePointer<Int>? = nil\n'
                                        '}\n')
        self.r.commit('Q\n')
        self.r.write('sources/Q.swift', 'func q() {\n    objc_sync_enter(l)\n    f()\n'
                                        '    // a comment\n    let p: UnsafePointer<Int>? = nil\n}\n')
        self.r.git('add', '-A')
        expected = [ported('sources/Q.swift', [[3, 4]],
                           (2, 5, 'sync-pairing', 'objc_sync_enter not followed on the next line by '
                                                  '"defer { objc_sync_exit(l) }"'),
                           (5, 12, 'unsafe-pointer-unmarked', 'UnsafePointer without "// SWIFT-MIGRATION-UNSAFE(hot): '
                                                              '<reason>" or "// SWIFT-MIGRATION-SHIM: <reason>" on the '
                                                              'line above'))]
        code, rep, err = self.r.json('--staged', '--message', write_message(self.r, PORT_P))
        self.assertEqual((code, rep['ported_lines']), (1, expected), err)
        port = self.r.commit(PORT_P)
        code, rep, err = self.r.json(port)
        self.assertEqual((code, rep['ported_lines']), (1, expected), err)

    def test_iuo_marker_line_counts_as_ported(self):
        # Removing the marker above an implicitly unwrapped type is a change to that finding's lines; a marked site
        # on changed lines is listed.
        iuo = 'implicitly unwrapped type outside a property without "// SWIFT-MIGRATION-IUO: <reason>" on the line ' \
              'above or at the end of the line'
        self.r.write('sources/R.swift', '// SWIFT-MIGRATION-IUO: x\nfunc f(a: Int!) { }\nfunc g(a: Int!) { }\n'
                                        'let k = 1\n')
        self.r.commit('R\n')
        self.r.write('sources/R.swift', '// a comment\nfunc f(a: Int!) { }\nfunc g(a: Int!) { }\n'
                                        'func h(a: Int!) { } // SWIFT-MIGRATION-IUO: y\n')
        self.r.git('add', '-A')
        code, rep, err = self.r.json('--staged', '--message', write_message(self.r, PORT_P))
        self.assertEqual((code, rep['ported_lines']),
                         (1, [ported('sources/R.swift', [[1, 1], [4, 4]], (2, 14, 'iuo-unmarked', iuo))]), err)
        self.assertEqual(rep['marked_iuo_sites'], [{'path': 'sources/R.swift', 'line': 4, 'column': 14,
                                                    'marker_line': 4, 'reason': 'y'}])

    def test_rule_docstring_and_help_state_ported_lines(self):
        self.assertNotIn('A file that a port commit only modified is not a migration file', sl.__doc__)
        for text in (sl.MIGRATION_RULE, sl.__doc__, self.r.run('--help')[1]):
            flat = ' '.join(text.split())
            self.assertIn('Ported lines in files that are not migration files', flat)
            self.assertIn('not linted in tree mode', flat)


class SummaryWordingTests(unittest.TestCase):
    """Item 3 and item 4d."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def test_message_without_a_port_trailer_excludes_added_files(self):
        self.r.write('sources/Old.swift', GOOD)
        self.r.commit('Old\n')
        self.r.write('sources/New.swift', BAD)
        self.r.git('add', '-A')
        code, out, err = self.r.run('--staged', '--message', write_message(self.r, PLAIN))
        self.assertEqual(code, 0, err)
        self.assertNotIn('plus files the change adds', out)
        self.assertIn('; the files the change adds are not migration files, because the pending message does not '
                      'have a kind=port trailer.\n', out)

    def test_renamed_migration_file(self):
        self.r.write('sources/Foo.swift', SWIFT_PORT)
        port = self.r.commit(PORT)
        self.r.git('mv', 'sources/Foo.swift', 'sources/Bar.swift')
        later = self.r.commit('Rename\n')
        code, out, err = self.r.run()
        self.assertIn('\n  sources/Bar.swift (created as sources/Foo.swift by %s, renamed to this path by %s, '
                      'unit Foo)\n'
                      % (port[:12], later[:12]), out)
        self.assertNotIn('(created by ', out)

    def test_carried_over_file_renamed_later(self):
        self.r.write('sources/Foo.swift', SWIFT_PORT)
        self.r.commit(PORT)
        self.r.git('rm', '-q', 'sources/Foo.swift')
        self.r.write('sources/Bar.swift', REWRITE)
        carry = self.r.commit(PLAIN)
        self.r.write('sources/Bar.swift', SWIFT_PORT)
        self.r.commit('Restore\n')
        self.r.git('mv', 'sources/Bar.swift', 'sources/Baz.swift')
        rename = self.r.commit('Move\n')
        code, out, err = self.r.run()
        self.assertIn('\n  sources/Baz.swift (treated as a migration file because commit %s deletes migration file(s) '
                      'sources/Foo.swift and adds it as sources/Bar.swift, renamed to this path by %s; unit Foo)\n'
                      % (carry[:12], rename[:12]), out)
        self.assertNotIn('adds this file', out)

    def test_no_zero_skipped_lines(self):
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.r.write('sources/Foo.swift', BAD)
        self.r.git('add', '-A')
        code, out, err = self.r.run('--staged')
        self.assertEqual(code, 1, err)
        self.assertNotIn('Skipped: 0', out)


class HistoryTests(unittest.TestCase):
    """Item 4: re-added paths, incomplete history, merge port commits."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def test_re_added_path_stays_a_migration_file(self):
        self.r.write('sources/A.swift', GOOD)
        port = self.r.commit(PORT)
        self.r.git('rm', '-q', 'sources/A.swift')
        self.r.commit('Revert the port\n')
        self.r.write('sources/A.swift', BAD)
        self.r.git('add', '-A')
        reason = ('treated as a migration file because the path was a migration file before (made one by commit %s)'
                  % port[:12])
        code, rep, err = self.r.json('--staged')
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/A.swift:1:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['readded'], {'sources/A.swift': reason})
        readd = self.r.commit('Reapply the port\n')
        code, rep, err = self.r.json(readd)
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/A.swift:1:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['readded'], {'sources/A.swift': reason})
        code, rep, err = self.r.json()
        self.assertEqual((code, finding_lines(rep)), (1, ['sources/A.swift:1:10: force-unwrap']), err)
        self.assertEqual(rep['selection']['migration_files'],
                         {'sources/A.swift': {'commit': readd, 'unit': 'Foo', 'readded': True}})
        code, out, err = self.r.run()
        self.assertIn('\n  sources/A.swift (re-added by %s at a path that was a migration file; unit Foo)\n'
                      % readd[:12], out)
        self.assertIn('re-adds a Swift file at the same path after a deletion', ' '.join(sl.MIGRATION_RULE.split()))

    WARNING = ('WARNING: the history is incomplete (%s); port commits beyond the visible history cannot be seen, '
               'so migration files may be missed.')

    def test_shallow_repository(self):
        self.r.write('sources/Foo.swift', BAD)
        self.r.commit(PORT)
        self.r.write('sources/Other.swift', GOOD)
        self.r.commit('Later\n')
        dest = tempfile.mkdtemp(prefix='swift_lints_shallow_')
        self.addCleanup(shutil.rmtree, dest, True)
        self.r.git('clone', '-q', '--depth', '1', 'file://' + self.r.root, os.path.join(dest, 'c'))
        shallow = GitRepo.__new__(GitRepo)
        shallow.root = os.path.join(dest, 'c')
        warning = self.WARNING % 'the repository is shallow'
        code, out, err = shallow.run()
        self.assertEqual(code, 2, err)
        self.assertIn('\n' + warning + '\n', out)
        self.assertIn('--allow-incomplete-history', out)
        code, out, err = shallow.run('--allow-incomplete-history')
        self.assertEqual(code, 0, err)
        self.assertIn('\n' + warning + '\n', out)
        for args in (['HEAD'], ['--staged']):
            code, out, err = shallow.run(*args)
            self.assertEqual(code, 0, (args, err))
            self.assertIn('\n' + warning + '\n', out, args)
        code, rep, err = shallow.json('--allow-incomplete-history')
        self.assertEqual(rep['selection']['history_warnings'], [warning])

    def test_replace_refs(self):
        self.r.write('sources/Foo.swift', BAD)
        port = self.r.commit(PORT)
        self.r.write('sources/Other.swift', GOOD)
        later = self.r.commit('Later\n')
        self.r.git('replace', port, later)
        warning = self.WARNING % 'the repository has replace refs'
        code, out, err = self.r.run()
        self.assertEqual(code, 2, err)
        self.assertIn('\n' + warning + '\n', out)
        for args in (['HEAD'], ['--staged']):
            code, out, err = self.r.run(*args)
            self.assertIn('\n' + warning + '\n', out, args)

    def test_merge_port_commit(self):
        self.r.write('sources/Base.swift', GOOD)
        self.r.commit('Base\n')
        self.r.git('checkout', '-q', '-b', 'side')
        self.r.write('sources/Side.swift', BAD)
        self.r.commit('Side\n')
        self.r.git('checkout', '-q', 'master')
        self.r.write('sources/Main.swift', GOOD)
        self.r.commit('Main\n')
        self.r.git('merge', '-q', '--no-ff', '-m', PORT, 'side')
        merge = self.r.git('rev-parse', 'HEAD').strip()
        problem = ('port commit %s is a merge; its files are not identified; the process requires linear history'
                   % merge)
        for args in ([], ['HEAD'], ['--staged']):
            code, rep, err = self.r.json(*args)
            self.assertEqual(code, 2, (args, err))
            self.assertIn(problem, [p['problem'] for p in rep['selection']['trailer_problems']], args)
        code, out, err = self.r.run()
        self.assertIn(problem, out)


class SixthReviewLintTests(unittest.TestCase):
    def test_closure_parameter_named_async_with_a_return_type(self):
        self.assertEqual(lint('let c = { async -> Int in async }\nlet d = { [c] async -> Int in c(async) }'), [])
        self.assertEqual(lint('let e = { (x) async -> Int in x }\nlet f = { x async -> Int in x }'),
                         [(1, 15, 'stage-one-concurrency'), (2, 13, 'stage-one-concurrency')])


B_MODIFIED = 'let b = 1\nlet n = z!\n'
Z_FINDING = (2, 10, 'force-unwrap', '"!" force unwrap')


class StagedModifyOnlyTests(unittest.TestCase):
    """Seventh round, item 1: a staged change that only modifies Swift files that are not migration files."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/B.swift', 'let b = 1\n')
        self.r.commit('Before\n')
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.r.write('sources/B.swift', B_MODIFIED)
        self.r.git('add', '-A')

    def test_modify_only_without_option(self):
        code, out, err = self.r.run('--staged')
        self.assertEqual((code, out), (2, ''))
        self.assertEqual(err, 'swift_lints.py: the staged change modifies 1 Swift file that is not a migration file '
                              '(sources/B.swift) and this tool cannot tell whether the lines it changes are ported '
                              'lines without --message FILE holding the pending commit message; pass --not-a-port if '
                              'the commit is not a port commit\n')
        for name in ('C1', 'C2', 'C3', 'C4', 'C5'):
            self.r.write('sources/%s.swift' % name, GOOD)
        self.r.commit('More\n')
        for name in ('B', 'C1', 'C2', 'C3', 'C4', 'C5'):
            self.r.write('sources/%s.swift' % name, BAD)
        self.r.git('add', '-A')
        code, out, err = self.r.run('--staged')
        self.assertEqual((code, out), (2, ''))
        self.assertIn('the staged change modifies 6 Swift files that are not migration files (sources/B.swift, '
                      'sources/C1.swift, sources/C2.swift, sources/C3.swift, sources/C4.swift, and 1 more) and this '
                      'tool cannot tell', err)

    def test_modify_only_port_message(self):
        code, rep, err = self.r.json('--staged', '--message', write_message(self.r, PORT_P))
        self.assertEqual((code, finding_lines(rep)), (1, []), err)
        self.assertEqual(rep['ported_lines'], [ported('sources/B.swift', [[2, 2]], Z_FINDING)])

    def test_modify_only_plain_message(self):
        for text in (PLAIN, TOOL):
            code, rep, err = self.r.json('--staged', '--message', write_message(self.r, text))
            self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), (text, err))

    def test_modify_only_unusable_trailer(self):
        code, out, err = self.r.run('--staged', '--message',
                                    write_message(self.r, 'Port\n\nSwift-Port: Foo kind = port\n'))
        self.assertEqual((code, out), (2, ''))
        self.assertEqual(err, 'swift_lints.py: the staged change modifies 1 Swift file that is not a migration file '
                              '(sources/B.swift) and the pending commit message has no usable Swift-Port trailer '
                              '(malformed trailer (not counted): Swift-Port: Foo kind = port), so this tool cannot '
                              'tell whether the lines it changes are ported lines; the modified Swift files were not '
                              'checked; fix the trailer, or pass --not-a-port if the commit is not a port commit\n')
        code, out, err = self.r.run('--staged', '--message', write_message(self.r, 'Port\n\nSwift-Port: Foo kind=prot\n'))
        self.assertEqual((code, out), (2, ''))
        self.assertIn('the modified Swift files were not checked', err)

    def test_change_touching_no_swift_file_needs_no_option(self):
        self.r.git('reset', '-q')
        self.r.write('sources/X.m', 'x\n')
        self.r.git('add', 'sources/X.m')
        code, rep, err = self.r.json('--staged')
        self.assertEqual((code, finding_lines(rep)), (0, []), err)

    def test_help_says_message_is_required(self):
        flat = ' '.join(self.r.run('--help')[1].split())
        self.assertIn('required with --staged unless --not-a-port is given', flat)


A_WITH_MOVED = 'let a = 1\nlet moved = y!\n'
B_WITH_OLD = 'let b = 1\nlet old = z!\n'
B_WITH_MOVED = 'let b = 1\nlet old = z!\nlet moved = y!\n'
MOVED_FINDING = (3, 14, 'force-unwrap', '"!" force unwrap')
ALSO_TOUCHES = 'this change also touches migration file(s) sources/A.swift'


def ported_with_reason(path, ranges, reason, *findings):
    entry = ported(path, ranges, *findings)
    entry['reason'] = reason
    return entry


class NonPortTouchingMigrationFileTests(unittest.TestCase):
    """Seventh round, item 2: code moved out of a migration file into an existing file that is not one."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/B.swift', B_WITH_OLD)
        self.r.commit('Before\n')

    def stage_move(self):
        self.r.write('sources/A.swift', 'let a = 1\n')
        self.r.write('sources/B.swift', B_WITH_MOVED)
        self.r.git('add', '-A')

    def test_improve_moves_code_from_a_migration_file(self):
        self.r.write('sources/A.swift', A_WITH_MOVED)
        self.r.commit(PORT)
        self.stage_move()
        expected = [ported_with_reason('sources/B.swift', [[3, 3]], ALSO_TOUCHES, MOVED_FINDING)]
        for args in (['--message', write_message(self.r, IMPROVE)], [], ['--not-a-port']):
            code, rep, err = self.r.json('--staged', *args)
            self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (1, [], expected), (args, err))
        code, out, err = self.r.run('--staged', '--message', write_message(self.r, IMPROVE))
        self.assertIn('\nPorted lines in files that are not migration files: 1 file, 1 finding\n'
                      '  sources/B.swift (lines linted: 3; ' + ALSO_TOUCHES + ')\n'
                      '    sources/B.swift:3:14: force-unwrap: "!" force unwrap\n', out)
        improve = self.r.commit(IMPROVE)
        code, rep, err = self.r.json(improve)
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (1, [], expected), err)
        code, rep, err = self.r.json()
        self.assertEqual((code, rep['ported_lines'], rep['selection']['ported_lines_not_linted']),
                         (0, [], {'sources/B.swift': [improve]}), err)

    def test_same_shape_touching_no_migration_file(self):
        self.r.write('sources/A.swift', A_WITH_MOVED)
        self.r.commit('A\n')
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.stage_move()
        code, out, err = self.r.run('--staged')
        self.assertEqual(code, 2, out)
        self.assertIn('cannot tell whether the lines it changes are ported lines', err)
        code, rep, err = self.r.json('--staged', '--message', write_message(self.r, IMPROVE))
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), err)
        improve = self.r.commit(IMPROVE)
        code, rep, err = self.r.json(improve)
        self.assertEqual((code, finding_lines(rep), rep['ported_lines']), (0, [], []), err)
        code, rep, err = self.r.json()
        self.assertEqual((code, rep['selection']['ported_lines_not_linted']), (0, {}), err)

    def test_rule_docstring_and_help_state_it(self):
        for text in (sl.MIGRATION_RULE, sl.__doc__, self.r.run('--help')[1]):
            flat = ' '.join(text.split())
            self.assertIn('every Swift file that is not a migration file and that the change modifies', flat)
            self.assertIn('unrelated edits made in the same commit', flat)


class DeletionHunkTests(unittest.TestCase):
    """Seventh round, item 3: a hunk that only deletes lines touches the lines on either side of it."""

    def test_deleted_defer_after_an_unchanged_enter(self):
        r = GitRepo()
        self.addCleanup(r.cleanup)
        r.write('sources/Q.swift', 'func q() {\n    objc_sync_enter(l)\n    defer { objc_sync_exit(l) }\n}\n')
        r.commit('Q\n')
        r.write('sources/Q.swift', 'func q() {\n    objc_sync_enter(l)\n}\n')
        r.git('add', '-A')
        expected = [ported('sources/Q.swift', [[2, 3]],
                           (2, 5, 'sync-pairing', 'objc_sync_enter not followed on the next line by '
                                                  '"defer { objc_sync_exit(l) }"'))]
        code, rep, err = r.json('--staged', '--message', write_message(r, PORT_P))
        self.assertEqual((code, rep['ported_lines']), (1, expected), err)
        port = r.commit(PORT_P)
        code, rep, err = r.json(port)
        self.assertEqual((code, rep['ported_lines']), (1, expected), err)
        self.assertIn('a deletion', ' '.join(sl.MIGRATION_RULE.split()))


class SurvivingMutantTests(unittest.TestCase):
    """Seventh round, item 4."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)
        self.r.write('sources/P+Ext.swift', P_EXT_BEFORE)
        self.r.commit('Before\n')
        self.r.write('sources/P+Ext.swift', P_EXT_PORTED)
        self.port = self.r.commit(PORT_P)

    def test_rev_ported_lines_are_diffed_against_the_first_parent(self):
        self.r.write('sources/P+Ext.swift', P_EXT_PORTED_AGAIN)
        self.r.commit('Later\n')
        code, rep, err = self.r.json(self.port)
        self.assertEqual((code, rep['ported_lines']), (1, [ported('sources/P+Ext.swift', [[3, 3]], Y_FINDING)]), err)

    def test_tree_mode_follows_a_later_rename(self):
        self.r.git('mv', 'sources/P+Ext.swift', 'sources/P+Moved.swift')
        self.r.commit('Move\n')
        code, rep, err = self.r.json()
        self.assertEqual((code, rep['selection']['ported_lines_not_linted']),
                         (0, {'sources/P+Moved.swift': [self.port]}), err)


class SeventhReviewWordingTests(unittest.TestCase):
    """Seventh round, item 5."""

    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def test_tree_summary_counts_by_reason(self):
        self.r.write('sources/Foo.swift', GOOD)
        self.r.commit(PORT)
        self.r.write('sources/Bar.swift', SWIFT_PORT)
        self.r.commit('Port Bar\n\nSwift-Port: Bar kind=port\n')
        self.r.git('mv', 'sources/Bar.swift', 'sources/Baz.swift')
        self.r.commit('Move\n')
        self.r.write('sources/Foo.swift', GOOD + GOOD)
        self.r.write('sources/FooPart.swift', GOOD)
        self.r.commit(IMPROVE)
        self.r.write('sources/D.swift', GOOD)
        self.r.commit('Port D\n\nSwift-Port: D kind=port\n')
        self.r.git('rm', '-q', 'sources/D.swift')
        self.r.commit('Revert\n')
        self.r.write('sources/D.swift', GOOD)
        self.r.commit('Reapply\n')
        code, out, err = self.r.run()
        self.assertEqual(code, 1, err)
        self.assertIn('\nMigration files linted: 4, identified by the trailer history (3 port commits found): 1 '
                      'created by a port commit, 1 renamed from a migration file, 1 carried over, 1 re-added\n', out)

    def test_rev_help_mentions_ported_lines(self):
        flat = ' '.join(self.r.run('--help')[1].split())
        self.assertIn('rev lint the migration files this commit touches, and the ported lines', flat)


class RealTreeSmokeTest(unittest.TestCase):
    def test_current_tree_has_no_migration_files(self):
        p = subprocess.run([sys.executable, '-B', SCRIPT], cwd=TOOL_DIR, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)
        out = p.stdout.decode()
        if 'Migration files linted: 0' not in out:
            self.skipTest('the tree now has migration files')
        self.assertEqual(p.returncode, 0, p.stderr.decode())
        self.assertIn('There are no migration files.', out)



# ---------------------------------------------------------------------------
# Implicitly unwrapped types outside properties (decisions.md, 2026-11-20; owner queue Q20 item 1)

# Each fixture: (name, source, the lint's findings as (line, column, lint), what the compiler says).
# The compiler check (IuoCompilerTests, run with SWIFT_LINTS_COMPILER_CHECK=1) runs xcrun swiftc -parse on every
# fixture, which must succeed, and then, by kind:
#   ('iuo', [(line, column)]): the fixture type-checks, -dump-parse has no force_value_expr, and for each position,
#       replacing the "!" there with "?" makes type-checking fail. Each fixture uses its implicitly unwrapped
#       declaration as a non-optional value, which only an implicitly unwrapped optional allows, so this shows that
#       the compiler reads that "!" as an implicitly unwrapped type.
#   ('iuo-illegal', [(line, column)]): -dump-parse has no force_value_expr, and type-checking reports "using '!' is
#       not allowed here" at each position: the parser read that "!" as an implicitly unwrapped type, in a position
#       where Swift does not allow one, so such code never compiles.
#   ('iuo-type', [(line, column)]): for a "!" whose implicit unwrapping no use can show (an associated value's
#       payload binds as an Optional, as does a property wrapper's wrapped value). -dump-parse has no
#       force_value_expr, the fixture type-checks, and for each position, replacing the "!" there with "?" removes
#       exactly one "!" from the declarations -print-ast prints: the compiler records an implicitly unwrapped type
#       at that position.
#   ('expr', n): -dump-parse has exactly n force_value_expr nodes (not counting the copy of a pattern binding's
#       initializer printed as processed_init) and no type_implicitly_unwrapped_optional; the fixture is only parsed,
#       since its names are not declared.
IUO_TYPE_FIXTURES = [
    ('parameter', 'func f(a: Int!) -> Int { return a }', [(1, 14, 'iuo-unmarked')], ('iuo', [(1, 14)])),
    ('labeled parameter', 'func f(label a: Int!) -> Int { return a }', [(1, 20, 'iuo-unmarked')], ('iuo', [(1, 20)])),
    ('unlabeled parameter', 'func f(_ a: Int!) -> Int { return a }', [(1, 16, 'iuo-unmarked')], ('iuo', [(1, 16)])),
    ('result', 'func f() -> Int! { return 1 }\nlet v: Int = f()', [(1, 16, 'iuo-unmarked')], ('iuo', [(1, 16)])),
    ('parameters and result on several lines',
     'func f(\n    a: Int!,\n    b: [String: Int]!\n) -> Int! { return a + b.count }\nlet v: Int = f(a: 1, b: [:])',
     [(2, 11, 'iuo-unmarked'), (3, 21, 'iuo-unmarked'), (4, 9, 'iuo-unmarked')],
     ('iuo', [(2, 11), (3, 21), (4, 9)])),
    ('initializer parameter', 'class C { var x = 0; init(a: Int!) { x = a } }', [(1, 33, 'iuo-unmarked')],
     ('iuo', [(1, 33)])),
    ('init!', 'class C { init!(a: Int) { return nil } }\nlet c: C = C(a: 1)', [(1, 15, 'iuo-unmarked')],
     ('iuo', [(1, 15)])),
    ('generic init!', 'class C { init!<T>(a: T) { return nil } }\nlet c: C = C(a: 1)', [(1, 15, 'iuo-unmarked')],
     ('iuo', [(1, 15)])),
    ('subscript parameter and result', 'class C { subscript(i: Int!) -> Int! { return i + 0 } }\nlet v: Int = C()[1]',
     [(1, 27, 'iuo-unmarked'), (1, 36, 'iuo-unmarked')], ('iuo', [(1, 27), (1, 36)])),
    ('closure expression parameter', 'let c = { (t: Int!) in t + 0 }', [(1, 18, 'iuo-unmarked')], ('iuo', [(1, 18)])),
    ('closure expression parameter after a capture list', 'let k = 1\nlet c = { [k] (t: Int!) in t + k }',
     [(2, 22, 'iuo-unmarked')], ('iuo', [(2, 22)])),
    ('local let', 'func f() -> Int { let x: Int! = 1; return x }', [(1, 29, 'iuo-unmarked')], ('iuo', [(1, 29)])),
    ('second local in one declaration', 'func f() -> Int { var a: Int! = 1, b: Int! = 2; return a + b }',
     [(1, 29, 'iuo-unmarked'), (1, 42, 'iuo-unmarked')], ('iuo', [(1, 29), (1, 42)])),
    # A file-scope var is banned outright (file-scope-var), and its implicitly unwrapped type still needs the marker.
    ('file-scope variable', 'var g: Int! = 1\nlet v: Int = g', [(1, 1, 'file-scope-var'), (1, 11, 'iuo-unmarked')],
     ('iuo', [(1, 11)])),
    ('file-scope constant', 'let g: Int! = 1\nlet v: Int = g', [(1, 11, 'iuo-unmarked')], ('iuo', [(1, 11)])),
    ('generic type made implicitly unwrapped', 'func f(a: Dictionary<String, Int>!) -> Int { return a.count }',
     [(1, 34, 'iuo-unmarked')], ('iuo', [(1, 34)])),
    ('parenthesized function type made implicitly unwrapped', 'func f(a: (() -> Void)!) { a() }',
     [(1, 23, 'iuo-unmarked')], ('iuo', [(1, 23)])),
    ('Optional<Int>! result', 'func f() -> Optional<Int>! { return 1 }\nlet v: Int? = f()', [(1, 26, 'iuo-unmarked')],
     ('iuo', [(1, 26)])),
    # An implicitly unwrapped parameter of a requirement has no effect a use can show (a witness may declare it
    # either way), so only the result is checked by use; the parameter is the same syntax as the others.
    ('protocol requirement', 'protocol P { func f(a: Int!) -> Int! }\nfunc g(p: P) -> Int { return p.f(a: 1) }',
     [(1, 27, 'iuo-unmarked'), (1, 36, 'iuo-unmarked')], ('iuo', [(1, 36)])),
    ('method parameter', 'class C { func f(a: Int!) -> Int { return a } }', [(1, 24, 'iuo-unmarked')],
     ('iuo', [(1, 24)])),
    # An attribute (a property wrapper) before a parameter's name, and an enum case's associated values. Neither
    # has an effect a use can show (the wrapped value and the bound payload are Optional either way), so the
    # compiler check is 'iuo-type' (see above).
    ('attribute before a parameter', '@propertyWrapper struct W { var wrappedValue: Int? }\nfunc at(@W v: Int!) { }',
     [(2, 18, 'iuo-unmarked')], ('iuo-type', [(2, 18)])),
    ('attribute with arguments before a parameter',
     '@propertyWrapper struct Wrapper { var wrappedValue: Int?; init(wrappedValue: Int?, arg: Int) { '
     'self.wrappedValue = wrappedValue } }\nfunc f(@Wrapper(arg: 1) v: Int!) { }\n'
     'func g(_ a: Int, @Wrapper(arg: 2) label v: Int!) { }',
     [(2, 31, 'iuo-unmarked'), (3, 47, 'iuo-unmarked')], ('iuo-type', [(2, 31), (3, 47)])),
    ('enum associated values', 'enum E { case a(Int!), b(x: String!) }',
     [(1, 20, 'iuo-unmarked'), (1, 35, 'iuo-unmarked')], ('iuo-type', [(1, 20), (1, 35)])),
    ('enum associated values on several lines',
     'enum E {\n    case a(\n        Int!,\n        y: [Int]!\n    )\n    indirect case c(E!)\n}',
     [(3, 12, 'iuo-unmarked'), (4, 17, 'iuo-unmarked'), (6, 22, 'iuo-unmarked')],
     ('iuo-type', [(3, 12), (4, 17), (6, 22)])),
    ('second associated value, unlabeled', 'enum E { case c(Int, String!) }', [(1, 28, 'iuo-unmarked')],
     ('iuo-type', [(1, 28)])),
    ('case list continued on the next line', 'enum E {\n    case a(Int!),\n        b(String!)\n}',
     [(2, 15, 'iuo-unmarked'), (3, 17, 'iuo-unmarked')], ('iuo-type', [(2, 15), (3, 17)])),
    ('local in a method', 'class C { func f() -> Int { let x: Int! = 1; return x } }', [(1, 39, 'iuo-unmarked')],
     ('iuo', [(1, 39)])),
    ('local in a closure that initializes a property', 'class C { var p: Int = { let x: Int! = 1; return x }() }',
     [(1, 36, 'iuo-unmarked')], ('iuo', [(1, 36)])),
    # Positions where Swift does not allow an implicitly unwrapped type. Each "!" is a type, never a force
    # unwrap, so it is reported as iuo-unmarked, including inside a property's type; the compiler rejects them.
    ('function type parameter', 'func f(a: (Int!) -> Void) { }', [(1, 15, 'iuo-unmarked')],
     ('iuo-illegal', [(1, 15)])),
    ('function type result', 'func f(a: () -> Int!) { }', [(1, 20, 'iuo-unmarked')], ('iuo-illegal', [(1, 20)])),
    ('closure expression result', 'let c = { (t: Int) -> Int! in t }', [(1, 26, 'iuo-unmarked')],
     ('iuo-illegal', [(1, 26)])),
    ('array element', 'let a: [Int!] = []', [(1, 12, 'iuo-unmarked')], ('iuo-illegal', [(1, 12)])),
    ('generic argument', 'let a: Array<Int!> = []', [(1, 17, 'iuo-unmarked')], ('iuo-illegal', [(1, 17)])),
    ('tuple element', 'let t: (Int!, Int) = (1, 2)', [(1, 12, 'iuo-unmarked')], ('iuo-illegal', [(1, 12)])),
    ('function type in a property', 'class C { var cb: ((Int!) -> Void)? }', [(1, 24, 'iuo-unmarked')],
     ('iuo-illegal', [(1, 24)])),
    ('function type result in a property', 'class C { var f: () -> Int! }', [(1, 27, 'iuo-unmarked')],
     ('iuo-illegal', [(1, 27)])),
    ('function type inside generic arguments of a property',
     'class C { var g: Dictionary<Int, (Int!) -> Void>? }', [(1, 38, 'iuo-unmarked')], ('iuo-illegal', [(1, 38)])),
    ('as cast', 'let x = 1\nlet v = x as Int!', [(2, 17, 'iuo-unmarked')], ('iuo-illegal', [(2, 17)])),
    ('is check', 'let x = 1\nlet v = x is Int!', [(2, 17, 'iuo-unmarked')], ('iuo-illegal', [(2, 17)])),
]

# Properties declared implicitly unwrapped: allowed (translation-rules.md section 7), not reported.
IUO_PROPERTY_FIXTURES = [
    ('stored property', 'class C { var p: Int! = 1 }\nlet v: Int = C().p', [], ('iuo', [(1, 21)])),
    ('static property of a struct', 'struct S { static var s: Int! = 1 }\nlet v: Int = S.s', [], ('iuo', [(1, 29)])),
    ('protocol property requirement', 'protocol P { var r: Int! { get } }\nfunc g(p: P) -> Int { return p.r }', [],
     ('iuo', [(1, 24)])),
    ('computed property in an extension', 'class C { }\nextension C { var e: Int! { return 1 } }\nlet v: Int = C().e',
     [], ('iuo', [(2, 25)])),
    ('property of a function-local type', 'func f() -> Int { class L { var p: Int! = 1 }; return L().p }', [],
     ('iuo', [(1, 39)])),
    ('two properties in one declaration', 'class C { var a: Int! = 1, b: Int! = 2 }\nlet v: Int = C().a + C().b', [],
     ('iuo', [(1, 21), (1, 34)])),
    ('lazy property', 'class C { lazy var l: Int! = 1 }\nlet v: Int = C().l', [], ('iuo', [(1, 26)])),
    ('property with an observer', 'class C { var w: Int! = 1 { didSet { } } }\nlet v: Int = C().w', [],
     ('iuo', [(1, 21)])),
    ('implicitly unwrapped function type property', 'class C { var f: (() -> Void)! = { } }\nfunc g() { C().f() }', [],
     ('iuo', [(1, 30)])),
    ('outlet: iuo-outlet, not iuo-unmarked', 'import AppKit\nclass C { @IBOutlet var v: NSView! }\nlet w: NSView = C().v',
     [(2, 34, 'iuo-outlet')], ('iuo', [(2, 34)])),
]

# Force unwraps of values and other "!" that are not types: never iuo-unmarked.
IUO_EXPRESSION_FIXTURES = [
    ('a!', 'let v = a!', [(1, 10, 'force-unwrap')], ('expr', 1)),
    ('a!.b', 'let v = a!.b', [(1, 10, 'force-unwrap')], ('expr', 1)),
    ('a![0]', 'let v = a![0]', [(1, 10, 'force-unwrap')], ('expr', 1)),
    ('f()!', 'let v = f()!', [(1, 12, 'force-unwrap')], ('expr', 1)),
    ('x != y', 'let v = x != y', [], ('expr', 0)),
    ('!x', 'let v = !x', [], ('expr', 0)),
    ('postfix after )', 'let v = (a)!', [(1, 12, 'force-unwrap')], ('expr', 1)),
    ('postfix after ]', 'let v = a[0]!', [(1, 13, 'force-unwrap')], ('expr', 1)),
    ('ternary', 'let v = c ? a! : b', [(1, 14, 'force-unwrap')], ('expr', 1)),
    ('ternary with type-like names', 'let v = c ? T! : U', [(1, 14, 'force-unwrap')], ('expr', 1)),
    ('string interpolation', 'let s = "\\(a!)"', [(1, 13, 'force-unwrap')], ('expr', 1)),
    ('try!', 'let v = try! f()', [(1, 9, 'forced-try')], ('expr', 0)),
    ('as!', 'let v = x as! Int', [(1, 11, 'forced-cast')], ('expr', 0)),
    ('default argument', 'func g(a: Int = b!) { }', [(1, 18, 'force-unwrap')], ('expr', 1)),
    ('ternary in a default argument', 'func g(a: Int = c ? x : y!) { }', [(1, 26, 'force-unwrap')], ('expr', 1)),
    ('call argument label', 'h(x: y!)', [(1, 7, 'force-unwrap')], ('expr', 1)),
    ('dictionary literal', 'let m = [k: v!]', [(1, 14, 'force-unwrap')], ('expr', 1)),
    ('initializer of an annotated local', 'func f() { let v: Int = w! }', [(1, 26, 'force-unwrap')], ('expr', 1)),
    ('nil coalescing in an annotated initializer', 'let v: Int = a ?? b!', [(1, 20, 'force-unwrap')], ('expr', 1)),
    ('switch case label', 'switch v { case .a: x! }', [(1, 22, 'force-unwrap')], ('expr', 1)),
    ('closure body after its parameters', 'f { (a: Int) in a! }', [(1, 18, 'force-unwrap')], ('expr', 1)),
    ('optional chain then force', 'let v = a?.b!', [(1, 13, 'force-unwrap')], ('expr', 1)),
    ('"!" inside a string', 'let s = "a!: Int!"', [], ('expr', 0)),
    ('prefix ! after a label', 'f(x: !y)', [], ('expr', 0)),
    ('call in a switch case pattern', 'switch v { case f(x!): break }', [(1, 20, 'force-unwrap')], ('expr', 1)),
    # -dump-parse prints each enum element twice (under its case declaration and as a member of the enum), so the
    # one force unwrap appears as two nodes.
    ('default value of an associated value', 'enum E { case a(x: Int = y!) }', [(1, 27, 'force-unwrap')],
     ('expr', 2)),
    ('call in a default value of an associated value', 'enum E { case a(x: Int = g(1, h(y!))) }',
     [(1, 34, 'force-unwrap')], ('expr', 2)),
    ('attribute argument before a parameter', 'func f(@W(a!) v: Int) { }', [(1, 12, 'force-unwrap')], ('expr', 1)),
]

IUO_FIXTURES = IUO_TYPE_FIXTURES + IUO_PROPERTY_FIXTURES + IUO_EXPRESSION_FIXTURES


def count_outside_processed_init(dump, word):
    """Occurrences of word in a -dump-parse dump, skipping each processed_init subtree, which repeats the
    original_init of a pattern binding."""
    count = 0
    skip_deeper_than = None
    for line in dump.split('\n'):
        indent = len(line) - len(line.lstrip(' '))
        if skip_deeper_than is not None:
            if indent > skip_deeper_than:
                continue
            skip_deeper_than = None
        if line.lstrip(' ').startswith('(processed_init='):
            skip_deeper_than = indent
            continue
        count += line.count(word)
    return count


def lint_iuo_sites(src):
    return [(m['line'], m['column'], m['reason']) for m in sl.lint_source_full('t.swift', src)[2]]


class IuoTests(unittest.TestCase):
    def test_fixtures(self):
        for name, src, expected, _ in IUO_FIXTURES:
            self.assertEqual(lint(src), expected, name)

    def test_column_is_the_exclamation_mark(self):
        # A "!" that the lexer joins with ">" into one operator is reported at the "!".
        self.assertEqual(lint('func f(a: A<B<C>>!) { }'), [(1, 18, 'iuo-unmarked')])

    def test_marker_on_the_line_above(self):
        src = '// SWIFT-MIGRATION-IUO: the header is not annotated yet\nfunc f(a: Int!) { }'
        self.assertEqual(lint(src), [])
        self.assertEqual(lint_iuo_sites(src), [(2, 14, 'the header is not annotated yet')])

    def test_marker_at_the_end_of_the_line(self):
        src = 'func f(a: Int!) { } // SWIFT-MIGRATION-IUO: matches the imported signature'
        self.assertEqual(lint(src), [])
        self.assertEqual(lint_iuo_sites(src), [(1, 14, 'matches the imported signature')])

    def test_marker_at_the_end_of_a_line_covers_only_that_line(self):
        self.assertEqual(lint('let k = 1 // SWIFT-MIGRATION-IUO: x\nfunc f(a: Int!) { }'), [(2, 14, 'iuo-unmarked')])

    def test_marker_not_directly_above(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO: x\n\nfunc f(a: Int!) { }'), [(3, 14, 'iuo-unmarked')])

    def test_one_marker_covers_every_site_on_its_line(self):
        src = '// SWIFT-MIGRATION-IUO: x\nfunc f(a: Int!) -> Int! { return a }'
        self.assertEqual(lint(src), [])
        self.assertEqual(lint_iuo_sites(src), [(2, 14, 'x'), (2, 23, 'x')])

    def test_one_marker_per_declaration_on_consecutive_lines(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO: x\nfunc f(a: Int!) { }\nfunc g(a: Int!) { }'),
                         [(3, 14, 'iuo-unmarked')])

    def test_parameters_on_several_lines(self):
        src = 'func f(\n    // SWIFT-MIGRATION-IUO: x\n    a: Int!,\n    b: Int!\n) { }'
        self.assertEqual(lint(src), [(4, 11, 'iuo-unmarked')])

    def test_init_bang_and_local(self):
        src = 'class C {\n    // SWIFT-MIGRATION-IUO: a\n    init!(a: Int) { return nil }\n    func f() {\n' \
              '        let x: Int! = nil // SWIFT-MIGRATION-IUO: b\n    }\n}'
        self.assertEqual(lint(src), [])
        self.assertEqual(lint_iuo_sites(src), [(3, 9, 'a'), (5, 19, 'b')])

    def test_other_markers_do_not_cover_and_are_not_covered(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-SHIM: x\nfunc f(a: Int!) { }'), [(2, 14, 'iuo-unmarked')])
        self.assertEqual(lint('// SWIFT-MIGRATION-UNSAFE(hot): x\nfunc f(a: Int!) { }'), [(2, 14, 'iuo-unmarked')])
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO: x\nlet p: UnsafePointer<Int>? = nil'),
                         [(2, 8, 'unsafe-pointer-unmarked')])
        self.assertEqual(marked('// SWIFT-MIGRATION-IUO: x\nfunc f(a: Int!) { }'), [])

    def test_marker_does_not_excuse_a_force_unwrap(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO: x\nlet v = a!'), [(2, 10, 'force-unwrap')])

    def test_valid_marker_form(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO: reason with (parentheses): and colons'), [])

    def test_malformed_markers(self):
        src = '\n'.join(['// SWIFT-MIGRATION-IUO:', '// SWIFT-MIGRATION-IUO reason', '/* SWIFT-MIGRATION-IUO: x */',
                         '//SWIFT-MIGRATION-IUO: x', '// SWIFT-MIGRATION-IUO(hot): x', '/// SWIFT-MIGRATION-IUO: x',
                         '// SWIFT-MIGRATION-IUO:   '])
        self.assertEqual(lint(src), [(1, 4, 'marker-format'), (2, 4, 'marker-format'), (3, 4, 'marker-format'),
                                     (4, 3, 'marker-format'), (5, 4, 'marker-format'), (6, 5, 'marker-format'),
                                     (7, 4, 'marker-format')])

    def test_malformed_marker_does_not_cover(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO:\nfunc f(a: Int!) { }'),
                         [(1, 4, 'marker-format'), (2, 14, 'iuo-unmarked')])

    def test_marker_format_message_names_the_iuo_form(self):
        findings, _ = sl.lint_source('t.swift', '// SWIFT-MIGRATION-IUO:')
        self.assertIn('"// SWIFT-MIGRATION-IUO: <reason>"', findings[0].message)

    def test_message(self):
        findings, _ = sl.lint_source('t.swift', 'func f(a: Int!) { }')
        self.assertEqual(findings[0].message,
                         'implicitly unwrapped type outside a property without "// SWIFT-MIGRATION-IUO: <reason>" on '
                         'the line above or at the end of the line')

    def test_legend(self):
        self.assertIn('SWIFT-MIGRATION-IUO', sl.LINTS['iuo-unmarked'])
        self.assertIn('SWIFT-MIGRATION-IUO', sl.LINTS['marker-format'])


class TrapCallFailureTests(unittest.TestCase):
    """assertionFailure and preconditionFailure join fatalError, assert and precondition (decisions.md,
    2026-11-20). The rule is the existing one: a call, written name( or Swift.name(, is reported; a function being
    declared (func name), a member call (x.name()), a reference without a call and a call with only a trailing
    closure are not. The last does not compile for any of the five (their messages are autoclosures)."""

    def test_reported(self):
        src = '\n'.join(['assertionFailure()', 'assertionFailure("m")', 'preconditionFailure()',
                         'preconditionFailure ("m")', 'Swift.assertionFailure()', 'Swift.preconditionFailure("m")',
                         'func f() { if c { assertionFailure("m") } }'])
        self.assertEqual(lint(src), [(1, 1, 'trap-call'), (2, 1, 'trap-call'), (3, 1, 'trap-call'),
                                     (4, 1, 'trap-call'), (5, 7, 'trap-call'), (6, 7, 'trap-call'),
                                     (7, 19, 'trap-call')])

    def test_not_reported(self):
        src = '\n'.join(['class T { func assertionFailure() { } }', 'func preconditionFailure(_ m: String) { }',
                         'x.assertionFailure()', 'logger.preconditionFailure("m")', 'let f = assertionFailure',
                         'assertionFailure { "m" }', 'fatalError { "m" }', 'let preconditionFailure = 1'])
        self.assertEqual(lint(src), [])

    def test_messages_name_the_replacement(self):
        findings, _ = sl.lint_source('t.swift', 'assertionFailure()\npreconditionFailure()\nfatalError()')
        self.assertEqual([f.message for f in findings], [
            'assertionFailure; use it_assert(false, ...) or a beta assertion (it_betaAssert); assertionFailure does '
            'nothing in release builds, where the Objective-C assert it replaces stays enabled',
            'preconditionFailure; use it_fatalError',
            'fatalError; use the it_ version'])
        findings, _ = sl.lint_source('t.swift', 'Swift.assertionFailure()\nSwift.preconditionFailure()')
        self.assertEqual([f.message for f in findings], [
            'Swift.assertionFailure; use it_assert(false, ...) or a beta assertion (it_betaAssert); assertionFailure '
            'does nothing in release builds, where the Objective-C assert it replaces stays enabled',
            'Swift.preconditionFailure; use it_fatalError'])


class DecidedNotImplementedTests(unittest.TestCase):
    def test_not_checked_states_the_decisions(self):
        rows = dict((r, w) for r, _, w in sl.NOT_CHECKED)
        pointer = [w for r, w in rows.items() if '&x' in r]
        self.assertEqual(len(pointer), 1)
        self.assertIn('type-aware lints on the Swift AST', pointer[0])
        self.assertIn('review item', pointer[0])
        rule = [w for r, w in rows.items() if 'which files are migration files' in r]
        self.assertEqual(len(rule), 1)
        self.assertIn('provisional until the pilot', rule[0])

    def test_help_states_the_decisions(self):
        r = GitRepo()
        self.addCleanup(r.cleanup)
        flat = ' '.join(r.run('--help')[1].split())
        self.assertIn('the unsafe marker on &x passed to a pointer parameter is to be enforced by type-aware lints '
                      'on the Swift AST', flat)
        self.assertIn('the rule for which files are migration files stays provisional until the pilot', flat)
        self.assertIn('--list-iuo', flat)


class ListIuoTests(unittest.TestCase):
    def setUp(self):
        self.r = GitRepo()
        self.addCleanup(self.r.cleanup)

    def test_lists_every_marked_site(self):
        self.r.write('sources/A.swift', '// SWIFT-MIGRATION-IUO: header not annotated\nfunc f(a: Int!) -> Int! '
                                        '{ return a }\nfunc g(b: Int!) { } // SWIFT-MIGRATION-IUO: second\n')
        self.r.write('ThirdParty/Other/B.swift', 'func h(c: Int!) { } // SWIFT-MIGRATION-IUO: elsewhere\n')
        self.r.write('docs/swift-migration/C.swift', 'func i(c: Int!) { } // SWIFT-MIGRATION-IUO: describes\n')
        self.r.write('tools/swift_migration/D.swift', 'func i(c: Int!) { } // SWIFT-MIGRATION-IUO: describes\n')
        self.r.write('submodules/E.swift', 'func i(c: Int!) { } // SWIFT-MIGRATION-IUO: not ours\n')
        self.r.write('sources/Stale.swift', '// SWIFT-MIGRATION-IUO: nothing below\nlet k = 1\nlet m = x!\n')
        self.r.write('sources/Untracked.swift', 'func i(c: Int!) { } // SWIFT-MIGRATION-IUO: untracked\n')
        self.r.commit('Code', 'sources/A.swift', 'ThirdParty/Other/B.swift', 'docs/swift-migration/C.swift',
                      'tools/swift_migration/D.swift', 'submodules/E.swift', 'sources/Stale.swift')
        code, out, err = self.r.run('--list-iuo')
        self.assertEqual(code, 0, err)
        self.assertIn('SWIFT-MIGRATION-IUO sites: 4\n'
                      'ThirdParty/Other/B.swift:1:14: elsewhere\n'
                      'sources/A.swift:2:14: header not annotated\n'
                      'sources/A.swift:2:23: header not annotated\n'
                      'sources/A.swift:3:14: second\n', out)
        self.assertIn('Markers that cover no implicitly unwrapped type: 1\nsources/Stale.swift:1: nothing below\n', out)
        code, rep, err = self.r.json('--list-iuo')
        self.assertEqual(code, 0, err)
        self.assertEqual(rep['sites'][0], {'path': 'ThirdParty/Other/B.swift', 'line': 1, 'column': 14,
                                           'marker_line': 1, 'reason': 'elsewhere'})
        self.assertEqual(rep['sites'][1]['marker_line'], 1)
        self.assertEqual(len(rep['sites']), 4)
        self.assertEqual(rep['unused_markers'], [{'path': 'sources/Stale.swift', 'line': 1, 'reason': 'nothing below'}])
        self.assertEqual(rep['files_read'], 3)

    def test_lexer_failure_is_an_error(self):
        # Files without the marker cannot hold a marked site and are not lexed.
        self.r.write('sources/A.swift', '// SWIFT-MIGRATION-IUO: x\nlet s = "abc\n')
        self.r.write('sources/B.swift', 'let s = "abc\n')
        self.r.commit('Code')
        code, out, err = self.r.run('--list-iuo')
        self.assertEqual(code, 2)
        self.assertIn('Errors (exit status 2): 1\n  sources/A.swift:2:9: lexer cannot handle the file: unterminated '
                      'string literal', out)

    def test_usage(self):
        self.r.commit('empty')
        self.assertEqual(self.r.run('--list-iuo', '--all-swift')[0], 2)
        self.assertEqual(self.r.run('--list-iuo', '--staged')[0], 2)
        self.assertEqual(self.r.run('--list-iuo', 'HEAD')[0], 2)


class AllSwiftReportsIuoTests(unittest.TestCase):
    def test_marked_sites_in_the_report(self):
        r = GitRepo()
        self.addCleanup(r.cleanup)
        r.write('sources/A.swift', 'func f(a: Int!) { }\nfunc g(a: Int!) { } // SWIFT-MIGRATION-IUO: why\n')
        r.commit('Code')
        code, rep, err = r.json('--all-swift')
        self.assertEqual(code, 1, err)
        self.assertEqual(finding_lines(rep), ['sources/A.swift:1:14: iuo-unmarked'])
        self.assertEqual(rep['counts']['iuo-unmarked'], 1)
        self.assertEqual(rep['marked_iuo_sites'], [{'path': 'sources/A.swift', 'line': 2, 'column': 14,
                                                    'marker_line': 2, 'reason': 'why'}])
        code, out, err = r.run('--all-swift')
        self.assertIn('\nMarked implicitly unwrapped types (the documented exemption for iuo-unmarked): 1\n'
                      '  sources/A.swift:2:14: why\n', out)


class IuoMarkerShadowTests(unittest.TestCase):
    def test_two_markers_on_one_line_list_the_unused_one(self):
        # A marker above and a trailing marker both cover line 2. The trailing one covers the site; the one above
        # ends up covering nothing and is listed as such.
        src = '// SWIFT-MIGRATION-IUO: above\nfunc f(a: Int!) { } // SWIFT-MIGRATION-IUO: trailing'
        findings, _, iuo_marked, unused = sl.lint_source_full('t.swift', src)
        self.assertEqual(findings, [])
        self.assertEqual([(m['line'], m['column'], m['reason']) for m in iuo_marked], [(2, 14, 'trailing')])
        self.assertEqual(unused, [{'path': 't.swift', 'line': 1, 'reason': 'above'}])

    def test_unused_markers_in_line_order(self):
        src = '// SWIFT-MIGRATION-IUO: a\nlet k = 1 // SWIFT-MIGRATION-IUO: b\n// SWIFT-MIGRATION-IUO: c\nlet m = 2'
        unused = sl.lint_source_full('t.swift', src)[3]
        self.assertEqual([(m['line'], m['reason']) for m in unused], [(1, 'a'), (2, 'b'), (3, 'c')])
        # The replaced marker (b, line 3) comes after an ordinary unused one (a, line 1).
        src = '// SWIFT-MIGRATION-IUO: a\nlet k = 1\n// SWIFT-MIGRATION-IUO: b\n' \
              'func f(x: Int!) { } // SWIFT-MIGRATION-IUO: c'
        findings, _, iuo_marked, unused = sl.lint_source_full('t.swift', src)
        self.assertEqual(findings, [])
        self.assertEqual([(m['line'], m['column'], m['reason']) for m in iuo_marked], [(4, 14, 'c')])
        self.assertEqual([(m['line'], m['reason']) for m in unused], [(1, 'a'), (3, 'b')])


# ---------------------------------------------------------------------------
# No file-scope var (decisions.md, 2026-11-20)

# Each fixture: (name, source, the lint's findings as (line, column, lint), (mode, globals)). The compiler check
# (FileScopeVarCompilerTests, run with SWIFT_LINTS_COMPILER_CHECK=1) compiles the fixture alone, defining DEBUG:
#   'library': as a library file (-parse-as-library); it type-checks, and -dump-ast has exactly `globals` var
#       declarations (not let) directly in the source file.
#   'main': as main.swift, where statements are legal at file scope; the same check.
#   'parse': as a library file that parses but does not type-check (a property wrapper on a global, which Swift
#       does not support yet); -dump-parse has exactly `globals` var declarations directly in the source file.
FILE_SCOPE_VAR_FIXTURES = [
    ('var', 'var g = 1', [(1, 1, 'file-scope-var')], ('library', 1)),
    ('private var', 'private var g = 1', [(1, 9, 'file-scope-var')], ('library', 1)),
    ('fileprivate var', 'fileprivate var g = 1', [(1, 13, 'file-scope-var')], ('library', 1)),
    ('nonisolated(unsafe) var', 'nonisolated(unsafe) var g = 1', [(1, 21, 'file-scope-var')], ('library', 1)),
    ('public private(set) var', 'public private(set) var g = 1', [(1, 21, 'file-scope-var')], ('library', 1)),
    ('@MainActor var', '@MainActor var g = 1', [(1, 1, 'stage-one-concurrency'), (1, 12, 'file-scope-var')],
     ('library', 1)),
    ('attribute with arguments', '@available(*, deprecated) var g = 1', [(1, 27, 'file-scope-var')], ('library', 1)),
    ('attributes on lines above', '@available(*, deprecated)\n@MainActor\nvar g = 1',
     [(2, 1, 'stage-one-concurrency'), (3, 1, 'file-scope-var')], ('library', 1)),
    ('property wrapper', '@propertyWrapper struct W { var wrappedValue: Int }\n@W var g = 1',
     [(2, 4, 'file-scope-var')], ('parse', 1)),
    ('several names: one finding', 'var a = 1, b = 2', [(1, 1, 'file-scope-var')], ('library', 2)),
    ('several names on several lines', 'var a = 1,\n    b = 2', [(1, 1, 'file-scope-var')], ('library', 2)),
    ('computed', 'var c: Int { return 1 }', [(1, 1, 'file-scope-var')], ('library', 1)),
    ('computed with accessors', 'var c: Int {\n    get { return 1 }\n    set { }\n}', [(1, 1, 'file-scope-var')],
     ('library', 1)),
    ('stored with an observer', 'var o = 1 { didSet { } }', [(1, 1, 'file-scope-var')], ('library', 1)),
    ('computed with the brace on the next line', 'var x: Int\n{\n    return 1\n}', [(1, 1, 'file-scope-var')],
     ('library', 1)),
    ('computed with its type on two lines', 'var m: [Int:\n    Int] {\n    return [:]\n}', [(1, 1, 'file-scope-var')],
     ('library', 1)),
    ('declared, then assigned, in main.swift',
     'var a: Int; if true { a = 1 } else { a = 2 }\nvar b: Int\nif true { b = 1 } else { b = 2 }\nprint(a, b)',
     [(1, 1, 'file-scope-var'), (2, 1, 'file-scope-var')], ('main', 2)),
    ('in a #if block', '#if DEBUG\nvar d = 1\n#else\nvar d = 2\n#endif',
     [(2, 1, 'file-scope-var'), (4, 1, 'file-scope-var')], ('library', 1)),
    ('after a type', 'class C { }\nvar g = 1', [(2, 1, 'file-scope-var')], ('library', 1)),
    ('after a function', 'func f() { }\nvar g = 1', [(2, 1, 'file-scope-var')], ('library', 1)),
    ('after a semicolon', 'let k = 1; var g = 2', [(1, 12, 'file-scope-var')], ('library', 1)),
    ('after a comment', '// note\nvar g = 1 /* x */', [(2, 1, 'file-scope-var')], ('library', 1)),
    ('named var in backticks', 'var `var` = 1', [(1, 1, 'file-scope-var')], ('library', 1)),
    ('implicitly unwrapped: both lints', 'var g: Int! = 1', [(1, 1, 'file-scope-var'), (1, 11, 'iuo-unmarked')],
     ('library', 1)),
    ('top-level code in main.swift', 'var x = 1\nx += 1', [(1, 1, 'file-scope-var')], ('main', 1)),
    ('after a statement in main.swift', 'print(1)\nvar x = 1', [(2, 1, 'file-scope-var')], ('main', 1)),
    ('modifier alone on the line above', 'fileprivate\nvar g = 1', [(2, 1, 'file-scope-var')], ('library', 1)),
    # A word that is also a modifier, or a call named like one, ending the line before is a member or a value,
    # not a modifier of the var.
    ('modifier words as members on the line before',
     'enum P { case required }\nlet defaultPriority = P.required\nvar counter = 0\n'
     'let firstThree = "abcdef".prefix(3)\nvar other = 1\nenum L { case `private` }\nlet logLevel = L.private\n'
     'var third = 2',
     [(3, 1, 'file-scope-var'), (5, 1, 'file-scope-var'), (8, 1, 'file-scope-var')], ('library', 3)),
    ('modifier words as members and values on the line before',
     'let a = [1, 2].lazy\nvar b = 1\nenum M { case optional }\nlet m = M.optional\nvar c = 2\n'
     'let dynamic = 1\nlet d = dynamic\nvar e = 3',
     [(2, 1, 'file-scope-var'), (5, 1, 'file-scope-var'), (8, 1, 'file-scope-var')], ('library', 3)),
    ('binding words as members on the line before',
     'enum K { case `case` }\nlet k = K.case\nvar f = 1\nstruct Q { var `for` = 1 }\nlet q = Q().for\nvar g = 2',
     [(3, 1, 'file-scope-var'), (6, 1, 'file-scope-var')], ('library', 2)),
    ('after a closing brace in main.swift', 'if true {\n}\nvar x = 1', [(3, 1, 'file-scope-var')], ('main', 1)),
    # Not reported.
    ('file-scope let', 'let k = 1\nprivate let m = 2', [], ('library', 0)),
    ('property of a class', 'class C { var x = 1 }', [], ('library', 0)),
    ('static property of a struct', 'struct S { static var s = 1 }', [], ('library', 0)),
    ('property in an extension', 'struct S { }\nextension S { var e: Int { return 1 } }', [], ('library', 0)),
    ('protocol requirement', 'protocol P { var r: Int { get } }', [], ('library', 0)),
    ('enum with a computed property', 'enum E { case a\n    var v: Int { return 1 } }', [], ('library', 0)),
    ('local in a function', 'func f() { var x = 1; x += 1 }', [], ('library', 0)),
    ('local in a closure', 'let c = { () -> Int in var z = 1; z += 1; return z }', [], ('library', 0)),
    ('local in an accessor', 'struct S { var p: Int { var t = 1; t += 1; return t } }', [], ('library', 0)),
    ('in a #if block in a type', 'class C {\n#if DEBUG\n    var d = 1\n#endif\n}', [], ('library', 0)),
    ('case pattern in a switch', 'func f(o: Int?) { switch o { case var .some(v): v += 1; _ = v; default: break } }',
     [], ('library', 0)),
    ('comments and strings', '// var x = 1\nlet s = "var y = 1"\n/* var z = 1 */\nlet t = """\nvar w\n"""', [],
     ('library', 0)),
    ('backticked identifier and label', 'let `var` = 1\nfunc f(`var`: Int) { }\nlet u: () = f(var: `var`)', [],
     ('library', 0)),
    ('member named var', 'struct S { var `var` = 1 }\nlet v = S().var', [], ('library', 0)),
    ('if var in main.swift', 'let o: Int? = 1\nif var y = o { y += 1 }', [], ('main', 0)),
    ('condition list over lines in main.swift', 'let o: Int? = 1\nif let a = o,\n   var b = Optional(a) { b += 1 }',
     [], ('main', 0)),
    ('if case var in main.swift', 'if case var y? = Optional(1) { y += 1 }', [], ('main', 0)),
    ('guard var in main.swift', 'import Foundation\nlet o: Int? = 1\nguard var y = o else { exit(1) }\ny += 1', [],
     ('main', 0)),
    ('for var in main.swift', 'for var i in 0..<2 { i += 1 }', [], ('main', 0)),
    ('for case var in main.swift', 'for case var i? in [Optional(1)] { i += 1 }', [], ('main', 0)),
    ('while var in main.swift', 'var n: Int? = 1\nwhile var m = n { m += 1; n = nil }',
     [(1, 1, 'file-scope-var')], ('main', 1)),
    ('binding words on the line before the var in main.swift',
     'import Foundation\nlet o: Int? = 1\nif\n    var y = o { y += 1 }\nguard\n    var z = o else { exit(1) }\n'
     'z += 1\nwhile\n    var w = Optional<Int>.none { w += 1 }\nfor\n    var i in 0..<2 { i += 1 }\nif case\n'
     '    var c? = o { c += 1 }\ndo { throw CancellationError() } catch\n    var e { e = CancellationError(); _ = e }',
     [], ('main', 0)),
    ('for await var in main.swift', 'let s = AsyncStream<Int> { $0.finish() }\nfor await var x in s { x += 1 }',
     [(2, 5, 'stage-one-concurrency')], ('main', 0)),
    ('a statement assigning a global named var in main.swift', 'var `var` = 1\n`var` = 2', [(1, 1, 'file-scope-var')],
     ('main', 1)),
    ('catch var in main.swift', 'do { throw CancellationError() } catch var e { e = CancellationError(); _ = e }', [],
     ('main', 0)),
]

FILE_SCOPE_VAR_MESSAGE = ('file-scope var declares a global variable; make it a static property of a type '
                          '(decisions.md, 2026-11-20)')
FILE_SCOPE_COMPUTED_VAR_MESSAGE = ('file-scope computed var is still a global; make it a static property of a type '
                                   '(decisions.md, 2026-11-20)')


class FileScopeVarTests(unittest.TestCase):
    def test_fixtures(self):
        for name, src, expected, _ in FILE_SCOPE_VAR_FIXTURES:
            self.assertEqual(lint(src), expected, name)

    def test_messages(self):
        findings, _ = sl.lint_source('t.swift', 'var g = 1\nvar o = 1 { didSet { } }\nvar c: Int { return 1 }\n'
                                                'var d: [Int: Int] {\n    return [:]\n}\n'
                                                'var t: Double = {\n    return 1\n}()\nvar x: Int\n{\n    return 1\n}\n'
                                                'var a: Int; if true { a = 1 } else { a = 2 }\n'
                                                'var b: Int\nif true { b = 1 } else { b = 2 }\n'
                                                'var m: [Int:\n    Int] {\n    return [:]\n}')
        self.assertEqual([(f.line, f.message) for f in findings], [
            (1, FILE_SCOPE_VAR_MESSAGE), (2, FILE_SCOPE_VAR_MESSAGE), (3, FILE_SCOPE_COMPUTED_VAR_MESSAGE),
            (4, FILE_SCOPE_COMPUTED_VAR_MESSAGE), (7, FILE_SCOPE_VAR_MESSAGE), (10, FILE_SCOPE_COMPUTED_VAR_MESSAGE),
            (14, FILE_SCOPE_VAR_MESSAGE), (15, FILE_SCOPE_VAR_MESSAGE), (17, FILE_SCOPE_COMPUTED_VAR_MESSAGE)])

    def test_empty_associated_value_list_does_not_leak_a_type_context(self):
        # Swift rejects case a() ("must have at least one associated value"); the force unwrap after it is still one.
        self.assertEqual(lint('enum E { case a() }\nlet v = x!'), [(2, 10, 'force-unwrap')])

    def test_no_marker_excuses_it(self):
        self.assertEqual(lint('// SWIFT-MIGRATION-IUO: x\nvar g: Int! = 1'), [(2, 1, 'file-scope-var')])
        self.assertEqual(lint('var g = 1 // SWIFT-MIGRATION-SHIM: x'), [(1, 1, 'file-scope-var')])

    def test_legend(self):
        self.assertIn('decisions.md 2026-11-20', sl.LINTS['file-scope-var'])
        self.assertIn('static property of a type', sl.LINTS['file-scope-var'])

    def test_file_scope_let_is_listed_as_not_checked(self):
        rows = [(r, w) for r, _, w in sl.NOT_CHECKED if 'file-scope let' in r]
        self.assertEqual(len(rows), 1)
        self.assertIn('to be confirmed with the owner', rows[0][1])

    def test_help_says_file_scope_let_is_not_reported(self):
        r = GitRepo()
        self.addCleanup(r.cleanup)
        flat = ' '.join(r.run('--help')[1].split())
        self.assertIn('A file-scope let is not reported until the owner confirms whether it is banned too', flat)

    def test_all_swift_counts_it(self):
        r = GitRepo()
        self.addCleanup(r.cleanup)
        r.write('sources/A.swift', 'private var g = 1\nlet k = 2\n')
        r.commit('Code')
        code, rep, err = r.json('--all-swift')
        self.assertEqual(code, 1, err)
        self.assertEqual(finding_lines(rep), ['sources/A.swift:1:9: file-scope-var'])
        self.assertEqual(rep['counts']['file-scope-var'], 1)


def global_var_count(dump):
    """The var declarations (not let) directly in the source file of a -dump-parse or -dump-ast dump."""
    return sum(1 for line in dump.split('\n')
               if line.startswith('  (var_decl ') and not re.search(r' let(?:[ )]|$)', line))


@unittest.skipUnless(os.environ.get('SWIFT_LINTS_COMPILER_CHECK') == '1',
                     'set SWIFT_LINTS_COMPILER_CHECK=1 to check the fixtures against xcrun swiftc')
class FileScopeVarCompilerTests(unittest.TestCase):
    """Checks every fixture of the file-scope var lint against the Swift compiler, one compiler process at a time."""

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='swift_lints_globals_')
        self.addCleanup(shutil.rmtree, self.dir, True)

    def swiftc(self, src, filename, *args):
        path = os.path.join(self.dir, filename)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src + '\n')
        p = subprocess.run(['xcrun', 'swiftc', '-D', 'DEBUG'] + list(args) + [path], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=120)
        return p.returncode, p.stdout.decode('utf-8', 'replace') + p.stderr.decode('utf-8', 'replace')

    def test_global_var_count_reads_the_dump(self):
        code, dump = self.swiftc('var a = 1\nlet b = 2\nvar c: Int { 1 }\nstruct S { var d = 1 }', 'f.swift',
                                 '-parse-as-library', '-dump-ast')
        self.assertEqual(code, 0, dump)
        self.assertEqual(global_var_count(dump), 2, dump)

    def test_fixtures_against_the_compiler(self):
        for name, src, _, (mode, globals_) in FILE_SCOPE_VAR_FIXTURES:
            with self.subTest(name=name):
                if mode == 'main':
                    filename, args = 'main.swift', []
                else:
                    filename, args = 'f.swift', ['-parse-as-library']
                code, out = self.swiftc(src, filename, *(args + ['-parse']))
                self.assertEqual(code, 0, (name, out))
                if mode == 'parse':
                    code, out = self.swiftc(src, filename, *(args + ['-typecheck']))
                    self.assertNotEqual(code, 0, (name, 'type-checks'))
                    _, dump = self.swiftc(src, filename, *(args + ['-dump-parse']))
                else:
                    code, out = self.swiftc(src, filename, *(args + ['-typecheck']))
                    self.assertEqual(code, 0, (name, out))
                    code, dump = self.swiftc(src, filename, *(args + ['-dump-ast']))
                    self.assertEqual(code, 0, (name, dump))
                self.assertEqual(global_var_count(dump), globals_, (name, dump))


@unittest.skipUnless(os.environ.get('SWIFT_LINTS_COMPILER_CHECK') == '1',
                     'set SWIFT_LINTS_COMPILER_CHECK=1 to check the fixtures against xcrun swiftc')
class IuoCompilerTests(unittest.TestCase):
    """Checks every fixture of the implicitly unwrapped type lint against the Swift compiler, one compiler process
    at a time. Slow (several compiler runs per fixture), so it runs only on request."""

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='swift_lints_iuo_')
        self.addCleanup(shutil.rmtree, self.dir, True)

    def swiftc(self, src, *args):
        path = os.path.join(self.dir, 'f.swift')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src + '\n')
        p = subprocess.run(['xcrun', 'swiftc'] + list(args) + [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=120)
        return p.returncode, p.stdout.decode('utf-8', 'replace') + p.stderr.decode('utf-8', 'replace')

    def test_fixtures_against_the_compiler(self):
        for name, src, _, (kind, detail) in IUO_FIXTURES:
            with self.subTest(name=name):
                self.check_fixture(name, src, kind, detail)

    def check_fixture(self, name, src, kind, detail):
        code, out = self.swiftc(src, '-parse')
        self.assertEqual(code, 0, (name, out))
        _, dump = self.swiftc(src, '-dump-parse')
        if kind == 'expr':
            self.assertEqual(count_outside_processed_init(dump, 'force_value_expr'), detail, (name, dump))
            self.assertNotIn('type_implicitly_unwrapped_optional', dump, name)
            return
        self.assertNotIn('force_value_expr', dump, name)
        if kind == 'iuo-type':
            code, out = self.swiftc(src, '-typecheck')
            self.assertEqual(code, 0, (name, out))
            code, printed = self.swiftc(src, '-print-ast')
            self.assertEqual(code, 0, (name, printed))
            lines = src.split('\n')
            for line, col in detail:
                self.assertEqual(lines[line - 1][col - 1], '!', (name, line, col))
                changed = list(lines)
                changed[line - 1] = changed[line - 1][:col - 1] + '?' + changed[line - 1][col:]
                code, out = self.swiftc('\n'.join(changed), '-print-ast')
                self.assertEqual(code, 0, (name, out))
                self.assertEqual(out.count('!'), printed.count('!') - 1, (name, line, col, printed, out))
        elif kind == 'iuo':
            code, out = self.swiftc(src, '-typecheck')
            self.assertEqual(code, 0, (name, out))
            lines = src.split('\n')
            for line, col in detail:
                self.assertEqual(lines[line - 1][col - 1], '!', (name, line, col))
                changed = list(lines)
                changed[line - 1] = changed[line - 1][:col - 1] + '?' + changed[line - 1][col:]
                code, out = self.swiftc('\n'.join(changed), '-typecheck')
                self.assertNotEqual(code, 0, (name, line, col, 'still type-checks with "?"'))
        else:
            code, out = self.swiftc(src, '-typecheck')
            self.assertNotEqual(code, 0, name)
            for line, col in detail:
                self.assertIn("f.swift:%d:%d: error: using '!' is not allowed here" % (line, col), out, name)


if __name__ == '__main__':
    unittest.main()
