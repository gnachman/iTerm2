#!/usr/bin/env python3
"""Lints for migration Swift (docs/swift-migration/phase0.md, section 6).

Part of the Objective-C to Swift migration. Applies the token-level lints
that the closing checks run (lifecycle.md section 5) to migration files only, and
says for every rule in the process documents that it does not enforce why it
does not.

WHICH FILES ARE MIGRATION FILES

phase0.md section 6 applies the lints to "files created by port commits
(tracked by a marker comment or by the trailer history, to be decided in the
pilot)". No document defines a marker comment for this, so this tool uses
the trailer history, read narrowly:

  A Swift file is a migration file in four cases. The staged change counts
  as a commit.

  1. Added by a port commit. A commit reachable from the inspected revision
     whose message carries a Swift-Port trailer with kind=port, as git reads
     it and as inventory.py parses it (parse_trailers), added the path: it did
     not exist before the commit and exists after it. This is read with git's
     rename and copy detection off, so a port that git would pair with the
     deleted Foo.m, or with a deleted Swift file that is not a migration file
     (FooExt.swift folded into Foo.swift), still adds Foo.swift.
  2. Renamed from a migration file. When git's rename detection pairs a
     migration file with a new Swift path, in any commit, the rename is
     followed: the destination inherits the status. Only then; a rename whose
     source is not a migration file is an addition of its destination, decided
     by case 1, 3 or 4.
  3. Carried over. When a commit that is not a port commit, whatever its kind,
     modifies, renames or deletes at least one migration file, each Swift
     file it adds (that no rename follows) is a migration file: the code of
     the files it touches may continue there (an extraction into a new file,
     a split that keeps the old name, a split that git reads as a rename of
     one part). The summary names the touched files. This also makes an
     unrelated new Swift file added in the same commit a migration file; that
     over-linting is accepted.
  4. Re-added. A path that was ever a migration file stays one: a commit that
     re-adds a Swift file at that path after a deletion (a revert followed by
     a re-application whose message lost the trailer) adds a migration file.

  A migration file deleted by a commit that adds no Swift file is gone; the
  --staged and REV summaries list it.

  Ported lines. A port commit that modifies an existing Swift file that is not
  a migration file (a port that adds methods to an existing extension,
  lifecycle.md section 2) does not make it one, since its older code was not
  ported. With --staged and a kind=port trailer in --message, and with REV
  when REV is a port commit, each such file is linted and only the findings on
  lines the change added or changed are reported (the added line ranges of
  the new side of git diff -U0, with rename and copy detection off, for the
  staged change or for REV against its first parent; a hunk that only
  deletes lines after new-side line N touches lines N and N + 1, a deletion
  touching the lines on either side of it). For sync-pairing and for the
  unsafe marker on the line above, a finding belongs to the change when
  either of its two lines does. These are printed under "Ported lines in
  files that are not migration files" with the ranges linted, and they count
  toward the exit status. The same applies to a change that is not a port
  commit but modifies, renames or deletes at least one migration file, since
  code moved out of a migration file may land in an existing file: every
  Swift file that is not a migration file and that the change modifies is
  linted by lines, each with the reason (the migration files the change
  touches). This also lints unrelated edits made in the same commit, which is
  accepted. Tree mode has no change to diff: it lists each such file with the
  commits that modified it, under a heading saying that ported lines in these
  files are linted only when their commit is linted (with REV or --staged)
  and are not linted in tree mode; the list does not affect the exit status.

  History. A port commit that is a merge is reported as a trailer problem and
  makes the exit status 2: git log --name-status shows no files for a merge,
  so its files are not identified, and the process requires linear history.
  When the repository is shallow or has replace refs, every mode prints a
  warning that port commits beyond the visible history cannot be seen; tree
  mode then exits 2 unless --allow-incomplete-history is given.

Usage (from anywhere inside the repository, or with --repo):

  swift_lints.py [--json] [--allow-incomplete-history]
                                        The working tree: every tracked Swift
                                        file that is a migration file at HEAD.
  swift_lints.py [--json] --staged [--message FILE | --not-a-port]
                                        The staged change: the migration files
                                        it adds, modifies or renames, as they
                                        are in the index. A file the change
                                        adds is a migration file when FILE,
                                        the pending commit message, has a
                                        Swift-Port trailer with kind=port, by
                                        the carry-over rule (case 3) when the
                                        change modifies, renames or deletes a
                                        migration file, or when its path was
                                        a migration file (case 4). When the
                                        change adds Swift files that none of
                                        these decides, or modifies Swift
                                        files that are not migration files
                                        and it touches no migration file,
                                        either FILE with a usable trailer
                                        (or none) or --not-a-port is
                                        required (exit 2): whether they hold
                                        ported code depends on the message.
                                        With a port trailer, or when the
                                        change touches a migration file,
                                        also the changed lines of the other
                                        Swift files it modifies.
  swift_lints.py [--json] REV           One commit: the migration files (as of
                                        REV) that REV adds, modifies or renames
                                        relative to its first parent, as they
                                        are in REV; when REV is a port commit
                                        or touches a migration file, also the
                                        changed lines of the other Swift
                                        files it modifies.
  swift_lints.py [--json] --all-swift   Every lint on every tracked Swift file
                                        in the migration's scope (README.md
                                        section 2), whether or not it is a
                                        migration file. A survey, not a gate.
  swift_lints.py [--json] --list-iuo    Every implicitly unwrapped type marked
                                        with "// SWIFT-MIGRATION-IUO: <reason>"
                                        (path:line:column: reason), and every
                                        such marker that covers none, in the
                                        tracked Swift files of the working
                                        tree outside submodules/ and the two
                                        directories that describe the markers.
                                        Not a gate: exit status 0, or 2 for a
                                        file that cannot be read or lexed.

Every run also applies one repository-wide check, frozen-reference-target
(large-code.md section 2.3), to every tracked file in the inspected tree that
contains the frozen-reference marker, whatever its language, except under
docs/swift-migration/ and tools/swift_migration/, which describe the marker.

Each finding is printed as path:line:column: lint-id: message. Columns count
Unicode code points from 1. The legend names the document and section each
lint enforces. Uses of unsafe pointer APIs that carry the required marker are
listed under "Marked unsafe uses", and implicitly unwrapped types that carry
theirs under "Marked implicitly unwrapped types"; the documents give no other
way to suppress a lint, so this tool has none.

The SWIFT-MIGRATION-IUO marker (translation-rules.md section 7; decisions.md,
2026-11-20) covers one line: alone on its line it covers the next line, and at
the end of a line of code it covers that line. It covers every implicitly
unwrapped type on that line. When two markers cover one line (one alone on the
line above it and one at its end), the one at its end covers it and the other
covers nothing; --list-iuo lists it as such. The lint iuo-unmarked reports a
"!" in a type position that no marker covers and that is not the declared type
of a property: a var or let directly in the body of a class, struct, enum,
extension, protocol or actor (in a function-local type too). Type positions
are a parameter's type (func, init, subscript, closure expression, with or
without attributes before its name), an enum case's associated value, a result
type after "->", the annotation of a var or let (local and file-scope
variables need the marker), and init!. A "!" nested in a type (a function
type's parameter or result, an array, tuple or generic argument) and the type
of an as or is cast are reported too, even in a property's type: Swift does
not allow an implicitly unwrapped type there, so such code does not compile.
An implicitly unwrapped @IBOutlet is reported by iuo-outlet instead.

The lint file-scope-var (decisions.md, 2026-11-20) reports every var declared
at file scope, stored or computed: a var keyword outside every bracket (no
enclosing type body, function, closure, accessor, parenthesis or bracket; a
#if block is not a bracket) that starts a declaration. It starts one when it,
or the run of attributes (with their arguments) and modifiers before it, or a
shorter run ending at it, begins a statement: nothing precedes it, or a ';' does, or the preceding token
is on an earlier line and is neither ',' nor one of if, guard, while, for, case
and catch used as a keyword (a binding in a condition list or pattern, legal at
file scope only in the top-level code of main.swift, is a local; K.case is a
member). On the same line any other token
(await in for await var) means it is not a declaration, since Swift requires a
';' or a new line between statements. One finding per declaration, at the var
keyword. The finding says "computed" when the first name's annotation is
followed by '{' (on its line, or first on the next) before any '=' or ';'. A
var in backticks is a name. There is no marker for it. A file-scope var with an
implicitly unwrapped type gets both findings; a file-scope let is not reported
until the owner confirms whether it is banned too.

Decided but not implemented here (owner-queue.md Q20, answered 2026-11-20):
the unsafe marker on &x passed to a pointer parameter is to be enforced by
type-aware lints on the Swift AST, a later unit, and until then is a review
item; the rule for which files are migration files stays provisional until
the pilot. A "Not checked by this tool" section
names every rule the documents ask a lint (or a check of Swift text) to
enforce that this tool does not, with the reason.

Exit status: 0 no findings; 1 findings (including findings on ported
lines); 2 usage or environment error, including a file that cannot be read,
is not UTF-8, or that the lexer cannot handle (each is reported; none is
skipped silently), a port commit that is a merge, and in tree mode an
incomplete history without --allow-incomplete-history. Python 3 standard
library only. Nothing is written to disk.
"""

import argparse
import bisect
import json
import os
import re
import subprocess
import sys
from collections import OrderedDict, namedtuple

sys.dont_write_bytecode = True
_TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
if _TOOL_DIR not in sys.path:
    sys.path.insert(0, _TOOL_DIR)

import inventory as inv  # noqa: E402  (read-only: trailer parsing and pbxproj parsing)


# ---------------------------------------------------------------------------
# Constants

# README.md section 2. Swift files under these roots are surveyed by --all-swift.
SCOPE_ROOTS = ('sources', 'ThirdParty/PSMTabBarControl', 'SignedArchive', 'pidinfo',
               'iTerm2SandboxedWorker', 'ShellLauncher', 'ColorPicker', 'SearchableComboListView',
               'BetterFontPicker')
# Paths that describe the markers rather than use them (as in inventory.py).
MARKER_EXCLUDED_PREFIXES = ('docs/swift-migration/', 'tools/swift_migration/')
# --list-iuo reads the files the inventory's marker counts read (inventory.py MARKER_EXCLUDED_PATHS), Swift only.
LIST_IUO_EXCLUDED_PREFIXES = ('submodules/',) + MARKER_EXCLUDED_PREFIXES
FROZEN_MARKER = 'SWIFT-MIGRATION-FROZEN-REFERENCE'
MARKER_PREFIX = 'SWIFT-MIGRATION-'
TEST_PRODUCT_TYPES = ('com.apple.product-type.bundle.unit-test',
                      'com.apple.product-type.bundle.ui-testing')

MIGRATION_RULE = ('A Swift file is a migration file when a commit reachable from the inspected revision, '
                  'whose message carries a Swift-Port trailer with kind=port (as git reads it and as '
                  'inventory.py parses it), added it: the path did not exist before that commit and exists '
                  'after it, whatever git would pair it with (a deleted Foo.m, or a deleted Swift file that is '
                  'not a migration file). A rename is followed, so that the destination inherits migration '
                  'status, only when its source is a migration file. Carry-over: when a commit that is not a '
                  'port commit, whatever its kind (or the staged change), modifies, renames or deletes at least '
                  'one migration file, each Swift file it adds that no rename follows is a migration file, since '
                  'the code of the files it touches may continue there (an extraction into a new file, a split). '
                  'This also makes an unrelated new Swift file added in the same commit as an edit to a '
                  'migration file a migration file; that over-linting is accepted. A path that was ever a '
                  'migration file stays one: a commit that re-adds a Swift file at the same path after a '
                  'deletion (a revert followed by a re-application whose message lost the trailer) adds a '
                  'migration file. A migration file deleted by a commit that adds no Swift file is gone. Ported '
                  'lines in files that are not migration files: a port commit that modifies an existing Swift '
                  'file that is not a migration file does not make it one; with --staged and a kind=port trailer '
                  'in --message, and with REV when REV is a port commit, that file is linted and only findings on '
                  'lines the change added or changed are reported (for sync-pairing and the unsafe marker on the '
                  'line above, when either of the two lines was; a deletion touches the lines on either side of '
                  'it), under their own heading, and they count toward the exit status. The same applies to a '
                  'change that is not a port commit but modifies, renames or deletes at least one migration file '
                  '(code moved out of a migration file may land in an existing file): every Swift file that is not '
                  'a migration file and that the change modifies is linted by lines, with the migration files it '
                  'touches as the reason; this also lints unrelated edits made in the same commit, which is '
                  'accepted. Tree mode lists such files with their commits, and they are not linted in tree mode. '
                  'With --staged, when the change adds or modifies Swift files whose status these rules do not '
                  'decide, --message FILE with a usable trailer (or none) or --not-a-port is required (exit status '
                  '2 otherwise), since whether they hold ported code depends on the pending message. A port commit that is a merge is an error (exit status 2): its files are not '
                  'identified. In a shallow repository, or one with replace refs, port commits beyond the '
                  'visible history cannot be seen: every mode warns, and tree mode exits 2 unless '
                  '--allow-incomplete-history is given. Source: phase0.md section 6 ("files created by port '
                  'commits"), read narrowly: no marker comment for this is defined in the documents.')

# Decisions that this tool does not implement (owner-queue.md Q20, answered 2026-11-20). Printed by --help; each is
# also a row of NOT_CHECKED.
DECIDED_NOT_IMPLEMENTED = (
    'Decided but not implemented here: the unsafe marker on &x passed to a pointer parameter is to be enforced by '
    'type-aware lints on the Swift AST, a later unit, and until then is a review item (owner-queue.md Q20 item 6); the '
    'rule for which files are migration files stays provisional until the pilot, and this tool applies the trailer '
    'history meanwhile (owner-queue.md Q20 item 3). To find every implicitly unwrapped type marked with SWIFT-MIGRATION-IUO, run '
    'swift_lints.py --list-iuo. A file-scope let is not reported until the owner confirms whether it is banned too '
    '(decisions.md, 2026-11-20); a file-scope var is reported by file-scope-var.')

LINTS = OrderedDict([
    ('unsafe-pointer-unmarked',
     'phase0.md section 6; translation-rules.md section 8: an unsafe pointer API needs '
     '"// SWIFT-MIGRATION-UNSAFE(hot): <reason>" or "// SWIFT-MIGRATION-SHIM: <reason>" on the line above'),
    ('force-unwrap', 'phase0.md section 6: no "!" force unwrap'),
    ('forced-cast', 'phase0.md section 6: no "as!"'),
    ('forced-try', 'phase0.md section 6: no "try!"'),
    ('unowned', 'phase0.md section 6; lifetimes.md; decisions.md 2026-11-19: no "unowned" or "unowned(unsafe)"'),
    ('trap-call', 'phase0.md section 6; assertions.md section 1; CLAUDE.md; decisions.md 2026-11-20: no fatalError, '
                  'assert, precondition, assertionFailure or preconditionFailure; use the it_ versions '
                  '(it_fatalError for preconditionFailure; it_assert(false, ...) or a beta assertion for '
                  'assertionFailure, which does nothing in release builds)'),
    ('stage-one-concurrency', 'phase0.md section 6; concurrency.md section 8: no async, await, Task, actor, '
                              '@MainActor or MainActor.assumeIsolated in a stage-one file'),
    ('sync-enter-argument', 'concurrency.md section 2: the lock passed to objc_sync_enter is evaluated once '
                            'into a constant; no forced unwrap or other expression'),
    ('sync-pairing', 'phase0.md section 6; concurrency.md section 2: objc_sync_enter(x) is followed, on the '
                     'next line, by "defer { objc_sync_exit(x) }" on the same constant'),
    ('lock-stored-property', 'phase0.md section 6; concurrency.md section 5: os_unfair_lock or '
                             'pthread_mutex_t must not be a Swift stored property'),
    ('iuo-outlet', 'hidden-callers.md section 4: outlets are optionals, not implicitly unwrapped'),
    ('iuo-unmarked', 'translation-rules.md section 7; decisions.md 2026-11-20: an implicitly unwrapped type outside a '
                     'property (a parameter, a result, a local or file-scope variable, init!) needs '
                     '"// SWIFT-MIGRATION-IUO: <reason>" on the line above or at the end of the line'),
    ('file-scope-var', 'decisions.md 2026-11-20; translation-rules.md section 5: no var at file scope, stored or '
                       'computed (a global variable); a static or global variable from Objective-C becomes a static '
                       'property of a type. A file-scope let is not reported'),
    ('marker-format', 'translation-rules.md sections 7 and 8; objc-state.md sections 1 and 2; large-code.md section '
                      '2.3: a SWIFT-MIGRATION- marker (SHIM, UNSAFE(hot), IUO, FROZEN-REFERENCE) is a line comment in its '
                      'documented form with its explanation; SWIFT-MIGRATION-IUO is "// SWIFT-MIGRATION-IUO: <reason>"'),
    ('frozen-reference-target', 'large-code.md section 2.3: a file containing '
                                'SWIFT-MIGRATION-FROZEN-REFERENCE is a member of no target other than a '
                                'test target'),
])

NOT_CHECKED = [
    ('Integer initializer applied to a non-literal (Int(x), Int32(x), UInt(x), ...)',
     'phase0.md section 6; translation-rules.md section 1',
     'needs the compiler: whether the argument is an integer or floating-point value (banned) or a String, '
     'Substring or NSNumber (another initializer) is a question of types'),
    ('Plain +, -, *, unary - or << on a fixed-width integer without a helper or "// bounded-by-type:"',
     'phase0.md section 6; translation-rules.md section 1',
     'needs the compiler: the operand types decide whether an operator is integer arithmetic'),
    ('Calling an imported API whose signature takes a pointer (for example &x to an out-parameter) '
     'needs the unsafe marker', 'translation-rules.md section 8; owner-queue.md Q20 item 6',
     'needs the compiler: "&x" passed to an inout parameter and to a pointer parameter look the same. Decided '
     '(owner, 2026-11-20): it is to be enforced by type-aware lints on the Swift AST, a later unit, since the '
     'AST says whether &x becomes a pointer or an inout; until then it is a review item. Uses that name an '
     'unsafe pointer API are checked'),
    ('Use of an implicitly unwrapped value from Objective-C without binding it first',
     'phase0.md section 6; nullability.md section 4',
     'needs the compiler: which declarations are imported as implicitly unwrapped is in the importer'),
    ('An optional or implicitly unwrapped identifier passed to objc_sync_enter',
     'phase0.md section 6; concurrency.md section 2',
     'needs the compiler: the identifier\'s type. Forced unwraps and arguments other than one identifier '
     'are checked (sync-enter-argument)'),
    ('The lock constant is a let of non-optional type AnyObject', 'concurrency.md section 2',
     'needs resolved declarations'),
    ('os_unfair_lock or pthread_mutex_t stored property whose type is neither written in its annotation '
     'nor its initializer call', 'phase0.md section 6; concurrency.md section 5',
     'needs the compiler (type inference); annotated and directly initialized properties are checked'),
    ('URL, Date, Data, IndexSet, Calendar or Locale where the Objective-C used the NS class',
     'phase0.md section 6; translation-rules.md section 4',
     'needs the Objective-C original and the imported signatures: Objective-C APIs taking NSURL and the '
     'others are imported with the Swift types'),
    ('NSNumber as? Int and similar bridging casts', 'phase0.md section 6; translation-rules.md section 4',
     'needs the compiler: whether the operand is or holds an NSNumber is a question of types'),
    ('== between Strings that came from NSString on data that can be non-ASCII',
     'phase0.md section 6; translation-rules.md section 4',
     'needs types and knowledge of the data; the document allows it to be a review checklist item'),
    ('New uses of the runtime APIs of hidden-callers.md section 3 outside the registered sites',
     'hidden-callers.md section 2',
     'a separate Phase 0 item (orchestration.md section 9) over all languages; the registry does not exist yet'),
    ('New macros of the classified kinds', 'hidden-callers.md section 6',
     'a separate Phase 0 item; Objective-C macros, not Swift'),
    ('A type of the file\'s own named Task, used as Task { }, Task(...), Task.x, Task<...> or as an annotation',
     'phase0.md section 6; concurrency.md section 8',
     'needs resolved names: such a use looks the same as the standard Task and is reported. A Task being '
     'declared, and other uses ([Task?]), are not reported; neither are async and await outside keyword '
     'position (an argument label, a declared name, a member, a variable read)'),
    ('Stage-one versus stage-two files', 'concurrency.md section 8; README.md section 4',
     'no document says how a file is known to be in stage two, so every migration file is treated as '
     'stage one'),
    ('@objc(OriginalName), @objc selectors, and @objc dynamic for swizzled, observed or key-value coded '
     'members', 'translation-rules.md section 7; hidden-callers.md section 5',
     'needs the Objective-C original and the census; the runtime snapshot comparison (phase0.md section 9) '
     'checks the result'),
    ('Captured locals that are var and were not __block go in a capture list', 'concurrency.md section 6',
     'needs data flow and the Objective-C original'),
    ('@unknown default in a switch over an imported NS_ENUM', 'translation-rules.md section 5',
     'needs the compiler (which also warns)'),
    ('Division and modulo by a non-constant get a zero check', 'translation-rules.md section 1',
     'needs types'),
    ('No assertion in a per-character, per-cell or per-token loop; it_betaAssert versus it_assert',
     'assertions.md sections 1 to 3', 'a review question, not a text property'),
    ('Strong outlets stay strong; outlets keep their names', 'hidden-callers.md section 4',
     'needs the Objective-C original; the binding tests (phase0.md section 3) check names'),
    ('A nonnull parameter with Objective-C callers is optional in Swift and guarded with it_fatalError',
     'nullability.md section 6', 'needs the header and the census'),
    ('Capture semantics and weak back-pointers are ported exactly', 'lifetimes.md',
     'needs the Objective-C original'),
    ('A file-scope let constant', 'decisions.md 2026-11-20',
     'whether a file-scope let is banned too is to be confirmed with the owner; until then only a file-scope var is '
     'reported (file-scope-var)'),
    ('An implicitly unwrapped property other than an outlet is listed in the commit message',
     'translation-rules.md section 7',
     'a property of the commit message; such declarations are allowed and not reported as force unwraps'),
    ('A SWIFT-MIGRATION-IUO site is removed once it is no longer needed; its reason is a real one',
     'translation-rules.md section 7; decisions.md 2026-11-20',
     'a question of meaning; the lint requires a non-empty reason, and --list-iuo lists every marked site and '
     'every marker that covers no implicitly unwrapped type'),
    ('The rule for which files are migration files (a marker comment or the trailer history)',
     'phase0.md section 6; owner-queue.md Q20 item 3',
     'provisional until the pilot (owner, 2026-11-20); this tool applies the trailer history as described under '
     '"Migration files", and that logic is not a settled rule'),
    ('A SWIFT-MIGRATION-UNSAFE(hot) marker names the measurement that justifies it',
     'README.md section 2; translation-rules.md section 8',
     'a question of meaning; the lint requires a non-empty reason'),
    ('A port of a function over about 150 lines carries an Oversize-Port trailer', 'large-code.md section 2',
     'a commit and review requirement, not a property of a Swift file'),
    ('Methods called off the main thread in AppKit subclasses are nonisolated', 'concurrency.md section 8',
     'needs the dossier\'s thread table'),
    ('Atomic properties, lazy var, queue affinity and run loop modes are ported faithfully',
     'concurrency.md sections 3, 5 and 7', 'needs the dossier and the Objective-C original'),
    ('Raw ivar accessors are named ivar_foo and never interchanged with self.foo', 'objc-state.md section 2',
     'needs the dossier\'s ivar table'),
]

# The standard library's unsafe pointer and buffer types and the functions that make or reinterpret raw
# memory. withExtendedLifetime is not one of them.
UNSAFE_NAMES = frozenset([
    'UnsafePointer', 'UnsafeMutablePointer', 'UnsafeRawPointer', 'UnsafeMutableRawPointer',
    'UnsafeBufferPointer', 'UnsafeMutableBufferPointer', 'UnsafeRawBufferPointer',
    'UnsafeMutableRawBufferPointer', 'AutoreleasingUnsafeMutablePointer', 'CVaListPointer', 'OpaquePointer',
    'Unmanaged', 'assumingMemoryBound', 'bindMemory', 'withMemoryRebound', 'unsafeBitCast', 'unsafeDowncast',
    'withVaList', 'getVaList', 'unsafeUninitializedCapacity'])
UNSAFE_PREFIX = 'withUnsafe'
# Members of the pointer types that have no other common meaning, so that a pointer whose type is inferred
# (a closure parameter: stop.pointee = true) is still found. Only after a dot.
UNSAFE_MEMBERS = frozenset(['pointee', 'baseAddress'])
TRAP_CALLS = frozenset(['fatalError', 'assert', 'precondition', 'assertionFailure', 'preconditionFailure'])
# What each banned call is replaced with (assertions.md section 1; decisions.md 2026-11-20).
TRAP_REPLACEMENTS = {
    'fatalError': 'use the it_ version',
    'assert': 'use the it_ version',
    'precondition': 'use the it_ version',
    'preconditionFailure': 'use it_fatalError',
    'assertionFailure': 'use it_assert(false, ...) or a beta assertion (it_betaAssert); assertionFailure does nothing '
                        'in release builds, where the Objective-C assert it replaces stays enabled',
}
LOCK_TYPES = frozenset(['os_unfair_lock', 'os_unfair_lock_s', 'pthread_mutex_t'])
LOCK_QUALIFIERS = frozenset(['Darwin', 'os', 'Glibc'])
TYPE_DECL_KEYWORDS = frozenset(['class', 'struct', 'enum', 'extension', 'protocol'])
DECL_MODIFIERS = frozenset([
    'weak', 'unowned', 'private', 'fileprivate', 'internal', 'public', 'open', 'final', 'lazy', 'dynamic',
    'override', 'static', 'class', 'required', 'convenience', 'nonisolated', 'mutating', 'nonmutating',
    'indirect', 'optional', 'prefix', 'postfix', 'infix', 'package'])
NOT_A_TYPE_NAME_AFTER_CLASS = DECL_MODIFIERS | frozenset(['func', 'var', 'let', 'subscript', 'init', 'deinit',
                                                          'typealias'])
CLOSURE_SIGNATURE_FOLLOWERS = frozenset(['in', '->', 'throws', 'rethrows', 'async'])
# A word after one of these is a name being declared, not a keyword.
DECLARING_WORDS = frozenset(['let', 'var', 'func', 'case'])
# Words after which a var binds a name in a condition list or a pattern (if var, for case var, catch var), not a
# declaration.
BINDING_WORDS = frozenset(['if', 'guard', 'while', 'for', 'case', 'catch'])
FILE_SCOPE_VAR_MESSAGE = ('file-scope var declares a global variable; make it a static property of a type '
                          '(decisions.md, 2026-11-20)')
FILE_SCOPE_COMPUTED_VAR_MESSAGE = ('file-scope computed var is still a global; make it a static property of a type '
                                   '(decisions.md, 2026-11-20)')
# Declarations of a type, after which a word is the type's name.
TYPE_NAMING_WORDS = frozenset(['class', 'struct', 'enum', 'protocol', 'typealias', 'actor', 'associatedtype'])

_MARKER_FORMS = (
    ('SWIFT-MIGRATION-SHIM', re.compile(r'// SWIFT-MIGRATION-SHIM: (\S.*?)\s*')),
    ('SWIFT-MIGRATION-UNSAFE(hot)', re.compile(r'// SWIFT-MIGRATION-UNSAFE\(hot\): (\S.*?)\s*')),
    ('SWIFT-MIGRATION-FROZEN-REFERENCE',
     re.compile(r'// SWIFT-MIGRATION-FROZEN-REFERENCE: (\S+ [^\s:]+:\S.*?)\s*')),
    ('SWIFT-MIGRATION-IUO', re.compile(r'// SWIFT-MIGRATION-IUO: (\S.*?)\s*')),
)
_UNSAFE_MARKER_KINDS = ('SWIFT-MIGRATION-SHIM', 'SWIFT-MIGRATION-UNSAFE(hot)')
IUO_MARKER = 'SWIFT-MIGRATION-IUO'


class UsageError(Exception):
    pass


class EnvironmentProblem(Exception):
    pass


# ---------------------------------------------------------------------------
# Lexer

Token = namedtuple('Token', 'kind text start end')
# kinds: line_comment, block_comment, string (one segment of a string literal), interp_open,
# interp_close, regex, ident, kw (as!, as?, try!, try?), number, op, punct, attr (@name), pound (#name)


class LexError(Exception):
    def __init__(self, offset, message):
        Exception.__init__(self, message)
        self.offset = offset
        self.message = message


_OP_CHARS = frozenset('/=-+!*%<>&|^~?')
_LEFT_UNBINDING = frozenset(' \t\r\n\f\v([{,;:')
_IDENT_RE = re.compile(r'[A-Za-z_\u0080-\U0010FFFF][A-Za-z0-9_\u0080-\U0010FFFF]*')
_DOLLAR_RE = re.compile(r'\$[A-Za-z0-9_]+')
_BACKTICK_RE = re.compile(r'`[^`\n]+`')
_NUMBER_RE = re.compile(r'0[xX][0-9a-fA-F_]*(?:\.[0-9a-fA-F_]+)?(?:[pP][+-]?[0-9_]+)?'
                        r'|0[bo][0-9_]+'
                        r'|[0-9][0-9_]*(?:\.[0-9][0-9_]*)?(?:[eE][+-]?[0-9_]+)?')
_WS_RE = re.compile(r'[ \t\r\n\f\v]+')
_PLAIN_STRING_BODY = re.compile(r'[^"\\\n]+')


class Lexed(object):
    """The tokens of one file, its line starts, and the number of string literals."""

    def __init__(self, text, tokens, literal_count, comment_ends):
        self.text = text
        self.tokens = tokens
        self.literal_count = literal_count
        self.comment_ends = comment_ends
        self.line_starts = [0]
        for m in re.finditer('\n', text):
            self.line_starts.append(m.end())

    def line_col(self, offset):
        i = bisect.bisect_right(self.line_starts, offset) - 1
        return i + 1, offset - self.line_starts[i] + 1

    def line(self, offset):
        return bisect.bisect_right(self.line_starts, offset)


class _Lexer(object):
    def __init__(self, text):
        self.text = text
        self.n = len(text)
        self.tokens = []
        self.literal_count = 0
        self.comment_ends = set()

    def left_bound(self, i):
        if i == 0:
            return False
        if i in self.comment_ends:
            return False
        return self.text[i - 1] not in _LEFT_UNBINDING

    def code(self, i, in_interpolation):
        """Lexes code from i. In an interpolation, stops at the ')' that closes it and returns its index."""
        text, n, toks = self.text, self.n, self.tokens
        depth = 0
        while i < n:
            c = text[i]
            if c in ' \t\r\n\f\v':
                i = _WS_RE.match(text, i).end()
                continue
            if c == '/' and text.startswith('//', i):
                j = text.find('\n', i)
                j = n if j < 0 else j
                toks.append(Token('line_comment', text[i:j], i, j))
                self.comment_ends.add(j)
                i = j
                continue
            if c == '/' and text.startswith('/*', i):
                j = self.block_comment(i)
                toks.append(Token('block_comment', text[i:j], i, j))
                self.comment_ends.add(j)
                i = j
                continue
            if c == '"' or c == '#':
                j = i
                while j < n and text[j] == '#':
                    j += 1
                hashes = j - i
                if j < n and text[j] == '"':
                    i = self.string(i, hashes)
                    continue
                if hashes and j < n and text[j] == '/':
                    i = self.regex(i, hashes)
                    continue
                if c == '#':
                    m = _IDENT_RE.match(text, i + 1)
                    if m:
                        toks.append(Token('pound', text[i:m.end()], i, m.end()))
                        i = m.end()
                        continue
            if c == '@':
                m = _IDENT_RE.match(text, i + 1)
                if m:
                    toks.append(Token('attr', text[i:m.end()], i, m.end()))
                    i = m.end()
                    continue
            if c == '`':
                m = _BACKTICK_RE.match(text, i)
                if m:
                    toks.append(Token('ident', m.group(0)[1:-1], i, m.end()))
                    i = m.end()
                    continue
            if c == '$':
                m = _DOLLAR_RE.match(text, i)
                if m:
                    toks.append(Token('ident', m.group(0), i, m.end()))
                    i = m.end()
                    continue
            if '0' <= c <= '9':
                m = _NUMBER_RE.match(text, i)
                toks.append(Token('number', m.group(0), i, m.end()))
                i = m.end()
                continue
            m = _IDENT_RE.match(text, i)
            if m:
                j = m.end()
                word = m.group(0)
                if word in ('as', 'try') and j < n and text[j] in '!?':
                    toks.append(Token('kw', text[i:j + 1], i, j + 1))
                    i = j + 1
                    continue
                toks.append(Token('ident', word, i, j))
                i = j
                continue
            if c in _OP_CHARS:
                if c in '!?' and self.left_bound(i):
                    toks.append(Token('op', c, i, i + 1))
                    i += 1
                    continue
                j = i
                while j < n and text[j] in _OP_CHARS:
                    if text.startswith('//', j) or text.startswith('/*', j):
                        break
                    j += 1
                toks.append(Token('op', text[i:j], i, j))
                i = j
                continue
            if c == '.':
                if i + 1 < n and text[i + 1] == '.':
                    j = i
                    while j < n and (text[j] == '.' or text[j] in _OP_CHARS):
                        j += 1
                    toks.append(Token('op', text[i:j], i, j))
                    i = j
                    continue
                toks.append(Token('punct', '.', i, i + 1))
                i += 1
                continue
            if in_interpolation:
                if c == '(':
                    depth += 1
                elif c == ')':
                    if depth == 0:
                        return i
                    depth -= 1
            toks.append(Token('punct', c, i, i + 1))
            i += 1
        if in_interpolation:
            raise LexError(n, 'unterminated string interpolation')
        return i

    def block_comment(self, i):
        text = self.text
        depth = 0
        j = i
        while True:
            k1 = text.find('/*', j)
            k2 = text.find('*/', j)
            if k2 < 0:
                raise LexError(i, 'unterminated block comment')
            if 0 <= k1 < k2:
                depth += 1
                j = k1 + 2
            else:
                depth -= 1
                j = k2 + 2
                if depth == 0:
                    return j

    def string(self, i, hashes):
        """Lexes a string literal starting at i (at its first '#' or quote). Returns the end."""
        text, n = self.text, self.n
        q = i + hashes
        multiline = text.startswith('"""', q)
        body = q + (3 if multiline else 1)
        closer = ('"""' if multiline else '"') + '#' * hashes
        escape = '\\' + '#' * hashes
        self.literal_count += 1
        seg_start = i
        j = body
        while True:
            if j >= n:
                raise LexError(i, 'unterminated string literal')
            c = text[j]
            if c == '\n' and not multiline:
                raise LexError(i, 'unterminated string literal')
            if c == '"' and text.startswith(closer, j):
                end = j + len(closer)
                self.tokens.append(Token('string', text[seg_start:end], seg_start, end))
                return end
            if c == '\\' and text.startswith(escape, j):
                k = j + len(escape)
                if k < n and text[k] == '(':
                    self.tokens.append(Token('string', text[seg_start:j], seg_start, j))
                    self.tokens.append(Token('interp_open', text[j:k + 1], j, k + 1))
                    close = self.code(k + 1, True)
                    self.tokens.append(Token('interp_close', ')', close, close + 1))
                    seg_start = close + 1
                    j = close + 1
                    continue
                if k < n and (text[k] != '\n' or multiline):
                    j = k + 1
                    continue
                j = k
                continue
            if not multiline and hashes == 0:
                m = _PLAIN_STRING_BODY.match(text, j)
                if m:
                    j = m.end()
                    continue
            j += 1

    def regex(self, i, hashes):
        """Lexes an extended regex literal #/.../# starting at i."""
        text, n = self.text, self.n
        closer = '/' + '#' * hashes
        j = i + hashes + 1
        while j < n:
            c = text[j]
            if c == '\\':
                j += 2
                continue
            if c == '/' and text.startswith(closer, j):
                end = j + len(closer)
                self.tokens.append(Token('regex', text[i:end], i, end))
                return end
            j += 1
        raise LexError(i, 'unterminated regex literal')


def lex(text):
    """Returns a Lexed for Swift source text. Raises LexError for text the lexer cannot handle."""
    lx = _Lexer(text)
    lx.code(1 if text.startswith('\ufeff') else 0, False)  # a byte-order mark is not part of the code
    return Lexed(text, lx.tokens, lx.literal_count, lx.comment_ends)


_MASKED_KINDS = frozenset(['line_comment', 'block_comment', 'string', 'interp_open', 'interp_close', 'regex'])


def mask(lexed):
    """The text with comments, string and regex literals (but not interpolated code) replaced by spaces.

    Newlines are kept, so length and line numbers are unchanged.
    """
    text = lexed.text
    out = []
    pos = 0
    for t in lexed.tokens:
        if t.kind in _MASKED_KINDS:
            out.append(text[pos:t.start])
            out.append(re.sub(r'[^\n]', ' ', text[t.start:t.end]))
            pos = t.end
    out.append(text[pos:])
    return ''.join(out)


def bracket_balance_error(masked):
    """Returns (offset, message) for the first bracket problem in masked text, or None."""
    pairs = {')': '(', ']': '[', '}': '{'}
    stack = []
    for m in re.finditer(r'[()\[\]{}]', masked):
        c = m.group(0)
        if c in '([{':
            stack.append((c, m.start()))
        else:
            if not stack or stack[-1][0] != pairs[c]:
                return m.start(), 'unbalanced %r' % c
            stack.pop()
    if stack:
        return stack[-1][1], 'unclosed %r' % stack[-1][0]
    return None


# ---------------------------------------------------------------------------
# Lints

Finding = namedtuple('Finding', 'path line col lint message')


def marker_form(comment_token):
    """Returns (kind, explanation) if the comment is a marker in a documented form, else None."""
    if comment_token.kind != 'line_comment':
        return None
    for kind, rx in _MARKER_FORMS:
        m = rx.fullmatch(comment_token.text)
        if m:
            return kind, m.group(1)
    return None


class _FileLinter(object):
    def __init__(self, path, lexed):
        self.path = path
        self.lx = lexed
        self.toks = [t for t in lexed.tokens if t.kind not in ('line_comment', 'block_comment')]
        self.findings = []
        self.marked = []
        self.lines = [lexed.line(t.start) for t in self.toks]
        # Implicitly unwrapped types outside properties: (offset of the "!",) found by lint_structure and
        # matched with SWIFT-MIGRATION-IUO markers by lint_iuo_sites.
        self.iuo_sites = []
        self.iuo_marked = []
        self.iuo_unused = []

    def add(self, tok, lint, message):
        line, col = self.lx.line_col(tok.start)
        self.findings.append(Finding(self.path, line, col, lint, message))

    def text(self, k):
        return self.toks[k].text if 0 <= k < len(self.toks) else None

    def kind(self, k):
        return self.toks[k].kind if 0 <= k < len(self.toks) else None

    def is_ident(self, k, word=None):
        if not (0 <= k < len(self.toks)) or self.toks[k].kind != 'ident':
            return False
        return word is None or self.toks[k].text == word

    def is_punct(self, k, ch):
        return 0 <= k < len(self.toks) and self.toks[k].kind == 'punct' and self.toks[k].text == ch

    def after_dot(self, k):
        return self.is_punct(k - 1, '.')

    def same_line(self, a, b):
        return 0 <= a < len(self.toks) and 0 <= b < len(self.toks) and self.lines[a] == self.lines[b]

    def matching_close(self, k):
        """Index of the token that closes the bracket at k (brackets balance: lint_source checked)."""
        depth = 0
        for j in range(k, len(self.toks)):
            t = self.toks[j]
            key = t.text if t.kind == 'punct' else t.kind
            if key in ('(', '[', '{', 'interp_open'):
                depth += 1
            elif key in (')', ']', '}', 'interp_close'):
                depth -= 1
                if depth == 0:
                    return j
        it_never = 'brackets were checked by lint_source'
        raise AssertionError(it_never)

    def run(self):
        self.lint_markers()
        self.lint_tokens()
        self.lint_structure()
        self.lint_iuo_sites()
        self.lint_sync()
        return self.findings, self.marked

    # -- markers -----------------------------------------------------------

    def lint_markers(self):
        self.unsafe_marker_lines = {}
        # {line covered: (marker line, reason)}. A SWIFT-MIGRATION-IUO marker alone on its line covers the next
        # line; one at the end of a line of code covers that line only. Either way it covers one line.
        self.iuo_marker_lines = OrderedDict()
        # Markers replaced by a later marker covering the same line (one above and one trailing): (marker line,
        # reason). They cover nothing.
        self.iuo_shadowed = []
        code_starts = [t.start for t in self.toks]
        for t in self.lx.tokens:
            if t.kind not in ('line_comment', 'block_comment') or MARKER_PREFIX not in t.text:
                continue
            form = marker_form(t)
            if form is None:
                line, col = self.lx.line_col(t.start + t.text.index(MARKER_PREFIX))
                self.findings.append(Finding(
                    self.path, line, col, 'marker-format',
                    'marker not in a documented form: "// SWIFT-MIGRATION-SHIM: <reason>", '
                    '"// SWIFT-MIGRATION-UNSAFE(hot): <reason>", "// SWIFT-MIGRATION-IUO: <reason>" or '
                    '"// SWIFT-MIGRATION-FROZEN-REFERENCE: <unit> <original file>:<function>", as a line comment, '
                    'with its explanation'))
            elif form[0] in _UNSAFE_MARKER_KINDS:
                self.unsafe_marker_lines[self.lx.line(t.start)] = form
            elif form[0] == IUO_MARKER:
                line = self.lx.line(t.start)
                i = bisect.bisect_left(code_starts, t.start) - 1
                trailing = i >= 0 and self.lx.line(self.toks[i].end - 1) == line
                covered = line if trailing else line + 1
                if covered in self.iuo_marker_lines:
                    self.iuo_shadowed.append(self.iuo_marker_lines[covered])
                self.iuo_marker_lines[covered] = (line, form[1])

    # -- single tokens -----------------------------------------------------

    def lint_tokens(self):
        toks = self.toks
        for k, t in enumerate(toks):
            if t.kind == 'kw':
                if t.text == 'as!':
                    self.add(t, 'forced-cast', '"as!" forced cast')
                elif t.text == 'try!':
                    self.add(t, 'forced-try', '"try!" forced try')
                continue
            if t.kind == 'attr':
                if t.text == '@MainActor':
                    self.add(t, 'stage-one-concurrency', '@MainActor in a stage-one file')
                continue
            if t.kind != 'ident':
                continue
            w = t.text
            if w in UNSAFE_NAMES or w.startswith(UNSAFE_PREFIX) or (w in UNSAFE_MEMBERS and self.after_dot(k)):
                line = self.lines[k]
                form = self.unsafe_marker_lines.get(line - 1)
                if form is None:
                    self.add(t, 'unsafe-pointer-unmarked',
                             '%s without "// SWIFT-MIGRATION-UNSAFE(hot): <reason>" or '
                             '"// SWIFT-MIGRATION-SHIM: <reason>" on the line above' % w)
                else:
                    ln, col = self.lx.line_col(t.start)
                    self.marked.append(OrderedDict([('path', self.path), ('line', ln), ('column', col),
                                                    ('api', w), ('marker', form[0]), ('reason', form[1])]))
                continue
            if self.after_dot(k):
                if w in TRAP_CALLS and self.is_ident(k - 2, 'Swift') and self.is_punct(k + 1, '('):
                    self.add(t, 'trap-call', 'Swift.%s; %s' % (w, TRAP_REPLACEMENTS[w]))
                elif w == 'assumeIsolated' and self.is_ident(k - 2, 'MainActor'):
                    self.add(toks[k - 2], 'stage-one-concurrency', 'MainActor.assumeIsolated in a stage-one file')
                continue
            if w in TRAP_CALLS:
                if self.is_punct(k + 1, '(') and not self.is_ident(k - 1, 'func'):
                    self.add(t, 'trap-call', '%s; %s' % (w, TRAP_REPLACEMENTS[w]))
            elif w == 'unowned':
                if self.same_line(k, k + 1) and (
                        self.kind(k + 1) == 'ident' or
                        (self.is_punct(k + 1, '(') and self.text(k + 2) in ('safe', 'unsafe') and
                         self.is_punct(k + 3, ')'))):
                    self.add(t, 'unowned', 'unowned reference; use weak (lifetimes.md)')
            elif w == 'await':
                if self.await_is_keyword(k):
                    self.add(t, 'stage-one-concurrency', 'await in a stage-one file')
            elif w == 'async':
                if self.async_is_keyword(k):
                    self.add(t, 'stage-one-concurrency', 'async in a stage-one file')
            elif w == 'Task':
                if self.task_is_concurrency(k):
                    self.add(t, 'stage-one-concurrency', 'Task in a stage-one file')
            elif w == 'actor':
                if self.kind(k + 1) == 'ident' and self.same_line(k, k + 1) and \
                        self.text(k + 1) not in ('in', 'as', 'is') and \
                        self.text(k - 1) not in DECLARING_WORDS and self.text(k - 1) != 'for':
                    self.add(t, 'stage-one-concurrency', 'actor in a stage-one file')

    def await_is_keyword(self, k):
        """Whether the await at k (not after a dot) is the keyword: not a label, a declared name or an operand."""
        if self.text(k - 1) in DECLARING_WORDS:
            return False
        nxt = self.toks[k + 1] if k + 1 < len(self.toks) else None
        # Not '.': the compiler reads "await .some(x)", and even "await.foo", as the keyword.
        if nxt is None or nxt.kind == 'interp_close' or (nxt.kind == 'punct' and nxt.text in ':,)]};'):
            return False
        return not (nxt.kind == 'op' and nxt.text == '=')

    def async_is_keyword(self, k):
        """Whether the async at k (not after a dot) is the effect or async let: it follows a parameter clause or
        get, or precedes let, throws, rethrows, -> or in. Elsewhere it is a variable, label or member; right
        after a closure's '{' (or its capture list) and before in or ->, it is the closure's parameter."""
        if self.text(k - 1) in DECLARING_WORDS or self.text(k + 1) in ('(', ':', '='):
            return False
        if self.closure_start(k - 1) and (self.is_ident(k + 1, 'in') or self.text(k + 1) == '->'):
            return False
        if self.is_punct(k - 1, ')') or self.is_ident(k - 1, 'get'):
            return True
        return self.text(k + 1) in ('let', 'throws', 'rethrows', '->', 'in')

    def task_is_concurrency(self, k):
        """Whether the Task at k (not after a dot) is used as the standard Task could be: followed by {, (, . or <,
        or written as the type in an annotation or a return type. A type declared with this name is not."""
        if self.text(k - 1) in TYPE_NAMING_WORDS or self.text(k - 1) in DECLARING_WORDS:
            return False
        nxt = self.text(k + 1)
        if nxt is not None and (nxt in ('{', '(', '.') or nxt.startswith('<')):
            return True
        return self.is_punct(k - 1, ':') or self.text(k - 1) == '->'

    # -- structure: force unwraps, outlets, stored lock properties -------------

    def lint_structure(self):
        toks = self.toks
        n = len(toks)
        # stack entries: [opener, kind] where opener is '(', '[', '{' or 'interp' and kind is
        # 'type' (a type body), 'params' (a parameter clause), 'assoc' (an enum case's associated values) or
        # 'other'.
        stack = []
        pending_type = False
        pending_params = False
        # The active type annotation context: dict(depth, angle, outlet, prop, arrow). prop: it annotates a var or
        # let directly in a type body (a property). arrow: a "->" was seen at its depth, so what follows is a
        # function type's result and not the declared type itself.
        ctx = None
        # The var or let declaration being read, so that "var x: Int!, y: Int!" annotates y too: dict(depth,
        # outlet). It ends at a ';' or a new line (unless the line before ended with ','), at its own depth.
        decl = None
        # The enum case declaration being read (case a(Int!), b(x: String!)), as dict(depth), so that the '(' after
        # each case name opens its associated values. It ends as decl does.
        case_decl = None
        for k in range(n):
            t = toks[k]
            key = t.text if t.kind == 'punct' else t.kind
            if decl is not None and (len(stack) < decl['depth'] or len(stack) == decl['depth'] and (
                    key == ';' or self.lines[k] != self.lines[k - 1] and not self.is_punct(k - 1, ','))):
                decl = None
            if case_decl is not None and (len(stack) < case_decl['depth'] or len(stack) == case_decl['depth'] and (
                    key == ';' or self.lines[k] != self.lines[k - 1] and not self.is_punct(k - 1, ','))):
                case_decl = None
            # Leave a type context at a new line, or at a terminator, at its own depth. A closing bracket
            # ends it even inside angle brackets, since generic arguments cannot hold an unmatched one.
            if ctx is not None and len(stack) == ctx['depth']:
                if key in (')', ']', '}', 'interp_close') or ctx['angle'] == 0 and (
                        self.lines[k] != self.lines[k - 1] or key in (',', ';', '{') or
                        (t.kind == 'op' and t.text == '=') or (t.kind == 'ident' and t.text == 'in')):
                    ctx = None
            # Each associated value starts a type context, at its label if it has one (a label and its ':' hold no
            # operator, so they change nothing). Not at the ')' of an empty list, which Swift rejects, so that the
            # context cannot outlive its parentheses.
            if ctx is None and stack and stack[-1][1] == 'assoc' and key != ')' and \
                    (self.is_punct(k - 1, '(') or self.is_punct(k - 1, ',')):
                ctx = {'depth': len(stack), 'angle': 0, 'outlet': False, 'prop': False, 'arrow': False}

            if t.kind == 'op':
                if ctx is not None:
                    # Inside a type annotation no operator is a force unwrap; "!" there is an implicitly
                    # unwrapped type. Angle brackets are counted so that a comma in generic arguments does
                    # not end the annotation; in a type every "<" and ">" is one, except in "->".
                    at_depth = len(stack) == ctx['depth']
                    if at_depth and t.text == '->':
                        # A function type at the top of the annotation; inside generic arguments it is not.
                        ctx['arrow'] = ctx['arrow'] or ctx['angle'] == 0
                    elif at_depth:
                        ctx['angle'] = max(0, ctx['angle'] + t.text.count('<') - t.text.count('>'))
                        if t.text.endswith('!') and ctx['outlet'] and ctx['angle'] == 0:
                            self.add(t, 'iuo-outlet', '@IBOutlet declared implicitly unwrapped; declare it '
                                                      'optional and use optional chaining')
                    if '!' in t.text:
                        # The declared type of a property (or outlet) itself may be implicitly unwrapped
                        # (translation-rules.md section 7). Any other "!" in a type needs the marker.
                        own_type = at_depth and ctx['angle'] == 0 and not ctx['arrow']
                        if not (own_type and (ctx['prop'] or ctx['outlet'])):
                            self.iuo_sites.append(t.start + t.text.index('!'))
                    continue
                if t.text == '->':
                    ctx = {'depth': len(stack), 'angle': 0, 'outlet': False, 'prop': False, 'arrow': False}
                elif t.text == '!' and self.left_bound_tok(k):
                    if self.is_ident(k - 1, 'init') and (self.is_punct(k + 1, '(') or self.text(k + 1) == '<'):
                        # init!( declares an implicitly unwrapped failable initializer
                        self.iuo_sites.append(t.start)
                        continue
                    if self.cast_type_bang(k):
                        self.iuo_sites.append(t.start)
                        continue
                    self.add(t, 'force-unwrap', '"!" force unwrap')
                continue

            if t.kind == 'ident':
                w = t.text
                if self.after_dot(k):
                    continue
                if w == 'var' and not stack and self.lx.text[t.start] != '`' and self.var_starts_declaration(k):
                    self.add(t, 'file-scope-var', FILE_SCOPE_COMPUTED_VAR_MESSAGE if self.is_computed_var(k)
                             else FILE_SCOPE_VAR_MESSAGE)
                if w == 'case' and stack and stack[-1] == ['{', 'type']:
                    case_decl = {'depth': len(stack)}
                if w in TYPE_DECL_KEYWORDS and not (w == 'class' and (
                        self.kind(k + 1) != 'ident' or self.text(k + 1) in NOT_A_TYPE_NAME_AFTER_CLASS)):
                    pending_type = True
                elif w == 'actor' and self.kind(k + 1) == 'ident' and self.same_line(k, k + 1):
                    pending_type = True
                elif w == 'func':
                    pending_params = True
                elif w in ('init', 'subscript') and (self.is_punct(k + 1, '(') or self.text(k + 1) in ('?', '!', '<')):
                    pending_params = True
                elif w in ('var', 'let') and not self.is_ident(k - 1, 'case'):
                    in_type_body = bool(stack) and stack[-1][1] == 'type' and stack[-1][0] == '{'
                    if in_type_body:
                        self.check_lock_property(k)
                    decl = {'depth': len(stack), 'outlet': self.has_outlet_attribute(k), 'prop': in_type_body}
                    if self.kind(k + 1) == 'ident' and self.is_punct(k + 2, ':') and ctx is None:
                        ctx = {'depth': len(stack), 'angle': 0, 'outlet': decl['outlet'], 'prop': in_type_body,
                               'arrow': False}
                continue

            if t.kind == 'punct':
                # A parameter's ':' follows its name, and the name follows '(' or ',' directly or after a label;
                # the ':' of a ternary in a default value does not.
                if key == ':' and stack and stack[-1][1] == 'params' and stack[-1][0] == '(' and \
                        ctx is None and self.parameter_name_colon(k):
                    ctx = {'depth': len(stack), 'angle': 0, 'outlet': False, 'prop': False, 'arrow': False}
                elif key == ':' and decl is not None and len(stack) == decl['depth'] and ctx is None and \
                        self.kind(k - 1) == 'ident' and self.is_punct(k - 2, ','):
                    ctx = {'depth': len(stack), 'angle': 0, 'outlet': decl['outlet'], 'prop': decl['prop'],
                           'arrow': False}
                elif key == '(':
                    kind = 'params' if pending_params else 'other'
                    pending_params = False
                    if kind == 'other' and self.closure_start(k - 1) and \
                            self.text(self.matching_close(k) + 1) in CLOSURE_SIGNATURE_FOLLOWERS:
                        kind = 'params'
                    elif kind == 'other' and case_decl is not None and len(stack) == case_decl['depth'] and \
                            self.kind(k - 1) == 'ident' and (self.is_ident(k - 2, 'case') or self.is_punct(k - 2, ',')):
                        kind = 'assoc'
                    stack.append(['(', kind])
                elif key == '[':
                    stack.append(['[', 'other'])
                elif key == '{':
                    stack.append(['{', 'type' if pending_type else 'other'])
                    pending_type = False
                    pending_params = False
                elif key in (')', ']', '}'):
                    if stack:
                        stack.pop()
                continue
            if t.kind == 'interp_open':
                stack.append(['interp', 'other'])
            elif t.kind == 'interp_close':
                if stack:
                    stack.pop()

    def matching_open(self, k):
        """Index of the '(' that opens the ')' at k (brackets balance: lint_source checked)."""
        depth = 0
        for j in range(k, -1, -1):
            if self.is_punct(j, ')'):
                depth += 1
            elif self.is_punct(j, '('):
                depth -= 1
                if depth == 0:
                    return j
        it_never = 'brackets were checked by lint_source'
        raise AssertionError(it_never)

    def skip_attributes(self, j, modifiers):
        """From token j backwards, skips attributes (with their arguments) and, when modifiers is true, declaration
        modifiers (with theirs: private(set), nonisolated(unsafe)). Returns the index of the token before them."""
        while j >= 0:
            t = self.toks[j]
            if t.kind == 'attr' or modifiers and t.kind == 'ident' and t.text in DECL_MODIFIERS:
                j -= 1
                continue
            if self.is_punct(j, ')'):
                o = self.matching_open(j)
                if self.kind(o - 1) == 'attr' or modifiers and self.text(o - 1) in DECL_MODIFIERS:
                    j = o - 1
                    continue
            break
        return j

    def parameter_name_colon(self, k):
        """Whether the ':' at k, in a parameter clause, follows a parameter's name: one or two
        names (label and name), after any attributes (@W, @Wrapper(arg: 1)), after the '(' or ','. The ':' of a
        ternary in a default value does not."""
        j = k - 1
        if not self.is_ident(j):
            return False
        j -= 1
        if self.is_ident(j):
            j -= 1
        j = self.skip_attributes(j, False)
        return self.is_punct(j, '(') or self.is_punct(j, ',')

    def var_starts_declaration(self, k):
        """Whether the var at k (outside every bracket) starts a declaration. The run of attributes (with their
        arguments) and modifiers (with theirs: private(set), nonisolated(unsafe)) before it is read backwards. The var
        starts a declaration when the run, or a shorter run that ends at the var, or the var itself, begins a
        statement (statement_start). So a word that is also a modifier ending the line before (P.required, [1].lazy,
        "x".prefix(3), a value named dynamic) does not hide the var: the var itself begins a statement. (Excluding a
        modifier word after a '.' from the run would change nothing, since the var is always a candidate.)"""
        starts = [k]
        j = k - 1
        while j >= 0:
            t = self.toks[j]
            if t.kind == 'attr' or t.kind == 'ident' and t.text in DECL_MODIFIERS:
                starts.append(j)
                j -= 1
                continue
            if self.is_punct(j, ')'):
                o = self.matching_open(j)
                if self.kind(o - 1) == 'attr' or self.kind(o - 1) == 'ident' and self.text(o - 1) in DECL_MODIFIERS:
                    starts.append(o - 1)
                    j = o - 2
                    continue
            break
        return any(self.statement_start(i) for i in starts)

    def statement_start(self, i):
        """Whether token i begins a statement: nothing precedes it, or ';' does, or a token on an earlier line that
        is neither ',' nor a word after which var binds a name in a condition or pattern (if var, guard var, for case
        var, catch var), unless that word is a member (K.case). Swift requires a ';' or a new line between
        statements, so on the same line any other token (await in for await var) means it does not."""
        p = i - 1
        if p < 0 or self.is_punct(p, ';'):
            return True
        if self.is_punct(p, ',') or self.is_ident(p) and self.text(p) in BINDING_WORDS and not self.after_dot(p):
            return False
        return self.lines[p] != self.lines[i]

    def is_computed_var(self, k):
        """Whether the var declaration at k declares a computed variable: its first name's annotation is followed
        by '{', on the same line or first on the next (as the compiler reads it), before any '=' or ';'. A stored
        variable with observers has an initializer at file scope, so its '=' comes first. A new line that does not
        start with '{' ends the declaration (var a: Int, then a statement, in main.swift)."""
        depth = 0
        for j in range(k + 1, len(self.toks)):
            t = self.toks[j]
            key = t.text if t.kind == 'punct' else t.kind
            if depth == 0 and (key == ';' or (t.kind == 'op' and t.text == '=') or
                               self.lines[j] != self.lines[j - 1] and key != '{'):
                return False
            if key == '{' and depth == 0:
                return True
            if key in ('(', '[', '{', 'interp_open'):
                depth += 1
            elif key in (')', ']', '}', 'interp_close'):
                depth -= 1
        return False

    def cast_type_bang(self, k):
        """Whether the "!" at k ends the type of an as or is cast (x as Foo!, x is A.B!): an implicitly unwrapped
        type, which Swift does not allow there, and not a force unwrap."""
        j = k - 1
        if not self.is_ident(j):
            return False
        while self.is_punct(j - 1, '.') and self.is_ident(j - 2):
            j -= 2
        return (self.is_ident(j - 1, 'as') or self.is_ident(j - 1, 'is')) and not self.after_dot(j - 1)

    def lint_iuo_sites(self):
        """Matches the implicitly unwrapped types found by lint_structure with SWIFT-MIGRATION-IUO markers."""
        used = set()
        for offset in self.iuo_sites:
            line, col = self.lx.line_col(offset)
            cover = self.iuo_marker_lines.get(line)
            if cover is None:
                self.findings.append(Finding(
                    self.path, line, col, 'iuo-unmarked',
                    'implicitly unwrapped type outside a property without "// SWIFT-MIGRATION-IUO: <reason>" on '
                    'the line above or at the end of the line'))
                continue
            used.add(line)
            self.iuo_marked.append(OrderedDict([('path', self.path), ('line', line), ('column', col),
                                                ('marker_line', cover[0]), ('reason', cover[1])]))
        unused = list(self.iuo_shadowed)
        unused.extend(cover for covered, cover in self.iuo_marker_lines.items() if covered not in used)
        for marker_line, reason in sorted(unused):
            self.iuo_unused.append(OrderedDict([('path', self.path), ('line', marker_line), ('reason', reason)]))

    def closure_start(self, k):
        """Whether token k is the '{' that opens a closure, or the ']' of a capture list just after one."""
        if self.is_punct(k, '{'):
            return True
        if not self.is_punct(k, ']'):
            return False
        depth = 0
        for j in range(k, -1, -1):
            if self.is_punct(j, ']'):
                depth += 1
            elif self.is_punct(j, '['):
                depth -= 1
                if depth == 0:
                    return self.is_punct(j - 1, '{')
        return False

    def left_bound_tok(self, k):
        """Whether the operator token at k is bound to what precedes it (no space or comment between)."""
        t = self.toks[k]
        i = t.start
        if i == 0 or i in self.lx.comment_ends:
            return False
        return self.lx.text[i - 1] not in _LEFT_UNBINDING

    def has_outlet_attribute(self, k):
        """Whether the declaration whose var/let is at k carries @IBOutlet among its attributes and modifiers."""
        j = k - 1
        while j >= 0:
            t = self.toks[j]
            if t.kind == 'attr':
                if t.text == '@IBOutlet':
                    return True
                j -= 1
                continue
            if t.kind == 'ident' and t.text in DECL_MODIFIERS:
                j -= 1
                continue
            if self.is_punct(j, ')'):
                # private(set), @objc(name), weak(...)
                depth = 0
                while j >= 0:
                    if self.is_punct(j, ')'):
                        depth += 1
                    elif self.is_punct(j, '('):
                        depth -= 1
                        if depth == 0:
                            break
                    j -= 1
                j -= 1
                continue
            break
        return False

    def check_lock_property(self, k):
        """k is a var/let directly in a type body. Reports a stored property of a lock struct type."""
        toks = self.toks
        n = len(toks)
        if self.kind(k + 1) != 'ident':
            return
        j = k + 2
        decl_line = self.lines[k]
        type_tokens = []
        init_tokens = []
        if self.is_punct(j, ':'):
            j += 1
            while j < n and self.lines[j] == decl_line and not (toks[j].kind == 'op' and toks[j].text == '=') \
                    and not (toks[j].kind == 'punct' and toks[j].text in ('{', ';', ',', '}')):
                type_tokens.append(toks[j])
                j += 1
        if j < n and toks[j].kind == 'op' and toks[j].text == '=':
            j += 1
            while j < n and self.lines[j] == decl_line:
                init_tokens.append(toks[j])
                j += 1
        elif self.is_punct(j, '{') and self.text(j + 1) not in ('willSet', 'didSet'):
            return  # a computed property

        def unqualified(names):
            return names[2:] if len(names) > 2 and names[0] in LOCK_QUALIFIERS and names[1] == '.' else names

        names = [t.text for t in type_tokens]
        while names and names[-1] in ('?', '!'):
            names.pop()
        names = unqualified(names)
        init = unqualified([t.text for t in init_tokens])
        lock = None
        if len(names) == 1 and names[0] in LOCK_TYPES:
            lock = names[0]
        elif init[:1] and init[0] in LOCK_TYPES and (init[1:2] == ['('] or init[1:3] == ['.', 'init']):
            lock = init[0]
        if lock:
            self.add(toks[k + 1], 'lock-stored-property',
                     '%s as a stored property; use OSAllocatedUnfairLock or keep the lock in Objective-C' % lock)

    # -- objc_sync_enter and objc_sync_exit ----------------------------------

    def lint_sync(self):
        toks = self.toks
        paired_exits = set()
        for k, t in enumerate(toks):
            if t.kind != 'ident' or t.text != 'objc_sync_enter' or not self.is_punct(k + 1, '('):
                continue
            close = self.matching_close(k + 1)
            arg = toks[k + 2:close]
            if not (len(arg) == 1 and arg[0].kind == 'ident'):
                self.add(t, 'sync-enter-argument',
                         'the lock passed to objc_sync_enter must be a constant evaluated once (a single '
                         'identifier); not a forced unwrap, optional chain or other expression')
            arg_text = [a.text for a in arg]
            next_line = self.lines[close] + 1
            line_toks = [j for j in range(close + 1, len(toks)) if self.lines[j] == next_line]
            expected = ['defer', '{', 'objc_sync_exit', '('] + arg_text + [')', '}']
            got = [toks[j].text for j in line_toks]
            if got == expected:
                paired_exits.add(line_toks[2])
            else:
                self.add(t, 'sync-pairing', 'objc_sync_enter not followed on the next line by '
                                            '"defer { objc_sync_exit(%s) }"' % ''.join(arg_text))
        for k, t in enumerate(toks):
            if t.kind == 'ident' and t.text == 'objc_sync_exit' and k not in paired_exits and \
                    self.is_punct(k + 1, '('):
                self.add(t, 'sync-pairing',
                         'objc_sync_exit outside the defer on the line after its objc_sync_enter')


def lint_source_full(path, text):
    """Lints one Swift source. Returns (findings, marked unsafe uses, marked implicitly unwrapped types, markers
    covering no implicitly unwrapped type). Raises LexError."""
    lexed = lex(text)
    problem = bracket_balance_error(mask(lexed))
    if problem is not None:
        raise LexError(problem[0], 'brackets do not balance after masking comments and literals (%s); '
                                   'the lexer cannot handle this file' % problem[1])
    linter = _FileLinter(path, lexed)
    findings, marked = linter.run()
    return sorted(set(findings)), marked, linter.iuo_marked, linter.iuo_unused


def lint_source(path, text):
    """Lints one Swift source. Returns (findings, marked unsafe uses). Raises LexError."""
    return lint_source_full(path, text)[:2]


# ---------------------------------------------------------------------------
# Git and file access

class Repo(object):
    def __init__(self, root):
        self.root = root

    def run(self, args, check=True):
        try:
            p = subprocess.run(['git', '-c', 'core.quotePath=false'] + args, cwd=self.root,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as e:
            raise EnvironmentProblem('cannot run git: %s' % e)
        if check and p.returncode != 0:
            raise EnvironmentProblem('git %s failed: %s' % (' '.join(args),
                                                            p.stderr.decode('utf-8', 'replace').strip()))
        return p

    def out(self, args):
        return self.run(args).stdout.decode('utf-8', 'surrogateescape')

    def has_head(self):
        return self.run(['rev-parse', '--verify', '-q', 'HEAD^{commit}'], check=False).returncode == 0

    def resolve(self, rev):
        p = self.run(['rev-parse', '--verify', '-q', rev + '^{commit}'], check=False)
        if p.returncode != 0:
            raise UsageError('not a commit: %s' % rev)
        return p.stdout.decode().strip()


def _split_z(s):
    parts = s.split('\0')
    if parts and parts[-1] == '':
        parts.pop()
    return parts


def _name_status(parts):
    """Parses git --name-status -z output into (status, path, new_path_or_None) tuples."""
    out = []
    i = 0
    while i < len(parts):
        st = parts[i].strip()
        if not st:
            i += 1
            continue
        if st[0] in 'RC':
            out.append((st[0], parts[i + 1], parts[i + 2]))
            i += 3
        else:
            out.append((st[0], parts[i + 1], None))
            i += 2
    return out


def port_commits(repo, rev):
    """Returns (commits, problems): {hash: [units]} for commits reachable from rev with a kind=port
    Swift-Port trailer, and the trailer problems inventory.py reports."""
    args = list(inv.GIT_LOG_TRAILER_ARGS)
    if args[1] != 'HEAD':
        raise EnvironmentProblem('inventory.GIT_LOG_TRAILER_ARGS has changed shape; cannot reuse it')
    args[1] = rev
    log = repo.out(args)
    commits = OrderedDict()
    problems = []
    for record in log.split('\x1e'):
        if not record.strip('\n').strip():
            continue
        try:
            units, probs = inv.parse_trailers(record + '\x1e')
        except inv.InventoryError as e:
            raise EnvironmentProblem(str(e))
        problems.extend(probs)
        ported = [u for u, info in units.items() if 'port' in info['kinds']]
        if ported:
            commits[record.strip('\n').split('\x1f')[0].strip()] = ported
    return commits, problems


EMPTY_TREE = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

# How a path became a migration file. commit and unit: the port commit and unit that created it; for a file
# carried over, the commit that added it and the units of the files it touched; for a re-added path, the commit
# that re-added it. origins: for a carried-over file, the migration files the commit touched (their paths
# before the commit), else None. touched: for a carried-over file, what the commit did to them (a phrase), else
# None. renames: ((old path, new path, commit), ...) for the renames followed since. readded: whether case 4
# made it a migration file. prior: for a re-added path, the commit that last made the path a migration file
# before, else None.
MigInfo = namedtuple('MigInfo', 'commit unit origins touched renames readded prior')
# The result of migration_files. files: {path: MigInfo}. commits: {port commit: [units]}. problems: trailer
# problems, including port commits that are merges. deleted_by: {commit: [migration files it deleted]}. ever:
# {path: (commit, unit)} for every path that was ever a migration file, with the commit that last made it one.
# port_modified: {path: [commits]} for Swift files that port commits, or commits that touched migration files,
# modified while they were not migration files. merges: the port commits that are merges. touched_by: {commit:
# the migration files it modified, renamed or deleted (their paths before it)}.
History = namedtuple('History', 'files commits problems deleted_by ever port_modified merges touched_by')
MERGE_PROBLEM = 'port commit %s is a merge; its files are not identified; the process requires linear history'


def touch_phrase(modified, renamed, deleted):
    """What a change did to migration files, as a verb phrase: 'modifies migration file(s) A, deletes ...'."""
    parts = []
    if modified:
        parts.append('modifies migration file(s) %s' % ', '.join(modified))
    if renamed:
        parts.append('renames migration file(s) %s' % ', '.join('%s to %s' % r for r in renamed))
    if deleted:
        parts.append('deletes migration file(s) %s' % ', '.join(deleted))
    return ', '.join(parts)


def carry_over(phrase, added):
    """The carry-over rule: when a change modifies, renames or deletes a migration file (phrase says which, and
    is empty when it does none of these), each Swift file it adds that no rename follows is a migration file.
    Returns {added path: reason}."""
    if not phrase:
        return OrderedDict()
    reason = 'treated as a migration file because this change %s and adds this file' % phrase
    return OrderedDict((p, reason) for p in sorted(added))


def swift_files_text(paths, qualifier):
    """'N Swift file(s) <qualifier> (a, b, c, d, e, and K more)', naming up to five."""
    names = ', '.join(paths[:5]) + (', and %d more' % (len(paths) - 5) if len(paths) > 5 else '')
    return '%d Swift file%s %s (%s)' % (len(paths), '' if len(paths) == 1 else 's', qualifier, names)


def undecided_message(added, modified, message, pprobs):
    """The usage error for a staged change whose added files or changed lines depend on the pending message."""
    what = []
    if added:
        what.append('adds Swift files (%s)' % ', '.join(added))
    if modified:
        what.append('modifies ' + swift_files_text(modified, 'that is not a migration file' if len(modified) == 1
                                                   else 'that are not migration files'))
    subject = ' and '.join(what) + (',' if added and modified else '')
    if added and modified:
        question = 'whether the files it adds are migration files or whether the lines it changes are ported lines'
    elif added:
        question = 'whether they are migration files'
    else:
        question = 'whether the lines it changes are ported lines'
    if not message:
        return ('the staged change %s and this tool cannot tell %s without --message FILE holding the pending '
                'commit message; pass --not-a-port if the commit is not a port commit' % (subject, question))
    return ('the staged change %s and the pending commit message has no usable Swift-Port trailer (%s), so this tool '
            'cannot tell %s; %sfix the trailer, or pass --not-a-port if the commit is not a port commit'
            % (subject, '; '.join('%s: %s' % (q['problem'], q['line']) for q in pprobs), question,
               'the modified Swift files were not checked; ' if modified else ''))


def readd_reason(commit):
    return ('treated as a migration file because the path was a migration file before (made one by commit %s)'
            % commit[:12])


def migration_files(repo, rev):
    """Returns a History for rev: the migration files at rev and how each became one (later renames are
    followed), and what the walk saw on the way."""
    if rev is None:
        return History(OrderedDict(), OrderedDict(), [], {}, {}, OrderedDict(), [], {})
    commits, problems = port_commits(repo, rev)
    files = OrderedDict()
    deleted_by = {}
    ever = {}
    port_modified = OrderedDict()
    touched_by = {}
    if not commits:
        return History(files, commits, problems, deleted_by, ever, port_modified, [], {})
    oldest = list(commits)[-1]
    merge_set = set(repo.out(['rev-list', '--merges', rev, '--not', oldest + '^@']).split())
    merges = [c for c in commits if c in merge_set]
    problems = problems + [{'commit': c, 'problem': MERGE_PROBLEM % c, 'line': 'exit status 2'} for c in merges]
    walk = ['log', '--reverse', '--topo-order', '--name-status', '-z', '--format=%x1e%H', rev, '--not',
            oldest + '^@']

    def per_commit(out):
        result = OrderedDict()
        for record in out.split('\x1e'):
            if not record:
                continue
            head, _, rest = record.partition('\0')
            result[head.strip()] = _name_status(_split_z(rest.lstrip('\n')))
        return result

    # Which paths a commit adds is read with rename detection off: a path that exists after the commit and
    # not before it is added, whatever git would pair it with. Renames are detected separately, only to
    # follow a migration file (or a file whose ported lines are listed) to a new Swift path.
    changes = per_commit(repo.out(walk[:1] + ['--no-renames'] + walk[1:]))
    renames = per_commit(repo.out(walk[:1] + ['-M', '--diff-filter=R'] + walk[1:]))
    for h, entries in changes.items():
        is_port = h in commits
        followed = swift_renames(renames.get(h, []), files)
        for new, old in followed.items():
            info = files.pop(old)
            files[new] = info._replace(renames=info.renames + ((old, new, h),))
            ever[new] = (h, info.unit)
        for st, old, new in renames.get(h, []):
            if st == 'R' and old in port_modified and new.endswith('.swift'):
                port_modified[new] = port_modified.pop(old)
        modified = sorted(p for st, p, _ in entries if st in 'MT' and p in files)
        deleted = sorted(p for st, p, _ in entries if st == 'D' and p in files)
        renamed = sorted((old, new) for new, old in followed.items())
        touched = sorted(modified + deleted + [old for old, _ in renamed])
        phrase = touch_phrase(modified, renamed, deleted)
        units = ', '.join(sorted(set(files[p].unit for p in modified + deleted + [new for _, new in renamed])))
        added = [path for st, path, _ in entries if st == 'A' and path.endswith('.swift') and path not in followed]
        for path in deleted:
            files.pop(path)
        for st, path, _ in entries:
            if st == 'D':
                port_modified.pop(path, None)
        if deleted:
            deleted_by[h] = deleted
        if touched:
            touched_by[h] = touched
        if is_port or touched:
            for st, path, _ in entries:
                if st in 'MT' and path.endswith('.swift') and path not in files:
                    port_modified.setdefault(path, []).append(h)
        for path in added:
            if is_port:
                files[path] = MigInfo(h, commits[h][0], None, None, (), False, None)
            elif touched:
                files[path] = MigInfo(h, units, touched, phrase, (), False, None)
            elif path in ever:
                files[path] = MigInfo(h, ever[path][1], None, None, (), True, ever[path][0])
            else:
                continue
            ever[path] = (h, files[path].unit)
            port_modified.pop(path, None)
    missing = [c for c in commits if c not in changes]
    if missing:
        raise EnvironmentProblem('port commits not in the history walked from %s (the commits reachable from it '
                                 'and not from the parents of the oldest port commit, %s): %s'
                                 % (rev, oldest, ', '.join(missing)))
    return History(OrderedDict(sorted(files.items())), commits, problems, deleted_by, ever, port_modified, merges,
                   touched_by)


def swift_renames(entries, migration):
    """{new path: old path} for the renames among name-status entries from a migration file to a Swift path:
    the destination inherits the source's status. Any other rename (Foo.m to Foo.swift, or a Swift file that
    is not a migration file to another Swift path) is, for this tool, an addition of its destination."""
    return OrderedDict((new, path) for st, path, new in entries
                       if st == 'R' and path in migration and path.endswith('.swift') and new.endswith('.swift'))


def pending_message_is_port(repo, message_path):
    """Returns (is_port, problems) for a pending commit message, read the way git reads trailers."""
    try:
        with open(message_path, 'rb') as f:
            body = f.read().decode('utf-8')
    except (OSError, UnicodeDecodeError) as e:
        raise UsageError('cannot read the message file %s: %s' % (message_path, e))
    try:
        p = subprocess.run(['git', 'interpret-trailers', '--parse'], input=body.encode('utf-8'),
                           cwd=repo.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        raise EnvironmentProblem('cannot run git: %s' % e)
    if p.returncode != 0:
        raise EnvironmentProblem('git interpret-trailers failed: %s' % p.stderr.decode('utf-8', 'replace'))
    trailers = [line for line in p.stdout.decode('utf-8').split('\n')
                if line.partition(':')[0].strip().lower() == 'swift-port']
    record = 'STAGED\x1f0000-00-00\x1f%s\x1f%s\x1e' % (body, '\x1d'.join(trailers))
    units, problems = inv.parse_trailers(record)
    return any('port' in u['kinds'] for u in units.values()), problems


_HUNK_RE = re.compile(r'@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')


def added_ranges(repo, diff_args, path):
    """The line ranges [(first, last)] of the new side of path that a change added or changed, from git diff -U0
    with rename and copy detection off. A hunk that only deletes lines after new-side line N touches lines N and
    N + 1, the lines on either side of the deletion. diff_args selects the change: ['--cached'] or [base, rev]."""
    out = repo.out(['diff', '-U0', '--no-renames', '--no-color', '--no-ext-diff', '--no-textconv'] + diff_args +
                   ['--', ':(literal)' + path])
    ranges = []
    for line in out.split('\n'):
        m = _HUNK_RE.match(line)
        if not m:
            continue
        first = int(m.group(1))
        count = 1 if m.group(2) is None else int(m.group(2))
        if count == 0:
            # Lines deleted only, between new-side lines first and first + 1 (first is 0 at the top of the file).
            first, last = max(first, 1), first + 1
        else:
            last = first + count - 1
        if ranges and ranges[-1][1] + 1 >= first:
            ranges[-1] = (ranges[-1][0], max(ranges[-1][1], last))
        else:
            ranges.append((first, last))
    return ranges


def paired_lines(finding):
    """The lines a finding is about: its own, and for the lints that pair two lines, the other one (the line
    above for an unsafe use, which holds the marker; the next line for objc_sync_enter, which holds the defer;
    the line above for a stray objc_sync_exit; the line above for an implicitly unwrapped type, where its marker
    may be)."""
    if finding.lint in ('unsafe-pointer-unmarked', 'iuo-unmarked'):
        return (finding.line - 1, finding.line)
    if finding.lint == 'sync-pairing':
        if finding.message.startswith('objc_sync_enter'):
            return (finding.line, finding.line + 1)
        return (finding.line - 1, finding.line)
    return (finding.line,)


def in_ranges(lines, ranges):
    return any(first <= ln <= last for ln in lines for first, last in ranges)


def history_warnings(repo):
    """Warnings for a history in which port commits may be invisible: a shallow clone, or replace refs."""
    reasons = []
    if repo.out(['rev-parse', '--is-shallow-repository']).strip() == 'true':
        reasons.append('the repository is shallow')
    if repo.out(['replace', '-l']).strip():
        reasons.append('the repository has replace refs')
    return ['WARNING: the history is incomplete (%s); port commits beyond the visible history cannot be seen, '
            'so migration files may be missed.' % r for r in reasons]


class Source(object):
    """Where file contents come from: the working tree, the index, or a commit."""

    def __init__(self, repo, where, rev=None):
        self.repo = repo
        self.where = where  # 'worktree', 'index', 'commit'
        self.rev = rev

    def describe(self):
        return {'worktree': 'the working tree', 'index': 'the index (staged contents)',
                'commit': 'commit %s' % self.rev}[self.where]

    def read_bytes(self, path):
        if self.where == 'worktree':
            with open(os.path.join(self.repo.root, path), 'rb') as f:
                return f.read()
        spec = (':' + path) if self.where == 'index' else (self.rev + ':' + path)
        p = self.repo.run(['cat-file', 'blob', spec], check=False)
        if p.returncode != 0:
            raise OSError(p.stderr.decode('utf-8', 'replace').strip())
        return p.stdout

    def read_text(self, path):
        return self.read_bytes(path).decode('utf-8')

    def ls(self, pattern):
        if self.where == 'commit':
            out = self.repo.out(['ls-tree', '-r', '-z', '--name-only', self.rev])
            names = _split_z(out)
            rx = re.compile(pattern)
            return [p for p in names if rx.search(p)]
        args = ['ls-files', '-z']
        out = self.repo.out(args)
        rx = re.compile(pattern)
        return [p for p in _split_z(out) if rx.search(p)]

    def grep_marker(self):
        """Returns {path: [(line, column)]} for every tracked file containing the frozen-reference marker."""
        args = ['grep', '-n', '-I', '-F', '-z', '--column', FROZEN_MARKER]
        if self.where == 'index':
            args.insert(1, '--cached')
        elif self.where == 'commit':
            args.append(self.rev)
        p = self.repo.run(args, check=False)
        if p.returncode not in (0, 1):
            raise EnvironmentProblem('git grep failed: %s' % p.stderr.decode('utf-8', 'replace').strip())
        hits = OrderedDict()
        for line in p.stdout.decode('utf-8', 'surrogateescape').split('\n'):
            if not line:
                continue
            parts = line.split('\0')
            if len(parts) < 4:
                continue
            path = parts[0]
            if self.where == 'commit' and path.startswith(self.rev + ':'):
                path = path[len(self.rev) + 1:]
            if any(path.startswith(pfx) for pfx in MARKER_EXCLUDED_PREFIXES):
                continue
            content = '\0'.join(parts[3:])
            col = content.find(FROZEN_MARKER) + 1
            hits.setdefault(path, []).append((int(parts[1]), col))
        return hits


# ---------------------------------------------------------------------------
# Target membership for the frozen-reference check

def _target_membership(source, pbx_path):
    """Returns {repo path: [(target, is_test)]} for one project, from its Sources phases and its
    synchronized folders."""
    text = source.read_text(pbx_path)
    plist = inv.parse_pbxproj(text)
    project_dir = os.path.dirname(os.path.dirname(pbx_path))
    membership, _, _ = inv.compute_target_membership(plist, project_dir, read_file=None)
    objects = plist['objects']
    root = objects[plist['rootObject']]
    kinds = {}
    names = {}
    for tid in root.get('targets', []):
        tobj = objects.get(tid, {})
        names[tid] = tobj.get('name')
        kinds[tobj.get('name')] = tobj.get('productType', '') in TEST_PRODUCT_TYPES
    result = {}
    for path, entries in membership.items():
        result[path] = [(e['target'], kinds[e['target']]) for e in entries]
    # Synchronized folders: every file under the folder belongs to the targets that list it, except
    # files named in a build-file exception set for that target; such a set names, for any other
    # target, files that belong to it.
    parent = {}
    for oid, obj in objects.items():
        for child in obj.get('children', []) if obj.get('isa') in ('PBXGroup', 'PBXVariantGroup') else []:
            parent[child] = oid

    def group_path(oid):
        parts = []
        cur = oid
        while cur is not None:
            obj = objects.get(cur, {})
            tree = obj.get('sourceTree', '<group>')
            if obj.get('path'):
                parts.append(obj['path'])
            if tree == 'SOURCE_ROOT':
                break
            if tree not in ('<group>',):
                return None
            cur = parent.get(cur)
        return os.path.normpath(os.path.join(project_dir, *reversed(parts))) if parts else project_dir

    owners = {}
    for tid in root.get('targets', []):
        for gid in objects.get(tid, {}).get('fileSystemSynchronizedGroups', []):
            owners.setdefault(gid, []).append(tid)
    synced = []
    for gid in sorted(owners):
        g = objects.get(gid, {})
        gpath = group_path(gid)
        if gpath is None:
            raise EnvironmentProblem('%s: cannot resolve the path of synchronized folder %s' % (pbx_path, gid))
        # A build-file exception set names files that its target does not include, when that target
        # lists the folder, or does include, when it does not.
        toggled = {}
        for eid in g.get('exceptions', []):
            e = objects.get(eid, {})
            if e.get('isa') != 'PBXFileSystemSynchronizedBuildFileExceptionSet':
                continue
            files = set(os.path.normpath(os.path.join(gpath, x)) for x in e.get('membershipExceptions', []))
            toggled.setdefault(e.get('target'), set()).update(files)
        for tid in owners[gid]:
            synced.append((gpath, names[tid], kinds[names[tid]], 'except', toggled.get(tid, set())))
        for tid, files in toggled.items():
            if tid not in owners[gid] and tid in names:
                synced.append((gpath, names[tid], kinds[names[tid]], 'only', files))
    return result, synced


def frozen_reference_findings(source):
    """Returns (findings, summary) for the frozen-reference check over the inspected tree."""
    hits = source.grep_marker()
    summary = OrderedDict([('files_with_marker', len(hits)), ('in_no_target', []), ('test_targets_only', []),
                           ('projects', 0)])
    if not hits:
        return [], summary
    projects = [p for p in source.ls(r'\.pbxproj$')
                if not any(p.startswith(x) for x in MARKER_EXCLUDED_PREFIXES)]
    summary['projects'] = len(projects)
    members = {}
    synced_all = []
    for pbx in sorted(projects):
        try:
            result, synced = _target_membership(source, pbx)
        except (OSError, UnicodeDecodeError, inv.InventoryError, KeyError, ValueError) as e:
            raise EnvironmentProblem('cannot read project %s: %s' % (pbx, e))
        for path, entries in result.items():
            members.setdefault(path, []).extend(entries)
        synced_all.extend(synced)
    findings = []
    for path, positions in hits.items():
        entries = list(members.get(path, []))
        for gpath, tname, is_test, how, files in synced_all:
            under = path.startswith(gpath + '/')
            if (how == 'except' and under and path not in files) or (how == 'only' and path in files):
                entries.append((tname, is_test))
        non_test = sorted(set(t for t, test in entries if not test))
        if not entries:
            summary['in_no_target'].append(path)
        elif not non_test:
            summary['test_targets_only'].append(path)
        for line, col in positions:
            if non_test:
                findings.append(Finding(path, line, col, 'frozen-reference-target',
                                        'file with the frozen-reference marker is a member of non-test '
                                        'target(s): %s' % ', '.join(non_test)))
    return findings, summary


# ---------------------------------------------------------------------------
# Modes

def in_scope(path):
    if path.startswith('submodules/'):
        return False
    return any(path == r or path.startswith(r + '/') for r in SCOPE_ROOTS)


def renames_text(info):
    """', renamed to X by C, ..., renamed to this path by C' for the renames followed since info's commit."""
    out = []
    for i, (_, new, commit) in enumerate(info.renames):
        out.append(', renamed to %s by %s' % ('this path' if i == len(info.renames) - 1 else new, commit[:12]))
    return ''.join(out)


def describe_migration_file(path, info):
    """One line of the tree mode summary: how path became a migration file."""
    first = info.renames[0][0] if info.renames else None
    if info.touched is not None:
        return '  %s (treated as a migration file because commit %s %s and adds %s%s; unit %s)' % (
            path, info.commit[:12], info.touched, 'it as %s' % first if first else 'this file', renames_text(info),
            info.unit)
    if info.readded:
        return '  %s (re-added%s by %s at a path that was a migration file%s; unit %s)' % (
            path, ' as %s' % first if first else '', info.commit[:12], renames_text(info), info.unit)
    if first:
        return '  %s (created as %s by %s%s, unit %s)' % (path, first, info.commit[:12], renames_text(info), info.unit)
    return '  %s (created by %s, unit %s)' % (path, info.commit[:12], info.unit)


def select(repo, args):
    """Returns (source, files_to_lint, ported, selection summary), where ported is {path: [(first, last)]}: the
    Swift files that are not migration files whose ported lines are linted, with the line ranges the change
    added or changed."""
    sel = OrderedDict()
    ported = OrderedDict()
    reasons = OrderedDict()  # {path in ported: why its changed lines are linted}, for changes that are not ports
    if args.all_swift:
        source = Source(repo, 'worktree')
        tracked = source.ls(r'\.swift$')
        files = sorted(p for p in tracked if in_scope(p))
        sel['mode'] = 'all-swift'
        sel['description'] = ('every tracked Swift file under the scope roots of README.md section 2 (%s), '
                              'in the working tree, whether or not it is a migration file'
                              % ', '.join(SCOPE_ROOTS))
        sel['swift_files_considered'] = len(tracked)
        sel['files_linted'] = len(files)
        sel['skipped'] = OrderedDict([('outside the scope roots', len(tracked) - len(files))])
        return source, files, ported, sel
    if args.staged:
        source = Source(repo, 'index')
        head = 'HEAD' if repo.has_head() else None
        hist = migration_files(repo, head)
        problems = hist.problems
        pending_port = False
        pprobs = []
        if args.message:
            pending_port, pprobs = pending_message_is_port(repo, args.message)
            problems = problems + pprobs
        diff_args = ['diff', '--cached', '--name-status', '-z']
        if head is None:
            diff_args.append(EMPTY_TREE)
        # As in migration_files: additions with rename detection off, renames only to follow Swift files.
        changes = _name_status(_split_z(repo.out(diff_args[:2] + ['--no-renames'] + diff_args[2:])))
        mig = OrderedDict(hist.files)
        followed = swift_renames(_name_status(_split_z(repo.out(diff_args[:2] + ['-M', '--diff-filter=R'] +
                                                                diff_args[2:]))), mig)
        for new, old in followed.items():
            mig[new] = mig.pop(old)
        modified = sorted(p for st, p, _ in changes if st in 'MT' and p in mig)
        deleted = sorted(p for st, p, _ in changes if st == 'D' and p in mig)
        renamed = sorted((old, new) for new, old in followed.items())
        for path in deleted:
            mig.pop(path)
        touched_swift = sorted(set(p for st, p, _ in changes if st != 'D' and p.endswith('.swift')))
        added = [p for st, p, _ in changes if st == 'A' and p.endswith('.swift') and p not in followed]
        phrase = touch_phrase(modified, renamed, deleted)
        carried = OrderedDict() if pending_port else carry_over(phrase, added)
        readded = OrderedDict() if pending_port else OrderedDict(
            (p, readd_reason(hist.ever[p][0])) for p in sorted(added) if p not in carried and p in hist.ever)
        undecided = [p for p in added if p not in mig and p not in carried and p not in readded]
        modified_swift = set(p for st, p, _ in changes if st in 'MT' and p.endswith('.swift'))
        # A change that touches a migration file lints the changed lines of the other Swift files it modifies,
        # so they are decided; otherwise whether they are ported lines depends on the pending message.
        undecided_modified = [] if phrase else sorted(p for p in modified_swift if p not in mig)
        if (undecided or undecided_modified) and not args.not_a_port and not pending_port and \
                (not args.message or pprobs):
            raise UsageError(undecided_message(undecided, undecided_modified, args.message, pprobs))
        touch_reason = ''
        if phrase and not pending_port:
            touch_reason = 'this change also touches migration file(s) %s' % ', '.join(
                sorted(modified + deleted + [old for old, _ in renamed]))
        files = []
        skipped_not_migration = 0
        skipped_added = 0
        by_message = 0
        for p in touched_swift:
            if p in mig:
                files.append(p)
            elif p in added and pending_port:
                files.append(p)
                by_message += 1
            elif p in carried or p in readded:
                files.append(p)
            elif p in modified_swift and (pending_port or touch_reason):
                ported[p] = added_ranges(repo, ['--cached'], p)
                if touch_reason:
                    reasons[p] = touch_reason
            elif p in added:
                skipped_added += 1
            else:
                skipped_not_migration += 1
        sel['mode'] = 'staged'
        if args.not_a_port:
            adds = '; the files the change adds are not migration files, by --not-a-port'
        elif not args.message:
            adds = ''
        elif pending_port:
            adds = (', plus the files the change adds, because the pending message has a kind=port trailer, and the '
                    'ported lines of the other Swift files it modifies')
        else:
            adds = ('; the files the change adds are not migration files, because the pending message does not '
                    'have a kind=port trailer')
        if carried:
            adds = ('; the files the change adds are migration files by the carry-over rule, since it modifies, '
                    'renames or deletes migration files')
        if readded:
            adds += '; the files it adds at paths that were migration files are migration files again'
        if touch_reason:
            adds += ('; the lines it adds or changes in the other Swift files it modifies are linted, since it '
                     'touches migration files')
        sel['description'] = ('Swift files added, modified or renamed by the staged change, as staged; '
                              'migration files by the trailer history at HEAD' + adds)
        sel['swift_files_considered'] = len(touched_swift)
        sel['files_linted'] = len(files)
        sel['identified_by_message'] = by_message
        sel['deleted_migration_files'] = deleted
        sel['carried_over'] = carried
        sel['readded'] = readded
        sel['port_change'] = pending_port
        added_reason = ('added by the staged change, which --not-a-port says is not a port commit'
                        if args.not_a_port else
                        'added by the staged change without a kind=port trailer in --message')
        sel['skipped'] = OrderedDict([('not a migration file', skipped_not_migration),
                                      (added_reason, skipped_added)])
        sel['port_commits'] = len(hist.commits)
        sel['trailer_problems'] = problems
        sel['merge_port_commits'] = hist.merges
        sel['ported_reasons'] = reasons
        return source, files, ported, sel
    if args.rev:
        rev = repo.resolve(args.rev)
        source = Source(repo, 'commit', rev)
        hist = migration_files(repo, rev)
        mig = hist.files
        parents = repo.out(['rev-list', '--parents', '-n', '1', rev]).split()[1:]
        base = parents[0] if parents else EMPTY_TREE
        changes = _name_status(_split_z(repo.out(['diff-tree', '-r', '--no-renames', '--name-status', '-z', base,
                                                  rev])))
        touched = sorted(set(path for st, path, _ in changes if st != 'D' and path.endswith('.swift')))
        is_port = rev in hist.commits
        touch_reason = '' if is_port or rev not in hist.touched_by else (
            'this change also touches migration file(s) %s' % ', '.join(hist.touched_by[rev]))
        files = [p for p in touched if p in mig]
        for st, path, _ in changes:
            if (is_port or touch_reason) and st in 'MT' and path.endswith('.swift') and path not in mig:
                ported[path] = added_ranges(repo, [base, rev], path)
                if touch_reason:
                    reasons[path] = touch_reason
        ported = OrderedDict(sorted(ported.items()))
        sel['mode'] = 'commit'
        sel['description'] = ('Swift files added, modified or renamed by %s relative to its first parent, as '
                              'they are in it; migration files by the trailer history at %s%s'
                              % (rev, rev, '; it is a port commit, so also the ported lines of the other Swift '
                                           'files it modifies' if is_port else
                                 '; it touches migration files, so also the lines it adds or changes in the other '
                                 'Swift files it modifies' if touch_reason else ''))
        sel['swift_files_considered'] = len(touched)
        sel['files_linted'] = len(files)
        sel['skipped'] = OrderedDict([('not a migration file', len(touched) - len(files) - len(ported))])
        sel['deleted_migration_files'] = hist.deleted_by.get(rev, [])
        sel['carried_over'] = OrderedDict()
        sel['readded'] = OrderedDict()
        sel['port_change'] = is_port
        for p in files:
            info = mig[p]
            if info.commit == rev and info.touched is not None:
                sel['carried_over'].update(carry_over(info.touched, [p]))
            elif info.commit == rev and info.readded:
                sel['readded'][p] = readd_reason(info.prior)
        sel['port_commits'] = len(hist.commits)
        sel['trailer_problems'] = hist.problems
        sel['merge_port_commits'] = hist.merges
        sel['ported_reasons'] = reasons
        return source, files, ported, sel
    source = Source(repo, 'worktree')
    head = 'HEAD' if repo.has_head() else None
    hist = migration_files(repo, head)
    mig = hist.files
    tracked = source.ls(r'\.swift$')
    files = sorted(p for p in tracked if p in mig)
    sel['mode'] = 'tree'
    sel['description'] = ('every tracked Swift file in the working tree that is a migration file by the '
                          'trailer history at HEAD')
    sel['swift_files_considered'] = len(tracked)
    sel['files_linted'] = len(files)
    sel['skipped'] = OrderedDict([('not a migration file', len(tracked) - len(files))])
    sel['port_commits'] = len(hist.commits)
    sel['trailer_problems'] = hist.problems
    sel['merge_port_commits'] = hist.merges
    sel['migration_files'] = OrderedDict()
    descriptions = []
    for p, info in mig.items():
        if p not in files:
            continue
        entry = OrderedDict([('commit', info.commit), ('unit', info.unit)])
        if info.origins is not None:
            entry['carried_over_from'] = info.origins
        if info.readded:
            entry['readded'] = True
        if info.renames:
            entry['created_as'] = info.renames[0][0]
            entry['renames'] = [OrderedDict([('from', old), ('to', new), ('commit', c)])
                                for old, new, c in info.renames]
        sel['migration_files'][p] = entry
        descriptions.append(describe_migration_file(p, info))
    sel['migration_file_descriptions'] = descriptions
    by_reason = OrderedDict([('created by a port commit', 0), ('renamed from a migration file', 0),
                             ('carried over', 0), ('re-added', 0)])
    for p in sel['migration_files']:
        info = mig[p]
        by_reason['carried over' if info.touched is not None else 're-added' if info.readded else
                  'renamed from a migration file' if info.renames else 'created by a port commit'] += 1
    sel['migration_files_by_reason'] = by_reason
    tracked_set = set(tracked)
    sel['ported_lines_not_linted'] = OrderedDict(
        (p, cs) for p, cs in sorted(hist.port_modified.items()) if p in tracked_set and p not in mig)
    return source, files, ported, sel


def run(argv):
    parser = argparse.ArgumentParser(
        prog='swift_lints.py', formatter_class=argparse.RawDescriptionHelpFormatter,
        description='Lints for migration Swift (docs/swift-migration/phase0.md section 6).\n\n'
                    'Which files: ' + MIGRATION_RULE,
        epilog='Exit status: 0 no findings, 1 findings (including findings on ported lines), 2 usage or '
               'environment error (including a file that cannot be read, is not UTF-8, or that the lexer cannot '
               'handle, a port commit that is a merge, and in tree mode an incomplete history without '
               '--allow-incomplete-history).\n\n' + DECIDED_NOT_IMPLEMENTED)
    parser.add_argument('rev', nargs='?', help='lint the migration files this commit touches, and the ported lines '
                                               '(added or changed lines) of the other Swift files it modifies when '
                                               'it is a port commit or touches a migration file')
    parser.add_argument('--staged', action='store_true', help='lint the migration files the staged change touches')
    parser.add_argument('--message', metavar='FILE',
                        help='the pending commit message, required with --staged unless --not-a-port is given, '
                             'because whether the Swift files the change adds are migration files, and whether the '
                             'lines it changes in other Swift files are ported lines, depends on whether the commit '
                             'is a port commit (without either, a change that adds or modifies such files exits '
                             '2); a kind=port trailer makes the files the change adds migration files, and the '
                             'ported lines of the other Swift files it modifies are linted')
    parser.add_argument('--not-a-port', action='store_true',
                        help='with --staged and without --message: the pending commit is not a port commit, so '
                             'the Swift files the change adds are not migration files, unless the carry-over '
                             'rule makes them so (the change modifies, renames or deletes migration files) or '
                             'their paths were migration files, and the lines it changes in other Swift files '
                             'are not ported lines unless it touches migration files')
    parser.add_argument('--allow-incomplete-history', action='store_true',
                        help='in tree mode, lint what the visible history identifies when the repository is '
                             'shallow or has replace refs, instead of exiting 2 (the warning is still printed)')
    parser.add_argument('--all-swift', action='store_true',
                        help='run every lint on every tracked Swift file in scope (a survey)')
    parser.add_argument('--list-iuo', action='store_true',
                        help='list every implicitly unwrapped type marked with "// SWIFT-MIGRATION-IUO: <reason>" '
                             '(file, line, column and reason), and every such marker that covers none, in every '
                             'tracked Swift file in the working tree outside %s; exit status 0, or 2 for a file '
                             'that cannot be read or lexed' % ', '.join(LIST_IUO_EXCLUDED_PREFIXES))
    parser.add_argument('--json', action='store_true', help='print JSON')
    parser.add_argument('--repo', metavar='DIR', help='the repository (default: the one containing the cwd)')
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else 2
    if sum(bool(x) for x in (args.rev, args.staged, args.all_swift, args.list_iuo)) > 1:
        print('swift_lints.py: choose one of REV, --staged, --all-swift and --list-iuo', file=sys.stderr)
        return 2
    if args.message and not args.staged:
        print('swift_lints.py: --message needs --staged', file=sys.stderr)
        return 2
    if args.not_a_port and (not args.staged or args.message):
        print('swift_lints.py: --not-a-port needs --staged and cannot be combined with --message', file=sys.stderr)
        return 2
    try:
        start = args.repo or os.getcwd()
        p = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=start, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)
        if p.returncode != 0:
            print('swift_lints.py: not in a git repository: %s' % start, file=sys.stderr)
            return 2
        repo = Repo(p.stdout.decode().strip())
        if args.list_iuo:
            return list_iuo(repo, args.json)
        source, files, ported, sel = select(repo, args)
        warnings = history_warnings(repo)
        sel['history_warnings'] = warnings
        sel['incomplete_history_fails'] = bool(warnings) and sel['mode'] == 'tree' and \
            not args.allow_incomplete_history
        findings = []
        marked = []
        iuo_marked = []
        errors = []
        ported_lines = []

        def lint_file(path):
            try:
                text = source.read_text(path)
            except OSError as e:
                errors.append(OrderedDict([('path', path), ('error', 'cannot read: %s' % e)]))
                return None
            except UnicodeDecodeError as e:
                errors.append(OrderedDict([('path', path), ('error', 'not UTF-8: %s' % e)]))
                return None
            try:
                return lint_source_full(path, text)
            except LexError as e:
                ln, col = lex_position(text, e.offset)
                errors.append(OrderedDict([('path', path), ('line', ln), ('column', col),
                                           ('error', 'lexer cannot handle the file: %s' % e.message)]))
                return None

        for path in files:
            result = lint_file(path)
            if result is not None:
                findings.extend(result[0])
                marked.extend(result[1])
                iuo_marked.extend(result[2])
        # Ported lines: the whole file is linted, so that context is right, and only findings on the lines the
        # change added or changed are kept.
        for path, ranges in ported.items():
            result = lint_file(path)
            kept = []
            if result is not None:
                kept = [f for f in result[0] if in_ranges(paired_lines(f), ranges)]
                marked.extend(m for m in result[1] if in_ranges((m['line'] - 1, m['line']), ranges))
                iuo_marked.extend(m for m in result[2] if in_ranges((m['marker_line'], m['line']), ranges))
            entry = OrderedDict([
                ('path', path), ('ranges', [[a, b] for a, b in ranges]),
                ('findings', [OrderedDict([('path', f.path), ('line', f.line), ('column', f.col), ('lint', f.lint),
                                           ('message', f.message)]) for f in kept])])
            if path in sel.get('ported_reasons', {}):
                entry['reason'] = sel['ported_reasons'][path]
            ported_lines.append(entry)
        frozen, frozen_summary = frozen_reference_findings(source)
        findings.extend(frozen)
    except UsageError as e:
        print('swift_lints.py: %s' % e, file=sys.stderr)
        return 2
    except EnvironmentProblem as e:
        print('swift_lints.py: %s' % e, file=sys.stderr)
        return 2
    findings = sorted(set(findings))
    counts = OrderedDict((lint, 0) for lint in LINTS)
    for f in findings:
        counts[f.lint] += 1
    ported_count = 0
    for entry in ported_lines:
        for f in entry['findings']:
            counts[f['lint']] += 1
            ported_count += 1
    report = OrderedDict([
        ('selection', sel),
        ('rule', MIGRATION_RULE),
        ('source', source.describe()),
        ('findings', [OrderedDict([('path', f.path), ('line', f.line), ('column', f.col), ('lint', f.lint),
                                   ('message', f.message)]) for f in findings]),
        ('ported_lines', ported_lines),
        ('counts', counts),
        ('marked_unsafe_uses', sorted(marked, key=lambda m: (m['path'], m['line'], m['column']))),
        ('marked_iuo_sites', sorted(iuo_marked, key=lambda m: (m['path'], m['line'], m['column']))),
        ('frozen_reference', frozen_summary),
        ('errors', errors),
        ('legend', LINTS),
        ('not_checked', [OrderedDict([('rule', r), ('source', s), ('why', w)]) for r, s, w in NOT_CHECKED]),
    ])
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_text(report)
    if errors or sel.get('merge_port_commits') or sel['incomplete_history_fails']:
        return 2
    return 1 if findings or ported_count else 0


def list_iuo(repo, as_json):
    """--list-iuo: every SWIFT-MIGRATION-IUO site, and every such marker that covers no implicitly unwrapped type, in
    the tracked Swift files of the working tree outside LIST_IUO_EXCLUDED_PREFIXES. Returns the exit status."""
    source = Source(repo, 'worktree')
    paths = sorted(p for p in source.ls(r'\.swift$') if not any(p.startswith(x) for x in LIST_IUO_EXCLUDED_PREFIXES))
    sites = []
    unused = []
    errors = []
    for path in paths:
        try:
            text = source.read_text(path)
        except (OSError, UnicodeDecodeError) as e:
            errors.append(OrderedDict([('path', path), ('error', 'cannot read: %s' % e)]))
            continue
        if IUO_MARKER not in text:
            continue
        try:
            _, _, marked, stale = lint_source_full(path, text)
        except LexError as e:
            ln, col = lex_position(text, e.offset)
            errors.append(OrderedDict([('path', path), ('line', ln), ('column', col),
                                       ('error', 'lexer cannot handle the file: %s' % e.message)]))
            continue
        sites.extend(marked)
        unused.extend(stale)
    report = OrderedDict([
        ('description', 'implicitly unwrapped types marked with "// SWIFT-MIGRATION-IUO: <reason>" in the tracked '
                        'Swift files of the working tree outside %s' % ', '.join(LIST_IUO_EXCLUDED_PREFIXES)),
        ('files_read', len(paths)), ('sites', sites), ('unused_markers', unused), ('errors', errors)])
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        out = ['Swift migration: %s.' % report['description'], 'Swift files read: %d' % len(paths),
               'SWIFT-MIGRATION-IUO sites: %d' % len(sites)]
        out.extend('%s:%d:%d: %s' % (m['path'], m['line'], m['column'], m['reason']) for m in sites)
        out.append('Markers that cover no implicitly unwrapped type: %d' % len(unused))
        out.extend('%s:%d: %s' % (m['path'], m['line'], m['reason']) for m in unused)
        if errors:
            out.append('Errors (exit status 2): %d' % len(errors))
            for e in errors:
                if 'line' in e:
                    out.append('  %s:%d:%d: %s' % (e['path'], e['line'], e['column'], e['error']))
                else:
                    out.append('  %s: %s' % (e['path'], e['error']))
        print('\n'.join(out))
    return 2 if errors else 0


def lex_position(text, offset):
    line = text.count('\n', 0, offset) + 1
    col = offset - (text.rfind('\n', 0, offset) + 1) + 1
    return line, col


def print_text(r):
    sel = r['selection']
    out = []
    out.append('Swift migration lints (phase0.md section 6)')
    for w in sel.get('history_warnings', []):
        out.append(w)
    if sel.get('incomplete_history_fails'):
        out.append('Exit status 2 because the history is incomplete; pass --allow-incomplete-history to lint what the '
                   'visible history identifies.')
    out.append('Mode: %s: %s.' % (sel['mode'], sel['description']))
    out.append('Contents read from %s.' % r['source'])
    out.append('Migration files: ' + r['rule'])
    out.append('Swift files considered: %d' % sel['swift_files_considered'])
    if sel['mode'] == 'all-swift':
        out.append('Files linted: %d (all of them, regardless of migration status)' % sel['files_linted'])
    elif sel['mode'] == 'staged' and sel['identified_by_message']:
        out.append('Migration files linted: %d: %d identified by the trailer history at HEAD (%d port commit%s '
                   'found), %d that the staged change adds, identified by the kind=port trailer in the pending '
                   'commit message'
                   % (sel['files_linted'], sel['files_linted'] - sel['identified_by_message'], sel['port_commits'],
                      '' if sel['port_commits'] == 1 else 's', sel['identified_by_message']))
    else:
        carried = len(sel.get('carried_over', {}))
        by_reason = sel.get('migration_files_by_reason')
        out.append('Migration files linted: %d, identified by the trailer history (%d port commit%s found)%s'
                   % (sel['files_linted'], sel['port_commits'], '' if sel['port_commits'] == 1 else 's',
                      ': ' + ', '.join('%d %s' % (c, k) for k, c in by_reason.items()) if by_reason else
                      ' and the carry-over rule (%d, listed below)' % carried if carried else ''))
        if sel['files_linted'] == 0:
            out.append('There are no migration files%s.' % ('' if sel['mode'] == 'tree' else ' in this change'))
    for reason, count in sel['skipped'].items():
        if count:
            out.append('Skipped: %d (%s)' % (count, reason))
    out.extend(sel.get('migration_file_descriptions', []))
    if 'ported_lines_not_linted' in sel:
        listed = sel['ported_lines_not_linted']
        out.append('Ported lines in files that are not migration files are linted only when their commit is '
                   'linted (with REV or --staged), not in tree mode: %d file%s'
                   % (len(listed), '' if len(listed) == 1 else 's'))
        for m, cs in listed.items():
            out.append('  %s (commit(s) %s)' % (m, ', '.join(c[:12] for c in cs)))
    if 'deleted_migration_files' in sel:
        out.append('Migration files deleted by this change: %d' % len(sel['deleted_migration_files']))
        for m in sel['deleted_migration_files']:
            out.append('  %s' % m)
        out.append('Carried over: %d' % len(sel['carried_over']))
        for m, reason in sel['carried_over'].items():
            out.append('  %s: %s' % (m, reason))
        if sel.get('readded'):
            out.append('Re-added at paths that were migration files: %d' % len(sel['readded']))
            for m, reason in sel['readded'].items():
                out.append('  %s: %s' % (m, reason))
    probs = sel.get('trailer_problems', [])
    if probs:
        out.append('Swift-Port trailer problems (not counted unless stated): %d' % len(probs))
        for p in probs:
            out.append('  %s: %s: %s' % (p['commit'][:12], p['problem'], p['line']))
    fz = r['frozen_reference']
    out.append('Frozen-reference check (whole tree, excluding %s): %d file%s with the marker in %d project%s '
               'read; %d in no target, %d in test targets only.'
               % (' and '.join(MARKER_EXCLUDED_PREFIXES), fz['files_with_marker'],
                  '' if fz['files_with_marker'] == 1 else 's', fz['projects'], '' if fz['projects'] == 1 else 's',
                  len(fz['in_no_target']), len(fz['test_targets_only'])))
    out.append('')
    out.append('Findings: %d' % len(r['findings']))
    for f in r['findings']:
        out.append('%s:%d:%d: %s: %s' % (f['path'], f['line'], f['column'], f['lint'], f['message']))
    if sel.get('port_change') or r['ported_lines']:
        n = sum(len(e['findings']) for e in r['ported_lines'])
        out.append('')
        out.append('Ported lines in files that are not migration files: %d file%s, %d finding%s'
                   % (len(r['ported_lines']), '' if len(r['ported_lines']) == 1 else 's', n, '' if n == 1 else 's'))
        for e in r['ported_lines']:
            out.append('  %s (lines linted: %s%s)' % (e['path'], ', '.join(
                '%d' % a if a == b else '%d-%d' % (a, b) for a, b in e['ranges']) or 'none',
                '; ' + e['reason'] if 'reason' in e else ''))
            for f in e['findings']:
                out.append('    %s:%d:%d: %s: %s' % (f['path'], f['line'], f['column'], f['lint'], f['message']))
    out.append('')
    out.append('Counts per lint:')
    for lint, c in r['counts'].items():
        out.append('  %-24s %d' % (lint, c))
    out.append('')
    out.append('Marked unsafe uses (the documented exemption for unsafe-pointer-unmarked): %d'
               % len(r['marked_unsafe_uses']))
    for m in r['marked_unsafe_uses']:
        out.append('  %s:%d:%d: %s under %s: %s' % (m['path'], m['line'], m['column'], m['api'], m['marker'],
                                                   m['reason']))
    out.append('')
    out.append('Marked implicitly unwrapped types (the documented exemption for iuo-unmarked): %d'
               % len(r['marked_iuo_sites']))
    for m in r['marked_iuo_sites']:
        out.append('  %s:%d:%d: %s' % (m['path'], m['line'], m['column'], m['reason']))
    if r['errors']:
        out.append('')
        out.append('Errors (exit status 2): %d' % len(r['errors']))
        for e in r['errors']:
            if 'line' in e:
                out.append('  %s:%d:%d: %s' % (e['path'], e['line'], e['column'], e['error']))
            else:
                out.append('  %s: %s' % (e['path'], e['error']))
    out.append('')
    out.append('Legend (lint: rule and where it is stated):')
    for lint, src in r['legend'].items():
        out.append('  %s: %s' % (lint, src))
    out.append('')
    out.append('Not checked by this tool:')
    for n in r['not_checked']:
        out.append('  - %s (%s): %s' % (n['rule'], n['source'], n['why']))
    print('\n'.join(out))


def main(argv=None):
    return run(sys.argv[1:] if argv is None else argv)


if __name__ == '__main__':
    sys.exit(main())
